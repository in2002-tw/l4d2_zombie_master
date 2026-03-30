///////////////////////////////////////
#if defined _zm_fair_queue_included
 #endinput
#endif
#define _zm_fair_queue_included
///////////////////////////////////////

void create_client_data(int client=-1, char auth[65] = "", int count=0)
{
    if (DEBUG) LogMessage("[zm] create_client_data");
    if ( client>0 && (IsFakeClient(client) || !get_client_auth(client,auth)) ) return;
    if (g_Steam.ContainsKey(auth)) return;
    zm_data cell;
    cell.rounds = count;
    cell.last_roundcount = -1;
    cell.offered = false;
    g_Steam.SetArray(auth,cell,3,true);
    if (DEBUG) LogMessage("New data entry %s %d", auth, count);
}

bool get_zm_data(zm_data cell, int client=-1, char auth[65] = "")
{
    if (DEBUG) LogMessage("[zm] get_zm_data");
    if (client>0 && !get_client_auth(client,auth)) return false;
    if (!g_Steam.ContainsKey(auth) && IsValidClient(client) && !IsFakeClient(client))
        create_client_data(client,auth);
    if (!g_Steam.GetArray(auth,cell,3)) return false;
    return true;
}

int get_rounds(int client=-1, char auth[65] = "")
{
    zm_data cell;
    if (!get_zm_data(cell,client,auth)) return 0;
    return cell.rounds;
}

void increase_playcount(int client=-1, char auth[65] = "")
{
    zm_data cell;
    if (!get_zm_data(cell,client,auth)) return;
    cell.rounds += 1;
    cell.last_roundcount = roundcount;
    cell.offered = true;
    g_Steam.SetArray(auth,cell,3,true);
    if (DEBUG) LogMessage("[zm] Playcount increased %s %d (%d)", auth, cell.rounds, cell.last_roundcount);
    playcount_increased = true;
}

void reset_fair_queue()
{
    fq_timer = INVALID_HANDLE;
    if (!g_bFairQueue)
    {
        fair_exhausted = true;
        return;
    }
    
    if (DEBUG) LogMessage("[zm] reset_fair_queue");
    
    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        clients_offered[i] = false;
    }
    
    fair_exhausted = false;
    t_offer = 0.0;
    client_offer = -1;
    roundcount_offer = -1;
    StringMapSnapshot snapshot = g_Steam.Snapshot();
    char auth[128];
    int maxKeys = snapshot.Length;
    zm_data cell;
    for (int i = 0; i < maxKeys; i++)
    {
        snapshot.GetKey(i,auth,sizeof(auth));
        if (!g_Steam.GetArray(auth,cell,3)) continue;
        if (cell.offered)
        {
            cell.offered = false;
            g_Steam.SetArray(auth,cell,3,true);
        }
    }
    delete snapshot;
}

Action fair_queue_update(Handle timer = null)
{
    
    fq_timer = INVALID_HANDLE;
    
    if (!g_bFairQueue || IsValidClientZM() || zm_stage>=ZM_STARTED || !clients_in_server || !first_active)
    {
        client_offer = -1;
        return Plugin_Stop;
    }
    
    if (DEBUG) LogMessage("[zm] fair_queue_update");
    
    float t_now = GetGameTime();

    if (IsValidClient(client_offer) && !IsFakeClient(client_offer))
    {
        if (L4D_IsInIntro()>0) t_offer = t_now;
        float t_left = g_fFairQueueWait - (t_now - t_offer);
        if (t_left<=0.0)
        {
            pass_ZM(client_offer);
            return Plugin_Stop;
        }
        else
        {
            create_offer_menu(client_offer);
    	    fq_timer = CreateTimer(1.0,fair_queue_update);
        }
    }
    else client_offer = -1;
    
    if (IsValidClient(client_offer)) return Plugin_Stop;
    if (L4D_IsInIntro()>0) return Plugin_Stop;
    
    // See if anybody can be offered
    int ingame,total;
    int floor = roundcount;
    ArrayList candidates = new ArrayList();
    zm_data cell;
    for (int i = 1; i <= MaxClients; i++)
    {
  		if (!IsClientConnected(i)) continue;
  		if (IsFakeClient(i)) continue;
  		if (IsClientTimingOut(i)) continue;
  		total += 1;
  		if (IsClientInGame(i)) ingame += 1;
  		else
  		{
      		float dt = t_now - clients_t_join[i];
      		// Respecting connecting clients
      		// But ignore clients who just started connecting, and those stuck connecting.
      		if (dt<=5.0 || dt>=30.0) continue;
  		}
  		
  		// Steam auth frequently fails because Valve abandoned this game, so, have to resort to this.
  		if (get_zm_data(cell,i))
  		{
  		  	if (!cell.offered)
        	{
            	candidates.Push(i);
            	if (cell.last_roundcount<floor) floor = cell.last_roundcount;
        	}
  		}
  		else if (!clients_offered[i]) candidates.Push(i);
    }
    
    if (total<=0 || ingame<=0 || candidates.Length<=0)
    {
        if (!fair_exhausted && total>0 && ingame>0 && candidates.Length<=0 && (1.0*ingame/total)>0.5)
        {
            LogMessage("[zm] Fair queue exhausted! JoinZM restrictions OFF.");
            fair_exhausted = true;
        }
        delete candidates;
        return Plugin_Stop;
    }
    
    roundcount_offer = floor;
    
    // Pick random
    if (candidates.Length==1) client_offer = candidates.Get(0);
    else
    {
        ArrayList pool = new ArrayList();
        int client;
        for (int i = 0; i < candidates.Length; i++)
        {
      		client = candidates.Get(i);
      		if (get_zm_data(cell,client))
      		{
          		if (cell.last_roundcount<=floor) pool.Push(client);
      		}
      		else if (roundcount<=floor) pool.Push(client);
        }
        
        if (pool.Length==1) client_offer = pool.Get(0);
        else
        {
            int random_index = GetRandomInt(0,pool.Length-1);
            client_offer = pool.Get(random_index);
        }
        
        delete pool;
    }
    
    delete candidates;
    if (!IsClientInGame(client_offer) || !clients_active[client_offer] || GetEntProp(client_offer,Prop_Send,"m_fFlags")&FL_FROZEN)
    {
        client_offer = -1;
        fq_timer = CreateTimer(1.0,fair_queue_update);
    }
    else if (IsValidClient(client_offer))
    {
        t_offer = t_now;
        EmitSoundToClient(client_offer,SOUND_OFFER);
        update_EMS_HUD(true,0.0);
        fq_timer = CreateTimer(0.1,fair_queue_update);
    }
    
    return Plugin_Stop;  
    
}

