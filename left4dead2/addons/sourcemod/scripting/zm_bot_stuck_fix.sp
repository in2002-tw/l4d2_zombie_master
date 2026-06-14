/**
 * ZM Survivor Bot Stuck Fix
 *
 *   SurvivorBot::EnforceProximityToHumans  - drags a too-far bot toward its single
 *       "follow human" handle. When that handle is valid but points at someone who
 *       is no longer a live survivor, we invalidate it so the routine takes its own
 *       "no follow target" early-out.
 *
 *   SurvivorBot::ResolveStuckSituation     - stuck recovery. branch A teleports the
 *       bot forward along its own path (good, untouched). branch B falls back to
 *       warping to a random tracked teammate. We prune that teammate list down to
 *       live survivors only, then let the routine run, so branch A still works and
 *       branch B can only ever pick a real, alive survivor.
 *
 *   ChasePath::RefreshPath                 - the way every survivor movement
 *       Action (Regroup, CoverOrphan, ...) chooses its chase path through. These Actions
 *       cache a target and never re-check its team, so a bot keeps chasing a teammate
 *       who switched to the infected team (the ZM). When we catch a survivor bot
 *       chasing a target that is no longer a live survivor, we redirect the chase
 *       to the engine's own closest-reachable teammate
 *       (or, if there is none, skip the refresh entirely).
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#define PLUGIN_VERSION "1.0"

#define TEAM_SURVIVOR 2

#define EHANDLE_INDEX_MASK 0xFFF
#define EHANDLE_INVALID    -1

#define LOG_THROTTLE_SECONDS 5.0

// The team-situation teammate list is a fixed-size array; the engine only ever
// copies up to this many entries out of it.
#define SITUATION_LIST_CAPACITY 4

ConVar g_cvEnable;
ConVar g_cvLog;
ConVar g_cvChase;

int g_iOfsFollowHuman;     // GetTeamSituation()+0x30: single "follow human" EHANDLE
int g_iOfsList;            // GetTeamSituation()+0x88: tracked-teammate EHANDLE array
int g_iOfsListCount;       // GetTeamSituation()+0xc4: entries in that array
int g_iOfsFollowDistance;  // GetTeamSituation()+0x34: distance vs sb_enforce_proximity_range (debug)

int g_iOfsINextBot;        // CTerrorPlayer -> INextBot subobject
int g_iOfsSituationBase;   // CTerrorPlayer -> SurvivorTeamSituation (GetTeamSituation()'s return)

Handle g_hGetClosestReachableFriend;  // SurvivorTeamSituation::GetClosestReachableFriend()

float g_fLastStuckLog[MAXPLAYERS + 1];
float g_fLastChaseLog[MAXPLAYERS + 1];

int g_iLastClearedFollow[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "ZM Survivor Bot Stuck Fix",
	author		= "zyiks",
	description	= "Stops stuck/distant survivor bots from teleporting onto team-switched players and falling to their death",
	version		= PLUGIN_VERSION,
	url			= ""
};

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("zm_bot_stuck_fix_enable", "1",
		"Enable the survivor-bot stale-teleport on the next tick only fix .",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvLog = CreateConVar("zm_bot_stuck_fix_log", "1",
		"Log to the server log whenever a bad bot teleport is prevented.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvChase = CreateConVar("zm_bot_stuck_fix_chase", "1",
		"Redirect survivor bots that are path-chasing a player who is no longer a live survivor.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	GameData gd = new GameData("zm_bot_stuck_fix");
	if (gd == null)
		SetFailState("Missing gamedata: zm_bot_stuck_fix.txt");

	g_iOfsFollowHuman    = LoadEntityOffset(gd, "Situation_FollowHuman");
	g_iOfsList           = LoadEntityOffset(gd, "Situation_List");
	g_iOfsListCount      = LoadEntityOffset(gd, "Situation_ListCount");
	g_iOfsFollowDistance = LoadEntityOffset(gd, "Situation_FollowDistance");
	g_iOfsINextBot       = LoadEntityOffset(gd, "INextBot_Subobject");
	g_iOfsSituationBase  = LoadEntityOffset(gd, "Situation_Base");

	g_hGetClosestReachableFriend = SetupClosestFriendCall(gd);

	DynamicDetour ddProximity = DynamicDetour.FromConf(gd, "SurvivorBot::EnforceProximityToHumans");
	if (ddProximity == null)
		SetFailState("Failed to set up detour: SurvivorBot::EnforceProximityToHumans");

	DynamicDetour ddStuck = DynamicDetour.FromConf(gd, "SurvivorBot::ResolveStuckSituation");
	if (ddStuck == null)
		SetFailState("Failed to set up detour: SurvivorBot::ResolveStuckSituation");

	DynamicDetour ddChase = DynamicDetour.FromConf(gd, "ChasePath::RefreshPath");
	if (ddChase == null)
		SetFailState("Failed to set up detour: ChasePath::RefreshPath");

	delete gd;

	ddProximity.Enable(Hook_Pre, Detour_EnforceProximity_Pre);
	ddStuck.Enable(Hook_Pre, Detour_ResolveStuck_Pre);
	ddChase.Enable(Hook_Pre, Detour_RefreshPath_Pre);

	RegAdminCmd("sm_botstuck_debug", Cmd_Debug, ADMFLAG_ROOT,
		"Dump each survivor bot's follow-human, proximity gate, and team-situation list.");

	for (int i = 1; i <= MaxClients; i++)
		g_iLastClearedFollow[i] = EHANDLE_INVALID;
}

static int LoadEntityOffset(GameData gd, const char[] key)
{
	int offset = gd.GetOffset(key);
	if (offset == -1)
		SetFailState("Missing offset in gamedata: %s", key);
	return offset;
}

static Handle SetupClosestFriendCall(GameData gd)
{
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "SurvivorTeamSituation::GetClosestReachableFriend"))
		SetFailState("Failed to find signature: SurvivorTeamSituation::GetClosestReachableFriend");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);

	Handle call = EndPrepSDKCall();
	if (call == null)
		SetFailState("Failed to prepare SDKCall: SurvivorTeamSituation::GetClosestReachableFriend");
	return call;
}

/**
 * EnforceProximityToHumans warps a too-far bot to its single "follow human"
 * handle. We only touch the handle: when it is valid but no longer a live
 * survivor, invalidate it so the routine hits its own "no follow target"
 * early-out (right after GetTeamSituation) and never teleports. The bot does not
 * move, and the routine's guard clauses still govern everything else.
 */
