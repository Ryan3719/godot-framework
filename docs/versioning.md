# Versioning And API Stability

## Version Scheme

Godot Framework follows Semantic Versioning: `MAJOR.MINOR.PATCH`.

- Before `1.0.0`, a minor release may contain documented breaking API changes.
- After `1.0.0`, breaking stable API changes require a major release.
- Patch releases fix behavior without intentionally changing documented contracts.
- Versions ending in `-dev` are unreleased development snapshots and cannot be published by the release workflow.

The supported engine range currently starts at Godot 4.4. CI validates editor/headless behavior plus Linux, macOS, Windows, single-threaded Web, and Android release APK execution on both the minimum version, 4.4.1, and the current compatibility version, 4.7.1. Android execution uses an API 35 x86_64 emulator and an ephemeral test signing key. These exports exercise startup and shutdown of all built-in modules in a clean consumer fixture. A separate package-installed reference consumer runs its project-owned route, input-binding, translation, settings, and save-path integration headlessly plus in Linux and single-threaded Web releases. Audio playback, downloads, PCK mounting, and HTTP/WebSocket protocol adapters still need exported consumer-project evidence. Threaded Web builds, AAB or Play workflows, production Android signing, and iOS require separate evidence. A future engine version is not supported merely because it parses the project.

## Stability Tiers

| Tier | Contract |
| --- | --- |
| Stable | Documented public classes, methods, signals, settings, service IDs, and serialized formats in a `1.x` release |
| Development | Public APIs in `0.x`; usable, tested, and documented, but may change in the next minor version |
| Internal | Members beginning with `_`, test fixtures, editor implementation details, packaging scripts, and undocumented internals |

All current runtime APIs are Development tier. Deprecation notices and an upgrade path should accompany planned breaking changes where practical, but pre-1.0 code must still pin a compatible minor version.

## Compatibility Boundaries

Module IDs, service IDs, signal argument order, error semantics, settings field names, and persisted framework schemas are API. Concrete application scenes, protocol envelopes, table schemas, content IDs, and gameplay types are outside the framework contract.

Release tags must exactly match the version in `addons/godot_framework/plugin.cfg`, prefixed with `v`. For example, tag `v0.5.0` requires plugin version `0.5.0`; `0.5.0-dev` is rejected.
