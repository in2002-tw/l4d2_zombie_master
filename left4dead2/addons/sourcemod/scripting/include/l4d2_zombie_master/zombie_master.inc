//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//You should have received a copy of the GNU General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

///////////////////////////////////////
#if defined _zm_included
 #endinput
#endif
#define __zm_included
///////////////////////////////////////

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>
#include <left4dhooks>
#include <adt_trie>

#define FIRST_TANK_SPAWNED 1
#define FIRST_TANK_DEAD 2

#define ZM_MENU_CLOSED 0
#define ZM_MENU_MAIN 1
#define ZM_MENU_COMMON 2
#define ZM_MENU_UNCOMMON 3
#define ZM_MENU_SPECIAL 4
#define ZM_MENU_BOSS 5
#define ZM_MENU_CLEANUP 6
#define ZM_MENU_OTHER 7
#define ZM_MENU_AUTOCOMMON 8
#define ZM_MENU_CONTEXT 9

// enum for spawner context state. to determine spawner RGB state:
// 0 -> GREEN
// 1,2 -> RED
// else -> BLUE
#define SPAWNER_OK 0
#define SPAWNER_INVALID 1
#define SPAWNER_NAV 2
#define SPAWNER_DISTANCE 3
#define SPAWNER_SIGHT 4
#define SPAWNER_OTHER 5
#define SPAWNER_FLOW 6 // ZM is looking at a survivor with intent -> request flow spawn.

#define RGB_ZM 16777215 // white for outlines
#define RGB_FLOW 16711680 // blue for flow target survivor
//#define RGB_FLOW 16777215

#define AUTOCOMMON_OFF 0
#define AUTOCOMMON_PANIC 1
#define AUTOCOMMON_ALWAYS 2

#define HULL_DX_STRICT 16.0
#define HULL_DZ_MIN_STRICT 20.0
#define HULL_DZ_MAX_STRICT 50.0

// TraceHull for obstruction
static float HULL_MINS[3] = {-HULL_DX_STRICT,-HULL_DX_STRICT,HULL_DZ_MIN_STRICT};
static float HULL_MAXS[3] = {HULL_DX_STRICT,HULL_DX_STRICT,HULL_DZ_MAX_STRICT};

#define DISTANCE_LAST_SAFEROOM 100.0 // minimum distance to saferoom for valid zombie spawns

#define AREA_COMMON 1024.0 // how much surface area a Common Infected is going to take up; 32x32

#define HULL_DX 20.0
#define HULL_DZ 40.0
#define HULL_DDZ 80.0

// TraceHull to determine if ZM is looking at survivor through walls
static float HULL_MINS_LOOK[3] = {-HULL_DX,-HULL_DX,-HULL_DZ};
static float HULL_MAXS_LOOK[3] = {HULL_DX,HULL_DX,HULL_DZ};

#define WITCH_STATIC 0
#define WITCH_MOVING 1

#define IGNITE_TIME 3600.0
#define FOG_DISTANCE 5000.0

#define SOUND_BLOCKED "ui/beep_error01.wav"
#define SOUND_CONDITIONAL "ui/menu_invalid.wav"
//#define SOUND_ALLOWED "ui/menu_focus.wav"
#define SOUND_HITMARKER "ui/littlereward.wav" // try beepclear.wav

#define EXPLOSION1 "ambient/explosions/explode_1.wav"
#define EXPLOSION2 "ambient/explosions/explode_2.wav"
#define EXPLOSION3 "ambient/explosions/explode_3.wav"

#define MODEL_SMOKER "models/infected/smoker.mdl"
#define MODEL_BOOMER "models/infected/boomer.mdl"
#define MODEL_HUNTER "models/infected/hunter.mdl"
#define MODEL_SPITTER "models/infected/spitter.mdl"
#define MODEL_JOCKEY "models/infected/jockey.mdl"
#define MODEL_CHARGER "models/infected/charger.mdl"
#define MODEL_TANK "models/infected/hulk.mdl"

#define MODEL_RIOT "models/infected/common_male_riot.mdl"
#define MODEL_RIOT2 "models/infected/common_male_riot_l4d1.mdl"

#define MODEL_CEDA "models/infected/common_male_ceda.mdl"
#define MODEL_CEDA2 "models/infected/common_male_ceda_l4d1.mdl"

#define MODEL_CLOWN "models/infected/common_male_clown.mdl"

#define MODEL_MUD "models/infected/common_male_mud.mdl"
#define MODEL_MUD2 "models/infected/common_male_mud_l4d1.mdl"

#define MODEL_ROAD "models/infected/common_male_roadcrew.mdl"
#define MODEL_ROAD2 "models/infected/common_male_roadcrew_rain.mdl"
#define MODEL_ROAD3 "models/infected/common_male_roadcrew_l4d1.mdl"
#define MODEL_ROAD4 "models/infected/common_male_baggagehandler_02.mdl"

#define MODEL_JIMMY "models/infected/common_male_jimmy.mdl"

#define MODEL_FALLEN "models/infected/common_male_fallen_survivor.mdl"
#define MODEL_FALLEN2 "models/infected/common_male_parachutist.mdl"
#define MODEL_FALLEN3 "models/infected/common_male_fallen_survivor_l4d1.mdl" // this one has 2 bodygroups as well



stock bool valid_uncommon(char arg[32])
{
    if (arg[0]==0) return false;
    if (strcmp(arg,"random")==0) return true;
    else if (strcmp(arg,"riot")==0) return true;
	else if (strcmp(arg,"ceda")==0) return true;
	else if (strcmp(arg,"clown")==0) return true;
	else if (strcmp(arg,"mud")==0) return true;
	else if (strcmp(arg,"road")==0) return true;
	else if (strcmp(arg,"jimmy")==0) return true;
	else if (strcmp(arg,"fallen")==0) return true;
	return false;
}

stock void get_uncommon_model(char label[16], char model[64])
{
    model = "";
    switch (label[0])
    {
        case 'r':
        {
            if (strcmp(label,"random",false)==0)
            {
                switch (GetRandomInt(1,5))
                {
                    case 1: get_uncommon_model("riot",model);
                    case 2: get_uncommon_model("road",model);
                    case 3: get_uncommon_model("ceda",model);
                    case 4: get_uncommon_model("clown",model);
                    case 5: get_uncommon_model("mud",model);
                }
                return;
            }
            else if (strcmp(label,"riot",false)==0)
            {
                switch (GetRandomInt(0,1))
                {
                    case 1: model = MODEL_RIOT2;
                    default: model = MODEL_RIOT;
                }
            }
            else if (strcmp(label,"road",false)==0)
            {
                switch (GetRandomInt(0,3))
                {
                    case 1: model = MODEL_ROAD2;
                    case 2: model = MODEL_ROAD3;
                    case 3: model = MODEL_ROAD4;
                    default: model = MODEL_ROAD;
                }
            }
        }
        case 'c':
        {
            if (strcmp(label,"ceda",false)==0)
            {
                switch (GetRandomInt(0,1))
                {
                    case 1: model = MODEL_CEDA2;
                    default: model = MODEL_CEDA;
                }
            }
            else if (strcmp(label,"clown",false)==0) model = MODEL_CLOWN;
        }
        case 'm':
        {
            if (strcmp(label,"mud",false)==0)
            {
                switch (GetRandomInt(0,1))
                {
                    case 1: model = MODEL_MUD2;
                    default: model = MODEL_MUD;
                }
            }
        }
        case 'j': model = MODEL_JIMMY;
        case 'f':
        {
            if (strcmp(label,"fallen",false)==0)
            {
                switch (GetRandomInt(0,2))
                {
                    case 1: model = MODEL_FALLEN2;
                    case 2: model = MODEL_FALLEN3;
                    default: model = MODEL_FALLEN;
                }
            }
        }
        default: model = ""; 
    }
}

#define SOUND_READY "ui/critical_event_1.wav"
#define SOUND_OFFER "ui/pickup_misc42.wav"
#define SOUND_REWARD "ui/beep_synthtone01.wav"
#define SOUND_ZM_WIN "level/loud/gallery_win.wav"
#define SOUND_DOORSLAM "doors/heavy_metal_stop1.wav"
#define SOUND_DOORSLAM2 "doors/hit_kickmetaldoor1.wav"
#define SOUND_DOORSLAM3 "doors/hit_kickmetaldoor2.wav"
#define SOUND_BUG "common/bugreporter_failed.wav"
//#define SOUND_INACTIVITY "ambient/crucial_cricket_amb_01.wav"
#define SOUND_START "ui/pickup_guitarriff10.wav"
#define SOUND_VISION "ui/menu_horror01.wav"
#define SOUND_PANIC_ON "npc/mega_mob/mega_mob_incoming.wav"
#define SOUND_PANIC_OFF "ui/pickup_secret01.wav"

#define SOUND_ELLIS_ZM_FAKE "player/survivor/voice/mechanic/dlc1_communitye20.wav"
#define SOUND_ELLIS_ZM "zm/ellis_zm.wav"
#define SOUND_ELLIS_ZM_MP3 "zm/ellis_zm.mp3"
#define VCD_ELLIS_ZM   "scenes/custom/ellis_zm.vcd"
#define SS_ELLIS_ZM    "CustomVoice_Ellis_ZM"

#define SOUND_LOUIS_ZM_FAKE "player/survivor/voice/Manager/TakeSubMachineGun03.wav"
#define SOUND_LOUIS_ZM "zm/louis_zm.wav"
#define SOUND_LOUIS_ZM_MP3 "zm/louis_zm.mp3"
#define VCD_LOUIS_ZM   "scenes/custom/louis_zm.vcd"
#define SS_LOUIS_ZM    "CustomVoice_Louis_ZM"

#define SOUND_FRANCIS_ZM_FAKE "player/survivor/voice/Biker/WorldSmallTown0311.wav"
#define SOUND_FRANCIS_ZM_MP3 "zm/francis_zm.mp3"

#define SOUND_ZOEY_ZM_FAKE "player/survivor/voice/teengirl/DLC2Steam01.wav"
#define SOUND_ZOEY_ZM_MP3 "zm/zoey_zm.mp3"

#define SOUND_NICK_ZM_FAKE "player/survivor/voice/gambler/nickocd02.wav"
#define SOUND_NICK_ZM_MP3 "zm/nick_zm.mp3"

#define SOUND_COACH_ZM_FAKE "player/survivor/voice/coach/Coach_WorldC4M107.wav"
#define SOUND_COACH_ZM_MP3 "zm/coach_zm.mp3"

#define SCENE_SAFETY_TIMEOUT 30.0

// These are played whenever the ZM forces the round to start by slamming the saferoom door open.
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

// ZM stages
#define ZM_NEWROUND 0 // Survivors in start area, no ZM picked.
#define ZM_PREP 1 // Survivors in start area, ZM is placing units and getting ready, or players still joining. Survivors cannot leave yet.
#define ZM_CANSTART 2 // Prep has ended but survivors haven't left the safezone yet // NOT IN USE
#define ZM_STARTED 3 // Round has started
#define ZM_END 4 // Round has ended - do not allow new ZM or spawning of zombies

bool l4dhooks_updated = false; // check if native L4D_FindEntityByClassnameWithin is available
ConVar g_hCvarDebug, g_hCvarAllow, z_max_player_zombies, infectedbots_enable, jukebox_horde, shoot_alert_enable, clown_world_enable;
bool g_bCvarAllow;
bool g_bSpawnWitchBride = false; // avoid crash

int zm_stage = ZM_END;

