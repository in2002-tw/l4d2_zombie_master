//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//You should have received a copy of the GNU General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

// Made for the Knockout.chat community
// Plugin authors: gvazdas, zyiks
// HUGE THANKS TO TESTERS: Hatsune Miku Fan (God's Strongest Playtester), Skerion, Raykeno, IronBar, ngh, Lil Ole Fella, ShaunOfTheLive, zyiks
// Chance, Lett1, AGGA Lambo, Robotnik, AriesToffle, Shadowcat, Wicket, GARFIELD'S SKELETON, Perchance, 
// Snake22, Mark9013100, Sarahtonin, Rex Bosworth, g3intel, SomeENG, nativehenu
// HUGE THANKS for scripting help: HarryPotter, xerox8521, Forgetest, little_froy, Lux, Marttt, Bacardi, Silvers, zyiks
// HUGE THANKS TO Reagy and IronBar for hosting the Knockout Left 4 Dead 2 Server
// Sentence-mixed survivor voice lines: Skerion. Ellis voice line by zyiks

#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>
#include <adt_trie>
#include <files>
#include <clientprefs>

bool DEBUG = false;

#define PLUGIN_NAME			    "l4d2_zombie_master"
#define PLUGIN_VERSION 			"0.9.13 2026-05-31"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

#include <l4d2_zombie_master/zombie_master>
#include <l4d2_grid_lib>
#include <l4d2_zombie_master/sdk>
#include <l4d2_zombie_master/glow>
#include <l4d2_zombie_master/grid/l4d2_grid_renderer>
#include <l4d2_zombie_master/los_cellcache>
#include <l4d2_zombie_master/spawner_validate>
#include <l4d2_zombie_master/spawner_analog>
#include <l4d2_zombie_master/grid/spawner_grid>
#include <l4d2_zombie_master/spawner>
#include <l4d2_zombie_master/spawncommands>
#include <l4d2_zombie_master/fair_queue>
#include <l4d2_zombie_master/settings>
#include <l4d2_zombie_master/prefs>
#include <l4d2_zombie_master/hud>
#include <l4d2_zombie_master/saferoom>
#include <l4d2_zombie_master/unitmanager>
#include <l4d2_zombie_master/panic>
#include <l4d2_zombie_master/survivor_inventory>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <l4d2_zombie_master/menus>

#define _NATIVE_ONLY
#include "l4d_path_to_goal"

public Plugin myinfo =
{
	name = "[L4D2] Zombie Master",
	author = "gvazdas, zyiks, Skerion",
	description = "[coop,survival] An infected player, the Zombie Master, controls all zombies instead of the AI Director.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352060, https://github.com/gvazdas/l4d2_zombie_master"
}

// Changelog for 0.9.2
// 1. Fixed Specials not refunding if deleted immediately on spawn due to ability cooldown checks
// 2. Ambush system: Specials that are vomited on, fighting Survivors, or burning, are not included in Freeze/Unfreeze commands.
// 3. Other -> Give Up now asks for confirmation to avoid accidents.
// 4. Player data: remember grid mode, autocommon settings, PTG
// 5. Traditional Chinese localization updated (thanks in2002)
// 6. Start area fixes for better compatibility with custom maps.
// 7. Common flow spawns fixed. Should fail less.
// 8. PTG
// 9. Menu overhaul.
// 10. Items menu.

// TO DO LIST:
// 5. Gas station tornado (done by zyiks, not implemented)
// 15. Performance bottlenecks.
// 16. Is there a way to prevent observers from being able to see the ZM info? Try SendProxy?
// 26. No fog for ZM
// 30. Bring back inputkill prevention. Might not need it though.
// 39. Rare spitter cooldown bug. Idk how to fix this.
// 40. Context interact when looking at something with R
// 41. Special context interact: delete, move, attack nearest
// 42. Panic Trap
// 47. Witches in survivor closets
// 51. Find out why commons get auto culled on finale start. Can avoid culling if they are attacking other infected...
// 52. Smoker, Charger stupid behavior after ability fail.
// 57. Frozen tanks should be in stasis to prevent music // EFL_DORMANT Entity_Flags
// 58. Autokill obstructed stuck units
// 60. Survivors still keep teleporting and falling to their death.
// 62. Fun command: z_mute_infected no yelling or growling, allowing to stealth attack survivors.
// 64. Crouched frozen specials should stay crouched.

// Idle tank: 1. TankBehavior NOT STARTED  ( 0xAD39A30 ) 
// Attacking Tank: 2. TankAttack STARTED  ( 0xD410FB0 ) 

