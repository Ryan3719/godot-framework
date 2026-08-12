extends Node

var _service: GFConnectivityService
var _http_done := false
var _http_valid := false
var _websocket_connected := false
var _websocket_text_valid := false
var _websocket_binary_valid := false
var _sent := false
var _failure := ""


func _ready() -> void:
	var arguments := _parse_arguments()
	var http_url := str(arguments.get("http-url", ""))
	var websocket_url := str(arguments.get("websocket-url", ""))
	if http_url.is_empty() or websocket_url.is_empty():
		_finish_failure("Integration URLs are required.")
		return

	var settings := GFConnectivitySettings.new()
	settings.root_name = "ConnectivityIntegration"
	settings.http_timeout_seconds = 5.0
	settings.http_response_body_limit_bytes = 1024
	var channel := GFWebSocketChannelDefinition.new()
	channel.channel_id = &"echo"
	channel.url = websocket_url
	channel.supported_protocols = PackedStringArray(["gf-test"])
	channel.connect_timeout_seconds = 5.0
	channel.heartbeat_interval_seconds = 0.25
	channel.max_packet_bytes = 1024
	settings.websocket_channels = [channel]
	_service = GFConnectivityService.new(self, settings)
	_service.http.request_completed.connect(_on_http_completed)
	_service.http.request_failed.connect(_on_http_failed)
	_service.websockets.channel_connected.connect(_on_websocket_connected)
	_service.websockets.packet_received.connect(_on_websocket_packet)
	_service.websockets.channel_error.connect(_on_websocket_error)

	var payload := PackedByteArray([0, 1, 2, 3, 255])
	if _service.http.request(
		http_url,
		HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/octet-stream"]),
		payload,
	) == 0:
		_finish_failure("Real HTTP request could not be queued.")
		return
	if _service.websockets.connect_channel(&"echo") != OK:
		_finish_failure("Real WebSocket connection could not start.")
		return

	for _index in range(600):
		_service.update(1.0 / 60.0)
		if _websocket_connected and not _sent:
			_sent = true
			if _service.websockets.send_text(&"echo", "framework") != OK:
				_failure = "Real WebSocket text send failed."
			elif _service.websockets.send(&"echo", PackedByteArray([5, 4, 3, 2, 1])) != OK:
				_failure = "Real WebSocket binary send failed."
		if _http_done and _websocket_text_valid and _websocket_binary_valid:
			break
		await get_tree().process_frame

	if not _failure.is_empty():
		_finish_failure(_failure)
		return
	if not _http_done or not _http_valid:
		_finish_failure("Real HTTP adapter did not return the expected response.")
		return
	if not _websocket_text_valid or not _websocket_binary_valid:
		_finish_failure("Real WebSocket adapter did not preserve text and binary frames.")
		return
	_service.websockets.disconnect_channel(&"echo", 1000, "complete")
	for _index in range(120):
		_service.update(1.0 / 60.0)
		if _service.websockets.state(&"echo") == GFWebSocketService.ChannelState.DISCONNECTED:
			break
		await get_tree().process_frame
	if _service.websockets.state(&"echo") != GFWebSocketService.ChannelState.DISCONNECTED:
		_finish_failure("Real WebSocket adapter did not close cleanly.")
		return
	print("[CONNECTIVITY TEST] PASS: real HTTP and WebSocket adapters")
	await _shutdown_and_quit(0)


func _on_http_completed(
	_request_id: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	_tag: StringName,
) -> void:
	_http_done = true
	_http_valid = response_code == 201 and body == PackedByteArray([0, 1, 2, 3, 255]) and _has_header(headers, "x-gf-test", "echo")


func _on_http_failed(
	_request_id: int,
	error: Error,
	_transport_result: int,
	_response_code: int,
	_tag: StringName,
) -> void:
	_http_done = true
	_failure = "Real HTTP adapter failed with error %d." % error


func _on_websocket_connected(channel_id: StringName, selected_protocol: String) -> void:
	if channel_id == &"echo":
		_websocket_connected = selected_protocol == "gf-test"
		if not _websocket_connected:
			_failure = "Real WebSocket adapter did not negotiate the requested protocol."


func _on_websocket_packet(channel_id: StringName, data: PackedByteArray, is_text: bool) -> void:
	if channel_id != &"echo":
		return
	if is_text and data.get_string_from_utf8() == "framework":
		_websocket_text_valid = true
	elif not is_text and data == PackedByteArray([5, 4, 3, 2, 1]):
		_websocket_binary_valid = true


func _on_websocket_error(channel_id: StringName, error: Error) -> void:
	if channel_id == &"echo":
		_failure = "Real WebSocket adapter failed with error %d." % error


func _parse_arguments() -> Dictionary:
	var parsed := {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		parsed[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return parsed


func _has_header(headers: PackedStringArray, expected_name: String, expected_value: String) -> bool:
	for header: String in headers:
		var separator := header.find(":")
		if separator < 0:
			continue
		if header.left(separator).strip_edges().to_lower() == expected_name \
		and header.substr(separator + 1).strip_edges().to_lower() == expected_value:
			return true
	return false


func _finish_failure(message: String) -> void:
	push_error("[CONNECTIVITY TEST] %s" % message)
	call_deferred("_shutdown_and_quit", 1)


func _shutdown_and_quit(exit_code: int) -> void:
	if _service != null:
		_service.shutdown()
	await get_tree().process_frame
	get_tree().quit(exit_code)
