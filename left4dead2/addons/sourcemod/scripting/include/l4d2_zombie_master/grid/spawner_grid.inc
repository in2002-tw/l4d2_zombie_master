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
    if (client > 0 && client <= MaxClients)
        GridRenderer_OnClientDisabled(client);
}

// ==========================================================================
// Validation helpers
// ==========================================================================

static void Grid_CacheSurvivorData()
{
    g_GridCachedSurvCount = 0;
    g_GridEffectiveMinDist = g_fSpawnMinDistance;
    if (zm_stage < ZM_STARTED) g_GridEffectiveMinDist *= 2.0;
    for (int s = 1; s <= MaxClients; s++)
    {
        if (!IsClientInGame(s) || !IsPlayerAlive(s) || GetClientTeam(s) != TEAM_SURVIVOR) continue;
        GetClientAbsOrigin(s, g_GridCachedSurvPos[g_GridCachedSurvCount]);
        g_GridCachedSurvFlow[g_GridCachedSurvCount] = L4D2Direct_GetFlowDistance(s);
        g_GridCachedSurvCount++;
    }
    for (int i = 0; i < g_GridCachedSurvCount; i++)
        g_GridSurvNavAreaComputed[i] = false;
}

static Address Grid_GetSurvivorNavArea(int survIdx)
{
    if (!g_GridSurvNavAreaComputed[survIdx])
    {
        g_GridCachedSurvNavArea[survIdx] = L4D_GetNearestNavArea(
            g_GridCachedSurvPos[survIdx], 300.0, false, false, true, TEAM_SURVIVOR);
        g_GridSurvNavAreaComputed[survIdx] = true;
    }
    return g_GridCachedSurvNavArea[survIdx];
}

static bool Grid_TryPhysPropRescue(int idx, float pos[3])
{
    int hitProp = -1;
    if (!IsObstructedByPhysicsProp(pos, hitProp))
        return false;

    float topZ = GetPhysicsPropTopZ(hitProp, pos);
    float adjustedPos[3];
    adjustedPos[0] = pos[0];
    adjustedPos[1] = pos[1];
    adjustedPos[2] = topZ + 1.0;

    if (IsObstructed(adjustedPos))
        return false;

    pos[0] = adjustedPos[0];
    pos[1] = adjustedPos[1];
    pos[2] = adjustedPos[2];
    g_GridValidPositions[idx] = adjustedPos;
    g_GridOverridePositions[idx] = adjustedPos;
    g_GridHasOverride[idx] = true;
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

    if (IsObstructed(pos))
    {
        if (!Grid_TryPhysPropRescue(idx, pos))
        {
            g_GridMs_obstruct += (GetEngineTime() - t) * 1000.0;
            g_GridN_obstructed++;
            return false;
        }
    }

    g_GridMs_obstruct += (GetEngineTime() - t) * 1000.0;
    return true;
}

static bool Grid_CheckDistance(float pos[3], Address navArea)
{
    float t = GetEngineTime();

    if (g_GridEffectiveMinDist <= 0.0 || g_GridCachedSurvCount == 0)
    {
        g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
        return true;
    }

    float cellFlow = L4D_GetFlowFromPoint(pos);
    bool tooClose = false;
    int closestSurvByVec = -1;
    float closestVecDist = 999999.0;

    for (int s = 0; s < g_GridCachedSurvCount; s++)
    {
        // Tier 1: flow distance
        float flowDiff = FloatAbs(cellFlow - g_GridCachedSurvFlow[s]);
        if (cellFlow > 0.0 && g_GridCachedSurvFlow[s] > 0.0
            && flowDiff >= g_GridEffectiveMinDist)
            continue;

        // Tier 2: vector distance
        float vecDist = GetVectorDistance(pos, g_GridCachedSurvPos[s]);
        if (vecDist >= g_GridEffectiveMinDist)
            continue;

        // Both too close - track closest survivor for potential NavMesh rescue
        tooClose = true;
        if (vecDist < closestVecDist)
        {
            closestVecDist = vecDist;
            closestSurvByVec = s;
        }
    }

    // Tier 3: bounded NavMesh path check for closest survivor only
    if (tooClose && closestSurvByVec >= 0)
    {
        Address survNav = Grid_GetSurvivorNavArea(closestSurvByVec);
        if (survNav != Address_Null && navArea != Address_Null
            && !L4D2_NavAreaBuildPath(navArea, survNav, g_GridEffectiveMinDist, TEAM_INFECTED, false))
            tooClose = false;
    }

    // Last saferoom distance check
    if (!tooClose)
    {
        float distLast = distance_last_saferoom(pos);
        if (distLast > 0.0 && distLast <= DISTANCE_LAST_SAFEROOM)
            tooClose = true;
    }

    if (tooClose)
    {
        g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
        g_GridN_dist++;
        return false;
    }

    g_GridMs_dist += (GetEngineTime() - t) * 1000.0;
    return true;
}

