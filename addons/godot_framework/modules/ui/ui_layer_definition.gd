@tool
class_name GFUILayerDefinition
extends Resource

@export var layer_id: StringName
@export var canvas_layer := 0
@export var blocks_lower_input := false


func validate() -> String:
	if layer_id.is_empty():
		return "UI layer ID cannot be empty."
	return ""
