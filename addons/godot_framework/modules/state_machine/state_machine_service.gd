class_name GFStateMachineService
extends RefCounted

var _machines: Dictionary = {}


func create(machine_id: StringName) -> GFStateMachine:
	if machine_id.is_empty() or _machines.has(machine_id):
		return null
	var machine := GFStateMachine.new()
	_machines[machine_id] = machine
	return machine


func add(machine_id: StringName, machine: GFStateMachine, replace := false) -> Error:
	if machine_id.is_empty() or machine == null:
		return ERR_INVALID_PARAMETER
	if _machines.has(machine_id) and not replace:
		return ERR_ALREADY_EXISTS
	_machines[machine_id] = machine
	return OK


func get_machine(machine_id: StringName) -> GFStateMachine:
	return _machines.get(machine_id) as GFStateMachine


func remove(machine_id: StringName) -> bool:
	return _machines.erase(machine_id)


func update(delta: float) -> void:
	for machine: GFStateMachine in _machines.values():
		machine.update(delta)


func physics_update(delta: float) -> void:
	for machine: GFStateMachine in _machines.values():
		machine.physics_update(delta)


func clear() -> void:
	for machine: GFStateMachine in _machines.values():
		machine.clear()
	_machines.clear()
