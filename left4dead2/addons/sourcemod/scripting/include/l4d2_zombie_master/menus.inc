///////////////////////////////////////
#if defined _zm_menus_included
 #endinput
#endif
#define _zm_menus_included
///////////////////////////////////////

void CategoryHandler( TopMenu topmenu,TopMenuAction action,TopMenuObject object_id,int param,char[] buffer,int maxlength)
{
  switch (action)
  {
    case TopMenuAction_DisplayTitle: Format(buffer,maxlength, "%T:", "Zombie Master", param);
    case TopMenuAction_DisplayOption: Format(buffer,maxlength, "%T", "Zombie Master", param);
  }
}
//
void AdminMenu_Handler(TopMenu topmenu,TopMenuAction action,TopMenuObject object_id,int param,char[] buffer,int maxlength)
{
  switch (action)
  {
    case TopMenuAction_DisplayOption:
    {
        if (object_id==zm_enable) Format(buffer,maxlength,"zm_enable %d",g_hCvarAllow.BoolValue);
        else if (object_id==zm_randomizer)
        {
            if (g_hRandomizer.IntValue==0) Format(buffer,maxlength,"zm_randomizer: OFF");
            else if (g_hRandomizer.IntValue==1) Format(buffer,maxlength,"zm_randomizer: Map");
            else if (g_hRandomizer.IntValue==2) Format(buffer,maxlength,"zm_randomizer: Round");
            else Format(buffer,maxlength,"zm_randomizer");
        }
        else if (object_id==zm_gamemode_menu) strcopy(buffer,maxlength,"zm_gamemode_menu"); 
        else if (object_id==zm_kick_topmenu) strcopy(buffer,maxlength,"zm_kick");
        else if (object_id==zm_sayhorde) Format(buffer,maxlength,"zm_say_horde %d",g_hSayHorde.BoolValue);
        else if (object_id==zm_help) Format(buffer,maxlength,"zm_help");
        else if (object_id==zm_random) strcopy(buffer,maxlength,"zm_gamemode random"); 
    }
    case TopMenuAction_SelectOption:
    {
        bool redisplay = true;
        if (object_id==zm_enable) SetConVarInt(g_hCvarAllow,!g_hCvarAllow.BoolValue);
        else if (object_id==zm_randomizer) next_randomizer_setting();
        else if (object_id==zm_gamemode_menu) {ZM_Gamemode_Command(param,0); redisplay = false;}
        else if (object_id==zm_kick_topmenu) zm_kick(param,0);
        else if (object_id==zm_sayhorde) SetConVarInt(g_hSayHorde,!g_hSayHorde.BoolValue);
        else if (object_id==zm_help) ZM_MOTD(param,0);
        else if (object_id==zm_random) random_gamemode();
        if (redisplay) RedisplayAdminMenu(topmenu,param);
    }
  }
}

void close_menus(int client)
{
    if (!IsValidClient(client)) return;
    InternalShowMenu(client, "\10", 1); // thanks to Zira
    CancelClientMenu(client, true, null);
    if (client==zm_client) zm_menu_state = ZM_MENU_CLOSED;
}

void open_menu(int client, int MENU=ZM_MENU_MAIN, int time=MENU_TIME_FOREVER)
{
    
    if (client!=zm_client)
    {
        close_menus(client);
        return;
    }
    
    if (!IsValidClientZM()) return;
    
    if (menu_main==null) update_menus();
    
    if (MENU<ZM_MENU_CLOSED || MENU>ZM_MENU_CONTEXT) MENU = ZM_MENU_MAIN;
    if (MENU==ZM_MENU_CLOSED) time = 1;
    
    switch(MENU)
    {
        case ZM_MENU_MAIN: menu_main.Display(zm_client,time);
        case ZM_MENU_COMMON: menu_common.Display(zm_client,time);
        case ZM_MENU_UNCOMMON: menu_uncommon.Display(zm_client,time);
        case ZM_MENU_SPECIAL: menu_special.Display(zm_client,time);
        case ZM_MENU_BOSS: menu_boss.Display(zm_client,time);
        case ZM_MENU_CLEANUP: menu_cleanup.Display(zm_client,time);
        case ZM_MENU_OTHER: menu_other.Display(zm_client,time);
        case ZM_MENU_AUTOCOMMON: menu_autocommon.Display(zm_client,time);
        case ZM_MENU_CLOSED: close_menus(zm_client);
        default: menu_main.Display(zm_client,time);
    }
    
    zm_menu_state = MENU;
    
}

