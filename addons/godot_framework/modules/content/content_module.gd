class_name GFContentModule
extends GFModule

var service: GFContentService
var module_settings: GFContentSettings


func module_id() -> StringName:
	return &"content"


func initialize() -> Error:
	module_settings = settings as GFContentSettings
	if module_settings == null:
		module_settings = GFContentSettings.new()
	if not module_settings.validate().is_empty():
		return ERR_INVALID_DATA
	service = GFContentService.new(module_settings)
	if service.initialization_error() != OK:
		return service.initialization_error()
	return context.services.register(GFServiceIds.CONTENT, service)


func start() -> Error:
	return service.mount_active() if module_settings.auto_mount_active else OK


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.CONTENT, service)
		service.shutdown()
	service = null
	module_settings = null
