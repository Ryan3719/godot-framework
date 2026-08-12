class_name GFStorageModule
extends GFModule

var service: GFStorageService
var module_settings: GFStorageSettings


func module_id() -> StringName:
	return &"storage"


func initialize() -> Error:
	module_settings = settings as GFStorageSettings
	if module_settings == null:
		module_settings = GFStorageSettings.new()
	service = GFStorageService.new(module_settings)
	return context.services.register(GFServiceIds.STORAGE, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.STORAGE, service)
	service = null
	module_settings = null
