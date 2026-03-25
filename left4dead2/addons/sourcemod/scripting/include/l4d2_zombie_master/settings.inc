///////////////////////////////////////
#if defined _zm_settings_included
 #endinput
#endif
#define _zm_settings_included
///////////////////////////////////////

// Re-run this if player number has changed
void SetCvarsZM()
{
   if (!g_bCvarAllow) return;
   
   if (DEBUG) LogMessage("[zm] SetCvarsZM");
   
   SetConVarInt(FindConVar("director_tank_lottery_selection_time"), 9999);
   SetConVarInt(FindConVar("tank_stuck_time_suicide"), 0);
   SetConVarInt(FindConVar("z_frustration"), 0);
   SetConVarInt(FindConVar("tank_stuck_failsafe"), 0);
   
   SetConVarInt(FindConVar("z_discard_min_range"), 9999999);
   SetConVarInt(FindConVar("z_discard_range"), 9999999);
   SetConVarInt(FindConVar("z_no_cull"), 1);
   SetConVarInt(FindConVar("z_minion_limit"), 0);
   SetConVarInt(FindConVar("director_no_bosses"), 1);
   SetConVarInt(FindConVar("director_no_specials"), 1);
   SetConVarInt(FindConVar("director_allow_infected_bots"), 0);
   
   SetConVarInt(FindConVar("sb_all_bot_game"),1);
   SetConVarInt(FindConVar("allow_all_bot_survivor_team"),1);
   
   SetConVarInt(FindConVar("z_large_volume_mob_too_far_xy"),50000);
   SetConVarInt(FindConVar("z_large_volume_mob_too_far_z"),50000);
   
   int d;
   
   // Check if Specials need updating
   int new_max_SI;
   if (g_iMaxSI<0)
   {
       new_max_SI = g_iAliveSurvivors+g_iMaxSI+1;
       if (new_max_SI<=0) new_max_SI = 1;
   }
   else new_max_SI = g_iMaxSI;
   if (new_max_SI > SI_cap) new_max_SI = SI_cap;
   if (new_max_SI!=max_SI)
   {
       available_SI += (new_max_SI-max_SI);
       max_SI = new_max_SI;
       if (available_SI>max_SI) available_SI = max_SI;
       else if (available_SI<0) available_SI = 0;
       create_main_menu();
   }
   int max_unique_SI = get_max_unique_SI_override();
   int length = sizeof(available_zombie_arr);
   int temp_lim, changes = 0;
   for(int i = 0; i < length; i++)
   {
         if (i==ZOMBIECLASS_COMMON || i==ZOMBIECLASS_WITCH) continue;
         if (costs_SI[i]<0) temp_lim = 0;
         else temp_lim = max_unique_SI; 
         if (change_special_max(i,temp_lim,false)>0)
         {
              if (i==ZOMBIECLASS_TANK) create_boss_menu();
              else changes += 1;
         }
         else if (available_zombie_arr[i]>max_zombie_arr[i])
         {
             available_zombie_arr[i] = max_zombie_arr[i];
         }
   }
   if (changes>0) create_special_menu();
   
   // Sanity check available_SI
   int occupied_SI_total = 0;
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_SMOKER]-available_zombie_arr[ZOMBIECLASS_SMOKER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_BOOMER]-available_zombie_arr[ZOMBIECLASS_BOOMER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_HUNTER]-available_zombie_arr[ZOMBIECLASS_HUNTER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_SPITTER]-available_zombie_arr[ZOMBIECLASS_SPITTER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_JOCKEY]-available_zombie_arr[ZOMBIECLASS_JOCKEY];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_CHARGER]-available_zombie_arr[ZOMBIECLASS_CHARGER];
   occupied_SI_total += max_zombie_arr[ZOMBIECLASS_TANK]-available_zombie_arr[ZOMBIECLASS_TANK];
   d = max_SI-available_SI;
   available_SI += (d-occupied_SI_total);
   if (available_SI>max_SI) available_SI = max_SI;
   else if (available_SI<0) available_SI = 0;
   
   // Check if Witches need updating
   int new_max_witches;
   if (g_iMaxWitches<0) new_max_witches = RoundToCeil(g_iAliveSurvivors/2.0);
   else new_max_witches = g_iMaxWitches;
   if (new_max_witches!=max_zombie_arr[ZOMBIECLASS_WITCH])
   {
      d = new_max_witches - max_zombie_arr[ZOMBIECLASS_WITCH];
      max_zombie_arr[ZOMBIECLASS_WITCH] = new_max_witches;
      add_available_zombie(ZOMBIECLASS_WITCH,d);
   }
   else if (available_zombie_arr[ZOMBIECLASS_WITCH]>max_zombie_arr[ZOMBIECLASS_WITCH])
       available_zombie_arr[ZOMBIECLASS_WITCH] = max_zombie_arr[ZOMBIECLASS_WITCH];
   
   // Include all SI on field + spectating ZM
   SetConVarInt(FindConVar("survival_max_specials"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_max_player_zombies"), MAXPLAYERS);
   
   SetConVarInt(FindConVar("survival_max_smokers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_boomers"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_hunters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_spitters"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_jockeys"), MAXPLAYERS);
   SetConVarInt(FindConVar("survival_max_chargers"), MAXPLAYERS);
   
   SetConVarInt(FindConVar("z_smoker_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_boomer_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_hunter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_spitter_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_jockey_limit"), MAXPLAYERS);
   SetConVarInt(FindConVar("z_charger_limit"), MAXPLAYERS);
   
   if (infectedbots_enable) SetConVarInt(infectedbots_enable, 0);
   if (jukebox_horde) SetConVarInt(jukebox_horde, 0);
}

Action Timer_load_zm_global_settings(Handle timer)
{
    char command[PLATFORM_MAX_PATH];
    Format(command, sizeof(command), "exec sourcemod/%s", CONFIG_FILENAME);
    ServerCommand(command);
    create_menu_gamemode();
    return Plugin_Stop;
}

ArrayList gamemodes;
char new_gamemode[64] = "";
void load_gamemodes()
{    
    gamemodes = new ArrayList(64);
    gamemodes.PushString("zm_default");
    
    char path[PLATFORM_MAX_PATH] = "cfg/sourcemod/l4d2_zombie_master/";
    if (!DirExists(path)) return;
    DirectoryListing dir = OpenDirectory(path);
    if (dir==null) return;
    char filename[64];
    while (dir.GetNext(filename, sizeof(filename)))
    {
        TrimString(filename);
        if (strcmp(filename,"zm_default.cfg")==0) continue;
        if (StrContains(filename,".cfg",false)==-1) continue;
        ReplaceString(filename,sizeof(filename),".cfg","",false);
        TrimString(filename);
        gamemodes.PushString(filename);
    }
    delete dir;
    LogMessage("[zm] Loaded %d gamemodes.", gamemodes.Length);
}

// GAMEMODE MENU
Menu menu_gamemode;
void create_menu_gamemode()
{		
	if (DEBUG) LogMessage("[zm] create_menu_gamemode");
	if (menu_gamemode!=INVALID_HANDLE) CloseHandle(menu_gamemode);
	menu_gamemode = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),gamemode_menu_Handler);
	char buffer1[8];
	char buffer2[64];
	Format(buffer2,sizeof(buffer2),"zm_gamemode %s",g_sZMGamemode);
	menu_gamemode.SetTitle(buffer2);
	for(int i = 0; i<gamemodes.Length; i++)
	{
    	IntToString(i,buffer1,sizeof(buffer1));
    	gamemodes.GetString(i,buffer2,sizeof(buffer2));
    	TrimString(buffer1); TrimString(buffer2);
    	menu_gamemode.AddItem(buffer1,buffer2);
	}
	menu_gamemode.ExitButton = true;
}
int gamemode_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (param2<0 || param2>=gamemodes.Length) return 0;
        	gamemodes.GetString(param2,new_gamemode,sizeof(new_gamemode));
        	if (CheckCommandAccess(param1,"is_a_sm_admin",ADMFLAG_GENERIC,true))
        	{
            	SetConVarString(g_hZMGamemode,new_gamemode);
            	ZM_Gamemode_Command(param1,0);
        	}
        	else create_gamemode_vote();
        }
    }
	return 0;
}

