///////////////////////////////////////
#if defined _zm_spawner_analog_included
 #endinput
#endif
#define _zm_spawner_analog_included
///////////////////////////////////////

// Filter context for SpawnerCellFilter callback
//float  g_SpawnerFilterOrigin[3];
//float  g_SpawnerFilterRadius;
int   g_iSpawnerZombieClass;
bool g_bLastDoorValid = false;

/**
 * Draw the colored spawn indicator ring at the ZM's aim position and update spawner state.
 * Draws three stacked rings (red=blocked, blue=conditional, green=allowed) and plays
 * a feedback sound when the state changes.
 *
 * @param target_pos   The position the ZM is aiming at
 * @param spawner_pos  The resolved spawn position (may differ from target_pos after nav snapping)
 * @param state        Spawner state: SPAWNER_OK or other
 * @param draw         If false, skip drawing and only update internal state
 */
void update_ZM_spawner(const float target_pos[3], const float spawner_pos[3], const int state, bool draw=true)
{
    if (draw && IsValidClientZM() && g_iLaser>0 && g_iHalo>0)
    {
        int color[4];
        if (state==SPAWNER_OK) color = color_allowed;
        else if (state>SPAWNER_NAV) color = color_conditional;
        else color = color_blocked;
        float draw_pos[3];
        draw_pos = spawner_pos;
        TE_SetupBeamRingPoint(draw_pos,HULL_DX-2.0,HULL_DX+2.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,1.5,0.0,color,0,0);
        TE_SendToClient(zm_client);
        draw_pos[2] += HULL_DZ;
        TE_SetupBeamRingPoint(draw_pos,HULL_DX-2.0,HULL_DX+2.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,1.5,0.0,color,0,0);
        TE_SendToClient(zm_client);
        draw_pos[2] += HULL_DZ;
        TE_SetupBeamRingPoint(draw_pos,HULL_DX-2.0,HULL_DX+2.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,1.5,0.0,color,0,0);
        TE_SendToClient(zm_client);
        
        float t_now = GetGameTime();
        
        if ( (zm_spawner_state!=state && (t_now-t_last_spawner_sound)>=2.0) )
        {
            static char sound_name[64];
            if (state==SPAWNER_OK) sound_name = "";
            else if (state>SPAWNER_NAV) sound_name = SOUND_CONDITIONAL;
            else sound_name = SOUND_BLOCKED;
            if (sound_name[0]!=0) EmitSoundToClient(zm_client,sound_name,zm_client,ATTN_TO_SNDLEVEL(SNDATTN_NORMAL),_,_,0.09,_,_,draw_pos,_,true);
            t_last_spawner_sound = t_now;
        }
        t_last_spawner_update = t_now;
        
        int target = get_spawner_target_survivor(false,state);
        if (target>0 && g_iGlowList[target]==INVALID_ENT_REFERENCE && L4D2_GetSurvivorVictim(zm_client)!=target) // Draw survivor with CONDITIONAL color
        {
            //GetClientEyePosition(target,draw_pos);
            //draw_pos[2] += 10.0;
            //TE_SetupBeamRingPoint(draw_pos,HULL_DX+2.0,HULL_DX,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.5,0.0,color_conditional,0,0);
            //TE_SendToClient(zm_client);
            CreateZMGlow(target,false,true);
        }
        
        if (state==SPAWNER_OK)
        {
            spawner_last_valid_pos = spawner_pos;
            spawner_last_valid = true;
        }
        
        
    }
    zm_target_pos = target_pos;
    zm_spawner_pos = spawner_pos;
    zm_spawner_state = state;
} 


// Test if pos xy values are out of bounds for given navmesh center and size
stock bool nav_xy_OOB(float pos[3], float center[3], float size[3])
{
    if (FloatAbs(pos[0]-center[0])>FloatAbs(size[0]/2.0)) return true;
    if (FloatAbs(pos[1]-center[1])>FloatAbs(size[1]/2.0)) return true;
    return false;
}

/**
 * Main spawn validation orchestrator - from ZM client.
 * @param zClass  Specify internal zombie_master zombieclass. Witches have relaxed nav checks, commons have relaxed obstruction checks.
 * @param hint   If true, show HUD hints explaining why spawning is blocked
 * @param look_only Exit early, check if ZM is looking at a survivor to trigger flow.
 * @return       SPAWNER_OK, -> GREEN
 *               SPAWNER_INVALID, SPAWNER_NAV -> RED
 *               SPAWNER_DISTANCE, SPAWNER_SIGHT, or SPAWNER_OTHER -> BLUE
 */
