extends Reference

## The mod's texts, in English only. Godot falls back to English for every other language.

const LOCALE := "en"
const TEXTS := {
	"AUTO_BROTATO": "Auto Brotato",
	"AUTO_RECYCLE_CRATE_ITEMS": "Recycle unwanted crate items",
	"AUTO_TAKE_CRATE_ITEMS": "Take wanted crate items",
	"AUTO_PICK_LEVEL_UPS": "Pick level-ups",
	"AUTO_START_NEXT_WAVE": "Start the next wave",
	"NEXT_WAVE_DELAY": "Next wave delay",
	"NEXT_WAVE_LIMIT": "Last wave to start (0 = no limit)",
	"AUTO_BROTATO_INFO": "Automates the end of a wave. Choose which crate items to take on the item page and how likely each level-up is on the level-up page, both in the pause menu under Auto Brotato.",
	"AUTO_BROTATO_SECONDS": "%d s",
	"AUTO_BROTATO_NO_LIMIT": "No limit",
	"AUTO_BROTATO_ITEMS": "Crate items",
	"AUTO_BROTATO_LEVEL_UPS": "Level-ups",
	"AUTO_BROTATO_TAB_ITEMS": "Items",
	"AUTO_BROTATO_TAB_WEAPONS": "Weapons",
	"AUTO_BROTATO_ITEMS_HINT": "Crossed-out items are recycled, all others are taken. Click an item to switch it.",
	"AUTO_BROTATO_ITEMS_CURSE_HINT": "Right-click an item to take it only when it is cursed.",
	"AUTO_BROTATO_TAKE_ALL": "Take all",
	"AUTO_BROTATO_RECYCLE_ALL": "Recycle all",
	"AUTO_BROTATO_WEIGHTS_HINT": "Each offered level-up is picked with a chance in proportion to its weight. 0 means never; if every offered level-up has 0, you pick yourself.",
	"AUTO_BROTATO_RESET": "Reset",
	"AUTO_BROTATO_CURSE_RULE": "Take when",
	"AUTO_BROTATO_CURSE_ALWAYS": "Always",
	"AUTO_BROTATO_CURSE_ONLY": "Only cursed",
	"AUTO_BROTATO_CURSE_MIN": "Cursed with at least",
	"AUTO_BROTATO_CURSE_BONUS": "Curse bonus",
	"AUTO_BROTATO_COUNTDOWN": "Next wave in %d s",
	"AUTO_BROTATO_COUNTDOWN_WAIT": "Next wave when this closes",
	"AUTO_BROTATO_COUNTDOWN_HINT": "Esc to cancel",
}


static func install() -> void:
	var translation := Translation.new()
	translation.locale = LOCALE
	for key in TEXTS:
		translation.add_message(key, TEXTS[key])
	TranslationServer.add_translation(translation)
