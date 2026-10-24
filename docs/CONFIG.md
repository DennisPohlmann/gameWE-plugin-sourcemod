# gameWE - SourceMod plugin: configuration

All settings are ConVars in `cfg/sourcemod/gamewe.cfg`. SourceMod writes the
file with all settings and their defaults on the first start and never changes
it afterwards: a setting added in a later version works with its default until
you add its line yourself (or delete the file once to have it written again).

## ConVars

| ConVar | Default | Meaning |
|--------|---------|---------|
| `gamewe_chat_cooldown` | `1.0` | Seconds between two gameWE commands of one player that are passed to the collector (silent `/` commands and menu entries), 0-30, `0` = off |
| `gamewe_block_commands_values` | | More commands that are silent when typed with `/`, separated by spaces; `clear` removes all, including the defaults |
| `gamewe_message_prefix` | | Text in front of every gameWE message (color tags allowed); `gamewe_message_prefix_clear` empties it |
| `gamewe_protect_address` | | `ip:port` of the collector to keep registered |
| `gamewe_log_locations` | `1` | Log player positions with kills and actions (heatmaps) |
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

The choices are saved with ClientPrefs cookies (`gamewe_damage_display`,
`gamewe_spectatorinfo`, private, value `0`/`1`/`2`; empty means server default),
so they are kept across maps and visits. Without ClientPrefs the menu still
works, but a choice is lost on reconnect or map change. Logging, the collector
address, blocked commands, the message prefix and the chat cooldown stay server
settings.

## Server commands

- `gamewe_message_prefix_clear` empties `gamewe_message_prefix`.

## Protecting the collector address

To stop admins or other plugins from removing the collector address by
accident, set `gamewe_protect_address` to the collector's `ip:port`. The plugin
then adds it again after `logaddress_del` / `logaddress_delall`, and turns
logging back on after `log off`. The collector also re-registers itself over
RCON every minute.