// Zombie Master Live Variables
float fog_distance = FOG_DISTANCE;
bool zm_can_start = false;
int zm_client = -1;
int zm_client_userid = -1;
int bank = 0;
float bank_rate = 0.0;
float bank_add = 0.0; // in case very small numbers need to be tracked
float t_last_update = 0.0;
float t_last_action = 0.0; // prevent ZM spamming buttons
int g_iAliveSurvivors = -1;
int max_SI = 16;
int live_SI = 0;
int SI_cap = 16;
bool panic = false;
float t_last_panic = 0.0;
int g_iEntities; // track number of edicts and entities
bool zm_allow_spawns = true; // in survival, prevent spawns until survivors have started timer
Handle zm_timer = INVALID_HANDLE; // zm_update timer, repeats periodically
Handle clients_timer = INVALID_HANDLE; // CountClients() timer which does not run twice if there's already a timer set to run it
char ZM_hint[128];
bool EMS_hud_ready = false; // track whether HUD was initialized
int roundcount = 0;
bool ZM_finale_announced = false;
float t_finale; // prevent finale stages from advancing too quickly
bool fallen_spawned = false; // spawn fallen survivor once per round
bool jimmy_spawned = false; // spawn jimmy gibbs jr once per round
int panic_target = -1; // legacy
int lastdoor = -1;
bool manual_panic = false; // track whether panic was started by game or by ZM
int script_CommonLimit = -1;
//bool scope_changed = false;
//float t_scope_change = 0.0;
bool survival_activated = false; // track if survival panic button was activated but ZM isn't present
bool pending_tank = false;
char targetName_pending[64]; // pending targetname for takeover tank
char model_pending[64]; // pending model for takeover tank
int maxhp_pending = 0; // pending max hp for takeover tank
bool active_looktarget = false; // live update HP for special infected ZM is looking at
Handle hp_timers[MAXENTITIES+1] = {INVALID_HANDLE, ...}; // prevent extremely frequent glow updates
bool l4d2_specials = true;
bool force_started = false;
bool g_bMapStarted = false;
bool clients_in_server = false; // track whether HUD needs to be updated
float t_round_start = 0.0;
bool natural_first_wait = true; // wait for first natural mob timer reset, when survivors leave saferoom usually.
bool clients_active[MAXPLAYERS+1] = {false,...};
bool first_active = false; // track whether ANY player has shown signs of life before starting to offer ZM
bool dominated[MAXPLAYERS+1] = {false,...};
bool zm_win_announced = false;
float clients_t_join[MAXPLAYERS+1] = {0.0,...};
Handle fq_timer = INVALID_HANDLE;
Handle ems_hud_timer = INVALID_HANDLE;
bool recordpos = true; // for tank stutter fix

// Spawner_CacheSurvivorData: PVS (Potentially Visible Set) engine calls + survivor position an
Handle hGetClusterForOrigin = null;
Handle hGetPVSForCluster = null;
Handle hCheckOriginInPVS = null;
Address g_pEngineServer = Address_Null;
#define PVS_BUFFER_SIZE 8192
#define PVS_VALID_TIME 0.09 // seconds (gametime)
bool   g_bBatchPVSActive = false; // is PVS batch valid?
bool   g_bBatchActive = false; // is survivor batch valid?
int    g_iBatchSurvivorCount = 0;
bool   g_BatchSurvivorValidPVS[MAXPLAYERS+1]; // avoiding char non sense
char   g_BatchSurvivorPVS[MAXPLAYERS+1][PVS_BUFFER_SIZE];
int    g_iBatchSurvivorClients[MAXPLAYERS+1];
float  g_fBatchSurvivorPos[MAXPLAYERS+1][3];
float  g_fBatchTime;
float   g_CachedSurvFlow[MAXPLAYERS+1];
Address g_CachedSurvNavArea[MAXPLAYERS+1];
bool    g_SurvNavAreaComputed[MAXPLAYERS+1];
//float   g_GridEffectiveMinDist;

#define GRID_BUDGET_MS 20.0
#define GRID_SEARCH_RADIUS  150.0
#define GRID_MAX_Z_DIFF     100.0
#define GRID_MAX_CELLS      25
#define GRID_UPDATE_RATE    0.1

// State
Handle g_hGridTimer;
bool   g_bGridReady;

// Per-spawn flow marker state (same pattern as analog)
bool   g_bGridFlowUsed;
int    g_iGridTargetClient;
bool   g_bGridHint;
bool   g_bGridBatchMode;
bool   g_bGridSurvivorBeamDrawn;

// Cached validation results from last timer update
float  g_GridValidPositions[GRID_MAX_CELLS][3];
bool   g_GridValidFlags[GRID_MAX_CELLS];
int    g_GridCellIndices[GRID_MAX_CELLS];
int    g_GridCellCount;
int    g_GridValidCellCount;
float  g_GridClosestValidPos[3];
bool   g_GridHasValidCell;
int    g_GridValidCellIdx;

// Physics prop position overrides (runtime-adjusted positions on top of props)
float  g_GridOverridePositions[GRID_MAX_CELLS][3];
bool   g_GridHasOverride[GRID_MAX_CELLS];

// Per-update timing accumulators (reset each tick, read by perf log)
float  g_GridMs_obstruct;
float  g_GridMs_nav;
float  g_GridMs_los;
float  g_GridMs_dist;
int    g_GridN_obstructed;
int    g_GridN_nav;
int    g_GridN_los;
int    g_GridN_dist;
int    g_GridN_valid;

float t_vomited[MAXPLAYERS+1] = {0.0,...}; // tracking when to spawn horde

bool specials_frozen = false;
bool ZM_specials_frozen = false;

int autocommon_setting = AUTOCOMMON_OFF;
bool autocommon_uncommons = false;
int autocommon_num = 10;
float t_last_autocommon = 0.0;
float autocommon_updaterate = 2.0;

bool holdfinale = true; // hold finale stages until ZM runs out of resources. if not let stages change ASAP

int g_ExplosionSprite = -1;

bool meme_delivered = false;
//bool lipsync_available = false; // custom funny louis and ellis voice lines

int first_tank_stage = 0;
int first_tank_price = 0;

int g_iLaser = 0;
int g_iHalo = 0;

ConVar g_hCvarMPGameMode;
char g_sCvarMPGameMode[32];

// Notify ZM about being able to control units with USE
bool zm_use_notify = false;
// Notify ZM about being able to spawn zombies automatically by looking at survivors.
bool zm_flow_notify = false; // "Flow hint"
//bool g_bFlowSurvivorGlowActive = false; // True when a flow survivor glow entity exists
// Notify ZM about maximum Tank discount.
bool zm_discount_notify = false; // "Max tank discount"

ConVar g_hBankRateBase, g_hBankRatePlayer, g_hBankInitial, g_hBankInitialPlayer, g_hStopInactivity, g_hMaxUniqueSI, g_hRandomizer, g_hNoTanks,
       g_hUpdateRate, g_hMaxCommons, g_hSpawnMinDistance, g_hBonusCarAlarm, g_hBonusFinaleStage, g_hPanicCost, g_hBonusSurvival, g_hAbilityCooldown,
       g_hCostBoomer, g_hCostSpitter, g_hCostHunter, g_hCostSmoker, g_hCostJockey, g_hMaxWitches, g_hMaxSI, g_hSpecialCooldown, g_hNoZMWarn,
       g_hCostCharger, g_hCostTank, g_hCostWitchStatic, g_hCostWitchMoving, g_hCostCommon, g_hCostUncommon, g_hLockSaferoom,
       g_hCommonRate, g_hWitchCooldown, g_hTankCooldown, g_hMinFinaleStage, g_hPanicDuration, g_hFairQueue, g_hFairQueueWait, g_hPanicRateMultiplier,
       g_hMenuTimeout, g_hDiscountTank, g_hMemes, g_hClownGlow, g_hForceCommon, g_hHoldFinale, g_hZMGamemode, g_hVomitCommons, g_hAllowFreeze,
       g_hGridSearchRadius, g_hGrid, g_hSpawnerMode, g_hPanicRefill, g_hCursed;

float g_fBankRateBase,g_fBankRatePlayer,g_fUpdateRate,g_fSpawnMinDistance,g_fStopInactivity,g_fSpecialCooldown, g_fPanicRateMultiplier,
g_fCommonRate, g_fWitchCooldown, g_fTankCooldown, g_fMinFinaleStage, g_fPanicDuration, g_fFairQueueWait, g_fMenuTimeout,
g_fGridSearchRadius, g_fAbilityCooldown;

bool g_bFairQueue, g_bDiscountTank, g_bMemes, g_bClownGlow, g_bAllowFreeze;
char g_sForceCommon[32];

char g_sZMGamemode[PLATFORM_MAX_PATH];

int g_iBankInitial,g_iBankInitialPlayer, g_iPanicCost, g_iVomitCommons;

int costs_SI[9];
int live_zombie_arr[9];
int available_SI;
int available_zombie_arr[9];
float timestamp_available_arr[9];
int max_zombie_arr[9];
int g_iCostCommon, g_iCostUncommon, g_iCostWitchStatic, g_iCostWitchMoving, g_iBonusCarAlarm,
g_iBonusFinaleStage, g_iBonusSurvival, g_iMaxWitches, g_iMaxSI, g_iMaxUniqueSI;

bool g_bLockSaferoom, g_bGrid;
int g_iSpawnerMode;

int info_director = -1;

// Scattered globals (moved from between functions in main file)
bool playcount_increased, g_bPanicRefill = false;
int entref_control = INVALID_ENT_REFERENCE; // track the last special infected ZM looked at
int entref_delete = INVALID_ENT_REFERENCE; // track the last zombie ZM looked at
int entref_lastlook = INVALID_ENT_REFERENCE;
int g_iLockedDoor = INVALID_ENT_REFERENCE;

// Pre-computed navmeshes storage
ArrayList g_hStartAreaList; // ArrayList of PreCalcNav structs
bool g_bNavReady = false;    // Is pre-computation complete?

ConVar g_hSayHorde;

float commons_add = 0.0; // in case rate is very slow

// Prep time for coop only
ConVar g_hPrepTimeZM;
float g_fPrepTimeZM;
float t_zm_join = 0.0;

float saferoom_cooldown = 5.0;
bool saferoom_locked = false;
float t_last_join = 0.0;

// Kick AFK ZM due to inactivity
float t_zm_activity = 0.0;
bool zm_kick_notify = false;

int bank_track_numplayers = 0; //tracking if more bank should be added when more survivors appear

int prev_finaleType = -1;

float zm_deathPos[3], zm_deathAngles[3];

int old_scope0, old_scope1, old_scope2, old_scope3, old_scope4;

float t_last_hitmarker = 0.0;

StringMap g_Steam;
bool fair_exhausted = false; // let anyone become ZM if true
int client_offer = -1;
float t_offer = 0.0;
int roundcount_offer = -1;
bool clients_offered[MAXPLAYERS+1] = {false,...}; // manual array in case steam auth fails

int color_blocked[4] = {255,0,0,128};
int color_conditional[4] = {0,0,255,128};
int color_allowed[4] = {0,255,0,128};
int color_unit_select[4] = {255,255,255,128};

float zm_target_pos[3], zm_spawner_pos[3], spawner_last_valid_pos[3];
bool spawner_last_valid = false;
Address zm_spawner_navArea;
//float zm_spawner_navSize[3];
//float zm_spawner_navCenter[3]; // for future use in ZM_Horde
int zm_spawner_state;
float t_last_spawner_update; // analog spawner
float t_last_spawner_grid_update; // grid spawner
float t_last_spawner_sound;

int spawner_nearest_survivor = -1;
float latest_distance = 0.0;

TopMenu hAdminMenu = null;
TopMenuObject obj_zmcommands, zm_enable, zm_gamemode_menu, zm_kick_topmenu, zm_randomizer, zm_sayhorde, zm_help, zm_random;

int zm_menu_state = ZM_MENU_CLOSED;
Menu menu_main,menu_common,menu_uncommon,menu_special,menu_boss,menu_cleanup,menu_other,menu_autocommon = null;

// Data structure for player stats
enum struct zm_data
{
	int rounds;          // number of rounds played as ZM
	int last_roundcount; // last internal roundcount value where they played as ZM
	bool offered;        // track if offered at round start
}

// Navmesh struct
enum struct PreCalcNav
{
	float position[3];     // World position
	Address navArea;       // Nav area reference
}

int g_iGlowList[MAXENTITIES+1] = {INVALID_ENT_REFERENCE, ...}; // track glow children of parent entities

