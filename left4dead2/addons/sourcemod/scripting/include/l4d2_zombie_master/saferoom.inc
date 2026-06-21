///////////////////////////////////////
#if defined _zm_saferoom_included
 #endinput
#endif
#define _zm_saferoom_included
///////////////////////////////////////

Action saferoom_disturb(Handle timer, float vPos[3])
{
    if (!IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED) return Plugin_Stop;
    int random = GetRandomInt(1,3);
    char sound[64];
    switch (random)
    {
        case 1: {sound=SOUND_DOORSLAM;}
        case 2: {sound=SOUND_DOORSLAM2;}
        case 3: {sound=SOUND_DOORSLAM3;}
        default: {sound=SOUND_DOORSLAM;}
    }
    EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL,GetRandomInt(70,130));
    CreateShake(2.0,1000.0,vPos);
    
    return Plugin_Stop;
}

// Full credit to Silvers
int entref_shake = INVALID_ENT_REFERENCE;
void CreateShake(float intensity, float range, float vPos[3])
{
	if( !g_bMapStarted ) return;
    
    char sTemp[8];
    
    if (!IsValidEntRef(entref_shake))
    {
    	int entity = CreateEntityByName("env_shake");
    	if( entity == -1 )
    	{
    		LogMessage("[zm] Failed to create env_shake");
    		return;
    	}
    	entref_shake = EntIndexToEntRef(entity);
    	
      	DispatchKeyValue(entref_shake, "frequency", "1.0");
      	DispatchKeyValue(entref_shake, "duration", "0.85");
      	DispatchKeyValue(entref_shake, "spawnflags", "8");
      	DispatchSpawn(entref_shake);
      	ActivateEntity(entref_shake);
      	AcceptEntityInput(entref_shake, "Enable");
      	TeleportEntity(entref_shake, vPos, NULL_VECTOR, NULL_VECTOR);
	}
	else DispatchKeyValue(entref_shake, "spawnflags", "4");
	FloatToString(intensity, sTemp, sizeof(sTemp));
	DispatchKeyValue(entref_shake, "amplitude", sTemp);
	FloatToString(range, sTemp, sizeof(sTemp));
    DispatchKeyValue(entref_shake, "radius", sTemp);
	AcceptEntityInput(entref_shake, "StartShake");
}

