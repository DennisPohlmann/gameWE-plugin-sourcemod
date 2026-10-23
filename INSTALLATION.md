# Installing the gameWE SourceMod plugin

The plugin runs on each Source game server and works together with the
[gameWE collector](https://github.com/DennisPohlmann/gameWE-collector): it writes
extra log lines for the collector and executes the collector's replies
(private chat, menus) that arrive over RCON. It has no database access of its own.

Placeholders below: `203.0.113.5` is the collector host, `198.51.100.7:27015`
the game server, `change-me` your RCON password.

## Requirements

- A Source game server of a [supported game](#supported-games). **Not CS2**:
  SourceMod does not run on Counter-Strike 2.
- [Metamod:Source](https://www.sourcemm.net/) and [SourceMod](https://www.sourcemod.net/)
  **1.12 or newer** (the release is built with 1.12, checked with 1.13).
  SDKHooks, ClientPrefs and the game extensions (cstrike, tf2) ship with
  SourceMod and are used when present.
- A gameWE collector that receives the server's logs and has the server in
  `hlstats_Servers` with its RCON password ([pairing](#pairing-with-the-collector)).

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

The server log shows the result after the start: `gameWE Game Detection: ...`.

## Install

1. Download `gamewe-sourcemod-<version>.tar.gz` (or `.zip`) and its `.sha256`
   from the releases and check it: `sha256sum -c gamewe-sourcemod-<version>.sha256`.
2. Extract it into the game folder, the folder that contains `addons/`
   (`cstrike/`, `csgo/`, `tf/`, `dod/`, `hl2mp/`, `left4dead2/`, ...):

   ```bash
   tar -xzf gamewe-sourcemod-0.1.0.tar.gz -C /path/to/server/cstrike
   ```

   It contains:

   ```
   addons/sourcemod/plugins/gamewe.smx                     the plugin
   addons/sourcemod/plugins/disabled/gamewe_messages.smx   example for plugin developers (not loaded)
   addons/sourcemod/translations/gamewe.phrases.txt        English
   addons/sourcemod/translations/<lang>/gamewe.phrases.txt da, de, es, fr, pl, pt, ru
   addons/sourcemod/scripting/gamewe.sp, gamewe_messages.sp, include/gamewe.inc   source (optional, not needed to run)
   README.md, CHANGELOG.md, LICENSE                        (can be deleted from the game folder)
   ```

3. Remove the original gameME plugin if it is installed
   (`addons/sourcemod/plugins/gameme.smx`, `translations/gameme.phrases.txt`):
   both would answer every command twice.
4. Restart the server or change the map, then check in the server console:

   ```
   sm plugins list            // "gameWE" is listed
   gamewe_plugin_version      // the version
   ```

On the first start SourceMod writes `cfg/sourcemod/gamewe.cfg` with all
settings and their defaults. It never changes the file afterwards.

## Game server setup

In `server.cfg` (the collector's address and UDP port, default 41337):

```
log on
mp_logdetail 3
logaddress_add 203.0.113.5:41337     // CS:GO: logaddress_add "203.0.113.5:41337"
rcon_password "change-me"            // the same password as in the collector's hlstats_Servers
gamewe_protect_address "203.0.113.5:41337"   // optional, see below
```

`gamewe_protect_address` keeps the collector registered: the plugin adds the
address again after `logaddress_del` / `logaddress_delall` and turns logging
back on after `log off`. The collector also re-registers itself over RCON every
minute.

## Settings (`cfg/sourcemod/gamewe.cfg`)

| ConVar | Default | Meaning |
|--------|---------|---------|
| `gamewe_chat_cooldown` | `1.0` | Seconds between two gameWE commands of one player that are passed to the collector (silent `/` commands and menu entries), 0-30, `0` = off |
| `gamewe_block_commands_values` | | More commands that are silent when typed with `/`, separated by spaces; `clear` removes all, including the defaults |
| `gamewe_message_prefix` | | Text in front of every gameWE message (color tags allowed); `gamewe_message_prefix_clear` empties it |
| `gamewe_protect_address` | | `ip:port` of the collector to keep registered |
| `gamewe_log_locations` | `1` | Log player positions with kills and actions (heatmaps) |
| `gamewe_display_spectatorinfo` | `0` | CS:S, CS:GO: show the stats of the spectated player |
| `gamewe_damage_display` | `0` | Damage summary on death: `0` off, `1` menu, `2` chat |
| `gamewe_plugin_version` | | Read only: the plugin version |

`/rank` is always silent (the plugin logs it), `!rank` and `rank` stay visible
(the engine logs them); the collector answers both privately. Changes in
`gamewe.cfg` apply after `exec sourcemod/gamewe.cfg`, a map change or a reload.

## Pairing with the collector

- The server must be a row of the collector's `hlstats_Servers`: IP, game port,
  game code and the **RCON password** of `server.cfg`. In the web admin, or on
  the collector host:

  ```bash
  gamewe server add 198.51.100.7:27015 -game css -name "My CS:S server" -rcon-password-file /root/rcon.txt
  ```

- The collector sends its replies as `gamewe_psay`, `gamewe_msay`,
  `gamewe_raw_message`, ... over RCON (TCP, the game port). The plugin
  accepts them with the `gamewe_` and the `gameme_` prefix. The collector
  setting `gamewe_command_prefix` (in `hlstats_Options`, default `gamewe`)
  stays `gamewe` for this plugin; `gameme` is only for servers that still run
  the original gameME plugin.
- Test: type `!rank` in game. The collector's journal shows the `say` line;
  `gamewe check` on the collector host lists servers without an RCON password.

## Reload

```
sm plugins reload gamewe
```

or change the map. After replacing `gamewe.smx` a reload is enough; players
keep playing.

## Upgrade

1. Read the release's entry in `CHANGELOG.md`.
2. Extract the new archive over the old files (as in Install, step 2).
3. `sm plugins reload gamewe` or change the map.

`cfg/sourcemod/gamewe.cfg` is kept, and new settings are **not** added to it:
they work with their default. To change one, add its line to `gamewe.cfg`
yourself, or delete the file once to have it written again with all settings
(then set your values again).

## Uninstall

Delete `addons/sourcemod/plugins/gamewe.smx`,
`addons/sourcemod/plugins/disabled/gamewe_messages.smx`,
`addons/sourcemod/translations/gamewe.phrases.txt`, the
`translations/<lang>/gamewe.phrases.txt` files and `cfg/sourcemod/gamewe.cfg`,
then `sm plugins unload gamewe` or change the map.
