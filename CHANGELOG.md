# Changelog

All notable changes to this project are documented in this file. The project follows Semantic Versioning, with the pre-1.0 compatibility policy described in [Versioning](docs/versioning.md).

## [Unreleased]

### Added

- Dependency-aware module kernel, services, events, commands, queries, logging, rollback, and one host autoload
- Resource, scene, storage, settings, pool, and state-machine foundation modules
- Optional UI, audio, input, and localization modules
- Optional resource ownership, download, signed PCK content, and table-provider modules
- Optional bounded HTTP, WebSocket channel, and request-correlation services
- Structured framework configuration validator, editor dock, and headless validation runner
- Deterministic addon-only ZIP packaging, SHA-256 output, clean-project install test, and release workflow
- LF-normalized source checkouts and cross-OS addon package checksum comparison
- Performance smoke runner and bounded queued-event backlog
- Capacity limits for threaded resource requests, downloads, HTTP history, and correlation tracking
- Linux, macOS, and Windows release-export execution tests using the packaged addon and matching Godot templates
- Single-threaded Web release-export execution in headless Chrome on both supported Godot versions
- Android release APK export, ephemeral test signing, x86_64 ABI verification, and API 35 emulator execution on both supported Godot versions
- Clean-package installation and all supported release exports now start all 14 built-in modules with integration-free consumer settings
- Package-installed reference consumer exercising project-owned configuration, UI routing, input profile restoration, localization, settings, and persistence
- Size-bounded, checksummed storage envelopes with backup fallback for missing or corrupt primaries

### Changed

- Framework initialization, startup, frame forwarding, and teardown tolerate modules shutting down the host reentrantly

- `GFEventBus.queue()` now returns `Error`; a full queue returns `ERR_OUT_OF_MEMORY`
- `GFModuleDefinition` now requires declarative IDs and dependencies that must match runtime module metadata
- Terminal HTTP and download metadata is bounded and evicts the oldest retained records
- `GFModuleManager` is explicitly single-use after shutdown or lifecycle failure
- Settings persistence creates valid nested `user://` parent directories before saving

### Known Limitations

- Public APIs remain development-tier until the first stable release
- Godot 4.4 cannot unload mounted PCK files in the same process
- Resumable downloads, bandwidth throttling, arbitrary script hot reload, and universal networking protocols are not claimed
- Release exports validate all-module lifecycle only. A headless reference consumer validates project routes, input bindings, translation resources, settings, and save paths; their exported paths, plus audio playback, downloads, PCK mounting, protocol adapters, AAB or Play workflows, production signing, and iOS remain unverified