Action Open_Saferoom(Handle timer, bool scary = false)
{
    if (IsValidEntRef(g_iLockedDoor) && scary && zm_stage<ZM_STARTED)
    {
        EmitSoundToAll(SOUND_PANIC_ON,_,_,_,_,SNDVOL_NORMAL);
        if (g_ExplosionSprite > -1)
		{
			float vPos[3],vAng[3];
			L4D_GetEntityWorldSpaceCenter(EntRefToEntIndex(g_iLockedDoor),vPos);
			TE_SetupExplosion(vPos,g_ExplosionSprite,20.0,1,0,500,5000);
			TE_SendToAll();
			PhysicsExplode(vPos,150,1500.0,false);
			
			float dust_size = 150.0;
			float vPos_dust[3];
			vPos_dust = vPos;
			vPos_dust[2] -= dust_size;
			
			CreateShake(50.0,5000.0,vPos);
			CreateShake(50.0,5000.0,vPos);
			CreateShake(50.0,5000.0,vPos);
			
			char sound_explosion[64];
			switch (GetRandomInt(1,3))
			{
    			case 1: sound_explosion = EXPLOSION1;
    			case 2: sound_explosion = EXPLOSION2;
    			case 3: sound_explosion = EXPLOSION3;
			}
			EmitSoundToAll(sound_explosion,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
			
			char sModel[64];
        	GetEntPropString(g_iLockedDoor, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
			GetEntPropVector(g_iLockedDoor, Prop_Data, "m_vecAbsOrigin", vPos);
            GetEntPropVector(g_iLockedDoor, Prop_Send, "m_angRotation", vAng);
			
			AcceptEntityInput(g_iLockedDoor,"Kill");
			g_iLockedDoor = INVALID_ENT_REFERENCE;
			
			// Get average survivor position
			int numplayers = 0;
			float vAvg[3], vTemp[3];
			for( int i = 1; i <= MaxClients; i++ )
        	{
        	    if (!IsClientInGame(i)) continue;
        	    if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        		if (!IsPlayerAlive(i)) continue;
        		L4D_GetEntityWorldSpaceCenter(i,vTemp);
        		vAvg[0] += vTemp[0];
        		vAvg[1] += vTemp[1];
        		vAvg[2] += vTemp[2];
        		numplayers += 1;
        	}
        	
        	if (numplayers>0)
        	{
            	vAvg[0] /= numplayers;
    			vAvg[1] /= numplayers;
    			vAvg[2] /= numplayers;
    			
    			float vecResult[3];
                MakeVectorFromPoints(vPos,vAvg,vecResult);
                vecResult[2] = 0.0;
                NormalizeVector(vecResult,vecResult);
                
     			// pos[3], dir[3], float Size, float Speed
     			TE_SetupDust(vPos_dust,{0.0,0.0,1.0},dust_size,2.0);
     			TE_SendToAll();
                
                ScaleVector(vecResult,GetRandomFloat(1000.0,10000.0));
    			
    			int door = CreateEntityByName("prop_physics");
    			if (IsValidEntity(door))
    			{
                    DispatchKeyValue(door, "spawnflags", "4");
                    DispatchKeyValue(door, "model", sModel);
                    DispatchSpawn(door);
                    TeleportEntity(door,vPos,vAng,vecResult);
                }
            }
		}
    }
    start_zm_round(false); // doesnt play sound
    
    if (IsValidEntRef(entref_shake))
    {
        RemoveEdict(entref_shake);
        entref_shake = INVALID_ENT_REFERENCE;
    }
    
    return Plugin_Continue;
}

void Force_Saferoom_Scary()
{
    if (!IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED)
    {
        if (zm_stage<ZM_STARTED) start_zm_round(false);
        return;
    }
    
    float vPos[3];
    L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,vPos);
    
    float vPosOrigin[3];
    GetEntPropVector(g_iLockedDoor, Prop_Data, "m_vecAbsOrigin", vPosOrigin);
    
    if (IsValidEntRef(entref_shake)) RemoveEdict(entref_shake);
    CreateShake(0.0,0.0,vPos); //precaching of some sort...
    
    if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED)
    {
        AcceptEntityInput(g_iLockedDoor,"Close");
    }
    
    set_force_start(true);
    saferoom_lock(true);
    //if (IsValidEntRef(g_iLockedDoor) && !saferoom_interacted) AcceptEntityInput(g_iLockedDoor, "Use");
    float delay_accumulate = 2.0;
    float max_duration = 2.0;
    float min_duration = 0.2;
    int num_slams = GetRandomInt(80,130);
    for( int i = 1; i <= num_slams; i++ )
    {
        float random_duration = GetRandomFloat(min_duration,max_duration);
        CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        if (i==num_slams) CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        delay_accumulate += random_duration;
        if (max_duration<=0.04) max_duration = 0.04;
        else max_duration -= (max_duration/10.0);
        min_duration = max_duration/10.0;
    }
    CreateTimer(delay_accumulate+1.0,Open_Saferoom,true,TIMER_FLAG_NO_MAPCHANGE);
}

Action zm_start(int client, int args)
{
    if (DEBUG) LogMessage("[zm] zm_start");
    if (!g_bCvarAllow) return Plugin_Continue;
    if (!L4D_HasMapStarted() || L4D_IsInIntro()>0) return Plugin_Continue;
    if (client==zm_client || CheckCommandAccess(client,"is_a_sm_admin",ADMFLAG_GENERIC,true))
    {
        if (zm_can_start || zm_stage>=ZM_STARTED)
        {
            if (zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor) && !force_started)
            {
                int random = GetRandomInt(1,5);
                char sound[64];
                switch (random)
                {
                    case 1: {sound=SOUND_SCARY1;}
                    case 2: {sound=SOUND_SCARY2;}
                    case 3: {sound=SOUND_SCARY3;}
                    case 4: {sound=SOUND_SCARY4;}
                    case 5: {sound=SOUND_SCARY5;}
                    default: {sound=SOUND_SCARY3;}
                }
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                RequestFrame(Force_Saferoom_Scary);
            }
            else
            {
                start_zm_round(true); // plays sound
                Open_Saferoom(null);
            }
        }
        
        if (client==zm_client && !zm_can_start)
        {
            update_t_zm_activity();
            t_zm_join = t_zm_activity - g_fPrepTimeZM - 1.0;
            can_zm_start();
        }
        
    }
    return Plugin_Continue;
}

