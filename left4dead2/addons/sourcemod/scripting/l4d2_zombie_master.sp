#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>

bool DEBUG = false;

// Changelog for 0.6.1
// Rounding zombie counts
// More frequent ZM looktarget checks
// Added "Angry" Uncommon
// Various EMS HUD improvements - better box width estimation, no PANIC text if PANIC is off, ZM info blinks when PANIC is about to end.
// All zombies spawned by ZM now have targetnames "zm_unit", "zm_unit_common" and "zm_unit_uncommon". Only zombies with this targetname are refundable.
// Uncommon infected now refunded correctly.
// Saferoom visibility checks added.
// During the prep stage, distance to saferoom is now checked for the zombie spawner.
// ZM unit glow now functions as a health bar.
// The health of the special infected that is currently selected is now displayed in the hint box.
// ZM can now see infected ladders.
// New survivor glows
// Damage messages (zombie master hit survivor etc...) are now disabled for ZM to prevent the sourcemod menu from being blocked visually.
// Going into observer after controlling special infected bugs have been fixed, namely the stuttering and lag issues related to shove and 3rd person camera animations.
// Estonian translation by zyiks
// Traditional Chinese translation by in2002
// Glows are now used to carry information
// Special infected: white to red glow indicates HP. Flashing indicates the unit selected for control with the USE key.
// Witches: flashing indicates the witch has been spotted and cannot be refunded.
// l4d1coop and l4d1survival now supported
// You can now point your spawner DIRECTLY at a survivor which will spawn the zombie at the nearest valid location.
// Added scary round start sequence involving the saferoom door. Only the zombie master can trigger it.
// New syntax on all client commands for spawning zombies

// TO DO LIST:
// 3. Gameplay balance
// 4. Better easier to read zombie spawner visuals (done by zyiks, not implemented)
// 5. Gas station tornado (done by zyiks, not implemented)
// 7. More models for Specials -- maybe l4d2_random_si_model is enough
// 10. Fixing stuck zombies -- hull checks by zyiks
// 11. Allowing ZM to see "obscured" navmeshes for easy spawns
// 12. Better navmesh integration - currently we are taking the highest possible z value of a nav mesh which can make the spawner appear super high above surfaces.
// 14. Zombie Master ticket system; give priority to players who didn't get to be ZM yet.
// 15. Performance bottlenecks.
// 16. Is there a way to prevent observers from being able to see the ZM info?
// 19. Improve ZM experience: spawning zombies, traversing map, reading survivor flow
// 21. Survivor bots will sometimes teleport to ZM and fall to their death
// 24. Dynamic light for ZM instead of annoying saturated night vision
// 25. Fix available SI exploit
// 26. No fog for ZM
// 27. Add Louis and Ellis sounds
// 28. See if infected ladders can be seen with scrimmage netprops
// 29. Lag due to too many commons.
// 30. QuitZM -> JoinZM exploit

#define PLUGIN_NAME			    "l4d2_zombie_master"
#define PLUGIN_VERSION 			"0.6.1 2026-01-26"
#define GAMEDATA_FILE           PLUGIN_NAME

#define FOG_DISTANCE 5000.0
float fog_distance = FOG_DISTANCE;

public Plugin myinfo =
{
	name = "[L4D2] Zombie Master",
	author = "gvazdas,zyiks",
	description = "[coop,survival] AI Game Director is replaced with a Player Game Director, the Zombie Master.",
	version = PLUGIN_VERSION,
	url = "https://github.com/gvazdas/l4d2_zombie_master, https://forums.alliedmods.net/showthread.php?t=352060"
}

#define HULL_DX 20.0
#define HULL_DZ 36.0
#define HULL_DDZ 72.0

static float HULL_MINS[3] = {-HULL_DX,-HULL_DX,1.0};
static float HULL_MAXS[3] = {HULL_DX,HULL_DX,HULL_DDZ};

// Pilfered from zyiks
public bool TraceFilter_NoPlayers(int entity, int contentsMask)
{
	return (entity > MaxClients || entity == 0);
}
bool IsObstructed(float vecpos[3], int ZOMBIECLASS)
{
     bool isObstructed = false;
	Handle hullTrace = TR_TraceHullFilterEx(vecpos, vecpos, HULL_MINS, HULL_MAXS,
								    MASK_NPCSOLID, TraceFilter_NoPlayers);
	if (TR_DidHit(hullTrace))
	{
		int hitEntity = TR_GetEntityIndex(hullTrace);
		int hullSurfaceFlags = TR_GetSurfaceFlags(hullTrace);
		if (hitEntity == 0)
		{
			// Hit world
			if (!(hullSurfaceFlags & 0x0080) && !(hullSurfaceFlags & 0x0100) && !(hullSurfaceFlags & 0x0200))
        			isObstructed = true;
		}
		else isObstructed = true;
	}
	delete hullTrace;
	return isObstructed;
}

#define HUD_TIMER                          0
#define HUD_ZM                             1
#define HUD_TICKER                         2
#define HUD_ZM_HINT                        3

#define HUD_FLAG_NONE                 0     // no flag
#define HUD_FLAG_PRESTR               1     // do you want a string/value pair to start(pre) with the string (default is PRE)
#define HUD_FLAG_POSTSTR              2     // do you want a string/value pair to end(post) with the string
#define HUD_FLAG_BEEP                 4     // Makes a countdown timer blink
#define HUD_FLAG_BLINK                8     // do you want this field to be blinking
#define HUD_FLAG_AS_TIME              16    // ?
#define HUD_FLAG_COUNTDOWN_WARN       32    // auto blink when the timer gets under 10 seconds
#define HUD_FLAG_NOBG                 64    // dont draw the background box for this UI element
#define HUD_FLAG_ALLOWNEGTIMER        128   // by default Timers stop on 0:00 to avoid briefly going negative over network, this keeps that from happening
#define HUD_FLAG_ALIGN_LEFT           256   // Left justify this text
#define HUD_FLAG_ALIGN_CENTER         512   // Center justify this text
#define HUD_FLAG_ALIGN_RIGHT          768   // Right justify this text
#define HUD_FLAG_TEAM_SURVIVORS       1024  // only show to the survivor team
#define HUD_FLAG_TEAM_INFECTED        2048  // only show to the special infected team
#define HUD_FLAG_TEAM_MASK            3072  // ?
#define HUD_FLAG_UNKNOWN1             4096  // ?
#define HUD_FLAG_TEXT                 8192  // ?
#define HUD_FLAG_NOTVISIBLE           16384 // if you want to keep the slot data but keep it from displaying
#define HUD_TEXT_ALIGN_LEFT           1
#define HUD_TEXT_ALIGN_CENTER         2
#define HUD_TEXT_ALIGN_RIGHT          3

#define TEAM_SPECTATOR		1
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3
#define TEAM_ZM 3

#define ZOMBIECLASS_COMMON 	0
#define ZOMBIECLASS_SMOKER 	1
#define ZOMBIECLASS_BOOMER	 2
#define ZOMBIECLASS_HUNTER	 3
#define ZOMBIECLASS_SPITTER	4
#define ZOMBIECLASS_JOCKEY	 5
#define ZOMBIECLASS_CHARGER	6
#define ZOMBIECLASS_WITCH	7
#define ZOMBIECLASS_TANK	8

void get_zombieclass_name(int ZOMBIECLASS, char name[32])
{
    switch(ZOMBIECLASS)
    {
        case ZOMBIECLASS_SMOKER: name = "Smoker";
        case ZOMBIECLASS_BOOMER: name = "Boomer";
        case ZOMBIECLASS_HUNTER: name = "Hunter";
        case ZOMBIECLASS_SPITTER: name = "Spitter";
        case ZOMBIECLASS_JOCKEY: name = "Jockey";
        case ZOMBIECLASS_CHARGER: name = "Charger";
        case ZOMBIECLASS_TANK: name = "Tank";
        default: Format(name, sizeof(name), "Unknown(%d)", ZOMBIECLASS);
    }
}

#define WITCH_STATIC 0
#define WITCH_MOVING 1

#define IGNITE_TIME 3600.0

#define MODEL_SMOKER "models/infected/smoker.mdl"
#define MODEL_BOOMER "models/infected/boomer.mdl"
#define MODEL_HUNTER "models/infected/hunter.mdl"
#define MODEL_SPITTER "models/infected/spitter.mdl"
#define MODEL_JOCKEY "models/infected/jockey.mdl"
#define MODEL_CHARGER "models/infected/charger.mdl"
#define MODEL_TANK "models/infected/hulk.mdl"

#define MODEL_RIOT "models/infected/common_male_riot.mdl"
#define MODEL_CEDA "models/infected/common_male_ceda.mdl"
#define MODEL_CLOWN "models/infected/common_male_clown.mdl"
#define MODEL_MUD "models/infected/common_male_mud.mdl"
#define MODEL_ROAD "models/infected/common_male_roadcrew.mdl"
#define MODEL_JIMMY "models/infected/common_male_jimmy.mdl"
#define MODEL_FALLEN "models/infected/common_male_fallen_survivor.mdl"

//#define MODEL_LADDER "models/props_c17/metalladder001.mdl"
//#define MODEL_LADDER "*1"

#define SOUND_READY "ui/critical_event_1.wav"
#define SOUND_REWARD "ui/beep_synthtone01.wav"
#define SOUND_ZM_WIN "level/loud/gallery_win.wav"
#define SOUND_DOORSLAM "doors/heavy_metal_stop1.wav"
#define SOUND_DOORSLAM2 "doors/hit_kickmetaldoor1.wav"
#define SOUND_DOORSLAM3 "doors/hit_kickmetaldoor2.wav"
#define SOUND_BUG "common/bugreporter_failed.wav"
#define SOUND_INACTIVITY "ambient/crucial_cricket_amb_01.wav"
#define SOUND_START "ui/pickup_guitarriff10.wav"
#define SOUND_VISION "ui/menu_horror01.wav"
#define SOUND_PANIC_ON "npc/mega_mob/mega_mob_incoming.wav"
#define SOUND_PANIC_OFF "ui/pickup_secret01.wav"

#define SOUND_ELLIS_ZM "zm/ellis_zm.wav"
#define SOUND_LOUIS_ZM "zm/louis_zm.wav"

// These are played whenever the ZM forces the round to start by slamming the door open.
#define SOUND_SCARY1 "ambient/creatures/town_moan1.wav"
#define SOUND_SCARY2 "ambient/creatures/town_scared_breathing1.wav"
#define SOUND_SCARY3 "ambient/creatures/town_scared_breathing2.wav"
#define SOUND_SCARY4 "ambient/creatures/town_scared_sob1.wav"
#define SOUND_SCARY5 "ambient/creatures/town_scared_sob2.wav"

#define VMT_LASERBEAM "sprites/laserbeam.vmt"
#define VMT_HALO "sprites/halo.vmt"

#define MAXENTITIES                   2048
#define ENTITY_SAFE_LIMIT 2000 //don't spawn boxes when it's index is above this
#define ENTITY_SAFER_LIMIT 1900

// Thanks Forgetest
DynamicDetour g_dd_StartRangeCull;

// Thanks blueblur
DynamicDetour g_hDTR_InputKill = null;
DynamicDetour g_hDTR_InputKillHierarchy = null;

//DynamicDetour g_dd_ChangeFinaleStage;

//signature call
static Handle hCreateSmoker = null;
#define NAME_CreateSmoker "NextBotCreatePlayerBot<Smoker>"
#define NAME_CreateSmoker_L4D1 "reloffs_NextBotCreatePlayerBot<Smoker>"
static Handle hCreateBoomer = null;
#define NAME_CreateBoomer "NextBotCreatePlayerBot<Boomer>"
#define NAME_CreateBoomer_L4D1 "reloffs_NextBotCreatePlayerBot<Boomer>"
static Handle hCreateHunter = null;
#define NAME_CreateHunter "NextBotCreatePlayerBot<Hunter>"
#define NAME_CreateHunter_L4D1 "reloffs_NextBotCreatePlayerBot<Hunter>"
static Handle hCreateSpitter = null;
#define NAME_CreateSpitter "NextBotCreatePlayerBot<Spitter>"
static Handle hCreateJockey = null;
#define NAME_CreateJockey "NextBotCreatePlayerBot<Jockey>"
static Handle hCreateCharger = null;
#define NAME_CreateCharger "NextBotCreatePlayerBot<Charger>"
static Handle hCreateTank = null;
#define NAME_CreateTank "NextBotCreatePlayerBot<Tank>"
#define NAME_CreateTank_L4D1 "reloffs_NextBotCreatePlayerBot<Tank>"

static Handle hInfectedAttackSurvivorTeam = null;

// https://github.com/Ilusion9/entityIO-sm
static Handle g_DHook_AcceptInput = null;

int AllPlayerCount;
ConVar g_hCvarDebug, g_hCvarAllow, z_max_player_zombies, infectedbots_enable;
//ConVar infectedbots_dispose_cowards;
bool g_bCvarAllow;
bool g_bSpawnWitchBride = false; // avoid crash

// ZM stages
#define ZM_NEWROUND 0 // Survivors in start area, no ZM picked.
#define ZM_PREP 1 // Survivors in start area, ZM is placing units and getting ready, or players still joining. Survivors cannot leave yet.
#define ZM_CANSTART 2 // Prep has ended but survivors haven't left the safezone yet
#define ZM_STARTED 3 // Round has started
#define ZM_END 4 // Round has ended - do not allow new ZM or spawning of zombies

int zm_stage = ZM_NEWROUND;
void set_zm_stage(int stage, bool override = false)
{
    if (zm_stage<stage || override) zm_stage = stage;
}

//static float t_panic_overlap = 5.0; //consecutive panic within this window is considered the same one

// Zombie Master Live Variables
bool zm_can_start = false;
int zm_client = -1;
int zm_client_userid = -1;
int bank = 0; // bank is shared between all ZMs
float bank_rate = 0.0;
float bank_add = 0.0; // in case very small numbers need to be tracked
float t_last_update = 0.0;
float t_last_action = 0.0; // prevent ZM spamming buttons
int g_iAliveSurvivors = -1;
int max_SI = 16;
int max_unique_SI = 16;
int live_SI = 0;
bool panic = false;
float t_last_panic = 0.0;
int g_iEntities; // track number of edicts and entities
bool zm_allow_spawns = true; // in survival, prevent spawns until survivors have started timer
Handle zm_timer = INVALID_HANDLE; // zm_update timer, repeats periodically
Handle clients_timer = INVALID_HANDLE; // CountClients() timer which does not run twice if there's already a timer set to run it
char ZM_hint[128]; 
bool zm_just_died = false; // tracking ZM team swap
bool EMS_hud_ready = false; // track whether HUD was initialized
int roundcount = 0; // to avoid timers getting into new rounds
bool ZM_finale_announced = false; // tracking whether finale has started to set bank_rate=0.0
bool ZM_finale_ended = false; // prevent zombie spawns
float t_finale; // prevent finale stages from advancing too quickly
bool fallen_spawned = false; // spawn fallen survivor once per round
bool jimmy_spawned = false; // spawn jimmy gibbs jr once per round
int panic_target = -1; // legacy
int lastdoor = -1;
bool manual_panic = false; // track whether panic was started by game or by ZM
int script_CommonLimit = -1;
bool scope_changed = false;
float t_scope_change = 0.0;
bool survival_activated = false; // track if survival panic button was activated but ZM isn't present
//bool manual_change = false; // track if finale stage was just forced manually
char targetName_pending[64]; // pending targetname for takeover tank
int maxhp_pending = 0; // pending max hp for takeover tank
bool active_looktarget = false; // live update HP for special infected ZM is looking at
bool arr_biled[MAXPLAYERS] = {false, ...};
int arr_hp[MAXPLAYERS] = {-1, ...}; // caching survivor hp
Handle hp_timers[MAXENTITIES] = {INVALID_HANDLE, ...}; // prevent extremely frequent glow updates
bool l4d2_specials = true;
bool force_started = false;
bool g_bMapStarted = false;

float zm_target_pos[3];
float zm_spawner_pos[3];
Address zm_spawner_navArea;
int zm_spawner_navAttrFlags, zm_spawner_navSpawnAttrs;
int zm_spawner_state;
float t_last_spawner_update;
float t_last_spawner_sound;
int g_iLaser = 0;
int g_iHalo = 0;

ConVar g_hCvarMPGameMode;
char g_sCvarMPGameMode[32];

#define PANIC_OFF 0 // Panic is OFF
#define PANIC_SINGLE 1 // Single panic event, started by ZM or basic info_director panic call
#define PANIC_SCRIPTED 2 // Scripted panic event, reset panic timer with each stage
#define PANIC_NUT 3 // Onslaught and other mob events that may last indefinitely.

// Notify ZM about being able to control units with USE
bool zm_use_notify = false;

ConVar g_hBankRateBase, g_hBankRatePlayer, g_hBankInitial, g_hBankInitialPlayer, g_hStopInactivity, g_hMaxUniqueSI,
       g_hUpdateRate, g_hMaxCommons, g_hSpawnMinDistance, g_hBonusCarAlarm, g_hBonusFinaleStage, g_hPanicCost,
       g_hCostBoomer, g_hCostSpitter, g_hCostHunter, g_hCostSmoker, g_hCostJockey, g_hMaxWitches, g_hMaxSI, g_hSpecialCooldown,
       g_hCostCharger, g_hCostTank, g_hCostWitchStatic, g_hCostWitchMoving, g_hCostCommon, g_hCostUncommon, g_hLockSaferoom,
       g_hCommonRate, g_hWitchCooldown, g_hTankCooldown, g_hMinFinaleStage, g_hPanicDuration;

float g_fBankRateBase,g_fBankRatePlayer,g_fUpdateRate,g_fSpawnMinDistance,g_fStopInactivity,g_fSpecialCooldown,
g_fCommonRate, g_fWitchCooldown, g_fTankCooldown, g_fMinFinaleStage, g_fPanicDuration;

int g_iBankInitial,g_iBankInitialPlayer, g_iPanicCost;

int costs_SI[9];
int live_zombie_arr[9];
int available_SI;
int available_zombie_arr[9];
int max_zombie_arr[9];
int g_iCostCommon, g_iCostUncommon, g_iCostWitchStatic, g_iCostWitchMoving, g_iBonusCarAlarm, g_iBonusFinaleStage, g_iMaxWitches, g_iMaxSI, g_iMaxUniqueSI;

bool g_bLockSaferoom;

int info_director = -1;
//Address EventManager;
//Address CDirector;

Action Timer_Free_Angry_Zombies(Handle timer, int count)
{
     if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return Plugin_Stop;
     CountCommons();
     if (live_zombie_arr[ZOMBIECLASS_COMMON]>=count) return Plugin_Stop;
     
     count = count - live_zombie_arr[ZOMBIECLASS_COMMON];
     if (count<=0) return Plugin_Stop;
     int target = L4D_GetHighestFlowSurvivor();
     spawn_free_angry_zombies(target,count);
     
     // There is a rare crash:
     // [DHOOKS] FATAL: Failed to find return address of original function. Check the arguments and return type of your detour setup.
     // When we call free_angry zombies when the mob spawn timer has JUST been reset (on the same tick).
     // Probably can be fixed by checking the mobspawntimer and delaying running this if timer is exactly at 0.0 elapsed time.
     
     return Plugin_Stop;  
}

public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	
	if (strcmp(key, "CommonLimit", false) == 0)
	{
	    script_CommonLimit = retVal;
       	retVal = 0;
       	//if (ZM_finale_announced || panic) retVal = 1;
       	//else retVal = 0;
       	return Plugin_Handled;
	}
	
	return Plugin_Continue;
	
}

//public void L4D_OnReplaceTank(int tank, int newtank)
//{
//	if (!g_bCvarAllow) return;
//	
//	int health1 = GetEntProp(tank,Prop_Data,"m_iHealth");
//	int health2 = GetEntProp(newtank,Prop_Data,"m_iHealth");
//	char targetName1[64], targetName2[64];
//    GetEntPropString(tank, Prop_Data, "m_iName", targetName1, sizeof(targetName1));
//    GetEntPropString(newtank, Prop_Data, "m_iName", targetName2, sizeof(targetName2));
//	PrintToServer("[zm] L4D_OnReplaceTank %d %s (%d HP) -> %d %s (%d HP)", tank, targetName1, health1, newtank, targetName2, health2);
//}

//public Action L4D_OnTakeOverBot(int client)
//{
//	if (!g_bCvarAllow) return Plugin_Continue;
//	int health1 = GetEntProp(client,Prop_Data,"m_iHealth");
//	PrintToServer("[zm] L4D_OnTakeOverBot %d, %d HP", client, health1);
//	return Plugin_Continue;
//}

//public Action L4D_OnSpawnTank(const float vecPos[3], const float vecAng[3])
//{
//	if (!g_bCvarAllow) return Plugin_Continue;
//	PrintToServer("[zm] L4D_OnSpawnTank");
//	return Plugin_Continue;
//}

//public void L4D_OnSpawnTank_Post(int client, const float vecPos[3], const float vecAng[3])
//{
//	if (!g_bCvarAllow) return;
//	int health1 = GetEntProp(client,Prop_Data,"m_iHealth");
//	PrintToServer("[zm] L4D_OnSpawnTank_Post %d, %d HP", client, health1);
//}

//public void L4D_OnTakeOverBot_Post(int client, bool success)
//{
//	if (!g_bCvarAllow) return;
//	int health1 = GetEntProp(client,Prop_Data,"m_iHealth");
//	PrintToServer("[zm] L4D_OnTakeOverBot_Post %d %d, %d HP", client, success, health1);
//}

public void OnEntityCreated(int entity, const char[] classname)
{
	switch (classname[0])
	{
    	case 'i':
    	{
        	if (live_zombie_arr[ZOMBIECLASS_COMMON]>0) return;
        	if (StrEqual(classname,"infected",false)) CountCommons(false);
    	}
	}
}

bool is_zm_spamming()
{
    float t_now = GetEngineTime();
    if ( (t_now-t_last_action)<=0.11 ) // typical tickrate is 30
    {
        update_hint("%T", "STOP SPAMMING", zm_client);
        t_last_action = t_now;
        return true;
    }
    t_last_action = t_now;
    return false;
}



public void OnDirectorOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    if (DEBUG) PrintToServer("[zm] info_director output %s fired! %d %d %f", output, activator, caller, delay);
    
    if (!ZM_finale_announced)
    {
        // Scripted panic event - may last a while and need revival.
       	if (strcmp(output,"OnCustomPanicStageFinished")==0)
       	{
           	manual_panic = false;
           	update_panic();
       	}
        create_common_menu();
        create_uncommon_menu();
    }
}

public void OnInfoZombieSpawnOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    if (DEBUG) PrintToServer("[zm] info_zombie_spawn output %s fired! %d %d %f", output, activator, caller, delay);
}

public void OnCommentarySpawnerOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    if (DEBUG) PrintToServer("[zm] commentary_zombie_spawner output %s fired! %d %d %f", output, activator, caller, delay);
}

float commons_add = 0.0; // in case rate is very slow

int entref_control = INVALID_ENT_REFERENCE; // track the last special infected ZM looked at
int entref_delete = INVALID_ENT_REFERENCE; // track the last zombie ZM looked at

int g_iGlowList[MAXENTITIES] = {INVALID_ENT_REFERENCE, ...}; // track glow children of parent entities

// Prep time for coop only
ConVar g_hPrepTimeZM;
float g_fPrepTimeZM;
float t_zm_join = 0.0;

int g_iLockedDoor = INVALID_ENT_REFERENCE;
//int g_iFirstFlags = -1;
float saferoom_cooldown = 5.0;
bool saferoom_locked = false;
float t_last_join = 0.0;

// enum for spawner state
#define SPAWNER_BLOCKED 0 // can never spawn infected here
#define SPAWNER_CONDITIONAL 1 // cannot spawn here temporarily because survivors can see or are too close
#define SPAWNER_ALLOWED 2 // can spawn infected here
static int color_blocked[4] = {255,0,0,128};
static int color_conditional[4] = {0,0,255,128};
static int color_allowed[4] = {0,255,0,128};
static int RGB_ZM = 16777215; // white for outlines
static int color_unit_select[4] = {255,255,255,128};

#define SOUND_BLOCKED "ui/beep_error01.wav"
#define SOUND_CONDITIONAL "ui/menu_invalid.wav"
//#define SOUND_ALLOWED "ui/menu_focus.wav"
#define SOUND_ALLOWED "ui/littlereward.wav" // try beepclear.wav

// Kick AFK ZM due to inactivity
float t_zm_activity = 0.0;
bool zm_kick_notify = false;
void update_t_zm_activity(float new_t = -1.0)
{
    zm_kick_notify = false;
    if (new_t<0.0) t_zm_activity = GetEngineTime();
    else t_zm_activity = new_t;
}

