///////////////////////////////////////
#if defined _zm_glow_included
 #endinput
#endif
#define _zm_glow_included
///////////////////////////////////////

void remove_all_ZM_glows()
{
    if (DEBUG) LogMessage("[zm] remove_all_ZM_glows");
    for(int i = 0; i < sizeof(g_iGlowList); i++)
	{
		if (g_iGlowList[i]==INVALID_ENT_REFERENCE) continue;
		remove_ZM_glow(i);
	}
}

void NextFrame_Remove(int entref)
{
    if (!IsValidEntRef(entref)) return;
    RemoveEntity(entref);
}

// remove glow of parent entity
void remove_ZM_glow(int entity)
{
    if (DEBUG) LogMessage("[zm] remove_ZM_glow %d", entity);
    if (!IsValidEntity(entity))
    {
        if (DEBUG) LogMessage("[zm] remove_ZM_glow %d skipped", entity);
        if (entity>=0 && entity<=MAXENTITIES) g_iGlowList[entity]=INVALID_ENT_REFERENCE;
        return; 
    }
    int entref_glow = g_iGlowList[entity];
    hp_timers[entity] = INVALID_HANDLE;
    if ( IsValidEntRef(entref_glow) && HasEntProp(entref_glow, Prop_Send, "m_CollisionGroup") )
    {
       char class[32];
       GetEntityClassname(entref_glow, class, sizeof(class));
       if (strcmp(class,"prop_dynamic_ornament")==0)
       {
   	       AcceptEntityInput(entref_glow, "StopGlowing");
   	       NextFrame_Remove(entref_glow);
   	       if (DEBUG) LogMessage("[zm] remove_ZM_glow %d killed prop_dynamic_ornament %d", entity, entref_glow);
   	       return;
       }
    }
    g_iGlowList[entity] = INVALID_ENT_REFERENCE;
    if (DEBUG) LogMessage("[zm] remove_ZM_glow %d unexpectedly did nothing", entity);
}

int arr_hp_vec[101][3];
void precache_survivor_hp()
{
    int color[3];
    for(int i = 0; i < sizeof(arr_hp_vec); i++)
    {
          GetSurvivorHealthColor(i,color,false,false);
          arr_hp_vec[i][0] = color[0];
          arr_hp_vec[i][1] = color[1];
          arr_hp_vec[i][2] = color[2];
    }   
}

void GetSurvivorHealthColor_pre(int hp, int color[3], bool rescue=false, bool critical=false)
{
    if (rescue || critical)
    {
        GetSurvivorHealthColor(hp,color,rescue,critical);
        return;
    }
    if (hp<0) hp=0;
    else if (hp>100) hp=100;
    color[0] = arr_hp_vec[hp][0];
    color[1] = arr_hp_vec[hp][1];
    color[2] = arr_hp_vec[hp][2];
}

bool survivor_dominated(int client)
{
    return L4D_IsPlayerPinned(client) || L4D2_GetQueuedPummelAttacker(client)>0;//L4D2_GetSpecialInfectedDominatingMe(client)>0;
}

Action Check_Dominated(Handle timer, int victim)
{
    if (!dominated[victim]) return Plugin_Stop;
    if (!IsValidClient(victim) || !IsPlayerAlive(victim) || !survivor_dominated(victim))
    {
        if (DEBUG) LogMessage("[zm] Dominated end %d", victim);
        request_update_glow(victim,true,0.0); // updates dominated[victim]
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

// Infected unit glow -- white
Action CreateZMGlow_white(Handle timer, int targetRef)
{
    if (!IsValidEntRef(targetRef)) return Plugin_Stop;
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target);
    return Plugin_Stop;
}

// Saferoom door glow -- red
Action CreateZMGlow_red(Handle timer, int targetRef)
{
    if (!IsValidEntRef(targetRef)) return Plugin_Stop;
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target,true);
    return Plugin_Stop;
}

