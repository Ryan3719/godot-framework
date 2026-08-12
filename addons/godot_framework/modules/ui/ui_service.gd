class_name GFUIService
extends RefCounted

signal layer_registered(layer_id: StringName)
signal route_registered(route_id: StringName)
signal view_opened(route_id: StringName, view: GFUIView)
signal view_suspended(route_id: StringName, view: GFUIView)
signal view_resumed(route_id: StringName, view: GFUIView)
signal view_closed(route_id: StringName, view: GFUIView, result: Variant)

enum OpenMode {
	PUSH,
	REPLACE_TOP,
}

var last_error := ""

var _host: Node
var _root: Node
var _layers: Dictionary = {}
var _routes: Dictionary = {}
var _stacks: Dictionary = {}
var _views_by_route: Dictionary = {}


func _init(host: Node, root_name: String) -> void:
	_host = host
	_root = Node.new()
	_root.name = root_name
	_host.add_child(_root)


func register_layer(definition: GFUILayerDefinition, replace := false) -> Error:
	if definition == null:
		return _fail(ERR_INVALID_PARAMETER, "Cannot register a null UI layer definition.")
	var validation := definition.validate()
	if not validation.is_empty():
		return _fail(ERR_INVALID_DATA, validation)
	var layer_id := definition.layer_id
	if _layers.has(layer_id):
		if not replace:
			return _fail(ERR_ALREADY_EXISTS, "Duplicate UI layer '%s'." % layer_id)
		if not (_stacks[layer_id] as Array).is_empty():
			return _fail(ERR_ALREADY_IN_USE, "Cannot replace non-empty UI layer '%s'." % layer_id)
		_remove_layer(layer_id)

	var canvas := CanvasLayer.new()
	canvas.name = str(layer_id).to_pascal_case()
	canvas.layer = definition.canvas_layer
	var container := Control.new()
	container.name = "Views"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP if definition.blocks_lower_input else Control.MOUSE_FILTER_IGNORE
	canvas.add_child(container)
	_root.add_child(canvas)
	_layers[layer_id] = {
		"definition": definition,
		"canvas": canvas,
		"container": container,
	}
	_stacks[layer_id] = []
	layer_registered.emit(layer_id)
	return OK


func unregister_layer(layer_id: StringName) -> Error:
	if not _layers.has(layer_id):
		return ERR_DOES_NOT_EXIST
	if not (_stacks[layer_id] as Array).is_empty():
		return _fail(ERR_ALREADY_IN_USE, "Cannot remove non-empty UI layer '%s'." % layer_id)
	for route: GFUIRoute in _routes.values():
		if route.layer_id == layer_id:
			return _fail(ERR_ALREADY_IN_USE, "Cannot remove UI layer '%s' while routes reference it." % layer_id)
	_remove_layer(layer_id)
	return OK


func register_route(route: GFUIRoute, replace := false) -> Error:
	if route == null:
		return _fail(ERR_INVALID_PARAMETER, "Cannot register a null UI route.")
	var validation := route.validate()
	if not validation.is_empty():
		return _fail(ERR_INVALID_DATA, validation)
	if not _layers.has(route.layer_id):
		return _fail(ERR_DOES_NOT_EXIST, "UI route '%s' references missing layer '%s'." % [route.route_id, route.layer_id])
	if _routes.has(route.route_id) and not replace:
		return _fail(ERR_ALREADY_EXISTS, "Duplicate UI route '%s'." % route.route_id)
	if replace and has_open_route(route.route_id):
		return _fail(ERR_ALREADY_IN_USE, "Cannot replace open UI route '%s'." % route.route_id)
	_routes[route.route_id] = route
	route_registered.emit(route.route_id)
	return OK


func unregister_route(route_id: StringName) -> Error:
	if not _routes.has(route_id):
		return ERR_DOES_NOT_EXIST
	if has_open_route(route_id):
		return _fail(ERR_ALREADY_IN_USE, "Cannot remove open UI route '%s'." % route_id)
	_routes.erase(route_id)
	return OK