public void OnPluginStart()
{
	LoadTranslations("l4d2_zombie_master.phrases");
    if (DEBUG) PrintToServer("[zm] OnPluginStart");
	GetGameData();
    
    // Commands -- all clients
    RegConsoleCmd("zm_vote", VoteZM, "zm_vote yes|no. Start a vote to enable/disable Zombie Master.");
	RegConsoleCmd("zm", JoinZM_command, "Become the Zombie Master; if already ZM, open main ZM menu.");
	RegConsoleCmd("zm_horde", ZM_Spawn_Horde, "zm_horde n type angry flow. Spawns n zombies; optional type: riot ceda clown mud road; optional angry: chase survivors (more expensive). optional flow: spawn ahead of furthest survivor instead of where ZM is pointing. Order of arguments doesn't matter.");
	RegConsoleCmd("zm_witch", ZM_Spawn_Witch, "zm_witch n flow; n=0 static, n=1 moving; optional flow: spawn ahead of furthest survivor. Order of arguments doesn't matter.");
	RegConsoleCmd("zm_smoker", ZM_Smoker, "zm_smoker flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_hunter", ZM_Hunter, "zm_hunter flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_jockey", ZM_Jockey, "zm_jockey flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_spitter", ZM_Spitter, "zm_spitter flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_boomer", ZM_Boomer, "zm_boomer flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_charger", ZM_Charger, "zm_charger flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_tank", ZM_Tank, "zm_tank flow; optional flow to spawn ahead of furthest survivor, otherwise spawn where ZM is looking.");
	RegConsoleCmd("zm_delete", ZM_Delete, "Delete last infected unit Zombie Master was looking at.");
	RegConsoleCmd("zm_delete_all", ZM_Delete_All, "Delete ALL zombies.");
	RegConsoleCmd("zm_delete_common", ZM_Delete_Commons, "Delete all common and uncommon infected.");
    RegConsoleCmd("zm_delete_specials", ZM_Delete_Specials, "Delete all special infected.");
    RegConsoleCmd("zm_delete_witches", ZM_Delete_Witches, "Delete all witches.");
	RegConsoleCmd("zm_quit", QuitZM_Command, "Give up Zombie Master and join Survivors.");
	RegConsoleCmd("zm_panic", ZMPanic, "All Common and Uncommon Infected rush the survivors. Bank rate is reduced.");
	RegConsoleCmd("zm_start", zm_start,"Allow survivors to leave safezone; if already so, force saferoom open and start round. Can be used by ZM and admins.");
	RegConsoleCmd("zm_followme", ZM_Chase_ZM, "Panic horde will chase Zombie Master.");
	RegConsoleCmd("zm_vision", ZM_Vision, "Toggle night vision for ZM. Or press the flashlight button.");
	RegConsoleCmd("zm_teleport", ZMTeleport, "ZM will teleport to farthest flow survivor.");
	RegConsoleCmd("zm_control", ZMControlSI, "ZM will take control of the special infected that is flashing. Or press the USE button.");
	RegConsoleCmd("zm_menu", ZM_Menu, "Open specific ZM menu: main common uncommon special boss cleanup other close. Use the RELOAD button to open the main menu.");
	
	// Commands -- admins only
	RegAdminCmd("zm_addbank", zm_addbank, ADMFLAG_ROOT,"Add zombux to zombie master bank. Admins only.");
    RegAdminCmd("zm_finale_next", zm_finale_advance, ADMFLAG_ROOT,"Trigger next finale stage. Admins only.");
    RegAdminCmd("zm_debug_player", zm_debug_player, ADMFLAG_ROOT, "Debug player state. Admins only.");
    RegAdminCmd("zm_debug_mob", zm_debug_mob, ADMFLAG_ROOT, "Debug mob state. Admins only.");
    RegAdminCmd("zm_debug_fog", zm_debug_fog, ADMFLAG_ROOT, "Check fog distance. Admins only.");
    
    g_hCvarDebug = CreateConVar("zm_debug", "0", "Print plugin debug info to server.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarDebug.AddChangeHook(ConVarChanged_Cvars);
    
	g_hCvarAllow = CreateConVar("zm_enable", "0", "0=Plugin off, 1=Plugin on.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
    
    g_hBankRateBase = CreateConVar("zm_bank_rate_base", "0.0", "Base ZM bank rate.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankRateBase.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankRatePlayer = CreateConVar("zm_bank_rate_player", "4.0", "Additional ZM bank rate per alive survivor.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankRatePlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitial = CreateConVar("zm_bank_initial", "500", "Initial ZM bank.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankInitial.AddChangeHook(ConVarChanged_Cvars);
    
    g_hPanicCost = CreateConVar("zm_panic_cost", "200", "Horde panic cost.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hPanicCost.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hPanicDuration = CreateConVar("zm_panic_duration", "30", "Horde panic duration.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hPanicDuration.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitialPlayer = CreateConVar("zm_bank_initial_player", "350", "Additional initial ZM bank per extra player.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankInitialPlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hUpdateRate = CreateConVar("zm_updaterate", "0.25", "Update rate for periodic ZM checks.",FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_hUpdateRate.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxCommons = CreateConVar("zm_maxcommons", "100", "ZM max number of common zombies.",FCVAR_NOTIFY, true, 0.0, true, 1000.0);
    g_hMaxCommons.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hSpawnMinDistance = CreateConVar("zm_spawndistance", "500", "ZM minimum spawn distance.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hSpawnMinDistance.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCostBoomer = CreateConVar("zm_cost_boomer", "150", "ZM boomer cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostBoomer.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostSpitter = CreateConVar("zm_cost_spitter", "200", "ZM spitter cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostSpitter.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostHunter = CreateConVar("zm_cost_hunter", "200", "ZM hunter cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostHunter.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostSmoker = CreateConVar("zm_cost_smoker", "200", "ZM smoker cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostSmoker.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostJockey = CreateConVar("zm_cost_jockey", "200", "ZM jockey cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostJockey.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostCharger = CreateConVar("zm_cost_charger", "200", "ZM charger cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostCharger.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostTank = CreateConVar("zm_cost_tank", "2000", "ZM tank cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostTank.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostWitchStatic = CreateConVar("zm_cost_witch_static", "600", "ZM static witch cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostWitchStatic.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostWitchMoving = CreateConVar("zm_cost_witch_moving", "500", "ZM moving witch cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostWitchMoving.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostCommon = CreateConVar("zm_cost_common", "5", "ZM common infected cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostUncommon = CreateConVar("zm_cost_uncommon", "25", "ZM uncommon infected cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hBonusCarAlarm = CreateConVar("zm_bonus_car_alarm", "400", "Award ZM points for triggered car alarm.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hBonusCarAlarm.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBonusFinaleStage = CreateConVar("zm_bonus_finale", "250", "ZM bank reward per player for advancing to the next Finale stage. Free tanks spawn automatically.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hBonusFinaleStage.AddChangeHook(ConVarChanged_Cvars);
    
    g_hLockSaferoom = CreateConVar("zm_lock_saferoom", "1", "Prevent players from leaving safezone only if: there is a ZM, zm prep time is over, and players have stopped joining.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hLockSaferoom.AddChangeHook(ConVarChanged_Cvars);
    
    g_hStopInactivity = CreateConVar("zm_inactivity", "120.0", "Seconds of inactivity before the ZM is replaced. 0 to disable.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
    g_hStopInactivity.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxWitches = CreateConVar("zm_max_witches", "-1.0", "Max number of witches: -1 for automatic AliveSurvivors, otherwise whatever number is given.",FCVAR_NOTIFY, true, -1.0, true, 10000000.0);
    g_hMaxWitches.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hMaxSI = CreateConVar("zm_max_SI", "-1.0", "Max number of total alive special infected: -1 for automatic AliveSurvivors, otherwise whatever number is given.",FCVAR_NOTIFY, true, -1.0, true, 10000000.0);
    g_hMaxSI.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hMaxUniqueSI = CreateConVar("zm_max_unique_SI", "-1.0", "Max number of each special infected class: -1 for automatic ceil(AliveSurvivors/2), otherwise whatever number is given.",FCVAR_NOTIFY, true, -1.0, true, 10000000.0);
    g_hMaxUniqueSI.AddChangeHook(ConVarChanged_Cvars_ZMenu);
	
	g_hPrepTimeZM = CreateConVar("zm_preptime", "60.0", "Seconds of zombie master prep time before survivors can leave safe zone.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hPrepTimeZM.AddChangeHook(ConVarChanged_Cvars);
	
	g_hCommonRate = CreateConVar("zm_common_rate", "1.5", "Commons per second made available to spawn in the zombie pool.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hCommonRate.AddChangeHook(ConVarChanged_Cvars);
	
	g_hWitchCooldown = CreateConVar("zm_witch_cooldown", "60.0", "Witch cooldown.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hWitchCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hTankCooldown = CreateConVar("zm_tank_cooldown", "90.0", "Tank cooldown.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hTankCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hSpecialCooldown = CreateConVar("zm_special_cooldown", "20.0", "Cooldown for special infected spawns.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hSpecialCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hMinFinaleStage = CreateConVar("zm_min_finale_stage", "60.0", "Minimum gap between ZM rewards during Finale.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hMinFinaleStage.AddChangeHook(ConVarChanged_Cvars);
	
	GetCvars();

	g_iAliveSurvivors = -1;
	zm_client = -1;

	// Removes the boundaries for z_max_player_zombies and notify flag
	z_max_player_zombies = FindConVar("z_max_player_zombies");
	int flags = z_max_player_zombies.Flags;
	SetConVarBounds(z_max_player_zombies, ConVarBound_Upper, false);
	SetConVarFlags(z_max_player_zombies, flags & ~FCVAR_NOTIFY);
  	
  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.GetString(g_sCvarMPGameMode, sizeof(g_sCvarMPGameMode));
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);

	
}

#define ZM_MENU_CLOSED 0
#define ZM_MENU_MAIN 1
#define ZM_MENU_COMMON 2
#define ZM_MENU_UNCOMMON 3
#define ZM_MENU_SPECIAL 4
#define ZM_MENU_BOSS 5
#define ZM_MENU_CLEANUP 6
#define ZM_MENU_OTHER 7
int zm_menu_state = ZM_MENU_CLOSED;

Menu menu_main = null;
Menu menu_common = null;
Menu menu_uncommon = null;
Menu menu_special = null;
Menu menu_boss = null;
Menu menu_cleanup = null;
Menu menu_other = null;

void close_menus(int client)
{
    if (!IsValidClient(client)) return;
    //if(GetClientMenu(client) != MenuSource_None) CancelClientMenu(client,true);
    //if (zm_menu_state>ZM_MENU_CLOSED || client!=zm_client)
    //{
    //    //menu_main.Display(client,1);
    //}
    InternalShowMenu(client, "\10", 1); // thanks to Zira
    CancelClientMenu(client, true, null);
    if (client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
    //CancelClientMenu(client,true);
}

//public int Menu_DoNothing(Menu menu, MenuAction action, int param1, int param2)
//{
//    switch (action)
//    {
//        case MenuAction_End:
//        {
//            delete menu;
//        }
//    }
//    return 0;
//} 

void open_menu(int client, int MENU=ZM_MENU_MAIN, int time=MENU_TIME_FOREVER)
{
    
    //if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
    
    if (client!=zm_client)
    {
        close_menus(client);
        return;
    }
    
    if (!IsValidClientZM()) return;
    
    if (menu_main==null) update_menus();
    
    if (MENU<ZM_MENU_CLOSED || MENU>ZM_MENU_OTHER) MENU = ZM_MENU_MAIN;
    if (MENU==ZM_MENU_CLOSED) time = 1;
    
    switch(MENU)
    {
        case ZM_MENU_MAIN: menu_main.Display(zm_client,time);
        case ZM_MENU_COMMON: menu_common.Display(zm_client,time);
        case ZM_MENU_UNCOMMON: menu_uncommon.Display(zm_client,time);
        case ZM_MENU_SPECIAL: menu_special.Display(zm_client,time);
        case ZM_MENU_BOSS: menu_boss.Display(zm_client,time);
        case ZM_MENU_CLEANUP: menu_cleanup.Display(zm_client,time);
        case ZM_MENU_OTHER: menu_other.Display(zm_client,time);
        case ZM_MENU_CLOSED: close_menus(zm_client);
        default: menu_main.Display(zm_client,time);
    }
    
    zm_menu_state = MENU;
    
}

void reopen_zm_menu(bool force = true)
{
    if (zm_menu_state == ZM_MENU_CLOSED || !IsValidClientZM()) return;
    if (force || GetClientMenu(zm_client)==MenuSource_None)
    {
        open_menu(zm_client,zm_menu_state);
        if (DEBUG) PrintToServer("[zm] Reopened menu.");
    }
}

// MAIN MENU
void create_main_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_main_menu");
	if (menu_main!=INVALID_HANDLE) CloseHandle(menu_main);
	menu_main = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),main_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Zombie Master", zm_language);
	menu_main.SetTitle(buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    AddMenuItem(menu_main, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
    AddMenuItem(menu_main, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
    AddMenuItem(menu_main, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
    AddMenuItem(menu_main, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
    AddMenuItem(menu_main, "4", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Teleport", zm_language);
    AddMenuItem(menu_main, "5", buffer);

	menu_main.ExitButton = true;
	SetMenuOptionFlags(menu_main,MENUFLAG_NO_SOUND);
}
int main_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: open_menu(zm_client,ZM_MENU_COMMON);
            	case 1: open_menu(zm_client,ZM_MENU_SPECIAL);
            	case 2: open_menu(zm_client,ZM_MENU_BOSS);
            	case 3: open_menu(zm_client,ZM_MENU_CLEANUP);
            	case 4: open_menu(zm_client,ZM_MENU_OTHER);
            	case 5: { ZMTeleport(zm_client,0); open_menu(zm_client,ZM_MENU_MAIN); }
            	default: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }
	return 0;
}

// COMMON MENU
void create_common_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_common_menu");
	if (menu_common!=INVALID_HANDLE) CloseHandle(menu_common);
	menu_common = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),common_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
    	
    Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
	menu_common.SetTitle(buffer);
    
    Format(buffer,sizeof(buffer),"%T x5 %d", "Common", zm_language, g_iCostCommon*5);
    AddMenuItem(menu_common, "0", buffer);
    Format(buffer,sizeof(buffer),"%T x10 %d", "Common", zm_language, g_iCostCommon*10);
    AddMenuItem(menu_common, "1", buffer);
    Format(buffer,sizeof(buffer),"%T x20 %d", "Common", zm_language, g_iCostCommon*20);
    AddMenuItem(menu_common, "2", buffer);
    Format(buffer,sizeof(buffer),"%T", "Uncommon", zm_language);
    AddMenuItem(menu_common, "3", buffer);
    
    if (L4D_IsSurvivalMode() || ZM_finale_announced)
       AddMenuItem(menu_common, "4", "-");
    else
    {
        Format(buffer,sizeof(buffer),"%T %d", "PANIC", zm_language, g_iPanicCost);
        AddMenuItem(menu_common, "4", buffer);
    }
    
    AddMenuItem(menu_common, "5", "-");
    AddMenuItem(menu_common, "6", "<-- (R)");

	menu_common.ExitButton = true;
	SetMenuOptionFlags(menu_common,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_COMMON && IsValidClientZM()) open_menu(zm_client,ZM_MENU_COMMON);
}
int common_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: {ZM_Horde(zm_client,5); open_menu(zm_client,ZM_MENU_COMMON);}
            	case 1: {ZM_Horde(zm_client,10); open_menu(zm_client,ZM_MENU_COMMON);}
            	case 2: {ZM_Horde(zm_client,20); open_menu(zm_client,ZM_MENU_COMMON);}
            	case 3: open_menu(zm_client,ZM_MENU_UNCOMMON);
            	case 4:
            	{
                	if (!L4D_IsSurvivalMode() && !ZM_finale_announced && !L4D_IsFinaleActive()) ZMPanic(zm_client,0);
                	open_menu(zm_client,ZM_MENU_COMMON);
            	}
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

// UNCOMMON MENU
void create_uncommon_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_uncommon_menu");
	if (menu_uncommon!=INVALID_HANDLE) CloseHandle(menu_uncommon);
	menu_uncommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),uncommon_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
	menu_uncommon.SetTitle(buffer);
    
    Format(buffer,sizeof(buffer),"%T %d", "Riot", zm_language, g_iCostUncommon);
    AddMenuItem(menu_uncommon, "0", buffer);
    Format(buffer,sizeof(buffer),"%T %d", "CEDA", zm_language, g_iCostUncommon);
    AddMenuItem(menu_uncommon, "1", buffer);
    Format(buffer,sizeof(buffer),"%T %d", "Clown", zm_language, g_iCostUncommon);
    AddMenuItem(menu_uncommon, "2", buffer);
    Format(buffer,sizeof(buffer),"%T %d", "Mud", zm_language, g_iCostUncommon);
    AddMenuItem(menu_uncommon, "3", buffer);
    Format(buffer,sizeof(buffer),"%T %d", "Road", zm_language, g_iCostUncommon);
    AddMenuItem(menu_uncommon, "4", buffer);
    
    if (!panic && !L4D_IsSurvivalMode() && !ZM_finale_announced)
    {
        Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, g_iCostUncommon);
        AddMenuItem(menu_uncommon, "5", buffer);
    }
    else AddMenuItem(menu_uncommon, "5", "-");
    
    AddMenuItem(menu_uncommon, "6", "<-- (R)");

	menu_uncommon.ExitButton = true;
	SetMenuOptionFlags(menu_uncommon,MENUFLAG_NO_SOUND);
}
int uncommon_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Horde(zm_client,1,"riot");
            	case 1: ZM_Horde(zm_client,1,"ceda");
            	case 2: ZM_Horde(zm_client,1,"clown");
            	case 3: ZM_Horde(zm_client,1,"mud");
            	case 4: ZM_Horde(zm_client,1,"road");
            	case 5: ZM_Horde(zm_client,1,"",true);
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	if (param2!=6) open_menu(zm_client,ZM_MENU_UNCOMMON);
        	
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

// SPECIAL MENU
void create_special_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_menu_special");
	if (menu_special!=INVALID_HANDLE) CloseHandle(menu_special);
	menu_special = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),special_menu_Handler);
    
    int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
    int occupied;
    int max;
    
    Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
	menu_special.SetTitle(buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_BOOMER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_BOOMER], live_zombie_arr[ZOMBIECLASS_BOOMER]);
    //FormatEx(buffer,sizeof(buffer),"Boomer %d %d/%d", costs_SI[ZOMBIECLASS_BOOMER], occupied, max);
    Format(buffer,sizeof(buffer),"%T %d %d/%d", "Boomer", zm_language, costs_SI[ZOMBIECLASS_BOOMER], occupied, max);
    AddMenuItem(menu_special, "0", buffer);
    
    if (l4d2_specials)
    {
        max = max_zombie_arr[ZOMBIECLASS_SPITTER];
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SPITTER], live_zombie_arr[ZOMBIECLASS_SPITTER]);
        //FormatEx(buffer,sizeof(buffer),"Spitter %d %d/%d", costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Spitter", zm_language, costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
        AddMenuItem(menu_special, "1", buffer);
    }
    else AddMenuItem(menu_special, "1", "-");
    
    max = max_zombie_arr[ZOMBIECLASS_SMOKER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SMOKER], live_zombie_arr[ZOMBIECLASS_SMOKER]);
    //FormatEx(buffer,sizeof(buffer),"Smoker %d %d/%d", costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    Format(buffer,sizeof(buffer),"%T %d %d/%d", "Smoker", zm_language, costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    AddMenuItem(menu_special, "2", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_HUNTER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_HUNTER], live_zombie_arr[ZOMBIECLASS_HUNTER]);
    //FormatEx(buffer,sizeof(buffer),"Hunter %d %d/%d", costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    Format(buffer,sizeof(buffer),"%T %d %d/%d", "Hunter", zm_language, costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    AddMenuItem(menu_special, "3", buffer);
    
    if (l4d2_specials)
    {
        max = max_zombie_arr[ZOMBIECLASS_JOCKEY];
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_JOCKEY], live_zombie_arr[ZOMBIECLASS_JOCKEY]);
        //FormatEx(buffer,sizeof(buffer),"Jockey %d %d/%d", costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Jockey", zm_language, costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
        AddMenuItem(menu_special, "4", buffer);
    }
    else AddMenuItem(menu_special, "4", "-");
    
    if (l4d2_specials)
    {
        max = max_zombie_arr[ZOMBIECLASS_CHARGER];
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_CHARGER], live_zombie_arr[ZOMBIECLASS_CHARGER]);
        //FormatEx(buffer,sizeof(buffer),"Charger %d %d/%d", costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Charger", zm_language, costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
        AddMenuItem(menu_special, "5", buffer);
    }
    else AddMenuItem(menu_special, "5", "-");
    
    AddMenuItem(menu_special, "6", "<-- (R)");

	menu_special.ExitButton = true;
	SetMenuOptionFlags(menu_special,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_SPECIAL && IsValidClientZM()) open_menu(zm_client,ZM_MENU_SPECIAL);
}
int special_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Boomer(zm_client,0);
            	case 1: ZM_Spitter(zm_client,0);
            	case 2: ZM_Smoker(zm_client,0);
            	case 3: ZM_Hunter(zm_client,0);
            	case 4: ZM_Jockey(zm_client,0);
            	case 5: ZM_Charger(zm_client,0);
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	if (param2!=6) open_menu(zm_client,ZM_MENU_SPECIAL);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

// BOSS MENU
void create_boss_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_menu_boss");
	if (menu_boss!=INVALID_HANDLE) CloseHandle(menu_boss);
	menu_boss = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),boss_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
	menu_boss.SetTitle(buffer);
    
    //FormatEx(buffer,sizeof(buffer),"Witch Moving %d", g_iCostWitchMoving);
    Format(buffer, sizeof(buffer), "%T %d", "Witch Moving", zm_language, g_iCostWitchMoving);
    AddMenuItem(menu_boss, "0", buffer);
    //FormatEx(buffer,sizeof(buffer),"Witch Static %d", g_iCostWitchStatic);
    Format(buffer, sizeof(buffer), "%T %d", "Witch Static", zm_language, g_iCostWitchStatic);
    AddMenuItem(menu_boss, "1", buffer);
    
    int max = max_zombie_arr[ZOMBIECLASS_TANK];
    int occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_TANK], live_zombie_arr[ZOMBIECLASS_TANK]);
    //FormatEx(buffer,sizeof(buffer),"Tank %d %d/%d", costs_SI[ZOMBIECLASS_TANK], occupied, max);
    Format(buffer,sizeof(buffer),"%T %d %d/%d", "Tank", zm_language, costs_SI[ZOMBIECLASS_TANK], occupied, max);
    AddMenuItem(menu_boss, "2", buffer);
    
    if (jimmy_spawned) AddMenuItem(menu_boss, "3", "-");
    else
    {
        //FormatEx(buffer,sizeof(buffer),"Jimmy Gibbs Jr %d", g_iCostUncommon);
        Format(buffer, sizeof(buffer), "%T %d", "Jimmy Gibbs Jr", zm_language,g_iCostUncommon);
        AddMenuItem(menu_boss, "3", buffer);
    }
    
    if (fallen_spawned) AddMenuItem(menu_boss, "4", "-");
    else
    {
        //FormatEx(buffer,sizeof(buffer),"Fallen Survivor %d", g_iCostUncommon);
        Format(buffer, sizeof(buffer), "%T %d", "Fallen Survivor", zm_language,g_iCostUncommon);
        AddMenuItem(menu_boss, "4", buffer);
    }
    
    AddMenuItem(menu_boss, "5", "-");
    AddMenuItem(menu_boss, "6", "<-- (R)");

	menu_boss.ExitButton = true;
	SetMenuOptionFlags(menu_boss,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_BOSS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_BOSS);
}
int boss_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Witch(zm_client,WITCH_MOVING);
            	case 1: ZM_Witch(zm_client,WITCH_STATIC);
            	case 2: ZM_Tank(zm_client,0);
            	case 3: { if (!jimmy_spawned) ZM_Horde(zm_client,1,"jimmy");}
            	case 4: { if (!fallen_spawned) ZM_Horde(zm_client,1,"fallen");}
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	if (param2!=6) open_menu(zm_client,ZM_MENU_BOSS);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

// CLEANUP MENU
void create_cleanup_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_menu_cleanup");
	if (menu_cleanup!=INVALID_HANDLE) CloseHandle(menu_cleanup);
	menu_cleanup = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),cleanup_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
	menu_cleanup.SetTitle(buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Target", zm_language);
    AddMenuItem(menu_cleanup, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Commons", zm_language);
    AddMenuItem(menu_cleanup, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Specials", zm_language);
    AddMenuItem(menu_cleanup, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Witches", zm_language);
    AddMenuItem(menu_cleanup, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete ALL", zm_language);
    AddMenuItem(menu_cleanup, "4", buffer);
    
    AddMenuItem(menu_cleanup, "5", "-");
    
    AddMenuItem(menu_cleanup, "6", "<-- (R)");

	menu_cleanup.ExitButton = true;
	SetMenuOptionFlags(menu_cleanup,MENUFLAG_NO_SOUND);
}
int cleanup_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Delete(zm_client,0);
            	case 1: ZM_Delete_Commons(zm_client,0);
            	case 2: ZM_Delete_Specials(zm_client,0);
            	case 3: ZM_Delete_Witches(zm_client,0);
            	case 4: ZM_Delete_All(zm_client,0);
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	if (param2!=6) open_menu(zm_client,ZM_MENU_CLEANUP);
        	
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

// OTHER MENU
void create_other_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_menu_other");
	if (menu_other!=INVALID_HANDLE) CloseHandle(menu_other);
	menu_other = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),other_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
	menu_other.SetTitle(buffer);
    
    if (zm_stage>=ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Control (USE)", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Start Round", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else 
        AddMenuItem(menu_other, "0", "-");
    
    Format(buffer, sizeof(buffer), "%T", "Toggle Rain", zm_language);
    AddMenuItem(menu_other, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Toggle Snow", zm_language);
    AddMenuItem(menu_other, "2", buffer);
    
    AddMenuItem(menu_other, "3", "-");
    
    Format(buffer, sizeof(buffer), "%T", "Give Up", zm_language);
    AddMenuItem(menu_other, "4", buffer);
    
    AddMenuItem(menu_other, "5", "-");
    
    AddMenuItem(menu_other, "6", "<-- (R)");

	menu_other.ExitButton = true;
	SetMenuOptionFlags(menu_other,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_OTHER && IsValidClientZM()) open_menu(zm_client,ZM_MENU_OTHER);
	
}
int other_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: 
            	{
                	if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED) zm_start(zm_client,0);
                	else
                	{
                    	if (zm_stage==ZM_STARTED)
                    	{
                        	if (live_SI>0) ZMControlSI(zm_client,0);
                        	else {open_menu(zm_client,ZM_MENU_SPECIAL); return 0;}
                    	}
                	}
            	}
            	case 1: ZM_Rain_Toggle(zm_client);
            	case 2: ZM_Snow_Toggle(zm_client);
            	case 4: {QuitZM(zm_client); return 0;}
            	case 6: open_menu(zm_client,ZM_MENU_MAIN);
        	}
        	if (param2!=6) open_menu(zm_client,ZM_MENU_OTHER);        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else if (param2==MenuCancel_NoDisplay || param2==MenuCancel_Timeout) reopen_zm_menu(true);
           }
        }
    }

	return 0;
}

void update_menus()
{
    create_main_menu();
    create_other_menu();
    create_cleanup_menu();
    create_boss_menu();
    create_special_menu();
    create_uncommon_menu();
    create_common_menu();
}

// Pre-computed navmeshes storage

enum struct PreCalcNav
{
	float position[3];     // World position
	Address navArea;       // Nav area reference
}
ArrayList g_hObscuredList;  // ArrayList of PreCalcNav structs
ArrayList g_hStartAreaList; // ArrayList of PreCalcNav structs
bool g_bNavReady = false;    // Is pre-computation complete?

int bank_track_numplayers = 0; //tracking if more bank should be added when more survivors appear

void set_bank_begin()
{
    
    if (g_iAliveSurvivors<=0) CountClients();
    if (L4D_IsSurvivalMode())
    {
        bank = g_iBonusFinaleStage*g_iAliveSurvivors;
    }
    else
    {
        bank = g_iBankInitial;
        bank += g_iBankInitialPlayer*g_iAliveSurvivors;
    }
    bank_track_numplayers = g_iAliveSurvivors;
    
    bank_add = 0.0;
    commons_add = 0.0;
}

void update_hint(const char[] myString, any ...)
{
	if (!IsValidClientZM()) return;
	char[] myFormattedString = new char[128];
	VFormat(myFormattedString,128,myString,2);
    FormatEx(ZM_hint,sizeof(ZM_hint),"%s",myFormattedString);
    update_EMS_HUD();
    active_looktarget = false;
}

// ZM Pointer

void update_ZM_spawner(float target_pos[3], float spawner_pos[3], int state, bool draw=true)
{
  
    if (draw && IsValidClientZM() && g_iLaser>0 && g_iHalo>0)
    {
        int color[4];
        if (state==SPAWNER_BLOCKED) color = color_blocked;
        else if (state==SPAWNER_CONDITIONAL) color = color_conditional;
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
            if (state==SPAWNER_BLOCKED) sound_name = SOUND_BLOCKED;
            else if (state==SPAWNER_CONDITIONAL) sound_name = SOUND_CONDITIONAL;
            else sound_name = SOUND_ALLOWED;
            EmitSoundToClient(zm_client,sound_name,zm_client,ATTN_TO_SNDLEVEL(SNDATTN_NORMAL),_,_,0.1,_,_,draw_pos,_,true);
            t_last_spawner_sound = t_now;
        }
        
        t_last_spawner_update = t_now;
        
    }

    zm_target_pos = target_pos;
    zm_spawner_pos = spawner_pos;
    zm_spawner_state = state;
    
} 

// Allow witches to be spawned in weird places
bool nav_can_spawn_zombies(int navAttributeFlags, int navSpawnAttributes, bool witch = false)
{
    if (navSpawnAttributes & NAV_SPAWN_PLAYER_START) return false;
    if (navSpawnAttributes & NAV_SPAWN_CHECKPOINT) return false;
    if (navSpawnAttributes & NAV_SPAWN_RESCUE_CLOSET) return false;
    if (!witch && (navAttributeFlags & NAV_BASE_OUTSIDE_WORLD)) return false;
    if (!witch && (navSpawnAttributes & NAV_SPAWN_BATTLESTATION)) return false;
    if ( (navSpawnAttributes & NAV_SPAWN_OBSCURED) || (navSpawnAttributes & NAV_SPAWN_IGNORE_VISIBILITY)) return true; // always spawn
    return true;
}

// True to allow the current entity to be hit, otherwise false.
static bool FilterSpawner(int entity, int mask, int self)
{
	if (!IsValidEntity(entity)) return false;
	if (entity==self) return false;
	if (GetEntProp(entity,Prop_Data,"m_iHealth")>0) return false;
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

// asdf to do make foliage hit trace
bool can_any_alive_survivor_see(float vecPos[3], bool hint = true)
{
   
   if (DEBUG) PrintToServer("[zm] can_any_alive_survivor_see");
   
   int filter_client = -1;
   if (IsValidClientZM()) filter_client = zm_client;
   
   //Check fog
   float pos[3];
   bool skip = true;
   bool skipList[MAXPLAYERS] = {true, ...};
   for( int i = 1; i <= MaxClients; i++ )
   {
         if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
         {
           GetClientAbsOrigin(i,pos);
           if (GetVectorDistance(pos,vecPos)<fog_distance)
           {
               skip=false;
               skipList[i] = false;
           }
         }
   }
   
   float VecPos2[3]; AddVectors(vecPos,{0.0,0.0,HULL_DZ},VecPos2);
   float VecPos3[3]; AddVectors(vecPos,{-HULL_DX,-HULL_DX,HULL_DZ},VecPos3);
   float VecPos4[3]; AddVectors(vecPos,{HULL_DX,HULL_DX,HULL_DZ},VecPos4);
   float VecPos5[3]; AddVectors(vecPos,{HULL_DX,-HULL_DX,HULL_DDZ},VecPos5);
   float VecPos6[3]; AddVectors(vecPos,{0.0,0.0,HULL_DDZ},VecPos6);
   
   //float hitPos[3];
   //int temp_dist1,temp_dist2;
   
   // asdf to do: check trace from saferoom door and see distance from hit pos to vecpos
   
   // Check line of sight with saferoom door
   if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
   {
        int door = EntRefToEntIndex(g_iLockedDoor);
        float saferoom_pos[3];
        //GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecOrigin", saferoom_pos);
        L4D_GetEntityWorldSpaceCenter(door,saferoom_pos);
        saferoom_pos[2] -= 10.0;
        
        if (GetVectorDistance(saferoom_pos,vecPos)<fog_distance)
        {
        
            //float vMins[3], vMaxs[3];
            //GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecMins", vMins);
            //GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecMaxs", vMaxs);
            //saferoom_pos[2] += (vMaxs[2]-vMins[2])/2.0;
         
            //PrintToServer("[zm] Checking saferoom visibility");
            //TE_SetupBeamPoints(vecPos,saferoom_pos,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,4.0,1,1.0,color_allowed,0);
            //	TE_SendToClient(zm_client);
        
            Handle trace = TR_TraceRayFilterEx(vecPos,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                //PrintToServer("[zm] Hit %d, saferoom is %d", hit_entity, door);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
                
                //TR_GetEndPosition(hitPos, trace);
                //GetVectorDistance(hitPos,saferoom_pos)
                //temp_dist1 = L4D2_NavAreaTravelDistance(saferoom_pos,hitPos,false);
                //temp_dist2 = L4D2_NavAreaTravelDistance(hitPos,saferoom_pos,false);
                
            }
            //else PrintToServer("[zm] Hit nothing");
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos2,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos3,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos4,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos5,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos6,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==door)
                {
                   if (hint) update_hint("%T", "Visible saferoom", zm_client);
                   delete trace;
                   return true;
                }
            }
            delete trace;
        
        }
   }
   
   if (skip) return false;
   
   for( int i = 1; i <= MaxClients; i++ )
   {
      
        if (skipList[i]) continue;
        
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,vecPos))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos2))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos3))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos4))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos5))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos6))
        {
           if (hint) update_hint("%T", "Visible survivors", zm_client);
           return true;
        }
        
        // asdf check back and forth ray trace for distance
      
   }
   return false;
}

// Find smallest distance to survivor. Check both ways in case survivor is about to appear here.
int spawner_nearest_survivor = -1;
float min_distance_to_survivors(float vecPos[3], bool store_client=false)
{
   if (DEBUG) PrintToServer("[zm] min_distance_to_survivors");
   float min_distance = -1.0;
   float survivor_origin[3];
   float temp_dist1;
   float temp_dist2;
   float raw_dist;
   if (store_client) spawner_nearest_survivor = -1;
   for( int i = 1; i <= MaxClients; i++ )
   {
      if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
      {
        GetClientAbsOrigin(i,survivor_origin);
        raw_dist = GetVectorDistance(survivor_origin,vecPos);
        temp_dist1 = L4D2_NavAreaTravelDistance(vecPos,survivor_origin,false);
        if (temp_dist1<raw_dist) temp_dist1 = raw_dist;
        if (temp_dist1>=0.0 && (min_distance<0.0 || temp_dist1<min_distance))
        {
            min_distance = temp_dist1;
            if (store_client) spawner_nearest_survivor = i;
        }
        
        if (zm_stage>=ZM_STARTED)
        {
            temp_dist2 = L4D2_NavAreaTravelDistance(survivor_origin,vecPos,false);
            if (temp_dist2<raw_dist) temp_dist2 = raw_dist;
            if (temp_dist2>=0.0 && (min_distance<0.0 || temp_dist2<min_distance))
            {
                min_distance = temp_dist2;
                if (store_client) spawner_nearest_survivor = i;
            }
        }
        
      }
   }
   
    // Check saferoom door
    if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
    {
         L4D_GetEntityWorldSpaceCenter(EntRefToEntIndex(g_iLockedDoor),survivor_origin);
         raw_dist = GetVectorDistance(survivor_origin,vecPos);
         temp_dist1 = L4D2_NavAreaTravelDistance(vecPos,survivor_origin,false);
         if (temp_dist1<raw_dist) temp_dist1 = raw_dist;
         if (temp_dist1>=0.0 && (min_distance<0.0 || temp_dist1<min_distance)) min_distance = temp_dist1;
    }
   
   return min_distance;

}

static float obscured_max_dist = 300.0;
bool relocate_spawner_obscured(float vPos_spawner[3])
{
    if (!g_bNavReady || g_hObscuredList.Length<=0 || g_hObscuredList.Length>40) return false;
    
    PreCalcNav cell;
    Address temp_navArea;
    float vPos[3];
    float dist;
    for (int i = 0; i < g_hObscuredList.Length; i++)
	{
    	g_hObscuredList.GetArray(i, cell);
    	temp_navArea = cell.navArea;
    	L4D_FindRandomSpot(temp_navArea,vPos);
    	dist = L4D2_NavAreaTravelDistance(vPos,vPos_spawner,true);
    	//PrintToServer("[zm] Relocate check %f", dist);
    	if (dist>=0.0 && dist<=obscured_max_dist)
    	{
        	//PrintToServer("[zm] Relocated spawner to obscured");
        	TE_SetupBeamPoints(vPos_spawner,vPos,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,4.0,1,1.0,color_allowed,0);
        	TE_SendToClient(zm_client);
        	vPos_spawner = vPos;
        	return true;
    	}
    	//else
    	//{
        //	if (IsValidClientZM())
        //	{
       	//        vPos[2] += 25.0;
       	//        TE_SetupBeamRingPoint(vPos,50.0,0.1,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,0.0,color_allowed,0,0);
        //        TE_SendToClient(zm_client);
        //	}
    	//}
    	
	}
	
	return false;
    
}

//native bool L4D2_IsLocationFoggedToSurvivors(float origin[3]);

#define SPAWNER_OK 0
#define SPAWNER_INVALID 1
#define SPAWNER_NAV 2
#define SPAWNER_DISTANCE 3
#define SPAWNER_SIGHT 4
#define SPAWNER_OTHER 5

float latest_distance = 0.0;
int can_ZM_spawn(bool witch = false, bool hint = true)
{
	if (DEBUG) PrintToServer("[zm] can_ZM_spawn");
	if (!IsValidClientZM()) return SPAWNER_OTHER;
	if (zm_stage>=ZM_END) return SPAWNER_OTHER;
	
	float vAngles[3],vOrigin[3],vPos[3],vPos_spawner[3];
	GetClientAbsOrigin(zm_client,vPos);
	GetClientEyePosition(zm_client,vOrigin);
	GetClientEyeAngles(zm_client,vAngles);
	
    Handle trace = TR_TraceRayFilterEx(vOrigin,vAngles,MASK_SOLID,RayType_Infinite,FilterSpawner,zm_client);
    	
	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(vPos,trace);
		vPos_spawner = vPos;
	}
	delete trace;
    
    if (TR_PointOutsideWorld(vPos))
    {
        if (hint) update_hint("%T", "Bad location", zm_client);
        update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED,false);
        return SPAWNER_INVALID;
    }
    
    // bools: anyz los checkground
    float check_dist = 1000.0;
    if (witch) check_dist = 20.0;
    zm_spawner_navArea = L4D_GetNearestNavArea(vPos,check_dist,true,true,true,TEAM_INFECTED);
    if (zm_spawner_navArea)
    {
        zm_spawner_navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(zm_spawner_navArea);
        zm_spawner_navAttrFlags = L4D_GetNavArea_AttributeFlags(zm_spawner_navArea);
        float navSize[3], navCenter[3];
        //float navOrigin[3];
        L4D_GetNavAreaCenter(zm_spawner_navArea, navCenter);
        //L4D_GetNavAreaPos(zm_spawner_navArea, navOrigin);
        L4D_GetNavAreaSize(zm_spawner_navArea, navSize);
        //float z_min = navOrigin[2];
        //if (z_min>navCenter[2]) z_min = navCenter[2];
        //z_min -= navSize[2];
        
        //if (z_max<vPos[2]) z_max = vPos[2];
        // Check if fully within navarea xy. If not, grab a random position
        
        if ( FloatAbs(vPos_spawner[0]-navCenter[0])>(navSize[0]/2.0) ||
             FloatAbs(vPos_spawner[1]-navCenter[1])>(navSize[1]/2.0) )
        {
            L4D_FindRandomSpot(zm_spawner_navArea,vPos_spawner);
        }
        else
        {
            float z_min = navCenter[2] - FloatAbs(navSize[2])/2.0;
            //float z_max = navCenter[2] + FloatAbs(navSize[2])/2.0 + 25.0;
            //if (vPos_spawner[2]<z_min || vPos_spawner[2]>z_max)
            if (vPos_spawner[2]<z_min)
               vPos_spawner[2] = navCenter[2] + FloatAbs(navSize[2])/2.0 + 1.0;
        }
    }
    else
    {
        vPos_spawner = vPos;
        zm_spawner_navSpawnAttrs = 0;
        zm_spawner_navAttrFlags = 0;
        if (!witch)
        {
            if (hint) update_hint("%T", "Bad location", zm_client);
            update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED);
            return SPAWNER_NAV;
        }
    }
    
    if (!nav_can_spawn_zombies(zm_spawner_navAttrFlags,zm_spawner_navSpawnAttrs,witch))
    {
        if (hint)
        {
            if (witch)
            {
                //update_hint("Witches illegal");
                update_hint("%T", "Witches illegal", zm_client);
            }
            else
            {
                //update_hint("Zombies illegal");
                update_hint("%T", "Zombies illegal", zm_client);
            }
        }
        update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED);
        return SPAWNER_NAV;
    }
    
    //if (IsObstructed(vPos_spawner))
    //{
    //    if (hint) update_hint("Not enough space");
    //	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
    //	return false;
    //}
    
    latest_distance = -1.0;
    float min_distance = min_distance_to_survivors(vPos,hint);
    if (min_distance>=0.0)
    {
        latest_distance = min_distance;
        if (zm_spawner_navSpawnAttrs & NAV_SPAWN_NO_MOBS) min_distance /= 2.0; // 2x the usual survivor distance for areas marked "NO MOBS".
        else if (zm_stage<ZM_STARTED) min_distance *= 2.0; // if not started, players won't get swarmed so easily by initial wave
        
        if (min_distance<g_fSpawnMinDistance)
        {
            if (hint) update_hint("%T %d", "Too close", zm_client, RoundFloat(min_distance));
            update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
            return SPAWNER_DISTANCE;
        }
    }
    
    // If obscured, we prevent line of sight from blocking spawns.
    bool obscured = ( (zm_spawner_navSpawnAttrs & NAV_SPAWN_OBSCURED) || (zm_spawner_navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
    if (!obscured)
    {
        if (can_any_alive_survivor_see(vPos_spawner,hint))
        {
            if (!relocate_spawner_obscured(vPos_spawner))
            {
                update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
                //if (hint) update_hint("%T", "Visible survivors", zm_client);
                return SPAWNER_SIGHT;
            }
        }
    }
    
    if (!zm_allow_spawns)
	{
    	if (hint) update_hint("%T", "Zombie spawns OFF", zm_client);
    	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
    	return SPAWNER_OTHER;
	}
    
    update_ZM_spawner(vPos,vPos_spawner,SPAWNER_ALLOWED);
    return SPAWNER_OK;
    
}

stock bool IsValidEntRef(int entity)
{
	if( entity && entity != -1 && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
		
}

bool saferoom_interacted = false;
int hits = 0;
public MRESReturn DHook_Saferoom_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	//if (!g_bCvarAllow || zm_stage!=ZM_STARTED || L4D_IsSurvivalMode()) return MRES_Ignored;
	if (!g_bCvarAllow || zm_stage>=ZM_STARTED) return MRES_Ignored;
	
	char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (strcmp(inputName,"PlayerOpen")==0) hits += 1;
	else if (strcmp(inputName,"Use")==0) hits += 1;
	
	PrintToServer("[zm] rotating door accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (hits>1 && !saferoom_interacted)
	{
    	saferoom_interacted = true;
    	can_zm_start();
    	if (zm_stage<ZM_STARTED && !zm_can_start)
        {
            saferoom_lock(true);
            //RequestFrame(saferoom_lock,true);
        }
	}
	
	return MRES_Ignored;
}


void check_saferoom()
{
   
   if (L4D_IsSurvivalMode())
   {
       g_iLockedDoor = INVALID_ENT_REFERENCE;
       return;
   }
   
   if (g_iLockedDoor==INVALID_ENT_REFERENCE && L4D_HasMapStarted())
   {
        if (DEBUG) PrintToServer("[zm] check_saferoom");
        g_iLockedDoor = L4D_GetCheckpointFirst();
        if (IsValidEntity(g_iLockedDoor))
        {
            g_iLockedDoor = EntIndexToEntRef(g_iLockedDoor);
            if (!saferoom_interacted && g_DHook_AcceptInput)
            {
                //SDKHook(g_iLockedDoor, SDKHook_Use, OnFirst);
                hits = 0;
                DHookEntity(g_DHook_AcceptInput, true, g_iLockedDoor, INVALID_FUNCTION, DHook_Saferoom_AcceptInput);
                //HookSingleEntityOutput(g_iLockedDoor, "OnOpen", OnFirst);
                //HookSingleEntityOutput(g_iLockedDoor, "OnLockedUse", OnFirst);
                //HookSingleEntityOutput(g_iLockedDoor, "OnBlockedOpening", OnFirst);
                //HookSingleEntityOutput(g_iLockedDoor, "OnUnblockedOpening", OnFirst);
            }
            else saferoom_interacted = true;
            //g_iFirstFlags = GetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags");
        }
        else
        {
            if (DEBUG) PrintToServer("[zm] no saferoom, ignoring");
            g_iLockedDoor = INVALID_ENT_REFERENCE;
            //g_iFirstFlags = -1;
        }
   }
   
}

//void OnFirst(int door, int client)
//{
//    //SDKUnhook(g_iLockedDoor, SDKHook_Use, OnFirst);
//    PrintToServer("[zm] OnFirst");
//    can_zm_start();
//    //if (zm_can_start || zm_stage>=ZM_STARTED) SDKUnhook(g_iLockedDoor, SDKHook_Use, OnFirst);
//    if (zm_stage<ZM_STARTED && !zm_can_start)
//    {
//        saferoom_interacted = true;
//        RequestFrame(saferoom_lock,true);
//    }
//}

void saferoom_lock(bool state)
{
    if (DEBUG) PrintToServer("[zm] saferoom_lock");
    check_saferoom();
    
    if ( !IsValidEntRef(g_iLockedDoor) )
    {
        
        //if (state && !zm_started && g_bLockSaferoom)
        //{
        //    if (DEBUG) PrintToServer("[zm] Can't lock - Freezing survivors");
        //    freeze_team(true);
        //}
        //else
        //{
        //    if (DEBUG) PrintToServer("[zm] Can't unlock - Unfreezing survivors");
        //    freeze_team(false);
        //}
        saferoom_locked = state;
        return;
    }
    
    if (state && zm_stage<ZM_STARTED && g_bLockSaferoom)
    {
        //SetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked",1);
        //AcceptEntityInput(g_iLockedDoor, "Close");
        //AcceptEntityInput(g_iLockedDoor, "forceclosed");
        //SetEntProp(g_iLockedDoor, Prop_Send, "m_eDoorState", DOOR_STATE_CLOSING_IN_PROGRESS);
        //AcceptEntityInput(g_iLockedDoor, "Lock");
        //SetEntProp(g_iLockedDoor, Prop_Send, "m_eDoorState", DOOR_STATE_CLOSING_IN_PROGRESS);
        if (saferoom_interacted)
            SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
        saferoom_glow(true);
        saferoom_locked=true;
        if (DEBUG) PrintToServer("[zm] Locked saferoom");
    }
    else
    {
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")&~DOOR_FLAG_IGNORE_USE);
        //if (!saferoom_interacted)
        //{
        //    if (saferoom_locked)
        //    {
        //        saferoom_locked = false;
        //        RequestFrame(saferoom_lock,false);
        //    }
        //    else
        //    {
        //        //AcceptEntityInput(g_iLockedDoor, "Use");
        //        saferoom_interacted = true;
        //   }
        //}
        //SetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked",0);
        //AcceptEntityInput(g_iLockedDoor, "Unlock");
        //SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", g_iFirstFlags&~DOOR_FLAG_IGNORE_USE);
        //if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_OPENING_IN_PROGRESS) SetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState",DOOR_STATE_CLOSED);
        saferoom_glow(false);
        saferoom_locked=false;
        //freeze_team(false);
        if (DEBUG) PrintToServer("[zm] Unlocked saferoom");
    }
    
}

void saferoom_glow(bool state=true)
{
   if (DEBUG) PrintToServer("[zm] saferoom_glow");
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
   if (DEBUG) PrintToServer("[zm] can_zm_start");
   if (!g_bLockSaferoom || zm_can_start) // Option 2: do not re-lock saferoom after first "round can start" announcement
   //if (!g_bLockSaferoom) // Option 1: allow saferoom to be relocked
   {
       zm_can_start = true;
       if (saferoom_locked) saferoom_lock(false);
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
   
   float t_now = GetEngineTime();
   if ( IsValidClientZM() && (t_now-t_last_join)>saferoom_cooldown )
   {
      if ((t_now - t_zm_join)>=g_fPrepTimeZM) zm_can_start = true;
   }
     
   if (zm_can_start)
   {
       if (saferoom_locked)
       {
           saferoom_lock(false);
           if (zm_stage<ZM_STARTED) EmitSoundToAll(SOUND_READY);
           update_EMS_HUD();
       }
   }
   else if (g_bLockSaferoom && !saferoom_locked)
   {
      saferoom_lock(true);
   }
}

void freeze_player(int client, bool state = true, int team = TEAM_SURVIVOR)
{
    if(IsValidEntRef(client) && IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client)==team && client!=zm_client)
    {   
        if (state && zm_stage<ZM_STARTED)
        {
            if (team == TEAM_SURVIVOR) SetEntProp(client, Prop_Data, "m_takedamage", 0);
    		SetEntityMoveType(client, MOVETYPE_NONE);
    		if (team == TEAM_INFECTED) SetEntProp(client, Prop_Send, "m_fFlags", GetEntProp(client, Prop_Send, "m_fFlags")|FL_FROZEN);
    		else if (team == TEAM_SURVIVOR) TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    		
		}
		else
		{
    		SetEntityMoveType(client, MOVETYPE_WALK);
    		if (team == TEAM_INFECTED) SetEntProp(client, Prop_Send, "m_fFlags", (GetEntProp(client, Prop_Send, "m_fFlags")&~FL_FROZEN));
            else if (team == TEAM_SURVIVOR) SetEntProp(client,Prop_Data,"m_takedamage",2);
		}
    }
}

// Teleport survivor to starting area - ONLY COOP
// Thanks Dragokas -- https://forums.alliedmods.net/showthread.php?t=338572
int safezone_navAreaId = -1;

// Check if navArea is a valid survivor starting area
bool navArea_validStart(Address navArea)
{
    if (!navArea) return false;
    int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
    if ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_FINALE) ) return false;
    if (!((navSpawnAttrs & NAV_SPAWN_PLAYER_START) || (navSpawnAttrs & NAV_SPAWN_CHECKPOINT))) return false;
    
    float pos[3];
    L4D_FindRandomSpot(navArea,pos);
    float flow = L4D_GetFlowFromPoint(pos);
    if (flow>0.0 || flow<(-9000.0)) return false;
    
    return true;
}

