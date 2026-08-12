class_name GFStateMachineModule
extends GFModule

var service: GFStateMachineService


func module_id() -> StringName:
	return &"state_machine"


func initialize() -> Error:
	service = GFStateMachineService.new()
	return context.services.register(GFServiceIds.STATE_MACHINES, service)


func update(delta: float) -> void:
	service.update(delta)


func physics_update(delta: float) -> void:
	service.physics_update(delta)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.STATE_MACHINES, service)
	if service != null:
		service.clear()
	service = null
