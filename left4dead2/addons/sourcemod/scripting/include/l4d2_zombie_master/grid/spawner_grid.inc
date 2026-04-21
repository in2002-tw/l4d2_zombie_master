///////////////////////////////////////
#if defined _zm_spawner_grid_included
 #endinput
#endif
#define _zm_spawner_grid_included
///////////////////////////////////////

/**
 * Grid spawner provider (mode 1).
 * Uses GridRenderer for colored-cell visuals and GridLib for cell discovery.
 * Validates cells using the ZM's shared validation functions (spawner_validate.inc).
 * Flow spawns delegate to the analog provider.
 */

// ==========================================================================
// Lifecycle
// ==========================================================================

void Grid_Init()
{
    GridRenderer_Init();
    g_bGridReady = true;
}

void Grid_Cleanup()
{
    if (g_hGridTimer != null)
    {
        KillTimer(g_hGridTimer);
        g_hGridTimer = null;
    }
    g_GridCellCount = 0;
    g_GridHasValidCell = false;
    g_GridValidCellCount = 0;
    if (g_bGridReady)
    {
        GridRenderer_Cleanup();
        g_bGridReady = false;
    }
}

void Grid_OnEnabled(int client)
{
    if (!g_bGridReady)
        Grid_Init();
    GridRenderer_OnClientEnabled(client);
    if (g_hGridTimer != null)
    {
        KillTimer(g_hGridTimer);
        g_hGridTimer = null;
    }
    if (g_iSpawnerMode==2) g_hGridTimer = CreateTimer(GRID_UPDATE_RATE, Grid_TimerUpdate, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    g_GridCellCount = 0;
    g_GridHasValidCell = false;
    g_GridValidCellCount = 0;
}

void Grid_OnDisabled(int client)
{
    if (g_hGridTimer != null)
    {
        KillTimer(g_hGridTimer);
        g_hGridTimer = null;
    }
    g_GridCellCount = 0;
    g_GridHasValidCell = false;
    g_GridValidCellCount = 0;
    if (client > 0 && client <= MaxClients)
        GridRenderer_OnClientDisabled(client);
}

// ==========================================================================
// Validation helpers
// ==========================================================================

// Recursion depth counter for stacked-prop rescues.
#define GRID_RESCUE_MAX_DEPTH 2
static int g_GridRescueDepth = 0;

// Try to resolve a cell obstructed by a rescuable entity by finding a standable
// position on top of it.
//
// Preconditions:
//   - The caller just ran IsObstructed(pos) which returned true.
//   - g_iObstructingEntity therefore identifies the blocker at pos.
static bool Grid_TryRescueObstruction(int idx, float pos[3])
{
    int obstructor = g_iObstructingEntity;

    if (obstructor <= 0) return false;

    static char className[16];
    GetEntityClassname(obstructor, className, sizeof(className));

    // Anti-stacking: never rescue onto other actors. Same list
    switch (className[0])
    {
        case 'p': { if (strcmp(className, "player", false) == 0) return false; }
        case 'i': { if (strcmp(className, "infected", false) == 0) return false; }
        case 'w': { if (strcmp(className, "witch", false) == 0) return false; }
        case 'z': { if (strcmp(className, "zombie", false) == 0) return false; }
    }

    float topZ = pos[2];
    float surfaceNormal[3];
    surfaceNormal[0] = 0.0;
    surfaceNormal[1] = 0.0;
    surfaceNormal[2] = 1.0;
    bool resolved = false;

    {
        float startPos[3], endPos[3];
        startPos[0] = pos[0];
        startPos[1] = pos[1];
        startPos[2] = pos[2] + 2048.0;
        endPos[0] = pos[0];
        endPos[1] = pos[1];
        endPos[2] = pos[2];

        g_TraceFilter_TargetEntity = obstructor;
        Handle trace = TR_TraceRayFilterEx(startPos, endPos, MASK_NPCSOLID,
                                           RayType_EndPoint, TraceFilter_OnlyTargetEntity);

        if (TR_DidHit(trace) && !TR_StartSolid(trace))
        {
            float hitPos[3];
            TR_GetEndPosition(hitPos, trace);
            topZ = hitPos[2];
            TR_GetPlaneNormal(trace, surfaceNormal);
            resolved = true;
        }
        delete trace;
        g_TraceFilter_TargetEntity = -1;
    }

    // AABB fallback: only when the ray trace could not resolve a top.
    if (!resolved)
    {
        static float vOrigin[3], vMaxs[3];
        GetEntPropVector(obstructor, Prop_Send, "m_vecOrigin", vOrigin);
        GetEntPropVector(obstructor, Prop_Send, "m_vecMaxs",  vMaxs);
        topZ = vOrigin[2] + vMaxs[2];
        surfaceNormal[0] = 0.0;
        surfaceNormal[1] = 0.0;
        surfaceNormal[2] = 1.0;
    }

    float adjustedPos[3];
    adjustedPos[0] = pos[0];
    adjustedPos[1] = pos[1];
    adjustedPos[2] = topZ + 2.0;

    if (IsObstructed(adjustedPos))
    {
        // IsObstructed just set g_iObstructingEntity to whatever blocks adjustedPos.
        // If that blocker is itself rescuable (stacked prop, pallet on table), recurse.
        if (g_GridRescueDepth < GRID_RESCUE_MAX_DEPTH)
        {
            g_GridRescueDepth++;
            bool ok = Grid_TryRescueObstruction(idx, adjustedPos);
            g_GridRescueDepth--;
            if (ok)
            {
                pos[0] = adjustedPos[0];
                pos[1] = adjustedPos[1];
                pos[2] = adjustedPos[2];
                g_iObstructingEntity = obstructor;
                return true;
            }
        }
        g_iObstructingEntity = obstructor;
        return false;
    }

    // Commit the rescue.
    pos[0] = adjustedPos[0];
    pos[1] = adjustedPos[1];
    pos[2] = adjustedPos[2];
    g_GridValidPositions[idx] = adjustedPos;
    g_GridOverridePositions[idx] = adjustedPos;
    g_GridHasOverride[idx] = true;
    g_GridOverrideFlat[idx] = (surfaceNormal[2] >= 0.98);
    g_GridOverrideNormals[idx][0] = surfaceNormal[0];
    g_GridOverrideNormals[idx][1] = surfaceNormal[1];
    g_GridOverrideNormals[idx][2] = surfaceNormal[2];

    g_iObstructingEntity = obstructor;
    return true;
}

static bool Grid_CheckObstruction(int idx, float pos[3], bool obstructed)
{
    float t = GetEngineTime();

    if (obstructed)
    {
        g_GridMs_obstruct += (GetEngineTime() - t) * 1000.0;
        g_GridN_obstructed++;
        return false;
    }

    if (IsObstructed(pos) && !Grid_TryRescueObstruction(idx, pos))
    {
        g_GridMs_obstruct += (GetEngineTime() - t) * 1000.0;
        g_GridN_obstructed++;
        return false;
    }

    g_GridMs_obstruct += (GetEngineTime() - t) * 1000.0;
    return true;
}

//static bool Grid_CheckDistance(float pos[3], Address navArea)
//{
//    float t = GetEngineTime();
//    
//    g_GridEffectiveMinDist = g_fSpawnMinDistance;
//    if (zm_stage < ZM_STARTED) g_GridEffectiveMinDist *= 2.0;
//    
//    if (g_GridEffectiveMinDist <= 0.0 || g_iBatchSurvivorCount == 0)
//    {
//        g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
//        return true;
//    }
//
//    float cellFlow = L4D_GetFlowFromPoint(pos);
//    bool tooClose = false;
//    int closestSurvByVec = -1;
//    float closestVecDist = 999999.0;
//
//    for (int s = 0; s < g_iBatchSurvivorCount; s++)
//    {
//        // Tier 1: flow distance
//        float flowDiff = FloatAbs(cellFlow - g_CachedSurvFlow[s]);
//        if (cellFlow > 0.0 && g_CachedSurvFlow[s] > 0.0
//            && flowDiff >= g_GridEffectiveMinDist)
//            continue;
//
//        // Tier 2: vector distance
//        float vecDist = GetVectorDistance(pos, g_fBatchSurvivorPos[s]);
//        if (vecDist >= g_GridEffectiveMinDist)
//            continue;
//
//        // Both too close - track closest survivor for potential NavMesh rescue
//        tooClose = true;
//        if (vecDist < closestVecDist)
//        {
//            closestVecDist = vecDist;
//            closestSurvByVec = s;
//        }
//    }
//
//    // Tier 3: bounded NavMesh path check for closest survivor only
//    if (tooClose && closestSurvByVec >= 0)
//    {
//        Address survNav = GetCachedSurvivorNavArea(closestSurvByVec);
//        if (survNav != Address_Null && navArea != Address_Null
//            && !L4D2_NavAreaBuildPath(navArea, survNav, g_GridEffectiveMinDist, TEAM_INFECTED, false))
//            tooClose = false;
//    }
//
//    // Last saferoom distance check
//    if (!tooClose)
//    {
//        float distLast = distance_last_saferoom(pos);
//        if (distLast > 0.0 && distLast <= DISTANCE_LAST_SAFEROOM)
//            tooClose = true;
//    }
//
//    if (tooClose)
//    {
//        g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
//        g_GridN_dist++;
//        return false;
//    }
//
//    g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
//    return true;
//}

// Run min_distance_to_survivors with store_client set to True until a valid survivor is hit with the grid cells. Then call the rest with
// This will allow flow spawns to function as intended.
static bool Grid_ValidateCell(int idx, float pos[3], Address navArea, bool obstructed)
{
    
    // Nav area attributes
    int navSpawnAttrs = -1; // skip LOS checks for obscured navmeshes
    float t = GetEngineTime();
    if (!nav_can_spawn_zombies(_,navArea,_,navSpawnAttrs))
    {
        g_GridMs_nav += (GetEngineTime() - t) * 1000.0;
        g_GridN_nav++;
        return false;
    }
    g_GridMs_nav += (GetEngineTime() - t) * 1000.0;
    
    // Distance to survivors + last saferoom
    t = GetEngineTime();
    //if (!Grid_CheckDistance(pos, navArea))
    //    return false;
    float distLast = distance_last_saferoom(pos);
    if (distLast > 0.0 && distLast < DISTANCE_LAST_SAFEROOM)
    {
        g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
        return false;
    }
    
    // Check survivor distance: only care about too close if not in grid spawner mode. Otherwise always check because we need to see if flow should trigger.
    if (g_fSpawnMinDistance>0.0 || g_iSpawnerMode==2)
    {
        float min_distance = -1.0;
        if (g_iSpawnerMode==2) min_distance = min_distance_to_survivors(pos,true,_,navArea); // determine down to flow trigger distance
        else
        {
            g_GridEffectiveMinDist = g_fSpawnMinDistance;
            if (zm_stage < ZM_STARTED) g_GridEffectiveMinDist /= 2.0;
            min_distance = min_distance_to_survivors(pos,false,g_GridEffectiveMinDist,navArea); // only care about too close
        }
        if (min_distance>=0.0 && g_iSpawnerMode==2) latest_distance = min_distance; // latest_distance is used to trigger flow
        if (distance_too_close(min_distance))
        {
            g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
            return false;
        }
    }
    g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
    
    // Obstruction (includes z rescue)
    if (!Grid_CheckObstruction(idx, pos, obstructed))
        return false;

    // Survivor line of sight
    t = GetEngineTime();
    
    bool obscured = navSpawnAttrs>0 && ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
    int cellCluster = GridLib_GetCellCluster(g_GridCellIndices[idx]);
    if (!obscured && can_any_alive_survivor_see_cheap(pos, cellCluster, navArea))
    {
        g_GridMs_los += (GetEngineTime() - t) * 1000.0;
        g_GridN_los++;
        return false;
    }
    g_GridMs_los += (GetEngineTime() - t) * 1000.0;

    g_GridN_valid++;
    return true;
}

// ==========================================================================
// Visual update (own timer)
// ==========================================================================

Action Grid_TimerUpdate(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClientZM() || client != zm_client || !g_bGridReady)
    {
        g_hGridTimer = null;
        return Plugin_Stop;
    }

    if (!GridLib_IsReady())
        return Plugin_Continue;
    
    g_iGridTargetClient = -1;
    
    // Hide grid when menu is closed or flow survivor glow is active
    if (zm_menu_state == ZM_MENU_CLOSED ||
       (g_iSpawnerMode<2 && get_spawner_target_survivor(false,_)>0) ||
       (g_iSpawnerMode==2 && Analog_CanSpawn(_,false,true)==SPAWNER_FLOW) )
    {
        if (g_GridCellCount > 0)
        {
            g_GridCellCount = 0;
            g_GridHasValidCell = false;
            g_GridValidCellCount = 0;
            GridRenderer_HideAll(client);
        }
        return Plugin_Continue;
    } 
    
    float t_start = GetEngineTime();
    bool over_budget = false;
    static float aimPos[3];
    //if (g_iSpawnerMode==1 && zm_spawner_state==SPAWNER_OK) aimPos = zm_spawner_pos;
    //else
    //{
        // Aim trace
        static float eyePos[3], eyeAngles[3];
        GetClientEyePosition(client, eyePos);
        GetClientEyeAngles(client, eyeAngles);
    
        Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_SOLID,
            RayType_Infinite, FilterSpawner, client);
    
        if (!TR_DidHit(trace))
        {
            delete trace;
            return Plugin_Continue;
        }
    
        TR_GetEndPosition(aimPos, trace);
        delete trace;
    //}

    // Find nearby cells
    float t_find = GetEngineTime();
    int nearbyCells[GRID_MAX_CELLS];
    
    //int cellCount = GridLib_FindNearbyCells(aimPos, GRID_SEARCH_RADIUS,
    //    GRID_MAX_Z_DIFF, nearbyCells, GRID_MAX_CELLS, _, GRID_BUDGET_MS);
    
    int cellCount = GridLib_FindCellsConnected(aimPos, GRID_MAX_CELLS, nearbyCells, GRID_MAX_CELLS, 300.0, _, GRID_BUDGET_MS, false);
    
    float ms_find = (GetEngineTime() - t_find) * 1000.0;
    
    //if (cellCount<=1 && g_iSpawnerMode==1 && zm_spawner_state==SPAWNER_OK)
    //{
    //    aimPos = zm_spawner_pos;
    //    cellCount = GridLib_FindNearbyCells(aimPos, GRID_SEARCH_RADIUS,GRID_MAX_Z_DIFF, nearbyCells, GRID_MAX_CELLS);
    //}
    
    if (cellCount == 0)
    {
        if (g_GridCellCount > 0)
            GridRenderer_HideAll(client);
        g_GridCellCount = 0;
        g_GridHasValidCell = false;
        g_GridValidCellCount = 0;
        if (g_iSpawnerMode==2) zm_spawner_state = SPAWNER_INVALID;
        return Plugin_Continue;
    }

    // Prepare validation context
    float t_validate = GetEngineTime();
    Spawner_CacheSurvivorData();

    g_GridMs_obstruct = 0.0;
    g_GridMs_nav = 0.0;
    g_GridMs_los = 0.0;
    g_GridMs_dist = 0.0;
    g_GridN_obstructed = 0;
    g_GridN_nav = 0;
    g_GridN_los = 0;
    g_GridN_dist = 0;
    g_GridN_valid = 0;
    g_LosN_fog = 0;
    g_LosN_nav_rej = 0;
    g_LosN_shortcut = 0;
    g_LosN_pvs_rej = 0;
    g_LosN_trace_hit = 0;
    g_LosN_safe_hit = 0;
    g_LosN_clear = 0;

    bool cellValid[GRID_MAX_CELLS];
    int closestValidIdx = -1;
    g_GridValidCellCount = 0;
    float closestDist = 999999.0;
    Address closestNavArea;

    for (int i = 0; i < GRID_MAX_CELLS; i++)
    {
        g_GridHasOverride[i] = false;
        g_GridOverrideFlat[i] = false;
    }

    // Validate each cell
    for (int i = 0; i < cellCount; i++)
    {
        float pos[3], normal[3];
        Address navArea;
        bool obstructed;
        
        if (!over_budget && ((GetEngineTime()-t_start)*1000.0)>=GRID_BUDGET_MS)
        {
            LogMessage("Grid_TimerUpdate over %1.f ms budget at %d/%d cells", GRID_BUDGET_MS, i, cellCount);
            over_budget = true;
        }

        if (over_budget || !GridLib_GetCellData(nearbyCells[i], pos, normal, navArea, obstructed))
        {
            cellValid[i] = false;
            continue;
        }

        g_GridValidPositions[i] = pos;
        g_GridCellIndices[i] = nearbyCells[i];

        cellValid[i] = Grid_ValidateCell(i, pos, navArea, obstructed);

        if (cellValid[i])
        {
            float dist = GetVectorDistance(aimPos, pos);
            if (closestValidIdx == -1 || dist < closestDist)
            {
                closestValidIdx = i;
                closestDist = dist;
                closestNavArea = navArea;
            }
        }
        else if (g_iSpawnerMode==2)
        {
            int target = get_spawner_target_survivor(false,_);
            if (target>0)
            {
                g_iGridTargetClient = target;
                if (g_iGlowList[target]==INVALID_ENT_REFERENCE && IsValidClientZM() && L4D2_GetSurvivorVictim(zm_client)!=target)
                {
                    CreateZMGlow(target,false,true);
                }
                closestValidIdx = -1;
                cellCount = 0;
                GridRenderer_HideAll(client);
                break;
            }
        }
        
    }

    float ms_validate = (GetEngineTime() - t_validate) * 1000.0;

    // Cache results
    g_GridCellCount = cellCount;
    g_GridHasValidCell = (closestValidIdx >= 0);
    for (int i = 0; i < cellCount; i++)
        g_GridValidFlags[i] = cellValid[i];

    if (g_GridHasValidCell)
    {
        g_GridClosestValidPos = g_GridValidPositions[closestValidIdx];
        if (g_iSpawnerMode==2)
        {
            zm_spawner_pos = g_GridClosestValidPos;
            zm_spawner_state = SPAWNER_OK;
            zm_spawner_navArea = closestNavArea;
        }
        g_GridValidCellIdx = closestValidIdx;
    }
    else
    {
        if (g_iSpawnerMode==2) zm_spawner_state = SPAWNER_SIGHT;
    }

    if (g_iSpawnerMode==2) zm_target_pos = aimPos;
    t_last_spawner_grid_update = GetGameTime();

    // Render
    float t_render = GetEngineTime();
    GridRenderer_DrawCells(client, g_GridCellIndices, cellValid, cellCount, closestValidIdx,
                           g_GridOverridePositions, g_GridHasOverride, g_GridOverrideFlat,
                           g_GridOverrideNormals);
    float ms_render = (GetEngineTime() - t_render) * 1000.0;

    float elapsed_ms = (GetEngineTime() - t_start) * 1000.0;
    if (elapsed_ms > 10.0)
    {
        LogMessage("[zm] WARNING: Grid_TimerUpdate took %.1f ms (%d cells: %d valid, %d obstructed, %d nav, %d LOS, %d dist) find=%.1f validate=%.1f [obstruct=%.1f nav=%.1f los=%.1f dist=%.1f] render=%.1f",
            elapsed_ms, cellCount, g_GridN_valid, g_GridN_obstructed,
            g_GridN_nav, g_GridN_los, g_GridN_dist,
            ms_find, ms_validate, g_GridMs_obstruct, g_GridMs_nav,
            g_GridMs_los, g_GridMs_dist, ms_render);
        LogMessage("[zm]   LOS breakdown: fog=%d nav_rej=%d shortcut=%d pvs_rej=%d trace_hit=%d safe_hit=%d clear=%d",
            g_LosN_fog, g_LosN_nav_rej, g_LosN_shortcut,
            g_LosN_pvs_rej, g_LosN_trace_hit, g_LosN_safe_hit, g_LosN_clear);
    }
    
    g_GridValidCellCount = g_GridN_valid;
    
    return Plugin_Continue;
}

