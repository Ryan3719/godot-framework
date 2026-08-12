class_name GFWebSocketChannelDefinition
extends Resource

@export var channel_id: StringName
@export var url := ""
@export var auto_connect := false
@export var handshake_headers := PackedStringArray()
@export var supported_protocols := PackedStringArray()
@export var reconnect_enabled := false
@export_range(0.0, 3600.0, 0.1) var reconnect_initial_delay_seconds := 1.0
@export_range(0.0, 3600.0, 0.1) var reconnect_max_delay_seconds := 30.0
@export_range(1.0, 10.0, 0.1) var reconnect_multiplier := 2.0
@export_range(-1, 100, 1) var max_reconnect_attempts := 5
@export_range(0.0, 3600.0, 0.1) var connect_timeout_seconds := 15.0
@export_range(0.0, 3600.0, 0.1) var close_timeout_seconds := 5.0
@export_range(0.0, 3600.0, 0.1) var heartbeat_interval_seconds := 0.0
@export_range(1024, 16777216, 1024) var inbound_buffer_size := 262144
@export_range(1024, 16777216, 1024) var outbound_buffer_size := 262144
@export_range(1, 65536, 1) var max_queued_packets := 4096
@export_range(1, 16777216, 1) var max_packet_bytes := 65536
@export_range(1, 4096, 1) var receive_packet_budget_per_frame := 64
@export_range(1, 16777216, 1) var send_high_watermark_bytes := 196608
@export_range(0, 16777216, 1) var send_low_watermark_bytes := 98304


func validate() -> String:
	if channel_id.is_empty():
		return "WebSocket channel ID cannot be empty."
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		return "WebSocket channel '%s' must use ws:// or wss://." % channel_id
	if reconnect_initial_delay_seconds < 0.0 or reconnect_max_delay_seconds < 0.0:
		return "WebSocket channel '%s' reconnect delays cannot be negative." % channel_id
	if reconnect_max_delay_seconds < reconnect_initial_delay_seconds:
		return "WebSocket channel '%s' reconnect maximum is below its initial delay." % channel_id
	if reconnect_multiplier < 1.0 or max_reconnect_attempts < -1:
		return "WebSocket channel '%s' reconnect policy is invalid." % channel_id
	if connect_timeout_seconds < 0.0 or close_timeout_seconds < 0.0 or heartbeat_interval_seconds < 0.0:
		return "WebSocket channel '%s' timeouts and heartbeat cannot be negative." % channel_id
	if inbound_buffer_size < 1 or outbound_buffer_size < 1 or max_queued_packets < 1:
		return "WebSocket channel '%s' buffers and packet queue must be positive." % channel_id
	if max_packet_bytes < 1 or receive_packet_budget_per_frame < 1:
		return "WebSocket channel '%s' packet limits must be positive." % channel_id
	if send_high_watermark_bytes < 1 or send_low_watermark_bytes < 0:
		return "WebSocket channel '%s' send watermarks are invalid." % channel_id
	if send_low_watermark_bytes > send_high_watermark_bytes:
		return "WebSocket channel '%s' low watermark exceeds its high watermark." % channel_id
	if send_high_watermark_bytes > outbound_buffer_size:
		return "WebSocket channel '%s' high watermark exceeds its outbound buffer." % channel_id
	if max_packet_bytes > send_high_watermark_bytes:
		return "WebSocket channel '%s' maximum packet exceeds its send high watermark." % channel_id
	return ""
