# Integration tests

These tests start Brotato with a set of mods and check, inside the running game, that each mod does what its README says: alone, together with every other mod in `src/`, and in the combinations a mod declares. They are local only; no GitHub workflow runs them, because they need the game.

## Requirements

- Brotato from Steam, and Steam running. The game folder is found through your Steam libraries; pass `-GameDirectory` or set `BROTATO_GAME_DIR` if that fails.
- PowerShell 7 or Windows PowerShell 5.1.
- The game closed. The tests open it windowed at 1280x720, without sound, in English; leave the mouse alone while they run.

Your saves and settings are never touched. The game runs in a separate profile, `%APPDATA%\Brotato Test`, which loads the mods from `tests/harness/run/mods` instead of the Workshop, and every session checks that your real profile stayed unchanged; see [harness/README.md](harness/README.md).

## Running

```powershell
./tests/run-integration.ps1
./tests/run-integration.ps1 -Mods der_floh-example_mod
./tests/run-integration.ps1 -Mods der_floh-example_mod -Session solo -Test 'test_shop*'
./tests/run-integration.ps1 -List
```

| Parameter | What it does |
| --- | --- |
| `-Mods <ids>` | Only the suites of these mods. |
| `-Session <names>` | Only these sessions: `solo`, `all`, or a session name from a `suite.json`. |
| `-Test <wildcard>` | Only tests whose function or file name matches. |
| `-List` | Prints the planned sessions and tests without starting the game. |
| `-NoBuild` | Uses the zips of the previous build. |
| `-TimeoutSec` | How long one test may take (default 120) before its session is restarted. |

Each session starts the game, runs its tests one at a time and quits; a test that hangs or crashes the game is reported and its session restarted.

Results go to the console and to `tests/harness/run/results/`: `summary.md`, `integration.xml` (JUnit), and the `godot.log` and `modloader.log` of every session with a failure. The exit code is 1 when a test failed.

In VS Code, run the **Integration tests** task.

## Sessions

Every suite runs in two sessions:

- **solo:** its mod alone (plus the harness);
- **all:** all mods in `src/` at once.

A suite's `suite.json` can add more, for mods it has to work with:

```json
{
    "sessions": [
        { "name": "with-other-mod", "mods": ["der_floh-other_mod"], "tests": ["test_items.gd"] },
        { "name": "with-mod-options", "third_party": ["dami-ModOptions"], "tests": ["test_settings.gd"] }
    ]
}
```

- `mods` are other mods from `src/` loaded together with the suite's mod.
- `third_party` names rows of [`src/ThirdParty/ThirdParty-Mods.csv`](../src/ThirdParty/ThirdParty-Mods.csv); their zips are fetched by [`fetch-third-party.ps1`](fetch-third-party.ps1) when missing. Load a mod's dependencies along with it.
- `tests` limits which of the suite's files run there; without it, all of them do.

Sessions that load the same mods are merged, and the largest run first. The tests in `integration/_common/` run first in every session: the game started without script errors, GML logged no errors while loading the mods, Steam achievements stay off, and a wave ends in the shop and the next one starts. Without any suite, they run in the `all` session.

## Writing tests

A mod's tests live in `integration/<author>/<mod-id>/`, one `test_<area>.gd` file per feature area. Every `func test_*()` in a file is one test. Brotato runs Godot 3, so tests are GDScript 1: they wait with `yield`, and fixtures are coroutines you wait for with `yield(fixture(), "completed")`:

```gdscript
extends "res://mods-unpacked/der_floh-test_harness/integration_test.gd"

const MOD_ID := "der_floh-example_mod"


func before_each():
	use_value(DebugService, "no_enemies", true)


func test_helmet_adds_armor():
	if not yield(in_shop(), "completed"):
		return
	var armor_before: float = RunData.get_stat(Keys.stat_armor_hash, 0)
	if not yield(give_item("item_helmet"), "completed"):
		return
	expect_eq(RunData.get_stat(Keys.stat_armor_hash, 0), armor_before + 1, "armor after a helmet")
```

The test runs inside the game. The base class, [`integration_test.gd`](harness/src/der_floh/der_floh-test_harness/integration_test.gd), provides:

