// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_order_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_ORDER_TEST_INTERNAL_H
#define RECORD_ORDER_TEST_INTERNAL_H

//
// The loop rule's orders on the record machine, both ways. A floor G over four 32-bit words is made of shears, each
// adding to one word a function of the others and wrapping to 32 bits. G is a bijection whatever the functions
// are, and G^-1 undoes the shears in reverse order. One word is the order's counter, n -> n + 1. The orders load
// themselves as the naturals, and the inverse carries them below zero. One program runs the orders 0 -> K -> -K -> 0
// with every floor tapped: each visit to order k must hold the CPU's G^k(x), the counter must read k, and the return
// to 0 is exact. Then the order omega on a finite window: a floor is a table permutation of the 16-bit states, its
// inverse table runs the negative orders, a third table reads a halt set, and an or gathers every bit's lim sup beside
// the floor. A bijection of a finite set has no transient. Every orbit is a cycle, and +omega and -omega are one
// stage: each bit's or over the cycle, and the halt flag set exactly when the cycle meets the halt set. The device
// decides every lane whose cycle fits its run; past the run a set flag is a halt seen, and a clear one is open. The
// test is one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define ORDER_TEST_LINE 8192ull

// the orders both ways: four 32-bit words (a, b, d and the counter n), K floors each way, every floor tapped
#define ORDER_TEST_WORDS 4u

#define ORDER_TEST_DEPTH 256u

#define ORDER_TEST_FLOORS (4u * ORDER_TEST_DEPTH)

#define ORDER_TEST_FLOOR_STEPS 12u

#define ORDER_TEST_LANES 512u

// the order omega: a permutation of the 16-bit states, the floors a run reads, the lanes, and the halt set's size
#define ORDER_TEST_STATE_BITS 16u

#define ORDER_TEST_STATES 65536u

#define ORDER_TEST_RUN 2048u

#define ORDER_TEST_OMEGA_STEPS 8u

#define ORDER_TEST_OMEGA_LANES 1024u

#define ORDER_TEST_HALTS 48u

// the most the test puts on the device at once: the orders' lanes, their four words in and every floor's four words
// out at no more than 33 bits each
#define ORDER_TEST_DECLARED                                                                                            \
    ((unsigned long long)ORDER_TEST_LANES *                                                                            \
     (ORDER_TEST_WORDS + (((ORDER_TEST_WORDS * ORDER_TEST_FLOORS * 33ull) + 31ull) / 32ull)) * sizeof(unsigned int))

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} OrderResults;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} OrderLoaded;

typedef struct
{
    EngineRecordStep *steps;
    unsigned int count;
} OrderStack;

typedef struct
{
    long long word[ORDER_TEST_WORDS];
} OrderState;

unsigned int order_random(void);

void order_check(OrderResults *results, int passed, const char *what);

unsigned int order_append(OrderStack *stack, EngineRecordOperation operation, unsigned int left, unsigned int right);

int order_load(const OrderStack *stack, const unsigned int *field_bits, const unsigned int *field_offset,
               unsigned int fields, unsigned int in_limbs, const unsigned int *outputs, unsigned int output_count,
               const EngineRecordTable *tables, unsigned int table_count, OrderLoaded *loaded);

void order_free(OrderLoaded *loaded);

void order_run(OrderLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
               unsigned int *device_out, int *host_ran, int *device_ran);

long long order_output(const OrderLoaded *loaded, const unsigned int *record, unsigned int step);

void order_both_ways(OrderResults *results);

#endif
