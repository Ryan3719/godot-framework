class_name GFModuleManager
extends RefCounted

var last_error := ""

var _context: GFContext
var _modules: Dictionary = {}
var _insertion_order: Array[StringName] = []
var _resolved_order: Array[StringName] = []
var _initialized := false
var _running := false
var _terminated := false


func _init(module_context: GFContext) -> void:
	_context = module_context


func install(module: GFModule) -> Error:
	if _terminated:
		return _fail(ERR_ALREADY_IN_USE, "Terminated module managers cannot install modules.")
	if _initialized or _running:
		return _fail(ERR_ALREADY_IN_USE, "Modules cannot be installed after initialization.")
	if module == null:
		return _fail(ERR_INVALID_PARAMETER, "Cannot install a null module.")
	var id := module.module_id()
	if id.is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Module IDs cannot be empty.")
	if _modules.has(id):
		return _fail(ERR_ALREADY_EXISTS, "Duplicate module ID '%s'." % id)
	_modules[id] = module
	_insertion_order.append(id)
	_resolved_order.clear()
	return OK


func initialize_all() -> Error:
	if _terminated:
		return _fail(ERR_ALREADY_IN_USE, "Terminated module managers cannot be initialized.")
	if _initialized or _running:
		return _fail(ERR_ALREADY_IN_USE, "Modules are already initialized.")
	var resolve_result := _resolve_dependencies()
	if resolve_result != OK:
		return resolve_result
	for id: StringName in _resolved_order:
		var validation := (_modules[id] as GFModule).validate_configuration()
		if not validation.is_empty():
			return _fail(ERR_INVALID_DATA, "Module '%s' configuration is invalid: %s" % [id, validation])
	var initialized: Array[GFModule] = []
	for id: StringName in _resolved_order:
		var module: GFModule = _modules[id]
		var result := module._framework_initialize(_context)
		if result != OK:
			module._framework_shutdown()
			for index in range(initialized.size() - 1, -1, -1):
				initialized[index]._framework_shutdown()
			_terminated = true
			return _fail(result, "Module '%s' failed to initialize with error %d." % [id, result])
		initialized.append(module)
	_initialized = true
	return OK


func start_all() -> Error:
	if _terminated:
		return _fail(ERR_ALREADY_IN_USE, "Terminated module managers cannot be started.")
	if not _initialized:
		return _fail(ERR_UNCONFIGURED, "Modules must be initialized before startup.")
	if _running:
		return _fail(ERR_ALREADY_IN_USE, "Modules are already running.")
	var started: Array[GFModule] = []
	for id: StringName in _resolved_order:
		var module: GFModule = _modules[id]
		var result := module._framework_start()
		if result != OK:
			shutdown_all()
			return _fail(result, "Module '%s' failed to start with error %d." % [id, result])
		started.append(module)
	_running = true
	return OK


func update(delta: float) -> void:
	if not _running:
		return
	for id: StringName in _resolved_order:
		var module: GFModule = _modules[id]
		if module.lifecycle == GFModule.Lifecycle.STARTED:
			module.update(delta)


func physics_update(delta: float) -> void:
	if not _running:
		return
	for id: StringName in _resolved_order:
		var module: GFModule = _modules[id]
		if module.lifecycle == GFModule.Lifecycle.STARTED:
			module.physics_update(delta)


func shutdown_all() -> void:
	if _terminated:
		return
	for index in range(_resolved_order.size() - 1, -1, -1):
		var module: GFModule = _modules[_resolved_order[index]]
		module._framework_shutdown()
	_running = false
	_initialized = false
	_terminated = true


func get_module(module_id: StringName) -> GFModule:
	return _modules.get(module_id) as GFModule


func ordered_ids() -> Array[StringName]:
	return _resolved_order.duplicate()


func is_terminated() -> bool:
	return _terminated


func _resolve_dependencies() -> Error:
	_resolved_order.clear()
	var marks: Dictionary = {}
	var stack: Array[StringName] = []
	for id: StringName in _insertion_order:
		var result := _visit(id, marks, stack)
		if result != OK:
			_resolved_order.clear()
			return result
	return OK


func _visit(id: StringName, marks: Dictionary, stack: Array[StringName]) -> Error:
	var mark: int = marks.get(id, 0)
	if mark == 2:
		return OK
	if mark == 1:
		var cycle: Array[String] = []
		for entry: StringName in stack:
			cycle.append(str(entry))
		cycle.append(str(id))
		return _fail(ERR_CYCLIC_LINK, "Module dependency cycle: %s" % " -> ".join(cycle))
	marks[id] = 1
	stack.append(id)
	var module: GFModule = _modules[id]
	for dependency_id: StringName in module.dependencies():
		if not _modules.has(dependency_id):
			return _fail(
				ERR_DOES_NOT_EXIST,
				"Module '%s' requires missing module '%s'." % [id, dependency_id],
			)
		var result := _visit(dependency_id, marks, stack)
		if result != OK:
			return result
	stack.pop_back()
	marks[id] = 2
	_resolved_order.append(id)
	return OK


func _fail(code: Error, message: String) -> Error:
	last_error = message
	if _context != null and _context.logger != null:
		_context.logger.error(&"modules", message)
	return code
