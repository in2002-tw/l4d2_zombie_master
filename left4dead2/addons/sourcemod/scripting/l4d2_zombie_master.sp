#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>

bool DEBUG = false;

// TO DO LIST:
// 1. Observer camera bugs after dying as Special
// 2. Prevent Survival start if no ZM
// 3. Gameplay balance - currently too hard for Survivors
// 4. Better easier to read zombie spawner visuals (done by zyiks, not implemented)
// 5. Gas station tornado (done by zyiks, not implemented)
// 6. Hooking all scripted panic events to toggle_panic + spawning free angry zombies
// 7. More models for Specials -- maybe l4d2_random_si_model is enough
// 8. Removing red dynamic light attached to ZM. Still appears sometimes.
// 9. Allowing ZM to see infected ladders
// 10. Fixing stuck zombies
// 11. Allowing ZM to see "obscured" navmeshes for easy spawns
// 12. Better navmesh integration - currently we are taking the highest possible z value of a nav mesh which can make the spawner appear super high above surfaces.
// 13. Add IsLocationFoggedToSurvivors check for spawner visibility
// 14. Zombie Master ticket system; give priority to players who didn't get to be ZM yet.
// 15. Performance bottlenecks.
// 16. Is there a way to prevent observers from being able to see the ZM info?
// 17. Improve spawner by searching for the nearest possible area that is valid for spawning zombies
// 18. JoinZM / QuitZM: delete zombie and saferoom door glows, readd zombie glows
// 19. Improve ZM experience: spawning zombies, traversing map, reading survivor flow etc
// 20. Glows are buggy - add hooks to dynamic ornaments, cleanup better, run cleanup after joinzm and quitzm
// 21. Survivor bots will sometimes teleport to ZM and fall to their death

#define PLUGIN_NAME			    "l4d2_zombie_master"
#define PLUGIN_VERSION 			"0.5.0 2026-01-12"
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

#define L4D2_TEAM_ALL -1
int g_iYesVotes;
int g_iNoVotes;
int g_iPlayersCount;
bool VoteInProgress;
bool CanPlayerVote[MAXPLAYERS+1];

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

#define SOUND_READY "ui/critical_event_1.wav"
#define SOUND_ZM_WIN "level/loud/gallery_win.wav"
#define SOUND_DOORSLAM "doors_switches_buttons/heavy_metal_stop1.wav" // asdf add this to force start
#define SOUND_BUG "common/bugreporter_failed.wav"
#define SOUND_INACTIVITY "ambient/levels/caves/cave_crickets_loop1.wav"
#define SOUND_START "ui/pickup_guitarriff10.wav"
#define SOUND_VISION "ui/menu_horror01.wav"
#define SOUND_PANIC_ON "npc/mega_mob/mega_mob_incoming.wav"
#define SOUND_PANIC_OFF "ui/pickup_secret01.wav"

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
ConVar infectedbots_dispose_cowards;
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
bool zm_deleted = false; //track if ZM just deleted something, for checks in removal of entity
bool zm_just_died = false; // tracking ZM team swap
bool EMS_hud_ready = false; // track whether HUD was initialized
int live_zm_tanks = 0; // track number of ZM spawned tanks for survival to function properly
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
     if (live_zombie_arr[ZOMBIECLASS_COMMON]>=count) return Plugin_Continue;
     
     count = count - live_zombie_arr[ZOMBIECLASS_COMMON];
     int target = L4D_GetHighestFlowSurvivor();
     spawn_free_angry_zombies(target,count);
     
     // There is a rare crash:
     // [DHOOKS] FATAL: Failed to find return address of original function. Check the arguments and return type of your detour setup.
     // When we call free_angry zombies when the mob spawn timer has JUST been reset (on the same tick).
     // Probably can be fixed by checking the mobspawntimer and delaying running this if timer is exactly at 0.0 elapsed time.
     
     return Plugin_Continue;  
}

public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	
	//if (strcmp(key, "MobMaxPending", false) == 0)
	//{
    //    	script_MobMaxPending = retVal;
    //    	return Plugin_Continue;
	//}
	
	if (strcmp(key, "CommonLimit", false) == 0)
	{
	    script_CommonLimit = retVal;
       	// Quieting Director...
       	//if (retVal<=0) zm_allow_spawns = false;
       	//else zm_allow_spawns = true;
       	
       	// try to include L4D2Direct_GetPendingMobCount()>0
       	
       	//if (retVal>0 && zm_stage==ZM_STARTED && !L4D_IsSurvivalMode() && !ZM_finale_announced)
       	//{
           	//CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
           	//if (MobSpawnTimer)
           	//{
               //float mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
               //float mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
               //int pending_mob = L4D2Direct_GetPendingMobCount();
               //if ( (mob_timer_left<=1.0 && mob_timer_elapsed>1.0 && mob_timer_elapsed<=g_fPanicDuration) || (pending_mob>0 && L4D_IsFinaleActive()) )
               //{
                   //PrintToServer("[zm] Mob event detected %f %f", mob_timer_left, mob_timer_elapsed);
                   //manual_panic=false;
                   //if (!panic)
                   //{
                   //    toggle_panic(true,true,true); // free panic!
                   //    CreateTimer(3.0, Timer_Free_Angry_Zombies, 50, TIMER_FLAG_NO_MAPCHANGE);
                  // }
                  // else t_last_panic = GetEngineTime();
                   
                  // if (pending_mob>0) L4D2Direct_SetPendingMobCount(0);
                   
              // }
               
          //  }
               
       	//}
       	
       	if (ZM_finale_announced || panic) retVal = 1;
       	else retVal = 0;
       	return Plugin_Handled;
	}
	
	//else if (strcmp(key, "MobMinSize", false) == 0)
	//{
       	//PrintToServer("[zm] MobMinSize %d", retVal);
       	//script_MobMinSize = retVal;
       	//retVal = 0;
     //  	return Plugin_Continue;
	//}
	
	//else if (strcmp(key, "MobMaxSize", false) == 0)
	//{
      	//PrintToServer("[zm] MobMaxSize %d", retVal);	
       	//retVal = 0;
       	//script_MobMaxSize = retVal;
     //  	return Plugin_Continue;
	//}
	
	return Plugin_Continue;
	
}

bool is_zm_spamming()
{
    float t_now = GetEngineTime();
    if ( (t_now-t_last_action)<=0.10 ) // typical tickrate is 30
    {
        update_hint("STOP SPAMMING");
        t_last_action = t_now;
        return true;
    }
    t_last_action = t_now;
    return false;
}

public void OnDirectorOutputFired(const char[] output, int activator, int caller, float delay)
{
    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
    PrintToServer("[zm] info_director output %s fired! %d %d %f", output, activator, caller, delay);
    
    // Scripted panic event - may last a while and need revival.
	if (strcmp(output,"OnCustomPanicStageFinished")==0)
	{
    	manual_panic = false;
    	update_panic();
	}
    if (!ZM_finale_announced) create_common_menu();
}

//public void OnChaseOutputFired(const char[] output, int activator, int caller, float delay)
//{
//    if (!g_bCvarAllow || zm_stage!=ZM_STARTED) return;
//    PrintToServer("[zm] chase output %s fired! %d %d %f", output, activator, caller, delay);
//    if (!ZM_finale_announced) create_common_menu();
//}

float commons_add = 0.0; // in case rate is very slow

int entref_control = INVALID_ENT_REFERENCE; // track the last special infected ZM looked at
int entref_delete = INVALID_ENT_REFERENCE; // track the last zombie ZM looked at

int g_iGlowList[MAXENTITIES] = {INVALID_ENT_REFERENCE, ...}; // track glow children of parent entities

// Prep time for coop only
ConVar g_hPrepTimeZM;
float g_fPrepTimeZM;
float t_zm_join = 0.0;

