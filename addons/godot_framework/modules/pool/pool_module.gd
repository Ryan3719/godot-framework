class_name GFPoolModule
extends GFModule

var service: GFPoolService


func module_id() -> StringName:
	return &"pool"


func initialize() -> Error:
	service = GFPoolService.new()
	return context.services.register(GFServiceIds.POOLS, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.POOLS, service)
	if service != null:
		service.clear()
	service = null
