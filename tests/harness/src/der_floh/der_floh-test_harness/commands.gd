extends Reference

const EvalRunner := preload("res://mods-unpacked/der_floh-test_harness/eval_runner.gd")
const TestRunner := preload("res://mods-unpacked/der_floh-test_harness/test_runner.gd")
const DEFAULT_RUN := {"character": "character_well_rounded", "weapon": "weapon_knife_1", "difficulty": 0, "zone": 0, "invulnerable": true}
const SCENE_TIMEOUT_MS := 30000
const ACTION_MODES := ["tap", "press", "release"]
const PLAYER := 0
const HANDLERS := {
	"status": "status",
	"eval": "eval_code",
	"run_test": "run_test",
	"screenshot": "screenshot",
	"quit": "quit",
	"new_run": "new_run",
	"end_wave": "end_wave",
	"next_wave": "next_wave",
	"give_item": "give_item",
	"give_weapon": "give_weapon",
	"set_gold": "set_gold",
	"action": "action",
}

var _access
var _eval_runner := EvalRunner.new()
var _test_runner := TestRunner.new()
var _screenshot_dir: String
var _skip_choices := true


func _init(access, screenshot_dir: String) -> void:
	_access = access
	_screenshot_dir = screenshot_dir


func handle(_method: String, path: String, args: Dictionary):
	var command := path.trim_prefix("/")
	if not HANDLERS.has(command):
		return _fail("Unknown command '%s'. Known: %s." % [command, PoolStringArray(HANDLERS.keys()).join(", ")])
	return call(HANDLERS[command], args)


# --- Harness ---

func status(_args := {}) -> Dictionary:
	var player_data = RunData.players_data[PLAYER] if RunData.players_data.size() > PLAYER else null
	return _ok({
		"pid": OS.get_process_id(),
		"user_data_dir": OS.get_user_data_dir(),
		"scene": _access.scene_path(),
		"in_wave": _access.wave() != null,
		"in_shop": _access.shop() != null,
		"paused": _access.tree.paused,
		"unlock_all_save": ProgressData.is_unlock_all_save(),
		"wave": RunData.current_wave,
		"zone": RunData.current_zone,
		"difficulty": RunData.current_difficulty,
		"character": _id_of(player_data.current_character) if player_data else "",
		"gold": player_data.gold if player_data else 0,
		"level": player_data.current_level if player_data else 0,
		"health": player_data.current_health if player_data else 0,
		"weapons": _ids(player_data.weapons) if player_data else [],
		"items": _ids(player_data.items) if player_data else [],
		"mods": _mod_list(),
	})


func eval_code(args: Dictionary):
	return _eval_runner.run(String(args.get("code", "")), _access)


func run_test(args: Dictionary):
	return _test_runner.run(args, _access, self)


func screenshot(args: Dictionary):
	var path := _screenshot_dir.plus_file(_file_name(String(args.get("name", "screenshot"))) + ".png")
	Directory.new().make_dir_recursive(_screenshot_dir)
	yield(VisualServer, "frame_post_draw")
	var image: Image = _access.tree.root.get_texture().get_data()
	image.flip_y()
	var error := image.save_png(path)
	if error != OK:
		return _fail("Saving %s failed (error %d)." % [path, error])
	return _ok({"path": path})


func quit(_args: Dictionary) -> Dictionary:
	_access.tree.call_deferred("quit")
	return _ok()


# --- Run flow ---

## Starts a solo run the way the character, weapon and difficulty menus do, and waits for wave 1.
func new_run(args: Dictionary):
	var settings := DEFAULT_RUN.duplicate()
	for key in args:
		settings[key] = args[key]
	var character = _element(ItemService.characters, String(settings["character"]))
	var weapon = _element(ItemService.weapons, String(settings["weapon"]))
	var difficulty = _difficulty(int(settings["difficulty"]))
	if character == null or difficulty == null or (String(settings["weapon"]) != "" and weapon == null):
		return _fail("Unknown character, weapon or difficulty in %s." % settings)
	_reset_run(int(settings["zone"]))
	RunData.add_character(character, PLAYER)
	if weapon and RunData.some_player_has_weapon_slots():
		var _added = RunData.add_weapon(weapon, PLAYER, true)
	RunData.add_starting_items_and_weapons()
	_apply_difficulty(difficulty)
	RunData.invulnerable = bool(settings["invulnerable"])
	var _error = _access.tree.change_scene(MenuData.game_scene)
	if not yield(_access.wait_until(_access, "wave", SCENE_TIMEOUT_MS), "completed"):
		return _fail("The first wave did not start in time.")
	return status()


## Ends the running wave. With skip_choices (default), level-up and crate choices are dropped so it goes
## straight to the shop, or to the end screen when the run is over.
func end_wave(args: Dictionary):
	var wave = _access.wave()
	if wave == null:
		return _fail("end_wave needs a running wave; use new_run or next_wave first.")
	_skip_choices = bool(args.get("skip_choices", true))
	wave._wave_timer.stop()
	wave._on_WaveTimer_timeout()
	if not yield(_access.wait_until(self, "_left_wave", SCENE_TIMEOUT_MS), "completed"):
		return _fail("The wave did not end in time; with skip_choices false, level-up choices wait for a pick.")
	return status()


