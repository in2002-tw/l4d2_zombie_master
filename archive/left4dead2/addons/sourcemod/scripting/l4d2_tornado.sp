#include < sourcemod >
#include < sdktools >
#include < sdkhooks >

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

#define TORNADO_RADIUS 650.0
#define TORNADO_HEIGHT 800.0
#define FORCE_SUCTION 900.0
#define FORCE_TANGENT 120.0
#define FORCE_LIFT    650.0
#define FORCE_SUCTION_PHASE1 300.0
#define PHASE1_DURATION 5.0
#define PHASE2_DURATION 30.0
#define PHYS_INTERVAL 0.1
#define SINGULARITY_RADIUS 200.0

#define PARTICLE_CORE "smoke_burning_engine_01"

#define SOUND_WIND "ambient/wind/windgust_strong.wav"

char g_sSoundThunder[][] = {
    "ambient/weather/thunderstorm/thunder_1.wav",
    "ambient/weather/thunderstorm/thunder_2.wav",
    "ambient/weather/thunderstorm/thunder_3.wav"
};

char g_sSoundImpact[][] = {
    "ambient/wind/wind_hit1.wav",
    "ambient/wind/wind_hit2.wav",
    "ambient/wind/wind_hit3.wav"
};

ConVar g_cvForcePlayerScale;
ConVar g_cvForcePropScale;
ConVar g_cvSingularityRadius;
ConVar g_cvSingularityOrbitRadius;
ConVar g_cvSingularityPushStrength;
ConVar g_cvSingularityPullStrength;
ConVar g_cvSingularityTangentMult;
ConVar g_cvSingularityLiftMult;

#define MAX_PARTICLES 13
#define ROTATION_SPEED 9.0

    enum struct Tornado
{
    int iAnchor;
    int iSoundEmitter;
    int iVisuals[MAX_PARTICLES];

    Handle hPhysicsTimer;
    Handle hRotationTimer;
    Handle hImpactSoundTimer;
    Handle hDebugBeamTimer;

    int iPhase;
    float fOrigin[3];
    bool bDebugRadius;

    float fParticleAngle[MAX_PARTICLES];
    float fParticleRadius[MAX_PARTICLES];
    float fParticleHeight[MAX_PARTICLES];

    void Reset()
    {
        this.iAnchor = - 1;
        this.iSoundEmitter = - 1;
        for (int i = 0; i < MAX_PARTICLES; i++)
        {
            this.iVisuals[i] = - 1;
        }
        this.hPhysicsTimer = null;
        this.hRotationTimer = null;
        this.hImpactSoundTimer = null;
        this.hDebugBeamTimer = null;
        this.iPhase = 0;
        this.bDebugRadius = false;
    }

    bool IsActive()
    {
        return this.iPhase > 0;
    }
}

Tornado g_Tornado;

int g_iBeamSprite = - 1;

bool g_bFallDamageImmune[MAXPLAYERS + 1] = {false, ...};
Handle g_hImmunityTimer[MAXPLAYERS + 1] = {null, ...};
#define IMMUNITY_DURATION 3.0

