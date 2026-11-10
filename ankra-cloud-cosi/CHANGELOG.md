# ankra-cloud-cosi changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

The chart is maintained in [`ankraio/ankra-cloud-csi`](https://github.com/ankraio/ankra-cloud-csi)
(`charts/ankra-cloud-cosi`) and copied here for each release; `appVersion` is the
driver image tag it installs.

## [Unreleased]

## [0.1.0] - 2026-11-10

### Added

- The COSI driver `cosi.ankra.cloud` for Ankra Cloud object storage: a
  `BucketClaim` creates an S3 bucket in the zone its `BucketClass` names, and a
  `BucketAccess` writes a Secret with the zone's endpoint and the account's key.
- One Deployment with the driver and the upstream `objectstorage-sidecar`
  v0.2.2 (pinned by digest), and the RBAC the sidecar needs.
- An example `ankra-objects` BucketClass (rendered when `bucketClass.zone` is
  set) and `ankra-objects-key` BucketAccessClass, both only when the cluster
  serves `objectstorage.k8s.io/v1alpha1`.
