/**
 * ZM Survivor Bot Stuck Fix
 *
 * The moment a survivor leaves the team, we reach into every survivor bot and:
 *   - null the team-situation follow-human handle if it points at them (the one-tick
 *     EnforceProximityToHumans relocate), and
 *   - walk the bot's behavior-action tree and null any Action's cached chase target that
 *     equals the departed player. The engine self-heals next tick (Regroup falls back to
 *     its closest reachable teammate, the Cover/Approach actions end "target gone").
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "2.0"

#define TEAM_SURVIVOR 2

#define EHANDLE_INDEX_MASK 0xFFF
#define EHANDLE_INVALID    -1

// The team-situation teammate list is a fixed-size array; the engine only ever copies up
// to this many entries out of it.
#define SITUATION_LIST_CAPACITY 4

#define WALK_MAX_NODES 64

ConVar g_cvEnable;
ConVar g_cvLog;

int g_iOfsFollowHuman;     // GetTeamSituation()+0x30: single "follow human" EHANDLE
int g_iOfsList;            // GetTeamSituation()+0x88: tracked-teammate EHANDLE array
int g_iOfsListCount;       // GetTeamSituation()+0xc4: entries in that array
int g_iOfsFollowDistance;  // GetTeamSituation()+0x34: distance vs sb_enforce_proximity_range (debug)

int g_iOfsINextBot;        // CTerrorPlayer -> INextBot subobject
int g_iOfsChaseTarget;     // Legs Action +0x34: cached chase-target EHANDLE
int g_iOfsActionBuried;    // Action +0x14: m_buriedUnderMe (suspended-action stack link)
int g_iOfsActionCovering;  // Action +0x18: m_coveringMe (suspended-action stack link)

Handle g_hGetIntention;    // INextBot::GetIntentionInterface()
Handle g_hFirstResponder;  // INextBotEventResponder::FirstContainedResponder()
Handle g_hNextResponder;   // INextBotEventResponder::NextContainedResponder(prev)
Handle g_hGetRefEHandle;   // CBaseEntity::GetRefEHandle()
Handle g_hGetName;         // Action::GetName() - diagnostic walk-dump labelling only

int g_iLastClearedFollow[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "ZM Survivor Bot Stuck Fix",
	author		= "zyiks",
	description	= "Stops survivor bots from chasing/teleporting onto team-switched players and falling to their death",
	version		= PLUGIN_VERSION,
	url			= ""
};

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("zm_bot_stuck_fix_enable", "1",
		"Enable the survivor-bot stale-target fix.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvLog = CreateConVar("zm_bot_stuck_fix_log", "1",
		"Log to the server log whenever a stale bot target is cleared.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	GameData gd = new GameData("zm_bot_stuck_fix");
	if (gd == null)
		SetFailState("Missing gamedata: zm_bot_stuck_fix.txt");

	g_iOfsFollowHuman    = LoadOffset(gd, "Situation_FollowHuman");
	g_iOfsList           = LoadOffset(gd, "Situation_List");
	g_iOfsListCount      = LoadOffset(gd, "Situation_ListCount");
	g_iOfsFollowDistance = LoadOffset(gd, "Situation_FollowDistance");
	g_iOfsINextBot       = LoadOffset(gd, "INextBot_Subobject");
	g_iOfsChaseTarget    = LoadOffset(gd, "Action_ChaseTarget");
	g_iOfsActionBuried   = LoadOffset(gd, "Action_BuriedUnder");
	g_iOfsActionCovering = LoadOffset(gd, "Action_Covering");

	g_hGetIntention   = SetupVirtual(gd, "VT_GetIntentionInterface",   SDKCall_Raw,    false);
	g_hFirstResponder = SetupVirtual(gd, "VT_FirstContainedResponder", SDKCall_Raw,    false);
	g_hNextResponder  = SetupVirtual(gd, "VT_NextContainedResponder",  SDKCall_Raw,    true);
	g_hGetRefEHandle  = SetupVirtual(gd, "VT_GetRefEHandle",           SDKCall_Entity, false);
	g_hGetName        = SetupVirtual(gd, "VT_GetName",                 SDKCall_Raw,    false);

	delete gd;

	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	RegAdminCmd("sm_botstuck_debug", Cmd_Debug, ADMFLAG_ROOT,
		"Dump each survivor bot's follow-human, proximity gate, and team-situation list.");

	for (int i = 1; i <= MaxClients; i++)
		g_iLastClearedFollow[i] = EHANDLE_INVALID;

	LogMessage("[zm-bot-stuck-fix] loaded; hooked player_team (one-shot mode)");
}

static int LoadOffset(GameData gd, const char[] key)
{
	int offset = gd.GetOffset(key);
	if (offset == -1)
		SetFailState("Missing offset in gamedata: %s", key);
	return offset;
}

static Handle SetupVirtual(GameData gd, const char[] key, SDKCallType callType, bool hasParam)
{
	int index = gd.GetOffset(key);
	if (index == -1)
		SetFailState("Missing vtable index in gamedata: %s", key);

	StartPrepSDKCall(callType);
	PrepSDKCall_SetVirtual(index);
	if (hasParam)
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

	Handle call = EndPrepSDKCall();
	if (call == null)
		SetFailState("Failed to prepare SDKCall: %s", key);
	return call;
}

/**
 * A survivor left the survivor team. Defer the cleanup to the NEXT frame
 * The walk reaches the whole action stack (active plus suspended),
 * a single pass clears every stale target.
 */
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
		return;
	if (event.GetBool("disconnect"))
		return;

	if (event.GetInt("oldteam") != TEAM_SURVIVOR || event.GetInt("team") == TEAM_SURVIVOR)
		return;

	RequestFrame(Frame_ClearStaleTargets);
}

