// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "golden_bands.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void golden_ladder(unsigned long long *rung)
{
    rung[0] = 0ull;
    rung[1] = 1ull;
    for (unsigned int step = 2u; step < DAMP_BANDS; step += 1u)
    {
        rung[step] = rung[step - 1u] + rung[step - 2u];
    }
}

unsigned int band_of(unsigned long long value)
{
    unsigned long long rung[DAMP_BANDS];
    golden_ladder(rung);
    unsigned int band = 0u;
    for (unsigned int step = 1u; step < DAMP_BANDS; step += 1u)
    {
        band += (unsigned int)(rung[step] <= value);
    }
    return band;
}

unsigned long long band_or_count(unsigned int by_band, unsigned long long count)
{
    return (by_band != 0u) ? (unsigned long long)band_of(count) : count;
}

unsigned long long band_floor(unsigned int band)
{
    unsigned long long rung[DAMP_BANDS];
    golden_ladder(rung);
    return rung[(band < DAMP_BANDS) ? band : (DAMP_BANDS - 1u)];
}
