extends Reference

## Runs one integration test per call: compiles its file (cached per path and source),
## waits for the test function, then undoes what the test left behind so the next one starts clean.

# Compiled test files take their repo path under res://, so errors in godot.log name the test file.
const VIRTUAL_ROOT := "res://"
const GODOT_LOG := "user://logs/godot.log"
# Brotato's release build logs no runtime script errors, only parse errors and push_error (also from ModLoaderLog).
const ERROR_MARKS := ["SCRIPT ERROR", "ERROR:"]

var _compiled := {}


func run(args: Dictionary, access, commands):
	var path := String(args.get("path", ""))
	var function_name := String(args.get("function", ""))
	var log_start := _log_length()
	var script = _compile(path, String(args.get("source", "")))
	if script == null:
		return _result("error", ["%s did not compile." % path] + _new_log_errors(log_start), "", 0)
	var test = script.new()
	if not test.has_method(function_name):
		return _result("error", ["%s has no function %s." % [path, function_name]], "", 0)
	test.tree = access.tree
	test.access = access
	test.commands = commands
	var snapshot := _snapshot_configs()
	# Random shop offers and rolls repeat from run to run.
	seed(hash(path + function_name))
	var started := OS.get_ticks_msec()
	yield(_finish(test.before_each()), "completed")
	if test.skip_reason.empty() and test.failures.empty():
		yield(_finish(test.call(function_name)), "completed")
	yield(_finish(test.after_each()), "completed")
	yield(_finish(test.run_cleanups()), "completed")
	_restore_configs(snapshot)
	yield(_close_leftovers(access), "completed")
	var errors := _new_log_errors(log_start)
	var messages: Array = test.failures.duplicate()
	messages.append_array(errors)
	return _result(_status(test, errors), messages, test.skip_reason, OS.get_ticks_msec() - started)


# A GDScript 1 function only returns a GDScriptFunctionState once it yields; this always yields, so
# the runner can wait the same way for test functions that yield and for those that don't.
func _finish(value):
	if value is GDScriptFunctionState and value.is_valid():
		yield(value, "completed")
	else:
		yield(Engine.get_main_loop(), "idle_frame")


func _compile(path: String, source: String) -> GDScript:
	var source_hash := source.hash()
	if _compiled.has(path) and _compiled[path]["hash"] == source_hash:
		return _compiled[path]["script"]
	var script := GDScript.new()
	script.source_code = source
	script.take_over_path(VIRTUAL_ROOT + path)
	if script.reload() != OK:
		_compiled.erase(path)
		return null
	_compiled[path] = {"hash": source_hash, "script": script}
	return script


# A test's own cleanups restore what it changed through the mods; this also puts back
# config data it changed directly.
static func _snapshot_configs() -> Dictionary:
	var snapshot := {}
	for mod_data in ModLoaderConfig.get_mods_with_config():
		for config in mod_data.configs.values():
			snapshot[config] = var2str(config.data)
	return snapshot


static func _restore_configs(snapshot: Dictionary) -> void:
	for config in snapshot:
		if var2str(config.data) != snapshot[config]:
			config.data = str2var(snapshot[config])
			config.save_to_file()


func _close_leftovers(access):
	var tree: SceneTree = access.tree
	tree.paused = false
	Engine.time_scale = 1.0
	yield(tree, "idle_frame")
	tree.paused = false


static func _status(test, errors: Array) -> String:
	if not errors.empty():
		return "error"
	if not test.skip_reason.empty():
		return "skipped"
	return "failed" if not test.failures.empty() else "passed"


static func _log_length() -> int:
	var file := File.new()
	if file.open(GODOT_LOG, File.READ) != OK:
		return 0
	var length := file.get_len()
	file.close()
	return length


# Errors would otherwise pass unnoticed; Godot flushes them to godot.log right away.
static func _new_log_errors(from: int) -> Array:
	var file := File.new()
	if file.open(GODOT_LOG, File.READ) != OK:
		return []
	var length := file.get_len()
	if length <= from:
		file.close()
		return []
	file.seek(from)
	var lines := file.get_buffer(length - from).get_string_from_utf8().split("\n")
	file.close()
	var errors := []
	for i in lines.size():
		if _is_error_line(lines[i]):
			var location: String = lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			errors.append("%s (%s)" % [lines[i].strip_edges(), location])
	return errors


static func _is_error_line(line: String) -> bool:
	for mark in ERROR_MARKS:
		if line.begins_with(mark):
			return true
	return false


static func _result(status: String, messages: Array, skip_reason: String, duration_ms: int) -> Dictionary:
	return {"ok": true, "result": {"status": status, "messages": messages, "skip_reason": skip_reason, "duration_ms": duration_ms}}
