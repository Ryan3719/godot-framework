class_name GFTableService
extends RefCounted

signal provider_registered(provider_id: StringName)
signal provider_removed(provider_id: StringName)

var last_error := ""
var _providers: Dictionary = {}


func register_provider(provider_id: StringName, provider: GFTableProvider, replace := false) -> Error:
	if provider_id.is_empty() or provider == null:
		return _fail(ERR_INVALID_PARAMETER, "Table provider ID and instance are required.")
	if _providers.has(provider_id) and not replace:
		return _fail(ERR_ALREADY_EXISTS, "Duplicate table provider '%s'." % provider_id)
	if replace:
		var existing := _providers.get(provider_id) as GFTableProvider
		if existing != null:
			existing.clear()
	_providers[provider_id] = provider
	provider_registered.emit(provider_id)
	return OK


func unregister_provider(provider_id: StringName, expected: GFTableProvider = null) -> bool:
	var provider := _providers.get(provider_id) as GFTableProvider
	if provider == null or (expected != null and not is_same(provider, expected)):
		return false
	_providers.erase(provider_id)
	provider.clear()
	provider_removed.emit(provider_id)
	return true


func provider(provider_id: StringName) -> GFTableProvider:
	return _providers.get(provider_id) as GFTableProvider


func load_table(provider_id: StringName, table_id: StringName, source: Variant = null) -> Error:
	var target := provider(provider_id)
	if target == null:
		return _fail(ERR_DOES_NOT_EXIST, "Unknown table provider '%s'." % provider_id)
	if table_id.is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Table ID cannot be empty.")
	return target.load_table(table_id, source)


func get_row(
	provider_id: StringName,
	table_id: StringName,
	row_id: Variant,
	default: Variant = null,
) -> Variant:
	var target := provider(provider_id)
	return target.get_row(table_id, row_id, default) if target != null else default


func get_all(provider_id: StringName, table_id: StringName) -> Array:
	var target := provider(provider_id)
	return target.get_all(table_id) if target != null else []


func has_table(provider_id: StringName, table_id: StringName) -> bool:
	var target := provider(provider_id)
	return target != null and target.has_table(table_id)


func unload_table(provider_id: StringName, table_id: StringName) -> bool:
	var target := provider(provider_id)
	return target != null and target.unload_table(table_id)


func shutdown() -> void:
	for provider_id: StringName in _providers.keys():
		unregister_provider(provider_id)


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