// Handled: invisible
// Continue: visible
Action OnTransmitZM(int entity, int client)
{
   	int parent = GetEntPropEnt(entity,Prop_Data,"m_pParent");
   	bool valid = IsValidEntity(parent);
   	if (valid && IsValidClient(parent) && !IsPlayerAlive(parent)) valid = false;
   	if (!valid || zm_client<0)
   	{
       	if (DEBUG) LogMessage("[zm] OnTransmitZM killing glow %d, parent %d", entity, parent); 
       	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
       	AcceptEntityInput(entity, "StopGlowing");
        NextFrame_Remove(EntIndexToEntRef(entity));
   	}
   	if (client==zm_client) return Plugin_Continue;
    return Plugin_Handled;
}

Action OnTransmitZM_FlowSurvivor(int entity, int client)
{
   	int parent = GetEntPropEnt(entity,Prop_Data,"m_pParent");
   	bool valid = IsValidClient(parent) && IsPlayerAlive(parent) && zm_menu_state!=ZM_MENU_CLOSED;
   	if (valid) valid = get_spawner_target_survivor()==parent;
   	if (!valid || zm_client<0)
   	{
       	if (DEBUG) LogMessage("[zm] OnTransmitZM_FlowSurvivor killing glow %d, parent %d", entity, parent); 
       	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
       	AcceptEntityInput(entity, "StopGlowing");
        NextFrame_Remove(EntIndexToEntRef(entity));
   	}
   	if (client==zm_client) return Plugin_Continue;
    return Plugin_Handled;
}

//void NextFrame_ActivateGlow(int entref)
//{
//    if (entref==INVALID_ENT_REFERENCE) return;
//    //SetEntProp(entref, Prop_Send, "m_nGlowRange", 999999);
//    AcceptEntityInput(entref, "StartGlowing");
//}

//Action Timer_ActivateGlow(int entref)
//{
//    if (!IsValidEntRef(entref)) return Plugin_Stop;
//    AcceptEntityInput(entref, "StartGlowing");
//    return Plugin_Stop;
//}

// Red: last saferoom door
// Flow: mark survivor blue
// Otherwise white zombie glow
void CreateZMGlow(int target, bool red = false, bool flow = false)
{
	if (!IsValidClientZM()) return;
	if (!IsValidEntity(target) || target==zm_client) return;
	
	if (!red && HasEntProp(target,Prop_Data,"m_iHealth"))
	{
    	if (GetEntProp(target,Prop_Data,"m_iHealth")<=0) return;
	}
	
	int glowref = g_iGlowList[target];
	if ( glowref!=INVALID_ENT_REFERENCE && IsValidEntity(glowref) )
	{
	    int parent = GetEntPropEnt(glowref,Prop_Data,"m_pParent");
	    if (parent==target) return;
       	AcceptEntityInput(glowref, "StopGlowing");
        NextFrame_Remove(glowref);
	}
	
	if (DEBUG) LogMessage("[zm] CreateZMGlow");
	
	int glow = CreateEntityByName("prop_dynamic_ornament");
	if (!IsEntitySafe(glow)) return;
	
	int eFlags = GetEdictFlags(target);
	if ((eFlags & FL_EDICT_ALWAYS)<=0) SetEdictFlags(target, eFlags | FL_EDICT_ALWAYS); //
	
	char sModelName[64];
	GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
	
	SetEntityModel(glow, sModelName);
	DispatchSpawn(glow);
	SetEntProp(glow, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRange", 999999);
	//RequestFrame(NextFrame_ActivateGlow,EntIndexToEntRef(glow));
	SetEntProp(glow, Prop_Send, "m_iGlowType", 3);
	if (red) SetEntProp(glow, Prop_Send, "m_glowColorOverride", 254);
	else if (flow)
	{
    	SetEntProp(glow, Prop_Send, "m_glowColorOverride", RGB_FLOW);
    	if (L4D_IsPlayerOnThirdStrike(target)) SetEntProp(glow, Prop_Send, "m_bFlashing", 1);
	}
	else SetEntProp(glow, Prop_Send, "m_glowColorOverride", RGB_ZM);
	AcceptEntityInput(glow, "StartGlowing");
	SetEntityRenderMode(glow, RENDER_TRANSCOLOR);
	SetEntityRenderColor(glow, 0, 0, 0, 0);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", target);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetAttached", target);
    g_iGlowList[target] = EntIndexToEntRef(glow);
	if (flow) SDKHook(glow, SDKHook_SetTransmit, OnTransmitZM_FlowSurvivor);
	else SDKHook(glow, SDKHook_SetTransmit, OnTransmitZM);
	DispatchKeyValue(glow, "targetname", "zm_glow");
	if (!red && !flow)
	{
    	// clients will hook to player_hurt; witches need this hook.
    	if (!IsValidClient(target)) SDKHook(target, SDKHook_OnTakeDamage, OnTakeDamageWitch);
        request_update_glow(target,true,0.0);
	}
	if (DEBUG) LogMessage("[zm] CreateZMGlow %d %d %d", target, glow, g_iGlowList[target]);
	//CreateTimer(0.1,Timer_ActivateGlow,g_iGlowList[target],TIMER_FLAG_NO_MAPCHANGE);
}

