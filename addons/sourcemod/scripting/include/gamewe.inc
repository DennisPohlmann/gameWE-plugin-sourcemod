/**
 * gameWE - SourceMod plugin include
 *
 * Natives and forwards of the gameWE plugin (gamewe.smx). Other plugins
 * can use them to query player statistics from the gameWE collector.
 *
 * Fork of gameme.inc of the gameME Plugin
 * (https://github.com/gamemedev/plugin-sourcemod),
 * Copyright (C) 2007-2020 TTS Oetzel & Goerz GmbH.
 * Copyright (C) 2026 gameWE contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#if defined _gamewe_included_
  #endinput
#endif
#define _gamewe_included_


// raw message handling
#define RAW_MESSAGE_RANK           1
#define RAW_MESSAGE_PLACE          2
#define RAW_MESSAGE_KDEATH         3
#define RAW_MESSAGE_SESSION_DATA   4
#define RAW_MESSAGE_TOP10          5
#define RAW_MESSAGE_NEXT           6

// callbacks
#define RAW_MESSAGE_CALLBACK_PLAYER  101
#define RAW_MESSAGE_CALLBACK_TOP10   102
#define RAW_MESSAGE_CALLBACK_NEXT    103


/**
 * Called when the collector answers a rank request of a player (!rank).
 * The datapack layout is documented in gamewe_messages.sp.
 */
forward Action onGameWEStatsRank(int command, int client, char[] message_prefix, Handle &datapack);

/**
 * Called when the collector answers a public command (!place, !kdeath, !session).
 */
forward Action onGameWEStatsPublicCommand(int command, int client, char[] message_prefix, Handle &datapack);

/**
 * Called when the collector sends the top 10 players.
 */
forward Action onGameWEStatsTop10(int command, int client, char[] message_prefix, Handle &datapack);

/**
 * Called when the collector sends the players ranked next to a player.
 */
forward Action onGameWEStatsNext(int command, int client, char[] message_prefix, Handle &datapack);


typedef gameWEStatsCallback = function Action (int command, int payload, int client, Handle datapack);

/**
 * Query gameWE statistics of a client.
 *
 * @param request       Request type (only "playerinfo" available).
 * @param client        Client index.
 * @param callback      Callback function.
 * @param payload       Payload to tell queries apart.
 */
native void QueryGameWEStats(const char[] request, int client, gameWEStatsCallback callback, int payload = 0);


typedef gameWEStatsTop10Callback = function Action (int command, int payload, Handle datapack);

/**
 * Query the top 10 players.
 *
 * @param request       Request type (only "top10" available).
 * @param client        Client index, or -1 for a query without a player.
 * @param callback      Callback function.
 * @param payload       Payload to tell queries apart.
 */
native void QueryGameWEStatsTop10(const char[] request, int client, gameWEStatsTop10Callback callback, int payload = 0);


typedef gameWEStatsNextCallback = function Action (int command, int payload, int client, Handle datapack);

/**
 * Query the players ranked next to a client.
 *
 * @param request       Request type (only "next" available).
 * @param client        Client index.
 * @param callback      Callback function.
 * @param payload       Payload to tell queries apart.
 */
native void QueryGameWEStatsNext(const char[] request, int client, gameWEStatsNextCallback callback, int payload = 0);


typedef gameWEStatsIntCallback = function Action (int command, int payload, int caller[MAXPLAYERS + 1], int target[MAXPLAYERS + 1], char[] message_prefix, char[] message);

/**
 * Query internal (preformatted) gameWE statistics.
 *
 * @param request       Request type.
 * @param client        Client index.
 * @param callback      Callback function.
 * @param payload       Payload to tell queries apart.
 * @param limit         1 to remove the callback after the first answer.
 */
native void QueryIntGameWEStats(const char[] request, int client, gameWEStatsIntCallback callback, int payload = 0, int limit = 0);


/**
 * Display the internal gameWE menu.
 *
 * @param client        The client index the menu is displayed to.
 * @param time          How long the menu is displayed, in seconds.
 * @param message       The menu text, lines separated by \n.
 * @param need_handler  1 if the menu needs a handler.
 */
native void DisplayGameWEStatsMenu(int client, int time, char[] message, int need_handler);


/**
 * Replace the color tags in a message.
 *
 * @param message       String.
 */
native void gameWEStatsColorEntities(char[] message);


public SharedPlugin __pl_gamewe =
{
	name = "gamewe",
	file = "gamewe.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_gamewe_SetNTVOptional()
{
	MarkNativeAsOptional("QueryGameWEStats");
	MarkNativeAsOptional("QueryGameWEStatsTop10");
	MarkNativeAsOptional("QueryGameWEStatsNext");
	MarkNativeAsOptional("QueryIntGameWEStats");
	MarkNativeAsOptional("DisplayGameWEStatsMenu");
	MarkNativeAsOptional("gameWEStatsColorEntities");
}
#endif
