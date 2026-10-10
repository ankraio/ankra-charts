# ankra-cloud-ccm changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

The chart is maintained in [`ankraio/ankra-cloud-ccm`](https://github.com/ankraio/ankra-cloud-ccm)
(`charts/ankra-cloud-ccm`) and copied here for each release; `appVersion` is the
controller image tag it installs.

## [Unreleased]

## [0.1.1] - 2026-10-10

### Fixed

- Services of type LoadBalancer no longer stay pending on a
  `get_zone_capabilities` decode error: the zone's `stage` is read as the number
  the API sends.
- A load balancer created without the IPv4 annotation no longer gets the priced
  IPv4 address: `public_ipv4` is always sent.
- Load balancers past the first page of `list_load_balancers` are found: the
  controller follows `next_cursor`.

### Changed

- Controller image `share.ankra.cloud/library/ankra-cloud-ccm:v0.1.1`; the API
  client is synced with the current Ankra Cloud OpenAPI document.

## [0.1.0] - 2026-09-28

### Added

- First public release of the Ankra Cloud cloud controller manager, provider
  `ankracloud` (image `share.ankra.cloud/library/ankra-cloud-ccm:v0.1.0`,
  linux/amd64 and linux/arm64, distroless, non-root): node initialisation and one
  Ankra load balancer per Service of type LoadBalancer, or members on a combined
  edge.
