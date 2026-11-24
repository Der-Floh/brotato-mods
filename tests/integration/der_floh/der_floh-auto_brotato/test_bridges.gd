extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# The switches and sliders in dami's and Oudstand's Mod Options stay in step with the mod's own settings.

const MOD_ID := "der_floh-auto_brotato"
const DAMI := "dami-ModOptions"
const OUDSTAND := "Oudstand-ModOptions"
const DAMI_INTERFACE := "/root/ModLoader/dami-ModOptions/ModsConfigInterface"
const OUDSTAND_MANAGER := "/root/ModLoader/Oudstand-ModOptions/ModOptions"


func test_dami_changes_are_saved():
	if not require_mods([DAMI]):
		return
	use_setting(MOD_ID, "auto_take_crate_items", false)
	tree.root.get_node(DAMI_INTERFACE).on_setting_changed("auto_take_crate_items", true, MOD_ID)
	expect_eq(mod(MOD_ID).get_auto_take_crate_items(), true, "the setting after switching it in dami's menu")


func test_dami_shows_changes_made_elsewhere():
	if not require_mods([DAMI]):
		return
	use_setting(MOD_ID, "next_wave_delay", 4.0)
	expect_eq(tree.root.get_node(DAMI_INTERFACE).get_settings(MOD_ID).get("next_wave_delay"), 4.0, "dami's value after changing it elsewhere")


func test_oudstand_registers_once_with_the_mod_values():
	if not require_mods([OUDSTAND]):
		return
	var manager = tree.root.get_node(OUDSTAND_MANAGER)
	expect_eq(manager.get_registered_mods().count(MOD_ID), 1, "registrations")
	for key in ["auto_recycle_crate_items", "next_wave_delay"]:
		expect_eq(manager.get_value(MOD_ID, key), mod(MOD_ID).call("get_" + key), "Oudstand's " + key)


func test_oudstand_changes_are_saved():
	if not require_mods([OUDSTAND]):
		return
	use_setting(MOD_ID, "auto_pick_level_ups", false)
	tree.root.get_node(OUDSTAND_MANAGER).set_value(MOD_ID, "auto_pick_level_ups", true)
	expect_eq(mod(MOD_ID).get_auto_pick_level_ups(), true, "the setting after switching it in Oudstand's menu")


func test_oudstand_shows_changes_made_elsewhere():
	if not require_mods([OUDSTAND]):
		return
	use_setting(MOD_ID, "next_wave_limit", 25.0)
	expect_eq(tree.root.get_node(OUDSTAND_MANAGER).get_value(MOD_ID, "next_wave_limit"), 25.0, "Oudstand's value after changing it elsewhere")
