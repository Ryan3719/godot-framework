class_name GFWebSocketService
extends RefCounted

signal channel_registered(channel_id: StringName)
signal channel_connecting(channel_id: StringName, reconnect_attempt: int)
signal channel_connected(channel_id: StringName, selected_protocol: String)
signal channel_disconnected(channel_id: StringName, code: int, reason: String, requested: bool)
signal reconnect_scheduled(channel_id: StringName, attempt: int, delay_seconds: float)
signal reconnect_exhausted(channel_id: StringName, attempts: int)
signal packet_received(channel_id: StringName, data: PackedByteArray, is_text: bool)
signal packet_sent(channel_id: StringName, bytes: int, is_text: bool)
signal send_blocked(channel_id: StringName, buffered_bytes: int)
signal channel_writable(channel_id: StringName)
signal channel_error(channel_id: StringName, error: Error)

enum ChannelState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	CLOSING,
	RECONNECT_WAIT,
}

var last_error := ""

var _backend_factory: Callable
var _channels: Dictionary = {}
var _closed := false


func _init(backend_factory := Callable()) -> void:
	_backend_factory = backend_factory


func register_channel(definition: GFWebSocketChannelDefinition, replace := false) -> Error:
	if _closed:
		return _fail(ERR_UNCONFIGURED, "WebSocket service is shut down.")
	if definition == null:
		return _fail(ERR_INVALID_PARAMETER, "Cannot register a null WebSocket channel.")
	var validation := definition.validate()
	if not validation.is_empty():
		return _fail(ERR_INVALID_DATA, validation)
	if _channels.has(definition.channel_id):
		if not replace:
			return _fail(ERR_ALREADY_EXISTS, "Duplicate WebSocket channel '%s'." % definition.channel_id)
		if state(definition.channel_id) != ChannelState.DISCONNECTED:
			return _fail(ERR_ALREADY_IN_USE, "Cannot replace an active WebSocket channel.")
	var owned_definition := definition.duplicate(true) as GFWebSocketChannelDefinition
	_channels[definition.channel_id] = {
		"definition": owned_definition,
		"backend": null,
		"state": ChannelState.DISCONNECTED,
		"requested_close": false,
		"connect_elapsed": 0.0,
		"close_elapsed": 0.0,
		"reconnect_attempts": 0,
		"reconnect_remaining": 0.0,
		"blocked": false,
		"tls_options": null,
	}
	channel_registered.emit(definition.channel_id)
	return OK


func unregister_channel(channel_id: StringName) -> bool:
	if not _channels.has(channel_id) or state(channel_id) != ChannelState.DISCONNECTED:
		return false
	_channels.erase(channel_id)
	return true


func connect_channel(channel_id: StringName, tls_options: TLSOptions = null) -> Error:
	if _closed:
		return ERR_UNCONFIGURED
	var record := _record(channel_id)
	if record.is_empty():
		return _fail(ERR_DOES_NOT_EXIST, "Unknown WebSocket channel '%s'." % channel_id)
	if int(record.state) not in [ChannelState.DISCONNECTED, ChannelState.RECONNECT_WAIT]:
		return _fail(ERR_ALREADY_IN_USE, "WebSocket channel '%s' is already active." % channel_id)
	record.requested_close = false
	record.reconnect_attempts = 0
	record.reconnect_remaining = 0.0
	record.tls_options = tls_options
	return _begin_connect(channel_id, record)


func disconnect_channel(channel_id: StringName, code := 1000, reason := "") -> Error:
	var record := _record(channel_id)
	if record.is_empty():
		return ERR_DOES_NOT_EXIST
	if code != -1 and (code < 1000 or code >= 5000):
		return ERR_INVALID_PARAMETER
	if reason.to_utf8_buffer().size() > 123:
		return ERR_INVALID_PARAMETER
	if int(record.state) == ChannelState.DISCONNECTED:
		return ERR_ALREADY_IN_USE
	record.requested_close = true
	record.reconnect_remaining = 0.0
	record.close_elapsed = 0.0
	var backend := record.backend as GFWebSocketBackend
	if backend == null or int(record.state) == ChannelState.RECONNECT_WAIT:
		record.backend = null
		record.state = ChannelState.DISCONNECTED
		channel_disconnected.emit(channel_id, code, reason, true)
		return OK
	record.state = ChannelState.CLOSING
	backend.close(code, reason)
	return OK


