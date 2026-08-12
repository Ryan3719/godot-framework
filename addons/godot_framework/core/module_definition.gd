@tool
class_name GFModuleDefinition
extends Resource

@export var enabled := true
@export var declared_id: StringName
@export var declared_dependencies: Array[StringName] = []
@export var module_script: Script
@export var expected_settings_class: StringName
@export var settings: Resource

var last_error := ""


func instantiate_module() -> GFModule:
	last_error = ""
	if declared_id.is_empty():
		last_error = "Module definition has no declared ID."
		return null
	if module_script == null:
		last_error = "Module script is not configured."
		return null
	if not module_script.can_instantiate():
		last_error = "Module script '%s' cannot be instantiated." % module_script.resource_path
		return null
	var instance: Variant = module_script.new()
	if not instance is GFModule:
		last_error = "Module script '%s' must extend GFModule." % module_script.resource_path
		return null
	var module := instance as GFModule
	if module.module_id() != declared_id:
		last_error = "Module script '%s' reports ID '%s' but definition declares '%s'." % [
			module_script.resource_path,
			module.module_id(),
			declared_id,
		]
		return null
	if module.dependencies() != declared_dependencies:
		last_error = "Module '%s' dependencies do not match its definition." % declared_id
		return null
	if settings != null and not expected_settings_class.is_empty():
		var settings_script := settings.get_script() as Script
		var actual_class := settings_script.get_global_name() if settings_script != null else StringName()
		if actual_class != expected_settings_class:
			last_error = "Module '%s' settings must use %s." % [declared_id, expected_settings_class]
			return null
	module.configure(settings)
	return module
