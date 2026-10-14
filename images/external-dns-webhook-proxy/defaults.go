package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

const (
	// adjustDefaultsEnvironmentName holds the provider-specific properties the
	// proxy adds to endpoints on their way to /adjustendpoints, as a
	// comma-separated list of name=value pairs. Empty adds nothing.
	adjustDefaultsEnvironmentName = "ADJUST_DEFAULT_PROVIDER_SPECIFIC"
	// adjustRecordTypesEnvironmentName limits the defaults to these record
	// types (comma-separated); empty means defaultAdjustRecordTypes.
	adjustRecordTypesEnvironmentName = "ADJUST_DEFAULT_RECORD_TYPES"
	// adjustResourceKindsEnvironmentName limits the defaults to endpoints
	// whose external-dns "resource" label names one of these source kinds
	// (the part before the first "/", e.g. ingress in ingress/<ns>/<name>);
	// empty means defaultAdjustResourceKinds.
	adjustResourceKindsEnvironmentName = "ADJUST_DEFAULT_RESOURCE_KINDS"
	// adjustDomainsEnvironmentName limits the defaults to DNS names equal to
	// or below one of these domains (comma-separated); empty means every name.
	adjustDomainsEnvironmentName = "ADJUST_DEFAULT_DOMAINS"
	defaultAdjustRecordTypes     = "AAAA"
	defaultAdjustResourceKinds   = "ingress"
	// adjustEndpointsPath is the webhook protocol's AdjustEndpoints call.
	adjustEndpointsPath = "/adjustendpoints"
	// maximumAdjustBodyBytes bounds the body the proxy reads to rewrite.
	maximumAdjustBodyBytes = 32 << 20
)

var errAdjustDefaultUnusable = errors.New(adjustDefaultsEnvironmentName + " must be a comma-separated list of name=value pairs")

// providerSpecificProperty is one external-dns provider-specific property.
type providerSpecificProperty struct {
	Name  string
	Value string
}

// adjustDefaults is a default provider-specific property set for the
// endpoints external-dns asks its webhook to adjust. external-dns has no flag
// that defaults a webhook provider's provider-specific properties (only its
// built-in Cloudflare provider has one); a provider applies its defaults in
// AdjustEndpoints, and the proxy sits on exactly that call. An endpoint that
// already carries a property of the same name - from an annotation under
// external-dns.alpha.kubernetes.io/webhook-, "false" included - keeps its own
// value, so a default is always overridable per Ingress.
type adjustDefaults struct {
	properties    []providerSpecificProperty
	recordTypes   map[string]bool
	resourceKinds map[string]bool
	domains       []string
}

// adjustDefaultsFromEnvironment reads the defaults; a nil result with a nil
// error means none are configured and the proxy forwards unchanged.
func adjustDefaultsFromEnvironment() (*adjustDefaults, error) {
	return parseAdjustDefaults(os.Getenv(adjustDefaultsEnvironmentName), os.Getenv(adjustRecordTypesEnvironmentName),
		os.Getenv(adjustResourceKindsEnvironmentName), os.Getenv(adjustDomainsEnvironmentName))
}

func parseAdjustDefaults(rawProperties string, rawRecordTypes string, rawResourceKinds string, rawDomains string) (*adjustDefaults, error) {
	if strings.TrimSpace(rawProperties) == "" {
		return nil, nil
	}
	defaults := &adjustDefaults{
		recordTypes:   setOf(withFallback(rawRecordTypes, defaultAdjustRecordTypes), strings.ToUpper),
		resourceKinds: setOf(withFallback(rawResourceKinds, defaultAdjustResourceKinds), strings.ToLower),
	}
	for _, pair := range splitList(rawProperties) {
		name, value, hasValue := strings.Cut(pair, "=")
		name = strings.TrimSpace(name)
		if !hasValue || name == "" {
			return nil, errAdjustDefaultUnusable
		}
		defaults.properties = append(defaults.properties, providerSpecificProperty{Name: name, Value: strings.TrimSpace(value)})
	}
	for _, domain := range splitList(rawDomains) {
		defaults.domains = append(defaults.domains, normaliseDNSName(domain))
	}
	return defaults, nil
}

func withFallback(raw string, fallback string) string {
	if strings.TrimSpace(raw) == "" {
		return fallback
	}
	return raw
}

