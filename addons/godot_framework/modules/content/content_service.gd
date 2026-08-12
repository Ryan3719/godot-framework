class_name GFContentService
extends RefCounted

signal release_installed(release_id: String)
signal release_activated(release_id: String, previous_release_id: String)
signal rollback_scheduled(release_id: String)
signal mount_started(release_id: String)
signal pack_mounted(release_id: String, pack_id: StringName, path: String)
signal mount_failed(release_id: String, pack_id: StringName, error: Error)

const RECORD_FORMAT := 1
const STATE_FORMAT := 1

var last_error := ""
var mounted_release := ""
var restart_required := false

var _settings: GFContentSettings
var _mount_callable: Callable
var _public_key: CryptoKey
var _initialization_error: Error = OK
var _mount_locked := false


func _init(settings: GFContentSettings, mount_callable := Callable()) -> void:
	_settings = settings
	_mount_callable = mount_callable
	if settings.require_signature:
		_public_key = CryptoKey.new()
		_initialization_error = _public_key.load_from_string(settings.public_key_pem, true)
		if _initialization_error != OK:
			last_error = "Content public key could not be loaded."


func initialization_error() -> Error:
	return _initialization_error


func install_release(manifest_text: String, signature := PackedByteArray()) -> Error:
	last_error = ""
	if manifest_text.to_utf8_buffer().size() > _settings.max_manifest_bytes:
		return _fail(ERR_OUT_OF_MEMORY, "Content manifest exceeds the configured size limit.")
	var signature_result := _verify_signature(manifest_text, signature)
	if signature_result != OK:
		return signature_result
	var manifest := GFContentManifest.new()
	var parse_result := manifest.parse(manifest_text)
	if parse_result != OK:
		return _fail(parse_result, manifest.last_error)
	var files_result := _validate_pack_files(manifest)
	if files_result != OK:
		return files_result
	var record := {
		"format": RECORD_FORMAT,
		"manifest": manifest_text,
		"signature": Marshalls.raw_to_base64(signature),
	}
	var write_result := _write_atomic(_record_path(manifest.release_id), JSON.stringify(record))
	if write_result != OK:
		return _fail(write_result, "Content release record could not be written.")
	release_installed.emit(manifest.release_id)
	return OK


func validate_release(release_id: String) -> Error:
	return OK if _load_installed_manifest(release_id) != null else ERR_INVALID_DATA


func activate_release(release_id: String) -> Error:
	last_error = ""
	if _load_installed_manifest(release_id) == null:
		return ERR_INVALID_DATA
	var state_result := _load_activation_state()
	if not bool(state_result.valid):
		return ERR_INVALID_DATA
	var state := state_result.state as Dictionary
	var previous := str(state.active)
	if previous == release_id:
		return OK
	var next_state := {
		"format": STATE_FORMAT,
		"active": release_id,
		"previous": previous,
	}
	var write_result := _write_state(next_state)
	if write_result != OK:
		return _fail(write_result, "Content activation state could not be written.")
	if not mounted_release.is_empty() and mounted_release != release_id:
		restart_required = true
	release_activated.emit(release_id, previous)
	return OK


func rollback() -> Error:
	last_error = ""
	var state_result := _load_activation_state()
	if not bool(state_result.valid):
		return ERR_INVALID_DATA
	var state := state_result.state as Dictionary
	var previous := str(state.previous)
	if previous.is_empty():
		return _fail(ERR_DOES_NOT_EXIST, "No previous content release is available.")
	if _load_installed_manifest(previous) == null:
		return ERR_INVALID_DATA
	var next_state := {
		"format": STATE_FORMAT,
		"active": previous,
		"previous": str(state.active),
	}
	var write_result := _write_state(next_state)
	if write_result != OK:
		return _fail(write_result, "Content rollback state could not be written.")
	restart_required = not mounted_release.is_empty() and mounted_release != previous
	rollback_scheduled.emit(previous)
	return OK


