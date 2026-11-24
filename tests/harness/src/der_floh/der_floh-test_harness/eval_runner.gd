extends Reference

const JsonValue := preload("res://mods-unpacked/der_floh-test_harness/json_value.gd")
const INDENT := "\t"
const SNIPPET_HEAD := """extends Reference

var tree: SceneTree
var access


func wave():
	return access.wave()


func shop():
	return access.shop()


func player(index := 0):
	return access.player(index)


func mod(mod_id: String):
	return access.mod_main(mod_id)


func run():
"""


func run(code: String, access):
	var script := GDScript.new()
	script.source_code = SNIPPET_HEAD + _indent(code)
	var error := script.reload()
	if error != OK:
		return {"ok": false, "error": "The snippet did not compile (error %d); the reason is in the test profile's godot.log." % error}
	var snippet = script.new()
	snippet.tree = access.tree
	snippet.access = access
	var result = snippet.run()
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	return {"ok": true, "result": JsonValue.convert_value(result)}


static func _indent(code: String) -> String:
	var body := code.strip_edges(false, true)
	if body.empty():
		return INDENT + "pass\n"
	var lines := PoolStringArray()
	for line in body.split("\n"):
		lines.append(INDENT + line.trim_suffix("\r"))
	return lines.join("\n") + "\n"