public MRESReturn Detour_EnforceProximity_Pre(int bot)
{
	if (!g_cvEnable.BoolValue)
		return MRES_Ignored;

	Address base = GetEntityAddress(bot);
	if (base == Address_Null)
		return MRES_Ignored;

	Address followField = EntityField(base, g_iOfsFollowHuman);
	int handle = LoadFromAddress(followField, NumberType_Int32);

	if (handle == EHANDLE_INVALID || IsLiveSurvivorHandle(handle))
	{
		g_iLastClearedFollow[bot] = EHANDLE_INVALID;
		return MRES_Ignored;
	}

	StoreToAddress(followField, EHANDLE_INVALID, NumberType_Int32);

	if (handle != g_iLastClearedFollow[bot])
	{
		g_iLastClearedFollow[bot] = handle;
		LogFix("cleared %N's stale follow target (no longer a live survivor) to stop a forced relocation", bot);
	}
	return MRES_Ignored;
}

/**
 * ResolveStuckSituation branch B warps the bot to a random tracked teammate.
 * Compact that list in place so it holds only live survivors before the routine
 * reads it; branch A (path-forward recovery) is left to run normally.
 */
public MRESReturn Detour_ResolveStuck_Pre(int bot)
{
	if (!g_cvEnable.BoolValue)
		return MRES_Ignored;

	Address base = GetEntityAddress(bot);
	if (base == Address_Null)
		return MRES_Ignored;

	Address countField = EntityField(base, g_iOfsListCount);
	int rawCount = LoadFromAddress(countField, NumberType_Int32);
	if (rawCount <= 0)
		return MRES_Ignored;

	int count = (rawCount > SITUATION_LIST_CAPACITY) ? SITUATION_LIST_CAPACITY : rawCount;

	int kept = 0;
	for (int i = 0; i < count; i++)
	{
		int handle = LoadFromAddress(EntityField(base, g_iOfsList + i * 4), NumberType_Int32);
		if (!IsLiveSurvivorHandle(handle))
			continue;

		if (kept != i)
			StoreToAddress(EntityField(base, g_iOfsList + kept * 4), handle, NumberType_Int32);
		kept++;
	}

	if (kept != rawCount)
		StoreToAddress(countField, kept, NumberType_Int32);

	if (kept != count)
	{
		float now = GetGameTime();
		if (now - g_fLastStuckLog[bot] >= LOG_THROTTLE_SECONDS)
		{
			g_fLastStuckLog[bot] = now;
			LogFix("pruned %d stale teammate handle(s) from %N's stuck-resolve list", count - kept, bot);
		}
	}

	return MRES_Ignored;
}

/**
 * Every chasing NextBot routes its path through ChasePath::RefreshPath each tick. When a
 * survivor bot is found chasing a target that is no longer a live survivor (the player has
 * switched to the infected team to become the ZM), redirect the chase to the engine's own
 * closest reachable teammate. With no reachable teammate, skip the refresh so the bot never
 * builds a path toward the departed player.
 */
