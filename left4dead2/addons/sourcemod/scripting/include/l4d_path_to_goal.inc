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
float g_fMaxFlow, g_fFlowRescueVehicle;

int color_forward[4] = {25,255,25,255};
int color_backward[4] = {255,25,25,255};

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

// Draw beams for all clients. Use client's last duration for RequestGuide if available, or override=true to force duration.
void Guide_All_Clients(float duration = 5.0, bool override = false)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_CellRequests[i].duration>=0.1) continue; // already requested
        if (!override && g_PlayerTime[i].t_cooldown>=0.1) g_CellRequests[i].duration = g_PlayerTime[i].t_cooldown*2.0;
        else g_CellRequests[i].duration = duration;
    }
    Timer_CheckRequests(null);
}

// Use Gauntlet-type logic for stitching escape route with rescue vehicle.
bool use_gauntlet_logic()
{
    if (!finale) return false;
    return finale_gauntlet || g_hCvarFinale.IntValue == FINALE_ALWAYS;
}

int g_iClosestFlow, g_iClosestDist, g_iStart; // closest cell by flow, by distance, and final determination.
float g_RequestFirstPos[3]; // for hint system

// Draw survivor path for client, for duration in seconds
// backward: include backwards-going path.
// join_client: draw connection between client's origin and nearest point in survivor path.
// return true if beams were drawn
bool RequestGuide(int client, float duration = 5.0, bool backward = false, bool join_client = true)
{
    #if DEBUG>1
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

    // Store info of latest request from client
    g_CellRequests[client].join_client = join_client;
    g_CellRequests[client].duration = duration;
    g_CellRequests[client].backward = backward;

    if (!guide_ready)
    {
        Guide_Prep();
        if (!guide_ready || g_GuideCells==null) return false;
    }
    else if (g_GuideCells==null || g_GuideCells.Length<=0) return false;

    static float last_pos[3], origin[3];

    bool self_origin = true;
    int target = INVALID_ENT_REFERENCE;
    if (!alive) // Check who their chase camera is set to. Take that origin instead.
    {
        int observermode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if (observermode==4 || observermode==5)
        {
            target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            if (IsValidEntity(target) && target!=INVALID_ENT_REFERENCE)
            {
                GetEntPropVector(target, Prop_Send, "m_vecOrigin", origin);
                self_origin = false;
                if (IsValidClient(target)) alive = IsPlayerAlive(target);
            }
        }
    }
    if (self_origin) GetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);
    float flow = L4D_GetFlowFromPoint(origin);

    g_iStart = -1;
    g_iClosestFlow = -1;
    g_iClosestDist = -1;

    Address navArea = L4D_GetNearestNavArea(origin,500.0,true,true,true,TEAM_SURVIVOR);
    if (navArea != Address_Null)
    {
        g_iClosestFlow = g_GuideCells.FindValue(navArea,1);
        g_iStart = g_iClosestFlow;
        if (flow<=0.0)
        {
            L4D_GetNavAreaCenter(navArea,last_pos);
            flow = L4D_GetFlowFromPoint(last_pos);
        }
    }

    last_pos = origin;
    if (alive || !self_origin) last_pos[2] += 16.0;
    if (alive)
    {
        switch (GetEntProp( (self_origin) ? client : target , Prop_Send, "m_nWaterLevel"))
        {
            case 1: last_pos[2] += 16.0;
            case 2: last_pos[2] += 32.0;
        }
    }
    else if (self_origin) last_pos[2] -= 16.0; // origin is client eye pos

    static Cell cell;

    bool use_flow = flow>0.0 && flow<=g_fMaxFlow && ( !finale_stitched || !finale_backwards || (use_gauntlet_logic() && flow<g_fFlowRescueVehicle) ); 

    if (g_iStart<0) // if we aren't standing on a guide cell, search all guide cells.
    {
        float min_dist = -1.0;
        float min_dist_flow = -1.0;
        float dist, dist_flow;
        for (int i = 0; i < g_GuideCells.Length; i++)
        {
            g_GuideCells.GetArray(i,cell,sizeof(Cell));
            bool end = true;
            if (min_dist<0.0 || min_dist>256.0) // end if very close cell already found
            {
                end = false;
                dist = GetVectorDistance(last_pos,cell.center,true);
                if (min_dist<0.0 || dist<min_dist)
                {
                    min_dist = dist;
                    g_iClosestDist = i;
                }
            }
            if (use_flow && min_dist_flow!=0.0) // exact flow match means we found the cell already
            {
                end = false;
                dist_flow = FloatAbs(cell.flow - flow);
                if (min_dist_flow<0.0 || dist_flow<min_dist_flow)
                {
                    min_dist_flow = dist_flow;
                    g_iClosestFlow = i;
                }
            }
            if (end) break;
        }
    }

    if (g_iClosestFlow==g_iClosestDist)
    {
        g_iClosestFlow = -1;
        g_iStart = g_iClosestDist;
    }
    else
    {
        g_iStart = (g_iClosestFlow>=0) ? g_iClosestFlow : g_iClosestDist;
    }
    int i_forward = g_iStart;
    int i_backward = g_iStart;
    int i_draw = 0; // how many beams were drawn

    // Try cell splitting technique first. If it fails try usual LOS adjustments
    static float pos_split[3];
    bool LOS = false;
    bool found_split = try_guide_cellsplit(last_pos,pos_split,i_forward) && twopos_visible(last_pos,pos_split); // if successful, adjusts pos_split and i_forward
    if (found_split)
    {
        if (i_forward>=g_GuideCells.Length) i_forward = g_GuideCells.Length-1;
        i_backward = (i_forward>0) ? i_forward-1 : 0;
        if (join_client && GetVectorDistance(last_pos,pos_split,true)>=256.0) // Connect unless they are very close to each other.
        {
            DrawBeam(client,last_pos,pos_split,duration,color_forward);
            i_draw += 1;
        }
        g_GuideCells.GetArray(i_forward,cell,sizeof(Cell));
        DrawBeam(client,pos_split,cell.center,duration,color_forward);
        i_draw += 1;
        if (backward)
        {
            g_GuideCells.GetArray(i_backward,cell,sizeof(Cell));
            if (GetVectorDistance(last_pos,cell.center,true)>=256.0)
            {
                DrawBeam(client,pos_split,cell.center,duration,color_backward);
                i_draw += 1;
            }
        }
        last_pos = pos_split;
        LOS = true;
    }

    if (!LOS) LOS = cell_visible(g_iStart,last_pos);

    // Try starting at a more reasonable position with LOS
    if (!found_split)
    {
        if ( (join_client || !LOS) && (g_iStart+1)<g_GuideCells.Length && cell_visible(g_iStart+1,last_pos,_,250.0))
        {
            g_iStart += 1; // Move forward
            LOS = true;
        }
        else if (g_iStart>0 && !LOS && cell_visible(g_iStart-1,last_pos,_,250.0))
        {
            g_iStart -=1; // Move backward
            LOS = true;
        }
        i_forward = g_iStart;
        i_backward = g_iStart;
    }

    g_GuideCells.GetArray(i_forward,cell,sizeof(Cell));

    if (join_client) // Connect client to starting cell
    {
        int num_beams = (navArea!=Address_Null && !LOS) ? detour_join(client,navArea,last_pos,flow,cell.center,cell.flow,duration) : 0;
        if (num_beams<=0)
        {
            if (!found_split)
            {
                DrawBeam(client,last_pos,cell.center,duration,color_forward);
                i_draw += 1;
            }
            g_RequestFirstPos = cell.center;
        }
        else
        {
            g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell)); // detour_join may have changed g_iStart
            i_draw += num_beams;
            i_forward = g_iStart;
            i_backward = g_iStart;
        }
    }
    static float pos_forward[3], pos_backward[3];
    g_GuideCells.GetArray(i_forward,pos_forward,3,2);
    g_GuideCells.GetArray(i_backward,pos_backward,3,2);
    bool end = false;
    while (!end && i_draw<g_hCvarMax.IntValue)
    {
        end = true;
        if ((i_forward+1)<g_GuideCells.Length)
        {
            i_forward += 1;
            g_GuideCells.GetArray(i_forward,cell,sizeof(Cell));
            DrawBeam(client,pos_forward,cell.center,duration,color_forward);
            pos_forward = cell.center;
            end = false;
            i_draw += 1;
            if (i_draw>=g_hCvarMax.IntValue) break;
        }
        if (backward && i_backward>0)
        {
            i_backward -= 1;
            g_GuideCells.GetArray(i_backward,cell,sizeof(Cell));
            DrawBeam(client,pos_backward,cell.center,duration,color_backward);
            pos_backward = cell.center;
            end = false;
            i_draw += 1;
        }
    }
    if (i_draw>0)
    {
        beams_cooldown_update(client,duration);
        #if DEBUG>1
        LogMessage("RequestGuide: client %d flow %f cells %d g_iStart %d (%f ms)", client, flow, i_draw, g_iStart, (GetEngineTime()-t)*1000.0);
        #endif
        return true;
    }
    return false;
}

