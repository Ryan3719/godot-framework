@tool
class_name GFFrameworkValidationDock
extends VBoxContainer

signal inspect_requested(resource: Resource)

var _path_label: Label
var _summary_label: Label
var _issues: Tree
var _validator := GFFrameworkValidator.new()


func _ready() -> void:
	name = "Framework"
	_build_ui()
	if DisplayServer.get_name() != "headless":
		refresh()
	else:
		_path_label.text = "Headless editor validation is disabled"
		_summary_label.text = "Use the configuration validation runner"


func refresh() -> void:
	if _issues == null:
		return
	var path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	_path_label.text = path if not path.is_empty() else "No configuration path"
	var report := _validator.validate_path(path)
	_render(report)


func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.icon = get_theme_icon(&"Reload", &"EditorIcons")
	refresh_button.tooltip_text = "Validate the configured framework resource"
	refresh_button.pressed.connect(refresh)
	toolbar.add_child(refresh_button)
	var inspect_button := Button.new()
	inspect_button.text = "Inspect"
	inspect_button.icon = get_theme_icon(&"Object", &"EditorIcons")
	inspect_button.tooltip_text = "Open the framework configuration in Inspector"
	inspect_button.pressed.connect(_inspect_config)
	toolbar.add_child(inspect_button)
	add_child(toolbar)

	_path_label = Label.new()
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path_label.tooltip_text = "Project setting: godot_framework/config_path"
	add_child(_path_label)
	_summary_label = Label.new()
	add_child(_summary_label)

	_issues = Tree.new()
	_issues.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issues.columns = 2
	_issues.set_column_title(0, "Level")
	_issues.set_column_title(1, "Issue")
	_issues.set_column_custom_minimum_width(0, 72)
	_issues.hide_root = true
	add_child(_issues)


func _render(report: Array[Dictionary]) -> void:
	_issues.clear()
	var root := _issues.create_item()
	var counts := {"errors": 0, "warnings": 0, "info": 0}
	for issue: Dictionary in report:
		var severity := int(issue.get("severity", GFFrameworkValidator.Severity.ERROR))
		var item := _issues.create_item(root)
		item.set_text(0, _severity_name(severity))
		item.set_icon(0, _severity_icon(severity))
		var module_id := str(issue.get("module_id", ""))
		var prefix := "[%s] " % module_id if not module_id.is_empty() else ""
		item.set_text(1, "%s%s" % [prefix, str(issue.get("message", ""))])
		item.set_tooltip_text(1, str(issue.get("code", "")))
		match severity:
			GFFrameworkValidator.Severity.ERROR:
				counts.errors += 1
			GFFrameworkValidator.Severity.WARNING:
				counts.warnings += 1
			_:
				counts.info += 1
	_summary_label.text = "%d errors, %d warnings" % [counts.errors, counts.warnings]


func _inspect_config() -> void:
	var path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var resource := ResourceLoader.load(path)
	if resource != null:
		inspect_requested.emit(resource)


func _severity_name(severity: int) -> String:
	match severity:
		GFFrameworkValidator.Severity.ERROR:
			return "Error"
		GFFrameworkValidator.Severity.WARNING:
			return "Warning"
		_:
			return "Info"


func _severity_icon(severity: int) -> Texture2D:
	match severity:
		GFFrameworkValidator.Severity.ERROR:
			return get_theme_icon(&"StatusError", &"EditorIcons")
		GFFrameworkValidator.Severity.WARNING:
			return get_theme_icon(&"StatusWarning", &"EditorIcons")
		_:
			return get_theme_icon(&"StatusSuccess", &"EditorIcons")