public Plugin myinfo = {
    name = "L4D2 Tornado Creator",
    author = "zyiks",
    description = "Spawns a tornado that lifts and spins entities.",
    version = PLUGIN_VERSION,
    url = "no"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_tornado", Cmd_SpawnTornado, ADMFLAG_CHEATS, "Spawns a tornado where you are looking.");
    RegAdminCmd("sm_tornado_debug", Cmd_DebugRadius, ADMFLAG_CHEATS, "Toggles debug visualization of tornado radius.");

    g_cvForcePlayerScale = CreateConVar("sm_tornado_player_force", "0.8", "Force multiplier for players (default: 0.8)", FCVAR_NOTIFY, true, 0.1, true, 5.0);
    g_cvForcePropScale = CreateConVar("sm_tornado_prop_force", "2.0", "Force multiplier for props (default: 2.0)", FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_cvSingularityRadius = CreateConVar("sm_tornado_singularity_radius", "200.0", "Radius of center zone", FCVAR_NOTIFY, true, 50.0, true, 500.0);
    g_cvSingularityOrbitRadius = CreateConVar("sm_tornado_orbit_radius", "150.0", "Target orbital radius in center zone", FCVAR_NOTIFY, true, 50.0, true, 400.0);
    g_cvSingularityPushStrength = CreateConVar("sm_tornado_push_strength", "15.0", "Strength of outward push when too close to center", FCVAR_NOTIFY, true, 1.0, true, 50.0);
    g_cvSingularityPullStrength = CreateConVar("sm_tornado_pull_strength", "5.0", "Strength of inward pull when too far from center", FCVAR_NOTIFY, true, 1.0, true, 50.0);
    g_cvSingularityTangentMult = CreateConVar("sm_tornado_spin_multiplier", "6.0", "Tangential force multiplier for spinning in center zone", FCVAR_NOTIFY, true, 1.0, true, 20.0);
    g_cvSingularityLiftMult = CreateConVar("sm_tornado_lift_multiplier", "0.7", "Lift force multiplier in center zone", FCVAR_NOTIFY, true, 0.1, true, 2.0);

    AutoExecConfig(true, "l4d2_tornado");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    ClearPlayerImmunity(client);
}

public void OnMapStart()
{
    PrecacheParticle(PARTICLE_CORE);

    PrecacheSound(SOUND_WIND);

    for (int i = 0; i < sizeof(g_sSoundThunder); i++)
    {
        PrecacheSound(g_sSoundThunder[i]);
    }

    for (int i = 0; i < sizeof(g_sSoundImpact); i++)
    {
        PrecacheSound(g_sSoundImpact[i]);
    }

    g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");

    g_Tornado.Reset();
}

public void OnPluginEnd()
{
    if (g_Tornado.IsActive())
    {
        StopTornado();
    }
}

public Action Cmd_DebugRadius(int client, int args)
{
    g_Tornado.bDebugRadius = !g_Tornado.bDebugRadius;
    PrintToChat(client, "[Tornado] Debug radius visualization: %s", g_Tornado.bDebugRadius ? "ON" : "OFF");
    return Plugin_Handled;
}

public Action Cmd_SpawnTornado(int client, int args)
{
    if (!IsClientInGame(client)) return Plugin_Handled;

    float eyePos[3], eyeAng[3], endPos[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);

    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, TraceFilter_NoPlayers);

    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(endPos, trace);

        endPos[2] += 10.0;

        StopTornado();
        StartTornado(endPos);

        PrintToChat(client, "[Tornado] Tornado spawned! Total Duration: %0.0fs", PHASE1_DURATION + PHASE2_DURATION);
    }
    else
    {
        PrintToChat(client, "[Tornado] Could not find a surface to spawn tornado.");
    }

    delete trace;
    return Plugin_Handled;
}

void StartTornado(float origin[3])
{
    g_Tornado.fOrigin[0] = origin[0];
    g_Tornado.fOrigin[1] = origin[1];
    g_Tornado.fOrigin[2] = origin[2];

    g_Tornado.iPhase = 1;

    g_Tornado.iAnchor = CreateEntityByName("info_target");
    if (g_Tornado.iAnchor != - 1)
    {
        DispatchSpawn(g_Tornado.iAnchor);
        TeleportEntity(g_Tornado.iAnchor, origin, NULL_VECTOR, NULL_VECTOR);
        SetEntityMoveType(g_Tornado.iAnchor, MOVETYPE_NONE);
    }

    CreateTornadoSound(origin);

    g_Tornado.hPhysicsTimer = CreateTimer(PHYS_INTERVAL, Timer_TornadoPhysics, _, TIMER_REPEAT);

    if (g_Tornado.bDebugRadius)
    {
        g_Tornado.hDebugBeamTimer = CreateTimer(0.1, Timer_DrawDebugBeams, _, TIMER_REPEAT);
    }

    CreateTimer(PHASE1_DURATION, Timer_StartPhase2);

    CreateTimer(PHASE1_DURATION + PHASE2_DURATION, Timer_StopTornado);

    PrintToChatAll("[Tornado] Phase 1: Pulling entities towards center... (%0.0fs)", PHASE1_DURATION);
}