func mount_active() -> Error:
	last_error = ""
	restart_required = false
	if _mount_locked or not mounted_release.is_empty():
		return _fail(ERR_ALREADY_IN_USE, "A content release is already mounted in this process.")
	var state_result := _load_activation_state()
	if not bool(state_result.valid):
		return ERR_INVALID_DATA
	var state := state_result.state as Dictionary
	var release_id := str(state.active)
	if release_id.is_empty():
		return OK
	var manifest := _load_installed_manifest(release_id)
	if manifest == null:
		_schedule_failed_activation_rollback(state)
		return ERR_INVALID_DATA
	mount_started.emit(release_id)
	for pack: GFContentPackDefinition in manifest.packs:
		var pack_path := _release_directory(release_id).path_join(pack.relative_path)
		if not _mount_pack(pack_path, pack.replace_files, pack.offset):
			_fail(ERR_CANT_OPEN, "Content pack '%s' could not be mounted." % pack.pack_id)
			mount_failed.emit(release_id, pack.pack_id, ERR_CANT_OPEN)
			_schedule_failed_activation_rollback(state)
			return ERR_CANT_OPEN
		_mount_locked = true
		pack_mounted.emit(release_id, pack.pack_id, pack_path)
	mounted_release = release_id
	return OK


func activation_state() -> Dictionary:
	return (_load_activation_state().state as Dictionary).duplicate(true)


func release_directory(release_id: String) -> String:
	return _release_directory(release_id) if _is_identifier(release_id) else ""


func pack_path(release_id: String, relative_path: String) -> String:
	if not _is_identifier(release_id):
		return ""
	var pack := GFContentPackDefinition.new()
	pack.pack_id = &"path_check"
	pack.relative_path = relative_path
	pack.sha256 = "0".repeat(64)
	pack.size = 0
	return _release_directory(release_id).path_join(relative_path) if pack.validate().is_empty() else ""


func shutdown() -> void:
	_mount_callable = Callable()
	_public_key = null
	_settings = null


func _load_activation_state() -> Dictionary:
	var default_state := {"format": STATE_FORMAT, "active": "", "previous": ""}
	var path := _state_path()
	var has_primary := FileAccess.file_exists(path)
	var has_backup := FileAccess.file_exists("%s.bak" % path)
	if not has_primary and not has_backup:
		return {"valid": true, "state": default_state}
	var state := _read_json_dictionary(path)
	if state.is_empty() and has_backup:
		state = _read_json_dictionary("%s.bak" % path)
	if int(state.get("format", 0)) != STATE_FORMAT:
		_fail(ERR_INVALID_DATA, "Content activation state is invalid.")
		return {"valid": false, "state": default_state}
	var active := str(state.get("active", ""))
	var previous := str(state.get("previous", ""))
	if not active.is_empty() and not _is_identifier(active):
		_fail(ERR_INVALID_DATA, "Content activation state has an unsafe active release ID.")
		return {"valid": false, "state": default_state}
	if not previous.is_empty() and not _is_identifier(previous):
		_fail(ERR_INVALID_DATA, "Content activation state has an unsafe previous release ID.")
		return {"valid": false, "state": default_state}
	return {
		"valid": true,
		"state": {"format": STATE_FORMAT, "active": active, "previous": previous},
	}


func _load_installed_manifest(release_id: String) -> GFContentManifest:
	if not _is_identifier(release_id):
		_fail(ERR_INVALID_PARAMETER, "Content release ID is unsafe.")
		return null
	var record := _read_json_dictionary(_record_path(release_id))
	if int(record.get("format", 0)) != RECORD_FORMAT or not record.get("manifest") is String or not record.get("signature") is String:
		_fail(ERR_INVALID_DATA, "Content release '%s' has an invalid installation record." % release_id)
		return null
	var manifest_text := str(record.manifest)
	var signature := Marshalls.base64_to_raw(str(record.signature))
	if _verify_signature(manifest_text, signature) != OK:
		return null
	var manifest := GFContentManifest.new()
	if manifest.parse(manifest_text) != OK or manifest.release_id != release_id:
		_fail(ERR_INVALID_DATA, "Content release '%s' manifest is invalid." % release_id)
		return null
	if _validate_pack_files(manifest) != OK:
		return null
	return manifest