void request_update_glow(int i, bool force = false, float delay=0.1)
{
    if (!IsValidEntity(i)) return;
    if (!force && hp_timers[i]!=null) return;
    if (delay<0.1) update_glow(i);
    else hp_timers[i] = CreateTimer(delay,Timer_update_glow,EntIndexToEntRef(i));
}

Action Timer_update_glow(Handle timer, int entref)
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    update_glow(EntRefToEntIndex(entref));
    return Plugin_Stop;
}

void update_glow(int i)
{
    if (DEBUG) LogMessage("[zm] update_glow %d", i);
    if (!IsValidEdict(i)) return;
    hp_timers[i]=null;
    if (!g_bCvarAllow) return;
    if (!IsValidEntity(i) || zm_stage>=ZM_END) return;
    if (IsValidClient(i))
    {
        switch (GetClientTeam(i))
        {
            case TEAM_INFECTED: update_zm_glow(i);
            case TEAM_SURVIVOR: UpdateSurvivorGlow(i);
            default:
            {
                L4D2_SetPlayerSurvivorGlowState(i,false);
                L4D2_RemoveEntityGlow(i);
            }
        }
        
    }
    else
    {
        char class[16];
        GetEntityClassname(i,class,sizeof(class));
        if (strcmp(class,"witch")==0) update_zm_glow(i);
    }
}

void update_zm_glow(int parent)
{
   	if (DEBUG) LogMessage("[zm] update_zm_glow %d", parent);
   	int health = GetEntProp(parent,Prop_Data,"m_iHealth");
   	if (IsValidClient(parent))
   	{
       	if (!IsPlayerAlive(parent) || L4D_IsPlayerGhost(parent))
       	{
           	health=0;
           	L4D2_RemoveEntityGlow(parent);
           	L4D2_SetPlayerSurvivorGlowState(parent,false);
       	}
       	else if (L4D_IsPlayerIncapacitated(parent)) health=1;
   	}
   	
    int entref_glow = g_iGlowList[parent];
    if (!IsValidEntRef(entref_glow)) return;
	
	if (health<=0 || parent==zm_client || !IsValidClientZM())
	{
    	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
       	AcceptEntityInput(entref_glow, "StopGlowing");
        NextFrame_Remove(entref_glow);
    	
	}
	else
	{
	    int color[3];
	    bool vomited = IsValidClient(parent) && is_player_vomited(parent);

       	if (health<=1) color[0] = 255;
        else
        {
            int max_health = GetEntProp(parent,Prop_Data,"m_iMaxHealth");
            if (health>max_health)
            {
                max_health = health;
                SetEntProp(parent,Prop_Data,"m_iMaxHealth",max_health);
            }
            float fraction = 1.0*health/max_health;
            if (fraction<0.0) fraction = 0.0;
            if (vomited)
            {
               	color[0] = 144+RoundFloat(fraction*111.0);
            	color[1] = 19+RoundFloat(fraction*236.0);
            	color[2] = 255;
        	}
        	else
        	{
   	            int RGB_frac = RoundFloat(255*fraction);
   	            color[0] = 255;
               	color[1] = RGB_frac;
               	color[2] = RGB_frac;
        	}
    	}
	    
       	char targetName[64];
        GetEntPropString(parent, Prop_Data, "m_iName", targetName, sizeof(targetName));
       	bool flashing = false;
       	if (EntIndexToEntRef(parent)==entref_control || strcmp(targetName,"zm_unit_spotted")==0 ) flashing = true;
       	L4D2_SetEntityGlow(entref_glow,L4D2Glow_Constant,999999,0,color,flashing);
       	if (active_looktarget && entref_control==EntIndexToEntRef(parent)) update_ZM_looktarget_HP();
	}
	
}

