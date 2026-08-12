extends Node


func _ready() -> void:
	await get_tree().process_frame
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
	if valid:
		print("[PACKAGE TEST] PASS: packaged addon installs with minimal defaults")
		framework.shutdown()
		get_tree().quit(0)
		return
	push_error("[PACKAGE TEST] Packaged addon installation contract failed.")
	get_tree().quit(1)
