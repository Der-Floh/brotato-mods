extends Reference

## Every read of the game's private members goes through here, each guarded, so a game update that renames
## one quietly switches the matching automation off instead of closing the game.

const WAVE_SCENE := "res://main.tscn"
const SHOP_SCENES := ["res://ui/menus/shop/shop.tscn", "res://ui/menus/shop/coop_shop.tscn"]
const ABYSSAL_TERRORS := "abyssal_terrors"
const NO_CHOICE := -1


static func is_wave_scene(scene: Node) -> bool:
	return scene != null and scene.filename == WAVE_SCENE


static func is_shop_scene(scene: Node) -> bool:
	return scene != null and scene.filename in SHOP_SCENES


static func curses_active() -> bool:
	return ProgressData.has_item_set(ABYSSAL_TERRORS)


static func player_count() -> int:
	return RunData.get_player_count()


# --- End of wave ---

static func upgrades_ui(scene: Node) -> Node:
	if not is_wave_scene(scene):
		return null
	var member := "_coop_upgrades_ui" if RunData.is_coop_run else "_upgrades_ui"
	var ui = scene.get(member) if member in scene else null
	return ui if is_instance_valid(ui) and "_player_is_choosing" in ui and ui.has_method("_get_player_container") else null


static func is_choosing(ui: Node, player_index: int) -> bool:
	return ui.visible and player_index < ui._player_is_choosing.size() and ui._player_is_choosing[player_index]


static func container(ui: Node, player_index: int) -> Node:
	var found = ui._get_player_container(player_index)
	return found if is_instance_valid(found) and "_button_pressed" in found and found.has_method("is_showing_item") else null


static func is_locked(container: Node) -> bool:
	return container._button_pressed


## Changes for every new level-up, crate, extra crate item and reroll; the item itself can't tell, because an
## uncursed roll hands out the shared item resource.
static func offer_key(ui: Node, container: Node, player_index: int) -> Array:
	var extras = ui._extra_items_to_process[player_index] if "_extra_items_to_process" in ui else []
	var rerolls = container._reroll_count if "_reroll_count" in container else 0
	return [ui._showing_option[player_index], extras.size(), container.is_showing_item(), rerolls]


static func shown_item(container: Node):
	return container._item_data if "_item_data" in container else null


static func can_take(container: Node, item, player_index: int) -> bool:
	if item is WeaponData and not RunData.can_take_weapon(item, player_index):
		return false
	if item.is_meca and container.has_method("_needs_meca_effect_choice") and container._needs_meca_effect_choice():
		return "_meca_effect_choice_selected" in container and container._meca_effect_choice_selected != NO_CHOICE
	return true


static func take_button(container: Node) -> BaseButton:
	return _button(container, "_take_button")


static func recycle_button(container: Node) -> BaseButton:
	return _button(container, "_discard_button")


## The visible level-up choices as [upgrade_data, button]; hidden ones keep the data of an older offer.
static func offered_upgrades(container: Node) -> Array:
	var offered := []
	if not container.has_method("_get_upgrade_uis") or not "_old_upgrades" in container:
		return offered
	var current: Array = container._old_upgrades
	var upgrade_uis: Array = container._get_upgrade_uis()
	for i in min(upgrade_uis.size(), current.size()):
		var upgrade_ui = upgrade_uis[i]
		if is_instance_valid(upgrade_ui) and upgrade_ui.visible and upgrade_ui.upgrade_data == current[i] and current[i] != null:
			offered.append([current[i], upgrade_ui.button])
	return offered


# --- Shop ---

static func go_button(shop: Node, player_index: int) -> BaseButton:
	if not shop.has_method("_get_go_button"):
		return null
	var button = shop._get_go_button(player_index)
	return button if is_instance_valid(button) and button is BaseButton else null


static func is_player_ready(shop: Node, player_index: int) -> bool:
	return "_player_pressed_go_button" in shop and shop._player_pressed_go_button[player_index]


## True while a shop popup waits for the player; the game would leave the shop with it still open.
static func is_shop_blocked(shop: Node) -> bool:
	if "_block_background" in shop and is_instance_valid(shop._block_background) and shop._block_background.visible:
		return true
	if not RunData.is_coop_run or not shop.has_method("_get_coop_player_container"):
		return false
	for player_index in player_count():
		var player_container = shop._get_coop_player_container(player_index)
		if is_instance_valid(player_container) and "_popup_dim_screen" in player_container and player_container._popup_dim_screen.visible:
			return true
	return false


static func shop_content(shop: Node) -> Control:
	var content = shop.get_node_or_null("Content")
	return content if content is Control else null


static func _button(holder: Node, member: String) -> BaseButton:
	var button = holder.get(member) if member in holder else null
	return button if is_instance_valid(button) and button is BaseButton else null