void GetCvars()
{
    if (DEBUG) LogMessage("[zm] GetCvars");
    g_fUpdateRate = g_hUpdateRate.FloatValue;
    ResetTimer();
    
    DEBUG = g_hCvarDebug.BoolValue || DEBUG;
    
    g_fBankRateBase = g_hBankRateBase.FloatValue;
    g_fBankRatePlayer = g_hBankRatePlayer.FloatValue;
    g_iBankInitial = g_hBankInitial.IntValue;
    g_iBankInitialPlayer = g_hBankInitialPlayer.IntValue;
    max_zombie_arr[ZOMBIECLASS_COMMON] = g_hMaxCommons.IntValue;
    g_fSpawnMinDistance = g_hSpawnMinDistance.FloatValue;
    g_fGridSearchRadius = g_hGridSearchRadius.FloatValue;
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
    g_iBonusSurvival = g_hBonusSurvival.IntValue;
    
    g_iPanicCost = g_hPanicCost.IntValue;
    g_fPanicDuration = g_hPanicDuration.FloatValue;
    
    g_bPanicRefill = g_hPanicRefill.BoolValue;
    
    g_bLockSaferoom = g_hLockSaferoom.BoolValue;
    
    g_fPrepTimeZM = g_hPrepTimeZM.FloatValue;
    
    g_fSpecialCooldown = g_hSpecialCooldown.FloatValue;
    g_fTankCooldown = g_hTankCooldown.FloatValue;
    g_fWitchCooldown = g_hWitchCooldown.FloatValue;
    g_fCommonRate = g_hCommonRate.FloatValue;
    
    g_fMinFinaleStage = g_hMinFinaleStage.FloatValue;
    
    g_bFairQueue = g_hFairQueue.BoolValue;
    if (!g_bFairQueue) fair_exhausted = true;
    g_fFairQueueWait = g_hFairQueueWait.FloatValue;
    g_fMenuTimeout = g_hMenuTimeout.FloatValue;
    
    g_bDiscountTank = g_hDiscountTank.BoolValue;
    g_bMemes = g_hMemes.BoolValue;
    g_bClownGlow = g_hClownGlow.BoolValue;
    
    g_hForceCommon.GetString(g_sForceCommon, sizeof(g_sForceCommon));
    TrimString(g_sForceCommon);
    
    holdfinale = g_hHoldFinale.BoolValue;
    
    g_iVomitCommons = g_hVomitCommons.IntValue;
    
    g_bAllowFreeze = g_hAllowFreeze.BoolValue;
    if (!g_bAllowFreeze) ZM_specials_frozen = false;
    
    if (g_iCostUncommon<0) autocommon_uncommons = false;
    else if (g_iCostCommon<0) autocommon_uncommons = true;
    if (autocommon_num>g_hMaxCommons.IntValue) autocommon_num = g_hMaxCommons.IntValue;
    
    g_fPanicRateMultiplier = g_hPanicRateMultiplier.FloatValue;
    
    if (g_hGrid.BoolValue!=g_bGrid)
    {
        if (g_bGrid && IsValidClientZM()) Spawner_OnDisabled(zm_client); 
        g_bGrid = g_hGrid.BoolValue && hGetClusterForOrigin!=null && l4dhooks_updated;
        if (g_bGrid && L4D_HasMapStarted() && !GridLib_IsReady())
        {
            GridLib_Initialize();
            GridLib_StartPrecomputation();
        }
        if (g_bGrid!=g_hGrid.BoolValue) SetConVarBool(g_hGrid,g_bGrid);
    }
    if (!g_bGrid) g_iSpawnerMode = 0;
    
    g_fAbilityCooldown = g_hAbilityCooldown.FloatValue;
}

Action ZM_MOTD(int client, int args)
{ 
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Continue;

    PrintToChat(client, "[zm] See console.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== ZOMBIE MASTER %s TUTORIAL ===", PLUGIN_VERSION);
    PrintToConsole(client, "Welcome to Left 4 Dead 2 Zombie Master!");
    PrintToConsole(client, "Visit the Steam Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3660216145");
    PrintToConsole(client, "Before every round starts, one player, the Zombie Master, is selected to control all zombies.");
    PrintToConsole(client, "IMPORTANT: Please enable Freelook Camera in Options -> Multiplayer!!!");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 1. Spawning Zombies ===");
    PrintToConsole(client, "Zombies can be spawned with the sourcemod menu, or with chat/console commands (Section 3).");
    PrintToConsole(client, "A spawner (3 circles) shows where you are pointing (or the nearest valid location). This is where zombies will spawn.");
    PrintToConsole(client, "The spawner can be in 1 of 4 states:");
    PrintToConsole(client, "1. GREEN -> Zombies can be spawned NOW!");
    PrintToConsole(client, "2. BLUE -> Zombies can be spawned, but not now. Usually because survivors are too close or they can see.");
    PrintToConsole(client, "3. RED -> Zombies can NEVER be spawned here.");
    PrintToConsole(client, "4. FLOW (long vertical blue stripe) -> Zombie locations were picked automatically.");
    PrintToConsole(client, "To activate FLOW: look at a survivor OR the ground next to them OR spectate that survivor; then, spawn zombies.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 2. Keyboard Shortcuts ===");
    PrintToConsole(client, "USE (default E) -> Control/Release Special Infected.");
    PrintToConsole(client, "FLASHLIGHT (default F) -> Flashlight.");
    PrintToConsole(client, "RELOAD (default R) -> once to open main menu; twice to close menu and hide spawner.");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 3. Chat/Console Commands ===");
    PrintToConsole(client, "/zm_vote -> Vote to enable/disable Zombie Master.");
    PrintToConsole(client, "/zm_gamemode_menu -> Gamemode menu for clients and admins.");
    PrintToConsole(client, "/zm -> become ZM OR open menu and enter free look.");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_horde n type angry flow");
    PrintToConsole(client, "optional type: riot ceda clown mud road random");
    PrintToConsole(client, "optional angry: chase survivors on spawn even if PANIC is OFF. More expensive than non-angry variant.");
    PrintToConsole(client, "optional flow: spawn in a random place ahead of furthest survivor instead of spawner position.");
    PrintToConsole(client, "The order of arguments doesn't matter. For example, zm_horde '50 angry clown' and zm_horde 'clown angry 50' gives the same result.");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_witch n flow");
    PrintToConsole(client, "n=0 static, n=1 moving");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_boomer flow");
    PrintToConsole(client, "/zm_spitter flow");
    PrintToConsole(client, "/zm_smoker flow");
    PrintToConsole(client, "/zm_hunter flow");
    PrintToConsole(client, "/zm_jockey flow");
    PrintToConsole(client, "/zm_charger flow");
    PrintToConsole(client, "/zm_tank flow");
    PrintToConsole(client, "");
    PrintToConsole(client, "/zm_panic -> Start PANIC");
    PrintToConsole(client, "/zm_start -> (1x) Unlock saferoom (2x) Force saferoom open (3x) Instantly open saferoom.");
    PrintToConsole(client, "/zm_delete -> Delete single unit where you are pointing indicated by a white circle.");
    PrintToConsole(client, "/zm_delete_all -> delete ALL zombies");
    PrintToConsole(client, "/zm_delete_common -> delete all commons/uncommons");
    PrintToConsole(client, "/zm_delete_specials -> delete all Special Infected");
    PrintToConsole(client, "/zm_delete_witches");
    PrintToConsole(client, "/zm_quit -> Give Up and join Survivors.");
    PrintToConsole(client, "/zm_teleport -> teleport to survivor with most progress.");
    PrintToConsole(client, "/zm_menu x -> main common uncommon special boss cleanup other close");
    PrintToConsole(client, "/zm_freeze -> Freeze/Unfreeze Special Infected units. Useful for setting up ambushes.");
    PrintToConsole(client, "/zm_autocommon_mode x -> off panic always. Sets AutoCommon system mode.");
    PrintToConsole(client, "/zm_autocommon_max n -> Set zombie cap for AutoCommon system.");
    PrintToConsole(client, "");
    PrintToConsole(client, "You can bind all of the commands above! For example: bind KP_MINUS 'zm_horde 10 flow'");
    
    PrintToConsole(client, "");
    PrintToConsole(client, "=== 4. Gameplay Tips ===");
    PrintToConsole(client, "1. Go to Common -> AutoCommon. Set mode to ALWAYS, and max to 30. This will spawn common zombies ahead of the Survivors automatically.");
    PrintToConsole(client, "2. Use Freeze SI/Unfreeze SI to set up ambushes. All Specials unfreeze automatically when one notices a Survivor. Press the USE key to fine-tune placement and view angle.");
    PrintToConsole(client, "3. In coop, you get %d seconds of prep time. Specials will be frozen. To end prep, type /zm_start or go to Other -> Start Round.", RoundFloat(g_fPrepTimeZM));
    PrintToConsole(client, "4. PANIC will make common and uncommon infected chase survivors, reducing your bank rate by 4x. Finales, survival, and scripted panic events give free PANIC.");
    PrintToConsole(client, "5. When a Boomer vomits on a survivor, %d free zombies will be spawned. Use this to your advantage!", g_iVomitCommons);
    PrintToConsole(client, "6. Car alarms give free PANIC, free common zombies, and free bank. Trick the survivors into starting them!");
    PrintToConsole(client, "7. During Survival and Finales, bank is added in stages: in Survival when Tanks die, in Finales when you run out of bank.");
    PrintToConsole(client, "7. In coop, when Tanks are not banned, the first Tank gets progressively cheaper: up to 50% off when Survivors progress 2/3 of the map.");
    PrintToConsole(client, "8. Units with full HP can be deleted to get a refund. You cannot refund: spotted witches, Specials that used their ability.");
    
    if (CheckCommandAccess(client,"is_a_sm_admin",ADMFLAG_GENERIC,true))
    {
        PrintToConsole(client, "");
        PrintToConsole(client, "=== 5. Admin commands ===");
        PrintToConsole(client, "/zm_addbank");
        PrintToConsole(client, "/zm_kick");
        PrintToConsole(client, "");
        PrintToConsole(client, "=== 6. CVARS ===");
        PrintToConsole(client, "Compatible mp_gamemode: coop l4d1coop survival l4d1survival.");
        PrintToConsole(client, "sm_cvar zm_gamemode sets the .cfg file that is read in cfg/sourcemod/l4d2_zombie_master/.");
        
        char name[64];
        char value[64];
        bool isCommand;
        int flags;
        ConVar cvar;
        Handle iter = FindFirstConCommand(name,sizeof(name),isCommand,flags);
        if (iter != null)
        {
            do
            {
                if (!isCommand && StrContains(name,"zm_",false)==0)
                {
                    cvar = FindConVar(name);
                    cvar.GetString(value, sizeof(value));
                    PrintToConsole(client, "%s %s", name, value);  
                }
            }
            while (FindNextConCommand(iter,name,sizeof(name),isCommand,flags));
        }
        CloseHandle(iter);
    }
    
    PrintToConsole(client, "");
    PrintToConsole(client, "For more information, and to install Zombie Master for your own server, go here:");
    PrintToConsole(client, "https://forums.alliedmods.net/showthread.php?t=352060");
    PrintToConsole(client, "https://github.com/gvazdas/l4d2_zombie_master");
    PrintToConsole(client, "Visit the Steam Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3660216145");
    PrintToConsole(client, "=== ZOMBIE MASTER TUTORIAL END ===");
    PrintToConsole(client, "");
   
    return Plugin_Continue;
}


void update_t_zm_activity(float new_t = -1.0)
{
    zm_kick_notify = false;
    if (new_t<0.0) t_zm_activity = GetGameTime();
    else t_zm_activity = new_t;
}

bool is_zm_spamming()
{
    float t_now = GetGameTime();
    if ( (t_now-t_last_action)<=0.11 ) // typical tickrate is 30
    {
        update_hint("%T", "STOP SPAMMING", zm_client);
        t_last_action = t_now;
        return true;
    }
    t_last_action = t_now;
    return false;
}

