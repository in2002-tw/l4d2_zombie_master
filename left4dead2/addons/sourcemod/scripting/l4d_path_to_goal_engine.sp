#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define PLUGIN_NAME     "l4d_path_to_goal_engine"
#define PLUGIN_VERSION  "0.1.0 2026-05-15"

public Plugin myinfo =
{
    name        = "[L4D2] Path To Goal (engine-sourced)",
    author      = "zyiks",
    description = "Renders the survivor path-to-goal by sampling the engine's CEscapeRoute entity. Reflects live nav state with no plugin-side cache.",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/gvazdas/l4d2_zombie_master"
};

/*
 * L4D2 maintains a singleton entity (classname "escape_route")
 * holding the current survivor path-to-goal. The engine
 * rebuilds it via A* whenever flow distances are recomputed, which happens
 * after any nav block/unblock settles, so it always reflects the live route
 * including dynamic map changes.
 *
 * This plugin samples that entity on demand and draws beams between samples.
 */

#define ESCAPE_ROUTE_CLASSNAME  "escape_route"
#define FLOW_TYPE_DEFAULT       0           // TerrorNavArea::FlowType::FLOW_DEFAULT
#define LASER_MATERIAL          "sprites/laserbeam.vmt"
#define MAX_BEAM_DURATION       60.0
#define PATH_GROUND_OFFSET      16.0        // lift samples off the floor so beams hover

#define DETOUR_MAX_WAYPOINTS    256         // m_parent chain depth we'll walk; merge collapses adjacent collinear waypoints so the beam budget isn't blown.
#define DETOUR_NEAREST_RADIUS   300.0       // max distance from sample point when resolving the nearest nav area for detour endpoints

#define TEAM_SPECTATOR  1
#define TEAM_SURVIVOR   2
#define TEAM_INFECTED   3

#define ALIVE_GATE_ANY    0
#define ALIVE_GATE_ALIVE  1
#define ALIVE_GATE_DEAD   2

int g_forwardColor[4]  = {100, 200, 100, 100};
int g_backwardColor[4] = {200, 100, 100, 100};
int g_detourColor[4]   = {100, 200, 220, 100};

// ---- Globals ----------------------------------------------------------------

Handle g_sdkGetPositionFromFlow;
int    g_offsetNavParent;       // CNavArea::m_parent byte offset (from gamedata)

ConVar g_cvEnable;
ConVar g_cvMaxBeams;
ConVar g_cvFlowStep;
ConVar g_cvDuration;
ConVar g_cvSurvivor;
ConVar g_cvInfected;
ConVar g_cvSpectator;
ConVar g_cvAliveGate;

int   g_laserModel;
float g_cooldownReady[MAXPLAYERS + 1];

// ---- Lifecycle --------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("L4D_Path_To_Goal_Engine", NativeRender);
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadSDK();
    CreateConVars();
    RegisterCommands();
}

public void OnMapStart()
{
    g_laserModel = PrecacheModel(LASER_MATERIAL, true);
}

public void OnClientPutInServer(int client)
{
    g_cooldownReady[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
    g_cooldownReady[client] = 0.0;
}

void LoadSDK()
{
    Handle gd = LoadGameConfigFile(PLUGIN_NAME);
    if (gd == null)
        SetFailState("Missing gamedata file: %s.txt", PLUGIN_NAME);

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CEscapeRoute::GetPositionFromFlow");
    PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float,        SDKPass_Plain);                              // flow
    PrepSDKCall_AddParameter(SDKType_Bool,         SDKPass_Plain);                              // interpolate
    PrepSDKCall_AddParameter(SDKType_Vector,       SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);    // out position
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);                              // flow type
    g_sdkGetPositionFromFlow = EndPrepSDKCall();

    g_offsetNavParent = GameConfGetOffset(gd, "CNavArea::m_parent");

    delete gd;

    if (g_sdkGetPositionFromFlow == null)
        SetFailState("Failed to prepare CEscapeRoute::GetPositionFromFlow SDKCall. Check gamedata signature for the current game build.");
    if (g_offsetNavParent <= 0)
        SetFailState("Missing or invalid offset CNavArea::m_parent in gamedata.");
}

// ---- ConVars ----------------------------------------------------------------

