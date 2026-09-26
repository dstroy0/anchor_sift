// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"
#include "obsignatio.h"

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
_Static_assert(QASM_LENS_BITS_MOST < 32u, "qasm lens: an aperture index is an unsigned int, drawn below 2^32");
_Static_assert((QASM_LENS_ROUNDS_MOST >= QASM_LENS_MESSAGE_WORDS) && (QASM_LENS_ROUNDS_MOST <= 64u),
               "qasm lens: a schedule holds the 16 message words and at most SHA-256's 64 rounds");
_Static_assert(QASM_LENS_LIFT_BITS == (2u * QASM_LENS_RAW_BITS),
               "qasm lens: the lift is the raw 256 bits and 256 AND-monomials");
_Static_assert(QASM_LENS_GENERATOR_BYTES >= (QASM_LENS_LIFT_BITS / 8u),
               "qasm lens: a generator's sealed bytes cover the lift's columns, as the Python's 96 do");
_Static_assert(ENGINE_SIGNUM_BYTES == OBSIGNATIO_SIGNUM_BYTES, "qasm lens: a reading's root is one obsignatio seal");
_Static_assert(((2ull << QASM_LENS_BITS_MOST) * QASM_LENS_GENERATOR_BYTES) <= SIZE_MAX,
               "qasm lens: both strands' generator bytes at the widest aperture fit one allocation");

// __LINE__ is a positive int, so it converts to unsigned int unchanged
#define QASM_HELD(held_, evacaddr_, error_) \
    engine_error_check((held_), ENGINE_ERROR_REQUEST, ENGINE_MODULE_QASM, (unsigned int)__LINE__, \
                       (const void *)(evacaddr_), (error_))

// __LINE__ is a positive int, so it converts to unsigned int unchanged
#define QASM_HAD(held_, evacaddr_, error_) \
    engine_error_check((held_), ENGINE_ERROR_RESOURCE, ENGINE_MODULE_QASM, (unsigned int)__LINE__, \
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
    unsigned char held[QASM_LENS_LIFT_BITS];
    unsigned int rank;
} QasmLensBasis;

typedef struct
{
    unsigned long long state;
} QasmLensSplitMix;

static const unsigned int qasm_lens_round_constant[64u] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

static QasmLensSplitMix qasm_lens_splitmix_start(unsigned long long seed, unsigned long long instance)
{
    const QasmLensSplitMix draws = {seed + (instance * QASM_LENS_GOLDEN)};
    return draws;
}

static unsigned long long qasm_lens_splitmix_next(QasmLensSplitMix *draws)
{
    draws->state += QASM_LENS_GOLDEN;
    const unsigned long long mixed = (draws->state ^ (draws->state >> 30u)) * 0xBF58476D1CE4E5B9ull;
    const unsigned long long remixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return remixed ^ (remixed >> 31u);
}

static unsigned int qasm_lens_splitmix_word(QasmLensSplitMix *draws)
{
    // masked to its low 32 bits, which an unsigned int holds exactly
    return (unsigned int)(qasm_lens_splitmix_next(draws) & 0xFFFFFFFFull);
}

static unsigned int qasm_lens_splitmix_bits(QasmLensSplitMix *draws, unsigned int count)
{
    // masked below 2^count, count at most QASM_LENS_BITS_MOST < 32, which an unsigned int holds exactly
    return (unsigned int)(qasm_lens_splitmix_next(draws) & ((1ull << count) - 1ull));
}

static unsigned int qasm_lens_rotate_right(unsigned int word, unsigned int count)
{
    return (word >> count) | (word << (32u - count));
}

static unsigned int qasm_lens_big_sigma0(unsigned int word)
{
    return qasm_lens_rotate_right(word, 2u) ^ qasm_lens_rotate_right(word, 13u) ^ qasm_lens_rotate_right(word, 22u);
}

static unsigned int qasm_lens_big_sigma1(unsigned int word)
{
    return qasm_lens_rotate_right(word, 6u) ^ qasm_lens_rotate_right(word, 11u) ^ qasm_lens_rotate_right(word, 25u);
}

