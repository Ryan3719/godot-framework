class_name GFConnectivityModule
extends GFModule

var service: GFConnectivityService
var module_settings: GFConnectivitySettings


func module_id() -> StringName:
	return &"connectivity"


func initialize() -> Error:
	module_settings = settings as GFConnectivitySettings
	if module_settings == null:
		module_settings = GFConnectivitySettings.new()
	var validation := module_settings.validate()
	if not validation.is_empty():
		return ERR_INVALID_DATA
	service = GFConnectivityService.new(context.host, module_settings)
	return context.services.register(GFServiceIds.CONNECTIVITY, service)


func start() -> Error:
	return service.start()


func update(delta: float) -> void:
	service.update(delta)


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.CONNECTIVITY, service)
		service.shutdown()
	service = null
	module_settings = null
