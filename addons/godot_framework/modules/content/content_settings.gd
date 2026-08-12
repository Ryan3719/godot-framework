@tool
class_name GFContentSettings
extends Resource

@export var base_directory := "user://godot_framework/content"
@export_multiline var public_key_pem := ""
@export var require_signature := true
@export var auto_mount_active := true
@export_range(1024, 16777216, 1024) var max_manifest_bytes := 1048576


func validate() -> String:
	if not _is_safe_user_directory(base_directory):
		return "Content base directory must be a non-root path inside user://."
	if require_signature and public_key_pem.strip_edges().is_empty():
		return "Signed content requires an RSA public key."
	if max_manifest_bytes < 1024:
		return "Content manifest limit must be at least 1024 bytes."
	return ""


func _is_safe_user_directory(path: String) -> bool:
	if not path.begins_with("user://") or path.contains("\\"):
		return false
	var relative := path.trim_prefix("user://")
	if relative.is_empty() or relative.contains(":"):
		return false
	for component: String in relative.split("/", false):
		if component == "..":
			return false
	var normalized := relative.simplify_path()
	return normalized not in ["", ".", ".."] and not normalized.begins_with("../")
