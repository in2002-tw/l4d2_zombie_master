///////////////////////////////////////
#if defined _zm_globals_included
 #endinput
#endif
#define _zm_globals_included
///////////////////////////////////////

// Ideally this file is empty in the future

ConVar g_hCvarDebug, g_hCvarAllow, z_max_player_zombies, infectedbots_enable, jukebox_horde, shoot_alert_enable, clown_world_enable;
bool g_bCvarAllow;
bool g_bSpawnWitchBride = false; // avoid crash

int zm_stage = ZM_END;
void set_zm_stage(int stage, bool override = false)
{
    if (override || zm_stage<stage) zm_stage = stage;
}

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
// Notify ZM about maximum Tank discount.
bool zm_discount_notify = false; // "Max tank discount"

ConVar g_hBankRateBase, g_hBankRatePlayer, g_hBankInitial, g_hBankInitialPlayer, g_hStopInactivity, g_hMaxUniqueSI, g_hRandomizer, g_hNoTanks,
       g_hUpdateRate, g_hMaxCommons, g_hSpawnMinDistance, g_hBonusCarAlarm, g_hBonusFinaleStage, g_hPanicCost, g_hBonusSurvival, g_hAbilityNoCooldown,
       g_hCostBoomer, g_hCostSpitter, g_hCostHunter, g_hCostSmoker, g_hCostJockey, g_hMaxWitches, g_hMaxSI, g_hSpecialCooldown,
       g_hCostCharger, g_hCostTank, g_hCostWitchStatic, g_hCostWitchMoving, g_hCostCommon, g_hCostUncommon, g_hLockSaferoom,
       g_hCommonRate, g_hWitchCooldown, g_hTankCooldown, g_hMinFinaleStage, g_hPanicDuration, g_hFairQueue, g_hFairQueueWait, g_hPanicRateMultiplier,
       g_hMenuTimeout, g_hDiscountTank, g_hMemes, g_hClownGlow, g_hForceCommon, g_hHoldFinale, g_hZMGamemode, g_hVomitCommons, g_hAllowFreeze,
       g_hGridSearchRadius;

float g_fBankRateBase,g_fBankRatePlayer,g_fUpdateRate,g_fSpawnMinDistance,g_fStopInactivity,g_fSpecialCooldown, g_fPanicRateMultiplier,
g_fCommonRate, g_fWitchCooldown, g_fTankCooldown, g_fMinFinaleStage, g_fPanicDuration, g_fFairQueueWait, g_fMenuTimeout,
g_fGridSearchRadius;

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

bool g_bLockSaferoom;

int info_director = -1;

// Scattered globals (moved from between functions in main file)
bool playcount_increased = false;
int entref_control = INVALID_ENT_REFERENCE; // track the last special infected ZM looked at
int entref_delete = INVALID_ENT_REFERENCE; // track the last zombie ZM looked at
int entref_lastlook = INVALID_ENT_REFERENCE;
int g_iLockedDoor = INVALID_ENT_REFERENCE;
