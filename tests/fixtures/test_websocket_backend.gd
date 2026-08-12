class_name GFTestWebSocketBackend
extends GFWebSocketBackend

var plan: Dictionary = {}
var configured: Dictionary = {}
var state := WebSocketPeer.STATE_CLOSED
var incoming: Array[Dictionary] = []
var sent: Array[Dictionary] = []
var buffered_bytes := 0
var requested_close := false
var requested_close_code := 0
var requested_close_reason := ""
var connected_url := ""


func setup(value: Dictionary) -> GFTestWebSocketBackend:
	plan = value
	incoming.clear()
	incoming.assign((plan.get("incoming", []) as Array).duplicate(true))
	buffered_bytes = int(plan.get("buffered_bytes", 0))
	return self


func configure(
	headers: PackedStringArray,
	protocols: PackedStringArray,
	heartbeat_interval: float,
	inbound_buffer_size: int,
	outbound_buffer_size: int,
	max_queued_packets: int,
) -> void:
	configured = {
		"headers": headers.duplicate(),
		"protocols": protocols.duplicate(),
		"heartbeat_interval": heartbeat_interval,
		"inbound_buffer_size": inbound_buffer_size,
		"outbound_buffer_size": outbound_buffer_size,
		"max_queued_packets": max_queued_packets,
	}


func connect_to_url(url: String, _tls_options: TLSOptions = null) -> Error:
	connected_url = url
	var result := int(plan.get("connect_error", OK)) as Error
	state = WebSocketPeer.STATE_CONNECTING if result == OK else WebSocketPeer.STATE_CLOSED
	return result


func poll() -> void:
	var states := plan.get("poll_states", []) as Array
	if not states.is_empty():
		state = int(states.pop_front())


func ready_state() -> int:
	return state


func available_packet_count() -> int:
	return incoming.size()


func get_packet() -> Dictionary:
	return incoming.pop_front() if not incoming.is_empty() else {
		"error": ERR_UNAVAILABLE,
		"data": PackedByteArray(),
		"is_text": false,
	}


func send(data: PackedByteArray, write_mode := WebSocketPeer.WRITE_MODE_BINARY) -> Error:
	var result := int(plan.get("send_error", OK)) as Error
	if result == OK:
		sent.append({"data": data.duplicate(), "write_mode": write_mode})
		buffered_bytes += data.size()
	return result


func close(code := 1000, reason := "") -> void:
	requested_close = true
	requested_close_code = code
	requested_close_reason = reason
	state = WebSocketPeer.STATE_CLOSED if bool(plan.get("close_immediately", true)) else WebSocketPeer.STATE_CLOSING


func close_code() -> int:
	return int(plan.get("close_code", requested_close_code))


func close_reason() -> String:
	return str(plan.get("close_reason", requested_close_reason))


func outbound_buffered_amount() -> int:
	return buffered_bytes


func selected_protocol() -> String:
	return str(plan.get("selected_protocol", ""))
