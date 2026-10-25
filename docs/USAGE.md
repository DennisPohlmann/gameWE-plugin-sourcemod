# gameWE - SourceMod plugin: usage

What players can type in game and what the gameWE menu offers. The answers
come from the [gameWE collector](https://github.com/DennisPohlmann/gameWE-collector);
the plugin hides the commands from chat, logs them and shows the replies.

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

## Menu

`!gamewe` or `!gamewe_menu` opens the gameWE menu (also in the SourceMod
settings menu `!settings`, when ClientPrefs is loaded). The menu entries send the
matching chat command for the player, for example `/rank` or `/top10`. The
menu entry "Settings" (also `!gamewe_settings`, the console command
`sm_gamewe_settings`, and "gameWE Settings" in SourceMod's `!settings` menu) has
one ranking entry that fits the player's current state: "Hide me in the
ranking" when the player is shown, "Show me in the ranking" when the player hid
themselves, and a disabled "Hidden from the ranking" when an admin or a ban hid
the player. Selecting it sends `/gamewe_hideranking 1` or `/gamewe_hideranking 0`
for the player; the collector answers in chat and with the new state, and the
menu opens again with the switched entry. The plugin has no database: it gets
the state from the collector (`gamewe_hidestate`, asked for with
`requested "hideranking"` when the menu opens the first time). As long as no
state has arrived (a collector without this command), the entry is "Hide or show
me in the ranking" and switches (`/gamewe_hideranking`).

The settings menu also has the player's own display settings, with their
current value:

- "Damage display" (CS:S, CS:GO, DoD:S): server default, off, menu, chat. With
  "menu" the summary of the round (attackers, victims, killer) is shown as a
  panel on death and at round end; with "chat" the killer, the damage and the
  killer's health left are shown in chat on death.
- "Spectator info" (CS:S, CS:GO): server default, off, on. Shows the stats of
  the spectated player as a key hint.

Selecting an entry switches to the next value and shows the menu again.
"Server default" follows `gamewe_damage_display` / `gamewe_display_spectatorinfo`
(the value is shown in brackets); an entry the server forbids
(`*_allow 0`) is shown as disabled. The choices are saved in ClientPrefs
cookies (see [CONFIG.md](CONFIG.md#per-player-settings)). The gameME entries "Auto Ranking", "Toggle Ranking Display" and
"Reset Statistics" are gone: the collector has no such commands (players cannot hide
themselves from the rankings or reset their statistics, and there are no
commands to set profile data such as name, email or homepage).
