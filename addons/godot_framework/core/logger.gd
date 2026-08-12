class_name GFLogger
extends RefCounted

signal record_written(record: Dictionary)

enum Level {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
	NONE,
}

var minimum_level: Level = Level.INFO


func debug(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write(Level.DEBUG, category, message, fields)


func info(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write(Level.INFO, category, message, fields)


func warning(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write(Level.WARNING, category, message, fields)


func error(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write(Level.ERROR, category, message, fields)


func _write(level: Level, category: StringName, message: String, fields: Dictionary) -> void:
	if level < minimum_level or minimum_level == Level.NONE:
		return
	var record := {
		"timestamp": Time.get_datetime_string_from_system(true),
		"level": Level.keys()[level],
		"category": str(category),
		"message": message,
		"fields": fields.duplicate(true),
	}
	record_written.emit(record)
	var rendered := "[GF][%s][%s] %s" % [record.level, record.category, message]
	if not fields.is_empty():
		rendered += " %s" % JSON.stringify(fields)
	match level:
		Level.ERROR:
			push_error(rendered)
		Level.WARNING:
			push_warning(rendered)
		_:
			print(rendered)
