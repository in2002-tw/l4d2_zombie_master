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
//#define VMT_LASERBEAM       "sprites/bubble.vmt"
//#define VMT_LASERBEAM       "sprites/white.vmt"

ConVar g_hCvarAlive;
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
ConVar g_hCvarMPGameMode, g_hCvarEnable, g_hCvarMax, g_hCvarSurvivors, g_hCvarInfected, g_hCvarSpec, g_hCvarBudget, g_hCvarFinaleAuto;
//ConVar g_hCvarDz;
bool gamemode_guidable, guide_ready, guide_prep, map_started, nav_started, enable, g_bL4D2, finale, finale_rescue, finale_gauntlet;
int g_iLaser;
float t_nav = -1.0; // nav event gametime
Handle timer_nav;

bool finale_stitched; // finale guide was drawn
bool finale_backwards; // rescue vehicle is not at max flow -> flow cannot be used for guiding

ConVar g_hCvarFinale;
#define FINALE_ALWAYS 0 
#define FINALE_STARTED 1
#define FINALE_RESCUE 2
#define FINALE_NEVER 3
bool g_bFoundRescueVehicle;
float g_fFlowRescueVehicle;

bool is_prep_cooldown() // Prevent Guide_Prep() from firing if navmesh just changed
{
    if (t_nav<=0.0 || finale_rescue) return false;
    if ((t_nav+NAV_COOLDOWN)>GetGameTime()) return true;
    return false;
}

