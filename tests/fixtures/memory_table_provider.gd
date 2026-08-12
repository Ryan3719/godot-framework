class_name GFMemoryTestTableProvider
extends GFTableProvider

var tables: Dictionary = {}
var cleared := false


func load_table(table_id: StringName, source: Variant = null) -> Error:
	if not source is Dictionary:
		return ERR_INVALID_DATA
	var rows: Dictionary = {}
	for row_id: Variant in source:
		rows[row_id] = source[row_id]
	tables[table_id] = rows
	return OK


func has_table(table_id: StringName) -> bool:
	return tables.has(table_id)


func get_row(table_id: StringName, row_id: Variant, default: Variant = null) -> Variant:
	return (tables[table_id] as Dictionary).get(row_id, default) if tables.has(table_id) else default


func get_all(table_id: StringName) -> Array:
	return (tables[table_id] as Dictionary).values() if tables.has(table_id) else []


func unload_table(table_id: StringName) -> bool:
	return tables.erase(table_id)


func clear() -> void:
	tables.clear()
	cleared = true
