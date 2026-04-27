///////////////////////////////////////
#if defined _zm_sdk_included
 #endinput
#endif
#define _zm_sdk_included
///////////////////////////////////////

Handle hCreateSmoker = null;
#define NAME_CreateSmoker "NextBotCreatePlayerBot<Smoker>"
#define NAME_CreateSmoker_L4D1 "reloffs_NextBotCreatePlayerBot<Smoker>"
Handle hCreateBoomer = null;
#define NAME_CreateBoomer "NextBotCreatePlayerBot<Boomer>"
#define NAME_CreateBoomer_L4D1 "reloffs_NextBotCreatePlayerBot<Boomer>"
Handle hCreateHunter = null;
#define NAME_CreateHunter "NextBotCreatePlayerBot<Hunter>"
#define NAME_CreateHunter_L4D1 "reloffs_NextBotCreatePlayerBot<Hunter>"
Handle hCreateSpitter = null;
#define NAME_CreateSpitter "NextBotCreatePlayerBot<Spitter>"
Handle hCreateJockey = null;
#define NAME_CreateJockey "NextBotCreatePlayerBot<Jockey>"
Handle hCreateCharger = null;
#define NAME_CreateCharger "NextBotCreatePlayerBot<Charger>"
Handle hCreateTank = null;
#define NAME_CreateTank "NextBotCreatePlayerBot<Tank>"
#define NAME_CreateTank_L4D1 "reloffs_NextBotCreatePlayerBot<Tank>"

//Handle hInfectedAttackSurvivorTeam = null;
//hTankEnterStasis, hTankLeaveStasis = null;

// https://github.com/Ilusion9/entityIO-sm
Handle g_DHook_AcceptInput;

// TerrorNavArea::IsPotentiallyVisibleToTeam(int) -> bool
Handle hNavIsPotentiallyVisibleToTeam;

// TerrorNavArea::IsCompletelyVisibleToTeam(int team) -> bool
Handle hNavIsCompletelyVisibleToTeam;

// TerrorNavArea::IsPotentiallyVisible(const TerrorNavArea*, bool) -> bool
Handle hNavIsPotentiallyVisible;

GameData hGameData;
//GameData hGameData_l4dhooks;
void GetGameData()
{
	hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	//hGameData_l4dhooks = LoadGameConfigFile("left4dhooks.l4d2");

	if( hGameData != null ) PrepSDKCall();
	else SetFailState("Unable to find l4d2_zombie_master.txt gamedata file.");

	delete hGameData;
	//delete hGameData_l4dhooks;
}