static unsigned int qasm_lens_small_sigma0(unsigned int word)
{
    return qasm_lens_rotate_right(word, 7u) ^ qasm_lens_rotate_right(word, 18u) ^ (word >> 3u);
}

static unsigned int qasm_lens_small_sigma1(unsigned int word)
{
    return qasm_lens_rotate_right(word, 17u) ^ qasm_lens_rotate_right(word, 19u) ^ (word >> 10u);
}

static unsigned int qasm_lens_choose(unsigned int selector, unsigned int when_set, unsigned int when_clear)
{
    return (selector & when_set) ^ (~selector & when_clear);
}

static unsigned int qasm_lens_majority(unsigned int first, unsigned int second, unsigned int third)
{
    return (first & second) ^ (first & third) ^ (second & third);
}

static void qasm_lens_schedule_expand(const unsigned int *message, unsigned int rounds, unsigned int *schedule)
{
    memcpy(schedule, message, QASM_LENS_MESSAGE_WORDS * sizeof(unsigned int));
    for (unsigned int index = QASM_LENS_MESSAGE_WORDS; index < rounds; index += 1u)
    {
        schedule[index] = qasm_lens_small_sigma1(schedule[index - 2u]) + schedule[index - 7u]
                        + qasm_lens_small_sigma0(schedule[index - 15u]) + schedule[index - 16u];
    }
}

static QasmLensState qasm_lens_round_forward(const QasmLensState *state, unsigned int schedule_word,
                                             unsigned int constant)
{
    const unsigned int schedule_term = state->word[7u] + qasm_lens_big_sigma1(state->word[4u])
                                     + qasm_lens_choose(state->word[4u], state->word[5u], state->word[6u]) + constant
                                     + schedule_word;
    const unsigned int majority_term = qasm_lens_big_sigma0(state->word[0u])
                                     + qasm_lens_majority(state->word[0u], state->word[1u], state->word[2u]);
    const QasmLensState next = {{schedule_term + majority_term, state->word[0u], state->word[1u], state->word[2u],
                                 state->word[3u] + schedule_term, state->word[4u], state->word[5u], state->word[6u]}};
    return next;
}

static QasmLensState qasm_lens_round_inverse(const QasmLensState *next, unsigned int schedule_word,
                                             unsigned int constant)
{
    // the four straight shifts unwind directly; the two sums are taken back out
    const unsigned int majority_term = qasm_lens_big_sigma0(next->word[1u])
                                     + qasm_lens_majority(next->word[1u], next->word[2u], next->word[3u]);
    const unsigned int schedule_term = next->word[0u] - majority_term;
    const QasmLensState previous = {{next->word[1u], next->word[2u], next->word[3u], next->word[4u] - schedule_term,
                                     next->word[5u], next->word[6u], next->word[7u],
                                     schedule_term - qasm_lens_big_sigma1(next->word[5u])
                                         - qasm_lens_choose(next->word[5u], next->word[6u], next->word[7u]) - constant
                                         - schedule_word}};
    return previous;
}

static QasmLensState qasm_lens_forward_from_state(const QasmLensState *state, const unsigned int *schedule,
                                                  unsigned int low, unsigned int high)
{
    QasmLensState walked = *state;
    for (unsigned int index = low; index < high; index += 1u)
    {
        walked = qasm_lens_round_forward(&walked, schedule[index], qasm_lens_round_constant[index]);
    }
    return walked;
}

static QasmLensState qasm_lens_invert_from_state(const QasmLensState *state, const unsigned int *schedule,
                                                 unsigned int high, unsigned int low)
{
    QasmLensState walked = *state;
    for (unsigned int index = high; index > low; index -= 1u)
    {
        walked = qasm_lens_round_inverse(&walked, schedule[index - 1u], qasm_lens_round_constant[index - 1u]);
    }
    return walked;
}

static unsigned int qasm_lens_set_low_bits(unsigned int word, unsigned int value, unsigned int bits)
{
    return ((word >> bits) << bits) | (value & ((1u << bits) - 1u));
}

