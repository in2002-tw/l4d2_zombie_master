///////////////////////////////////////
#if defined _zm_spawner_validate_included
 #endinput
#endif
#define _zm_spawner_validate_included
///////////////////////////////////////

/**
 * Shared spawner validation functions.
 * Used by both analog and grid providers for consistent cell/position filtering.
 */

bool DEBUG_SPAWNER = false;

// ==========================================================================
// Cell Cooldown - for reducing expensive revalidation
// ==========================================================================

// Check if cell is in cooldown
bool cell_cooldown(int cellIdx)
{
    if (g_fGridCooldown<=0.0 || !g_CellCooldown || g_CellCooldown.Size<=0) return false;
    char cellKey[8];
    FormatEx(cellKey,sizeof(cellKey), "%x", cellIdx);
    float t_cooldown; // gametime
    if (!g_CellCooldown.GetValue(cellKey,t_cooldown)) return false;
    if (t_cooldown>GetGameTime()) return true;
    g_CellCooldown.Remove(cellKey);
    return false;
}

// Set cell cooldown time
void set_cell_cooldown(int cellIdx, float t = -1.0)
{
    if (t<0.0)
    {
        if (g_fGridCooldown<=0.0) return;
        t = GetGameTime()+g_fGridCooldown;
    }
    char cellKey[8];
    FormatEx(cellKey,sizeof(cellKey), "%x", cellIdx);
    g_CellCooldown.SetValue(cellKey,t,true);
    LogMessage("%s %f", cellKey, t);
}

// Batch PVS state for accelerated visibility checks in GridLib filter callbacks + other survivor data.
// Call before a batch.
/**
 * Pre-compute data for all alive survivors. Call before a batch of
 * can_any_alive_survivor_see_cheap() calls (e.g. inside a GridLib filter).
 * PVS buffers are built once here and reused for every cell check.
 * Survivor death, map end and round end events automatically reset. 
 */
void Spawner_CacheSurvivorData()
{
	if (Is_Survivor_Cache_Valid()) return;
	g_bBatchPVSActive = hCheckOriginInPVS!=null;
	g_bBatchActive = false;
	g_iBatchSurvivorCount = 0;
	int cluster;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR || !IsPlayerAlive(i))
			continue;
		GetClientAbsOrigin(i, g_fBatchSurvivorPos[g_iBatchSurvivorCount]);
		g_CachedSurvFlow[g_iBatchSurvivorCount] = L4D2Direct_GetFlowDistance(i);
		GetClientEyePosition(i,g_fBatchSurvivorEyePos[g_iBatchSurvivorCount]);
		if (g_bBatchPVSActive)
		{
    		cluster = PVS_GetClusterForOrigin(g_fBatchSurvivorEyePos[g_iBatchSurvivorCount]);
    		g_BatchSurvivorCluster[g_iBatchSurvivorCount] = cluster;
    		if (cluster<0)
    		{
    		    g_BatchSurvivorValidPVS[g_iBatchSurvivorCount] = false;
    		}
    		else
    		{
        		g_BatchSurvivorValidPVS[g_iBatchSurvivorCount] = true;
        		PVS_GetForCluster(cluster, g_BatchSurvivorPVS[g_iBatchSurvivorCount]);
    		}
		}
		else
		{
		    g_BatchSurvivorCluster[g_iBatchSurvivorCount] = -1;
		}
		g_iBatchSurvivorClients[g_iBatchSurvivorCount] = i;
		g_CachedSurvNavArea[g_iBatchSurvivorCount] = L4D_GetNearestNavArea(
			g_fBatchSurvivorPos[g_iBatchSurvivorCount], 300.0, true, false, true, TEAM_SURVIVOR);
		g_SurvNavAreaComputed[g_iBatchSurvivorCount] = true;

		g_CachedSurvCell[g_iBatchSurvivorCount] = surv_pos_key(g_fBatchSurvivorEyePos[g_iBatchSurvivorCount]);

		g_iBatchSurvivorCount++;
	}
	g_bBatchActive = g_iBatchSurvivorCount>0;
	g_bBatchPVSActive = g_bBatchActive && g_bBatchPVSActive;
	if (g_bBatchActive) g_fBatchTime = GetGameTime();

	if (DEBUG_SPAWNER) LogMessage("[zm] Spawner_CacheSurvivorData: %d survivors, active=%d, PVS_active=%d",g_iBatchSurvivorCount,g_bBatchActive,g_bBatchPVSActive);
}

