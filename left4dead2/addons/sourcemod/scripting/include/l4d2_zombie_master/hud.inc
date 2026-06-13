///////////////////////////////////////
#if defined _zm_hud_included
 #endinput
#endif
#define _zm_hud_included
///////////////////////////////////////

// To draw EMS HUD
void enable_challenge_mode()
{
    //GameRules_SetProp("m_bChallengeModeActive", 1);
    GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
    EMS_hud_ready = true;
}

char HintFormattedString[128];
void update_hint(const char[] myString, any ...)
{
	if (!IsValidClientZM()) return;
	VFormat(HintFormattedString,128,myString,2);
    FormatEx(ZM_hint,sizeof(ZM_hint),"%s",HintFormattedString);
    update_EMS_HUD();
    active_looktarget = false;
}

char g_sHUD_Text[512];
char g_sHUD_TextArray[4][128];
char g_sBuffer[128];
char g_sSpaces[128] = "                                                                                                                               ";
char g_sData_HUD_ZM_Text[128];
char g_sData_HUD_TIMER_Text[128];

void update_EMS_HUD(bool force = false, float delay = 0.1)
{
    if (!force && ems_hud_timer!=INVALID_HANDLE) return;
    if (delay<0.1) perform_HUD_update();
    else ems_hud_timer = CreateTimer(delay,perform_HUD_update);
}

Action perform_HUD_update(Handle timer = null)
{
    ems_hud_timer = INVALID_HANDLE;
    if (!EMS_hud_ready) return Plugin_Stop;
    
    if (DEBUG) LogMessage("[zm] perform_HUD_update");
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TICKER);
    if (!g_bCvarAllow || !clients_in_server || L4D_IsInIntro()>0 || zm_stage>=ZM_END || !L4D_HasMapStarted())
    {
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_TIMER);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM);
        GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, HUD_ZM_HINT);
        return Plugin_Stop;
    }

    char pad[128];
    if (g_bHudPerElement) pad[0] = '\0';
    else strcopy(pad, sizeof(pad), g_sSpaces);

    int HUD_TIMER_flags = HUD_FLAG_ALIGN_CENTER|HUD_FLAG_TEXT;
    int HUD_ZM_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT;
    int HUD_ZM_HINT_flags = HUD_FLAG_TEAM_INFECTED|HUD_FLAG_ALIGN_LEFT|HUD_FLAG_TEXT|HUD_FLAG_NOBG;
    
    float t_now = GetGameTime();
    int rows;
    float cols;
    
    if (IsValidClientZM() && zm_stage<ZM_END)
    {
        
        char panic_str[32];
        if (panic || ZM_finale_announced || (L4D_IsSurvivalMode() && zm_stage==ZM_STARTED) )
        {
            float panic_left;
            if (ZM_finale_announced || L4D_IsSurvivalMode()) panic_left = 0.0;
            else panic_left = g_fPanicDuration - (t_now - t_last_panic);
            if (panic_left<=0.0) Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON", zm_client);
            else
            {
                Format(panic_str, sizeof(panic_str), "%T\n", "PANIC ON time", zm_client, panic_left);
                if (panic_left<=5.0)
                {
                    HUD_ZM_flags |= HUD_FLAG_BLINK;
                    HUD_ZM_HINT_flags |= HUD_FLAG_BLINK;
                }
            }
        }
        else Format(panic_str, sizeof(panic_str), "");
        
        char bank_str[32];
        char common_str[32];
        char special_str[32];
        char witch_str[32];
        
        if (bank_rate>0.0) Format(bank_str, sizeof(bank_str), "%T %d (%.1f)", "Bank", zm_client, bank, bank_rate);
        else Format(bank_str, sizeof(bank_str), "%T %d", "Bank", zm_client, bank);
        
        Format(common_str, sizeof(common_str), "%T", "Common", zm_client);
        Format(special_str, sizeof(special_str), "%T", "Special", zm_client);
        Format(witch_str, sizeof(witch_str), "%T", "Witch", zm_client);
        
        // ZM INFO
        int occupied_SI = get_occupied_units(max_SI,available_SI,live_SI);
        int occupied_commons = get_occupied_units(max_zombie_arr[ZOMBIECLASS_COMMON],available_zombie_arr[ZOMBIECLASS_COMMON],live_zombie_arr[ZOMBIECLASS_COMMON]);
        int occupied_witches = get_occupied_units(max_zombie_arr[ZOMBIECLASS_WITCH],available_zombie_arr[ZOMBIECLASS_WITCH],live_zombie_arr[ZOMBIECLASS_WITCH]);
        FormatEx(g_sData_HUD_ZM_Text,sizeof(g_sData_HUD_ZM_Text),
                 "%s\n%s%s %d/%d\n%s %d/%d\n%s %d/%d",
                 bank_str,
                 panic_str,
                 common_str,occupied_commons,max_zombie_arr[ZOMBIECLASS_COMMON],
                 special_str,occupied_SI,max_SI,
                 witch_str,occupied_witches,max_zombie_arr[ZOMBIECLASS_WITCH]);
        
        TrimString(g_sData_HUD_ZM_Text);
        CountStringRowsCols(g_sData_HUD_ZM_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.008, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.1, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_ZM);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026*rows, HUD_ZM);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s %s", g_sData_HUD_ZM_Text, pad);
        g_sHUD_TextArray[HUD_ZM] = g_sBuffer;
        
        // ZM HINT
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.0, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.07, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.51, HUD_ZM_HINT);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_ZM_HINT);
        TrimString(ZM_hint);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n%s\n %s", ZM_hint, pad);
        g_sHUD_TextArray[HUD_ZM_HINT] = g_sBuffer;
        
    }
    else
    {
        HUD_ZM_flags = HUD_FLAG_NOTVISIBLE;
        HUD_ZM_HINT_flags = HUD_FLAG_NOTVISIBLE;
    }
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_flags, _, HUD_ZM);
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_ZM_HINT_flags, _, HUD_ZM_HINT);
    
    if (!IsValidClientZM())
    {
       
       if (IsValidClient(client_offer))
       {
           char name[MAX_NAME_LENGTH]; 
           GetClientName(client_offer,name,sizeof(name));
           int timeleft = RoundFloat(g_fFairQueueWait - (t_now - t_offer));
           if (timeleft<0) timeleft = 0;
           Format(g_sData_HUD_TIMER_Text,sizeof(g_sData_HUD_TIMER_Text),
           "%T", "Offered ZM Ticker", LANG_SERVER, name, timeleft);
       }
       else
       {
           if (autocommon_setting>0) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
           else Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "No ZM notify", LANG_SERVER);
       }
    }
    else
    {
        if (zm_stage>=ZM_STARTED || force_started || L4D_IsSurvivalMode()) HUD_TIMER_flags = HUD_FLAG_NOTVISIBLE;
        else
        {
            if (zm_can_start)
            {
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Survivors can leave", LANG_SERVER);
                HUD_TIMER_flags |= HUD_FLAG_BLINK;
            }
            else
            {
                
                float time1 = saferoom_cooldown - (t_now - t_last_join);
                float time2 = g_fPrepTimeZM - (t_now - t_zm_join);
                
                float t_biggest;
                if (time1>time2) t_biggest=time1;
                else t_biggest = time2;
                
                if (t_biggest<0.0) t_biggest = 0.0;
                if (t_biggest<=5.0) HUD_TIMER_flags |= HUD_FLAG_BLINK;
                
                Format(g_sData_HUD_TIMER_Text, sizeof(g_sData_HUD_TIMER_Text), "%T", "Round can start in", LANG_SERVER, RoundFloat(t_biggest));
            }
        }
    }
    
    GameRules_SetProp("m_iScriptedHUDFlags", HUD_TIMER_flags, _, HUD_TIMER);
    if (HUD_TIMER_flags!=HUD_FLAG_NOTVISIBLE)
    {
        
        CountStringRowsCols(g_sData_HUD_TIMER_Text,rows,cols);
        
        GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.35, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.14, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0099*cols, HUD_TIMER);
        GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.026, HUD_TIMER);
        g_sBuffer = "\0";
        FormatEx(g_sBuffer, sizeof(g_sBuffer), "\n  %s\n %s", g_sData_HUD_TIMER_Text, pad);
        g_sHUD_TextArray[HUD_TIMER] = g_sBuffer;
    }
    
    // TICKER - PLACEHOLDER
    g_sBuffer = "\0";
    FormatEx(g_sBuffer, sizeof(g_sBuffer), "%s%s", pad, pad);
    g_sHUD_TextArray[HUD_TICKER] = g_sBuffer;

    if (g_bHudPerElement)
    {
        // Each slot to its own array element: no padding, no overflow, only the
        // real (changed) text is networked.
        for (int i = 0; i < sizeof(g_sHUD_TextArray); i++)
            GameRules_SetPropString("m_szScriptedHUDStringSet", g_sHUD_TextArray[i], true, i);
    }
    else
    {
        // Legacy: one element-0 write of the padded blob, relying on overflow into
        // the contiguous slot buffers.
        ImplodeStrings(g_sHUD_TextArray, sizeof(g_sHUD_TextArray), " ", g_sHUD_Text, sizeof(g_sHUD_Text));
        GameRules_SetPropString("m_szScriptedHUDStringSet", g_sHUD_Text);
    }

    return Plugin_Stop;
    
}

