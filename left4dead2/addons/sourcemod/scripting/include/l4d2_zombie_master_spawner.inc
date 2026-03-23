///////////////////////////////////////
#if defined _zm_spawner_included
 #endinput
#endif
#define _zm_spawner_included
///////////////////////////////////////

int color_blocked[4] = {255,0,0,128};
int color_conditional[4] = {0,0,255,128};
int color_allowed[4] = {0,255,0,128};
int color_unit_select[4] = {255,255,255,128};

float zm_target_pos[3];
float zm_spawner_pos[3];
Address zm_spawner_navArea;
int zm_spawner_navAttrFlags, zm_spawner_navSpawnAttrs;
int zm_spawner_state;
float t_last_spawner_update;
float t_last_spawner_sound;

int spawner_nearest_survivor = -1;
float latest_distance = 0.0;

/**
 * Draw the colored spawn indicator ring at the ZM's aim position and update spawner state.
 * Draws three stacked rings (red=blocked, blue=conditional, green=allowed) and plays
 * a feedback sound when the state changes.
 *
 * @param target_pos   The position the ZM is aiming at
 * @param spawner_pos  The resolved spawn position (may differ from target_pos after nav snapping)
 * @param state        Spawner RGB state: SPAWNER_RGB_BLOCKED, SPAWNER_RGB_CONDITIONAL, or SPAWNER_RGB_ALLOWED
 * @param draw         If false, skip drawing and only update internal state
 */
