/**
 * L4D2 Grid Library
 * Pre-computed nav mesh grid system for spawn validation
 *
 * Version: 1.1.0
 * Author: zyiks
 * Dependencies: left4dhooks, sdktools
 *
 * Usage:
 *   #include <left4dhooks>
 *   #include <l4d2_grid_lib>
 *
 *   // In OnMapStart()
 *   GridLib_Initialize();
 *   GridLib_StartPrecomputation();
 *
 *   // In OnMapEnd()
 *   GridLib_Cleanup();
 *
 *   // Find cells near a position
 *   int cells[200];
 *   int count = GridLib_FindNearbyCells(position, 150.0, 100.0, cells, 200);
 *
 *   // Get cell data
 *   float pos[3], normal[3];
 *   Address navArea;
 *   bool obstructed;
 *   GridLib_GetCellData(cellIdx, pos, normal, navArea, obstructed);
 *
 *   // Get nav attributes for spawn validation
 *   int spawnAttrs = GridLib_GetCellSpawnAttributes(cellIdx);
 *   if (spawnAttrs & GRIDLIB_NAV_SPAWN_CHECKPOINT) { ... }
 *
 * Constants:
 *   GRIDLIB_NAV_BLOCKED_ZOMBIES  - Blocks saferooms, checkpoints, battlestations
 */

#if defined _l4d2_grid_lib_included
 #endinput
#endif
#define _l4d2_grid_lib_included

// Require dependencies
#if !defined _l4dh_included
    #tryinclude <left4dhooks>
#endif

#if !defined _sdktools_included
    #include <sdktools>
#endif

#if !defined _l4d2_log_lib_included
    #include <l4d2_log_lib>
#endif

// ============================================================================
// Constants
// ============================================================================

#define GRIDLIB_VERSION "1.1.0"

#define GRIDLIB_LOG_CHANNEL "GridLib"

#define GRIDLIB_CELL_SIZE 32.0
#define GRIDLIB_SPATIAL_BUCKET_SIZE 150.0
#define GRIDLIB_MAX_CELLS 500000

// ============================================================================
// Nav Mesh Attribute Constants (from left4dhooks)
// ============================================================================

// Nav Spawn Attributes (L4D_GetNavArea_SpawnAttributes)
#define GRIDLIB_NAV_SPAWN_EMPTY              0
#define GRIDLIB_NAV_SPAWN_STOP_SCAN          (1 << 0)   // 0x1
#define GRIDLIB_NAV_SPAWN_BATTLESTATION      (1 << 3)   // 0x8
#define GRIDLIB_NAV_SPAWN_FINALE             (1 << 5)   // 0x20
#define GRIDLIB_NAV_SPAWN_PLAYER_START       (1 << 7)   // 0x80
#define GRIDLIB_NAV_SPAWN_BATTLEFIELD        (1 << 8)   // 0x100
#define GRIDLIB_NAV_SPAWN_IGNORE_VISIBILITY  (1 << 9)   // 0x200
#define GRIDLIB_NAV_SPAWN_NOT_CLEARABLE      (1 << 10)  // 0x400
#define GRIDLIB_NAV_SPAWN_CHECKPOINT         (1 << 11)  // 0x800
#define GRIDLIB_NAV_SPAWN_OBSCURED           (1 << 12)  // 0x1000
#define GRIDLIB_NAV_SPAWN_NO_MOBS            (1 << 13)  // 0x2000
#define GRIDLIB_NAV_SPAWN_THREAT             (1 << 14)  // 0x4000
#define GRIDLIB_NAV_SPAWN_RESCUE_VEHICLE     (1 << 15)  // 0x8000
#define GRIDLIB_NAV_SPAWN_RESCUE_CLOSET      (1 << 17)  // 0x20000
#define GRIDLIB_NAV_SPAWN_ESCAPE_ROUTE       (1 << 18)  // 0x40000
#define GRIDLIB_NAV_SPAWN_DOOR               (1 << 19)  // 0x80000

// Nav Attribute Flags (L4D_GetNavArea_AttributeFlags)
#define GRIDLIB_NAV_ATTR_CROUCH              (1 << 0)   // 0x1
#define GRIDLIB_NAV_ATTR_JUMP                (1 << 1)   // 0x2
#define GRIDLIB_NAV_ATTR_PRECISE             (1 << 2)   // 0x4
#define GRIDLIB_NAV_ATTR_NO_JUMP             (1 << 3)   // 0x8
#define GRIDLIB_NAV_ATTR_STOP                (1 << 4)   // 0x10
#define GRIDLIB_NAV_ATTR_RUN                 (1 << 5)   // 0x20
#define GRIDLIB_NAV_ATTR_WALK                (1 << 6)   // 0x40
#define GRIDLIB_NAV_ATTR_AVOID               (1 << 7)   // 0x80
#define GRIDLIB_NAV_ATTR_TRANSIENT           (1 << 8)   // 0x100
#define GRIDLIB_NAV_ATTR_DONT_HIDE           (1 << 9)   // 0x200
#define GRIDLIB_NAV_ATTR_STAND               (1 << 10)  // 0x400
#define GRIDLIB_NAV_ATTR_NO_HOSTAGES         (1 << 11)  // 0x800
#define GRIDLIB_NAV_ATTR_STAIRS              (1 << 12)  // 0x1000
#define GRIDLIB_NAV_ATTR_OUTSIDE_WORLD       (1 << 14)  // 0x4000

// Preset blocked spawn attributes for common use cases
#define GRIDLIB_NAV_BLOCKED_ZOMBIES (GRIDLIB_NAV_SPAWN_PLAYER_START | GRIDLIB_NAV_SPAWN_CHECKPOINT | GRIDLIB_NAV_SPAWN_BATTLESTATION)

// Legacy aliases for backward compatibility
#define GRIDLIB_NAV_CHECKPOINT GRIDLIB_NAV_SPAWN_CHECKPOINT
#define GRIDLIB_NAV_OBSCURED   GRIDLIB_NAV_SPAWN_OBSCURED

// Surface flags
#define GRIDLIB_SURF_NODRAW  0x0080
#define GRIDLIB_SURF_HINT    0x0100
#define GRIDLIB_SURF_SKIP    0x0200

// Team definitions
#define GRIDLIB_TEAM_SURVIVOR 2
#define GRIDLIB_TEAM_INFECTED		3

// Zombie hull dimensions
#define GRIDLIB_HULL_MIN_X  -16.0
#define GRIDLIB_HULL_MIN_Y  -16.0
//#define GRIDLIB_HULL_MIN_Z    0.0
#define GRIDLIB_HULL_MIN_Z   20.0
#define GRIDLIB_HULL_MAX_X   16.0
#define GRIDLIB_HULL_MAX_Y   16.0
//#define GRIDLIB_HULL_MAX_Z   72.0
#define GRIDLIB_HULL_MAX_Z   60.0

// LOS validation constants
#define GRIDLIB_LOS_CHECK_HEIGHT  36.0
#define GRIDLIB_LOS_HIT_TOLERANCE 10.0

// ============================================================================
// Data Structures
// ============================================================================

enum struct GridCell
{
	float position[3];     // World position
	Address navArea;       // Nav area reference
	bool isObstructed;     // Hull trace result (pre-computed)
	float normal[3];       // Surface normal
	int cluster;           // PVS leaf cluster for position (-1 if PVS native unavailable)
	bool isUnderwater;     // Submerged in water brush (pre-computed at bake time)
}

/**
 * Filter result for GridLib_FindNearbyCells callbacks.
 */
#define GRIDLIB_FILTER_KEEP         0  // Accept this cell
#define GRIDLIB_FILTER_DISCARD      1  // Reject this cell only
#define GRIDLIB_FILTER_DISCARD_NAV  2  // Reject this cell and all cells on the same nav area
#define GRIDLIB_FILTER_DISCARD_ALL  3  // Stop searching, reject all remaining cells

/**
 * Filter callback for GridLib_FindNearbyCells.
 * The filter can call GridLib_GetCellData / GridLib_GetCellSpawnAttributes
 * to inspect cell properties. Context should flow through caller-side statics.
 *
 * @param cellIdx    Cell index to evaluate
 * @return           GRIDLIB_FILTER_KEEP, GRIDLIB_FILTER_DISCARD, GRIDLIB_FILTER_DISCARD_NAV, or GRIDLIB_FILTER_DISCARD_ALL
 */
typedef GridLibCellFilter = function int(int cellIdx);

static stock int GridLib_CallFilter(GridLibCellFilter filter, int cellIdx)
{
	int result;
	Call_StartFunction(null, filter);
	Call_PushCell(cellIdx);
	Call_Finish(result);
	return result;
}

static stock int GridLib_SortByDistance(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList list = view_as<ArrayList>(array);
	float a[2], b[2];
	list.GetArray(index1, a);
	list.GetArray(index2, b);
	if (a[0] < b[0]) return -1;
	if (a[0] > b[0]) return 1;
	return 0;
}

// ============================================================================
// Private State (do not access directly)
// ============================================================================

static ArrayList g_GridCells = null;
static ArrayList g_SpatialHash = null;
static float g_MapMin[3];
static float g_MapMax[3];
static int g_HashGridWidth;
static int g_HashGridHeight;
static bool g_IsReady = false;
static int g_TotalCells = 0;
static bool g_IsPrecomputing = false;
static float g_HeightOffset = 5.0;
static bool g_CheckObstruction = true;
static bool g_ExcludeObstructed = true;
static StringMap g_NavAreaCells = null;  // navArea Address → ArrayList of cell indices

// --- Nav-reach precompute state ---
// consumers must check g_NavReachReady == true before reading g_NavReach
static StringMap g_NavReach = null;
static bool g_NavReachReady = false;
static ArrayList g_NavReachPending = null;  // nav areas still to process during sliced precompute
static int g_NavReachCursor = 0;

