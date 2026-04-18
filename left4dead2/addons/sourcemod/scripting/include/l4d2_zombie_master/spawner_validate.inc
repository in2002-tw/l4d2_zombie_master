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
	g_bBatchPVSActive = false;
	g_bBatchActive = false;
	g_iBatchSurvivorCount = 0;
	static float eyePos[3];
	int cluster;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR || !IsPlayerAlive(i))
			continue;
		GetClientAbsOrigin(i, g_fBatchSurvivorPos[g_iBatchSurvivorCount]);
		g_CachedSurvFlow[g_iBatchSurvivorCount] = L4D2Direct_GetFlowDistance(i);
		if (hCheckOriginInPVS!=null)
		{
    		GetClientEyePosition(i, eyePos);
    		cluster = PVS_GetClusterForOrigin(eyePos);
    		if (cluster<0) g_BatchSurvivorValidPVS[g_iBatchSurvivorCount] = false;
    		else
    		{
        		g_BatchSurvivorValidPVS[g_iBatchSurvivorCount] = true;
        		PVS_GetForCluster(cluster, g_BatchSurvivorPVS[g_iBatchSurvivorCount]);
    		}
		}
		g_iBatchSurvivorClients[g_iBatchSurvivorCount] = i;
		g_SurvNavAreaComputed[g_iBatchSurvivorCount] = false;
		g_iBatchSurvivorCount++;
	}
	g_bBatchActive = g_iBatchSurvivorCount>0;
	g_bBatchPVSActive = g_bBatchActive && hCheckOriginInPVS!=null;
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
            g_fBatchSurvivorPos[survIdx], 300.0, false, false, true, TEAM_SURVIVOR);
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

/**
 * Check if any alive survivor (or the saferoom door) has line of sight to a position.
 * Tests multiple points on the spawn hull to prevent partial-visibility exploits.
 * First does a cheap distance cull (fog_distance), then ray traces for actual visibility.
 *
 * @param vecPos  The world position to check visibility for
 * @param hint    If true, show a HUD hint to the ZM explaining why the spot is visible
 * @return        true if any survivor can see the position
 */
//bool can_any_alive_survivor_see(float vecPos[3], bool hint = true)
//{
//   if (DEBUG) LogMessage("[zm] can_any_alive_survivor_see");
//   bool visible = false;
//   
//   static float VecPos2[3]; AddVectors(vecPos,{0.0,0.0,HULL_DZ},VecPos2);
//   static float VecPos3[3]; AddVectors(vecPos,{-HULL_DX,-HULL_DX,HULL_DZ},VecPos3);
//   static float VecPos4[3]; AddVectors(vecPos,{HULL_DX,HULL_DX,HULL_DZ},VecPos4);
//   static float VecPos5[3]; AddVectors(vecPos,{HULL_DX,-HULL_DX,HULL_DDZ},VecPos5);
//   static float VecPos6[3]; AddVectors(vecPos,{0.0,0.0,HULL_DDZ},VecPos6);
//
//   // Check line of sight with saferoom door
//   if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
//   {
//        int filter_client = -1;
//        if (IsValidClientZM()) filter_client = zm_client;
//        int door = EntRefToEntIndex(g_iLockedDoor);
//        static float saferoom_pos[3];
//        L4D_GetEntityWorldSpaceCenter(door,saferoom_pos);
//        saferoom_pos[2] -= 10.0;
//        if (GetVectorDistance(saferoom_pos,vecPos)<=fog_distance)
//        {
//            Handle trace = TR_TraceRayFilterEx(vecPos,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//            if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//            delete trace;
//            if (!visible)
//            {
//                trace = TR_TraceRayFilterEx(VecPos2,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//                delete trace;
//            }
//            if (!visible)
//            {
//                trace = TR_TraceRayFilterEx(VecPos3,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//                delete trace;
//            }
//            if (!visible)
//            {
//                trace = TR_TraceRayFilterEx(VecPos4,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//                delete trace;
//            }
//            if (!visible)
//            {
//                trace = TR_TraceRayFilterEx(VecPos5,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//                delete trace;
//            }
//            if (!visible)
//            {
//                trace = TR_TraceRayFilterEx(VecPos6,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
//                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
//                delete trace;
//            }
//
//            if (visible)
//            {
//                if (hint) update_hint("%T", "Visible saferoom", zm_client);
//                return true;
//            }
//        }
//    }
//
//    //Ray traces are (probably) expensive so let's do easy calculations first.
//    bool skip = true;
//    bool skipList[MAXPLAYERS+1] = {true,...};
//    int i = INVALID_ENT_REFERENCE;
//    if (l4dhooks_updated)
//    {
//        while( (i = L4D_FindEntityByClassnameWithin(i,"player",vecPos,fog_distance)) != INVALID_ENT_REFERENCE )
//        {
//            if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
//            {
//                skip = false;
//                skipList[i] = false;
//            }
//        }
//    }
//    else
//    {
//        float pos[3];
//        for(i = 1; i <= MaxClients; i++)
//        {
//              if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
//              {
//                GetClientAbsOrigin(i,pos);
//                if (GetVectorDistance(pos,vecPos)<fog_distance)
//                {
//                    skip=false;
//                    skipList[i] = false;
//                }
//              }
//        }
//    }
//
//   if (skip) return false;
//
//   // Check VecPos2 first - that's most likely to hit.
//   for(i = 1; i <= MaxClients; i++)
//   {
//        if (skipList[i]) continue;
//        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos2)) {visible=true; break;}
//   }
//   if (!visible)
//   {
//        for(i = 1; i <= MaxClients; i++ )
//        {
//             if (skipList[i]) continue;
//             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,vecPos)) {visible=true; break;}
//             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos3)) {visible=true; break;}
//             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos4)) {visible=true; break;}
//             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos5)) {visible=true; break;}
//             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos6)) {visible=true; break;}
//        }
//   }
//
//   if (visible)
//   {
//       if (hint) update_hint("%T", "Visible survivors", zm_client);
//       return true;
//   }
//   return false;
//}

