class_name GFTrackingTestState
extends GFState

var id: StringName
var trace: Array[String]
var allow_enter := true
var allow_exit := true


func setup(p_id: StringName, p_trace: Array[String]) -> GFTrackingTestState:
	id = p_id
	trace = p_trace
	return self


func state_id() -> StringName:
	return id


func can_enter(_from: StringName, _payload: Variant) -> bool:
	return allow_enter


func enter(from: StringName, _payload: Variant) -> void:
	trace.append("enter:%s:%s" % [id, from])


func update(_delta: float) -> void:
	trace.append("update:%s" % id)


func can_exit(_to: StringName, _payload: Variant) -> bool:
	return allow_exit


func exit(to: StringName, _payload: Variant) -> void:
	trace.append("exit:%s:%s" % [id, to])
