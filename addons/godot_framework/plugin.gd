@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GodotFramework"
const AUTOLOAD_PATH := "res://addons/godot_framework/runtime/framework_host.gd"
const CONFIG_PATH_SETTING := "godot_framework/config_path"
const AUTO_BOOT_SETTING := "godot_framework/auto_boot"
const DEFAULT_CONFIG_PATH := "res://addons/godot_framework/config/default_framework_config.tres"

var _validation_dock: GFFrameworkValidationDock


func _enter_tree() -> void:
	_ensure_registered()
	_create_validation_dock()


func _enable_plugin() -> void:
	_ensure_registered()
	_create_validation_dock()


func _ensure_registered() -> void:
	_register_project_settings()
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(autoload_setting):
		ProjectSettings.set_setting(autoload_setting, "*%s" % AUTOLOAD_PATH)
	ProjectSettings.save()


func _disable_plugin() -> void:
	_remove_validation_dock()
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	var configured_path := str(ProjectSettings.get_setting(autoload_setting, ""))
	if configured_path.trim_prefix("*") == AUTOLOAD_PATH:
		ProjectSettings.set_setting(autoload_setting, null)
		ProjectSettings.save()


func _exit_tree() -> void:
	_remove_validation_dock()


func _register_project_settings() -> void:
	if not ProjectSettings.has_setting(CONFIG_PATH_SETTING):
		ProjectSettings.set_setting(CONFIG_PATH_SETTING, DEFAULT_CONFIG_PATH)
	ProjectSettings.add_property_info({
		"name": CONFIG_PATH_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res",
	})

	if not ProjectSettings.has_setting(AUTO_BOOT_SETTING):
		ProjectSettings.set_setting(AUTO_BOOT_SETTING, true)
	ProjectSettings.add_property_info({
		"name": AUTO_BOOT_SETTING,
		"type": TYPE_BOOL,
	})


func _create_validation_dock() -> void:
	if is_instance_valid(_validation_dock):
		return
	_validation_dock = GFFrameworkValidationDock.new()
	_validation_dock.inspect_requested.connect(_on_inspect_requested)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _validation_dock)


func _remove_validation_dock() -> void:
	if not is_instance_valid(_validation_dock):
		_validation_dock = null
		return
	remove_control_from_docks(_validation_dock)
	_validation_dock.queue_free()
	_validation_dock = null


func _on_inspect_requested(resource: Resource) -> void:
	get_editor_interface().edit_resource(resource)