public void Frame_ClearStaleTargets()
{
	if (!g_cvEnable.BoolValue)
		return;

	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (!IsClientInGame(bot) || !IsFakeClient(bot) || GetClientTeam(bot) != TEAM_SURVIVOR)
			continue;

		Address base = GetEntityAddress(bot);
		if (base == Address_Null)
			continue;

		CleanStaleFollow(bot, base);
		ClearChaseTargets(bot, base);
	}
}

static int RefEHandle(int client)
{
	Address handlePtr = view_as<Address>(SDKCall(g_hGetRefEHandle, client));
	if (handlePtr == Address_Null)
		return EHANDLE_INVALID;
	return LoadFromAddress(handlePtr, NumberType_Int32);
}

/**
 * EnforceProximityToHumans warps a too-far bot to the team-situation follow-human handle.
 * If that handle still points at the player who just left, null it so the routine takes
 * its own "no follow target" early-out next time it runs.
 */
static void CleanStaleFollow(int bot, Address base)
{
	Address field = EntityField(base, g_iOfsFollowHuman);
	int handle = LoadFromAddress(field, NumberType_Int32);

	if (handle == EHANDLE_INVALID || IsLiveSurvivorHandle(handle))
		return;

	StoreToAddress(field, EHANDLE_INVALID, NumberType_Int32);
	LogFix("cleared %N's stale follow target (no longer a live survivor)", bot);
}

/**
 * Walk the bot's behavior-action tree (intention -> behavior(s) -> action chains) and null
 * any Action whose cached chase target is no longer a live survivor.
 */