stock void get_zombieclass_name(int ZOMBIECLASS, char name[32])
{
    switch(ZOMBIECLASS)
    {
        case ZOMBIECLASS_COMMON: name = "Common";
        case ZOMBIECLASS_SMOKER: name = "Smoker";
        case ZOMBIECLASS_BOOMER: name = "Boomer";
        case ZOMBIECLASS_HUNTER: name = "Hunter";
        case ZOMBIECLASS_SPITTER: name = "Spitter";
        case ZOMBIECLASS_JOCKEY: name = "Jockey";
        case ZOMBIECLASS_CHARGER: name = "Charger";
        case ZOMBIECLASS_WITCH: name = "Witch";
        case ZOMBIECLASS_TANK: name = "Tank";
        default: Format(name, sizeof(name), "Unknown(%d)", ZOMBIECLASS);
    }
}

bool hit_trigger;
// Check if navArea is legal for zombies. Allow witches to be spawned in weird places
// You may provide all attributes or automatically get them from navArea.
stock bool nav_can_spawn_zombies(const int zClass = ZOMBIECLASS_COMMON,
                                 Address navArea = Address_Null,
                                 int &navAttributeFlags = -1, int &navSpawnAttributes = -1,
                                 float navCenter[3] = {0.0,0.0,0.0}, float navSize[3] = {0.0,0.0,0.0})
{
    if (navArea!=Address_Null && l4dhooks_updated && L4D_NavArea_IsBlocked(navArea,TEAM_INFECTED,false)) return false;
    if (navAttributeFlags<0) navAttributeFlags = L4D_GetNavArea_AttributeFlags(navArea);
    if (navSpawnAttributes<0) navSpawnAttributes = L4D_GetNavArea_SpawnAttributes(navArea);
    //if (navSpawnAttributes&NAV_SPAWN_EMPTY && navSpawnAttributes&NAV_SPAWN_NOTHREAT) return false;
    if (zClass!=ZOMBIECLASS_WITCH)
    {
        if (navAttributeFlags & NAV_BASE_OUTSIDE_WORLD) return false;
        if (navSpawnAttributes & NAV_SPAWN_BATTLESTATION) return false;
    }
    // some Valve maps have messed up navmeshes: rescue closets in crazy places, survivor player start in finale areas...
    if (navSpawnAttributes & NAV_SPAWN_BATTLEFIELD) return true;
    if (navSpawnAttributes & NAV_SPAWN_FINALE) return true;
    if (navAttributeFlags & NAV_BASE_MOB_ONLY) return true;
    if (navAttributeFlags & NAV_BASE_TANK_ONLY) return true;
    if (navSpawnAttributes & NAV_SPAWN_PLAYER_START) return false;
    if (navSpawnAttributes & NAV_SPAWN_CHECKPOINT) return false;
    if (navSpawnAttributes & NAV_SPAWN_ESCAPE_ROUTE) return true;
    if (navSpawnAttributes & NAV_SPAWN_OBSCURED || navSpawnAttributes & NAV_SPAWN_IGNORE_VISIBILITY) return true;
    if (navSpawnAttributes&NAV_SPAWN_EMPTY && navSpawnAttributes&NAV_SPAWN_NO_MOBS && navSpawnAttributes&NAV_SPAWN_NOTHREAT)
    {
        if (navArea!=Address_Null && navSize[0]==0.0 && navSize[1]==0.0)
        {
            L4D_GetNavAreaCenter(navArea,navCenter);
            L4D_GetNavAreaSize(navArea,navSize);
        }
        int hurt = INVALID_ENT_REFERENCE; // Look for trigger hurt to prevent spawning zombies that will die.
        if (l4dhooks_updated)
        {
            while( (hurt = L4D_FindEntityByClassnameWithin(hurt,"trigger_hurt",navCenter,500.0)) != INVALID_ENT_REFERENCE )
            {
                return false;
            }
        }
        else
        {
            while ( ((hurt = FindEntityByClassname(hurt, "trigger_hurt")) != INVALID_ENT_REFERENCE) )
            {
                hit_trigger = false;
                TR_EnumerateEntitiesSphere(navCenter,500.0,PARTITION_TRIGGER_EDICTS,HitTrigger);
                if (hit_trigger) return false;
                break;
            }
        }
    }
    if (navSpawnAttributes & NAV_SPAWN_RESCUE_CLOSET)
    {
        if (l4dhooks_updated) // Verify info_survivor_rescue
        {
            if (navArea!=Address_Null && navSize[0]==0.0 && navSize[1]==0.0)
            {
                L4D_GetNavAreaCenter(navArea,navCenter);
                L4D_GetNavAreaSize(navArea,navSize);
            }
            float abs_x = FloatAbs(navSize[0]);
            float abs_y = FloatAbs(navSize[1]);
            if (abs_x>0.0 || abs_y>0.0)
            {
                int entity = INVALID_ENT_REFERENCE; // should use 2d vector length of sizes/2 but sqrt is slow
                float radius = (abs_y>abs_x) ? abs_y : abs_x;
                while( (entity = L4D_FindEntityByClassnameWithin(entity,"info_survivor_rescue",navCenter,radius)) != INVALID_ENT_REFERENCE )
                {
                    return false;
                }
            }
            return true;
        }
        return false;
    }
    return true;
}

// trigger_hurt detection callback
bool HitTrigger(int entity, int &hit) // return true to continue enumerating, or false to stop
{
    //if (entity<=0 || !IsValidEntity(entity)) return true;
    static char classname[64];
    GetEntityClassname(entity,classname,sizeof(classname));
    //LogMessage("HitTrigger %d %s", entity, classname);
    if (strcmp(classname,"trigger_hurt",false)==0)
    {
        hit_trigger = true;
        return false;
    }
    return true;	
}

// Filter to only consider trigger_hurt entities
public bool FilterTriggerHurt(int entity, int contentsMask)
{
    if (entity <= 0 || !IsValidEntity(entity)) return false; 
    static char className[64];
    GetEntityClassname(entity, className, sizeof(className));
    LogMessage("FilterTriggerHurt %s", className);
    return strcmp(className,"trigger_hurt")==0;
}

// True to allow the current entity to be hit, otherwise false.
stock bool FilterSpawner(int entity, int mask, int self)
{
	if (!IsValidEntity(entity)) return false;
	if (entity==self) return false;
	if (GetEntProp(entity,Prop_Data,"m_iHealth")>0) return false;
	if (IsValidClient(entity) && !IsPlayerAlive(entity)) return false;
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

stock void get_finale_label(int finaleType, char label[32])
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


bool PlaySceneOnSurvivor(int survivor, const char[] sceneFile)
{
	int scene = CreateEntityByName("instanced_scripted_scene");
	if (!IsEntitySafe(scene)) return false;
	DispatchKeyValue(scene, "SceneFile", sceneFile);
	DispatchSpawn(scene);
	SetEntPropEnt(scene, Prop_Data, "m_hOwner", survivor);
	AcceptEntityInput(scene, "Start", survivor, survivor);
	HookSingleEntityOutput(scene, "OnCompletion", OnSceneComplete, true);
	CreateTimer(SCENE_SAFETY_TIMEOUT, Timer_KillScene, EntIndexToEntRef(scene));
	return true;
}



void OnSceneComplete(const char[] output, int caller, int activator, float delay)
{
	if (IsValidEntity(caller)) RemoveEntity(caller);
}

Action Timer_KillScene(Handle timer, int sceneRef)
{
	int scene = EntRefToEntIndex(sceneRef);
	if (scene != INVALID_ENT_REFERENCE && IsValidEntity(scene)) RemoveEntity(scene);
	return Plugin_Stop;
}

Action random_meme(Handle timer = null, bool francis = false)
{
	if (!g_bMemes || (!francis && meme_delivered) || force_started) return Plugin_Stop;
	int i;
	ArrayList listplayers = new ArrayList();
	for (i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i)!=TEAM_SURVIVOR) continue;
		if (L4D_IsPlayerIncapacitated(i)) continue;
		listplayers.Push(i); 
	}
	if (listplayers.Length<=0)
	{
    	delete listplayers;
    	return Plugin_Stop;
	}
	
	int scene;
	ArrayList actors = new ArrayList();
	while ( ((scene = FindEntityByClassname(scene, "instanced_scripted_scene")) != -1) )
    {
    	   i = GetEntPropEnt(scene, Prop_Data, "m_hOwner");
    	   if (!IsValidClient(i)) continue;
    	   if (DEBUG) LogMessage("[zm] instanced_scripted_scene %d", i);
    	   actors.Push(i); 
    }
	
	listplayers.Sort(Sort_Random, Sort_Integer);
	char model[PLATFORM_MAX_PATH];
    char sound[PLATFORM_MAX_PATH];
    char soundFake[PLATFORM_MAX_PATH];
    //char vcdPath[PLATFORM_MAX_PATH];
    char PathFake[PLATFORM_MAX_PATH];
	for(int x = 0; x < listplayers.Length; x++)
    {
        i = listplayers.Get(x);
        if (actors.FindValue(i)>=0) continue;
        sound = "";
		GetClientModel(i, model, sizeof(model));
		if (!francis && StrContains(model,"survivor_mechanic",false)!=-1)
		{
    		//if (lipsync_available) sound = SOUND_ELLIS_ZM;
    		sound = SOUND_ELLIS_ZM_MP3;
    		//vcdPath = VCD_ELLIS_ZM;
    		soundFake = SOUND_ELLIS_ZM_FAKE;
    		PathFake = "scenes/mechanic/dlc1_communitye20.vcd";
		}
		else if (!francis && StrContains(model,"survivor_manager",false)!=-1)
		{
    		//if (lipsync_available) sound = SOUND_LOUIS_ZM;
            sound = SOUND_LOUIS_ZM_MP3;
    		//vcdPath = VCD_LOUIS_ZM;
    		soundFake = SOUND_LOUIS_ZM_FAKE;
    		PathFake = "scenes/manager/takesubmachinegun03.vcd";
		}
		else if (!francis && StrContains(model,"survivor_teenangst",false)!=-1)
		{
            sound = SOUND_ZOEY_ZM_MP3;
    		soundFake = SOUND_ZOEY_ZM_FAKE;
    		PathFake = "scenes/teengirl/dlc2steam01.vcd";
		}
		else if (!francis && StrContains(model,"survivor_gambler",false)!=-1)
		{
            sound = SOUND_NICK_ZM_MP3;
    		soundFake = SOUND_NICK_ZM_FAKE;
    		PathFake = "scenes/gambler/nickocd02.vcd";
		}
		else if (!francis && StrContains(model,"survivor_coach",false)!=-1)
		{
            sound = SOUND_COACH_ZM_MP3;
    		soundFake = SOUND_COACH_ZM_FAKE;
    		PathFake = "scenes/coach/worldc4m1b07.vcd";
		}
		else if (StrContains(model,"survivor_biker",false)!=-1)
		{
            sound = SOUND_FRANCIS_ZM_MP3;
    		soundFake = SOUND_FRANCIS_ZM_FAKE;
    		PathFake = "scenes/biker/worldsmalltown0311.vcd";
		}
		
		if ( sound[0]!=0 && GetRandomFloat(0.0,1.0)>=0.5 ) 
		{
    		if (DEBUG) LogMessage("[zm] Playing %d %s", i, sound);
    		meme_delivered = true;
    		//EmitSoundToAll(sound,i,SNDCHAN_VOICE,SNDLEVEL_SCREAMING,_,1.0);
    		EmitSoundToAll(soundFake,i,SNDCHAN_VOICE,SNDLEVEL_RUSTLE,_,0.0);
    		EmitSoundToAll(sound,i,SNDCHAN_AUTO,SNDLEVEL_SCREAMING,_,1.0);
    		//if (lipsync_available) PlaySceneOnSurvivor(i, vcdPath);
    		PlaySceneOnSurvivor(i,PathFake);
    		// Francis response
    		if (strcmp(sound,SOUND_FRANCIS_ZM_MP3,false)!=0) CreateTimer(GetRandomFloat(3.0,4.0),random_meme,true,TIMER_FLAG_NO_MAPCHANGE);
    		break;
		}
	}
	delete listplayers;
	delete actors;
	return Plugin_Stop;
}




