
// What the anchor_raster_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef ANCHOR_RASTER_INTERNAL_H
#define ANCHOR_RASTER_INTERNAL_H

/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_raster_internal.h
 * @brief The host rasterizer and the P5 writer. Integer arithmetic throughout.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHY THIS IS FAST, AND IT IS THE SAME REASON THE SEARCH IS. A pixel costs what the alignment under
 * it costs, and a steered probe set rejects most alignments on the first read. The renderer gets the
 * same saving: driving reads per alignment toward one drives the cost of a frame toward one read
 * per alignment. Nothing here is optimized separately from the search, and there is no second code
 * path to keep in agreement with it.
 */

#include "anchor_raster.h"

#include <stdio.h>

/** @brief Death level step in the gray ramp, chosen so four probes stay far apart in 8 bits. */
#define ANCHOR_RASTER_STEP 40u

/** @brief Brightest value a death level may reach, leaving ANCHOR_RASTER_MATCH above it. */
#define ANCHOR_RASTER_CEILING 250u

/**
 * @brief Symbol counts over the object, held apart from anchor_steer so the device links neither.
 *
 * @note The rarity channel needs the same counts anchor_steer builds, and the device rasterizer
 *       cannot link the limb library those live behind. Counting bytes is eight lines. The
 *       duplication costs less than the dependency and neither copy can drift into a different
 *       answer: both are a histogram of the same bytes.
 */
typedef struct
{
    uint64_t occurrences[256];
    uint64_t total;
} AnchorRasterCensus;

void raster_census(AnchorRasterCensus *census, const uint8_t *corpus, size_t corpus_len);

uint8_t anchor_raster_sample(const AnchorRasterConfig *config, const uint8_t *corpus, const uint8_t *needle,
                             size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count, size_t at,
                             const uint64_t *occurrences, uint64_t total);

const char *anchor_raster_channel_name(AnchorRasterChannel channel);
#if (!defined(ANCHOR_RASTER_HAVE_CUDA) || !ANCHOR_RASTER_HAVE_CUDA)

int anchor_raster_device_available(void);

int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count);
#endif

#endif