bool saferoom_interacted = false;
int hits = 0;
MRESReturn DHook_Saferoom_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bCvarAllow || zm_stage>=ZM_STARTED) return MRES_Ignored;
	
	char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (strcmp(inputName,"PlayerOpen")==0 || strcmp(inputName,"Use")==0)
	{
    	hits += 1;
    	RequestFrame(verify_saferoom_closed);
	}
	
	if (DEBUG) LogMessage("[zm] rotating door accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (hits>1 && !saferoom_interacted)
	{
    	saferoom_interacted = true;
    	if (!zm_can_start) can_zm_start();
    	if (zm_stage<ZM_STARTED && (!zm_can_start || force_started)) saferoom_lock(true);
	}
	
	return MRES_Ignored;
}

void check_saferoom()
{
   
   if (DEBUG) LogMessage("[zm] check_saferoom");
   if (L4D_IsSurvivalMode())
   {
       g_iLockedDoor = INVALID_ENT_REFERENCE;
       return;
   }
   
   if (g_iLockedDoor==INVALID_ENT_REFERENCE && L4D_HasMapStarted())
   {
        if (DEBUG) LogMessage("[zm] check_saferoom");
        g_iLockedDoor = L4D_GetCheckpointFirst();
        if (IsValidEntity(g_iLockedDoor))
        {
            g_iLockedDoor = EntIndexToEntRef(g_iLockedDoor);
            if (!saferoom_interacted && g_DHook_AcceptInput)
            {
                if (DEBUG) LogMessage("[zm] Hooking rotating door g_DHook_AcceptInput");
                hits = 0;
                DHookEntity(g_DHook_AcceptInput, true, g_iLockedDoor, INVALID_FUNCTION, DHook_Saferoom_AcceptInput);
            }
            else saferoom_interacted = true;
        }
        else
        {
            if (DEBUG) LogMessage("[zm] no saferoom, ignoring");
            g_iLockedDoor = INVALID_ENT_REFERENCE;
        }
   }
   
}

void verify_saferoom_closed()
{
    if ( !IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED || !saferoom_locked ) return;
    if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED)
    {
        AcceptEntityInput(g_iLockedDoor,"Close");
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
    }
}

void saferoom_lock(bool state)
{
    if (DEBUG) LogMessage("[zm] saferoom_lock");
    check_saferoom();
    
    if ( !IsValidEntRef(g_iLockedDoor) )
    {
        saferoom_locked = state;
        return;
    }
    
    if (state && zm_stage<ZM_STARTED && g_bLockSaferoom)
    {
        if (saferoom_interacted)
        {
            SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
            if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED) AcceptEntityInput(g_iLockedDoor,"Close");
            RequestFrame(verify_saferoom_closed);
        }
        saferoom_glow(true);
        saferoom_locked=true;
        if (DEBUG) LogMessage("[zm] Locked saferoom");
    }
    else
    {
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")&~DOOR_FLAG_IGNORE_USE);
        saferoom_glow(false);
        saferoom_locked=false;
        if (DEBUG) LogMessage("[zm] Unlocked saferoom");
        hits = 0;
    }
    
}

