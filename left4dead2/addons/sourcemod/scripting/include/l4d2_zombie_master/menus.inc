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
    
    if (MENU<ZM_MENU_QUIT || MENU>=ZM_MENU_MAX) MENU = ZM_MENU_MAIN;
    if (MENU==ZM_MENU_CLOSED) time = 1;
    
    switch(MENU)
    {
        case ZM_MENU_MAIN: menu_main.Display(zm_client,time);
        case ZM_MENU_COMMON:
        {
            update_spawner_zombieclass(ZOMBIECLASS_COMMON);
            menu_common.Display(zm_client,time);
        }
        case ZM_MENU_UNCOMMON:
        {
            update_spawner_zombieclass(ZOMBIECLASS_COMMON);
            menu_uncommon.Display(zm_client,time);
        }
        case ZM_MENU_SPECIAL:
        {
            update_spawner_zombieclass(ZOMBIECLASS_BOOMER);
            menu_special.Display(zm_client,time);
        }
        case ZM_MENU_BOSS: menu_boss.Display(zm_client,time);
        case ZM_MENU_CLEANUP: menu_cleanup.Display(zm_client,time);
        case ZM_MENU_OTHER: menu_other.Display(zm_client,time);
        case ZM_MENU_ITEMS:
        {
            if (menu_items==null) create_items_menu();
            menu_items.Display(zm_client,time);
        }
        case ZM_MENU_TRAPS: menu_traps.Display(zm_client,time);
        case ZM_MENU_QUIT:
        {
            if (zm_menu_state!=ZM_MENU_QUIT) create_quit_menu();
            menu_quit.Display(zm_client,time);
        }
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

// Apply menu settings homogenously to all ZM menus. Main menu gets no exit button.
void apply_zm_menu_settings(Menu menu)
{
    SetMenuOptionFlags(menu,MENUFLAG_NO_SOUND);
    //menu.ExitButton = false;
    menu.Pagination = MENU_NO_PAGINATION;
}

// Add "fake" unselectable new line of gray text to menu.
void buffer_add_rawline(char[] buffer, char[] add = "\nR. <--", int maxlen=64)
{
    Format(buffer,maxlen,"%s%s", buffer, add);
}

// MAIN MENU
void create_main_menu()
{		
	if (DEBUG) LogMessage("[zm] create_main_menu");
	delete menu_main;
	menu_main = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),main_menu_Handler);
    apply_zm_menu_settings(menu_main);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Zombie Master", zm_language);
	menu_main.SetTitle(buffer);
    
    if (max_zombie_arr[ZOMBIECLASS_COMMON]>0 && (g_iCostUncommon>=0 || g_iCostCommon>=0))
        Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
    else buffer = "-";
    menu_main.AddItem("item_1",buffer);
    
    if (max_SI>0) Format(buffer, sizeof(buffer), "%T", "Special", zm_language);
    else buffer = "-";
    menu_main.AddItem("item_2",buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
    menu_main.AddItem("item_3",buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
    menu_main.AddItem("item_4",buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
    menu_main.AddItem("item_5",buffer);

    Format(buffer, sizeof(buffer), "%T", "Inventory", zm_language);
    if (!g_hTraps.BoolValue) buffer_add_rawline(buffer);
    menu_main.AddItem("item_6",buffer);

    if (g_hTraps.BoolValue)
    {
        Format(buffer, sizeof(buffer), "%T", "Traps", zm_language);
        buffer_add_rawline(buffer);
        menu_main.AddItem("item_7",buffer);
    }
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
                	if (max_zombie_arr[ZOMBIECLASS_COMMON]>0 && (g_iCostCommon>=0 || g_iCostUncommon>=0)) zm_menu_state=ZM_MENU_COMMON;
            	}
            	case 1:
            	{
                	if (max_SI>0) zm_menu_state=ZM_MENU_SPECIAL;
            	}
            	case 2: zm_menu_state=ZM_MENU_BOSS;
            	case 3: zm_menu_state=ZM_MENU_CLEANUP;
            	case 4: zm_menu_state=ZM_MENU_OTHER;
            	case 5: zm_menu_state=ZM_MENU_ITEMS;
            	case 6:
                {
                    if (g_hTraps.BoolValue) zm_menu_state=ZM_MENU_TRAPS;
                }
                default: zm_menu_state=ZM_MENU_MAIN;
            	
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
	delete menu_common;
	menu_common = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),common_menu_Handler);
    apply_zm_menu_settings(menu_common);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
    	
    Format(buffer, sizeof(buffer), "%T", "Common", zm_language);
	menu_common.SetTitle(buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x5 %d", "Common", zm_language, g_iCostCommon*5);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x5 %d", "Uncommon", zm_language, g_iCostUncommon*5);
    else buffer = "-";
    menu_common.AddItem("item_1",buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x10 %d", "Common", zm_language, g_iCostCommon*10);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x10 %d", "Uncommon", zm_language, g_iCostUncommon*10);
    else buffer = "-";
    menu_common.AddItem("item_2",buffer);
    
    if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T x20 %d", "Common", zm_language, g_iCostCommon*20);
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T x20 %d", "Uncommon", zm_language, g_iCostUncommon*20);
    else buffer = "-"; 
    menu_common.AddItem("item_3",buffer);
    
    if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T", "Uncommon", zm_language);
    else buffer = "-";
    menu_common.AddItem("item_4",buffer);
    
    if (ZM_finale_announced || g_iPanicCost<0 || L4D_IsSurvivalMode()) Format(buffer,sizeof(buffer),"-\n%t", "AutoCommon", zm_language);
    else Format(buffer,sizeof(buffer),"%t %d\n%t", "PANIC", g_iPanicCost, "AutoCommon", zm_language);
    menu_common.AddItem("item_5",buffer);

    switch (autocommon_setting)
    {
        case AUTOCOMMON_ALWAYS: Format(buffer, sizeof(buffer), "%t: %t", "Mode", "ALWAYS", zm_language);
        case AUTOCOMMON_PANIC: Format(buffer, sizeof(buffer), "%t: %t", "Mode", "PANIC", zm_language);
        default: Format(buffer, sizeof(buffer), "%t: %t", "Mode", "OFF", zm_language);
    }
    menu_common.AddItem("item_6",buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Max", zm_language, autocommon_num);
    menu_common.AddItem("item_7",buffer);
    
    if (autocommon_uncommons) Format(buffer, sizeof(buffer), "%t: %t", "Mode", "Uncommon", zm_language);
    else Format(buffer, sizeof(buffer), "%t: %t", "Mode", "Common", zm_language);
    buffer_add_rawline(buffer);
    menu_common.AddItem("item_8",buffer);
	
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
                	if (g_iPanicCost>=0 && !ZM_finale_announced && !L4D_IsSurvivalMode()) ZMPanic(zm_client,0);
            	}
                case 5: next_autocommon_setting();
            	case 6: next_autocommon_num();
            	case 7:
            	{
                	if (g_iCostUncommon<0) autocommon_uncommons=false;
                	else if (g_iCostCommon<0 || valid_uncommon(g_sForceCommon)) autocommon_uncommons=true;
                	else autocommon_uncommons=!autocommon_uncommons;
                	create_common_menu();
                    ZMPrefs_SaveAutoCommonUncommon(zm_client);
                	return 0;
            	}
                default: zm_menu_state=ZM_MENU_MAIN;
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
	delete menu_uncommon;
	menu_uncommon = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),uncommon_menu_Handler);
    apply_zm_menu_settings(menu_uncommon);
    
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Uncommon", zm_language);
	menu_uncommon.SetTitle(buffer);
    
    if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%s %d", "Random", g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_1", buffer);

    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"riot")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Riot", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_2", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"ceda")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "CEDA", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"clown")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Clown", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_4", buffer);
   
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"mud")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Mud", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_5", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"road")!=0) buffer = "-";
    else if (g_iCostUncommon>=0) Format(buffer,sizeof(buffer),"%T %d", "Road", zm_language, g_iCostUncommon);
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_6", buffer);
    
    if (!panic && !L4D_IsSurvivalMode() && !ZM_finale_announced && g_iCostUncommon>=0)
    {
        if (g_iCostCommon>=0 && !valid_uncommon(g_sForceCommon)) Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, g_iCostUncommon);
        else Format(buffer,sizeof(buffer),"%T %d", "Angry", zm_language, 2*g_iCostUncommon);
    }
    else buffer = "-";
    AddMenuItem(menu_uncommon, "item_7", buffer);

    Format(buffer,sizeof(buffer),"x%d", uncommon_num);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_uncommon, "item_8", buffer);
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
            	case 0: ZM_Horde(zm_client,uncommon_num,"random");
                case 1: ZM_Horde(zm_client,uncommon_num,"riot");
            	case 2: ZM_Horde(zm_client,uncommon_num,"ceda");
            	case 3: ZM_Horde(zm_client,uncommon_num,"clown");
            	case 4: ZM_Horde(zm_client,uncommon_num,"mud");
            	case 5: ZM_Horde(zm_client,uncommon_num,"road");
            	case 6: ZM_Horde(zm_client,uncommon_num,"",true);
                case 7: next_uncommon_num();
            	default: zm_menu_state=ZM_MENU_MAIN;
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
	delete menu_special;
	menu_special = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),special_menu_Handler);
    apply_zm_menu_settings(menu_special);
    
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
    AddMenuItem(menu_special, "item_1", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SPITTER];
    if (l4d2_specials && max>0 && costs_SI[ZOMBIECLASS_SPITTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SPITTER], live_zombie_arr[ZOMBIECLASS_SPITTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Spitter", zm_language, costs_SI[ZOMBIECLASS_SPITTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_2", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_SMOKER];
    if (max>0 && costs_SI[ZOMBIECLASS_SMOKER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_SMOKER], live_zombie_arr[ZOMBIECLASS_SMOKER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Smoker", zm_language, costs_SI[ZOMBIECLASS_SMOKER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_3", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_HUNTER];
    if (max>0 && costs_SI[ZOMBIECLASS_HUNTER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_HUNTER], live_zombie_arr[ZOMBIECLASS_HUNTER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Hunter", zm_language, costs_SI[ZOMBIECLASS_HUNTER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_4", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_JOCKEY];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_JOCKEY]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_JOCKEY], live_zombie_arr[ZOMBIECLASS_JOCKEY]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Jockey", zm_language, costs_SI[ZOMBIECLASS_JOCKEY], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_5", buffer);
    
    max = max_zombie_arr[ZOMBIECLASS_CHARGER];
    if (l4d2_specials && costs_SI[ZOMBIECLASS_CHARGER]>=0)
    {
        occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_CHARGER], live_zombie_arr[ZOMBIECLASS_CHARGER]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Charger", zm_language, costs_SI[ZOMBIECLASS_CHARGER], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_6", buffer);
    
    if (g_bAllowFreeze && max_SI>0)
    {
        if (ZM_specials_frozen) Format(buffer, sizeof(buffer), "%T", "Unfreeze Specials", zm_language);
        else Format(buffer, sizeof(buffer), "%T", "Freeze Specials", zm_language);
    }
    else buffer = "-";
    AddMenuItem(menu_special, "item_7", buffer);

    Format(buffer, sizeof(buffer), "%T", "Control (USE)", zm_language);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_special, "item_8", buffer);
	
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
                case 6: set_specials_frozen(~ZM_specials_frozen);
                case 7: 
            	{
                    if (live_SI>0) ZMControlSI(zm_client,0);
                    else zm_menu_state=ZM_MENU_SPECIAL;
            	}
            	default: zm_menu_state=ZM_MENU_MAIN;
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
	delete menu_boss;
	menu_boss = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),boss_menu_Handler);
    apply_zm_menu_settings(menu_boss);
	
	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Boss", zm_language);
	menu_boss.SetTitle(buffer);
    
    if (g_iCostWitchMoving>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Moving", zm_language, g_iCostWitchMoving);
    else buffer = "-";
    AddMenuItem(menu_boss, "item_1", buffer);
    
    if (g_iCostWitchStatic>=0 && max_zombie_arr[ZOMBIECLASS_WITCH]>0) Format(buffer, sizeof(buffer), "%T %d", "Witch Static", zm_language, g_iCostWitchStatic);
    else buffer = "-";
    AddMenuItem(menu_boss, "item_2", buffer);
    
    int max = max_zombie_arr[ZOMBIECLASS_TANK];
    if (max>0 && costs_SI[ZOMBIECLASS_TANK]>=0)
    {
        int occupied = get_occupied_units(max,available_zombie_arr[ZOMBIECLASS_TANK], live_zombie_arr[ZOMBIECLASS_TANK]);
        Format(buffer,sizeof(buffer),"%T %d %d/%d", "Tank", zm_language, costs_SI[ZOMBIECLASS_TANK], occupied, max);
    }
    else buffer = "-";
    AddMenuItem(menu_boss, "item_3", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"jimmy")!=0) buffer = "-";
    else if (jimmy_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Jimmy Gibbs Jr", zm_language,g_iCostUncommon);
    AddMenuItem(menu_boss, "item_4", buffer);
    
    if (valid_uncommon(g_sForceCommon) && strcmp(g_sForceCommon,"fallen")!=0) buffer = "-";
    else if (fallen_spawned || g_iCostUncommon<0 || max_zombie_arr[ZOMBIECLASS_COMMON]<=0) buffer = "-";
    else Format(buffer, sizeof(buffer), "%T %d", "Fallen Survivor", zm_language,g_iCostUncommon);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_boss, "item_5", buffer);
	
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
            	default: zm_menu_state=ZM_MENU_MAIN;
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

