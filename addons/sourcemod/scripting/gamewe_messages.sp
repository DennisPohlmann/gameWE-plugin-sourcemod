/**
 * gameWE - raw message example plugin
 *
 * Shows how another plugin reads the statistics that the gameWE collector
 * sends to the game server (natives and forwards from gamewe.inc).
 *
 * Fork of gameme_messages.sp of the gameME Plugin
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

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <gamewe>


// plugin information
#if !defined GAMEWE_PLUGIN_VERSION
#define GAMEWE_PLUGIN_VERSION "0.3.0"
#endif
public Plugin myinfo = {
	name = "gameWE Raw Messages Example",
	author = "gameWE contributors, based on gameME by TTS Oetzel & Goerz GmbH",
	description = "Example for the gameWE raw message interface",
	version = GAMEWE_PLUGIN_VERSION,
	url = ""
};


/* Example to define query contants to be able to distinct gameWE Stats queries. The
 * payload is given as cell on query function call
 */

#define QUERY_TYPE_OTHER				0
#define QUERY_TYPE_ONCLIENTPUTINSERVER	1


public void OnPluginStart()
{
	LogToGame("gameWE Raw Messages Example Plugin %s", GAMEWE_PLUGIN_VERSION);

	QueryGameWEStatsTop10("top10", -1, QuerygameWEStatsTop10Callback);
}


public void OnClientPutInServer(int client)
{
	// example on how to retrieve data from gameWE Stats if player put in server
	if (client > 0) {
		if (!IsFakeClient(client)) {
			QueryGameWEStats("playerinfo", client, QuerygameWEStatsCallback, QUERY_TYPE_ONCLIENTPUTINSERVER);
			QueryGameWEStatsNext("next", client, QuerygameWEStatsNextCallback);
		}
	}
}


public Action QuerygameWEStatsCallback(int command, int payload, int client, Handle datapack)
{
	if ((client > 0) && (command == RAW_MESSAGE_CALLBACK_PLAYER)) {

		Handle data = CloneHandle(datapack);
		ResetPack(data);

		// total values
		int rank            = ReadPackCell(data);
		ReadPackCell(data); // players
		int skill           = ReadPackCell(data);
		ReadPackCell(data); // kills
		ReadPackCell(data); // deaths
		ReadPackFloat(data); // kpd
		ReadPackCell(data); // suicides
		ReadPackCell(data); // headshots
		ReadPackFloat(data); // hpk
		ReadPackFloat(data); // accuracy
		ReadPackCell(data); // connection_time
		ReadPackCell(data); // kill_assists
		ReadPackCell(data); // kills_assisted
		ReadPackCell(data); // points_healed
		ReadPackCell(data); // flags_captured
		ReadPackCell(data); // custom_wins
		ReadPackCell(data); // kill_streak
		ReadPackCell(data); // death_streak

		// session values
		ReadPackCell(data); // session_pos_change
		ReadPackCell(data); // session_skill_change
		ReadPackCell(data); // session_kills
		ReadPackCell(data); // session_deaths
		ReadPackFloat(data); // session_kpd
		ReadPackCell(data); // session_suicides
		ReadPackCell(data); // session_headshots
		ReadPackFloat(data); // session_hpk
		ReadPackFloat(data); // session_accuracy
		ReadPackCell(data); // session_time
		ReadPackCell(data); // session_kill_assists
		ReadPackCell(data); // session_kills_assisted
		ReadPackCell(data); // session_points_healed
		ReadPackCell(data); // session_flags_captured
		ReadPackCell(data); // session_custom_wins
		ReadPackCell(data); // session_kill_streak
		ReadPackCell(data); // session_death_streak

		char session_fav_weapon[32];
		ReadPackString(data, session_fav_weapon, 32);

		// global values
		ReadPackCell(data); // global_rank
		ReadPackCell(data); // global_players
		ReadPackCell(data); // global_skill
		ReadPackCell(data); // global_kills
		ReadPackCell(data); // global_deaths
		ReadPackFloat(data); // global_kpd
		ReadPackCell(data); // global_headshots
		ReadPackFloat(data); // global_hpk

		char player_country_code[16];
		ReadPackString(data, player_country_code, sizeof(player_country_code));

		CloseHandle(data);

		// only write this message to gameserver log if client has connected
		if (payload == QUERY_TYPE_ONCLIENTPUTINSERVER) {
			LogToGame("Player %L is on rank %d with %d points", client, rank, skill);
		}

	}
	return Plugin_Continue;
}