#define SAFEROOM_UNKNOWN 	-2
#define SAFEROOM_NO	 -1
int g_iLockedDoor = SAFEROOM_UNKNOWN;
int g_iFirstFlags = -1;
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
#define SOUND_ALLOWED "ui/menu_focus.wav"

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
	//LoadTranslations("l4d2_zombie_master.phrases");
    if (DEBUG) PrintToServer("[zm] OnPluginStart");
	GetGameData();
    
    // Commands -- all clients
    RegConsoleCmd("zm_vote", VoteZM, "zm_vote yes|no. Start a vote to enable/disable Zombie Master.");
	RegConsoleCmd("zm", JoinZM, "Become the Zombie Master; if already ZM, open main ZM menu.");
	RegConsoleCmd("zm_horde", ZM_Spawn_Horde, "zm_horde n type spawns n zombies; optional type: riot ceda clown mud road jimmy fallen (fallen is buggy)");
	RegConsoleCmd("zm_witch", ZM_Spawn_Witch, "zm_witch n spawns witch; n=0 static, n=1 moving");
	RegConsoleCmd("zm_smoker", ZM_Smoker, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_hunter", ZM_Hunter, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_jockey", ZM_Jockey, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_spitter", ZM_Spitter, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_boomer", ZM_Boomer, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_charger", ZM_Charger, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_tank", ZM_Tank, "Spawn SI where Zombie Master is pointing");
	RegConsoleCmd("zm_delete", ZM_Delete, "Delete last infected unit Zombie Master was looking at.");
	RegConsoleCmd("zm_delete_all", ZM_Delete_All, "Delete ALL zombies.");
	RegConsoleCmd("zm_delete_common", ZM_Delete_Commons, "Delete all common and uncommon infected.");
    RegConsoleCmd("zm_delete_specials", ZM_Delete_Specials, "Delete all special infected.");
    RegConsoleCmd("zm_delete_witches", ZM_Delete_Witches, "Delete all witches.");
	RegConsoleCmd("zm_quit", QuitZM_Command, "Give up Zombie Master and join Survivors.");
	RegConsoleCmd("zm_panic", ZMPanic, "Zombie horde rushes survivor who has progressed the most. Bank rate is reduced by 10.");
	RegConsoleCmd("zm_start", zm_start,"Allow survivors to leave safezone; if already so, force saferoom open and start round. Can be used by ZM and admins.");
	RegConsoleCmd("zm_followme", ZM_Chase_ZM, "Panic horde will chase Zombie Master.");
	RegConsoleCmd("zm_vision", ZM_Vision, "Toggle night vision for ZM. Or press the flashlight button.");
	RegConsoleCmd("zm_teleport", ZMTeleport, "ZM will teleport to farthest flow survivor.");
	RegConsoleCmd("zm_control", ZMControlSI, "ZM will take control of last special infected they were looking at. Or press the USE button.");
	RegConsoleCmd("zm_menu", ZM_Menu, "Open specific ZM menu: main common uncommon special boss cleanup other close. Use the RELOAD button to open the main menu.");
	
	// Commands -- admins only
	RegAdminCmd("zm_addbank", zm_addbank, ADMFLAG_ROOT,"Add zombux to zombie master bank. Admins only.");
    RegAdminCmd("zm_finale_next", zm_finale_advance, ADMFLAG_ROOT,"Trigger next finale stage. Admins only.");
    RegAdminCmd("zm_debug_player", zm_debug_player, ADMFLAG_ROOT, "Debug player state. Admins only.");
    RegAdminCmd("zm_debug_mob", zm_debug_mob, ADMFLAG_ROOT, "Debug mob state. Admins only.");
    
    g_hCvarDebug = CreateConVar("zm_debug", "0", "Print plugin debug info to server.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarDebug.AddChangeHook(ConVarChanged_Cvars);
    
	g_hCvarAllow = CreateConVar("zm_enable", "0", "0=Plugin off, 1=Plugin on.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
    
    g_hBankRateBase = CreateConVar("zm_bank_rate_base", "0.5", "Base ZM bank rate.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankRateBase.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankRatePlayer = CreateConVar("zm_bank_rate_player", "4.0", "Additional ZM bank rate per alive survivor.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankRatePlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitial = CreateConVar("zm_bank_initial", "500", "Initial ZM bank.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankInitial.AddChangeHook(ConVarChanged_Cvars);
    
    g_hPanicCost = CreateConVar("zm_panic_cost", "200", "Horde panic cost.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hPanicCost.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hPanicDuration = CreateConVar("zm_panic_duration", "30", "Horde panic duration.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hPanicDuration.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBankInitialPlayer = CreateConVar("zm_bank_initial_player", "400", "Additional initial ZM bank per extra player.",FCVAR_NOTIFY, true, 0.0, true, 1000000.0);
    g_hBankInitialPlayer.AddChangeHook(ConVarChanged_Cvars);
    
    g_hUpdateRate = CreateConVar("zm_updaterate", "0.25", "Update rate for periodic ZM checks.",FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_hUpdateRate.AddChangeHook(ConVarChanged_Cvars);
    
    g_hMaxCommons = CreateConVar("zm_maxcommons", "100", "ZM max number of common zombies.",FCVAR_NOTIFY, true, 0.0, true, 1000.0);
    g_hMaxCommons.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hSpawnMinDistance = CreateConVar("zm_spawndistance", "500", "ZM minimum spawn distance.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hSpawnMinDistance.AddChangeHook(ConVarChanged_Cvars);
    
    g_hCostBoomer = CreateConVar("zm_cost_boomer", "150", "ZM boomer cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostBoomer.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostSpitter = CreateConVar("zm_cost_spitter", "150", "ZM spitter cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
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
    
    g_hCostWitchStatic = CreateConVar("zm_cost_witch_static", "550", "ZM static witch cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostWitchStatic.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostWitchMoving = CreateConVar("zm_cost_witch_moving", "450", "ZM moving witch cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostWitchMoving.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostCommon = CreateConVar("zm_cost_common", "3", "ZM common infected cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hCostUncommon = CreateConVar("zm_cost_uncommon", "25", "ZM uncommon infected cost.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hCostCommon.AddChangeHook(ConVarChanged_Cvars_ZMenu);
    
    g_hBonusCarAlarm = CreateConVar("zm_bonus_car_alarm", "500", "Award ZM points for triggered car alarm.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hBonusCarAlarm.AddChangeHook(ConVarChanged_Cvars);
    
    g_hBonusFinaleStage = CreateConVar("zm_bonus_finale", "300", "ZM bank reward per player for advancing to the next Finale stage. Free tanks spawn automatically.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);
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
	
	g_hCommonRate = CreateConVar("zm_common_rate", "1.75", "Commons per second made available to spawn in the zombie pool.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hCommonRate.AddChangeHook(ConVarChanged_Cvars);
	
	g_hWitchCooldown = CreateConVar("zm_witch_cooldown", "60.0", "Witch cooldown.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hWitchCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hTankCooldown = CreateConVar("zm_tank_cooldown", "90.0", "Tank cooldown.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hTankCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hSpecialCooldown = CreateConVar("zm_special_cooldown", "20.0", "Cooldown for special infected spawns.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
	g_hSpecialCooldown.AddChangeHook(ConVarChanged_Cvars);
	
	g_hMinFinaleStage = CreateConVar("zm_min_finale_stage", "30.0", "Minimum gap between ZM rewards during Finale.",FCVAR_NOTIFY, true, 0.0, true, 10000000.0);
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
    
    if (menu_main==null)
    {
        create_main_menu();
        update_menus();
    }
    
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
    //else if (DEBUG) PrintToServer("[zm] Could not reopen.");
}

// MAIN MENU
void create_main_menu()
{		
	if (DEBUG) PrintToServer("[zm] create_main_menu");
	if (menu_main!=INVALID_HANDLE) CloseHandle(menu_main);
	menu_main = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),main_menu_Handler);
	menu_main.SetTitle("Zombie Master");
    
    AddMenuItem(menu_main, "0", "Common");
    AddMenuItem(menu_main, "1", "Special");
    AddMenuItem(menu_main, "2", "Boss");
    AddMenuItem(menu_main, "3", "Cleanup");
    AddMenuItem(menu_main, "4", "Other");
    AddMenuItem(menu_main, "5", "Teleport");

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
	menu_common.SetTitle("Common");
    
    char buffer[64]; 
    FormatEx(buffer,sizeof(buffer),"Common x10 %d", g_iCostCommon*10);
    AddMenuItem(menu_common, "0", buffer);
    FormatEx(buffer,sizeof(buffer),"Common x25 %d", g_iCostCommon*25);
    AddMenuItem(menu_common, "1", buffer);
    FormatEx(buffer,sizeof(buffer),"Common x50 %d", g_iCostCommon*50);
    AddMenuItem(menu_common, "2", buffer);
    AddMenuItem(menu_common, "3", "Uncommons");
    
    if (L4D_IsSurvivalMode() || ZM_finale_announced)
       AddMenuItem(menu_common, "4", "-");
    else
    {
        FormatEx(buffer,sizeof(buffer),"PANIC %d", g_iPanicCost);
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
            	case 0: {ZM_Horde(zm_client,10); open_menu(zm_client,ZM_MENU_COMMON);}
            	case 1: {ZM_Horde(zm_client,25); open_menu(zm_client,ZM_MENU_COMMON);}
            	case 2: {ZM_Horde(zm_client,50); open_menu(zm_client,ZM_MENU_COMMON);}
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
	menu_uncommon.SetTitle("Uncommon");
    
    char buffer[64]; 
    
    FormatEx(buffer,sizeof(buffer),"Riot %d", g_iCostUncommon);
    AddMenuItem(menu_uncommon, "0", buffer);
    FormatEx(buffer,sizeof(buffer),"CEDA %d", g_iCostUncommon);
    AddMenuItem(menu_uncommon, "1", buffer);
    FormatEx(buffer,sizeof(buffer),"Clown %d", g_iCostUncommon);
    AddMenuItem(menu_uncommon, "2", buffer);
    FormatEx(buffer,sizeof(buffer),"Mud %d", g_iCostUncommon);
    AddMenuItem(menu_uncommon, "3", buffer);
    FormatEx(buffer,sizeof(buffer),"Road %d", g_iCostUncommon);
    AddMenuItem(menu_uncommon, "4", buffer);
    AddMenuItem(menu_uncommon, "5", "-");
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
	menu_special.SetTitle("Special");
    
    char buffer[64];
    int occupied;
    int max;
    
    max = max_zombie_arr[ZOMBIECLASS_BOOMER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_BOOMER], live_zombie_arr[ZOMBIECLASS_BOOMER]);
    FormatEx(buffer,sizeof(buffer),"Boomer %d %d/%d", costs_SI[ZOMBIECLASS_BOOMER], occupied, max);
    AddMenuItem(menu_special, "0", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SPITTER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SPITTER], live_zombie_arr[ZOMBIECLASS_SPITTER]);
    FormatEx(buffer,sizeof(buffer),"Spitter %d %d/%d", costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
    AddMenuItem(menu_special, "1", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SMOKER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SMOKER], live_zombie_arr[ZOMBIECLASS_SMOKER]);
    FormatEx(buffer,sizeof(buffer),"Smoker %d %d/%d", costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    AddMenuItem(menu_special, "2", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_HUNTER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_HUNTER], live_zombie_arr[ZOMBIECLASS_HUNTER]);
    FormatEx(buffer,sizeof(buffer),"Hunter %d %d/%d", costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    AddMenuItem(menu_special, "3", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_JOCKEY];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_JOCKEY], live_zombie_arr[ZOMBIECLASS_JOCKEY]);
    FormatEx(buffer,sizeof(buffer),"Jockey %d %d/%d", costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
    AddMenuItem(menu_special, "4", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_CHARGER];
    occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_CHARGER], live_zombie_arr[ZOMBIECLASS_CHARGER]);
    FormatEx(buffer,sizeof(buffer),"Charger %d %d/%d", costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
    AddMenuItem(menu_special, "5", buffer);
    
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
	menu_boss.SetTitle("Boss");
    
    char buffer[64];
    
    FormatEx(buffer,sizeof(buffer),"Witch Moving %d", g_iCostWitchMoving);
    AddMenuItem(menu_boss, "0", buffer);
    FormatEx(buffer,sizeof(buffer),"Witch Static %d", g_iCostWitchStatic);
    AddMenuItem(menu_boss, "1", buffer);
    
    int max = max_zombie_arr[ZOMBIECLASS_TANK];
    int occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_TANK], live_zombie_arr[ZOMBIECLASS_TANK]);
    FormatEx(buffer,sizeof(buffer),"Tank %d %d/%d", costs_SI[ZOMBIECLASS_TANK], occupied, max);
    AddMenuItem(menu_boss, "2", buffer);
    
    if (jimmy_spawned) AddMenuItem(menu_boss, "3", "-");
    else
    {
        FormatEx(buffer,sizeof(buffer),"Jimmy Gibbs Jr %d", g_iCostUncommon);
        AddMenuItem(menu_boss, "3", buffer);
    }
    
    if (fallen_spawned) AddMenuItem(menu_boss, "4", "-");
    else
    {
        FormatEx(buffer,sizeof(buffer),"Fallen Survivor %d", g_iCostUncommon);
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
	menu_cleanup.SetTitle("Cleanup");
    
    AddMenuItem(menu_cleanup, "0", "Delete Target");
    AddMenuItem(menu_cleanup, "1", "Delete Commons");
    AddMenuItem(menu_cleanup, "2", "Delete Specials");
    AddMenuItem(menu_cleanup, "3", "Delete Witches");
    AddMenuItem(menu_cleanup, "4", "Delete All");
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
	menu_other.SetTitle("Other");
    
    if (zm_stage>=ZM_STARTED)
        AddMenuItem(menu_other, "0", "Control (USE)");
    else if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
        AddMenuItem(menu_other, "0", "Start Round");
    else 
        AddMenuItem(menu_other, "0", "-");
    
    AddMenuItem(menu_other, "1", "Toggle Rain");
    AddMenuItem(menu_other, "2", "Toggle Snow");
    AddMenuItem(menu_other, "3", "-");
    AddMenuItem(menu_other, "4", "Give Up");
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

public void update_hint(const char[] myString, any ...)
{
	char[] myFormattedString = new char[128];
	VFormat(myFormattedString,128,myString,2);
    FormatEx(ZM_hint,sizeof(ZM_hint),"%s",myFormattedString);
    if (IsValidClientZM()) update_EMS_HUD();
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
        TE_SetupBeamRingPoint(draw_pos,20.0,30.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,0.0,color,0,0);
        TE_SendToClient(zm_client);
        draw_pos = spawner_pos; draw_pos[2] += 20.0;
        TE_SetupBeamRingPoint(draw_pos,20.0,30.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,0.0,color,0,0);
        TE_SendToClient(zm_client);
        draw_pos = spawner_pos; draw_pos[2] -= 20.0;
        TE_SetupBeamRingPoint(draw_pos,20.0,30.0,g_iLaser,g_iHalo,0,0,g_fUpdateRate*2.0,2.0,0.0,color,0,0);
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
   
   int filter_client;
   if (IsValidClientZM()) filter_client = zm_client;
   else filter_client = 0;
   
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
               break;
           }
         }
   }
   
   float VecPos2[3];
   AddVectors(vecPos,{0.0,0.0,35.0},VecPos2);
   
   float VecPos3[3];
   AddVectors(vecPos,{-25.0,0.0,35.0},VecPos3);
   
   float VecPos4[3];
   AddVectors(vecPos,{25.0,0.0,35.0},VecPos4);
   
   float VecPos5[3];
   AddVectors(vecPos,{0.0,-25.0,35.0},VecPos5);
   
   float VecPos6[3];
   AddVectors(vecPos,{0.0,25.0,35.0},VecPos6);
   
   // Check line of sight with saferoom door before spawning frozen infected
   if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
   {
        float saferoom_pos[3];
        GetEntPropVector(g_iLockedDoor, Prop_Send, "m_vecOrigin", saferoom_pos);
        
        if (GetVectorDistance(saferoom_pos,vecPos)<fog_distance)
        {
        
            Handle trace = TR_TraceRayFilterEx(vecPos,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos2,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos3,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos4,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos5,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
                   delete trace;
                   return true;
                }
            }
            delete trace;
            
            trace = TR_TraceRayFilterEx(VecPos6,saferoom_pos,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,filter_client);
            if(TR_DidHit(trace))
            {
                int hit_entity = TR_GetEntityIndex(trace);
                if (hit_entity==g_iLockedDoor)
                {
                   if (hint) update_hint("Visible saferoom");
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
      if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
      {
      
        if (skipList[i]) continue;
        
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,vecPos))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos2))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos3))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos4))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos5))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
        if (L4D2_IsVisibleToPlayer(i,TEAM_SURVIVOR,3,0,VecPos6))
        {
           if (hint) update_hint("Visible survivors");
           return true;
        }
      }
   }
   return false;
}

// Find smallest distance to survivor. Check both ways in case survivor is about to appear here.
float min_distance_to_survivors(float vecPos[3])
{
   if (DEBUG) PrintToServer("[zm] min_distance_to_survivors");
   float min_distance = -1.0;
   float survivor_origin[3];
   float temp_dist1;
   float temp_dist2;
   for( int i = 1; i <= MaxClients; i++ )
   {
      if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i))
      {
        GetClientAbsOrigin(i,survivor_origin);
        temp_dist1 = L4D2_NavAreaTravelDistance(vecPos,survivor_origin,false);
        if (temp_dist1>=0.0 && (min_distance<0.0 || temp_dist1<min_distance)) min_distance = temp_dist1;
        if (zm_stage>=ZM_STARTED)
        {
            temp_dist2 = L4D2_NavAreaTravelDistance(survivor_origin,vecPos,false);
            if (temp_dist2>=0.0 && (min_distance<0.0 || temp_dist2<min_distance)) min_distance = temp_dist2;
        }
      }
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