void saferoom_glow(bool state=true)
{
   if (DEBUG) LogMessage("[zm] saferoom_glow");
   check_saferoom();
   if (!IsValidEntRef(g_iLockedDoor) ) return;
   
   if (state && zm_stage<ZM_STARTED && g_bLockSaferoom)
   {
       SetEntProp(g_iLockedDoor, Prop_Send, "m_iGlowType", 3);
       SetEntProp(g_iLockedDoor, Prop_Send, "m_glowColorOverride", 254); //red
       SetEntProp(g_iLockedDoor, Prop_Send, "m_nGlowRangeMin", 0);
   	   SetEntProp(g_iLockedDoor, Prop_Send, "m_nGlowRange", 999999);
   }
   else
   {
       SetEntProp(g_iLockedDoor, Prop_Send, "m_glowColorOverride", 0);
       AcceptEntityInput(g_iLockedDoor, "StopGlowing");
   }
   
}

void can_zm_start()
{
   if (DEBUG) LogMessage("[zm] can_zm_start");
   if (!g_bLockSaferoom || zm_can_start) // Option 2: do not re-lock saferoom after first "round can start" announcement
   //if (!g_bLockSaferoom) // Option 1: allow saferoom to be relocked
   {
       zm_can_start = true;
       if (saferoom_locked && !force_started) saferoom_lock(false);
       return;
   }
   
   zm_can_start = false;
   if (!zm_allow_spawns) return;
   check_saferoom();
   
   if (zm_stage>=ZM_STARTED)
   {
      if (saferoom_locked) saferoom_lock(false);
      return;
   }
   
   float t_now = GetGameTime();
   if ( IsValidClientZM() && (t_now-t_last_join)>=saferoom_cooldown )
   {
      if ((t_now - t_zm_join)>=g_fPrepTimeZM) zm_can_start = true;
   }
     
   if (zm_can_start)
   {
       if (saferoom_locked && !force_started)
       {
           saferoom_lock(false);
           if (zm_stage<ZM_STARTED) EmitSoundToAll(SOUND_READY);
           if (g_bMemes && !meme_delivered)
           {
               float delay = GetRandomFloat(1.0,10.0);
               CreateTimer(delay,random_meme,TIMER_FLAG_NO_MAPCHANGE);
           }
       }
       update_EMS_HUD(true,0.0); 
   }
   else if (g_bLockSaferoom && !saferoom_locked)
   {
      saferoom_lock(true);
      update_EMS_HUD();
   }
}

// Teleport survivor to starting area - ONLY COOP
// Thanks Dragokas -- https://forums.alliedmods.net/showthread.php?t=338572
int safezone_navAreaId = -1;
//float vecPos_tp_safe[3];
//bool tp_safe_exists = false;

