/**
 * Grid Renderer Backend: prop_dynamic + Custom Model
 * Spawns flat colored quad models at cell positions
 *
 * Uses a custom flat quad .mdl (32x32 units) positioned at each cell.
 * Renders as FILLED SOLID colored rectangles instead of wireframe outlines.
 * Per-client visibility via SDKHook_SetTransmit.
 *
 *
 * Model files required in addons/sourcemod/:
 *   models/grid/grid_cell.mdl
 *   models/grid/grid_cell.vvd
 *   models/grid/grid_cell.dx90.vtx
 *   materials/models/grid/grid_cell.vmt
 *   materials/models/grid/grid_cell.vtf
 */

#if defined _l4d2_grid_renderer_prop_included
 #endinput
#endif
#define _l4d2_grid_renderer_prop_included

// SDKHooks for transmit filtering
#include <sdkhooks>

// ============================================================================
// Constants
// ============================================================================

#define GRIDRENDERERPROP_MAX_ENTITIES 25
#define GRIDRENDERERPROP_MODEL "models/grid/grid_cell.mdl"

// Render modes
#define RENDER_NORMAL     0
#define RENDER_TRANSCOLOR 1
#define RENDER_TRANSTEXTURE 2
#define RENDER_TRANSALPHA 4
#define RENDER_TRANSADD   5

// Entity effect flags
#define EF_NOINTERP  8   // Don't interpolate position (snap instantly)
#define EF_NOSHADOW  16  // Don't cast shadows
#define EF_NODRAW    32  // Don't render

// ============================================================================
// Data Structures
// ============================================================================

enum struct PropPool
{
	int entities[GRIDRENDERERPROP_MAX_ENTITIES];      // Entity refs
	int assignedCell[GRIDRENDERERPROP_MAX_ENTITIES];  // Cell index assigned to each entity (-1 = free)
	int activeCount;                                  // Currently visible entities
	int totalAllocated;                               // Total allocated in pool
	bool initialized;                                 // Pool is ready
}

// ============================================================================
// Private State
// ============================================================================

static PropPool g_PropPool[MAXPLAYERS+1];
static int g_Prop_OwnerClient[2049];   // Entity index -> owner client
static bool g_PropModelPrecached = false;
static bool g_PropAlphaFade = true;    // Distance-based alpha fade

// ============================================================================
// Backend Interface
// ============================================================================

/**
 * Enable or disable distance-based alpha fade on cells
 */
stock void GridRendererProp_SetAlphaFade(bool enabled)
{
	g_PropAlphaFade = enabled;
}

stock void GridRendererProp_Init()
{
	for (int i = 0; i <= MaxClients; i++)
	{
		g_PropPool[i].initialized = false;
		g_PropPool[i].totalAllocated = 0;
		g_PropPool[i].activeCount = 0;
		for (int j = 0; j < GRIDRENDERERPROP_MAX_ENTITIES; j++)
			g_PropPool[i].assignedCell[j] = -1;
	}

	for (int i = 0; i < sizeof(g_Prop_OwnerClient); i++)
		g_Prop_OwnerClient[i] = 0;

	// Precache model and add to downloads table
	if (GridRendererProp_PrecacheAssets())
	{
		g_PropModelPrecached = true;
		if (DEBUG) LogMessage("[GridRenderer Prop] Model precached: %s", GRIDRENDERERPROP_MODEL);
	}
	else
	{
		g_PropModelPrecached = false;
		if (DEBUG) LogError("[GridRenderer Prop] Failed to precache model! Backend will be unavailable.");
	}
}

stock void GridRendererProp_Cleanup()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		GridRendererProp_DestroyPool(i);
	}
}

stock void GridRendererProp_OnClientEnabled(int client)
{
	if (!g_PropModelPrecached)
		return;

	GridRendererProp_CreatePool(client);
}

stock void GridRendererProp_OnClientDisabled(int client)
{
	GridRendererProp_DestroyPool(client);
}

/**
 * Draw cells using prop_dynamic entities with stable reconciliation.
 *
 * Entities are stably assigned to GridLib cell indices across frames. If a cell
 * persists between frames, the same entity keeps rendering it (color-only
 * update, no teleport). Only cells that appear/disappear cause entity
 * reassignment, eliminating visual "scrambling" when the grid moves.
 *
 * assignedCell[] stores the GridLib cell index (can be any positive int),
 * NOT the 0-24 position in the cellIndices array.
 */
