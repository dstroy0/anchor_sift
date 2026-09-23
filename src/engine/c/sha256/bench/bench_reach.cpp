/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_reach.cpp
 * @brief Exact reachability over the SHA-256 round graph, so absence can be told from effect.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Failure mode one in docs/failure-modes.md, and the one that has produced the most defects
 *       in this tree. H6 rotated the nonce, which enters at W[3] in round three, instead of the
 *       chaining value, and reported a decay that never happened. H23 measured through W[17],
 *       which does not depend on W[3], and reported 100.000% agreement, which was zero equalling
 *       zero. bench_closeness labeled rounds one to three "premise holds: no" when the nonce had
 *       not arrived yet. Three separate defects, one cause: measuring an effect along a path that
 *       does not exist, and reading the resulting nothing as a result.
 * @note The subtraction is a precondition instead of a correction. Before measuring how much of
 *       input X reaches output Y, establish that any path from X to Y exists at all. Where none
 *       does, the measurement is of absence and no sample size fixes it.
 * @note This is computed instead of sampled. The circuit is a fixed graph, so reachability is
 *       decidable, and "no path exists" is a constraint of a different kind from "no effect
 *       observed". Every state bit carries the set of input bits that can reach it, propagated
 *       through the real operations:
 *
 *         rotate right by n   output bit i takes input bit (i + n) mod 32
 *         shift right by n    output bit i takes input bit i + n, and nothing where that is off
 *         xor, and, or, not   output bit i takes bit i of each operand
 *         addition            output bit i takes bits 0 through i of both operands, by the carry
 *
 * @note Addition is the only one that widens, and it widens upward only. That is what makes the
 *       analysis an over-approximation: a path in this graph may still carry no influence, but the
 *       absence of a path is exact. An over-approximation is the right side to err on for a
 *       precondition, because it never says absent when something is present.
 * @note The sampled check is the control and runs in the opposite direction. Where the analysis
 *       says no path, flipping the input must never change the output, over many random messages.
 *       Where it says a path exists, some fraction must actually change. An analysis that claims
 *       reachability everywhere would pass the first test trivially, so both halves are needed.
 */

#include "sha256_core.h"

#include <bitset>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

namespace
{

/** @brief Message block bits, 16 words of 32. */
const unsigned MESSAGE_BITS = 512u;

/** @brief Chaining value bits, 8 words of 32. */
const unsigned CHAINING_BITS = 256u;

/** @brief Every input bit of one compression call. */
const unsigned INPUT_BITS = MESSAGE_BITS + CHAINING_BITS;

/** @brief Rounds in the compression function. */
const unsigned ROUNDS = 64u;

/** @brief The word holding the nonce in a Bitcoin header's second block. */
const unsigned NONCE_WORD = 3u;

/** @brief Which input bits can reach one bit of the circuit. */
typedef std::bitset<INPUT_BITS> Cone;

/** @brief A 32-bit word, one dependency set per bit, least significant bit first. */
struct WordCone
{
    Cone bit[32];
};

/**
 * @brief Rotates a word's dependency sets right, which permutes which bit holds which set.
 *
 * @param[in] source   Dependency sets to rotate [BORROWS].
 * @param[in] distance How far right.
 * @return             The rotated sets.
 */
WordCone rotate_right(const WordCone &source, unsigned distance)
{
    WordCone result;
    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        result.bit[position] = source.bit[(position + distance) & 31u];
    }
    return result;
}

/**
 * @brief Shifts a word's dependency sets right, dropping the sets that fall off the top.
 *
 * @param[in] source   Dependency sets to shift [BORROWS].
 * @param[in] distance How far right.
 * @return             The shifted sets, with the vacated high bits depending on nothing.
 */
WordCone shift_right(const WordCone &source, unsigned distance)
{
    WordCone result;
    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        if ((position + distance) < 32u)
        {
            result.bit[position] = source.bit[position + distance];
        }
    }
    return result;
}

