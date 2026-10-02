// Command external-dns-webhook-proxy is a loopback-only reverse proxy that
// lets external-dns talk to a remote webhook provider whose URL carries a
// credential, without external-dns ever holding that URL.
//
// external-dns prints its whole resolved configuration at INFO on every start,
// before it applies --log-level, and its config dump masks only fields tagged
// secure:"yes". WebhookProviderURL is not one of them (v0.21.0 through
// v0.23.0), so a provider addressed as https://host/api/external-dns/<token>
// puts <token> into the pod log of every external-dns that starts. Running
// this proxy as a sidecar moves the credential-bearing URL out of
// external-dns's configuration: external-dns is pointed at
// http://127.0.0.1:8888, which is not a secret, and only this process reads
// the real URL.
//
// Every request external-dns sends is forwarded to the configured URL with the
// request path appended to the URL's own path, so the webhook protocol's
// negotiation (GET /), /records and /adjustendpoints reach
// <url>, <url>/records and <url>/adjustendpoints. The proxy never logs the
// upstream path or query, and redacts both from anything an error carries.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

const (
	// upstreamURLEnvironmentName holds the credential-bearing webhook URL.
	upstreamURLEnvironmentName = "WEBHOOK_PROVIDER_URL"
	// listenAddressEnvironmentName overrides the loopback listen address.
	listenAddressEnvironmentName = "LISTEN_ADDRESS"
	// defaultListenAddress is external-dns's own default webhook address.
	defaultListenAddress = "127.0.0.1:8888"
	// redactedMarker replaces the credential-bearing parts of the upstream
	// URL wherever they would otherwise be written out.
	redactedMarker = "[redacted]"
	// shutdownGrace bounds how long in-flight requests may finish after
	// SIGTERM before the process exits anyway.
	shutdownGrace = 10 * time.Second
	// minimumRedactedLength is the shortest upstream URL fragment the
	// redactor scrubs from log output.
	minimumRedactedLength = 8
)

// errUpstreamURLMissing and errUpstreamURLUnusable never carry the value they
// reject: the value is the credential.
var (
	errUpstreamURLMissing  = errors.New(upstreamURLEnvironmentName + " is not set")
	errUpstreamURLUnusable = errors.New(upstreamURLEnvironmentName + " is not an absolute http or https URL with a host")
	errListenNotLoopback   = errors.New(listenAddressEnvironmentName + " must be a loopback address: the proxy authenticates every caller that can reach it")
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if runError := run(logger); runError != nil {
		logger.Error("external-dns-webhook-proxy stopped", "error", runError.Error())
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	upstream, parseError := parseUpstreamURL(os.Getenv(upstreamURLEnvironmentName))
	if parseError != nil {
		return parseError
	}
	listenAddress := os.Getenv(listenAddressEnvironmentName)
	if listenAddress == "" {
		listenAddress = defaultListenAddress
	}
	if loopbackError := requireLoopback(listenAddress); loopbackError != nil {
		return loopbackError
	}

	redactor := newRedactor(upstream)
	server := &http.Server{
		Addr:              listenAddress,
		Handler:           newProxy(upstream, logger, redactor),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		ErrorLog:          log.New(redactingWriter{target: os.Stderr, redactor: redactor}, "", 0),
	}

	listener, listenError := net.Listen("tcp", listenAddress)
	if listenError != nil {
		return fmt.Errorf("listening on %s: %w", listenAddress, listenError)
	}
	logger.Info("forwarding external-dns webhook calls",
		"listen", listenAddress, "upstream_origin", upstream.Scheme+"://"+upstream.Host)

	signals, stopSignals := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stopSignals()
	serveErrors := make(chan error, 1)
	go func() { serveErrors <- server.Serve(listener) }()

	select {
	case serveError := <-serveErrors:
		if errors.Is(serveError, http.ErrServerClosed) {
			return nil
		}
		return serveError
	case <-signals.Done():
		shutdownContext, cancelShutdown := context.WithTimeout(context.Background(), shutdownGrace)
		defer cancelShutdown()
		return server.Shutdown(shutdownContext)
	}
}

// parseUpstreamURL validates the credential-bearing URL without ever echoing
// it back.
func parseUpstreamURL(raw string) (*url.URL, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil, errUpstreamURLMissing
	}
	parsed, parseError := url.Parse(trimmed)
	if parseError != nil {
		return nil, errUpstreamURLUnusable
	}
	if (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" || parsed.Opaque != "" {
		return nil, errUpstreamURLUnusable
	}
	parsed.Fragment = ""
	parsed.RawFragment = ""
	return parsed, nil
}