// Max Dijkstra horizon at precompute time (world units of nav-path distance).
#define GRIDLIB_NAV_REACH_MAX 600.0

// How many nav areas to Dijkstra per timer slice (budget guard separately).
#define GRIDLIB_NAV_REACH_PER_TICK 20

// Hard CPU budget per slice in ms; slice yields when exceeded.
#define GRIDLIB_NAV_REACH_SLICE_MS 5.0

// ============================================================================
// Public API
// ============================================================================

/**
 * Initialize the grid system
 * Call this in OnMapStart() before StartPrecomputation()
 */
stock void GridLib_Initialize()
{
	if (g_IsPrecomputing)
	{
		Log_Warn(GRIDLIB_LOG_CHANNEL, "Initialize skipped, precomputation in progress");
		return;
	}

	if (g_GridCells != null)
		GridLib_Cleanup();

	g_GridCells = new ArrayList(sizeof(GridCell));
	g_SpatialHash = new ArrayList();
	g_NavAreaCells = new StringMap();
	g_IsReady = false;
	g_TotalCells = 0;

	Log_Info(GRIDLIB_LOG_CHANNEL, "Initialized");
}

/**
 * Start pre-computation
 * Returns true if started, false if already running
 */
stock bool GridLib_StartPrecomputation()
{
	if (g_IsPrecomputing || g_IsReady)
		return false;

	if (g_GridCells == null)
		GridLib_Initialize();

	g_IsPrecomputing = true;
	CreateTimer(1.0, GridLib_Timer_StartPrecompute, _, TIMER_FLAG_NO_MAPCHANGE);
	return true;
}

/**
 * Check if pre-computation is complete
 */
stock bool GridLib_IsReady()
{
	return g_IsReady;
}

/**
 * Get total number of pre-computed cells
 */
stock int GridLib_GetTotalCells()
{
	return g_TotalCells;
}

/**
 * Set height offset above ground for cells
 * Default: 5.0 units
 */
stock void GridLib_SetHeightOffset(float offset)
{
	g_HeightOffset = offset;
}

/**
 * Enable/disable obstruction checking during pre-computation
 * Default: true
 */
stock void GridLib_SetCheckObstruction(bool enable)
{
	g_CheckObstruction = enable;
}

/**
 * Exclude obstructed cells from the spatial hash during pre-computation
 * When enabled, cells that fail the hull obstruction check are not stored at all,
 * reducing memory usage and lookup cost.
 * Default: false (obstructed cells are stored but filtered at runtime)
 */
stock void GridLib_SetExcludeObstructed(bool enable)
{
	g_ExcludeObstructed = enable;
}

/**
 * Find nearby cells around a position
 *
 * @param position      World position to search around
 * @param searchRadius  Search radius in units
 * @param maxZDiff      Maximum Z-height difference
 * @param results       Output array of cell indices
 * @param maxResults    Maximum number of results to return
 * @param filter        Optional filter callback. When provided, cells are tested
 *                      closest-first during selection. Rejected cells are skipped
 *                      and the search continues to find the next closest passing cell.
 * @param budget_ms     Allowed CPU budget in miliseconds; exit early when exceeded.
 * @return              Number of cells found (sorted by distance, closest first)
 */
stock int GridLib_FindNearbyCells(const float position[3],
                                   float searchRadius,
                                   float maxZDiff,
                                   int[] results,
                                   int maxResults,
                                   GridLibCellFilter filter = INVALID_FUNCTION,
                                   float budget_ms = 10.0)
{
	if (!g_IsReady || g_GridCells == null)
		return 0;
    
    float tStart_ms = GetEngineTime() * 1000.0;

	// Static candidate list - allocated once, reused across calls
	// Each entry: [0] = distance, [1] = cellIndex (as float)
	static ArrayList candidates = null;
	if (candidates == null)
		candidates = new ArrayList(2);
	else
		candidates.Clear();

	// Calculate center bucket
	int centerBucketX = RoundToFloor((position[0] - g_MapMin[0]) / GRIDLIB_SPATIAL_BUCKET_SIZE);
	int centerBucketY = RoundToFloor((position[1] - g_MapMin[1]) / GRIDLIB_SPATIAL_BUCKET_SIZE);

	// Search adjacent buckets
	int bucketRadius = RoundToCeil(searchRadius / GRIDLIB_SPATIAL_BUCKET_SIZE);

	for (int dx = -bucketRadius; dx <= bucketRadius; dx++)
	{
		for (int dy = -bucketRadius; dy <= bucketRadius; dy++)
		{
			int bucketX = centerBucketX + dx;
			int bucketY = centerBucketY + dy;

			if (bucketX < 0 || bucketX >= g_HashGridWidth) continue;
			if (bucketY < 0 || bucketY >= g_HashGridHeight) continue;

			int bucketIdx = bucketY * g_HashGridWidth + bucketX;
			ArrayList bucket = g_SpatialHash.Get(bucketIdx);

			for (int i = 0; i < bucket.Length; i++)
			{
				int cellIdx = bucket.Get(i);
				GridCell cell;
				g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));

				// Distance check (XY plane + Z separately)
				float dx_f = cell.position[0] - position[0];
				float dy_f = cell.position[1] - position[1];
				float dz = cell.position[2] - position[2];
				float distXY = SquareRoot(dx_f*dx_f + dy_f*dy_f);

				if (distXY > searchRadius) continue;
				if (FloatAbs(dz) > maxZDiff) continue;

				float distance = SquareRoot(dx_f*dx_f + dy_f*dy_f + dz*dz);

				float entry[2];
				entry[0] = distance;
				entry[1] = float(cellIdx);
				candidates.PushArray(entry);
			}
		}
	}

	int candidateCount = candidates.Length;
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: %d candidates in radius %.0f, maxResults=%d, filter=%s",
		candidateCount, searchRadius, maxResults, filter != INVALID_FUNCTION ? "yes" : "no");

	// Selection sort closest-first, applying filter during selection.
	// Rejected cells are skipped; the search continues to fill maxResults.
	// DISCARD_NAV blacklists an entire nav area (O(1) lookup via StringMap).
	static StringMap blacklistedNavAreas = null;
	char navKey[16];
	float filterT0 = 0.0;
	if (filter != INVALID_FUNCTION)
	{
		if (blacklistedNavAreas == null)
			blacklistedNavAreas = new StringMap();
		else
			blacklistedNavAreas.Clear();
		filterT0 = GetEngineTime();
	}

	float tSortStart = GetEngineTime();
	SortADTArrayCustom(candidates, GridLib_SortByDistance);
	float sortMs = (GetEngineTime() - tSortStart) * 1000.0;

	int resultCount = 0;
	int scanned = 0;
	Address master_navArea = Address_Null;
	float filterCallTimeAccum = 0.0;
	for (int i = 0; i < candidateCount && resultCount < maxResults; i++, scanned++)
	{
		float selected[2];
		candidates.GetArray(i, selected);
		int cellIdx = RoundToFloor(selected[1]);

		if (filter != INVALID_FUNCTION)
		{
			GridCell cell;
			g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));

			// Check nav area blacklist (O(1) StringMap lookup)
			if (cell.navArea != Address_Null)
			{
				FormatEx(navKey, sizeof(navKey), "%x", cell.navArea);
				int dummy;
				if (blacklistedNavAreas.GetValue(navKey, dummy))
				{
					Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d nav %s blacklisted, skipping", cellIdx, navKey);
					continue;
				}
			}
			else
			{
    			continue; // invalid nav areas should be skipped
			}

			float tFilter = GetEngineTime();
			int filterResult = GridLib_CallFilter(filter, cellIdx);
			filterCallTimeAccum += GetEngineTime() - tFilter;
			if (filterResult == GRIDLIB_FILTER_DISCARD_ALL)
			{
				Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d DISCARD_ALL, stopping search", cellIdx);
				break;
			}
			if (filterResult == GRIDLIB_FILTER_DISCARD_NAV)
			{
				Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d DISCARD_NAV (nav=%x)", cellIdx, cell.navArea);
				if (cell.navArea != Address_Null)
				{
					FormatEx(navKey, sizeof(navKey), "%x", cell.navArea);
					blacklistedNavAreas.SetValue(navKey, 1);
				}
				continue;
			}
			if (filterResult != GRIDLIB_FILTER_KEEP)
			{
				Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d DISCARD", cellIdx);
				continue;
			}
			if (master_navArea!=Address_Null && master_navArea!=cell.navArea)
			{
    			if (!L4D2_NavAreaBuildPath(cell.navArea, master_navArea, searchRadius, GRIDLIB_TEAM_INFECTED, false))
    			{
        			Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d NavAreaBuildPath failed", cellIdx);
    				continue;
    			}
    			if (!L4D2_NavAreaBuildPath(master_navArea, cell.navArea, searchRadius, GRIDLIB_TEAM_INFECTED, false))
    			{
        			Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d NavAreaBuildPath failed", cellIdx);
    				continue;
    			}
			}
			Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: cell %d KEEP (dist=%.0f)", cellIdx, selected[0]);
			if (master_navArea==Address_Null) master_navArea = cell.navArea;
		}
        
		results[resultCount++] = cellIdx;
		
		if ( (GetEngineTime()*1000.0-tStart_ms) >= budget_ms)
		{
    		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: %.1fms budget exceeded, %d/%d cells", budget_ms, i, candidateCount);
    		break;
		}
		
	}

	float filterMs = (filter != INVALID_FUNCTION) ? (GetEngineTime() - filterT0) * 1000.0 : 0.0;
	float filterCallMs = filterCallTimeAccum * 1000.0;
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindNearbyCells: returning %d/%d candidates (scanned %d, %.2fms, sort=%.2fms, filter=%.2fms)",
		resultCount, candidateCount, scanned, filterMs, sortMs, filterCallMs);
	if (filterMs > budget_ms)
		Log_Warn(GRIDLIB_LOG_CHANNEL, "FindNearbyCells filter took %.1fms (scanned %d/%d, returned %d, sort=%.1fms, filtercb=%.1fms, overhead=%.1fms)",
			filterMs, scanned, candidateCount, resultCount, sortMs, filterCallMs, filterMs - sortMs - filterCallMs);

	return resultCount;
}

