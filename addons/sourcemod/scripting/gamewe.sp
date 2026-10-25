/**
 * gameWE - SourceMod plugin
 *
 * Logs extended player statistics to the game server log for the gameWE
 * collector and shows its answers (rank, top10, session ...) in game.
 *
 * Fork of the gameME Plugin 5.0.0 (https://github.com/gamemedev/plugin-sourcemod),
 * Copyright (C) 2007-2020 TTS Oetzel & Goerz GmbH, licensed under the
 * GNU General Public License version 2 or (at your option) any later version.
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

#include <lang>
#include <sourcemod>
#include <keyvalues>
#include <menus>
#include <sdktools>
#include <gamewe>
#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <clientprefs>
#include <sdkhooks>
#include <tf2_stocks>


// plugin information
#if !defined GAMEWE_PLUGIN_VERSION
#define GAMEWE_PLUGIN_VERSION "0.2.2"
#endif
public Plugin myinfo = {
	name = "gameWE",
	author = "gameWE contributors, based on gameME by TTS Oetzel & Goerz GmbH",
	description = "Extended statistics logging and in-game messages for the gameWE collector",
	version = GAMEWE_PLUGIN_VERSION,
	url = ""
};


// mod information
#define MOD_CSS 1
#define MOD_DODS 2
#define MOD_HL2MP 3
#define MOD_TF2 4
#define MOD_L4D 5
#define MOD_L4DII 6
#define MOD_INSMOD 7
#define MOD_FF 8
#define MOD_CSP 9
#define MOD_ZPS 10
#define MOD_CSGO 11

char team_list[16][32];

// chat commands answered by the collector, also blocked with "/" and "!" in front
static const char default_blocked_commands[][] = {
	"rank", "skill", "points", "place", "session", "sdata", "kpd", "kdratio", "kdeath",
	"next", "load", "status", "top20", "top10", "top5", "maps", "map_stats", "clans",
	"cheaters", "statsme", "weapons", "weapon", "action", "actions", "accuracy",
	"targets", "target", "kills", "kill", "player_kills", "cmds", "commands", "help",
	"gstats", "global_stats", "gamewe", "gamewe_menu", "gamewe_display 0", "gamewe_display 1",
	"gamewe_atb 0", "gamewe_atb 1", "gamewe_hideranking", "gamewe_hideranking 0", "gamewe_hideranking 1",
	"hideranking", "hideranking 0", "hideranking 1", "hideranking on", "hideranking off",
	"gamewe_hideranking on", "gamewe_hideranking off", "gamewe_reset",
	"gamewe_chat 0", "gamewe_chat 1",
	"gameme", "gameme_menu", "gameme_display 0", "gameme_display 1",
	"gameme_atb 0", "gameme_atb 1", "gameme_hideranking", "gameme_reset",
	"gameme_chat 0", "gameme_chat 1"
};

// gameWE Stats
#define GAMEWE_TAG "gameWE"
#define GAMEWE_CHAT_TAG "[gameWE]" // start of the collector's chat lines
enum struct gamewe_plugin_data {
  int mod_id;
  char game_mod[32];
  StringMap blocked_commands;
  ConVar block_chat_commands_values;
  ConVar message_prefix;
  char message_prefix_value[64];
  ConVar protect_address;
  char protect_address_value[32];
  ConVar chat_cooldown;
  int protect_address_port;
  ConVar display_spectatorinfo;
  ConVar allow_spectatorinfo;
  Menu menu_main;
  Menu menu_events;
  Menu menu_settings;
  ArrayList player_color_array;
  ArrayStack message_recipients;
  ConVar enable_log_locations;
  ConVar enable_damage_display;
  ConVar allow_damage_display;
  int log_locations;
  int damage_display;
  int display_spectator;
  bool sdkhook_available;
  bool clientprefs_available;
  Handle cookie_damage_display;
  Handle cookie_spectatorinfo;
  EngineVersion engine_version;
  bool ignore_next_tag_change;
  ArrayList custom_tags;
  ConVar sv_tags;
  int server_port;
  int protobuf;
}

gamewe_plugin_data gamewe_plugin;

// game time of the last gameWE command a player sent (chat or menu), for gamewe_chat_cooldown
float gamewe_last_trigger[MAXPLAYERS + 1];


/**
 *  Per-player settings (gameWE settings menu, saved with clientprefs cookies)
 *  -1 = use the server default (cvar), otherwise the player's own choice
 */

#define SETTING_SERVER_DEFAULT  -1

#define HIDERANKING_UNKNOWN     -1

enum struct player_settings {
	int damage_display; // 0 = off, 1 = menu, 2 = chat
	int spectatorinfo;  // 0 = off, 1 = on
	int hideranking;    // from the collector (gamewe_hidestate): 0 = shown, 1 = admin, 2 = banned, 3 = hidden by the player
	bool hideranking_wait; // show the settings menu again when the state arrives
	float hideranking_asked; // game time of the last request, at most one per 5 seconds
}

player_settings gamewe_player_settings[MAXPLAYERS + 1];


/**
 *  Spectator Info Display
 */

#define SPECTATOR_TIMER_INTERVAL    0.5
#define SPECTATOR_NONE              0
#define SPECTATOR_FIRSTPERSON       4
#define SPECTATOR_3RDPERSON         5
#define SPECTATOR_FREELOOK          6
#define QUERY_TYPE_UNKNOWN          0
#define QUERY_TYPE_SPECTATOR        1001

enum struct player_display_messages {
	char smessage[255];
	int supdated;
}
player_display_messages player_messages[MAXPLAYERS + 1][MAXPLAYERS + 1];


enum struct spectator_data {
	Handle stimer;
	float srequested;
	int starget;
}


/**
 *  gameWE Stats Players
 */

enum struct gamewe_player_data {
	int prole;
	int parmor;
	int phealth;
	float ploc1;
	float ploc2;
	float ploc3;
	float pangle;
	int pmoney;
	int palive;
	char pweapon[64];
	int pgglevel;
	spectator_data pspectator;
}

gamewe_player_data gamewe_players[MAXPLAYERS + 1];


/**
 *  Hit location tracking
 */

#define HITGROUP_GENERIC   0
#define HITGROUP_HEAD      1
#define HITGROUP_CHEST     2
#define HITGROUP_STOMACH   3
#define HITGROUP_LEFTARM   4
#define HITGROUP_RIGHTARM  5
#define HITGROUP_LEFTLEG   6
#define HITGROUP_RIGHTLEG  7

#define MAX_LOG_WEAPONS    96 // must be >= the longest weapon list below (Insurgency: 88)
enum struct weapon_data {
	int wshots;
	int whits;
	int wkills;
	int wheadshots;
	int wteamkills;
	int wdamage;
	int wdeaths;
	int whealth;
	int wgeneric;
	int whead;
	int wchest;
	int wstomach;
	int wleftarm;
	int wrightarm;
	int wleftleg;
	int wrightleg;
}

weapon_data player_weapons[MAXPLAYERS + 1][MAX_LOG_WEAPONS];



/**
 *  Damage tracking
 */
enum struct damage_data {
	int dhits;
	int dkills;
	int dheadshots;
	int ddamage;
	int dkiller;
	int dhpleft;
	int dteamkill;
	int dweapon;
}

damage_data player_damage[MAXPLAYERS + 1][MAXPLAYERS + 1];


/**
 *  Misc Handling
 */

int ColorSlotArray[] = { -1, -1, -1, -1, -1, -1 };


/**
 *  Counter-Strike: Global Offensive
 */


#define MAX_CSGO_CODE_MODELS 15
static const char csgo_code_models[15][] = {"leet",
	          	            	            "phoenix",
	          	            	            "balkan",
	          	            	            "st6",
	          	            	            "gign",
	          	            	            "gsg9",
	          	            	            "anarchist",
	          	            	            "pirate",
	          	            	            "professional",
	          	            	            "separatist",
	          	            	            "fbi",
	          	            	            "idf",
	          	            	            "sas",
	          	            	            "swat",
	          	            	            "zombie"};


#define MAX_CSGO_WEAPON_COUNT 74
static const char csgo_weapon_list[][] = { "ak47", "m4a1", "deagle", "awp", "p90", "bizon", "hkp2000",
										   "glock", "nova", "galilar", "ump45", "famas", "aug", "ssg08",
										   "p250", "mp7", "elite", "sg556", "knife", "fiveseven", "sawedoff",
										   "mag7", "hegrenade", "tec9", "scar20", "mp9", "xm1014", "negev",
										   "g3sg1", "mac10", "m249", "taser", "inferno", "decoy", "flashbang",
										   "smokegrenade", "molotov", "incgrenade", "knifegg", "usp_silencer",
										   "m4a1_silencer", "bayonet", "knife_m9_bayonet", "knife_karambit",
										   "knife_flip", "knife_gut", "cz75a", "knife_tactical", "knife_butterfly",
										   "knife_falchion", "knife_push", "revolver", "knife_survival_bowie",
										   // added in gameWE 1.0.0, keep new entries at the end because indices are used below
										   "mp5sd", "tagrenade", "bumpmine", "breachcharge", "snowball",
										   "fists", "axe", "hammer", "spanner", "shield", "knife_ursus",
										   "knife_gypsy_jackknife", "knife_stiletto", "knife_widowmaker", "knife_css",
										   "knife_cord", "knife_canis", "knife_outdoor", "knife_skeleton", "knife_kukri",
										   "knife_t" };


/**
 *  Counter-Strike: Source
 */

static const char css_code_models[8][] = {"phoenix",
                                          "leet",
                                          "arctic",
                                          "guerilla",
                                          "urban",
                                          "gsg9",
                                          "sas",
                                          "gign"};

#define MAX_CSS_CT_MODELS 4
static const char css_ct_models[4][] = {"models/player/ct_urban.mdl",
                                        "models/player/ct_gsg9.mdl",
                                        "models/player/ct_sas.mdl",
                                        "models/player/ct_gign.mdl"};

#define MAX_CSS_TS_MODELS 4
static const char css_ts_models[4][] = {"models/player/t_phoenix.mdl",
                                        "models/player/t_leet.mdl",
                                        "models/player/t_arctic.mdl",
                                        "models/player/t_guerilla.mdl"};



#define MAX_CSS_WEAPON_COUNT 28
static const char css_weapon_list[][] = { "ak47", "m4a1", "awp", "deagle", "mp5navy", "aug", "p90",
                                          "famas", "galil", "scout", "g3sg1", "hegrenade", "usp",
                                          "glock", "m249", "m3", "elite", "fiveseven", "mac10",
                                          "p228", "sg550", "sg552", "tmp", "ump45", "xm1014", "knife",
                                          "smokegrenade", "flashbang" };



/**
 *  Day of Defeat: Source
 */

#define MAX_DODS_WEAPON_COUNT 26
static const char dods_weapon_list[][] = {
									 "thompson",        // 11
									 "m1carbine",       // 7
									 "k98",             // 8
									 "k98_scoped",      // 10	// 34
									 "mp40",            // 12
									 "mg42",            // 16	// 36
									 "mp44",            // 13	// 38
									 "colt",            // 3
									 "garand",          // 31	// 6
									 "spring",          // 9	// 33
									 "c96",             // 5
									 "bar",             // 14
									 "30cal",           // 15	// 35
									 "bazooka",         // 17
									 "pschreck",        // 18
									 "p38",             // 4
									 "spade",           // 2
									 "frag_ger",        // 20
									 "punch",           // 30	// 29
									 "frag_us",         // 19
									 "amerknife",       // 1
									 "riflegren_ger",   // 26
									 "riflegren_us",    // 25
									 "smoke_ger",       // 24
									 "smoke_us",        // 23
									 "dod_bomb_target"
								};


/**
 *  Left4Dead
 */

 #define MAX_L4D_WEAPON_COUNT 23
static const char l4d_weapon_list[][] = { "rifle", "autoshotgun", "pumpshotgun", "smg", "dual_pistols",
                                          "pipe_bomb", "hunting_rifle", "pistol", "prop_minigun",
                                          "tank_claw", "hunter_claw", "smoker_claw", "boomer_claw",
                                          "smg_silenced", "pistol_magnum", "rifle_ak47", "rifle_desert",
                                          "shotgun_chrome", "shotgun_spas", "sniper_military", "jockey_claw",
                                          "splitter_claw", "charger_claw"
                                        };

enum struct l4dii_plugin_data {
	int active_weapon_offset;
}

l4dii_plugin_data l4dii_data;


/**
 *  Half-Life 2: Deathmatch
 */

#define MAX_HL2MP_WEAPON_COUNT 6
static const char hl2mp_weapon_list[][] = { "crossbow_bolt", "smg1", "357", "shotgun", "ar2", "pistol" };

#define HL2MP_CROSSBOW 0

enum struct hl2mp_plugin_data {
	ConVar teamplay;
	bool teamplay_enabled;
	ArrayStack boltchecks;
	int crossbow_owner_offset;
}

hl2mp_plugin_data hl2mp_data;


enum struct hl2mp_player {
	int next_hitgroup;
	int nextbow_hitgroup;
}

hl2mp_player hl2mp_players[MAXPLAYERS + 1];


/**
 *  Zombie Panic! Source
 */

#define MAX_ZPS_WEAPON_COUNT 11
static const char zps_weapon_list[][] = { "870", "revolver", "ak47", "usp", "glock18c", "glock", "mp5", "m4", "supershorty", "winchester", "ppk"};

enum struct zps_player {
	int next_hitgroup_zps;
}

zps_player zps_players[MAXPLAYERS + 1];


/**
 *  Insurgency 2014
 */

#define MAX_INSMOD_WEAPON_COUNT 88
static const char insmod_weapon_list[][] = { "mp443", "m1asocom16", "ppsh41", "m1014", "m1garand", "steyraug", "car15", "kar98", "sig553", "sten", "thompson",
                                             "stg44", "sr25", "spectre", "spas12", "scarl", "scar", "saiga12auto", "remingtonmsr", "pecheneg", "p90", "ots33",
                                             "nova", "mp7", "mp5a4", "mk46", "mk18_m0", "mg42", "mac10", "m60", "m500", "m4a1sopmod", "m240", "m16a1", "m107",
                                             "ksg", "krissvector", "honeybadger", "hk417", "gol", "glock33", "glock18", "g36c", "g33", "famas", "f2000", "enfield",
                                             "dragunovsvu", "deagle", "combatcommander", "colt9mm", "cobra", "cm901", "asval", "ak12u", "acr", "type95", "l85a2",
                                             "ak74", "akm", "aks74u", "fal", "m14", "m16a4", "m1911", "m1a1", "m249", "m40a1", "m45", "m4a1", "m590", "m9", "makarov",
                                             "mini14", "mk18", "mosin", "mp40", "mp5", "rpk", "sks", "toz", "ump45", "galil", "galil_sar", "sterling", "model10", "l1a1",
                                             "gurkha"
                                           };

enum struct insmod_player {
	char last_role[64];
}

insmod_player insmod_players[MAXPLAYERS + 1];


/**
 *  Team Fortress 2
 */

#define TF2_UNLOCKABLE_BIT (1<<30)
#define TF2_WEAPON_PREFIX_LENGTH 10
#define TF2_MAX_LOADOUT_SLOTS 8
#define TF2_OBJ_DISPENSER 0
#define TF2_OBJ_TELEPORTER 1
#define TF2_OBJ_SENTRYGUN 2
#define TF2_OBJ_SENTRYGUN_MINI 20
#define TF2_ITEMINDEX_DEMOSHIELD 131
#define TF2_ITEMINDEX_GUNBOATS 133
#define TF2_JUMP_NONE 0
#define TF2_JUMP_ROCKET_START 1
#define TF2_JUMP_ROCKET 2
#define TF2_JUMP_STICKY 3
#define TF2_LUNCHBOX_CHOCOLATE 159
#define TF2_LUNCHBOX_STEAK 311

#define MAX_TF2_WEAPON_COUNT 28
static const char tf2_weapon_list[MAX_TF2_WEAPON_COUNT][] = {
	"ball",
	"flaregun",
	"minigun",
	"natascha",
	"pistol",
	"pistol_scout",
	"revolver",
	"ambassador",
	"scattergun",
	"force_a_nature",
	"shotgun_hwg",
	"shotgun_primary",
	"shotgun_pyro",
	"shotgun_soldier",
	"smg",
	"sniperrifle",
	"syringegun_medic",
	"blutsauger",
	"tf_projectile_arrow",
	"tf_projectile_pipe",
	"tf_projectile_pipe_remote",
	"sticky_resistance",
	"tf_projectile_rocket",
	"rocketlauncher_directhit",
	"deflect_rocket",
	"deflect_promode",
	"deflect_flare",
	"deflect_arrow"
};

#assert MAX_CSGO_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_CSS_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_DODS_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_L4D_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_HL2MP_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_ZPS_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_INSMOD_WEAPON_COUNT <= MAX_LOG_WEAPONS
#assert MAX_TF2_WEAPON_COUNT <= MAX_LOG_WEAPONS


enum struct tf2_plugin_data {
	StringMap weapons_trie;
	KeyValues items_kv;
	StringMap slots_trie;
	int stun_ball_id;
	ArrayStack stun_balls;
	ArrayStack wearables;
	int carry_offset;
	ConVar critical_hits;
	bool critical_hits_enabled;
	bool block_next_logging;
}

tf2_plugin_data tf2_data;


enum struct tf2_player {
	int player_loadout0[TF2_MAX_LOADOUT_SLOTS];
	int player_loadout1[TF2_MAX_LOADOUT_SLOTS];
	bool player_loadout_updated;
	ArrayStack object_list;
	float object_removed;
	int jump_status;
	float dalokohs;
	TFClassType player_class;
	bool carry_object;
}

tf2_player tf2_players[MAXPLAYERS + 1];


/**
 *  Raw Messages Interface
 */

// RAW_MESSAGE_* constants are defined in gamewe.inc

// internal usage
#define RAW_MESSAGE_CALLBACK_INT_CLOSE		1000
#define RAW_MESSAGE_CALLBACK_INT_SPECTATOR	1001


Handle gameWEStatsRankForward;
Handle gameWEStatsPublicCommandForward;
Handle gameWEStatsTop10Forward;
Handle gameWEStatsNextForward;
Handle gameMEStatsRankForward;
Handle gameMEStatsPublicCommandForward;
Handle gameMEStatsTop10Forward;
Handle gameMEStatsNextForward;

int global_query_id = 0;
ArrayList QueryCallbackArray;

#define CALLBACK_DATA_SIZE 7
enum struct callback_data {
	int callback_data_id;
	float callback_data_time;
	int callback_data_client;
	Handle callback_data_plugin;
	Function callback_data_function;
	int callback_data_payload;
	int callback_data_limit;
}

