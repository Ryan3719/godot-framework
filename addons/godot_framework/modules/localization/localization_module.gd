class_name GFLocalizationModule
extends GFModule

var service: GFLocalizationService
var module_settings: GFLocalizationSettings
var _previous_locale := ""


func module_id() -> StringName:
	return &"localization"


func initialize() -> Error:
	module_settings = settings as GFLocalizationSettings
	if module_settings == null:
		module_settings = GFLocalizationSettings.new()
	service = GFLocalizationService.new(
		module_settings.supported_locales,
		module_settings.fallback_locale,
	)
	_previous_locale = TranslationServer.get_locale()
	var requested := OS.get_locale() if module_settings.use_system_locale else module_settings.fallback_locale
	var selected := service.choose_best_locale(requested)
	var result := service.set_locale(selected)
	if result != OK:
		return result
	return context.services.register(GFServiceIds.LOCALIZATION, service)


func shutdown() -> void:
	context.services.unregister(GFServiceIds.LOCALIZATION, service)
	if service != null:
		service.shutdown()
	if not _previous_locale.is_empty():
		TranslationServer.set_locale(_previous_locale)
	service = null
	module_settings = null
	_previous_locale = ""
