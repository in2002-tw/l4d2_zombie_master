#if defined _zm_prefs_included
 #endinput
#endif
#define _zm_prefs_included

// Per-player ZM preferences, persisted across server restarts via clientprefs.
// Stored per SteamID
static Cookie g_cSpawnerMode;
static Cookie g_cPTG;
static Cookie g_cAutoCommonNum;
static Cookie g_cAutoCommonUncommon;
static Cookie g_cAutoCommonMode;
static Cookie g_cUncommonNum;

// Register cookies. Call once from OnPluginStart.
void ZMPrefs_Register()
{
    g_cSpawnerMode = RegClientCookie("zm_spawner_mode", "ZM preferred spawner/grid display mode", CookieAccess_Protected);
    g_cPTG = RegClientCookie("zm_ptg", "ZM path-to-goal indicator preference", CookieAccess_Protected);
    g_cAutoCommonNum = RegClientCookie("zm_autocommon_num", "ZM autocommon number preference", CookieAccess_Protected);
    g_cAutoCommonUncommon = RegClientCookie("zm_autocommon_uncommon", "ZM autocommon common/uncommon type preference", CookieAccess_Protected);
    g_cAutoCommonMode = RegClientCookie("zm_autocommon_mode", "ZM autocommon mode - OFF PANIC ALWAYS - preference", CookieAccess_Protected);
    g_cUncommonNum = RegClientCookie("zm_uncommon_num", "ZM uncommon number preference", CookieAccess_Protected);
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
    if (!g_bGrid) g_iSpawnerMode = 0;
    else
    {
        int mode = ReadCookieInt(client, g_cSpawnerMode, g_hSpawnerMode.IntValue);
        if (mode < 0) mode = 0;
        else if (mode > 2) mode = 2;
        g_iSpawnerMode = mode;
    }
    
    // AutoCommon: Num
    autocommon_num = ReadCookieInt(client, g_cAutoCommonNum,10);
    if (autocommon_num<1) autocommon_num = 10;

    // AutoCommon: Common/Uncommon
    autocommon_uncommons = ReadCookieInt(client, g_cAutoCommonUncommon,0) == 1;

    // AutoCommon: Mode - OFF PANIC ALWAYS
    autocommon_setting = ReadCookieInt(client, g_cAutoCommonMode,AUTOCOMMON_OFF);
    if (autocommon_setting<0) autocommon_setting = 0;
    else if (autocommon_setting>AUTOCOMMON_ALWAYS) autocommon_setting = AUTOCOMMON_ALWAYS;

    // Uncommon number
    uncommon_num = ReadCookieInt(client, g_cUncommonNum,1);
    if (uncommon_num<1) uncommon_num = 1;

    // PTG: saved value, or on by default.
    zm_draw_path = ReadCookieInt(client, g_cPTG, 1) > 0;
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

stock void ZMPrefs_SaveAutoCommonNum(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !AreClientCookiesCached(client)) return;
    char buffer[16];
    IntToString(autocommon_num, buffer, sizeof(buffer));
    g_cAutoCommonNum.Set(client, buffer);
}

stock void ZMPrefs_SaveAutoCommonUncommon(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !AreClientCookiesCached(client)) return;
    char buffer[16];
    IntToString(autocommon_uncommons, buffer, sizeof(buffer));
    g_cAutoCommonUncommon.Set(client, buffer);
}

stock void ZMPrefs_SaveAutoCommonMode(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !AreClientCookiesCached(client)) return;
    char buffer[16];
    IntToString(autocommon_setting, buffer, sizeof(buffer));
    g_cAutoCommonMode.Set(client, buffer);
}

stock void ZMPrefs_SaveUncommonNum(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !AreClientCookiesCached(client)) return;
    char buffer[16];
    IntToString(uncommon_num, buffer, sizeof(buffer));
    g_cUncommonNum.Set(client, buffer);
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
