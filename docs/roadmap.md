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

Exit criteria: modules can be removed independently and do not ship branded screens or concrete game flow.

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

- Transport interface and connection lifecycle
- HTTP/WebSocket adapters first; ENet adapter based on demonstrated multiplayer use cases
- Request correlation, timeout, cancellation, reconnect, heartbeat, and backpressure
- Serializer and protocol adapters owned outside core

Exit criteria: transport tests with simulated loss/failure and no protocol-specific dependency in the kernel.

## 0.5 Tooling And Distribution

- Framework configuration inspector and validation dock
- Godot Asset Library-compatible package
- Semantic versioning, changelog, upgrade guides, and API stability tiers
- Performance benchmarks and allocation budgets

## Explicit Non-Goals

- Gameplay, combat, inventory, quests, abilities, AI, levels, and application procedures
- A mandatory ECS or entity model
- A mandatory UI visual style
- Arbitrary script hot reload in exported games
- Security through obscurity for local save files
- One networking API that hides fundamentally different consistency models
