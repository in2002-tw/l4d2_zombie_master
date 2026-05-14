#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <l4d_path_to_goal>

#define PLUGIN_NAME			    "l4d_path_to_goal"
#define PLUGIN_VERSION 			"1.00 2026-05-13"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Path To Goal",
	author = "gvazdas",
	description = "Navmesh-based automatic path to goal indicator.",
	version = PLUGIN_VERSION,
	url = "https://github.com/gvazdas/l4d2_zombie_master"
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
  	
    g_hCvarMax = CreateConVar("l4d_path_to_goal_max", "32",
    "Max number of beams per request.",FCVAR_NOTIFY, true, 1.0, true, 1000.0);
    g_hCvarMax.AddChangeHook(ConVarChanged_Cvars);

  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);
    
    Check_Guidable();
    GetCvars();
    
    nav_started = true;
    HookEvent("round_start_post_nav", evtPostNav, EventHookMode_PostNoCopy);
    // nav_blocked nav_generate
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
    Guide_Prep();
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

Action CmdRequestGuide(int client, int args)
{
    if (!enable || !map_started || !gamemode_guidable) return Plugin_Continue;
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
    if (nav_started && !guide_ready) Guide_Prep();
}

public void OnMapEnd()
{
    map_started = false;
    nav_started = false;
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
}

// NATIVE //

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("L4D_Path_To_Goal", Native_RequestGuide);
	return APLRes_Success;
}

void Native_RequestGuide(Handle plugin, int numParams)
{
    if (!enable) return;
    int client = (numParams>0) ? GetNativeCell(1) : -1;
    float duration = (numParams>1) ? view_as<float>(GetNativeCell(2)) : 5.0;
    bool backward = (numParams>2) ? view_as<bool>(GetNativeCell(3)) : false;
    bool join_client = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : true;
    RequestGuide(client,duration,backward,join_client);
}

// Draw survivor path for client, for duration in seconds
// backward: include backwards-going path.
// join_client: draw connection between client's origin and nearest point in survivor path.
void RequestGuide(int client, float duration = 5.0, bool backward = false, bool join_client = true)
{
    #if DEBUG
    float t = GetEngineTime();
    #endif
    if (!enable || !gamemode_guidable || duration<=0.0 || g_iLaser==0 || !IsValidClient(client) || IsFakeClient(client)) return;
    if (!guide_ready) Guide_Prep();
    if (!guide_ready || g_GuideCells==null) return;
    if (beams_cooldown(client)) return;
    float flow = 0.0;
    int i_start = g_GuideCells.Length - 1;
    static float last_pos[3], eye_pos[3];
    GetClientEyePosition(client,eye_pos);
    if (IsPlayerAlive(client))
    {
        flow = L4D2Direct_GetFlowDistance(client);
        GetClientAbsOrigin(client,last_pos);
        last_pos[2] += 16.0;
        switch (GetEntProp(client, Prop_Send, "m_nWaterLevel"))
        {
            case 1: last_pos[2] += 16.0;
            case 2: last_pos[2] += 32.0;
        }
    }
    else
    {
        last_pos = eye_pos;
        last_pos[2] -= 48.0;
        if (pos_underwater(last_pos)) last_pos[2] += 32.0;
    }
    static Cell cell;
    bool use_flow = flow>0.0;
    float min_dist = -1.0;
    float dist;
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        if ( use_flow && ( cell.flow > flow ) )
        {
            i_start = i;
            break;
        }
        else
        {
            dist = GetVectorDistance(last_pos,cell.center,true);
            if (min_dist<0.0 || dist<min_dist)
            {
                min_dist = dist;
                i_start = i;
            }
        }
    }
    if (!use_flow && min_dist<0.0) return;
    
    // Try starting at a more reasonable position with LOS
    if ( join_client && (i_start+1)<g_GuideCells.Length && cell_visible(i_start+1,last_pos)) i_start += 1; // Move forward
    else if (i_start>0 && !cell_visible(i_start,last_pos) && cell_visible(i_start-1,last_pos)) i_start -=1; // Move backward
    
    int i_draw = 0;
    g_GuideCells.GetArray(i_start,cell,sizeof(Cell));

    if (join_client) // Connect client to starting cell
    {
        DrawBeam(client,last_pos,cell.center,duration);
        i_draw += 1;
    }

    int i_forward = i_start;
    int i_backward = i_start;
    static float pos_forward[3], pos_backward[3];
    pos_forward = cell.center;
    pos_backward = cell.center;
    bool end = false;
    while (!end)
    {
        end = true;
        if ((i_forward+1)<g_GuideCells.Length)
        {
            i_forward += 1;
            g_GuideCells.GetArray(i_forward,cell,sizeof(Cell));
            DrawBeam(client,pos_forward,cell.center,duration);
            pos_forward = cell.center;
            end = false;
            i_draw += 1;
            //#if DEBUG>1
            //    LogMessage("%d %.1f %.1f %.1f -> %.1f %.1f %.1f", i_forward,
            //    pos_forward[0], pos_forward[1], pos_forward[2],
            //    cell.center[0], cell.center[1], cell.center[2]);
            //#endif
            if (i_draw>=max_draw) break;
        }
        if (backward && i_backward>0)
        {
            i_backward -= 1;
            g_GuideCells.GetArray(i_backward,cell,sizeof(Cell));
            DrawBeam(client,pos_backward,cell.center,duration,{200,100,100,100});
            pos_backward = cell.center;
            end = false;
            i_draw += 1;
            if (i_draw>=max_draw) break;
        }
    }
    if (i_draw>0) beams_cooldown_update(client,duration);
    #if DEBUG
        LogMessage("RequestGuide: client %d flow %f cells %d i_start %d (%f ms)", client, flow, i_draw, i_start, (GetEngineTime()-t)*1000.0);
    #endif
}