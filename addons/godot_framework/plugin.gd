@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GodotFramework"
const AUTOLOAD_PATH := "res://addons/godot_framework/runtime/framework_host.gd"
const CONFIG_PATH_SETTING := "godot_framework/config_path"
const AUTO_BOOT_SETTING := "godot_framework/auto_boot"
const DEFAULT_CONFIG_PATH := "res://addons/godot_framework/config/default_framework_config.tres"


func _enter_tree() -> void:
	_ensure_registered()


func _enable_plugin() -> void:
	_ensure_registered()


func _ensure_registered() -> void:
	_register_project_settings()
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(autoload_setting):
		ProjectSettings.set_setting(autoload_setting, "*%s" % AUTOLOAD_PATH)
	ProjectSettings.save()


func _disable_plugin() -> void:
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	var configured_path := str(ProjectSettings.get_setting(autoload_setting, ""))
	if configured_path.trim_prefix("*") == AUTOLOAD_PATH:
		ProjectSettings.set_setting(autoload_setting, null)
		ProjectSettings.save()


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
