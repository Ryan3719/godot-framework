extends GFUIView


func _ready() -> void:
	%CloseButton.pressed.connect(request_close)


func opened(payload: Variant) -> void:
	var status := str((payload as Dictionary).get("status", "Framework ready")) if payload is Dictionary else "Framework ready"
	set_meta(&"reference_status", status)
	var status_label := get_node_or_null("Panel/Margin/Content/StatusLabel") as Label
	if status_label != null:
		status_label.text = status
