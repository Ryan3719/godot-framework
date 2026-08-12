class_name GFTableProvider
extends RefCounted


func load_table(_table_id: StringName, _source: Variant = null) -> Error:
	return ERR_UNAVAILABLE


func has_table(_table_id: StringName) -> bool:
	return false


func get_row(_table_id: StringName, _row_id: Variant, default: Variant = null) -> Variant:
	return default


func get_all(_table_id: StringName) -> Array:
	return []


func unload_table(_table_id: StringName) -> bool:
	return false


func clear() -> void:
	pass