bool can_ZM_spawn(bool witch = false, bool hint = true)
{
	if (DEBUG) PrintToServer("[zm] can_ZM_spawn");
	if (!IsValidClientZM()) return false;
	if (zm_stage>=ZM_END) return false;
	
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
        if (hint) update_hint("Bad location");
        update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED,false);
        return false;
    }
    
    // bools: anyz los checkground
    float check_dist = 200.0;
    if (witch) check_dist = 10.0;
    zm_spawner_navArea = L4D_GetNearestNavArea(vPos,check_dist,true,true,true,TEAM_INFECTED);
    if (zm_spawner_navArea)
    {
        zm_spawner_navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(zm_spawner_navArea);
        zm_spawner_navAttrFlags = L4D_GetNavArea_AttributeFlags(zm_spawner_navArea);
        float navSize[3], navOrigin[3], navCenter[3];
        L4D_GetNavAreaCenter(zm_spawner_navArea, navCenter);
        L4D_GetNavAreaPos(zm_spawner_navArea, navOrigin);
        L4D_GetNavAreaSize(zm_spawner_navArea, navSize);
        float z_max = navOrigin[2];
        if (z_max<navCenter[2]) z_max =  navCenter[2];
        z_max += navSize[2];
        if (z_max<vPos[2]) z_max = vPos[2];
        // Check if fully within navarea xy. If not, grab a random position
        if ( FloatAbs(vPos_spawner[0]-navCenter[0])>(navSize[0]/2.0) || FloatAbs(vPos_spawner[1]-navCenter[1])>(navSize[1]/2.0) )
        {
            L4D_FindRandomSpot(zm_spawner_navArea,vPos_spawner);
        }
        else vPos_spawner[2] = z_max;
    }
    else
    {
        vPos_spawner = vPos;
        zm_spawner_navSpawnAttrs = 0;
        zm_spawner_navAttrFlags = 0;
        if (!witch)
        {
            if (hint) update_hint("Bad location");
            update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED);
            return false;
        }
    }
    
    if (!nav_can_spawn_zombies(zm_spawner_navAttrFlags,zm_spawner_navSpawnAttrs,witch))
    {
        if (hint)
        {
            if (witch) update_hint("Witches illegal");
            else update_hint("Zombies illegal");
        }
        update_ZM_spawner(vPos,vPos_spawner,SPAWNER_BLOCKED);
        return false;
    }
    
    //if (IsObstructed(vPos_spawner))
    //{
    //    if (hint) update_hint("Not enough space");
    //	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
    //	return false;
    //}
    
    float min_distance = min_distance_to_survivors(vPos);
    if (min_distance>=0.0)
    {
        if (zm_spawner_navSpawnAttrs & NAV_SPAWN_NO_MOBS) min_distance /= 2.0; // 2x the usual survivor distance for areas marked "NO MOBS".
        else if (zm_stage<ZM_STARTED) min_distance *= 2.0; // if not started, players won't get swarmed so easily by initial wave
        
        if (min_distance<g_fSpawnMinDistance)
        {
            if (hint) update_hint("Too close %d", RoundFloat(min_distance));
            update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
            return false;
        }
    }
    
    // If obscured, we prevent line of sight from blocking spawns.
    bool obscured = ( (zm_spawner_navSpawnAttrs & NAV_SPAWN_OBSCURED) || (zm_spawner_navSpawnAttrs & NAV_SPAWN_IGNORE_VISIBILITY) );
    if (!obscured)
    {
        //if (L4D2_IsLocationFoggedToSurvivors(vPos_spawner)) PrintToServer("[zm] FoggedToSurvivors");
        if (can_any_alive_survivor_see(vPos_spawner,false))
        {
            if (!relocate_spawner_obscured(vPos_spawner))
            {
                update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
                if (hint) update_hint("Survivors visible");
                return false;
            }
        }
    }
    
    if (!zm_allow_spawns)
	{
    	if (hint) update_hint("Zombie spawns OFF");
    	update_ZM_spawner(vPos,vPos_spawner,SPAWNER_CONDITIONAL);
    	return false;
	}
    
    update_ZM_spawner(vPos,vPos_spawner,SPAWNER_ALLOWED);
    return true;
    
}

stock bool IsValidEntRef(int entity)
{
	if( entity && entity != -1 && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
		
}

void check_saferoom()
{
   
   if (L4D_IsSurvivalMode())
   {
       g_iLockedDoor = SAFEROOM_NO;
       return;
   }
   
   if (g_iLockedDoor==SAFEROOM_UNKNOWN && L4D_HasMapStarted())
   {
        if (DEBUG) PrintToServer("[zm] check_saferoom");
        g_iLockedDoor = L4D_GetCheckpointFirst();
        if (IsValidEntRef(g_iLockedDoor) && IsValidEntity(g_iLockedDoor))
        {
            g_iFirstFlags = GetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags");
        }
        else
        {
            if (DEBUG) PrintToServer("[zm] no saferoom, ignoring");
            g_iLockedDoor = SAFEROOM_NO;
            g_iFirstFlags = -1;
        }
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
    if (team==TEAM_SURVIVOR && g_iLockedDoor<0) saferoom_locked=state;
}

void saferoom_lock(bool state)
{
    if (DEBUG) PrintToServer("[zm] saferoom_lock");
    check_saferoom();
    
    if ( g_iLockedDoor<=0 || !IsValidEntRef(g_iLockedDoor) )
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
        AcceptEntityInput(g_iLockedDoor, "forceclosed");
        //AcceptEntityInput(g_iLockedDoor, "Lock");
        //SetEntProp(g_iLockedDoor, Prop_Send, "m_eDoorState", DOOR_STATE_CLOSING_IN_PROGRESS);
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", g_iFirstFlags|DOOR_FLAG_IGNORE_USE);
        saferoom_glow(true);
        saferoom_locked=true;
        if (DEBUG) PrintToServer("[zm] Locked saferoom");
    }
    else
    {
        SetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked",0);
        AcceptEntityInput(g_iLockedDoor, "Unlock");
        SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", g_iFirstFlags&~DOOR_FLAG_IGNORE_USE);
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

public void L4D2_OnChangeFinaleStage_Post()
{
    if (DEBUG) PrintToServer("[zm] L4D2_OnChangeFinaleStage_Post");
    if (L4D_IsSurvivalMode() || ZM_finale_ended || !ZM_finale_announced) return;
    
    CreateTimer(5.0, Timer_Free_Angry_Zombies, 25, TIMER_FLAG_NO_MAPCHANGE);
    
    float t_now = GetEngineTime();
    int add_bank = g_iBonusFinaleStage*g_iAliveSurvivors;
    if ((t_now-t_finale)>=g_fMinFinaleStage && (bank<(2*add_bank)) )
    {
        if (IsValidClientZM()) PrintHintText(zm_client, "Finale has advanced. Bank added.");
        bank += add_bank;
        if (bank>2*add_bank) bank = 2*add_bank;
        t_finale = t_now;
    }
    else if ( live_zombie_arr[ZOMBIECLASS_TANK]>0 || bank>=(2*add_bank) )
        t_finale = t_now;
}


// asdf fix when in prep stage this shouldn't trigger
void announce_finale()
{
    if (DEBUG) PrintToServer("[zm] announce_finale");
    if (L4D_IsSurvivalMode() || zm_stage<ZM_STARTED) return;
    if (!ZM_finale_announced)
    {
        if (IsValidClientZM()) PrintHintText(zm_client, "The Finale has started. Use up your bank to advance the stage.");
        PrintToChatAll("[zm] The Finale has started. Stages will advance when the ZM runs out of resources.");
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
        update_hint("Chasing %s", name);
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
    
    if (!panic)
    {
        toggle_panic(true,true,true);
    }
    else
    {
        t_last_panic = GetEngineTime();
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
        update_hint("Panic is automatic");
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
              update_hint("Can't afford panic");
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
       if (zm_stage>=ZM_STARTED && !panic && IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_PANIC_ON);
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
       if (!manual_panic && IsValidClientZM()) PrintHintText(zm_client, "Horde PANIC!");
       update_hint("Panic ON, rate reduced");
       actual_state = true;
       infected_panic();
       
    }
    else
    {
        if (DEBUG) PrintToServer("[zm] Panic OFF");
        manual_panic = false;
        if (zm_stage<ZM_STARTED) update_hint("Round not started");
        else update_hint("Panic OFF, rate normal");
        actual_state = false;
        disable_chase();
        if (zm_stage>=ZM_STARTED && panic && IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_PANIC_OFF);
        panic = false;
    }
    
    if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
    else SetConVarInt(FindConVar("director_panic_forever"), 0);
    create_common_menu();
    zm_update(zm_timer);
    
}

int CountCharInString(const char[] str, char c)
{
    int i;
    int count;

    while (str[i] != 0)
    {
        if (str[i++] == c)
            count++;
    }

    return count;
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

    if (IsValidClientZM() && zm_stage<ZM_END)
    {
        
        char panic_str[32];
        if (panic || ZM_finale_announced || (L4D_IsSurvivalMode() && zm_stage==ZM_STARTED) )
        {
            float panic_left;
            if (ZM_finale_announced || L4D_IsSurvivalMode()) panic_left = 0.0;
            else panic_left = g_fPanicDuration - (t_now - t_last_panic);
            if (panic_left<=0.0) panic_str = "Panic ON";
            else FormatEx(panic_str,sizeof(panic_str),"Panic ON %.1f", panic_left);
        }
        else panic_str = "Panic OFF";
        
        // ZM INFO
        int occupied_SI = get_occupied_units(max_SI,available_SI,live_SI);
        int occupied_commons = get_occupied_units(max_zombie_arr[ZOMBIECLASS_COMMON],available_zombie_arr[ZOMBIECLASS_COMMON],live_zombie_arr[ZOMBIECLASS_COMMON]);
        int occupied_witches = get_occupied_units(max_zombie_arr[ZOMBIECLASS_WITCH],available_zombie_arr[ZOMBIECLASS_WITCH],live_zombie_arr[ZOMBIECLASS_WITCH]);
        FormatEx(g_sData_HUD_ZM_Text,sizeof(g_sData_HUD_ZM_Text),"Bank %d (%.1f)\n%s\nCommon %d/%d\nSpecials %d/%d\nWitches %d/%d",
                 bank,bank_rate,
                 panic_str,
                 occupied_commons,max_zombie_arr[ZOMBIECLASS_COMMON],
                 occupied_SI,max_SI,
                 occupied_witches,max_zombie_arr[ZOMBIECLASS_WITCH]);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.008, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.1, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.126, HUD_ZM);
        TrimString(g_sData_HUD_ZM_Text);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026 * (CountCharInString(g_sData_HUD_ZM_Text, '\n') + 1), HUD_ZM);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s %s", g_sData_HUD_ZM_Text, g_sSpaces);
        g_sHUD_TextArray[HUD_ZM] = g_sBuffer;
        
        // ZM HINT
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.0, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.07, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.5, HUD_ZM_HINT);
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
       FormatEx(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),"There is no Zombie Master!");
    else
    {
        if (zm_stage>=ZM_STARTED || L4D_IsSurvivalMode()) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
        else
        {
            if (zm_can_start)
            {
                FormatEx(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),"Survivors can leave the safe zone!");
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
                
                FormatEx(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),"Round will start in %d seconds!", RoundFloat(t_biggest));
                
                
            }
        }
    }
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_TIMER_flags, _, HUD_TIMER);
    if (HUD_TIMER_flags!=HUD_FLAG_NOTVISIBLE)
    {
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.35, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.14, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.28, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026 * (CountCharInString(g_sData_HUD_TIMER_Text, '\n') + 1), HUD_TIMER);
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

float get_bank_rate()
{

 // Coop finale and Survival logic
 if (ZM_finale_announced || L4D_IsSurvivalMode() )
 {
    if (!L4D_IsSurvivalMode())
    {
        // Coop finale logic
        float t_now = GetEngineTime();
        if ( ZM_finale_announced && bank<=200 && zm_stage<ZM_END && !ZM_finale_ended && live_zombie_arr[ZOMBIECLASS_TANK]<=0 && !L4D2_IsTankInPlay()
        && ( (t_now-t_finale)>=g_fMinFinaleStage || (live_SI<=0 && live_zombie_arr[ZOMBIECLASS_COMMON]<10) )                       )
        {
           PrintToServer("[zm] Forcing next stage manually");
           L4D2_ForceNextStage();
        }
    }
    bank_rate = 0.0;
    return bank_rate;
 }
 
 // Coop logic
 float final_rate = g_fBankRateBase;
 if (g_iAliveSurvivors>0) final_rate += g_iAliveSurvivors*g_fBankRatePlayer;
    
 if (panic) final_rate /= 5.0;
 bank_rate = final_rate;
 return bank_rate;
 
}

int ent_control = -1; // track ZM controlled entity to prevent refunds