// TRAPS MENU
void create_traps_menu()
{
	if (DEBUG) LogMessage("[zm] create_traps_menu");
	delete menu_traps;
	menu_traps = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),traps_menu_Handler);
    apply_zm_menu_settings(menu_traps);

	int zm_language = LANG_SERVER;
	if (IsValidClientZM()) zm_language = zm_client;
	char buffer[64];

	Format(buffer, sizeof(buffer), "%T", "Traps", zm_language);
	menu_traps.SetTitle(buffer);

	// Row 0: Panic door
	if (g_iCostTrapDoor>=0 && g_iMaxTrapDoor>0)
		Format(buffer, sizeof(buffer), "%T %d %d/%d", "Trap Panic Door", zm_language, g_iCostTrapDoor, Trap_CountActive(ZM_TRAP_TYPE_DOOR), g_iMaxTrapDoor);
	else buffer = "-";
	AddMenuItem(menu_traps, "item_1", buffer);

	// Row 1: Alarm car
	if (g_iCostTrapCar>=0 && g_iMaxTrapCar>0)
		Format(buffer, sizeof(buffer), "%T %d %d/%d", "Trap Alarm Car", zm_language, g_iCostTrapCar, Trap_CountActive(ZM_TRAP_TYPE_CAR), g_iMaxTrapCar);
	else buffer = "-";
	AddMenuItem(menu_traps, "item_2", buffer);

	if (g_iCostTrapTornado>=0 && g_iMaxTrapTornado>0)
		Format(buffer, sizeof(buffer), "%T %d %d/%d", "Trap Tornado", zm_language, g_iCostTrapTornado, Trap_CountActive(ZM_TRAP_TYPE_TORNADO), g_iMaxTrapTornado);
	else buffer = "-";
    buffer_add_rawline(buffer);
	AddMenuItem(menu_traps, "item_3", buffer);

	if (zm_menu_state == ZM_MENU_TRAPS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_TRAPS);
}
int traps_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: TrapDoor_BeginArm();
            	case 1: TrapCar_BeginArm();
            	case 2: TrapTornado_BeginArm();
            	default: zm_menu_state=ZM_MENU_MAIN;
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
	delete menu_cleanup;
	menu_cleanup = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),cleanup_menu_Handler);
    apply_zm_menu_settings(menu_cleanup);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Cleanup", zm_language);
	menu_cleanup.SetTitle(buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Target", zm_language);
    AddMenuItem(menu_cleanup, "item_1", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Commons", zm_language);
    AddMenuItem(menu_cleanup, "item_2", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Specials", zm_language);
    AddMenuItem(menu_cleanup, "item_3", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete Witches", zm_language);
    AddMenuItem(menu_cleanup, "item_4", buffer);
    
    Format(buffer, sizeof(buffer), "%T", "Delete ALL", zm_language);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_cleanup, "item_5", buffer);
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
            	default: zm_menu_state=ZM_MENU_MAIN;
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
	delete menu_other;
	menu_other = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),other_menu_Handler);
    apply_zm_menu_settings(menu_other);
	
	int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    char buffer[64]; 
	
	Format(buffer, sizeof(buffer), "%T", "Other", zm_language);
	menu_other.SetTitle(buffer);
    
    if (!L4D_IsSurvivalMode() && zm_stage<ZM_STARTED)
    {
        Format(buffer, sizeof(buffer), "%T", "Start Round", zm_language);
    }
    else buffer = "-";
    AddMenuItem(menu_other, "item_1", buffer);
    
    if (g_bGrid)
    {
        switch (g_iSpawnerMode)
        {
            case 1: Format(buffer, sizeof(buffer), "Spawner: Default+Grid");
            case 2: Format(buffer, sizeof(buffer), "Spawner: Grid");
            default: Format(buffer, sizeof(buffer), "Spawner: Default");
        }
    }
    else buffer = "-";
    AddMenuItem(menu_other, "item_2", buffer);

    Format(buffer, sizeof(buffer), "%T", "Teleport", zm_language);
    AddMenuItem(menu_other, "item_3", buffer);

    if (GetFeatureStatus(FeatureType_Native,"L4D_Path_To_Goal")==FeatureStatus_Available)
    {
        if (zm_draw_path) Format(buffer, sizeof(buffer), "PTG ON");
        else Format(buffer, sizeof(buffer), "PTG OFF");
    }
    else Format(buffer, sizeof(buffer), "-");
    AddMenuItem(menu_other, "item_4", buffer);

    Format(buffer, sizeof(buffer), "%T", "Give Up", zm_language);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_other, "item_5", buffer);
	
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
            	}
            	case 1:
            	{
            	    // Toggle spawner display mode
            	    int newMode;
            	    if (g_bGrid)
            	    {
                	    newMode = g_iSpawnerMode + 1;
                	    if (newMode>2) newMode = 0;
            	    }
            	    else newMode = 0;
            	    Spawner_OnDisabled(zm_client);
            	    g_iSpawnerMode = newMode;
            	    ZMPrefs_SaveSpawnerMode(zm_client);
            	    Spawner_OnEnabled(zm_client);
            	    create_other_menu(); 
            	}
            	case 2: ZMTeleport(zm_client,0);
                case 3:
                {
                    zm_draw_path = !zm_draw_path;
                    ZMPrefs_SavePTG(zm_client);
                    if (GetFeatureStatus(FeatureType_Native,"L4D_Path_To_Goal")==FeatureStatus_Available)
                        create_other_menu();
                }
                case 4: {open_menu(zm_client, ZM_MENU_QUIT); return 0;}
                default: zm_menu_state=ZM_MENU_MAIN;
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

