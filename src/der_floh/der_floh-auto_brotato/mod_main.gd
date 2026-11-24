extends Node

## Watches which scene is current and lets the automators act; it extends no game script.

const MOD_ID := "der_floh-auto_brotato"
const SETTINGS_META := "der_floh_auto_brotato_settings"
const AUTOMATOR_META := "der_floh_auto_brotato_shop"
const Translations := preload("res://mods-unpacked/der_floh-auto_brotato/core/translations.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const GameAccess := preload("res://mods-unpacked/der_floh-auto_brotato/core/game_access.gd")
const EndWaveAutomator := preload("res://mods-unpacked/der_floh-auto_brotato/automation/end_wave_automator.gd")
const ShopAutomator := preload("res://mods-unpacked/der_floh-auto_brotato/automation/shop_automator.gd")
const Injector := preload("res://mods-unpacked/der_floh-auto_brotato/ui/injector.gd")
const DamiBridge := preload("res://mods-unpacked/der_floh-auto_brotato/bridges/dami_bridge.gd")
const OudstandBridge := preload("res://mods-unpacked/der_floh-auto_brotato/bridges/oudstand_bridge.gd")

var _settings: Node
var _end_wave: Reference
var _shop: Reference
var _injector: Reference
var _bridges := []
var _scene_id := 0
var _scene_path := ""


func _init() -> void:
	Translations.install()


func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	_settings = Settings.new()
	add_child(_settings)
	Engine.set_meta(SETTINGS_META, _settings)
	_end_wave = EndWaveAutomator.new(_settings)
	_shop = ShopAutomator.new(_settings)
	Engine.set_meta(AUTOMATOR_META, _shop)
	_injector = Injector.new(_settings)
	var _connected = _settings.connect("changed", self, "_on_settings_changed")
	call_deferred("_connect_bridges")


func _process(delta: float) -> void:
	var scene = get_tree().current_scene
	if not is_instance_valid(scene):
		return
	if scene.get_instance_id() != _scene_id:
		_on_scene_changed(scene)
		return
	var paused := get_tree().paused
	if GameAccess.is_wave_scene(scene):
		if not paused:
			_end_wave.tick(scene)
	elif GameAccess.is_shop_scene(scene):
		_shop.tick(delta, paused)


# A shop reached from anywhere but a wave is a resumed run; the game clears its own flag before this runs.
func _on_scene_changed(scene: Node) -> void:
	var previous_path := _scene_path
	_scene_id = scene.get_instance_id()
	_scene_path = scene.filename
	_shop.on_shop_left()
	if GameAccess.is_shop_scene(scene):
		_shop.on_shop_entered(scene, previous_path != MenuData.game_scene)
	_injector.on_scene_changed(scene)


func _on_settings_changed(_key: String, _source: String) -> void:
	_shop.on_settings_changed()


# Deferred until the mod loader is ready, so the options libraries have built their nodes.
func _connect_bridges() -> void:
	for bridge in [DamiBridge.new(_settings), OudstandBridge.new(_settings)]:
		if bridge.connect_to(get_tree()):
			_bridges.append(bridge)


# --- For tests and other mods ---

static func settings() -> Node:
	return Engine.get_meta(SETTINGS_META) if Engine.has_meta(SETTINGS_META) else null


static func shop_automator() -> Reference:
	return Engine.get_meta(AUTOMATOR_META) if Engine.has_meta(AUTOMATOR_META) else null


static func get_auto_recycle_crate_items() -> bool:
	return settings().get_value(Settings.AUTO_RECYCLE)


static func set_auto_recycle_crate_items(value: bool) -> void:
	settings().set_value(Settings.AUTO_RECYCLE, value)


static func get_auto_take_crate_items() -> bool:
	return settings().get_value(Settings.AUTO_TAKE)


static func set_auto_take_crate_items(value: bool) -> void:
	settings().set_value(Settings.AUTO_TAKE, value)


static func get_auto_pick_level_ups() -> bool:
	return settings().get_value(Settings.AUTO_LEVEL_UP)


static func set_auto_pick_level_ups(value: bool) -> void:
	settings().set_value(Settings.AUTO_LEVEL_UP, value)


static func get_auto_start_next_wave() -> bool:
	return settings().get_value(Settings.AUTO_NEXT_WAVE)


static func set_auto_start_next_wave(value: bool) -> void:
	settings().set_value(Settings.AUTO_NEXT_WAVE, value)


static func get_next_wave_delay() -> float:
	return settings().get_value(Settings.NEXT_WAVE_DELAY)


static func set_next_wave_delay(value: float) -> void:
	settings().set_value(Settings.NEXT_WAVE_DELAY, value)


static func get_next_wave_limit() -> float:
	return settings().get_value(Settings.NEXT_WAVE_LIMIT)


static func set_next_wave_limit(value: float) -> void:
	settings().set_value(Settings.NEXT_WAVE_LIMIT, value)


static func get_item_rules() -> Dictionary:
	return settings().get_rules(Settings.ITEM_RULES)


static func set_item_rules(rules: Dictionary) -> void:
	settings().set_rules(Settings.ITEM_RULES, rules)


static func get_weapon_rules() -> Dictionary:
	return settings().get_rules(Settings.WEAPON_RULES)


static func set_weapon_rules(rules: Dictionary) -> void:
	settings().set_rules(Settings.WEAPON_RULES, rules)


static func get_level_up_weights() -> Dictionary:
	return settings().get_rules(Settings.LEVEL_UP_WEIGHTS)


static func set_level_up_weights(weights: Dictionary) -> void:
	settings().set_rules(Settings.LEVEL_UP_WEIGHTS, weights)
