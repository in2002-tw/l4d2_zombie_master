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

// ============================================================================
// Constants
// ============================================================================

#define GRIDLIB_VERSION "1.1.0"
//#define GRIDLIB_DEBUG
#if defined GRIDLIB_DEBUG
stock void GridLibLog(const char[] fmt, any ...)
{
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	LogMessage("%s", buffer);
}
#else
stock void GridLibLog(const char[] fmt, any ...) {
	#pragma unused fmt
}
#endif
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

// Zombie hull dimensions
#define GRIDLIB_HULL_MIN_X  -16.0
#define GRIDLIB_HULL_MIN_Y  -16.0
#define GRIDLIB_HULL_MIN_Z    0.0
#define GRIDLIB_HULL_MAX_X   16.0
#define GRIDLIB_HULL_MAX_Y   16.0
#define GRIDLIB_HULL_MAX_Z   72.0

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
		GridLibLog("[GridLib] Initialize skipped - precomputation in progress");
		return;
	}

	if (g_GridCells != null)
		GridLib_Cleanup();

	g_GridCells = new ArrayList(sizeof(GridCell));
	g_SpatialHash = new ArrayList();
	g_NavAreaCells = new StringMap();
	g_IsReady = false;
	g_TotalCells = 0;

	GridLibLog("[GridLib] Initialized");
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
 * @return              Number of cells found (sorted by distance, closest first)
 */
