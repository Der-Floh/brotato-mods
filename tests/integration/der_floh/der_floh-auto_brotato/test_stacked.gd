extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# Several crates and level-ups wait at the end of a wave, and the game shows them one after another; each one
# is answered by the settings, including the extra crate items of a Treasure Map.

const MOD_ID := "der_floh-auto_brotato"
const PLAYER := 0
const CRATES := 4
const LEVEL_UPS := 3
const ZERO_WEIGHT_KINDS := 3
const TREASURE_MAP := "item_treasure_map"
const TREASURE_MAP_CRATES := 2
const CERTAIN := 100
const CHOICES_WAIT_MS := 20000

var _rules := {}
var _taken := []
var _recycled := []
var _picked := []


func before_each():
	use_value(DebugService, "no_enemies", true)
	use_setting(MOD_ID, "auto_start_next_wave", false)
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	use_setting(MOD_ID, "auto_take_crate_items", true)
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	_rules = _recycle_every_other_item()
	use_setting(MOD_ID, "item_rules", _rules)


func test_stacked_crates_and_level_ups_are_all_answered():
	if not yield(fresh_run(), "completed"):
		return
	var zero_weights := _zero_weights_for_some_kinds()
	use_setting(MOD_ID, "level_up_weights", zero_weights)
	if not yield(_end_wave_with(CRATES, LEVEL_UPS), "completed"):
		return
	expect_eq(_taken.size() + _recycled.size(), CRATES, "crate items answered")
	_expect_crate_rules_followed()
	expect_eq(_picked.size(), LEVEL_UPS, "level-ups picked")
	for upgrade in _picked:
		expect(not zero_weights.has(upgrade.upgrade_id), "%s has weight 0 but was picked" % upgrade.upgrade_id)


func test_treasure_map_items_are_answered_too():
	if not yield(fresh_run(), "completed"):
		return
	if not yield(_extra_item_in_every_crate(), "completed"):
		return
	if not yield(_end_wave_with(TREASURE_MAP_CRATES, 0), "completed"):
		return
	expect_eq(_taken.size() + _recycled.size(), TREASURE_MAP_CRATES * 2, "crate items and their extra items answered")
	_expect_crate_rules_followed()


func _end_wave_with(crates: int, level_ups: int):
	if crates > 0 and not yield(queue_crates(crates), "completed"):
		return false
	if level_ups > 0 and not yield(queue_level_ups(level_ups), "completed"):
		return false
	_record_choices()
	if not yield(end_wave_async(), "completed"):
		return false
	var reached = yield(await_shop(CHOICES_WAIT_MS), "completed")
	return expect(reached, "the shop opened after every choice")


func _record_choices() -> void:
	_taken.clear()
	_recycled.clear()
	_picked.clear()
	var container = access.upgrade_container(PLAYER)
	var _taken_connected = container.connect("item_take_button_pressed", self, "_on_taken")
	var _recycled_connected = container.connect("item_discard_button_pressed", self, "_on_recycled")
	var _picked_connected = container.connect("choose_button_pressed", self, "_on_picked")


func _on_taken(item) -> void:
	_taken.append(item)


func _on_recycled(item) -> void:
	_recycled.append(item)


func _on_picked(upgrade) -> void:
	_picked.append(upgrade)


func _expect_crate_rules_followed() -> void:
	for item in _taken:
		expect(not _rules.has(item.my_id), "%s is crossed out but was taken" % item.my_id)
	for item in _recycled:
		expect(_rules.has(item.my_id), "%s is wanted but was recycled" % item.my_id)


## A Treasure Map adds a random extra item to a crate by chance; this makes it certain. Without Abyssal
## Terrors, the player gets the Treasure Map's effect without the item.
func _extra_item_in_every_crate():
	if _owns_item(TREASURE_MAP):
		if not yield(give_item(TREASURE_MAP), "completed"):
			return false
	else:
		RunData.get_player_effect(Keys.extra_item_in_crate_hash, PLAYER).append([Keys.random_hash, CERTAIN])
		yield(frames(), "completed")
	on_cleanup(self, "_remove_extra_items")
	var extra_items: Array = RunData.get_player_effect(Keys.extra_item_in_crate_hash, PLAYER)
	for extra_item in extra_items:
		extra_item[1] = CERTAIN
	return expect(not extra_items.empty(), "the player has an extra crate item effect")


func _remove_extra_items() -> void:
	RunData.get_player_effect(Keys.extra_item_in_crate_hash, PLAYER).clear()


static func _owns_item(item_id: String) -> bool:
	for item in ItemService.items:
		if item.my_id == item_id:
			return true
	return false


## Crosses out every other item, so a crate item is about as likely to be recycled as taken.
static func _recycle_every_other_item() -> Dictionary:
	var rules := {}
	var crossed_out := false
	for item in ItemService.items:
		crossed_out = not crossed_out
		if crossed_out:
			rules[item.my_id] = {"mode": "recycle"}
	return rules


## Weight 0 for a few kinds only, so every offer of four still has a kind that can be picked.
static func _zero_weights_for_some_kinds() -> Dictionary:
	var weights := {}
	for upgrade in ItemService.upgrades:
		if weights.size() < ZERO_WEIGHT_KINDS:
			weights[upgrade.upgrade_id] = 0.0
	return weights
