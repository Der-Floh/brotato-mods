extends Reference

## Oudstand's Mod Options keeps its own copy of the values. The mod's config stays the one that counts: it is
## pushed there at start and after every change made elsewhere, and changes made there are saved here.

const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const MOD_ID := "der_floh-auto_brotato"
const MANAGER_PATH := "/root/ModLoader/Oudstand-ModOptions/ModOptions"
const SOURCE := "oudstand"
const TOGGLES := [Settings.AUTO_RECYCLE, Settings.AUTO_TAKE, Settings.AUTO_LEVEL_UP, Settings.AUTO_NEXT_WAVE]
const SLIDERS := [Settings.NEXT_WAVE_DELAY, Settings.NEXT_WAVE_LIMIT]

var _settings: Node
var _manager: Node
var _pushing := false


func _init(settings: Node) -> void:
	_settings = settings


func connect_to(tree: SceneTree) -> bool:
	_manager = tree.root.get_node_or_null(MANAGER_PATH)
	if _manager == null or not _manager.has_method("register_mod_options") or not _manager.has_signal("config_changed"):
		return false
	if not MOD_ID in _manager.get_registered_mods():
		_manager.register_mod_options(MOD_ID, _options())
	for key in Settings.DEFAULTS:
		_push(key)
	var _from_oudstand = _manager.connect("config_changed", self, "_on_config_changed")
	var _to_oudstand = _settings.connect("changed", self, "_on_settings_changed")
	return true


func registered_values() -> Dictionary:
	return _manager.get_mod_values(MOD_ID) if is_instance_valid(_manager) else {}


static func _options() -> Dictionary:
	var options := []
	for key in TOGGLES:
		options.append({"type": "toggle", "id": key, "label": key.to_upper(), "default": Settings.DEFAULTS[key]})
	for key in SLIDERS:
		var number_range: Array = Settings.NUMBER_RANGES[key]
		options.append({"type": "slider", "id": key, "label": key.to_upper(), "default": Settings.DEFAULTS[key], "min": number_range[0], "max": number_range[1], "step": 1.0, "display_as_integer": true})
	return {"tab_title": "AUTO_BROTATO", "info_text": "AUTO_BROTATO_INFO", "options": options}


# set_value reports every change through config_changed, also the ones pushed from here.
func _push(key: String) -> void:
	var value = _settings.get_value(key)
	if _manager.get_value(MOD_ID, key) == value:
		return
	_pushing = true
	_manager.set_value(MOD_ID, key, value)
	_pushing = false


func _on_config_changed(mod_id: String, option_id: String, value) -> void:
	if mod_id == MOD_ID and not _pushing and Settings.DEFAULTS.has(option_id):
		_settings.set_value(option_id, value, SOURCE)


func _on_settings_changed(key: String, source: String) -> void:
	if source != SOURCE and Settings.DEFAULTS.has(key) and is_instance_valid(_manager):
		_push(key)
