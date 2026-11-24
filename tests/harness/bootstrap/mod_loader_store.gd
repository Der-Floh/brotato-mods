extends "res://addons/mod_loader/mod_loader_store.gd"

# Replaces the ModLoaderStore autoload through the harness's override.cfg. The Steam build loads only
# subscribed Workshop items, and CrashReporter turns mods off after a mod error in the last log.
const LOG_NAME_BOOTSTRAP := "der_floh-test_harness:Bootstrap"


func _update_ml_options_from_cli_args() -> void:
	._update_ml_options_from_cli_args()
	ml_options.enable_mods = true
	ml_options.steam_workshop_enabled = false
	ModLoaderLog.info("Loading the zips in %s instead of Workshop items." % ml_options.override_path_to_mods, LOG_NAME_BOOTSTRAP)
