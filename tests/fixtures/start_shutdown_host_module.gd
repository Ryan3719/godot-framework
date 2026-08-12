class_name GFStartShutdownHostTestModule
extends GFModule


func module_id() -> StringName:
	return &"start_shutdown_host"


func start() -> Error:
	context.host.shutdown()
	return OK


func shutdown() -> void:
	context.host.shutdown()
