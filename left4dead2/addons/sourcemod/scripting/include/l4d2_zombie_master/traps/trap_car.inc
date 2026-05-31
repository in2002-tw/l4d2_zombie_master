#if defined _zm_trap_car_included
 #endinput
#endif
#define _zm_trap_car_included

// Spawn structure adapted from Mart's "[L4D1 & L4D2] Replace Cars Into Car Alarms" (which in turn
// derives from DieTeetasse's "[L4D1&2] Spawn Alarmcars"). The companion layout, env_sprite /
// beam_spotlight / logic_timer keyvalues, and the MoveVectorvPos3D / MatrixMulti offset math are
// reproduced verbatim from that reference.

#define ZM_CAR_COMPANION_MAX 16

#define ALARMCAR_MODEL            "models/props_vehicles/cara_95sedan.mdl"
#define ALARMCAR_GLASS_ALARM_ON   "models/props_vehicles/cara_95sedan_glass_alarm.mdl"
#define ALARMCAR_GLASS_ALARM_OFF  "models/props_vehicles/cara_95sedan_glass.mdl"
#define ALARMCAR_GLOW_SPRITE      "sprites/glow.vmt"

#define ALARMCAR_SOUND            "vehicles/car_alarm/car_alarm.wav"
#define ALARMCAR_SOUND_CHIRP      "vehicles/car_alarm/car_alarm_chirp2.wav"

#define ALARMCAR_COLOR_YELLOW     "224 162 44"
#define ALARMCAR_COLOR_RED        "255 13 19"
#define ALARMCAR_COLOR_WHITE      "252 243 226"

// Companion offsets relative to the car origin (verbatim from the reference plugin).
#define ALARMCAR_DISTANCE_FRONT     101.0
#define ALARMCAR_DISTANCE_SIDETURN  34.0
#define ALARMCAR_DISTANCE_UPFRONT   29.0
#define ALARMCAR_DISTANCE_BACK      103.0
#define ALARMCAR_DISTANCE_SIDE      27.0
#define ALARMCAR_DISTANCE_UPBACK    31.0

enum struct car_trap_data
{
    int companions[ZM_CAR_COMPANION_MAX]; // entity refs of glass/sound/light/timer helpers
    int companionCount;

    void Clear()
    {
        this.companionCount = 0;
        for (int i = 0; i < ZM_CAR_COMPANION_MAX; i++)
            this.companions[i] = INVALID_ENT_REFERENCE;
    }

    // Record a companion entity by reference so teardown can kill it. Silently drops overflow.
    void Track(int entity)
    {
        if (this.companionCount >= ZM_CAR_COMPANION_MAX) return;
        this.companions[this.companionCount++] = EntIndexToEntRef(entity);
    }
}
car_trap_data g_CarTrapData[ZM_TRAP_MAX];

// Precache the alarm-car models and sounds. Called from the plugin's OnMapStart.
void TrapCar_Precache()
{
    PrecacheModel(ALARMCAR_MODEL, true);
    PrecacheModel(ALARMCAR_GLASS_ALARM_ON, true);
    PrecacheModel(ALARMCAR_GLASS_ALARM_OFF, true);
    PrecacheModel(ALARMCAR_GLOW_SPRITE, true);

    PrecacheSound(ALARMCAR_SOUND, true);
    PrecacheSound(ALARMCAR_SOUND_CHIRP, true);
}

bool TrapCar_CanArm(int entity)
{
    if (!IsValidEntity(entity)) return false;
    char cls[32];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (strcmp(cls, "prop_physics") != 0 && strcmp(cls, "prop_dynamic") != 0 && strcmp(cls, "prop_physics_override") != 0) return false;
    char model[128];
    GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
    // Match L4D2 vehicle model paths only (NOT a bare "car" substring).
    if (StrContains(model, "props_vehicles/", false) < 0 && StrContains(model, "/cara_", false) < 0) return false;
    for (int i = 0; i < ZM_TRAP_MAX; i++)
        if (g_Traps[i].state != ZM_TRAP_STATE_FREE && EntRefToEntIndex(g_Traps[i].entRef) == entity) return false;
    return true;
}