void reopen_zm_menu(bool force = true)
{
    if (zm_menu_state == ZM_MENU_CLOSED || !IsValidClientZM()) return;
    if (force || GetClientMenu(zm_client)==MenuSource_None) open_menu(zm_client,zm_menu_state);
}

// MAIN MENU
void create_main_menu()
{		
	if (DEBUG) LogMessage("[zm] create_main_menu");
	if (menu_main!=INVALID_HANDLE) CloseHandle(menu_main);
	menu_main = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),main_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Zombie Master", zm_language);
	menu_main.SetTitle(buffer);
    
    if (max_zombie_arr[ZOMBIECLASS_COMMON]>0 && (g_iCostUncommon>=0 || g_iCostCommon>=0))
        Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    else buffer = "-";
    AddMenuItem(menu_main, "0", buffer);
    
    if (max_SI>0) Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
    else buffer = "-";
    AddMenuItem(menu_main, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
    AddMenuItem(menu_main, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
    AddMenuItem(menu_main, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
    AddMenuItem(menu_main, "4", buffer);
    
    if (g_bAllowFreeze && max_SI>0)
    {
        if (ZM_specials_frozen) Format(buffer, sizeof(buffer), "%T", "Unfreeze Specials", zm_language);
        else Format(buffer, sizeof(buffer), "%T", "Freeze Specials", zm_language);
    }
    else buffer = "-";
    AddMenuItem(menu_main, "5", buffer);

	menu_main.ExitButton = true;
	SetMenuOptionFlags(menu_main,MENUFLAG_NO_SOUND);
}
int main_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0:
            	{
                	if (max_zombie_arr[ZOMBIECLASS_COMMON]>0) zm_menu_state=ZM_MENU_COMMON;
            	}
            	case 1:
            	{
                	if (max_SI>0) zm_menu_state=ZM_MENU_SPECIAL;
            	}
            	case 2: zm_menu_state=ZM_MENU_BOSS;
            	case 3: zm_menu_state=ZM_MENU_CLEANUP;
            	case 4: zm_menu_state=ZM_MENU_OTHER;
            	case 5: set_specials_frozen(~ZM_specials_frozen);
            	
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }
	return 0;
}

// COMMON MENU
void create_common_menu()
{		
	if (DEBUG) LogMessage("[zm] create_common_menu");
	if (menu_common!=INVALID_HANDLE) CloseHandle(menu_common);
	menu_common = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),common_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
    	
    Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
	menu_common.SetTitle(buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x5 %d", "Common", zm_language, g_iCostCommon*5);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x5 %d", "Uncommon", zm_language, g_iCostUncommon*5);
    else buffer = "-";
    AddMenuItem(menu_common, "0", buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x10 %d", "Common", zm_language, g_iCostCommon*10);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x10 %d", "Uncommon", zm_language, g_iCostUncommon*10);
    else buffer = "-";
    AddMenuItem(menu_common, "1", buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x20 %d", "Common", zm_language, g_iCostCommon*20);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x20 %d", "Uncommon", zm_language, g_iCostUncommon*20);
    else buffer = "-"; 
    AddMenuItem(menu_common, "2", buffer);
    
    if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T", "Uncommon", zm_language);
    else buffer = "-";
    AddMenuItem(menu_common, "3", buffer);
    
    if (L4D_IsSurvivalMode() || ZM_finale_announced) AddMenuItem(menu_common, "4", "-");
    else
    {
        Format(buffer,sizeof(buffer),"%T %d", "PANIC", zm_language, g_iPanicCost);
        AddMenuItem(menu_common, "4", buffer);
    }
    
    Format(buffer,sizeof(buffer),"%T", "AutoCommon", zm_language);
    AddMenuItem(menu_common, "5", buffer);
    
    AddMenuItem(menu_common, "6", "<-- (R)");

	menu_common.ExitButton = true;
	SetMenuOptionFlags(menu_common,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_COMMON && IsValidClientZM()) open_menu(zm_client,ZM_MENU_COMMON);
}
int common_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Horde(zm_client,5);
            	case 1: ZM_Horde(zm_client,10);
            	case 2: ZM_Horde(zm_client,20);
            	case 3: zm_menu_state=ZM_MENU_UNCOMMON;
            	case 4:
            	{
                	if (!L4D_IsSurvivalMode() && !ZM_finale_announced) ZMPanic(zm_client,0);
            	}
            	case 5: zm_menu_state=ZM_MENU_AUTOCOMMON;
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// UNCOMMON MENU
void create_uncommon_menu()
{		
	if (DEBUG) LogMessage("[zm] create_uncommon_menu");
	if (menu_uncommon!=INVALID_HANDLE) CloseHandle(menu_uncommon);
	menu_uncommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),uncommon_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
	menu_uncommon.SetTitle(buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"riot")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Riot", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "0", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"ceda")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "CEDA", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "1", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"clown")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Clown", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "2", buffer);
   
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"mud")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Mud", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"road")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Road", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "4", buffer);
    
    if (!panic && !L4D_IsSurvivalMode() && !ZM_finale_announced && g_iCostUncommon>=0)
    {
        if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, g_iCostUncommon);
        else Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, 2*g_iCostUncommon);
    }
    else buffer = "-";
    AddMenuItem(menu_uncommon, "5", buffer);
    
    AddMenuItem(menu_uncommon, "6", "<-- (R)");

	menu_uncommon.ExitButton = true;
	SetMenuOptionFlags(menu_uncommon,MENUFLAG_NO_SOUND);
}
int uncommon_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Horde(zm_client,1,"riot");
            	case 1: ZM_Horde(zm_client,1,"ceda");
            	case 2: ZM_Horde(zm_client,1,"clown");
            	case 3: ZM_Horde(zm_client,1,"mud");
            	case 4: ZM_Horde(zm_client,1,"road");
            	case 5: ZM_Horde(zm_client,1,"",true);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// SPECIAL MENU
