extends Node

var _assertions := 0
var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_test_default_framework_boot()
	_test_service_container()
	_test_event_bus()
	_test_message_bus()
	_test_module_dependencies_and_lifecycle()
	_test_module_failure_rollback()
	_test_state_machine()
	_test_object_pool()
	await _test_resource_service()
	_test_settings_service()
	_test_storage_service_and_migration()
	_finish()


func _test_default_framework_boot() -> void:
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	_expect(framework != null, "Autoload framework host exists")
	if framework == null:
		return
	_expect(framework.is_booted(), "Default framework configuration boots")
	_expect(framework.get_service(GFServiceIds.EVENTS) is GFEventBus, "Event service is registered")
	_expect(framework.get_service(GFServiceIds.MESSAGES) is GFMessageBus, "Message service is registered")
	_expect(framework.get_service(GFServiceIds.RESOURCES) is GFResourceService, "Resource module is registered")
	_expect(framework.get_service(GFServiceIds.SCENES) is GFSceneService, "Scene module is registered")
	_expect(framework.get_service(GFServiceIds.STORAGE) is GFStorageService, "Storage module is registered")
	_expect(framework.get_service(GFServiceIds.SETTINGS) is GFSettingsService, "Settings module is registered")
	_expect(framework.get_service(GFServiceIds.POOLS) is GFPoolService, "Pool module is registered")
	_expect(
		framework.get_service(GFServiceIds.STATE_MACHINES) is GFStateMachineService,
		"State machine module is registered",
	)
	var ordered := framework.modules.ordered_ids()
	_expect(ordered.find(&"resource") < ordered.find(&"scene"), "Resource dependency starts before scene")


func _test_service_container() -> void:
	var services := GFServiceContainer.new()
	var value := RefCounted.new()
	_expect(services.register(&"sample", value) == OK, "Service can be registered")
	_expect(services.register(&"sample", value) == ERR_ALREADY_EXISTS, "Duplicate service is rejected")
	_expect(is_same(services.require(&"sample"), value), "Required service resolves by identity")
	_expect(not services.unregister(&"sample", RefCounted.new()), "Expected identity protects unregister")
	_expect(services.unregister(&"sample", value), "Matching service can be unregistered")


func _test_event_bus() -> void:
	var events := GFEventBus.new()
	var order: Array[String] = []
	events.subscribe(&"ordered", func(_payload: Variant) -> void: order.append("low"), 0)
	events.subscribe(&"ordered", func(_payload: Variant) -> void: order.append("high"), 10)
	_expect(events.publish(&"ordered") == 2, "Event invokes all subscribers")
	_expect(order == ["high", "low"], "Event priority is deterministic")

	var once_count := [0]
	events.subscribe(&"once", func(_payload: Variant) -> void: once_count[0] += 1, 0, true)
	events.publish(&"once")
	events.publish(&"once")
	_expect(once_count[0] == 1, "One-shot subscription is removed before callback")

	var low_token := events.subscribe(&"reentrant", func(_payload: Variant) -> void: order.append("unexpected"))
	events.subscribe(&"reentrant", func(_payload: Variant) -> void: events.unsubscribe(low_token), 10)
	_expect(events.publish(&"reentrant") == 1, "Unsubscribe during publish safely skips stale callback")

	var queued: Array[int] = []
	events.subscribe(&"queued", func(value: Variant) -> void: queued.append(int(value)))
	events.queue(&"queued", 1)
	events.queue(&"queued", 2)
	_expect(events.flush(1) == 1 and events.queued_count() == 1, "Event flush limit defers overflow")
	_expect(events.flush() == 1 and queued == [1, 2], "Queued events preserve FIFO order")
	events.clear()


