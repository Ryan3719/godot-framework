class_name GFDownloadService
extends RefCounted

signal task_queued(task_id: int, url: String, target_path: String)
signal task_started(task_id: int, attempt: int)
signal task_progress(task_id: int, downloaded_bytes: int, total_bytes: int)
signal task_retry_scheduled(task_id: int, next_attempt: int, error: Error, response_code: int)
signal task_completed(task_id: int, target_path: String)
signal task_failed(task_id: int, error: Error, response_code: int)
signal task_cancelled(task_id: int)

enum TaskState {
	QUEUED,
	RUNNING,
	COMPLETED,
	FAILED,
	CANCELLED,
}

var last_error := ""

var _settings: GFDownloadSettings
var _root: Node
var _backend_factory: Callable
var _queue: Array[int] = []
var _tasks: Dictionary = {}
var _active: Dictionary = {}
var _finished_order: Array[int] = []
var _next_id := 1
var _dispatching := false
var _closed := false


func _init(host: Node, settings: GFDownloadSettings, backend_factory := Callable()) -> void:
	_settings = settings
	_backend_factory = backend_factory
	_root = Node.new()
	_root.name = settings.root_name
	host.add_child(_root)


func enqueue(
	url: String,
	relative_path: String,
	expected_sha256 := "",
	expected_size := -1,
	headers := PackedStringArray(),
) -> int:
	last_error = ""
	if _closed or _settings == null:
		return _fail_id("Download service is shut down.")
	var normalized_path := _normalize_relative_path(relative_path)
	var normalized_hash := expected_sha256.to_lower()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return _fail_id("Download URL must use HTTP or HTTPS.")
	if normalized_path.is_empty():
		return _fail_id("Download target must be a safe relative path.")
	if expected_size < -1:
		return _fail_id("Expected download size cannot be less than -1.")
	if not normalized_hash.is_empty() and not _is_sha256(normalized_hash):
		return _fail_id("Expected SHA-256 must contain exactly 64 hexadecimal characters.")
	if _queue.size() + _active.size() >= _settings.max_in_flight_tasks:
		return _fail_id("Download task queue is full.")

	var task_id := _next_id
	_next_id += 1
	var target_path := _settings.base_directory.path_join(normalized_path)
	if _target_in_use(target_path):
		return _fail_id("Another download already owns target '%s'." % normalized_path)
	_tasks[task_id] = {
		"id": task_id,
		"url": url,
		"relative_path": normalized_path,
		"target_path": target_path,
		"temp_path": "%s.part.%d" % [target_path, task_id],
		"headers": headers.duplicate(),
		"expected_sha256": normalized_hash,
		"expected_size": expected_size,
		"state": TaskState.QUEUED,
		"attempts": 0,
		"error": OK,
		"response_code": 0,
		"downloaded_bytes": 0,
		"total_bytes": -1,
	}
	_queue.append(task_id)
	task_queued.emit(task_id, url, target_path)
	return task_id


func update(_delta: float = 0.0) -> void:
	if _closed:
		return
	for task_id: int in _active.keys():
		var backend := _active.get(task_id) as GFDownloadBackend
		if backend == null or not is_instance_valid(backend):
			_fail_or_retry(task_id, ERR_BUG, 0, 0)
			continue
		var task: Dictionary = _tasks[task_id]
		var downloaded := backend.downloaded_bytes()
		var total := backend.body_size()
		if downloaded != int(task.downloaded_bytes) or total != int(task.total_bytes):
			task.downloaded_bytes = downloaded
			task.total_bytes = total
			task_progress.emit(task_id, downloaded, total)
	_dispatch()


func cancel(task_id: int) -> bool:
	if not _tasks.has(task_id):
		return false
	var task: Dictionary = _tasks[task_id]
	if int(task.state) not in [TaskState.QUEUED, TaskState.RUNNING]:
		return false
	_queue.erase(task_id)
	var backend := _active.get(task_id) as GFDownloadBackend
	_active.erase(task_id)
	if backend != null and is_instance_valid(backend):
		backend.cancel()
		_dispose_backend(backend)
	_remove_file(task.temp_path)
	task.state = TaskState.CANCELLED
	task.error = ERR_SKIP
	_record_finished(task_id)
	task_cancelled.emit(task_id)
	return true


