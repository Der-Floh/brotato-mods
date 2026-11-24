extends Reference

const TEXTS := {
	"en": {
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
	},
	"de": {
		"AUTO_BROTATO": "Auto Brotato",
		"AUTO_RECYCLE_CRATE_ITEMS": "Unerwünschte Kistengegenstände recyceln",
		"AUTO_TAKE_CRATE_ITEMS": "Gewünschte Kistengegenstände nehmen",
		"AUTO_PICK_LEVEL_UPS": "Level-ups wählen",
		"AUTO_START_NEXT_WAVE": "Nächste Welle starten",
		"NEXT_WAVE_DELAY": "Verzögerung bis zur nächsten Welle",
		"NEXT_WAVE_LIMIT": "Letzte gestartete Welle (0 = keine Grenze)",
		"AUTO_BROTATO_INFO": "Automatisiert das Ende einer Welle. Welche Kistengegenstände genommen werden und wie wahrscheinlich jedes Level-up ist, legst du im Pausenmenü unter Auto Brotato fest.",
		"AUTO_BROTATO_SECONDS": "%d s",
		"AUTO_BROTATO_NO_LIMIT": "Keine Grenze",
		"AUTO_BROTATO_ITEMS": "Kistengegenstände",
		"AUTO_BROTATO_LEVEL_UPS": "Level-ups",
		"AUTO_BROTATO_TAB_ITEMS": "Gegenstände",
		"AUTO_BROTATO_TAB_WEAPONS": "Waffen",
		"AUTO_BROTATO_ITEMS_HINT": "Durchgestrichene Gegenstände werden recycelt, alle anderen genommen. Klicke einen Gegenstand an, um ihn umzuschalten.",
		"AUTO_BROTATO_ITEMS_CURSE_HINT": "Rechtsklicke einen Gegenstand, um ihn nur verflucht zu nehmen.",
		"AUTO_BROTATO_TAKE_ALL": "Alle nehmen",
		"AUTO_BROTATO_RECYCLE_ALL": "Alle recyceln",
		"AUTO_BROTATO_WEIGHTS_HINT": "Jedes angebotene Level-up wird mit einer Chance im Verhältnis zu seinem Gewicht gewählt. 0 heißt nie; haben alle angebotenen 0, wählst du selbst.",
		"AUTO_BROTATO_RESET": "Zurücksetzen",
		"AUTO_BROTATO_CURSE_RULE": "Nehmen, wenn",
		"AUTO_BROTATO_CURSE_ALWAYS": "Immer",
		"AUTO_BROTATO_CURSE_ONLY": "Nur verflucht",
		"AUTO_BROTATO_CURSE_MIN": "Verflucht mit mindestens",
		"AUTO_BROTATO_CURSE_BONUS": "Fluchbonus",
		"AUTO_BROTATO_COUNTDOWN": "Nächste Welle in %d s",
		"AUTO_BROTATO_COUNTDOWN_WAIT": "Nächste Welle, sobald dies geschlossen ist",
		"AUTO_BROTATO_COUNTDOWN_HINT": "Esc zum Abbrechen",
	},
}


static func install() -> void:
	for locale in TEXTS:
		var translation := Translation.new()
		translation.locale = locale
		var texts: Dictionary = TEXTS[locale]
		for key in texts:
			translation.add_message(key, texts[key])
		TranslationServer.add_translation(translation)
