extends Reference

## What the pages list, read from the game's data each time a page opens, so items, weapons and level-ups
## that updates, DLCs or other mods add show up without a list in this mod.

const CRATE_WEAPON_EFFECT := "effect_crate_give_weapon"


## Items a crate can hold, one per id, sorted by tier and name.
static func crate_items() -> Array:
	var by_id := {}
	for element in _loot_candidates():
		if _is_crate_item(element) and not by_id.has(element.my_id):
			by_id[element.my_id] = element
	return _sorted(by_id.values())


## Weapons, one per weapon id (its lowest tier); crates hold them only for characters like the Survivor.
static func crate_weapons() -> Array:
	var by_id := {}
	for element in _loot_candidates():
		if not element is WeaponData or not _is_lootable(element):
			continue
		var known = by_id.get(element.weapon_id)
		if known == null or element.tier < known.tier:
			by_id[element.weapon_id] = element
	return _sorted(by_id.values())


## Whether an owned character or item turns crate loot into weapons, as Primal Dread's Survivor does.
static func crates_can_hold_weapons() -> bool:
	var candidates := _owned_elements()
	candidates.append_array(ItemService.characters)
	candidates.append_array(ItemService.items)
	for element in candidates:
		if _gives_crate_weapons(element):
			return true
	return false


## One entry per level-up kind, in the game's order: [upgrade_id, its lowest-tier upgrade].
static func upgrade_kinds() -> Array:
	var kinds := []
	var index_by_id := {}
	for upgrade in _all_upgrades():
		if not upgrade is UpgradeData or not _is_update_owned(upgrade.required_item_set):
			continue
		var index = index_by_id.get(upgrade.upgrade_id)
		if index == null:
			index_by_id[upgrade.upgrade_id] = kinds.size()
			kinds.append([upgrade.upgrade_id, upgrade])
		elif upgrade.tier < kinds[index][1].tier:
			kinds[index][1] = upgrade
	return kinds


static func rule_id(element) -> String:
	return element.weapon_id if element is WeaponData else element.my_id


static func _loot_candidates() -> Array:
	var candidates := _owned_elements()
	candidates.append_array(ItemService.items)
	candidates.append_array(ItemService.weapons)
	candidates.append_array(_pooled([ItemService.TierData.ITEMS, ItemService.TierData.WEAPONS]))
	return candidates


static func _all_upgrades() -> Array:
	var upgrades: Array = ItemService.upgrades.duplicate()
	upgrades.append(ItemService.weapon_slot_upgrade_data)
	upgrades.append_array(_pooled([ItemService.TierData.UPGRADES]))
	return upgrades


## Every element in every list of the owned item sets, including lists only some sets have.
static func _owned_elements() -> Array:
	var elements := []
	for item_set in _owned_item_sets():
		for property in item_set.get_property_list():
			var value = item_set.get(property.name)
			if value is Array:
				elements.append_array(value)
	return elements


static func _owned_item_sets() -> Array:
	var item_sets := []
	if ItemService.base_game_item_set != null:
		item_sets.append(ItemService.base_game_item_set)
	for update_data in ItemService.update_data_list:
		if update_data != null and update_data.item_set != null and ProgressData.is_update_data_available(update_data):
			item_sets.append(update_data.item_set)
	return item_sets


static func _is_update_owned(update_id: String) -> bool:
	if update_id.empty():
		return true
	for update_data in ItemService.update_data_list:
		if update_data != null and update_data.id == update_id:
			return ProgressData.is_update_data_available(update_data)
	return false


# The live pools of a running game, which also hold what other mods added there. The autoload goes through
# a variable: mods compile before it exists, and Godot folds `in` on a constant at parse time.
static func _pooled(pool_types: Array) -> Array:
	var pooled := []
	var item_service = ItemService
	if not "_tiers_data" in item_service:
		return pooled
	for tier_data in item_service._tiers_data:
		for pool_type in pool_types:
			if tier_data is Array and pool_type < tier_data.size() and tier_data[pool_type] is Array:
				pooled.append_array(tier_data[pool_type])
	return pooled


static func _is_crate_item(element) -> bool:
	if not element is ItemData or element is CharacterData or element is UpgradeData or element is ConsumableData:
		return false
	return _is_lootable(element)


static func _is_lootable(element) -> bool:
	if not element.can_be_looted:
		return false
	return not "max_nb" in element or element.max_nb != 0


static func _gives_crate_weapons(element) -> bool:
	if not element is ItemParentData:
		return false
	for effect in element.effects:
		if effect != null and effect.key == CRATE_WEAPON_EFFECT and effect.value > 0:
			return true
	return false


static func _sorted(elements: Array) -> Array:
	elements.sort_custom(ElementOrder.new(), "before")
	return elements


class ElementOrder:
	func before(a, b) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return TranslationServer.translate(a.name) < TranslationServer.translate(b.name)
