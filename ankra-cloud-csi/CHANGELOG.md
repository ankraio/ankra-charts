# ankra-cloud-csi changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

The chart is maintained in [`ankraio/ankra-cloud-csi`](https://github.com/ankraio/ankra-cloud-csi)
(`charts/ankra-cloud-csi`) and copied here for each release; `appVersion` is the
driver image tag it installs.

## [Unreleased]

## [0.2.0] - 2026-10-10

### Fixed

- A `local-nvme` volume is created on the compute node that runs the scheduled
  node's server (`create_storage` `placement.server_id`), so attaching it no
  longer fails with 409 Conflict.

### Changed

- The default StorageClass is the new `ankra-default`: it names no tier, so every
  volume gets its zone's default storage tier and a claim without a class works in
  a zone without Ankra Storage, where only `local-nvme` is offered.
  `ankra-standard` stays, no longer the default.
- Driver image `share.ankra.cloud/library/ankra-cloud-csi:v0.2.0`; the API client
  is regenerated from the current Ankra Cloud OpenAPI document.

## [0.1.0] - 2026-09-28

### Added

- First public release of the Ankra Cloud CSI driver `csi.ankra.cloud` (image
  `share.ankra.cloud/library/ankra-cloud-csi:v0.1.0`, linux/amd64 and linux/arm64):
  dynamic provisioning for the `standard`, `maxiops`, `hdd` and `local-nvme` tiers,
  hot-plug attach and detach, online expansion, snapshots, restore and clones.
- StorageClasses `ankra-standard` (default), `ankra-maxiops`, `ankra-hdd` and
  `ankra-local-nvme`, all `WaitForFirstConsumer`; the `ankra-snapshots`
  VolumeSnapshotClass when the snapshot API is served.