void CreateTornadoSound(float origin[3])
{
    g_Tornado.iSoundEmitter = CreateEntityByName("ambient_generic");
    if (g_Tornado.iSoundEmitter == - 1)
    {
        PrintToChatAll("[Tornado] Warning: Failed to create sound emitter");
        return ;
    }

    DispatchKeyValue(g_Tornado.iSoundEmitter, "message", SOUND_WIND);
    DispatchKeyValue(g_Tornado.iSoundEmitter, "health", "100");
    DispatchKeyValue(g_Tornado.iSoundEmitter, "pitch", "100");
    DispatchKeyValue(g_Tornado.iSoundEmitter, "radius", "2500");
    DispatchKeyValue(g_Tornado.iSoundEmitter, "spawnflags", "1");

    DispatchSpawn(g_Tornado.iSoundEmitter);
    ActivateEntity(g_Tornado.iSoundEmitter);

    TeleportEntity(g_Tornado.iSoundEmitter, origin, NULL_VECTOR, NULL_VECTOR);

    AcceptEntityInput(g_Tornado.iSoundEmitter, "PlaySound");

    PrintToChatAll("[Tornado] Wind sound started");
}

void CreateTornadoParticles(float origin[3])
{
    int particleCount = 0;

    for (int i = 0; i < MAX_PARTICLES; i++)
    {
        float spiralRotation = (360.0 / MAX_PARTICLES) * i + (i * 45.0);
        float radians = DegToRad(spiralRotation);

        float height = i * 60.0;

        float bottomRadius = 50.0;
        float topRadius = 150.0;
        float heightRatio = float(i) / float(MAX_PARTICLES - 1);
        float radius = bottomRadius + ((topRadius - bottomRadius) * heightRatio);

        float offset[3];
        offset[0] = origin[0] + (Cosine(radians) * radius);
        offset[1] = origin[1] + (Sine(radians) * radius);
        offset[2] = origin[2] + height;

        int particle = CreateEntityByName("info_particle_system");
        if (particle == - 1)
        {
            PrintToChatAll("[Tornado] Warning: Failed to create particle %d", i);
            continue;
        }

        DispatchKeyValue(particle, "effect_name", PARTICLE_CORE);
        DispatchKeyValue(particle, "start_active", "1");

        if (!DispatchSpawn(particle))
        {
            PrintToChatAll("[Tornado] Warning: Failed to spawn particle %d", i);
            AcceptEntityInput(particle, "Kill");
            continue;
        }

        TeleportEntity(particle, offset, NULL_VECTOR, NULL_VECTOR);

        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");

        g_Tornado.iVisuals[i] = particle;

        g_Tornado.fParticleAngle[i] = spiralRotation;
        g_Tornado.fParticleRadius[i] = radius;
        g_Tornado.fParticleHeight[i] = height;

        particleCount++;
    }

    PrintToChatAll("[Tornado] Created %d/%d smoke particles in spiral pattern", particleCount, MAX_PARTICLES);
}

public Action Timer_RotateParticles(Handle timer)
{
    if (!IsValidEntity(g_Tornado.iAnchor))
    {
        g_Tornado.hRotationTimer = null;
        return Plugin_Stop;
    }

    for (int i = 0; i < MAX_PARTICLES; i++)
    {
        if (!IsValidEntity(g_Tornado.iVisuals[i]))
        continue;

        g_Tornado.fParticleAngle[i] += ROTATION_SPEED;
        if (g_Tornado.fParticleAngle[i] >= 360.0)
        g_Tornado.fParticleAngle[i] -= 360.0;

        float radians = DegToRad(g_Tornado.fParticleAngle[i]);
        float newPos[3];
        newPos[0] = g_Tornado.fOrigin[0] + (Cosine(radians) * g_Tornado.fParticleRadius[i]);
        newPos[1] = g_Tornado.fOrigin[1] + (Sine(radians) * g_Tornado.fParticleRadius[i]);
        newPos[2] = g_Tornado.fOrigin[2] + g_Tornado.fParticleHeight[i];

        TeleportEntity(g_Tornado.iVisuals[i], newPos, NULL_VECTOR, NULL_VECTOR);
    }

    return Plugin_Continue;
}