int Handle_VoteGamemode(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_VoteEnd)
    {
        if (param1 == 0) SetConVarString(g_hZMGamemode,new_gamemode);
    }
    return 0;
}
void create_gamemode_vote()
{
    if (IsVoteInProgress()) return;
    Menu menu = new Menu(Handle_VoteGamemode);
    char buffer[128];
    Format(buffer,sizeof(buffer), "zm_gamemode -> %s?", new_gamemode);
    menu.SetTitle(buffer);
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}

void random_gamemode()
{
    if (gamemodes.Length<=0) return;
    if (gamemodes.Length==1) gamemodes.GetString(0,new_gamemode,sizeof(new_gamemode));
    else
    {
        gamemodes.GetString(GetRandomInt(0,gamemodes.Length-1),new_gamemode,sizeof(new_gamemode));
        if (strcmp(new_gamemode,g_sZMGamemode)==0) gamemodes.GetString(GetRandomInt(0,gamemodes.Length-1),new_gamemode,sizeof(new_gamemode));
    }
    SetConVarString(g_hZMGamemode,new_gamemode);
    LogMessage("[zm] Randomizer gamemode: %s", new_gamemode);
}

Action ZM_Gamemode_Command(int client, int args)
{
    if (!IsValidClient(client) || menu_gamemode==null) return Plugin_Continue;
    menu_gamemode.Display(client,MENU_TIME_FOREVER);
    return Plugin_Continue;
}

