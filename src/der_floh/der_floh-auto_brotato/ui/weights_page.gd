extends Control

## One weight per level-up kind: an offered level-up is picked with a chance in proportion to its weight.

signal back_button_pressed

const Widgets := preload("res://mods-unpacked/der_floh-auto_brotato/ui/widgets.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const Rules := preload("res://mods-unpacked/der_floh-auto_brotato/core/rules.gd")
const Catalog := preload("res://mods-unpacked/der_floh-auto_brotato/core/catalog.gd")
const SOURCE := "page"
const WEIGHT_STEP := 5.0
const ICON_SIZE := Vector2(48, 48)
const CONTENT_WIDTH := 1100
const SEPARATION := 12

var _settings: Node
var _rows := {}
var _refreshing := false


func setup(settings: Node) -> void:
	_settings = settings
	name = "AutoBrotatoWeightsPage"
	var column := VBoxContainer.new()
	column.add_constant_override("separation", SEPARATION)
	Widgets.setup_page(self).add_child(column)
	column.add_child(Widgets.title(tr("AUTO_BROTATO_LEVEL_UPS")))
	column.add_child(Widgets.hint(tr("AUTO_BROTATO_WEIGHTS_HINT")))
	column.add_child(_rows_scroll())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_CENTER
	buttons.add_constant_override("separation", SEPARATION)
	var reset := Widgets.menu_button(tr("AUTO_BROTATO_RESET"))
	var _reset_connected = reset.connect("pressed", self, "_on_reset_pressed")
	buttons.add_child(reset)
	var back := Widgets.menu_button(tr("MENU_BACK"))
	var _back_connected = back.connect("pressed", self, "emit_signal", ["back_button_pressed"])
	buttons.add_child(back)
	column.add_child(buttons)


## Called by the game's Menus.switch when the page opens.
func init() -> void:
	_refresh()
	if not _rows.empty():
		Widgets.focus(_rows.values()[0].slider)


func _input(event: InputEvent) -> void:
	if visible and Widgets.is_cancel_released(event):
		get_tree().set_input_as_handled()
		emit_signal("back_button_pressed")


func _rows_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(center)
	var list := VBoxContainer.new()
	list.rect_min_size.x = CONTENT_WIDTH
	list.add_constant_override("separation", SEPARATION)
	center.add_child(list)
	for kind in Catalog.upgrade_kinds():
		list.add_child(_weight_row(kind[0], kind[1]))
	return scroll


func _weight_row(upgrade_id: String, upgrade) -> HBoxContainer:
	var weight_row := Widgets.slider_row(_kind_name(upgrade), 0.0, float(Rules.DEFAULT_WEIGHT), WEIGHT_STEP)
	var icon := TextureRect.new()
	icon.texture = upgrade.get_icon() if upgrade.has_method("get_icon") else upgrade.icon
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = ICON_SIZE
	weight_row.row.add_child(icon)
	weight_row.row.move_child(icon, 0)
	var _connected = weight_row.slider.connect("value_changed", self, "_on_weight_changed", [upgrade_id])
	_rows[upgrade_id] = weight_row
	return weight_row.row


# Level-ups are named after body parts, so the stat they raise follows in brackets: "Chest (Armor)".
static func _kind_name(upgrade) -> String:
	var kind_name := TranslationServer.translate(upgrade.name)
	if upgrade.effects.empty() or not "key" in upgrade.effects[0]:
		return kind_name
	var stat_key: String = String(upgrade.effects[0].key).to_upper()
	var stat_name := TranslationServer.translate(stat_key)
	if stat_name == stat_key:
		return kind_name
	return "%s (%s)" % [kind_name, stat_name.trim_prefix("% ")]


func _refresh() -> void:
	_refreshing = true
	var weights: Dictionary = _settings.get_rules(Settings.LEVEL_UP_WEIGHTS)
	for upgrade_id in _rows:
		var weight_row: Dictionary = _rows[upgrade_id]
		weight_row.slider.value = Rules.weight_of(weights, upgrade_id)
		weight_row.value.text = str(int(weight_row.slider.value))
	_refreshing = false


func _on_weight_changed(value: float, upgrade_id: String) -> void:
	_rows[upgrade_id].value.text = str(int(value))
	if _refreshing:
		return
	var weights: Dictionary = _settings.get_rules(Settings.LEVEL_UP_WEIGHTS)
	weights[upgrade_id] = value
	_settings.set_rules(Settings.LEVEL_UP_WEIGHTS, weights, SOURCE)


func _on_reset_pressed() -> void:
	_settings.set_rules(Settings.LEVEL_UP_WEIGHTS, {}, SOURCE)
	_refresh()
