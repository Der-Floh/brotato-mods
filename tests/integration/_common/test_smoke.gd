extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# Runs first in every session, whatever mods it loads.

const SCRIPT_ERROR_MARK := "SCRIPT ERROR"
const GODOT_LOG := "user://logs/godot.log"
const MOD_LOADER_LOG := "user://logs/modloader.log"
const MOD_LOADER_ERROR_PATTERN := "^\\d{2}:\\d{2}:\\d{2}\\s+(FATAL-ERROR|ERROR)\\s"


func test_game_started_without_script_errors():
	expect_eq(_read(GODOT_LOG).count(SCRIPT_ERROR_MARK), 0, "SCRIPT ERROR lines in godot.log since the game started")


func test_mod_loader_reported_no_errors():
	var pattern := RegEx.new()
	var _compiled = pattern.compile(MOD_LOADER_ERROR_PATTERN)
	var errors := []
	for line in _read(MOD_LOADER_LOG).split("\n"):
		if pattern.search(line):
			errors.append(line.strip_edges())
	expect_eq(errors, [], "errors in modloader.log since the game started")


func test_steam_achievements_stay_off():
	expect(ProgressData.is_unlock_all_save(), "the test profile uses an unlock-all save, which never reports Steam achievements")


func test_a_wave_ends_in_the_shop_and_the_next_one_starts():
	if not yield(fresh_run(), "completed"):
		return
	expect_eq(RunData.current_wave, 1, "wave of a new run")
	if not yield(end_wave(), "completed"):
		return
	expect(shop() != null, "the shop opened after wave 1")
	if not yield(next_wave(), "completed"):
		return
	expect_eq(RunData.current_wave, 2, "wave after leaving the shop")


func _read(path: String) -> String:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		fail("%s can't be read" % path)
		return ""
	var text := file.get_as_text()
	file.close()
	return text