func send(channel_id: StringName, data: PackedByteArray, is_text := false) -> Error:
	var record := _record(channel_id)
	if record.is_empty():
		return ERR_DOES_NOT_EXIST
	if int(record.state) != ChannelState.CONNECTED:
		return ERR_UNCONFIGURED
	var definition := record.definition as GFWebSocketChannelDefinition
	if data.size() > definition.max_packet_bytes:
		return ERR_OUT_OF_MEMORY
	var backend := record.backend as GFWebSocketBackend
	var buffered := backend.outbound_buffered_amount()
	if bool(record.blocked):
		return ERR_BUSY
	if buffered + data.size() > definition.send_high_watermark_bytes:
		record.blocked = true
		send_blocked.emit(channel_id, buffered)
		return ERR_BUSY
	var result := backend.send(
		data,
		WebSocketPeer.WRITE_MODE_TEXT if is_text else WebSocketPeer.WRITE_MODE_BINARY,
	)
	if result == OK:
		packet_sent.emit(channel_id, data.size(), is_text)
	else:
		channel_error.emit(channel_id, result)
	return result


func send_text(channel_id: StringName, text: String) -> Error:
	return send(channel_id, text.to_utf8_buffer(), true)


func update(delta: float) -> void:
	for channel_id: StringName in _channels.keys():
		var record: Dictionary = _channels[channel_id]
		match int(record.state):
			ChannelState.RECONNECT_WAIT:
				record.reconnect_remaining = maxf(float(record.reconnect_remaining) - maxf(delta, 0.0), 0.0)
				if float(record.reconnect_remaining) <= 0.0:
					_begin_connect(channel_id, record)
			ChannelState.CONNECTING, ChannelState.CONNECTED, ChannelState.CLOSING:
				_poll_channel(channel_id, record, delta)


func start_auto_connect() -> Error:
	for channel_id: StringName in _channels.keys():
		var definition := (_channels[channel_id] as Dictionary).definition as GFWebSocketChannelDefinition
		if definition.auto_connect:
			connect_channel(channel_id)
	return OK


func state(channel_id: StringName) -> int:
	return int((_channels[channel_id] as Dictionary).state) if _channels.has(channel_id) else -1


func channel_info(channel_id: StringName) -> Dictionary:
	if not _channels.has(channel_id):
		return {}
	var record: Dictionary = _channels[channel_id]
	var backend := record.backend as GFWebSocketBackend
	return {
		"state": record.state,
		"reconnect_attempts": record.reconnect_attempts,
		"reconnect_remaining": record.reconnect_remaining,
		"buffered_bytes": backend.outbound_buffered_amount() if backend != null else 0,
		"blocked": record.blocked,
	}


func shutdown() -> void:
	if _closed:
		return
	_closed = true
	for channel_id: StringName in _channels.keys():
		var record: Dictionary = _channels[channel_id]
		var backend := record.backend as GFWebSocketBackend
		if backend != null:
			backend.close(-1, "")
	_channels.clear()
	_backend_factory = Callable()


func _begin_connect(channel_id: StringName, record: Dictionary) -> Error:
	var definition := record.definition as GFWebSocketChannelDefinition
	var backend := _create_backend(channel_id)
	if backend == null:
		_handle_disconnect(channel_id, record, ERR_CANT_CREATE, -1, "Backend creation failed.")
		return ERR_CANT_CREATE
	backend.configure(
		definition.handshake_headers,
		definition.supported_protocols,
		definition.heartbeat_interval_seconds,
		definition.inbound_buffer_size,
		definition.outbound_buffer_size,
		definition.max_queued_packets,
	)
	record.backend = backend
	record.state = ChannelState.CONNECTING
	record.connect_elapsed = 0.0
	record.blocked = false
	var result := backend.connect_to_url(definition.url, record.tls_options)
	if result != OK:
		_handle_disconnect(channel_id, record, result, -1, "Connection could not start.")
		return result
	channel_connecting.emit(channel_id, int(record.reconnect_attempts))
	return OK