/**
 * @brief Combines two words bitwise, which unions each bit's dependency set with its opposite.
 *
 * @param[in] left  One operand [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          The union, bit by bit.
 * @note This covers xor, and, or and every other bitwise operation at once, because at this
 *       granularity they differ in what they compute and not in what they read.
 */
WordCone combine_bitwise(const WordCone &left, const WordCone &right)
{
    WordCone result;
    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        result.bit[position] = left.bit[position] | right.bit[position];
    }
    return result;
}

/**
 * @brief Adds two words, which unions each bit's set with every lower bit of both operands.
 *
 * @param[in] left  One operand [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          The sum's dependency sets.
 * @note The carry is the whole reason addition differs from xor here. Bit i of a sum reads bits 0
 *       through i of both inputs, so addition is the only operation in SHA-256 that moves
 *       dependency upward through bit positions, and it is therefore the only reason the analysis
 *       is an over-approximation instead of exact.
 */
WordCone combine_addition(const WordCone &left, const WordCone &right)
{
    WordCone result;
    Cone running;
    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        running |= left.bit[position];
        running |= right.bit[position];
        result.bit[position] = running;
    }
    return result;
}

/** @brief The round's low mixing function, as dependency sets. */
WordCone mix_low(const WordCone &value)
{
    return combine_bitwise(combine_bitwise(rotate_right(value, 2u), rotate_right(value, 13u)),
                           rotate_right(value, 22u));
}

/** @brief The round's high mixing function, as dependency sets. */
WordCone mix_high(const WordCone &value)
{
    return combine_bitwise(combine_bitwise(rotate_right(value, 6u), rotate_right(value, 11u)),
                           rotate_right(value, 25u));
}

/** @brief The schedule's low expansion function, as dependency sets. */
WordCone expand_low(const WordCone &value)
{
    return combine_bitwise(combine_bitwise(rotate_right(value, 7u), rotate_right(value, 18u)),
                           shift_right(value, 3u));
}

/** @brief The schedule's high expansion function, as dependency sets. */
WordCone expand_high(const WordCone &value)
{
    return combine_bitwise(combine_bitwise(rotate_right(value, 17u), rotate_right(value, 19u)),
                           shift_right(value, 10u));
}

/**
 * @brief Builds the dependency sets of all 64 schedule words.
 *
 * @param[out] schedule Sixty-four words of dependency sets [BORROWS].
 * @note Words 0 through 15 depend on themselves alone, which seeds everything after them.
 */
void build_schedule(std::vector<WordCone> &schedule)
{
    schedule.assign(ROUNDS, WordCone());

    for (unsigned word = 0u; word < 16u; word += 1u)
    {
        for (unsigned position = 0u; position < 32u; position += 1u)
        {
            schedule[word].bit[position].set((word * 32u) + position);
        }
    }

    for (unsigned word = 16u; word < ROUNDS; word += 1u)
    {
        const WordCone high = expand_high(schedule[word - 2u]);
        const WordCone low = expand_low(schedule[word - 15u]);
        schedule[word] = combine_addition(
            combine_addition(high, schedule[word - 7u]),
            combine_addition(low, schedule[word - 16u]));
    }
}

/**
 * @brief Runs the dependency analysis through the rounds, recording the state after each.
 *
 * @param[in]  schedule Schedule dependency sets [BORROWS].
 * @param[out] history  State dependency sets after every round, 65 entries with entry 0 the input.
 */
