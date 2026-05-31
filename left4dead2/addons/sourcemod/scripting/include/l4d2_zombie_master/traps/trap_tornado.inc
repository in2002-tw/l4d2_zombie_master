#if defined _zm_trap_tornado_included
 #endinput
#endif
#define _zm_trap_tornado_included

#define TORNADO_MAX_PARTICLES 13
#define TORNADO_PARTICLE_CORE "smoke_burning_engine_01"
#define TORNADO_SOUND_WIND    "ambient/wind/windgust_strong.wav"

#define TORNADO_K_RADIAL    2.0
#define TORNADO_TARGET_R    220.0
#define TORNADO_K_TANGENT   950.0
#define TORNADO_HOVER_H     450.0
#define TORNADO_K_VERT      2.0

#define TORNADO_BOB_AMP     1000.0

#define TORNADO_BOB_FREQ    3.0

#define TORNADO_MAX_HORIZ   1300.0
#define TORNADO_MAX_LIFT    1100.0
#define TORNADO_FLING_OUT   700.0
#define TORNADO_FLING_UP    300.0
#define TORNADO_PLAYER_SCALE 1.0
#define TORNADO_PROP_SCALE   1.0

enum struct tornado_data
{
    float origin[3];
    int   particles[TORNADO_MAX_PARTICLES];
    int   particleCount;
    int   soundRef;
    void Clear()
    {
        this.origin[0] = 0.0; this.origin[1] = 0.0; this.origin[2] = 0.0;
        this.particleCount = 0;
        for (int i = 0; i < TORNADO_MAX_PARTICLES; i++) this.particles[i] = INVALID_ENT_REFERENCE;
        this.soundRef = INVALID_ENT_REFERENCE;
    }
}
tornado_data g_TornadoData[ZM_TRAP_MAX];

// Hard-clamp an applied velocity so a tornado can never approach sv_maxvelocity.
// extreme velocities spam "velocity too high" and blow up vphysics on props (segfault).
stock void TrapTornado_ClampVel(float v[3])
{
    float h = SquareRoot(v[0]*v[0] + v[1]*v[1]);
    if (h > TORNADO_MAX_HORIZ) { float s = TORNADO_MAX_HORIZ / h; v[0] *= s; v[1] *= s; }
    if (v[2] > TORNADO_MAX_LIFT) v[2] = TORNADO_MAX_LIFT;
    else if (v[2] < -TORNADO_MAX_LIFT) v[2] = -TORNADO_MAX_LIFT;
}

stock void TrapTornado_ApplyForce(int slot, int entity, bool isPlayer)
{
    float entPos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entPos); // m_vecOrigin via Prop_Send works for players and props

    float c[3]; c = g_TornadoData[slot].origin;
    if (FloatAbs(entPos[2] - c[2]) > g_fTornadoHeight) return;

    float toCenter[3]; toCenter[0] = c[0]-entPos[0]; toCenter[1] = c[1]-entPos[1]; toCenter[2] = 0.0;
    float dist = GetVectorLength(toCenter);
    if (dist > g_fTornadoRadius) return;

    float radialOut[3]; radialOut[0] = -toCenter[0]; radialOut[1] = -toCenter[1]; radialOut[2] = 0.0;
    if (dist > 0.1) NormalizeVector(radialOut, radialOut);

    // Orbital velocity: inward pull toward the band (radial) + swirl (tangential) + gentle lift.
    float radialError = dist - TORNADO_TARGET_R;
    float vel[3];
    vel[0] = -radialOut[0] * radialError * TORNADO_K_RADIAL;
    vel[1] = -radialOut[1] * radialError * TORNADO_K_RADIAL;

    float up[3]; up[0]=0.0; up[1]=0.0; up[2]=1.0;
    float tangent[3]; GetVectorCrossProduct(up, radialOut, tangent);
    vel[0] += tangent[0] * TORNADO_K_TANGENT;
    vel[1] += tangent[1] * TORNADO_K_TANGENT;
    // Vertical = spring toward hover height (launches them off the floor, keeps them airborne) PLUS a
    // bob. The bob's down-swing gives real downward velocity, which is what fires the falling-scream.
    // Per-entity phase (+entity) so survivors bob out of sync rather than in lockstep.
    vel[2] = (c[2] + TORNADO_HOVER_H - entPos[2]) * TORNADO_K_VERT
           + TORNADO_BOB_AMP * Sine(GetGameTime() * TORNADO_BOB_FREQ + float(entity));

    if (isPlayer)
    {
        ScaleVector(vel, TORNADO_PLAYER_SCALE);
        TrapTornado_ClampVel(vel);
        int flags = GetEntityFlags(entity);
        if (flags & FL_ONGROUND) SetEntityFlags(entity, flags & ~FL_ONGROUND);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vel);
    }
    else
    {
        if (HasEntProp(entity, Prop_Data, "m_bAwake")) { AcceptEntityInput(entity, "EnableMotion"); AcceptEntityInput(entity, "Wake"); }
        ScaleVector(vel, TORNADO_PROP_SCALE);
        TrapTornado_ClampVel(vel);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vel);
        // occasional debris tumble
        if (GetRandomInt(1, 5) == 1 && HasEntProp(entity, Prop_Data, "m_vecAngVelocity"))
        {
            float av[3]; av[0]=GetRandomFloat(-180.0,180.0); av[1]=GetRandomFloat(-180.0,180.0); av[2]=GetRandomFloat(-180.0,180.0);
            SetEntPropVector(entity, Prop_Data, "m_vecAngVelocity", av);
        }
    }
}

