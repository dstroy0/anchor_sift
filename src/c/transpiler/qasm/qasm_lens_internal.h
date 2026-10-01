// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_lens_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_LENS_INTERNAL_H
#define QASM_LENS_INTERNAL_H

#include "../../engine/runtime/obsignatio/obsignatio.h"
#include "qasm.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define QASM_LENS_STATE_WORDS 8u
#define QASM_LENS_MESSAGE_WORDS 16u
#define QASM_LENS_RAW_BITS 256u
#define QASM_LENS_LIFT_WORDS (QASM_LENS_LIFT_BITS / 32u)
#define QASM_LENS_GENERATOR_BYTES 96u
#define QASM_LENS_GOLDEN 0x9E3779B97F4A7C15ull
#define QASM_LENS_FORWARD_SALT 0x5151ull
#define QASM_LENS_BACKWARD_SALT 0x8888ull

_Static_assert(UINT_MAX == 0xFFFFFFFFu, "qasm lens: a SHA-256 word is an unsigned int that wraps at 2^32");
_Static_assert(ULLONG_MAX == 0xFFFFFFFFFFFFFFFFull, "qasm lens: SplitMix's state is an unsigned long long of 64 bits");
_Static_assert(QASM_LENS_BITS_MAX < 32u, "qasm lens: an aperture index is an unsigned int, drawn below 2^32");
_Static_assert((QASM_LENS_ROUNDS_MAX >= QASM_LENS_MESSAGE_WORDS) && (QASM_LENS_ROUNDS_MAX <= 64u),
               "qasm lens: a schedule holds the 16 message words and at most SHA-256's 64 rounds");
_Static_assert(QASM_LENS_LIFT_BITS == (2u * QASM_LENS_RAW_BITS),
               "qasm lens: the lift is the raw 256 bits and 256 AND-monomials");
_Static_assert(QASM_LENS_GENERATOR_BYTES >= (QASM_LENS_LIFT_BITS / 8u),
               "qasm lens: a generator's sealed bytes cover the lift's columns, as the Python's 96 do");
_Static_assert(ENGINE_SIGNUM_BYTES == OBSIGNATIO_SIGNUM_BYTES, "qasm lens: a reading's root is one obsignatio seal");
_Static_assert(((2ull << QASM_LENS_BITS_MAX) * QASM_LENS_GENERATOR_BYTES) <= SIZE_MAX,
               "qasm lens: both strands' generator bytes at the widest aperture fit one allocation");

// __LINE__ is a positive int. It converts to unsigned int unchanged
#define QASM_CHECK(condition_, evacaddr_, error_)                                                                      \
    engine_error_check((condition_), ENGINE_ERROR_REQUEST, ENGINE_MODULE_QASM, (unsigned int)__LINE__,                 \
                       (const void *)(evacaddr_), (error_))

// __LINE__ is a positive int. It converts to unsigned int unchanged
#define QASM_HAD(condition_, evacaddr_, error_)                                                                        \
    engine_error_check((condition_), ENGINE_ERROR_RESOURCE, ENGINE_MODULE_QASM, (unsigned int)__LINE__,                \
                       (const void *)(evacaddr_), (error_))

typedef struct
{
    unsigned int word[QASM_LENS_STATE_WORDS];
} QasmLensState;

_Static_assert(sizeof(QasmLensState) == (4u * QASM_LENS_STATE_WORDS),
               "qasm lens: a state has no padding, so memcmp compares its words alone");

typedef struct
{
    unsigned int word[QASM_LENS_LIFT_WORDS];
} QasmLensRow;

typedef struct
{
    QasmLensRow pivot_row[QASM_LENS_LIFT_BITS];
    unsigned char occupied[QASM_LENS_LIFT_BITS];
    unsigned int rank;
} QasmLensBasis;

typedef struct
{
    unsigned long long state;
} QasmLensSplitMix;

QasmLensSplitMix qasm_lens_splitmix_start(unsigned long long seed, unsigned long long instance);

unsigned int qasm_lens_splitmix_bits(QasmLensSplitMix *draws, unsigned int count);

void qasm_lens_schedule_expand(const unsigned int *message, unsigned int rounds, unsigned int *schedule);

QasmLensState qasm_lens_forward_from_state(const QasmLensState *state, const unsigned int *schedule, unsigned int low,
                                           unsigned int high);

QasmLensState qasm_lens_invert_from_state(const QasmLensState *state, const unsigned int *schedule, unsigned int high,
                                          unsigned int low);

QasmLensState qasm_lens_instance_draw(const QasmLensRequest *request, QasmLensState *anchor, unsigned int *base);

void qasm_lens_forward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                   const unsigned int *base, const QasmLensState *target, QasmLensState *table);

void qasm_lens_backward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                    const unsigned int *base, QasmLensState *table);

#endif
