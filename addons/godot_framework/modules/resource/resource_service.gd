class_name GFResourceService
extends RefCounted

signal load_started(path: String)
signal load_progress(path: String, progress: float)
signal load_completed(path: String, resource: Resource)
signal load_failed(path: String, error: Error)

var cache_enabled := true
var _cache: Dictionary = {}
var _requests: Dictionary = {}
var _lease_counts: Dictionary = {}
var _retained: Dictionary = {}


func load(path: String, type_hint := "", cache_mode := ResourceLoader.CACHE_MODE_REUSE) -> Resource:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Resource
	var resource := ResourceLoader.load(path, type_hint, cache_mode)
	if resource != null and cache_enabled:
		_cache[path] = resource
		_retained[path] = true
	return resource


func acquire(
	path: String,
	type_hint := "",
	policy := GFResourceHandle.CachePolicy.LEASED,
	cache_mode := ResourceLoader.CACHE_MODE_REUSE,
) -> GFResourceHandle:
	if path.is_empty() or policy not in GFResourceHandle.CachePolicy.values():
		return null
	var resource := _cache.get(path) as Resource
	if resource == null:
		resource = ResourceLoader.load(path, type_hint, cache_mode)
	if resource == null:
		return null
	match policy:
		GFResourceHandle.CachePolicy.LEASED:
			_cache[path] = resource
			_lease_counts[path] = int(_lease_counts.get(path, 0)) + 1
		GFResourceHandle.CachePolicy.RETAINED:
			_cache[path] = resource
			_retained[path] = true
		GFResourceHandle.CachePolicy.TRANSIENT:
			pass
	return GFResourceHandle.new(self, path, resource, policy)


func request(path: String, type_hint := "", use_sub_threads := false) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	if _cache.has(path):
		load_completed.emit(path, _cache[path])
		return OK
	if _requests.has(path):
		return ERR_ALREADY_IN_USE
	var result := ResourceLoader.load_threaded_request(
		path,
		type_hint,
		use_sub_threads,
		ResourceLoader.CACHE_MODE_REUSE,
	)
	if result == OK:
		_requests[path] = []
		load_started.emit(path)
	else:
		load_failed.emit(path, result)
	return result


func poll(max_requests := 8) -> int:
	var checked := 0
	for path: String in _requests.keys():
		if checked >= max_requests:
			break
		checked += 1
		var progress: Array = _requests[path]
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				load_progress.emit(path, float(progress[0]) if not progress.is_empty() else 0.0)
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				_requests.erase(path)
				if resource != null:
					if cache_enabled:
						_cache[path] = resource
						_retained[path] = true
					load_progress.emit(path, 1.0)
					load_completed.emit(path, resource)
				else:
					load_failed.emit(path, ERR_CANT_ACQUIRE_RESOURCE)
			ResourceLoader.THREAD_LOAD_FAILED:
				_requests.erase(path)
				load_failed.emit(path, ERR_CANT_OPEN)
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_requests.erase(path)
				load_failed.emit(path, ERR_FILE_BAD_PATH)
	return checked


func get_cached(path: String) -> Resource:
	return _cache.get(path) as Resource


func has_cached(path: String) -> bool:
	return _cache.has(path)


func release(path: String) -> bool:
	if lease_count(path) > 0:
		return false
	_retained.erase(path)
	return _cache.erase(path)


func clear_cache(force := false) -> void:
	if force:
		_cache.clear()
		_retained.clear()
		return
	for path: String in _cache.keys():
		if lease_count(path) == 0:
			_cache.erase(path)
			_retained.erase(path)


func clear(wait_for_pending := true) -> void:
	if wait_for_pending:
		for path: String in _requests.keys():
			ResourceLoader.load_threaded_get(path)
	_requests.clear()
	clear_cache(true)
	_lease_counts.clear()


func pending_count() -> int:
	return _requests.size()


func lease_count(path: String) -> int:
	return int(_lease_counts.get(path, 0))


func is_retained(path: String) -> bool:
	return _retained.has(path)


func _release_handle(path: String, policy: GFResourceHandle.CachePolicy) -> void:
	if policy != GFResourceHandle.CachePolicy.LEASED:
		return
	var remaining := lease_count(path) - 1
	if remaining > 0:
		_lease_counts[path] = remaining
		return
	_lease_counts.erase(path)
	if not _retained.has(path):
		_cache.erase(path)
