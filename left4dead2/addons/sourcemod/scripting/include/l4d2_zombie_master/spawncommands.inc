///////////////////////////////////////
#if defined _zm_spawn_commands_included
 #endinput
#endif
#define _zm_spawn_commands_included
///////////////////////////////////////

/**
 * Timer callback that spawns free angry common infected up to a target count.
 * Tops up commons to reach `count` by spawning near the highest-flow survivor.
 * Stops if the plugin is disabled or the round hasn't started.
 *
 * @param timer  Timer handle (unused)
 * @param count  Target number of common infected to reach
 */
Action Timer_Free_Angry_Zombies(Handle timer, int count)
{
     if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return Plugin_Stop;
     CountCommons();
     if (live_zombie_arr[ZOMBIECLASS_COMMON]>=count) return Plugin_Stop;
     count = count - live_zombie_arr[ZOMBIECLASS_COMMON];
     if (count<=0) return Plugin_Stop;
     int target = L4D_GetHighestFlowSurvivor();
     spawn_free_angry_zombies(target,count);
     return Plugin_Stop;
}

/**
 * Timer callback that spawns a single free angry zombie targeting the given entity.
 * Used for delayed spawns (e.g. after a survivor event triggers bonus zombies).
 *
 * @param timer   Timer handle (unused)
 * @param entref  Entity reference of the survivor to target
 */
Action Delayed_Free_Angry_Zombie(Handle timer, int entref)
{
     if (!IsValidEntRef(entref)) return Plugin_Stop;
     spawn_free_angry_zombies(EntRefToEntIndex(entref),1,true);
     return Plugin_Stop;
}

/**
 * Console command handler for zm_horde. Parses arguments (count, type, angry, flow)
 * and delegates to ZM_Horde for the actual spawn logic.
 */
