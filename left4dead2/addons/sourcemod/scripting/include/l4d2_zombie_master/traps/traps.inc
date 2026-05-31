#if defined _zm_traps_included
 #endinput
#endif
#define _zm_traps_included

// Per-trap generic record. Per-type state lives in side arrays owned by sources/effects.
enum struct zm_trap
{
    int type;        // ZM_TRAP_TYPE_*
    int effect;      // ZM_TRAP_FX_*
    int entRef;      // converted/owned entity (door or car)
    int glowSurvRef; // survivor-visible glow ornament
    int glowZMRef;   // ZM-only glow ornament
    int ownerUserId; // informational
    int state;       // ZM_TRAP_STATE_*
    int costPaid;
    float armedAt;

    void Clear()
    {
        this.type = -1;
        this.effect = -1;
        this.entRef = INVALID_ENT_REFERENCE;
        this.glowSurvRef = INVALID_ENT_REFERENCE;
        this.glowZMRef = INVALID_ENT_REFERENCE;
        this.ownerUserId = -1;
        this.state = ZM_TRAP_STATE_FREE;
        this.costPaid = 0;
        this.armedAt = 0.0;
    }
}

zm_trap g_Traps[ZM_TRAP_MAX];

// Find a free slot, or -1 if full.
stock int Trap_FindFreeSlot()
{
    for (int i = 0; i < ZM_TRAP_MAX; i++)
        if (g_Traps[i].state == ZM_TRAP_STATE_FREE) return i;
    return -1;
}

// Count active traps of a given source type (-1 = all types).
stock int Trap_CountActive(int type = -1)
{
    int n = 0;
    for (int i = 0; i < ZM_TRAP_MAX; i++)
    {
        if (g_Traps[i].state == ZM_TRAP_STATE_FREE) continue;
        if (type < 0 || g_Traps[i].type == type) n++;
    }
    return n;
}

stock void Traps_Init()
{
    for (int i = 0; i < ZM_TRAP_MAX; i++) g_Traps[i].Clear();
    g_fTrapLastArm = 0.0;
}

// Per-type cost accessor. Returns -1 if the type is disabled.
stock int Trap_TypeCost(int type)
{
    switch (type)
    {
        case ZM_TRAP_TYPE_DOOR:    return g_iCostTrapDoor;
        case ZM_TRAP_TYPE_CAR:     return g_iCostTrapCar;
        case ZM_TRAP_TYPE_TORNADO: return g_iCostTrapTornado;
    }
    return -1;
}

// Per-type cap accessor.
stock int Trap_TypeMax(int type)
{
    switch (type)
    {
        case ZM_TRAP_TYPE_DOOR:    return g_iMaxTrapDoor;
        case ZM_TRAP_TYPE_CAR:     return g_iMaxTrapCar;
        case ZM_TRAP_TYPE_TORNADO: return g_iMaxTrapTornado;
    }
    return 0;
}

// True if the ZM may arm a trap of this type (cap, cooldown, bank gate).
stock bool Trap_CanAfford(int type, bool hint)
{
    int cost = Trap_TypeCost(type);
    if (cost < 0)
    {
        if (hint) update_hint("%T", "Trap disabled", zm_client);
        return false;
    }
    if (Trap_CountActive(type) >= Trap_TypeMax(type))
    {
        if (hint) update_hint("%T", "Trap max reached", zm_client);
        return false;
    }
    if ((GetGameTime() - g_fTrapLastArm) < g_fTrapCooldown)
    {
        if (hint) update_hint("%T", "Trap on cooldown", zm_client);
        return false;
    }
    if (bank - cost < 0)
    {
        if (hint) update_hint("%T", "Cannot afford", zm_client);
        return false;
    }
    return true;
}

// Accept world/props; ignore the ZM and survivors so the ray lands on the door/car itself.
public bool FilterTrapAim(int entity, int mask, int self)
{
    if (entity == self) return false;
    if (entity > 0 && entity <= MaxClients) return false; // ignore all players
    return true;
}

// Resolve what the ZM is aiming at. Returns entity index (>0) or -1; fills hitPos.
stock int Trap_GetAimedEntity(float hitPos[3])
{
    if (!IsValidClientZM()) return -1;
    float vOrigin[3], vAngles[3];
    GetClientEyePosition(zm_client, vOrigin);
    GetClientEyeAngles(zm_client, vAngles);
    Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SOLID, RayType_Infinite, FilterTrapAim, zm_client);
    int ent = -1;
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(hitPos, trace);
        ent = TR_GetEntityIndex(trace);
    }
    delete trace;
    return ent;
}

