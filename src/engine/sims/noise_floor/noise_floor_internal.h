// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the noise_floor_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef NOISE_FLOOR_INTERNAL_H
#define NOISE_FLOOR_INTERNAL_H

#include "sim_camera.h"

#include "noise_detector.h"

#define FLOOR_KEY 0x464C4F4F52ull

#define FLOOR_STREAM_BITS 512u

#define FLOOR_STREAM_WORDS (FLOOR_STREAM_BITS / 64u)

#define FLOOR_STREAMS 4096u

#define FLOOR_DEGREE_LEAST 8u

#define FLOOR_DEGREE_MAX 64u

#define FLOOR_RANDOM_RANGE 16u

#define FLOOR_PLANES 16u

#define FLOOR_THREADS 128ull

#define FLOOR_LEVELS 262144ull

#define FLOOR_ROUTES 3u

#define FLOOR_FOUNDERS 8u

// the static pairs' neighbor correlation is held within 5 / sqrt(N) of 0, this squared times N. A frame difference
// shares a frame with the next. Over 23 frame pairs a voxel the product sum spreads by sqrt(1.478) of an
// independent one's, and the tolerance is about 4.1 standard errors
#define FLOOR_CORRELATION_RANGE_SQUARED 25ll

// the truth route's slope and intercept are held within 5 standard errors of the law, this squared, and the intercept
// at least 5 above 0
#define FLOOR_ERROR_RANGE_SQUARED 25ull

typedef struct
{
    unsigned long long word[FLOOR_STREAM_WORDS];
} FloorStream;

typedef struct
{
    unsigned long long *count;
    unsigned long long *total;
} FloorBins;

typedef struct
{
    unsigned long long pairs;
    unsigned long long both_static;
    unsigned long long neighbor_product;
    unsigned long long square_here;
    unsigned long long square_beside;
    unsigned long long neighbor_product_all;
    unsigned long long square_here_all;
    unsigned long long square_beside_all;
} FloorCoherence;

void floor_mock(SimResults *results, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated);

void floor_random(SimResults *results, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated);

void floor_planes(SimResults *results, const unsigned short *lanes, unsigned long long lanes_count);

__global__ void floor_transfer_kernel(unsigned short *lanes, const unsigned int *signal, unsigned long long frames,
                                      unsigned long long voxels, unsigned long long columns, FloorBins truth,
                                      FloorBins level, FloorBins coherent, FloorCoherence *coherence);

typedef struct
{
    AnchorExactInteger slope;
    AnchorExactInteger intercept;
    AnchorExactInteger denominator;
    unsigned long long samples;
} FloorLine;

#endif