func next_wave(_args: Dictionary):
	var shop = _access.shop()
	if shop == null:
		return _fail("next_wave needs the shop; use end_wave first.")
	shop._on_GoButton_pressed(PLAYER)
	if not yield(_access.wait_until(_access, "wave", SCENE_TIMEOUT_MS), "completed"):
		return _fail("The next wave did not start in time.")
	return status()


# --- Cheats ---

## Adds an item as a shop purchase would; its stats reach a running wave's player when the next wave starts.
func give_item(args: Dictionary) -> Dictionary:
	var item_id := String(args.get("id", ""))
	var item = _element(ItemService.items, item_id)
	if item == null:
		return _fail("'%s' is not an item id such as item_helmet." % item_id)
	for i in max(1, int(args.get("count", 1))):
		RunData.add_item(item, PLAYER)
	return _ok({"items": _ids(RunData.get_player_items(PLAYER))})


## Adds a weapon to the run; a running wave's player gets it when the next wave starts.
func give_weapon(args: Dictionary) -> Dictionary:
	var weapon_id := String(args.get("id", ""))
	var weapon = _element(ItemService.weapons, weapon_id)
	if weapon == null:
		return _fail("'%s' is not a weapon id such as weapon_knife_1." % weapon_id)
	var _added = RunData.add_weapon(weapon, PLAYER)
	return _ok({"weapons": _ids(RunData.get_player_weapons(PLAYER))})


func set_gold(args: Dictionary) -> Dictionary:
	var difference: int = int(args.get("amount", 0)) - RunData.get_player_gold(PLAYER)
	if difference > 0:
		RunData.add_gold(difference, PLAYER)
	elif difference < 0:
		RunData.remove_gold(-difference, PLAYER)
	return _ok({"gold": RunData.get_player_gold(PLAYER)})


# --- Input ---

func action(args: Dictionary):
	var action_name := String(args.get("name", ""))
	var mode := String(args.get("mode", "tap"))
	if not InputMap.has_action(action_name) or not mode in ACTION_MODES:
		return _fail("Unknown input action '%s' or mode '%s' (tap, press, release)." % [action_name, mode])
	if mode != "release":
		_send_action(action_name, true)
	if mode == "tap":
		yield(_access.tree, "physics_frame")
		yield(_access.tree, "physics_frame")
	if mode != "press":
		_send_action(action_name, false)
	return _ok()


# --- Helpers ---

static func _reset_run(zone: int) -> void:
	RunData.reset()
	RunData.play_mode = RunData.PlayMode.SOLO
	RunData.is_streamplay_run = false
	RunData.set_coop_run(false)
	RunData.current_zone = zone


# Mirrors the difficulty menu's _on_element_pressed for one player.
static func _apply_difficulty(difficulty) -> void:
	var character_difficulty = ProgressData.get_character_difficulty_info(RunData.get_player_character(PLAYER).my_id_hash, RunData.current_zone)
	character_difficulty.difficulty_selected_value = difficulty.value
	RunData.current_difficulty = difficulty.value
	RunData.reset_elites_spawn()
	RunData.init_elites_spawn()
	RunData.init_events_nightmare()
	RunData.enabled_dlcs = ProgressData.available_dlc_ids.duplicate()
	RunData.active_update_data_ids = ProgressData.active_update_data.duplicate()
	ItemService.init_unlocked_pool()
	for effect in difficulty.effects:
		effect.apply(PLAYER)
	var player_data = RunData.players_data[PLAYER]
	player_data.uses_ban = RunData.is_ban_mode_active
	player_data.remaining_ban_token = RunData.BAN_MAX_TOKEN
	RunData.init_bosses_spawn()
	RunData.current_run_accessibility_settings = ProgressData.settings.enemy_scaling.duplicate()
	ProgressData.load_status = LoadStatus.SAVE_OK
	ProgressData.data["chal_hourglass_quit_wave"] = false


func _left_wave() -> bool:
	var wave = _access.wave()
	if wave and _skip_choices:
		for player_index in wave._upgrades_to_process.size():
			wave._upgrades_to_process[player_index].clear()
			wave._consumables_to_process[player_index].clear()
	return _access.shop() != null or _access.end_run() != null


func _mod_list() -> Array:
	var mods := []
	var mod_data: Dictionary = ModLoaderStore.mod_data
	for dir_name in mod_data:
		var data = mod_data[dir_name]
		mods.append({"id": dir_name, "version": data.manifest.version_number if data.manifest else "", "active": data.is_active})
	return mods


static func _element(elements: Array, element_id: String) -> Resource:
	for element in elements:
		if element.my_id == element_id:
			return element
	return null


static func _difficulty(value: int) -> Resource:
	for difficulty in ItemService.difficulties:
		if difficulty.value == value:
			return difficulty
	return null


static func _id_of(element) -> String:
	return element.my_id if element else ""


static func _ids(elements: Array) -> Array:
	var ids := []
	for element in elements:
		ids.append(_id_of(element))
	return ids


static func _file_name(name: String) -> String:
	var safe := name
	for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe = safe.replace(character, "_")
	return safe


static func _send_action(action_name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)


static func _ok(result = null) -> Dictionary:
	return {"ok": true, "result": result}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
