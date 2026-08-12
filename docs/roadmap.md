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

- Optional UI navigation service with layers, history, modal policy, and project-owned views
- Audio buses, groups, playback handles, concurrency limits, and fades
- Input remapping profiles and device-change signals
- Localization facade over Godot TranslationServer with content validation

Exit criteria: modules can be removed independently and do not ship branded screens or concrete game flow.

## 0.3 Content Delivery

- Resource ownership handles and cache policies
- PCK manifest, download, integrity/signature verification, mount, rollback, and recovery
- HTTP download queue with retry, throttling, cancellation, and resumability where supported
- Configuration-table adapter interfaces; Luban integration remains an optional external package

Exit criteria: exported desktop/mobile validation and an explicit threat model. Resource hot update is not declared supported before this milestone exits.

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
