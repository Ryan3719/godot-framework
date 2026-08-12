class_name GFTrackingTestView
extends GFUIView

var trace: Array = []


func opened(payload: Variant) -> void:
	trace.append(["opened", payload])


func suspended() -> void:
	trace.append(["suspended"])


func resumed(payload: Variant) -> void:
	trace.append(["resumed", payload])


func closed(result: Variant) -> void:
	trace.append(["closed", result])