public void OnPluginStart()
{
	LogToGame("gameWE Plugin %s, based on the gameME Plugin, copyright (c) 2007-2020 TTS Oetzel & Goerz GmbH", GAMEWE_PLUGIN_VERSION);

	// setup default values
	gamewe_plugin.log_locations       = 1;
	gamewe_plugin.damage_display      = 1;
	gamewe_plugin.display_spectator   = 1;
	gamewe_plugin.protobuf            = 0;

	for (int i = 0; (i <= MAXPLAYERS); i++) {
		reset_player_settings(i);
	}

	LoadTranslations("gamewe.phrases");

	// block the gameWE chat commands by default
	gamewe_plugin.blocked_commands = new StringMap();
	char blocked_command[64];
	for (int i = 0; i < sizeof(default_blocked_commands); i++) {
		gamewe_plugin.blocked_commands.SetValue(default_blocked_commands[i], 1);
		Format(blocked_command, sizeof(blocked_command), "/%s", default_blocked_commands[i]);
		gamewe_plugin.blocked_commands.SetValue(blocked_command, 1);
		Format(blocked_command, sizeof(blocked_command), "!%s", default_blocked_commands[i]);
		gamewe_plugin.blocked_commands.SetValue(blocked_command, 1);
	}

	CreateConVar("gamewe_plugin_version", GAMEWE_PLUGIN_VERSION, "gameWE Plugin", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	gamewe_plugin.block_chat_commands_values = CreateConVar("gamewe_block_commands_values", "", "Define which commands should be blocked from the chat area");
	HookConVarChange(gamewe_plugin.block_chat_commands_values, OnBlockChatCommandsValuesChange);
	gamewe_plugin.message_prefix = CreateConVar("gamewe_message_prefix", "", "Prefix of every gameWE chat message, also of the collector's answers (up to 63 characters, color tags like {green} or {default} allowed)");
	HookConVarChange(gamewe_plugin.message_prefix, OnMessagePrefixChange);
	gamewe_plugin.protect_address = CreateConVar("gamewe_protect_address", "", "Address to be protected for logging/forwarding");
	HookConVarChange(gamewe_plugin.protect_address, OnProtectAddressChange);
	gamewe_plugin.chat_cooldown = CreateConVar("gamewe_chat_cooldown", "1.0", "Seconds a player has to wait between two logged gameWE commands (0-30, 0 = off)", FCVAR_NONE, true, 0.0, true, 30.0);
	gamewe_plugin.enable_log_locations = CreateConVar("gamewe_log_locations", "1", "Log player positions with kills and actions for the heatmaps (0 = off, 1 = on)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(gamewe_plugin.enable_log_locations, OnLogLocationsChange);
	gamewe_plugin.display_spectatorinfo = CreateConVar("gamewe_display_spectatorinfo", "0", "Default for players: display gameWE Stats data while spectating a player (0 = off, 1 = on); players can change it in the gameWE settings menu", FCVAR_NONE, true, 0.0, true, 1.0);
	gamewe_plugin.allow_spectatorinfo = CreateConVar("gamewe_display_spectatorinfo_allow", "1", "Allow the spectator info at all (0 = off for everyone, players cannot enable it)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(gamewe_plugin.allow_spectatorinfo, OnDisplaySpectatorinfoAllowChange);
	gamewe_plugin.enable_damage_display = CreateConVar("gamewe_damage_display", "0", "Default for players: damage summary on death and round end (0 = off, 1 = menu, 2 = chat); players can change it in the gameWE settings menu", FCVAR_NONE, true, 0.0, true, 2.0);
	gamewe_plugin.allow_damage_display = CreateConVar("gamewe_damage_display_allow", "1", "Allow the damage display at all (0 = off for everyone, no damage tracking, players cannot enable it)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(gamewe_plugin.allow_damage_display, OnDamageDisplayAllowChange);

	AutoExecConfig(true, "gamewe");

	get_server_mod();
	if (gamewe_plugin.mod_id == MOD_CSGO) {
		if (GetUserMessageType() == UM_Protobuf) {
			gamewe_plugin.protobuf = 1;
			LogToGame("gameWE Protobuf user messages detected");
		}
	}

	CreateGameWEMenuMain(gamewe_plugin.menu_main);
	CreateGameWEMenuEvents(gamewe_plugin.menu_events);
	CreateGameWEMenuSettings(gamewe_plugin.menu_settings);

	RegServerCmd("gamewe_raw_message",    gamewe_raw_message, "gameWE: <type> <query_id> <userid> <data...> - pass collector data to other plugins");
	RegServerCmd("gamewe_psay",           gamewe_psay, "gameWE: <userid[,userid...]> [colored] <message> - send a private chat message");
	RegServerCmd("gamewe_csay",           gamewe_csay, "gameWE: <message> - display a center message to all players");
	RegServerCmd("gamewe_msay",           gamewe_msay, "gameWE: <time> <userid> [handler] <message> - display a menu to a player");
	RegServerCmd("gamewe_hidestate",      gamewe_hidestate, "gameWE: <userid> <hideranking> - ranking state of a player for the settings menu");
	RegServerCmd("gamewe_tsay",           gamewe_tsay, "gameWE: <time> <userid> <message> - display a top-left message to a player");
	RegServerCmd("gamewe_hint",           gamewe_hint, "gameWE: <userid[,userid...]> <message> - display a hint message");
	RegServerCmd("gamewe_khint",          gamewe_khint, "gameWE: <userid[,userid...]> <message> - display a key hint message");
	RegServerCmd("gamewe_browse",         gamewe_browse, "gameWE: <userid> <url> - open a website in the in-game browser");
	RegServerCmd("gamewe_swap",           gamewe_swap, "gameWE: <userid> - move a player to the opposite team");
	RegServerCmd("gamewe_redirect",       gamewe_redirect, "gameWE: <time> <userid> <address> <reason> - ask a player to join another server");
	RegServerCmd("gamewe_player_action",  gamewe_player_action, "gameWE: <userid> <action> - log a player action");
	RegServerCmd("gamewe_team_action",    gamewe_team_action, "gameWE: <team> <action> [objective] - log a team action");
	RegServerCmd("gamewe_world_action",   gamewe_world_action, "gameWE: <action> - log a world action");

	// gameME command names, so collectors and scripts written for gameME keep working
	RegServerCmd("gameme_raw_message",    gamewe_raw_message);
	RegServerCmd("gameme_psay",           gamewe_psay);
	RegServerCmd("gameme_csay",           gamewe_csay);
	RegServerCmd("gameme_msay",           gamewe_msay);
	RegServerCmd("gameme_hidestate",      gamewe_hidestate);
	RegServerCmd("gameme_tsay",           gamewe_tsay);
	RegServerCmd("gameme_hint",           gamewe_hint);
	RegServerCmd("gameme_khint",          gamewe_khint);
	RegServerCmd("gameme_browse",         gamewe_browse);
	RegServerCmd("gameme_swap",           gamewe_swap);
	RegServerCmd("gameme_redirect",       gamewe_redirect);
	RegServerCmd("gameme_player_action",  gamewe_player_action);
	RegServerCmd("gameme_team_action",    gamewe_team_action);
	RegServerCmd("gameme_world_action",   gamewe_world_action);

	RegConsoleCmd("sm_gamewe_settings",  gamewe_settings_command, "gameWE: your settings (ranking, damage display, spectator info)");
	RegConsoleCmd("say",                 gamewe_block_commands);
	RegConsoleCmd("say_team",            gamewe_block_commands);

	if (gamewe_plugin.mod_id == MOD_INSMOD) {
		RegConsoleCmd("say2",            gamewe_block_commands);
	}

	RegServerCmd("log", ProtectLoggingChange);
	RegServerCmd("logaddress_del", ProtectForwardingChange);
	RegServerCmd("logaddress_delall", ProtectForwardingDelallChange);
	RegServerCmd("gamewe_message_prefix_clear", MessagePrefixClear);

	gamewe_plugin.custom_tags = new ArrayList(128);
	gamewe_plugin.sv_tags = FindConVar("sv_tags");
	gamewe_plugin.engine_version = GetEngineVersion();
	if (gamewe_plugin.sv_tags != INVALID_HANDLE) {
		AddPluginServerTag(GAMEWE_TAG);
		HookConVarChange(gamewe_plugin.sv_tags, OnTagsChange);
	}


	if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD)) {
		HookEvent("player_team", gameWE_Event_PlyTeamChange, EventHookMode_Pre);
	}

	switch (gamewe_plugin.mod_id) {
		case MOD_L4DII: {
			l4dii_data.active_weapon_offset = FindSendPropInfo("CTerrorPlayer", "m_hActiveWeapon");
		}
		case MOD_HL2MP: {
			hl2mp_data.crossbow_owner_offset = FindSendPropInfo("CCrossbowBolt", "m_hOwnerEntity");
			hl2mp_data.teamplay = FindConVar("mp_teamplay");
			if (hl2mp_data.teamplay != INVALID_HANDLE) {
				hl2mp_data.teamplay_enabled = GetConVarBool(hl2mp_data.teamplay);
				HookConVarChange(hl2mp_data.teamplay, OnTeamPlayChange);
			}
			hl2mp_data.boltchecks = new ArrayStack();
		}
		case MOD_TF2: {
			tf2_data.critical_hits = FindConVar("tf_weapon_criticals");
			HookConVarChange(tf2_data.critical_hits, OnTF2CriticalHitsChange);

			tf2_data.stun_balls = new ArrayStack();
			tf2_data.wearables = new ArrayStack();
			tf2_data.items_kv = new KeyValues("items_game");
			if (FileToKeyValues(tf2_data.items_kv, "scripts/items/items_game.txt")) {
				KvJumpToKey(tf2_data.items_kv, "items");
			}
			tf2_data.slots_trie = new StringMap();
			SetTrieValue(tf2_data.slots_trie, "primary", 0);
			SetTrieValue(tf2_data.slots_trie, "secondary", 1);
			SetTrieValue(tf2_data.slots_trie, "melee", 2);
			SetTrieValue(tf2_data.slots_trie, "pda", 3);
			SetTrieValue(tf2_data.slots_trie, "pda2", 4);
			SetTrieValue(tf2_data.slots_trie, "building", 5);
			SetTrieValue(tf2_data.slots_trie, "head", 6);
			SetTrieValue(tf2_data.slots_trie, "misc", 7);

			for (int i = 0; (i <= MAXPLAYERS); i++) {
				tf2_players[i].object_list  = new ArrayStack();
				tf2_players[i].carry_object = false;
				tf2_players[i].jump_status  = 0;
			}

			init_tf2_weapon_trie();
			AddGameLogHook(OnTF2GameLog);
		}
	}


	GetConVarString(gamewe_plugin.message_prefix, gamewe_plugin.message_prefix_value, sizeof(gamewe_plugin.message_prefix_value));
	color_gamewe_entities(gamewe_plugin.message_prefix_value, sizeof(gamewe_plugin.message_prefix_value));

	if (gamewe_plugin.protect_address != INVALID_HANDLE) {
		char protect_address_cvar_value[32];
		GetConVarString(gamewe_plugin.protect_address, protect_address_cvar_value, 32);
		if (strcmp(protect_address_cvar_value, "") != 0) {
			char ProtectSplitArray[2][16];
			int protect_split_count = ExplodeString(protect_address_cvar_value, ":", ProtectSplitArray, 2, 16);
			if (protect_split_count == 2) {
				strcopy(gamewe_plugin.protect_address_value, 32, ProtectSplitArray[0]);
				gamewe_plugin.protect_address_port = StringToInt(ProtectSplitArray[1]);
			}
		}
	}


	ConVar server_hostport = FindConVar("hostport");
	if (server_hostport != INVALID_HANDLE) {
		char temp_port[16];
		GetConVarString(server_hostport, temp_port, 16);
		gamewe_plugin.server_port = StringToInt(temp_port);
	}

	gamewe_plugin.player_color_array = new ArrayList();
	gamewe_plugin.message_recipients = new ArrayStack();
	QueryCallbackArray = new ArrayList(CALLBACK_DATA_SIZE);

	gameWEStatsRankForward = CreateGlobalForward("onGameWEStatsRank", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameWEStatsPublicCommandForward = CreateGlobalForward("onGameWEStatsPublicCommand", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameWEStatsTop10Forward = CreateGlobalForward("onGameWEStatsTop10", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameWEStatsNextForward = CreateGlobalForward("onGameWEStatsNext", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);

	// legacy forward names, so plugins written for the gameME plugin keep working
	gameMEStatsRankForward = CreateGlobalForward("onGameMEStatsRank", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameMEStatsPublicCommandForward = CreateGlobalForward("onGameMEStatsPublicCommand", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameMEStatsTop10Forward = CreateGlobalForward("onGameMEStatsTop10", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);
	gameMEStatsNextForward = CreateGlobalForward("onGameMEStatsNext", ET_Event, Param_Cell, Param_Cell, Param_String, Param_CellByRef);

}


public void OnPluginEnd()
{
	if (gamewe_plugin.player_color_array != INVALID_HANDLE) {
		CloseHandle(gamewe_plugin.player_color_array);
	}
	if (gamewe_plugin.message_recipients != INVALID_HANDLE) {
		CloseHandle(gamewe_plugin.message_recipients);
	}
	if (QueryCallbackArray != INVALID_HANDLE) {
		CloseHandle(QueryCallbackArray);
	}
	if (gamewe_plugin.blocked_commands != INVALID_HANDLE) {
		CloseHandle(gamewe_plugin.blocked_commands);
	}

	if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS)) {
		for (int i = 1; (i <= MaxClients); i++) {
			if (gamewe_players[i].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[i].pspectator.stimer);
				gamewe_players[i].pspectator.stimer = INVALID_HANDLE;
			}
		}
	}
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("gamewe");
	RegPluginLibrary("gameme");

	CreateNative("DisplayGameWEStatsMenu", native_display_menu);
	CreateNative("QueryGameWEStats", native_query_gamewe_stats);
	CreateNative("QueryGameWEStatsTop10", native_query_gamewe_stats);
	CreateNative("QueryGameWEStatsNext", native_query_gamewe_stats);
	CreateNative("QueryIntGameWEStats", native_query_gamewe_stats);
	CreateNative("gameWEStatsColorEntities", native_color_gamewe_entities);

	// gameME native names, so plugins compiled against gameme.inc keep working
	CreateNative("DisplayGameMEStatsMenu", native_display_menu);
	CreateNative("QueryGameMEStats", native_query_gamewe_stats);
	CreateNative("QueryGameMEStatsTop10", native_query_gamewe_stats);
	CreateNative("QueryGameMEStatsNext", native_query_gamewe_stats);
	CreateNative("QueryIntGameMEStats", native_query_gamewe_stats);
	CreateNative("gameMEStatsColorEntities", native_color_gamewe_entities);

	MarkNativeAsOptional("CS_SwitchTeam");
	MarkNativeAsOptional("CS_RespawnPlayer");
	MarkNativeAsOptional("SetCookieMenuItem");
	MarkNativeAsOptional("RegClientCookie");
	MarkNativeAsOptional("GetClientCookie");
	MarkNativeAsOptional("SetClientCookie");
	MarkNativeAsOptional("AreClientCookiesCached");
	MarkNativeAsOptional("SDKHook");

	MarkNativeAsOptional("GetUserMessageType");
	MarkNativeAsOptional("PbSetInt");
	MarkNativeAsOptional("PbSetBool");
	MarkNativeAsOptional("PbSetString");
	MarkNativeAsOptional("PbAddString");

	return APLRes_Success;
}


public void OnAllPluginsLoaded()
{
	if (LibraryExists("clientprefs")) {
		gamewe_plugin.cookie_damage_display = RegClientCookie("gamewe_damage_display", "gameWE: damage display (0 = off, 1 = menu, 2 = chat, empty = server default)", CookieAccess_Private);
		gamewe_plugin.cookie_spectatorinfo  = RegClientCookie("gamewe_spectatorinfo", "gameWE: spectator info (0 = off, 1 = on, empty = server default)", CookieAccess_Private);
		gamewe_plugin.clientprefs_available = true;
		SetCookieMenuItem(gameWESettingsMenu, 0, "gameWE Settings");
	}

	if (LibraryExists("sdkhooks")) {
		LogToGame("gameWE Extension SDK Hooks is available");
		gamewe_plugin.sdkhook_available = true;
	}


	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			if (gamewe_plugin.sdkhook_available) {
				switch (gamewe_plugin.mod_id) {
					case MOD_HL2MP: {
						SDKHook(i, SDKHook_FireBulletsPost,  OnHL2MPFireBullets);
						SDKHook(i, SDKHook_TraceAttackPost,  OnHL2MPTraceAttack);
						SDKHook(i, SDKHook_OnTakeDamagePost, OnHL2MPTakeDamage);
					}
					case MOD_ZPS: {
						SDKHook(i, SDKHook_FireBulletsPost,  OnZPSFireBullets);
						SDKHook(i, SDKHook_TraceAttackPost,  OnZPSTraceAttack);
						SDKHook(i, SDKHook_OnTakeDamagePost, OnZPSTakeDamage);
					}
					case MOD_TF2: {
						SDKHook(i, SDKHook_OnTakeDamagePost, OnTF2TakeDamage_Post);
						SDKHook(i, SDKHook_OnTakeDamage, 	 OnTF2TakeDamage);

						tf2_players[i].player_loadout_updated = true;
						tf2_players[i].carry_object = false;
						tf2_players[i].object_removed = 0.0;
						tf2_players[i].player_class = TFClass_Unknown;

						for (int j = 0; j < TF2_MAX_LOADOUT_SLOTS; j++) {
							tf2_players[i].player_loadout0[j] = -1;
							tf2_players[i].player_loadout1[j] = -1;
						}

					}
				}
			}

			if (!IsFakeClient(i)) {
				load_player_settings(i);
				QueryClientConVar(i, "cl_language", ClientConVar, i);
				if ((gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_HL2MP)) {
					QueryClientConVar(i, "cl_connectmethod", ClientConVar, i);
				}
			}

			if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS)) {
				gamewe_players[i].pspectator.stimer = INVALID_HANDLE;
				for (int j = 0; (j <= MAXPLAYERS); j++) {
					player_messages[j][i].supdated = 1;
					strcopy(player_messages[j][i].smessage, 255, "");
				}
			}
		}
	}
}


public void gameWESettingsMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_SelectOption) {
		display_settings_menu(client);
	}
}


// sm_gamewe_settings (!gamewe_settings): the player's gameWE settings
public Action gamewe_settings_command(int client, int args)
{
	if ((client > 0) && IsClientInGame(client) && !IsFakeClient(client)) {
		display_settings_menu(client);
	}
	return Plugin_Handled;
}


// Shows the settings menu. Without the ranking state yet, the plugin asks
// the collector for it (`requested "hideranking"`, at most every 5 seconds,
// so opening the menu cannot flood the collector); the menu is shown again
// when gamewe_hidestate arrives.
void display_settings_menu(int client)
{
	float now = GetGameTime();
	float asked = gamewe_player_settings[client].hideranking_asked;
	if ((gamewe_player_settings[client].hideranking == HIDERANKING_UNKNOWN) &&
	    ((asked <= 0.0) || ((now - asked) >= 5.0) || (now < asked))) {
		gamewe_player_settings[client].hideranking_asked = now;
		gamewe_player_settings[client].hideranking_wait = true;
		log_player_settings(client, "requested", "hideranking", "0");
	}
	DisplayMenu(gamewe_plugin.menu_settings, client, MENU_TIME_FOREVER);
}


// gamewe_hidestate <userid> <hideranking>: the collector tells the player's
// ranking state, after !hideranking / !settings or when the menu asked.
public Action gamewe_hidestate(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_hidestate <userid> <hideranking> - ranking state for the settings menu");
		return Plugin_Handled;
	}

	char argument[16];
	GetCmdArg(1, argument, sizeof(argument));
	int client = GetClientOfUserId(StringToInt(argument));
	if ((client < 1) || !IsClientInGame(client) || IsFakeClient(client)) {
		return Plugin_Handled;
	}

	GetCmdArg(2, argument, sizeof(argument));
	int hide_state = StringToInt(argument);
	if ((hide_state < 0) || (hide_state > 3)) {
		hide_state = HIDERANKING_UNKNOWN;
	}
	gamewe_player_settings[client].hideranking = hide_state;

	if (gamewe_player_settings[client].hideranking_wait) {
		gamewe_player_settings[client].hideranking_wait = false;
		DisplayMenu(gamewe_plugin.menu_settings, client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}


void reset_player_settings(int client)
{
	gamewe_player_settings[client].damage_display = SETTING_SERVER_DEFAULT;
	gamewe_player_settings[client].spectatorinfo  = SETTING_SERVER_DEFAULT;
	gamewe_player_settings[client].hideranking    = HIDERANKING_UNKNOWN;
	gamewe_player_settings[client].hideranking_wait = false;
	gamewe_player_settings[client].hideranking_asked = 0.0;
}


// cookie value -> setting; empty, "default" or anything invalid means the server default
int parse_player_setting(const char[] value, int max_value)
{
	if ((value[0] == '\0') || (strcmp(value, "default") == 0)) {
		return SETTING_SERVER_DEFAULT;
	}
	int setting = 0;
	if ((StringToIntEx(value, setting) != strlen(value)) || (setting < 0) || (setting > max_value)) {
		return SETTING_SERVER_DEFAULT;
	}
	return setting;
}


// loads the player's settings from the clientprefs cookies (once they are cached).
// Without clientprefs the choices made in the menu last until the player disconnects.
void load_player_settings(int client)
{
	if ((!gamewe_plugin.clientprefs_available) || (!AreClientCookiesCached(client))) {
		return;
	}

	char value[16];
	GetClientCookie(client, gamewe_plugin.cookie_damage_display, value, sizeof(value));
	gamewe_player_settings[client].damage_display = parse_player_setting(value, 2);
	GetClientCookie(client, gamewe_plugin.cookie_spectatorinfo, value, sizeof(value));
	gamewe_player_settings[client].spectatorinfo = parse_player_setting(value, 1);
}


void save_player_setting(int client, Handle cookie, int setting)
{
	if ((!gamewe_plugin.clientprefs_available) || (cookie == INVALID_HANDLE) || (!AreClientCookiesCached(client))) {
		return;
	}

	char value[16];
	if (setting == SETTING_SERVER_DEFAULT) {
		strcopy(value, sizeof(value), "");
	} else {
		IntToString(setting, value, sizeof(value));
	}
	SetClientCookie(client, cookie, value);
}


public void OnClientCookiesCached(int client)
{
	if ((client > 0) && (client <= MaxClients) && (!IsFakeClient(client))) {
		load_player_settings(client);
	}
}


// the player's damage display mode (0 = off, 1 = menu, 2 = chat):
// the player's own choice, otherwise the server default gamewe_damage_display
int get_damage_display_mode(int client)
{
	if (gamewe_plugin.damage_display == 0) {
		return 0;
	}
	int mode = gamewe_player_settings[client].damage_display;
	if (mode == SETTING_SERVER_DEFAULT) {
		mode = GetConVarInt(gamewe_plugin.enable_damage_display);
	}
	if ((mode < 0) || (mode > 2)) {
		mode = 0;
	}
	return mode;
}


// true if the player wants the spectator info: the player's own choice,
// otherwise the server default gamewe_display_spectatorinfo
bool is_spectatorinfo_enabled(int client)
{
	if (gamewe_plugin.display_spectator == 0) {
		return false;
	}
	int setting = gamewe_player_settings[client].spectatorinfo;
	if (setting == SETTING_SERVER_DEFAULT) {
		setting = GetConVarInt(gamewe_plugin.display_spectatorinfo);
	}
	return (setting == 1);
}


bool mod_has_damage_display()
{
	return (gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS);
}


bool mod_has_spectatorinfo()
{
	return (gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS);
}


// shows the damage summary to a player who just died, in the player's display mode
void display_damage_on_death(int victim)
{
	int damage_mode = get_damage_display_mode(victim);
	if (damage_mode == 2) {
		build_damage_chat(victim);
	} else if (damage_mode == 1) {
		build_damage_panel(victim);
	} else {
		// not displayed: forget the killer, so it does not show up after a later death
		for (int i = 1; (i <= MaxClients); i++) {
			player_damage[i][victim].dkiller = 0;
			player_damage[i][victim].dhpleft = 0;
			player_damage[i][victim].dweapon = -1;
		}
	}
}


public void OnMapStart()
{

	get_server_mod();

	for (int i = 0; (i <= MAXPLAYERS); i++) {
		reset_player_data(i);
		gamewe_players[i].prole = -1;
		gamewe_players[i].pgglevel = 0;
	}

	if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_HL2MP) ||
	    (gamewe_plugin.mod_id == MOD_INSMOD) || (gamewe_plugin.mod_id == MOD_FF) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) ||
	    (gamewe_plugin.mod_id == MOD_CSP)) {

		char map_name[64];
		GetCurrentMap(map_name, 64);

		int max_teams_count = GetTeamCount();
		for (int team_index = 0; (team_index < max_teams_count); team_index++) {
			char team_name[32];
			GetTeamName(team_index, team_name, 32);

			if (strcmp(team_name, "") != 0) {
				team_list[team_index] = team_name;
			}
		}
	}

	if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD)) {
		find_player_team_slot(2);
		find_player_team_slot(3);
	}

	ClearArray(QueryCallbackArray);
}


void set_server_mod(const char[] game_mod, int mod_id)
{
	strcopy(gamewe_plugin.game_mod, sizeof(gamewe_plugin.game_mod), game_mod);
	gamewe_plugin.mod_id = mod_id;
}


void get_server_mod()
{
	if (strcmp(gamewe_plugin.game_mod, "") == 0) {
		// the engine version is the most reliable source, mods are detected by name below
		switch (GetEngineVersion()) {
			case Engine_CSS:          set_server_mod("CSS", MOD_CSS);
			case Engine_CSGO:         set_server_mod("CSGO", MOD_CSGO);
			case Engine_DODS:         set_server_mod("DODS", MOD_DODS);
			case Engine_HL2DM:        set_server_mod("HL2MP", MOD_HL2MP);
			case Engine_TF2:          set_server_mod("TF2", MOD_TF2);
			case Engine_Insurgency:   set_server_mod("INSMOD", MOD_INSMOD);
			case Engine_Left4Dead:    set_server_mod("L4D", MOD_L4D);
			case Engine_Left4Dead2:   set_server_mod("L4DII", MOD_L4DII);
		}

		char game_description[64];
		GetGameDescription(game_description, 64, true);

		if (strcmp(gamewe_plugin.game_mod, "") == 0) {

			if (StrContains(game_description, "Counter-Strike", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSS");
				gamewe_plugin.mod_id = MOD_CSS;
			}
			if (StrContains(game_description, "Counter-Strike: Global Offensive", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSGO");
				gamewe_plugin.mod_id = MOD_CSGO;
			}
			if (StrContains(game_description, "Day of Defeat", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "DODS");
				gamewe_plugin.mod_id = MOD_DODS;
			}
			if (StrContains(game_description, "Half-Life 2 Deathmatch", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "HL2MP");
				gamewe_plugin.mod_id = MOD_HL2MP;
			}
			if (StrContains(game_description, "Team Fortress", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "TF2");
				gamewe_plugin.mod_id = MOD_TF2;
			}
			if (StrContains(game_description, "Insurgency", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "INSMOD");
				gamewe_plugin.mod_id = MOD_INSMOD;
			}
			if (StrContains(game_description, "L4D", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "L4D");
				gamewe_plugin.mod_id = MOD_L4D;
			}
			if (StrContains(game_description, "Left 4 Dead 2", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "L4DII");
				gamewe_plugin.mod_id = MOD_L4DII;
			}
			if (StrContains(game_description, "Fortress Forever", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "FF");
				gamewe_plugin.mod_id = MOD_FF;
			}
			if (StrContains(game_description, "CSPromod", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSP");
				gamewe_plugin.mod_id = MOD_CSP;
			}
			if (StrContains(game_description, "ZPS", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "ZPS");
				gamewe_plugin.mod_id = MOD_ZPS;
			}

		}

		// game mod could not detected, try further
		if (strcmp(gamewe_plugin.game_mod, "") == 0) {
			char game_folder[64];
			GetGameFolderName(game_folder, 64);

			if (StrContains(game_folder, "cstrike", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSS");
				gamewe_plugin.mod_id = MOD_CSS;
			}
			if (StrContains(game_folder, "csgo", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSGO");
				gamewe_plugin.mod_id = MOD_CSGO;
			}
			if (StrContains(game_folder, "dod", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "DODS");
				gamewe_plugin.mod_id = MOD_DODS;
			}
			if (StrContains(game_folder, "hl2mp", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "HL2MP");
				gamewe_plugin.mod_id = MOD_HL2MP;
			}
			if (StrContains(game_folder, "tf", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "TF2");
				gamewe_plugin.mod_id = MOD_TF2;
			}
			if (StrContains(game_folder, "insurgency", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "INSMOD");
				gamewe_plugin.mod_id = MOD_INSMOD;
			}
			if (StrContains(game_folder, "left4dead", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "L4D");
				gamewe_plugin.mod_id = MOD_L4D;
			}
			if (StrContains(game_folder, "left4dead2", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "L4DII");
				gamewe_plugin.mod_id = MOD_L4DII;
			}
			if (StrContains(game_folder, "FortressForever", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "FF");
				gamewe_plugin.mod_id = MOD_FF;
			}
			if (StrContains(game_folder, "cspromod", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "CSP");
				gamewe_plugin.mod_id = MOD_CSP;
			}
			if (StrContains(game_folder, "zps", false) != -1) {
				strcopy(gamewe_plugin.game_mod, 32, "ZPS");
				gamewe_plugin.mod_id = MOD_ZPS;
			}
			if (strcmp(gamewe_plugin.game_mod, "") == 0) {
				LogToGame("gameWE Game Detection: Failed (%s, %s)", game_description, game_folder);
			}
		}

		// setup hooks
		switch (gamewe_plugin.mod_id) {
			case MOD_CSGO: {
				HookEvent("weapon_fire",  		   	      Event_CSGOPlayerFire);
				HookEvent("weapon_fire_on_empty",  	      Event_CSGOPlayerFire);
				HookEvent("player_hurt",     	  		  Event_CSGOPlayerHurt);
				HookEvent("player_death", 			      Event_CSGOPlayerDeath);
				HookEvent("player_spawn",		     	  Event_CSGOPlayerSpawn);
				HookEvent("round_start",   	   	   	      Event_CSGORoundStart);
				HookEvent("round_end",       		  	  Event_CSGORoundEnd);
				HookEvent("round_announce_warmup",        Event_CSGOAnnounceWarmup);
				HookEvent("round_announce_match_start",   Event_CSGOAnnounceMatchStart);
				HookEvent("gg_player_levelup",            Event_CSGOGGLevelUp);
				HookEvent("ggtr_player_levelup",          Event_CSGOGGLevelUp);
				HookEvent("ggprogressive_player_levelup", Event_CSGOGGLevelUp);
				HookEvent("gg_final_weapon_achieved",     Event_CSGOGGWin);
				HookEvent("gg_leader",                    Event_CSGOGGLeader);
				HookEvent("round_mvp",                    Event_RoundMVP);

				HookEvent("bomb_dropped",		 	 gameWE_Event_PlyBombDropped, EventHookMode_Pre);
				HookEvent("player_given_c4",     	 gameWE_Event_PlyBombPickup,  EventHookMode_Pre);
				HookEvent("bomb_planted",    		 gameWE_Event_PlyBombPlanted, EventHookMode_Pre);
				HookEvent("bomb_defused",    		 gameWE_Event_PlyBombDefused, EventHookMode_Pre);
				HookEvent("hostage_killed",  		 gameWE_Event_PlyHostageKill, EventHookMode_Pre);
				HookEvent("hostage_rescued", 		 gameWE_Event_PlyHostageResc, EventHookMode_Pre);

			}
			case MOD_CSS: {
				HookEvent("weapon_fire",  			 Event_CSSPlayerFire);
				HookEvent("player_hurt",  			 Event_CSSPlayerHurt);
				HookEvent("player_death", 			 Event_CSSPlayerDeath);
				HookEvent("player_spawn",			 Event_CSSPlayerSpawn);
				HookEvent("round_start",   			 Event_CSSRoundStart);
				HookEvent("round_end",    			 Event_CSSRoundEnd);
				HookEvent("round_mvp",               Event_RoundMVP);

				HookEvent("bomb_dropped",			 gameWE_Event_PlyBombDropped, EventHookMode_Pre);
				HookEvent("bomb_pickup",     		 gameWE_Event_PlyBombPickup,  EventHookMode_Pre);
				HookEvent("bomb_planted",    		 gameWE_Event_PlyBombPlanted, EventHookMode_Pre);
				HookEvent("bomb_defused",    		 gameWE_Event_PlyBombDefused, EventHookMode_Pre);
				HookEvent("hostage_killed",  		 gameWE_Event_PlyHostageKill, EventHookMode_Pre);
				HookEvent("hostage_rescued", 		 gameWE_Event_PlyHostageResc, EventHookMode_Pre);
			}
			case MOD_DODS: {
				HookEvent("dod_stats_weapon_attack", Event_DODSWeaponAttack);
				HookEvent("player_hurt",  			 Event_DODSPlayerHurt);
				HookEvent("player_death", 			 Event_DODSPlayerDeath);
				HookEvent("round_end", 			     Event_DODSRoundEnd);
			}
			case MOD_TF2: {
				HookEvent("player_death", 			 	Event_TF2PlayerDeath);

				HookEvent("object_destroyed", 			Event_TF2ObjectDestroyedPre, EventHookMode_Pre);
				HookEvent("player_builtobject", 	 	Event_TF2PlayerBuiltObjectPre, EventHookMode_Pre);
				HookEvent("player_spawn", 			 	Event_TF2PlayerSpawn);
				HookEvent("round_start",   			 	Event_TF2RoundStart);
				HookEvent("round_end",    			 	Event_TF2RoundEnd);
				HookEvent("object_removed", 			Event_TF2ObjectRemoved);
				HookEvent("post_inventory_application", Event_TF2PostInvApp);
				HookEvent("teamplay_win_panel",     	Event_TF2WinPanel);
				HookEvent("arena_win_panel",         	Event_TF2WinPanel);
				HookEvent("player_teleported",       	Event_TF2PlayerTeleported);

				HookEvent("rocket_jump", 				Event_TF2RocketJump);
				HookEvent("rocket_jump_landed", 	 	Event_TF2JumpLanded);
				HookEvent("sticky_jump", 				Event_TF2StickyJump);
				HookEvent("sticky_jump_landed", 	 	Event_TF2JumpLanded);
				HookEvent("object_deflected", 			Event_TF2ObjectDeflected);

				HookEvent("player_stealsandvich",    	Event_TF2StealSandvich);
				HookEvent("player_stunned",          	Event_TF2Stunned);
				HookEvent("player_escort_score",     	Event_TF2EscortScore);
				HookEvent("deploy_buff_banner",      	Event_TF2DeployBuffBanner);
				HookEvent("medic_defended",          	Event_TF2MedicDefended);

				HookUserMessage(GetUserMessageId("PlayerJarated"),       Event_TF2Jarated);
				HookUserMessage(GetUserMessageId("PlayerShieldBlocked"), Event_TF2ShieldBlocked);

				AddNormalSoundHook(Event_TF2SoundHook);

				tf2_data.carry_offset = FindSendPropInfo("CTFPlayer", "m_bCarryingObject");
			}
			case MOD_L4D, MOD_L4DII: {
				HookEvent("weapon_fire",  			 Event_L4DPlayerFire);
				HookEvent("weapon_fire_on_empty",  	 Event_L4DPlayerFire);
				HookEvent("player_hurt",  			 Event_L4DPlayerHurt);
				HookEvent("infected_hurt",  		 Event_L4DInfectedHurt);
				HookEvent("player_death", 			 Event_L4DPlayerDeath);
				HookEvent("player_spawn", 			 Event_L4DPlayerSpawn);
				HookEvent("round_end_message",		 Event_L4DRoundEnd, EventHookMode_PostNoCopy);

				HookEvent("survivor_rescued",		 Event_L4DRescueSurvivor);
				HookEvent("heal_success", 			 Event_L4DHeal);
				HookEvent("revive_success", 		 Event_L4DRevive);
				HookEvent("witch_harasser_set", 	 Event_L4DStartleWitch);
				HookEvent("lunge_pounce", 			 Event_L4DPounce);
				HookEvent("player_now_it", 			 Event_L4DBoomered);
				HookEvent("friendly_fire", 			 Event_L4DFF);
				HookEvent("witch_killed", 			 Event_L4DWitchKilled);
				HookEvent("award_earned", 			 Event_L4DAward);

				if (gamewe_plugin.mod_id == MOD_L4DII) {
					HookEvent("defibrillator_used", 	 Event_L4DDefib);
					HookEvent("adrenaline_used", 	     Event_L4DAdrenaline);
					HookEvent("jockey_ride", 		     Event_L4DJockeyRide);
					HookEvent("charger_pummel_start",    Event_L4DChargerPummelStart);
					HookEvent("vomit_bomb_tank",         Event_L4DVomitBombTank);
					HookEvent("scavenge_match_finished", Event_L4DScavengeEnd);
					HookEvent("versus_match_finished",   Event_L4DVersusEnd);
					HookEvent("charger_killed",          Event_L4dChargerKilled);
				}

			}
			case MOD_INSMOD: {
				HookEvent("player_death", 			 Event_INSMODPlayerDeath);
				HookEvent("player_hurt",  			 Event_INSMODPlayerHurt);
				HookEvent("weapon_fire",  			 Event_INSMODEventFired);
				HookEvent("player_spawn", 			 Event_INSMODPlayerSpawn);
				HookEvent("player_pick_squad",       Event_INSMODPlayerPickSquad);
				HookEvent("round_end",    			 Event_INSMODRoundEnd);
				HookEvent("object_destroyed",		 Event_INSMODObjectiveDestroyed);
				HookEvent("controlpoint_captured",	 Event_INSMODControlpointCapped);
			}
			case MOD_HL2MP: {
				HookEvent("player_death",            Event_HL2MPPlayerDeath);
				HookEvent("player_spawn",            Event_HL2MPPlayerSpawn);
				HookEvent("round_end",               Event_HL2MPRoundEnd, EventHookMode_PostNoCopy);
			}
			case MOD_ZPS: {
				HookEvent("player_death",            Event_ZPSPlayerDeath);
				HookEvent("player_spawn",            Event_ZPSPlayerSpawn);
				HookEvent("round_end",               Event_ZPSRoundEnd, EventHookMode_PostNoCopy);
			}
			case MOD_CSP: {
				HookEvent("round_start",   			 Event_CSPRoundStart);
				HookEvent("round_end",    			 Event_CSPRoundEnd);
			}
		} // end switch

		// generic death event hook
		HookEvent("player_death", gameWE_Event_PlyDeath, EventHookMode_Pre);

		if ((gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD)) {
			// since almost no deaths occurs force the data to be logged at least every 180 seconds
			CreateTimer(180.0, flush_weapon_logs, 0, TIMER_REPEAT);
		}

		// player location logging
		if (gamewe_plugin.enable_log_locations != INVALID_HANDLE) {
			int enable_log_locations_cvar = GetConVarInt(gamewe_plugin.enable_log_locations);
			if (enable_log_locations_cvar == 1) {
				gamewe_plugin.log_locations = 1;
				LogToGame("gameWE location logging activated");
			} else if (enable_log_locations_cvar == 0) {
				gamewe_plugin.log_locations = 0;
				LogToGame("gameWE location logging deactivated");
			}
		} else {
			gamewe_plugin.log_locations = 0;
		}

		LogToGame("gameWE Game Detection: %s [%s]", game_description, gamewe_plugin.game_mod);

	}
}


public void OnClientPutInServer(int client)
{
	if (client > 0) {
		gamewe_last_trigger[client] = 0.0;
		if (gamewe_plugin.sdkhook_available) {
			switch (gamewe_plugin.mod_id) {
				case MOD_HL2MP: {
					SDKHook(client, SDKHook_FireBulletsPost,  OnHL2MPFireBullets);
					SDKHook(client, SDKHook_TraceAttackPost,  OnHL2MPTraceAttack);
					SDKHook(client, SDKHook_OnTakeDamagePost, OnHL2MPTakeDamage);
				}
				case MOD_ZPS: {
					SDKHook(client, SDKHook_FireBulletsPost,  OnZPSFireBullets);
					SDKHook(client, SDKHook_TraceAttackPost,  OnZPSTraceAttack);
					SDKHook(client, SDKHook_OnTakeDamagePost, OnZPSTakeDamage);
				}
				case MOD_TF2: {
					SDKHook(client, SDKHook_OnTakeDamagePost, OnTF2TakeDamage_Post);
					SDKHook(client, SDKHook_OnTakeDamage, 	  OnTF2TakeDamage);

					tf2_players[client].player_loadout_updated = true;
					tf2_players[client].carry_object = false;
					tf2_players[client].object_removed = 0.0;
					tf2_players[client].player_class = TFClass_Unknown;

					for (int i = 0; (i < TF2_MAX_LOADOUT_SLOTS); i++) {
						tf2_players[client].player_loadout0[i] = -1;
						tf2_players[client].player_loadout1[i] = -1;
					}
				}
			}
		}

		reset_player_data(client);
		gamewe_players[client].prole = -1;
		gamewe_players[client].pgglevel = 0;

		if (!IsFakeClient(client)) {
			load_player_settings(client);
			QueryClientConVar(client, "cl_language", ClientConVar, client);
			if ((gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_HL2MP)) {
				QueryClientConVar(client, "cl_connectmethod", ClientConVar, client);
			}
		}

		if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS)) {
			if (gamewe_plugin.display_spectator == 1) {
				gamewe_players[client].pspectator.stimer = INVALID_HANDLE;
				for (int j = 0; (j <= MAXPLAYERS); j++) {
					player_messages[j][client].supdated = 1;
					strcopy(player_messages[j][client].smessage, 255, "");
				}
			}
		}

	}
}


public void ClientConVar(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue) {
	if (IsClientConnected(client)) {
		log_player_settings(client, "setup", cvarName, cvarValue);
	}
}


int get_weapon_index(const char[][] weapon_list, int weapon_list_count, const char[] weapon_name)
{
	int loop_break = 0;
	int index = 0;

	while ((loop_break == 0) && (index < weapon_list_count)) {
   	    if (strcmp(weapon_name, weapon_list[index], true) == 0) {
       		loop_break++;
		} else {
			index++;
		}
	}

	if (loop_break == 0) {
		return -1;
	}
	return index;
}


void init_tf2_weapon_trie()
{

	tf2_data.weapons_trie = new StringMap();
	for (int i = 0; i < MAX_TF2_WEAPON_COUNT; i++) {
		SetTrieValue(tf2_data.weapons_trie, tf2_weapon_list[i], i);
	}

	int index;
	if(GetTrieValue(tf2_data.weapons_trie, "ball", index)) {
		SetTrieValue(tf2_data.weapons_trie, "tf_projectile_stun_ball", index);
		tf2_data.stun_ball_id = index;
	}
}


int get_tf2_weapon_index(const char[] weapon_name, int client = 0, int weapon = -1)
{
	int weapon_index = -1;
	bool unlockable_weapon;
	int reflect_index = -1;

	if (strlen(weapon_name) < 15) {
		return -1;
	}

	if(GetTrieValue(tf2_data.weapons_trie, weapon_name, weapon_index)) {
		if (weapon_index & TF2_UNLOCKABLE_BIT) {
			weapon_index &= ~TF2_UNLOCKABLE_BIT;
			unlockable_weapon = true;
		}

		if ((weapon_name[3] == 'p') && (weapon > -1)) {
			if (client == GetEntProp(weapon, Prop_Send, "m_iDeflected")) {
				switch(weapon_name[14]) {
					case 'a':
						reflect_index = get_tf2_weapon_index("deflect_arrow");
					case 'f':
						reflect_index = get_tf2_weapon_index("deflect_flare");
					case 'p': {
						if (weapon_name[19] == 0) {
							reflect_index = get_tf2_weapon_index("deflect_promode");
						}
					}
					case 'r':
						reflect_index = get_tf2_weapon_index("deflect_rocket");
				}
			}
		}

		if (reflect_index > -1) {
			return reflect_index;
		}

		if ((unlockable_weapon) && (client > 0)) {
			int slot = 0;
			if (tf2_players[client].player_class == TFClass_DemoMan) {
				slot = 1;
			}
			int item_index = tf2_players[client].player_loadout0[slot];
			switch (item_index) {
				case 36, 41, 45, 61, 127, 130:
					weapon_index++;
			}
		}
	}
	return weapon_index;
}



void reset_player_data(int player_index)
{
	for (int i = 0; (i < MAX_LOG_WEAPONS); i++) {
		player_weapons[player_index][i].wshots     = 0;
		player_weapons[player_index][i].whits      = 0;
		player_weapons[player_index][i].wkills     = 0;
		player_weapons[player_index][i].wheadshots = 0;
		player_weapons[player_index][i].wteamkills = 0;
		player_weapons[player_index][i].wdamage    = 0;
		player_weapons[player_index][i].wdeaths    = 0;
		player_weapons[player_index][i].wgeneric   = 0;
		player_weapons[player_index][i].whead      = 0;
		player_weapons[player_index][i].wchest     = 0;
		player_weapons[player_index][i].wstomach   = 0;
		player_weapons[player_index][i].wleftarm   = 0;
		player_weapons[player_index][i].wrightarm  = 0;
		player_weapons[player_index][i].wleftleg   = 0;
		player_weapons[player_index][i].wrightleg  = 0;

	}


	if (gamewe_plugin.damage_display == 1) {
		for (int i = 1; (i <= MaxClients); i++) {
			player_damage[player_index][i].dhits         = 0;
			player_damage[player_index][i].dkills        = 0;
			player_damage[player_index][i].dheadshots    = 0;
			player_damage[player_index][i].ddamage       = 0;
			player_damage[player_index][i].dkiller       = 0;
			player_damage[player_index][i].dhpleft       = 0;
			player_damage[player_index][i].dteamkill     = 0;
			player_damage[player_index][i].dweapon       = 0;
		}
	}

}


void dump_player_data(int player_index)
{
	if (IsClientInGame(player_index))  {
		int is_logged = 0;
		for (int i = 0; (i < MAX_LOG_WEAPONS); i++) {
			if (player_weapons[player_index][i].wshots > 0) {
				switch (gamewe_plugin.mod_id) {
					case MOD_CSGO: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, csgo_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, csgo_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_CSS: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, css_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, css_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_DODS: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, dods_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, dods_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_L4D, MOD_L4DII: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, l4d_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, l4d_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_INSMOD: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, insmod_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, insmod_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_HL2MP: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, hl2mp_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, hl2mp_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_ZPS: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, zps_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
						if (player_weapons[player_index][i].whits > 0) {
							LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", player_index, zps_weapon_list[i], player_weapons[player_index][i].whead, player_weapons[player_index][i].wchest, player_weapons[player_index][i].wstomach, player_weapons[player_index][i].wleftarm, player_weapons[player_index][i].wrightarm, player_weapons[player_index][i].wleftleg, player_weapons[player_index][i].wrightleg);
						}
					}
					case MOD_TF2: {
						LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", player_index, tf2_weapon_list[i], player_weapons[player_index][i].wshots, player_weapons[player_index][i].whits, player_weapons[player_index][i].wkills, player_weapons[player_index][i].wheadshots, player_weapons[player_index][i].wteamkills, player_weapons[player_index][i].wdamage, player_weapons[player_index][i].wdeaths);
					}
				} // switch
				is_logged++;
			}
		}
		if (is_logged > 0) {
			reset_player_data(player_index);
		}
	}

}


public Action flush_weapon_logs(Handle timer, any index)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}
	return Plugin_Continue;
}


