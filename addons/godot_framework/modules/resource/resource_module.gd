class_name GFResourceModule
extends GFModule

var service: GFResourceService
var module_settings: GFResourceSettings


func module_id() -> StringName:
	return &"resource"


func initialize() -> Error:
	module_settings = settings as GFResourceSettings
	if module_settings == null:
		module_settings = GFResourceSettings.new()
	service = GFResourceService.new()
	service.cache_enabled = module_settings.cache_loaded_resources
	return context.services.register(GFServiceIds.RESOURCES, service)


func update(_delta: float) -> void:
	service.poll(module_settings.max_threaded_requests_per_frame)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.RESOURCES, service)
	if service != null:
		service.clear()
	service = null
	module_settings = null
