///////////////////////////////////////
#if defined _zm_unitmanager_included
 #endinput
#endif
#define _zm_unitmanager_included
///////////////////////////////////////

// TANK BULLSHIT

// Tank model consistency
void NextFrame_SetModel(int entref)
{
    if (!IsValidEntRef(entref)) return;
    if (model_pending[0]==0) return;
    SetEntityModel(entref, model_pending);
    pending_tank = false;
}

Action Timer_Clear_targetname_pending(Handle timer = null)
{
    if (pending_tank)
    {
        targetName_pending = "";
        pending_tank = false;
        model_pending = "";
        LogMessage("[zm] unexpectedly cleared targetName_pending. Report to mod authors.");
    }
    return Plugin_Stop;
}

float t_stutter = 0.0;
bool verify_stutter_fixed()
{
    if (!IsValidClientZM()) return true;
    if (IsClientTimingOut(zm_client))
    {
        float latency = GetClientAvgLatency(zm_client, NetFlow_Both) * 2.0;
        t_stutter = GetEngineTime() + latency;
        return false;
    }
    if (IsPlayerAlive(zm_client))
    {
        return true;
    }
    if ( GetEngineTime()>(t_stutter+5.0) )
    {
        LogMessage("[zm] Tank stutter fix timed out, report this to mod authors");
        EmitSoundToAll(SOUND_BUG);
        return true;
    }
    return false;
}

void NextFrame_Check_Stutter(int stored_roundcount)
{
    if (DEBUG) LogMessage("[zm] NextFrame_Check_Stutter");
    if (stored_roundcount!=roundcount) return;
    if (verify_stutter_fixed() && GetEngineTime()>t_stutter)
    {
        RequestFrame(ZM_FixCamera,false);
        CreateTimer(1.0,stop_tankmusic,TIMER_FLAG_NO_MAPCHANGE);
    }
    else RequestFrame(NextFrame_Check_Stutter,stored_roundcount);
}

void ZM_FixTankStutter(bool freeze = true)
{
    if (!IsValidClientZM()) return;
    if (GetClientTeam(zm_client)==TEAM_SURVIVOR && IsPlayerAlive(zm_client)) return;

    recordpos = false;
    
    SetEntityMoveType(zm_client, MOVETYPE_NONE);
    L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
    L4D_BecomeGhost(zm_client);
    L4D_SetClass(zm_client,ZOMBIECLASS_BOOMER);
    TeleportEntity(zm_client, {0.0,0.0,0.0}, NULL_VECTOR, NULL_VECTOR);	
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", ZOMBIECLASS_BOOMER);
    L4D_MaterializeFromGhost(zm_client);
    L4D_RespawnPlayer(zm_client);
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", ZOMBIECLASS_BOOMER);
    L4D_SetClass(zm_client,ZOMBIECLASS_BOOMER);
    TeleportEntity(zm_client, {0.0,0.0,0.0}, NULL_VECTOR, NULL_VECTOR);	
    SetEntityMoveType(zm_client, MOVETYPE_NONE);
    SetEntProp(zm_client,Prop_Data,"m_iHealth",0);
    
    float latency = GetClientAvgLatency(zm_client, NetFlow_Both) * 2.0;
    t_stutter = GetEngineTime() + latency;
    
    if (DEBUG) LogMessage("[zm] ZM_FixTankStutter, latency %f", latency);
    RequestFrame(NextFrame_Check_Stutter,roundcount);
}

///////////////////////////////////////

stock int get_occupied_units(int max, int available, int live)
{
    int occupied = max-available;
    if (occupied<live) occupied = live;
    return occupied;
}

