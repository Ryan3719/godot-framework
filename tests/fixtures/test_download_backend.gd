class_name GFTestDownloadBackend
extends GFDownloadBackend

var plan: Dictionary = {}
var _downloaded := 0
var _total := -1
var _cancelled := false
var _temp_path := ""


func setup(value: Dictionary) -> GFTestDownloadBackend:
	plan = value
	return self


func start(
	_url: String,
	temp_path: String,
	_headers: PackedStringArray,
	_timeout_seconds: float,
	_use_threads: bool,
	_max_redirects: int,
	_body_size_limit_bytes: int,
) -> Error:
	_temp_path = temp_path
	var start_error := int(plan.get("start_error", OK)) as Error
	if start_error != OK:
		return start_error
	var data := plan.get("data", PackedByteArray()) as PackedByteArray
	_downloaded = data.size()
	_total = data.size()
	if bool(plan.get("write_on_start", false)):
		_write_data(data)
	if bool(plan.get("auto_complete", true)):
		call_deferred("_complete")
	return OK


func cancel() -> void:
	_cancelled = true


func downloaded_bytes() -> int:
	return _downloaded


func body_size() -> int:
	return _total


func _complete() -> void:
	if _cancelled:
		return
	_write_data(plan.get("data", PackedByteArray()) as PackedByteArray)
	completed.emit(
		int(plan.get("result", HTTPRequest.RESULT_SUCCESS)),
		int(plan.get("response_code", 200)),
		PackedStringArray(),
	)


func _write_data(data: PackedByteArray) -> void:
	var file := FileAccess.open(_temp_path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(data)
		file = null
