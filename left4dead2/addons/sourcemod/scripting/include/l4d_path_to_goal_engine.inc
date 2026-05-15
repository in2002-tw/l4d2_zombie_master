#if defined _l4d_path_to_goal_engine_included
 #endinput
#endif
#define _l4d_path_to_goal_engine_included

/**
 * Render the engine-sourced path-to-goal beams for a specific client.
 *
 * Samples the L4D2 engine's CEscapeRoute singleton entity, so the path
 * reflects live nav-blocked state with no caching.
 *
 * @param client    Real in-game client index. Bots and SourceTV are ignored.
 * @param duration  Beam lifetime in seconds (clamped to (0, 60]).
 * @param backward  If true, also draw the path behind the player toward spawn.
 */
native void L4D_Path_To_Goal_Engine(int client, float duration = 5.0, bool backward = false);

public SharedPlugin __pl_l4d_path_to_goal_engine =
{
    name     = "l4d_path_to_goal_engine",
    file     = "l4d_path_to_goal_engine.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_l4d_path_to_goal_engine_SetNTVOptional()
{
    MarkNativeAsOptional("L4D_Path_To_Goal_Engine");
}
#endif