void CreateConVars()
{
    g_cvEnable = CreateConVar("l4d_path_to_goal_engine_enable", "1",
        "0 = OFF, 1 = ON.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvMaxBeams = CreateConVar("l4d_path_to_goal_engine_max", "16",
        "Maximum beams drawn per request.",
        FCVAR_NOTIFY, true, 1.0, true, 1000.0);

    g_cvFlowStep = CreateConVar("l4d_path_to_goal_engine_step", "256",
        "Flow distance between samples. Lower = denser path, more beams.",
        FCVAR_NOTIFY, true, 16.0, true, 4096.0);

    g_cvDuration = CreateConVar("l4d_path_to_goal_engine_duration", "5",
        "Default beam lifetime when no duration is passed.",
        FCVAR_NOTIFY, true, 1.0, true, MAX_BEAM_DURATION);

    g_cvSurvivor = CreateConVar("l4d_path_to_goal_engine_survivor", "1",
        "Allow survivors to request.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvInfected = CreateConVar("l4d_path_to_goal_engine_infected", "1",
        "Allow infected to request.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvSpectator = CreateConVar("l4d_path_to_goal_engine_spec", "1",
        "Allow spectators to request.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvAliveGate = CreateConVar("l4d_path_to_goal_engine_alive", "0",
        "Gating: 0 = any, 1 = alive only, 2 = dead only.",
        FCVAR_NOTIFY, true, 0.0, true, 2.0);

    AutoExecConfig(true, PLUGIN_NAME);
}

// ---- Commands and native ----------------------------------------------------

void RegisterCommands()
{
    RegConsoleCmd("path_to_goal_engine", CmdGuide, "Show engine-sourced path to goal.");
    RegConsoleCmd("pathtogoal2",         CmdGuide, "Show engine-sourced path to goal.");
    RegConsoleCmd("wheretogo2",          CmdGuide, "Show engine-sourced path to goal.");
    RegConsoleCmd("ptg2",                CmdGuide, "Show engine-sourced path to goal.");
}

Action CmdGuide(int client, int args)
{
    if (!IsClientValid(client) || IsFakeClient(client)) return Plugin_Continue;
    if (!g_cvEnable.BoolValue)                          return Plugin_Continue;
    if (!IsTeamAllowed(client))                         return Plugin_Continue;
    if (!IsAliveStateAllowed(client))                   return Plugin_Continue;
    if (IsOnCooldown(client))                           return Plugin_Continue;

    float duration = g_cvDuration.FloatValue;
    bool  drawBackward = (GetClientTeam(client) != TEAM_SURVIVOR);
    ParseArgs(args, duration, drawBackward);

    RenderPath(client, duration, drawBackward);
    StartCooldown(client, duration);
    return Plugin_Continue;
}

int NativeRender(Handle plugin, int numParams)
{
    int   client       = GetNativeCell(1);
    float duration     = (numParams >= 2) ? view_as<float>(GetNativeCell(2)) : g_cvDuration.FloatValue;
    bool  drawBackward = (numParams >= 3) ? view_as<bool>(GetNativeCell(3))  : false;

    if (!IsClientValid(client) || IsFakeClient(client)) return 0;
    if (!g_cvEnable.BoolValue)                          return 0;

    duration = ClampDuration(duration);
    RenderPath(client, duration, drawBackward);
    StartCooldown(client, duration);
    return 0;
}

void ParseArgs(int args, float &duration, bool &drawBackward)
{
    for (int i = 1; i <= args; i++)
    {
        char arg[16];
        GetCmdArg(i, arg, sizeof(arg));

        if      (StrEqual(arg, "backward", false)) drawBackward = true;
        else if (StrEqual(arg, "forward",  false)) drawBackward = false;
        else
        {
            float parsed = StringToFloat(arg);
            if (parsed > 0.0) duration = parsed;
        }
    }
    duration = ClampDuration(duration);
}

float ClampDuration(float duration)
{
    if (duration <= 0.0) return g_cvDuration.FloatValue;
    if (duration > MAX_BEAM_DURATION) return MAX_BEAM_DURATION;
    return duration;
}

// ---- Gating -----------------------------------------------------------------

bool IsTeamAllowed(int client)
{
    switch (GetClientTeam(client))
    {
        case TEAM_SPECTATOR: return g_cvSpectator.BoolValue;
        case TEAM_SURVIVOR:  return g_cvSurvivor.BoolValue;
        case TEAM_INFECTED:  return g_cvInfected.BoolValue;
    }
    return false;
}

bool IsAliveStateAllowed(int client)
{
    switch (g_cvAliveGate.IntValue)
    {
        case ALIVE_GATE_ALIVE: return IsPlayerAlive(client);
        case ALIVE_GATE_DEAD:  return !IsPlayerAlive(client);
    }
    return true;
}

#define MAX_SUBDIVISION_DEPTH 4

int g_beamBudget;