void TrapTornado_BeginArm()
{
    if (!IsValidClientZM()) return;
    if (!Trap_CanAfford(ZM_TRAP_TYPE_TORNADO, true)) return;

    float pos[3];
    if (Trap_GetAimedEntity(pos) < 0) { update_hint("%T", "Trap invalid tornado", zm_client); return; }
    pos[2] += 10.0;

    int anchor = CreateEntityByName("info_target");
    if (!IsValidEntity(anchor)) { update_hint("%T", "Trap invalid tornado", zm_client); return; }
    DispatchSpawn(anchor);
    TeleportEntity(anchor, pos, NULL_VECTOR, NULL_VECTOR);
    SetEntityMoveType(anchor, MOVETYPE_NONE);

    int slot = Trap_Register(ZM_TRAP_TYPE_TORNADO, ZM_TRAP_FX_TORNADO, anchor);
    if (slot < 0) { RemoveEntity(anchor); update_hint("%T", "Trap max reached", zm_client); return; }

    g_TornadoData[slot].Clear();
    g_TornadoData[slot].origin = pos;
    if (!Trap_EffectOnArm(ZM_TRAP_FX_TORNADO, slot))
    {
        Trap_AbortArm(slot);
        if (IsValidEntity(anchor)) RemoveEntity(anchor);
        update_hint("%T", "Trap invalid tornado", zm_client);
        return;
    }
    Trap_ConfirmArm();
    update_hint("%T", "Trap placed tornado", zm_client);
    RequestFrame(create_traps_menu);
}

bool FX_Tornado_OnArm(int slot)
{
    int anchor = EntRefToEntIndex(g_Traps[slot].entRef);
    if (anchor <= 0) return false;
    GetEntPropVector(anchor, Prop_Data, "m_vecOrigin", g_TornadoData[slot].origin);
    TrapTornado_SpawnVisuals(slot);
    return true;
}

void TrapTornado_Update()
{
    float now = GetGameTime();
    int expired[ZM_TRAP_MAX]; int nExpired = 0;

    for (int slot = 0; slot < ZM_TRAP_MAX; slot++)
    {
        if (g_Traps[slot].state != ZM_TRAP_STATE_ARMED) continue;
        if (g_Traps[slot].type != ZM_TRAP_TYPE_TORNADO) continue;

        if (now - g_Traps[slot].armedAt >= g_fTornadoDuration) { expired[nExpired++] = slot; continue; }

        // players
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
            if (GetEntityMoveType(i) == MOVETYPE_NOCLIP) continue;
            if (GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_isGhost") == 1) continue;
            TrapTornado_ApplyForce(slot, i, true);
            if (GetClientTeam(i) == TEAM_SURVIVOR) TrapTornado_RefreshImmunity(i);
        }
        // infected + physics props
        int maxEnts = GetMaxEntities();
        for (int e = MaxClients + 1; e < maxEnts; e++)
        {
            if (!IsValidEntity(e)) continue;
            char cls[64]; GetEntityClassname(e, cls, sizeof(cls));
            if (StrEqual(cls, "infected") || StrEqual(cls, "prop_physics") || StrEqual(cls, "prop_physics_override") || StrEqual(cls, "prop_physics_multiplayer"))
                TrapTornado_ApplyForce(slot, e, false);
        }
    }

    for (int k = 0; k < nExpired; k++) Trap_OnTriggered(expired[k], 0); // end-fling + cleanup, after iteration
}

void TrapTornado_RefreshImmunity(int client)
{
    g_fTornadoImmuneUntil[client] = GetGameTime() + g_fTornadoGrace;
}

