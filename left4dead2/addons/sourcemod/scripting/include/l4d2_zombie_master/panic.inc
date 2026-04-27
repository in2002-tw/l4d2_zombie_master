///////////////////////////////////////
#if defined _zm_panic_included
 #endinput
#endif
#define _zm_panic_included
///////////////////////////////////////

bool DEBUG_PANIC = false;
#define PANIC_SPACING_SEC 5.0 // minimum time in seconds between panic refills
#define NATURAL_TIMEOUT 30.0 // how long to wait for director-initiated natural mob to reset after round start

Action ZMPanic(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (!panic) manual_panic = true;
    toggle_panic();
    return Plugin_Continue;
}

void update_panic()
{
    // No panic before round start, in survival, and finales.
    if (zm_stage!=ZM_STARTED || ZM_finale_announced || L4D_IsSurvivalMode()) return;
    
    if (DEBUG) LogMessage("[zm] update_panic triggered");
    
    if (!panic) toggle_panic(true,true,true);
    else
    {
        t_last_panic = GetGameTime();
        manual_panic = false;
        if (g_bPanicRefill) available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    }
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (pending_mob>0)
    {
        if (pending_mob>10 && (g_iCostCommon>=0 || g_iCostUncommon>=0)) pending_mob = 10; // if commons are enabled, assist ZM minimally.
        CreateTimer(2.5, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
        L4D2Direct_SetPendingMobCount(0);
    }
    RequestFrame(create_common_menu);
    RequestFrame(create_uncommon_menu);
    
}

void toggle_panic(bool state = true, bool overwrite = false, bool free = false)
{
    if (ZM_finale_announced || g_iPanicCost<0 || L4D_IsSurvivalMode())
    {
        update_hint("%T", "Panic is automatic", zm_client);
        if (panic)
        {
            disable_chase();
            panic=false;
        }
        return;
    }
    
    bool actual_state;
    if (overwrite) actual_state = state;
    else actual_state = !panic;
    
    if (DEBUG) LogMessage("[zm] toggle_panic %d %d %d", actual_state, overwrite, free);
    
    if ( zm_stage>=ZM_STARTED && actual_state )
    {
       
       if ( manual_panic && panic_conditions(_,true) ) // automatically fallback to free panic
       {
           manual_panic = false;
           free = true;
       }
       
       if (!free)
       {
           if ((bank-g_iPanicCost)<0)
           {
              update_hint("%T", "Cannot afford", zm_client);
              return;
           }
           bank -= g_iPanicCost;
       }
       else
       {
           if (DEBUG) LogMessage("[zm] Free panic");
       }
       
       if (DEBUG) LogMessage("[zm] Panic ON");
       if (zm_stage==ZM_STARTED && !panic && IsValidClientZM() && !ZM_finale_announced)
           EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
       panic = true;
       if (g_bPanicRefill) available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
       float t_now = GetGameTime();
       if (strcmp(g_sCvarMPGameMode,"zm_clowns",false)==0 && clown_world_enable && (t_now-t_last_panic)>=30.0) ServerCommand("clown_world_randomize");
       t_last_panic = t_now;
       t_last_autocommon = t_last_panic - 5.0; // immediately start spawning autocommon PANIC zombies
       L4D2Direct_SetPendingMobCount(0);
       if (manual_panic)
       {
           if (DEBUG) LogMessage("[zm] Manual panic");
           L4D_ForcePanicEvent();
       }
       if (!manual_panic && IsValidClientZM()) PrintHintText(zm_client, "%t", "ZM panic notify");
       if (manual_panic) update_hint("%T", "panic_rate_reduced", zm_client);
       actual_state = true;
       //infected_panic(hInfectedAttackSurvivorTeam);
       infected_panic(null);
    }
    else
    {
        if (DEBUG) LogMessage("[zm] Panic OFF");
        manual_panic = false;
        if (zm_stage<ZM_STARTED) update_hint("Round not started");
        else update_hint("%T", "panic_rate_normal", zm_client);
        actual_state = false;
        disable_chase();
        if (zm_stage==ZM_STARTED && panic && IsValidClientZM() && !ZM_finale_announced)
            EmitSoundToClient(zm_client,SOUND_PANIC_OFF);
        panic = false;
    }
    
    if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
    else SetConVarInt(FindConVar("director_panic_forever"), 0);
    RequestFrame(create_common_menu);
    RequestFrame(create_uncommon_menu);
    L4D2Direct_SetPendingMobCount(0);
    zm_update();
}

stock void infected_panic(Handle InfectedAttackSurvivorTeam,bool update_look = false)
{
    int zombie = INVALID_ENT_REFERENCE;
    while( INVALID_ENT_REFERENCE != (zombie = FindEntityByClassname(zombie, "infected")) )
    {
   	    if( IsValidEntity(zombie) && GetEntProp(zombie,Prop_Data,"m_iHealth")>0 ) 
   	    {
	        if (update_look) SetEntPropEnt(zombie, Prop_Send, "m_clientLookatTarget",GetRandomSurvivor(1,1));
	        if (InfectedAttackSurvivorTeam) SDKCall(InfectedAttackSurvivorTeam,zombie);
            else SetEntProp(zombie, Prop_Send, "m_mobRush", 1);
        }
    }
}

stock Action infinite_delay_natural_mob(Handle timer = null)
{
    CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
    if (MobSpawnTimer)
    {
        CTimer_Invalidate(MobSpawnTimer);
        CTimer_Start(MobSpawnTimer,3600.0); 
        CTimer_SetDuration(MobSpawnTimer,3600.0+100.0);
    }
    return Plugin_Stop;
}


float mob_timestamp;

// use zm_debug_mob to print these
bool panic_conditions(bool mob_just_spawned=false, bool ignore_spacing = false)
{
    if ( ZM_finale_announced || L4D_IsSurvivalMode() )
    {
        if (DEBUG_PANIC) LogMessage("panic_conditions: early exit");
        return false;
    }
    
    if (natural_first_wait && zm_stage>=ZM_STARTED && (GetGameTime()-t_round_start)>NATURAL_TIMEOUT) natural_first_wait = false;
    
    bool natural_mob = false;
    CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
    if (MobSpawnTimer)
    {
        float mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
        if ( (zm_stage!=ZM_STARTED || natural_first_wait) && mob_timer_elapsed<g_fPanicDuration)
        {
            // Director tends to reset natural mob timer when survivors first leave safe area which may trigger panic, fight this.
            CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
            if (zm_stage >= ZM_STARTED) natural_first_wait = false;
            if (DEBUG_PANIC) LogMessage("panic_conditions: natural_first_wait exit");
            return false;
        }
        float new_timestamp = CTimer_GetTimestamp(MobSpawnTimer);
        float mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
        if ( FloatAbs(new_timestamp-mob_timestamp)>=0.001 )
        {
            if (DEBUG_PANIC) LogMessage("[zm] MobSpawnTimer jumped %.2f, %.2f", mob_timer_left, mob_timer_elapsed);
            if (mob_timer_left<=5.0 && mob_timer_left>=(-1.0) && mob_timer_elapsed<g_fPanicDuration)
            {
                if (ignore_spacing || (GetGameTime()-t_last_panic)>PANIC_SPACING_SEC) natural_mob=true;
            }
        }
        mob_timestamp = new_timestamp;
        
        if (mob_timer_left>=5.0)
        {
            if (DEBUG_PANIC) LogMessage("panic_conditions: mob_timer_left >= 5.0");
            return false;
        }
        if (mob_timer_elapsed>=g_fPanicDuration)
        {
            if (DEBUG_PANIC) LogMessage("panic_conditions: mob_timer_elapsed >= %f", g_fPanicDuration);
            return false;
        }
        
    }
    else
    {
        if (DEBUG_PANIC) LogMessage("panic_conditions: bad timer");
        return false;
    }
    
    //if (panic && manual_panic)
    //{
    //    if (DEBUG_PANIC) LogMessage("panic_conditions: manual_panic");
    //    return false;
    //}
    if (script_CommonLimit<=0)
    {
        LogMessage("panic_conditions: script_CommonLimit");
        return false;
    }
    if (!natural_mob)
    {
        if (DEBUG_PANIC) LogMessage("panic_conditions: no natural mob");
        return false;
    }
    if (L4D2Direct_GetPendingMobCount()<=0 && !mob_just_spawned)
    {
        if (DEBUG_PANIC) LogMessage("panic_conditions: no mob");
        return false;
    }
    if (DEBUG_PANIC) LogMessage("panic_conditions: SATISFIED!");
    return true;
}

void check_panic(bool mob_spawned = false)
{
    //if (DEBUG_PANIC) LogMessage("check_panic");
    if (ZM_finale_announced || L4D_IsSurvivalMode())
    {
        if (DEBUG_PANIC) LogMessage("check_panic: exit early");
        return;
    }
    if (panic_conditions(mob_spawned)) update_panic();
    else if (panic && (GetGameTime()-t_last_panic)>=g_fPanicDuration ) toggle_panic(false,true,true);
    else if (!panic && !mob_spawned)
    {
        CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
        if (MobSpawnTimer)
        {
            float elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
            if ( elapsed>1000.0 || (elapsed<100.0 && elapsed>g_fPanicDuration) )
            {
                infinite_delay_natural_mob();
                CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
            }
            
        }
    }
}

void OnDirectorOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    if (DEBUG) LogMessage("[zm] info_director output %s fired! %d %d %f", output, activator, caller, delay);
    
    if (!ZM_finale_announced)
    {
       	if (strcmp(output,"OnCustomPanicStageFinished")==0)
       	{
           	manual_panic = false;
           	update_panic();
       	}
    }
}

