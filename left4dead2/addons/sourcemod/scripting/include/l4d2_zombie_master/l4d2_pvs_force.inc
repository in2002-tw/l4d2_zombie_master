///////////////////////////////////////
#if defined _zm_pvs_force_included
 #endinput
#endif
#define _zm_pvs_force_included
///////////////////////////////////////

#define PVSFORCE_EF_NODRAW 32

static ConVar g_cvPvsForceEnable;
static DynamicDetour g_ddSetupVisibility;
static Handle g_hAddOriginToPVS;
static bool g_bPvsForceAvailable;
static bool g_bPvsForceHooked;
static int g_PvsForceCount;
static ArrayList g_PvsForceEnts[MAXPLAYERS + 1];
static int g_PvsForcePrimary[MAXPLAYERS + 1];

static ConVar g_cvPvsForceProfile;
static Handle g_hPvsForceProfileTimer;
static float g_PvsForceProfileMs;
static int g_PvsForceProfileHookCalls;
static int g_PvsForceProfileWorkCalls;
static int g_PvsForceProfileInjects;

stock void PvsForce_Init()
{
	g_cvPvsForceEnable = CreateConVar("zm_pvs_force_enable", "1",
		"Render per-client entities (grid cells) through walls across the whole map. 0 = limit to normal PVS.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvPvsForceProfile = CreateConVar("zm_pvs_force_profile", "0",
		"Log per-second timing of the PVS injection callback (calls, injects, ms, us/call).",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_PvsForceEnts[i] == null)
			g_PvsForceEnts[i] = new ArrayList();
		g_PvsForcePrimary[i] = INVALID_ENT_REFERENCE;
	}

	if (g_hPvsForceProfileTimer == null)
		g_hPvsForceProfileTimer = CreateTimer(1.0, PvsForce_ProfileReport, _, TIMER_REPEAT);

	GameData gd = new GameData("zm_pvs_force");
	if (gd == null)
	{
		LogError("[zm pvs] Missing gamedata zm_pvs_force.txt; through-wall visibility disabled, using PVS-limited fallback.");
		return;
	}

	int offset = gd.GetOffset("AddOriginToPVS");
	if (offset != -1)
	{
		StartPrepSDKCall(SDKCall_Engine);
		PrepSDKCall_SetVirtual(offset);
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
		g_hAddOriginToPVS = EndPrepSDKCall();
	}

	g_ddSetupVisibility = DynamicDetour.FromConf(gd, "ClientSetupVisibility");
	delete gd;

	if (g_hAddOriginToPVS == null || g_ddSetupVisibility == null)
	{
		LogError("[zm pvs] Failed to resolve AddOriginToPVS or ClientSetupVisibility; through-wall visibility disabled, using PVS-limited fallback.");
		if (g_ddSetupVisibility != null)
		{
			delete g_ddSetupVisibility;
			g_ddSetupVisibility = null;
		}
		if (g_hAddOriginToPVS != null)
		{
			delete g_hAddOriginToPVS;
			g_hAddOriginToPVS = null;
		}
		return;
	}

	g_bPvsForceAvailable = true;
}

stock void PvsForce_Cleanup()
{
	if (g_hPvsForceProfileTimer != null)
	{
		KillTimer(g_hPvsForceProfileTimer);
		g_hPvsForceProfileTimer = null;
	}
	if (g_ddSetupVisibility != null)
	{
		if (g_bPvsForceHooked)
		{
			g_ddSetupVisibility.Disable(Hook_Post, PvsForce_OnSetupVisibility);
			g_bPvsForceHooked = false;
		}
		delete g_ddSetupVisibility;
		g_ddSetupVisibility = null;
	}
	if (g_hAddOriginToPVS != null)
	{
		delete g_hAddOriginToPVS;
		g_hAddOriginToPVS = null;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		delete g_PvsForceEnts[i];
		g_PvsForceEnts[i] = null;
	}
	g_PvsForceCount = 0;
	g_bPvsForceAvailable = false;
}

stock void PvsForce_Register(int entity, int client)
{
	if (client < 1 || client > MaxClients)
		return;
	if (g_PvsForceEnts[client] == null)
		g_PvsForceEnts[client] = new ArrayList();

	int ref = EntIndexToEntRef(entity);
	if (g_PvsForceEnts[client].FindValue(ref) != -1)
		return;

	g_PvsForceEnts[client].Push(ref);
	PvsForce_Retain();
}