public Action QuerygameWEStatsTop10Callback(int command, int payload, Handle datapack)
{
	if ((command == RAW_MESSAGE_CALLBACK_TOP10)) {

		Handle data = CloneHandle(datapack);
		ResetPack(data);
		int total_count = ReadPackCell(data); // total_players

		if (total_count == -1) {

			LogToGame("-----------------------------------------------------------");
			LogToGame("No Players ranked");
			LogToGame("-----------------------------------------------------------");

		} else {

			LogToGame("-----------------------------------------------------------");
			LogToGame("Current Top10-Players");
			for (int i = 0; (i < total_count); i++) {

				int rank       = ReadPackCell(data); // rank
				int skill      = ReadPackCell(data); // skill

				char name[64]; // name
				ReadPackString(data, name, 64);

				ReadPackFloat(data); // kpd
				ReadPackFloat(data); // hpk

				LogToGame("%02d  %d  %s", rank, skill, name);
			}
			LogToGame("-----------------------------------------------------------");

		}

		CloseHandle(data);
	}
	return Plugin_Continue;
}


public Action QuerygameWEStatsNextCallback(int command, int payload, int client, Handle datapack)
{
	if ((client > 0) && (command == RAW_MESSAGE_CALLBACK_NEXT)) {

		Handle data = CloneHandle(datapack);
		ResetPack(data);
		int total_count = ReadPackCell(data); // total_players

		if (total_count == -1) {

			LogToGame("-----------------------------------------------------------");
			LogToGame("No next players available");
			LogToGame("-----------------------------------------------------------");

		} else {

			LogToGame("-----------------------------------------------------------");
			LogToGame("Next players for %L", client);

			int prev_skill = -1;
			for (int i = 0; (i < total_count); i++) {

				int rank       = ReadPackCell(data); // rank
				int skill      = ReadPackCell(data); // skill

				char name[64]; // name
				ReadPackString(data, name, 64);

				ReadPackFloat(data); // kpd
				ReadPackFloat(data); // hpk

				int diff  = -1;
				if (prev_skill > -1) {
					diff  = skill - prev_skill;
				}

				if (i == 0) {
					LogToGame("%02d  %d  -  %s", rank, skill, name);
				} else {
					LogToGame("%02d  %d  +%04d  %s", rank, skill, diff, name);
				}

				if (prev_skill == -1) {
					prev_skill = skill;
				}
			}
			LogToGame("-----------------------------------------------------------");

		}

		CloseHandle(data);
	}
	return Plugin_Continue;
}


// helper function to format timestamps
void format_time(int timestamp, char formatted_time[192]) {
	Format(formatted_time, 192, "%dd %02d:%02d:%02dh", timestamp / 86400, timestamp / 3600 % 24, timestamp / 60 % 60, timestamp % 60);
}


