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

Create a `GFModuleDefinition`, assign the module script and settings resource, and append it to the project's `GFFrameworkConfig`.

## Service Ownership

A module owns every service it registers. Use identity-checked unregister when several implementations may share an ID:

```gdscript
context.services.unregister(SERVICE_ID, service)
```

Consumers resolve a capability during use or retain it only within a clearly shorter lifetime. Avoid storing the autoload in domain model objects.

## Event Ownership

`subscribe()` returns an integer token. The subscriber owns that token and should unsubscribe during teardown. Use `once = true` for single-response flows. Avoid callbacks that capture a bus forever; buses keep callbacks alive until unsubscribed or cleared.

Events are facts and use past-tense IDs such as `save.completed`. Commands are requests and use verbs such as `profile.save`. Queries describe reads such as `profile.current`.

## State Machines

`GFStateMachine` is deliberately generic. Define application states outside the addon. States receive a weak reference to their machine through `get_machine()`, preventing `RefCounted` cycles. Call `clear()` when a machine's owner ends.

## Tests

Add deterministic headless assertions to `tests/test_runner.gd`. Tests must cover the successful path, invalid input, ownership cleanup, and failure rollback for lifecycle code. Run both commands from the repository root:

```bash
godot --headless --editor --quit --path .
godot --headless --verbose --path .
```

Treat leak warnings as failures even when Godot exits with code zero.
