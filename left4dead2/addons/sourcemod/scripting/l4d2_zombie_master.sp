// Made for the Knockout.chat community
// Plugin authors: gvazdas, zyiks
// HUGE THANKS TO TESTERS: Hatsune Miku Fan, Raykeno, IronBar, ngh, Lil Ole Fella, ShaunOfTheLive, zyiks
// Chance, Skerion, Lett1, AGGA Lambo, Robotnik, AriesToffle, Shadowcat, Wicket, GARFIELD'S SKELETON, Perchance, 
// Snake22, Mark9013100
// HUGE THANKS for scripting help: HarryPotter, xerox8521, Forgetest, little_froy, Lux, Marttt, Bacardi, Silvers
// HUGE THANKS TO Reagy and IronBar for hosting the Knockout Left 4 Dead 2 Server
// Custom Ellis and Louis sounds: zyiks and Skerion

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
#include <l4d2_zombie_master>
#include <l4d2_grid_lib>

bool DEBUG = false;

#define PLUGIN_NAME			    "l4d2_zombie_master"
#define PLUGIN_VERSION 			"0.9.02 2026-03-17"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

#include <zm_globals>
#include <zm_sdk>
#include <zm_spawner>
#include <zm_spawn_commands>
#undef REQUIRE_PLUGIN
#include <adminmenu>

public Plugin myinfo =
{
	name = "[L4D2] Zombie Master",
	author = "gvazdas,zyiks",
	description = "[coop,survival] AI Game Director is replaced by an infected player, the Zombie Master.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352060, https://github.com/gvazdas/l4d2_zombie_master"
}

// Changelog for 0.9.1
// 1. Bug fixed where uncommons can sometimes instantly die on spawn.
// 2. Rare bug hopefully fixed where commons try to attack empty space in Finales and Survival.
// 4. Random SI model bug fixed for tanks.
// 5. If you take over a tank that is climbing level geometry, you can get stuck. Fixed.
// 6. Compatibility with jukebox by Silvers.
// 7. Improved compatibility with plugins that modify survivor_set.
// 8. Custom maps tested: Daybreak, I Hate Mountains 2, Urban Flight, Warcelona
// 9. Improved distance to survivors calculations. Should give less false positives.
// 10. Make vomit target that specific survivor rather than whole team.
// 11. Compatibility with l4d2_shoot_alert_common. Plugin gets disabled during prep stage and re-activated on round start.
// 12. Optimizations thanks to Silvers.
// 13. New cvar: zm_say_horde which makes survivors team chatting spawn horde.
// 14. sm plugins reload called on plugins instead of resetting cvars which makes plugins reset to .cfg values.
// 15. zm_tankrun, zm_onlycommons, zm_jockeys
// 16. zm_randomizer
// 17. ZM menus updated to better represent game rules, like no specials, no witches, no commons, no uncommons, etc.
// 18. New cvar: zm_panic_rate_multiplier
// 19. New cvar: zm_ability_nocooldown
// 20. zm_max_si behavior update: acceptable values -3, -2, -1, 0, etc.
// 21. Many bug fixes.
// 22. new cvar: zm_notanks
// 23. Check IsBlocked
// 24. New admin menu.

// TO DO LIST:
// 4. Better easier to read zombie spawner visuals (done by zyiks, not implemented)
// 5. Gas station tornado (done by zyiks, not implemented)
// 15. Performance bottlenecks.
// 16. Is there a way to prevent observers from being able to see the ZM info? Try SendProxy?
// 26. No fog for ZM
// 30. Bring back inputkill prevention. Might not need it though.
// 39. Rare spitter cooldown bug. Idk how to fix this.
// 40. Context interact when looking at something with R
// 41. Special context interact: delete, move, attack nearest
// 42. Panic Trap
// 45. Admin menu
// 47. Witches in survivor closets
// 50. Random pz can spawn in saferoom :) nice valve
// 51. Find out why commons get auto culled on finale start. Can avoid culling if they are attacking other infected...
// 52. Smoker, Charger stupid behavior after ability fail.
// 57. Frozen tanks should be in stasis to prevent music // EFL_DORMANT Entity_Flags
// 58. Autokill obstructed stuck units
// 59. Some maps have busted Intro states. Try checking if survivor cameras are busy instead.
// 60. Survivors still keep teleporting and falling to their death.
// 62. Fun command: z_mute_infected no yelling or growling, allowing to stealth attack survivors.
// 63. Bad navmeshes where commons refuse to navigate? // m_isBlocked?
// 64. Crouched frozen specials should stay crouched.
// 65. Enumerate within optimizations


public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	switch(key[0])
	{
    	case 'C':
    	{
        	if (strcmp(key, "CommonLimit", false) == 0)
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
      		if (strcmp(key, "SpecialInfectedAssault", false) == 0)
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
        	
        	if (strcmp(key, "cm_AggressiveSpecials", false) == 0)
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
      		if (strcmp(key, "WitchLimit", false) == 0)
          	{
                 retVal = -1;
                 return Plugin_Handled;
          	}
    	}
    	case 'E':
    	{
        	if (strcmp(key, "EnforceFinaleNavSpawnRules", false) == 0)
        	{
               retVal = 0;
               return Plugin_Handled;
        	}
    	}
    	
	}
	return Plugin_Continue;
}

StringMap g_Steam;
bool fair_exhausted = false; // let anyone become ZM if true
int client_offer = -1;
float t_offer = 0.0;
int roundcount_offer = -1;
bool clients_offered[MAXPLAYERS+1] = {false,...}; // manual array in case steam auth fails

void create_client_data(int client=-1, char auth[65] = "", int count=0)
{
    if (DEBUG) LogMessage("[zm] create_client_data");
    if ( client>0 && (IsFakeClient(client) || !get_client_auth(client,auth)) ) return;
    if (g_Steam.ContainsKey(auth)) return;
    zm_data cell;
    cell.rounds = count;
    cell.last_roundcount = -1;
    cell.offered = false;
    g_Steam.SetArray(auth,cell,3,true);
    if (DEBUG) LogMessage("New data entry %s %d", auth, count);
}

bool get_zm_data(zm_data cell, int client=-1, char auth[65] = "")
{
    if (DEBUG) LogMessage("[zm] get_zm_data");
    if (client>0 && !get_client_auth(client,auth)) return false;
    if (!g_Steam.ContainsKey(auth) && IsValidClient(client) && !IsFakeClient(client))
        create_client_data(client,auth);
    if (!g_Steam.GetArray(auth,cell,3)) return false;
    return true;
}

int get_rounds(int client=-1, char auth[65] = "")
{
    zm_data cell;
    if (!get_zm_data(cell,client,auth)) return 0;
    return cell.rounds;
}

void increase_playcount(int client=-1, char auth[65] = "")
{
    zm_data cell;
    if (!get_zm_data(cell,client,auth)) return;
    cell.rounds += 1;
    cell.last_roundcount = roundcount;
    cell.offered = true;
    g_Steam.SetArray(auth,cell,3,true);
    if (DEBUG) LogMessage("[zm] Playcount increased %s %d (%d)", auth, cell.rounds, cell.last_roundcount);
    playcount_increased = true;
}

void reset_fair_queue()
{
    fq_timer = INVALID_HANDLE;
    if (!g_bFairQueue)
    {
        fair_exhausted = true;
        return;
    }
    
    if (DEBUG) LogMessage("[zm] reset_fair_queue");
    
    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        clients_offered[i] = false;
    }
    
    fair_exhausted = false;
    t_offer = 0.0;
    client_offer = -1;
    roundcount_offer = -1;
    StringMapSnapshot snapshot = g_Steam.Snapshot();
    static char auth[128];
    int maxKeys = snapshot.Length;
    zm_data cell;
    for (int i = 0; i < maxKeys; i++)
    {
        snapshot.GetKey(i,auth,sizeof(auth));
        if (!g_Steam.GetArray(auth,cell,3)) continue;
        if (cell.offered)
        {
            cell.offered = false;
            g_Steam.SetArray(auth,cell,3,true);
        }
    }
    delete snapshot;
}

Action fair_queue_update(Handle timer = null)
{
    
    fq_timer = INVALID_HANDLE;
    
    if (!g_bFairQueue || IsValidClientZM() || zm_stage>=ZM_STARTED || !clients_in_server || !first_active)
    {
        client_offer = -1;
        return Plugin_Stop;
    }
    
    if (DEBUG) LogMessage("[zm] fair_queue_update");
    
    float t_now = GetEngineTime();

    if (IsValidClient(client_offer) && !IsFakeClient(client_offer))
    {
        if (L4D_IsInIntro()>0) t_offer = t_now;
        float t_left = g_fFairQueueWait - (t_now - t_offer);
        if (t_left<=0.0)
        {
            pass_ZM(client_offer);
            return Plugin_Stop;
        }
        else
        {
            create_offer_menu(client_offer);
    	    fq_timer = CreateTimer(1.0,fair_queue_update);
        }
    }
    else client_offer = -1;
    
    if (IsValidClient(client_offer)) return Plugin_Stop;
    if (L4D_IsInIntro()>0) return Plugin_Stop;
    
    // See if anybody can be offered
    int ingame,total;
    int floor = roundcount;
    ArrayList candidates = new ArrayList();
    zm_data cell;
    for (int i = 1; i <= MaxClients; i++)
    {
  		if (!IsClientConnected(i)) continue;
  		if (IsFakeClient(i)) continue;
  		if (IsClientTimingOut(i)) continue;
  		total += 1;
  		if (IsClientInGame(i)) ingame += 1;
  		else
  		{
      		float dt = t_now - clients_t_join[i];
      		// Respecting connecting clients
      		// But ignore clients who just started connecting, and those stuck connecting.
      		if (dt<=5.0 || dt>=30.0) continue;
  		}
  		
  		// Steam auth frequently fails because Valve abandoned this game, so, have to resort to this.
  		if (get_zm_data(cell,i))
  		{
  		  	if (!cell.offered)
        	{
            	candidates.Push(i);
            	if (cell.last_roundcount<floor) floor = cell.last_roundcount;
        	}
  		}
  		else if (!clients_offered[i]) candidates.Push(i);
    }
    
    if (total<=0 || ingame<=0 || candidates.Length<=0)
    {
        if (!fair_exhausted && total>0 && ingame>0 && candidates.Length<=0 && (1.0*ingame/total)>0.5)
        {
            LogMessage("[zm] Fair queue exhausted! JoinZM restrictions OFF.");
            fair_exhausted = true;
        }
        delete candidates;
        return Plugin_Stop;
    }
    
    roundcount_offer = floor;
    
    // Pick random
    if (candidates.Length==1) client_offer = candidates.Get(0);
    else
    {
        ArrayList pool = new ArrayList();
        int client;
        for (int i = 0; i < candidates.Length; i++)
        {
      		client = candidates.Get(i);
      		if (get_zm_data(cell,client))
      		{
          		if (cell.last_roundcount<=floor) pool.Push(client);
      		}
      		else if (roundcount<=floor) pool.Push(client);
        }
        
        if (pool.Length==1) client_offer = pool.Get(0);
        else
        {
            int random_index = GetRandomInt(0,pool.Length-1);
            client_offer = pool.Get(random_index);
        }
        
        delete pool;
    }
    
    delete candidates;
    if (!IsClientInGame(client_offer) || !clients_active[client_offer] || GetEntProp(client_offer,Prop_Send,"m_fFlags")&FL_FROZEN)
    {
        client_offer = -1;
        fq_timer = CreateTimer(1.0,fair_queue_update);
    }
    else if (IsValidClient(client_offer))
    {
        t_offer = t_now;
        EmitSoundToClient(client_offer,SOUND_OFFER);
        update_EMS_HUD(true,0.0);
        fq_timer = CreateTimer(0.1,fair_queue_update);
    }
    
    return Plugin_Stop;  
    
}

void pass_ZM(int client=-1, char auth[65] = "")
{
    if (DEBUG) LogMessage("[zm] pass_ZM");
    zm_data cell;
    if (IsValidClient(client))
    {
        if (get_zm_data(cell,client,auth))
        {
            cell.offered = true;
            g_Steam.SetArray(auth,cell,3,true);
        }
        clients_offered[client] = true;
        if (client==client_offer) client_offer = -1;
    }
    fair_queue_update(null);
}

// ZM OFFER MENU
Menu menu_offer;
void create_offer_menu(int client)
{		
	if (!IsValidClient(client)) return;
	if (DEBUG) LogMessage("[zm] create_offer_menu");
	if (menu_offer!=INVALID_HANDLE) CloseHandle(menu_offer);
	menu_offer = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),offer_menu_Handler);
	static char buffer[64]; 
    Format(buffer, sizeof(buffer), "%T", "Offer ZM", client);
	menu_offer.SetTitle(buffer); 
    
    Format(buffer,sizeof(buffer),"%T", "Yes", client);
    AddMenuItem(menu_offer, "0", buffer);
    Format(buffer,sizeof(buffer),"%T", "No", client);
    AddMenuItem(menu_offer, "1", buffer);
    
	menu_offer.ExitButton = false;
	SetMenuOptionFlags(menu_offer,MENUFLAG_NO_SOUND);
	menu_offer.Display(client,RoundFloat(g_fFairQueueWait));
}
int offer_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (IsValidClientZM()) return 0;
        	switch(param2)
        	{
            	case 0: JoinZM_command(param1,0);
            	case 1: {pass_ZM(param1); close_menus(param1);}
        	}
        	return 0;
        }
        case MenuAction_Cancel:
        {
           if (menu_offer && param1==client_offer && IsValidClient(client_offer) && param2==MenuCancel_Exit)
               menu_offer.Display(client_offer,RoundFloat(g_fFairQueueWait));
        }
    }
	return 0;
}


public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_bCvarAllow) return;
	switch (classname[0])
	{
    	case 'i':
    	{
        	if (live_zombie_arr[ZOMBIECLASS_COMMON]>0) return;
        	if (StrEqual(classname,"infected",false)) CountCommons(null,false);
    	}
	}
}

bool is_zm_spamming()
{
    float t_now = GetEngineTime();
    if ( (t_now-t_last_action)<=0.11 ) // typical tickrate is 30
    {
        update_hint("%T", "STOP SPAMMING", zm_client);
        t_last_action = t_now;
        return true;
    }
    t_last_action = t_now;
    return false;
}

void OnDirectorOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    if (DEBUG) LogMessage("[zm] info_director output %s fired! %d %d %f", output, activator, caller, delay);
    
    if (!ZM_finale_announced)
    {
       	if (strcmp(output,"OnCustomPanicStageFinished")==0)
       	{
           	manual_panic = false;
           	update_panic();
       	}
    }
}

ConVar g_hSayHorde;

float commons_add = 0.0; // in case rate is very slow


int g_iGlowList[MAXENTITIES+1] = {INVALID_ENT_REFERENCE, ...}; // track glow children of parent entities

// Prep time for coop only
ConVar g_hPrepTimeZM;
float g_fPrepTimeZM;
float t_zm_join = 0.0;

float saferoom_cooldown = 5.0;
bool saferoom_locked = false;
float t_last_join = 0.0;

// Kick AFK ZM due to inactivity
float t_zm_activity = 0.0;
bool zm_kick_notify = false;
void update_t_zm_activity(float new_t = -1.0)
{
    zm_kick_notify = false;
    if (new_t<0.0) t_zm_activity = GetEngineTime();
    else t_zm_activity = new_t;
}

Action Timer_load_zm_global_settings(Handle timer)
{
    char command[PLATFORM_MAX_PATH];
    Format(command, sizeof(command), "exec sourcemod/%s", CONFIG_FILENAME);
    ServerCommand(command);
    create_menu_gamemode();
    return Plugin_Stop;
}

ArrayList gamemodes;
static char new_gamemode[64] = "";
void load_gamemodes()
{    
    gamemodes = new ArrayList(64);
    gamemodes.PushString("zm_default");
    
    static char path[PLATFORM_MAX_PATH] = "cfg/sourcemod/l4d2_zombie_master/";
    if (!DirExists(path)) return;
    DirectoryListing dir = OpenDirectory(path);
    if (dir==null) return;
    static char filename[64];
    while (dir.GetNext(filename, sizeof(filename)))
    {
        TrimString(filename);
        if (strcmp(filename,"zm_default.cfg")==0) continue;
        if (StrContains(filename,".cfg",false)==-1) continue;
        ReplaceString(filename,sizeof(filename),".cfg","",false);
        TrimString(filename);
        gamemodes.PushString(filename);
    }
    delete dir;
    LogMessage("[zm] Loaded %d gamemodes.", gamemodes.Length);
}

// GAMEMODE MENU
Menu menu_gamemode;
void create_menu_gamemode()
{		
	if (DEBUG) LogMessage("[zm] create_menu_gamemode");
	if (menu_gamemode!=INVALID_HANDLE) CloseHandle(menu_gamemode);
	menu_gamemode = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),gamemode_menu_Handler);
	static char buffer1[8];
	static char buffer2[64];
	Format(buffer2,sizeof(buffer2),"zm_gamemode %s",g_sZMGamemode);
	menu_gamemode.SetTitle(buffer2);
	for(int i = 0; i<gamemodes.Length; i++)
	{
    	IntToString(i,buffer1,sizeof(buffer1));
    	gamemodes.GetString(i,buffer2,sizeof(buffer2));
    	TrimString(buffer1); TrimString(buffer2);
    	menu_gamemode.AddItem(buffer1,buffer2);
	}
	menu_gamemode.ExitButton = true;
}
int gamemode_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param2<0 || param2>=gamemodes.Length) return 0;
        	gamemodes.GetString(param2,new_gamemode,sizeof(new_gamemode));
        	if (CheckCommandAccess(param1,"is_a_sm_admin",ADMFLAG_GENERIC,true))
        	{
            	SetConVarString(g_hZMGamemode,new_gamemode);
            	ZM_Gamemode_Command(param1,0);
        	}
        	else create_gamemode_vote();
        }
    }
	return 0;
}

int Handle_VoteGamemode(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_VoteEnd)
    {
        if (param1 == 0) SetConVarString(g_hZMGamemode,new_gamemode);
    }
    return 0;
}
void create_gamemode_vote()
{
    if (IsVoteInProgress()) return;
    Menu menu = new Menu(Handle_VoteGamemode);
    static char buffer[128];
    Format(buffer,sizeof(buffer), "zm_gamemode -> %s?", new_gamemode);
    menu.SetTitle(buffer);
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}

void random_gamemode()
{
    if (gamemodes.Length<=0) return;
    if (gamemodes.Length==1) gamemodes.GetString(0,new_gamemode,sizeof(new_gamemode));
    else
    {
        gamemodes.GetString(GetRandomInt(0,gamemodes.Length-1),new_gamemode,sizeof(new_gamemode));
        if (strcmp(new_gamemode,g_sZMGamemode)==0) gamemodes.GetString(GetRandomInt(0,gamemodes.Length-1),new_gamemode,sizeof(new_gamemode));
    }
    SetConVarString(g_hZMGamemode,new_gamemode);
    LogMessage("[zm] Randomizer gamemode: %s", new_gamemode);
}

Action ZM_Gamemode_Command(int client, int args)
{
    if (!IsValidClient(client) || menu_gamemode==null) return Plugin_Continue;
    menu_gamemode.Display(client,MENU_TIME_FOREVER);
    return Plugin_Continue;
}