static bool Grid_ValidateCell(int idx, float pos[3], Address navArea, bool obstructed)
{
    // 1. Obstruction (includes physics prop rescue)
    if (!Grid_CheckObstruction(idx, pos, obstructed))
        return false;

    // 2. Nav area attributes
    float t = GetEngineTime();
    if (!nav_can_spawn_zombies(false, navArea))
    {
        g_GridMs_nav += (GetEngineTime() - t) * 1000.0;
        g_GridN_nav++;
        return false;
    }
    g_GridMs_nav += (GetEngineTime() - t) * 1000.0;

    // 3. Survivor line of sight
    t = GetEngineTime();
    if (can_any_alive_survivor_see_cheap(pos))
    {
        g_GridMs_los += (GetEngineTime() - t) * 1000.0;
        g_GridN_los++;
        return false;
    }
    g_GridMs_los += (GetEngineTime() - t) * 1000.0;

    // 4. Distance to survivors + last saferoom
    if (!Grid_CheckDistance(pos, navArea))
        return false;

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

    // Hide grid when menu is closed or flow survivor glow is active
    if (zm_menu_state == ZM_MENU_CLOSED || g_bFlowSurvivorGlowActive)
    {
        if (g_GridCellCount > 0)
        {
            g_GridCellCount = 0;
            g_GridHasValidCell = false;
            GridRenderer_HideAll(client);
        }
        return Plugin_Continue;
    }

    float t_start = GetEngineTime();
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
    int cellCount = GridLib_FindNearbyCells(aimPos, GRID_SEARCH_RADIUS,
        GRID_MAX_Z_DIFF, nearbyCells, GRID_MAX_CELLS);
    float ms_find = (GetEngineTime() - t_find) * 1000.0;
    
    if (cellCount<=1 && g_iSpawnerMode==1 && zm_spawner_state==SPAWNER_OK)
    {
        aimPos = zm_spawner_pos;
        cellCount = GridLib_FindNearbyCells(aimPos, GRID_SEARCH_RADIUS,GRID_MAX_Z_DIFF, nearbyCells, GRID_MAX_CELLS);
    }
    
    if (cellCount == 0)
    {
        if (g_GridCellCount > 0)
            GridRenderer_HideAll(client);
        g_GridCellCount = 0;
        g_GridHasValidCell = false;
        if (g_iSpawnerMode==2) zm_spawner_state = SPAWNER_INVALID;
        return Plugin_Continue;
    }

    // Prepare validation context
    float t_validate = GetEngineTime();
    Spawner_BeginBatchPVS();
    Grid_CacheSurvivorData();

    g_GridMs_obstruct = 0.0;
    g_GridMs_nav = 0.0;
    g_GridMs_los = 0.0;
    g_GridMs_dist = 0.0;
    g_GridN_obstructed = 0;
    g_GridN_nav = 0;
    g_GridN_los = 0;
    g_GridN_dist = 0;
    g_GridN_valid = 0;

    bool cellValid[GRID_MAX_CELLS];
    int closestValidIdx = -1;
    float closestDist = 999999.0;
    Address closestNavArea;

    for (int i = 0; i < GRID_MAX_CELLS; i++)
        g_GridHasOverride[i] = false;

    // Validate each cell
    for (int i = 0; i < cellCount; i++)
    {
        float pos[3], normal[3];
        Address navArea;
        bool obstructed;

        if (!GridLib_GetCellData(nearbyCells[i], pos, normal, navArea, obstructed))
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
                           g_GridOverridePositions, g_GridHasOverride);
    float ms_render = (GetEngineTime() - t_render) * 1000.0;

    float elapsed_ms = (GetEngineTime() - t_start) * 1000.0;
    if (elapsed_ms > 5.0)
        LogMessage("[zm] WARNING: Grid_TimerUpdate took %.1f ms (%d cells: %d valid, %d obstructed, %d nav, %d LOS, %d dist) find=%.1f validate=%.1f [obstruct=%.1f nav=%.1f los=%.1f dist=%.1f] render=%.1f",
            elapsed_ms, cellCount, g_GridN_valid, g_GridN_obstructed,
            g_GridN_nav, g_GridN_los, g_GridN_dist,
            ms_find, ms_validate, g_GridMs_obstruct, g_GridMs_nav,
            g_GridMs_los, g_GridMs_dist, ms_render);

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
    if (flow)
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
    if (flow)
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
    return true;
}

bool Grid_ResolveSpecialPosition(int zombieclass, bool flow, float outPos[3])
{
    if (flow)
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
    return true;
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