Action zm_addbank(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] zm_addbank");
    if (args>0)
    {
        int add = GetCmdArgInt(1);
        bank += add;
        if (add!=0 && IsValidClientZM()) update_EMS_HUD();
    }
    return Plugin_Continue;
}

void set_bank_begin()
{
    if (g_iAliveSurvivors<=0) CountClients();
    if (L4D_IsSurvivalMode()) bank = g_iBonusSurvival*g_iAliveSurvivors;
    else
    {
        bank = g_iBankInitial;
        bank += g_iBankInitialPlayer*g_iAliveSurvivors;
    }
    bank_track_numplayers = g_iAliveSurvivors;
    bank_add = 0.0;
    commons_add = 0.0;
}

float get_bank_rate()
{
 
 bool zero_rate = L4D_IsSurvivalMode() || !L4D_HasAnySurvivorLeftSafeArea();
 float multiplier = 1.0;
 if (!zero_rate && ZM_finale_announced)
 {
     // Coop finale logic
     if (can_change_finale_stage()) L4D2Direct_SetPendingMobCount(0);
     else
     {
         // Hold pending mob to prevent stage advance!
         int pending_mob = L4D2Direct_GetPendingMobCount();
         if (script_CommonLimit>0 && pending_mob<script_CommonLimit)
            L4D2Direct_SetPendingMobCount(script_CommonLimit);
     }
     int current = L4D2_GetCurrentFinaleStage();
     if (current==FINALE_GAUNTLET_ESCAPE || current==FINALE_HORDE_ESCAPE)
     {
         // Infinite Finale
         zero_rate = false;
         multiplier = 2.0;
     }
     else if ( (current==FINALE_CUSTOM_CLEAROUT || current==FINALE_CUSTOM_SCRIPTED) &&
               (GetGameTime()-t_finale)>=g_fMinFinaleStage ) 
     {
         zero_rate = false;
     }
     else zero_rate = true;
 }
 
 if (zero_rate)
 {
     bank_rate = 0.0;
     return bank_rate;
 }
 
 // Coop logic
 float final_rate = g_fBankRateBase;
 if (g_iAliveSurvivors>0) final_rate += g_iAliveSurvivors*g_fBankRatePlayer;
 if (panic && manual_panic) final_rate *= g_fPanicRateMultiplier;
 bank_rate = multiplier*final_rate;
 return bank_rate;
}

Action ZM_Vision(int client, int args)
{
   toggle_ZM_vision(client);
   return Plugin_Continue;
}

int entref_light = INVALID_ENT_REFERENCE;
Action TransmitZMLight(int entity, int client)
{
	if (!IsValidClientZM()) AcceptEntityInput(entity, "Kill");
	if(client==zm_client) return Plugin_Continue;
	return Plugin_Handled;
}

// Update z position of ZM light if they are in free look vs spectating a target or alive.
void update_zm_flashlight()
{
    if (!IsValidEntRef(entref_light)) return;
    int entity = EntRefToEntIndex(entref_light);
    if (!IsValidEntity(entity)) return;
    if (!IsValidClientZM()) return;
    int observermode = GetEntProp(zm_client, Prop_Send, "m_iObserverMode");
    int lastlook = -1;
    if (observermode==4 || observermode==5)
        lastlook = GetEntPropEnt(zm_client, Prop_Send, "m_hObserverTarget");
    if (lastlook>0 && IsValidEntity(lastlook))
    {
        // Prevent flicker
        AcceptEntityInput(entity, "Kill");
    	entref_light = INVALID_ENT_REFERENCE;
    }
    else
    {
        if (IsPlayerAlive(zm_client))
        {
            float vMin[3], vMax[3], vOffset[3];
            GetEntPropVector(zm_client, Prop_Send, "m_vecMins", vMin);
            GetEntPropVector(zm_client, Prop_Send, "m_vecMaxs", vMax);
            vOffset[2] = vMax[2] - vMin[2] + 1.0;
            TeleportEntity(entity,
                           vOffset,
                           view_as<float>({ -45.0, -45.0, 90.0 }),
                           NULL_VECTOR);
        }
        else
        {
            TeleportEntity(entity,
                           view_as<float>({ 0.0, 0.0, 0.0 }),
                           view_as<float>({ 0.0, 0.0, 0.0 }),
                           NULL_VECTOR);
        }
    }
    
}

// l4d_flashlight by Silvers
void toggle_ZM_vision(int client)
{
    if (!g_bCvarAllow || !IsValidClient(client)) return;
    if (client!=zm_client) return;
    
    if (is_zm_spamming()) return;
    
    int entity;
    if (IsValidEntRef(entref_light)) entity = EntRefToEntIndex(entref_light);
    else entity = -1;
    
    if (!IsValidEntity(entity))
    {
        
        // No dynamic light when observing somebody. Prevents flicker.
        int observermode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if (observermode==4 || observermode==5) return;
        
        entity = CreateEntityByName("light_dynamic");
    	if( entity == -1) return;
        
       	DispatchKeyValue(entity, "_light", "5 5 5 5");
       	DispatchKeyValue(entity, "brightness", "1");
       	DispatchKeyValueFloat(entity, "spotlight_radius", 0.0);
       	DispatchKeyValueFloat(entity, "distance", 3000.0);
       	DispatchKeyValue(entity, "style", "0");
       	DispatchSpawn(entity);
       	AcceptEntityInput(entity, "TurnOn");
       	SetVariantString("!activator");
       	AcceptEntityInput(entity, "SetParent", client);
       	TeleportEntity(entity,
                       view_as<float>({ 0.0, 0.0, 0.0 }),
                       view_as<float>({ 0.0, 0.0, 0.0 }),
                       NULL_VECTOR);
		entref_light = EntIndexToEntRef(entity);
		SDKHook(entity, SDKHook_SetTransmit, TransmitZMLight);
		update_zm_flashlight();
    }
	else
	{
    	AcceptEntityInput(entity, "Kill");
    	entref_light = INVALID_ENT_REFERENCE;
	}
	
    EmitSoundToClient(client,SOUND_VISION);
}

stock void process_horde_arg(int &count, char type[16], bool &angry, bool &flow, char arg[16])
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

bool TraceFilter_Looktarget(int entity, int contentsMask)
{
	if (entity==zm_client || entity<=0) return false;
	if (IsValidClient(entity) && IsPlayerAlive(entity)) return true;
	char class[32];
    GetEntityClassname(entity, class, sizeof(class));
    switch (class[0])
    {
        case 'i': { if (strcmp(class,"infected")==0) return true; }
        case 'w': { if (strcmp(class,"witch")==0) return true; }
    }
	return false;
}

// TraceFilter for ZM Spawner: GREEN only in empty space WITHOUT specials and WITHOUT witches.
bool TraceFilter_Spawner(int entity, int contentsMask, int ignore_entity)
{
	if (entity==ignore_entity) return false;
	if (entity==0) return true;
	if (IsValidClient(entity))
	{
	 if (IsValidClient(ignore_entity) && GetClientTeam(entity)==TEAM_SURVIVOR && GetClientTeam(ignore_entity)==TEAM_SURVIVOR)
    	 return false; // survivors wont get stuck in other survivors.
	 if (IsPlayerAlive(entity)) return true;
	}
	if (entity>MaxClients)
	{
    	if (GetEntProp(entity, Prop_Data, "m_nSolidType")==0) return false;
    	static char class[32];
        GetEntityClassname(entity, class, sizeof(class));
        if (strcmp(class,"infected")==0) return false;
        if (strcmp(class,"env_player_blocker")==0) return false;
        //if (strcmp(class,"witch")==0) return false; // restrict dirty witch placement
        if (strcmp(class,"env_physics_blocker")==0) return false;
    	   return true;
	}
	return true;
}

// TraceFilter for predicting if an infected entity might be stuck: ignore infected, witches and special infected
bool TraceFilter_Stuck_IgnoreZombies(int entity, int contentsMask, int ignore_entity)
{
	if (entity==ignore_entity) return false;
	if (entity==0) return true;
	if (IsValidClient(entity))
	{
	 if (IsValidClient(ignore_entity) && GetClientTeam(entity)==TEAM_SURVIVOR && GetClientTeam(ignore_entity)==TEAM_SURVIVOR)
    	 return false; // survivors wont get stuck in other survivors.
     if (GetClientTeam(entity)==TEAM_INFECTED) return false; // ignore all clients on infected team
     if (!IsPlayerAlive(entity)) return false;
	}
	else if (IsValidEntity(entity))
	{
    	static char class[32];
        GetEntityClassname(entity, class, sizeof(class));
	    switch (class[0])
        {
            case 'e':
            {
                if (strcmp(class,"env_player_blocker")==0) return false;
                if (strcmp(class,"env_physics_blocker")==0) return false;
            }
            case 'i':
            {
                if (strcmp(class,"infected")==0) return false;
            }
            case 'w':
            {
                if (strcmp(class,"witch")==0) return false;
            }
        }
	}
	return true;
}

// IsObstructed checks for ZM spawner (ignore_zombies=false) or to determine if a zombie will be stuck in that position (ignore_zombies=true)
int g_iObstructingEntity;
stock bool IsObstructed(float pos[3], int entity = -1, bool debug=false, bool ignore_zombies = false)
{
    bool isObstructed = false;
    g_iObstructingEntity = -1;
    Handle hullTrace;
    if (ignore_zombies) hullTrace = TR_TraceHullFilterEx(pos,pos,HULL_MINS,HULL_MAXS,MASK_NPCSOLID,TraceFilter_Stuck_IgnoreZombies,entity);
    else hullTrace = TR_TraceHullFilterEx(pos,pos,HULL_MINS,HULL_MAXS,MASK_NPCSOLID,TraceFilter_Spawner,entity);
	if (TR_DidHit(hullTrace))
	{
		g_iObstructingEntity = TR_GetEntityIndex(hullTrace);
    	if (debug)
    	{
		     static char classname[64];
             GetEntityClassname(g_iObstructingEntity, classname, sizeof(classname));
             LogMessage("IsObstructed hit %d %s", g_iObstructingEntity, classname);
        }
		if (g_iObstructingEntity == 0) // Hit world
		{
			//int hullSurfaceFlags = TR_GetSurfaceFlags(hullTrace);
			//if (!(hullSurfaceFlags & SURF_NODRAW) && !(hullSurfaceFlags & SURF_HINT) && !(hullSurfaceFlags & SURF_SKIP))
        	//		isObstructed = true;
        	//isObstructed = hullSurfaceFlags
        	// try checking both ways? idk what else could be done.
        	isObstructed = true;
		}
		else if (IsValidEntity(g_iObstructingEntity)) isObstructed = true;
	}
	delete hullTrace;
	//LogMessage("IsObstructed %d %d %.1f %.1f %.1f", isObstructed, entity, pos[0], pos[1], pos[2]);
	return isObstructed;
}

// Check if a position is obstructed specifically by a physics prop.
// If so, returns true and sets hitPropRef to the entity index.
stock bool IsObstructedByPhysicsProp(float pos[3], int &hitPropRef = -1)
{
    Handle hullTrace = TR_TraceHullFilterEx(pos, pos, HULL_MINS, HULL_MAXS,
                                            MASK_NPCSOLID, TraceFilter_Spawner, -1);
    bool result = false;
    if (TR_DidHit(hullTrace))
    {
        int hitEntity = TR_GetEntityIndex(hullTrace);
        if (hitEntity > MaxClients && IsValidEntity(hitEntity))
        {
            static char className[32];
            GetEntityClassname(hitEntity, className, sizeof(className));
            if (strncmp(className, "prop_physics", 12) == 0 ||
                StrEqual(className, "prop_car_alarm"))
            {
                hitPropRef = hitEntity;
                result = true;
            }
        }
    }
    delete hullTrace;
    return result;
}

// Trace filter that only hits a specific entity
static int g_TraceFilter_TargetEntity = -1;

