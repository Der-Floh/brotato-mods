extends Control

## The Auto Brotato page: the four switches, the next-wave sliders and the way to the two list pages.

signal back_button_pressed
signal items_button_pressed
signal weights_button_pressed

const Widgets := preload("res://mods-unpacked/der_floh-auto_brotato/ui/widgets.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const SOURCE := "page"
const SWITCHES := [Settings.AUTO_RECYCLE, Settings.AUTO_TAKE, Settings.AUTO_LEVEL_UP, Settings.AUTO_NEXT_WAVE]
const CONTENT_WIDTH := 1100
const SEPARATION := 16

var _settings: Node
var _switches := {}
var _delay: Dictionary
var _limit: Dictionary
var _refreshing := false


func setup(settings: Node) -> void:
	_settings = settings
	name = "AutoBrotatoPage"
	var column := _centered_column(Widgets.setup_page(self))
	column.add_child(Widgets.title(tr("AUTO_BROTATO")))
	for key in SWITCHES:
		var check := Widgets.check_button(tr(key.to_upper()))
		var _connected = check.connect("toggled", self, "_on_switch_toggled", [key])
		_switches[key] = check
		column.add_child(check)
	_delay = _add_slider(column, Settings.NEXT_WAVE_DELAY, 1.0)
	_limit = _add_slider(column, Settings.NEXT_WAVE_LIMIT, 1.0)
	_add_page_button(column, "AUTO_BROTATO_ITEMS", "items_button_pressed")
	_add_page_button(column, "AUTO_BROTATO_LEVEL_UPS", "weights_button_pressed")
	_add_page_button(column, "MENU_BACK", "back_button_pressed")
	var _connected = _settings.connect("changed", self, "_on_settings_changed")


## Called by the game's Menus.switch when the page opens.
func init() -> void:
	_refresh()
	Widgets.focus(_switches[SWITCHES[0]])


func _input(event: InputEvent) -> void:
	if visible and Widgets.is_cancel_released(event):
		get_tree().set_input_as_handled()
		emit_signal("back_button_pressed")


func _refresh() -> void:
	_refreshing = true
	for key in SWITCHES:
		_switches[key].pressed = bool(_settings.get_value(key))
	_delay.slider.value = float(_settings.get_value(Settings.NEXT_WAVE_DELAY))
	_limit.slider.value = float(_settings.get_value(Settings.NEXT_WAVE_LIMIT))
	_show_numbers()
	_refreshing = false


func _show_numbers() -> void:
	_delay.value.text = tr("AUTO_BROTATO_SECONDS") % int(_delay.slider.value)
	var limit := int(_limit.slider.value)
	_limit.value.text = str(limit) if limit > 0 else tr("AUTO_BROTATO_NO_LIMIT")


func _add_slider(column: Control, key: String, step: float) -> Dictionary:
	var number_range: Array = Settings.NUMBER_RANGES[key]
	var slider_row := Widgets.slider_row(tr(key.to_upper()), number_range[0], number_range[1], step)
	var _connected = slider_row.slider.connect("value_changed", self, "_on_slider_changed", [key])
	column.add_child(slider_row.row)
	return slider_row


func _add_page_button(column: Control, text_key: String, signal_name: String) -> void:
	var button := Widgets.menu_button(tr(text_key))
	var _connected = button.connect("pressed", self, "emit_signal", [signal_name])
	column.add_child(button)


static func _centered_column(margin: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	margin.add_child(center)
	var column := VBoxContainer.new()
	column.rect_min_size.x = CONTENT_WIDTH
	column.add_constant_override("separation", SEPARATION)
	center.add_child(column)
	return column


func _on_switch_toggled(pressed: bool, key: String) -> void:
	if not _refreshing:
		_settings.set_value(key, pressed, SOURCE)


func _on_slider_changed(value: float, key: String) -> void:
	_show_numbers()
	if not _refreshing:
		_settings.set_value(key, value, SOURCE)


func _on_settings_changed(_key: String, source: String) -> void:
	if source != SOURCE and visible:
		_refresh()
