extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

# The decisions on their own: weighted level-up picks and whether a crate item is wanted.

const RULES_PATH := "res://mods-unpacked/der_floh-auto_brotato/core/rules.gd"
const DRAWS := 10000

var rules


func before_each():
	rules = load(RULES_PATH)


func test_rolls_map_to_the_weight_shares():
	var weights := [40, 0, 60]
	expect_eq(rules.pick_index_for_roll(weights, 0), 0, "roll 0")
	expect_eq(rules.pick_index_for_roll(weights, 39), 0, "roll 39")
	expect_eq(rules.pick_index_for_roll(weights, 40), 2, "roll 40 skips the weight 0")
	expect_eq(rules.pick_index_for_roll(weights, 99), 2, "roll 99")


func test_zero_weights_pick_nothing_and_one_option_is_always_picked():
	expect_eq(rules.pick_index([0, 0, 0]), rules.NO_PICK, "pick among weights 0")
	expect_eq(rules.pick_index([]), rules.NO_PICK, "pick without options")
	expect_eq(rules.pick_index([1]), 0, "pick with one option")


func test_picks_follow_the_weights():
	var counts := [0, 0]
	for i in DRAWS:
		counts[rules.pick_index([80, 20])] += 1
	expect_between(counts[0] / float(DRAWS), 0.77, 0.83, "share of weight 80 against 20")


func test_unknown_kinds_weigh_100_and_weights_stay_in_range():
	expect_eq(rules.weight_of({}, "upgrade_from_another_mod"), 100, "weight of an unknown kind")
	expect_eq(rules.weight_of({"upgrade_armor": 250.0}, "upgrade_armor"), 100, "weight above 100")
	expect_eq(rules.weight_of({"upgrade_armor": -5.0}, "upgrade_armor"), 0, "weight below 0")


func test_crate_item_rules():
	# rule, cursed, curse factor, curses possible, wanted
	var cases := [
		[{}, false, 0.0, true, true],
		[{"mode": "recycle"}, false, 0.0, true, false],
		[{"mode": "cursed"}, false, 0.0, true, false],
		[{"mode": "cursed"}, true, 0.2, true, true],
		[{"mode": "cursed_min", "min_curse": 50.0}, true, 0.49, true, false],
		[{"mode": "cursed_min", "min_curse": 50.0}, true, 0.5, true, true],
		[{"mode": "cursed"}, false, 0.0, false, true],
		[{"mode": "recycle"}, false, 0.0, false, false],
	]
	for case in cases:
		expect_eq(rules.is_wanted(case[0], case[1], case[2], case[3]), case[4], "wanted with %s, cursed %s, factor %s, curses %s" % case.slice(0, 3))


func test_crate_actions():
	var take: int = rules.CrateAction.TAKE
	var recycle: int = rules.CrateAction.RECYCLE
	var leave: int = rules.CrateAction.LEAVE
	expect_eq(rules.crate_action(true, true, true, false), take, "wanted and takeable")
	expect_eq(rules.crate_action(true, false, true, true), leave, "wanted but not takeable")
	expect_eq(rules.crate_action(true, true, false, true), leave, "wanted with taking off")
	expect_eq(rules.crate_action(false, true, true, true), recycle, "unwanted")
	expect_eq(rules.crate_action(false, true, true, false), leave, "unwanted with recycling off")