public Action spectator_player_timer(Handle timer, any caller)
{
	if (((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS)) && (IsValidEntity(caller)) && (is_spectatorinfo_enabled(caller))) {
		int observer_mode = GetEntProp(caller, Prop_Send, "m_iObserverMode");
		if ((!IsFakeClient(caller)) && ((observer_mode == SPECTATOR_FIRSTPERSON) || (observer_mode == SPECTATOR_3RDPERSON))) {
			int target = GetEntPropEnt(caller, Prop_Send, "m_hObserverTarget");
			if ((target > 0) && (target <= MaxClients) && (IsClientInGame(target))) {

				if ((player_messages[caller][target].supdated == 1) || (gamewe_players[caller].pspectator.starget == 0)) {
					for (int i = 0; (i <= MAXPLAYERS); i++) {
						player_messages[i][target].supdated = 0;
					}
					QueryIntGameWEStats("spectatorinfo", target, QuerygameWEStatsIntCallback, QUERY_TYPE_SPECTATOR);
				}

				if (target != gamewe_players[caller].pspectator.starget) {
					gamewe_players[caller].pspectator.srequested = 0.0;
				}

				if (strcmp(player_messages[caller][target].smessage, "") != 0) {
					if ((caller > 0) && (caller <= MaxClients) && (!IsFakeClient(caller)) && (IsClientInGame(caller))) {
						if ((GetGameTime() - gamewe_players[caller].pspectator.srequested) > 5) {
							send_key_hint(caller, player_messages[caller][target].smessage);
							gamewe_players[caller].pspectator.srequested = GetGameTime();
						}
					}
				} else {
					if (target != gamewe_players[caller].pspectator.starget) {
						if (gamewe_plugin.mod_id != MOD_CSGO) {
							Handle message_handle = StartMessageOne("KeyHintText", caller);
							if (message_handle != INVALID_HANDLE) {
								if (gamewe_plugin.protobuf == 1) {
									PbAddString(message_handle, "hints", "");
								} else {
									BfWriteByte(message_handle, 1);
									BfWriteString(message_handle, "");
								}
								EndMessage();
							}
						}
						gamewe_players[caller].pspectator.srequested = GetGameTime();
					}
				}
				gamewe_players[caller].pspectator.starget = target;
			}
		}
	}
	return Plugin_Continue;
}

public Action QuerygameWEStatsIntCallback(int query_command, int query_payload, int query_caller[MAXPLAYERS + 1], int query_target[MAXPLAYERS + 1], char[] query_message_prefix, char[] query_message)
{
	if ((query_caller[0] > 0) && (query_command == RAW_MESSAGE_CALLBACK_INT_SPECTATOR)) {
		if ((query_payload == QUERY_TYPE_SPECTATOR) && (query_target[0] > 0)) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				if (query_caller[i] > -1) {
					strcopy(player_messages[query_caller[i]][query_target[0]].smessage, 255, query_message);
					ReplaceString(player_messages[query_caller[i]][query_target[0]].smessage, 255, "\\n", "\10");
					gamewe_players[query_caller[i]].pspectator.srequested = 0.0;
				}
			}
		}
	}
	return Plugin_Continue;
}


public void PanelDamageHandler(Menu menu, MenuAction action, int param1, int param2)
{
}


public void build_damage_panel(int player_index)
{

	if ((gamewe_plugin.damage_display == 0) || ((!IsClientInGame(player_index)) || (IsFakeClient(player_index)))) {
		return ;
	}

	int max_clients = MaxClients;

	char attacked[8][128];
	int attacked_index = 0;
	char wounded[8][128];
	int wounded_index = 0;
	char killed[8][128];
	int killed_index = 0;
	char killer[8][128];
	int killer_index = 0;

	for (int i = 1; (i <= max_clients); i++) {
		if (player_index == i) {
			for (int j = 1; (j <= max_clients); j++) {
				int wounded_damage = 0;
				int wounded_hits   = 0;
				int is_kill        = 0;
				if (player_damage[i][j].dhits > 0) {
					wounded_hits = player_damage[i][j].dhits;
					wounded_damage = player_damage[i][j].ddamage;
					if (player_damage[i][j].dkills > 0) {
						is_kill++;
					}
				}
				if (wounded_hits > 0) {
					if (IsClientConnected(j)) {
						if (is_kill == 0) {
							char victim_name[64];
							GetClientName(j, victim_name, 64);
							if (wounded_index < sizeof(wounded)) {
								if (wounded_hits == 1) {
									Format(wounded[wounded_index], 128, "  %s - %d %T, %d Hit", victim_name, wounded_damage, "DamagePanel_Dmg", player_index, wounded_hits, "DamagePanel_Hit", player_index);
								} else {
									Format(wounded[wounded_index], 128, "  %s - %d %T, %d Hits", victim_name, wounded_damage, "DamagePanel_Dmg", player_index, wounded_hits, "DamagePanel_Hits", player_index);
								}
								wounded_index++;
							}
						} else {
							char victim_name[32];
							GetClientName(j, victim_name, 32);
							if (killed_index < sizeof(killed)) {
								if (wounded_hits == 1) {
									Format(killed[killed_index], 128, "  %s - %d %T, %d %T", victim_name, wounded_damage, "DamagePanel_Dmg", player_index, wounded_hits, "DamagePanel_Hit", player_index);
								} else {
									Format(killed[killed_index], 128, "  %s - %d %T, %d %T", victim_name, wounded_damage, "DamagePanel_Dmg", player_index, wounded_hits, "DamagePanel_Hits", player_index);
								}
								killed_index++;
							}
						}
					}
				}
			}
		} else {
			for (int j = 1; (j <= max_clients); j++) {
				if (j == player_index) {
					int attacked_damage   = 0;
					int attacked_hits     = 0;
					int is_killer         = 0;
					int killer_hpleft     = 0;
					int killer_weapon     = 0;
					if (player_damage[i][j].dhits > 0) {
						attacked_hits = player_damage[i][j].dhits;
						attacked_damage = player_damage[i][j].ddamage;
						if (player_damage[i][j].dkiller > 0) {
							is_killer++;
							killer_hpleft = player_damage[i][j].dhpleft;
							killer_weapon = player_damage[i][j].dweapon;

							player_damage[i][j].dkiller = 0;
							player_damage[i][j].dhpleft = 0;
							player_damage[i][j].dweapon = -1;
						}
					}
					if (attacked_hits > 0) {
						if (IsClientConnected(i)) {
							if (is_killer == 0) {
								char attacker_name[64];
								GetClientName(i, attacker_name, 64);
								if (attacked_index < sizeof(attacked)) {
									if (attacked_hits == 1) {
										Format(attacked[attacked_index], 128, "  %s - %d %T, %d %T", attacker_name, attacked_damage, "DamagePanel_Dmg", player_index, attacked_hits, "DamagePanel_Hit", player_index);
									} else {
										Format(attacked[attacked_index], 128, "  %s - %d %T, %d %T", attacker_name, attacked_damage, "DamagePanel_Dmg", player_index, attacked_hits, "DamagePanel_Hits", player_index);
									}
									attacked_index++;
								}
							} else {
								char killer_name[64];
								GetClientName(i, killer_name, 64);
								if (killer_index < sizeof(killer)) {
									if (gamewe_plugin.mod_id == MOD_CSGO) {
										if (attacked_hits == 1) {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, csgo_weapon_list[killer_weapon]);
										} else {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, csgo_weapon_list[killer_weapon]);
										}
									} else if (gamewe_plugin.mod_id == MOD_CSS) {
										if (attacked_hits == 1) {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, css_weapon_list[killer_weapon]);
										} else {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, css_weapon_list[killer_weapon]);
										}
									} else if (gamewe_plugin.mod_id == MOD_DODS) {
										if (attacked_hits == 1) {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, dods_weapon_list[killer_weapon]);
										} else {
											Format(killer[killer_index], 128, "  %s - %d %T, %d %T, %s", killer_name, killer_hpleft,  "DamagePanel_Hp", player_index, attacked_damage, "DamagePanel_Dmg", player_index, dods_weapon_list[killer_weapon]);
										}
									}
									killer_index++;
								}
							}
						}
					}
				}
			}


		}
	}

	if ((attacked_index > 0) || (wounded_index > 0) || (killed_index > 0) || (killer_index > 0)) {
		Panel panel = new Panel();
		SetPanelKeys(panel, 1023);

		int is_attacked = 0;
		for (int i = 0; (i < sizeof(attacked)); i++) {
			if (strcmp(attacked[i], "") != 0) {
				is_attacked++;
				if (is_attacked == 1) {
					char attackers_caption[32];
					Format(attackers_caption, 32, "%T", "DamagePanel_Attackers", player_index);
					DrawPanelItem(panel, attackers_caption);
				}
				DrawPanelText(panel, attacked[i]);
			} else {
				break;
			}
		}

		int is_killed = 0;
		for (int i = 0; (i < sizeof(killed)); i++) {
			if (strcmp(killed[i], "") != 0) {
				is_killed++;
				if (is_killed == 1) {
					char killed_caption[32];
					Format(killed_caption, 32, "%T", "DamagePanel_Killed", player_index);
					DrawPanelItem(panel, killed_caption);
				}
				DrawPanelText(panel, killed[i]);
			} else {
				break;
			}
		}

		int is_wounded = 0;
		for (int i = 0; (i < sizeof(wounded)); i++) {
			if (strcmp(wounded[i], "") != 0) {
				is_wounded++;
				if (is_wounded == 1) {
					char wounded_caption[32];
					Format(wounded_caption, 32, "%T", "DamagePanel_Wounded", player_index);
					DrawPanelItem(panel, wounded_caption);
				}
				DrawPanelText(panel, wounded[i]);
			} else {
				break;
			}
		}

		int is_killer = 0;
		for (int i = 0; (i < sizeof(killer)); i++) {
			if (strcmp(killer[i], "") != 0) {
				is_killer++;
				if (is_killer == 1) {
					char killer_caption[32];
					Format(killer_caption, 32, "%T", "DamagePanel_Killer", player_index);
					DrawPanelItem(panel, killer_caption);
				}
				DrawPanelText(panel, killer[i]);
			} else {
				break;
			}
		}

		SendPanelToClient(panel, player_index, PanelDamageHandler, 15);
		CloseHandle(panel);
	}
}


public void build_damage_chat(int player_index)
{

	if ((gamewe_plugin.damage_display == 0) || ((!IsClientInGame(player_index)) || (IsFakeClient(player_index)))) {
		return ;
	}

	int max_clients = MaxClients;
	char killed_message[192];
	int killer_index = 0;

	for (int i = 1; (i <= max_clients); i++) {
		if (i != player_index) {
			for (int j = 1; (j <= max_clients); j++) {
				if (j == player_index) {
					int attacked_damage = 0;
					int killer_hpleft   = 0;
					int is_killer       = 0;
					if (player_damage[i][j].dhits > 0) {
						attacked_damage = player_damage[i][j].ddamage;
						if (player_damage[i][j].dkiller > 0) {
							killer_hpleft = player_damage[i][j].dhpleft;
							is_killer++;

							player_damage[i][j].dkiller = 0;
							player_damage[i][j].dhpleft = 0;
							player_damage[i][j].dweapon = -1;
						}
					}

					if (is_killer > 0) {
						if (IsClientConnected(i)) {
							char killer_name[64];
							GetClientName(i, killer_name, 64);
							if (strcmp(gamewe_plugin.message_prefix_value, "") == 0) {
								Format(killed_message, 192, "%T", "DamageChat_Killedyou", player_index, killer_name, attacked_damage, killer_hpleft);
							} else {
								Format(killed_message, 192, "%s %T", gamewe_plugin.message_prefix_value, "DamageChat_Killedyou", player_index, killer_name, attacked_damage, killer_hpleft);
							}
							killer_index++;
						}
					}
				}
			}
		}
	}

	if (killer_index > 0) {
		if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {

			if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS)) {
				color_gamewe_entities(killed_message);
				csgo_chat_start(killed_message, sizeof(killed_message));

				if (gamewe_plugin.mod_id == MOD_DODS) {
					PrintToChat(player_index, "%s", killed_message);
				} else {
					Handle message_handle = StartMessageOne("SayText2", player_index);
					if (message_handle != INVALID_HANDLE) {
						if (gamewe_plugin.protobuf == 1) {
							PbSetInt(message_handle, "ent_idx", player_index);
							PbSetBool(message_handle, "chat", false);
							PbSetString(message_handle, "msg_name", killed_message);
							PbAddString(message_handle, "params", "");
							PbAddString(message_handle, "params", "");
							PbAddString(message_handle, "params", "");
							PbAddString(message_handle, "params", "");
						} else {
							BfWriteByte(message_handle, player_index);
							BfWriteByte(message_handle, 0);
							BfWriteString(message_handle, killed_message);
						}
						EndMessage();
					}
				}
			}
		}

	}
}


public void Event_CSGOPlayerFire(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"        "short"
	// "weapon"        "string"        // weapon name used

	int userid   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		ReplaceString(weapon_str, 32, "weapon_", "", false);
		int weapon_index = get_weapon_index(csgo_weapon_list, MAX_CSGO_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if ((weapon_index != 22) && // hegrenade
			    (weapon_index != 32) && // inferno
			    (weapon_index != 33) && // decoy
			    (weapon_index != 34) && // flashbang
			    (weapon_index != 35) && // smokegrenade
			    (weapon_index != 36) && // molotov
			    (weapon_index != 37) && // incgrenade
			    ((weapon_index < 54) || (weapon_index > 57))) { // tagrenade, bumpmine, breachcharge, snowball
				player_weapons[userid][weapon_index].wshots++;
			}
		}
	}
}


public void Event_CSSPlayerFire(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"        "short"
	// "weapon"        "string"        // weapon name used

	int userid   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(css_weapon_list, MAX_CSS_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if ((weapon_index != 27) && // flashbang
			    (weapon_index != 11) && // hegrenade
			    (weapon_index != 26)) { // smokegrenade
				player_weapons[userid][weapon_index].wshots++;
			}
		}
	}
}


public void Event_DODSWeaponAttack(Event event, const char[] name, bool dontBroadcast)
{
    // "attacker"      "short"
    // "weapon"        "byte"

	int userid   = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (userid > 0) {
		int log_weapon_index  = GetEventInt(event, "weapon");

		int weapon_index = -1;
		switch (log_weapon_index) {
			case 1 :
				weapon_index = 20;
			case 2 :
				weapon_index = 16;
			case 3 :
				weapon_index = 7;
			case 4 :
				weapon_index = 15;
			case 5 :
				weapon_index = 10;
			case 6 :
				weapon_index = 8;
			case 7 :
				weapon_index = 1;
			case 8 :
				weapon_index = 2;
			case 9 :
				weapon_index = 9;
			case 10 :
				weapon_index = 3;
			case 11 :
				weapon_index = 0;
			case 12 :
				weapon_index = 4;
			case 13 :
				weapon_index = 6;
			case 14 :
				weapon_index = 11;
			case 15 :
				weapon_index = 12;
			case 16 :
				weapon_index = 5;
			case 17 :
				weapon_index = 13;
			case 18 :
				weapon_index = 14;
			case 19 :
				weapon_index = 19;
			case 20 :
				weapon_index = 17;
			case 23 :
				weapon_index = 24;
			case 24 :
				weapon_index = 23;
			case 25 :
				weapon_index = 22;
			case 26 :
				weapon_index = 21;
			case 31 :
				weapon_index = 8;
			case 33 :
				weapon_index = 9;
			case 34 :
				weapon_index = 3;
			case 35 :
				weapon_index = 12;
			case 36 :
				weapon_index = 5;
			case 38 :
				weapon_index = 6;
		}

		if (weapon_index > -1) {
			if ((weapon_index != 25) && // dod_bomb_target
			    (weapon_index != 21) && // riflegren_ger
			    (weapon_index != 22) && // riflegren_us
			    (weapon_index != 23) && // smoke_ger
			    (weapon_index != 24)) { // smoke_us
				player_weapons[userid][weapon_index].wshots++;
			}
		}
	}

}


public void Event_L4DPlayerFire(Event event, const char[] name, bool dontBroadcast)
{
	// "local"         "1"             // don't network this, its way too spammy
	// "userid"        "short"
	// "weapon"        "string"        // used weapon name
	// "weaponid"      "short"         // used weapon ID
	// "count"         "short"         // number of bullets

	int userid   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(l4d_weapon_list, MAX_L4D_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if ((weapon_index != 12) && // entityflame
			    (weapon_index != 6)) { // inferno
				player_weapons[userid][weapon_index].wshots++;
			}
		}
	}
}