static QasmLensState qasm_lens_wordwise_subtract(const QasmLensState *left, const QasmLensState *right)
{
    QasmLensState difference;
    for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
    {
        difference.word[word] = left->word[word] - right->word[word];
    }
    return difference;
}

static QasmLensState qasm_lens_wordwise_add(const QasmLensState *left, const QasmLensState *right)
{
    QasmLensState sum;
    for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
    {
        sum.word[word] = left->word[word] + right->word[word];
    }
    return sum;
}

static QasmLensState qasm_lens_biclique_plant(const QasmLensRequest *request, const QasmLensState *anchor,
                                              const unsigned int *base, unsigned int secret_forward,
                                              unsigned int secret_backward)
{
    unsigned int message[QASM_LENS_MESSAGE_WORDS];
    memcpy(message, base, sizeof(message));
    message[request->forward_word] = qasm_lens_set_low_bits(base[request->forward_word], secret_forward,
                                                            request->bits);
    message[request->backward_word] = qasm_lens_set_low_bits(base[request->backward_word], secret_backward,
                                                             request->bits);
    unsigned int schedule[QASM_LENS_ROUNDS_MOST];
    qasm_lens_schedule_expand(message, request->rounds, schedule);
    const QasmLensState chaining_input = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    const QasmLensState final_state = qasm_lens_forward_from_state(anchor, schedule, request->middle,
                                                                   request->rounds);
    return qasm_lens_wordwise_add(&chaining_input, &final_state);
}

static QasmLensState qasm_lens_instance_draw(const QasmLensRequest *request, QasmLensState *anchor,
                                             unsigned int *base)
{
    QasmLensSplitMix draws = qasm_lens_splitmix_start(request->seed, request->instance);
    for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
    {
        anchor->word[word] = qasm_lens_splitmix_word(&draws);
    }
    for (unsigned int word = 0u; word < QASM_LENS_MESSAGE_WORDS; word += 1u)
    {
        base[word] = qasm_lens_splitmix_word(&draws);
    }
    // the forward secret is drawn before the backward one, as the Python's arguments evaluate
    const unsigned int secret_forward = qasm_lens_splitmix_bits(&draws, request->bits);
    const unsigned int secret_backward = qasm_lens_splitmix_bits(&draws, request->bits);
    return qasm_lens_biclique_plant(request, anchor, base, secret_forward, secret_backward);
}

static void qasm_lens_forward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                          const unsigned int *base, const QasmLensState *target,
                                          QasmLensState *table)
{
    unsigned int message[QASM_LENS_MESSAGE_WORDS];
    memcpy(message, base, sizeof(message));
    for (unsigned int image = 0u; image < (1u << request->bits); image += 1u)
    {
        message[request->forward_word] = qasm_lens_set_low_bits(base[request->forward_word], image, request->bits);
        unsigned int schedule[QASM_LENS_ROUNDS_MOST];
        qasm_lens_schedule_expand(message, request->rounds, schedule);
        const QasmLensState final_state = qasm_lens_forward_from_state(anchor, schedule, request->middle,
                                                                       request->rounds);
        table[image] = qasm_lens_wordwise_subtract(target, &final_state);
    }
}

static void qasm_lens_backward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                           const unsigned int *base, QasmLensState *table)
{
    unsigned int message[QASM_LENS_MESSAGE_WORDS];
    memcpy(message, base, sizeof(message));
    for (unsigned int image = 0u; image < (1u << request->bits); image += 1u)
    {
        message[request->backward_word] = qasm_lens_set_low_bits(base[request->backward_word], image,
                                                                 request->bits);
        unsigned int schedule[QASM_LENS_ROUNDS_MOST];
        qasm_lens_schedule_expand(message, request->rounds, schedule);
        table[image] = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    }
}

static unsigned int qasm_lens_row_bit(const QasmLensRow *row, unsigned int column)
{
    return (row->word[column / 32u] >> (column % 32u)) & 1u;
}