void freeze_player(int client, bool state = true, int team = TEAM_SURVIVOR)
{
    if(IsValidClient(client) && client!=zm_client && GetClientTeam(client)==team && IsPlayerAlive(client))
    {   
        
        int zClass = -1;
        if (team==TEAM_INFECTED) zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        
        if (state)
        {
            if (team == TEAM_SURVIVOR) SetEntProp(client, Prop_Data, "m_takedamage", 0);
            else if (IsFakeClient(client))
            {
                SetEntPropEnt(client, Prop_Send, "m_lookatPlayer",-1);
                SetEntProp(client, Prop_Send, "m_hasVisibleThreats",0);
                if (zClass==ZOMBIECLASS_TANK)
                {
                    //if (hTankEnterStasis) SDKCall(hTankEnterStasis,client);
                    SetEntProp(client, Prop_Send, "m_zombieState",0);
                }
            }
    		//SetEntityMoveType(client, MOVETYPE_NONE);
    		SetEntProp(client, Prop_Send, "m_fFlags", GetEntProp(client, Prop_Send, "m_fFlags")|FL_FROZEN);
    		if (team == TEAM_SURVIVOR) TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    		
		}
		else
		{
    		if (GetEntityMoveType(client)==MOVETYPE_NONE) SetEntityMoveType(client, MOVETYPE_WALK);
    		SetEntProp(client, Prop_Send, "m_fFlags", (GetEntProp(client, Prop_Send, "m_fFlags")&~FL_FROZEN));
            if (team == TEAM_SURVIVOR) SetEntProp(client,Prop_Data,"m_takedamage",2);
            else if (IsFakeClient(client))
            {
                if (zClass==ZOMBIECLASS_TANK)
                {
                    //if (hTankLeaveStasis) SDKCall(hTankLeaveStasis,client);
                    SetEntProp(client, Prop_Send, "m_hasVisibleThreats",1);
                    SetEntPropEnt(client, Prop_Send, "m_lookatPlayer",GetRandomSurvivor(1,1));
                    SetEntProp(client, Prop_Send, "m_zombieState",1);
                }
            }
		}
    }
}

// Call this if you want to freeze silently (for periodic refreezing)
void freeze_team(bool state = true, int team = TEAM_SURVIVOR)
{
    if (DEBUG) LogMessage("[zm] freeze_team");
    if (team==TEAM_INFECTED)
    {
        if (zm_stage<ZM_STARTED && !state) return;
        if (g_bAllowFreeze && zm_stage==ZM_STARTED && state!=ZM_specials_frozen) return;
    }
    for (int i=1;i<=MaxClients;i++)
    {
        freeze_player(i,state,team);
    }
    if (DEBUG)
    {
        if (state) LogMessage("[zm] Froze team %d", team);
        else LogMessage("[zm] Unfroze team %d", team);
    }
    if (team==TEAM_INFECTED) specials_frozen = state;
    else if (team==TEAM_SURVIVOR && g_iLockedDoor==INVALID_ENT_REFERENCE) saferoom_locked=state;
}

stock void transfer_SI_properties(int entity_new, char[] modelname, float vOrigin[3], float vAngles[3], float vVelocity[3], int health, int maxhealth, int fFlags, float timestamp_cooldown, char targetname[64] = "")
{
   if (!IsValidClient(entity_new)) return;
   int zClass = GetEntProp(entity_new, Prop_Send, "m_zombieClass");
   if (zClass!=ZOMBIECLASS_BOOMER) SetEntityModel(entity_new, modelname); // gender swapping boomers because that's hilarious
   
   TeleportEntity(entity_new,vOrigin,vAngles,vVelocity);
   SetEntProp(entity_new,Prop_Data,"m_iHealth",health);
   SetEntProp(entity_new,Prop_Data,"m_iMaxHealth",maxhealth);
   float cooldown_remaining = timestamp_cooldown - GetGameTime();
   if (cooldown_remaining<=0.0) cooldown_remaining = 0.0;
   else
   {
       // Prevent 3600 seconds cooldown bug
       float default_cooldown;
       switch(zClass)
       {
           case ZOMBIECLASS_SMOKER: default_cooldown = FindConVar("tongue_hit_delay").FloatValue;
           case ZOMBIECLASS_BOOMER: default_cooldown = FindConVar("z_vomit_interval").FloatValue;
           case ZOMBIECLASS_SPITTER: default_cooldown = FindConVar("z_spit_interval").FloatValue;
           case ZOMBIECLASS_JOCKEY: default_cooldown = FindConVar("z_leap_interval_post_ride").FloatValue;
           case ZOMBIECLASS_CHARGER: default_cooldown = FindConVar("z_charge_interval").FloatValue;
           case ZOMBIECLASS_TANK: default_cooldown = FindConVar("z_tank_throw_interval").FloatValue;
           default: default_cooldown = 10.0;
       }
       
       if (cooldown_remaining>default_cooldown) cooldown_remaining = default_cooldown;
       
   }
   
   L4D2_SetCustomAbilityCooldown(entity_new,cooldown_remaining);
   //SetEntProp(entity_new, Prop_Data, "m_fFlags", fFlags); // causes charger to be stuck forever
   if (fFlags & FL_ONFIRE) IgniteEntity(entity_new, IGNITE_TIME);
   if (fFlags & FL_DUCKING)
   {
       SetEntityFlags(entity_new, GetEntityFlags(entity_new) | FL_DUCKING);
   }
   
   TrimString(targetname);
   if (targetname[0]!=0)
      DispatchKeyValue(entity_new, "targetname", targetname); 
}

void reset_available_zombies()
{
  available_SI = max_SI;
  available_zombie_arr = max_zombie_arr;
}

