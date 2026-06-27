# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> Earlier entries predate the move to a standalone repository; they were
> previously tracked in the [ExScim umbrella](https://github.com/ExScim/ex_scim)
> changelog under the `scim_tester` heading.

## [Unreleased]

### Changed

- Extracted into its own repository, independent of the ExScim umbrella
- Depend on `ex_scim_client` via Hex instead of an umbrella path dependency
- Refactored `ScimLive` into focused context modules and function components

## [0.1.2]

### Added

- Schema-aware payload generation for create, update, patch, and bulk tests

## [0.1.0]

### Added

- Search composer with navbar, dedicated route, and result section
- Connect button to fetch server capabilities
- Re-run functionality for individual test cases
- Integration tests for filter operators
- Filter list built from schema