public Action Timer_StartPhase2(Handle timer)
{
    if (!IsValidEntity(g_Tornado.iAnchor))
    {
        return Plugin_Stop;
    }

    g_Tornado.iPhase = 2;

    PrintToChatAll("[Tornado] Phase 2: Full tornado activated! (%0.0fs)", PHASE2_DURATION);

    CreateTornadoParticles(g_Tornado.fOrigin);

    g_Tornado.hRotationTimer = CreateTimer(PHYS_INTERVAL, Timer_RotateParticles, _, TIMER_REPEAT);

    g_Tornado.hImpactSoundTimer = CreateTimer(1.5, Timer_PlayRandomSounds, _, TIMER_REPEAT);

    return Plugin_Stop;
}

public Action Timer_DrawDebugBeams(Handle timer)
{
    if (!IsValidEntity(g_Tornado.iAnchor))
    {
        g_Tornado.hDebugBeamTimer = null;
        return Plugin_Stop;
    }

    #define NUM_CIRCLE_SEGMENTS 12
    #define NUM_VERTICAL_LINES 8
    #define BEAM_LIFE 0.15

    float angle, nextAngle;
    float pos1[3], pos2[3], pos3[3], pos4[3];

    for (int i = 0; i < NUM_CIRCLE_SEGMENTS; i++)
    {
        angle = (360.0 / NUM_CIRCLE_SEGMENTS) * i;
        nextAngle = (360.0 / NUM_CIRCLE_SEGMENTS) * ((i + 1) % NUM_CIRCLE_SEGMENTS);

        float radians1 = DegToRad(angle);
        float radians2 = DegToRad(nextAngle);

        pos1[0] = g_Tornado.fOrigin[0] + (Cosine(radians1) * TORNADO_RADIUS);
        pos1[1] = g_Tornado.fOrigin[1] + (Sine(radians1) * TORNADO_RADIUS);
        pos1[2] = g_Tornado.fOrigin[2] + 10.0;

        pos2[0] = g_Tornado.fOrigin[0] + (Cosine(radians2) * TORNADO_RADIUS);
        pos2[1] = g_Tornado.fOrigin[1] + (Sine(radians2) * TORNADO_RADIUS);
        pos2[2] = g_Tornado.fOrigin[2] + 10.0;

        pos3[0] = g_Tornado.fOrigin[0] + (Cosine(radians1) * TORNADO_RADIUS);
        pos3[1] = g_Tornado.fOrigin[1] + (Sine(radians1) * TORNADO_RADIUS);
        pos3[2] = g_Tornado.fOrigin[2] + TORNADO_HEIGHT;

        pos4[0] = g_Tornado.fOrigin[0] + (Cosine(radians2) * TORNADO_RADIUS);
        pos4[1] = g_Tornado.fOrigin[1] + (Sine(radians2) * TORNADO_RADIUS);
        pos4[2] = g_Tornado.fOrigin[2] + TORNADO_HEIGHT;

        TE_SetupBeamPoints(pos1, pos2, g_iBeamSprite, 0, 0, 0, BEAM_LIFE, 3.0, 3.0, 1, 0.0, {0, 255, 255, 255}, 0);
        TE_SendToAll();

        TE_SetupBeamPoints(pos3, pos4, g_iBeamSprite, 0, 0, 0, BEAM_LIFE, 3.0, 3.0, 1, 0.0, {0, 255, 255, 255}, 0);
        TE_SendToAll();
    }

    for (int i = 0; i < NUM_VERTICAL_LINES; i++)
    {
        angle = (360.0 / NUM_VERTICAL_LINES) * i;
        float radians = DegToRad(angle);

        pos1[0] = g_Tornado.fOrigin[0] + (Cosine(radians) * TORNADO_RADIUS);
        pos1[1] = g_Tornado.fOrigin[1] + (Sine(radians) * TORNADO_RADIUS);
        pos1[2] = g_Tornado.fOrigin[2] + 10.0;

        pos3[0] = g_Tornado.fOrigin[0] + (Cosine(radians) * TORNADO_RADIUS);
        pos3[1] = g_Tornado.fOrigin[1] + (Sine(radians) * TORNADO_RADIUS);
        pos3[2] = g_Tornado.fOrigin[2] + TORNADO_HEIGHT;

        TE_SetupBeamPoints(pos1, pos3, g_iBeamSprite, 0, 0, 0, BEAM_LIFE, 3.0, 3.0, 1, 0.0, {255, 255, 0, 255}, 0);
        TE_SendToAll();
    }

    return Plugin_Continue;
}

