extends Reference

## dami's Mod Options builds its controls from the manifest's config_schema but doesn't save them, so its
## changes are saved here, and changes made elsewhere are handed back to it.

const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const MOD_ID := "der_floh-auto_brotato"
const INTERFACE_PATH := "/root/ModLoader/dami-ModOptions/ModsConfigInterface"
const SOURCE := "dami"

var _settings: Node
var _interface: Node


func _init(settings: Node) -> void:
	_settings = settings


func connect_to(tree: SceneTree) -> bool:
	_interface = tree.root.get_node_or_null(INTERFACE_PATH)
	if _interface == null or not _interface.has_signal("setting_changed") or not _interface.has_method("load_config"):
		return false
	var _from_dami = _interface.connect("setting_changed", self, "_on_dami_setting_changed")
	var _to_dami = _settings.connect("changed", self, "_on_settings_changed")
	return true


func _on_dami_setting_changed(setting_name: String, value, mod_name: String) -> void:
	if mod_name == MOD_ID and Settings.DEFAULTS.has(setting_name):
		_settings.set_value(setting_name, value, SOURCE)


func _on_settings_changed(key: String, source: String) -> void:
	if source == SOURCE or not Settings.DEFAULTS.has(key) or not is_instance_valid(_interface):
		return
	var mod_data = ModLoaderStore.mod_data.get(MOD_ID)
	if mod_data != null:
		_interface.load_config(mod_data)
