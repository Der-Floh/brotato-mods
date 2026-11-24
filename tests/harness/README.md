# Brotato test harness

The harness launches Brotato with exactly the mods you choose, in a separate profile, and lets a script drive the game through a local HTTP API: run and wave flow, cheats, GDScript run inside the game, screenshots and logs. The [integration tests](../README.md) are built on it, and it is handy on its own for trying out a change.

It is a dev tool: its mod (`der_floh-test_harness`) lives here, outside `src/`, so neither the build nor GitHub's workflows ever pack or publish it.

## How it loads local mods

Brotato's Steam build loads only the Workshop items you are subscribed to and ignores GML's `--mods-path`. While the game starts, a marked `override.cfg` next to `Brotato.exe` does two things:

- it points `user://` at `%APPDATA%\Brotato Test`, so saves, settings, logs, mod configs and GML's cache go there instead of `%APPDATA%\Brotato`;
- it replaces the `ModLoaderStore` autoload with [`bootstrap/mod_loader_store.gd`](bootstrap/mod_loader_store.gd), which `start` copies into that profile. It extends GML's own store and turns Workshop loading off, so GML loads the zips in `--mods-path` (`run/mods`) instead. It also keeps mods on when Brotato's crash reporter found a mod error in the previous session's log, which would otherwise disable them.

## Safety

- **Separate profile.** The test profile is outside what Steam Cloud syncs. The harness mod deletes `override.cfg` as soon as it loads, and `start` deletes it again in every outcome.
- **Wrong-profile guard.** A harness-launched game that finds itself in any other profile kills itself before it can save, and `start` refuses a game whose `status` reports another `user_data_dir`.
- **No achievements.** Challenges completed in an ordinary save also unlock your Steam achievements. The harness turns the test profile's save into an unlock-all save, the game's own option, which never reports them; it also unlocks every character, weapon, item and difficulty for the tests.
- **Check at the end.** `start` hashes every file in your real profile; `stop` prints `real_profile_unchanged` and lists any file that changed.
- **Local only.** The API listens on 127.0.0.1 and needs the random per-session token in the `X-Harness-Token` header.

## Usage

Run from the repo root in PowerShell 7 or Windows PowerShell 5.1, with Steam running, and always finish with `stop`:

```powershell
./tests/harness/harness.ps1 start -Compact
./tests/harness/harness.ps1 call new_run @{ character = 'character_ranger'; weapon = 'weapon_pistol_1' } -Compact
./tests/harness/harness.ps1 call end_wave -Compact
./tests/harness/harness.ps1 eval 'return RunData.get_player_gold(0)'
./tests/harness/harness.ps1 screenshot shop
./tests/harness/harness.ps1 stop
```

| Script command | What it does |
| --- | --- |
| `start [-Mods <ids>] [-Extra <zips>] [-NoBuild]` | Builds the repo mods and the harness (skipped with `-NoBuild`), copies the chosen zips to `run/mods`, re-enables any mod GML marked inactive in the test profile, launches the game windowed at 1280x720 without sound, and waits for the API. Without `-Mods`, every mod in `src/` is loaded. `-Extra` adds outside zips, such as a third-party mod. |
| `status` | Prints the game state. |
| `call <command> [@{ ... }]` | Sends an API command; arguments go in a hashtable, or as raw JSON with `-Json`. |
| `eval '<gdscript>'` | Runs GDScript inside the game. |
| `screenshot [name]` | Saves `run/screenshots/<name>.png` and prints its path. |
| `log [-Lines N] [-ModLoader]` | Prints the end of the test profile's `godot.log`, or `modloader.log`. |
| `stop` | Quits the game (killing it if it is frozen), removes a leftover `override.cfg` and runs the profile check. It also repairs an interrupted session. |

`-Compact` prints `status`, `call` and `eval` results on one line without the mod list. The game folder comes from `-GameDirectory`, the `BROTATO_GAME_DIR` environment variable, or your Steam libraries.

Scripts can import [`Harness.psm1`](Harness.psm1) instead: `Start-HarnessSession`, `Stop-HarnessSession`, `Invoke-HarnessCommand`, `Get-HarnessLog` and `Clear-HarnessModConfig`.

## API commands

| Command | Arguments (default) | What it does |
| --- | --- | --- |
| `status` | | pid, `user_data_dir`, scene, in wave, in shop, paused, unlock-all save, wave, zone, difficulty, character, gold, level, health, weapons, items, loaded mods |
| `new_run` | `character` (`character_well_rounded`), `weapon` (`weapon_knife_1`, `""` for none), `difficulty` (0), `zone` (0), `invulnerable` (`true`) | Starts a solo run the way the character, weapon and difficulty menus do, and waits for wave 1. |
| `end_wave` | `skip_choices` (`true`) | Ends the running wave and waits for the shop, or the end screen when the run is over. Skipping drops the level-up and crate choices; without it, the game waits for them. |
| `next_wave` | | Leaves the shop and waits for the next wave. |
| `give_item` | `id`, `count` (1) | Adds an item such as `item_helmet`, as a purchase would. A running wave's player gets its stats when the next wave starts. |
| `give_weapon` | `id` | Adds a weapon such as `weapon_pistol_1`; a running wave's player gets it when the next wave starts. |
| `set_gold` | `amount` | Sets the materials. |
| `action` | `name`, `mode` (`tap`, `press`, `release`) | Sends an input action, for example `ui_pause`. |
| `screenshot` | `name` | Saves a screenshot. |
| `eval` | `code` | Runs GDScript. |
| `run_test` | `path`, `source`, `function` | Runs one integration test; used by `run-integration.ps1`. |
| `quit` | | Quits the game. |

## eval

The code becomes the body of `func run()`: indent with tabs, `yield` works, and whatever you `return` comes back as JSON (values JSON can't hold come back through `var2str`). It can use `tree`, `access`, `wave()`, `shop()`, `player(index)`, `mod("<mod-id>")`, which returns that mod's `mod_main` script, and the game's autoloads such as `RunData`. A snippet that doesn't compile returns `ok: false`, and the reason is in `log`.

```powershell
./tests/harness/harness.ps1 eval 'var ids = []
for weapon in RunData.get_player_weapons(0):
	ids.append(weapon.my_id)
return ids'
```

## Limits

- Brotato runs Godot 3, so the harness and the tests are GDScript 1: no lambdas, `yield` instead of `await`, and `:=` can't infer types from the game's autoloads.
- The game is a release build, which logs no GDScript runtime errors: bad indexes and property reads on null give `null`, and a method call on null closes the game without a word, also in `eval`. Errors only show when code calls `push_error` (GML's `ModLoaderLog.error` does) or the engine reports one.
- Godot writes `godot.log` lines other than errors only when its buffer fills or the game exits, so a crashed game loses its last lines.
- `action` sends an `InputEventAction`; code that reads key events needs an `InputEventKey` with `scancode` and `physical_scancode` set, which `press_key()` in the test base class sends.
- Mod config changes write the test profile's `configs` folder. Restore what a test changed, or delete that folder, especially after a killed or crashed session.

## Files

```
harness.ps1                          command line
Harness.psm1                         session logic, shared with run-integration.ps1
bootstrap/mod_loader_store.gd        the ModLoaderStore replacement that loads run/mods
src/der_floh/der_floh-test_harness/  the GML mod: mod_main, server, commands, game_access, eval_runner, test_runner, integration_test, profile_switch, json_value
run/                                 created by the harness, ignored by git: build/, mods/, screenshots/, results/, session.json, real-profile-fingerprint.json
```

The test profile lives in `%APPDATA%\Brotato Test`; delete it whenever you want a clean slate.
