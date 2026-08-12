@tool
class_name GFInputSettings
extends Resource

@export var managed_actions: Array[StringName] = []


func validate() -> String:
	var seen: Dictionary = {}
	for action: StringName in managed_actions:
		if action.is_empty():
			return "Managed input action cannot be empty."
		if seen.has(action):
			return "Duplicate managed input action '%s'." % action
		if not InputMap.has_action(action):
			return "Managed input action '%s' does not exist in InputMap." % action
		seen[action] = true
	return ""
