class_name GFObjectPool
extends RefCounted

signal object_created(object: Object)
signal object_acquired(object: Object)
signal object_released(object: Object)
signal object_discarded(object: Object)

var capacity: int
var factory: Callable
var resetter: Callable
var disposer: Callable

var _available: Array[Object] = []
var _available_ids: Dictionary = {}
var _leased: Dictionary = {}
var _created_count := 0


func _init(
	p_factory: Callable,
	p_capacity := 64,
	p_resetter := Callable(),
	p_disposer := Callable(),
) -> void:
	factory = p_factory
	capacity = maxi(p_capacity, 0)
	resetter = p_resetter
	disposer = p_disposer


func acquire() -> Object:
	var object: Object
	while not _available.is_empty():
		object = _available.pop_back()
		_available_ids.erase(_identity(object))
		if _is_usable(object):
			break
		_dispose(object)
		object = null
	if object == null:
		if not factory.is_valid():
			return null
		var created: Variant = factory.call()
		if not created is Object:
			return null
		object = created as Object
		_created_count += 1
		object_created.emit(object)
	var identity := _identity(object)
	if identity == 0 or _leased.has(identity):
		return null
	_leased[identity] = object
	object_acquired.emit(object)
	return object


func release(object: Object) -> bool:
	var identity := _identity(object)
	if identity == 0 or not _leased.has(identity) or not is_same(_leased[identity], object):
		return false
	_leased.erase(identity)
	if resetter.is_valid():
		resetter.call(object)
	if capacity == 0 or _available.size() >= capacity or not _is_usable(object):
		_dispose(object)
		object_discarded.emit(object)
		return true
	_available.append(object)
	_available_ids[identity] = true
	object_released.emit(object)
	return true


func warm_up(count: int) -> int:
	var added := 0
	while added < count and _available.size() < capacity:
		if not factory.is_valid():
			break
		var created: Variant = factory.call()
		if not created is Object:
			break
		var object := created as Object
		var identity := _identity(object)
		if identity == 0 or _leased.has(identity) or _available_ids.has(identity):
			break
		_created_count += 1
		_available.append(object)
		_available_ids[identity] = true
		object_created.emit(object)
		added += 1
	return added


func trim(keep := 0) -> int:
	var target := clampi(keep, 0, _available.size())
	var removed := 0
	while _available.size() > target:
		var object := _available.pop_back()
		_available_ids.erase(_identity(object))
		_dispose(object)
		removed += 1
	return removed


func clear(dispose_leased := false) -> void:
	trim(0)
	if dispose_leased:
		for object: Object in _leased.values():
			_dispose(object)
	_leased.clear()
	_available_ids.clear()


func available_count() -> int:
	return _available.size()


func leased_count() -> int:
	return _leased.size()


func created_count() -> int:
	return _created_count


func _identity(object: Object) -> int:
	return object.get_instance_id() if is_instance_valid(object) else 0


func _is_usable(object: Object) -> bool:
	return is_instance_valid(object)


func _dispose(object: Object) -> void:
	if not is_instance_valid(object):
		return
	if disposer.is_valid():
		disposer.call(object)
	elif object is Node:
		(object as Node).queue_free()
