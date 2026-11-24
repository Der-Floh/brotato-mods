# Auto Brotato

Takes over the routine clicks at the end of a wave, so a strong late-game run plays itself between waves: it recycles crate items you don't want, takes the ones you do, picks level-ups and starts the next wave. Each of the four is switched on and off on its own, and all are off until you switch them on.

Auto Brotato only presses the game's own buttons (Take, Recycle, the level-up choices and Go), so everything after the click works as if you had clicked yourself, including the effects of other mods. It works with or without the Abyssal Terrors and Primal Dread DLCs, with items other mods add, and in local co-op, where every player is handled with the same settings.

## Settings

Open them in the pause menu or on the title screen with the **Auto Brotato** button. The switches and sliders also appear under Options → Mods when dami's Mod Options or Oudstand's Mod Options is installed.

| Setting | Default | Description |
| --- | --- | --- |
| Recycle unwanted crate items | Off | Recycles crate items you crossed out, and cursed-only items that aren't cursed enough |
| Take wanted crate items | Off | Takes every other crate item |
| Pick level-ups | Off | Picks one of the offered level-ups by their weights |
| Start the next wave | Off | Presses Go in the shop |
| Next wave delay | `0 s` | Waits up to 10 seconds first, with a countdown above the Go button; Esc cancels it for this shop |
| Last wave to start | `0` | Stops starting waves after this wave; `0` never stops |

### Crate items

The **Crate items** page lists every item and weapon a crate can hold in your game. Click an item to cross it out: crossed-out items are recycled, all others are taken. With Abyssal Terrors, right-click an item to take it only when it is cursed, or only when its curse bonus is at least a percentage you choose. Weapons only come from crates for characters like the Survivor.

A crate item the game won't let you take as it is waits for you: a Primal Dread meca weapon that still needs its effect chosen, or a weapon without a free slot and nothing to combine it with.

### Level-ups

The **Level-ups** page gives every level-up a weight from `0` to `100` (default `100`). When a level-up shows, one of the offered choices is picked with a chance in proportion to its weight, so with weights 80 and 20 the first is picked four times out of five. A weight of `0` is never picked, and when every offered choice has `0`, you pick yourself.

### Next wave

The shop after wave 19 offers endless mode, so Auto Brotato leaves the choice to you there. It also doesn't start a wave when a saved run continues in the shop.

## Compatibility

- Brotato 1.2.0.4 with its built-in mod loader 6.3.0.
- No game script is replaced or extended, which keeps it compatible with mods that change the same screens.
