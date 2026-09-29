// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SORT_H
#define SORT_H

#include "engine.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define SORT_ERROR (-1L)

// .links opens with frames, depth, height, width, the three weights and the cost's terms. Each frame pair after it is
// a pair record, then each source's record in the order of frame t's .points, then each gate pair's record in the
// order (source, target). Every word is little-endian, and a 64-bit word is its low 32 bits, then its high
#define SORT_HEADER_WORDS 8u

// the cost's terms, one bit each: the weighted squared distance from the prediction, the shape term, clear until O8
// defines its distance, the still term, set when the gate also reads each source's still place (its place carried
// by the lag alone) and a pair's distance is the lesser of the two, and the first term, set when each pair's cost is
// O7's: its distance's level in the sample's pooled count of first-rank links
#define SORT_TERM_DISTANCE 0x1u
#define SORT_TERM_HESSIAN 0x2u
#define SORT_TERM_STILL 0x4u
#define SORT_TERM_FIRST 0x8u
#define SORT_TERMS SORT_TERM_DISTANCE

// a pair record: its sources, targets, gate pairs, components and chosen links, then the chosen links' kept, level
// and crossed pairs, 64 bits each
#define SORT_PAIR_WORDS 11u

// a source record: its prediction (z, y, x), signed, and its flags
#define SORT_SOURCE_WORDS 4u
#define SORT_SOURCE_OUTSIDE 0x1u
#define SORT_SOURCE_CARRIED 0x2u

// a gate pair record: source, target, cost (64 bits), weight, component, flags. A pair is in the gate when its
// target is among the source's nearest (forward) or its source among the target's nearest (backward), or, with the
// still term, its target is among the nearest to the source's still place (still)
#define SORT_GATE_WORDS 7u
#define SORT_GATE_CHOSEN 0x1u
#define SORT_GATE_FORWARD 0x2u
#define SORT_GATE_BACKWARD 0x4u
#define SORT_GATE_STILL 0x8u

// the most sources, targets or gate pairs a frame pair takes: heaviest_matching's bound
#define SORT_COUNT_MAX 0x3FFFFFFFu

// why a frame pair errored
#define SORT_WHY_NONE 0u
#define SORT_WHY_REQUEST 1u
#define SORT_WHY_SPAN 2u
#define SORT_WHY_GATE 3u
#define SORT_WHY_WIDE 4u
#define SORT_WHY_DEVICE 5u
#define SORT_WHY_MATCHING 6u

    // one frame pair: the places (z, y, x) of frame t's points (the sources) and frame t + 1's (the targets), and each
    // source's prediction. `stills`, when not NULL, is each source's still place, which the gate also reads forward
    typedef struct
    {
        unsigned int weights[ENGINE_AXES];
        unsigned int sources;
        unsigned int targets;
        const int *source_places;
        const int *predictions;
        const int *target_places;
        const int *stills;
    } SortPairRequest;

    // the pair's links, its arrays grown to `capacity` gate pairs and kept between calls. `needs` is the K a component
    // too wide for 32 bits needs, with `needs_past_64` set when it passes 64 bits too
    typedef struct
    {
        unsigned int capacity;
        unsigned int pairs;
        unsigned int *source;
        unsigned int *target;
        unsigned long long *cost;
        unsigned int *weight;
        unsigned int *component;
        unsigned int *flags;
        unsigned int components;
        unsigned int chosen;
        unsigned long long kept;
        unsigned long long level;
        unsigned long long crossed;
        unsigned int why;
        unsigned int wide_component;
        unsigned long long needs;
        int needs_past_64;
        unsigned long long gate_microseconds;
        unsigned long long match_microseconds;
    } SortLinks;

    // S5 on one frame pair: the gate, the costs, the support components and their weights K - cost, the heaviest
    // matching (the most links, then the least cost) and the chosen links' crossing verdict. Returns the chosen links,
    // or SORT_ERROR with `why` set
    long sort_link_pair(const SortPairRequest *request, SortLinks *links);

    void sort_links_release(SortLinks *links);

    // the device bytes the gate holds for frames of at most `maximum` points
    unsigned long long sort_reserve_bytes(unsigned int maximum);

    // gives back the gate's device pool
    void sort_release(void);

    // the most points a frame over the samples' .points, read by their counts; returns 1, or 0 when a .points is
    // missing or its head does not read
    int sort_points_max(const char *set, char *const *samples, unsigned int count, unsigned int *maximum);

    // O7's count at one distance (a gate pair's weighted squared distance): the gate pairs there, the first-rank ones
    // among them (forward, their target among their source's nearest), and the level the pooling gives it
    typedef struct
    {
        unsigned long long length;
        unsigned long long firsts;
        unsigned long long pairs;
        unsigned long long level;
    } SortFirstCount;

    // pool-adjacent-violators over `count` distances in ascending order: a block whose share of first-rank pairs, its
    // summed firsts over its summed pairs, passes the block before it joins it, until the share never rises with the
    // distance. Each distance's level is its block's place among the distinct pooled shares, the most first, and blocks
    // of equal shares share a level. The shares are compared exactly, as 128-bit cross products. Returns 1, or 0 with
    // no level set when the distances do not ascend, a distance has no pairs or more firsts than pairs, the pairs sum
    // past 64 bits, or the blocks' memory cannot be reserved
    int sort_first_pool(SortFirstCount *counts, unsigned long long count, unsigned long long *blocks,
                        unsigned long long *levels);

    // `still` set: the gate also reads each source's still place, its place carried by the lag alone. `first` set: O7,
    // once a sample's first pass is written each gate pair's cost becomes its distance's level in the sample's pooled
    // count, and each frame pair is weighed and matched again on those costs, its predictions the first pass's
    typedef struct
    {
        const char *set;
        char *const *samples;
        unsigned int count;
        unsigned long long voxel_pm[ENGINE_AXES];
        EngineError *error;
        unsigned int still;
        unsigned int first;
    } SortRequest;

    // writes each sample's .links from its .points and .drift; a sample that errors has no .links, and the set errors
    long sort_link_set(const SortRequest *request);

#ifdef __cplusplus
}
#endif

#endif