// Try to optimize the size of the ZM info box.
stock void CountStringRowsCols(const char[] str, int &rows, float &cols)
{
    int i, count = 0;
    float current, longest = 0.0;
    char c_temp;
    while (str[i] != 0)
    {
        c_temp = str[i];
        switch (c_temp)
        {
            case ' ': current += 0.75;
            case '1': current += 0.5;
            case 'i': current += 0.5;
            case 'l': current += 0.5;
            case 'f': current += 0.5;
            case 'j': current += 0.5;
            case 't': current += 0.5;
            case '|': current += 0.5;
            case '`': current += 0.5;
            case '!': current += 0.5;
            case '.': current += 0.5;
            case ',': current += 0.5;
            case '(': current += 0.5;
            case ')': current += 0.5;
            case '\n':
            {
                count++;
                if (current>longest) longest = current;
                current = 0.0;
            }
            default: current += 1.0;
        }
        i+=1;
    }
    rows = count + 1;
    if (current>longest) longest = current;
    cols = longest + 0.1;
}

// Hide hit messages for ZM
Action OnPZDmgMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    if (!g_bCvarAllow || !IsValidClientZM()) return Plugin_Continue;
    BfReadByte(msg);
    int userid = BfReadShort(msg);
    if (zm_client_userid==userid) return Plugin_Handled;
    return Plugin_Continue;
} 