void update_ZM_spawner(const float target_pos[3], const float spawner_pos[3], const int state, bool draw=true)
{
    if (draw && IsValidClientZM() && g_iLaser>0 && g_iHalo>0)
    {
        int color[4];
        if (state==SPAWNER_RGB_BLOCKED) color = color_blocked;
        else if (state==SPAWNER_RGB_CONDITIONAL) color = color_conditional;
        else color = color_allowed;
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
        
        if ( (zm_spawner_state!=state || zm_target_pos[0]!=target_pos[0] || zm_target_pos[1]!=target_pos[1] || zm_target_pos[2]!=target_pos[2]) && (t_now-t_last_spawner_sound)>=2.0)
        {
            char sound_name[64];
            if (state==SPAWNER_RGB_BLOCKED) sound_name = SOUND_BLOCKED;
            else if (state==SPAWNER_RGB_CONDITIONAL) sound_name = SOUND_CONDITIONAL;
            else sound_name = "";
            if (sound_name[0]!=0)
                EmitSoundToClient(zm_client,sound_name,zm_client,ATTN_TO_SNDLEVEL(SNDATTN_NORMAL),_,_,0.09,_,_,draw_pos,_,true);
            t_last_spawner_sound = t_now;
        }
        t_last_spawner_update = t_now;
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
        while( (i = L4D_FindEntityByClassnameWithin(i,"player",vecPos,fog_distance)) != INVALID_ENT_REFERENCE )
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

   // Distance pre-filter
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
 * @param store_client  If true, store the nearest survivor client index in spawner_nearest_survivor
 * @return              Minimum distance to survivors, or -1.0 if no valid measurement
 */
float min_distance_to_survivors(float pos[3], bool store_client=false)
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
   int i = INVALID_ENT_REFERENCE;
   bool hit = true;
   float min_distance = (g_fSpawnMinDistance<150.0) ? 150.0 : g_fSpawnMinDistance; // 150.0 for "survivor being targeted" detection
   if (l4dhooks_updated) hit = any_alive_survivors_in_radius(pos,min_distance);
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
   
   for(i = 1; i <= MaxClients; i++)
   {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        //GetClientAbsOrigin(i,pos2);
        L4D_GetEntityWorldSpaceCenter(i,pos2);
        d_raw_temp = GetVectorDistance(pos,pos2);
        if (d_raw<0.0 || d_raw_temp<d_raw)
        {
            d_raw = d_raw_temp;
            //LogMessage("[zm] d_raw %d %f", i, d_raw);
            if (store_client) spawner_nearest_survivor = i;
        }
        
        d_nav_temp = L4D2_NavAreaTravelDistance(pos,pos2,false); // can return -1.0 for no path
        if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
        {
            d_nav = d_nav_temp;
            //LogMessage("[zm] d_nav pos->pos2 %d %f", i, d_nav);
            if (store_client) spawner_nearest_survivor = i;
        }
        
        // If round has started, check if survivors might appear here soon.
        if (zm_stage==ZM_STARTED)
        {
            d_nav_temp = L4D2_NavAreaTravelDistance(pos2,pos,false);
            if (d_nav_temp>=0.0 && (d_nav<0.0 || d_nav_temp<d_nav))
            {
                d_nav = d_nav_temp;
                //LogMessage("[zm] d_nav pos2->pos %d %f", i, d_nav);
                if (store_client) spawner_nearest_survivor = i;
            }
        }
        if (d_nav<150.0 && d_raw<150.0 && d_nav<g_fSpawnMinDistance && d_raw<g_fSpawnMinDistance) break; // targeting survivor
   }
    
    if (d_nav>=0.0) d_min = d_nav>d_raw ? d_nav : d_raw;
    //LogMessage("[zm] d_min %f", d_min);
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

/**
 * Main spawn validation orchestrator. Traces from the ZM's eye position to determine
 * if a spawn is valid at the aimed location. Checks: world bounds, NavMesh area,
 * nav spawn attributes, minimum distance to survivors, obstruction, and line of sight.
 * Updates the visual spawner indicator as a side effect.
 * GridLib should run here to reposition the spawner if it's very close to a good spawn location.
 *
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
	
	float vAngles[3],vOrigin[3],vPos[3],vPos_spawner[3];
	GetClientAbsOrigin(zm_client,vPos);
	GetClientEyePosition(zm_client,vOrigin);
	GetClientEyeAngles(zm_client,vAngles);
	
    Handle trace = TR_TraceRayFilterEx(vOrigin,vAngles,MASK_SOLID,RayType_Infinite,FilterSpawner_HitSurvivors,zm_client);
	if(TR_DidHit(trace))
	{
    	TR_GetEndPosition(vPos,trace);
    	int entity = TR_GetEntityIndex(trace);
    	if (IsValidClient(entity) && GetClientTeam(entity)==TEAM_SURVIVOR && IsPlayerAlive(entity))
    	{
        	GetClientAbsOrigin(entity,vPos);
        	update_ZM_spawner(vPos,vPos,SPAWNER_RGB_CONDITIONAL);
        	latest_distance = 0.0;
        	spawner_nearest_survivor = entity;
        	delete trace;
        	return SPAWNER_DISTANCE;
    	}
	}
	vPos_spawner = vPos;
	delete trace;
    
    if (TR_PointOutsideWorld(vPos))
    {
        if (hint) update_hint("%T", "Bad location", zm_client);
        update_ZM_spawner(vPos,vPos_spawner,SPAWNER_RGB_BLOCKED,false);
        return SPAWNER_INVALID;
    }
    
    float check_dist = 500.0;
    if (witch) check_dist = 50.0;
    
    // cycle 0: is analog spawner position in a good place? -> if YES, spawn zombie, if NO, ask gridlib fallback
    // cycle 1: is gridlib fallback in a good place? -> if YES, spawn zombie
    // cycle 2: give up
    int num_cycle = 0;
    float min_distance;
    latest_distance = -1.0;
    while (num_cycle<2)
    {
        bool fail = false;
        int spawner_state = SPAWNER_OK;
        int spawner_state_RGB = SPAWNER_RGB_ALLOWED;
        
        //                                                  bools: anyz los checkground
        zm_spawner_navArea = L4D_GetNearestNavArea(vPos_spawner,check_dist,true,true,true,TEAM_INFECTED);
        if (zm_spawner_navArea)
        {
            zm_spawner_navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(zm_spawner_navArea);
            zm_spawner_navAttrFlags = L4D_GetNavArea_AttributeFlags(zm_spawner_navArea);
            float navSize[3], navCenter[3];
            L4D_GetNavAreaCenter(zm_spawner_navArea, navCenter);
            L4D_GetNavAreaSize(zm_spawner_navArea, navSize);
            
            if ( FloatAbs(vPos_spawner[0]-navCenter[0])>(navSize[0]/2.0) ||
                 FloatAbs(vPos_spawner[1]-navCenter[1])>(navSize[1]/2.0) || IsObstructed(vPos_spawner) )
            {
                if (IsObstructed(navCenter)) L4D_FindRandomSpot(zm_spawner_navArea,vPos_spawner);
                else vPos_spawner = navCenter;
            }
            else
            {
                float z_min = navCenter[2] - FloatAbs(navSize[2])/2.0;
                if (vPos_spawner[2]<z_min) vPos_spawner[2] = navCenter[2] + FloatAbs(navSize[2])/2.0 + 1.0;
            }
        }
        else
        {
            vPos_spawner = vPos;
            zm_spawner_navSpawnAttrs = 0;
            zm_spawner_navAttrFlags = 0;
            if (!witch)
            {
                spawner_state = SPAWNER_INVALID;
                fail = true;
            }
        }
        
        min_distance = min_distance_to_survivors(vPos_spawner,hint);
        if (min_distance>=0.0 && num_cycle==0) latest_distance = min_distance;
        if (zm_stage<ZM_STARTED && spawner_nearest_survivor!=-1) min_distance *= 2.0;
        if (min_distance>=0.0 && g_fSpawnMinDistance>0.0 && min_distance<g_fSpawnMinDistance)
        {
            spawner_state = SPAWNER_DISTANCE;
            fail = true;
        }
        if (spawner_nearest_survivor>0 && min_distance<150.0 && min_distance>=0.0) // targeting survivor
        {
           	GetClientAbsOrigin(spawner_nearest_survivor,vPos_spawner);
            return SPAWNER_DISTANCE;
        }
        
        if (!fail)
        {
            fail = !nav_can_spawn_zombies(zm_spawner_navAttrFlags,zm_spawner_navSpawnAttrs,witch);
            if (fail) spawner_state = SPAWNER_NAV;
        }
        if (!fail && !witch && l4dhooks_updated)
        {
            fail = L4D_NavArea_IsBlocked(zm_spawner_navArea,TEAM_INFECTED,false);
            if (fail) spawner_state = SPAWNER_NAV;
        }
        if (!fail)
        {
            fail = IsObstructed(vPos_spawner);
            if (fail) spawner_state = SPAWNER_OTHER;
        }
        if (!fail)
        {
            bool obscured = ( (zm_spawner_navSpawnAttrs & NAV_SPAWN_OBSCURED) || (zm_spawner_navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
            if (!obscured)
            {
                fail = can_any_alive_survivor_see(vPos_spawner,false);
                if (fail)
                {
                    //fail = !L4D_FindRandomSpot(zm_spawner_navArea,vPos_spawner) || can_any_alive_survivor_see(vPos_spawner,false);
                    spawner_state = SPAWNER_SIGHT;
                }
            }
        }
        if (fail)
        {
            float vPos_gridlib[3];
            if (num_cycle<=0 && FindNearbyValidSpawnCell(vPos_spawner,vPos_gridlib,check_dist) && L4D2_NavAreaTravelDistance(vPos_gridlib,vPos_spawner,false)<check_dist)
            {
                vPos_spawner = vPos_gridlib;
                num_cycle +=1;
                continue; // return to beginning of while loop, check if new position is valid.
            }
            if (!DEBUG) vPos_spawner = vPos; // reduce jumpiness which can look disorienting. good for debugging though.
            spawner_state_RGB = SPAWNER_RGB_BLOCKED;
            switch (spawner_state)
            {
                case SPAWNER_DISTANCE:
                {
                    if (hint) update_hint("%T %d", "Too close", zm_client, RoundFloat(min_distance));
                    spawner_state_RGB = SPAWNER_RGB_CONDITIONAL;
                }
                case SPAWNER_SIGHT:
                {
                    if (hint) update_hint("%T", "Visible survivors", zm_client);
                    spawner_state_RGB = SPAWNER_RGB_CONDITIONAL;
                    if (hint && num_cycle>0 && zm_allow_spawns && !zm_flow_notify && IsValidClientZM())
                        PrintHintText(zm_client, "%t", "Flow hint");
                }
                case SPAWNER_OTHER:
                {
                    if (hint) update_hint("%T", "Obstacle", zm_client);
                    spawner_state_RGB = SPAWNER_RGB_CONDITIONAL;
                }
                case SPAWNER_INVALID:
                {
                    if (hint) update_hint("%T", "Bad location", zm_client);
                    spawner_state = SPAWNER_INVALID;
                }
                default: // SPAWNER_NAV 
                {
                    if (hint)
                    {
                        if (witch) update_hint("%T", "Witches illegal", zm_client);
                        else update_hint("%T", "Zombies illegal", zm_client);
                    }
                }
            }
            update_ZM_spawner(vPos,vPos_spawner,spawner_state_RGB);
            return spawner_state;
        }
        num_cycle += 1;
        if (num_cycle>1) break; // give up
    }
    if (!zm_allow_spawns) // this could be moved much earlier for optimization, but it is useful to ZM for exploring the navmesh and understanding the map.
	{
    	if (hint) update_hint("%T", "Zombie spawns OFF", zm_client);
    	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_RGB_CONDITIONAL);
    	return SPAWNER_OTHER;
	}
    update_ZM_spawner(vPos,vPos_spawner,SPAWNER_RGB_ALLOWED);
    return SPAWNER_OK;
}

/**
 * When the spawn indicator is blue (SPAWNER_RGB_CONDITIONAL), search nearby GridLib
 * cells for a valid spawn position that isn't visible to or too close to survivors.
 *
 * @param origin    The aimed spawn position to search around
 * @param outPos    Output: the valid nearby cell position, if found
 * @param radius    Search radius, defaults to g_fGridSearchRadius
 * @return          true if a valid cell was found, false otherwise
 */
bool FindNearbyValidSpawnCell(const float origin[3], float outPos[3], float radius = -1.0)
{
    if (radius<=0.0) radius = g_fGridSearchRadius;
    if (radius<=0.0)
    {
        LogMessage("[zm] radius %f skipped", radius);
        return false;
    }

    LogMessage("[zm] FindNearbyValidSpawnCell origin=(%.0f,%.0f,%.0f) radius=%.0f", origin[0], origin[1], origin[2], radius);

    if (!GridLib_IsReady())
    {
        LogMessage("[zm] FindNearbyValidSpawnCell: GridLib not ready");
        return false;
    }

    int cells[16];
    int count = GridLib_FindNearbyCells(origin, radius, 200.0, cells, 16);
    LogMessage("[zm] FindNearbyValidSpawnCell: %d candidates found", count);

    for (int i = 0; i < count; i++)
    {
        // Skip nav-blocked cells (saferooms, player start, etc.)
        if (GridLib_GetCellSpawnAttributes(cells[i]) & GRIDLIB_NAV_BLOCKED_ZOMBIES)
            continue;

        float cellPos[3], normal[3];
        Address navArea;
        bool obstructed;
        if (!GridLib_GetCellData(cells[i], cellPos, normal, navArea, obstructed))
            continue;

        if (obstructed)
            continue;

        // Distance check against all alive survivors
        float minDist = min_distance_to_survivors(cellPos);
        if (minDist >= 0.0 && g_fSpawnMinDistance > 0.0 && minDist < g_fSpawnMinDistance)
        {
            LogMessage("[zm] FindNearbyValidSpawnCell: cell %d too close (%.0f)", i, minDist);
            continue;
        }

        // Visibility check (cheap variant for batch cell filtering)
        if (can_any_alive_survivor_see_cheap(cellPos))
        {
            LogMessage("[zm] FindNearbyValidSpawnCell: cell %d visible to survivors", i);
            continue;
        }

        LogMessage("[zm] FindNearbyValidSpawnCell: valid cell %d at (%.0f,%.0f,%.0f)", i, cellPos[0], cellPos[1], cellPos[2]);
        outPos = cellPos;
        return true;
    }

    LogMessage("[zm] FindNearbyValidSpawnCell: no valid cell found");
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
        
        if (target_client<0 && spawner_state!=SPAWNER_OK)
	    {
            target_client = spawner_nearest_survivor;
            float test_pos[3];
            test_pos = zm_spawner_pos;
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
	
	if (!IsValidClient(target_client) || !IsPlayerAlive(target_client) || GetClientTeam(target_client)!=TEAM_SURVIVOR)
        	return -1;
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
