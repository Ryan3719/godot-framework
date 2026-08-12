class_name GFSettingsModule
extends GFModule

var service: GFSettingsService
var module_settings: GFSettingsSettings


func module_id() -> StringName:
	return &"settings"


func initialize() -> Error:
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