static QasmLensRow qasm_lens_generator_row(const QasmLensState *table, unsigned int image, int lifted)
{
    QasmLensRow row;
    memset(&row, 0, sizeof(row));
    for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
    {
        row.word[word] = table[image].word[word] ^ table[0].word[word];
    }
    if (lifted != 0)
    {
        for (unsigned int index = 0u; index < (QASM_LENS_LIFT_BITS - QASM_LENS_RAW_BITS); index += 1u)
        {
            // the Python lift's pairing: bit index against bit (131 index + 17) mod 256, never itself
            const unsigned int partner = ((index * 131u) + 17u) & 255u;
            const unsigned int other = (partner == index) ? ((partner + 1u) & 255u) : partner;
            const unsigned int column = QASM_LENS_RAW_BITS + index;
            row.word[column / 32u] |= (qasm_lens_row_bit(&row, index) & qasm_lens_row_bit(&row, other))
                                   << (column % 32u);
        }
    }
    return row;
}

static void qasm_lens_basis_insert(QasmLensBasis *basis, QasmLensRow row, unsigned int columns)
{
    // a full basis spans every row: the rest reduce to zero and add no rank
    if (basis->rank == columns)
    {
        return;
    }
    for (unsigned int column = 0u; column < columns; column += 1u)
    {
        if (qasm_lens_row_bit(&row, column) != 0u)
        {
            if (basis->held[column] == 0u)
            {
                basis->pivot_row[column] = row;
                basis->held[column] = 1u;
                basis->rank += 1u;
                return;
            }
            for (unsigned int word = column / 32u; word < (columns / 32u); word += 1u)
            {
                row.word[word] ^= basis->pivot_row[column].word[word];
            }
        }
    }
}

static unsigned int qasm_lens_rank(const QasmLensState *forward_table, const QasmLensState *backward_table,
                                   unsigned int size, int lifted, QasmLensBasis *basis)
{
    memset(basis, 0, sizeof(*basis));
    const unsigned int columns = (lifted != 0) ? QASM_LENS_LIFT_BITS : QASM_LENS_RAW_BITS;
    const QasmLensState *const tables[2u] = {forward_table, backward_table};
    for (unsigned int strand = 0u; strand < 2u; strand += 1u)
    {
        for (unsigned int image = 1u; image < size; image += 1u)
        {
            qasm_lens_basis_insert(basis, qasm_lens_generator_row(tables[strand], image, lifted), columns);
        }
    }
    return basis->rank;
}

static int qasm_lens_clock_closes(const QasmLensRequest *request, const QasmLensState *anchor,
                                  const unsigned int *base)
{
    unsigned int schedule[QASM_LENS_ROUNDS_MOST];
    qasm_lens_schedule_expand(base, request->rounds, schedule);
    const QasmLensState chaining_input = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    const QasmLensState returned = qasm_lens_forward_from_state(&chaining_input, schedule, 0u, request->middle);
    return memcmp(&returned, anchor, sizeof(QasmLensState)) == 0;
}

static unsigned int qasm_lens_curvature_vanish(const QasmLensState *table, unsigned int bits,
                                               QasmLensSplitMix *draws)
{
    // an aperture below 4 images counts every sample as vanished, as the Python's 1.0 does
    if ((1u << bits) < 4u)
    {
        return QASM_LENS_CURVATURE_SAMPLES;
    }
    unsigned int vanish = 0u;
    for (unsigned int sample = 0u; sample < QASM_LENS_CURVATURE_SAMPLES; sample += 1u)
    {
        const unsigned int origin = qasm_lens_splitmix_bits(draws, bits);
        const unsigned int first_step = qasm_lens_splitmix_bits(draws, bits);
        const unsigned int second_step = qasm_lens_splitmix_bits(draws, bits);
        unsigned int second_difference = 0u;
        for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
        {
            second_difference |= table[origin].word[word] ^ table[origin ^ first_step].word[word]
                               ^ table[origin ^ second_step].word[word]
                               ^ table[origin ^ first_step ^ second_step].word[word];
        }
        if (second_difference == 0u)
        {
            vanish += 1u;
        }
    }
    return vanish;
}