// QUIT MENU
void create_quit_menu()
{		
	if (DEBUG) LogMessage("[zm] create_quit_menu");
    if (!IsValidClientZM()) return;
	delete menu_quit;
	menu_quit = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),quit_menu_Handler);
    apply_zm_menu_settings(menu_quit);

    char buffer[64]; 
    Format(buffer, sizeof(buffer), "%t ?", "Give Up", zm_client);
	menu_quit.SetTitle(buffer);

    Format(buffer,sizeof(buffer),"%T", "Yes", zm_client);
    AddMenuItem(menu_quit, "item_1", buffer);

    Format(buffer,sizeof(buffer),"%T", "No", zm_client);
    buffer_add_rawline(buffer);
    AddMenuItem(menu_quit, "item_2", buffer);
}
int quit_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
        	switch(param2)
        	{
            	case 0: {QuitZM(zm_client); return 0;}
            	default: zm_menu_state=ZM_MENU_MAIN;
        	}
        	RequestFrame(reopen_zm_menu,true);
        }
        case MenuAction_Cancel:
        {
           if (param1==zm_client)
           {
               if (param2==MenuCancel_Exit)
               {
                    zm_menu_state=ZM_MENU_MAIN;
                    RequestFrame(reopen_zm_menu,true);
               }
               else RequestFrame(reopen_zm_menu,false);
           }
        }
    }
	return 0;
}