public void OnPluginStart()
{
	if (DEBUG) LogMessage("[zm] OnPluginStart");
	load_gamemodes();
	zm_stage = ZM_END;
	CreateTimer(1.0,Timer_load_zm_global_settings);
	//AutoExecConfig(true, CONFIG_FILENAME);
	g_Steam = new StringMap();
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
    
    g_hPanicCost = CreateConVar("zm_panic_cost", "200", "Horde panic cost.",FCVAR_PROTECTED , true, 0.0, true, 1000000.0);
    g_hPanicCost.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hPanicDuration = CreateConVar("zm_panic_duration", "30", "Horde panic duration, in seconds.",FCVAR_PROTECTED , true, 10.0, true, 1000.0);
    g_hPanicDuration.AddChangeHook(ConVarChanged_Cvars);
    
    g_hUpdateRate = CreateConVar("zm_updaterate", "0.25", "Update rate for periodic ZM checks, in seconds.",FCVAR_PROTECTED , true, 0.1, true, 10.0);
    g_hUpdateRate.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxCommons = CreateConVar("zm_maxcommons", "75", "ZM max number of common zombies. Be careful.",FCVAR_PROTECTED , true, 0.0, true, 1000.0);
    g_hMaxCommons.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hSpawnMinDistance = CreateConVar("zm_spawndistance", "400", "ZM minimum spawn distance.",FCVAR_PROTECTED, true, 0.0, true, 10000.0);
    g_hSpawnMinDistance.AddChangeHook(ConVarChanged_Cvars);

    g_hGridSearchRadius = CreateConVar("zm_grid_search_radius", "500", "Search radius (units) for GridLib fallback spawn when indicator is blue.",FCVAR_PROTECTED, true, 0.0, true, 5000.0);
    g_hGridSearchRadius.AddChangeHook(ConVarChanged_Cvars);
    
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
	
	g_hHoldFinale = CreateConVar("zm_hold_finale", "1", "Hold Finale stages until ZM runs out of resources. Otherise the Finale will be very short.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
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
	
	g_hAbilityNoCooldown = CreateConVar("zm_ability_nocooldown", "0", "No cooldown for Special abilities.",FCVAR_PROTECTED, true, 0.0, true, 1.0);
	
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

TopMenu hAdminMenu = null;
public void OnLibraryRemoved(const char[] name)
{
  if (StrEqual(name,"adminmenu",false)) hAdminMenu = null;
}

TopMenuObject obj_zmcommands, zm_enable, zm_gamemode_menu, zm_kick_topmenu, zm_randomizer, zm_sayhorde, zm_help, zm_random;
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

public void CategoryHandler( TopMenu topmenu,TopMenuAction action,TopMenuObject object_id,int param,char[] buffer,int maxlength)
{
  switch (action)
  {
    case TopMenuAction_DisplayTitle: Format(buffer,maxlength, "%T:", "Zombie Master", param);
    case TopMenuAction_DisplayOption: Format(buffer,maxlength, "%T", "Zombie Master", param);
  }
}
//
public void AdminMenu_Handler(TopMenu topmenu,TopMenuAction action,TopMenuObject object_id,int param,char[] buffer,int maxlength)
{
  switch (action)
  {
    case TopMenuAction_DisplayOption:
    {
        if (object_id==zm_enable) Format(buffer,maxlength,"zm_enable %d",g_hCvarAllow.BoolValue);
        else if (object_id==zm_randomizer)
        {
            if (g_hRandomizer.IntValue==0) Format(buffer,maxlength,"zm_randomizer: OFF");
            else if (g_hRandomizer.IntValue==1) Format(buffer,maxlength,"zm_randomizer: Map");
            else if (g_hRandomizer.IntValue==2) Format(buffer,maxlength,"zm_randomizer: Round");
            else Format(buffer,maxlength,"zm_randomizer");
        }
        else if (object_id==zm_gamemode_menu) strcopy(buffer,maxlength,"zm_gamemode_menu"); 
        else if (object_id==zm_kick_topmenu) strcopy(buffer,maxlength,"zm_kick");
        else if (object_id==zm_sayhorde) Format(buffer,maxlength,"zm_say_horde %d",g_hSayHorde.BoolValue);
        else if (object_id==zm_help) Format(buffer,maxlength,"zm_help");
        else if (object_id==zm_random) strcopy(buffer,maxlength,"zm_gamemode random"); 
    }
    case TopMenuAction_SelectOption:
    {
        bool redisplay = true;
        if (object_id==zm_enable) SetConVarInt(g_hCvarAllow,!g_hCvarAllow.BoolValue);
        else if (object_id==zm_randomizer) next_randomizer_setting();
        else if (object_id==zm_gamemode_menu) {ZM_Gamemode_Command(param,0); redisplay = false;}
        else if (object_id==zm_kick_topmenu) zm_kick(param,0);
        else if (object_id==zm_sayhorde) SetConVarInt(g_hSayHorde,!g_hSayHorde.BoolValue);
        else if (object_id==zm_help) ZM_MOTD(param,0);
        else if (object_id==zm_random) random_gamemode();
        if (redisplay) RedisplayAdminMenu(topmenu,param);
    }
  }
}

void next_randomizer_setting()
{
    int next = g_hRandomizer.IntValue + 1;
    if (next>2) next = 0;
    SetConVarInt(g_hRandomizer,next);
}

int zm_menu_state = ZM_MENU_CLOSED;
Menu menu_main,menu_common,menu_uncommon,menu_special,menu_boss,menu_cleanup,menu_other,menu_autocommon = null;

void close_menus(int client)
{
    if (!IsValidClient(client)) return;
    InternalShowMenu(client, "\10", 1); // thanks to Zira
    CancelClientMenu(client, true, null);
    if (client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
}

void open_menu(int client, int MENU=ZM_MENU_MAIN, int time=MENU_TIME_FOREVER)
{
    
    if (client!=zm_client)
    {
        close_menus(client);
        return;
    }
    
    if (!IsValidClientZM()) return;
    
    if (menu_main==null) update_menus();
    
    if (MENU<ZM_MENU_CLOSED || MENU>ZM_MENU_CONTEXT) MENU = ZM_MENU_MAIN;
    if (MENU==ZM_MENU_CLOSED) time = 1;
    
    switch(MENU)
    {
        case ZM_MENU_MAIN: menu_main.Display(zm_client,time);
        case ZM_MENU_COMMON: menu_common.Display(zm_client,time);
        case ZM_MENU_UNCOMMON: menu_uncommon.Display(zm_client,time);
        case ZM_MENU_SPECIAL: menu_special.Display(zm_client,time);
        case ZM_MENU_BOSS: menu_boss.Display(zm_client,time);
        case ZM_MENU_CLEANUP: menu_cleanup.Display(zm_client,time);
        case ZM_MENU_OTHER: menu_other.Display(zm_client,time);
        case ZM_MENU_AUTOCOMMON: menu_autocommon.Display(zm_client,time);
        case ZM_MENU_CLOSED: close_menus(zm_client);
        default: menu_main.Display(zm_client,time);
    }
    
    zm_menu_state = MENU;
    
}

void reopen_zm_menu(bool force = true)
{
    if (zm_menu_state == ZM_MENU_CLOSED || !IsValidClientZM()) return;
    if (force || GetClientMenu(zm_client)==MenuSource_None) open_menu(zm_client,zm_menu_state);
}

// MAIN MENU
void create_main_menu()
{		
	if (DEBUG) LogMessage("[zm] create_main_menu");
	if (menu_main!=INVALID_HANDLE) CloseHandle(menu_main);
	menu_main = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),main_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	static char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Zombie Master", zm_language);
	menu_main.SetTitle(buffer);
    
    if (max_zombie_arr[ZOMBIECLASS_COMMON]>0 && (g_iCostUncommon>=0 || g_iCostCommon>=0))
        Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    else buffer = "-";
    AddMenuItem(menu_main, "0", buffer);
    
    if (max_SI>0) Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
    else buffer = "-";
    AddMenuItem(menu_main, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
    AddMenuItem(menu_main, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
    AddMenuItem(menu_main, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
    AddMenuItem(menu_main, "4", buffer);
    
    if (g_bAllowFreeze && max_SI>0)
    {
        if (ZM_specials_frozen) Format(buffer, sizeof(buffer), "%T", "Unfreeze Specials", zm_language);
        else Format(buffer, sizeof(buffer), "%T", "Freeze Specials", zm_language);
    }
    else buffer = "-";
    AddMenuItem(menu_main, "5", buffer);

	menu_main.ExitButton = true;
	SetMenuOptionFlags(menu_main,MENUFLAG_NO_SOUND);
}
int main_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0:
            	{
                	if (max_zombie_arr[ZOMBIECLASS_COMMON]>0) zm_menu_state=ZM_MENU_COMMON;
            	}
            	case 1:
            	{
                	if (max_SI>0) zm_menu_state=ZM_MENU_SPECIAL;
            	}
            	case 2: zm_menu_state=ZM_MENU_BOSS;
            	case 3: zm_menu_state=ZM_MENU_CLEANUP;
            	case 4: zm_menu_state=ZM_MENU_OTHER;
            	case 5: set_specials_frozen(~ZM_specials_frozen);
            	
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }
	return 0;
}

// COMMON MENU
void create_common_menu()
{		
	if (DEBUG) LogMessage("[zm] create_common_menu");
	if (menu_common!=INVALID_HANDLE) CloseHandle(menu_common);
	menu_common = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),common_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	static char buffer[64]; 
    	
    Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
	menu_common.SetTitle(buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x200 %d", "Common", zm_language, g_iCostCommon*200);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x200 %d", "Uncommon", zm_language, g_iCostUncommon*200);
    else buffer = "-";
    AddMenuItem(menu_common, "0", buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x10 %d", "Common", zm_language, g_iCostCommon*10);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x10 %d", "Uncommon", zm_language, g_iCostUncommon*10);
    else buffer = "-";
    AddMenuItem(menu_common, "1", buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x20 %d", "Common", zm_language, g_iCostCommon*20);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x20 %d", "Uncommon", zm_language, g_iCostUncommon*20);
    else buffer = "-"; 
    AddMenuItem(menu_common, "2", buffer);
    
    if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T", "Uncommon", zm_language);
    else buffer = "-";
    AddMenuItem(menu_common, "3", buffer);
    
    if (L4D_IsSurvivalMode() || ZM_finale_announced) AddMenuItem(menu_common, "4", "-");
    else
    {
        Format(buffer,sizeof(buffer),"%T %d", "PANIC", zm_language, g_iPanicCost);
        AddMenuItem(menu_common, "4", buffer);
    }
    
    Format(buffer,sizeof(buffer),"%T", "AutoCommon", zm_language);
    AddMenuItem(menu_common, "5", buffer);
    
    AddMenuItem(menu_common, "6", "<-- (R)");

	menu_common.ExitButton = true;
	SetMenuOptionFlags(menu_common,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_COMMON && IsValidClientZM()) open_menu(zm_client,ZM_MENU_COMMON);
}
int common_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Horde(zm_client,200);
            	case 1: ZM_Horde(zm_client,10);
            	case 2: ZM_Horde(zm_client,20);
            	case 3: zm_menu_state=ZM_MENU_UNCOMMON;
            	case 4:
            	{
                	if (!L4D_IsSurvivalMode() && !ZM_finale_announced) ZMPanic(zm_client,0);
            	}
            	case 5: zm_menu_state=ZM_MENU_AUTOCOMMON;
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// UNCOMMON MENU
void create_uncommon_menu()
{		
	if (DEBUG) LogMessage("[zm] create_uncommon_menu");
	if (menu_uncommon!=INVALID_HANDLE) CloseHandle(menu_uncommon);
	menu_uncommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),uncommon_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	static char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
	menu_uncommon.SetTitle(buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"riot")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Riot", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "0", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"ceda")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "CEDA", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "1", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"clown")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Clown", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "2", buffer);
   
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"mud")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Mud", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"road")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Road", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "4", buffer);
    
    if (!panic && !L4D_IsSurvivalMode() && !ZM_finale_announced && g_iCostUncommon>=0)
    {
        if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, g_iCostUncommon);
        else Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, 2*g_iCostUncommon);
    }
    else buffer = "-";
    AddMenuItem(menu_uncommon, "5", buffer);
    
    AddMenuItem(menu_uncommon, "6", "<-- (R)");

	menu_uncommon.ExitButton = true;
	SetMenuOptionFlags(menu_uncommon,MENUFLAG_NO_SOUND);
}
int uncommon_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Horde(zm_client,1,"riot");
            	case 1: ZM_Horde(zm_client,1,"ceda");
            	case 2: ZM_Horde(zm_client,1,"clown");
            	case 3: ZM_Horde(zm_client,1,"mud");
            	case 4: ZM_Horde(zm_client,1,"road");
            	case 5: ZM_Horde(zm_client,1,"",true);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// SPECIAL MENU
void create_special_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_special");
	if (menu_special!=INVALID_HANDLE) CloseHandle(menu_special);
	menu_special = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),special_menu_Handler);
    
    int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	static char buffer[64]; 
    int occupied, max;
    
    Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
	menu_special.SetTitle(buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_BOOMER];
    if (max>0 && costs_SI[ZOMBIECLASS_BOOMER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_BOOMER], live_zombie_arr[ZOMBIECLASS_BOOMER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Boomer", zm_language, costs_SI[ZOMBIECLASS_BOOMER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "0", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SPITTER];
    if (l4d2_specials && max>0 && costs_SI[ZOMBIECLASS_SPITTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SPITTER], live_zombie_arr[ZOMBIECLASS_SPITTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Spitter", zm_language, costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "1", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SMOKER];
    if (max>0 && costs_SI[ZOMBIECLASS_SMOKER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SMOKER], live_zombie_arr[ZOMBIECLASS_SMOKER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Smoker", zm_language, costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "2", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_HUNTER];
    if (max>0 && costs_SI[ZOMBIECLASS_HUNTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_HUNTER], live_zombie_arr[ZOMBIECLASS_HUNTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Hunter", zm_language, costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "3", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_JOCKEY];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_JOCKEY]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_JOCKEY], live_zombie_arr[ZOMBIECLASS_JOCKEY]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Jockey", zm_language, costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "4", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_CHARGER];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_CHARGER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_CHARGER], live_zombie_arr[ZOMBIECLASS_CHARGER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Charger", zm_language, costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "5", buffer);
    
    AddMenuItem(menu_special, "6", "<-- (R)");

	menu_special.ExitButton = true;
	SetMenuOptionFlags(menu_special,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_SPECIAL && IsValidClientZM()) open_menu(zm_client,ZM_MENU_SPECIAL);
}
int special_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Boomer(zm_client,0);
            	case 1: ZM_Spitter(zm_client,0);
            	case 2: ZM_Smoker(zm_client,0);
            	case 3: ZM_Hunter(zm_client,0);
            	case 4: ZM_Jockey(zm_client,0);
            	case 5: ZM_Charger(zm_client,0);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// BOSS MENU
void create_boss_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_boss");
	if (menu_boss!=INVALID_HANDLE) CloseHandle(menu_boss);
	menu_boss = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),boss_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	static char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
	menu_boss.SetTitle(buffer);
    
    if (g_iCostWitchMoving>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Moving", zm_language, g_iCostWitchMoving);
    else buffer = "-";
    AddMenuItem(menu_boss, "0", buffer);
    if (g_iCostWitchStatic>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Static", zm_language, g_iCostWitchStatic);
    else buffer = "-";
    AddMenuItem(menu_boss, "1", buffer);
    
    int max = max_zombie_arr[ZOMBIECLASS_TANK];
    if (max>0 && costs_SI[ZOMBIECLASS_TANK]>=0)
    {
        int occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_TANK], live_zombie_arr[ZOMBIECLASS_TANK]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Tank", zm_language, costs_SI[ZOMBIECLASS_TANK], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_boss, "2", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"jimmy")!=0) buffer = "-";
    else if (jimmy_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Jimmy Gibbs Jr", zm_language,g_iCostUncommon);
    AddMenuItem(menu_boss, "3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"fallen")!=0) buffer = "-";
    else if (fallen_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Fallen Survivor", zm_language,g_iCostUncommon);
    AddMenuItem(menu_boss, "4", buffer);
    
    AddMenuItem(menu_boss, "5", "-");
    AddMenuItem(menu_boss, "6", "<-- (R)");

	menu_boss.ExitButton = true;
	SetMenuOptionFlags(menu_boss,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_BOSS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_BOSS);
}
int boss_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Witch(zm_client,WITCH_MOVING);
            	case 1: ZM_Witch(zm_client,WITCH_STATIC);
            	case 2: ZM_Tank(zm_client,0);
            	case 3: { if (!jimmy_spawned) ZM_Horde(zm_client,1,"jimmy");}
            	case 4: { if (!fallen_spawned) ZM_Horde(zm_client,1,"fallen");}
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// CLEANUP MENU
void create_cleanup_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_cleanup");
	if (menu_cleanup!=INVALID_HANDLE) CloseHandle(menu_cleanup);
	menu_cleanup = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),cleanup_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    static char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
	menu_cleanup.SetTitle(buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Target", zm_language);
    AddMenuItem(menu_cleanup, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Commons", zm_language);
    AddMenuItem(menu_cleanup, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Specials", zm_language);
    AddMenuItem(menu_cleanup, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Witches", zm_language);
    AddMenuItem(menu_cleanup, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete ALL", zm_language);
    AddMenuItem(menu_cleanup, "4", buffer);
    
    AddMenuItem(menu_cleanup, "5", "-");
    
    AddMenuItem(menu_cleanup, "6", "<-- (R)");

	menu_cleanup.ExitButton = true;
	SetMenuOptionFlags(menu_cleanup,MENUFLAG_NO_SOUND);
}
int cleanup_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Delete(zm_client,0);
            	case 1: ZM_Delete_Commons(zm_client,0);
            	case 2: ZM_Delete_Specials(zm_client,0);
            	case 3: ZM_Delete_Witches(zm_client,0);
            	case 4: ZM_Delete_All(zm_client,0);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// OTHER MENU
void create_other_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_other");
	if (menu_other!=INVALID_HANDLE) CloseHandle(menu_other);
	menu_other = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),other_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    static char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
	menu_other.SetTitle(buffer);
    
    if (zm_stage>=ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Control (USE)", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Start Round", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else AddMenuItem(menu_other, "0", "-");
    
    AddMenuItem(menu_other, "1", "-");
    
    Format(buffer, sizeof(buffer), "%T", "Teleport", zm_language);
    AddMenuItem(menu_other, "2", buffer);
    
    AddMenuItem(menu_other, "3", "-");
    
    Format(buffer, sizeof(buffer), "%T", "Give Up", zm_language);
    AddMenuItem(menu_other, "4", buffer);
    
    AddMenuItem(menu_other, "5", "-");
    AddMenuItem(menu_other, "6", "<-- (R)");

	menu_other.ExitButton = true;
	SetMenuOptionFlags(menu_other,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_OTHER && IsValidClientZM()) open_menu(zm_client,ZM_MENU_OTHER);
	
}
int other_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: 
            	{
                	if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED) zm_start(zm_client,0);
                	else
                	{
                    	if (zm_stage==ZM_STARTED)
                    	{
                        	if (live_SI>0) ZMControlSI(zm_client,0);
                        	else zm_menu_state=ZM_MENU_SPECIAL;
                    	}
                	}
            	}
            	case 2: ZMTeleport(zm_client,0);
            	case 4: {QuitZM(zm_client); return 0;}
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);     	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }
	return 0;
}

void next_autocommon_setting()
{
    autocommon_setting += 1;
    if (autocommon_setting>AUTOCOMMON_ALWAYS) autocommon_setting = 0;
    create_autocommon_menu();
}

void next_autocommon_num()
{
    if (autocommon_num>10) autocommon_num -= 10;
    else autocommon_num = 30;
    create_autocommon_menu();
}

// AUTOCOMMON MENU
void create_autocommon_menu()
{		
	if (DEBUG) LogMessage("[zm] create_autocommon_menu");
	if (menu_autocommon!=INVALID_HANDLE) CloseHandle(menu_autocommon);
	menu_autocommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),autocommon_menu_Handler);
	
	static char buffer[64]; 
    int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    	
    Format(buffer, sizeof(buffer), "%T", "AutoCommon", zm_language);
	menu_autocommon.SetTitle(buffer);
    
    switch (autocommon_setting)
    {
        case AUTOCOMMON_ALWAYS: Format(buffer, sizeof(buffer), "%T", "AutoCommon ALWAYS", zm_language);
        case AUTOCOMMON_PANIC: Format(buffer, sizeof(buffer), "%T", "AutoCommon PANIC", zm_language);
        default: Format(buffer, sizeof(buffer), "%T", "AutoCommon OFF", zm_language);
    }
    AddMenuItem(menu_autocommon, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "AutoCommon Max", zm_language, autocommon_num);
    AddMenuItem(menu_autocommon, "1", buffer);
    
    if (autocommon_uncommons) Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
    else Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    AddMenuItem(menu_autocommon, "2", buffer);
    
    AddMenuItem(menu_autocommon, "3", "-");
    AddMenuItem(menu_autocommon, "4", "-");
    AddMenuItem(menu_autocommon, "5", "-");
    AddMenuItem(menu_autocommon, "6", "<-- (R)");

	menu_autocommon.ExitButton = true;
	SetMenuOptionFlags(menu_autocommon,MENUFLAG_NO_SOUND);
	if (zm_menu_state == ZM_MENU_AUTOCOMMON && IsValidClientZM()) open_menu(zm_client,ZM_MENU_AUTOCOMMON);
}
int autocommon_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: next_autocommon_setting();
            	case 1: next_autocommon_num();
            	case 2:
            	{
                	if (g_iCostUncommon<0) autocommon_uncommons=false;
                	else if (g_iCostCommon<0) autocommon_uncommons=true;
                	else autocommon_uncommons=~autocommon_uncommons;
                	create_autocommon_menu();
                	return 0;
            	}
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

void update_menus()
{
    if (DEBUG) LogMessage("[zm] update_menus");
    create_main_menu();
    create_other_menu();
    create_cleanup_menu();
    create_boss_menu();
    create_special_menu();
    create_uncommon_menu();
    create_common_menu();
    create_autocommon_menu();
}

// Pre-computed navmeshes storage

ArrayList g_hObscuredList;  // ArrayList of PreCalcNav structs
ArrayList g_hStartAreaList; // ArrayList of PreCalcNav structs
bool g_bNavReady = false;    // Is pre-computation complete?

int bank_track_numplayers = 0; //tracking if more bank should be added when more survivors appear

void set_bank_begin()
{
    if (g_iAliveSurvivors<=0) CountClients();
    if (L4D_IsSurvivalMode()) bank = g_iBonusSurvival*g_iAliveSurvivors;
    else
    {
        bank = g_iBankInitial;
        bank += g_iBankInitialPlayer*g_iAliveSurvivors;
    }
    bank_track_numplayers = g_iAliveSurvivors;
    bank_add = 0.0;
    commons_add = 0.0;
}

static char myFormattedString[128];
void update_hint(const char[] myString, any ...)
{
	if (!IsValidClientZM()) return;
	VFormat(myFormattedString,128,myString,2);
    FormatEx(ZM_hint,sizeof(ZM_hint),"%s",myFormattedString);
    update_EMS_HUD();
    active_looktarget = false;
}

bool saferoom_interacted = false;
int hits = 0;
MRESReturn DHook_Saferoom_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bCvarAllow || zm_stage>=ZM_STARTED) return MRES_Ignored;
	
	static char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (strcmp(inputName,"PlayerOpen")==0 || strcmp(inputName,"Use")==0)
	{
    	hits += 1;
    	RequestFrame(verify_saferoom_closed);
	}
	
	if (DEBUG) LogMessage("[zm] rotating door accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (hits>1 && !saferoom_interacted)
	{
    	saferoom_interacted = true;
    	if (!zm_can_start) can_zm_start();
    	if (zm_stage<ZM_STARTED && (!zm_can_start || force_started)) saferoom_lock(true);
	}
	
	return MRES_Ignored;
}

void check_saferoom()
{
   
   if (DEBUG) LogMessage("[zm] check_saferoom");
   if (L4D_IsSurvivalMode())
   {
       g_iLockedDoor = INVALID_ENT_REFERENCE;
       return;
   }

   if (g_iLockedDoor==INVALID_ENT_REFERENCE && L4D_HasMapStarted())
   {
        if (DEBUG) LogMessage("[zm] check_saferoom");
        g_iLockedDoor = L4D_GetCheckpointFirst();
        if (IsValidEntity(g_iLockedDoor))
        {
            g_iLockedDoor = EntIndexToEntRef(g_iLockedDoor);
            if (!saferoom_interacted && g_DHook_AcceptInput)
            {
                if (DEBUG) LogMessage("[zm] Hooking rotating door g_DHook_AcceptInput");
                hits = 0;
                DHookEntity(g_DHook_AcceptInput, true, g_iLockedDoor, INVALID_FUNCTION, DHook_Saferoom_AcceptInput);
            }
            else saferoom_interacted = true;
        }
        else
        {
            if (DEBUG) LogMessage("[zm] no saferoom, ignoring");
            g_iLockedDoor = INVALID_ENT_REFERENCE;
        }
   }
   
}

void verify_saferoom_closed()
{
    if ( !IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED || !saferoom_locked ) return;
    if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED)
    {
        AcceptEntityInput(g_iLockedDoor,"Close");
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
    }
}

void saferoom_lock(bool state)
{
    if (DEBUG) LogMessage("[zm] saferoom_lock");
    check_saferoom();
    
    if ( !IsValidEntRef(g_iLockedDoor) )
    {
        saferoom_locked = state;
        return;
    }
    
    if (state && zm_stage<ZM_STARTED && g_bLockSaferoom)
    {
        if (saferoom_interacted)
        {
            SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
            if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED) AcceptEntityInput(g_iLockedDoor,"Close");
            RequestFrame(verify_saferoom_closed);
        }
        saferoom_glow(true);
        saferoom_locked=true;
        if (DEBUG) LogMessage("[zm] Locked saferoom");
    }
    else
    {
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")&~DOOR_FLAG_IGNORE_USE);
        saferoom_glow(false);
        saferoom_locked=false;
        if (DEBUG) LogMessage("[zm] Unlocked saferoom");
        hits = 0;
    }
    
}

void saferoom_glow(bool state=true)
{
   if (DEBUG) LogMessage("[zm] saferoom_glow");
   check_saferoom();
   if (!IsValidEntRef(g_iLockedDoor) ) return;
   
   if (state && zm_stage<ZM_STARTED && g_bLockSaferoom)
   {
       SetEntProp(g_iLockedDoor, Prop_Send, "m_iGlowType", 3);
       SetEntProp(g_iLockedDoor, Prop_Send, "m_glowColorOverride", 254); //red
       SetEntProp(g_iLockedDoor, Prop_Send, "m_nGlowRangeMin", 0);
   	   SetEntProp(g_iLockedDoor, Prop_Send, "m_nGlowRange", 999999);
   }
   else
   {
       SetEntProp(g_iLockedDoor, Prop_Send, "m_glowColorOverride", 0);
       AcceptEntityInput(g_iLockedDoor, "StopGlowing");
   }
   
}

void can_zm_start()
{
   if (DEBUG) LogMessage("[zm] can_zm_start");
   if (!g_bLockSaferoom || zm_can_start) // Option 2: do not re-lock saferoom after first "round can start" announcement
   //if (!g_bLockSaferoom) // Option 1: allow saferoom to be relocked
   {
       zm_can_start = true;
       if (saferoom_locked && !force_started) saferoom_lock(false);
       return;
   }
   
   zm_can_start = false;
   if (!zm_allow_spawns) return;
   check_saferoom();
   
   if (zm_stage>=ZM_STARTED)
   {
      if (saferoom_locked) saferoom_lock(false);
      return;
   }
   
   float t_now = GetEngineTime();
   if ( IsValidClientZM() && (t_now-t_last_join)>=saferoom_cooldown )
   {
      if ((t_now - t_zm_join)>=g_fPrepTimeZM) zm_can_start = true;
   }
     
   if (zm_can_start)
   {
       if (saferoom_locked && !force_started)
       {
           saferoom_lock(false);
           if (zm_stage<ZM_STARTED) EmitSoundToAll(SOUND_READY);
           if (g_bMemes && !meme_delivered)
           {
               float delay = GetRandomFloat(1.0,10.0);
               CreateTimer(delay,random_meme,TIMER_FLAG_NO_MAPCHANGE);
           }
       }
       update_EMS_HUD(true,0.0); 
   }
   else if (g_bLockSaferoom && !saferoom_locked)
   {
      saferoom_lock(true);
      update_EMS_HUD();
   }
}

void freeze_player(int client, bool state = true, int team = TEAM_SURVIVOR)
{
    if(IsValidClient(client) && client!=zm_client && GetClientTeam(client)==team && IsPlayerAlive(client))
    {   
        
        int zClass = -1;
        if (team==TEAM_INFECTED) zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        
        if (state)
        {
            if (team == TEAM_SURVIVOR) SetEntProp(client, Prop_Data, "m_takedamage", 0);
            else if (IsFakeClient(client))
            {
                SetEntPropEnt(client, Prop_Send, "m_lookatPlayer",-1);
                SetEntProp(client, Prop_Send, "m_hasVisibleThreats",0);
                if (zClass==ZOMBIECLASS_TANK)
                {
                    //if (hTankEnterStasis) SDKCall(hTankEnterStasis,client);
                    SetEntProp(client, Prop_Send, "m_zombieState",0);
                }
            }
    		//SetEntityMoveType(client, MOVETYPE_NONE);
    		SetEntProp(client, Prop_Send, "m_fFlags", GetEntProp(client, Prop_Send, "m_fFlags")|FL_FROZEN);
    		if (team == TEAM_SURVIVOR) TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    		
		}
		else
		{
    		if (GetEntityMoveType(client)==MOVETYPE_NONE) SetEntityMoveType(client, MOVETYPE_WALK);
    		SetEntProp(client, Prop_Send, "m_fFlags", (GetEntProp(client, Prop_Send, "m_fFlags")&~FL_FROZEN));
            if (team == TEAM_SURVIVOR) SetEntProp(client,Prop_Data,"m_takedamage",2);
            else if (IsFakeClient(client))
            {
                if (zClass==ZOMBIECLASS_TANK)
                {
                    //if (hTankLeaveStasis) SDKCall(hTankLeaveStasis,client);
                    SetEntProp(client, Prop_Send, "m_hasVisibleThreats",1);
                    SetEntPropEnt(client, Prop_Send, "m_lookatPlayer",GetRandomSurvivor(1,1));
                    SetEntProp(client, Prop_Send, "m_zombieState",1);
                }
            }
		}
    }
}

// Teleport survivor to starting area - ONLY COOP
// Thanks Dragokas -- https://forums.alliedmods.net/showthread.php?t=338572
int safezone_navAreaId = -1;

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

void tp_survivor_start(int client, bool notify = false)
{
   
   if (!IsValidClient(client) || !L4D_HasMapStarted())
   {
       if (DEBUG) LogMessage("[zm] tp_survivor_start failed early");
       return;
   }
   
   float vector[3];
   
   if (L4D_IsSurvivalMode())
   {
       int survivor = GetRandomSurvivor(1,1);
       if (IsValidClient(survivor) && client!=survivor)
       {
           GetClientEyePosition(survivor, vector);
           vector[2] += 10.0;
           TeleportEntity(client, vector, NULL_VECTOR, NULL_VECTOR);
           if (DEBUG) LogMessage("[zm] Teleported to random survivor");
       }
       return;
   }
   
   Address temp_navArea;
   
   if (g_bNavReady && g_hStartAreaList.Length>0)
   {
       int random = 0;
       if (g_hStartAreaList.Length>1) random = GetRandomInt(0,g_hStartAreaList.Length-1);
       PreCalcNav cell;
       g_hStartAreaList.GetArray(random, cell);
       temp_navArea = cell.navArea;
       if (navArea_validStart(temp_navArea))
       {
           safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
           if (DEBUG) LogMessage("[zm] found precomputed start area");
       }
   }
   
   if (safezone_navAreaId<0)
   {
       int g_iInfoPlayerStart = FindEntityByClassname(INVALID_ENT_REFERENCE, "info_player_start");
       if(IsValidEntity_Safe(g_iInfoPlayerStart))
       {
           GetEntPropVector(g_iInfoPlayerStart, Prop_Data, "m_vecOrigin", vector);
           
           // bools: anyz los checkground
           temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
           if (navArea_validStart(temp_navArea))
           {
               safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
               if (DEBUG) LogMessage("[zm] found info_player_start");
           }
       }
       
       if (safezone_navAreaId<0)
       {
           int entity = INVALID_ENT_REFERENCE;
           while( INVALID_ENT_REFERENCE != (entity = FindEntityByClassname(entity, "info_survivor_position")) )
   	       {
           	    if(IsValidEntity_Safe(entity)) 
           	    {
               	    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector);
               	    temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
                    if (navArea_validStart(temp_navArea))
                    {
                        safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                        if (DEBUG) LogMessage("[zm] found info_survivor_position");
                        break;
                    }
                }
   	       }
       }
       
   
       if (safezone_navAreaId<0)
       {
           check_saferoom();
           if (IsValidEntRef(g_iLockedDoor))
           {
               GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecOrigin", vector);
               temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
               if (navArea_validStart(temp_navArea))
               {
                   safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                   if (DEBUG) LogMessage("[zm] found saferoom");
               }
           }
       }
       
       if (safezone_navAreaId<0)
       {
           for (int i = 1; i <= MaxClients; i++)
       	   {
       		 if (!IsClientInGame(i)) continue;
       	
       		 GetEntPropVector(i, Prop_Send, "m_vecOrigin", vector);
             temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
             if (navArea_validStart(temp_navArea))
             {
                safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                if (DEBUG) LogMessage("[zm] found player in start area");
                break;
             }
       		 
       	    }
       }
       
   }
   
   // Find navarea of player start and select random position on navmesh to teleport
   if (safezone_navAreaId>0)
   {
       float randomPos[3];
       Address safezone_navArea = L4D_GetNavAreaByID(safezone_navAreaId);
       if (safezone_navArea && navArea_validStart(safezone_navArea))
       {
           L4D_FindRandomSpot(safezone_navArea,randomPos);
           if (IsObstructed(randomPos,client)) randomPos[2] += 50.0;
           else randomPos[2] += 25.0;
           //TeleportEntity(client, randomPos, NULL_VECTOR, NULL_VECTOR);
           SetAbsOrigin(client,randomPos);
           if (DEBUG) LogMessage("[zm] Teleported %d to safezone", client);
           
            if (notify && !IsFakeClient(client))
            {
                if (!IsValidClientZM()) PrintHintText(client, "%t", "No ZM notify");
                else PrintHintText(client, "%t", "Cannot start notify");
            }
           
       }
       else safezone_navAreaId = -1;
   }
   
}

// Call this if you want to freeze silently (for periodic refreezing)
void freeze_team(bool state = true, int team = TEAM_SURVIVOR)
{
    if (DEBUG) LogMessage("[zm] freeze_team");
    if (team==TEAM_INFECTED)
    {
        if (zm_stage<ZM_STARTED && !state) return;
        if (g_bAllowFreeze && zm_stage==ZM_STARTED && state!=ZM_specials_frozen) return;
    }
    for (int i=1;i<=MaxClients;i++)
    {
        freeze_player(i,state,team);
    }
    if (DEBUG)
    {
        if (state) LogMessage("[zm] Froze team %d", team);
        else LogMessage("[zm] Unfroze team %d", team);
    }
    if (team==TEAM_INFECTED) specials_frozen = state;
    else if (team==TEAM_SURVIVOR && g_iLockedDoor==INVALID_ENT_REFERENCE) saferoom_locked=state;
}

bool IsValidClientZM(int client=-1)
{
    switch (client)
    {
        case -1: return IsValidClient(zm_client);
        default: return IsValidClient(client);
    }
}

// To stop autocull
// L4D2_OnChangeFinaleStage FINALE_NONE -> FINALE_HORDE_ATTACK_1 DOESNT WORK
// Try baseclass->m_nSequence (1172) changed from 47 to 98
// Which makes them attack each other

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg)
{	
	if (!g_bCvarAllow || zm_stage!=ZM_STARTED || finaleType==FINALE_NONE) return Plugin_Continue;
	int current = L4D2_GetCurrentFinaleStage();
	static char current_label[32], label[32]; //
	get_finale_label(current,current_label);
	get_finale_label(finaleType,label);
	int pending_mob = L4D2Direct_GetPendingMobCount();
	if (DEBUG) LogMessage("[zm] L4D2_OnChangeFinaleStage %s -> %s %s, mob %d", current_label, label, arg, pending_mob);
    if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
       L4D2Direct_SetPendingMobCount(script_CommonLimit);
    //if (current==FINALE_NONE && finaleType!=FINALE_NONE)
    //{
    //    LogMessage("AGGRO");
        // force all commons to mobrush so they don't get culled by director
    //    if (hInfectedAttackSurvivorTeam) infected_panic(hInfectedAttackSurvivorTeam,true);
    //    infected_panic(null,true);
    //}
    return Plugin_Continue;
}