void GetCvars()
{
    if (enable != g_hCvarEnable.BoolValue)
    {
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

// Check if any client has a request queued after nav cooldown has expired or guide is ready to draw beams.
Action Timer_CheckRequests(Handle timer = null)
{
    // If both handles are null, allow to pass. Otherwise only allow expected handle through.
    if ( (timer != null || timer_nav != null) &&  timer != timer_nav) return Plugin_Stop;
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
    if (!enable || !map_started || !nav_started || !gamemode_guidable || g_iLaser==0 || guide_prep) return Plugin_Stop;
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

// Draw beams for all clients
void Guide_All_Clients()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_CellRequests[i].duration = 5.0;
    }
    Timer_CheckRequests(null);
}

int g_iStart;
float g_RequestFirstPos[3]; // for hint system

// Draw survivor path for client, for duration in seconds
// backward: include backwards-going path.
// join_client: draw connection between client's origin and nearest point in survivor path.
// return true if beams were drawn
bool RequestGuide(int client, float duration = 5.0, bool backward = false, bool join_client = true)
{
    #if DEBUG>2
    float t = GetEngineTime();
    #endif
    if (!enable || !map_started || !nav_started || !gamemode_guidable || duration<=0.0 || g_iLaser==0 || !IsValidClient(client) || IsFakeClient(client)) return false;

    switch (GetClientTeam(client)) // Check if team is blocked
    {
        case TEAM_SPECTATOR:
        {
            if (!g_hCvarSpec.BoolValue) return false;
        }
        case TEAM_SURVIVOR:
        {
            if (!g_hCvarSurvivors.BoolValue) return false;
        }
        case TEAM_INFECTED:
        {
            if (!g_hCvarInfected.BoolValue) return false;
        }
    }

    bool alive = IsPlayerAlive(client);

    if (g_hCvarAlive.IntValue>0) // 0 -> all states allowed
    {
        switch (alive)
        {
            case true:
            {
                if (g_hCvarAlive.IntValue == ACCEPT_DEAD) return false; // alive state blocked by cvar
            }
            default:
            {
                if (g_hCvarAlive.IntValue == ACCEPT_ALIVE) return false; // alive state blocked by cvar
            }
        }
    }

    if (beams_cooldown(client)) return false;

    if (duration < 0.1) duration = 0.1; // prevent beams with infinite lifetime

    if (!guide_ready)
    {
        Guide_Prep();
        if (!guide_ready || g_GuideCells==null)
        {
            static CellRequest request;
            request.duration = duration;
            request.backward = backward;
            request.join_client = join_client;
            g_CellRequests[client] = request;
            return false;
        }
    }

    float flow = 0.0;
    g_iStart = g_GuideCells.Length - 1;
    static float last_pos[3], eye_pos[3], origin[3];
    GetClientAbsOrigin(client,origin);
    GetClientEyePosition(client,eye_pos);
    Address navArea = L4D_GetNearestNavArea(origin,500.0,true,true,true,TEAM_SURVIVOR);
    if (navArea == Address_Null)
    {
        // search for navareas within radius of client origin... native not available yet
    }
    if (navArea != Address_Null) // Get flow
    {
        L4D_GetNavAreaCenter(navArea,last_pos);
        flow = L4D_GetFlowFromPoint(last_pos);
    }
    
    if (alive) // Get initial beam position
    {
        last_pos = origin;
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

    
    // Use flow when it makes sense to be used.
    bool use_flow = flow>0.0 && (!g_bFoundRescueVehicle || !finale_stitched || !finale_backwards); 
    
    if (!use_flow && navArea != Address_Null) // use flow if in starting area
    {
        int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
        use_flow = navSpawnAttrs & NAV_SPAWN_PLAYER_START || navSpawnAttrs & NAV_SPAWN_CHECKPOINT;
    }

    // TBD: Optimize both vector distance and flow!
    // Find nearest vector distance with LOS and best flow.

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
    if (!use_flow && min_dist<0.0) return false;
    
    bool LOS = cell_visible(g_iStart,last_pos);

    // Try starting at a more reasonable position with LOS
    if ( (join_client || !LOS) && (g_iStart+1)<g_GuideCells.Length && cell_visible(g_iStart+1,last_pos))
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
        int num_beams = (navArea!=Address_Null && !LOS && use_flow) ? detour_join(client,navArea,last_pos,flow,cell.center,cell.flow,duration) : 0;
        if (num_beams<=0)
        {
            DrawBeam(client,last_pos,cell.center,duration);
            g_RequestFirstPos = cell.center;
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
            DrawBeam(client,pos_backward,cell.center,duration,{255,25,25,255});
            pos_backward = cell.center;
            end = false;
            i_draw += 1;
        }
    }
    if (i_draw>0)
    {
        beams_cooldown_update(client,duration);
        #if DEBUG>2
        LogMessage("RequestGuide: client %d flow %f cells %d g_iStart %d (%f ms)", client, flow, i_draw, g_iStart, (GetEngineTime()-t)*1000.0);
        #endif
        return true;
    }
    return false;
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

    static float pos_curr[3], pos_last[3];
    float flow_curr = flow;
    pos_curr = pos;
    ArrayList adjAreas = new ArrayList();
    ArrayList queue = new ArrayList(3);
    queue.PushArray(pos);
        
    Address navArea_curr = navArea;
    float flow_temp, flow_best, dz, dz_best;
    static float pos_temp[3], pos_best[3];
    Address navArea_best;

    bool success = false;
    while (navArea_curr != Address_Null)
    {
        bool found = false;
        flow_best = flow_curr;
        dz_best = 10000.0;
        for (int dir = 0; dir < 4; dir++) // Enqueue adjacent nav areas (all 4 directions)
        {
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea_curr, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                Address adjArea = adjAreas.Get(i);
                if (adjArea == Address_Null) continue;
                //if (!L4D_NavArea_IsConnected(navArea_curr,adjArea,dir)) continue;
                //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                L4D_GetNavAreaCenter(adjArea,pos_temp);
                flow_temp = L4D_GetFlowFromPoint(pos_temp);
                if (flow_temp<=flow_best) continue;
                pos_temp[2] += 16.0;
                if (g_bL4D2 && !L4D2_NavAreaBuildPath(navArea_curr,adjArea,2.0*GetVectorDistance(pos_temp,pos_curr),TEAM_SURVIVOR,false)) continue;
                dz = pos_temp[2] - pos_curr[2];
                if (dz>=32.0 && dz>dz_best) continue; // avoid vertical changes that can't be crouch jumped
                dz_best = dz;
                flow_best = flow_temp;
                navArea_best = adjArea;
                pos_best = pos_temp;
                found = true;
            }
        }

        if (found)
        {
            if (pos_underwater(pos_best)) pos_best[2] += 32.0;
            if (!twopos_visible(pos_curr,pos_best))
            {
                static float pos_mid[3];
                if (LOS_rescue_cheap(pos_curr,pos_best,pos_mid)) queue.PushArray(pos_mid);
                else if (queue.Length == 1) // Try nav center of client origin
                {
                    L4D_GetNavAreaCenter(navArea,pos_mid);
                    pos_mid[2] += 16.0;
                    if (pos_underwater(pos_mid)) pos_mid[2] += 32.0;
                    if (twopos_visible(pos_curr,pos_mid) && twopos_visible(pos_best,pos_mid)) queue.PushArray(pos_mid);
                }
                queue.PushArray(pos_best);
            }
            else if (queue.Length>1)
            {
                queue.GetArray(queue.Length-2,pos_last,3);
                //if (g_hCvarDz.FloatValue>0.0) // reduce floating cells
                //{
                //    if (FloatAbs(pos_last[2]-pos_best[2])>g_hCvarDz.FloatValue)
                //    {
                //        queue.PushArray(pos_best);
                //    }
                //}
                if (twopos_visible(pos_best,pos_last)) queue.SetArray(queue.Length-1,pos_best,3);
                else queue.PushArray(pos_best);
            }
            else queue.PushArray(pos_best);
            pos_curr = pos_best;
            navArea_curr = navArea_best;
            flow_curr = flow_best;
            int spawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea_curr);
            if ( spawnAttrs & NAV_SPAWN_ESCAPE_ROUTE || (finale_rescue && spawnAttrs & NAV_SPAWN_RESCUE_VEHICLE) )
            {
                g_iStart = get_flow_iStart(flow_curr,true,pos_curr);
                static Cell cell;
                g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell));
                pos_end = cell.center;
                if (queue.Length>1 && twopos_visible(pos_curr,pos_end))
                {
                    queue.GetArray(queue.Length-2,pos_last,3);
                    if (twopos_visible(pos_last,pos_end)) queue.Erase(queue.Length-1);
                }
                success = true;
                break;
            }
        }
        
        if (!found || success) break;
        if (found && flow_curr <= flow_end && twopos_visible(pos_curr,pos_end))
        {
            success = true;
            break;
        }

        if ( ((GetEngineTime()-t)*1000.0) >= DETOUR_BUDGET_MS )
        {
            #if DEBUG>1
            LogMessage("detour_join exceeded budget");
            #endif
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
            if (beams==1) g_RequestFirstPos = pos_curr;
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


void DrawBeam(int client, float pos_start[3], float pos_end[3], float duration = 10.0, int color[4] = {25,255,25,255})
{
    if (g_iLaser==0) return;
    float start_width = 1.5;
    float end_width = 1.5;
    int fade_length = 10;
    float amp = 0.0;
    TE_SetupBeamPoints(pos_start,pos_end,g_iLaser,0,0,0,duration,start_width,end_width,fade_length,amp,color,0);
    TE_SendToClient(client); // no LOS
}

void Check_Guidable()
{
    gamemode_guidable = !L4D_IsSurvivalMode();
    if (gamemode_guidable && g_bL4D2) gamemode_guidable = !L4D2_IsScavengeMode();
    if (!map_started || !nav_started) return;
    if (guide_ready && !gamemode_guidable) Guide_Cleanup();
}

#define STAGE_NONE 0
#define STAGE_PREP 1
#define STAGE_COLLECT 2
#define STAGE_SORT 3
#define STAGE_BUILD 4
#define STAGE_FINALE 5
#define STAGE_VALIDATE 6
#define STAGE_END 7

int g_iPrepStage, g_iLoop;
float g_fMaxFlow, g_fFlowStart, g_fFlowCheckpoint, g_tFrameStart;
ArrayList allAreas, all_cells, RescueVehicleCells;
bool g_bMissingStart, g_bMissingCheckpoint, g_bFoundStart, g_bFoundCheckpoint;
Address g_aNavStart, g_aNavCheckpoint, g_aNavRescueVehicle;


#if DEBUG
float g_fPrepTotalTime;
int g_iPrepFrames, g_iErased, g_iNavBlocked;
#endif

void Guide_Prep()
{
    if (!enable || !gamemode_guidable || !map_started || !nav_started || guide_prep || is_prep_cooldown()) return;
    #if DEBUG>1
    LogMessage("Guide_Prep");
    #endif
    guide_prep = true;
    g_iPrepStage = STAGE_PREP;
    #if DEBUG
    g_iPrepFrames = 0;
    #endif
    timer_nav = null;
    OnFramePrep(true);
}

void Guide_Cleanup()
{
    g_iPrepStage = STAGE_NONE; // tell guide prep to cancel
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
    static Cell cell, cell_before, cell_after;
    Address navArea;
    bool budget_spent = false; // same variable for all stages
    if (new_frame)
    {
        #if DEBUG
        g_iPrepFrames += 1;
        #endif
        g_tFrameStart = GetEngineTime();
    }
    switch (g_iPrepStage)
    {
        case STAGE_PREP:
        {

            delete allAreas;
            allAreas = new ArrayList();
            L4D_GetAllNavAreas(allAreas);
            if (allAreas.Length<=1)
            {
                delete allAreas;
                guide_prep = false;
                return;
            }

            // Get max flow
            if (g_bL4D2) g_fMaxFlow = L4D2Direct_GetMapMaxFlowDistance();
            else
            {
                g_fMaxFlow = 0.0;
                g_iLoop = 0;
                while (g_iLoop<allAreas.Length)
                {
                    navArea = allAreas.Get(g_iLoop);
                    if (navArea == Address_Null)
                    {
                        allAreas.Erase(g_iLoop);
                        continue;
                    }
                    L4D_GetNavAreaCenter(navArea,pos);
                    flow = L4D_GetFlowFromPoint(pos);
                    if (flow>g_fMaxFlow) g_fMaxFlow = flow;
                    g_iLoop += 1;
                }
            }

            if (g_fMaxFlow<=0.0)
            {
                guide_prep = false;
                g_iPrepStage = STAGE_NONE;
                return;
            }

            g_fFlowRescueVehicle = -1.0;
            g_bFoundRescueVehicle = false;

            delete all_cells;
            all_cells = new ArrayList(sizeof(Cell)); // Collect nav areas in survivor path
            
            delete g_GuideCells;
            g_GuideCells = new ArrayList(sizeof(Cell));

            delete RescueVehicleCells;
            RescueVehicleCells = new ArrayList(sizeof(Cell));

            g_bMissingStart = true; // do we have a confirmed start area navmesh in g_GuideCells?
            g_bMissingCheckpoint = true; // do we have a confirmed end area navmesh in g_GuideCells?
            
            g_bFoundStart = false;
            g_bFoundCheckpoint = false;
            
            g_fFlowStart = g_fMaxFlow;
            g_fFlowCheckpoint = 0.0;

            finale_stitched = false;
            finale_backwards = false;

            g_iLoop = 0;
            #if DEBUG
            g_fPrepTotalTime = 0.0;
            g_iErased = 0;
            g_iNavBlocked = 0;
            #endif
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
                if (frame_budget_exceeded()) { budget_spent = true; break; }
                navArea = allAreas.Get(g_iLoop);
                g_iLoop += 1;
                if (!navArea) continue;
                L4D_GetNavAreaCenter(navArea,pos);
                flow = L4D_GetFlowFromPoint(pos);
                if (flow>g_fMaxFlow) continue;
                int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);

                if (flow > 0.0 && g_hCvarFinale.IntValue < FINALE_NEVER && navSpawnAttrs & NAV_SPAWN_RESCUE_VEHICLE )
                {
                    if (flow>g_fFlowRescueVehicle)
                    {
                        g_bFoundRescueVehicle = true;
                        g_fFlowRescueVehicle = flow;
                        g_aNavRescueVehicle = navArea;
                    }
                }

                if (L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,true) || L4D_NavArea_IsBlocked(navArea,TEAM_SURVIVOR,false))
                {
                    #if DEBUG
                    g_iNavBlocked += 1;
                    #endif
                    continue;
                }

                bool checkpoint = navSpawnAttrs & NAV_SPAWN_PLAYER_START || navSpawnAttrs & NAV_SPAWN_CHECKPOINT;

                if (flow > 0.0 && navSpawnAttrs & NAV_SPAWN_ESCAPE_ROUTE)
                {
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
                    if (checkpoint && flow<(g_fMaxFlow*0.25)) g_bMissingStart = false;
                    if (checkpoint && flow>(g_fMaxFlow*0.75)) g_bMissingCheckpoint = false;
                    //#if DEBUG>2
                    //    LogMessage("%d %f %f", g_iLoop, flow);
                    //#endif
                }
                
                if (checkpoint)
                {
                    if (flow<g_fFlowStart) // Find smallest flow starting position
                    {
                        g_bFoundStart = true;
                        g_aNavStart = navArea;
                        g_fFlowStart = flow;
                    }
                    if (flow>g_fFlowCheckpoint) // Find biggest flow ending position
                    {
                        g_bFoundCheckpoint = true;
                        g_aNavCheckpoint = navArea;
                        g_fFlowCheckpoint = flow;
                    }
                }

            }
            
            if (!budget_spent) // Stage has ended, prep for next stage.
            {
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

                if (g_bFoundRescueVehicle)
                {
                    cell.navArea = g_aNavRescueVehicle;
                    cell.flow = g_fFlowRescueVehicle;
                    L4D_GetNavAreaCenter(cell.navArea,pos);
                    pos[2] += 16.0;
                    if (pos_underwater(pos)) pos[2] += 16.0;
                    cell.center = pos;
                    RescueVehicleCells.PushArray(cell); 
                }

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
                if (frame_budget_exceeded()) { budget_spent = true; break; }
                all_cells.GetArray(g_iLoop,cell,sizeof(Cell));
                guide_add_cell(g_GuideCells,cell);
                g_iLoop += 1;
            }
            if (!budget_spent) // Stage has ended, prep for next stage
            {
                delete all_cells;
                if (g_GuideCells.Length <= 1)
                {
                    delete g_GuideCells;
                    guide_prep = false;
                    return;
                }
                if (g_bFoundRescueVehicle)
                {
                    float max_guide_flow = g_GuideCells.Get(g_GuideCells.Length-1,0);
                    LogMessage("rescue vehicle flow %f max guide flow %f", g_fFlowRescueVehicle, max_guide_flow);
                    finale_backwards = g_fFlowRescueVehicle<max_guide_flow;
                }
                g_iLoop = 1;
            }
        }
        case STAGE_FINALE:
        {
            if (RescueVehicleCells == null || RescueVehicleCells.Length <= 0 || g_hCvarFinale.IntValue == FINALE_NEVER)
                g_bFoundRescueVehicle = false;

            if (g_bFoundRescueVehicle)
            {
                RescueVehicleCells.GetArray(RescueVehicleCells.Length-1,cell,sizeof(Cell));
                static float pos_curr[3];
                float flow_curr = cell.flow;
                pos_curr = cell.center;
                ArrayList adjAreas = new ArrayList();
                    
                Address navArea_curr = cell.navArea;
                float flow_temp, flow_best;
                //float dz, dz_best;
                static float pos_temp[3], pos_best[3];
                Address navArea_best;

                while (navArea_curr != Address_Null)
                {
                    if (frame_budget_exceeded()) { budget_spent = true; break; }
                    bool found = false;
                    flow_best = flow_curr;
                    //dz_best = 10000.0;
                    for (int dir = 0; dir < 4; dir++) // Enqueue adjacent nav areas (all 4 directions)
                    {
                        adjAreas.Clear();
                        L4D_NavArea_GetAdjacentAreas(navArea_curr, dir, adjAreas);
                        for (int i = 0; i < adjAreas.Length; i++)
                        {
                            Address adjArea = adjAreas.Get(i);
                            if (adjArea == Address_Null) continue;
                            //if (!L4D_NavArea_IsConnected(navArea_curr,adjArea,dir)) continue;
                            //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                            //if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                            L4D_GetNavAreaCenter(adjArea,pos_temp);
                            flow_temp = L4D_GetFlowFromPoint(pos_temp);
                            if (finale_backwards && flow_temp<=flow_best) continue; // from rescue zone -> go upwards in flow
                            else if (!finale_backwards && flow_temp>=flow_best) continue; // from rescue zone -> go downwards in flow
                            pos_temp[2] += 16.0;
                            //if (g_bL4D2 && !L4D2_NavAreaBuildPath(navArea_curr,adjArea,2.0*GetVectorDistance(pos_temp,pos_curr),TEAM_SURVIVOR,false)) continue;
                            //dz = FloatAbs(pos_temp[2] - pos_curr[2]);
                            //if (dz>=32.0 && dz>dz_best) continue;
                            //dz_best = dz;
                            flow_best = flow_temp;
                            navArea_best = adjArea;
                            pos_best = pos_temp;
                            found = true;
                        }
                    }

                    if (found)
                    {
                        if (pos_underwater(pos_best)) pos_best[2] += 32.0;
                        //if (!twopos_visible(pos_curr,pos_best))
                        //{
                        //    static float pos_mid[3];
                        //    if (LOS_rescue_cheap(pos_curr,pos_best,pos_mid)) RescueVehicleCells.PushArray(pos_mid);
                        //    else if (queue.Length == 1) // Try nav center of client origin
                        //    {
                        //        L4D_GetNavAreaCenter(navArea,pos_mid);
                        //        pos_mid[2] += 16.0;
                        //        if (pos_underwater(pos_mid)) pos_mid[2] += 32.0;
                        //        if (twopos_visible(pos_curr,pos_mid) && twopos_visible(pos_best,pos_mid)) RescueVehicleCells.PushArray(pos_mid);
                        //    }
                        //    RescueVehicleCells.PushArray(pos_best);
                        //}
                        //else if (queue.Length>1)
                        //{
                        //    RescueVehicleCells.GetArray(RescueVehicleCells.Length-2,pos_last,3);
                            //if (g_hCvarDz.FloatValue>0.0) // reduce floating cells
                            //{
                            //    if (FloatAbs(pos_last[2]-pos_best[2])>g_hCvarDz.FloatValue)
                            //    {
                            //        queue.PushArray(pos_best);
                            //    }
                            //}
                        //    if (twopos_visible(pos_best,pos_last)) RescueVehicleCells.SetArray(queue.Length-1,pos_best,3);
                        //    else RescueVehicleCells.PushArray(pos_best);
                        //}
                        //else RescueVehicleCells.PushArray(pos_best);
                        pos_curr = pos_best;
                        navArea_curr = navArea_best;
                        flow_curr = flow_best;
                        
                        cell.flow = flow_curr;
                        cell.navArea = navArea_curr;
                        cell.center = pos_curr;
                        //RescueVehicleCells.PushArray(cell,sizeof(Cell));
                        guide_add_cell(RescueVehicleCells,cell);
                        //LogMessage("STAGE_FINALE %d %f", RescueVehicleCells.Length, cell.flow);
                        //if (L4D_GetNavArea_SpawnAttributes(navArea_curr) & NAV_SPAWN_ESCAPE_ROUTE)
                        //{
                        //    g_iStart = get_flow_iStart(flow_curr,true,pos_curr);
                        //    static Cell cell;
                        //    g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell));
                        //    pos_end = cell.center;
                        //    if (RescueVehicleCells.Length>1 && twopos_visible(pos_curr,pos_end))
                        //    {
                        //        RescueVehicleCells.GetArray(RescueVehicleCells.Length-2,pos_last,3);
                        //        if (twopos_visible(pos_last,pos_end)) RescueVehicleCells.Erase(RescueVehicleCells.Length-1);
                        //    }
                        //    success = true;
                        //    break;
                        //}
                    }
                    else break;
                }
                if (!budget_spent)
                {
                    LogMessage("Rescue vehicle cells %d", RescueVehicleCells.Length);
                    if (should_stitch_finale()) stitch_finale();
                }
                delete adjAreas;
            }
            g_iLoop = 1;
        }
        case STAGE_VALIDATE:
        {
            if (g_GuideCells != null && g_GuideCells.Length>2) // Erase inbetween cells with mutual LOS
            {
                while (g_iLoop<(g_GuideCells.Length-1))
                {
                    if (frame_budget_exceeded()) { budget_spent = true; break; }
                    g_GuideCells.GetArray(g_iLoop,cell,sizeof(Cell));
                    g_GuideCells.GetArray(g_iLoop+1,cell_after,sizeof(Cell));
                    
                    //if (g_hCvarDz.FloatValue>0.0) // reduce floating cells
                    //{
                    //    if (FloatAbs(cell.center[2]-cell_after.center[2])>g_hCvarDz.FloatValue)
                    //    {
                    //        g_iLoop += 1;
                    //        continue;
                    //    }
                    //}

                    g_GuideCells.GetArray(g_iLoop-1,cell_before,sizeof(Cell));

                    bool LOS1 = twopos_visible(cell_before.center,cell.center);
                    bool LOS2 = twopos_visible(cell_before.center,cell_after.center);
                    if (!LOS1 && LOS2)
                    {
                        g_GuideCells.Erase(g_iLoop);
                        #if DEBUG
                        g_iErased += 1;
                        #endif
                        continue;
                    }
                    if (LOS1 && LOS2 && twopos_visible(cell.center,cell_after.center))
                    {
                        g_GuideCells.Erase(g_iLoop);
                        #if DEBUG
                        g_iErased += 1;
                        #endif
                        continue;
                    }
                    #if DEBUG>2
                        LogMessage("%d %f", g_iLoop, cell.flow);
                    #endif
                    g_iLoop += 1;
                }
            }
        }
        default:
        {
            guide_prep = false;
            return;
        }
    }
    
    if (!budget_spent) g_iPrepStage += 1;

    if (g_iPrepStage>STAGE_NONE && g_iPrepStage<STAGE_END)
    {
        if (budget_spent || frame_budget_exceeded())
        {
            RequestFrame(OnFramePrep,true);
            #if DEBUG
            g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
            #endif
            return;
        }
        else OnFramePrep(false);
    }
    else
    {
        guide_prep = false;
        guide_ready = true;
        beams_cooldown_reset(); // reset cooldowns but not requests to draw
        delete allAreas;
        delete all_cells;
        #if DEBUG
        g_fPrepTotalTime += (GetEngineTime()-g_tFrameStart);
        LogMessage("Final cell num %d (%d erased, %d blocked) (%f ms %d frames)", g_GuideCells.Length, g_iErased, g_iNavBlocked, g_fPrepTotalTime*1000.0, g_iPrepFrames);
        #endif
        g_iPrepStage = STAGE_NONE;
        timer_nav = null;
        Timer_CheckRequests(); // Draw beams immediately for pending clients
    }

}

