extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# Settings live in GML's config system: off by default, saved to a "user" config on the first change.

const MOD_ID := "der_floh-auto_brotato"
const SWITCHES := ["auto_recycle_crate_items", "auto_take_crate_items", "auto_pick_level_ups", "auto_start_next_wave"]
const USER_CONFIG_PATH := "user://configs/der_floh-auto_brotato/user.json"


func test_everything_starts_switched_off():
	for switch in SWITCHES:
		expect_eq(mod(MOD_ID).call("get_" + switch), false, switch)
	expect_eq(mod(MOD_ID).get_next_wave_delay(), 0.0, "next_wave_delay")
	expect_eq(mod(MOD_ID).get_next_wave_limit(), 0.0, "next_wave_limit")


func test_a_change_is_saved_in_the_user_config():
	use_setting(MOD_ID, "next_wave_delay", 3.0)
	use_setting(MOD_ID, "item_rules", {"item_helmet": {"mode": "recycle"}})
	use_setting(MOD_ID, "level_up_weights", {"upgrade_armor": 25.0})
	var settings = mod(MOD_ID).settings()
	settings.save_now()
	var config = ModLoaderStore.mod_data[MOD_ID].current_config
	expect_eq(config.name, "user", "current config")
	expect_eq(config.validate(), "", "validation of the config with the rule lists")
	var saved := _read_json(USER_CONFIG_PATH)
	expect_eq(typeof(saved.get("next_wave_delay")), TYPE_REAL, "type of a saved number")
	expect_eq(saved.get("next_wave_delay"), 3.0, "saved delay")
	expect_eq(saved.get("item_rules"), {"item_helmet": {"mode": "recycle"}}, "saved item rules")
	expect_eq(saved.get("level_up_weights"), {"upgrade_armor": 25.0}, "saved weights")


func test_numbers_stay_in_their_range():
	use_setting(MOD_ID, "next_wave_delay", 42.0)
	expect_eq(mod(MOD_ID).get_next_wave_delay(), 10.0, "a delay above 10 s")
	use_setting(MOD_ID, "next_wave_limit", 2.6)
	expect_eq(mod(MOD_ID).get_next_wave_limit(), 3.0, "a fractional wave limit")


func _read_json(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		fail("%s can't be read" % path)
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}
