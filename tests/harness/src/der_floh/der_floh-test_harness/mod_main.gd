extends Node

const LOG_NAME := "der_floh-test_harness:Main"
const PORT_ARG := "--harness-port="
const TOKEN_ARG := "--harness-token="
const SCREENSHOTS_ARG := "--harness-screenshots="
const DEFAULT_SCREENSHOT_FOLDER := "harness_screenshots"
const WINDOW_SIZE := Vector2(1280, 720)
const TEST_LANGUAGE := "en"
const ProfileSwitch := preload("res://mods-unpacked/der_floh-test_harness/profile_switch.gd")
const Server := preload("res://mods-unpacked/der_floh-test_harness/server.gd")
const Commands := preload("res://mods-unpacked/der_floh-test_harness/commands.gd")
const GameAccess := preload("res://mods-unpacked/der_floh-test_harness/game_access.gd")

var _port := 0
var _token := ""
var _screenshot_dir := ""
var _server
var _commands


func _init() -> void:
	ProfileSwitch.remove()
	_read_args()


# Runs before the later autoloads' _ready, so ProgressData has not loaded the save yet.
func _ready():
	if _port <= 0 or _token.empty():
		ModLoaderLog.warning("No --harness-port/--harness-token args, so the harness stays off.", LOG_NAME)
		return
	if not ProfileSwitch.is_active():
		_close_outside_test_profile()
		return
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.no_fullscreen_on_launch = true
	var _connected = ProgressData.connect("ready", self, "_prepare_test_profile", [], CONNECT_ONESHOT)
	yield(get_tree(), "idle_frame")
	_use_test_window()
	_start_server()


func _process(_delta: float) -> void:
	if _server:
		_server.poll()


func _exit_tree() -> void:
	if _server:
		_server.stop()


func _read_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with(PORT_ARG):
			_port = int(arg.trim_prefix(PORT_ARG))
		elif arg.begins_with(TOKEN_ARG):
			_token = arg.trim_prefix(TOKEN_ARG)
		elif arg.begins_with(SCREENSHOTS_ARG):
			_screenshot_dir = arg.trim_prefix(SCREENSHOTS_ARG)
	if _screenshot_dir.empty():
		_screenshot_dir = OS.get_user_data_dir().plus_file(DEFAULT_SCREENSHOT_FOLDER)


func _start_server() -> void:
	_commands = Commands.new(GameAccess.new(get_tree()), _screenshot_dir)
	_server = Server.new()
	var error: int = _server.start(_port, _token, _commands, "handle")
	if error != OK:
		ModLoaderLog.error("Could not listen on 127.0.0.1:%d (error %d)." % [_port, error], LOG_NAME)
		_server = null
		return
	ModLoaderLog.info("Listening on 127.0.0.1:%d." % _port, LOG_NAME)


# Challenges completed in an ordinary save also unlock the Steam achievements; an unlock-all save,
# the game's own option, never reports them. Connected to ProgressData's ready, which comes before
# ChallengeService syncs completed challenges to Steam. English keeps labels the same for every tester.
func _prepare_test_profile() -> void:
	if not ProgressData.is_unlock_all_save():
		ProgressData.unlock_all_save_profile(ProgressData.current_profile_id)
	ProgressData.change_language(TEST_LANGUAGE)
	ModLoaderLog.info("The test profile uses an unlock-all save: %s." % ProgressData.is_unlock_all_save(), LOG_NAME)


# Killed rather than quit, because quitting saves the game into the profile it wrongly started in.
func _close_outside_test_profile() -> void:
	ModLoaderLog.error("Started in %s instead of the %s profile; closing without saving." % [OS.get_user_data_dir(), ProfileSwitch.PROFILE_NAME], LOG_NAME)
	OS.kill(OS.get_process_id())


func _use_test_window() -> void:
	OS.window_fullscreen = false
	OS.window_maximized = false
	OS.window_size = WINDOW_SIZE
