@tool
extends EditorPlugin


func _enter_tree() -> void:
	var arguments := _parse_arguments()
	var java_sdk_path := str(arguments.get("java-sdk-path", "")).simplify_path()
	var android_sdk_path := str(arguments.get("android-sdk-path", "")).simplify_path()
	if not _is_java_sdk(java_sdk_path):
		_finish(1, "Java SDK must contain bin/java and bin/keytool.")
		return
	if not _is_android_sdk(android_sdk_path):
		_finish(1, "Android SDK must contain platform-tools/adb.")
		return
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", java_sdk_path)
	settings.set_setting("export/android/android_sdk_path", android_sdk_path)
	_finish(0, "Editor settings configured.")


func _parse_arguments() -> Dictionary:
	var parsed := {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		parsed[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return parsed


func _is_java_sdk(path: String) -> bool:
	return not path.is_empty() and FileAccess.file_exists(path.path_join("bin/java")) \
		and FileAccess.file_exists(path.path_join("bin/keytool"))


func _is_android_sdk(path: String) -> bool:
	return not path.is_empty() and FileAccess.file_exists(path.path_join("platform-tools/adb"))


func _finish(exit_code: int, message: String) -> void:
	var prefix := "[ANDROID EXPORT]"
	if exit_code == 0:
		print("%s %s" % [prefix, message])
	else:
		push_error("%s %s" % [prefix, message])
	get_tree().process_frame.connect(get_tree().quit.bind(exit_code), CONNECT_ONE_SHOT)