Action ZM_Spawn_Horde(int client, int args)
{
    if (!g_bCvarAllow || client!=zm_client) return Plugin_Continue;
    int count = 10;
    bool angry = false;
    bool flow = false;
    char type[16] = "";
    if (args>0)
    {
        static char arg[16] = "";
        GetCmdArg(1,arg,sizeof(arg));
        process_horde_arg(count,type,angry,flow,arg);
    	if (args>1) {GetCmdArg(2,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    	if (args>2) {GetCmdArg(3,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    	if (args>3) {GetCmdArg(4,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    }
    ZM_Horde(client,count,type,angry,flow);
    return Plugin_Continue;
}

/**
 * Repeating timer callback that checks if a clown uncommon is rushing or visible to a survivor.
 * If so, applies a red glow to make it visually distinct. Stops checking during panic events.
 *
 * @param timer   Timer handle (unused)
 * @param entref  Entity reference of the clown common infected
 */
Action clown_check_rush(Handle timer, int entref)
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    if (panic) return Plugin_Continue;
    bool glow = false;
    if ((GetEntProp(entref, Prop_Send, "m_mobRush"))>0) glow = true;
    else
    {
       	int looktarget = GetEntPropEnt(entref, Prop_Send, "m_clientLookatTarget");
       	if (IsValidClient(looktarget) && IsPlayerAlive(looktarget) && GetClientTeam(looktarget)==TEAM_SURVIVOR)
       	{
           	float pos[3];
           	L4D_GetEntityWorldSpaceCenter(entref,pos);
           	pos[2] += 36.0;
           	glow = L4D2_IsVisibleToPlayer(looktarget,TEAM_SURVIVOR,3,0,pos);
       	}
    }
    if (glow)
    {
       	int eFlags = GetEdictFlags(entref);
        if ((eFlags & FL_EDICT_ALWAYS)<=0) SetEdictFlags(entref, eFlags | FL_EDICT_ALWAYS);
       	L4D2_SetEntityGlow(entref,L4D2Glow_Constant,3000,0,{160,40,40},false);
       	return Plugin_Stop;
   	}
    return Plugin_Continue;
}

/**
 * Set a random yaw (horizontal rotation) for spawned entities so they don't all face the same way.
 */
void get_random_xy_orientation(float angle[3])
{
    angle[1] = GetRandomFloat(-180.0,180.0);
}

/**
 * Core horde spawn logic. Spawns common or uncommon infected at the ZM's aimed position,
 * a GridLib fallback cell, or a random position near a target survivor. Handles cost
 * calculation, limit enforcement, cooldown checks, model selection, and angry/rush behavior.
 *
 * @param client  Client index of the ZM (or 0 for server-initiated spawns)
 * @param count   Number of commons to spawn (capped by limits and bank)
 * @param type    Uncommon type string: "riot", "ceda", "clown", "mud", "road", "jimmy",
 *                "fallen", "random", or "" for regular commons
 * @param angry   If true, spawned zombies rush survivors (costs more outside panic/finale)
 * @param flow    If true, spawn near the highest-flow survivor instead of the aimed position
 * @param hint    If true, show HUD feedback to the ZM
 */
void ZM_Horde(int client, int count=10, char type[16]="", bool angry = false, bool flow = false, bool hint = true, float t_budget_ms = HORDE_BUDGET_MS)
{
	if (!g_bCvarAllow) return;
	if (!(client==zm_client || client==0)) return;
	if (DEBUG) LogMessage("[zm] ZM_Horde");
	
	float t_start = GetEngineTime(); // for profiling
	
	if (hint && is_zm_spamming()) return;
	
	CountCommons(null,false);
	if (live_zombie_arr[ZOMBIECLASS_COMMON]>=max_zombie_arr[ZOMBIECLASS_COMMON])
	{
        if (hint) update_hint("%T", "Limit reached", zm_client);
        return;
	}
	
	if (!is_zombie_available_cooldown(ZOMBIECLASS_COMMON))
	{
        if (hint) update_hint("%T", "Cooldown active", zm_client);
        return;
	}
	
	if ((live_zombie_arr[ZOMBIECLASS_COMMON]+count)>max_zombie_arr[ZOMBIECLASS_COMMON])
	   count = max_zombie_arr[ZOMBIECLASS_COMMON]-live_zombie_arr[ZOMBIECLASS_COMMON];
	if (count>available_zombie_arr[ZOMBIECLASS_COMMON]) count = available_zombie_arr[ZOMBIECLASS_COMMON];
	
	g_iEntities = GetEntityCountEx();
	if(count<=0 || (g_iEntities+count)>=ENTITY_SAFER_LIMIT)
	{
	   if (hint) update_hint("%T", "Limit reached", zm_client);
	   return;
    }
    
    if (IsValidClientZM()) update_t_zm_activity();
    
    TrimString(type);
    bool force_type = false;
    if (g_sForceCommon[0]!=0 && valid_uncommon(g_sForceCommon))
    {
        strcopy(type,sizeof(type),g_sForceCommon);
        force_type = true;
    }
    else if (type[0]!=0 && !valid_uncommon(type)) strcopy(type,sizeof(type),"");
	
	if (g_iCostCommon<0 && type[0]==0) strcopy(type,sizeof(type),"random"); // commons disabled -> can only spawn uncommons
	else if (type[0]!=0 && g_iCostUncommon<0) strcopy(type,sizeof(type),""); // uncommons disabled -> can only spawn commons
	
	if (strcmp(type,"jimmy",false)==0)
	{
    	if (jimmy_spawned && !force_type) return;
    	if (!force_type) count = 1;
	}
	else if (strcmp(type,"fallen",false)==0)
   	{
       	if (fallen_spawned && !force_type) return;
       	if (!force_type) count = 1;
   	}
   	
   	TrimString(type);
	
	int temp_cost = -1;
	bool price_angry = angry && ( !panic && !ZM_finale_announced && !L4D_IsSurvivalMode() );
	switch (price_angry)
	{
       	case false: // Not angry - regular price
       	{
           	if (type[0]!=0) temp_cost = g_iCostUncommon;
           	else temp_cost = g_iCostCommon;
       	}
       	default: // Angry - more expensive. Doubly more expensive if angry uncommon.
       	{
           	if (type[0]!=0) temp_cost = 2*g_iCostUncommon;
           	else if (g_iCostCommon>=0) temp_cost = g_iCostUncommon; // disables aggro common if commons are disabled
       	}
	}
	
	if (temp_cost<0)
	{
    	if (hint) update_hint("%T", "Limit reached", zm_client);
 	    return;
	}
	
	int max_count = RoundToFloor(float(bank)/(temp_cost));
	if (count>max_count) count = max_count;
	
	if ( count<=0 || (bank-temp_cost*count)<0 )
	{
       	if (hint) update_hint("%T", "afford_common", zm_client);
       	return;
	}

	angry = angry || panic;

	// Resolve spawn positions via provider
	static float resolvedPositions[1500]; // 500 * 3 flat
	int posCount = Spawner_ResolveCommonPositions(count,flow,angry,hint,resolvedPositions,500);
	if (posCount < count) count = posCount;
	if (count<=0)
	{
    	if (zm_allow_spawns && g_iSpawnerMode>1 && hint) update_hint("%T", "Spawn failed", zm_client);
    	return;
    }

	int spawned = 0;
	float randomPos[3], angle[3];
	bool glow, random;

	char set_model[64] = "";
	if (strcmp(type,"random")==0) random = true;
    else if (g_bClownGlow && strcmp(type,"clown")==0) glow = true;

	for( int i = 0; i < count; i++  )
	{
		int idx = (i % posCount) * 3;
		randomPos[0] = resolvedPositions[idx];
		randomPos[1] = resolvedPositions[idx+1];
		randomPos[2] = resolvedPositions[idx+2];

        if (!angry) get_random_xy_orientation(angle);
		int zombie = -1;
		if (type[0]!=0) get_uncommon_model(type,set_model);
		if (set_model[0]==0) zombie = L4D_SpawnCommonInfected(randomPos,angle);
		else
		{
      		zombie = CreateEntityByName("infected");
      		if (zombie!=-1)
      		{
          		if (random) glow = strcmp(set_model,MODEL_CLOWN)==0;
          		SetEntityModel(zombie,set_model);
          		TeleportEntity(zombie,randomPos,angle,NULL_VECTOR);
                DispatchSpawn(zombie);
              	if (glow && !ZM_finale_announced && !L4D_IsSurvivalMode())
                  	CreateTimer(1.0,clown_check_rush,EntIndexToEntRef(zombie),TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
                if (strcmp(set_model,MODEL_FALLEN3,false)==0) SetEntProp(zombie,Prop_Send,"m_nBody",GetRandomInt(0,1));
          	}
		}
		
        if (zombie>0)
        {
           if (!playcount_increased && zm_stage>=ZM_STARTED && IsValidClientZM()) increase_playcount(zm_client);
           spawned += 1;
           bank -= temp_cost;
           live_zombie_arr[ZOMBIECLASS_COMMON] += 1;
           g_iEntities += 1;
           if (angry)
           {
               //if (hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
               SetEntProp(zombie, Prop_Send, "m_mobRush", 1);
           }
           if (g_hCursed.BoolValue)
           {
               SetEntPropFloat(zombie,Prop_Send,"m_flModelScale",GetRandomFloat(0.5,2.0)); 
               ChangeEdictState(zombie);
           }
           if (type[0]!=0 || price_angry) DispatchKeyValue(zombie, "targetname", "zm_unit_uncommon");
           else DispatchKeyValue(zombie, "targetname", "zm_unit_common");
           Spawner_NotifySpawned(zombie);
        }
        if ((GetEngineTime()-t_start)*1000.0>t_budget_ms) break;
    }
    Spawner_EndSpawn();

	if (spawned<=0)
	{
    	if (hint) update_hint("%T", "Spawn failed", zm_client);
    	if (live_zombie_arr[ZOMBIECLASS_COMMON]<10) SetConVarInt(FindConVar("director_panic_forever"), 0);
	}
	else
	{
        
	    if (hint)
	    {
    	    char label[32];
    	    Format(label, sizeof(label), "%T", "Common", zm_client);
    	    update_hint("%T", "Spawned X Y", zm_client, spawned, label);
	    }
	    add_available_zombie(ZOMBIECLASS_COMMON,-spawned);
	    if (!force_type)
	    {
    	    if (strcmp(type,"jimmy")==0)
    	    {
        	    jimmy_spawned = true;
        	    create_boss_menu();
    	    }
    	    else if (strcmp(type,"fallen")==0)
    	    {
        	    fallen_spawned = true;
        	    create_boss_menu();
    	    }
	    }
    	if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
    	//zm_update();
    	update_EMS_HUD();
	}
	
	float elapsed_ms = (GetEngineTime()-t_start)*1000.0;
	if (elapsed_ms>t_budget_ms) LogMessage("ZM_Horde ct=%d %s angry=%d flow=%d took %f ms",count,type,angry,flow,elapsed_ms);
	
}

/**
 * Spawn a witch at the ZM's aimed position or a fallback location. Handles cost/limit checks,
 * time-of-day override (sitting vs wandering), and witch bride variant selection.
 *
 * @param client      Client index of the ZM (or 0 for server-initiated)
 * @param witch_type  WITCH_STATIC (sitting) or WITCH_MOVING (wandering)
 * @param free        If true, skip cost deduction
 * @param flow        If true, spawn near the highest-flow survivor
 */
void ZM_Witch(int client,int witch_type, bool free = false, bool flow = false)
{

	if (!g_bCvarAllow) return;
	if (!(client==zm_client || client==0)) return;

	if (DEBUG) LogMessage("[zm] ZM_Witch");

	if (is_zm_spamming()) return;

	int temp_cost;
	if (!free)
	{
    	if (witch_type==WITCH_STATIC) temp_cost=g_iCostWitchStatic;
    	else temp_cost=g_iCostWitchMoving;
    	if ((bank-temp_cost)<0)
    	{
        	update_hint("%T", "Cannot afford", zm_client);
        	return;
    	}
	}

	CountWitches(false);
	if (live_zombie_arr[ZOMBIECLASS_WITCH]>=max_zombie_arr[ZOMBIECLASS_WITCH] || temp_cost<0)
	{
    	update_hint("%T", "Limit reached", zm_client);
    	return;
	}

	if (!is_zombie_available_cooldown(ZOMBIECLASS_WITCH))
	{
    	update_hint("%T", "Cooldown active", zm_client);
        return;
	}

	if (IsValidClientZM()) update_t_zm_activity();

	static float spawn_pos[3];
	if (!Spawner_ResolveWitchPosition(flow,spawn_pos))
	{
	    if (zm_allow_spawns && g_iSpawnerMode>1) update_hint("%T", "Spawn failed", zm_client);
	    return;
	}

	if (witch_type==WITCH_STATIC) SetConVarInt(FindConVar("sv_force_time_of_day"),0);
	else SetConVarInt(FindConVar("sv_force_time_of_day"),3);

	float angle[3];
	get_random_xy_orientation(angle);

	int witch;
	if(g_bSpawnWitchBride) witch = L4D2_SpawnWitchBride(spawn_pos,angle);
    else witch = L4D2_SpawnWitch(spawn_pos,angle);

	if (witch>0)
	{
       	if (strcmp(g_sZMGamemode,"zm_jimmypocalypse",false)==0 && witch_type==WITCH_STATIC) SetEntityModel(witch,MODEL_JIMMY);
       	if (!free) bank -= temp_cost;
       	live_zombie_arr[ZOMBIECLASS_WITCH] += 1;
       	if (DEBUG) LogMessage("[zm] Created witch %d", witch);
       	CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(witch), TIMER_FLAG_NO_MAPCHANGE);
       	entref_delete = EntIndexToEntRef(witch);
       	add_available_zombie(ZOMBIECLASS_WITCH,-1);
       	static char label[32];
   	    Format(label, sizeof(label), "%T", "Witch", zm_client);
   	    update_hint("%T", "Spawned X Y", zm_client, 1, label);
       	DispatchKeyValue(witch, "targetname", "zm_unit");
       	Spawner_NotifySpawned(witch);
       	if (!playcount_increased && zm_stage>=ZM_STARTED) increase_playcount(zm_client);
       	if (g_hCursed.BoolValue)
       	{
           	SetEntPropFloat(witch,Prop_Send,"m_flModelScale",GetRandomFloat(0.5,2.0));
           	ChangeEdictState(witch);
       	}
	}
	else update_hint("%T", "Spawn failed", zm_client);

}

/**
 * Recount live witches using L4D2_GetWitchCount(). Skips the expensive count
 * if fast=true and the tracked count is already zero.
 */
void CountWitches(bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_WITCH]<=0 && fast) return;
    if (DEBUG) LogMessage("[zm] CountWitches expensive");
    live_zombie_arr[ZOMBIECLASS_WITCH] = L4D2_GetWitchCount();
}

/**
 * Timer callback that kills an entity by firing the "Kill" input. Used as a
 * follow-up to dissolve_forcekill since L4D_Dissolve doesn't always kill.
 */
Action kill_entity(Handle timer, int entref)
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    AcceptEntityInput(entref,"Kill");
    return Plugin_Stop;
}

/**
 * Dissolve an entity with a visual effect, then schedule a hard kill 2 seconds later
 * as a failsafe since L4D_Dissolve doesn't always remove the entity.
 */
void dissolve_forcekill(int entity)
{
    L4D_Dissolve(entity); // doesn't always kill them
    CreateTimer(2.0,kill_entity,EntIndexToEntRef(entity),TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Delete all ZM-spawned infected entities by category. Iterates all entities,
 * removes glows, dissolves commons/witches, and kills special infected bots.
 * Protects non-ZM tanks during finale/survival from deletion.
 *
 * @param common   Delete common infected
 * @param witch    Delete witches
 * @param special  Delete special infected (bot players)
 */
void delete_all_infected(bool common=true, bool witch=true, bool special=true)
{
   	bool anything_to_delete = false;
   	if (common && live_zombie_arr[ZOMBIECLASS_COMMON]>0) anything_to_delete = true;
   	if (witch && live_zombie_arr[ZOMBIECLASS_WITCH]>0) anything_to_delete = true;
   	if (special && live_SI>0) anything_to_delete = true;
   	if (!anything_to_delete) return;

   	reset_live_zombie_arr(common,witch,special);

   	if (DEBUG) LogMessage("[zm] delete_all_infected");

   	static char class[32];
   	int entity;
   	for(entity = 1; entity<=MAXENTITIES; entity++)
   	{
   		if(IsValidEntity(entity))
   		{
   		     if (IsValidClient(entity) && !IsFakeClient(entity)) continue;
   		     if (GetEntProp(entity,Prop_Data,"m_iMaxHealth")<=0) continue;
      	     GetEntityClassname(entity, class, sizeof(class));
      	     if ( (ZM_finale_announced || L4D_IsSurvivalMode()) && strcmp(class,"player")==0 && GetEntProp(entity, Prop_Send, "m_zombieClass")==ZOMBIECLASS_TANK )
             {
                 static char targetName[20];
                 GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
                 if (strcmp(targetName,"zm_unit")!=0)
                 {
                     live_zombie_arr[ZOMBIECLASS_TANK] += 1;
                     continue;
                 }
             }

      	     if ( (common && strcmp(class,"infected")==0) || (witch && strcmp(class,"witch")==0) || (special && strcmp(class,"player")==0 && GetClientTeam(entity)==TEAM_INFECTED) )
      	     {
          	     remove_ZM_glow(entity);
          	     if (strcmp(class,"player")==0) AcceptEntityInput(entity,"Kill");
                 else dissolve_forcekill(entity);
      	     }
   		}
   	}

   	if (special && clients_timer==INVALID_HANDLE)
   	   clients_timer = CreateTimer(0.1,CountClients);
   	if (common) live_zombie_arr[ZOMBIECLASS_COMMON] = 1; // Dissolve doesn't always work
}

/**
 * Console command handler for sm_zm_witch. Parses arguments (witch_type, flow)
 * and delegates to ZM_Witch for the actual spawn logic.
 */
Action ZM_Spawn_Witch(int client, int args)
{
	if (!g_bCvarAllow || client!=zm_client) return Plugin_Continue;
	int witch_type = WITCH_STATIC;
	bool flow = false;
	if (args>0)
	{
	    int arg_int;
        static char arg[16];
        bool hit = false;
    	// Check Argument 1
    	GetCmdArg(1,arg,sizeof(arg));
    	if (strcmp(arg,"flow")==0) flow = true;
    	else
    	{
        	arg_int = GetCmdArgInt(1);
        	if (arg_int==WITCH_STATIC || arg_int==WITCH_MOVING) witch_type = arg_int;
    	}

    	// Check Argument 2
    	if (args>1)
    	{
        	hit = false;
        	if (!flow)
        	{
            	GetCmdArg(2,arg,sizeof(arg));
            	if (strcmp(arg,"flow")==0)
            	{
                	flow = true;
                	hit = true;
            	}
        	}
        	if (!hit)
        	{
            	arg_int = GetCmdArgInt(2);
            	if (arg_int==WITCH_STATIC || arg_int==WITCH_MOVING) witch_type = arg_int;
        	}
    	}
	}
	ZM_Witch(client,witch_type,_,flow);
	return Plugin_Continue;
}

/**
 * Delete the entity the ZM is currently pointing at (tracked via entref_delete).
 * Validates the target, protects non-ZM tanks during finale/survival,
 * then dissolves or kills the entity and updates counts.
 */
void zm_del_pointing(int client)
{

   if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;

   if (DEBUG) LogMessage("[zm] zm_del_pointing");

   if (is_zm_spamming()) return;

   update_t_zm_activity();
   update_ZM_looktarget(false);
   if (!IsValidEntRef(entref_delete))
   {
       update_hint("%T", "Invalid target", zm_client);
       return;
   }
   int target = EntRefToEntIndex(entref_delete);
   if ( !IsValidEntity(target) || (target<=MaxClients && !IsFakeClient(target)) )
   {
       update_hint("%T", "Invalid target", zm_client);
       return;
   }

   static char class[32];
   GetEntityClassname(target, class, sizeof(class));

   if ( (ZM_finale_announced || L4D_IsSurvivalMode()) && strcmp(class,"player")==0 &&
       GetEntProp(target, Prop_Send, "m_zombieClass")==ZOMBIECLASS_TANK )
   {
       static char targetName[20];
       GetEntPropString(target, Prop_Data, "m_iName", targetName, sizeof(targetName));
       if (strcmp(targetName,"zm_unit")!=0)
       {
           update_hint("%T", "Cannot delete", zm_client);
           return;
       }
   }

   if (strcmp(class,"player")==0) AcceptEntityInput(target,"Kill");
   else dissolve_forcekill(target);

   if (strcmp(class,"player")==0)
   {
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
   }
   else if (strcmp(class,"witch")==0) CountWitches();
   else CountCommons();

}

/**
 * Spawn free angry (rushing) common infected targeting a specific survivor.
 * Used for boomer vomit response and bonus zombie events. Caps to max commons limit
 * and optionally refunds excess bank cost if fewer zombies could be spawned.
 *
 * @param victim  Client index of the survivor the zombies will target
 * @param count   Number of angry commons to spawn
 * @param refund  If true, refund bank for zombies that couldn't spawn due to limits
 */
void spawn_free_angry_zombies(int victim, int count, bool refund = true)
{

    int old_count = count;

    if (DEBUG) LogMessage("[zm] spawn_free_angry_zombies");

    CountCommons(null,false);

    if ((live_zombie_arr[ZOMBIECLASS_COMMON]+count)>max_zombie_arr[ZOMBIECLASS_COMMON])
       count = max_zombie_arr[ZOMBIECLASS_COMMON]-live_zombie_arr[ZOMBIECLASS_COMMON];

    if (refund && old_count>count && g_iCostCommon>0) bank += g_iCostCommon*(old_count-count);
    if (count<=0) return;
    if (!IsValidClient(victim) || GetClientTeam(victim)!=TEAM_SURVIVOR) return;

    g_iEntities = GetEntityCountEx();
	if((g_iEntities+count)>=ENTITY_SAFER_LIMIT) return;

    float vecPos[3];
    for( int i = 0; i < count; i++  )
    {
        int zombie = -1;
        if(L4D_GetRandomPZSpawnPosition(victim,ZOMBIECLASS_TANK,10,vecPos))
        {
            zombie = L4D_SpawnCommonInfected(vecPos);
            if (zombie>0)
            {
                live_zombie_arr[ZOMBIECLASS_COMMON] += 1;
                //if (hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
                SetEntProp(zombie, Prop_Send, "m_mobRush", 1);
                if (IsPlayerAlive(victim)) command_infected_attack(zombie,victim);
            }

        }
    }

    if (IsValidClientZM()) update_EMS_HUD();

}

/**
 * RequestFrame callback that resets a special infected's ability cooldown
 * Applied after spawning to fix spitter ability delay.
 */
void OnNextFrame_ZeroCooldown(int entity)
{
    if (!IsValidClient(entity)) return;
    L4D2_SetCustomAbilityCooldown(entity,1.0);
}

/**
 * Core special infected spawn logic. Creates a bot via NextBotCreatePlayerBot SDKCall,
 * teleports it to the ZM's aimed position (or a fallback), and configures it.
 * Handles cost deduction, limit/cooldown checks, freeze during prep time, glow assignment,
 * and first-tank discount tracking.
 *
 * @param client      Client index of the ZM (or 0 for server-initiated)
 * @param ZOMBIECLASS Zombie class ID (ZOMBIECLASS_SMOKER through ZOMBIECLASS_TANK)
 * @param free        If true, skip cost deduction
 * @param setpos      If true, use the provided pos instead of the ZM's aim position. Should only be used for zm_control because it bypasses many checks.
 * @param pos         Explicit spawn position (only used when setpos=true)
 * @param glow        If true, apply a white ZM glow to the spawned bot
 * @param flow        If true, spawn near the highest-flow survivor
 * @return            Client index of the spawned bot, or -1 on failure
 */
int ZM_Spawn_SI(int client, int ZOMBIECLASS, bool free = false, bool setpos=false, float pos[3] = {0.0,0.0,0.0}, bool glow = true, bool flow = false)
{
	if (!g_bCvarAllow || ZOMBIECLASS<=0) return -1;
	if (!(client==zm_client || client==0)) return -1;

	if (!l4d2_specials)
    {
        if (ZOMBIECLASS==ZOMBIECLASS_SPITTER || ZOMBIECLASS==ZOMBIECLASS_JOCKEY || ZOMBIECLASS==ZOMBIECLASS_CHARGER)
            return -1;
    }

	//LogMessage("[zm] ZM_Spawn_SI %d %d", ZOMBIECLASS, flow);

	if (!setpos && is_zm_spamming()) return -1;

	int cost_SI;
	if (!free)
	{
    	cost_SI = costs_SI[ZOMBIECLASS];
    	if ((bank-cost_SI)<0)
    	{
        	update_hint("%T", "afford_special", zm_client);
        	return -1;
    	}
	}

	float spawn_pos[3];

	if (!setpos)
	{
	    if (live_SI>=max_SI || live_zombie_arr[ZOMBIECLASS]>=max_zombie_arr[ZOMBIECLASS] || cost_SI<0)
        {
            update_hint("%T", "Limit reached", zm_client);
            return -1;
        }

	    if (!is_zombie_available_cooldown(ZOMBIECLASS))
        {
           	update_hint("%T", "Cooldown active", zm_client);
           	return -1;
        }
        
        if (!Spawner_ResolveSpecialPosition(ZOMBIECLASS,flow,spawn_pos))
        {
            if (zm_allow_spawns && g_iSpawnerMode>1) update_hint("%T", "Spawn failed", zm_client);
            return -1;
        }
    }
    else spawn_pos = pos;

    if (IsValidClientZM()) update_t_zm_activity();

	int bot = -1;

	switch (ZOMBIECLASS)
	{
        case ZOMBIECLASS_SMOKER: bot = SDKCall(hCreateSmoker, "ZM Smoker");
    	case ZOMBIECLASS_BOOMER: bot = SDKCall(hCreateBoomer, "ZM Boomer");
    	case ZOMBIECLASS_HUNTER: bot = SDKCall(hCreateHunter, "ZM Hunter");
    	case ZOMBIECLASS_SPITTER: bot = SDKCall(hCreateSpitter, "ZM Spitter");
    	case ZOMBIECLASS_JOCKEY: bot = SDKCall(hCreateJockey, "ZM Jockey");
    	case ZOMBIECLASS_CHARGER: bot = SDKCall(hCreateCharger, "ZM Charger");
    	case ZOMBIECLASS_TANK: bot = SDKCall(hCreateTank, "ZM Tank");
	}

	if (IsValidClient(bot))
	{
       	float angle[3];
        get_random_xy_orientation(angle);
       	ChangeClientTeam(bot, TEAM_INFECTED);
       	SetEntProp(bot, Prop_Send, "m_usSolidFlags", 16);
       	SetEntProp(bot, Prop_Send, "deadflag", 0);
       	SetEntProp(bot, Prop_Send, "m_lifeState", 0);
       	SetEntProp(bot, Prop_Send, "m_iObserverMode", 0);
       	SetEntProp(bot, Prop_Send, "m_iPlayerState", 0);
       	SetEntProp(bot, Prop_Send, "m_zombieState", 0);
       	DispatchSpawn(bot);
       	ActivateEntity(bot);
       	TeleportEntity(bot, spawn_pos, angle, NULL_VECTOR);
       	if (zm_stage<ZM_STARTED || specials_frozen)
       	{
           	freeze_player(bot,true,TEAM_INFECTED);
       	}
       	else SetEntProp(bot, Prop_Send, "movetype", 2);
       	if (!free) bank -= cost_SI;

       	request_crouch(EntIndexToEntRef(bot));
        RequestFrame(request_crouch,EntIndexToEntRef(bot));

       	if (glow) CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(bot), TIMER_FLAG_NO_MAPCHANGE);

       	entref_delete = EntIndexToEntRef(bot);
       	active_looktarget = true;
        update_entref_control(entref_delete,true);

        if (!setpos)
        {

            active_looktarget = true;
            add_available_zombie(ZOMBIECLASS,-1);
            L4D2_SetCustomAbilityCooldown(bot,1.0); // 1.0s cooldown to prevent abuse
            RequestFrame(OnNextFrame_ZeroCooldown,bot);

            if (ZOMBIECLASS==ZOMBIECLASS_TANK && g_bDiscountTank && first_tank_stage==0)
            {
               	first_tank_price = cost_SI;
               	first_tank_stage += 1;
               	update_dynamic_tank();
            }

            if (IsValidClientZM())
            {
                if (!zm_use_notify)
                {
                    update_hint("%T", "ZM control hint", zm_client);
                    if (IsValidClientZM()) PrintHintText(zm_client, "%t", "ZM control hint");
                }
                else
                {
                    static char name[32];
                    get_zombieclass_name(ZOMBIECLASS,name);
                    Format(name, sizeof(name), "%T", name, zm_client);
                    update_hint("%T", "Spawned X Y", zm_client, 1, name);
                }
            }

            Spawner_NotifySpawned(bot);
            if (!playcount_increased && zm_stage>=ZM_STARTED) increase_playcount(zm_client);
        }
        else update_EMS_HUD();

        //L4D2_CommandABot(bot,L4D_GetHighestFlowSurvivor(),BOT_CMD_ATTACK);
        if (g_hCursed.BoolValue && ZOMBIECLASS==ZOMBIECLASS_JOCKEY)
        {
            SetEntPropFloat(bot,Prop_Send,"m_flModelScale",GetRandomFloat(0.5,2.0));
            ChangeEdictState(bot);
        }

	}
	else update_hint("%T", "Spawn failed", zm_client);

	return bot;
}

/** Console command handler for sm_zm_smoker. Supports optional "flow" argument. */
Action ZM_Smoker(int client, int args)
{
   static char extra[32];
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_SMOKER,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_boomer. Supports optional "flow" argument. */
Action ZM_Boomer(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_BOOMER,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_hunter. Supports optional "flow" argument. */
Action ZM_Hunter(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_HUNTER,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_spitter. Supports optional "flow" argument. */
Action ZM_Spitter(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_SPITTER,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_jockey. Supports optional "flow" argument. */
Action ZM_Jockey(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_JOCKEY,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_charger. Supports optional "flow" argument. */
Action ZM_Charger(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_CHARGER,extra);
   return Plugin_Continue;
}

/** Console command handler for sm_zm_tank. Supports optional "flow" argument. */
Action ZM_Tank(int client, int args)
{
   static char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   else strcopy(extra,sizeof(extra),"");
   ZM_Unit_Special(client,ZOMBIECLASS_TANK,extra);
   return Plugin_Continue;
}

/**
 * Shared handler for all individual SI console commands. Spawns the SI via ZM_Spawn_SI
 * and tags it with the "zm_unit" targetname. Parses the "flow" argument.
 */
Action ZM_Unit_Special(int client, int ZOMBIECLASS, char[] arg = "")
{
    bool flow = false;
    if (strcmp(arg,"flow",false)==0) flow = true;
    int bot = ZM_Spawn_SI(client,ZOMBIECLASS,_,_,_,_,flow);
    if (IsValidClient(bot)) DispatchKeyValue(bot, "targetname", "zm_unit");
    return Plugin_Continue;
}

/** Console command handler for zm_delete. Deletes the entity the ZM is pointing at. */
Action ZM_Delete(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   zm_del_pointing(client);
   return Plugin_Continue;
}

/** Console command handler for zm_delete_all. Deletes all ZM-spawned infected. */
Action ZM_Delete_All(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(true,true,true);
   return Plugin_Continue;
}

/** Console command handler for zm_delete_commons. Deletes all ZM-spawned commons only. */
Action ZM_Delete_Commons(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(true,false,false);
   return Plugin_Continue;
}

/** Console command handler for zm_delete_specials. Deletes all ZM-spawned special infected only. */
Action ZM_Delete_Specials(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(false,false,true);
   return Plugin_Continue;
}

/** Console command handler for zm_delete_witches. Deletes all ZM-spawned witches only. */
Action ZM_Delete_Witches(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(false,true,false);
   return Plugin_Continue;
}
