# Extending The Framework

## Module Contract

Extend `GFModule` and implement at least a non-empty `module_id()`. Declare every module-level dependency, register capabilities in `initialize()`, begin runtime work in `start()`, and release everything in `shutdown()`.

Do not assume `start()` will run. Both `initialize()` and `start()` can fail, and the manager calls `shutdown()` on partially initialized modules during rollback.

```gdscript
class_name ExampleModule
extends GFModule

const SERVICE_ID := &"example"
var service: ExampleService

func module_id() -> StringName:
	return &"example"

func dependencies() -> Array[StringName]:
	return [&"settings"]

func initialize() -> Error:
	service = ExampleService.new()
	return context.services.register(SERVICE_ID, service)

func start() -> Error:
	return service.connect_to_backend()

func shutdown() -> void:
	if context != null:
		context.services.unregister(SERVICE_ID, service)
	if service != null:
		service.close()
	service = null
```

## Add Configuration

Create a typed `Resource` for authorable settings and accept it through the inherited `settings` property. Always provide safe defaults when configuration is optional. Return an error when required fields are missing; do not silently hardcode production endpoints, content IDs, or platform secrets.

```gdscript
class_name ExampleSettings
extends Resource

@export var endpoint := ""
@export_range(1, 60, 1) var timeout_seconds := 10
```

Create a `GFModuleDefinition`, assign the following fields, and append it to the project's `GFFrameworkConfig`:

- `declared_id`: exactly the value returned by `module_id()`
- `declared_dependencies`: exactly the array returned by `dependencies()`
- `module_script`: the script extending `GFModule`
- `expected_settings_class`: the global class name of the settings resource, when the module has typed settings
- `settings`: the project-owned settings resource, when required

The declaration is intentionally redundant. Editor validation can inspect it without instantiating runtime modules, while boot verifies it against the module script and refuses mismatches. Keep both sides synchronized when an ID or dependency changes.

The default configuration already contains disabled definitions for UI, audio, input, localization, download, content, tables, and connectivity. Duplicate the framework and relevant settings resources outside `addons/`, then enable the definitions in the project copy. Do not edit addon defaults because an upgrade can replace them.

For UI, keep layers and route metadata in `GFUISettings`, and keep concrete scenes and application behavior in the project. For input, list only actions the framework may rebind. For localization, configure the supported locale allowlist and fallback explicitly. Audio groups must reference buses that exist in the project.

For downloadable content, use `GFContentService.release_directory()` and `pack_path()` to derive safe staging targets, feed those paths to `GFDownloadService`, then call `install_release()` only after all task completions. Embed only the public verification key in the client; the private signing key belongs in an offline release pipeline.

Configuration-table integrations extend `GFTableProvider`. A provider owns parsing, generated types, indexing, and source format. The framework registry owns provider lifetime and routing only, so Luban support can ship as a separate adapter without making it a mandatory dependency.

Connectivity configuration owns transport limits and WebSocket endpoints, not application protocol. Send raw request or frame bytes through `GFConnectivityService.http` and `.websockets`; put JSON, MessagePack, Protobuf, authentication refresh, acknowledgements, and domain error mapping in project adapters. Use `.requests` when an application protocol needs correlation IDs, then place that ID in the application's own envelope.

Do not automatically resend WebSocket application messages after reconnect unless the protocol defines idempotency and acknowledgement rules. Godot's native WebSocket ping interval is unavailable in Web exports, so browser-compatible application heartbeats also belong in the protocol adapter.

## Service Ownership

A module owns every service it registers. Use identity-checked unregister when several implementations may share an ID:

```gdscript
context.services.unregister(SERVICE_ID, service)
```

Consumers resolve a capability during use or retain it only within a clearly shorter lifetime. Avoid storing the autoload in domain model objects.

## Event Ownership

`subscribe()` returns an integer token. The subscriber owns that token and should unsubscribe during teardown. Use `once = true` for single-response flows. Avoid callbacks that capture a bus forever; buses keep callbacks alive until unsubscribed or cleared.

Events are facts and use past-tense IDs such as `save.completed`. Commands are requests and use verbs such as `profile.save`. Queries describe reads such as `profile.current`.

Queued events have a framework-wide capacity configured by `GFFrameworkConfig.max_queued_events`. Check the `Error` returned by `queue()` when delivery matters; `ERR_OUT_OF_MEMORY` means the bounded backlog rejected the new event. `max_queued_events_per_frame` controls consumption and does not change total capacity.

## State Machines

`GFStateMachine` is deliberately generic. Define application states outside the addon. States receive a weak reference to their machine through `get_machine()`, preventing `RefCounted` cycles. Call `clear()` when a machine's owner ends.

## Tests

Add deterministic headless assertions to `tests/test_runner.gd`. Tests must cover the successful path, invalid input, ownership cleanup, and failure rollback for lifecycle code. Run both commands from the repository root:

```bash
godot --headless --editor --quit --path .
godot --headless --verbose --path .
godot --headless --verbose --path . tests/config_validation_runner.tscn
```

Treat leak warnings as failures even when Godot exits with code zero.

Audio tests should inject playback start and stop callables into `GFAudioService`. Native `AudioStreamPlayer.play()` and `stop()` are not virtual GDScript methods, and live dummy-server playback can retain engine playback references at headless shutdown. Production construction leaves the callables empty and uses the native methods.
