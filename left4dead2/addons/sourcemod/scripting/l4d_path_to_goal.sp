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

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <l4d_path_to_goal>

#define PLUGIN_NAME			    "l4d_path_to_goal"
#define PLUGIN_VERSION 			"1.31 2026-06-02"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

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
    LoadTranslations("l4d_path_to_goal.phrases");

    RegConsoleCmd("path_to_goal",       CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("pathtogoal",         CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("wheretogo",          CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("imlost",             CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("guide",              CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("ptg",                CmdRequestGuide, "Point where to go to progress in the map.");

    g_bL4D2 = GetEngineVersion()==Engine_Left4Dead2;
    
    RegAdminCmd("l4d_path_to_goal_recalculate", CmdRecalculate, ADMFLAG_ROOT,"Recalculate guide points.");
    RegAdminCmd("l4d_path_to_goal_print",       CmdPrint, ADMFLAG_ROOT,"Print g_GuideCells.");
    if (g_bL4D2) RegAdminCmd("l4d_path_to_goal_rescue", CmdRescue, ADMFLAG_ROOT,"Send in rescue vehicle.");
    RegAdminCmd("l4d_path_to_goal_ground", CmdGround, ADMFLAG_ROOT,"Check if origin is near ground.");

    g_hCvarEnable = CreateConVar("l4d_path_to_goal_enable", "1",
    "0=OFF, 1=ON.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarEnable.AddChangeHook(ConVarChanged_Cvars);
  	
    g_hCvarMax = CreateConVar("l4d_path_to_goal_max", "32",
    "Max beams per request. Increasing this can potentially cause crashes for clients.",FCVAR_NOTIFY, true, 1.0, true, 1000.0);

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

    g_hCvarFinale = CreateConVar("l4d_path_to_goal_finale", "1",
    "On Finale maps, connect to rescue vehicle... 0: ALWAYS, 1: FINALE STARTED, 2: RESCUE ARRIVED, 3: NEVER",FCVAR_NOTIFY, true, 0.0, true, 3.0);

    g_hCvarFinaleAuto = CreateConVar("l4d_path_to_goal_finale_auto", "1",
    "Draw beams to rescue vehicle when it arrives. l4d_path_to_goal_finale must be less than 3.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);
    
    t_nav = -1.0;
    Check_Guidable();
    GetCvars();
    
    nav_started = true;
    guide_prep = false;
    HookEvent("round_start_post_nav",     evtPostNav,        EventHookMode_PostNoCopy);
    HookEvent("nav_blocked",              evtNavChange,      EventHookMode_PostNoCopy);
    HookEvent("nav_generate",             evtNavChange,      EventHookMode_PostNoCopy);
	HookEvent("finale_start", 			  evtFinaleStart,    EventHookMode_PostNoCopy);
	HookEvent("finale_radio_start", 	  evtFinaleStart,    EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_ready", 	  evtFinaleVehicle,  EventHookMode_PostNoCopy);
    if (g_bL4D2)
    {
    HookEvent("gauntlet_finale_start", 	  evtGauntletStart,  EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_incoming",  evtFinaleVehicle,  EventHookMode_PostNoCopy);
    }
}

void evtFinaleVehicle(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
    LogMessage("evtFinaleVehicle");
    #endif
    if (finale) finale_rescue = true;
    if (!enable) return;
    if (finale_rescue && g_hCvarFinale.IntValue < FINALE_NEVER)
    {
        if (guide_ready && !finale_stitched && should_stitch_finale()) stitch_finale();
        if (g_hCvarFinaleAuto.BoolValue) Guide_All_Clients();
    }
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
    LogMessage("evtFinaleStart");
    #endif
    finale = true;
    if (guide_ready && !finale_stitched && should_stitch_finale()) stitch_finale();
}

void evtGauntletStart(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
    LogMessage("evtGauntletStart");
    #endif
    finale = true;
    if (!use_gauntlet_logic() && finale_stitched) Guide_Cleanup(); // need to recalculate cells
    finale_gauntlet = true;
    if (!enable) return;
    if (guide_ready && !finale_stitched && should_stitch_finale()) stitch_finale();
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void evtPostNav(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG>1
        LogMessage("round_start_post_nav");
    #endif
    nav_started = true;
    finale = false;
    finale_rescue = false;
    finale_gauntlet = false;
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
    if (!enable || !gamemode_guidable || !map_started || !nav_started || timer_nav != null) return;
    timer_nav = CreateTimer(NAV_COOLDOWN,Timer_CheckRequests,_,TIMER_FLAG_NO_MAPCHANGE);
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

Action CmdRequestGuide(int client, int args)
{
    if (!enable || !map_started || !nav_started || !gamemode_guidable || !IsValidClient(client) || IsFakeClient(client)) return Plugin_Continue;
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
    switch (RequestGuide(client,duration,backward))
    {
        case true: // beams drawn
        {
            static float eye_client[3], ang_client[3], ang_beam[3];
            GetClientEyePosition(client,eye_client);

            float dx = FloatAbs(eye_client[0] - g_RequestFirstPos[0]);
            float dy = FloatAbs(eye_client[1] - g_RequestFirstPos[1]);
            if (dx<=5.0 && dy<=5.0) // Direction will be spurious if we are on the point
            {
                if (g_fRequestFlow>0.0) ReplyToCommand(client, "[PTG|%.0f|%.0f] %t%t", g_fRequestFlow, g_fMaxFlow, "ptg_look", "ptg_down");
                else ReplyToCommand(client, "[PTG] %t%t", "ptg_look", "ptg_down");
                return Plugin_Continue;
            }

            GetClientEyeAngles(client,ang_client);
    
            SubtractVectors(g_RequestFirstPos,eye_client,ang_beam);
            GetVectorAngles(ang_beam,ang_beam);  
            if (ang_beam[0] > 180.0) ang_beam[0] -= 360.0;
            if (ang_beam[1] > 180.0) ang_beam[1] -= 360.0;
            SubtractVectors(ang_beam,ang_client,ang_beam);
            //LogMessage("%.1f %.1f %.1f", ang_beam[0], ang_beam[1], ang_beam[2]);

            static char str1[PLATFORM_MAX_PATH], str2[PLATFORM_MAX_PATH];
            
            if (FloatAbs(ang_beam[1]) < 90.0) Format(str1,sizeof(str1),"%T", "ptg_ahead", client);
            else Format(str1,sizeof(str1),"%T", "ptg_behind", client);
            //else if ( FloatAbs(FloatAbs(ang_beam[1])-180.0) <= 45.0 ) Format(str1,sizeof(str1),"%T", "ptg_behind", client);
            //else if (ang_beam[1]>0.0) Format(str1,sizeof(str1),"%T", "ptg_left", client);
            //else Format(str1,sizeof(str1),"%T", "ptg_right", client);

            if (ang_beam[0]>=30.0) Format(str2,sizeof(str2),"%T", "ptg_down", client);
            else if (ang_beam[0]<=(-30.0)) Format(str2,sizeof(str2),"%T", "ptg_up", client);
            else str2 = "\0";
            if (g_fRequestFlow>0.0) ReplyToCommand(client, "[PTG|%.0f|%.0f] %t%s %s", g_fRequestFlow, g_fMaxFlow, "ptg_look", str1, str2);
            else ReplyToCommand(client, "[PTG] %t%s %s", "ptg_look", str1, str2);
        }
        default: // beams not drawn
        {
            if (!guide_ready && g_CellRequests[client].duration > 0.0) ReplyToCommand(client, "[PTG] %t", "ptg_wait");
        }
    }
    return Plugin_Continue;
}

Action CmdRecalculate(int client, int args)
{
    if (!enable || !map_started || !nav_started || !gamemode_guidable) return Plugin_Continue;
    if (!guide_prep)
    {
        Guide_Cleanup();
        Guide_Prep();
    }
    else ReplyToCommand(client, "[PTG] %t", "ptg_busy");
    return Plugin_Continue;
}

Action CmdPrint(int client, int args)
{
    if (!guide_ready || g_GuideCells==null || g_GuideCells.Length<=0) return Plugin_Continue;
    static Cell cell;
    ReplyToCommand(client, "index navArea flow pos");
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        ReplyToCommand(client, "%d %d %.1f (%.1f %1.f %.1f)", i, cell.navArea, cell.flow, cell.center[0], cell.center[1], cell.center[2]);
    }
    return Plugin_Continue;
}

Action CmdRescue(int client, int args)
{
    //LogMessage("CmdRescue");
    L4D2_SendInRescueVehicle();
    return Plugin_Continue;
}

Action CmdGround(int client, int args)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Stop;
    static float pos[3];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
    ReplyToCommand(client,"Ground %d",valid_ground(pos));
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
    timer_nav = null;
}

public void OnMapEnd()
{
    map_started = false;
    nav_started = false;
    t_nav = -1.0;
    Guide_Cleanup();
    guide_prep = false;
    g_iPrepStage = STAGE_NONE;
    beams_cooldown_reset(_,true); // reset all requests and cooldowns
    timer_nav = null;
    finale = false;
}

public void OnPluginEnd()
{
    Guide_Cleanup();
    guide_prep = false;
    g_iPrepStage = STAGE_NONE;
}

public void OnClientPutInServer(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    beams_cooldown_reset(client,true); // reset cooldown and last request from client
}

// NATIVE //

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("L4D_Path_To_Goal", Native_RequestGuide);
	return APLRes_Success;
}

void Native_RequestGuide(Handle plugin, int numParams)
{
    if (!enable || !gamemode_guidable || !nav_started || !map_started) return;
    int client = (numParams>0) ? GetNativeCell(1) : -1;
    float duration = (numParams>1) ? view_as<float>(GetNativeCell(2)) : 5.0;
    bool backward = (numParams>2) ? view_as<bool>(GetNativeCell(3)) : false;
    bool join_client = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : true;
    RequestGuide(client,duration,backward,join_client);
}