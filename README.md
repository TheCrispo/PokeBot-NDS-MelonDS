# PokéBot NDS — DPPt Enhanced

<img src='https://i.imgur.com/lHaYC4z.png' width='600px'>

An unofficial fork of **PokéBot NDS by wyanido**, focused on improved Pokémon Diamond, Pearl and Platinum automation and melonDS Lua compatibility.

This fork keeps the original PokéBot functionality while adding and refining D/P/Pt automation, including improved daycare and egg-hatching behaviour, automatic PC depositing, encounter and battle timing fixes, Platinum compatibility improvements, and restored D/P/Pt starter resets.

See [`MODIFICATIONS.md`](MODIFICATIONS.md) for a more detailed record of changes made in this fork.

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/en)
- A compatible Lua-enabled emulator. This fork is developed and tested primarily with the accompanying **melonDS PokéBot Lua build**.

### Installation

Clone or download this repository to your computer.

If downloading a release, extract the archive somewhere convenient before starting the bot.

### Setup

1. Start the dashboard with `start-dashboard.bat`, or run the following commands inside the `dashboard/` folder:
   - `npm i`
   - `npm start`
2. Use the dashboard **Config** tab to configure the bot for the task you want to perform.
3. Open the emulator's Lua Console and load `pokebot-nds.lua`.
4. Once connected, PokéBot will begin operating according to the selected configuration and encounters will be logged to the dashboard.

## D/P/Pt Support

The fork retains the original PokéBot modes while expanding and fixing support for Pokémon Diamond, Pearl and Platinum.

| Mode / Feature | D/P/Pt |
|---|:-:|
| Starter resets | ✅ |
| Random encounters | ✅ |
| Random encounters (small areas) | ✅ |
| Gift resets | ✅ |
| Static encounters | ✅ |
| Roamers | ✅ |
| Fishing | ✅ |
| Egg hatching | ✅ |
| Automatic daycare handling | ✅ |
| Automatic PC depositing after hatching | ✅ |
| Auto-catching | ✅ |
| Auto-battling | ✅ |
| Thief farming | ✅ |
| Pickup farming | ✅ |

Other game-specific functionality from the original PokéBot project remains in the source where applicable.
While the other Pokémon game have not been tested you are welcome to try them out and see if they work. There will be future updates bringing enchancements and compatibility.

## D/P/Pt Enhancements

This fork includes (Relevent to MelonDS with Lua compatibilty) :

- Expanded D/P/Pt daycare and egg-hatching automation.
- Automatic depositing of newly hatched non-target Pokémon into the PC.
- Protection for party slot 1 during automatic depositing.
- Live PC box scanning for Diamond, Pearl and Platinum.
- Automatic selection of a PC box with available space.
- Improved hatching-route recovery after PC trips.
- D/P/Pt battle-state and post-battle timing fixes.
- Improved PP handling and between-battle lead switching.
- Platinum Poké Ball / auto-catch compatibility improvements.
- Save-after-target timing and input fixes.
- Improved random-encounter behaviour.
- melonDS Lua compatibility and dashboard connection improvements.

For implementation details, see [`MODIFICATIONS.md`](MODIFICATIONS.md).

## Credits and Licensing

This is an **unofficial fork** of [PokéBot NDS](https://github.com/wyanido/pokebot-nds) by **wyanido**.

PokéBot NDS is distributed under the MIT License. The original copyright and license notice are preserved in [`LICENSE`](LICENSE).

This repository also includes the LuaSocket runtime component used by the dashboard. Its license notice is included in [`THIRD_PARTY_LUASOCKET_LICENSE.txt`](THIRD_PARTY_LUASOCKET_LICENSE.txt).

This fork is not endorsed by or maintained by the original PokéBot NDS author.

Special Thanks kept below as it still applies.

## Special Thanks

- The contributors of [BizHawk](https://github.com/TASEmulators/BizHawk) and [DeSmuME](https://github.com/TASEmulators/DeSmuME) for providing a basis to make this project possible
- [40 Cakes](https://github.com/40Cakes) for the [Gen III PokéBot](https://github.com/40Cakes/pokebot-gen3) that originally inspired this project
- [evandixon](https://projectpokemon.org/home/profile/183-evandixon/) for demystifying the [NDS Pokemon format](https://projectpokemon.org/home/docs/gen-5/bw-save-structure-r60)
