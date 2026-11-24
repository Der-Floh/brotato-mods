# Brotato Mods

Collection of mods for the game [Brotato](https://store.steampowered.com/app/1942280/Brotato/).

> **IMPORTANT:** You use mods at your own risk. I am not responsible for any issues or damage caused by using mods.

---

## Installation

Subscribe to a mod on its Steam Workshop page and start Brotato: the game's built-in mod loader loads every Workshop item you are subscribed to. Unsubscribe to remove it again. The **Mods** button in the main menu lists the loaded mods.

---

## Overview

Every mod in this repository has its own README with all its settings, linked from the table below.

| Mod | Author | Description |
| --- | ------ | ----------- |
| [Auto Brotato](src/der_floh/der_floh-auto_brotato/README.md) (`der_floh-auto_brotato`) | der_floh | Recycles unwanted crate items, takes wanted ones, picks level-ups by weight and starts the next wave, each switchable on its own |

---

## Repository layout

| Folder | Contents |
| --- | --- |
| `src/<author>/<namespace>-<name>/` | One mod each: `manifest.json`, `mod_main.gd`, `README.md`, `changelog.md`, its scripts and assets, and `media/` with the images for its Workshop page. |
| `src/ThirdParty/` | Other authors' mods for reference and compatibility tests; see [Third-party mods](#third-party-mods). |
| `.vscode/build/` | Build, validation and Workshop publishing scripts. |
| `.github/` | GitHub workflows and `workshop-items.json`, the Workshop item of every published mod. |
| `tests/` | Integration tests that run inside the game, and the harness that drives it. |

## Building from source

[`.vscode/build/build.ps1`](.vscode/build/build.ps1) packs every mod in `src/<author>/<mod>/` (except `src/ThirdParty/`) into `out/<author>/<namespace>-<name>-<version>.zip` with the layout Godot Mod Loader expects, and writes each mod's Workshop description to `out/workshop/`. [`.vscode/build/validate.ps1`](.vscode/build/validate.ps1) then checks that every zip is in the folder of its mod's author, matches its source folder and has the layout and manifest that GML 6.3, the mod loader Brotato ships, accepts.

```powershell
./.vscode/build/build.ps1
./.vscode/build/validate.ps1
```

Both work with PowerShell 7 (`pwsh`) on Windows, Linux and macOS, and with the Windows PowerShell 5.1 that ships with Windows. Pass `-OutputDirectory <folder>` to build somewhere else and `-ZipDirectory <folder>` to validate that folder. As long as `src/` has no mods, run the build with `-AllowEmpty`. If Windows PowerShell refuses to run scripts, start it with `powershell -ExecutionPolicy Bypass -File .vscode\build\build.ps1`.

In VS Code, **Ctrl+Shift+B** runs the build, and **Tasks: Run Test Task** builds and then validates.

Every mod folder has a `README.md`, which is packed into the zip like the mod's other files. [`.vscode/build/workshop-descriptions.ps1`](.vscode/build/workshop-descriptions.ps1) converts it into the BBCode of the Steam Workshop: headings become `[h1]` to `[h3]`, tables stay tables and relative links point to the file on GitHub. The build runs it after packing; run it on its own, or the **Workshop descriptions** task, to regenerate only the descriptions.

## Publishing

GitHub runs the build and the validation on every push to `main` and every pull request. A release reaches players in two steps:

1. **GitHub release.** Bump the `version_number` of every changed mod, add a section for that version to its `changelog.md`, and publish a GitHub release. [`release.yml`](.github/workflows/release.yml) builds and validates the release tag and attaches every zip to the release, attested.
2. **Steam Workshop.** On your PC, run [`.vscode/build/publish-workshop.ps1`](.vscode/build/publish-workshop.ps1). It uploads every mod whose version differs from the one [`.github/workshop-items.json`](.github/workshop-items.json) records, with its changelog section as change note, then records the item id and the uploaded version there; commit that file.

```powershell
./.vscode/build/publish-workshop.ps1 -SteamUser <account> -DryRun
./.vscode/build/publish-workshop.ps1 -SteamUser <account>
```

The script uses [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD), which asks for your password and Steam Guard code the first time and then reuses the saved login; your Steam client may be signed out while it uploads. Your login never leaves your PC. An existing item keeps the title, description, preview image, tags and visibility of its Workshop page (`-UpdateDescription` replaces the description with the converted README). A mod without an item gets a new hidden one, titled with its README heading and with `media/preview.png` as preview image; set its tags and make it public on its Workshop page.

## Integration tests

[`tests/run-integration.ps1`](tests/run-integration.ps1) starts Brotato with the mods and checks, inside the running game, that each mod does what its README says: alone, with all mods in `src/` at once, and in the combinations its suite declares. The tests need the game and Steam, so they run only locally, never in GitHub's workflows. [tests/README.md](tests/README.md) explains running them and writing new ones, and [tests/harness/README.md](tests/harness/README.md) the harness they use to drive the game.

```powershell
./tests/run-integration.ps1
```

In VS Code, the **Integration tests** task runs them.

## Third-party mods

`src/ThirdParty/` holds other authors' mods, for reading their code and for testing compatibility with them. Only [`ThirdParty-Mods.csv`](src/ThirdParty/ThirdParty-Mods.csv), with each mod's name, author and URL, is tracked; everything else in the folder is ignored by git, and the build, the validation and publishing skip it. Never edit a mod there. [`tests/fetch-third-party.ps1`](tests/fetch-third-party.ps1) puts each listed mod there as a zip Godot Mod Loader can load: from its latest GitHub release, or from Steam's download of a Workshop item you are subscribed to.

```powershell
./tests/fetch-third-party.ps1
```