public void OnPluginStart()
{
	if (DEBUG) LogMessage("[zm] OnPluginStart");
	l4dhooks_updated = GetFeatureStatus(FeatureType_Native,"L4D_NavArea_IsBlocked")==FeatureStatus_Available;
    if (!l4dhooks_updated) LogMessage("Please update l4dhooks to improve performance.");
	load_gamemodes();
	zm_stage = ZM_END;
	CreateTimer(1.0,Timer_load_zm_global_settings);
	//AutoExecConfig(true, CONFIG_FILENAME);
	g_Steam = new StringMap();
	ZMPrefs_Register();
	g_CellCooldown = new StringMap();
	precache_survivor_hp();
	LoadTranslations("l4d2_zombie_master.phrases");
	LoadTranslations("common.phrases");
	GetGameData();
    
    // Commands -- all clients
    RegConsoleCmd("zm_vote", VoteZM, "zm_vote yes|no. Start a vote to enable/disable Zombie Master.");
	RegConsoleCmd("zm", JoinZM_command, "Become the Zombie Master; if already ZM, open main ZM menu.");
	RegConsoleCmd("zm_horde", ZM_Spawn_Horde, "zm_horde n type angry flow. Spawns n zombies; optional type: riot ceda clown mud road random; optional angry: chase survivors (more expensive). optional flow: spawn ahead of furthest survivor instead of where ZM is pointing. Order of arguments doesn't matter.");
	RegConsoleCmd("zm_witch", ZM_Spawn_Witch, "zm_witch n flow; n=0 static, n=1 moving; optional flow: spawn ahead of furthest survivor. Order of arguments doesn't matter.");
	RegConsoleCmd("zm_smoker", ZM_Smoker, "zm_smoker flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_hunter", ZM_Hunter, "zm_hunter flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_jockey", ZM_Jockey, "zm_jockey flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_spitter", ZM_Spitter, "zm_spitter flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_boomer", ZM_Boomer, "zm_boomer flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_charger", ZM_Charger, "zm_charger flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_tank", ZM_Tank, "zm_tank flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_delete", ZM_Delete, "Delete last infected unit Zombie Master was looking at.");
	RegConsoleCmd("zm_delete_all", ZM_Delete_All, "Delete ALL zombies.");
	RegConsoleCmd("zm_delete_common", ZM_Delete_Commons, "Delete all common and uncommon infected.");
    RegConsoleCmd("zm_delete_specials", ZM_Delete_Specials, "Delete all special infected.");
    RegConsoleCmd("zm_delete_witches", ZM_Delete_Witches, "Delete all witches.");
	RegConsoleCmd("zm_quit", QuitZM_Command, "Give up Zombie Master and join Survivors.");
    RegConsoleCmd("zm_giveup", QuitZM_Command, "Give up Zombie Master and join Survivors.");
	RegConsoleCmd("zm_panic", ZMPanic, "All Common and Uncommon Infected rush the survivors. Bank rate is reduced.");
	RegConsoleCmd("zm_start", zm_start,"Allow survivors to leave safezone; if already so, force saferoom open and start round. Can be used by ZM and admins.");
	RegConsoleCmd("zm_followme", ZM_Chase_ZM, "Panic horde will chase Zombie Master.");
	RegConsoleCmd("zm_vision", ZM_Vision, "Toggle night vision for ZM. Or press the flashlight button.");
	RegConsoleCmd("zm_teleport", ZMTeleport, "ZM will teleport to farthest flow survivor.");
	RegConsoleCmd("zm_control", ZMControlSI, "ZM will take control of the special infected that is flashing. Or press the USE button.");
	RegConsoleCmd("zm_menu", ZM_Menu, "Open specific ZM menu: main common uncommon special boss cleanup other close. Use the RELOAD button to open the main menu.");
	RegConsoleCmd("zm_help", ZM_MOTD, "Open console tutorial which explains how to play Zombie Master.");
	RegConsoleCmd("zm_tutorial", ZM_MOTD, "Open console tutorial which explains how to play Zombie Master.");
	RegConsoleCmd("zm_autocommon_mode", zm_autocommon_mode, "off panic always");
	RegConsoleCmd("zm_autocommon_max", zm_autocommon_max, "n");
	RegConsoleCmd("zm_freeze", zm_freeze, "Freeze/unfreeze all specials.");
	RegConsoleCmd("zm_gamemode_menu", ZM_Gamemode_Command, "Admins: select gamemode. Clients: vote for gamemode.");
    
	// Commands -- admins only
	RegAdminCmd("zm_addbank", zm_addbank, ADMFLAG_ROOT,"Add zombux to zombie master bank. Admins only.");
    RegAdminCmd("zm_kick", zm_kick, ADMFLAG_ROOT,"Kick Zombie Master back into survivors. Admins only.");
    RegAdminCmd("zm_finale_next", zm_finale_advance, ADMFLAG_ROOT,"Trigger next finale stage. Admins only.");
    RegAdminCmd("zm_debug_player", zm_debug_player, ADMFLAG_ROOT, "Debug player state. Admins only.");
    RegAdminCmd("zm_debug_mob", zm_debug_mob, ADMFLAG_ROOT, "Debug mob state. Admins only.");

    g_hCvarDebug = CreateConVar("zm_debug", "0", "Print plugin debug info to server.",FCVAR_PROTECTED , true, 0.0, true, 1.0);
    g_hCvarDebug.AddChangeHook(ConVarChanged_Cvars);
    
	g_hCvarAllow = CreateConVar("zm_enable", "0", "0=Plugin off, 1=Plugin on.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
    
    g_hBankRateBase = CreateConVar("zm_bank_rate_base", "6.0", "Base ZM bank rate, per second.",FCVAR_PROTECTED , true, 0.0, true, 1000000.0);
    g_hBankRateBase.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankRatePlayer = CreateConVar("zm_bank_rate_player", "2.5", "Additional ZM bank rate per alive survivor, per second.",FCVAR_PROTECTED, true, 0.0, true, 1000000.0);
    g_hBankRatePlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitial = CreateConVar("zm_bank_initial", "600", "Initial ZM bank.",FCVAR_PROTECTED, true, 0.0, true, 1000000.0);
    g_hBankInitial.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitialPlayer = CreateConVar("zm_bank_initial_player", "300", "Additional initial ZM bank per extra player.",FCVAR_PROTECTED, true, 0.0, true, 1000000.0);
    g_hBankInitialPlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hPanicCost = CreateConVar("zm_panic_cost", "200", "Horde panic cost. -1.0 to disable.",FCVAR_PROTECTED , true, -1.0, true, 1000000.0);
    g_hPanicCost.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hPanicDuration = CreateConVar("zm_panic_duration", "30", "Horde panic duration, in seconds.",FCVAR_PROTECTED , true, 10.0, true, 1000.0);
    g_hPanicDuration.AddChangeHook(ConVarChanged_Cvars);
    
    g_hPanicRefill = CreateConVar("zm_panic_refill", "1", "If 1, panic will reset spawn cooldown for commons.",FCVAR_PROTECTED , true, 0.0, true, 1.0);
    g_hPanicRefill.AddChangeHook(ConVarChanged_Cvars);
    
    g_hUpdateRate = CreateConVar("zm_updaterate", "0.25", "Update rate for periodic ZM checks, in seconds.",FCVAR_PROTECTED , true, 0.1, true, 10.0);
    g_hUpdateRate.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxCommons = CreateConVar("zm_maxcommons", "75", "ZM max number of common zombies. Be careful.",FCVAR_PROTECTED , true, 0.0, true, 500.0);
    g_hMaxCommons.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hSpawnMinDistance = CreateConVar("zm_spawndistance", "400", "ZM minimum spawn distance.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hSpawnMinDistance.AddChangeHook(ConVarChanged_Cvars);
    
    g_hGrid = CreateConVar("zm_grid", "1", "Integrate GridLib into ZM spawner.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
    g_hGrid.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    //g_hGridSearchRadius = CreateConVar("zm_grid_search_radius", "500", "Search radius (units) for GridLib fallback spawn when indicator is blue.",FCVAR_PROTECTED, true, 0.0, true, 5000.0);
    //g_hGridSearchRadius.AddChangeHook(ConVarChanged_Cvars);
    
    g_hGridCooldown = CreateConVar("zm_grid_cooldown", "0.0", "Invalid cell cooldown time. This is an optimization. Do not change unless you know what you are doing.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hGridCooldown.AddChangeHook(ConVarChanged_Cvars);


    g_hLosCellCache = CreateConVar("zm_los_cellcache", "1", "If 1, use a shared hash-based (survivor_grid_cell, target_grid_cell) LOS cache to skip redundant traces. 0 = always trace.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
    g_hLosCellCache.AddChangeHook(ConVarChanged_Cvars);

    g_hLosCellCacheTTL = CreateConVar("zm_los_cellcache_ttl", "1.0", "Cell-pair LOS cache entry lifetime in seconds.",FCVAR_PROTECTED, true, 0.1, true, 60.0);
    g_hLosCellCacheTTL.AddChangeHook(ConVarChanged_Cvars);


    g_hSpawnerMode = CreateConVar("zm_spawner_mode", "1", "Default spawner mode. 0 = analog(3 rings), 1 = analog+grid, 2 = grid.",FCVAR_PROTECTED, true, 0.0, true, 2.0);
    g_hSpawnerMode.AddChangeHook(ConVarChanged_Cvars_ZMenu);

    g_hCostBoomer = CreateConVar("zm_cost_boomer", "150", "ZM boomer cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostBoomer.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostSpitter = CreateConVar("zm_cost_spitter", "200", "ZM spitter cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostSpitter.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostHunter = CreateConVar("zm_cost_hunter", "200", "ZM hunter cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostHunter.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostSmoker = CreateConVar("zm_cost_smoker", "200", "ZM smoker cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostSmoker.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostJockey = CreateConVar("zm_cost_jockey", "200", "ZM jockey cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostJockey.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostCharger = CreateConVar("zm_cost_charger", "200", "ZM charger cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostCharger.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostTank = CreateConVar("zm_cost_tank", "2000", "ZM tank cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostTank.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostWitchStatic = CreateConVar("zm_cost_witch_static", "600", "ZM static witch cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostWitchStatic.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostWitchMoving = CreateConVar("zm_cost_witch_moving", "500", "ZM moving witch cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostWitchMoving.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostCommon = CreateConVar("zm_cost_common", "5", "ZM common infected cost. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostUncommon = CreateConVar("zm_cost_uncommon", "25", "ZM uncommon infected cost. Also the cost of angry common zombies. -1 to prevent spawns.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
    g_hCostUncommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hBonusCarAlarm = CreateConVar("zm_bonus_car_alarm", "400", "ZM bank reward for triggered car alarm.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hBonusCarAlarm.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBonusFinaleStage = CreateConVar("zm_bonus_finale", "350", "ZM bank reward per player for advancing to the next Finale stage.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hBonusFinaleStage.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBonusSurvival = CreateConVar("zm_bonus_survival", "300", "ZM bank reward per player when an automatic Tank dies in Survival.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hBonusSurvival.AddChangeHook(ConVarChanged_Cvars);
    
    g_hLockSaferoom = CreateConVar("zm_lock_saferoom", "1", "Allow players to leave safezone only if: there is a ZM, zm prep time is over, and players have stopped joining.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
    g_hLockSaferoom.AddChangeHook(ConVarChanged_Cvars);
    
    g_hStopInactivity = CreateConVar("zm_inactivity", "120.0", "Seconds of inactivity before the ZM is kicked to survivors. 0 to disable.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
    g_hStopInactivity.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxWitches = CreateConVar("zm_max_witches", "-1.0", "Max number of witches: -1 for automatic AliveSurvivors//2, otherwise whatever number is given.",FCVAR_PROTECTED, true, -1.0, true, 1000.0);
    g_hMaxWitches.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hMaxSI = CreateConVar("zm_max_SI", "-1.0", "Max number of total alive special infected: -n for AliveSurvivors-n+1, otherwise whatever number is given.",FCVAR_PROTECTED, true, -32.0, true, 32.0);
    g_hMaxSI.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hMaxUniqueSI = CreateConVar("zm_max_unique_SI", "-1.0", "Max number of each special infected class: -1 for automatic AliveSurvivors//2, otherwise whatever number is given.",FCVAR_PROTECTED, true, -1.0, true, 32.0);
    g_hMaxUniqueSI.AddChangeHook(ConVarChanged_Cvars_ZMenu);
	
	g_hPrepTimeZM = CreateConVar("zm_preptime", "60.0", "Seconds of zombie master prep time before survivors can leave safe zone.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
	g_hPrepTimeZM.AddChangeHook(ConVarChanged_Cvars);
	
	g_hCommonRate = CreateConVar("zm_common_rate", "2.0", "Commons per second made available to spawn in the zombie pool.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
	g_hCommonRate.AddChangeHook(ConVarChanged_Cvars);
	
	g_hWitchCooldown = CreateConVar("zm_witch_cooldown", "45.0", "Witch cooldown, in seconds.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
	g_hWitchCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hTankCooldown = CreateConVar("zm_tank_cooldown", "60.0", "Tank cooldown, in seconds.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
	g_hTankCooldown.AddChangeHook(ConVarChanged_Cvars);
	
    g_hSpitterCooldown = CreateConVar("zm_spitter_cooldown", "40.0", "Spitter cooldown, in seconds.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
	g_hSpitterCooldown.AddChangeHook(ConVarChanged_Cvars);

	g_hSpecialCooldown = CreateConVar("zm_special_cooldown", "20.0", "Cooldown for special infected spawns, in seconds.",FCVAR_PROTECTED, true, 0.0, true, 100000.0);
	g_hSpecialCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hMinFinaleStage = CreateConVar("zm_min_finale_stage", "45.0", "Minimum gap between ZM rewards during Finale. Forces ZM to conserve resources.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
	g_hMinFinaleStage.AddChangeHook(ConVarChanged_Cvars);
	
	g_hFairQueue = CreateConVar("zm_fair_queue", "1.0", "Queue system to allow all players a fair chance at playing ZM.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hFairQueue.AddChangeHook(ConVarChanged_Cvars);
	
	g_hFairQueueWait = CreateConVar("zm_fair_queue_wait", "10.0", "How long to wait for client response to ZM offer.",FCVAR_PROTECTED, true, 0.0, true, 30.0);
	g_hFairQueueWait.AddChangeHook(ConVarChanged_Cvars);
	
	g_hMenuTimeout = CreateConVar("zm_menu_reopen_ping", "0.05", "Threshold ping in seconds to periodically re-open ZM sourcemod menu. Prevents menu from closing unexpectedly for high pings. Lower values are more aggressive about reopening. 0.0 will always periodically reopen the menu. -1.0 to disable.",FCVAR_PROTECTED, true, -1.0, true, 1000.0);
	g_hMenuTimeout.AddChangeHook(ConVarChanged_Cvars);
	
	g_hDiscountTank = CreateConVar("zm_discount_tank", "1.0", "Dynamic first tank pricing on maps where tanks are allowed: 50% off when survivors reach 66.6% progress.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hDiscountTank.AddChangeHook(ConVarChanged_Cvars);
	
	g_hMemes = CreateConVar("zm_memes", "1.0", "Enable funny Louis and Ellis voice lines. sv_allowdownload must be 1. If sv_downloadurl is empty the project github will be linked automatically.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hMemes.AddChangeHook(ConVarChanged_Cvars);
	
	g_hClownGlow = CreateConVar("zm_clown_glow", "1.0", "Clowns spawned by ZM will glow red.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hClownGlow.AddChangeHook(ConVarChanged_Cvars);
	
	g_hForceCommon = CreateConVar("zm_force_common", "", "Force all ZM commons to spawn as this type. Values: riot ceda clown mud road jimmy.",FCVAR_PROTECTED);
	g_hForceCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
	
	g_hHoldFinale = CreateConVar("zm_hold_finale", "1", "Hold Finale stages until ZM runs out of resources. Otherwise the Finale will be very short.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hHoldFinale.AddChangeHook(ConVarChanged_Cvars);
	
	g_hZMGamemode = CreateConVar("zm_gamemode", "zm_default", "Specify gamemode cfg inside cfg/sourcemod/l4d2_zombie_master/, or random to randomize.",FCVAR_PROTECTED);
	g_hZMGamemode.AddChangeHook(ConVarChanged_Cvars_Gamemode);
	
	g_hVomitCommons = CreateConVar("zm_vomit_commons", "10", "Number of angry commons spawned near survivor when vomited upon.",FCVAR_PROTECTED);
	g_hVomitCommons.AddChangeHook(ConVarChanged_Cvars);
	
	g_hAllowFreeze = CreateConVar("zm_allow_freeze", "1", "Allow ZM to freeze Special Infected.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hAllowFreeze.AddChangeHook(ConVarChanged_Cvars_ZMenu);
	
	g_hPanicRateMultiplier = CreateConVar("zm_panic_rate_multiplier", "0.25", "Bank rate multiplier during active manual panic.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hPanicRateMultiplier.AddChangeHook(ConVarChanged_Cvars);
	
	g_hRandomizer = CreateConVar("zm_randomizer", "0", "Randomize zm_gamemode on: 1 new map, 2 new round.",FCVAR_PROTECTED, true, 0.0, true, 2.0);
	g_hSayHorde = CreateConVar("zm_say_horde", "0", "Survivors spawn free angry zombies when they talk in team chat.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	
	g_hNoTanks = CreateConVar("zm_notanks", "0", "Fully disable tanks, including Survival, Finales and scripted tanks.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_hNoTanks.AddChangeHook(ConVarChanged_Cvars_ZMenu);
	
	g_hAbilityCooldown = CreateConVar("zm_ability_cooldown", "-1.0", "Set cooldown for all Special abilities. -1.0 to use game defaults.",FCVAR_PROTECTED, true, -1.0, true, 10000.0);
	g_hAbilityCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hNoZMWarn = CreateConVar("zm_nozm_warning", "1.0", "Warn players when there is no ZM.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	
	g_hCursed = CreateConVar("zm_cursed", "0", "Enable dumb stuff.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	
	GetCvars();

	g_iAliveSurvivors = -1;
	zm_client = -1;

	// Removes the boundaries for z_max_player_zombies and notify flag
	z_max_player_zombies = FindConVar("z_max_player_zombies");
	int flags = z_max_player_zombies.Flags;
	SetConVarBounds(z_max_player_zombies, ConVarBound_Upper, false);
	SetConVarFlags(z_max_player_zombies, flags & ~FCVAR_NOTIFY);
  	
  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.GetString(g_sCvarMPGameMode, sizeof(g_sCvarMPGameMode));
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);
  	
    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
        OnAdminMenuReady(topmenu);
}

public void OnAdminMenuReady(Handle aTopMenu)
{
  TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
  if (topmenu == hAdminMenu && obj_zmcommands != INVALID_TOPMENUOBJECT) return;
  hAdminMenu = topmenu;
  obj_zmcommands = AddToTopMenu(topmenu,"Zombie Master",TopMenuObject_Category,CategoryHandler,INVALID_TOPMENUOBJECT);
  if (obj_zmcommands == INVALID_TOPMENUOBJECT) return;
  zm_enable = AddToTopMenu(hAdminMenu,"zm_enable",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_enable",ADMFLAG_SLAY);
  zm_randomizer = AddToTopMenu(hAdminMenu,"zm_randomizer",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_randomizer",ADMFLAG_SLAY);
  zm_gamemode_menu = AddToTopMenu(hAdminMenu,"zm_gamemode_menu",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_gamemode_menu",ADMFLAG_SLAY);
  zm_kick_topmenu = AddToTopMenu(hAdminMenu,"zm_kick",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_kick",ADMFLAG_SLAY);
  zm_sayhorde = AddToTopMenu(hAdminMenu,"zm_say_horde",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_say_horde",ADMFLAG_SLAY);
  zm_help = AddToTopMenu(hAdminMenu,"zm_help",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_help",ADMFLAG_SLAY);
  zm_random = AddToTopMenu(hAdminMenu,"zm_random",TopMenuObject_Item,AdminMenu_Handler,obj_zmcommands,"zm_random",ADMFLAG_SLAY);
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (strcmp(oldValue,newValue)==0) return;
	char sGameMode[32];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	if(strcmp(g_sCvarMPGameMode, sGameMode, false) == 0) return;
	g_sCvarMPGameMode = sGameMode;
    if (DEBUG) LogMessage("[zm] Gamemode: %s", g_sCvarMPGameMode);
    l4d2_specials = true;
    if (strcmp(g_sCvarMPGameMode,"l4d1coop")==0 || strcmp(g_sCvarMPGameMode,"l4d1survival")==0)
        l4d2_specials = false;
	IsAllowed();
}

void ConVarChanged_Cvars_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (strcmp(oldValue,"zm_clowns",false)==0 && clown_world_enable) ServerCommand("clown_world_resetcvars");
    load_zm_gamemode();
    on_changed_rules();
    create_menu_gamemode();
}

void ConVarChanged_Cvars_ZMenu(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (strcmp(oldValue,newValue)==0) return;
    on_changed_rules();
}

void on_changed_rules()
{
   GetCvars();
   SetCvarsZM();
   if (g_iCostUncommon<0) autocommon_uncommons=false;
   else if (g_iCostCommon<0 || valid_uncommon(g_sForceCommon)) autocommon_uncommons=true;
   if (g_bCvarAllow && IsValidClientZM())
   {
      update_menus();
      update_EMS_HUD(true,0.0);
   }
}

void ConVarChanged_Allow(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (strcmp(oldValue,newValue)==0) return;
    IsAllowed();
}
void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (strcmp(oldValue,newValue)==0) return;
    GetCvars();
}

void IsAllowed()
{
	if (DEBUG) LogMessage("[zm] IsAllowed");
	bool bCvarAllow = g_hCvarAllow.BoolValue;
    
    if ( L4D_HasPlayerControlledZombies() && bCvarAllow)
    {
        SetConVarBool(g_hCvarAllow,false);
        PrintToChatAll("[zm] %t", "ZM restrict notify");
        return;
    }
    
	if(!g_bCvarAllow && bCvarAllow)
	{
		g_bCvarAllow = true;
		HookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
		HookEvent("round_start", evtRoundStart,		EventHookMode_PostNoCopy);
		HookEvent("survival_round_start",Event_SurvivalRoundStart,EventHookMode_PostNoCopy);
		HookEvent("round_end",				evtRoundEnd,		EventHookMode_Pre); //trigger twice in versus mode, one when all survivors wipe out or make it to saferom, one when first round ends (second round_start begins).
		HookEvent("map_transition", 		evtRoundEnd,		EventHookMode_Pre); //all survivors make it to saferoom, and server is about to change next level in coop mode (does not trigger round_end) 
		HookEvent("mission_lost", 			evtRoundEnd,		EventHookMode_Pre); //all survivors wipe out in coop mode (also triggers round_end)
		HookEvent("finale_vehicle_leaving", evtRoundEnd,		EventHookMode_Pre); //final map final rescue vehicle leaving  (does not trigger round_end)
	    HookEvent("triggered_car_alarm", Event_TriggeredCarAlarm, EventHookMode_Post);
		HookEvent("player_death", evtPlayerDeath, EventHookMode_Post);
		HookEvent("player_team", evtPlayerTeam, EventHookMode_Post);
		HookEvent("finale_start", 			evtFinaleStart, EventHookMode_Pre); //final starts, some of final maps won't trigger
		HookEvent("finale_radio_start", 	evtFinaleStart, EventHookMode_Pre); //final starts, all final maps trigger
		HookEvent("gauntlet_finale_start", 	evtFinaleStart, EventHookMode_Pre); //final starts, only rushing maps trigger (C5M5, C13M4)
		HookEvent("player_spawn", evtPlayerSpawned, EventHookMode_Post);
		HookEvent("player_left_checkpoint", evt_ZM_start_imminent, EventHookMode_Post); // unhooking this can cause exceptions. dont ask me why. idk WHY. IDK 
		HookEvent("player_left_start_area", evt_ZM_start_imminent, EventHookMode_Post);
		HookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		HookEvent("player_no_longer_it", Event_PlayerUnBoomed, EventHookMode_Pre);
		
		HookEvent("player_hurt", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		HookEvent("player_falldamage", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		HookEvent("heal_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		HookEvent("pills_used", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		HookEvent("revive_end", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		HookEvent("revive_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		
		HookEvent("survivor_rescued", EvtPlayerRescued, EventHookMode_Post); // victim was rescued
		HookEvent("rescue_door_open", EvtRescueDoorOpen, EventHookMode_Post);
		HookEvent("survivor_call_for_help", EvtPlayerCallHelp, EventHookMode_Post); //userid -> actual player entity
		HookEvent("player_bot_replace", EvtBotReplacePlayer, EventHookMode_Post);
        HookEvent("bot_player_replace", EvtPlayerReplaceBot, EventHookMode_Post);
        HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
        HookEvent("item_pickup", EvtSurvivorItem, EventHookMode_Post);
        HookEvent("spawner_give_item", EvtSurvivorItem, EventHookMode_Post);
        HookEvent("upgrade_pack_used", EvtSurvivorItem, EventHookMode_Post);
        HookEvent("defibrillator_used", EvtSurvivorItem, EventHookMode_Post);
        HookEvent("adrenaline_used", EvtSurvivorItem, EventHookMode_Post);
		
		load_zm_gamemode();
		GetCvars();
		SetCvarsZM();

		//if (g_hDTR_InputKill && !bypass_windows) g_hDTR_InputKill.Enable(Hook_Pre, DTR_CBaseEntity_InputKill);
		//if (g_hDTR_InputKillHierarchy && !bypass_windows) g_hDTR_InputKillHierarchy.Enable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
	    
		enable_challenge_mode();
		clients_in_server = true;
		
		for( int i = 1; i <= MaxClients; i++ )
    	{
    		if(IsValidClient(i) && !IsFakeClient(i))
    		{
        		create_client_data(i);
        		clients_active[i] = true;
        	}
    	}
		
		RequestFrame(update_menus);
		
        HookEntityOutput("info_director", "OnPanicEventFinished", OnDirectorOutputFired);
        HookEntityOutput("info_director", "OnCustomPanicStageFinished", OnDirectorOutputFired);
        
        zm_stage = ZM_END;
        SetConVarInt(FindConVar("mp_restartgame"), 1);
        
        if (!g_bNavReady)
    	{
        	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
        	g_bNavReady = false;
        	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
    	}
    	
    	HookUserMessage(GetUserMessageId("PZDmgMsg"), OnPZDmgMsg, true);
    	HookUserMessage(GetUserMessageId("Damage"), OnPZDmgMsg, true);
		
	}
    
	else if(g_bCvarAllow && !bCvarAllow)
	{
		g_bCvarAllow = false;
		
		UnhookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
		UnhookEvent("round_start", evtRoundStart,		EventHookMode_PostNoCopy);
		UnhookEvent("survival_round_start",Event_SurvivalRoundStart,EventHookMode_PostNoCopy);
		UnhookEvent("round_end",				evtRoundEnd,		EventHookMode_Pre); //trigger twice in versus mode, one when all survivors wipe out or make it to saferom, one when first round ends (second round_start begins).
		UnhookEvent("map_transition", 		evtRoundEnd,		EventHookMode_Pre); //all survivors make it to saferoom, and server is about to change next level in coop mode (does not trigger round_end) 
		UnhookEvent("mission_lost", 			evtRoundEnd,		EventHookMode_Pre); //all survivors wipe out in coop mode (also triggers round_end)
		UnhookEvent("finale_vehicle_leaving", evtRoundEnd,		EventHookMode_Pre); //final map final rescue vehicle leaving  (does not trigger round_end)
	    UnhookEvent("triggered_car_alarm", Event_TriggeredCarAlarm, EventHookMode_Post);
		UnhookEvent("player_death", evtPlayerDeath, EventHookMode_Post);
		UnhookEvent("player_team", evtPlayerTeam, EventHookMode_Post);
		UnhookEvent("finale_start", 			evtFinaleStart, EventHookMode_Pre); //final starts, some of final maps won't trigger
		UnhookEvent("finale_radio_start", 	evtFinaleStart, EventHookMode_Pre); //final starts, all final maps trigger
		UnhookEvent("gauntlet_finale_start", 	evtFinaleStart, EventHookMode_Pre); //final starts, only rushing maps trigger (C5M5, C13M4)
		UnhookEvent("player_spawn", evtPlayerSpawned, EventHookMode_Post);
		UnhookEvent("player_left_start_area", evt_ZM_start_imminent, EventHookMode_Post);
		UnhookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		UnhookEvent("player_no_longer_it", Event_PlayerUnBoomed, EventHookMode_Pre);
		
		UnhookEvent("player_hurt", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		UnhookEvent("player_falldamage", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		UnhookEvent("heal_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		UnhookEvent("pills_used", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		UnhookEvent("revive_end", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		UnhookEvent("revive_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		
		UnhookEvent("survivor_rescued", EvtPlayerRescued, EventHookMode_Post); // victim was rescued
		UnhookEvent("rescue_door_open", EvtRescueDoorOpen, EventHookMode_Post);
		UnhookEvent("survivor_call_for_help", EvtPlayerCallHelp, EventHookMode_Post); // userid -> actual player entity
		UnhookEvent("player_bot_replace", EvtBotReplacePlayer, EventHookMode_Post);
        UnhookEvent("bot_player_replace", EvtPlayerReplaceBot, EventHookMode_Post);
        UnhookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
		
		//if (g_hDTR_InputKill && !bypass_windows) g_hDTR_InputKill.Disable(Hook_Pre, DTR_CBaseEntity_InputKill);
		//if (g_hDTR_InputKillHierarchy && !bypass_windows) g_hDTR_InputKillHierarchy.Disable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
		
		for( int i = 1; i <= MaxClients; i++ )
    	{
    		if(IsClientInGame(i))
    		{
        		L4D2_RemoveEntityGlow(i);
        		if (!IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
    		}
    	}
		
		if (EMS_hud_ready)
        {
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM);
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TIMER);
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM_HINT);
        }
		EMS_hud_ready = false;
		
        UnhookEntityOutput("info_director", "OnPanicEventFinished", OnDirectorOutputFired);
        UnhookEntityOutput("info_director", "OnCustomPanicStageFinished", OnDirectorOutputFired);
        
		UnhookUserMessage(GetUserMessageId("PZDmgMsg"), OnPZDmgMsg, true);
		UnhookUserMessage(GetUserMessageId("Damage"), OnPZDmgMsg, true);
		
		zm_stage = ZM_END;
		OnPluginEnd();
		zm_stage = ZM_END;
	}
}

// Draw Path To Goal for Zombie Master
void zm_ptg()
{
    L4D_Path_To_Goal(zm_client,g_fUpdateRate*1.9,true,false);
}

Action zm_update(Handle timer = null)
{
   
   if (!g_bCvarAllow || zm_stage>=ZM_END)
   {
      if (timer==zm_timer) zm_timer = INVALID_HANDLE;
      if (IsValidClientZM()) QuitZM_Force(zm_client);
      return Plugin_Stop;
   }
   if (timer && zm_timer && timer != zm_timer) return Plugin_Stop; // cancel timer if it's not zm_timer
   
   float t_now = GetGameTime();
   if (DEBUG) LogMessage("[zm] zm_update %d %d %f", zm_timer, timer, t_now);
   
   if (L4D_HasMapStarted())
   {
       CountCommons();
       if (g_bLockSaferoom && L4D_IsInIntro()>0) freeze_team(true);
       check_panic();
   }
   
   float dt = t_now - t_last_update;
   if (dt>0.0)
   {
        
        if (g_bDiscountTank) update_dynamic_tank();
        
        if (ZM_specials_frozen!=specials_frozen && zm_stage==ZM_STARTED)
        {
            freeze_team(ZM_specials_frozen,TEAM_INFECTED);
        }
        
        if (zm_stage==ZM_STARTED)
        {
            bank_add += dt*get_bank_rate();
            if (bank_add>=1.0)
            {
                int add_int = RoundToFloor(bank_add);
                bank += add_int;
                bank_add -= add_int;
            }
        }
        else verify_saferoom_closed();
        
        if (available_zombie_arr[ZOMBIECLASS_COMMON]<max_zombie_arr[ZOMBIECLASS_COMMON])
        {
            int occupied = get_occupied_units(max_zombie_arr[ZOMBIECLASS_COMMON],
                                              available_zombie_arr[ZOMBIECLASS_COMMON],
                                              live_zombie_arr[ZOMBIECLASS_COMMON]);
            if (occupied>live_zombie_arr[ZOMBIECLASS_COMMON])
            {
                 if (live_zombie_arr[ZOMBIECLASS_TANK]<=0)
                     commons_add += dt*g_fCommonRate;
                 else if ( ZM_finale_announced && (prev_finaleType==FINALE_HORDE_ESCAPE || prev_finaleType==FINALE_GAUNTLET_ESCAPE) )
                     commons_add += dt*g_fCommonRate;
                 else commons_add += dt*g_fCommonRate/(1.0+1.0*live_zombie_arr[ZOMBIECLASS_TANK]);
                 if (commons_add>=1.0)
                 {
                     int add_common = RoundToFloor(commons_add);
                     add_available_zombie(ZOMBIECLASS_COMMON,add_common);
                     commons_add -= add_common;
                 }
            }
            else commons_add = 0.0;
        }
        else commons_add = 0.0;
        
        sanity_check_available(ZOMBIECLASS_SMOKER,t_now);
        sanity_check_available(ZOMBIECLASS_BOOMER,t_now);
        sanity_check_available(ZOMBIECLASS_HUNTER,t_now);
        sanity_check_available(ZOMBIECLASS_SPITTER,t_now);
        sanity_check_available(ZOMBIECLASS_JOCKEY,t_now);
        sanity_check_available(ZOMBIECLASS_CHARGER,t_now);
        sanity_check_available(ZOMBIECLASS_WITCH,t_now);
        sanity_check_available(ZOMBIECLASS_TANK,t_now);
        
        if (specials_frozen && zm_stage==ZM_STARTED)
        {
           	for( int i = 1; i <= MaxClients; i++ )
           	{
           		if (!IsValidClient(i) || !IsPlayerAlive(i) || !IsFakeClient(i) || GetClientTeam(i)!=TEAM_INFECTED) continue;
                if (ignore_threats[i]) continue;
           		if (GetEntProp(i, Prop_Send, "m_hasVisibleThreats")>0 || L4D2_GetSurvivorVictim(i)>0)
           		{
               		set_specials_frozen(false);
               		if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_START,_,_,_,_,_,GetRandomInt(95,105));
               		break;
           		}
           		
           	}
        }
        
        if (autocommon_setting>0 && (t_now-t_last_autocommon)>=autocommon_updaterate)
        {
            if ( autocommon_setting>=AUTOCOMMON_ALWAYS || 
                      ( (panic || L4D_IsSurvivalMode() || ZM_finale_announced) && autocommon_setting>=AUTOCOMMON_PANIC ) )
            {
                  if (live_zombie_arr[ZOMBIECLASS_COMMON]<autocommon_num && available_zombie_arr[ZOMBIECLASS_COMMON]>0)
                  {
                      int count = autocommon_num;
                      count -= live_zombie_arr[ZOMBIECLASS_COMMON];
                      if (autocommon_uncommons) ZM_Horde(0,count,"random",_,true,false);
                      else ZM_Horde(0,count,_,_,true,false);
                  }
            }
            
            if ( autocommon_setting==AUTOCOMMON_ALWAYS && !IsValidClientZM() && live_SI<max_SI && available_SI>0 && (available_SI>1 || GetRandomFloat(0.0,1.0)<0.25) )
            {
               	ArrayList classes = new ArrayList();
               	for (int i = 1; i <= 6; i++)
               	{
               		if (costs_SI[i]>=0 && max_zombie_arr[i]>0 && available_zombie_arr[i]>0) classes.Push(i); 
               	}
               	if (classes.Length>0)
               	{
                   	int zClass;
                   	if (classes.Length==1) zClass = classes.Get(0);
                   	else zClass = classes.Get(GetRandomInt(0,classes.Length-1));
                    if (bank>=(3*costs_SI[zClass]))
                    {
                        int bot = ZM_Spawn_SI(0,zClass,false,false,_,false,true);
                        if (IsValidClient(bot)) DispatchKeyValue(bot, "targetname", "zm_unit");
                    }
                    
                }
                delete classes;
            }
            
            t_last_autocommon = t_now;
            
        }
        
   }
   
   if (zm_stage<ZM_STARTED && !zm_can_start) can_zm_start();
   
   // Double check that survivors havent left start area
   if ( zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && L4D_HasAnySurvivorLeftSafeArea() )
   {
       for (int i = 1; i <= MaxClients; i++)
   	   {
       		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
       		if (GetClientTeam(i)!=TEAM_SURVIVOR || i==zm_client) continue;
       		if (!client_in_start_area(i))
       		{
           		if (IsValidClientZM() && zm_can_start && !force_started)
           		{
               		start_zm_round();
               		break;
           		}
           		else if (!L4D_IsPlayerHangingFromLedge(i)) tp_survivor_start(i,true);
       		}
       }
   }
   
   t_last_update = t_now;
   
    // Check if witches were spotted to prevent refunds.
    float witch_pos[3];
    int entity = -1;
    int counted_witches = 0;
    char targetName[20];
    while ( ((entity = FindEntityByClassname(entity, "witch")) != -1) )
    {
    	 if (!IsValidEntity(entity)) continue;
    	 
           if (GetEntProp(entity,Prop_Data,"m_iHealth")<=0) continue;	 
    	   counted_witches += 1;
           if (g_iGlowList[entity]==INVALID_ENT_REFERENCE) CreateZMGlow(entity);
           GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
           if (strcmp(targetName,"zm_unit")==0)
           {
              GetEntPropVector(entity, Prop_Send, "m_vecOrigin", witch_pos);
              if (can_any_alive_survivor_see_cheap(witch_pos))
              {
                 DispatchKeyValue(entity, "targetname", "zm_unit_spotted");
                 update_hint("%T", "Witch sighted", zm_client);
                 request_update_glow(entity);
              }
           
           }
   }
   live_zombie_arr[ZOMBIECLASS_WITCH] = counted_witches; 
   
   if ( (panic || L4D_IsSurvivalMode() || ZM_finale_announced) && live_zombie_arr[ZOMBIECLASS_TANK]<=0
       && zm_stage==ZM_STARTED && !manual_panic && g_iCostCommon<0 && g_iCostUncommon<0
       && script_CommonLimit>0 && max_zombie_arr[ZOMBIECLASS_COMMON]>0 )
   {
       int lim = script_CommonLimit;
       if (lim>10) lim = 10;
       CreateTimer(0.1, Timer_Free_Angry_Zombies, lim, TIMER_FLAG_NO_MAPCHANGE);
   }
   
   // Track survivor changes. If new survivors spawn mid-round, ZM should get more bank to compensate.
   if (g_iAliveSurvivors!=bank_track_numplayers)
   {
        int player_diff = g_iAliveSurvivors - bank_track_numplayers;
        if (player_diff!=0 && (player_diff>0 || zm_stage<ZM_STARTED))
        {
            int d_bank;
            if (L4D_IsSurvivalMode()) d_bank = g_iBonusSurvival*player_diff;
            else if (ZM_finale_announced) d_bank = g_iBonusFinaleStage*player_diff;
            else d_bank = g_iBankInitialPlayer*player_diff;
            if (player_diff>0 && g_bRescueDoor && zm_stage==ZM_STARTED)
            {
                g_bRescueDoor = false;
                reset_available_zombies();
                if (IsValidClientZM())
                {
                    update_hint("Survivors rescued");
                    PrintToChat(zm_client, "[zm] Survivors rescued: bank added, cooldowns reset.");
                }
            }
            bank += d_bank;
        }
        bank_track_numplayers = g_iAliveSurvivors;
   }
   
   if (IsValidClientZM() && GetClientTeam(zm_client)!=TEAM_SURVIVOR)
   { 
      zm_fake_gamemode(); // have to run this periodically or it gets reset
      if (!IsPlayerAlive(zm_client))
      {
          if (GetEntityMoveType(zm_client)!=MOVETYPE_NONE) SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
          if (!IsValidEntRef(entref_control) && live_SI>0)
          {
              int client = GetRandomClient(TEAM_INFECTED,1,1);
              if (IsValidClient(client) && IsFakeClient(client) && L4D2_GetSurvivorVictim(client)<=0)
                  update_entref_control(EntIndexToEntRef(client),false);
          }
      }
      update_zm_flashlight();
      
      if (survival_activated && L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
      {
          if (IsValidEntity(info_director)) AcceptEntityInput(info_director, "ForcePanicEvent");
          else L4D_ForcePanicEvent();
          survival_activated = false;
      }
      
      if (zm_menu_state>ZM_MENU_CLOSED)
      {
          bool force_reopen = g_fMenuTimeout>=0.0 && GetClientAvgLatency(zm_client,NetFlow_Both)>=g_fMenuTimeout;
          RequestFrame(reopen_zm_menu,force_reopen);
      }
      
      if (g_fStopInactivity>0.0)
      {
          if (zm_allow_spawns && !IsPlayerAlive(zm_client) &&
              bank>=g_iBankInitial && live_SI<=0 && live_zombie_arr[ZOMBIECLASS_WITCH]<=0 &&
              !panic && live_zombie_arr[ZOMBIECLASS_COMMON]<=10)
          {
             
             if ((t_now-t_zm_activity)>=(g_fStopInactivity)/2.0)
             {
             
                 if (!zm_kick_notify)
                 {
                     //EmitSoundToAll(SOUND_INACTIVITY);
                     PrintHintText(zm_client, "%t", "Inactivity hint");
                     update_hint("%T", "zm_menu_hint", zm_client);
                     zm_kick_notify=true;
                 }
                 else if ((t_now-t_zm_activity)>=g_fStopInactivity)
                 {
                        PrintHintText(zm_client, "%t", "Inactivity notify kicked");
                        PrintToChatAll("[zm] %t", "Inactivity notify");
                        update_t_zm_activity(t_now);
                        QuitZM(zm_client,false);
                 }
             
             }
             
          }
          else update_t_zm_activity(t_now);
      }
      
      // Draw spawner visuals for ZM. Grid visualizer runs on its own timer
      if (zm_menu_state>ZM_MENU_CLOSED) Spawner_Update();
      else if (g_iSpawnerMode>0 && g_bGridReady && g_GridCellCount>0) GridRenderer_HideAll(zm_client); // grid needs to be hidden manually

      // Draw path to goal
      if (zm_draw_path && zm_menu_state>ZM_MENU_CLOSED && GetFeatureStatus(FeatureType_Native,"L4D_Path_To_Goal")==FeatureStatus_Available)
      {
            RequestFrame(zm_ptg);
      }
      
   }
   else
   {
      if (!IsValidClient(client_offer) && fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(1.0,fair_queue_update);
      if (!IsValidClientZM() && zm_client_userid!=-1)
      {
          zm_client = GetClientOfUserId(zm_client_userid);
          if (IsValidClientZM()) return Plugin_Continue;
      }
      
      if (g_hNoZMWarn.BoolValue && (t_now-t_zm_activity)>=10.0)
      {
         if (zm_stage<ZM_END && L4D_IsInIntro()<=0 && (fair_exhausted || zm_stage==ZM_STARTED ))
             PrintToChatAll("[zm] %t", "No ZM");
         update_t_zm_activity(t_now);
      }
      Spawner_OnDisabled(zm_client);
      zm_client = -1;
      zm_client_userid = -1;
   }
   
   //if (zm_stage==ZM_STARTED) update_director_script_scopes();
   
   update_EMS_HUD();
   
   if (zm_timer==INVALID_HANDLE)
   {
      zm_timer = CreateTimer(g_fUpdateRate,zm_update,_,TIMER_REPEAT);
      return Plugin_Stop;
   }
   return Plugin_Continue;
}

Action zm_new_round(Handle timer = null)
{
    invalidate_survivor_cache();
    if (!g_bCvarAllow)
    {
        zm_stage = ZM_END;
        return Plugin_Stop;
    }
    g_bRescueDoor = false;
    g_bVomitJar = false;
    g_hVomitJarTimer = null;
    g_iLastZombieClass = -1;
    
    if (g_bGrid && !GridLib_IsReady())
    {
        GridLib_Initialize();
        GridLib_StartPrecomputation();
    }
    Spawner_Init();
    if (g_CellCooldown) g_CellCooldown.Clear();
    cellcache_clear_all();

    if (g_hRandomizer.IntValue==2) random_gamemode();
    GetCvars();
    
    spawner_last_valid = false;
    
    set_zm_stage(ZM_NEWROUND,true);
    autocommon_setting = AUTOCOMMON_OFF;
    autocommon_uncommons = false;
    ZM_specials_frozen = false;
    specials_frozen = true;
    freeze_team(true,TEAM_INFECTED);
    recordpos = true;
    
    reset_time_of_day();
	
    set_force_start(false);
	meme_delivered = false;
	zm_win_announced = false;
	
	enable_challenge_mode();
	
	costs_SI[ZOMBIECLASS_TANK] = g_hCostTank.IntValue;
	first_tank_stage = 0;
	first_tank_price = 0;
	
	playcount_increased = false;
	reset_fair_queue();
	
	t_zm_join = 0.0;
	
	l4d2_specials = true;
    if (strcmp(g_sCvarMPGameMode,"l4d1coop")==0 || strcmp(g_sCvarMPGameMode,"l4d1survival")==0)
        l4d2_specials = false;
	
	fog_distance = FOG_DISTANCE;
	fog_distance_sq = FOG_DISTANCE * FOG_DISTANCE;

	roundcount += 1;
	
	saferoom_locked = false;
    
    if (DEBUG) LogMessage("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
    saferoom_interacted = false;
    if(L4D_IsSurvivalMode())
    {
        zm_allow_spawns = false;
        g_iLockedDoor = INVALID_ENT_REFERENCE;
    }
    else
    {
        zm_allow_spawns = true;
        check_saferoom();
    }
    
    manual_panic = false;
    delete_all_infected();
    
    ZM_finale_announced = false;
    zm_can_start = !g_bLockSaferoom;
    t_last_update = GetGameTime();
    t_last_panic = t_last_update;
    t_last_spawner_update = t_last_update;
    t_last_spawner_grid_update = t_last_update;
    t_last_spawner_sound = t_last_update;
    t_finale = t_last_update;
    t_last_action = t_last_update;
    update_t_zm_activity(t_last_update);
    t_last_autocommon = t_last_update;
    g_iAliveSurvivors = -1;
    
    for( int i = 1; i <= MaxClients; i++ )
	{
		if(!IsClientInGame(i)) continue;
		if (!IsFakeClient(i))
		{
    		//FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
    		if (GetClientTeam(i)==TEAM_INFECTED) QuitZM_Force(i);
		}
	}
	
	zm_client_userid = -1;
    Spawner_OnDisabled(zm_client);
    zm_client = -1;

    CountClients();
    CountWitches(false);
    CreateTimer(1.0,CountCommons,false,TIMER_FLAG_NO_MAPCHANGE);
    
    set_bank_begin();
    
    toggle_panic(false,true);
    
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
    if (shoot_alert_enable) SetConVarInt(shoot_alert_enable, 0);
    if (clown_world_enable && strcmp(g_sZMGamemode,"zm_clowns",false)==0) SetConVarInt(clown_world_enable, 1);
    if (jukebox_horde) SetConVarInt(jukebox_horde, 0);
    
    safezone_navAreaId = -1;
    
    int entity = -1;
   	while ((entity = FindEntityByClassname(entity, "func_playerinfected_clip")) != -1)
   	{	
   		if (IsValidEntity(entity)) AcceptEntityInput(entity, "Kill");
   	}
	
	fallen_spawned = false;
	jimmy_spawned = false;
	
	zm_menu_state = ZM_MENU_CLOSED;
	RequestFrame(update_menus);
	
	reset_available_zombies();
	
	info_director = FindEntityByClassname(-1, "info_director");
	if (g_DHook_AcceptInput && IsValidEntity(info_director)) // Listen to all info_director inputs
    	DHookEntity(g_DHook_AcceptInput, false, info_director, INVALID_FUNCTION, DHook_Director_AcceptInput);
	
	check_fog_distance();
	
	remove_all_ZM_glows();
	
	lastdoor = -1;
	
	update_director_script_scopes(false);
	//scope_changed = false;
	survival_activated = false;
	
	targetName_pending = "";
	model_pending = "";
	pending_tank = false;
    ignore_threat_pending = false;
	
	if (fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(1.0,fair_queue_update);
	
	infinite_delay_natural_mob();
	CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
	natural_first_wait = true;
	L4D2Direct_SetPendingMobCount(0);
	
	PrintToChatAll("[zm] Type /zm_help to read the Zombie Master tutorial.");
	
	zm_update();
	
	return Plugin_Continue;
    
}

// Count Survivor and Special Infected (Players AND Bots)
Action CountClients(Handle timer = null)
{
	clients_timer = INVALID_HANDLE;
	if (!g_bCvarAllow) return Plugin_Stop;
	
	if (DEBUG) LogMessage("[zm] CountClients");
	
	int allplayers = GetClientCount(false);
	if (allplayers<=0 || zm_stage>=ZM_END) return Plugin_Stop;
	
	int temp_SI,new_SI_cap, clientcount, new_AliveSurvivors, zClass, health = 0;
	reset_live_zombie_arr(false,false,true);
	
	new_SI_cap -= 1; // include ZM
	int last_valid_target = -1; // if only one SI on the field, auto select them for ZM control
	for (int i=1;i<=MaxClients;i++)
	{
		//LogMessage("[zm] CountClients %d", i);
		if (!IsClientConnected(i)) continue;
		clientcount += 1;
		
        //if (!IsFakeClient(i))
        //{
        //    if (i!=zm_client) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
        //}
        if (!IsClientInGame(i)) continue;
        if (IsFakeClient(i) && GetClientTeam(i)==TEAM_INFECTED) new_SI_cap += 1;
		
		if (!IsPlayerAlive(i))
		{
      		if (g_iGlowList[i]!=INVALID_ENT_REFERENCE) remove_ZM_glow(i);
      		L4D2_RemoveEntityGlow(i);
      		continue;
		}
		
		switch(GetClientTeam(i))
		{
			case TEAM_INFECTED:
			{
				if (zm_stage<ZM_PREP && IsFakeClient(i)) ForcePlayerSuicide(i); // fix The Sacrifice bug where 2 tanks spawn in the safe zone
     		    else if (!L4D_IsPlayerIncapacitated(i))
     		    {
         		   health = GetEntProp(i,Prop_Data,"m_iHealth");
         		   if (health>0)
         		   {
             		   temp_SI += 1;
             		   zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
             		   live_zombie_arr[zClass] += 1;
             		   if (L4D2_GetSurvivorVictim(i)<=0) last_valid_target = i;
             		   if (IsValidClientZM())
             		   {
                 		   int glowref = g_iGlowList[i];
                 		   if ( glowref==INVALID_ENT_REFERENCE || !IsValidEntity(glowref) )
                 		      CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(i), TIMER_FLAG_NO_MAPCHANGE);
         		       }
     		       }
     		    }
			}
			case TEAM_SURVIVOR: new_AliveSurvivors += 1;
		}
		
		if (clientcount>=allplayers) break;
		
	}
	
	new_SI_cap = MaxClients - allplayers + new_SI_cap;
	if (ZM_finale_announced || L4D_IsSurvivalMode()) new_SI_cap -= 1; // allow non-ZM Tanks to spawn
	if (new_SI_cap<0) new_SI_cap = 0;
	
	if (live_zombie_arr[ZOMBIECLASS_TANK]<=0)
	{
    	targetName_pending = "";
    	pending_tank = false;
    	model_pending = "";
        ignore_threat_pending = false;
    	if (first_tank_stage==FIRST_TANK_SPAWNED) first_tank_stage = FIRST_TANK_DEAD;
	}
	
	if (temp_SI==1 && IsValidEntity(last_valid_target)) update_entref_control(EntIndexToEntRef(last_valid_target),false);
	
	bool do_zm_update = false;
	if (new_AliveSurvivors!=g_iAliveSurvivors || new_SI_cap!=SI_cap)
	{
    	g_iAliveSurvivors = new_AliveSurvivors;
    	SI_cap = new_SI_cap;
    	get_bank_rate(); // for ZM UI
    	SetCvarsZM();
    	do_zm_update = true;
        survivor_items_changed();
	}
	if (live_SI!=temp_SI)
	{
	   live_SI = temp_SI;
	   do_zm_update = true;
	}
	
	if (IsValidClientZM() && do_zm_update)
	{
    	create_special_menu();
 	    create_boss_menu();
	}
	
	return Plugin_Stop;
	
}

public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	switch(key[0])
	{
    	case 'C':
    	{
        	if (strcmp(key, "CommonLimit", false) == 0) // stops director from spawning commons
        	{
        	    script_CommonLimit = retVal;
               	retVal = 0;
               	return Plugin_Handled;
        	}
    	}
    	case 'S':
    	{
        	//if (strcmp(key, "SpawnSetRule", false) == 0)
        	//{
            //   	retVal = SPAWN_ANYWHERE;
            //   	return Plugin_Handled;
        	//}
      		if (strcmp(key, "SpecialInfectedAssault", false) == 0) // makes specials less shit except smokers and chargers
          	{
                retVal = 1;
                return Plugin_Handled;
          	}
    	}
    	case 'c':
    	{
        	//if (strcmp(key, "cm_SpecialsRetreatToCover", false) == 0)
        	//{
            //   	retVal = 1;
            //   	return Plugin_Handled;
        	//}
        	
        	if (strcmp(key, "cm_AggressiveSpecials", false) == 0) // makes specials less shit except smokers and chargers
        	{
               	retVal = 1;
               	return Plugin_Handled;
        	}
        	if (strcmp(key, "cm_ShouldHurry", false) == 0)
        	{
               	retVal = 1;
               	return Plugin_Handled;
        	}
    	}
    	case 'W':
    	{
      		if (strcmp(key, "WitchLimit", false) == 0) // Witches always allowed
          	{
                 retVal = -1;
                 return Plugin_Handled;
          	}
    	}
    	case 'E':
    	{
        	if (strcmp(key, "EnforceFinaleNavSpawnRules", false) == 0) // might not do anything
        	{
               retVal = 0;
               return Plugin_Handled;
        	}
    	}
    	
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_bCvarAllow) return;
	switch (classname[0])
	{
    	case 'i':
    	{
        	if (live_zombie_arr[ZOMBIECLASS_COMMON]>0) return;
        	if (strcmp(classname,"infected",false)==0) CountCommons(null,false);
    	}
    	//case 't':
    	//{
        //	if (specials_frozen && strcmp(classname,"tank",false)==0)
        //	{
        //	//if (specials_frozen && strcmp(classname,"tank",false)==0)
        //	//{
        //    	SilentTank(entity);
        //    	RequestFrame(SilentTank,EntIndexToEntRef(entity));
        //	//}
        //	}
    	//}
	}
}

//void SilentTank(int entref)
//{
//    if (!IsValidEntRef(entref)) return;
    //SetEntProp(entref,Prop_Data,"m_nNextThinkTick",-1);
    //int nextTick = GetGameTickCount() + 1000;
    //SetEntProp(entref, Prop_Data, "m_nNextThinkTick", -1);
    //SetVariantString("idle"); 
    //AcceptEntityInput(entref, "SetAnimation");
    //SetVariantString("1"); 
    //AcceptEntityInput(entref, "SetCommentaryStatueMode");
    //RequestFrame(SilentTank,entref);
//}



public void OnLibraryRemoved(const char[] name)
{
  if (StrEqual(name,"adminmenu",false)) hAdminMenu = null;
}

// Prevent survivor suicide abuse
public Action L4D_OnFatalFalling(int client, int camera)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] L4D_OnFatalFalling");
    if (zm_stage<ZM_STARTED && IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client)==TEAM_SURVIVOR)
    {
        tp_survivor_start(client);
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg)
{	
	if (!g_bCvarAllow || zm_stage!=ZM_STARTED || finaleType==FINALE_NONE) return Plugin_Continue;
	int current = L4D2_GetCurrentFinaleStage();
	char current_label[32], label[32]; //
	get_finale_label(current,current_label);
	get_finale_label(finaleType,label);
	int pending_mob = L4D2Direct_GetPendingMobCount();
	if (DEBUG) LogMessage("[zm] L4D2_OnChangeFinaleStage %s -> %s %s, mob %d", current_label, label, arg, pending_mob);
    if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
       L4D2Direct_SetPendingMobCount(script_CommonLimit);
    return Plugin_Continue;
}

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg)
{   
    if (!g_bCvarAllow || L4D_IsSurvivalMode() || !ZM_finale_announced) return;

    if (finaleType==FINALE_CUSTOM_DELAY) return;
    
    if ( IsValidClientZM() && (finaleType==FINALE_HALFTIME_BOSS || finaleType==FINALE_FINAL_BOSS
                            || finaleType==FINALE_GAUNTLET_BOSS || finaleType==FINALE_CUSTOM_TANK ) )
        EmitSoundToClient(zm_client,SOUND_READY,_,_,_,_,_,GetRandomInt(95,105));
    
    available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    
    float t_now = GetGameTime();
    int add_bank = g_iBonusFinaleStage*g_iAliveSurvivors;
    if ( (t_now-t_finale)>=g_fMinFinaleStage || finaleType==FINALE_HORDE_ESCAPE ||
            finaleType==FINALE_GAUNTLET_ESCAPE || prev_finaleType==FINALE_HALFTIME_BOSS || prev_finaleType==FINALE_FINAL_BOSS ||
            prev_finaleType==FINALE_CUSTOM_TANK || prev_finaleType==FINALE_GAUNTLET_BOSS )
    {
        bank += add_bank;
        if (bank>2*add_bank) bank = 2*add_bank;
        else if (IsValidClientZM())
        {
            PrintHintText(zm_client, "%t", "ZM finale advance");
            EmitSoundToClient(zm_client,SOUND_REWARD);
        }
        t_finale = t_now;
    }
    
    prev_finaleType = finaleType;
    
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    announce_finale();
}

// Prevent ZM from deleting Commons for a while after a vomit jar detonates.
public void L4D2_VomitJar_Detonate_Post(int entity, int client)
{
    //if (!IsValidClient(client) || GetClientTeam(client)!=TEAM_SURVIVOR) return;
    g_bVomitJar = true;
    g_hVomitJarTimer = CreateTimer(VOMIT_JAR_DURATION,vomit_jar_reset,TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D2_OnRevived(int client)
{
    if (!g_bCvarAllow) return;
    if (DEBUG) LogMessage("[zm] L4D2_OnRevived %d", client);
    request_update_glow(client);
}

public void L4D_OnTakeOverBot_Post(int client, bool success)
{
    if (DEBUG) LogMessage("[zm] L4D_OnTakeOverBot_Post %d success %d", client, success);
    if (g_bCvarAllow && success) request_update_glow(client);
}

// This runs super frequently, can't run any logic here.
public void L4D2_OnDominatedBySpecialInfected(int victim, int dominator)
{
    if (!g_bCvarAllow || !IsValidClient(victim) || dominated[victim]) return;
    if (DEBUG) LogMessage("[zm] Dominated start %d", victim);
    dominated[victim] = true;
    request_update_glow(victim); // delayed by 0.1 sec
    CreateTimer(g_fUpdateRate,Check_Dominated,victim,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D_OnLedgeGrabbed_Post(int client)
{
    if (!g_bCvarAllow) return;
    request_update_glow(client);
}

public void L4D_OnEnterGhostState(int client)
{
    if (!g_bCvarAllow) return;
    if (DEBUG) LogMessage("[zm] L4D_OnEnterGhostState %d", client); 
    request_update_glow(client);  
}

public Action L4D_OnTryOfferingTankBot(int tank_index, bool &enterStasis)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	if (DEBUG) LogMessage("[zm] L4D_OnTryOfferingTankBot %d %d", tank_index, enterStasis);
	return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (!g_bCvarAllow || command[0]==0) return Plugin_Continue;
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Continue;
    first_active = true;
	set_client_active(null,client);
	return Plugin_Continue;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (!g_hSayHorde.BoolValue || L4D_IsInIntro()>0) return;
    if (max_zombie_arr[ZOMBIECLASS_COMMON]<=0 || (zm_stage!=ZM_STARTED && IsValidClientZM())) return;
    if (!IsValidClient(client) || GetClientTeam(client)!=TEAM_SURVIVOR) return;
    if (strcmp(command,"say_team")!=0) return;
    int num_args = RoundToCeil(1.0*strlen(sArgs)/2.5);
    if (num_args<=0) return;
    if (DEBUG) LogMessage("[zm] ZM_SayHorde %d %d", client, num_args);
   	if (live_zombie_arr[ZOMBIECLASS_COMMON]>=max_zombie_arr[ZOMBIECLASS_COMMON])
   	{
       	int zombie = INVALID_ENT_REFERENCE;
       	while ( (zombie=FindEntityByClassname(zombie,"infected"))!=INVALID_ENT_REFERENCE )
        {
    	   if (GetEntProp(zombie, Prop_Send, "m_mobRush")<=0)
    	   {
        	   SetEntProp(zombie, Prop_Send, "m_mobRush", 1);
        	   if (IsPlayerAlive(client)) command_infected_attack(zombie,client);
        	   num_args -= 1;
        	   if (num_args<=0) return;
    	   }
        }
    }
   	for (int i = 1; i <= num_args; i++)
   	{
   		CreateTimer(GetRandomFloat(0.1,10.0),Delayed_Free_Angry_Zombie,EntIndexToEntRef(client));
   	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion()!=Engine_Left4Dead2)
	{
		strcopy(error,err_max,"Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
	RegPluginLibrary("l4d2_zombie_master");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	infectedbots_enable = FindConVar("l4d_infectedbots_allow"); // l4d_infectedbots by HarryPotter https://github.com/fbef0102/L4D1_2-Plugins
	if (infectedbots_enable) SetConVarFlags(infectedbots_enable, GetConVarFlags(infectedbots_enable) & ~FCVAR_NOTIFY);
	jukebox_horde = FindConVar("l4d2_jukebox_horde_trigger"); // l4d2_jukebox_spawner by Silvers https://forums.alliedmods.net/showthread.php?t=149084
	if (jukebox_horde) SetConVarFlags(jukebox_horde, GetConVarFlags(jukebox_horde) & ~FCVAR_NOTIFY);
	shoot_alert_enable = FindConVar("l4d2_shoot_alert_common_enable"); // l4d2_shoot_alert_common https://forums.alliedmods.net/showthread.php?t=352360
	if (shoot_alert_enable) SetConVarFlags(shoot_alert_enable, GetConVarFlags(shoot_alert_enable) & ~FCVAR_NOTIFY);
	clown_world_enable = FindConVar("clown_world_enable"); // CLOWN WORLD - https://forums.alliedmods.net/showthread.php?t=352413
	if (clown_world_enable) SetConVarFlags(clown_world_enable, GetConVarFlags(clown_world_enable) & ~FCVAR_NOTIFY);
	SetCvarsZM();
}

public void L4D_OnIncapacitated_Post(int client, int inflictor, int attacker, float damage, int damagetype, int weapon)
{
    if (!g_bCvarAllow) return;
    request_update_glow(client);
    if (panic_target==client) panic_target = -1;
}

public Action evtPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    
    if (!g_bCvarAllow) return Plugin_Continue;
    
    // Skip victims that are not infected entities
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int health = GetEntProp(victim,Prop_Data,"m_iHealth");
    if (!IsValidClient(victim)) return Plugin_Continue;
    dominated[victim] = false;
    
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
    
    //L4D2_RemoveEntityGlow(victim);
    request_update_glow(victim,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(victim,true); 
    
    if(GetClientTeam(victim)!=TEAM_INFECTED)
    {
        if (GetClientTeam(victim)==TEAM_SURVIVOR) invalidate_survivor_cache(true);
        return Plugin_Continue;
    }
    
    char targetName[20];
    GetEntPropString(victim, Prop_Data, "m_iName", targetName, sizeof(targetName));
    
    if (active_looktarget && entref_control==EntIndexToEntRef(victim))
    {
        if (strcmp(targetName,"zm_unit_control")!=0 && strcmp(targetName,"zm_control")!=0)
            update_ZM_looktarget_HP(0);
        active_looktarget = false;
    }
    
    int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    
    if (DEBUG) LogMessage("[zm] evtPlayerDeath %d %d %s, %d HP", victim, zClass, targetName, health);
    
     // survival: every non-ZM tank death gives ZM bank
    if (zClass==ZOMBIECLASS_TANK && L4D_IsSurvivalMode())
    {
        
        if (strcmp(targetName,"zm_unit")!=0 && strcmp(targetName,"zm_unit_control")!=0
             && strcmp(targetName,"zm_unit_dead")!=0 && strcmp(targetName,"zm_control_dead")!=0 )
        {
            if (DEBUG) LogMessage("[zm] Survival non-ZM tank died");
            bank += g_iBonusSurvival*g_iAliveSurvivors;
            update_hint("%T", "Tank died reward", zm_client);
            if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_REWARD);
        }
    }
    
    // Begin availability countdown.
    // Set targetname to something indicating countdown has started to avoid double countdown
    if (strcmp(targetName,"zm_unit")==0 || strcmp(targetName,"zm_unit_control")==0)
    {
        DispatchKeyValue(victim, "targetname", "zm_unit_dead");
        create_timer_add_available_zombie(get_class_cooldown(zClass),zClass,roundcount);
        
        if (zClass==ZOMBIECLASS_TANK && first_tank_stage==FIRST_TANK_SPAWNED)
            first_tank_stage = FIRST_TANK_DEAD;
        
    }

    // ZM controlling special infected has died
    if (victim==zm_client)
    {
        if (panic_target==zm_client) panic_target = -1;
        DispatchKeyValue(zm_client, "targetname", "zm_client");
        SetEntityMoveType(zm_client, MOVETYPE_NONE);
        RequestFrame(ZM_FixCamera,true);
        if (zClass==ZOMBIECLASS_TANK) CreateTimer(1.0,stop_tankmusic,TIMER_FLAG_NO_MAPCHANGE);
    }
    
    remove_ZM_glow(victim);

	return Plugin_Continue;
}

public Action L4D_OnVomitedUpon(int victim, int &attacker, bool &boomerExplosion)
{
    if (!g_bCvarAllow) return Plugin_Continue;      
    if (DEBUG) LogMessage("[zm] L4D_OnVomitedUpon");
    if (IsValidClient(victim) && GetClientTeam(victim)==TEAM_SURVIVOR)
        update_vomited(victim);
    return Plugin_Continue;
}

public Action Event_PlayerUnBoomed(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (DEBUG) LogMessage("[zm] Event_PlayerUnBoomed %d", victim); 
    update_glow(victim);
    request_update_glow(victim);
    return Plugin_Continue;
}

public Action EvtWitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] EvtWitchKilled");
    int witch = event.GetInt("witchid");
    remove_ZM_glow(witch);
	return Plugin_Continue;
}

public void OnMapStart()
{
    if (DEBUG) LogMessage("[zm] OnMapStart");

	PluginPrecacheModel(MODEL_SMOKER);
	PluginPrecacheModel(MODEL_BOOMER);
	PluginPrecacheModel(MODEL_HUNTER);
	PluginPrecacheModel(MODEL_SPITTER);
	PluginPrecacheModel(MODEL_JOCKEY);
	PluginPrecacheModel(MODEL_CHARGER);
	PluginPrecacheModel(MODEL_TANK);
	
	PluginPrecacheModel(MODEL_RIOT); // Riot Police
	PluginPrecacheModel(MODEL_RIOT2); // Riot Police
	PluginPrecacheModel(MODEL_CEDA); // CEDA Hazmat
	PluginPrecacheModel(MODEL_CEDA2); // CEDA Hazmat
	PluginPrecacheModel(MODEL_CLOWN); // Clown
	PluginPrecacheModel(MODEL_MUD); // Mud
	PluginPrecacheModel(MODEL_MUD2); // Mud
	PluginPrecacheModel(MODEL_ROAD); // Road Worker
	PluginPrecacheModel(MODEL_ROAD2); // Road Worker
	PluginPrecacheModel(MODEL_ROAD3); // Road Worker
	PluginPrecacheModel(MODEL_ROAD4); // Road Worker
	PluginPrecacheModel(MODEL_JIMMY); // Jimmy Gibbs
	PluginPrecacheModel(MODEL_FALLEN); // Fallen Survivor
	PluginPrecacheModel(MODEL_FALLEN2); // Fallen Survivor
	PluginPrecacheModel(MODEL_FALLEN3); // Fallen Survivor
	
	g_ExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
	g_iLaser = PrecacheModel(VMT_LASERBEAM, true);
	g_iHalo = PrecacheModel(VMT_HALO, true);
	
	PrecacheSound(SOUND_REWARD);
	PrecacheSound(SOUND_READY);
	PrecacheSound(SOUND_OFFER);
	PrecacheSound(SOUND_BUG);
	PrecacheSound(SOUND_DOORSLAM);
	PrecacheSound(SOUND_DOORSLAM2);
	PrecacheSound(SOUND_DOORSLAM3);
    PrecacheSound(SOUND_START);
    PrecacheSound(SOUND_VISION);
    
    PrecacheSound(EXPLOSION1);
    PrecacheSound(EXPLOSION2);
    PrecacheSound(EXPLOSION3);
    
    if (g_bMemes)
    {
        //lipsync_available = FileExists(VCD_ELLIS_ZM) && FileExists(VCD_LOUIS_ZM);
        //lipsync_available = false; // vcd is failing, reverting to mp3 for now
        //if (lipsync_available)
        //{
            //bool check1 = PrecacheSound(SOUND_ELLIS_ZM);
            //bool check2 = PrecacheSound(SOUND_LOUIS_ZM);
            //int ssEllis = PrecacheScriptSound(SS_ELLIS_ZM);
            //int ssLouis = PrecacheScriptSound(SS_LOUIS_ZM);
            //PrecacheGeneric(VCD_ELLIS_ZM, true);
            //PrecacheGeneric(VCD_LOUIS_ZM, true);
            //lipsync_available = check1 && check2 && ssEllis!=0 && ssLouis!=0;
           // lipsync_available = check1 && check2;
            //LogMessage("[zm] lipsync state: %d %d %d %d", check1, check2, ssEllis, ssLouis);
        //}
        
        //if (!lipsync_available)
        //{
           PrecacheSound(SOUND_ELLIS_ZM_MP3);
           PrecacheSound(SOUND_LOUIS_ZM_MP3);
           PrecacheSound(SOUND_ELLIS_ZM_FAKE);
           PrecacheSound(SOUND_LOUIS_ZM_FAKE);
           PrecacheSound(SOUND_FRANCIS_ZM_FAKE);
           PrecacheSound(SOUND_FRANCIS_ZM_MP3);
           PrecacheSound(SOUND_ZOEY_ZM_MP3);
           PrecacheSound(SOUND_ZOEY_ZM_FAKE);
           PrecacheSound(SOUND_NICK_ZM_MP3);
           PrecacheSound(SOUND_NICK_ZM_FAKE);
           PrecacheSound(SOUND_COACH_ZM_MP3);
           PrecacheSound(SOUND_COACH_ZM_FAKE);
        //}
        
        //fastdl is necessary otherwise client will hang FOREVER on a black screen.
        if (FindConVar("sv_allowdownload").BoolValue)
        {
            ConVar g_hDownloadUrl = FindConVar("sv_downloadurl");
            if (g_hDownloadUrl!=null)
            {
                char currentUrl[256];
                g_hDownloadUrl.GetString(currentUrl,sizeof(currentUrl));
                TrimString(currentUrl);
                if (currentUrl[0]=='\0') g_hDownloadUrl.SetString("https://gvazdas.github.io/l4d2_zombie_master/left4dead2", false, false);
            }
            
            char buffer[128];
            //if (lipsync_available) Format(buffer, sizeof(buffer), "sound/%s", SOUND_ELLIS_ZM);
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_ELLIS_ZM_MP3);
            AddFileToDownloadsTable(buffer);
            
            //if (lipsync_available) Format(buffer, sizeof(buffer), "sound/%s", SOUND_LOUIS_ZM);
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_LOUIS_ZM_MP3);
            AddFileToDownloadsTable(buffer); 
            
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_FRANCIS_ZM_MP3);
            AddFileToDownloadsTable(buffer);
            
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_ZOEY_ZM_MP3);
            AddFileToDownloadsTable(buffer);
            
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_NICK_ZM_MP3);
            AddFileToDownloadsTable(buffer); 
            
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_COACH_ZM_MP3);
            AddFileToDownloadsTable(buffer); 
        
            //if (lipsync_available)
            //{
            //    AddFileToDownloadsTable(VCD_ELLIS_ZM);
            //	AddFileToDownloadsTable(VCD_LOUIS_ZM); 
        	//}
        }
        //else lipsync_available = false;
        
        //if (!lipsync_available) LogMessage("[zm] custom lipsynced voice lines cannot be played."); 
    }
    
    //if (g_hGrid.BoolValue)
        GridRendererProp_PrecacheAssets();

    PrecacheSound(SOUND_PANIC_ON);
    PrecacheSound(SOUND_PANIC_OFF);
    
    PrecacheSound(SOUND_SCARY1);
    PrecacheSound(SOUND_SCARY2);
    PrecacheSound(SOUND_SCARY3);
    PrecacheSound(SOUND_SCARY4);
    PrecacheSound(SOUND_SCARY5);
    
    PrecacheSound(SOUND_BLOCKED);
    PrecacheSound(SOUND_CONDITIONAL);
    PrecacheSound(SOUND_HITMARKER);

	g_bSpawnWitchBride = false;
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	if(StrEqual("c6m1_riverbank", sMap, false)) g_bSpawnWitchBride = true;
	else g_bSpawnWitchBride = false;
	
	saferoom_locked = false;
	zm_can_start = false;
	zm_stage = 0;
	
	if (g_bCvarAllow)
	{
    	if (g_hRandomizer.IntValue==1) random_gamemode();
    	if (IsValidClientZM()) QuitZM_Force(zm_client);
    	if (!g_bNavReady)
    	{
        	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
        	g_bNavReady = false;
        	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
    	}
    	zm_update();
    	if (g_bGrid && !GridLib_IsReady())
        {
            GridLib_Initialize();
            GridLib_StartPrecomputation();
        }
	}

	// env_shake needs to be "precached"
	int shake = CreateEntityByName("env_shake");
	if( shake != -1 )
	{
		DispatchKeyValue(shake, "spawnflags", "8");
		DispatchKeyValue(shake, "amplitude", "16.0");
		DispatchKeyValue(shake, "frequency", "1.5");
		DispatchKeyValue(shake, "duration", "0.9");
		DispatchKeyValue(shake, "radius", "50");
		TeleportEntity(shake, view_as<float>({ 0.0, 0.0, -1000.0 }), NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(shake);
		ActivateEntity(shake);
		AcceptEntityInput(shake, "Enable");
		AcceptEntityInput(shake, "StartShake");
		RemoveEdict(shake);
	}
	
	g_bMapStarted = true;
	
}

public void OnMapEnd()
{
	if (DEBUG) LogMessage("[zm] OnMapEnd");
	invalidate_survivor_cache();
	Spawner_Cleanup();
	if (GridLib_IsReady()) GridLib_Cleanup();
	if (!g_bCvarAllow) return;
	g_bRescueDoor = false;
	g_iLockedDoor = INVALID_ENT_REFERENCE; // we don't know if there's gonna be a door next map
	ResetTimer();
	zm_stage = ZM_END;
	clients_in_server = false;
	update_EMS_HUD();
	
	// Clean up pre-computed data
    if (g_hStartAreaList != null)
    {
    	delete g_hStartAreaList;
    	g_hStartAreaList = null;
    }
    g_bNavReady = false;
    lastdoor = -1;
    //scope_changed = false;
    g_bMapStarted = false;
    first_active = false;
    reset_time_of_day();
}

// this runs very frequently, find a better way.
bool use_pressed, reload_pressed = false;
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse)
{
    if (!g_bCvarAllow || !IsValidClient(client)) return Plugin_Continue;
	
	if (g_fAbilityCooldown>=0.0 && IsPlayerAlive(client) && GetClientTeam(client)==TEAM_INFECTED)
	{
    	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
    	if (IsValidEntity(ability))
    	{
        	float gametime = GetGameTime();
        	float cooldown = GetEntPropFloat(ability,Prop_Send,"m_timestamp") - gametime;
        	if (cooldown>g_fAbilityCooldown && cooldown<3000.0) SetEntPropFloat(ability,Prop_Send,"m_timestamp",gametime+g_fAbilityCooldown);
    	}
	}
	
	if (IsFakeClient(client)) return Plugin_Continue;

	if (buttons>0 || impulse>0)
	{
    	first_active = true;
    	set_client_active(null,client);
	}
	
	if (client!=zm_client) return Plugin_Continue;
	
   	if (recordpos && IsPlayerAlive(zm_client)) // move this to controlSI and player_death
   	{
       	GetClientEyePosition(zm_client,zm_deathPos);
        GetClientEyeAngles(zm_client,zm_deathAngles);
   	}
   	update_ZM_looktarget(true);
   	
   	if (buttons&IN_USE>0)
   	{
       	if (!use_pressed)
       	{
           	if (live_SI>0) ZMControlSI(client,0);
           	else open_menu(client,ZM_MENU_SPECIAL);
           	use_pressed = true;
       	}
   	}
   	else use_pressed = false;
   	
   	if (buttons&IN_RELOAD>0)
   	{
       	if (!reload_pressed)
       	{
           	if (zm_menu_state==ZM_MENU_MAIN) close_menus(client);
           	else open_menu(client,ZM_MENU_MAIN);
           	reload_pressed = true;
       	}
   	}
   	else reload_pressed = false;
   	
   	if (impulse==100) toggle_ZM_vision(client);
        
    if (zm_stage<ZM_STARTED && !zm_can_start && !force_started) buttons &= ~IN_ATTACK & ~IN_ATTACK2;
	return Plugin_Continue;	
}

public void OnConfigsExecuted()
{
    if (DEBUG) LogMessage("[zm] OnConfigsExecuted");
	IsAllowed();
}

void evtRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	
	if (DEBUG) LogMessage("[zm] evtRoundEnd");
    
    invalidate_survivor_cache();
    if (!g_bCvarAllow)
    {
        zm_stage = ZM_END;
        return;
    }
    
	bool ZM_won = true;
	for( int i = 1; i <= MaxClients; i++ )
	{
		if (!IsClientInGame(i)) continue;
		if(!IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
	    L4D2_RemoveEntityGlow(i);
	    if (GetClientTeam(i)==TEAM_INFECTED)
	    {
    	    if (i!=zm_client && !IsFakeClient(i)) QuitZM_Force(i);
    	    continue;
		}
		if ( IsPlayerAlive(i) && !L4D_IsPlayerIncapacitated(i)  ) 
		{
    		ZM_won = false;
		}
		
	}
	if (IsValidClientZM())
	{
    	if (ZM_won && !zm_win_announced)
    	{
        	zm_win_announced = true;
        	EmitSoundToClient(zm_client,SOUND_ZM_WIN);
        	PrintHintText(zm_client, "%t", "ZM win text");
        	char zm_name[MAX_NAME_LENGTH]; 
            GetClientName(zm_client,zm_name,sizeof(zm_name));
            PrintToChatAll("[zm] %d %t", bank, "ZM won", zm_name);
    	}
    	QuitZM_Force(zm_client); // InputKill prevention
	}
	g_iLockedDoor = INVALID_ENT_REFERENCE;
	saferoom_locked = false;
	set_zm_stage(ZM_END,true);
	ResetTimer();
	update_EMS_HUD();
	
}

void evtRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
	if (DEBUG) LogMessage("[zm] evtRoundStart");
	if (IsValidClientZM()) QuitZM_Force(zm_client);
	g_iLockedDoor = INVALID_ENT_REFERENCE;
	saferoom_locked = false;
	set_zm_stage(ZM_NEWROUND,true);
	CreateTimer(0.1,zm_new_round,TIMER_FLAG_NO_MAPCHANGE);
}

void Event_SurvivalRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
	if (DEBUG) LogMessage("[zm] Event_SurvivalRoundStart");
    manual_panic = false;
    RequestFrame(start_zm_round);
}

public void L4D_OnFinishIntro()
{
    if (!g_bCvarAllow) return;
    if (DEBUG) LogMessage("[zm] L4D_OnFinishIntro");
    if (fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(0.1,fair_queue_update);
    if (g_bLockSaferoom) freeze_team(false);
    
}

//public Action L4D_OnMobRushStart()
//{
//    if (!g_bCvarAllow) return Plugin_Continue;
//    int pending_mob = L4D2Direct_GetPendingMobCount();
//    if (DEBUG) LogMessage("[zm] L4D_OnMobRushStart %d", pending_mob);
//    //update_director_script_scopes();
//    return Plugin_Stop;
//}

public Action L4D_OnSpawnMob()
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return Plugin_Continue;
    if (g_bMemes && !meme_delivered)
    {
        float delay = GetRandomFloat(0.1,10.0);
        CreateTimer(delay,random_meme,TIMER_FLAG_NO_MAPCHANGE);
    }
    if (DEBUG)
    {
        int pending_mob = L4D2Direct_GetPendingMobCount();
        LogMessage("[zm] L4D_OnSpawnMob %d", pending_mob);
    }
    check_panic(true);
    //update_director_script_scopes();
    return Plugin_Stop;
}

// hide zm_ cvar change spam due to gamemode changes
Action Event_ServerCvar(Handle event, char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	char sConVarName[64];
	GetEventString(event, "cvarname", sConVarName, sizeof(sConVarName));
	if (StrContains(sConVarName,"zm_",false)==0) return Plugin_Handled;
	return Plugin_Continue;
}

// Bot replaced a player
Action EvtBotReplacePlayer(Event event, const char[] name, bool dontBroadcast) 
{
    int bot = GetClientOfUserId(event.GetInt("bot"));
    int client = GetClientOfUserId(event.GetInt("player"));
    if (DEBUG) LogMessage("[zm] EvtBotReplacePlayer %d replaced %d", bot, client);
    request_update_glow(client,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(client,true); 
    request_update_glow(bot,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(bot,true); 
    if (GetEntityFlags(client) & FL_DUCKING)
    {
        request_crouch(EntIndexToEntRef(bot));
        RequestFrame(request_crouch,EntIndexToEntRef(bot));
    }
    return Plugin_Continue;
}

// Player replaced a bot
Action EvtPlayerReplaceBot(Event event, const char[] name, bool dontBroadcast)
{
    int bot = GetClientOfUserId(event.GetInt("bot"));
    int client = GetClientOfUserId(event.GetInt("player"));
    if (DEBUG) LogMessage("[zm] EvtPlayerReplaceBot %d replaced %d", client, bot);
    request_update_glow(client,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(client,true); 
    request_update_glow(bot,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(bot,true); 
    if (GetEntityFlags(bot) & FL_DUCKING)
    {
        request_crouch(EntIndexToEntRef(client));
        RequestFrame(request_crouch,EntIndexToEntRef(client));
    }
    return Plugin_Continue;
}

void EvtPlayerRescued(Event event, const char[] name, bool dontBroadcast)
{
    int victim = event.GetInt("victim");
    if (IsValidClient(victim)) request_update_glow(victim);
}

void EvtRescueDoorOpen(Event event, const char[] name, bool dontBroadcast)
{
    g_bRescueDoor = true;
    CreateTimer(2.0*g_fUpdateRate,Timer_reset_rescue_door,TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_reset_rescue_door(Handle timer)
{
    g_bRescueDoor = false;
    return Plugin_Stop;
}

void EvtPlayerCallHelp(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) UpdateSurvivorGlow(client);
}

//MRESReturn DTR_CBaseEntity_InputKill(int pThis)
//{
//	if (pThis==zm_client && IsValidClientZM()) 
//	{
//	    LogMessage("[zm] CBaseEntity_InputKill %d -> MRES_Supercede", pThis);
//    	return MRES_Supercede;
//	}
//	
//    return MRES_Ignored;
//	
//}

//MRESReturn DTR_CBaseEntity_InputKillHierarchy(int pThis)
//{
//	if (pThis==zm_client && IsValidClientZM()) 
//	{
//	    LogMessage("[zm] CBaseEntity_InputKillHierarchy %d -> MRES_Supercede", pThis);
//    	return MRES_Supercede;
//	}
//	
//	return MRES_Ignored;
//	
//}

public void OnPluginEnd()
{
    if (DEBUG) LogMessage("[zm] OnPluginEnd");
    if (IsValidClientZM()) ChangeClientTeam(zm_client,TEAM_SURVIVOR);
    Spawner_OnDisabled(zm_client);
    zm_client = -1;
    if (saferoom_locked) saferoom_lock(false);
    ResetTimer();
    ResetCvars();
    reset_time_of_day();
    zm_stage = ZM_END;
}

void Event_TriggeredCarAlarm(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    if (DEBUG) LogMessage("[zm] Event_TriggeredCarAlarm");
    if (zm_stage==ZM_STARTED)
    {
        bank += g_iBonusCarAlarm;
        PrintToChatAll("[zm] %t", "Car alarm notify", g_iBonusCarAlarm);
        manual_panic=false;
        if (!panic)
        {
            toggle_panic(true,true,true); // free panic!
        }
        else
        {
            bank += g_iPanicCost;
            t_last_panic = GetGameTime();
        }
    }
    
    int victim = GetClientOfUserId(event.GetInt("userid"));
    spawn_free_angry_zombies(victim,25);
}

void evtPlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    
   	   int client = GetClientOfUserId(event.GetInt("userid"));
   	   if (DEBUG) LogMessage("[zm] evtPlayerSpawned %d", client);
   	   dominated[client] = false;
   	   if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
       if (zm_timer==INVALID_HANDLE) zm_update();
   	   request_update_glow(client);
   	   if (!IsPlayerAlive(client)) return;
   	   if (GetClientTeam(client)==TEAM_SURVIVOR)
   	   {
       	   if (g_bLockSaferoom && L4D_IsInIntro()>0) freeze_player(client);
       	   invalidate_survivor_cache(true);
   	   }
   	   else if (GetClientTeam(client)==TEAM_INFECTED)
   	   {
   	    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	    if (zClass==ZOMBIECLASS_TANK)
       	{
           	if (g_hNoTanks.BoolValue)
           	{
               	ForcePlayerSuicide(client);
               	return;
           	}
           	else if (pending_tank)
           	{
               	int health = GetEntProp(client,Prop_Data,"m_iHealth");
               	if (DEBUG) LogMessage("[zm] Applied pending targetname and model %s %s", targetName_pending, model_pending);
               	if (health>1) SetEntProp(client,Prop_Data,"m_iHealth",health-1); // prevent possible same-frame refund exploit
               	DispatchKeyValue(client, "targetname", targetName_pending);
               	SetEntProp(client,Prop_Data,"m_iMaxHealth", maxhp_pending);
                ignore_threats[client] = ignore_threat_pending;
               	if (model_pending[0]!=0)
               	{
                   	SetEntityModel(client, model_pending);
                   	RequestFrame(NextFrame_SetModel,EntIndexToEntRef(client));
               	}
           	}
       	}
       	if (specials_frozen && IsFakeClient(client) && !ignore_threats[client]) freeze_player(client,true,TEAM_INFECTED);
      }
}

void EvtSurvivorItem(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client)!=TEAM_SURVIVOR) return;
    survivor_items_changed();
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow || !specials_frozen || zm_stage!=ZM_STARTED) return; 
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(victim) && !ignore_threats[victim] && IsFakeClient(victim) && GetClientTeam(victim)==TEAM_INFECTED)
    {
        int client = GetClientOfUserId(event.GetInt("attacker"));
       	if (IsValidClient(client) && GetClientTeam(client)!=TEAM_INFECTED)
       	{
           set_specials_frozen(false);
           if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_START,_,_,_,_,_,GetRandomInt(95,105));
       	}
    }
}

// called only on players: survivors and specials
void EvtPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (DEBUG) LogMessage("[zm] EvtPlayerHurt %d", client);
	request_update_glow(client);
	
	if (specials_frozen && zm_stage==ZM_STARTED && !ignore_threats[client] && IsFakeClient(client) && GetClientTeam(client)==TEAM_INFECTED)
    {
       	int attacker = event.GetInt("attackerentid");
       	if (IsValidClient(attacker) && GetClientTeam(attacker)!=TEAM_INFECTED)
       	{
           set_specials_frozen(false);
           if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_START,_,_,_,_,_,GetRandomInt(95,105));
       	}
    }
}

void EvtPlayerHeal(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
	int client = GetClientOfUserId(event.GetInt("subject"));
	request_update_glow(client);
    survivor_items_changed();
}

void evtPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    if (DEBUG) LogMessage("[zm] evtPlayerTeam %d", client);
    request_update_glow(client,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(client,true); 
    if (zm_timer==INVALID_HANDLE) zm_update();
    if (zm_client==client) RequestFrame(check_zm_team);
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    if (!g_bCvarAllow) return;
    infinite_delay_natural_mob();
    CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.0,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
}

void evt_ZM_start_imminent(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    if (zm_timer==INVALID_HANDLE) zm_update();
    //LogMessage("[zm] evt_ZM_start_imminent");
    if (zm_stage<ZM_STARTED)
    {
        infinite_delay_natural_mob();
        CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
        if (L4D_IsSurvivalMode()) return;
        int client = GetClientOfUserId(event.GetInt("userid"));
        if (!IsValidClient(client)) return;
        if (!IsPlayerAlive(client)) return;
        if (GetClientTeam(client)!=TEAM_SURVIVOR) return;
        if (client==zm_client) return;
        if (!zm_can_start) can_zm_start();
        if (zm_can_start && !client_in_start_area(client) && IsValidClientZM() && !force_started)
            start_zm_round();
        else if (g_bLockSaferoom && saferoom_locked && L4D_IsInIntro()<=0)
            tp_survivor_start(client,true);
    }
}

public void OnClientPutInServer(int client)
{
	if(!g_bCvarAllow) return;
	if (!IsValidClient(client)) return;
	if (DEBUG) LogMessage("[zm] OnClientPutInServer %d", client);
	hp_timers[client] = null;
    request_update_glow(client,true,0.0); // Force update glow to reduce glow glitches.
    request_update_glow(client,true); 
	clients_active[client] = false;
	clients_offered[client] = false;
	dominated[client] = false;
	if (!IsFakeClient(client))
	{
       	clients_in_server = true;
       	t_last_join = GetGameTime();
       	if (DEBUG) LogMessage("[zm] t_last_join updated");
       	CreateTimer(15.0,set_client_active,client,TIMER_FLAG_NO_MAPCHANGE);
       	if (fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(2.0,fair_queue_update);
	}
	
	if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
	if (zm_timer==INVALID_HANDLE) zm_update();
}

public void OnClientConnected(int client)
{
    if (!g_bCvarAllow || IsFakeClient(client)) return;
    clients_t_join[client] = GetGameTime();
    clients_offered[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
    if (!g_bCvarAllow || IsFakeClient(client)) return;
    if (DEBUG) LogMessage("[zm] OnClientPostAdminCheck %d", client);
    create_client_data(client);
}

public void OnClientDisconnect(int client)
{
	if (!g_bCvarAllow) return;
	if (client<=0) return;
	hp_timers[client] = null;
	L4D2_RemoveEntityGlow(client);
	clients_active[client] = false;
	if (!IsValidClient(client)) return;

	   if (DEBUG) LogMessage("[zm] OnClientDisconnect %d", client);
	   if (!IsFakeClient(client) && fq_timer==INVALID_HANDLE)
    	   fq_timer = CreateTimer(0.1,fair_queue_update);
	   if (zm_timer==INVALID_HANDLE) zm_update();
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
       if (zm_client==client)
       {
   	      if (DEBUG) LogMessage("[zm] OnClientDisconnect ZM disconnected");
   	      update_t_zm_activity(0.0); 
   	      QuitZM_Force(zm_client);
   	      if (zm_stage<ZM_STARTED) can_zm_start();
   	   } 
    
}

// Refund zombie delete
public void OnEntityDestroyed(int entity)
{
    if ( !g_bCvarAllow || zm_stage<ZM_PREP || !IsValidEntity(entity) ) return;
    
	int max_health = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
	//if (DEBUG) LogMessage("[zm] OnEntityDestroyed MaxHP %d", max_health);
	if (max_health && max_health>0)
    {
	      int health = GetEntProp(entity,Prop_Data,"m_iHealth");
	      bool refund = (health>=max_health);
	      
          char targetName[32];
          GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
          char class[32];
          GetEntityClassname(entity, class, sizeof(class));
          
          // Check only for: zm units, spotted zm units, and infected
          if ( !(strcmp(targetName,"zm_unit")==0 || strcmp(targetName,"zm_unit_spotted")==0 || strcmp(class,"infected")==0) )
              return;
       	  
       	  int bank_refund = -1;
       	  
       	  if (strcmp(class,"infected")==0)
       	  {
      	     if (refund)
      	     {
          	     if (strcmp(targetName,"zm_unit_common")==0 || strcmp(targetName,"zm_unit")==0)
              	     bank_refund = g_iCostCommon;
          	     else if (strcmp(targetName,"zm_unit_uncommon")==0)
              	     bank_refund = g_iCostUncommon;
      	         add_available_zombie(ZOMBIECLASS_COMMON,1);
  	         }
   	      }
       	  else if (strcmp(class,"witch")==0)
       	  {
       	     
       	     if (strcmp(targetName,"zm_unit")!=0 && strcmp(targetName,"zm_unit_spotted")!=0 ) return;
       	     if (refund && strcmp(targetName,"zm_unit_spotted")==0) refund = false;
       	     
       	     if (refund)
       	     {
       	         // Figuring out if witch is stationary or moving
           	     int m_nSequence = GetEntProp(entity,Prop_Data,"m_nSequence");
           	     if (m_nSequence==4 || m_nSequence==27)
           	     {
               	     bank_refund = g_iCostWitchStatic;
               	     if (DEBUG) LogMessage("[zm] Refunding static witch");
           	     }
           	     else if (m_nSequence==10 || m_nSequence==11 || m_nSequence==2)
           	     {
               	     bank_refund = g_iCostWitchMoving;
               	     if (DEBUG) LogMessage("[zm] Refunding moving witch");
           	     }
           	     if (bank_refund<0)
           	     {
               	     if (DEBUG) LogMessage("[zm] Refunding cheapest witch");
               	     if (g_hCostWitchStatic<g_hCostWitchMoving) bank_refund=g_iCostWitchStatic;
               	     else bank_refund=g_iCostWitchMoving;
           	     }
           	     add_available_zombie(ZOMBIECLASS_WITCH,1);
       	     }
       	     else
       	     {
           	     create_timer_add_available_zombie(g_fWitchCooldown,ZOMBIECLASS_WITCH,roundcount);
       	     }
       	  }
       	  else if (strcmp(class,"player")==0 && GetClientTeam(entity)==TEAM_INFECTED)
       	  {
           	 int client = EntRefToEntIndex(entity);
           	 if ( !IsClientInGame(client) || !IsPlayerAlive(client)) return;
           	 if (L4D_IsPlayerIncapacitated(entity)) return;
           	 int zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
             if (zClass<ZOMBIECLASS_SMOKER || zClass>ZOMBIECLASS_TANK || zClass==7) return;
             
             // Prevent refunds if ability is still on cooldown
             if (zClass!=ZOMBIECLASS_HUNTER) //  Hunters don't have cooldown
             {
                 int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
                 if (ability > 0 && IsValidEdict(ability))
                 {
                     if ((GetEntPropFloat(ability, Prop_Send, "m_timestamp")-GetGameTime())>1.0) 
                         refund = false;
                 }
             }

             if (refund)
             {
                 if (zClass==ZOMBIECLASS_TANK)
                 {
                     if (first_tank_stage==FIRST_TANK_SPAWNED)
                     {
                         bank_refund = first_tank_price;
                         first_tank_stage = 0;
                         update_dynamic_tank();
                     }
                     else bank_refund = g_hCostTank.IntValue;
                 }
                 else bank_refund = costs_SI[zClass];
                 add_available_zombie(zClass,1);
             }
             else
             {
                 float cooldown_time;
                 if (zClass==ZOMBIECLASS_TANK)
                 {
                     cooldown_time = g_fTankCooldown;
                     if (first_tank_stage==FIRST_TANK_SPAWNED) first_tank_stage += 1;
                 }
                 else cooldown_time = g_fSpecialCooldown;
        	     create_timer_add_available_zombie(cooldown_time,zClass,roundcount);
             }
       	  }
       	  else return;
       	  
       	  if (refund && bank_refund>0)
       	  {
           	  bank += bank_refund;
           	  if (DEBUG) LogMessage("OnEntityDestroyed %s refunded %d", class, bank_refund);
       	  }
 	         
    }
	
}