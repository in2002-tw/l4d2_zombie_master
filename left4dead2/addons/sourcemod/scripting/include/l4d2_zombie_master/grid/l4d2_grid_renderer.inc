/**
 * L4D2 Grid Renderer
 * Prop-based rendering for grid cell visualization
 *
 * Version: 2.1.0
 * Author: zyiks
 * Dependencies: l4d2_grid_lib, sdktools
 *
 * Renders grid cells as prop_dynamic_override entities using a custom flat
 * quad model. Each cell is a filled colored rectangle with per-client
 * visibility via SDKHook_SetTransmit.
 *
 */

#if defined _l4d2_grid_renderer_included
 #endinput
#endif
#define _l4d2_grid_renderer_included

// Require dependencies
#if !defined _l4d2_grid_lib_included
    #include <l4d2_grid_lib>
#endif

#if !defined _sdktools_included
    #include <sdktools>
#endif

// ============================================================================
// Constants
// ============================================================================

#define GRIDRENDERER_VERSION "2.1.0"
#define GRIDRENDERER_MAX_CELLS 25      // Max cells to render per client

// Cell colors (RGBA)
#define GRIDRENDERER_COLOR_VALID             {0, 100, 0, 255}      // Dark green
#define GRIDRENDERER_COLOR_INVALID           {100, 0, 0, 255}      // Dark red
#define GRIDRENDERER_COLOR_HIGHLIGHT         {0, 255, 0, 255}      // Green
#define GRIDRENDERER_COLOR_HIGHLIGHT_INVALID {255, 128, 0, 255}    // Orange

// ============================================================================
// Include Prop Backend
// ============================================================================

#include <l4d2_zombie_master/grid/l4d2_grid_renderer_prop>

// ============================================================================
// Public API - Lifecycle
// ============================================================================

/**
 * Initialize the renderer system
 * Call in OnMapStart() after precaching sprites/models
 */
stock void GridRenderer_Init()
{
	GridRendererProp_Init();
	if (DEBUG) LogMessage("[GridRenderer] Initialized (prop_dynamic)");
}

/**
 * Cleanup the renderer system
 * Call in OnMapEnd() and OnPluginEnd()
 */
stock void GridRenderer_Cleanup()
{
	GridRendererProp_Cleanup();
}

/**
 * Called when a client enables their grid
 *
 * @param client    Client index
 */
stock void GridRenderer_OnClientEnabled(int client)
{
	GridRendererProp_OnClientEnabled(client);
}

/**
 * Called when a client disables their grid
 *
 * @param client    Client index
 */
stock void GridRenderer_OnClientDisabled(int client)
{
	GridRendererProp_OnClientDisabled(client);
}

/**
 * Enable or disable distance-based alpha fade on cells
 *
 * @param enabled    true = cells fade with distance, false = uniform alpha
 */
stock void GridRenderer_SetAlphaFade(bool enabled)
{
	GridRendererProp_SetAlphaFade(enabled);
}

// ============================================================================
// Public API - Rendering
// ============================================================================

/**
 * Draw cells for a client using prop_dynamic entities
 *
 * @param client             Client to draw for
 * @param cellIndices        Array of cell indices from GridLib
 * @param cellValid          Array of validation results (true = valid spawn)
 * @param count              Number of cells (max GRIDRENDERER_MAX_CELLS)
 * @param closestValidIdx    Index into cellIndices of closest valid cell, or -1
 * @param overridePositions  Per-cell position overrides (e.g. on top of physics props)
 * @param hasOverride        Whether each cell has a position override
 * @param overrideFlat       When true for a cell with hasOverride, render with flat (0,0,1) normal (prop top)
 * @return                   Number of cells drawn
 */
stock int GridRenderer_DrawCells(int client,
                                 const int cellIndices[GRIDRENDERER_MAX_CELLS],
                                 const bool cellValid[GRIDRENDERER_MAX_CELLS],
                                 int count,
                                 int closestValidIdx,
                                 const float overridePositions[GRIDRENDERER_MAX_CELLS][3],
                                 const bool hasOverride[GRIDRENDERER_MAX_CELLS],
                                 const bool overrideFlat[GRIDRENDERER_MAX_CELLS])
{
	if (count <= 0)
		return 0;

	if (count > GRIDRENDERER_MAX_CELLS)
		count = GRIDRENDERER_MAX_CELLS;

	return GridRendererProp_DrawCells(client, cellIndices, cellValid,
	                                  count, closestValidIdx,
	                                  overridePositions, hasOverride, overrideFlat);
}

/**
 * Hide all grid cells for a client
 */
stock void GridRenderer_HideAll(int client)
{
	GridRendererProp_HideAll(client);
}

// ============================================================================
// Helpers
// ============================================================================

/**
 * Resolve color for a cell based on its validation state and highlight status
 *
 * @param isValid     Whether the cell is a valid spawn
 * @param isClosest   Whether this is the closest valid cell (highlighted)
 * @param color       Output RGBA color array
 */
stock void GridRenderer_ResolveColor(bool isValid, bool isClosest, int color[4])
{
	if (isClosest && g_iSpawnerMode==2)
	{
		if (isValid)
		{
			int c[4] = GRIDRENDERER_COLOR_HIGHLIGHT;
			color = c;
		}
		else
		{
			int c[4] = GRIDRENDERER_COLOR_HIGHLIGHT_INVALID;
			color = c;
		}
	}
	else
	{
		if (isValid)
		{
			int c[4] = GRIDRENDERER_COLOR_VALID;
			color = c;
		}
		else
		{
			int c[4] = GRIDRENDERER_COLOR_INVALID;
			color = c;
		}
	}
}
