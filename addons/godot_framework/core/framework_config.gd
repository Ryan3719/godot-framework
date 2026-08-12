@tool
class_name GFFrameworkConfig
extends Resource

@export var modules: Array[GFModuleDefinition] = []
@export var minimum_log_level: GFLogger.Level = GFLogger.Level.INFO
@export_range(1, 65536, 1) var max_queued_events_per_frame := 1024
@export_range(1, 1048576, 1) var max_queued_events := 8192


func validate() -> String:
	if minimum_log_level not in GFLogger.Level.values():
		return "Framework minimum log level is invalid."
	if max_queued_events_per_frame < 1:
		return "Framework queued-event budget must be at least one per frame."
	if max_queued_events < 1:
		return "Framework queued-event capacity must be at least one."
	return ""
