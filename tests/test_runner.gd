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
	_test_optional_module_lifecycle()
	_test_state_machine()
	_test_object_pool()
	_test_ui_service()
	await _test_audio_service()
	_test_input_service()
	_test_localization_service()
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
	_expect(framework.get_service(GFServiceIds.UI) == null, "Optional UI module is disabled by default")
	_expect(framework.get_service(GFServiceIds.AUDIO) == null, "Optional audio module is disabled by default")
	_expect(framework.get_service(GFServiceIds.INPUT) == null, "Optional input module is disabled by default")
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

	_expect(manager.install(ui_module) == OK, "Optional UI module can be installed before its dependency")
	_expect(manager.install(audio_module) == OK, "Optional audio module can be installed")
	_expect(manager.install(input_module) == OK, "Optional input module can be installed")
	_expect(manager.install(localization_module) == OK, "Optional localization module can be installed")
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
	manager.shutdown_all()
	_expect(not services.has(GFServiceIds.UI), "UI module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.AUDIO), "Audio module removes its service during shutdown")
	_expect(not services.has(GFServiceIds.INPUT), "Input module removes its service during shutdown")
	_expect(
		not services.has(GFServiceIds.LOCALIZATION),
		"Localization module removes its service during shutdown",
	)

	var existing_input_service := RefCounted.new()
	var failure_services := GFServiceContainer.new()
	failure_services.register(GFServiceIds.INPUT, existing_input_service)
	var failure_manager := _new_module_manager(failure_services)
	var invalid_input_module := GFInputModule.new()
	var invalid_input_settings := GFInputSettings.new()
	invalid_input_settings.managed_actions = [&"gf_missing_action"]
	invalid_input_module.configure(invalid_input_settings)
	failure_manager.install(invalid_input_module)
	_expect(failure_manager.initialize_all() == ERR_DOES_NOT_EXIST, "Invalid input configuration fails startup")
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


func _new_module_manager(service_container: GFServiceContainer = null) -> GFModuleManager:
	var services := service_container if service_container != null else GFServiceContainer.new()
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