stock int GridLib_FindNearbyCells(const float position[3],
                                   float searchRadius,
                                   float maxZDiff,
                                   int[] results,
                                   int maxResults,
                                   GridLibCellFilter filter = INVALID_FUNCTION)
{
	if (!g_IsReady || g_GridCells == null)
		return 0;

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
	GridLibLog("[GridLib] FindNearbyCells: %d candidates in radius %.0f, maxResults=%d, filter=%s",
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
					GridLibLog("[GridLib] FindNearbyCells: cell %d nav %s blacklisted, skipping", cellIdx, navKey);
					continue;
				}
			}

			float tFilter = GetEngineTime();
			int filterResult = GridLib_CallFilter(filter, cellIdx);
			filterCallTimeAccum += GetEngineTime() - tFilter;
			if (filterResult == GRIDLIB_FILTER_DISCARD_ALL)
			{
				GridLibLog("[GridLib] FindNearbyCells: cell %d DISCARD_ALL - stopping search", cellIdx);
				break;
			}
			if (filterResult == GRIDLIB_FILTER_DISCARD_NAV)
			{
				GridLibLog("[GridLib] FindNearbyCells: cell %d DISCARD_NAV (nav=%x)", cellIdx, cell.navArea);
				if (cell.navArea != Address_Null)
				{
					FormatEx(navKey, sizeof(navKey), "%x", cell.navArea);
					blacklistedNavAreas.SetValue(navKey, 1);
				}
				continue;
			}
			if (filterResult != GRIDLIB_FILTER_KEEP)
			{
				GridLibLog("[GridLib] FindNearbyCells: cell %d DISCARD", cellIdx);
				continue;
			}
			GridLibLog("[GridLib] FindNearbyCells: cell %d KEEP (dist=%.0f)", cellIdx, selected[0]);
		}

		results[resultCount++] = cellIdx;
	}

	float filterMs = (filter != INVALID_FUNCTION) ? (GetEngineTime() - filterT0) * 1000.0 : 0.0;
	float filterCallMs = filterCallTimeAccum * 1000.0;
	GridLibLog("[GridLib] FindNearbyCells: returning %d/%d candidates (scanned %d, %.2f ms, sort=%.2f ms, filter=%.2f ms)",
		resultCount, candidateCount, scanned, filterMs, sortMs, filterCallMs);
	if (filterMs > 5.0)
		LogMessage("[GridLib] WARNING: filter took %.1f ms (scanned %d/%d, returned %d, sort=%.1f ms, filtercb=%.1f ms, overhead=%.1f ms)",
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
 * @return              Number of cells found
 */
stock int GridLib_FindCellsFromClosest(const float position[3],
                                       int desiredCount,
                                       int[] results,
                                       int maxResults,
                                       GridLibCellFilter filter = INVALID_FUNCTION)
{
	GridLibLog("[GridLib] FindCellsFromClosest: pos=(%.0f,%.0f,%.0f) desired=%d maxResults=%d filter=%s",
		position[0], position[1], position[2], desiredCount, maxResults,
		filter != INVALID_FUNCTION ? "yes" : "no");

	if (!g_IsReady || g_GridCells == null || g_NavAreaCells == null)
	{
		GridLibLog("[GridLib] FindCellsFromClosest: not ready (ready=%d cells=%d navmap=%d)",
			g_IsReady, g_GridCells != null, g_NavAreaCells != null);
		return 0;
	}

	// Find the single closest cell
	int closestCell[1];
	int found = GridLib_FindNearbyCells(position, GRIDLIB_SPATIAL_BUCKET_SIZE, 9999.0, closestCell, 1);
	if (found == 0)
	{
		GridLibLog("[GridLib] FindCellsFromClosest: no nearby cell found within bucket size %.0f", GRIDLIB_SPATIAL_BUCKET_SIZE);
		return 0;
	}

	// Get nav area of closest cell
	float cellPos[3], cellNormal[3];
	Address startNavArea;
	bool obstructed;
	if (!GridLib_GetCellData(closestCell[0], cellPos, cellNormal, startNavArea, obstructed))
	{
		GridLibLog("[GridLib] FindCellsFromClosest: failed to get cell data for closest cell %d", closestCell[0]);
		return 0;
	}

	if (startNavArea == Address_Null)
	{
		GridLibLog("[GridLib] FindCellsFromClosest: closest cell %d has null nav area", closestCell[0]);
		return 0;
	}

	GridLibLog("[GridLib] FindCellsFromClosest: closest cell %d at (%.0f,%.0f,%.0f) navArea=%x",
		closestCell[0], cellPos[0], cellPos[1], cellPos[2], startNavArea);

	int cap = desiredCount;
	if (cap > maxResults)
		cap = maxResults;
	if (cap > 500)
		cap = 500;

	// BFS over nav areas to collect cells
	float candidates[500][2]; // [distance, cellIndex]
	int candidateCount = 0;

	StringMap visited = new StringMap();
	ArrayList queue = new ArrayList();
	ArrayList adjAreas = new ArrayList();
	char navKey[20];

	// Nav area blacklist for filter DISCARD_NAV results
	static StringMap blacklistedNavAreas = null;
	if (filter != INVALID_FUNCTION)
	{
		if (blacklistedNavAreas == null)
			blacklistedNavAreas = new StringMap();
		else
			blacklistedNavAreas.Clear();
	}

	float filterT0 = GetEngineTime();

	// Seed BFS with starting nav area
	FormatEx(navKey, sizeof(navKey), "%x", startNavArea);
	visited.SetValue(navKey, true);
	queue.Push(startNavArea);

	int queueIdx = 0;
	int stopAfter = -1; // queue length snapshot when cap was reached
	bool filterAbort = false;
	while (queueIdx < queue.Length && candidateCount < 500 && !filterAbort)
	{
		// Stop after processing one extra BFS ring beyond the cap
		if (stopAfter >= 0 && queueIdx >= stopAfter)
			break;

		Address currentArea = queue.Get(queueIdx);
		queueIdx++;

		// Collect cells from this nav area
		int areaCells[500];
		int areaCellCount = GridLib_GetCellsForNavArea(currentArea, areaCells, 500);
		GridLibLog("[GridLib] FindCellsFromClosest: BFS[%d] navArea=%x cells=%d total=%d",
			queueIdx - 1, currentArea, areaCellCount, candidateCount);

		for (int i = 0; i < areaCellCount && candidateCount < 500; i++)
		{
			// Skip obstructed cells
			GridCell cell;
			g_GridCells.GetArray(areaCells[i], cell, sizeof(GridCell));
			if (cell.isObstructed)
				continue;

			// Skip nav-blocked cells (saferooms, checkpoints, etc.)
			if (cell.navArea != Address_Null)
			{
				int spawnAttrs = L4D_GetNavArea_SpawnAttributes(cell.navArea);
				if (spawnAttrs & GRIDLIB_NAV_BLOCKED_ZOMBIES)
					continue;
			}

			// Apply filter callback
			if (filter != INVALID_FUNCTION)
			{
				// Check nav area blacklist first (O(1) lookup)
				if (cell.navArea != Address_Null)
				{
					FormatEx(navKey, sizeof(navKey), "%x", cell.navArea);
					int dummy;
					if (blacklistedNavAreas.GetValue(navKey, dummy))
						continue;
				}

				int filterResult = GridLib_CallFilter(filter, areaCells[i]);
				if (filterResult == GRIDLIB_FILTER_DISCARD_ALL)
				{
					filterAbort = true;
					break;
				}
				if (filterResult == GRIDLIB_FILTER_DISCARD_NAV)
				{
					if (cell.navArea != Address_Null)
					{
						FormatEx(navKey, sizeof(navKey), "%x", cell.navArea);
						blacklistedNavAreas.SetValue(navKey, 1);
					}
					continue;
				}
				if (filterResult != GRIDLIB_FILTER_KEEP)
					continue;
			}

			float dist = GetVectorDistance(position, cell.position);
			candidates[candidateCount][0] = dist;
			candidates[candidateCount][1] = float(areaCells[i]);
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

		// Once we hit the desired count, snapshot the queue length
		// so we process one more full ring of adjacent areas
		if (stopAfter < 0 && candidateCount >= cap)
			stopAfter = queue.Length;
	}

	float filterMs = (filter != INVALID_FUNCTION) ? (GetEngineTime() - filterT0) * 1000.0 : 0.0;
	GridLibLog("[GridLib] FindCellsFromClosest: BFS done. navAreas=%d candidates=%d cap=%d stopAfter=%d filter=%.2fms",
		queueIdx, candidateCount, cap, stopAfter, filterMs);
	if (filterMs > 5.0)
		LogMessage("[GridLib] WARNING: FindCellsFromClosest filter took %.1f ms (navAreas=%d, candidates=%d)",
			filterMs, queueIdx, candidateCount);

	delete visited;
	delete queue;
	delete adjAreas;

	// Sort by distance (selection sort)
	int numToSelect = (candidateCount < cap) ? candidateCount : cap;

	for (int i = 0; i < numToSelect; i++)
	{
		int minIdx = i;
		for (int j = i + 1; j < candidateCount; j++)
		{
			if (candidates[j][0] < candidates[minIdx][0])
				minIdx = j;
		}

		if (minIdx != i)
		{
			float temp[2];
			temp = candidates[i];
			candidates[i] = candidates[minIdx];
			candidates[minIdx] = temp;
		}

		results[i] = RoundToFloor(candidates[i][1]);
	}

	GridLibLog("[GridLib] FindCellsFromClosest: returning %d cells (closest dist=%.0f, farthest dist=%.0f)",
		numToSelect,
		numToSelect > 0 ? candidates[0][0] : 0.0,
		numToSelect > 0 ? candidates[numToSelect - 1][0] : 0.0);

	return numToSelect;
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

	g_IsReady = false;
	g_TotalCells = 0;
	g_IsPrecomputing = false;

	GridLibLog("[GridLib] Cleaned up");
}

/**
 * Helper: Calculate surface vectors from normal (for rendering)
 * Used to rotate cell rectangles to match surface orientation
 */
stock void GridLib_CalculateSurfaceVectors(const float normal[3], float right[3], float up[3])
{
	// Choose a reference vector that's not parallel to the normal
	float reference[3];

	// If normal is mostly pointing up/down, use world forward (Y-axis)
	if (FloatAbs(normal[2]) > 0.9)
	{
		reference[0] = 0.0;
		reference[1] = 1.0;
		reference[2] = 0.0;
	}
	else
	{
		// Otherwise use world up (Z-axis)
		reference[0] = 0.0;
		reference[1] = 0.0;
		reference[2] = 1.0;
	}

	// Calculate right vector: cross(reference, normal)
	right[0] = reference[1] * normal[2] - reference[2] * normal[1];
	right[1] = reference[2] * normal[0] - reference[0] * normal[2];
	right[2] = reference[0] * normal[1] - reference[1] * normal[0];

	// Normalize right vector
	float rightLen = SquareRoot(right[0]*right[0] + right[1]*right[1] + right[2]*right[2]);
	if (rightLen > 0.0001)
	{
		right[0] /= rightLen;
		right[1] /= rightLen;
		right[2] /= rightLen;
	}

	// Calculate up vector: cross(normal, right)
	up[0] = normal[1] * right[2] - normal[2] * right[1];
	up[1] = normal[2] * right[0] - normal[0] * right[2];
	up[2] = normal[0] * right[1] - normal[1] * right[0];

	// Normalize up vector
	float upLen = SquareRoot(up[0]*up[0] + up[1]*up[1] + up[2]*up[2]);
	if (upLen > 0.0001)
	{
		up[0] /= upLen;
		up[1] /= upLen;
		up[2] /= upLen;
	}
}

// ============================================================================
// Private Implementation
// ============================================================================

static Action GridLib_Timer_StartPrecompute(Handle timer)
{
	GridLibLog("[GridLib] Starting pre-computation...");
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

	GridLibLog("[GridLib] Found %d nav areas", totalAreas);

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
			GridLibLog("[GridLib] Processed %d/%d areas (%d cells)...",
			          i + 1, totalAreas, cellsCreated);
		}

		// Safety limit
		if (cellsCreated >= GRIDLIB_MAX_CELLS)
		{
			GridLibLog("[GridLib] WARNING: Cell limit reached (%d)", GRIDLIB_MAX_CELLS);
			break;
		}
	}

	delete allAreas;

	g_TotalCells = cellsCreated;
	g_IsReady = true;
	g_IsPrecomputing = false;

	float duration = GetEngineTime() - startTime;
	GridLibLog("[GridLib] Pre-computation complete!");
	GridLibLog("[GridLib]   Cells: %d | Areas: %d | Skipped: %d | Excluded (obstructed): %d | Duration: %.2fs",
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
		GridLibLog("[GridLib] Nav area stats: %d areas, %d total cells, largest=%s with %d cells, avg=%.1f",
			navSnap.Length, totalNavCells, maxKey, maxCells, float(totalNavCells) / float(navSnap.Length));
		delete navSnap;
	}

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

	GridLibLog("[GridLib] Map bounds: (%.0f, %.0f, %.0f) to (%.0f, %.0f, %.0f)",
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

	GridLibLog("[GridLib] Spatial hash: %dx%d (%d buckets)",
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

	// Ensure normal points upward
	if (slopeNormal[2] < 0.0)
	{
		slopeNormal[0] = -slopeNormal[0];
		slopeNormal[1] = -slopeNormal[1];
		slopeNormal[2] = -slopeNormal[2];
	}
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

	// Slope properties
	bool isSloped = (FloatAbs(navSize[2]) > 8.0);
	float slopeNormal[3] = {0.0, 0.0, 1.0};
	float slopeHullLift = 0.0;
	if (isSloped)
	{
		GridLib_ComputeSlopeNormal(navSize, slopeNormal);
		slopeHullLift = GridLib_ComputeSlopeHullLift(navSize);
	}

	// Z trace band setup
	float zMin = navPos[2];
	float zMax = navPos[2] + navSize[2];
	if (zMin > zMax) { float tmp = zMin; zMin = zMax; zMax = tmp; }
	float zTop = zMax + 20.0;
	float bandHeight = (zTop - (zMin - 20.0)) / 4.0;

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

	// if (cellsAttempted != cellsCreated)
	// {
	// 	LogMessage("[GridLib] NavArea %x: attempted=%d created=%d skippedObstruction=%d lost=%d (size=%.0fx%.0fx%.0f cellsXY=%dx%d checkObs=%d excludeObs=%d)",
	// 		navArea, cellsAttempted, cellsCreated, cellsSkippedObstruction,
	// 		cellsAttempted - cellsCreated - cellsSkippedObstruction,
	// 		navSize[0], navSize[1], navSize[2], cellsX, cellsY,
	// 		g_CheckObstruction, g_ExcludeObstructed);
	// }

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
			// Skip env_physics_blocker (blocktype toggleable at runtime)
			// and physics props (movable at runtime, handled by spawn-time adjustment)
			char className[32];
			GetEntityClassname(hitEntity, className, sizeof(className));
			if (!StrEqual(className, "env_physics_blocker") &&
			    strncmp(className, "prop_physics", 12) != 0 &&
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
	return (entity > MaxClients || entity == 0);
}

public bool GridLib_TraceFilter_NoPlayersNoPhysicsProps(int entity, int contentsMask)
{
	if (entity == 0) return true;
	if (entity <= MaxClients) return false;
	static char className[32];
	GetEntityClassname(entity, className, sizeof(className));
	if (strncmp(className, "prop_physics", 12) == 0) return false;
	if (StrEqual(className, "prop_car_alarm")) return false;
	return true;
}