int prev_finaleType = -1;

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg)
{   
    if (!g_bCvarAllow || L4D_IsSurvivalMode() || !ZM_finale_announced) return;

    if (finaleType==FINALE_CUSTOM_DELAY) return;
    
    if ( IsValidClientZM() && (finaleType==FINALE_HALFTIME_BOSS || finaleType==FINALE_FINAL_BOSS
                            || finaleType==FINALE_GAUNTLET_BOSS || finaleType==FINALE_CUSTOM_TANK ) )
        EmitSoundToClient(zm_client,SOUND_READY,_,_,_,_,_,GetRandomInt(95,105));
    
    available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    
    float t_now = GetEngineTime();
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

void announce_finale()
{
    if (DEBUG) LogMessage("[zm] announce_finale");
    //if (hInfectedAttackSurvivorTeam) infected_panic(hInfectedAttackSurvivorTeam,true);
    //infected_panic(null,true); // force all commons to mobrush so they don't get culled by director
    if (L4D_IsSurvivalMode() || zm_stage!=ZM_STARTED) return;
    if (panic) toggle_panic(false,true);
    if (!ZM_finale_announced)
    {
        ZM_finale_announced = true;
        if (IsValidClientZM())
        {
            EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
            PrintHintText(zm_client, "%t", "Finale started ZM");
        }
        PrintToChatAll("[zm] %t", "Finale started");
        update_menus();
    }
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    announce_finale();
}

void NextFrame_SetModel(int entref)
{
    if (!IsValidEntRef(entref)) return;
    if (model_pending[0]==0) return;
    SetEntityModel(entref, model_pending);
    pending_tank = false;
}

// Full credit to Dragokas
void Chase(int target)
{
	if (DEBUG) LogMessage("[zm] Chase");
	
	if (ZM_finale_announced || L4D_IsSurvivalMode() )
	{
    	if (DEBUG) LogMessage("[zm] Infected chase is already set, ignoring.");
    	panic_target = -1;
    	return;
	}
	
	if (!IsClientInGame(target))
	{
    	panic_target = -1;
    	return;
	}
	
	bool bTeleported;
	float vPos[3];
	static int iChase = INVALID_ENT_REFERENCE;
	
	// Maybe ZM is being chased and they flew somewhere unreasonable.
	GetClientEyePosition(target, vPos);
	if (TR_PointOutsideWorld(vPos))
	{
    	panic_target = -1;
    	return;
	}
	
	int entity = EntRefToEntIndex(iChase);
	if( !entity || entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity) )
	{
		entity = FindEntityByClassname(MaxClients + 1, "info_goal_infected_chase");
		if( !entity || entity == INVALID_ENT_REFERENCE )
		{
		    if (DEBUG) LogMessage("[zm] New Chase created");
			entity = CreateEntityByName("info_goal_infected_chase");
			if( entity != -1 )
			{
				DispatchSpawn(entity);
				TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
				iChase = EntIndexToEntRef(entity);
				bTeleported = true;
			}
		}
	}
	if( entity != -1 )
	{
		if( !bTeleported)
		{
			AcceptEntityInput(entity, "Disable");
			AcceptEntityInput(entity, "ClearParent");
			TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
		}
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", target);
		AcceptEntityInput(entity, "Enable");
		if (DEBUG) LogMessage("[zm] Chase enabled");
		panic_target = target;
		static char name[MAX_NAME_LENGTH];
        GetClientName(target,name,sizeof(name));
        update_hint("%T", "Chasing x", zm_client, name);
	}
	else panic_target = -1;
}

void disable_chase(bool kill = false)
{
    int chase_ent = FindEntityByClassname(MaxClients + 1, "info_goal_infected_chase");
    if (chase_ent && chase_ent != INVALID_ENT_REFERENCE)
    {
        if (DEBUG) LogMessage("[zm] Chase found, disabled");
     	if (kill) AcceptEntityInput(chase_ent, "Kill");
     	else AcceptEntityInput(chase_ent, "Disable");
    }
    panic_target = -1;
}

void update_panic()
{
    // No panic before round start, in survival, and finales.
    if (zm_stage!=ZM_STARTED || L4D_IsSurvivalMode() || ZM_finale_announced) return;
    
    if (DEBUG) LogMessage("[zm] update_panic triggered");
    
    if (!panic) toggle_panic(true,true,true);
    else
    {
        t_last_panic = GetEngineTime();
        available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    }
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (pending_mob>0)
    {
        if (pending_mob>10 && (g_iCostCommon>=0 || g_iCostUncommon>=0)) pending_mob = 10;
        CreateTimer(2.5, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
        L4D2Direct_SetPendingMobCount(0);
    }
    RequestFrame(create_common_menu);
    RequestFrame(create_uncommon_menu);
    
}

void toggle_panic(bool state = true, bool overwrite = false, bool free = false)
{
    if (L4D_IsSurvivalMode() || ZM_finale_announced)
    {
        update_hint("%T", "Panic is automatic", zm_client);
        if (panic)
        {
            disable_chase();
            panic=false;
        }
        return;
    }
    
    if (DEBUG) LogMessage("[zm] toggle_panic");
    
    bool actual_state;
    if (overwrite) actual_state = state;
    else actual_state = !panic;
    
    if ( zm_stage>=ZM_STARTED && actual_state )
    {
       
       if (!free)
       {
           if ((bank-g_iPanicCost)<0)
           {
              update_hint("%T", "Cannot afford", zm_client);
              return;
           }
           bank -= g_iPanicCost;
       }
       else
       {
           if (DEBUG) LogMessage("[zm] Free panic");
       }
       
       if (DEBUG) LogMessage("[zm] Panic ON");
       if (zm_stage==ZM_STARTED && !panic && IsValidClientZM() && !ZM_finale_announced)
           EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
       panic = true;
       available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON]; 
       t_last_panic = GetEngineTime();
       t_last_autocommon = t_last_panic - 5.0;
       if (manual_panic)
       {
           if (DEBUG) LogMessage("[zm] Manual panic");
           L4D_ForcePanicEvent();
       }
       if (!manual_panic && IsValidClientZM()) PrintHintText(zm_client, "%t", "ZM panic notify");
       if (manual_panic) update_hint("%T", "panic_rate_reduced", zm_client);
       actual_state = true;
       infected_panic(hInfectedAttackSurvivorTeam);
       
    }
    else
    {
        L4D2Direct_SetPendingMobCount(0);
        if (DEBUG) LogMessage("[zm] Panic OFF");
        manual_panic = false;
        if (zm_stage<ZM_STARTED) update_hint("Round not started");
        else update_hint("%T", "panic_rate_normal", zm_client);
        actual_state = false;
        disable_chase();
        if (zm_stage==ZM_STARTED && panic && IsValidClientZM() && !ZM_finale_announced)
            EmitSoundToClient(zm_client,SOUND_PANIC_OFF);
        panic = false;
    }
    
    if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
    else SetConVarInt(FindConVar("director_panic_forever"), 0);
    RequestFrame(create_common_menu);
    RequestFrame(create_uncommon_menu);
    zm_update();
    
}

static char g_sHUD_Text[512];
static char g_sHUD_TextArray[4][128];
static char g_sBuffer[128];
static char g_sSpaces[128] = "                                                                                                                               ";
static char g_sData_HUD_ZM_Text[128];
static char g_sData_HUD_TIMER_Text[128];

void update_EMS_HUD(bool force = false, float delay = 0.1)
{
    if (!force && ems_hud_timer!=INVALID_HANDLE) return;
    if (delay<0.1) perform_HUD_update();
    else ems_hud_timer = CreateTimer(delay,perform_HUD_update);
}

Action perform_HUD_update(Handle timer = null)
{
    ems_hud_timer = INVALID_HANDLE;
    if (!EMS_hud_ready) return Plugin_Stop;
    
    if (DEBUG) LogMessage("[zm] perform_HUD_update");
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TICKER);
    if (!g_bCvarAllow || !clients_in_server || L4D_IsInIntro()>0 || zm_stage>=ZM_END || !L4D_HasMapStarted())
    {
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TIMER);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM_HINT);
        return Plugin_Stop;
    }
    
    int HUD_TIMER_flags = HUD_FLAG_ALIGN_CENTER|HUD_FLAG_TEXT;
    int HUD_ZM_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT;
    int HUD_ZM_HINT_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT|HUD_FLAG_NOBG;
    
    float t_now = GetEngineTime();
    int rows;
    float cols;
    
    if (IsValidClientZM() && zm_stage<ZM_END)
    {
        
        static char panic_str[32];
        if (panic || ZM_finale_announced || (L4D_IsSurvivalMode() && zm_stage==ZM_STARTED) )
        {
            float panic_left;
            if (ZM_finale_announced || L4D_IsSurvivalMode()) panic_left = 0.0;
            else panic_left = g_fPanicDuration - (t_now - t_last_panic);
            if (panic_left<=0.0) Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON", zm_client);
            else
            {
                Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON time", zm_client, panic_left);
                if (panic_left<=5.0)
                {
                    HUD_ZM_flags |= HUD_FLAG_BLINK;
                    HUD_ZM_HINT_flags |= HUD_FLAG_BLINK;
                }
            }
        }
        else Format(panic_str, sizeof(panic_str), "");
        
        static char bank_str[32];
        static char common_str[32];
        static char special_str[32];
        static char witch_str[32];
        
        if (bank_rate>0.0) Format(bank_str, sizeof(bank_str), "%T %d (%.1f)", "Bank", zm_client, bank, bank_rate);
        else Format(bank_str, sizeof(bank_str), "%T %d", "Bank", zm_client, bank);
        
        Format(common_str, sizeof(common_str), "%T", "Common", zm_client);
        Format(special_str, sizeof(special_str), "%T", "Special", zm_client);
        Format(witch_str, sizeof(witch_str), "%T", "Witch", zm_client);
        
        // ZM INFO
        int occupied_SI = get_occupied_units(max_SI,available_SI,live_SI);
        int occupied_commons = get_occupied_units(max_zombie_arr[ZOMBIECLASS_COMMON],available_zombie_arr[ZOMBIECLASS_COMMON],live_zombie_arr[ZOMBIECLASS_COMMON]);
        int occupied_witches = get_occupied_units(max_zombie_arr[ZOMBIECLASS_WITCH],available_zombie_arr[ZOMBIECLASS_WITCH],live_zombie_arr[ZOMBIECLASS_WITCH]);
        FormatEx(g_sData_HUD_ZM_Text,sizeof(g_sData_HUD_ZM_Text),
                 "%s\n%s%s %d/%d\n%s %d/%d\n%s %d/%d",
                 bank_str,
                 panic_str,
                 common_str,occupied_commons,max_zombie_arr[ZOMBIECLASS_COMMON],
                 special_str,occupied_SI,max_SI,
                 witch_str,occupied_witches,max_zombie_arr[ZOMBIECLASS_WITCH]);
        
        TrimString(g_sData_HUD_ZM_Text);
        CountStringRowsCols(g_sData_HUD_ZM_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.008, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.1, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026*rows, HUD_ZM);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s %s", g_sData_HUD_ZM_Text, g_sSpaces);
        g_sHUD_TextArray[HUD_ZM] = g_sBuffer;
        
        // ZM HINT
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.0, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.07, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.51, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_ZM_HINT);
        TrimString(ZM_hint);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n%s\n %s", ZM_hint, g_sSpaces);
        g_sHUD_TextArray[HUD_ZM_HINT] = g_sBuffer;
        
    }
    else
    {
        HUD_ZM_flags = HUD_FLAG_NOTVISIBLE;
        HUD_ZM_HINT_flags = HUD_FLAG_NOTVISIBLE;
    }
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_flags, _, HUD_ZM);
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_HINT_flags, _, HUD_ZM_HINT);
    
    if (!IsValidClientZM())
    {
       
       if (IsValidClient(client_offer))
       {
           static char name[MAX_NAME_LENGTH]; 
           GetClientName(client_offer,name,sizeof(name));
           int timeleft = RoundFloat(g_fFairQueueWait - (t_now - t_offer));
           if (timeleft<0) timeleft = 0;
           Format(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),
           "%T", "Offered ZM Ticker", LANG_SERVER, name, timeleft);
       }
       else
       {
           if (autocommon_setting>0) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
           else Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "No ZM notify", LANG_SERVER);
       }
    }
    else
    {
        if (zm_stage>=ZM_STARTED || force_started || L4D_IsSurvivalMode()) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
        else
        {
            if (zm_can_start)
            {
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Survivors can leave", LANG_SERVER);
                HUD_TIMER_flags |= HUD_FLAG_BLINK;
            }
            else
            {
                
                float time1 = saferoom_cooldown - (t_now - t_last_join);
                float time2 = g_fPrepTimeZM - (t_now - t_zm_join);
                
                float t_biggest;
                if (time1>time2) t_biggest=time1;
                else t_biggest = time2;
                
                if (t_biggest<0.0) t_biggest = 0.0;
                if (t_biggest<=5.0) HUD_TIMER_flags |= HUD_FLAG_BLINK;
                
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Round can start in", LANG_SERVER, RoundFloat(t_biggest));
            }
        }
    }
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_TIMER_flags, _, HUD_TIMER);
    if (HUD_TIMER_flags!=HUD_FLAG_NOTVISIBLE)
    {
        
        CountStringRowsCols(g_sData_HUD_TIMER_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.35, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.14, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_TIMER);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n  %s\n %s", g_sData_HUD_TIMER_Text, g_sSpaces);
        g_sHUD_TextArray[HUD_TIMER] = g_sBuffer;
    }
    
    // TICKER - PLACEHOLDER
    g_sBuffer = "\0";
    FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s%s", g_sSpaces, g_sSpaces);
    g_sHUD_TextArray[HUD_TICKER] = g_sBuffer;
    
    ImplodeStrings(g_sHUD_TextArray, sizeof(g_sHUD_TextArray), " ", g_sHUD_Text, sizeof(g_sHUD_Text));
    GameRules_SetPropString("m_szScriptedHUDStringSet", g_sHUD_Text);
    
    return Plugin_Stop;
    
}

bool can_change_finale_stage()
{
    if (!ZM_finale_announced) return false;
    if (zm_stage>=ZM_END) return false;
    if (!holdfinale) return true;
    int current = L4D2_GetCurrentFinaleStage();
    if (current==FINALE_CUSTOM_SCRIPTED || current==FINALE_CUSTOM_DELAY || current==FINALE_CUSTOM_CLEAROUT)
        return true;
    if (bank<g_iBonusFinaleStage) return true;
    if ( bank>=(0.5*g_iBonusFinaleStage*g_iAliveSurvivors) ) return false;
    if ( live_SI<=1 && live_zombie_arr[ZOMBIECLASS_TANK]<=0 ) return true;
    return false;
}

float get_bank_rate()
{
 
 bool zero_rate = L4D_IsSurvivalMode() || !L4D_HasAnySurvivorLeftSafeArea();
 float multiplier = 1.0;
 if (!zero_rate && ZM_finale_announced)
 {
     // Coop finale logic
     if (can_change_finale_stage()) L4D2Direct_SetPendingMobCount(0);
     else
     {
         // Hold pending mob to prevent stage advance!
         int pending_mob = L4D2Direct_GetPendingMobCount();
         if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
            L4D2Direct_SetPendingMobCount(script_CommonLimit);
     }
     int current = L4D2_GetCurrentFinaleStage();
     if (current==FINALE_GAUNTLET_ESCAPE || current==FINALE_HORDE_ESCAPE)
     {
         // Infinite Finale
         zero_rate = false;
         multiplier = 2.0;
     }
     else if ( (current==FINALE_CUSTOM_CLEAROUT || current==FINALE_CUSTOM_SCRIPTED) &&
               (GetEngineTime()-t_finale)>=g_fMinFinaleStage ) 
     {
         zero_rate = false;
     }
     else zero_rate = true;
 }
 
 if (zero_rate)
 {
     bank_rate = 0.0;
     return bank_rate;
 }
 
 // Coop logic
 float final_rate = g_fBankRateBase;
 if (g_iAliveSurvivors>0) final_rate += g_iAliveSurvivors*g_fBankRatePlayer;
 if (panic && manual_panic) final_rate *= g_fPanicRateMultiplier;
 bank_rate = multiplier*final_rate;
 return bank_rate;
 
}

