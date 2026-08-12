class_name GFState
extends RefCounted

var _machine_ref: WeakRef


func get_machine() -> GFStateMachine:
	if _machine_ref == null:
		return null
	return _machine_ref.get_ref() as GFStateMachine


func _bind_machine(value: GFStateMachine) -> void:
	_machine_ref = weakref(value) if value != null else null


func state_id() -> StringName:
	return &""


func can_enter(_from: StringName, _payload: Variant) -> bool:
	return true


func enter(_from: StringName, _payload: Variant) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func can_exit(_to: StringName, _payload: Variant) -> bool:
	return true


func exit(_to: StringName, _payload: Variant) -> void:
	pass