public Action Timer_PlayRandomSounds(Handle timer)
{
    if (!IsValidEntity(g_Tornado.iAnchor))
    {
        g_Tornado.hImpactSoundTimer = null;
        return Plugin_Stop;
    }

    bool playThunder = GetRandomInt(0, 1) == 1;

    if (playThunder)
    {
        int idx = GetRandomInt(0, sizeof(g_sSoundThunder) - 1);
        EmitAmbientSound(g_sSoundThunder[idx], g_Tornado.fOrigin, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE, _, 0.8);
    }
    else
    {
        int idx = GetRandomInt(0, sizeof(g_sSoundImpact) - 1);
        EmitAmbientSound(g_sSoundImpact[idx], g_Tornado.fOrigin, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE, _, 0.7);
    }

    return Plugin_Continue;
}

public Action Timer_StopTornado(Handle timer)
{
    StopTornado();
    PrintToChatAll("\x04\x01 The tornado has dissipated.");
    return Plugin_Stop;
}

void StopTornado()
{
    SafeKillTimer(g_Tornado.hPhysicsTimer);
    SafeKillTimer(g_Tornado.hRotationTimer);
    SafeKillTimer(g_Tornado.hImpactSoundTimer);
    SafeKillTimer(g_Tornado.hDebugBeamTimer);

    SafeKillEntity(g_Tornado.iSoundEmitter, true);

    for (int i = 0; i < MAX_PARTICLES; i++)
    {
        SafeKillEntity(g_Tornado.iVisuals[i], true);
    }

    SafeKillEntity(g_Tornado.iAnchor);

    g_Tornado.Reset();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bFallDamageImmune[i])
        {
            ScheduleImmunityRemoval(i);
        }
    }
}

public Action Timer_TornadoPhysics(Handle timer)
{
    if (!IsValidEntity(g_Tornado.iAnchor))
    {
        g_Tornado.hPhysicsTimer = null;
        return Plugin_Stop;
    }

    float tornadoOrigin[3];
    GetEntPropVector(g_Tornado.iAnchor, Prop_Data, "m_vecOrigin", tornadoOrigin);

    if (g_Tornado.iPhase >= 1)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && IsPlayerAlive(i))
            {
                float playerPos[3];
                GetEntPropVector(i, Prop_Send, "m_vecOrigin", playerPos);

                float dist = GetVectorDistance(tornadoOrigin, playerPos);

                if (dist < TORNADO_RADIUS + 200.0)
                {
                    GrantPlayerImmunity(i);
                }
            }
        }
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_isGhost") == 1)
            continue;

            if (GetEntityMoveType(i) == MOVETYPE_NOCLIP)
            continue;

            ApplyTornadoForce(i, tornadoOrigin, true);
        }
    }

    int maxEnts = GetMaxEntities();
    for (int i = MaxClients + 1; i < maxEnts; i++)
    {
        if (!IsValidEntity(i)) continue;

        char cls[64];
        GetEntityClassname(i, cls, sizeof(cls));

        if (StrEqual(cls, "infected") ||
        StrEqual(cls, "prop_physics") ||
        StrEqual(cls, "prop_physics_override") ||
        StrEqual(cls, "prop_physics_multiplayer"))
        {
            ApplyTornadoForce(i, tornadoOrigin, false);
        }
    }

    return Plugin_Continue;
}