void tp_survivor_start(int client)
{
   
   if (!IsValidClient(client) || !L4D_HasMapStarted())
   {
       if (DEBUG) PrintToServer("[zm] tp_survivor_start failed early");
       return;
   }
   
   float vector[3];
   
   if (L4D_IsSurvivalMode())
   {
       int survivor = GetRandomSurvivor(1,1);
       if (IsValidClient(survivor) && client!=survivor)
       {
           GetClientEyePosition(survivor, vector);
           vector[2] += 10.0;
           TeleportEntity(client, vector, NULL_VECTOR, NULL_VECTOR);
           if (DEBUG) PrintToServer("[zm] Teleported to random survivor");
       }
       return;
   }
   
   Address temp_navArea;
   
   if (g_bNavReady && g_hStartAreaList.Length>0)
   {
       int random = 0;
       if (g_hStartAreaList.Length>1) random = GetRandomInt(0,g_hStartAreaList.Length-1);
       PreCalcNav cell;
       g_hStartAreaList.GetArray(random, cell);
       temp_navArea = cell.navArea;
       if (navArea_validStart(temp_navArea))
       {
           safezone_navAreaId = L4D_GetNavAreaID(temp_navArea);
           if (DEBUG) PrintToServer("[zm] found precomputed start area");
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
               if (DEBUG) PrintToServer("[zm] found info_player_start");
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
                        if (DEBUG) PrintToServer("[zm] found info_survivor_position");
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
                   if (DEBUG) PrintToServer("[zm] found saferoom");
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
                if (DEBUG) PrintToServer("[zm] found player in start area");
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
           randomPos[2] += 25.0;
           TeleportEntity(client, randomPos, NULL_VECTOR, NULL_VECTOR);
           if (DEBUG) PrintToServer("[zm] Teleported to safezone");
       }
       else safezone_navAreaId = -1;
   }
   
}

stock bool IsValidEntity_Safe(int entity)
{
	return ( entity && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity) );
}

// Call this if you want to freeze silently (for periodic refreezing)
void freeze_team(bool state = true, int team = TEAM_SURVIVOR)
{
    if (DEBUG) PrintToServer("[zm] freeze_team");
    //check_saferoom();
    for (int i=1;i<=MaxClients;i++)
    {
        freeze_player(i,state,team);
    }
    if (DEBUG)
    {
        if (state) PrintToServer("[zm] Froze team %d", team);
        else PrintToServer("[zm] Unfroze team %d", team);
    }
    if (team==TEAM_SURVIVOR && g_iLockedDoor==INVALID_ENT_REFERENCE) saferoom_locked=state;
}

stock int GetEntityCountEx()
{
	if (DEBUG) PrintToServer("[zm] GetEntityCountEx");
	int ent;
	int cnt;
	for(ent = 0; ent < MAXENTITIES; ent++)
	{
		if( IsValidEntity(ent) || IsValidEdict(ent) )
		{
			cnt++;
		}
	}
	return cnt;
}

// Check if player is a valid actual player on the server
bool IsValidClientZM(int client=-1)
{
    int check_client = client;
    if (client<0) check_client = zm_client;
    if (check_client>0 && check_client<=MAXPLAYERS && IsClientInGame(check_client) && !IsFakeClient(check_client) && !IsClientSourceTV(check_client) && !IsClientReplay(check_client))
       return true;
    return false;
}

public Action L4D2_OnSendInRescueVehicle()
{
    if (ZM_finale_announced) ZM_finale_ended = true;
    else PrintToServer("[zm] ???? Rescue vehicle sent before Finale start");
}

void get_finale_label(int finaleType, char label[32])
{
    switch (finaleType)
    {
        case 0: {label = "FINALE_GAUNTLET_1";} // minimum 30s
        case 1: {label = "FINALE_HORDE_ATTACK_1";} // no interrupt
        case 2: {label = "FINALE_HALFTIME_BOSS";} // minimum 30s and tank must die
        case 3: {label = "FINALE_GAUNTLET_2";} // minimum 30s
        case 4: {label = "FINALE_HORDE_ATTACK_2";} // no interrupt
        case 5: {label = "FINALE_FINAL_BOSS";} // minimum 30s and tank must die
        case 6: {label = "FINALE_HORDE_ESCAPE";} //infinite
        case 7: {label = "FINALE_CUSTOM_PANIC";} // minimum 30s
        case 8: {label = "FINALE_CUSTOM_TANK";} // minimum 30s and tank dead
        case 9: {label = "FINALE_CUSTOM_SCRIPTED";} // ??? could do anything
        case 10: {label = "FINALE_CUSTOM_DELAY";} // ??? could do anything
        case 11: {label = "FINALE_CUSTOM_CLEAROUT";} // let map manage this
        case 12: {label = "FINALE_GAUNTLET_START";} // let it through
        case 13: {label = "FINALE_GAUNTLET_HORDE";} // minimum 30s
        case 14: {label = "FINALE_GAUNTLET_HORDE_BONUSTIME";} // minimum 30s
        case 15: {label = "FINALE_GAUNTLET_BOSS_INCOMING";} // let it through
        case 16: {label = "FINALE_GAUNTLET_BOSS";} // minimum 30s and tank must die
        case 17: {label = "FINALE_GAUNTLET_ESCAPE";} // infinite
        case 18: {label = "FINALE_NONE";} // let it through
        default: {label = "unknown";} // let it through
    }
}

//MRESReturn ChangeFinaleStage_Pre(DHookReturn hReturn, DHookParam hParams)
//{
//	int finaleType = hParams.Get(1);
//	char current_label[32], label[32];
//	int current = L4D2_GetCurrentFinaleStage();
//    get_finale_label(current,current_label);
//    get_finale_label(finaleType,label);
//    PrintToServer("[zm] ChangeFinaleStage_Pre %s -> %s", current_label, label);
//    if (!g_bCvarAllow) return MRES_Ignored;
//    
//    if (current == FINALE_NONE || finaleType==FINALE_NONE) return MRES_Ignored;
//    
//    if (ZM_finale_announced && zm_stage==ZM_STARTED)
//    {
//        hParams.Set(1,current);
//        hReturn.Value = false;       
//        PrintToServer("[zm] ChangeFinaleStage_Pre HOLDING %s", current_label);
//        //if (finaleType!=current) L4D2_ChangeFinaleStage(current,"zm_hold");
//        return MRES_Supercede;
//    }
//    
//	return MRES_Ignored;
//}

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg)
{	
	if (!g_bCvarAllow || zm_stage!=ZM_STARTED || finaleType==FINALE_NONE) return Plugin_Continue;
	int current = L4D2_GetCurrentFinaleStage();
	char current_label[32], label[32]; //
	get_finale_label(current,current_label);
	get_finale_label(finaleType,label);
	int pending_mob = L4D2Direct_GetPendingMobCount();
	if (DEBUG) PrintToServer("[zm] L4D2_OnChangeFinaleStage %s -> %s %s, mob %d", current_label, label, arg, pending_mob);
    
    if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
       L4D2Direct_SetPendingMobCount(script_CommonLimit);
    
    return Plugin_Continue;
    
    //if (!ZM_finale_announced || current==FINALE_NONE || finaleType==FINALE_NONE)
    //    return Plugin_Continue;
    
    // Always allow transition from scripted stage and tank stage.
    //switch (current)
    //{
    //    case FINALE_GAUNTLET_START: {return Plugin_Continue;}
    //    case FINALE_FINAL_BOSS: {return Plugin_Continue;}
    //    case FINALE_HALFTIME_BOSS: {return Plugin_Continue;}
    //    case FINALE_CUSTOM_TANK: {return Plugin_Continue;}
    //    case FINALE_GAUNTLET_BOSS: {return Plugin_Continue;}
    //    case FINALE_HORDE_ESCAPE: {return Plugin_Continue;}
    //    case FINALE_GAUNTLET_ESCAPE: {return Plugin_Continue;}
        //case FINALE_HORDE_ATTACK_1: {return Plugin_Continue;}
        //case FINALE_HORDE_ATTACK_2: {return Plugin_Continue;}
        
    //    case FINALE_CUSTOM_DELAY: {return Plugin_Continue;}
    //    case FINALE_CUSTOM_SCRIPTED: {return Plugin_Continue;}
    //}
    
    // Always allow transitions to tanks to prevent community plugins from messing shit up.
    //switch (finaleType)
    //{
    //    case FINALE_GAUNTLET_START: {return Plugin_Continue;}
    //    case FINALE_FINAL_BOSS: {return Plugin_Continue;}
    //    case FINALE_HALFTIME_BOSS: {return Plugin_Continue;}
    //    case FINALE_CUSTOM_TANK: {return Plugin_Continue;}
    //    case FINALE_GAUNTLET_BOSS: {return Plugin_Continue;}
    //    case FINALE_HORDE_ESCAPE: {return Plugin_Continue;}
    //    case FINALE_GAUNTLET_ESCAPE: {return Plugin_Continue;}
        //case FINALE_HORDE_ATTACK_1: {return Plugin_Continue;}
        //case FINALE_HORDE_ATTACK_2: {return Plugin_Continue;}
    //    case FINALE_CUSTOM_DELAY: {return Plugin_Continue;}
    //    case FINALE_CUSTOM_SCRIPTED: {return Plugin_Continue;}
    //}
    
    //if ( live_zombie_arr[ZOMBIECLASS_TANK]<=0 && ((GetEngineTime()-t_finale)>=g_fMinFinaleStage) )
    //    	return Plugin_Continue;
    
    //PrintToServer("[zm] L4D2_OnChangeFinaleStage HOLDING %d", current);    
    //if (current==finaleType) return Plugin_Handled;
    //finaleType = current;
    //return Plugin_Stop;
    //return Plugin_Handled;
}

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg)
{   
   	char label[32];
   	get_finale_label(finaleType,label);
   	int pending_mob = L4D2Direct_GetPendingMobCount();
   	if (DEBUG) PrintToServer("[zm] L4D2_OnChangeFinaleStage_Post %s %s, mob %d", label, arg, pending_mob);
    
    //if (finaleType==FINALE_CUSTOM_TANK) PrintToServer("[zm] Finale tank should spawn");
    if (!g_bCvarAllow || L4D_IsSurvivalMode() || ZM_finale_ended || !ZM_finale_announced) return;
    
    available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    
    //CreateTimer(5.0, Timer_Free_Angry_Zombies, 25, TIMER_FLAG_NO_MAPCHANGE);
    
    float t_now = GetEngineTime();
    int add_bank = g_iBonusFinaleStage*g_iAliveSurvivors;
    if ((t_now-t_finale)>=g_fMinFinaleStage && (bank<(2*add_bank)) )
    {
        if (IsValidClientZM())
        {
            PrintHintText(zm_client, "%t", "ZM finale advance");
            EmitSoundToClient(zm_client,SOUND_REWARD);
        }
        bank += add_bank;
        if (bank>2*add_bank) bank = 2*add_bank;
        t_finale = t_now;
    }
    else if ( live_zombie_arr[ZOMBIECLASS_TANK]>0 || bank>=(2*add_bank) )
        t_finale = t_now;
    //t_finale = t_now;
    //manual_change = false;
}

public void L4D2_OnChangeFinaleStage_PostHandled(int finaleType, const char[] arg)
{
    int current = L4D2_GetCurrentFinaleStage();
    //L4D2_ChangeFinaleStage(current,"zm_hold");
	char current_label[32], label[32];
	get_finale_label(current,current_label);
    get_finale_label(finaleType,label);
    //finaleType = current;
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (DEBUG) PrintToServer("[zm] L4D2_OnChangeFinaleStage_PostHandled %s -> %s %s, mob %d", current_label, label, arg, pending_mob);
    //manual_change = false;
}

void announce_finale()
{
    if (DEBUG) PrintToServer("[zm] announce_finale");
    if (L4D_IsSurvivalMode() || zm_stage<ZM_STARTED) return;
    if (!ZM_finale_announced)
    {
        if (IsValidClientZM())
        {
            EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
            PrintHintText(zm_client, "%t", "Finale started ZM");
        }
        PrintToChatAll("[zm] %t", "Finale started");
        t_finale = GetEngineTime();
        ZM_finale_announced=true;
        update_menus();
        if (panic) toggle_panic(false,true);
    }
    else if (ZM_finale_ended)
    {
        PrintToServer("[zm] Finale just announced but it's already ended. lol");
    }
    if (panic) toggle_panic(false,true);
    ZM_finale_announced = true;
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    announce_finale();
}

void EvtFinaleRush(Event event, const char[] name, bool dontBroadcast)
{
    PrintToServer("[zm] EvtFinaleRush");
}

void EvtTankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    //L4D2_RemoveEntityGlow(victim);
    //L4D2_SetPlayerSurvivorGlowState(victim,false);
    int health = GetEntProp(victim,Prop_Data,"m_iHealth");
    char targetName[64];
    GetEntPropString(victim, Prop_Data, "m_iName", targetName, sizeof(targetName));
    if (DEBUG) PrintToServer("[zm] EvtTankSpawn %d %s, %d HP", victim, targetName, health);
    if (targetName_pending[0]!=0 && victim!=zm_client)
	{
    	if (DEBUG) PrintToServer("[zm] Applied targetName_pending %s", targetName_pending);
    	if (health>1) SetEntProp(victim,Prop_Data,"m_iHealth",health-1); // prevent possible same-frame refund exploit
    	DispatchKeyValue(victim, "targetname", targetName_pending);
    	SetEntProp(victim,Prop_Data,"m_iMaxHealth", maxhp_pending);
    	targetName_pending = "";
	}
}

//void EvtTankKilled(Event event, const char[] name, bool dontBroadcast)
//{
//    int victim = GetClientOfUserId(event.GetInt("userid"));
//    int health = GetEntProp(victim,Prop_Data,"m_iHealth");
//    PrintToServer("[zm] EvtTankKilled %d, %d HP", victim, health);
//}

// Full credit to Dragokas
void Chase(int target)
{
	if (DEBUG) PrintToServer("[zm] Chase");
	
	if (ZM_finale_announced || L4D_IsSurvivalMode() )
	{
    	if (DEBUG) PrintToServer("[zm] Infected chase is already set, ignoring.");
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
		    if (DEBUG) PrintToServer("[zm] New Chase created");
			entity = CreateEntityByName("info_goal_infected_chase");
			if( entity != -1 )
			{
				TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
				DispatchSpawn(entity);
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
		if (DEBUG) PrintToServer("[zm] Chase enabled");
		panic_target = target;

		
		char name[MAX_NAME_LENGTH];
        GetClientName(target,name,sizeof(name));
        //update_hint("Chasing %s", name);
        update_hint("%T", "Chasing x", zm_client, name);
        //if (DEBUG) PrintToServer(char_full);
	}
	else panic_target = -1;
}

void disable_chase()
{
    int chase_ent = FindEntityByClassname(MaxClients + 1, "info_goal_infected_chase");
    if (chase_ent && chase_ent != INVALID_ENT_REFERENCE)
    {
        if (DEBUG) PrintToServer("[zm] Chase found, disabled");
     	AcceptEntityInput(chase_ent, "Disable");
     	//AcceptEntityInput(chase_ent, "ClearParent");
    }
    panic_target = -1;
}

void infected_panic()
{
    int zombie = INVALID_ENT_REFERENCE;
    while( INVALID_ENT_REFERENCE != (zombie = FindEntityByClassname(zombie, "infected")) )
    {
   	    if( IsValidEntity(zombie) && GetEntProp(zombie,Prop_Data,"m_iHealth")>0 ) 
   	    {
       	     if (hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
        }
    }
}

void update_panic()
{
    // No panic before round start, in survival, and finales.
    if (zm_stage!=ZM_STARTED || L4D_IsSurvivalMode() || ZM_finale_announced) return;
    
    if (!panic) toggle_panic(true,true,true);
    else
    {
        t_last_panic = GetEngineTime();
        available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
    }
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (pending_mob>0)
    {
        CreateTimer(2.5, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
        L4D2Direct_SetPendingMobCount(0);
    }
}

void toggle_panic(bool state = true, bool overwrite = false, bool free = false)
{
    if (L4D_IsSurvivalMode() || ZM_finale_announced)
    {
        update_hint("%T", "Panic is automatic", zm_client);
        if (panic)
        {
            disable_chase();
            panic=false;
        }
        return;
    }
    
    if (DEBUG) PrintToServer("[zm] toggle_panic");
    
    bool actual_state;
    if (overwrite) actual_state = state;
    else
    {
        bool current = panic;
        actual_state = !current;
    }
    
    if ( zm_stage>=ZM_STARTED && actual_state )
    {
       
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
           if (DEBUG) PrintToServer("[zm] Free panic");
       }
       
       if (DEBUG) PrintToServer("[zm] Panic ON");
       //int target = L4D_GetHighestFlowSurvivor();
       if (zm_stage==ZM_STARTED && !panic && IsValidClientZM() && !ZM_finale_announced)
           EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
       panic = true;
       available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON]; 
       t_last_panic = GetEngineTime();
       if (manual_panic)
       {
           if (DEBUG) PrintToServer("[zm] Manual panic");
           L4D_ForcePanicEvent();
           //if (IsValidClient(target)) Chase(target);
           //else panic_target = -1;
           
       }
       if (!manual_panic && IsValidClientZM()) PrintHintText(zm_client, "%t", "ZM panic notify");
       if (manual_panic) update_hint("%T", "panic_rate_reduced", zm_client);
       actual_state = true;
       infected_panic();
       
    }
    else
    {
        if (DEBUG) PrintToServer("[zm] Panic OFF");
        manual_panic = false;
        if (zm_stage<ZM_STARTED) update_hint("Round not started");
        else update_hint("%T", "panic_rate_normal", zm_client);
        actual_state = false;
        disable_chase();
        if (zm_stage==ZM_STARTED && panic && IsValidClientZM() && !ZM_finale_announced) EmitSoundToClient(zm_client,SOUND_PANIC_OFF);
        panic = false;
    }
    
    if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
    else SetConVarInt(FindConVar("director_panic_forever"), 0);
    create_common_menu();
    create_uncommon_menu();
    zm_update(zm_timer);
    
}

void CountStringRowsCols(const char[] str, int &rows, float &cols)
{
    int i, count = 0;
    float current, longest = 0.0;
    char c_temp;
    while (str[i] != 0)
    {
        c_temp = str[i];
        switch (c_temp)
        {
            case ' ': current += 0.75;
            case '1': current += 0.5;
            case 'i': current += 0.5;
            case 'l': current += 0.5;
            case 'f': current += 0.5;
            case 'j': current += 0.5;
            case 't': current += 0.5;
            case '|': current += 0.5;
            case '`': current += 0.5;
            case '!': current += 0.5;
            case '.': current += 0.5;
            case ',': current += 0.5;
            case '(': current += 0.5;
            case ')': current += 0.5;
            case '\n':
            {
                count++;
                if (current>longest) longest = current;
                current = 0.0;
            }
            default: current += 1.0;
        }
        i+=1;
    }
    rows = count + 1;
    if (current>longest) longest = current;
    cols = longest + 0.1;
}

static char g_sHUD_Text[512];
char g_sHUD_TextArray[4][128];
char g_sBuffer[128];
char g_sSpaces[128] = "                                                                                                                               ";
char g_sData_HUD_ZM_Text[128];
char g_sData_HUD_TIMER_Text[128];

bool clients_in_server = false; // track whether HUD needs to be updated

int get_occupied_units(int max, int available, int live)
{
    int occupied = max-available;
    if (occupied<live) occupied = live;
    return occupied;
}

void update_EMS_HUD()
{
    
    if (!EMS_hud_ready) return;
    
    if (DEBUG) PrintToServer("[zm] update_EMS_HUD");
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TICKER);
    if (!clients_in_server || zm_stage>=ZM_END)
    {
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TIMER);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM_HINT);
        return;
    }
    
    int HUD_TIMER_flags = HUD_FLAG_ALIGN_CENTER|HUD_FLAG_TEXT;
    int HUD_ZM_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT;
    int HUD_ZM_HINT_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT|HUD_FLAG_NOBG;
    
    float t_now = GetEngineTime();
    int rows;
    float cols;
    
    if (IsValidClientZM() && zm_stage<ZM_END)
    {
        
        char panic_str[32];
        if (panic || ZM_finale_announced || (L4D_IsSurvivalMode() && zm_stage==ZM_STARTED) )
        {
            float panic_left;
            if (ZM_finale_announced || L4D_IsSurvivalMode()) panic_left = 0.0;
            else panic_left = g_fPanicDuration - (t_now - t_last_panic);
            if (panic_left<=0.0) Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON", zm_client);
            else
            {
                Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON time", zm_client, panic_left);
                if (panic_left<=5.0)
                {
                    HUD_ZM_flags |= HUD_FLAG_BLINK;
                    HUD_ZM_HINT_flags |= HUD_FLAG_BLINK;
                }
            }
        }
        //else Format(panic_str, sizeof(panic_str), "%T", "PANIC OFF", zm_client);
        else Format(panic_str, sizeof(panic_str), "");
        
        char bank_str[32];
        char common_str[32];
        char special_str[32];
        char witch_str[32];
        
        if (bank_rate>0.0) Format(bank_str, sizeof(bank_str), "%T %d (%.1f)", "Bank", zm_client, bank, bank_rate);
        else Format(bank_str, sizeof(bank_str), "%T %d", "Bank", zm_client, bank);
        
        Format(common_str, sizeof(common_str), "%T", "Common", zm_client);
        Format(special_str, sizeof(special_str), "%T", "Special", zm_client);
        Format(witch_str, sizeof(witch_str), "%T", "Witch", zm_client);
        
        // ZM INFO
        int occupied_SI = get_occupied_units(max_SI,available_SI,live_SI);
        int occupied_commons = get_occupied_units(max_zombie_arr[ZOMBIECLASS_COMMON],available_zombie_arr[ZOMBIECLASS_COMMON],live_zombie_arr[ZOMBIECLASS_COMMON]);
        int occupied_witches = get_occupied_units(max_zombie_arr[ZOMBIECLASS_WITCH],available_zombie_arr[ZOMBIECLASS_WITCH],live_zombie_arr[ZOMBIECLASS_WITCH]);
        FormatEx(g_sData_HUD_ZM_Text,sizeof(g_sData_HUD_ZM_Text),
                 "%s\n%s%s %d/%d\n%s %d/%d\n%s %d/%d",
                 bank_str,
                 panic_str,
                 common_str,occupied_commons,max_zombie_arr[ZOMBIECLASS_COMMON],
                 special_str,occupied_SI,max_SI,
                 witch_str,occupied_witches,max_zombie_arr[ZOMBIECLASS_WITCH]);
        
        TrimString(g_sData_HUD_ZM_Text);
        CountStringRowsCols(g_sData_HUD_ZM_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.008, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.1, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026*rows, HUD_ZM);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s %s", g_sData_HUD_ZM_Text, g_sSpaces);
        g_sHUD_TextArray[HUD_ZM] = g_sBuffer;
        
        // ZM HINT
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.0, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.07, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.51, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_ZM_HINT);
        TrimString(ZM_hint);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n%s\n %s", ZM_hint, g_sSpaces);
        g_sHUD_TextArray[HUD_ZM_HINT] = g_sBuffer;
        
    }
    else
    {
        HUD_ZM_flags = HUD_FLAG_NOTVISIBLE;
        HUD_ZM_HINT_flags = HUD_FLAG_NOTVISIBLE;
    }
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_flags, _, HUD_ZM);
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_HINT_flags, _, HUD_ZM_HINT);
    
    if (!IsValidClientZM() && !zm_just_died)
       Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "No ZM notify", LANG_SERVER);
    else
    {
        if (zm_stage>=ZM_STARTED || L4D_IsSurvivalMode()) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
        else
        {
            if (zm_can_start)
            {
                //FormatEx(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),"Survivors can leave the safe zone!");
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Survivors can leave", LANG_SERVER);
                HUD_TIMER_flags |= HUD_FLAG_BLINK;
            }
            else
            {
                
                float time1 = saferoom_cooldown - (t_now - t_last_join);
                float time2 = g_fPrepTimeZM - (t_now - t_zm_join);
                
                float t_biggest;
                if (time1>time2) t_biggest=time1;
                else t_biggest = time2;
                
                if (t_biggest<0.0) t_biggest = 0.0;
                if (t_biggest<=5.0) HUD_TIMER_flags |= HUD_FLAG_BLINK;
                
                //FormatEx(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),"Round will start in %d seconds!", RoundFloat(t_biggest));
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Round can start in", LANG_SERVER, RoundFloat(t_biggest));
                
                
            }
        }
    }
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_TIMER_flags, _, HUD_TIMER);
    if (HUD_TIMER_flags!=HUD_FLAG_NOTVISIBLE)
    {
        
        CountStringRowsCols(g_sData_HUD_TIMER_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.35, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.14, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_TIMER);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n  %s\n %s", g_sData_HUD_TIMER_Text, g_sSpaces);
        g_sHUD_TextArray[HUD_TIMER] = g_sBuffer;
    }
    
    // TICKER - PLACEHOLDER
    g_sBuffer = "\0";
    FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s%s", g_sSpaces, g_sSpaces);
    g_sHUD_TextArray[HUD_TICKER] = g_sBuffer;
    
    ImplodeStrings(g_sHUD_TextArray, sizeof(g_sHUD_TextArray), " ", g_sHUD_Text, sizeof(g_sHUD_Text));
    GameRules_SetPropString("m_szScriptedHUDStringSet", g_sHUD_Text);
    
}

bool can_change_finale_stage()
{
    //if (manual_change) return false;
    if (!ZM_finale_announced) return false;
    
    //int pending_mob = L4D2Direct_GetPendingMobCount();
    //if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
    //   L4D2Direct_SetPendingMobCount(script_CommonLimit);
    
    if (bank>250) return false;
    if (zm_stage>=ZM_END || ZM_finale_ended) return false;
    if (L4D2Direct_GetTankCount()>0) return false;
    if (live_zombie_arr[ZOMBIECLASS_TANK]>0) return false;
    if (L4D2_IsTankInPlay()) return false;
    
   // L4D2Direct_SetPendingMobCount(0);
    
    int current = L4D2_GetCurrentFinaleStage();
    switch (current)
    {
        case FINALE_HORDE_ESCAPE: {return false;}
        //case FINALE_CUSTOM_SCRIPTED: {return false;}
        //case FINALE_CUSTOM_DELAY: {return false;}
        case FINALE_GAUNTLET_ESCAPE: {return false;}
        case FINALE_NONE: {return false;}
    }
    
    float t_now = GetEngineTime();
    if ((t_now-t_finale)>=g_fMinFinaleStage || (live_SI<=0 && live_zombie_arr[ZOMBIECLASS_COMMON]<10) )
       return true;
    
    return false;
    
}

float get_bank_rate()
{

 // Coop finale and Survival logic
 if (ZM_finale_announced || L4D_IsSurvivalMode() || !L4D_HasAnySurvivorLeftSafeArea() )
 {
    if (ZM_finale_announced && !L4D_IsSurvivalMode())
    {
        // Coop finale logic
        if (can_change_finale_stage())
        {
            L4D2Direct_SetPendingMobCount(0);
            //PrintToServer("[zm] Forcing next stage manually");
            //manual_change = true;
            //L4D2_ForceNextStage();
        }
        else
        {
            int pending_mob = L4D2Direct_GetPendingMobCount();
            if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
               L4D2Direct_SetPendingMobCount(script_CommonLimit);
        }
    }
    bank_rate = 0.0;
    return bank_rate;
 }
 
 // Coop logic
 float final_rate = g_fBankRateBase;
 if (g_iAliveSurvivors>0) final_rate += g_iAliveSurvivors*g_fBankRatePlayer;
    
 if (panic && manual_panic) final_rate /= 4.0;
 bank_rate = final_rate;
 return bank_rate;
 
}

// zm client: player has input command SetFogController -> create special zm fog controller with infinite range
// try m_skybox3d.fog.start m_skybox3d.fog.end for zm_client
// 

 //   -Member: m_skybox3d.scale (offset 152) (type integer) (bits 12)
 ///   -Member: m_skybox3d.origin (offset 156) (type vector) (bits 0)
 //   -Member: m_skybox3d.area (offset 168) (type integer) (bits 8)
 //   -Member: m_skybox3d.bClip3DSkyBoxNearToWorldFar (offset 172) (type integer) (bits 1)
 //   -Member: m_skybox3d.flClip3DSkyBoxNearToWorldFarOffset (offset 176) (type float) (bits 0)
 //   -Member: m_skybox3d.fog.enable (offset 256) (type integer) (bits 1)
 //   -Member: m_skybox3d.fog.blend (offset 257) (type integer) (bits 1)
 //   -Member: m_skybox3d.fog.dirPrimary (offset 184) (type vector) (bits 0)
 //   -Member: m_skybox3d.fog.colorPrimary (offset 196) (type integer) (bits 32)
 //   -Member: m_skybox3d.fog.colorSecondary (offset 200) (type integer) (bits 32)
 //   -Member: m_skybox3d.fog.start (offset 212) (type float) (bits 0)
 //   -Member: m_skybox3d.fog.end (offset 216) (type float) (bits 0)
 //   -Member: m_skybox3d.fog.maxdensity (offset 224) (type float) (bits 0)
//    -Member: m_skybox3d.fog.HDRColorScale (offset 260) (type float) (bits 0)

// fog controller:
//Sub-Class Table (1 Deep): DT_FogController
//-Member: m_fog.enable (offset 1148) (type integer) (bits 1)
//-Member: m_fog.blend (offset 1149) (type integer) (bits 1)
//-Member: m_fog.dirPrimary (offset 1076) (type vector) (bits 0)
//-Member: m_fog.colorPrimary (offset 1088) (type integer) (bits 32)
//-Member: m_fog.colorSecondary (offset 1092) (type integer) (bits 32)
//-Member: m_fog.start (offset 1104) (type float) (bits 0)
//-Member: m_fog.end (offset 1108) (type float) (bits 0)
//-Member: m_fog.maxdensity (offset 1116) (type float) (bits 0)
//-Member: m_fog.farz (offset 1112) (type float) (bits 0)
//-Member: m_fog.skyboxFogFactor (offset 1120) (type float) (bits 0)
//-Member: m_fog.colorPrimaryLerpTo (offset 1096) (type integer) (bits 32)
//-Member: m_fog.colorSecondaryLerpTo (offset 1100) (type integer) (bits 32)
//-Member: m_fog.startLerpTo (offset 1128) (type float) (bits 0)
//-Member: m_fog.endLerpTo (offset 1132) (type float) (bits 0)
//-Member: m_fog.maxdensityLerpTo (offset 1136) (type float) (bits 0)
//-Member: m_fog.skyboxFogFactorLerpTo (offset 1124) (type float) (bits 0)
//-Member: m_fog.lerptime (offset 1140) (type float) (bits 0)
//-Member: m_fog.duration (offset 1144) (type float) (bits 0)
//-Member: m_fog.HDRColorScale (offset 1152) (type float) (bits 0)

