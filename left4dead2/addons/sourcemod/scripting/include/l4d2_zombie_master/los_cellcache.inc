///////////////////////////////////////
#if defined _zm_los_cellcache_included
 #endinput
#endif
#define _zm_los_cellcache_included
///////////////////////////////////////

/**
 * Cross-tick (surv_cell_idx, target_cell_idx) LOS result cache.
 */

#define CELLCACHE_POW    14
#define CELLCACHE_SLOTS  (1 << CELLCACHE_POW)
#define CELLCACHE_MASK   (CELLCACHE_SLOTS - 1)
#define CELLCACHE_PROBE  4

ConVar g_hLosCellCache;
ConVar g_hLosCellCacheTTL;
bool   g_bLosCellCache;
float  g_fLosCellCacheTTL;

int g_CachedSurvCell[MAXPLAYERS+1];

// Hash table slots. g_LosCellCache_exp[slot] == 0.0 means "never written".
int   g_LosCellCache_surv[CELLCACHE_SLOTS];
int   g_LosCellCache_targ[CELLCACHE_SLOTS];
bool  g_LosCellCache_res [CELLCACHE_SLOTS];
float g_LosCellCache_exp [CELLCACHE_SLOTS];

int g_LosN_cellcache_hit_vis;  // cache hit with cached result = visible (early returns)
int g_LosN_cellcache_hit_blk;  // cache hit with cached result = blocked (skip survivor)
int g_LosN_cellcache_miss;     // cache miss; trace ran and populated a slot
int g_LosN_cellcache_evict;    // populate evicted a full probe-chain head


stock int surv_pos_key(const float pos[3])
{
    int x = RoundToFloor(pos[0] / 16.0);
    int y = RoundToFloor(pos[1] / 16.0);
    int z = RoundToFloor(pos[2] / 64.0);
    return (x & 0x7FF) | ((y & 0x7FF) << 11) | ((z & 0x3FF) << 22);
}

stock void cellcache_clear_all()
{
    for (int i = 0; i < CELLCACHE_SLOTS; i++) g_LosCellCache_exp[i] = 0.0;
}

stock int cellcache_hash(int surv, int targ)
{
    return ((surv * 2654435761) ^ (targ * 2246822519)) & CELLCACHE_MASK;
}

stock bool cellcache_lookup(int surv, int targ, bool &outResult)
{
    float now = GetGameTime();
    int start = cellcache_hash(surv, targ);
    for (int i = 0; i < CELLCACHE_PROBE; i++)
    {
        int slot = (start + i) & CELLCACHE_MASK;
        if (g_LosCellCache_exp[slot] == 0.0) return false;   // never-written; chain ends
        if (g_LosCellCache_surv[slot] == surv && g_LosCellCache_targ[slot] == targ)
        {
            if (g_LosCellCache_exp[slot] >= now)
            {
                outResult = g_LosCellCache_res[slot];
                return true;
            }
            return false; // matched but expired; caller may populate back into this slot
        }
    }
    return false; // probe chain exhausted without matching
}

stock void cellcache_populate(int surv, int targ, bool result, float ttl)
{
    float now = GetGameTime();
    int start = cellcache_hash(surv, targ);
    int writeSlot = -1;
    for (int i = 0; i < CELLCACHE_PROBE; i++)
    {
        int slot = (start + i) & CELLCACHE_MASK;
        if (g_LosCellCache_exp[slot] == 0.0 || g_LosCellCache_exp[slot] < now)
        {
            writeSlot = slot;
            break;
        }
        if (g_LosCellCache_surv[slot] == surv && g_LosCellCache_targ[slot] == targ)
        {
            writeSlot = slot; // refresh our own valid entry
            break;
        }
    }
    if (writeSlot < 0)
    {
        g_LosN_cellcache_evict++;
        writeSlot = start; // full chain; evict the head
    }
    g_LosCellCache_surv[writeSlot] = surv;
    g_LosCellCache_targ[writeSlot] = targ;
    g_LosCellCache_res [writeSlot] = result;
    g_LosCellCache_exp [writeSlot] = now + ttl;
}

stock void cellcache_get_cvars()
{
    g_bLosCellCache     = g_hLosCellCache.BoolValue;
    g_fLosCellCacheTTL  = g_hLosCellCacheTTL.FloatValue;
    if (g_fLosCellCacheTTL > 5.0)
    {
        LogMessage("[zm] NOTE: zm_los_cellcache_ttl=%.1f is above 5s. Cache may thrash on dynamic maps and stale-entry window grows after prop movement/breakage.",
                   g_fLosCellCacheTTL);
    }
}