func open(route_id: StringName, payload: Variant = null, mode := OpenMode.PUSH) -> GFUIView:
	var route := _routes.get(route_id) as GFUIRoute
	if route == null:
		_fail(ERR_DOES_NOT_EXIST, "Unknown UI route '%s'." % route_id)
		return null
	if mode not in [OpenMode.PUSH, OpenMode.REPLACE_TOP]:
		_fail(ERR_INVALID_PARAMETER, "Unsupported UI open mode %d." % mode)
		return null
	if route.singleton and has_open_route(route_id):
		var existing: Array = _views_by_route[route_id]
		var singleton_view := existing.back() as GFUIView
		_focus_view(singleton_view, payload, mode)
		return singleton_view

	var instance := route.scene.instantiate()
	if not instance is GFUIView:
		if instance != null:
			instance.free()
		_fail(ERR_CANT_CREATE, "UI route '%s' root must extend GFUIView." % route_id)
		return null
	var view := instance as GFUIView
	var stack: Array = _stacks[route.layer_id]
	if mode == OpenMode.REPLACE_TOP and not stack.is_empty():
		_close_view(stack.back() as GFUIView, null, false)
	if not stack.is_empty():
		var current := stack.back() as GFUIView
		current._framework_suspend()
		view_suspended.emit(current.route_id, current)

	var layer: Dictionary = _layers[route.layer_id]
	(layer.container as Control).add_child(view)
	stack.append(view)
	if not _views_by_route.has(route_id):
		_views_by_route[route_id] = []
	(_views_by_route[route_id] as Array).append(view)
	view.close_requested.connect(_on_view_close_requested.bind(view))
	view._framework_open(self, route_id, payload)
	view_opened.emit(route_id, view)
	return view


func close(view: GFUIView, result: Variant = null) -> Error:
	if view == null or not is_instance_valid(view):
		return ERR_INVALID_PARAMETER
	var route := _routes.get(view.route_id) as GFUIRoute
	if route == null or not _stacks.has(route.layer_id):
		return ERR_DOES_NOT_EXIST
	if not (_stacks[route.layer_id] as Array).has(view):
		return ERR_DOES_NOT_EXIST
	_close_view(view, result, true)
	return OK


func pop(layer_id: StringName, result: Variant = null) -> Error:
	if not _stacks.has(layer_id):
		return ERR_DOES_NOT_EXIST
	var stack: Array = _stacks[layer_id]
	if stack.is_empty():
		return ERR_DOES_NOT_EXIST
	_close_view(stack.back() as GFUIView, result, true)
	return OK


func close_all(result: Variant = null) -> void:
	for layer_id: StringName in _stacks.keys():
		var stack: Array = _stacks[layer_id]
		while not stack.is_empty():
			_close_view(stack.back() as GFUIView, result, false)


func top(layer_id: StringName) -> GFUIView:
	if not _stacks.has(layer_id):
		return null
	var stack: Array = _stacks[layer_id]
	return stack.back() as GFUIView if not stack.is_empty() else null


func stack_size(layer_id: StringName) -> int:
	return (_stacks.get(layer_id, []) as Array).size()


func has_open_route(route_id: StringName) -> bool:
	if not _views_by_route.has(route_id):
		return false
	for view: GFUIView in (_views_by_route[route_id] as Array).duplicate():
		if is_instance_valid(view) and view.lifecycle != GFUIView.Lifecycle.CLOSED:
			return true
	return false


func shutdown() -> void:
	close_all()
	_routes.clear()
	_views_by_route.clear()
	_stacks.clear()
	_layers.clear()
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_host = null


func _close_view(view: GFUIView, result: Variant, resume_previous: bool) -> void:
	var route := _routes.get(view.route_id) as GFUIRoute
	if route == null:
		return
	var stack: Array = _stacks[route.layer_id]
	var was_top: bool = not stack.is_empty() and stack.back() == view
	stack.erase(view)
	if view.close_requested.is_connected(_on_view_close_requested.bind(view)):
		view.close_requested.disconnect(_on_view_close_requested.bind(view))
	view._framework_close(result)
	if _views_by_route.has(view.route_id):
		var route_views: Array = _views_by_route[view.route_id]
		route_views.erase(view)
		if route_views.is_empty():
			_views_by_route.erase(view.route_id)
	view_closed.emit(view.route_id, view, result)
	view.queue_free()
	if resume_previous and was_top:
		_resume_top(route.layer_id, result)


func _resume_top(layer_id: StringName, payload: Variant) -> void:
	var view := top(layer_id)
	if view == null:
		return
	view._framework_resume(payload)
	view_resumed.emit(view.route_id, view)


func _focus_view(view: GFUIView, payload: Variant, mode: int) -> void:
	var route := _routes.get(view.route_id) as GFUIRoute
	if route == null:
		return
	var stack: Array = _stacks[route.layer_id]
	if stack.is_empty() or stack.back() == view:
		return
	if mode == OpenMode.REPLACE_TOP:
		_close_view(stack.back() as GFUIView, null, false)
	if not stack.is_empty() and stack.back() != view:
		var current := stack.back() as GFUIView
		current._framework_suspend()
		view_suspended.emit(current.route_id, current)
	stack.erase(view)
	stack.append(view)
	view._framework_resume(payload)
	view_resumed.emit(view.route_id, view)


func _on_view_close_requested(result: Variant, view: GFUIView) -> void:
	close(view, result)


func _remove_layer(layer_id: StringName) -> void:
	var layer: Dictionary = _layers[layer_id]
	var canvas := layer.canvas as CanvasLayer
	if is_instance_valid(canvas):
		canvas.queue_free()
	_layers.erase(layer_id)
	_stacks.erase(layer_id)


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