bool is_zombie_available_cooldown(int zClass)
{
    if (zClass>ZOMBIECLASS_TANK) return false;
    switch (zClass)
    {
        case ZOMBIECLASS_COMMON: { if (available_zombie_arr[zClass]>0) return true; }
        case ZOMBIECLASS_WITCH: { if (available_zombie_arr[zClass]>0) return true; }
        default: { if (available_SI>0 && available_zombie_arr[zClass]>0) return true; }
    }
    return false;
}

// Cooldowns for specials and witches
float get_class_cooldown(int ZOMBIECLASS)
{
    switch (ZOMBIECLASS)
    {
        case ZOMBIECLASS_WITCH: return g_fWitchCooldown;
        case ZOMBIECLASS_TANK: return g_fTankCooldown;
        default: return g_fSpecialCooldown;
    }
}

void sanity_check_available(int zClass, float t_now = -1.0)
{
    if (t_now<0.0) t_now = GetEngineTime();
    bool apply_cooldown = false;
    if (live_zombie_arr[zClass]>0) apply_cooldown = true;
    else if ( available_zombie_arr[zClass]<max_zombie_arr[zClass] &&
              t_now>(timestamp_available_arr[zClass]+0.15) ) //timers can jitter
    {
        char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        LogMessage("[zm] unexpected sanity_check %s fallthrough, report to mod authors", zClassName);
        add_available_zombie(zClass);
        apply_cooldown = true;
    }
    if (apply_cooldown) timestamp_available_arr[zClass] = t_now + get_class_cooldown(zClass);
}

