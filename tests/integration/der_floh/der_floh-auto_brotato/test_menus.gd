extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# The Auto Brotato button and pages in the pause menu and on the title screen.

const MOD_ID := "der_floh-auto_brotato"
const PAUSE_BUTTONS := "Menus/MainMenu/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/Buttons"
const TITLE_BUTTONS := "Menus/MainMenu/MarginContainer/VBoxContainer/HBoxContainer/ButtonsRight"
const BUTTON := "AutoBrotatoButton"
const SETTINGS_PAGE := "Menus/AutoBrotatoPage"
const ITEMS_PAGE := "Menus/AutoBrotatoItemsPage"
const WEIGHTS_PAGE := "Menus/AutoBrotatoWeightsPage"
const MAIN_MENU := "Menus/MainMenu"
const SETTLE_SEC := 0.3
const TEMPLATE_ITEM := "item_helmet"
const NEW_ITEM := "item_auto_brotato_menu_test"
const NEW_KIND := "upgrade_auto_brotato_menu_test"
const ABYSSAL_TERRORS := "abyssal_terrors"
const LAYOUT_FRAMES := 2

var _pause_menu: Node


func after_each():
	if is_instance_valid(_pause_menu) and tree.paused:
		_pause_menu.unpause()


func test_the_pause_menu_opens_the_page_and_esc_steps_back():
	if not yield(_paused_wave(), "completed"):
		return
	expect_eq(_pause_menu.get_node(PAUSE_BUTTONS).get_node(BUTTON).get_index(), _pause_menu.get_node(PAUSE_BUTTONS + "/OptionsButton").get_index() + 1, "button position after Options")
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	expect(_pause_menu.get_node(SETTINGS_PAGE).visible, "the page opened")
	yield(press_key(KEY_ESCAPE), "completed")
	expect(not _pause_menu.get_node(SETTINGS_PAGE).visible, "Esc closed the page")
	expect(_pause_menu.get_node(MAIN_MENU).visible and tree.paused, "Esc went back to the pause menu")


func test_list_pages_step_back_to_the_page():
	if not yield(_paused_wave(), "completed"):
		return
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	for signal_and_page in [["items_button_pressed", ITEMS_PAGE], ["weights_button_pressed", WEIGHTS_PAGE]]:
		_pause_menu.get_node(SETTINGS_PAGE).emit_signal(signal_and_page[0])
		yield(tree.create_timer(SETTLE_SEC, true), "timeout")
		expect(_pause_menu.get_node(signal_and_page[1]).visible, "%s opened" % signal_and_page[1])
		yield(press_key(KEY_ESCAPE), "completed")
		expect(_pause_menu.get_node(SETTINGS_PAGE).visible, "Esc on %s went back to the page" % signal_and_page[1])


func test_crossing_out_an_item_is_saved():
	if not yield(_paused_wave(), "completed"):
		return
	use_setting(MOD_ID, "item_rules", {})
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	_pause_menu.get_node(SETTINGS_PAGE).emit_signal("items_button_pressed")
	yield(tree.create_timer(SETTLE_SEC, true), "timeout")
	var element = _pause_menu.get_node(ITEMS_PAGE)._elements[0]
	element.emit_signal("element_pressed", element)
	expect_eq(mod(MOD_ID).get_item_rules(), {element.item.my_id: {"mode": "recycle"}}, "rules after crossing out")
	expect(element._baned.visible, "the item is crossed out")
	element.emit_signal("element_pressed", element)
	expect_eq(mod(MOD_ID).get_item_rules(), {}, "rules after taking it back")


func test_a_level_up_weight_is_saved():
	if not yield(_paused_wave(), "completed"):
		return
	use_setting(MOD_ID, "level_up_weights", {})
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	_pause_menu.get_node(SETTINGS_PAGE).emit_signal("weights_button_pressed")
	yield(tree.create_timer(SETTLE_SEC, true), "timeout")
	var rows: Dictionary = _pause_menu.get_node(WEIGHTS_PAGE)._rows
	rows["upgrade_armor"].slider.value = 40.0
	expect_eq(mod(MOD_ID).get_level_up_weights(), {"upgrade_armor": 40.0}, "weights after moving a slider")


func test_the_pages_list_content_added_after_they_were_built():
	if not yield(_paused_wave(), "completed"):
		return
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	var settings_page = _pause_menu.get_node(SETTINGS_PAGE)
	yield(_open_list_page(settings_page, "items_button_pressed"), "completed")
	yield(press_key(KEY_ESCAPE), "completed")
	_add_new_content()
	yield(_open_list_page(settings_page, "items_button_pressed"), "completed")
	var listed := []
	for element in _pause_menu.get_node(ITEMS_PAGE)._elements:
		listed.append(element.item.my_id)
	expect(listed.has(NEW_ITEM), "the item page lists an item added after it first opened")
	yield(press_key(KEY_ESCAPE), "completed")
	yield(_open_list_page(settings_page, "weights_button_pressed"), "completed")
	expect(_pause_menu.get_node(WEIGHTS_PAGE)._rows.has(NEW_KIND), "the level-up page lists a kind added after it was built")