stock int GridRendererProp_DrawCells(int client,
                                     const int cellIndices[GRIDRENDERER_MAX_CELLS],
                                     const bool cellValid[GRIDRENDERER_MAX_CELLS],
                                     int count,
                                     int closestValidIdx,
                                     const float overridePositions[GRIDRENDERER_MAX_CELLS][3],
                                     const bool hasOverride[GRIDRENDERER_MAX_CELLS],
                                     const bool overrideFlat[GRIDRENDERER_MAX_CELLS],
                                     const float overrideNormals[GRIDRENDERER_MAX_CELLS][3])
{
	if (!g_PropPool[client].initialized || !g_PropModelPrecached)
		return 0;

	int totalEnts = g_PropPool[client].totalAllocated;
	if (totalEnts <= 0)
		return 0;

	// Clamp count to pool size
	if (count > totalEnts)
		count = totalEnts;

	// --- Phase 1: Classify entities as "kept" or "freed" ---
	// An entity is "kept" if its assignedCell matches one of the new cellIndices.
	// We also record which cellIndices[] slot it matched (for color lookup).
	bool entityKept[GRIDRENDERERPROP_MAX_ENTITIES];
	int entityDataIdx[GRIDRENDERERPROP_MAX_ENTITIES]; // index into cellIndices/cellValid for kept entities
	bool cellHandled[GRIDRENDERER_MAX_CELLS];         // which cellIndices slots already have an entity

	for (int i = 0; i < GRIDRENDERER_MAX_CELLS; i++)
		cellHandled[i] = false;

	for (int e = 0; e < totalEnts; e++)
	{
		entityKept[e] = false;
		entityDataIdx[e] = -1;

		int ac = g_PropPool[client].assignedCell[e];
		if (ac < 0)
			continue;

		// Search for this entity's assigned cell in the new cellIndices
		for (int i = 0; i < count; i++)
		{
			if (!cellHandled[i] && cellIndices[i] == ac)
			{
				// Match - keep this entity for this cell
				entityKept[e] = true;
				entityDataIdx[e] = i;
				cellHandled[i] = true;
				break;
			}
		}

		if (!entityKept[e])
		{
			// Cell is gone - free this entity
			g_PropPool[client].assignedCell[e] = -1;
		}
	}

	// --- Phase 2: Assign freed entities to new (unmatched) cells ---
	int freeIdx = 0;
	for (int i = 0; i < count; i++)
	{
		if (cellHandled[i])
			continue;  // Already has a kept entity

		// Find next free entity
		while (freeIdx < totalEnts && entityKept[freeIdx])
			freeIdx++;

		if (freeIdx >= totalEnts)
			break;  // No more free entities

		// Assign this freed entity to the new cell
		g_PropPool[client].assignedCell[freeIdx] = cellIndices[i];
		entityKept[freeIdx] = true;
		entityDataIdx[freeIdx] = i;

		// Get cell data and teleport
		float position[3], normal[3];
		Address navArea;
		bool obstructed;

		if (GridLib_GetCellData(cellIndices[i], position, normal, navArea, obstructed))
		{
			// Apply runtime rescue position override (prop top, etc.)
			if (hasOverride[i])
			{
				position[0] = overridePositions[i][0];
				position[1] = overridePositions[i][1];
				position[2] = overridePositions[i][2];

				if (overrideFlat[i])
				{
					normal[0] = 0.0;
					normal[1] = 0.0;
					normal[2] = 1.0;
				}
				else
				{
					normal[0] = overrideNormals[i][0];
					normal[1] = overrideNormals[i][1];
					normal[2] = overrideNormals[i][2];
				}
			}

			int color[4];
			bool isClosest = (i == closestValidIdx);
			GridRenderer_ResolveColor(cellValid[i], isClosest, color, g_GridCellContext[i]);
			color[3] = GridRendererProp_ComputeAlpha(i, count, isClosest, g_GridCellContext[i]);

			bool glowThis = (isClosest && cellValid[i] && g_iSpawnerMode==2)
			             || GridLib_IsCellUnderwater(cellIndices[i]);

			float angles[3];
			GridRendererProp_NormalToAngles(normal, angles);
			GridRendererProp_UpdateEntity(client, freeIdx, position, angles, color, glowThis);
		}

		freeIdx++;
	}

	// --- Phase 3: Update kept entities (color + teleport if override changed) ---
	int drawn = 0;
	for (int e = 0; e < totalEnts; e++)
	{
		int dataIdx = entityDataIdx[e];
		if (dataIdx < 0)
			continue;  // Unused - will be hidden in Phase 4

		// Update color (and ensure visible)
		int color[4];
		bool isClosest = (dataIdx == closestValidIdx);
		GridRenderer_ResolveColor(cellValid[dataIdx], isClosest, color, g_GridCellContext[dataIdx]);
		color[3] = GridRendererProp_ComputeAlpha(dataIdx, count, isClosest, g_GridCellContext[dataIdx]);

		bool glowThis = (isClosest && cellValid[dataIdx] && g_iSpawnerMode==2)
		             || GridLib_IsCellUnderwater(cellIndices[dataIdx]);

		// If this cell has a rescue position override, teleport to the adjusted position
		if (hasOverride[dataIdx])
		{
			float position[3], normal[3];
			Address navArea;
			bool obstructed;
			if (GridLib_GetCellData(cellIndices[dataIdx], position, normal, navArea, obstructed))
			{
				position[0] = overridePositions[dataIdx][0];
				position[1] = overridePositions[dataIdx][1];
				position[2] = overridePositions[dataIdx][2];

				if (overrideFlat[dataIdx])
				{
					normal[0] = 0.0;
					normal[1] = 0.0;
					normal[2] = 1.0;
				}
				else
				{
					normal[0] = overrideNormals[dataIdx][0];
					normal[1] = overrideNormals[dataIdx][1];
					normal[2] = overrideNormals[dataIdx][2];
				}

				float angles[3];
				GridRendererProp_NormalToAngles(normal, angles);
				GridRendererProp_UpdateEntity(client, e, position, angles, color, glowThis);
			}
			else
			{
				GridRendererProp_UpdateEntityColor(client, e, color, glowThis);
			}
		}
		else
		{
			GridRendererProp_UpdateEntityColor(client, e, color, glowThis);
		}
		drawn++;
	}

	// --- Phase 4: Hide unused entities ---
	for (int e = 0; e < totalEnts; e++)
	{
		if (g_PropPool[client].assignedCell[e] < 0)
			GridRendererProp_HideEntity(client, e);
	}

	g_PropPool[client].activeCount = drawn;
	return drawn;
}