void PrepSDKCall()
{

	StartPrepSDKCall(SDKCall_Player);

	//find create bot signature
	Address replaceWithBot = GameConfGetAddress(hGameData, "NextBotCreatePlayerBot.jumptable");
	if (replaceWithBot != Address_Null && LoadFromAddress(replaceWithBot, NumberType_Int8) == 0x68) {
		// We're on L4D2 and linux
		PrepWindowsCreateBotCalls(replaceWithBot);
	}
	else
	{
		PrepL4D2CreateBotCalls();
		PrepL4D1CreateBotCalls();
	}

    //g_hDTR_InputKill = DynamicDetour.FromConf(hGameData, "l4d2_zombie_master::CBaseEntity::InputKill");
    //if (!g_hDTR_InputKill) LogMessage("[zm] Failed to create DynamicDetour InputKill");

    //g_hDTR_InputKillHierarchy = DynamicDetour.FromConf(hGameData, "l4d2_zombie_master::CBaseEntity::InputKillHierarchy");
    //if (!g_hDTR_InputKillHierarchy) LogMessage("[zm] Failed to create DynamicDetour InputKillHierarchy");

    //StartPrepSDKCall(SDKCall_Entity);
	//PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "Infected::AttackSurvivorTeam");
	//hInfectedAttackSurvivorTeam = EndPrepSDKCall();

	//StartPrepSDKCall(SDKCall_Entity);
	//PrepSDKCall_SetFromConf(hGameData_l4dhooks, SDKConf_Signature, "Tank::EnterStasis");
	//hTankEnterStasis = EndPrepSDKCall();

	//StartPrepSDKCall(SDKCall_Entity);
	//PrepSDKCall_SetFromConf(hGameData_l4dhooks, SDKConf_Signature, "Tank::LeaveStasis");
	//hTankLeaveStasis = EndPrepSDKCall();

	int acceptInputOffset = GameConfGetOffset(hGameData, "CBaseEntity::AcceptInput");
	if (acceptInputOffset == -1)
	{
		LogMessage("[zm] Failed to load \"CBaseEntity::AcceptInput\" offset.");
	}
	else
	{
	    g_DHook_AcceptInput = DHookCreate(acceptInputOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CharPtr);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(g_DHook_AcceptInput, HookParamType_Object, 20);
	    DHookAddParam(g_DHook_AcceptInput, HookParamType_Int);
	}

	// PVS engine calls
	g_pEngineServer = GameConfGetAddress(hGameData, "engine_ptr");
	if (g_pEngineServer == Address_Null)
	{
		LogMessage("[zm] WARNING: Could not find engine server pointer (gamedata address 'engine_ptr'); PVS checks disabled");
	}
	else
	{
		int offClu = GameConfGetOffset(hGameData, "IVEngineServer::GetClusterForOrigin");
		int offPvs = GameConfGetOffset(hGameData, "IVEngineServer::GetPVSForCluster");
		int offChk = GameConfGetOffset(hGameData, "IVEngineServer::CheckOriginInPVS");

		// GetClusterForOrigin(Vector const&) -> int
		if (offClu == -1)
			LogMessage("[zm] WARNING: Gamedata offset IVEngineServer::GetClusterForOrigin missing");
		else
		{
			StartPrepSDKCall(SDKCall_Raw);
			PrepSDKCall_SetVirtual(offClu);
			PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
			hGetClusterForOrigin = EndPrepSDKCall();
			if (hGetClusterForOrigin == null)
				LogMessage("[zm] WARNING: EndPrepSDKCall(GetClusterForOrigin) returned null (offset=%d may be wrong)", offClu);
		}

		// GetPVSForCluster(int cluster, int pvslength, unsigned char* outputpvs) -> int
		if (offPvs == -1)
			LogMessage("[zm] WARNING: Gamedata offset IVEngineServer::GetPVSForCluster missing");
		else
		{
			StartPrepSDKCall(SDKCall_Raw);
			PrepSDKCall_SetVirtual(offPvs);
			PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
			PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
			PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
			hGetPVSForCluster = EndPrepSDKCall();
			if (hGetPVSForCluster == null)
				LogMessage("[zm] WARNING: EndPrepSDKCall(GetPVSForCluster) returned null (offset=%d may be wrong)", offPvs);
		}

		// CheckOriginInPVS(Vector const&, unsigned char const*, int) -> bool
		if (offChk == -1)
			LogMessage("[zm] WARNING: Gamedata offset IVEngineServer::CheckOriginInPVS missing");
		else
		{
			StartPrepSDKCall(SDKCall_Raw);
			PrepSDKCall_SetVirtual(offChk);
			PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
			PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
			PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
			hCheckOriginInPVS = EndPrepSDKCall();
			if (hCheckOriginInPVS == null)
				LogMessage("[zm] WARNING: EndPrepSDKCall(CheckOriginInPVS) returned null (offset=%d may be wrong)", offChk);
		}

		bool allPvsReady = hGetClusterForOrigin != null && hGetPVSForCluster != null && hCheckOriginInPVS != null;
		if (!allPvsReady)
		{
    		LogMessage("[zm] INFO: PVS SDKCalls: GetClusterForOrigin=%s GetPVSForCluster=%s CheckOriginInPVS=%s (pipeline %s)",
    		hGetClusterForOrigin == null ? "FAIL" : "ok",
    		hGetPVSForCluster == null ? "FAIL" : "ok",
    		hCheckOriginInPVS == null ? "FAIL" : "ok",
    		allPvsReady ? "READY" : "DEGRADED - fallback LOS path will run");
        }
	}

	// TerrorNavArea::IsPotentiallyVisibleToTeam(int team) -> bool
	StartPrepSDKCall(SDKCall_Raw);
	bool navSigOk = PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "TerrorNavArea::IsPotentiallyVisibleToTeam");
	if (navSigOk)
	{
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		hNavIsPotentiallyVisibleToTeam = EndPrepSDKCall();
	}
	if (!navSigOk)
		LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisibleToTeam SetFromConf failed; nav filter disabled (gamedata sig not found or binary mismatch)");
	else if (hNavIsPotentiallyVisibleToTeam == null)
		LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisibleToTeam EndPrepSDKCall returned null; nav filter disabled");
	//else
	//	LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisibleToTeam SDKCall ready");
	
	// TerrorNavArea::IsCompletelyVisibleToTeam(int team) -> bool
	StartPrepSDKCall(SDKCall_Raw);
	navSigOk = PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "TerrorNavArea::IsCompletelyVisibleToTeam");
	if (navSigOk)
	{
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		hNavIsCompletelyVisibleToTeam = EndPrepSDKCall();
	}
	if (!navSigOk)
		LogMessage("[zm] INFO: TerrorNavArea::IsCompletelyVisibleToTeam SetFromConf failed; nav filter disabled (gamedata sig not found or binary mismatch)");
	else if (hNavIsPotentiallyVisibleToTeam == null)
		LogMessage("[zm] INFO: TerrorNavArea::IsCompletelyVisibleToTeam EndPrepSDKCall returned null; nav filter disabled");

	// TerrorNavArea::IsPotentiallyVisible(const TerrorNavArea*, bool) -> bool (signature-based, non-virtual)
	StartPrepSDKCall(SDKCall_Raw);
	bool navPairSigOk = PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "TerrorNavArea::IsPotentiallyVisible");
	if (navPairSigOk)
	{
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // const TerrorNavArea* other
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // bool checkAttributes
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		hNavIsPotentiallyVisible = EndPrepSDKCall();
	}
	if (!navPairSigOk)
		LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisible SetFromConf failed; per-area-pair LOS path disabled (sig not found or binary mismatch)");
	else if (hNavIsPotentiallyVisible == null)
		LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisible EndPrepSDKCall returned null; per-area-pair LOS path disabled");
	//else
	//	LogMessage("[zm] INFO: TerrorNavArea::IsPotentiallyVisible SDKCall ready");

	delete hGameData;
}

