extends Reference

## Answers crate items and level-ups at the end of a wave by pressing the game's own buttons.

const GameAccess := preload("res://mods-unpacked/der_floh-auto_brotato/core/game_access.gd")
const Rules := preload("res://mods-unpacked/der_floh-auto_brotato/core/rules.gd")
const Catalog := preload("res://mods-unpacked/der_floh-auto_brotato/core/catalog.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const MAX_PLAYERS := 4
# A new offer is left on screen this long before it is answered.
const SETTLE_MS := 150
# The game drops presses during its button delay, so an unanswered press is repeated once, then the offer is
# left to the player.
const RETRY_MS := 1000
const MAX_PRESSES := 2

var _settings: Node
var _keys := [null, null, null, null]
var _seen_at := [0, 0, 0, 0]
var _presses := [0, 0, 0, 0]
var _pressed_at := [0, 0, 0, 0]


func _init(settings: Node) -> void:
	_settings = settings


## Presses at most one button per call, which keeps the game's per-player button delay intact.
func tick(scene: Node) -> void:
	var ui := GameAccess.upgrades_ui(scene)
	if ui == null or not ui.visible:
		return
	var now := OS.get_ticks_msec()
	for player_index in min(GameAccess.player_count(), MAX_PLAYERS):
		if _answer(ui, player_index, now):
			return


func _answer(ui: Node, player_index: int, now: int) -> bool:
	if not GameAccess.is_choosing(ui, player_index):
		return false
	var container := GameAccess.container(ui, player_index)
	if container == null or GameAccess.is_locked(container):
		return false
	var key := GameAccess.offer_key(ui, container, player_index) + [_settings.revision]
	if key != _keys[player_index]:
		_keys[player_index] = key
		_seen_at[player_index] = now
		_presses[player_index] = 0
		return false
	if not _is_due(player_index, now):
		return false
	var button := _choice(container, player_index)
	if button == null:
		return false
	_press(button, player_index)
	_presses[player_index] += 1
	_pressed_at[player_index] = now
	return true


func _is_due(player_index: int, now: int) -> bool:
	if now - _seen_at[player_index] < SETTLE_MS or _presses[player_index] >= MAX_PRESSES:
		return false
	return _presses[player_index] == 0 or now - _pressed_at[player_index] >= RETRY_MS


func _choice(container: Node, player_index: int) -> BaseButton:
	if container.is_showing_item():
		return _crate_choice(container, player_index)
	return _level_up_choice(container)


func _crate_choice(container: Node, player_index: int) -> BaseButton:
	var item = GameAccess.shown_item(container)
	if item == null:
		return null
	var rules_key: String = Settings.WEAPON_RULES if item is WeaponData else Settings.ITEM_RULES
	var rule: Dictionary = _settings.rule_for(rules_key, Catalog.rule_id(item))
	var wanted := Rules.is_wanted(rule, item.is_cursed, item.curse_factor, GameAccess.curses_active())
	var can_take := GameAccess.can_take(container, item, player_index)
	var action := Rules.crate_action(wanted, can_take, _settings.get_value(Settings.AUTO_TAKE), _settings.get_value(Settings.AUTO_RECYCLE))
	if action == Rules.CrateAction.TAKE:
		return GameAccess.take_button(container)
	if action == Rules.CrateAction.RECYCLE:
		return GameAccess.recycle_button(container)
	return null


func _level_up_choice(container: Node) -> BaseButton:
	if not _settings.get_value(Settings.AUTO_LEVEL_UP):
		return null
	var offered := GameAccess.offered_upgrades(container)
	var weights_by_id: Dictionary = _settings.get_rules(Settings.LEVEL_UP_WEIGHTS)
	var weights := []
	for choice in offered:
		weights.append(Rules.weight_of(weights_by_id, choice[0].upgrade_id))
	var index := Rules.pick_index(weights)
	return offered[index][1] if index != Rules.NO_PICK else null


# Co-op presses go through the focus emulator like a player's own, for mods that ask who pressed.
static func _press(button: BaseButton, player_index: int) -> void:
	if RunData.is_coop_run:
		FocusEmulatorSignal.emit(button, "pressed", player_index)
	else:
		button.emit_signal("pressed")
