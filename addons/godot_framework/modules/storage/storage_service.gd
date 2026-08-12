class_name GFStorageService
extends RefCounted

signal saved(slot: StringName, path: String)
signal loaded(slot: StringName, path: String)
signal recovered(slot: StringName, backup_path: String)
signal deleted(slot: StringName)
signal operation_failed(operation: StringName, slot: StringName, error: Error)

const FILE_MAGIC := 0x31534647
const CHECKSUM_BYTES := 32

var settings: GFStorageSettings
var _migrations: Dictionary = {}


func _init(storage_settings: GFStorageSettings) -> void:
	settings = storage_settings


func register_migration(from_version: int, migration: Callable, replace := false) -> Error:
	if from_version < 0 or not migration.is_valid():
		return ERR_INVALID_PARAMETER
	if _migrations.has(from_version) and not replace:
		return ERR_ALREADY_EXISTS
	_migrations[from_version] = migration
	return OK


func save(slot: StringName, data: Dictionary) -> Error:
	if not _valid_slot(slot) or not _is_serializable(data, []):
		operation_failed.emit(&"save", slot, ERR_INVALID_DATA)
		return ERR_INVALID_DATA
	var directory_result := DirAccess.make_dir_recursive_absolute(settings.base_directory)
	if directory_result != OK and directory_result != ERR_ALREADY_EXISTS:
		operation_failed.emit(&"save", slot, directory_result)
		return directory_result
	var path := path_for(slot)
	var temporary_path := "%s.tmp" % path
	var envelope := {
		"schema_version": settings.schema_version,
		"saved_at": Time.get_datetime_string_from_system(true),
		"data": data,
	}
	var payload := var_to_bytes(envelope)
	if payload.size() + 8 + CHECKSUM_BYTES > settings.max_file_bytes:
		operation_failed.emit(&"save", slot, ERR_OUT_OF_MEMORY)
		return ERR_OUT_OF_MEMORY
	var checksum := _sha256(payload)
	if checksum.size() != CHECKSUM_BYTES:
		operation_failed.emit(&"save", slot, ERR_CANT_CREATE)
		return ERR_CANT_CREATE
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		operation_failed.emit(&"save", slot, error)
		return error
	file.store_32(FILE_MAGIC)
	file.store_32(payload.size())
	file.store_buffer(checksum)
	file.store_buffer(payload)
	file.flush()
	file.close()

	var rotation_result := _rotate_backups(path)
	if rotation_result != OK:
		DirAccess.remove_absolute(temporary_path)
		operation_failed.emit(&"save", slot, rotation_result)
		return rotation_result
	var rename_result := DirAccess.rename_absolute(temporary_path, path)
	if rename_result != OK:
		operation_failed.emit(&"save", slot, rename_result)
		return rename_result
	saved.emit(slot, path)
	return OK


func load(slot: StringName, default: Dictionary = {}) -> Dictionary:
	if not _valid_slot(slot):
		operation_failed.emit(&"load", slot, ERR_INVALID_PARAMETER)
		return default.duplicate(true)
	var path := path_for(slot)
	var candidates: Array[String] = [path]
	for index in range(1, settings.backup_count + 1):
		candidates.append("%s.bak%d" % [path, index])
	var failure := ERR_FILE_NOT_FOUND
	for candidate: String in candidates:
		if not FileAccess.file_exists(candidate):
			continue
		var result := _load_path(candidate)
		if bool(result.valid):
			loaded.emit(slot, candidate)
			if candidate != path:
				recovered.emit(slot, candidate)
			return (result.data as Dictionary).duplicate(true)
		failure = result.error as Error
	operation_failed.emit(&"load", slot, failure)
	return default.duplicate(true)


func exists(slot: StringName) -> bool:
	if not _valid_slot(slot):
		return false
	var path := path_for(slot)
	if FileAccess.file_exists(path):
		return true
	for index in range(1, settings.backup_count + 1):
		if FileAccess.file_exists("%s.bak%d" % [path, index]):
			return true
	return false


func delete(slot: StringName, include_backups := true) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var path := path_for(slot)
	if FileAccess.file_exists(path):
		var result := DirAccess.remove_absolute(path)
		if result != OK:
			operation_failed.emit(&"delete", slot, result)
			return result
	if include_backups:
		for index in range(1, settings.backup_count + 1):
			var backup := "%s.bak%d" % [path, index]
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
	deleted.emit(slot)
	return OK


func path_for(slot: StringName) -> String:
	return "%s/%s.%s" % [
		settings.base_directory.trim_suffix("/"),
		str(slot),
		settings.file_extension.trim_prefix("."),
	]


func _valid_slot(slot: StringName) -> bool:
	if slot.is_empty():
		return false
	var text := str(slot)
	return text.validate_node_name() == text and text != "." and text != ".."