func _test_message_bus() -> void:
	var messages := GFMessageBus.new()
	var command_values: Array[int] = []
	_expect(
		messages.register_command(&"append", func(value: Variant) -> void: command_values.append(int(value))) == OK,
		"Command handler can be registered",
	)
	_expect(messages.send(&"append", 7) == OK and command_values == [7], "Command dispatches intent")
	_expect(messages.send(&"missing") == ERR_DOES_NOT_EXIST, "Missing command returns an explicit error")
	messages.register_query(&"double", func(value: Variant) -> int: return int(value) * 2)
	_expect(messages.ask(&"double", 6) == 12, "Query returns a value")
	_expect(messages.ask(&"missing", null, 9) == 9, "Missing query returns caller default")


func _test_module_dependencies_and_lifecycle() -> void:
	var trace: Array[String] = []
	var manager := _new_module_manager()
	var consumer := GFTrackingTestModule.new().setup(&"consumer", [&"provider"], trace)
	var provider := GFTrackingTestModule.new().setup(&"provider", [], trace)
	_expect(manager.install(consumer) == OK and manager.install(provider) == OK, "Modules install in any order")
	_expect(manager.initialize_all() == OK, "Module dependency graph initializes")
	_expect(
		manager.install(GFTrackingTestModule.new().setup(&"late", [], trace)) == ERR_ALREADY_IN_USE,
		"Module graph is immutable after initialization",
	)
	_expect(manager.initialize_all() == ERR_ALREADY_IN_USE, "Repeated initialization is rejected")
	_expect(manager.ordered_ids() == [&"provider", &"consumer"], "Dependencies are topologically sorted")
	_expect(manager.start_all() == OK, "Initialized modules start")
	manager.shutdown_all()
	_expect(
		trace == [
			"initialize:provider",
			"initialize:consumer",
			"start:provider",
			"start:consumer",
			"shutdown:consumer",
			"shutdown:provider",
		],
		"Module shutdown reverses startup order",
	)

	var missing_manager := _new_module_manager()
	missing_manager.install(GFTrackingTestModule.new().setup(&"consumer", [&"absent"], []))
	_expect(missing_manager.initialize_all() == ERR_DOES_NOT_EXIST, "Missing dependency fails loudly")

	var cycle_manager := _new_module_manager()
	cycle_manager.install(GFTrackingTestModule.new().setup(&"a", [&"b"], []))
	cycle_manager.install(GFTrackingTestModule.new().setup(&"b", [&"a"], []))
	_expect(cycle_manager.initialize_all() == ERR_CYCLIC_LINK, "Dependency cycle is rejected")


func _test_module_failure_rollback() -> void:
	var trace: Array[String] = []
	var manager := _new_module_manager()
	manager.install(GFTrackingTestModule.new().setup(&"first", [], trace))
	manager.install(GFTrackingTestModule.new().setup(&"failed", [&"first"], trace, ERR_CANT_CREATE))
	_expect(manager.initialize_all() == ERR_CANT_CREATE, "Initialization error is propagated")
	_expect(
		trace == ["initialize:first", "initialize:failed", "shutdown:failed", "shutdown:first"],
		"Initialization failure cleans the failing module and rolls back initialized modules",
	)

	trace.clear()
	var start_manager := _new_module_manager()
	start_manager.install(GFTrackingTestModule.new().setup(&"first", [], trace))
	start_manager.install(GFTrackingTestModule.new().setup(&"failed", [&"first"], trace, OK, ERR_CANT_CREATE))
	_expect(start_manager.initialize_all() == OK, "Start rollback fixture initializes")
	_expect(start_manager.start_all() == ERR_CANT_CREATE, "Start error is propagated")
	_expect(
		trace == [
			"initialize:first",
			"initialize:failed",
			"start:first",
			"start:failed",
			"shutdown:failed",
			"shutdown:first",
		],
		"Start failure shuts down every initialized module in reverse order",
	)


