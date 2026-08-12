class_name GFConnectivityService
extends RefCounted

var http: GFHTTPService
var websockets: GFWebSocketService
var requests: GFRequestTracker

var _root: Node
var _settings: GFConnectivitySettings


func _init(
	host: Node,
	settings: GFConnectivitySettings,
	http_backend_factory := Callable(),
	websocket_backend_factory := Callable(),
) -> void:
	_settings = settings
	_root = Node.new()
	_root.name = settings.root_name
	host.add_child(_root)
	http = GFHTTPService.new(_root, settings, http_backend_factory)
	websockets = GFWebSocketService.new(websocket_backend_factory)
	requests = GFRequestTracker.new(settings.request_max_pending)
	requests.default_timeout_seconds = settings.request_timeout_seconds
	for definition: GFWebSocketChannelDefinition in settings.websocket_channels:
		websockets.register_channel(definition)


func start() -> Error:
	return websockets.start_auto_connect()


func update(delta: float) -> void:
	http.update(delta)
	websockets.update(delta)
	requests.update(delta)


func shutdown() -> void:
	if http != null:
		http.shutdown()
	if websockets != null:
		websockets.shutdown()
	if requests != null:
		requests.clear(true)
	http = null
	websockets = null
	requests = null
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_settings = null
