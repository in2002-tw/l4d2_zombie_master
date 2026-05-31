#if defined _zm_trap_door_included
 #endinput
#endif
#define _zm_trap_door_included

// Validate the aimed entity as a panic-door candidate.
bool TrapDoor_CanArm(int entity)
{
    if (!IsValidEntity(entity)) return false;
    char cls[32];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (strcmp(cls, "prop_door_rotating") != 0) return false;

    // Exclude reserved doors: start saferoom door and the checkpoint-last door (carries its own glow).
    if (IsValidEntRef(g_iLockedDoor) && entity == EntRefToEntIndex(g_iLockedDoor)) return false;
    if (entity == L4D_GetCheckpointLast()) return false;

    // Reject doors already trapped.
    for (int i = 0; i < ZM_TRAP_MAX; i++)
        if (g_Traps[i].state != ZM_TRAP_STATE_FREE && EntRefToEntIndex(g_Traps[i].entRef) == entity)
            return false;

    return true;
}

// Begin arm-by-aim for a panic door. Called from the menu.
void TrapDoor_BeginArm()
{
    if (!IsValidClientZM()) return;
    if (!Trap_CanAfford(ZM_TRAP_TYPE_DOOR, true)) return;

    float hitPos[3];
    int ent = Trap_GetAimedEntity(hitPos);
    if (ent <= 0 || !TrapDoor_CanArm(ent))
    {
        update_hint("%T", "Trap invalid door", zm_client);
        return;
    }

    int slot = Trap_Register(ZM_TRAP_TYPE_DOOR, ZM_TRAP_FX_PANIC, ent);
    if (slot < 0)
    {
        update_hint("%T", "Trap max reached", zm_client);
        return;
    }

    Trap_AttachDoorGlow(slot, ent);

    // Hook the door's open output once; it should auto-remove when it fires.
    HookSingleEntityOutput(ent, "OnOpen", TrapDoor_OnOpen, true);

    Trap_ConfirmArm();
    update_hint("%T", "Trap armed door", zm_client);
    RequestFrame(create_traps_menu);
}

// Entity output: door opened. Map this door to its slot and fire.
public void TrapDoor_OnOpen(const char[] output, int caller, int activator, float delay)
{
    for (int i = 0; i < ZM_TRAP_MAX; i++)
    {
        if (g_Traps[i].state != ZM_TRAP_STATE_ARMED) continue;
        if (g_Traps[i].type != ZM_TRAP_TYPE_DOOR) continue;
        if (EntRefToEntIndex(g_Traps[i].entRef) != caller) continue;
        int triggerClient = (IsValidClient(activator) ? activator : 0);
        Trap_OnTriggered(i, triggerClient);
        return;
    }
}

// Source teardown: unhook the door output if it never fired and the door still exists.
void TrapDoor_Teardown(int slot)
{
    int door = EntRefToEntIndex(g_Traps[slot].entRef);
    if (door > 0 && IsValidEntity(door))
        UnhookSingleEntityOutput(door, "OnOpen", TrapDoor_OnOpen);
}
