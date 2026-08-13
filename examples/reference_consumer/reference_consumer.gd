extends Node

const STATUS_ROUTE := &"reference.status"
const CONFIRM_ACTION := &"reference.confirm"
const STORAGE_SLOT := &"reference_session"
const EXPORT_VERIFICATION_FEATURE := "reference_consumer_export_verify"
const WEB_PASS_TITLE := "GF_REFERENCE_CONSUMER_EXPORT_PASS"
const WEB_FAIL_TITLE := "GF_REFERENCE_CONSUMER_EXPORT_FAIL"


func _ready() -> void:
	await get_tree().process_frame
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	var succeeded := _exercise_framework(framework)
	if succeeded:
		print("[REFERENCE CONSUMER] PASS: project configuration and integration paths succeeded")
	else:
		push_error("[REFERENCE CONSUMER] Project integration contract failed.")
	if _is_automated_run():
		if framework != null and framework.is_booted():
			framework.shutdown()
			await get_tree().process_frame
			succeeded = succeeded and framework.services == null
		if succeeded:
			if _is_export_verification():
				print("[REFERENCE CONSUMER EXPORT] PASS: project integration paths succeeded in release export")
		else:
			push_error("[REFERENCE CONSUMER] Automated shutdown contract failed.")
		_set_web_result(succeeded)
		if not OS.has_feature("web"):
			get_tree().quit(0 if succeeded else 1)


func _exercise_framework(framework: GFFrameworkHost) -> bool:
	if framework == null or not framework.is_booted():
		return _fail("framework host did not boot")
	var validator := GFFrameworkValidator.new()
	var config_path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	if validator.has_errors(validator.validate_path(config_path)):
		return _fail("project-owned configuration did not validate")

	var resources := framework.get_service(GFServiceIds.RESOURCES) as GFResourceService
	var storage := framework.get_service(GFServiceIds.STORAGE) as GFStorageService
	var settings := framework.get_service(GFServiceIds.SETTINGS) as GFSettingsService
	var ui := framework.get_service(GFServiceIds.UI) as GFUIService
	var input := framework.get_service(GFServiceIds.INPUT) as GFInputService
	var localization := framework.get_service(GFServiceIds.LOCALIZATION) as GFLocalizationService
	if resources == null or storage == null or settings == null or ui == null or input == null or localization == null:
		return _fail("required project services were not registered")

	var view_handle := resources.acquire("res://ui/reference_view.tscn", "PackedScene")
	if view_handle == null or not view_handle.resource is PackedScene:
		return _fail("project scene could not be acquired")
	view_handle.release()

	if settings.set_value(&"reference", &"configured", true) != OK:
		return _fail("settings write failed")
	if settings.get_value(&"reference", &"configured", false) != true:
		return _fail("settings read did not return the project value")
	if storage.save(STORAGE_SLOT, {"version": 1, "origin": "reference_consumer"}) != OK:
		return _fail("storage write failed")
	if storage.load(STORAGE_SLOT).get("origin") != "reference_consumer":
		return _fail("storage read did not return the project value")
	if storage.delete(STORAGE_SLOT) != OK:
		return _fail("storage cleanup failed")

	var saved_profile := input.capture_profile()
	var rebound_key := InputEventKey.new()
	rebound_key.physical_keycode = KEY_SPACE
	if input.rebind(CONFIRM_ACTION, [rebound_key]) != OK:
		return _fail("input rebind failed")
	if not input.has_equivalent_binding(CONFIRM_ACTION, rebound_key):
		return _fail("input rebind did not become active")
	if input.apply_profile(saved_profile) != OK:
		return _fail("input profile restore failed")

	var english := Translation.new()
	english.locale = "en_US"
	english.add_message(&"reference.status", "Framework ready, {name}")
	var chinese := Translation.new()
	chinese.locale = "zh_CN"
	chinese.add_message(&"reference.status", "Framework ready (CN), {name}")
	if localization.add_translation(english) != OK or localization.add_translation(chinese) != OK:
		return _fail("project translations could not be registered")
	if localization.set_locale("zh_CN") != OK:
		return _fail("project locale selection failed")
	if localization.format(&"reference.status", {"name": "consumer"}) != "Framework ready (CN), consumer":
		return _fail("project translation formatting failed")

	var view := ui.open(STATUS_ROUTE, {"status": localization.translate(&"reference.status")})
	if view == null or view.lifecycle != GFUIView.Lifecycle.OPENED:
		return _fail("project UI route did not open")
	if str(view.get_meta(&"reference_status", "")) != "Framework ready (CN), {name}":
		return _fail("project UI view did not receive route payload")
	if _is_automated_run() and ui.close(view, {"verified": true}) != OK:
		return _fail("project UI route did not close")
	return true


func _fail(stage: String) -> bool:
	print("[REFERENCE CONSUMER] FAIL: %s" % stage)
	return false


func _is_automated_run() -> bool:
	return (
		OS.get_cmdline_user_args().has("--verify-reference-consumer")
		or _is_export_verification()
	)


func _is_export_verification() -> bool:
	return OS.has_feature(EXPORT_VERIFICATION_FEATURE)


func _set_web_result(succeeded: bool) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var title := WEB_PASS_TITLE if succeeded else WEB_FAIL_TITLE
	bridge.call(&"eval", "document.title = '%s';" % title, true)
