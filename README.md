# Godot Framework

A modular, business-agnostic game framework for Godot 4.4+.

> Status: `0.5.0-dev`. Foundation, presentation, content-delivery, connectivity, validation, and distribution tooling are implemented and tested, but public APIs may change before the first stable release.

Godot Framework provides reusable infrastructure without prescribing a game genre, screen flow, data model, or application architecture. It uses Godot's scene tree, signals, Resources, and loaders directly instead of recreating Unity's runtime model.

## Implemented

- Dependency-aware module lifecycle with rollback on failed initialization or startup
- Service container with explicit service IDs
- Synchronous and queued event bus with priorities and safe reentrant unsubscribe
- Command/query message bus for directed application intents and reads
- Structured logger
- Synchronous and threaded resource loading with an explicit cache
- Scene switching service with transition signals
- Versioned, recoverable local storage with backups and sequential migrations
- `ConfigFile`-backed user settings
- Generic object pools with ownership validation
- Generic finite state machines with guarded transitions
- Layered UI navigation with project-owned routes and view lifecycles
- Grouped audio playback with handles, concurrency limits, and runtime controls
- Input remapping profiles scoped to an explicit action allowlist
- Locale selection, owned translations, formatting, and translation-key validation
- Resource ownership handles with transient, leased, and retained cache policies
- Transactional HTTP download queue with concurrency, retry, cancellation, size, and SHA-256 validation
- Signed PCK release manifests with staged installation, startup activation, and persistent rollback
- Provider-neutral configuration-table registry
- Bounded HTTP request queue with raw byte bodies, cancellation, timeouts, tags, and response limits
- WebSocket channel state machines with reconnect policy, native ping intervals, receive budgets, and send backpressure
- Protocol-neutral correlation tracker with resolve, timeout, and cancellation lifecycles
- Configuration validator with structured issue codes and an editor dock
- Bounded queued-event memory with explicit overflow errors
- Deterministic Asset Library-compatible addon packaging and clean-project installation checks

Every feature except the small runtime kernel can be enabled or disabled at runtime through `GFFrameworkConfig`. The current distribution is one cohesive addon package: disabled module scripts remain present and referenced by the addon default configuration. It does not yet claim per-module package installation or deletion-safe physical stripping.

## Install

Copy `addons/godot_framework` into a Godot 4.4+ project and enable **Project > Project Settings > Plugins > Godot Framework**. The plugin registers the `GodotFramework` autoload and the default configuration.

To customize modules, duplicate:

```text
res://addons/godot_framework/config/default_framework_config.tres
```

Move the duplicate outside `addons/`, then set `godot_framework/config_path` in Project Settings to that resource. Keeping project-owned configuration outside the addon prevents updates from overwriting it.

UI, audio, input, localization, download, content, table, and connectivity definitions are included but disabled in the addon default. Enable only the modules a project uses, then assign project-owned settings resources. This keeps a fresh installation from creating render, audio, or network nodes, managing input actions, changing locale, or mounting external content.

## Use

Resolve services through the framework host rather than reaching into module instances:

```gdscript
var events := GodotFramework.get_service(GFServiceIds.EVENTS) as GFEventBus
var token := events.subscribe(&"inventory.changed", _on_inventory_changed)
events.publish(&"inventory.changed", {"slot": 3})

var storage := GodotFramework.get_service(GFServiceIds.STORAGE) as GFStorageService
storage.save(&"profile_1", {"level": 4, "position": Vector3.ZERO})
```

Event subscriptions are explicit ownership. Store the token and unsubscribe it, or call `clear()` on a bus you own. For one-to-one operations, prefer the message bus over broadcasting events.

## Create A Module

```gdscript
class_name TelemetryModule
extends GFModule

func module_id() -> StringName:
	return &"telemetry"

func dependencies() -> Array[StringName]:
	return [&"settings"]

func initialize() -> Error:
	return context.services.register(&"telemetry", TelemetryService.new())

func shutdown() -> void:
	context.services.unregister(&"telemetry")
```

Add the script to a `GFModuleDefinition` in your project-owned `GFFrameworkConfig`. See [Extending the framework](docs/extending.md) for lifecycle and ownership rules.

Every definition declares `declared_id` and `declared_dependencies` in addition to its script. The framework validates these declarations without running module code in the editor, then verifies them against the instantiated module at runtime.

## Verify

```bash
godot --headless --editor --quit --path .
godot --headless --verbose --path .
godot --headless --verbose --path . tests/config_validation_runner.tscn
godot --headless --verbose --path . tests/performance_runner.tscn
```

The test project currently runs 366 assertions plus configuration, performance-smoke, clean-package installation, Linux release-export execution, scene-transition, real PCK-mount, and local HTTP/WebSocket adapter tests. The CI matrix uses matching export templates for Godot 4.4.1 and 4.7.1 and treats parse errors, engine errors, leaked objects, and resources left in use as failures.

## Documentation

- [Architecture](docs/architecture.md)
- [Research and design decisions](docs/research.md)
- [Extending the framework](docs/extending.md)
- [Roadmap](docs/roadmap.md)
- [Content delivery](docs/content_delivery.md)
- [Connectivity](docs/connectivity.md)
- [Distribution](docs/distribution.md)
- [Performance](docs/performance.md)
- [Versioning and API stability](docs/versioning.md)
- [Upgrading](docs/upgrading.md)
- [Changelog](CHANGELOG.md)

## License

Licensed under the [MIT License](LICENSE).