public void Event_CSGOPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	//	"userid"        "short"         // player index who was hurt
	//	"attacker"      "short"         // player index who attacked
	//	"health"        "byte"          // remaining health points
	//	"armor"         "byte"          // remaining armor points
	//	"weapon"        "string"        // weapon name attacker used, if not the world
	//	"dmg_health"    "byte"  		// damage done to health
	//	"dmg_armor"     "byte"          // damage done to armor
	//	"hitgroup"      "byte"          // hitgroup that was damaged

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (attacker != victim)) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(csgo_weapon_list, MAX_CSGO_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if (player_weapons[attacker][weapon_index].wshots == 0) {
				player_weapons[attacker][weapon_index].wshots++;
			}
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += GetEventInt(event, "dmg_health");
			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

			if (gamewe_plugin.damage_display == 1) {
				player_damage[attacker][victim].dhits++;
				player_damage[attacker][victim].ddamage += GetEventInt(event, "dmg_health");
			}
		}
	}
}


public void Event_CSSPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	//	"userid"        "short"         // player index who was hurt
	//	"attacker"      "short"         // player index who attacked
	//	"health"        "byte"          // remaining health points
	//	"armor"         "byte"          // remaining armor points
	//	"weapon"        "string"        // weapon name attacker used, if not the world
	//	"dmg_health"    "byte"  		// damage done to health
	//	"dmg_armor"     "byte"          // damage done to armor
	//	"hitgroup"      "byte"          // hitgroup that was damaged

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (attacker != victim)) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(css_weapon_list, MAX_CSS_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if (player_weapons[attacker][weapon_index].wshots == 0) {
				player_weapons[attacker][weapon_index].wshots++;
			}
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += GetEventInt(event, "dmg_health");
			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

			if (gamewe_plugin.damage_display == 1) {
				player_damage[attacker][victim].dhits++;
				player_damage[attacker][victim].ddamage += GetEventInt(event, "dmg_health");
			}
		}
	}
}


public void Event_DODSPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"        "short"         // user ID who was hurt
	// "attacker"      "short"         // user ID who attacked
	// "weapon"        "string"        // weapon name attacker used
	// "health"        "byte"          // health remaining
	// "damage"        "byte"          // how much damage in this attack
	// "hitgroup"      "byte"          // what hitgroup was hit

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (attacker != victim)) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(dods_weapon_list, MAX_DODS_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if (player_weapons[attacker][weapon_index].wshots == 0) {
				player_weapons[attacker][weapon_index].wshots++;
			}
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += GetEventInt(event, "health");
			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

			if (gamewe_plugin.damage_display == 1) {
				player_damage[attacker][victim].dhits++;
				player_damage[attacker][victim].ddamage += GetEventInt(event, "damage");
			}
		}
	}
}


public void Event_L4DPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// "local"         "1"             // Not networked
	// "userid"        "short"         // user ID who was hurt
	// "attacker"      "short"         // user id who attacked
	// "attackerentid" "long"          // entity id who attacked, if attacker not a player, and userid therefore invalid
	// "health"        "short"         // remaining health points
	// "armor"         "byte"          // remaining armor points
	// "weapon"        "string"        // weapon name attacker used, if not the world
	// "dmg_health"    "short"         // damage done to health
	// "dmg_armor"     "byte"          // damage done to armor
	// "hitgroup"      "byte"          // hitgroup that was damaged
	// "type"          "long"          // damage type

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (attacker != victim)) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		int weapon_index = get_weapon_index(l4d_weapon_list, MAX_L4D_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			if (player_weapons[attacker][weapon_index].wshots == 0) {
				player_weapons[attacker][weapon_index].wshots++;
			}
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += GetEventInt(event, "dmg_health");
			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

		} else if (!strcmp(weapon_str, "insect_swarm")) {
			if ((victim > 0) && (IsClientInGame(victim)) && (GetClientTeam(victim) == 2) &&  (!GetEntProp(victim, Prop_Send, "m_isIncapacitated"))) {
				log_player_player_event(attacker, victim, "triggered", "spit_hurt");
			}
		}

	}
}


public void Event_L4DInfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
	// "local"         "1"             // don't network this, its way too spammy
	// "attacker"      "short"         // player userid who attacked
	// "entityid"      "long"          // entity id of infected
	// "hitgroup"      "byte"          // hitgroup that was damaged
	// "amount"        "short"         // how much damage was done
	// "type"          "long"          // damage type

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (attacker > 0) {
		char weapon_str[32];
		GetClientWeapon(attacker, weapon_str, 32);
		int weapon_index = get_weapon_index(l4d_weapon_list, MAX_L4D_WEAPON_COUNT, weapon_str[7]);
		if (weapon_index > -1) {
			if (player_weapons[attacker][weapon_index].wshots == 0) {
				player_weapons[attacker][weapon_index].wshots++;
			}
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += GetEventInt(event, "amount");

			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

		}
	}
}

public void Event_CSGOPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// this extents the original player_death by a new fields
	//	"userid"	"short"   	// user ID who died
	//	"attacker"	"short"	 	// user ID who killed
	//	"assister"	"short"	 	// user ID who assisted in the kill
	//	"weapon"	"string" 	// weapon name killer used
	//	"headshot"	"bool"		// singals a headshot
	//	"dominated"	"short"		// did killer dominate victim with this kill
	//	"revenge"	"short"		// did killer get revenge on victim with this kill
	//	"penetrated" "short"	// number of objects shot penetrated before killing target

	int victim       = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker     = GetClientOfUserId(GetEventInt(event, "attacker"));
	int weapon_index = -1;

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			weapon_index = get_weapon_index(csgo_weapon_list, MAX_CSGO_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				int headshot = GetEventBool(event, "headshot");
				if (headshot == 1) {
					player_weapons[attacker][weapon_index].wheadshots++;
				}
				player_weapons[victim][weapon_index].wdeaths++;

				if (GetEventInt(event, "dominated")) {
					log_player_player_event(attacker, victim, "triggered", "domination");
				} else if (GetEventInt(event, "revenge")) {
					log_player_player_event(attacker, victim, "triggered", "revenge");
				}

				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
					if (gamewe_plugin.damage_display == 1) {
						player_damage[attacker][victim].dteamkill += 1;
					}
				} else {
					int assister = GetClientOfUserId(GetEventInt(event, "assister"));
					if ((assister > 0) && (assister != victim)) {
						log_player_player_event(assister, victim, "triggered", "kill_assist");
					}
				}

				if (gamewe_plugin.damage_display == 1) {
					player_damage[attacker][victim].dhpleft  = GetClientHealth(attacker);
					player_damage[attacker][victim].dkills   += 1;
					player_damage[attacker][victim].dkiller  = attacker;
					player_damage[attacker][victim].dweapon  = weapon_index;
					if (headshot == 1) {
						player_damage[attacker][victim].dheadshots += 1;
					}

					display_damage_on_death(victim);

				}
			}
		}
		dump_player_data(victim);

		gamewe_players[victim].palive = 0;
		if (gamewe_plugin.display_spectator == 1) {
			if ((victim > 0) && (attacker > 0)) {
				if ((IsClientInGame(victim)) && (!IsFakeClient(victim))) {
					if ((victim == attacker) && (weapon_index == -1)) {
						// this "could" a simple player disconnect if the cvar "mp_disconnect_kills_players"
						// is enabled. However player "world" kills for example by jumping etc are ignored now
						// as well. Hopefully the player disconnect event gets a flag if the kill is triggered
						// by the disconnect event.
					} else {
						gamewe_players[victim].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, victim, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}

			for (int j = 0; (j <= MAXPLAYERS); j++) {
				player_messages[j][attacker].supdated = 1;
				player_messages[j][victim].supdated = 1;
			}
		}
	}
}


public void Event_CSSPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// this extents the original player_death by a new fields
	// "userid"        "short"         // user ID who died
	// "attacker"      "short"         // user ID who killed
	// "weapon"        "string"        // weapon name killer used
	// "headshot"      "bool"          // signals a headshot
	// "dominated" 	   "short"		   // did killer dominate victim with this kill
	// "revenge" 	   "short" 		   // did killer get revenge on victim with this kill

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			int weapon_index = get_weapon_index(css_weapon_list, MAX_CSS_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				int headshot = GetEventBool(event, "headshot");
				if (headshot == 1) {
					player_weapons[attacker][weapon_index].wheadshots++;
				}
				player_weapons[victim][weapon_index].wdeaths++;

				if (GetEventInt(event, "dominated")) {
					log_player_player_event(attacker, victim, "triggered", "domination");
				} else if (GetEventInt(event, "revenge")) {
					log_player_player_event(attacker, victim, "triggered", "revenge");
				}


				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
					if (gamewe_plugin.damage_display == 1) {
						player_damage[attacker][victim].dteamkill += 1;
					}
				}

				if (gamewe_plugin.damage_display == 1) {
					player_damage[attacker][victim].dhpleft  = GetClientHealth(attacker);
					player_damage[attacker][victim].dkills  += 1;
					player_damage[attacker][victim].dkiller  = attacker;
					player_damage[attacker][victim].dweapon  = weapon_index;
					if (headshot == 1) {
						player_damage[attacker][victim].dheadshots += 1;
					}

					display_damage_on_death(victim);

				}
			}
		}
		dump_player_data(victim);

		gamewe_players[victim].palive = 0;
		if (gamewe_plugin.display_spectator == 1) {
			if ((IsClientInGame(victim)) && (!IsFakeClient(victim))) {
				gamewe_players[victim].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, victim, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}

			for (int j = 0; (j <= MAXPLAYERS); j++) {
				player_messages[j][attacker].supdated = 1;
				player_messages[j][victim].supdated = 1;
			}
		}
	}
}


public void Event_DODSPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// this extents the original player_death
	// "userid"        "short"         // user ID who died
	// "attacker"      "short"         // user ID who killed
	// "weapon"        "string"        // weapon name killed used

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			int weapon_index = get_weapon_index(dods_weapon_list, MAX_DODS_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				player_weapons[victim][weapon_index].wdeaths++;

				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
					if (gamewe_plugin.damage_display == 1) {
						player_damage[attacker][victim].dteamkill += 1;
					}
				}

				if (gamewe_plugin.damage_display == 1) {
					player_damage[attacker][victim].dhpleft  = GetClientHealth(attacker);
					player_damage[attacker][victim].dkills  += 1;
					player_damage[attacker][victim].dkiller  = attacker;
					player_damage[attacker][victim].dweapon  = weapon_index;

					display_damage_on_death(victim);
				}
			}
		}
		dump_player_data(victim);
	}
}


public void Event_L4DPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"        "short"         // user ID who died
	// "entityid"      "long"          // entity ID who died, userid should be used first, to get the dead Player.  Otherwise, it is not a player, so use this.         $
	// "attacker"      "short"         // user ID who killed
	// "attackername"  "string"        // What type of zombie, so we don't have zombie names
	// "attackerentid" "long"          // if killer not a player, the entindex of who killed.  Again, use attacker first
	// "weapon"        "string"        // weapon name killer used
	// "headshot"      "bool"          // signals a headshot
	// "attackerisbot" "bool"          // is the attacker a bot
	// "victimname"    "string"        // What type of zombie, so we don't have zombie names
	// "victimisbot"   "bool"          // is the victim a bot
	// "abort"         "bool"          // did the victim abort
	// "type"          "long"          // damage type
	// "victim_x"      "float"
	// "victim_y"      "float"
	// "victim_z"      "float"

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			int weapon_index = get_weapon_index(l4d_weapon_list, MAX_L4D_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				int headshot = GetEventBool(event, "headshot");
				if (headshot == 1) {
					player_weapons[attacker][weapon_index].wheadshots++;
				}
				player_weapons[victim][weapon_index].wdeaths++;

				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
				}
			}
		}
		dump_player_data(victim);
	}
}


public void Event_HL2MPPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// this extents the original player_death by a new fields
	// "userid"        "short"         // user ID who died
	// "attacker"      "short"         // user ID who killed
	// "weapon"        "string"        // weapon name killer used

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			int weapon_index = get_weapon_index(hl2mp_weapon_list, MAX_HL2MP_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				player_weapons[victim][weapon_index].wdeaths++;
				if ((hl2mp_data.teamplay_enabled) && (GetClientTeam(attacker) == GetClientTeam(victim))) {
					player_weapons[attacker][weapon_index].wteamkills++;
				}
			}
		}
		dump_player_data(victim);
	}
}


public void Event_ZPSPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// this extents the original player_death by a new fields
	// "userid"        "short"         // user ID who died
	// "attacker"      "short"         // user ID who killed
	// "weapon"        "string"        // weapon name killer used

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			int weapon_index = get_weapon_index(zps_weapon_list, MAX_ZPS_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				player_weapons[victim][weapon_index].wdeaths++;
				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
				}
			}
		}
		dump_player_data(victim);
	}
}


public void Event_CSGOPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
		if (gamewe_plugin.display_spectator == 1) {
			if (gamewe_players[userid].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[userid].pspectator.stimer);
				gamewe_players[userid].pspectator.stimer = INVALID_HANDLE;
			}
		}


		if (IsClientInGame(userid)) {
			int client_team = GetClientTeam(userid);
			if ((client_team == 2) || (client_team == 3)) {

				char client_model[128];
				GetClientModel(userid, client_model, 128);

				int role_index = -1;
				for (int i = 0; (i < MAX_CSGO_CODE_MODELS); i++) {
					if (StrContains(client_model, csgo_code_models[i]) != -1) {
						role_index = i;
					}
				}

				if (role_index > -1) {
					if (gamewe_players[userid].prole != role_index) {
						gamewe_players[userid].prole = role_index;
						LogToGame("\"%L\" changed role to \"%s\"", userid, csgo_code_models[role_index]);
					}
				}

			} else if (client_team == 0) {

				if (gamewe_plugin.display_spectator == 1) {
					gamewe_players[userid].pspectator.starget = 0;
					if (!IsFakeClient(userid)) {
						gamewe_players[userid].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, userid, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					}
				}

			}
		}

	}
}


public void Event_CSSPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
		if (gamewe_plugin.display_spectator == 1) {
			if (gamewe_players[userid].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[userid].pspectator.stimer);
				gamewe_players[userid].pspectator.stimer = INVALID_HANDLE;
			}
		}


		if (IsClientInGame(userid)) {
			int client_team = GetClientTeam(userid);
			if ((client_team == 2) || (client_team == 3)) {

				char client_model[128];
				GetClientModel(userid, client_model, 128);

				int role_index = -1;
				if (client_team == 2) {
					for (int i = 0; (i < MAX_CSS_TS_MODELS); i++) {
						if (strcmp(css_ts_models[i], client_model) == 0) {
							role_index = i;
						}
					}
				} else if (client_team == 3) {
					for (int i = 0; (i < MAX_CSS_CT_MODELS); i++) {
						if (strcmp(css_ct_models[i], client_model) == 0) {
							role_index = i + MAX_CSS_TS_MODELS;
						}
					}
				}

				if (role_index > -1) {
					if (gamewe_players[userid].prole != role_index) {
						gamewe_players[userid].prole = role_index;
						LogToGame("\"%L\" changed role to \"%s\"", userid, css_code_models[role_index]);
					}
				}

			} else if (client_team == 0) {

				if (gamewe_plugin.display_spectator == 1) {
					gamewe_players[userid].pspectator.starget = 0;

					if (!IsFakeClient(userid)) {
						gamewe_players[userid].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, userid, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					}
				}

			}
		}

	}
}


public void Event_L4DPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
	}
}


public void Event_HL2MPPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
	}
}


public void Event_ZPSPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
	}
}


public Action Event_CSPRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	LogToGame("World triggered \"Round_Start\"");
	return Plugin_Continue;
}


public void Event_CSGORoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (gamewe_plugin.display_spectator == 1) {
		for (int i = 1; (i <= MaxClients); i++) {
			if (gamewe_players[i].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[i].pspectator.stimer);
				gamewe_players[i].pspectator.stimer = INVALID_HANDLE;
			}

			for (int j = 0; (j <= MAXPLAYERS); j++) {
				player_messages[i][j].supdated = 1;
			}

			if ((i > 0) && (IsClientInGame(i)) && (!IsFakeClient(i)) && (IsClientObserver(i))) {
				gamewe_players[i].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}


public void Event_CSSRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (gamewe_plugin.display_spectator == 1) {
		for (int i = 1; (i <= MaxClients); i++) {

			if (gamewe_players[i].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[i].pspectator.stimer);
				gamewe_players[i].pspectator.stimer = INVALID_HANDLE;
			}

			for (int j = 0; (j <= MAXPLAYERS); j++) {
				player_messages[i][j].supdated = 1;
			}

			if ((i > 0) && (IsClientInGame(i)) && (!IsFakeClient(i)) && (IsClientObserver(i))) {
				gamewe_players[i].pspectator.stimer = CreateTimer(SPECTATOR_TIMER_INTERVAL, spectator_player_timer, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}


public void Event_CSGORoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		if ((IsClientConnected(i)) && (IsClientInGame(i)) && (IsPlayerAlive(i))) {
			if (get_damage_display_mode(i) == 1) {
				build_damage_panel(i);
			}
		}
		dump_player_data(i);
	}
}


public void Event_CSSRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		if ((IsClientConnected(i)) && (IsClientInGame(i)) && (IsPlayerAlive(i))) {
			if (get_damage_display_mode(i) == 1) {
				build_damage_panel(i);
			}
		}
		dump_player_data(i);
	}
}


public void Event_DODSRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		if ((IsClientConnected(i)) && (IsClientInGame(i)) && (IsPlayerAlive(i))) {
			if (get_damage_display_mode(i) == 1) {
				build_damage_panel(i);
			}
		}
		dump_player_data(i);
	}
}


public void Event_L4DRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}
}


public void Event_HL2MPRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}
}


public void Event_ZPSRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}
}


public void Event_CSPRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int team_index = GetEventInt(event, "winners");
	if (strcmp(team_list[team_index], "") != 0) {
		log_team_event(team_list[team_index], "Round_Win");
	}
	LogToGame("World triggered \"Round_End\"");
}


public void Event_CSGOAnnounceWarmup(Event event, const char[] name, bool dontBroadcast)
{
	LogToGame("World triggered \"Round_Warmup_Start\"");
}


public void Event_CSGOAnnounceMatchStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 0; (i <= MAXPLAYERS); i++) {
		reset_player_data(i);
		gamewe_players[i].pgglevel = 0;
	}
	LogToGame("World triggered \"Round_Match_Start\"");
}


public void Event_CSGOGGLevelUp(Event event, const char[] name, bool dontBroadcast)
{
	//	"userid"	"short"		// player who leveled up
	//	"weaponrank"	"short"
	//	"weaponname"	"string"	// name of weapon being awarded

	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {

		int level = GetEventInt(event,"weaponrank");
		if (level >= 0) {
			if (level > gamewe_players[player].pgglevel) {
				log_player_event(player, "triggered", "gg_levelup");
			} else if (level < gamewe_players[player].pgglevel) {
				log_player_event(player, "triggered", "gg_leveldown");
			}
			gamewe_players[player].pgglevel = level;
		}
	}
}


public void Event_CSGOGGWin(Event event, const char[] name, bool dontBroadcast)
{
	// 	"playerid"	"short"	 	// user ID who achieved the final gun game weapon

	int player = GetClientOfUserId(GetEventInt(event, "playerid"));
	if (player > 0) {
		log_player_event(player, "triggered", "gg_win");
	}
}


public void Event_CSGOGGLeader(Event event, const char[] name, bool dontBroadcast)
{
	//	"playerid"      "short"         // user ID that is currently in the lead

	int player = GetClientOfUserId(GetEventInt(event, "playerid"));
	if (player > 0) {
		log_player_event(player, "triggered", "gg_leader");
	}
}


public void Event_RoundMVP(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		log_player_event(player, "triggered", "mvp");
	}
}


public void Event_TF2PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"		"short"   	// user ID who died
	// "attacker"	"short"	 	// user ID who killed
	// "weapon"	"string" 		// weapon name killer used
	// "weaponid"	"short"		// ID of weapon killed used
	// "damagebits"	"long"		// bits of type of damage
	// "customkill"	"short"		// type of custom kill
	// "assister"	"short"		// user ID of assister
	// "weapon_logclassname"	"string" 	// weapon name that should be printed on the log
	// "stun_flags"	"short"		// victim's stun flags at the moment of death
	// "death_flags"	"short" //death flags.

	int death_flags = GetEventInt(event, "death_flags");
	if ((death_flags & TF_DEATHFLAG_DEADRINGER) == TF_DEATHFLAG_DEADRINGER) {
		return;
	}

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (victim > 0) && (attacker <= MaxClients)) {

		tf2_players[victim].jump_status = TF2_JUMP_NONE;
		tf2_players[victim].carry_object = false;

		int custom_kill = GetEventInt(event, "customkill");
		if (custom_kill > 0) {
			int victim_team_index = GetClientTeam(victim);
			int player_team_index = GetClientTeam(attacker);

			if (victim_team_index == player_team_index) {
				if (custom_kill == TF_CUSTOM_SUICIDE) {
					log_player_event(attacker, "triggered", "force_suicide");
				}
			} else {
				if (custom_kill == TF_CUSTOM_HEADSHOT) {
					log_player_event(attacker, "triggered", "headshot");
				} else if (custom_kill == TF_CUSTOM_BACKSTAB) {
					log_player_player_event(attacker, victim, "triggered", "backstab");
				}
			}
		}

		if (attacker != victim) {
			switch(tf2_players[attacker].jump_status) {
				case 2:
					log_player_event(attacker, "triggered", "rocket_jump_kill");
				case 3:
					log_player_event(attacker, "triggered", "sticky_jump_kill");
			}

			int bits = GetEventInt(event, "damagebits");
			if ((bits & DMG_ACID) && (attacker > 0) && (custom_kill != TF_CUSTOM_HEADSHOT)) {
				log_player_event(attacker, "triggered", "crit_kill");
			} else if (bits & DMG_DROWN) {
				log_player_event(attacker, "triggered", "drowned");
			}
			if ((death_flags & TF_DEATHFLAG_FIRSTBLOOD) == TF_DEATHFLAG_FIRSTBLOOD) {
				log_player_event(attacker, "triggered", "first_blood");
			}
			if ((custom_kill == TF_CUSTOM_HEADSHOT) && (victim <= MaxClients) && (IsClientInGame(victim)) && ((GetEntityFlags(victim) & (FL_ONGROUND | FL_INWATER)) == 0)) {
				log_player_event(attacker, "triggered", "airshot_headshot");
			}
		}

		char weapon_log_name[64];
		GetEventString(event, "weapon_logclassname", weapon_log_name, 64);
		int weapon_index = get_tf2_weapon_index(weapon_log_name, attacker);
		if (weapon_index != -1) {
			player_weapons[attacker][weapon_index].wkills++;
			if (custom_kill == TF_CUSTOM_HEADSHOT) {
				player_weapons[attacker][weapon_index].wheadshots++;
			}
			player_weapons[victim][weapon_index].wdeaths++;
			if (GetClientTeam(victim) == GetClientTeam(attacker)) {
				player_weapons[attacker][weapon_index].wteamkills++;
			}
		}
		dump_player_data(victim);
		gamewe_players[victim].palive = 0;
	}
}


public void Event_TF2PlayerTeleported(Event event, const char[] name, bool dontBroadcast)
{
	//	"userid"        "short"         // userid of the player
	//	"builderid"     "short"         // userid of the player who built the teleporter

	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	int builder = GetClientOfUserId(GetEventInt(event, "builderid"));
	if (((player > 0) && (builder > 0)) && (player != builder)) {
		log_player_player_event(builder, player, "triggered", "player_teleported", 1);
	}
}


public void OnGameFrame()
{
	switch (gamewe_plugin.mod_id) {
		case MOD_HL2MP: {
			int bow_entity;
			while (PopStackCell(hl2mp_data.boltchecks, bow_entity))	{
				if (!IsValidEntity(bow_entity)) {
					continue;
				}
				int owner = GetEntDataEnt2(bow_entity, hl2mp_data.crossbow_owner_offset);
				if ((owner < 0) || (owner > MaxClients)) {
					continue;
				}
				player_weapons[owner][HL2MP_CROSSBOW].wshots++;
			}
		}
		case MOD_TF2: {
			int entity;
			if ((gamewe_plugin.sdkhook_available) && (tf2_data.stun_ball_id > -1)) {
				while (PopStackCell(tf2_data.stun_balls, entity)) {
					if (IsValidEntity(entity)) {
						int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
						if ((owner > 0) && (owner <= MaxClients)) {
							player_weapons[owner][tf2_data.stun_ball_id].wshots++;
						}
					}
				}
			}

			while (PopStackCell(tf2_data.wearables, entity)) {
				if (IsValidEntity(entity)) {
					int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
					if ((owner > 0) && (owner <= MaxClients)) {

						int item_index = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
						char tmp_str[16];
						Format(tmp_str, 16, "%d", item_index);

						if (KvJumpToKey(tf2_data.items_kv, tmp_str)) {
							KvGetString(tf2_data.items_kv, "item_slot", tmp_str, 16);
							int slot;
							if (GetTrieValue(tf2_data.slots_trie, tmp_str, slot)) {
								if ((slot == 0) && (tf2_players[owner].player_class == TFClass_DemoMan)) {
									slot++;
								}
								if (tf2_players[owner].player_loadout0[slot] != item_index) {
									tf2_players[owner].player_loadout0[slot] = item_index;
									tf2_players[owner].player_loadout_updated = true;
								}
								tf2_players[owner].player_loadout1[slot] = entity;
							}
							KvGoBack(tf2_data.items_kv);
						}
					}
				}
			}

			// client indexes are not contiguous, so walk all slots
			if (tf2_data.carry_offset > 0) {
				for (int i = 1; i <= MaxClients; i++) {
					if ((IsClientInGame(i)) && (GetEntData(i, tf2_data.carry_offset, 1))) {
						tf2_players[i].carry_object = true;
					}
				}
			}

		}

	}
}


public void OnEntityCreated(int entity, const char[] classname) {
	switch (gamewe_plugin.mod_id) {
		case MOD_HL2MP: {
			if (strcmp(classname, "crossbow_bolt") == 0) {
				PushStackCell(hl2mp_data.boltchecks, entity);
			}
		}
		case MOD_TF2: {
			if(StrEqual(classname, "tf_projectile_stun_ball")) {
				PushStackCell(tf2_data.stun_balls, EntIndexToEntRef(entity));
			} else if(StrEqual(classname, "tf_wearable_item_demoshield") || StrEqual(classname, "tf_wearable_item")) {
				PushStackCell(tf2_data.wearables, EntIndexToEntRef(entity));
			}
		}
	}
}


public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	if (gamewe_plugin.mod_id == MOD_CSGO) {
		char command[PLATFORM_MAX_PATH];
		if ((KvGetSectionName(kv, command, sizeof(command))) && (StrEqual(command, "ClanTagChanged", false))) {
			char clan[192];
			KvGetString(kv, "tag", clan, sizeof(clan), "");
			if (strcmp(clan, "") != 0) {
				log_player_settings(client, "triggered", "clantag", clan);
			}
		}
	}
	return Plugin_Continue;
}


public Action OnTF2GameLog(const char[] message)
{
	if (tf2_data.block_next_logging) {
		tf2_data.block_next_logging = false;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}


public void OnLogLocationsChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (strcmp(newVal, "") != 0) {
		if ((strcmp(newVal, "0") == 0) || (strcmp(newVal, "1") == 0)) {
			if (((strcmp(newVal, "1") == 0) && (strcmp(oldVal, "1") != 0)) ||
			   ((strcmp(newVal, "0") == 0) && (strcmp(oldVal, "0") != 0))) {

				if (gamewe_plugin.enable_log_locations != INVALID_HANDLE) {
					int enable_log_locations_cvar = GetConVarInt(gamewe_plugin.enable_log_locations);
					if (enable_log_locations_cvar == 1) {
						gamewe_plugin.log_locations = 1;
						LogToGame("gameWE location logging activated");
					} else if (enable_log_locations_cvar == 0) {
						gamewe_plugin.log_locations = 0;
						LogToGame("gameWE location logging deactivated");
					}
				} else {
					gamewe_plugin.log_locations = 0;
				}

			}
		}
	}
}