bool TraceFilter_OnlyTargetEntity(int entity, int contentsMask)
{
    return (entity == g_TraceFilter_TargetEntity);
}

// Find the top Z coordinate of a physics prop at a given XY position.
// Traces downward from above to find the prop's top surface.
stock float GetPhysicsPropTopZ(int entity, const float pos[3])
{
    float startPos[3], endPos[3];
    startPos[0] = pos[0];
    startPos[1] = pos[1];
    startPos[2] = pos[2] + 200.0;
    endPos[0] = pos[0];
    endPos[1] = pos[1];
    endPos[2] = pos[2] - 50.0;

    g_TraceFilter_TargetEntity = entity;
    Handle trace = TR_TraceRayFilterEx(startPos, endPos, MASK_NPCSOLID,
                                       RayType_EndPoint, TraceFilter_OnlyTargetEntity);

    float topZ = pos[2];
    if (TR_DidHit(trace))
    {
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);
        topZ = hitPos[2];
    }

    delete trace;
    g_TraceFilter_TargetEntity = -1;
    return topZ;
}

// Attempt to rescue obstruction by moving vPos upwards.
// Supply entity that should be ignored if needed.
// We check the hull of the obstructing entity and set vPos[2] to the max height of the obstructing entity.
// Do not rescue if obstruction is player, infected or witch to prevent vertical stacking abuse.
// return: true if rescue was successful.
bool obstruction_rescue_hull_up(float vPos[3], int entity = -1, int zClass = ZOMBIECLASS_BOOMER)
{
    bool rescued = false;
    int memory = g_iObstructingEntity; // IsObstructed will overwrite g_iObstructingEntity... i am an idiot sandwich
    static float newPos[3];
    if (g_iObstructingEntity>0)
    {
        static char className[8];
        GetEntityClassname(g_iObstructingEntity,className,sizeof(className));
        switch (className[0])
        {
            case 'i':
            {
                if (strcmp(className,"infected",false)==0) return false;
            }
            case 'w':
            {
                if (strcmp(className,"witch",false)==0) return false;
            }
            case 'p':
            {
                if (strcmp(className,"player",false)==0) return false;
            }
        }
        static float vPos_obstructing[3], vMaxs[3];
        GetEntPropVector(g_iObstructingEntity, Prop_Send, "m_vecMaxs", vMaxs);
        GetEntPropVector(g_iObstructingEntity, Prop_Send, "m_vecOrigin", vPos_obstructing);
        newPos = vPos;
        newPos[2] = vPos_obstructing[2] + vMaxs[2] + 1.0;
        if (!IsObstructed(newPos,entity,_,zClass==ZOMBIECLASS_COMMON))
        {
            vPos = newPos;
            rescued = true;
        }
        g_iObstructingEntity = memory;
    }
    else if (g_iObstructingEntity==0) // hit world - unclear how much we should move up
    {
        newPos = vPos;
        newPos[2] += HULL_DZ_MIN_STRICT;
        if (!IsObstructed(newPos,entity,_,zClass==ZOMBIECLASS_COMMON))
        {
            vPos = newPos;
            rescued = true;
        }
        g_iObstructingEntity = memory;
    }
    return rescued;
}

// for known obstructed pos, try adjusting position slightly
// optional: navArea and center for try_center, try_random
// optional: zClass to determine if ignore_zombies is used for relaxed obstruction checks
// optional: entity to ignore
// true on success, false on failure
// future: make this more useful
stock bool try_adjusting_obstructed_pos(float pos[3], int entity = -1, int zClass = ZOMBIECLASS_BOOMER,
                                        Address navArea=Address_Null, float center[3]={0.0,0.0,0.0},
                                        bool try_up = true,
                                        bool try_center = true, bool try_center_up = true,
                                        bool try_random = true, bool try_random_up = true)
{
    bool ignore_zombies = zClass==ZOMBIECLASS_COMMON;
    float new_pos[3];
    if (try_up)
    {
        if (obstruction_rescue_hull_up(pos,entity,zClass)) return true;
    }
    
    if (try_center && center[0]!=0.0 && center[1]!=0.0)
    {
        if (!IsObstructed(center,entity,_,ignore_zombies))
        {
            pos = center;
            return true;
        }
        else if (try_center_up)
        {
            if (obstruction_rescue_hull_up(center,entity,zClass))
            {
                pos = center;
                return true;
            }
        }
    }
    
    if (try_random && navArea!=Address_Null)
    {
        L4D_FindRandomSpot(navArea,new_pos);
        if (!IsObstructed(new_pos,entity,_,ignore_zombies))
        {
            pos = new_pos;
            return true;
        }
        else if (try_random_up)
        {
            if (obstruction_rescue_hull_up(new_pos,entity,zClass))
            {
                pos = new_pos;
                return true;
            }
        }
    }
    return false;
}