Action check_fog_distance(Handle timer = null)
{
    if (DEBUG) LogMessage("[zm] check_fog_distance");
    float new_fog_distance = FOG_DISTANCE;
	int fog_controller = -1;
	while( (fog_controller = FindEntityByClassname(fog_controller, "env_fog_controller")) != INVALID_ENT_REFERENCE )
	{
		if (g_DHook_AcceptInput)
     	{
           	if (IsValidEntity(fog_controller))
           	{
           	   if (DEBUG) LogMessage("[zm] Hooking fog_controller g_DHook_AcceptInput");
           	   DHookEntity(g_DHook_AcceptInput, true, fog_controller, INVALID_FUNCTION, DHook_Fog_AcceptInput);
           	}
     	}
		bool enabled = GetEntProp(fog_controller, Prop_Data, "m_fog.enable") > 0;
		if (enabled)
		{
        		float fog_end = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.end");
        		float fog_farz = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.farz");
        		float maxdensity = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.maxdensity");
        		if (DEBUG) LogMessage("[zm] Found env_fog_controller %d", fog_controller);
        		if (DEBUG) LogMessage("[zm] end farz maxdensity: %f %f %f", fog_end, fog_farz, maxdensity);
        		if (maxdensity>=1.0)
        		{
            		if (fog_farz<new_fog_distance && fog_farz>0.0) new_fog_distance = fog_farz;
        		}
    		
		}
	}
	
	if (new_fog_distance!=fog_distance)
	{
	    fog_distance = new_fog_distance;
	    CreateTimer(10.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(30.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(45.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(60.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
        LogMessage("[zm] ZM spawner fog distance: %f", fog_distance);
	}
	
	return Plugin_Stop;
	
}

void set_force_start(bool state = true)
{
    if (state && !force_started)
    {
        force_started = true;
        AddNormalSoundHook(SwapSound);
    }
    else if (!state && force_started)
    {
        force_started = false;
        RemoveNormalSoundHook(SwapSound);
    }
}

Action zm_new_round(Handle timer = null)
{
    if (!g_bCvarAllow)
    {
        zm_stage = ZM_END;
        return Plugin_Stop;
    }
    
    if (g_hRandomizer.IntValue==2) random_gamemode();
    
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
    t_last_update = GetEngineTime();
    t_last_panic = t_last_update;
    t_last_spawner_update = t_last_update;
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
	// Listen to all info_director inputs
	if (g_DHook_AcceptInput)
	{
       	if (IsValidEntity(info_director))
       	{
       	   DHookEntity(g_DHook_AcceptInput, false, info_director, INVALID_FUNCTION, DHook_Director_AcceptInput);
       	}
	}
	
	check_fog_distance();
	
	remove_all_ZM_glows();
	
	lastdoor = -1;
	
	update_director_script_scopes(false);
	//scope_changed = false;
	survival_activated = false;
	
	targetName_pending = "";
	model_pending = "";
	pending_tank = false;
	
	if (fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(1.0,fair_queue_update);
	
	infinite_delay_natural_mob();
	CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
	natural_first_wait = true;
	L4D2Direct_SetPendingMobCount(0);
	
	PrintToChatAll("[zm] Type /zm_help to read the Zombie Master tutorial.");
	
	zm_update();
	
	return Plugin_Continue;
    
}

void reset_available_zombies()
{
  available_SI = max_SI;
  available_zombie_arr = max_zombie_arr;
}

bool is_zombie_available_cooldown(int zClass)
{
    if (zClass>ZOMBIECLASS_TANK) return false;
    switch (zClass)
    {
        case ZOMBIECLASS_COMMON: { if (available_zombie_arr[zClass]>0) return true; }
        case ZOMBIECLASS_WITCH: { if (available_zombie_arr[zClass]>0) return true; }
        default: { if (available_SI>0 && available_zombie_arr[zClass]>0) return true; }
    }
    return false;
}

// Cooldowns for specials and witches
float get_class_cooldown(int ZOMBIECLASS)
{
    switch (ZOMBIECLASS)
    {
        case ZOMBIECLASS_WITCH: return g_fWitchCooldown;
        case ZOMBIECLASS_TANK: return g_fTankCooldown;
        default: return g_fSpecialCooldown;
    }
}

void sanity_check_available(int zClass, float t_now = -1.0)
{
    if (t_now<0.0) t_now = GetEngineTime();
    bool apply_cooldown = false;
    if (live_zombie_arr[zClass]>0) apply_cooldown = true;
    else if ( available_zombie_arr[zClass]<max_zombie_arr[zClass] &&
              t_now>(timestamp_available_arr[zClass]+0.15) ) //timers can jitter
    {
        static char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        LogMessage("[zm] unexpected sanity_check %s fallthrough, report to mod authors", zClassName);
        add_available_zombie(zClass);
        apply_cooldown = true;
    }
    if (apply_cooldown) timestamp_available_arr[zClass] = t_now + get_class_cooldown(zClass);
}

void create_timer_add_available_zombie(float delay,int zClass, int round, int count=1)
{
    // sourcemod timers cannot be smaller than 0.1
    if (delay<0.1)
    {
        add_available_zombie(zClass);
        return;
    }
    static char zClassName[32]; 
    get_zombieclass_name(zClass,zClassName);
    if (DEBUG) LogMessage("[zm] create_timer_add_available_zombie %d %s, delay: %f", count, zClassName, delay);
    timestamp_available_arr[zClass] = GetEngineTime() + delay;
    DataPack pack;
    CreateDataTimer(delay, timer_add_available_zombie, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(zClass);
    pack.WriteCell(round);
    pack.WriteCell(count);
}

Action timer_add_available_zombie(Handle timer, DataPack pack)
{
    int zClass,round,count;
    pack.Reset();
    zClass = pack.ReadCell();
    round = pack.ReadCell();
    count = pack.ReadCell();
    if (round!=roundcount) return Plugin_Continue;
    add_available_zombie(zClass,count);
    return Plugin_Stop;
}

void add_available_zombie(int zClass, int add=1, bool draw = true)
{
    if (zClass>ZOMBIECLASS_TANK) return;
    
    if (zm_stage>=ZM_PREP)
    {
        static char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        if (DEBUG) LogMessage("[zm] add_available_zombie %d %s", add, zClassName);
    }
    
    if (add<0) timestamp_available_arr[zClass] = GetEngineTime()+get_class_cooldown(zClass);
    
    available_zombie_arr[zClass] += add;
    if (available_zombie_arr[zClass]>max_zombie_arr[zClass]) available_zombie_arr[zClass] = max_zombie_arr[zClass];
    else if (available_zombie_arr[zClass]<0) available_zombie_arr[zClass] = 0;
     
    // Will this operation change available Specials?
    int add_SI;
    switch (zClass)
    {
        case ZOMBIECLASS_COMMON: add_SI=0;
        case ZOMBIECLASS_WITCH: add_SI=0;
        default: add_SI = add;
    }
    
    if (add_SI!=0)
    {
        available_SI += add_SI;
        if (available_SI>max_SI) available_SI = max_SI;
        else if (available_SI<0) available_SI = 0;
        if (draw && IsValidClientZM() && zm_stage>=ZM_PREP && zm_stage<ZM_END)
        {
            if (zClass == ZOMBIECLASS_TANK) create_boss_menu();
            else create_special_menu();
        }
    }
    if (draw && IsValidClientZM() && zm_stage>=ZM_PREP && zm_stage<ZM_END) update_EMS_HUD();
}

void reset_live_zombie_arr(bool common=true, bool witch=true, bool special=true)
{
    int length = sizeof(live_zombie_arr);
    for(int i = 0; i < length; i++)
	{
		switch (i)
		{
    		case ZOMBIECLASS_COMMON: { if (common) live_zombie_arr[i] = 0; }
    		case ZOMBIECLASS_WITCH: { if (witch) live_zombie_arr[i] = 0; }
    		default: { if (special) live_zombie_arr[i] = 0; }
		}
	}
	
}

Action stop_tankmusic(Handle timer=null)
{
    if (live_zombie_arr[ZOMBIECLASS_TANK]>0) return Plugin_Stop;
    for (int i=1;i<=MaxClients;i++)
	{
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
 		L4D_StopMusic(i, "Event.Tank");
 		L4D_StopMusic(i, "Event.TankMidpoint");
 		L4D_StopMusic(i, "Event.TankMidpoint_Metal");
 		L4D_StopMusic(i, "Event.TankBrothers");
 		L4D_StopMusic(i, "C2M5.RidinTank1");
 		L4D_StopMusic(i, "C2M5.RidinTank2");
 		L4D_StopMusic(i, "C2M5.BadManTank1");
 		L4D_StopMusic(i, "C2M5.BadManTank2");
    }
    return Plugin_Stop;
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

Action ZMPanic(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (!panic) manual_panic = true;
    toggle_panic();
    return Plugin_Continue;
}

Action ZMTeleport(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    
    if (IsPlayerAlive(zm_client)) return Plugin_Continue;
    
    if (zm_stage<ZM_STARTED)
    {
        tp_survivor_start(zm_client);
        return Plugin_Continue;
    }
    
    int target = L4D_GetHighestFlowSurvivor();
    if (IsValidClient(target) && IsPlayerAlive(target))
    {
        float vTP[3];
        GetClientEyePosition(target, vTP);
        vTP[2] += 10.0;
        TeleportEntity(zm_client, vTP, NULL_VECTOR, NULL_VECTOR);
    }

    return Plugin_Continue;
}

void remove_all_ZM_glows()
{
    if (DEBUG) LogMessage("[zm] remove_all_ZM_glows");
    for(int i = 0; i < sizeof(g_iGlowList); i++)
	{
		if (g_iGlowList[i]==INVALID_ENT_REFERENCE) continue;
		remove_ZM_glow(i);
	}
}

// remove glow of parent entity
void remove_ZM_glow(int entity)
{
    if (DEBUG) LogMessage("[zm] remove_ZM_glow %d", entity);
    if (!IsValidEntity(entity))
    {
        if (DEBUG) LogMessage("[zm] remove_ZM_glow %d skipped", entity);
        if (entity>=0 && entity<=MAXENTITIES) g_iGlowList[entity]=INVALID_ENT_REFERENCE;
        return; 
    }
    int entref_glow = g_iGlowList[entity];
    hp_timers[entity] = INVALID_HANDLE;
    if (entref_glow==INVALID_ENT_REFERENCE) return;
    if ( IsValidEntRef(entref_glow) && HasEntProp(entref_glow, Prop_Send, "m_CollisionGroup") )
    {
       static char class[32];
       GetEntityClassname(entref_glow, class, sizeof(class));
       if (strcmp(class,"prop_dynamic_ornament")==0)
       {
   	       AcceptEntityInput(entref_glow, "Kill");
   	       if (DEBUG) LogMessage("[zm] remove_ZM_glow %d killed prop_dynamic_ornament %d", entity, entref_glow);
   	       return;
       }
    }
    g_iGlowList[entity] = INVALID_ENT_REFERENCE;
    if (DEBUG) LogMessage("[zm] remove_ZM_glow %d unexpectedly did nothing", entity);
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

int arr_hp_vec[101][3];
void precache_survivor_hp()
{
    int color[3];
    for(int i = 0; i < sizeof(arr_hp_vec); i++)
    {
          GetSurvivorHealthColor(i,color,false,false);
          arr_hp_vec[i][0] = color[0];
          arr_hp_vec[i][1] = color[1];
          arr_hp_vec[i][2] = color[2];
    }   
}

void GetSurvivorHealthColor_pre(int hp, int color[3], bool rescue=false, bool critical=false)
{
    if (rescue || critical)
    {
        GetSurvivorHealthColor(hp,color,rescue,critical);
        return;
    }
    if (hp<0) hp=0;
    else if (hp>100) hp=100;
    color[0] = arr_hp_vec[hp][0];
    color[1] = arr_hp_vec[hp][1];
    color[2] = arr_hp_vec[hp][2];
}

bool survivor_dominated(int client)
{
    return L4D_IsPlayerPinned(client) || L4D2_GetQueuedPummelAttacker(client)>0;//L4D2_GetSpecialInfectedDominatingMe(client)>0;
}

Action Check_Dominated(Handle timer, int victim)
{
    if (!dominated[victim]) return Plugin_Stop;
    if (!IsValidClient(victim) || !IsPlayerAlive(victim) || !survivor_dominated(victim))
    {
        if (DEBUG) LogMessage("[zm] Dominated end %d", victim);
        request_update_glow(victim,true,0.0); // updates dominated[victim]
        return Plugin_Stop;
    }
    return Plugin_Continue;
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

// Infected unit glow -- white
Action CreateZMGlow_white(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target);
    return Plugin_Stop;
}

// Saferoom door glow -- red
Action CreateZMGlow_red(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target,true);
    return Plugin_Stop;
}

// Handled: invisible
// Continue: visible
Action OnTransmitZM(int entity, int client)
{
   	int parent = GetEntPropEnt(entity,Prop_Data,"m_pParent");
   	bool valid = IsValidEntity(parent);
   	if (valid && IsValidClient(parent) && !IsPlayerAlive(parent)) valid = false;
   	if (valid && client==zm_client) return Plugin_Continue;
   	else if (!valid || zm_client<0)
   	{
       	if (DEBUG) LogMessage("[zm] OnTransmitZM killing glow %d, parent %d", entity, parent); 
       	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
       	AcceptEntityInput(entity, "Kill");
   	}
    return Plugin_Handled;
}

void CreateZMGlow(int target, bool red = false)
{
	if (!IsValidClientZM()) return;
	if (!IsValidEntity(target) || target==zm_client) return;
	
	if (!red && HasEntProp(target,Prop_Data,"m_iHealth"))
	{
    	if (GetEntProp(target,Prop_Data,"m_iHealth")<=0) return;
	}
	
	int glowref = g_iGlowList[target];
	if ( glowref!=INVALID_ENT_REFERENCE && IsValidEntity(glowref) )
	{
	    int parent = GetEntPropEnt(glowref,Prop_Data,"m_pParent");
	    if (parent==target) return;
	    AcceptEntityInput(glowref,"Kill");
	}
	
	if (DEBUG) LogMessage("[zm] CreateZMGlow");
	
	int glow = CreateEntityByName("prop_dynamic_ornament");
	if (!IsEntitySafe(glow)) return;
	
	int eFlags = GetEdictFlags(target);
	if ((eFlags & FL_EDICT_ALWAYS)<=0) SetEdictFlags(target, eFlags | FL_EDICT_ALWAYS);
	
	static char sModelName[64];
	GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
	
	SetEntityModel(glow, sModelName);
	DispatchSpawn(glow);
	SetEntProp(glow, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRange", 999999);
	SetEntProp(glow, Prop_Send, "m_iGlowType", 3);
	if (red) SetEntProp(glow, Prop_Send, "m_glowColorOverride", 254);
	else SetEntProp(glow, Prop_Send, "m_glowColorOverride", RGB_ZM);
	AcceptEntityInput(glow, "StartGlowing");
	SetEntityRenderMode(glow, RENDER_TRANSCOLOR);
	SetEntityRenderColor(glow, 0, 0, 0, 0);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", target);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetAttached", target);
    g_iGlowList[target] = EntIndexToEntRef(glow);
	SDKHook(glow, SDKHook_SetTransmit, OnTransmitZM);
	DispatchKeyValue(glow, "targetname", "zm_glow");
	if (!red)
	{
    	// clients will hook to player_hurt; witches need this hook.
    	if (!IsValidClient(target)) SDKHook(target, SDKHook_OnTakeDamage, OnTakeDamageWitch);
        request_update_glow(target,true,0.0);
	}
	if (DEBUG) LogMessage("[zm] CreateZMGlow %d %d %d", target, glow, g_iGlowList[target]);
}

void request_update_glow(int i, bool force = false, float delay=0.1)
{
    if (!IsValidEntity(i)) return;
    if (!force && hp_timers[i]!=null) return;
    if (delay<0.1) update_glow(i);
    else hp_timers[i] = CreateTimer(delay,Timer_update_glow,EntIndexToEntRef(i));
}

Action Timer_update_glow(Handle timer, int entref)
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    update_glow(EntRefToEntIndex(entref));
    return Plugin_Stop;
}

void update_glow(int i)
{
    if (DEBUG) LogMessage("[zm] update_glow %d", i);
    if (!IsValidEdict(i)) return;
    hp_timers[i]=null;
    if (!g_bCvarAllow) return;
    if (!IsValidEntity(i) || zm_stage>=ZM_END) return;
    if (IsValidClient(i))
    {
        switch (GetClientTeam(i))
        {
            case TEAM_INFECTED: update_zm_glow(i);
            case TEAM_SURVIVOR: UpdateSurvivorGlow(i);
            default:
            {
                L4D2_SetPlayerSurvivorGlowState(i,false);
                L4D2_RemoveEntityGlow(i);
            }
        }
        
    }
    else
    {
        static char class[16];
        GetEntityClassname(i,class,sizeof(class));
        if (strcmp(class,"witch")==0) update_zm_glow(i);
    }
}

public void L4D_OnEnterGhostState(int client)
{
    if (!g_bCvarAllow) return;
    if (DEBUG) LogMessage("[zm] L4D_OnEnterGhostState %d", client); 
    request_update_glow(client);  
}

void update_zm_glow(int parent)
{
   	if (DEBUG) LogMessage("[zm] update_zm_glow %d", parent);
   	int health = GetEntProp(parent,Prop_Data,"m_iHealth");
   	if (IsValidClient(parent))
   	{
       	if (!IsPlayerAlive(parent) || L4D_IsPlayerGhost(parent))
       	{
           	health=0;
           	L4D2_RemoveEntityGlow(parent);
           	L4D2_SetPlayerSurvivorGlowState(parent,false);
       	}
       	else if (L4D_IsPlayerIncapacitated(parent)) health=1;
   	}
   	
    int entref_glow = g_iGlowList[parent];
    if (!IsValidEntRef(entref_glow)) return;
	
	if (health<=0 || parent==zm_client || !IsValidClientZM())
	{
    	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
    	AcceptEntityInput(entref_glow, "Kill");
	}
	else
	{
	    int color[3];
	    bool vomited = IsValidClient(parent) && is_player_vomited(parent);

       	if (health<=1) color[0] = 255;
        else
        {
            int max_health = GetEntProp(parent,Prop_Data,"m_iMaxHealth");
            if (health>max_health)
            {
                max_health = health;
                SetEntProp(parent,Prop_Data,"m_iMaxHealth",max_health);
            }
            float fraction = 1.0*health/max_health;
            if (fraction<0.0) fraction = 0.0;
            if (vomited)
            {
               	color[0] = 144+RoundFloat(fraction*111.0);
            	color[1] = 19+RoundFloat(fraction*236.0);
            	color[2] = 255;
        	}
        	else
        	{
   	            int RGB_frac = RoundFloat(255*fraction);
   	            color[0] = 255;
               	color[1] = RGB_frac;
               	color[2] = RGB_frac;
        	}
    	}
	    
       	static char targetName[64];
        GetEntPropString(parent, Prop_Data, "m_iName", targetName, sizeof(targetName));
       	bool flashing = false;
       	if (EntIndexToEntRef(parent)==entref_control || strcmp(targetName,"zm_unit_spotted")==0 ) flashing = true;
       	L4D2_SetEntityGlow(entref_glow,L4D2Glow_Constant,999999,0,color,flashing);
       	if (active_looktarget && entref_control==EntIndexToEntRef(parent)) update_ZM_looktarget_HP();
	}
	
}

// There is a deeper layer of glows that the game is managing I can't seem to access with l4dhooks.
void UpdateSurvivorGlow(int client)
{   
    bool alive = IsPlayerAlive(client);
    bool survivor_glow = !alive || is_player_vomited(client);
    L4D2_SetPlayerSurvivorGlowState(client,survivor_glow);
    
    if (DEBUG)
    {
        static char name[MAX_NAME_LENGTH]; 
        GetClientName(client,name,sizeof(name));
        LogMessage("[zm] UpdateSurvivorGlow %s alive %d SurvivorGlow %d",name,alive,survivor_glow);
    }
    
    if (alive && survivor_glow) L4D2_RemoveEntityGlow(client);
    else
    {
        bool rescue = false;
        if (alive)
        {
            rescue = survivor_dominated(client);
            dominated[client] = rescue;
        }
        else dominated[client] = false;
        
        bool should_glow = rescue || alive;
        if (should_glow)
        {
           int hp = GetEntProp(client,Prop_Data,"m_iHealth");
           bool flashing = alive && L4D_IsPlayerOnThirdStrike(client);
           bool critical = alive && (L4D_IsPlayerIncapacitated(client) || L4D_IsPlayerHangingFromLedge(client));
           int color[3];
           GetSurvivorHealthColor_pre(hp,color,rescue,critical);
       	   L4D2_SetEntityGlow(client,
                              L4D2Glow_Constant,
                              999999,0,color,flashing);
        }
        else L4D2_RemoveEntityGlow(client);
	}
}

Action OnTakeDamageWitch(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (damage>32.0)
    {
        static char class[32];
        GetEntityClassname(inflictor, class, sizeof(class));
        switch (class[0])
        {
            case 'p':
            {
                 if (StrContains(class,"prop_minigun",false)!=-1)
                 {
                     damage = 32.0;
                     return Plugin_Changed;
                 }
            }
        }
    }
    request_update_glow(victim);
    return Plugin_Continue;
}

Action Timer_Clear_targetname_pending(Handle timer = null)
{
    if (pending_tank)
    {
        targetName_pending = "";
        pending_tank = false;
        model_pending = "";
        LogMessage("[zm] unexpectedly cleared targetName_pending. Report to mod authors.");
    }
    return Plugin_Stop;
}

float zm_deathPos[3], zm_deathAngles[3];

Action ZMControlSI(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Stop;
    
    if (is_zm_spamming()) return Plugin_Continue;
    
    if (DEBUG) LogMessage("[zm] ZMControlSI");
    
    int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
    if (zClass==ZOMBIECLASS_TANK && L4D_IsPlayerIncapacitated(zm_client)) return Plugin_Continue;
    
    // ZM wants to let go of special infected.
    if ( IsPlayerAlive(zm_client) && GetClientTeam(zm_client)==TEAM_INFECTED && !L4D_IsPlayerIncapacitated(zm_client) )
    {
        
        int health = GetEntProp(zm_client,Prop_Data,"m_iHealth");
        if (zClass==ZOMBIECLASS_BOOMER && health==0)
        {
            // Tank stutter fix is active, prevent ZM from doing anything.
            return Plugin_Continue;
        }
        
        if ( L4D2_GetSurvivorVictim(zm_client)<=0 &&
             ( !ZM_finale_announced || zClass!=ZOMBIECLASS_TANK ) )
        {
            
            //SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
            GetClientAbsOrigin(zm_client, vOrigin);
            GetClientEyeAngles(zm_client, vAngles); 
            GetClientEyePosition(zm_client, vEye);
            GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
            int maxhealth = GetEntProp(zm_client,Prop_Data,"m_iMaxHealth");
            int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
            zm_use_notify = true;
            
            zm_deathPos = vEye;
            zm_deathAngles = vAngles;
            
            static char sModelName[64];
            GetEntPropString(zm_client, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
            
            static char targetName[64];
            GetEntPropString(zm_client, Prop_Data, "m_iName", targetName, sizeof(targetName));
            if (strcmp(targetName,"zm_control")==0) targetName = "";
            else if (strcmp(targetName,"zm_unit_control")==0) targetName = "zm_unit";
            DispatchKeyValue(zm_client, "targetname", "zm_client");
            
            if (zClass == ZOMBIECLASS_TANK)
            {
                pending_tank = true;
                targetName_pending = targetName;
                maxhp_pending = maxhealth;
                model_pending = sModelName;
                if (DEBUG) LogMessage("[zm] targetName_pending %s", targetName_pending);
                CreateTimer(0.1,Timer_Clear_targetname_pending,TIMER_FLAG_NO_MAPCHANGE);
                L4D_ReplaceWithBot(zm_client);
            }
            else
            {
                //L4D_ReplaceWithBot(zm_client); // why doesn't this work :/
                float timestamp_cooldown = 0.0;
                int ability = GetEntPropEnt(zm_client, Prop_Send, "m_customAbility");
                if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
                live_SI -= 1;
                live_zombie_arr[zClass] -= 1;
                int bot = ZM_Spawn_SI(zm_client,zClass,true,true,vOrigin);
                if (IsValidEntity(bot))
                {
                    transfer_SI_properties(bot,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
                    if (L4D_IsPlayerStaggering(zm_client)) L4D_StaggerPlayer(bot,bot,NULL_VECTOR);
                }
                
            }
            
            L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
            SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
            if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
            L4D_CleanupPlayerState(zm_client);
            SetEntityMoveType(zm_client, MOVETYPE_NONE);
            SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
            SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
            SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
            TeleportEntity(zm_client, vEye, vAngles, NULL_VECTOR);
            RequestFrame(ZM_FixCamera,false);
            update_zm_flashlight();
        }
        else update_hint("%T", "Cannot control", zm_client);
        
        return Plugin_Continue;
        
    }
    
    update_ZM_looktarget(false);
    if (!IsValidEntRef(entref_control))
    {
        update_hint("%T", "Invalid target", zm_client);
        return Plugin_Continue;
    }
    int entity = EntRefToEntIndex(entref_control);
    if (!IsValidEntity(entity) || !IsValidClient(entity) || GetClientTeam(entity)!=TEAM_INFECTED || !IsFakeClient(entity) || !IsPlayerAlive(entity)) 
    {
        update_hint("%T", "Invalid target", zm_client);
        return Plugin_Continue;
    }
    
    static char class[32];
  	GetEntityClassname(entity, class, sizeof(class));
  	if (strcmp(class,"player")==0 && L4D2_GetSurvivorVictim(entity)<=0 )
  	{
         recordpos = true;
         float vOrigin[3], vAngles[3], vVelocity[3];
         GetClientAbsOrigin(entity, vOrigin);
         GetClientEyeAngles(entity, vAngles); 
         GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vVelocity);
         int health = GetEntProp(entity,Prop_Data,"m_iHealth");
         if (health<=0 || L4D_IsPlayerIncapacitated(entity))
         {
             update_hint("%T", "Cannot control", zm_client);
             return Plugin_Continue;
         }
         int maxhealth = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
         int fFlags = GetEntProp(entity, Prop_Data, "m_fFlags");
         zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
         
         static char targetName[64];
         GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
         if (strcmp(targetName,"zm_unit")==0) DispatchKeyValue(entity, "targetname", "zm_unit_dead");
         else
         {
             DispatchKeyValue(entity, "targetname", "zm_control_dead");
             if (targetName[0]==0) DispatchKeyValue(zm_client, "targetname", "zm_control");
         }
         
         static char sModelName[64];
         GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
         
         remove_ZM_glow(entity);
         
         float timestamp_cooldown = 0.0;
         int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
         if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
         
         if (active_looktarget) update_hint("");
         
         ChangeClientTeam(zm_client,TEAM_ZM);
         L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
         
         bool stagger = false;
         if (L4D_IsPlayerStaggering(entity)) stagger = true;
         
         if (zClass==ZOMBIECLASS_TANK)
         {
             if (IsObstructed(vOrigin,entity)) vOrigin[2] += 25.0;
             L4D_ReplaceTank(entity,zm_client);
         }
         else L4D_TakeOverZombieBot(zm_client,entity);
         L4D_CleanupPlayerState(zm_client);
         
         transfer_SI_properties(zm_client,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
         if (stagger) L4D_StaggerPlayer(zm_client,zm_client,NULL_VECTOR);
         zm_use_notify = true;
         update_zm_flashlight();
  	 }
  	 else update_hint("%T", "Cannot control", zm_client);

    return Plugin_Continue;
}

float t_stutter = 0.0;
bool verify_stutter_fixed()
{
    if (!IsValidClientZM()) return true;
    if (IsClientTimingOut(zm_client))
    {
        float latency = GetClientAvgLatency(zm_client, NetFlow_Both) * 2.0;
        t_stutter = GetEngineTime() + latency;
        return false;
    }
    if (IsPlayerAlive(zm_client))
    {
        return true;
    }
    if ( GetEngineTime()>(t_stutter+5.0) )
    {
        LogMessage("[zm] Tank stutter fix timed out, report this to mod authors");
        EmitSoundToAll(SOUND_BUG);
        return true;
    }
    return false;
}

void NextFrame_Check_Stutter(int stored_roundcount)
{
    if (DEBUG) LogMessage("[zm] NextFrame_Check_Stutter");
    if (stored_roundcount!=roundcount) return;
    if (verify_stutter_fixed() && GetEngineTime()>t_stutter)
    {
        RequestFrame(ZM_FixCamera,false);
        CreateTimer(1.0,stop_tankmusic,TIMER_FLAG_NO_MAPCHANGE);
    }
    else RequestFrame(NextFrame_Check_Stutter,stored_roundcount);
}

void ZM_FixTankStutter(bool freeze = true)
{
    if (!IsValidClientZM()) return;
    if (GetClientTeam(zm_client)==TEAM_SURVIVOR && IsPlayerAlive(zm_client)) return;

    recordpos = false;
    
    SetEntityMoveType(zm_client, MOVETYPE_NONE);
    L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
    L4D_BecomeGhost(zm_client);
    L4D_SetClass(zm_client,ZOMBIECLASS_BOOMER);
    TeleportEntity(zm_client, {0.0,0.0,0.0}, NULL_VECTOR, NULL_VECTOR);	
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", ZOMBIECLASS_BOOMER);
    L4D_MaterializeFromGhost(zm_client);
    L4D_RespawnPlayer(zm_client);
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", ZOMBIECLASS_BOOMER);
    L4D_SetClass(zm_client,ZOMBIECLASS_BOOMER);
    TeleportEntity(zm_client, {0.0,0.0,0.0}, NULL_VECTOR, NULL_VECTOR);	
    SetEntityMoveType(zm_client, MOVETYPE_NONE);
    SetEntProp(zm_client,Prop_Data,"m_iHealth",0);
    
    float latency = GetClientAvgLatency(zm_client, NetFlow_Both) * 2.0;
    t_stutter = GetEngineTime() + latency;
    
    if (DEBUG) LogMessage("[zm] ZM_FixTankStutter, latency %f", latency);
    RequestFrame(NextFrame_Check_Stutter,roundcount);
}

Action Unfreeze_ZM(Handle timer=null)
{
    if (!IsValidClientZM()) return Plugin_Stop;
    if (!IsPlayerAlive(zm_client))
    {
        SetEntityMoveType(zm_client, MOVETYPE_NOCLIP); //
        SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
        SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
        SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
        SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
        EmitSoundToClient(zm_client,SOUND_VISION);
    }
    return Plugin_Stop;
}

void ZM_FixCamera(bool freeze = true)
{
    if (!IsValidClientZM()) return;
    
    // Fix camera stutter
    if (GetEntProp(zm_client,Prop_Send,"m_zombieClass")==ZOMBIECLASS_TANK)
    {
        if (IsPlayerAlive(zm_client)) ForcePlayerSuicide(zm_client);
        RequestFrame(ZM_FixTankStutter,freeze);
        return;
    }
    
    L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
    SetEntPropEnt(zm_client, Prop_Send, "m_hViewEntity", -1);
    SetEntProp(zm_client, Prop_Send, "m_iFOV", 0);
    SetEntProp(zm_client, Prop_Send, "m_iFOVStart", 0);
    SetEntPropFloat(zm_client, Prop_Send, "m_flFOVRate", 0.0);
    
    SetEntPropFloat(zm_client, Prop_Send, "m_staggerTimer", 0.0, 0);
    SetEntPropFloat(zm_client, Prop_Send, "m_stunTimer", 0.0, 0);
    
    SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0),
    SetEntProp(zm_client, Prop_Send, "m_nSolidType", 0),
    SetEntProp(zm_client, Prop_Send, "m_usSolidFlags", 0x0004);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageSphereInitialRadius", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageStartTime", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_TimeForceExternalView", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_staggerDist", 0.0); 
    SetEntPropVector(zm_client, Prop_Send, "m_scrimmageSphereCenter", {0.0,0.0,0.0});
    
    SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
    SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
    SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
    SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
    
    JoinZM(zm_client,0);
    
    TeleportEntity(zm_client, zm_deathPos, zm_deathAngles, NULL_VECTOR);
    recordpos = true;
    
    if (freeze)
    {
        SetEntityMoveType(zm_client, MOVETYPE_NONE);
        SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
        SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
        SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
        SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
        CreateTimer(0.5,Unfreeze_ZM,TIMER_FLAG_NO_MAPCHANGE);
    }
    
}

public Action L4D_OnTryOfferingTankBot(int tank_index, bool &enterStasis)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	if (DEBUG) LogMessage("[zm] L4D_OnTryOfferingTankBot %d %d", tank_index, enterStasis);
	return Plugin_Handled;
}

Action ZM_Chase_ZM(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM()  || zm_client!=client) return Plugin_Continue;
    if (panic) Chase(zm_client);
    else update_hint("%T", "Panic must be ON", zm_client);
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
       	int zombie = -1;
       	while ( (zombie=FindEntityByClassname(zombie,"infected"))!=-1 )
        {
    	   if (GetEntProp(zombie, Prop_Send, "m_mobRush")<=0)
    	   {
        	   SetEntProp(zombie, Prop_Send, "m_mobRush", 1);
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

Action CountCommons(Handle timer = null, bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_COMMON]>0 || !fast)
    {
        if (DEBUG) LogMessage("[zm] CountCommons expensive");
        live_zombie_arr[ZOMBIECLASS_COMMON] = L4D_GetCommonsCount();
    }
    return Plugin_Continue;
}


bool PlaySceneOnSurvivor(int survivor, const char[] sceneFile)
{
	int scene = CreateEntityByName("instanced_scripted_scene");
	if (!IsEntitySafe(scene)) return false;
	DispatchKeyValue(scene, "SceneFile", sceneFile);
	DispatchSpawn(scene);
	SetEntPropEnt(scene, Prop_Data, "m_hOwner", survivor);
	AcceptEntityInput(scene, "Start", survivor, survivor);
	HookSingleEntityOutput(scene, "OnCompletion", OnSceneComplete, true);
	CreateTimer(SCENE_SAFETY_TIMEOUT, Timer_KillScene, EntIndexToEntRef(scene));
	return true;
}

void OnSceneComplete(const char[] output, int caller, int activator, float delay)
{
	if (IsValidEntity(caller)) RemoveEntity(caller);
}

Action Timer_KillScene(Handle timer, int sceneRef)
{
	int scene = EntRefToEntIndex(sceneRef);
	if (scene != INVALID_ENT_REFERENCE && IsValidEntity(scene)) RemoveEntity(scene);
	return Plugin_Stop;
}

Action random_meme(Handle timer = null)
{
	if (!g_bMemes || meme_delivered || force_started) return Plugin_Stop;
	int i;
	ArrayList listplayers = new ArrayList();
	for (i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
		if (L4D_IsPlayerIncapacitated(i)) continue;
		listplayers.Push(i); 
	}
	if (listplayers.Length<=0)
	{
    	delete listplayers;
    	return Plugin_Stop;
	}
	
	int scene;
	ArrayList actors = new ArrayList();
	while ( ((scene = FindEntityByClassname(scene, "instanced_scripted_scene")) != -1) )
    {
    	   i = GetEntPropEnt(scene, Prop_Data, "m_hOwner");
    	   if (!IsValidClient(i)) continue;
    	   if (DEBUG) LogMessage("[zm] instanced_scripted_scene %d", i);
    	   actors.Push(i); 
    }
	
	listplayers.Sort(Sort_Random, Sort_Integer);
	static char model[PLATFORM_MAX_PATH];
    static char sound[PLATFORM_MAX_PATH];
    static char soundFake[PLATFORM_MAX_PATH];
    //char vcdPath[PLATFORM_MAX_PATH];
    static char PathFake[PLATFORM_MAX_PATH];
	for(int x = 0; x < listplayers.Length; x++)
    {
        i = listplayers.Get(x);
        if (actors.FindValue(i)>=0) continue;
        sound = "";
		GetClientModel(i, model, sizeof(model));
		if (StrContains(model,"survivor_mechanic",false)!=-1)
		{
    		//if (lipsync_available) sound = SOUND_ELLIS_ZM;
    		sound = SOUND_ELLIS_ZM_MP3;
    		//vcdPath = VCD_ELLIS_ZM;
    		soundFake = SOUND_ELLIS_ZM_FAKE;
    		PathFake = "scenes/mechanic/dlc1_communitye20.vcd";
		}
		else if (StrContains(model,"survivor_manager",false)!=-1)
		{
    		//if (lipsync_available) sound = SOUND_LOUIS_ZM;
            sound = SOUND_LOUIS_ZM_MP3;
    		//vcdPath = VCD_LOUIS_ZM;
    		soundFake = SOUND_LOUIS_ZM_FAKE;
    		PathFake = "scenes/manager/takesubmachinegun03.vcd";
		}
		if ( sound[0]!=0 && GetRandomFloat(0.0,1.0)>=0.5 ) 
		{
    		if (DEBUG) LogMessage("[zm] Playing %d %s", i, sound);
    		meme_delivered = true;
    		//EmitSoundToAll(sound,i,SNDCHAN_VOICE,SNDLEVEL_SCREAMING,_,1.0);
    		EmitSoundToAll(soundFake,i,SNDCHAN_VOICE,SNDLEVEL_RUSTLE,_,0.0);
    		EmitSoundToAll(sound,i,SNDCHAN_AUTO,SNDLEVEL_SCREAMING,_,1.0);
    		//if (lipsync_available) PlaySceneOnSurvivor(i, vcdPath);
    		PlaySceneOnSurvivor(i,PathFake);
    		break;
		}
	}
	delete listplayers;
	delete actors;
	return Plugin_Stop;
}

void start_zm_round(bool play_sound = true)
{
 if (zm_stage<ZM_STARTED)
 {
     PrintToChatAll("[zm] %t", "Round started");
     if (IsValidClientZM())
     {
         PrintHintText(zm_client, "%t", "Round started");
         freeze_player(zm_client,false,TEAM_INFECTED);
     }
     update_hint("%T", "Round started", zm_client);
     if (play_sound) EmitSoundToAll(SOUND_START);
     t_round_start = GetEngineTime();
     L4D2Direct_SetPendingMobCount(0);
     if (g_bMemes && !meme_delivered)
     {
         float delay = GetRandomFloat(1.0,10.0);
         CreateTimer(delay,random_meme,TIMER_FLAG_NO_MAPCHANGE);
     }
     infinite_delay_natural_mob();
     CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
     CountClients();
     update_EMS_HUD(true,0.0);
     if (shoot_alert_enable) ServerCommand("l4d2_shoot_alert_common_resetcvars");
 }
 zm_allow_spawns = true;
 set_zm_stage(ZM_STARTED);
 update_t_zm_activity();
 check_saferoom();
 saferoom_lock(false);
 if (IsValidEntRef(g_iLockedDoor))
 {
     if (GetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked")>0) AcceptEntityInput(g_iLockedDoor, "Unlock");
     AcceptEntityInput(g_iLockedDoor, "Open");
     SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
     AcceptEntityInput(g_iLockedDoor, "Open");
 }
 freeze_team(false,TEAM_INFECTED);
 saferoom_locked = false;
 create_other_menu();
 create_main_menu();
 //scope_changed = false;
 update_director_script_scopes(false);
 fair_exhausted = true;
 //scope_changed = false;
 set_force_start(false);
 
}

void update_ZM_looktarget_HP(int health_manual = -1)
{
  	 if (!active_looktarget || !IsValidEntRef(entref_control) || !IsValidClientZM())
  	 {
      	 active_looktarget = false;
      	 return;
  	 }
  	 int health;
  	 if ( health_manual==0 || L4D_IsPlayerIncapacitated(entref_control) || !IsPlayerAlive(EntRefToEntIndex(entref_control)) )
  	    health = 0;
  	 else health = GetEntProp(entref_control,Prop_Data,"m_iHealth");
     if (health>0)
     {
        int zClass = GetEntProp(entref_control, Prop_Send, "m_zombieClass");
        static char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        int max_health = GetEntProp(entref_control,Prop_Data,"m_iMaxHealth");
  	    update_hint("%T", "Selected Special", zm_client, zClassName, health, max_health);
  	    active_looktarget = true;
  	 }
  	 else update_hint("");
  	 
}

void update_entref_control(int new_entref, bool draw = false)
{
    if (!IsValidEntRef(new_entref)) return;
    int new_target = EntRefToEntIndex(new_entref);
    if (!IsValidClient(new_target)) return;
    int old_target = -1;
    if (IsValidEntRef(entref_control)) old_target = EntRefToEntIndex(entref_control);
    else if (active_looktarget)
    {
        entref_control = INVALID_ENT_REFERENCE;
        active_looktarget = false;
    }
    if (old_target==new_target && !draw) return;
    if (DEBUG) LogMessage("[zm] update_entref_control %d -> %d", old_target, new_target); 
    if (!IsValidClient(old_target)) old_target = -1;
    entref_control = INVALID_ENT_REFERENCE;
    entref_control = new_entref;
    if ( (new_target!=old_target || !active_looktarget) && draw)
    {
        active_looktarget = true;
        if (old_target>0 && new_target!=old_target) request_update_glow(old_target,true,0.0);
        request_update_glow(new_target,true,0.0);
    }
    
}

bool TraceFilter_Looktarget(int entity, int contentsMask)
{
	if (entity==zm_client || entity<=0) return false;
	if (IsValidClient(entity) && IsPlayerAlive(entity)) return true;
	static char class[32];
    GetEntityClassname(entity, class, sizeof(class));
    switch (class[0])
    {
        case 'i': { if (strcmp(class,"infected")==0) return true; }
        case 'w': { if (strcmp(class,"witch")==0) return true; }
    }
	return false;
}

void update_ZM_looktarget(bool draw = true)
{
   if (!IsValidClientZM())
   {
       entref_lastlook = INVALID_ENT_REFERENCE;
       return;
   }
   int target = GetClientAimTarget(zm_client, true);
   if (!IsValidClient(target) || target==zm_client)
   {
       float vAngles[3],vOrigin[3];
       GetClientEyePosition(zm_client,vOrigin);
       GetClientEyeAngles(zm_client,vAngles);
       Handle trace = TR_TraceRayFilterEx(vOrigin,vAngles,MASK_SHOT,RayType_Infinite,TraceFilter_Looktarget,_,TRACE_ENTITIES_ONLY);
       if(TR_DidHit(trace)) target = TR_GetEntityIndex(trace);
       delete trace;
   }
   if (target>=0 && EntIndexToEntRef(target)==entref_lastlook) return;
   entref_lastlook = INVALID_ENT_REFERENCE;
   if (!IsValidEntity(target) || target==zm_client) return;
   int health = GetEntProp(target,Prop_Data,"m_iHealth");
   if (health<=0) return;
   entref_lastlook = EntIndexToEntRef(target);
   static char class[32];
   GetEntityClassname(target, class, sizeof(class));
   if ( strcmp(class,"infected")==0 || strcmp(class,"witch")==0 || (strcmp(class,"player")==0 && GetClientTeam(target)==TEAM_INFECTED && IsFakeClient(target)) )
   {
  	 int entref_temp = EntIndexToEntRef(target);
  	 if (draw && entref_temp!=entref_delete)
  	 {
  	    float vOrigin[3];
  	    L4D_GetEntityWorldSpaceCenter(target,vOrigin);
      	TE_SetupBeamRingPoint(vOrigin,50.0,0.0,g_iLaser,g_iHalo,0,0,1.0,1.5,0.0,color_unit_select,0,0);
        TE_SendToClient(zm_client);
  	 }
  	 entref_delete = entref_temp;
  	 if (strcmp(class,"player")==0 && !L4D_IsPlayerIncapacitated(target)) update_entref_control(entref_temp,draw);
  	 
   
   }
   
}

int old_scope0, old_scope1, old_scope2, old_scope3, old_scope4;

void update_director_script_scopes(bool warn = true)
{
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    if (old_scope0!=scope0)
    {
        if (DEBUG && warn) LogMessage("[zm] DirectorScript scope changed! mob %d", pending_mob); 
        old_scope0 = scope0;
    }
    
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    if (old_scope1!=scope1)
    {
        if (DEBUG && warn) LogMessage("[zm] MapScript scope changed! mob %d", pending_mob); 
        old_scope1 = scope1;
    }
    
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    if (old_scope2!=scope2)
    {
        if (DEBUG && warn) LogMessage("[zm] LocalScript scope changed! mob %d", pending_mob); 
        old_scope2 = scope2;
        check_fog_distance();
        CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
    }
    
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    if (old_scope3!=scope3)
    {
        if (DEBUG && warn) LogMessage("[zm] ChallengeScript scope changed! mob", pending_mob); 
        old_scope3 = scope3;
    }
    
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    if (old_scope4!=scope4)
    {
        if (DEBUG && warn) LogMessage("[zm] DirectorOptions scope changed! mob %d", pending_mob); 
        old_scope4 = scope4;
        //scope_changed = true;
        //t_scope_change = GetEngineTime();
    }
     
}

float mob_timestamp;

// use zm_debug_mob to print these
bool panic_conditions(bool mob_just_spawned=false)
{
    if (zm_stage!=ZM_STARTED) return false;
    if (L4D_IsSurvivalMode() || ZM_finale_announced) return false;
    bool natural_mob = false;
    CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
    if (MobSpawnTimer)
    {
        float new_timestamp = CTimer_GetTimestamp(MobSpawnTimer);
        float mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
        float mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
        if (new_timestamp!=mob_timestamp)
        {
            mob_timestamp = new_timestamp;
            if (DEBUG) LogMessage("[zm] MobSpawnTimer jumped %.2f, %.2f", mob_timer_left, mob_timer_elapsed);
            if (mob_timer_left<=5.0 && mob_timer_left>=(-1.0) && mob_timer_elapsed<g_fPanicDuration)
                natural_mob=true;
        }
        
        if (natural_first_wait && L4D_HasAnySurvivorLeftSafeArea() && mob_timer_elapsed<g_fPanicDuration)
        {
            CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
            natural_first_wait = false;
            return false;
        }
        
        if (mob_timer_left>5.0) return false;
        if (mob_timer_elapsed>g_fPanicDuration) return false;
        
    }
    else return false;
    
    if ((GetEngineTime()-t_round_start)<=10.0) return false;
    if (panic && manual_panic) return false;
    if (script_CommonLimit<=0) return false;
    if (L4D2Direct_GetPendingMobCount()<=0 && !mob_just_spawned && !natural_mob) return false;
    return true;
}

void check_panic(bool mob_spawned = false)
{
    if (!L4D_IsSurvivalMode() && !ZM_finale_announced)
    {
        float t_now = GetEngineTime();
        if (panic_conditions(mob_spawned)) update_panic();
        else if (panic && (t_now-t_last_panic)>=g_fPanicDuration ) toggle_panic(false,true,true);
        else if (!panic)
        {
            CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
            if (MobSpawnTimer)
            {
                float elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
                if ( elapsed>1000.0 || (elapsed<100.0 && elapsed>g_fPanicDuration) )
                {
                    infinite_delay_natural_mob();
                    CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
                }
                
            }
        }
    }
}

// taking shitty navmeshes into account
bool client_in_start_area(int client)
{
    float pos[3];
    L4D_GetEntityWorldSpaceCenter(client,pos);
    // bools: anyz los checkground
    Address temp_navArea = L4D_GetNearestNavArea(pos,500.0,true,true,true,TEAM_SURVIVOR);
    if (navArea_validStart(temp_navArea)) return true;
    if (IsValidEntRef(g_iLockedDoor))
    {
        float safepos[3];
        L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,safepos);
        if (GetVectorDistance(pos,safepos)<=100.0) return true;
    }
    return false;
}

Action zm_freeze(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client || zm_stage<ZM_STARTED) return Plugin_Continue;
    set_specials_frozen(~ZM_specials_frozen);
    return Plugin_Continue;
}

void set_specials_frozen(bool state)
{
    if (!g_bAllowFreeze || max_SI<=0) state = false;
    if (ZM_specials_frozen!=state || specials_frozen!=state)
    {
        ZM_specials_frozen = state;
        freeze_team(state,TEAM_INFECTED);
        if (IsValidClientZM()) create_main_menu();
    }
}

Action zm_autocommon_mode(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (args>0)
    {
        static char type[32];
        GetCmdArg(1, type, sizeof(type));
        TrimString(type);
        if (strcmp(type,"always",false)==0) autocommon_setting = AUTOCOMMON_ALWAYS;
        else if (strcmp(type,"panic",false)==0) autocommon_setting = AUTOCOMMON_PANIC;
        else autocommon_setting = AUTOCOMMON_OFF;
        create_autocommon_menu();
    }
    else next_autocommon_setting();
    switch (autocommon_setting)
    {
        case AUTOCOMMON_ALWAYS: ReplyToCommand(client,"zm_autocommon_mode always");
        case AUTOCOMMON_PANIC: ReplyToCommand(client,"zm_autocommon_mode panic");
        default: ReplyToCommand(client,"zm_autocommon_mode off");
    }
    return Plugin_Continue;
}

Action zm_autocommon_max(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (args>0)
    {
        int new_num = GetCmdArgInt(1);
        if (new_num<1) return Plugin_Continue;
        if (new_num>max_zombie_arr[ZOMBIECLASS_COMMON]) new_num = max_zombie_arr[ZOMBIECLASS_COMMON];
        if (autocommon_num!=new_num)
        {
            autocommon_num = new_num;
            create_autocommon_menu();
        }
   	}
   	else next_autocommon_num();
   	ReplyToCommand(client,"zm_autocommon_max %d", autocommon_num);
   	return Plugin_Continue;
}

Action zm_update(Handle timer = null)
{
   
   if (!g_bCvarAllow || zm_stage>=ZM_END)
   {
      if (zm_timer && timer==zm_timer) zm_timer = INVALID_HANDLE;
      if (IsValidClientZM()) QuitZM_Force(zm_client);
      return Plugin_Stop;
   }
   
   if (DEBUG) LogMessage("[zm] zm_update %d %d", zm_timer, timer);
   
   if (L4D_HasMapStarted())
   {
       CountCommons();
       if (g_bLockSaferoom && L4D_IsInIntro()>0) freeze_team(true);
       check_panic();
   }
   
   float t_now = GetEngineTime();
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
           		if (!IsClientInGame(i)) continue;
           		if (!IsPlayerAlive(i)) continue;
           	    if (GetClientTeam(i)!=TEAM_INFECTED || !IsFakeClient(i)) continue;
           		if (GetEntProp(i, Prop_Send, "m_hasVisibleThreats")>0)
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
    static char targetName[20];
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
              if (can_any_alive_survivor_see(witch_pos,false))
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
        if (player_diff>0 || zm_stage<ZM_STARTED)
        {
            if (L4D_IsSurvivalMode()) bank += g_iBonusSurvival*player_diff;
            else if (ZM_finale_announced) bank += g_iBonusFinaleStage*player_diff;
            else bank += g_iBankInitialPlayer*player_diff;
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
      
      // Draw spawner visuals for ZM
      if (zm_menu_state>ZM_MENU_CLOSED && (t_now-t_last_spawner_update)>=g_fUpdateRate) can_ZM_spawn(false,false);
      
   }
   else
   {
      if (!IsValidClient(client_offer) && fq_timer==INVALID_HANDLE) fq_timer = CreateTimer(1.0,fair_queue_update);
      if (!IsValidClientZM() && zm_client_userid!=-1)
      {
          zm_client = GetClientOfUserId(zm_client_userid);
          if (IsValidClientZM()) return Plugin_Continue;
      }
      
      if ((t_now-t_zm_activity)>=10.0)
      {
         if (zm_stage<ZM_END && L4D_IsInIntro()<=0 && (fair_exhausted || zm_stage==ZM_STARTED ))
             PrintToChatAll("[zm] %t", "No ZM");
         update_t_zm_activity(t_now);
      }
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
   if (timer && timer!=zm_timer) return Plugin_Stop; // prevent repeating timer from doubling
   return Plugin_Continue;
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{

	if(GetEngineVersion()!=Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	RegPluginLibrary("l4d2_zombie_master");

	return APLRes_Success;
}


public void OnAllPluginsLoaded()
{
	// l4d_infectedbots by HarryPotter https://github.com/fbef0102/L4D1_2-Plugins
	infectedbots_enable = FindConVar("l4d_infectedbots_allow");
	if (infectedbots_enable) SetConVarFlags(infectedbots_enable, GetConVarFlags(infectedbots_enable) & ~FCVAR_NOTIFY);
	jukebox_horde = FindConVar("l4d2_jukebox_horde_trigger");
	if (jukebox_horde) SetConVarFlags(jukebox_horde, GetConVarFlags(jukebox_horde) & ~FCVAR_NOTIFY);
	shoot_alert_enable = FindConVar("l4d2_shoot_alert_common_enable");
	if (shoot_alert_enable) SetConVarFlags(shoot_alert_enable, GetConVarFlags(shoot_alert_enable) & ~FCVAR_NOTIFY);
	SetCvarsZM();
}


Action zm_debug_player(int client, int args)
{   
    DumpPlayerState(client,client);
    return Plugin_Continue;
}

Action zm_debug_mob(int client, int args)
{   
    bool finale_active = L4D_IsFinaleActive();
    int pending_mob = L4D2Direct_GetPendingMobCount();
   	float mob_timer_left = -1.0;
   	float mob_timer_elapsed = -1.0;
   	CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
   	if (MobSpawnTimer)
   	{
       mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
       mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
    }
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    
    CountCommons(null,false);
    int commons = live_zombie_arr[ZOMBIECLASS_COMMON];
    int panic_forever = FindConVar("director_panic_forever").IntValue;

    PrintToChat(client, "commons %d panic forever %d pending_mob %d finale_active %d CommonLimit %d",
                commons, panic_forever, pending_mob, finale_active, script_CommonLimit);
    PrintToChat(client, "MobTimer Remaining Elapsed %.2f %.2f", mob_timer_left, mob_timer_elapsed);
    PrintToChat(client, "DirectorScriptScope %d %d %d %d %d", scope0, scope1, scope2, scope3, scope4);
    return Plugin_Continue;
}

int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_VoteEnd)
    {
        if (param1 == 0)
        {
            if (g_bCvarAllow) SetConVarInt(g_hCvarAllow,0);
            else SetConVarInt(g_hCvarAllow,1);
        }
    }
    return 0;
}
 
void DoVoteMenu()
{
    if (IsVoteInProgress()) return;
    EmitSoundToAll(SOUND_READY);
    Menu menu = new Menu(Handle_VoteMenu);
    if (g_bCvarAllow) menu.SetTitle("Zombie Master -> OFF?");
    else menu.SetTitle("Zombie Master -> ON?");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}
 
Action VoteZM(int client, int args)
{
        
    if (L4D_HasPlayerControlledZombies())
    {
        PrintToChat(client, "[zm] %t", "ZM restrict notify");
        return Plugin_Stop;
    }
    
    if (IsVoteInProgress()) return Plugin_Stop;
    
    DoVoteMenu();
    return Plugin_Continue;
	
}


Action ZM_MOTD(int client, int args)
{ 
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Continue;

    PrintToChat(client, "[zm] See console.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== ZOMBIE MASTER %s TUTORIAL ===", PLUGIN_VERSION);
    PrintToConsole(client, "Welcome to Left 4 Dead 2 Zombie Master!");
    PrintToConsole(client, "Visit the Steam Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3660216145");
    PrintToConsole(client, "Before every round starts, one player, the Zombie Master, is selected to control all zombies.");
    PrintToConsole(client, "IMPORTANT: Please enable Freelook Camera in Options -> Multiplayer!!!");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 1. Spawning Zombies ===");
    PrintToConsole(client, "Zombies can be spawned with the sourcemod menu, or with chat/console commands (Section 3).");
    PrintToConsole(client, "A spawner (3 circles) shows where you are pointing (or the nearest valid location). This is where zombies will spawn.");
    PrintToConsole(client, "The spawner can be in 1 of 4 states:");
    PrintToConsole(client, "1. GREEN -> Zombies can be spawned NOW!");
    PrintToConsole(client, "2. BLUE -> Zombies can be spawned, but not now because survivors are too close or they can see.");
    PrintToConsole(client, "3. RED -> Zombies can NEVER be spawned here.");
    PrintToConsole(client, "4. FLOW (long vertical blue stripe) -> Zombie locations were picked automatically.");
    PrintToConsole(client, "To activate FLOW: look at a survivor OR the ground next to them OR spectate that survivor; then, spawn zombies.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 2. Keyboard Shortcuts ===");
    PrintToConsole(client, "USE (default E) -> Control/Release Special Infected.");
    PrintToConsole(client, "FLASHLIGHT (default F) -> Flashlight.");
    PrintToConsole(client, "RELOAD (default R) -> once to open main menu, twice to close menu completely and hide spawner.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 3. Chat/Console Commands ===");
    PrintToConsole(client, "/zm_vote -> Vote to enable/disable Zombie Master.");
    PrintToConsole(client, "/zm_gamemode_menu -> Gamemode menu for clients and admins.");
    PrintToConsole(client, "/zm -> become ZM OR open menu and enter free look.");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_horde n type angry flow");
    PrintToConsole(client, "optional type: riot ceda clown mud road random");
    PrintToConsole(client, "optional angry: chase survivors on spawn even if PANIC is OFF. More expensive than non-angry variant.");
    PrintToConsole(client, "optional flow: spawn in a random place ahead of furthest survivor instead of spawner position.");
    PrintToConsole(client, "The order of arguments doesn't matter. For example, zm_horde '50 angry clown' and zm_horde 'clown angry 50' gives the same result.");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_witch n flow");
    PrintToConsole(client, "n=0 static, n=1 moving");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_boomer flow");
    PrintToConsole(client, "/zm_spitter flow");
    PrintToConsole(client, "/zm_smoker flow");
    PrintToConsole(client, "/zm_hunter flow");
    PrintToConsole(client, "/zm_jockey flow");
    PrintToConsole(client, "/zm_charger flow");
    PrintToConsole(client, "/zm_tank flow");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_panic -> Start PANIC");
    PrintToConsole(client, "/zm_start -> (1x) Unlock saferoom (2x) Force saferoom open (3x) Instantly open saferoom.");
    PrintToConsole(client, "/zm_delete -> Delete single unit where you are pointing indicated by a white circle.");
    PrintToConsole(client, "/zm_delete_all -> delete ALL zombies");
    PrintToConsole(client, "/zm_delete_common -> delete all commons/uncommons");
    PrintToConsole(client, "/zm_delete_specials -> delete all Special Infected");
    PrintToConsole(client, "/zm_delete_witches");
    PrintToConsole(client, "/zm_quit -> Give Up and join Survivors.");
    PrintToConsole(client, "/zm_teleport -> teleport to survivor with most progress.");
    PrintToConsole(client, "/zm_menu x -> main common uncommon special boss cleanup other close");
    PrintToConsole(client, "/zm_freeze -> Freeze/Unfreeze Special Infected units. Useful for setting up ambushes.");
    PrintToConsole(client, "/zm_autocommon_mode x -> off panic always. Sets AutoCommon system mode.");
    PrintToConsole(client, "/zm_autocommon_max n -> Set zombie cap for AutoCommon system.");
    PrintToConsole(client, "");
    PrintToConsole(client, "You can bind all of the commands above! For example: bind KP_MINUS 'zm_horde 10 flow'");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 4. Gameplay Tips ===");
    PrintToConsole(client, "1. Go to Common -> AutoCommon. Set mode to ALWAYS, and max to 30. This will spawn common zombies ahead of the Survivors automatically.");
    PrintToConsole(client, "2. Use Freeze SI/Unfreeze SI to set up ambushes. All Specials unfreeze automatically when one notices a Survivor. Press the USE key to fine-tune placement and view angle.");
    PrintToConsole(client, "3. In coop, you get %d seconds of prep time. Specials will be frozen. To end prep, type /zm_start or go to Other -> Start Round.", RoundFloat(g_fPrepTimeZM));
    PrintToConsole(client, "4. PANIC will make common and uncommon infected chase survivors, reducing your bank rate by 4x. Finales, survival, and scripted panic events give free PANIC.");
    PrintToConsole(client, "5. When a Boomer vomits on a survivor, %d free zombies will be spawned. Use this to your advantage!", g_iVomitCommons);
    PrintToConsole(client, "6. Car alarms give free PANIC, free common zombies, and free bank. Trick the survivors into starting them!");
    PrintToConsole(client, "7. During Survival and Finales, bank is added in stages: in Survival when Tanks die, in Finales when you run out of bank.");
    PrintToConsole(client, "7. In coop, when Tanks are not banned, the first Tank gets progressively cheaper: up to 50% off when Survivors progress 2/3 of the map.");
    PrintToConsole(client, "8. Units with full HP can be deleted to get a refund. You cannot refund: spotted witches, Specials that used their ability.");
    
    if (CheckCommandAccess(client,"is_a_sm_admin",ADMFLAG_GENERIC,true))
    {
        PrintToConsole(client, "");
        PrintToConsole(client, "=== 5. Admin commands ===");
        PrintToConsole(client, "/zm_addbank");
        PrintToConsole(client, "/zm_kick");
        PrintToConsole(client, "");
        PrintToConsole(client, "=== 6. CVARS ===");
        PrintToConsole(client, "Compatible mp_gamemode: coop l4d1coop survival l4d1survival.");
        PrintToConsole(client, "sm_cvar zm_gamemode sets the .cfg file that is read in cfg/sourcemod/l4d2_zombie_master/.");
        
        static char name[64];
        static char value[64];
        bool isCommand;
        int flags;
        ConVar cvar;
        Handle iter = FindFirstConCommand(name,sizeof(name),isCommand,flags);
        if (iter != null)
        {
            do
            {
                if (!isCommand && StrContains(name,"zm_",false)==0)
                {
                    cvar = FindConVar(name);
                    cvar.GetString(value, sizeof(value));
                    PrintToConsole(client, "%s %s", name, value);  
                }
            }
            while (FindNextConCommand(iter,name,sizeof(name),isCommand,flags));
        }
        CloseHandle(iter);
    }
    
    PrintToConsole(client, "");
    PrintToConsole(client, "For more information, and to install Zombie Master for your own server, go here:");
    PrintToConsole(client, "https://forums.alliedmods.net/showthread.php?t=352060");
    PrintToConsole(client, "https://github.com/gvazdas/l4d2_zombie_master");
    PrintToConsole(client, "Visit the Steam Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3660216145");
    PrintToConsole(client, "=== ZOMBIE MASTER TUTORIAL END ===");
    PrintToConsole(client, "");
   
    return Plugin_Continue;
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	static char sGameMode[32];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	if(strcmp(g_sCvarMPGameMode, sGameMode, false) == 0) return;
	g_sCvarMPGameMode = sGameMode;
    
    if (DEBUG) LogMessage("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
    l4d2_specials = true;
    if (strcmp(g_sCvarMPGameMode,"l4d1coop")==0 || strcmp(g_sCvarMPGameMode,"l4d1survival")==0)
        l4d2_specials = false;
    
	IsAllowed();
}

void load_zm_gamemode()
{
    g_hZMGamemode.GetString(g_sZMGamemode, sizeof(g_sZMGamemode));
    TrimString(g_sZMGamemode);
    if (g_sZMGamemode[0]==0) g_sZMGamemode = "zm_default";
    else if (strcmp(g_sZMGamemode,"random",false)==0)
    {
        random_gamemode();
        return;
    }
    static char command[PLATFORM_MAX_PATH];
    Format(command, sizeof(command), "exec sourcemod/l4d2_zombie_master/%s", g_sZMGamemode);
    ServerCommand(command);
}

void ConVarChanged_Cvars_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue)
{
    load_zm_gamemode();
    on_changed_rules();
    create_menu_gamemode();
}

void ConVarChanged_Cvars_ZMenu(ConVar convar, const char[] oldValue, const char[] newValue)
{
    on_changed_rules();
}

void on_changed_rules()
{
   GetCvars();
   SetCvarsZM();
   if (g_bCvarAllow && IsValidClientZM())
   {
      update_menus();
      update_EMS_HUD(true,0.0);
   }
}

void ConVarChanged_Allow(ConVar convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void GetCvars()
{

    if (DEBUG) LogMessage("[zm] GetCvars");
    g_fUpdateRate = g_hUpdateRate.FloatValue;
    ResetTimer();

    DEBUG = g_hCvarDebug.BoolValue || DEBUG;

    g_fBankRateBase = g_hBankRateBase.FloatValue;
    g_fBankRatePlayer = g_hBankRatePlayer.FloatValue;
    g_iBankInitial = g_hBankInitial.IntValue;
    g_iBankInitialPlayer = g_hBankInitialPlayer.IntValue;
    max_zombie_arr[ZOMBIECLASS_COMMON] = g_hMaxCommons.IntValue;
    g_fSpawnMinDistance = g_hSpawnMinDistance.FloatValue;
    g_fGridSearchRadius = g_hGridSearchRadius.FloatValue;
    g_fStopInactivity = g_hStopInactivity.FloatValue;

    costs_SI[ZOMBIECLASS_BOOMER] = g_hCostBoomer.IntValue;
    costs_SI[ZOMBIECLASS_SPITTER] = g_hCostSpitter.IntValue;
    costs_SI[ZOMBIECLASS_HUNTER] = g_hCostHunter.IntValue;
    costs_SI[ZOMBIECLASS_SMOKER] = g_hCostSmoker.IntValue;
    costs_SI[ZOMBIECLASS_JOCKEY] = g_hCostJockey.IntValue;
    costs_SI[ZOMBIECLASS_CHARGER] = g_hCostCharger.IntValue;
    costs_SI[ZOMBIECLASS_TANK] = g_hCostTank.IntValue;
    g_iCostWitchStatic = g_hCostWitchStatic.IntValue;
    g_iCostWitchMoving = g_hCostWitchMoving.IntValue;
    g_iCostCommon = g_hCostCommon.IntValue;
    g_iCostUncommon = g_hCostUncommon.IntValue;
    g_iMaxWitches = g_hMaxWitches.IntValue;
    g_iMaxSI = g_hMaxSI.IntValue;
    g_iMaxUniqueSI = g_hMaxUniqueSI.IntValue;

    g_iBonusCarAlarm = g_hBonusCarAlarm.IntValue;
    g_iBonusFinaleStage = g_hBonusFinaleStage.IntValue;
    g_iBonusSurvival = g_hBonusSurvival.IntValue;

    g_iPanicCost = g_hPanicCost.IntValue;
    g_fPanicDuration = g_hPanicDuration.FloatValue;

    g_bLockSaferoom = g_hLockSaferoom.BoolValue;

    g_fPrepTimeZM = g_hPrepTimeZM.FloatValue;

    g_fSpecialCooldown = g_hSpecialCooldown.FloatValue;
    g_fTankCooldown = g_hTankCooldown.FloatValue;
    g_fWitchCooldown = g_hWitchCooldown.FloatValue;
    g_fCommonRate = g_hCommonRate.FloatValue;

    g_fMinFinaleStage = g_hMinFinaleStage.FloatValue;

    g_bFairQueue = g_hFairQueue.BoolValue;
    if (!g_bFairQueue) fair_exhausted = true;
    g_fFairQueueWait = g_hFairQueueWait.FloatValue;
    g_fMenuTimeout = g_hMenuTimeout.FloatValue;

    g_bDiscountTank = g_hDiscountTank.BoolValue;
    g_bMemes = g_hMemes.BoolValue;
    g_bClownGlow = g_hClownGlow.BoolValue;

    g_hForceCommon.GetString(g_sForceCommon, sizeof(g_sForceCommon));
    TrimString(g_sForceCommon);

    holdfinale = g_hHoldFinale.BoolValue;

    g_iVomitCommons = g_hVomitCommons.IntValue;

    g_bAllowFreeze = g_hAllowFreeze.BoolValue;
    if (!g_bAllowFreeze) ZM_specials_frozen = false;

    if (g_iCostUncommon<0) autocommon_uncommons = false;
    else if (g_iCostCommon<0) autocommon_uncommons = true;
    if (autocommon_num>g_hMaxCommons.IntValue) autocommon_num = g_hMaxCommons.IntValue;

    g_fPanicRateMultiplier = g_hPanicRateMultiplier.FloatValue;

}

void zm_fake_gamemode()
{
    if (L4D_IsSurvivalMode()) FindConVar("mp_gamemode").ReplicateToClient(zm_client,"mutation15");
    else FindConVar("mp_gamemode").ReplicateToClient(zm_client,"versus");
}

Action JoinZM_command(int client, int args)
{
    if (!IsValidClient(client)) return Plugin_Continue;
    first_active = true;
    clients_active[client] = true;
    if (!g_bCvarAllow) VoteZM(client,0);
    if (IsValidClientZM() && client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
    JoinZM(client,args);
    return Plugin_Continue;
}

Action JoinZM(int client, int args)
{
	if (!g_bCvarAllow || !IsValidClient(client) || args>1) return Plugin_Continue;
	if (zm_stage>=ZM_END) return Plugin_Continue;
	if (client<0 || IsFakeClient(client)) return Plugin_Continue;
	if (DEBUG) LogMessage("[zm] JoinZM");
	if (IsValidClientZM())
	{
       if (client==zm_client)
       {
          if (GetClientTeam(zm_client)!=TEAM_ZM)
          {
              ChangeClientTeam(zm_client,TEAM_ZM);
              L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
          }
          if (!IsPlayerAlive(zm_client))
          {
              SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6); //thanks to EHG https://forums.alliedmods.net/showthread.php?p=1080991
              SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
              L4D2_RemoveEntityGlow(zm_client);
              L4D2_SetPlayerSurvivorGlowState(zm_client,false);
          }
          if (zm_menu_state==ZM_MENU_CLOSED) open_menu(zm_client);
       }
       else PrintHintText(client,"%t", "ZM taken");
       return Plugin_Continue;
    }
    
    // Allow players who played less to skip ahead of offer line
    if (g_bFairQueue && zm_stage<ZM_STARTED && !fair_exhausted && client!=client_offer)
    {
  		zm_data cell;
  		if (!get_zm_data(cell,client)) return Plugin_Continue;
  		int roundcount_client = cell.last_roundcount;
  		if (roundcount_client>=roundcount_offer)
  		{
      		if (IsValidClient(client_offer))
      		{
          		static char name[MAX_NAME_LENGTH]; 
                GetClientName(client_offer,name,sizeof(name));
                int timeleft = RoundFloat(g_fFairQueueWait - (GetEngineTime() - t_offer));
                if (timeleft<0) timeleft = 0;
           		PrintToChat(client, "[zm] %T", "Offered ZM Ticker", client, name, timeleft); 
      		}
      		return Plugin_Continue;
  		}
    }
    
    if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client))
    {
        L4D_TakeOverBot(client);
    }
    
    remove_all_ZM_glows();
    
    ChangeClientTeam(client,TEAM_ZM);
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    //autocommon_setting = AUTOCOMMON_OFF;
    //autocommon_uncommons = false;
    if (!g_bAllowFreeze) ZM_specials_frozen = false;
    zm_client = client;
    zm_client_userid = GetClientUserId(zm_client);
    
    update_menus();
    
    // Prevent InputKill - thanks Shadowsyn
   	//SetVariantString("self.ValidateScriptScope()");
   	//AcceptEntityInput(client, "RunScriptCode");
  	//SetVariantString("plugin_shouldKill <- false;");
  	//AcceptEntityInput(client, "RunScriptCode");
  	//SetVariantString("function InputKill() {return plugin_shouldKill}");
   	//AcceptEntityInput(client, "RunScriptCode");
    
    static char name[MAX_NAME_LENGTH]; 
    GetClientName(client,name,sizeof(name));
    int playcount = get_rounds(client);
    PrintToChatAll("[zm] %t (%d)", "ZM joined", name, playcount);
    zm_use_notify = playcount>0;
    zm_flow_notify = playcount>0;
    DispatchKeyValue(zm_client, "targetname", "zm_client");
    SetEntProp(client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    PrintHintText(client, "%t", "ZM join hint");
    L4D2_RemoveEntityGlow(zm_client);
    L4D2_SetPlayerSurvivorGlowState(zm_client,false);
    zm_fake_gamemode();
    ems_hud_timer = INVALID_HANDLE;
    update_hint("%T", "zm_menu_hint", zm_client);
    if (playcount<=0) PrintToChat(client, "[zm] Enable Spectating Free Look in Options -> Multiplayer!!!");
    if (strcmp(g_sZMGamemode,"zm_default")!=0) PrintToChat(client, "[zm] Gamemode: %s", g_sZMGamemode);
    if (panic_target==zm_client) panic_target = -1;
    update_t_zm_activity();
    if (t_zm_join==0.0) t_zm_join = t_zm_activity;
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
    pass_ZM(client);
    if (zm_timer == INVALID_HANDLE) zm_update();
    open_menu(zm_client);
    recordpos = true;
    
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_VISION);
    
    if (zm_stage<ZM_PREP) set_bank_begin();
    
    ZMTeleport(zm_client,0);
    L4D_CleanupPlayerState(client);
    SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
    
    // Make end saferoom door glow, and close it.
    if (!L4D_IsSurvivalMode())
    {
        lastdoor = L4D_GetCheckpointLast();
        if (IsValidEntity(lastdoor))
        {
            if (zm_stage<ZM_PREP) AcceptEntityInput(lastdoor, "Close");
            CreateTimer(g_fUpdateRate, CreateZMGlow_red, EntIndexToEntRef(lastdoor), TIMER_FLAG_NO_MAPCHANGE);
        }
        else lastdoor = -1;
    }

    set_zm_stage(ZM_PREP);

    return Plugin_Continue;
}

void QuitZM_Force(int client)
{
    if (!IsValidClient(client)) return;
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    QuitZM(client,false);
}

void QuitZM(int client, bool print = true)
{
	if (DEBUG) LogMessage("[zm] QuitZM");
	if (!g_bCvarAllow || client<=0 || !IsClientInGame(client) || IsFakeClient(client)) return;
	
	if (client==zm_client)
	{
	   if (IsValidClientZM())
	   {
	       FindConVar("mp_gamemode").ReplicateToClient(zm_client,g_sCvarMPGameMode);
           if (print)
           {
               static char name[MAX_NAME_LENGTH]; 
               GetClientName(client,name,sizeof(name));
               PrintToChatAll("[zm] %t", "ZM quit", name);
               update_t_zm_activity();
           }
           
           if (panic_target==zm_client) panic_target = -1;
           
           if (zm_stage<ZM_STARTED)
           {
               zm_can_start = false;
               set_zm_stage(ZM_PREP,true);
           }
           
           if (zm_menu_state!=ZM_MENU_CLOSED) close_menus(zm_client);
           
           if (IsPlayerAlive(zm_client))
           {
               ZMControlSI(zm_client,0);
               RequestFrame(QuitZM_Force,client);
               return;
           }
           DispatchKeyValue(zm_client, "targetname", "client");
       }
       remove_all_ZM_glows();
       zm_client = -1;
       zm_client_userid = -1;
       zm_menu_state = ZM_MENU_CLOSED;
       fair_queue_update(null);
    }
    
    if (IsValidClient(client) && GetClientTeam(client)!=TEAM_SURVIVOR)
    {
            // Find bot that can be taken over. Credit: l4dmultislots by HarryPotter
            int bot = -1;
            for (int i = 1; i <= MaxClients; i++)
        	{
        		if (!IsClientInGame(i)) continue;
        		if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        		if (!IsPlayerAlive(i)) continue;
        		if (!IsFakeClient(i)) continue;
        		if (HasEntProp(i,Prop_Send,"m_humanSpectatorUserID"))
        		{
            		if (GetEntProp(i, Prop_Send, "m_humanSpectatorUserID")>0) continue;
        		}
        		if (L4D_IsPlayerIncapacitated(i)) continue;
        		bot = i;
        		break;
            }
            ChangeClientTeam(client,TEAM_SURVIVOR);
   			if(bot > 0)
   			{
   				L4D_SetHumanSpec(bot,client);
   				L4D_TakeOverBot(client);
   			}
   			L4D_CleanupPlayerState(client);
    }

}

Action QuitZM_Command(int client, int args)
{
  if (!g_bCvarAllow) return Plugin_Continue;
  QuitZM(client,true);
  return Plugin_Continue;
}

Action ZM_Vision(int client, int args)
{
   toggle_ZM_vision(client);
   return Plugin_Continue;
}

int entref_light = INVALID_ENT_REFERENCE;
Action TransmitZMLight(int entity, int client)
{
	if (!IsValidClientZM()) AcceptEntityInput(entity, "Kill");
	if(client==zm_client) return Plugin_Continue;
	return Plugin_Handled;
}

// Update z position of ZM light if they are in free look vs spectating a target or alive.
void update_zm_flashlight()
{
    if (!IsValidEntRef(entref_light)) return;
    int entity = EntRefToEntIndex(entref_light);
    if (!IsValidEntity(entity)) return;
    if (!IsValidClientZM()) return;
    int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode");
    int lastlook = -1;
    if (observermode==4 || observermode==5)
        lastlook = GetEntPropEnt(zm_client, Prop_Send, "m_hObserverTarget");
    if (lastlook>0 && IsValidEntity(lastlook))
    {
        // Prevent flicker
        AcceptEntityInput(entity, "Kill");
    	entref_light = INVALID_ENT_REFERENCE;
    }
    else
    {
        if (IsPlayerAlive(zm_client))
        {
            float vMin[3], vMax[3], vOffset[3];
            GetEntPropVector(zm_client, Prop_Send, "m_vecMins", vMin);
            GetEntPropVector(zm_client, Prop_Send, "m_vecMaxs", vMax);
            vOffset[2] = vMax[2] - vMin[2] + 1.0;
            TeleportEntity(entity,
                           vOffset,
                           view_as<float>({ -45.0, -45.0, 90.0 }),
                           NULL_VECTOR);
        }
        else
        {
            TeleportEntity(entity,
                           view_as<float>({ 0.0, 0.0, 0.0 }),
                           view_as<float>({ 0.0, 0.0, 0.0 }),
                           NULL_VECTOR);
        }
    }
    
}

// l4d_flashlight by Silvers
void toggle_ZM_vision(int client)
{
    if (!g_bCvarAllow || !IsValidClient(client)) return;
    if (client!=zm_client) return;
    
    if (is_zm_spamming()) return;
    
    int entity;
    if (IsValidEntRef(entref_light)) entity = EntRefToEntIndex(entref_light);
    else entity = -1;
    
    if (!IsValidEntity(entity))
    {
        
        // No dynamic light when observing somebody. Prevents flicker.
        int observermode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if (observermode==4 || observermode==5) return;
        
        entity = CreateEntityByName("light_dynamic");
    	if( entity == -1) return;
        
       	DispatchKeyValue(entity, "_light", "5 5 5 5");
       	DispatchKeyValue(entity, "brightness", "1");
       	DispatchKeyValueFloat(entity, "spotlight_radius", 0.0);
       	DispatchKeyValueFloat(entity, "distance", 3000.0);
       	DispatchKeyValue(entity, "style", "0");
       	DispatchSpawn(entity);
       	AcceptEntityInput(entity, "TurnOn");
       	SetVariantString("!activator");
       	AcceptEntityInput(entity, "SetParent", client);
       	TeleportEntity(entity,
                       view_as<float>({ 0.0, 0.0, 0.0 }),
                       view_as<float>({ 0.0, 0.0, 0.0 }),
                       NULL_VECTOR);
		entref_light = EntIndexToEntRef(entity);
		SDKHook(entity, SDKHook_SetTransmit, TransmitZMLight);
		update_zm_flashlight();
    }
	else
	{
    	AcceptEntityInput(entity, "Kill");
    	entref_light = INVALID_ENT_REFERENCE;
	}
	
    EmitSoundToClient(client,SOUND_VISION);
}

Action zm_finale_advance(int client, int args)
{
  if (DEBUG) LogMessage("[zm] zm_finale_advance");
  if (L4D_IsFinaleActive()) L4D2_ForceNextStage();
  else PrintToChat(client, "[zm] Finale is not active"); 
  return Plugin_Continue;
}

Action zm_addbank(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] zm_addbank");
    if (args>0)
    {
        int add = GetCmdArgInt(1);
        bank += add;
        if (add!=0 && IsValidClientZM()) update_EMS_HUD();
    }
    return Plugin_Continue;
}

Action zm_kick(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (!IsValidClientZM()) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] zm_kick");
    QuitZM(zm_client,false);
    return Plugin_Continue;
}


bool can_discount_tank()
{
    if (!g_bDiscountTank) return false;
    if (max_zombie_arr[ZOMBIECLASS_TANK]<=0 || costs_SI[ZOMBIECLASS_TANK]<0) return false;
    if (zm_stage!=ZM_STARTED) return false;
    if (first_tank_stage>0) return false;
    if ( ZM_finale_announced || L4D_IsSurvivalMode() ) return false;
    if (L4D_IsMissionFinalMap() && !IsValidEntity(lastdoor)) return false;
    int ProhibitBosses = L4D2_GetScriptValueInt("ProhibitBosses", 0);
    if (ProhibitBosses>0) return false;
    int DisallowThreatType = L4D2_GetScriptValueInt("DisallowThreatType", 0);
    if (DisallowThreatType==ZOMBIECLASS_TANK) return false;
    return true;  
}

float get_survivor_flow_fraction(int client)
{
    if (!IsValidClient(client)) return -1.0;
    if (!IsPlayerAlive(client)) return -1.0;
    float max_flow = L4D2Direct_GetMapMaxFlowDistance();
    if (max_flow<=0.0) return -1.0;
    float flow = L4D2Direct_GetFlowDistance(client);
    if (flow<0.0) flow = 0.0;
    return flow/max_flow;
}

void update_dynamic_tank()
{
    int new_cost = g_hCostTank.IntValue;
    if (can_discount_tank())
    {
        int target = L4D_GetHighestFlowSurvivor();
        float fraction = get_survivor_flow_fraction(target);
        if (fraction>=0.0)
        {
            // For >=60.0% flow, give 50% discount.
            if (fraction>0.6)
            {
                fraction = 0.6;
                if (!zm_discount_notify)
                {
                    zm_discount_notify = true;
                    update_hint("%T", "Max tank discount", zm_client);
                    if (IsValidClientZM())
                    {
                        PrintHintText(zm_client, "%t", "Max tank discount"); 
                        EmitSoundToClient(zm_client,SOUND_REWARD);
                    }
                }
            }
            new_cost = RoundToCeil( (1.0-0.5*fraction/0.6)*g_hCostTank.IntValue);
            
            // Prevent Tank from getting more expensive if Survivor is walking back.
            if (new_cost>costs_SI[ZOMBIECLASS_TANK])
                new_cost = costs_SI[ZOMBIECLASS_TANK];
        }
        
    }
    
    if (new_cost!=costs_SI[ZOMBIECLASS_TANK])
    {
        costs_SI[ZOMBIECLASS_TANK] = new_cost;
        create_boss_menu();
    }
}

stock void request_crouch(int entref)
{
    if (!IsValidEntRef(entref)) return;
    SetEntProp(entref, Prop_Send, "m_bDucked", 1);
    SetEntProp(entref, Prop_Send, "m_fFlags", GetEntProp(entref, Prop_Send, "m_fFlags") | FL_DUCKING);
}

Action saferoom_disturb(Handle timer, float vPos[3])
{
    if (!IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED) return Plugin_Stop;
    int random = GetRandomInt(1,3);
    static char sound[64];
    switch (random)
    {
        case 1: {sound=SOUND_DOORSLAM;}
        case 2: {sound=SOUND_DOORSLAM2;}
        case 3: {sound=SOUND_DOORSLAM3;}
        default: {sound=SOUND_DOORSLAM;}
    }
    EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL,GetRandomInt(70,130));
    CreateShake(2.0,1000.0,vPos);
    
    return Plugin_Stop;
}

// Full credit to Silvers
int entref_shake = INVALID_ENT_REFERENCE;
void CreateShake(float intensity, float range, float vPos[3])
{
	if( !g_bMapStarted ) return;
    
    static char sTemp[8];
    
    if (!IsValidEntRef(entref_shake))
    {
    	int entity = CreateEntityByName("env_shake");
    	if( entity == -1 )
    	{
    		LogMessage("[zm] Failed to create env_shake");
    		return;
    	}
    	entref_shake = EntIndexToEntRef(entity);
    	
      	DispatchKeyValue(entref_shake, "frequency", "1.0");
      	DispatchKeyValue(entref_shake, "duration", "0.85");
      	DispatchKeyValue(entref_shake, "spawnflags", "8");
      	DispatchSpawn(entref_shake);
      	ActivateEntity(entref_shake);
      	AcceptEntityInput(entref_shake, "Enable");
      	TeleportEntity(entref_shake, vPos, NULL_VECTOR, NULL_VECTOR);
	}
	else DispatchKeyValue(entref_shake, "spawnflags", "4");
	FloatToString(intensity, sTemp, sizeof(sTemp));
	DispatchKeyValue(entref_shake, "amplitude", sTemp);
	FloatToString(range, sTemp, sizeof(sTemp));
    DispatchKeyValue(entref_shake, "radius", sTemp);
	AcceptEntityInput(entref_shake, "StartShake");
}

Action Open_Saferoom(Handle timer, bool scary = false)
{
    if (IsValidEntRef(g_iLockedDoor) && scary && zm_stage<ZM_STARTED)
    {
        EmitSoundToAll(SOUND_PANIC_ON,_,_,_,_,SNDVOL_NORMAL);
        if (g_ExplosionSprite > -1)
		{
			float vPos[3],vAng[3];
			L4D_GetEntityWorldSpaceCenter(EntRefToEntIndex(g_iLockedDoor),vPos);
			TE_SetupExplosion(vPos,g_ExplosionSprite,20.0,1,0,500,5000);
			TE_SendToAll();
			PhysicsExplode(vPos,150,1500.0,false);
			
			float dust_size = 150.0;
			float vPos_dust[3];
			vPos_dust = vPos;
			vPos_dust[2] -= dust_size;
			
			CreateShake(50.0,5000.0,vPos);
			CreateShake(50.0,5000.0,vPos);
			CreateShake(50.0,5000.0,vPos);
			
			static char sound_explosion[64];
			switch (GetRandomInt(1,3))
			{
    			case 1: sound_explosion = EXPLOSION1;
    			case 2: sound_explosion = EXPLOSION2;
    			case 3: sound_explosion = EXPLOSION3;
			}
			EmitSoundToAll(sound_explosion,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
			
			static char sModel[64];
        	GetEntPropString(g_iLockedDoor, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
			GetEntPropVector(g_iLockedDoor, Prop_Data, "m_vecAbsOrigin", vPos);
            GetEntPropVector(g_iLockedDoor, Prop_Send, "m_angRotation", vAng);
			
			AcceptEntityInput(g_iLockedDoor,"Kill");
			g_iLockedDoor = INVALID_ENT_REFERENCE;
			
			// Get average survivor position
			int numplayers = 0;
			float vAvg[3], vTemp[3];
			for( int i = 1; i <= MaxClients; i++ )
        	{
        	    if (!IsClientInGame(i)) continue;
        	    if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        		if (!IsPlayerAlive(i)) continue;
        		L4D_GetEntityWorldSpaceCenter(i,vTemp);
        		vAvg[0] += vTemp[0];
        		vAvg[1] += vTemp[1];
        		vAvg[2] += vTemp[2];
        		numplayers += 1;
        	}
        	
        	if (numplayers>0)
        	{
            	vAvg[0] /= numplayers;
    			vAvg[1] /= numplayers;
    			vAvg[2] /= numplayers;
    			
    			float vecResult[3];
                MakeVectorFromPoints(vPos,vAvg,vecResult);
                vecResult[2] = 0.0;
                NormalizeVector(vecResult,vecResult);
                
     			// pos[3], dir[3], float Size, float Speed
     			TE_SetupDust(vPos_dust,{0.0,0.0,1.0},dust_size,2.0);
     			TE_SendToAll();
                
                ScaleVector(vecResult,GetRandomFloat(1000.0,10000.0));
    			
    			int door = CreateEntityByName("prop_physics");
    			if (IsValidEntity(door))
    			{
                    DispatchKeyValue(door, "spawnflags", "4");
                    DispatchKeyValue(door, "model", sModel);
                    DispatchSpawn(door);
                    TeleportEntity(door,vPos,vAng,vecResult);
                }
            }
		}
    }
    start_zm_round(false); // doesnt play sound
    
    if (IsValidEntRef(entref_shake))
    {
        RemoveEdict(entref_shake);
        entref_shake = INVALID_ENT_REFERENCE;
    }
    
    return Plugin_Continue;
}

void Force_Saferoom_Scary()
{
    if (!IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED)
    {
        if (zm_stage<ZM_STARTED) start_zm_round(false);
        return;
    }
    
    float vPos[3];
    L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,vPos);
    
    float vPosOrigin[3];
    GetEntPropVector(g_iLockedDoor, Prop_Data, "m_vecAbsOrigin", vPosOrigin);
    
    if (IsValidEntRef(entref_shake)) RemoveEdict(entref_shake);
    CreateShake(0.0,0.0,vPos); //precaching of some sort...
    
    if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED)
    {
        AcceptEntityInput(g_iLockedDoor,"Close");
    }
    
    set_force_start(true);
    saferoom_lock(true);
    //if (IsValidEntRef(g_iLockedDoor) && !saferoom_interacted) AcceptEntityInput(g_iLockedDoor, "Use");
    float delay_accumulate = 2.0;
    float max_duration = 2.0;
    float min_duration = 0.2;
    int num_slams = GetRandomInt(80,130);
    for( int i = 1; i <= num_slams; i++ )
    {
        float random_duration = GetRandomFloat(min_duration,max_duration);
        CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        if (i==num_slams) CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        delay_accumulate += random_duration;
        if (max_duration<=0.04) max_duration = 0.04;
        else max_duration -= (max_duration/10.0);
        min_duration = max_duration/10.0;
    }
    CreateTimer(delay_accumulate+1.0,Open_Saferoom,true,TIMER_FLAG_NO_MAPCHANGE);
}

Action zm_start(int client, int args)
{
    if (DEBUG) LogMessage("[zm] zm_start");
    if (!g_bCvarAllow) return Plugin_Continue;
    if (!L4D_HasMapStarted() || L4D_IsInIntro()>0) return Plugin_Continue;
    if (client==zm_client || CheckCommandAccess(client,"is_a_sm_admin",ADMFLAG_GENERIC,true))
    {
        if (zm_can_start || zm_stage>=ZM_STARTED)
        {
            if (zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor) && !force_started)
            {
                int random = GetRandomInt(1,5);
                static char sound[64];
                switch (random)
                {
                    case 1: {sound=SOUND_SCARY1;}
                    case 2: {sound=SOUND_SCARY2;}
                    case 3: {sound=SOUND_SCARY3;}
                    case 4: {sound=SOUND_SCARY4;}
                    case 5: {sound=SOUND_SCARY5;}
                    default: {sound=SOUND_SCARY3;}
                }
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                RequestFrame(Force_Saferoom_Scary);
            }
            else
            {
                start_zm_round(true); // plays sound
                Open_Saferoom(null);
            }
        }
        
        if (client==zm_client && !zm_can_start)
        {
            update_t_zm_activity();
            t_zm_join = t_zm_activity - g_fPrepTimeZM - 1.0;
            can_zm_start();
        }
        
    }
    return Plugin_Continue;
}

