# Modifications in this fork

This is an **unofficial modified fork** of **PokéBot NDS** by **wyanido**, based on the upstream 1.2-beta project.

The original project is licensed under the MIT License. The original `LICENSE` file and its copyright notice are preserved unchanged.

## D/P/Pt work in this fork

This source corresponds to the confirmed working D/P/Pt branch used with the custom melonDS Lua build.

Major D/P/Pt changes include:

- Expanded daycare and egg-hatching automation.
- Automatic post-hatch PC depositing while permanently protecting party slot 1.
- Live PC storage scanning and box-selection handling for Diamond, Pearl, and Platinum.
- Separate D/P/Pt PC scan handling and fixes for occupied slots that cannot be fully decoded.
- Fixed hatching-lane reacquisition and settled hatching start after returning from the PC.
- Random-encounter and small-area encounter improvements.
- D/P/Pt battle-state handling and live PP refreshes.
- No automatic in-battle party switching; exhausted leads are handled between battles.
- A 6-second post-battle settling delay before the existing between-battle lead-switch routine.
- Platinum Poké Ball pocket / auto-catch compatibility fixes.
- Save-after-target input/timing fixes.
- Fishing diagnostics and D/P/Pt fishing compatibility fixes.
- melonDS Lua compatibility updates, including UTF-8 compatibility and more robust dashboard socket handling.
- The upstream D/P/Pt Starters implementation is present/restored, including the Diamond/Pearl and Platinum paths.
- Adds a D/P/Pt-specific 6-second post-battle settling delay before opening the party menu to remove an item obtained with Thief. This prevents menu navigation inputs from leaking into the overworld during the battle transition.

These modifications are unofficial and are not endorsed by or maintained by the original PokéBot NDS author.

## LuaSocket runtime dependency

This repository intentionally includes the bundled Windows LuaSocket runtime file:

`lua/modules/socket/core.dll`

PokéBot's dashboard communication requires `socket.core`, so this file is retained to keep the dashboard usable for Windows users.

LuaSocket is distributed under the MIT License. Its license notice is included in `THIRD_PARTY_LUASOCKET_LICENSE.txt`.

## Distribution notes

This repository does not include Pokémon ROMs, Nintendo BIOS/firmware dumps, or save files.
