# gameWE - SourceMod plugin

> **Fork:** This project is a fork of the gameME SourceMod plugin
> ([gamemedev/plugin-sourcemod](https://github.com/gamemedev/plugin-sourcemod)), version 5.0.0, by TTS Oetzel & Goerz GmbH.

The gameWE SourceMod plugin runs on the game server and works together with the
[gameWE collector](https://github.com/DennisPohlmann/gameWE-collector). It

- writes extra statistics to the server log: per-weapon accuracy and hit groups
  (`weaponstats`, `weaponstats2`), player actions (bomb planted, flag captured,
  healed, ...), positions and roles,
- offers the console commands the collector uses to answer players in game
  (`gamewe_psay`, `gamewe_msay`, ...),
- hides the stats chat commands (`!rank`, `!top10`, ...) from chat, but still
  logs them for the collector,
- shows the gameWE menu (`!gamewe`), and optionally a damage summary on death,
- gives other plugins access to the statistics through natives and forwards.

It is a fork of the original [gameME plugin](https://github.com/gamemedev/plugin-sourcemod)
5.0.0, ported to current SourcePawn, renamed to gameWE. The log format and the command
interface stay compatible with gameME.

Current version: see `VERSION` and [CHANGELOG.md](CHANGELOG.md). Requires SourceMod 1.12
or newer; works with the gameWE collector 0.1.0 or newer.

## Contents

1. [Supported games](#supported-games)
2. [Install](#install) (step by step: [INSTALLATION.md](INSTALLATION.md))
3. [Game server setup](#game-server-setup)
4. [Configuration](#configuration)
5. [Chat commands](#chat-commands)
6. [Collector interface](#collector-interface)
7. [For plugin developers](#for-plugin-developers)
8. [Migrating from the gameME plugin](#migrating-from-the-gameme-plugin)
9. [Building](#building)
10. [License](#license)

## Supported games

| Game | Detected as |
|------|-------------|
| Counter-Strike: Source | `CSS` |
| Counter-Strike: Global Offensive (legacy servers) | `CSGO` |
| Team Fortress 2 | `TF2` |
| Day of Defeat: Source | `DODS` |
| Half-Life 2: Deathmatch | `HL2MP` |
| Left 4 Dead, Left 4 Dead 2 | `L4D`, `L4DII` |
| Insurgency (2014) | `INSMOD` |
| Fortress Forever, CSPromod, Zombie Panic! Source | `FF`, `CSP`, `ZPS` |

The game is detected from the engine version, and from the game name and folder
for mods. The result is in the log: `gameWE Game Detection: ...`.

**Counter-Strike 2 is not supported.** SourceMod does not run on CS2.

## Install

[INSTALLATION.md](INSTALLATION.md) has every step (requirements, folder
layout, settings, pairing with the collector, reload, upgrade, removal). In short:

Requirements: [Metamod:Source](https://www.sourcemm.net/) and
[SourceMod](https://www.sourcemod.net/) **1.12 or newer**. SDKHooks, ClientPrefs
and the game extensions (cstrike, tf2) ship with SourceMod and are used when present.

1. Download `gamewe-sourcemod-<version>.tar.gz` (or `.zip`) from the releases.
2. Extract it into the game folder of the server, the folder that contains
   `addons/` (for example `cstrike/`, `csgo/`, `tf/`):

   ```bash
   tar -xzf gamewe-sourcemod-0.1.0.tar.gz -C /path/to/server/cstrike
   ```

   This installs `addons/sourcemod/plugins/gamewe.smx`, the translations and
   the source code. The example plugin `gamewe_messages.smx` is placed in
   `plugins/disabled/` and does not load.
3. If the old gameME plugin is installed, remove `addons/sourcemod/plugins/gameme.smx`
   (see [Migrating](#migrating-from-the-gameme-plugin)).
4. Restart the server or change the map. Check with `sm plugins list` that
   `gameWE` is loaded.

On the first start the plugin writes its settings to
`cfg/sourcemod/gamewe.cfg`. SourceMod never changes that file afterwards: a
setting added in a later version works with its default until you add its
line yourself.

## Game server setup

The collector reads the server log over UDP and answers over RCON. Add this to
`server.cfg`:

```
log on
mp_logdetail 3                       // log attacks, needed by some games for full detail
logaddress_add 203.0.113.5:41337     // IP and port of the collector (default port 41337)
rcon_password "change-me"            // the same password as the server's row in the collector's hlstats_Servers
```

The server must be registered in the collector (web admin, or `gamewe server
add` on the collector host) with its IP, game port, game and RCON password.

On CS:GO, `logaddress_add` needs quotes around the address.

To stop admins or other plugins from removing the collector address by accident,
set `gamewe_protect_address` to the same address (see below). The plugin then
adds it again after `logaddress_del` / `logaddress_delall`, and turns logging back
on after `log off`.

## Configuration

All settings are in `cfg/sourcemod/gamewe.cfg`.

| ConVar | Default | Meaning |
|--------|---------|---------|
| `gamewe_block_commands_values` | | More commands that are silent when typed with `/`, separated by spaces. `clear` removes all, including the defaults. |
| `gamewe_message_prefix` | | Text put in front of every gameWE message. Supports the color tags. |
| `gamewe_protect_address` | | `ip:port` of the collector to protect, see above. |
| `gamewe_chat_cooldown` | `1.0` | Seconds between two gameWE commands of one player that are passed to the collector (silent `/` commands and menu entries), 0-30, `0` = off. |
| `gamewe_log_locations` | `1` | Log player positions with kills and actions. |
| `gamewe_display_spectatorinfo` | `0` | CS:S and CS:GO: show the stats of the player you spectate. |
| `gamewe_damage_display` | `0` | Damage summary on death: `0` off, `1` menu, `2` chat. |
| `gamewe_plugin_version` | | Read only, the plugin version. |

The server command `gamewe_message_prefix_clear` empties the prefix.

## Chat commands

Players type these in chat, with `!`, `/` or nothing in front. With
`/` (`/rank`) the plugin hides the line from chat and logs it itself as a
`say` line, for example `"Name<2><STEAM_1:0:123><CT>" say "/rank"`; with `!`
(`!rank`) or without a prefix the line stays visible to everybody and the
engine logs it. The collector answers both, privately.

`rank`, `skill`, `points`, `place`, `session`, `sdata`, `kpd`, `kdratio`, `kdeath`,
`next`, `load`, `status`, `top5`, `top10`, `top20`, `maps`, `map_stats`, `clans`,
`cheaters`, `statsme`, `weapons`, `weapon`, `action`, `actions`, `accuracy`,
`targets`, `target`, `kills`, `kill`, `player_kills`, `cmds`, `commands`, `help`,
`gstats`, `global_stats`, and the settings commands `gamewe_display 0|1`,
`gamewe_chat 0|1`, `gamewe_atb 0|1`, `gamewe_hideranking`, `gamewe_reset`.
The `gameme_*` spellings are hidden too.

The collector answers `!rank`, `!statsme`, `!session`, `!status`, `!next`,
`!top10`, `!hideranking`, `!settings` and `!help`; the other words are hidden
from chat but not answered.

`!gamewe` or `!gamewe_menu` opens the gameWE menu (also in the SourceMod
settings menu `!settings`, when ClientPrefs is loaded). The menu entries send the
matching chat command for the player, for example `/rank` or `/top10`. The
menu entry "Settings" (also `!gamewe_settings`, the console command
`sm_gamewe_settings`, and "gameWE Settings" in SourceMod's `!settings` menu) has
"Hide me in the ranking" and "Show me in the ranking": they send
`/gamewe_hideranking 1` or `/gamewe_hideranking 0` for the player, and the
collector answers with the new state in chat. The plugin has
no database, so it cannot show the current state; both choices are always
offered. The gameME entries "Auto Ranking", "Toggle Ranking Display" and
"Reset Statistics" are gone: the collector has no such commands (players cannot hide
themselves from the rankings or reset their statistics, and there are no
commands to set profile data such as name, email or homepage).

## Collector interface

### Log lines

The plugin writes standard HL log lines. The ones the collector uses most:

```
"Name<2><STEAM_1:0:123><CT>" triggered "weaponstats" (weapon "ak47") (shots "14") (hits "6") (kills "1") (headshots "1") (tks "0") (damage "412") (deaths "0")
"Name<2><STEAM_1:0:123><CT>" triggered "weaponstats2" (weapon "ak47") (head "1") (chest "3") (stomach "1") (leftarm "0") (rightarm "1") (leftleg "0") (rightleg "0")
"Name<2><STEAM_1:0:123><CT>" triggered "mvp"
"Name<2><STEAM_1:0:123><CT>" say "!rank"
```

`weaponstats` lines are written when a player dies, disconnects or the round
ends (on L4D, L4D2 and Insurgency also every 180 seconds). `weaponstats2` follows
when the weapon hit something. TF2 writes `weaponstats` without `weaponstats2`.

### Server commands

The collector sends these over Source RCON. Players are addressed by their
**userid**, the number in the first `<..>` of a log line (`2` above).
Arguments may be quoted or not. The message is everything after the other
arguments, so it may contain spaces. `\n` in a message (backslash, n) is a line break.

| Command | Does |
|---------|------|
| `gamewe_psay <userid[,userid...]> [colored] "<message>"` | Private chat message. `colored` is `0` (plain), `1` (color tags), `2`/`3` (team colors). |
| `gamewe_csay "<message>"` | Center message to everybody. |
| `gamewe_msay <time> <userid> [handler] "<menu text>"` | Menu for `time` seconds, lines separated by `\n`. |
| `gamewe_tsay <time> <userid> "<message>"` | Message in the top left corner. |
| `gamewe_hint <userid[,userid...]> "<message>"` | Hint box (not on HL2:DM). |
| `gamewe_khint <userid[,userid...]> "<message>"` | Key hint box, on games that have one (CS:S); on CS:GO a hint box (Panorama shows no key hints). |
| `gamewe_browse <userid> "<url>"` | Opens a website in the in-game browser (MOTD); on CS:GO, which shows no web pages in the MOTD, the URL as a chat line. |
| `gamewe_swap <userid>` | Moves a player to the other team (CS:S, CS:GO). |
| `gamewe_redirect <time> <userid> <address> "<reason>"` | Asks a player to join another server. |
| `gamewe_player_action <userid> <action>` | Logs `triggered "<action>"` for a player. |
| `gamewe_team_action <team> <action> [objective]` | Logs a team action. |
| `gamewe_world_action <action>` | Logs a world action. |
| `gamewe_raw_message <type> <query_id> <userid> ...` | Data for other plugins, see below. |

Every command also exists with the `gameme_` prefix, so a collector or script
written for gameME works unchanged.

With `colored 1` the plugin replaces the tags `x01`, `x03`, `x04`, `x05`, `x07` and
`x08` in the message by chat color codes, as the gameME plugin did. `x01` is the
default color, `x03` the team color and `x04` green on most games. Which colors a
game can show depends on the game.

## For plugin developers

`addons/sourcemod/scripting/include/gamewe.inc` declares the natives and
forwards. `gamewe_messages.sp` is a complete example.

```sourcepawn
#include <gamewe>

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client)) {
        QueryGameWEStats("playerinfo", client, OnStats);
    }
}

public Action OnStats(int command, int payload, int client, Handle datapack)
{
    DataPack data = view_as<DataPack>(CloneHandle(datapack));
    data.Reset();
    int rank = data.ReadCell();
    // ... see gamewe_messages.sp for all fields
    delete data;
    return Plugin_Continue;
}
```

| Native | |
|--------|--|
| `QueryGameWEStats`, `QueryGameWEStatsTop10`, `QueryGameWEStatsNext` | Ask the collector for player, top 10 or next-player data. The answer arrives in the callback. |
| `QueryIntGameWEStats` | Ask for preformatted text (used for the spectator display). |
| `DisplayGameWEStatsMenu` | Shows a gameWE menu. |
| `gameWEStatsColorEntities` | Replaces the color tags in a string. |

Forwards: `onGameWEStatsRank`, `onGameWEStatsPublicCommand`, `onGameWEStatsTop10`,
`onGameWEStatsNext`.

The data comes from `gamewe_raw_message`, which the collector sends
(`playerinfo`, `top10`, `next`, `spectatorinfo`).

The plugin also registers the library `gameme`, the gameME native names
(`QueryGameMEStats`, ...) and the gameME forwards (`onGameMEStatsRank`, ...),
so plugins compiled against `gameme.inc` keep working.

## Migrating from the gameME plugin

- Remove `gameme.smx` and `translations/gameme.phrases.txt`. Do not run both plugins
  at the same time: both handle the `gameme_*` commands and log the same events,
  so players would get every message twice.
- The ConVars are renamed from `gameme_*` to `gamewe_*`. Copy your values from
  `cfg/sourcemod/gameme.cfg` or `server.cfg` into `cfg/sourcemod/gamewe.cfg`.
  `gameme_webpage` is gone.
- Server commands, natives and forwards work with both prefixes. Nothing to change.
- Log lines are the same as before.

## Building

You need `spcomp` from SourceMod 1.12 or newer.

```bash
make build      # build/stage/addons/sourcemod/plugins/gamewe.smx
make package    # dist/gamewe-sourcemod-<version>.tar.gz, .zip and .sha256
```

If `spcomp` is not in `PATH`, use `make SPCOMP=/path/to/spcomp`. To add another
include folder, use `SM_INCLUDE=/path/to/include`. The version comes from the git
tag (`v1.2.3`) or the `VERSION` file. Warnings are treated as errors.

The GitHub workflow `.github/workflows/build.yml` builds the plugin with
SourceMod 1.12 and 1.13 for every push to `main` (or when started by hand) and
keeps the packages as a workflow artifact.

### Releases

Releases are made by [semantic-release](https://semantic-release.gitbook.io/)
(`.releaserc.json`) in the same workflow; nobody tags by hand. To make a
release, push commits written as [Conventional Commits](https://www.conventionalcommits.org/)
to `main`. semantic-release reads the commits since the last tag and decides
the next version:

| Commit | Release |
|---|---|
| `feat: ...` | minor (0.1.0 → 0.2.0) |
| `fix: ...` (also `fix(security): ...`), `perf: ...` | patch (0.1.0 → 0.1.1) |
| `feat!: ...`, `fix!: ...` or a `BREAKING CHANGE:` footer | major (0.1.0 → 1.0.0) |
| `docs`, `chore`, `ci`, `build`, `test`, `refactor`, `style` | no release |

For a release it writes `VERSION`, `GAMEWE_PLUGIN_VERSION` in
`gamewe.sp`/`gamewe_messages.sp` and `CHANGELOG.md`, commits them as
`chore(release): vX.Y.Z [skip ci]`, tags `vX.Y.Z` and creates the GitHub
release. The workflow then builds that tag with SourceMod 1.12 and uploads the
packages (`.tar.gz`, `.zip`, `.sha256`) to the release. Never edit the version
files or `CHANGELOG.md` by hand.

## License

gameWE is free software under the **GNU General Public License version 3 or later**,
see [LICENSE](LICENSE).

It is based on the gameME plugin, Copyright (C) 2007-2020 TTS Oetzel & Goerz GmbH,
published under the GPL version 2 or later. It contains the SuperLogs code by
Nicholas Hastings (psychonic) and Insurgency logging based on work by FZFalzar
and Jared Ballou, also under the GPL. The gameME changelog up to 5.0.0 is kept in
[docs/gameme-CHANGELOG.txt](docs/gameme-CHANGELOG.txt).
