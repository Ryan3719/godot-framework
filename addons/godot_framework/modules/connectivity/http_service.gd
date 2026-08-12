class_name GFHTTPService
extends RefCounted

signal request_queued(request_id: int, tag: StringName)
signal request_started(request_id: int, tag: StringName)
signal request_completed(
	request_id: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	tag: StringName,
)
signal request_failed(request_id: int, error: Error, transport_result: int, response_code: int, tag: StringName)
signal request_cancelled(request_id: int, tag: StringName)

enum TaskState {
	QUEUED,
	RUNNING,
	COMPLETED,
	FAILED,
	CANCELLED,
}

var last_error := ""

var _root: Node
var _settings: GFConnectivitySettings
var _backend_factory: Callable
var _queue: Array[int] = []
var _tasks: Dictionary = {}
var _active: Dictionary = {}
var _next_id := 1
var _queued_body_bytes := 0
var _dispatching := false
var _closed := false


func _init(root: Node, settings: GFConnectivitySettings, backend_factory := Callable()) -> void:
	_root = root
	_settings = settings
	_backend_factory = backend_factory


func request(
	url: String,
	method := HTTPClient.METHOD_GET,
	headers := PackedStringArray(),
	body := PackedByteArray(),
	timeout_seconds := -1.0,
	tag := StringName(),
	tls_options: TLSOptions = null,
) -> int:
	last_error = ""
	if _closed or _settings == null:
		return _fail_id("HTTP service is shut down.")
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return _fail_id("HTTP URL must use http:// or https://.")
	if method < 0 or method >= HTTPClient.METHOD_MAX:
		return _fail_id("HTTP method is invalid.")
	if timeout_seconds < -1.0:
		return _fail_id("HTTP timeout cannot be less than -1.")
	if _tasks_in_flight() >= _settings.http_max_in_flight_requests:
		return _fail_id("HTTP request queue is full.")
	if body.size() > _settings.http_request_body_limit_bytes:
		return _fail_id("HTTP request body exceeds the configured limit.")
	if _queued_body_bytes + body.size() > _settings.http_max_queued_body_bytes:
		return _fail_id("HTTP queued request bodies exceed the configured byte limit.")

	var request_id := _next_id
	_next_id += 1
	_tasks[request_id] = {
		"id": request_id,
		"url": url,
		"method": method,
		"headers": headers.duplicate(),
		"body": body.duplicate(),
		"timeout_seconds": _settings.http_timeout_seconds if timeout_seconds < 0.0 else timeout_seconds,
		"elapsed_seconds": 0.0,
		"tag": tag,
		"tls_options": tls_options,
		"state": TaskState.QUEUED,
		"error": OK,
		"transport_result": -1,
		"response_code": 0,
		"response_headers": PackedStringArray(),
		"response_body": PackedByteArray(),
	}
	_queue.append(request_id)
	_queued_body_bytes += body.size()
	request_queued.emit(request_id, tag)
	_dispatch()
	return request_id


func update(delta: float) -> void:
	for request_id: int in _active.keys():
		var backend := _active.get(request_id) as GFHTTPRequestBackend
		if backend == null or not is_instance_valid(backend):
			_finish_failure(request_id, ERR_BUG, -1, 0)
			continue
		var task: Dictionary = _tasks[request_id]
		var timeout := float(task.timeout_seconds)
		if timeout <= 0.0:
			continue
		task.elapsed_seconds = float(task.elapsed_seconds) + maxf(delta, 0.0)
		if float(task.elapsed_seconds) >= timeout:
			backend.cancel()
			_finish_failure(request_id, ERR_TIMEOUT, HTTPRequest.RESULT_TIMEOUT, 0)
	_dispatch()


func cancel(request_id: int) -> bool:
	if not _tasks.has(request_id):
		return false
	var task: Dictionary = _tasks[request_id]
	if int(task.state) not in [TaskState.QUEUED, TaskState.RUNNING]:
		return false
	if int(task.state) == TaskState.QUEUED:
		_queue.erase(request_id)
		_queued_body_bytes -= (task.body as PackedByteArray).size()
	var backend := _active.get(request_id) as GFHTTPRequestBackend
	_active.erase(request_id)
	if backend != null and is_instance_valid(backend):
		backend.cancel()
		_dispose_backend(backend)
	task.state = TaskState.CANCELLED
	task.body = PackedByteArray()
	task.tls_options = null
	request_cancelled.emit(request_id, task.tag)
	_dispatch()
	return true


func cancel_tag(tag: StringName) -> int:
	var cancelled := 0
	for request_id: int in _tasks.keys():
		if (_tasks[request_id] as Dictionary).tag == tag and cancel(request_id):
			cancelled += 1
	return cancelled


func task_info(request_id: int) -> Dictionary:
	return (_tasks[request_id] as Dictionary).duplicate() if _tasks.has(request_id) else {}


