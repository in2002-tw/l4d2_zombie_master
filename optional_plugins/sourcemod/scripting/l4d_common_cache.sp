#include <sourcemod>
#include <left4dhooks>

#define PLUGIN_NAME			    "l4d_common_cache"
#define PLUGIN_VERSION 			"1.00"
#define CONFIG_FILENAME         PLUGIN_NAME

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Common Cache",
	author = "gvazdas, Silvers",
	description = "Reduce lag due to dynamic load of materials for Common Infected on Linux servers.",
	version = PLUGIN_VERSION,
	url = "https://knockout.chat/user/3022"
}

#define MAXENTITIES                   2048
#define DEBUG 0

ArrayList g_AllModels; // all infected models
bool g_bClientsCached[MAXPLAYERS+1] = {true,...}; // check if already cached for client
int g_iModel[MAXPLAYERS+1]; // track model in cycle for client
int g_iCycle[MAXPLAYERS+1] = {-1,...}; // track model in cycle for client. -1 for not in cycle
int g_iInfectedRef[MAXPLAYERS+1]; // track infected entity assigned to client
ConVar g_hCvarCycles;

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_PostNoCopy);
	g_hCvarCycles = CreateConVar("l4d_common_cache","5","How many times to repeat cycle. 0 to disable plugin",FCVAR_NOTIFY,true,0.0,true,100.0);
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bClientsCached[i] = false;
	}
}

public void OnMapStart()
{
	RequestFrame(LoadModels);
}

void LoadModels()
{
	// StringTable data
	int table = INVALID_STRING_TABLE;
	if( table == INVALID_STRING_TABLE ) table = FindStringTable("modelprecache");
	int total = GetStringTableNumStrings(table);
	static char sTemp[PLATFORM_MAX_PATH];
	delete g_AllModels;
	g_AllModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	for( int i = 0; i < total; i++ )
	{
		ReadStringTable(table, i, sTemp, sizeof(sTemp)); // "_w_ models appear to be gib related, i dont think they have this lag issue."
		if( strncmp(sTemp,"models/infected/common",22) == 0 && StrContains(sTemp,"_w_",false)<0 )
		//if( strncmp(sTemp,"models/infected/common",22) == 0 )
		{
			g_AllModels.PushString(sTemp);
		}
	}
	#if DEBUG
	LogMessage("modelprecache: %d models", g_AllModels.Length);
	#endif
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i)) g_bClientsCached[i] = true;
		else g_bClientsCached[i] = false;
	}
}

public void OnClientPutInServer(int client) // player_spawn doesn't always happen. spectators, for example.
{
    if (!IsValidClient(client)) return;
    if(IsFakeClient(client))
    {
        g_bClientsCached[client] = true;
        return;
    }
    #if DEBUG
    LogMessage("OnClientPutInServer %d %f", client, GetEngineTime());
    #endif
    g_bClientsCached[client] = false;
    g_iCycle[client] = -1; // not cycling
    g_iModel[client] = 0;
    if (g_hCvarCycles.IntValue<=0) return;
    CreateTimer(6.0,Timer_CycleModels,GetClientUserId(client),TIMER_FLAG_NO_MAPCHANGE);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_hCvarCycles.IntValue<=0) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client)) return;
	if(IsFakeClient(client)) return;
	#if DEBUG
	LogMessage("Event_PlayerSpawn %d %f", client, GetEngineTime());
	#endif
	if(g_bClientsCached[client] || g_iCycle[client]>=0) return; // skip if already cycling
	CreateTimer(0.1,Timer_CycleModels,GetClientUserId(client),TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_CycleModels(Handle timer, int userid)
{
    if (g_AllModels.Length <= 0) return Plugin_Stop;
    if (g_hCvarCycles.IntValue<=0) return Plugin_Stop;
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client)) return Plugin_Stop;
    if(g_bClientsCached[client] || g_iCycle[client]>=0) return Plugin_Stop;
    g_iModel[client] = 0;
    g_iCycle[client] = 0;
    RequestFrame(CycleModels,GetClientUserId(client));
    return Plugin_Stop;
}

void CycleModels(int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
    {
        cleanup_infected();
        return;
    }
    int entref_infected = g_iInfectedRef[client];
    if (g_iModel[client]==0 && IsValidEntRef(entref_infected)) // new zombie for new cycle
    {
        RemoveEntity(entref_infected);
        g_iInfectedRef[client] = INVALID_ENT_REFERENCE;
        entref_infected = INVALID_ENT_REFERENCE;
    }
    if (g_iCycle[client]>=g_hCvarCycles.IntValue) // end of cycle
    {
        g_iCycle[client] = -1;
        g_bClientsCached[client] = true;
        return;
    }
    if (!IsValidEntRef(entref_infected))
    {
        static float vPos[3];
        //if( !L4D_GetRandomPZSpawnPosition(client,0,5,vPos) ) GetClientAbsOrigin(client,vPos);
        GetClientAbsOrigin(client,vPos);
        vPos[2] += 120.0;
        int infected = CreateEntityByName("infected");
        if (!IsValidEntity_Safe(infected))
        {
            g_iCycle[client] = -1;
            return;
        }
        SDKHook(infected, SDKHook_SetTransmit, OnTransmit);
        TeleportEntity(infected, vPos, NULL_VECTOR, NULL_VECTOR);
        DispatchSpawn(infected);
        SetEntityRenderMode(infected,RENDER_NONE);
        SetEntPropFloat(infected,Prop_Send,"m_flModelScale",0.001); 
        SetEntProp(infected,Prop_Data,"m_takedamage",0);
        SetEntityMoveType(infected, MOVETYPE_NONE);
        SetEntProp(infected,Prop_Data,"m_iHealth",99999);
        SetEntProp(infected,Prop_Data,"m_iMaxHealth",99999);
        SetEntProp(infected,Prop_Data,"m_nNextThinkTick",-1);
        SetEntProp(infected, Prop_Data, "m_nSolidType", 0);
        SetEntProp(infected, Prop_Data, "m_CollisionGroup", 1);
        entref_infected = EntIndexToEntRef(infected);
        g_iInfectedRef[client] = entref_infected;
        #if DEBUG
        LogMessage("%d new infected %d %d", client, infected, entref_infected);
        #endif
    }
    static char model[128];
    g_AllModels.GetString(g_iModel[client],model,sizeof(model));
    SetEntityModel(entref_infected, model);
    #if DEBUG
    LogMessage("%d %d %d %s", client, g_iCycle[client], g_iModel[client], model);
    #endif
    g_iModel[client] += 1;
    if (g_iModel[client]>=g_AllModels.Length)
    {
        g_iModel[client] = 0;
        g_iCycle[client] += 1;
    }
    RequestFrame(CycleModels,userid);
}

// Transmit only to clients who are known to need precaching.
Action OnTransmit(int entity, int client)
{
	if(g_bClientsCached[client]) return Plugin_Handled;
	return Plugin_Continue;
}

// A client disappeared in the middle of a cycle - find loose infected and remove them.
void cleanup_infected()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if ( (g_iCycle[i]<0 || !IsValidClient(i)) && IsValidEntRef(g_iInfectedRef[i]) )
        {
            #if DEBUG
            LogMessage("cleanup_infected %d %d", i, g_iInfectedRef[i]);
            #endif
            RemoveEntity(g_iInfectedRef[i]);
            g_iInfectedRef[i] = INVALID_ENT_REFERENCE;
            g_iModel[i] = -1;
        }
    }
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