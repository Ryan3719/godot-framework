class_name GFFrameworkConfig
extends Resource

@export var modules: Array[GFModuleDefinition] = []
@export var minimum_log_level: GFLogger.Level = GFLogger.Level.INFO
@export_range(1, 65536, 1) var max_queued_events_per_frame := 1024