// Check if escape vehicle should be connected to RequestGuide
bool should_stitch_finale()
{
    if (!enable || !map_started || !nav_started || finale_stitched || !g_bFoundRescueVehicle) return false;
    switch (g_hCvarFinale.IntValue)
    {
        case FINALE_NEVER: return false;
        case FINALE_RESCUE: return finale && finale_rescue;
        case FINALE_STARTED: return finale;
        default: return true;
    }
}

void stitch_finale()
{
    if (!enable || finale_stitched) return;
    if (g_GuideCells == null || RescueVehicleCells == null) return;
    static Cell cell;
    if (!finale_backwards) // simplest case. extend guide cells to escape vehicle
    {
        LogMessage("Finale increasing in flow, extended by %d cells", RescueVehicleCells.Length);
    }
    else
    {
        if (finale_gauntlet) // Erase g_GuideCells after rescue flow
        {
            g_iLoop = g_GuideCells.Length-1;
            int erased = 0;
            while (g_iLoop>=0 && g_iLoop<=(g_GuideCells.Length-1))
            {
                if (g_GuideCells.Get(g_iLoop,0)>=g_fFlowRescueVehicle)
                {
                    g_GuideCells.Erase(g_iLoop);
                    erased += 1;
                }
                else g_iLoop -= 1;
            }
            LogMessage("Gauntlet flow backwards, erased %d cells, added %d cells", erased, RescueVehicleCells.Length);
        }
        else // Keep only last guide cell, connect to rescue zone.
        {
            LogMessage("Finale flow backwards, guide from radio only. %d cells", RescueVehicleCells.Length);
            g_GuideCells.GetArray(g_GuideCells.Length-1,cell,sizeof(Cell));
            g_GuideCells.Clear();
            g_GuideCells.PushArray(cell,sizeof(Cell));
        }
    }
    // Merge g_GuideCells with rescue vehicle cells
    // in RescueVehicleCells, the first cell is the rescue position, i.e. the very last point.
    g_iLoop = RescueVehicleCells.Length-1;
    while (g_iLoop>=0 && g_iLoop<=(RescueVehicleCells.Length-1))
    {
        RescueVehicleCells.GetArray(g_iLoop,cell,sizeof(Cell));
        g_GuideCells.PushArray(cell,sizeof(Cell));
        g_iLoop -= 1;
    }
    finale_stitched = true;
}

