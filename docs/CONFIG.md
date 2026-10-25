# gameWE - SourceMod plugin: configuration

All settings are ConVars in `cfg/sourcemod/gamewe.cfg`. SourceMod writes the
file with all settings and their defaults on the first start and never changes
it afterwards: a setting added in a later version works with its default until
you add its line yourself (or delete the file once to have it written again).
The same holds for the comments above each line: the allowed range
(`Minimum`/`Maximum`) of a setting only shows up in a file written by a
version that has it, so delete the file once after an update to get the
current descriptions and ranges. Values outside the range are clamped.

## ConVars

| ConVar | Default | Meaning |
|--------|---------|---------|
| `gamewe_chat_cooldown` | `1.0` | Seconds between two gameWE commands of one player that are passed to the collector (silent `/` commands and menu entries), 0-30, `0` = off |
| `gamewe_block_commands_values` | | More commands that are silent when typed with `/`, separated by spaces; `clear` removes all, including the defaults |
| `gamewe_message_prefix` | | Text in front of every gameWE chat message, also in place of the `[gameWE]` of the collector's answers; up to 63 characters, [color tags](#color-tags) allowed, e.g. `"{lightgreen}[MyServer]{default}"`. Empty: the plugin's messages have no prefix and the collector's keep `[gameWE]`. `gamewe_message_prefix_clear` empties it |
| `gamewe_protect_address` | | `ip:port` of the collector to keep registered |
| `gamewe_log_locations` | `1` | Log player positions with kills and actions (heatmaps): `0` off, `1` on |
| `gamewe_display_spectatorinfo` | `0` | CS:S, CS:GO: default for players: show the stats of the spectated player (`0` off, `1` on); each player can override it in the settings menu |
| `gamewe_display_spectatorinfo_allow` | `1` | `0` switches the spectator info off for everyone; players cannot enable it then |
| `gamewe_damage_display` | `0` | CS:S, CS:GO, DoD:S: default for players: damage summary on death and at round end (`0` off, `1` menu, `2` chat); each player can override it in the settings menu |
| `gamewe_damage_display_allow` | `1` | `0` switches the damage display (and its damage tracking) off for everyone; players cannot enable it then |
| `gamewe_plugin_version` | | Read only: the plugin version |

`/rank` is always silent (the plugin logs it), `!rank` and `rank` stay visible
(the engine logs them); the collector answers both privately. Changes in
`gamewe.cfg` apply after `exec sourcemod/gamewe.cfg`, a map change or a reload.

## Per-player settings

The displays a player sees are chosen by each player in the gameWE settings
menu (see [USAGE.md](USAGE.md#menu)): the damage display (off, menu, chat) and
the spectator info (off, on), each also "server default". `gamewe_damage_display`
and `gamewe_display_spectatorinfo` are only the default for players who have
not chosen (or chose "server default"), so `0` means "off by default, players
can switch it on". To forbid a display completely, set its `*_allow` ConVar to
`0`; the menu then shows the entry as disabled.

The players also choose the collector's console events and global chat
events (`gamewe_display 0|1`, `gamewe_chat 0|1`, on by default; the
collector's `gamewe_console_events` / `gamewe_global_chat` decide whether
there are any), their auto commands (`gamewe_auto`) and their language
(`gamewe_lang`), see [USAGE.md](USAGE.md#settings-the-plugin-keeps).

The choices are saved with ClientPrefs cookies, all private:
`gamewe_damage_display` and `gamewe_spectatorinfo` (value `0`/`1`/`2`; empty
means server default), `gamewe_display` and `gamewe_chat` (`0` off, `1` or
empty on), `gamewe_auto` (`<start>,<end>,<kill>`, each a command of the
allowed list or empty) and `gamewe_lang` (a SourceMod language code, empty =
the game's language), so they are kept across maps and visits. Without ClientPrefs the menu still
works, but a choice is lost on reconnect or map change. Logging, the collector
address, blocked commands, the message prefix and the chat cooldown stay server
settings.

## Color tags

`gamewe_message_prefix` (and messages sent with `colored 1`) may contain color
tags. Upper and lower case do not matter.

| Tag | CS:GO | CS:S, DoD:S, HL2:DM, TF2 | Other games |
|-----|-------|--------------------------|-------------|
| `{default}` | default | default | default |
| `{teamcolor}`, `{team}` | team color | team color | team color |
| `{green}` | green | green | green |
| `{lightgreen}` | light green | light green (`#99FF99`) | team color |
| `{olive}` | olive | olive | olive |
| `{red}`, `{lightred}`, `{darkred}` | red, light red, dark red | `#FF4040`, `#FF8080`, `#B00000` | removed |
| `{blue}`, `{lightblue}` | blue, light blue | `#4D7AFF`, `#99CCFF` | removed |
| `{grey}`, `{gray}` | grey | `#CCCCCC` | removed |
| `{yellow}`, `{orange}`, `{purple}`, `{lime}` | yellow, orange, purple, lime | `#FFD700`, `#FFA500`, `#B070FF`, `#00FF00` | removed |

The gameME tags `x01`, `x03`, `x04`, `x05`, `x07` and `x08` work as well. End
the prefix with `{default}` so the message after it has the normal color; the
plugin adds a default color after the prefix of the collector's answers itself.

## Server commands

- `gamewe_message_prefix_clear` empties `gamewe_message_prefix`.

## Protecting the collector address

To stop admins or other plugins from removing the collector address by
accident, set `gamewe_protect_address` to the collector's `ip:port`. The plugin
then adds it again after `logaddress_del` / `logaddress_delall`, and turns
logging back on after `log off`. The collector also re-registers itself over
RCON every minute.
