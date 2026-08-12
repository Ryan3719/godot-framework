class_name GFStateMachine
extends RefCounted

signal transition_started(from: StringName, to: StringName)
signal state_changed(previous: StringName, current: StringName)
signal transition_rejected(from: StringName, to: StringName)

var _states: Dictionary = {}
var _current: GFState
var _transitioning := false


func add_state(state: GFState, replace := false) -> Error:
	if state == null or state.state_id().is_empty():
		return ERR_INVALID_PARAMETER
	var id := state.state_id()
	if _states.has(id) and not replace:
		return ERR_ALREADY_EXISTS
	if replace and _current == _states.get(id):
		return ERR_ALREADY_IN_USE
	var previous: GFState = _states.get(id) as GFState
	if previous != null:
		previous._bind_machine(null)
	_states[id] = state
	state._bind_machine(self)
	return OK


func remove_state(state_id: StringName) -> bool:
	if not _states.has(state_id) or current_id() == state_id:
		return false
	var state: GFState = _states[state_id]
	state._bind_machine(null)
	_states.erase(state_id)
	return true


func has_state(state_id: StringName) -> bool:
	return _states.has(state_id)


func get_state(state_id: StringName) -> GFState:
	return _states.get(state_id) as GFState


func current_state() -> GFState:
	return _current


func current_id() -> StringName:
	return _current.state_id() if _current != null else &""


func change(state_id: StringName, payload: Variant = null, force := false) -> Error:
	if _transitioning:
		return ERR_BUSY
	var next: GFState = get_state(state_id)
	if next == null:
		return ERR_DOES_NOT_EXIST
	if next == _current and not force:
		return ERR_ALREADY_IN_USE

	var previous := _current
	var previous_id := current_id()
	if not force:
		if previous != null and not previous.can_exit(state_id, payload):
			transition_rejected.emit(previous_id, state_id)
			return ERR_UNAUTHORIZED
		if not next.can_enter(previous_id, payload):
			transition_rejected.emit(previous_id, state_id)
			return ERR_UNAUTHORIZED

	_transitioning = true
	transition_started.emit(previous_id, state_id)
	if previous != null:
		previous.exit(state_id, payload)
	_current = next
	next.enter(previous_id, payload)
	_transitioning = false
	state_changed.emit(previous_id, state_id)
	return OK


func clear(payload: Variant = null) -> void:
	if _current != null:
		var previous_id := current_id()
		_current.exit(&"", payload)
		_current = null
		state_changed.emit(previous_id, &"")
	for state: GFState in _states.values():
		state._bind_machine(null)
	_states.clear()


func update(delta: float) -> void:
	if _current != null and not _transitioning:
		_current.update(delta)


func physics_update(delta: float) -> void:
	if _current != null and not _transitioning:
		_current.physics_update(delta)