func _verify_signature(manifest_text: String, signature: PackedByteArray) -> Error:
	if not _settings.require_signature:
		return OK
	if _initialization_error != OK or _public_key == null or signature.is_empty():
		return _fail(ERR_UNAUTHORIZED, "Content manifest signature cannot be verified.")
	var verified := Crypto.new().verify(
		HashingContext.HASH_SHA256,
		manifest_text.sha256_buffer(),
		signature,
		_public_key,
	)
	return OK if verified else _fail(ERR_UNAUTHORIZED, "Content manifest signature is invalid.")


func _validate_pack_files(manifest: GFContentManifest) -> Error:
	var directory := _release_directory(manifest.release_id)
	for pack: GFContentPackDefinition in manifest.packs:
		var path := directory.path_join(pack.relative_path)
		if not FileAccess.file_exists(path):
			return _fail(ERR_FILE_NOT_FOUND, "Content pack '%s' does not exist." % pack.pack_id)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _fail(FileAccess.get_open_error(), "Content pack '%s' cannot be opened." % pack.pack_id)
		var actual_size := file.get_length()
		file = null
		if actual_size != pack.size:
			return _fail(ERR_FILE_CORRUPT, "Content pack '%s' size does not match its manifest." % pack.pack_id)
		if FileAccess.get_sha256(path).to_lower() != pack.sha256:
			return _fail(ERR_FILE_CORRUPT, "Content pack '%s' hash does not match its manifest." % pack.pack_id)
	return OK


func _schedule_failed_activation_rollback(state: Dictionary) -> void:
	var failed_release := str(state.active)
	var previous := str(state.previous)
	var write_result := _write_state({"format": STATE_FORMAT, "active": previous, "previous": failed_release})
	restart_required = true
	if write_result == OK:
		rollback_scheduled.emit(previous)
	else:
		_fail(write_result, "Content mount failed and activation rollback could not be persisted.")


func _mount_pack(path: String, replace_files: bool, offset: int) -> bool:
	if _mount_callable.is_valid():
		return bool(_mount_callable.call(path, replace_files, offset))
	return ProjectSettings.load_resource_pack(path, replace_files, offset)


func _write_state(state: Dictionary) -> Error:
	return _write_atomic(_state_path(), JSON.stringify(state))


func _write_atomic(path: String, text: String) -> Error:
	var directory_result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_result != OK:
		return directory_result
	var temp_path := "%s.tmp" % path
	var backup_path := "%s.bak" % path
	_remove_file(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file = null
	_remove_file(backup_path)
	var had_target := FileAccess.file_exists(path)
	if had_target:
		var backup_result := DirAccess.rename_absolute(path, backup_path)
		if backup_result != OK:
			_remove_file(temp_path)
			return backup_result
	var replace_result := DirAccess.rename_absolute(temp_path, path)
	if replace_result != OK:
		if had_target:
			DirAccess.rename_absolute(backup_path, path)
		return replace_result
	_remove_file(backup_path)
	return OK


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file = null
	var json := JSON.new()
	return json.data as Dictionary if json.parse(text) == OK and json.data is Dictionary else {}


func _release_directory(release_id: String) -> String:
	return _settings.base_directory.path_join("releases").path_join(release_id)


func _record_path(release_id: String) -> String:
	return _release_directory(release_id).path_join("release.json")


func _state_path() -> String:
	return _settings.base_directory.path_join("activation.json")


func _is_identifier(value: String) -> bool:
	if value in ["", ".", ".."]:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
