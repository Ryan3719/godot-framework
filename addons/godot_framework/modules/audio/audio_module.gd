class_name GFAudioModule
extends GFModule

var service: GFAudioService
var module_settings: GFAudioSettings


func module_id() -> StringName:
	return &"audio"


func initialize() -> Error:
	module_settings = settings as GFAudioSettings
	if module_settings == null:
		module_settings = GFAudioSettings.new()
	service = GFAudioService.new(context.host, module_settings.root_name)
	for group: GFAudioGroupDefinition in module_settings.groups:
		var result := service.register_group(group)
		if result != OK:
			return result
	return context.services.register(GFServiceIds.AUDIO, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.AUDIO, service)
	if service != null:
		service.shutdown()
	service = null
	module_settings = null