// SDKHook_OnTakeDamage handler installed on every client at spawn (OnClientPutInServer + retro-loop).
// Blocks fall damage and prop-impact damage while the client is within the grace window.
// Probably needs optimization, SDKHook and Unhook on activate/deactivate
public Action TrapTornado_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    if (victim < 1 || victim > MaxClients) return Plugin_Continue;
    if (GetGameTime() >= g_fTornadoImmuneUntil[victim]) return Plugin_Continue;
    if (damagetype & DMG_FALL) return Plugin_Handled;
    // block prop-impact damage while caught
    if (IsValidEntity(inflictor))
    {
        char cls[64]; GetEntityClassname(inflictor, cls, sizeof(cls));
        if (StrContains(cls, "prop_physics") == 0) return Plugin_Handled;
    }
    return Plugin_Continue;
}

// Precache the tornado particle effect (spawn-and-kill trick) and wind sound.
void TrapTornado_Precache()
{
    int p = CreateEntityByName("info_particle_system");
    if (IsValidEntity(p)) { DispatchKeyValue(p, "effect_name", TORNADO_PARTICLE_CORE); DispatchSpawn(p); ActivateEntity(p); AcceptEntityInput(p, "Kill"); }
    PrecacheSound(TORNADO_SOUND_WIND, true);
}

// Spawn the rising spiral of smoke particles and the looping wind sound at the tornado origin.
void TrapTornado_SpawnVisuals(int slot)
{
    float origin[3]; origin = g_TornadoData[slot].origin;

    // Rising spiral of smoke columns.
    for (int i = 0; i < TORNADO_MAX_PARTICLES; i++)
    {
        float spiralRotation = (360.0 / TORNADO_MAX_PARTICLES) * i + (i * 45.0);
        float radians = DegToRad(spiralRotation);

        float height = i * 60.0;

        float bottomRadius = 50.0;
        float topRadius    = 150.0;
        float heightRatio  = float(i) / float(TORNADO_MAX_PARTICLES - 1);
        float radius = bottomRadius + ((topRadius - bottomRadius) * heightRatio);

        float offset[3];
        offset[0] = origin[0] + (Cosine(radians) * radius);
        offset[1] = origin[1] + (Sine(radians)   * radius);
        offset[2] = origin[2] + height;

        int particle = CreateEntityByName("info_particle_system");
        if (particle == -1) continue;

        DispatchKeyValue(particle, "effect_name", TORNADO_PARTICLE_CORE);
        DispatchKeyValue(particle, "start_active", "1");

        if (!DispatchSpawn(particle)) { AcceptEntityInput(particle, "Kill"); continue; }

        TeleportEntity(particle, offset, NULL_VECTOR, NULL_VECTOR);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");

        g_TornadoData[slot].particles[g_TornadoData[slot].particleCount] = EntIndexToEntRef(particle);
        g_TornadoData[slot].particleCount++;
    }

    // Looping wind ambient_generic.
    int snd = CreateEntityByName("ambient_generic");
    if (snd == -1) return;

    DispatchKeyValue(snd, "message", TORNADO_SOUND_WIND);
    DispatchKeyValue(snd, "health",      "100");
    DispatchKeyValue(snd, "pitch",       "100");
    DispatchKeyValue(snd, "radius",      "2500");
    DispatchKeyValue(snd, "spawnflags",  "1");

    DispatchSpawn(snd);
    ActivateEntity(snd);
    TeleportEntity(snd, origin, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(snd, "PlaySound");

    g_TornadoData[slot].soundRef = EntIndexToEntRef(snd);
}

void FX_Tornado_Fire(int slot, int triggerClient, const float pos[3])
{
    #pragma unused slot
    #pragma unused triggerClient
    #pragma unused pos
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == TEAM_SURVIVOR)
            TrapTornado_RefreshImmunity(i);
}

void FX_Tornado_OnCleanup(int slot)
{
    int snd = g_TornadoData[slot].soundRef;
    if (IsValidEntRef(snd)) { AcceptEntityInput(EntRefToEntIndex(snd), "StopSound"); RemoveEntity(snd); }
    for (int i = 0; i < g_TornadoData[slot].particleCount; i++)
    {
        int p = g_TornadoData[slot].particles[i];
        if (IsValidEntRef(p)) { AcceptEntityInput(EntRefToEntIndex(p), "Stop"); RemoveEntity(p); }
    }
    int anchor = EntRefToEntIndex(g_Traps[slot].entRef);
    if (anchor > 0 && IsValidEntity(anchor)) RemoveEntity(anchor);
    g_TornadoData[slot].Clear();
}
