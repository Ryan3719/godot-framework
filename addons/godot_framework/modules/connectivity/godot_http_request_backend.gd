class_name GFGodotHTTPRequestBackend
extends GFHTTPRequestBackend

var _request: HTTPRequest
var _active := false


func start(
	url: String,
	headers: PackedStringArray,
	method: int,
	body: PackedByteArray,
	timeout_seconds: float,
	use_threads: bool,
	max_redirects: int,
	body_size_limit_bytes: int,
	tls_options: TLSOptions,
) -> Error:
	if _active:
		return ERR_BUSY
	_request = HTTPRequest.new()
	_request.timeout = timeout_seconds
	_request.use_threads = use_threads
	_request.max_redirects = max_redirects
	_request.body_size_limit = body_size_limit_bytes
	if tls_options != null:
		_request.set_tls_options(tls_options)
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_active = true
	var result := _request.request_raw(url, headers, method, body)
	if result != OK:
		_active = false
		_request.cancel_request()
	return result


func cancel() -> void:
	_active = false
	if is_instance_valid(_request):
		_request.cancel_request()


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if not _active:
		return
	_active = false
	completed.emit(result, response_code, headers, body)