func task_state(request_id: int) -> int:
	return int((_tasks[request_id] as Dictionary).state) if _tasks.has(request_id) else -1


func queued_count() -> int:
	return _queue.size()


func active_count() -> int:
	return _active.size()


func in_flight_count() -> int:
	return _tasks_in_flight()


func clear_finished() -> int:
	var removed := 0
	for request_id: int in _tasks.keys():
		if int((_tasks[request_id] as Dictionary).state) in [TaskState.COMPLETED, TaskState.FAILED, TaskState.CANCELLED]:
			_tasks.erase(request_id)
			removed += 1
	return removed


func shutdown() -> void:
	if _closed:
		return
	_closed = true
	for request_id: int in _tasks.keys():
		if int((_tasks[request_id] as Dictionary).state) in [TaskState.QUEUED, TaskState.RUNNING]:
			cancel(request_id)
	_queue.clear()
	_active.clear()
	_tasks.clear()
	_queued_body_bytes = 0
	_backend_factory = Callable()
	_settings = null
	_root = null


func _dispatch() -> void:
	if _dispatching or _closed or _settings == null:
		return
	_dispatching = true
	while _active.size() < _settings.http_max_concurrent and not _queue.is_empty():
		var request_id := _queue.pop_front()
		if task_state(request_id) != TaskState.QUEUED:
			continue
		_start_request(request_id)
	_dispatching = false


func _start_request(request_id: int) -> void:
	var task: Dictionary = _tasks[request_id]
	_queued_body_bytes -= (task.body as PackedByteArray).size()
	task.state = TaskState.RUNNING
	var backend := _create_backend()
	if backend == null:
		_finish_failure(request_id, ERR_CANT_CREATE, -1, 0)
		return
	_root.add_child(backend)
	backend.completed.connect(_on_backend_completed.bind(request_id), CONNECT_ONE_SHOT)
	_active[request_id] = backend
	var result := backend.start(
		task.url,
		task.headers,
		int(task.method),
		task.body,
		float(task.timeout_seconds),
		_settings.http_use_threads,
		_settings.http_max_redirects,
		_settings.http_response_body_limit_bytes,
		task.tls_options,
	)
	if result != OK:
		_finish_failure(request_id, result, -1, 0)
		return
	if task_state(request_id) == TaskState.RUNNING:
		request_started.emit(request_id, task.tag)


func _on_backend_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	request_id: int,
) -> void:
	if task_state(request_id) != TaskState.RUNNING:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_failure(request_id, _result_to_error(result), result, response_code)
		return
	if _settings.http_response_body_limit_bytes >= 0 and body.size() > _settings.http_response_body_limit_bytes:
		_finish_failure(request_id, ERR_OUT_OF_MEMORY, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, response_code)
		return
	var backend := _active.get(request_id) as GFHTTPRequestBackend
	_active.erase(request_id)
	if backend != null:
		_dispose_backend(backend)
	var task: Dictionary = _tasks[request_id]
	task.state = TaskState.COMPLETED
	task.transport_result = result
	task.response_code = response_code
	task.response_headers = headers
	task.response_body = body
	task.body = PackedByteArray()
	task.tls_options = null
	request_completed.emit(request_id, response_code, headers, body, task.tag)
	_dispatch()


func _finish_failure(request_id: int, error: Error, result: int, response_code: int) -> void:
	if not _tasks.has(request_id):
		return
	var backend := _active.get(request_id) as GFHTTPRequestBackend
	_active.erase(request_id)
	if backend != null:
		backend.cancel()
		_dispose_backend(backend)
	var task: Dictionary = _tasks[request_id]
	if int(task.state) == TaskState.QUEUED:
		_queue.erase(request_id)
		_queued_body_bytes -= (task.body as PackedByteArray).size()
	task.state = TaskState.FAILED
	task.error = error
	task.transport_result = result
	task.response_code = response_code
	task.body = PackedByteArray()
	task.tls_options = null
	request_failed.emit(request_id, error, result, response_code, task.tag)
	_dispatch()


func _create_backend() -> GFHTTPRequestBackend:
	if not _backend_factory.is_valid():
		return GFGodotHTTPRequestBackend.new()
	var created: Variant = _backend_factory.call()
	return created as GFHTTPRequestBackend if created is GFHTTPRequestBackend else null


func _dispose_backend(backend: GFHTTPRequestBackend) -> void:
	if is_instance_valid(backend):
		backend.queue_free()


func _tasks_in_flight() -> int:
	return _queue.size() + _active.size()


func _result_to_error(result: int) -> Error:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return ERR_TIMEOUT
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return ERR_OUT_OF_MEMORY
		HTTPRequest.RESULT_CANT_RESOLVE:
			return ERR_CANT_RESOLVE
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return ERR_CANT_CONNECT
		_:
			return ERR_QUERY_FAILED


func _fail_id(message: String) -> int:
	last_error = message
	return 0
