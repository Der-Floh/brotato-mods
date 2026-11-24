extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# Crate items are taken or recycled by their rule, or left to the player.

const MOD_ID := "der_floh-auto_brotato"
const ITEM := "item_helmet"
const OTHER_WEAPONS := ["weapon_pistol_1", "weapon_shredder_1", "weapon_slingshot_1", "weapon_stick_1", "weapon_crowbar_1"]
const CRATE_WEAPON := "weapon_dagger_1"
const CURSE_RULE := {ITEM: {"mode": "cursed_min", "min_curse": 50.0}}
const LEFT_ALONE_MS := 1500
const PLAYER := 0


func before_each():
	use_value(DebugService, "no_enemies", true)
	use_setting(MOD_ID, "auto_start_next_wave", false)
	use_setting(MOD_ID, "auto_pick_level_ups", false)


func test_a_crossed_out_item_is_recycled():
	if not yield(_crate_shows(ITEM), "completed"):
		return
	use_setting(MOD_ID, "item_rules", {ITEM: {"mode": "recycle"}})
	var gold_before: int = RunData.get_player_gold(PLAYER)
	var value: int = ItemService.get_item_box_recycling_value(RunData.current_wave, _item(ITEM).value, PLAYER)
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	expect(yield(await_shop(), "completed"), "the shop opened after the crate")
	expect_eq(RunData.get_player_gold(PLAYER), gold_before + value, "materials after recycling")
	expect(not _has_item(ITEM), "the recycled item was not added")


func test_a_wanted_item_is_taken():
	if not yield(_crate_shows(ITEM), "completed"):
		return
	use_setting(MOD_ID, "auto_take_crate_items", true)
	expect(yield(await_shop(), "completed"), "the shop opened after the crate")
	expect(_has_item(ITEM), "the item was taken")


func test_each_switch_works_alone():
	if not yield(_crate_shows(ITEM), "completed"):
		return
	use_setting(MOD_ID, "item_rules", {ITEM: {"mode": "recycle"}})
	use_setting(MOD_ID, "auto_take_crate_items", true)
	yield(tree.create_timer(LEFT_ALONE_MS / 1000.0), "timeout")
	expect(access.is_choosing(PLAYER), "taking alone leaves a crossed-out item")
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	expect(yield(await_shop(), "completed"), "recycling then answers it")


func test_a_curse_below_the_minimum_is_recycled():
	if not _curses_possible():
		return
	if not yield(_crate_shows(ITEM, 1, true, 0.4), "completed"):
		return
	_answer_with_curse_rule()
	expect(yield(await_shop(), "completed"), "the shop opened after the crate")
	expect(not _has_item(ITEM), "a 40% curse was recycled against a 50% minimum")


func test_a_curse_at_the_minimum_is_taken():
	if not _curses_possible():
		return
	if not yield(_crate_shows(ITEM, 1, true, 0.5), "completed"):
		return
	_answer_with_curse_rule()
	expect(yield(await_shop(), "completed"), "the shop opened after the crate")
	expect(_has_item(ITEM), "a 50% curse was taken against a 50% minimum")


func _curses_possible() -> bool:
	if not ProgressData.has_item_set("abyssal_terrors"):
		skip("needs Abyssal Terrors")
		return false
	return true


func _answer_with_curse_rule() -> void:
	use_setting(MOD_ID, "item_rules", CURSE_RULE)
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	use_setting(MOD_ID, "auto_take_crate_items", true)


func test_an_item_that_cannot_be_taken_waits():
	if not yield(fresh_run(), "completed"):
		return
	for weapon_id in OTHER_WEAPONS:
		if not yield(give_weapon(weapon_id), "completed"):
			return
	if not yield(_crate_shows(CRATE_WEAPON, 1, false, 0.0, true, false), "completed"):
		return
	use_setting(MOD_ID, "auto_take_crate_items", true)
	yield(tree.create_timer(LEFT_ALONE_MS / 1000.0), "timeout")
	expect(access.is_choosing(PLAYER), "a weapon without a free slot waits")
	access.upgrade_container(PLAYER)._discard_button.emit_signal("pressed")
	expect(yield(await_shop(), "completed"), "the shop opened after recycling by hand")


func test_everything_on_reaches_the_shop():
	if not yield(fresh_run(), "completed"):
		return
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	use_setting(MOD_ID, "auto_take_crate_items", true)
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	if not yield(queue_crates(2), "completed"):
		return
	if not yield(queue_level_ups(2), "completed"):
		return
	if not yield(end_wave_async(), "completed"):
		return
	expect(yield(await_shop(), "completed"), "the shop opened with every switch on")


## Ends a new run's wave with crates and shows the given item (or weapon) in the first one.
func _crate_shows(element_id: String, crates := 1, cursed := false, curse_factor := 0.0, weapon := false, new_run := true):
	if new_run and not yield(fresh_run(), "completed"):
		return false
	if not yield(queue_crates(crates), "completed"):
		return false
	if not yield(end_wave_async(), "completed"):
		return false
	var shown = yield(await_offer(PLAYER), "completed")
	if not expect(shown, "a crate item showed"):
		return false
	var replaced = yield(show_crate_item(element_id, cursed, curse_factor, weapon), "completed")
	return replaced


func _item(item_id: String):
	for item in ItemService.items:
		if item.my_id == item_id:
			return item
	return null


func _has_item(item_id: String) -> bool:
	for item in RunData.get_player_items(PLAYER):
		if item.my_id == item_id:
			return true
	return false