// Explore from starting position up to flow_min until we hit ESCAPE_ROUTE
stock bool explore_to_escape_route(ArrayList cells, Address navArea, float pos[3], float flow, float flow_min, int max_steps = 50)
{
    LogMessage("explore_to_escape_route %f %f", flow, flow_min);
    static float pos_curr[3];
    float flow_curr = flow;
    pos_curr = pos;
    ArrayList adjAreas = new ArrayList();
        
    Address navArea_curr = navArea;
    float flow_temp;
    static float pos_temp[3];
    static Cell cell, cell_last;
    cell.navArea = navArea;
    cell.flow = flow;
    cell.center = pos;
    cells.PushArray(cell);
    int steps = 0;

    while (steps<max_steps)
    {
        bool found = false;
        for (int dir = 0; dir < 4; dir++)
        {
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea_curr, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                Address adjArea = adjAreas.Get(i);
                if (adjArea == Address_Null) continue;
                L4D_GetNavAreaCenter(adjArea,pos_temp);
                flow_temp = L4D_GetFlowFromPoint(pos_temp);
                if (flow_temp<=flow_curr) continue;
                //if (!L4D_NavArea_IsConnected(navArea_curr,adjArea,dir)) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                pos_temp[2] += 16.0;
                if (pos_underwater(pos_temp)) pos_temp[2] += 32.0;
                if (!twopos_visible(pos_curr,pos_temp))
                {
                    static float pos_mid[3];
                    if (LOS_rescue_cheap(pos_curr,pos_temp,pos_mid))
                    {
                        cell.navArea = adjArea;
                        cell.flow = (flow_temp+flow_curr)/2.0;
                        cell.center = pos_mid;
                        cells.PushArray(cell);
                    }
                }
                steps += 1;
                found = true;
                navArea_curr = adjArea;
                pos_curr = pos_temp;
                flow_curr = flow_temp;
                cell.navArea = navArea_curr;
                cell.flow = flow_temp;
                cell.center = pos_temp;
                if (cells.Length>1)
                {
                    cells.GetArray(cells.Length-2,cell_last,sizeof(Cell));
                    if (twopos_visible(cell.center ,cell_last.center)) cells.SetArray(cells.Length-1,cell,sizeof(Cell));
                    else cells.PushArray(cell);
                }
                else cells.PushArray(cell);
                if (flow_temp > flow_min && L4D_GetNavArea_SpawnAttributes(navArea_curr) & NAV_SPAWN_ESCAPE_ROUTE)
                {
                    delete adjAreas;
                    return true;
                }
                break;
            }
        }
        if (!found) break;
    }

    delete adjAreas;

    return false;
}