float zm_fog_end;
int default_fog_entity = -1;
int zm_fog_entity = -1;
void set_zm_client_fog(bool join=true, bool initial = false)
{
    
    if (zm_stage<=ZM_END) return; //placeholder, never runs
    
    if (!IsValidEntRef(zm_fog_entity))
    {
        zm_fog_entity = CreateEntityByName("env_fog_controller");
        if (IsValidEntity(zm_fog_entity))
        {
            DispatchKeyValue(zm_fog_entity, "targetname", "zm_fog");
    		DispatchKeyValue(zm_fog_entity, "use_angles", "1");
    		DispatchKeyValueFloat(zm_fog_entity, "fogstart", 0.0);
    		DispatchKeyValue(zm_fog_entity, "fogblend", "0");
    		DispatchKeyValueFloat(zm_fog_entity, "fogend", 0.0);
    		DispatchKeyValueFloat(zm_fog_entity, "fogmaxdensity", 1.0);
    		DispatchKeyValue(zm_fog_entity, "heightFogStart", "0.0");
    		DispatchKeyValue(zm_fog_entity, "heightFogMaxDensity", "1.0");
    		DispatchKeyValue(zm_fog_entity, "heightFogDensity", "0.0");
    		DispatchKeyValue(zm_fog_entity, "fogenable", "1");
    		DispatchKeyValue(zm_fog_entity, "fogdir", "1 0 0");
    		DispatchKeyValue(zm_fog_entity, "angles", "0 180 0");
    		DispatchKeyValue(zm_fog_entity, "farz", "21000");
    		//DispatchKeyValue(zm_fog_entity, "foglerptime", "1");
    		DispatchKeyValue(zm_fog_entity, "fogcolor", "255 0 0");
    		DispatchKeyValue(zm_fog_entity, "fogcolor2", "255 0 0");
    		DispatchSpawn(zm_fog_entity);
            ActivateEntity(zm_fog_entity);
            TeleportEntity(zm_fog_entity, view_as<float>({ 10.0, 15.0, 20.0 }), NULL_VECTOR, NULL_VECTOR);
            AcceptEntityInput(zm_fog_entity, "TurnOn");
            zm_fog_entity = EntIndexToEntRef(zm_fog_entity);
            if (DEBUG) PrintToServer("[zm] zm_fog_entity %d created", zm_fog_entity);
        }
    }
    
    if (zm_client<0 || !IsValidClientZM()) return;
    
    if (join)
    {
        
        if (initial)
        {
            // this might be a handle or address... try to see if we can identify the fog controller
            //default_fog_entity = GetEntProp(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl");
            default_fog_entity = EntIndexToEntRef(GetEntPropEnt(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl"));
            //int test = GetEntPropEnt(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl");
            //int test2 = EntIndexToEntRef(test);
            //Handle test3 = view_as<Handle>(test2);
            char class[32];
            if (IsValidEntRef(default_fog_entity))
               GetEntityClassname(default_fog_entity, class, sizeof(class));
            if (DEBUG) PrintToServer("[zm] default_fog_entity %d %s", default_fog_entity, class);
            //zm_fog_start = GetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.start");
            zm_fog_end = GetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.end");
        }
        
        if (IsValidEntRef(zm_fog_entity))
        {
            if (DEBUG) PrintToServer("[zm] custom zombie master fog activated");
            SetVariantString("zm_fog");
            AcceptEntityInput(zm_client, "SetFogController");
            //SetEntPropEnt(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl",zm_fog_entity);
        }
        
        //SetEntProp(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl",zm_fog_entity);
        //AcceptEntityInput(zm_client,"SetFogController")
        // m_skybox3d.fog.enable
        // m_PlayerFog.m_hCtrl
        //SetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.start", 10000.0);
        //SetEntProp(zm_client, Prop_Send, "m_skybox3d.fog.enable", 0);
        SetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.end", 50000.0);
    }
    else
    {
        if (DEBUG) PrintToServer("[zm] default fog restored");
        if (IsValidEntRef(default_fog_entity)) SetEntPropEnt(zm_client, Prop_Send, "m_PlayerFog.m_hCtrl",default_fog_entity);
        //SetEntProp(zm_client, Prop_Send, "m_skybox3d.fog.enable", 1);
        //SetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.start", zm_fog_start);
        SetEntPropFloat(zm_client, Prop_Send, "m_skybox3d.fog.end", zm_fog_end);
    }
    
}

// Handled: invisible
// Continue: visible
//Action OnTransmitFog(int entity, int client)
//{
//   	//PrintToServer("[zm] OnTransmitFog");
//   	if (!g_bCvarAllow) return Plugin_Continue;
//   	if(GetEdictFlags(entity) & FL_EDICT_ALWAYS) SetEdictFlags(entity, GetEdictFlags(entity) ^ FL_EDICT_ALWAYS);
//   	if (client==zm_client) return Plugin_Handled;
//    return Plugin_Continue;
//}

//Action reactivate_fog(Handle timer = null, int fog_entity)
//{
//    PrintToServer("[zm] reactivate_fog");
//    //return Plugin_Continue;
//    //if (!IsValidEntRef(fog_entity)) return Plugin_Stop;
//    //SDKHook(fog_entity, SDKHook_SetTransmit, OnTransmitFog);
//    AcceptEntityInput(fog_entity, "TurnOn");
//    CreateTimer(1.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
//    return Plugin_Continue;
//}

Action check_fog_distance(Handle timer = null)
{
    float new_fog_distance = FOG_DISTANCE;
	int fog_controller = -1;
	while( (fog_controller = FindEntityByClassname(fog_controller, "env_fog_controller")) != INVALID_ENT_REFERENCE )
	{
		
		////SDKHook(fog_controller, SDKHook_SetTransmit, OnTransmitFog);
		//if(GetEdictFlags(fog_controller) & FL_EDICT_ALWAYS)
		//{
    	//	SetEdictFlags(fog_controller, GetEdictFlags(fog_controller) ^ FL_EDICT_ALWAYS);
    	//	AcceptEntityInput(fog_controller, "TurnOff");
    	//	SDKHook(fog_controller, SDKHook_SetTransmit, OnTransmitFog);
    	//	CreateTimer(1.0,reactivate_fog,fog_controller,TIMER_FLAG_NO_MAPCHANGE);
    	//	continue;
		//}
		
		//SetEdictFlags(fog_controller, GetEdictFlags(fog_controller) | FL_EDICT_DONTSEND);
		//AcceptEntityInput(fog_controller, "Kill");
		//AcceptEntityInput(fog_controller, "TurnOff");
		//continue;
		if (g_DHook_AcceptInput)
     	{
           	if (IsValidEntity(fog_controller))
           	   DHookEntity(g_DHook_AcceptInput, true, fog_controller, INVALID_FUNCTION, DHook_Fog_AcceptInput);
     	}
		bool enabled = GetEntProp(fog_controller, Prop_Data, "m_fog.enable") > 0;
		if (enabled)
		{
        		float fog_end = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.end");
        		float fog_farz = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.farz");
        		float maxdensity = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.maxdensity");
        		if (DEBUG) PrintToServer("[zm] Found env_fog_controller %d", fog_controller);
        		if (DEBUG) PrintToServer("[zm] end farz maxdensity: %f %f %f", fog_end, fog_farz, maxdensity);
        		if (maxdensity>=1.0)
        		{
            		//if (fog_end<new_fog_distance && fog_end>0.0) new_fog_distance = fog_end;
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
        PrintToServer("[zm] ZM spawner fog distance: %f", fog_distance);
	}
	
	return Plugin_Stop;
	
}

void zm_new_round()
{
    if (!g_bCvarAllow) return;
	
	force_started = false;
	
	l4d2_specials = true;
    if (strcmp(g_sCvarMPGameMode,"l4d1coop")==0 || strcmp(g_sCvarMPGameMode,"l4d1survival")==0)
        l4d2_specials = false;
	
	fog_distance = FOG_DISTANCE;
	
	roundcount += 1;
	
	saferoom_locked = false;
    
    if (DEBUG) PrintToServer("[zm] zm_new_round");
    if (DEBUG) PrintToServer("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
    saferoom_interacted = false;
    if(L4D_IsSurvivalMode())
    {
        zm_allow_spawns = false;
        g_iLockedDoor = INVALID_ENT_REFERENCE;
    }
    else
    {
        zm_allow_spawns = true;
        check_saferoom();
    }
    
    manual_panic = false;
    delete_all_infected();
    
    ZM_finale_announced = false;
    ZM_finale_ended = false;
    zm_can_start = !g_bLockSaferoom;
    t_last_update = GetEngineTime();
    t_last_panic = t_last_update;
    t_last_spawner_update = t_last_update;
    t_last_spawner_sound = t_last_update;
    t_finale = t_last_update;
    t_last_action = t_last_update;
    update_t_zm_activity(t_last_update);
    g_iAliveSurvivors = -1;
    
    if (IsValidClientZM()) QuitZM(zm_client,false);
    zm_client_userid = -1;
    
    CountClients();
    CountWitches(false);
    CountCommons(false);
    
    set_bank_begin();
    
    toggle_panic(false,true);
    
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    //if (infectedbots_dispose_cowards) SetConVarInt(infectedbots_dispose_cowards, 0);
    if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
    
    set_zm_stage(ZM_NEWROUND,true);
    
    safezone_navAreaId = -1;
    
    zm_use_notify = false;
    
    int entity = -1;
	while ((entity = FindEntityByClassname(entity, "func_playerinfected_clip")) != -1)
	{	
		AcceptEntityInput(entity, "kill"); 
	}
	
	fallen_spawned = false;
	jimmy_spawned = false;
	
	zm_menu_state = ZM_MENU_CLOSED;
	update_menus();
	
	if (!zm_timer) zm_update(zm_timer);
	else update_EMS_HUD();
	
	reset_available_zombies();
	
	info_director = FindEntityByClassname(-1, "info_director");
	// Listen to all info_director inputs
	if (g_DHook_AcceptInput)
	{
       	if (IsValidEntity(info_director))
       	   DHookEntity(g_DHook_AcceptInput, false, info_director, INVALID_FUNCTION, DHook_Director_AcceptInput);
	}
	
	check_fog_distance();
	
	// Find all ladders and transmit visibility to ZM
	//int ladder = -1;
	//char modelname[128];
	//int ladderteam = -1;
	//while( (ladder = FindEntityByClassname(ladder, "func_simpleladder")) != INVALID_ENT_REFERENCE )
	//{
		//if (GetEntProp(ladder, Prop_Data, "team")!=TEAM_INFECTED) continue;
		//ladderteam = GetEntProp(ladder, Prop_Data, "TeamNum");
		//GetEntPropString(ladder, Prop_Data, "m_ModelName", modelname, sizeof(modelname));
		//PrintToServer("[zm] Found infected ladder %d %s", ladder, modelname);
		//DispatchKeyValue(ladder, "team", "0");
		//AcceptEntityInput(ladder, "Enable");
		//SetEdictFlags(ladder, GetEdictFlags(ladder) | FL_EDICT_ALWAYS);
		//RemoveEntity(ladder);
		//SetEntityModel(ladder,MODEL_LADDER);
		//DispatchKeyValue(ladder, "model", MODEL_LADDER);
		
    //	SetEntProp(ladder, Prop_Send, "m_nGlowRangeMin", 0);
    //	SetEntProp(ladder, Prop_Send, "m_nGlowRange", 999999);
    //	SetEntProp(ladder, Prop_Send, "m_iGlowType", 3);
    //	SetEntProp(ladder, Prop_Send, "m_glowColorOverride", RGB_ZM);
    //	AcceptEntityInput(ladder, "StartGlowing");
    //	SetEntityRenderMode(ladder, RENDER_TRANSCOLOR);
    //    SetEntityRenderColor(ladder, 0, 0, 0, 0);
	//}
	
	remove_all_ZM_glows();
	
	lastdoor = -1;
	
	update_director_script_scopes(false);
	scope_changed = false;
	survival_activated = false;
	//manual_change = false;
	
	targetName_pending = "";
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		arr_biled[i] = false;
		arr_hp[i] = -1;
		if(IsClientInGame(i) && !IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
	}
    
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

void create_timer_add_available_zombie(float delay,int zClass, int round, int count=1)
{
    DataPack pack;
    CreateDataTimer(delay, timer_add_available_zombie, pack, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
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

void add_available_zombie(int zClass, int add=1)
{
    if (zClass>ZOMBIECLASS_TANK) return;
    
    available_zombie_arr[zClass] += add;
    if (available_zombie_arr[zClass]>max_zombie_arr[zClass]) available_zombie_arr[zClass] = max_zombie_arr[zClass];
    else if (available_zombie_arr[zClass]<0) available_zombie_arr[zClass] = 0;
    
    // Will this operation change available Specials?
    int add_SI;
    switch (zClass)
    {
        case ZOMBIECLASS_COMMON: { add_SI=0; }
        case ZOMBIECLASS_WITCH: { add_SI=0; }
        default: { add_SI = add; }
    }
    
    if (add_SI!=0)
    {
        //if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
        available_SI += add_SI;
        if (available_SI>max_SI) available_SI = max_SI;
        else if (available_SI<0) available_SI = 0;
        if (zClass == ZOMBIECLASS_TANK) create_boss_menu();
        else create_special_menu();
        zm_update(zm_timer);
    }
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

// Count Survivor and Special Infected (Players AND Bots)
Action CountClients(Handle timer = null)
{
	
	if (!g_bCvarAllow) return Plugin_Stop;
	
	if (DEBUG) PrintToServer("[zm] CountClients");
	
	clients_timer = INVALID_HANDLE;
	
	int allplayers = GetClientCount(false);
	if (allplayers<=0) return Plugin_Stop;
	
	int temp_SI = 0;
	int new_AllPlayerCount = 0;
	int clientcount = 0;
	int new_AliveSurvivors = 0;
	int zClass, health;
	reset_live_zombie_arr(false,false,true);
	
	int last_valid_target = -1; // if only one SI on the field, auto select them for ZM control
	for (int i=1;i<=MaxClients;i++)
	{
		//PrintToServer("[zm] CountClients %d", i);
		if (!IsClientConnected(i)) continue;
		clientcount += 1;
        if (!IsFakeClient(i))
        {
            new_AllPlayerCount += 1;
            if (i!=zm_client) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
        }
        if (!IsClientInGame(i)) continue;
		
		if (!IsPlayerAlive(i))
		{
    		L4D2_RemoveEntityGlow(i);
    		if (g_iGlowList[i]!=INVALID_ENT_REFERENCE) remove_ZM_glow(i);
    		continue;
		}
		
		switch(GetClientTeam(i))
		{
			case TEAM_INFECTED:
			{
				if (zm_stage<ZM_PREP && IsFakeClient(i)) ForcePlayerSuicide(i); // fix The Passing bug where 2 tanks spawn in the safe zone
     		    else if (!L4D_IsPlayerIncapacitated(i))
     		    {
         		   health = GetEntProp(i,Prop_Data,"m_iHealth");
         		   if (health>0)
         		   {
             		   temp_SI += 1;
             		   zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
             		   live_zombie_arr[zClass] += 1;
             		   last_valid_target = i;
             		   int glowref = g_iGlowList[i];
             		   if ( glowref==INVALID_ENT_REFERENCE || !IsValidEntity(glowref) )
             		      CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(i), TIMER_FLAG_NO_MAPCHANGE);
     		       }
     		    }
			}
			case TEAM_SURVIVOR:
			{
			    if(hp_timers[i]==INVALID_HANDLE)
    			    hp_timers[i] = CreateTimer(0.1,UpdateSurvivorGlow,i,TIMER_FLAG_NO_MAPCHANGE);
    			new_AliveSurvivors += 1;
			}
		}
		
		if (clientcount>=allplayers) break;
		
	}
	
	if (live_zombie_arr[ZOMBIECLASS_TANK]<=0) targetName_pending = "";
	
	if (temp_SI==1 && IsValidEntity(last_valid_target)) update_entref_control(EntIndexToEntRef(last_valid_target));
	
	bool do_zm_update = false;
	if (new_AllPlayerCount!=AllPlayerCount || new_AliveSurvivors!=g_iAliveSurvivors)
	{
    	AllPlayerCount = new_AllPlayerCount;
    	g_iAliveSurvivors = new_AliveSurvivors;
    	get_bank_rate(); // for ZM UI
    	SetCvarsZM();
    	do_zm_update = true;
	}
	if (live_SI!=temp_SI)
	{
	   live_SI = temp_SI;
	   do_zm_update = true;
	}
	
	if (IsValidClientZM() && do_zm_update)
	{
    	create_special_menu();
 	    create_boss_menu();
    	zm_update(zm_timer);
	}
	
	return Plugin_Stop;
	
}

Action ZMPanic(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (!panic) manual_panic = true;
    toggle_panic();
    return Plugin_Continue;
}

Action ZMTeleport(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    
    if (IsPlayerAlive(zm_client)) return Plugin_Continue;
    
    if (zm_stage<ZM_STARTED)
    {
        tp_survivor_start(zm_client);
        return Plugin_Continue;
    }
    
    int target = L4D_GetHighestFlowSurvivor();
    if (IsValidClient(target) && IsPlayerAlive(target))
    {
        float vTP[3];
        GetClientEyePosition(target, vTP);
        vTP[2] += 10.0;
        TeleportEntity(zm_client, vTP, NULL_VECTOR, NULL_VECTOR);
    }

    return Plugin_Continue;
}

void transfer_SI_properties(int entity_new, char[] modelname, float vOrigin[3], float vAngles[3], float vVelocity[3], int health, int maxhealth, int fFlags, float timestamp_cooldown, char targetname[64] = "")
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
   //SetEntProp(entity_new, Prop_Data, "m_fFlags", fFlags);
   if ((fFlags & FL_ONFIRE)>0) IgniteEntity(entity_new, IGNITE_TIME);
   
   TrimString(targetname);
   if (targetname[0]!=0)
      DispatchKeyValue(entity_new, "targetname", targetname);
   
}

bool already_replaced_SI = false; // track whether SI was already replaced. to prevent doubling and weird ping issues.

void remove_all_ZM_glows()
{
    if (DEBUG) PrintToServer("[zm] remove_all_ZM_glows");
    for(int i = 0; i < sizeof(g_iGlowList); i++)
	{
		if (g_iGlowList[i]==INVALID_ENT_REFERENCE) continue;
		remove_ZM_glow(i);
	}
	
	// tbd: loop over all prop_dynamic_ornament and check for "zm_glow" targetname
}

// remove glow of parent entity
void remove_ZM_glow(int entity)
{
    if (!IsValidEntity(entity))
    {
        if (DEBUG) PrintToServer("[zm] remove_ZM_glow %d skipped", entity);
        if (entity>=0 && entity<=MAXENTITIES) g_iGlowList[entity]=INVALID_ENT_REFERENCE;
        return; 
    }
    int entref_glow = g_iGlowList[entity];
    if (entref_glow==INVALID_ENT_REFERENCE) return;
    g_iGlowList[entity] = INVALID_ENT_REFERENCE;
    if ( IsValidEntRef(entref_glow) && HasEntProp(entref_glow, Prop_Send, "m_CollisionGroup") )
    {
       static char class[32];
       GetEntityClassname(entref_glow, class, sizeof(class));
       if (strcmp(class,"prop_dynamic_ornament")==0 && (GetEntProp(entref_glow, Prop_Send, "m_CollisionGroup")==0))
       {
   	       AcceptEntityInput(entref_glow, "kill");
   	       if (DEBUG) PrintToServer("[zm] remove_ZM_glow %d killed prop_dynamic_ornament %d", entity, entref_glow);
   	       return;
       }
    }
    if (DEBUG) PrintToServer("[zm] remove_ZM_glow %d unexpectedly did nothing", entity);
}

//CTerrorPlayer->m_vomitStart (16152) changed from 0.0000 to 574.6000
//CTerrorPlayer->m_vomitFadeStart (16156) changed from 0.0000 to 579.6000
Action UpdateSurvivorGlow(Handle timer, int client)
{
    if (!IsValidClient(client)) return Plugin_Stop;
    hp_timers[client] = INVALID_HANDLE;
    if (!IsPlayerAlive(client) || client==zm_client)
    {
        L4D2_RemoveEntityGlow(client);
        arr_hp[client] = -1;
        return Plugin_Stop;
    }
    if (GetClientTeam(client)!=TEAM_SURVIVOR) return Plugin_Stop;
    if (arr_biled[client]) return Plugin_Stop; // asdf future: check entity for vomit state instead
    
    int hp = GetEntProp(client,Prop_Data,"m_iHealth");
    if (hp==arr_hp[client]) return Plugin_Stop;
    
    char name[MAX_NAME_LENGTH]; 
    GetClientName(client,name,sizeof(name));
    if (DEBUG) PrintToServer("[zm] UpdateSurvivorGlow %s", name);
    
    int color[3];
    GetSurvivorHealthColor(client,hp,color);
    
    //L4D2_RemoveEntityGlow(i);
    //L4D2_RemoveEntityGlow_Color(i);
    L4D2_SetPlayerSurvivorGlowState(client,false);
	L4D2_SetEntityGlow(client,L4D2Glow_Constant,999999,0,color,false);
	//L4D2_RemoveEntityGlow_Color(i);
	//SetEntProp(i, Prop_Send, "m_nGlowRangeMin", 0);
	//SetEntProp(i, Prop_Send, "m_nGlowRange", 999999);
	//SetEntProp(i, Prop_Send, "m_iGlowType", 3);
	//SetEntProp(i, Prop_Send, "m_glowColorOverride", 256*255);
	//AcceptEntityInput(i, "StartGlowing");
	
	arr_hp[client] = hp;
	
	return Plugin_Stop;
    
}

// Survivor health interpolator
static int RGB_CRITICAL[3] =    {160,24,24};
static int RGB_LOW[3] =         {178,63,0};
static int RGB_MEDIUM[3] =      {150,122,8};
static int RGB_HIGH[3] =        {9,175,49};
void GetSurvivorHealthColor(int client, int hp, int color[3])
{
      
      if (L4D_IsPlayerIncapacitated(client) || hp<=1)
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

// Infected unit glow -- white
Action CreateZMGlow_white(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target);
    return Plugin_Stop;
}

// Saferoom door glow -- red
Action CreateZMGlow_red(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target,true);
    return Plugin_Stop;
}

Action update_zm_glow(Handle timer, int parent)
{
   	if (parent<0 || parent>=MAXENTITIES) return Plugin_Stop;
   	if (DEBUG) PrintToServer("[zm] update_zm_glow");
   	hp_timers[parent] = INVALID_HANDLE;
   	int entref_glow = g_iGlowList[parent];
   	if (!IsValidEntRef(entref_glow)) return Plugin_Stop;
   	L4D2_RemoveEntityGlow(parent);
   	int health = GetEntProp(parent,Prop_Data,"m_iHealth");
   	if (IsValidClient(parent))
   	{
       	L4D2_SetPlayerSurvivorGlowState(parent,false);
       	if (L4D_IsPlayerIncapacitated(parent)) health=1;
       	else if (!IsPlayerAlive(parent)) health=0;
   	}
   	
   	int color[3];
   	if (health<=1)
   	{
       	color[0] = 255;
    }
    else
    {
        int max_health = GetEntProp(parent,Prop_Data,"m_iMaxHealth");
        float fraction = 1.0*health/max_health;
        //if (fraction<0.1) fraction = 0.1;
        int RGB_frac = RoundFloat(255*fraction);
       	color[0] = 255;
    	color[1] = RGB_frac;
    	color[2] = RGB_frac;
	}
	
	if (health<=0)
	{
    	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
    	AcceptEntityInput(entref_glow, "Kill");
	}
	else
	{
    	char targetName[64];
        GetEntPropString(parent, Prop_Data, "m_iName", targetName, sizeof(targetName));
    	bool flashing = false;
    	if (EntIndexToEntRef(parent)==entref_control || strcmp(targetName,"zm_unit_spotted")==0 ) flashing = true;
    	//SetEntProp(entref_glow, Prop_Send, "m_glowColorOverride", iColor);
    	L4D2_SetEntityGlow(entref_glow,L4D2Glow_Constant,999999,0,color,flashing);
    	
    	if (active_looktarget && entref_control==EntIndexToEntRef(parent)) update_ZM_looktarget_HP();
    	
	}
	
	return Plugin_Stop;
	
}

// Handled: invisible
// Continue: visible
// future tbd asdf: separate transmit for alive clients. stop transmitting if they're not alive
Action OnTransmitZM(int entity, int client)
{
   	int parent = GetEntPropEnt(entity,Prop_Data,"m_pParent");
   	bool valid = IsValidEntity(parent);
   	if (valid && IsValidClient(parent) && !IsPlayerAlive(parent)) valid = false;
   	
   	if (valid && client==zm_client)
   	{
       	return Plugin_Continue;
   	}
   	else if (!valid || zm_client<0)
   	{
       	if (DEBUG) PrintToServer("[zm] OnTransmitZM killing glow %d, parent %d", entity, parent); 
       	if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
       	AcceptEntityInput(entity, "Kill");
   	}
    return Plugin_Handled;
}

void CreateZMGlow(int target, bool red = false)
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
	    AcceptEntityInput(glowref,"Kill");
	}
	
	if (DEBUG) PrintToServer("[zm] CreateZMGlow");
	
	int glow = CreateEntityByName("prop_dynamic_ornament");
	if (!IsEntitySafe(glow)) return;
	
	int eFlags = GetEdictFlags(target);
	if ((eFlags & FL_EDICT_ALWAYS)<=0) SetEdictFlags(target, eFlags | FL_EDICT_ALWAYS);
	
	char sModelName[64];
	GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
	
	SetEntityModel(glow, sModelName);
	DispatchSpawn(glow);
	SetEntProp(glow, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRange", 999999);
	SetEntProp(glow, Prop_Send, "m_iGlowType", 3);
	if (red) SetEntProp(glow, Prop_Send, "m_glowColorOverride", 254);
	else SetEntProp(glow, Prop_Send, "m_glowColorOverride", RGB_ZM);
	AcceptEntityInput(glow, "StartGlowing");
	SetEntityRenderMode(glow, RENDER_TRANSCOLOR);
	SetEntityRenderColor(glow, 0, 0, 0, 0);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", target);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetAttached", target);
	//int effects = GetEntProp(glow, Prop_Data, "m_fEffects");
	//SetEntProp(glow, Prop_Data, "m_fEffects", effects | 0x001);
    g_iGlowList[target] = EntIndexToEntRef(glow);
	SDKHook(glow, SDKHook_SetTransmit, OnTransmitZM);
	DispatchKeyValue(glow, "targetname", "zm_glow");
	
	if (!red)
	{
    	SDKHook(target, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
    	update_zm_glow(null,target);
	}
	
	
	if (DEBUG) PrintToServer("[zm] CreateZMGlow %d %d %d", target, glow, g_iGlowList[target]);
	
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    if (!IsValidClientZM()) return;
    if (hp_timers[victim]==INVALID_HANDLE)
           hp_timers[victim] = CreateTimer(0.1,update_zm_glow,victim,TIMER_FLAG_NO_MAPCHANGE);
}

//void cleanup_bad_glows()
//{
//    PrintToServer("[zm] cleanup_bad_glows");
//    int child = -1;
//    while ((child = FindEntityByClassname(child, "prop_dynamic_ornament")) != -1)
//    {
//        if (IsValidEntity(child) && child > MaxClients)
//        {
//            int parent = GetEntPropEnt(child,Prop_Data,"m_pParent");
//            if (!IsValidEntity(parent))
//            {
//                AcceptEntityInput(child, "Kill");
//                if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
//                continue;
//            }
//            
//            if ( IsValidClient(parent) && IsClientInGame(parent) && !IsPlayerAlive(parent) )
//            {
//                AcceptEntityInput(child, "Kill");
//                if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
//                continue;
//            }
//            
//            static char class[32];
//            GetEntityClassname(parent, class, sizeof(class));
//            if (strcmp(class,"witch")==0)
//            {
//                AcceptEntityInput(child, "Kill");
//                if (parent>=0 && parent<MAXENTITIES) g_iGlowList[parent] = INVALID_ENT_REFERENCE;
//                continue;
//            }
//            
//            
//        }
//    }
//}



Action Timer_Clear_targetname_pending(Handle timer = null)
{
    if (targetName_pending[0]!=0)
    {
        targetName_pending = "";
        PrintToServer("[zm] unexpectedly cleared targetName_pending");
    }
    return Plugin_Stop;
}

Action ZMControlSI(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Stop;
    
    if (is_zm_spamming()) return Plugin_Continue;
    
    if (DEBUG) PrintToServer("[zm] ZMControlSI");
    
    //char name[32];
    
    int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
    
    // ZM wants to let go of special infected.
    if ( IsPlayerAlive(zm_client) && GetClientTeam(zm_client)==TEAM_INFECTED )
    {
        if ( L4D2_GetSurvivorVictim(zm_client)<=0 &&
             ( !ZM_finale_announced || zClass!=ZOMBIECLASS_TANK ) )
        {
            
            SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            
            
            
            float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
            GetClientAbsOrigin(zm_client, vOrigin);
            GetClientEyeAngles(zm_client, vAngles); 
            GetClientEyePosition(zm_client, vEye);
            GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
            int health = GetEntProp(zm_client,Prop_Data,"m_iHealth");
            int maxhealth = GetEntProp(zm_client,Prop_Data,"m_iMaxHealth");
            int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
            zm_use_notify = true;
            
            char sModelName[64];
            GetEntPropString(zm_client, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
            
            //get_zombieclass_name(zClass,name);
            //PrintToServer("[zm] Letting go of %s with %d HP", name, health);
            
            //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
            
            //SetEntProp(zm_client,Prop_Data,"m_iHealth",health-1); //prevent refund
            
            char targetName[64];
            GetEntPropString(zm_client, Prop_Data, "m_iName", targetName, sizeof(targetName));
            if (strcmp(targetName,"zm_control")==0) targetName = "";
            else if (strcmp(targetName,"zm_unit_control")==0) targetName = "zm_unit";
            DispatchKeyValue(zm_client, "targetname", "zm_client");
            
            //ForcePlayerSuicide(zm_client);
            //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            if (zClass == ZOMBIECLASS_TANK)
            {
                //L4D2Direct_TryOfferingTankBot(zm_client,false);
                //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
                if (targetName[0]!=0 && strcmp(targetName,"zm_client")!=0)
                {
                    targetName_pending = targetName;
                    maxhp_pending = maxhealth;
                    if (DEBUG) PrintToServer("[zm] targetName_pending %s", targetName_pending);
                    CreateTimer(0.1,Timer_Clear_targetname_pending,TIMER_FLAG_NO_MAPCHANGE);
                    
                }
                L4D_ReplaceWithBot(zm_client);
            }
            else
            {
                //L4D_ReplaceWithBot(zm_client); // why doesn't this work :/
                float timestamp_cooldown = 0.0;
                int ability = GetEntPropEnt(zm_client, Prop_Send, "m_customAbility");
                if (ability > 0 && IsValidEdict(ability))
                {
                    timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
                    //float m_duration = GetEntPropFloat(ability, Prop_Send, "m_duration");
                    //PrintToServer("[zm] Saving SI cooldown %f %f", cooldown_remaining,m_duration);
                }
                //SetEntProp(zm_client,Prop_Data,"m_iHealth",health-1); //prevent refund
                live_SI -= 1;
                live_zombie_arr[zClass] -= 1;
                
                int bot = ZM_Spawn_SI(zm_client,zClass,true,true,vOrigin);
                if (IsValidEntity(bot)) transfer_SI_properties(bot,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
                
            }
            
            zm_just_died = true;
            L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
            SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
            if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
            L4D_CleanupPlayerState(zm_client);
            //remove_attached_lights(zm_client);
            SetEntityMoveType(zm_client, MOVETYPE_NONE);
            SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
            SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
            SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
            TeleportEntity(zm_client, vEye, vAngles, NULL_VECTOR);
            //RequestFrame(OnNextFrame_FixCamera, GetClientUserId(zm_client));
            CreateTimer(0.1,ZM_FixCamera,GetClientUserId(zm_client),TIMER_FLAG_NO_MAPCHANGE);
            //JoinZM(zm_client,0);
            
            //cleanup_bad_glows();
        
        }
        else update_hint("%T", "Cannot control", zm_client);
        
        return Plugin_Continue;
        
    }
    
    if (zm_stage<ZM_STARTED)
    {
        update_hint("%T", "Round not started", zm_client);
        return Plugin_Continue;
    }
    
    update_ZM_looktarget(false);
    if (!IsValidEntRef(entref_control))
    {
        update_hint("%T", "Invalid target", zm_client);
        return Plugin_Continue;
    }
    int entity = EntRefToEntIndex(entref_control);
    if (!IsValidEntity(entity) || !IsValidClient(entity) || GetClientTeam(entity)!=TEAM_INFECTED || !IsFakeClient(entity) || !IsPlayerAlive(entity)) 
    {
        update_hint("%T", "Invalid target", zm_client);
        return Plugin_Continue;
    }
    
    static char class[32];
  	GetEntityClassname(entity, class, sizeof(class));
  	if (strcmp(class,"player")==0 && L4D2_GetSurvivorVictim(entity)<=0 )
  	{
         float vOrigin[3], vAngles[3], vVelocity[3];
         GetClientAbsOrigin(entity, vOrigin);
         GetClientEyeAngles(entity, vAngles); 
         GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vVelocity);
         int health = GetEntProp(entity,Prop_Data,"m_iHealth");
         //int max_health = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
         if (health<=0 || L4D_IsPlayerIncapacitated(entity))
         {
             update_hint("%T", "Cannot control", zm_client);
             return Plugin_Continue;
         }
         int maxhealth = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
         int fFlags = GetEntProp(entity, Prop_Data, "m_fFlags");
         zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
         
         char targetName[64];
         GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
         if (strcmp(targetName,"zm_unit")==0) DispatchKeyValue(entity, "targetname", "zm_unit_control");
         else
         {
             DispatchKeyValue(entity, "targetname", "zm_control");
             if (targetName[0]==0) DispatchKeyValue(zm_client, "targetname", "zm_control");
         }
         
         char sModelName[64];
         GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
         
         remove_ZM_glow(entity);
         
         float timestamp_cooldown = 0.0;
         int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
         if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
         
         if (active_looktarget) update_hint("");
         
         zm_just_died = true;
         ChangeClientTeam(zm_client,TEAM_ZM);
         L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
         
         if (zClass==ZOMBIECLASS_TANK) L4D_ReplaceTank(entity,zm_client);
         else L4D_TakeOverZombieBot(zm_client,entity);
         L4D_CleanupPlayerState(zm_client);
         
         transfer_SI_properties(zm_client,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
         
         already_replaced_SI = false;
         zm_use_notify = true;
         
         SDKHook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
         //remove_attached_lights(zm_client);
         
         //if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
         
         //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
         //L4D_SetPlayerSpawnTime(zm_client,1.0,true);
         //L4D_BecomeGhost(zm_client);
         //L4D_SetClass(zm_client, zClass);
         //L4D_BecomeGhost(zm_client);
         //TeleportEntity(zm_client, vOrigin, NULL_VECTOR, NULL_VECTOR);
         //L4D_MaterializeFromGhost(zm_client);
         //TeleportEntity(zm_client, vOrigin, vAngles, vVelocity);	
	         //L4D_CleanupPlayerState(zm_client);
	         //SetEntProp(zm_client,Prop_Data,"m_iHealth",health);
	         //SetEntProp(zm_client,Prop_Data,"m_fFlags",fFlags);
	       
	       
  	 }
  	 else update_hint("%T", "Cannot control", zm_client);
  	     

    
    return Plugin_Continue;
}

float zm_deathPos[3], zm_deathAngles[3];
// Try replacing with SDKHook_OnTakeDamageAlive
Action OnTakeDamage_ZM(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
        
        if (!g_bCvarAllow || victim!=zm_client || GetClientTeam(victim)!=TEAM_INFECTED)
        {
            SDKUnhook(victim, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            return Plugin_Continue;
        }
        
        if (!IsPlayerAlive(victim))
        {
            damage *= 0.0;
            return Plugin_Stop;
        }
        
        int health = GetEntProp(victim, Prop_Data, "m_iHealth");
        int new_health = health-RoundFloat(damage);
        int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
        if (DEBUG) PrintToServer("[zm] OnTakeDamage_ZM %d %f -> %d, bool %d", health, damage, new_health, already_replaced_SI);
        if (new_health<=5 && (fFlags & FL_ONFIRE)) new_health = 0;
        if (new_health>0 && L4D_IsPlayerIncapacitated(victim))
        {
            new_health = 0;
            health = 0;
        }
        
        if (new_health<=0 && IsPlayerAlive(victim))
        {
            
            int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
            
            //SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            if (panic_target==zm_client) panic_target = -1;
            
            if (!already_replaced_SI && (!ZM_finale_announced || zClass!=ZOMBIECLASS_TANK))
            {
            
                float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
                GetClientAbsOrigin(zm_client, vOrigin);
                GetClientEyeAngles(zm_client, vAngles);
                zm_deathAngles = vAngles;
                GetClientEyePosition(zm_client, vEye);
                zm_deathPos = vEye;
                GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
    
                char sModelName[64];
                GetEntPropString(zm_client, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
    
                float timestamp_cooldown = 0.0;
                int ability = GetEntPropEnt(zm_client, Prop_Send, "m_customAbility");
                if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
                live_SI -= 1;
                live_zombie_arr[zClass] -= 1;
                
                int maxhealth = GetEntProp(victim, Prop_Data, "m_iMaxHealth");
                
                //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
                //SetEntityFlags(zm_client, GetEntityFlags(zm_client) & FL_FROZEN);
                //SetEntityMoveType(zm_client, MOVETYPE_NONE);
                
                //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
                //L4D_State_Transition(zm_client, STATE_DEATH_WAIT_FOR_KEY);
                //SetEntProp(zm_client, Prop_Send, "m_zombieClass", ZOMBIECLASS_SMOKER);
                //L4D_BecomeGhost(zm_client);
                //L4D_State_Transition(zm_client, STATE_GHOST);
                //SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
                //SetEntityFlags(zm_client, GetEntityFlags(zm_client) & FL_FROZEN);
                //SetEntityMoveType(zm_client, MOVETYPE_NONE);
                //L4D_State_Transition(zm_client, STATE_GHOST);
                //CreateTimer(0.5,unfreeze_zm,TIMER_FLAG_NO_MAPCHANGE);
                
                //TeleportEntity(zm_client, zm_deathPos, NULL_VECTOR, NULL_VECTOR);
                //SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0);
                //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
                //SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
               // SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
                //SetEntPropEnt(zm_client, Prop_Send, "m_hViewEntity", -1);
        	    //SetClientViewEntity(zm_client, zm_client);
        	    //SetEntityFlags(zm_client, GetEntityFlags(zm_client) & ~FL_FROZEN);
        	    //SetEntPropEnt(zm_client, Prop_Send, "m_hZoomOwner", -1);
        	    //SetEntProp(zm_client, Prop_Send, "m_iFOV", 0);
        	    //SetEntProp(zm_client, Prop_Send, "m_iFOVStart", 0);
        	    //SetEntPropFloat(zm_client, Prop_Send, "m_flFOVRate", 0.0);
        	    //SetEntProp(zm_client, Prop_Data, "m_fFlags", 65664);  // FL_CLIENT | FL_AIMTARGET
        	    //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        	    //SetEntityMoveType(zm_client, 10);
        	    //L4D_State_Transition(zm_client, STATE_GHOST);
        	    //L4D_BecomeGhost(zm_client);
        	    
	            char targetName[64];
                GetEntPropString(zm_client, Prop_Data, "m_iName", targetName, sizeof(targetName));
                if (strcmp(targetName,"zm_control")==0) targetName = "";
                else if (strcmp(targetName,"zm_unit_control")==0) targetName = "zm_unit";
                
                int bot = ZM_Spawn_SI(zm_client,zClass,true,true,vOrigin,false);
                //int bot = -1;
                already_replaced_SI = true;
                if (IsValidEntity(bot))
                {
                    if (attacker==zm_client) attacker = bot;
                    if (DEBUG) PrintToServer("[zm] OnTakeDamage_ZM replaced with bot, bool %d", already_replaced_SI);
                    transfer_SI_properties(bot,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
                    //SetClientName(bot, "bozo");
                    //SetEntProp(bot, Prop_Send, "m_bSurvivorGlowEnabled", 0);
                    //SetEntProp(bot, Prop_Send, "m_glowColorOverride", 0);
                    //AcceptEntityInput(bot, "StopGlowing");
                    //ForcePlayerSuicide(bot);
                    //SDKHooks_TakeDamage(bot,attacker,attacker,damage,damagetype,-1,{0.0,0.0,0.0},{0.0,0.0,0.0},false);
                    //SDKHooks_TakeDamage(bot,inflictor,attacker,damage,damagetype,weapon,damageForce,damagePosition,false);
                    //RequestFrame(ForcePlayerSuicide,bot);
                    DataPack data = CreateDataPack();
                    data.WriteCell(GetClientUserId(bot));
                    //data.WriteCell(inflictor);
                    data.WriteCell(EntIndexToEntRef(attacker));
                    data.WriteFloat(damage);
                    data.WriteCell(damagetype);
                    data.WriteCell(weapon);
                    data.WriteFloatArray(damageForce,3);
                    data.WriteFloatArray(damagePosition,3);
                    RequestFrame(OnNextFrame_Damage,data);
                }
                
                //Cmd_FullUpdate(zm_client); // prevent camera stutter
            
            }
            else if (zClass==ZOMBIECLASS_TANK) ForcePlayerSuicide(zm_client);
            
            //remove_attached_lights(zm_client);
            
            //L4D_SetClass(int client, int zombieClass)
            //L4D_BecomeGhost(int client);
            
            L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
            SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
            SetEntPropEnt(zm_client, Prop_Send, "m_hViewEntity", -1);
       	    SetClientViewEntity(zm_client, zm_client);
       	    SetEntPropEnt(zm_client, Prop_Send, "m_hZoomOwner", -1);
       	    SetEntProp(zm_client, Prop_Send, "m_iFOV", 0);
   	        SetEntProp(zm_client, Prop_Send, "m_iFOVStart", 0);
       	    SetEntPropFloat(zm_client, Prop_Send, "m_flFOVRate", 0.0);
            //JoinZM(zm_client,0);
            L4D_CleanupPlayerState(zm_client);
            SetEntityMoveType(zm_client, MOVETYPE_NONE);
            SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
            SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
            SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
            TeleportEntity(zm_client, zm_deathPos, zm_deathAngles, NULL_VECTOR);
            //RequestFrame(OnNextFrame_FixCamera, GetClientUserId(zm_client));
            CreateTimer(0.30,ZM_FixCamera,GetClientUserId(zm_client),TIMER_FLAG_NO_MAPCHANGE);
            
            ////L4D_RespawnPlayer(zm_client);
            //L4D_SetBecomeGhostAt(zm_client,0.0);
            
            damage *= 0.0;
            return Plugin_Stop;
        }
        return Plugin_Continue;
} 

Action ZM_FixCamera(Handle timer, int userid)
{
    if (!IsValidClientZM()) return Plugin_Stop;
    int client = GetClientOfUserId(userid);
    if (client!=zm_client) return Plugin_Stop;
    SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
    SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
    SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
        
    //baseclass->m_flProgressBarStartTime (10500) changed from 2931.5334 to 2941.5668
    ///m_stunTimer->m_timestamp (13020) changed from -1.0000 to 2941.5668
    //terrorlocaldata->m_TimeForceExternalView (16412) changed from -1.0000 to 2947.3334
    //m_staggerTimer->m_timestamp (12792) changed from -1.0000 to 2947.5668
    //CTerrorPlayer->m_staggerStart (12796) changed from 0.0000 0.0000 0.0000 to -6851.1694 -1033.1778 384.0312
    //CTerrorPlayer->m_staggerDir (12808) changed from 0.0000 0.0000 0.0000 to 0.5364 -0.8439 0.0000
    //CTerrorPlayer->m_staggerDist (12820) changed from 0.0000 to 400.0000
    // m_Collision->m_usSolidFlags (436) changed from 16 to 20
    // serveranimdata->m_flCycle (1168) changed from 0.1042 to 0.0000
    // baseclass->m_hGroundEntity (600) changed from 125337600 to -1
    // terrorlocaldata->m_scrimmageSphereCenter (11268) changed from -6855.1640 -1066.9466 419.5312 to -6858.5883 -1132.8811 418.0312
    //terrorlocaldata->m_scrimmageSphereInitialRadius (11280) changed from 2438.6347 to 2433.9594
    //terrorlocaldata->m_scrimmageStartTime (11288) changed from 2902.7001 to 2931.5334
    
    //SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0),
    //SetEntProp(zm_client, Prop_Send, "m_nSolidType", 0),
    //SetEntProp(zm_client, Prop_Send, "m_usSolidFlags", 0x0004);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageSphereInitialRadius", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageStartTime", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_TimeForceExternalView", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_staggerDist", 0.0); 
    SetEntPropVector(zm_client, Prop_Send, "m_scrimmageSphereCenter", {0.0,0.0,0.0});
    
    JoinZM(zm_client,0);
    
    EmitSoundToClient(zm_client,SOUND_VISION);
    
    return Plugin_Stop;
}

void OnNextFrame_Damage(any packed)
{
    DataPack pack = view_as<DataPack>(packed);
    pack.Reset();
    int userid = pack.ReadCell();
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
    {
        PrintToServer("[zm] OnNextFrame_Damage failed, report this to mod authors");
        CloseHandle(pack);
        return;
    }
    float damageForce[3],damagePosition[3];
    //int inflictor = pack.ReadCell();
    int attacker = EntRefToEntIndex(pack.ReadCell());
    if (!IsValidEntity(attacker)) attacker = client;
    float damage = pack.ReadFloat();
    int damagetype = pack.ReadCell();
    int weapon = pack.ReadCell();
    pack.ReadFloatArray(damageForce,3);
    pack.ReadFloatArray(damagePosition,3); 
    //SDKHooks_TakeDamage(client,inflictor,attacker,damage,damagetype,weapon,damageForce,damagePosition,false);
    SDKHooks_TakeDamage(client,attacker,attacker,damage,damagetype,weapon,damageForce,damagePosition,false);
    //ForcePlayerSuicide(client,true);
    CloseHandle(pack);
}

//void OnNextFrame_UpdateDeathTime(int userid)
//{
//    int client = GetClientOfUserId(userid);
//	if (!IsValidClient(client)) return;
	//SetEntPropFloat(client, Prop_Send, "m_flDeathTime", GetEntPropFloat(client, Prop_Send, "m_flDeathTime") - 10.0); 
	//SetEntProp(client, Prop_Send, "m_nTickBase", GetEntProp(client, Prop_Send, "m_nTickBase")+3);
	//SetEntProp(client, Prop_Send, "m_flSimulationTime", 154);
	//SetEntProp(client, Prop_Send, "m_flAnimTime", 154);
	//SetEntProp(client, Prop_Send, "m_nNewSequenceParity", 0);
	//SetEntProp(client, Prop_Send, "m_nResetEventsParity", 0);
	//SetEntPropFloat(client, Prop_Send, "m_flCycle", 0.0);
	//SetEntPropFloat(client, Prop_Send, "m_flFOVTime", GetEntPropFloat(client, Prop_Send, "m_flFOVTime")+6.0);
	//SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime")+6.0);
	//SetEntPropFloat(client, Prop_Send, "m_fServerAnimStartTime", GetEntPropFloat(client, Prop_Send, "m_fServerAnimStartTime")+6.0);
	
	//if (client==zm_client)
	//{
    //	SetEntProp(client, Prop_Send, "m_lifeState", 2);
    //    SetEntProp(client, Prop_Send, "m_iObserverMode", 6);
    //    SetEntProp(client, Prop_Send, "m_iPlayerState", 6);
    //    SetEntProp(client, Prop_Send, "m_scrimmageType", 0);
	//}
//}


public Action L4D_OnTryOfferingTankBot(int tank_index, bool &enterStasis)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	PrintToServer("[zm] L4D_OnTryOfferingTankBot %d %d", tank_index, enterStasis);
	return Plugin_Handled;
	
	//if(!L4D_HasPlayerControlledZombies() && tank_index && IsClientInGame(tank_index) && IsFakeClient(tank_index))
	//{
	//	return Plugin_Handled;
	//}
	//return Plugin_Continue;
}

Action ZM_Chase_ZM(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM()  || zm_client!=client) return Plugin_Continue;
    if (panic) Chase(zm_client);
    else update_hint("%T", "Panic must be ON", zm_client);
    return Plugin_Continue;
}

void CountCommons(bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_COMMON]>0 || !fast)
    {
        if (DEBUG) PrintToServer("[zm] CountCommons expensive");
        live_zombie_arr[ZOMBIECLASS_COMMON] = L4D_GetCommonsCount();
    }
}

void start_zm_round(bool play_sound = true)
{
 if (zm_stage<ZM_STARTED)
 {
     PrintToChatAll("[zm] %t", "Round started");
     if (IsValidClientZM()) PrintHintText(zm_client, "%t", "Round started");
     update_hint("%T", "Round started", zm_client);
     if (play_sound) EmitSoundToAll(SOUND_START);
     
     EmitSoundToAll(SOUND_ELLIS_ZM);
     
     //SOUND_ELLIS_ZM
     
     CountClients();
 }
 zm_allow_spawns = true;
 set_zm_stage(ZM_STARTED);
 update_t_zm_activity();
 check_saferoom();
 saferoom_lock(false);
 if (g_iLockedDoor!=INVALID_ENT_REFERENCE)
 {
     if (GetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked")>0) AcceptEntityInput(g_iLockedDoor, "Unlock");
     AcceptEntityInput(g_iLockedDoor, "Open");
 }
 //freeze_team(false);
 freeze_team(false,TEAM_INFECTED);
 saferoom_locked = false;
 //if (IsValidEntRef(g_iLockedDoor)) AcceptEntityInput(g_iLockedDoor, "Open");
 create_other_menu();
 scope_changed = false;
 update_director_script_scopes(false);
 scope_changed = false;
}

void update_ZM_looktarget_HP(int health_manual = -1)
{
  	 if (!active_looktarget || !IsValidEntRef(entref_control) || !IsValidClientZM())
  	 {
      	 active_looktarget = false;
      	 return;
  	 }
  	 int health;
  	 if ( health_manual==0 || L4D_IsPlayerIncapacitated(entref_control) || !IsPlayerAlive(EntRefToEntIndex(entref_control)) )
  	    health = 0;
  	 else
  	    health = GetEntProp(entref_control,Prop_Data,"m_iHealth");
  	 //if (health<=max_health)
  	 //{
         if (health>0)
         {
             int zClass = GetEntProp(entref_control, Prop_Send, "m_zombieClass");
             char zClassName[32]; 
             get_zombieclass_name(zClass,zClassName);
             int max_health = GetEntProp(entref_control,Prop_Data,"m_iMaxHealth");
          	 update_hint("%T", "Selected Special", zm_client, zClassName, health, max_health);
          	 active_looktarget = true;
      	 }
      	 else
      	 {
          	 update_hint("");
      	 }
  	 //}
}

void update_entref_control(int new_entref)
{
    if (!IsValidEntRef(new_entref)) return;
    int new_target = EntRefToEntIndex(new_entref);
    if (!IsValidClient(new_target)) return;
    int old_target = -1;
    if (IsValidEntRef(entref_control)) old_target = EntRefToEntIndex(entref_control);
    if (!IsValidClient(old_target)) old_target = -1;
    entref_control = INVALID_ENT_REFERENCE;
    if (old_target>0) update_zm_glow(null,old_target);
    entref_control = new_entref;
    update_zm_glow(null,new_target);
}

// asdf future: make trace through world geometry to select units through walls
int entref_lastlook = -1;
void update_ZM_looktarget(bool draw = true)
{
   entref_lastlook = -1;
   if (!IsValidClientZM()) return;
   int target = GetClientAimTarget(zm_client, false);
   if (!IsValidEntity(target) || target==zm_client) return;
   int health = GetEntProp(target,Prop_Data,"m_iHealth");
   if (health<=0) return;
   entref_lastlook = EntIndexToEntRef(target);
   static char class[32];
   GetEntityClassname(target, class, sizeof(class));
   if ( strcmp(class,"infected")==0 || strcmp(class,"witch")==0 || (strcmp(class,"player")==0 && GetClientTeam(target)==TEAM_INFECTED && IsFakeClient(target)) )
   {
  	 int entref_temp = EntIndexToEntRef(target);
  	 if (draw && entref_temp!=entref_delete)
  	 {
  	    float vOrigin[3];
  	    L4D_GetEntityWorldSpaceCenter(target,vOrigin);
      	TE_SetupBeamRingPoint(vOrigin,50.0,0.0,g_iLaser,g_iHalo,0,0,1.0,1.5,0.0,color_unit_select,0,0);
        TE_SendToClient(zm_client);
  	 }
  	 entref_delete = entref_temp;
  	 if (strcmp(class,"player")==0 && !L4D_IsPlayerIncapacitated(target))
  	 {
      	 active_looktarget = true; 
      	 update_entref_control(entref_temp);
      	 active_looktarget = true;
  	 }
   
   }
   
}

int old_scope0, old_scope1, old_scope2, old_scope3, old_scope4;
//int old_CommonLimit = -1;

// If scope changed, a panic might just start.
// Listen for next 10 seconds for a pending mob, or mobrush, or timer reset, or mobspawn

void update_director_script_scopes(bool warn = true)
{
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    if (old_scope0!=scope0)
    {
        if (warn && DEBUG) PrintToServer("[zm] DirectorScript scope changed! mob %d", pending_mob); 
        old_scope0 = scope0;
    }
    
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    if (old_scope1!=scope1)
    {
        if (warn && DEBUG) PrintToServer("[zm] MapScript scope changed! mob %d", pending_mob); 
        old_scope1 = scope1;
    }
    
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    if (old_scope2!=scope2)
    {
        if (warn && DEBUG) PrintToServer("[zm] LocalScript scope changed! mob %d", pending_mob); 
        old_scope2 = scope2;
        check_fog_distance();
        CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
    }
    
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    if (old_scope3!=scope3)
    {
        if (warn && DEBUG) PrintToServer("[zm] ChallengeScript scope changed! mob", pending_mob); 
        old_scope3 = scope3;
    }
    
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    if (old_scope4!=scope4)
    {
        if (warn && DEBUG) PrintToServer("[zm] DirectorOptions scope changed! mob %d", pending_mob); 
        old_scope4 = scope4;
        scope_changed = true;
        t_scope_change = GetEngineTime();
    }
     
}

Action zm_update(Handle timer)
{
   
   if (!g_bCvarAllow || zm_stage>=ZM_END)
   {
      if (zm_timer) delete zm_timer;
      if (IsValidClientZM()) QuitZM(zm_client,false);
      return Plugin_Stop;
   }
   
   if (DEBUG) PrintToServer("[zm] zm_update"); 
   
   if (g_bLockSaferoom && L4D_HasMapStarted() && L4D_IsInIntro()>0) freeze_team(true);
   
   float t_now = GetEngineTime();
   float dt = t_now - t_last_update;
   if (zm_stage>=ZM_STARTED)
   {
      if (dt>0.0)
      {
         bank_add += dt*get_bank_rate();
         if (bank_add>=1.0)
         {
             int add_int = RoundFloat(bank_add);
             bank += add_int;
             bank_add -= add_int;
         }
      }
   }
   else if (!zm_can_start) can_zm_start();
   
   // Double check that survivors havent left start area
   if ( zm_stage<ZM_STARTED && zm_can_start && !L4D_IsSurvivalMode() && L4D_HasAnySurvivorLeftSafeArea() )
   {
       float pos[3];
       Address temp_navArea;
       for (int i = 1; i <= MaxClients; i++)
   	   {
       		if (!IsClientInGame(i)) continue;
       		if (GetClientTeam(i)!=TEAM_SURVIVOR || i==zm_client) continue;
       		if (!IsPlayerAlive(i)) continue;
       		GetClientAbsOrigin(i, pos);
       		temp_navArea = L4D_GetNearestNavArea(pos,500.0,true,false,true,TEAM_SURVIVOR);
       		if (!navArea_validStart(temp_navArea))
       		{
           		if (IsValidClientZM())
           		{
               		start_zm_round();
               		break;
           		}
           		else tp_survivor_start(i);
       		}
       }
   }
   
   CountCommons();
   
   if (available_zombie_arr[ZOMBIECLASS_COMMON]<max_zombie_arr[ZOMBIECLASS_COMMON])
   {
       
       //if (panic || ZM_finale_announced) available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
       //else
       //{
           if (dt>0.0)
           {
              commons_add += dt*g_fCommonRate;
              if (commons_add>=1.0)
              {
                  int add_common = RoundFloat(commons_add);
                  add_available_zombie(ZOMBIECLASS_COMMON,add_common);
                  commons_add -= add_common;
              }
           }
       //}
   }
   else commons_add = 0.0;
   
   t_last_update = t_now;
   
    // Check if witches were spotted to prevent refunds.
    // asdf future:
    // CTerrorPlayer->m_hasVisibleThreats (12616) changed from 1 to 0
    float witch_pos[3];
    int entity = -1;
    int counted_witches = 0;
    char targetName[20];
    while ( ((entity = FindEntityByClassname(entity, "witch")) != -1) )
    {
    	 if (IsValidEntity(entity))
    	 {
           if (GetEntProp(entity,Prop_Data,"m_iHealth")<=0) continue;	 
    	   counted_witches += 1;
           if (g_iGlowList[entity]==INVALID_ENT_REFERENCE) CreateZMGlow(entity);
           GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
           if (strcmp(targetName,"zm_unit")==0)
           {
              GetEntPropVector(entity, Prop_Send, "m_vecOrigin", witch_pos);
              if (can_any_alive_survivor_see(witch_pos,false))
              {
                 DispatchKeyValue(entity, "targetname", "zm_unit_spotted");
                 update_hint("%T", "Witch sighted", zm_client);
                 update_zm_glow(null, entity);
              }
           
           }
           
    	 } 
   }
   live_zombie_arr[ZOMBIECLASS_WITCH] = counted_witches; 
   
   if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
   else
   {
       SetConVarInt(FindConVar("director_panic_forever"), 0);
       if (panic && bank_rate>0.0 && manual_panic) update_hint("%T", "panic_rate_reduced", zm_client);
   }
   
   //if (panic && (panic_target<0 || live_zombie_arr[ZOMBIECLASS_COMMON]>10))
   //{   
   //    int new_target = L4D_GetHighestFlowSurvivor();
   //    if (panic_target<0 || new_target!=panic_target || !IsValidClient(panic_target) || (!IsPlayerAlive(panic_target) && panic_target!=zm_client ))
   //    {
   //        Chase(new_target);
   //    }
   //}
   
   if (g_iAliveSurvivors!=bank_track_numplayers)
   {
        int player_diff = g_iAliveSurvivors - bank_track_numplayers;
        if (player_diff>0 || zm_stage<ZM_STARTED)
        {
            if (L4D_IsSurvivalMode()) bank += g_iBonusFinaleStage*player_diff;
            else bank += g_iBankInitialPlayer*player_diff;
        }
        bank_track_numplayers = g_iAliveSurvivors;
   }
   
   if (IsValidClientZM() && (GetClientTeam(zm_client)!=TEAM_SURVIVOR || zm_just_died))
   { 
      
      zm_fake_gamemode();
      
      if (survival_activated && L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
      {
          if (IsValidEntity(info_director)) AcceptEntityInput(info_director, "ForcePanicEvent");
          else L4D_ForcePanicEvent();
          survival_activated = false;
      }
      
      if (zm_menu_state>ZM_MENU_CLOSED) reopen_zm_menu(false); 
      
      zm_just_died = false;
      
      if (g_fStopInactivity>0.0)
      {
          if (zm_allow_spawns && !IsPlayerAlive(zm_client) && bank>=g_iBankInitial && live_SI<=0 && live_zombie_arr[ZOMBIECLASS_WITCH]<=0 && !panic && live_zombie_arr[ZOMBIECLASS_COMMON]<=10)
          {
             
             if ((t_now-t_zm_activity)>=(g_fStopInactivity)/2.0)
             {
             
                 if (!zm_kick_notify)
                 {
                     EmitSoundToAll(SOUND_INACTIVITY);
                     PrintHintText(zm_client, "%t", "Inactivity hint");
                     update_hint("%T", "zm_menu_hint", zm_client);
                     zm_kick_notify=true;
                 }
                 else if ((t_now-t_zm_activity)>=g_fStopInactivity)
                 {
                         PrintHintText(zm_client, "%t", "Inactivity notify kicked");
                         PrintToChatAll("[zm] %t", "Inactivity notify");
                         update_t_zm_activity(t_now);
                         QuitZM(zm_client,false);
                 }
             
             }
             
          }
          else update_t_zm_activity(t_now);
      }
        
        //if ((t_now-t_last_spawner_update)>=g_fUpdateRate)
        //{
      	    //Find all ladders and transmit visibility to ZM
          //	int ladder = -1;
          	//char modelname[128];
          	//int ladderteam = -1;
          	//float mins[3],maxs[3],center[3];
          	//float vDrawStart[3], vDrawEnd[3];
          	//float width_x = 10.0;
          	//while( (ladder = FindEntityByClassname(ladder, "func_simpleladder")) != INVALID_ENT_REFERENCE )
          	//{
          		//if (GetEntProp(ladder, Prop_Data, "TeamNum")!=TEAM_INFECTED) continue;
          		//if (GetEntProp(ladder, Prop_Send, "m_iTeamNum", 0)!=TEAM_INFECTED) continue;
          	//	GetEntPropVector(ladder, Prop_Send, "m_vecMins", mins);
              //  GetEntPropVector(ladder, Prop_Send, "m_vecMaxs", maxs);
                //GetEntPropVector(ladder, Prop_Data, "m_vecOrigin", center);
                
                //PrintToServer("[zm] Ladder %d %f %f %f %f %f %f", ladder, maxs[0], maxs[1], maxs[2], mins[0], mins[1], mins[2]);
                
                //vDrawStart = center;
                //vDrawEnd = center;
                //vDrawEnd[2] += maxs[2] - mins[2];
                
                //width_x = maxs[0] - mins[0];
                
                
              //  TE_SetupBeamPoints(mins,maxs,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,width_x,width_x,1,1.0,{255,255,255,0}, 0);
              //  TE_SendToClient(zm_client);
                
          		//ladderteam = GetEntProp(ladder, Prop_Data, "TeamNum");
          		//GetEntPropString(ladder, Prop_Data, "m_ModelName", modelname, sizeof(modelname));
          		//PrintToServer("[zm] Found infected ladder %d %s", ladder, modelname);
          		//DispatchKeyValue(ladder, "team", "0");
          		//AcceptEntityInput(ladder, "Enable");
          		//SetEdictFlags(ladder, GetEdictFlags(ladder) | FL_EDICT_ALWAYS);
          		//RemoveEntity(ladder);
          		//SetEntityModel(ladder,MODEL_LADDER);
          		//DispatchKeyValue(ladder, "model", MODEL_LADDER);
          		
              //	SetEntProp(ladder, Prop_Send, "m_nGlowRangeMin", 0);
              //	SetEntProp(ladder, Prop_Send, "m_nGlowRange", 999999);
              //	SetEntProp(ladder, Prop_Send, "m_iGlowType", 3);
              //	SetEntProp(ladder, Prop_Send, "m_glowColorOverride", RGB_ZM);
              //	AcceptEntityInput(ladder, "StartGlowing");
              //	SetEntityRenderMode(ladder, RENDER_TRANSCOLOR);
              //    SetEntityRenderColor(ladder, 0, 0, 0, 0);
          	//}
      	//}
      
      // Draw spawner visuals for ZM
      if (zm_menu_state>ZM_MENU_CLOSED && (t_now-t_last_spawner_update)>=g_fUpdateRate) can_ZM_spawn(false,false);
      
      
   }
   else
   {
      
      if (!IsValidClientZM())
      {
          zm_client = GetClientOfUserId(zm_client_userid);
          if (IsValidClientZM())
          {
              zm_update(zm_timer);
              return Plugin_Continue;
          }
      }
      
      if ((t_now-t_zm_activity)>=10.0)
      {
         if (zm_stage<ZM_END) PrintToChatAll("[zm] %t", "No ZM");
         update_t_zm_activity(t_now);
      }
      zm_client = -1;
      zm_client_userid = -1;
   }
   
   // POINTER_DIRECTOR CDirector m_iTempoState
   // POINTER_ZOMBIEMANAGER ZombieManager
   // POINTER_EVENTMANAGER CDirectorScriptedEventManager m_cCustomFinaleType m_bPanicEventInProgress
   
   //bool director_panic = false;
   //if (EventManager) director_panic = view_as<bool>(LoadFromAddress(EventManager + view_as<Address>(272), NumberType_Int8)); 
   // 
   //if ( (L4D_IsFinaleActive() || director_panic) && !panic && !L4D_IsMissionFinalMap() && !L4D_IsSurvivalMode() && !ZM_finale_announced && zm_stage==ZM_STARTED)
   //{
   //     PrintToServer("[zm] finale or director panic detected");
   //     //if (live_zombie_arr[ZOMBIECLASS_COMMON]<30) spawn_free_angry_zombies(L4D_GetHighestFlowSurvivor(),40);
   //     CreateTimer(2.0, Timer_Free_Angry_Zombies, 50, TIMER_FLAG_NO_MAPCHANGE);
   //     manual_panic=false; // panic hasn't run yet - means it wasn't started by ZM
   //     toggle_panic(true,true,true); // free panic!
   //}
   //if ( panic && !ZM_finale_announced && !(L4D_IsFinaleActive() || director_panic) )
   //{
   //    if ( (t_now-t_last_panic)>=g_fPanicDuration )
   //       toggle_panic(false,true,true);
   //} 
   
   int pending_mob = L4D2Direct_GetPendingMobCount();
   
   if (!L4D_IsSurvivalMode() && !ZM_finale_announced)
   {
   
       CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
       float mob_timer_left, mob_timer_elapsed;
       if (MobSpawnTimer)
       {
           mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
           mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
       }
       
       if (zm_stage==ZM_STARTED) update_director_script_scopes();
       
       if (scope_changed && script_CommonLimit>0 && pending_mob>0 )
       {
            if (mob_timer_elapsed<=10.0 && mob_timer_left<=1.0)
            {
               if (panic && manual_panic) bank += g_iPanicCost;
               manual_panic = false;
               update_panic();
               scope_changed = false;    
            }   
       }
       
       if (panic)
       {
           if (pending_mob>0 && !manual_panic)
           {
               if (MobSpawnTimer)
               {
                   if (mob_timer_left<=1.0 && mob_timer_elapsed<=g_fPanicDuration)
                   {
                       if (DEBUG) PrintToServer("[zm] Panic holding, pending mob %d, timer %f %f", pending_mob, mob_timer_left, mob_timer_elapsed);
                       t_last_panic = t_now;
                       CreateTimer(1.0, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
                       L4D2Direct_SetPendingMobCount(0);
                   }
                   
               }
           }
           
           if ( (t_now-t_last_panic)>=g_fPanicDuration )
           {
               toggle_panic(false,true,true);
           }
          
       }
       else
       {
           
           // Prevent "Incoming Attack" jingle from playing
           if (!scope_changed && MobSpawnTimer && mob_timer_left>0.0 && mob_timer_elapsed>g_fPanicDuration)
           {
              //CTimer_Reset(MobSpawnTimer);
              CTimer_Invalidate(MobSpawnTimer);
              CTimer_Start(MobSpawnTimer,3600.0); 
           } 
       }
       
       if ( scope_changed && (t_now-t_scope_change)>=10.0 ) scope_changed = false;
   
   }
   //else if (pending_mob>0)
   //{
   //    //CreateTimer(5.0, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
   //    L4D2Direct_SetPendingMobCount(0);
   //}
   
   update_EMS_HUD();
   
   if (!zm_timer)
   {
      zm_timer = CreateTimer(g_fUpdateRate,zm_update,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
      return Plugin_Stop;
   }
   
   return Plugin_Continue;
   
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{

	if(GetEngineVersion()!=Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	RegPluginLibrary("l4d2_zombie_master");

	return APLRes_Success;
}


public void OnAllPluginsLoaded()
{
	// l4d_infectedbots by HarryPotter https://github.com/fbef0102/L4D1_2-Plugins
	//infectedbots_dispose_cowards = FindConVar("l4d_infectedbots_dispose_cowards");
	//if (infectedbots_dispose_cowards) SetConVarFlags(infectedbots_dispose_cowards, GetConVarFlags(infectedbots_dispose_cowards) & ~FCVAR_NOTIFY);
	infectedbots_enable = FindConVar("l4d_infectedbots_allow");
	if (infectedbots_enable) SetConVarFlags(infectedbots_enable, GetConVarFlags(infectedbots_enable) & ~FCVAR_NOTIFY);
	SetCvarsZM();
}

// ty zyiks
void DumpPlayerState(int client, int target = -1)
{
      if (target == -1) target = client;
      if (!IsValidClient(target) || !IsClientInGame(target))
      {
          PrintToChat(client, "[DEBUG] Invalid target");
          return;
      }

      PrintToChat(client, "=== Player State Dump: %N ===", target);

      // Basic info
      PrintToChat(client, "Team: %d | Alive: %d | Bot: %d",
          GetClientTeam(target),
          IsPlayerAlive(target),
          IsFakeClient(target));

      // Zombie class
      int zClass = GetEntProp(target, Prop_Send, "m_zombieClass");
      char zClassName[32];
      get_zombieclass_name(zClass,zClassName);
      PrintToChat(client, "ZombieClass: %s (%d)", zClassName, zClass);

      // Movement
      PrintToChat(client, "MoveType: %d | MoveCollide: %d",
          GetEntityMoveType(target),
          GetEntProp(target, Prop_Data, "m_MoveCollide"));

      // Collision
      PrintToChat(client, "CollisionGroup: %d | SolidType: %d | SolidFlags: %d",
          GetEntProp(target, Prop_Send, "m_CollisionGroup"),
          GetEntProp(target, Prop_Send, "m_nSolidType"),
          GetEntProp(target, Prop_Send, "m_usSolidFlags"));

      // Hull size
      float vecMins[3], vecMaxs[3];
      GetEntPropVector(target, Prop_Send, "m_vecMins", vecMins);
      GetEntPropVector(target, Prop_Send, "m_vecMaxs", vecMaxs);
      PrintToChat(client, "Hull Mins: %.0f,%.0f,%.0f | Maxs: %.0f,%.0f,%.0f",
          vecMins[0], vecMins[1], vecMins[2],
          vecMaxs[0], vecMaxs[1], vecMaxs[2]);

      // Observer mode
      PrintToChat(client, "ObserverMode: %d | ObserverTarget: %d",
          GetEntProp(target, Prop_Data, "m_iObserverMode"),
          GetEntPropEnt(target, Prop_Data, "m_hObserverTarget"));

      // Ghost state
      PrintToChat(client, "IsGhost: %d | GhostSpawnState: %d",
          GetEntProp(target, Prop_Send, "m_isGhost"),
          GetEntProp(target, Prop_Send, "m_ghostSpawnState"));

      // Ability
      int ability = GetEntPropEnt(target, Prop_Send, "m_customAbility");
      if (ability != -1 && IsValidEntity(ability))
      {
          char abilityClass[64];
          GetEntityClassname(ability, abilityClass, sizeof(abilityClass));
          PrintToChat(client, "CustomAbility: %d (%s)", ability, abilityClass);
      }
      else
      {
          PrintToChat(client, "CustomAbility: None (-1)");
      }

      // SI-specific victim/attacker relationships
      int jockeyAttacker = GetEntPropEnt(target, Prop_Send, "m_jockeyAttacker");
      int pummelAttacker = GetEntPropEnt(target, Prop_Send, "m_pummelAttacker");
      int carryAttacker = GetEntPropEnt(target, Prop_Send, "m_carryAttacker");
      int tongueOwner = GetEntPropEnt(target, Prop_Send, "m_tongueOwner");
      int pounceAttacker = GetEntPropEnt(target, Prop_Send, "m_pounceAttacker");

      PrintToChat(client, "Attackers - Jockey:%d Pummel:%d Carry:%d Tongue:%d Pounce:%d",
          jockeyAttacker, pummelAttacker, carryAttacker, tongueOwner, pounceAttacker);

      // If they're a Jockey, check victim
      if (zClass == 5) // Jockey
      {
          int jockeyVictim = GetEntPropEnt(target, Prop_Send, "m_jockeyVictim");
          PrintToChat(client, "JockeyVictim: %d", jockeyVictim);
      }

      // If they're a Charger, check victims
      if (zClass == 6) // Charger
      {
          int pummelVictim = GetEntPropEnt(target, Prop_Send, "m_pummelVictim");
          int carryVictim = GetEntPropEnt(target, Prop_Send, "m_carryVictim");
          PrintToChat(client, "Charger - PummelVictim:%d CarryVictim:%d", pummelVictim, carryVictim);
      }

      // Flags
      int flags = GetEntProp(target, Prop_Data, "m_fFlags");
      PrintToChat(client, "Flags: %d (OnGround:%d Ducking:%d)",
          flags,
          (flags & FL_ONGROUND) ? 1 : 0,
          (flags & FL_DUCKING) ? 1 : 0);

      // Stagger
      PrintToChat(client, "IsStaggering: %d", L4D_IsPlayerStaggering(target));

      // Parent entity (sometimes causes movement issues)
      int parent = GetEntPropEnt(target, Prop_Data, "m_pParent");
      PrintToChat(client, "Parent: %d", parent);

      // Ground entity
    int groundEnt = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
    PrintToChat(client, "GroundEntity: %d", groundEnt);

    // View offset
    if (HasEntProp(client,Prop_Send,"m_vecViewOffset"))
    {
        float viewOffset[3];
        GetEntPropVector(client, Prop_Send, "m_vecViewOffset", viewOffset);
        PrintToChat(client, "ViewOffset: %.1f,%.1f,%.1f", viewOffset[0], viewOffset[1], viewOffset[2]);
    }

    // Base velocity (forced movement)
    float baseVel[3];
    GetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", baseVel);
    PrintToChat(client, "BaseVelocity: %.1f,%.1f,%.1f", baseVel[0], baseVel[1], baseVel[2]);

    // Lag compensation / simulation
    float simTime = GetEntPropFloat(client, Prop_Data, "m_flSimulationTime");
    float lagMove = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
    PrintToChat(client, "SimTime: %.2f | LaggedMovement: %.2f", simTime, lagMove);

    // Water level
    int waterLevel = GetEntProp(client, Prop_Send, "m_nWaterLevel");
    PrintToChat(client, "WaterLevel: %d", waterLevel);

    // Friction
    float friction = GetEntPropFloat(client, Prop_Data, "m_flFriction");
    PrintToChat(client, "Friction: %.2f", friction);

    // Gravity
    float gravity = GetEntPropFloat(client, Prop_Data, "m_flGravity");
    PrintToChat(client, "Gravity: %.2f", gravity);

    // Check for children/attached entities
    int child = -1;
    while ((child = FindEntityByClassname(child, "*")) != -1)
    {
        if (IsValidEntity(child) && child > MaxClients)
        {
            int parent2 = GetEntPropEnt(child, Prop_Data, "m_pParent");
            if (parent2 == client)
            {
                char classname[64];
                GetEntityClassname(child, classname, sizeof(classname));
                PrintToChat(client, "ATTACHED CHILD: %d (%s)", child, classname);
            }
        }
    }

      PrintToChat(client, "=== End Dump ===");
}


Action zm_debug_player(int client, int args)
{   
    DumpPlayerState(client,client);
    return Plugin_Continue;
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
    
    // CommonLimit
    // MobMinSize 
    // MobMaxSize 
    // MobMaxPending 
    // BuildUpMinInterval
    // MobRechargeRate
    // MobSpawnMinTime
    // MobSpawnMaxTime
    // SustainPeakMinTime
    // SustainPeakMaxTime
    // MegaMobSize
    // 
    
    CountCommons(false);
    int commons = live_zombie_arr[ZOMBIECLASS_COMMON];
    int panic_forever = FindConVar("director_panic_forever").IntValue;
    
    //L4D_OnGetScriptValueInt(const char[] key, int &retVal)

    PrintToChat(client, "commons %d panic forever %d pending_mob %d finale_active %d", commons, panic_forever, pending_mob, finale_active);
    PrintToChat(client, "MobTimer Remaining Elapsed %.2f %.2f", mob_timer_left, mob_timer_elapsed);
    PrintToChat(client, "DirectorScriptScope %d %d %d %d %d", scope0, scope1, scope2, scope3, scope4);
    //PrintToChat(client, "CommonLimit %d MobMinSize %d MobMaxSize %d MobMaxPending %d", script_CommonLimit, script_MobMinSize, script_MobMaxSize, script_MobMaxPending);
    
    return Plugin_Continue;
}

Action zm_debug_fog(int client, int args)
{   
    check_fog_distance();
    set_zm_client_fog(true,false);
    return Plugin_Continue;
}


public int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_VoteEnd)
    {
        /* 0=yes, 1=no */
        if (param1 == 0)
        {
            if (g_bCvarAllow) SetConVarInt(g_hCvarAllow,0);
            else SetConVarInt(g_hCvarAllow,1);
        }
    }
    return 0;
}
 
void DoVoteMenu()
{
    if (IsVoteInProgress()) return;
    EmitSoundToAll(SOUND_READY);
    Menu menu = new Menu(Handle_VoteMenu);
    if (g_bCvarAllow) menu.SetTitle("Zombie Master -> OFF?");
    else menu.SetTitle("Zombie Master -> ON?");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}
 
public Action VoteZM(int client, int args)
{
        
    if (L4D_HasPlayerControlledZombies())
    {
        PrintToChat(client, "[zm] %t", "ZM restrict notify");
        return Plugin_Stop;
    }
    
    if (IsVoteInProgress()) return Plugin_Stop;
    
    DoVoteMenu();
    return Plugin_Continue;
	
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sGameMode[32];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	if(strcmp(g_sCvarMPGameMode, sGameMode, false) == 0) return;
	g_sCvarMPGameMode = sGameMode;
    
    if (DEBUG) PrintToServer("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
    l4d2_specials = true;
    if (strcmp(g_sCvarMPGameMode,"l4d1coop")==0 || strcmp(g_sCvarMPGameMode,"l4d1survival")==0)
        l4d2_specials = false;
    
	IsAllowed();
}

void ConVarChanged_Cvars_ZMenu(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (DEBUG) PrintToServer("[zm] ConVarChanged_Cvars_ZMenu");
    GetCvars();
    SetCvarsZM();
    update_menus();
    if (IsValidClientZM() && zm_menu_state>ZM_MENU_MAIN)
    {
	   open_menu(zm_client,zm_menu_state);
	   if (DEBUG) PrintToServer("[zm] zmenu cvars changed, redisplaying."); 
	}
	if (g_bCvarAllow && IsValidClientZM()) zm_update(zm_timer);
}

void ConVarChanged_Allow(ConVar convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void GetCvars()
{
    
    if (DEBUG) PrintToServer("[zm] GetCvars");
    g_fUpdateRate = g_hUpdateRate.FloatValue;
    ResetTimer();
    
    DEBUG = g_hCvarDebug.BoolValue;
    
    g_fBankRateBase = g_hBankRateBase.FloatValue;
    g_fBankRatePlayer = g_hBankRatePlayer.FloatValue;
    g_iBankInitial = g_hBankInitial.IntValue;
    g_iBankInitialPlayer = g_hBankInitialPlayer.IntValue;
    max_zombie_arr[ZOMBIECLASS_COMMON] = g_hMaxCommons.IntValue;
    g_fSpawnMinDistance = g_hSpawnMinDistance.FloatValue;
    g_fStopInactivity = g_hStopInactivity.FloatValue;
    
    costs_SI[ZOMBIECLASS_BOOMER] = g_hCostBoomer.IntValue;
    costs_SI[ZOMBIECLASS_SPITTER] = g_hCostSpitter.IntValue;
    costs_SI[ZOMBIECLASS_HUNTER] = g_hCostHunter.IntValue;
    costs_SI[ZOMBIECLASS_SMOKER] = g_hCostSmoker.IntValue;
    costs_SI[ZOMBIECLASS_JOCKEY] = g_hCostJockey.IntValue;
    costs_SI[ZOMBIECLASS_CHARGER] = g_hCostCharger.IntValue;
    costs_SI[ZOMBIECLASS_TANK] = g_hCostTank.IntValue;
    g_iCostWitchStatic = g_hCostWitchStatic.IntValue;
    g_iCostWitchMoving = g_hCostWitchMoving.IntValue;
    g_iCostCommon = g_hCostCommon.IntValue;
    g_iCostUncommon = g_hCostUncommon.IntValue;
    g_iMaxWitches = g_hMaxWitches.IntValue;
    g_iMaxSI = g_hMaxSI.IntValue;
    g_iMaxUniqueSI = g_hMaxUniqueSI.IntValue;
    
    g_iBonusCarAlarm = g_hBonusCarAlarm.IntValue;
    g_iBonusFinaleStage = g_hBonusFinaleStage.IntValue;
    
    g_iPanicCost = g_hPanicCost.IntValue;
    g_fPanicDuration = g_hPanicDuration.FloatValue;
    
    g_bLockSaferoom = g_hLockSaferoom.BoolValue;
    
    g_fPrepTimeZM = g_hPrepTimeZM.FloatValue;
    
    g_fSpecialCooldown = g_hSpecialCooldown.FloatValue;
    g_fTankCooldown = g_hTankCooldown.FloatValue;
    g_fWitchCooldown = g_hWitchCooldown.FloatValue;
    g_fCommonRate = g_hCommonRate.FloatValue;
    
    g_fMinFinaleStage = g_hMinFinaleStage.FloatValue;
    
    zm_update(zm_timer);
    
}

//void remove_attached_lights(int client)
//{
//    if (!IsValidClient(client)) return;
//    int child = -1;
//    while ((child = FindEntityByClassname(child, "light_dynamic")) != -1)
//    {
//        if (IsValidEntity(child) && HasEntProp(child,Prop_Data,"m_pParent"))
//        {
//            if (GetEntPropEnt(child,Prop_Data,"m_pParent") == client)
//            {
//                AcceptEntityInput(child, "TurnOff");
//                AcceptEntityInput(child, "Kill");
//            }
//        }
//    }
//}

void zm_fake_gamemode()
{
    if (L4D_IsSurvivalMode()) FindConVar("mp_gamemode").ReplicateToClient(zm_client,"mutation15");
    else FindConVar("mp_gamemode").ReplicateToClient(zm_client,"versus");
}

Action JoinZM_command(int client, int args) //
{
    if (!g_bCvarAllow || !IsValidClient(client)) return Plugin_Continue;
    if (IsValidClientZM() && client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
    JoinZM(client,args);
    return Plugin_Continue;
}

Action JoinZM(int client, int args)
{
	if (!g_bCvarAllow || !IsValidClient(client) || args>1) return Plugin_Continue;
	if (DEBUG) PrintToServer("[zm] JoinZM");
	if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
	if (client<0 || IsFakeClient(client)) return Plugin_Continue;
	if (zm_stage>=ZM_END) return Plugin_Continue;
	if (IsValidClientZM())
	{
       if (client==zm_client)
       {
          set_zm_client_fog(true);
          if (GetClientTeam(zm_client)!=TEAM_ZM)
          {
              zm_just_died = true;
              ChangeClientTeam(zm_client,TEAM_ZM);
              L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
          }
          if (!IsPlayerAlive(zm_client))
          {
              SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6); //thanks to EHG https://forums.alliedmods.net/showthread.php?p=1080991
              SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
              L4D2_RemoveEntityGlow(zm_client);
              L4D2_SetPlayerSurvivorGlowState(zm_client,false);
          }
          if (zm_timer==INVALID_HANDLE) zm_update(zm_timer);
          if (zm_menu_state==ZM_MENU_CLOSED) open_menu(zm_client);
       }
       else PrintHintText(client,"%t", "ZM taken");
       return Plugin_Continue;
    }
    
    if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client))
    {
        L4D_TakeOverBot(client);
    }
    
    remove_all_ZM_glows();
    
    zm_just_died = true;
    ChangeClientTeam(client,TEAM_ZM);
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    
    zm_client = client;
    zm_client_userid = GetClientUserId(zm_client);
    
    // try setting m_iVersusTeam m_scrimmageType   netprops
    
    update_menus();
    
    char name[MAX_NAME_LENGTH]; 
    GetClientName(client,name,sizeof(name));
    PrintToChatAll("[zm] %t", "ZM joined", name);
    DispatchKeyValue(zm_client, "targetname", "zm_client");
    SetEntProp(client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    set_zm_client_fog(true,true);
    PrintHintText(client, "%t", "ZM join hint");
    //AcceptEntityInput(zm_client, "StopGlowing");
    L4D2_RemoveEntityGlow(zm_client);
    //L4D2_RemoveEntityGlow_Color(i);
    L4D2_SetPlayerSurvivorGlowState(zm_client,false);
    zm_fake_gamemode();
    update_hint("%T", "zm_menu_hint", zm_client);
    if (panic_target==zm_client) panic_target = -1;
    update_t_zm_activity();
    t_zm_join = t_zm_activity;
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
    zm_update(zm_timer);
    open_menu(zm_client);
    
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    EmitSoundToClient(zm_client,SOUND_VISION);
    
    if (zm_stage<ZM_PREP) set_bank_begin();
    
    set_zm_stage(ZM_PREP);
    
    ZMTeleport(zm_client,0);
    
    L4D_CleanupPlayerState(client);
    
    SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
    
    //remove_attached_lights(zm_client);
    
    // Make end saferoom door glow
    if (!L4D_IsSurvivalMode())
    {
        lastdoor = L4D_GetCheckpointLast();
        if (IsValidEntity(lastdoor)) CreateTimer(g_fUpdateRate, CreateZMGlow_red, EntIndexToEntRef(lastdoor), TIMER_FLAG_NO_MAPCHANGE);
        else lastdoor = -1;
    }

	return Plugin_Continue;
}

void QuitZM(int client, bool print = true)
{
	if (DEBUG) PrintToServer("[zm] QuitZM");
	if (!IsValidClientZM())
	{
    	zm_client = -1;
        zm_client_userid = -1;
        zm_menu_state = ZM_MENU_CLOSED;
        return;
	}
	if (!g_bCvarAllow || client<=0 || IsFakeClient(client) || !IsClientInGame(client)) return;
	if (client==zm_client)
	{
	   if (IsValidClientZM())
	   {
	       FindConVar("mp_gamemode").ReplicateToClient(zm_client,g_sCvarMPGameMode);
           if (print)
           {
               char name[MAX_NAME_LENGTH]; 
               GetClientName(client,name,sizeof(name));
               PrintToChatAll("[zm] %t", "ZM quit", name);
               update_t_zm_activity();
           }
           
           L4D_CleanupPlayerState(client);
           zm_use_notify = false;
           
           if (panic_target==zm_client) panic_target = -1;
           
           if (zm_stage<ZM_STARTED)
           {
               zm_can_start = false;
               set_zm_stage(ZM_PREP,true);
               //can_zm_start();
           }
           
           if (zm_menu_state>ZM_MENU_CLOSED) open_menu(client,ZM_MENU_CLOSED);
           
           DispatchKeyValue(zm_client, "targetname", "client");
           set_zm_client_fog(false);
       }
       remove_all_ZM_glows();
       zm_client = -1;
       zm_client_userid = -1;
       zm_menu_state = ZM_MENU_CLOSED;
       //cleanup_bad_glows(); 
    }
    if (IsValidClient(client))
    {
        if (GetClientTeam(client)!=TEAM_SURVIVOR)
        {
            
            // Find bot that can be taken over
            // Credit: l4dmultislots by HarryPotter
            int bot = -1;
            for (int i = 1; i <= MaxClients; i++)
        	{
        		if (!IsClientInGame(i)) continue;
        		if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
        		if (!IsPlayerAlive(i)) continue;
        		if (!IsFakeClient(i)) continue;
        		if (HasEntProp(i,Prop_Send,"m_humanSpectatorUserID"))
        		{
            		if (GetEntProp(i, Prop_Send, "m_humanSpectatorUserID")>0) continue;
        		}
        		if (L4D_IsPlayerIncapacitated(i)) continue;
        		bot = i;
        		break;
            }
            
            ChangeClientTeam(client,TEAM_SURVIVOR);

   			if(bot > 0)
   			{
   				L4D_SetHumanSpec(bot,client);
   				L4D_TakeOverBot(client);
   			}
        }
        SetEntProp(client, Prop_Send, "m_bNightVisionOn",0);
        L4D_CleanupPlayerState(client);
    }
    
}

Action QuitZM_Command(int client, int args)
{
  if (!g_bCvarAllow) return Plugin_Continue;
  QuitZM(client,true);
  return Plugin_Continue;
}

// Rain and Snow all thanks to l4d2_storm by SilverShot
// https://forums.alliedmods.net/showthread.php?t=184890

int rain_entity = -1;

Action ZM_Rain_Toggle(int client)
{
   toggle_rain(client);
   return Plugin_Continue;
}

Action ZM_Vision(int client, int args)
{
   toggle_ZM_vision(client);
   return Plugin_Continue;
}

void toggle_ZM_vision(int client)
{
    if (!g_bCvarAllow || !IsValidClient(client)) return;
    
    if (client!=zm_client)
    {
        SetEntProp(client, Prop_Send, "m_bNightVisionOn",0);
        return;
    }
    
    int curr_state = GetEntProp(client, Prop_Send, "m_bNightVisionOn");
    if (curr_state>0) SetEntProp(client, Prop_Send, "m_bNightVisionOn",0);
    else SetEntProp(client, Prop_Send, "m_bNightVisionOn",1);
    EmitSoundToClient(client,SOUND_VISION);
}

void toggle_rain(int client)
{
	if (DEBUG) PrintToServer("[zm] toggle_rain");
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
	
	if (rain_entity>0)
	{
	   if (EntRefToEntIndex(rain_entity)!=INVALID_ENT_REFERENCE) RemoveEntity(rain_entity);
	   rain_entity = -1;
	   PrintToServer("[zm] Rain turned OFF"); 
	   return;
	}
	
	int value, entity = -1;
	while( (entity = FindEntityByClassname(entity, "func_precipitation")) != INVALID_ENT_REFERENCE )
	{
		value = GetEntProp(entity, Prop_Data, "m_nPrecipType");
		if( value < 0 || value == 4 || value > 5 )
			RemoveEntity(entity);
	}
	
		entity = CreateEntityByName("func_precipitation");
		if( entity != -1 )
		{
			char buffer[128];
			GetCurrentMap(buffer, sizeof(buffer));
			Format(buffer, sizeof(buffer), "maps/%s.bsp", buffer);

			DispatchKeyValue(entity, "model", buffer);
			DispatchKeyValue(entity, "targetname", "silver_rain");
			IntToString(1, buffer, sizeof(buffer));
			DispatchKeyValue(entity, "preciptype", buffer);
			DispatchKeyValue(entity, "minSpeed", "25");
			DispatchKeyValue(entity, "maxSpeed", "35");
			DispatchKeyValue(entity, "renderfx", "21");
			DispatchKeyValue(entity, "rendercolor", "31 34 52");
			DispatchKeyValue(entity, "renderamt", "100");

			float vMins[3], vMaxs[3];
			GetEntPropVector(0, Prop_Data, "m_WorldMins", vMins);
			GetEntPropVector(0, Prop_Data, "m_WorldMaxs", vMaxs);
			SetEntPropVector(entity, Prop_Send, "m_vecMins", vMins);
			SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vMaxs);

			float vBuff[3];
			vBuff[0] = vMins[0] + vMaxs[0];
			vBuff[1] = vMins[1] + vMaxs[1];
			vBuff[2] = vMins[2] + vMaxs[2];

			DispatchSpawn(entity);
			ActivateEntity(entity);
			TeleportEntity(entity, vBuff, NULL_VECTOR, NULL_VECTOR);
			
			//rain_entity = EntIndexToEntRef(entity);
			rain_entity = entity;
			PrintToServer("[zm] Rain turned ON"); 
			
		}
		else if (IsValidClientZM())
			PrintHintText(zm_client, "%t", "Weather failed");
	
	return;
}

int snow_entity = -1;

Action ZM_Snow_Toggle(int client)
{
   toggle_snow(client);
   return Plugin_Continue;
}

void toggle_snow(int client)
{
	if (DEBUG) PrintToServer("[zm] toggle_snow");
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
	
	if (snow_entity>0)
	{
	   if (EntRefToEntIndex(snow_entity)!=INVALID_ENT_REFERENCE) RemoveEntity(snow_entity);
	   snow_entity = -1;
	   PrintToServer("[zm] Snow turned OFF"); 
	   return;
	}
	
	int value, entity = -1;
	while( (entity = FindEntityByClassname(entity, "func_precipitation")) != INVALID_ENT_REFERENCE )
	{
		value = GetEntProp(entity, Prop_Data, "m_nPrecipType");
		if( value < 0 || value == 4 || value > 5 )
			RemoveEntity(entity);
	}

	entity = CreateEntityByName("func_precipitation");
	if( entity != -1 )
	{
		char buffer[128];
		GetCurrentMap(buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "maps/%s.bsp", buffer);

		DispatchKeyValue(entity, "model", buffer);
		DispatchKeyValue(entity, "targetname", "silver_snow");
		DispatchKeyValue(entity, "preciptype", "3");
		DispatchKeyValue(entity, "renderamt", "100");
		DispatchKeyValue(entity, "rendercolor", "200 200 200");

		//snow_entity = EntIndexToEntRef(entity);
		snow_entity = entity;

		float vBuff[3], vMins[3], vMaxs[3];
		GetEntPropVector(0, Prop_Data, "m_WorldMins", vMins);
		GetEntPropVector(0, Prop_Data, "m_WorldMaxs", vMaxs);
		SetEntPropVector(snow_entity, Prop_Send, "m_vecMins", vMins);
		SetEntPropVector(snow_entity, Prop_Send, "m_vecMaxs", vMaxs);

		bool found = false;
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( !found && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) )
			{
				found = true;
				GetClientAbsOrigin(i, vBuff);
				break;
			}
		}

		if( !found )
		{
			vBuff[0] = vMins[0] + vMaxs[0];
			vBuff[1] = vMins[1] + vMaxs[1];
			vBuff[2] = vMins[2] + vMaxs[2];
		}

		DispatchSpawn(snow_entity);
		ActivateEntity(snow_entity);
		TeleportEntity(snow_entity, vBuff, NULL_VECTOR, NULL_VECTOR);
		
		PrintToServer("[zm] Snow turned ON"); 
		
	}
	else if (IsValidClientZM()) PrintHintText(zm_client, "%t", "Weather failed");
	
	return;
}

Action zm_finale_advance(int client, int args)
{
  if (DEBUG) PrintToServer("[zm] zm_finale_advance");
  if (L4D_IsFinaleActive()) L4D2_ForceNextStage();
  else PrintToChat(client, "[zm] Finale is not active"); 
  return Plugin_Continue;
}

Action zm_addbank(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) PrintToServer("[zm] zm_addbank");
    if (args>0)
    {
        int add = GetCmdArgInt(1);
        if (add>90000) add = 90000;
        bank += add;
        zm_update(zm_timer);
    }
    return Plugin_Continue;
}

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
    //EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_ROCKET,_,SNDVOL_NORMAL,GetRandomInt(70,130),_,_,_,_,_);
    EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL,GetRandomInt(70,130));
    CreateShake(3.0,10000.0,vPos);
    return Plugin_Stop;
}

// Full credit to Silvers
void CreateShake(float intensity, float range, float vPos[3])
{
	if( !g_bMapStarted ) return;

	int entity = CreateEntityByName("env_shake");
	if( entity == -1 )
	{
		LogError("Failed to create 'env_shake'");
		return;
	}

	static char sTemp[8];
	FloatToString(intensity, sTemp, sizeof(sTemp));
	DispatchKeyValue(entity, "amplitude", sTemp);
	DispatchKeyValue(entity, "frequency", "1.5");
	DispatchKeyValue(entity, "duration", "0.9");
	FloatToString(range, sTemp, sizeof(sTemp));
	DispatchKeyValue(entity, "radius", sTemp);
	DispatchKeyValue(entity, "spawnflags", "8");
	DispatchSpawn(entity);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Enable");

	TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(entity, "StartShake");
	RemoveEdict(entity);
}

Action Open_Saferoom(Handle timer, bool scary = false)
{
    if (!IsValidEntRef(g_iLockedDoor) || zm_stage>=ZM_STARTED) return Plugin_Stop;
    start_zm_round(false); // doesnt play sound
    if (scary)
    {
        //EmitSoundToAll(SOUND_PANIC_ON,g_iLockedDoor,_,SNDLEVEL_ROCKET,_,SNDVOL_NORMAL,GetRandomInt(90,110),_,_,_,_,_);
        EmitSoundToAll(SOUND_PANIC_ON,_,_,_,_,SNDVOL_NORMAL);
    }
    //if (GetEntProp(g_iLockedDoor,Prop_Send,"m_eDoorState")!=DOOR_STATE_CLOSED) return Plugin_Stop;
    //AcceptEntityInput(g_iLockedDoor, "Break");
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
    L4D_GetEntityWorldSpaceCenter(EntRefToEntIndex(g_iLockedDoor),vPos);
    
    force_started = true;
    saferoom_lock(true);
    //if (IsValidEntRef(g_iLockedDoor) && !saferoom_interacted) AcceptEntityInput(g_iLockedDoor, "Use");
    float delay_accumulate = 3.0;
    float max_duration = 2.0;
    float min_duration = 0.2;
    int num_slams = GetRandomInt(60,130);
    for( int i = 1; i <= num_slams; i++ )
    {
        float random_duration = GetRandomFloat(min_duration,max_duration);
        CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        if (i==num_slams) CreateTimer(delay_accumulate,saferoom_disturb,vPos,TIMER_FLAG_NO_MAPCHANGE);
        delay_accumulate += random_duration;
        max_duration -= (max_duration/10.0);
        min_duration -= 0.02;
        if (max_duration<0.04) max_duration = 0.04;
        if (min_duration<0.001) min_duration = 0.001;
    }
    CreateTimer(delay_accumulate+1.0,Open_Saferoom,true,TIMER_FLAG_NO_MAPCHANGE);
}

Action zm_start(int client, int args)
{
    if (DEBUG) PrintToServer("[zm] zm_start");
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
                //EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_ROCKET,_,SNDVOL_NORMAL,GetRandomInt(90,110),_,_,_,_,_);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                EmitSoundToAll(sound,g_iLockedDoor,_,SNDLEVEL_GUNFIRE,_,SNDVOL_NORMAL);
                Force_Saferoom_Scary();
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
            //if (IsValidEntRef(g_iLockedDoor) && !saferoom_interacted)
            //{
            //SetVariantString("unlock");
        	//AcceptEntityInput(g_iLockedDoor, "SetAnimation");
            //AcceptEntityInput(g_iLockedDoor, "");
            //}
        }
        
    }
    return Plugin_Continue;
}

Action ZM_Menu(int client, int args)
{
    if (!g_bCvarAllow || client!=zm_client || !IsValidClientZM()) return Plugin_Continue;
    char type[32] = "main";
    if (args>0) GetCmdArg(1, type, sizeof(type));
	TrimString(type);
	
	int MENU = ZM_MENU_MAIN;
	if (strcmp(type,"main")==0) MENU = ZM_MENU_MAIN;
	else if (strcmp(type,"common")==0) MENU = ZM_MENU_COMMON;
	else if (strcmp(type,"uncommon")==0) MENU = ZM_MENU_UNCOMMON;
	else if (strcmp(type,"special")==0) MENU = ZM_MENU_SPECIAL;
	else if (strcmp(type,"boss")==0) MENU = ZM_MENU_BOSS;
	else if (strcmp(type,"cleanup")==0) MENU = ZM_MENU_CLEANUP;
	else if (strcmp(type,"other")==0) MENU = ZM_MENU_OTHER;
	else if (strcmp(type,"close")==0) MENU = ZM_MENU_CLOSED;
	else MENU = ZM_MENU_MAIN;
    open_menu(zm_client,MENU);
    return Plugin_Continue;
}

bool valid_uncommon(char arg[32])
{
    if (strcmp(arg,"riot")==0) return true;
	else if (strcmp(arg,"ceda")==0) return true;
	else if (strcmp(arg,"clown")==0) return true;
	else if (strcmp(arg,"mud")==0) return true;
	else if (strcmp(arg,"road")==0) return true;
	else if (strcmp(arg,"jimmy")==0) return true;
	else if (strcmp(arg,"fallen")==0) return true;
	return false;
}

void process_horde_arg(int &count, char type[32], bool &angry, bool &flow, char arg[32])
{
    if (!angry)
    {
        if (strcmp(arg,"angry")==0)
        {
            angry = true;
            return;
        }
    }
    
    if (!flow)
    {
        if (strcmp(arg,"flow")==0)
        {
            flow = true;
            return;
        }
    }
    
    if (!valid_uncommon(type))
    {
        if (valid_uncommon(arg))
        {
            type = arg;
            return;
        }
    }
    
    int arg_int = StringToInt(arg);
    if (arg_int!=0)
    {
        count = arg_int;
        if (count<=0) count = 10;
    }
}

Action ZM_Spawn_Horde(int client, int args)
{
    if (!g_bCvarAllow || client!=zm_client) return Plugin_Continue;
    int count = 10;
    bool angry = false;
    bool flow = false;
    char type[32] = "";
    if (args>0)
    {
        char arg[32] = "";
        GetCmdArg(1,arg,sizeof(arg));
        process_horde_arg(count,type,angry,flow,arg);
    	if (args>1) {GetCmdArg(2,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    	if (args>2) {GetCmdArg(3,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    	if (args>3) {GetCmdArg(4,arg,sizeof(arg)); process_horde_arg(count,type,angry,flow,arg);}
    }
    ZM_Horde(client,count,type,angry,flow);
    return Plugin_Continue;
}

// Tank discount:
// native float L4D2Direct_GetMapMaxFlowDistance();

// TerrorNavArea bool IsBlocked(int team, bool affectsFlow)
// bool IsSpawningAllowed()
// TerrorNavArea float GetDistanceSquaredToPoint(Vector pos)

//  CTerrorPlayer GetClosestSurvivor(Vector origin, bool bIncludeIncap, bool bIncludeOnRescueVehicle)
// Returns the closest Survivor from the passed origin, if incapped Survivors are included in search, or on rescue vehicle.

// L4D2_CommandABot(int entity, int target, BOT_CMD type, float vecPos[3] = NULL_VECTOR)

int get_spawner_target_survivor(bool flow = false, int spawner_state = SPAWNER_DISTANCE)
{
    int target_client = -1;
    if (flow) target_client = L4D_GetHighestFlowSurvivor();
    else
    {
        if (spawner_state == SPAWNER_DISTANCE)
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
           	
           	if (target_client<0)
           	{
               	update_ZM_looktarget();
               	int lastlook = EntRefToEntIndex(entref_lastlook);
               	if (IsValidClient(lastlook) && GetClientTeam(lastlook)==TEAM_SURVIVOR && IsPlayerAlive(lastlook))
                   	target_client = lastlook;	
            }
           	
       	}
       	
   	}
	
	if (!IsValidClient(target_client) || !IsPlayerAlive(target_client) || GetClientTeam(target_client)!=TEAM_SURVIVOR)
    	return -1;
	return target_client;
}

void ZM_Horde(int client, int count=10, char type[64]="", bool angry = false, bool flow = false)
{
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
	
	if (DEBUG) PrintToServer("[zm] ZM_Horde");
	
	if (is_zm_spamming()) return;
	
	CountCommons(false);
	if (live_zombie_arr[ZOMBIECLASS_COMMON]>=max_zombie_arr[ZOMBIECLASS_COMMON])
	{
        	update_hint("%T", "Limit reached", zm_client);
        return;
	}
	
	if (!is_zombie_available_cooldown(ZOMBIECLASS_COMMON))
	{
        	update_hint("%T", "Cooldown active", zm_client);
        return;
	}
	
	update_t_zm_activity();
	
	if ((live_zombie_arr[ZOMBIECLASS_COMMON]+count)>max_zombie_arr[ZOMBIECLASS_COMMON])
	   count = max_zombie_arr[ZOMBIECLASS_COMMON]-live_zombie_arr[ZOMBIECLASS_COMMON];
	
	if (count>available_zombie_arr[ZOMBIECLASS_COMMON]) count = available_zombie_arr[ZOMBIECLASS_COMMON];
	
	g_iEntities = GetEntityCountEx();
	if(count<=0 || (g_iEntities+count)>=ENTITY_SAFER_LIMIT)
	{
	   update_hint("%T", "Limit reached", zm_client);
	   return;
    }
    
    TrimString(type);
	char set_model[64] = "";
	if (type[0]!=0)
	{
    	if (strcmp(type,"riot")==0) set_model = MODEL_RIOT;
    	else if (strcmp(type,"ceda")==0) set_model = MODEL_CEDA;
    	else if (strcmp(type,"clown")==0) set_model = MODEL_CLOWN;
    	else if (strcmp(type,"mud")==0) set_model = MODEL_MUD;
    	else if (strcmp(type,"road")==0) set_model = MODEL_ROAD;
    	else if (strcmp(type,"jimmy")==0)
    	{
        	if (jimmy_spawned) return;
        	set_model = MODEL_JIMMY;
        	count=1;
    	}
    	else if (strcmp(type,"fallen")==0)
    	{
        	if (fallen_spawned) return;
        	set_model = MODEL_FALLEN;
        	count=1;
    	}
    	else set_model = "";
	}
	TrimString(set_model);
	
	int temp_cost;
	bool price_angry = angry && ( !panic && !ZM_finale_announced && !L4D_IsSurvivalMode() );
	switch (price_angry)
	{
       	case false: // Not angry - regular price
       	{
           	if (set_model[0]!=0) temp_cost = g_iCostUncommon;
           	else temp_cost = g_iCostCommon;
       	}
       	default: // Angry - more expensive. Doubly more expensive if angry uncommon.
       	{
           	if (set_model[0]!=0) temp_cost = 2*g_iCostUncommon;
           	else temp_cost = g_iCostUncommon;
       	}
	}
	
	int max_count = RoundToFloor(float(bank)/(temp_cost));
	if (count>max_count) count = max_count;
	
	if ( count<=0 || (bank-temp_cost*count)<0 )
	{
        	update_hint("%T", "afford_common", zm_client);
        	return;
	}
	
	int target_client = -1;
	bool use_randompz = false;
	int spawner_state;
    if (flow) spawner_state = SPAWNER_DISTANCE;
    else spawner_state = can_ZM_spawn();
	if (spawner_state!=SPAWNER_OK)
	{
        use_randompz = true;
        target_client = get_spawner_target_survivor(flow,spawner_state);
    	if (target_client<0) return;
	}
	
	angry = angry || panic || ZM_finale_announced || L4D_IsSurvivalMode();
	
	float flow_survivor;
    if (use_randompz && !angry) flow_survivor = L4D2Direct_GetFlowDistance(target_client);
	
	int tries = 3;
	if (count<=10) tries = 5;
	
	int spawned = 0;
	float randomPos[3];
	int ticktime = RoundToNearest(GetGameTime()/GetTickInterval()) + 5;
	for( int i = 0; i < count; i++  )
	{
		
		if (use_randompz)
		{
    		if (!IsValidClient(target_client) || !IsPlayerAlive(target_client))
        		break;
    		if(!L4D_GetRandomPZSpawnPosition(target_client,ZOMBIECLASS_TANK,tries,randomPos))
        		continue;
        	
        	// If not angry, check that the spawn is strictly ahead of the survivor's flow.
        	// Prevents useless zombies spawns where the survivors are unlikely to go.
        	if (!angry && L4D_GetFlowFromPoint(randomPos)<flow_survivor)
            	continue;
        	
		}
		else
		{
    		if (zm_spawner_navArea && count>1)
    		{
        		L4D_FindRandomSpot(zm_spawner_navArea,randomPos);
        		if ( can_any_alive_survivor_see(randomPos,false) )
        		   randomPos=zm_spawner_pos;
    		}
    		else randomPos=zm_spawner_pos;
		}
		
		int zombie = -1;
		if (set_model[0]!=0)
		{
    		zombie = CreateEntityByName("infected");
    		if (zombie>MaxClients && IsValidEntity(zombie))
    		{
        		SetEntityModel(zombie, set_model);
        		SetEntProp(zombie, Prop_Data, "m_nNextThinkTick", ticktime);
        		DispatchSpawn(zombie);
            	ActivateEntity(zombie);
            	TeleportEntity(zombie, randomPos, NULL_VECTOR, NULL_VECTOR);
        	}
		}
		else
		{
    		zombie = L4D_SpawnCommonInfected(randomPos); 
		}
		
        if (zombie>0)
        {
           spawned += 1;
           bank -= temp_cost;
           live_zombie_arr[ZOMBIECLASS_COMMON] += 1;
           g_iEntities += 1;
           if (angry && hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
           // if this doesn't work', try setting the entprop m_mobRush 
           if (set_model[0]!=0 || price_angry) DispatchKeyValue(zombie, "targetname", "zm_unit_uncommon");
           else DispatchKeyValue(zombie, "targetname", "zm_unit_common");
           if (use_randompz) mark_flow_survivor_and_zombie(-1,zombie);
        }
    }
		
	if (spawned<=0)
	{
    	update_hint("%T", "Spawn failed", zm_client);
    	if (live_zombie_arr[ZOMBIECLASS_COMMON]<10) SetConVarInt(FindConVar("director_panic_forever"), 0);
	}
	else
	{
	    
	    if (use_randompz) mark_flow_survivor_and_zombie(target_client,-1);
        
	    char label[32];
	    Format(label, sizeof(label), "%T", "Common", zm_client);
	    update_hint("%T", "Spawned X Y", zm_client, spawned, label);
	    if (!panic && !ZM_finale_announced) add_available_zombie(ZOMBIECLASS_COMMON,-spawned);
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
    	if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
	}
    zm_update(zm_timer);
}

Action reset_time_of_day(Handle Timer)
{
    SetConVarInt(FindConVar("sv_force_time_of_day"),-1);
    return Plugin_Stop;
}
    

void ZM_Witch(int client,int witch_type, bool free = false, bool flow = false)
{

	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
	
	if (DEBUG) PrintToServer("[zm] ZM_Witch");
	
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
	if (live_zombie_arr[ZOMBIECLASS_WITCH]>=max_zombie_arr[ZOMBIECLASS_WITCH]) 
	{
    	update_hint("%T", "Limit reached", zm_client);
    	return;
	}
	
	if (!is_zombie_available_cooldown(ZOMBIECLASS_WITCH))
	{
    	update_hint("%T", "Cooldown active", zm_client);
        return;
	}
	
	update_t_zm_activity();
	
	bool use_randompz = false;
	float spawn_pos[3];
	
	int spawner_state;
	int target_client = -1;
    if (flow) spawner_state = SPAWNER_DISTANCE;
    else spawner_state = can_ZM_spawn(true);
    spawn_pos = zm_spawner_pos;
	if (spawner_state!=SPAWNER_OK)
	{
        use_randompz = true;
        target_client = get_spawner_target_survivor(flow,spawner_state);
    	if (target_client<0) return;
    	if(!L4D_GetRandomPZSpawnPosition(target_client,ZOMBIECLASS_TANK,10,spawn_pos))
        	return;
	}
	
	if (witch_type==WITCH_STATIC) SetConVarInt(FindConVar("sv_force_time_of_day"),0);
	else SetConVarInt(FindConVar("sv_force_time_of_day"),3);
	
	int witch;
	if(g_bSpawnWitchBride) witch = L4D2_SpawnWitchBride(spawn_pos,NULL_VECTOR);
    else witch = L4D2_SpawnWitch(spawn_pos,NULL_VECTOR);
	
	CreateTimer(0.25,reset_time_of_day,TIMER_FLAG_NO_MAPCHANGE);
	
	if (witch>0)
	{
    	if (!free) bank -= temp_cost;
    	live_zombie_arr[ZOMBIECLASS_WITCH] += 1;
    	if (DEBUG) PrintToServer("[zm] Created witch %d", witch);
    	//SDKHook(witch, entity_visible, OnTakeDamage_Units);
    	//CreateZMGlow(witch);
    	L4D2_RemoveEntityGlow_Color(witch);
    	L4D2_RemoveEntityGlow(witch);
    	CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(witch), TIMER_FLAG_NO_MAPCHANGE);
    	entref_delete = EntIndexToEntRef(witch);
    	char label[32];
	    Format(label, sizeof(label), "%T", "Witch", zm_client);
	    update_hint("%T", "Spawned X Y", zm_client, 1, label);
    	add_available_zombie(ZOMBIECLASS_WITCH,-1);
    	create_timer_add_available_zombie(g_fWitchCooldown,ZOMBIECLASS_WITCH,roundcount);
    	DispatchKeyValue(witch, "targetname", "zm_unit");
    	if (use_randompz) mark_flow_survivor_and_zombie(target_client,witch);
	}
	else update_hint("%T", "Spawn failed", zm_client);
    
    zm_update(zm_timer);

}


void CountWitches(bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_WITCH]<=0 && fast) return;
    if (DEBUG) PrintToServer("[zm] CountWitches expensive");
    live_zombie_arr[ZOMBIECLASS_WITCH] = L4D2_GetWitchCount();
}

//#define DEAD 1
//void ResetDeadZombie(int client)
//{
//    //SetStateTransition(client, STATE_ACTIVE);
//    L4D_State_Transition(client, STATE_ACTIVE);
//    SetEntProp(client, Prop_Send, "m_isGhost", true);
//    SetEntProp(client, Prop_Send, "deadflag", DEAD);
//    SetEntProp(client, Prop_Send, "m_lifeState", DEAD);
//   SetEntProp(client, Prop_Send, "m_iPlayerState", DEAD);
//    SetEntProp(client, Prop_Send, "m_zombieState", DEAD);
//    SetEntProp(client, Prop_Send, "m_iObserverMode", DEAD);
//    SetEntProp(client, Prop_Send, "movetype", MOVETYPE_NOCLIP);    
///    L4D_State_Transition(client, STATE_OBSERVER_MODE);
//    SetEntProp(client, Prop_Send, "m_isGhost", false);
//    SetEntProp(client, Prop_Send, "m_iObserverMode", 6);
//    SetEntProp(client, Prop_Send, "movetype", MOVETYPE_NOCLIP);   
//}

void delete_all_infected(bool common=true, bool witch=true, bool special=true)
{
   	bool anything_to_delete = false;
   	if (common && live_zombie_arr[ZOMBIECLASS_COMMON]>0) anything_to_delete = true;
   	if (witch && live_zombie_arr[ZOMBIECLASS_WITCH]>0) anything_to_delete = true;
   	if (special && live_SI>0) anything_to_delete = true;
   	if (!anything_to_delete) return;
   	
   	reset_live_zombie_arr(common,witch,special);
   	
   	if (DEBUG) PrintToServer("[zm] delete_all_infected");
   	
   	static char class[32];
   	int entity;
   	for(entity = 0; entity < MAXENTITIES; entity++)
   	{
   		if(IsValidEntity(entity))
   		{    
   		     if (entity==zm_client) continue;
   		     if (GetEntProp(entity,Prop_Data,"m_iMaxHealth")<=0) continue;
      	     GetEntityClassname(entity, class, sizeof(class));
      	     if ( (ZM_finale_announced || L4D_IsSurvivalMode()) && strcmp(class,"player")==0 && GetEntProp(entity, Prop_Send, "m_zombieClass")==ZOMBIECLASS_TANK )
             {
                 live_zombie_arr[ZOMBIECLASS_TANK] += 1;
                 continue;
             }
      	     
      	     if ( (common && strcmp(class,"infected")==0) || (witch && strcmp(class,"witch")==0) || (special && strcmp(class,"player")==0 && GetClientTeam(entity)==TEAM_INFECTED) )
      	     {
          	     remove_ZM_glow(entity);
          	     AcceptEntityInput(entity, "kill"); 
      	     }
   		}
   	}
   	
   	if (special && clients_timer==INVALID_HANDLE)
   	   clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
   	
   	//cleanup_bad_glows();  	
}

Action ZM_Spawn_Witch(int client, int args)
{	
	if (!g_bCvarAllow || client!=zm_client) return Plugin_Continue;
	int witch_type = WITCH_STATIC;
	bool flow = false;
	if (args>0)
	{
	    int arg_int;
        char arg[32];
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


void zm_del_pointing(int client)
{
   
   if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
   
   if (DEBUG) PrintToServer("[zm] zm_del_pointing");
   
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
   
   if ( (ZM_finale_announced || L4D_IsSurvivalMode()) && strcmp(class,"player")==0 && GetEntProp(target, Prop_Send, "m_zombieClass")==ZOMBIECLASS_TANK )
   {
       update_hint("%T", "Cannot delete", zm_client);
       return;
   }
   
   AcceptEntityInput(target,"Kill");
   
   if (strcmp(class,"player")==0)
   {
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
   }
   else if (strcmp(class,"witch")==0) CountWitches();
   else CountCommons();
   
   //cleanup_bad_glows();
   
}

public Action evtPlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
    
    if (!g_bCvarAllow) return Plugin_Continue;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (GetClientTeam(victim)==TEAM_SURVIVOR && hp_timers[victim]==INVALID_HANDLE)
       hp_timers[victim] = CreateTimer(0.1,UpdateSurvivorGlow,victim,TIMER_FLAG_NO_MAPCHANGE);
    if (panic_target==victim) panic_target = -1;
	return Plugin_Continue;
}

//int zm_deathClass;
// After ZM has died as living infected, allow free camera again
//Action unfreeze_zm(Handle Timer)
//{
    //if (!IsValidClientZM()) return Plugin_Continue;
    
    //JoinZM(zm_client,0);
    //SetEntityFlags(zm_client, GetEntityFlags(zm_client) & ~FL_FROZEN);
    
    // int deadflag = GetEntProp(zm_client, Prop_Send, "deadflag", 0);
	//int lifestate = GetEntProp(zm_client, Prop_Send, "m_lifeState", 0);
	//int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode", 0);
	//int playerstate = GetEntProp(zm_client, Prop_Send, "m_iPlayerState", 0);
	//int zombiestate = GetEntProp(zm_client, Prop_Send, "m_zombieState", 0);
	//int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
	//PrintToServer("[zm] unfreeze_zm %d %d %d %d %d", deadflag, lifestate, observermode, playerstate, zombiestate);
	
	// dead and ready to free cam: 1 2 6 6 0
    
    //if (zClass==ZOMBIECLASS_TANK)
    //{
    //    // Camera gets very buggy and laggy, idk.
    //    L4D_State_Transition(zm_client, STATE_GHOST);
    //}
    //else
    //{
        //L4D_State_Transition(zm_client, STATE_DEATH_WAIT_FOR_KEY);
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        //L4D_State_Transition(zm_client, STATE_GHOST);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
    //    SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        //ChangeClientTeam(zm_client,TEAM_ZM);
    //}
    
    //if (deadflag==1 && lifestate==2 && playerstate==6 && zombiestate==0)
   // if (deadflag==1 && zombiestate==0)
   // {
        
       // zm_just_died = true;
        
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        
        //int temp_client = zm_client;
        //ChangeClientTeam(zm_client,TEAM_SURVIVOR);
        //if (zm_client_userid>0) zm_client = GetClientOfUserId(zm_client_userid);
        
        //ChangeClientTeam(zm_client,TEAM_ZM);
        
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
        //SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        
        //if (zm_deathClass==ZOMBIECLASS_TANK)
        //{
        //    L4D_SetClass(zm_client, ZOMBIECLASS_SMOKER);
            //L4D_State_Transition(zm_client, STATE_GHOST);
        //    L4D_BecomeGhost(zm_client);
            //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            //SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        //}
        
        //TeleportEntity(zm_client, zm_deathPos, NULL_VECTOR, NULL_VECTOR);
        //SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0);
        //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        //SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
        //SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
        //SetEntPropEnt(zm_client, Prop_Send, "m_hViewEntity", -1);
	    //SetClientViewEntity(zm_client, zm_client);
	   // SetEntityFlags(zm_client, GetEntityFlags(zm_client) & ~FL_FROZEN);
	    //SetEntPropEnt(zm_client, Prop_Send, "m_hZoomOwner", -1);
	    //SetEntProp(zm_client, Prop_Send, "m_iFOV", 0);
	    //SetEntProp(zm_client, Prop_Send, "m_iFOVStart", 0);
	    //SetEntPropFloat(zm_client, Prop_Send, "m_flFOVRate", 0.0);
	    //SetEntProp(zm_client, Prop_Data, "m_fFlags", 65664);  // FL_CLIENT | FL_AIMTARGET
	    //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
	    //SetEntityMoveType(zm_client, 10);
	    //L4D_State_Transition(zm_client, STATE_GHOST);
	    //L4D_BecomeGhost(zm_client);
	    //L4D_CleanupPlayerState(zm_client);
	    
	    //L4D_ReplaceWithBot(zm_client);
	    //zm_client = temp_client;
	    //ChangeClientTeam(zm_client,TEAM_ZM);
	    //JoinZM(zm_client,0);
	    
	    //if (zm_client_userid>0) zm_client = GetClientOfUserId(zm_client_userid);
	    //if (zm_client>0) JoinZM(zm_client,0);
	    
	    //ClientCommand(zm_client, "cl_fullupdate");
        
       // return Plugin_Continue;
    //}
    
    //CreateTimer(0.1,unfreeze_zm,TIMER_FLAG_NO_MAPCHANGE);
    
   // return Plugin_Continue;
//}

public Action evtPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    
    if (!g_bCvarAllow) return Plugin_Continue;
    
    // Skip victims that are not infected entities
    int victim = GetClientOfUserId(event.GetInt("userid"));
    //if (DEBUG)
    //{
    //    int max_health = GetEntProp(victim,Prop_Data,"m_iMaxHealth");
        int health = GetEntProp(victim,Prop_Data,"m_iHealth");
    //    PrintToServer("%d died %d/%d", victim, health, max_health);
    //}
    if (!IsValidClient(victim) || !IsClientInGame(victim)) return Plugin_Continue;
    
    
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
    
    L4D2_RemoveEntityGlow(victim);
    
    if(GetClientTeam(victim)!=TEAM_INFECTED) return Plugin_Continue;
    
    char targetName[20];
    GetEntPropString(victim, Prop_Data, "m_iName", targetName, sizeof(targetName));
    
    if (active_looktarget && entref_control==EntIndexToEntRef(victim))
    {
        if (strcmp(targetName,"zm_unit_control")!=0 && strcmp(targetName,"zm_control")!=0)
            update_ZM_looktarget_HP(0);
        active_looktarget = false;
    }
    
    int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    
    if (DEBUG) PrintToServer("[zm] evtPlayerDeath %d %s, %d HP", victim, targetName, health);
    
     // survival: every non-ZM tank death gives ZM bank
     if (zClass==ZOMBIECLASS_TANK)
     {
        if ( strcmp(targetName,"zm_unit")!=0 && strcmp(targetName,"zm_unit_control")!=0 && strcmp(targetName,"zm_control")!=0 )
        {
            if (DEBUG) PrintToServer("[zm] Survival non-ZM tank died");
            bank += g_iBonusFinaleStage*g_iAliveSurvivors;
            update_hint("%T", "Tank died reward", zm_client);
            if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_REWARD);
        }
     }
    
    // ZM controlling special infected has died
    if (victim==zm_client)
    {
        //RequestFrame(OnNextFrame_UpdateDeathTime, GetClientUserId(zm_client));
        if (zClass!=ZOMBIECLASS_TANK || !ZM_finale_announced )
        {
            PrintToServer("[zm] Unexpected player_death on ZM!!! Report this to mod authors.");
            EmitSoundToAll(SOUND_BUG);
        }
        //float vOrigin[3];
        //GetClientAbsOrigin(zm_client, zm_deathPos);
        GetClientEyePosition(zm_client,zm_deathPos);
        //ChangeClientTeam(zm_client,TEAM_SURVIVOR);
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        //JoinZM(zm_client,0);
        //ChangeClientTeam(client,TEAM_ZM);
        //L4D_State_Transition(client, STATE_OBSERVER_MODE);
        L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        L4D_CleanupPlayerState(zm_client);
        if (panic_target==zm_client) panic_target = -1;
        //JoinZM(zm_client,0);
        //ZMTeleport(zm_client,0);
        
        //L4D_State_Transition(zm_client, STATE_DEATH_WAIT_FOR_KEY);

        //ForcePlayerSuicide(zm_client);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //L4D_ReplaceWithBot(zm_client);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //L4D_CleanupPlayerState(zm_client);
        
        TeleportEntity(zm_client, zm_deathPos, NULL_VECTOR, NULL_VECTOR);
        //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        //unfreeze_zm();
        //zm_deathClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
        //if (zClass == ZOMBIECLASS_TANK) CreateTimer(2.0,unfreeze_zm,zClass,TIMER_FLAG_NO_MAPCHANGE);
        //else CreateTimer(0.5,unfreeze_zm,zClass,TIMER_FLAG_NO_MAPCHANGE);
        
        //L4D_CleanupPlayerState(zm_client);
        SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0);
        //SetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", {0.0,0.0,0.0});
        SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        
        //CreateTimer(0.1,unfreeze_zm,TIMER_FLAG_NO_MAPCHANGE);
        
        DispatchKeyValue(zm_client, "targetname", "zm_client");
        
    }
    
    remove_ZM_glow(victim);
    
    // survival: every non-ZM tank death gives ZM bank
    //if (zClass==ZOMBIECLASS_TANK && L4D_IsSurvivalMode())
    //{
    //   char targetName[20];
    //   GetEntPropString(victim, Prop_Data, "m_iName", targetName, sizeof(targetName));
    //   int incap = L4D_IsPlayerIncapacitated(victim);
    //   if ( strcmp(targetName,"zm_unit")!=0 && strcmp(targetName,"zm_unit_control")!=0 )
    //   {
    //       PrintToServer("[zm] Survival non-ZM tank died %d %s, %d HP, incap %d", victim, targetName, health, incap);
    //       if (victim==zm_client) DispatchKeyValue(victim, "targetname", "zm_client");
    //       else DispatchKeyValue(victim, "targetname", "zm_unit_dead");
    //       bank += g_iBonusFinaleStage*g_iAliveSurvivors;
    //       update_hint("%T", "Tank died reward", zm_client);
    //   }
    //}

	return Plugin_Continue;
}

void spawn_free_angry_zombies(int victim, int count)
{
    if (!IsValidClient(victim) || GetClientTeam(victim)!=TEAM_SURVIVOR || !IsPlayerAlive(victim)) return;
    
    if (DEBUG) PrintToServer("[zm] spawn_free_angry_zombies");
    
    CountCommons(false);
    if (live_zombie_arr[ZOMBIECLASS_COMMON]>=max_zombie_arr[ZOMBIECLASS_COMMON]) return;
    
    if ((live_zombie_arr[ZOMBIECLASS_COMMON]+count)>max_zombie_arr[ZOMBIECLASS_COMMON])
       count = max_zombie_arr[ZOMBIECLASS_COMMON]-live_zombie_arr[ZOMBIECLASS_COMMON];
    
    if (count<=0) return;
    
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
                //SetEntProp(zombie,Prop_Data,"m_iHealth", GetEntProp(zombie,Prop_Data,"m_iMaxHealth")-1 ); // no refunds
                live_zombie_arr[ZOMBIECLASS_COMMON] += 1;
                if (hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
            }
            
        }
    }
    
    if (IsValidClientZM()) update_EMS_HUD();
    
}