| Group | Members |
| --- | --- |
| Game | `tree`, `access`, `commands`, `wave()`, `shop()`, `player(index)`; the game's autoloads (`RunData`, `ItemService`, `ProgressData`, `DebugService`, ...) are globals |
| Mods | `mod(id)` (the mod's `mod_main` script, for its static functions and settings), `has_mod(id)`, `require_mods([ids])` |
| Fixtures | `fresh_run(character, weapon, difficulty, invulnerable)`, `in_wave()`, `in_shop()`, `end_wave(skip_choices)`, `next_wave()`: each yields and returns `false` after recording the failure when it can't get there |
| End of wave | `queue_level_ups(count)`, `queue_crates(count, legendary)` during a wave; `end_wave_async()` ends it without waiting; `await_offer()` waits for a level-up or crate item; `show_crate_item(id, cursed, curse_factor, weapon)` swaps the crate item on screen; `offer_container()` is the panel with its buttons; `await_shop()` |
| Cheats | `give_item(id, count)`, `give_weapon(id)`, `press_key(KEY_ESCAPE)`, and the harness commands through `commands.<name>({...})` |
| Waiting | `frames(n)`, `physics_frames(n)` |
| Restoring | `use_setting(mod_id, setting, value)` (through `set_<setting>`/`get_<setting>`), `use_value(object, property, value)`, `on_cleanup(target, method, args)` |
| Checks | `expect(condition, message)`, `expect_eq`, `expect_near`, `expect_between`, `fail`, `skip(reason)` |
| Hooks | `before_each()`, `after_each()` |

Things to know:

- **Checks don't stop a test.** GDScript has no exceptions, so after a fixture returns `false`, or after `skip()` or `require_mods()`, `return` yourself.
- **Wait for coroutines.** A GDScript 1 function only returns a value once it is done if it never yields; otherwise the caller gets a `GDScriptFunctionState`. The fixtures always yield, so always write `yield(fixture(), "completed")`. Your own helpers that yield must do the same in every branch.
- **No lambdas.** GDScript 1 has none, so `on_cleanup()` takes an object, a method name and its arguments, and `use_value()` covers properties.
- **Restore what you change.** Change mod settings through `use_setting`, `use_value` or `on_cleanup`. After every test the runner also restores config data, unpauses the game and resets `Engine.time_scale`, and every session starts with default configs.
- **Runs are shared.** Tests in a session reuse the current run, including items earlier tests bought. Start from `fresh_run()` when a test needs a clean run. New runs are solo, on wave 1, with the player invulnerable unless the fixture is told otherwise; `DebugService` flags such as `no_enemies` quiet the arena.
- **Logged errors fail the test.** Brotato's release build reports no GDScript runtime errors: an index out of range or a property read on null quietly gives `null`, and a method call on null closes the game at once. So the runner reads `godot.log` after each test and turns every `ERROR:` or `SCRIPT ERROR` line the test added (parse errors, `push_error`, GML's `ModLoaderLog.error`, engine errors) into an error with its message. A game that closes during a test is reported as such and its session restarted. Check results with expectations rather than counting on errors.
- **Tests are compiled from the repo** each time they run, with `res://tests/integration/...` as their path, so errors name the file. They can't `preload` other files or use `class_name`, and must not name another mod's classes or files unless that mod is in every session the file runs in; use `has_mod()` and `mod()` instead. Variables whose type comes from the game's autoloads need an explicit type, because `:=` can't infer it.
- **Make randomness irrelevant.** Force the state a test needs (items with `give_item`, flags on `DebugService`) instead of waiting for luck. The runner seeds the random generator per test, so a test repeats the same way.
- **Keys:** `harness.ps1 call action` sends input actions; use `press_key()` for code that reads key events. It sends each event at the start of a frame, like real input; an event sent from a `physics_frame` or `frame_post_draw` callback that switches menu pages logs engine errors.
- **One scene change per frame.** Mods that watch the current scene see it once per frame, so give a scene a few frames before changing it again, as a player would.

Try a single test while writing it with `-Mods <id> -Session solo -Test <name>`; add `-NoBuild` when only test files changed.