func splitList(raw string) []string {
	var items []string
	for _, item := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			items = append(items, trimmed)
		}
	}
	return items
}

func setOf(raw string, normalise func(string) string) map[string]bool {
	set := map[string]bool{}
	for _, item := range splitList(raw) {
		set[normalise(item)] = true
	}
	return set
}

func normaliseDNSName(name string) string {
	return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(name)), ".")
}

// describe names the configuration for the startup log line; nothing in it is
// a credential.
func (defaults *adjustDefaults) describe() string {
	names := make([]string, 0, len(defaults.properties))
	for _, property := range defaults.properties {
		names = append(names, property.Name+"="+property.Value)
	}
	return strings.Join(names, ",")
}

// applies reports whether the defaults cover one endpoint.
func (defaults *adjustDefaults) applies(endpoint map[string]any) bool {
	recordType, _ := endpoint["recordType"].(string)
	if !defaults.recordTypes[strings.ToUpper(recordType)] {
		return false
	}
	labels, _ := endpoint["labels"].(map[string]any)
	resource, _ := labels["resource"].(string)
	kind, _, _ := strings.Cut(resource, "/")
	if !defaults.resourceKinds[strings.ToLower(kind)] {
		return false
	}
	if len(defaults.domains) == 0 {
		return true
	}
	dnsName, _ := endpoint["dnsName"].(string)
	dnsName = normaliseDNSName(dnsName)
	for _, domain := range defaults.domains {
		if dnsName == domain || strings.HasSuffix(dnsName, "."+domain) {
			return true
		}
	}
	return false
}

// apply adds every default property an endpoint the defaults cover does not
// already carry, and reports whether anything changed.
func (defaults *adjustDefaults) apply(endpoint map[string]any) bool {
	if !defaults.applies(endpoint) {
		return false
	}
	existing, _ := endpoint["providerSpecific"].([]any)
	carried := map[string]bool{}
	for _, entry := range existing {
		if property, isProperty := entry.(map[string]any); isProperty {
			if name, isName := property["name"].(string); isName {
				carried[name] = true
			}
		}
	}
	isChanged := false
	for _, property := range defaults.properties {
		if carried[property.Name] {
			continue
		}
		existing = append(existing, map[string]any{"name": property.Name, "value": property.Value})
		isChanged = true
	}
	if isChanged {
		endpoint["providerSpecific"] = existing
	}
	return isChanged
}

// rewriteAdjustRequest applies the defaults to the endpoints of a POST
// /adjustendpoints body. A body that is not the endpoint list the protocol
// sends is forwarded exactly as received, so the provider answers it as it
// would have without the proxy. Every other field of an endpoint survives
// the rewrite byte for byte in meaning (numbers are kept as written).
func (defaults *adjustDefaults) rewriteAdjustRequest(request *http.Request) error {
	if defaults == nil || request.Method != http.MethodPost || request.URL.Path != adjustEndpointsPath || request.Body == nil {
		return nil
	}
	body, readError := io.ReadAll(io.LimitReader(request.Body, maximumAdjustBodyBytes+1))
	_ = request.Body.Close()
	if readError != nil {
		return fmt.Errorf("reading the adjustendpoints body: %w", readError)
	}
	if len(body) > maximumAdjustBodyBytes {
		return fmt.Errorf("the adjustendpoints body exceeds %d bytes", maximumAdjustBodyBytes)
	}
	request.Body = io.NopCloser(bytes.NewReader(body))
	request.ContentLength = int64(len(body))

	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.UseNumber()
	var endpoints []any
	if decoder.Decode(&endpoints) != nil {
		return nil
	}
	isChanged := false
	for _, entry := range endpoints {
		if endpoint, isEndpoint := entry.(map[string]any); isEndpoint && defaults.apply(endpoint) {
			isChanged = true
		}
	}
	if !isChanged {
		return nil
	}
	rewritten, marshalError := json.Marshal(endpoints)
	if marshalError != nil {
		return fmt.Errorf("encoding the adjusted endpoints: %w", marshalError)
	}
	request.Body = io.NopCloser(bytes.NewReader(rewritten))
	request.ContentLength = int64(len(rewritten))
	request.Header.Del("Content-Length")
	return nil
}