// Replace the static car prop with a genuine prop_car_alarm at the same pose/color.
bool TrapCar_Convert(int slot, int car)
{
    float vPos[3], vAng[3];
    GetEntPropVector(car, Prop_Data, "m_vecAbsOrigin", vPos);
    GetEntPropVector(car, Prop_Data, "m_angAbsRotation", vAng);

    int r, g, b, a;
    GetEntityRenderColor(car, r, g, b, a);
    char rendercolor[12];
    if (r == 255 && g == 255 && b == 255) // uncolored prop: use the default alarm-car body color
        strcopy(rendercolor, sizeof(rendercolor), "138 37 9");
    else
        FormatEx(rendercolor, sizeof(rendercolor), "%i %i %i", r, g, b);

    AcceptEntityInput(car, "Kill");

    int alarm = TrapCar_SpawnAlarmCar(slot, vPos, vAng, rendercolor);
    if (alarm <= 0) return false;

    g_Traps[slot].entRef = EntIndexToEntRef(alarm);
    // Once-flag hook: the engine fires OnCarAlarmStart on this specific car when its alarm begins.
    HookSingleEntityOutput(alarm, "OnCarAlarmStart", TrapCar_OnAlarmStart, true);
    return true;
}

// Spawn the prop_car_alarm and its companion entities. Returns the car entity index, or -1.
int TrapCar_SpawnAlarmCar(int slot, float vPos[3], float vAng[3], const char[] rendercolor)
{
    int car = CreateEntityByName("prop_car_alarm");
    if (car <= 0) return -1;

    // Unique targetnames so the wired outputs/parents resolve to this car's own companions.
    char carName[64], glassOnName[64], glassOffName[64], timerName[64];
    char alarmSoundName[64], chirpSoundName[64], lightsName[64], headlightsName[64];
    FormatEx(carName,         sizeof(carName),         "zm_tcar_%i", car);
    FormatEx(glassOnName,     sizeof(glassOnName),     "zm_tcar_glasson_%i", car);
    FormatEx(glassOffName,    sizeof(glassOffName),    "zm_tcar_glassoff_%i", car);
    FormatEx(timerName,       sizeof(timerName),       "zm_tcar_timer_%i", car);
    FormatEx(alarmSoundName,  sizeof(alarmSoundName),  "zm_tcar_alarm_%i", car);
    FormatEx(chirpSoundName,  sizeof(chirpSoundName),  "zm_tcar_chirp_%i", car);
    FormatEx(lightsName,      sizeof(lightsName),      "zm_tcar_lights_%i", car);
    FormatEx(headlightsName,  sizeof(headlightsName),  "zm_tcar_headlights_%i", car);

    DispatchKeyValue(car, "targetname", carName);
    DispatchKeyValue(car, "model", ALARMCAR_MODEL);
    DispatchKeyValue(car, "rendercolor", rendercolor);

    char io[128];
    // Chirp-when-shot-near tell.
    Format(io, sizeof(io), "%s,PlaySound,,0.2,-1", chirpSoundName);
    DispatchKeyValue(car, "OnCarAlarmChirpStart", io);
    Format(io, sizeof(io), "%s,ShowSprite,,0.2,-1", lightsName);
    DispatchKeyValue(car, "OnCarAlarmChirpStart", io);
    Format(io, sizeof(io), "%s,HideSprite,,0.7,-1", lightsName);
    DispatchKeyValue(car, "OnCarAlarmChirpEnd", io);

    // Full alarm start: run the flash timer, play the alarm, swap to the non-blinking glass.
    Format(io, sizeof(io), "%s,Enable,,0,-1", timerName);
    DispatchKeyValue(car, "OnCarAlarmStart", io);
    Format(io, sizeof(io), "%s,PlaySound,,0,-1", alarmSoundName);
    DispatchKeyValue(car, "OnCarAlarmStart", io);
    Format(io, sizeof(io), "%s,Enable,,0,-1", glassOffName);
    DispatchKeyValue(car, "OnCarAlarmStart", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", glassOnName);
    DispatchKeyValue(car, "OnCarAlarmStart", io);

    // Alarm end / tank hit: stop everything so the sound and lights do NOT loop forever.
    Format(io, sizeof(io), "%s,Kill,,0,-1", timerName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", alarmSoundName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", chirpSoundName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", lightsName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", headlightsName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);
    Format(io, sizeof(io), "%s,Kill,,0,-1", glassOnName);
    DispatchKeyValue(car, "OnCarAlarmEnd", io);
    DispatchKeyValue(car, "OnHitByTank", io);

    DispatchKeyValueVector(car, "origin", vPos);
    DispatchKeyValueVector(car, "angles", vAng);
    DispatchSpawn(car);

    // Companions: each parented to the car and tracked for teardown.
    TrapCar_CreateGlass(slot, glassOnName, false, vPos, vAng, carName); // blinking resting tell
    TrapCar_CreateGlass(slot, glassOffName, true, vPos, vAng, carName);  // plain glass once alarming
    TrapCar_CreateSound(slot, alarmSoundName, "16", "Car.Alarm", vPos, carName);
    TrapCar_CreateSound(slot, chirpSoundName, "48", "Car.Alarm.Chirp2", vPos, carName);
    TrapCar_CreateLights(slot, lightsName, vPos, vAng, carName);
    TrapCar_CreateHeadlights(slot, headlightsName, vPos, vAng, carName);
    TrapCar_CreateLogicTimer(slot, timerName, lightsName, headlightsName, vPos, carName);

    return car;
}

static void TrapCar_CreateGlass(int slot, const char[] targetName, bool startDisabled, float vPos[3], float vAng[3], const char[] carName)
{
    int entity = CreateEntityByName("prop_car_glass");
    if (entity <= 0) return;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "model", startDisabled ? ALARMCAR_GLASS_ALARM_OFF : ALARMCAR_GLASS_ALARM_ON);
    DispatchKeyValue(entity, "StartDisabled", startDisabled ? "1" : "0");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
    g_CarTrapData[slot].Track(entity);
}