void guide_add_cell(ArrayList cells, Cell cell)
{
    if (cells.Length<=1) // no LOS shortcuts available
    {
        cells.PushArray(cell);
        return;
    }
    static Cell cell_prev, cell_prev2;
    cells.GetArray(cells.Length-1,cell_prev,sizeof(Cell)); // last cell
    cells.GetArray(cells.Length-2,cell_prev2,sizeof(Cell)); // cell before last cell
    if (twopos_visible(cell.center,cell_prev.center))
    {
        //if (g_hCvarDz.FloatValue>0.0) // reduce floating cells
        //{
        //    if (FloatAbs(cell_prev.center[2]-cell.center[2])>g_hCvarDz.FloatValue)
        //    {
        //        cells.PushArray(cell);
        //        return;
        //    }
        //}
        if (twopos_visible(cell.center,cell_prev2.center) && twopos_visible(cell_prev2.center,cell_prev.center))
            cells.SetArray(cells.Length-1,cell,sizeof(Cell));
        else 
            cells.PushArray(cell);
    }
    else
    {
        cell_rescue(cells,cell_prev,cell,cell_prev2);
    }
}

// Two cells cannot see each other. Attempt to remedy this
void cell_rescue(ArrayList cells, Cell cell_old, Cell cell_new, Cell cell_prev2)
{
    static Cell cell;
    static Address navAreas[2];
    static float diff[3], diff_candidate[3], diff_template[3], pos_candidate[3], pos_template[3];
    navAreas[0] = cell_new.navArea;
    navAreas[1] = cell_old.navArea;
    ArrayList adjAreas = new ArrayList();
    for (int i_nav = 0; i_nav < sizeof(navAreas); i_nav++) // Check adjacent areas
    {
        Address navArea = navAreas[i_nav];
        for (int dir = 0; dir < 4; dir++) // Enqueue adjacent nav areas (all 4 directions)
        {
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                Address adjArea = adjAreas.Get(i);
                if (adjArea == Address_Null) continue;
                L4D_GetNavAreaCenter(adjArea,pos_candidate);
                //flow_temp = L4D_GetFlowFromPoint(pos_candidate);
                //if (flow_temp<=flow_curr) continue;
                //if (!L4D_NavArea_IsConnected(navArea,adjArea,dir)) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                pos_candidate[2] += 16.0;
                if (pos_underwater(pos_candidate)) pos_candidate[2] += 32.0;
                if (twopos_visible(pos_candidate,cell_new.center) && twopos_visible(pos_candidate,cell_old.center))
                {
                    float d_flow = GetVectorDistance(cell_old.center,pos_candidate);
                    cell.flow = cell_old.flow + d_flow;
                    if (cell.flow>=cell_new.flow) cell.flow = (cell_old.flow + cell_new.flow)/2.0;
                    cell.navArea = adjArea;
                    cell.center = pos_candidate;
                    cells.PushArray(cell);
                    cells.PushArray(cell_new);
                    delete adjAreas;
                    return;
                }
            }
        }
    }
    delete adjAreas;

    ArrayList pos_candidates = new ArrayList(3);

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

            if (diff_template[2] != 0.0) // z is not flat
            {
                diff_candidate = diff_template; diff_candidate[0] = 0.0; diff_candidate[1] = 0.0; // dz
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
        if (twopos_visible(cell.center,cell_prev2.center)) cells.SetArray(cells.Length-1,cell,sizeof(Cell));
        else cells.PushArray(cell);
        break;
    }
    cells.PushArray(cell_new);
    delete pos_candidates;
}

