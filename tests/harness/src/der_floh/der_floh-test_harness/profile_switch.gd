extends Reference

# Godot reads override.cfg next to the exe at startup; this one points user:// at a separate test profile
# and swaps in the bootstrap ModLoaderStore, which harness.ps1 copies into that profile.
const FILE_NAME := "override.cfg"
const PROFILE_NAME := "Brotato Test"
const MARKER := "; der_floh-test_harness: temporary switch to the " + PROFILE_NAME + " profile"


static func file_path() -> String:
	return OS.get_executable_path().get_base_dir().plus_file(FILE_NAME)


static func is_active() -> bool:
	return OS.get_user_data_dir().get_file() == PROFILE_NAME


static func remove() -> void:
	var path := file_path()
	var file := File.new()
	if not file.file_exists(path) or file.open(path, File.READ) != OK:
		return
	var written_by_harness := file.get_as_text().begins_with(MARKER)
	file.close()
	if written_by_harness:
		Directory.new().remove(path)
