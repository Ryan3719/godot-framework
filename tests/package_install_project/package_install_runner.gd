extends Node


func _ready() -> void:
	await get_tree().process_frame
	var verify_export := not OS.has_feature("editor") or OS.get_cmdline_user_args().has("--verify-export-pack")
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	var expected: Array[StringName] = [
		&"resource",
		&"scene",
		&"storage",
		&"settings",
		&"pool",
		&"state_machine",
	]
	var valid := framework != null and framework.is_booted()
	valid = valid and framework.modules.ordered_ids() == expected
	valid = valid and framework.get_service(GFServiceIds.CONNECTIVITY) == null
	var validator := GFFrameworkValidator.new()
	var config_path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	valid = valid and not validator.has_errors(validator.validate_path(config_path))
	if verify_export:
		valid = valid and not FileAccess.file_exists("res://addons/godot_framework/plugin.cfg")
		valid = valid and not ResourceLoader.exists("res://addons/godot_framework/plugin.gd")
		valid = valid and not ResourceLoader.exists(
			"res://addons/godot_framework/editor/framework_validation_dock.gd"
		)
	if valid:
		if verify_export:
			print("[EXPORT TEST] PASS: packaged addon runs in Linux release export")
		else:
			print("[PACKAGE TEST] PASS: packaged addon installs with minimal defaults")
		framework.shutdown()
		get_tree().quit(0)
		return
	var failure_label := "EXPORT" if verify_export else "PACKAGE"
	push_error("[%s TEST] Packaged addon runtime contract failed." % failure_label)
	get_tree().quit(1)