// Two vector positions do not have LOS. See if a vector position inbetween can fix it.
// Result stored in pos_mid. Returns true on success.
bool LOS_rescue_cheap(float pos1[3], float pos2[3], float pos_mid[3])
{
    static float diff[3], diff_candidate[3];
    SubtractVectors(pos2,pos1,diff);
    
    // dx only
    if (FloatAbs(diff[0])>=5.0)
    {
        diff_candidate = diff; diff_candidate[1] = 0.0;
        AddVectors(pos1,diff_candidate,pos_mid);
        if (twopos_visible(pos_mid,pos1) && twopos_visible(pos_mid,pos2)) return true;
    }

    // dy only
    if (FloatAbs(diff[1])>=5.0)
    {
        diff_candidate = diff; diff_candidate[0] = 0.0;
        AddVectors(pos1,diff_candidate,pos_mid);
        if (twopos_visible(pos_mid,pos1) && twopos_visible(pos_mid,pos2)) return true;
    }

    // dz only
    if (FloatAbs(diff[2])>=5.0)
    {
        diff_candidate = diff; diff_candidate[0] = 0.0; diff_candidate[1] = 0.0;
        AddVectors(pos1,diff_candidate,pos_mid);
        if (twopos_visible(pos_mid,pos1) && twopos_visible(pos_mid,pos2)) return true;
    }

    return false;
}