/**
 * Get cell data by index
 *
 * @param cellIdx    Cell index from FindNearbyCells
 * @param position   Output: cell world position
 * @param normal     Output: surface normal
 * @param navArea    Output: nav area address
 * @param obstructed Output: is obstructed
 * @return           true if valid index, false otherwise
 */
stock bool GridLib_GetCellData(int cellIdx,
                                float position[3],
                                float normal[3],
                                Address &navArea,
                                bool &obstructed)
{
	if (!g_IsReady || cellIdx < 0 || cellIdx >= g_TotalCells)
		return false;

	GridCell cell;
	g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));

	position[0] = cell.position[0];
	position[1] = cell.position[1];
	position[2] = cell.position[2];

	normal[0] = cell.normal[0];
	normal[1] = cell.normal[1];
	normal[2] = cell.normal[2];

	navArea = cell.navArea;
	obstructed = cell.isObstructed;

	return true;
}

/**
 * Get the precomputed PVS leaf cluster for a cell.
 *
 * @param cellIdx    Cell index
 * @return           Cluster int, or -1 if invalid index or PVS native unavailable at precompute time
 */
stock int GridLib_GetCellCluster(int cellIdx)
{
	if (!g_IsReady || cellIdx < 0 || cellIdx >= g_TotalCells)
		return -1;

	GridCell cell;
	g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));
	return cell.cluster;
}

/**
 * Check whether a cell is submerged in water.
 *
 * @param cellIdx    Cell index
 * @return           true if submerged, false otherwise or on invalid index
 */
stock bool GridLib_IsCellUnderwater(int cellIdx)
{
	if (!g_IsReady || cellIdx < 0 || cellIdx >= g_TotalCells)
		return false;

	GridCell cell;
	g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));
	return cell.isUnderwater;
}

/**
 * Get nav area spawn attributes for a cell
 * @param cellIdx    Cell index
 * @return           Spawn attributes, or 0 if invalid
 */
stock int GridLib_GetCellSpawnAttributes(int cellIdx)
{
	float pos[3], normal[3];
	Address navArea;
	bool obstructed;

	if (!GridLib_GetCellData(cellIdx, pos, normal, navArea, obstructed))
		return 0;

	if (navArea == Address_Null)
		return 0;

	return L4D_GetNavArea_SpawnAttributes(navArea);
}

/**
 * Get nav area attribute flags for a cell
 * @param cellIdx    Cell index
 * @return           Attribute flags, or 0 if invalid
 */
stock int GridLib_GetCellAttributeFlags(int cellIdx)
{
	float pos[3], normal[3];
	Address navArea;
	bool obstructed;

	if (!GridLib_GetCellData(cellIdx, pos, normal, navArea, obstructed))
		return 0;

	if (navArea == Address_Null)
		return 0;

	return L4D_GetNavArea_AttributeFlags(navArea);
}

/**
 * Get all cell indices belonging to a nav area
 *
 * @param navArea       Nav area address
 * @param results       Output array of cell indices
 * @param maxResults    Maximum number of results
 * @return              Number of cells found, or 0 if nav area not in grid
 */
stock int GridLib_GetCellsForNavArea(Address navArea, int[] results, int maxResults)
{
	if (!g_IsReady || g_NavAreaCells == null)
		return 0;

	char navKey[20];
	FormatEx(navKey, sizeof(navKey), "%x", navArea);

	ArrayList cellList;
	if (!g_NavAreaCells.GetValue(navKey, cellList))
		return 0;

	int count = cellList.Length;
	if (count > maxResults)
		count = maxResults;

	for (int i = 0; i < count; i++)
		results[i] = cellList.Get(i);

	return count;
}

/**
 * Find cells starting from the closest cell's nav area, expanding to adjacent areas if needed.
 *
 * Locates the nearest cell to the given position, then collects all cells in that cell's
 * nav area. If fewer than desiredCount cells are found, performs a BFS over adjacent nav
 * areas until enough cells are gathered or no more connected areas remain.
 *
 * @param position      World position to search from
 * @param desiredCount  Number of cells desired
 * @param results       Output array of cell indices (sorted by distance to position)
 * @param maxResults    Maximum size of results array
 * @param filter        Optional filter callback. When provided, cells are tested
 *                      during BFS collection. Rejected cells are skipped.
 * @param budget_ms     Allowed CPU budget in miliseconds; exit early when exceeded.
 * @param discard_obstructed Skip obstructed cells?
 * @return              Number of cells found
 */
stock int GridLib_FindCellsFromClosest(const float position[3],
                                       int desiredCount,
                                       int[] results,
                                       int maxResults,
                                       GridLibCellFilter filter = INVALID_FUNCTION,
                                       float budget_ms = 10.0,
                                       bool discard_obstructed = true)
{
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: pos=(%.0f,%.0f,%.0f) desired=%d maxResults=%d filter=%s",
		position[0], position[1], position[2], desiredCount, maxResults,
		filter != INVALID_FUNCTION ? "yes" : "no");

	if (!g_IsReady || g_GridCells == null || g_NavAreaCells == null)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: not ready (ready=%d cells=%d navmap=%d)",
			g_IsReady, g_GridCells != null, g_NavAreaCells != null);
		return 0;
	}
	
	float tStart_ms = GetEngineTime() * 1000.0;

	// Find the single closest cell
	int closestCell[1];
	int found = GridLib_FindNearbyCells(position, GRIDLIB_SPATIAL_BUCKET_SIZE, 9999.0, closestCell, 1);
	if (found == 0)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: no nearby cell found within bucket size %.0f", GRIDLIB_SPATIAL_BUCKET_SIZE);
		return 0;
	}

	// Get nav area of closest cell
	float cellPos[3], cellNormal[3];
	Address startNavArea;
	bool obstructed;
	if (!GridLib_GetCellData(closestCell[0], cellPos, cellNormal, startNavArea, obstructed))
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: failed to get cell data for closest cell %d", closestCell[0]);
		return 0;
	}

	if (startNavArea == Address_Null)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: closest cell %d has null nav area", closestCell[0]);
		return 0;
	}

	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: closest cell %d at (%.0f,%.0f,%.0f) navArea=%x",
		closestCell[0], cellPos[0], cellPos[1], cellPos[2], startNavArea);

	int cap = desiredCount;
	if (cap > maxResults) cap = maxResults;
	if (cap > 500) cap = 500;

	// Collect unfiltered target: over-collect to account for filter rejection
	int unfilteredTarget = cap * 5;
	if (unfilteredTarget > 500)
		unfilteredTarget = 500;

	// BFS over nav areas to collect candidate cells (cheap checks only)
	float candidates[500][3]; // [distance, cellIndex, navArea]
	int candidateCount = 0;

	StringMap visited = new StringMap();
	ArrayList queue = new ArrayList();
	ArrayList adjAreas = new ArrayList();
	char navKey[20];

	float collectT0 = GetEngineTime();

	// Seed BFS with starting nav area
	FormatEx(navKey, sizeof(navKey), "%x", startNavArea);
	visited.SetValue(navKey, true);
	queue.Push(startNavArea);

	int queueIdx = 0;
	int stopAfter = -1; // queue length snapshot when target was reached
	while (queueIdx < queue.Length && candidateCount < 500)
	{
		// Stop after processing one extra BFS ring beyond the unfiltered target
		if (stopAfter >= 0 && queueIdx >= stopAfter)
			break;

		Address currentArea = queue.Get(queueIdx);
		queueIdx++;

		// Collect cells from this nav area (cheap checks only, no filter)
		int areaCells[500];
		int areaCellCount = GridLib_GetCellsForNavArea(currentArea, areaCells, 500);
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: BFS[%d] navArea=%x cells=%d total=%d",
			queueIdx - 1, currentArea, areaCellCount, candidateCount);

		for (int i = 0; i < areaCellCount && candidateCount < 500; i++)
		{
			GridCell cell;
			g_GridCells.GetArray(areaCells[i], cell, sizeof(GridCell));
			if (cell.isObstructed && discard_obstructed)
				continue;

			// Skip nav-blocked cells (saferooms, checkpoints, etc.)
			if (cell.navArea != Address_Null)
			{
				int spawnAttrs = L4D_GetNavArea_SpawnAttributes(cell.navArea);
				if (spawnAttrs & GRIDLIB_NAV_BLOCKED_ZOMBIES)
					continue;
			}

			float dist = GetVectorDistance(position, cell.position);
			candidates[candidateCount][0] = dist;
			candidates[candidateCount][1] = float(areaCells[i]);
			candidates[candidateCount][2] = float(view_as<int>(cell.navArea));
			candidateCount++;
		}

		// Enqueue adjacent nav areas (all 4 directions)
		for (int dir = 0; dir < 4; dir++)
		{
			adjAreas.Clear();
			L4D_NavArea_GetAdjacentAreas(currentArea, dir, adjAreas);

			for (int i = 0; i < adjAreas.Length; i++)
			{
				Address adjArea = adjAreas.Get(i);
				FormatEx(navKey, sizeof(navKey), "%x", adjArea);

				int dummy;
				if (!visited.GetValue(navKey, dummy))
				{
					visited.SetValue(navKey, true);
					queue.Push(adjArea);
				}
			}
		}

		// Once we hit the unfiltered target, snapshot the queue length
		// so we process one more full ring of adjacent areas
		if (stopAfter < 0 && candidateCount >= unfilteredTarget)
			stopAfter = queue.Length;
	}

	float collectMs = (GetEngineTime() - collectT0) * 1000.0;
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: BFS done. navAreas=%d candidates=%d target=%d stopAfter=%d collect=%.2fms",
		queueIdx, candidateCount, unfilteredTarget, stopAfter, collectMs);

	delete visited;
	delete queue;
	delete adjAreas;

	// Sort all candidates by distance (selection sort)
	for (int i = 0; i < candidateCount - 1; i++)
	{
		int minIdx = i;
		for (int j = i + 1; j < candidateCount; j++)
		{
			if (candidates[j][0] < candidates[minIdx][0])
				minIdx = j;
		}

		if (minIdx != i)
		{
			float temp[3];
			temp = candidates[i];
			candidates[i] = candidates[minIdx];
			candidates[minIdx] = temp;
		}
	}

	// Filter closest-first (expensive filter calls minimized)
	float filterT0 = GetEngineTime();
	int resultCount = 0;
	int filterCalls = 0;
	bool filterAbort = false;

	// Nav area blacklist for filter DISCARD_NAV results
	static StringMap blacklistedNavAreas = null;
	if (filter != INVALID_FUNCTION)
	{
		if (blacklistedNavAreas == null)
			blacklistedNavAreas = new StringMap();
		else
			blacklistedNavAreas.Clear();
	}

	for (int i = 0; i < candidateCount && resultCount < cap && !filterAbort; i++)
	{
		int cellIdx = RoundToFloor(candidates[i][1]);

		if (filter != INVALID_FUNCTION)
		{
			
			if ((GetEngineTime()*1000.0-tStart_ms)>=budget_ms)
            {
                Log_Warn(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest over %.1fms budget at %d/%d cells", budget_ms, i, candidateCount);
                filterAbort = true;
                break;
            }
			
			// Check nav area blacklist first (O(1) lookup)
			Address navArea = view_as<Address>(RoundToFloor(candidates[i][2]));
			if (navArea != Address_Null)
			{
				FormatEx(navKey, sizeof(navKey), "%x", navArea);
				int dummy;
				if (blacklistedNavAreas.GetValue(navKey, dummy))
					continue;
			}

			filterCalls++;
			int filterResult = GridLib_CallFilter(filter, cellIdx);
			if (filterResult == GRIDLIB_FILTER_DISCARD_ALL)
			{
				filterAbort = true;
				break;
			}
			if (filterResult == GRIDLIB_FILTER_DISCARD_NAV)
			{
				if (navArea != Address_Null)
				{
					FormatEx(navKey, sizeof(navKey), "%x", navArea);
					blacklistedNavAreas.SetValue(navKey, 1);
				}
				continue;
			}
			if (filterResult != GRIDLIB_FILTER_KEEP)
				continue;
		}

		results[resultCount] = cellIdx;
		resultCount++;
	}

	float filterMs = (filter != INVALID_FUNCTION) ? (GetEngineTime() - filterT0) * 1000.0 : 0.0;
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest: returning %d cells, filterCalls=%d/%d collect=%.2fms filter=%.2fms (closest dist=%.0f, farthest dist=%.0f)",
		resultCount, filterCalls, candidateCount, collectMs, filterMs,
		resultCount > 0 ? candidates[0][0] : 0.0,
		resultCount > 0 ? candidates[resultCount - 1][0] : 0.0);
	if (filterMs > budget_ms)
		Log_Warn(GRIDLIB_LOG_CHANNEL, "FindCellsFromClosest filter took %.1fms (filterCalls=%d, candidates=%d)",
			filterMs, filterCalls, candidateCount);

	return resultCount;
}