void create_timer_add_available_zombie(float delay,int zClass, int round, int count=1)
{
    // sourcemod timers cannot be smaller than 0.1
    if (delay<0.1)
    {
        add_available_zombie(zClass);
        return;
    }
    char zClassName[32]; 
    get_zombieclass_name(zClass,zClassName);
    if (DEBUG) LogMessage("[zm] create_timer_add_available_zombie %d %s, delay: %f", count, zClassName, delay);
    timestamp_available_arr[zClass] = GetEngineTime() + delay;
    DataPack pack;
    CreateDataTimer(delay, timer_add_available_zombie, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(zClass);
    pack.WriteCell(round);
    pack.WriteCell(count);
}

Action timer_add_available_zombie(Handle timer, DataPack pack)
{
    int zClass,round,count;
    pack.Reset();
    zClass = pack.ReadCell();
    round = pack.ReadCell();
    count = pack.ReadCell();
    if (round!=roundcount) return Plugin_Continue;
    add_available_zombie(zClass,count);
    return Plugin_Stop;
}

void add_available_zombie(int zClass, int add=1, bool draw = true)
{
    if (zClass>ZOMBIECLASS_TANK) return;
    
    if (zm_stage>=ZM_PREP)
    {
        char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        if (DEBUG) LogMessage("[zm] add_available_zombie %d %s", add, zClassName);
    }
    
    if (add<0) timestamp_available_arr[zClass] = GetEngineTime()+get_class_cooldown(zClass);
    
    available_zombie_arr[zClass] += add;
    if (available_zombie_arr[zClass]>max_zombie_arr[zClass]) available_zombie_arr[zClass] = max_zombie_arr[zClass];
    else if (available_zombie_arr[zClass]<0) available_zombie_arr[zClass] = 0;
     
    // Will this operation change available Specials?
    int add_SI;
    switch (zClass)
    {
        case ZOMBIECLASS_COMMON: add_SI=0;
        case ZOMBIECLASS_WITCH: add_SI=0;
        default: add_SI = add;
    }
    
    if (add_SI!=0)
    {
        available_SI += add_SI;
        if (available_SI>max_SI) available_SI = max_SI;
        else if (available_SI<0) available_SI = 0;
        if (draw && IsValidClientZM() && zm_stage>=ZM_PREP && zm_stage<ZM_END)
        {
            if (zClass == ZOMBIECLASS_TANK) create_boss_menu();
            else create_special_menu();
        }
    }
    if (draw && IsValidClientZM() && zm_stage>=ZM_PREP && zm_stage<ZM_END) update_EMS_HUD();
}

void reset_live_zombie_arr(bool common=true, bool witch=true, bool special=true)
{
    int length = sizeof(live_zombie_arr);
    for(int i = 0; i < length; i++)
	{
		switch (i)
		{
    		case ZOMBIECLASS_COMMON: { if (common) live_zombie_arr[i] = 0; }
    		case ZOMBIECLASS_WITCH: { if (witch) live_zombie_arr[i] = 0; }
    		default: { if (special) live_zombie_arr[i] = 0; }
		}
	}
	
}


int get_max_unique_SI_override()
{
    if (g_iMaxUniqueSI<0) return RoundToCeil(max_SI/2.0);
    if (g_iMaxUniqueSI>max_SI) return max_SI;
    return g_iMaxUniqueSI;
}

int change_special_max(int ZOMBIECLASS, int new_max, bool draw = true)
{
    if (ZOMBIECLASS==ZOMBIECLASS_TANK && g_hNoTanks.BoolValue) new_max = 0;
    else if (new_max>max_SI) new_max = max_SI;
    if (max_zombie_arr[ZOMBIECLASS]==new_max) return 0;
    int d = new_max - max_zombie_arr[ZOMBIECLASS];
    max_zombie_arr[ZOMBIECLASS] = new_max;
    add_available_zombie(ZOMBIECLASS,d,draw);
    return 1;
}


Action OnTakeDamageWitch(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (damage>32.0)
    {
        char class[32];
        GetEntityClassname(inflictor, class, sizeof(class));
        switch (class[0])
        {
            case 'p':
            {
                 if (StrContains(class,"prop_minigun",false)!=-1)
                 {
                     damage = 32.0;
                     return Plugin_Changed;
                 }
            }
        }
    }
    request_update_glow(victim);
    return Plugin_Continue;
}

stock void request_crouch(int entref)
{
    if (!IsValidEntRef(entref)) return;
    SetEntProp(entref, Prop_Send, "m_bDucked", 1);
    SetEntProp(entref, Prop_Send, "m_fFlags", GetEntProp(entref, Prop_Send, "m_fFlags") | FL_DUCKING);
}

void reset_time_of_day()
{
    SetConVarInt(FindConVar("sv_force_time_of_day"),-1);
}

bool can_discount_tank()
{
    if (!g_bDiscountTank) return false;
    if (max_zombie_arr[ZOMBIECLASS_TANK]<=0 || costs_SI[ZOMBIECLASS_TANK]<0) return false;
    if (zm_stage!=ZM_STARTED) return false;
    if (first_tank_stage>0) return false;
    if ( ZM_finale_announced || L4D_IsSurvivalMode() ) return false;
    if (L4D_IsMissionFinalMap() && !IsValidEntity(lastdoor)) return false;
    int ProhibitBosses = L4D2_GetScriptValueInt("ProhibitBosses", 0);
    if (ProhibitBosses>0) return false;
    int DisallowThreatType = L4D2_GetScriptValueInt("DisallowThreatType", 0);
    if (DisallowThreatType==ZOMBIECLASS_TANK) return false;
    return true;  
}

void update_dynamic_tank()
{
    int new_cost = g_hCostTank.IntValue;
    if (can_discount_tank())
    {
        int target = L4D_GetHighestFlowSurvivor();
        float fraction = get_survivor_flow_fraction(target);
        if (fraction>=0.0)
        {
            // For >=60.0% flow, give 50% discount.
            if (fraction>0.6)
            {
                fraction = 0.6;
                if (!zm_discount_notify)
                {
                    zm_discount_notify = true;
                    update_hint("%T", "Max tank discount", zm_client);
                    if (IsValidClientZM())
                    {
                        PrintHintText(zm_client, "%t", "Max tank discount"); 
                        EmitSoundToClient(zm_client,SOUND_REWARD);
                    }
                }
            }
            new_cost = RoundToCeil( (1.0-0.5*fraction/0.6)*g_hCostTank.IntValue);
            
            // Prevent Tank from getting more expensive if Survivor is walking back.
            if (new_cost>costs_SI[ZOMBIECLASS_TANK])
                new_cost = costs_SI[ZOMBIECLASS_TANK];
        }
        
    }
    
    if (new_cost!=costs_SI[ZOMBIECLASS_TANK])
    {
        costs_SI[ZOMBIECLASS_TANK] = new_cost;
        create_boss_menu();
    }
}

Action stop_tankmusic(Handle timer=null)
{
    if (live_zombie_arr[ZOMBIECLASS_TANK]>0) return Plugin_Stop;
    for (int i=1;i<=MaxClients;i++)
	{
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
 		L4D_StopMusic(i, "Event.Tank");
 		L4D_StopMusic(i, "Event.TankMidpoint");
 		L4D_StopMusic(i, "Event.TankMidpoint_Metal");
 		L4D_StopMusic(i, "Event.TankBrothers");
 		L4D_StopMusic(i, "C2M5.RidinTank1");
 		L4D_StopMusic(i, "C2M5.RidinTank2");
 		L4D_StopMusic(i, "C2M5.BadManTank1");
 		L4D_StopMusic(i, "C2M5.BadManTank2");
    }
    return Plugin_Stop;
}