public MRESReturn Detour_RefreshPath_Pre(Address pThis, DHookParam hParams)
{
	if (!g_cvEnable.BoolValue || !g_cvChase.BoolValue)
		return MRES_Ignored;

	int target = ClientFromEntityAddress(view_as<Address>(DHookGetParam(hParams, 2)));
	if (target == -1)
		return MRES_Ignored;

	if (GetClientTeam(target) == TEAM_SURVIVOR && IsPlayerAlive(target))
		return MRES_Ignored;

	Address botBase = view_as<Address>(DHookGetParam(hParams, 1) - g_iOfsINextBot);
	int bot = ClientFromEntityAddress(botBase);
	if (bot == -1 || !IsFakeClient(bot) || GetClientTeam(bot) != TEAM_SURVIVOR)
		return MRES_Ignored;

	int friend = SDKCall(g_hGetClosestReachableFriend, EntityField(botBase, g_iOfsSituationBase));

	if (friend >= 1 && friend <= MaxClients && friend != bot
		&& IsClientInGame(friend) && GetClientTeam(friend) == TEAM_SURVIVOR && IsPlayerAlive(friend))
	{
		DHookSetParam(hParams, 2, view_as<int>(GetEntityAddress(friend)));
		ChaseLog(bot, target, friend);
		return MRES_ChangedOverride;
	}

	ChaseLog(bot, target, -1);
	return MRES_Supercede;
}

static void ChaseLog(int bot, int badTarget, int redirect)
{
	float now = GetGameTime();
	if (now - g_fLastChaseLog[bot] < LOG_THROTTLE_SECONDS)
		return;
	g_fLastChaseLog[bot] = now;

	if (redirect == -1)
		LogFix("stopped %N from chasing %N (no longer a live survivor); no reachable teammate to redirect to", bot, badTarget);
	else
		LogFix("redirected %N from chasing %N (no longer a live survivor) to %N", bot, badTarget, redirect);
}

static int ClientFromEntityAddress(Address base)
{
	if (base == Address_Null)
		return -1;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetEntityAddress(i) == base)
			return i;
	}
	return -1;
}

static bool IsLiveSurvivorHandle(int handle)
{
	if (handle == EHANDLE_INVALID)
		return false;

	int client = handle & EHANDLE_INDEX_MASK;
	if (client < 1 || client > MaxClients)
		return false;

	return IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

static Address EntityField(Address base, int offset)
{
	return view_as<Address>(view_as<int>(base) + offset);
}

public Action Cmd_Debug(int client, int args)
{
	ConVar cvRange = FindConVar("sb_enforce_proximity_range");
	float range = (cvRange != null) ? cvRange.FloatValue : -1.0;
	ReplyToCommand(client, "[zm-bot-stuck-fix] sb_enforce_proximity_range = %.1f", range);

	int found = 0;
	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (!IsClientInGame(bot) || !IsFakeClient(bot) || GetClientTeam(bot) != TEAM_SURVIVOR)
			continue;

		Address base = GetEntityAddress(bot);
		if (base == Address_Null)
			continue;
		found++;

		int follow = LoadFromAddress(EntityField(base, g_iOfsFollowHuman), NumberType_Int32);
		float distance = view_as<float>(LoadFromAddress(EntityField(base, g_iOfsFollowDistance), NumberType_Int32));

		char who[96];
		DescribeHandle(follow, who, sizeof(who));

		char gate[80];
		if (follow == EHANDLE_INVALID)
			strcopy(gate, sizeof(gate), "no follow target -> engine bails, no relocation");
		else if (range < 0.0)
			strcopy(gate, sizeof(gate), "range cvar not found");
		else if (distance > range)
			Format(gate, sizeof(gate), "dist %.0f > range %.0f -> would relocate to follow", distance, range);
		else
			Format(gate, sizeof(gate), "dist %.0f <= range %.0f -> no relocation", distance, range);

		ReplyToCommand(client, "%N: follow=%s | %s", bot, who, gate);

		int count = LoadFromAddress(EntityField(base, g_iOfsListCount), NumberType_Int32);
		ReplyToCommand(client, "    stuck-list count=%d", count);
		int shown = (count > SITUATION_LIST_CAPACITY) ? SITUATION_LIST_CAPACITY : count;
		for (int i = 0; i < shown; i++)
		{
			int handle = LoadFromAddress(EntityField(base, g_iOfsList + i * 4), NumberType_Int32);
			char entry[96];
			DescribeHandle(handle, entry, sizeof(entry));
			ReplyToCommand(client, "      [%d] %s", i, entry);
		}
	}

	if (found == 0)
		ReplyToCommand(client, "[zm-bot-stuck-fix] no survivor bots in game");
	return Plugin_Handled;
}

static void DescribeHandle(int handle, char[] buffer, int maxlen)
{
	if (handle == EHANDLE_INVALID)
	{
		strcopy(buffer, maxlen, "none (unset)");
		return;
	}

	int index = handle & EHANDLE_INDEX_MASK;
	if (index < 1 || index > MaxClients || !IsClientInGame(index))
	{
		Format(buffer, maxlen, "#%d (not a live client)", index);
		return;
	}

	Format(buffer, maxlen, "%N team=%d alive=%d%s",
		index, GetClientTeam(index), IsPlayerAlive(index),
		IsLiveSurvivorHandle(handle) ? " [live survivor]" : " [STALE]");
}

static void LogFix(const char[] format, any ...)
{
	if (!g_cvLog.BoolValue)
		return;

	char message[256];
	VFormat(message, sizeof(message), format, 2);
	LogMessage("[zm-bot-stuck-fix] %s", message);
}