void run_rounds(const std::vector<WordCone> &schedule,
                std::vector<std::vector<WordCone>> &history)
{
    std::vector<WordCone> state(8u);
    for (unsigned word = 0u; word < 8u; word += 1u)
    {
        for (unsigned position = 0u; position < 32u; position += 1u)
        {
            state[word].bit[position].set(MESSAGE_BITS + (word * 32u) + position);
        }
    }

    history.clear();
    history.push_back(state);

    for (unsigned round = 0u; round < ROUNDS; round += 1u)
    {
        // The round constant depends on no input, so it contributes nothing to a dependency set
        // and is absent here on purpose instead of by oversight.
        const WordCone choice = combine_bitwise(state[4], combine_bitwise(state[5], state[6]));
        const WordCone carry_one = combine_addition(
            combine_addition(state[7], mix_high(state[4])),
            combine_addition(choice, schedule[round]));
        const WordCone majority = combine_bitwise(state[0], combine_bitwise(state[1], state[2]));
        const WordCone carry_two = combine_addition(mix_low(state[0]), majority);

        std::vector<WordCone> next(8u);
        next[7] = state[6];
        next[6] = state[5];
        next[5] = state[4];
        next[4] = combine_addition(state[3], carry_one);
        next[3] = state[2];
        next[2] = state[1];
        next[1] = state[0];
        next[0] = combine_addition(carry_one, carry_two);

        state = next;
        history.push_back(state);
    }
}

/**
 * @brief Counts how many of a word's bits can be reached from a given input word.
 *
 * @param[in] cone       The word's dependency sets [BORROWS].
 * @param[in] input_word Which of the sixteen message words to ask about.
 * @return               How many of the 32 bits have a path from any bit of that word.
 */
unsigned bits_reached_from(const WordCone &cone, unsigned input_word)
{
    unsigned reached = 0u;
    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        for (unsigned source = 0u; source < 32u; source += 1u)
        {
            if (cone.bit[position].test((input_word * 32u) + source))
            {
                reached += 1u;
                break;
            }
        }
    }
    return reached;
}

/**
 * @brief Rotates a word right, on real values instead of dependency sets.
 *
 * @param[in] value    The word.
 * @param[in] distance How far.
 * @return             The rotated word.
 */
uint32_t rotate_word(uint32_t value, unsigned distance)
{
    distance &= 31u;
    return (distance == 0u) ? value : ((value >> distance) | (value << (32u - distance)));
}

/**
 * @brief Runs the real compression to a chosen round and returns the state.
 *
 * @param[in]  message Sixteen message words [BORROWS].
 * @param[in]  input   Eight chaining words [BORROWS].
 * @param[in]  rounds  How many rounds to run.
 * @param[out] output  Eight state words after those rounds [BORROWS].
 */