public Action onGameWEStatsRank(int command, int client, char[] message_prefix, Handle &datapack)
{
	if ((client > 0) && (command == RAW_MESSAGE_RANK)) {
		int time = 15;
		int need_handler = 0;

		Handle data = CloneHandle(datapack);
		ResetPack(data);

		// total values
		int rank            = ReadPackCell(data);
		int players         = ReadPackCell(data);
		int skill           = ReadPackCell(data);
		int kills           = ReadPackCell(data);
		int deaths          = ReadPackCell(data);
		float kpd      = ReadPackFloat(data);
		ReadPackCell(data); // suicides
		int headshots       = ReadPackCell(data);
		float hpk      = ReadPackFloat(data);
		float accuracy = ReadPackFloat(data);
		int connection_time = ReadPackCell(data);
		ReadPackCell(data); // kill_assists
		ReadPackCell(data); // kills_assisted
		ReadPackCell(data); // points_healed
		ReadPackCell(data); // flags_captured
		ReadPackCell(data); // custom_wins
		ReadPackCell(data); // kill_streak
		ReadPackCell(data); // death_streak

		// session values
		int session_pos_change      = ReadPackCell(data);
		int session_skill_change    = ReadPackCell(data);
		int session_kills           = ReadPackCell(data);
		int session_deaths          = ReadPackCell(data);
		float session_kpd      = ReadPackFloat(data);
		ReadPackCell(data); // session_suicides
		int session_headshots       = ReadPackCell(data);
		float session_hpk 		= ReadPackFloat(data);
		float session_accuracy = ReadPackFloat(data);
		int session_time            = ReadPackCell(data);
		ReadPackCell(data); // session_kill_assists
		ReadPackCell(data); // session_kills_assisted
		ReadPackCell(data); // session_points_healed
		ReadPackCell(data); // session_flags_captured
		ReadPackCell(data); // session_custom_wins
		ReadPackCell(data); // session_kill_streak
		ReadPackCell(data); // session_death_streak

		char session_fav_weapon[32];
		ReadPackString(data, session_fav_weapon, 32);

		// global values
		int global_rank       = ReadPackCell(data);
		int global_players    = ReadPackCell(data);
		int global_kills      = ReadPackCell(data);
		int global_deaths     = ReadPackCell(data);
		float global_kpd = ReadPackFloat(data);
		int global_headshots  = ReadPackCell(data);
		float global_hpk = ReadPackFloat(data);

		CloseHandle(data);


		char formatted_time[192];
		format_time(connection_time, formatted_time);
		char formatted_session_time[192];
		format_time(session_time, formatted_session_time);

		char message[1024];
		if (rank < 1) {
			Format(message, 1024, "Not yet available");
		} else {
			// total
			char total_message[512];
			Format(total_message, 512, "->1 - Total\\n   Position %d of %d\\n   %d Points\\n   %d:%d Frags (%.2f)\\n   %d (%.0f%%) Headshots\\n   %.0f%% Accuracy\\n   Time %s\\n\\n",
				rank, players, skill, kills, deaths, kpd, headshots, hpk * 100, accuracy * 100, formatted_time);
			strcopy(message[strlen(message)], 512, total_message);

			// session
			char session_message[512];
			Format(session_message, 512, "->2 - Session\\n   %d Positions\\n   %d Points\\n   %d:%d Frags (%.2f)\\n   %d (%.0f%%) Headshots\\n   %.0f%% Accuracy\\n   %s\\n   Time %s\\n",
				session_pos_change, session_skill_change, session_kills, session_deaths, session_kpd, session_headshots, session_hpk * 100, session_accuracy * 100, session_fav_weapon, formatted_session_time);
			strcopy(message[strlen(message)], 512, session_message);

			// global
			if (global_rank < 1) {
				char global_message[512];
				Format(global_message, 512, "%s", "->3 - Global\\n   Not yet available");
				strcopy(message[strlen(message)], 512, global_message);
			} else {
				char global_message[512];
				Format(global_message, 512, "->3 - Global\\n   Position %d of %d\\n   %d Points\\n   %d:%d Frags (%.2f)\\n%   %d (%.0f%%) Headshots",
					global_rank, global_players, global_kills, global_deaths, global_kpd, global_headshots, global_hpk * 100);
				strcopy(message[strlen(message)], 512, global_message);
			}
		}

		if ((!IsFakeClient(client)) && (IsClientInGame(client))) {
			DisplayGameWEStatsMenu(client, time, message, need_handler);
		}
	}
	return Plugin_Continue;
}


public Action onGameWEStatsPublicCommand(int command, int client, char[] message_prefix, Handle &datapack)
{
	if ((client > 0) && ((command == RAW_MESSAGE_PLACE) || (command == RAW_MESSAGE_KDEATH) || (command == RAW_MESSAGE_SESSION_DATA))) {

		Handle data = CloneHandle(datapack);
		ResetPack(data);

		// total values
		int rank            = ReadPackCell(data);
		int players         = ReadPackCell(data);
		int skill           = ReadPackCell(data);
		int kills           = ReadPackCell(data);
		int deaths          = ReadPackCell(data);
		float kpd      = ReadPackFloat(data);
		ReadPackCell(data); // suicides
		int headshots       = ReadPackCell(data);
		float hpk      = ReadPackFloat(data);
		ReadPackFloat(data); // accuracy
		ReadPackCell(data); // connection_time
		ReadPackCell(data); // kill_assists
		ReadPackCell(data); // kills_assisted
		ReadPackCell(data); // points_healed
		ReadPackCell(data); // flags_captured
		ReadPackCell(data); // custom_wins
		ReadPackCell(data); // kill_streak
		ReadPackCell(data); // death_streak

		// session values
		ReadPackCell(data); // session_pos_change
		int session_skill_change    = ReadPackCell(data);
		int session_kills           = ReadPackCell(data);
		int session_deaths          = ReadPackCell(data);
		float session_kpd      = ReadPackFloat(data);
		ReadPackCell(data); // session_suicides
		int session_headshots       = ReadPackCell(data);
		float session_hpk 		= ReadPackFloat(data);
		ReadPackFloat(data); // session_accuracy
		ReadPackCell(data); // session_time
		ReadPackCell(data); // session_kill_assists
		ReadPackCell(data); // session_kills_assisted
		ReadPackCell(data); // session_points_healed
		ReadPackCell(data); // session_flags_captured
		ReadPackCell(data); // session_custom_wins
		ReadPackCell(data); // session_kill_streak
		ReadPackCell(data); // session_death_streak

		char session_fav_weapon[32];
		ReadPackString(data, session_fav_weapon, 32);

		// global values
		ReadPackCell(data); // global_rank
		ReadPackCell(data); // global_players
		ReadPackCell(data); // global_kills
		ReadPackCell(data); // global_deaths
		ReadPackFloat(data); // global_kpd
		ReadPackCell(data); // global_headshots
		ReadPackFloat(data); // global_hpk

		CloseHandle(data);

		char client_message[192];
		switch (command) {
			case RAW_MESSAGE_PLACE:
				Format(client_message, 192, "%N is on rank %d of %d with %d points", client, rank, players, skill);
			case RAW_MESSAGE_KDEATH:
				Format(client_message, 192, "%N has %d:%d (%.2f) kills with %d (%.2f) headshots", client, kills, deaths, kpd, headshots, hpk);
			case RAW_MESSAGE_SESSION_DATA:
				Format(client_message, 192, "%N has %d:%d (%.2f) kills, %d (%.2f) headshots, %d skill change", client, session_kills, session_deaths, session_kpd, session_headshots, session_hpk, session_skill_change);
		}


		char message[192];
		if (strcmp(message_prefix, "") == 0) {
			Format(message, 192, "\x01%s", client_message);
		} else {
			gameWEStatsColorEntities(message_prefix);
			Format(message, 192, "\x04%s\x01 %s", message_prefix, client_message);
		}

		// display message
		if ((!IsFakeClient(client)) && (IsClientInGame(client))) {
			// the message holds player names: never use it as the format;
			// CS:GO ignores a color code in the first byte (leading space)
			PrintToChatAll((GetEngineVersion() == Engine_CSGO) ? " %s" : "%s", message);
		}
	}
	return Plugin_Continue;
}


