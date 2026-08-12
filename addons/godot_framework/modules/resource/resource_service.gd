class_name GFResourceService
extends RefCounted

signal load_started(path: String)
signal load_progress(path: String, progress: float)
signal load_completed(path: String, resource: Resource)
signal load_failed(path: String, error: Error)

var cache_enabled := true
var _cache: Dictionary = {}
var _requests: Dictionary = {}


func load(path: String, type_hint := "", cache_mode := ResourceLoader.CACHE_MODE_REUSE) -> Resource:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Resource
	var resource := ResourceLoader.load(path, type_hint, cache_mode)
	if resource != null and cache_enabled:
		_cache[path] = resource
	return resource


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
	return _cache.erase(path)


func clear_cache() -> void:
	_cache.clear()


func clear(wait_for_pending := true) -> void:
	if wait_for_pending:
		for path: String in _requests.keys():
			ResourceLoader.load_threaded_get(path)
	_requests.clear()
	_cache.clear()


func pending_count() -> int:
	return _requests.size()
