# gameWE - SourceMod plugin: interface

How the plugin talks to the [gameWE collector](https://github.com/DennisPohlmann/gameWE-collector)
(log lines and the server commands the collector sends over RCON) and to other
SourceMod plugins (natives and forwards). The collector's side is described in
its [INTERFACE.md](https://github.com/DennisPohlmann/gameWE-collector/blob/main/docs/INTERFACE.md).

## Log lines

The plugin writes standard HL log lines. The ones the collector uses most:

```
"Name<2><STEAM_1:0:123><CT>" triggered "weaponstats" (weapon "ak47") (shots "14") (hits "6") (kills "1") (headshots "1") (tks "0") (damage "412") (deaths "0")
"Name<2><STEAM_1:0:123><CT>" triggered "weaponstats2" (weapon "ak47") (head "1") (chest "3") (stomach "1") (leftarm "0") (rightarm "1") (leftleg "0") (rightleg "0")
"Name<2><STEAM_1:0:123><CT>" triggered "mvp"
"Name<2><STEAM_1:0:123><CT>" say "!rank"
"Name<2><STEAM_1:0:123><CT>" requested "hideranking" (value "0")
"Name<2><STEAM_1:0:123><CT>" setup "cl_language" (value "german")
"Name<2><STEAM_1:0:123><CT>" setup "gamewe_lang" (value "de")
```

`weaponstats` lines are written when a player dies, disconnects or the round
ends (on L4D, L4D2 and Insurgency also every 180 seconds). `weaponstats2` follows
when the weapon hit something. TF2 writes `weaponstats` without `weaponstats2`.
`requested "hideranking"` asks the collector for the player's ranking state
when the settings menu opens and the state is not known yet; the collector
answers with `gamewe_hidestate`. `setup "gamewe_lang"` is the player's
language choice (`gamewe_lang`: `en`, `de`, `ru`, `es`, `fr`, `pt`, `nl`, `da`,
`pl`), logged when the player chooses and whenever the player is put in the
server; `setup "cl_language"` is the game's language, queried on connect. The
collector answers in that language.

## Server commands

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
| `gamewe_hidestate <userid> <hideranking>` | The player's ranking state for the settings menu: `0` shown, `1` hidden by an admin, `2` banned, `3` hidden by the player. Sent by the collector after `!hideranking` / `!settings` and for `requested "hideranking"`. |
| `gamewe_console_event <userid[,userid...]> "<message>"` | A console line for the listed players whose console events are on (`gamewe_display`): the collector's points of kills and actions. |
| `gamewe_chat_event <userid[,userid...]> "<message>"` | A chat line (with the message prefix) for the listed players whose global chat is on (`gamewe_chat`): the collector's announcements of actions with points. |
| `gamewe_raw_message <type> <query_id> <userid> ...` | Data for other plugins, see below. |

Every command also exists with the `gameme_` prefix, so a collector or script
written for gameME works unchanged.

With `colored 1` the plugin replaces the tags `x01`, `x03`, `x04`, `x05`, `x07` and
`x08` in the message by chat color codes, as the gameME plugin did. `x01` is the
default color, `x03` the team color and `x04` green on most games. Which colors a
game can show depends on the game. The color tags of `gamewe_message_prefix`
(see [CONFIG.md](CONFIG.md#color-tags)) work there as well.

The collector starts every `gamewe_psay` chat line with `[gameWE]`. When
`gamewe_message_prefix` is set, the plugin puts the prefix in its place, so
the collector's answers (`!rank`, `!hideranking`, `!settings`, ...) show the
server's prefix like the plugin's own messages.

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
