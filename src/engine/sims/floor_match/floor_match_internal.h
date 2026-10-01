// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the floor_match_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef FLOOR_MATCH_INTERNAL_H
#define FLOOR_MATCH_INTERNAL_H

// Finding x on a's floor 2 for less than half of a. a is one camera-law frame of n samples. The engine's tower lifts it,
// and floor 2
// is the approximation after two levels: the 16^3 corner, m = n / 64 values, read from the engine by lowering that
// corner as its own tower and checked against the host's own two-level lifting. Floor 2's values are laid out once as
// 16 bit planes. A query x then reads no value at all: the positions holding x are the and, over the planes, of each
// plane where x's bit is 1 and its complement where it is 0, 32 positions a word, and a word stops being read once its
// mask is empty. Every match set is checked against the host's scan of floor 2, for values on floor 2 and values not on
// it, and every query's reads are counted against n / 2. The index is built once: the lift reads a's n samples and the
// planes floor 2's m values, and every query after reads only plane words.
#include "sim_camera.h"

#include "tower.h"

#define MATCH_KEY 0x464C4F4F52ull

#define MATCH_FOUNDER_PURPOSE 0x464F554Eull

#define MATCH_PRESENT_PURPOSE 0x50524553ull

#define MATCH_ABSENT_PURPOSE 0x41425345ull

#define MATCH_SIDE 64ull

#define MATCH_FLOOR 2u

// floor 2's side: two halvings of every axis
#define MATCH_FLOOR_SIDE (MATCH_SIDE >> MATCH_FLOOR)

#define MATCH_SAMPLES (MATCH_SIDE * MATCH_SIDE * MATCH_SIDE)

#define MATCH_FLOOR_VALUES (MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE)

// a floor-2 value's width: the engine's lowering holds every value inside the 16-bit lane
#define MATCH_BITS 16u

#define MATCH_WORD_BITS 32ull

#define MATCH_WORDS (MATCH_FLOOR_VALUES / MATCH_WORD_BITS)

#define MATCH_VALUES_MAX 65536ull

#define MATCH_FOUNDERS 6u

// queries of each kind: values on floor 2, drawn at keyed positions, and values not on it
#define MATCH_QUERIES_EACH 1024u

#define MATCH_QUERIES (2u * MATCH_QUERIES_EACH)

#define MATCH_THREADS 256ull

static_assert((MATCH_FLOOR_VALUES % MATCH_WORD_BITS) == 0ull, "floor 2 fills whole plane words, one warp a word");

static_assert((MATCH_FLOOR_VALUES % MATCH_THREADS) == 0ull, "the plane kernel's blocks are whole warps");

// what the sim puts on the device at once: the frame, the tower's two kept coefficient arrays, floor 2, the planes,
// the queries, and each query's match word and reads for every plane word
#define MATCH_DECLARED                                                                                                 \
    ((MATCH_SAMPLES * sizeof(unsigned short)) + (2ull * MATCH_SAMPLES * sizeof(int)) +                                 \
     (MATCH_FLOOR_VALUES * sizeof(unsigned short)) + (MATCH_BITS * MATCH_WORDS * sizeof(unsigned int)) +               \
     (MATCH_QUERIES * sizeof(unsigned int)) +                                                                          \
     ((unsigned long long)MATCH_QUERIES * MATCH_WORDS * (sizeof(unsigned int) + sizeof(unsigned char))))

void match_floor_host(const unsigned short *lanes, long long *work, long long *before, long long *floor_values);

int match_floor_engine(SimResults *results, const unsigned short *device_lanes, int *crystal, int *corner,
                       unsigned short *floor_values);

__global__ void match_planes_kernel(const unsigned short *floor_values, unsigned int *planes);

__global__ void match_query_kernel(const unsigned int *planes, const unsigned int *queries, unsigned int *matches,
                                   unsigned char *reads);

typedef struct
{
    unsigned long long total;
    unsigned long long maximum;
    unsigned long long found;
    unsigned long long found_max;
    unsigned long long matched;
} MatchSide;

void match_print_side(ScripturaLine *line, const char *name, const MatchSide *side);

#endif
