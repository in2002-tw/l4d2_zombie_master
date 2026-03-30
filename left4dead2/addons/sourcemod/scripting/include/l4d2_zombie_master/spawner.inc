///////////////////////////////////////
#if defined _zm_spawner_included
 #endinput
#endif
#define _zm_spawner_included
///////////////////////////////////////

/**
 * Spawner dispatcher.
 * Routes spawner calls to the active provider based on zm_spawner_mode.
 * Providers: 0 = analog (ring indicator), 1 = analog + grid visuals, 2 = grid only
 */

// --- Visual feedback ---

// Is it legal for ANY spawner to spawn zombies? Reduces needless computation.
bool Spawner_Can_Spawn(int client)
{
    if (!zm_allow_spawns) return false;
    if (client>0 && client!=zm_client) return false; // allow only server or zm client to spawn zombies.
    //if (g_iSpawnerMode<2 && client==zm_client)
    //{
    //    
    //}
    return true;
}

/** Called by zm_update timer every g_fUpdateRate seconds when a menu is open. */
void Spawner_Update()
{
    bool update_analog, update_grid;
    float t_now = GetEngineTime();
    if ( g_bGrid && g_iSpawnerMode>0 && (t_now-t_last_spawner_grid_update)>=g_fUpdateRate )
        update_grid = true;
    if ( (g_iSpawnerMode<2 || !g_bGrid) && (t_now-t_last_spawner_update)>=g_fUpdateRate )
        update_analog = true;
    if (update_grid) Grid_Update();
    if (update_analog) Analog_CanSpawn(ZOMBIECLASS_BOOMER, false);
}

// --- Position resolution ---

/** Resolve N positions for common infected. Positions are trusted by the caller. */
int Spawner_ResolveCommonPositions(int count, bool flow, bool angry, bool hint,
    float[] outPositions, int maxOut)
{
    if (!Spawner_Can_Spawn(-1)) return 0;
    switch (g_iSpawnerMode)
    {
        case 2: return Grid_ResolveCommonPositions(count, flow, angry, hint,
            outPositions, maxOut);
        default: return Analog_ResolveCommonPositions(count, flow, angry, hint,
            outPositions, maxOut);
    }
}

/** Resolve one position for a witch. Returns false if no valid position found. */
bool Spawner_ResolveWitchPosition(bool flow, float outPos[3])
{
    if (!Spawner_Can_Spawn(-1)) return false;
    switch (g_iSpawnerMode)
    {
        case 2: return Grid_ResolveWitchPosition(flow, outPos);
        default: return Analog_ResolveWitchPosition(flow, outPos);
    }
}

/** Resolve one position for a special infected. Returns false if no valid position found. */
bool Spawner_ResolveSpecialPosition(int zombieclass, bool flow, float outPos[3])
{
    if (!Spawner_Can_Spawn(-1)) return false;
    switch (g_iSpawnerMode)
    {
        case 2: return Grid_ResolveSpecialPosition(zombieclass, flow, outPos);
        default: return Analog_ResolveSpecialPosition(zombieclass, flow, outPos);
    }
}

// --- Post-spawn notification ---

/** Notify provider that an entity was spawned. Provider draws flow markers if needed. */
void Spawner_NotifySpawned(int entity)
{
    switch (g_iSpawnerMode)
    {
        case 2: Grid_NotifySpawned(entity);
        default: Analog_NotifySpawned(entity);
    }
}

/** Finalize a batch spawn. Draws deferred survivor beam for commons. */
void Spawner_EndSpawn()
{
    switch (g_iSpawnerMode)
    {
        case 2: Grid_EndSpawn();
        default: Analog_EndSpawn();
    }
}

// --- Lifecycle ---

/** Provider setup when ZM role is activated. */
void Spawner_OnEnabled(int client)
{
    if (client <= 0 || client > MaxClients) return;
    if (g_iSpawnerMode>0)
    {
        GridRenderer_SetAlphaFade(g_iSpawnerMode==2);
        Grid_OnEnabled(client);
    }
}

/** Provider teardown when ZM role ends or provider switches. */
void Spawner_OnDisabled(int client)
{
    if (client <= 0 || client > MaxClients) return;
    if (g_iSpawnerMode>0) Grid_OnDisabled(client);
}

/** Called on map start after GridLib precomputation. */
void Spawner_Init()
{
    // Always init grid infrastructure so mid-round switching works
    Grid_Init();
}

/** Called on map end / plugin end. */
void Spawner_Cleanup()
{
    // Always clean up all providers to avoid leaked entities
    Grid_Cleanup();
}
