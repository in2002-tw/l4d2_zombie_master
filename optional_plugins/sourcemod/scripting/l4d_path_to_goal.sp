#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_NAME			    "l4d_path_to_goal"
#define PLUGIN_VERSION 			"1.00 2026-05-09"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME
#define DEBUG 0

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Path To Goal",
	author = "gvazdas",
	description = "Fully automatic navmesh-based path to goal indicator.",
	version = PLUGIN_VERSION,
	url = "https://github.com/gvazdas/l4d2_zombie_master"
}

#define TEAM_SPECTATOR		1
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3

#define VMT_LASERBEAM "sprites/laserbeam.vmt"

// Data structure for guide points
enum struct Cell
{
	float flow;
    Address navArea;
	float center[3];
}

ArrayList g_GuideCells;
ConVar g_hCvarMPGameMode;
bool gamemode_guidable, guide_ready, map_started;
int g_iLaser;

public void OnPluginStart()
{
    RegConsoleCmd("guideme",   CmdRequestGuide, "Point where to go to progress in the map.");
	RegConsoleCmd("wheretogo", CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("imlost",    CmdRequestGuide, "Point where to go to progress in the map.");

    RegAdminCmd("l4d_path_to_goal_recalculate", CmdRecalculate, ADMFLAG_ROOT,"Recalculate guide points.");
  	
  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);

    Check_Guidable();
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

Action CmdRequestGuide(int client, int args)
{
    RequestGuide(client);
    return Plugin_Continue;
}

Action CmdRecalculate(int client, int args)
{
    Guide_Prep();
    return Plugin_Continue;
}

void Check_Guidable()
{
    gamemode_guidable = !L4D_IsSurvivalMode();
    if (gamemode_guidable && GetEngineVersion()==Engine_Left4Dead2) gamemode_guidable = gamemode_guidable && !L4D2_IsScavengeMode();
    if (!guide_ready && gamemode_guidable) Guide_Prep();
    else if (guide_ready && !gamemode_guidable) Guide_Cleanup();
}

public void OnMapStart()
{
	g_iLaser = PrecacheModel(VMT_LASERBEAM, true);
    RequestFrame(MapStarted);
}

void MapStarted()
{
    map_started = true;
    RequestFrame(Guide_Prep);
}

public void OnMapEnd()
{
    map_started = false;
    Guide_Cleanup();
}

void Guide_Prep()
{
    if (!map_started) return;
    #if DEBUG
        float t = GetEngineTime();
    #endif

    ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
	int totalAreas = allAreas.Length;
    if (totalAreas<1) return;

    float max_flow = L4D2Direct_GetMapMaxFlowDistance();
    if (max_flow<=0.0) return;

    float pos[3];
    float flow;
    Cell cell;

    // Collect nav areas in survivor path
    ArrayList all_cells = new ArrayList(sizeof(Cell));

	for (int i = 0; i < totalAreas; i++)
	{
		Address navArea = allAreas.Get(i);
		if (!navArea) continue;
        if (!(L4D_GetNavArea_SpawnAttributes(navArea) & NAV_SPAWN_ESCAPE_ROUTE)) continue;
        if (L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,true) || L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,false)) continue;
        flow = L4D2Direct_GetTerrorNavAreaFlow(navArea);
        if (flow<0.0 || flow>max_flow) continue;
        L4D_GetNavAreaCenter(navArea,pos);
        pos[2] += 16.0;
        cell.navArea = navArea;
        cell.center = pos;
        cell.flow = flow;
        all_cells.PushArray(cell);
        #if DEBUG>1
            LogMessage("%d %f %f", i, flow, cell.flow);
        #endif
    }

    #if DEBUG
        LogMessage("Initial cell num %d", all_cells.Length);
    #endif

    if (all_cells.Length <= 1)
    {
        delete all_cells;
        return;
    }
    
    // Sort by flow
    all_cells.SortCustom(SortFlow);

    delete g_GuideCells;
    g_GuideCells = new ArrayList(sizeof(Cell));

    // Merge points that are visible with one another
    float last_pos[3];
    Cell cell_last;
    bool last_valid = false;
    for (int i = 0; i < all_cells.Length; i++)
    {
        all_cells.GetArray(i,cell,sizeof(Cell));
        #if DEBUG>1
            LogMessage("%d %f", i, cell.flow);
        #endif
        if (i==0)
        {
            g_GuideCells.Push(cell);
            last_pos = cell.center;
            continue;
        }
        TR_TraceRayFilter(last_pos,cell.center,MASK_SOLID,RayType_EndPoint,TraceFilterWorld);
        if (TR_DidHit(INVALID_HANDLE))
        {
            if (last_valid) g_GuideCells.PushArray(cell_last);
            g_GuideCells.PushArray(cell);
            last_pos = cell.center;
            last_valid = false;
            continue;
        }
        cell_last = cell;
        last_valid = true;
    }

    #if DEBUG
        LogMessage("Final cell num %d", g_GuideCells.Length);
    #endif

    guide_ready = true;
    delete all_cells;

    #if DEBUG
        LogMessage("Guide_Prep: %f ms", (GetEngineTime()-t)*1000.0);
    #endif


}