static void TrapCar_CreateSound(int slot, const char[] targetName, const char[] spawnFlags, const char[] messageName, float vPos[3], const char[] carName)
{
    int entity = CreateEntityByName("ambient_generic");
    if (entity <= 0) return;

    float newPos[3];
    newPos = vPos;
    newPos[2] += 80.0;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "spawnflags", spawnFlags);
    DispatchKeyValue(entity, "message", messageName);
    DispatchKeyValue(entity, "SourceEntityName", carName);
    DispatchKeyValue(entity, "radius", "4000");
    DispatchKeyValueVector(entity, "origin", newPos);
    DispatchSpawn(entity);
    ActivateEntity(entity); // ambient_generic needs an explicit activate

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
    g_CarTrapData[slot].Track(entity);
}

static void TrapCar_CreateLights(int slot, const char[] lightsName, float vPos[3], float vAng[3], const char[] carName)
{
    float distance[6] = {ALARMCAR_DISTANCE_FRONT, ALARMCAR_DISTANCE_SIDETURN, ALARMCAR_DISTANCE_UPFRONT, ALARMCAR_DISTANCE_BACK, ALARMCAR_DISTANCE_SIDE, ALARMCAR_DISTANCE_UPBACK};
    float newPos[3];
    float lightDistance[3];

    newPos = vPos;
    lightDistance[0] = distance[0];
    lightDistance[1] = distance[1]*-1.0;
    lightDistance[2] = distance[2];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // front left
    TrapCar_CreateLight(slot, lightsName, ALARMCAR_COLOR_YELLOW, newPos, carName);

    newPos = vPos;
    lightDistance[1] = distance[1];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // front right
    TrapCar_CreateLight(slot, lightsName, ALARMCAR_COLOR_YELLOW, newPos, carName);

    newPos = vPos;
    lightDistance[0] = distance[3]*-1.0;
    lightDistance[1] = distance[4]*-1.0;
    lightDistance[2] = distance[5];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // back left
    TrapCar_CreateLight(slot, lightsName, ALARMCAR_COLOR_RED, newPos, carName);

    newPos = vPos;
    lightDistance[1] = distance[4];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // back right
    TrapCar_CreateLight(slot, lightsName, ALARMCAR_COLOR_RED, newPos, carName);
}