// ============================================================================
// Alpha Helpers
// ============================================================================

/**
 * Compute alpha for a cell based on its distance rank from center.
 * Cells are sorted closest-first, so dataIdx 0 = center, count-1 = edge.
 *
 * @param dataIdx       Index in the sorted cellIndices array (0 = closest)
 * @param count         Total cells being rendered
 * @param isClosest     Whether this is the highlighted (closest valid) cell
 * @return              Alpha value (0-255)
 */
static int GridRendererProp_ComputeAlpha(int dataIdx, int count, bool isClosest, int state = SPAWNER_OK)
{
	if (state==SPAWNER_BUDGET) return 0;
	if (isClosest && g_iSpawnerMode==2) return 220;
	if (!g_PropAlphaFade) return 50;

	// Fade from ALPHA_CENTER (nearest) to ALPHA_EDGE (furthest)
	static const int ALPHA_CENTER = 150;
	static const int ALPHA_EDGE = 35;

	if (count <= 1)
		return ALPHA_CENTER;

	// Linear interpolation: t goes from 0.0 (center) to 1.0 (edge)
	float t = float(dataIdx) / float(count - 1);
	return RoundToNearest(float(ALPHA_CENTER) + t * float(ALPHA_EDGE - ALPHA_CENTER));
}

// ============================================================================
// Asset Management
// ============================================================================

/**
 * Precache model and add files to download table
 */