func test_the_item_page_fits_the_screen_with_every_curse_rule():
	if not ProgressData.has_item_set(ABYSSAL_TERRORS):
		skip("needs Abyssal Terrors")
		return
	if not yield(_paused_wave(), "completed"):
		return
	use_setting(MOD_ID, "item_rules", {})
	yield(_open_settings_page(_pause_menu, PAUSE_BUTTONS), "completed")
	yield(_open_list_page(_pause_menu.get_node(SETTINGS_PAGE), "items_button_pressed"), "completed")
	var page = _pause_menu.get_node(ITEMS_PAGE)
	_expect_on_screen(page, "the opened page")
	var element = _cursable_element(page)
	if not expect(element != null, "the page lists an item that can be cursed"):
		return
	element.emit_signal("gui_input", _right_click())
	for mode_button in page._curse_buttons:
		mode_button.emit_signal("pressed")
		yield(frames(LAYOUT_FRAMES), "completed")
		_expect_on_screen(page, mode_button.text)
	expect(page._curse_slider.row.visible, "the curse bonus slider shows")


func test_the_title_screen_opens_the_page():
	var _changed = tree.change_scene(MenuData.title_screen_scene)
	if not expect(yield(access.wait_until(access, "title_screen", 15000), "completed"), "the title screen opened"):
		return
	yield(tree.create_timer(SETTLE_SEC), "timeout")
	var title_screen = access.title_screen()
	if not expect(title_screen.get_node_or_null(TITLE_BUTTONS + "/" + BUTTON) != null, "the title screen has the button"):
		return
	yield(_open_settings_page(title_screen, TITLE_BUTTONS), "completed")
	expect(title_screen.get_node(SETTINGS_PAGE).visible, "the page opened")
	yield(press_key(KEY_ESCAPE), "completed")
	expect(title_screen.get_node(MAIN_MENU).visible, "Esc went back to the title menu")


func _paused_wave():
	if not yield(in_wave(), "completed"):
		return false
	_pause_menu = wave().get_node_or_null("UI/PauseMenu")
	if not expect(_pause_menu != null, "the wave has a pause menu"):
		return false
	_pause_menu.pause(0)
	yield(tree.create_timer(SETTLE_SEC, true), "timeout")
	return expect(_pause_menu.get_node_or_null(PAUSE_BUTTONS + "/" + BUTTON) != null, "the pause menu has the button")


func _open_settings_page(menu_owner: Node, buttons_path: String):
	menu_owner.get_node(buttons_path + "/" + BUTTON).emit_signal("pressed")
	yield(tree.create_timer(SETTLE_SEC, true), "timeout")


func _open_list_page(settings_page: Node, button_signal: String):
	settings_page.emit_signal(button_signal)
	yield(tree.create_timer(SETTLE_SEC, true), "timeout")


## Adds a copy of a game item and of a level-up under new ids, as another mod would.
func _add_new_content() -> void:
	for template in ItemService.items:
		if template.my_id == TEMPLATE_ITEM:
			var item = template.duplicate()
			item.my_id = NEW_ITEM
			item.my_id_hash = Keys.generate_hash(NEW_ITEM)
			_add_for_this_test(ItemService.items, item)
			break
	var upgrade = ItemService.upgrades[0].duplicate()
	upgrade.upgrade_id = NEW_KIND
	upgrade.upgrade_id_hash = Keys.generate_hash(NEW_KIND)
	_add_for_this_test(ItemService.upgrades, upgrade)


func _add_for_this_test(list: Array, element) -> void:
	list.append(element)
	on_cleanup(self, "_remove_from", [list, element])


func _remove_from(list: Array, element) -> void:
	list.erase(element)


## Anything wider or taller than the screen grows the page's margin container past the screen's edge.
func _expect_on_screen(page: Node, state: String) -> void:
	var screen: Rect2 = page.get_viewport_rect()
	var margin = page.get_child(0)
	var content: Rect2 = margin.get_global_rect()
	expect(screen.encloses(content), "%s: the page %s fits the screen %s" % [state, content, screen])


static func _cursable_element(page: Node):
	for element in page._elements:
		if ItemService.can_item_be_cursed(element.item):
			return element
	return null


static func _right_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_RIGHT
	click.pressed = true
	return click
