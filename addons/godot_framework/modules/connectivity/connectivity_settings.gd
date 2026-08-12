@tool
class_name GFConnectivitySettings
extends Resource

@export var root_name := "FrameworkConnectivity"
@export_range(1, 32, 1) var http_max_concurrent := 4
@export_range(1, 4096, 1) var http_max_in_flight_requests := 128
@export_range(0, 67108864, 1024) var http_request_body_limit_bytes := 4194304
@export_range(0, 268435456, 1024) var http_max_queued_body_bytes := 16777216
@export_range(-1, 268435456, 1024) var http_response_body_limit_bytes := 16777216
@export_range(0.0, 3600.0, 0.1) var http_timeout_seconds := 30.0
@export var http_use_threads := true
@export_range(0, 32, 1) var http_max_redirects := 8
@export_range(0.0, 3600.0, 0.1) var request_timeout_seconds := 15.0
@export var websocket_channels: Array[GFWebSocketChannelDefinition] = []


func validate() -> String:
	if root_name.is_empty():
		return "Connectivity root name cannot be empty."
	if http_max_concurrent < 1:
		return "HTTP concurrency must be at least one."
	if http_max_in_flight_requests < http_max_concurrent:
		return "HTTP in-flight request limit cannot be below concurrency."
	if http_request_body_limit_bytes < 0 or http_max_queued_body_bytes < 0:
		return "HTTP request body limits cannot be negative."
	if http_request_body_limit_bytes > http_max_queued_body_bytes:
		return "HTTP per-request body limit exceeds the queued body byte limit."
	if http_response_body_limit_bytes < -1:
		return "HTTP response body limit cannot be less than -1."
	if http_timeout_seconds < 0.0 or request_timeout_seconds < 0.0:
		return "Connectivity timeouts cannot be negative."
	if http_max_redirects < 0:
		return "HTTP redirect limit cannot be negative."
	var channel_ids: Dictionary = {}
	for channel: GFWebSocketChannelDefinition in websocket_channels:
		if channel == null:
			return "Connectivity settings contain a null WebSocket channel."
		var validation := channel.validate()
		if not validation.is_empty():
			return validation
		if channel_ids.has(channel.channel_id):
			return "Duplicate WebSocket channel '%s'." % channel.channel_id
		channel_ids[channel.channel_id] = true
	return ""