/**
 * Cheaper version of can_any_alive_survivor_see.
 * Uses 3 test points instead of 6, single survivor loop, and skips saferoom door checks.
 * Suitable for batch-checking many candidate positions (e.g. grid cell filtering).
 */
bool can_any_alive_survivor_see_cheap(float vecPos[3])
{
   if (DEBUG) LogMessage("[zm] can_any_alive_survivor_see_cheap");

   // 3 test points: ground, mid-height center (most likely), top center
   static float testPoints[3][3];
   bool visible = false;
   AddVectors(vecPos, {0.0, 0.0, HULL_DZ}, testPoints[1]);
   AddVectors(vecPos, {0.0, 0.0, HULL_DDZ}, testPoints[2]);

   if (l4dhooks_updated && !any_alive_survivors_in_radius(vecPos,fog_distance)) return false; // this call is very fast, good for early exit.
   
   // Check first saferoom door.
   if (zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor))
   {
       static float saferoom_pos[3];
       L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,saferoom_pos);
       if (GetVectorDistance(saferoom_pos,vecPos)<=fog_distance)
       {
            int door = EntRefToEntIndex(g_iLockedDoor);
            Handle trace = TR_TraceRayFilterEx(testPoints[1],saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,door);
            visible = !TR_DidHit(trace);
            delete trace;
            if (visible) return true;
            trace = TR_TraceRayFilterEx(testPoints[2],saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,door);
            visible = !TR_DidHit(trace);
            delete trace;
            if (visible) return true;
        }
   }
   
   Spawner_CacheSurvivorData();
   if (Is_PVS_Valid())
   {
       for (int s = 0; s < g_iBatchSurvivorCount; s++)
       {
           if (GetVectorDistance(g_fBatchSurvivorPos[s],vecPos) >= fog_distance) continue;

           //LogMessage("%d %s", s, g_BatchSurvivorPVS[s]);
           // PVS pre-filter: if position is not in this survivor's PVS, skip raytraces
           if (!g_BatchSurvivorValidPVS[s] || !PVS_CheckOriginInPVS(vecPos, g_BatchSurvivorPVS[s]))
           {
               if (DEBUG_SPAWNER) LogMessage("PVS pre-filter %d skipping raytraces", s);
               continue;
           }
               
           // l4dhooks does not validate client indices
           if (!IsValidClient(g_iBatchSurvivorClients[s])) continue;
           if (L4D2_IsVisibleToPlayer(g_iBatchSurvivorClients[s],TEAM_SURVIVOR,3,0,testPoints[1])) return true;
           if (L4D2_IsVisibleToPlayer(g_iBatchSurvivorClients[s],TEAM_SURVIVOR,3,0,testPoints[2])) return true;
       }
       return false;
   }
   //else LogMessage("PERF WARNING: can_any_alive_survivor_see_cheap not using PVS");
   
   //testPoints[0] = vecPos;

   float pos[3];
   bool skipList[MAXPLAYERS+1] = {true, ...};
   bool skip = true;
   for (int i = 1; i <= MaxClients; i++)
   {
       if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
       {
           GetClientAbsOrigin(i, pos);
           if (GetVectorDistance(pos, vecPos) < fog_distance)
           {
               skip = false;
               skipList[i] = false;
           }
       }
   }

   if (skip) return false;

   // Single loop: check mid-height first (most likely hit), then others
   for (int i = 1; i <= MaxClients; i++)
   {
       if (skipList[i]) continue;
       if (L4D2_IsVisibleToPlayer(i, TEAM_SURVIVOR, 3, 0, testPoints[1])) return true;
       //if (L4D2_IsVisibleToPlayer(i, TEAM_SURVIVOR, 3, 0, testPoints[0])) return true;
       if (L4D2_IsVisibleToPlayer(i, TEAM_SURVIVOR, 3, 0, testPoints[2])) return true;
   }

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
    if (safe_distance<0.0) safe_distance = (g_fSpawnMinDistance<150.0) ? 150.0 : g_fSpawnMinDistance; // 150.0 for "survivor being targeted" detection
    
    bool include_saferoom = zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor);
    static float pos_saferoom[3];
    float vector_distance_saferoom = -1.0;
    float min_distance = -1.0; // nav travel distance
    float min_vector_distance = -1.0; // vector distance
    
    float nearest_flowDiff = -1.0;
    int nearest_flow_survivor = -1;
    //static float nearest_flow_pos[3];
    float nearest_flow_vecDist;
    
    bool hit = false; // is there anything closer than "too close"?
    if (include_saferoom) // Check first saferoom
    {
         GetEntPropVector(g_iLockedDoor,Prop_Send,"m_vecOrigin",pos_saferoom);
         vector_distance_saferoom = GetVectorDistance(pos,pos_saferoom);
         if (vector_distance_saferoom<safe_distance) hit = true;
         else include_saferoom = false;
    }
    if (!hit) hit = !l4dhooks_updated || any_alive_survivors_in_radius(pos,safe_distance);
    if (!hit) return safe_distance+1.0; // no entities, no problem
   
    Spawner_CacheSurvivorData();
    float flow_pos = L4D_GetFlowFromPoint(pos);
    //static float navSize1[3], navSize2[3];
    if (navArea == Address_Null) navArea = L4D_GetNearestNavArea(pos, 300.0, false, false, true, TEAM_INFECTED);
    //if (navArea != Address_Null) L4D_GetNavAreaSize(navArea,navSize1);
    
    float flowDiff, vecDist, navDist;
    Address survNav;
    for (int s = 0; s < g_iBatchSurvivorCount; s++) // Check alive survivors
    {
        vecDist = GetVectorDistance(pos, g_fBatchSurvivorPos[s]); // Vector distance
        if (vecDist >= safe_distance)
            continue;
        
        if (flow_pos>0.0 && g_CachedSurvFlow[s]>0.0)
        {
            // Flow is useful - find smallest flow diff survivor, check nav travel distance only for the closest one.
            flowDiff = FloatAbs(flow_pos - g_CachedSurvFlow[s]);
            if (flowDiff<vecDist) flowDiff = vecDist; // vector distance better captures travel distance
            //LogMessage("flow_pos %f flowDiff %d %f", flow_pos, g_iBatchSurvivorClients[s], flowDiff);
            if (nearest_flowDiff<0.0 || flowDiff<nearest_flowDiff)
            {
                nearest_flow_survivor = g_iBatchSurvivorClients[s];
                if ( (flowDiff<150.0 || !store_client) && flowDiff<g_fSpawnMinDistance ) // exit early or trigger flow
                {
                    if (store_client && nearest_flow_survivor>0) spawner_nearest_survivor = nearest_flow_survivor;
                    return flowDiff;
                }
                //nearest_flow_pos = g_fBatchSurvivorPos[s];
                nearest_flow_vecDist = vecDist;
                nearest_flowDiff = flowDiff;
            }
        }
        else if (navArea != Address_Null)
        {
            // Flow is useless - calculate nav travel distance now, we have no choice.
            if (min_distance>=0.0 && vecDist>min_distance) continue; // smaller distance already found
            survNav = GetCachedSurvivorNavArea(s);
            if (survNav == Address_Null) continue;
            //L4D_GetNavAreaSize(survNav,navSize2);
            //extended_distance = safe_distance + navSize1[0] + navSize1[1] + navSize2[0] + navSize2[1];
            if (!L4D2_NavAreaBuildPath(navArea,survNav,safe_distance,TEAM_INFECTED,false)) continue; // no connection
            //navDist = L4D2_NavAreaTravelDistance(pos,g_fBatchSurvivorPos[s],false); // from pos to survivor
            navDist = vecDist;
            if ( navDist>=0.0 && (min_distance<0.0 || navDist<min_distance) )
            {
                min_distance = navDist;
                if (store_client) spawner_nearest_survivor = g_iBatchSurvivorClients[s];
                if ( (min_distance<150.0 || !store_client) && min_distance<g_fSpawnMinDistance) return min_distance; // trigger flow or exit early
                min_vector_distance = vecDist;
            }
            //if (zm_stage==ZM_STARTED)
            //{
            //    navDist = L4D2_NavAreaTravelDistance(g_fBatchSurvivorPos[s],pos,false); // from survivor to pos
            //    if ( navDist>=0.0 && (min_distance<0.0 || navDist<min_distance) )
            //    {
            //        min_distance = navDist;
            //        if (store_client) spawner_nearest_survivor = g_iBatchSurvivorClients[s];
            //        if (min_distance<=150.0 && min_distance<g_fSpawnMinDistance) return min_distance; // trigger flow
            //        min_vector_distance = vecDist;
            //    }
            //}
        }
        else continue;
    }
    
    // Check first saferoom
    if (include_saferoom)
    {
        bool check_nav = false; // if flow values are good, we can delay nav travel distance calculation
        if (flow_pos>0.0)
        {
            float flow_saferoom = L4D_GetFlowFromPoint(pos_saferoom);
            if (flow_saferoom>0.0)
            {
                flowDiff = FloatAbs(flow_pos-flow_saferoom);
                if (flowDiff<vector_distance_saferoom) flowDiff = vector_distance_saferoom;
                if (nearest_flowDiff<0.0 || flowDiff<nearest_flowDiff)
                {
                    //nearest_flow_pos = pos_saferoom;
                    nearest_flow_vecDist = vector_distance_saferoom;
                    nearest_flowDiff = flowDiff;
                }
            }
            else check_nav = true;
        }
        else check_nav = true;
        
        if (check_nav) // Flow is useless - calculate nav travel distance now.
        {
            vecDist = vector_distance_saferoom;
            if (min_distance<0.0 || vecDist<min_distance)
            {
                Address navArea_saferoom = L4D_GetNearestNavArea(pos_saferoom, 300.0, false, false, true, TEAM_INFECTED);
                if (navArea_saferoom != Address_Null && L4D2_NavAreaBuildPath(navArea,navArea_saferoom,safe_distance,TEAM_INFECTED,false))
                {
                    //navDist = L4D2_NavAreaTravelDistance(pos,pos_saferoom,false); // from pos to nearest position
                    navDist = vecDist;
                    if ( navDist>=0.0 && (min_distance<0.0 || navDist<min_distance) )
                    {
                        min_distance = navDist;
                        if (store_client && nearest_flow_survivor>0) spawner_nearest_survivor = nearest_flow_survivor;
                        if ( (min_distance<150.0 || !store_client) && min_distance<g_fSpawnMinDistance) return min_distance; // trigger flow or exit early
                        min_vector_distance = vecDist;
                    }
                }
            }
        }
    }
    
    // Check if nearest flow position is closer than closest position by nav distance.
    if (nearest_flowDiff>=0.0 && nearest_flowDiff<safe_distance)
    {
        //navDist = L4D2_NavAreaTravelDistance(pos,nearest_flow_pos,false); // from pos to nearest position
        //Address nearest_flow_navArea = L4D_GetNearestNavArea(nearest_flow_pos, 300.0, false, false, true, TEAM_INFECTED);
        //if (nearest_flow_navArea != Address_Null && L4D2_NavAreaBuildPath(navArea,nearest_flow_navArea,safe_distance,TEAM_INFECTED,false))
        //{
            navDist = nearest_flowDiff;
            if ( navDist>=0.0 && (min_distance<0.0 || navDist<min_distance) )
            {
                min_distance = navDist;
                if (store_client && nearest_flow_survivor>0) spawner_nearest_survivor = nearest_flow_survivor;
                if (min_distance<150.0 && min_distance<g_fSpawnMinDistance) return min_distance; // trigger flow
                min_vector_distance = nearest_flow_vecDist;
            }
            //if (zm_stage==ZM_STARTED)
            //{
            //    navDist = L4D2_NavAreaTravelDistance(nearest_flow_pos,pos,false); // from nearest position to pos
            //    if ( navDist>=0.0 && (min_distance<0.0 || navDist<min_distance) )
            //    {
            //        min_distance = navDist;
            //        if (store_client && nearest_flow_survivor>0) spawner_nearest_survivor = nearest_flow_survivor;
            //        if (min_distance<=150.0 && min_distance<g_fSpawnMinDistance) return min_distance; // trigger flow
            //        min_vector_distance = nearest_flow_vecDist;
            //    }
            //}
        //}
    }
    
    if (min_distance>=0.0 && min_vector_distance>min_distance) min_distance = min_vector_distance;
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