void RenderPath(int client, float duration, bool drawBackward)
{
    int escapeRoute = FindEscapeRoute();
    if (escapeRoute == -1) return;

    float maxFlow = L4D2Direct_GetMapMaxFlowDistance();
    if (maxFlow <= 0.0) return;

    float anchor[3];
    GetClientAnchor(client, anchor);

    float startFlow = ClampFlow(GetClientPathFlow(client), maxFlow);
    float step      = g_cvFlowStep.FloatValue;

    g_beamBudget = g_cvMaxBeams.IntValue;

    DrawRibbon(client, escapeRoute, anchor, duration,
               startFlow, maxFlow, step, g_forwardColor);

    if (drawBackward && startFlow > 0.0 && g_beamBudget > 0)
    {
        DrawRibbon(client, escapeRoute, anchor, duration,
                   startFlow, 0.0, -step, g_backwardColor);
    }
}

void DrawRibbon(int client, int escapeRoute, const float anchor[3], float duration,
                float startFlow, float endFlow, float step, const int color[4])
{
    float prev[3], cur[3];
    prev = anchor;

    bool walkingForward = (step > 0.0);
    float prevFlow = startFlow;
    float flow = startFlow;
    bool firstBeam = true;
    bool havePrev = true;
    float spanStart[3];

    float blockFlow = -1.0;
    {
        float scan = startFlow;
        while (InFlowBounds(scan, endFlow, walkingForward))
        {
            if (SamplePathAt(escapeRoute, scan, cur) && IsPositionBlocked(cur))
            {
                blockFlow = scan;
                break;
            }
            scan += step;
        }
    }
    if (blockFlow >= 0.0)
    {
        flow = blockFlow;
        spanStart = anchor;
        havePrev = false;
        prevFlow = startFlow;
    }
    else if (SamplePathAt(escapeRoute, flow, cur) && !HasWorldLOS(anchor, cur))
    {
        flow += step;
        while (InFlowBounds(flow, endFlow, walkingForward))
        {
            if (SamplePathAt(escapeRoute, flow, cur) && HasWorldLOS(anchor, cur)) break;
            flow += step;
        }
        prevFlow = flow;
    }

    while (g_beamBudget > 0 && InFlowBounds(flow, endFlow, walkingForward))
    {
        if (SamplePathAt(escapeRoute, flow, cur))
        {
            if (IsPositionBlocked(cur))
            {
                if (havePrev)
                {
                    spanStart = prev;
                    havePrev = false;
                }
            }
            else
            {
                if (havePrev)
                {
                    EmitBeam(client, escapeRoute, prev, cur, prevFlow, flow,
                             duration, color, firstBeam);
                }
                else
                {
                    SpliceDetour(client, spanStart, cur, duration);
                    havePrev = true;
                }
                prev = cur;
                prevFlow = flow;
                firstBeam = false;
            }
        }
        flow += step;
    }

    if (g_beamBudget > 0 && havePrev
        && SamplePathAt(escapeRoute, endFlow, cur) && !VectorsEqual(prev, cur)
        && !IsPositionBlocked(cur))
    {
        EmitBeam(client, escapeRoute, prev, cur, prevFlow, endFlow,
                 duration, color, firstBeam);
    }
}

Address NearestNavForSurvivor(const float pos[3])
{
    return L4D_GetNearestNavArea(pos, DETOUR_NEAREST_RADIUS, false, false, true, TEAM_SURVIVOR);
}

bool IsPositionBlocked(const float pos[3])
{
    Address navArea = NearestNavForSurvivor(pos);
    if (!navArea) return false;
    return L4D_NavArea_IsBlocked(navArea, TEAM_SURVIVOR, false)
        || L4D_NavArea_IsBlocked(navArea, TEAM_SURVIVOR, true);
}

void SpliceDetour(int client, const float from[3], const float to[3], float duration)
{
    Address navFrom = NearestNavForSurvivor(from);
    Address navTo   = NearestNavForSurvivor(to);
    if (!navFrom || !navTo) return;

    if (!L4D2_NavAreaBuildPath(navFrom, navTo, 0.0, TEAM_SURVIVOR, false)) return;

    float waypoints[DETOUR_MAX_WAYPOINTS][3];
    int count = 0;
    Address area = navTo;

    while (area && count < DETOUR_MAX_WAYPOINTS)
    {
        L4D_GetNavAreaCenter(area, waypoints[count]);
        waypoints[count][2] += PATH_GROUND_OFFSET;
        count++;
        if (area == navFrom) break;
        area = view_as<Address>(LoadFromAddress(area + view_as<Address>(g_offsetNavParent), NumberType_Int32));
    }

    if (count < 2) return;

    float prev[3];
    prev = from;
    int i = count - 1;
    while (i >= 0 && g_beamBudget > 0)
    {
        int j = i;
        while (j > 0 && HasWorldLOS(prev, waypoints[j - 1])) j--;
        DrawBeam(client, prev, waypoints[j], duration, g_detourColor);
        g_beamBudget--;
        prev = waypoints[j];
        i = j - 1;
    }
    if (g_beamBudget > 0 && !VectorsEqual(prev, to))
    {
        DrawBeam(client, prev, to, duration, g_detourColor);
        g_beamBudget--;
    }
}

