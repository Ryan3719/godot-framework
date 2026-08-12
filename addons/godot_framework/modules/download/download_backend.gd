class_name GFDownloadBackend
extends Node

signal completed(result: int, response_code: int, headers: PackedStringArray)


func start(
	_url: String,
	_temp_path: String,
	_headers: PackedStringArray,
	_timeout_seconds: float,
	_use_threads: bool,
	_max_redirects: int,
	_body_size_limit_bytes: int,
) -> Error:
	return ERR_UNAVAILABLE


func cancel() -> void:
	pass


func downloaded_bytes() -> int:
	return 0


func body_size() -> int:
	return -1