ArrayList i_candidates,i_explored;

// See if pos can be connected to a split inbetween two cells. return true on success
// Outputs pos_split, and sets correct i_forward (closest first green cell)
stock bool try_guide_cellsplit(float pos[3],float pos_split[3], int &i_forward)
{
    if (g_GuideCells.Length<=1) return false;
    if (i_candidates==null) i_candidates = new ArrayList();
    if (i_explored==null) i_explored = new ArrayList();
    i_candidates.Clear();
    i_explored.Clear();

    // Each index in i_candidates will be i_backward from which split is drawn towards i_forward
    if (g_iClosestFlow>=0)
    {
        if (g_iClosestFlow < (g_GuideCells.Length-1)) i_candidates.Push(g_iClosestFlow);
        if (g_iClosestFlow>0) i_candidates.Push(g_iClosestFlow-1);
        if (g_iClosestDist < 0) // search more
        {
            if (g_iClosestFlow < (g_GuideCells.Length-2)) i_candidates.Push(g_iClosestFlow+1);
            if (g_iClosestFlow>1) i_candidates.Push(g_iClosestFlow-2);
        }
    }
    if (g_iClosestDist>=0 && g_iClosestDist!=g_iClosestFlow)
    {
        if (g_iClosestDist < (g_GuideCells.Length-1)) i_candidates.Push(g_iClosestDist);
        if (g_iClosestDist>0) i_candidates.Push(g_iClosestDist-1);
        if (g_iClosestFlow < 0) // search more
        {
            if (g_iClosestDist < (g_GuideCells.Length-2)) i_candidates.Push(g_iClosestDist+1);
            if (g_iClosestDist>1) i_candidates.Push(g_iClosestDist-2);
        }
    }

    float dist, mag_sq, dot, scale;
    float best_dist = -1.0;
    static float pos_temp[3], pos_start[3], pos_end[3], vDiff[3], vDiff2[3];
    int i_cell, i_forward_best;
    for (int i = 0; i < i_candidates.Length; i++)
    {
        i_cell = i_candidates.Get(i);
        if (i_explored.FindValue(i_cell)>=0) continue;
        i_explored.Push(i_cell);
        g_GuideCells.GetArray(i_cell,pos_start,3,2);
        dist = GetVectorDistance(pos,pos_start,true);
        if (best_dist<0.0 || dist<best_dist)
        {
            i_forward_best = i_cell+1; pos_split = pos_start;
            best_dist = dist; if (best_dist<=256.0) break; // if very close to client position, we found our answer
        }
        g_GuideCells.GetArray(i_cell+1,pos_end,3,2);
        dist = GetVectorDistance(pos,pos_end,true);
        if (best_dist<0.0 || dist<best_dist)
        {
            i_forward_best = i_cell+1+1; pos_split = pos_end;
            best_dist = dist; if (best_dist<=256.0) break; // if very close to client position, we found our answer
        }
        MakeVectorFromPoints(pos_start,pos_end,vDiff);
        mag_sq = GetVectorDotProduct(vDiff,vDiff);
        if (mag_sq<=0.0) continue;
        MakeVectorFromPoints(pos_start,pos,vDiff2);
        dot = GetVectorDotProduct(vDiff,vDiff2);
        if (dot<=0.0) continue; // not pointing in the right direction
        scale = dot/mag_sq;
        if (scale>=0.999 || scale<=0.001) continue; // projection is crappy
        ScaleVector(vDiff,scale);
        AddVectors(pos_start,vDiff,pos_temp);
        dist = GetVectorDistance(pos,pos_temp,true);
        if (best_dist<0.0 || dist<best_dist)
        {
            i_forward_best = i_cell+1; pos_split = pos_temp;
            best_dist = dist; if (best_dist<=256.0) break; // if very close to client position, we found our answer
        }
    }
    if (best_dist>=0.0)
    {
        i_forward = i_forward_best;
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
        if ((i_start+1)<g_GuideCells.Length && cell_visible(i_start+1,pos,_,250.0))
        {
            i_start += 1; // Move forward
        }
        else if (i_start>0 && !cell_visible(i_start,pos) && cell_visible(i_start-1,pos,_,250.0))
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
                pos_temp[2] += 16.0;
                if (g_bL4D2 && !L4D2_NavAreaBuildPath(navArea_curr,adjArea,2.0*GetVectorDistance(pos_temp,pos_curr),TEAM_SURVIVOR,false)) continue;
                dz = pos_temp[2] - pos_curr[2];
                // Accept candidate if: best flow and dz is OK, or flow is better and dz is better
                if ( (flow_temp>flow_best && dz<32.0) || (flow_temp>flow_curr && dz<dz_best))
                {
                    dz_best = dz;
                    flow_best = flow_temp;
                    navArea_best = adjArea;
                    pos_best = pos_temp;
                    found = true;
                }
            }
        }

        if (!found)
        {
            static Cell cell;
            if (try_ladder(flow_curr,pos_curr,cell))
            {
                found = true;
                flow_best = cell.flow;
                navArea_best = cell.navArea;
                pos_best = cell.center;
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
            static Cell cell;
            int i_found = g_GuideCells.FindValue(navArea_best,1);
            success = i_found>=0;
            if (!success)
            {
                int spawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea_curr);
                success = spawnAttrs & NAV_SPAWN_ESCAPE_ROUTE || (finale_stitched && spawnAttrs & NAV_SPAWN_RESCUE_VEHICLE);
            }
            if (success)
            {
                g_iStart = (i_found>=0) ? i_found : get_flow_iStart(flow_curr,true,pos_curr);
                //LogMessage("detour_join success i_found %d flow %f i_start %d", i_found, flow_curr, g_iStart);
                g_GuideCells.GetArray(g_iStart,cell,sizeof(Cell));
                pos_end = cell.center;
                if (queue.Length>1 && twopos_visible(pos_curr,pos_end))
                {
                    queue.GetArray(queue.Length-2,pos_last,3);
                    if (twopos_visible(pos_last,pos_end)) queue.Erase(queue.Length-1);
                }
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
            DrawBeam(client,pos_curr,pos_temp,duration,color_forward);
            pos_curr = pos_temp;
            beams += 1;
            if (beams==1) g_RequestFirstPos = pos_curr;
            if (beams>=g_hCvarMax.IntValue) break;
        }
        if (beams<g_hCvarMax.IntValue)
        {
            DrawBeam(client,pos_curr,pos_end,duration,color_forward);
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

#define STAGE_NONE 0 // Prep not running
#define STAGE_PREP 1 // First frame of Prep
#define STAGE_COLLECT 2 // Get all ESCAPE_ROUTE, CHECKPOINT, PLAYER_START and RESCUE VEHICLE
#define STAGE_SORT 3 // Sort by flow
#define STAGE_BUILD 4 //
#define STAGE_FINALE 5
#define STAGE_VALIDATE 6
#define STAGE_END 7 // Prep just ended. Guide should be ready.

int g_iPrepStage, g_iLoop;
float g_fFlowStart, g_fFlowCheckpoint, g_tFrameStart;
ArrayList allAreas, all_cells, RescueVehicleCells;
bool g_bMissingStart, g_bMissingCheckpoint, g_bFoundStart, g_bFoundCheckpoint;
Address g_aNavStart, g_aNavCheckpoint, g_aNavRescueVehicle;


#if DEBUG
float g_fPrepTotalTime;
int g_iPrepFrames, g_iErased, g_iNavBlocked, g_iTotalCollected;
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
            g_iTotalCollected = 0;
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
                bool rescue = (navSpawnAttrs & NAV_SPAWN_RESCUE_VEHICLE) > 0;
                if (rescue && flow <= 0.0)
                {
                    rescue = false;
                    LogMessage("NAV_SPAWN_RESCUE_VEHICLE at <= 0.0 flow!!! BOOOOOO!!!!!! THROW TOMATOES AT THE MAPPER!!!!!!");
                }

                if (rescue && g_hCvarFinale.IntValue < FINALE_NEVER)
                {
                    if (flow>g_fFlowRescueVehicle)
                    {
                        g_bFoundRescueVehicle = true;
                        g_fFlowRescueVehicle = flow;
                        g_aNavRescueVehicle = navArea;
                    }
                }

                if (all_cells.FindValue(flow,0)>=0) continue; // if identical flow exists, ignore this cell

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
                    if (g_bMissingStart && checkpoint && flow<=(g_fMaxFlow*0.1)) g_bMissingStart = false;
                    if (g_bMissingCheckpoint && (checkpoint || rescue) && flow>=(g_fMaxFlow*0.25)) g_bMissingCheckpoint = false;
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
            #if DEBUG
            g_iTotalCollected = all_cells.Length;
            #endif
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
                    #if DEBUG
                    LogMessage("rescue vehicle flow %f max guide flow %f", g_fFlowRescueVehicle, max_guide_flow);
                    #endif
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
                float dz, dz_best;
                static float pos_temp[3], pos_best[3];
                Address navArea_best;

                while (navArea_curr != Address_Null)
                {
                    if (frame_budget_exceeded()) { budget_spent = true; break; }
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
                            flow_temp = get_navFlow(adjArea);
                            if (finale_backwards && flow_temp<=flow_best) continue; // from rescue zone -> go upwards in flow
                            else if (!finale_backwards && flow_temp>=flow_best) continue; // from rescue zone -> go downwards in flow
                            L4D_GetNavAreaCenter(adjArea,pos_temp);
                            pos_temp[2] += 16.0;
                            //if (g_bL4D2 && !L4D2_NavAreaBuildPath(navArea_curr,adjArea,2.0*GetVectorDistance(pos_temp,pos_curr),TEAM_SURVIVOR,false)) continue;
                            dz = FloatAbs(pos_temp[2] - pos_curr[2]);
                            if (dz>=32.0 && dz>dz_best) continue;
                            dz_best = dz;
                            flow_best = flow_temp;
                            navArea_best = adjArea;
                            pos_best = pos_temp;
                            found = true;
                        }
                    }

                    if (!found)
                    {
                        if (try_ladder(flow_curr,pos_curr,cell,finale_backwards))
                        {
                            found = true;
                            flow_best = cell.flow;
                            navArea_best = cell.navArea;
                            pos_best = cell.center;
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
                        //i_finale_cut = g_GuideCells.FindValue(navArea_best,1);
                        //if (i_finale_cut>0)
                        //{
                        //    break;
                        //}
                        guide_add_cell(RescueVehicleCells,cell);
                    }
                    else break;
                }
                if (!budget_spent)
                {
                    #if DEBUG
                    LogMessage("Rescue vehicle cells %d", RescueVehicleCells.Length);
                    #endif
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
        LogMessage("Final cell num %d (%d collected, %d erased, %d blocked) (%f ms %d frames)", g_GuideCells.Length, g_iTotalCollected, g_iErased, g_iNavBlocked, g_fPrepTotalTime*1000.0, g_iPrepFrames);
        #endif
        g_iPrepStage = STAGE_NONE;
        timer_nav = null;
        if (finale_stitched && finale_rescue && g_hCvarFinaleAuto.BoolValue) Guide_All_Clients();
        else Timer_CheckRequests(); // Draw beams immediately for pending clients
    }

}

