class_name GFRequestTracker
extends RefCounted

signal request_tracked(correlation_id: int, context: Variant)
signal request_resolved(correlation_id: int, response: Variant, context: Variant)
signal request_timed_out(correlation_id: int, context: Variant)
signal request_cancelled(correlation_id: int, context: Variant)

var default_timeout_seconds := 15.0

var _pending: Dictionary = {}
var _next_id := 1


func begin(timeout_seconds := -1.0, context: Variant = null) -> int:
	if timeout_seconds < -1.0:
		return 0
	var correlation_id := _next_id
	_next_id += 1
	_pending[correlation_id] = {
		"id": correlation_id,
		"timeout_seconds": default_timeout_seconds if timeout_seconds < 0.0 else timeout_seconds,
		"elapsed_seconds": 0.0,
		"context": context,
	}
	request_tracked.emit(correlation_id, context)
	return correlation_id


func resolve(correlation_id: int, response: Variant = null) -> bool:
	if not _pending.has(correlation_id):
		return false
	var entry: Dictionary = _pending[correlation_id]
	_pending.erase(correlation_id)
	request_resolved.emit(correlation_id, response, entry.context)
	return true


func cancel(correlation_id: int) -> bool:
	if not _pending.has(correlation_id):
		return false
	var entry: Dictionary = _pending[correlation_id]
	_pending.erase(correlation_id)
	request_cancelled.emit(correlation_id, entry.context)
	return true


func update(delta: float) -> void:
	for correlation_id: int in _pending.keys():
		var entry: Dictionary = _pending[correlation_id]
		var timeout := float(entry.timeout_seconds)
		if timeout <= 0.0:
			continue
		entry.elapsed_seconds = float(entry.elapsed_seconds) + maxf(delta, 0.0)
		if float(entry.elapsed_seconds) >= timeout:
			_pending.erase(correlation_id)
			request_timed_out.emit(correlation_id, entry.context)


func has(correlation_id: int) -> bool:
	return _pending.has(correlation_id)


func info(correlation_id: int) -> Dictionary:
	return (_pending[correlation_id] as Dictionary).duplicate() if _pending.has(correlation_id) else {}


func pending_count() -> int:
	return _pending.size()


func clear(emit_cancelled := false) -> void:
	if emit_cancelled:
		for correlation_id: int in _pending.keys():
			cancel(correlation_id)
	_pending.clear()