static int vomit_numzombies = 10;
public Action Event_PlayerBoomed(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    //if (!event.GetBool("infected")) return Plugin_Continue;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    // by_boomer
    if (GetClientTeam(victim)==TEAM_SURVIVOR)
    {
        spawn_free_angry_zombies(victim,vomit_numzombies);
        L4D2_RemoveEntityGlow(victim);
        L4D2_SetPlayerSurvivorGlowState(victim,true);
        arr_biled[victim] = true;
        arr_hp[victim] = -1;
    }
    return Plugin_Continue;
}

public Action Event_PlayerUnBoomed(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    //if (!event.GetBool("infected")) return Plugin_Continue;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (GetClientTeam(victim)==TEAM_SURVIVOR)
    {
        arr_biled[victim] = false;
        arr_hp[victim] = -1;
        UpdateSurvivorGlow(null,victim);
    }
    
    return Plugin_Continue;
}

public Action EvtWitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) PrintToServer("[zm] EvtWitchKilled");
    
    int witch = event.GetInt("witchid");
    remove_ZM_glow(witch);

	return Plugin_Continue;
}

void mark_flow_survivor_and_zombie(int survivor=-1, int zombie=-1)
{
    
    if (!IsValidClientZM()) return;
     
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

int ZM_Spawn_SI(int client, int ZOMBIECLASS, bool free = false, bool setpos=false, float pos[3] = {0.0,0.0,0.0}, bool glow = true, bool flow = false)
{
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client || ZOMBIECLASS<=0) return -1;
	
	if (!l4d2_specials)
    {
        if (ZOMBIECLASS==ZOMBIECLASS_SPITTER || ZOMBIECLASS==ZOMBIECLASS_JOCKEY || ZOMBIECLASS==ZOMBIECLASS_CHARGER)
            return -1;
    }
	
	if (DEBUG) PrintToServer("[zm] ZM_Spawn_SI");
	
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
	
	int target_client = -1;
	float spawn_pos[3];
	bool use_randompz = false;
	
	if (!setpos)
	{
	    if (live_SI>=max_SI || live_zombie_arr[ZOMBIECLASS]>=max_unique_SI)
        {
            update_hint("%T", "Limit reached", zm_client);
            return -1;
        }
	    
	    if (!is_zombie_available_cooldown(ZOMBIECLASS))
    	{
        	// TO DO: print time left
        	update_hint("%T", "Cooldown active", zm_client);
        	return -1;
    	}
	    
    	int spawner_state;
        if (flow) spawner_state = SPAWNER_DISTANCE;
        else spawner_state = can_ZM_spawn();
        spawn_pos = zm_spawner_pos;
    	if (spawner_state!=SPAWNER_OK)
    	{
            use_randompz = true;
            target_client = get_spawner_target_survivor(flow,spawner_state);
        	if (target_client<0) return -1;
        	if(!L4D_GetRandomPZSpawnPosition(target_client,ZOMBIECLASS,10,spawn_pos))
            	return -1;
    	}
    }
    else spawn_pos = pos;
    
    if (IsObstructed(spawn_pos,ZOMBIECLASS)) PrintToServer("[zm] Obstructed");
    
    update_t_zm_activity();
	
	int bot = -1;
    
    // TBD: custom models, see spawn_infected_nolimit
    
	switch (ZOMBIECLASS)
	{
        case ZOMBIECLASS_SMOKER: 
    	{
    		bot = SDKCall(hCreateSmoker, "ZM Smoker");
    	}
    	case ZOMBIECLASS_BOOMER: 
    	{
    		bot = SDKCall(hCreateBoomer, "ZM Boomer");
    	}
    	case ZOMBIECLASS_HUNTER: 
    	{
    		bot = SDKCall(hCreateHunter, "ZM Hunter");
    	}
    	case ZOMBIECLASS_SPITTER: 
    	{
    		bot = SDKCall(hCreateSpitter, "ZM Spitter");
    	}
    	case ZOMBIECLASS_JOCKEY: 
    	{
    		bot = SDKCall(hCreateJockey, "ZM Jockey");
    	}
    	case ZOMBIECLASS_CHARGER: 
    	{
    		bot = SDKCall(hCreateCharger, "ZM Charger");
    	}
    	case ZOMBIECLASS_TANK: 
    	{
    		bot = SDKCall(hCreateTank, "ZM Tank");
    	}
	}
	
	if (IsValidClient(bot))
	{
       	ChangeClientTeam(bot, TEAM_INFECTED);
       	SetEntProp(bot, Prop_Send, "m_usSolidFlags", 16);
       	SetEntProp(bot, Prop_Send, "deadflag", 0);
       	SetEntProp(bot, Prop_Send, "m_lifeState", 0);
       	SetEntProp(bot, Prop_Send, "m_iObserverMode", 0);
       	SetEntProp(bot, Prop_Send, "m_iPlayerState", 0);
       	SetEntProp(bot, Prop_Send, "m_zombieState", 0);
       	DispatchSpawn(bot);
       	ActivateEntity(bot);
       	TeleportEntity(bot, spawn_pos, NULL_VECTOR, NULL_VECTOR);
       	if (zm_stage<ZM_STARTED)
       	{
           	SetEntProp(bot, Prop_Send, "movetype", 0);
           	SetEntProp(bot, Prop_Send, "m_fFlags", GetEntProp(bot, Prop_Send, "m_fFlags")|FL_FROZEN);
       	}
       	else SetEntProp(bot, Prop_Send, "movetype", 2);
       	if (!free) bank -= cost_SI;
       	
       	if (glow) CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(bot), TIMER_FLAG_NO_MAPCHANGE);
       	
       	entref_delete = EntIndexToEntRef(bot);
       	active_looktarget = true;
        update_entref_control(entref_delete);
        
        if (!setpos)
        {
            active_looktarget = true;
            add_available_zombie(ZOMBIECLASS,-1);
            
            float cooldown_time;
            if (ZOMBIECLASS==ZOMBIECLASS_TANK) cooldown_time = g_fTankCooldown;
            else cooldown_time = g_fSpecialCooldown;
            
            //CreateTimer(cooldown_time, timer_add_available_zombie, ZOMBIECLASS, TIMER_FLAG_NO_MAPCHANGE);
            create_timer_add_available_zombie(cooldown_time,ZOMBIECLASS,roundcount);
            L4D2_SetCustomAbilityCooldown(bot,0.0); //spitter fix
            
            if (!zm_use_notify && zm_stage>=ZM_STARTED)
            {
                update_hint("%T", "ZM control hint", zm_client);
                if (IsValidClientZM()) PrintHintText(zm_client, "%t", "ZM control hint");
                zm_use_notify = true;
            }
            else 
            {
                char name[32];
                get_zombieclass_name(ZOMBIECLASS,name);
                Format(name, sizeof(name), "%T", name, zm_client);
                update_hint("%T", "Spawned X Y", zm_client, 1, name);
            }
            
            if (use_randompz) mark_flow_survivor_and_zombie(target_client,bot);
            
        }
    
        
        L4D2_CommandABot(bot,L4D_GetHighestFlowSurvivor(),BOT_CMD_ATTACK);
        
        zm_update(zm_timer);

	}
	else update_hint("%T", "Spawn failed", zm_client);
    
	return bot;
}

