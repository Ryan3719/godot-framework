class_name GFMessageBus
extends RefCounted

signal command_sent(command_id: StringName, payload: Variant)

var _commands: Dictionary = {}
var _queries: Dictionary = {}


func register_command(command_id: StringName, handler: Callable, replace := false) -> Error:
	return _register(_commands, command_id, handler, replace)


func unregister_command(command_id: StringName, expected := Callable()) -> bool:
	return _unregister(_commands, command_id, expected)


func has_command(command_id: StringName) -> bool:
	return _commands.has(command_id)


func send(command_id: StringName, payload: Variant = null) -> Error:
	var handler: Callable = _commands.get(command_id, Callable())
	if not handler.is_valid():
		return ERR_DOES_NOT_EXIST
	handler.call(payload)
	command_sent.emit(command_id, payload)
	return OK


func register_query(query_id: StringName, handler: Callable, replace := false) -> Error:
	return _register(_queries, query_id, handler, replace)


func unregister_query(query_id: StringName, expected := Callable()) -> bool:
	return _unregister(_queries, query_id, expected)


func has_query(query_id: StringName) -> bool:
	return _queries.has(query_id)


func ask(query_id: StringName, payload: Variant = null, default: Variant = null) -> Variant:
	var handler: Callable = _queries.get(query_id, Callable())
	if not handler.is_valid():
		return default
	return handler.call(payload)


func clear() -> void:
	_commands.clear()
	_queries.clear()


func _register(collection: Dictionary, message_id: StringName, handler: Callable, replace: bool) -> Error:
	if message_id.is_empty() or not handler.is_valid():
		return ERR_INVALID_PARAMETER
	if collection.has(message_id) and not replace:
		return ERR_ALREADY_EXISTS
	collection[message_id] = handler
	return OK


func _unregister(collection: Dictionary, message_id: StringName, expected: Callable) -> bool:
	if not collection.has(message_id):
		return false
	if expected.is_valid() and collection[message_id] != expected:
		return false
	collection.erase(message_id)
	return true
