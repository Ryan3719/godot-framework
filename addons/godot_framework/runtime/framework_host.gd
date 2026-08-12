class_name GFFrameworkHost
extends Node

signal boot_completed
signal boot_failed(error: Error, message: String)
signal shutdown_completed

const CONFIG_PATH_SETTING := "godot_framework/config_path"
const AUTO_BOOT_SETTING := "godot_framework/auto_boot"

var config: GFFrameworkConfig
var services: GFServiceContainer
var events: GFEventBus
var messages: GFMessageBus
var logger: GFLogger
var modules: GFModuleManager

var _context: GFContext
var _booted := false
var _shutting_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	if bool(ProjectSettings.get_setting(AUTO_BOOT_SETTING, true)):
		boot()


func boot(override_config: GFFrameworkConfig = null) -> Error:
	if _booted or modules != null or _shutting_down:
		return ERR_ALREADY_IN_USE
	config = override_config if override_config != null else _load_config()
	if config == null:
		return _boot_failure(ERR_FILE_CANT_READ, "Framework configuration could not be loaded.")
	var config_error := config.validate()
	if not config_error.is_empty():
		return _boot_failure(ERR_INVALID_DATA, config_error)

	services = GFServiceContainer.new()
	events = GFEventBus.new(config.max_queued_events)
	messages = GFMessageBus.new()
	logger = GFLogger.new()
	logger.minimum_level = config.minimum_log_level
	_context = GFContext.new(self, services, events, messages, logger)
	var active_modules := GFModuleManager.new(_context)
	modules = active_modules

	services.register(GFServiceIds.FRAMEWORK, self)
	services.register(GFServiceIds.SERVICES, services)
	services.register(GFServiceIds.EVENTS, events)
	services.register(GFServiceIds.MESSAGES, messages)
	services.register(GFServiceIds.LOGGER, logger)
	services.register(GFServiceIds.MODULES, active_modules)

	for definition: GFModuleDefinition in config.modules:
		if definition == null:
			return _boot_failure(ERR_INVALID_DATA, "Framework configuration contains a null module definition.")
		if not definition.enabled:
			continue
		var module := definition.instantiate_module()
		if module == null:
			return _boot_failure(ERR_CANT_CREATE, definition.last_error)
		var install_result := active_modules.install(module)
		if install_result != OK:
			return _boot_failure(install_result, active_modules.last_error)

	var result := active_modules.initialize_all()
	if result != OK:
		return _boot_failure(result, active_modules.last_error)
	if not is_same(modules, active_modules):
		return _boot_failure(ERR_BUSY, "Framework initialization was interrupted by shutdown.")
	result = active_modules.start_all()
	if result != OK:
		return _boot_failure(result, active_modules.last_error)
	if not is_same(modules, active_modules):
		return _boot_failure(ERR_BUSY, "Framework startup was interrupted by shutdown.")

	_booted = true
	set_process(true)
	set_physics_process(true)
	logger.info(&"framework", "Framework boot completed.", {"modules": active_modules.ordered_ids()})
	boot_completed.emit()
	return OK


func shutdown() -> void:
	if modules == null or _shutting_down:
		return
	_shutting_down = true
	set_process(false)
	set_physics_process(false)
	modules.shutdown_all()
	if events != null:
		events.clear()
	if messages != null:
		messages.clear()
	if services != null:
		services.clear()
	modules = null
	_context = null
	events = null
	messages = null
	logger = null
	services = null
	config = null
	_booted = false
	_shutting_down = false
	shutdown_completed.emit()


func is_booted() -> bool:
	return _booted


func get_service(service_id: StringName, default: Variant = null) -> Variant:
	if services == null:
		return default
	return services.resolve(service_id, default)


func _process(delta: float) -> void:
	var active_modules := modules
	var active_events := events
	var active_config := config
	if active_modules == null or active_events == null or active_config == null:
		return
	active_modules.update(delta)
	if not _booted or not is_same(modules, active_modules) or not is_same(events, active_events):
		return
	active_events.flush(active_config.max_queued_events_per_frame)


func _physics_process(delta: float) -> void:
	var active_modules := modules
	if active_modules != null:
		active_modules.physics_update(delta)


func _exit_tree() -> void:
	shutdown()


func _load_config() -> GFFrameworkConfig:
	var path := str(ProjectSettings.get_setting(CONFIG_PATH_SETTING, ""))
	if path.is_empty():
		return GFFrameworkConfig.new()
	var loaded := ResourceLoader.load(path)
	if loaded is GFFrameworkConfig:
		return loaded as GFFrameworkConfig
	return null


func _boot_failure(error: Error, message: String) -> Error:
	_shutting_down = true
	set_process(false)
	set_physics_process(false)
	if logger != null:
		logger.error(&"framework", message, {"error": error})
	if modules != null:
		modules.shutdown_all()
	if events != null:
		events.clear()
	if messages != null:
		messages.clear()
	if services != null:
		services.clear()
	modules = null
	_context = null
	events = null
	messages = null
	logger = null
	services = null
	config = null
	_booted = false
	_shutting_down = false
	boot_failed.emit(error, message)
	return error
