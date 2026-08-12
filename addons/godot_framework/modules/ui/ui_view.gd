class_name GFUIView
extends Control

signal close_requested(result: Variant)

enum Lifecycle {
	CREATED,
	OPENED,
	SUSPENDED,
	CLOSED,
}

var lifecycle := Lifecycle.CREATED
var route_id: StringName
var _service_ref: WeakRef


func request_close(result: Variant = null) -> void:
	if lifecycle != Lifecycle.CLOSED:
		close_requested.emit(result)


func ui_service() -> GFUIService:
	if _service_ref == null:
		return null
	return _service_ref.get_ref() as GFUIService


func opened(_payload: Variant) -> void:
	pass


func suspended() -> void:
	pass


func resumed(_payload: Variant) -> void:
	pass


func closed(_result: Variant) -> void:
	pass


func _framework_open(service: GFUIService, id: StringName, payload: Variant) -> void:
	_service_ref = weakref(service)
	route_id = id
	lifecycle = Lifecycle.OPENED
	opened(payload)


func _framework_suspend() -> void:
	if lifecycle != Lifecycle.OPENED:
		return
	lifecycle = Lifecycle.SUSPENDED
	process_mode = Node.PROCESS_MODE_DISABLED
	suspended()


func _framework_resume(payload: Variant) -> void:
	if lifecycle != Lifecycle.SUSPENDED:
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	lifecycle = Lifecycle.OPENED
	resumed(payload)


func _framework_close(result: Variant) -> void:
	if lifecycle == Lifecycle.CLOSED:
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	lifecycle = Lifecycle.CLOSED
	closed(result)
	_service_ref = null