int Analog_CanSpawn(int zClass=ZOMBIECLASS_BOOMER, bool hint = true, bool look_only = false)
{
    if (DEBUG) LogMessage("[zm] Analog_CanSpawn");
	if (!IsValidClientZM()) return SPAWNER_INVALID;
	if (zm_stage>=ZM_END) return SPAWNER_INVALID;
	if (IsPlayerAlive(zm_client) && L4D2_GetSurvivorVictim(zm_client)>0) return SPAWNER_FLOW; 
	int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode");
    if ( (observermode==4 || observermode==5) && get_spawner_target_survivor(false,SPAWNER_DISTANCE)>0 )
    {
        // exit early, draw only visor on target survivor.
        update_ZM_spawner({0.0,0.0,0.0},{0.0,0.0,0.0},SPAWNER_FLOW,true);
        return SPAWNER_FLOW;
    }
    if (IsValidEntRef(entref_lastlook))
    {
        int lastlook = EntRefToEntIndex(entref_lastlook);
        if (IsValidClient(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR && IsPlayerAlive(lastlook))
        {
            update_ZM_spawner({0.0,0.0,0.0},{0.0,0.0,0.0},SPAWNER_FLOW,true);
            return SPAWNER_FLOW;
        }
    }
	float vAngles[3],vOrigin[3],vPos[3];
	GetClientEyePosition(zm_client,vOrigin);
	GetClientEyeAngles(zm_client,vAngles);
    Handle trace = TR_TraceRayFilterEx(vOrigin,vAngles,MASK_SOLID,RayType_Infinite,FilterSpawner_HitSurvivors,zm_client);
	if(TR_DidHit(trace))
	{
    	TR_GetEndPosition(vPos,trace);
    	zm_target_pos = vPos;
    	int entity = TR_GetEntityIndex(trace);
    	if (IsValidClient(entity) && GetClientTeam(entity)==TEAM_SURVIVOR && IsPlayerAlive(entity))
    	{
        	float vPos_spawner[3];
        	GetClientAbsOrigin(entity,vPos_spawner);
        	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_DISTANCE,true);
        	latest_distance = 0.0;
        	spawner_nearest_survivor = entity;
        	delete trace;
        	return SPAWNER_FLOW;
    	}
	}
	else GetClientAbsOrigin(zm_client,vPos);
	delete trace;
	if (look_only) return SPAWNER_INVALID;
    int spawner_state = Analog_CanSpawnPos(vPos,zClass,hint,true);
    if (spawner_state==SPAWNER_OK && !zm_allow_spawns)
	{
    	if (hint) update_hint("%T", "Zombie spawns OFF", zm_client);
    	return SPAWNER_OTHER;
	}
	return spawner_state;
}

/**
 * Main spawn validation orchestrator - specify world position in map.
 * if a spawn is valid at the aimed location. Checks: world bounds, NavMesh area,
 * nav spawn attributes, minimum distance to survivors, obstruction, and line of sight.
 * Updates the visual spawner indicator as a side effect (when update_ZM_spawner() is called).
 * GridLib should run here to reposition the spawner if it's very close to a good spawn location.
 *
 * @param vPos   World position to check. It may be adjusted slightly if there's a valid position very close by.
 * @param zClass 
 * @param hint   If true, show HUD hints explaining why spawning is blocked
 * @param draw   Run update_ZM_spawner() which will update zm_spawner globals + draw GREEN/BLUE/RED for ZM to see. Set draw=false for internal calculations, i.e. to check spawn rules.
 * @param skip_gridlib If true, skip gridlib fallback and immediately throw out a failed spawner state.
 * @return       SPAWNER_OK, -> GREEN
 *               SPAWNER_INVALID, SPAWNER_NAV -> RED
 *               SPAWNER_DISTANCE, SPAWNER_SIGHT, or SPAWNER_OTHER -> BLUE
 */
