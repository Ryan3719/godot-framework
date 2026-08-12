@tool
class_name GFSettingsSettings
extends Resource

@export var file_path := "user://settings.cfg"
@export var auto_save := true


func validate() -> String:
	if not file_path.begins_with("user://") or file_path.trim_prefix("user://").is_empty():
		return "User settings file must be a non-root path inside user://."
	var relative := file_path.trim_prefix("user://")
	if relative.contains("\\") or relative.contains(":"):
		return "User settings file path is invalid."
	var normalized := relative.simplify_path()
	if normalized in ["", ".", ".."] or normalized.begins_with("../") or normalized.get_file().is_empty():
		return "User settings file path is invalid."
	return ""