// Reserve and populate a slot. Returns slot index or -1 if full. Deducts cost.
// Does NOT fill the cooldown: the caller stamps it via Trap_ConfirmArm only once arming fully
// succeeds, so a failed arm (e.g. car conversion fails) neither burns the cooldown nor keeps the cost.
stock int Trap_Register(int type, int effect, int entity)
{
    int slot = Trap_FindFreeSlot();
    if (slot < 0) return -1;
    int cost = Trap_TypeCost(type);
    g_Traps[slot].Clear();
    g_Traps[slot].type = type;
    g_Traps[slot].effect = effect;
    g_Traps[slot].entRef = EntIndexToEntRef(entity);
    g_Traps[slot].ownerUserId = (IsValidClientZM() ? GetClientUserId(zm_client) : -1);
    g_Traps[slot].state = ZM_TRAP_STATE_ARMED;
    g_Traps[slot].costPaid = cost;
    g_Traps[slot].armedAt = GetGameTime();
    bank -= cost;
    return slot;
}

// Set the arming time after a successful arm.
stock void Trap_ConfirmArm()
{
    g_fTrapLastArm = GetGameTime();
}

// Abort an arm that failed after Trap_Register deducted cost: refund and free the slot.
// Does not touch the cooldown (Trap_Register never stamped it).
stock void Trap_AbortArm(int slot)
{
    if (slot < 0 || slot >= ZM_TRAP_MAX) return;
    bank += g_Traps[slot].costPaid;
    g_Traps[slot].Clear();
}

// Survivor-visible ornament: visible to living survivors, hidden from the ZM.
public Action OnTransmitTrapDoorSurv(int entity, int client)
{
    int parent = GetEntPropEnt(entity, Prop_Data, "m_pParent");
    if (!IsValidEntity(parent)) return Plugin_Handled;
    if (client == zm_client) return Plugin_Handled;
    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client))
        return Plugin_Handled;
    return Plugin_Continue;
}

// ZM-only accent ornament, hidden from everyone else.
public Action OnTransmitTrapDoorZM(int entity, int client)
{
    int parent = GetEntPropEnt(entity, Prop_Data, "m_pParent");
    if (!IsValidEntity(parent)) return Plugin_Handled;
    if (client == zm_client) return Plugin_Continue;
    return Plugin_Handled;
}

// Spawn a glow ornament parented to target with the given packed color. No transmit hook here.
// Returns the glow entity index, or -1.
static int Trap_SpawnOrnament(int target, int packedColor)
{
    if (!IsValidEntity(target)) return -1;
    int glow = CreateEntityByName("prop_dynamic_ornament");
    if (!IsEntitySafe(glow)) return -1;

    char sModelName[64];
    GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
    SetEntityModel(glow, sModelName);
    DispatchSpawn(glow);
    SetEntProp(glow, Prop_Send, "m_CollisionGroup", 0);
    SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
    SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
    SetEntProp(glow, Prop_Send, "m_nGlowRange", 999999);
    SetEntProp(glow, Prop_Send, "m_iGlowType", 3);
    SetEntProp(glow, Prop_Send, "m_glowColorOverride", packedColor);
    AcceptEntityInput(glow, "StartGlowing");
    SetEntityRenderMode(glow, view_as<RenderMode>(RENDER_TRANSCOLOR));
    SetEntityRenderColor(glow, 0, 0, 0, 0);
    SetVariantString("!activator");
    AcceptEntityInput(glow, "SetParent", target);
    SetVariantString("!activator");
    AcceptEntityInput(glow, "SetAttached", target);
    DispatchKeyValue(glow, "targetname", "zm_trap_glow");
    return glow;
}

stock int Trap_CreateDoorGlowSurv(int target)
{
    int glow = Trap_SpawnOrnament(target, TRAP_GLOW_SURV);
    if (glow < 0) return INVALID_ENT_REFERENCE;
    SDKHook(glow, SDKHook_SetTransmit, OnTransmitTrapDoorSurv);
    return EntIndexToEntRef(glow);
}

stock int Trap_CreateDoorGlowZM(int target)
{
    int glow = Trap_SpawnOrnament(target, TRAP_GLOW_ZM);
    if (glow < 0) return INVALID_ENT_REFERENCE;
    SDKHook(glow, SDKHook_SetTransmit, OnTransmitTrapDoorZM);
    return EntIndexToEntRef(glow);
}

stock void Trap_AttachDoorGlow(int slot, int door)
{
    g_Traps[slot].glowSurvRef = Trap_CreateDoorGlowSurv(door);
    g_Traps[slot].glowZMRef   = Trap_CreateDoorGlowZM(door);
}

stock void Trap_RemoveGlow(int slot)
{
    int s = g_Traps[slot].glowSurvRef;
    if (IsValidEntRef(s))
    {
        AcceptEntityInput(EntRefToEntIndex(s), "StopGlowing");
        RemoveEntity(s);
    }
    int z = g_Traps[slot].glowZMRef;
    if (IsValidEntRef(z))
    {
        AcceptEntityInput(EntRefToEntIndex(z), "StopGlowing");
        RemoveEntity(z);
    }
    g_Traps[slot].glowSurvRef = INVALID_ENT_REFERENCE;
    g_Traps[slot].glowZMRef = INVALID_ENT_REFERENCE;
}