int Analog_CanSpawnPos(float vPos[3], int zClass = ZOMBIECLASS_BOOMER,bool hint = true,bool draw = true,bool skip_gridlib=false)
{
	if (DEBUG) LogMessage("[zm] Analog_CanSpawn %.1f %.1f %.1f", vPos[0], vPos[1], vPos[2]);
	if (zm_stage>=ZM_END) return SPAWNER_INVALID;
	if ( (hint || draw) && !IsValidClientZM())
	{
    	hint = false;
    	draw = false;
    }
    
    if (TR_PointOutsideWorld(vPos)) // Straight up bad location? Don't waste time.
    {
        if (hint) update_hint("%T", "Bad location", zm_client);
        if (draw) update_ZM_spawner(vPos,vPos,SPAWNER_INVALID,draw);
        return SPAWNER_INVALID;
    }
    
    bool ignore_zombies = zClass==ZOMBIECLASS_COMMON;
    // vPos: input, adjusted on the fly
	// vPos_spawner: final spawner position (output). later we decide where to draw the spawner depending on its state.
	float vPos_spawner[3];
	vPos_spawner = vPos;
    float check_dist = (zClass==ZOMBIECLASS_WITCH) ? 50.0 : 500.0;
    float min_distance;
    latest_distance = -1.0;
    
    bool fail = false;
    int spawner_state = SPAWNER_OK;
    if (!g_bGrid || !GridLib_IsReady()) skip_gridlib = true;
    
    //                                                  bools: anyz los checkground
    Address navArea = L4D_GetNearestNavArea(vPos_spawner,check_dist,true,true,true,TEAM_INFECTED);
    int navSpawnAttrs, navAttrFlags;
    if (draw) zm_spawner_navArea = navArea; // update global navarea
    float navSize[3], navCenter[3];
    if (navArea)
    {
        navAttrFlags = L4D_GetNavArea_AttributeFlags(navArea);
        navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
        L4D_GetNavAreaCenter(navArea,navCenter);
        L4D_GetNavAreaSize(navArea,navSize);
        
        if (!nav_can_spawn_zombies(zClass,navArea,navAttrFlags,navSpawnAttrs,navCenter,navSize))
        {
            spawner_state = SPAWNER_NAV; // nav does not allow this zombie.
            fail = true;
        }
        
        if (!fail)
        {
            //float z_min = navCenter[2] - FloatAbs(navSize[2])/2.0;
            float z_min = navCenter[2] - FloatAbs(navSize[2]); // fix only egregious out of bounds
            
            bool OOB = nav_xy_OOB(vPos_spawner,navCenter,navSize); // are we out of bounds for the navmesh?
            bool obstruction_checked = false;
            if (OOB) // If navmesh is outside expected xy: try up,center,center-up,random,random-up
            {
                fail = !try_adjusting_obstructed_pos(vPos_spawner,_,zClass,navArea,navCenter,
                                             false,        true,true,         true,true);
                obstruction_checked = true;
            }
            if (!fail && !obstruction_checked && IsObstructed(vPos_spawner,_,_,ignore_zombies)) // Navmesh xy is good, but we are obstructed. Try moving up.
            {
                fail = !try_adjusting_obstructed_pos(vPos_spawner,_,zClass,navArea,navCenter,
                                             true,!obstruction_checked,!obstruction_checked,!obstruction_checked,!obstruction_checked);
                
            }
            if (!fail && vPos_spawner[2]<z_min)
            {
                float new_vPos[3];
                new_vPos = vPos_spawner;
                new_vPos[2] = navCenter[2] + FloatAbs(navSize[2])/2.0 + 1.0;
                if (!IsObstructed(new_vPos,_,_,ignore_zombies)) vPos_spawner = new_vPos;
                else fail = true;
            }
            if (fail) spawner_state = SPAWNER_OTHER;
        }
    }
    else
    {
        if (zClass!=ZOMBIECLASS_WITCH || IsObstructed(vPos_spawner,_,_,ignore_zombies))
        {
            spawner_state = SPAWNER_INVALID;
            fail = true;
        }
    }
    if (!fail || draw) // nav area travel distance is expensive, skip if not needed
    {
        float t = GetEngineTime();
        min_distance = min_distance_to_survivors(vPos_spawner,draw,_,navArea);
        float t_ms = (GetEngineTime()-t)*1000.0;
        if (t_ms>1.0) LogMessage("min_distance_to_survivors took %f ms", t_ms);
        if (min_distance>=0.0 && draw) latest_distance = min_distance;
        if (zm_stage<ZM_STARTED) min_distance *= 2.0; // allow spawns close to saferoom before round start
        if (min_distance>=0.0 && g_fSpawnMinDistance>0.0 && min_distance<g_fSpawnMinDistance)
        {
            if (!fail) spawner_state = SPAWNER_DISTANCE;
            fail = true;
            if (latest_distance<150.0 && draw && spawner_nearest_survivor>0) // trigger flow
            {
                if (draw) update_ZM_spawner(vPos,vPos_spawner,spawner_state,draw);
                return spawner_state;
            }
        }
    }
    if (!fail || spawner_state>SPAWNER_NAV) // if OK or BLUE, check for last saferoom abuse.
    {
        static float distance_last;
        distance_last = distance_last_saferoom(vPos_spawner);
        if (distance_last>0.0 && distance_last<DISTANCE_LAST_SAFEROOM)
        {
            fail = true;
            spawner_state = SPAWNER_NAV;
        }
    }
    if (!fail) // check if survivors can see
    {
        bool obscured = ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
        if (!obscured)
        {
            fail = can_any_alive_survivor_see_cheap(vPos_spawner);
            if (fail) spawner_state = SPAWNER_SIGHT;
        }
    }
    //if (!fail && IsObstructed(vPos_spawner,_,_,ignore_zombies))
    //{
    //    fail = true;
    //    spawner_state = SPAWNER_OTHER;
    //}
    if (fail && draw && spawner_state>SPAWNER_NAV && get_spawner_target_survivor(false,SPAWNER_DISTANCE)<0) // check other candidates
    {
        float newPos[3];
        if (!skip_gridlib && g_bGridReady && g_iSpawnerMode>0 && g_GridHasValidCell && can_ZM_see(g_GridClosestValidPos))
        {
            newPos = g_GridClosestValidPos;
            Grid_InvalidateClosestValid();
            fail = false;
        }
        if (fail && spawner_last_valid)
        {
            newPos = spawner_last_valid_pos;
            if (can_ZM_see(newPos) && Analog_CanSpawnPos(newPos,zClass,false,false,true)==SPAWNER_OK)
                fail = false;
        }
        if (fail && !skip_gridlib) // ask gridlib for a better position
        {
            if (FindNearbyValidSpawnCell(vPos_spawner,newPos,check_dist,zClass) && Analog_CanSpawnPos(newPos,zClass,false,false,true)==SPAWNER_OK)
                fail = false;
        }
        
        if (!fail) // we fixed it!! YIPPEEEEEEEEEEEEEEEEEEE
        {
            vPos_spawner = newPos;
            spawner_state = SPAWNER_OK;
            if (draw) zm_spawner_navArea = L4D_GetNearestNavArea(newPos,check_dist,true,true,true,TEAM_INFECTED);
        }
    }
    if (fail)
    {
        if (hint)
        {
            switch (spawner_state)
            {
                case SPAWNER_DISTANCE: update_hint("%T %d", "Too close", zm_client, RoundFloat(min_distance));
                case SPAWNER_SIGHT:
                {
                    update_hint("%T", "Visible survivors", zm_client);
                    if (zm_allow_spawns && !zm_flow_notify && IsValidClientZM()) PrintHintText(zm_client, "%t", "Flow hint");
                }
                case SPAWNER_OTHER: update_hint("%T", "Obstacle", zm_client);
                case SPAWNER_INVALID: update_hint("%T", "Bad location", zm_client);
                default: // SPAWNER_NAV 
                {
                    if (zClass==ZOMBIECLASS_WITCH) update_hint("%T", "Witches illegal", zm_client);
                    else update_hint("%T", "Zombies illegal", zm_client);
                }
            }
        }
        if (draw)
        {
            if (!DEBUG) vPos_spawner = vPos; // reduce jumpiness which can look disorienting. good for debugging though.
            update_ZM_spawner(vPos,vPos_spawner,spawner_state,draw);
        }
        return spawner_state;
    }
    if (draw) update_ZM_spawner(vPos,vPos_spawner,SPAWNER_OK,draw);
    vPos = vPos_spawner; // in case dynamic adjustment was made
    return SPAWNER_OK;
}