func _rotate_backups(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	if not bool(_read_envelope(path).valid):
		return DirAccess.remove_absolute(path)
	if settings.backup_count <= 0:
		return DirAccess.remove_absolute(path)
	for index in range(settings.backup_count, 0, -1):
		var source := path if index == 1 else "%s.bak%d" % [path, index - 1]
		var target := "%s.bak%d" % [path, index]
		if FileAccess.file_exists(source):
			if FileAccess.file_exists(target):
				var remove_result := DirAccess.remove_absolute(target)
				if remove_result != OK:
					return remove_result
			var rename_result := DirAccess.rename_absolute(source, target)
			if rename_result != OK:
				return rename_result
	return OK


func _load_path(path: String) -> Dictionary:
	var decoded := _read_envelope(path)
	if not bool(decoded.valid):
		return decoded
	var envelope := decoded.envelope as Dictionary
	var version := int(envelope.schema_version)
	var data: Variant = envelope.data
	if version > settings.schema_version:
		return {"valid": false, "error": ERR_INVALID_DATA}
	while version < settings.schema_version:
		var migration: Callable = _migrations.get(version, Callable())
		if not migration.is_valid():
			return {"valid": false, "error": ERR_UNCONFIGURED}
		data = migration.call(data)
		if not data is Dictionary or not _is_serializable(data, []):
			return {"valid": false, "error": ERR_INVALID_DATA}
		version += 1
	return {"valid": true, "data": data, "error": OK}


func _read_envelope(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": FileAccess.get_open_error()}
	if file.get_length() > settings.max_file_bytes:
		file.close()
		return {"valid": false, "error": ERR_OUT_OF_MEMORY}
	if file.get_length() < 4:
		file.close()
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var marker := file.get_32()
	if marker != FILE_MAGIC:
		var legacy_result := _read_legacy_envelope(file, marker)
		file.close()
		return legacy_result
	var header_size := 8 + CHECKSUM_BYTES
	if file.get_length() < header_size:
		file.close()
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var payload_size := file.get_32()
	var checksum := file.get_buffer(CHECKSUM_BYTES)
	if payload_size != file.get_length() - header_size:
		file.close()
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var payload := file.get_buffer(payload_size)
	file.close()
	if payload.size() != payload_size or _sha256(payload) != checksum:
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var parsed: Variant = bytes_to_var(payload)
	if not parsed is Dictionary:
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var envelope := parsed as Dictionary
	var raw_version: Variant = envelope.get("schema_version")
	var data: Variant = envelope.get("data")
	if (
		not raw_version is int
		or int(raw_version) < 1
		or not data is Dictionary
		or not _is_serializable(data, [])
	):
		return {"valid": false, "error": ERR_INVALID_DATA}
	return {"valid": true, "envelope": envelope, "error": OK}


func _read_legacy_envelope(file: FileAccess, payload_size: int) -> Dictionary:
	if payload_size <= 0 or payload_size != file.get_length() - 4:
		return {"valid": false, "error": ERR_FILE_UNRECOGNIZED}
	var payload := file.get_buffer(payload_size)
	if payload.size() != payload_size:
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var parsed: Variant = bytes_to_var(payload)
	if not parsed is Dictionary:
		return {"valid": false, "error": ERR_FILE_CORRUPT}
	var envelope := parsed as Dictionary
	var raw_version: Variant = envelope.get("schema_version")
	var data: Variant = envelope.get("data")
	if (
		not raw_version is int
		or int(raw_version) < 1
		or not data is Dictionary
		or not _is_serializable(data, [])
	):
		return {"valid": false, "error": ERR_INVALID_DATA}
	return {"valid": true, "envelope": envelope, "error": OK}


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	hasher.update(data)
	return hasher.finish()


func _is_serializable(value: Variant, ancestors: Array[Variant]) -> bool:
	var value_type := typeof(value)
	if value_type in [
		TYPE_NIL,
		TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		TYPE_VECTOR2,
		TYPE_VECTOR2I,
		TYPE_RECT2,
		TYPE_RECT2I,
		TYPE_VECTOR3,
		TYPE_VECTOR3I,
		TYPE_TRANSFORM2D,
		TYPE_VECTOR4,
		TYPE_VECTOR4I,
		TYPE_PLANE,
		TYPE_QUATERNION,
		TYPE_AABB,
		TYPE_BASIS,
		TYPE_TRANSFORM3D,
		TYPE_PROJECTION,
		TYPE_COLOR,
		TYPE_STRING_NAME,
		TYPE_NODE_PATH,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY,
	]:
		return true
	match value_type:
		TYPE_ARRAY:
			if _contains_same(ancestors, value):
				return false
			var next_ancestors := ancestors.duplicate()
			next_ancestors.append(value)
			for item: Variant in value:
				if not _is_serializable(item, next_ancestors):
					return false
			return true
		TYPE_DICTIONARY:
			if _contains_same(ancestors, value):
				return false
			var next_ancestors := ancestors.duplicate()
			next_ancestors.append(value)
			for key: Variant in value:
				if not key is String and not key is StringName:
					return false
				if not _is_serializable(value[key], next_ancestors):
					return false
			return true
		_:
			return false


func _contains_same(values: Array[Variant], target: Variant) -> bool:
	for value: Variant in values:
		if is_same(value, target):
			return true
	return false
