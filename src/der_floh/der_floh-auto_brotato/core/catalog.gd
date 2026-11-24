extends Reference

## What the pages list: every item and weapon a crate can hold in this install, and the level-up kinds.

const EXTRA_ITEM_LISTS := ["meca_items", "mutant_items", "evolution_items"]
const TIER_COUNT := 4


## Items that can come from a crate, one per id, sorted by tier and name.
static func crate_items() -> Array:
	var by_id := {}
	for item in _all_candidates("items", true):
		if _is_lootable(item) and not by_id.has(item.my_id):
			by_id[item.my_id] = item
	return _sorted(by_id.values())


## Weapons, one per weapon id (its lowest tier); crates only hold them for characters like the Survivor.
static func crate_weapons() -> Array:
	var by_id := {}
	for weapon in _all_candidates("weapons", false):
		if not _is_lootable(weapon) or not "weapon_id" in weapon:
			continue
		var known = by_id.get(weapon.weapon_id)
		if known == null or weapon.tier < known.tier:
			by_id[weapon.weapon_id] = weapon
	return _sorted(by_id.values())


## One entry per level-up kind in the game's order: [upgrade_id, the tier-I upgrade].
static func upgrade_kinds() -> Array:
	var kinds := []
	var seen := {}
	var upgrades: Array = ItemService.upgrades.duplicate()
	if ItemService.weapon_slot_upgrade_data != null:
		upgrades.append(ItemService.weapon_slot_upgrade_data)
	for upgrade in upgrades:
		if upgrade == null or not "upgrade_id" in upgrade or not upgrade.upgrade_id is String:
			continue
		var known = seen.get(upgrade.upgrade_id)
		if known == null:
			seen[upgrade.upgrade_id] = kinds.size()
			kinds.append([upgrade.upgrade_id, upgrade])
		elif upgrade.tier < kinds[known][1].tier:
			kinds[known][1] = upgrade
	return kinds


static func rule_id(element) -> String:
	return element.weapon_id if element is WeaponData else element.my_id


static func _all_candidates(list_name: String, with_extra_lists: bool) -> Array:
	var candidates := []
	for item_set in _owned_item_sets():
		candidates.append_array(_list(item_set, list_name))
		if with_extra_lists:
			for extra in EXTRA_ITEM_LISTS:
				candidates.append_array(_list(item_set, extra))
	candidates.append_array(ItemService.get(list_name))
	candidates.append_array(_pooled(list_name))
	return candidates


static func _owned_item_sets() -> Array:
	var item_sets := [ItemService.base_game_item_set]
	for update_data in ItemService.update_data_list:
		if update_data != null and update_data.item_set != null and ProgressData.is_update_data_available(update_data):
			item_sets.append(update_data.item_set)
	return item_sets


# The live loot pools of a running game, which also hold items other mods added there. The autoload goes
# through a variable: mods compile before it exists, and Godot folds `in` on a constant at parse time.
static func _pooled(list_name: String) -> Array:
	var pooled := []
	var item_service = ItemService
	if not "_tiers_data" in item_service or item_service._tiers_data.size() < TIER_COUNT:
		return pooled
	var pool_type: int = ItemService.TierData.ITEMS if list_name == "items" else ItemService.TierData.WEAPONS
	for tier in TIER_COUNT:
		pooled.append_array(ItemService.get_pool(tier, pool_type))
	return pooled


static func _list(item_set, list_name: String) -> Array:
	if item_set == null or not list_name in item_set or not item_set.get(list_name) is Array:
		return []
	return item_set.get(list_name)


static func _is_lootable(element) -> bool:
	if element == null or not element.can_be_looted:
		return false
	return not "max_nb" in element or element.max_nb != 0


static func _sorted(elements: Array) -> Array:
	elements.sort_custom(ElementOrder.new(), "before")
	return elements


class ElementOrder:
	func before(a, b) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return TranslationServer.translate(a.name) < TranslationServer.translate(b.name)