void tp_survivor_start(int client, bool notify = false)
{
   
   if (!IsValidClient(client) || !L4D_HasMapStarted())
   {
       if (DEBUG) LogMessage("[zm] tp_survivor_start failed early");
       return;
   }
   
   //if (safezone_navAreaId<0) tp_safe_exists = false;
   
   static float vector[3]; 
   
   if (L4D_IsSurvivalMode())
   {
       int survivor = GetRandomSurvivor(1,1);
       if (IsValidClient(survivor) && client!=survivor)
       {
           GetClientEyePosition(survivor, vector);
           vector[2] += 10.0;
           TeleportEntity(client, vector, NULL_VECTOR, NULL_VECTOR);
           if (DEBUG) LogMessage("[zm] Teleported to random survivor");
       }
       return;
   }
   
   Address temp_navArea;
   
   if (g_bNavReady && g_hStartAreaList.Length>0)
   {
       int random = 0;
       if (g_hStartAreaList.Length>1) random = GetRandomInt(0,g_hStartAreaList.Length-1);
       static PreCalcNav cell;
       g_hStartAreaList.GetArray(random, cell);
       temp_navArea = cell.navArea;
       if (navArea_validStart(temp_navArea))
       {
           safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
           if (DEBUG) LogMessage("[zm] found precomputed start area");
       }
   }
   
   if (safezone_navAreaId<0)
   {
       int g_iInfoPlayerStart = FindEntityByClassname(INVALID_ENT_REFERENCE, "info_player_start");
       if(IsValidEntity_Safe(g_iInfoPlayerStart))
       {
           GetEntPropVector(g_iInfoPlayerStart, Prop_Data, "m_vecOrigin", vector);
           
           // bools: anyz los checkground
           temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
           if (navArea_validStart(temp_navArea))
           {
               safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
               //vecPos_tp_safe = vector;
               //tp_safe_exists = true;
               if (DEBUG) LogMessage("[zm] found info_player_start");
           }
       }
       
       if (safezone_navAreaId<0)
       {
           int entity = INVALID_ENT_REFERENCE;
           while( INVALID_ENT_REFERENCE != (entity = FindEntityByClassname(entity, "info_survivor_position")) )
   	       {
           	    if(IsValidEntity_Safe(entity)) 
           	    {
               	    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector);
               	    temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
                    if (navArea_validStart(temp_navArea))
                    {
                        safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                        //vecPos_tp_safe = vector;
                        //tp_safe_exists = true;
                        if (DEBUG) LogMessage("[zm] found info_survivor_position");
                        break;
                    }
                }
   	       }
       }
       
   
       if (safezone_navAreaId<0)
       {
           check_saferoom();
           if (IsValidEntRef(g_iLockedDoor))
           {
               GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecOrigin", vector);
               temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
               if (navArea_validStart(temp_navArea))
               {
                   safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                   if (DEBUG) LogMessage("[zm] found saferoom");
               }
           }
       }
       
       if (safezone_navAreaId<0)
       {
           for (int i = 1; i <= MaxClients; i++)
       	   {
       		 if (!IsClientInGame(i)) continue;
       	
       		 GetEntPropVector(i, Prop_Send, "m_vecOrigin", vector);
             temp_navArea = L4D_GetNearestNavArea(vector,500.0,true,false,true,TEAM_SURVIVOR);
             if (navArea_validStart(temp_navArea))
             {
                safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
                if (DEBUG) LogMessage("[zm] found player in start area");
                break;
             }
       		 
       	    }
       }
       
   }
   
   // Find navarea of player start and select random position on navmesh to teleport
   if (safezone_navAreaId>0)
   {
       float randomPos[3];
       Address safezone_navArea = L4D_GetNavAreaByID(safezone_navAreaId);
       if (safezone_navArea && navArea_validStart(safezone_navArea))
       {
           L4D_FindRandomSpot(safezone_navArea,randomPos);
           if (IsObstructed(randomPos,client)) L4D_GetNavAreaCenter(safezone_navArea,randomPos);
           if (IsObstructed(randomPos,client)) L4D_FindRandomSpot(safezone_navArea,randomPos);
           if (IsObstructed(randomPos,client))
           {
               Grid_TryRescueObstruction(-1,randomPos,client);
           }
           //TeleportEntity(client, randomPos, NULL_VECTOR, NULL_VECTOR);
           SetAbsOrigin(client,randomPos);
           if (DEBUG) LogMessage("[zm] Teleported %d to safezone", client);
           
            if (notify && !IsFakeClient(client))
            {
                if (!IsValidClientZM()) PrintHintText(client, "%t", "No ZM notify");
                else PrintHintText(client, "%t", "Cannot start notify");
            }
           
       }
       else safezone_navAreaId = -1;
   }
   
}