stock bool GridRendererProp_PrecacheAssets()
{
	// Check if model file exists before trying to precache
	if (!FileExists(GRIDRENDERERPROP_MODEL, true))
	{
		LogError("[GridRenderer Prop] Model file not found: %s", GRIDRENDERERPROP_MODEL);
		LogError("[GridRenderer Prop] To use this backend, create the model files.");
		LogError("[GridRenderer Prop] See RENDERER_BACKENDS.md for details.");
		return false;
	}

	PrecacheModel(GRIDRENDERERPROP_MODEL, true);

	// Add model files to downloads table
	if (FindConVar("sv_allowdownload").BoolValue)
	{
		AddFileToDownloadsTable("models/grid/grid_cell.mdl");
		AddFileToDownloadsTable("models/grid/grid_cell.vvd");
		AddFileToDownloadsTable("models/grid/grid_cell.dx90.vtx");
		AddFileToDownloadsTable("materials/models/grid/grid_cell.vmt");
		AddFileToDownloadsTable("materials/models/grid/grid_cell.vtf");
	}

	return true;
}

// ============================================================================
// Pool Management
// ============================================================================

/**
 * Create the entity pool for a client
 */
static void GridRendererProp_CreatePool(int client)
{
	if (g_PropPool[client].initialized)
		return;

	int created = 0;

	for (int i = 0; i < GRIDRENDERERPROP_MAX_ENTITIES; i++)
	{
		int ent = CreateEntityByName("prop_dynamic_override");
		if (!IsEntitySafe(ent))
		{
			LogError("[GridRenderer Prop] Edict limit reached at %d/%d entities", i, GRIDRENDERERPROP_MAX_ENTITIES);
			break;
		}

		DispatchKeyValue(ent, "model", GRIDRENDERERPROP_MODEL);
		DispatchKeyValue(ent, "solid", "0");            // Not solid
		DispatchKeyValue(ent, "disableshadows", "1");    // No cast shadows
		DispatchKeyValue(ent, "disablereceiveshadows", "1"); // No receive shadows
		DispatchKeyValue(ent, "DisableBoneFollowers", "1"); // Save edicts

		DispatchSpawn(ent);

		// Set render mode for color/alpha support
		SetEntityRenderMode(ent, view_as<RenderMode>(RENDER_TRANSCOLOR));
		SetEntityRenderColor(ent, 0, 255, 0, 150);

		// Start hidden, no shadows, no interpolation
		int effects = GetEntProp(ent, Prop_Send, "m_fEffects");
		SetEntProp(ent, Prop_Send, "m_fEffects", effects | EF_NODRAW | EF_NOSHADOW | EF_NOINTERP);

		// Set up transmit hook for per-client visibility
		g_Prop_OwnerClient[ent] = client;
		SDKHook(ent, SDKHook_SetTransmit, GridRendererProp_OnSetTransmit);

		g_PropPool[client].entities[i] = EntIndexToEntRef(ent);
		created++;
	}

	g_PropPool[client].totalAllocated = created;
	g_PropPool[client].activeCount = 0;
	for (int i = 0; i < GRIDRENDERERPROP_MAX_ENTITIES; i++)
		g_PropPool[client].assignedCell[i] = -1;
	g_PropPool[client].initialized = true;

	if (DEBUG) LogMessage("[GridRenderer Prop] Created pool for client %d: %d entities", client, created);
}

/**
 * Destroy the entity pool for a client
 */
static void GridRendererProp_DestroyPool(int client)
{
	if (!g_PropPool[client].initialized)
		return;

	if (DEBUG) LogMessage("[zm] GridRendererProp_DestroyPool: client=%d, entities=%d",
		                  client, g_PropPool[client].totalAllocated);

	for (int i = 0; i < g_PropPool[client].totalAllocated; i++)
	{
		int ent = EntRefToEntIndex(g_PropPool[client].entities[i]);
		if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
		{
			g_Prop_OwnerClient[ent] = 0;
			RemoveEntity(ent);
		}
	}

	g_PropPool[client].totalAllocated = 0;
	g_PropPool[client].activeCount = 0;
	g_PropPool[client].initialized = false;
}

// ============================================================================
// Entity Updates
// ============================================================================

/**
 * Update a prop entity's position, angle, color, and glow state
 */