void create_special_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_special");
	if (menu_special!=INVALID_HANDLE) CloseHandle(menu_special);
	menu_special = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),special_menu_Handler);
    
    int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
    int occupied, max;
    
    Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
	menu_special.SetTitle(buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_BOOMER];
    if (max>0 && costs_SI[ZOMBIECLASS_BOOMER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_BOOMER], live_zombie_arr[ZOMBIECLASS_BOOMER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Boomer", zm_language, costs_SI[ZOMBIECLASS_BOOMER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "0", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SPITTER];
    if (l4d2_specials && max>0 && costs_SI[ZOMBIECLASS_SPITTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SPITTER], live_zombie_arr[ZOMBIECLASS_SPITTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Spitter", zm_language, costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "1", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SMOKER];
    if (max>0 && costs_SI[ZOMBIECLASS_SMOKER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SMOKER], live_zombie_arr[ZOMBIECLASS_SMOKER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Smoker", zm_language, costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "2", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_HUNTER];
    if (max>0 && costs_SI[ZOMBIECLASS_HUNTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_HUNTER], live_zombie_arr[ZOMBIECLASS_HUNTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Hunter", zm_language, costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "3", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_JOCKEY];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_JOCKEY]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_JOCKEY], live_zombie_arr[ZOMBIECLASS_JOCKEY]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Jockey", zm_language, costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "4", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_CHARGER];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_CHARGER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_CHARGER], live_zombie_arr[ZOMBIECLASS_CHARGER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Charger", zm_language, costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "5", buffer);
    
    AddMenuItem(menu_special, "6", "<-- (R)");

	menu_special.ExitButton = true;
	SetMenuOptionFlags(menu_special,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_SPECIAL && IsValidClientZM()) open_menu(zm_client,ZM_MENU_SPECIAL);
}
int special_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Boomer(zm_client,0);
            	case 1: ZM_Spitter(zm_client,0);
            	case 2: ZM_Smoker(zm_client,0);
            	case 3: ZM_Hunter(zm_client,0);
            	case 4: ZM_Jockey(zm_client,0);
            	case 5: ZM_Charger(zm_client,0);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// BOSS MENU
void create_boss_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_boss");
	if (menu_boss!=INVALID_HANDLE) CloseHandle(menu_boss);
	menu_boss = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),boss_menu_Handler);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
	menu_boss.SetTitle(buffer);
    
    if (g_iCostWitchMoving>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Moving", zm_language, g_iCostWitchMoving);
    else buffer = "-";
    AddMenuItem(menu_boss, "0", buffer);
    if (g_iCostWitchStatic>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Static", zm_language, g_iCostWitchStatic);
    else buffer = "-";
    AddMenuItem(menu_boss, "1", buffer);
    
    int max = max_zombie_arr[ZOMBIECLASS_TANK];
    if (max>0 && costs_SI[ZOMBIECLASS_TANK]>=0)
    {
        int occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_TANK], live_zombie_arr[ZOMBIECLASS_TANK]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Tank", zm_language, costs_SI[ZOMBIECLASS_TANK], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_boss, "2", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"jimmy")!=0) buffer = "-";
    else if (jimmy_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Jimmy Gibbs Jr", zm_language,g_iCostUncommon);
    AddMenuItem(menu_boss, "3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"fallen")!=0) buffer = "-";
    else if (fallen_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Fallen Survivor", zm_language,g_iCostUncommon);
    AddMenuItem(menu_boss, "4", buffer);
    
    AddMenuItem(menu_boss, "5", "-");
    AddMenuItem(menu_boss, "6", "<-- (R)");

	menu_boss.ExitButton = true;
	SetMenuOptionFlags(menu_boss,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_BOSS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_BOSS);
}
int boss_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Witch(zm_client,WITCH_MOVING);
            	case 1: ZM_Witch(zm_client,WITCH_STATIC);
            	case 2: ZM_Tank(zm_client,0);
            	case 3: { if (!jimmy_spawned) ZM_Horde(zm_client,1,"jimmy"); }
            	case 4: { if (!fallen_spawned) ZM_Horde(zm_client,1,"fallen"); }
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// CLEANUP MENU
void create_cleanup_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_cleanup");
	if (menu_cleanup!=INVALID_HANDLE) CloseHandle(menu_cleanup);
	menu_cleanup = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),cleanup_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
	menu_cleanup.SetTitle(buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Target", zm_language);
    AddMenuItem(menu_cleanup, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Commons", zm_language);
    AddMenuItem(menu_cleanup, "1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Specials", zm_language);
    AddMenuItem(menu_cleanup, "2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Witches", zm_language);
    AddMenuItem(menu_cleanup, "3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete ALL", zm_language);
    AddMenuItem(menu_cleanup, "4", buffer);
    
    AddMenuItem(menu_cleanup, "5", "-");
    
    AddMenuItem(menu_cleanup, "6", "<-- (R)");

	menu_cleanup.ExitButton = true;
	SetMenuOptionFlags(menu_cleanup,MENUFLAG_NO_SOUND);
}
int cleanup_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: ZM_Delete(zm_client,0);
            	case 1: ZM_Delete_Commons(zm_client,0);
            	case 2: ZM_Delete_Specials(zm_client,0);
            	case 3: ZM_Delete_Witches(zm_client,0);
            	case 4: ZM_Delete_All(zm_client,0);
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

// OTHER MENU
void create_other_menu()
{		
	if (DEBUG) LogMessage("[zm] create_menu_other");
	if (menu_other!=INVALID_HANDLE) CloseHandle(menu_other);
	menu_other = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),other_menu_Handler);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
	menu_other.SetTitle(buffer);
    
    if (zm_stage>=ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Control (USE)", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Start Round", zm_language);
        AddMenuItem(menu_other, "0", buffer);
    }
    else AddMenuItem(menu_other, "0", "-");
    
    Format(buffer, sizeof(buffer), "Display: %s", g_iSpawnerMode == 0 ? "Analog" : "Grid");
    AddMenuItem(menu_other, "1", buffer);

    Format(buffer, sizeof(buffer), "%T", "Teleport", zm_language);
    AddMenuItem(menu_other, "2", buffer);

    AddMenuItem(menu_other, "3", "-");

    Format(buffer, sizeof(buffer), "%T", "Give Up", zm_language);
    AddMenuItem(menu_other, "4", buffer);

    AddMenuItem(menu_other, "5", "-");
    AddMenuItem(menu_other, "6", "<-- (R)");

	menu_other.ExitButton = true;
	SetMenuOptionFlags(menu_other,MENUFLAG_NO_SOUND);
	
	if (zm_menu_state == ZM_MENU_OTHER && IsValidClientZM()) open_menu(zm_client,ZM_MENU_OTHER);
	
}
int other_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: 
            	{
                	if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED) zm_start(zm_client,0);
                	else
                	{
                    	if (zm_stage==ZM_STARTED)
                    	{
                        	if (live_SI>0) ZMControlSI(zm_client,0);
                        	else zm_menu_state=ZM_MENU_SPECIAL;
                    	}
                	}
            	}
            	case 1:
            	{
            	    // Toggle spawner display mode
            	    int newMode = (g_iSpawnerMode + 1) % 2;
            	    Spawner_OnDisabled(zm_client);
            	    g_iSpawnerMode = newMode;
            	    Spawner_OnEnabled(zm_client);
            	    create_other_menu();
            	}
            	case 2: ZMTeleport(zm_client,0);
            	case 4: {QuitZM(zm_client); return 0;}
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);     	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }
	return 0;
}

// AUTOCOMMON MENU
void create_autocommon_menu()
{		
	if (DEBUG) LogMessage("[zm] create_autocommon_menu");
	if (menu_autocommon!=INVALID_HANDLE) CloseHandle(menu_autocommon);
	menu_autocommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),autocommon_menu_Handler);
	
	char buffer[64]; 
    int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    	
    Format(buffer, sizeof(buffer), "%T", "AutoCommon", zm_language);
	menu_autocommon.SetTitle(buffer);
    
    switch (autocommon_setting)
    {
        case AUTOCOMMON_ALWAYS: Format(buffer, sizeof(buffer), "%T", "AutoCommon ALWAYS", zm_language);
        case AUTOCOMMON_PANIC: Format(buffer, sizeof(buffer), "%T", "AutoCommon PANIC", zm_language);
        default: Format(buffer, sizeof(buffer), "%T", "AutoCommon OFF", zm_language);
    }
    AddMenuItem(menu_autocommon, "0", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "AutoCommon Max", zm_language, autocommon_num);
    AddMenuItem(menu_autocommon, "1", buffer);
    
    if (autocommon_uncommons) Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
    else Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    AddMenuItem(menu_autocommon, "2", buffer);
    
    AddMenuItem(menu_autocommon, "3", "-");
    AddMenuItem(menu_autocommon, "4", "-");
    AddMenuItem(menu_autocommon, "5", "-");
    AddMenuItem(menu_autocommon, "6", "<-- (R)");

	menu_autocommon.ExitButton = true;
	SetMenuOptionFlags(menu_autocommon,MENUFLAG_NO_SOUND);
	if (zm_menu_state == ZM_MENU_AUTOCOMMON && IsValidClientZM()) open_menu(zm_client,ZM_MENU_AUTOCOMMON);
}
int autocommon_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: next_autocommon_setting();
            	case 1: next_autocommon_num();
            	case 2:
            	{
                	if (g_iCostUncommon<0) autocommon_uncommons=false;
                	else if (g_iCostCommon<0 || valid_uncommon(g_sForceCommon)) autocommon_uncommons=true;
                	else autocommon_uncommons=~autocommon_uncommons;
                	create_autocommon_menu();
                	return 0;
            	}
            	case 6: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        	
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit) zm_menu_state=ZM_MENU_CLOSED;
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }

	return 0;
}

