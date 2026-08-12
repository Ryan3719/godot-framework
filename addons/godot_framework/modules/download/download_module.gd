class_name GFDownloadModule
extends GFModule

var service: GFDownloadService
var module_settings: GFDownloadSettings


func module_id() -> StringName:
	return &"download"


func initialize() -> Error:
	module_settings = settings as GFDownloadSettings
	if module_settings == null:
		module_settings = GFDownloadSettings.new()
	var validation := module_settings.validate()
	if not validation.is_empty():
		return ERR_INVALID_DATA
	service = GFDownloadService.new(context.host, module_settings)
	return context.services.register(GFServiceIds.DOWNLOADS, service)


func update(delta: float) -> void:
	service.update(delta)


func shutdown() -> void:
	if service != null:
		context.services.unregister(GFServiceIds.DOWNLOADS, service)
		service.shutdown()
	service = null
	module_settings = null
