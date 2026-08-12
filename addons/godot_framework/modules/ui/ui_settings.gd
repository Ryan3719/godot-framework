@tool
class_name GFUISettings
extends Resource

@export var root_name := "FrameworkUI"
@export var layers: Array[GFUILayerDefinition] = []
@export var routes: Array[GFUIRoute] = []


func validate() -> String:
	if root_name.is_empty():
		return "UI root name cannot be empty."
	var layer_ids: Dictionary = {}
	for layer: GFUILayerDefinition in layers:
		if layer == null:
			return "UI settings contain a null layer definition."
		var validation := layer.validate()
		if not validation.is_empty():
			return validation
		if layer_ids.has(layer.layer_id):
			return "Duplicate UI layer '%s'." % layer.layer_id
		layer_ids[layer.layer_id] = true
	var route_ids: Dictionary = {}
	for route: GFUIRoute in routes:
		if route == null:
			return "UI settings contain a null route."
		var validation := route.validate()
		if not validation.is_empty():
			return validation
		if route_ids.has(route.route_id):
			return "Duplicate UI route '%s'." % route.route_id
		if not layer_ids.has(route.layer_id):
			return "UI route '%s' references missing layer '%s'." % [route.route_id, route.layer_id]
		route_ids[route.route_id] = true
	return ""