void pass_ZM(int client=-1, char auth[65] = "")
{
    if (DEBUG) LogMessage("[zm] pass_ZM");
    zm_data cell;
    if (IsValidClient(client))
    {
        if (get_zm_data(cell,client,auth))
        {
            cell.offered = true;
            g_Steam.SetArray(auth,cell,3,true);
        }
        clients_offered[client] = true;
        if (client==client_offer) client_offer = -1;
    }
    fair_queue_update(null);
}

// ZM OFFER MENU
Menu menu_offer;
void create_offer_menu(int client)
{		
	if (!IsValidClient(client)) return;
	if (DEBUG) LogMessage("[zm] create_offer_menu");
	if (menu_offer!=INVALID_HANDLE) CloseHandle(menu_offer);
	menu_offer = CreateMenuEx(GetMenuStyleHandle(MenuStyle_Radio),offer_menu_Handler);
	char buffer[64]; 
    Format(buffer, sizeof(buffer), "%T", "Offer ZM", client);
	menu_offer.SetTitle(buffer); 
    
    Format(buffer,sizeof(buffer),"%T", "Yes", client);
    AddMenuItem(menu_offer, "0", buffer);
    Format(buffer,sizeof(buffer),"%T", "No", client);
    AddMenuItem(menu_offer, "1", buffer);
    
	menu_offer.ExitButton = false;
	SetMenuOptionFlags(menu_offer,MENUFLAG_NO_SOUND);
	menu_offer.Display(client,RoundFloat(g_fFairQueueWait));
}
int offer_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action) 
    {
        case MenuAction_Select:
        {
        	if (IsValidClientZM()) return 0;
        	switch(param2)
        	{
            	case 0: JoinZM_command(param1,0);
            	case 1: {pass_ZM(param1); close_menus(param1);}
        	}
        	return 0;
        }
        case MenuAction_Cancel:
        {
           if (menu_offer && param1==client_offer && IsValidClient(client_offer) && param2==MenuCancel_Exit)
               menu_offer.Display(client_offer,RoundFloat(g_fFairQueueWait));
        }
    }
	return 0;
}

stock bool get_client_auth(int client, char auth[65])
{
    //if (!IsValidClient(client)) return false;
    if (client<=0 || client>MaxClients) return false;
    if (!GetClientAuthId(client,AuthId_Engine,auth,sizeof(auth))) return false;
    return true;
}

Action set_client_active(Handle timer, int client)
{
    if (!IsValidClient(client)) return Plugin_Stop;
    if (clients_active[client]) return Plugin_Stop;
    if (DEBUG) LogMessage("[zm] set_client_active %d", client);
    clients_active[client] = true;
    if (zm_stage<ZM_STARTED && fq_timer==null) fq_timer = CreateTimer(0.1,fair_queue_update);
    return Plugin_Stop;
}