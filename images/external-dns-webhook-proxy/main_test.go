package main

import (
	"bytes"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// credentialSegment stands in for the token a real webhook URL carries. It is
// deliberately not shaped like any real credential.
const credentialSegment = "credential-segment-for-tests"

type recordedRequest struct {
	method      string
	path        string
	rawQuery    string
	host        string
	accept      string
	contentType string
	body        string
	forwarded   string
}

func newRecordingUpstream(t *testing.T, respond func(http.ResponseWriter, *http.Request)) (*httptest.Server, *[]recordedRequest) {
	t.Helper()
	recorded := &[]recordedRequest{}
	upstream := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		body, _ := io.ReadAll(request.Body)
		*recorded = append(*recorded, recordedRequest{
			method:      request.Method,
			path:        request.URL.Path,
			rawQuery:    request.URL.RawQuery,
			host:        request.Host,
			accept:      request.Header.Get("Accept"),
			contentType: request.Header.Get("Content-Type"),
			body:        string(body),
			forwarded:   request.Header.Get("X-Forwarded-For"),
		})
		respond(writer, request)
	}))
	t.Cleanup(upstream.Close)
	return upstream, recorded
}

func newTestProxy(t *testing.T, rawUpstream string, logOutput io.Writer) *httptest.Server {
	t.Helper()
	upstream, parseError := parseUpstreamURL(rawUpstream)
	if parseError != nil {
		t.Fatalf("parseUpstreamURL: %v", parseError)
	}
	logger := slog.New(slog.NewTextHandler(logOutput, nil))
	proxy := httptest.NewServer(newProxy(upstream, logger, newRedactor(upstream)))
	t.Cleanup(proxy.Close)
	return proxy
}

func TestProxyMapsTheWebhookProtocolOntoTheUpstreamPath(t *testing.T) {
	upstream, recorded := newRecordingUpstream(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("Content-Type", "application/external.dns.webhook+json;version=1")
		_, _ = writer.Write([]byte(`{"include":["zone.example.com"]}`))
	})
	proxy := newTestProxy(t, upstream.URL+"/api/external-dns/"+credentialSegment, io.Discard)

	cases := []struct {
		method       string
		requestPath  string
		body         string
		expectedPath string
	}{
		{http.MethodGet, "", "", "/api/external-dns/" + credentialSegment},
		{http.MethodGet, "/", "", "/api/external-dns/" + credentialSegment},
		{http.MethodGet, "/records", "", "/api/external-dns/" + credentialSegment + "/records"},
		{http.MethodPost, "/records", `{"Create":[]}`, "/api/external-dns/" + credentialSegment + "/records"},
		{http.MethodPost, "/adjustendpoints", `[]`, "/api/external-dns/" + credentialSegment + "/adjustendpoints"},
	}
	for _, testCase := range cases {
		request, _ := http.NewRequest(testCase.method, proxy.URL+testCase.requestPath, strings.NewReader(testCase.body))
		request.Header.Set("Accept", "application/external.dns.webhook+json;version=1")
		if testCase.body != "" {
			request.Header.Set("Content-Type", "application/external.dns.webhook+json;version=1")
		}
		response, requestError := http.DefaultClient.Do(request)
		if requestError != nil {
			t.Fatalf("%s %q: %v", testCase.method, testCase.requestPath, requestError)
		}
		responseBody, _ := io.ReadAll(response.Body)
		_ = response.Body.Close()
		if response.StatusCode != http.StatusOK || string(responseBody) != `{"include":["zone.example.com"]}` {
			t.Fatalf("%s %q: got %d %q", testCase.method, testCase.requestPath, response.StatusCode, responseBody)
		}
		last := (*recorded)[len(*recorded)-1]
		if last.method != testCase.method || last.path != testCase.expectedPath {
			t.Fatalf("%s %q reached upstream as %s %q, want %q", testCase.method, testCase.requestPath, last.method, last.path, testCase.expectedPath)
		}
		if last.accept != "application/external.dns.webhook+json;version=1" {
			t.Fatalf("Accept header not forwarded: %q", last.accept)
		}
		if last.body != testCase.body {
			t.Fatalf("body not forwarded: got %q want %q", last.body, testCase.body)
		}
		if last.host != strings.TrimPrefix(upstream.URL, "http://") {
			t.Fatalf("Host header %q is not the upstream host", last.host)
		}
		if last.forwarded != "" {
			t.Fatalf("the proxy must not add X-Forwarded-For, got %q", last.forwarded)
		}
	}
}

