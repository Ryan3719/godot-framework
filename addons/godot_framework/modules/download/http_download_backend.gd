class_name GFHTTPDownloadBackend
extends GFDownloadBackend

var _request: HTTPRequest
var _active := false


func start(
	url: String,
	temp_path: String,
	headers: PackedStringArray,
	timeout_seconds: float,
	use_threads: bool,
	max_redirects: int,
	body_size_limit_bytes: int,
) -> Error:
	if _active:
		return ERR_BUSY
	_request = HTTPRequest.new()
	_request.download_file = temp_path
	_request.timeout = timeout_seconds
	_request.use_threads = use_threads
	_request.max_redirects = max_redirects
	_request.body_size_limit = body_size_limit_bytes
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_active = true
	var result := _request.request(url, headers, HTTPClient.METHOD_GET)
	if result != OK:
		_active = false
		_request.cancel_request()
	return result


func cancel() -> void:
	_active = false
	if is_instance_valid(_request):
		_request.cancel_request()


func downloaded_bytes() -> int:
	return _request.get_downloaded_bytes() if is_instance_valid(_request) else 0


func body_size() -> int:
	return _request.get_body_size() if is_instance_valid(_request) else -1


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	_body: PackedByteArray,
) -> void:
	if not _active:
		return
	_active = false
	completed.emit(result, response_code, headers)
