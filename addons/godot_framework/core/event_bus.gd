class_name GFEventBus
extends RefCounted

var _subscriptions: Dictionary = {}
var _by_token: Dictionary = {}
var _queue: Array[Dictionary] = []
var _next_token := 1
var _next_order := 1


func subscribe(event_id: StringName, callback: Callable, priority := 0, once := false) -> int:
	if event_id.is_empty() or not callback.is_valid():
		return 0
	var token := _next_token
	_next_token += 1
	var subscription := {
		"token": token,
		"event_id": event_id,
		"callback": callback,
		"priority": priority,
		"once": once,
		"order": _next_order,
	}
	_next_order += 1
	_by_token[token] = subscription
	if not _subscriptions.has(event_id):
		_subscriptions[event_id] = []
	var tokens: Array = _subscriptions[event_id]
	tokens.append(token)
	tokens.sort_custom(_is_before)
	return token


func unsubscribe(token: int) -> bool:
	var subscription: Variant = _by_token.get(token)
	if subscription == null:
		return false
	var event_id: StringName = subscription.event_id
	if _subscriptions.has(event_id):
		var tokens: Array = _subscriptions[event_id]
		tokens.erase(token)
		if tokens.is_empty():
			_subscriptions.erase(event_id)
	_by_token.erase(token)
	return true


func publish(event_id: StringName, payload: Variant = null) -> int:
	if not _subscriptions.has(event_id):
		return 0
	var snapshot: Array = (_subscriptions[event_id] as Array).duplicate()
	var invoked := 0
	for token: int in snapshot:
		var subscription: Variant = _by_token.get(token)
		if subscription == null:
			continue
		if subscription.once:
			unsubscribe(token)
		var callback: Callable = subscription.callback
		if callback.is_valid():
			callback.call(payload)
			invoked += 1
	return invoked


func queue(event_id: StringName, payload: Variant = null) -> void:
	if event_id.is_empty():
		return
	_queue.append({"event_id": event_id, "payload": payload})


func flush(max_events := 1024) -> int:
	var processed := 0
	while not _queue.is_empty() and processed < max_events:
		var queued: Dictionary = _queue.pop_front()
		publish(queued.event_id, queued.payload)
		processed += 1
	return processed


func clear(event_id: StringName = &"") -> void:
	if event_id.is_empty():
		_subscriptions.clear()
		_by_token.clear()
		_queue.clear()
		return
	if not _subscriptions.has(event_id):
		return
	for token: int in (_subscriptions[event_id] as Array).duplicate():
		_by_token.erase(token)
	_subscriptions.erase(event_id)
	_queue = _queue.filter(func(item: Dictionary) -> bool: return item.event_id != event_id)


func subscription_count(event_id: StringName = &"") -> int:
	if event_id.is_empty():
		return _by_token.size()
	return (_subscriptions.get(event_id, []) as Array).size()


func queued_count() -> int:
	return _queue.size()


func _is_before(left_token: int, right_token: int) -> bool:
	var left: Dictionary = _by_token[left_token]
	var right: Dictionary = _by_token[right_token]
	if left.priority == right.priority:
		return left.order < right.order
	return left.priority > right.priority
