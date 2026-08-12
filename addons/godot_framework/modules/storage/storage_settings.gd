@tool
class_name GFStorageSettings
extends Resource

@export var base_directory := "user://saves"
@export var file_extension := "save"
@export_range(0, 100, 1) var backup_count := 1
@export_range(1, 2147483647, 1) var schema_version := 1
@export_range(1024, 268435456, 1024) var max_file_bytes := 16777216


func validate() -> String:
	if not _is_safe_user_directory(base_directory):
		return "Storage base directory must be a non-root path inside user://."
	if file_extension.is_empty() or file_extension.contains("/") or file_extension.contains("\\") or file_extension.contains(":"):
		return "Storage file extension is invalid."
	if backup_count < 0:
		return "Storage backup count cannot be negative."
	if schema_version < 1:
		return "Storage schema version must be at least one."
	if max_file_bytes < 1024:
		return "Storage file size limit must be at least 1024 bytes."
	return ""


func _is_safe_user_directory(path: String) -> bool:
	if not path.begins_with("user://") or path.contains("\\"):
		return false
	var relative := path.trim_prefix("user://")
	if relative.is_empty() or relative.contains(":"):
		return false
	var normalized := relative.simplify_path()
	return normalized not in ["", ".", ".."] and not normalized.begins_with("../")
