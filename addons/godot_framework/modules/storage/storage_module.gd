class_name GFStorageModule
extends GFModule

var service: GFStorageService
var module_settings: GFStorageSettings


func module_id() -> StringName:
	return &"storage"


func validate_configuration() -> String:
	if settings != null and not settings is GFStorageSettings:
		return "Storage module settings must use GFStorageSettings."
	var candidate := settings as GFStorageSettings if settings != null else GFStorageSettings.new()
	return candidate.validate()


func initialize() -> Error:
	if not validate_configuration().is_empty():
		return ERR_INVALID_DATA
	module_settings = settings as GFStorageSettings
	if module_settings == null:
		module_settings = GFStorageSettings.new()
	service = GFStorageService.new(module_settings)
	return context.services.register(GFServiceIds.STORAGE, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.STORAGE, service)
	service = null
	module_settings = null
