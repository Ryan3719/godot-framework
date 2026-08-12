@tool
class_name GFLocalizationSettings
extends Resource

@export var supported_locales: PackedStringArray = []
@export var fallback_locale := "en"
@export var use_system_locale := true


func validate() -> String:
	var fallback := TranslationServer.standardize_locale(fallback_locale)
	if fallback.is_empty():
		return "Localization fallback locale is invalid."
	var seen := PackedStringArray()
	for locale: String in supported_locales:
		var standardized := TranslationServer.standardize_locale(locale)
		if standardized.is_empty():
			return "Localization settings contain an invalid locale."
		if seen.has(standardized):
			return "Duplicate supported locale '%s'." % standardized
		seen.append(standardized)
	return ""
