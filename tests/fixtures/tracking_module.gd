class_name GFTrackingTestModule
extends GFModule

var id: StringName
var required: Array[StringName] = []
var trace: Array[String]
var initialize_result := OK
var start_result := OK


func setup(
	p_id: StringName,
	p_required: Array[StringName],
	p_trace: Array[String],
	p_initialize_result := OK,
	p_start_result := OK,
) -> GFTrackingTestModule:
	id = p_id
	required = p_required
	trace = p_trace
	initialize_result = p_initialize_result
	start_result = p_start_result
	return self


func module_id() -> StringName:
	return id


func dependencies() -> Array[StringName]:
	return required


func initialize() -> Error:
	trace.append("initialize:%s" % id)
	return initialize_result


func start() -> Error:
	trace.append("start:%s" % id)
	return start_result


func shutdown() -> void:
	trace.append("shutdown:%s" % id)