// Allow game events, namely survivor death and spawn, to reset cached survivor data.
// optional bool refresh: cache new survivor data immediately if a batch is actively being used for something.
void invalidate_survivor_cache(bool refresh = false)
{
    if (refresh && g_bBatchActive)
    {
        g_bBatchActive = false;
        Spawner_CacheSurvivorData();
        return;
    }
    g_bBatchPVSActive = false;
    g_bBatchActive = false;
    g_iBatchSurvivorCount = 0;
}

// Check if a survivor data batch is still valid.
bool Is_Survivor_Cache_Valid()
{
    if (g_bBatchActive)
    {
        if ( g_iAliveSurvivors!=g_iBatchSurvivorCount || (GetGameTime()-g_fBatchTime)>PVS_VALID_TIME)
        {
            invalidate_survivor_cache();
        }
    }
    else g_bBatchPVSActive = false;
    //LogMessage("Is_PVS_Valid %d %d", g_bBatchPVSActive, g_iBatchSurvivorCount);
    return g_bBatchActive;
}

// Check if PVS cache is valid
bool Is_PVS_Valid()
{
    if (g_bBatchPVSActive) Is_Survivor_Cache_Valid();
    return g_bBatchPVSActive;
}

Address GetCachedSurvivorNavArea(int survIdx)
{
    if (!g_SurvNavAreaComputed[survIdx])
    {
        g_CachedSurvNavArea[survIdx] = L4D_GetNearestNavArea(
            g_fBatchSurvivorPos[survIdx], 300.0, true, false, true, TEAM_SURVIVOR);
        g_SurvNavAreaComputed[survIdx] = true;
    }
    return g_CachedSurvNavArea[survIdx];
}


/**
 * Check if there are any alive survivors nearby. Extremely efficient if the l4dhooks native "L4D_FindEntityByClassnameWithin" is available.
 *
 * @param vecPos  The world position to check visibility for
 * @param radius Spherical radius around pos
 * @return        true if an alive survivor was found
 */
bool any_alive_survivors_in_radius(float vecPos[3], float radius)
{
    int i = INVALID_ENT_REFERENCE;
    if (l4dhooks_updated)
    {
        while( (i = L4D_FindEntityByClassnameWithin(i,"player",vecPos,radius)) != INVALID_ENT_REFERENCE )
        {
            if (IsValidClient(i) && GetClientTeam(i)==TEAM_SURVIVOR && IsPlayerAlive(i))
                return true;
        }
        return false;
    }
    else
    {
        float pos[3];
        for(i = 1; i <= MaxClients; i++)
        {
              if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
              {
                GetClientAbsOrigin(i,pos);
                if (GetVectorDistance(pos,vecPos)<radius) return true;
              }
        }
        return false;
    }
}

const int TR_MASK_LOS = MASK_VISIBLE;

// 1st survivor: 6 traces. 2nd: 5. 3rd: 4. 4th and the rest: 3.
#define MAX_TRACES LOS_TESTPOINTS
#define MIN_TRACES 3

/**
 * Check if LOS from `eyePos` to `testPoint` is blocked.
 *
 * Runs a single TR_TraceRayFilter with FilterLOS. The filter skips self, all clients,
 * witches, common infected, and other see-through classes so they don't spuriously
 * block survivor sightlines. Necessary because every useful LOS mask includes
 * CONTENTS_SOLID and players in L4D2 respond to CONTENTS_SOLID.
 *
 * @param eyePos     Eye position.
 * @param testPoint  Target point.
 * @param self       Entity index of the eye owner (client or door ent), passed to FilterLOS.
 * @return           true if LOS is blocked, false if visible.
 */
stock bool los_blocked(const float eyePos[3], const float testPoint[3], int self)
{
    TR_TraceRayFilter(eyePos, testPoint, TR_MASK_LOS, RayType_EndPoint, FilterLOS, self);
    return TR_DidHit(INVALID_HANDLE);
}

