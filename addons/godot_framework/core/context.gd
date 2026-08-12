class_name GFContext
extends RefCounted

var host: Node
var services: GFServiceContainer
var events: GFEventBus
var messages: GFMessageBus
var logger: GFLogger


func _init(
	p_host: Node,
	p_services: GFServiceContainer,
	p_events: GFEventBus,
	p_messages: GFMessageBus,
	p_logger: GFLogger,
) -> void:
	host = p_host
	services = p_services
	events = p_events
	messages = p_messages
	logger = p_logger


func tree() -> SceneTree:
	if not is_instance_valid(host):
		return null
	return host.get_tree()
