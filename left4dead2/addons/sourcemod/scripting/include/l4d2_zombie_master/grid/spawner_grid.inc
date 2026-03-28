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

#define GRID_SEARCH_RADIUS  150.0
#define GRID_MAX_Z_DIFF     100.0
#define GRID_MAX_CELLS      25
#define GRID_UPDATE_RATE    0.1

// State
static Handle g_hGridTimer;
static bool   g_bGridReady;

// Per-spawn flow marker state (same pattern as analog)
static bool   g_bGridFlowUsed;
static int    g_iGridTargetClient;
static bool   g_bGridHint;
static bool   g_bGridBatchMode;
static bool   g_bGridSurvivorBeamDrawn;

// Cached validation results from last timer update
static float  g_GridValidPositions[GRID_MAX_CELLS][3];
static bool   g_GridValidFlags[GRID_MAX_CELLS];
static int    g_GridCellIndices[GRID_MAX_CELLS];
static int    g_GridCellCount;
static float  g_GridClosestValidPos[3];
static bool   g_GridHasValidCell;

// Physics prop position overrides (runtime-adjusted positions on top of props)
static float  g_GridOverridePositions[GRID_MAX_CELLS][3];
static bool   g_GridHasOverride[GRID_MAX_CELLS];

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
    g_hGridTimer = CreateTimer(GRID_UPDATE_RATE, Grid_TimerUpdate,
        GetClientUserId(client), TIMER_REPEAT);
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

    // Get aim position
    float eyePos[3], eyeAngles[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAngles);

    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_SHOT,
        RayType_Infinite, FilterSpawner, client);

    if (!TR_DidHit(trace))
    {
        delete trace;
        return Plugin_Continue;
    }

    float aimPos[3];
    TR_GetEndPosition(aimPos, trace);
    delete trace;

    // Find nearby cells
    float t_find = GetEngineTime();
    int nearbyCells[GRID_MAX_CELLS];
    int cellCount = GridLib_FindNearbyCells(aimPos, GRID_SEARCH_RADIUS,
        GRID_MAX_Z_DIFF, nearbyCells, GRID_MAX_CELLS);
    float ms_find = (GetEngineTime() - t_find) * 1000.0;

    if (cellCount == 0)
    {
        g_GridCellCount = 0;
        g_GridHasValidCell = false;
        zm_spawner_state = SPAWNER_INVALID;
        return Plugin_Continue;
    }

    // Validate each cell using shared ZM validation functions
    float t_validate = GetEngineTime();
    Spawner_BeginBatchPVS();

    bool cellValid[GRID_MAX_CELLS];
    int closestValidIdx = -1;
    float closestDist = 999999.0;
    int nObstructed = 0, nNav = 0, nLOS = 0, nDist = 0, nValid = 0;
    float ms_obstruct = 0.0, ms_nav = 0.0, ms_los = 0.0, ms_dist = 0.0;

    // Pre-compute survivor positions + flow once for distance checks
    float cachedSurvPos[MAXPLAYERS+1][3];
    float cachedSurvFlow[MAXPLAYERS+1];
    int cachedSurvCount = 0;
    float effectiveMinDist = g_fSpawnMinDistance;
    if (zm_stage < ZM_STARTED) effectiveMinDist *= 2.0;
    for (int s = 1; s <= MaxClients; s++)
    {
        if (!IsClientInGame(s) || !IsPlayerAlive(s) || GetClientTeam(s) != TEAM_SURVIVOR) continue;
        GetClientAbsOrigin(s, cachedSurvPos[cachedSurvCount]);
        cachedSurvFlow[cachedSurvCount] = L4D2Direct_GetFlowDistance(s);
        cachedSurvCount++;
    }

    // Reset physics prop position overrides
    for (int i = 0; i < GRID_MAX_CELLS; i++)
        g_GridHasOverride[i] = false;

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

        // Shared validation: same checks as analog provider
        float t_check = GetEngineTime();
        if (obstructed)
        {
            ms_obstruct += (GetEngineTime() - t_check) * 1000.0;
            cellValid[i] = false;
            nObstructed++;
            continue;
        }
        if (IsObstructed(pos))
        {
            // If obstructed by a physics prop, try spawning on top of it
            int hitProp = -1;
            if (IsObstructedByPhysicsProp(pos, hitProp))
            {
                float topZ = GetPhysicsPropTopZ(hitProp, pos);
                float adjustedPos[3];
                adjustedPos[0] = pos[0];
                adjustedPos[1] = pos[1];
                adjustedPos[2] = topZ + 1.0;

                if (!IsObstructed(adjustedPos))
                {
                    // Use adjusted position for this cell
                    pos = adjustedPos;
                    g_GridValidPositions[i] = adjustedPos;
                    g_GridOverridePositions[i] = adjustedPos;
                    g_GridHasOverride[i] = true;
                }
                else
                {
                    ms_obstruct += (GetEngineTime() - t_check) * 1000.0;
                    cellValid[i] = false;
                    nObstructed++;
                    continue;
                }
            }
            else
            {
                ms_obstruct += (GetEngineTime() - t_check) * 1000.0;
                cellValid[i] = false;
                nObstructed++;
                continue;
            }
        }
        ms_obstruct += (GetEngineTime() - t_check) * 1000.0;

        t_check = GetEngineTime();
        if (!nav_can_spawn_zombies(false, navArea))
        {
            ms_nav += (GetEngineTime() - t_check) * 1000.0;
            cellValid[i] = false;
            nNav++;
            continue;
        }
        ms_nav += (GetEngineTime() - t_check) * 1000.0;

        t_check = GetEngineTime();
        if (can_any_alive_survivor_see_cheap(pos))
        {
            ms_los += (GetEngineTime() - t_check) * 1000.0;
            cellValid[i] = false;
            nLOS++;
            continue;
        }
        ms_los += (GetEngineTime() - t_check) * 1000.0;

        // Distance check: 3-tier (flow -> vector -> NavMesh for closest survivor only)
        // 1. Flow difference >= threshold: definitely far enough (free)
        // 2. Vector distance >= threshold: far enough (cheap)
        // 3. Both too close: try NavMesh travel for the closest-by-vector survivor only (1 call)
        //    NavMesh rescues cells in adjacent rooms with similar flow but long walking paths.
        t_check = GetEngineTime();
        if (effectiveMinDist > 0.0 && cachedSurvCount > 0)
        {
            float cellFlow = L4D_GetFlowFromPoint(pos);
            bool tooClose = false;
            int closestSurvByVec = -1;
            float closestVecDist = 999999.0;

            for (int s = 0; s < cachedSurvCount; s++)
            {
                // Tier 1: flow distance
                float flowDiff = FloatAbs(cellFlow - cachedSurvFlow[s]);
                if (cellFlow > 0.0 && cachedSurvFlow[s] > 0.0 && flowDiff >= effectiveMinDist)
                    continue;

                // Tier 2: vector distance
                float vecDist = GetVectorDistance(pos, cachedSurvPos[s]);
                if (vecDist >= effectiveMinDist)
                    continue;

                // Both too close - track closest survivor for potential NavMesh rescue
                tooClose = true;
                if (vecDist < closestVecDist)
                {
                    closestVecDist = vecDist;
                    closestSurvByVec = s;
                }
            }

            if (tooClose && closestSurvByVec >= 0)
            {
                // Tier 3: NavMesh travel for closest survivor only (1 call, not N)
                float navDist = L4D2_NavAreaTravelDistance(pos, cachedSurvPos[closestSurvByVec], false);
                if (navDist >= 0.0 && navDist >= effectiveMinDist)
                    tooClose = false; // rescued by NavMesh - walking path is long enough
            }

            if (tooClose)
            {
                ms_dist += (GetEngineTime() - t_check) * 1000.0;
                cellValid[i] = false;
                nDist++;
                continue;
            }
        }
        ms_dist += (GetEngineTime() - t_check) * 1000.0;

        cellValid[i] = true;
        nValid++;

        // Track closest valid cell to aim point
        float dist = GetVectorDistance(aimPos, pos);
        if (closestValidIdx == -1 || dist < closestDist)
        {
            closestValidIdx = i;
            closestDist = dist;
        }
    }

    Spawner_EndBatchPVS();
    float ms_validate = (GetEngineTime() - t_validate) * 1000.0;

    // Cache results
    g_GridCellCount = cellCount;
    g_GridHasValidCell = (closestValidIdx >= 0);
    for (int i = 0; i < cellCount; i++)
        g_GridValidFlags[i] = cellValid[i];

    if (g_GridHasValidCell)
    {
        g_GridClosestValidPos = g_GridValidPositions[closestValidIdx];
        zm_spawner_pos = g_GridClosestValidPos;
        zm_spawner_state = SPAWNER_OK;
        zm_spawner_navArea = L4D_GetNearestNavArea(g_GridClosestValidPos, 500.0, true, true, true, TEAM_INFECTED);
    }
    else
    {
        zm_spawner_state = SPAWNER_SIGHT;
    }

    zm_target_pos = aimPos;
    t_last_spawner_update = GetEngineTime();

    // Render via GridRenderer
    float t_render = GetEngineTime();
    GridRenderer_DrawCells(client, g_GridCellIndices, cellValid, cellCount, closestValidIdx,
                           g_GridOverridePositions, g_GridHasOverride);
    float ms_render = (GetEngineTime() - t_render) * 1000.0;

    float elapsed_ms = (GetEngineTime() - t_start) * 1000.0;
    if (elapsed_ms > 5.0)
        LogMessage("[zm] WARNING: Grid_TimerUpdate took %.1f ms (%d cells: %d valid, %d obstructed, %d nav, %d LOS, %d dist) find=%.1f validate=%.1f [obstruct=%.1f nav=%.1f los=%.1f dist=%.1f] render=%.1f",
            elapsed_ms, cellCount, nValid, nObstructed, nNav, nLOS, nDist,
            ms_find, ms_validate, ms_obstruct, ms_nav, ms_los, ms_dist, ms_render);

    return Plugin_Continue;
}

// ==========================================================================
// Spawner_Update (no-op, grid uses own timer)
// ==========================================================================

int Grid_Update()
{
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
    {
        // No valid grid cells - fall back to analog resolver
        int result = Analog_ResolveCommonPositions(count, false, angry, hint, outPositions, maxOut);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

    // Count valid cells - if fewer than requested, fall back to analog
    int validCount = 0;
    for (int i = 0; i < g_GridCellCount; i++)
    {
        if (g_GridValidFlags[i]) validCount++;
    }
    if (validCount < count)
    {
        int result = Analog_ResolveCommonPositions(count, false, angry, hint, outPositions, maxOut);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

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
    {
        bool result = Analog_ResolveWitchPosition(false, outPos);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

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
    {
        bool result = Analog_ResolveSpecialPosition(zombieclass, false, outPos);
        g_bGridFlowUsed = g_bAnalogFlowUsed;
        g_iGridTargetClient = g_iAnalogTargetClient;
        return result;
    }

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
