///////////////////////////////////////
#if defined _zm_inventory_included
 #endinput
#endif
#define _zm_inventory_included
///////////////////////////////////////

void survivor_items_changed(bool inventory = true, bool weapons = true)
{
	if (weapons && !g_bWeapons)
	{
		g_bWeapons = true;
		RequestFrame(survivor_weapons_changed);
	}
	if (inventory && !g_bInventory)
	{
		g_bInventory = true;
		RequestFrame(survivor_inventory_changed);
	}
}

void survivor_inventory_changed()
{
	delete menu_items;
    if (zm_menu_state == ZM_MENU_ITEMS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_ITEMS);
	g_bWeapons = false;
}

void survivor_weapons_changed()
{
	delete menu_weapons;
	if (zm_menu_state == ZM_MENU_WEAPONS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_WEAPONS);
	g_bInventory = false;
}

void count_survivor_items()
{
	g_iMolotov=0;g_iPipeBomb=0;g_iBileJar=0;g_iMedkit=0;g_iDefib=0;g_iIncendiary=0;g_iExplosive=0;g_iPills=0;g_iAdrenaline=0;
	g_iPistol=0;g_iMagnum=0;g_iMelee=0;g_iSMG=0;g_iShotgunT1=0;g_iRifle=0;g_iShotgunT2=0;g_iChainsaw=0;g_iGnome=0;
	int entity;
	static char class[32];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=TEAM_SURVIVOR) continue;
		for (int slot = 2; slot <= 5; slot++)
		{
			entity = GetPlayerWeaponSlot(i,slot);
			if (!IsValidEntity(entity)) continue;
			GetEntityClassname(entity,class, sizeof(class));
			//LogMessage("%d %d %d %s", i, slot, entity, class);
			if (class[0]!='w') continue;
			switch (class[7])
			{
				case 'm':
				{
					if (strncmp(class,"weapon_molotov",14,false)==0) g_iMolotov += 1;
				}
				case 'p':
				{
					if (strncmp(class,"weapon_pipe_bomb",16,false)==0) g_iPipeBomb += 1;
					if (strncmp(class,"weapon_pain_pills",17,false)==0) g_iPills += 1;
				}
				case 'v':
				{
					if (strncmp(class,"weapon_vomitjar",15,false)==0) g_iBileJar += 1;
				}
				case 'f':
				{
					if (strncmp(class,"weapon_first_aid_kit",20,false)==0) g_iMedkit += 1;
				}
				case 'd':
				{
					if (strncmp(class,"weapon_defibrillator",20,false)==0) g_iDefib += 1;
				}
				case 'u':
				{
					if (strncmp(class,"weapon_upgradepack_incendiary",29,false)==0) g_iIncendiary += 1;
					if (strncmp(class,"weapon_upgradepack_explosive",28,false)==0) g_iExplosive += 1;
				}
				case 'a':
				{
					if (strncmp(class,"weapon_adrenaline",17,false)==0) g_iAdrenaline += 1;
				}
			}
		}
	}
}

void count_survivor_weapons()
{
	g_iPistol=0;g_iMagnum=0;g_iMelee=0;g_iSMG=0;g_iShotgunT1=0;g_iRifle=0;g_iShotgunT2=0;g_iChainsaw=0;g_iGnome=0;
	int entity;
	static char class[32];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=TEAM_SURVIVOR) continue;

		// Active Weapon
		GetClientWeapon(i,class,sizeof(class));
		if (strncmp(class,"weapon_gnome",12,false)==0) g_iGnome += 1;
		
		// Inventory
		for (int slot = 0; slot <= 1; slot++)
		{
			entity = GetPlayerWeaponSlot(i,slot);
			if (!IsValidEntity(entity)) continue;
			GetEntityClassname(entity,class, sizeof(class));
			if (class[0]!='w') continue;
			switch (class[7])
			{
				case 'm':
				{
					if (strncmp(class,"weapon_melee",12,false)==0) g_iMelee += 1;
				}
				case 'p':
				{
					if (strncmp(class,"weapon_pistol_magnum",20,false)==0) g_iMagnum += 1;
					else if (strncmp(class,"weapon_pistol",13,false)==0) g_iPistol += 1;
					else if (strncmp(class,"weapon_pumpshotgun",18,false)==0) g_iShotgunT1 += 1;
				}
				case 's':
				{
					if (strncmp(class,"weapon_sniper",13,false)==0) g_iRifle += 1;
					else if (strncmp(class,"weapon_smg",10,false)==0) g_iSMG += 1;
					else if (strncmp(class,"weapon_shotgun_chrome",21,false)==0) g_iShotgunT1 += 1;
					else if (strncmp(class,"weapon_shotgun_spas",19,false)==0) g_iShotgunT2 += 1;
				}
				case 'h':
				{
					if (strncmp(class,"weapon_hunting_rifle",20,false)==0) g_iRifle += 1;
				}
				case 'r':
				{
					if (strncmp(class,"weapon_rifle",12,false)==0) g_iRifle += 1;
				}
				case 'g':
				{
					if (strncmp(class,"weapon_grenade_launcher",23,false)==0) g_iRifle += 1;
				}
				case 'a':
				{
					if (strncmp(class,"weapon_autoshotgun",18,false)==0) g_iShotgunT2 += 1;
				}
				case 'c':
				{
					if (strncmp(class,"weapon_chainsaw",15,false)==0) g_iChainsaw += 1;
				}
			}
		}
	}
}

#endinput

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

int entref_sprites[MAXPLAYERS+1][3];

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