func _test_state_machine() -> void:
	var trace: Array[String] = []
	var machine := GFStateMachine.new()
	var idle := GFTrackingTestState.new().setup(&"idle", trace)
	var active := GFTrackingTestState.new().setup(&"active", trace)
	_expect(machine.add_state(idle) == OK and machine.add_state(active) == OK, "FSM states can be added")
	_expect(machine.change(&"idle") == OK, "FSM enters initial state")
	machine.update(0.1)
	_expect(machine.change(&"active") == OK, "FSM changes state")
	_expect(machine.current_id() == &"active", "FSM exposes current state")
	active.allow_exit = false
	_expect(machine.change(&"idle") == ERR_UNAUTHORIZED, "FSM state can guard exit")
	_expect(
		trace == ["enter:idle:", "update:idle", "exit:idle:active", "enter:active:idle"],
		"FSM lifecycle callbacks have stable order",
	)
	machine.clear()


func _test_object_pool() -> void:
	var reset_count := [0]
	var pool := GFObjectPool.new(
		func() -> RefCounted: return RefCounted.new(),
		1,
		func(_object: Variant) -> void: reset_count[0] += 1,
	)
	var first := pool.acquire()
	_expect(first is RefCounted and pool.leased_count() == 1, "Pool creates and leases an object")
	_expect(pool.release(first), "Leased object returns to pool")
	_expect(not pool.release(first), "Double release is rejected")
	var second := pool.acquire()
	_expect(is_same(first, second), "Pool reuses available object")
	_expect(reset_count[0] == 1, "Pool reset hook runs on release")
	pool.release(second)
	_expect(pool.warm_up(3) == 0 and pool.available_count() == 1, "Pool capacity limits warm-up")
	var invalid_pool := GFObjectPool.new(func() -> Variant: return [])
	_expect(invalid_pool.acquire() == null, "Pool rejects non-Object factory results")
	var shared := RefCounted.new()
	var duplicate_pool := GFObjectPool.new(func() -> RefCounted: return shared, 2)
	_expect(duplicate_pool.warm_up(2) == 1, "Pool rejects duplicate object identity during warm-up")
	duplicate_pool.clear()


func _test_resource_service() -> void:
	var resources := GFResourceService.new()
	var loaded := resources.load("res://addons/godot_framework/config/default_framework_config.tres")
	_expect(loaded is GFFrameworkConfig, "Resource service loads typed Godot resources")
	_expect(is_same(loaded, resources.get_cached(loaded.resource_path)), "Resource service caches loaded resource")
	_expect(resources.release(loaded.resource_path), "Resource cache entry can be released")
	var async_completed := [false]
	resources.load_completed.connect(func(path: String, _resource: Resource) -> void:
		if path == "res://tests/fixtures/transition_target.tscn":
			async_completed[0] = true
	)
	_expect(
		resources.request("res://tests/fixtures/transition_target.tscn", "PackedScene") == OK,
		"Threaded resource request starts",
	)
	for _index in range(120):
		resources.poll()
		if async_completed[0]:
			break
		await get_tree().process_frame
	_expect(async_completed[0], "Threaded resource request completes")
	_expect(resources.get_cached("res://tests/fixtures/transition_target.tscn") is PackedScene, "Threaded resource is cached")


func _test_settings_service() -> void:
	var service_settings := GFSettingsSettings.new()
	service_settings.file_path = "user://gf_test_settings.cfg"
	service_settings.auto_save = false
	var settings_service := GFSettingsService.new(service_settings)
	_expect(settings_service.load() == OK, "Missing settings file loads as empty configuration")
	_expect(settings_service.set_value(&"audio", &"volume", 0.75) == OK, "Setting value is accepted")
	var runtime_node := Node.new()
	_expect(
		settings_service.set_value(&"invalid", &"nested", {"nodes": [runtime_node]}) == ERR_INVALID_PARAMETER,
		"Settings reject nested runtime objects",
	)
	var cyclic_settings: Array = []
	cyclic_settings.append(cyclic_settings)
	_expect(
		settings_service.set_value(&"invalid", &"cyclic", cyclic_settings) == ERR_INVALID_PARAMETER,
		"Settings reject cyclic containers",
	)
	runtime_node.free()
	_expect(settings_service.is_dirty(), "Unsaved settings are marked dirty")
	_expect(settings_service.save() == OK, "Settings persist to ConfigFile")
	var reloaded := GFSettingsService.new(service_settings)
	_expect(reloaded.load() == OK, "Settings file reloads")
	_expect(is_equal_approx(float(reloaded.get_value(&"audio", &"volume")), 0.75), "Setting value round-trips")
	DirAccess.remove_absolute(service_settings.file_path)