public Action onGameWEStatsTop10(int command, int client, char[] message_prefix, Handle &datapack)
{
	if ((client > 0) && (command == RAW_MESSAGE_TOP10)) {
		int time = 15;
		int need_handler = 0;
		char message[1024];

		Handle data = CloneHandle(datapack);
		ResetPack(data);
		int total_count = ReadPackCell(data); // total_players

		if (total_count == -1) {

			Format(message, 1024, "->1 - Top Players\\n   Not yet available");

		} else {

			char start_message[192];
			Format(start_message, 192, "->1 - Top Players\\n");
			strcopy(message[strlen(message)], 192, start_message);

			for (int i = 0; (i < total_count); i++) {

				int rank       = ReadPackCell(data); // rank
				int skill      = ReadPackCell(data); // skill

				char name[64]; // name
				ReadPackString(data, name, 64);

				ReadPackFloat(data); // kpd
				ReadPackFloat(data); // hpk

				char entry_message[192];
				Format(entry_message, 192, "   %02d  %d  %s\\n", rank, skill, name);
				strcopy(message[strlen(message)], 192, entry_message);
			}
		}
		CloseHandle(data);

		if ((!IsFakeClient(client)) && (IsClientInGame(client))) {
			DisplayGameWEStatsMenu(client, time, message, need_handler);
		}
	}
	return Plugin_Continue;
}


public Action onGameWEStatsNext(int command, int client, char[] message_prefix, Handle &datapack)
{
	if ((client > 0) && (command == RAW_MESSAGE_NEXT)) {
		int time = 15;
		int need_handler = 0;
		char message[1024];

		Handle data = CloneHandle(datapack);
		ResetPack(data);
		int total_count = ReadPackCell(data); // total_players

		if (total_count == -1) {

			Format(message, 1024, "->1 - Next Players\\n   Not yet available");

		} else {

			char start_message[192];
			Format(start_message, 192, "->1 - Next Players\\n");
			strcopy(message[strlen(message)], 192, start_message);

			int prev_skill = -1;
			for (int i = 0; (i < total_count); i++) {

				int rank       = ReadPackCell(data); // rank
				int skill      = ReadPackCell(data); // skill

				char name[64]; // name
				ReadPackString(data, name, 64);

				ReadPackFloat(data); // kpd
				ReadPackFloat(data); // hpk

				int diff  = -1;
				if (prev_skill > -1) {
					diff  = skill - prev_skill;
				}

				char entry_message[192];
				if (i == 0) {
					Format(entry_message, 192, "   %02d  %d       -      %s\\n", rank, skill, name);
				} else {
					Format(entry_message, 192, "   %02d  %d  +%04d  %s\\n", rank, skill, diff, name);
				}
				strcopy(message[strlen(message)], 192, entry_message);

				if (prev_skill == -1) {
					prev_skill = skill;
				}
			}
		}
		CloseHandle(data);

		if ((!IsFakeClient(client)) && (IsClientInGame(client))) {
			DisplayGameWEStatsMenu(client, time, message, need_handler);
		}
	}
	return Plugin_Continue;
}
