///////////////////////////////////////
#if defined _zm_spawner_included
 #endinput
#endif
#define _zm_spawner_included
///////////////////////////////////////

/**
 * Spawner dispatcher.
 * Routes spawner calls to the active provider based on zm_spawner_mode.
 * Providers: 0 = analog (ring indicator).
 */

// --- Visual feedback ---

/** Called by zm_update timer every g_fUpdateRate seconds when a menu is open. */
int Spawner_Update()
{
    switch (g_iSpawnerMode)
    {
        default: return Analog_CanSpawn(false, false);
    }
}

// --- Position resolution ---

/** Resolve N positions for common infected. Positions are trusted by the caller. */
int Spawner_ResolveCommonPositions(int count, bool flow, bool angry, bool hint,
    float[] outPositions, int maxOut)
{
    switch (g_iSpawnerMode)
    {
        default: return Analog_ResolveCommonPositions(count, flow, angry, hint,
            outPositions, maxOut);
    }
}

/** Resolve one position for a witch. Returns false if no valid position found. */
bool Spawner_ResolveWitchPosition(bool flow, float outPos[3])
{
    switch (g_iSpawnerMode)
    {
        default: return Analog_ResolveWitchPosition(flow, outPos);
    }
}

/** Resolve one position for a special infected. Returns false if no valid position found. */
bool Spawner_ResolveSpecialPosition(int zombieclass, bool flow, float outPos[3])
{
    switch (g_iSpawnerMode)
    {
        default: return Analog_ResolveSpecialPosition(zombieclass, flow, outPos);
    }
}

// --- Post-spawn notification ---

/** Notify provider that an entity was spawned. Provider draws flow markers if needed. */
void Spawner_NotifySpawned(int entity)
{
    switch (g_iSpawnerMode)
    {
        default: Analog_NotifySpawned(entity);
    }
}

/** Finalize a batch spawn. Draws deferred survivor beam for commons. */
void Spawner_EndSpawn()
{
    switch (g_iSpawnerMode)
    {
        default: Analog_EndSpawn();
    }
}

// --- Lifecycle stubs (wired up when providers need them) ---

/** Provider setup when ZM role is activated. */
stock void Spawner_OnEnabled(int client)
{
    #pragma unused client
    switch (g_iSpawnerMode)
    {
        // future: case 1: Grid_OnEnabled(client);
    }
}

/** Provider teardown when ZM role ends or provider switches. */
stock void Spawner_OnDisabled(int client)
{
    #pragma unused client
    switch (g_iSpawnerMode)
    {
        // future: case 1: Grid_OnDisabled(client);
    }
}

/** Called on map start after GridLib precomputation. */
stock void Spawner_Init()
{
    switch (g_iSpawnerMode)
    {
        // future: case 1: Grid_Init();
    }
}

/** Called on map end / plugin end. */
stock void Spawner_Cleanup()
{
    // Always clean up all providers to avoid leaked entities
    // future: Grid_Cleanup();
}
