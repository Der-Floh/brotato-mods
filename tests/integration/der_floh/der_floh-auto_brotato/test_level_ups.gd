extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# Level-ups at the end of a wave are picked by weight, or left to the player.

const MOD_ID := "der_floh-auto_brotato"
const LEFT_ALONE_MS := 1500
const PLAYER := 0


func before_each():
	use_value(DebugService, "no_enemies", true)
	use_setting(MOD_ID, "auto_start_next_wave", false)


func test_the_only_weighted_kind_is_picked():
	if not yield(_level_up_shown(1), "completed"):
		return
	var offered := _offered()
	var chosen = offered[1]
	use_setting(MOD_ID, "level_up_weights", _weights_with_only(chosen.upgrade_id))
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	expect(yield(await_shop(), "completed"), "the shop opened after the level-up")
	expect_eq(RunData.get_player_upgrades(PLAYER).back(), chosen.my_id_hash, "picked level-up")


func test_several_level_ups_reach_the_shop():
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	if not yield(_level_up_shown(3), "completed"):
		return
	expect(yield(await_shop(), "completed"), "the shop opened after three level-ups")


func test_weights_of_0_leave_the_level_up_to_the_player():
	if not yield(_level_up_shown(1), "completed"):
		return
	use_setting(MOD_ID, "level_up_weights", _weights_with_only(""))
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	yield(tree.create_timer(LEFT_ALONE_MS / 1000.0), "timeout")
	expect(access.is_choosing(PLAYER), "the level-up still waits")
	yield(_pick_by_hand(), "completed")


func test_switched_off_leaves_the_level_up_to_the_player():
	use_setting(MOD_ID, "auto_pick_level_ups", false)
	if not yield(_level_up_shown(1), "completed"):
		return
	yield(tree.create_timer(LEFT_ALONE_MS / 1000.0), "timeout")
	expect(access.is_choosing(PLAYER), "the level-up still waits")
	yield(_pick_by_hand(), "completed")


func _level_up_shown(count: int):
	if not yield(fresh_run(), "completed"):
		return false
	if not yield(queue_level_ups(count), "completed"):
		return false
	if not yield(end_wave_async(), "completed"):
		return false
	var shown = yield(await_offer(PLAYER), "completed")
	return expect(shown, "a level-up showed")


func _offered() -> Array:
	var container = access.upgrade_container(PLAYER)
	return container._old_upgrades.duplicate()


func _weights_with_only(upgrade_id: String) -> Dictionary:
	var weights := {}
	for upgrade in ItemService.upgrades:
		weights[upgrade.upgrade_id] = 0.0
	weights[ItemService.weapon_slot_upgrade_data.upgrade_id] = 0.0
	if upgrade_id != "":
		weights[upgrade_id] = 100.0
	return weights


func _pick_by_hand():
	var container = access.upgrade_container(PLAYER)
	container._get_upgrade_uis()[0].button.emit_signal("pressed")
	expect(yield(await_shop(), "completed"), "the shop opened after picking by hand")
