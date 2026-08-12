@tool
class_name GFAudioGroupDefinition
extends Resource

enum OverflowPolicy {
	REJECT_NEW,
	STOP_OLDEST,
}

@export var group_id: StringName
@export var bus: StringName = &"Master"
@export_range(0, 256, 1) var max_voices := 8
@export var overflow_policy := OverflowPolicy.STOP_OLDEST
@export_range(-80.0, 24.0, 0.1) var volume_db := 0.0


func validate() -> String:
	if group_id.is_empty():
		return "Audio group ID cannot be empty."
	if bus.is_empty():
		return "Audio group '%s' has no bus." % group_id
	if AudioServer.get_bus_index(bus) < 0:
		return "Audio group '%s' references missing bus '%s'." % [group_id, bus]
	return ""
