extends Control

## Every item a crate can hold, and the weapons when a character's crates hold weapons. Clicking one crosses
## it out (recycled); with Abyssal Terrors, right-click or the select button sets whether it is taken only
## when cursed. The grid is read from the game's data whenever the page opens.

signal back_button_pressed

const Widgets := preload("res://mods-unpacked/der_floh-auto_brotato/ui/widgets.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const Rules := preload("res://mods-unpacked/der_floh-auto_brotato/core/rules.gd")
const Catalog := preload("res://mods-unpacked/der_floh-auto_brotato/core/catalog.gd")
const GameAccess := preload("res://mods-unpacked/der_floh-auto_brotato/core/game_access.gd")
const INVENTORY_ELEMENT := "res://items/global/inventory_element.tscn"
const ITEM_DESCRIPTION := "res://ui/menus/pages/menu_codex/codex_item_description.tscn"
const SOURCE := "page"
const TAB_ITEMS := 0
const TAB_WEAPONS := 1
const COLUMNS := 12
const SIDE_WIDTH := 520
const CROSSED_OUT_ALPHA := 0.6
const CURSE_STEP := 5.0
const CURSE_MAX := 110.0
const DEFAULT_MIN_CURSE := 50.0
const SEPARATION := 16
const CURSE_MODES := [Rules.MODE_TAKE, Rules.MODE_CURSED, Rules.MODE_CURSED_MIN]
const CURSE_MODE_TEXTS := ["AUTO_BROTATO_CURSE_ALWAYS", "AUTO_BROTATO_CURSE_ONLY", "AUTO_BROTATO_CURSE_MIN"]

var _settings: Node
var _tab := TAB_ITEMS
var _grid_key := []
var _elements := []
var _grid: GridContainer
var _tab_buttons := []
var _description: Control
var _curse_panel: VBoxContainer
var _curse_title: Label
var _curse_buttons := []
var _curse_slider: Dictionary
var _selected: Control
var _refreshing := false


func setup(settings: Node) -> void:
	_settings = settings
	name = "AutoBrotatoItemsPage"
	var column := VBoxContainer.new()
	column.add_constant_override("separation", SEPARATION)
	Widgets.setup_page(self).add_child(column)
	column.add_child(Widgets.title(tr("AUTO_BROTATO_ITEMS")))
	column.add_child(Widgets.hint(_hint_text()))
	column.add_child(_toolbar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_constant_override("separation", SEPARATION)
	column.add_child(body)
	body.add_child(_grid_scroll())
	body.add_child(_side_panel())
	var back := Widgets.menu_button(tr("MENU_BACK"))
	var _connected = back.connect("pressed", self, "emit_signal", ["back_button_pressed"])
	column.add_child(back)


## Called by the game's Menus.switch when the page opens.
func init() -> void:
	_close_curse_panel()
	_show_tabs(Catalog.crates_can_hold_weapons())
	_update_grid()
	if not _elements.empty():
		Widgets.focus(_elements[0])


func _input(event: InputEvent) -> void:
	if not visible or not Widgets.is_cancel_released(event):
		return
	get_tree().set_input_as_handled()
	if _curse_panel.visible:
		_close_curse_panel()
	else:
		emit_signal("back_button_pressed")


# --- Layout ---

func _hint_text() -> String:
	if GameAccess.curses_active():
		return "%s %s" % [tr("AUTO_BROTATO_ITEMS_HINT"), tr("AUTO_BROTATO_ITEMS_CURSE_HINT")]
	return tr("AUTO_BROTATO_ITEMS_HINT")


func _toolbar() -> HBoxContainer:
	var toolbar := HBoxContainer.new()
	toolbar.alignment = BoxContainer.ALIGN_CENTER
	toolbar.add_constant_override("separation", SEPARATION)
	var tabs := ButtonGroup.new()
	for tab in [TAB_ITEMS, TAB_WEAPONS]:
		var tab_button := Widgets.menu_button(tr("AUTO_BROTATO_TAB_WEAPONS" if tab == TAB_WEAPONS else "AUTO_BROTATO_TAB_ITEMS"))
		tab_button.toggle_mode = true
		tab_button.group = tabs
		tab_button.pressed = tab == _tab
		var _connected = tab_button.connect("pressed", self, "_on_tab_pressed", [tab])
		_tab_buttons.append(tab_button)
		toolbar.add_child(tab_button)
	for recycle in [false, true]:
		var all_button := Widgets.menu_button(tr("AUTO_BROTATO_RECYCLE_ALL" if recycle else "AUTO_BROTATO_TAKE_ALL"))
		var _connected = all_button.connect("pressed", self, "_set_all", [recycle])
		toolbar.add_child(all_button)
	return toolbar


func _grid_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	scroll.add_child(_grid)
	return scroll


# Scrolls, so a long item description never pushes the page past the screen.
func _side_panel() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.rect_min_size.x = SIDE_WIDTH
	scroll.scroll_horizontal_enabled = false
	var side := VBoxContainer.new()
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	side.add_constant_override("separation", SEPARATION)
	scroll.add_child(side)
	var description_scene = Widgets.resource(ITEM_DESCRIPTION)
	if description_scene:
		_description = description_scene.instance()
		_description.hide_description_if_locked_in_codex = false
		_description.visible = false
		side.add_child(_description)
	side.add_child(_curse_editor())
	return scroll


func _curse_editor() -> VBoxContainer:
	_curse_panel = VBoxContainer.new()
	_curse_panel.visible = false
	_curse_title = Widgets.label("")
	_curse_title.autowrap = true
	_curse_panel.add_child(_curse_title)
	_curse_panel.add_child(Widgets.label(tr("AUTO_BROTATO_CURSE_RULE"), Widgets.FONT_SMALL))
	var modes := ButtonGroup.new()
	for i in CURSE_MODES.size():
		var mode_button := Widgets.check_button(tr(CURSE_MODE_TEXTS[i]))
		mode_button.group = modes
		var _connected = mode_button.connect("pressed", self, "_on_curse_mode_pressed", [CURSE_MODES[i]])
		_curse_buttons.append(mode_button)
		_curse_panel.add_child(mode_button)
	_curse_slider = Widgets.stacked_slider_row(tr("AUTO_BROTATO_CURSE_BONUS"), 0.0, CURSE_MAX, CURSE_STEP)
	var _connected = _curse_slider.slider.connect("value_changed", self, "_on_curse_slider_changed")
	_curse_panel.add_child(_curse_slider.row)
	return _curse_panel


func _show_tabs(with_weapons: bool) -> void:
	for tab_button in _tab_buttons:
		tab_button.visible = with_weapons
	if not with_weapons and _tab == TAB_WEAPONS:
		_tab = TAB_ITEMS
		_tab_buttons[TAB_ITEMS].pressed = true


# --- Grid ---

func _update_grid() -> void:
	var catalog: Array = Catalog.crate_weapons() if _tab == TAB_WEAPONS else Catalog.crate_items()
	var key := _key_of(catalog)
	if key == _grid_key:
		_refresh_looks()
	else:
		_build_grid(catalog)
		_grid_key = key


func _key_of(catalog: Array) -> Array:
	var key := [_tab]
	for element_data in catalog:
		key.append(Catalog.rule_id(element_data))
	return key


func _build_grid(catalog: Array) -> void:
	for element in _elements:
		element.queue_free()
	_elements.clear()
	var element_scene = Widgets.resource(INVENTORY_ELEMENT)
	if element_scene == null:
		return
	for element_data in catalog:
		var element = element_scene.instance()
		_grid.add_child(element)
		element.set_element(element_data)
		var _pressed = element.connect("element_pressed", self, "_on_element_pressed")
		var _focused = element.connect("element_focused", self, "_on_element_shown")
		var _hovered = element.connect("element_hovered", self, "_on_element_shown")
		var _input_connected = element.connect("gui_input", self, "_on_element_input", [element])
		_elements.append(element)
		_apply_look(element)


func _refresh_looks() -> void:
	for element in _elements:
		_apply_look(element)


func _apply_look(element: Control) -> void:
	var rule := _rule(element)
	var mode: String = rule.get(Rules.MODE, Rules.MODE_TAKE)
	if "_baned" in element:
		element._baned.visible = mode == Rules.MODE_RECYCLE
		element._baned.modulate = Color(ProgressData.settings.color_negative)
		element._baned.modulate.a = CROSSED_OUT_ALPHA
	if "_curse" in element:
		element._curse.visible = mode == Rules.MODE_CURSED or mode == Rules.MODE_CURSED_MIN
	if "_number_label" in element:
		element._number_label.visible = mode == Rules.MODE_CURSED_MIN
		element._number_label.text = "≥%d%%" % int(rule.get(Rules.MIN_CURSE, 0))


func _rules_key() -> String:
	return Settings.WEAPON_RULES if _tab == TAB_WEAPONS else Settings.ITEM_RULES


func _rule(element: Control) -> Dictionary:
	return _settings.rule_for(_rules_key(), Catalog.rule_id(element.item))


func _set_rule(element: Control, rule: Dictionary) -> void:
	_settings.set_rule_for(_rules_key(), Catalog.rule_id(element.item), rule, SOURCE)
	_apply_look(element)


func _set_all(recycle: bool) -> void:
	var rules: Dictionary = _settings.get_rules(_rules_key())
	for element in _elements:
		var element_id := Catalog.rule_id(element.item)
		if recycle:
			rules[element_id] = {Rules.MODE: Rules.MODE_RECYCLE}
		else:
			var _erased = rules.erase(element_id)
	_settings.set_rules(_rules_key(), rules, SOURCE)
	_refresh_looks()
	_close_curse_panel()


# --- Curse rule editor ---

func _open_curse_panel(element: Control) -> void:
	_selected = element
	_curse_title.text = element.item.get_name_text() if element.item.has_method("get_name_text") else tr(element.item.name)
	_show_curse_rule()
	if _description != null:
		_description.visible = false
	_curse_panel.visible = true
	for mode_button in _curse_buttons:
		if mode_button.pressed:
			Widgets.focus(mode_button)


func _close_curse_panel() -> void:
	if _curse_panel != null:
		_curse_panel.visible = false
	if is_instance_valid(_selected):
		Widgets.focus(_selected)
	_selected = null


func _show_curse_rule() -> void:
	_refreshing = true
	var rule := _rule(_selected)
	var mode: String = rule.get(Rules.MODE, Rules.MODE_TAKE)
	var mode_index := CURSE_MODES.find(mode)
	for i in _curse_buttons.size():
		_curse_buttons[i].pressed = i == mode_index
	_curse_slider.slider.value = float(rule.get(Rules.MIN_CURSE, DEFAULT_MIN_CURSE))
	_curse_slider.value.text = "%d%%" % int(_curse_slider.slider.value)
	_curse_slider.row.visible = mode == Rules.MODE_CURSED_MIN
	_refreshing = false


func _curse_rule(mode: String) -> Dictionary:
	if mode == Rules.MODE_TAKE:
		return {}
	if mode == Rules.MODE_CURSED:
		return {Rules.MODE: mode}
	return {Rules.MODE: mode, Rules.MIN_CURSE: float(_curse_slider.slider.value)}


static func _can_have_curse_rule(item) -> bool:
	return GameAccess.curses_active() and ItemService.can_item_be_cursed(item)


# --- Events ---

func _on_tab_pressed(tab: int) -> void:
	if tab == _tab:
		return
	_tab = tab
	_close_curse_panel()
	_update_grid()


func _on_element_pressed(element: Control) -> void:
	var recycled: bool = _rule(element).get(Rules.MODE) == Rules.MODE_RECYCLE
	_set_rule(element, {} if recycled else {Rules.MODE: Rules.MODE_RECYCLE})
	if element == _selected:
		_show_curse_rule()


func _on_element_shown(element: Control) -> void:
	if _description != null and not _curse_panel.visible and RunData.get_player_count() > 0:
		_description.set_item(element.item, 0)
		_description.visible = true


func _on_element_input(event: InputEvent, element: Control) -> void:
	var right_click: bool = event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed
	if not right_click and not event.is_action_pressed("ui_select"):
		return
	if _can_have_curse_rule(element.item):
		_open_curse_panel(element)
		accept_event()


func _on_curse_mode_pressed(mode: String) -> void:
	if _refreshing or not is_instance_valid(_selected):
		return
	_set_rule(_selected, _curse_rule(mode))
	_show_curse_rule()


func _on_curse_slider_changed(value: float) -> void:
	_curse_slider.value.text = "%d%%" % int(value)
	if _refreshing or not is_instance_valid(_selected):
		return
	if _rule(_selected).get(Rules.MODE) == Rules.MODE_CURSED_MIN:
		_set_rule(_selected, _curse_rule(Rules.MODE_CURSED_MIN))
