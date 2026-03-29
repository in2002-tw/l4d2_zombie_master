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

// Batch PVS state for accelerated visibility checks in GridLib filter callbacks.
// Call Spawner_BeginBatchPVS() before a batch and Spawner_EndBatchPVS() after.
static bool   g_bBatchPVSActive = false;
static int    g_iBatchSurvivorCount = 0;
static char   g_BatchSurvivorPVS[MAXPLAYERS+1][PVS_BUFFER_SIZE];
static int    g_iBatchSurvivorClients[MAXPLAYERS+1];
static float  g_fBatchSurvivorPos[MAXPLAYERS+1][3];

/**
 * Pre-compute PVS data for all alive survivors. Call before a batch of
 * can_any_alive_survivor_see_cheap() calls (e.g. inside a GridLib filter).
 * PVS buffers are built once here and reused for every cell check.
 */
void Spawner_BeginBatchPVS()
{
	g_bBatchPVSActive = false;
	g_iBatchSurvivorCount = 0;

	if (hCheckOriginInPVS == null) return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR || !IsPlayerAlive(i))
			continue;

		GetClientAbsOrigin(i, g_fBatchSurvivorPos[g_iBatchSurvivorCount]);

		float eyePos[3];
		GetClientEyePosition(i, eyePos);
		int cluster = PVS_GetClusterForOrigin(eyePos);
		if (cluster < 0) continue;

		PVS_GetForCluster(cluster, g_BatchSurvivorPVS[g_iBatchSurvivorCount]);
		g_iBatchSurvivorClients[g_iBatchSurvivorCount] = i;
		g_iBatchSurvivorCount++;
	}

	g_bBatchPVSActive = (g_iBatchSurvivorCount > 0);
	if (DEBUG_SPAWNER) LogMessage("[zm] BeginBatchPVS: %d survivors, active=%d", g_iBatchSurvivorCount, g_bBatchPVSActive);
}

void Spawner_EndBatchPVS()
{
	g_bBatchPVSActive = false;
	g_iBatchSurvivorCount = 0;
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
bool can_any_alive_survivor_see(float vecPos[3], bool hint = true)
{
   if (DEBUG) LogMessage("[zm] can_any_alive_survivor_see");
   bool visible = false;
   
   if (l4dhooks_updated && !any_alive_survivors_in_radius(vecPos,fog_distance)) return false;
   
   static float VecPos2[3]; AddVectors(vecPos,{0.0,0.0,HULL_DZ},VecPos2);
   static float VecPos3[3]; AddVectors(vecPos,{-HULL_DX,-HULL_DX,HULL_DZ},VecPos3);
   static float VecPos4[3]; AddVectors(vecPos,{HULL_DX,HULL_DX,HULL_DZ},VecPos4);
   static float VecPos5[3]; AddVectors(vecPos,{HULL_DX,-HULL_DX,HULL_DDZ},VecPos5);
   static float VecPos6[3]; AddVectors(vecPos,{0.0,0.0,HULL_DDZ},VecPos6);

   // Check line of sight with saferoom door
   if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
   {
        int filter_client = -1;
        if (IsValidClientZM()) filter_client = zm_client;
        int door = EntRefToEntIndex(g_iLockedDoor);
        static float saferoom_pos[3];
        L4D_GetEntityWorldSpaceCenter(door,saferoom_pos);
        saferoom_pos[2] -= 10.0;
        if (GetVectorDistance(saferoom_pos,vecPos)<=fog_distance)
        {
            Handle trace = TR_TraceRayFilterEx(vecPos,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
            delete trace;
            if (!visible)
            {
                trace = TR_TraceRayFilterEx(VecPos2,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
                delete trace;
            }
            if (!visible)
            {
                trace = TR_TraceRayFilterEx(VecPos3,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
                delete trace;
            }
            if (!visible)
            {
                trace = TR_TraceRayFilterEx(VecPos4,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
                delete trace;
            }
            if (!visible)
            {
                trace = TR_TraceRayFilterEx(VecPos5,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
                delete trace;
            }
            if (!visible)
            {
                trace = TR_TraceRayFilterEx(VecPos6,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
                if(TR_DidHit(trace) && TR_GetEntityIndex(trace)==door) visible = true;
                delete trace;
            }

            if (visible)
            {
                if (hint) update_hint("%T", "Visible saferoom", zm_client);
                return true;
            }
        }
    }

    //Ray traces are (probably) expensive so let's do easy calculations first.
    bool skip = true;
    bool skipList[MAXPLAYERS+1] = {true,...};
    int i = INVALID_ENT_REFERENCE;
    if (l4dhooks_updated)
    {
        while( (i = L4D_FindEntityByClassnameWithin(i,"player",vecPos,fog_distance)) != INVALID_ENT_REFERENCE )
        {
            if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
            {
                skip = false;
                skipList[i] = false;
            }
        }
    }
    else
    {
        float pos[3];
        for(i = 1; i <= MaxClients; i++)
        {
              if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
              {
                GetClientAbsOrigin(i,pos);
                if (GetVectorDistance(pos,vecPos)<fog_distance)
                {
                    skip=false;
                    skipList[i] = false;
                }
              }
        }
    }

   if (skip) return false;

   // Check VecPos2 first - that's most likely to hit.
   for(i = 1; i <= MaxClients; i++)
   {
        if (skipList[i]) continue;
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos2)) {visible=true; break;}
   }
   if (!visible)
   {
        for(i = 1; i <= MaxClients; i++ )
        {
             if (skipList[i]) continue;
             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,vecPos)) {visible=true; break;}
             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos3)) {visible=true; break;}
             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos4)) {visible=true; break;}
             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos5)) {visible=true; break;}
             if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos6)) {visible=true; break;}
        }
   }

   if (visible)
   {
       if (hint) update_hint("%T", "Visible survivors", zm_client);
       return true;
   }
   return false;
}

