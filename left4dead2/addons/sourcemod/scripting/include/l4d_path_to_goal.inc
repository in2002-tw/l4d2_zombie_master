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

#if defined _ptg_inc_included
 #endinput
#endif
#define _ptg_inc_included

/**
 * Draw survivor escape path in L4D1 or L4D2.
 *
 * @param client       Client entity index for which to draw beams. Must be a real in game client.
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
#include <left4dhooks>

#define DEBUG 1 // 1 for basic debug, 2 for details, 3 for EXTREME amount of detail

#define NAV_COOLDOWN 3.0 // GameTime cooldown after nav events fire before Guide_Prep can be requested

#define TEAM_SPECTATOR		1
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3

#define VMT_LASERBEAM       "sprites/laserbeam.vmt"

#define ACCEPT_ALL   0 // accept all players
#define ACCEPT_ALIVE 1 // accept only alive players
#define ACCEPT_DEAD  2 // accept only non-alive players

// Data structure for guide points
enum struct Cell
{
	float flow;
    Address navArea;
	float center[3]; // cell position slightly above ground
}

ArrayList g_GuideCells;
ConVar g_hCvarMPGameMode, g_hCvarEnable, g_hCvarMax, g_hCvarSurvivors, g_hCvarInfected, g_hCvarSpec, g_hCvarAlive, g_hCvarBudget;
bool gamemode_guidable, guide_ready, guide_prep, map_started, nav_started, enable;
int g_iLaser;
float t_nav = -1.0; // nav event gametime
Handle timer_nav;

bool is_prep_cooldown()
{
    if (t_nav<=0.0) return false;
    if ((t_nav+NAV_COOLDOWN)>GetGameTime()) return true;
    return false;
}

void GetCvars()
{
    if (enable != g_hCvarEnable.BoolValue)
    {
        t_nav = -1.0;
        enable = g_hCvarEnable.BoolValue;
        if (!enable && guide_ready) Guide_Cleanup();
        beams_cooldown_reset(_,true); // reset all requests and cooldowns
    }
}

// Player cooldown
enum struct PlayerTime
{
	float t_engine;
    float t_game;
    float t_cooldown;
}
PlayerTime g_PlayerTime[MAXPLAYERS+1];

// Data structure for requests to draw beams
enum struct CellRequest
{
	float duration;
    bool backward;
	bool join_client;
}
CellRequest g_CellRequests[MAXPLAYERS+1];

Action Timer_CheckRequests(Handle timer)
{
    if (timer != timer_nav) return Plugin_Stop;
    float t_left = (t_nav+NAV_COOLDOWN) - GetGameTime();
    if (t_left>0.0)
    {
        if (t_left<0.1) t_left = 0.1;
        timer_nav = CreateTimer(t_left,Timer_CheckRequests,_,TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    timer_nav = null;
    #if DEBUG>1
    LogMessage("Timer_CheckRequests");
    #endif
    if (!enable || !gamemode_guidable || g_iLaser==0 || guide_prep) return Plugin_Stop;
    for (int i = 1; i <= MaxClients; i++) // Draw beams immediately for pending clients
    {
        if (g_CellRequests[i].duration <= 0.0) continue;
        if (!IsValidClient(i) || IsFakeClient(i))
        {
            g_CellRequests[i].duration = -1.0;
            continue;
        }
        if (guide_ready)
        {
            static CellRequest request;
            request = g_CellRequests[i];
            RequestGuide(i,request.duration,request.backward,request.join_client);
        }
        else
        {
            Guide_Prep();
            break;
        }
    }
    return Plugin_Stop;
}

int g_iStart;

// Draw survivor path for client, for duration in seconds
// backward: include backwards-going path.
// join_client: draw connection between client's origin and nearest point in survivor path.
void RequestGuide(int client, float duration = 5.0, bool backward = false, bool join_client = true)
{
    #if DEBUG>2
    float t = GetEngineTime();
    #endif
    if (!enable || !gamemode_guidable || duration<=0.0 || g_iLaser==0 || !IsValidClient(client) || IsFakeClient(client)) return;

    switch (GetClientTeam(client)) // Check if team is blocked
    {
        case TEAM_SPECTATOR:
        {
            if (!g_hCvarSpec.BoolValue) return;
        }
        case TEAM_SURVIVOR:
        {
            if (!g_hCvarSurvivors.BoolValue) return;
        }
        case TEAM_INFECTED:
        {
            if (!g_hCvarInfected.BoolValue) return;
        }
    }

    bool alive = IsPlayerAlive(client);

    if (g_hCvarAlive.IntValue>0) // 0 -> all states allowed
    {
        switch (alive)
        {
            case true:
            {
                if (g_hCvarAlive.IntValue == ACCEPT_DEAD) return; // alive state blocked by cvar
            }
            default:
            {
                if (g_hCvarAlive.IntValue == ACCEPT_ALIVE) return; // alive state blocked by cvar
            }
        }
    }

    if (!guide_ready) Guide_Prep(); // Check if guide is ready
    if (!guide_ready || g_GuideCells==null || beams_cooldown(client))
    {
        static CellRequest request;
        request.duration = duration;
        request.backward = backward;
        request.join_client = join_client;
        g_CellRequests[client] = request;
        return;
    }
    

    float flow = 0.0;
    g_iStart = g_GuideCells.Length - 1;
    static float last_pos[3], eye_pos[3];
    GetClientEyePosition(client,eye_pos);
    Address navArea = L4D_GetNearestNavArea(eye_pos,500.0,true,true,true,TEAM_SURVIVOR);
    if (navArea != Address_Null) // Get flow
    {
        L4D_GetNavAreaCenter(navArea,last_pos);
        flow = L4D_GetFlowFromPoint(last_pos);
    }
    
    if (alive) // Get initial beam position
    {
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
        last_pos[2] -= 32.0;
        if (pos_underwater(last_pos)) last_pos[2] += 16.0;
    }

    static Cell cell;
    bool use_flow = flow>0.0;
    float min_dist = -1.0;
    float dist;
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        if ( use_flow && ( cell.flow >= flow ) )
        {
            g_iStart = i;
            break;
        }
        else
        {
            dist = GetVectorDistance(last_pos,cell.center,true);
            if (min_dist<0.0 || dist<min_dist)
            {
                min_dist = dist;
                g_iStart = i;
            }
        }
    }
    if (!use_flow && min_dist<0.0) return;
    
    bool LOS = cell_visible(g_iStart,last_pos);

    // Try starting at a more reasonable position with LOS
    if ( join_client && (g_iStart+1)<g_GuideCells.Length && cell_visible(g_iStart+1,last_pos))
    {
        g_iStart += 1; // Move forward
        LOS = true;
    }
    else if (g_iStart>0 && !LOS && cell_visible(g_iStart-1,last_pos))
    {
        g_iStart -=1; // Move backward
        LOS = true;
    }

    int i_draw = 0;
    g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell));

    if (join_client) // Connect client to starting cell
    {
        int num_beams = (navArea!=Address_Null && !LOS && use_flow && flow<cell.flow) ? detour_join(client,navArea,last_pos,flow,cell.center,cell.flow,duration) : 0;
        if (num_beams<=0)
        {
            DrawBeam(client,last_pos,cell.center,duration);
            i_draw += 1;
        }
        else
        {
            g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell)); // detour_join may have changed g_iStart
            i_draw += num_beams;
        }
    }

    int i_forward = g_iStart;
    int i_backward = g_iStart;
    static float pos_forward[3], pos_backward[3];
    pos_forward = cell.center;
    pos_backward = cell.center;
    bool end = false;
    while (!end && i_draw<g_hCvarMax.IntValue)
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
            if (i_draw>=g_hCvarMax.IntValue) break;
        }
        if (backward && i_backward>0)
        {
            i_backward -= 1;
            g_GuideCells.GetArray(i_backward,cell,sizeof(Cell));
            DrawBeam(client,pos_backward,cell.center,duration,{200,100,100,100});
            pos_backward = cell.center;
            end = false;
            i_draw += 1;
        }
    }
    if (i_draw>0) beams_cooldown_update(client,duration);
    #if DEBUG>2
        LogMessage("RequestGuide: client %d flow %f cells %d g_iStart %d (%f ms)", client, flow, i_draw, g_iStart, (GetEngineTime()-t)*1000.0);
    #endif
}

// Find closest guide cell for given flow value. 
// If check_LOS, wiggle cell forward/backward to improve LOS for given vector position
int get_flow_iStart(float flow, bool check_LOS = true, float pos[3])
{
    int i_start = 0;
    static Cell cell;
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        if ( cell.flow >= flow )
        {
            i_start = i;
            break;
        }
    }
    if (check_LOS)
    {
        if ((i_start+1)<g_GuideCells.Length && cell_visible(i_start+1,pos))
        {
            i_start += 1; // Move forward
        }
        else if (i_start>0 && !cell_visible(i_start,pos) && cell_visible(i_start-1,pos))
        {
            i_start -=1; // Move backward
        }
    }
    return i_start;
}

#define DETOUR_BUDGET_MS 1.0

// detour client_join, return how many beams were drawn
int detour_join(int client, Address navArea, float pos[3], float flow, float pos_end[3], float flow_end, float duration)
{
    float t = GetEngineTime();

    static float pos_curr[3];
    float flow_curr = flow;
    pos_curr = pos;
    ArrayList adjAreas = new ArrayList();
    ArrayList queue = new ArrayList(3);
    queue.PushArray(pos);
        
    Address navArea_curr = navArea;
    float flow_temp;
    static float pos_temp[3];

    bool success = false;
    while (navArea_curr != Address_Null)
    {
        bool found = false;
        for (int dir = 0; dir < 4; dir++) // Enqueue adjacent nav areas (all 4 directions)
        {
            if ( ((GetEngineTime()-t)*1000.0) >= DETOUR_BUDGET_MS )
            {
                #if DEBUG>1
                LogMessage("detour_join exceeded budget");
                #endif
                return 0;
            }
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea_curr, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                Address adjArea = adjAreas.Get(i);
                if (adjArea == Address_Null) continue;
                L4D_GetNavAreaCenter(adjArea,pos_temp);
                flow_temp = L4D_GetFlowFromPoint(pos_temp);
                if (flow_temp<=flow_curr) continue;
                //if (!L4D_NavArea_IsConnected(adjArea,navArea_curr,-1)) continue;
                //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                pos_temp[2] += 16.0;
                if (pos_underwater(pos_temp)) pos_temp[2] += 32.0;
                //if (!twopos_visible(pos_curr,pos_temp)) continue;
                found = true;
                navArea_curr = adjArea;
                pos_curr = pos_temp;
                flow_curr = flow_temp;
                if (queue.Length>1)
                {
                    static float pos_last[3];
                    queue.GetArray(queue.Length-2,pos_last,3);
                    if (twopos_visible(pos_curr,pos_last)) queue.SetArray(queue.Length-1,pos_curr,3);
                    else queue.PushArray(pos_curr);
                }
                else queue.PushArray(pos_curr);
                if (L4D_GetNavArea_SpawnAttributes(navArea_curr) & NAV_SPAWN_ESCAPE_ROUTE)
                {
                    g_iStart = get_flow_iStart(flow_curr,true,pos_curr);
                    static Cell cell;
                    g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell));
                    pos_end = cell.center;
                    success = true;
                    break;
                }
                break;
            }
            if (found || success) break;
        }
        
        if (!found || success) break;
        if (found && flow_curr <= flow_end && twopos_visible(pos_curr,pos_end))
        {
            success = true;
            break;
        }

    }

    int beams = 0; 
    if (success) // Path found, draw beams.
    {
        queue.GetArray(0,pos_curr,3);
        for (int i = 1; i < queue.Length; i++)
		{
			queue.GetArray(i,pos_temp,3);
            DrawBeam(client,pos_curr,pos_temp,duration);
            pos_curr = pos_temp;
            beams += 1;
            if (beams>=g_hCvarMax.IntValue) break;
        }
        if (beams<g_hCvarMax.IntValue)
        {
            DrawBeam(client,pos_curr,pos_end,duration);
            beams += 1;
        }
    }

    delete adjAreas;
    delete queue;

    #if DEBUG>1
    LogMessage("detour_join %f ms", (GetEngineTime()-t)*1000.0);
    #endif

    return beams;
}

void DrawBeam(int client, float pos_start[3], float pos_end[3], float duration = 10.0, int color[4] = {100,200,100,100})
{
    if (g_iLaser==0) return;
    float start_width = 1.0;
    float end_width = 1.0;
    int fade_length = 1;
    float amp = 0.0;
    TE_SetupBeamPoints(pos_start,pos_end,g_iLaser,0,0,0,duration,start_width,end_width,fade_length,amp,color,0);
    TE_SendToClient(client); // no LOS
}

void Check_Guidable()
{
    gamemode_guidable = !L4D_IsSurvivalMode();
    if (gamemode_guidable && GetEngineVersion()==Engine_Left4Dead2) gamemode_guidable = !L4D2_IsScavengeMode();
    if (!map_started || !nav_started) return;
    if (guide_ready && !gamemode_guidable) Guide_Cleanup();
}

#define STAGE_NONE 0
#define STAGE_PREP 1
#define STAGE_COLLECT 2
#define STAGE_SORT 3
#define STAGE_BUILD 4
#define STAGE_VALIDATE 5
#define STAGE_END 6

int g_iPrepStage, g_iPrepFrames, g_iLoop, g_iErased, g_iNavBlocked;
float g_fPrepTotalTime, g_fMaxFlow, g_fFlowStart, g_fFlowCheckpoint, g_tFrameStart;
ArrayList allAreas, all_cells;
bool g_bMissingStart, g_bMissingCheckpoint, g_bFoundStart, g_bFoundCheckpoint;
Address g_aNavStart, g_aNavCheckpoint;

void Guide_Prep()
{
    if (!enable || !gamemode_guidable || !map_started || !nav_started || guide_prep || is_prep_cooldown()) return;
    #if DEBUG>1
    LogMessage("Guide_Prep");
    #endif
    guide_prep = true;
    g_iPrepStage = STAGE_PREP;
    g_iPrepFrames = 0;
    timer_nav = null;
    OnFramePrep(true);
}

void Guide_Cleanup()
{
    g_iPrepStage = STAGE_NONE;
    if (guide_ready)
    {
        #if DEBUG>1
        LogMessage("Guide_Cleanup");
        #endif
        guide_ready = false;
        delete g_GuideCells;
    }
}

bool frame_budget_exceeded()
{
    if (g_hCvarBudget.FloatValue <= 0.0) return false;
    float dt_ms = (GetEngineTime()-g_tFrameStart)*1000.0;
    bool exceeded = dt_ms >= g_hCvarBudget.FloatValue;
    return exceeded;
}

void OnFramePrep(bool new_frame = true)
{
    if (!enable || guide_ready || !gamemode_guidable || !map_started || !nav_started || g_iPrepStage<=STAGE_NONE || g_iPrepStage>=STAGE_END)
    {
        guide_prep = false;
        g_iPrepStage = STAGE_NONE;
        timer_nav = null;
        return;
    }
    static float pos[3];
    float flow;
    static Cell cell;
    if (new_frame)
    {
        g_iPrepFrames += 1;
        g_tFrameStart = GetEngineTime();
    }
    switch (g_iPrepStage)
    {
        case STAGE_PREP:
        {
            g_fPrepTotalTime = 0.0;
            g_fMaxFlow = L4D2Direct_GetMapMaxFlowDistance();
            if (g_fMaxFlow<=0.0)
            {
                guide_prep = false;
                return;
            }

            delete allAreas;
            allAreas = new ArrayList();
            L4D_GetAllNavAreas(allAreas);
            if (allAreas.Length<=1)
            {
                delete allAreas;
                guide_prep = false;
                return;
            }

            delete all_cells;
            all_cells = new ArrayList(sizeof(Cell)); // Collect nav areas in survivor path
            
            delete g_GuideCells;
            g_GuideCells = new ArrayList(sizeof(Cell));

            g_bMissingStart = true; // do we have a confirmed start area navmesh in g_GuideCells?
            g_bMissingCheckpoint = true; // do we have a confirmed end area navmesh in g_GuideCells?
            
            g_bFoundStart = false;
            g_bFoundCheckpoint = false;
            
            g_fFlowStart = g_fMaxFlow;
            g_fFlowCheckpoint = 0.0;

            g_iLoop = 0;
            g_iErased = 0;
            g_iNavBlocked = 0;
        }
        case STAGE_COLLECT:
        {
            if (allAreas==null || all_cells==null)
            {
                guide_prep = false;
                return;
            }
            while (g_iLoop<allAreas.Length)
            {
                if (frame_budget_exceeded())
                {
                    RequestFrame(OnFramePrep,true);
                    g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
                    return;
                }
                Address navArea = allAreas.Get(g_iLoop);
                g_iLoop += 1;
                if (!navArea) continue;
                if (L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,true) || L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,false))
                {
                    g_iNavBlocked += 1;
                    continue;
                }
                L4D_GetNavAreaCenter(navArea,pos);
                flow = L4D_GetFlowFromPoint(pos);
                if (flow>g_fMaxFlow) continue;
                int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
                if (navSpawnAttrs & NAV_SPAWN_ESCAPE_ROUTE)
                {
                    if (flow<=0.0) continue;
                    if (all_cells.FindValue(flow,0)>=0) continue; // if identical flow exists, ignore this cell
                    pos[2] += 16.0;
                    if (pos_underwater(pos))
                    {
                        pos[2] += 16.0;
                        if (pos_underwater(pos))
                        {
                            pos[2] += 16.0;
                            if (pos_underwater(pos)) continue;
                        }
                    }
                    cell.navArea = navArea;
                    cell.center = pos;
                    cell.flow = flow;
                    all_cells.PushArray(cell);
                    if (navSpawnAttrs & NAV_SPAWN_PLAYER_START) g_bMissingStart = false;
                    if (navSpawnAttrs & NAV_SPAWN_CHECKPOINT) g_bMissingCheckpoint = false;
                    #if DEBUG>2
                        LogMessage("%d %f %f", i, flow, cell.flow);
                    #endif
                }
                
                if (navSpawnAttrs & NAV_SPAWN_PLAYER_START) // Find smallest flow starting position
                {
                    if (flow<g_fFlowStart)
                    {
                        g_bFoundStart = true;
                        g_aNavStart = navArea;
                        g_fFlowStart = flow;
                    }
                }
                else if (navSpawnAttrs & NAV_SPAWN_CHECKPOINT) // Find biggest flow ending position
                {
                    if (flow>g_fFlowCheckpoint)
                    {
                        g_bFoundCheckpoint = true;
                        g_aNavCheckpoint = navArea;
                        g_fFlowCheckpoint = flow;
                    }
                }
            }
            
            if (g_bMissingStart && g_bFoundStart && all_cells.FindValue(g_fFlowStart,0)<0)
            {
                cell.navArea = g_aNavStart;
                L4D_GetNavAreaCenter(g_aNavStart,pos);
                pos[2] += 16.0; 
                if (pos_underwater(pos)) pos[2] += 16.0;
                cell.center = pos;
                cell.flow = g_fFlowStart;
                all_cells.PushArray(cell);
            }
            if (g_bMissingCheckpoint && g_bFoundCheckpoint && all_cells.FindValue(g_fFlowCheckpoint,0)<0)
            {
                cell.navArea = g_aNavCheckpoint;
                L4D_GetNavAreaCenter(g_aNavCheckpoint,pos);
                pos[2] += 16.0;
                if (pos_underwater(pos)) pos[2] += 16.0;
                cell.center = pos;
                cell.flow = g_fFlowCheckpoint;
                all_cells.PushArray(cell);
            }

            delete allAreas;

            #if DEBUG>1
                LogMessage("Initial cell num %d", all_cells.Length);
            #endif

            if (all_cells.Length <= 1)
            {
                delete all_cells;
                guide_prep = false;
                return;
            }
        }
        case STAGE_SORT:
        {
            if (all_cells==null || g_GuideCells==null)
            {
                guide_prep = false;
                return;
            }
            all_cells.SortCustom(SortFlow);
            all_cells.GetArray(0,cell,sizeof(Cell));
            g_GuideCells.PushArray(cell);
            g_iLoop = 1;
        }
        case STAGE_BUILD:
        {
            if (all_cells==null || g_GuideCells==null)
            {
                guide_prep = false;
                return;
            }
            while (g_iLoop<all_cells.Length)
            {
                all_cells.GetArray(g_iLoop,cell,sizeof(Cell));
                guide_add_cell(cell);
                g_iLoop += 1;
                if (frame_budget_exceeded())
                {
                    RequestFrame(OnFramePrep,true);
                    g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
                    return;
                }
            }
            delete all_cells;
            if (g_GuideCells.Length <= 1)
            {
                delete g_GuideCells;
                guide_prep = false;
                return;
            }
            g_iLoop = 1;
        }
        case STAGE_VALIDATE:
        {
            if (g_GuideCells !=null && g_GuideCells.Length>2) // Erase inbetween cells with mutual LOS
            {
                static Cell cell_before,cell_after;
                while (g_iLoop<(g_GuideCells.Length-1))
                {
                    g_GuideCells.GetArray(g_iLoop-1,cell_before,sizeof(Cell));
                    g_GuideCells.GetArray(g_iLoop,cell,sizeof(Cell));
                    g_GuideCells.GetArray(g_iLoop+1,cell_after,sizeof(Cell));
                    if (twopos_visible(cell_before.center,cell.center) &&
                        twopos_visible(cell_before.center,cell_after.center) &&
                        twopos_visible(cell.center,cell_after.center))
                    {
                        g_GuideCells.Erase(g_iLoop);
                        g_iErased += 1;
                        continue;
                    }
                    g_iLoop += 1;
                    if (frame_budget_exceeded())
                    {
                        RequestFrame(OnFramePrep,true);
                        g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
                        return;
                    }
                }
            }
        }
        default:
        {
            guide_prep = false;
            return;
        }
    }
    
    g_iPrepStage += 1;

    if (g_iPrepStage>STAGE_NONE && g_iPrepStage<STAGE_END)
    {
        if (frame_budget_exceeded())
        {
            RequestFrame(OnFramePrep,true);
            g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
            return;
        }
        else OnFramePrep(false);
    }
    else
    {
        guide_prep = false;
        guide_ready = true;
        beams_cooldown_reset();
        delete allAreas;
        delete all_cells;
        g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
        #if DEBUG
        LogMessage("Final cell num %d (%d erased, %d blocked) (%f ms %d frames)", g_GuideCells.Length, g_iErased, g_iNavBlocked, g_fPrepTotalTime*1000.0, g_iPrepFrames);
        #endif
        g_iPrepStage = STAGE_NONE;
        timer_nav = null;
        for (int i = 1; i <= MaxClients; i++) // Draw beams immediately for pending clients
        {
            if (g_CellRequests[i].duration <= 0.0) continue;
            if (!IsValidClient(i) || IsFakeClient(i)) continue;
            static CellRequest request;
            request = g_CellRequests[i];
            RequestGuide(i,request.duration,request.backward,request.join_client);
        }
    }

}

void guide_add_cell(Cell cell)
{
    static Cell cell_prev, cell_prev2;
    g_GuideCells.GetArray(g_GuideCells.Length-1,cell_prev,sizeof(Cell)); // last cell
    bool prev2_exists = (g_GuideCells.Length-2)>=0;
    if (prev2_exists) g_GuideCells.GetArray(g_GuideCells.Length-2,cell_prev2,sizeof(Cell)); // cell before last one
    if (twopos_visible(cell.center,cell_prev.center))
    {
        if (prev2_exists && twopos_visible(cell.center,cell_prev2.center)) g_GuideCells.SetArray(g_GuideCells.Length-1,cell,sizeof(Cell));
        else g_GuideCells.PushArray(cell);
    }
    else cell_rescue(g_GuideCells,cell_prev,cell,prev2_exists,cell_prev2); // Try adding cell inbetween to recover LOS.
}

// Two cells cannot see each other. Attempt to remedy this
void cell_rescue(ArrayList cells, Cell cell_old, Cell cell_new, bool prev2_exists, Cell cell_prev2)
{
    static Cell cell;
    ArrayList pos_candidates = new ArrayList(3);

    // cell_new and cell_old do not have LOS

    static float diff[3], diff_candidate[3], diff_template[3], pos_candidate[3], pos_template[3];
    SubtractVectors(cell_new.center,cell_old.center,diff);
    diff_candidate = diff;

    bool flat = FloatAbs(diff[2])<=1.0; // flat -> nothing to do in z direction
    int i_turns_flat = 1;
    if (!flat) i_turns_flat += 1; // two turns if not flat
    int i_turns_mid = 2; // one cycle at old cell, then one cycle at midpoint

    for (int i_turn_flat = 0; i_turn_flat < i_turns_flat; i_turn_flat++)
    {
        diff_template = diff;
        if (i_turn_flat==1) diff_template[2] = 0.0;
        for (int i_turn_mid = 0; i_turn_mid < i_turns_mid; i_turn_mid++) 
        {
            if (i_turn_mid==1) // Try wiggling at midpoint
            {
                diff_candidate = diff; ScaleVector(diff_candidate,0.5);
                AddVectors(cell_old.center,diff_candidate,pos_template);
            }
            else pos_template = cell_old.center;

            if (i_turn_mid==0)
            {
                diff_candidate = diff_template; ScaleVector(diff_candidate,0.5); // half
                AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            }

            diff_candidate = diff_template; diff_candidate[0] = 0.0; // dy
            AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            diff_candidate[1] *= 0.5; // dy/2
            AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            
            diff_candidate = diff_template; diff_candidate[1] = 0.0; // dx
            AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            diff_candidate[0] *= 0.5; // dx/2
            AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            
            diff_candidate = diff_template; ScaleVector(diff_candidate,0.25); // quarter
            AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);

            if (!flat && i_turn_flat==0) // z is not flat
            {
                diff_candidate = diff_template; diff_template[0] = 0.0; diff_template[1] = 0.0; // dz
                AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
                diff_candidate[2] *= 0.5; // dz/2
                AddVectors(pos_template,diff_candidate,pos_candidate); pos_candidates.PushArray(pos_candidate);
            }

            // Try small static wiggles
            AddVectors(pos_template,{16.0,0.0,0.0},pos_candidate); pos_candidates.PushArray(pos_candidate);
            AddVectors(pos_template,{-16.0,0.0,0.0},pos_candidate); pos_candidates.PushArray(pos_candidate);
            AddVectors(pos_template,{0.0,16.0,0.0},pos_candidate); pos_candidates.PushArray(pos_candidate);
            AddVectors(pos_template,{0.0,-16.0,0.0},pos_candidate); pos_candidates.PushArray(pos_candidate);
            AddVectors(pos_template,{0.0,0.0,16.0},pos_candidate); pos_candidates.PushArray(pos_candidate);
            AddVectors(pos_template,{0.0,-0.0,-16.0},pos_candidate); pos_candidates.PushArray(pos_candidate);

        }
    }

    for (int i = 0; i < pos_candidates.Length; i++) 
    {
        pos_candidates.GetArray(i,pos_candidate,sizeof(pos_candidate));
        if (!twopos_visible(cell_new.center,pos_candidate)) continue;
        if (!twopos_visible(cell_old.center,pos_candidate)) continue;
        float d_flow = GetVectorDistance(cell_old.center,pos_candidate);
        cell.flow = cell_old.flow + d_flow;
        if (cell.flow>=cell_new.flow) cell.flow = (cell_old.flow + cell_new.flow)/2.0;
        cell.navArea = cell_old.navArea;
        cell.center = pos_candidate;
        if (prev2_exists && twopos_visible(cell.center,cell_prev2.center)) cells.SetArray(cells.Length-1,cell,sizeof(Cell));
        else cells.PushArray(cell);
        break;
    }
    cells.PushArray(cell_new);
    delete pos_candidates;
}

// Check if client is on cooldown for drawing beams
bool beams_cooldown(int client)
{
    //if (playertime.t_engine<0.0 && playertime.t_game<0.0) return false;
    if (g_PlayerTime[client].t_game<0.0) return false;
    //if ( (playertime.t_engine+playertime.t_cooldown/2.0)>=GetEngineTime() ) return true;
    if ( (g_PlayerTime[client].t_game+g_PlayerTime[client].t_cooldown)>GetGameTime() ) return true;
    return false;
}

// Client just rendered beams for given duration. Set cooldown to half the duration.
void beams_cooldown_update(int client, float duration = -1.0)
{
    static PlayerTime playertime;
    playertime = g_PlayerTime[client];
    if (duration < 0.0)
    {
        duration = playertime.t_cooldown;
        if (duration < 0.0) return;
    }
    else duration /= 2.0;
    //playertime.t_engine = GetEngineTime();
    playertime.t_game = GetGameTime();
    playertime.t_cooldown = duration;
    g_PlayerTime[client] = playertime;
    g_CellRequests[client].duration = -1.0;
}

// Reset all beam cooldowns. If client is specified, reset only for that client
// If request, reset beam requests too
void beams_cooldown_reset(int client = -1, bool request = false)
{
    if (!enable || !guide_ready) return;
    static PlayerTime playertime;
    if (client>0)
    {
        playertime = g_PlayerTime[client];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[client] = playertime;
        if (request) g_CellRequests[client].duration = -1.0;
        return;
    }
    for (int i = 1; i <= MaxClients; i++)
    {
        playertime = g_PlayerTime[i];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[i] = playertime;
        if (request) g_CellRequests[i].duration = -1.0;
    }
}

int SortFlow(int index1, int index2, Handle array, Handle hndl)
{
    float flow1 = view_as<ArrayList>(array).Get(index1,0);
    float flow2 = view_as<ArrayList>(array).Get(index2,0);
    if (flow1 > flow2) return 1;
    else if (flow1 < flow2) return -1;
    return 0;
}

// Test if cell is visible from given position
bool cell_visible(int i, float pos[3], bool world_only = true)
{
    static Cell cell;
    g_GuideCells.GetArray(i,cell,sizeof(Cell));
    return twopos_visible(pos,cell.center,world_only);
}

// Test if two vector positions are visible to one another. world_only to hit only entity 0.
bool twopos_visible(float pos1[3], float pos2[3], bool world_only = true)
{
    if (world_only) TR_TraceRayFilter(pos1,pos2,MASK_SOLID,RayType_EndPoint,TraceFilterWorld);
    else TR_TraceRayFilter(pos1,pos2,MASK_SOLID,RayType_EndPoint,TraceFilterNoClients);
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

stock bool pos_underwater(const float pos[3])
{
	static float top[3], bottom[3];
    bottom = pos;
    top = pos; top[2] += 64.0;
	TR_TraceRay(top,bottom,MASK_WATER,RayType_EndPoint);
	if (TR_DidHit(INVALID_HANDLE)) return true;
    return false;
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