stock bool NavArea_IsPotentiallyVisibleToTeam(Address navArea, int team)
{
	if (hNavIsPotentiallyVisibleToTeam == null || navArea == Address_Null) return true;
	return SDKCall(hNavIsPotentiallyVisibleToTeam, navArea, team);
}

stock bool NavArea_IsCompletelyVisibleToTeam(Address navArea, int team)
{
	if (hNavIsCompletelyVisibleToTeam == null || navArea == Address_Null) return true;
	return SDKCall(hNavIsCompletelyVisibleToTeam, navArea, team);
}

stock bool NavArea_IsPotentiallyVisible(Address cellArea, Address survivorArea, bool checkAttributes)
{
	if (hNavIsPotentiallyVisible == null || cellArea == Address_Null || survivorArea == Address_Null) return true;
	return SDKCall(hNavIsPotentiallyVisible, cellArea, survivorArea, checkAttributes);
}

// PVS wrapper functions
stock int PVS_GetClusterForOrigin(const float origin[3])
{
	if (hGetClusterForOrigin == null || g_pEngineServer == Address_Null) return -1;
	return SDKCall(hGetClusterForOrigin, g_pEngineServer, origin);
}

stock bool PVS_GetForCluster(int cluster, char pvsBuf[PVS_BUFFER_SIZE])
{
	if (hGetPVSForCluster == null || g_pEngineServer == Address_Null) return false;
	SDKCall(hGetPVSForCluster, g_pEngineServer, cluster, PVS_BUFFER_SIZE, pvsBuf);
	return true;
}

stock bool PVS_CheckOriginInPVS(const float origin[3], const char pvsBuf[PVS_BUFFER_SIZE])
{
	if (hCheckOriginInPVS == null || g_pEngineServer == Address_Null) return false;
	return SDKCall(hCheckOriginInPVS, g_pEngineServer, origin, pvsBuf, PVS_BUFFER_SIZE);
}

stock bool PVS_IsInAnySurvivorPVS(const float origin[3], const char survivorPVS[][PVS_BUFFER_SIZE], int survivorPVSCount)
{
	for (int s = 0; s < survivorPVSCount; s++)
	{
		if (PVS_CheckOriginInPVS(origin, survivorPVS[s]))
			return true;
	}
	return false;
}

void LoadStringFromAdddress(Address addr, char[] buffer, int maxlength) {
	int i = 0;
	while(i < maxlength) {
		char val = LoadFromAddress(addr + view_as<Address>(i), NumberType_Int8);
		if(val == 0) {
			buffer[i] = 0;
			break;
		}
		buffer[i] = val;
		i++;
	}
	buffer[maxlength - 1] = 0;
}

