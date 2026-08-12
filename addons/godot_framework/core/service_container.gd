class_name GFServiceContainer
extends RefCounted

var _services: Dictionary = {}


func register(service_id: StringName, service: Variant, replace := false) -> Error:
	if service_id.is_empty() or service == null:
		return ERR_INVALID_PARAMETER
	if _services.has(service_id) and not replace:
		return ERR_ALREADY_EXISTS
	_services[service_id] = service
	return OK


func unregister(service_id: StringName, expected: Variant = null) -> bool:
	if not _services.has(service_id):
		return false
	if expected != null and not is_same(_services[service_id], expected):
		return false
	_services.erase(service_id)
	return true


func has(service_id: StringName) -> bool:
	return _services.has(service_id)


func resolve(service_id: StringName, default: Variant = null) -> Variant:
	return _services.get(service_id, default)


func require(service_id: StringName) -> Variant:
	if not _services.has(service_id):
		push_error("[GF] Required service '%s' is not registered." % service_id)
		return null
	return _services[service_id]


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for service_id: StringName in _services:
		result.append(service_id)
	return result


func clear() -> void:
	_services.clear()