/**
 * Find up to desiredCount cells near the given position that are nav-connected
 * to the seed cell's nav area within a nav-path distance of pathBudget.
 *
 * Uses the precomputed nav-reach table and a
 * ring-expanding KNN walk over the spatial hash.
 * Never fetches the full set of cells in a nav area, cells
 * come from spatial buckets only.
 *
 * Sort order: ascending Euclidean distance to `position`.
 *
 * @param position      World position to search from
 * @param desiredCount  Number of cells desired
 * @param results       Output array of cell indices.
 * @param maxResults    Capacity of `results`.
 * @param pathBudget    Max nav-path distance in world units. Clamped to
 *                      GRIDLIB_NAV_REACH_MAX (= 600).
 * @param filter        Optional GridLibCellFilter callback.
 * @param budget_ms     CPU budget in ms; the walk yields when exceeded.
 * @param discard_obstructed Skip cells flagged obstructed at precompute time.
 * @param oversample    Pre-filter oversample factor. The ring walk collects up
 *                      to desiredCount * oversample candidates (capped at 500)
 *                      so that a user filter rejecting some cells still leaves
 *                      enough survivors to fill desiredCount. Default 5.0 matches
 *                      the old FindCellsFromClosest behavior. Set to 1.0 to
 *                      disable oversampling.
 * @return              Number of cells written to results.
 *
 * Fallback: if g_NavReachReady is false (precompute not done yet, or reach
 * table unavailable on this map), delegates to GridLib_FindCellsFromClosest.
 */
