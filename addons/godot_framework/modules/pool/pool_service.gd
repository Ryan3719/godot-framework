class_name GFPoolService
extends RefCounted

var _pools: Dictionary = {}


func create_pool(
	pool_id: StringName,
	factory: Callable,
	capacity := 64,
	resetter := Callable(),
	disposer := Callable(),
) -> GFObjectPool:
	if pool_id.is_empty() or _pools.has(pool_id) or not factory.is_valid():
		return null
	var pool := GFObjectPool.new(factory, capacity, resetter, disposer)
	_pools[pool_id] = pool
	return pool


func add_pool(pool_id: StringName, pool: GFObjectPool, replace := false) -> Error:
	if pool_id.is_empty() or pool == null:
		return ERR_INVALID_PARAMETER
	if _pools.has(pool_id) and not replace:
		return ERR_ALREADY_EXISTS
	if replace:
		remove_pool(pool_id)
	_pools[pool_id] = pool
	return OK


func get_pool(pool_id: StringName) -> GFObjectPool:
	return _pools.get(pool_id) as GFObjectPool


func remove_pool(pool_id: StringName, dispose_leased := false) -> bool:
	var pool := get_pool(pool_id)
	if pool == null:
		return false
	pool.clear(dispose_leased)
	_pools.erase(pool_id)
	return true


func clear(dispose_leased := false) -> void:
	for pool: GFObjectPool in _pools.values():
		pool.clear(dispose_leased)
	_pools.clear()