void next_randomizer_setting()
{
    int next = g_hRandomizer.IntValue + 1;
    if (next>2) next = 0;
    SetConVarInt(g_hRandomizer,next);
}

void next_autocommon_setting()
{
    autocommon_setting += 1;
    if (autocommon_setting>AUTOCOMMON_ALWAYS) autocommon_setting = 0;
    create_autocommon_menu();
}

void next_autocommon_num()
{
    if (autocommon_num>10) autocommon_num -= 10;
    else autocommon_num = 30;
    create_autocommon_menu();
}

Action zm_autocommon_mode(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (args>0)
    {
        char type[32];
        GetCmdArg(1, type, sizeof(type));
        TrimString(type);
        if (strcmp(type,"always",false)==0) autocommon_setting = AUTOCOMMON_ALWAYS;
        else if (strcmp(type,"panic",false)==0) autocommon_setting = AUTOCOMMON_PANIC;
        else autocommon_setting = AUTOCOMMON_OFF;
        create_autocommon_menu();
    }
    else next_autocommon_setting();
    switch (autocommon_setting)
    {
        case AUTOCOMMON_ALWAYS: ReplyToCommand(client,"zm_autocommon_mode always");
        case AUTOCOMMON_PANIC: ReplyToCommand(client,"zm_autocommon_mode panic");
        default: ReplyToCommand(client,"zm_autocommon_mode off");
    }
    return Plugin_Continue;
}

Action zm_autocommon_max(int client, int args)
{
    if (!g_bCvarAllow || !IsValidClientZM() || zm_client!=client) return Plugin_Continue;
    if (args>0)
    {
        int new_num = GetCmdArgInt(1);
        if (new_num<1) return Plugin_Continue;
        if (new_num>max_zombie_arr[ZOMBIECLASS_COMMON]) new_num = max_zombie_arr[ZOMBIECLASS_COMMON];
        if (autocommon_num!=new_num)
        {
            autocommon_num = new_num;
            create_autocommon_menu();
        }
   	}
   	else next_autocommon_num();
   	ReplyToCommand(client,"zm_autocommon_max %d", autocommon_num);
   	return Plugin_Continue;
}