/**
 * Check if any alive survivor (or the saferoom door) can see a position.
 * Uses `LOS_TESTPOINTS` (3) test points distributed across the spawner hull. Each
 * testpoint is resolved via los_blocked() which runs a single TR_TraceRayFilter with
 * MASK_VISIBLE + FilterLOS (skips clients/NPCs/see-through classes; glass brushes
 * pass via the mask).
 *
 * @param vecPos       World position to test visibility against
 * @param cellCluster  Optional precomputed PVS leaf cluster of vecPos. When >= 0, enables
 *                     the same-cluster shortcut (skip PVS_CheckOriginInPVS when survivor
 *                     sits in the same cluster: Pass -1 (default) when unknown.
 * @param cellNavArea  Optional nav area of vecPos. When non-null and the nav-area
 *                     SDKCall is available, the director's lazily-maintained per-team
 *                     visibility bit gates the PVS loop
 * @param cellIdx      Optional GridLib target cell idx for vecPos. When >= 0 and the
 *                     `zm_los_cellcache` cvar is on, enables the shared cell-pair LOS
 *                     cache lookup (see los_cellcache.inc). Pass -1 (default) for non-grid callers.
 * @return             true if any alive survivor or the saferoom door has line of sight
 */
bool can_any_alive_survivor_see_cheap(float vecPos[3], int cellCluster = -1, Address cellNavArea = Address_Null, int cellIdx = -1)
{
    if (DEBUG) LogMessage("[zm] can_any_alive_survivor_see_cheap");
    
    if (l4dhooks_updated && !any_alive_survivors_in_radius(vecPos,fog_distance))
    {
        g_LosN_fog++;
        return false; // very fast early exit when no survivor within fog radius
    }
    
    // LOS_TESTPOINTS (6) sample points around the spawner hull
    // Ordered by priority. The ones more likely to hit should always go first.
    static float testPoints[LOS_TESTPOINTS][3];
    testPoints[0] = vecPos; testPoints[0][2] += HULL_DZ;
    testPoints[1] = vecPos; testPoints[1][2] += HULL_DDZ; testPoints[1][0] -= 4.0; testPoints[1][1] += 5.0;
    testPoints[2] = vecPos; testPoints[2][2] += HULL_DZ_MIN_STRICT; testPoints[2][0] += HULL_DX; testPoints[2][1] -= HULL_DX;
    testPoints[3] = vecPos; testPoints[3][2] += HULL_DZ; testPoints[3][0] -= HULL_DX; testPoints[3][1] += HULL_DX;
    testPoints[4] = vecPos; testPoints[4][2] += HULL_DDZ; testPoints[4][0] += HULL_DX; testPoints[4][1] += HULL_DX;
    testPoints[5] = vecPos; testPoints[5][2] += HULL_DZ; testPoints[5][0] -= HULL_DX; testPoints[5][1] -= HULL_DX;
    int num_traces = MAX_TRACES; // start with MAX_TRACES, after each set, reduce number of traces by 1 until we fire only MIN_TRACES.
    
    //LogMessage("can_any_alive_survivor_see_cheap spawner mode: %d cluster %d navArea %d cell %d", g_iSpawnerMode, cellCluster, cellNavArea, cellIdx);
    
    int i;
    int temp_traces = num_traces;
    
    bool check_nav = hNavIsPotentiallyVisibleToTeam!=null || hNavIsPotentiallyVisible!=null;
    if (check_nav) // check visibility between two navmeshes
    {
        if (cellNavArea == Address_Null) cellNavArea = L4D_GetNearestNavArea(vecPos, 300.0, true, false, true, TEAM_INFECTED);
        check_nav = cellNavArea != Address_Null; // check IsPotentiallyVisibleToTeam and IsPotentiallyVisible
    }
    
    // Check saferoom door to prevent ZM abusing survivors not looking out door.
    if (zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor))
    {
        static float saferoom_pos[3];
        L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,saferoom_pos);
        if (GetVectorDistance(saferoom_pos,vecPos,true) <= fog_distance_sq)
        {
            float t_safe = GetEngineTime();
            if (check_nav) // reduce number of traces if both navs can't see each other
            {
                Address navArea_saferoom = L4D_GetNearestNavArea(saferoom_pos, 300.0, true, false, true, TEAM_SURVIVOR);
                if (navArea_saferoom != Address_Null && !NavArea_IsPotentiallyVisible(cellNavArea,navArea_saferoom,false))
                temp_traces = 1;
            }
            g_LosN_safe_enter++;
            int door = EntRefToEntIndex(g_iLockedDoor);
            for (i = 0; i < temp_traces; i++)
            {
                g_LosN_safe_trace++;
                if (!los_blocked(saferoom_pos, testPoints[i], door))
                {
                    g_LosN_safe_hit++;
                    g_LosMs_safe += (GetEngineTime() - t_safe) * 1000.0;
                    return true;
                }
            }
            if (num_traces>MIN_TRACES && temp_traces>=num_traces) num_traces -= 1;
            g_LosMs_safe += (GetEngineTime() - t_safe) * 1000.0;
        }
    }

    // Nav-area visibility pre-reject: if the director's recent-visibility list for the survivor team
    // does not include this area, no survivor has marked it as seeable.
    if (check_nav && hNavIsPotentiallyVisibleToTeam!=null && !NavArea_IsPotentiallyVisibleToTeam(cellNavArea, TEAM_SURVIVOR))
    {
        g_LosN_nav_rej++;
        //num_traces = MIN_TRACES;
        num_traces = 1;
        //LogMessage("IsPotentiallyVisibleToTeam false, num_traces reduced");
        check_nav = false; // MIN_TRACES already reduced
        //return false;
    }
    
    Spawner_CacheSurvivorData(); // optimization - load survivor data or read cached values
    bool use_PVS = Is_PVS_Valid();
    bool use_PVS_SameCluster = true; // use PVS same cluster shortcut
    bool use_LOS_cache = true;
    check_nav = check_nav && hNavIsPotentiallyVisible!=null; // only checking IsPotentiallyVisible from here
    float t_surv = GetEngineTime();
    
    if (use_PVS_SameCluster && cellCluster<0 && use_PVS) cellCluster = PVS_GetClusterForOrigin(vecPos);

    // Build per-cell survivor iteration order: closest-first maximises the chance of
    // early-exiting on the first visible trace. Fog-distance and valid-client gates
    // are applied up-front so the hot loop below deals only with candidates.
    static int   surv_order[MAXPLAYERS+1];
    static float surv_distsq[MAXPLAYERS+1];
    int surv_n = 0;
    for (int s = 0; s < g_iBatchSurvivorCount; s++)
    {
        float dsq = GetVectorDistance(g_fBatchSurvivorPos[s], vecPos, true);
        if (dsq >= fog_distance_sq) continue;
        if (!IsValidClient(g_iBatchSurvivorClients[s])) continue;
        int j = surv_n - 1;
        while (j >= 0 && surv_distsq[j] > dsq)
        {
            surv_order[j+1]  = surv_order[j];
            surv_distsq[j+1] = surv_distsq[j];
            j--;
        }
        surv_order[j+1]  = s;
        surv_distsq[j+1] = dsq;
        surv_n++;
    }
    
    for (int o = 0; o < surv_n; o++)
    {
        int s = surv_order[o];
        temp_traces = num_traces;

        // Shared cell-pair cache: skip the work when (surv_subcell_key, target_cell) is
        // already known within its TTL. Eligibility: cache enabled, target has a grid
        // cell idx. The survivor key is always a valid packed position hash.
        int survCellKey = g_CachedSurvCell[s];
        bool cacheEligible = use_LOS_cache && g_bLosCellCache && cellIdx >= 0;
        if (cacheEligible)
        {
            bool cachedRes;
            if (cellcache_lookup(survCellKey, cellIdx, cachedRes))
            {
                if (cachedRes)
                {
                    g_LosN_cellcache_hit_vis++;
                    g_LosMs_surv += (GetEngineTime() - t_surv) * 1000.0;
                    return true;
                }
                g_LosN_cellcache_hit_blk++;
                continue; // cached as blocked for this survivor-cell pair; move on
            }
        }

        if (use_PVS)
        {
            // Same-cluster shortcut: two points in one leaf cluster are trivially mutually visible via PVS.
            // Skip any per-pair visibility check and go straight to the trace.
            if (use_PVS_SameCluster && (cellCluster >= 0 && cellCluster == g_BatchSurvivorCluster[s]) )
            {
                g_LosN_shortcut++;
                //LogMessage("%d same-cluster", s);
            }
            else
            {
                // Legacy per-survivor PVS byte-buffer check
                if (!g_BatchSurvivorValidPVS[s] || !PVS_CheckOriginInPVS(vecPos, g_BatchSurvivorPVS[s]))
                {
                    g_LosN_pvs_rej++;
                    //LogMessage("%d not in PVS, skip trace rays", s);
                    continue;
                }
            }
            
            // per-area-pair bitset lookup. Engine's own fast path.
            // Falls back to legacy per-survivor PVS byte-buffer check when:
            //  - SDKCall not bound (Microslop windows))
            //  - cell or survivor nav area is null
           // bool pairChecked = false;
            //bool pairVisible = true;
            //if (check_nav && g_CachedSurvNavArea[s] != Address_Null)
            //{
            //    pairChecked = true;
            //    pairVisible = NavArea_IsPotentiallyVisible(cellNavArea, g_CachedSurvNavArea[s], false);
            //}
    
            //if (pairChecked)
            //{
                //if (!pairVisible)
                //{
                    //g_LosN_pvs_rej++;
                    //temp_traces = MIN_TRACES;
                    //continue;
                //}
            //}
            
        }
        
        if (check_nav && temp_traces>MIN_TRACES && g_CachedSurvNavArea[s] != Address_Null && !NavArea_IsPotentiallyVisible(cellNavArea, g_CachedSurvNavArea[s], false))
        {
            //LogMessage("%d IsPotentiallyVisible false, reduce temp_traces", s);
            //temp_traces = MIN_TRACES;
            temp_traces = 1;
        }
        
        
        for (i = 0; i < temp_traces; i++)
        {
            g_LosN_surv_trace++;
            bool blocked = los_blocked(g_fBatchSurvivorEyePos[s],testPoints[i],g_iBatchSurvivorClients[s]);
            if (!blocked)
            {
                g_LosN_trace_hit++;
                if (cacheEligible)
                {
                    cellcache_populate(survCellKey, cellIdx, true, g_fLosCellCacheTTL);
                    g_LosN_cellcache_miss++;
                }
                g_LosMs_surv += (GetEngineTime() - t_surv) * 1000.0;
                return true;
            }
        }
        if (num_traces>MIN_TRACES && temp_traces>=num_traces) num_traces -= 1;
        // All testpoints blocked for this survivor.
        if (cacheEligible)
        {
            cellcache_populate(survCellKey, cellIdx, false, g_fLosCellCacheTTL);
            g_LosN_cellcache_miss++;
        }
    }
    g_LosMs_surv += (GetEngineTime() - t_surv) * 1000.0;

    g_LosN_clear++;
    return false;
}

