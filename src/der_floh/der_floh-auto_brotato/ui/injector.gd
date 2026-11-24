extends Reference

## Adds an "Auto Brotato" button and the mod's pages to the pause menu and the title screen menus, switched
## through the game's own Menus.switch like every other page.

const SettingsPage := preload("res://mods-unpacked/der_floh-auto_brotato/ui/settings_page.gd")
const ItemsPage := preload("res://mods-unpacked/der_floh-auto_brotato/ui/items_page.gd")
const WeightsPage := preload("res://mods-unpacked/der_floh-auto_brotato/ui/weights_page.gd")
const Widgets := preload("res://mods-unpacked/der_floh-auto_brotato/ui/widgets.gd")
const TITLE_SCREEN := "res://ui/menus/title_screen/title_screen.tscn"
const TITLE_MENUS := "Menus"
const PAUSE_MENUS := ["UI/PauseMenu/Menus", "PauseMenu/Menus"]
const MAIN_MENU := "MainMenu"
const TITLE_ANCHOR := "MarginContainer/VBoxContainer/HBoxContainer/ButtonsRight/ModsButton"
const PAUSE_ANCHOR := "MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/Buttons/OptionsButton"
const BUTTON_NAME := "AutoBrotatoButton"
const BUTTON_TEXT := "AUTO_BROTATO"

var _settings: Node


func _init(settings: Node) -> void:
	_settings = settings


func on_scene_changed(scene: Node) -> void:
	if scene.filename == TITLE_SCREEN:
		_inject(scene.get_node_or_null(TITLE_MENUS), TITLE_ANCHOR)
		return
	for path in PAUSE_MENUS:
		var menus := scene.get_node_or_null(path)
		if menus != null:
			_inject(menus, PAUSE_ANCHOR)
			return


func _inject(menus: Node, anchor_path: String) -> void:
	if menus == null or not menus.has_method("switch"):
		return
	var main_menu := menus.get_node_or_null(MAIN_MENU)
	var anchor = main_menu.get_node_or_null(anchor_path) if main_menu != null else null
	if not anchor is Button or anchor.get_parent().has_node(BUTTON_NAME):
		return
	var settings_page := _add_page(menus, SettingsPage.new())
	var items_page := _add_page(menus, ItemsPage.new())
	var weights_page := _add_page(menus, WeightsPage.new())
	var button := _add_button(anchor)
	_link(button, "pressed", menus, main_menu, settings_page)
	_link(settings_page, "back_button_pressed", menus, settings_page, main_menu, button)
	_link(settings_page, "items_button_pressed", menus, settings_page, items_page)
	_link(settings_page, "weights_button_pressed", menus, settings_page, weights_page)
	_link(items_page, "back_button_pressed", menus, items_page, settings_page)
	_link(weights_page, "back_button_pressed", menus, weights_page, settings_page)


func _add_page(menus: Node, page: Control) -> Control:
	page.setup(_settings)
	menus.add_child(page)
	return page


# A copy of a menu button of the same column gets its look, sound and focus handling; copying only the script
# leaves out the original's connections, which would open the original's page too.
static func _add_button(anchor: Button) -> Button:
	var button: Button = anchor.duplicate(Node.DUPLICATE_SCRIPTS)
	button.name = BUTTON_NAME
	button.text = BUTTON_TEXT
	button.disabled = false
	button.focus_neighbour_top = NodePath()
	button.focus_neighbour_bottom = NodePath()
	if "unique_name_in_owner" in button:
		button.unique_name_in_owner = false
	anchor.get_parent().add_child_below_node(anchor, button)
	return button


func _link(source: Object, signal_name: String, menus: Node, from: Control, to: Control, focus_after: Control = null) -> void:
	var _connected = source.connect(signal_name, self, "_switch", [menus, from, to, focus_after])


func _switch(menus: Node, from: Control, to: Control, focus_after: Control) -> void:
	if not is_instance_valid(menus) or not from.visible:
		return
	menus.switch(from, to)
	if focus_after != null:
		Widgets.focus(focus_after)
