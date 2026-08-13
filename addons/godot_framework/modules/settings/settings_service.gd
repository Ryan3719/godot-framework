class_name GFSettingsService
extends RefCounted

signal value_changed(section: StringName, key: StringName, value: Variant)
signal settings_loaded(path: String)
signal settings_saved(path: String)
signal operation_failed(operation: StringName, error: Error)

var settings: GFSettingsSettings
var _config := ConfigFile.new()
var _dirty := false


func _init(service_settings: GFSettingsSettings) -> void:
	settings = service_settings


func load() -> Error:
	_config = ConfigFile.new()
	if not FileAccess.file_exists(settings.file_path):
		_dirty = false
		return OK
	var result := _config.load(settings.file_path)
	if result != OK:
		operation_failed.emit(&"load", result)
		return result
	_dirty = false
	settings_loaded.emit(settings.file_path)
	return OK


func save() -> Error:
	var directory_result := DirAccess.make_dir_recursive_absolute(settings.file_path.get_base_dir())
	if directory_result != OK and directory_result != ERR_ALREADY_EXISTS:
		operation_failed.emit(&"save", directory_result)
		return directory_result
	var result := _config.save(settings.file_path)
	if result != OK:
		operation_failed.emit(&"save", result)
		return result
	_dirty = false
	settings_saved.emit(settings.file_path)
	return OK


func set_value(section: StringName, key: StringName, value: Variant) -> Error:
	if section.is_empty() or key.is_empty() or not _is_supported(value, []):
		return ERR_INVALID_PARAMETER
	var old_value: Variant = null
	if _config.has_section_key(str(section), str(key)):
		old_value = _config.get_value(str(section), str(key))
	if typeof(old_value) == typeof(value) and old_value == value:
		return OK
	_config.set_value(str(section), str(key), value)
	_dirty = true
	value_changed.emit(section, key, value)
	return save() if settings.auto_save else OK


func get_value(section: StringName, key: StringName, default: Variant = null) -> Variant:
	return _config.get_value(str(section), str(key), default)


func has_value(section: StringName, key: StringName) -> bool:
	return _config.has_section_key(str(section), str(key))


func erase_value(section: StringName, key: StringName) -> Error:
	if not has_value(section, key):
		return ERR_DOES_NOT_EXIST
	_config.erase_section_key(str(section), str(key))
	_dirty = true
	value_changed.emit(section, key, null)
	return save() if settings.auto_save else OK


func erase_section(section: StringName) -> Error:
	if not _config.has_section(str(section)):
		return ERR_DOES_NOT_EXIST
	_config.erase_section(str(section))
	_dirty = true
	return save() if settings.auto_save else OK


func sections() -> PackedStringArray:
	return _config.get_sections()


func keys(section: StringName) -> PackedStringArray:
	return _config.get_section_keys(str(section))


func is_dirty() -> bool:
	return _dirty


func _is_supported(value: Variant, ancestors: Array[Variant]) -> bool:
	var value_type := typeof(value)
	if value_type in [
		TYPE_NIL,
		TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		TYPE_STRING_NAME,
		TYPE_VECTOR2,
		TYPE_VECTOR2I,
		TYPE_VECTOR3,
		TYPE_VECTOR3I,
		TYPE_COLOR,
		TYPE_RECT2,
		TYPE_RECT2I,
	]:
		return true
	if value_type == TYPE_ARRAY:
		if _contains_same(ancestors, value):
			return false
		var next_ancestors := ancestors.duplicate()
		next_ancestors.append(value)
		for item: Variant in value:
			if not _is_supported(item, next_ancestors):
				return false
		return true
	if value_type == TYPE_DICTIONARY:
		if _contains_same(ancestors, value):
			return false
		var next_ancestors := ancestors.duplicate()
		next_ancestors.append(value)
		for key: Variant in value:
			if not key is String and not key is StringName:
				return false
			if not _is_supported(value[key], next_ancestors):
				return false
		return true
	return false


func _contains_same(values: Array[Variant], target: Variant) -> bool:
	for value: Variant in values:
		if is_same(value, target):
			return true
	return false