// Find nearest s-index of cached survivor to a given vector position
int nearest_cached_survivor_index(float pos[3])
{
    Spawner_CacheSurvivorData();
    int s_best = -1;
    float dsq;
    float dsq_best = -1.0;
    for (int s = 0; s < g_iBatchSurvivorCount; s++)
    {
        if (!IsValidClient(g_iBatchSurvivorClients[s])) continue;
        dsq = GetVectorDistance(g_fBatchSurvivorPos[s],pos,true);
        if (dsq_best<0.0 || dsq<dsq_best)
        {
            dsq_best = dsq;
            s_best = s;
        }
    }
    return s_best;
}

// Can survivor team travel to a given vector position where a zombie is about to spawn?
// Optional navAreaSurv: when you know the nearest survivor navmesh. If null wil be calculated automatically
bool Survivors_CanTravelTo_Pos(float pos[3],
                               Address navArea = Address_Null,
                               Address navAreaSurv = Address_Null,
                               float max_distance = 5000.0)
{
    if (navArea == Address_Null) navArea = L4D_GetNearestNavArea(pos, 300.0, true, false, true, TEAM_SURVIVOR);
    if (navArea == Address_Null) return false;
    if (navAreaSurv == Address_Null)
    {
        int s_best = nearest_cached_survivor_index(pos);
        if (s_best<0) return false;
        navAreaSurv = GetCachedSurvivorNavArea(s_best);
    }
    if (navAreaSurv == Address_Null) return false;
    return L4D2_NavAreaBuildPath(navAreaSurv,navArea,max_distance,TEAM_SURVIVOR,false);
}

