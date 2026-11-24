extends Node

## Added as the shop's last child, so it sees Esc before the shop does: Godot 3 hands input to the last nodes
## first. Swallowing the press keeps the pause menu closed, because the shop pauses only on a release
## that follows a press it saw.

const CANCEL_ACTIONS := ["ui_pause", "ui_cancel"]
const MAX_PLAYERS := 4

var cancelled := false
# While a shop popup is open, Esc belongs to the popup.
var passthrough := false


func _ready() -> void:
	pause_mode = PAUSE_MODE_STOP


func _input(event: InputEvent) -> void:
	if cancelled or passthrough or not _is_cancel(event):
		return
	cancelled = true
	get_tree().set_input_as_handled()


static func _is_cancel(event: InputEvent) -> bool:
	for player_index in int(clamp(RunData.get_player_count(), 1, MAX_PLAYERS)):
		for action in CANCEL_ACTIONS:
			if Utils.is_player_action_pressed(event, player_index, action):
				return true
	return false
