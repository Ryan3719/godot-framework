class_name GFContentManifest
extends RefCounted

const SCHEMA_VERSION := 1

var release_id := ""
var packs: Array[GFContentPackDefinition] = []
var last_error := ""


func parse(text: String) -> Error:
	last_error = ""
	release_id = ""
	packs.clear()
	var json := JSON.new()
	var parse_result := json.parse(text)
	if parse_result != OK:
		return _fail(ERR_PARSE_ERROR, "Manifest JSON is invalid at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return _fail(ERR_INVALID_DATA, "Content manifest root must be an object.")
	var data := json.data as Dictionary
	var raw_schema: Variant = data.get("schema_version", 0)
	if (not raw_schema is int and not raw_schema is float) or int(raw_schema) != SCHEMA_VERSION or float(raw_schema) != float(SCHEMA_VERSION):
		return _fail(ERR_INVALID_DATA, "Unsupported content manifest schema.")
	release_id = str(data.get("release_id", ""))
	if not _is_identifier(release_id):
		return _fail(ERR_INVALID_DATA, "Content release ID contains unsafe characters.")
	if not data.get("packs") is Array:
		return _fail(ERR_INVALID_DATA, "Content manifest packs must be an array.")
	var ids: Dictionary = {}
	var paths: Dictionary = {}
	for raw_pack: Variant in data.packs:
		if not raw_pack is Dictionary:
			return _fail(ERR_INVALID_DATA, "Content manifest contains a non-object pack.")
		var pack := GFContentPackDefinition.new()
		if pack.load_dictionary(raw_pack) != OK:
			return _fail(ERR_INVALID_DATA, pack.validate())
		if ids.has(pack.pack_id):
			return _fail(ERR_ALREADY_EXISTS, "Duplicate content pack ID '%s'." % pack.pack_id)
		if paths.has(pack.relative_path):
			return _fail(ERR_ALREADY_EXISTS, "Duplicate content pack path '%s'." % pack.relative_path)
		ids[pack.pack_id] = true
		paths[pack.relative_path] = true
		packs.append(pack)
	if packs.is_empty():
		return _fail(ERR_INVALID_DATA, "Content manifest must contain at least one pack.")
	return OK


func _is_identifier(value: String) -> bool:
	if value in ["", ".", ".."]:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
