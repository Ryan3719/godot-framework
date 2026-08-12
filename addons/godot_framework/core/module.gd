class_name GFModule
extends RefCounted

enum Lifecycle {
	CREATED,
	INITIALIZING,
	INITIALIZED,
	STARTED,
	STOPPED,
	FAILED,
}

var lifecycle: Lifecycle = Lifecycle.CREATED
var context: GFContext
var settings: Resource


func module_id() -> StringName:
	return &""


func dependencies() -> Array[StringName]:
	return []


func configure(module_settings: Resource) -> void:
	settings = module_settings


func validate_configuration() -> String:
	return ""


func initialize() -> Error:
	return OK


func start() -> Error:
	return OK


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func shutdown() -> void:
	pass


func _framework_initialize(module_context: GFContext) -> Error:
	if lifecycle != Lifecycle.CREATED:
		return ERR_ALREADY_IN_USE
	context = module_context
	lifecycle = Lifecycle.INITIALIZING
	var result := initialize()
	if lifecycle != Lifecycle.INITIALIZING:
		return ERR_BUSY
	lifecycle = Lifecycle.INITIALIZED if result == OK else Lifecycle.FAILED
	return result


func _framework_start() -> Error:
	if lifecycle != Lifecycle.INITIALIZED:
		return ERR_UNCONFIGURED
	var result := start()
	if lifecycle != Lifecycle.INITIALIZED:
		return ERR_BUSY
	lifecycle = Lifecycle.STARTED if result == OK else Lifecycle.FAILED
	return result


func _framework_shutdown() -> void:
	if lifecycle in [Lifecycle.INITIALIZING, Lifecycle.INITIALIZED, Lifecycle.STARTED, Lifecycle.FAILED]:
		shutdown()
	lifecycle = Lifecycle.STOPPED
	context = null
