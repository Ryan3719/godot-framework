class_name GFAudioService
extends RefCounted

signal group_registered(group_id: StringName)
signal playback_started(handle: int, group_id: StringName, tag: StringName)
signal playback_finished(handle: int, group_id: StringName, tag: StringName)
signal playback_stopped(handle: int, group_id: StringName, tag: StringName)
signal playback_rejected(group_id: StringName, tag: StringName)

var last_error := ""

var _host: Node
var _root: Node
var _groups: Dictionary = {}
var _playbacks: Dictionary = {}
var _next_handle := 1
var _sequence := 1
var _player_factory: Callable
var _playback_starter: Callable
var _playback_stopper: Callable


func _init(
	host: Node,
	root_name: String,
	player_factory := Callable(),
	playback_starter := Callable(),
	playback_stopper := Callable(),
) -> void:
	_host = host
	_player_factory = player_factory
	_playback_starter = playback_starter
	_playback_stopper = playback_stopper
	_root = Node.new()
	_root.name = root_name
	_host.add_child(_root)


func register_group(definition: GFAudioGroupDefinition, replace := false) -> Error:
	if definition == null:
		return _fail(ERR_INVALID_PARAMETER, "Cannot register a null audio group.")
	var validation := definition.validate()
	if not validation.is_empty():
		return _fail(ERR_INVALID_DATA, validation)
	var group_id := definition.group_id
	if _groups.has(group_id):
		if not replace:
			return _fail(ERR_ALREADY_EXISTS, "Duplicate audio group '%s'." % group_id)
		if active_count(group_id) > 0:
			return _fail(ERR_ALREADY_IN_USE, "Cannot replace active audio group '%s'." % group_id)
	_groups[group_id] = {
		"definition": definition,
		"handles": [],
		"paused": false,
		"volume_db": definition.volume_db,
	}
	group_registered.emit(group_id)
	return OK


func unregister_group(group_id: StringName, stop_active := false) -> Error:
	if not _groups.has(group_id):
		return ERR_DOES_NOT_EXIST
	if active_count(group_id) > 0 and not stop_active:
		return _fail(ERR_ALREADY_IN_USE, "Audio group '%s' still has active playbacks." % group_id)
	if stop_active:
		stop_group(group_id)
	_groups.erase(group_id)
	return OK


func play(
	stream: AudioStream,
	group_id: StringName,
	tag: StringName = &"",
	volume_db := 0.0,
	pitch_scale := 1.0,
	from_position := 0.0,
) -> int:
	if stream == null or not _groups.has(group_id) or pitch_scale <= 0.0 or from_position < 0.0:
		_fail(ERR_INVALID_PARAMETER, "Invalid audio playback request for group '%s'." % group_id)
		return 0
	var group: Dictionary = _groups[group_id]
	var definition := group.definition as GFAudioGroupDefinition
	var handles: Array = group.handles
	_cleanup_invalid(handles)
	if definition.max_voices == 0:
		playback_rejected.emit(group_id, tag)
		return 0
	if handles.size() >= definition.max_voices:
		if definition.overflow_policy == GFAudioGroupDefinition.OverflowPolicy.REJECT_NEW:
			playback_rejected.emit(group_id, tag)
			return 0
		_stop_internal(int(handles.front()), true)

	var player := _create_player()
	if player == null:
		_fail(ERR_CANT_CREATE, "Audio player factory must return an AudioStreamPlayer.")
		return 0
	player.name = "Playback%d" % _next_handle
	player.stream = stream
	player.bus = definition.bus
	player.volume_db = float(group.volume_db) + volume_db
	player.pitch_scale = pitch_scale
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(player)
	var handle := _next_handle
	_next_handle += 1
	var record := {
		"handle": handle,
		"group_id": group_id,
		"tag": tag,
		"player": player,
		"sequence": _sequence,
	}
	_sequence += 1
	_playbacks[handle] = record
	handles.append(handle)
	player.finished.connect(_on_player_finished.bind(handle), CONNECT_ONE_SHOT)
	player.stream_paused = bool(group.paused)
	_start_playback(player, from_position)
	playback_started.emit(handle, group_id, tag)
	return handle


