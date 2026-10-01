// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_tower_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_TOWER_TEST_INTERNAL_H
#define RECORD_TOWER_TEST_INTERNAL_H

//
// The two towers as record floors the engine emits (engine_table.md item 8), each floor focused from a ruleset, the
// wave transform's math, and not written out by hand. A lifting step moves one band of a line by a rounded sum
// over the other, target += sign floor((rounding + sum_k weight_k other[a + offset_k]) / 2^shift), and
// tower_record_lift and tower_record_lower pass a ruleset through a block's extent as record steps, one block of the
// lattice to a lane. The kernels' 5/3 is read against tower_lift and tower_lower lane for lane: on blocks of one to
// four axes, odd extents and even, every volume's T equals tower_lift's crystal at every coefficient, and T^-1 run on
// it equals tower_lower's rebuilt samples and the source, with no ruleset named and with the 5/3 named as its two
// steps. Two rulesets the kernels do not run, the S transform and a four-tap predict, are read against a host
// oracle, which itself equals the kernels on the 5/3. For every ruleset, T read through T^-1 as one program returns
// crystals drawn anywhere in the fields' widths. An operation F read through T^-1 (the block's sum, and its energy
// along x, the sum of the squared differences of x neighbors) equals F on tower_lower's samples. Every program runs
// on the device and the host, word for word. The emitter sizes a program before it is held, and it errors on a register
// that is not earlier, a capacity too small, an empty extent and a malformed step, leaving the program as it was.
// Every sweep gives back the stack its frame grew. The limit after the blocks is the limit before them.
// The test is one job on the device's tessera daemon, submitted before its first device work.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "sim.h"
#include "../../../../../../../src/c/engine/analysis/tower/tower.h"

#include <algorithm>
#include <vector>

#define TOWER_TEST_VOLUMES 256u

#define TOWER_TEST_BLOCKS 7u

#define TOWER_TEST_RULESETS 4u

#define TOWER_TEST_SAMPLE_BITS 16u

// the device holds one volume for the kernels and one program's records at a time, far below this
#define TOWER_TEST_DECLARED (16ull << 20u)

// the 5/3 as tower.h states it: the highs less floor((x_2j + x_(2j+2)) / 2), the lows plus floor((d_(j-1) + d_j + 2) /
// 4)
static const TowerLiftingStep s_tower_test_five_three[2] = {{TOWER_BAND_HIGH, -1, 2u, {0, 1}, {1, 1}, 0u, 1u},
                                                            {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

typedef struct
{
    const char *name;
    const TowerLiftingStep *rules;
    unsigned int rule_count;
    int kernels;
} TowerTestRuleset;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} TowerTestLoaded;

unsigned int tower_test_random(void);

unsigned short tower_test_sample(unsigned int volume, unsigned int position);

long long tower_test_signed(unsigned int word, unsigned int bits);

long long tower_test_take(const unsigned int *record, const DeviceRecordStep *step);

void tower_test_oracle(const unsigned long long extent[4], const TowerLiftingStep *rules, unsigned int rule_count,
                       std::vector<long long> &values, int inverse);

int tower_test_load(const std::vector<EngineRecordStep> &steps, const std::vector<unsigned int> &outputs,
                    const std::vector<unsigned int> &field_bits, TowerTestLoaded *loaded);

void tower_test_free(TowerTestLoaded *loaded);

int tower_test_run(TowerTestLoaded *loaded, const std::vector<unsigned int> &atoms, unsigned int volumes,
                   std::vector<unsigned int> &out);

int tower_test_kernels(const unsigned long long extent[4], const unsigned short *source, unsigned short *device_volume,
                       int *crystal, unsigned short *rebuilt, unsigned int lanes);

void tower_test_operation(const unsigned long long extent[4], const unsigned short *samples, unsigned int lanes,
                          long long *sum, long long *energy);

int tower_test_build(const unsigned long long extent[4], const TowerTestRuleset *ruleset, int inverse,
                     const std::vector<unsigned int> &in, std::vector<unsigned int> &out,
                     std::vector<EngineRecordStep> &steps);

std::vector<EngineRecordStep> tower_test_fields(unsigned int lanes, EngineRecordOperation field);

#endif