void ApplyTornadoForce(int entity, float tornadoPos[3], bool isPlayer)
{
    float entPos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entPos);

    float vecToCenter[3];
    SubtractVectors(tornadoPos, entPos, vecToCenter);

    float dist = GetVectorLength(vecToCenter);

    if (dist > TORNADO_RADIUS) return ;

    if (FloatAbs(entPos[2] - tornadoPos[2]) > TORNADO_HEIGHT) return ;

    float vecFinal[3];

    if (g_Tornado.iPhase == 1)
    {
        float vecSuction[3];
        NormalizeVector(vecToCenter, vecSuction);

        vecSuction[2] = 0.0;
        NormalizeVector(vecSuction, vecSuction);

        ScaleVector(vecSuction, FORCE_SUCTION_PHASE1);

        vecFinal[0] = vecSuction[0];
        vecFinal[1] = vecSuction[1];
        vecFinal[2] = 0.0;
    }
    else if (g_Tornado.iPhase == 2)
    {
        float vecUp[3] = {0.0, 0.0, 1.0};
        float vecTangent[3];

        float vecToEdge[3];
        vecToEdge[0] = tornadoPos[0] - entPos[0];
        vecToEdge[1] = tornadoPos[1] - entPos[1];
        vecToEdge[2] = 0.0;
        NormalizeVector(vecToEdge, vecToEdge);
        GetVectorCrossProduct(vecUp, vecToEdge, vecTangent);

        float singularityRadius = g_cvSingularityRadius.FloatValue;
        if (dist < singularityRadius)
        {
            float targetRadius = g_cvSingularityOrbitRadius.FloatValue;

            float pushOut[3];
            if (dist < targetRadius)
            {
                float pushStrength = (targetRadius - dist) * g_cvSingularityPushStrength.FloatValue;
                pushOut[0] = - vecToEdge[0] * pushStrength;
                pushOut[1] = - vecToEdge[1] * pushStrength;
                pushOut[2] = 0.0;
            }
            else
            {
                float pullStrength = (dist - targetRadius) * g_cvSingularityPullStrength.FloatValue;
                pushOut[0] = vecToEdge[0] * pullStrength;
                pushOut[1] = vecToEdge[1] * pullStrength;
                pushOut[2] = 0.0;
            }

            ScaleVector(vecTangent, FORCE_TANGENT * g_cvSingularityTangentMult.FloatValue);

            vecFinal[0] = pushOut[0] + vecTangent[0];
            vecFinal[1] = pushOut[1] + vecTangent[1];
            vecFinal[2] = FORCE_LIFT * g_cvSingularityLiftMult.FloatValue;
        }
        else
        {
            float vecSuction[3];
            NormalizeVector(vecToCenter, vecSuction);

            float distRatio = dist / TORNADO_RADIUS;
            float suctionMultiplier = 1.0 + (distRatio * 1.0);

            float vecLift[3] = {0.0, 0.0, 1.0};

            ScaleVector(vecSuction, FORCE_SUCTION * suctionMultiplier);
            ScaleVector(vecTangent, FORCE_TANGENT);
            ScaleVector(vecLift, FORCE_LIFT);

            AddVectors(vecSuction, vecTangent, vecFinal);
            AddVectors(vecFinal, vecLift, vecFinal);
        }
    }
    else
    {
        return ;
    }

    if (isPlayer)
    {
        if (g_Tornado.iPhase == 2)
        {
            GrantPlayerImmunity(entity);
        }

        ScaleVector(vecFinal, g_cvForcePlayerScale.FloatValue);
        SetEntPropVector(entity, Prop_Data, "m_vecBaseVelocity", vecFinal);
    }
    else
    {
        if (HasEntProp(entity, Prop_Data, "m_bAwake"))
        {
            AcceptEntityInput(entity, "EnableMotion");
            AcceptEntityInput(entity, "Wake");
        }

        ScaleVector(vecFinal, g_cvForcePropScale.FloatValue);

        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vecFinal);

        if (g_Tornado.iPhase == 2 && GetRandomInt(1, 5) == 1)
        {
            if (HasEntProp(entity, Prop_Data, "m_vecAngVelocity"))
            {
                float angVel[3];
                angVel[0] = GetRandomFloat(- 180.0, 180.0);
                angVel[1] = GetRandomFloat(- 180.0, 180.0);
                angVel[2] = GetRandomFloat(- 180.0, 180.0);
                SetEntPropVector(entity, Prop_Data, "m_vecAngVelocity", angVel);
            }
        }
    }
}