// Check if client is on cooldown for drawing beams
bool beams_cooldown(int client)
{
    //return false;
    //if (playertime.t_engine<0.0 && playertime.t_game<0.0) return false;
    if (g_PlayerTime[client].t_game<=0.0) return false;
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
    if (duration<0.1) duration = 0.1; // reduce server load
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
    if (!enable) return;
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

// Test if two vector positions are visible to one another. world_only to hit only world and static props
bool twopos_visible(float pos1[3], float pos2[3], bool world_only = true)
{
    //if (world_only) TR_TraceRayFilter(pos1,pos2,MASK_SOLID,RayType_EndPoint,TraceFilterStatic);
    //else TR_TraceRayFilter(pos1,pos2,MASK_SOLID,RayType_EndPoint,TraceFilterNoClients);
    if (world_only) TR_TraceHullFilter(pos1,pos2,{-2.0,-2.0,-2.0},{2.0,2.0,16.0},MASK_PLAYERSOLID | MASK_VISIBLE | CONTENTS_DETAIL,TraceFilterStatic);
    //if (world_only) TR_TraceHullFilter(pos1,pos2,{-2.0,-2.0,-2.0},{2.0,2.0,16.0},MASK_ALL,TraceFilterStatic);
    else            TR_TraceHullFilter(pos1,pos2,{-2.0,-2.0,-2.0},{2.0,2.0,10.0},MASK_PLAYERSOLID | MASK_VISIBLE | CONTENTS_DETAIL,TraceFilterNoClients);
    if (!TR_DidHit(INVALID_HANDLE)) return true;
    return false;
}

bool TraceFilterStatic(int entity, int contentsMask)
{
    if (entity == 0) return true;
    if (entity > 0 && entity <= MaxClients) return false;
    static char class[16];
    GetEntityClassname(entity,class,sizeof(class));
    //LogMessage("TraceFilterStatic hit %d %s", entity, class);
    if (strncmp(class,"prop_static",11,false)==0) return true;
    return false;
}

bool TraceFilterNoClients(int entity, int contentsMask)
{
    if (entity > 0 && entity <= MaxClients) return false;
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

