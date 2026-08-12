class_name GFGodotWebSocketBackend
extends GFWebSocketBackend

var _peer: WebSocketPeer
var _headers := PackedStringArray()
var _protocols := PackedStringArray()
var _heartbeat_interval := 0.0
var _inbound_buffer_size := 65535
var _outbound_buffer_size := 65535
var _max_queued_packets := 4096


func configure(
	headers: PackedStringArray,
	protocols: PackedStringArray,
	heartbeat_interval: float,
	inbound_buffer_size: int,
	outbound_buffer_size: int,
	max_queued_packets: int,
) -> void:
	_headers = headers.duplicate()
	_protocols = protocols.duplicate()
	_heartbeat_interval = heartbeat_interval
	_inbound_buffer_size = inbound_buffer_size
	_outbound_buffer_size = outbound_buffer_size
	_max_queued_packets = max_queued_packets


func connect_to_url(url: String, tls_options: TLSOptions = null) -> Error:
	_peer = WebSocketPeer.new()
	_peer.handshake_headers = _headers
	_peer.supported_protocols = _protocols
	_peer.heartbeat_interval = _heartbeat_interval
	_peer.inbound_buffer_size = _inbound_buffer_size
	_peer.outbound_buffer_size = _outbound_buffer_size
	_peer.max_queued_packets = _max_queued_packets
	return _peer.connect_to_url(url, tls_options)


func poll() -> void:
	if _peer != null:
		_peer.poll()


func ready_state() -> int:
	return _peer.get_ready_state() if _peer != null else WebSocketPeer.STATE_CLOSED


func available_packet_count() -> int:
	return _peer.get_available_packet_count() if _peer != null else 0


func get_packet() -> Dictionary:
	if _peer == null:
		return {"error": ERR_UNCONFIGURED, "data": PackedByteArray(), "is_text": false}
	var data := _peer.get_packet()
	return {
		"error": _peer.get_packet_error(),
		"data": data,
		"is_text": _peer.was_string_packet(),
	}


func send(data: PackedByteArray, write_mode := WebSocketPeer.WRITE_MODE_BINARY) -> Error:
	return _peer.send(data, write_mode) if _peer != null else ERR_UNCONFIGURED


func close(code := 1000, reason := "") -> void:
	if _peer != null:
		_peer.close(code, reason)


func close_code() -> int:
	return _peer.get_close_code() if _peer != null else -1


func close_reason() -> String:
	return _peer.get_close_reason() if _peer != null else ""


func outbound_buffered_amount() -> int:
	return _peer.get_current_outbound_buffered_amount() if _peer != null else 0


func selected_protocol() -> String:
	return _peer.get_selected_protocol() if _peer != null else ""