// Resolve a stable effect id string to its enum
stock int Trap_EffectByName(const char[] name)
{
    if (strcmp(name, "panic",   false) == 0) return ZM_TRAP_FX_PANIC;
    if (strcmp(name, "alarm",   false) == 0) return ZM_TRAP_FX_ALARM;
    if (strcmp(name, "tornado", false) == 0) return ZM_TRAP_FX_TORNADO;
    return -1;
}

stock void Trap_EffectName(int effect, char[] out, int maxlen)
{
    switch (effect)
    {
        case ZM_TRAP_FX_PANIC:   strcopy(out, maxlen, "panic");
        case ZM_TRAP_FX_ALARM:   strcopy(out, maxlen, "alarm");
        case ZM_TRAP_FX_TORNADO: strcopy(out, maxlen, "tornado");
        default: strcopy(out, maxlen, "");
    }
}

// Returns false if arming setup failed (caller must refund + free the slot).
bool Trap_EffectOnArm(int effect, int slot)
{
    switch (effect)
    {
        case ZM_TRAP_FX_ALARM:   return FX_Alarm_OnArm(slot);
        case ZM_TRAP_FX_TORNADO: return FX_Tornado_OnArm(slot);
        // FX_PANIC has no OnArm
    }
    return true;
}

void Trap_EffectFire(int effect, int slot, int triggerClient, const float pos[3])
{
    switch (effect)
    {
        case ZM_TRAP_FX_PANIC:   FX_Panic_Fire(slot, triggerClient, pos);
        case ZM_TRAP_FX_ALARM:   FX_Alarm_Fire(slot, triggerClient, pos);
        case ZM_TRAP_FX_TORNADO: FX_Tornado_Fire(slot, triggerClient, pos);
    }
}

void Trap_EffectOnCleanup(int effect, int slot)
{
    switch (effect)
    {
        case ZM_TRAP_FX_ALARM:   FX_Alarm_OnCleanup(slot);
        case ZM_TRAP_FX_TORNADO: FX_Tornado_OnCleanup(slot);
    }
}

// Fire an effect purely by name at a position. triggerClient may be 0.
stock void Trap_FireEffectById(const char[] name, int triggerClient, const float pos[3])
{
    int fx = Trap_EffectByName(name);
    if (fx < 0) return;
    Trap_EffectFire(fx, -1, triggerClient, pos); // slot -1: effect has no backing registry slot
}

void FX_Panic_Fire(int slot, int triggerClient, const float pos[3])
{
    #pragma unused slot
    #pragma unused pos

    manual_panic = false;

    if (!panic)
    {
        toggle_panic(true, true, true); // free panic: no cost, no rate penalty
        if (panic && !ZM_finale_announced && !L4D_IsSurvivalMode())
            L4D_ForcePanicEvent();
    }

    if (g_iTrapDoorBurst > 0 && IsValidClient(triggerClient))
        spawn_free_angry_zombies(triggerClient, g_iTrapDoorBurst);
}

// Called by a source when its trap's trigger condition fires.
void Trap_OnTriggered(int slot, int triggerClient)
{
    if (slot < 0 || slot >= ZM_TRAP_MAX) return;
    if (g_Traps[slot].state != ZM_TRAP_STATE_ARMED) return;
    g_Traps[slot].state = ZM_TRAP_STATE_TRIGGERED;

    float pos[3];
    int ent = EntRefToEntIndex(g_Traps[slot].entRef);
    if (ent > 0) GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

    Trap_EffectFire(g_Traps[slot].effect, slot, triggerClient, pos);
    Trap_Cleanup(slot);
}

// Tear down every live trap. Safe to call repeatedly.
void Traps_TeardownAll()
{
    for (int i = 0; i < ZM_TRAP_MAX; i++)
        if (g_Traps[i].state != ZM_TRAP_STATE_FREE) Trap_Cleanup(i);
    g_fTrapLastArm = 0.0;
}

// Release everything a slot owns and free it. Safe to call on an already-free slot.
void Trap_Cleanup(int slot)
{
    if (slot < 0 || slot >= ZM_TRAP_MAX) return;
    if (g_Traps[slot].state == ZM_TRAP_STATE_FREE) return;

    Trap_EffectOnCleanup(g_Traps[slot].effect, slot);
    Trap_RemoveGlow(slot);

    // Source-specific teardown (e.g. unhook door output). Dispatch by source type.
    switch (g_Traps[slot].type)
    {
        case ZM_TRAP_TYPE_DOOR: TrapDoor_Teardown(slot);
        case ZM_TRAP_TYPE_CAR:  TrapCar_Teardown(slot);
    }

    g_Traps[slot].Clear();
}
