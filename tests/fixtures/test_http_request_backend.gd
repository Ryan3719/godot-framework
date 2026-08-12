class_name GFTestHTTPRequestBackend
extends GFHTTPRequestBackend

var plan: Dictionary = {}
var started := false
var cancelled := false
var captured: Dictionary = {}


func setup(value: Dictionary) -> GFTestHTTPRequestBackend:
	plan = value
	return self


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
	started = true
	captured = {
		"url": url,
		"headers": headers.duplicate(),
		"method": method,
		"body": body.duplicate(),
		"timeout_seconds": timeout_seconds,
		"use_threads": use_threads,
		"max_redirects": max_redirects,
		"body_size_limit_bytes": body_size_limit_bytes,
		"tls_options": tls_options,
	}
	var start_error := int(plan.get("start_error", OK)) as Error
	if start_error != OK:
		return start_error
	if bool(plan.get("auto_complete", false)):
		call_deferred("complete")
	return OK


func cancel() -> void:
	cancelled = true


func complete() -> void:
	if cancelled:
		return
	completed.emit(
		int(plan.get("result", HTTPRequest.RESULT_SUCCESS)),
		int(plan.get("response_code", 200)),
		plan.get("headers", PackedStringArray()) as PackedStringArray,
		plan.get("body", PackedByteArray()) as PackedByteArray,
	)