Handle PrepCreateBotCallFromAddress(Handle hSiFuncTrie, const char[] siName) {
	Address addr;
	StartPrepSDKCall(SDKCall_Static);
	if (!GetTrieValue(hSiFuncTrie, siName, addr) || !PrepSDKCall_SetAddress(addr))
	{
		SetFailState("Unable to find NextBotCreatePlayer<%s> address in memory.", siName);
		return null;
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	return EndPrepSDKCall();
}

void PrepWindowsCreateBotCalls(Address jumpTableAddr) {
	Handle hInfectedFuncs = CreateTrie();
	// We have the address of the jump table, starting at the first PUSH instruction of the
	// PUSH mem32 (5 bytes)
	// CALL rel32 (5 bytes)
	// JUMP rel8 (2 bytes)
	// repeated pattern.

	// Each push is pushing the address of a string onto the stack. Let's grab these strings to identify each case.
	// "Hunter" / "Smoker" / etc.
	for(int i = 0; i < 7; i++) {
		// 12 bytes in PUSH32, CALL32, JMP8.
		Address caseBase = jumpTableAddr + view_as<Address>(i * 12);
		Address siStringAddr = view_as<Address>(LoadFromAddress(caseBase + view_as<Address>(1), NumberType_Int32));
		static char siName[32];
		LoadStringFromAdddress(siStringAddr, siName, sizeof(siName));

		Address funcRefAddr = caseBase + view_as<Address>(6); // 2nd byte of call, 5+1 byte offset.
		int funcRelOffset = LoadFromAddress(funcRefAddr, NumberType_Int32);
		Address callOffsetBase = caseBase + view_as<Address>(10); // first byte of next instruction after the CALL instruction
		Address nextBotCreatePlayerBotTAddr = callOffsetBase + view_as<Address>(funcRelOffset);
		//LogMessage("Found NextBotCreatePlayerBot<%s>() @ %08x", siName, nextBotCreatePlayerBotTAddr);
		SetTrieValue(hInfectedFuncs, siName, nextBotCreatePlayerBotTAddr);
	}

	hCreateSmoker = PrepCreateBotCallFromAddress(hInfectedFuncs, "Smoker");
	if (hCreateSmoker == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateSmoker); return; }

	hCreateBoomer = PrepCreateBotCallFromAddress(hInfectedFuncs, "Boomer");
	if (hCreateBoomer == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateBoomer); return; }

	hCreateHunter = PrepCreateBotCallFromAddress(hInfectedFuncs, "Hunter");
	if (hCreateHunter == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateHunter); return; }

	hCreateTank = PrepCreateBotCallFromAddress(hInfectedFuncs, "Tank");
	if (hCreateTank == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateTank); return; }

	hCreateSpitter = PrepCreateBotCallFromAddress(hInfectedFuncs, "Spitter");
	if (hCreateSpitter == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateSpitter); return; }

	hCreateJockey = PrepCreateBotCallFromAddress(hInfectedFuncs, "Jockey");
	if (hCreateJockey == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateJockey); return; }

	hCreateCharger = PrepCreateBotCallFromAddress(hInfectedFuncs, "Charger");
	if (hCreateCharger == null)
	{ SetFailState("Cannot initialize %s SDKCall, address lookup failed.", NAME_CreateCharger); return; }

	delete hInfectedFuncs;
}

void PrepL4D2CreateBotCalls() {
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateSpitter))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSpitter); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateSpitter = EndPrepSDKCall();
	if (hCreateSpitter == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSpitter); return; }

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateJockey))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateJockey); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateJockey = EndPrepSDKCall();
	if (hCreateJockey == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateJockey); return; }

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateCharger))
	{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateCharger); return; }
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateCharger = EndPrepSDKCall();
	if (hCreateCharger == null)
	{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateCharger); return; }
}

void PrepL4D1CreateBotCalls()
{
	bool bLinuxOS = hGameData.GetOffset("OS") != 0;
	if(bLinuxOS)
	{
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateSmoker))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSmoker); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateSmoker = EndPrepSDKCall();
		if (hCreateSmoker == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSmoker); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateBoomer))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateBoomer); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateBoomer = EndPrepSDKCall();
		if (hCreateBoomer == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateBoomer); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateHunter))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateHunter); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateHunter = EndPrepSDKCall();
		if (hCreateHunter == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateHunter); return; }

		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, NAME_CreateTank))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateTank); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateTank = EndPrepSDKCall();
		if (hCreateTank == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateTank); return; }
	}
	else
	{
		Address addr;

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateSmoker_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateSmoker_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateSmoker = EndPrepSDKCall();
		if(hCreateSmoker == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateSmoker_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateBoomer_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateBoomer_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateBoomer = EndPrepSDKCall();
		if(hCreateBoomer == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateBoomer_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateHunter_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateHunter_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateHunter = EndPrepSDKCall();
		if(hCreateHunter == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateHunter_L4D1); return; }

		addr = RelativeJumpDestination(hGameData.GetAddress(NAME_CreateTank_L4D1));
		StartPrepSDKCall(SDKCall_Static);
		if (!PrepSDKCall_SetAddress(addr))
		{ SetFailState("Unable to find %s signature in gamedata file.", NAME_CreateTank_L4D1); return; }
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
		hCreateTank = EndPrepSDKCall();
		if(hCreateTank == null)
		{ SetFailState("Cannot initialize %s SDKCall, signature is broken.", NAME_CreateTank_L4D1); return; }
	}
}

Address RelativeJumpDestination(Address p)
{
	int offset = LoadFromAddress(p, NumberType_Int32);
	return p + view_as<Address>(offset + 4);
}
