// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "residual_survey.h"

#include "engine_config.h"
#include "golden_bands.h"
#include "radix_keys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned int g_survey = 0u;

static unsigned long long s_survey_frames = 0ull;

static unsigned long long s_survey_positive = 0ull;

static unsigned long long s_survey_voxels = 0ull;

static unsigned int s_survey_reached = 0u;

static unsigned long long s_survey_distinct_sum = 0ull;

static unsigned long long s_survey_distinct_least = 0xFFFFFFFFFFFFFFFFull;

static unsigned long long s_survey_distinct_most = 0ull;

static unsigned long long s_survey_rungs[DAMP_BANDS];

void survey_residual(const unsigned int *residual, size_t voxels)
{
    unsigned int reached = 0u;
    size_t positive = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int *const limbs = &residual[voxel * ENGINE_RESIDUAL_LIMBS];
        const unsigned int negative = (unsigned int)((limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) != 0u);
        positive += (size_t)(negative == 0u);
        for (unsigned int limb = 0u; (negative == 0u) && (limb < ENGINE_RESIDUAL_LIMBS); limb += 1u)
        {
            reached = ((limbs[limb] != 0u) && ((limb + 1u) > reached)) ? (limb + 1u) : reached;
        }
    }
    s_survey_frames += 1ull;
    s_survey_voxels += (unsigned long long)voxels;
    s_survey_positive += (unsigned long long)positive;
    s_survey_reached = (reached > s_survey_reached) ? reached : s_survey_reached;
    if ((reached == 0u) || (positive == 0u))
    {
        return;
    }
    unsigned long long *const keys = (unsigned long long *)malloc(positive * sizeof(unsigned long long));
    if (keys == NULL)
    {
        return;
    }
    size_t held = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int *const limbs = &residual[voxel * ENGINE_RESIDUAL_LIMBS];
        if ((limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) != 0u)
        {
            continue;
        }
        const unsigned int high = (reached >= 2u) ? limbs[reached - 1u] : 0u;
        const unsigned int low = limbs[(reached >= 2u) ? (reached - 2u) : (reached - 1u)];
        keys[held] = ((unsigned long long)high << 32u) | (unsigned long long)low;
        held += 1u;
    }
    radix_sort_keys(keys, held);
    unsigned long long distinct = (held != 0u) ? 1ull : 0ull;
    for (size_t at = 1u; at < held; at += 1u)
    {
        distinct += (unsigned long long)(keys[at] != keys[at - 1u]);
    }
    s_survey_distinct_sum += distinct;
    s_survey_distinct_least = (distinct < s_survey_distinct_least) ? distinct : s_survey_distinct_least;
    s_survey_distinct_most = (distinct > s_survey_distinct_most) ? distinct : s_survey_distinct_most;
    for (size_t at = 0u; at < held; at += 1u)
    {
        s_survey_rungs[band_of(keys[at])] += 1ull;
    }
    free(keys);
}

void survey_report(void)
{
    if (s_survey_frames == 0ull)
    {
        return;
    }
    printf("\n  RESIDUAL SURVEY over %llu frames, %llu voxels:\n", s_survey_frames, s_survey_voxels);
    const unsigned long long positive_tenths = (1000ull * s_survey_positive) / s_survey_voxels;
    printf("    positive voxels               %llu  (%llu.%llu%% of all)\n", s_survey_positive,
           positive_tenths / 10ull, positive_tenths % 10ull);
    printf("    limbs the residual reaches    %u of %u  (%u bits of 288)\n",
           s_survey_reached, ENGINE_RESIDUAL_LIMBS, s_survey_reached * 32u);
    printf("    distinct levels a frame holds least %llu, most %llu, mean %llu\n",
           s_survey_distinct_least, s_survey_distinct_most, s_survey_distinct_sum / s_survey_frames);
    unsigned int occupied = 0u;
    for (unsigned int band = 0u; band < DAMP_BANDS; band += 1u)
    {
        occupied += (unsigned int)(s_survey_rungs[band] != 0ull);
    }
    printf("    golden rungs occupied         %u\n", occupied);
    printf("    voxels by rung, where a count banded flood would step:\n");
    for (unsigned int band = 0u; band < DAMP_BANDS; band += 1u)
    {
        if (s_survey_rungs[band] == 0ull)
        {
            continue;
        }
        const unsigned long long hundredths = (10000ull * s_survey_rungs[band]) / s_survey_positive;
        printf("      rung %-3u from %-12llu %12llu voxels  %3llu.%02llu%%\n", band, band_floor(band),
               s_survey_rungs[band], hundredths / 100ull, hundredths % 100ull);
    }
}
