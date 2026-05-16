#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <l4d_path_to_goal>

#define PLUGIN_NAME			    "l4d_path_to_goal"
#define PLUGIN_VERSION 			"1.03 2026-05-15"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

// Try escape_route entity

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Path To Goal",
	author = "gvazdas, zyiks",
	description = "Automatic path to goal indicator.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352685, https://github.com/gvazdas/l4d2_zombie_master"
}

public void OnPluginStart()
{
    AutoExecConfig(true, CONFIG_FILENAME);

    RegConsoleCmd("path_to_goal",       CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("pathtogoal",         CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("wheretogo",          CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("imlost",             CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("guide",              CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("ptg",                CmdRequestGuide, "Point where to go to progress in the map.");
    
    RegAdminCmd("l4d_path_to_goal_recalculate", CmdRecalculate, ADMFLAG_ROOT,"Recalculate guide points.");

    g_hCvarEnable = CreateConVar("l4d_path_to_goal_enable", "1",
    "0=OFF, 1=ON.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarEnable.AddChangeHook(ConVarChanged_Cvars);
  	
    g_hCvarMax = CreateConVar("l4d_path_to_goal_max", "16",
    "Max beams per request. Increasing this can potentially cause crashes.",FCVAR_NOTIFY, true, 1.0, true, 1000.0);

    g_hCvarSurvivors = CreateConVar("l4d_path_to_goal_survivor", "1",
    "Allow survivors to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarInfected = CreateConVar("l4d_path_to_goal_infected", "1",
    "Allow infected to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarSpec = CreateConVar("l4d_path_to_goal_spec", "1",
    "Allow observers/spectators to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarAlive = CreateConVar("l4d_path_to_goal_alive", "0",
    "Allow request based on alive state: 0=all,1=alive only,2=dead only.",FCVAR_NOTIFY, true, 0.0, true, 2.0);

    g_hCvarBudget = CreateConVar("l4d_path_to_goal_budget", "0.5",
    "Max CPU budget (ms per frame) for escape route calculation. Larger budget makes requests available faster at the expense of server lag. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 1000.0);

  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);
    
    t_nav = -1.0;
    Check_Guidable();
    GetCvars();
    
    nav_started = true;
    guide_prep = false;
    HookEvent("round_start_post_nav", evtPostNav,    EventHookMode_PostNoCopy);
    HookEvent("nav_blocked",          evtNavChange,  EventHookMode_PostNoCopy);
    HookEvent("nav_generate",         evtNavChange,  EventHookMode_PostNoCopy);
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void evtPostNav(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
        LogMessage("round_start_post_nav");
    #endif
    nav_started = true;
    NavChanged();
}

void evtNavChange(Event event, const char[] name, bool dontBroadcast)
{
    NavChanged();
}

void NavChanged()
{
    Guide_Cleanup();
    t_nav = GetGameTime();
}

//public void OnEntityCreated(int entity, const char[] classname)
//{
//    if (!nav_started || !map_started) return;
//    if (strcmp(classname,"func_nav_blocker",false)==0 || strcmp(classname,"script_nav_blocker",false)==0)
//    {
//        NavChanged();
//    }
//}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

Action CmdRequestGuide(int client, int args)
{
    if (!enable || !map_started || !nav_started || !gamemode_guidable) return Plugin_Continue;
    float duration = 5.0;
    bool backward = GetClientTeam(client)!=TEAM_SURVIVOR;
    if (args>0)
    {
        float duration_new = GetCmdArgFloat(1);
        if (duration_new>0.0) duration = duration_new;
        char arg[16];
        GetCmdArg(1,arg,sizeof(arg));
        if (strcmp(arg,"backward")==0) backward = true;
        if (args>1)
        {
            duration_new = GetCmdArgFloat(2);
            if (duration_new>0.0) duration = duration_new;
            GetCmdArg(2,arg,sizeof(arg));
            if (strcmp(arg,"backward")==0) backward = true;
        }
    }
    RequestGuide(client,duration,backward);
    return Plugin_Continue;
}

Action CmdRecalculate(int client, int args)
{
    if (!enable || !map_started || !nav_started || !gamemode_guidable) return Plugin_Continue;
    if (!guide_prep) Guide_Cleanup();
    Guide_Prep();
    return Plugin_Continue;
}

public void OnMapStart()
{
	g_iLaser = PrecacheModel(VMT_LASERBEAM, true);
    RequestFrame(MapStarted);
}

void MapStarted()
{
    map_started = true;
    t_nav = -1.0;
    //if (nav_started && gamemode_guidable && !guide_ready) Guide_Prep();
}

public void OnMapEnd()
{
    map_started = false;
    nav_started = false;
    t_nav = -1.0;
    Guide_Cleanup(); 
}

public void OnPluginEnd()
{
    Guide_Cleanup();
}

public void OnClientPutInServer(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    beams_cooldown_reset(client);
    g_CellRequests[client].duration = -1.0; // cancel pending beams
}

// NATIVE //

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("L4D_Path_To_Goal", Native_RequestGuide);
	return APLRes_Success;
}

void Native_RequestGuide(Handle plugin, int numParams)
{
    if (!enable || !gamemode_guidable) return;
    int client = (numParams>0) ? GetNativeCell(1) : -1;
    float duration = (numParams>1) ? view_as<float>(GetNativeCell(2)) : 5.0;
    bool backward = (numParams>2) ? view_as<bool>(GetNativeCell(3)) : false;
    bool join_client = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : true;
    RequestGuide(client,duration,backward,join_client);
}