int SortFlow(int index1, int index2, Handle array, Handle hndl)
{
    float flow1 = view_as<ArrayList>(array).Get(index1,0);
    float flow2 = view_as<ArrayList>(array).Get(index2,0);
    if (flow1 > flow2) return 1;
    else if (flow1 < flow2) return -1;
    return 0;
}

// L4D_GetFlowFromPoint(float point[3]) 

void Guide_Cleanup()
{
    delete g_GuideCells;
    guide_ready = false;
}

// Might be asking forward only, or both directions
void RequestGuide(int client, float duration = 10.0)
{
    #if DEBUG
    float t = GetEngineTime();
    #endif
    if (!gamemode_guidable || !IsValidClient(client)) return;
    if (!guide_ready) Guide_Prep();
    if (!guide_ready || g_GuideCells==null) return;
    #if DEBUG
    float flow = L4D2Direct_GetFlowDistance(client);
    #endif
    //if (flow<0.0) flow = 0.0;
    int i_start = 0;
    float last_pos[3];
    float eye_pos[3];
    GetClientEyePosition(client,eye_pos);
    GetClientAbsOrigin(client,last_pos);
    if (IsPlayerAlive(client)) last_pos[2] += 16.0;
    Cell cell;
    //if (flow<=0.0)
    //{
        float min_dist = -1.0;
        float dist;
        for (int i = 0; i < g_GuideCells.Length; i++)
        {
            g_GuideCells.GetArray(i,cell,sizeof(Cell));
            dist = GetVectorDistance(last_pos,cell.center,true);
            if (min_dist<0.0 || dist<min_dist)
            {
                //if (min_dist>=0.0)
                //{
                //    TR_TraceRayFilter(eye_pos,cell.center,MASK_SOLID,RayType_EndPoint,TraceFilterWorld);
                //    if (TR_DidHit(INVALID_HANDLE)) continue;
                //}
                min_dist = dist;
                i_start = i;
            }
        }
        if (min_dist<0.0) return;
    //}
    float width = 1.0;
    for (int i = i_start; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        //if (cell.flow < flow) continue;
        #if DEBUG
        LogMessage("%d %f %d %f", client, flow, i, cell.flow);
        #endif
        TE_SetupBeamPoints(last_pos,cell.center,g_iLaser,0,0,0,duration,width,width,1,0.0,{100,100,100,255},0);
        TE_SendToClient(client); // no LOS
        last_pos = cell.center;
        //width += 1.0;
    }
    #if DEBUG
        LogMessage("RequestGuide: client %d flow %f, %f ms", client, flow, (GetEngineTime()-t)*1000.0);
    #endif
}

bool TraceFilterWorld(int entity, int contentsMask)
{
    return entity==0;
}

stock bool IsValidClient(int client, bool replaycheck = true)
{
	if (client<1 || client>MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}