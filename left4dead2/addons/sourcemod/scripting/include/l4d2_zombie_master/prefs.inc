#if defined _zm_prefs_included
 #endinput
#endif
#define _zm_prefs_included

// Per-player ZM preferences, persisted across server restarts via clientprefs.
// Stored per SteamID: spawner/grid display mode and the PTG indicator toggle.
static Cookie g_cSpawnerMode;
static Cookie g_cPTG;

// Register cookies. Call once from OnPluginStart.
void ZMPrefs_Register()
{
    g_cSpawnerMode = RegClientCookie("zm_spawner_mode", "ZM preferred spawner/grid display mode", CookieAccess_Protected);
    g_cPTG = RegClientCookie("zm_ptg", "ZM path-to-goal indicator preference", CookieAccess_Protected);
}

// Read an integer cookie, returning def when cookies are not cached or unset.
static stock int ReadCookieInt(int client, Cookie cookie, int def)
{
    if (!AreClientCookiesCached(client)) return def;
    char buffer[16];
    cookie.Get(client, buffer, sizeof(buffer));
    if (buffer[0] == '\0') return def;
    return StringToInt(buffer);
}

// Apply a player's saved preferences to the live globals. Falls back to the
// current defaults when no preference is stored.
stock void ZMPrefs_Apply(int client)
{
    // Spawner mode: forced off when grid is unavailable; otherwise the saved
    // value (clamped to 0..2) or the cvar default.
    if (!g_bGrid)
    {
        g_iSpawnerMode = 0;
    }
    else
    {
        int mode = ReadCookieInt(client, g_cSpawnerMode, g_hSpawnerMode.IntValue);
        if (mode < 0) mode = 0;
        else if (mode > 2) mode = 2;
        g_iSpawnerMode = mode;
    }

    // PTG: saved value, or on by default.
    zm_draw_path = ReadCookieInt(client, g_cPTG, 1) != 0;
}

// Persist the current spawner mode for this player.
stock void ZMPrefs_SaveSpawnerMode(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    if (!AreClientCookiesCached(client)) return;
    char buffer[16];
    IntToString(g_iSpawnerMode, buffer, sizeof(buffer));
    g_cSpawnerMode.Set(client, buffer);
}

// Persist the current PTG toggle for this player.
stock void ZMPrefs_SavePTG(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    if (!AreClientCookiesCached(client)) return;
    char buffer[4];
    IntToString(zm_draw_path ? 1 : 0, buffer, sizeof(buffer));
    g_cPTG.Set(client, buffer);
}
