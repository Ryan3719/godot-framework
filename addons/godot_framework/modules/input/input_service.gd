class_name GFInputService
extends RefCounted

signal action_rebound(action: StringName, events: Array[InputEvent])
signal profile_applied(profile: Dictionary)
signal defaults_restored

var last_error := ""

var _managed_actions: Array[StringName] = []
var _defaults: Dictionary = {}


func _init(managed_actions: Array[StringName]) -> void:
	for action: StringName in managed_actions:
		if action.is_empty() or _managed_actions.has(action):
			continue
		_managed_actions.append(action)
	_capture_defaults()


func managed_actions() -> Array[StringName]:
	return _managed_actions.duplicate()


func has_action(action: StringName) -> bool:
	return _managed_actions.has(action) and InputMap.has_action(action)


func events_for(action: StringName) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	if not has_action(action):
		return result
	for event: InputEvent in InputMap.action_get_events(action):
		result.append(event.duplicate(true) as InputEvent)
	return result


func rebind(action: StringName, events: Array[InputEvent]) -> Error:
	if not has_action(action):
		return _fail(ERR_DOES_NOT_EXIST, "Input action '%s' is not managed." % action)
	for event: InputEvent in events:
		if event == null:
			return _fail(ERR_INVALID_PARAMETER, "Input action '%s' contains a null event." % action)
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event.duplicate(true))
	action_rebound.emit(action, events_for(action))
	return OK


func add_binding(action: StringName, event: InputEvent, allow_duplicate := false) -> Error:
	if not has_action(action) or event == null:
		return _fail(ERR_INVALID_PARAMETER, "Invalid input binding request for '%s'." % action)
	if not allow_duplicate and has_equivalent_binding(action, event):
		return ERR_ALREADY_EXISTS
	InputMap.action_add_event(action, event.duplicate(true))
	action_rebound.emit(action, events_for(action))
	return OK


func remove_binding(action: StringName, event: InputEvent) -> Error:
	if not has_action(action) or event == null:
		return ERR_INVALID_PARAMETER
	var match := _find_equivalent(action, event)
	if match == null:
		return ERR_DOES_NOT_EXIST
	InputMap.action_erase_event(action, match)
	action_rebound.emit(action, events_for(action))
	return OK


func has_equivalent_binding(action: StringName, event: InputEvent) -> bool:
	return _find_equivalent(action, event) != null


func find_conflicts(event: InputEvent, except_action: StringName = &"") -> Array[StringName]:
	var conflicts: Array[StringName] = []
	if event == null:
		return conflicts
	for action: StringName in _managed_actions:
		if action == except_action or not InputMap.has_action(action):
			continue
		if _find_equivalent(action, event) != null:
			conflicts.append(action)
	return conflicts


func capture_profile() -> Dictionary:
	var profile := {"version": 1, "actions": {}}
	var actions: Dictionary = profile.actions
	for action: StringName in _managed_actions:
		if not InputMap.has_action(action):
			continue
		var encoded: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var value := _encode_event(event)
			if not value.is_empty():
				encoded.append(value)
		actions[str(action)] = encoded
	return profile


func apply_profile(profile: Dictionary) -> Error:
	if int(profile.get("version", 0)) != 1 or not profile.get("actions") is Dictionary:
		return _fail(ERR_INVALID_DATA, "Unsupported input profile format.")
	var actions := profile.actions as Dictionary
	var decoded: Dictionary = {}
	for action_key: Variant in actions:
		var action := StringName(str(action_key))
		if not _managed_actions.has(action) or not actions[action_key] is Array:
			continue
		var events: Array[InputEvent] = []
		for encoded: Variant in actions[action_key]:
			if not encoded is Dictionary:
				return _fail(ERR_INVALID_DATA, "Input profile action '%s' contains invalid event data." % action)
			var event := _decode_event(encoded)
			if event == null:
				return _fail(ERR_INVALID_DATA, "Input profile action '%s' uses an unsupported event." % action)
			events.append(event)
		decoded[action] = events
	for action: StringName in decoded:
		var result := rebind(action, decoded[action])
		if result != OK:
			return result
	profile_applied.emit(capture_profile())
	return OK


func restore_defaults(action: StringName = &"") -> Error:
	if not action.is_empty():
		if not _defaults.has(action):
			return ERR_DOES_NOT_EXIST
		var result := rebind(action, _duplicate_events(_defaults[action]))
		if result == OK:
			defaults_restored.emit()
		return result
	for managed_action: StringName in _managed_actions:
		if _defaults.has(managed_action) and InputMap.has_action(managed_action):
			rebind(managed_action, _duplicate_events(_defaults[managed_action]))
	defaults_restored.emit()
	return OK


func _capture_defaults() -> void:
	_defaults.clear()
	for action: StringName in _managed_actions:
		if InputMap.has_action(action):
			_defaults[action] = events_for(action)


func _find_equivalent(action: StringName, target: InputEvent) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for existing: InputEvent in InputMap.action_get_events(action):
		if _events_equivalent(existing, target):
			return existing
	return null


func _events_equivalent(left: InputEvent, right: InputEvent) -> bool:
	if left == null or right == null or left.get_class() != right.get_class():
		return false
	if left is InputEventKey:
		var left_key := left as InputEventKey
		var right_key := right as InputEventKey
		return (
			left_key.physical_keycode == right_key.physical_keycode
			and left_key.keycode == right_key.keycode
			and left_key.shift_pressed == right_key.shift_pressed
			and left_key.alt_pressed == right_key.alt_pressed
			and left_key.ctrl_pressed == right_key.ctrl_pressed
			and left_key.meta_pressed == right_key.meta_pressed
		)
	if left is InputEventMouseButton:
		var left_mouse := left as InputEventMouseButton
		var right_mouse := right as InputEventMouseButton
		return left_mouse.button_index == right_mouse.button_index
	if left is InputEventJoypadButton:
		var left_button := left as InputEventJoypadButton
		var right_button := right as InputEventJoypadButton
		return left_button.button_index == right_button.button_index
	if left is InputEventJoypadMotion:
		var left_motion := left as InputEventJoypadMotion
		var right_motion := right as InputEventJoypadMotion
		return left_motion.axis == right_motion.axis and signf(left_motion.axis_value) == signf(right_motion.axis_value)
	return left.as_text() == right.as_text()


func _encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"keycode": key.keycode,
			"physical_keycode": key.physical_keycode,
			"shift": key.shift_pressed,
			"alt": key.alt_pressed,
			"ctrl": key.ctrl_pressed,
			"meta": key.meta_pressed,
		}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"type": "joypad_button", "button": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joypad_motion", "axis": motion.axis, "axis_value": signf(motion.axis_value)}
	return {}


func _decode_event(encoded: Dictionary) -> InputEvent:
	match str(encoded.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.keycode = int(encoded.get("keycode", 0)) as Key
			key.physical_keycode = int(encoded.get("physical_keycode", 0)) as Key
			key.shift_pressed = bool(encoded.get("shift", false))
			key.alt_pressed = bool(encoded.get("alt", false))
			key.ctrl_pressed = bool(encoded.get("ctrl", false))
			key.meta_pressed = bool(encoded.get("meta", false))
			return key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(encoded.get("button", 0)) as MouseButton
			return mouse
		"joypad_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(encoded.get("button", -1)) as JoyButton
			return button
		"joypad_motion":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(encoded.get("axis", -1)) as JoyAxis
			motion.axis_value = float(encoded.get("axis_value", 0.0))
			return motion
		_:
			return null


func _duplicate_events(source: Array) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event: InputEvent in source:
		result.append(event.duplicate(true) as InputEvent)
	return result


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
