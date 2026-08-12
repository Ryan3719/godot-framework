class_name GFConnectivityTestBackendFactory
extends RefCounted

var http_plans: Array[Dictionary] = []
var websocket_plans: Dictionary = {}
var created_http: Array[GFTestHTTPRequestBackend] = []
var created_websockets: Dictionary = {}


func create_http():
	var plan: Dictionary = http_plans.pop_front() if not http_plans.is_empty() else {}
	var backend := GFTestHTTPRequestBackend.new().setup(plan)
	created_http.append(backend)
	return backend


func create_websocket(channel_id: StringName):
	var plans := websocket_plans.get(channel_id, []) as Array
	var plan: Dictionary = plans.pop_front() if not plans.is_empty() else {}
	var backend := GFTestWebSocketBackend.new().setup(plan)
	if not created_websockets.has(channel_id):
		created_websockets[channel_id] = []
	(created_websockets[channel_id] as Array).append(backend)
	return backend
