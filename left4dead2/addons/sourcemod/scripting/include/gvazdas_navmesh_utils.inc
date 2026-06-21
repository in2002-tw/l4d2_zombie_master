//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//You should have received a copy of the GNU General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

#if defined _gvazdas_navmesh_utils_inc_included
 #endinput
#endif
#define _gvazdas_navmesh_utils_inc_included

#include <left4dhooks>

#if !defined AREA_COMMON
    #define AREA_COMMON 1024.0 // how much xy area a common infected takes up 
#endif

// Project given xy coordinates onto navArea (get Z automatically). return false on failure. force_OOB ignores OOB prevention
stock bool project_navmesh_xy(Address navArea, float pos[3], bool force_OOB = false)
{
    if (navArea == Address_Null) return false;
    if (!force_OOB && navmesh_OOB(navArea,pos,false)) return false;
    pos[2] = L4D_NavArea_GetZ(navArea,pos);
    return true;
}

// get navArea size vector relevant for spawning; extends any xy component shorter than min to min
stock void L4D_GetNavAreaSpawnSize(Address navArea, float size[3], float min = 32.0)
{
    L4D_GetNavAreaSize(navArea,size); AbsoluteVector(size);
    if (min>0.0)
    {
        if (size[0] < min) size[0] = min;
        if (size[1] < min) size[1] = min;
    }
}

// Calculate how many commons we can fit in the given navArea xy bounds
stock float nav_xy_area(Address navArea, float min = 32.0)
{
    static float size[3];
    L4D_GetNavAreaSpawnSize(navArea,size,min);
    return vec_xy_area(size);
}

stock float vec_xy_area(const float v[3])
{
    return v[0]*v[1];
}

// Check if position is out of bounds for given navmesh in xy plane. z=true to check if z is under
stock bool navmesh_OOB(Address navArea, float pos[3], const bool z = true)
{
    if (navArea == Address_Null) return true;
    static float center[3],size[3];
    L4D_GetNavAreaCenter(navArea,center);
    L4D_GetNavAreaSize(navArea,size); AbsoluteVector(size);
    if (z && pos[2]<L4D_NavArea_GetZ(navArea,pos)) return true;
    static float mins[3], maxs[3]; get_center_size_mins_maxs(center,size,mins,maxs);
    return pos_OOB(pos,mins,maxs,false);
}

// get mins and maxs for given center and abs size
stock void get_center_size_mins_maxs(const float center[3], const float size[3], float mins[3], float maxs[3])
{
    AddVectors(center,size,maxs);
    SubtractVectors(center,size,mins);
}

// Check if pos is out of bounds with respect to mins or maxs. z=true for xyz, z=false for xy
stock bool pos_OOB(const float pos[3], const float mins[3], const float maxs[3], const bool z = false)
{
    if (pos[0]<mins[0] || pos[0]>maxs[0] || pos[1]<mins[1] || pos[1]>maxs[1]) return true;
    if (z && pos[2]<mins[2]) return true;
    return false;
}

// Take abs of each vector component, modify in-place
stock void AbsoluteVector(float v[3])
{
    v[0] = FloatAbs(v[0]);
    v[1] = FloatAbs(v[1]);
    v[2] = FloatAbs(v[2]);
}

stock void clip_xy(float pos[3], const float mins[3], const float maxs[3])
{
    if (pos[0]<mins[0]) pos[0] = mins[0];
    else if (pos[0]>maxs[0]) pos[0] = maxs[0];
    if (pos[1]<mins[1]) pos[1] = mins[1];
    else if (pos[1]>maxs[1]) pos[1] = maxs[1];
}

// Find random spot on navArea, preferably centered around spawner_pos, for given count of common zombies
float mins_cached[3], maxs_cached[3], spawner_pos_cached[3];
Address navArea_cached;
int count_cached;
stock void L4D_FindRandomSpot_Constrained(Address navArea, const float spawner_pos[3], int count, float pos[3])
{
    float area_full = nav_xy_area(navArea) * 1.25;
    float desired_area = AREA_COMMON*count;
    if (area_full<=desired_area)
    {
        L4D_FindRandomSpot(navArea,pos);
        return;
    }
    if (navArea!=navArea_cached || spawner_pos[0]!=spawner_pos_cached[0] || spawner_pos[1]!=spawner_pos_cached[1] || count_cached!=count)
    {
        float desired_side = SquareRoot(desired_area);
        //float min_side = (size[0]<size[1]) ? size[0] : size[1];
        
        static float center[3], size[3], mins[3], maxs[3], diff[3];
        L4D_GetNavAreaCenter(navArea,center); L4D_GetNavAreaSpawnSize(navArea,size);
        get_center_size_mins_maxs(center,size,mins,maxs); // bounds of navArea
        
        // Try square centered at spawner_pos -> if within xy bounds -> return
        mins_cached[0] = spawner_pos[0] - desired_side/2.0;
        mins_cached[1] = spawner_pos[1] - desired_side/2.0;
        maxs_cached[0] = spawner_pos[0] + desired_side/2.0;
        maxs_cached[1] = spawner_pos[1] + desired_side/2.0;
        clip_xy(mins_cached,mins,maxs); clip_xy(maxs_cached,mins,maxs);
        SubtractVectors(maxs,mins,diff);
        float final_area = vec_xy_area(diff) * 1.25;
        if (final_area<desired_area)
        {
            // Mold the shape ourselves.
            L4D_FindRandomSpot(navArea,pos);
            return;
        }

        // Try square centered at center -> guaranteed within xy bounds -> return

        navArea_cached = navArea;
        spawner_pos_cached = spawner_pos;
        count_cached=count;
    }
    pos[0] = GetRandomFloat(mins_cached[0],maxs_cached[0]);
    pos[1] = GetRandomFloat(mins_cached[1],maxs_cached[1]);
    pos[2] = L4D_NavArea_GetZ(navArea,pos);
}