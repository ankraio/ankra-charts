package main

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const proxiedDefault = "webhook/ankra-cloud-proxied=true"

func newDefaultsProxy(t *testing.T, defaults *adjustDefaults) (*httptest.Server, *[]recordedRequest) {
	t.Helper()
	upstreamServer, recorded := newRecordingUpstream(t, func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "application/external.dns.webhook+json;version=1")
		_, _ = writer.Write([]byte("[]"))
	})
	upstream, parseError := parseUpstreamURL(upstreamServer.URL + "/v1/dns/webhook/" + credentialSegment)
	if parseError != nil {
		t.Fatal(parseError)
	}
	proxy := httptest.NewServer(newProxy(upstream, slog.New(slog.NewTextHandler(io.Discard, nil)), newRedactor(upstream), defaults))
	t.Cleanup(proxy.Close)
	return proxy, recorded
}

func mustDefaults(t *testing.T, properties string, recordTypes string, resourceKinds string, domains string) *adjustDefaults {
	t.Helper()
	defaults, parseError := parseAdjustDefaults(properties, recordTypes, resourceKinds, domains)
	if parseError != nil {
		t.Fatalf("parseAdjustDefaults: %v", parseError)
	}
	return defaults
}

func postAdjust(t *testing.T, proxy *httptest.Server, path string, body string) *http.Response {
	t.Helper()
	response, postError := http.Post(proxy.URL+path, "application/external.dns.webhook+json;version=1", strings.NewReader(body))
	if postError != nil {
		t.Fatal(postError)
	}
	t.Cleanup(func() { _ = response.Body.Close() })
	return response
}

func forwardedEndpoints(t *testing.T, recorded *[]recordedRequest) []map[string]any {
	t.Helper()
	if len(*recorded) != 1 {
		t.Fatalf("want one forwarded request, got %d", len(*recorded))
	}
	var endpoints []map[string]any
	if decodeError := json.Unmarshal([]byte((*recorded)[0].body), &endpoints); decodeError != nil {
		t.Fatalf("the forwarded body is not an endpoint list: %v (%s)", decodeError, (*recorded)[0].body)
	}
	return endpoints
}

func propertiesOf(endpoint map[string]any) map[string]string {
	properties := map[string]string{}
	entries, _ := endpoint["providerSpecific"].([]any)
	for _, entry := range entries {
		property, _ := entry.(map[string]any)
		name, _ := property["name"].(string)
		value, _ := property["value"].(string)
		properties[name] = value
	}
	return properties
}

const adjustBody = `[
 {"dnsName":"demo.c1.o1.ankra.cc","targets":["2a01:4f8::1"],"recordType":"AAAA","recordTTL":60,"labels":{"resource":"ingress/default/demo"}},
 {"dnsName":"optout.c1.o1.ankra.cc","targets":["2a01:4f8::1"],"recordType":"AAAA","labels":{"resource":"ingress/default/optout"},"providerSpecific":[{"name":"webhook/ankra-cloud-proxied","value":"false"}]},
 {"dnsName":"demo.c1.o1.ankra.cc","targets":["198.51.100.4"],"recordType":"A","labels":{"resource":"ingress/default/demo"}},
 {"dnsName":"mqtt.c1.o1.ankra.cc","targets":["2a01:4f8::2"],"recordType":"AAAA","labels":{"resource":"service/default/mqtt"}},
 {"dnsName":"app.example.com","targets":["2a01:4f8::1"],"recordType":"AAAA","labels":{"resource":"ingress/default/custom"}}
]`