static void ClearChaseTargets(int bot, Address base)
{
	Address intention = view_as<Address>(SDKCall(g_hGetIntention, EntityField(base, g_iOfsINextBot)));
	if (intention == Address_Null)
		return;

	Address nodes[WALK_MAX_NODES];
	int depths[WALK_MAX_NODES];
	Address seen[WALK_MAX_NODES];
	int seenCount = 0;
	int top = 0;

	top = PushNode(nodes, depths, top, seen, seenCount, intention, 0);

	char walk[768];
	walk[0] = '\0';

	while (top > 0)
	{
		top--;
		Address node = nodes[top];
		int depth = depths[top];

		// intention is depth 0, behaviors depth 1, actions depth 2+.
		if (depth >= 2)
		{
			Address field = EntityField(node, g_iOfsChaseTarget);
			int raw = LoadFromAddress(field, NumberType_Int32);
			int target = GenuineHandleClient(raw);

			char name[48];
			ActionName(node, name, sizeof(name));

			char entry[128];
			Format(entry, sizeof(entry), "%s%s@0x%x(+34:#%d)",
				(walk[0] != '\0') ? " <- " : "", name, view_as<int>(node), raw & EHANDLE_INDEX_MASK);
			StrCat(walk, sizeof(walk), entry);

			if (target != -1 && !IsLiveSurvivor(target))
			{
				StoreToAddress(field, EHANDLE_INVALID, NumberType_Int32);
				LogFix("cleared %N's chase target (%N) at action 0x%x", bot, target, view_as<int>(node));
			}

			top = PushNode(nodes, depths, top, seen, seenCount,
				view_as<Address>(LoadFromAddress(EntityField(node, g_iOfsActionBuried), NumberType_Int32)), depth);
			top = PushNode(nodes, depths, top, seen, seenCount,
				view_as<Address>(LoadFromAddress(EntityField(node, g_iOfsActionCovering), NumberType_Int32)), depth);
		}

		Address child = view_as<Address>(SDKCall(g_hFirstResponder, node));
		while (child != Address_Null)
		{
			top = PushNode(nodes, depths, top, seen, seenCount, child, depth + 1);
			child = view_as<Address>(SDKCall(g_hNextResponder, node, child));
		}
	}

	if (g_cvLog.BoolValue && walk[0] != '\0')
		LogMessage("[zm-bot-stuck-fix]   [walk-dump] %N tree: %s", bot, walk);
}

static int PushNode(Address[] nodes, int[] depths, int top, Address[] seen, int &seenCount,
	Address node, int depth)
{
	if (node == Address_Null)
		return top;

	for (int i = 0; i < seenCount; i++)
		if (seen[i] == node)
			return top;

	if (seenCount >= WALK_MAX_NODES || top >= WALK_MAX_NODES)
		return top;

	seen[seenCount++] = node;
	nodes[top] = node;
	depths[top] = depth;
	return top + 1;
}

static void ActionName(Address action, char[] buffer, int maxlen)
{
	Address namePtr = view_as<Address>(SDKCall(g_hGetName, action));
	if (namePtr == Address_Null)
	{
		strcopy(buffer, maxlen, "(null)");
		return;
	}

	int i = 0;
	for (; i < maxlen - 1; i++)
	{
		int b = LoadFromAddress(view_as<Address>(view_as<int>(namePtr) + i), NumberType_Int8) & 0xFF;
		if (b == 0)
			break;
		buffer[i] = b;
	}
	buffer[i] = '\0';
}

static int GenuineHandleClient(int handle)
{
	if (handle == EHANDLE_INVALID)
		return -1;

	int client = handle & EHANDLE_INDEX_MASK;
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return -1;

	if (RefEHandle(client) != handle)
		return -1;

	return client;
}

static bool IsLiveSurvivor(int client)
{
	return GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client);
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
		index, GetClientTeam(index), view_as<int>(IsPlayerAlive(index)),
		IsLiveSurvivorHandle(handle) ? " [live survivor]" : " [STALE]");
}

static void LogFix(const char[] format, any ...)
{
	if (!g_cvLog.BoolValue)
		return;

	char message[256];
	VFormat(message, sizeof(message), format, 2);
	LogMessage("[zm-bot-stuck-fix] (tick %d) %s", GetGameTickCount(), message);
}