//// ty zyiks
stock void DumpPlayerState(int client, int target = -1)
{
      if (target == -1) target = client;
      if (!IsValidClient(target))
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

void check_zm_team()
{
   if (!IsValidClientZM()) return;
   if (GetClientTeam(zm_client)==TEAM_SURVIVOR)
   {
       update_t_zm_activity(0.0); // instantly starts printing the "no ZM" message
       QuitZM(zm_client);
   } 
}

stock bool IsValidClientZM(int client=-1)
{
    switch (client)
    {
        case -1: return IsValidClient(zm_client);
        default: return IsValidClient(client);
    }
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

stock int GetEntityCountEx()
{
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

stock bool IsValidEntRef(int entity)
{
	if( entity && entity != -1 && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;	
}

stock bool IsValidEntity_Safe(int entity)
{
	return ( entity && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity) );
}

stock bool IsEntitySafe(int entity)
{
	if(entity == -1) return false;
	if(entity >= ENTITY_SAFER_LIMIT)
	{
		RemoveEntity(entity);
		return false;
	}
	return true;
}

stock void PluginPrecacheModel(const char[] model)
{
	if (!IsModelPrecached(model)) PrecacheModel(model, true);
}

stock float get_survivor_flow_fraction(int client)
{
    if (!IsValidClient(client)) return -1.0;
    if (!IsPlayerAlive(client)) return -1.0;
    float max_flow = L4D2Direct_GetMapMaxFlowDistance();
    if (max_flow<=0.0) return -1.0;
    float flow = L4D2Direct_GetFlowDistance(client);
    if (flow<0.0) flow = 0.0;
    return flow/max_flow;
}

void set_zm_stage(int stage, bool override = false)
{
    if (override || zm_stage<stage) zm_stage = stage;
}

bool can_change_finale_stage()
{
    if (!ZM_finale_announced) return false;
    if (zm_stage>=ZM_END) return false;
    if (!holdfinale) return true;
    int current = L4D2_GetCurrentFinaleStage();
    if (current==FINALE_CUSTOM_SCRIPTED || current==FINALE_CUSTOM_DELAY || current==FINALE_CUSTOM_CLEAROUT)
        return true;
    if (bank<g_iBonusFinaleStage) return true;
    if ( bank>=(0.5*g_iBonusFinaleStage*g_iAliveSurvivors) ) return false;
    if ( live_SI<=1 && live_zombie_arr[ZOMBIECLASS_TANK]<=0 ) return true;
    return false;
}

void announce_finale()
{
    if (DEBUG) LogMessage("[zm] announce_finale");
    if (L4D_IsSurvivalMode() || zm_stage!=ZM_STARTED) return;
    if (panic) toggle_panic(false,true);
    if (!ZM_finale_announced)
    {
        ZM_finale_announced = true;
        if (IsValidClientZM())
        {
            EmitSoundToClient(zm_client,SOUND_PANIC_ON,_,_,_,_,_,GetRandomInt(90,110));
            PrintHintText(zm_client, "%t", "Finale started ZM");
        }
        PrintToChatAll("[zm] %t", "Finale started");
        update_menus();
    }
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

Action ZMControlSI(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Stop;
    
    if (is_zm_spamming()) return Plugin_Continue;
    
    if (DEBUG) LogMessage("[zm] ZMControlSI");
    
    int zClass = GetEntProp(zm_client, Prop_Send, "m_zombieClass");
    if (zClass==ZOMBIECLASS_TANK && L4D_IsPlayerIncapacitated(zm_client)) return Plugin_Continue;
    
    // ZM wants to let go of special infected.
    if ( IsPlayerAlive(zm_client) && GetClientTeam(zm_client)==TEAM_INFECTED && !L4D_IsPlayerIncapacitated(zm_client) )
    {
        
        int health = GetEntProp(zm_client,Prop_Data,"m_iHealth");
        if (zClass==ZOMBIECLASS_BOOMER && health==0)
        {
            // Tank stutter fix is active, prevent ZM from doing anything.
            return Plugin_Continue;
        }
        
        if ( L4D2_GetSurvivorVictim(zm_client)<=0 &&
             ( !ZM_finale_announced || zClass!=ZOMBIECLASS_TANK ) )
        {
            
            //SDKUnhook(zm_client, SDKHook_OnTakeDamage, OnTakeDamage_ZM);
            float vOrigin[3], vAngles[3], vVelocity[3], vEye[3];
            GetClientAbsOrigin(zm_client, vOrigin);
            GetClientEyeAngles(zm_client, vAngles); 
            GetClientEyePosition(zm_client, vEye);
            GetEntPropVector(zm_client, Prop_Data, "m_vecAbsVelocity", vVelocity);
            int maxhealth = GetEntProp(zm_client,Prop_Data,"m_iMaxHealth");
            int fFlags = GetEntProp(zm_client, Prop_Data, "m_fFlags");
            zm_use_notify = true;
            
            zm_deathPos = vEye;
            zm_deathAngles = vAngles;
            
            char sModelName[64];
            GetEntPropString(zm_client, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
            
            char targetName[64];
            GetEntPropString(zm_client, Prop_Data, "m_iName", targetName, sizeof(targetName));
            if (strcmp(targetName,"zm_control")==0) targetName = "";
            else if (strcmp(targetName,"zm_unit_control")==0) targetName = "zm_unit";
            DispatchKeyValue(zm_client, "targetname", "zm_client");
            
            if (zClass == ZOMBIECLASS_TANK)
            {
                pending_tank = true;
                targetName_pending = targetName;
                maxhp_pending = maxhealth;
                model_pending = sModelName;
                if (DEBUG) LogMessage("[zm] targetName_pending %s", targetName_pending);
                CreateTimer(0.1,Timer_Clear_targetname_pending,TIMER_FLAG_NO_MAPCHANGE);
                L4D_ReplaceWithBot(zm_client);
            }
            else
            {
                //L4D_ReplaceWithBot(zm_client); // why doesn't this work :/
                float timestamp_cooldown = 0.0;
                int ability = GetEntPropEnt(zm_client, Prop_Send, "m_customAbility");
                if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
                live_SI -= 1;
                live_zombie_arr[zClass] -= 1;
                int bot = ZM_Spawn_SI(zm_client,zClass,true,true,vOrigin);
                if (IsValidEntity(bot))
                {
                    transfer_SI_properties(bot,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
                    if (L4D_IsPlayerStaggering(zm_client)) L4D_StaggerPlayer(bot,bot,NULL_VECTOR);
                }
                
            }
            
            L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
            SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
            SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
            if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
            L4D_CleanupPlayerState(zm_client);
            SetEntityMoveType(zm_client, MOVETYPE_NONE);
            SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
            SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
            SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
            TeleportEntity(zm_client, vEye, vAngles, NULL_VECTOR);
            RequestFrame(ZM_FixCamera,false);
            update_zm_flashlight();
        }
        else update_hint("%T", "Cannot control", zm_client);
        
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
    
    char class[32];
  	GetEntityClassname(entity, class, sizeof(class));
  	if (strcmp(class,"player")==0 && L4D2_GetSurvivorVictim(entity)<=0 )
  	{
         recordpos = true;
         float vOrigin[3], vAngles[3], vVelocity[3];
         GetClientAbsOrigin(entity, vOrigin);
         GetClientEyeAngles(entity, vAngles); 
         GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vVelocity);
         int health = GetEntProp(entity,Prop_Data,"m_iHealth");
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
         if (strcmp(targetName,"zm_unit")==0) DispatchKeyValue(entity, "targetname", "zm_unit_dead");
         else
         {
             DispatchKeyValue(entity, "targetname", "zm_control_dead");
             if (targetName[0]==0) DispatchKeyValue(zm_client, "targetname", "zm_control");
         }
         
         char sModelName[64];
         GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
         
         remove_ZM_glow(entity);
         
         float timestamp_cooldown = 0.0;
         int ability = GetEntPropEnt(entity, Prop_Send, "m_customAbility");
         if (ability > 0 && IsValidEdict(ability)) timestamp_cooldown = GetEntPropFloat(ability, Prop_Send, "m_timestamp");
         
         if (active_looktarget) update_hint("");
         
         ChangeClientTeam(zm_client,TEAM_ZM);
         L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
         
         bool stagger = false;
         if (L4D_IsPlayerStaggering(entity)) stagger = true;
         
         if (zClass==ZOMBIECLASS_TANK)
         {
             if (IsObstructed(vOrigin,entity,_,true)) try_adjusting_obstructed_pos(vOrigin,entity,ZOMBIECLASS_TANK,_,_,true,false,false,false,false);
             L4D_ReplaceTank(entity,zm_client);
         }
         else L4D_TakeOverZombieBot(zm_client,entity);
         L4D_CleanupPlayerState(zm_client);
         
         transfer_SI_properties(zm_client,sModelName,vOrigin,vAngles,vVelocity,health,maxhealth,fFlags,timestamp_cooldown,targetName);
         if (stagger) L4D_StaggerPlayer(zm_client,zm_client,NULL_VECTOR);
         zm_use_notify = true;
         update_zm_flashlight();
  	 }
  	 else update_hint("%T", "Cannot control", zm_client);

    return Plugin_Continue;
}

Action Unfreeze_ZM(Handle timer=null)
{
    if (!IsValidClientZM()) return Plugin_Stop;
    if (!IsPlayerAlive(zm_client))
    {
        SetEntityMoveType(zm_client, MOVETYPE_NOCLIP); //
        SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
        SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
        SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
        SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
        EmitSoundToClient(zm_client,SOUND_VISION);
    }
    return Plugin_Stop;
}

void ZM_FixCamera(bool freeze = true)
{
    if (!IsValidClientZM()) return;
    
    // Fix camera stutter
    if (GetEntProp(zm_client,Prop_Send,"m_zombieClass")==ZOMBIECLASS_TANK)
    {
        if (IsPlayerAlive(zm_client)) ForcePlayerSuicide(zm_client);
        RequestFrame(ZM_FixTankStutter,freeze);
        return;
    }
    
    L4D_State_Transition(zm_client, STATE_OBSERVER_MODE);
    SetEntProp(zm_client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(zm_client, Prop_Data, "m_iObserverMode", 6);
    SetEntPropEnt(zm_client, Prop_Send, "m_hViewEntity", -1);
    SetEntProp(zm_client, Prop_Send, "m_iFOV", 0);
    SetEntProp(zm_client, Prop_Send, "m_iFOVStart", 0);
    SetEntPropFloat(zm_client, Prop_Send, "m_flFOVRate", 0.0);
    
    SetEntPropFloat(zm_client, Prop_Send, "m_staggerTimer", 0.0, 0);
    SetEntPropFloat(zm_client, Prop_Send, "m_stunTimer", 0.0, 0);
    
    SetEntProp(zm_client, Prop_Send, "m_CollisionGroup", 0),
    SetEntProp(zm_client, Prop_Send, "m_nSolidType", 0),
    SetEntProp(zm_client, Prop_Send, "m_usSolidFlags", 0x0004);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageSphereInitialRadius", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_scrimmageStartTime", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_TimeForceExternalView", 0.0);
    SetEntPropFloat(zm_client, Prop_Send, "m_staggerDist", 0.0); 
    SetEntPropVector(zm_client, Prop_Send, "m_scrimmageSphereCenter", {0.0,0.0,0.0});
    
    SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
    SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
    SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
    SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
    
    JoinZM(zm_client,0);
    
    TeleportEntity(zm_client, zm_deathPos, zm_deathAngles, NULL_VECTOR);
    recordpos = true;
    
    if (freeze)
    {
        SetEntityMoveType(zm_client, MOVETYPE_NONE);
        SetEntPropVector(zm_client, Prop_Data, "m_vecVelocity", {0.0,0.0,0.0});
        SetEntPropVector(zm_client, Prop_Data, "m_vecAngVelocity", {0.0,0.0,0.0});
        SetEntPropFloat(zm_client, Prop_Send, "m_flFallVelocity", 0.0);
        SetEntPropVector(zm_client, Prop_Data, "m_angRotation", {0.0,0.0,0.0});
        CreateTimer(0.5,Unfreeze_ZM,TIMER_FLAG_NO_MAPCHANGE);
    }
    
}

Action ZM_Chase_ZM(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM()  || zm_client!=client) return Plugin_Continue;
    if (panic) Chase(zm_client);
    else update_hint("%T", "Panic must be ON", zm_client);
    return Plugin_Continue;
}

Action CountCommons(Handle timer = null, bool fast = true)
{
    if (live_zombie_arr[ZOMBIECLASS_COMMON]>0 || !fast)
    {
        if (DEBUG) LogMessage("[zm] CountCommons expensive");
        live_zombie_arr[ZOMBIECLASS_COMMON] = L4D_GetCommonsCount();
    }
    return Plugin_Continue;
}

void start_zm_round(bool play_sound = true)
{
 if (zm_stage<ZM_STARTED)
 {
     PrintToChatAll("[zm] %t", "Round started");
     if (IsValidClientZM()) PrintHintText(zm_client, "%t", "Round started");
     update_hint("%T", "Round started", zm_client);
     if (play_sound) EmitSoundToAll(SOUND_START);
     t_round_start = GetGameTime();
     L4D2Direct_SetPendingMobCount(0);
     if (g_bMemes && !meme_delivered)
     {
         float delay = GetRandomFloat(1.0,10.0);
         CreateTimer(delay,random_meme,_,TIMER_FLAG_NO_MAPCHANGE);
     }
     infinite_delay_natural_mob();
     CreateTimer(0.1,infinite_delay_natural_mob,TIMER_FLAG_NO_MAPCHANGE);
     CountClients();
     update_EMS_HUD(true,0.0);
     if (shoot_alert_enable) ServerCommand("l4d2_shoot_alert_common_resetcvars");
 }
 zm_allow_spawns = true;
 set_zm_stage(ZM_STARTED);
 update_t_zm_activity();
 check_saferoom();
 saferoom_lock(false);
 if (IsValidEntRef(g_iLockedDoor))
 {
     if (GetEntProp(g_iLockedDoor,Prop_Send,"m_bLocked")>0) AcceptEntityInput(g_iLockedDoor, "Unlock");
     AcceptEntityInput(g_iLockedDoor, "Open");
     SetEntProp(g_iLockedDoor, Prop_Send, "m_spawnflags", GetEntProp(g_iLockedDoor,Prop_Send,"m_spawnflags")|DOOR_FLAG_IGNORE_USE);
     AcceptEntityInput(g_iLockedDoor, "Open");
 }
 freeze_team(false,TEAM_INFECTED);
 saferoom_locked = false;
 create_other_menu();
 create_main_menu();
 //scope_changed = false;
 update_director_script_scopes(false);
 fair_exhausted = true;
 //scope_changed = false;
 set_force_start(false);
 
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
  	 else health = GetEntProp(entref_control,Prop_Data,"m_iHealth");
     if (health>0)
     {
        int zClass = GetEntProp(entref_control, Prop_Send, "m_zombieClass");
        char zClassName[32]; 
        get_zombieclass_name(zClass,zClassName);
        int max_health = GetEntProp(entref_control,Prop_Data,"m_iMaxHealth");
  	    update_hint("%T", "Selected Special", zm_client, zClassName, health, max_health);
  	    active_looktarget = true;
  	 }
  	 else update_hint("");
  	 
}

void update_entref_control(int new_entref, bool draw = false)
{
    if (!IsValidEntRef(new_entref)) return;
    int new_target = EntRefToEntIndex(new_entref);
    if (!IsValidClient(new_target)) return;
    int old_target = -1;
    if (IsValidEntRef(entref_control)) old_target = EntRefToEntIndex(entref_control);
    else if (active_looktarget)
    {
        entref_control = INVALID_ENT_REFERENCE;
        active_looktarget = false;
    }
    if (old_target==new_target && !draw) return;
    if (DEBUG) LogMessage("[zm] update_entref_control %d -> %d", old_target, new_target); 
    if (!IsValidClient(old_target)) old_target = -1;
    entref_control = INVALID_ENT_REFERENCE;
    entref_control = new_entref;
    if ( (new_target!=old_target || !active_looktarget) && draw)
    {
        active_looktarget = true;
        if (old_target>0 && new_target!=old_target) request_update_glow(old_target,true,0.0);
        request_update_glow(new_target,true,0.0);
    }
    
}

void update_ZM_looktarget(bool draw = true)
{
   if (!IsValidClientZM())
   {
       entref_lastlook = INVALID_ENT_REFERENCE;
       return;
   }
   int target = GetClientAimTarget(zm_client, true);
   if (!IsValidClient(target) || target==zm_client)
   {
       static float vAngles[3],vOrigin[3],vForward[3],vEnd[3];
       GetClientEyePosition(zm_client,vOrigin);
       GetClientEyeAngles(zm_client,vAngles);
       GetAngleVectors(vAngles,vForward,NULL_VECTOR,NULL_VECTOR);
       vEnd[0] = vOrigin[0] + (vForward[0] * 10000.0);
       vEnd[1] = vOrigin[1] + (vForward[1] * 10000.0);
       vEnd[2] = vOrigin[2] + (vForward[2] * 10000.0);
       //Handle trace = TR_TraceRayFilterEx(vOrigin,vAngles,MASK_SHOT,RayType_Infinite,TraceFilter_Looktarget,_,TRACE_ENTITIES_ONLY);
       Handle trace = TR_TraceHullFilterEx(vOrigin,vEnd,HULL_MINS_LOOK,HULL_MAXS_LOOK,MASK_SHOT,TraceFilter_Looktarget,zm_client,TRACE_ENTITIES_ONLY);
       if(TR_DidHit(trace)) target = TR_GetEntityIndex(trace);
       delete trace;
   }
   if (target>=0 && EntIndexToEntRef(target)==entref_lastlook) return;
   entref_lastlook = INVALID_ENT_REFERENCE;
   if (!IsValidEntity(target) || target==zm_client) return;
   int health = GetEntProp(target,Prop_Data,"m_iHealth");
   if (health<=0) return;
   entref_lastlook = EntIndexToEntRef(target);
   char class[32];
   GetEntityClassname(target, class, sizeof(class));
   if (class[0]=='i' || class[0]=='w' || class[0]=='p')
   {
       if (IsValidClient(target) && GetClientTeam(target)==TEAM_SURVIVOR && IsPlayerAlive(target))
       {
           if (!IsValidEntRef(g_iGlowList[target]) && L4D2_GetSurvivorVictim(zm_client)!=target) CreateZMGlow(target,false,true);
       }
       else if ( strcmp(class,"infected")==0 || strcmp(class,"witch")==0 || (IsValidClient(target) && GetClientTeam(target)==TEAM_INFECTED && IsFakeClient(target)) )
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
      	 if (strcmp(class,"player")==0 && !L4D_IsPlayerIncapacitated(target)) update_entref_control(entref_temp,draw);
       }
   }
}

void update_director_script_scopes(bool warn = true)
{
    
    int pending_mob = L4D2Direct_GetPendingMobCount();
    
    int scope0 = L4D2_GetDirectorScriptScope(0); 
    if (old_scope0!=scope0)
    {
        if (DEBUG && warn) LogMessage("[zm] DirectorScript scope changed! mob %d", pending_mob); 
        old_scope0 = scope0;
    }
    
    int scope1 = L4D2_GetDirectorScriptScope(1); 
    if (old_scope1!=scope1)
    {
        if (DEBUG && warn) LogMessage("[zm] MapScript scope changed! mob %d", pending_mob); 
        old_scope1 = scope1;
    }
    
    int scope2 = L4D2_GetDirectorScriptScope(2); 
    if (old_scope2!=scope2)
    {
        if (DEBUG && warn) LogMessage("[zm] LocalScript scope changed! mob %d", pending_mob); 
        old_scope2 = scope2;
        check_fog_distance();
        CreateTimer(2.0,check_fog_distance,TIMER_FLAG_NO_MAPCHANGE);
    }
    
    int scope3 = L4D2_GetDirectorScriptScope(3); 
    if (old_scope3!=scope3)
    {
        if (DEBUG && warn) LogMessage("[zm] ChallengeScript scope changed! mob", pending_mob); 
        old_scope3 = scope3;
    }
    
    int scope4 = L4D2_GetDirectorScriptScope(4); 
    if (old_scope4!=scope4)
    {
        if (DEBUG && warn) LogMessage("[zm] DirectorOptions scope changed! mob %d", pending_mob); 
        old_scope4 = scope4;
        //scope_changed = true;
        //t_scope_change = GetGameTime();
    }
     
}

Action zm_freeze(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client || zm_stage<ZM_STARTED) return Plugin_Continue;
    set_specials_frozen(~ZM_specials_frozen);
    return Plugin_Continue;
}

void set_specials_frozen(bool state)
{
    if (!g_bAllowFreeze || max_SI<=0) state = false;
    if (ZM_specials_frozen!=state || specials_frozen!=state)
    {
        ZM_specials_frozen = state;
        freeze_team(state,TEAM_INFECTED);
        if (IsValidClientZM()) create_main_menu();
    }
}

Action zm_debug_player(int client, int args)
{
    DumpPlayerState(client,client);
    return Plugin_Continue;
}

void zm_fake_gamemode()
{
    if (L4D_IsSurvivalMode()) FindConVar("mp_gamemode").ReplicateToClient(zm_client,"mutation15");
    else FindConVar("mp_gamemode").ReplicateToClient(zm_client,"versus");
}

Action JoinZM_command(int client, int args)
{
    if (!IsValidClient(client)) return Plugin_Continue;
    first_active = true;
    clients_active[client] = true;
    if (!g_bCvarAllow) VoteZM(client,0);
    if (IsValidClientZM() && client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
    JoinZM(client,args);
    return Plugin_Continue;
}

Action JoinZM(int client, int args)
{
	if (!g_bCvarAllow || !IsValidClient(client) || args>1) return Plugin_Continue;
	if (zm_stage>=ZM_END) return Plugin_Continue;
	if (client<0 || IsFakeClient(client)) return Plugin_Continue;
	if (DEBUG) LogMessage("[zm] JoinZM");
	if (IsValidClientZM())
	{
       if (client==zm_client)
       {
          if (GetClientTeam(zm_client)!=TEAM_ZM)
          {
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
          if (zm_menu_state==ZM_MENU_CLOSED) open_menu(zm_client);
       }
       else PrintHintText(client,"%t", "ZM taken");
       return Plugin_Continue;
    }
    
    // Allow players who played less to skip ahead of offer line
    if (g_bFairQueue && zm_stage<ZM_STARTED && !fair_exhausted && client!=client_offer)
    {
  		zm_data cell;
  		if (!get_zm_data(cell,client)) return Plugin_Continue;
  		int roundcount_client = cell.last_roundcount;
  		if (roundcount_client>=roundcount_offer)
  		{
      		if (IsValidClient(client_offer))
      		{
          		char name[MAX_NAME_LENGTH]; 
                GetClientName(client_offer,name,sizeof(name));
                int timeleft = RoundFloat(g_fFairQueueWait - (GetGameTime() - t_offer));
                if (timeleft<0) timeleft = 0;
           		PrintToChat(client, "[zm] %T", "Offered ZM Ticker", client, name, timeleft); 
      		}
      		return Plugin_Continue;
  		}
    }
    
    if (GetClientTeam(client)==TEAM_SURVIVOR && IsPlayerAlive(client))
    {
        L4D_TakeOverBot(client);
    }
    
    remove_all_ZM_glows();
    
    if (!g_bGrid) g_iSpawnerMode = 0;
    else g_iSpawnerMode = g_hSpawnerMode.IntValue;
    
    ChangeClientTeam(client,TEAM_ZM);
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    if (!g_bAllowFreeze) ZM_specials_frozen = false;
    zm_client = client;
    zm_client_userid = GetClientUserId(zm_client);
    Spawner_OnEnabled(client);

    update_menus();
    
    // Prevent InputKill - thanks Shadowsyn
   	//SetVariantString("self.ValidateScriptScope()");
   	//AcceptEntityInput(client, "RunScriptCode");
  	//SetVariantString("plugin_shouldKill <- false;");
  	//AcceptEntityInput(client, "RunScriptCode");
  	//SetVariantString("function InputKill() {return plugin_shouldKill}");
   	//AcceptEntityInput(client, "RunScriptCode");
    
    spawner_last_valid = false;
    char name[MAX_NAME_LENGTH]; 
    GetClientName(client,name,sizeof(name));
    int playcount = get_rounds(client);
    PrintToChatAll("[zm] %t (%d)", "ZM joined", name, playcount);
    zm_use_notify = playcount>0;
    zm_flow_notify = playcount>0;
    DispatchKeyValue(zm_client, "targetname", "zm_client");
    SetEntProp(client, Prop_Send, "m_zombieClass", 0);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    PrintHintText(client, "%t", "ZM join hint");
    L4D2_RemoveEntityGlow(zm_client);
    L4D2_SetPlayerSurvivorGlowState(zm_client,false);
    zm_fake_gamemode();
    ems_hud_timer = INVALID_HANDLE;
    update_hint("%T", "zm_menu_hint", zm_client);
    if (playcount<=0) PrintToChat(client, "[zm] Enable Spectating Free Look in Options -> Multiplayer!!!");
    if (strcmp(g_sZMGamemode,"zm_default")!=0) PrintToChat(client, "[zm] Gamemode: %s", g_sZMGamemode);
    if (panic_target==zm_client) panic_target = -1;
    update_t_zm_activity();
    if (t_zm_join==0.0) t_zm_join = t_zm_activity;
    if (clients_timer==INVALID_HANDLE) clients_timer = CreateTimer(0.1,CountClients);
    pass_ZM(client);
    if (zm_timer == INVALID_HANDLE) zm_update();
    open_menu(zm_client);
    recordpos = true;
    
    entref_control = INVALID_ENT_REFERENCE;
    entref_delete = INVALID_ENT_REFERENCE;
    
    if (IsValidClientZM()) EmitSoundToClient(zm_client,SOUND_VISION);
    
    if (zm_stage<ZM_PREP) set_bank_begin();
    
    ZMTeleport(zm_client,0);
    L4D_CleanupPlayerState(client);
    SetEntityMoveType(zm_client, MOVETYPE_NOCLIP);
    
    // Make end saferoom door glow, and close it.
    if (!L4D_IsSurvivalMode())
    {
        lastdoor = L4D_GetCheckpointLast();
        if (IsValidEntity(lastdoor))
        {
            if (zm_stage<ZM_PREP) AcceptEntityInput(lastdoor, "Close");
            CreateTimer(g_fUpdateRate, CreateZMGlow_red, EntIndexToEntRef(lastdoor), TIMER_FLAG_NO_MAPCHANGE);
        }
        else lastdoor = -1;
    }

    set_zm_stage(ZM_PREP);

    return Plugin_Continue;
}

void QuitZM_Force(int client)
{
    if (!IsValidClient(client)) return;
    L4D_State_Transition(client, STATE_OBSERVER_MODE);
    SetEntProp(client, Prop_Data, "m_iObserverMode", 6);
    QuitZM(client,false);
}

void QuitZM(int client, bool print = true)
{
	if (DEBUG) LogMessage("[zm] QuitZM");
	if (!g_bCvarAllow || client<=0 || !IsClientInGame(client) || IsFakeClient(client)) return;
	
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
           
           if (panic_target==zm_client) panic_target = -1;
           
           if (zm_stage<ZM_STARTED)
           {
               zm_can_start = false;
               set_zm_stage(ZM_PREP,true);
           }
           
           if (zm_menu_state!=ZM_MENU_CLOSED) close_menus(zm_client);
           
           if (IsPlayerAlive(zm_client))
           {
               ZMControlSI(zm_client,0);
               RequestFrame(QuitZM_Force,client);
               return;
           }
           DispatchKeyValue(zm_client, "targetname", "client");
       }
       Spawner_OnDisabled(zm_client);
       remove_all_ZM_glows();
       zm_client = -1;
       zm_client_userid = -1;
       zm_menu_state = ZM_MENU_CLOSED;
       fair_queue_update(null);
    }
    
    if (IsValidClient(client) && GetClientTeam(client)!=TEAM_SURVIVOR)
    {
            // Find bot that can be taken over. Credit: l4dmultislots by HarryPotter
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
   			L4D_CleanupPlayerState(client);
    }

}

Action QuitZM_Command(int client, int args)
{
  if (!g_bCvarAllow) return Plugin_Continue;
  QuitZM(client,true);
  return Plugin_Continue;
}

Action zm_finale_advance(int client, int args)
{
  if (DEBUG) LogMessage("[zm] zm_finale_advance");
  if (L4D_IsFinaleActive()) L4D2_ForceNextStage();
  else PrintToChat(client, "[zm] Finale is not active"); 
  return Plugin_Continue;
}

Action zm_kick(int client, int args)
{
    if (!g_bCvarAllow) return Plugin_Continue;
    if (!IsValidClientZM()) return Plugin_Continue;
    if (DEBUG) LogMessage("[zm] zm_kick");
    QuitZM(zm_client,false);
    return Plugin_Continue;
}

void update_vomited(int victim)
{
    float t_now = GetGameTime();
    if ( FloatAbs(t_now-t_vomited[victim])<5.0 ) return;
    request_update_glow(victim);
    t_vomited[victim] = t_now;
    if (IsValidClientZM() && (t_now-t_last_hitmarker)>=0.1)
    {
        EmitSoundToClient(zm_client,SOUND_HITMARKER,_,_,_,_,_,GetRandomInt(95,105));
        t_last_hitmarker = t_now;
    }
    spawn_free_angry_zombies(victim,g_iVomitCommons);
}

void ResetTimer()
{
    if (DEBUG) LogMessage("[zm] ResetTimer");
    delete fq_timer;
    delete zm_timer;
    zm_timer = INVALID_HANDLE;
    delete ems_hud_timer;
    delete clients_timer;
    for(int i=1; i<=MAXENTITIES; i++)
    {
        hp_timers[i] = INVALID_HANDLE;
    }
    if (g_bCvarAllow && zm_stage<ZM_END) zm_update();
}

static float last_saferoom_pos[3];
float distance_last_saferoom(float pos[3])
{
    if (ZM_finale_announced || L4D_IsSurvivalMode() || !IsValidEntity(lastdoor)) return -1.0;
    L4D_GetEntityWorldSpaceCenter(lastdoor,last_saferoom_pos);
    return GetVectorDistance(pos,last_saferoom_pos);
}

// Check if ZM can see position
bool can_ZM_see(float vPos[3])
{
    if (!IsValidClientZM()) return false;
    float vEye[3], vPos2[3];
    GetClientEyePosition(zm_client,vEye);
    if (GetVectorDistance(vPos,vEye)>=fog_distance) return false;
    vPos2 = vPos; vPos2[2] += 32.0;
    bool can_see = true;
    Handle trace = TR_TraceRayFilterEx(vEye,vPos2,MASK_VISIBLE,RayType_EndPoint,FilterSpawner,zm_client);
    if(TR_DidHit(trace)) can_see = false;
    delete trace;
    return can_see;
}