#define MAX_FAILS 50
int cellfilter_fails = 0;
void reset_SpawnerCellFilter()
{
    cellfilter_fails = 0;
}

/**
 * GridLib filter callback for spawn cell validation.
 * Returns GRIDLIB_FILTER_KEEP, GRIDLIB_FILTER_DISCARD, or GRIDLIB_FILTER_DISCARD_NAV.
 * Nav-blocked areas use DISCARD_NAV to skip all cells on that nav area.
 * Context (origin, radius) flows through g_SpawnerFilterOrigin / g_SpawnerFilterRadius.
 */
int SpawnerCellFilter(int cellIdx)
{
    
    if (cellfilter_fails>=MAX_FAILS)
        return GRIDLIB_FILTER_DISCARD_ALL;
    
    // Nav-blocked attributes apply to the entire nav area
    if (GridLib_GetCellSpawnAttributes(cellIdx) & GRIDLIB_NAV_BLOCKED_ZOMBIES)
        return GRIDLIB_FILTER_DISCARD_NAV;

    float cellPos[3], normal[3];
    Address navArea;
    bool obstructed;
    if (!GridLib_GetCellData(cellIdx, cellPos, normal, navArea, obstructed))
    {
        return GRIDLIB_FILTER_DISCARD;
    }
    
    //if (obstructed)
    //    return GRIDLIB_FILTER_DISCARD;
    
    if (!nav_can_spawn_zombies(g_iSpawnerZombieClass,navArea))
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d failed nav attrs", cellIdx);
        return GRIDLIB_FILTER_DISCARD_NAV;
    }
    
    cellfilter_fails += 1;
    
    if (g_bLastDoorValid)
    {
        static float distance_last;
        distance_last = distance_last_saferoom(cellPos);
        if (distance_last>0.0 && distance_last_saferoom(cellPos)<DISTANCE_LAST_SAFEROOM) // prevent last saferoom abuse
            return GRIDLIB_FILTER_DISCARD;
    }
    
    //if (IsObstructed(cellPos,_,_,g_iSpawnerZombieClass==ZOMBIECLASS_COMMON))
    //{ // my obstruction checks can be more restrictive
    //    if (!obstruction_rescue_hull_up(cellPos,_,g_iSpawnerZombieClass))
    //        return GRIDLIB_FILTER_DISCARD;
    //}
    
    if (IsValidClientZM() && !can_ZM_see(cellPos)) // Check if ZM can actually see that location.
        return GRIDLIB_FILTER_DISCARD;
    
    if (can_any_alive_survivor_see_cheap(cellPos))
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d visible to survivors", cellIdx);
        return GRIDLIB_FILTER_DISCARD;
    }

    //float travel = L4D2_NavAreaTravelDistance(cellPos, g_SpawnerFilterOrigin, false);
    //if (travel < 0.0 || travel > g_SpawnerFilterRadius)
    //{
    //    if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d travel fail %.0f", cellIdx, travel);
    //    return GRIDLIB_FILTER_DISCARD;
    //}

    if (g_fSpawnMinDistance > 0.0)
    {
        float minDist = min_distance_to_survivors(cellPos, _, g_fSpawnMinDistance, navArea);
        if (minDist >= 0.0 && minDist < g_fSpawnMinDistance)
        {
            if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d too close (%.0f)", cellIdx, minDist);
            return GRIDLIB_FILTER_DISCARD;
        }
    }
    
    cellfilter_fails = 0;
    return GRIDLIB_FILTER_KEEP;
}