static void TrapCar_CreateLight(int slot, const char[] targetName, const char[] renderColor, float vPos[3], const char[] carName)
{
    int entity = CreateEntityByName("env_sprite");
    if (entity <= 0) return;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "rendercolor", renderColor);
    DispatchKeyValue(entity, "model", ALARMCAR_GLOW_SPRITE);
    DispatchKeyValue(entity, "scale", "0.5");
    DispatchKeyValue(entity, "rendermode", "9");
    DispatchKeyValue(entity, "renderamt", "255");
    DispatchKeyValue(entity, "HDRColorScale", "0.7");
    DispatchKeyValue(entity, "GlowProxySize", "5");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
    g_CarTrapData[slot].Track(entity);
}

static void TrapCar_CreateHeadlights(int slot, const char[] headlightsName, float vPos[3], float vAng[3], const char[] carName)
{
    float distance[3] = {ALARMCAR_DISTANCE_FRONT, ALARMCAR_DISTANCE_SIDE, ALARMCAR_DISTANCE_UPFRONT};
    float newPos[3];
    float headlightDistance[3];

    newPos = vPos;
    headlightDistance[0] = distance[0];
    headlightDistance[1] = distance[1]*-1.0;
    headlightDistance[2] = distance[2];
    MoveVectorvPos3D(newPos, vAng, headlightDistance); // front left
    TrapCar_CreateHeadlight(slot, headlightsName, newPos, vAng, carName);

    newPos = vPos;
    headlightDistance[1] = distance[1];
    MoveVectorvPos3D(newPos, vAng, headlightDistance); // front right
    TrapCar_CreateHeadlight(slot, headlightsName, newPos, vAng, carName);
}

static void TrapCar_CreateHeadlight(int slot, const char[] targetName, float vPos[3], float vAng[3], const char[] carName)
{
    int entity = CreateEntityByName("beam_spotlight");
    if (entity <= 0) return;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "rendercolor", ALARMCAR_COLOR_WHITE);
    DispatchKeyValue(entity, "spotlightwidth", "32");
    DispatchKeyValue(entity, "spotlightlength", "256");
    DispatchKeyValue(entity, "spawnflags", "2");
    DispatchKeyValue(entity, "rendermode", "5");
    DispatchKeyValue(entity, "renderamt", "150");
    DispatchKeyValue(entity, "maxspeed", "100");
    DispatchKeyValue(entity, "HDRColorScale", "0.5");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
    g_CarTrapData[slot].Track(entity);
}