static int qasm_lens_state_order(const void *left, const void *right)
{
    return memcmp(left, right, sizeof(QasmLensState));
}

static unsigned long long qasm_lens_fiber_count(QasmLensState *table, unsigned int size)
{
    // sorts the table in place: the caller reads it no further
    qsort(table, size, sizeof(QasmLensState), qasm_lens_state_order);
    unsigned long long distinct = 1ull;
    for (unsigned int image = 1u; image < size; image += 1u)
    {
        if (memcmp(&table[image], &table[image - 1u], sizeof(QasmLensState)) != 0)
        {
            distinct += 1ull;
        }
    }
    return distinct;
}

static void qasm_lens_generator_bytes(const QasmLensState *table, unsigned int size, unsigned char *bytes,
                                      unsigned int first_generator)
{
    for (unsigned int image = 1u; image < size; image += 1u)
    {
        const size_t generator = first_generator + (image - 1u);
        unsigned char *const generator_slot = &bytes[generator * QASM_LENS_GENERATOR_BYTES];
        for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
        {
            const unsigned int value = table[image].word[word] ^ table[0].word[word];
            for (unsigned int byte = 0u; byte < 4u; byte += 1u)
            {
                // one byte of the word, masked to eight bits, which an unsigned char holds exactly
                generator_slot[(4u * word) + byte] = (unsigned char)((value >> (8u * byte)) & 0xFFu);
            }
        }
    }
}

static long qasm_lens_seal(const unsigned char *bytes, unsigned long long generators, unsigned char *signum,
                           EngineError *error)
{
    const ObsignatioSealRequest seal = {bytes, generators * QASM_LENS_GENERATOR_BYTES, signum, error};
    return obsignatio_seal(&seal);
}

static int qasm_lens_request_held(const QasmLensRequest *request, EngineError *error)
{
    return QASM_HELD((request->rounds <= QASM_LENS_ROUNDS_MOST) && (request->middle < request->rounds)
                         && (request->forward_word < QASM_LENS_MESSAGE_WORDS)
                         && (request->backward_word < QASM_LENS_MESSAGE_WORDS)
                         && (request->bits <= QASM_LENS_BITS_MOST),
                     request, error);
}

