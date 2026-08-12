@tool
class_name GFAudioSettings
extends Resource

@export var root_name := "FrameworkAudio"
@export var groups: Array[GFAudioGroupDefinition] = []


func validate() -> String:
	if root_name.is_empty():
		return "Audio root name cannot be empty."
	var group_ids: Dictionary = {}
	for group: GFAudioGroupDefinition in groups:
		if group == null:
			return "Audio settings contain a null group definition."
		var validation := group.validate()
		if not validation.is_empty():
			return validation
		if group.max_voices < 0:
			return "Audio group '%s' has a negative voice limit." % group.group_id
		if group_ids.has(group.group_id):
			return "Duplicate audio group '%s'." % group.group_id
		group_ids[group.group_id] = true
	return ""
