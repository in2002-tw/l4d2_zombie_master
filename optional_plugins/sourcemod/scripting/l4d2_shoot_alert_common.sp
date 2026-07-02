// Thanks to testers: Hatsune Miku Fan, ngh, Krufftys Killers
// Thanks to SilverShot for code cleanup and serious optimizations.

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <left4dhooks>
#include <l4d2_shoot_alert_common>

#define PLUGIN_VERSION 		"2.18 2026-07-02"
public Plugin myinfo =
{
	name = "[L4D2] Weapon Fire Alert Common",
	author = "gvazdas, SilverShot",
	description = "Survivor gunfire and speech alerts Common Infected (except road workers).",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352360, https://github.com/gvazdas/l4d2_zombie_master"
}

public void OnPluginStart()
{   
    AutoExecConfig(true, CONFIG_FILENAME);
    RegAdminCmd("l4d2_shoot_alert_common_resetcvars", request_reset, ADMFLAG_ROOT, "Reload default cfg. Admins only.");

    populate_multipliers(); // Populate table of weaponid range multipliers.
    
    g_hCvarEnable = CreateConVar("l4d2_shoot_alert_common_enable", "1",
    "0=OFF, 1=ON.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarEnable.AddChangeHook(ConVarChanged_Cvars);   
    
    g_hCvarAlertRange = CreateConVar("l4d2_shoot_alert_common_range", "2500.0",
    "Alert range in line of sight for multiplier=1.0. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 100000.0);
    g_hCvarAlertRange.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertProbability = CreateConVar("l4d2_shoot_alert_common_probability", "0.5",
    "Alert probability. (rush probability is always 1.0)",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAlertProbability.AddChangeHook(ConVarChanged_Cvars);  
    
    g_hCvarRushRange = CreateConVar("l4d2_shoot_alert_common_range_rush", "800.0",
    "Rush range in line of sight for multiplier=1.0. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 100000.0);
    g_hCvarRushRange.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarLOS = CreateConVar("l4d2_shoot_alert_common_los", "2.5",
    "No-line-of-sight range multiplier.",FCVAR_NOTIFY, true, 1.0, true, 10000.0);
    g_hCvarLOS.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertMax = CreateConVar("l4d2_shoot_alert_common_max", "12",
    "Number of alerts in zombie memory to rush. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCvarAlertMax.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAlertMemory = CreateConVar("l4d2_shoot_alert_common_memory", "4.0",
    "How many seconds to forget 1 alert. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCvarAlertMemory.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarVoice = CreateConVar("l4d2_shoot_alert_common_voice", "2.0",
    "Survivor voice range multiplier (scales with volume). 0 to disable. -1.0 for default.",FCVAR_NOTIFY, true, -1.0, true, 1000.0);
    g_hCvarVoice.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarAccumulate = CreateConVar("l4d2_shoot_alert_common_accumulate", "0.0",
    "Set to 1 for hardcore realism. Any extra gunfire between shot and delayed response is accumulated.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAccumulate.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarSaferoom = CreateConVar("l4d2_shoot_alert_common_saferoom", "0.0",
    "Enable alert and rush when survivors are in start area.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarSaferoom.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCvarBudget = CreateConVar("l4d2_shoot_alert_common_budget_ms", "5.0",
    "CPU budget in ms for each alert. 0.0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 1000.0);
    
    g_hCvarMPGameMode = FindConVar("mp_gamemode");
    g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Gamemode);
    
    HookEvent("finale_start", 		    evtFinaleStart,    EventHookMode_PostNoCopy);
    HookEvent("finale_radio_start", 	evtFinaleStart,    EventHookMode_PostNoCopy);
    HookEvent("gauntlet_finale_start", 	evtFinaleStart,    EventHookMode_PostNoCopy);
    HookEvent("round_end",              evtRound,          EventHookMode_PostNoCopy);
    HookEvent("map_transition",         evtRound,          EventHookMode_PostNoCopy);
    HookEvent("triggered_car_alarm",    evtCarAlarm,       EventHookMode_PostNoCopy);
    CheckSurvival();
    GetCvars();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion()!=Engine_Left4Dead2)
	{
		strcopy(error,err_max,"Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
    MarkNativeAsOptional("L4D_FindEntityByClassnameNearest");
    MarkNativeAsOptional("L4D_FindEntityByClassnameWithin");
    CreateNative("L4D2_Infected_Alert_Constructor", Native_alert_constructor);
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	l4dhooks_updated = GetFeatureStatus(FeatureType_Native,"L4D_FindEntityByClassnameNearest")==FeatureStatus_Available;
    if (!l4dhooks_updated) LogMessage("WARNING: update l4dhooks for better performance.");
}

void ConVarChanged_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CheckSurvival();
    RequestFrame(check_hooks);
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

public void L4D_OnFinishIntro()
{
    if (!enabled || weapon_fire_hooked || timer_hook!=null) return;
    timer_hook = CreateTimer(0.1,timer_check_hooks,_,TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post()
{
    if (!enabled || weapon_fire_hooked || timer_hook!=null) return;
    timer_hook = CreateTimer(0.1,timer_check_hooks,_,TIMER_FLAG_NO_MAPCHANGE);
}

public void OnEntityCreated(int entity, const char[] classname) // Check if this is an infected entity.
{
	if (!enabled || !map_started || finale || survival || !IsValidEdict(entity)) return;
	ignore[entity] = true; // ignore alerts from before zombie spawned
	if (entity>MaxClients && strncmp(classname,"infected",8,false)==0 && GetEntProp(entity,Prop_Send,"m_mobRush")<=0)
	{
       	CreateTimer(weapon_fire_hooked ? 1.51 : 0.1,check_aggro,EntIndexToEntRef(entity),TIMER_FLAG_NO_MAPCHANGE); // prevent zombie from alerting retroactively
	}
}

public void L4D2_Infected_HitByVomitJar_Post(int victim, int attacker)
{
    if (!enabled || finale || survival || !IsValidEdict(victim)) return;
    ignore_infected(victim);
}

public void OnEntityDestroyed(int entity) // When infected is destroyed, check if hooks need to be deactivated.
{
    if (!weapon_fire_hooked || !IsValidEntity(entity)) return;
    if (is_infected(entity))
    {
        commons -= 1;
        if (commons<=0 && timer_hook==null) timer_hook = CreateTimer(0.1,timer_check_hooks,_,TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void L4D2_GrenadeLauncher_Detonate_Post(int entity, int client)
{
    if (!weapon_fire_hooked) return;
    float multiplier = get_weaponid_multiplier(L4D2WeaponId_GrenadeLauncher);
    #if DEBUG 
    LogMessage("%d detonated grenade %d -> %f", client,entity,multiplier);
    #endif
    reset_timers(false,true); // louder than guns and voices
    alert_constructor(entity,client,multiplier,true);
}

public void L4D_PipeBombProjectile_Post(int client, int projectile, const float vecPos[3], const float vecAng[3], const float vecVel[3], const float vecRot[3])
{
    if (!weapon_fire_hooked || !IsValidAliveSurvivor(client)) return;
    #if DEBUG 
    LogMessage("%d threw pipebomb %d", client, projectile);
    #endif
    reset_timers(false,true); // louder than guns and voices
}

void evtCarAlarm(Event event, const char[] name, bool dontBroadcast)
{
    if (!weapon_fire_hooked) return;
    #if DEBUG 
    LogMessage("evtCarAlarm");
    #endif
    ignore_all(); // all commons should be rushing
    commons = 0;
    check_hooks(HOOKS_FORCE_OFF);
    timer_hook = CreateTimer(5.0,timer_check_hooks,_,TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D2_VomitJar_Detonate_Post(int entity, int client)
{
    if (!weapon_fire_hooked) return;
    #if DEBUG 
    LogMessage("VomitJar_Detonate");
    #endif
    reset_timers(false,true);
}

public void L4D_PipeBomb_Detonate_Post(int entity, int client)
{
    if (!weapon_fire_hooked) return;
    static char class[32];
    GetEntityClassname(entity,class,sizeof(class)); 
    if (strncmp(class,"pipe_bomb_projectile",20,false)!=0) return; // bug noted in l4dhooks documentation
    #if DEBUG 
    LogMessage("%d detonated %s %d", client, class, entity);
    #endif
    reset_timers(false,true); // louder than guns and voices
    float multiplier = get_weaponid_multiplier(L4D2WeaponId_GrenadeLauncher);
    alert_constructor(entity,client,multiplier,true);
}

public void OnMapStart()
{
    #if DEBUG
    g_iLaser = PrecacheModel("sprites/laserbeam.vmt", true);
    #endif
    finale = false;
    roundcount += 1;
    if (enabled) ignore_all();
    if (weapon_fire_hooked) check_hooks(HOOKS_FORCE_OFF);
    RequestFrame(MapStarted);
}

public void OnMapEnd()
{
    finale = false;
    roundcount += 1;
    map_started = false;
    if (enabled) ignore_all();
    if (weapon_fire_hooked) check_hooks(HOOKS_FORCE_OFF);
}

public void L4D2_OnSavingEntities_Post(int info_changelevel)
{
    map_started = false;
    if (enabled) ignore_all();
    if (weapon_fire_hooked) check_hooks(HOOKS_FORCE_OFF);
}

void evtRound(Event event, const char[] name, bool dontBroadcast)
{
    roundcount += 1;
    finale = false;
    if (enabled) ignore_all();
    if (weapon_fire_hooked) check_hooks(HOOKS_FORCE_OFF);
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    finale = true;
    commons = 0; // all rushing survivors
    if (enabled) ignore_all();
    if (weapon_fire_hooked) check_hooks(HOOKS_FORCE_OFF);
}

public void OnClientPutInServer(int client)
{
    if (!weapon_fire_hooked || client<=0 || client>MaxClients) return;
    timers[client] = null;
    spoken[client] = false;
}

void Native_alert_constructor(Handle plugin, int numParams)
{
    if (!weapon_fire_hooked) return;
    int entity = (numParams>0) ? GetNativeCell(1) : -1;
    int client = (numParams>1) ? GetNativeCell(2) : -1;
    float multiplier = (numParams>2) ? view_as<float>(GetNativeCell(3)) : 1.0;
    bool force = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : false;
    float pos[3] = {0.0,0.0,0.0};
    if (numParams>4) GetNativeArray(5,pos,3);
    alert_constructor(entity,client,multiplier,force,pos);
}