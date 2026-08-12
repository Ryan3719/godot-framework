@tool
class_name GFUIRoute
extends Resource

@export var route_id: StringName
@export var layer_id: StringName
@export var scene: PackedScene
@export var singleton := false


func validate() -> String:
	if route_id.is_empty():
		return "UI route ID cannot be empty."
	if layer_id.is_empty():
		return "UI route '%s' has no layer ID." % route_id
	if scene == null:
		return "UI route '%s' has no PackedScene." % route_id
	return ""