// gamewe_display_spectatorinfo_allow: the server can switch the spectator info off for everyone.
// gamewe_display_spectatorinfo itself is only the default for players and is read when needed.
public void OnDisplaySpectatorinfoAllowChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (GetConVarInt(cvar) == 1) {
		if (gamewe_plugin.display_spectator == 0) {
			gamewe_plugin.display_spectator = 1;
			LogToGame("gameWE spectator displaying allowed");
		}
	} else if (gamewe_plugin.display_spectator == 1) {
		gamewe_plugin.display_spectator = 0;
		for (int i = 1; (i <= MaxClients); i++) {
			if (gamewe_players[i].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[i].pspectator.stimer);
				gamewe_players[i].pspectator.stimer = INVALID_HANDLE;
			}
		}
		LogToGame("gameWE spectator displaying deactivated");
	}
}


// gamewe_damage_display_allow: the server can switch the damage display (and its tracking) off
// for everyone. gamewe_damage_display itself is only the default for players and is read when needed.
public void OnDamageDisplayAllowChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (GetConVarInt(cvar) == 1) {
		if (gamewe_plugin.damage_display == 0) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				for (int j = 0; (j <= MAXPLAYERS); j++) {
					player_damage[i][j].dhits      = 0;
					player_damage[i][j].dkills     = 0;
					player_damage[i][j].dheadshots = 0;
					player_damage[i][j].ddamage    = 0;
					player_damage[i][j].dkiller    = 0;
					player_damage[i][j].dhpleft    = 0;
					player_damage[i][j].dteamkill  = 0;
					player_damage[i][j].dweapon    = 0;
				}
			}
			gamewe_plugin.damage_display = 1;
			LogToGame("gameWE damage display allowed");
		}
	} else if (gamewe_plugin.damage_display == 1) {
		gamewe_plugin.damage_display = 0;
		LogToGame("gameWE damage display deactivated");
	}
}


public void OnTagsChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (gamewe_plugin.ignore_next_tag_change){
		return;
	}

	int count = GetArraySize(gamewe_plugin.custom_tags);
	for (int i = 0; (i < count); i++) {
		char tag[128];
		GetArrayString(gamewe_plugin.custom_tags, i, tag, 128);
		AddPluginServerTag(tag);
	}
}


// true for "a.b.c.d:port" (IPv4, octets 0-255, port 1-65535) and nothing else
bool is_valid_protect_address(const char[] value)
{
	int len = strlen(value);
	int dots = 0;
	int colon = -1;
	int part_value = 0;
	int part_digits = 0;
	for (int i = 0; i <= len; i++) {
		int c = value[i];
		if ((c >= '0') && (c <= '9')) {
			part_digits++;
			if (part_digits > 5) {
				return false;
			}
			part_value = (part_value * 10) + (c - '0');
		} else if ((c == '.') || (c == ':') || (c == 0)) {
			if (part_digits == 0) {
				return false;
			}
			if (colon == -1) {
				// octet, ended by '.' or ':'
				if ((part_digits > 3) || (part_value > 255) || (c == 0)) {
					return false;
				}
				if (c == '.') {
					dots++;
					if (dots > 3) {
						return false;
					}
				} else if (c == ':') {
					if (dots != 3) {
						return false;
					}
					colon = i;
				}
			} else {
				// port, must end the string
				if ((c != 0) || (part_value < 1) || (part_value > 65535)) {
					return false;
				}
			}
			part_value = 0;
			part_digits = 0;
		} else {
			return false;
		}
	}
	return (colon > -1);
}


// values passed to ServerCommand must not chain or break commands
bool is_safe_command_value(const char[] value)
{
	for (int i = 0; value[i] != 0; i++) {
		if ((value[i] == ';') || (value[i] == '"') || (value[i] == '\n') || (value[i] == '\r')) {
			return false;
		}
	}
	return true;
}


public void OnProtectAddressChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{

	if (strcmp(newVal, "") != 0) {
		if (!is_valid_protect_address(newVal)) {
			LogError("gamewe_protect_address must be IPv4:port, value rejected: %s", newVal);
			SetConVarString(cvar, "");
			return;
		}
		if (gamewe_plugin.protect_address != INVALID_HANDLE) {
			char protect_address_cvar_value[32];
			GetConVarString(gamewe_plugin.protect_address, protect_address_cvar_value, 32);
			if (strcmp(protect_address_cvar_value, "") != 0) {
				char SplitArray[2][16];
				int split_count = ExplodeString(protect_address_cvar_value, ":", SplitArray, 2, 16);
				if (split_count == 2) {
					strcopy(gamewe_plugin.protect_address_value, 32, SplitArray[0]);
					gamewe_plugin.protect_address_port = StringToInt(SplitArray[1]);
				}
			}

			if (is_safe_command_value(newVal)) {
				char log_command[192];
				Format(log_command, 192, "logaddress_add %s", newVal);
				ServerCommand(log_command);
			}

			for (int i = 0; (i <= MAXPLAYERS); i++) {
				gamewe_players[i].prole = -1;
			}
		}
	}
}


public Action ProtectLoggingChange(int args)
{
	if (gamewe_plugin.protect_address != INVALID_HANDLE) {
		char protect_address_cvar_value[192];
		GetConVarString(gamewe_plugin.protect_address, protect_address_cvar_value, 192);
		if (args >= 1) {
			char log_action[192];
			GetCmdArg(1, log_action, 192);
			if ((strcmp(log_action, "off") == 0) || (strcmp(log_action, "0") == 0)) {
				if (strcmp(protect_address_cvar_value, "") != 0) {
					LogToGame("gameWE address protection active, logging reenabled!");
					ServerCommand("log 1");
				}
			} else if ((strcmp(log_action, "on") == 0) || (strcmp(log_action, "1") == 0)) {
				for (int i = 0; (i <= MAXPLAYERS); i++) {
					gamewe_players[i].prole = -1;
				}
			}

		}
	}
	return Plugin_Continue;
}


public Action ProtectForwardingChange(int args)
{
	if (gamewe_plugin.protect_address != INVALID_HANDLE) {
		char protect_address_cvar_value[32];
		GetConVarString(gamewe_plugin.protect_address, protect_address_cvar_value, 32);
		if (strcmp(protect_address_cvar_value, "") != 0) {
			if (args == 1) {
				char log_action[192];
				GetCmdArg(1, log_action, 192);
				if ((strcmp(log_action, protect_address_cvar_value) == 0) && is_safe_command_value(protect_address_cvar_value)) {
					char log_command[192];
					Format(log_command, 192, "logaddress_add %s", protect_address_cvar_value);
					LogToGame("gameWE address protection active, logaddress readded!");
					ServerCommand(log_command);
				}
			} else if (args > 1) {
				char log_action[192];
				for (int i = 1; i <= args; i++) {
					char temp_argument[192];
					GetCmdArg(i, temp_argument, 192);
					StrCat(log_action, sizeof(log_action), temp_argument);
				}
				if ((strcmp(log_action, protect_address_cvar_value) == 0) && is_safe_command_value(protect_address_cvar_value)) {
					char log_command[192];
					Format(log_command, 192, "logaddress_add %s", protect_address_cvar_value);
					LogToGame("gameWE address protection active, logaddress readded!");
					ServerCommand(log_command);
				}
			}
		}
	}
	return Plugin_Continue;
}


public Action ProtectForwardingDelallChange(int args)
{
	if (gamewe_plugin.protect_address != INVALID_HANDLE) {
		char protect_address_cvar_value[32];
		GetConVarString(gamewe_plugin.protect_address, protect_address_cvar_value, 32);
		if ((strcmp(protect_address_cvar_value, "") != 0) && is_safe_command_value(protect_address_cvar_value)) {
			char log_command[192];
			Format(log_command, 192, "logaddress_add %s", protect_address_cvar_value);
			LogToGame("gameWE address protection active, logaddress readded!");
			ServerCommand(log_command);
		}
	}
	return Plugin_Continue;
}


public void OnBlockChatCommandsValuesChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (strcmp(newVal, "clear") == 0) {
		ClearTrie(gamewe_plugin.blocked_commands);
		LogToGame("Server triggered \"%s\"", "blocked_commands_cleared");
	} else {
		if (strcmp(newVal, "") != 0) {
			char BlockedCommands[32][64];
			int block_commands_count = ExplodeString(newVal, " ", BlockedCommands, 32, 64);
			for (int i = 0; (i < block_commands_count); i++) {
				SetTrieValue(gamewe_plugin.blocked_commands, BlockedCommands[i], 1);
			}
		}
	}
}


public void OnMessagePrefixChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	strcopy(gamewe_plugin.message_prefix_value, sizeof(gamewe_plugin.message_prefix_value), newVal);
	color_gamewe_entities(gamewe_plugin.message_prefix_value, sizeof(gamewe_plugin.message_prefix_value));
}


public Action MessagePrefixClear(int args)
{
	// the change hook empties message_prefix_value
	SetConVarString(gamewe_plugin.message_prefix, "");
	return Plugin_Handled;
}


public void OnTeamPlayChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	if (gamewe_plugin.mod_id == MOD_HL2MP) {
		hl2mp_data.teamplay_enabled = GetConVarBool(hl2mp_data.teamplay);
	}
}


public void OnTF2CriticalHitsChange(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	tf2_data.critical_hits_enabled = GetConVarBool(tf2_data.critical_hits);
	if(!tf2_data.critical_hits_enabled) {
		for(int i = 1; i <= MaxClients; i++) {
			dump_player_data(i);
		}
	}
}


public Action TF2_CalcIsAttackCritical(int attacker, int weapon, char[] weaponname, bool &result)
{
	if ((gamewe_plugin.sdkhook_available) && (attacker > 0) && (attacker <= MaxClients)) {
		int weapon_index = get_tf2_weapon_index(weaponname[TF2_WEAPON_PREFIX_LENGTH], attacker);
		if (weapon_index != -1) {
			player_weapons[attacker][weapon_index].wshots++;
		}
	}
	return Plugin_Continue;
}


void log_player_settings(int client, char verb[32], const char[] settings_name, const char[] settings_value)
{
	if (client > 0) {
		LogToGame("\"%L\" %s \"%s\" (value \"%s\")", client, verb, settings_name, settings_value);
	} else {
		LogToGame("\"%s\" %s \"%s\" (value \"%s\")", "Server", verb, settings_name, settings_value);
	}
}


void log_player_event(int client, char verb[32], char player_event[192], int additional_player = 0, int display_location = 0)
{
	if (client > 0) {
		if (display_location > 0) {
			float player_origin[3];
			GetClientAbsOrigin(client, player_origin);
			if ((additional_player > 0) && (client != additional_player)) {
				LogToGame("\"%L\" %s \"%s\" (position \"%d %d %d\") (player \"%L\")", client, verb, player_event, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]), additional_player);
			} else {
				LogToGame("\"%L\" %s \"%s\" (position \"%d %d %d\")", client, verb, player_event, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]));
			}
		} else {
			if ((additional_player > 0) && (client != additional_player)) {
				LogToGame("\"%L\" %s \"%s\" (player \"%L\")", client, verb, player_event, additional_player);
			} else {
				LogToGame("\"%L\" %s \"%s\"", client, verb, player_event);
			}
		}
	}
}


void log_player_player_event(int client, int victim, char verb[32], char player_event[192], int display_location = 0)
{
	if ((client > 0) && (victim > 0)) {
		if (display_location > 0) {
			float player_origin[3];
			GetClientAbsOrigin(client, player_origin);

			float victim_origin[3];
			GetClientAbsOrigin(victim, victim_origin);

			LogToGame("\"%L\" %s \"%s\" against \"%L\" (position \"%d %d %d\") (victim_position \"%d %d %d\")", client, verb, player_event, victim, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]), RoundFloat(victim_origin[0]), RoundFloat(victim_origin[1]), RoundFloat(victim_origin[2]));
		} else {
			LogToGame("\"%L\" %s \"%s\" against \"%L\"", client, verb, player_event, victim);
		}
	}
}


void log_team_event(char team_name[32], char team_action[192], char team_objective[192] = "")
{
	if (strcmp(team_name, "") != 0) {
		if (strcmp(team_objective, "") != 0) {
			LogToGame("Team \"%s\" triggered \"%s\" (object \"%s\")", team_name, team_action, team_objective);
		} else {
			LogToGame("Team \"%s\" triggered \"%s\"", team_name, team_action);
		}
	}
}


void log_player_location(char event[32], int client, int additional_player = 0)
{
	if (client > 0) {
		float player_origin[3];
		GetClientAbsOrigin(client, player_origin);
		if ((additional_player > 0) && (client != additional_player)) {
			float additional_player_origin[3];
			GetClientAbsOrigin(additional_player, additional_player_origin);
			LogToGame("\"%L\" located on \"%s\" (position \"%d %d %d\") against \"%L\" (victim_position \"%d %d %d\")", client, event, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]), additional_player, RoundFloat(additional_player_origin[0]), RoundFloat(additional_player_origin[1]), RoundFloat(additional_player_origin[2]));
		} else {
			LogToGame("\"%L\" located on \"%s\" (position \"%d %d %d\")", client, event, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]));
		}
	}
}


void find_player_team_slot(int team_index)
{
	if (team_index > -1) {
		ColorSlotArray[team_index] = -1;
		for (int i = 1; i <= MaxClients; i++) {
			if ((IsClientInGame(i)) && (GetClientTeam(i) == team_index)) {
				ColorSlotArray[team_index] = i;
				break;
			}
		}
	}
}


stock void validate_team_colors()
{
	for (int i = 0; (i < sizeof(ColorSlotArray)); i++) {
		int color_client = ColorSlotArray[i];
		if (color_client > 0) {
			if ((IsClientInGame(color_client)) && (GetClientTeam(color_client) != color_client)) {
				find_player_team_slot(i);
			}
		} else {
			if ((i == 2) || (i == 3)) {
				find_player_team_slot(i);
			}
		}
	}
}


public int native_color_gamewe_entities(Handle plugin, int numParams)
{
	if (numParams < 1) {
		return 0;
	}

	int message_length;
	GetNativeStringLength(1, message_length);
	if (message_length <= 0) {
		return 0;
	}

	// tags can grow (#RRGGBB colors): color in a larger buffer, write back
	// at most the caller's length
	int buffer_length = message_length + 64;
	char[] message = new char[buffer_length];
	GetNativeString(1, message, message_length + 1);

	color_gamewe_entities(message, buffer_length);
	SetNativeString(1, message, message_length + 1);

	return 1;
}


// send_key_hint shows a key hint (the box at the right). CS:GO's Panorama
// HUD does not show KeyHintText: there it is a center hint.
void send_key_hint(int client, const char[] message)
{
	if (gamewe_plugin.mod_id == MOD_CSGO) {
		PrintHintText(client, "%s", message);
		return;
	}
	Handle message_handle = StartMessageOne("KeyHintText", client);
	if (message_handle != INVALID_HANDLE) {
		if (gamewe_plugin.protobuf == 1) {
			PbAddString(message_handle, "hints", message);
		} else {
			BfWriteByte(message_handle, 1);
			BfWriteString(message_handle, message);
		}
		EndMessage();
	}
}


// csgo_chat_start puts a space before a color code at the start of a chat
// message: CS:GO ignores a color in the first byte of SayText2.
void csgo_chat_start(char[] message, int maxlen)
{
	if ((gamewe_plugin.mod_id == MOD_CSGO) && (message[0] > 0) && (message[0] < 0x10)) {
		Format(message, maxlen, " %s", message);
	}
}


// Color tags {name} for the message prefix and colored messages. The codes
// are per engine: CS:GO has fixed chat colors, the Orange Box games (CS:S,
// DoD:S, HL2:DM, TF2) take any color as \x07RRGGBB (written as #RRGGBB here),
// the other games only know default, team color, green and olive. A tag
// without a color in a game is removed.
static const char color_tag_names[][] = {
	"{default}", "{teamcolor}", "{team}", "{green}", "{lightgreen}", "{olive}",
	"{red}", "{lightred}", "{darkred}", "{blue}", "{lightblue}", "{grey}",
	"{gray}", "{yellow}", "{orange}", "{purple}", "{lime}"
};
static const char color_tag_csgo[][] = {
	"\x01", "\x03", "\x03", "\x04", "\x05", "\x05",
	"\x07", "\x0F", "\x02", "\x0C", "\x0B", "\x08",
	"\x08", "\x09", "\x10", "\x0E", "\x06"
};
static const char color_tag_orangebox[][] = {
	"\x01", "\x03", "\x03", "\x04", "#99FF99", "\x05",
	"#FF4040", "#FF8080", "#B00000", "#4D7AFF", "#99CCFF", "#CCCCCC",
	"#CCCCCC", "#FFD700", "#FFA500", "#B070FF", "#00FF00"
};
static const char color_tag_other[][] = {
	"\x01", "\x03", "\x03", "\x04", "\x03", "\x05",
	"", "", "", "", "", "",
	"", "", "", "", ""
};

void color_gamewe_tags(char[] message, int maxlen)
{
	char code[16];
	for (int i = 0; i < sizeof(color_tag_names); i++) {
		if (StrContains(message, color_tag_names[i], false) == -1) {
			continue;
		}
		if (gamewe_plugin.mod_id == MOD_CSGO) {
			strcopy(code, sizeof(code), color_tag_csgo[i]);
		} else if ((gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2)) {
			strcopy(code, sizeof(code), color_tag_orangebox[i]);
			if (code[0] == '#') {
				code[0] = 0x07;
			}
		} else {
			strcopy(code, sizeof(code), color_tag_other[i]);
		}
		ReplaceString(message, maxlen, color_tag_names[i], code, false);
	}
}

void color_gamewe_entities(char[] message, int maxlen = 192)
{
	if (StrContains(message, "{") > -1) {
		color_gamewe_tags(message, maxlen);
	}
	ReplaceString(message, maxlen, "x08", "\x08");
	ReplaceString(message, maxlen, "x07", "\x07");
	ReplaceString(message, maxlen, "x05", "\x05");
	ReplaceString(message, maxlen, "x04", "\x04");
	ReplaceString(message, maxlen, "x03", "\x03");
	ReplaceString(message, maxlen, "x01", "\x01");
	ReplaceString(message, maxlen, "x||0", "x0");
}


// The collector starts its chat lines with [gameWE]; with a message prefix
// set, the prefix (already colored) takes its place.
void apply_message_prefix(char[] message, int maxlen)
{
	if (gamewe_plugin.message_prefix_value[0] == '\0') {
		return;
	}
	int tag_length = strlen(GAMEWE_CHAT_TAG);
	if (strncmp(message, GAMEWE_CHAT_TAG, tag_length) == 0) {
		char rest[192];
		strcopy(rest, sizeof(rest), message[tag_length]);
		Format(message, maxlen, "%s\x01%s", gamewe_plugin.message_prefix_value, rest);
	}
}


public void OnClientDisconnect(int client)
{
	if (client > 0) {
		reset_player_settings(client);
		if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_ZPS)) {
			dump_player_data(client);
			reset_player_data(client);
		}
		if (IsClientInGame(client)) {
			if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD)) {
				int team_index = GetClientTeam(client);
				if (client == ColorSlotArray[team_index]) {
					ColorSlotArray[team_index] = -1;
				}
			}
		}

		if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS)) {
			if (gamewe_players[client].pspectator.stimer != INVALID_HANDLE) {
				KillTimer(gamewe_players[client].pspectator.stimer);
				gamewe_players[client].pspectator.stimer = INVALID_HANDLE;
			}
			for (int j = 0; (j <= MAXPLAYERS); j++) {
				player_messages[j][client].supdated = 1;
				strcopy(player_messages[j][client].smessage, 255, "");
			}
		}

	}
}


stock int get_team_index(char[] team_name)
{
	int loop_break = 0;
	int index = 0;
	while ((loop_break == 0) && (index < sizeof(team_list))) {
   	    if (strcmp(team_name, team_list[index], true) == 0) {
       		loop_break++;
        }
   	    index++;
	}
	if (loop_break == 0) {
		return -1;
	} else {
		return index - 1;
	}
}


public void native_display_menu(Handle plugin, int numParams)
{
	if (numParams < 4) {
		return;
	}

	int client = GetNativeCell(1);
	int time = GetNativeCell(2);

	int message_length;
	GetNativeStringLength(3, message_length);
	if (message_length <= 0) {
		return;
	}
	char[] message = new char[message_length + 1];
	GetNativeString(3, message, message_length + 1);

	int handler = GetNativeCell(4);
	display_menu(client, time, message, handler);

	return;
}


void display_menu(int player_index, int time, char[] full_message, int need_handler = 0)
{
	ReplaceString(full_message, 1024, "\\n", "\10");
	if (need_handler == 0) {
		InternalShowMenu(player_index, full_message, time);
	} else {
		InternalShowMenu(player_index, full_message, time, (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9), InternalMenuHandler);
	}
}


public void InternalMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	int client = param1;
	if (IsClientInGame(client)) {
		if (action == MenuAction_Select) {
			char player_event[192];
			IntToString(param2, player_event, 192);
			log_player_event(client, "selected", player_event);
		} else if (action == MenuAction_Cancel) {
			char player_event[192] = "cancel";
			log_player_event(client, "selected", player_event);
		}
	}
}


int get_param(int index, int argument_count)
{
	char param[128];
	if (index <= argument_count) {
		GetCmdArg(index, param, 128);
		return StringToInt(param);
	}
	return -1;
}


int get_query_id()
{
	global_query_id++;
	if (global_query_id > 65535) {
		global_query_id = 1;
	}
	return global_query_id;
}


int find_callback(int query_id)
{
	int index = -1;
	int size = GetArraySize(QueryCallbackArray);

	for (int i = 0; i < size; i++) {
		callback_data data;
		GetArrayArray(QueryCallbackArray, i, data, sizeof(data));
		if ((data.callback_data_id == query_id) && (data.callback_data_plugin != INVALID_HANDLE) && (data.callback_data_function != INVALID_FUNCTION)) {
			index = i;
			break;
		}
	}
	return index;
}


public void native_query_gamewe_stats(Handle plugin, int numParams)
{
	if (numParams < 4) {
		return;
	}
	char cb_type[255];
	GetNativeString(1, cb_type, 255);
	int cb_client = GetNativeCell(2);
	Function cb_function = GetNativeCell(3);
	int cb_payload = GetNativeCell(4);

	int cb_limit = 1;
	if (numParams >= 5) {
		cb_limit = GetNativeCell(5);
	}

	if (cb_client < 1) {
		int queryid = get_query_id();

		callback_data data;
		data.callback_data_id = queryid;
		data.callback_data_time = GetGameTime();
		data.callback_data_client = cb_client;
		data.callback_data_plugin = plugin;
		data.callback_data_function = cb_function;
		data.callback_data_payload = cb_payload;
		data.callback_data_limit = cb_limit;
		if (QueryCallbackArray != INVALID_HANDLE) {
			PushArrayArray(QueryCallbackArray, data);
		}

		char query_payload[32];
		IntToString(queryid, query_payload, 32);
		log_player_settings(cb_client, "requested", cb_type, query_payload);
	} else {
		if (IsClientInGame(cb_client)) {
			int userid = GetClientUserId(cb_client);
			if (userid > 0) {
				int queryid = get_query_id();

				callback_data data;
				data.callback_data_id = queryid;
				data.callback_data_time = GetGameTime();
				data.callback_data_client = cb_client;
				data.callback_data_plugin = plugin;
				data.callback_data_function = cb_function;
				data.callback_data_payload = cb_payload;
				data.callback_data_limit = cb_limit;

				if (QueryCallbackArray != INVALID_HANDLE) {
					PushArrayArray(QueryCallbackArray, data);

					char query_payload[32];
					IntToString(queryid, query_payload, 32);
					log_player_settings(cb_client, "requested", cb_type, query_payload);
				}
			}
		}
	}
}


void fire_stats_forward(Handle forward_handle, Handle legacy_forward_handle, int command, int client, Handle &pack)
{
	Handle forwards[2];
	forwards[0] = forward_handle;
	forwards[1] = legacy_forward_handle;
	for (int i = 0; i < sizeof(forwards); i++) {
		if ((forwards[i] != INVALID_HANDLE) && (GetForwardFunctionCount(forwards[i]) > 0)) {
			Action result;
			Call_StartForward(forwards[i]);
			Call_PushCell(command);
			Call_PushCell(client);
			Call_PushString(gamewe_plugin.message_prefix_value);
			Call_PushCellRef(pack);
			Call_Finish(result);
		}
	}
}


