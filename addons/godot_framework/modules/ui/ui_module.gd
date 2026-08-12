class_name GFUIModule
extends GFModule

var service: GFUIService
var module_settings: GFUISettings


func module_id() -> StringName:
	return &"ui"


func validate_configuration() -> String:
	if settings != null and not settings is GFUISettings:
		return "UI module settings must use GFUISettings."
	var candidate := settings as GFUISettings if settings != null else GFUISettings.new()
	return candidate.validate()


func initialize() -> Error:
	if not validate_configuration().is_empty():
		return ERR_INVALID_DATA
	module_settings = settings as GFUISettings
	if module_settings == null:
		module_settings = GFUISettings.new()
	service = GFUIService.new(context.host, module_settings.root_name)
	for layer: GFUILayerDefinition in module_settings.layers:
		var result := service.register_layer(layer)
		if result != OK:
			return result
	for route: GFUIRoute in module_settings.routes:
		var result := service.register_route(route)
		if result != OK:
			return result
	return context.services.register(GFServiceIds.UI, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.UI, service)
	if service != null:
		service.shutdown()
	service = null
	module_settings = null
