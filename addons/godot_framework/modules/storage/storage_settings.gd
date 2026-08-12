class_name GFStorageSettings
extends Resource

@export var base_directory := "user://saves"
@export var file_extension := "save"
@export_range(0, 100, 1) var backup_count := 1
@export_range(1, 2147483647, 1) var schema_version := 1