Action ZM_Menu(int client, int args)
{
    if (!g_bCvarAllow || client!=zm_client || !IsValidClientZM()) return Plugin_Continue;
    char type[32] = "main";
    if (args>0) GetCmdArg(1, type, sizeof(type));
	TrimString(type);
	
	int MENU = ZM_MENU_MAIN;
	if (strcmp(type,"main")==0) MENU = ZM_MENU_MAIN;
	else if (strcmp(type,"common")==0) MENU = ZM_MENU_COMMON;
	else if (strcmp(type,"uncommon")==0) MENU = ZM_MENU_UNCOMMON;
	else if (strcmp(type,"special")==0) MENU = ZM_MENU_SPECIAL;
	else if (strcmp(type,"boss")==0) MENU = ZM_MENU_BOSS;
	else if (strcmp(type,"cleanup")==0) MENU = ZM_MENU_CLEANUP;
	else if (strcmp(type,"other")==0) MENU = ZM_MENU_OTHER;
	else if (strcmp(type,"close")==0) MENU = ZM_MENU_CLOSED;
	else MENU = ZM_MENU_MAIN;
    open_menu(zm_client,MENU);
    return Plugin_Continue;
}


//Action Unfreeze_Zombie(Handle timer, int entref)
//{
//    if (!IsValidEntRef(entref)) return Plugin_Stop;
//    SetEntProp(entref, Prop_Send, "m_fFlags", GetEntProp(entref, Prop_Send, "m_fFlags")&~FL_FROZEN);
//    return Plugin_Stop;
//}