func _poll_channel(channel_id: StringName, record: Dictionary, delta: float) -> void:
	var backend := record.backend as GFWebSocketBackend
	if backend == null:
		_handle_disconnect(channel_id, record, ERR_BUG, -1, "WebSocket backend disappeared.")
		return
	backend.poll()
	var peer_state := backend.ready_state()
	if int(record.state) == ChannelState.CONNECTING:
		record.connect_elapsed = float(record.connect_elapsed) + maxf(delta, 0.0)
		var definition := record.definition as GFWebSocketChannelDefinition
		if peer_state == WebSocketPeer.STATE_OPEN:
			record.state = ChannelState.CONNECTED
			record.connect_elapsed = 0.0
			record.reconnect_attempts = 0
			channel_connected.emit(channel_id, backend.selected_protocol())
		elif definition.connect_timeout_seconds > 0.0 and float(record.connect_elapsed) >= definition.connect_timeout_seconds:
			backend.close(-1, "")
			_handle_disconnect(channel_id, record, ERR_TIMEOUT, -1, "Connection timed out.")
			return
	elif int(record.state) == ChannelState.CLOSING:
		record.close_elapsed = float(record.close_elapsed) + maxf(delta, 0.0)
		var definition := record.definition as GFWebSocketChannelDefinition
		if definition.close_timeout_seconds > 0.0 and float(record.close_elapsed) >= definition.close_timeout_seconds:
			backend.close(-1, "")
			_handle_disconnect(channel_id, record, ERR_TIMEOUT, -1, "Close handshake timed out.")
			return
	if peer_state == WebSocketPeer.STATE_OPEN and int(record.state) == ChannelState.CONNECTED:
		_receive_packets(channel_id, record)
		_update_backpressure(channel_id, record)
	elif peer_state == WebSocketPeer.STATE_CLOSING:
		record.state = ChannelState.CLOSING
	elif peer_state == WebSocketPeer.STATE_CLOSED:
		_handle_disconnect(channel_id, record, OK, backend.close_code(), backend.close_reason())


func _receive_packets(channel_id: StringName, record: Dictionary) -> void:
	var backend := record.backend as GFWebSocketBackend
	var definition := record.definition as GFWebSocketChannelDefinition
	var received := 0
	while received < definition.receive_packet_budget_per_frame and backend.available_packet_count() > 0:
		var packet := backend.get_packet()
		var error := int(packet.get("error", ERR_BUG)) as Error
		if error != OK:
			channel_error.emit(channel_id, error)
			break
		var data := packet.get("data", PackedByteArray()) as PackedByteArray
		if data.size() > definition.max_packet_bytes:
			channel_error.emit(channel_id, ERR_OUT_OF_MEMORY)
		else:
			packet_received.emit(channel_id, data, bool(packet.get("is_text", false)))
		received += 1


func _update_backpressure(channel_id: StringName, record: Dictionary) -> void:
	if not bool(record.blocked):
		return
	var definition := record.definition as GFWebSocketChannelDefinition
	var backend := record.backend as GFWebSocketBackend
	if backend.outbound_buffered_amount() <= definition.send_low_watermark_bytes:
		record.blocked = false
		channel_writable.emit(channel_id)


func _handle_disconnect(
	channel_id: StringName,
	record: Dictionary,
	error: Error,
	code: int,
	reason: String,
) -> void:
	var requested := bool(record.requested_close)
	record.backend = null
	record.connect_elapsed = 0.0
	record.close_elapsed = 0.0
	record.blocked = false
	if error != OK:
		channel_error.emit(channel_id, error)
	channel_disconnected.emit(channel_id, code, reason, requested)
	if requested:
		record.state = ChannelState.DISCONNECTED
		return
	_schedule_reconnect(channel_id, record)


func _schedule_reconnect(channel_id: StringName, record: Dictionary) -> void:
	var definition := record.definition as GFWebSocketChannelDefinition
	var attempts := int(record.reconnect_attempts)
	if not definition.reconnect_enabled:
		record.state = ChannelState.DISCONNECTED
		return
	if definition.max_reconnect_attempts >= 0 and attempts >= definition.max_reconnect_attempts:
		record.state = ChannelState.DISCONNECTED
		reconnect_exhausted.emit(channel_id, attempts)
		return
	attempts += 1
	record.reconnect_attempts = attempts
	var delay := definition.reconnect_initial_delay_seconds * pow(definition.reconnect_multiplier, attempts - 1)
	delay = minf(delay, definition.reconnect_max_delay_seconds)
	record.reconnect_remaining = delay
	record.state = ChannelState.RECONNECT_WAIT
	reconnect_scheduled.emit(channel_id, attempts, delay)


func _create_backend(channel_id: StringName) -> GFWebSocketBackend:
	if not _backend_factory.is_valid():
		return GFGodotWebSocketBackend.new()
	var created: Variant = _backend_factory.call(channel_id)
	return created as GFWebSocketBackend if created is GFWebSocketBackend else null


func _record(channel_id: StringName) -> Dictionary:
	return _channels.get(channel_id, {}) as Dictionary


func _fail(code: Error, message: String) -> Error:
	last_error = message
	return code