func _test_storage_service_and_migration() -> void:
	var version_one := GFStorageSettings.new()
	version_one.base_directory = "user://gf_framework_tests"
	version_one.schema_version = 1
	version_one.backup_count = 1
	var storage := GFStorageService.new(version_one)
	storage.delete(&"profile")
	_expect(storage.save(&"profile", {"score": 5}) == OK, "Storage writes serializable state")
	_expect(storage.exists(&"profile"), "Storage reports existing slot")
	_expect(storage.load(&"profile") == {"score": 5}, "Storage data round-trips")
	_expect(storage.save(&"profile", {"score": 6}) == OK, "Storage atomically replaces existing slot")
	_expect(FileAccess.file_exists("%s.bak1" % storage.path_for(&"profile")), "Storage keeps configured backup")

	var version_two := version_one.duplicate() as GFStorageSettings
	version_two.schema_version = 2
	var migrated_storage := GFStorageService.new(version_two)
	migrated_storage.register_migration(1, func(data: Dictionary) -> Dictionary:
		var migrated := data.duplicate(true)
		migrated["rank"] = "new"
		return migrated
	)
	_expect(
		migrated_storage.load(&"profile") == {"score": 6, "rank": "new"},
		"Storage migrates older schema sequentially",
	)
	var runtime_node := Node.new()
	_expect(storage.save(&"invalid", {"node": runtime_node}) == ERR_INVALID_DATA, "Storage rejects runtime objects")
	runtime_node.free()
	var cyclic_data: Dictionary = {}
	cyclic_data["self"] = cyclic_data
	_expect(storage.save(&"cyclic", cyclic_data) == ERR_INVALID_DATA, "Storage rejects cyclic containers")
	storage.delete(&"profile")
	var no_backup := GFStorageSettings.new()
	no_backup.base_directory = version_one.base_directory
	no_backup.backup_count = 0
	var no_backup_storage := GFStorageService.new(no_backup)
	_expect(no_backup_storage.save(&"replace", {"value": 1}) == OK, "Storage without backups writes first state")
	_expect(no_backup_storage.save(&"replace", {"value": 2}) == OK, "Storage without backups replaces state")
	_expect(no_backup_storage.load(&"replace") == {"value": 2}, "Storage replacement keeps latest state")
	no_backup_storage.delete(&"replace")
	DirAccess.remove_absolute(version_one.base_directory)


func _new_module_manager() -> GFModuleManager:
	var services := GFServiceContainer.new()
	var events := GFEventBus.new()
	var messages := GFMessageBus.new()
	var logger := GFLogger.new()
	logger.minimum_level = GFLogger.Level.NONE
	var context := GFContext.new(self, services, events, messages, logger)
	return GFModuleManager.new(context)


func _expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		push_error("[TEST] %s" % description)


func _finish() -> void:
	var framework := get_node_or_null("/root/GodotFramework") as GFFrameworkHost
	if framework != null:
		framework.shutdown()
	if _failures.is_empty():
		print("[TEST] PASS: %d assertions" % _assertions)
		call_deferred("_quit", 0)
		return
	print("[TEST] FAIL: %d of %d assertions failed" % [_failures.size(), _assertions])
	for failure: String in _failures:
		print("  - %s" % failure)
	call_deferred("_quit", 1)


func _quit(exit_code: int) -> void:
	get_tree().quit(exit_code)
