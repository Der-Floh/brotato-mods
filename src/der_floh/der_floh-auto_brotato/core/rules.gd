extends Reference

## The decisions, free of game state so tests can check them directly.

enum CrateAction {LEAVE, TAKE, RECYCLE}

const MODE := "mode"
const MIN_CURSE := "min_curse"
const MODE_TAKE := "take"
const MODE_RECYCLE := "recycle"
const MODE_CURSED := "cursed"
const MODE_CURSED_MIN := "cursed_min"
const DEFAULT_WEIGHT := 100
const NO_PICK := -1


## Whether a crate item with this rule should be taken. Curse rules only count while curses can happen.
static func is_wanted(rule: Dictionary, is_cursed: bool, curse_factor: float, curses_active: bool) -> bool:
	var mode: String = rule.get(MODE, MODE_TAKE)
	if mode == MODE_RECYCLE:
		return false
	if not curses_active or mode == MODE_TAKE:
		return true
	if not is_cursed:
		return false
	return mode == MODE_CURSED or curse_percent(curse_factor) >= int(rule.get(MIN_CURSE, 0))


static func curse_percent(curse_factor: float) -> int:
	return int(round(curse_factor * 100.0))


static func crate_action(wanted: bool, can_take: bool, auto_take: bool, auto_recycle: bool) -> int:
	if wanted:
		return CrateAction.TAKE if auto_take and can_take else CrateAction.LEAVE
	return CrateAction.RECYCLE if auto_recycle else CrateAction.LEAVE


static func weight_of(weights: Dictionary, upgrade_id: String) -> int:
	return int(clamp(round(float(weights.get(upgrade_id, DEFAULT_WEIGHT))), 0, DEFAULT_WEIGHT))


static func weight_sum(weights: Array) -> int:
	var total := 0
	for weight in weights:
		total += int(weight)
	return total


## The index whose share of the summed weights contains roll (0 <= roll < sum), or NO_PICK when all are 0.
static func pick_index_for_roll(weights: Array, roll: int) -> int:
	var running := 0
	for i in weights.size():
		running += int(weights[i])
		if roll < running:
			return i
	return NO_PICK


static func pick_index(weights: Array) -> int:
	var total := weight_sum(weights)
	if total <= 0:
		return NO_PICK
	return pick_index_for_roll(weights, randi() % total)
