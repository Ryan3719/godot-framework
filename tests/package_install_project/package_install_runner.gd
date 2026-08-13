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
		&"ui",
		&"audio",
		&"input",
		&"localization",
		&"download",
		&"content",
		&"tables",
		&"connectivity",
	]
	var valid := framework != null and framework.is_booted()
	valid = valid and framework.modules.ordered_ids() == expected
	valid = valid and framework.get_service(GFServiceIds.UI) is GFUIService
	valid = valid and framework.get_service(GFServiceIds.AUDIO) is GFAudioService
	valid = valid and framework.get_service(GFServiceIds.INPUT) is GFInputService
	valid = valid and framework.get_service(GFServiceIds.LOCALIZATION) is GFLocalizationService
	valid = valid and framework.get_service(GFServiceIds.DOWNLOADS) is GFDownloadService
	valid = valid and framework.get_service(GFServiceIds.CONTENT) is GFContentService
	valid = valid and framework.get_service(GFServiceIds.TABLES) is GFTableService
	valid = valid and framework.get_service(GFServiceIds.CONNECTIVITY) is GFConnectivityService
	valid = valid and framework.get_node_or_null("FrameworkUI") != null
	valid = valid and framework.get_node_or_null("FrameworkAudio") != null
	valid = valid and framework.get_node_or_null("FrameworkDownloads") != null
	valid = valid and framework.get_node_or_null("FrameworkConnectivity") != null
	var validator := GFFrameworkValidator.new()
	var config_path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	valid = valid and not validator.has_errors(validator.validate_path(config_path))
	if verify_export:
		valid = valid and not FileAccess.file_exists("res://addons/godot_framework/plugin.cfg")
		valid = valid and not ResourceLoader.exists("res://addons/godot_framework/plugin.gd")
		valid = valid and not ResourceLoader.exists(
			"res://addons/godot_framework/editor/framework_validation_dock.gd"
		)
		valid = valid and not ResourceLoader.exists(
			"res://addons/godot_framework_android_export_settings/plugin.gd"
		)
	if valid:
		framework.shutdown()
		await get_tree().process_frame
		valid = not framework.is_booted() and framework.services == null
		valid = valid and framework.get_node_or_null("FrameworkUI") == null
		valid = valid and framework.get_node_or_null("FrameworkAudio") == null
		valid = valid and framework.get_node_or_null("FrameworkDownloads") == null
		valid = valid and framework.get_node_or_null("FrameworkConnectivity") == null
	if valid:
		_set_web_result(true)
		if verify_export:
			print("[EXPORT TEST] PASS: packaged addon starts and stops all modules in release export")
		else:
			print("[PACKAGE TEST] PASS: packaged addon installs and stops all module services")
		if not OS.has_feature("web"):
			get_tree().quit(0)
		return
	var failure_label := "EXPORT" if verify_export else "PACKAGE"
	_set_web_result(false)
	push_error("[%s TEST] Packaged addon runtime contract failed." % failure_label)
	if not OS.has_feature("web"):
		get_tree().quit(1)


func _set_web_result(succeeded: bool) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var title := "GF_EXPORT_TEST_PASS" if succeeded else "GF_EXPORT_TEST_FAIL"
	bridge.call(&"eval", "document.title = '%s';" % title, true)
