#if defined _ptg_inc_included
 #endinput
#endif
#define _ptg_inc_included

/**
 * Draw survivor escape path.
 *
 * @param client      Client entity index for which to draw. Must be a real client in the server.
 * @param duration    How long beam will display.
 * @param backward    If true, draw backwards going path (red).
 * @param join_client If true, visually connect client origin to nearest cell in survivor path.
 */
native void L4D_Path_To_Goal(int client = -1, float duration = -1.0, bool backward = false, bool join_client = true);

#if defined _NATIVE_ONLY
 #endinput
#endif

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <files>
#include <left4dhooks>

// Data structure for guide points
enum struct PlayerTime
{
	float t_engine;
    float t_game;
    float t_cooldown;
}
PlayerTime g_PlayerTime[MAXPLAYERS+1];

// is player time on cooldown for guide?
bool playertime_cooldown(PlayerTime playertime)
{
    if (playertime.t_engine<0.0 && playertime.t_game<0.0) return false;
    if ( (playertime.t_engine+playertime.t_cooldown)<GetEngineTime() ) return true;
    if ( (playertime.t_game+playertime.t_cooldown)<GetGameTime() ) return true;
    return false;
}

void playertime_update(int client, float duration = -1.0)
{
    static PlayerTime playertime;
    playertime = g_PlayerTime[client];
    if (duration < 0.0) duration = playertime.t_cooldown;
    if (duration < 0.0) return;
    playertime.t_engine = GetEngineTime();
    playertime.t_game = GetGameTime();
    playertime.t_cooldown = duration;
    g_PlayerTime[client] = playertime;
}

void reset_PlayerTime(int client = -1)
{
    PlayerTime playertime;
    if (client>0)
    {
        playertime = g_PlayerTime[client];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[client] = playertime;
        return;
    }
    for (int i = 1; i <= MaxClients; i++)
    {
        playertime = g_PlayerTime[i];
        playertime.t_game = -1.0; playertime.t_engine = -1.0; playertime.t_cooldown = -1.0;
        g_PlayerTime[i] = playertime;
    }
}

