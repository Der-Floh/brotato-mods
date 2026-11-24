extends Node

## The mod's settings, kept in GML's config system so dami-ModOptions sees the simple ones. The default
## config can't be changed, so the first change creates a "user" config and makes it current.

signal changed(key, source)

const MOD_ID := "der_floh-auto_brotato"
const USER_CONFIG := "user"
const DEFAULT_CONFIG := "default"
const SAVE_DELAY_SEC := 0.5
const SCHEMA_VERSION := 1

const AUTO_RECYCLE := "auto_recycle_crate_items"
const AUTO_TAKE := "auto_take_crate_items"
const AUTO_LEVEL_UP := "auto_pick_level_ups"
const AUTO_NEXT_WAVE := "auto_start_next_wave"
const NEXT_WAVE_DELAY := "next_wave_delay"
const NEXT_WAVE_LIMIT := "next_wave_limit"
const ITEM_RULES := "item_rules"
const WEAPON_RULES := "weapon_rules"
const LEVEL_UP_WEIGHTS := "level_up_weights"
const SCHEMA_VERSION_KEY := "schema_version"

const DEFAULTS := {
	AUTO_RECYCLE: false,
	AUTO_TAKE: false,
	AUTO_LEVEL_UP: false,
	AUTO_NEXT_WAVE: false,
	NEXT_WAVE_DELAY: 0.0,
	NEXT_WAVE_LIMIT: 0.0,
}
const NUMBER_RANGES := {
	NEXT_WAVE_DELAY: [0.0, 10.0],
	NEXT_WAVE_LIMIT: [0.0, 200.0],
}
const RULE_KEYS := [ITEM_RULES, WEAPON_RULES, LEVEL_UP_WEIGHTS]

var revision := 0
var _save_timer := Timer.new()


func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_SEC
	var _connected = _save_timer.connect("timeout", self, "save_now")
	add_child(_save_timer)


func _exit_tree() -> void:
	if not _save_timer.is_stopped():
		save_now()


func get_value(key: String):
	return _data().get(key, DEFAULTS.get(key))


func set_value(key: String, value, source := "") -> void:
	var sanitized = _sanitized(key, value)
	if get_value(key) == sanitized:
		return
	var data = _writable_data()
	if data == null:
		return
	data[key] = sanitized
	_note_change(key, source)


## A deep copy of item_rules, weapon_rules or level_up_weights.
func get_rules(key: String) -> Dictionary:
	var rules = _data().get(key, {})
	return rules.duplicate(true) if rules is Dictionary else {}


func set_rules(key: String, rules: Dictionary, source := "") -> void:
	var data = _writable_data()
	if data == null:
		return
	data[key] = rules.duplicate(true)
	data[SCHEMA_VERSION_KEY] = float(SCHEMA_VERSION)
	_note_change(key, source)


## The rule of one item or weapon; an id without rule is taken.
func rule_for(key: String, element_id: String) -> Dictionary:
	var rules = _data().get(key, {})
	if rules is Dictionary and rules.get(element_id) is Dictionary:
		return rules[element_id]
	return {}


func set_rule_for(key: String, element_id: String, rule: Dictionary, source := "") -> void:
	var rules := get_rules(key)
	if rule.empty():
		var _erased = rules.erase(element_id)
	else:
		rules[element_id] = rule.duplicate(true)
	set_rules(key, rules, source)


func save_now() -> void:
	_save_timer.stop()
	var config = _current_config()
	if config != null and config.name != DEFAULT_CONFIG:
		var _saved = ModLoaderConfig.update_config(config)


func _note_change(key: String, source: String) -> void:
	revision += 1
	_save_timer.start()
	emit_signal("changed", key, source)


func _data() -> Dictionary:
	var config = _current_config()
	return config.data if config != null and config.data is Dictionary else {}


# Read on every call, because the test runner and the options libraries swap config.data.
static func _current_config():
	var mod_data = ModLoaderStore.mod_data.get(MOD_ID)
	if mod_data == null:
		return null
	if mod_data.current_config != null:
		return mod_data.current_config
	return mod_data.configs.get(DEFAULT_CONFIG)


func _writable_data():
	var config = _current_config()
	if config == null:
		return null
	if config.name == DEFAULT_CONFIG:
		config = _user_config(config)
	return config.data if config != null else null


static func _user_config(default_config):
	var mod_data = ModLoaderStore.mod_data[MOD_ID]
	var config = mod_data.configs.get(USER_CONFIG)
	if config == null:
		config = ModLoaderConfig.create_config(MOD_ID, USER_CONFIG, default_config.data.duplicate(true))
	if config != null:
		ModLoaderConfig.set_current_config(config)
	return config


static func _sanitized(key: String, value):
	if not DEFAULTS.has(key):
		return value
	if typeof(DEFAULTS[key]) == TYPE_BOOL:
		return bool(value)
	var number_range: Array = NUMBER_RANGES[key]
	return clamp(round(float(value)), number_range[0], number_range[1])
