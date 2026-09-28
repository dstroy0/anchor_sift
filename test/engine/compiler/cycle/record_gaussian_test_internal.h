// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_gaussian_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_GAUSSIAN_TEST_INTERNAL_H
#define RECORD_GAUSSIAN_TEST_INTERNAL_H

//
// The Gaussian step as record floors. BBP's base is a power of the Gaussian prime 1 + i: (1 + i)^8 = 16. One step,
// z -> z (1 + i) on z = a + b i, is the floor (a, b) -> (a - b, a + b): one DIFFERENCE and one SUM. It turns z by
// pi / 4 and scales it by the square root of 2, and its determinant is 2. Each floor drops one bit: its image is
// the pairs of equal parity. Eight floors close the turn and leave 16 z. Every lane runs on the device and on the
// host, word for word, and every floor is checked against the Gaussian product z (1 + i)^k taken on the CPU from the
// powers' polar form, not from the floor. keymath carries every register as a linear form over the two fields and
// bounds it by the sum of |coefficient| 2^bits. After k floors the coefficients are the parts of (1 + i)^k, whose
// magnitudes sum to 2^ceil(k/2). The widths are 24 + ceil(k/2): they grow half a bit a floor, as the values do, and
// some lane fills each one.
// The test is one job on the device's tessera daemon, submitted before the program is loaded onto the device.
#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"
#include "sim.h"

#define GAUSSIAN_TEST_LANES 4096u

#define GAUSSIAN_TEST_FLOORS 8u

#define GAUSSIAN_TEST_FIELD_BITS 24u

// the two fields, then a DIFFERENCE and a SUM a floor
#define GAUSSIAN_TEST_STEPS (2u + (2u * GAUSSIAN_TEST_FLOORS))

// both registers of every floor
#define GAUSSIAN_TEST_OUTPUTS (2u * GAUSSIAN_TEST_FLOORS)

// the kinds of field value: 0, -1, 1, the most negative and the most positive, then drawn
#define GAUSSIAN_TEST_EDGES 5u

unsigned int gaussian_random(void);

long long gaussian_value(unsigned int kind);

unsigned int gaussian_word(long long value);

// The inverse floor, (c, d) -> ((c + d) / 2, (d - c) / 2), is z -> z / (1 + i): a SUM, a DIFFERENCE and two
// EXACT_QUOTIENTs by the constant 2. On the pairs of equal parity, the floor's image, it is exact; a pair of mixed
// parity leaves a remainder, and the machine errors on its lane. So j inverse floors run on c + d i exactly where (1 +
// i)^j divides it, its (1 + i)-adic valuation at least j, and the lane errors otherwise.
#define GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR 4u

// the two fields and the constant 2, then four steps a floor
#define GAUSSIAN_TEST_INVERSE_STEPS (3u + (GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR * GAUSSIAN_TEST_FLOORS))

// the chosen pairs: w (1 + i)^k for k from 0 to 9 and six drawn w of valuation 0, then 0, which every floor divides
#define GAUSSIAN_TEST_POWERS 10u

#define GAUSSIAN_TEST_UNITS 6u

#define GAUSSIAN_TEST_PAIRS ((GAUSSIAN_TEST_POWERS * GAUSSIAN_TEST_UNITS) + 1u)

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
} GaussianLoaded;

int gaussian_inverse_build(unsigned int floors, GaussianLoaded *loaded, EngineError *error);

void gaussian_inverse_release(GaussianLoaded *loaded);

int gaussian_inverse_run(const GaussianLoaded *loaded, const unsigned int *atoms, unsigned int lanes,
                         unsigned int *host_out, unsigned int *device_out, EngineError *error);

unsigned int gaussian_valuation(long long real_part, long long imaginary_part, unsigned int maximum);

long long gaussian_take(const unsigned int *record, unsigned int offset, unsigned int bits);

#endif