public Action gamewe_raw_message(int args)
{

	if (args < 1) {
		PrintToServer("Usage: gamewe_raw_message <type><array> - retrieve internal gameWE Stats data");
		return Plugin_Handled;
	}

	int argument_count = GetCmdArgs();
	int type = get_param(1, argument_count);
	switch (type) {

		case RAW_MESSAGE_CALLBACK_PLAYER, RAW_MESSAGE_RANK, RAW_MESSAGE_PLACE, RAW_MESSAGE_KDEATH, RAW_MESSAGE_SESSION_DATA: {
			if (argument_count >= 48) {
				int query_id = get_param(2, argument_count);
				int userid = get_param(3, argument_count);
				int client = GetClientOfUserId(userid);
				if (client > 0) {

					DataPack pack = new DataPack();

					// total values
					WritePackCell(pack, get_param(4, argument_count)); // rank
					WritePackCell(pack, get_param(5, argument_count)); // players
					WritePackCell(pack, get_param(6, argument_count)); // skill
					WritePackCell(pack, get_param(7, argument_count)); // kills
					WritePackCell(pack, get_param(8, argument_count)); // deaths

					char kpd_param[16];
					GetCmdArg(9, kpd_param, 16);
					WritePackFloat(pack, StringToFloat(kpd_param)); // kpd

					WritePackCell(pack, get_param(10, argument_count)); // suicides
					WritePackCell(pack, get_param(11, argument_count)); // headshots

					char hpk_param[16];
					GetCmdArg(12, hpk_param, 16);
					WritePackFloat(pack, StringToFloat(hpk_param)); // hpk

					char acc_param[16];
					GetCmdArg(13, acc_param, 16);
					WritePackFloat(pack, StringToFloat(acc_param)); // accuracy

					WritePackCell(pack, get_param(14, argument_count)); // connection_time
					WritePackCell(pack, get_param(15, argument_count)); // kill_assists
					WritePackCell(pack, get_param(16, argument_count)); // kills_assisted
					WritePackCell(pack, get_param(17, argument_count)); // points_healed
					WritePackCell(pack, get_param(18, argument_count)); // flags_captured
					WritePackCell(pack, get_param(19, argument_count)); // custom_wins
					WritePackCell(pack, get_param(20, argument_count)); // kill_streak
					WritePackCell(pack, get_param(21, argument_count)); // death_streak

					// session values
					WritePackCell(pack, get_param(22, argument_count)); // session_pos_change
					WritePackCell(pack, get_param(23, argument_count)); // session_skill_change
					WritePackCell(pack, get_param(24, argument_count)); // session_kills
					WritePackCell(pack, get_param(25, argument_count)); // session_deaths

					char session_kpd_param[16];
					GetCmdArg(26, session_kpd_param, 16);
					WritePackFloat(pack, StringToFloat(session_kpd_param)); // session_kpd

					WritePackCell(pack, get_param(27, argument_count)); // session_suicides
					WritePackCell(pack, get_param(28, argument_count)); // session_headshots

					char session_hpk_param[16];
					GetCmdArg(29, session_hpk_param, 16);
					WritePackFloat(pack, StringToFloat(session_hpk_param)); // session_hpk

					char session_acc_param[16];
					GetCmdArg(30, session_acc_param, 16);
					WritePackFloat(pack, StringToFloat(session_acc_param)); // session_accuracy

					WritePackCell(pack, get_param(31, argument_count)); // session_time
					WritePackCell(pack, get_param(32, argument_count)); // session_kill_assists
					WritePackCell(pack, get_param(33, argument_count)); // session_kills_assisted
					WritePackCell(pack, get_param(34, argument_count)); // session_points_healed
					WritePackCell(pack, get_param(35, argument_count)); // session_flags_captured
					WritePackCell(pack, get_param(36, argument_count)); // session_custom_wins
					WritePackCell(pack, get_param(37, argument_count)); // session_kill_streak
					WritePackCell(pack, get_param(38, argument_count)); // session_death_streak

					char session_fav_weapon[32];
					GetCmdArg(39, session_fav_weapon, 32);
					if (StrEqual(session_fav_weapon, "-")) {
						session_fav_weapon = "No Fav Weapon";
					}
					WritePackString(pack, session_fav_weapon); // fav weapons

					// global values
					WritePackCell(pack, get_param(40, argument_count)); // global_rank
					WritePackCell(pack, get_param(41, argument_count)); // global_players
					WritePackCell(pack, get_param(42, argument_count)); // global_skill
					WritePackCell(pack, get_param(43, argument_count)); // global_kills
					WritePackCell(pack, get_param(44, argument_count)); // global_deaths

					char global_kpd_param[16];
					GetCmdArg(45, global_kpd_param, 16);
					WritePackFloat(pack, StringToFloat(global_kpd_param)); // global_kpd

					WritePackCell(pack, get_param(46, argument_count)); // global_headshots

					char global_hpk_param[16];
					GetCmdArg(47, global_hpk_param, 16);
					WritePackFloat(pack, StringToFloat(global_hpk_param)); // global_hpk

					// country
					char country_code[16];
					GetCmdArg(48, country_code, 16);
					WritePackString(pack, country_code); // player country


					Action result;
					if (type == RAW_MESSAGE_CALLBACK_PLAYER) {
						if (query_id > 0) {
							int cb_array_index = find_callback(query_id);
							if (cb_array_index >= 0) {
								callback_data data;
								GetArrayArray(QueryCallbackArray, cb_array_index, data, sizeof(data));
								if ((data.callback_data_plugin != INVALID_HANDLE) && (data.callback_data_function != INVALID_FUNCTION)) {
									Call_StartFunction(data.callback_data_plugin, data.callback_data_function);
									Call_PushCell(RAW_MESSAGE_CALLBACK_PLAYER);

									Call_PushCell(data.callback_data_payload);
									Call_PushCell(client);

									Call_PushCell(pack);
									Call_Finish(result);

									if (data.callback_data_limit == 1) {
										RemoveFromArray(QueryCallbackArray, cb_array_index);
									}
								}
							}
						}
					} else {
						if (type == RAW_MESSAGE_RANK) {
							fire_stats_forward(gameWEStatsRankForward, gameMEStatsRankForward, type, client, pack);
						} else {
							fire_stats_forward(gameWEStatsPublicCommandForward, gameMEStatsPublicCommandForward, type, client, pack);
						}
					}

					CloseHandle(pack);
				}

			}
		}
		case RAW_MESSAGE_CALLBACK_TOP10, RAW_MESSAGE_TOP10: {
			if (argument_count >= 4) {
				int query_id = get_param(2, argument_count);
				int userid = get_param(3, argument_count);
				if (((userid > 0) && (type == RAW_MESSAGE_TOP10)) ||
   					((userid == -1) && (type == RAW_MESSAGE_CALLBACK_TOP10))) {

   					int client = GetClientOfUserId(userid);
   					if ((client < 1) && (type == RAW_MESSAGE_TOP10)) {
						return Plugin_Handled;
   					}

					DataPack pack = new DataPack();
					if (argument_count == 4) {
						WritePackCell(pack, -1); // total_players
					} else {
						int count = 0;
						for (int i = 4; (i <= argument_count); i++) {
							if (((i + 3) <= argument_count)) {
								count++;
								i = i + 3;
							}
						}
						WritePackCell(pack, count); // total_players

						int rank = 0;
						for (int i = 4; (i <= argument_count); i++) {
							if (((i + 3) <= argument_count)) {
								rank++;

								WritePackCell(pack, rank); // rank
								WritePackCell(pack, get_param(i, argument_count)); // skill

								char name[64];
								GetCmdArg((i + 1), name, 64);
								WritePackString(pack, name); // name

								char kpd_param[16];
								GetCmdArg((i + 2), kpd_param, 16);
								WritePackFloat(pack, StringToFloat(kpd_param)); // kpd

								char hpk_param[16];
								GetCmdArg((i + 3), hpk_param, 16);
								WritePackFloat(pack, StringToFloat(hpk_param)); // hpk

								i = i + 3;
							}
						}
					}

					Action result;
					if (type == RAW_MESSAGE_CALLBACK_TOP10) {
						if (query_id > 0) {
							int cb_array_index = find_callback(query_id);
							if (cb_array_index >= 0) {
								callback_data data;
								GetArrayArray(QueryCallbackArray, cb_array_index, data, sizeof(data));
								if ((data.callback_data_plugin != INVALID_HANDLE) && (data.callback_data_function != INVALID_FUNCTION)) {
									Call_StartFunction(data.callback_data_plugin, data.callback_data_function);
									Call_PushCell(RAW_MESSAGE_CALLBACK_TOP10);
									Call_PushCell(data.callback_data_payload);
									Call_PushCell(pack);
									Call_Finish(result);

									if (data.callback_data_limit == 1) {
										RemoveFromArray(QueryCallbackArray, cb_array_index);
									}
								}
							}
						}
					} else {

						fire_stats_forward(gameWEStatsTop10Forward, gameMEStatsTop10Forward, RAW_MESSAGE_TOP10, client, pack);

					}

					CloseHandle(pack);
				}
			}
		}
		case RAW_MESSAGE_CALLBACK_NEXT, RAW_MESSAGE_NEXT: {
			if (argument_count >= 4) {
				int query_id = get_param(2, argument_count);
				int userid = get_param(3, argument_count);
				int client = GetClientOfUserId(userid);
				if (client > 0) {

					DataPack pack = new DataPack();

					if (argument_count == 4) {
						WritePackCell(pack, -1); // total_players
					} else {
						int count = 0;
						for (int i = 4; (i <= argument_count); i++) {
							if (((i + 4) <= argument_count)) {
								count++;
								i = i + 4;
							}
						}
						WritePackCell(pack, count); // total_players

						for (int i = 4; (i <= argument_count); i++) {
							if (((i + 4) <= argument_count)) {

								WritePackCell(pack, get_param(i, argument_count)); // rank
								WritePackCell(pack, get_param((i + 1), argument_count)); // skill

								char name[64];
								GetCmdArg((i + 2), name, 64);
								WritePackString(pack, name); // name

								char kpd_param[16];
								GetCmdArg((i + 3), kpd_param, 16);
								WritePackFloat(pack, StringToFloat(kpd_param)); // kpd

								char hpk_param[16];
								GetCmdArg((i + 4), hpk_param, 16);
								WritePackFloat(pack, StringToFloat(hpk_param)); // hpk

								i = i + 4;
							}
						}
					}

					Action result;
					if (type == RAW_MESSAGE_CALLBACK_NEXT) {
						if (query_id > 0) {
							int cb_array_index = find_callback(query_id);
							if (cb_array_index >= 0) {
								callback_data data;
								GetArrayArray(QueryCallbackArray, cb_array_index, data, sizeof(data));
								if ((data.callback_data_plugin != INVALID_HANDLE) && (data.callback_data_function != INVALID_FUNCTION)) {
									Call_StartFunction(data.callback_data_plugin, data.callback_data_function);
									Call_PushCell(RAW_MESSAGE_CALLBACK_NEXT);
									Call_PushCell(data.callback_data_payload);
									Call_PushCell(client);
									Call_PushCell(pack);
									Call_Finish(result);

									if (data.callback_data_limit == 1) {
										RemoveFromArray(QueryCallbackArray, cb_array_index);
									}
								}
							}
						}
					} else {

						fire_stats_forward(gameWEStatsNextForward, gameMEStatsNextForward, RAW_MESSAGE_NEXT, client, pack);

					}
					CloseHandle(pack);
				}
			}
		}
		case RAW_MESSAGE_CALLBACK_INT_CLOSE: {
			if (argument_count >= 2) {
				int query_id = get_param(2, argument_count);
				int cb_array_index = find_callback(query_id);
				if (cb_array_index >= 0) {
					RemoveFromArray(QueryCallbackArray, cb_array_index);
				}
			}
		}
		case RAW_MESSAGE_CALLBACK_INT_SPECTATOR: {
			if (argument_count >= 5) {
				int query_id = get_param(2, argument_count);

				int caller[MAXPLAYERS + 1] = {-1, ...};
				char caller_id[512];
				GetCmdArg(3, caller_id, 512);
				if (StrContains(caller_id, ",") > -1) {
					char[][] CallerRecipients = new char[MaxClients][16];
					int recipient_count = ExplodeString(caller_id, ",", CallerRecipients, MaxClients, 16);
					for (int i = 0; (i < recipient_count); i++) {
						caller[i] = GetClientOfUserId(StringToInt(CallerRecipients[i]));
					}
				} else {
					caller[0] = GetClientOfUserId(StringToInt(caller_id));
				}

				int target[MAXPLAYERS + 1] = {-1, ...};
				char target_id[512];
				GetCmdArg(4, target_id, 512);
				if (StrContains(target_id, ",") > -1) {
					char[][] TargetRecipients = new char[MaxClients][16];
					int recipient_count = ExplodeString(target_id, ",", TargetRecipients, MaxClients, 16);
					for (int i = 0; (i < recipient_count); i++) {
						target[i] = GetClientOfUserId(StringToInt(TargetRecipients[i]));
					}
				} else {
					target[0] = GetClientOfUserId(StringToInt(target_id));
				}


				if ((caller[0] > -1) && (target[0] > -1) && (query_id > 0)) {
					char message[1024];
					GetCmdArg(5, message, 1024);

					int cb_array_index = find_callback(query_id);
					if (cb_array_index >= 0) {
						callback_data data;
						GetArrayArray(QueryCallbackArray, cb_array_index, data, sizeof(data));
						if ((data.callback_data_plugin != INVALID_HANDLE) && (data.callback_data_function != INVALID_FUNCTION)) {
							Action result;
							Call_StartFunction(data.callback_data_plugin, data.callback_data_function);
							Call_PushCell(RAW_MESSAGE_CALLBACK_INT_SPECTATOR);
							Call_PushCell(data.callback_data_payload);
							Call_PushArray(caller, MAXPLAYERS + 1);
							Call_PushArray(target, MAXPLAYERS + 1);
							Call_PushString(gamewe_plugin.message_prefix_value);
							Call_PushString(message);
							Call_Finish(result);

							if (data.callback_data_limit == 1) {
								RemoveFromArray(QueryCallbackArray, cb_array_index);
							}
						}
					}

				}
			}
		}

	}

	return Plugin_Handled;
}


// Copies the command text after the first skip_args arguments into message,
// without surrounding quotes. Leading arguments may be quoted or not, so both
// gamewe_psay 2 0 "text" and gamewe_psay "2" 0 "text" work.
void get_cmd_message(int skip_args, char[] message, int maxlen)
{
	char argument_string[1024];
	GetCmdArgString(argument_string, sizeof(argument_string));

	int pos = 0;
	char argument[256];
	for (int i = 0; i < skip_args; i++) {
		int next = BreakString(argument_string[pos], argument, sizeof(argument));
		if (next == -1) {
			message[0] = '\0';
			return;
		}
		pos += next;
	}

	strcopy(message, maxlen, argument_string[pos]);
	TrimString(message);
	StripQuotes(message);
}


public Action gamewe_psay(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_psay <userid><colored><message> - sends private message");
		return Plugin_Handled;
	}

	char client_id[192];
	GetCmdArg(1, client_id, 192);
	if (StrContains(client_id, ",") > -1) {
		char[][] MessageRecipients = new char[MaxClients][16];
		int recipient_count = ExplodeString(client_id, ",", MessageRecipients, MaxClients, 16);
		for (int i = 0; (i < recipient_count); i++) {
			PushStackCell(gamewe_plugin.message_recipients, StringToInt(MessageRecipients[i]));
		}
	} else {
		PushStackCell(gamewe_plugin.message_recipients, StringToInt(client_id));
	}

	char colored_param[32];
	GetCmdArg(2, colored_param, 32);
	int is_colored = 0;
	int ignore_param = 0;
	if (strcmp(colored_param, "1") == 0) {
		is_colored = 1;
		ignore_param = 1;
	} else if (strcmp(colored_param, "2") == 0) {
		is_colored = 2;
		ignore_param = 1;
	} else if (strcmp(colored_param, "3") == 0) {
		is_colored = 3;
		ignore_param = 1;
	} else if (strcmp(colored_param, "0") == 0) {
		ignore_param = 1;
	}

	char client_message[192];
	get_cmd_message((ignore_param == 1) ? 2 : 1, client_message, sizeof(client_message));
	apply_message_prefix(client_message, sizeof(client_message));

	if (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
		int color_index = -1;
		if ((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_DODS) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_TF2) || (gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII) || (gamewe_plugin.mod_id == MOD_INSMOD)) {

			if (is_colored > 1) {
				validate_team_colors();
				if (is_colored == 2) {
					if (ColorSlotArray[2] > -1) {
						color_index = ColorSlotArray[2];
					}
				} else if (is_colored == 3) {
					if (ColorSlotArray[3] > -1) {
						color_index = ColorSlotArray[3];
					}
				}
				color_gamewe_entities(client_message);
			} else if (is_colored == 1) {
				color_gamewe_entities(client_message);
			}
			csgo_chat_start(client_message, sizeof(client_message));

			bool setupColorForRecipients = false;
			if (color_index == -1) {
				setupColorForRecipients = true;
			}

			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					if (setupColorForRecipients == true) {
						color_index = player_index;
					}

					if (gamewe_plugin.mod_id == MOD_DODS) {
						PrintToChat(player_index, "%s", client_message);
					} else {
						Handle message_handle = StartMessageOne("SayText2", player_index);
						if (message_handle != INVALID_HANDLE) {
							if (gamewe_plugin.protobuf == 1) {
								PbSetInt(message_handle, "ent_idx", color_index);
								PbSetBool(message_handle, "chat", false);
								PbSetString(message_handle, "msg_name", client_message);
								PbAddString(message_handle, "params", "");
								PbAddString(message_handle, "params", "");
								PbAddString(message_handle, "params", "");
								PbAddString(message_handle, "params", "");
							} else {
								BfWriteByte(message_handle, color_index);
								BfWriteByte(message_handle, 0);
								BfWriteString(message_handle, client_message);
							}
							EndMessage();
						}
					}
				}
			}
		} else {
			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					PrintToChat(player_index, "%s", client_message);
				}
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_csay(int args)
{
	if (args < 1) {
		PrintToServer("Usage: gamewe_csay <message> - display center message");
		return Plugin_Handled;
	}

	char display_message[192];
	get_cmd_message(0, display_message, sizeof(display_message));

	if (strcmp(display_message, "") != 0) {
		PrintCenterTextAll("%s", display_message);
	}

	return Plugin_Handled;
}


public Action gamewe_msay(int args)
{
	if (args < 3) {
		PrintToServer("Usage: gamewe_msay <time><userid><message> - sends hud message");
		return Plugin_Handled;
	}

	if (gamewe_plugin.mod_id == MOD_HL2MP) {
		return Plugin_Handled;
	}

	char display_time[16];
	GetCmdArg(1, display_time, 16);

	char client_id[32];
	GetCmdArg(2, client_id, 32);

	char handler_param[32];
	GetCmdArg(3, handler_param, 32);

	int need_handler = 0;
	if ((strcmp(handler_param, "1") == 0) || (strcmp(handler_param, "0") == 0)) {
		need_handler = 1;
	}

	char client_message[1024];
	get_cmd_message((need_handler == 1) ? 3 : 2, client_message, sizeof(client_message));

	int time = StringToInt(display_time);
	if (time <= 0) {
		time = 10;
	}

	int client = StringToInt(client_id);
	if (client > 0) {
		int player_index = GetClientOfUserId(client);
		if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
			if (strcmp(client_message, "") != 0) {
				display_menu(player_index, time, client_message, need_handler);
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_tsay(int args)
{
	if (args < 3) {
		PrintToServer("Usage: gamewe_tsay <time><userid><message> - sends hud message");
		return Plugin_Handled;
	}

	char display_time[16];
	GetCmdArg(1, display_time, 16);

	char client_id[32];
	GetCmdArg(2, client_id, 32);

	char client_message[192];
	get_cmd_message(2, client_message, sizeof(client_message));

	int client = StringToInt(client_id);
	if ((client > 0) && (strcmp(client_message, "") != 0)) {
		int player_index = GetClientOfUserId(client);
		if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
			KeyValues values = new KeyValues("msg");
			KvSetString(values, "title", client_message);
			KvSetNum(values, "level", 1);
			KvSetString(values, "time", display_time);
			CreateDialog(player_index, values, DialogType_Msg);
			CloseHandle(values);
		}
	}

	return Plugin_Handled;
}


public Action gamewe_hint(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_hint <userid><message> - send hint message");
		return Plugin_Handled;
	}

	if (gamewe_plugin.mod_id == MOD_HL2MP) {
		return Plugin_Handled;
	}

	char client_id[512];
	GetCmdArg(1, client_id, 512);
	if (StrContains(client_id, ",") > -1) {
		char[][] MessageRecipients = new char[MaxClients][16];
		int recipient_count = ExplodeString(client_id, ",", MessageRecipients, MaxClients, 16);
		for (int i = 0; (i < recipient_count); i++) {
			PushStackCell(gamewe_plugin.message_recipients, StringToInt(MessageRecipients[i]));
		}
	} else {
		PushStackCell(gamewe_plugin.message_recipients, StringToInt(client_id));
	}

	char client_message[192];
	get_cmd_message(1, client_message, sizeof(client_message));

	if (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
		if (strcmp(client_message, "") != 0) {
			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					PrintHintText(player_index, "%s", client_message);
				}
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_khint(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_khint <userid><message> - send khint message");
		return Plugin_Handled;
	}

	char client_id[512];
	GetCmdArg(1, client_id, 512);
	if (StrContains(client_id, ",") > -1) {
		char[][] MessageRecipients = new char[MaxClients][16];
		int recipient_count = ExplodeString(client_id, ",", MessageRecipients, MaxClients, 16);
		for (int i = 0; (i < recipient_count); i++) {
			PushStackCell(gamewe_plugin.message_recipients, StringToInt(MessageRecipients[i]));
		}
	} else {
		PushStackCell(gamewe_plugin.message_recipients, StringToInt(client_id));
	}

	char client_message[255];
	get_cmd_message(1, client_message, sizeof(client_message));
	ReplaceString(client_message, 255, "\\n", "\10");

	if (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
		if (strcmp(client_message, "") != 0) {
			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					send_key_hint(player_index, client_message);
				}
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_browse(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_browse <userid><url> - open client ingame browser");
		return Plugin_Handled;
	}

	char client_url[192];
	GetCmdArg(2, client_url, 192);
	if ((StrContains(client_url, "http://", false) != 0) && (StrContains(client_url, "https://", false) != 0)) {
		PrintToServer("gamewe_browse: only http:// and https:// URLs are allowed");
		return Plugin_Handled;
	}

	char client_id[512];
	GetCmdArg(1, client_id, 512);
	if (StrContains(client_id, ",") > -1) {
		char[][] MessageRecipients = new char[MaxClients][16];
		int recipient_count = ExplodeString(client_id, ",", MessageRecipients, MaxClients, 16);
		for (int i = 0; (i < recipient_count); i++) {
			PushStackCell(gamewe_plugin.message_recipients, StringToInt(MessageRecipients[i]));
		}
	} else {
		PushStackCell(gamewe_plugin.message_recipients, StringToInt(client_id));
	}

	if (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
		if (strcmp(client_url, "") != 0) {
			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					if (gamewe_plugin.mod_id == MOD_CSGO) {
						// CS:GO shows no web pages in the MOTD panel any more
						PrintToChat(player_index, "%s", client_url);
					} else {
						ShowMOTDPanel(player_index, "gameWE", client_url, MOTDPANEL_TYPE_URL);
					}
				}
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_swap(int args)
{
	if (args < 1) {
		PrintToServer("Usage: gamewe_swap <userid> - swaps players to the opposite team (css only)");
		return Plugin_Handled;
	}

	if ((gamewe_plugin.mod_id != MOD_CSS) && (gamewe_plugin.mod_id != MOD_CSGO)) {
		return Plugin_Handled;
	}

	char client_id[32];
	GetCmdArg(1, client_id, 32);

	int client = StringToInt(client_id);
	if (client > 0) {
		int player_index = GetClientOfUserId(client);
		if ((player_index > 0) && (IsClientInGame(player_index))) {
			swap_player(player_index);
		}
	}
	return Plugin_Handled;
}


public Action gamewe_redirect(int args)
{
	if (args < 3) {
		PrintToServer("Usage: gamewe_redirect <time><userid><address><reason> - asks player to be redirected to specified gameserver");
		return Plugin_Handled;
	}

	char display_time[16];
	GetCmdArg(1, display_time, 16);

	char client_id[512];
	GetCmdArg(2, client_id, 512);
	if (StrContains(client_id, ",") > -1) {
		char[][] MessageRecipients = new char[MaxClients][16];
		int recipient_count = ExplodeString(client_id, ",", MessageRecipients, MaxClients, 16);
		for (int i = 0; (i < recipient_count); i++) {
			PushStackCell(gamewe_plugin.message_recipients, StringToInt(MessageRecipients[i]));
		}
	} else {
		PushStackCell(gamewe_plugin.message_recipients, StringToInt(client_id));
	}

	char server_address[192];
	GetCmdArg(3, server_address, 192);

	char redirect_reason[192];
	get_cmd_message(3, redirect_reason, sizeof(redirect_reason));

	if (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
		if (strcmp(server_address, "") != 0) {

			while (IsStackEmpty(gamewe_plugin.message_recipients) == false) {
				int recipient_client = -1;
				PopStackCell(gamewe_plugin.message_recipients, recipient_client);

				int player_index = GetClientOfUserId(recipient_client);
				if ((player_index > 0) && (!IsFakeClient(player_index)) && (IsClientInGame(player_index))) {
					KeyValues top_values = new KeyValues("msg");
					KvSetString(top_values, "title", redirect_reason);
					KvSetNum(top_values, "level", 1);
					KvSetString(top_values, "time", display_time);
					CreateDialog(player_index, top_values, DialogType_Msg);
					CloseHandle(top_values);

					float display_time_float;
					display_time_float = StringToFloat(display_time);
					DisplayAskConnectBox(player_index, display_time_float, server_address);
				}
			}
		}
	}

	return Plugin_Handled;
}


public Action gamewe_player_action(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_player_action <client><action> - trigger player action to be handled from gameWE");
		return Plugin_Handled;
	}

	char client_id[32];
	GetCmdArg(1, client_id, 32);

	char player_action[192];
	GetCmdArg(2, player_action, 192);

	int client = StringToInt(client_id);
	if (client > 0) {
		log_player_event(client, "triggered", player_action);
	}

	return Plugin_Handled;
}


public Action gamewe_team_action(int args)
{
	if (args < 2) {
		PrintToServer("Usage: gamewe_team_action <team_name><action>(objective) - trigger team action to be handled from gameWE");
		return Plugin_Handled;
	}

	char team_name[32];
	GetCmdArg(1, team_name, 32);

	char team_action[192];
	GetCmdArg(2, team_action, 192);

	if (args > 2) {
		char team_objective[192];
		GetCmdArg(3, team_objective, 192);
		log_team_event(team_name, team_action, team_objective);
	} else {
		log_team_event(team_name, team_action);
	}

	return Plugin_Handled;
}


public Action gamewe_world_action(int args)
{
	if (args < 1) {
		PrintToServer("Usage: gamewe_world_action <action> - trigger world action to be handled from gameWE");
		return Plugin_Handled;
	}

	char world_action[192];
	GetCmdArg(1, world_action, 192);

	LogToGame("World triggered \"%s\"", world_action);

	return Plugin_Handled;
}


// true if the player may send the next gameWE command to the collector;
// a player who floods is not logged, so the collector does not answer
bool gamewe_trigger_allowed(int client)
{
	float now = GetGameTime();
	float cooldown = gamewe_plugin.chat_cooldown.FloatValue;
	if ((cooldown <= 0.0) || (gamewe_last_trigger[client] <= 0.0) || ((now - gamewe_last_trigger[client]) >= cooldown) || (now < gamewe_last_trigger[client])) {
		gamewe_last_trigger[client] = now;
		return true;
	}
	return false;
}


int is_command_blocked(char[] command)
{
	int index;
	if(GetTrieValue(gamewe_plugin.blocked_commands, command, index)) {
		return 1;
	}
	return 0;
}


// true for the chat commands that open the settings menu
bool is_settings_command(const char[] command)
{
	int start = ((command[0] == '/') || (command[0] == '!')) ? 1 : 0;
	return start == 1 && strcmp(command[start], "gamewe_settings") == 0;
}

// true for the chat commands that open the gameWE menu (gameME names included)
bool is_menu_command(const char[] command)
{
	int start = ((command[0] == '/') || (command[0] == '!')) ? 1 : 0;
	return (strcmp(command[start], "gamewe") == 0) || (strcmp(command[start], "gamewe_menu") == 0) ||
	       (strcmp(command[start], "gameme") == 0) || (strcmp(command[start], "gameme_menu") == 0);
}


public Action gamewe_block_commands(int client, int args)
{
	if ((client <= 0) || !IsClientInGame(client)) {
		return Plugin_Continue;
	}

	char user_command[192];
	GetCmdArgString(user_command, 192);

	char origin_command[192];
	int start_index = 0;
	int command_length = strlen(user_command);
	if (command_length == 0) {
		return Plugin_Continue;
	}
	if (user_command[0] == 34)	{
		start_index = 1;
		if (user_command[command_length - 1] == 34)	{
			user_command[command_length - 1] = 0;
		}
	}
	strcopy(origin_command, 192, user_command[start_index]);

	if (is_settings_command(user_command[start_index])) {
		// sm_gamewe_settings opens the menu; not logged, so the collector
		// does not answer in chat as well.
		return Plugin_Stop;
	}
	if (is_menu_command(user_command[start_index])) {
		DisplayMenu(gamewe_plugin.menu_main, client, MENU_TIME_FOREVER);
	}
	// "/rank" is silent: the plugin logs it itself. "!rank" and "rank" stay
	// in chat and the engine logs them.
	if ((user_command[start_index] == '/') && (is_command_blocked(user_command[start_index]) > 0)) {
		if (gamewe_trigger_allowed(client)) {
			log_player_event(client, "say", origin_command);
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}


public Action gameWE_Event_PlyDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));

	if (attacker > 0) {
		int headshot = 0;
		headshot = GetEventBool(event, "headshot");

		if (((gamewe_plugin.mod_id == MOD_CSGO) || (gamewe_plugin.mod_id == MOD_CSS) || (gamewe_plugin.mod_id == MOD_CSP)) && (victim > 0)) {
			if (headshot == 1) {
				int player_team_index = GetClientTeam(attacker);
				int victim_team_index = GetClientTeam(victim);
				if (victim_team_index != player_team_index) {
					log_player_event(attacker, "triggered", "headshot");
				}
			}
			if ((gamewe_plugin.log_locations == 1) && ((gamewe_plugin.mod_id != MOD_CSP))) {
				if (attacker != victim) {
					log_player_location("kill", attacker, victim);
				} else {
					log_player_location("suicide", attacker);
				}
			}
		}

		if ((gamewe_plugin.mod_id == MOD_L4D) || (gamewe_plugin.mod_id == MOD_L4DII)) {
			if (headshot == 1) {
				log_player_event(attacker, "triggered", "headshot");
			}
			if (gamewe_plugin.mod_id == MOD_L4DII) {
				char weapon[32];
				GetEventString(event, "weapon", weapon, 32);
				if (strncmp(weapon, "melee", 5) == 0) {
					int new_weapon_index = GetEntDataEnt2(attacker, l4dii_data.active_weapon_offset);
					if (IsValidEdict(new_weapon_index)) {
						GetEdictClassname(new_weapon_index, weapon, 32);
						if (strncmp(weapon[7], "melee", 5) == 0) {
							GetEntPropString(new_weapon_index, Prop_Data, "m_strMapSetScriptName", weapon, 32);
							SetEventString(event, "weapon", weapon);
						}
					}
				}
			}
		}

		if (gamewe_plugin.mod_id == MOD_HL2MP) {
			char weapon[32];
			GetEventString(event, "weapon", weapon, 32);
			if (strcmp(weapon, "crossbow_bolt") == 0) {
				if (hl2mp_players[victim].nextbow_hitgroup == HITGROUP_HEAD) {
					log_player_event(attacker, "triggered", "headshot");
				}
			} else {
				if (hl2mp_players[victim].next_hitgroup == HITGROUP_HEAD) {
					log_player_event(attacker, "triggered", "headshot");
				}
			}
		}

		if (gamewe_plugin.mod_id == MOD_ZPS) {
			if (zps_players[victim].next_hitgroup_zps == HITGROUP_HEAD) {
				log_player_event(attacker, "triggered", "headshot");
			}
		}

		if (gamewe_plugin.mod_id == MOD_TF2) {
			int customkill = GetEventInt(event, "customkill");
			int weapon = GetEventInt(event, "weaponid");
			switch (customkill) {
				case TF_CUSTOM_BURNING_ARROW, TF_CUSTOM_FLYINGBURN: {
					char log_weapon[64];
					GetEventString(event, "weapon_logclassname", log_weapon, 64);
					if (log_weapon[0] != 'd') {
						SetEventString(event, "weapon_logclassname", "tf_projectile_arrow_fire");
					}
				}
				case TF_CUSTOM_TAUNT_UBERSLICE: {
					if (weapon == TF_WEAPON_BONESAW) {
						SetEventString(event, "weapon_logclassname", "taunt_medic");
						SetEventString(event, "weapon", "taunt_medic");
					}
				}
				case TF_CUSTOM_DECAPITATION_BOSS: {
					log_player_event(attacker, "triggered", "killed_by_horseman");
				}
			}
		}

		if (gamewe_plugin.log_locations == 1) {
			if (((gamewe_plugin.mod_id == MOD_INSMOD) || (gamewe_plugin.mod_id == MOD_HL2MP) || (gamewe_plugin.mod_id == MOD_DODS)) && (victim > 0)) {
				if (attacker != victim) {
					log_player_location("kill", attacker, victim);
				}
			}
		}

	}

	return Plugin_Continue;
}


public Action gameWE_Event_PlyTeamChange(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	if (userid > 0) {
		int player_index = GetClientOfUserId(userid);
		if (player_index > 0) {
			for (int i = 0; (i < sizeof(ColorSlotArray)); i++) {
				int color_client = ColorSlotArray[i];
				if (color_client > -1) {
					if (color_client == player_index) {
						ColorSlotArray[i] = -1;
					}
				}
			}
		}
	}
	return Plugin_Continue;
}


public Action gameWE_Event_PlyBombDropped(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Dropped_The_Bomb", player);
		}

		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}

	return Plugin_Continue;
}


public Action gameWE_Event_PlyBombPickup(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Got_The_Bomb", player);
		}
		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}

	return Plugin_Continue;
}


