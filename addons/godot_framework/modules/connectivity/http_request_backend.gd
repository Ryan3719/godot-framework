class_name GFHTTPRequestBackend
extends Node

signal completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)


func start(
	_url: String,
	_headers: PackedStringArray,
	_method: int,
	_body: PackedByteArray,
	_timeout_seconds: float,
	_use_threads: bool,
	_max_redirects: int,
	_body_size_limit_bytes: int,
	_tls_options: TLSOptions,
) -> Error:
	return ERR_UNAVAILABLE


func cancel() -> void:
	pass