stock int GridLib_FindCellsConnected(const float position[3],
                                      int desiredCount,
                                      int[] results,
                                      int maxResults,
                                      float pathBudget = 300.0,
                                      GridLibCellFilter filter = INVALID_FUNCTION,
                                      float budget_ms = 10.0,
                                      bool discard_obstructed = true,
                                      float oversample = 5.0)
{
	if (!g_IsReady || g_GridCells == null || g_SpatialHash == null)
		return 0;

	// Fallback while nav-reach precompute is still pending or unavailable
	if (!g_NavReachReady || g_NavReach == null)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsConnected: nav-reach not ready, falling back to FromClosest");
		return GridLib_FindCellsFromClosest(position, desiredCount, results, maxResults,
		                                     filter, budget_ms, discard_obstructed);
	}

	float t_start = GetEngineTime() * 1000.0;

	// Clamp pathBudget to precompute horizon
	if (pathBudget > GRIDLIB_NAV_REACH_MAX)
		pathBudget = GRIDLIB_NAV_REACH_MAX;

	// --- Resolve seed cell via existing spatial-hash single-nearest query ---
	int seedResult[1];
	int seedFound = GridLib_FindNearbyCells(position, GRIDLIB_SPATIAL_BUCKET_SIZE, 9999.0, seedResult, 1);
	if (seedFound == 0)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsConnected: no seed cell within bucket size");
		return 0;
	}

	GridCell seedCell;
	g_GridCells.GetArray(seedResult[0], seedCell, sizeof(GridCell));
	Address seedArea = seedCell.navArea;
	if (seedArea == Address_Null)
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsConnected: seed cell has null navArea");
		return 0;
	}

	// --- Fetch seed's reach inner-map (or fallback if missing) ---
	char seedKey[20];
	FormatEx(seedKey, sizeof(seedKey), "%x", seedArea);
	StringMap reachInner;
	if (!g_NavReach.GetValue(seedKey, reachInner))
	{
		Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsConnected: seed area %s has no reach entry, falling back", seedKey);
		return GridLib_FindCellsFromClosest(position, desiredCount, results, maxResults,
		                                     filter, budget_ms, discard_obstructed);
	}

	// Direct-neighbor set: cells in any of seed's nav-mesh adjacents always pass
	// the reach filter, regardless of the reach table's stored distance. This
	// fixes boundary behavior for very large nav areas, where the precomputed
	// area-center-to-area-center Dijkstra overstates the travel cost to an
	// immediate neighbor.
	StringMap seedAdjacents = new StringMap();
	ArrayList adjList = new ArrayList();
	char adjKey[20];
	for (int dir = 0; dir < 4; dir++)
	{
		adjList.Clear();
		L4D_NavArea_GetAdjacentAreas(seedArea, dir, adjList);
		for (int i = 0; i < adjList.Length; i++)
		{
			Address adj = adjList.Get(i);
			if (adj == Address_Null) continue;
			FormatEx(adjKey, sizeof(adjKey), "%x", adj);
			seedAdjacents.SetValue(adjKey, 1);
		}
	}
	delete adjList;

	// --- Top-K state: parallel arrays of (cellIdx, d_euc), kept sorted ascending ---
	// outputCap: how many cells we'll write to results[] after filtering.
	// searchCap: how many candidates we collect pre-filter (oversample for
	// resilience against user-filter rejections and DISCARD_NAV blacklists).
	int outputCap = desiredCount;
	if (outputCap > maxResults) outputCap = maxResults;
	if (outputCap > 500) outputCap = 500;

	if (oversample < 1.0) oversample = 1.0;
	int searchCap = RoundToCeil(float(desiredCount) * oversample);
	if (searchCap < outputCap) searchCap = outputCap;
	if (searchCap > 500) searchCap = 500;

	int topIdx[500];
	float topDist[500];
	int topN = 0;
	float maxInTopK = 99999999.0;

	// --- Ring-expanding spatial-hash walk ---
	int centerBucketX = RoundToFloor((position[0] - g_MapMin[0]) / GRIDLIB_SPATIAL_BUCKET_SIZE);
	int centerBucketY = RoundToFloor((position[1] - g_MapMin[1]) / GRIDLIB_SPATIAL_BUCKET_SIZE);
	int maxRing = RoundToCeil(pathBudget / GRIDLIB_SPATIAL_BUCKET_SIZE) + 1;

	int cellsVisited = 0;
	int cellsInsertedCount = 0;
	int cellsRejectReach = 0;
	int cellsRejectDist = 0;
	bool overBudget = false;
	char candKey[20];

	for (int ring = 0; ring <= maxRing && !overBudget; ring++)
	{
		// KNN cutoff: if the whole topK is full and the nearest bucket in this ring
		// is already farther than the worst entry, we're done.
		if (topN >= searchCap)
		{
			float ringMinDist = float(ring - 1) * GRIDLIB_SPATIAL_BUCKET_SIZE;
			if (ringMinDist > maxInTopK)
				break;
		}

		// Enumerate the buckets at Chebyshev distance `ring` from (centerBucketX, centerBucketY)
		int xLo = centerBucketX - ring, xHi = centerBucketX + ring;
		int yLo = centerBucketY - ring, yHi = centerBucketY + ring;

		for (int by = yLo; by <= yHi && !overBudget; by++)
		{
			for (int bx = xLo; bx <= xHi && !overBudget; bx++)
			{
				// Only the perimeter (skip interior for ring > 0)
				if (ring > 0 && bx != xLo && bx != xHi && by != yLo && by != yHi)
					continue;
				if (bx < 0 || bx >= g_HashGridWidth) continue;
				if (by < 0 || by >= g_HashGridHeight) continue;

				int bucketIdx = by * g_HashGridWidth + bx;
				ArrayList bucket = g_SpatialHash.Get(bucketIdx);

				for (int bi = 0; bi < bucket.Length; bi++)
				{
					int cellIdx = bucket.Get(bi);
					GridCell cell;
					g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));
					cellsVisited++;

					// Obstruction / blocked nav gate (cheap)
					if (cell.isObstructed && discard_obstructed)
						continue;
					if (cell.navArea == Address_Null)
						continue;
					int spawnAttrs = L4D_GetNavArea_SpawnAttributes(cell.navArea);
					if (spawnAttrs & GRIDLIB_NAV_BLOCKED_ZOMBIES)
						continue;

					// Euclidean distance
					float dx = cell.position[0] - position[0];
					float dy = cell.position[1] - position[1];
					float dz = cell.position[2] - position[2];
					float d_euc = SquareRoot(dx*dx + dy*dy + dz*dz);

					if (topN >= searchCap && d_euc >= maxInTopK)
						continue;

					// Nav-reach filter.
					// Direct-adjacents of the seed area always pass.
					if (cell.navArea != seedArea)
					{
						FormatEx(candKey, sizeof(candKey), "%x", cell.navArea);
						int adjDummy;
						if (!seedAdjacents.GetValue(candKey, adjDummy))
						{
							float pathDist;
							if (!reachInner.GetValue(candKey, pathDist))
							{
								cellsRejectReach++;
								continue;
							}
							if (pathDist > pathBudget)
							{
								cellsRejectDist++;
								continue;
							}
						}
					}

					// Insert into top-K (sorted ascending by d_euc)
					int insertAt = topN;
					for (int k = 0; k < topN; k++)
					{
						if (d_euc < topDist[k]) { insertAt = k; break; }
					}
					if (insertAt < searchCap)
					{
						int shiftEnd = (topN < searchCap) ? topN : searchCap - 1;
						for (int k = shiftEnd; k > insertAt; k--)
						{
							topIdx[k]  = topIdx[k - 1];
							topDist[k] = topDist[k - 1];
						}
						topIdx[insertAt]  = cellIdx;
						topDist[insertAt] = d_euc;
						if (topN < searchCap) topN++;
						cellsInsertedCount++;
						if (topN >= searchCap) maxInTopK = topDist[searchCap - 1];
					}

					// Budget check
					if ((GetEngineTime() * 1000.0 - t_start) >= budget_ms)
					{
						overBudget = true;
						Log_Warn(GRIDLIB_LOG_CHANNEL, "FindCellsConnected over %.1fms budget at ring=%d visited=%d",
							budget_ms, ring, cellsVisited);
						break;
					}
				}
			}
		}
	}

	// --- User filter pass ---
	int resultCount = 0;
	if (filter != INVALID_FUNCTION)
	{
		static StringMap blacklistedNavAreas = null;
		if (blacklistedNavAreas == null) blacklistedNavAreas = new StringMap();
		else blacklistedNavAreas.Clear();

		char filterKey[20];
		for (int k = 0; k < topN && resultCount < outputCap; k++)
		{
			int cellIdx = topIdx[k];
			GridCell cell;
			g_GridCells.GetArray(cellIdx, cell, sizeof(GridCell));

			if (cell.navArea != Address_Null)
			{
				FormatEx(filterKey, sizeof(filterKey), "%x", cell.navArea);
				int dummy;
				if (blacklistedNavAreas.GetValue(filterKey, dummy))
					continue;
			}

			int fr = GridLib_CallFilter(filter, cellIdx);
			if (fr == GRIDLIB_FILTER_DISCARD_ALL)
				break;
			if (fr == GRIDLIB_FILTER_DISCARD_NAV)
			{
				if (cell.navArea != Address_Null)
				{
					FormatEx(filterKey, sizeof(filterKey), "%x", cell.navArea);
					blacklistedNavAreas.SetValue(filterKey, 1);
				}
				continue;
			}
			if (fr != GRIDLIB_FILTER_KEEP)
				continue;

			results[resultCount++] = cellIdx;
		}
	}
	else
	{
		int limit = (topN < outputCap) ? topN : outputCap;
		for (int k = 0; k < limit; k++)
			results[resultCount++] = topIdx[k];
	}

	delete seedAdjacents;

	float ms_total = GetEngineTime() * 1000.0 - t_start;
	Log_Debug(GRIDLIB_LOG_CHANNEL, "FindCellsConnected: topN=%d returned=%d visited=%d inserted=%d rejReach=%d rejDist=%d time=%.2fms",
		topN, resultCount, cellsVisited, cellsInsertedCount, cellsRejectReach, cellsRejectDist, ms_total);

	return resultCount;
}

/**
 * Cleanup grid system
 * Call this in OnMapEnd()
 */
stock void GridLib_Cleanup()
{
	if (g_GridCells != null)
	{
		delete g_GridCells;
		g_GridCells = null;
	}

	if (g_SpatialHash != null)
	{
		for (int i = 0; i < g_SpatialHash.Length; i++)
		{
			ArrayList bucket = g_SpatialHash.Get(i);
			if (bucket != null)
				delete bucket;
		}
		delete g_SpatialHash;
		g_SpatialHash = null;
	}

	if (g_NavAreaCells != null)
	{
		StringMapSnapshot snap = g_NavAreaCells.Snapshot();
		char key[20];
		for (int i = 0; i < snap.Length; i++)
		{
			snap.GetKey(i, key, sizeof(key));
			ArrayList cellList;
			if (g_NavAreaCells.GetValue(key, cellList) && cellList != null)
				delete cellList;
		}
		delete snap;
		delete g_NavAreaCells;
		g_NavAreaCells = null;
	}

	// Free nav-reach nested maps
	if (g_NavReach != null)
	{
		StringMapSnapshot reachSnap = g_NavReach.Snapshot();
		char reachKey[20];
		for (int i = 0; i < reachSnap.Length; i++)
		{
			reachSnap.GetKey(i, reachKey, sizeof(reachKey));
			StringMap inner;
			if (g_NavReach.GetValue(reachKey, inner) && inner != null)
				delete inner;
		}
		delete reachSnap;
		delete g_NavReach;
		g_NavReach = null;
	}

	if (g_NavReachPending != null)
	{
		delete g_NavReachPending;
		g_NavReachPending = null;
	}
	g_NavReachReady = false;
	g_NavReachCursor = 0;

	g_IsReady = false;
	g_TotalCells = 0;
	g_IsPrecomputing = false;

	Log_Info(GRIDLIB_LOG_CHANNEL, "Cleaned up");
}


/**
 * Run bounded Dijkstra from one nav area, writing reachable (target, pathDist) pairs
 * into a StringMap. Uses Euclidean center-to-center distance as edge cost.
 * Areas farther than D_max are pruned. Self-distance (seed -> seed) is NOT stored.
 */
static void GridLib_BuildNavReachForArea(Address seed, float D_max, StringMap out)
{
	// visited: key=hex(addr) -> float dist
	StringMap visited = new StringMap();

	ArrayList frontierAddr = new ArrayList();
	ArrayList frontierDist = new ArrayList();
	ArrayList adjAreas = new ArrayList();

	char key[20];
	FormatEx(key, sizeof(key), "%x", seed);
	visited.SetValue(key, 0.0);
	frontierAddr.Push(seed);
	frontierDist.Push(0.0);

	float seedCenter[3], curCenter[3], adjCenter[3];
	L4D_GetNavAreaCenter(seed, seedCenter);

	while (frontierAddr.Length > 0)
	{
		int minIdx = 0;
		float minDist = frontierDist.Get(0);
		for (int i = 1; i < frontierAddr.Length; i++)
		{
			float d = frontierDist.Get(i);
			if (d < minDist) { minDist = d; minIdx = i; }
		}

		Address cur = frontierAddr.Get(minIdx);
		float curDist = minDist;
		frontierAddr.Erase(minIdx);
		frontierDist.Erase(minIdx);

		FormatEx(key, sizeof(key), "%x", cur);
		float recorded;
		if (!visited.GetValue(key, recorded) || curDist > recorded)
			continue;

		L4D_GetNavAreaCenter(cur, curCenter);

		for (int dir = 0; dir < 4; dir++)
		{
			adjAreas.Clear();
			L4D_NavArea_GetAdjacentAreas(cur, dir, adjAreas);

			for (int i = 0; i < adjAreas.Length; i++)
			{
				Address adj = adjAreas.Get(i);
				if (adj == seed) continue;

				L4D_GetNavAreaCenter(adj, adjCenter);
				float edgeCost = GetVectorDistance(curCenter, adjCenter);
				float newDist = curDist + edgeCost;
				if (newDist >= D_max) continue;

				FormatEx(key, sizeof(key), "%x", adj);
				float existing;
				if (visited.GetValue(key, existing) && existing <= newDist)
					continue;

				visited.SetValue(key, newDist);
				frontierAddr.Push(adj);
				frontierDist.Push(newDist);
			}
		}
	}

	char seedKeyStr[20];
	FormatEx(seedKeyStr, sizeof(seedKeyStr), "%x", seed);
	StringMapSnapshot snap = visited.Snapshot();
	for (int i = 0; i < snap.Length; i++)
	{
		char k[20];
		snap.GetKey(i, k, sizeof(k));
		if (StrEqual(k, seedKeyStr))
			continue;
		float d;
		visited.GetValue(k, d);
		out.SetValue(k, d);
	}

	delete snap;
	delete visited;
	delete frontierAddr;
	delete frontierDist;
	delete adjAreas;
}

