// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the floor_track_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef FLOOR_TRACK_INTERNAL_H
#define FLOOR_TRACK_INTERNAL_H

// Floor 2 matched across frames. Every frame's floor 2 is the
// engine's, the crystal's 16^3 corner lowered as its own tower, checked against the host's two-level lifting, and laid
// out once as 16 bit planes. A body's signature is its patch of floor-2 values in frame t: its own cell alone, or the
// 27 cells around it. The later frame is searched whole with no value read: each patch cell's range [v - d, v + d] is
// taken on the planes by ands and ors alone, shifted to the patch center, and the patch's masks anded, a word stopping
// once it is empty. The expected answer is each body's own path. A control moves every body exactly one floor-2 cell a
// frame with no noise and no ramp. Floor 2 translates exactly and a tolerance of 0 must find every body. The camera law
// then moves bodies a voxel a frame under shot and read noise. From frame t to t + 1 that is a quarter of a floor-2
// cell, and the decimated floor is not shift-invariant under it; from t to t + 4, floor 2's own time step, it is a
// whole cell again. The 27 cells read the samples within 10 of the body's cell. A body another body reaches there does
// not translate alone: the camera law's bodies are run again with no noise, and three of them are set apart along z,
// with the noise and without it, where every step is clear and a tolerance of 0 must find every one. The hits, the
// false candidates and the plane words read are counted at every tolerance. Every candidate set is held to the
// host's scan.
#include "sim_camera.h"

#include "tower.h"

#define TRACK_KEY 0x545241434Bull

#define TRACK_CONTROL_PURPOSE 0x434F4E54ull

#define TRACK_FOUNDER_PURPOSE 0x464F554Eull

#define TRACK_SIDE 64ull

#define TRACK_FLOOR 2u

#define TRACK_FLOOR_SIDE (TRACK_SIDE >> TRACK_FLOOR)

// a floor-2 cell covers this many samples along each axis
#define TRACK_CELL (1ll << TRACK_FLOOR)

// a floor-2 value reads the samples within 6 of its center: two levels of the 5/3 lowpass, 2 + 2 * 2
#define TRACK_SUPPORT 6ll

// the patch centers whose 27 cells, along one axis, every lifting formula takes in its interior form
#define TRACK_CLEAR_FIRST 3ll

#define TRACK_CLEAR_LAST 13ll

#define TRACK_SAMPLES (TRACK_SIDE * TRACK_SIDE * TRACK_SIDE)

#define TRACK_FLOOR_VALUES (TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE)

#define TRACK_BITS 16u

#define TRACK_WORD_BITS 32ull

#define TRACK_WORDS (TRACK_FLOOR_VALUES / TRACK_WORD_BITS)

#define TRACK_VALUE_MAX 65535u

#define TRACK_PATCH_MAX 27u

#define TRACK_PATCHES 2u

#define TRACK_DELTAS 6u

#define TRACK_CONTROL_FRAMES 3ull

#define TRACK_CAMERA_FRAMES 9ull

#define TRACK_FRAMES_MAX TRACK_CAMERA_FRAMES

#define TRACK_CONTROL_BODIES 8u

#define TRACK_CAMERA_BODIES 10u

#define TRACK_BODIES_MAX TRACK_CAMERA_BODIES

// the sparse scene: three of the camera law's bodies, set 22 apart along z, where the most a footprint and a body
// reach toward each other is 13 + 3
#define TRACK_SPARSE_BODIES 3u

#define TRACK_SPARSE_FIRST_Z 10ll

#define TRACK_SPARSE_Z_STEP 22ll

#define TRACK_QUERIES_MAX (TRACK_BODIES_MAX * (TRACK_FRAMES_MAX - 1ull) * TRACK_PATCHES * TRACK_DELTAS)

#define TRACK_THREADS 256ull

static_assert(TRACK_WORDS <= 1024ull, "one block holds a query, one thread a word");

static_assert((TRACK_FLOOR_VALUES % TRACK_THREADS) == 0ull, "the plane kernel's blocks are whole warps");

// one query: the frame searched, and each patch cell's step from the center and its range of values
typedef struct
{
    unsigned int frame;
    unsigned int count;
    int step[TRACK_PATCH_MAX][SIM_AXES];
    unsigned int low[TRACK_PATCH_MAX];
    unsigned int high[TRACK_PATCH_MAX];
} TrackQuery;

// what a query is graded by: the setting it belongs to, the body's cell in each of the two frames, and whether the
// step is clear of other bodies and of the edges
typedef struct
{
    unsigned int patch;
    unsigned int delta;
    unsigned long long from;
    unsigned long long truth;
    int clear;
} TrackTruth;

// one setting's counts over its queries
typedef struct
{
    unsigned long long queries;
    unsigned long long hits;
    unsigned long long candidates;
    unsigned long long candidates_max;
    unsigned long long gated;
    unsigned long long alone;
    unsigned long long reads;
    unsigned long long reads_max;
    unsigned long long clear;
    unsigned long long clear_hits;
} TrackSetting;

// the host buffers one scene needs
typedef struct
{
    unsigned short *lanes;
    int *crystal;
    int *corner;
    unsigned short *floors;
    long long *work;
    long long *before;
    long long *floor_host;
    unsigned int *planes;
    TrackQuery *queries;
    TrackTruth *truths;
    unsigned int *candidates;
    unsigned int *reads;
    unsigned int *expected;
} TrackHost;

// the device buffers one scene needs
typedef struct
{
    unsigned short *lanes;
    unsigned short *floors;
    unsigned int *planes;
    TrackQuery *queries;
    unsigned int *candidates;
    unsigned int *reads;
} TrackDevice;

// what the sim puts on the device at once: the longest scene's frames, the tower's two kept coefficient arrays,
// floor 2 and its planes for every frame, the queries, and each query's candidate word and reads for every word
#define TRACK_DECLARED                                                                                                 \
    ((TRACK_FRAMES_MAX * TRACK_SAMPLES * sizeof(unsigned short)) + (2ull * TRACK_SAMPLES * sizeof(int)) +              \
     (TRACK_FRAMES_MAX * TRACK_FLOOR_VALUES * sizeof(unsigned short)) +                                                \
     (TRACK_FRAMES_MAX * TRACK_BITS * TRACK_WORDS * sizeof(unsigned int)) + (TRACK_QUERIES_MAX * sizeof(TrackQuery)) + \
     (2ull * TRACK_QUERIES_MAX * TRACK_WORDS * sizeof(unsigned int)))

void track_floor_host(const unsigned short *lanes, long long *work, long long *before, long long *floor_values);

int track_floor_engine(const unsigned short *device_lanes, int *crystal, int *corner, unsigned short *floor_values);

__global__ void track_planes_kernel(const unsigned short *floor_values, unsigned int *planes);

__global__ void track_query_kernel(const unsigned int *planes, const TrackQuery *queries, unsigned int *candidates,
                                   unsigned int *reads);

unsigned long long track_body_cell(const SimBody *body, unsigned long long frame);

void track_control_bodies(SimBody *body, unsigned long long frames);

void track_scan(const TrackQuery *query, const unsigned short *floor_values, unsigned int *expected);

int track_gated(unsigned long long from, unsigned long long position);

int track_clear(const SimScene *scene, unsigned int index, unsigned long long frame, unsigned long long stride,
                unsigned long long from, unsigned long long truth);

#endif