/**
 * When the spawn indicator is blue (>SPAWNER_NAV), search nearby GridLib
 * cells for a valid spawn position that isn't visible to or too close to survivors.
 * Uses GridLib's filter callback to reject cells during closest-first selection,
 * so all returned cells have already passed cheap/medium checks.
 *
 * @param origin    The aimed spawn position to search around
 * @param outPos    Output: the valid nearby cell position, if found
 * @param radius    Search radius, defaults to g_fGridSearchRadius
 * @return          true if a valid cell was found, false otherwise
 */
bool FindNearbyValidSpawnCell(float origin[3], float outPos[3], float radius = -1.0, int zClass = ZOMBIECLASS_COMMON)
{
    if (radius <= 0.0) radius = g_fGridSearchRadius;
    if (radius <= 0.0)
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] radius %f skipped", radius);
        return false;
    }

    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell origin=(%.0f,%.0f,%.0f) radius=%.0f", origin[0], origin[1], origin[2], radius);

    if (!GridLib_IsReady())
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: GridLib not ready");
        return false;
    }

    float t_start = GetEngineTime(); // for profiling

    // Set up filter context and batch PVS
    //g_SpawnerFilterOrigin = origin;
    //g_SpawnerFilterRadius = radius;
    g_iSpawnerZombieClass = zClass;
    g_bLastDoorValid = IsValidEntity(lastdoor);
    Spawner_CacheSurvivorData();

    float t_gridlib = GetEngineTime();
    int cells[1];
    reset_SpawnerCellFilter();
    int count = GridLib_FindNearbyCells(origin, radius, 200.0, cells, 1, SpawnerCellFilter, GRID_BUDGET_MS);
    float gridlib_ms = (GetEngineTime() - t_gridlib) * 1000.0;

    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: %d pre-validated candidates (gridlib=%.2f ms)", count, gridlib_ms);

    // All returned cells passed nav/obstruction/travel/distance/visibility checks.
    // Only the expensive Analog_CanSpawnPos check remains.
    //int expensive_fails = 0;
    for (int i = 0; i < count; i++)
    {
        float cellPos[3], normal[3];
        Address navArea;
        bool obstructed;
        GridLib_GetCellData(cells[i], cellPos, normal, navArea, obstructed);
        //if (Analog_CanSpawnPos(cellPos, g_iSpawnerZombieClass, false, false, true) != SPAWNER_OK)
        //{
        //    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: cell %d Analog_CanSpawnPos fail", i);
        //    expensive_fails++;
        //    if (expensive_fails >= 3)
        //    {
        //        float total_ms = (GetEngineTime() - t_start) * 1000.0;
        //        if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: aborted after 3 expensive fails (gridlib=%.2f ms, total=%.2f ms)", gridlib_ms, total_ms);
        //        if (total_ms > 10.0)
        //            LogMessage("[zm] WARNING: FindNearbyValidSpawnCell took %.1f ms (gridlib=%.1f ms, %d results)", total_ms, gridlib_ms, count);
        //        return false;
        //    }
        //    continue;
        //}
        
        //if (IsValidClientZM())
        //{
        //    float cellPos2[3];
        //    cellPos2 = cellPos; cellPos2[2] += 32.0;
        //    if (!L4D2_IsVisibleToPlayer(zm_client,TEAM_INFECTED,3,0,cellPos2))
        //    {
        //        LogMessage("[zm] FindNearbyValidSpawnCell: cell %d zm_client LOS", i);
        //        continue;
        //    }
        //}
        
        //if (IsValidClientZM() && !can_ZM_see(cellPos))
        //{
        //    LogMessage("[zm] FindNearbyValidSpawnCell: cell %d zm_client LOS", i);
        //    continue;
        //}
        
        if (IsObstructed(cellPos,_,_,zClass==ZOMBIECLASS_COMMON))
        {
            if (!obstruction_rescue_hull_up(cellPos,_,zClass))
                return false;
        }

        if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: valid cell %d at (%.0f,%.0f,%.0f)", i, cellPos[0], cellPos[1], cellPos[2]);
        outPos = cellPos;
        float total_ms = (GetEngineTime() - t_start) * 1000.0;
        if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: done (gridlib=%.2f ms, total=%.2f ms)", gridlib_ms, total_ms);
        if (total_ms > 10.0)
            LogMessage("[zm] WARNING: FindNearbyValidSpawnCell took %.1f ms (gridlib=%.1f ms, %d results)", total_ms, gridlib_ms, count);
        return true;
    }

    float total_ms = (GetEngineTime() - t_start) * 1000.0;
    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: no valid cell found (gridlib=%.2f ms, total=%.2f ms)", gridlib_ms, total_ms);
    if (total_ms > 10.0)
        LogMessage("[zm] WARNING: FindNearbyValidSpawnCell took %.1f ms (gridlib=%.1f ms, %d results)", total_ms, gridlib_ms, count);
    return false;
}

/**
 * Determine which survivor to target for random spawn placement (L4D_GetRandomPZSpawnPosition).
 * Priority: ZM's spectated target > last looked-at survivor > nearest survivor to spawner >
 * forced looktarget update. Falls back to highest-flow survivor when flow mode is active.
 *
 * @param flow            If true, target the highest-flow survivor instead of using look logic
 * @param spawner_state   Current spawner state, used to decide if nearest-survivor fallback applies
 * @return                Client index of the target survivor, or -1 if none found
 */