// Should we exit min_distance_to_survivors early?
// If safe distance is larger than 150.0, we need to check if we satisfy flow conditions.
// If store_client is false means we don't care about flow.
bool distance_early_exit(float distance, float safe_distance, bool store_client)
{
    return (!store_client || distance<150.0) && distance<safe_distance;
}

// Is given distance to survivors too close to spawn zombies? -1.0 for invalid values
bool distance_too_close(float distance)
{
    if (g_fSpawnMinDistance<=0.0) return false;
    if (zm_stage<ZM_STARTED) distance *= 2.0; // allow spawns close to saferoom before round start
    if (distance>=0.0 && distance<g_fSpawnMinDistance) return true;
    return false;
}

/**
 * Find the smallest travel distance from pos to any alive survivor or first saferoom door. The result may trigger flow.
 *
 * @param pos           The world position to measure from
 * @param store_client  If true, store the nearest survivor client index in spawner_nearest_survivor. For flow spawns.
 * @param safe_distance  Safe distance. Ignore everything more distant than this. We exit early if there are no entities to consider within a sphere of this radius.
 * @param navArea  optional pre-computed navArea of pos. If not provided will be computed during the call.
 * @return              Minimum distance to survivors, or -1.0 if no valid measurement
 */
float min_distance_to_survivors(float pos[3], bool store_client=false, float safe_distance = -1.0, Address navArea = Address_Null)
{
    if (store_client) spawner_nearest_survivor = -1;
    if (safe_distance<0.0)
    {
        safe_distance = (zm_stage<ZM_STARTED) ? g_fSpawnMinDistance/2.0 : g_fSpawnMinDistance;
        if (safe_distance<150.0) safe_distance = 150.0; // 150.0 for "survivor being targeted" detection
    }
    
    bool include_saferoom = zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor);
    static float pos_saferoom[3];
    float vector_distance_saferoom = -1.0;
    float min_distance = -1.0; // travel distance
    
    bool hit = false; // is there anything closer than "too close"?
    if (include_saferoom) // Check first saferoom
    {
         GetEntPropVector(g_iLockedDoor,Prop_Send,"m_vecOrigin",pos_saferoom);
         vector_distance_saferoom = GetVectorDistance(pos,pos_saferoom);
         if (vector_distance_saferoom<safe_distance) hit = true;
         else include_saferoom = false; // ignore saferoom completely - it's too far away.
    }
    if (!hit) hit = !l4dhooks_updated || any_alive_survivors_in_radius(pos,safe_distance);
    if (!hit) return safe_distance+1.0; // survivors and first saferoom too far -> exit now
   
    Spawner_CacheSurvivorData();
    float flow_pos = L4D_GetFlowFromPoint(pos);
    if (navArea == Address_Null) navArea = L4D_GetNearestNavArea(pos, 300.0, true, false, true, TEAM_INFECTED);
    
    float flowDiff, vecDist;
    Address survNav;
    for (int s = 0; s < g_iBatchSurvivorCount; s++) // Check alive survivors
    {
        vecDist = GetVectorDistance(pos, g_fBatchSurvivorPos[s]); // Vector distance
        if (vecDist >= safe_distance) continue;
        if (flow_pos>0.0 && g_CachedSurvFlow[s]>0.0) // Flow distance
        {
            // Flow is meaningful - find smallest flow diff survivor, check nav travel distance only for the closest one.
            flowDiff = FloatAbs(flow_pos - g_CachedSurvFlow[s]);
            if (flowDiff >= safe_distance) continue;
            if (flowDiff < vecDist) flowDiff = vecDist; // reasonably, travel distance should never be smaller than vector distance
            if (min_distance<0.0 || flowDiff<min_distance)
            {
                min_distance = flowDiff;
                if (store_client) spawner_nearest_survivor = g_iBatchSurvivorClients[s];
                if (distance_early_exit(min_distance,safe_distance,store_client)) return min_distance;
            }
        }
        else if (navArea != Address_Null)
        {
            // Flow is useless - check if any connection can be made within safe_distance. If so, use vector distance as final distance.
            if (min_distance>=0.0 && vecDist>min_distance) continue; // smaller distance already found
            survNav = GetCachedSurvivorNavArea(s);
            if (survNav == Address_Null) continue;
            if (!L4D2_NavAreaBuildPath(navArea,survNav,safe_distance,TEAM_INFECTED,false)) continue; // no connection
            min_distance = vecDist;
            if (store_client) spawner_nearest_survivor = g_iBatchSurvivorClients[s];
            if (distance_early_exit(min_distance,safe_distance,store_client)) return min_distance;
        }
        else continue;
    }
    
    // Check first saferoom
    if (include_saferoom)
    {
        bool check_nav = false;
        if (flow_pos>0.0)
        {
            float flow_saferoom = L4D_GetFlowFromPoint(pos_saferoom);
            if (flow_saferoom>0.0)
            {
                flowDiff = FloatAbs(flow_pos-flow_saferoom);
                if (flowDiff<safe_distance)
                {
                    if (flowDiff<vector_distance_saferoom) flowDiff = vector_distance_saferoom;
                    if (min_distance<0.0 || flowDiff<min_distance) min_distance = flowDiff;
                }
            }
            else check_nav = true;
        }
        else check_nav = true;
        
        if (check_nav)
        {
            if (min_distance<0.0 || vector_distance_saferoom<min_distance)
            {
                Address navArea_saferoom = L4D_GetNearestNavArea(pos_saferoom, 300.0, true, false, true, TEAM_INFECTED);
                if (navArea_saferoom != Address_Null && L4D2_NavAreaBuildPath(navArea,navArea_saferoom,safe_distance,TEAM_INFECTED,false))
                    min_distance = vector_distance_saferoom;
            }
        }
    }
    
    if (min_distance<0.0) return safe_distance+1.0;
    return min_distance;
}

