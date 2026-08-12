@tool
class_name GFFrameworkValidator
extends RefCounted

enum Severity {
	INFO,
	WARNING,
	ERROR,
}


func validate_path(path: String) -> Array[Dictionary]:
	if path.is_empty():
		return [_issue(Severity.ERROR, &"config.path_empty", "Framework configuration path is empty.")]
	if not ResourceLoader.exists(path):
		return [_issue(Severity.ERROR, &"config.not_found", "Framework configuration does not exist: %s" % path)]
	var resource := ResourceLoader.load(path)
	if not resource is GFFrameworkConfig:
		return [_issue(Severity.ERROR, &"config.wrong_type", "Framework configuration must use GFFrameworkConfig.")]
	return validate(resource as GFFrameworkConfig)


func validate(config: GFFrameworkConfig) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if config == null:
		issues.append(_issue(Severity.ERROR, &"config.null", "Framework configuration is null."))
		return issues
	var config_error := config.validate()
	if not config_error.is_empty():
		issues.append(_issue(Severity.ERROR, &"config.invalid", config_error))

	var modules: Dictionary = {}
	var declared_ids: Dictionary = {}
	var insertion_order: Array[StringName] = []
	for index in config.modules.size():
		var definition := config.modules[index]
		if definition == null:
			issues.append(_issue(Severity.ERROR, &"module.definition_null", "Module definition at index %d is null." % index, &"", index))
			continue
		var module_id := definition.declared_id
		if module_id.is_empty():
			issues.append(_issue(Severity.ERROR, &"module.id_empty", "Module at index %d has no declared ID." % index, &"", index))
			continue
		if declared_ids.has(module_id):
			issues.append(_issue(Severity.ERROR, &"module.id_duplicate", "Duplicate module ID '%s'." % module_id, module_id, index))
			continue
		declared_ids[module_id] = true
		if definition.module_script == null:
			issues.append(_issue(Severity.ERROR, &"module.script_missing", "Module '%s' has no script." % module_id, module_id, index))
			continue
		if definition.module_script.resource_path.is_empty() or not ResourceLoader.exists(definition.module_script.resource_path):
			issues.append(_issue(Severity.ERROR, &"module.script_invalid", "Module '%s' script has no valid resource path." % module_id, module_id, index))
			continue
		modules[module_id] = {"definition": definition, "index": index}
		insertion_order.append(module_id)
		if definition.enabled and definition.settings != null:
			if not definition.expected_settings_class.is_empty():
				var settings_script := definition.settings.get_script() as Script
				var actual_class := settings_script.get_global_name() if settings_script != null else StringName()
				if actual_class != definition.expected_settings_class:
					issues.append(_issue(
						Severity.ERROR,
						&"module.settings_wrong_type",
						"Module '%s' settings must use %s." % [module_id, definition.expected_settings_class],
						module_id,
						index,
					))
					continue
			if not definition.settings.has_method(&"validate"):
				issues.append(_issue(Severity.WARNING, &"module.settings_unvalidated", "Module settings do not expose validate().", module_id, index))
				continue
			var validation := str(definition.settings.call(&"validate"))
			if not validation.is_empty():
				issues.append(_issue(Severity.ERROR, &"module.settings_invalid", validation, module_id, index))

	for module_id: StringName in insertion_order:
		var entry: Dictionary = modules[module_id]
		var definition := entry.definition as GFModuleDefinition
		if not definition.enabled:
			continue
		for dependency_id: StringName in definition.declared_dependencies:
			if not modules.has(dependency_id):
				issues.append(_issue(
					Severity.ERROR,
					&"module.dependency_missing",
					"Module '%s' requires missing module '%s'." % [module_id, dependency_id],
					module_id,
					int(entry.index),
				))
				continue
			var dependency: Dictionary = modules[dependency_id]
			if not (dependency.definition as GFModuleDefinition).enabled:
				issues.append(_issue(
					Severity.ERROR,
					&"module.dependency_disabled",
					"Module '%s' requires disabled module '%s'." % [module_id, dependency_id],
					module_id,
					int(entry.index),
				))

	_validate_cycles(modules, insertion_order, issues)
	if issues.is_empty():
		issues.append(_issue(Severity.INFO, &"config.valid", "Framework configuration is valid."))
	return issues


func has_errors(issues: Array[Dictionary]) -> bool:
	for issue: Dictionary in issues:
		if int(issue.get("severity", Severity.ERROR)) == Severity.ERROR:
			return true
	return false


func _validate_cycles(
	modules: Dictionary,
	insertion_order: Array[StringName],
	issues: Array[Dictionary],
) -> void:
	var marks: Dictionary = {}
	var stack: Array[StringName] = []
	var reported: Dictionary = {}
	for module_id: StringName in insertion_order:
		_visit(module_id, modules, marks, stack, reported, issues)


func _visit(
	module_id: StringName,
	modules: Dictionary,
	marks: Dictionary,
	stack: Array[StringName],
	reported: Dictionary,
	issues: Array[Dictionary],
) -> void:
	var mark := int(marks.get(module_id, 0))
	if mark == 2:
		return
	if mark == 1:
		var start := stack.find(module_id)
		var cycle_ids := stack.slice(start) if start >= 0 else stack.duplicate()
		cycle_ids.append(module_id)
		var cycle_parts: Array[String] = []
		for id: StringName in cycle_ids:
			cycle_parts.append(str(id))
		var cycle_key := " -> ".join(cycle_parts)
		if not reported.has(cycle_key):
			reported[cycle_key] = true
			var entry: Dictionary = modules[module_id]
			issues.append(_issue(Severity.ERROR, &"module.dependency_cycle", "Module dependency cycle: %s" % cycle_key, module_id, int(entry.index)))
		return
	if not modules.has(module_id):
		return
	var entry: Dictionary = modules[module_id]
	if not (entry.definition as GFModuleDefinition).enabled:
		marks[module_id] = 2
		return
	marks[module_id] = 1
	stack.append(module_id)
	var definition := entry.definition as GFModuleDefinition
	for dependency_id: StringName in definition.declared_dependencies:
		if modules.has(dependency_id) and (modules[dependency_id].definition as GFModuleDefinition).enabled:
			_visit(dependency_id, modules, marks, stack, reported, issues)
	stack.pop_back()
	marks[module_id] = 2


func _issue(
	severity: Severity,
	code: StringName,
	message: String,
	module_id := StringName(),
	module_index := -1,
) -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"message": message,
		"module_id": module_id,
		"module_index": module_index,
	}