/**
 * Sliced precompute: process GRIDLIB_NAV_REACH_PER_TICK areas per fire,
 * or until GRIDLIB_NAV_REACH_SLICE_MS elapses, whichever comes first.
 * Repeats itself until all pending areas are Dijkstra'd, then flips g_NavReachReady.
 */
static Action GridLib_Timer_PrecomputeNavReach(Handle timer)
{
	if (g_NavReachPending == null || g_NavReachReady)
		return Plugin_Stop;

	float t_start = GetEngineTime();
	int processedThisTick = 0;

	while (g_NavReachCursor < g_NavReachPending.Length
	       && processedThisTick < GRIDLIB_NAV_REACH_PER_TICK
	       && (GetEngineTime() - t_start) * 1000.0 < GRIDLIB_NAV_REACH_SLICE_MS)
	{
		Address area = g_NavReachPending.Get(g_NavReachCursor);
		g_NavReachCursor++;
		processedThisTick++;

		StringMap inner = new StringMap();
		GridLib_BuildNavReachForArea(area, GRIDLIB_NAV_REACH_MAX, inner);

		char key[20];
		FormatEx(key, sizeof(key), "%x", area);
		g_NavReach.SetValue(key, inner);
	}

	if (g_NavReachCursor >= g_NavReachPending.Length)
	{
		g_NavReachReady = true;
		Log_Info(GRIDLIB_LOG_CHANNEL, "Nav reach precompute complete: %d source areas (D_max=%.0f), took %f ms",
			g_NavReachCursor, GRIDLIB_NAV_REACH_MAX, (GetEngineTime()-t_start)*1000.0);
		delete g_NavReachPending;
		g_NavReachPending = null;
		g_NavReachCursor = 0;
		return Plugin_Stop;
	}

	Log_Trace(GRIDLIB_LOG_CHANNEL, "Nav reach precompute: cursor=%d/%d (tick=%.2fms)",
		g_NavReachCursor, g_NavReachPending.Length,
		(GetEngineTime() - t_start) * 1000.0);
	return Plugin_Continue;
}

// ============================================================================
// Private Implementation
// ============================================================================

