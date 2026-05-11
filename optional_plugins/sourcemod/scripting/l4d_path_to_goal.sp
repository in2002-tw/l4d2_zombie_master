#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_NAME			    "l4d_path_to_goal"
#define PLUGIN_VERSION 			"1.00 2026-05-11"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME
#define DEBUG 1 // 1 for basic debug, 2 for details, 3 for EXTREME amount of detail

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

#define MAX_DRAW 64

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
    bool backward = GetClientTeam(client)!=TEAM_SURVIVOR;
    if (!backward && args>0)
    {
        char arg[16];
        GetCmdArg(1,arg,sizeof(arg));
        backward = strcmp(arg,"backward")==0;
    }
    RequestGuide(client,_,backward);
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
    if (gamemode_guidable && GetEngineVersion()==Engine_Left4Dead2) gamemode_guidable = !L4D2_IsScavengeMode();
    if (!guide_ready && gamemode_guidable) RequestFrame(Guide_Prep);
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

// Check round_nav event to recalculate guide

void Guide_Prep()
{
    if (!map_started) return;
    #if DEBUG
        float t = GetEngineTime();
    #endif

    float max_flow = L4D2Direct_GetMapMaxFlowDistance();
    if (max_flow<=0.0) return;

    ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
    if (allAreas.Length<=1)
    {
        delete allAreas;
        return;
    }

    float pos[3];
    float flow;
    Cell cell;

    ArrayList all_cells = new ArrayList(sizeof(Cell)); // Collect nav areas in survivor path
	for (int i = 0; i < allAreas.Length; i++)
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
        #if DEBUG>2
            LogMessage("%d %f %f", i, flow, cell.flow);
        #endif
    }
    
    delete allAreas;

    #if DEBUG
        LogMessage("Initial cell num %d", all_cells.Length);
    #endif

    if (all_cells.Length <= 1)
    {
        delete all_cells;
        return;
    }
    
    all_cells.SortCustom(SortFlow);

    delete g_GuideCells;
    g_GuideCells = new ArrayList(sizeof(Cell));

    float last_pos[3];
    Cell cell_last;
    bool last_valid = false;
    for (int i = 0; i < all_cells.Length; i++) // Merge points that are visible to one another
    {
        all_cells.GetArray(i,cell,sizeof(Cell));
        #if DEBUG>1
            LogMessage("%d %f (%.1f %.1f %.1f)", i, cell.flow, cell.center[0], cell.center[1], cell.center[2]);
        #endif
        if (i==0)
        {
            g_GuideCells.PushArray(cell);
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

    delete all_cells;

    if (g_GuideCells.Length <= 1)
    {
        delete g_GuideCells;
        return;
    }

    #if DEBUG
        LogMessage("Final cell num %d", g_GuideCells.Length);
    #endif

    guide_ready = true;

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

// Draw survivor path for client, for duration in seconds
// backward: include backwards-going path.
// join_client: draw connection between client's origin and nearest point in survivor path.
void RequestGuide(int client, float duration = 10.0, bool backward = false, bool join_client = true)
{
    #if DEBUG
    float t = GetEngineTime();
    #endif
    if (!gamemode_guidable || !IsValidClient(client) || IsFakeClient(client)) return;
    if (!guide_ready) Guide_Prep();
    if (!guide_ready || g_GuideCells==null) return;
    float flow = L4D2Direct_GetFlowDistance(client);
    int i_start = 0;
    static float last_pos[3];
    GetClientAbsOrigin(client,last_pos);
    if (IsPlayerAlive(client)) last_pos[2] += 16.0;
    static Cell cell;
    bool use_flow = flow>0.0 && IsPlayerAlive(client);
    float min_dist = -1.0;
    float dist;
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        if (use_flow && cell.flow >= flow)
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

    // Move start backwards by 1 cell if there's no LOS
    if (i_start>0)
    {
        static float eye_pos[3];
        GetClientEyePosition(client,eye_pos);
        TR_TraceRayFilter(eye_pos,cell.center,MASK_SOLID,RayType_EndPoint,TraceFilterWorld);
        if (TR_DidHit(INVALID_HANDLE)) i_start -= 1;
    }

    int i_draw = 0;

    if (join_client)
    {
        g_GuideCells.GetArray(i_start,cell,sizeof(Cell));
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
            DrawBeam(client,pos_forward,cell.center,duration,{100,200,100,100});
            pos_forward = cell.center;
            end = false;
            i_draw += 1;
        }
        if (backward && i_backward>0)
        {
            i_backward -= 1;
            g_GuideCells.GetArray(i_backward,cell,sizeof(Cell));
            #if DEBUG>1
                LogMessage("%d, %.1f %.1f %.1f", i_backward, cell.center[0], cell.center[1], cell.center[2]);
            #endif
            DrawBeam(client,pos_backward,cell.center,duration,{200,100,100,100});
            pos_backward = cell.center;
            end = false;
            i_draw += 1;
        }
        if (i_draw>=MAX_DRAW) break;
    }
    #if DEBUG
        LogMessage("RequestGuide: client %d flow %f, %f ms", client, flow, (GetEngineTime()-t)*1000.0);
    #endif
}

void DrawBeam(int client, float pos_start[3], float pos_end[3], float duration = 10.0, int color[4] = {100,100,100,255})
{
    float width = 1.0;
    TE_SetupBeamPoints(pos_start,pos_end,g_iLaser,0,0,0,duration,width,width,1,0.0,color,0);
    TE_SendToClient(client); // no LOS
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