public Action gameWE_Event_PlyBombPlanted(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Planted_The_Bomb", player);
		}
		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}

	return Plugin_Continue;
}


public Action gameWE_Event_PlyBombDefused(Event event, const char[] name, bool dontBroadcast)
{
	int player   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Defused_The_Bomb", player);
		}

		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}
	return Plugin_Continue;
}


public Action gameWE_Event_PlyHostageKill(Event event, const char[] name, bool dontBroadcast)
{
	int player   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Killed_A_Hostage", player);
		}

		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}
	return Plugin_Continue;
}


public Action gameWE_Event_PlyHostageResc(Event event, const char[] name, bool dontBroadcast)
{
	int player   = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		if (gamewe_plugin.log_locations == 1) {
			log_player_location("Rescued_A_Hostage", player);
		}

		if (gamewe_plugin.display_spectator == 1) {
			for (int i = 0; (i <= MAXPLAYERS); i++) {
				player_messages[i][player].supdated = 1;
			}
		}
	}
	return Plugin_Continue;
}


void swap_player(int player_index)
{
	if (IsClientInGame(player_index)) {
		int player_team_index = GetClientTeam(player_index);
		char player_team[32];
		player_team = team_list[player_team_index];

		if (strcmp(player_team, "CT") == 0) {
			if (IsPlayerAlive(player_index)) {
				CS_SwitchTeam(player_index, CS_TEAM_T);
				CS_RespawnPlayer(player_index);
				if (gamewe_plugin.mod_id == MOD_CSS) {
					int new_model = GetRandomInt(0, 3);
					SetEntityModel(player_index, css_ts_models[new_model]);
				} else if (gamewe_plugin.mod_id == MOD_CSGO) {
					CS_UpdateClientModel(player_index);
				}
			} else {
				ChangeClientTeam(player_index, CS_TEAM_T);
			}
		} else if (strcmp(player_team, "TERRORIST") == 0) {
			if (IsPlayerAlive(player_index)) {
				CS_SwitchTeam(player_index, CS_TEAM_CT);
				CS_RespawnPlayer(player_index);
				if (gamewe_plugin.mod_id == MOD_CSS) {
					int new_model = GetRandomInt(0, 3);
					SetEntityModel(player_index, css_ct_models[new_model]);
				} else if (gamewe_plugin.mod_id == MOD_CSGO) {
					CS_UpdateClientModel(player_index);
				}
				int weapon_entity = GetPlayerWeaponSlot(player_index, 4);
				if (weapon_entity > 0) {
					char class_name[32];
					GetEdictClassname(weapon_entity, class_name, 32);
					if (strcmp(class_name, "weapon_c4") == 0) {
						RemovePlayerItem(player_index, weapon_entity);
					}
				}
			} else {
				ChangeClientTeam(player_index, CS_TEAM_CT);
			}
		}
	}
}


public void CreateGameWEMenuMain(Menu &MenuHandle)
{
	MenuHandle = CreateMenu(gameWEMainCommandHandler, MenuAction_Display | MenuAction_DisplayItem  | MenuAction_Select | MenuAction_Cancel);

	if (gamewe_plugin.mod_id == MOD_HL2MP) {

		SetMenuTitle(MenuHandle, "gameWE - Main Menu");

		AddMenuItem(MenuHandle, "IngameMenu_Menu1",  "Display Rank");
		AddMenuItem(MenuHandle, "IngameMenu_Menu2",  "Next Players");
		AddMenuItem(MenuHandle, "IngameMenu_Menu3",  "Top10 Players");
		AddMenuItem(MenuHandle, "IngameMenu_Menu5",  "Console Events");
		AddMenuItem(MenuHandle, "IngameMenu_Menu17", "Settings");

	} else {

		SetMenuTitle(MenuHandle, "gameWE - Main Menu");

		AddMenuItem(MenuHandle, "IngameMenu_Menu1",  "Display Rank");
		AddMenuItem(MenuHandle, "IngameMenu_Menu2",  "Next Players");
		AddMenuItem(MenuHandle, "IngameMenu_Menu3",  "Top10 Players");
		AddMenuItem(MenuHandle, "IngameMenu_Menu7",  "Clans Ranking");
		AddMenuItem(MenuHandle, "IngameMenu_Menu8",  "Server Status");
		AddMenuItem(MenuHandle, "IngameMenu_Menu9",  "Statsme");

		AddMenuItem(MenuHandle, "IngameMenu_Menu5",  "Console Events");
		AddMenuItem(MenuHandle, "IngameMenu_Menu10", "Weapon Usage");
		AddMenuItem(MenuHandle, "IngameMenu_Menu11", "Weapons Accuracy");
		AddMenuItem(MenuHandle, "IngameMenu_Menu12", "Weapons Targets");
		AddMenuItem(MenuHandle, "IngameMenu_Menu13", "Player Kills");

		AddMenuItem(MenuHandle, "IngameMenu_Menu14", "VAC Cheaterlist");
		AddMenuItem(MenuHandle, "IngameMenu_Menu15", "Display Help");
		AddMenuItem(MenuHandle, "IngameMenu_Menu17", "Settings");
	}

	SetMenuPagination(MenuHandle, 8);
}


// The player's settings. The ranking entry is answered by the collector (the
// plugin has no database): it hides or shows the player, depending on the
// state the collector sent last (gamewe_hidestate), and switches when the
// state is not known yet. The display entries are kept by the plugin
// (clientprefs cookies): selecting one switches to the next value and shows
// the menu again with the current value.
public void CreateGameWEMenuSettings(Menu &MenuHandle)
{
	MenuHandle = CreateMenu(gameWESettingsCommandHandler, MenuAction_Display | MenuAction_DisplayItem | MenuAction_DrawItem | MenuAction_Select | MenuAction_Cancel);

	SetMenuTitle(MenuHandle, "gameWE - Settings");

	AddMenuItem(MenuHandle, "SettingsMenu_Ranking", "Ranking");
	if (mod_has_damage_display()) {
		AddMenuItem(MenuHandle, "SettingsMenu_Damage", "Damage display");
	}
	if (mod_has_spectatorinfo()) {
		AddMenuItem(MenuHandle, "SettingsMenu_Spectator", "Spectator info");
	}

	SetMenuPagination(MenuHandle, 8);
}


// name of a damage display mode in the player's language
void format_damage_mode(int client, int mode, char[] buffer, int maxlen)
{
	if (mode == 1) {
		Format(buffer, maxlen, "%T", "SettingsValue_Menu", client);
	} else if (mode == 2) {
		Format(buffer, maxlen, "%T", "SettingsValue_Chat", client);
	} else {
		Format(buffer, maxlen, "%T", "SettingsValue_Off", client);
	}
}


// current value of a settings entry as shown in the menu
void format_setting_value(int client, const char[] info, char[] buffer, int maxlen)
{
	char name[64];
	if (strcmp(info, "SettingsMenu_Damage") == 0) {
		if (gamewe_plugin.damage_display == 0) {
			Format(buffer, maxlen, "%T", "SettingsValue_Disabled", client);
		} else if (gamewe_player_settings[client].damage_display == SETTING_SERVER_DEFAULT) {
			format_damage_mode(client, get_damage_display_mode(client), name, sizeof(name));
			Format(buffer, maxlen, "%T", "SettingsValue_Default", client, name);
		} else {
			format_damage_mode(client, gamewe_player_settings[client].damage_display, buffer, maxlen);
		}
	} else {
		if (gamewe_plugin.display_spectator == 0) {
			Format(buffer, maxlen, "%T", "SettingsValue_Disabled", client);
		} else {
			if (is_spectatorinfo_enabled(client)) {
				Format(name, sizeof(name), "%T", "SettingsValue_On", client);
			} else {
				Format(name, sizeof(name), "%T", "SettingsValue_Off", client);
			}
			if (gamewe_player_settings[client].spectatorinfo == SETTING_SERVER_DEFAULT) {
				Format(buffer, maxlen, "%T", "SettingsValue_Default", client, name);
			} else {
				strcopy(buffer, maxlen, name);
			}
		}
	}
}


public int gameWESettingsCommandHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_DisplayItem) {

		char info[64];
		GetMenuItem(menu, param2, info, sizeof(info), _, "", 0);

		char buffer[255];
		if ((strcmp(info, "SettingsMenu_Damage") == 0) || (strcmp(info, "SettingsMenu_Spectator") == 0)) {
			char value[128];
			format_setting_value(param1, info, value, sizeof(value));
			Format(buffer, sizeof(buffer), "%T", info, param1, value);
		} else if (strcmp(info, "SettingsMenu_Ranking") == 0) {
			int hide_state = gamewe_player_settings[param1].hideranking;
			if (hide_state == 0) {
				Format(buffer, sizeof(buffer), "%T", "SettingsMenu_Hide", param1);
			} else if (hide_state == 3) {
				Format(buffer, sizeof(buffer), "%T", "SettingsMenu_Show", param1);
			} else if (hide_state == HIDERANKING_UNKNOWN) {
				Format(buffer, sizeof(buffer), "%T", "SettingsMenu_Ranking", param1);
			} else {
				Format(buffer, sizeof(buffer), "%T", "SettingsMenu_RankingLocked", param1);
			}
		} else {
			Format(buffer, sizeof(buffer), "%T", info, param1);
		}

		return RedrawMenuItem(buffer);

	} else if (action == MenuAction_DrawItem) {

		char info[64];
		int style;
		GetMenuItem(menu, param2, info, sizeof(info), style, "", 0);

		// the server switched the feature off: show it, but it cannot be changed
		if (((strcmp(info, "SettingsMenu_Damage") == 0) && (gamewe_plugin.damage_display == 0)) ||
		    ((strcmp(info, "SettingsMenu_Spectator") == 0) && (gamewe_plugin.display_spectator == 0))) {
			return ITEMDRAW_DISABLED;
		}
		// hidden by an admin or banned: only an admin can change it
		if ((strcmp(info, "SettingsMenu_Ranking") == 0) &&
		    ((gamewe_player_settings[param1].hideranking == 1) || (gamewe_player_settings[param1].hideranking == 2))) {
			return ITEMDRAW_DISABLED;
		}
		return style;

	} else if (action == MenuAction_Display) {

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", "SettingsMenu_Caption", param1);

		Panel panel = view_as<Panel>(param2);
		SetPanelTitle(panel, buffer);

	} else if (action == MenuAction_Cancel) {

		// closed by the player: do not open it again when the state arrives
		if ((param2 == MenuCancel_Exit) || (param2 == MenuCancel_ExitBack)) {
			gamewe_player_settings[param1].hideranking_wait = false;
		}

	} else if (action == MenuAction_Select) {

		if (IsClientInGame(param1)) {
			char info[64];
			GetMenuItem(menu, param2, info, sizeof(info), _, "", 0);

			if (strcmp(info, "SettingsMenu_Ranking") == 0) {
				int hide_state = gamewe_player_settings[param1].hideranking;
				bool sent;
				if (hide_state == 0) {
					sent = make_player_command(param1, "/gamewe_hideranking 1");
				} else if (hide_state == 3) {
					sent = make_player_command(param1, "/gamewe_hideranking 0");
				} else {
					sent = make_player_command(param1, "/gamewe_hideranking");
				}
				// the collector answers with the new state: show the menu with it
				gamewe_player_settings[param1].hideranking_wait = sent;
			} else if ((strcmp(info, "SettingsMenu_Damage") == 0) && (gamewe_plugin.damage_display == 1)) {
				// server default -> off -> menu -> chat -> server default
				int setting = gamewe_player_settings[param1].damage_display;
				setting = (setting >= 2) ? SETTING_SERVER_DEFAULT : (setting + 1);
				gamewe_player_settings[param1].damage_display = setting;
				save_player_setting(param1, gamewe_plugin.cookie_damage_display, setting);
				DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
			} else if ((strcmp(info, "SettingsMenu_Spectator") == 0) && (gamewe_plugin.display_spectator == 1)) {
				// server default -> off -> on -> server default
				int setting = gamewe_player_settings[param1].spectatorinfo;
				setting = (setting >= 1) ? SETTING_SERVER_DEFAULT : (setting + 1);
				gamewe_player_settings[param1].spectatorinfo = setting;
				save_player_setting(param1, gamewe_plugin.cookie_spectatorinfo, setting);
				DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
			}
		}
	}

	return 0;
}


public void CreateGameWEMenuEvents(Menu &MenuHandle)
{
	MenuHandle = CreateMenu(gameWEEventsCommandHandler, MenuAction_Display | MenuAction_DisplayItem  | MenuAction_Select | MenuAction_Cancel);

	SetMenuTitle(MenuHandle, "gameWE - Console Events");

	AddMenuItem(MenuHandle, "ConsoleMenu_Menu1", "Enable Events");
	AddMenuItem(MenuHandle, "ConsoleMenu_Menu2", "Disable Events");
	AddMenuItem(MenuHandle, "ConsoleMenu_Menu3", "Enable Global Chat");
	AddMenuItem(MenuHandle, "ConsoleMenu_Menu4", "Disable Global Chat");

	SetMenuPagination(MenuHandle, 8);
}


bool make_player_command(int client, char player_command[192])
{
	if ((client > 0) && gamewe_trigger_allowed(client)) {
		log_player_event(client, "say", player_command);
		return true;
	}
	return false;
}


public int gameWEMainCommandHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_DisplayItem) {

		char info[64];
		GetMenuItem(menu, param2, info, sizeof(info), _, "", 0);

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", info, param1);

		return RedrawMenuItem(buffer);

	} else if (action == MenuAction_Display) {

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", "IngameMenu_Caption", param1);

		Panel panel = view_as<Panel>(param2);
		SetPanelTitle(panel, buffer);

	} else if (action == MenuAction_Select) {

		if (IsClientInGame(param1)) {
			if (gamewe_plugin.mod_id == MOD_HL2MP) {
				switch (param2) {
					case 0 :
						make_player_command(param1, "/rank");
					case 1 :
						make_player_command(param1, "/next");
					case 2 :
						make_player_command(param1, "/top10");
					case 3 :
						DisplayMenu(gamewe_plugin.menu_events, param1, MENU_TIME_FOREVER);
					case 4 :
						display_settings_menu(param1);
				}
			} else {
				switch (param2) {
					case 0 :
						make_player_command(param1, "/rank");
					case 1 :
						make_player_command(param1, "/next");
					case 2 :
						make_player_command(param1, "/top10");
					case 3 :
						make_player_command(param1, "/clans");
					case 4 :
						make_player_command(param1, "/status");
					case 5 :
						make_player_command(param1, "/statsme");
					case 6 :
						DisplayMenu(gamewe_plugin.menu_events, param1, MENU_TIME_FOREVER);
					case 7 :
						make_player_command(param1, "/weapons");
					case 8 :
						make_player_command(param1, "/accuracy");
					case 9 :
						make_player_command(param1, "/targets");
					case 10 :
						make_player_command(param1, "/kills");
					case 11 :
						make_player_command(param1, "/cheaters");
					case 12 :
						make_player_command(param1, "/help");
					case 13 :
						display_settings_menu(param1);


				}
			}
		}
	}

	return 0;
}


public int gameWEEventsCommandHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_DisplayItem) {

		char info[64];
		GetMenuItem(menu, param2, info, sizeof(info), _, "", 0);

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", info, param1);

		return RedrawMenuItem(buffer);

	} else if (action == MenuAction_Display) {

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", "IngameMenu_Caption", param1);

		Panel panel = view_as<Panel>(param2);
		SetPanelTitle(panel, buffer);

	} else if (action == MenuAction_Select) {

		if (IsClientInGame(param1)) {
			switch (param2) {
				case 0 :
					make_player_command(param1, "/gamewe_display 1");
				case 1 :
					make_player_command(param1, "/gamewe_display 0");
				case 2 :
					make_player_command(param1, "/gamewe_chat 1");
				case 3 :
					make_player_command(param1, "/gamewe_chat 0");
			}
		}
	}

	return 0;
}


//
//
// Third Party Addons
//
//