// requireLoopback refuses any listen address that is not a loopback IP. The
// proxy adds the credential to every request it forwards, so anything that can
// reach it can write DNS as the credential's owner; on a pod IP that would be
// every workload in the cluster.
func requireLoopback(listenAddress string) error {
	host, _, splitError := net.SplitHostPort(listenAddress)
	if splitError != nil {
		return errListenNotLoopback
	}
	address := net.ParseIP(host)
	if address == nil || !address.IsLoopback() {
		return errListenNotLoopback
	}
	return nil
}

// newProxy builds the forwarding handler.
func newProxy(upstream *url.URL, logger *slog.Logger, redactor redactor) http.Handler {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.ResponseHeaderTimeout = 60 * time.Second
	reverseProxy := &httputil.ReverseProxy{
		Rewrite: func(proxyRequest *httputil.ProxyRequest) {
			outgoing := proxyRequest.Out
			outgoing.URL.Scheme = upstream.Scheme
			outgoing.URL.Host = upstream.Host
			outgoing.URL.Path = joinUpstreamPath(upstream.Path, proxyRequest.In.URL.Path)
			outgoing.URL.RawPath = ""
			outgoing.URL.RawQuery = joinQuery(upstream.RawQuery, proxyRequest.In.URL.RawQuery)
			outgoing.Host = upstream.Host
			if upstream.User != nil {
				password, _ := upstream.User.Password()
				outgoing.SetBasicAuth(upstream.User.Username(), password)
			}
		},
		Transport: transport,
		ModifyResponse: func(response *http.Response) error {
			rewriteLocation(response, upstream)
			return nil
		},
		// The request handed to ErrorHandler is the rewritten outgoing one,
		// whose path is the credential-bearing upstream path; it is mapped
		// back to the path external-dns asked for before it is logged.
		ErrorHandler: func(writer http.ResponseWriter, request *http.Request, proxyError error) {
			logger.Warn("upstream webhook request failed",
				"method", request.Method, "path", redactor.redact(localPath(upstream, request.URL.Path)),
				"error", redactor.redact(describeError(proxyError)))
			writer.WriteHeader(http.StatusBadGateway)
		},
		ErrorLog: log.New(redactingWriter{target: os.Stderr, redactor: redactor}, "", 0),
	}
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if hasDotSegment(request.URL.Path) {
			http.Error(writer, "path must not contain dot segments", http.StatusBadRequest)
			return
		}
		reverseProxy.ServeHTTP(writer, request)
	})
}

// joinUpstreamPath appends the path external-dns asked for to the upstream
// URL's path. The webhook root ("/" or "") maps to the upstream path itself,
// never to it with a trailing slash: a framework that redirects trailing
// slashes would answer with a Location carrying the credential.
func joinUpstreamPath(upstreamPath string, requestPath string) string {
	base := strings.TrimSuffix(upstreamPath, "/")
	suffix := requestPath
	if suffix == "/" {
		suffix = ""
	}
	joined := base + suffix
	if joined == "" {
		return "/"
	}
	return joined
}

// joinQuery merges the upstream URL's own query with the request's.
func joinQuery(upstreamQuery string, requestQuery string) string {
	switch {
	case upstreamQuery == "":
		return requestQuery
	case requestQuery == "":
		return upstreamQuery
	default:
		return upstreamQuery + "&" + requestQuery
	}
}

