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
| `gamewe_display_spectatorinfo` | `0` | CS:S, CS:GO: show the stats of the spectated player |
| `gamewe_damage_display` | `0` | Damage summary on death: `0` off, `1` menu, `2` chat |
| `gamewe_plugin_version` | | Read only: the plugin version |

`/rank` is always silent (the plugin logs it), `!rank` and `rank` stay visible
(the engine logs them); the collector answers both privately. Changes in
`gamewe.cfg` apply after `exec sourcemod/gamewe.cfg`, a map change or a reload.

## Server commands

- `gamewe_message_prefix_clear` empties `gamewe_message_prefix`.

## Protecting the collector address

To stop admins or other plugins from removing the collector address by
accident, set `gamewe_protect_address` to the collector's `ip:port`. The plugin
then adds it again after `logaddress_del` / `logaddress_delall`, and turns
logging back on after `log off`. The collector also re-registers itself over
RCON every minute.
