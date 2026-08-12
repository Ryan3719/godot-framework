extends Node

const SOURCE_PATH := "user://gf_content_pack_source.txt"
const PACK_PATH := "user://gf_content_pack_test.pck"
const VIRTUAL_PATH := "res://gf_generated_content_marker.txt"


func _ready() -> void:
	var source := FileAccess.open(SOURCE_PATH, FileAccess.WRITE)
	if source == null:
		_finish(false, "Could not create content pack source file")
		return
	source.store_string("mounted content")
	source.flush()
	source = null

	var packer := PCKPacker.new()
	if packer.pck_start(PACK_PATH) != OK:
		_finish(false, "Could not start PCK writer")
		return
	if packer.add_file(VIRTUAL_PATH, SOURCE_PATH) != OK:
		_finish(false, "Could not add file to PCK")
		return
	if packer.flush() != OK:
		_finish(false, "Could not flush PCK")
		return
	if not ProjectSettings.load_resource_pack(PACK_PATH, true):
		_finish(false, "Could not mount generated PCK")
		return
	if FileAccess.get_file_as_string(VIRTUAL_PATH) != "mounted content":
		_finish(false, "Mounted PCK content could not be read")
		return
	_finish(true)


func _finish(success: bool, error := "") -> void:
	if FileAccess.file_exists(SOURCE_PATH):
		DirAccess.remove_absolute(SOURCE_PATH)
	if FileAccess.file_exists(PACK_PATH):
		DirAccess.remove_absolute(PACK_PATH)
	if success:
		print("[TEST] PASS: content pack mounted")
		get_tree().quit(0)
		return
	push_error("[TEST] %s" % error)
	get_tree().quit(1)