void zm_new_round()
{
    if (!g_bCvarAllow) return;
	
	roundcount += 1;
	
	saferoom_locked = false;
    
    if (DEBUG) PrintToServer("[zm] zm_new_round");
    if (DEBUG) PrintToServer("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
    if(L4D_IsSurvivalMode())
    {
        zm_allow_spawns = false;
        g_iLockedDoor = SAFEROOM_NO;
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
    
    zm_deleted = false;
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    if (infectedbots_dispose_cowards) SetConVarInt(infectedbots_dispose_cowards, 0);
    else if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
    
    set_zm_stage(ZM_NEWROUND,true);
    
    safezone_navAreaId = -1;
    
    ent_control = -1;
    
    zm_use_notify = false;
    
    int entity = -1;
	while ((entity = FindEntityByClassname(entity, "func_playerinfected_clip")) != -1)
	{	
		AcceptEntityInput(entity, "kill"); 
	}
	
	live_zm_tanks = 0;
	
	fallen_spawned = false;
	jimmy_spawned = false;
	
	zm_menu_state = ZM_MENU_CLOSED;
	create_main_menu();
	update_menus();
	
	if (!zm_timer) zm_update(zm_timer);
	else update_EMS_HUD();
	
	reset_available_zombies();
	
	// Listen to all info_director inputs
	if (g_DHook_AcceptInput)
	{
       	info_director = FindEntityByClassname(-1, "info_director");
       	if (IsValidEntity(info_director))
       	   DHookEntity(g_DHook_AcceptInput, true, info_director, INVALID_FUNCTION, DHook_AcceptInput_Post);
	}
	
	// Check fog visiblity to survivors
	fog_distance = FOG_DISTANCE;
	int fog_controller = -1;
	while( (fog_controller = FindEntityByClassname(fog_controller, "env_fog_controller")) != INVALID_ENT_REFERENCE )
	{
		bool enabled = GetEntProp(fog_controller, Prop_Data, "m_fog.enable") > 0;
		if (enabled)
		{
    		float fog_end = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.end");
    		float fog_farz = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.farz");
    		float maxdensity = GetEntPropFloat(fog_controller, Prop_Data, "m_fog.maxdensity");
    		if (DEBUG) PrintToServer("[zm] Found env_fog_controller %d", fog_controller);
    		if (DEBUG) PrintToServer("[zm] end farz maxdensity: %f %f %f", fog_end, fog_farz, maxdensity);
    		if (maxdensity>0.9)
    		{
        		if (fog_end<fog_distance) fog_distance = fog_end;
        		if (fog_farz<fog_distance) fog_distance = fog_farz;
    		}
    		
		}
	}
	PrintToServer("[zm] ZM spawner fog distance: %f", fog_distance);
	
	remove_all_ZM_glows();
	
	lastdoor = -1;
	
	update_director_script_scopes(false);
	scope_changed = false;
	//L4D2Direct_SetPendingMobCount(0);
    
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
    return Plugin_Continue;
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
        if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
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
	
	if (DEBUG) PrintToServer("[zm] CountClients");
	
	if (timer==clients_timer) clients_timer = INVALID_HANDLE;
	
	int allplayers = GetClientCount(false);
	if (allplayers<=0) return Plugin_Stop;
	
	int temp_SI = 0;
	int new_AllPlayerCount = 0;
	int new_AliveSurvivors = 0;
	int zClass;
	reset_live_zombie_arr(false,false,true);
	
	int last_valid_target = -1; // if only one SI on the field, auto select them for ZM control
	for (int i=1;i<=MaxClients;i++)
	{
		if (!IsClientConnected(i)) continue;
        if (!IsFakeClient(i)) new_AllPlayerCount += 1;
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		
		switch(GetClientTeam(i))
		{
			case TEAM_INFECTED:
			{
				if (zm_stage<ZM_PREP && IsFakeClient(i)) ForcePlayerSuicide(i); // fix The Passing bug where 2 tanks spawn in the safe zone
     		    else
     		    {
         		   temp_SI += 1;
         		   zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
         		   live_zombie_arr[zClass] += 1;
         		   last_valid_target = i;
         		   if (g_iGlowList[i]==INVALID_ENT_REFERENCE) CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(i), TIMER_FLAG_NO_MAPCHANGE);
     		    }
			}
			case TEAM_SURVIVOR:
			{
    			new_AliveSurvivors += 1;
			}
		}
		
		if (new_AllPlayerCount>=allplayers) break;
		
	}
	
	if (temp_SI==1 && IsValidEntity(last_valid_target)) entref_control = EntIndexToEntRef(last_valid_target);
	
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
	
	if (live_SI<=0 || live_zombie_arr[ZOMBIECLASS_TANK]<=0) live_zm_tanks = 0;
	
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
    if (L4D_IsFinaleActive()) update_hint("Try again later");
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
        TeleportEntity(zm_client, vTP, NULL_VECTOR, NULL_VECTOR);
    }

    return Plugin_Continue;
}

void transfer_SI_properties(int entity_new, float vOrigin[3], float vAngles[3], float vVelocity[3], int health, int fFlags, float timestamp_cooldown)
{
   if (!IsValidClient(entity_new)) return;
   
   TeleportEntity(entity_new,vOrigin,vAngles,vVelocity);
   SetEntProp(entity_new,Prop_Data,"m_iHealth",health);
   float cooldown_remaining = timestamp_cooldown - GetGameTime();
   if (cooldown_remaining<=0.0) cooldown_remaining = 0.0;
   else
   {
       // Prevent 3600 seconds cooldown bug
       int zClass = GetEntProp(entity_new, Prop_Send, "m_zombieClass");
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
   if ((fFlags & FL_ONFIRE)>0) IgniteEntity(entity_new, IGNITE_TIME);
}

bool already_replaced_SI = false; // track whether SI was already replaced. to prevent doubling and weird ping issues.

void remove_all_ZM_glows()
{
    for(int i = 0; i < sizeof(g_iGlowList); i++)
	{
		if (g_iGlowList[i]==INVALID_ENT_REFERENCE) continue;
		remove_ZM_glow(i);
	}
}

void remove_ZM_glow(int entity)
{
    if (!IsValidEntity(entity))
    {
        //PrintToServer("[zm] remove_ZM_glow %d skipped", entity);
        return; 
    }
    int ent_glow = g_iGlowList[entity];
    g_iGlowList[entity] = INVALID_ENT_REFERENCE;
    if ( IsValidEntRef(ent_glow) && HasEntProp(ent_glow, Prop_Send, "m_CollisionGroup") )
    {
       static char class[32];
       GetEntityClassname(ent_glow, class, sizeof(class));
       if (strcmp(class,"prop_dynamic_ornament")==0 && (GetEntProp(ent_glow, Prop_Send, "m_CollisionGroup")==0))
       {
   	       AcceptEntityInput(ent_glow, "kill");
   	       //PrintToServer("[zm] remove_ZM_glow %d killed prop_dynamic_ornament %d", entity, ent_glow);
   	       return;
       }
    }
    //PrintToServer("[zm] remove_ZM_glow %d did nothing", entity);
}

// Infected unit glow -- white
Action CreateZMGlow_white(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target);
    return Plugin_Continue;
}

// Saferoom door glow -- red
Action CreateZMGlow_red(Handle timer, int targetRef)
{
    int target = EntRefToEntIndex(targetRef);
    CreateZMGlow(target,true);
    return Plugin_Continue;
}

void CreateZMGlow(int target, bool red = false)
{
	if (target<0) return;
	if (g_iGlowList[target]!=INVALID_ENT_REFERENCE) remove_ZM_glow(target);
	if (!IsValidClientZM()) return;
	if (!IsValidEntity(target) || target==zm_client) return;
	
	if (!red && HasEntProp(target,Prop_Data,"m_iHealth"))
	{
    	if (GetEntProp(target,Prop_Data,"m_iHealth")<=0) return;
	}
	
	if (DEBUG) PrintToServer("[zm] CreateZMGlow");
	
	int glow = CreateEntityByName("prop_dynamic_ornament");
	if (!IsEntitySafe(glow)) return;
	
	SetEdictFlags(target, GetEdictFlags(target) | FL_EDICT_ALWAYS);
	
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
	int effects = GetEntProp(glow, Prop_Data, "m_fEffects");
	SetEntProp(glow, Prop_Data, "m_fEffects", effects | 0x001);
    g_iGlowList[target] = EntIndexToEntRef(glow);
	SDKHook(glow, SDKHook_SetTransmit, OnTransmitZM);
	
	//PrintToServer("[zm] CreateZMGlow %d %d %d", target, glow, g_iGlowList[target]);
	
}

Action ZMControlSI(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    
    if (is_zm_spamming()) return Plugin_Continue;
    
    ent_control = -1;
    //char name[32];
    
    // ZM wants to let go of special infected.
    if (IsPlayerAlive(zm_client) && GetClientTeam(zm_client)==TEAM_INFECTED && L4D2_GetSurvivorVictim(zm_client)<=0)
    {
        
        SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
        
        
        
        float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
        GetClientAbsOrigin(zm_client, vOrigin);
        GetClientEyeAngles(zm_client, vAngles); 
        GetClientEyePosition(zm_client, vEye);
        GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
        int health = GetEntProp(zm_client,Prop_Data,"m_iHealth");
        int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
        int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
        zm_use_notify = true;
        
        //get_zombieclass_name(zClass,name);
        //PrintToServer("[zm] Letting go of %s with %d HP", name, health);
        
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        
        SetEntProp(zm_client,Prop_Data,"m_iHealth",health-1); //prevent refund
        
        //ForcePlayerSuicide(zm_client);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        if (zClass == ZOMBIECLASS_TANK)
        {
            //L4D2Direct_TryOfferingTankBot(zm_client,false);
            //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
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
            if (IsValidEntity(bot)) transfer_SI_properties(bot,vOrigin,vAngles,vVelocity,health,fFlags,timestamp_cooldown);
            
        }
        
        zm_just_died = true;
        L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
        SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
        TeleportEntity(zm_client, vEye, vAngles, NULL_VECTOR);
        L4D_CleanupPlayerState(zm_client);
        remove_attached_lights(zm_client);
        JoinZM(zm_client,0);
        
        cleanup_bad_glows();
        
        return Plugin_Continue;
    }
    
    if (zm_stage<ZM_STARTED)
    {
        update_hint("Round not started");
        return Plugin_Continue;
    }
    
    update_ZM_looktarget(false);
    if (!IsValidEntRef(entref_control))
    {
        update_hint("Invalid target");
        return Plugin_Continue;
    }
    int entity = EntRefToEntIndex(entref_control);
    if (!IsValidEntity(entity) || !IsValidClient(entity) || GetClientTeam(entity)!=TEAM_INFECTED || !IsFakeClient(entity) || !IsPlayerAlive(entity)) 
    {
        update_hint("Invalid target");
        return Plugin_Continue;
    }
    
    // Takeover another special infected
    //native void L4D_TakeOverZombieBot(int client, int target);

    // Replaces the player with a bot
    //native void L4D_ReplaceWithBot(int client);

    // Kills the player. Teleports their view to a random survivor
    //native void L4D_CullZombie(int client);
    
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
         if (health<=0 || L4D_IsPlayerIncapacitated(entity)) return Plugin_Continue;
         int fFlags = GetEntProp(entity, Prop_Data, "m_fFlags");
         int zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
         
         //remove_ZM_glow(entity);
         
         float timestamp_cooldown = 0.0;
         int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
         if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
         
         zm_just_died = true;
         ChangeClientTeam(zm_client,TEAM_ZM);
         L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
         
         ent_control = entity;
         if (zClass==ZOMBIECLASS_TANK) L4D_ReplaceTank(entity,zm_client);
         else L4D_TakeOverZombieBot(zm_client,entity);
         L4D_CleanupPlayerState(zm_client);
         
         transfer_SI_properties(zm_client,vOrigin,vAngles,vVelocity,health,fFlags,timestamp_cooldown);
         
         already_replaced_SI = false;
         zm_use_notify = true;
         
         SDKHook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
         remove_attached_lights(zm_client);
         
         if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
         
         cleanup_bad_glows();
         
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
  	 else update_hint("Cannot control");
  	     

    
    return Plugin_Continue;
}

//float zm_deathPos[3];
Action OnTakeDamage_ZM(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
        
        if (!g_bCvarAllow || victim!=zm_client || GetClientTeam(victim)!=TEAM_INFECTED)
        {
            SDKUnhook(victim, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            return Plugin_Continue;
        }
        
        int health = GetEntProp(victim, Prop_Data, "m_iHealth");
        int new_health = health-RoundFloat(damage);
        //PrintToServer("[zm] OnTakeDamage_ZM %d %f -> %d", health, damage, new_health);
        
        if (new_health<=0 && IsPlayerAlive(victim))
        {
            
            //SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            if (panic_target==zm_client) panic_target = -1;
            
            if (!already_replaced_SI)
            {
            
                float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
                GetClientAbsOrigin(zm_client, vOrigin);
                GetClientEyeAngles(zm_client, vAngles); 
                GetClientEyePosition(zm_client, vEye);
                //zm_deathPos = vEye;
                GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
                int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
                int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
    
                float timestamp_cooldown = 0.0;
                int ability = GetEntPropEnt(zm_client, Prop_Send, "m_customAbility");
                if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
                live_SI -= 1;
                live_zombie_arr[zClass] -= 1;
                
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
                //SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
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
                
                int bot = ZM_Spawn_SI(zm_client,zClass,true,true,vOrigin,false);
                if (IsValidEntity(bot))
                {
                    remove_ZM_glow(bot);
                    //PrintToServer("[zm] OnTakeDamage_ZM replaced with bot");
                    transfer_SI_properties(bot,vOrigin,vAngles,vVelocity,health,fFlags,timestamp_cooldown);
                    SDKHooks_TakeDamage(bot,inflictor,attacker,damage,damagetype,weapon,damageForce,damagePosition,false);
                    //RequestFrame(OnNextFrame_UpdateDeathTime, GetClientUserId(bot));
                }
                
                //Cmd_FullUpdate(zm_client); // prevent camera stutter
                
                already_replaced_SI = true;
                remove_attached_lights(zm_client);
            
            }
            
            //L4D_SetClass(int client, int zombieClass)
            //L4D_BecomeGhost(int client);
            
            L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
            SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
            JoinZM(zm_client,0);
            L4D_CleanupPlayerState(zm_client);
            //RequestFrame(OnNextFrame_UpdateDeathTime, GetClientUserId(zm_client));
            
            ////L4D_RespawnPlayer(zm_client);
            //L4D_SetBecomeGhostAt(zm_client,0.0);
            
            return Plugin_Handled;
        }
        return Plugin_Continue;
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
    else update_hint("Panic must be ON");
    return Plugin_Continue;
}

void CountCommons(bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_COMMON]>0 || !fast || panic || ZM_finale_announced)
    {
        if (DEBUG) PrintToServer("[zm] CountCommons expensive");
        live_zombie_arr[ZOMBIECLASS_COMMON] = L4D_GetCommonsCount();
    }
}