stock void PvsForce_Unregister(int entity)
{
	PvsForce_UnregisterRef(EntIndexToEntRef(entity));
}

stock void PvsForce_UnregisterRef(int ref)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_PvsForceEnts[i] == null)
			continue;
		int idx = g_PvsForceEnts[i].FindValue(ref);
		if (idx != -1)
		{
			g_PvsForceEnts[i].Erase(idx);
			PvsForce_Release(1);
			return;
		}
	}
}

stock void PvsForce_SetPrimary(int client, int entity)
{
	if (client < 1 || client > MaxClients)
		return;
	g_PvsForcePrimary[client] = (entity > 0 && IsValidEntity(entity))
		? EntIndexToEntRef(entity) : INVALID_ENT_REFERENCE;
}

stock void PvsForce_OnClientDisconnect(int client)
{
	if (client < 1 || client > MaxClients)
		return;

	g_PvsForcePrimary[client] = INVALID_ENT_REFERENCE;

	if (g_PvsForceEnts[client] == null)
		return;

	int count = g_PvsForceEnts[client].Length;
	if (count > 0)
	{
		g_PvsForceEnts[client].Clear();
		PvsForce_Release(count);
	}
}

stock void PvsForce_Retain()
{
	g_PvsForceCount++;
	if (g_bPvsForceAvailable && !g_bPvsForceHooked)
	{
		g_ddSetupVisibility.Enable(Hook_Post, PvsForce_OnSetupVisibility);
		g_bPvsForceHooked = true;
	}
}

stock void PvsForce_Release(int amount)
{
	g_PvsForceCount -= amount;
	if (g_PvsForceCount > 0)
		return;

	g_PvsForceCount = 0;
	if (g_bPvsForceHooked)
	{
		g_ddSetupVisibility.Disable(Hook_Post, PvsForce_OnSetupVisibility);
		g_bPvsForceHooked = false;
	}
}

public MRESReturn PvsForce_OnSetupVisibility(Address pThis, DHookParam hParams)
{
	bool profile = (g_cvPvsForceProfile != null && g_cvPvsForceProfile.BoolValue);
	if (profile)
		g_PvsForceProfileHookCalls++;

	if (!g_bPvsForceAvailable || !g_cvPvsForceEnable.BoolValue)
		return MRES_Ignored;

	int client = DHookGetParam(hParams, 2);
	if (client < 1 || client > MaxClients)
		return MRES_Ignored;

	ArrayList list = g_PvsForceEnts[client];
	if (list == null || list.Length == 0)
		return MRES_Ignored;

	int ent = EntRefToEntIndex(g_PvsForcePrimary[client]);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
		return MRES_Ignored;
	if (GetEntProp(ent, Prop_Send, "m_fEffects") & PVSFORCE_EF_NODRAW)
		return MRES_Ignored;

	float t0 = profile ? GetEngineTime() : 0.0;

	float origin[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", origin);
	SDKCall(g_hAddOriginToPVS, origin);

	if (profile)
	{
		g_PvsForceProfileMs += (GetEngineTime() - t0) * 1000.0;
		g_PvsForceProfileWorkCalls++;
		g_PvsForceProfileInjects++;
	}
	return MRES_Ignored;
}

public Action PvsForce_ProfileReport(Handle timer)
{
	if (g_cvPvsForceProfile == null || !g_cvPvsForceProfile.BoolValue)
	{
		g_PvsForceProfileMs = 0.0;
		g_PvsForceProfileHookCalls = 0;
		g_PvsForceProfileWorkCalls = 0;
		g_PvsForceProfileInjects = 0;
		return Plugin_Continue;
	}

	float usPerWorkCall = (g_PvsForceProfileWorkCalls > 0)
		? (g_PvsForceProfileMs * 1000.0 / g_PvsForceProfileWorkCalls) : 0.0;

	LogMessage("[zm pvs] profile: hook %d/s (all clients), work %d/s, injects %d/s, %.3f ms/s work (%.1f us/work-call)",
		g_PvsForceProfileHookCalls, g_PvsForceProfileWorkCalls, g_PvsForceProfileInjects,
		g_PvsForceProfileMs, usPerWorkCall);

	g_PvsForceProfileMs = 0.0;
	g_PvsForceProfileHookCalls = 0;
	g_PvsForceProfileWorkCalls = 0;
	g_PvsForceProfileInjects = 0;
	return Plugin_Continue;
}
