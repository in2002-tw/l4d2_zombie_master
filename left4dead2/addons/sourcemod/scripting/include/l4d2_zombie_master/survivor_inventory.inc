///////////////////////////////////////
#if defined _zm_inventory_included
 #endinput
#endif
#define _zm_inventory_included
///////////////////////////////////////

int entref_sprites[MAXPLAYERS+1][3];

// root\materials\vgui\terror\l4d360ui\hud\inventory_painpills.vmt
// root\materials\vgui\terror\molotov_icon.vmt
// root\materials\vgui\terror\pipebomb_icon.vtf
// root\materials\vgui\terror\l4d360ui\hud\inventory_pipebomb_selected.vmt 

// 3 sprites
// 1. Grenade
// 2. Medkit / Defib
// 3. Pills / Adrenaline

// primary
// secondary
#define SLOT_THROW 0
#define SLOT_MEDKIT 1
#define SLOT_PILLS 2

#define DISTANCE_INVENTORY 3000

//0: Primary Weapon
//1: Secondary Weapon (Pistol/Melee)
//2: Throwable (Molotov/Pipe Bomb/Bile)
//3: Health Item (Medkit/Defib)
//4: Special Item (Pills/Adrenaline)

// GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")
// GetPlayerWeaponSlot(client, slot_index)

Action zm_test_inventory(int client, int args)
{
    int client2 = GetRandomSurvivor(1,1);
    if(!IsValidClient(client2) || !IsPlayerAlive(client2) || GetClientTeam(client2)!=TEAM_SURVIVOR) return Plugin_Continue;
    SpawnSpriteAbovePlayer(client2,0);
    SpawnSpriteAbovePlayer(client2,1);
    SpawnSpriteAbovePlayer(client2,2);
    return Plugin_Continue;
}

Action OnTransmitZM_Inventory(int entity, int client)
{
  	int parent = GetEntPropEnt(entity,Prop_Data,"m_pParent");
  	if (!IsValidClientZM() || !IsValidClient(parent) || !IsPlayerAlive(parent))
  	{
      	LogMessage("OnTransmitZM_Inventory killed %d, parent %d", entity, parent);
      	RemoveEntity(entity);
      	return Plugin_Handled;
  	}
  	if (client==zm_client)
  	{
      	//static float pos1[3], pos2[3];
      	//GetClientEyePosition(zm_client, pos1);
      	//GetEntPropVector(client,Prop_Send,"m_vecOrigin",pos2);
      	//if (GetVectorDistance(pos1,pos2)<=DISTANCE_INVENTORY)
        //  	DispatchKeyValue(entity, "renderamt", "255");
        //else
        //    DispatchKeyValue(entity, "renderamt", "0");
      	return Plugin_Continue;
  	}
  	return Plugin_Handled;
}



stock int SpawnSpriteAbovePlayer(int client,int slot)
{
	int entref_old = entref_sprites[client][slot];
	if (entref_old!=0 && IsValidEntRef(entref_old)) RemoveEntity(entref_old);
	entref_sprites[client][slot] = INVALID_ENT_REFERENCE;
	int iEnt = CreateEntityByName("env_sprite");
	if (!IsEntitySafe(iEnt)) return -1;
	float fOrigin[3];
	GetClientEyePosition(client, fOrigin);
	fOrigin[2] += 10.0;
	switch (slot)
	{
    	case 0:
    	{
        	SetEntityModel(iEnt, DECAL_MOLOTOV);
        	fOrigin[0] -= 10.0;
    	}
    	case 1:
    	{
        	SetEntityModel(iEnt, DECAL_MEDKIT);
    	}
    	case 2:
    	{
        	SetEntityModel(iEnt, DECAL_PILLS);
        	fOrigin[0] += 10.0;
    	}
	}
	//DispatchKeyValue(iEnt, "GlowProxySize", "1");
	DispatchKeyValue(iEnt, "rendercolor", "255 255 255");
	DispatchKeyValue(iEnt, "renderamt", "255");
	DispatchKeyValue(iEnt, "rendermode", "5");
	//DispatchKeyValue(iEnt, "rendermode", "9"); // Glow
	//DispatchKeyValue(iEnt, "renderfx", "0");
	//DispatchKeyValueFloat(iEnt, "framerate", 15.0);
	DispatchKeyValueFloat(iEnt, "scale", 0.000001);
	//SetEntPropVector(iEnt, Prop_Send, "m_vecMins", {-50.0, -50.0, 0.0});
	//SetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", {50.0, 50.0, 0.0});
	//SetEntProp(iEnt, Prop_Send, "m_nSolidType", 2);
	//int iEffects = GetEntProp(iEnt, Prop_Send, "m_fEffects");
	//SetEntProp(iEnt,Prop_Send,"m_fEffects", (iEffects | 32));
	DispatchSpawn(iEnt);
	ActivateEntity(iEnt);
	SDKHook(iEnt, SDKHook_SetTransmit, OnTransmitZM_Inventory);
	TeleportEntity(iEnt, fOrigin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetParent", client);
	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetAttached", client);
	entref_sprites[client][slot] = EntIndexToEntRef(iEnt);
	LogMessage("Created %d %d %d", client, slot, entref_sprites[client][slot]);
	return iEnt;
}

//stock bool:RemoveSpriteAbovePlayer(client)
//{
///	if(!IsClientInGame(client))
//		return false;
////	
//	decl String:sBuffer[32];
//	GetEntPropString(client, Prop_Data, "m_iName", sBuffer, sizeof(sBuffer));
//	
//	new iEnt = StringToInt(sBuffer[11]);
//	if(iEnt <= 0 || !IsValidEntity(iEnt) || !IsValidEdict(iEnt))
//		return false;
//	
//	GetEdictClassname(iEnt, sBuffer, sizeof(sBuffer));
//	if(!StrEqual(sBuffer, "env_sprite"))
//	{
//		DispatchKeyValue(client, "targetname", "");
//		return false;
//	}
//	
//	AcceptEntityInput(iEnt, "Kill");
//	DispatchKeyValue(client, "targetname", "");
//	return true;
//}