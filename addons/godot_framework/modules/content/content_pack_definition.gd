class_name GFContentPackDefinition
extends RefCounted

var pack_id: StringName
var relative_path := ""
var sha256 := ""
var size := -1
var replace_files := true
var offset := 0


func load_dictionary(data: Dictionary) -> Error:
	pack_id = StringName(str(data.get("id", "")))
	relative_path = str(data.get("path", ""))
	sha256 = str(data.get("sha256", "")).to_lower()
	var raw_size: Variant = data.get("size", -1)
	var raw_offset: Variant = data.get("offset", 0)
	if not raw_size is int and not raw_size is float:
		return ERR_INVALID_DATA
	if not raw_offset is int and not raw_offset is float:
		return ERR_INVALID_DATA
	size = int(raw_size)
	offset = int(raw_offset)
	if float(raw_size) != float(size) or float(raw_offset) != float(offset):
		return ERR_INVALID_DATA
	if data.has("replace_files") and not data.replace_files is bool:
		return ERR_INVALID_DATA
	replace_files = bool(data.get("replace_files", true))
	return OK if validate().is_empty() else ERR_INVALID_DATA


func validate() -> String:
	if pack_id.is_empty():
		return "Content pack ID cannot be empty."
	if not _is_identifier(str(pack_id)):
		return "Content pack ID '%s' contains unsafe characters." % pack_id
	if relative_path.is_empty() or relative_path.contains("\\") or relative_path.contains(":"):
		return "Content pack '%s' has an unsafe path." % pack_id
	var normalized := relative_path.simplify_path()
	if normalized != relative_path or normalized.is_absolute_path() or normalized.begins_with("../"):
		return "Content pack '%s' has an unsafe path." % pack_id
	if relative_path.get_extension().to_lower() != "pck":
		return "Content pack '%s' must reference a .pck file." % pack_id
	if size < 0:
		return "Content pack '%s' must declare a non-negative size." % pack_id
	if offset < 0:
		return "Content pack '%s' has a negative offset." % pack_id
	if not _is_sha256(sha256):
		return "Content pack '%s' has an invalid SHA-256." % pack_id
	return ""


func _is_identifier(value: String) -> bool:
	if value in ["", ".", ".."]:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true
