class_name GFInputModule
extends GFModule

var service: GFInputService
var module_settings: GFInputSettings


func module_id() -> StringName:
	return &"input"


func validate_configuration() -> String:
	if settings != null and not settings is GFInputSettings:
		return "Input module settings must use GFInputSettings."
	var candidate := settings as GFInputSettings if settings != null else GFInputSettings.new()
	return candidate.validate()


func initialize() -> Error:
	var validation := validate_configuration()
	if not validation.is_empty():
		return ERR_DOES_NOT_EXIST if validation.contains("does not exist") else ERR_INVALID_DATA
	module_settings = settings as GFInputSettings
	if module_settings == null:
		module_settings = GFInputSettings.new()
	service = GFInputService.new(module_settings.managed_actions)
	return context.services.register(GFServiceIds.INPUT, service)


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.INPUT, service)
	service = null
	module_settings = null