// There is a deeper layer of glows that the game is managing I can't seem to access with l4dhooks.
void UpdateSurvivorGlow(int client)
{   
    bool alive = IsPlayerAlive(client);
    bool survivor_glow = !alive || is_player_vomited(client);
    L4D2_SetPlayerSurvivorGlowState(client,survivor_glow);
    
    if (DEBUG)
    {
        char name[MAX_NAME_LENGTH]; 
        GetClientName(client,name,sizeof(name));
        LogMessage("[zm] UpdateSurvivorGlow %s alive %d SurvivorGlow %d",name,alive,survivor_glow);
    }
    
    if (alive && survivor_glow) L4D2_RemoveEntityGlow(client);
    else
    {
        bool rescue = false;
        if (alive)
        {
            rescue = survivor_dominated(client);
            dominated[client] = rescue;
        }
        else dominated[client] = false;
        
        bool should_glow = rescue || alive;
        if (should_glow)
        {
           int hp = GetEntProp(client,Prop_Data,"m_iHealth");
           bool flashing = alive && L4D_IsPlayerOnThirdStrike(client);
           bool critical = alive && (L4D_IsPlayerIncapacitated(client) || L4D_IsPlayerHangingFromLedge(client));
           int color[3];
           GetSurvivorHealthColor_pre(hp,color,rescue,critical);
       	   L4D2_SetEntityGlow(client,
                              L4D2Glow_Constant,
                              999999,0,color,flashing);
        }
        else L4D2_RemoveEntityGlow(client);
	}
}

// Survivor health interpolator
static int RGB_CRITICAL[3] =    {160,24,24};
static int RGB_LOW[3] =         {178,63,0};
static int RGB_MEDIUM[3] =      {150,122,8};
static int RGB_HIGH[3] =        {9,175,49};
static int RGB_RESCUE[3] =      {255,102,0};
stock void GetSurvivorHealthColor(int hp,int color[3],bool rescue=false,bool critical=false)
{
      if (rescue)
      {
          color = RGB_RESCUE;
          return;
      }
      else if ( critical || hp<=1 )
      {
          color = RGB_CRITICAL;
          return;
      }
      else if (hp>=100)
      {
          color = RGB_HIGH;
          return;
      }
      
      int mins[3],maxs[3];
      int min,max;
      
      if (hp < 25)
      {
          mins = RGB_CRITICAL;
          maxs = RGB_LOW;
          min = 1;
          max = 25;
      }
      else if (hp < 40)
      {
          mins = RGB_LOW;
          maxs = RGB_MEDIUM;
          min = 25;
          max = 40;
      }
      else
      {
          mins = RGB_MEDIUM;
          maxs = RGB_HIGH;
          min = 40;
          max = 100;
      }
      
      float frac = 1.0*(hp-min)/(max-min);
      if (frac>1.0) frac = 1.0;
      
      color[0] = mins[0] + RoundFloat(frac*(maxs[0]-mins[0]));
      color[1] = mins[1] + RoundFloat(frac*(maxs[1]-mins[1]));
      color[2] = mins[2] + RoundFloat(frac*(maxs[2]-mins[2]));
}

// Check if Survivor or Special Infected is vomited -- attracting commons, for survivors vomit overlay ON.
stock bool is_player_vomited(int client)
{
    float t_end = GetEntPropFloat(client, Prop_Send, "m_itTimer", 1);
    if (t_end<0.0) return false;
    t_end -= 0.1; // smooth transition between custom glow and survivor glow
    if (GetGameTime()>=t_end) return false;
    return true;
}