// ==========================================================================
// Spawner_Update (no-op, grid uses own timer)
// ==========================================================================

int Grid_Update()
{
    if (g_iSpawnerMode==1 && IsValidClientZM()) Grid_TimerUpdate(null,GetClientUserId(zm_client));
    return zm_spawner_state;
}

// ==========================================================================
// Position resolution
// ==========================================================================

void Grid_BeginSpawn()
{
    g_bGridFlowUsed = false;
    g_iGridTargetClient = -1;
    g_bGridHint = false;
    g_bGridBatchMode = false;
    g_bGridSurvivorBeamDrawn = false;
}

int Grid_ResolveCommonPositions(int count, bool flow, bool angry, bool hint,
    float[] outPositions, int maxOut)
{
    // Flow spawns delegate to analog (grid is aim-based only)
    if ( flow || (!g_GridHasValidCell && g_iGridTargetClient>0) || (get_spawner_target_survivor(false,_)>0) )
    {
        Grid_BeginSpawn();
        g_bGridHint = hint;
        g_bGridBatchMode = true;
        int result = Analog_ResolveCommonPositions(count, flow, angry, hint, outPositions, maxOut);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

    Grid_BeginSpawn();
    g_bGridHint = hint;
    g_bGridBatchMode = true;

    if (!g_GridHasValidCell)
        return 0;

    // Return valid cell positions from last timer update
    int resolved = 0;
    for (int i = 0; i < g_GridCellCount && resolved < count && resolved < maxOut; i++)
    {
        if (!g_GridValidFlags[i]) continue;

        int idx = resolved * 3;
        outPositions[idx] = g_GridValidPositions[i][0];
        outPositions[idx+1] = g_GridValidPositions[i][1];
        outPositions[idx+2] = g_GridValidPositions[i][2];
        resolved++;
    }

    return resolved;
}

bool Grid_ResolveWitchPosition(bool flow, float outPos[3])
{
    if ( flow || (!g_GridHasValidCell && g_iGridTargetClient>0) || (get_spawner_target_survivor(false,_)>0) )
    {
        Grid_BeginSpawn();
        g_bGridHint = true;
        bool result = Analog_ResolveWitchPosition(flow, outPos);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

    Grid_BeginSpawn();
    g_bGridHint = true;

    if (!g_GridHasValidCell)
        return false;

    outPos = g_GridClosestValidPos;
    Grid_InvalidateClosestValid();
    return true;
}

bool Grid_ResolveSpecialPosition(int zombieclass, bool flow, float outPos[3])
{
    if ( flow || (!g_GridHasValidCell && g_iGridTargetClient>0) || (get_spawner_target_survivor(false,_)>0) )
    {
        Grid_BeginSpawn();
        g_bGridHint = true;
        bool result = Analog_ResolveSpecialPosition(zombieclass, flow, outPos);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

    Grid_BeginSpawn();
    g_bGridHint = true;

    if (!g_GridHasValidCell)
        return false;

    outPos = g_GridClosestValidPos;
    Grid_InvalidateClosestValid();
    return true;
}

// A grid cell will (probably) become red during this frame due to obstruction by a freshly spawned unit. Update relevant data to reflect this.
void Grid_InvalidateClosestValid()
{
    g_GridHasValidCell = false;
    g_GridValidFlags[g_GridValidCellIdx] = false;
    if (g_GridValidCellCount<=1) return; // no more green cells
    for (int i = 0; i < g_GridValidCellCount; i++)
    {
        if (g_GridValidFlags[i])
        {
            g_GridValidCellIdx = i;
            if (g_GridHasOverride[i]) g_GridClosestValidPos = g_GridOverridePositions[i];
            else g_GridClosestValidPos = g_GridValidPositions[i];
            g_GridHasValidCell = true;
            return;
        }
    }
}

// ==========================================================================
// Post-spawn notification (same pattern as analog)
// ==========================================================================

void Grid_NotifySpawned(int entity)
{
    if (!g_bGridFlowUsed || !g_bGridHint) return;
    if (entity <= 0 || !IsValidEntity(entity)) return;

    if (g_bGridBatchMode)
    {
        g_bGridSurvivorBeamDrawn = true;
        mark_flow_survivor_and_zombie(-1, entity);
    }
    else
    {
        mark_flow_survivor_and_zombie(g_iGridTargetClient, entity);
    }
}

void Grid_EndSpawn()
{
    if (g_bGridBatchMode && g_bGridFlowUsed && g_bGridHint && g_bGridSurvivorBeamDrawn)
        mark_flow_survivor_and_zombie(g_iGridTargetClient, -1);
}
