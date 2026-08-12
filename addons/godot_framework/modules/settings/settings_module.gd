class_name GFSettingsModule
extends GFModule

var service: GFSettingsService
var module_settings: GFSettingsSettings


func module_id() -> StringName:
	return &"settings"


func validate_configuration() -> String:
	if settings != null and not settings is GFSettingsSettings:
		return "Settings module settings must use GFSettingsSettings."
	var candidate := settings as GFSettingsSettings if settings != null else GFSettingsSettings.new()
	return candidate.validate()


func initialize() -> Error:
	if not validate_configuration().is_empty():
		return ERR_INVALID_DATA
	module_settings = settings as GFSettingsSettings
	if module_settings == null:
		module_settings = GFSettingsSettings.new()
	service = GFSettingsService.new(module_settings)
	var result := service.load()
	if result != OK:
		return result
	return context.services.register(GFServiceIds.SETTINGS, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.SETTINGS, service)
	if service != null and service.is_dirty():
		service.save()
	service = null
	module_settings = null