func task_info(task_id: int) -> Dictionary:
	if not _tasks.has(task_id):
		return {}
	return (_tasks[task_id] as Dictionary).duplicate(true)


func task_state(task_id: int) -> int:
	return int((_tasks[task_id] as Dictionary).state) if _tasks.has(task_id) else -1


func queued_count() -> int:
	return _queue.size()


func active_count() -> int:
	return _active.size()


func clear_finished() -> int:
	var removed := 0
	for task_id: int in _tasks.keys():
		if int((_tasks[task_id] as Dictionary).state) in [TaskState.COMPLETED, TaskState.FAILED, TaskState.CANCELLED]:
			_tasks.erase(task_id)
			removed += 1
	_finished_order.clear()
	return removed


func shutdown() -> void:
	if _closed:
		return
	_closed = true
	for task_id: int in _tasks.keys():
		if int((_tasks[task_id] as Dictionary).state) in [TaskState.QUEUED, TaskState.RUNNING]:
			cancel(task_id)
	_queue.clear()
	_active.clear()
	_tasks.clear()
	_finished_order.clear()
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_backend_factory = Callable()
	_settings = null


func _dispatch() -> void:
	if _dispatching or _closed or _settings == null:
		return
	_dispatching = true
	while not _closed and _settings != null and _active.size() < _settings.max_concurrent and not _queue.is_empty():
		var task_id := _queue.pop_front()
		if task_state(task_id) != TaskState.QUEUED:
			continue
		_start_task(task_id)
	_dispatching = false


func _start_task(task_id: int) -> void:
	var task: Dictionary = _tasks[task_id]
	task.attempts = int(task.attempts) + 1
	task.state = TaskState.RUNNING
	var directory_result := DirAccess.make_dir_recursive_absolute(str(task.target_path).get_base_dir())
	if directory_result != OK:
		_fail_or_retry(task_id, directory_result, 0, 0)
		return
	_remove_file(task.temp_path)
	var backend := _create_backend()
	if backend == null:
		_fail_or_retry(task_id, ERR_CANT_CREATE, 0, 0)
		return
	_root.add_child(backend)
	backend.completed.connect(_on_backend_completed.bind(task_id), CONNECT_ONE_SHOT)
	_active[task_id] = backend
	var start_result := backend.start(
		task.url,
		task.temp_path,
		task.headers,
		_settings.timeout_seconds,
		_settings.use_threads,
		_settings.max_redirects,
		_settings.body_size_limit_bytes,
	)
	if start_result != OK:
		_active.erase(task_id)
		backend.cancel()
		_dispose_backend(backend)
		_fail_or_retry(task_id, start_result, 0, 0)
		return
	if task_state(task_id) == TaskState.RUNNING:
		task_started.emit(task_id, int(task.attempts))


func _on_backend_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	task_id: int,
) -> void:
	if task_state(task_id) != TaskState.RUNNING:
		return
	var backend := _active.get(task_id) as GFDownloadBackend
	_active.erase(task_id)
	if backend != null:
		_dispose_backend(backend)
	var task: Dictionary = _tasks[task_id]
	task.response_code = response_code
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_or_retry(task_id, _result_to_error(result), result, response_code)
		return
	if response_code < 200 or response_code >= 300:
		_fail_or_retry(task_id, ERR_QUERY_FAILED, result, response_code)
		return
	var validation_result := _validate_file(task)
	if validation_result != OK:
		_fail_or_retry(task_id, validation_result, result, response_code)
		return
	var commit_result := _commit_file(task.temp_path, task.target_path)
	if commit_result != OK:
		_fail_or_retry(task_id, commit_result, result, response_code, false)
		return
	task.state = TaskState.COMPLETED
	task.error = OK
	_record_finished(task_id)
	task_completed.emit(task_id, task.target_path)
	_dispatch()


