class_name GFSceneService
extends RefCounted

signal transition_started(from_path: String, to_path: String)
signal transition_completed(from_path: String, to_path: String, scene: Node)
signal transition_failed(path: String, error: Error)

var _tree: SceneTree
var _resources: GFResourceService
var _transitioning := false


func _init(tree: SceneTree, resources: GFResourceService = null) -> void:
	_tree = tree
	_resources = resources


func change_to_file(path: String) -> Error:
	if _transitioning:
		return ERR_BUSY
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		transition_failed.emit(path, ERR_FILE_NOT_FOUND)
		return ERR_FILE_NOT_FOUND
	var packed := _resources.load(path, "PackedScene") if _resources != null else load(path)
	if not packed is PackedScene:
		transition_failed.emit(path, ERR_FILE_CORRUPT)
		return ERR_FILE_CORRUPT
	return change_to_packed(packed as PackedScene)


func change_to_packed(scene: PackedScene) -> Error:
	if _transitioning:
		return ERR_BUSY
	if scene == null or _tree == null:
		return ERR_INVALID_PARAMETER
	_transitioning = true
	var previous_path := current_scene_path()
	var next_path := scene.resource_path
	transition_started.emit(previous_path, next_path)
	var result := _tree.change_scene_to_packed(scene)
	if result != OK:
		_transitioning = false
		transition_failed.emit(next_path, result)
		return result
	_tree.process_frame.connect(
		func() -> void:
			_transitioning = false
			transition_completed.emit(previous_path, next_path, _tree.current_scene),
		CONNECT_ONE_SHOT,
	)
	return OK


func reload_current() -> Error:
	if _tree == null or _tree.current_scene == null:
		return ERR_DOES_NOT_EXIST
	return _tree.reload_current_scene()


func current_scene() -> Node:
	return _tree.current_scene if _tree != null else null


func current_scene_path() -> String:
	var scene := current_scene()
	return scene.scene_file_path if scene != null else ""


func is_transitioning() -> bool:
	return _transitioning