Action Timer_StartPrecomputeNav(Handle timer)
{
	if (DEBUG) LogMessage("[zm] Starting navmesh precomputation...");
	float startTime = GetEngineTime(); // for profiling
    g_bNavReady = false;

    Address temp_navArea;
    static float vector_start[3];
    bool start_known = false;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "info_player_start")) != -1)
    {
        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector_start);
        temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
        start_known = navArea_validStart(temp_navArea);
        if (start_known) break;
    }
    if (!start_known)
    {
        entity = -1;
        while ((entity = FindEntityByClassname(entity, "info_survivor_position")) != -1)
	    {
            GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector_start);
            temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
            start_known = navArea_validStart(temp_navArea);
            if (start_known) break;
	   }
    }
    if (!start_known)
    {
        //LogMessage("Could not find info_player_start or info_survivor_position");
        // scan all navAreas
        //return Plugin_Stop;
    }
    if (!start_known)
    {
        LogMessage("Could not find start area");
        return Plugin_Stop;
    }

    Address navArea_start = temp_navArea;

    ArrayList explored = new ArrayList(); // navAreas already checked
    explored.Push(navArea_start);
    ArrayList pending = new ArrayList(); // navAreas that haven't had their adjacent areas checked
    pending.Push(navArea_start);
    ArrayList adjAreas = new ArrayList(); // temporary adjacent areas

    static PreCalcNav cell;
    static float pos[3], vSize[3];
    L4D_GetNavAreaCenter(navArea_start,pos);
    cell.position = pos;
    cell.navArea = navArea_start;
    g_hStartAreaList.PushArray(cell);
    int total_stored_start = 1;
    while (pending.Length>0)
    {
        Address navArea_curr = pending.Get(0);
        for (int dir = 0; dir < 5; dir++)
        {
            adjAreas.Clear();
            L4D_NavArea_GetAdjacentAreas(navArea_curr, dir, adjAreas);
            for (int i = 0; i < adjAreas.Length; i++)
            {
                temp_navArea = adjAreas.Get(i);
                if (temp_navArea == Address_Null) continue;
                if (explored.FindValue(temp_navArea)!=-1) continue;
                explored.Push(temp_navArea);
                if (!navArea_validStart(temp_navArea)) continue;
                pending.Push(temp_navArea);
                L4D_GetNavAreaSize(temp_navArea, vSize);
                if (vSize[0]<=50.0 && vSize[1]<=50.0) continue;
                L4D_GetNavAreaCenter(temp_navArea,pos);
                if (GetVectorDistance(vector_start,pos)>400.0) continue;
                if (IsObstructed(pos)) continue;
                cell.position = pos;
                cell.navArea = temp_navArea;
                g_hStartAreaList.PushArray(cell);
                total_stored_start += 1;
            }
        }
        pending.Erase(0);
    }
    delete explored;
    delete pending;
    delete adjAreas;
	g_bNavReady = true;
	float duration = GetEngineTime() - startTime;
	LogMessage("[zm] Found %d start area navmeshes, %f seconds", total_stored_start, duration);
	return Plugin_Stop;
}

void set_force_start(bool state = true)
{
    if (state && !force_started)
    {
        force_started = true;
        AddNormalSoundHook(SwapSound);
    }
    else if (!state && force_started)
    {
        force_started = false;
        RemoveNormalSoundHook(SwapSound);
    }
}

Action SwapSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
                    	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
                    	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (force_started && zm_stage<ZM_STARTED)
    {
        if (StrContains(sample,"survivor",false)!=-1 && StrContains(sample,"voice",false)!=-1 && StrContains(sample,"world",false)!=-1)
        {
            if (DEBUG) LogMessage("[zm] Muting survivor");
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

// Check if navArea is a valid survivor starting area
stock bool navArea_validStart(Address navArea)
{
    if (navArea == Address_Null) return false;
    static float pos[3];
    L4D_GetNavAreaCenter(navArea,pos);
    if (L4D_IsPositionInFirstCheckpoint(pos)) return true;
    
    int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
    if ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_FINALE) ) return false;
    if ( !( (navSpawnAttrs & NAV_SPAWN_PLAYER_START) || (navSpawnAttrs & NAV_SPAWN_CHECKPOINT) ) ) return false;
    float flow = L4D_GetFlowFromPoint(pos);
    if (flow<=(-9000.0)) return false;
    float max_flow = L4D2Direct_GetMapMaxFlowDistance();
    if (flow>=(max_flow*0.1)) return false;
    return true;
}

// taking shitty navmeshes into account
bool client_in_start_area(int client)
{
    float pos[3];
    L4D_GetEntityWorldSpaceCenter(client,pos);
    // bools: anyz los checkground
    Address temp_navArea = L4D_GetNearestNavArea(pos,500.0,true,true,true,TEAM_SURVIVOR);
    if (navArea_validStart(temp_navArea)) return true;
    if (IsValidEntRef(g_iLockedDoor))
    {
        float safepos[3];
        L4D_GetEntityWorldSpaceCenter(g_iLockedDoor,safepos);
        if (GetVectorDistance(pos,safepos)<=100.0) return true;
    }
    return false;
}