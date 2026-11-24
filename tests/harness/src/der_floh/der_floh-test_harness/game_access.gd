extends Reference

const WAVE_SCENE := "res://main.tscn"
const SHOP_SCENES := ["res://ui/menus/shop/shop.tscn", "res://ui/menus/shop/coop_shop.tscn"]
const END_RUN_SCENES := ["res://ui/menus/run/end_run.tscn", "res://ui/menus/run/coop_end_run.tscn"]
const TITLE_SCREEN_SCENE := "res://ui/menus/title_screen/title_screen.tscn"
const MOD_MAIN_PATH := "res://mods-unpacked/%s/mod_main.gd"

var tree: SceneTree


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


func autoload(autoload_name: String) -> Node:
	return tree.root.get_node_or_null(autoload_name)


func scene() -> Node:
	var current = tree.current_scene
	return current if is_instance_valid(current) and not current.is_queued_for_deletion() else null


func scene_path() -> String:
	var current := scene()
	return current.filename if current else ""


## The wave scene (main.tscn) once its players have spawned.
func wave() -> Node:
	var current := scene()
	return current if current and current.filename == WAVE_SCENE and not current._players.empty() else null


func shop() -> Node:
	var current := scene()
	return current if current and current.filename in SHOP_SCENES else null


func end_run() -> Node:
	var current := scene()
	return current if current and current.filename in END_RUN_SCENES else null


func title_screen() -> Node:
	var current := scene()
	return current if current and current.filename == TITLE_SCREEN_SCENE else null


func player(index := 0) -> Node:
	var current := wave()
	if current == null or index >= current._players.size():
		return null
	var found = current._players[index]
	return found if is_instance_valid(found) else null


func mod_main(mod_id: String) -> Resource:
	var path := MOD_MAIN_PATH % mod_id
	return load(path) if ResourceLoader.exists(path) else null


func is_mod_active(mod_id: String) -> bool:
	var store := autoload("ModLoaderStore")
	return store != null and store.mod_data.has(mod_id) and store.mod_data[mod_id].is_active


## Waits until target.call(method) is true; always waits at least one frame, so callers can yield on it.
func wait_until(target: Object, method: String, timeout_ms: int):
	var deadline := OS.get_ticks_msec() + timeout_ms
	yield(tree, "idle_frame")
	while not target.call(method):
		if OS.get_ticks_msec() > deadline:
			return false
		yield(tree, "idle_frame")
	return true
