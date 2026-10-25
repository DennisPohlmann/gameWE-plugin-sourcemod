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

`rank`, `skill`, `points`, `place`, `session`, `sdata`, `session_data`, `kpd`,
`kdratio`, `kdeath`, `next`, `load`, `status`, `servers`, `top5`, `top10`, `top20`,
`maps`, `map_stats`, `clans`, `cheaters`, `statsme`, `weapons`, `weapon`, `action`,
`actions`, `accuracy`, `targets`, `target`, `kills`, `kill`, `player_kills`, `cmd`,
`cmds`, `commands`, `help`, `gstats`, `global_stats`, and the settings commands
`gamewe_atb 0|1`, `gamewe_hideranking [0|1]`, `gamewe_reset [0|1]`. The
`gameme_*` spellings are hidden too.

The collector answers gameME's command list (its USAGE.md lists them): the
stats in chat or a panel (`!rank`, `!kpd`, `!session`, `!next`, `!top5`,
`!top10`, `!top20`, and `!place`, `!kdeath`, `!session_data` to everybody),
web pages in the in-game browser (`!statsme`, `!status`, `!servers`, `!load`,
`!clans`, `!cheaters`, `!maps`, `!weapons`, `!accuracy`, `!targets`, `!kills`,
`!actions`; on CS:GO the address comes as a chat line), `!hideranking`,
`!settings`, `!gamewe_reset` (if the server allows it) and `!help`.
`gstats`, `global_stats` and `gamewe_atb` are hidden but not answered.

### Settings the plugin keeps

These are answered by the plugin itself (in the player's language, with the
message prefix) and saved per player in ClientPrefs cookies
([CONFIG.md](CONFIG.md#per-player-settings)); the collector does not see them
as commands. With `/` they are hidden from chat, with `!` or without a prefix
they stay visible. The `gameme_*` spellings work as well. A player can use
them at most once per `gamewe_chat_cooldown`.

| Command | Effect |
|---------|--------|
| `gamewe_display 0\|1` | console events off or on (default on): the collector's points of your kills and actions in the console, when the server has `gamewe_console_events` on (collector setting) |
| `gamewe_chat 0\|1` | global chat events off or on (default on): the collector's announcements of player and team actions with points, when the server has `gamewe_global_chat` on |
| `gamewe_auto start\|end\|kill <command>` | a command the plugin sends for you at round start (`start`), round end (`end`) or when you die (`kill`, as gameME), as if you typed `/<command>`. Only the stats commands `rank`, `skill`, `points`, `kpd`, `kdratio`, `session`, `sdata`, `next`, `top5`, `top10`, `top20`, `statsme`; `gamewe_auto start clear` removes one, `gamewe_auto clear` all, `gamewe_auto` alone lists them. The chat cooldown (`gamewe_chat_cooldown`) applies |
| `gamewe_lang en\|de\|ru\|es\|fr\|pt\|nl\|dk\|pl` | the language of the plugin's menus and messages and of the collector's answers. The plugin switches the player's SourceMod language (`dk` is Danish, `da` in SourceMod) and logs `setup "gamewe_lang" (value "de")` for the collector, on every connect too. Without a choice the game's language (`cl_language`) is used |

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
- "Console events" and "Global chat": on, off (`gamewe_display`,
  `gamewe_chat` above). The main menu entry "Chat-Events" switches the same
  two settings.

Selecting an entry switches to the next value and shows the menu again.
"Server default" follows `gamewe_damage_display` / `gamewe_display_spectatorinfo`
(the value is shown in brackets); an entry the server forbids
(`*_allow 0`) is shown as disabled. The choices are saved in ClientPrefs
cookies (see [CONFIG.md](CONFIG.md#per-player-settings)). The gameME menu
entries "Auto Ranking", "Toggle Ranking Display" and "Reset Statistics" are
not in the menu: the chat commands `gamewe_auto`, `gamewe_hideranking` and
`gamewe_reset` do that (there are no commands to set profile data such as
name, email or homepage).