void reset_time_of_day()
{
    SetConVarInt(FindConVar("sv_force_time_of_day"),-1);
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
    
    L4D2_RemoveEntityGlow(victim);
    
    if(GetClientTeam(victim)!=TEAM_INFECTED) return Plugin_Continue;
    
    static char targetName[20];
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
// 


float t_last_hitmarker = 0.0;
void update_vomited(int victim)
{
    float t_now = GetEngineTime();
    if ( FloatAbs(t_now-t_vomited[victim])<5.0 ) return;
    request_update_glow(victim);
    t_vomited[victim] = t_now;
    if (IsValidClientZM() && (t_now-t_last_hitmarker)>=0.1)
    {
        EmitSoundToClient(zm_client,SOUND_HITMARKER,_,_,_,_,_,GetRandomInt(95,105));
        t_last_hitmarker = t_now;
    }
    spawn_free_angry_zombies(victim,g_iVomitCommons);
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



void ResetCvars()
{
    if (DEBUG) LogMessage("[zm] ResetCvars");
    
    ResetConVar(FindConVar("director_tank_lottery_selection_time"), true, true);
    ResetConVar(FindConVar("tank_stuck_time_suicide"), true, true);
    ResetConVar(FindConVar("z_frustration"), true, true);
    ResetConVar(FindConVar("tank_stuck_failsafe"), true, true);
    
    ResetConVar(FindConVar("z_no_cull"), true, true);
	ResetConVar(FindConVar("z_minion_limit"), true, true);
	ResetConVar(FindConVar("director_no_bosses"), true, true);
	ResetConVar(FindConVar("director_no_specials"), true, true);
	ResetConVar(FindConVar("director_panic_forever"), true, true);
	
	ResetConVar(FindConVar("z_discard_range"), true, true);
	ResetConVar(FindConVar("z_discard_min_range"), true, true);

	ResetConVar(FindConVar("survival_max_smokers"), true, true);
	ResetConVar(FindConVar("survival_max_boomers"), true, true);
	ResetConVar(FindConVar("survival_max_hunters"), true, true);
	ResetConVar(FindConVar("survival_max_spitters"), true, true);
	ResetConVar(FindConVar("survival_max_jockeys"), true, true);
	ResetConVar(FindConVar("survival_max_chargers"), true, true);
	ResetConVar(FindConVar("survival_max_specials"), true, true);
	ResetConVar(FindConVar("survival_special_limit_increase"), true, true);
	ResetConVar(FindConVar("survival_special_spawn_interval"), true, true);
	ResetConVar(FindConVar("survival_special_stage_interval"), true, true);
	ResetConVar(FindConVar("z_smoker_limit"), true, true);
	ResetConVar(FindConVar("z_boomer_limit"), true, true);
	ResetConVar(FindConVar("z_hunter_limit"), true, true);
	ResetConVar(FindConVar("z_spitter_limit"), true, true);
	ResetConVar(FindConVar("z_jockey_limit"), true, true);
	ResetConVar(FindConVar("z_charger_limit"), true, true);
	ResetConVar(FindConVar("director_allow_infected_bots"), true, true);
	ResetConVar(FindConVar("z_spawn_safety_range"), true, true);
	
	ResetConVar(FindConVar("z_max_player_zombies"), true,true);
	
	ResetConVar(FindConVar("z_large_volume_mob_too_far_xy"), true,true);
	ResetConVar(FindConVar("z_large_volume_mob_too_far_z"), true,true);
	
	// ask all plugins we are communicating with to reload their default values
	if (shoot_alert_enable && GetConVarInt(shoot_alert_enable)<=0) ServerCommand("sm plugins reload l4d2_shoot_alert_common");
	if (infectedbots_enable && GetConVarInt(infectedbots_enable)<=0) ServerCommand("sm plugins reload l4dinfectedbots");
	if (jukebox_horde && GetConVarInt(jukebox_horde)<=0) ServerCommand("sm plugins reload l4d2_jukebox_spawner");
	SetConVarInt(FindConVar("mp_restartgame"), 1);
}

// Re-run this if player number has changed
void SetCvarsZM()
{
   if (DEBUG) LogMessage("[zm] SetCvarsZM");
   if (!g_bCvarAllow) return;
   
   SetConVarInt(FindConVar("director_tank_lottery_selection_time"), 9999);
   SetConVarInt(FindConVar("tank_stuck_time_suicide"), 0);
   SetConVarInt(FindConVar("z_frustration"), 0);
   SetConVarInt(FindConVar("tank_stuck_failsafe"), 0);
   
   SetConVarInt(FindConVar("z_discard_min_range"), 9999999);
   SetConVarInt(FindConVar("z_discard_range"), 9999999);
   SetConVarInt(FindConVar("z_no_cull"), 1);
   SetConVarInt(FindConVar("z_minion_limit"), 0);
   SetConVarInt(FindConVar("director_no_bosses"), 1);
   SetConVarInt(FindConVar("director_no_specials"), 1);
   SetConVarInt(FindConVar("director_allow_infected_bots"), 0);
   
   SetConVarInt(FindConVar("sb_all_bot_game"),1);
   SetConVarInt(FindConVar("allow_all_bot_survivor_team"),1);
   
   SetConVarInt(FindConVar("z_large_volume_mob_too_far_xy"),50000);
   SetConVarInt(FindConVar("z_large_volume_mob_too_far_z"),50000);
   
   int d;
   
   // Check if Specials need updating
   int new_max_SI;
   if (g_iMaxSI<0)
   {
       new_max_SI = g_iAliveSurvivors+g_iMaxSI+1;
       if (new_max_SI<=0) new_max_SI = 1;
   }
   else new_max_SI = g_iMaxSI;
   if (new_max_SI > SI_cap) new_max_SI = SI_cap;
   if (new_max_SI!=max_SI)
   {
       available_SI += (new_max_SI-max_SI);
       max_SI = new_max_SI;
       if (available_SI>max_SI) available_SI = max_SI;
       else if (available_SI<0) available_SI = 0;
       create_main_menu();
   }
   int max_unique_SI = get_max_unique_SI_override();
   int length = sizeof(available_zombie_arr);
   int temp_lim, changes = 0;
   for(int i = 0; i < length; i++)
   {
         if (i==ZOMBIECLASS_COMMON || i==ZOMBIECLASS_WITCH) continue;
         if (costs_SI[i]<0) temp_lim = 0;
         else temp_lim = max_unique_SI; 
         if (change_special_max(i,temp_lim,false)>0)
         {
              if (i==ZOMBIECLASS_TANK) create_boss_menu();
              else changes += 1;
         }
         else if (available_zombie_arr[i]>max_zombie_arr[i])
         {
             available_zombie_arr[i] = max_zombie_arr[i];
         }
   }
   if (changes>0) create_special_menu();
   
   // Sanity check available_SI
   int occupied_SI_total = 0;
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_SMOKER]-available_zombie_arr[ZOMBIECLASS_SMOKER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_BOOMER]-available_zombie_arr[ZOMBIECLASS_BOOMER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_HUNTER]-available_zombie_arr[ZOMBIECLASS_HUNTER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_SPITTER]-available_zombie_arr[ZOMBIECLASS_SPITTER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_JOCKEY]-available_zombie_arr[ZOMBIECLASS_JOCKEY];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_CHARGER]-available_zombie_arr[ZOMBIECLASS_CHARGER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_TANK]-available_zombie_arr[ZOMBIECLASS_TANK];
   d = max_SI-available_SI;
   available_SI += (d-occupied_SI_total);
   if (available_SI>max_SI) available_SI = max_SI;
   else if (available_SI<0) available_SI = 0;
   
   // Check if Witches need updating
   int new_max_witches;
   if (g_iMaxWitches<0) new_max_witches = RoundToCeil(g_iAliveSurvivors/2.0);
   else new_max_witches = g_iMaxWitches;
   if (new_max_witches!=max_zombie_arr[ZOMBIECLASS_WITCH])
   {
      d = new_max_witches - max_zombie_arr[ZOMBIECLASS_WITCH];
      max_zombie_arr[ZOMBIECLASS_WITCH] = new_max_witches;
      add_available_zombie(ZOMBIECLASS_WITCH,d);
   }
   else if (available_zombie_arr[ZOMBIECLASS_WITCH]>max_zombie_arr[ZOMBIECLASS_WITCH])
       available_zombie_arr[ZOMBIECLASS_WITCH] = max_zombie_arr[ZOMBIECLASS_WITCH];
   
   // Include all SI on field + spectating ZM
   SetConVarInt(FindConVar("survival_max_specials"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_max_player_zombies"), MAXPLAYERS);
   
   SetConVarInt(FindConVar("survival_max_smokers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_boomers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_hunters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_spitters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_jockeys"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_chargers"), MAXPLAYERS);
   
   SetConVarInt(FindConVar("z_smoker_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_boomer_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_hunter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_spitter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_jockey_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_charger_limit"), MAXPLAYERS);
   
   if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
   if (jukebox_horde) SetConVarInt(jukebox_horde, 0);
   
}

int get_max_unique_SI_override()
{
    if (g_iMaxUniqueSI<0) return RoundToCeil(max_SI/2.0);
    if (g_iMaxUniqueSI>max_SI) return max_SI;
    return g_iMaxUniqueSI;
}

int change_special_max(int ZOMBIECLASS, int new_max, bool draw = true)
{
    if (ZOMBIECLASS==ZOMBIECLASS_TANK && g_hNoTanks.BoolValue) new_max = 0;
    else if (new_max>max_SI) new_max = max_SI;
    if (max_zombie_arr[ZOMBIECLASS]==new_max) return 0;
    int d = new_max - max_zombie_arr[ZOMBIECLASS];
    max_zombie_arr[ZOMBIECLASS] = new_max;
    add_available_zombie(ZOMBIECLASS,d,draw);
    return 1;
}

public void OnMapStart()
{
    if (DEBUG) LogMessage("[zm] OnMapStart");

	GridLib_Initialize();
	GridLib_StartPrecomputation();

	PluginPrecacheModel(MODEL_SMOKER);
	PluginPrecacheModel(MODEL_BOOMER);
	PluginPrecacheModel(MODEL_HUNTER);
	PluginPrecacheModel(MODEL_SPITTER);
	PluginPrecacheModel(MODEL_JOCKEY);
	PluginPrecacheModel(MODEL_CHARGER);
	PluginPrecacheModel(MODEL_TANK);
	
	PluginPrecacheModel(MODEL_RIOT); // Riot Police
	PluginPrecacheModel(MODEL_CEDA); // CEDA Hazmat
	PluginPrecacheModel(MODEL_CLOWN); // Clown
	PluginPrecacheModel(MODEL_MUD); // Mud
	PluginPrecacheModel(MODEL_ROAD); // Road Worker
	PluginPrecacheModel(MODEL_JIMMY); // Jimmy Gibbs
	PluginPrecacheModel(MODEL_FALLEN); // Fallen Survivor
	
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
        //}
        
        //fastdl is necessary otherwise client will hang FOREVER on a black screen.
        if (FindConVar("sv_allowdownload").BoolValue)
        {
            ConVar g_hDownloadUrl = FindConVar("sv_downloadurl");
            if (g_hDownloadUrl!=null)
            {
                static char currentUrl[256];
                g_hDownloadUrl.GetString(currentUrl,sizeof(currentUrl));
                TrimString(currentUrl);
                if (currentUrl[0]=='\0') g_hDownloadUrl.SetString("https://gvazdas.github.io/l4d2_zombie_master/left4dead2", false, false);
            }
            
            static char buffer[128];
            //if (lipsync_available) Format(buffer, sizeof(buffer), "sound/%s", SOUND_ELLIS_ZM);
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_ELLIS_ZM_MP3);
            AddFileToDownloadsTable(buffer);
            
            //if (lipsync_available) Format(buffer, sizeof(buffer), "sound/%s", SOUND_LOUIS_ZM);
            Format(buffer, sizeof(buffer), "sound/%s", SOUND_LOUIS_ZM_MP3);
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
	static char sMap[64];
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
        	g_hObscuredList = new ArrayList(sizeof(PreCalcNav));
        	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
        	g_bNavReady = false;
        	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
    	}
    	zm_update();
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

Action Timer_StartPrecomputeNav(Handle timer)
{
	if (DEBUG) LogMessage("[zm] Starting navmesh precomputation...");
	float startTime = GetEngineTime();

	// Get all nav areas
	ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
	int totalAreas = allAreas.Length;
    g_bNavReady = false;
    
	LogMessage("[zm] Found %d nav areas to process", totalAreas);
    if (totalAreas<1) return Plugin_Stop;
    
    Address temp_navArea;
    float vector_start[3];
    bool start_known = false;
    int g_iInfoPlayerStart = FindEntityByClassname(INVALID_ENT_REFERENCE, "info_player_start");
    if(IsValidEntity_Safe(g_iInfoPlayerStart))
    {
        GetEntPropVector(g_iInfoPlayerStart, Prop_Data, "m_vecOrigin", vector_start);
        temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
        if (navArea_validStart(temp_navArea)) start_known = true;
    }
    if (!start_known)
    {
        int entity = INVALID_ENT_REFERENCE;
        while( INVALID_ENT_REFERENCE != (entity = FindEntityByClassname(entity, "info_survivor_position")) )
	    {
       	    if(IsValidEntity_Safe(entity)) 
       	    {
           	     GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector_start);
           	     temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
                 if (navArea_validStart(temp_navArea)) start_known = true;
            }
	   }
    }
    
    
    int navSpawnAttributes;
    int total_stored_obscured = 0;
    int total_stored_start = 0;
    bool valid_start = false;
    bool valid_obscured = false;
    PreCalcNav cell;
    float pos[3];
    float vSize[3];
	for (int i = 0; i < totalAreas; i++)
	{
		Address navArea = allAreas.Get(i);
		if (!navArea) continue;
		L4D_GetNavAreaSize(navArea, vSize);
        if (vSize[0]<=50.0 && vSize[1]<=50.0) continue;
		L4D_FindRandomSpot(navArea,pos);
		valid_start = false;
		valid_obscured = true;
		navSpawnAttributes = L4D_GetNavArea_SpawnAttributes(navArea);
		
		valid_start = navArea_validStart(navArea);
		if (valid_start) valid_obscured = false;
		
		// asdf future: check back and forth distance from info survivor position, if negative this is not a valid position
		
		//valid_start = (navSpawnAttributes & NAV_SPAWN_PLAYER_START) || (navSpawnAttributes & NAV_SPAWN_CHECKPOINT && navSpawnAttributes & ~NAV_SPAWN_FINALE && navSpawnAttributes & ~NAV_SPAWN_OBSCURED);
		if (valid_start)
		{
    	//	float flow = L4D_GetFlowFromPoint(pos);
    	//	if (flow>0.0 || flow<(-9000.0)) valid_start = false;
    		
    		float distance = 0.0;
    		if (valid_start && start_known) distance = L4D2_NavAreaTravelDistance(vector_start,pos,false);
    		//bool isconnected = L4D_NavArea_IsConnected(navArea,temp_navArea,4);
    		//bool isconnected = L4D2_IsReachable(1,pos);
    		
    		//if (valid_start) LogMessage("[zm] start nav size: %f %f %f, flow: %f, start dist: %f", vSize[0], vSize[1], vSize[2], flow, distance);
    		if (distance>500.0 || distance<0.0) valid_start = false;
    		
		}
		
		if (!valid_start && valid_obscured) valid_obscured = ( (navSpawnAttributes & NAV_SPAWN_OBSCURED) || (navSpawnAttributes & NAV_SPAWN_IGNORE_VISIBILITY) );
		
		if (valid_start || valid_obscured)
		{
    		L4D_FindRandomSpot(navArea,pos);
    		cell.position[0] = pos[0];
			cell.position[1] = pos[1];
			cell.position[2] = pos[2];
			cell.navArea = navArea;
		}
		else continue;
		
		if (valid_start)
		{
    		g_hStartAreaList.PushArray(cell);
    		total_stored_start += 1;
		}
		else if (valid_obscured)
		{
    		g_hObscuredList.PushArray(cell);
    		total_stored_obscured += 1;
		}
		
	}

	delete allAreas;

	g_bNavReady = true;

	float duration = GetEngineTime() - startTime;
	LogMessage("[zm] Navmesh precomputation took %f seconds", duration);
	LogMessage("[zm] Total obscured navmeshes: %d", total_stored_obscured);
	LogMessage("[zm] Total start area navmeshes: %d", total_stored_start);

	return Plugin_Stop;
}

Action set_client_active(Handle timer, int client)
{
    if (!IsValidClient(client)) return Plugin_Stop;
    if (clients_active[client]) return Plugin_Stop;
    if (DEBUG) LogMessage("[zm] set_client_active %d", client);
    clients_active[client] = true;
    if (zm_stage<ZM_STARTED && fq_timer==INVALID_HANDLE)
        fq_timer = CreateTimer(0.1,fair_queue_update);
    return Plugin_Stop;
}

// asdf TO DO this runs very frequently, find a better way.
bool use_pressed = false;
bool reload_pressed = false;
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse)
{
    if (!g_bCvarAllow) return Plugin_Continue;
	
	if (g_hAbilityNoCooldown.BoolValue && GetClientTeam(client)==TEAM_INFECTED && IsPlayerAlive(client))
	{
    	L4D2_SetCustomAbilityCooldown(client,0.0);
	}
	
	if (IsFakeClient(client))
	{
    	return Plugin_Continue;
	}
	
	if (impulse==100) toggle_ZM_vision(client);
	
	if ( (!first_active || !clients_active[client]) && (buttons>0 || impulse>0) )
	{
    	first_active = true;
    	set_client_active(null,client);
    }
	
	if (client==zm_client)
	{
        	
       	if (recordpos && IsPlayerAlive(zm_client))
       	{
           	GetClientEyePosition(zm_client, zm_deathPos);
            GetClientEyeAngles(zm_client, zm_deathAngles);
       	}
       	
       	update_ZM_looktarget(true);
       	if (!use_pressed && (buttons&IN_USE)>0)
       	{
           	if (live_SI>0) ZMControlSI(zm_client,0);
           	else open_menu(zm_client,ZM_MENU_SPECIAL);
           	use_pressed = true;
       	}
       	else if (use_pressed && (buttons&IN_USE)<=0)
           	use_pressed = false;
       	
       	if (!reload_pressed && (buttons&IN_RELOAD)>0)
       	{
           	if (zm_menu_state==ZM_MENU_MAIN) close_menus(client);
           	else open_menu(zm_client,ZM_MENU_MAIN);
           	reload_pressed = true;
       	}
       	else if (reload_pressed && (buttons&IN_RELOAD)<=0)
           	reload_pressed = false;
        
        if (zm_stage<ZM_STARTED && !zm_can_start && !force_started) buttons &= ~IN_ATTACK & ~IN_ATTACK2;
        
	}
	
	return Plugin_Continue;
	
}

public void OnMapEnd()
{
	if (DEBUG) LogMessage("[zm] OnMapEnd");

	GridLib_Cleanup();

	if (!g_bCvarAllow) return;
	g_iLockedDoor = INVALID_ENT_REFERENCE; // we don't know if there's gonna be a door next map
	ResetTimer();
	zm_stage = ZM_END;
	clients_in_server = false;
	update_EMS_HUD();
	
	// Clean up pre-computed data
    if (g_hObscuredList != null)
    {
       	delete g_hObscuredList;
       	g_hObscuredList = null;
    }
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

void ResetTimer()
{
    if (DEBUG) LogMessage("[zm] ResetTimer");
    delete fq_timer;
    delete zm_timer;
    zm_timer = INVALID_HANDLE;
    delete ems_hud_timer;
    delete clients_timer;
    for(int i=1; i<=MAXENTITIES; i++)
    {
        hp_timers[i] = INVALID_HANDLE;
    }
    if (g_bCvarAllow && zm_stage<ZM_END) zm_update();
}

public void OnConfigsExecuted()
{
    if (DEBUG) LogMessage("[zm] OnConfigsExecuted");
	IsAllowed();
}

void evtRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	
	if (DEBUG) LogMessage("[zm] evtRoundEnd");
    
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
        	static char zm_name[MAX_NAME_LENGTH]; 
            GetClientName(zm_client,zm_name,sizeof(zm_name));
            PrintToChatAll("[zm] %t", "ZM won", zm_name);
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

// To draw EMS HUD
void enable_challenge_mode()
{
    //GameRules_SetProp("m_bChallengeModeActive", 1);
    GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
    EMS_hud_ready = true;
}

void IsAllowed()
{
	if (DEBUG) LogMessage("[zm] IsAllowed");
	bool bCvarAllow = g_hCvarAllow.BoolValue;
    
    if ( L4D_HasPlayerControlledZombies() && bCvarAllow)
    {
        SetConVarInt(g_hCvarAllow,0);
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
		HookEvent("survivor_call_for_help", EvtPlayerCallHelp, EventHookMode_Post); //userid -> actual player entity
		HookEvent("player_bot_replace", EvtBotReplacePlayer, EventHookMode_Post);
        HookEvent("bot_player_replace", EvtPlayerReplaceBot, EventHookMode_Post);
        HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
		
		load_zm_gamemode();
		GetCvars();
		SetCvarsZM();

		//if (g_hDTR_InputKill && !bypass_windows) g_hDTR_InputKill.Enable(Hook_Pre, DTR_CBaseEntity_InputKill);
		//if (g_hDTR_InputKillHierarchy && !bypass_windows) g_hDTR_InputKillHierarchy.Enable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
	    
		enable_challenge_mode();
		clients_in_server = true;
		
		for( int i = 1; i <= MaxClients; i++ )
    	{
    		if(IsClientInGame(i) && !IsFakeClient(i))
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
        	g_hObscuredList = new ArrayList(sizeof(PreCalcNav));
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

Action Event_ServerCvar(Handle event, char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	static char sConVarName[64];
	GetEventString(event, "cvarname", sConVarName, sizeof(sConVarName));
	if (StrContains(sConVarName,"zm_",false)==0) return Plugin_Handled;
	return Plugin_Continue;
}

// Bot replaced a player //
Action EvtBotReplacePlayer(Event event, const char[] name, bool dontBroadcast) 
{
    int bot = GetClientOfUserId(event.GetInt("bot"));
    int client = GetClientOfUserId(event.GetInt("player"));
    if (DEBUG) LogMessage("[zm] EvtBotReplacePlayer %d replaced %d", bot, client);
    request_update_glow(bot);
    request_update_glow(client);
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
    request_update_glow(bot);
    request_update_glow(client);
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
    request_update_glow(victim);
}

void EvtPlayerCallHelp(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) UpdateSurvivorGlow(client);
}

Action SwapSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
                    	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
                    	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (force_started && zm_stage<ZM_STARTED)
    {
        if (StrContains(sample,"survivor",false)!=-1 && StrContains(sample,"voice",false)!=-1 && StrContains(sample,"world",false)!=-1)
        {
            if (DEBUG) LogMessage("[zm] Muting survivor");
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

// Hide hit messages for ZM
Action OnPZDmgMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    if (!g_bCvarAllow || !IsValidClientZM()) return Plugin_Continue;
    BfReadByte(msg);
    int userid = BfReadShort(msg);
    if (zm_client_userid==userid) return Plugin_Handled;
    return Plugin_Continue;
} 

MRESReturn DHook_Fog_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (DEBUG) LogMessage("[zm] DHook_Fog_AcceptInput");
	if (!g_bCvarAllow) return MRES_Ignored;
	check_fog_distance();
	CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	return MRES_Ignored;
}

MRESReturn DHook_Director_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (DEBUG) LogMessage("[zm] DHook_Director_AcceptInput");
	if (!g_bCvarAllow) return MRES_Ignored;
	
	static char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (DEBUG) LogMessage("[zm] info_director accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (strcmp(inputName,"ForcePanicEvent")==0)
	{
	   if (zm_stage<ZM_STARTED)
	   {
    	   survival_activated=true;
	   }
	   // Called by ZM -- do nothing
	   if (activator==-1 && caller==-1 && actionId==0)
	   {
        	   manual_panic = true;
        	   return MRES_Ignored;
	   }
	   
	   if (panic && manual_panic) bank += g_iPanicCost;
	   manual_panic = false;
	   update_panic();
	}
	else if (strcmp(inputName,"PanicEvent")==0 || strcmp(inputName,"ScriptedPanicEvent")==0)
	{
        	if (panic && manual_panic) bank += g_iPanicCost;
        	manual_panic = false;
        	if (zm_stage<ZM_STARTED) survival_activated=true;
        	update_panic();
	}
	
	if (survival_activated && L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && !IsValidClientZM())
	{
        	PrintToChatAll("[zm] %t", "Start delay notify");
        	hReturn.Value = true;
        	return MRES_Supercede;
	}
	
	return MRES_Ignored;
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
            t_last_panic = GetEngineTime();
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
   	   if (g_bLockSaferoom && L4D_IsInIntro()>0 && GetClientTeam(client)==TEAM_SURVIVOR)
   	   {
       	   freeze_player(client);
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
               	if (model_pending[0]!=0)
               	{
                   	SetEntityModel(client, model_pending);
                   	RequestFrame(NextFrame_SetModel,EntIndexToEntRef(client));
               	}
           	}
       	}
       	if (specials_frozen && IsFakeClient(client)) freeze_player(client,true,TEAM_INFECTED);
      }
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    if (!specials_frozen || zm_stage!=ZM_STARTED) return;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(victim) && IsFakeClient(victim) && GetClientTeam(victim)==TEAM_INFECTED)
    {
        int client = event.GetInt("attacker");
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
	
	if (specials_frozen && zm_stage==ZM_STARTED && IsFakeClient(client) && GetClientTeam(client)==TEAM_INFECTED)
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
}

void check_zm_team()
{
   if (!IsValidClientZM()) return;
   if (GetClientTeam(zm_client)==TEAM_SURVIVOR)
   {
       update_t_zm_activity(0.0); // instantly starts printing the "no ZM" message
       QuitZM(zm_client);
   } 
}

void evtPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    if (DEBUG) LogMessage("[zm] evtPlayerTeam %d", client);
    request_update_glow(client);
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
	request_update_glow(client);
	clients_active[client] = false;
	clients_offered[client] = false;
	dominated[client] = false;
	if (!IsFakeClient(client))
	{
       	clients_in_server = true;
       	t_last_join = GetEngineTime();
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
    clients_t_join[client] = GetEngineTime();
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
	      
          static char targetName[32];
          GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
          static char class[32];
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
             int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
             if (ability > 0 && IsValidEdict(ability))
             {
                 if ((GetEntPropFloat(ability, Prop_Send, "m_timestamp")-GetGameTime())>0.0) 
                     refund = false;
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




    
