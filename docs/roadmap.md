# Roadmap

The roadmap is ordered by dependency and risk, not by the number of features a competing framework lists.

## 0.1 Foundation

Status: implemented in the current development branch.

- Kernel lifecycle, dependency graph, rollback, services, events, messages, and logging
- Resource, scene, storage, settings, pool, and state-machine modules
- Typed Resource configuration
- Headless test runner and CI compatibility gate
- Architecture and extension documentation

Exit criteria: Godot 4.4 compatibility, deterministic tests, zero lifecycle leak warnings, and no game-specific code.

## 0.2 Presentation And Media

Status: implemented in the current development branch. These modules are present in the default configuration but disabled by default.

- Optional UI navigation service with layers, stack navigation, singleton routes, input-blocking layers, and project-owned views
- Logical audio groups, buses, playback handles, pause/stop controls, tags, and concurrency policies
- Input remapping and serializable profiles for an explicit managed-action allowlist
- Localization facade over Godot `TranslationServer` with locale fallback, owned translations, formatting, and content validation
- Module lifecycle integration tests and headless audio injection boundary

Exit criteria: modules can be enabled independently at runtime and do not ship branded screens or concrete game flow. Physical per-module packages remain deferred until real consumer projects demonstrate that their versioning and dependency cost is justified.

## 0.3 Content Delivery

Status: implemented for Godot 4.4-compatible desktop behavior in the current development branch. Exported mobile validation and bandwidth/resume policy remain release-hardening work.

- Resource ownership handles with transient, leased, and retained cache policies
- HTTP download queue with bounded concurrency, progress, retry, cancellation, safe relative targets, and transactional replacement
- Optional size and SHA-256 download verification
- Detached RSA-SHA256 PCK manifests, installation records, active/previous release state, ordered startup mount, and persistent rollback
- Fail-closed corrupt-state handling and an explicit restart boundary because Godot cannot unload mounted PCKs
- Configuration-table provider interface and registry; Luban remains an optional external adapter
- Mocked failure-path tests plus a real PCK creation/mount/read integration test

Exit criteria for a stable release: exported desktop/mobile validation, CDN integration tests, and a defined resumable Range-request policy. The current development API does not claim bandwidth throttling, resumable downloads, same-process PCK unload, or arbitrary script hot reload.

## 0.4 Connectivity

Status: implemented for Godot 4.4-compatible desktop behavior in the current development branch. Exported Web/mobile validation and application-protocol integration remain release-hardening work.

- Bounded HTTP request queue with raw byte bodies, tags, cancellation, timeout, TLS options, redirects, and response size limits
- Named WebSocket channel lifecycle with non-blocking polling, clean close, connection timeout, and bounded reconnect policy
- Native WebSocket ping interval, receive packet budget, packet size limit, and outbound high/low watermark backpressure
- Protocol-neutral correlation tracker with resolve, timeout, cancellation, and context ownership
- Injectable transport backends for deterministic loss/failure tests
- Local real-adapter integration test for HTTP raw-byte echo and WebSocket text/binary echo
- Serializer, envelope, authentication, acknowledgement, idempotency, and domain protocol adapters remain project-owned

Exit criteria for a stable release: exported desktop/Web/mobile validation, TLS integration coverage, and documented protocol-adapter examples. The current API does not claim reliable delivery, automatic WebSocket replay, browser-native ping support, ENet coverage, or one universal networking abstraction.

## 0.5 Tooling And Distribution

Status: implemented in the current development branch. Asset Library publication and release-tag creation remain maintainer operations.

- Framework configuration validator, structured issue codes, editor dock, and headless runner
- Declarative module metadata that can be validated without executing runtime modules in the editor
- Deterministic Godot Asset Library-compatible package with checksum and clean-project installation test
- Release-tag workflow with exact version matching and development-version rejection
- Semantic versioning, changelog, upgrade guide, distribution guide, and API stability tiers
- Bounded event backlog and performance smoke benchmarks with machine-readable results

Exit criteria: Godot 4.4.1 and 4.7.1 validation, reproducible addon-only ZIP output, clean-project installation, documented compatibility policy, and no application-specific content.

## Explicit Non-Goals

- Gameplay, combat, inventory, quests, abilities, AI, levels, and application procedures
- A mandatory ECS or entity model
- A mandatory UI visual style
- Arbitrary script hot reload in exported games
- Security through obscurity for local save files
- One networking API that hides fundamentally different consistency models
