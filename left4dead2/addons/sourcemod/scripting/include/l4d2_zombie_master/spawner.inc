///////////////////////////////////////
#if defined _zm_spawner_included
 #endinput
#endif
#define _zm_spawner_included
///////////////////////////////////////

bool DEBUG_SPAWNER = false;

// Batch PVS state for accelerated visibility checks in GridLib filter callbacks.
// Call Spawner_BeginBatchPVS() before a batch and Spawner_EndBatchPVS() after.
static bool   g_bBatchPVSActive = false;
static int    g_iBatchSurvivorCount = 0;
static char   g_BatchSurvivorPVS[MAXPLAYERS+1][PVS_BUFFER_SIZE];
static int    g_iBatchSurvivorClients[MAXPLAYERS+1];
static float  g_fBatchSurvivorPos[MAXPLAYERS+1][3];

// Filter context for SpawnerCellFilter callback
static float  g_SpawnerFilterOrigin[3];
static float  g_SpawnerFilterRadius;

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
        
        float t_now = GetEngineTime();
        
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
        if (target>0 && g_iGlowList[target]==INVALID_ENT_REFERENCE) // Draw survivor with CONDITIONAL color
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
        static float pos[3];
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
   
   float VecPos2[3]; AddVectors(vecPos,{0.0,0.0,HULL_DZ},VecPos2);
   float VecPos3[3]; AddVectors(vecPos,{-HULL_DX,-HULL_DX,HULL_DZ},VecPos3);
   float VecPos4[3]; AddVectors(vecPos,{HULL_DX,HULL_DX,HULL_DZ},VecPos4);
   float VecPos5[3]; AddVectors(vecPos,{HULL_DX,-HULL_DX,HULL_DDZ},VecPos5);
   float VecPos6[3]; AddVectors(vecPos,{0.0,0.0,HULL_DDZ},VecPos6);
   
   // Check line of sight with saferoom door
   if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
   {
        int filter_client = -1;
        if (IsValidClientZM()) filter_client = zm_client;
        int door = EntRefToEntIndex(g_iLockedDoor);
        float saferoom_pos[3];
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
        static float pos[3];
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
   if (l4dhooks_updated) hit = any_alive_survivors_in_radius(pos,min_distance); // replace with L4D_FindEntityByClassnameNearest. exit early
   if (!hit)
   {
        if (!L4D_IsSurvivalMode() && IsValidEntity(lastdoor)) // Check last saferoom
        {
            L4D_GetEntityWorldSpaceCenter(lastdoor,pos2);
            d_raw_temp = GetVectorDistance(pos,pos2);
            if ( d_raw_temp<=75.0 && (d_raw<0.0 || d_raw_temp<d_raw) )
            {
                if (store_client) spawner_nearest_survivor = -1;
                return d_raw_temp;
            }
            d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false);
            if (d_nav_temp>=0.0 && d_nav_temp<=75.0 && (d_nav<0.0 || d_nav_temp<d_nav))
            {
                if (store_client) spawner_nearest_survivor = -1;
                return d_nav_temp;
            }
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

// Test if pos xy values are out of bounds for given navmesh center and size
stock bool nav_xy_OOB(float pos[3], float center[3], float size[3])
{
    if (FloatAbs(pos[0]-center[0])>FloatAbs(size[0]/2.0)) return true;
    if (FloatAbs(pos[1]-center[1])>FloatAbs(size[1]/2.0)) return true;
    return false;
}

/**
 * Main spawn validation orchestrator - from ZM client.
 * @param witch  If true, use relaxed nav validation rules for witch placement
 * @param hint   If true, show HUD hints explaining why spawning is blocked
 * @return       SPAWNER_OK, -> GREEN
 *               SPAWNER_INVALID, SPAWNER_NAV -> RED
 *               SPAWNER_DISTANCE, SPAWNER_SIGHT, or SPAWNER_OTHER -> BLUE
 */
int can_ZM_spawn(bool witch = false, bool hint = true)
{
    if (DEBUG) LogMessage("[zm] can_ZM_spawn");
	if (!IsValidClientZM()) return SPAWNER_INVALID;
	if (zm_stage>=ZM_END) return SPAWNER_INVALID;	
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
    int spawner_state = can_ZM_spawn_pos(vPos,witch,hint);
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
 * @param witch  If true, use relaxed nav validation rules for witch placement
 * @param witch  If true, use relaxed nav validation rules for witch placement
 * @param hint   If true, show HUD hints explaining why spawning is blocked
 * @param draw   Run update_ZM_spawner() which will update zm_spawner globals + draw GREEN/BLUE/RED for ZM to see. Set draw=false for internal calculations, i.e. to check spawn rules.
 * @param skip_gridlib If true, skip gridlib fallback and immediately throw out a failed spawner state.
 * @return       SPAWNER_OK, -> GREEN
 *               SPAWNER_INVALID, SPAWNER_NAV -> RED
 *               SPAWNER_DISTANCE, SPAWNER_SIGHT, or SPAWNER_OTHER -> BLUE
 */
int can_ZM_spawn_pos(float vPos[3],bool witch = false,bool hint = true,bool draw = true,bool skip_gridlib=false)
{
	if (DEBUG) LogMessage("[zm] can_ZM_spawn");
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
    
    // vPos: input, adjusted on the fly
	// vPos_spawner: final spawner position (output). later we decide where to draw the spawner depending on its state.
	float vPos_spawner[3];
	vPos_spawner = vPos;
    float check_dist = (witch) ? 50.0 : 500.0;
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
        //float z_min = navCenter[2] - FloatAbs(navSize[2])/2.0;
        float z_min = navCenter[2] - FloatAbs(navSize[2]); // fix only egregious out of bounds
        
        bool OOB = nav_xy_OOB(vPos_spawner,navCenter,navSize);
        bool obstruction_checked = false;
        bool tried_center = false;
        if (OOB) // If navmesh is outside expected xy: try center,center-up,random,random-up
        {
            fail = !try_adjusting_obstructed_pos(vPos_spawner,navArea,navCenter,
                                         false,        true,true,         true,true);
            tried_center = true;
            obstruction_checked = true;
        }
        if (!fail && !obstruction_checked && IsObstructed(vPos_spawner)) // Navmesh xy is good, but we are obstructed. Try moving up.
        {
            fail = !try_adjusting_obstructed_pos(vPos_spawner,navArea,navCenter,
                                         true,!tried_center,!tried_center,!tried_center,!tried_center);
            
        }
        if (!fail && vPos_spawner[2]<z_min)
        {
            static float new_vPos[3];
            new_vPos = vPos_spawner;
            new_vPos[2] = navCenter[2] + FloatAbs(navSize[2])/2.0 + 1.0;
            if (!IsObstructed(new_vPos)) vPos_spawner = new_vPos;
            else fail = true;
        }
        if (fail) spawner_state = SPAWNER_OTHER;
         
    }
    else
    {
        vPos_spawner = vPos;
        if (!witch)
        {
            spawner_state = SPAWNER_INVALID;
            fail = true;
        }
    }
    
    if ( !fail || (draw && spawner_state>SPAWNER_NAV) ) // check navmesh properties for no-no. run this if spawner is CONDITIONAL to make it RED
    {
        if (navArea && !nav_can_spawn_zombies(witch, navArea,
                                   navAttrFlags,navSpawnAttrs,
                                   navCenter,navSize))
        {
            spawner_state = SPAWNER_NAV;
            fail = true;
        }
    }
    if (!fail || draw) // nav area travel distance is expensive, skip if not needed
    {
        min_distance = min_distance_to_survivors(vPos_spawner,draw);
        if (min_distance>=0.0 && draw) latest_distance = min_distance;
        if (zm_stage<ZM_STARTED && spawner_nearest_survivor>0) min_distance *= 2.0;
        if (min_distance>=0.0 && g_fSpawnMinDistance>0.0 && min_distance<g_fSpawnMinDistance)
        {
            spawner_state = SPAWNER_DISTANCE;
            fail = true;
        }
    }
    if (!fail) // check if obstructed
    {
        fail = IsObstructed(vPos_spawner);
        if (fail) spawner_state = SPAWNER_OTHER;
    }
    if (!fail) // check if survivors can see
    {
        bool obscured = ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
        if (!obscured)
        {
            fail = can_any_alive_survivor_see(vPos_spawner,false);
            if (fail) spawner_state = SPAWNER_SIGHT;
        }
    }
    if (fail && draw && spawner_state>SPAWNER_NAV && spawner_last_valid && get_spawner_target_survivor(false,SPAWNER_DISTANCE)<0) // see if there's a good nearby position in memory
    {
        if (can_ZM_see(spawner_last_valid_pos) && can_ZM_spawn_pos(spawner_last_valid_pos,witch,false,false,true)==SPAWNER_OK)
        {
            vPos_spawner = spawner_last_valid_pos;
            fail = false;
            spawner_state = SPAWNER_OK;
            if (draw) zm_spawner_navArea = L4D_GetNearestNavArea(vPos_spawner,check_dist,true,true,true,TEAM_INFECTED);
            if (DEBUG_SPAWNER) LogMessage("Valid old position");
        }
    
        if (fail && !skip_gridlib) // ask gridlib for a better position
        {
            static float vPos_gridlib[3];
            if (FindNearbyValidSpawnCell(vPos_spawner,vPos_gridlib,check_dist))
            {
                vPos_spawner = vPos_gridlib;
                fail = false;
                spawner_state = SPAWNER_OK;
                if (draw) zm_spawner_navArea = L4D_GetNearestNavArea(vPos_spawner,check_dist,true,true,true,TEAM_INFECTED);
            }
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
                    if (witch) update_hint("%T", "Witches illegal", zm_client);
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
    //vPos = vPos_spawner; // in case dynamic adjustment was made
    return SPAWNER_OK;
}

bool can_ZM_see(float vPos[3])
{
    if (!IsValidClientZM()) return false;
    bool can_see = true;
    static float vEye[3], vPos2[3];
    vPos2 = vPos; vPos2[2] += 32.0;
    GetClientEyePosition(zm_client,vEye);
    Handle trace = TR_TraceRayFilterEx(vEye,vPos2,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,zm_client);
    if(TR_DidHit(trace)) can_see = false;
    delete trace;
    //LogMessage("can_ZM_see %d", can_see);
    return can_see;
}

/**
 * GridLib filter callback for spawn cell validation.
 * Returns GRIDLIB_FILTER_KEEP, GRIDLIB_FILTER_DISCARD, or GRIDLIB_FILTER_DISCARD_NAV.
 * Nav-blocked areas use DISCARD_NAV to skip all cells on that nav area.
 * Context (origin, radius) flows through g_SpawnerFilterOrigin / g_SpawnerFilterRadius.
 */
int SpawnerCellFilter(int cellIdx)
{
    // Nav-blocked attributes apply to the entire nav area
    if (GridLib_GetCellSpawnAttributes(cellIdx) & GRIDLIB_NAV_BLOCKED_ZOMBIES)
        return GRIDLIB_FILTER_DISCARD_NAV;

    float cellPos[3], normal[3];
    Address navArea;
    bool obstructed;
    if (!GridLib_GetCellData(cellIdx, cellPos, normal, navArea, obstructed))
        return GRIDLIB_FILTER_DISCARD;

    if (obstructed)
        return GRIDLIB_FILTER_DISCARD;
    
    if (!nav_can_spawn_zombies(false,navArea))
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d failed nav attrs", cellIdx);
        return GRIDLIB_FILTER_DISCARD_NAV;
    }
    
    if (IsObstructed(cellPos)) // my obstruction check is more restrictive
        return GRIDLIB_FILTER_DISCARD;
    
    if (IsValidClientZM() && !can_ZM_see(cellPos)) // Check if ZM can actually see that location.
        return GRIDLIB_FILTER_DISCARD;
    
    if (can_any_alive_survivor_see_cheap(cellPos))
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d visible to survivors", cellIdx);
        return GRIDLIB_FILTER_DISCARD;
    }

    float travel = L4D2_NavAreaTravelDistance(cellPos, g_SpawnerFilterOrigin, false);
    if (travel < 0.0 || travel > g_SpawnerFilterRadius)
    {
        if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d travel fail %.0f", cellIdx, travel);
        return GRIDLIB_FILTER_DISCARD;
    }

    if (g_fSpawnMinDistance > 0.0)
    {
        float minDist = min_distance_to_survivors(cellPos, _, g_fSpawnMinDistance);
        if (minDist >= 0.0 && minDist < g_fSpawnMinDistance)
        {
            if (DEBUG_SPAWNER) LogMessage("[zm] SpawnerCellFilter: cell %d too close (%.0f)", cellIdx, minDist);
            return GRIDLIB_FILTER_DISCARD;
        }
    }

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
bool FindNearbyValidSpawnCell(float origin[3], float outPos[3], float radius = -1.0)
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

    float t_start = GetEngineTime();

    // Set up filter context and batch PVS
    g_SpawnerFilterOrigin = origin;
    g_SpawnerFilterRadius = radius;
    Spawner_BeginBatchPVS();

    float t_gridlib = GetEngineTime();
    static int cells[16];
    int count = GridLib_FindNearbyCells(origin, radius, 200.0, cells, 16, SpawnerCellFilter);
    float gridlib_ms = (GetEngineTime() - t_gridlib) * 1000.0;

    Spawner_EndBatchPVS();

    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: %d pre-validated candidates (gridlib=%.2f ms)", count, gridlib_ms);

    // All returned cells passed nav/obstruction/travel/distance/visibility checks.
    // Only the expensive can_ZM_spawn_pos check remains.
    //int expensive_fails = 0;
    for (int i = 0; i < count; i++)
    {
        float cellPos[3], normal[3];
        Address navArea;
        bool obstructed;
        GridLib_GetCellData(cells[i], cellPos, normal, navArea, obstructed);
        //if (can_ZM_spawn_pos(cellPos, witch, false, false, true) != SPAWNER_OK)
        //{
        //    if (DEBUG_SPAWNER) LogMessage("[zm] FindNearbyValidSpawnCell: cell %d can_ZM_spawn_pos fail", i);
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
        //    static float cellPos2[3];
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
    if (!zm_allow_spawns) return -1;
    int target_client = -1;
    if (flow) target_client = L4D_GetHighestFlowSurvivor();
    else
    {
        int lastlook = -1;
        if (IsValidClientZM())
        {
            int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode");
            if (observermode==4 || observermode==5)
            {
                lastlook = GetEntPropEnt(zm_client, Prop_Send, "m_hObserverTarget");
                if (IsValidClient(lastlook) && IsPlayerAlive(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR)
                    target_client = lastlook;
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
            static float test_pos[3];
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