//void lock_survival(state=true)
//{
//    if (!L4D_IsSurvivalMode()) return;
//}

void start_zm_round(bool play_sound = true)
{
 if (zm_stage<ZM_STARTED)
 {
     PrintToChatAll("[zm] Round has started!");
     if (IsValidClientZM()) PrintHintText(zm_client, "Round has started!");
     update_hint("Round started");
     if (play_sound) EmitSoundToAll(SOUND_START);
     CountClients();
 }
 zm_allow_spawns = true;
 set_zm_stage(ZM_STARTED);
 update_t_zm_activity();
 check_saferoom();
 saferoom_lock(false);
 //freeze_team(false);
 freeze_team(false,TEAM_INFECTED);
 saferoom_locked = false;
 //if (IsValidEntRef(g_iLockedDoor)) AcceptEntityInput(g_iLockedDoor, "Open");
 create_other_menu();
 scope_changed = false;
 update_director_script_scopes(false);
 scope_changed = false;
}

void update_ZM_looktarget(bool draw = true)
{
   if (!IsValidClientZM()) return;
   int target = GetClientAimTarget(zm_client, false);
   if (target<=0) return;
   if (target <= MaxClients && !IsFakeClient(target)) return;
   if (target && IsValidEntity(target) && target!=zm_client)
   {
         static char class[32];
 	     GetEntityClassname(target, class, sizeof(class));
 	     if ( strcmp(class,"infected")==0 || strcmp(class,"witch")==0 || (strcmp(class,"player")==0 && GetClientTeam(target)==TEAM_INFECTED) )
 	     {
       	     int entref_temp = EntIndexToEntRef(target);
       	     if (draw && entref_temp!=entref_delete)
       	     {
           	     float vOrigin[3];
           	     L4D_GetEntityWorldSpaceCenter(target,vOrigin);
           	     TE_SetupBeamRingPoint(vOrigin,40.0,0.1,g_iLaser,g_iHalo,0,0,1.0,2.0,0.0,color_unit_select,0,0);
                 TE_SendToClient(zm_client);
       	     }
       	     entref_delete = entref_temp;
       	     if (strcmp(class,"player")==0 && GetClientTeam(target)==TEAM_INFECTED) entref_control = entref_temp;
 	     }
   }
}

int old_scope0, old_scope1, old_scope2, old_scope3, old_scope4;
//int old_CommonLimit = -1;

// If scope changed, a panic might just start.
// Listen for next 10 seconds for a pending mob, or mobrush, or timer reset, or mobspawn

