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
	_test_framework_validator()
	_test_optional_module_lifecycle()
	_test_state_machine()
	_test_object_pool()
	_test_ui_service()
	await _test_audio_service()
	_test_input_service()
	_test_localization_service()
	await _test_resource_service()
	await _test_download_service()
	_test_content_service()
	_test_table_service()
	_test_connectivity_service()
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
	_expect(
		framework.events.queue_capacity() == framework.config.max_queued_events,
		"Framework host applies the configured event queue capacity",
	)
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
	_expect(framework.get_service(GFServiceIds.UI) == null, "Optional UI module is disabled by default")
	_expect(framework.get_service(GFServiceIds.AUDIO) == null, "Optional audio module is disabled by default")
	_expect(framework.get_service(GFServiceIds.INPUT) == null, "Optional input module is disabled by default")
	_expect(framework.get_service(GFServiceIds.DOWNLOADS) == null, "Optional download module is disabled by default")
	_expect(framework.get_service(GFServiceIds.CONTENT) == null, "Optional content module is disabled by default")
	_expect(framework.get_service(GFServiceIds.TABLES) == null, "Optional table module is disabled by default")
	_expect(framework.get_service(GFServiceIds.CONNECTIVITY) == null, "Optional connectivity module is disabled by default")
	_expect(
		framework.get_service(GFServiceIds.LOCALIZATION) == null,
		"Optional localization module is disabled by default",
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
	_expect(events.queue(&"") == ERR_INVALID_PARAMETER, "Event queue rejects an empty event ID")
	_expect(events.queue(&"queued", 1) == OK, "Event queue accepts an event within capacity")
	_expect(events.queue(&"queued", 2) == OK, "Event queue accepts a second event within capacity")
	_expect(events.flush(1) == 1 and events.queued_count() == 1, "Event flush limit defers overflow")
	_expect(events.flush() == 1 and queued == [1, 2], "Queued events preserve FIFO order")

	var bounded_events := GFEventBus.new(2)
	_expect(bounded_events.queue_capacity() == 2, "Event queue exposes its configured capacity")
	_expect(
		bounded_events.queue(&"bounded", 1) == OK
		and bounded_events.queue(&"bounded", 2) == OK
		and bounded_events.queue(&"bounded", 3) == ERR_OUT_OF_MEMORY,
		"Event queue rejects new events when its capacity is exhausted",
	)
	bounded_events.flush(1)
	_expect(
		bounded_events.queue(&"bounded", 3) == OK and bounded_events.queued_count() == 2,
		"Event queue accepts new events after capacity is released",
	)
	bounded_events.clear(&"bounded")
	_expect(
		bounded_events.queued_count() == 0,
		"Event clear removes queued entries even when the event has no subscribers",
	)
	var compacted_events := GFEventBus.new(2048)
	for index in 2048:
		compacted_events.queue(&"compacted", index)
	_expect(
		compacted_events.flush(1536) == 1536 and compacted_events.queued_count() == 512,
		"Event queue compaction preserves the unprocessed backlog",
	)
	_expect(
		compacted_events.flush() == 512 and compacted_events.queued_count() == 0,
		"Event queue drains correctly after compaction",
	)
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


func _test_framework_validator() -> void:
	var validator := GFFrameworkValidator.new()
	var default_config := load("res://addons/godot_framework/config/default_framework_config.tres") as GFFrameworkConfig
	var valid_issues := validator.validate(default_config)
	_expect(
		valid_issues.size() == 1
		and valid_issues[0].code == &"config.valid"
		and not validator.has_errors(valid_issues),
		"Framework validator accepts the addon default configuration",
	)
	_expect(
		validator.validate_path("res://missing-framework-config.tres")[0].code == &"config.not_found",
		"Framework validator reports a missing configuration path",
	)
	var invalid_capacity := GFFrameworkConfig.new()
	invalid_capacity.max_queued_events = 0
	_expect(
		invalid_capacity.validate().contains("capacity"),
		"Framework configuration rejects a non-positive event queue capacity",
	)

	var invalid_config := GFFrameworkConfig.new()
	var empty_id := GFModuleDefinition.new()
	empty_id.module_script = GFPoolModule
	var duplicate_a := GFModuleDefinition.new()
	duplicate_a.declared_id = &"duplicate"
	duplicate_a.module_script = GFPoolModule
	var duplicate_b := GFModuleDefinition.new()
	duplicate_b.declared_id = &"duplicate"
	duplicate_b.module_script = GFPoolModule
	var disabled_dependency := GFModuleDefinition.new()
	disabled_dependency.enabled = false
	disabled_dependency.declared_id = &"provider"
	disabled_dependency.module_script = GFPoolModule
	var consumer := GFModuleDefinition.new()
	consumer.declared_id = &"consumer"
	consumer.declared_dependencies = [&"provider"]
	consumer.module_script = GFPoolModule
	var cycle_a := GFModuleDefinition.new()
	cycle_a.declared_id = &"cycle_a"
	cycle_a.declared_dependencies = [&"cycle_b"]
	cycle_a.module_script = GFPoolModule
	var cycle_b := GFModuleDefinition.new()
	cycle_b.declared_id = &"cycle_b"
	cycle_b.declared_dependencies = [&"cycle_a"]
	cycle_b.module_script = GFPoolModule
	var wrong_settings := GFModuleDefinition.new()
	wrong_settings.declared_id = &"wrong_settings"
	wrong_settings.module_script = GFPoolModule
	wrong_settings.expected_settings_class = &"GFStorageSettings"
	wrong_settings.settings = GFUISettings.new()
	var invalid_settings := GFModuleDefinition.new()
	invalid_settings.declared_id = &"invalid_settings"
	invalid_settings.module_script = GFPoolModule
	invalid_settings.expected_settings_class = &"GFStorageSettings"
	var bad_storage := GFStorageSettings.new()
	bad_storage.base_directory = "res://unsafe"
	invalid_settings.settings = bad_storage
	invalid_config.modules = [
		empty_id,
		duplicate_a,
		duplicate_b,
		disabled_dependency,
		consumer,
		cycle_a,
		cycle_b,
		wrong_settings,
		invalid_settings,
	]
	var issues := validator.validate(invalid_config)
	var codes: Array[StringName] = []
	for issue: Dictionary in issues:
		codes.append(issue.code)
	_expect(validator.has_errors(issues), "Framework validator exposes aggregate error state")
	_expect(codes.has(&"module.id_empty"), "Framework validator reports empty module IDs")
	_expect(codes.has(&"module.id_duplicate"), "Framework validator reports duplicate module IDs")
	_expect(codes.has(&"module.dependency_disabled"), "Framework validator reports disabled dependencies")
	_expect(codes.has(&"module.dependency_cycle"), "Framework validator reports dependency cycles")
	_expect(codes.has(&"module.settings_wrong_type"), "Framework validator reports settings type mismatch")
	_expect(codes.has(&"module.settings_invalid"), "Framework validator reports invalid settings content")
	var scriptless := GFModuleDefinition.new()
	scriptless.declared_id = &"scriptless_duplicate"
	var duplicate_after_scriptless := GFModuleDefinition.new()
	duplicate_after_scriptless.declared_id = &"scriptless_duplicate"
	duplicate_after_scriptless.module_script = GFPoolModule
	var scriptless_config := GFFrameworkConfig.new()
	scriptless_config.modules = [scriptless, duplicate_after_scriptless]
	var scriptless_codes: Array[StringName] = []
	for issue: Dictionary in validator.validate(scriptless_config):
		scriptless_codes.append(issue.code)
	_expect(
		scriptless_codes.has(&"module.script_missing") and scriptless_codes.has(&"module.id_duplicate"),
		"Framework validator reports duplicate IDs independently of script validity",
	)

	var mismatched_id := GFModuleDefinition.new()
	mismatched_id.declared_id = &"not_pool"
	mismatched_id.module_script = GFPoolModule
	_expect(
		mismatched_id.instantiate_module() == null and mismatched_id.last_error.contains("reports ID"),
		"Module instantiation rejects a declared ID that differs from runtime metadata",
	)
	var mismatched_dependencies := GFModuleDefinition.new()
	mismatched_dependencies.declared_id = &"scene"
	mismatched_dependencies.module_script = GFSceneModule
	_expect(
		mismatched_dependencies.instantiate_module() == null
		and mismatched_dependencies.last_error.contains("dependencies do not match"),
		"Module instantiation rejects declared dependencies that differ from runtime metadata",
	)
	var mismatched_settings := GFModuleDefinition.new()
	mismatched_settings.declared_id = &"pool"
	mismatched_settings.module_script = GFPoolModule
	mismatched_settings.expected_settings_class = &"GFStorageSettings"
	mismatched_settings.settings = GFUISettings.new()
	_expect(
		mismatched_settings.instantiate_module() == null
		and mismatched_settings.last_error.contains("settings must use"),
		"Module instantiation enforces declared settings types at runtime",
	)


func _test_optional_module_lifecycle() -> void:
	var services := GFServiceContainer.new()
	var manager := _new_module_manager(services)
	var resource_module := GFResourceModule.new()
	var ui_module := GFUIModule.new()
	var ui_settings := GFUISettings.new()
	ui_settings.root_name = "IntegratedTestUI"
	ui_module.configure(ui_settings)
	var audio_module := GFAudioModule.new()
	var audio_settings := GFAudioSettings.new()
	audio_settings.root_name = "IntegratedTestAudio"
	audio_module.configure(audio_settings)
	var input_module := GFInputModule.new()
	input_module.configure(GFInputSettings.new())
	var localization_module := GFLocalizationModule.new()
	var localization_settings := GFLocalizationSettings.new()
	localization_settings.supported_locales = PackedStringArray(["en"])
	localization_settings.fallback_locale = "en"
	localization_settings.use_system_locale = false
	localization_module.configure(localization_settings)
	var download_module := GFDownloadModule.new()
	var download_settings := GFDownloadSettings.new()
	download_settings.base_directory = "user://gf_integrated_downloads"
	download_module.configure(download_settings)
	var content_module := GFContentModule.new()
	var content_settings := GFContentSettings.new()
	content_settings.base_directory = "user://gf_integrated_content"
	content_settings.require_signature = false
	content_settings.auto_mount_active = false
	content_module.configure(content_settings)
	var table_module := GFTableModule.new()
	var connectivity_module := GFConnectivityModule.new()
	var connectivity_settings := GFConnectivitySettings.new()
	connectivity_settings.root_name = "IntegratedTestConnectivity"
	connectivity_module.configure(connectivity_settings)

	_expect(manager.install(ui_module) == OK, "Optional UI module can be installed before its dependency")
	_expect(manager.install(audio_module) == OK, "Optional audio module can be installed")
	_expect(manager.install(input_module) == OK, "Optional input module can be installed")
	_expect(manager.install(localization_module) == OK, "Optional localization module can be installed")
	_expect(manager.install(download_module) == OK, "Optional download module can be installed")
	_expect(manager.install(content_module) == OK, "Optional content module can be installed")
	_expect(manager.install(table_module) == OK, "Optional table module can be installed")
	_expect(manager.install(connectivity_module) == OK, "Optional connectivity module can be installed")
	_expect(manager.install(resource_module) == OK, "Resource module can coexist with optional modules")
	_expect(manager.initialize_all() == OK and manager.start_all() == OK, "Optional modules start through module manager")
	_expect(
		ui_module.dependencies().is_empty(),
		"UI module does not require an unused resource dependency",
	)
	_expect(services.resolve(GFServiceIds.UI) is GFUIService, "UI module registers its service")
	_expect(services.resolve(GFServiceIds.AUDIO) is GFAudioService, "Audio module registers its service")
	_expect(services.resolve(GFServiceIds.INPUT) is GFInputService, "Input module registers its service")
	_expect(
		services.resolve(GFServiceIds.LOCALIZATION) is GFLocalizationService,
		"Localization module registers its service",
	)
	_expect(services.resolve(GFServiceIds.DOWNLOADS) is GFDownloadService, "Download module registers its service")
	_expect(services.resolve(GFServiceIds.CONTENT) is GFContentService, "Content module registers its service")
	_expect(services.resolve(GFServiceIds.TABLES) is GFTableService, "Table module registers its service")
	_expect(services.resolve(GFServiceIds.CONNECTIVITY) is GFConnectivityService, "Connectivity module registers its service")
	manager.shutdown_all()
	_expect(not services.has(GFServiceIds.UI), "UI module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.AUDIO), "Audio module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.INPUT), "Input module removes its service during shutdown")
	_expect(
		not services.has(GFServiceIds.LOCALIZATION),
		"Localization module removes its service during shutdown",
	)
	_expect(not services.has(GFServiceIds.DOWNLOADS), "Download module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.CONTENT), "Content module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.TABLES), "Table module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.CONNECTIVITY), "Connectivity module removes its service during shutdown")

	var existing_input_service := RefCounted.new()
	var failure_services := GFServiceContainer.new()
	failure_services.register(GFServiceIds.INPUT, existing_input_service)
	var failure_manager := _new_module_manager(failure_services)
	var invalid_input_module := GFInputModule.new()
	var invalid_input_settings := GFInputSettings.new()
	invalid_input_settings.managed_actions = [&"gf_missing_action"]
	invalid_input_module.configure(invalid_input_settings)
	failure_manager.install(invalid_input_module)
	_expect(failure_manager.initialize_all() == ERR_INVALID_DATA, "Invalid input configuration fails before module startup")
	_expect(
		is_same(failure_services.resolve(GFServiceIds.INPUT), existing_input_service),
		"Input rollback preserves a service it does not own",
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


func _test_ui_service() -> void:
	var ui := GFUIService.new(self, "TestUI")
	var layer := GFUILayerDefinition.new()
	layer.layer_id = &"screen"
	layer.canvas_layer = 10
	_expect(ui.register_layer(layer) == OK, "UI layer can be registered")
	_expect(ui.register_layer(layer) == ERR_ALREADY_EXISTS, "Duplicate UI layer is rejected")

	var route_a := GFUIRoute.new()
	route_a.route_id = &"screen.a"
	route_a.layer_id = layer.layer_id
	route_a.scene = load("res://tests/fixtures/tracking_view.tscn")
	var route_b := GFUIRoute.new()
	route_b.route_id = &"screen.b"
	route_b.layer_id = layer.layer_id
	route_b.scene = route_a.scene
	route_b.singleton = true
	var invalid_root := Node.new()
	var invalid_scene := PackedScene.new()
	var invalid_scene_result := invalid_scene.pack(invalid_root)
	invalid_root.free()
	var invalid_route := GFUIRoute.new()
	invalid_route.route_id = &"screen.invalid"
	invalid_route.layer_id = layer.layer_id
	invalid_route.scene = invalid_scene
	_expect(
		ui.register_route(route_a) == OK and ui.register_route(route_b) == OK,
		"UI routes can be registered",
	)
	_expect(
		invalid_scene_result == OK and ui.register_route(invalid_route) == OK,
		"UI route validation accepts any PackedScene before instantiation",
	)
	_expect(ui.unregister_layer(layer.layer_id) == ERR_ALREADY_IN_USE, "UI layer with routes cannot be removed")

	var first := ui.open(route_a.route_id, {"index": 1}) as GFTrackingTestView
	_expect(first != null and first.lifecycle == GFUIView.Lifecycle.OPENED, "UI push opens a configured view")
	var second := ui.open(route_b.route_id, {"index": 2}) as GFTrackingTestView
	_expect(first.lifecycle == GFUIView.Lifecycle.SUSPENDED, "UI push suspends previous layer top")
	_expect(second.lifecycle == GFUIView.Lifecycle.OPENED and ui.top(layer.layer_id) == second, "UI top tracks latest view")
	_expect(ui.open(route_b.route_id) == second, "Singleton UI route reuses open instance")
	_expect(ui.stack_size(layer.layer_id) == 2, "Singleton reuse does not grow UI stack")
	var third := ui.open(route_a.route_id, {"index": 3}) as GFTrackingTestView
	_expect(ui.open(route_b.route_id, "focused") == second, "Singleton UI route can be focused again")
	_expect(
		second.lifecycle == GFUIView.Lifecycle.OPENED and ui.top(layer.layer_id) == second,
		"Reopened singleton view returns to the top",
	)
	_expect(third.lifecycle == GFUIView.Lifecycle.SUSPENDED, "Focusing singleton suspends previous top")
	_expect(ui.close(first, "background") == OK, "UI can close a non-top view")
	_expect(second.lifecycle == GFUIView.Lifecycle.OPENED, "Closing non-top view does not resume another view")
	second.request_close("accepted")
	_expect(ui.stack_size(layer.layer_id) == 1, "View close request removes top from stack")
	_expect(second.trace.back() == ["closed", "accepted"], "View close result reaches lifecycle callback")
	_expect(third.lifecycle == GFUIView.Lifecycle.OPENED, "Closing focused singleton resumes previous view")
	ui.pop(layer.layer_id)

	var replacement_source := ui.open(route_a.route_id, 1) as GFTrackingTestView
	var replacement := ui.open(route_b.route_id, 2, GFUIService.OpenMode.REPLACE_TOP) as GFTrackingTestView
	_expect(replacement_source.lifecycle == GFUIView.Lifecycle.CLOSED, "Replace mode closes previous top")
	_expect(replacement != null and ui.stack_size(layer.layer_id) == 1, "Replace mode leaves one new top")
	_expect(ui.pop(layer.layer_id, 3) == OK and replacement.trace.back() == ["closed", 3], "UI pop closes layer top")
	var stable := ui.open(route_a.route_id) as GFTrackingTestView
	_expect(
		ui.open(invalid_route.route_id, null, GFUIService.OpenMode.REPLACE_TOP) == null
		and ui.top(layer.layer_id) == stable
		and stable.lifecycle == GFUIView.Lifecycle.OPENED,
		"Invalid replacement scene preserves the current UI view",
	)
	ui.pop(layer.layer_id)
	_expect(ui.open(&"missing") == null and ui.last_error.contains("Unknown"), "Unknown UI route fails explicitly")
	ui.shutdown()


func _test_audio_service() -> void:
	var starts: Array[float] = []
	var stops := [0]
	var audio := GFAudioService.new(
		self,
		"TestAudio",
		Callable(),
		func(_player: AudioStreamPlayer, position: float) -> void: starts.append(position),
		func(_player: AudioStreamPlayer) -> void: stops[0] += 1,
	)
	var group := GFAudioGroupDefinition.new()
	group.group_id = &"sfx"
	group.max_voices = 1
	group.volume_db = -3.0
	group.overflow_policy = GFAudioGroupDefinition.OverflowPolicy.REJECT_NEW
	_expect(audio.register_group(group) == OK, "Audio group can be registered")
	_expect(audio.register_group(group) == ERR_ALREADY_EXISTS, "Duplicate audio group is rejected")

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray([128, 128, 128, 128])
	var first_handle := audio.play(stream, group.group_id, &"click", -2.0, 1.25)
	var first_player := audio.get_player(first_handle)
	_expect(first_handle > 0 and first_player != null, "Audio playback returns a live handle")
	_expect(starts == [0.0], "Audio service starts its player")
	_expect(first_player.bus == &"Master", "Audio playback uses configured bus")
	_expect(is_equal_approx(first_player.volume_db, -5.0), "Audio playback combines group and request volume")
	_expect(is_equal_approx(first_player.pitch_scale, 1.25), "Audio playback applies pitch")
	_expect(audio.play(stream, group.group_id, &"rejected") == 0, "Reject policy enforces audio voice limit")
	_expect(audio.set_group_paused(group.group_id, true) == OK, "Audio group pause state can change")
	_expect(audio.set_group_volume_db(group.group_id, -6.0) == OK, "Audio group volume can change")
	_expect(is_equal_approx(first_player.volume_db, -8.0), "Audio group volume preserves request offset")
	_expect(is_equal_approx(group.volume_db, -3.0), "Runtime audio volume does not mutate authored settings")
	_expect(audio.stop(first_handle), "Audio playback can be stopped by handle")
	_expect(not audio.is_active(first_handle) and audio.active_count(group.group_id) == 0, "Stopped audio releases its handle")
	_expect(stops[0] == 1, "Audio service invokes the configured playback stopper")

	group.overflow_policy = GFAudioGroupDefinition.OverflowPolicy.STOP_OLDEST
	var old_handle := audio.play(stream, group.group_id, &"old")
	var new_handle := audio.play(stream, group.group_id, &"new")
	_expect(old_handle > 0 and new_handle > old_handle, "Overflow policy starts replacement playback")
	_expect(not audio.is_active(old_handle) and audio.is_active(new_handle), "Stop-oldest policy releases previous voice")
	_expect(audio.stop_group(group.group_id, &"new") == 1, "Audio group can stop playbacks by tag")
	_expect(audio.unregister_group(group.group_id) == OK, "Inactive audio group can be removed")
	_expect(audio.play(stream, &"missing") == 0, "Unknown audio group is rejected")
	audio.shutdown()
	await get_tree().process_frame


func _test_input_service() -> void:
	var action_a := &"gf_test_action_a"
	var action_b := &"gf_test_action_b"
	InputMap.add_action(action_a)
	InputMap.add_action(action_b)
	var default_key := InputEventKey.new()
	default_key.physical_keycode = KEY_A
	InputMap.action_add_event(action_a, default_key)
	var input_service := GFInputService.new([action_a, action_b])
	_expect(input_service.has_action(action_a), "Input service manages configured actions")
	_expect(input_service.events_for(action_a).size() == 1, "Input service captures action events")

	var key_b := InputEventKey.new()
	key_b.physical_keycode = KEY_B
	_expect(input_service.add_binding(action_b, key_b) == OK, "Input binding can be added")
	_expect(input_service.add_binding(action_b, key_b) == ERR_ALREADY_EXISTS, "Equivalent input binding is rejected")
	_expect(input_service.find_conflicts(key_b) == [action_b], "Input conflicts are reported across managed actions")
	_expect(input_service.find_conflicts(key_b, action_b).is_empty(), "Input conflict query can exclude an action")

	var profile := input_service.capture_profile()
	_expect(profile.actions.has(str(action_a)) and profile.actions.has(str(action_b)), "Input profile captures managed actions")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	_expect(input_service.rebind(action_a, [mouse]) == OK, "Input action can be rebound")
	_expect(input_service.has_equivalent_binding(action_a, mouse), "Rebound input event is active")
	_expect(input_service.apply_profile(profile) == OK, "Input profile can be reapplied")
	_expect(input_service.has_equivalent_binding(action_a, default_key), "Input profile restores encoded key event")
	_expect(input_service.restore_defaults(action_a) == OK, "Input action restores captured default")
	_expect(input_service.remove_binding(action_b, key_b) == OK, "Input binding can be removed")
	_expect(input_service.remove_binding(action_b, key_b) == ERR_DOES_NOT_EXIST, "Missing input binding reports error")
	_expect(input_service.apply_profile({"version": 99, "actions": {}}) == ERR_INVALID_DATA, "Unsupported input profile is rejected")
	InputMap.erase_action(action_a)
	InputMap.erase_action(action_b)


func _test_localization_service() -> void:
	var previous_locale := TranslationServer.get_locale()
	var localization := GFLocalizationService.new(PackedStringArray(["en_US", "zh_CN"]), "en_US")
	_expect(localization.supported_locales() == PackedStringArray(["en_US", "zh_CN"]), "Locales are standardized and deduplicated")
	_expect(localization.choose_best_locale("zh_TW") == "zh_CN", "Locale selection falls back by language")
	_expect(localization.choose_best_locale("fr_FR") == "en_US", "Locale selection falls back to configured locale")
	_expect(localization.set_locale("fr_FR") == ERR_DOES_NOT_EXIST, "Unsupported locale is rejected")

	var english := Translation.new()
	english.locale = "en_US"
	english.add_message(&"framework.test.hello", "Hello {name}")
	var chinese := Translation.new()
	chinese.locale = "zh_CN"
	chinese.add_message(&"framework.test.hello", "Ni Hao {name}")
	_expect(localization.add_translation(english) == OK, "Translation can be registered")
	_expect(localization.add_translation(english) == ERR_ALREADY_EXISTS, "Duplicate translation resource is rejected")
	_expect(localization.add_translation(chinese) == OK, "Second locale translation can be registered")
	_expect(localization.set_locale("zh_CN") == OK, "Supported locale can be selected")
	_expect(localization.translate(&"framework.test.hello") == "Ni Hao {name}", "Translation resolves current locale")
	_expect(localization.format(&"framework.test.hello", {"name": "Codex"}) == "Ni Hao Codex", "Localized string can be formatted")
	_expect(localization.has_message(&"framework.test.hello", "en_US"), "Translation key existence can be checked")
	var missing := localization.validate_messages([&"framework.test.hello", &"framework.test.missing"])
	_expect(missing["en_US"] == [&"framework.test.missing"], "Translation validation reports missing English key")
	_expect(missing["zh_CN"] == [&"framework.test.missing"], "Translation validation reports missing Chinese key")
	_expect(localization.remove_translation(chinese), "Owned translation can be removed")
	_expect(not localization.remove_translation(chinese), "Removed translation is no longer owned")
	localization.shutdown()
	TranslationServer.set_locale(previous_locale)


func _test_resource_service() -> void:
	var resources := GFResourceService.new()
	var config_path := "res://addons/godot_framework/config/default_framework_config.tres"
	var loaded := resources.load(config_path)
	_expect(loaded is GFFrameworkConfig, "Resource service loads typed Godot resources")
	_expect(is_same(loaded, resources.get_cached(loaded.resource_path)), "Resource service caches loaded resource")
	_expect(resources.release(loaded.resource_path), "Resource cache entry can be released")
	var legacy_cached := resources.load(config_path)
	var lease_over_legacy := resources.acquire(config_path)
	lease_over_legacy.release()
	_expect(
		legacy_cached != null and resources.has_cached(config_path),
		"Leased handle does not evict a cache entry retained by legacy load",
	)
	resources.release(config_path)

	var first_lease := resources.acquire(config_path)
	var second_lease := resources.acquire(config_path)
	_expect(
		first_lease != null and second_lease != null and is_same(first_lease.resource, second_lease.resource),
		"Leased resource handles share a framework cache entry",
	)
	_expect(resources.lease_count(config_path) == 2, "Resource service counts active leases")
	_expect(not resources.release(config_path), "Manual cache release cannot evict an active lease")
	first_lease.release()
	_expect(
		resources.lease_count(config_path) == 1 and resources.has_cached(config_path),
		"Releasing one resource handle preserves other leases",
	)
	second_lease.release()
	_expect(not resources.has_cached(config_path), "Last leased handle evicts an unretained resource")
	second_lease.release()
	_expect(
		resources.lease_count(config_path) == 0 and not resources.has_cached(config_path),
		"Repeated resource handle release is harmless",
	)

	var retained := resources.acquire(config_path, "", GFResourceHandle.CachePolicy.RETAINED)
	_expect(retained != null and resources.is_retained(config_path), "Retained handle marks its cache entry")
	retained.release()
	_expect(resources.has_cached(config_path), "Releasing retained handle keeps its cache entry")
	_expect(resources.release(config_path), "Retained cache entry can be explicitly released")
	var transient := resources.acquire(config_path, "", GFResourceHandle.CachePolicy.TRANSIENT)
	_expect(transient != null and not resources.has_cached(config_path), "Transient handle bypasses framework cache")
	transient.release()
	_expect(transient.is_released() and transient.resource == null, "Released resource handle drops resource ownership")
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


func _test_download_service() -> void:
	var base_directory := "user://gf_framework_download_tests"
	var settings := GFDownloadSettings.new()
	settings.base_directory = base_directory
	settings.max_concurrent = 2
	settings.retry_count = 1
	var unsafe_download_settings := GFDownloadSettings.new()
	unsafe_download_settings.base_directory = "user://../outside"
	_expect(not unsafe_download_settings.validate().is_empty(), "Download settings reject user directory escape")
	var payload := "download payload".to_utf8_buffer()
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(payload)
	var payload_hash := hasher.finish().hex_encode()
	var plans: Array[Dictionary] = [
		{"response_code": 500, "data": "retry".to_utf8_buffer()},
		{"response_code": 200, "data": "second".to_utf8_buffer()},
		{"response_code": 200, "data": payload},
		{"response_code": 200, "data": "bad hash".to_utf8_buffer()},
		{
			"response_code": 200,
			"data": "cancelled".to_utf8_buffer(),
			"auto_complete": false,
			"write_on_start": true,
		},
	]
	var downloads := GFDownloadService.new(
		self,
		settings,
		func(): return GFTestDownloadBackend.new().setup(plans.pop_front()),
	)
	_expect(downloads.enqueue("file:///unsafe", "bad.bin") == 0, "Download queue rejects non-HTTP URLs")
	_expect(downloads.enqueue("https://example.test/file", "../bad.bin") == 0, "Download queue rejects traversal paths")
	_expect(downloads.enqueue("https://example.test/file", "C:/bad.bin") == 0, "Download queue rejects drive-qualified paths")
	_expect(downloads.enqueue("https://example.test/file", "bad.bin", "xyz") == 0, "Download queue rejects malformed hashes")

	var first_id := downloads.enqueue(
		"https://example.test/first",
		"content/first.bin",
		payload_hash,
		payload.size(),
	)
	var second_id := downloads.enqueue("https://example.test/second", "content/second.bin")
	_expect(
		downloads.enqueue("https://example.test/duplicate", "content/first.bin") == 0,
		"Download queue rejects concurrent ownership of one target",
	)
	downloads.update()
	_expect(downloads.active_count() == 2, "Download queue enforces configured parallel dispatch")
	await get_tree().process_frame
	downloads.update()
	await get_tree().process_frame
	downloads.update()
	_expect(downloads.task_state(first_id) == GFDownloadService.TaskState.COMPLETED, "Retryable HTTP failure is retried")
	_expect(int(downloads.task_info(first_id).attempts) == 2, "Download task records retry attempts")
	_expect(downloads.task_state(second_id) == GFDownloadService.TaskState.COMPLETED, "Parallel download completes")
	_expect(
		FileAccess.get_file_as_bytes(base_directory.path_join("content/first.bin")) == payload,
		"Validated download is committed to its target",
	)

	settings.retry_count = 0
	var bad_target := base_directory.path_join("content/bad.bin")
	var existing := FileAccess.open(bad_target, FileAccess.WRITE)
	existing.store_string("existing")
	existing.flush()
	existing = null
	var bad_id := downloads.enqueue(
		"https://example.test/bad",
		"content/bad.bin",
		payload_hash,
	)
	downloads.update()
	await get_tree().process_frame
	downloads.update()
	_expect(downloads.task_state(bad_id) == GFDownloadService.TaskState.FAILED, "Checksum mismatch fails download")
	_expect(FileAccess.get_file_as_string(bad_target) == "existing", "Failed download preserves existing target")

	var cancelled_id := downloads.enqueue("https://example.test/cancel", "content/cancel.bin")
	downloads.update()
	_expect(downloads.task_state(cancelled_id) == GFDownloadService.TaskState.RUNNING, "Download can enter running state")
	_expect(FileAccess.file_exists(str(downloads.task_info(cancelled_id).temp_path)), "Running download may own a partial file")
	_expect(downloads.cancel(cancelled_id), "Running download can be cancelled")
	_expect(downloads.task_state(cancelled_id) == GFDownloadService.TaskState.CANCELLED, "Cancelled download reaches terminal state")
	_expect(not FileAccess.file_exists(base_directory.path_join("content/cancel.bin")), "Cancelled download removes partial file")
	_expect(downloads.clear_finished() == 4, "Finished download history can be cleared")
	downloads.shutdown()
	await get_tree().process_frame
	DirAccess.remove_absolute(base_directory.path_join("content/first.bin"))
	DirAccess.remove_absolute(base_directory.path_join("content/second.bin"))
	DirAccess.remove_absolute(bad_target)
	DirAccess.remove_absolute(base_directory.path_join("content"))
	DirAccess.remove_absolute(base_directory)


func _test_content_service() -> void:
	var base_directory := "user://gf_framework_content_tests"
	var crypto := Crypto.new()
	var private_key := crypto.generate_rsa(2048)
	_expect(private_key != null, "Content test can generate an RSA key")
	var settings := GFContentSettings.new()
	settings.base_directory = base_directory
	settings.public_key_pem = private_key.save_to_string(true)
	settings.require_signature = true
	settings.auto_mount_active = false
	var unsafe_content_settings := GFContentSettings.new()
	unsafe_content_settings.base_directory = "user://../outside"
	unsafe_content_settings.require_signature = false
	_expect(not unsafe_content_settings.validate().is_empty(), "Content settings reject user directory escape")

	var first_data := "first pack".to_utf8_buffer()
	var first_path := base_directory.path_join("releases/v1/base.pck")
	_expect(_write_test_file(first_path, first_data) == OK, "Content test pack can be staged")
	var first_manifest := JSON.stringify({
		"schema_version": 1,
		"release_id": "v1",
		"packs": [{
			"id": "base",
			"path": "base.pck",
			"sha256": _sha256_bytes(first_data),
			"size": first_data.size(),
			"replace_files": true,
		}],
	})
	var first_signature := crypto.sign(HashingContext.HASH_SHA256, first_manifest.sha256_buffer(), private_key)
	var mounted_paths: Array[String] = []
	var content := GFContentService.new(
		settings,
		func(path: String, _replace: bool, _offset: int) -> bool:
			mounted_paths.append(path)
			return true,
	)
	_expect(content.initialization_error() == OK, "Content service loads configured public key")
	_expect(content.release_directory("v1").ends_with("/releases/v1"), "Content service exposes a safe release staging directory")
	_expect(content.pack_path("v1", "../bad.pck").is_empty(), "Content service rejects unsafe staged pack path")
	_expect(
		content.install_release(first_manifest, PackedByteArray([1, 2, 3])) == ERR_UNAUTHORIZED,
		"Content installation rejects an invalid detached signature",
	)
	_expect(content.install_release(first_manifest, first_signature) == OK, "Signed content release can be installed")
	_expect(content.validate_release("v1") == OK, "Installed content release can be revalidated")
	_expect(content.activate_release("v1") == OK, "Installed content release can be activated")
	_expect(content.mount_active() == OK and content.mounted_release == "v1", "Active content release mounts all packs")
	_expect(mounted_paths == [first_path], "Content mount uses the validated release path")

	var second_a := "second a".to_utf8_buffer()
	var second_b := "second b".to_utf8_buffer()
	var second_a_path := base_directory.path_join("releases/v2/a.pck")
	var second_b_path := base_directory.path_join("releases/v2/b.pck")
	_write_test_file(second_a_path, second_a)
	_write_test_file(second_b_path, second_b)
	var second_manifest := JSON.stringify({
		"schema_version": 1,
		"release_id": "v2",
		"packs": [
			{
				"id": "a",
				"path": "a.pck",
				"sha256": _sha256_bytes(second_a),
				"size": second_a.size(),
			},
			{
				"id": "b",
				"path": "b.pck",
				"sha256": _sha256_bytes(second_b),
				"size": second_b.size(),
			},
		],
	})
	var second_signature := crypto.sign(HashingContext.HASH_SHA256, second_manifest.sha256_buffer(), private_key)
	_expect(content.install_release(second_manifest, second_signature) == OK, "Second signed content release can be installed")
	_expect(content.activate_release("v2") == OK and content.restart_required, "Switching mounted content schedules a restart")

	var mount_attempts := [0]
	var failing_content := GFContentService.new(
		settings,
		func(_path: String, _replace: bool, _offset: int) -> bool:
			mount_attempts[0] += 1
			return mount_attempts[0] == 1,
	)
	_expect(failing_content.mount_active() == ERR_CANT_OPEN, "Partial content mount failure is reported")
	_expect(failing_content.restart_required, "Partial content mount failure requires process restart")
	_expect(
		failing_content.mount_active() == ERR_ALREADY_IN_USE,
		"Partial content mount locks further mounts in the current process",
	)
	_expect(
		failing_content.activation_state().active == "v1"
		and failing_content.activation_state().previous == "v2",
		"Failed activation restores previous release for next startup",
	)
	_expect(failing_content.rollback() == OK, "Content activation can roll back to previous release")
	_expect(failing_content.activation_state().active == "v2", "Explicit rollback swaps active and previous releases")

	var unsafe_manifest := JSON.stringify({
		"schema_version": 1,
		"release_id": "unsafe",
		"packs": [{
			"id": "bad",
			"path": "../bad.pck",
			"sha256": _sha256_bytes(first_data),
			"size": first_data.size(),
		}],
	})
	var unsafe_signature := crypto.sign(HashingContext.HASH_SHA256, unsafe_manifest.sha256_buffer(), private_key)
	_expect(
		content.install_release(unsafe_manifest, unsafe_signature) == ERR_INVALID_DATA,
		"Content manifest rejects traversal paths",
	)
	var corrupt_state := FileAccess.open(base_directory.path_join("activation.json"), FileAccess.WRITE)
	corrupt_state.store_string("not json")
	corrupt_state.flush()
	corrupt_state = null
	var corrupt_content := GFContentService.new(settings, func(_path: String, _replace: bool, _offset: int) -> bool: return true)
	_expect(corrupt_content.mount_active() == ERR_INVALID_DATA, "Corrupt activation state fails closed")
	content.shutdown()
	failing_content.shutdown()
	corrupt_content.shutdown()

	DirAccess.remove_absolute(base_directory.path_join("activation.json"))
	DirAccess.remove_absolute(base_directory.path_join("releases/v1/release.json"))
	DirAccess.remove_absolute(first_path)
	DirAccess.remove_absolute(base_directory.path_join("releases/v1"))
	DirAccess.remove_absolute(base_directory.path_join("releases/v2/release.json"))
	DirAccess.remove_absolute(second_a_path)
	DirAccess.remove_absolute(second_b_path)
	DirAccess.remove_absolute(base_directory.path_join("releases/v2"))
	DirAccess.remove_absolute(base_directory.path_join("releases"))
	DirAccess.remove_absolute(base_directory)


func _test_table_service() -> void:
	var tables := GFTableService.new()
	var provider := GFMemoryTestTableProvider.new()
	_expect(tables.register_provider(&"memory", provider) == OK, "Table provider can be registered")
	_expect(tables.register_provider(&"memory", provider) == ERR_ALREADY_EXISTS, "Duplicate table provider is rejected")
	_expect(
		tables.load_table(&"memory", &"items", {1: {"name": "Potion"}, 2: {"name": "Sword"}}) == OK,
		"Table service delegates loading to its provider",
	)
	_expect(tables.has_table(&"memory", &"items"), "Table service reports loaded provider table")
	_expect(tables.get_row(&"memory", &"items", 1).name == "Potion", "Table service delegates keyed row lookup")
	_expect(tables.get_row(&"memory", &"items", 9, "missing") == "missing", "Table lookup preserves caller default")
	_expect(tables.get_all(&"memory", &"items").size() == 2, "Table service delegates full table reads")
	_expect(tables.unload_table(&"memory", &"items") and not tables.has_table(&"memory", &"items"), "Table service delegates unload")
	_expect(tables.load_table(&"missing", &"items", {}) == ERR_DOES_NOT_EXIST, "Unknown table provider fails explicitly")
	_expect(not tables.unregister_provider(&"memory", GFMemoryTestTableProvider.new()), "Table provider unregister checks owner identity")
	_expect(tables.unregister_provider(&"memory", provider) and provider.cleared, "Owned table provider is cleared on removal")
	tables.shutdown()


func _test_connectivity_service() -> void:
	var invalid_settings := GFConnectivitySettings.new()
	invalid_settings.http_request_body_limit_bytes = 8
	invalid_settings.http_max_queued_body_bytes = 4
	_expect(not invalid_settings.validate().is_empty(), "Connectivity settings reject inconsistent HTTP byte limits")
	var invalid_capacity := GFConnectivitySettings.new()
	invalid_capacity.http_max_concurrent = 2
	invalid_capacity.http_max_in_flight_requests = 1
	_expect(not invalid_capacity.validate().is_empty(), "Connectivity settings reject in-flight capacity below concurrency")
	var invalid_channel := GFWebSocketChannelDefinition.new()
	invalid_channel.channel_id = &"invalid"
	invalid_channel.url = "https://example.test/socket"
	_expect(not invalid_channel.validate().is_empty(), "WebSocket channel rejects non-WebSocket URLs")
	var default_channel := GFWebSocketChannelDefinition.new()
	default_channel.channel_id = &"default"
	default_channel.url = "wss://example.test/socket"
	_expect(default_channel.validate().is_empty(), "WebSocket channel defaults form a valid bounded configuration")

	var settings := GFConnectivitySettings.new()
	settings.root_name = "ConnectivityServiceTest"
	settings.http_max_concurrent = 1
	settings.http_max_in_flight_requests = 2
	settings.http_request_body_limit_bytes = 8
	settings.http_max_queued_body_bytes = 8
	settings.http_response_body_limit_bytes = 32
	settings.http_timeout_seconds = 0.5
	settings.request_timeout_seconds = 0.5
	var factory := GFConnectivityTestBackendFactory.new()
	factory.http_plans = [
		{"response_code": 503, "body": "busy".to_utf8_buffer()},
		{},
		{},
		{"body": "x".repeat(33).to_utf8_buffer()},
	]
	var service := GFConnectivityService.new(
		self,
		settings,
		factory.create_http,
		factory.create_websocket,
	)
	var completed_http: Array[int] = []
	var failed_http: Array[Dictionary] = []
	service.http.request_completed.connect(
		func(request_id: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray, _tag: StringName) -> void:
			completed_http.append(request_id)
	)
	service.http.request_failed.connect(
		func(request_id: int, error: Error, _result: int, _code: int, _tag: StringName) -> void:
			failed_http.append({"id": request_id, "error": error})
	)
	_expect(service.http.request("file:///unsafe") == 0, "HTTP queue rejects non-HTTP URLs")
	_expect(
		service.http.request("https://example.test/large", HTTPClient.METHOD_POST, PackedStringArray(), PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8])) == 0,
		"HTTP queue rejects oversized request bodies",
	)
	var first_body := "first".to_utf8_buffer()
	var first_id := service.http.request(
		"https://example.test/first",
		HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/octet-stream"]),
		first_body,
		0.25,
		&"batch",
	)
	var second_id := service.http.request("https://example.test/second", HTTPClient.METHOD_GET, PackedStringArray(), PackedByteArray(), -1.0, &"batch")
	_expect(first_id > 0 and second_id > first_id, "HTTP queue assigns monotonic request IDs")
	_expect(
		service.http.active_count() == 1 and service.http.queued_count() == 1 and service.http.in_flight_count() == 2,
		"HTTP queue enforces bounded concurrency and total in-flight capacity",
	)
	_expect(service.http.request("https://example.test/full") == 0, "HTTP queue rejects overflow")
	var first_backend := factory.created_http[0]
	_expect(
		first_backend.captured.url == "https://example.test/first"
		and first_backend.captured.method == HTTPClient.METHOD_POST
		and first_backend.captured.body == first_body
		and is_equal_approx(float(first_backend.captured.timeout_seconds), 0.25),
		"HTTP backend receives raw request data and per-request timeout",
	)
	first_backend.complete()
	_expect(
		service.http.task_state(first_id) == GFHTTPService.TaskState.COMPLETED
		and int(service.http.task_info(first_id).response_code) == 503
		and completed_http == [first_id],
		"HTTP transport completion preserves response status for application interpretation",
	)
	_expect(service.http.task_state(second_id) == GFHTTPService.TaskState.RUNNING, "HTTP queue dispatches the next task after completion")
	_expect(service.http.cancel(second_id), "Running HTTP request can be cancelled")
	_expect(service.http.task_state(second_id) == GFHTTPService.TaskState.CANCELLED, "Cancelled HTTP request reaches terminal state")
	var timeout_id := service.http.request("https://example.test/timeout", HTTPClient.METHOD_GET, PackedStringArray(), PackedByteArray(), 0.1)
	service.update(0.11)
	_expect(
		service.http.task_state(timeout_id) == GFHTTPService.TaskState.FAILED
		and not failed_http.is_empty()
		and failed_http.back().error == ERR_TIMEOUT,
		"HTTP service enforces framework timeout and reports transport failure",
	)
	var oversized_response_id := service.http.request("https://example.test/oversized-response")
	(factory.created_http[3] as GFTestHTTPRequestBackend).complete()
	_expect(
		service.http.task_state(oversized_response_id) == GFHTTPService.TaskState.FAILED
		and failed_http.back().error == ERR_OUT_OF_MEMORY,
		"HTTP service enforces response limit across custom backends",
	)
	_expect(service.http.clear_finished() == 4, "HTTP service can clear terminal request history")

	var tracker := service.requests
	var resolved: Array[int] = []
	var timed_out: Array[int] = []
	var cancelled: Array[int] = []
	tracker.request_resolved.connect(func(id: int, _response: Variant, _context: Variant) -> void: resolved.append(id))
	tracker.request_timed_out.connect(func(id: int, _context: Variant) -> void: timed_out.append(id))
	tracker.request_cancelled.connect(func(id: int, _context: Variant) -> void: cancelled.append(id))
	var resolve_id := tracker.begin(1.0, {"operation": "resolve"})
	var timeout_correlation_id := tracker.begin(0.1, {"operation": "timeout"})
	var cancel_id := tracker.begin(0.0, {"operation": "cancel"})
	_expect(tracker.resolve(resolve_id, PackedByteArray([1])) and resolved == [resolve_id], "Correlation tracker resolves one pending request")
	tracker.update(0.11)
	_expect(not tracker.has(timeout_correlation_id) and timed_out == [timeout_correlation_id], "Correlation tracker expires timed requests")
	_expect(tracker.cancel(cancel_id) and cancelled == [cancel_id], "Correlation tracker cancels an indefinite request")
	_expect(not tracker.resolve(resolve_id), "Resolved correlation ID cannot complete twice")

	var primary := GFWebSocketChannelDefinition.new()
	primary.channel_id = &"primary"
	primary.url = "wss://example.test/socket"
	primary.handshake_headers = PackedStringArray(["Authorization: test"])
	primary.supported_protocols = PackedStringArray(["gf-test"])
	primary.reconnect_enabled = true
	primary.reconnect_initial_delay_seconds = 0.5
	primary.reconnect_max_delay_seconds = 2.0
	primary.reconnect_multiplier = 2.0
	primary.max_reconnect_attempts = 3
	primary.heartbeat_interval_seconds = 5.0
	primary.inbound_buffer_size = 2048
	primary.outbound_buffer_size = 1024
	primary.max_queued_packets = 8
	primary.max_packet_bytes = 8
	primary.receive_packet_budget_per_frame = 1
	primary.send_high_watermark_bytes = 10
	primary.send_low_watermark_bytes = 3
	var flaky := primary.duplicate() as GFWebSocketChannelDefinition
	flaky.channel_id = &"flaky"
	flaky.reconnect_initial_delay_seconds = 1.0
	flaky.reconnect_max_delay_seconds = 4.0
	flaky.max_reconnect_attempts = 2
	var slow := primary.duplicate() as GFWebSocketChannelDefinition
	slow.channel_id = &"slow"
	slow.reconnect_enabled = false
	slow.connect_timeout_seconds = 0.1
	var stalled_close := primary.duplicate() as GFWebSocketChannelDefinition
	stalled_close.channel_id = &"stalled_close"
	stalled_close.reconnect_enabled = false
	stalled_close.close_timeout_seconds = 0.1
	factory.websocket_plans = {
		&"primary": [
			{
				"poll_states": [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CLOSED],
				"selected_protocol": "gf-test",
				"close_code": 1006,
				"close_reason": "lost",
				"incoming": [
					{"error": OK, "data": "one".to_utf8_buffer(), "is_text": true},
					{"error": OK, "data": PackedByteArray([1, 2]), "is_text": false},
				],
			},
			{"poll_states": [WebSocketPeer.STATE_OPEN]},
		],
		&"flaky": [
			{"connect_error": ERR_CANT_CONNECT},
			{"connect_error": ERR_CANT_CONNECT},
			{"connect_error": ERR_CANT_CONNECT},
		],
		&"slow": [{}],
		&"stalled_close": [{
			"poll_states": [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSING],
			"close_immediately": false,
		}],
	}
	var sockets := service.websockets
	var received: Array[Dictionary] = []
	var writable: Array[StringName] = []
	var reconnect_delays: Array[float] = []
	var exhausted: Array[StringName] = []
	sockets.packet_received.connect(func(channel_id: StringName, data: PackedByteArray, is_text: bool) -> void:
		received.append({"channel_id": channel_id, "data": data, "is_text": is_text})
	)
	sockets.channel_writable.connect(func(channel_id: StringName) -> void: writable.append(channel_id))
	sockets.reconnect_scheduled.connect(func(_channel_id: StringName, _attempt: int, delay: float) -> void: reconnect_delays.append(delay))
	sockets.reconnect_exhausted.connect(func(channel_id: StringName, _attempts: int) -> void: exhausted.append(channel_id))
	_expect(sockets.register_channel(primary) == OK, "WebSocket channel can be registered")
	_expect(sockets.register_channel(primary) == ERR_ALREADY_EXISTS, "Duplicate WebSocket channel is rejected")
	primary.url = "https://mutated.invalid"
	_expect(sockets.connect_channel(&"primary") == OK, "WebSocket channel begins a non-blocking connection")
	sockets.update(0.1)
	var primary_backend := (factory.created_websockets[&"primary"] as Array)[0] as GFTestWebSocketBackend
	_expect(
		sockets.state(&"primary") == GFWebSocketService.ChannelState.CONNECTED
		and primary_backend.connected_url == "wss://example.test/socket"
		and primary_backend.configured.heartbeat_interval == 5.0
		and primary_backend.configured.protocols == PackedStringArray(["gf-test"]),
		"WebSocket service owns validated configuration and observes open state",
	)
	_expect(received.size() == 1 and received[0].is_text, "WebSocket receive budget limits packets per update")
	sockets.update(0.1)
	_expect(received.size() == 2 and not received[1].is_text, "WebSocket service preserves text and binary frame metadata")
	_expect(sockets.send_text(&"primary", "ping") == OK, "WebSocket channel sends raw text frames")
	_expect(sockets.send(&"primary", PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8])) == ERR_OUT_OF_MEMORY, "WebSocket channel rejects oversized packets")
	primary_backend.buffered_bytes = 8
	_expect(sockets.send(&"primary", PackedByteArray([1, 2, 3])) == ERR_BUSY, "WebSocket high watermark applies send backpressure")
	_expect(sockets.send(&"primary", PackedByteArray([1])) == ERR_BUSY, "Blocked WebSocket remains blocked until low watermark")
	primary_backend.buffered_bytes = 2
	sockets.update(0.1)
	_expect(writable == [&"primary"], "WebSocket low watermark emits writable transition")
	_expect(sockets.send(&"primary", PackedByteArray([1])) == OK, "Writable WebSocket accepts binary frames")
	sockets.update(0.1)
	_expect(
		sockets.state(&"primary") == GFWebSocketService.ChannelState.RECONNECT_WAIT
		and reconnect_delays == [0.5],
		"Unexpected WebSocket close schedules configured reconnect",
	)
	sockets.update(0.5)
	_expect(sockets.state(&"primary") == GFWebSocketService.ChannelState.CONNECTING, "Reconnect delay starts a fresh backend")
	sockets.update(0.0)
	var reconnected_backend := (factory.created_websockets[&"primary"] as Array)[1] as GFTestWebSocketBackend
	_expect(
		sockets.state(&"primary") == GFWebSocketService.ChannelState.CONNECTED
		and reconnected_backend.sent.is_empty(),
		"Reconnected WebSocket does not replay application frames",
	)
	_expect(sockets.disconnect_channel(&"primary", 1000, "done") == OK, "WebSocket supports requested close")
	sockets.update(0.0)
	_expect(sockets.state(&"primary") == GFWebSocketService.ChannelState.DISCONNECTED, "Requested WebSocket close does not reconnect")
	_expect(
		sockets.connect_channel(&"primary") == OK
		and sockets.disconnect_channel(&"primary", 1000, "x".repeat(124)) == ERR_INVALID_PARAMETER,
		"WebSocket close rejects reasons above the RFC byte limit",
	)
	sockets.disconnect_channel(&"primary", -1, "")
	sockets.update(0.0)

	_expect(sockets.register_channel(flaky) == OK, "Second WebSocket channel can be registered")
	_expect(sockets.connect_channel(&"flaky") == ERR_CANT_CONNECT, "Immediate WebSocket connection error is propagated")
	_expect(sockets.state(&"flaky") == GFWebSocketService.ChannelState.RECONNECT_WAIT, "Failed WebSocket connection enters reconnect wait")
	sockets.update(1.0)
	_expect(
		sockets.state(&"flaky") == GFWebSocketService.ChannelState.RECONNECT_WAIT
		and reconnect_delays.slice(1) == [1.0, 2.0],
		"WebSocket reconnect delay grows exponentially",
	)
	sockets.update(2.0)
	_expect(
		sockets.state(&"flaky") == GFWebSocketService.ChannelState.DISCONNECTED
		and exhausted == [&"flaky"],
		"WebSocket reconnect attempts stop at the configured limit",
	)
	_expect(sockets.register_channel(slow) == OK and sockets.connect_channel(&"slow") == OK, "Connecting WebSocket can enter timeout fixture")
	sockets.update(0.11)
	_expect(sockets.state(&"slow") == GFWebSocketService.ChannelState.DISCONNECTED, "WebSocket connection timeout closes an unresponsive channel")
	_expect(
		sockets.register_channel(stalled_close) == OK
		and sockets.connect_channel(&"stalled_close") == OK,
		"WebSocket close-timeout fixture can connect",
	)
	sockets.update(0.0)
	sockets.disconnect_channel(&"stalled_close", 1000, "closing")
	sockets.update(0.11)
	_expect(
		sockets.state(&"stalled_close") == GFWebSocketService.ChannelState.DISCONNECTED,
		"WebSocket close timeout force-closes an unresponsive peer",
	)
	var http_service := service.http
	service.shutdown()
	service.shutdown()
	_expect(
		http_service.request("https://example.test/closed") == 0
		and sockets.register_channel(default_channel) == ERR_UNCONFIGURED,
		"Connectivity shutdown is idempotent and rejects new work",
	)


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


func _new_module_manager(service_container: GFServiceContainer = null) -> GFModuleManager:
	var services := service_container if service_container != null else GFServiceContainer.new()
	var events := GFEventBus.new()
	var messages := GFMessageBus.new()
	var logger := GFLogger.new()
	logger.minimum_level = GFLogger.Level.NONE
	var context := GFContext.new(self, services, events, messages, logger)
	return GFModuleManager.new(context)


func _write_test_file(path: String, data: PackedByteArray) -> Error:
	var directory_result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_result != OK:
		return directory_result
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	file.flush()
	return OK


func _sha256_bytes(data: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(data)
	return hasher.finish().hex_encode()


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
