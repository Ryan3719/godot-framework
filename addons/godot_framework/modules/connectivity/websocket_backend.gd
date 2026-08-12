class_name GFWebSocketBackend
extends RefCounted


func configure(
	_headers: PackedStringArray,
	_protocols: PackedStringArray,
	_heartbeat_interval: float,
	_inbound_buffer_size: int,
	_outbound_buffer_size: int,
	_max_queued_packets: int,
) -> void:
	pass


func connect_to_url(_url: String, _tls_options: TLSOptions = null) -> Error:
	return ERR_UNAVAILABLE


func poll() -> void:
	pass


func ready_state() -> int:
	return WebSocketPeer.STATE_CLOSED


func available_packet_count() -> int:
	return 0


func get_packet() -> Dictionary:
	return {"error": ERR_UNAVAILABLE, "data": PackedByteArray(), "is_text": false}


func send(_data: PackedByteArray, _write_mode := WebSocketPeer.WRITE_MODE_BINARY) -> Error:
	return ERR_UNAVAILABLE


func close(_code := 1000, _reason := "") -> void:
	pass


func close_code() -> int:
	return -1


func close_reason() -> String:
	return ""


func outbound_buffered_amount() -> int:
	return 0


func selected_protocol() -> String:
	return ""
