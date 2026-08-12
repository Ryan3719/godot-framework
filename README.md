# Godot Framework

A modular, business-agnostic game framework for Godot 4.4+.

> Status: `0.3.0-dev`. Foundation, presentation, and content-delivery modules are usable and tested, but public APIs may change before the first stable release.

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

Every feature except the small runtime kernel is optional through `GFFrameworkConfig`.

## Install

Copy `addons/godot_framework` into a Godot 4.4+ project and enable **Project > Project Settings > Plugins > Godot Framework**. The plugin registers the `GodotFramework` autoload and the default configuration.

To customize modules, duplicate:

```text
res://addons/godot_framework/config/default_framework_config.tres
```

Move the duplicate outside `addons/`, then set `godot_framework/config_path` in Project Settings to that resource. Keeping project-owned configuration outside the addon prevents updates from overwriting it.

UI, audio, input, localization, download, content, and table definitions are included but disabled in the addon default. Enable only the modules a project uses, then assign project-owned settings resources. This keeps a fresh installation from creating render, audio, or network nodes, managing input actions, changing locale, or mounting external content.

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

## Verify

```bash
godot --headless --editor --quit --path .
godot --headless --verbose --path .
```

The test project currently runs 250 assertions plus end-to-end scene-transition and real PCK-mount tests, and exits non-zero on failure. CI treats parse errors, engine errors, leaked objects, and resources left in use as failures.

## Documentation

- [Architecture](docs/architecture.md)
- [Research and design decisions](docs/research.md)
- [Extending the framework](docs/extending.md)
- [Roadmap](docs/roadmap.md)
- [Content delivery](docs/content_delivery.md)

## License

Licensed under the [MIT License](LICENSE).