// ZM_Spawn_SI(int client, int ZOMBIECLASS, bool free = false, bool setpos=false, float pos[3] = {0.0,0.0,0.0}, bool glow = true, bool flow = false)
Action ZM_Smoker(int client, int args)
{
   char extra[32];
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_SMOKER,extra);
   return Plugin_Continue;
}

Action ZM_Boomer(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_BOOMER,extra);
   return Plugin_Continue;
}

Action ZM_Hunter(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_HUNTER,extra);
   return Plugin_Continue;
}

Action ZM_Spitter(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_SPITTER,extra);
   return Plugin_Continue;
}

Action ZM_Jockey(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_JOCKEY,extra);
   return Plugin_Continue;
}

Action ZM_Charger(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_CHARGER,extra);
   return Plugin_Continue;
}

Action ZM_Tank(int client, int args)
{
   char extra[32] = "";
   if (args>0) GetCmdArg(1, extra, sizeof(extra));
   ZM_Unit_Special(client,ZOMBIECLASS_TANK,extra);
   return Plugin_Continue;
}

Action ZM_Unit_Special(int client, int ZOMBIECLASS, char[] arg = "")
{
    bool flow = false;
    if (strcmp(arg,"flow",false)==0) flow = true;
    int bot = ZM_Spawn_SI(client,ZOMBIECLASS,_,_,_,_,flow);
    if (IsValidClient(bot)) DispatchKeyValue(bot, "targetname", "zm_unit");
    return Plugin_Continue;
}