static void GridRendererProp_UpdateEntity(int client, int idx,
                                           const float position[3],
                                           const float angles[3],
                                           const int color[4],
                                           bool glow)
{
	int ent = EntRefToEntIndex(g_PropPool[client].entities[idx]);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
		return;

	TeleportEntity(ent, position, angles, NULL_VECTOR);
	SetEntityRenderColor(ent, color[0], color[1], color[2], color[3]);

	int effects = GetEntProp(ent, Prop_Send, "m_fEffects") & ~EF_NODRAW;
	if (g_iSpawnerMode<2) effects = effects | EF_NOSHADOW;
	else effects = effects | EF_NOSHADOW | EF_NOINTERP;
	SetEntProp(ent, Prop_Send, "m_fEffects", effects);

	GridRendererProp_SetGlow(ent, glow, color);
}

/**
 * Update a prop entity's color and glow only (no teleport) and ensure visible
 */
static void GridRendererProp_UpdateEntityColor(int client, int idx, const int color[4], bool glow)
{
	int ent = EntRefToEntIndex(g_PropPool[client].entities[idx]);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
		return;

	SetEntityRenderColor(ent, color[0], color[1], color[2], color[3]);

	int effects = GetEntProp(ent, Prop_Send, "m_fEffects") & ~EF_NODRAW;
    if (g_iSpawnerMode<2) effects = effects | EF_NOSHADOW;
    else effects = effects | EF_NOSHADOW | EF_NOINTERP;
	SetEntProp(ent, Prop_Send, "m_fEffects", effects);

	GridRendererProp_SetGlow(ent, glow, color);
}

/**
 * Toggle glow on/off for a prop entity
 */
static void GridRendererProp_SetGlow(int ent, bool glow, const int color[4])
{
	if (glow)
	{
		int rgb = (color[0] << 16) | (color[1] << 8) | color[2];
		SetEntProp(ent, Prop_Send, "m_iGlowType", 3);
		SetEntProp(ent, Prop_Send, "m_glowColorOverride", rgb);
		SetEntProp(ent, Prop_Send, "m_nGlowRangeMin", 0);
		SetEntProp(ent, Prop_Send, "m_nGlowRange", 999999);
		AcceptEntityInput(ent, "StartGlowing");
	}
	else
	{
		SetEntProp(ent, Prop_Send, "m_glowColorOverride", 0);
		AcceptEntityInput(ent, "StopGlowing");
	}
}

/**
 * Hide a prop entity
 */
static void GridRendererProp_HideEntity(int client, int idx)
{
	int ent = EntRefToEntIndex(g_PropPool[client].entities[idx]);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
	{
		// Set EF_NODRAW, keep EF_NOSHADOW + EF_NOINTERP
		int effects = GetEntProp(ent, Prop_Send, "m_fEffects");
		SetEntProp(ent, Prop_Send, "m_fEffects", effects | EF_NODRAW | EF_NOSHADOW | EF_NOINTERP);

		SetEntProp(ent, Prop_Send, "m_glowColorOverride", 0);
		AcceptEntityInput(ent, "StopGlowing");
	}
}

/**
 * Hide all prop entities for a client
 */
void GridRendererProp_HideAll(int client)
{
	if (!g_PropPool[client].initialized) return;
	int totalEnts = g_PropPool[client].totalAllocated;
	for (int e = 0; e < totalEnts; e++)
	{
		g_PropPool[client].assignedCell[e] = -1;
		GridRendererProp_HideEntity(client, e);
	}
	g_PropPool[client].activeCount = 0;
}

// ============================================================================
// Helpers
// ============================================================================

/**
 * Convert a surface normal vector to Euler angles for entity orientation.
 *
 * @param normal    Surface normal vector (unit length)
 * @param angles    Output: Pitch, Yaw, Roll angles in degrees
 */
static void GridRendererProp_NormalToAngles(const float normal[3], float angles[3])
{
	float ny = normal[1];
	if (ny > 0.99)  ny = 0.99;
	if (ny < -0.99) ny = -0.99;

	float pitch = RadToDeg(ArcTangent2(normal[0], normal[2]));
	float roll  = -RadToDeg(ArcSine(ny));

	angles[0] = pitch;
	angles[1] = 0.0;
	angles[2] = roll;
}

// ============================================================================
// Transmit Hook
// ============================================================================

/**
 * SetTransmit hook - only show entities to their owner client
 */
public Action GridRendererProp_OnSetTransmit(int entity, int client)
{
	if (g_Prop_OwnerClient[entity] != client)
		return Plugin_Handled;
	return Plugin_Continue;
}
