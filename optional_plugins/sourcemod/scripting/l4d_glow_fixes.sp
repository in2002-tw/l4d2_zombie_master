//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//You should have received a copy of the GNU General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define PLUGIN_VERSION 			"1.0"

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Glow Fixes",
	author = "gvazdas",
	description = "Fix stuck glows.",
	version = PLUGIN_VERSION,
	url = "https://github.com/gvazdas/l4d2_zombie_master"
}

public void OnPluginStart()
{
    //HookEvent("nav_blocked",              evtNavBlocked,     EventHookMode_Post);
    RegAdminCmd("glow_fix", CmdTest, ADMFLAG_ROOT,"Test");
}

//void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
//{
//    
//}

Action CmdTest(int client, int args)
{
    
    int clients_applied, ornaments_applied = 0;
    static float pos[3];

    for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (IsPlayerAlive(i)) CLIENT_GLOW_TRANSMIT_ALWAYS(i);
        else remove_client_glow(i);
        clients_applied += 1;
	}

    int entity = INVALID_ENT_REFERENCE;
	while ( ((entity = FindEntityByClassname(entity, "prop_dynamic_ornament")) != INVALID_ENT_REFERENCE) )
    {
    	SET_TRANSMIT_ALWAYS(entity);
        ornaments_applied += 1;
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
        if (pos[0]==0.0 && pos[1]==0.0 && pos[2]==0.0)
        {
            LogMessage("ornament %d at 0.0 0.0 0.0", entity);
        }
    }

    LogMessage("clients %d ornaments %d", clients_applied, ornaments_applied);

    return Plugin_Continue;

}

public void OnMapStart()
{
	
}

public void OnMapEnd()
{
    
}

public void OnPluginEnd()
{
    
}

public void OnClientPutInServer(int client)
{
    
}

public void OnClientDisconnect(int client)
{

}

stock void SET_TRANSMIT_ALWAYS(int entity)
{
    int flags = GetEdictFlags(entity);
    SetEdictFlags(entity, flags | FL_EDICT_ALWAYS);
}

stock void CLIENT_GLOW_TRANSMIT_ALWAYS(int entity)
{
    SET_TRANSMIT_ALWAYS(entity);
    ChangeEdictState(entity,FindDataMapInfo(entity,"m_Glow"));
}

stock void remove_client_glow(int client)
{
    L4D2_RemoveEntityGlow(client);
    SetEntProp(client, Prop_Send, "m_iGlowType", 0);
    SetEntProp(client, Prop_Send, "m_glowColorOverride", 0);
    ChangeEdictState(client,FindDataMapInfo(client,"m_Glow"));
}

stock bool IsValidClient(int client, bool replaycheck = true)
{
	if (client<1 || client>MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}