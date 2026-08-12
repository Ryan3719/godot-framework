@tool
class_name GFResourceSettings
extends Resource

@export_range(1, 64, 1) var max_threaded_requests_per_frame := 8
@export var cache_loaded_resources := true


func validate() -> String:
	if max_threaded_requests_per_frame < 1:
		return "Resource poll budget must be at least one request per frame."
	return ""
