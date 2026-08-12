# Architecture

## Scope

The framework owns infrastructure. A game owns domain rules and presentation.

Framework code may provide lifecycle, communication, persistence mechanics, resource access, scene switching, pooling, and generic algorithms. It must not define gameplay states, player data, combat formulas, UI pages, item schemas, analytics events, server protocols, or content IDs.

## Layers

```text
Application / game
  Scenes, UI, domain state, gameplay systems, project adapters
                         |
Optional framework modules
  Resource, scene, storage, settings, pool, state machine,
  UI, audio, input, localization, download, content, tables,
  connectivity
                         |
Stable framework kernel
  Host, module lifecycle, services, events, messages, logging
                         |
Godot 4
  SceneTree, Node, Signal, Resource, ResourceLoader, FileAccess
```

Dependencies point downward. The kernel never imports optional modules. Modules communicate through service IDs and declared module dependencies. Application code can replace a module by providing the same project-level contract.

## Runtime

`GFFrameworkHost` is the only framework autoload. At boot it creates the kernel services, instantiates enabled `GFModuleDefinition` resources, topologically sorts dependencies, initializes all modules, then starts them. The object pool accepts Godot `Object` instances (`Node`, `RefCounted`, `Resource`, and derived types), whose engine instance IDs provide stable ownership identity; value containers are intentionally excluded.

```text
created -> initializing -> initialized -> started -> stopped
                      \-> failed -------/
```

If an initialization or startup step fails, the failing module and every initialized module receive `shutdown()` in reverse dependency order. Missing dependencies, duplicate IDs, and cycles are boot errors.

The host forwards `_process` and `_physics_process` only after startup. Shutdown reverses module order, clears buses and services, then releases configuration references.

## Communication

Use the narrowest mechanism that fits:

| Need | Mechanism | Cardinality |
| --- | --- | --- |
| Resolve a long-lived capability | `GFServiceContainer` | many consumers to one service |
| Broadcast a fact that already happened | `GFEventBus` | one publisher to many subscribers |
| Request one operation | `GFMessageBus.send` | one caller to one handler |
| Read derived state | `GFMessageBus.ask` | one caller to one handler with a result |
| Local node relationship | Godot signal or direct method | scene-owned |

The event bus does not replace every Godot signal. Signals remain the natural API inside a scene or component boundary. The bus is for cross-system events where sender and receivers should not know one another.

## Configuration

Framework and module configuration uses typed Godot `Resource` objects. The addon includes defaults, but projects should duplicate them outside `addons/` and reference their copy through `godot_framework/config_path`.

Resources hold authorable configuration. Runtime save data is restricted to object-free Variants and never serializes `Node`, `Resource`, texture, audio, or arbitrary script objects.

The addon default enables the foundation modules and keeps UI, audio, input, localization, download, content, tables, and connectivity disabled. Enabling those modules is an explicit project decision:

- UI owns a node root and configured `CanvasLayer` instances. Routes point to project-owned scenes whose roots extend `GFUIView`; the framework owns navigation lifecycle, not screen content.
- Audio owns its players beneath one node root. Project configuration defines logical groups and buses, while playback handles and group volume are runtime state.
- Input can modify only the `InputMap` actions listed in `GFInputSettings`. It captures their original bindings as restore points and leaves all other actions untouched.
- Localization selects only configured locales, owns only translations added through its service, and restores the previous global locale when its module shuts down.

Each presentation module can be removed independently. In particular, UI uses Godot `PackedScene` directly and has no artificial dependency on the resource module.

## Content Delivery

Resource handles make ownership explicit without replacing Godot's loader. A transient handle does not enter the framework cache, a leased handle keeps one shared cache entry until its last owner releases it, and a retained handle remains cached until explicit eviction. Every owner must call `GFResourceHandle.release()`; finalization is deliberately not an ownership boundary because deterministic cleanup must not depend on engine destruction order. Module shutdown still clears all framework cache state. Legacy `load()` calls retain their cache entries for backward compatibility.

The download module owns queue policy and file transactions while `GFHTTPDownloadBackend` delegates transport to Godot `HTTPRequest`. Each task streams into a unique `.part` file under a configured `user://` directory, validates optional length and SHA-256, then replaces its target through a backup. Cancellation and failed validation remove the partial file without overwriting a previous target.

The content module accepts detached RSA-SHA256 signatures over the exact manifest UTF-8 bytes. It validates every declared PCK path, length, and hash before writing an installation record. Activation changes a small persistent `active`/`previous` pointer; startup mounts the active release in manifest order.

Godot 4.4 exposes `ProjectSettings.load_resource_pack()` but no matching unload API. Consequently, a partially mounted release cannot be removed from the current process. The module restores the previous activation pointer for the next startup, locks further mounts, and exposes `restart_required`. It never claims same-process PCK rollback.

The table module is only a provider registry. It does not impose JSON, CSV, Luban, SQLite, row ID, or generated-code conventions on applications.

## Connectivity

`GFConnectivityService` groups three distinct capabilities without pretending they share one transport contract. `GFHTTPService` owns bounded request concurrency, queued-body memory limits, cancellation, transport timeouts, and response size limits. An HTTP response is transport-complete regardless of status code; application adapters decide whether `404`, `409`, or `503` represents a domain success, retry, or failure.

`GFWebSocketService` owns named channel lifecycles, non-blocking connection polling, optional reconnect schedules, per-frame receive budgets, maximum packet size, and high/low send-buffer watermarks. It exposes raw text/binary frames and never parses envelopes, invents message IDs, or automatically replays packets after reconnect. Applications that require delivery guarantees must define acknowledgements, idempotency, ordering, and replay policy in their protocol adapter.

Godot 4.4 `WebSocketPeer` supplies native ping control frames through `heartbeat_interval`, but Web exports ignore that property due to browser restrictions. Browser deployments that require liveness detection need an application-protocol heartbeat. `GFRequestTracker` provides only correlation ID ownership plus resolve/timeout/cancel lifecycle; it deliberately does not serialize or route protocol messages.

## Storage Safety

Storage writes an object-free Variant envelope to a temporary file, rotates backups, then replaces the primary file. Deserialization explicitly disables object construction. Schema upgrades run one registered migration per version and reject future schemas.

This is a recoverable local persistence mechanism, not an encrypted or tamper-resistant format. Competitive or authoritative state belongs on a trusted server. Platform APIs differ in filesystem guarantees, so the framework does not claim strict cross-platform atomicity.

## Extension Rules

- A module ID is stable public API.
- Every dependency is returned by `dependencies()`; hidden order dependencies are defects.
- A module registers services during `initialize()` and removes them during `shutdown()`.
- `shutdown()` must tolerate partial initialization and repeated framework teardown.
- Long-lived references from child objects to owners use weak references when both sides are `RefCounted`.
- Cross-frame work has an explicit per-frame budget.
- Optional modules do not become implicit global singletons.
- Domain constants and game content never enter the framework addon.

## Headless Boundaries

`GFAudioService` normally calls `AudioStreamPlayer.play()` and `stop()`. Its constructor also accepts playback callables so deterministic headless tests can exercise ownership and concurrency without creating a live `AudioServer` playback. This is a test boundary, not a second production audio backend.

Download tests inject `GFDownloadBackend` instances to simulate status codes and partial files deterministically. Content tests inject a mount callable for failure/rollback paths, while a separate process creates and mounts a real PCK through Godot's engine API. Connectivity tests inject HTTP and WebSocket backends for timeout, reconnect, receive-budget, and backpressure paths; a local loopback server separately exercises the real `HTTPRequest` and `WebSocketPeer` adapters.
