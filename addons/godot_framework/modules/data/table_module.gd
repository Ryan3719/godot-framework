class_name GFTableModule
extends GFModule

var service: GFTableService


func module_id() -> StringName:
	return &"tables"


func initialize() -> Error:
	service = GFTableService.new()
	return context.services.register(GFServiceIds.TABLES, service)


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.TABLES, service)
		service.shutdown()
	service = null
