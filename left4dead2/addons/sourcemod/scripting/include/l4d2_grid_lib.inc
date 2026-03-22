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
#define GRIDLIB_CELL_SIZE 32.0
#define GRIDLIB_SPATIAL_BUCKET_SIZE 500.0
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
#define GRIDLIB_NAV_BLOCKED_ZOMBIES (GRIDLIB_NAV_SPAWN_PLAYER_START | GRIDLIB_NAV_SPAWN_CHECKPOINT | GRIDLIB_NAV_SPAWN_RESCUE_CLOSET | GRIDLIB_NAV_SPAWN_BATTLESTATION)

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

// ============================================================================
// Public API
// ============================================================================

/**
 * Initialize the grid system
 * Call this in OnMapStart() before StartPrecomputation()
 */
stock void GridLib_Initialize()
{
	if (g_GridCells != null)
		GridLib_Cleanup();

	g_GridCells = new ArrayList(sizeof(GridCell));
	g_SpatialHash = new ArrayList();
	g_IsReady = false;
	g_TotalCells = 0;
	g_IsPrecomputing = false;

	LogMessage("[GridLib] Initialized");
}

/**
 * Start pre-computation
 * Returns true if started, false if already running
 */
stock bool GridLib_StartPrecomputation()
{
	if (g_IsPrecomputing)
		return false;

	if (g_GridCells == null)
		GridLib_Initialize();

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
 * @return              Number of cells found (sorted by distance, closest first)
 */
stock int GridLib_FindNearbyCells(const float position[3],
                                   float searchRadius,
                                   float maxZDiff,
                                   int[] results,
                                   int maxResults)
{
	if (!g_IsReady || g_GridCells == null)
		return 0;

	// Calculate center bucket
	int centerBucketX = RoundToFloor((position[0] - g_MapMin[0]) / GRIDLIB_SPATIAL_BUCKET_SIZE);
	int centerBucketY = RoundToFloor((position[1] - g_MapMin[1]) / GRIDLIB_SPATIAL_BUCKET_SIZE);

	// Search adjacent buckets
	int bucketRadius = RoundToCeil(searchRadius / GRIDLIB_SPATIAL_BUCKET_SIZE);

	// Temporary storage for candidates [distance, cellIndex]
	float candidates[500][2];
	int candidateCount = 0;

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
				if (candidateCount >= 500)
					break;

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

				// Calculate distance
				float distance = GetVectorDistance(position, cell.position);

				candidates[candidateCount][0] = distance;
				candidates[candidateCount][1] = float(cellIdx);
				candidateCount++;
			}

			if (candidateCount >= 500)
				break;
		}

		if (candidateCount >= 500)
			break;
	}

	// Sort by distance (selection sort - simple for small N)
	int numToSelect = (candidateCount < maxResults) ? candidateCount : maxResults;

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

	return numToSelect;
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

	g_IsReady = false;
	g_TotalCells = 0;
	g_IsPrecomputing = false;

	LogMessage("[GridLib] Cleaned up");
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
	LogMessage("[GridLib] Starting pre-computation...");
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

	LogMessage("[GridLib] Found %d nav areas", totalAreas);

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
			LogMessage("[GridLib] Processed %d/%d areas (%d cells)...",
			          i + 1, totalAreas, cellsCreated);
		}

		// Safety limit
		if (cellsCreated >= GRIDLIB_MAX_CELLS)
		{
			LogMessage("[GridLib] WARNING: Cell limit reached (%d)", GRIDLIB_MAX_CELLS);
			break;
		}
	}

	delete allAreas;

	g_TotalCells = cellsCreated;
	g_IsReady = true;
	g_IsPrecomputing = false;

	float duration = GetEngineTime() - startTime;
	LogMessage("[GridLib] Pre-computation complete!");
	LogMessage("[GridLib]   Cells: %d | Areas: %d | Skipped: %d | Excluded (obstructed): %d | Duration: %.2fs",
	          g_TotalCells, areasProcessed, areasSkipped, cellsExcluded, duration);

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

	LogMessage("[GridLib] Map bounds: (%.0f, %.0f, %.0f) to (%.0f, %.0f, %.0f)",
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

	LogMessage("[GridLib] Spatial hash: %dx%d (%d buckets)",
	          g_HashGridWidth, g_HashGridHeight, totalBuckets);
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

	// Calculate grid dimensions
	int cellsX = RoundToFloor(navSize[0] / GRIDLIB_CELL_SIZE);
	int cellsY = RoundToFloor(navSize[1] / GRIDLIB_CELL_SIZE);

	// Minimum 1 cell per dimension
	if (cellsX < 1) cellsX = 1;
	if (cellsY < 1) cellsY = 1;

	// Calculate offsets to center single rows/columns
	float offsetX = 0.0;
	float offsetY = 0.0;

	if (cellsX == 1)
	{
		offsetX = navSize[0] / 2.0;
	}
	else if (cellsY == 1)
	{
		float totalWidth = float(cellsX) * GRIDLIB_CELL_SIZE;
		float leftover = navSize[0] - totalWidth;
		offsetX = leftover / 2.0;
	}

	if (cellsY == 1)
	{
		offsetY = navSize[1] / 2.0;
	}
	else if (cellsX == 1)
	{
		float totalHeight = float(cellsY) * GRIDLIB_CELL_SIZE;
		float leftover = navSize[1] - totalHeight;
		offsetY = leftover / 2.0;
	}

	int cellsCreated = 0;

	for (int x = 0; x < cellsX; x++)
	{
		for (int y = 0; y < cellsY; y++)
		{
			// Calculate cell center position
			float cellPos[3];

			if (cellsX == 1)
			{
				cellPos[0] = navPos[0] + offsetX;
			}
			else if (cellsY == 1)
			{
				cellPos[0] = navPos[0] + offsetX + (float(x) * GRIDLIB_CELL_SIZE) + (GRIDLIB_CELL_SIZE / 2.0);
			}
			else
			{
				float spacingX = navSize[0] / float(cellsX);
				cellPos[0] = navPos[0] + (float(x) + 0.5) * spacingX;
			}

			if (cellsY == 1)
			{
				cellPos[1] = navPos[1] + offsetY;
			}
			else if (cellsX == 1)
			{
				cellPos[1] = navPos[1] + offsetY + (float(y) * GRIDLIB_CELL_SIZE) + (GRIDLIB_CELL_SIZE / 2.0);
			}
			else
			{
				float spacingY = navSize[1] / float(cellsY);
				cellPos[1] = navPos[1] + (float(y) + 0.5) * spacingY;
			}

			// Trace down to find ground (trace from high above to ensure we hit the surface)
			float traceStart[3], traceEnd[3];
			traceStart[0] = cellPos[0];
			traceStart[1] = cellPos[1];
			traceStart[2] = navPos[2] + navSize[2] + 200.0;  // Start well above

			traceEnd[0] = cellPos[0];
			traceEnd[1] = cellPos[1];
			traceEnd[2] = navPos[2] - 200.0;  // End well below

			// Get surface normal from trace
			float surfaceNormal[3] = {0.0, 0.0, 1.0};
			float hitPos[3];  // Declare here so it's accessible later for hull check
			hitPos[2] = navPos[2];  // Default to nav area Z

			// Use MASK_NPCSOLID to avoid player clips (which would block the trace
			// in areas where zombies can actually spawn)
			Handle trace = TR_TraceRayFilterEx(traceStart, traceEnd, MASK_NPCSOLID,
			                                   RayType_EndPoint, GridLib_TraceFilter_World);
			bool traceHit = TR_DidHit(trace);

			if (traceHit)
			{
				TR_GetEndPosition(hitPos, trace);

				// Check if trace hit is within reasonable range of nav area's vertical bounds
				// Allow some tolerance for slopes/uneven terrain, but prevent wrong floor selection
				float tolerance = 100.0;
				float minZ = navPos[2] - tolerance;
				float maxZ = navPos[2] + navSize[2] + tolerance;

				if (hitPos[2] >= minZ && hitPos[2] <= maxZ)
				{
					// Get surface normal first
					float traceNormal[3];
					TR_GetPlaneNormal(trace, traceNormal);

					// Validate normal (must not be zero vector)
					float normalLen = SquareRoot(traceNormal[0]*traceNormal[0] +
					                             traceNormal[1]*traceNormal[1] +
					                             traceNormal[2]*traceNormal[2]);

					if (normalLen > 0.5)  // Valid normal (increase threshold to reject bad normals)
					{
						surfaceNormal[0] = traceNormal[0];
						surfaceNormal[1] = traceNormal[1];
						surfaceNormal[2] = traceNormal[2];

						// Calculate vertical offset needed to lift perpendicular to surface
						// On slopes, we need more Z offset to achieve the same perpendicular distance
						float verticalOffset = g_HeightOffset;
						if (surfaceNormal[2] > 0.1)  // Avoid division by zero
						{
							// To get g_HeightOffset units perpendicular to surface,
							// we need: g_HeightOffset / normal.z units vertical
							verticalOffset = g_HeightOffset / surfaceNormal[2];

							// Clamp to reasonable range (max 3x the base offset)
							if (verticalOffset > g_HeightOffset * 3.0)
								verticalOffset = g_HeightOffset * 3.0;
						}

						cellPos[2] = hitPos[2] + verticalOffset;
					}
					else
					{
						// Degenerate normal, use vertical offset
						surfaceNormal[0] = 0.0;
						surfaceNormal[1] = 0.0;
						surfaceNormal[2] = 1.0;
						cellPos[2] = hitPos[2] + g_HeightOffset;
					}
				}
				else
				{
					// Trace hit something very far away - use nav area Z
					cellPos[2] = navPos[2] + g_HeightOffset;
				}
			}
			else
			{
				// No trace hit - use nav area Z
				cellPos[2] = navPos[2] + g_HeightOffset;
			}
			delete trace;

			// Clamp to nav area bounds
			if (cellPos[0] < navPos[0])
				cellPos[0] = navPos[0] + 8.0;
			if (cellPos[0] > navPos[0] + navSize[0])
				cellPos[0] = navPos[0] + navSize[0] - 8.0;

			if (cellPos[1] < navPos[1])
				cellPos[1] = navPos[1] + 8.0;
			if (cellPos[1] > navPos[1] + navSize[1])
				cellPos[1] = navPos[1] + navSize[1] - 8.0;

			// Hull trace for obstruction
			bool isObstructed = false;
			if (g_CheckObstruction)
			{
			    isObstructed = GridLib_IsObstructed(cellPos);
			}

			// Skip obstructed cells entirely if configured
			if (isObstructed && g_ExcludeObstructed)
			{
				excludedCount++;
				continue;
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

			// Add to spatial hash
			GridLib_AddCellToHash(cellIndex, cellPos);

			cellsCreated++;
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