// ITEMS MENU
void create_items_menu()
{
    delete menu_items;
    //LogMessage("create_items_menu");
    count_survivor_items();
    menu_items = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),items_menu_Handler);
    apply_zm_menu_settings(menu_items);

    int zm_language = LANG_SERVER;
    if (IsValidClientZM()) zm_language = zm_client;
    
    menu_items.SetTitle("%t: %d", "Survivors", g_iAliveSurvivors, zm_language);

    char buffer[64]; 
    
    if (g_iMolotov>0) Format(buffer, sizeof(buffer), "%t: %d", "Molotov", g_iMolotov, zm_language);
    else buffer = "";
    menu_items.AddItem("item_1",buffer);

    if (g_iPipeBomb>0) Format(buffer, sizeof(buffer), "%t: %d", "Pipe Bomb", g_iPipeBomb, zm_language);
    else buffer = "";
    menu_items.AddItem("item_2",buffer);

    if (g_iBileJar>0) Format(buffer, sizeof(buffer), "%t: %d", "Bile Jar", g_iBileJar, zm_language);
    else buffer = "";
    menu_items.AddItem("item_3",buffer);

    if (g_iMedkit>0) Format(buffer, sizeof(buffer), "%t: %d", "Medkit", g_iMedkit, zm_language);
    else buffer = "";
    menu_items.AddItem("item_4",buffer);

    if (g_iDefib>0) Format(buffer, sizeof(buffer), "%t: %d", "Defib", g_iDefib, zm_language);
    else buffer = "";
    menu_items.AddItem("item_5",buffer);

    if (g_iIncendiary>0) Format(buffer, sizeof(buffer), "%t: %d", "Incendiary", g_iIncendiary, zm_language);
    else buffer = "";
    menu_items.AddItem("item_6",buffer);

    if (g_iExplosive>0) Format(buffer, sizeof(buffer), "%t: %d", "Explosive", g_iExplosive, zm_language);
    else buffer = "";
    menu_items.AddItem("item_7",buffer);

    if (g_iPills>0) Format(buffer, sizeof(buffer), "%t: %d", "Pills", g_iPills, zm_language);
    else buffer = "";
    menu_items.AddItem("item_8",buffer);

    if (g_iAdrenaline>0) Format(buffer, sizeof(buffer), "%t: %d", "Adrenaline", g_iAdrenaline, zm_language);
    else buffer = "";
    buffer_add_rawline(buffer);
    menu_items.AddItem("item_9",buffer);

    if (zm_menu_state == ZM_MENU_ITEMS && IsValidClientZM()) open_menu(zm_client,ZM_MENU_ITEMS);
}
int items_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param1!=zm_client || zm_stage>=ZM_END) return 0;
            zm_menu_state=ZM_MENU_MAIN;
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
    create_traps_menu();
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
    menu.ExitButton = false;
    AddMenuItem(menu, "yes", "Yes");
    AddMenuItem(menu, "no", "No");
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
    else if (strcmp(type,"items")==0) MENU = ZM_MENU_ITEMS;
    else if (strcmp(type,"traps")==0) MENU = ZM_MENU_TRAPS;
	else if (strcmp(type,"close")==0) MENU = ZM_MENU_CLOSED;
	else MENU = ZM_MENU_MAIN;
    open_menu(zm_client,MENU);
    return Plugin_Continue;
}