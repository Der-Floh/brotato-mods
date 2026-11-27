extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# The item and level-up lists are read from the game's data, so items and level-ups that other mods add are
# listed and automated like the game's own.

const MOD_ID := "der_floh-auto_brotato"
const CATALOG_PATH := "res://mods-unpacked/der_floh-auto_brotato/core/catalog.gd"
const TEMPLATE_ITEM := "item_helmet"
const NEW_ITEM := "item_auto_brotato_test"
const NEW_POOL_ITEM := "item_auto_brotato_pool_test"
const NEW_KIND := "upgrade_auto_brotato_test"
const SURVIVOR := "character_survivor"
const PLAYER := 0

var catalog
var _recycled := []
var _picked := []


func before_each():
	catalog = load(CATALOG_PATH)
	use_value(DebugService, "no_enemies", true)
	use_setting(MOD_ID, "auto_start_next_wave", false)


func test_items_and_level_ups_from_other_mods_are_listed():
	if not yield(in_wave(), "completed"):
		return
	_add_for_this_test(ItemService.items, _new_item(NEW_ITEM))
	var pooled = _new_item(NEW_POOL_ITEM)
	_add_for_this_test(ItemService._tiers_data[pooled.tier][ItemService.TierData.ITEMS], pooled)
	_add_for_this_test(ItemService.upgrades, _new_kind())
	var item_ids := []
	for item in catalog.crate_items():
		item_ids.append(item.my_id)
	expect(item_ids.has(NEW_ITEM), "an item added to the game's item list is listed")
	expect(item_ids.has(NEW_POOL_ITEM), "an item added to a loot pool is listed")
	var kind_ids := []
	for kind in catalog.upgrade_kinds():
		kind_ids.append(kind[0])
	expect(kind_ids.has(NEW_KIND), "a level-up kind added to the game's list is listed")


func test_weapons_are_listed_only_when_a_character_gets_them_from_crates():
	var survivor_owned := false
	for character in ItemService.characters:
		survivor_owned = survivor_owned or character.my_id == SURVIVOR
	expect_eq(catalog.crates_can_hold_weapons(), survivor_owned, "crates can hold weapons, as they do for the Survivor")
	expect(not catalog.crate_weapons().empty(), "the weapon list")


func test_a_crossed_out_item_from_another_mod_is_recycled():
	if not yield(fresh_run(), "completed"):
		return
	_add_for_this_test(ItemService.items, _new_item(NEW_ITEM))
	use_setting(MOD_ID, "item_rules", {NEW_ITEM: {"mode": "recycle"}})
	if not yield(queue_crates(1), "completed"):
		return
	if not yield(end_wave_async(), "completed"):
		return
	if not expect(yield(await_offer(PLAYER), "completed"), "a crate item showed"):
		return
	if not yield(show_crate_item(NEW_ITEM), "completed"):
		return
	var container = access.upgrade_container(PLAYER)
	var _connected = container.connect("item_discard_button_pressed", self, "_on_recycled")
	use_setting(MOD_ID, "auto_recycle_crate_items", true)
	expect(yield(await_shop(), "completed"), "the shop opened after the crate")
	expect_eq(_ids(_recycled), [NEW_ITEM], "recycled items")


func test_a_level_up_kind_from_another_mod_is_picked():
	if not yield(fresh_run(), "completed"):
		return
	_offer_only(_new_kind())
	use_setting(MOD_ID, "level_up_weights", {})
	if not yield(queue_level_ups(1), "completed"):
		return
	var container = access.upgrade_container(PLAYER)
	var _connected = container.connect("choose_button_pressed", self, "_on_picked")
	use_setting(MOD_ID, "auto_pick_level_ups", true)
	if not yield(end_wave_async(), "completed"):
		return
	expect(yield(await_shop(), "completed"), "the shop opened after the level-up")
	var picked_kinds := []
	for upgrade in _picked:
		picked_kinds.append(upgrade.upgrade_id)
	expect_eq(picked_kinds, [NEW_KIND], "picked level-up kinds")


## A copy of a game item under a new id, as another mod would add it.
func _new_item(item_id: String) -> Resource:
	var item: Resource
	for template in ItemService.items:
		if template.my_id == TEMPLATE_ITEM:
			item = template.duplicate()
			break
	item.my_id = item_id
	item.my_id_hash = Keys.generate_hash(item_id)
	return item


## A copy of a game level-up under a new kind; it keeps the template's my_id, so a saved run stays loadable.
func _new_kind() -> Resource:
	var upgrade: Resource = ItemService.upgrades[0].duplicate()
	upgrade.upgrade_id = NEW_KIND
	upgrade.upgrade_id_hash = Keys.generate_hash(NEW_KIND)
	return upgrade


func _add_for_this_test(list: Array, element) -> void:
	list.append(element)
	on_cleanup(self, "_remove_from", [list, element])


func _remove_from(list: Array, element) -> void:
	list.erase(element)


## Every level-up offered until the test ends is the given one.
func _offer_only(upgrade) -> void:
	var upgrades_pool: int = ItemService.TierData.UPGRADES
	for tier_data in ItemService._tiers_data:
		on_cleanup(self, "_restore_pool", [tier_data, tier_data[upgrades_pool]])
		tier_data[upgrades_pool] = [upgrade]


func _restore_pool(tier_data: Array, pool: Array) -> void:
	tier_data[ItemService.TierData.UPGRADES] = pool


func _on_recycled(item) -> void:
	_recycled.append(item)


func _on_picked(upgrade) -> void:
	_picked.append(upgrade)


static func _ids(elements: Array) -> Array:
	var ids := []
	for element in elements:
		ids.append(element.my_id)
	return ids
