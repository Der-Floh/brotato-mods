extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# The shop starts the next wave by itself, after an optional countdown that Esc cancels.

const MOD_ID := "der_floh-auto_brotato"
const DELAY := 2.0
const LEFT_ALONE_SEC := 1.5
const ENDLESS_SHOP_WAVE := 19


func before_each():
	use_value(DebugService, "no_enemies", true)
	use_setting(MOD_ID, "auto_start_next_wave", false)
	use_setting(MOD_ID, "next_wave_delay", 0.0)
	use_setting(MOD_ID, "next_wave_limit", 0.0)


func test_without_delay_the_next_wave_starts():
	if not yield(_fresh_shop(), "completed"):
		return
	use_setting(MOD_ID, "auto_start_next_wave", true)
	expect(yield(_await_wave(2), "completed"), "wave 2 started from the shop")


func test_the_countdown_shows_and_esc_cancels_it():
	if not yield(_shop_with_countdown(), "completed"):
		return
	expect(_automator().is_counting(), "the countdown runs")
	expect(_countdown_label_shown(), "the countdown shows above the Go button")
	yield(press_key(KEY_ESCAPE), "completed")
	expect(not _automator().is_counting(), "Esc stopped the countdown")
	expect(not tree.paused, "Esc didn't open the pause menu")
	yield(tree.create_timer(DELAY + 0.5), "timeout")
	expect(shop() != null, "the shop stays open")


func test_pausing_holds_the_countdown():
	if not yield(_shop_with_countdown(), "completed"):
		return
	tree.paused = true
	yield(tree.create_timer(DELAY + 0.5, true), "timeout")
	expect(shop() != null, "the shop stays open while paused")
	expect_near(_automator().remaining_seconds(), DELAY, 0.2, "seconds left after the pause")
	tree.paused = false
	expect(yield(_await_wave(2), "completed"), "wave 2 started after the countdown")


func test_an_open_popup_holds_the_countdown():
	if not yield(_shop_with_countdown(), "completed"):
		return
	var block: Control = shop()._block_background
	block.visible = true
	yield(tree.create_timer(DELAY + 0.5), "timeout")
	expect(shop() != null, "the shop stays open while a popup is open")
	block.visible = false
	expect(yield(_await_wave(2), "completed"), "wave 2 started once the popup closed")


func test_the_wave_limit_stops_auto_start():
	if not yield(_fresh_shop(), "completed"):
		return
	use_setting(MOD_ID, "next_wave_limit", 1.0)
	use_setting(MOD_ID, "auto_start_next_wave", true)
	yield(tree.create_timer(LEFT_ALONE_SEC), "timeout")
	expect(shop() != null, "wave 2 is above the limit of 1")


func test_the_endless_choice_is_left_to_the_player():
	if not yield(fresh_run(), "completed"):
		return
	RunData.current_wave = ENDLESS_SHOP_WAVE
	if not yield(in_shop(), "completed"):
		return
	expect(RunData.should_show_endless_button(), "the shop offers endless mode")
	use_setting(MOD_ID, "auto_start_next_wave", true)
	yield(tree.create_timer(LEFT_ALONE_SEC), "timeout")
	expect(shop() != null, "the shop after wave 19 waits for the player")


func test_a_resumed_shop_is_left_to_the_player():
	if not yield(_fresh_shop(), "completed"):
		return
	# Like a real resume, the first shop is on screen for a moment before the next one loads.
	yield(frames(3), "completed")
	var _changed = tree.change_scene(RunData.get_shop_scene_path())
	yield(frames(3), "completed")
	use_setting(MOD_ID, "auto_start_next_wave", true)
	yield(tree.create_timer(LEFT_ALONE_SEC), "timeout")
	expect(shop() != null, "a shop not reached from a wave waits for the player")


func _fresh_shop():
	if not yield(fresh_run(), "completed"):
		return false
	var opened = yield(in_shop(), "completed")
	return opened


func _shop_with_countdown():
	if not yield(_fresh_shop(), "completed"):
		return false
	use_setting(MOD_ID, "next_wave_delay", DELAY)
	use_setting(MOD_ID, "auto_start_next_wave", true)
	yield(frames(), "completed")
	return true


func _await_wave(wave: int):
	var started = yield(access.wait_until(self, "_is_in_wave", 10000, [wave]), "completed")
	return started


func _is_in_wave(wave: int) -> bool:
	return access.wave() != null and RunData.current_wave == wave


func _automator():
	return mod(MOD_ID).shop_automator()


func _countdown_label_shown() -> bool:
	var go_button: Control = shop()._get_go_button(0)
	var box = go_button.get_parent()
	var index := go_button.get_index()
	return index > 0 and box.get_child(index - 1) is Label and box.get_child(index - 1).visible
