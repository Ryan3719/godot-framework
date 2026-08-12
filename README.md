# Godot Framework

A modular, business-agnostic game framework for Godot 4.4+.

> Status: `0.1.0-dev`. The foundation is usable and tested, but public APIs may change before the first stable release.

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

Every feature except the small runtime kernel is optional through `GFFrameworkConfig`.

## Install

Copy `addons/godot_framework` into a Godot 4.4+ project and enable **Project > Project Settings > Plugins > Godot Framework**. The plugin registers the `GodotFramework` autoload and the default configuration.

To customize modules, duplicate:

```text
res://addons/godot_framework/config/default_framework_config.tres
```

Move the duplicate outside `addons/`, then set `godot_framework/config_path` in Project Settings to that resource. Keeping project-owned configuration outside the addon prevents updates from overwriting it.

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

The test project currently runs 80 assertions plus an end-to-end scene transition test, and exits non-zero on failure.

## Documentation

- [Architecture](docs/architecture.md)
- [Research and design decisions](docs/research.md)
- [Extending the framework](docs/extending.md)
- [Roadmap](docs/roadmap.md)

## License

Licensed under the [MIT License](LICENSE).