func _fail_or_retry(
	task_id: int,
	error: Error,
	result: int,
	response_code: int,
	allow_retry := true,
) -> void:
	var backend := _active.get(task_id) as GFDownloadBackend
	_active.erase(task_id)
	if backend != null:
		backend.cancel()
		_dispose_backend(backend)
	var task: Dictionary = _tasks[task_id]
	_remove_file(task.temp_path)
	task.error = error
	task.response_code = response_code
	if allow_retry and int(task.attempts) <= _settings.retry_count and _is_retryable(result, response_code, error):
		task.state = TaskState.QUEUED
		_queue.append(task_id)
		task_retry_scheduled.emit(task_id, int(task.attempts) + 1, error, response_code)
		return
	task.state = TaskState.FAILED
	_record_finished(task_id)
	task_failed.emit(task_id, error, response_code)
	_dispatch()


func _record_finished(task_id: int) -> void:
	_finished_order.append(task_id)
	while _finished_order.size() > _settings.max_finished_tasks:
		_tasks.erase(_finished_order.pop_front())


func _validate_file(task: Dictionary) -> Error:
	if not FileAccess.file_exists(task.temp_path):
		return ERR_FILE_CANT_READ
	var file := FileAccess.open(task.temp_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var actual_size := file.get_length()
	file = null
	if int(task.expected_size) >= 0 and actual_size != int(task.expected_size):
		return ERR_FILE_CORRUPT
	if not str(task.expected_sha256).is_empty():
		var actual_hash := FileAccess.get_sha256(task.temp_path).to_lower()
		if actual_hash != task.expected_sha256:
			return ERR_FILE_CORRUPT
	return OK


func _commit_file(temp_path: String, target_path: String) -> Error:
	var backup_path := "%s.bak" % target_path
	_remove_file(backup_path)
	var had_target := FileAccess.file_exists(target_path)
	if had_target:
		var backup_result := DirAccess.rename_absolute(target_path, backup_path)
		if backup_result != OK:
			return backup_result
	var replace_result := DirAccess.rename_absolute(temp_path, target_path)
	if replace_result != OK:
		if had_target:
			DirAccess.rename_absolute(backup_path, target_path)
		return replace_result
	_remove_file(backup_path)
	return OK


func _is_retryable(result: int, response_code: int, error: Error) -> bool:
	if error == ERR_FILE_CORRUPT:
		return true
	if response_code > 0:
		return _settings.retry_http_status_codes.has(response_code)
	if error in [
		ERR_FILE_CANT_WRITE,
		ERR_FILE_NO_PERMISSION,
		ERR_INVALID_PARAMETER,
		ERR_CANT_CREATE,
		ERR_BUG,
		ERR_OUT_OF_MEMORY,
	]:
		return false
	return result != HTTPRequest.RESULT_SUCCESS or error != OK


func _result_to_error(result: int) -> Error:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return ERR_TIMEOUT
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return ERR_FILE_CANT_WRITE
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return ERR_OUT_OF_MEMORY
		_:
			return ERR_CANT_CONNECT


func _create_backend() -> GFDownloadBackend:
	if not _backend_factory.is_valid():
		return GFHTTPDownloadBackend.new()
	var created: Variant = _backend_factory.call()
	return created as GFDownloadBackend if created is GFDownloadBackend else null


func _dispose_backend(backend: GFDownloadBackend) -> void:
	if is_instance_valid(backend):
		backend.queue_free()


func _normalize_relative_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty() or normalized.is_absolute_path() or normalized.contains(":"):
		return ""
	for component: String in normalized.split("/", false):
		if component == "..":
			return ""
	normalized = normalized.simplify_path()
	return "" if normalized in ["", ".", ".."] or normalized.begins_with("../") else normalized


func _target_in_use(target_path: String) -> bool:
	for task: Dictionary in _tasks.values():
		if task.target_path == target_path and int(task.state) in [TaskState.QUEUED, TaskState.RUNNING]:
			return true
	return false


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fail_id(message: String) -> int:
	last_error = message
	return 0
