class_name GFSceneModule
extends GFModule

var service: GFSceneService


func module_id() -> StringName:
	return &"scene"


func dependencies() -> Array[StringName]:
	return [&"resource"]


func initialize() -> Error:
	var resource_service := context.services.resolve(GFServiceIds.RESOURCES) as GFResourceService
	service = GFSceneService.new(context.tree(), resource_service)
	return context.services.register(GFServiceIds.SCENES, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.SCENES, service)
	service = null
