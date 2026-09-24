// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "grow.h"

#include <stdlib.h>
#include <string.h>

#define GROW_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_GROW, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

extern "C" long grow_leaves(const EngineBody *bodies, unsigned int count, EngineLeaves *leaves, EngineError *error)
{
    if (error == NULL)
    {
        return GROW_REFUSED;
    }
    if (!GROW_HELD((leaves != NULL) && ((bodies != NULL) || (count == 0u)), bodies, error, ENGINE_ERROR_REQUEST))
    {
        return GROW_REFUSED;
    }
    memset(leaves, 0, sizeof(*leaves));
    const size_t room = (size_t)count + 1u;
    leaves->peaks = (unsigned int *)malloc(room * sizeof(unsigned int));
    leaves->sizes = (unsigned int *)malloc(room * sizeof(unsigned int));
    leaves->sums = (unsigned long long *)malloc(room * 3u * sizeof(unsigned long long));
    leaves->moments = (unsigned long long *)malloc(room * 6u * sizeof(unsigned long long));
    leaves->touches = (unsigned int *)malloc(room * sizeof(unsigned int));
    leaves->joined = (unsigned int *)malloc(2u * sizeof(unsigned int));
    if (!GROW_HELD((leaves->peaks != NULL) && (leaves->sizes != NULL) && (leaves->sums != NULL)
                       && (leaves->moments != NULL) && (leaves->touches != NULL) && (leaves->joined != NULL),
                   leaves, error, ENGINE_ERROR_RESOURCE))
    {
        free(leaves->peaks);
        free(leaves->sizes);
        free(leaves->sums);
        free(leaves->moments);
        free(leaves->touches);
        free(leaves->joined);
        memset(leaves, 0, sizeof(*leaves));
        return GROW_REFUSED;
    }
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        const EngineBody *const body = &bodies[leaf];
        leaves->peaks[leaf] = body->peak;
        leaves->sizes[leaf] = body->mass;
        leaves->touches[leaf] = body->touches;
        memcpy(&leaves->sums[(size_t)leaf * 3u], body->sums, 3u * sizeof(unsigned long long));
        memcpy(&leaves->moments[(size_t)leaf * 6u], body->moments, 6u * sizeof(unsigned long long));
    }
    leaves->leaf_count = count;
    leaves->joined_count = 0u;
    return (long)count;
}

extern "C" void grow_group_voxels(const EngineGroupRequest *request)
{
    const unsigned int voxels = request->voxels;
    const unsigned int *const labels = request->labels;
    int *const leaf_at_peak = request->leaf_at_peak;
    unsigned int *const start = request->start;
    for (unsigned int leaf = 0u; leaf < request->leaf_count; leaf += 1u)
    {
        leaf_at_peak[request->peaks[leaf]] = (int)leaf;
    }
    memset(start, 0, ((size_t)request->leaf_count + 2u) * sizeof(unsigned int));
    unsigned int run_label = labels[0];
    int run_leaf = leaf_at_peak[run_label];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (labels[voxel] != run_label)
        {
            run_label = labels[voxel];
            run_leaf = leaf_at_peak[run_label];
        }
        if (run_leaf >= 0)
        {
            start[(unsigned int)run_leaf + 1u] += 1u;
        }
    }
    for (unsigned int leaf = 0u; leaf < request->leaf_count; leaf += 1u)
    {
        start[leaf + 1u] += start[leaf];
    }
    run_label = labels[0];
    run_leaf = leaf_at_peak[run_label];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (labels[voxel] != run_label)
        {
            run_label = labels[voxel];
            run_leaf = leaf_at_peak[run_label];
        }
        if (run_leaf >= 0)
        {
            request->grouped[start[(unsigned int)run_leaf]] = voxel;
            start[(unsigned int)run_leaf] += 1u;
        }
    }
    for (unsigned int leaf = request->leaf_count; leaf > 0u; leaf -= 1u)
    {
        start[leaf] = start[leaf - 1u];
    }
    start[0] = 0u;
    for (unsigned int leaf = 0u; leaf < request->leaf_count; leaf += 1u)
    {
        leaf_at_peak[request->peaks[leaf]] = -1;
    }
}
