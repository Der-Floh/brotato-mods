extends Reference

## Controls built from the game's own theme, fonts and button scripts, so the pages look like Brotato's.

const THEME := "res://resources/themes/base_theme.tres"
const FONT_TITLE := "res://resources/fonts/actual/base/font_60_outline.tres"
const FONT_ROW := "res://resources/fonts/actual/base/font_40_outline.tres"
const FONT_SMALL := "res://resources/fonts/actual/base/font_26_outline.tres"
const HOVER_STYLE := "res://resources/themes/button_styles/button_hover.tres"
const MENU_BUTTON_SCRIPT := "res://ui/menus/global/my_menu_button.gd"
const SLIDER_SCRIPT := "res://ui/menus/global/my_h_slider.gd"
const PAGE_MARGIN := 60
const ROW_SEPARATION := 20
const SLIDER_WIDTH := 300
const VALUE_WIDTH := 140
const MAX_PLAYERS := 4


static func resource(path: String) -> Resource:
	return load(path) if ResourceLoader.exists(path) else null


## A full-screen page, hidden until the game's Menus.switch shows it.
static func setup_page(page: Control) -> MarginContainer:
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.visible = false
	page.theme = resource(THEME)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_" + side, PAGE_MARGIN)
	page.add_child(margin)
	return margin


static func label(text: String, font_path := FONT_ROW) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.add_font_override("font", resource(font_path))
	return new_label


static func title(text: String) -> Label:
	var new_label := label(text, FONT_TITLE)
	new_label.align = Label.ALIGN_CENTER
	return new_label


static func hint(text: String) -> Label:
	var new_label := label(text, FONT_SMALL)
	new_label.autowrap = true
	new_label.align = Label.ALIGN_CENTER
	return new_label


static func menu_button(text: String) -> Button:
	var button := Button.new()
	_style_button(button, text)
	return button


static func check_button(text: String) -> CheckButton:
	var button := CheckButton.new()
	_style_button(button, text)
	button.add_stylebox_override("hover_pressed", resource(HOVER_STYLE))
	return button


## A labelled slider with its value on the right: {row, slider, value, name}.
static func slider_row(text: String, min_value: float, max_value: float, step: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_constant_override("separation", ROW_SEPARATION)
	var name_label := label(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.rect_min_size.x = SLIDER_WIDTH
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var slider_script = resource(SLIDER_SCRIPT)
	if slider_script:
		slider.set_script(slider_script)
	var value_label := label("")
	value_label.rect_min_size.x = VALUE_WIDTH
	value_label.align = Label.ALIGN_RIGHT
	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value_label)
	return {"row": row, "slider": slider, "value": value_label, "name": name_label}


## Esc or B on any player's controller; the title screen has no run, so it checks the plain action there.
static func is_cancel_released(event: InputEvent) -> bool:
	for player_index in int(clamp(RunData.get_player_count(), 1, MAX_PLAYERS)):
		if Utils.is_player_cancel_released(event, player_index):
			return true
	return false


static func focus(control: Control) -> void:
	if control != null and control.is_visible_in_tree():
		control.grab_focus()


static func _style_button(button: Button, text: String) -> void:
	button.text = text
	button.add_font_override("font", resource(FONT_ROW))
	var button_script = resource(MENU_BUTTON_SCRIPT)
	if button_script:
		button.set_script(button_script)