/**
 * Cheaper version of can_any_alive_survivor_see.
 * Uses 3 test points instead of 6, single survivor loop, and skips saferoom door checks.
 * Suitable for batch-checking many candidate positions (e.g. grid cell filtering).
 */
bool can_any_alive_survivor_see_cheap(float vecPos[3])
{
   if (DEBUG) LogMessage("[zm] can_any_alive_survivor_see_cheap");

   // 3 test points: ground, mid-height center (most likely), top center
   float testPoints[3][3];
   testPoints[0] = vecPos;
   AddVectors(vecPos, {0.0, 0.0, HULL_DZ}, testPoints[1]);
   AddVectors(vecPos, {0.0, 0.0, HULL_DDZ}, testPoints[2]);

   if (g_bBatchPVSActive)
   {
       for (int s = 0; s < g_iBatchSurvivorCount; s++)
       {
           if (GetVectorDistance(g_fBatchSurvivorPos[s], vecPos) >= fog_distance)
               continue;

           // PVS pre-filter: if position is not in this survivor's PVS, skip raytraces
           if (!PVS_CheckOriginInPVS(vecPos, g_BatchSurvivorPVS[s]))
               continue;

           int client = g_iBatchSurvivorClients[s];
           if (L4D2_IsVisibleToPlayer(client, TEAM_SURVIVOR, 3, 0, testPoints[1])) return true;
           if (L4D2_IsVisibleToPlayer(client, TEAM_SURVIVOR, 3, 0, testPoints[0])) return true;
           if (L4D2_IsVisibleToPlayer(client, TEAM_SURVIVOR, 3, 0, testPoints[2])) return true;
       }
       return false;
   }

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
       if (L4D2_IsVisibleToPlayer(i, TEAM_SURVIVOR, 3, 0, testPoints[0])) return true;
       if (L4D2_IsVisibleToPlayer(i, TEAM_SURVIVOR, 3, 0, testPoints[2])) return true;
   }

   return false;
}

/**
 * Find the minimum distance from a position to any alive survivor.
 * Computes both raw vector distance and NavMesh travel distance in both directions,
 * then returns the larger of the two (conservative estimate). Also checks distance
 * to saferoom doors. Returns -1.0 if no valid path or survivor exists.
 *
 * @param pos           The world position to measure from
 * @param store_client  If true, store the nearest survivor client index in spawner_nearest_survivor. For flow spawns.
 * @param min_distance  Safe distance to spawn. Feeds to fast any_alive_survivors_in_radius() call which can exit early returning min_distance.
 * @return              Minimum distance to survivors, or -1.0 if no valid measurement
 */
float min_distance_to_survivors(float pos[3], bool store_client=false, float min_distance = -1.0)
{
   if (DEBUG) LogMessage("[zm] min_distance_to_survivors");
   // d_min is the final value. nav distance and vector distance are calculated independently, and then we think.
   // -1.0 are invalid values, we will deal with them later
   float d_nav_temp, d_raw_temp;
   float d_min = -1.0;
   float d_nav = -1.0;
   float d_raw = -1.0;
   float pos2[3];
   if (store_client) spawner_nearest_survivor = -1;

   // Is there at least one survivor close enough? If not, end early.
   bool hit = true;
   if (min_distance<0.0) min_distance = (g_fSpawnMinDistance<150.0) ? 150.0 : g_fSpawnMinDistance; // 150.0 for "survivor being targeted" detection
   if (l4dhooks_updated) hit = any_alive_survivors_in_radius(pos,min_distance);
   if (!hit)
   {
        if (min_distance>DISTANCE_LAST_SAFEROOM)
        {
            float distance_last = distance_last_saferoom(pos);
            if (distance_last>0.0 && distance_last<min_distance) return DISTANCE_LAST_SAFEROOM-1.0;
        }
        return min_distance+1.0;
    }

    if (zm_stage<ZM_STARTED && !L4D_IsSurvivalMode() && IsValidEntRef(g_iLockedDoor)) // Check first saferoom
    {
         L4D_GetEntityWorldSpaceCenter(EntRefToEntIndex(g_iLockedDoor),pos2);
         d_raw_temp = GetVectorDistance(pos,pos2);
         if (d_raw<0.0 || d_raw_temp<d_raw) d_raw = d_raw_temp;
         d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false);
         if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav)) d_nav = d_nav_temp;
    }

   int i = INVALID_ENT_REFERENCE;
   for(i = 1; i <= MaxClients; i++)
   {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        L4D_GetEntityWorldSpaceCenter(i,pos2);
        d_raw_temp = GetVectorDistance(pos,pos2);
        if (d_raw<0.0 || d_raw_temp<d_raw)
        {
            d_raw = d_raw_temp;
            if (store_client) spawner_nearest_survivor = i;
        }

        d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false); // can return -1.0 for no path
        if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
        {
            d_nav = d_nav_temp;
            if (store_client) spawner_nearest_survivor = i;
            if (d_nav<150.0) return d_nav;
        }

        // If round has started, check if survivors might appear here soon.
        if (zm_stage==ZM_STARTED)
        {
            d_nav_temp = L4D2_NavAreaTravelDistance(pos2,pos,false);
            if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
            {
                d_nav = d_nav_temp;
                if (store_client) spawner_nearest_survivor = i;
            }
        }
        if (d_nav<150.0 && d_raw<150.0 && d_nav<min_distance && d_raw<min_distance) break; // targeting survivor
   }

    if (d_nav>=0.0) d_min = d_nav>d_raw ? d_nav : d_raw;
    return d_min;
}

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
