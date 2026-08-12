class_name GFModuleDefinition
extends Resource

@export var enabled := true
@export var module_script: Script
@export var settings: Resource

var last_error := ""


func instantiate_module() -> GFModule:
	last_error = ""
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
	module.configure(settings)
	return module