long qasm_lens_read(const QasmLensRequest *request, QasmLensReading *reading, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    if (!QASM_HELD((request != NULL) && (reading != NULL), request, error) || !qasm_lens_request_held(request, error))
    {
        return QASM_REFUSED;
    }
    const unsigned int size = 1u << request->bits;
    const unsigned int generators = 2u * (size - 1u);
    QasmLensState *const forward_table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    QasmLensState *const backward_table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    unsigned char *const generator_bytes = (generators != 0u)
                                         ? (unsigned char *)calloc(generators, QASM_LENS_GENERATOR_BYTES) : NULL;
    QasmLensBasis *const basis = (QasmLensBasis *)calloc(1u, sizeof(QasmLensBasis));
    if (!QASM_HAD((forward_table != NULL) && (backward_table != NULL)
                      && ((generators == 0u) || (generator_bytes != NULL)) && (basis != NULL),
                  request, error))
    {
        free(forward_table);
        free(backward_table);
        free(generator_bytes);
        free(basis);
        return QASM_REFUSED;
    }
    QasmLensState anchor;
    unsigned int base[QASM_LENS_MESSAGE_WORDS];
    const QasmLensState target = qasm_lens_instance_draw(request, &anchor, base);
    qasm_lens_forward_field_table(request, &anchor, base, &target, forward_table);
    qasm_lens_backward_field_table(request, &anchor, base, backward_table);
    const unsigned int raw_rank = qasm_lens_rank(forward_table, backward_table, size, 0, basis);
    const unsigned int lift_rank = qasm_lens_rank(forward_table, backward_table, size, 1, basis);
    const int reversible = qasm_lens_clock_closes(request, &anchor, base);
    qasm_lens_generator_bytes(forward_table, size, generator_bytes, 0u);
    qasm_lens_generator_bytes(backward_table, size, generator_bytes, size - 1u);
    // the read is taken twice over the same generators, as the Python re-reads its witness root
    unsigned char root[ENGINE_SIGNUM_BYTES];
    unsigned char root_again[ENGINE_SIGNUM_BYTES];
    const int sealed = (qasm_lens_seal(generator_bytes, generators, root, error) == 0L)
                    && (qasm_lens_seal(generator_bytes, generators, root_again, error) == 0L);
    QasmLensSplitMix forward_draws = qasm_lens_splitmix_start(request->seed,
                                                              request->instance ^ QASM_LENS_FORWARD_SALT);
    QasmLensSplitMix backward_draws = qasm_lens_splitmix_start(request->seed,
                                                               request->instance ^ QASM_LENS_BACKWARD_SALT);
    const unsigned int forward_vanish = qasm_lens_curvature_vanish(forward_table, request->bits, &forward_draws);
    const unsigned int backward_vanish = qasm_lens_curvature_vanish(backward_table, request->bits, &backward_draws);
    const unsigned long long forward_fiber = qasm_lens_fiber_count(forward_table, size);
    const unsigned long long backward_fiber = qasm_lens_fiber_count(backward_table, size);
    free(forward_table);
    free(backward_table);
    free(generator_bytes);
    free(basis);
    if (!sealed)
    {
        return QASM_REFUSED;
    }
    reading->raw_rank = raw_rank;
    // a rank over 256 columns is at most 256
    reading->complement = QASM_LENS_RAW_BITS - raw_rank;
    // the lift keeps the raw columns, so its rank is at least the raw rank
    reading->lift_extra_rank = lift_rank - raw_rank;
    reading->forward_vanish = forward_vanish;
    reading->backward_vanish = backward_vanish;
    reading->forward_fiber = forward_fiber;
    reading->backward_fiber = backward_fiber;
    reading->reversible = reversible;
    reading->root_stable = memcmp(root, root_again, ENGINE_SIGNUM_BYTES) == 0;
    memcpy(reading->root, root, ENGINE_SIGNUM_BYTES);
    return 0L;
}

long qasm_lens_seal_check(const QasmLensRequest *request, unsigned char *clean, unsigned char *flipped,
                          EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    // the Python flips a bit of the first generator, which an empty aperture does not have
    if (!QASM_HELD((request != NULL) && (clean != NULL) && (flipped != NULL), request, error)
        || !qasm_lens_request_held(request, error) || !QASM_HELD(request->bits != 0u, request, error))
    {
        return QASM_REFUSED;
    }
    const unsigned int size = 1u << request->bits;
    const unsigned int generators = size - 1u;
    QasmLensState *const table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    unsigned char *const generator_bytes = (unsigned char *)calloc(generators, QASM_LENS_GENERATOR_BYTES);
    if (!QASM_HAD((table != NULL) && (generator_bytes != NULL), request, error))
    {
        free(table);
        free(generator_bytes);
        return QASM_REFUSED;
    }
    QasmLensState anchor;
    unsigned int base[QASM_LENS_MESSAGE_WORDS];
    const QasmLensState target = qasm_lens_instance_draw(request, &anchor, base);
    qasm_lens_forward_field_table(request, &anchor, base, &target, table);
    qasm_lens_generator_bytes(table, size, generator_bytes, 0u);
    unsigned char clean_root[ENGINE_SIGNUM_BYTES];
    unsigned char flipped_root[ENGINE_SIGNUM_BYTES];
    const int clean_sealed = qasm_lens_seal(generator_bytes, generators, clean_root, error) == 0L;
    // one bit, the lowest of the first generator
    generator_bytes[0] ^= 1u;
    const int sealed = clean_sealed && (qasm_lens_seal(generator_bytes, generators, flipped_root, error) == 0L);
    free(table);
    free(generator_bytes);
    if (!sealed)
    {
        return QASM_REFUSED;
    }
    memcpy(clean, clean_root, ENGINE_SIGNUM_BYTES);
    memcpy(flipped, flipped_root, ENGINE_SIGNUM_BYTES);
    return 0L;
}