Action zm_debug_mob(int client, int args)
{   
    bool finale_active = L4D_IsFinaleActive();
    int pending_mob = L4D2Direct_GetPendingMobCount();
   	float mob_timer_left = -1.0;
   	float mob_timer_elapsed = -1.0;
   	CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
   	if (MobSpawnTimer)
   	{
       mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
       mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
    }
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    
    CountCommons(null,false);
    int commons = live_zombie_arr[ZOMBIECLASS_COMMON];
    int panic_forever = FindConVar("director_panic_forever").IntValue;

    PrintToChat(client, "commons %d panic forever %d pending_mob %d finale_active %d CommonLimit %d",
                commons, panic_forever, pending_mob, finale_active, script_CommonLimit);
    PrintToChat(client, "MobTimer Remaining Elapsed %.2f %.2f", mob_timer_left, mob_timer_elapsed);
    PrintToChat(client, "natural wait %d dt_last_panic %f", natural_first_wait, GetGameTime()-t_last_panic);
    PrintToChat(client, "DirectorScriptScope %d %d %d %d %d", scope0, scope1, scope2, scope3, scope4);
    return Plugin_Continue;
}


// Full credit to Dragokas
void Chase(int target)
{
	if (DEBUG) LogMessage("[zm] Chase");
	
	if (ZM_finale_announced || L4D_IsSurvivalMode() )
	{
    	if (DEBUG) LogMessage("[zm] Infected chase is already set, ignoring.");
    	panic_target = -1;
    	return;
	}
	
	if (!IsClientInGame(target))
	{
    	panic_target = -1;
    	return;
	}
	
	bool bTeleported;
	float vPos[3];
	static int iChase = INVALID_ENT_REFERENCE;
	
	// Maybe ZM is being chased and they flew somewhere unreasonable.
	GetClientEyePosition(target, vPos);
	if (TR_PointOutsideWorld(vPos))
	{
    	panic_target = -1;
    	return;
	}
	
	int entity = EntRefToEntIndex(iChase);
	if( !entity || entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity) )
	{
		entity = FindEntityByClassname(MaxClients + 1, "info_goal_infected_chase");
		if( !entity || entity == INVALID_ENT_REFERENCE )
		{
		    if (DEBUG) LogMessage("[zm] New Chase created");
			entity = CreateEntityByName("info_goal_infected_chase");
			if( entity != -1 )
			{
				DispatchSpawn(entity);
				TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
				iChase = EntIndexToEntRef(entity);
				bTeleported = true;
			}
		}
	}
	if( entity != -1 )
	{
		if( !bTeleported)
		{
			AcceptEntityInput(entity, "Disable");
			AcceptEntityInput(entity, "ClearParent");
			TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
		}
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", target);
		AcceptEntityInput(entity, "Enable");
		if (DEBUG) LogMessage("[zm] Chase enabled");
		panic_target = target;
		char name[MAX_NAME_LENGTH];
        GetClientName(target,name,sizeof(name));
        update_hint("%T", "Chasing x", zm_client, name);
	}
	else panic_target = -1;
}