static void TrapCar_CreateLogicTimer(int slot, const char[] targetName, const char[] lightsName, const char[] headlightsName, float vPos[3], const char[] carName)
{
    int entity = CreateEntityByName("logic_timer");
    if (entity <= 0) return;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "StartDisabled", "1");
    DispatchKeyValue(entity, "RefireTime", "0.75");

    char io[128];
    Format(io, sizeof(io), "%s,ShowSprite,,0,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    Format(io, sizeof(io), "%s,ShowSprite,,0,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    Format(io, sizeof(io), "%s,LightOn,,0,-1", headlightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    Format(io, sizeof(io), "%s,HideSprite,,0.5,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    Format(io, sizeof(io), "%s,HideSprite,,0.5,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    Format(io, sizeof(io), "%s,LightOff,,0.5,-1", headlightsName);
    DispatchKeyValue(entity, "OnTimer", io);
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
    g_CarTrapData[slot].Track(entity);
}

// Rotate an offset by the car's angles and add it to vPos (verbatim from the reference).
static void MoveVectorvPos3D(float vPos[3], float constvAng[3], float constDistance[3])
{
    float vAng[3], dirFw[3], dirRi[3], dirUp[3], distance[3];
    distance = constDistance;

    vAng[0] = DegToRad(constvAng[0]);
    vAng[1] = DegToRad(constvAng[1]);
    vAng[2] = DegToRad(constvAng[2]);

    // roll (rotation over x)
    dirFw[0] = 1.0;
    dirFw[1] = 0.0;
    dirFw[2] = 0.0;
    dirRi[0] = 0.0;
    dirRi[1] = Cosine(vAng[2]);
    dirRi[2] = Sine(vAng[2])*-1;
    dirUp[0] = 0.0;
    dirUp[1] = Sine(vAng[2]);
    dirUp[2] = Cosine(vAng[2]);
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // pitch (rotation over y)
    dirFw[0] = Cosine(vAng[0]);
    dirFw[1] = 0.0;
    dirFw[2] = Sine(vAng[0]);
    dirRi[0] = 0.0;
    dirRi[1] = 1.0;
    dirRi[2] = 0.0;
    dirUp[0] = Sine(vAng[0])*-1;
    dirUp[1] = 0.0;
    dirUp[2] = Cosine(vAng[0]);
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // yaw (rotation over z)
    dirFw[0] = Cosine(vAng[1]);
    dirFw[1] = Sine(vAng[1])*-1;
    dirFw[2] = 0.0;
    dirRi[0] = Sine(vAng[1]);
    dirRi[1] = Cosine(vAng[1]);
    dirRi[2] = 0.0;
    dirUp[0] = 0.0;
    dirUp[1] = 0.0;
    dirUp[2] = 1.0;
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // addition
    for (int i = 0; i < 3; i++) vPos[i] += distance[i];
}

static void MatrixMulti(float matA[3], float matB[3], float matC[3], float vec[3])
{
    float res[3];
    for (int i = 0; i < 3; i++) res[0] += matA[i]*vec[i];
    for (int i = 0; i < 3; i++) res[1] += matB[i]*vec[i];
    for (int i = 0; i < 3; i++) res[2] += matC[i]*vec[i];
    vec = res;
}

// Per-car OnCarAlarmStart output: find the armed car slot for this caller and fire its trigger.
public void TrapCar_OnAlarmStart(const char[] output, int caller, int activator, float delay)
{
    for (int i = 0; i < ZM_TRAP_MAX; i++)
    {
        if (g_Traps[i].state != ZM_TRAP_STATE_ARMED) continue;
        if (g_Traps[i].type != ZM_TRAP_TYPE_CAR) continue;
        if (EntRefToEntIndex(g_Traps[i].entRef) != caller) continue;
        Trap_OnTriggered(i, IsValidClient(activator) ? activator : 0);
        return;
    }
}

bool FX_Alarm_OnArm(int slot)
{
    int car = EntRefToEntIndex(g_Traps[slot].entRef);
    if (car <= 0) return false;
    return TrapCar_Convert(slot, car);
}

void FX_Alarm_Fire(int slot, int triggerClient, const float pos[3])
{
    #pragma unused slot
    #pragma unused triggerClient
    #pragma unused pos
}

void FX_Alarm_OnCleanup(int slot)
{
    #pragma unused slot
}

void TrapCar_Teardown(int slot)
{
    bool spent = (g_Traps[slot].state == ZM_TRAP_STATE_TRIGGERED);

    if (!spent)
    {
        int car = EntRefToEntIndex(g_Traps[slot].entRef);
        if (car > 0 && IsValidEntity(car))
            UnhookSingleEntityOutput(car, "OnCarAlarmStart", TrapCar_OnAlarmStart);

        for (int i = 0; i < g_CarTrapData[slot].companionCount; i++)
        {
            int c = EntRefToEntIndex(g_CarTrapData[slot].companions[i]);
            if (c > 0 && IsValidEntity(c)) AcceptEntityInput(c, "Kill");
        }

        if (car > 0 && IsValidEntity(car)) AcceptEntityInput(car, "Kill");
    }

    g_CarTrapData[slot].Clear();
}

void TrapCar_BeginArm()
{
    if (!IsValidClientZM()) return;
    if (!Trap_CanAfford(ZM_TRAP_TYPE_CAR, true)) return;
    float hitPos[3];
    int ent = Trap_GetAimedEntity(hitPos);
    if (ent <= 0 || !TrapCar_CanArm(ent)) { update_hint("%T", "Trap invalid car", zm_client); return; }
    int slot = Trap_Register(ZM_TRAP_TYPE_CAR, ZM_TRAP_FX_ALARM, ent);
    if (slot < 0) { update_hint("%T", "Trap max reached", zm_client); return; }
    g_CarTrapData[slot].Clear();
    if (!Trap_EffectOnArm(ZM_TRAP_FX_ALARM, slot))
    {
        Trap_AbortArm(slot);
        update_hint("%T", "Trap invalid car", zm_client);
        return;
    }
    Trap_ConfirmArm();
    update_hint("%T", "Trap armed car", zm_client);
    RequestFrame(create_traps_menu);
}
