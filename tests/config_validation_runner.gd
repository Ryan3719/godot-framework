extends Node


func _ready() -> void:
	var path := str(ProjectSettings.get_setting(GFFrameworkHost.CONFIG_PATH_SETTING, ""))
	var validator := GFFrameworkValidator.new()
	var issues := validator.validate_path(path)
	if validator.has_errors(issues):
		for issue: Dictionary in issues:
			print("[%s] %s" % [issue.code, issue.message])
		push_error("[CONFIG TEST] Framework configuration is invalid.")
		get_tree().quit(1)
		return
	print("[CONFIG TEST] PASS: framework configuration is valid")
	get_tree().quit(0)