void update_director_script_scopes(bool warn = true)
{
    
    //bool something_changed = false;
    int pending_mob = L4D2Direct_GetPendingMobCount();
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    if (old_scope0!=scope0)
    {
        if (warn) PrintToServer("[zm] DirectorScript scope changed! mob %d", pending_mob); 
        old_scope0 = scope0;
        //something_changed = true;
    }
    
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    if (old_scope1!=scope1)
    {
        if (warn) PrintToServer("[zm] MapScript scope changed! mob %d", pending_mob); 
        old_scope1 = scope1;
        //something_changed = true;
    }
    
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    if (old_scope2!=scope2)
    {
        if (warn) PrintToServer("[zm] LocalScript scope changed! mob %d", pending_mob); 
        old_scope2 = scope2;
        //something_changed = true;
    }
    
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    if (old_scope3!=scope3)
    {
        if (warn) PrintToServer("[zm] ChallengeScript scope changed! mob", pending_mob); 
        old_scope3 = scope3;
        //something_changed = true;
    }
    
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    if (old_scope4!=scope4)
    {
        if (warn) PrintToServer("[zm] DirectorOptions scope changed! mob %d", pending_mob); 
        old_scope4 = scope4;
        //something_changed = true;
        scope_changed = true;
        t_scope_change = GetEngineTime();
    }
    
    //if (something_changed && zm_stage==ZM_STARTED)
    //{
        //int new_CommonLimit;
        //L4D_OnGetScriptValueInt("CommonLimit", new_CommonLimit);
        //if (new_CommonLimit!=old_CommonLimit)
        //{
        //    if (warn) PrintToServer("[zm] CommonLimit Changed %d -> %d", old_CommonLimit, new_CommonLimit); 
        //    old_CommonLimit = new_CommonLimit;
        //}
        
    //    if (script_CommonLimit>0 && pending_mob>0)
     //   {
      //      CountdownTimer MobSpawnTimer = L4D2Direct_GetMobSpawnTimer();
      //  	if (MobSpawnTimer)
      //  	{
      //          float mob_timer_left = CTimer_GetRemainingTime(MobSpawnTimer);
       //         float mob_timer_elapsed = CTimer_GetElapsedTime(MobSpawnTimer);
      //          if (mob_timer_elapsed<=1.0 && mob_timer_left<=0.0) update_panic();
       //     }
            
       // }
        
    //}
     
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
           		start_zm_round();
           		break;
       		}
       }
   }
   
   CountCommons();
   
   if (available_zombie_arr[ZOMBIECLASS_COMMON]<max_zombie_arr[ZOMBIECLASS_COMMON])
   {
       
       if (panic || ZM_finale_announced) available_zombie_arr[ZOMBIECLASS_COMMON]=max_zombie_arr[ZOMBIECLASS_COMMON];
       else
       {
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
       }
   }
   else commons_add = 0.0;
   
   t_last_update = t_now;
   
    // Check if witches were spotted to prevent refunds.
    float witch_pos[3];
    int entity = -1;
    int counted_witches = 0;
    while ( ((entity = FindEntityByClassname(entity, "witch")) != -1) )
    {
    	 if (IsValidEntity(entity))
    	 {
    	   
    	   if (g_iGlowList[entity]==INVALID_ENT_REFERENCE) CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
    	   
    	   counted_witches += 1;
           int max_health = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
           int health = GetEntProp(entity,Prop_Data,"m_iHealth");
           if (health>=max_health)
           {
               GetEntPropVector(entity, Prop_Send, "m_vecOrigin", witch_pos);
               if ( zm_stage<ZM_PREP || ( zm_stage>=ZM_STARTED && can_any_alive_survivor_see(witch_pos,false) ) )
               {
                   SetEntProp(entity,Prop_Data,"m_iHealth",health-1);
                   update_hint("Witch sighted, no refund");
               }
           }
    	 }
    	 
   }
   live_zombie_arr[ZOMBIECLASS_WITCH] = counted_witches; 
   
   if (panic && live_zombie_arr[ZOMBIECLASS_COMMON]>=10) SetConVarInt(FindConVar("director_panic_forever"), 1);
   else
   {
       SetConVarInt(FindConVar("director_panic_forever"), 0);
       if (panic && bank_rate>0.0) update_hint("PANIC is ON, rate is reduced!");
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
      
      update_ZM_looktarget();
      
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
                     PrintHintText(zm_client, "Type /zm in chat to spawn zombies.");
                     update_hint("Type /zm to open the menu");
                     zm_kick_notify=true;
                 }
                 else if ((t_now-t_zm_activity)>=g_fStopInactivity)
                 {
                         PrintHintText(zm_client, "You were removed from ZM due to inactivity.");
                         PrintToChatAll("[zm] The ZM was removed due to inactivity.");
                         update_t_zm_activity(t_now);
                         QuitZM(zm_client,false);
                 }
             
             }
             
          }
          else update_t_zm_activity(t_now);
      }
      
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
         if (zm_stage<ZM_END) PrintToChatAll("[zm] There is no Zombie Master. Type !zm to become ZM.");
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
       
       if (panic)
       {
           if (pending_mob>0)
           {
               if (MobSpawnTimer)
               {
                   if (mob_timer_left<=1.0 && mob_timer_elapsed<=g_fPanicDuration)
                   {
                       PrintToServer("[zm] Panic holding, pending mob %d, timer %f %f", pending_mob, mob_timer_left, mob_timer_elapsed);
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
           
           if (scope_changed && script_CommonLimit>0 && pending_mob>0 )
           {
                if (mob_timer_elapsed<=5.0 && mob_timer_left<=1.0)
                {
                   update_panic();
                   scope_changed = false;    
                }   
           }
           
           // Prevent "Incoming Attack" jingle from playing
           else if (MobSpawnTimer && mob_timer_left>0.0 && mob_timer_left<=10.0 && mob_timer_elapsed>10.0)
           {
              //CTimer_Reset(MobSpawnTimer);
              CTimer_Invalidate(MobSpawnTimer);
              CTimer_Start(MobSpawnTimer,3600.0); 
           } 
       }
       
       if ( scope_changed && (t_now-t_scope_change)>5.0 ) scope_changed = false;
   
   }
   else if (pending_mob>0)
   {
       CreateTimer(5.0, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
       L4D2Direct_SetPendingMobCount(0);
   }
   
   update_EMS_HUD();
   
   if (!zm_timer)
   {
      zm_timer = CreateTimer(g_fUpdateRate,zm_update,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
      return Plugin_Handled;
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
	infectedbots_dispose_cowards = FindConVar("l4d_infectedbots_dispose_cowards");
	if (infectedbots_dispose_cowards) SetConVarFlags(infectedbots_dispose_cowards, GetConVarFlags(infectedbots_dispose_cowards) & ~FCVAR_NOTIFY);
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
    
    //L4D_OnGetScriptValueInt(const char[] key, int &retVal)

    PrintToChat(client, "pending_mob: %d", pending_mob);
    PrintToChat(client, "finale_active: %d", finale_active);
    PrintToChat(client, "MobSpawnTimer RemainingTime ElapsedTime: %f %f", mob_timer_left, mob_timer_elapsed);
    PrintToChat(client, "DirectorScriptScope: %d %d %d %d %d", scope0, scope1, scope2, scope3, scope4);
    //PrintToChat(client, "CommonLimit %d MobMinSize %d MobMaxSize %d MobMaxPending %d", script_CommonLimit, script_MobMinSize, script_MobMaxSize, script_MobMaxPending);
    
    return Plugin_Continue;
}
 
 
public Action timerVoteCheck(Handle timer)
{
	if (VoteInProgress)
	{
		VoteInProgress = false;
		UpdateVotes();
	}
	return Plugin_Continue;
}
 
public void UpdateVotes()
{
	Event event = CreateEvent("vote_changed");
	event.SetInt("yesVotes", g_iYesVotes);
	event.SetInt("noVotes", g_iNoVotes);
	event.SetInt("potentialVotes", g_iPlayersCount);
	event.Fire();
 
	if ( ((g_iYesVotes+g_iNoVotes)>=g_iPlayersCount) || !VoteInProgress )
	{
		if (DEBUG) PrintToServer("[zm] voting complete!");
 
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				CanPlayerVote[i] = false;
			}
		}
 
		if ( g_iYesVotes>g_iNoVotes && g_iYesVotes>=(g_iPlayersCount/2.0) ) // asdf check that this is sane
		{
			BfWrite bf = UserMessageToBfWrite(StartMessageAll("VotePass"));
			bf.WriteByte(L4D2_TEAM_ALL);
			bf.WriteString("#L4D_TargetID_Player");
			bf.WriteString("Zombie Master Vote Passed");
			EndMessage();
			if (g_bCvarAllow) SetConVarInt(g_hCvarAllow,0);
			else SetConVarInt(g_hCvarAllow,1);
		}
		else
		{
			BfWrite bf = UserMessageToBfWrite(StartMessageAll("VoteFail"));
			bf.WriteByte(L4D2_TEAM_ALL);
			EndMessage();
		}
		
		VoteInProgress = false;
		
	}
}
 
public Action VoteZM(int client, int args)
{
	if (!VoteInProgress)
	{
        
        if (!L4D2_IsGenericCooperativeMode() && !L4D_IsSurvivalMode())
        {
            PrintToChat(client, "[zm] Zombie Master is available only for Coop and Survival.");
            return Plugin_Handled;
        }
        
    	BfWrite bf = UserMessageToBfWrite(StartMessageAll("VoteStart", USERMSG_RELIABLE));
     
    	bf.WriteByte(L4D2_TEAM_ALL);
    	bf.WriteByte(0);
    	bf.WriteString("#L4D_TargetID_Player");
    	if (g_bCvarAllow) bf.WriteString("End Zombie Master?");
    	else bf.WriteString("Start Zombie Master?");
    	bf.WriteString("Server");
    	EndMessage();
     
    	g_iYesVotes = 0;
    	g_iNoVotes = 0;
    	g_iPlayersCount = 0;
    	VoteInProgress = true;
     
    	for (int i = 1; i <= MaxClients; i++)
    	{
    		if (IsClientInGame(i) && !IsFakeClient(i))
    		{
    			CanPlayerVote[i] = true;
    			g_iPlayersCount ++;
    		}
    	}
    	
    	g_iYesVotes++;
     
    	UpdateVotes();
    	CreateTimer(10.0, timerVoteCheck, TIMER_FLAG_NO_MAPCHANGE);
    	
	}
	
	else if (VoteInProgress && CanPlayerVote[client])
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof arg);
        TrimString(arg);
        
		if (DEBUG) PrintToServer("[zm] Got vote %s from %i", arg, client);
 
		if (strcmp(arg,"yes",false)==0 || strcmp(arg,"1",false)==0  ) g_iYesVotes++;
		else g_iNoVotes++;
 
		UpdateVotes();
	}
	
	CanPlayerVote[client] = false;
 
	return Plugin_Handled;
	
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sGameMode[32];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	if(strcmp(g_sCvarMPGameMode, sGameMode, false) == 0) return;
	g_sCvarMPGameMode = sGameMode;
    
    if (DEBUG) PrintToServer("[zm] Gamemode: %s", g_sCvarMPGameMode);
    
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

void remove_attached_lights(int client)
{
    if (!IsValidClient(client)) return;
    int child = -1;
    while ((child = FindEntityByClassname(child, "*")) != -1)
    {
        if (IsValidEntity(child) && child > MaxClients && HasEntProp(child,Prop_Data,"m_pParent"))
        {
            if (GetEntPropEnt(child,Prop_Data,"m_pParent") == client)
            {
                char classname[64];
                GetEntityClassname(child, classname, sizeof(classname));
                if (strcmp(classname,"light_dynamic")==0)
                { 
                    //RemoveEntity(child);
                    AcceptEntityInput(child, "TurnOff");
                    AcceptEntityInput(child, "Kill");
                }
            }
        }
    }
}

Action JoinZM(int client, int args)
{
	if (!g_bCvarAllow) return Plugin_Continue;
	if (DEBUG) PrintToServer("[zm] JoinZM");
	if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
	if (client<0 || IsFakeClient(client)) return Plugin_Continue;
	if (zm_stage>=ZM_END) return Plugin_Continue;
	if (IsValidClientZM())
	{
       if (client==zm_client)
       {
          if (GetClientTeam(zm_client)!=TEAM_ZM)
          {
              zm_just_died = true;
              ChangeClientTeam(zm_client,TEAM_ZM);
              L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
          }
          else if (!IsPlayerAlive(zm_client))
          {
              SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
              SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6); //thanks to EHG https://forums.alliedmods.net/showthread.php?p=1080991
              SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
          }
          if (zm_timer==INVALID_HANDLE) zm_update(zm_timer);
          open_menu(zm_client);
       }
       else PrintHintText(client,"There is already a Zombie Master.");
       return Plugin_Continue;
    }
    
    if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client)) L4D_TakeOverBot(client);
    
    //remove_ZM_glow(lastdoor);
    remove_all_ZM_glows();
    
    zm_just_died = true;
    ChangeClientTeam(client,TEAM_ZM);
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    
    zm_client = client;
    zm_client_userid = GetClientUserId(zm_client);
    
    char name[MAX_NAME_LENGTH]; 
    GetClientName(client,name,sizeof(name));
    PrintToChatAll("[zm] %s is the Zombie Master.", name);
    SetEntProp(client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    PrintHintText(client, "You are the Zombie Master. Type /zm to open the menu.");
    update_hint("Type /zm to open the menu");
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
    
    remove_attached_lights(zm_client);
    
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
           if (print)
           {
               char name[MAX_NAME_LENGTH]; 
               GetClientName(client,name,sizeof(name));
               PrintToChatAll("[zm] %s is no longer the Zombie Master.", name);
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
           
       }
       //remove_ZM_glow(lastdoor);
       remove_all_ZM_glows();
       zm_client = -1;
       zm_client_userid = -1;
       zm_menu_state = ZM_MENU_CLOSED;
       cleanup_bad_glows(); 
    }
    if (IsValidClient(client))
    {
        if (GetClientTeam(client)!=TEAM_SURVIVOR)
        {
            ChangeClientTeam(client,TEAM_SURVIVOR);
            
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
			PrintHintText(zm_client, "Weather could not be adjusted.");
	
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
	else if (IsValidClientZM()) PrintHintText(zm_client, "Weather could not be adjusted.");
	
	return;
}

Action zm_finale_advance(int client, int args)
{
  if (DEBUG) PrintToServer("[zm] zm_finale_advance");
  if (L4D_IsFinaleActive()) L4D2_ForceNextStage();
  else PrintToServer("[zm] Finale is not active"); 
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



Action zm_start(int client, int args)
{
    if (DEBUG) PrintToServer("[zm] zm_start");
    if (!g_bCvarAllow) return Plugin_Continue;
    if (!L4D_HasMapStarted() || L4D_IsInIntro()>0) return Plugin_Continue;
    if (client==zm_client || CheckCommandAccess(client,"is_a_sm_admin",ADMFLAG_GENERIC,true))
    {
        if (zm_can_start || zm_stage>=ZM_STARTED)
        {
            if (zm_stage<ZM_STARTED && IsValidEntRef(g_iLockedDoor))
            {
                int random = GetRandomInt(1,5);
                switch (random)
                {
                    case 1: {EmitSoundToAll(SOUND_SCARY1,g_iLockedDoor);}
                    case 2: {EmitSoundToAll(SOUND_SCARY2,g_iLockedDoor);}
                    case 3: {EmitSoundToAll(SOUND_SCARY3,g_iLockedDoor);}
                    case 4: {EmitSoundToAll(SOUND_SCARY4,g_iLockedDoor);}
                    case 5: {EmitSoundToAll(SOUND_SCARY5,g_iLockedDoor);}
                    default: {EmitSoundToAll(SOUND_SCARY3,g_iLockedDoor);}
                }
                start_zm_round(false); // doesnt play sound
                if (IsValidEntRef(g_iLockedDoor)) AcceptEntityInput(g_iLockedDoor, "Open");
            }
            else start_zm_round(true); // plays sound
        }
        
        if (client==zm_client && !zm_can_start)
        {
            update_t_zm_activity();
            t_zm_join = t_zm_activity - g_fPrepTimeZM - 1.0;
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

Action ZM_Spawn_Horde(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    int count = 10;
    char type[32] = "common";
    if (args>0)
    {
        count=GetCmdArgInt(1);
        if (count<=0 || count>max_zombie_arr[ZOMBIECLASS_COMMON]) count = 10;
        if (args>1) GetCmdArg(2, type, sizeof(type));
	}
    ZM_Horde(client,count,type);
    return Plugin_Continue;
}

// TerrorNavArea bool IsBlocked(int team, bool affectsFlow)
// bool IsSpawningAllowed()
// TerrorNavArea float GetDistanceSquaredToPoint(Vector pos)

//  CTerrorPlayer GetClosestSurvivor(Vector origin, bool bIncludeIncap, bool bIncludeOnRescueVehicle)
// Returns the closest Survivor from the passed origin, if incapped Survivors are included in search, or on rescue vehicle.

// L4D2_CommandABot(int entity, int target, BOT_CMD type, float vecPos[3] = NULL_VECTOR)

void ZM_Horde(int client, int count=10, char type[64]="", bool angry = false)
{
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
	
	if (DEBUG) PrintToServer("[zm] ZM_Horde");
	
	if (is_zm_spamming()) return;
	
	CountCommons(false);
	if (live_zombie_arr[ZOMBIECLASS_COMMON]>=max_zombie_arr[ZOMBIECLASS_COMMON])
	{
    	update_hint("Limit reached");
        return;
	}
	
	if (!is_zombie_available_cooldown(ZOMBIECLASS_COMMON))
	{
    	update_hint("Cooldown active");
        return;
	}
	
	update_t_zm_activity();
	
	if ((live_zombie_arr[ZOMBIECLASS_COMMON]+count)>max_zombie_arr[ZOMBIECLASS_COMMON])
	   count = max_zombie_arr[ZOMBIECLASS_COMMON]-live_zombie_arr[ZOMBIECLASS_COMMON];
	
	if (count>available_zombie_arr[ZOMBIECLASS_COMMON]) count = available_zombie_arr[ZOMBIECLASS_COMMON];
	
	g_iEntities = GetEntityCountEx();
	if(count<=0 || (g_iEntities+count)>=ENTITY_SAFER_LIMIT)
	{
	   update_hint("Limit reached");
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
	if (set_model[0]!=0) temp_cost = g_iCostUncommon;
	else temp_cost = g_iCostCommon;
	
	if ((bank-temp_cost*count)<0)
	{
    	update_hint("OH GOD WE'RE GONNA BE POOR!!!!!");
    	return;
	}
    
	if (!can_ZM_spawn()) return;
    
	bank -= temp_cost*count;
	live_zombie_arr[ZOMBIECLASS_COMMON] += count;
	g_iEntities += count; // do not shrink this because director can teleport these zombies elsewhere on the map
	int spawned = 0;
	
	float randomPos[3];
	int ticktime = RoundToNearest(GetGameTime()/GetTickInterval()) + 5;
	for( int i = 0; i < count; i++  )
	{
		
		if (zm_spawner_navArea && count>1)
		{
    		L4D_FindRandomSpot(zm_spawner_navArea,randomPos);
    		if ( can_any_alive_survivor_see(randomPos,false) )
    		   randomPos=zm_spawner_pos;
		}
		else randomPos=zm_spawner_pos;
		
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
		
		if (zombie<=0)
    	{
            	if (DEBUG) PrintToServer("[zm] Spawn failed");
            	bank += temp_cost;
            	live_zombie_arr[ZOMBIECLASS_COMMON] -= 1;
        }
        else
        {
           spawned += 1;
           if ( (angry || panic || ZM_finale_announced) && hInfectedAttackSurvivorTeam ) SDKCall(hInfectedAttackSurvivorTeam,zombie);
        }
    }
		
	if (spawned<=0)
	{
    	update_hint("Spawn failed");
    	if (live_zombie_arr[ZOMBIECLASS_COMMON]<10) SetConVarInt(FindConVar("director_panic_forever"), 0);
	}
	else
	{
	    update_hint("Spawned %d Commons", spawned);
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
    return Plugin_Continue;
}
    

void ZM_Witch(int client,int witch_type, bool free = false)
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
        	update_hint("Can't afford witch");
        	return;
    	}
	}
	
	CountWitches(false);
	if (live_zombie_arr[ZOMBIECLASS_WITCH]>=max_zombie_arr[ZOMBIECLASS_WITCH]) 
	{
    	update_hint("Limit reached");
    	return;
	}
	
	if (!is_zombie_available_cooldown(ZOMBIECLASS_WITCH))
	{
    	update_hint("Cooldown active");
        return;
	}
	
	update_t_zm_activity();
	
	if (!can_ZM_spawn(true)) return;
	
	if (witch_type==WITCH_STATIC) SetConVarInt(FindConVar("sv_force_time_of_day"),0);
	else SetConVarInt(FindConVar("sv_force_time_of_day"),3);
	
	int witch;
	if(g_bSpawnWitchBride) witch = L4D2_SpawnWitchBride(zm_spawner_pos,NULL_VECTOR);
    else witch = L4D2_SpawnWitch(zm_spawner_pos,NULL_VECTOR);
	
	CreateTimer(0.25,reset_time_of_day,TIMER_FLAG_NO_MAPCHANGE);
	
	if (witch>0)
	{
    	if (!free) bank -= temp_cost;
    	live_zombie_arr[ZOMBIECLASS_WITCH] += 1;
    	if (DEBUG) PrintToServer("[zm] Created witch %d", witch);
    	//SDKHook(bot, entity_visible, OnTakeDamage_Units);
    	CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(witch), TIMER_FLAG_NO_MAPCHANGE);
    	entref_delete = EntIndexToEntRef(witch);
    	update_hint("Spawned witch");
    	add_available_zombie(ZOMBIECLASS_WITCH,-1);
    	create_timer_add_available_zombie(g_fWitchCooldown,ZOMBIECLASS_WITCH,roundcount);
	}
	else update_hint("Witch spawn failed");
    
    zm_update(zm_timer);

}


void CountWitches(bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_WITCH]<=0 && fast) return;
    if (DEBUG) PrintToServer("[zm] CountWitches expensive");
    live_zombie_arr[ZOMBIECLASS_WITCH] = L4D2_GetWitchCount();
}

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
   		if(IsValidEntity(entity) || IsValidEdict(entity))
   		{    
   		     if (entity==zm_client) continue;
   		     if (GetEntProp(entity,Prop_Data,"m_iMaxHealth")<=0) continue;
      	     GetEntityClassname(entity, class, sizeof(class));
      	     if ( (common && strcmp(class,"infected")==0) || (witch && strcmp(class,"witch")==0) || (special && strcmp(class,"player")==0 && GetClientTeam(entity)==TEAM_INFECTED) )
      	     {
          	     remove_ZM_glow(entity);
          	     zm_deleted = true;
          	     RemoveEntity(entity); // asdf change this to something beter like cull or kill
      	     }
   		}
   	}
   	
   	cleanup_bad_glows();  	
}

Action ZM_Spawn_Witch(int client, int args)
{	
	if (!g_bCvarAllow) return Plugin_Continue;
	int witch_type = WITCH_STATIC;
	if (args>0) witch_type=GetCmdArgInt(1);
	ZM_Witch(client,witch_type);
	return Plugin_Continue;
}


void zm_del_pointing(int client)
{
   
   if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client) return;
   
   if (DEBUG) PrintToServer("[zm] zm_del_pointing");
   
   if (is_zm_spamming()) return;
   
   update_t_zm_activity();
   zm_deleted = false;
   update_ZM_looktarget(false);
   if (!IsValidEntRef(entref_delete))
   {
       update_hint("Invalid target");
       return;
   }
   int target = EntRefToEntIndex(entref_delete);
   if ( !IsValidEntity(target) || (target<=MaxClients && !IsFakeClient(target)) ) 
   {
       update_hint("Invalid target");
       return;
   }
   
   static char class[32];
   GetEntityClassname(target, class, sizeof(class));
   
   zm_deleted = true;
   RemoveEntity(target); // asdf change this to something better like cull
   
   if (strcmp(class,"player")==0)
   {
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
   }
   else if (strcmp(class,"witch")==0) CountWitches();
   else CountCommons();
   
   cleanup_bad_glows();
   
}