func TestProxyMergesUpstreamAndRequestQueries(t *testing.T) {
	upstream, recorded := newRecordingUpstream(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusNoContent)
	})
	proxy := newTestProxy(t, upstream.URL+"/hook?key="+credentialSegment, io.Discard)
	response, requestError := http.Get(proxy.URL + "/records?zone=a")
	if requestError != nil {
		t.Fatal(requestError)
	}
	_ = response.Body.Close()
	last := (*recorded)[len(*recorded)-1]
	if last.path != "/hook/records" || last.rawQuery != "key="+credentialSegment+"&zone=a" {
		t.Fatalf("got path %q query %q", last.path, last.rawQuery)
	}
}

func TestProxyPassesUpstreamStatusAndBodyThrough(t *testing.T) {
	upstream, _ := newRecordingUpstream(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusServiceUnavailable)
		_, _ = writer.Write([]byte(`{"error":"down"}`))
	})
	proxy := newTestProxy(t, upstream.URL+"/api/external-dns/"+credentialSegment, io.Discard)
	response, requestError := http.Get(proxy.URL + "/records")
	if requestError != nil {
		t.Fatal(requestError)
	}
	body, _ := io.ReadAll(response.Body)
	_ = response.Body.Close()
	if response.StatusCode != http.StatusServiceUnavailable || string(body) != `{"error":"down"}` {
		t.Fatalf("got %d %q", response.StatusCode, body)
	}
}

func TestProxyRewritesRedirectsIntoTheLocalPathSpace(t *testing.T) {
	upstream, _ := newRecordingUpstream(t, func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Location", "/api/external-dns/"+credentialSegment+"/records?page=2")
		writer.WriteHeader(http.StatusPermanentRedirect)
	})
	proxy := newTestProxy(t, upstream.URL+"/api/external-dns/"+credentialSegment, io.Discard)
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, requestError := client.Get(proxy.URL + "/records/")
	if requestError != nil {
		t.Fatal(requestError)
	}
	_ = response.Body.Close()
	location := response.Header.Get("Location")
	if location != "/records?page=2" {
		t.Fatalf("Location %q was not mapped into the proxy's path space", location)
	}
}

func TestProxyLeavesForeignRedirectsAlone(t *testing.T) {
	upstream, _ := newRecordingUpstream(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("Location", "https://elsewhere.example.com/login")
		writer.WriteHeader(http.StatusFound)
	})
	proxy := newTestProxy(t, upstream.URL+"/api/external-dns/"+credentialSegment, io.Discard)
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, requestError := client.Get(proxy.URL + "/records")
	if requestError != nil {
		t.Fatal(requestError)
	}
	_ = response.Body.Close()
	if response.Header.Get("Location") != "https://elsewhere.example.com/login" {
		t.Fatalf("foreign Location rewritten to %q", response.Header.Get("Location"))
	}
}

func TestProxyRefusesDotSegments(t *testing.T) {
	upstream, recorded := newRecordingUpstream(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusOK)
	})
	proxy := newTestProxy(t, upstream.URL+"/api/external-dns/"+credentialSegment, io.Discard)
	request, _ := http.NewRequest(http.MethodGet, proxy.URL, nil)
	request.URL.Opaque = "/../../admin"
	response, requestError := http.DefaultClient.Do(request)
	if requestError != nil {
		t.Fatal(requestError)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("got %d, want 400", response.StatusCode)
	}
	if len(*recorded) != 0 {
		t.Fatalf("a dot-segment request reached the upstream: %+v", *recorded)
	}
}

