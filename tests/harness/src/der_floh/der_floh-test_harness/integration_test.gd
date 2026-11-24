extends Reference

## Base class of the integration tests in tests/integration/. Every func test_*() of a file
## extending this one runs inside the game with the helpers below. Failed expectations are
## collected instead of stopping the test, and everything registered with on_cleanup() is
## undone after it, whatever happened.
##
## Fixtures and waits are coroutines that always yield, so wait for them with
##   if not yield(fresh_run(), "completed"):
##       return

const DEFAULT_CHARACTER := "character_well_rounded"
const DEFAULT_WEAPON := "weapon_knife_1"
const KEY_HOLD_FRAMES := 2

var tree: SceneTree
var access
var commands

var failures := []
var skip_reason := ""
var _cleanups := []


## Runs before every test of the file; override it, it may yield.
func before_each():
	pass


## Runs after every test of the file, before the registered cleanups; override it, it may yield.
func after_each():
	pass


# --- Game access ---

## The running wave's main.tscn scene, or null.
func wave():
	return access.wave()


func shop():
	return access.shop()


func player(index := 0):
	return access.player(index)


## The mod_main script of a loaded mod, whose static functions and settings tests call.
func mod(mod_id: String):
	return access.mod_main(mod_id)


func has_mod(mod_id: String) -> bool:
	return access.is_mod_active(mod_id)


func frames(count := 1):
	for i in max(count, 1):
		yield(tree, "idle_frame")


func physics_frames(count := 1):
	for i in max(count, 1):
		yield(tree, "physics_frame")


# --- Fixtures ---

## Starts a new solo run and waits for wave 1. The player is invulnerable unless invulnerable is false.
func fresh_run(character := DEFAULT_CHARACTER, weapon := DEFAULT_WEAPON, difficulty := 0, invulnerable := true):
	var response = yield(_command("new_run", {"character": character, "weapon": weapon, "difficulty": difficulty, "invulnerable": invulnerable}), "completed")
	return _succeeded(response)


## A running wave of the current run, from the shop or a new run when needed.
func in_wave():
	if access.wave() != null:
		yield(tree, "idle_frame")
		return true
	if access.shop() != null:
		var response = yield(_command("next_wave"), "completed")
		return _succeeded(response)
	var started = yield(fresh_run(), "completed")
	return started


## The shop of the current run, ending the running wave or starting a run when needed.
func in_shop():
	if access.shop() != null:
		yield(tree, "idle_frame")
		return true
	if access.wave() == null:
		var started = yield(fresh_run(), "completed")
		if not started:
			return false
	var response = yield(_command("end_wave"), "completed")
	return _succeeded(response)


func end_wave(skip_choices := true):
	var response = yield(_command("end_wave", {"skip_choices": skip_choices}), "completed")
	return _succeeded(response)


func next_wave():
	var response = yield(_command("next_wave"), "completed")
	return _succeeded(response)


func give_item(item_id: String, count := 1):
	var response = yield(_command("give_item", {"id": item_id, "count": count}), "completed")
	return _succeeded(response)


func give_weapon(weapon_id: String):
	var response = yield(_command("give_weapon", {"id": weapon_id}), "completed")
	return _succeeded(response)


## Presses and releases a key, with both key codes set like a real key press.
func press_key(scancode: int):
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.scancode = scancode
		event.physical_scancode = scancode
		event.pressed = pressed
		Input.parse_input_event(event)
		yield(physics_frames(KEY_HOLD_FRAMES), "completed")


# --- Restoring ---

## Calls target.method(args) after the test, last registered first.
func on_cleanup(target: Object, method: String, args := []) -> void:
	_cleanups.append([target, method, args])


## Sets a mod setting through its set_<setting>() and restores get_<setting>()'s value after the test.
func use_setting(mod_id: String, setting: String, value) -> void:
	var mod_main = mod(mod_id)
	var previous = mod_main.call("get_" + setting)
	mod_main.call("set_" + setting, value)
	on_cleanup(mod_main, "set_" + setting, [previous])


## Sets a property, such as a DebugService flag, and restores its previous value after the test.
func use_value(target: Object, property: String, value) -> void:
	var previous = target.get(property)
	target.set(property, value)
	on_cleanup(target, "set", [property, previous])


# --- Expectations ---

func expect(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func expect_eq(actual, expected, message := "") -> bool:
	return expect(_same(actual, expected), "%sexpected %s, got %s" % [_prefix(message), _show(expected), _show(actual)])


func expect_near(actual: float, expected: float, tolerance: float, message := "") -> bool:
	return expect(abs(actual - expected) <= tolerance, "%sexpected %s ± %s, got %s" % [_prefix(message), expected, tolerance, actual])


func expect_between(actual: float, low: float, high: float, message := "") -> bool:
	return expect(actual >= low and actual <= high, "%sexpected %s to %s, got %s" % [_prefix(message), low, high, actual])


func fail(message: String) -> void:
	failures.append(message)


## Marks the test as skipped; return right after calling it.
func skip(reason: String) -> void:
	skip_reason = reason


## Skips the test unless all these mods are loaded; use as: if not require_mods([...]): return
func require_mods(mod_ids: Array) -> bool:
	var missing := []
	for mod_id in mod_ids:
		if not has_mod(mod_id):
			missing.append(mod_id)
	if not missing.empty():
		skip("needs " + PoolStringArray(missing).join(", "))
	return missing.empty()


# --- Used by test_runner.gd ---

func run_cleanups():
	while not _cleanups.empty():
		var cleanup: Array = _cleanups.pop_back()
		if not is_instance_valid(cleanup[0]):
			continue
		var state = cleanup[0].callv(cleanup[1], cleanup[2])
		if state is GDScriptFunctionState:
			yield(state, "completed")


# Always yields, also for commands that answer at once.
func _command(command_name: String, args := {}):
	var response = commands.call(command_name, args)
	if response is GDScriptFunctionState:
		response = yield(response, "completed")
	else:
		yield(tree, "idle_frame")
	return response


func _succeeded(response: Dictionary) -> bool:
	if not response.get("ok", false):
		fail(String(response.get("error", "the harness command failed")))
		return false
	return true


static func _prefix(message: String) -> String:
	return message + ": " if not message.empty() else ""


static func _show(value) -> String:
	return var2str(value).replace("\n", " ")


# == errors in GDScript when the types can't be compared, so numbers compare by value
# and containers element by element.
static func _same(actual, expected) -> bool:
	if _is_number(actual) and _is_number(expected):
		return is_equal_approx(float(actual), float(expected))
	if typeof(actual) != typeof(expected):
		return false
	if actual is Array:
		if actual.size() != expected.size():
			return false
		for i in actual.size():
			if not _same(actual[i], expected[i]):
				return false
		return true
	if actual is Dictionary:
		if actual.size() != expected.size():
			return false
		for key in actual:
			if not expected.has(key) or not _same(actual[key], expected[key]):
				return false
		return true
	return actual == expected


static func _is_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_REAL]