public Action evtPlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
    
    if (!g_bCvarAllow) return Plugin_Continue;
    
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (panic_target==victim && IsClientInGame(victim) && GetClientTeam(victim)==TEAM_SURVIVOR)
        panic_target = -1;
    
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
    
    if (DEBUG) PrintToServer("[zm] evtPlayerDeath");
    
    // Skip victims that are not infected entities
    int victim = GetClientOfUserId(event.GetInt("userid"));
    //if (DEBUG)
    //{
    //    int max_health = GetEntProp(victim,Prop_Data,"m_iMaxHealth");
    //    int health = GetEntProp(victim,Prop_Data,"m_iHealth");
    //    PrintToServer("%d died %d/%d", victim, health, max_health);
    //}
    if (!IsValidClient(victim) || !IsClientInGame(victim)) return Plugin_Continue;
    
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
    
    if(GetClientTeam(victim)!=TEAM_INFECTED) return Plugin_Continue;
    
    // ZM controlling special infected has died
    if (victim==zm_client)
    {
        //RequestFrame(OnNextFrame_UpdateDeathTime, GetClientUserId(zm_client));
        PrintToServer("[zm] Unexpected player_death on ZM!!! Report this to mod authors.");
        EmitSoundToAll(SOUND_BUG);
        //float vOrigin[3];
        //GetClientAbsOrigin(zm_client, zm_deathPos);
        //GetClientEyePosition(zm_client,zm_deathPos);
        //ChangeClientTeam(zm_client,TEAM_SURVIVOR);
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        //JoinZM(zm_client,0);
        //ChangeClientTeam(client,TEAM_ZM);
        //L4D_State_Transition(client, STATE_OBSERVER_MODE);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
        //L4D_CleanupPlayerState(zm_client);
        //if (panic_target==zm_client) panic_target = -1;
        //JoinZM(zm_client,0);
        //ZMTeleport(zm_client,0);
        
        //L4D_State_Transition(zm_client, STATE_DEATH_WAIT_FOR_KEY);

        //ForcePlayerSuicide(zm_client);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //L4D_ReplaceWithBot(zm_client);
        //L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
        //L4D_CleanupPlayerState(zm_client);
        
        //TeleportEntity(zm_client, vOrigin, NULL_VECTOR, NULL_VECTOR);
        //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        //unfreeze_zm();
        //zm_deathClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
        //if (zClass == ZOMBIECLASS_TANK) CreateTimer(2.0,unfreeze_zm,zClass,TIMER_FLAG_NO_MAPCHANGE);
        //else CreateTimer(0.5,unfreeze_zm,zClass,TIMER_FLAG_NO_MAPCHANGE);
        
        //L4D_CleanupPlayerState(zm_client);
        //SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0);
        //SetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", {0.0,0.0,0.0});
        //SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
        
        //ChangeClientTeam(zm_client,TEAM_SPECTATOR);
        
        //CreateTimer(0.1,unfreeze_zm,TIMER_FLAG_NO_MAPCHANGE);
        
    }
    
    int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    
    remove_ZM_glow(victim);
    
    // Skip logic if tank is suicided due to player control
    if (victim==ent_control)
    {
        ent_control = -1;
        return Plugin_Continue;
    }
    
    // survival: every tank death gives ZM points
    if (zClass==ZOMBIECLASS_TANK)
    {
       if (L4D_IsSurvivalMode())
       {
           if (live_zm_tanks<=0)
           {
               bank += g_iBonusFinaleStage*g_iAliveSurvivors;
               update_hint("Tank died, dosh added");
           }
       }
       if (live_zm_tanks>0) live_zm_tanks -= 1;
    }

	return Plugin_Continue;
}

void spawn_free_angry_zombies(int victim, int count)
{
    if (!IsValidClient(victim) || GetClientTeam(victim)!=TEAM_SURVIVOR || !IsPlayerAlive(victim)) return;
    
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
        if(L4D_GetRandomPZSpawnPosition(victim,ZOMBIECLASS_TANK,5,vecPos))
        {
            zombie = L4D_SpawnCommonInfected(vecPos);
            if (zombie>0)
            {
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
    spawn_free_angry_zombies(victim,vomit_numzombies);
    return Plugin_Continue;
}

public Action EvtWitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (DEBUG) PrintToServer("[zm] EvtWitchKilled");
    
    int witch = event.GetInt("witchid");
    remove_ZM_glow(witch);

	return Plugin_Continue;
}

// high ping bug: spawns will sometimes be under the world. try to check 1.0s after spawning and enforce on navmesh
// save navmesh info and where zombie should have been spawned 

int ZM_Spawn_SI(int client, int ZOMBIECLASS, bool free = false, bool setpos=false, float pos[3] = {0.0,0.0,0.0}, bool glow = true)
{
	if (!g_bCvarAllow || !IsValidClientZM() || client!=zm_client || ZOMBIECLASS<=0) return -1;
	
	if (DEBUG) PrintToServer("[zm] ZM_Spawn_SI");
	
	if (!setpos && is_zm_spamming()) return -1;
	
	// asdf bots stand still doing nothing sometimes. make them move. use order bot native?
	
	int cost_SI;
	if (!free)
	{
    	cost_SI = costs_SI[ZOMBIECLASS];
    	if ((bank-cost_SI)<0)
    	{
        	update_hint("Try getting a job");
        	return -1;
    	}
	}
	
	CountClients();
	if (!setpos)
	{
	    if (live_SI>=max_SI || live_zombie_arr[ZOMBIECLASS]>=max_unique_SI)
        {
            update_hint("Limit reached");
            return -1;
        }
	    
    	if (!can_ZM_spawn()) return -1;
    	
    	if (!is_zombie_available_cooldown(ZOMBIECLASS))
    	{
        	// TO DO: print time left
        	update_hint("Cooldown active");
        	return -1;
    	}
    }
    
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
    	if (setpos) TeleportEntity(bot, pos, NULL_VECTOR, NULL_VECTOR);
    	else TeleportEntity(bot, zm_spawner_pos, NULL_VECTOR, NULL_VECTOR);
    	if (zm_stage<ZM_STARTED)
    	{
        	SetEntProp(bot, Prop_Send, "movetype", 0);
        	SetEntProp(bot, Prop_Send, "m_fFlags", GetEntProp(bot, Prop_Send, "m_fFlags")|FL_FROZEN);
    	}
    	else SetEntProp(bot, Prop_Send, "movetype", 2);
    	if (!free) bank -= cost_SI;
    	
    	if (glow) CreateTimer(g_fUpdateRate, CreateZMGlow_white, EntIndexToEntRef(bot), TIMER_FLAG_NO_MAPCHANGE);
    	
    	entref_delete = EntIndexToEntRef(bot);
        entref_control = bot;
        
        if (!setpos)
        {
            add_available_zombie(ZOMBIECLASS,-1);
            
            float cooldown_time;
            if (ZOMBIECLASS==ZOMBIECLASS_TANK) cooldown_time = g_fTankCooldown;
            else cooldown_time = g_fSpecialCooldown;
            
            //CreateTimer(cooldown_time, timer_add_available_zombie, ZOMBIECLASS, TIMER_FLAG_NO_MAPCHANGE);
            create_timer_add_available_zombie(cooldown_time,ZOMBIECLASS,roundcount);
            L4D2_SetCustomAbilityCooldown(bot,0.0); //spitter fix
            
            if (!zm_use_notify && zm_stage>=ZM_STARTED)
            {
                update_hint("USE to control Specials");
                if (IsValidClientZM()) PrintHintText(zm_client, "Press the USE key to control Special Infected.");
                zm_use_notify = true;
            }
            else 
            {
                char name[32];
                get_zombieclass_name(ZOMBIECLASS,name);
                update_hint("Spawned %s", name);
            }
            
            if (ZOMBIECLASS==ZOMBIECLASS_TANK) live_zm_tanks += 1;
            
        }
        
        zm_update(zm_timer);

	}
	else update_hint("Spawn failed");
    
	return bot;
}

Action ZM_Smoker(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_SMOKER);
   return Plugin_Continue;
}

Action ZM_Boomer(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_BOOMER);
   return Plugin_Continue;
}

Action ZM_Hunter(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_HUNTER);
   return Plugin_Continue;
}

Action ZM_Spitter(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_SPITTER);
   return Plugin_Continue;
}

Action ZM_Jockey(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_JOCKEY);
   return Plugin_Continue;
}

Action ZM_Charger(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_CHARGER);
   return Plugin_Continue;
}

Action ZM_Tank(int client, int args)
{
   ZM_Spawn_SI(client,ZOMBIECLASS_TANK);
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
    
    ResetConVar(FindConVar("sb_enforce_proximity_range"), true, true);
    
    ResetConVar(FindConVar("z_common_limit"), true, true);
    ResetConVar(FindConVar("z_no_cull"), true, true);
	ResetConVar(FindConVar("z_minion_limit"), true, true);
	//ResetConVar(FindConVar("director_no_mobs"), true, true);
	ResetConVar(FindConVar("z_wandering_density"), true, true);
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
	
	if (infectedbots_dispose_cowards) ResetConVar(infectedbots_dispose_cowards, true,true);
	else if (infectedbots_enable) ResetConVar(infectedbots_enable, true,true);

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
   
   // Prevent survivor bot teleport bug
   SetConVarInt(FindConVar("sb_enforce_proximity_range"), 999999);
   
   //SetConVarInt(FindConVar("z_common_limit"), 1);
   SetConVarInt(FindConVar("z_discard_min_range"), 9999999);
   SetConVarInt(FindConVar("z_discard_range"), 9999999);
   SetConVarInt(FindConVar("z_no_cull"), 1);
   SetConVarInt(FindConVar("z_minion_limit"), 0);
   //SetConVarInt(FindConVar("director_no_mobs"), 1);
   SetConVarInt(FindConVar("z_wandering_density"), 0);
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
   
   // Including all SI on field + spectating ZM
   SetConVarInt(FindConVar("survival_max_specials"), max_SI+1);
   SetConVarInt(FindConVar("z_max_player_zombies"), max_SI+1);
   
   SetConVarInt(FindConVar("survival_max_smokers"), max_unique_SI+1);
   SetConVarInt(FindConVar("survival_max_boomers"), max_unique_SI+1);
   SetConVarInt(FindConVar("survival_max_hunters"), max_unique_SI+1);
   SetConVarInt(FindConVar("survival_max_spitters"), max_unique_SI+1);
   SetConVarInt(FindConVar("survival_max_jockeys"), max_unique_SI+1);
   SetConVarInt(FindConVar("survival_max_chargers"), max_unique_SI+1);
   

   SetConVarInt(FindConVar("z_smoker_limit"), max_unique_SI+1);
   SetConVarInt(FindConVar("z_boomer_limit"), max_unique_SI+1);
   SetConVarInt(FindConVar("z_hunter_limit"), max_unique_SI+1);
   SetConVarInt(FindConVar("z_spitter_limit"), max_unique_SI+1);
   SetConVarInt(FindConVar("z_jockey_limit"), max_unique_SI+1);
   SetConVarInt(FindConVar("z_charger_limit"), max_unique_SI+1);
   
   if (infectedbots_dispose_cowards) SetConVarInt(infectedbots_dispose_cowards, 0);
   else if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
   
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
	
	PrecacheSound(SOUND_READY);
	PrecacheSound(SOUND_BUG);
	PrecacheSound(SOUND_DOORSLAM);
	PrecacheSound(SOUND_INACTIVITY);
    PrecacheSound(SOUND_START);
    PrecacheSound(SOUND_VISION);
    
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
	
}

