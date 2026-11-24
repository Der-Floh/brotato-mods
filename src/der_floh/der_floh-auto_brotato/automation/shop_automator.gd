extends Reference

## Starts the next wave from the shop by pressing every player's Go button, after an optional countdown that
## Esc cancels for this shop.

const GameAccess := preload("res://mods-unpacked/der_floh-auto_brotato/core/game_access.gd")
const Settings := preload("res://mods-unpacked/der_floh-auto_brotato/core/settings.gd")
const CountdownInput := preload("res://mods-unpacked/der_floh-auto_brotato/automation/countdown_input.gd")
const COUNTDOWN_FONT := "res://resources/fonts/actual/base/font_40_outline_thick.tres"

var _settings: Node
var _shop: Node
var _resumed := false
var _cancelled := false
var _counting := false
var _remaining := 0.0
var _labels := []
var _input: Node


func _init(settings: Node) -> void:
	_settings = settings


func on_shop_entered(shop: Node, resumed: bool) -> void:
	_stop()
	_shop = shop
	_resumed = resumed
	_cancelled = false
	_start_if_wanted()


func on_shop_left() -> void:
	_stop()
	_shop = null


func on_settings_changed() -> void:
	if not is_instance_valid(_shop) or _cancelled:
		return
	if not _counting:
		_start_if_wanted()
	elif not _settings.get_value(Settings.AUTO_NEXT_WAVE):
		_stop()


func tick(delta: float, paused: bool) -> void:
	if not _counting or not is_instance_valid(_shop) or paused:
		return
	if is_instance_valid(_input) and _input.cancelled:
		_cancelled = true
		_stop()
		return
	var blocked := GameAccess.is_shop_blocked(_shop)
	if is_instance_valid(_input):
		_input.passthrough = blocked
	if blocked:
		_show_text(tr("AUTO_BROTATO_COUNTDOWN_WAIT"))
		return
	if _remaining > 0.0:
		_remaining = max(0.0, _remaining - delta)
		_show_text(tr("AUTO_BROTATO_COUNTDOWN") % int(ceil(_remaining)))
		return
	_press_go_buttons()
	_stop()


func is_counting() -> bool:
	return _counting


func remaining_seconds() -> float:
	return _remaining


func _start_if_wanted() -> void:
	if not _should_start():
		return
	_counting = true
	_remaining = float(_settings.get_value(Settings.NEXT_WAVE_DELAY))
	if _remaining > 0.0:
		_show_countdown()


func _should_start() -> bool:
	if _resumed or not _settings.get_value(Settings.AUTO_NEXT_WAVE):
		return false
	# Pressing Go in the shop that offers endless mode would silently decide against it.
	if RunData.should_show_endless_button():
		return false
	var limit := int(_settings.get_value(Settings.NEXT_WAVE_LIMIT))
	return limit <= 0 or RunData.get_next_wave() <= limit


func _press_go_buttons() -> void:
	for player_index in GameAccess.player_count():
		if GameAccess.is_player_ready(_shop, player_index):
			continue
		var button := GameAccess.go_button(_shop, player_index)
		if button == null:
			continue
		if RunData.is_coop_run:
			FocusEmulatorSignal.emit(button, "pressed", player_index)
		else:
			button.emit_signal("pressed")


func _show_countdown() -> void:
	for player_index in GameAccess.player_count():
		var button := GameAccess.go_button(_shop, player_index)
		if button == null or not button.get_parent() is BoxContainer:
			continue
		var label := _new_label()
		var box: Node = button.get_parent()
		box.add_child(label)
		box.move_child(label, button.get_index())
		_labels.append(label)
	_input = CountdownInput.new()
	_shop.add_child(_input)
	_show_text(tr("AUTO_BROTATO_COUNTDOWN") % int(ceil(_remaining)))


func _show_text(text: String) -> void:
	for label in _labels:
		if is_instance_valid(label):
			label.text = "%s\n%s" % [text, tr("AUTO_BROTATO_COUNTDOWN_HINT")]


func _stop() -> void:
	_counting = false
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	if is_instance_valid(_input):
		_input.queue_free()
	_input = null


static func _new_label() -> Label:
	var label := Label.new()
	label.align = Label.ALIGN_CENTER
	if ResourceLoader.exists(COUNTDOWN_FONT):
		label.add_font_override("font", load(COUNTDOWN_FONT))
	return label