//float min_distance_to_survivors_old(float pos[3], bool store_client=false, float min_distance = -1.0)
//{
//   if (DEBUG) LogMessage("[zm] min_distance_to_survivors");
//   // d_min is the final value. nav distance and vector distance are calculated independently, and then we think.
//   // -1.0 are invalid values, we will deal with them later
//   float d_nav_temp, d_raw_temp;
//   float d_min = -1.0;
//   float d_nav = -1.0;
//   float d_raw = -1.0;
//   float pos2[3];
//   if (store_client) spawner_nearest_survivor = -1;
//   // Is there at least one survivor close enough? If not, end early.
//   bool hit = true;
//   if (min_distance<0.0) min_distance = (g_fSpawnMinDistance<150.0) ? 150.0 : g_fSpawnMinDistance; // 150.0 for "survivor being targeted" detection
//   if (l4dhooks_updated) hit = any_alive_survivors_in_radius(pos,min_distance);
//   if (!hit) return min_distance+1.0;
//    if (zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor)) // Check first saferoom
//    {
//         L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,pos2);
//         d_raw_temp = GetVectorDistance(pos,pos2);
//         if (d_raw<0.0 || d_raw_temp<d_raw) d_raw = d_raw_temp;
//         d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false);
//         if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav)) d_nav = d_nav_temp;
//    }
//
//   int i = INVALID_ENT_REFERENCE;
//   for(i = 1; i <= MaxClients; i++)
//   {
//        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=TEAM_SURVIVOR) continue;
//        L4D_GetEntityWorldSpaceCenter(i,pos2);
//        d_raw_temp = GetVectorDistance(pos,pos2);
//        if (d_raw<0.0 || d_raw_temp<d_raw)
//        {
//            d_raw = d_raw_temp;
//            if (store_client) spawner_nearest_survivor = i;
//        }
//
//        d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false); // can return -1.0 for no path
//        if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
//        {
//           d_nav = d_nav_temp;
//            if (store_client) spawner_nearest_survivor = i;
//            if (d_nav<150.0) return d_nav;
//        }
//
//        // If round has started, check if survivors might appear here soon.
//        if (zm_stage==ZM_STARTED)
//        {
//            d_nav_temp = L4D2_NavAreaTravelDistance(pos2,pos,false);
//            if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
//            {
//                d_nav = d_nav_temp;
//                if (store_client) spawner_nearest_survivor = i;
//            }
//        }
//        if (d_nav<150.0 && d_raw<150.0 && d_nav<min_distance && d_raw<min_distance) break; // targeting survivor
//   }
//
//    if (d_nav>=0.0) d_min = d_nav>d_raw ? d_nav : d_raw;
//    return d_min;
//}