void disable_chase(bool kill = false)
{
    int chase_ent = FindEntityByClassname(MaxClients + 1, "info_goal_infected_chase");
    if (chase_ent && chase_ent != INVALID_ENT_REFERENCE)
    {
        if (DEBUG) LogMessage("[zm] Chase found, disabled");
     	if (kill) AcceptEntityInput(chase_ent, "Kill");
     	else AcceptEntityInput(chase_ent, "Disable");
    }
    panic_target = -1;
}

MRESReturn DHook_Director_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (DEBUG) LogMessage("[zm] DHook_Director_AcceptInput");
	if (!g_bCvarAllow) return MRES_Ignored;
	
	char inputName[32];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (DEBUG) LogMessage("[zm] info_director accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (strcmp(inputName,"ForcePanicEvent")==0)
	{
	   if (zm_stage<ZM_STARTED) survival_activated=true;
	   if (activator==-1 && caller==-1 && manual_panic) return MRES_Ignored; // Called by ZM -- do nothing
	   if (panic && manual_panic) bank += g_iPanicCost; // ZM paid for panic - refund them
	   manual_panic = false;
	   update_panic();
	}
	else if (strcmp(inputName,"PanicEvent")==0 || strcmp(inputName,"ScriptedPanicEvent")==0)
	{
        	if (panic && manual_panic) bank += g_iPanicCost;
        	manual_panic = false;
        	if (zm_stage<ZM_STARTED) survival_activated=true;
        	update_panic();
	}
	
	if (survival_activated && zm_stage<ZM_STARTED && L4D_IsSurvivalMode() && !IsValidClientZM())
	{
        	PrintToChatAll("[zm] %t", "Start delay notify");
        	hReturn.Value = true;
        	return MRES_Supercede;
	}
	
	return MRES_Ignored;
}