Action ZM_Delete(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   zm_del_pointing(client);
   return Plugin_Continue;
}

Action ZM_Delete_All(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(true,true,true);
   return Plugin_Continue;
}

Action ZM_Delete_Commons(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(true,false,false);
   return Plugin_Continue;
}

Action ZM_Delete_Specials(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(false,false,true);
   return Plugin_Continue;
}

Action ZM_Delete_Witches(int client, int args)
{
   if (!g_bCvarAllow) return Plugin_Continue;
   if (IsValidClientZM() && client==zm_client) delete_all_infected(false,true,false);
   return Plugin_Continue;
}


void ResetCvars()
{
    if (DEBUG) PrintToServer("[zm] ResetCvars");
    
    ResetConVar(FindConVar("director_tank_lottery_selection_time"), true, true);
    ResetConVar(FindConVar("tank_stuck_time_suicide"), true, true);
    ResetConVar(FindConVar("z_frustration"), true, true);
    ResetConVar(FindConVar("tank_stuck_failsafe"), true, true);
    
    //ResetConVar(FindConVar("sb_enforce_proximity_range"), true, true);
    //ResetConVar(FindConVar("sb_unstick"), true, true);
    
    //ResetConVar(FindConVar("z_common_limit"), true, true);
    ResetConVar(FindConVar("z_no_cull"), true, true);
	ResetConVar(FindConVar("z_minion_limit"), true, true);
	//ResetConVar(FindConVar("director_no_mobs"), true, true);
	//ResetConVar(FindConVar("z_wandering_density"), true, true);
	ResetConVar(FindConVar("director_no_bosses"), true, true);
	ResetConVar(FindConVar("director_no_specials"), true, true);
	ResetConVar(FindConVar("director_panic_forever"), true, true);
	
	ResetConVar(FindConVar("z_discard_range"), true, true);
	ResetConVar(FindConVar("z_discard_min_range"), true, true);

	ResetConVar(FindConVar("survival_max_smokers"), true, true);
	ResetConVar(FindConVar("survival_max_boomers"), true, true);
	ResetConVar(FindConVar("survival_max_hunters"), true, true);
	ResetConVar(FindConVar("survival_max_spitters"), true, true);
	ResetConVar(FindConVar("survival_max_jockeys"), true, true);
	ResetConVar(FindConVar("survival_max_chargers"), true, true);
	ResetConVar(FindConVar("survival_max_specials"), true, true);
	ResetConVar(FindConVar("survival_special_limit_increase"), true, true);
	ResetConVar(FindConVar("survival_special_spawn_interval"), true, true);
	ResetConVar(FindConVar("survival_special_stage_interval"), true, true);
	ResetConVar(FindConVar("z_smoker_limit"), true, true);
	ResetConVar(FindConVar("z_boomer_limit"), true, true);
	ResetConVar(FindConVar("z_hunter_limit"), true, true);
	ResetConVar(FindConVar("z_spitter_limit"), true, true);
	ResetConVar(FindConVar("z_jockey_limit"), true, true);
	ResetConVar(FindConVar("z_charger_limit"), true, true);
	ResetConVar(FindConVar("director_allow_infected_bots"), true, true);
	ResetConVar(FindConVar("z_spawn_safety_range"), true, true);
	
	ResetConVar(FindConVar("z_max_player_zombies"), true,true);
	
	//if (infectedbots_dispose_cowards) ResetConVar(infectedbots_dispose_cowards, true,true);
	if (infectedbots_enable) ResetConVar(infectedbots_enable, true,true);

}