func TestUpstreamFailureLogNeverCarriesTheCredential(t *testing.T) {
	// A closed server's address refuses connections, so the transport fails
	// and *url.Error would quote the full upstream URL if it were logged raw.
	closed := httptest.NewServer(http.NotFoundHandler())
	closedURL := closed.URL
	closed.Close()

	var logOutput bytes.Buffer
	proxy := newTestProxy(t, closedURL+"/api/external-dns/"+credentialSegment+"?key="+credentialSegment, &logOutput)
	response, requestError := http.Get(proxy.URL + "/records")
	if requestError != nil {
		t.Fatal(requestError)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusBadGateway {
		t.Fatalf("got %d, want 502", response.StatusCode)
	}
	logged := logOutput.String()
	if !strings.Contains(logged, "upstream webhook request failed") {
		t.Fatalf("failure was not logged: %q", logged)
	}
	if strings.Contains(logged, credentialSegment) {
		t.Fatalf("the credential reached the log: %q", logged)
	}
}

func TestRedactorScrubsEveryCredentialBearingPart(t *testing.T) {
	upstream, _ := url.Parse("https://user:" + credentialSegment + "@dns.example.com/api/external-dns/" + credentialSegment + "?key=" + credentialSegment)
	redactor := newRedactor(upstream)
	text := `Get "https://user:` + credentialSegment + `@dns.example.com/api/external-dns/` + credentialSegment + `/records?key=` + credentialSegment + `": dial tcp: refused`
	redacted := redactor.redact(text)
	if strings.Contains(redacted, credentialSegment) {
		t.Fatalf("credential survived redaction: %q", redacted)
	}
	if !strings.Contains(redacted, "dial tcp: refused") {
		t.Fatalf("redaction removed the diagnosis: %q", redacted)
	}
}

func TestParseUpstreamURLNeverEchoesTheValue(t *testing.T) {
	for _, raw := range []string{"", "   ", "ftp://host/" + credentialSegment, "host-without-scheme/" + credentialSegment, "https:///" + credentialSegment, "mailto:" + credentialSegment} {
		_, parseError := parseUpstreamURL(raw)
		if parseError == nil {
			t.Fatalf("parseUpstreamURL(%q) accepted an unusable URL", raw)
		}
		if strings.Contains(parseError.Error(), credentialSegment) {
			t.Fatalf("the refusal echoed the value: %q", parseError.Error())
		}
	}
	parsed, parseError := parseUpstreamURL(" https://dns.example.com/api/external-dns/" + credentialSegment + "#fragment ")
	if parseError != nil || parsed.Host != "dns.example.com" || parsed.Fragment != "" {
		t.Fatalf("got %v, %v", parsed, parseError)
	}
}

func TestRequireLoopbackRefusesReachableAddresses(t *testing.T) {
	for _, address := range []string{"127.0.0.1:8888", "[::1]:8888", "127.0.0.2:9000"} {
		if requireLoopback(address) != nil {
			t.Fatalf("%s is loopback and was refused", address)
		}
	}
	for _, address := range []string{":8888", "0.0.0.0:8888", "10.0.0.5:8888", "localhost:8888", "[::]:8888", "8888"} {
		if requireLoopback(address) == nil {
			t.Fatalf("%s is not a loopback IP and was accepted", address)
		}
	}
}

func TestJoinUpstreamPath(t *testing.T) {
	cases := map[[2]string]string{
		{"/api/external-dns/x", ""}:          "/api/external-dns/x",
		{"/api/external-dns/x", "/"}:         "/api/external-dns/x",
		{"/api/external-dns/x/", "/"}:        "/api/external-dns/x",
		{"/api/external-dns/x", "/records"}:  "/api/external-dns/x/records",
		{"/api/external-dns/x/", "/records"}: "/api/external-dns/x/records",
		{"", "/records"}:                     "/records",
		{"", "/"}:                            "/",
		{"/", ""}:                            "/",
	}
	for input, expected := range cases {
		if joined := joinUpstreamPath(input[0], input[1]); joined != expected {
			t.Fatalf("joinUpstreamPath(%q, %q) = %q, want %q", input[0], input[1], joined, expected)
		}
	}
}

func TestLocalPathInvertsJoinUpstreamPath(t *testing.T) {
	upstream, _ := url.Parse("https://dns.example.com/api/external-dns/" + credentialSegment)
	for _, requestPath := range []string{"/", "/records", "/adjustendpoints"} {
		joined := joinUpstreamPath(upstream.Path, requestPath)
		if local := localPath(upstream, joined); local != requestPath {
			t.Fatalf("localPath(joinUpstreamPath(%q)) = %q", requestPath, local)
		}
	}
}
