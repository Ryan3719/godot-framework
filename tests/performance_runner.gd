extends Node

const DISASTER_THRESHOLD_USEC := 30_000_000

var _results: Dictionary = {}
var _failed := false


func _ready() -> void:
	await get_tree().process_frame
	_benchmark_event_publish()
	_benchmark_message_dispatch()
	_benchmark_service_resolve()
	_benchmark_request_tracking()
	_benchmark_module_resolution()
	print("[BENCHMARK] %s" % JSON.stringify(_results))
	if _failed:
		push_error("[BENCHMARK] Catastrophic regression threshold exceeded.")
		get_tree().quit(1)
		return
	print("[BENCHMARK] PASS: framework performance smoke test")
	get_tree().quit(0)


func _benchmark_event_publish() -> void:
	var bus := GFEventBus.new()
	var received := [0]
	bus.subscribe(&"benchmark.event", func(_payload: Variant) -> void: received[0] += 1)
	var started := Time.get_ticks_usec()
	for index in 10_000:
		bus.publish(&"benchmark.event", index)
	_record(&"event_publish_10k", Time.get_ticks_usec() - started, received[0] == 10_000)


func _benchmark_message_dispatch() -> void:
	var bus := GFMessageBus.new()
	var received := [0]
	bus.register_command(&"benchmark.command", func(value: Variant) -> void: received[0] += int(value))
	bus.register_query(&"benchmark.query", func(value: Variant) -> int: return int(value) + 1)
	var started := Time.get_ticks_usec()
	for _index in 10_000:
		bus.send(&"benchmark.command", 1)
	var command_elapsed := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var query_result := 0
	for index in 10_000:
		query_result = int(bus.ask(&"benchmark.query", index))
	_record(&"message_send_10k", command_elapsed, received[0] == 10_000)
	_record(&"message_query_10k", Time.get_ticks_usec() - started, query_result == 10_000)


func _benchmark_service_resolve() -> void:
	var services := GFServiceContainer.new()
	var service := RefCounted.new()
	services.register(&"benchmark.service", service)
	var resolved: Variant
	var started := Time.get_ticks_usec()
	for _index in 100_000:
		resolved = services.resolve(&"benchmark.service")
	_record(&"service_resolve_100k", Time.get_ticks_usec() - started, is_same(resolved, service))


func _benchmark_request_tracking() -> void:
	var tracker := GFRequestTracker.new()
	var ids: Array[int] = []
	var started := Time.get_ticks_usec()
	for _index in 10_000:
		ids.append(tracker.begin(0.0))
	for correlation_id: int in ids:
		tracker.resolve(correlation_id)
	_record(&"request_begin_resolve_10k", Time.get_ticks_usec() - started, tracker.pending_count() == 0)


func _benchmark_module_resolution() -> void:
	var services := GFServiceContainer.new()
	var logger := GFLogger.new()
	logger.minimum_level = GFLogger.Level.ERROR
	var context := GFContext.new(null, services, GFEventBus.new(), GFMessageBus.new(), logger)
	var manager := GFModuleManager.new(context)
	var trace: Array[String] = []
	for index in 500:
		var dependencies: Array[StringName] = []
		if index > 0:
			dependencies.append(StringName("benchmark_module_%d" % (index - 1)))
		manager.install(
			GFTrackingTestModule.new().setup(
				StringName("benchmark_module_%d" % index),
				dependencies,
				trace,
			),
		)
	var started := Time.get_ticks_usec()
	var result := manager.initialize_all()
	var elapsed := Time.get_ticks_usec() - started
	_record(&"module_chain_resolve_500", elapsed, result == OK and manager.ordered_ids().size() == 500)
	manager.shutdown_all()


func _record(benchmark_id: StringName, elapsed_usec: int, valid: bool) -> void:
	_results[benchmark_id] = {
		"elapsed_usec": elapsed_usec,
		"valid": valid,
	}
	if not valid or elapsed_usec > DISASTER_THRESHOLD_USEC:
		_failed = true