// Look for closest survivor ladder. Output cell_ladder
bool try_ladder(float flow_curr,float pos_curr[3],Cell cell_ladder,bool flow_increasing = true)
{
    int entity = INVALID_ENT_REFERENCE;
    int closest = -1;
    static float mins[3],maxs[3],pos_temp[3],pos_best[3];
    float best_dist = -1.0;
    float flow_best = -1.0;
    float flow_temp;
    bool found = false;
    Address navArea_best;
    while ((entity = FindEntityByClassname(entity, "func_simpleladder")) != INVALID_ENT_REFERENCE)
    {
        int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
        if (team!=0 && team!=TEAM_SURVIVOR) continue;
        GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
        float dist = GetVectorDistance(pos_curr,maxs,true);
        if (best_dist<0.0 || dist<best_dist)
        {
            closest = entity;
            best_dist = dist;
        }
        GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
        dist = GetVectorDistance(pos_curr,maxs,true);
        if (best_dist<0.0 || dist<best_dist)
        {
            closest = entity;
            best_dist = dist;
        }
    }
    if (closest>0 && best_dist<100000.0)
    {
        //LogMessage("Found survivor ladder %d %f", closest, best_dist);
        flow_best = flow_curr;
        for (int i_nav = 0; i_nav < 2; i_nav++)
        {
            if (i_nav==0) GetEntPropVector(closest, Prop_Send, "m_vecMaxs", pos_temp);
            else GetEntPropVector(closest, Prop_Send, "m_vecMins", pos_temp);
            Address adjArea = L4D_GetNearestNavArea(pos_temp,500.0,true,false,true,TEAM_SURVIVOR);
            if (adjArea == Address_Null) continue;
            flow_temp = get_navFlow(adjArea);
            switch (flow_increasing)
            {
                case true: { if (flow_temp<=flow_best) continue; }
                default: { if (flow_temp>=flow_best) continue; }
            }
            L4D_GetNavAreaCenter(adjArea,pos_temp);
            pos_temp[2] += 16.0;
            flow_best = flow_temp;
            navArea_best = adjArea;
            pos_best = pos_temp;
            found = true;
        }
    }
    if (found)
    {
        cell_ladder.flow = flow_best;
        cell_ladder.navArea = navArea_best;
        cell_ladder.center = pos_best;
        return true;
    }
    return false;
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

// Check if two cells are nearly identical. max_distance sets how far apart they can be.
bool cells_almost_identical(Cell cell1, Cell cell2, float max_distance = 250.0)
{
    if (cell1.navArea != Address_Null && cell1.navArea == cell2.navArea) return true;
    return GetVectorDistance(cell1.center,cell2.center)<=max_distance && twopos_visible(cell1.center,cell2.center);
}

void stitch_finale()
{
    if (!enable || finale_stitched) return;
    if (g_GuideCells == null || RescueVehicleCells == null) return;
    static Cell cell, cell2;
    g_GuideCells.GetArray(g_GuideCells.Length-1,cell2,sizeof(Cell));

    int erased = 0;

    int i_finale_cut = -1; // which guide cell meets with rescue
    int i_finale_cut_rescue = -1; // which rescue cell meets with guide
    g_iLoop = 0;
    while (g_iLoop>=0 && g_iLoop<=(RescueVehicleCells.Length-1))
    {
        RescueVehicleCells.GetArray(g_iLoop,cell,sizeof(Cell));
        if ( g_iLoop==0 && cells_almost_identical(cell,cell2) )
        {
            g_GuideCells.PushArray(cell,sizeof(Cell));
            finale_backwards = false;
            finale_stitched = true;
            #if DEBUG
            LogMessage("Rescue zone is close to last guide cell. Added 1 cell.");
            #endif
            return;
        }
        if (cell.navArea != Address_Null)
        {
            i_finale_cut = g_GuideCells.FindValue(cell.navArea,1);
            if (i_finale_cut>=0)
            {
                i_finale_cut_rescue = g_iLoop;
                break;
            }
        }
        g_iLoop += 1;
    }

    if ( (!finale_backwards || use_gauntlet_logic()) && i_finale_cut_rescue>=0 && i_finale_cut>0)
    {
        // keep g_GuideCells up to i_finale_cut. keep i_finale_cut
        g_GuideCells.Resize(i_finale_cut+1);
        // keep RescueVehicleCells up to i_finale_cut_rescue. don't keep i_finale_cut_rescue
        RescueVehicleCells.Resize(i_finale_cut_rescue);
        #if DEBUG
        LogMessage("Finale resize g_GuideCells %d RescueVehicleCells %d", i_finale_cut+1, i_finale_cut_rescue);
        #endif
    }

    if (!finale_backwards) // simplest case. extend guide cells to escape vehicle
    {
        #if DEBUG
        LogMessage("Finale increasing in flow, erased %d cells, added %d cells", erased, RescueVehicleCells.Length);
        #endif
    }
    else
    {
        if (use_gauntlet_logic())
        {
            // Erase g_GuideCells after rescue flow
            g_iLoop = g_GuideCells.Length-1;
            while (g_iLoop>=0 && g_iLoop<=(g_GuideCells.Length-1))
            {
                if (g_GuideCells.Get(g_iLoop,0)>=g_fFlowRescueVehicle)
                {
                    g_GuideCells.Erase(g_iLoop);
                    erased += 1;
                }
                else g_iLoop -= 1;
            }
            #if DEBUG
            LogMessage("Gauntlet flow backwards, erased %d cells, added %d cells", erased, RescueVehicleCells.Length);
            #endif
        }
        else
        {
            // Keep only last guide cell, connect to rescue zone.
            #if DEBUG
            LogMessage("Finale flow backwards, guide from radio only. %d cells", RescueVehicleCells.Length);
            #endif
            g_GuideCells.GetArray(g_GuideCells.Length-1,cell,sizeof(Cell));
            g_GuideCells.Clear();
            g_GuideCells.PushArray(cell,sizeof(Cell));
        }
    }
    // Merge g_GuideCells with rescue vehicle cells
    // in RescueVehicleCells, the first cell is the rescue position (the very last point).
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
        if (navArea == Address_Null) continue;
        for (int dir = 0; dir < 4; dir++) // Enqueue adjacent nav areas (all 4 directions)
        {
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                Address adjArea = adjAreas.Get(i);
                if (adjArea == Address_Null) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,true)) continue;
                if (L4D_NavArea_IsBlocked(adjArea,TEAM_SURVIVOR,false)) continue;
                for (int i_try = 0; i_try < 2; i_try++)
                {
                    if (i_try == 0) L4D_GetNavAreaCenter(adjArea,pos_candidate);
                    else L4D_GetNavAreaPos(adjArea,pos_candidate);
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
    }
    delete adjAreas;

    ArrayList pos_candidates = new ArrayList(3);

    L4D_GetNavAreaPos(cell_new.navArea,pos_candidate); pos_candidate[2] += 16.0;
    pos_candidates.PushArray(pos_candidate);

    L4D_GetNavAreaPos(cell_old.navArea,pos_candidate); pos_candidate[2] += 16.0;
    pos_candidates.PushArray(pos_candidate);

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
        if (pos_underwater(pos_candidate))
        {
            pos_candidate[2] += 16.0;
            if (pos_underwater(pos_candidate)) pos_candidate[2] += 16.0;
        }
        if (!twopos_visible(cell_new.center,pos_candidate)) continue;
        if (!twopos_visible(cell_old.center,pos_candidate)) continue;
        float d_flow = GetVectorDistance(cell_old.center,pos_candidate);
        cell.flow = cell_old.flow + d_flow;
        if (cell.flow>=cell_new.flow) cell.flow = (cell_old.flow + cell_new.flow)/2.0;
        cell.navArea = Address_Null;
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

stock float get_navFlow(Address navArea)
{
    if (g_bL4D2) return L4D2Direct_GetTerrorNavAreaFlow(navArea);
    else
    {
        static float pos[3];
        L4D_GetNavAreaCenter(navArea,pos);
        return L4D_GetFlowFromPoint(pos);
    }
}

// Test if cell is visible from given position
bool cell_visible(int i, float pos[3], bool world_only = true, float max_distance = -1.0)
{
    static Cell cell;
    g_GuideCells.GetArray(i,cell,sizeof(Cell));
    return twopos_visible(pos,cell.center,world_only,max_distance);
}

static int MASK_PTG = MASK_PLAYERSOLID | MASK_VISIBLE | CONTENTS_DETAIL;

// Test if two vector positions are visible to one another. world_only to hit only world and static props
bool twopos_visible(float pos1[3], float pos2[3], bool world_only = true, float max_distance = -1.0, bool hull = true)
{
    if (max_distance>0.0 && GetVectorDistance(pos1,pos2)>max_distance) return false;
    if (hull)
    {
        if (world_only) TR_TraceHullFilter(pos1,pos2,{-2.0,-2.0,-2.0},{2.0,2.0,16.0},MASK_PTG,TraceFilterStatic);
        else            TR_TraceHullFilter(pos1,pos2,{-2.0,-2.0,-2.0},{2.0,2.0,10.0},MASK_PTG,TraceFilterNoClients);
    }
    else
    {
       if (world_only) TR_TraceRayFilter(pos1,pos2,MASK_PTG,RayType_EndPoint,TraceFilterStatic);
       else TR_TraceRayFilter(pos1,pos2,MASK_PTG,RayType_EndPoint,TraceFilterNoClients);
    }
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

