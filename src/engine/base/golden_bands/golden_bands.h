// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef GOLDEN_BANDS_H
#define GOLDEN_BANDS_H

#include "engine_config.h"

#define DAMP_BANDS ENGINE_GOLDEN_RUNGS

unsigned int band_of(unsigned long long value);

unsigned long long band_floor(unsigned int band);

unsigned long long band_or_count(unsigned int by_band, unsigned long long count);

#endif
