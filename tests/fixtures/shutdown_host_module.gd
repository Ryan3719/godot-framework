class_name GFShutdownHostTestModule
extends GFModule


func module_id() -> StringName:
	return &"shutdown_host"


func update(_delta: float) -> void:
	context.host.shutdown()


func shutdown() -> void:
	context.host.shutdown()
