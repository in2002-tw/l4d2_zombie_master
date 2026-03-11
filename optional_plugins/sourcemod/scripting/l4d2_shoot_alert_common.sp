// Thanks to testers: Hatsune Miku Fan, Krufftys Killers
// Thanks Silvers for code cleanup.

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <left4dhooks>

#define PLUGIN_NAME			    "l4d2_shoot_alert_common"
#define PLUGIN_VERSION 			"1.4 2026-03-10"
#define GAMEDATA_FILE           PLUGIN_NAME
#define CONFIG_FILENAME         PLUGIN_NAME

public Plugin myinfo =
{
	name = "[L4D2] Weapon Fire Alert Common",
	author = "gvazdas",
	description = "Survivor weapon fire and speech alerts Common Infected (except road workers).",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352360,https://github.com/gvazdas/l4d2_zombie_master"
}

#define TEAM_SPECTATOR		1
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3
#define MAXENTITIES         2048
#define MODEL_ROAD          "models/infected/common_male_roadcrew.mdl"
#define DEBUG               0

// Optimizations
Handle timer_hook; // reduce weapon_fire hook/unhook spam
Handle timers[MAXPLAYERS+1]; // reduce weapon_fire and NormalSoundHook spam
bool ignore[MAXENTITIES] = {true,...}; // ignore non-infected, and rushing or road worker infected
float multipliers[MAXPLAYERS+1]; // track range multipliers for silent smg, survivor speech
bool weapon_fire_hooked = false; // track weapon_fire hook
bool speech_hooked = false; // track NormalSoundHook
bool finale_active = false; // do nothing during survival and finales
int commons = 0; // track only non-rushing commons
float pos_arr[MAXPLAYERS+1][3]; // calculate position of survivor only once before callback
int alerts[MAXENTITIES]; // force infected rush if alerted too many times
Handle timer_calm; // periodically calm down non-rushing infected

// Inputs
ConVar g_hCvarEnable, g_hCvarAlertRange, g_hCvarAlertProbability, g_hCvarRushRange, g_hCvarLOS, g_hCvarAlertMax, g_hCvarAlertMemory, g_hCvarSpeech, g_hCvarMPGameMode;
bool enabled, speech = false;
float alert_range, rush_range, alert_probability, alert_memory, LOS_multiplier;
int alert_max;

