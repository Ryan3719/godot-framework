class_name GFInputModule
extends GFModule

var service: GFInputService
var module_settings: GFInputSettings


func module_id() -> StringName:
	return &"input"


func initialize() -> Error:
	module_settings = settings as GFInputSettings
	if module_settings == null:
		module_settings = GFInputSettings.new()
	for action: StringName in module_settings.managed_actions:
		if action.is_empty():
			return ERR_INVALID_DATA
		if not InputMap.has_action(action):
			return ERR_DOES_NOT_EXIST
	service = GFInputService.new(module_settings.managed_actions)
	return context.services.register(GFServiceIds.INPUT, service)


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.INPUT, service)
	service = null
	module_settings = null