void update_menus()
{
    if (DEBUG) LogMessage("[zm] update_menus");
    create_main_menu();
    create_other_menu();
    create_cleanup_menu();
    create_boss_menu();
    create_special_menu();
    create_uncommon_menu();
    create_common_menu();
    create_autocommon_menu();
}

int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_VoteEnd)
    {
        if (param1 == 0)
        {
            if (g_bCvarAllow) SetConVarInt(g_hCvarAllow,0);
            else SetConVarInt(g_hCvarAllow,1);
        }
    }
    return 0;
}
 
void DoVoteMenu()
{
    if (IsVoteInProgress()) return;
    EmitSoundToAll(SOUND_READY);
    Menu menu = new Menu(Handle_VoteMenu);
    if (g_bCvarAllow) menu.SetTitle("Zombie Master -> OFF?");
    else menu.SetTitle("Zombie Master -> ON?");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}
 
Action VoteZM(int client, int args)
{
    if (L4D_HasPlayerControlledZombies())
    {
        PrintToChat(client, "[zm] %t", "ZM restrict notify");
        return Plugin_Stop;
    }
    
    if (IsVoteInProgress()) return Plugin_Stop;
    
    DoVoteMenu();
    return Plugin_Continue;
}

Action ZM_Menu(int client, int args)
{
    if (!g_bCvarAllow || client!=zm_client || !IsValidClientZM()) return Plugin_Continue;
    char type[32] = "main";
    if (args>0) GetCmdArg(1, type, sizeof(type));
	TrimString(type);
	
	int MENU = ZM_MENU_MAIN;
	if (strcmp(type,"main")==0) MENU = ZM_MENU_MAIN;
	else if (strcmp(type,"common")==0) MENU = ZM_MENU_COMMON;
	else if (strcmp(type,"uncommon")==0) MENU = ZM_MENU_UNCOMMON;
	else if (strcmp(type,"special")==0) MENU = ZM_MENU_SPECIAL;
	else if (strcmp(type,"boss")==0) MENU = ZM_MENU_BOSS;
	else if (strcmp(type,"cleanup")==0) MENU = ZM_MENU_CLEANUP;
	else if (strcmp(type,"other")==0) MENU = ZM_MENU_OTHER;
	else if (strcmp(type,"close")==0) MENU = ZM_MENU_CLOSED;
	else MENU = ZM_MENU_MAIN;
    open_menu(zm_client,MENU);
    return Plugin_Continue;
}