void load_zm_gamemode()
{
    g_hZMGamemode.GetString(g_sZMGamemode, sizeof(g_sZMGamemode));
    TrimString(g_sZMGamemode);
    if (g_sZMGamemode[0]==0) g_sZMGamemode = "zm_default";
    else if (strcmp(g_sZMGamemode,"random",false)==0)
    {
        random_gamemode();
        return;
    }
    char command[PLATFORM_MAX_PATH];
    Format(command, sizeof(command), "exec sourcemod/l4d2_zombie_master/%s", g_sZMGamemode);
    ServerCommand(command);
    if (clown_world_enable && strcmp(g_sZMGamemode,"zm_clowns",false)==0) SetConVarInt(clown_world_enable, 1);
}

void ResetCvars()
{
    if (DEBUG) LogMessage("[zm] ResetCvars");
    
    ResetConVar(FindConVar("director_tank_lottery_selection_time"), true, true);
    ResetConVar(FindConVar("tank_stuck_time_suicide"), true, true);
    ResetConVar(FindConVar("z_frustration"), true, true);
    ResetConVar(FindConVar("tank_stuck_failsafe"), true, true);
    
    ResetConVar(FindConVar("z_no_cull"), true, true);
	ResetConVar(FindConVar("z_minion_limit"), true, true);
	ResetConVar(FindConVar("director_no_bosses"), true, true);
	ResetConVar(FindConVar("director_no_specials"), true, true);
	ResetConVar(FindConVar("director_panic_forever"), true, true);
	
	ResetConVar(FindConVar("z_discard_range"), true, true);
	ResetConVar(FindConVar("z_discard_min_range"), true, true);

	ResetConVar(FindConVar("survival_max_smokers"), true, true);
	ResetConVar(FindConVar("survival_max_boomers"), true, true);
	ResetConVar(FindConVar("survival_max_hunters"), true, true);
	ResetConVar(FindConVar("survival_max_spitters"), true, true);
	ResetConVar(FindConVar("survival_max_jockeys"), true, true);
	ResetConVar(FindConVar("survival_max_chargers"), true, true);
	ResetConVar(FindConVar("survival_max_specials"), true, true);
	ResetConVar(FindConVar("survival_special_limit_increase"), true, true);
	ResetConVar(FindConVar("survival_special_spawn_interval"), true, true);
	ResetConVar(FindConVar("survival_special_stage_interval"), true, true);
	ResetConVar(FindConVar("z_smoker_limit"), true, true);
	ResetConVar(FindConVar("z_boomer_limit"), true, true);
	ResetConVar(FindConVar("z_hunter_limit"), true, true);
	ResetConVar(FindConVar("z_spitter_limit"), true, true);
	ResetConVar(FindConVar("z_jockey_limit"), true, true);
	ResetConVar(FindConVar("z_charger_limit"), true, true);
	ResetConVar(FindConVar("director_allow_infected_bots"), true, true);
	ResetConVar(FindConVar("z_spawn_safety_range"), true, true);
	
	ResetConVar(FindConVar("z_max_player_zombies"), true,true);
	
	ResetConVar(FindConVar("z_large_volume_mob_too_far_xy"), true,true);
	ResetConVar(FindConVar("z_large_volume_mob_too_far_z"), true,true);
	
	// ask all plugins we are communicating with to reload their default values
	if (shoot_alert_enable && GetConVarInt(shoot_alert_enable)<=0) ServerCommand("sm plugins reload l4d2_shoot_alert_common");
	if (infectedbots_enable && GetConVarInt(infectedbots_enable)<=0) ServerCommand("sm plugins reload l4dinfectedbots");
	if (jukebox_horde && GetConVarInt(jukebox_horde)<=0) ServerCommand("sm plugins reload l4d2_jukebox_spawner");
	SetConVarInt(FindConVar("mp_restartgame"), 1);
}