void EmitBeam(int client, int escapeRoute, const float a[3], const float b[3],
              float aFlow, float bFlow, float duration, const int color[4],
              bool isAnchorBeam)
{
    if (g_beamBudget <= 0) return;

    if (isAnchorBeam)
    {
        if (HasWorldLOS(a, b))
        {
            DrawBeam(client, a, b, duration, color);
            g_beamBudget--;
        }
        return;
    }

    if (HasWorldLOS(a, b))
    {
        DrawBeam(client, a, b, duration, color);
        g_beamBudget--;
        return;
    }
    SubdivideAndEmit(client, escapeRoute, a, b, aFlow, bFlow,
                     duration, color, MAX_SUBDIVISION_DEPTH);
}

void SubdivideAndEmit(int client, int escapeRoute, const float a[3], const float b[3],
                     float aFlow, float bFlow, float duration, const int color[4],
                     int depth)
{
    if (g_beamBudget <= 0) return;

    if (depth <= 0 || HasWorldLOS(a, b))
    {
        DrawBeam(client, a, b, duration, color);
        g_beamBudget--;
        return;
    }

    float midFlow = (aFlow + bFlow) * 0.5;
    float mid[3];
    if (!SamplePathAt(escapeRoute, midFlow, mid)
        || VectorsEqual(mid, a) || VectorsEqual(mid, b))
    {
        DrawBeam(client, a, b, duration, color);
        g_beamBudget--;
        return;
    }

    SubdivideAndEmit(client, escapeRoute, a,   mid, aFlow,   midFlow, duration, color, depth - 1);
    SubdivideAndEmit(client, escapeRoute, mid, b,   midFlow, bFlow,   duration, color, depth - 1);
}

bool InFlowBounds(float flow, float endFlow, bool walkingForward)
{
    return walkingForward ? (flow <= endFlow) : (flow >= endFlow);
}

bool HasWorldLOS(const float a[3], const float b[3])
{
    TR_TraceRayFilter(a, b, MASK_SOLID, RayType_EndPoint, TraceFilterWorldOnly);
    return !TR_DidHit(INVALID_HANDLE);
}

bool TraceFilterWorldOnly(int entity, int contentsMask)
{
    return entity == 0;
}

void DrawBeam(int client, const float a[3], const float b[3], float duration, const int color[4])
{
    TE_SetupBeamPoints(a, b, g_laserModel, 0, 0, 0, duration, 1.0, 1.0, 1, 0.0, color, 0);
    TE_SendToClient(client);
}

void GetClientAnchor(int client, float anchor[3])
{
    if (IsPlayerAlive(client))
    {
        GetClientAbsOrigin(client, anchor);
        anchor[2] += 16.0;

        int waterLevel = GetEntProp(client, Prop_Send, "m_nWaterLevel");
        if      (waterLevel == 1) anchor[2] += 16.0;
        else if (waterLevel == 2) anchor[2] += 32.0;
    }
    else
    {
        float eye[3];
        GetClientEyePosition(client, eye);
        anchor[0] = eye[0];
        anchor[1] = eye[1];
        anchor[2] = eye[2] - 48.0;
    }
}

float GetClientPathFlow(int client)
{
    if (!IsPlayerAlive(client)) return 0.0;
    float flow = L4D2Direct_GetFlowDistance(client);
    return (flow > 0.0) ? flow : 0.0;
}

float ClampFlow(float flow, float maxFlow)
{
    if (flow < 0.0)     return 0.0;
    if (flow > maxFlow) return maxFlow;
    return flow;
}


int FindEscapeRoute()
{
    return FindEntityByClassname(-1, ESCAPE_ROUTE_CLASSNAME);
}

bool SamplePathAt(int escapeRoute, float flow, float outPos[3])
{
    SDKCall(g_sdkGetPositionFromFlow, escapeRoute, flow, true, outPos, FLOW_TYPE_DEFAULT);
    if (outPos[0] == 0.0 && outPos[1] == 0.0 && outPos[2] == 0.0) return false;
    outPos[2] += PATH_GROUND_OFFSET;
    return true;
}


bool IsOnCooldown(int client)
{
    return GetGameTime() < g_cooldownReady[client];
}

void StartCooldown(int client, float duration)
{
    g_cooldownReady[client] = GetGameTime() + duration * 0.5;
}


bool IsClientValid(int client)
{
    return client > 0 && client <= MaxClients
        && IsClientInGame(client)
        && !IsClientSourceTV(client)
        && !IsClientReplay(client);
}

bool VectorsEqual(const float a[3], const float b[3])
{
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}