/*
 *
 * Advanced Logging for
 *   Left 4 Dead,
 *   Left 4 Dead 2,
 *   Team Fortress 2,
 *   Insurgency,
 *   Half-Life 2: Deathmatch
 * Copyright (C) 2011 Nicholas Hastings (psychonic)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/


public void Event_L4DRescueSurvivor(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "rescuer"));
	if (player > 0) {
		log_player_event(player, "triggered", "rescued_survivor");
	}
}


public void Event_L4DHeal(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if ((player > 0) && (player != GetClientOfUserId(GetEventInt(event, "subject")))) {
		log_player_event(player, "triggered", "healed_teammate");
	}
}


public void Event_L4DRevive(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		log_player_event(player, "triggered", "revived_teammate");
	}
}


public void Event_L4DStartleWitch(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if ((player > 0) && ((gamewe_plugin.mod_id != MOD_L4DII) || (GetEventBool(event, "first")))) {
		log_player_event(player, "triggered", "startled_witch");
	}
}


public void Event_L4DPounce(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (victim > 0) {
		log_player_player_event(player, victim, "triggered", "pounce");
	} else {
		log_player_event(player, "triggered", "pounce");
	}
}


public void Event_L4DBoomered(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((player > 0) && ((gamewe_plugin.mod_id != MOD_L4DII) || (GetEventBool(event, "by_boomer")))) {
		if (victim > 0) {
			log_player_player_event(player, victim, "triggered", "vomit");
		} else {
			log_player_event(player, "triggered", "vomit");
		}
	}
}


public void Event_L4DFF(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if ((player > 0) && (player == GetClientOfUserId(GetEventInt(event, "guilty")))) {
		if (victim > 0) {
			log_player_player_event(player, victim, "triggered", "friendly_fire");
		} else {
			log_player_event(player, "triggered", "friendly_fire");
		}
	}
}


public void Event_L4DWitchKilled(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if ((player > 0) && (GetEventBool(event, "oneshot"))) {
		log_player_event(player, "triggered", "cr0wned");
	}
}


public void Event_L4DDefib(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player >  0) {
		log_player_event(player, "triggered", "defibrillated_teammate");
	}
}


public void Event_L4DAdrenaline(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player >  0) {
		log_player_event(player, "triggered", "used_adrenaline");
	}
}


public void Event_L4DJockeyRide(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (player > 0) {
		if (victim > 0) {
			log_player_player_event(player, victim, "triggered", "jockey_ride");
		} else {
			log_player_event(player, "triggered", "jockey_ride");
		}
	}
}


public void Event_L4DChargerPummelStart(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (player > 0) {
		if (victim > 0) {
			log_player_player_event(player, victim, "triggered", "charger_pummel");
		} else {
			log_player_event(player, "triggered", "charger_pummel");
		}
	}
}


public void Event_L4DVomitBombTank(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player >  0) {
		log_player_event(player, "triggered", "bilebomb_tank");
	}
}


public void Event_L4DScavengeEnd(Event event, const char[] name, bool dontBroadcast)
{
	int team_index = GetEventInt(event, "winners");
	if (strcmp(team_list[team_index], "") != 0) {
		log_team_event(team_list[team_index], "scavenge_win");
	}
}


public void Event_L4DVersusEnd(Event event, const char[] name, bool dontBroadcast)
{
	int team_index = GetEventInt(event, "winners");
	if (strcmp(team_list[team_index], "") != 0) {
		log_team_event(team_list[team_index], "versus_win");
	}
}


public void Event_L4dChargerKilled(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "charger"));
	if ((attacker > 0) && (IsClientInGame(attacker))) {
		if (GetEventBool(event, "melee") && GetEventBool(event, "charging")) {
			if ((victim > 0) && (IsClientInGame(victim))) {
				log_player_player_event(attacker, victim, "triggered", "level_a_charge");
			} else {
				log_player_event(attacker, "triggered", "level_a_charge");
			}
		}
	}
}


public void Event_L4DAward(Event event, const char[] name, bool dontBroadcast)
{
	// "userid"	"short"				// player who earned the award
	// "entityid"	"long"			// client likes ent id
	// "subjectentid"	"long"		// entity id of other party in the award, if any
	// "award"		"short"			// id of award earned

	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player >  0) {
		switch (GetEventInt(event, "award")) {
			case 21:
				log_player_event(player, "triggered", "hunter_punter");
			case 27:
				log_player_event(player, "triggered", "tounge_twister");
			case 67:
				log_player_event(player, "triggered", "protect_teammate");
			case 80:
				log_player_event(player, "triggered", "no_death_on_tank");
			case 136:
				log_player_event(player, "triggered", "killed_all_survivors");
		}
	}
}


public void Event_TF2StealSandvich(Event event, const char[] name, bool dontBroadcast)
{
	// "owner"		"short"
	// "target"		"short"

	int owner = GetClientOfUserId(GetEventInt(event, "owner"));
	int target = GetClientOfUserId(GetEventInt(event, "target"));

	if ((owner > 0) && (target > 0)) {
		log_player_player_event(target, owner, "triggered", "steal_sandvich");
	}
}


public void Event_TF2Stunned(Event event, const char[] name, bool dontBroadcast)
{
	// "stunner"	"short"
	// "victim"	"short"
	// "victim_capping"	"bool"
	// "big_stun"	"bool"

	int stunner = GetClientOfUserId(GetEventInt(event, "stunner"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if ((stunner > 0) && (victim > 0)) {

		log_player_player_event(stunner, victim, "triggered", "stun");
		if ((GetEntityFlags(victim) & (FL_ONGROUND | FL_INWATER)) == 0) {
			log_player_event(stunner, "triggered", "airshot_stun");
		}
	}
}


public Action Event_TF2Jarated(UserMsg msg_id, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = BfReadByte(bf);
	int victim = BfReadByte(bf);

	if ((client > 0) && (victim > 0) && (IsClientInGame(client)) && (IsClientInGame(victim))) {
		if (TF2_IsPlayerInCondition(victim, TFCond_Jarated)) {
			log_player_player_event(client, victim, "triggered", "jarate");
		} else if (TF2_IsPlayerInCondition(victim, TFCond_Milked)) {
			log_player_player_event(client, victim, "triggered", "madmilk");
		}
	}
	return Plugin_Continue;
}


public Action Event_TF2ShieldBlocked(UserMsg msg_id, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int victim = BfReadByte(bf);
	int client = BfReadByte(bf);

	if ((client > 0) && (victim > 0)) {
		log_player_player_event(client, victim, "triggered", "shield_blocked");
	}
	return Plugin_Continue;
}


public Action Event_TF2SoundHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if ((entity <= MaxClients) &&(clients[0] == entity) && (tf2_players[entity].player_class == TFClass_Heavy) && (StrEqual(sample, "vo/SandwichEat09.wav"))) {

		switch (tf2_players[entity].player_loadout0[1]) {
			case TF2_LUNCHBOX_CHOCOLATE: {
				log_player_event(entity, "triggered", "dalokohs");
				float time = GetGameTime();
				if ((time - tf2_players[entity].dalokohs) > 30) {
					log_player_event(entity, "triggered", "dalokohs_healthboost");
				}
				tf2_players[entity].dalokohs = time;
				if (GetClientHealth(entity) < 350) {
					log_player_event(entity, "triggered", "dalokohs_healself");
				}
			}
			case TF2_LUNCHBOX_STEAK: {
				log_player_event(entity, "triggered", "steak");
			}
			default: {
				log_player_event(entity, "triggered", "sandvich");
				if (GetClientHealth(entity) < 300) {
					log_player_event(entity, "triggered", "sandvich_healself");
				}
			}
		}


	}
	return Plugin_Continue;
}


public void Event_TF2WinPanel(Event event, const char[] name, bool dontBroadcast)
{
	int player1 = GetEventInt(event, "player_1");
	int player2 = GetEventInt(event, "player_2");
	int player3 = GetEventInt(event, "player_3");

	if ((player1 > 0) && (IsClientInGame(player1))) {
		log_player_event(player1, "triggered", "mvp1");
	}
	if ((player2 > 0) && (IsClientInGame(player2))) {
		log_player_event(player2, "triggered", "mvp2");
	}
	if ((player3 > 0) && (IsClientInGame(player3))) {
		log_player_event(player3, "triggered", "mvp3");
	}
}


public void Event_TF2EscortScore(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetEventInt(event, "player");
	if (player > 0) {
		log_player_event(player, "triggered", "escort_score");
	}
}


public void Event_TF2DeployBuffBanner(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "buff_owner"));
	if (player > 0) {
		log_player_event(player, "triggered", "buff_deployed");
	}

}


public void Event_TF2MedicDefended(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "userid"));
	if (player > 0) {
		log_player_event(player, "triggered", "defended_medic");
	}
}


public Action Event_TF2ObjectDestroyedPre(Event event, const char[] name, bool dontBroadcast)
{
	if (GetEntProp(GetEventInt(event, "index"), Prop_Send, "m_bMiniBuilding", 1)) {
		int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		int userid = GetEventInt(event, "userid");
		int victim = GetClientOfUserId(userid);

		if ((attacker > 0) && (victim > 0) && (attacker <= MAXPLAYERS) && (victim <= MAXPLAYERS) && (IsClientInGame(victim)) && (IsClientInGame(attacker))) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			float player_origin[3];
			GetClientAbsOrigin(attacker, player_origin);
			LogToGame("\"%L\" %s \"%s\" (object \"%s\") (weapon \"%s\") (objectowner \"%L\") (attacker_position \"%d %d %d\")", attacker, "triggered", "killedobject", "OBJ_SENTRYGUN_MINI", weapon_str, victim, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]));
		}
		tf2_data.block_next_logging = true;
	}
	return Plugin_Continue;
}


public Action Event_TF2PlayerBuiltObjectPre(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0) {
		if (tf2_players[client].carry_object) {
			tf2_players[client].carry_object = false;
			tf2_data.block_next_logging = true;
		} else {
			if (GetEntProp(GetEventInt(event, "index"), Prop_Send, "m_bMiniBuilding", 1)) {
				if ((client > 0) && (client <= MAXPLAYERS) && (IsClientInGame(client))) {
					float player_origin[3];
					GetClientAbsOrigin(client, player_origin);
					LogToGame("\"%L\" %s \"%s\" (object \"%s\") (position \"%d %d %d\")", client, "triggered", "builtobject", "OBJ_SENTRYGUN_MINI", RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]));
				}
				tf2_data.block_next_logging = true;
			}
		}
	}
	return Plugin_Continue;
}


public void Event_TF2PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	float time = GetGameTime();
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);
	TFClassType spawn_class = view_as<TFClassType>(GetEventInt(event, "class"));

	tf2_players[client].jump_status = TF2_JUMP_NONE;
	dump_player_data(client);

	if (time == tf2_players[client].object_removed) {
		int obj_type;
		char obj_name[24];
		while (PopStackCell(tf2_players[client].object_list, obj_type)) {
			switch (obj_type) {
				case TF2_OBJ_DISPENSER:
					obj_name = "OBJ_DISPENSER";
				case TF2_OBJ_TELEPORTER:
					obj_name = "OBJ_TELEPORTER";
				case TF2_OBJ_SENTRYGUN:
					obj_name = "OBJ_SENTRYGUN";
				case TF2_OBJ_SENTRYGUN_MINI:
					obj_name = "OBJ_SENTRYGUN_MINI";
				default:
					continue;
			}
			float player_origin[3];
			GetClientAbsOrigin(client, player_origin);
			LogToGame("\"%L\" %s \"%s\" (object \"%s\") (weapon \"%s\") (objectowner \"%L\") (attacker_position \"%d %d %d\")", client, "triggered", "killedobject", obj_name, "pda_engineer", client, RoundFloat(player_origin[0]), RoundFloat(player_origin[1]), RoundFloat(player_origin[2]));
		}
	}

	tf2_players[client].player_class = spawn_class;
	tf2_players[client].dalokohs = -30.0;
}


public void Event_TF2RoundStart(Event event, const char[] name, bool dontBroadcast)
{
}


public void Event_TF2RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}
}


public void Event_TF2ObjectRemoved(Event event, const char[] name, bool dontBroadcast)
{
	float time = GetGameTime();
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	if (time != tf2_players[client].object_removed) {
		tf2_players[client].object_removed = time;
		while (PopStack(tf2_players[client].object_list)) {
			continue;
		}
	}
	int obj_type = GetEventInt(event, "objecttype");
	int obj_index = GetEventInt(event, "index");
	if ((IsValidEdict(obj_index)) && (GetEntProp(GetEventInt(event, "index"), Prop_Send, "m_bMiniBuilding", 1))) {
		obj_type = TF2_OBJ_SENTRYGUN_MINI;
	}
	PushStackCell(tf2_players[client].object_list, obj_type);
}


public void Event_TF2PostInvApp(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.2, check_player_loadout, GetEventInt(event, "userid"));
}


public Action check_player_loadout(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if ((client == 0) || (!IsClientInGame(client))) {
		return Plugin_Stop;
	}

	bool is_new_loadout = false;
	for (int check_slot = 0; check_slot <= 5; check_slot++) {
		if ((tf2_players[client].player_loadout1[check_slot] != 0) && (IsValidEntity(tf2_players[client].player_loadout1[check_slot]))) {
			continue;
		}
		int entity = GetPlayerWeaponSlot(client, check_slot);
		if (entity == -1) {
			if ((gamewe_plugin.sdkhook_available) && (check_slot < 3) && ((tf2_players[client].player_class == TFClass_Soldier) || (tf2_players[client].player_class == TFClass_DemoMan))) {
				tf2_players[client].player_loadout1[check_slot] = -1;
				continue;
			}
			if (tf2_players[client].player_loadout0[check_slot] == -1) {
				continue;
			}
			tf2_players[client].player_loadout0[check_slot] = -1;
			tf2_players[client].player_loadout1[check_slot] = -1;
			is_new_loadout = true;
		} else {
			int item_index = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
			if (tf2_players[client].player_loadout0[check_slot] != item_index) {
				tf2_players[client].player_loadout0[check_slot] = item_index;
				is_new_loadout = true;
			}
			tf2_players[client].player_loadout1[check_slot] = EntIndexToEntRef(entity);
		}
	}

	if (gamewe_plugin.sdkhook_available) {
		if (is_new_loadout) {
			tf2_players[client].player_loadout_updated = true;
		}
		CreateTimer(0.2, log_weapon_loadout, userid);
	} else {
		if (is_new_loadout) {
			log_weapon_loadout(INVALID_HANDLE, userid);
		}
	}
	return Plugin_Stop;
}


public Action log_weapon_loadout(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if ((client > 0) && (IsClientInGame(client))) {
		for (int i = 0; i < TF2_MAX_LOADOUT_SLOTS; i++) {
			if ((tf2_players[client].player_loadout0[i] != -1) && (!IsValidEntity(tf2_players[client].player_loadout1[i])) || (tf2_players[client].player_loadout1[i] == 0)) {
				tf2_players[client].player_loadout0[i] = -1;
				tf2_players[client].player_loadout1[i] = -1;
				tf2_players[client].player_loadout_updated = true;
			}

		}
		if (tf2_players[client].player_loadout_updated == false) {
			return Plugin_Stop;
		}
		tf2_players[client].player_loadout_updated = false;
		LogToGame("\"%L\" %s \"%s\" (primary \"%d\") (secondary \"%d\") (melee \"%d\") (pda \"%d\") (pda2 \"%d\") (building \"%d\") (head \"%d\") (misc \"%d\")", client, "triggered", "player_loadout", tf2_players[client].player_loadout0[0], tf2_players[client].player_loadout0[1], tf2_players[client].player_loadout0[2], tf2_players[client].player_loadout0[3], tf2_players[client].player_loadout0[4], tf2_players[client].player_loadout0[5], tf2_players[client].player_loadout0[6], tf2_players[client].player_loadout0[7]);
	}
	return Plugin_Stop;
}


public Action OnTF2TakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if ((attacker > 0) && (attacker <= MaxClients) && (attacker != victim) && (inflictor > MaxClients) && (damage > 0.0) && (IsValidEntity(inflictor)) && ((GetEntityFlags(victim) & (FL_ONGROUND | FL_INWATER)) == 0)) {
		char weapon_str[64];
		GetEdictClassname(inflictor, weapon_str, 64);
		if ((weapon_str[3] == 'p') && (weapon_str[4] == 'r')) {
			switch(weapon_str[14]) {
				case 'r': {
					log_player_event(attacker, "triggered", "airshot_rocket");
					if (tf2_players[attacker].jump_status == TF2_JUMP_ROCKET) {
						log_player_event(attacker, "triggered", "air2airshot_rocket");
					}
				}
				case 'p': {
					if (weapon_str[18] != 0) {
						log_player_event(attacker, "triggered", "airshot_sticky");
						if (tf2_players[attacker].jump_status == TF2_JUMP_STICKY) {
							log_player_event(attacker, "triggered", "air2airshot_sticky");
						}
					} else {
						log_player_event(attacker, "triggered", "airshot_pipebomb");
						if (tf2_players[attacker].jump_status == TF2_JUMP_STICKY) {
							log_player_event(attacker, "triggered", "air2airshot_pipebomb");
						}
					}
				}
				case 'a': {
					log_player_event(attacker, "triggered", "airshot_arrow");
				}
				case 'f': {
					if (damage > 10.0) {
						log_player_event(attacker, "triggered", "airshot_flare");
					}
				}
			}
		}
	}
	return Plugin_Continue;
}


public void OnTF2TakeDamage_Post(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if ((attacker > 0) && (attacker <= MaxClients)) {
		int weapon_index = -1;
		int idamage = RoundFloat(damage);
		char weapon_str[64];

		if (inflictor <= MaxClients) {
			if (damagetype & DMG_BURN) {
				return;
			}
			if ((inflictor == attacker) && (damagetype & 1) && (damage == 1000.0)) {
				return;
			}
			GetClientWeapon(attacker, weapon_str, 64);
			weapon_index = get_tf2_weapon_index(weapon_str[TF2_WEAPON_PREFIX_LENGTH], attacker);
		} else if (IsValidEdict(inflictor)) {
			GetEdictClassname(inflictor, weapon_str, 64);
			if (weapon_str[TF2_WEAPON_PREFIX_LENGTH] == 'g') {
				return;
			} else if (weapon_str[3] == 'p') {
				weapon_index = get_tf2_weapon_index(weapon_str, attacker, inflictor);
			} else {
				if ((!(damagetype & DMG_CRUSH)) && (damagetype & DMG_CLUB) && (StrEqual(weapon_str, "tf_weapon_bat_wood"))) {
					weapon_index = get_tf2_weapon_index("ball", attacker);
				} else {
					weapon_index = get_tf2_weapon_index(weapon_str[TF2_WEAPON_PREFIX_LENGTH], attacker);
				}
			}
		}

		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].wdamage += idamage;
			player_weapons[attacker][weapon_index].whits++;
		}
	}
}


public void Event_TF2RocketJump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0) {
		if (tf2_players[client].jump_status == TF2_JUMP_ROCKET_START) {
			tf2_players[client].jump_status = TF2_JUMP_ROCKET;
			log_player_event(client, "triggered", "rocket_jump");
		} else if (tf2_players[client].jump_status != TF2_JUMP_ROCKET) {
			tf2_players[client].jump_status = TF2_JUMP_ROCKET_START;
		}
	}
}


public void Event_TF2StickyJump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0) {
		if (tf2_players[client].jump_status != TF2_JUMP_STICKY) {
			tf2_players[client].jump_status = TF2_JUMP_STICKY;
			log_player_event(client, "triggered", "sticky_jump");
		}
	}
}


public void Event_TF2JumpLanded(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0) {
		tf2_players[client].jump_status = TF2_JUMP_NONE;
	}
}


public void Event_TF2ObjectDeflected(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int owner = GetClientOfUserId(GetEventInt(event, "ownerid"));

	if ((client > 0) && (owner > 0)) {
		int weapon_id = GetEventInt(event, "weaponid");

		switch (weapon_id)	{
			case TF_WEAPON_NONE: {
				log_player_player_event(client, owner, "triggered", "airblast_player", 1);
			}
			case TF_WEAPON_COMPOUND_BOW: {
				if (gamewe_plugin.sdkhook_available) {
					int weapon_index = get_tf2_weapon_index("deflect_arrow");
					if (weapon_index > -1) {
						player_weapons[client][weapon_index].wshots++;
					}
				}
			}
			case TF_WEAPON_FLAREGUN: {
				if (gamewe_plugin.sdkhook_available) {
					int weapon_index = get_tf2_weapon_index("deflect_flare");
					if(weapon_index > -1) {
						player_weapons[client][weapon_index].wshots++;
					}
				}
			}
			case TF_WEAPON_ROCKETLAUNCHER: {
				if (gamewe_plugin.sdkhook_available) {
					int weapon_index = get_tf2_weapon_index("deflect_rocket");
					if(weapon_index > -1) {
						player_weapons[client][weapon_index].wshots++;
					}
				}
			}
			case TF_WEAPON_DIRECTHIT: {
				if (gamewe_plugin.sdkhook_available) {
					int weapon_index = get_tf2_weapon_index("deflect_rocket");
					if(weapon_index > -1) {
						player_weapons[client][weapon_index].wshots++;
					}
				}
			}
			case TF_WEAPON_GRENADE_DEMOMAN: {
				if (gamewe_plugin.sdkhook_available) {
					int weapon_index = get_tf2_weapon_index("deflect_promode");
					if(weapon_index > -1) {
						player_weapons[client][weapon_index].wshots++;
					}
				}
			}
		}

	}
}


public void OnHL2MPFireBullets(int attacker, int shots, char[] weapon_str)
{
	if ((attacker > 0) && (attacker <= MaxClients)) {
		char weapon_name[32];
		GetClientWeapon(attacker, weapon_name, 32);
		int weapon_index = get_weapon_index(hl2mp_weapon_list, MAX_HL2MP_WEAPON_COUNT, weapon_name[7]);
		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].wshots++;
		}
	}
}


public void OnHL2MPTraceAttack(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
{
	if ((hitgroup > 0) && (attacker > 0) && (attacker <= MaxClients) && (victim > 0) && (victim <= MaxClients)) {
		if (IsValidEntity(inflictor)) {
			char inflictorclsname[64];
			if ((GetEntityNetClass(inflictor, inflictorclsname, sizeof(inflictorclsname)) && (strcmp(inflictorclsname, "CCrossbowBolt") == 0))) {
				hl2mp_players[victim].nextbow_hitgroup = hitgroup;
				return;
			}
		}
		hl2mp_players[victim].next_hitgroup = hitgroup;
	}
}


public void OnHL2MPTakeDamage(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if ((attacker > 0) && (attacker <= MaxClients) && (victim > 0) && (victim <= MaxClients)) {
		char weapon_str[32];
		GetClientWeapon(attacker, weapon_str, 32);
		int weapon_index = -1;

		if (IsValidEntity(inflictor)) {
			char inflictorclsname[64];
			if (GetEntityNetClass(inflictor, inflictorclsname, sizeof(inflictorclsname)) && strcmp(inflictorclsname, "CCrossbowBolt") == 0) {
				weapon_index = HL2MP_CROSSBOW;
			}
		}
		if (weapon_index == -1) {
			weapon_index = get_weapon_index(hl2mp_weapon_list, MAX_HL2MP_WEAPON_COUNT, weapon_str[7]);
		}

		int hitgroup = ((weapon_index == HL2MP_CROSSBOW) ? hl2mp_players[victim].nextbow_hitgroup : hl2mp_players[victim].next_hitgroup);
		if ((hitgroup >= 0) && (hitgroup < 8)) {
			switch (hitgroup) {
				case HITGROUP_GENERIC:
					player_weapons[attacker][weapon_index].wgeneric++;
				case HITGROUP_HEAD:
					player_weapons[attacker][weapon_index].whead++;
				case HITGROUP_CHEST:
					player_weapons[attacker][weapon_index].wchest++;
				case HITGROUP_STOMACH:
					player_weapons[attacker][weapon_index].wstomach++;
				case HITGROUP_LEFTARM:
					player_weapons[attacker][weapon_index].wleftarm++;
				case HITGROUP_RIGHTARM:
					player_weapons[attacker][weapon_index].wrightarm++;
				case HITGROUP_LEFTLEG:
					player_weapons[attacker][weapon_index].wleftleg++;
				case HITGROUP_RIGHTLEG:
					player_weapons[attacker][weapon_index].wrightleg++;
			}
		}

		bool headshot = ((GetClientHealth(victim) <= 0) && (hitgroup == HITGROUP_HEAD));
		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += RoundToNearest(damage);
			if (headshot) {
				player_weapons[attacker][weapon_index].wheadshots++;
			}
		}

		if (weapon_index == HL2MP_CROSSBOW) {
			hl2mp_players[victim].nextbow_hitgroup = 0;
		} else {
			hl2mp_players[victim].next_hitgroup = 0;
		}

	}
}


public void OnZPSFireBullets(int attacker, int shots, char[] weapon)
{
	if ((attacker > 0) && (attacker <= MaxClients)) {
		char weapon_name[32];
		GetClientWeapon(attacker, weapon_name, 32);
		int weapon_index = get_weapon_index(zps_weapon_list, MAX_ZPS_WEAPON_COUNT, weapon_name);
		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].wshots++;
		}
	}
}


public void OnZPSTraceAttack(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
{
	if ((hitgroup > 0) && (attacker > 0) && (attacker <= MaxClients) && (victim > 0) && (victim <= MaxClients)) {
		zps_players[victim].next_hitgroup_zps = hitgroup;
	}
}


public void OnZPSTakeDamage(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if ((attacker > 0) && (attacker <= MaxClients) && (victim > 0) && (victim <= MaxClients)) {
		int hitgroup = zps_players[victim].next_hitgroup_zps;
		bool headshot = ((GetClientHealth(victim) <= 0) && (hitgroup == HITGROUP_HEAD));

		char weapon_str[32];
		GetClientWeapon(attacker, weapon_str, 32);
		int weapon_index = get_weapon_index(zps_weapon_list, MAX_ZPS_WEAPON_COUNT, weapon_str);

		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage += RoundToNearest(damage);
			if (headshot) {
				player_weapons[attacker][weapon_index].wheadshots++;
			}
		}
		zps_players[victim].next_hitgroup_zps = 0;
	}
}


stock void AddPluginServerTag(const char[] tag)
{
	if ((gamewe_plugin.sv_tags == INVALID_HANDLE) ||
	    ((gamewe_plugin.engine_version != Engine_CSS) && (gamewe_plugin.engine_version != Engine_HL2DM) &&
	     (gamewe_plugin.engine_version != Engine_DODS) && (gamewe_plugin.engine_version != Engine_TF2) &&
	     (gamewe_plugin.engine_version != Engine_NuclearDawn) && (gamewe_plugin.engine_version != Engine_Left4Dead) &&
	     (gamewe_plugin.engine_version != Engine_Left4Dead2) && (gamewe_plugin.engine_version != Engine_CSGO) &&
	     (gamewe_plugin.engine_version != Engine_Insurgency))) {
		return;
	}

	if (FindStringInArray(gamewe_plugin.custom_tags, tag) == -1) {
		PushArrayString(gamewe_plugin.custom_tags, tag);
	}

	char current_tags[128];
	GetConVarString(gamewe_plugin.sv_tags, current_tags, 128);
	if (StrContains(current_tags, tag) > -1) {
		LogToGame("gameWE gameserver tag already exists [%s]", current_tags);
		return;
	}

	char new_tags[128];
	Format(new_tags, sizeof(new_tags), "%s%s%s", current_tags, (current_tags[0] != 0) ? "," : "", tag);

	int flags = GetConVarFlags(gamewe_plugin.sv_tags);
	SetConVarFlags(gamewe_plugin.sv_tags, flags & ~FCVAR_NOTIFY);
	gamewe_plugin.ignore_next_tag_change = true;
	SetConVarString(gamewe_plugin.sv_tags, new_tags);
	gamewe_plugin.ignore_next_tag_change = false;
	SetConVarFlags(gamewe_plugin.sv_tags, flags);

	LogToGame("Added gameWE gameserver tag [%s]", new_tags);
}


public void Event_INSMODPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	//	"deathflags"		"short"
	//	"attacker"			"short"
	//	"customkill"		"short"
	//	"lives"				"short"
	//	"attackerteam"		"short"
	//	"damagebits"		"short"
	//	"weapon"			"string"
	//	"weaponid"			"short"
	//	"userid"			"short"
	//	"priority"			"short"
	//	"team"				"short"
	//	"y"					"float"
	//	"x"					"float"
	//	"z"					"float"
	//	"assister"			"short"

	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if ((victim > 0) && (attacker > 0)) {
		if (attacker != victim) {
			char weapon_str[32];
			GetEventString(event, "weapon", weapon_str, 32);
			ReplaceString(weapon_str, 32, "weapon_", "", false);

			int weapon_index = get_weapon_index(insmod_weapon_list, MAX_INSMOD_WEAPON_COUNT, weapon_str);
			if (weapon_index > -1) {
				player_weapons[attacker][weapon_index].wkills++;
				player_weapons[victim][weapon_index].wdeaths++;
				if (GetClientTeam(attacker) == GetClientTeam(victim)) {
					player_weapons[attacker][weapon_index].wteamkills++;
				}
			}

			int assister = GetClientOfUserId(GetEventInt(event, "assister"));
			if ((assister > 0) && (assister != victim)) {
				log_player_player_event(assister, victim, "triggered", "kill_assist");
			}
		}
		dump_player_data(victim);
	}
}


public void Event_INSMODPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	//	"userid"		"short"
	//	"weapon"		"string"
	//	"hitgroup"		"short"
	//	"priority"		"short"
	//	"attacker"		"short"
	//	"dmg_health"	"short"
	//	"health"		"byte"

	int attacker  = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if ((attacker > 0) && (attacker != victim)) {
		char weapon_str[32];
		GetEventString(event, "weapon", weapon_str, 32);
		ReplaceString(weapon_str, 32, "weapon_", "", false);

		int weapon_index = get_weapon_index(insmod_weapon_list, MAX_INSMOD_WEAPON_COUNT, weapon_str);
		if (weapon_index > -1) {
			player_weapons[attacker][weapon_index].wshots++;
			player_weapons[attacker][weapon_index].whits++;
			player_weapons[attacker][weapon_index].wdamage  += GetEventInt(event, "dmg_health");
			int hitgroup  = GetEventInt(event, "hitgroup");
			if ((hitgroup >= 0) && (hitgroup < 8)) {
				switch (hitgroup) {
					case HITGROUP_GENERIC:
						player_weapons[attacker][weapon_index].wgeneric++;
					case HITGROUP_HEAD:
						player_weapons[attacker][weapon_index].whead++;
					case HITGROUP_CHEST:
						player_weapons[attacker][weapon_index].wchest++;
					case HITGROUP_STOMACH:
						player_weapons[attacker][weapon_index].wstomach++;
					case HITGROUP_LEFTARM:
						player_weapons[attacker][weapon_index].wleftarm++;
					case HITGROUP_RIGHTARM:
						player_weapons[attacker][weapon_index].wrightarm++;
					case HITGROUP_LEFTLEG:
						player_weapons[attacker][weapon_index].wleftleg++;
					case HITGROUP_RIGHTLEG:
						player_weapons[attacker][weapon_index].wrightleg++;
				}
			}

			if (hitgroup == HITGROUP_HEAD) {
				player_weapons[attacker][weapon_index].wheadshots++;
				if (IsClientInGame(attacker)) {
					log_player_event(attacker, "triggered", "headshot");
				}
			}
		}
	}
}


public void Event_INSMODEventFired(Event event, const char[] name, bool dontBroadcast)
{
	//	"weaponid"	"short"
	//	"userid"	"short"
	//	"shots"		"byte"

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	char weapon_str[32];
	GetClientWeapon(client, weapon_str, 32);
	ReplaceString(weapon_str, 32, "weapon_", "", false);

	int weapon_index = get_weapon_index(insmod_weapon_list, MAX_INSMOD_WEAPON_COUNT, weapon_str);
	if (weapon_index > -1) {
		player_weapons[client][weapon_index].wshots++;
	}

}


public void Event_INSMODPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	if (userid > 0) {
		reset_player_data(userid);
	}
}


public void Event_INSMODRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; (i <= MaxClients); i++) {
		dump_player_data(i);
	}

	int team_index = GetEventInt(event, "winner");
	if (team_index > 0) {
		log_team_event(team_list[team_index], "Round_Win");
	}
}


/**
 * Insurgency2 Logger/LogFixer
 * Based on SuperLogs by psychonic (https://forums.alliedmods.net/showthread.php?t=99231?t=99231)
 * Author: FZFalzar of Brutus.SG Modded Servers (http://brutus.sg)
 * Updated and maintained by Jared Ballou (http://jballou.com)
 * Version: 1.2.0
 */



public void Event_INSMODPlayerPickSquad(Event event, const char[] name, bool dontBroadcast)
{
	//	"squad_slot"		"byte"
	//	"squad"				"byte"
	//	"userid"			"short"
	//	"class_template"	"string"


	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if( client == 0) {
		return;
	}

	char class_template[64];
	GetEventString(event, "class_template", class_template, sizeof(class_template));
	ReplaceString(class_template, sizeof(class_template), "template_", "", false);
	ReplaceString(class_template, sizeof(class_template), "_training", "", false);
	ReplaceString(class_template, sizeof(class_template), "_coop", "", false);
	ReplaceString(class_template, sizeof(class_template), "coop_", "", false);
	ReplaceString(class_template, sizeof(class_template), "_security", "", false);
	ReplaceString(class_template, sizeof(class_template), "_insurgent", "", false);
	ReplaceString(class_template, sizeof(class_template), "_survival", "", false);

	if(!StrEqual(insmod_players[client].last_role, class_template)) {
		LogToGame("\"%L\" changed role to \"%s\"", client, class_template);
		strcopy(insmod_players[client].last_role, 64, class_template);
	}
}


public Action Event_INSMODObjectiveDestroyed(Event event, const char[] name, bool dontBroadcast)
{
	//"team"		"byte"
	//"attacker"	"byte"
	//"cp"			"short"
	//"index"		"short"
	//"type"		"byte"
	//"weapon"		"string"
	//"weaponid"	"short"
	//"assister"	"byte"
	//"attackerteam" "byte"

	int client = GetClientOfUserId(GetEventInt(event, "attacker"));
	if ((client > 0) && (client <= MaxClients) && (IsClientInGame(client))) {
		log_player_event(client, "triggered", "obj_destroyed");
	}
	return Plugin_Continue;
}


public Action Event_INSMODControlpointCapped(Event event, const char[] name, bool dontBroadcast)
{
	//	"priority"	"short"
	//	"cp"		"byte"
	//	"cappers"	"string"
	//	"cpname"	"string"
	//	"team"		"byte"

	char cappers[256];
	GetEventString(event, "cappers", cappers, sizeof(cappers));

	for (int i = 0; i < strlen(cappers); i++) {
		int client = cappers[i];
		if ((client > 0) && (client <= MaxClients) && (IsClientInGame(client))) {
			log_player_event(client, "triggered", "obj_captured");
		}
	}
	return Plugin_Continue;
}
