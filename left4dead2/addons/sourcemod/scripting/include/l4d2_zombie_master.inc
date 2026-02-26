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

#define SPAWNER_OK 0
#define SPAWNER_INVALID 1
#define SPAWNER_NAV 2
#define SPAWNER_DISTANCE 3
#define SPAWNER_SIGHT 4
#define SPAWNER_OTHER 5

#define AUTOCOMMON_OFF 0
#define AUTOCOMMON_PANIC 1
#define AUTOCOMMON_ALWAYS 2

#define FOG_DISTANCE 5000.0

#define HULL_DX_STRICT 15.0
#define HULL_DZ_MIN_STRICT 26.0
#define HULL_DZ_MAX_STRICT 46.0

#define HULL_DX 20.0
#define HULL_DZ 36.0
#define HULL_DDZ 72.0

#define WITCH_STATIC 0
#define WITCH_MOVING 1

#define IGNITE_TIME 3600.0


// enum for spawner state
#define SPAWNER_BLOCKED 0 // can never spawn infected here
#define SPAWNER_CONDITIONAL 1 // cannot spawn here temporarily because survivors can see or are too close
#define SPAWNER_ALLOWED 2 // can spawn infected here
#define RGB_ZM 16777215 // white for outlines

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
#define MODEL_CEDA "models/infected/common_male_ceda.mdl"
#define MODEL_CLOWN "models/infected/common_male_clown.mdl"
#define MODEL_MUD "models/infected/common_male_mud.mdl"
#define MODEL_ROAD "models/infected/common_male_roadcrew.mdl"
#define MODEL_JIMMY "models/infected/common_male_jimmy.mdl"
#define MODEL_FALLEN "models/infected/common_male_fallen_survivor.mdl"

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

// Data structure for player stats
enum struct zm_data
{
	int rounds;          // number of rounds played as ZM
	int last_roundcount; // last internal roundcount value where they played as ZM
	bool offered;        // track if offered at round start
}

enum struct PreCalcNav
{
	float position[3];     // World position
	Address navArea;       // Nav area reference
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

// Allow witches to be spawned in weird places
stock bool nav_can_spawn_zombies(int navAttributeFlags, int navSpawnAttributes, bool witch = false)
{
    if (!witch)
    {
        if (navAttributeFlags & NAV_BASE_OUTSIDE_WORLD) return false;
        if (navSpawnAttributes & NAV_SPAWN_BATTLESTATION) return false;
    }
    // some Valve maps have messed up navmeshes where rescue closet is bleeding out
    if (navSpawnAttributes & NAV_SPAWN_PLAYER_START) return false;
    if (navSpawnAttributes & NAV_SPAWN_CHECKPOINT) return false;
    if (navSpawnAttributes & NAV_SPAWN_BATTLEFIELD) return true;
    if (navSpawnAttributes & NAV_SPAWN_ESCAPE_ROUTE) return true;
    if (navSpawnAttributes & NAV_SPAWN_OBSCURED || navSpawnAttributes & NAV_SPAWN_IGNORE_VISIBILITY) return true;
    if (navSpawnAttributes & NAV_SPAWN_RESCUE_CLOSET) return false;
    return true;
}

// True to allow the current entity to be hit, otherwise false.
stock bool FilterSpawner(int entity, int mask, int self)
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

// Check if navArea is a valid survivor starting area
stock bool navArea_validStart(Address navArea)
{
    if (!navArea) return false;
    int navSpawnAttrs = L4D_GetNavArea_SpawnAttributes(navArea);
    if ( (navSpawnAttrs & NAV_SPAWN_OBSCURED) || (navSpawnAttrs & NAV_SPAWN_FINALE) ) return false;
    if (!((navSpawnAttrs & NAV_SPAWN_PLAYER_START) || (navSpawnAttrs & NAV_SPAWN_CHECKPOINT))) return false;
    
    float pos[3];
    L4D_FindRandomSpot(navArea,pos);
    float flow = L4D_GetFlowFromPoint(pos);
    if (flow>0.0 || flow<(-9000.0)) return false;
    if (!L4D_IsPositionInFirstCheckpoint(pos)) return false;
    return true;
}

stock void infected_panic(Handle hInfectedAttackSurvivorTeam)
{
    int zombie = INVALID_ENT_REFERENCE;
    while( INVALID_ENT_REFERENCE != (zombie = FindEntityByClassname(zombie, "infected")) )
    {
   	    if( IsValidEntity(zombie) && GetEntProp(zombie,Prop_Data,"m_iHealth")>0 ) 
   	    {
	        if (hInfectedAttackSurvivorTeam) SDKCall(hInfectedAttackSurvivorTeam,zombie);
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

// Check if Survivor or Special Infected is vomited -- attracting commons, for survivors vomit overlay ON.
stock bool is_player_vomited(int client)
{
    //float t_start = GetEntPropFloat(client, Prop_Send, "m_vomitStart");
    //if (t_start<=0.0) return false;
    //float t_end = GetEntPropFloat(client, Prop_Send, "m_vomitFadeStart");
    //float t_end = GetEntPropFloat(client, Prop_Send, "m_itTimer", 1); 
    //if (t_end<=0.0) return false;
    //t_end -= 1.0;
    //float t_now = GetGameTime();
    //if (t_now<t_end && t_now>=t_start) return true;
    //return false;
    return GetEntPropFloat(client, Prop_Send, "m_itTimer", 1)!=-1.0;
}

stock bool get_client_auth(int client, char auth[65])
{
    //if (!IsValidClient(client)) return false;
    if (client<=0 || client>MaxClients) return false;
    if (!GetClientAuthId(client,AuthId_Engine,auth,sizeof(auth))) return false;
    return true;
}

stock void CountStringRowsCols(const char[] str, int &rows, float &cols)
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

stock int get_occupied_units(int max, int available, int live)
{
    int occupied = max-available;
    if (occupied<live) occupied = live;
    return occupied;
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

stock bool valid_uncommon(char arg[32])
{
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

stock void process_horde_arg(int &count, char type[32], bool &angry, bool &flow, char arg[32])
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

static float HULL_MINS[3] = {-HULL_DX_STRICT,-HULL_DX_STRICT,HULL_DZ_MIN_STRICT};
static float HULL_MAXS[3] = {HULL_DX_STRICT,HULL_DX_STRICT,HULL_DZ_MAX_STRICT};
public bool TraceFilter_Spawner(int entity, int contentsMask)
{
	if (entity==0) return true;
	if (IsValidClient(entity) && IsPlayerAlive(entity)) return true;
	if (entity>MaxClients)
	{
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
stock bool IsObstructed(float vecpos[3], bool DEBUG=false)
{
    bool isObstructed = false;
	Handle hullTrace = TR_TraceHullFilterEx(vecpos, vecpos, HULL_MINS, HULL_MAXS,
								        MASK_NPCSOLID,
								        TraceFilter_Spawner);
	if (TR_DidHit(hullTrace))
	{
		int hitEntity = TR_GetEntityIndex(hullTrace);
		if (DEBUG && IsValidEntity(hitEntity))
		{
		     char classname[64];
             GetEntityClassname(hitEntity, classname, sizeof(classname));
             LogMessage("[zm] IsObstructed hit %d %s", hitEntity, classname);
		}
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
