# gameWE - SourceMod plugin

> **Fork:** This project is a fork of the gameME SourceMod plugin
> ([gamemedev/plugin-sourcemod](https://github.com/gamemedev/plugin-sourcemod)), version 5.0.0, by TTS Oetzel & Goerz GmbH.

gameWE is a statistics system for Source and GoldSrc game servers, in the
style of gameME / HLstatsX. The **SourceMod plugin** runs on each Source game
server and works together with the
[gameWE collector](https://github.com/DennisPohlmann/gameWE-collector). It

- writes extra statistics to the server log: per-weapon accuracy and hit groups
  (`weaponstats`, `weaponstats2`), player actions (bomb planted, flag captured,
  healed, ...), positions and roles,
- offers the console commands the collector uses to answer players in game
  (`gamewe_psay`, `gamewe_msay`, ...),
- hides the stats chat commands (`!rank`, `!top10`, ...) from chat, but still
  logs them for the collector,
- shows the gameWE menu (`!gamewe`), a damage summary on death and the stats of
  the spectated player; every player chooses these displays in the gameWE
  settings menu, `gamewe.cfg` only sets the default,
- keeps the players' own settings of gameME's commands: console and chat
  events (`gamewe_display`, `gamewe_chat`), auto commands at round start,
  round end and death (`gamewe_auto`) and the language (`gamewe_lang`, 9
  languages, also for the collector's answers),
- gives other plugins access to the statistics through natives and forwards.

It is the original gameME plugin 5.0.0, ported to current SourcePawn and
renamed to gameWE. The log format and the command interface stay compatible
with gameME. It has no database access of its own.

Current version: see `VERSION` and [CHANGELOG.md](CHANGELOG.md).

## Requirements

- [Metamod:Source](https://www.sourcemm.net/) and [SourceMod](https://www.sourcemod.net/)
  **1.12 or newer**; SDKHooks, ClientPrefs and the game extensions (cstrike,
  tf2) ship with SourceMod and are used when present
- the gameWE collector 0.1.0 or newer, with the server registered in its
  `hlstats_Servers`

## Supported games

| Game | Detected as |
|------|-------------|
| Counter-Strike: Source | `CSS` |
| Counter-Strike: Global Offensive (legacy servers) | `CSGO` |
| Team Fortress 2 | `TF2` |
| Day of Defeat: Source | `DODS` |
| Half-Life 2: Deathmatch | `HL2MP` |
| Left 4 Dead, Left 4 Dead 2 | `L4D`, `L4DII` |
| Zombie Panic! Source | `ZPS` |
| Fistful of Frags, No More Room in Hell | `FOF`, `NMRIH` |

Insurgency (2014), Fortress Forever and CSPromod are no longer supported:
the gameWE collector retired them, and the plugin no longer detects them.
A server that still runs an older plugin version keeps logging as before.

The game is detected from the engine version, and from the game name and folder
for mods. The result is in the log: `gameWE Game Detection: ...`.

**Counter-Strike 2 is not supported.** SourceMod does not run on CS2.

## Quick start

1. Extract `gamewe-sourcemod-<version>.tar.gz` (or `.zip`) from the releases
   into the game folder, the folder that contains `addons/`:

   ```bash
   tar -xzf gamewe-sourcemod-0.1.0.tar.gz -C /path/to/server/cstrike
   ```

2. Remove the old gameME plugin (`addons/sourcemod/plugins/gameme.smx`) if
   it is installed.
3. Add to `server.cfg`:

   ```
   log on
   mp_logdetail 3
   logaddress_add 203.0.113.5:41337     // the collector's IP and UDP port (CS:GO: in quotes)
   rcon_password "change-me"            // the same as in the collector's hlstats_Servers
   ```

4. Restart the server or change the map; `sm plugins list` shows `gameWE`.

Every step in detail: [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Documentation

| File | Content |
|------|---------|
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | installation step by step: requirements, game server setup, pairing with the collector, update, removal, coming from gameME |
| [docs/CONFIG.md](docs/CONFIG.md) | the ConVars in `cfg/sourcemod/gamewe.cfg` |
| [docs/USAGE.md](docs/USAGE.md) | chat commands and the gameWE menu |
| [docs/INTERFACE.md](docs/INTERFACE.md) | log lines, the collector's server commands, natives and forwards for other plugins |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | building, CI and releases |
| [CHANGELOG.md](CHANGELOG.md) | changes per version |
| [docs/gameme-CHANGELOG.txt](docs/gameme-CHANGELOG.txt) | the changelog of the original gameME plugin up to 5.0.0 |

## gameWE components

| Repository | Part |
|------------|------|
| [gameWE-collector](https://github.com/DennisPohlmann/gameWE-collector) | receives the game server logs and fills the database |
| [gameWE-web](https://github.com/DennisPohlmann/gameWE-web) | statistics website and admin area |
| [gameWE-plugin-sourcemod](https://github.com/DennisPohlmann/gameWE-plugin-sourcemod) | game server plugin for Source games (this repository) |
| [gameWE-plugin-amxmodx](https://github.com/DennisPohlmann/gameWE-plugin-amxmodx) | game server plugin for GoldSrc games |

## Building

```bash
make build      # build/stage/addons/sourcemod/plugins/gamewe.smx
make package    # dist/gamewe-sourcemod-<version>.tar.gz and .zip, each with its .sha256
```

Requirements and the release process: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

gameWE is free software under the **GNU General Public License version 3 or later**,
see [LICENSE](LICENSE).

It is based on the gameME plugin, Copyright (C) 2007-2020 TTS Oetzel & Goerz GmbH,
published under the GPL version 2 or later. It contains the SuperLogs code by
Nicholas Hastings (psychonic), also under the GPL (versions up to 0.3.1 also
contained Insurgency logging based on work by FZFalzar and Jared Ballou). The gameME changelog up to 5.0.0 is kept in
[docs/gameme-CHANGELOG.txt](docs/gameme-CHANGELOG.txt).