public Action OnTakeDamage(int victim, int & attacker, int & inflictor, float & damage, int & damagetype)
{
    if (!g_bFallDamageImmune[victim])
    return Plugin_Continue;

    if (damagetype & (1 << 5))
    {
        return Plugin_Handled;
    }

    if (IsValidEntity(inflictor))
    {
        char classname[64];
        GetEntityClassname(inflictor, classname, sizeof(classname));

        if (StrEqual(classname, "prop_physics") ||
        StrEqual(classname, "prop_physics_override") ||
        StrEqual(classname, "prop_physics_multiplayer"))
        {
            return Plugin_Handled;
        }
    }

    if (IsValidEntity(attacker))
    {
        char classname[64];
        GetEntityClassname(attacker, classname, sizeof(classname));

        if (StrEqual(classname, "prop_physics") ||
        StrEqual(classname, "prop_physics_override") ||
        StrEqual(classname, "prop_physics_multiplayer"))
        {
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

void GrantPlayerImmunity(int client)
{
    if (!IsValidClient(client)) return ;

    g_bFallDamageImmune[client] = true;

    if (g_hImmunityTimer[client] != null)
    {
        KillTimer(g_hImmunityTimer[client]);
        g_hImmunityTimer[client] = null;
    }
}

void ScheduleImmunityRemoval(int client)
{
    if (!IsValidClient(client)) return ;

    if (g_hImmunityTimer[client] != null)
    {
        KillTimer(g_hImmunityTimer[client]);
    }

    g_hImmunityTimer[client] = CreateTimer(IMMUNITY_DURATION, Timer_RemoveImmunity, GetClientUserId(client));
}

public Action Timer_RemoveImmunity(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client))
    {
        g_bFallDamageImmune[client] = false;
        g_hImmunityTimer[client] = null;
    }
    return Plugin_Stop;
}

void ClearPlayerImmunity(int client)
{
    g_bFallDamageImmune[client] = false;
    if (g_hImmunityTimer[client] != null)
    {
        KillTimer(g_hImmunityTimer[client]);
        g_hImmunityTimer[client] = null;
    }
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

void SafeKillTimer(Handle & timer)
{
    if (timer != null)
    {
        KillTimer(timer);
        timer = null;
    }
}

void SafeKillEntity(int & entity, bool stopFirst = false)
{
    if (!IsValidEntity(entity))
    return ;

    if (stopFirst)
    AcceptEntityInput(entity, "Stop");

    AcceptEntityInput(entity, "Kill");
    entity = - 1;
}

public bool TraceFilter_NoPlayers(int entity, int contentsMask)
{
    return entity > MaxClients;
}

stock void PrecacheParticle(const char[] particleName)
{
    int particle = CreateEntityByName("info_particle_system");
    if (IsValidEntity(particle))
    {
        DispatchKeyValue(particle, "effect_name", particleName);
        DispatchSpawn(particle);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Kill");
    }
}