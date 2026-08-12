class_name GFDownloadSettings
extends Resource

@export var root_name := "FrameworkDownloads"
@export var base_directory := "user://godot_framework/downloads"
@export_range(1, 16, 1) var max_concurrent := 2
@export_range(0, 10, 1) var retry_count := 2
@export_range(0.0, 3600.0, 0.1) var timeout_seconds := 30.0
@export var use_threads := true
@export_range(0, 32, 1) var max_redirects := 8
@export_range(-1, 2147483647, 1) var body_size_limit_bytes := -1
@export var retry_http_status_codes := PackedInt32Array([408, 425, 429, 500, 502, 503, 504])


func validate() -> String:
	if root_name.is_empty():
		return "Download root name cannot be empty."
	if not _is_safe_user_directory(base_directory):
		return "Download base directory must be a non-root path inside user://."
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
