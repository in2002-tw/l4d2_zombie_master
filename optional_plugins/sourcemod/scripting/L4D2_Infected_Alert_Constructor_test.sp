#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#define _NATIVE_ONLY
#include "l4d2_shoot_alert_common"

public void OnPluginStart()
{   
    RegAdminCmd("alert_pointing", AlertPointing, ADMFLAG_ROOT,"Localize L4D2_Infected_Alert_Constructor where client is pointing.");
    RegAdminCmd("alert_me", AlertMe, ADMFLAG_ROOT,"Localize L4D2_Infected_Alert_Constructor on client.");
}

Action AlertPointing(int client, int args)
{
    if (GetFeatureStatus(FeatureType_Native,"L4D2_Infected_Alert_Constructor")!=FeatureStatus_Available)
    {
        LogMessage("L4D2_Infected_Alert_Constructor not available");
        return Plugin_Continue;
    }
    if (client<=0) return Plugin_Stop;
    static float pos[3], vPos[3], vAng[3];
    GetClientEyePosition(client, vPos);
    GetClientEyeAngles(client, vAng);
    TR_TraceRayFilter(vPos,vAng,MASK_ALL,RayType_Infinite,FilterSelf,client);
    if (TR_DidHit(INVALID_HANDLE)) TR_GetEndPosition(pos, INVALID_HANDLE);
    else pos = vPos;
    L4D2_Infected_Alert_Constructor(-1,client,1.0,false,pos);
    return Plugin_Continue;
}

stock bool FilterSelf(int entity, int mask, int self = -1)
{
    return entity!=self;
}

Action AlertMe(int client, int args)
{
    if (GetFeatureStatus(FeatureType_Native,"L4D2_Infected_Alert_Constructor")!=FeatureStatus_Available)
    {
        LogMessage("L4D2_Infected_Alert_Constructor not available");
        return Plugin_Continue;
    }
    if (client<=0) return Plugin_Stop;
    L4D2_Infected_Alert_Constructor(client,client);
    return Plugin_Continue;
}