void compress_to(const uint32_t *message, const uint32_t *input, unsigned rounds, uint32_t *output)
{
    static const uint32_t ROUND_CONSTANT[64] = {
        0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
        0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
        0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
        0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
        0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
        0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
        0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
        0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
        0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
        0xc67178f2u};

    uint32_t schedule[64];
    for (unsigned word = 0u; word < 16u; word += 1u)
    {
        schedule[word] = message[word];
    }
    for (unsigned word = 16u; word < 64u; word += 1u)
    {
        const uint32_t high = rotate_word(schedule[word - 2u], 17u) ^
                              rotate_word(schedule[word - 2u], 19u) ^ (schedule[word - 2u] >> 10);
        const uint32_t low = rotate_word(schedule[word - 15u], 7u) ^
                             rotate_word(schedule[word - 15u], 18u) ^ (schedule[word - 15u] >> 3);
        schedule[word] = high + schedule[word - 7u] + low + schedule[word - 16u];
    }

    uint32_t state[8];
    for (unsigned word = 0u; word < 8u; word += 1u)
    {
        state[word] = input[word];
    }

    for (unsigned round = 0u; round < rounds; round += 1u)
    {
        const uint32_t high = rotate_word(state[4], 6u) ^ rotate_word(state[4], 11u) ^
                              rotate_word(state[4], 25u);
        const uint32_t choice = state[6] ^ (state[4] & (state[5] ^ state[6]));
        const uint32_t carry_one = state[7] + high + choice + ROUND_CONSTANT[round] +
                                   schedule[round];
        const uint32_t low = rotate_word(state[0], 2u) ^ rotate_word(state[0], 13u) ^
                             rotate_word(state[0], 22u);
        const uint32_t majority = (state[0] & state[1]) | (state[2] & (state[0] ^ state[1]));
        const uint32_t carry_two = low + majority;

        state[7] = state[6];
        state[6] = state[5];
        state[5] = state[4];
        state[4] = state[3] + carry_one;
        state[3] = state[2];
        state[2] = state[1];
        state[1] = state[0];
        state[0] = carry_one + carry_two;
    }

    for (unsigned word = 0u; word < 8u; word += 1u)
    {
        output[word] = state[word];
    }
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Exact reachability over the SHA-256 round graph\n");
    std::printf("================================================================\n");
    std::printf("\n  Failure mode one: measuring an effect along a path that does not exist and\n");
    std::printf("  reading the resulting nothing as a result. It has produced three defects here.\n");
    std::printf("  H6 rotated the nonce instead of the chaining value. H23 measured through\n");
    std::printf("  W[17], which does not depend on W[3], and reported 100.000%% agreement.\n");
    std::printf("  bench_closeness graded rounds one to three before the nonce had arrived.\n");
    std::printf("\n  This is computed, not sampled. Every state bit carries the set of input bits\n");
    std::printf("  that can reach it. Addition is the only operation that widens a set, upward\n");
    std::printf("  through the carry, so a path here may carry no influence but the absence of a\n");
    std::printf("  path is exact. That is the right side to err on for a precondition.\n");

    std::vector<WordCone> schedule;
    std::vector<std::vector<WordCone>> history;
    build_schedule(schedule);
    run_rounds(schedule, history);

    std::printf("\n================================================================\n");
    std::printf("  Where the nonce reaches, round by round\n");
    std::printf("================================================================\n");
    std::printf("\n  The nonce occupies W[%u] of the header's second block. A round writes only\n",
                NONCE_WORD);
    std::printf("  state[0] and state[4]; the other six are shifted copies. Both are shown.\n");
    std::printf("\n  The column counts rounds completed, not a round index. W[%u] is consumed by\n",
                NONCE_WORD);
    std::printf("  the fourth round, which is index %u counting from zero, so the first row that\n",
                NONCE_WORD);
    std::printf("  can carry it is the one reading 4. The two conventions name the same round and\n");
    std::printf("  confusing them is how this was got wrong before.\n");
    std::printf("\n  %14s %18s %18s %14s\n", "rounds done", "bits of state[0]", "bits of state[4]",
                "verdict");
    std::printf("  %14s %18s %18s %14s\n", "--------------", "------------------",
                "------------------", "--------------");

    unsigned first_arrival = ROUNDS + 1u;
    for (unsigned round = 1u; round <= 12u; round += 1u)
    {
        const unsigned in_zero = bits_reached_from(history[round][0], NONCE_WORD);
        const unsigned in_four = bits_reached_from(history[round][4], NONCE_WORD);
        const char *verdict = ((in_zero == 0u) && (in_four == 0u)) ? "not arrived"
                              : ((in_zero == 32u) && (in_four == 32u)) ? "saturated"
                                                                      : "arriving";
        if ((first_arrival > ROUNDS) && ((in_zero != 0u) || (in_four != 0u)))
        {
            first_arrival = round;
        }
        std::printf("  %14u %18u %18u %14s\n", round, in_zero, in_four, verdict);
    }

    std::printf("\n  The nonce reaches no state bit until %u rounds have run, and saturates both\n",
                first_arrival);
    std::printf("  written words immediately on arriving. Any measurement of its effect at fewer\n");
    std::printf("  rounds than that is a measurement of absence, and no sample size fixes it.\n");
    std::printf("  This is the precondition H6, H23 and bench_closeness each needed and none had.\n");

    std::printf("\n================================================================\n");
    std::printf("  Which schedule words carry the nonce\n");
    std::printf("================================================================\n");
    std::printf("\n  H23 measured through W[17]. The expansion is\n");
    std::printf("  W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16], so W[17] reads\n");
    std::printf("  W[15], W[10], W[2] and W[1], and W[3] is in none of them.\n");
    std::printf("\n  %8s %28s\n", "schedule", "bits reachable from W[3]");
    std::printf("  %8s %28s\n", "--------", "----------------------------");
    for (unsigned word = 16u; word < 26u; word += 1u)
    {
        std::printf("  %8u %28u\n", word, bits_reached_from(schedule[word], NONCE_WORD));
    }

    std::printf("\n================================================================\n");
    std::printf("  Full diffusion: when does every output bit read every input bit\n");
    std::printf("================================================================\n");
    std::printf("\n  %6s %22s %22s\n", "round", "state[0] input bits", "all eight words");
    std::printf("  %6s %22s %22s\n", "------", "----------------------",
                "----------------------");

    unsigned saturated_at = 0u;
    for (unsigned round = 1u; round <= ROUNDS; round += 1u)
    {
        unsigned widest = 0u;
        size_t total = 0u;
        for (unsigned position = 0u; position < 32u; position += 1u)
        {
            const size_t here = history[round][0].bit[position].count();
            widest = (here > widest) ? (unsigned)here : widest;
        }
        for (unsigned word = 0u; word < 8u; word += 1u)
        {
            for (unsigned position = 0u; position < 32u; position += 1u)
            {
                total += history[round][word].bit[position].count();
            }
        }
        const int complete = (total == (size_t)8u * 32u * INPUT_BITS) ? 1 : 0;
        if ((saturated_at == 0u) && (complete != 0))
        {
            saturated_at = round;
        }
        if ((round <= 12u) || (complete != 0 && saturated_at == round))
        {
            std::printf("  %6u %22u %22.4f%%\n", round, widest,
                        100.0 * (double)total / (double)((size_t)8u * 32u * INPUT_BITS));
        }
    }
    std::printf("\n  Every one of the 256 state bits reads all %u input bits from round %u on.\n",
                INPUT_BITS, saturated_at);

    // -------------------------------------------------------------------------------------
    // The backward cone, which has never been measured.
    //
    // bench_depth found forward saturating at six rounds for both the 5-to-8 and 9-to-16 weight
    // strata while the inverted direction kept separating, nine against eight. That asymmetry was
    // recorded as unexplained. If it is topology it is decidable here instead of sampleable there:
    // the forward cone grows thirty-two bits a round after the first two and saturates at
    // twenty-one, and once a cone covers the word being read, extra input weight cannot buy
    // anything - which is exactly a floor that does not move with weight.
    //
    // The backward round is a different function from the forward one, so its cone is a different
    // graph. Running the same analysis on the inverse says whether the slower backward diffusion
    // measured statistically is a slower cone measured exactly.
    // -------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The cone in both directions, computed instead of sampled\n");
    std::printf("================================================================\n");
    std::printf("\n  A round writes state[0] and state[4] going forward and state[3] and state[7]\n");
    std::printf("  coming back, so the two directions are different functions and entitled to\n");
    std::printf("  different cones. This is reachability, so it is exact.\n");
    std::printf("\n  %8s %20s %20s %14s\n", "rounds", "forward cone", "backward cone", "ratio");
    std::printf("  %8s %20s %20s %14s\n", "--------", "--------------------",
                "--------------------", "--------------");

    {
        std::vector<WordCone> backward(8u);
        for (unsigned word = 0u; word < 8u; word += 1u)
        {
            for (unsigned position = 0u; position < 32u; position += 1u)
            {
                backward[word].bit[position].set(MESSAGE_BITS + (word * 32u) + position);
            }
        }

        for (unsigned round = 1u; round <= 24u; round += 1u)
        {
            // The inverse round, as dependency sets. Six words shift the other way; the two it
            // writes are state[3] and state[7], recovered by undoing the two additions.
            const WordCone before_a = backward[1];
            const WordCone before_b = backward[2];
            const WordCone before_c = backward[3];
            const WordCone before_e = backward[5];
            const WordCone before_f = backward[6];
            const WordCone before_g = backward[7];

            const WordCone carry_two = combine_addition(
                mix_low(before_a), combine_bitwise(before_a, combine_bitwise(before_b, before_c)));
            const WordCone carry_one = combine_addition(backward[0], carry_two);
            const WordCone before_d = combine_addition(backward[4], carry_one);
            // The schedule word the inverse consumes. Leaving it out was a defect and not a
            // shortcut: without it the backward cone cannot exceed the 256 chaining bits it was
            // seeded with, it read exactly 256 at every depth, and that looked like a dramatic
            // structural fact instead of an input nobody supplied. Failure mode one, inside the
            // bench that exists to prevent failure mode one.
            const unsigned undoing = (24u - round) & 63u;
            const WordCone before_h = combine_addition(
                carry_one,
                combine_addition(
                    combine_addition(mix_high(before_e), schedule[undoing]),
                    combine_bitwise(before_e, combine_bitwise(before_f, before_g))));

            backward[0] = before_a;
            backward[1] = before_b;
            backward[2] = before_c;
            backward[3] = before_d;
            backward[4] = before_e;
            backward[5] = before_f;
            backward[6] = before_g;
            backward[7] = before_h;

            size_t forward_widest = 0u;
            size_t backward_widest = 0u;
            for (unsigned position = 0u; position < 32u; position += 1u)
            {
                const size_t ahead = history[round][0].bit[position].count();
                forward_widest = (ahead > forward_widest) ? ahead : forward_widest;
                for (unsigned word = 0u; word < 8u; word += 1u)
                {
                    const size_t behind = backward[word].bit[position].count();
                    backward_widest = (behind > backward_widest) ? behind : backward_widest;
                }
            }

            if ((round <= 12u) || ((round % 4u) == 0u))
            {
                std::printf("  %8u %20zu %20zu %14.3f\n", round, forward_widest, backward_widest,
                            (backward_widest > 0u)
                                ? ((double)forward_widest / (double)backward_widest)
                                : 0.0);
            }
        }
    }

    std::printf("\n  A backward cone that grows more slowly is the statistical asymmetry in\n");
    std::printf("  bench_depth stated as a graph property, and it would say the saturation floor\n");
    std::printf("  is topology instead of anything about the differences fed through it. A\n");
    std::printf("  backward cone that grows at the same rate leaves that asymmetry unexplained\n");
    std::printf("  and means the cause is elsewhere.\n");

    std::printf("\n================================================================\n");
    std::printf("  The write mask: how much of the output a round did not write\n");
    std::printf("================================================================\n");
    std::printf("\n  Failure mode four. A SHA-256 round computes state[0] and state[4]; the other\n");
    std::printf("  six words are the previous state shifted along. A measurement that reads all\n");
    std::printf("  eight words after one round is reading six words that were carried through\n");
    std::printf("  unchanged, and they agree with themselves for free. H30 did exactly that and\n");
    std::printf("  reported P = 1.00000000.\n");
    std::printf("\n  Established by running the real rounds and asking which output words are\n");
    std::printf("  bit-identical to an input word on every one of many random inputs.\n");
    std::printf("\n  %14s %14s %14s %28s\n", "rounds done", "words written", "words carried",
                "fraction of a read that is free");
    std::printf("  %14s %14s %14s %28s\n", "--------------", "--------------", "--------------",
                "----------------------------");

    {
        std::mt19937 mask_generator(20260908u);
        const unsigned mask_trials = 2000u;

        for (unsigned depth = 1u; depth <= 6u; depth += 1u)
        {
            // Starts as every output word being a candidate copy of every input word, and each
            // trial removes the pairings that failed. What survives every trial is a word the
            // rounds carried instead of wrote.
            bool carried[8][8];
            for (unsigned out = 0u; out < 8u; out += 1u)
            {
                for (unsigned in = 0u; in < 8u; in += 1u)
                {
                    carried[out][in] = true;
                }
            }

            for (unsigned trial = 0u; trial < mask_trials; trial += 1u)
            {
                uint32_t message[16];
                uint32_t input[8];
                uint32_t output[8];
                for (unsigned word = 0u; word < 16u; word += 1u)
                {
                    message[word] = mask_generator();
                }
                for (unsigned word = 0u; word < 8u; word += 1u)
                {
                    input[word] = mask_generator();
                }
                compress_to(message, input, depth, output);

                for (unsigned out = 0u; out < 8u; out += 1u)
                {
                    for (unsigned in = 0u; in < 8u; in += 1u)
                    {
                        if (output[out] != input[in])
                        {
                            carried[out][in] = false;
                        }
                    }
                }
            }

            unsigned free_words = 0u;
            for (unsigned out = 0u; out < 8u; out += 1u)
            {
                for (unsigned in = 0u; in < 8u; in += 1u)
                {
                    if (carried[out][in])
                    {
                        free_words += 1u;
                        break;
                    }
                }
            }

            std::printf("  %14u %14u %14u %27.1f%%\n", depth, 8u - free_words, free_words,
                        100.0 * (double)free_words / 8.0);
        }
    }

    std::printf("\n  Read the last column as the share of an eight-word comparison that agrees\n");
    std::printf("  before the round function is consulted. At one round it is most of the read.\n");

    std::printf("\n================================================================\n");
    std::printf("  The control, run in the opposite direction\n");
    std::printf("================================================================\n");
    std::printf("\n  An analysis that claimed reachability everywhere would pass an absence test\n");
    std::printf("  trivially, so both halves are needed. Where the analysis says no path exists,\n");
    std::printf("  flipping the input bit must never change the output bit. Where it says a path\n");
    std::printf("  exists, some flips must land.\n");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4000u;
    unsigned absent_checked = 0u;
    unsigned absent_violated = 0u;
    unsigned present_checked = 0u;
    unsigned present_landed = 0u;

    for (unsigned round = 1u; round <= 6u; round += 1u)
    {
        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t message[16];
            uint32_t input[8];
            for (unsigned word = 0u; word < 16u; word += 1u)
            {
                message[word] = generator();
            }
            for (unsigned word = 0u; word < 8u; word += 1u)
            {
                input[word] = generator();
            }

            const unsigned flip_word = generator() % 16u;
            const unsigned flip_bit = generator() % 32u;
            const unsigned read_word = generator() % 8u;
            const unsigned read_bit = generator() % 32u;

            uint32_t plain[8];
            uint32_t altered[8];
            compress_to(message, input, round, plain);
            message[flip_word] ^= (1u << flip_bit);
            compress_to(message, input, round, altered);

            const uint32_t changed = plain[read_word] ^ altered[read_word];
            const int landed = (((changed >> read_bit) & 1u) != 0u) ? 1 : 0;
            const int has_path =
                history[round][read_word].bit[read_bit].test((flip_word * 32u) + flip_bit) ? 1 : 0;

            if (has_path != 0)
            {
                present_checked += 1u;
                present_landed += (unsigned)landed;
            }
            else
            {
                absent_checked += 1u;
                absent_violated += (unsigned)landed;
            }
        }
    }

    std::printf("\n  %-40s %12u\n", "pairs the analysis called unreachable", absent_checked);
    std::printf("  %-40s %12u\n", "of those, a flip that changed the bit", absent_violated);
    std::printf("  %-40s %12u\n", "pairs the analysis called reachable", present_checked);
    std::printf("  %-40s %11.4f%%\n", "of those, a flip that landed",
                (present_checked > 0u)
                    ? (100.0 * (double)present_landed / (double)present_checked)
                    : 0.0);

    std::printf("\n  A single violation in the first count would falsify the analysis outright,\n");
    std::printf("  since it claims no path exists. The second count must sit well below one\n");
    std::printf("  hundred percent and well above zero: an over-approximation admits paths that\n");
    std::printf("  carry nothing, and a value at either extreme would mean the analysis is not\n");
    std::printf("  discriminating.\n");

    std::printf("\n================================================================\n");
    std::printf("  Using it\n");
    std::printf("================================================================\n");
    std::printf("\n  Before measuring how much of input X reaches output Y, ask this first. Where\n");
    std::printf("  the answer is that no path exists, the measurement is of absence and belongs\n");
    std::printf("  in no table. Where a path exists, the measurement is of its strength and the\n");
    std::printf("  result means what it says.\n");
    return 0;
}