public void OnPluginStart()
{
    AutoExecConfig(true, CONFIG_FILENAME);
    
    g_hCvarEnable = CreateConVar("l4d2_shoot_alert_common_enable", "1", "0=Plugin off, 1=Plugin on.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarEnable.AddChangeHook(ConVarChanged_Cvars);   
    
    g_hCvarAlertRange = CreateConVar("l4d2_shoot_alert_common_range", "2500.0", "Alert range in line of sight.",FCVAR_NOTIFY, true, 0.0, true, 100000.0);
    g_hCvarAlertRange.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertProbability = CreateConVar("l4d2_shoot_alert_common_probability", "0.5", "Alert probability.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAlertProbability.AddChangeHook(ConVarChanged_Cvars);  
    
    g_hCvarRushRange = CreateConVar("l4d2_shoot_alert_common_range_rush", "700.0", "Rush range in line of sight.",FCVAR_NOTIFY, true, 0.0, true, 100000.0);
    g_hCvarRushRange.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarLOS = CreateConVar("l4d2_shoot_alert_common_los", "2.0", "No line-of-sight range multiplier.",FCVAR_NOTIFY, true, 1.0, true, 10000.0);
    g_hCvarLOS.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertMax = CreateConVar("l4d2_shoot_alert_common_max", "10", "Number of alerts to rush. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCvarAlertMax.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertMemory = CreateConVar("l4d2_shoot_alert_common_memory", "5.0", "How many seconds to forget 1 alert. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCvarAlertMemory.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarSpeech = CreateConVar("l4d2_shoot_alert_common_vocalize", "0.0", "Treat survivor voice same as silenced mp5 (also scales with volume).",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarSpeech.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarMPGameMode = FindConVar("mp_gamemode");
    g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Gamemode);
    
  	HookEvent("finale_start", 			evtFinaleStart,    EventHookMode_PostNoCopy);
  	HookEvent("finale_radio_start", 	evtFinaleStart,    EventHookMode_PostNoCopy);
  	HookEvent("gauntlet_finale_start", 	evtFinaleStart,    EventHookMode_PostNoCopy);
  	HookEvent("survival_round_start",   evtFinaleStart,    EventHookMode_PostNoCopy);
  	HookEvent("round_start",            evtRound,          EventHookMode_PostNoCopy);
    HookEvent("round_end",              evtRound,          EventHookMode_PostNoCopy);
    GetCvars();
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue) { GetCvars(); }
void ConVarChanged_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue) { RequestFrame(check_hooks); }

void GetCvars()
{
    alert_range = g_hCvarAlertRange.FloatValue;
    rush_range = g_hCvarRushRange.FloatValue;
    alert_probability = g_hCvarAlertProbability.FloatValue;
    LOS_multiplier = g_hCvarLOS.FloatValue;
    if (g_hCvarSpeech.BoolValue != speech)
    {
        speech = g_hCvarSpeech.BoolValue;
        if (speech_hooked!=speech) RequestFrame(check_hooks);
    }
    if (alert_max!=g_hCvarAlertMax.IntValue || g_hCvarAlertMemory.FloatValue != alert_memory)
    {
        alert_max = g_hCvarAlertMax.IntValue;
        alert_memory = g_hCvarAlertMemory.FloatValue;
        if (weapon_fire_hooked) // Repeating timer needs to be restarted with new period
        {
            timer_calm = null;
            if (alert_memory>0.0 && alert_max>0) perform_calm(null,true);
        }
    }
    IsAllowed();
}

void IsAllowed()
{
    if (g_hCvarEnable.BoolValue==enabled) return;
    enabled = g_hCvarEnable.BoolValue;
    if (enabled)
    {
        HookEvent("player_team", evtPlayerTeam, EventHookMode_Post);
        HookEvent("player_spawn", evtPlayerTeam, EventHookMode_Post);
        HookEvent("player_activate", evtPlayerTeam, EventHookMode_Post);
        HookEvent("player_bot_replace", EvtBotReplace, EventHookMode_Post);
        HookEvent("bot_player_replace", EvtBotReplace, EventHookMode_Post);
        late_enable();
    }
    else
    {
        UnhookEvent("player_team", evtPlayerTeam, EventHookMode_Post);
        UnhookEvent("player_spawn", evtPlayerTeam, EventHookMode_Post);
        UnhookEvent("player_activate", evtPlayerTeam, EventHookMode_Post);
        UnhookEvent("player_bot_replace", EvtBotReplace, EventHookMode_Post);
        UnhookEvent("bot_player_replace", EvtBotReplace, EventHookMode_Post);
        check_hooks();
    }
}

void check_hooks() // Dynamically hook/unhook weapon_fire and NormalSoundHook for performance.
{
    timer_hook = null;
    bool should_hook = enabled && !finale_active && !L4D_IsSurvivalMode() && get_commons()>0;
    bool should_hook_speech = should_hook && speech;
    bool changed = false;
    if (should_hook!=weapon_fire_hooked)
    {
        if (should_hook) HookEvent("weapon_fire", evtPlayerFired, EventHookMode_Post);
        else UnhookEvent("weapon_fire", evtPlayerFired, EventHookMode_Post);
        weapon_fire_hooked = should_hook;
        changed = true;
        #if DEBUG 
            LogMessage("weapon_fire hook %d", weapon_fire_hooked);
        #endif
    }
    if (should_hook_speech!=speech_hooked)
    {
        if (should_hook_speech) AddNormalSoundHook(SurvivorSpeak);
        else RemoveNormalSoundHook(SurvivorSpeak);
        speech_hooked = should_hook_speech;
        changed = true;
        #if DEBUG 
            LogMessage("NormalSoundHook %d", speech_hooked);
        #endif
    }
    if (changed && alert_memory>0.0 && alert_max>0) perform_calm(null,true);
}

Action timer_check_hooks(Handle timer)
{
    check_hooks();
    return Plugin_Stop;
}

void late_enable() // If plugin just enabled, check if there are any infected entities to alarm.
{
    reset_timers();
    get_commons(false,true);
    if (!weapon_fire_hooked && commons>0) check_hooks();
}

public void OnEntityCreated(int entity, const char[] classname) // When a zombie is created, check if hooks should activate.
{
	if (!enabled || finale_active || L4D_IsSurvivalMode()) return;
	if (strcmp(classname,"infected")==0 && GetEntProp(entity,Prop_Send,"m_mobRush")<=0)
	{
    	ignore[entity] = false; commons += 1; alerts[entity]=0;
    	CreateTimer(1.0,check_aggro,EntIndexToEntRef(entity));
	}
}

Action check_aggro(Handle timer, int entref) // Check again.
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    if (GetEntProp(entref,Prop_Send,"m_mobRush")>0)
    {
        ignore_infected(EntRefToEntIndex(entref));
        return Plugin_Stop;
    }
    if (weapon_fire_hooked || timer_hook!=null) return Plugin_Stop;
    timer_hook = CreateTimer(0.1,timer_check_hooks); // idle infected, activate hooks
    return Plugin_Stop;
}

public void OnEntityDestroyed(int entity) // When infected is destroyed, check if hooks needs to be deactivated.
{
	if (!weapon_fire_hooked || !IsValidEntity(entity)) return;
	static char class[16];
    GetEntityClassname(entity, class, sizeof(class));
    if (strcmp(class,"infected")==0)
    {
    	commons -= 1;
    	if (commons<=0 && timer_hook==null) timer_hook = CreateTimer(0.1,timer_check_hooks);
    }
}

void evtPlayerFired(Event event, const char[] name, bool dontBroadcast) // Survivor fired a gun.
{
    if (event.GetInt("count")<=0) return; // melee weapons give 0 count
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (timers[client]!=null) return;
    if (GetClientTeam(client)!=TEAM_SURVIVOR) return;
    static char weapon[128];
    event.GetString("weapon",weapon,sizeof(weapon),""); // 2.0 multiplier for silenced smg
    multipliers[client] = (StrContains(weapon,"silen",false)>=0) ? 2.0 : 1.0;
    timers[client] = CreateTimer(GetRandomFloat(0.5,1.5),alert_update,EntIndexToEntRef(client),TIMER_FLAG_NO_MAPCHANGE);
}

Action SurvivorSpeak(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
                   int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
                   char soundEntry[PLATFORM_MAX_PATH], int &seed) // Survivor said something.
{
    if (channel!=SNDCHAN_VOICE) return Plugin_Continue;
    if (volume<=0.1) return Plugin_Continue;
    if (sample[0]!='p') return Plugin_Continue;
    if (!IsValidClient(entity)) return Plugin_Continue;
    if (timers[entity]!=null) return Plugin_Continue;
    if (!IsPlayerAlive(entity) || GetClientTeam(entity)!=TEAM_SURVIVOR) return Plugin_Continue;
    if (StrContains(sample,"survivor")<0 || StrContains(sample,"voice")<0) return Plugin_Continue;
    multipliers[entity] = 2.0/volume; // at full volume, treat speech similar to silenced mp5
    #if DEBUG 
        LogMessage("%s %f -> %f", sample, volume, multipliers[entity]);
    #endif
    timers[entity] = CreateTimer(GetRandomFloat(0.5,1.5),alert_update,EntIndexToEntRef(entity),TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

Action alert_update(Handle timer, int entref) // Alert nearby infected.
{
    if (!IsValidEntRef(entref)) return Plugin_Stop;
    int client = EntRefToEntIndex(entref);
    if (!IsValidClient(client)) return Plugin_Stop;
    if (timers[client]==null) return Plugin_Stop; // prevent carry-over to new round
    timers[client] = null;
    if (!IsPlayerAlive(client) || GetClientTeam(client)!=TEAM_SURVIVOR) return Plugin_Stop;
    if (FindEntityByClassname(-1, "pipe_bomb_projectile")!=INVALID_ENT_REFERENCE) return Plugin_Stop;
    static float pos[3];
    L4D_GetEntityWorldSpaceCenter(client,pos);
    pos_arr[client][0] = pos[0]; pos_arr[client][1] = pos[1]; pos_arr[client][2] = pos[2];
    TR_EnumerateEntitiesSphere(pos,alert_range,PARTITION_NON_STATIC_EDICTS,AlertCallback,client);
    return Plugin_Stop;
}

bool AlertCallback(int entity, int client) // Return true to continue enumerating, false to stop
{
    if (entity<=MaxClients || !IsValidEntity(entity)) return true;
    if (ignore[entity]) return true;
    #if DEBUG
        LogMessage("AlertCallback client %d entity %d", client, entity);
    #endif
    static char class[16];
    GetEntityClassname(entity, class, sizeof(class));
    if (strcmp(class,"infected")==0)
    {
        if (GetEntProp(entity,Prop_Send,"m_mobRush")>0) // If already rushing, do nothing.
        {
            ignore_infected(entity);
            return true;
        }
        
        static char sModelName[64]; 
        GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
        if (strcmp(sModelName,MODEL_ROAD)==0) // Road crew have headphones, ignore gunfire.
        {
            ignore_infected(entity);
            return true;
        }
        
        if (!IsValidClient(client)) return false; // just in case.
        
        static float pos[3], pos2[3];
        pos[0] = pos_arr[client][0]; pos[1] = pos_arr[client][1]; pos[2] = pos_arr[client][2];
        L4D_GetEntityWorldSpaceCenter(entity,pos2);
        float range = GetVectorDistance(pos,pos2);
        pos2[2] += 36.0;
        bool LOS = L4D2_IsVisibleToPlayer(client,TEAM_SURVIVOR,3,0,pos2);
        if (!LOS) range *= LOS_multiplier;
        range *= multipliers[client];
        
        if (range<=rush_range)
        {
            infected_rush_client(entity,client);
            return true;
        }
        if (range>alert_range) return true;
        if (alert_probability>=1.0 || GetRandomFloat(0.0,1.0)<alert_probability)
        {
            if (alert_max>0) // Aggro if disturbed too many times.
            {
                alerts[entity] += 1; 
                if (alerts[entity]>=alert_max)
                {
                    infected_rush_client(entity,client);
                    return true;
                }
            }
            int look = GetEntPropEnt(entity, Prop_Send, "m_clientLookatTarget");
            if ( LOS && ( look==client || (IsValidClient(look) && IsPlayerAlive(look) && GetClientTeam(look)==TEAM_SURVIVOR) ) )
                infected_rush_client(entity,client); // Aggro if LOS and was previously looking at any alive survivor.
            else if (look<=0)
            {
                SetEntPropEnt(entity, Prop_Send, "m_clientLookatTarget",client);
                DataPack pack;
                CreateDataTimer(GetRandomFloat(1.5,2.5),undo_lookat,pack,TIMER_FLAG_NO_MAPCHANGE);
                pack.WriteCell(EntIndexToEntRef(entity));
                pack.WriteCell(EntIndexToEntRef(client));
            }
        }
    }
    else ignore[entity] = true;
    return true;
}

void infected_rush_client(int infected, int client)
{
    #if DEBUG
        LogMessage("infected %d rush %d", infected, client);
    #endif
    SetEntPropEnt(infected, Prop_Send, "m_clientLookatTarget", client); // this might do absolutely nothing.
    SetEntProp(infected, Prop_Send, "m_mobRush", 1);
    ignore_infected(infected);
}

void ignore_infected(int infected)
{
    ignore[infected] = true;
    alerts[infected] = 0;
    commons -= 1;
    if (commons<=0 && timer_hook==null) check_hooks();
}

Action undo_lookat(Handle timer, DataPack pack) // Must have been the wind...
{
    pack.Reset();
    int entref_zombie = pack.ReadCell();
    if (!IsValidEntRef(entref_zombie)) return Plugin_Stop;
    if (GetEntProp(entref_zombie, Prop_Send, "m_mobRush")>0)
    {
        ignore_infected(EntRefToEntIndex(entref_zombie));
        return Plugin_Stop;
    }
    int entref_client = pack.ReadCell();
    if (!IsValidEntRef(entref_client)) return Plugin_Stop;
    int client = EntRefToEntIndex(entref_client);
    if (GetEntPropEnt(entref_zombie, Prop_Send, "m_clientLookatTarget")==client)
        SetEntPropEnt(entref_zombie, Prop_Send, "m_clientLookatTarget",-1);
    return Plugin_Stop;
}

public void OnMapStart()
{
    if (!enabled) return;
    reset_timers();
    RequestFrame(check_hooks);
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    finale_active = true;
    if (weapon_fire_hooked) RequestFrame(check_hooks);
}

void evtRound(Event event, const char[] name, bool dontBroadcast)
{
    finale_active = false;
    if (!enabled) return;
    reset_timers();
    RequestFrame(check_hooks);
}

void EvtBotReplace(Event event, const char[] name, bool dontBroadcast) 
{
    int bot = GetClientOfUserId(event.GetInt("bot"));
    int client = GetClientOfUserId(event.GetInt("player"));
    if (IsValidClient(client)) timers[client] = null;
    if (IsValidClient(bot)) timers[bot] = null;
}

void evtPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) timers[client] = null;
}

int get_commons(bool calm=false, bool late=false) // Counting ONLY non-aggro infected
{
    int entity = -1;
    int count = 0;
   	while( (entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE )
   	{
   		if (GetEntProp(entity,Prop_Send,"m_mobRush")>0) ignore[entity] = true;
   		else
   		{
       		if (late) ignore[entity] = false;
       		if (calm && alerts[entity]>0)
       		{
           		alerts[entity] -= 1;
           		#if DEBUG
                       LogMessage("infected %d calmed -> %d", entity, alerts[entity]);
                #endif
       		}
       		count++;
   		}
   	}
   	commons = count;
    return commons;
}

Action perform_calm(Handle timer=null, bool reset = false)
{
    if (!weapon_fire_hooked)
    {
        timer_calm = null;
        return Plugin_Stop;
    }
    if ( (timer_calm==null || reset) && alert_memory>=0.1 )
    {
        timer_calm = CreateTimer(alert_memory,perform_calm,false,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    if (timer_calm==null || timer!=timer_calm) return Plugin_Stop;
    get_commons(true);
    return Plugin_Continue;
}

void reset_timers()
{
    for( int i = 1; i <= MAXPLAYERS; i++ )
    {
        timers[i] = null;
    }
    timer_hook = null;
    timer_calm = null;
}  

stock bool IsValidClient(int client, bool replaycheck = true)
{
	if (client<1 || client>MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}

stock bool IsValidEntRef(int entity)
{
	if( entity && entity != -1 && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;	
}