func stop(handle: int) -> bool:
	return _stop_internal(handle, false)


func stop_group(group_id: StringName, tag: StringName = &"") -> int:
	if not _groups.has(group_id):
		return 0
	var stopped := 0
	var handles: Array = (_groups[group_id].handles as Array).duplicate()
	for handle: int in handles:
		var record: Variant = _playbacks.get(handle)
		if record == null or (not tag.is_empty() and record.tag != tag):
			continue
		if _stop_internal(handle, false):
			stopped += 1
	return stopped


func set_group_paused(group_id: StringName, paused: bool) -> Error:
	if not _groups.has(group_id):
		return ERR_DOES_NOT_EXIST
	var group: Dictionary = _groups[group_id]
	group.paused = paused
	for handle: int in group.handles:
		var player := get_player(handle)
		if player != null:
			player.stream_paused = paused
	return OK


func set_group_volume_db(group_id: StringName, volume_db: float) -> Error:
	if not _groups.has(group_id):
		return ERR_DOES_NOT_EXIST
	var group: Dictionary = _groups[group_id]
	var difference := volume_db - float(group.volume_db)
	group.volume_db = volume_db
	for handle: int in group.handles:
		var player := get_player(handle)
		if player != null:
			player.volume_db += difference
	return OK


func is_active(handle: int) -> bool:
	return _playbacks.has(handle) and get_player(handle) != null


func active_count(group_id: StringName = &"") -> int:
	if group_id.is_empty():
		return _playbacks.size()
	if not _groups.has(group_id):
		return 0
	var handles: Array = _groups[group_id].handles
	_cleanup_invalid(handles)
	return handles.size()


func get_player(handle: int) -> AudioStreamPlayer:
	var record: Variant = _playbacks.get(handle)
	if record == null:
		return null
	var player := record.player as AudioStreamPlayer
	return player if is_instance_valid(player) else null


func shutdown() -> void:
	for handle: int in _playbacks.keys():
		_stop_internal(handle, false)
	_groups.clear()
	_playbacks.clear()
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_host = null


func _stop_internal(handle: int, overflow: bool) -> bool:
	var record: Variant = _playbacks.get(handle)
	if record == null:
		return false
	_playbacks.erase(handle)
	var group_id: StringName = record.group_id
	if _groups.has(group_id):
		(_groups[group_id].handles as Array).erase(handle)
	var player := record.player as AudioStreamPlayer
	if is_instance_valid(player):
		_stop_playback(player)
		player.stream = null
		_dispose_player(player)
	playback_stopped.emit(handle, group_id, record.tag)
	if overflow:
		last_error = "Audio group '%s' stopped its oldest playback because the voice limit was reached." % group_id
	return true


func _on_player_finished(handle: int) -> void:
	var record: Variant = _playbacks.get(handle)
	if record == null:
		return
	_playbacks.erase(handle)
	var group_id: StringName = record.group_id
	if _groups.has(group_id):
		(_groups[group_id].handles as Array).erase(handle)
	var player := record.player as AudioStreamPlayer
	if is_instance_valid(player):
		_stop_playback(player)
		player.stream = null
		_dispose_player(player)
	playback_finished.emit(handle, group_id, record.tag)


func _cleanup_invalid(handles: Array) -> void:
	for handle: int in handles.duplicate():
		if get_player(handle) == null:
			handles.erase(handle)
			_playbacks.erase(handle)


func _dispose_player(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player):
		return
	player.queue_free()


func _create_player() -> AudioStreamPlayer:
	if not _player_factory.is_valid():
		return AudioStreamPlayer.new()
	var created: Variant = _player_factory.call()
	return created as AudioStreamPlayer if created is AudioStreamPlayer else null


func _start_playback(player: AudioStreamPlayer, from_position: float) -> void:
	if _playback_starter.is_valid():
		_playback_starter.call(player, from_position)
	else:
		player.play(from_position)


func _stop_playback(player: AudioStreamPlayer) -> void:
	if _playback_stopper.is_valid():
		_playback_stopper.call(player)
	else:
		player.stop()


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
