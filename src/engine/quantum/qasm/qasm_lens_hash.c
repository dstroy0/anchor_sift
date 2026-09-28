// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_lens_hash.c: splitmix and the hash rounds
#include "qasm_lens_internal.h"

static const unsigned int qasm_lens_round_constant[64u] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

QasmLensSplitMix qasm_lens_splitmix_start(unsigned long long seed, unsigned long long instance)
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

unsigned int qasm_lens_splitmix_bits(QasmLensSplitMix *draws, unsigned int count)
{
    // masked below 2^count, count at most QASM_LENS_BITS_MAX < 32, which an unsigned int holds exactly
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

void qasm_lens_schedule_expand(const unsigned int *message, unsigned int rounds, unsigned int *schedule)
{
    memcpy(schedule, message, QASM_LENS_MESSAGE_WORDS * sizeof(unsigned int));
    for (unsigned int index = QASM_LENS_MESSAGE_WORDS; index < rounds; index += 1u)
    {
        schedule[index] = qasm_lens_small_sigma1(schedule[index - 2u]) + schedule[index - 7u] +
                          qasm_lens_small_sigma0(schedule[index - 15u]) + schedule[index - 16u];
    }
}

static QasmLensState qasm_lens_round_forward(const QasmLensState *state, unsigned int schedule_word,
                                             unsigned int constant)
{
    const unsigned int schedule_term = state->word[7u] + qasm_lens_big_sigma1(state->word[4u]) +
                                       qasm_lens_choose(state->word[4u], state->word[5u], state->word[6u]) + constant +
                                       schedule_word;
    const unsigned int majority_term =
        qasm_lens_big_sigma0(state->word[0u]) + qasm_lens_majority(state->word[0u], state->word[1u], state->word[2u]);
    const QasmLensState next = {{schedule_term + majority_term, state->word[0u], state->word[1u], state->word[2u],
                                 state->word[3u] + schedule_term, state->word[4u], state->word[5u], state->word[6u]}};
    return next;
}

static QasmLensState qasm_lens_round_inverse(const QasmLensState *next, unsigned int schedule_word,
                                             unsigned int constant)
{
    // the four straight shifts unwind directly; the two sums are taken back out
    const unsigned int majority_term =
        qasm_lens_big_sigma0(next->word[1u]) + qasm_lens_majority(next->word[1u], next->word[2u], next->word[3u]);
    const unsigned int schedule_term = next->word[0u] - majority_term;
    const QasmLensState previous = {{next->word[1u], next->word[2u], next->word[3u], next->word[4u] - schedule_term,
                                     next->word[5u], next->word[6u], next->word[7u],
                                     schedule_term - qasm_lens_big_sigma1(next->word[5u]) -
                                         qasm_lens_choose(next->word[5u], next->word[6u], next->word[7u]) - constant -
                                         schedule_word}};
    return previous;
}

QasmLensState qasm_lens_forward_from_state(const QasmLensState *state, const unsigned int *schedule, unsigned int low,
                                           unsigned int high)
{
    QasmLensState walked = *state;
    for (unsigned int index = low; index < high; index += 1u)
    {
        walked = qasm_lens_round_forward(&walked, schedule[index], qasm_lens_round_constant[index]);
    }
    return walked;
}

QasmLensState qasm_lens_invert_from_state(const QasmLensState *state, const unsigned int *schedule, unsigned int high,
                                          unsigned int low)
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
    message[request->forward_word] = qasm_lens_set_low_bits(base[request->forward_word], secret_forward, request->bits);
    message[request->backward_word] =
        qasm_lens_set_low_bits(base[request->backward_word], secret_backward, request->bits);
    unsigned int schedule[QASM_LENS_ROUNDS_MAX];
    qasm_lens_schedule_expand(message, request->rounds, schedule);
    const QasmLensState chaining_input = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    const QasmLensState final_state = qasm_lens_forward_from_state(anchor, schedule, request->middle, request->rounds);
    return qasm_lens_wordwise_add(&chaining_input, &final_state);
}

QasmLensState qasm_lens_instance_draw(const QasmLensRequest *request, QasmLensState *anchor, unsigned int *base)
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

void qasm_lens_forward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                   const unsigned int *base, const QasmLensState *target, QasmLensState *table)
{
    unsigned int message[QASM_LENS_MESSAGE_WORDS];
    memcpy(message, base, sizeof(message));
    for (unsigned int image = 0u; image < (1u << request->bits); image += 1u)
    {
        message[request->forward_word] = qasm_lens_set_low_bits(base[request->forward_word], image, request->bits);
        unsigned int schedule[QASM_LENS_ROUNDS_MAX];
        qasm_lens_schedule_expand(message, request->rounds, schedule);
        const QasmLensState final_state =
            qasm_lens_forward_from_state(anchor, schedule, request->middle, request->rounds);
        table[image] = qasm_lens_wordwise_subtract(target, &final_state);
    }
}

void qasm_lens_backward_field_table(const QasmLensRequest *request, const QasmLensState *anchor,
                                    const unsigned int *base, QasmLensState *table)
{
    unsigned int message[QASM_LENS_MESSAGE_WORDS];
    memcpy(message, base, sizeof(message));
    for (unsigned int image = 0u; image < (1u << request->bits); image += 1u)
    {
        message[request->backward_word] = qasm_lens_set_low_bits(base[request->backward_word], image, request->bits);
        unsigned int schedule[QASM_LENS_ROUNDS_MAX];
        qasm_lens_schedule_expand(message, request->rounds, schedule);
        table[image] = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    }
}
