#if defined _ptg_inc_included
 #endinput
#endif
#define _ptg_inc_included

/**
 * Draw survivor escape path in L4D1 or L4D2.
 *
 * @param client       Client entity index for which to draw beams. Must be a real client in the server.
 * @param duration     Beam lifetime.
 * @param backward     Draw backwards-going path.
 * @param join_client  Visually connect client origin to nearest point in survivor path.
 */
native void L4D_Path_To_Goal(int client = -1, float duration = 5.0, bool backward = false, bool join_client = true);

#if defined _NATIVE_ONLY
 #endinput
#endif

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <files>
#include <left4dhooks>

#define DEBUG 1 // 1 for basic debug, 2 for details, 3 for EXTREME amount of detail

#define TEAM_SPECTATOR		1
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3
#define VMT_LASERBEAM       "sprites/laserbeam.vmt"
#define MAX_DRAW            32

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

// Data structure for guide points
enum struct PlayerTime
{
	float t_engine;
    float t_game;
    float t_cooldown;
}
PlayerTime g_PlayerTime[MAXPLAYERS+1];

// Check if client is on cooldown for drawing beams
bool beams_cooldown(int client)
{
    static PlayerTime playertime;
    playertime = g_PlayerTime[client];
    if (playertime.t_engine<0.0 && playertime.t_game<0.0) return false;
    if ( (playertime.t_engine+playertime.t_cooldown/2.0)>=GetEngineTime() ) return true;
    if ( (playertime.t_game+playertime.t_cooldown/2.0)>=GetGameTime() ) return true;
    return false;
}

// Client just rendered beams for given duration.
void beams_cooldown_update(int client, float duration = -1.0)
{
    static PlayerTime playertime;
    playertime = g_PlayerTime[client];
    if (duration < 0.0)
    {
        duration = playertime.t_cooldown;
        if (duration < 0.0) return;
    }
    playertime.t_engine = GetEngineTime();
    playertime.t_game = GetGameTime();
    playertime.t_cooldown = duration;
    g_PlayerTime[client] = playertime;
}

// Reset all beam cooldowns. If client is specified, reset only for that client
void beams_cooldown_reset(int client = -1)
{
    static PlayerTime playertime;
    if (client>0)
    {
        playertime = g_PlayerTime[client];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[client] = playertime;
        return;
    }
    for (int i = 1; i <= MaxClients; i++)
    {
        playertime = g_PlayerTime[i];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[i] = playertime;
    }
}

void Check_Guidable()
{
    gamemode_guidable = !L4D_IsSurvivalMode();
    if (gamemode_guidable && GetEngineVersion()==Engine_Left4Dead2) gamemode_guidable = !L4D2_IsScavengeMode();
    if (!guide_ready && gamemode_guidable) RequestFrame(Guide_Prep);
    else if (guide_ready && !gamemode_guidable) Guide_Cleanup();
}

void Guide_Prep()
{
    if (!map_started || !gamemode_guidable) return;
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
        bool hit = TR_DidHit(INVALID_HANDLE);
        if (hit && !cell_rescue(all_cells,g_GuideCells,i))
        {    
            if (last_valid) g_GuideCells.PushArray(cell_last);
            g_GuideCells.PushArray(cell);
            last_pos = cell.center;
            last_valid = false;
            continue;
        }
        if (hit) g_GuideCells.GetArray(g_GuideCells.Length-1,cell_last,sizeof(Cell)); // last cell may have been updated by rescue
        else cell_last = cell;
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

    beams_cooldown_reset();
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
    TR_TraceRayFilter(pos,cell.center,MASK_SOLID,RayType_EndPoint,TraceFilterNoClients);
    if (!TR_DidHit(INVALID_HANDLE)) return true;
    return false;
}

bool TraceFilterWorld(int entity, int contentsMask)
{
    return entity==0;
}

bool TraceFilterNoClients(int entity, int contentsMask)
{
    if (IsValidClient(entity)) return false;
    return true;
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

