extends Node


func _ready() -> void:
	await get_tree().process_frame
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	if framework == null or not framework.is_booted():
		_fail("Framework did not boot for scene transition test.")
		return
	var scenes := framework.get_service(GFServiceIds.SCENES) as GFSceneService
	if scenes == null:
		_fail("Scene service is unavailable.")
		return
	get_tree().set_meta(&"gf_scene_transition_test", true)
	if scenes.change_to_file("res://tests/fixtures/transition_target.tscn") != OK:
		_fail("Scene service rejected a valid PackedScene.")
		return


func _fail(message: String) -> void:
	push_error("[TEST] %s" % message)
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	if framework != null:
		framework.shutdown()
	get_tree().quit(1)
