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
  UI, audio, input, localization
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

The addon default enables the foundation modules and keeps UI, audio, input, and localization disabled. Enabling those modules is an explicit project decision:

- UI owns a node root and configured `CanvasLayer` instances. Routes point to project-owned scenes whose roots extend `GFUIView`; the framework owns navigation lifecycle, not screen content.
- Audio owns its players beneath one node root. Project configuration defines logical groups and buses, while playback handles and group volume are runtime state.
- Input can modify only the `InputMap` actions listed in `GFInputSettings`. It captures their original bindings as restore points and leaves all other actions untouched.
- Localization selects only configured locales, owns only translations added through its service, and restores the previous global locale when its module shuts down.

Each presentation module can be removed independently. In particular, UI uses Godot `PackedScene` directly and has no artificial dependency on the resource module.

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