// Special TraceFilter: pass through entities with hp except alive survivors.
stock bool FilterSpawner_HitSurvivors(int entity, int mask, int self)
{
	if (!IsValidEntity(entity)) return false;
	if (entity==self) return false;
	if (GetEntProp(entity,Prop_Data,"m_iHealth")>0)
	{
    	if (IsValidClient(entity) && GetClientTeam(entity)==TEAM_SURVIVOR && IsPlayerAlive(entity)) return true;
    	return false;
	}
	static char class[32];
	GetEntityClassname(entity, class, sizeof(class));
	if (strcmp(class,"func_playerinfected_clip")==0) return false;
	if (strcmp(class,"func_clip_vphysics")==0) return false;
	if (strcmp(class,"func_playerghostinfected_clip")==0) return false;
	if (strcmp(class,"func_vehicleclip")==0) return false;
	if (strcmp(class,"script_clip_vphysics")==0) return false;
	if (strcmp(class,"env_physics_blocker")==0) return false;
	if (strcmp(class,"env_player_blocker")==0) return false;
	if (strcmp(class,"entity_blocker")==0) return false;
	return true;
}

Action check_fog_distance(Handle timer = null)
{
    if (DEBUG) LogMessage("[zm] check_fog_distance");
    float new_fog_distance = FOG_DISTANCE;
	int fog_controller = -1;
	while( (fog_controller = FindEntityByClassname(fog_controller, "env_fog_controller")) != INVALID_ENT_REFERENCE )
	{
		if (g_DHook_AcceptInput)
     	{
           	if (IsValidEntity(fog_controller))
           	{
           	   if (DEBUG) LogMessage("[zm] Hooking fog_controller g_DHook_AcceptInput");
           	   DHookEntity(g_DHook_AcceptInput, true, fog_controller, INVALID_FUNCTION, DHook_Fog_AcceptInput);
           	}
     	}
		bool enabled = GetEntProp(fog_controller, Prop_Data, "m_fog.enable") > 0;
		if (enabled)
		{
        		float fog_end = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.end");
        		float fog_farz = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.farz");
        		float maxdensity = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.maxdensity");
        		if (DEBUG) LogMessage("[zm] Found env_fog_controller %d", fog_controller);
        		if (DEBUG) LogMessage("[zm] end farz maxdensity: %f %f %f", fog_end, fog_farz, maxdensity);
        		if (maxdensity>=1.0)
        		{
            		if (fog_farz<new_fog_distance && fog_farz>0.0) new_fog_distance = fog_farz;
        		}
    		
		}
	}
	
	// FUTURE Better idea: loop over alive survivors and check their active fog entity.
	
	if (new_fog_distance!=fog_distance)
	{
	    fog_distance = new_fog_distance;
	    fog_distance_sq = new_fog_distance * new_fog_distance;
	    CreateTimer(10.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(30.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(45.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	    CreateTimer(60.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
        LogMessage("[zm] ZM spawner fog distance: %f", fog_distance);
	}
	return Plugin_Stop;
}

MRESReturn DHook_Fog_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (DEBUG) LogMessage("[zm] DHook_Fog_AcceptInput");
	if (!g_bCvarAllow) return MRES_Ignored;
	check_fog_distance();
	CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	return MRES_Ignored;
}
