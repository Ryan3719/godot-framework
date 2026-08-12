class_name GFLocalizationService
extends RefCounted

signal locale_changed(previous: String, current: String)
signal translation_added(translation: Translation)
signal translation_removed(translation: Translation)

var last_error := ""

var _supported: PackedStringArray
var _fallback: String
var _owned_translations: Array[Translation] = []
var _translations_by_locale: Dictionary = {}


func _init(supported_locales: PackedStringArray, fallback_locale: String) -> void:
	_supported = _normalize_locales(supported_locales)
	_fallback = TranslationServer.standardize_locale(fallback_locale)
	if _fallback.is_empty():
		_fallback = "en"
	if not _supported.is_empty() and not _supported.has(_fallback):
		_supported.append(_fallback)


func supported_locales() -> PackedStringArray:
	return _supported.duplicate()


func fallback_locale() -> String:
	return _fallback


func current_locale() -> String:
	return TranslationServer.get_locale()


func set_locale(locale: String) -> Error:
	var standardized := TranslationServer.standardize_locale(locale)
	if standardized.is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Locale cannot be empty.")
	if not _supported.is_empty() and not _supported.has(standardized):
		return _fail(ERR_DOES_NOT_EXIST, "Locale '%s' is not supported." % standardized)
	var previous := current_locale()
	if previous == standardized:
		return OK
	TranslationServer.set_locale(standardized)
	locale_changed.emit(previous, standardized)
	return OK


func choose_best_locale(requested: String) -> String:
	var standardized := TranslationServer.standardize_locale(requested)
	if _supported.is_empty():
		return standardized if not standardized.is_empty() else _fallback
	if _supported.has(standardized):
		return standardized
	var language := standardized.get_slice("_", 0)
	for candidate: String in _supported:
		if candidate.get_slice("_", 0) == language:
			return candidate
	return _fallback


func add_translation(translation: Translation) -> Error:
	if translation == null:
		return ERR_INVALID_PARAMETER
	if _owned_translations.has(translation):
		return ERR_ALREADY_EXISTS
	TranslationServer.add_translation(translation)
	_owned_translations.append(translation)
	var locale := TranslationServer.standardize_locale(translation.locale)
	if not _translations_by_locale.has(locale):
		_translations_by_locale[locale] = []
	(_translations_by_locale[locale] as Array).append(translation)
	translation_added.emit(translation)
	return OK


func remove_translation(translation: Translation) -> bool:
	if translation == null or not _owned_translations.has(translation):
		return false
	TranslationServer.remove_translation(translation)
	_owned_translations.erase(translation)
	var locale := TranslationServer.standardize_locale(translation.locale)
	if _translations_by_locale.has(locale):
		var translations: Array = _translations_by_locale[locale]
		translations.erase(translation)
		if translations.is_empty():
			_translations_by_locale.erase(locale)
	translation_removed.emit(translation)
	return true


func translate(message: StringName, context: StringName = &"") -> String:
	return TranslationServer.translate(message, context)


func translate_plural(
	message: StringName,
	plural_message: StringName,
	n: int,
	context: StringName = &"",
) -> String:
	return TranslationServer.translate_plural(message, plural_message, n, context)


func format(message: StringName, values: Variant, context: StringName = &"") -> String:
	return translate(message, context).format(values)


func has_message(message: StringName, locale := "", context: StringName = &"") -> bool:
	if message.is_empty():
		return false
	if locale.is_empty():
		return TranslationServer.translate(message, context) != str(message)
	var target_locale := TranslationServer.standardize_locale(locale)
	for translation: Translation in _translations_by_locale.get(target_locale, []):
		if not translation.get_message(message, context).is_empty():
			return true
	return false


func validate_messages(messages: Array[StringName], locales: PackedStringArray = []) -> Dictionary:
	var targets := locales if not locales.is_empty() else _supported
	if targets.is_empty():
		targets = PackedStringArray([current_locale()])
	var missing: Dictionary = {}
	for locale: String in targets:
		var locale_missing: Array[StringName] = []
		for message: StringName in messages:
			if not has_message(message, locale):
				locale_missing.append(message)
		if not locale_missing.is_empty():
			missing[locale] = locale_missing
	return missing


func shutdown() -> void:
	for translation: Translation in _owned_translations.duplicate():
		remove_translation(translation)


func _normalize_locales(locales: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for locale: String in locales:
		var standardized := TranslationServer.standardize_locale(locale)
		if not standardized.is_empty() and not result.has(standardized):
			result.append(standardized)
	return result


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
