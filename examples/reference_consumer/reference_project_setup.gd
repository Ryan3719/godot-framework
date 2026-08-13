extends Node

const CONFIRM_ACTION := &"reference.confirm"


func _enter_tree() -> void:
	if InputMap.has_action(CONFIRM_ACTION):
		return
	InputMap.add_action(CONFIRM_ACTION)
	var confirm_key := InputEventKey.new()
	confirm_key.physical_keycode = KEY_ENTER
	InputMap.action_add_event(CONFIRM_ACTION, confirm_key)
