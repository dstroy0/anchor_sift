// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_lane_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_LANE_TEST_INTERNAL_H
#define RECORD_LANE_TEST_INTERNAL_H

//
// The lane's own number as a register, and the latch (vertical_time_compression.md, "The lane index and the latch").
// ENGINE_RECORD_LANE writes the number a sweep runs a lane as into a register, and a member of one record is read by
// every lane. One shared record and the lanes enumerate a range, x = base + l, with nothing stored a lane. A hash of
// x against a threshold T, base and T both in the one record, runs over every lane on the host, on the device's
// interpreter and as the compiled program: the three must agree word for word, and each lane's l, x, hash and hit must
// equal the host's own 64-bit arithmetic. The latch is the first lane whose output holds, min{l : cond(l)}, infinity
// where none does. Read on the device by a tree over each warp and one atomic minimum, it must return the lane the
// host's serial scan over the same records returns and the first lane the host's own arithmetic finds, at every
// threshold from every lane hitting to none, and over 2^24 lanes on the device with only the lane brought back. Its
// edges: lane 0, the last lane, the least of many, a field across two limbs, a field of a whole limb, and bits outside
// the field that must not trip it. Under an index the lane register is still the lane, not the record it reads. A
// member of two records still refuses a sweep of three lanes, and the latch refuses a field past its record. The test
// is one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define LANE_TEST_LINE 8192ull

#define LANE_TEST_STEPS 32u

#define LANE_TEST_OUTPUTS 4u

// the enumerated lanes, run three ways
#define LANE_TEST_LANES 65536ull

// the lanes the latch reads on the device alone
#define LANE_TEST_SCALE_LANES (1ull << 24u)

// the threshold of the scale run, 2^32 / 2^22: a lane hits with chance 2^-22
#define LANE_TEST_SCALE_THRESHOLD (1ull << 10u)

// the scale run's base: its low word stays under 2^32 across all 2^24 lanes. No lane's low word is 0, whose hash is
// 0 and hits every threshold above it
#define LANE_TEST_SCALE_BASE 0x0000ABCD12345678ull

// the latch's edge records, two limbs each
#define LANE_TEST_EDGE_LANES (1ull << 20u)

#define LANE_TEST_EDGE_LIMBS 2u

// the lanes read under an index, each its own record
#define LANE_TEST_INDEXED_LANES 4096u

// the shared record: base at bit 0, 48 bits, and T at bit 48, 33 bits so that 2^32 fits, in three limbs
#define LANE_TEST_BASE_BITS 48u

#define LANE_TEST_THRESHOLD_OFFSET 48u

#define LANE_TEST_THRESHOLD_BITS 33u

#define LANE_TEST_SHARED_LIMBS 3u

// base's low word lies 2^15 under 2^32. X = base + l carries into its high word at l = 32768, where x's low word is
// 0 and so is its hash: lane 32768 hits every threshold above 0
#define LANE_TEST_BASE 0x00001234FFFF8000ull

// the hash's two odd multipliers
#define LANE_TEST_FIRST_MULTIPLIER 0x9E3779B1u

#define LANE_TEST_SECOND_MULTIPLIER 0x85EBCA6Bu

#define LANE_TEST_THRESHOLDS 6u

// the small allocations beside the records, each on its own page of the device's allocator: a shared record, the
// latch's word, and each loaded program's steps, refusal count, block and counters. The first run's peak passed the
// records alone by one 2 MiB page
#define LANE_TEST_SMALL_BYTES (8ull << 20u)

// the most the test puts on the device at once: the scale run's records, a limb a lane, with the edge records and the
// small allocations beside
#define LANE_TEST_DECLARED                                                                                             \
    ((LANE_TEST_SCALE_LANES * sizeof(unsigned int)) +                                                                  \
     (LANE_TEST_EDGE_LANES * LANE_TEST_EDGE_LIMBS * sizeof(unsigned int)) + LANE_TEST_SMALL_BYTES)

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} LaneResults;

typedef struct
{
    EngineRecordStep steps[LANE_TEST_STEPS];
    unsigned int count;
    unsigned int outputs[LANE_TEST_OUTPUTS];
    unsigned int output_count;
} LaneProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} LaneLoaded;

// the search's outputs, as places in its program's outputs; the hit alone where only it is written
typedef struct
{
    unsigned int lane;
    unsigned int value;
    unsigned int hash;
    unsigned int hit;
} LaneSearch;

unsigned long long lane_random(void);

void lane_check(LaneResults *results, int passed, const char *what);

void lane_print(LaneResults *results, unsigned long long lane);

void lane_search_build(LaneProgram *program, int write_all, LaneSearch *search);

int lane_load(const LaneProgram *program, int interpret, LaneLoaded *loaded);

void lane_free(LaneLoaded *loaded);

void lane_put(unsigned int *record, unsigned int offset, unsigned int bits, unsigned long long value);

void lane_shared(unsigned int *record, unsigned long long base, unsigned long long threshold);

unsigned long long lane_take(const unsigned int *record, const DeviceRecordStep *step, int *fits);

unsigned int lane_hash(unsigned long long value);

unsigned long long lane_native_first(unsigned long long base, unsigned long long threshold, unsigned long long lanes);

int lane_sweep(LaneLoaded *loaded, const unsigned int *device_shared, unsigned long long lanes,
               unsigned int *device_out);

int lane_latch_device(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *device_out,
                      unsigned long long lanes, unsigned long long *first, EngineError *error);

int lane_latch_host(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *out,
                    unsigned long long lanes, unsigned long long *first, EngineError *error);

#endif