// Re-run this if player number has changed
void SetCvarsZM()
{
   if (DEBUG) PrintToServer("[zm] SetCvarsZM");
   if (!g_bCvarAllow) return;
   
   SetConVarInt(FindConVar("director_tank_lottery_selection_time"), 9999);
   SetConVarInt(FindConVar("tank_stuck_time_suicide"), 0);
   SetConVarInt(FindConVar("z_frustration"), 0);
   SetConVarInt(FindConVar("tank_stuck_failsafe"), 0);
   
   // Prevent survivor bot teleport to ZM bug
   // If that doesn't work try detouring SurvivorBot::EnforceProximityToHumans
   //SetConVarInt(FindConVar("sb_enforce_proximity_range"), 99999);
   //SetConVarInt(FindConVar("sb_unstick"), 0);
   
   //SetConVarInt(FindConVar("z_common_limit"), 1);
   SetConVarInt(FindConVar("z_discard_min_range"), 9999999);
   SetConVarInt(FindConVar("z_discard_range"), 9999999);
   SetConVarInt(FindConVar("z_no_cull"), 1);
   SetConVarInt(FindConVar("z_minion_limit"), 0);
   //SetConVarInt(FindConVar("director_no_mobs"), 1);
   //SetConVarInt(FindConVar("z_wandering_density"), 0);
   SetConVarInt(FindConVar("director_no_bosses"), 1);
   SetConVarInt(FindConVar("director_no_specials"), 1);
   SetConVarInt(FindConVar("director_allow_infected_bots"), 0);
   
   int d;
   
   // Check if Specials need updating
   int new_max_SI;
   if (g_iMaxSI<0) new_max_SI = g_iAliveSurvivors;
   else new_max_SI = g_iMaxSI;
   if ((MaxClients-AllPlayerCount)<new_max_SI)
   {
      new_max_SI = MaxClients-AllPlayerCount;
   }
   if (new_max_SI!=max_SI)
   {
       available_SI += (new_max_SI-max_SI);
       max_SI = new_max_SI;
       if (available_SI>max_SI) available_SI = max_SI;
       else if (available_SI<0) available_SI = 0;
   }
   int new_max_unique_SI;
   if (g_iMaxUniqueSI<0) new_max_unique_SI = RoundToCeil(max_SI/2.0);
   else new_max_unique_SI = g_iMaxUniqueSI;
   if (new_max_unique_SI!=max_unique_SI)
   {
       d = new_max_unique_SI - max_unique_SI;
       int length = sizeof(available_zombie_arr);
       for(int i = 0; i < length; i++)
       {
             if (i==ZOMBIECLASS_COMMON || i==ZOMBIECLASS_WITCH) continue;
             available_zombie_arr[i] += d;
             if (available_zombie_arr[i]<0) available_zombie_arr[i] = 0;
             else if (available_zombie_arr[i]>new_max_unique_SI) available_zombie_arr[i] = new_max_unique_SI;
             max_zombie_arr[i] = new_max_unique_SI;
       }
       max_unique_SI = new_max_unique_SI;
   }
   
   // Check if Witches need updating
   int new_max_witches;
   if (g_iMaxWitches<0) new_max_witches = g_iAliveSurvivors;
   else new_max_witches = g_iMaxWitches;
   if (new_max_witches!=max_zombie_arr[ZOMBIECLASS_WITCH])
   {
      d = new_max_witches - max_zombie_arr[ZOMBIECLASS_WITCH];
      max_zombie_arr[ZOMBIECLASS_WITCH] = new_max_witches;
      add_available_zombie(ZOMBIECLASS_WITCH,d);
   }
   
   // Include all SI on field + spectating ZM
   SetConVarInt(FindConVar("survival_max_specials"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_max_player_zombies"), MAXPLAYERS);
   
   SetConVarInt(FindConVar("survival_max_smokers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_boomers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_hunters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_spitters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_jockeys"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_chargers"), MAXPLAYERS);
   

   SetConVarInt(FindConVar("z_smoker_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_boomer_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_hunter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_spitter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_jockey_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_charger_limit"), MAXPLAYERS);
   
   //if (infectedbots_dispose_cowards) SetConVarInt(infectedbots_dispose_cowards, 0);
   if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
   
   zm_update(zm_timer);
   
}

bool IsValidClient(int client, bool replaycheck = true)
{
	if (client < 1 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}

void PluginPrecacheModel(const char[] model)
{
	if (!IsModelPrecached(model)) PrecacheModel(model, true);
}

public void OnMapStart()
{
    if (DEBUG) PrintToServer("[zm] OnMapStart");
	
	//PluginPrecacheModel(MODEL_LADDER);
	
	PluginPrecacheModel(MODEL_SMOKER);
	PluginPrecacheModel(MODEL_BOOMER);
	PluginPrecacheModel(MODEL_HUNTER);
	PluginPrecacheModel(MODEL_SPITTER);
	PluginPrecacheModel(MODEL_JOCKEY);
	PluginPrecacheModel(MODEL_CHARGER);
	PluginPrecacheModel(MODEL_TANK);
	
	PluginPrecacheModel(MODEL_RIOT); // Riot Police
	PluginPrecacheModel(MODEL_CEDA); // CEDA Hazmat
	PluginPrecacheModel(MODEL_CLOWN); // Clown
	PluginPrecacheModel(MODEL_MUD); // Mud
	PluginPrecacheModel(MODEL_ROAD); // Road Worker
	PluginPrecacheModel(MODEL_JIMMY); // Jimmy Gibbs
	PluginPrecacheModel(MODEL_FALLEN); // Fallen Survivor
	
	g_iLaser = PrecacheModel(VMT_LASERBEAM, true);
	g_iHalo = PrecacheModel(VMT_HALO, true);
	
	PrecacheSound(SOUND_REWARD);
	PrecacheSound(SOUND_READY);
	PrecacheSound(SOUND_BUG);
	PrecacheSound(SOUND_DOORSLAM);
	PrecacheSound(SOUND_DOORSLAM2);
	PrecacheSound(SOUND_DOORSLAM3);
	PrecacheSound(SOUND_INACTIVITY);
    PrecacheSound(SOUND_START);
    PrecacheSound(SOUND_VISION);
    
    PrecacheSound(SOUND_ELLIS_ZM);
    PrecacheSound(SOUND_LOUIS_ZM);
    
    //AddFileToDownloadsTable(SOUND_ELLIS_ZM);
    //AddFileToDownloadsTable(SOUND_LOUIS_ZM); 
    
    PrecacheSound(SOUND_PANIC_ON);
    PrecacheSound(SOUND_PANIC_OFF);
    
    PrecacheSound(SOUND_SCARY1);
    PrecacheSound(SOUND_SCARY2);
    PrecacheSound(SOUND_SCARY3);
    PrecacheSound(SOUND_SCARY4);
    PrecacheSound(SOUND_SCARY5);
    
    PrecacheSound(SOUND_BLOCKED);
    PrecacheSound(SOUND_CONDITIONAL);
    PrecacheSound(SOUND_ALLOWED);

	g_bSpawnWitchBride = false;
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	if(StrEqual("c6m1_riverbank", sMap, false)) g_bSpawnWitchBride = true;
	else g_bSpawnWitchBride = false;
	
	saferoom_locked = false;
	zm_can_start = false;
	
	if (g_bCvarAllow && !g_bNavReady)
	{
    	g_hObscuredList = new ArrayList(sizeof(PreCalcNav));
    	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
    	g_bNavReady = false;
    	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	//EventManager = L4D2Direct_GetScriptedEventManager();
	//EventManager = L4D_GetPointer(POINTER_EVENTMANAGER);
	//CDirector = L4D_GetPointer(POINTER_DIRECTOR);

	// env_shake needs to be "precached"
	int shake = CreateEntityByName("env_shake");
	if( shake != -1 )
	{
		DispatchKeyValue(shake, "spawnflags", "8");
		DispatchKeyValue(shake, "amplitude", "16.0");
		DispatchKeyValue(shake, "frequency", "1.5");
		DispatchKeyValue(shake, "duration", "0.9");
		DispatchKeyValue(shake, "radius", "50");
		TeleportEntity(shake, view_as<float>({ 0.0, 0.0, -1000.0 }), NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(shake);
		ActivateEntity(shake);
		AcceptEntityInput(shake, "Enable");
		AcceptEntityInput(shake, "StartShake");
		RemoveEdict(shake);
	}
	
	g_bMapStarted = true;
	
	
}

Action Timer_StartPrecomputeNav(Handle timer)
{
	if (DEBUG) PrintToServer("[zm] Starting navmesh precomputation...");
	float startTime = GetEngineTime();

	// Get all nav areas
	ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
	int totalAreas = allAreas.Length;
    g_bNavReady = false;
    
	PrintToServer("[zm] Found %d nav areas to process", totalAreas);
    if (totalAreas<1) return Plugin_Stop;
    
    Address temp_navArea;
    float vector_start[3];
    bool start_known = false;
    int g_iInfoPlayerStart = FindEntityByClassname(INVALID_ENT_REFERENCE, "info_player_start");
    if(IsValidEntity_Safe(g_iInfoPlayerStart))
    {
        GetEntPropVector(g_iInfoPlayerStart, Prop_Data, "m_vecOrigin", vector_start);
        temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
        if (navArea_validStart(temp_navArea)) start_known = true;
    }
    if (!start_known)
    {
        int entity = INVALID_ENT_REFERENCE;
        while( INVALID_ENT_REFERENCE != (entity = FindEntityByClassname(entity, "info_survivor_position")) )
	    {
       	    if(IsValidEntity_Safe(entity)) 
       	    {
           	     GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vector_start);
           	     temp_navArea = L4D_GetNearestNavArea(vector_start,500.0,true,false,true,TEAM_SURVIVOR);
                 if (navArea_validStart(temp_navArea)) start_known = true;
            }
	   }
    }
    
    
    int navSpawnAttributes;
    int total_stored_obscured = 0;
    int total_stored_start = 0;
    bool valid_start = false;
    bool valid_obscured = false;
    PreCalcNav cell;
    float pos[3];
    float vSize[3];
	for (int i = 0; i < totalAreas; i++)
	{
		Address navArea = allAreas.Get(i);
		if (!navArea) continue;
		L4D_GetNavAreaSize(navArea, vSize);
        if (vSize[0]<=50.0 && vSize[1]<=50.0) continue;
		L4D_FindRandomSpot(navArea,pos);
		valid_start = false;
		valid_obscured = true;
		navSpawnAttributes = L4D_GetNavArea_SpawnAttributes(navArea);
		
		valid_start = navArea_validStart(navArea);
		if (valid_start) valid_obscured = false;
		
		//valid_start = (navSpawnAttributes & NAV_SPAWN_PLAYER_START) || (navSpawnAttributes & NAV_SPAWN_CHECKPOINT && navSpawnAttributes & ~NAV_SPAWN_FINALE && navSpawnAttributes & ~NAV_SPAWN_OBSCURED);
		if (valid_start)
		{
    	//	float flow = L4D_GetFlowFromPoint(pos);
    	//	if (flow>0.0 || flow<(-9000.0)) valid_start = false;
    		
    		float distance = 0.0;
    		if (valid_start && start_known) distance = L4D2_NavAreaTravelDistance(vector_start,pos,false);
    		//bool isconnected = L4D_NavArea_IsConnected(navArea,temp_navArea,4);
    		//bool isconnected = L4D2_IsReachable(1,pos);
    		
    		//if (valid_start) PrintToServer("[zm] start nav size: %f %f %f, flow: %f, start dist: %f", vSize[0], vSize[1], vSize[2], flow, distance);
    		if (distance>500.0) valid_start = false;
    		
		}
		
		if (!valid_start && valid_obscured) valid_obscured = ( (navSpawnAttributes & NAV_SPAWN_OBSCURED) || (navSpawnAttributes & NAV_SPAWN_IGNORE_VISIBILITY) );
		
		if (valid_start || valid_obscured)
		{
    		L4D_FindRandomSpot(navArea,pos);
    		cell.position[0] = pos[0];
			cell.position[1] = pos[1];
			cell.position[2] = pos[2];
			cell.navArea = navArea;
		}
		else continue;
		
		if (valid_start)
		{
    		g_hStartAreaList.PushArray(cell);
    		total_stored_start += 1;
		}
		else if (valid_obscured)
		{
    		g_hObscuredList.PushArray(cell);
    		total_stored_obscured += 1;
		}
		
	}

	delete allAreas;

	g_bNavReady = true;

	float duration = GetEngineTime() - startTime;
	PrintToServer("[zm] Navmesh precomputation took %f seconds", duration);
	PrintToServer("[zm] Total obscured navmeshes: %d", total_stored_obscured);
	PrintToServer("[zm] Total start area navmeshes: %d", total_stored_start);

	return Plugin_Stop;
}

// asdf TO DO this runs very frequently, find a better way.
bool use_pressed = false;
bool reload_pressed = false;
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse)
{
    if (!g_bCvarAllow || !IsValidClient(client) || IsFakeClient(client)) return;
	if(impulse==100) toggle_ZM_vision(client);	
	else if (client==zm_client)
	{
        	update_ZM_looktarget(true);
        	if (!use_pressed && (buttons&IN_USE)>0)
        	{
            	if (live_SI>0) ZMControlSI(zm_client,0);
            	else open_menu(zm_client,ZM_MENU_SPECIAL);
            	use_pressed = true;
        	}
        	else if (use_pressed && (buttons&IN_USE)<=0)
        	{
            	use_pressed = false;
        	}
        	
        	if (!reload_pressed && (buttons&IN_RELOAD)>0)
        	{
            	if (zm_menu_state==ZM_MENU_MAIN)
            	{
                	close_menus(client);
            	}
            	else open_menu(zm_client,ZM_MENU_MAIN);
            	reload_pressed = true;
        	}
        	else if (reload_pressed && (buttons&IN_RELOAD)<=0)
        	{
            	reload_pressed = false;
        	}
    	
	}
}

public void OnMapEnd()
{
	if (DEBUG) PrintToServer("[zm] OnMapEnd");
	g_iLockedDoor = INVALID_ENT_REFERENCE; // we don't know if there's gonna be a door next map
	ResetTimer();
	rain_entity = -1;
	snow_entity = -1;
	zm_stage = ZM_END;
	clients_in_server = false;
	update_EMS_HUD();
	
	// Clean up pre-computed data
    if (g_hObscuredList != null)
    {
       	delete g_hObscuredList;
       	g_hObscuredList = null;
    }
    if (g_hStartAreaList != null)
    {
    	delete g_hStartAreaList;
    	g_hStartAreaList = null;
    }
    g_bNavReady = false;
    lastdoor = -1;
    scope_changed = false;
    g_bMapStarted = false;
}

void ResetTimer()
{
 if (DEBUG) PrintToServer("[zm] ResetTimer");
 delete zm_timer;
}

public void OnConfigsExecuted()
{
    if (DEBUG) PrintToServer("[zm] OnConfigsExecuted");
	IsAllowed();
}

void evtRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	
	if (DEBUG) PrintToServer("[zm] evtRoundEnd");
	bool ZM_won = true;
	for( int i = 1; i <= MaxClients; i++ )
	{
		if(IsClientInGame(i) && !IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
	    
	    if (!IsClientInGame(i)) continue;
	    if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
		if ( IsPlayerAlive(i) && !L4D_IsPlayerIncapacitated(i)  ) 
		{
    		ZM_won = false;
		}
		
	}
	if (IsValidClientZM())
	{
    	if (ZM_won)
    	{
        	EmitSoundToClient(zm_client,SOUND_ZM_WIN);
        	PrintHintText(zm_client, "%t", "ZM win text");
        	char zm_name[MAX_NAME_LENGTH]; 
            GetClientName(zm_client,zm_name,sizeof(zm_name));
            PrintToChatAll("[zm] %t", "ZM won", zm_name);
    	}
    	QuitZM(zm_client,false); // InputKill prevention
	}
	g_iLockedDoor = INVALID_ENT_REFERENCE;
	saferoom_locked = false;
    if (ZM_finale_announced) ZM_finale_ended = true;
	ResetTimer();
	set_zm_stage(ZM_END,true);
	update_EMS_HUD();
	
}

void evtRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (DEBUG) PrintToServer("[zm] evtRoundStart");
	g_iLockedDoor = INVALID_ENT_REFERENCE;
	saferoom_locked = false;
	zm_new_round();
}

void Event_SurvivalRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bCvarAllow) return;
	if (DEBUG) PrintToServer("[zm] Event_SurvivalRoundStart");
    manual_panic = false;
    start_zm_round();
    zm_update(zm_timer);
}

public void L4D_OnFinishIntro()
{
    if (DEBUG) PrintToServer("[zm] L4D_OnFinishIntro");
    if (g_bCvarAllow && g_bLockSaferoom) freeze_team(false);
}

public Action L4D_OnMobRushStart()
{
    if (!g_bCvarAllow) return Plugin_Continue;
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (DEBUG) PrintToServer("[zm] L4D_OnMobRushStart %d", pending_mob);
    update_director_script_scopes();
    return Plugin_Stop;
}

public Action L4D_OnSpawnMob()
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return Plugin_Continue;
    int pending_mob = L4D2Direct_GetPendingMobCount();
    if (DEBUG) PrintToServer("[zm] L4D_OnSpawnMob %d", pending_mob);
    update_director_script_scopes();
    if (panic && !manual_panic && L4D2_IsGenericCooperativeMode())
    {
        t_last_panic = GetEngineTime();
        L4D2Direct_SetPendingMobCount(0);
    }
    
    return Plugin_Stop;
}

void IsAllowed()
{
	if (DEBUG) PrintToServer("[zm] IsAllowed");
	bool bCvarAllow = g_hCvarAllow.BoolValue;
    
    //int coop = L4D_IsCoopMode();
    //int generic_coop = L4D2_IsGenericCooperativeMode();
    //int survival = L4D_IsSurvivalMode();
    //int versus = L4D_IsVersusMode();
    //int gametype = L4D_GetGameModeType();
    //int controllable_zombies = L4D_HasPlayerControlledZombies();
    //PrintToServer("[zm] Gamemode checks: %d %d %d %d %d %d", coop, generic_coop, survival, versus, gametype, controllable_zombies);
    
    if ( L4D_HasPlayerControlledZombies() && bCvarAllow)
    {
        SetConVarInt(g_hCvarAllow,0);
        PrintToChatAll("[zm] %t", "ZM restrict notify");
        return;
    }
    
	if(!g_bCvarAllow && bCvarAllow)
	{
		g_bCvarAllow = true;

		HookEvent("round_start", evtRoundStart,		EventHookMode_PostNoCopy);
		HookEvent("survival_round_start",Event_SurvivalRoundStart,EventHookMode_PostNoCopy);
		HookEvent("round_end",				evtRoundEnd,		EventHookMode_Pre); //trigger twice in versus mode, one when all survivors wipe out or make it to saferom, one when first round ends (second round_start begins).
		HookEvent("map_transition", 		evtRoundEnd,		EventHookMode_Pre); //all survivors make it to saferoom, and server is about to change next level in coop mode (does not trigger round_end) 
		HookEvent("mission_lost", 			evtRoundEnd,		EventHookMode_Pre); //all survivors wipe out in coop mode (also triggers round_end)
		HookEvent("finale_vehicle_leaving", evtRoundEnd,		EventHookMode_Pre); //final map final rescue vehicle leaving  (does not trigger round_end)
	    //HookEvent("create_panic_event", PanicEventStarted,		EventHookMode_PostNoCopy);
	    //HookEvent("panic_event_finished", PanicEventFinished,	EventHookMode_PostNoCopy);
	    HookEvent("triggered_car_alarm", Event_TriggeredCarAlarm, EventHookMode_Post);
		HookEvent("player_death", evtPlayerDeath, EventHookMode_Post);
		HookEvent("player_incapacitated", evtPlayerIncap, EventHookMode_Post);
		HookEvent("player_team", evtPlayerTeam);
		HookEvent("finale_start", 			evtFinaleStart, EventHookMode_PostNoCopy); //final starts, some of final maps won't trigger
		HookEvent("finale_radio_start", 	evtFinaleStart, EventHookMode_PostNoCopy); //final starts, all final maps trigger
		HookEvent("gauntlet_finale_start", 	evtFinaleStart, EventHookMode_PostNoCopy); //final starts, only rushing maps trigger (C5M5, C13M4)
		HookEvent("player_spawn", evtPlayerSpawned);
		HookEvent("player_left_start_area", evt_ZM_start_imminent);
		HookEvent("player_left_checkpoint", evt_ZM_start_imminent);
		//HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
		HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post);
		HookEvent("finale_vehicle_ready", EvtFinaleEnding, EventHookMode_PostNoCopy);
		HookEvent("finale_vehicle_incoming", EvtFinaleEnding, EventHookMode_PostNoCopy);
		HookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		HookEvent("player_now_it", Event_PlayerBoomed, EventHookMode_Post);
		HookEvent("player_no_longer_it", Event_PlayerUnBoomed, EventHookMode_Post);
		HookEvent("finale_rush", EvtFinaleRush, EventHookMode_PostNoCopy);
		HookEvent("tank_spawn", EvtTankSpawn, EventHookMode_Post);
		//HookEvent("tank_killed", EvtTankKilled, EventHookMode_Post);
		
		HookEvent("player_hurt", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		HookEvent("heal_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		HookEvent("pills_used", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		HookEvent("revive_end", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		
		GetCvars();
		SetCvarsZM();
		
		if (g_dd_StartRangeCull) g_dd_StartRangeCull.Enable(Hook_Pre, StartRangeCull_Pre);
		if (g_hDTR_InputKill) g_hDTR_InputKill.Enable(Hook_Pre, DTR_CBaseEntity_InputKill);
		if (g_hDTR_InputKillHierarchy) g_hDTR_InputKillHierarchy.Enable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
        //if (g_dd_ChangeFinaleStage) g_dd_ChangeFinaleStage.Enable(Hook_Pre, ChangeFinaleStage_Pre);
	
		GameRules_SetProp("m_bChallengeModeActive", 1); // Enable the HUD drawing
		EMS_hud_ready = true;
		if (AllPlayerCount<=0) CountClients();
		if (AllPlayerCount>0) clients_in_server = true;
		
		update_menus();
		
        HookEntityOutput("info_director", "OnPanicEventFinished", OnDirectorOutputFired);
        HookEntityOutput("info_director", "OnCustomPanicStageFinished", OnDirectorOutputFired);
        HookEntityOutput("info_zombie_spawn", "OnSpawnTank", OnInfoZombieSpawnOutputFired);
        HookEntityOutput("commentary_zombie_spawner", "OnSpawnedZombieDeath", OnCommentarySpawnerOutputFired);
        
        //HookEntityOutput("info_goal_infected_chase", "Enable", OnChaseOutputFired);
        
        SetConVarInt(FindConVar("mp_restartgame"), 1);
        
        if (!g_bNavReady)
    	{
        	g_hObscuredList = new ArrayList(sizeof(PreCalcNav));
        	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
        	g_bNavReady = false;
        	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
    	}
    	
    	HookUserMessage(GetUserMessageId("PZDmgMsg"), OnPZDmgMsg, true);
    	HookUserMessage(GetUserMessageId("Damage"), OnPZDmgMsg, true);
    	
    	AddNormalSoundHook(SwapSound);
    	//HookUserMessage(GetUserMessageId("SendAudio"),OnSendAudio,true);
		
	}
    
	else if(g_bCvarAllow && !bCvarAllow)
	{
		OnPluginEnd();
		g_bCvarAllow = false;
		
		//Add unhooks here
		UnhookEvent("round_start", evtRoundStart,		EventHookMode_PostNoCopy);
		UnhookEvent("survival_round_start",Event_SurvivalRoundStart,EventHookMode_PostNoCopy);
		UnhookEvent("round_end",				evtRoundEnd,		EventHookMode_Pre); //trigger twice in versus mode, one when all survivors wipe out or make it to saferom, one when first round ends (second round_start begins).
		UnhookEvent("map_transition", 		evtRoundEnd,		EventHookMode_Pre); //all survivors make it to saferoom, and server is about to change next level in coop mode (does not trigger round_end) 
		UnhookEvent("mission_lost", 			evtRoundEnd,		EventHookMode_Pre); //all survivors wipe out in coop mode (also triggers round_end)
		UnhookEvent("finale_vehicle_leaving", evtRoundEnd,		EventHookMode_Pre); //final map final rescue vehicle leaving  (does not trigger round_end)
	    //UnhookEvent("create_panic_event", PanicEventStarted,		EventHookMode_PostNoCopy);
	    //UnhookEvent("panic_event_finished", PanicEventFinished,	EventHookMode_PostNoCopy);
	    UnhookEvent("triggered_car_alarm", Event_TriggeredCarAlarm, EventHookMode_Post);
		UnhookEvent("player_death", evtPlayerDeath, EventHookMode_Post);
		UnhookEvent("player_incapacitated", evtPlayerIncap, EventHookMode_Post);
		UnhookEvent("player_team", evtPlayerTeam);
		UnhookEvent("finale_start", 			evtFinaleStart, EventHookMode_PostNoCopy); //final starts, some of final maps won't trigger
		UnhookEvent("finale_radio_start", 	evtFinaleStart, EventHookMode_PostNoCopy); //final starts, all final maps trigger
		UnhookEvent("gauntlet_finale_start", 	evtFinaleStart, EventHookMode_PostNoCopy); //final starts, only rushing maps trigger (C5M5, C13M4)
		UnhookEvent("player_spawn", evtPlayerSpawned);
		UnhookEvent("player_left_start_area", evt_ZM_start_imminent);
		UnhookEvent("player_left_checkpoint", evt_ZM_start_imminent);
		//UnhookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
		UnhookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post);
		UnhookEvent("finale_vehicle_ready", EvtFinaleEnding, EventHookMode_PostNoCopy);
		UnhookEvent("finale_vehicle_incoming", EvtFinaleEnding, EventHookMode_PostNoCopy);
		UnhookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		UnhookEvent("player_now_it", Event_PlayerBoomed, EventHookMode_Post);
		UnhookEvent("player_no_longer_it", Event_PlayerUnBoomed, EventHookMode_Post);
		UnhookEvent("finale_rush", EvtFinaleRush, EventHookMode_PostNoCopy);
		UnhookEvent("tank_spawn", EvtTankSpawn, EventHookMode_Post);
		//UnhookEvent("tank_killed", EvtTankKilled, EventHookMode_Post);
		
		UnhookEvent("player_hurt", EvtPlayerHurt, EventHookMode_Post); // userid was hurt
		UnhookEvent("heal_success", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		UnhookEvent("pills_used", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		UnhookEvent("revive_end", EvtPlayerHeal, EventHookMode_Post); // subject was healed
		
		if (g_dd_StartRangeCull) g_dd_StartRangeCull.Disable(Hook_Pre, StartRangeCull_Pre);
		if (g_hDTR_InputKill) g_hDTR_InputKill.Disable(Hook_Pre, DTR_CBaseEntity_InputKill);
		if (g_hDTR_InputKillHierarchy) g_hDTR_InputKillHierarchy.Disable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
		//if (g_dd_ChangeFinaleStage) g_dd_ChangeFinaleStage.Disable(Hook_Pre, ChangeFinaleStage_Pre);
		
		for( int i = 1; i <= MaxClients; i++ )
    	{
    		if(IsClientInGame(i))
    		{
        		L4D2_RemoveEntityGlow(i);
        		L4D2_RemoveEntityGlow_Color(i); //
        		if (!IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
    		}
    	}
		
		if (EMS_hud_ready)
        {
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM);
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TIMER);
            GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM_HINT);
        }
		EMS_hud_ready = false;
		
        UnhookEntityOutput("info_director", "OnPanicEventFinished", OnDirectorOutputFired);
        UnhookEntityOutput("info_director", "OnCustomPanicStageFinished", OnDirectorOutputFired);
        UnhookEntityOutput("info_zombie_spawn", "OnSpawnTank", OnInfoZombieSpawnOutputFired);
        UnhookEntityOutput("commentary_zombie_spawner", "OnSpawnedZombieDeath", OnCommentarySpawnerOutputFired);
        
        //UnhookEntityOutput("info_goal_infected_chase", "Enable", OnChaseOutputFired);
        
		SetConVarInt(FindConVar("mp_restartgame"), 1);
		
		UnhookUserMessage(GetUserMessageId("PZDmgMsg"), OnPZDmgMsg, true);
		UnhookUserMessage(GetUserMessageId("Damage"), OnPZDmgMsg, true);
		
		RemoveNormalSoundHook(SwapSound);
		//UnhookUserMessage(GetUserMessageId("SendAudio"),OnSendAudio,true);
		
	}

	
}

public Action SwapSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
                    	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
                    	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    //PrintToServer("[zm] %s", sample);
    if (force_started && zm_stage<ZM_STARTED)
    {
        if (StrContains(sample,"survivor",false)!=-1 && StrContains(sample,"voice",false)!=-1 && StrContains(sample,"world",false)!=-1)
        {
            if (DEBUG) PrintToServer("[zm] Muting survivor");
            return Plugin_Handled;
        }
    }
//    //PrintToServer("[zm] SwapSound %d %s %s", entity, sample, soundEntry);
//    switch (sample[0])
//    {
//        case 'p':
///        {
//            if (strcmp(sample,"player/survivor/voice/mechanic/dlc1_communitye20.wav",false)==0)
//            {
//                PrintToServer("Swapping Ellis sound");
//                sample = SOUND_ELLIS_ZM;
//                return Plugin_Changed;
//            }
//            else if (strcmp(sample,"player/survivor/voice/Manager/TakeSubMachineGun03.wav",false)==0)
//            {
//                PrintToServer("Swapping Louis sound");
//                sample = SOUND_LOUIS_ZM;
//                return Plugin_Changed;
//            }
//        }
//    }
    return Plugin_Continue;
}

//Action OnSendAudio(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
//{
//    PrintToServer("[zm] OnSendAudio");
//    return Plugin_Continue;
//} 

// Hide hit messages for ZM
Action OnPZDmgMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    if (!g_bCvarAllow || !IsValidClientZM()) return Plugin_Continue;
    BfReadByte(msg);
    int userid = BfReadShort(msg);
    //PrintToServer("[zm] OnPZDmgMsg %d %d", userid, zm_client_userid);
    if (zm_client_userid==userid) return Plugin_Handled;
    return Plugin_Continue;
} 

public MRESReturn DHook_Fog_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bCvarAllow) return MRES_Ignored;
	check_fog_distance();
	CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
	return MRES_Ignored;
}

public MRESReturn DHook_Director_AcceptInput(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	//if (!g_bCvarAllow || zm_stage!=ZM_STARTED || L4D_IsSurvivalMode()) return MRES_Ignored;
	if (!g_bCvarAllow) return MRES_Ignored;
	
	char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	if (DEBUG) PrintToServer("[zm] info_director accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	if (strcmp(inputName,"ForcePanicEvent")==0)
	{
	   if (zm_stage<ZM_STARTED) survival_activated=true;
	   // Called by ZM -- do nothing
	   if (activator==-1 && caller==-1 && actionId==0)
	   {
        	   manual_panic = true;
        	   return MRES_Ignored;
	   }
	   
	   if (panic && manual_panic) bank += g_iPanicCost;
	   manual_panic = false;
	   update_panic();
	   return MRES_Ignored;
	}
	
	if (strcmp(inputName,"PanicEvent")==0 || strcmp(inputName,"ScriptedPanicEvent")==0)
	{
        	if (panic && manual_panic) bank += g_iPanicCost;
        	manual_panic = false;
        	if (zm_stage<ZM_STARTED) survival_activated=true;
        	update_panic();
	}
	
	if (survival_activated && L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && !IsValidClientZM())
	{
        	PrintToChatAll("[zm] %t", "Start delay notify");
        	hReturn.Value = true;
        	return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

MRESReturn StartRangeCull_Pre(int entity)
{
	if (DEBUG) PrintToServer("[zm] StartRangeCull_Pre");
	if (g_bCvarAllow && zm_stage<ZM_STARTED) return MRES_Supercede;
	return MRES_Ignored;
}

MRESReturn DTR_CBaseEntity_InputKill(int pThis)
{
	if (pThis==zm_client && IsValidClientZM()) 
	{
	    PrintToServer("[zm] CBaseEntity_InputKill %d -> MRES_Supercede", pThis);
    	return MRES_Supercede;
	}
	
    return MRES_Ignored;
	
}

MRESReturn DTR_CBaseEntity_InputKillHierarchy(int pThis)
{
	if (pThis==zm_client && IsValidClientZM()) 
	{
	    PrintToServer("[zm] CBaseEntity_InputKillHierarchy %d -> MRES_Supercede", pThis);
    	return MRES_Supercede;
	}
	
	return MRES_Ignored;
	
}

public void OnPluginEnd()
{
    if (DEBUG) PrintToServer("[zm] OnPluginEnd");
    if (IsValidClientZM()) ChangeClientTeam(zm_client,TEAM_SURVIVOR);
    zm_client = -1;
    if (saferoom_locked) saferoom_lock(false);
    ResetTimer();
    ResetCvars();
}

public Action EvtFinaleEnding(Handle hEvent, char[] Name, bool dontBroastcast)
{
    if (DEBUG) PrintToServer("[zm] EvtFinaleEnding");
    if (ZM_finale_announced) ZM_finale_ended = true;
    else PrintToServer("[zm] Finale ending before it started???");
    return Plugin_Continue;
}

void Event_TriggeredCarAlarm(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow) return;
    if (DEBUG) PrintToServer("[zm] Event_TriggeredCarAlarm");
    if (zm_stage==ZM_STARTED)
    {
        bank += g_iBonusCarAlarm;
        PrintToChatAll("[zm] %t", "Car alarm notify", g_iBonusCarAlarm);
        if (!panic)
        {
            manual_panic=true;
            toggle_panic(true,true,true); // free panic!
        }
        else
        {
            bank += g_iPanicCost;
            t_last_panic = GetEngineTime();
        }
    }
    
    int victim = GetClientOfUserId(event.GetInt("userid"));
    spawn_free_angry_zombies(victim,50);
}

void Event_PlayerActivate(Event event, char[] name, bool bDontBroadcast)
{
    if (DEBUG) PrintToServer("[zm] Event_PlayerActivate");
    if (g_bCvarAllow)
    {
        if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
        int client = GetClientOfUserId(event.GetInt("userid"));
        arr_hp[client] = -1;
        arr_biled[client] = false;
        if (IsValidClient(client) && !IsFakeClient(client))
           clients_in_server = true;
    }
}


void evtPlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
    if (DEBUG) PrintToServer("[zm] evtPlayerSpawned");
    
    if (g_bCvarAllow)
    {
    
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
       if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
   	   int client = GetClientOfUserId(event.GetInt("userid"));
   	   arr_biled[client] = false;
   	   arr_hp[client] = -1;
   	   if (g_bLockSaferoom && L4D_IsInIntro()>0)
   	   {
       	   if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client))
       	      freeze_player(client);
   	   }
   	  
    }
}

void EvtPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (GetClientTeam(client)==TEAM_SURVIVOR && hp_timers[client]==INVALID_HANDLE)
        hp_timers[client] = CreateTimer(0.1,UpdateSurvivorGlow,client,TIMER_FLAG_NO_MAPCHANGE);
}

void EvtPlayerHeal(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("subject"));
	if (GetClientTeam(client)==TEAM_SURVIVOR && hp_timers[client]==INVALID_HANDLE)
	{
    	hp_timers[client] = CreateTimer(0.1,UpdateSurvivorGlow,client,TIMER_FLAG_NO_MAPCHANGE);
	}
}

void evtPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (DEBUG) PrintToServer("[zm] evtPlayerTeam");
	if (g_bCvarAllow)
    {
       if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
       int client = GetClientOfUserId(event.GetInt("userid"));
       arr_hp[client] = -1;
       arr_biled[client] = false;
       if (zm_client==client)
       {
   	      if (GetClientTeam(zm_client)==TEAM_SURVIVOR)
   	      {
   	         update_t_zm_activity(0.0); // instantly starts printing the "no ZM" message
   	         QuitZM(zm_client);
   	      }
   	   }
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
    }
}

void evt_ZM_start_imminent(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvarAllow || L4D_IsSurvivalMode()) return;
    if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
    //PrintToServer("[zm] evt_ZM_start_imminent");
    if (zm_stage<ZM_STARTED)
    {
        int client = GetClientOfUserId(event.GetInt("userid"));
        if (!IsValidClient(client)) return;
        if (!IsPlayerAlive(client)) return;
        if (GetClientTeam(client)!=TEAM_SURVIVOR) return;
        if (client==zm_client) return;
        zm_update(zm_timer); // runs can_zm_start()
        float pos[3];
        GetClientAbsOrigin(client,pos);
        Address temp_navArea = L4D_GetNearestNavArea(pos,500.0,true,false,true,TEAM_SURVIVOR);
        if (zm_can_start && !navArea_validStart(temp_navArea) && IsValidClientZM()) start_zm_round();
        else if (g_bLockSaferoom && saferoom_locked && L4D_IsInIntro()<=0)
        {
            tp_survivor_start(client);
            if (!IsFakeClient(client))
            {
                if (!IsValidClientZM()) PrintHintText(client, "%t", "No ZM notify");
                else PrintHintText(client, "%t", "Cannot start notify");
            }
        }
    }
}


public void OnClientPutInServer(int client)
{
	if(!g_bCvarAllow) return;
	if (DEBUG) PrintToServer("[zm] OnClientPutInServer");
	if (!IsFakeClient(client))
	{
    	t_last_join = GetEngineTime();
    	if (DEBUG) PrintToServer("[zm] t_last_join updated");
    	clients_in_server = true;
	}
	
	if (zm_stage==ZM_STARTED || zm_timer == INVALID_HANDLE) zm_update(zm_timer);
}

//void Event_PlayerDisconnect(Event event, char[] name, bool bDontBroadcast)
//{
//    if (DEBUG) PrintToServer("[zm] Event_PlayerDisconnect");
//    if (g_bCvarAllow)
//    {
//       if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
//       int client = GetClientOfUserId(event.GetInt("userid"));
//       arr_hp[client] = -1;
//       if (zm_client==client)
//       {
//   	      update_t_zm_activity(0.0); // instantly starts printing the "no ZM" message
//   	      QuitZM(client);
////   	      if (zm_stage<ZM_STARTED) can_zm_start();
//   	   }
//   	   
//   	   if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
////   	   
//    }
//}

public void OnClientDisconnect(int client)
{
	if (g_bCvarAllow)
	{
	   if (DEBUG) PrintToServer("[zm] OnClientDisconnect");
	   arr_hp[client] = -1;
	   if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
       if (zm_client==client)
       {
   	      update_t_zm_activity(0.0); 
   	      QuitZM(zm_client,0);
   	      if (zm_stage<ZM_STARTED) can_zm_start();
   	   } 
    }
}

// Refund zombie delete
public void OnEntityDestroyed(int entity)
{
    if ( !g_bCvarAllow || zm_stage<ZM_PREP || !IsValidEntity(entity) ) return;
    
	int max_health = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
	   //if (DEBUG) PrintToServer("[zm] OnEntityDestroyed MaxHP %d", max_health);
	if (max_health && max_health>0)
    {
	      int health = GetEntProp(entity,Prop_Data,"m_iHealth");
	      if (health<max_health) return;
	      
    	  static char class[32];
          GetEntityClassname(entity, class, sizeof(class));
          static char targetName[32];
          GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
          //PrintToServer("[zm] OnEntityDestroyed %d %s %s: %d/%d HP, ", entity, class, targetName, health, max_health);
           
          //PrintToServer("OnEntityDestroyed %s %s", class, targetName);
           
          if ( !(strcmp(targetName,"zm_unit")==0 || strcmp(class,"infected")==0) ) return;
       	  
       	  int bank_refund = 0;
       	  
       	  if (strcmp(class,"infected")==0)
       	  {
       	     //if (GetEntProp(entity,Prop_Send,"m_hasVisibleThreats")>0) return;
       	     if (strcmp(targetName,"zm_unit_common")==0 || strcmp(targetName,"zm_unit")==0)
       	     {
           	     bank_refund = g_iCostCommon;
           	     add_available_zombie(ZOMBIECLASS_COMMON,1);
       	     }
       	     else if (strcmp(targetName,"zm_unit_uncommon")==0)
       	     {
           	     bank_refund = g_iCostUncommon;
       	         add_available_zombie(ZOMBIECLASS_COMMON,1);
   	         }
   	      }
       	  else if (strcmp(class,"witch")==0)
       	  {
       	     // Figuring out if witch is stationary or moving
       	     bank_refund = -1;
       	     int m_nSequence = GetEntProp(entity,Prop_Data,"m_nSequence");
       	     if (m_nSequence==4 || m_nSequence==27)
       	     {
           	     bank_refund = g_iCostWitchStatic;
           	     if (DEBUG) PrintToServer("[zm] Refunding static witch");
       	     }
       	     else if (m_nSequence==10 || m_nSequence==11 || m_nSequence==2)
       	     {
           	     bank_refund = g_iCostWitchMoving;
           	     if (DEBUG) PrintToServer("[zm] Refunding moving witch");
       	     }
       	     if (bank_refund<0)
       	     {
           	     if (DEBUG) PrintToServer("[zm] Refunding cheapest witch");
           	     if (g_hCostWitchStatic<g_hCostWitchMoving) bank_refund=g_iCostWitchStatic;
           	     else bank_refund=g_iCostWitchMoving;
       	     }
       	     add_available_zombie(ZOMBIECLASS_WITCH,1);
       	  }
       	  else if (strcmp(class,"player")==0 && GetClientTeam(entity)==TEAM_INFECTED)
       	  {
           	 if (L4D_IsPlayerIncapacitated(entity)) return;
           	 int zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
             if (zClass<ZOMBIECLASS_SMOKER || zClass>ZOMBIECLASS_TANK || zClass==7) return;
             
             // Prevent refunds if ability is still on cooldown
             int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
             if (ability > 0 && IsValidEdict(ability))
             {
                 if ((GetEntPropFloat(ability, Prop_Send, "m_timestamp")-GetGameTime())>0.0) return;
             }
             
             if (GetEntProp(entity,Prop_Send,"m_hasVisibleThreats")>0) return;
             
             bank_refund = costs_SI[zClass];
             //// Prevent tanks from being refunded during finales and survival
             //if (zClass==ZOMBIECLASS_TANK)
             //{
             //    if ( ZM_finale_announced || L4D_IsSurvivalMode() ) bank_refund = 0;
             //}
             add_available_zombie(zClass,1);
       	  }
       	  else return;
       	  
       	  if (bank_refund>0)
       	  {
           	  bank += bank_refund;
           	  if (DEBUG) PrintToServer("OnEntityDestroyed %s refunded %d", class, bank_refund);
       	  }
 	       
    	   
    }
	
    
}





bool IsEntitySafe(int entity)
{
	if(entity == -1) return false;
	if(entity >= ENTITY_SAFER_LIMIT)
	{
		RemoveEntity(entity);
		return false;
	}
	return true;
}

GameData hGameData;
//GameData hGameData_l4dhooks;
void GetGameData()
{
	if (DEBUG) PrintToServer("[zm] GetGameData");
	hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	//hGameData_l4dhooks = LoadGameConfigFile("left4dhooks.l4d2");
	
	if( hGameData != null ) PrepSDKCall();
	else SetFailState("Unable to find l4d2_zombie_master.txt gamedata file.");
	
	delete hGameData;
	//delete hGameData_l4dhooks;
}



void PrepSDKCall()
{

	StartPrepSDKCall(SDKCall_Player);
    
	//find create bot signature
	Address replaceWithBot = GameConfGetAddress(hGameData, "NextBotCreatePlayerBot.jumptable");
	if (replaceWithBot != Address_Null && LoadFromAddress(replaceWithBot, NumberType_Int8) == 0x68) {
		// We're on L4D2 and linux
		PrepWindowsCreateBotCalls(replaceWithBot);
	}
	else
	{
		PrepL4D2CreateBotCalls();
		PrepL4D1CreateBotCalls();
	}

    g_dd_StartRangeCull = DynamicDetour.FromConf(hGameData, "l4d2_zombie_master::CTerrorPlayer::StartRangeCull");
	if (!g_dd_StartRangeCull) PrintToServer("[zm] Failed to create DynamicDetour StartRangeCull");
	//else PrintToServer("[zm] Created DynamicDetour l4d2_zombie_master::CTerrorPlayer::StartRangeCull");
    
    g_hDTR_InputKill = DynamicDetour.FromConf(hGameData, "l4d2_zombie_master::CBaseEntity::InputKill");
    if (!g_hDTR_InputKill) PrintToServer("[zm] Failed to create DynamicDetour InputKill");
    
    g_hDTR_InputKillHierarchy = DynamicDetour.FromConf(hGameData, "l4d2_zombie_master::CBaseEntity::InputKillHierarchy");
    if (!g_hDTR_InputKillHierarchy) PrintToServer("[zm] Failed to create DynamicDetour InputKillHierarchy");
    
    StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "Infected::AttackSurvivorTeam");
	hInfectedAttackSurvivorTeam = EndPrepSDKCall();
	
	int acceptInputOffset = GameConfGetOffset(hGameData, "CBaseEntity::AcceptInput");
	if (acceptInputOffset == -1)
	{
		PrintToServer("[zm] Failed to load \"CBaseEntity::AcceptInput\" offset.");
	}
	else
	{
	    g_DHook_AcceptInput = DHookCreate(acceptInputOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CharPtr);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_Object, 20);
	    DHookAddParam(g_DHook_AcceptInput, HookParamType_Int);
	}
	
	//if (hGameData_l4dhooks != null)
	//{
	//    StartPrepSDKCall(SDKCall_Raw);
    //	g_dd_ChangeFinaleStage = DynamicDetour.FromConf(hGameData_l4dhooks, "L4DD::CDirectorScriptedEventManager::ChangeFinaleStage");
    //    if (!g_dd_ChangeFinaleStage) PrintToServer("[zm] Failed to create DynamicDetour ChangeFinaleStage");
	//}

	delete hGameData;
	//delete hGameData_l4dhooks;
}

void LoadStringFromAdddress(Address addr, char[] buffer, int maxlength) {
	int i = 0;
	while(i < maxlength) {
		char val = LoadFromAddress(addr + view_as<Address>(i), NumberType_Int8);
		if(val == 0) {
			buffer[i] = 0;
			break;
		}
		buffer[i] = val;
		i++;
	}
	buffer[maxlength - 1] = 0;
}

Handle PrepCreateBotCallFromAddress(Handle hSiFuncTrie, const char[] siName) {
	Address addr;
	StartPrepSDKCall(SDKCall_Static);
	if (!GetTrieValue(hSiFuncTrie, siName, addr) || !PrepSDKCall_SetAddress(addr))
	{
		SetFailState("Unable to find NextBotCreatePlayer<%s> address in memory.", siName);
		return null;
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	return EndPrepSDKCall();
}

void PrepWindowsCreateBotCalls(Address jumpTableAddr) {
	Handle hInfectedFuncs = CreateTrie();
	// We have the address of the jump table, starting at the first PUSH instruction of the
	// PUSH mem32 (5 bytes)
	// CALL rel32 (5 bytes)
	// JUMP rel8 (2 bytes)
	// repeated pattern.

	// Each push is pushing the address of a string onto the stack. Let's grab these strings to identify each case.
	// "Hunter" / "Smoker" / etc.
	for(int i = 0; i < 7; i++) {
		// 12 bytes in PUSH32, CALL32, JMP8.
		Address caseBase = jumpTableAddr + view_as<Address>(i * 12);
		Address siStringAddr = view_as<Address>(LoadFromAddress(caseBase + view_as<Address>(1), NumberType_Int32));
		static char siName[32];
		LoadStringFromAdddress(siStringAddr, siName, sizeof(siName));

		Address funcRefAddr = caseBase + view_as<Address>(6); // 2nd byte of call, 5+1 byte offset.
		int funcRelOffset = LoadFromAddress(funcRefAddr, NumberType_Int32);
		Address callOffsetBase = caseBase + view_as<Address>(10); // first byte of next instruction after the CALL instruction
		Address nextBotCreatePlayerBotTAddr = callOffsetBase + view_as<Address>(funcRelOffset);
		//PrintToServer("Found NextBotCreatePlayerBot<%s>() @ %08x", siName, nextBotCreatePlayerBotTAddr);
		SetTrieValue(hInfectedFuncs, siName, nextBotCreatePlayerBotTAddr);
	}

	hCreateSmoker = PrepCreateBotCallFromAddress(hInfectedFuncs, "Smoker");
	if (hCreateSmoker == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateSmoker); return; }

	hCreateBoomer = PrepCreateBotCallFromAddress(hInfectedFuncs, "Boomer");
	if (hCreateBoomer == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateBoomer); return; }

	hCreateHunter = PrepCreateBotCallFromAddress(hInfectedFuncs, "Hunter");
	if (hCreateHunter == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateHunter); return; }

	hCreateTank = PrepCreateBotCallFromAddress(hInfectedFuncs, "Tank");
	if (hCreateTank == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateTank); return; }

	hCreateSpitter = PrepCreateBotCallFromAddress(hInfectedFuncs, "Spitter");
	if (hCreateSpitter == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateSpitter); return; }

	hCreateJockey = PrepCreateBotCallFromAddress(hInfectedFuncs, "Jockey");
	if (hCreateJockey == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateJockey); return; }

	hCreateCharger = PrepCreateBotCallFromAddress(hInfectedFuncs, "Charger");
	if (hCreateCharger == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateCharger); return; }

	delete hInfectedFuncs;
}

void PrepL4D2CreateBotCalls() {
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateSpitter))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSpitter); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateSpitter = EndPrepSDKCall();
	if (hCreateSpitter == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSpitter); return; }

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateJockey))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateJockey); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateJockey = EndPrepSDKCall();
	if (hCreateJockey == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateJockey); return; }

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateCharger))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateCharger); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateCharger = EndPrepSDKCall();
	if (hCreateCharger == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateCharger); return; }
}

void PrepL4D1CreateBotCalls() 
{
	bool bLinuxOS = hGameData.GetOffset("OS") != 0;
	if(bLinuxOS)
	{
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateSmoker))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSmoker); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateSmoker = EndPrepSDKCall();
		if (hCreateSmoker == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSmoker); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateBoomer))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateBoomer); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateBoomer = EndPrepSDKCall();
		if (hCreateBoomer == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateBoomer); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateHunter))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateHunter); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateHunter = EndPrepSDKCall();
		if (hCreateHunter == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateHunter); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateTank))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateTank); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateTank = EndPrepSDKCall();
		if (hCreateTank == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateTank); return; }
	}
	else
	{
		Address addr;

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateSmoker_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSmoker_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateSmoker = EndPrepSDKCall();
		if(hCreateSmoker == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSmoker_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateBoomer_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateBoomer_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateBoomer = EndPrepSDKCall();
		if(hCreateBoomer == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateBoomer_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateHunter_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateHunter_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateHunter = EndPrepSDKCall();
		if(hCreateHunter == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateHunter_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateTank_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateTank_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateTank = EndPrepSDKCall();
		if(hCreateTank == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateTank_L4D1); return; }
	}
}

Address RelativeJumpDestination(Address p)
{
	int offset = LoadFromAddress(p, NumberType_Int32);
	return p + view_as<Address>(offset + 4);
}

// Made for the Knockout.chat community
// Plugin authors: gvazdas, zyiks
// HUGE THANKS TO TESTERS: IronBar, ngh, Hatsune Miku Fan, Raykeno, Lil Ole Fella, ShaunOfTheLive, zyiks
// Chance, Skerion, Lett1, AGGA Lambo, AriesToffle, Shadowcat, Wicket
// HUGE THANKS for scripting help: HarryPotter, xerox8521, Forgetest, little_froy, Lux, Marttt, Bacardi
// HUGE THANKS TO Reagy and IronBar for hosting the Knockout Left 4 Dead 2 Server

// MASSIVE THANKS to authors of various L4D2 scripts used for reference:
// Marttt - nav_info
// Dragokas -- Chase() -- https://forums.alliedmods.net/showthread.php?t=321034