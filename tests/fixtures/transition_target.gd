extends Node


func _ready() -> void:
	if get_tree().has_meta(&"gf_scene_transition_test"):
		print("[TEST] PASS: scene transition completed")
		var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
		if framework != null:
			framework.shutdown()
		get_tree().quit(0)
