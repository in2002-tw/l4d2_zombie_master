#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d_path_to_goal>



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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("L4D_Path_To_Goal", Native_RequestGuide);
	return APLRes_Success;
}

void Native_RequestGuide(Handle plugin, int numParams)
{
    int client = (numParams>0) ? GetNativeCell(1) : 0;
    float duration = (numParams>1) ? view_as<float>(GetNativeCell(2)) : -1.0;
    bool backward = (numParams>2) ? view_as<bool>(GetNativeCell(3)) : false;
    bool join_client = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : false;
    RequestGuide(client,duration,backward,join_client);
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

    HookEvent("round_start_post_nav", evtNav, EventHookMode_PostNoCopy);
    //  nav_blocked
    //  nav_generate

}

void evtNav(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
        LogMessage("round_start_post_nav");
    #endif
    Guide_Cleanup();
    RequestFrame(Check_Guidable);
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

Action CmdRequestGuide(int client, int args)
{
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

public void OnClientPutInServer(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    reset_PlayerTime(client);
}

void Guide_Prep()
{
    if (!map_started) return;
    #if DEBUG
        float t = GetEngineTime();
    #endif

    #if DEBUG
        LogMessage("Guide_Prep");
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
        if (TR_DidHit(INVALID_HANDLE) && !cell_rescue(all_cells,g_GuideCells,i))
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

    reset_PlayerTime();
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

#define RESCUE_FAIL 0
#define RESCUE_INSERT 1
#define RESCUE_MOVE 2

// Two cells cannot see each other. Attempt to fix this.
int cell_rescue(ArrayList cells, int i1, int i2)
{
    return RESCUE_FAIL;
    static Cell cell1,cell2;
    cells.GetArray(i1,cell1,sizeof(Cell));
    cells.GetArray(i2,cell2,sizeof(Cell));

    // // Place new cell inbetween

    // or // Adjust prior cell to recover LOS

    // L4D_GetFlowFromPoint(float point[3])
    // Make sure INSERT has flow inbetween the two original cells.
}

void Guide_Cleanup()
{
    #if DEBUG
        LogMessage("Guide_Cleanup");
    #endif
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
    if (!gamemode_guidable || duration<=0.0 || !IsValidClient(client) || IsFakeClient(client)) return;
    if (!guide_ready) Guide_Prep();
    if (!guide_ready || g_GuideCells==null) return;
    //if (playertime_cooldown(g_PlayerTime[client])) return;
    float flow = L4D2Direct_GetFlowDistance(client);
    int i_start = 0;
    static float last_pos[3];
    if (IsPlayerAlive(client))
    {
        GetClientAbsOrigin(client,last_pos);
        last_pos[2] += 16.0;
    }
    else
    {
        GetClientEyePosition(client,last_pos);
        last_pos[2] -= 16.0;
    }
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

    static float eye_pos[3]; // Move start if there's no LOS
    GetClientEyePosition(client,eye_pos);
    if (!cell_visible(i_start,eye_pos))
    {
        if ((i_start+1)<g_GuideCells.Length && cell_visible(i_start+1,eye_pos)) i_start += 1; // Move forward
        else if (i_start>0 && cell_visible(i_start-1,eye_pos)) i_start -=1; // Move backward
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
    if (i_draw>0) playertime_update(client,duration);
    #if DEBUG
        LogMessage("RequestGuide: client %d flow %f, %f ms", client, flow, (GetEngineTime()-t)*1000.0);
    #endif
}

void DrawBeam(int client, float pos_start[3], float pos_end[3], float duration = 10.0, int color[4] = {100,100,100,255})
{
    float start_width = 1.0;
    float end_width = 1.0;
    int fade_length = 1;
    float amp = 0.0;
    TE_SetupBeamPoints(pos_start,pos_end,g_iLaser,0,0,0,duration,start_width,end_width,fade_length,amp,color,0);
    TE_SendToClient(client); // no LOS
}

// Test if cell is visible from given position
bool cell_visible(int i, float pos[3])
{
    static Cell cell;
    g_GuideCells.GetArray(i,cell,sizeof(Cell));
    TR_TraceRay(pos,cell.center,MASK_SOLID,RayType_EndPoint);
    if (!TR_DidHit(INVALID_HANDLE)) return true;
    return false;
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