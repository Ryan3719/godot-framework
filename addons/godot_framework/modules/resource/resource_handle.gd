class_name GFResourceHandle
extends RefCounted

enum CachePolicy {
	TRANSIENT,
	LEASED,
	RETAINED,
}

var path: String
var resource: Resource
var policy: CachePolicy

var _service_ref: WeakRef
var _released := false


func _init(
	service: RefCounted,
	resource_path: String,
	loaded_resource: Resource,
	cache_policy: CachePolicy,
) -> void:
	_service_ref = weakref(service)
	path = resource_path
	resource = loaded_resource
	policy = cache_policy


func is_released() -> bool:
	return _released


func release() -> void:
	if _released:
		return
	_released = true
	var service := _service_ref.get_ref() as RefCounted if _service_ref != null else null
	if service != null and service.has_method(&"_release_handle"):
		service.call(&"_release_handle", path, policy)
	_service_ref = null
	resource = null