public Action Timer_StartPrecomputeNav(Handle timer)
{
	PrintToServer("[zm] Starting navmesh precomputation...");
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
	g_iLockedDoor = SAFEROOM_UNKNOWN; // we don't know if there's gonna be a door next map
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

//void PanicEventStarted(Event event, const char[] name, bool dontBroadcast)
//{	
//	if (L4D_IsSurvivalMode() || zm_stage!=ZM_STARTED) return;
//	
//	PrintToServer("[zm] PanicEventStarted");
//	
//	if ((GetEngineTime()-t_last_panic)<t_panic_overlap)
//	{
//    	if (DEBUG) PrintToServer("[zm] Overlap detected, ignoring");
//    	return;
//	}
//	
//	if (zm_stage==ZM_STARTED)
//    {
//        bank += g_iBonusCarAlarm;
//        //PrintToChatAll("[zm] ZM awarded %d zombux and free panic for car alarm!", g_iBonusCarAlarm);
//        if (!panic)
//        {
//            //int target = L4D_GetHighestFlowSurvivor();
//            //spawn_free_angry_zombies(target,50);
//            CreateTimer(1.0, Timer_Free_Angry_Zombies, 50, TIMER_FLAG_NO_MAPCHANGE);
//            manual_panic=false; // panic hasn't run yet - means it wasn't started by ZM
//            toggle_panic(true,true,true); // free panic!
//        }
//        else bank += g_iPanicCost;
//        zm_update(zm_timer);
//    }
//    
//    create_common_menu();
//    
//}

//void PanicEventFinished(Event event, const char[] name, bool dontBroadcast)
//{
//	if (L4D_IsSurvivalMode() || zm_stage!=ZM_STARTED || ZM_finale_announced || L4D_IsFinaleActive()) return;
//	PrintToServer("[zm] PanicEventFinished");
///	//L4D2Direct_SetPendingMobCount(0);
//	//if (panic && !manual_panic) toggle_panic(false,true,true);
///	create_common_menu();
//}

void evtRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	
	if (DEBUG) PrintToServer("[zm] evtRoundEnd");
	bool ZM_won = true;
	for( int i = 1; i <= MaxClients; i++ )
	{
		if(IsClientInGame(i) && !IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
	    
	    if (!IsClientInGame(i)) continue;
	    if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
		if ( IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_isIncapacitated")<=0 )
		{
    		ZM_won = false;
		}
		
	}
	if (IsValidClientZM())
	{
    	if (ZM_won) EmitSoundToClient(zm_client,SOUND_ZM_WIN);
    	QuitZM(zm_client,false); // InputKill prevention
	}
	g_iLockedDoor = SAFEROOM_UNKNOWN;
	saferoom_locked = false;
    if (ZM_finale_announced) ZM_finale_ended = true;
	ResetTimer();
	set_zm_stage(ZM_END,true);
	update_EMS_HUD();
	
}

void evtRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (DEBUG) PrintToServer("[zm] evtRoundStart");
	g_iLockedDoor = SAFEROOM_UNKNOWN;
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
    if (g_bLockSaferoom) freeze_team(false);
}

public Action L4D_OnMobRushStart()
{
    int pending_mob = L4D2Direct_GetPendingMobCount();
    PrintToServer("[zm] L4D_OnMobRushStart %d", pending_mob);
    if (!g_bCvarAllow) return Plugin_Continue;
    update_director_script_scopes();
    //if (!panic) L4D2Direct_SetPendingMobCount(0);
    return Plugin_Continue;
}

public Action L4D_OnSpawnMob()
{
    int pending_mob = L4D2Direct_GetPendingMobCount();
    PrintToServer("[zm] L4D_OnSpawnMob %d", pending_mob);
    if (!g_bCvarAllow) return Plugin_Continue;
//    if (L4D_IsSurvivalMode() || ZM_finale_announced) return Plugin_Continue;
//    if (pending_mob<=0) return Plugin_Continue;
//    if (panic) t_last_panic = GetEngineTime();
//    else
//    {
//        PrintToServer("[zm] L4D_OnSpawnMob started panic");
//        manual_panic = false;
//        toggle_panic(true,true,true); // free panic!
//        CreateTimer(2.0, Timer_Free_Angry_Zombies, pending_mob, TIMER_FLAG_NO_MAPCHANGE);
//    }
    update_director_script_scopes();
    //if (!panic) L4D2Direct_SetPendingMobCount(0);
    return Plugin_Continue;
}

void IsAllowed()
{
	if (DEBUG) PrintToServer("[zm] IsAllowed");
	bool bCvarAllow = g_hCvarAllow.BoolValue;
    
    if (!L4D2_IsGenericCooperativeMode() && !L4D_IsSurvivalMode() && bCvarAllow)
    {
        SetConVarInt(g_hCvarAllow,0);
        PrintToChatAll("[zm] Zombie Master is available only for Coop and Survival.");
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
		HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
		HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post);
		HookEvent("finale_vehicle_ready", EvtFinaleEnding, EventHookMode_PostNoCopy);
		HookEvent("finale_vehicle_incoming", EvtFinaleEnding, EventHookMode_PostNoCopy);
		HookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		HookEvent("player_now_it", Event_PlayerBoomed, EventHookMode_Post);
		HookEvent("finale_rush", EvtFinaleRush, EventHookMode_PostNoCopy);
		
		GetCvars();
		SetCvarsZM();
		
		if (g_dd_StartRangeCull) g_dd_StartRangeCull.Enable(Hook_Pre, StartRangeCull_Pre);
		if (g_hDTR_InputKill) g_hDTR_InputKill.Enable(Hook_Pre, DTR_CBaseEntity_InputKill);
		if (g_hDTR_InputKillHierarchy) g_hDTR_InputKillHierarchy.Enable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
		
		GameRules_SetProp("m_bChallengeModeActive", 1); // Enable the HUD drawing
		EMS_hud_ready = true;
		if (AllPlayerCount<=0) CountClients();
		if (AllPlayerCount>0) clients_in_server = true;
		
		create_main_menu();
		update_menus();
		
        HookEntityOutput("info_director", "OnPanicEventFinished", OnDirectorOutputFired);
        HookEntityOutput("info_director", "OnCustomPanicStageFinished", OnDirectorOutputFired);
        
        //HookEntityOutput("info_goal_infected_chase", "Enable", OnChaseOutputFired);
        
        SetConVarInt(FindConVar("mp_restartgame"), 1);
        
        if (!g_bNavReady)
    	{
        	g_hObscuredList = new ArrayList(sizeof(PreCalcNav));
        	g_hStartAreaList = new ArrayList(sizeof(PreCalcNav));
        	g_bNavReady = false;
        	CreateTimer(1.0, Timer_StartPrecomputeNav, _, TIMER_FLAG_NO_MAPCHANGE);
    	}
        
		
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
		UnhookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
		UnhookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post);
		UnhookEvent("finale_vehicle_ready", EvtFinaleEnding, EventHookMode_PostNoCopy);
		UnhookEvent("finale_vehicle_incoming", EvtFinaleEnding, EventHookMode_PostNoCopy);
		UnhookEvent("witch_killed", EvtWitchKilled, EventHookMode_Post);
		UnhookEvent("player_now_it", Event_PlayerBoomed, EventHookMode_Post);
		UnhookEvent("finale_rush", EvtFinaleRush, EventHookMode_PostNoCopy);
		
		if (g_dd_StartRangeCull) g_dd_StartRangeCull.Disable(Hook_Pre, StartRangeCull_Pre);
		if (g_hDTR_InputKill) g_hDTR_InputKill.Disable(Hook_Pre, DTR_CBaseEntity_InputKill);
		if (g_hDTR_InputKillHierarchy) g_hDTR_InputKillHierarchy.Disable(Hook_Pre, DTR_CBaseEntity_InputKillHierarchy);
		
		for( int i = 1; i <= MaxClients; i++ )
    	{
    		if(IsClientInGame(i) && !IsFakeClient(i)) FindConVar("mp_gamemode").ReplicateToClient(i,g_sCvarMPGameMode);
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
        
        //UnhookEntityOutput("info_goal_infected_chase", "Enable", OnChaseOutputFired);
        
		SetConVarInt(FindConVar("mp_restartgame"), 1);
		
	}

	
}

public MRESReturn DHook_AcceptInput_Post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bCvarAllow || zm_stage!=ZM_STARTED || L4D_IsSurvivalMode()) return MRES_Ignored;
	
	char inputName[256];
	hParams.GetString(1, inputName, sizeof(inputName));
	int activator = hParams.IsNull(2) ? -1 : hParams.Get(2);
	int caller = hParams.IsNull(3) ? -1 : hParams.Get(3);	
	int actionId = hParams.Get(5);	
	
	// Called by ZM -- do nothing
	if (strcmp(inputName,"ForcePanicEvent")==0 && activator==-1 && caller==-1 && actionId==0 )
	{
	   manual_panic = true;
	   return MRES_Ignored;
	}
	
	// Single panic event -- will not need revival
	if (strcmp(inputName,"PanicEvent")==0)
	{
    	manual_panic = false;
    	update_panic();
	}
	
	// Scripted panic event - may last a while and need revival.
	if (strcmp(inputName,"ScriptedPanicEvent")==0)
	{
    	manual_panic = false;
    	update_panic();
	}
	
	PrintToServer("[zm] info_director accepted input %s %d %d %d", inputName, activator, caller, actionId);
	
	return MRES_Ignored;
}

MRESReturn StartRangeCull_Pre(int entity)
{
	PrintToServer("[zm] StartRangeCull_Pre");
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
    if (L4D_IsSurvivalMode()) return;
    if (DEBUG) PrintToServer("[zm] Event_TriggeredCarAlarm");
    if (zm_stage==ZM_STARTED)
    {
        bank += g_iBonusCarAlarm;
        PrintToChatAll("[zm] ZM awarded %d zombux and free panic for car alarm!", g_iBonusCarAlarm);
        if (!panic)
        {
            manual_panic=false;
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

void Event_PlayerDisconnect(Event event, char[] name, bool bDontBroadcast)
{
    if (DEBUG) PrintToServer("[zm] Event_PlayerDisconnect");
    if (g_bCvarAllow)
    {
       if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
       int client = GetClientOfUserId(event.GetInt("userid"));
       if (zm_client==client)
       {
   	      update_t_zm_activity(0.0); // instantly starts printing the "no ZM" message
   	      QuitZM(client);
   	      if (zm_stage<ZM_STARTED) can_zm_start();
   	   }
   	   
   	   if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
   	   
    }
}

void Event_PlayerActivate(Event event, char[] name, bool bDontBroadcast)
{
    if (DEBUG) PrintToServer("[zm] Event_PlayerActivate");
    if (g_bCvarAllow)
    {
        if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
        int client = GetClientOfUserId(event.GetInt("userid"));
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
   	   if (g_bLockSaferoom && L4D_IsInIntro()>0)
   	   {
       	   if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client))
       	      freeze_player(client);
   	   }
   	  
    }
}

void evtPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (DEBUG) PrintToServer("[zm] evtPlayerTeam");
	if (g_bCvarAllow)
    {
       if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
       int client = GetClientOfUserId(event.GetInt("userid"));
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
        if (zm_can_start && !navArea_validStart(temp_navArea)) start_zm_round();
        else if (g_bLockSaferoom && saferoom_locked && L4D_IsInIntro()<=0)
        {
            tp_survivor_start(client);
            if (!IsFakeClient(client))
            {
                if (!IsValidClientZM()) PrintHintText(client, "There is no Zombie Master.");
                else PrintHintText(client, "The round cannot start yet.");
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

public void OnClientDisconnect(int client)
{
	if (g_bCvarAllow)
	{
	   if (DEBUG) PrintToServer("[zm] OnClientDisconnect");
	   if (zm_timer == INVALID_HANDLE) zm_update(zm_timer);
       if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients,TIMER_FLAG_NO_MAPCHANGE);
       if (zm_client==client)
       {
   	      update_t_zm_activity(0.0); 
   	      QuitZM(zm_client,0);
   	   } 
    }
}

// Refund zombie delete
public void OnEntityDestroyed(int entity)
{
    if ( !g_bCvarAllow || !IsValidEntity(entity) ) return;
    
	if (zm_stage>=ZM_PREP || zm_deleted)
	{
	   int max_health = GetEntProp(entity,Prop_Data,"m_iMaxHealth");
	   //if (DEBUG) PrintToServer("[zm] OnEntityDestroyed MaxHP %d", max_health);
	   if (max_health && max_health>0)
	   {
    	   int health = GetEntProp(entity,Prop_Data,"m_iHealth");
    	   
    	   if (health<max_health) return;
           
           static char class[32];
       	   GetEntityClassname(entity, class, sizeof(class));
       	  
       	  int bank_refund = 0;
       	  
       	  if (strcmp(class,"infected")==0)
       	  {
       	     bank_refund=g_iCostCommon;
       	     // asdf TBD check if uncommon to refund correct amount
       	     add_available_zombie(ZOMBIECLASS_COMMON,1);
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
           	 if (GetEntProp(entity, Prop_Send, "m_isIncapacitated")>0) return;
           	 int zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
             if (zClass<ZOMBIECLASS_SMOKER || zClass>ZOMBIECLASS_TANK || zClass==7) return;
             bank_refund = costs_SI[zClass];
             // Prevent tanks from being refunded during finales and survival
             if (zClass==ZOMBIECLASS_TANK)
             {
                 if ( ZM_finale_announced || L4D_IsSurvivalMode() ) bank_refund = 0;
                 if (live_zm_tanks>0) live_zm_tanks -= 1;
             }
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
    
}

void cleanup_bad_glows()
{
    int child = -1;
    while ((child = FindEntityByClassname(child, "prop_dynamic_ornament")) != -1)
    {
        if (IsValidEntity(child) && child > MaxClients)
        {
            int parent = GetEntPropEnt(child,Prop_Data,"m_pParent");
            if (!IsValidEntity(parent) || ( IsValidClient(parent) && IsClientInGame(parent) && !IsPlayerAlive(parent) ) )
            {
                //RemoveEntity(child);
                AcceptEntityInput(child, "Kill"); 
            }
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

// Handled: invisible
// Continue: visible
Action OnTransmitZM(int entity, int client)
{
	if(GetClientTeam(client) == TEAM_SURVIVOR) return Plugin_Handled;
	return Plugin_Continue;
}

GameData hGameData;
void GetGameData()
{
	if (DEBUG) PrintToServer("[zm] GetGameData");
	hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	
	if( hGameData != null ) PrepSDKCall();
	else SetFailState("Unable to find l4d2_zombie_master.txt gamedata file.");
	
	delete hGameData;
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

	delete hGameData;
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
// Chance, Skerion, Lett1, AGGA Lambo, AriesToffle, Shadowcat
// HUGE THANKS for scripting help: HarryPotter, xerox8521, Forgetest, little_froy, Lux, Marttt, Bacardi
// HUGE THANKS TO Reagy and IronBar for hosting the Knockout Left 4 Dead 2 Server

// MASSIVE THANKS to authors of various L4D2 scripts used for reference:
// Marttt - nav_info
// Dragokas -- Chase() -- https://forums.alliedmods.net/showthread.php?t=321034