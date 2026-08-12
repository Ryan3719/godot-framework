class_name GFInitializeShutdownHostTestModule
extends GFModule


func module_id() -> StringName:
	return &"initialize_shutdown_host"


func initialize() -> Error:
	context.host.shutdown()
	return OK


func shutdown() -> void:
	context.host.shutdown()