// hasDotSegment reports whether a request path holds a "." or ".." segment.
// Only the external-dns container shares the loopback interface, but a path
// that climbs out of the upstream URL's path would address endpoints the
// credential was never configured for.
func hasDotSegment(requestPath string) bool {
	for _, segment := range strings.Split(requestPath, "/") {
		if segment == "." || segment == ".." {
			return true
		}
	}
	return false
}

// localPath maps an upstream request path back onto the proxy's own path
// space: the inverse of joinUpstreamPath.
func localPath(upstream *url.URL, upstreamPath string) string {
	base := strings.TrimSuffix(upstream.Path, "/")
	if base != "" && upstreamPath != base && !strings.HasPrefix(upstreamPath, base+"/") {
		return upstreamPath
	}
	trimmed := strings.TrimPrefix(upstreamPath, base)
	if trimmed == "" {
		return "/"
	}
	return trimmed
}

// rewriteLocation maps a redirect that points back into the upstream URL onto
// the proxy's own path space, so external-dns follows it through the proxy and
// never sees, logs or requests the credential-bearing path.
func rewriteLocation(response *http.Response, upstream *url.URL) {
	location := response.Header.Get("Location")
	if location == "" {
		return
	}
	target, parseError := response.Request.URL.Parse(location)
	if parseError != nil {
		response.Header.Del("Location")
		return
	}
	if !strings.EqualFold(target.Host, upstream.Host) {
		return
	}
	base := strings.TrimSuffix(upstream.Path, "/")
	if target.Path != base && !strings.HasPrefix(target.Path, base+"/") {
		return
	}
	local := url.URL{Path: localPath(upstream, target.Path), RawQuery: target.RawQuery}
	response.Header.Set("Location", local.String())
}

// describeError strips the request URL a transport error carries
// (*url.Error prints `Get "<full url>": <cause>`), keeping only the cause.
func describeError(proxyError error) string {
	var urlError *url.Error
	if errors.As(proxyError, &urlError) {
		return urlError.Op + ": " + urlError.Err.Error()
	}
	return proxyError.Error()
}

// redactor replaces every credential-bearing part of the upstream URL in text
// that is about to be written out. It is the backstop under describeError:
// whatever an error from the standard library chooses to quote, the path,
// query and userinfo of the upstream URL never reach the log.
type redactor struct {
	secrets []string
}

func newRedactor(upstream *url.URL) redactor {
	candidates := []string{upstream.String(), upstream.EscapedPath(), upstream.Path, upstream.RawQuery}
	if upstream.User != nil {
		candidates = append(candidates, upstream.User.String())
		if password, hasPassword := upstream.User.Password(); hasPassword {
			candidates = append(candidates, password)
		}
	}
	for _, segment := range strings.Split(upstream.Path, "/") {
		candidates = append(candidates, segment)
	}
	secrets := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		if isRedactable(candidate) {
			secrets = append(secrets, candidate)
		}
	}
	return redactor{secrets: secrets}
}

// isRedactable keeps short, common fragments ("api", "/", "v1") out of the
// list, so redaction does not shred ordinary words; a credential is never
// that short.
func isRedactable(candidate string) bool {
	return len(candidate) >= minimumRedactedLength
}

func (redactor redactor) redact(text string) string {
	for _, secret := range redactor.secrets {
		text = strings.ReplaceAll(text, secret, redactedMarker)
	}
	return text
}

// redactingWriter is the io.Writer behind the standard library loggers the
// HTTP server and reverse proxy write to.
type redactingWriter struct {
	target   io.Writer
	redactor redactor
}

func (writer redactingWriter) Write(payload []byte) (int, error) {
	if _, writeError := io.WriteString(writer.target, writer.redactor.redact(string(payload))); writeError != nil {
		return 0, writeError
	}
	return len(payload), nil
}