func TestAdjustDefaultsProxyOnlyTheIngressAAAAEndpointsOfTheZone(t *testing.T) {
	proxy, recorded := newDefaultsProxy(t, mustDefaults(t, proxiedDefault, "", "", "c1.o1.ankra.cc"))
	if response := postAdjust(t, proxy, "/adjustendpoints", adjustBody); response.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", response.StatusCode)
	}
	endpoints := forwardedEndpoints(t, recorded)
	want := []string{"true", "false", "", "", ""}
	for index, endpoint := range endpoints {
		if got := propertiesOf(endpoint)["webhook/ankra-cloud-proxied"]; got != want[index] {
			t.Errorf("endpoint %d (%v %v): proxied = %q, want %q", index, endpoint["dnsName"], endpoint["recordType"], got, want[index])
		}
	}
	if ttl := endpoints[0]["recordTTL"]; ttl != float64(60) {
		t.Fatalf("every other field must survive the rewrite: recordTTL = %v", ttl)
	}
	if (*recorded)[0].path != "/v1/dns/webhook/"+credentialSegment+"/adjustendpoints" {
		t.Fatalf("the call must still reach the upstream adjustendpoints: %q", (*recorded)[0].path)
	}
}

func TestAdjustDefaultsWithoutDomainsCoverEveryIngressAAAA(t *testing.T) {
	proxy, recorded := newDefaultsProxy(t, mustDefaults(t, proxiedDefault, "", "", ""))
	postAdjust(t, proxy, "/adjustendpoints", adjustBody)
	if got := propertiesOf(forwardedEndpoints(t, recorded)[4])["webhook/ankra-cloud-proxied"]; got != "true" {
		t.Fatalf("without a domain list every ingress AAAA is covered, got %q", got)
	}
}

func TestAdjustDefaultsLeaveOtherCallsAlone(t *testing.T) {
	proxy, recorded := newDefaultsProxy(t, mustDefaults(t, proxiedDefault, "", "", ""))
	changes := `{"Create":[{"dnsName":"demo.c1.o1.ankra.cc","targets":["2a01:4f8::1"],"recordType":"AAAA","labels":{"resource":"ingress/default/demo"}}]}`
	postAdjust(t, proxy, "/records", changes)
	if (*recorded)[0].body != changes {
		t.Fatalf("only adjustendpoints is rewritten; /records got %s", (*recorded)[0].body)
	}
}

func TestAdjustDefaultsForwardABodyTheyCannotReadUnchanged(t *testing.T) {
	proxy, recorded := newDefaultsProxy(t, mustDefaults(t, proxiedDefault, "", "", ""))
	postAdjust(t, proxy, "/adjustendpoints", `{"not":"a list"}`)
	if (*recorded)[0].body != `{"not":"a list"}` {
		t.Fatalf("an unexpected body must reach the provider as sent: %s", (*recorded)[0].body)
	}
}

func TestNoAdjustDefaultsForwardsByteForByte(t *testing.T) {
	proxy, recorded := newDefaultsProxy(t, nil)
	postAdjust(t, proxy, "/adjustendpoints", adjustBody)
	if (*recorded)[0].body != adjustBody {
		t.Fatalf("without defaults the body must be forwarded unchanged")
	}
}

func TestParseAdjustDefaults(t *testing.T) {
	if defaults, parseError := parseAdjustDefaults(" ", "", "", ""); defaults != nil || parseError != nil {
		t.Fatalf("empty configures nothing: %v %v", defaults, parseError)
	}
	for _, unusable := range []string{"webhook/ankra-cloud-proxied", "=true"} {
		if _, parseError := parseAdjustDefaults(unusable, "", "", ""); parseError == nil {
			t.Fatalf("%q must be refused", unusable)
		}
	}
	defaults := mustDefaults(t, "webhook/a=1, webhook/b = 2", "aaaa,cname", "Ingress", "Example.COM.")
	if len(defaults.properties) != 2 || defaults.properties[1] != (providerSpecificProperty{Name: "webhook/b", Value: "2"}) {
		t.Fatalf("properties = %+v", defaults.properties)
	}
	if !defaults.recordTypes["AAAA"] || !defaults.recordTypes["CNAME"] || !defaults.resourceKinds["ingress"] || defaults.domains[0] != "example.com" {
		t.Fatalf("defaults = %+v", defaults)
	}
}