int get_spawner_target_survivor(bool flow = false, int spawner_state = SPAWNER_DISTANCE)
{
    int target_client = -1;
    if (flow) target_client = L4D_GetHighestFlowSurvivor();
    else
    {
        int lastlook = -1;
        if (IsValidClientZM())
        {
            if (IsPlayerAlive(zm_client))
            {
                 lastlook = L4D2_GetSurvivorVictim(zm_client);
                 if (IsValidClient(lastlook) && IsPlayerAlive(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR)
                     target_client = lastlook;
            }
            else
            {
                int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode");
                if (observermode==4 || observermode==5)
                {
                    lastlook = GetEntPropEnt(zm_client, Prop_Send, "m_hObserverTarget");
                    if (IsValidClient(lastlook) && IsPlayerAlive(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR)
                        target_client = lastlook;
                }
            }
        }
        if (target_client<0 && IsValidEntRef(entref_lastlook))
        {
            lastlook = EntRefToEntIndex(entref_lastlook);
            if (IsValidClient(lastlook) && IsPlayerAlive(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR)
                target_client = lastlook;
        }
        
        if (target_client<0 && spawner_state!=SPAWNER_OK && spawner_nearest_survivor>0)
	    {
            target_client = spawner_nearest_survivor;
            float test_pos[3];
            test_pos = zm_target_pos;
            test_pos[2] += 25.0;
           	if (latest_distance<0.0 || latest_distance>250.0 || 
           	!IsValidClient(target_client) || !IsPlayerAlive(target_client) ||
           	( latest_distance>50.0 && !L4D2_IsVisibleToPlayer(target_client,TEAM_SURVIVOR,3,0,test_pos) ) )
           	{
               	target_client = -1;
           	}
        }
        
        if (target_client<0)
	    {
        	update_ZM_looktarget();
        	if (IsValidEntRef(entref_lastlook)) lastlook = EntRefToEntIndex(entref_lastlook);
        	if (IsValidClient(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR && IsPlayerAlive(lastlook))
            	target_client = lastlook;	
        }
       	
   	}
	if (!IsValidClient(target_client) || !IsPlayerAlive(target_client) || GetClientTeam(target_client)!=TEAM_SURVIVOR) return -1;
	spawner_nearest_survivor = target_client;
	return target_client;
}

/**
 * Draw vertical beam columns to visually mark a survivor and/or zombie for the ZM.
 * Green beam marks the spawned zombie, blue beam marks the targeted survivor.
 * Used when spawning via flow/random placement so the ZM can see where units appeared.
 *
 * @param survivor  Client index of the survivor to mark, or -1 to skip
 * @param zombie    Entity index of the zombie to mark, or -1 to skip
 */
void mark_flow_survivor_and_zombie(int survivor=-1, int zombie=-1)
{
    
    if (!IsValidClientZM()) return;
    zm_flow_notify = true;
     
    float vOrigin[3], draw_start[3], draw_end[3];
    
    if (zombie>0 && IsValidEntity(zombie))
    {
    	L4D_GetEntityWorldSpaceCenter(zombie,vOrigin);
        draw_start = vOrigin; draw_start[2] += 2000.0;
        draw_end = vOrigin; draw_end[2] -= 2000.0;
        TE_SetupBeamPoints(draw_start,draw_end,g_iLaser,g_iHalo,0,0,2.5,2.0,4.0,1,1.0,color_allowed,0);
        TE_SendToClient(zm_client);
    }
    
    if (survivor>0 && IsValidEntity(survivor))
    {
        L4D_GetEntityWorldSpaceCenter(survivor,vOrigin);
        draw_start = vOrigin; draw_start[2] += 2000.0;
        draw_end = vOrigin; draw_end[2] -= 2000.0;
        TE_SetupBeamPoints(draw_start,draw_end,g_iLaser,g_iHalo,0,0,0.5,2.0,4.0,1,1.0,color_conditional,0);
        TE_SendToClient(zm_client);
    }
}

// ==========================================================================
// Provider interface: Resolve + Notify
// ==========================================================================

// Per-spawn state for flow markers (set during Resolve, read during NotifySpawned)
bool  g_bAnalogFlowUsed;
int   g_iAnalogTargetClient;
bool  g_bAnalogHint;
bool  g_bAnalogBatchMode;
bool  g_bAnalogSurvivorBeamDrawn;

void Analog_BeginSpawn()
{
    g_bAnalogFlowUsed = false;
    g_iAnalogTargetClient = -1;
    g_bAnalogHint = false;
    g_bAnalogBatchMode = false;
    g_bAnalogSurvivorBeamDrawn = false;
}

void Analog_NotifySpawned(int entity)
{
    if (!g_bAnalogFlowUsed || !g_bAnalogHint) return;
    if (entity <= 0 || !IsValidEntity(entity)) return;

    if (g_bAnalogBatchMode)
    {
        g_bAnalogSurvivorBeamDrawn = true;
        mark_flow_survivor_and_zombie(-1, entity);
    }
    else
    {
        mark_flow_survivor_and_zombie(g_iAnalogTargetClient, entity);
    }
}

void Analog_EndSpawn()
{
    if (g_bAnalogBatchMode && g_bAnalogFlowUsed && g_bAnalogHint && g_bAnalogSurvivorBeamDrawn)
        mark_flow_survivor_and_zombie(g_iAnalogTargetClient, -1);
}

stock bool Analog_ValidatePosition(float pos[3], bool checkLOS = true)
{
    if (IsObstructed(pos,_,_,g_iSpawnerZombieClass==ZOMBIECLASS_COMMON)) return false;
    if (checkLOS && can_any_alive_survivor_see_cheap(pos)) return false;
    return true;
}

int Analog_ResolveCommonPositions(int count, bool flow, bool angry, bool hint,
    float[] outPositions, int maxOut)
{
    Analog_BeginSpawn();
    g_bAnalogHint = hint;
    g_bAnalogBatchMode = true;
    static float min_distance_last;
    bool valid_last = IsValidEntity(lastdoor); 

    int spawner_state;
    if (flow) spawner_state = SPAWNER_DISTANCE;
    else spawner_state = Analog_CanSpawn(false, hint);

    if (flow || spawner_state != SPAWNER_OK)
    {
        int target_client = get_spawner_target_survivor(flow, spawner_state);
        if (target_client < 0) return 0;

        g_bAnalogFlowUsed = true;
        g_iAnalogTargetClient = target_client;

        bool expected_angry = angry || panic || ZM_finale_announced || L4D_IsSurvivalMode();
        float flow_survivor, flow_survivor_fraction;
        if (!expected_angry)
        {
            flow_survivor = L4D2Direct_GetFlowDistance(target_client);
            flow_survivor_fraction = get_survivor_flow_fraction(target_client);
        }

        int tries = (count <= 10) ? 5 : 3;
        int resolved = 0;
        float randomPos[3];
        for (int i = 0; i < count && resolved < maxOut; i++)
        {
            if (!IsValidClient(target_client) || !IsPlayerAlive(target_client))
                break;
            if (!L4D_GetRandomPZSpawnPosition(target_client, ZOMBIECLASS_COMMON, tries, randomPos))
                continue;
            if (zm_stage < ZM_STARTED && can_any_alive_survivor_see_cheap(randomPos))
                continue;
            if (valid_last)
            {
                min_distance_last = distance_last_saferoom(randomPos);
                if (min_distance_last>0.0 && min_distance_last<DISTANCE_LAST_SAFEROOM)
                    continue;
            }
            if (!expected_angry)
            {
                if (flow_survivor_fraction <= 0.91 && L4D_GetFlowFromPoint(randomPos) < flow_survivor)
                    continue;
            }

            int idx = resolved * 3;
            outPositions[idx] = randomPos[0];
            outPositions[idx+1] = randomPos[1];
            outPositions[idx+2] = randomPos[2];
            resolved++;
        }

        return resolved;
    }

    // Aimed position path: GridLib with per-iteration PVS validation + navmesh fallback
    static int gridlib_cells[500];
    int gridlib_cell_count = 0;
    bool use_gridlib = false;

    int resolved = 0;

    if (count > 1 && g_bGrid && GridLib_IsReady())
    {
        if (g_iSpawnerMode>0 && g_GridValidCellCount>=count && GetVectorDistance(g_GridClosestValidPos,zm_spawner_pos)<150.0
            && L4D2_NavAreaTravelDistance(g_GridClosestValidPos,zm_spawner_pos,false)<150.0)
        {
            //for (int c = 0; c < count; c++)
            //{
            //    gridlib_cells[c] = g_GridCellIndices[c];
            //}
            //use_gridlib = true;
            //gridlib_cell_count = g_GridValidCellCount;
            resolved = Grid_ResolveCommonPositions(count,flow,angry,hint,outPositions,maxOut);
            return resolved;
        }
        
        bool try_gridlib = true;
        if (zm_spawner_navArea)
        {
            float navSize[3];
            L4D_GetNavAreaSize(zm_spawner_navArea, navSize);
            if (navSize[0] < 32.0) navSize[0] = 32.0;
            if (navSize[1] < 32.0) navSize[1] = 32.0;
            float count_navmesh = (navSize[0] * navSize[1]) / AREA_COMMON + 1.0;
            try_gridlib = count_navmesh < count || count_navmesh > (4.0 * count);
        }
        if (try_gridlib)
        {
            reset_SpawnerCellFilter();
            gridlib_cell_count = GridLib_FindCellsFromClosest(zm_spawner_pos, count, gridlib_cells, 500, SpawnerCellFilter, GRID_BUDGET_MS, false);
            if (gridlib_cell_count > 0) use_gridlib = true;
        }
        
    }

    Spawner_CacheSurvivorData();
    static float pos[3];
    for (int i = 0; i < count && resolved < maxOut; i++)
    {

        bool fallback_original_navmesh = false;
        if (use_gridlib && i<gridlib_cell_count)
        {
            int cellIdx = gridlib_cells[i];
            static float cellNormal[3];
            Address cellNavArea;
            bool cellObstructed;
            if (!GridLib_GetCellData(cellIdx, pos, cellNormal, cellNavArea, cellObstructed))
                fallback_original_navmesh = true;
            if (IsObstructed(pos,_,_,true))
            {
                if (!obstruction_rescue_hull_up(pos,_,ZOMBIECLASS_COMMON))
                    fallback_original_navmesh = true;
            }

            //// PVS + single ray trace visibility check
            //if (g_iBatchSurvivorCount > 0)
            //{
            //    bool actuallyVisible = false;
            //    static float cellEye[3];
            //    cellEye[0] = pos[0];
            //    cellEye[1] = pos[1];
            //    cellEye[2] = pos[2] + 36.0;
            //    for (int s = 0; s < g_iBatchSurvivorCount; s++)
            //    {
            //        if (!PVS_CheckOriginInPVS(pos,g_BatchSurvivorPVS[s]))
            //            continue;
            //        Handle trace = TR_TraceRayFilterEx(cellEye, g_fBatchSurvivorPos[s],
            //            MASK_VISIBLE, RayType_EndPoint, FilterSpawner, -1);
            //        bool hit = TR_DidHit(trace);
            //        delete trace;
            //        if (!hit)
            //        {
            //            actuallyVisible = true;
            //            break;
            //        }
            //    }
            //    if (actuallyVisible) continue;
            //}
        }
        else fallback_original_navmesh = true;

        if (fallback_original_navmesh)
        {
            if (zm_spawner_navArea && count > 1)
            {
                L4D_FindRandomSpot(zm_spawner_navArea, pos);
                if (valid_last && distance_last_saferoom(pos)<DISTANCE_LAST_SAFEROOM) pos = zm_spawner_pos;
                else if (g_fSpawnMinDistance>0.0 && min_distance_to_survivors(pos,false,g_fSpawnMinDistance,zm_spawner_navArea)<g_fSpawnMinDistance) pos = zm_spawner_pos;
                else if (can_any_alive_survivor_see_cheap(pos)) pos = zm_spawner_pos;
                else if (IsObstructed(pos,_,_,true))
                {
                    if (!obstruction_rescue_hull_up(pos,_,ZOMBIECLASS_COMMON))
                        pos = zm_spawner_pos;
                }
            }
            else pos = zm_spawner_pos;
        }

        int idx = resolved * 3;
        outPositions[idx] = pos[0];
        outPositions[idx+1] = pos[1];
        outPositions[idx+2] = pos[2];
        resolved++;
    }

    return resolved;
}

/**
 * Resolve position for a witch spawn.
 * Handles aimed/random PZ/flow internally.
 */
bool Analog_ResolveWitchPosition(bool flow, float outPos[3])
{
    Analog_BeginSpawn();
    g_bAnalogHint = true;

    int spawner_state;
    if (flow) spawner_state = SPAWNER_DISTANCE;
    else spawner_state = Analog_CanSpawn(ZOMBIECLASS_WITCH);
    outPos = zm_spawner_pos;

    if (spawner_state != SPAWNER_OK)
    {
        int target_client = get_spawner_target_survivor(flow, spawner_state);
        if (target_client < 0) return false;

        bool fail = false;
        if (!L4D_GetRandomPZSpawnPosition(target_client, ZOMBIECLASS_WITCH, 10, outPos)) fail = true;
        if (!fail && zm_stage < ZM_STARTED && can_any_alive_survivor_see_cheap(outPos)) fail = true;
        if (!fail)
        {
            float flow_survivor_fraction = get_survivor_flow_fraction(target_client);
            if (flow_survivor_fraction <= 0.91 && L4D_GetFlowFromPoint(outPos) < L4D2Direct_GetFlowDistance(target_client))
                fail = true;
            if (!fail && IsObstructed(outPos,_,_,false)) fail = true;
        }
        if (fail) return false;
        g_bAnalogFlowUsed = true;
        g_iAnalogTargetClient = target_client;
    }
    return true;
}

// Analog_ResolveSpecialPosition(zombieclass, flow, outPos)
/**
 * Resolve position for a special infected spawn.
 * Handles aimed/random PZ/flow internally.
 */
bool Analog_ResolveSpecialPosition(int zombieclass, bool flow, float outPos[3])
{
    Analog_BeginSpawn();
    g_bAnalogHint = true;
    //LogMessage("Analog_ResolveSpecialPosition %d %d", zombieclass, flow);

    int spawner_state;
    if (flow) spawner_state = SPAWNER_DISTANCE;
    else spawner_state = Analog_CanSpawn(zombieclass);
    outPos = zm_spawner_pos;

    if (spawner_state != SPAWNER_OK)
    {
        int target_client = get_spawner_target_survivor(flow, spawner_state);
        if (target_client < 0) return false;

        if (!L4D_GetRandomPZSpawnPosition(target_client, zombieclass, 10, outPos) || IsObstructed(outPos,_,_,false))
            return false;

        if (zm_stage < ZM_STARTED && can_any_alive_survivor_see_cheap(outPos))
            return false;

        g_bAnalogFlowUsed = true;
        g_iAnalogTargetClient = target_client;
    }
    return true;
}