static Action GridLib_Timer_StartPrecompute(Handle timer)
{
	Log_Info(GRIDLIB_LOG_CHANNEL, "Starting pre-computation");
	g_IsPrecomputing = true;

	CreateTimer(0.1, GridLib_Timer_Precompute, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

static Action GridLib_Timer_Precompute(Handle timer)
{
	float startTime = GetEngineTime();

	// Get all nav areas
	ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
	int totalAreas = allAreas.Length;

	Log_Info(GRIDLIB_LOG_CHANNEL, "Found %d nav areas", totalAreas);

	// Calculate map bounds
	GridLib_CalculateMapBounds(allAreas);

	// Initialize spatial hash
	GridLib_InitializeSpatialHash();

	// Subdivide nav areas into cells
	int cellsCreated = 0;
	int areasProcessed = 0;
	int areasSkipped = 0;
	int cellsExcluded = 0;

	for (int i = 0; i < totalAreas; i++)
	{
		Address navArea = allAreas.Get(i);
		int cellsInArea = GridLib_SubdivideNavArea(navArea, cellsExcluded);

		if (cellsInArea > 0)
		{
			cellsCreated += cellsInArea;
			areasProcessed++;
		}
		else
		{
			areasSkipped++;
		}

		// Progress indicator
		if ((i + 1) % 500 == 0)
		{
			Log_Debug(GRIDLIB_LOG_CHANNEL, "Processed %d/%d areas (%d cells)",
			          i + 1, totalAreas, cellsCreated);
		}

		// Safety limit
		if (cellsCreated >= GRIDLIB_MAX_CELLS)
		{
			Log_Warn(GRIDLIB_LOG_CHANNEL, "Cell limit reached (%d)", GRIDLIB_MAX_CELLS);
			break;
		}
	}

	delete allAreas;

	g_TotalCells = cellsCreated;
	g_IsReady = true;
	g_IsPrecomputing = false;

	float duration = GetEngineTime() - startTime;
	Log_Info(GRIDLIB_LOG_CHANNEL, "Pre-computation complete");
	Log_Info(GRIDLIB_LOG_CHANNEL, "Cells: %d | Areas: %d | Skipped: %d | Excluded (obstructed): %d | Duration: %.2fs",
	          g_TotalCells, areasProcessed, areasSkipped, cellsExcluded, duration);

	// Log nav area stats
	if (g_NavAreaCells != null)
	{
		StringMapSnapshot navSnap = g_NavAreaCells.Snapshot();
		int maxCells = 0;
		int totalNavCells = 0;
		char maxKey[20];
		for (int s = 0; s < navSnap.Length; s++)
		{
			char sKey[20];
			navSnap.GetKey(s, sKey, sizeof(sKey));
			ArrayList sCellList;
			g_NavAreaCells.GetValue(sKey, sCellList);
			int sCount = sCellList.Length;
			totalNavCells += sCount;
			if (sCount > maxCells)
			{
				maxCells = sCount;
				maxKey = sKey;
			}
		}
		Log_Info(GRIDLIB_LOG_CHANNEL, "Nav area stats: %d areas, %d total cells, largest=%s with %d cells, avg=%.1f",
			navSnap.Length, totalNavCells, maxKey, maxCells, float(totalNavCells) / float(navSnap.Length));
		delete navSnap;
	}

	// --- Kick off nav-reach precompute in a separate sliced timer ---
	if (g_NavReach != null)
	{
		StringMapSnapshot oldSnap = g_NavReach.Snapshot();
		char oldKey[20];
		for (int i = 0; i < oldSnap.Length; i++)
		{
			oldSnap.GetKey(i, oldKey, sizeof(oldKey));
			StringMap oldInner;
			if (g_NavReach.GetValue(oldKey, oldInner) && oldInner != null)
				delete oldInner;
		}
		delete oldSnap;
		delete g_NavReach;
	}
	if (g_NavReachPending != null)
		delete g_NavReachPending;

	g_NavReach = new StringMap();
	g_NavReachPending = new ArrayList();
	g_NavReachCursor = 0;
	g_NavReachReady = false;

	ArrayList navAreasForReach = new ArrayList();
	L4D_GetAllNavAreas(navAreasForReach);
	for (int i = 0; i < navAreasForReach.Length; i++)
		g_NavReachPending.Push(navAreasForReach.Get(i));
	delete navAreasForReach;

	Log_Info(GRIDLIB_LOG_CHANNEL, "Starting nav-reach precompute for %d areas", g_NavReachPending.Length);
	CreateTimer(0.1, GridLib_Timer_PrecomputeNavReach, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

static void GridLib_CalculateMapBounds(ArrayList navAreas)
{
	g_MapMin[0] = 999999.0;
	g_MapMin[1] = 999999.0;
	g_MapMin[2] = 999999.0;
	g_MapMax[0] = -999999.0;
	g_MapMax[1] = -999999.0;
	g_MapMax[2] = -999999.0;

	for (int i = 0; i < navAreas.Length; i++)
	{
		Address navArea = navAreas.Get(i);
		float navPos[3], navSize[3];
		L4D_GetNavAreaPos(navArea, navPos);
		L4D_GetNavAreaSize(navArea, navSize);

		if (navPos[0] < g_MapMin[0]) g_MapMin[0] = navPos[0];
		if (navPos[1] < g_MapMin[1]) g_MapMin[1] = navPos[1];
		if (navPos[2] < g_MapMin[2]) g_MapMin[2] = navPos[2];

		float maxX = navPos[0] + navSize[0];
		float maxY = navPos[1] + navSize[1];
		float maxZ = navPos[2] + navSize[2];

		if (maxX > g_MapMax[0]) g_MapMax[0] = maxX;
		if (maxY > g_MapMax[1]) g_MapMax[1] = maxY;
		if (maxZ > g_MapMax[2]) g_MapMax[2] = maxZ;
	}

	Log_Info(GRIDLIB_LOG_CHANNEL, "Map bounds: (%.0f, %.0f, %.0f) to (%.0f, %.0f, %.0f)",
	          g_MapMin[0], g_MapMin[1], g_MapMin[2],
	          g_MapMax[0], g_MapMax[1], g_MapMax[2]);
}

static void GridLib_InitializeSpatialHash()
{
	float mapWidth = g_MapMax[0] - g_MapMin[0];
	float mapHeight = g_MapMax[1] - g_MapMin[1];

	g_HashGridWidth = RoundToCeil(mapWidth / GRIDLIB_SPATIAL_BUCKET_SIZE) + 1;
	g_HashGridHeight = RoundToCeil(mapHeight / GRIDLIB_SPATIAL_BUCKET_SIZE) + 1;

	int totalBuckets = g_HashGridWidth * g_HashGridHeight;

	for (int i = 0; i < totalBuckets; i++)
	{
		ArrayList bucket = new ArrayList();
		g_SpatialHash.Push(bucket);
	}

	Log_Info(GRIDLIB_LOG_CHANNEL, "Spatial hash: %dx%d (%d buckets)",
	          g_HashGridWidth, g_HashGridHeight, totalBuckets);
}

/**
 * Compute the overall slope normal for a sloped nav area (stairs, ramps).
 * Individual step treads are flat (0,0,1) but we want the overall slope angle.
 */
static void GridLib_ComputeSlopeNormal(const float navSize[3], float slopeNormal[3])
{
	bool slopeAlongX = (navSize[0] >= navSize[1]);
	float slopeLen = slopeAlongX ? navSize[0] : navSize[1];
	float dZ = navSize[2];

	// Degenerate nav area (zero horizontal extent): fall back to world-up.
	if (slopeLen < 0.001)
	{
		slopeNormal[0] = 0.0;
		slopeNormal[1] = 0.0;
		slopeNormal[2] = 1.0;
		return;
	}

	if (slopeAlongX)
	{
		slopeNormal[0] = -dZ;
		slopeNormal[1] = 0.0;
		slopeNormal[2] = slopeLen;
	}
	else
	{
		slopeNormal[0] = 0.0;
		slopeNormal[1] = -dZ;
		slopeNormal[2] = slopeLen;
	}

	float len = SquareRoot(slopeNormal[0]*slopeNormal[0] +
	                       slopeNormal[1]*slopeNormal[1] +
	                       slopeNormal[2]*slopeNormal[2]);
	if (len > 0.001)
	{
		slopeNormal[0] /= len;
		slopeNormal[1] /= len;
		slopeNormal[2] /= len;
	}

	// slopeNormal[2] = slopeLen / len > 0 by construction, so no upward-flip needed.
}

/**
 * Compute how much to lift the hull check on slopes to clear adjacent step risers.
 * Over half the hull width (16 units), the Z changes by |dZ/dHorizontal| * 16.
 */
static float GridLib_ComputeSlopeHullLift(const float navSize[3])
{
	bool slopeAlongX = (navSize[0] >= navSize[1]);
	float slopeAxisLen = slopeAlongX ? navSize[0] : navSize[1];
	if (slopeAxisLen > 0.0)
		return FloatAbs(navSize[2]) / slopeAxisLen * 16.0;
	return 0.0;
}

/**
 * Z-trace downward at (x, y) within [zBottom, zTop] and return the hit Z.
 * Returns false if no ground is hit.
 */
static bool GridLib_SampleCornerZ(float x, float y, float zTop, float zBottom, float &outZ)
{
	float start[3], end[3];
	start[0] = x; start[1] = y; start[2] = zTop;
	end[0]   = x; end[1]   = y; end[2]   = zBottom;

	Handle trace = TR_TraceRayFilterEx(start, end, MASK_NPCSOLID,
	                                   RayType_EndPoint, GridLib_TraceFilter_NoPlayersNoPhysicsProps);

	bool ok = false;
	if (TR_DidHit(trace) && !TR_StartSolid(trace))
	{
		float hitPos[3];
		TR_GetEndPosition(hitPos, trace);
		outZ = hitPos[2];
		ok = true;
	}
	delete trace;
	return ok;
}

/**
 * Compute the slope normal from real corner Z samples. Samples Z at the four
 * inset corners of the nav area; derives the plane normal from the XY gradient.
 * Falls back to GridLib_ComputeSlopeNormal(navSize, ...) if any sample missed.
 *
 * Inset (8 units) keeps the traces off the nav boundary where adjacent-area
 * geometry can cause spurious hits.
 */
static void GridLib_SlopeNormalFromCorners(const float navPos[3], const float navSize[3],
                                            float zTop, float zBottom,
                                            float slopeNormal[3])
{
	float inset = 8.0;
	float x0 = navPos[0] + inset;
	float x1 = navPos[0] + navSize[0] - inset;
	float y0 = navPos[1] + inset;
	float y1 = navPos[1] + navSize[1] - inset;

	// Degenerate (very small) nav area: fall back.
	if (x1 - x0 < 1.0 || y1 - y0 < 1.0)
	{
		GridLib_ComputeSlopeNormal(navSize, slopeNormal);
		return;
	}

	float nwZ, neZ, swZ, seZ;
	bool ok =  GridLib_SampleCornerZ(x0, y0, zTop, zBottom, nwZ);
	ok = ok && GridLib_SampleCornerZ(x1, y0, zTop, zBottom, neZ);
	ok = ok && GridLib_SampleCornerZ(x0, y1, zTop, zBottom, swZ);
	ok = ok && GridLib_SampleCornerZ(x1, y1, zTop, zBottom, seZ);

	if (!ok)
	{
		GridLib_ComputeSlopeNormal(navSize, slopeNormal);
		return;
	}

	// Average Z gradient along each axis (uses both edge pairs, robust to
	// non-planar quads where all four corners aren't coplanar).
	float dzX = ((neZ - nwZ) + (seZ - swZ)) * 0.5;
	float dzY = ((swZ - nwZ) + (seZ - neZ)) * 0.5;
	float dx = x1 - x0;
	float dy = y1 - y0;

	// Plane normal from gradient: n = (-dz/dx, -dz/dy, 1), then normalize.
	slopeNormal[0] = -dzX / dx;
	slopeNormal[1] = -dzY / dy;
	slopeNormal[2] = 1.0;

	float len = SquareRoot(slopeNormal[0]*slopeNormal[0] +
	                       slopeNormal[1]*slopeNormal[1] +
	                       slopeNormal[2]*slopeNormal[2]);
	if (len > 0.001)
	{
		slopeNormal[0] /= len;
		slopeNormal[1] /= len;
		slopeNormal[2] /= len;
	}
	else
	{
		slopeNormal[0] = 0.0;
		slopeNormal[1] = 0.0;
		slopeNormal[2] = 1.0;
	}
}

/**
 * Find the ground Z at a cell's XY position using 4-band traces.
 * Picks the hit closest to the expected Z (from slope interpolation)
 * to avoid ceilings (too high) and lower steps visible through gaps (too low).
 *
 * @param cellPos        Cell XY position (Z is written on output)
 * @param navPos         Nav area position
 * @param navSize        Nav area size
 * @param isSloped       Whether the nav area is sloped
 * @param zTop           Top of trace range
 * @param bandHeight     Height of each trace band
 * @param zMin           Min Z of nav area
 * @param zMax           Max Z of nav area
 * @param navArea        Nav area address (for center Z fallback)
 * @param surfaceNormal  Output: surface normal at hit point
 */
static void GridLib_FindGroundZ(float cellPos[3],
                                 const float navPos[3],
                                 const float navSize[3],
                                 bool isSloped,
                                 float zTop, float bandHeight,
                                 float zMin, float zMax,
                                 Address navArea,
                                 float surfaceNormal[3])
{
	float bestHitZ = -999999.0;
	float bestHitDist = 999999.0;
	bool groundFound = false;

	// Compute expected Z from slope interpolation
	float expectedZ;
	if (isSloped)
	{
		bool slopeAlongX = (navSize[0] >= navSize[1]);
		float frac;
		if (slopeAlongX)
			frac = (cellPos[0] - navPos[0]) / navSize[0];
		else
			frac = (cellPos[1] - navPos[1]) / navSize[1];
		if (frac < 0.0) frac = 0.0;
		if (frac > 1.0) frac = 1.0;
		expectedZ = navPos[2] + frac * navSize[2];
	}
	else
	{
		expectedZ = navPos[2] + navSize[2] * 0.5;
	}

	float trBandStart[3], trBandEnd[3];
	trBandStart[0] = cellPos[0];
	trBandStart[1] = cellPos[1];
	trBandEnd[0] = cellPos[0];
	trBandEnd[1] = cellPos[1];

	for (int band = 0; band < 4; band++)
	{
		trBandStart[2] = zTop - float(band) * bandHeight;
		trBandEnd[2]   = zTop - float(band + 1) * bandHeight;

		Handle trace = TR_TraceRayFilterEx(trBandStart, trBandEnd, MASK_NPCSOLID,
		                                   RayType_EndPoint, GridLib_TraceFilter_NoPlayersNoPhysicsProps);

		if (TR_DidHit(trace) && !TR_StartSolid(trace))
		{
			float hitPos[3];
			TR_GetEndPosition(hitPos, trace);

			if (hitPos[2] >= zMin - 30.0 && hitPos[2] <= zMax + 30.0)
			{
				float traceNormal[3];
				TR_GetPlaneNormal(trace, traceNormal);
				float normalLen = SquareRoot(traceNormal[0]*traceNormal[0] +
				                             traceNormal[1]*traceNormal[1] +
				                             traceNormal[2]*traceNormal[2]);

				if (normalLen > 0.5 && traceNormal[2] > 0.3)
				{
					float dist = FloatAbs(hitPos[2] - expectedZ);
					if (!groundFound || dist < bestHitDist)
					{
						bestHitZ = hitPos[2];
						bestHitDist = dist;
						groundFound = true;

						surfaceNormal[0] = traceNormal[0];
						surfaceNormal[1] = traceNormal[1];
						surfaceNormal[2] = traceNormal[2];
					}
				}
			}
		}

		delete trace;
	}

	if (groundFound)
	{
		float verticalOffset = g_HeightOffset;
		if (surfaceNormal[2] > 0.1)
		{
			verticalOffset = g_HeightOffset / surfaceNormal[2];
			if (verticalOffset > g_HeightOffset * 3.0)
				verticalOffset = g_HeightOffset * 3.0;
		}
		cellPos[2] = bestHitZ + verticalOffset;
	}
	else
	{
		float centerPos[3];
		L4D_GetNavAreaCenter(navArea, centerPos);
		cellPos[2] = centerPos[2] + g_HeightOffset;
	}
}

/**
 * Clamp cell position, check obstruction, and store the cell.
 *
 * @return true if cell was stored, false if excluded by obstruction
 */
static bool GridLib_CheckAndStoreCell(float cellPos[3],
                                       const float surfaceNormal[3],
                                       const float navPos[3],
                                       const float navSize[3],
                                       float slopeHullLift,
                                       Address navArea,
                                       int &excludedCount)
{
	// Clamp to nav area bounds
	if (cellPos[0] < navPos[0])
		cellPos[0] = navPos[0] + 8.0;
	if (cellPos[0] > navPos[0] + navSize[0])
		cellPos[0] = navPos[0] + navSize[0] - 8.0;

	if (cellPos[1] < navPos[1])
		cellPos[1] = navPos[1] + 8.0;
	if (cellPos[1] > navPos[1] + navSize[1])
		cellPos[1] = navPos[1] + navSize[1] - 8.0;

	// Hull trace for obstruction (on slopes, lift to clear step risers)
	bool isObstructed = false;
	if (g_CheckObstruction)
	{
		float obstructionPos[3];
		obstructionPos[0] = cellPos[0];
		obstructionPos[1] = cellPos[1];
		obstructionPos[2] = cellPos[2] + slopeHullLift;
		isObstructed = GridLib_IsObstructed(obstructionPos);
	}

	if (isObstructed && g_ExcludeObstructed)
	{
		excludedCount++;
		return false;
	}

	// Store cell
	GridCell cell;
	cell.position[0] = cellPos[0];
	cell.position[1] = cellPos[1];
	cell.position[2] = cellPos[2];
	cell.navArea = navArea;
	cell.isObstructed = isObstructed;
	cell.normal[0] = surfaceNormal[0];
	cell.normal[1] = surfaceNormal[1];
	cell.normal[2] = surfaceNormal[2];
	cell.cluster = (hGetClusterForOrigin != null) ? PVS_GetClusterForOrigin(cellPos) : -1;
	cell.isUnderwater = GridLib_IsUnderwater(cellPos);

	int cellIndex = g_GridCells.PushArray(cell);
	GridLib_AddCellToHash(cellIndex, cellPos);
	GridLib_AddCellToNavMap(cellIndex, navArea);

	return true;
}

static int GridLib_SubdivideNavArea(Address navArea, int &excludedCount)
{
	// Skip saferooms
	int attributes = L4D_GetNavArea_SpawnAttributes(navArea);
	if (attributes & GRIDLIB_NAV_CHECKPOINT)
		return 0;

	float navPos[3], navSize[3];
	L4D_GetNavAreaPos(navArea, navPos);
	L4D_GetNavAreaSize(navArea, navSize);

	// Grid dimensions and spacing
	int cellsX = RoundToFloor(navSize[0] / GRIDLIB_CELL_SIZE);
	int cellsY = RoundToFloor(navSize[1] / GRIDLIB_CELL_SIZE);
	if (cellsX < 1) cellsX = 1;
	if (cellsY < 1) cellsY = 1;
	float spacingX = navSize[0] / float(cellsX);
	float spacingY = navSize[1] / float(cellsY);

	// Z trace band setup
	float zMin = navPos[2];
	float zMax = navPos[2] + navSize[2];
	if (zMin > zMax) { float tmp = zMin; zMin = zMax; zMax = tmp; }
	float zTop = zMax + 20.0;
	float bandHeight = (zTop - (zMin - 20.0)) / 4.0;

	// Slope properties
	bool isSloped = (FloatAbs(navSize[2]) > 8.0);
	float slopeNormal[3] = {0.0, 0.0, 1.0};
	float slopeHullLift = 0.0;
	if (isSloped)
	{
		GridLib_SlopeNormalFromCorners(navPos, navSize, zTop, zMin - 20.0, slopeNormal);
		slopeHullLift = GridLib_ComputeSlopeHullLift(navSize);
	}

	int cellsCreated = 0;
	int cellsAttempted = 0;
	int cellsSkippedObstruction = 0;

	for (int x = 0; x < cellsX; x++)
	{
		for (int y = 0; y < cellsY; y++)
		{
			cellsAttempted++;

			float cellPos[3];
			cellPos[0] = navPos[0] + (float(x) + 0.5) * spacingX;
			cellPos[1] = navPos[1] + (float(y) + 0.5) * spacingY;

			// Find ground Z via 4-band traces
			float surfaceNormal[3] = {0.0, 0.0, 1.0};
			GridLib_FindGroundZ(cellPos, navPos, navSize, isSloped,
			                    zTop, bandHeight, zMin, zMax,
			                    navArea, surfaceNormal);

			// Use computed slope normal only if the trace returned a flat surface
			// (e.g. stair treads). If the trace found an actual slope (ramp), keep it.
			if (isSloped && surfaceNormal[2] > 0.95)
			{
				surfaceNormal[0] = slopeNormal[0];
				surfaceNormal[1] = slopeNormal[1];
				surfaceNormal[2] = slopeNormal[2];
			}

			// Clamp, check obstruction, and store
			if (GridLib_CheckAndStoreCell(cellPos, surfaceNormal, navPos, navSize,
			                              slopeHullLift, navArea, excludedCount))
			{
				cellsCreated++;
			}
			else
			{
				cellsSkippedObstruction++;
			}
		}
	}

	return cellsCreated;
}

static void GridLib_AddCellToHash(int cellIndex, const float pos[3])
{
	int bucketX = RoundToFloor((pos[0] - g_MapMin[0]) / GRIDLIB_SPATIAL_BUCKET_SIZE);
	int bucketY = RoundToFloor((pos[1] - g_MapMin[1]) / GRIDLIB_SPATIAL_BUCKET_SIZE);

	// Clamp to grid bounds
	if (bucketX < 0) bucketX = 0;
	if (bucketY < 0) bucketY = 0;
	if (bucketX >= g_HashGridWidth) bucketX = g_HashGridWidth - 1;
	if (bucketY >= g_HashGridHeight) bucketY = g_HashGridHeight - 1;

	int bucketIndex = bucketY * g_HashGridWidth + bucketX;

	ArrayList bucket = g_SpatialHash.Get(bucketIndex);
	bucket.Push(cellIndex);
}

static void GridLib_AddCellToNavMap(int cellIndex, Address navArea)
{
	char navKey[20];
	FormatEx(navKey, sizeof(navKey), "%x", navArea);

	ArrayList cellList;
	if (!g_NavAreaCells.GetValue(navKey, cellList))
	{
		cellList = new ArrayList();
		g_NavAreaCells.SetValue(navKey, cellList);
	}
	cellList.Push(cellIndex);
}

/**
 * Check whether a position is inside a water brush.
 *
 * @param pos    Floor-level position to test (typically a cell position)
 * @return       true if the sample point is submerged
 */
static bool GridLib_IsUnderwater(const float pos[3])
{
	float sample[3];
	sample[0] = pos[0];
	sample[1] = pos[1];
	sample[2] = pos[2] + 8.0;

	float endPos[3];
	endPos[0] = sample[0];
	endPos[1] = sample[1];
	endPos[2] = sample[2] + 1.0;

	Handle trace = TR_TraceRayEx(sample, endPos, MASK_WATER, RayType_EndPoint);
	bool underwater = TR_StartSolid(trace);
	delete trace;
	return underwater;
}

static bool GridLib_IsObstructed(const float pos[3])
{
	float mins[3] = {GRIDLIB_HULL_MIN_X, GRIDLIB_HULL_MIN_Y, GRIDLIB_HULL_MIN_Z};
	float maxs[3] = {GRIDLIB_HULL_MAX_X, GRIDLIB_HULL_MAX_Y, GRIDLIB_HULL_MAX_Z};

	// Use MASK_NPCSOLID instead of MASK_PLAYERSOLID to avoid player clip brushes
	// Zombies/NPCs use monster clips, not player clips
	Handle trace = TR_TraceHullFilterEx(pos, pos, mins, maxs, MASK_NPCSOLID,
	                                    GridLib_TraceFilter_NoPlayers);

	bool isBlocked = false;
	if (TR_DidHit(trace))
	{
		int hitEntity = TR_GetEntityIndex(trace);

		if (hitEntity == 0)
		{
			int surfaceFlags = TR_GetSurfaceFlags(trace);

			if (!(surfaceFlags & GRIDLIB_SURF_NODRAW) &&
			    !(surfaceFlags & GRIDLIB_SURF_HINT) &&
			    !(surfaceFlags & GRIDLIB_SURF_SKIP))
			{
				isBlocked = true;
			}
		}
		else
		{
			// Skip physics props (movable at runtime, handled by spawn-time adjustment)
			char className[32];
			GetEntityClassname(hitEntity, className, sizeof(className));
			if (strncmp(className, "prop_physics", 12) != 0 &&
			    !StrEqual(className, "prop_car_alarm"))
				isBlocked = true;
		}
	}

	delete trace;
	return isBlocked;
}

// ============================================================================
// Trace Filters
// ============================================================================

public bool GridLib_TraceFilter_World(int entity, int contentsMask)
{
	return entity == 0;
}

public bool GridLib_TraceFilter_NoPlayers(int entity, int contentsMask)
{
	if (GetEntProp(entity, Prop_Data, "m_nSolidType")==0) return false;
	static char className[32];
    GetEntityClassname(entity, className, sizeof(className));
    if (strcmp(className,"infected")==0) return false;
    if (strcmp(className,"env_player_blocker")==0) return false;
    if (strcmp(className,"env_physics_blocker")==0) return false;
	return (entity > MaxClients || entity == 0);
}

public bool GridLib_TraceFilter_NoPlayersNoPhysicsProps(int entity, int contentsMask)
{
	if (entity == 0) return true;
	if (GetEntProp(entity, Prop_Data, "m_nSolidType")==0) return false;
	if (entity <= MaxClients) return false;
	static char className[32];
	GetEntityClassname(entity, className, sizeof(className));
	if (strncmp(className, "prop_physics", 12) == 0) return false;
	if (StrEqual(className, "prop_car_alarm")) return false;
	if (strcmp(className,"infected")==0) return false;
    if (strcmp(className,"env_player_blocker")==0) return false;
    if (strcmp(className,"env_physics_blocker")==0) return false;
	return true;
}
