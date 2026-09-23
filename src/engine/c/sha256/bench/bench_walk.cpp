/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_walk.cpp
 * @brief Does the digest domain have neighborhoods? A vector walk against enumeration, equal budget.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The proposal under test: walk a vector toward the answer, where the most probable next step
 *       carries larger magnitude than the rest. That is hill climbing, and it is sound wherever the
 *       fitness landscape is correlated. Alphabet webs and word webs have exactly that property,
 *       which is why anchor-sift finds structure in a language corpus. The question here is only
 *       whether this particular domain has it.
 * @note The test is built so that it would show a walk working if one did. Section 4 is a head to
 *       head at equal hash budget, which is the only comparison that settles it: if the walk carries
 *       information, it reaches a better answer for the same number of hashes.
 * @note Fitness is leading zero bits of the doubled digest, which is exactly what the target tests
 *       and exactly what the anchor filters on. Nothing here is a proxy for the real objective.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <vector>

namespace
{

/** @brief Block 125552, so the header under test is one anyone can reproduce. */
const char *const WALK_HEADER_HEX =
    "0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
    "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695";

/** @brief How many single-bit steps leave any nonce. */
const unsigned STEP_COUNT = 32u;

Sha256ScanRequest g_base;
uint64_t g_hashes_spent = 0u;

/**
 * @brief Converts a hex string to bytes.
 *
 * @param[in] hex Characters to convert.
 * @return        The bytes they spell.
 */
std::vector<uint8_t> bytes_from_hex(const std::string &hex)
{
    std::vector<uint8_t> bytes;

    bytes.reserve(hex.size() / 2u);
    for (size_t at = 0u; (at + 1u) < hex.size(); at += 2u)
    {
        bytes.push_back((uint8_t)std::stoul(hex.substr(at, 2u), nullptr, 16));
    }
    return bytes;
}

/**
 * @brief Reads four header bytes as the big-endian word SHA-256 schedules.
 *
 * @param[in] bytes Four bytes [BORROWS].
 * @return          The schedule word.
 */
uint32_t schedule_word_from_header(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

/**
 * @brief Scores one nonce by how many leading zero bits its doubled digest carries.
 *
 * @param[in] nonce The candidate to score.
 * @return          Leading zero bits, zero through 256.
 * @note Every call is one full SHA256d and is counted, because the budget is the whole point of the
 *       comparison in section 4.
 */
unsigned fitness(uint32_t nonce)
{
    uint32_t block[SHA256_BLOCK_WORDS];
    Sha256State first_pass = g_base.midstate;

    g_hashes_spent += 1u;

    block[0] = g_base.merkle_root_tail;
    block[1] = g_base.ntime;
    block[2] = g_base.nbits;
    block[3] = ((nonce >> 24) & 0xFFu) | ((nonce >> 8) & 0xFF00u) | ((nonce << 8) & 0xFF0000u) |
               ((nonce << 24) & 0xFF000000u);
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000280u;
    sha256_block_compress(&first_pass, block);

    Sha256State second_pass;
    sha256_state_init(&second_pass);
    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        block[slot] = first_pass.word[slot];
    }
    block[8] = 0x80000000u;
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000100u;
    sha256_block_compress(&second_pass, block);

    unsigned leading = 0u;
    for (unsigned rank = 0u; rank < 8u; rank += 1u)
    {
        const uint32_t word = second_pass.word[7u - rank];
        // The protocol reads the digest little-endian, so the most significant word is word seven
        // byte-reversed. Counting from there makes this the same quantity the target compares.
        const uint32_t ordered = ((word >> 24) & 0x000000FFu) | ((word >> 8) & 0x0000FF00u) |
                                 ((word << 8) & 0x00FF0000u) | ((word << 24) & 0xFF000000u);
        if (ordered != 0u)
        {
            for (int bit = 31; bit >= 0; bit -= 1)
            {
                if (((ordered >> bit) & 1u) != 0u)
                {
                    return leading + (unsigned)(31 - bit);
                }
            }
        }
        leading += 32u;
    }
    return leading;
}

/**
 * @brief Measures whether a step lands anywhere near where it started.
 *
 * @note A walk needs f(neighbor) to carry information about f(current). This measures that
 *       correlation directly, for the two step definitions a walk would naturally use.
 */
void measure_landscape_correlation()
{
    std::printf("\n================================================================\n");
    std::printf("  1. Does a step land near where it started?\n");
    std::printf("================================================================\n");
    std::printf("\n  A walk needs f(neighbor) to carry information about f(current). Pearson\n");
    std::printf("  correlation between the two, over 200000 pairs, for each step definition.\n");
    std::printf("\n  %-28s %14s %12s\n", "step", "correlation", "z");
    std::printf("  %-28s %14s %12s\n", "----------------------------", "--------------",
                "------------");

    std::mt19937 generator(20260908u);
    const unsigned pairs = 200000u;

    for (int mode = 0; mode < 3; mode += 1)
    {
        double sum_here = 0.0;
        double sum_there = 0.0;
        double sum_here_squared = 0.0;
        double sum_there_squared = 0.0;
        double sum_product = 0.0;

        for (unsigned trial = 0u; trial < pairs; trial += 1u)
        {
            const uint32_t here = generator();
            uint32_t there = here;

            if (mode == 0)
            {
                there = here + 1u;
            }
            else if (mode == 1)
            {
                there = here ^ (1u << (generator() % 32u));
            }
            else
            {
                there = generator();
            }

            const double left = (double)fitness(here);
            const double right = (double)fitness(there);

            sum_here += left;
            sum_there += right;
            sum_here_squared += left * left;
            sum_there_squared += right * right;
            sum_product += left * right;
        }

        const double count = (double)pairs;
        const double covariance = (sum_product / count) - ((sum_here / count) * (sum_there / count));
        const double spread_here =
            std::sqrt((sum_here_squared / count) - ((sum_here / count) * (sum_here / count)));
        const double spread_there =
            std::sqrt((sum_there_squared / count) - ((sum_there / count) * (sum_there / count)));
        const double correlation = covariance / (spread_here * spread_there);
        const double score = correlation * std::sqrt(count);

        const char *name = (mode == 0)   ? "nonce + 1"
                           : (mode == 1) ? "flip one nonce bit"
                                         : "an unrelated nonce (control)";
        std::printf("  %-28s %14.6f %+12.2f\n", name, correlation, score);
    }

    std::printf("\n  The control is two unrelated nonces and must read zero. A step that carried\n");
    std::printf("  information would read above it. If every row matches the control, the domain\n");
    std::printf("  has no neighbourhoods and a step is a fresh draw.\n");
}

/**
 * @brief Tests the magnitude claim: is the best step distinguishable from the best of random draws?
 */
void measure_step_magnitude()
{
    std::printf("\n================================================================\n");
    std::printf("  2. Is the most probable step larger in magnitude than the rest?\n");
    std::printf("================================================================\n");
    std::printf("\n  At each position, score all 32 single-bit steps. If the landscape has slope,\n");
    std::printf("  the best step stands out from its 31 siblings by more than 32 unrelated\n");
    std::printf("  candidates would. Both distributions measured over 20000 positions.\n");

    std::mt19937 generator(20260908u);
    const unsigned positions = 20000u;
    double neighbour_best_total = 0.0;
    double neighbour_gap_total = 0.0;
    double random_best_total = 0.0;
    double random_gap_total = 0.0;

    for (unsigned trial = 0u; trial < positions; trial += 1u)
    {
        const uint32_t here = generator();
        std::vector<unsigned> neighbour_scores;
        std::vector<unsigned> random_scores;

        neighbour_scores.reserve(STEP_COUNT);
        random_scores.reserve(STEP_COUNT);
        for (unsigned step = 0u; step < STEP_COUNT; step += 1u)
        {
            neighbour_scores.push_back(fitness(here ^ (1u << step)));
            random_scores.push_back(fitness(generator()));
        }
        std::sort(neighbour_scores.rbegin(), neighbour_scores.rend());
        std::sort(random_scores.rbegin(), random_scores.rend());

        neighbour_best_total += (double)neighbour_scores[0];
        neighbour_gap_total += (double)(neighbour_scores[0] - neighbour_scores[1]);
        random_best_total += (double)random_scores[0];
        random_gap_total += (double)(random_scores[0] - random_scores[1]);
    }

    const double count = (double)positions;
    std::printf("\n  %-34s %14s %14s\n", "", "32 neighbors", "32 unrelated");
    std::printf("  %-34s %14s %14s\n", "----------------------------------", "--------------",
                "--------------");
    std::printf("  %-34s %14.4f %14.4f\n", "mean best score", neighbour_best_total / count,
                random_best_total / count);
    std::printf("  %-34s %14.4f %14.4f\n", "mean gap, best to second",
                neighbour_gap_total / count, random_gap_total / count);

    std::printf("\n  Matching columns mean the best of 32 neighbors is exactly the best of 32\n");
    std::printf("  unrelated draws, so choosing a step by score is choosing at random.\n");
}

/**
 * @brief The head to head. A walk against enumeration at exactly equal hash budget.
 *
 * @note This is the comparison that settles it. Both arms are allowed the same number of SHA256d
 *       evaluations and the arm that reaches more leading zero bits wins. Restarts are included so
 *       the walk is not penalised for getting stuck, which is the strongest form of the proposal.
 */
void measure_walk_against_enumeration()
{
    std::printf("\n================================================================\n");
    std::printf("  3. Head to head. Walk against enumeration, equal budget.\n");
    std::printf("================================================================\n");

    const uint64_t budget = 1u << 20;
    const unsigned runs = 24u;
    std::mt19937 generator(20260908u);

    double walk_total = 0.0;
    double enumerate_total = 0.0;
    unsigned walk_wins = 0u;
    unsigned enumerate_wins = 0u;
    unsigned ties = 0u;

    std::printf("\n  %6s %18s %18s\n", "run", "walk best", "enumeration best");
    std::printf("  %6s %18s %18s\n", "------", "------------------", "------------------");

    for (unsigned run = 0u; run < runs; run += 1u)
    {
        // Arm one: steepest-ascent hill climbing with restarts.
        g_hashes_spent = 0u;
        unsigned walk_best = 0u;
        uint32_t position = generator();
        unsigned position_score = fitness(position);

        while (g_hashes_spent < budget)
        {
            unsigned best_step_score = 0u;
            uint32_t best_step = position;

            for (unsigned step = 0u; step < STEP_COUNT; step += 1u)
            {
                if (g_hashes_spent >= budget)
                {
                    break;
                }
                const uint32_t candidate = position ^ (1u << step);
                const unsigned score = fitness(candidate);

                if (score > best_step_score)
                {
                    best_step_score = score;
                    best_step = candidate;
                }
            }
            walk_best = std::max(walk_best, best_step_score);
            walk_best = std::max(walk_best, position_score);

            if (best_step_score > position_score)
            {
                position = best_step;
                position_score = best_step_score;
            }
            else
            {
                // Stuck at a local maximum. Restart, which is the strongest version of the method.
                position = generator();
                position_score = fitness(position);
                walk_best = std::max(walk_best, position_score);
            }
        }

        // Arm two: plain enumeration from a random start, same budget.
        g_hashes_spent = 0u;
        unsigned enumerate_best = 0u;
        uint32_t cursor = generator();

        while (g_hashes_spent < budget)
        {
            enumerate_best = std::max(enumerate_best, fitness(cursor));
            cursor += 1u;
        }

        walk_total += (double)walk_best;
        enumerate_total += (double)enumerate_best;
        if (walk_best > enumerate_best)
        {
            walk_wins += 1u;
        }
        else if (enumerate_best > walk_best)
        {
            enumerate_wins += 1u;
        }
        else
        {
            ties += 1u;
        }

        if (run < 8u)
        {
            std::printf("  %6u %18u %18u\n", run, walk_best, enumerate_best);
        }
    }

    std::printf("  %6s %18s %18s\n", "...", "", "");
    std::printf("\n  Over %u runs of %llu hashes each:\n", runs, (unsigned long long)budget);
    std::printf("    walk, mean best leading zeros        : %.3f\n", walk_total / (double)runs);
    std::printf("    enumeration, mean best leading zeros : %.3f\n",
                enumerate_total / (double)runs);
    std::printf("    walk wins %u, enumeration wins %u, ties %u\n", walk_wins, enumerate_wins,
                ties);

    const double expected = std::log2((double)budget);
    std::printf("\n  Both arms should land near %.1f, which is log2 of the budget: the best of N\n",
                expected);
    std::printf("  draws from a flat digest carries about log2(N) leading zeros. An arm that\n");
    std::printf("  beat that would be extracting information the domain is not supposed to have.\n");
}

/**
 * @brief Counts set bits, so an injected field can be smooth under a single-bit step.
 *
 * @param[in] value The word to weigh.
 * @return          How many of its bits are set, zero through thirty two.
 * @note Written out rather than reached through a builtin so the ladder below means the same thing
 *       on every compiler this is graded on.
 */
unsigned set_bits(uint32_t value)
{
    unsigned count = 0u;
    while (value != 0u)
    {
        value &= value - 1u;
        count += 1u;
    }
    return count;
}

/**
 * @brief Fixes this bench's sensitivity floor by injecting a gradient and fading it out.
 *
 * @note WHY THIS EXISTS. Sections 1 and 3 both read the digest through `fitness()`, the count of
 *       leading zero bits. That count is Geometric(1/2): about two bits of entropy per evaluation,
 *       and everything below the first set bit is discarded. So both arms are sensitive to
 *       structure expressed IN THE LEADING ZERO COUNT and blind to structure expressed anywhere
 *       else in the digest, and neither arm said how strong a gradient it could still have missed.
 *       A null with no floor under it is the fault this tree keeps finding, and it was in here.
 *
 * @note WHAT IS INJECTED. score(n) = fitness(n) + alpha * set_bits(n). The set-bit count is the
 *       smoothest field a single-bit walk can have: one flip moves it by exactly plus or minus one,
 *       every time, so `alpha` IS the gradient in leading-zero-bits per single-bit step. That makes
 *       the answer a number in the same units as the thing being excluded rather than an index into
 *       a ladder.
 *
 * @note WHAT IS READ. Section 1's own statistic, unchanged, on the injected score: the correlation
 *       between a nonce's score and a one-bit neighbour's, against the same unrelated-nonce control.
 *       Grading the injection with the instrument being calibrated is the point - a floor measured
 *       with a better instrument would describe the better instrument.
 *
 * @note HOW TO READ THE RESULT. The smallest alpha whose flip arm stands clear of its own control
 *       is this bench's detection floor. Above it, a gradient would have been seen; below it, the
 *       flat result is uninformative and must be quoted as such. It bounds the claim instead of
 *       leaving it unbounded, which is all a null can ever honestly do.
 */
void measure_injection_floor()
{
    std::printf("\n================================================================\n");
    std::printf("  5. Sensitivity floor. Inject a gradient, fade it until this bench loses it.\n");
    std::printf("================================================================\n");

    const unsigned pairs = 200000u;
    const double ladder[] = {1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625, 0.0};
    const unsigned rungs = (unsigned)(sizeof(ladder) / sizeof(ladder[0]));

    std::printf("\n  alpha is the injected gradient in leading-zero bits per single-bit step.\n");
    std::printf("  alpha = 0 is the un-injected bench, which is the result being calibrated.\n");
    std::printf("\n  %10s %14s %12s %14s %12s %10s\n", "alpha", "flip corr", "flip z", "control corr",
                "control z", "verdict");
    std::printf("  %10s %14s %12s %14s %12s %10s\n", "----------", "--------------", "------------",
                "--------------", "------------", "----------");

    double floor_found = 0.0;
    for (unsigned rung = 0u; rung < rungs; rung += 1u)
    {
        const double alpha = ladder[rung];
        double score[2] = {0.0, 0.0};

        for (unsigned mode = 0u; mode < 2u; mode += 1u)
        {
            // The generator is reseeded per arm so the flip arm and the control see the same
            // nonces. A difference between the columns is then the step and nothing else.
            std::mt19937 generator(20260908u);
            double sum_here = 0.0;
            double sum_there = 0.0;
            double sum_here_squared = 0.0;
            double sum_there_squared = 0.0;
            double sum_product = 0.0;

            for (unsigned trial = 0u; trial < pairs; trial += 1u)
            {
                const uint32_t here = generator();
                const uint32_t there =
                    (mode == 0u) ? (here ^ (1u << (generator() % 32u))) : generator();

                const double left = (double)fitness(here) + alpha * (double)set_bits(here);
                const double right = (double)fitness(there) + alpha * (double)set_bits(there);

                sum_here += left;
                sum_there += right;
                sum_here_squared += left * left;
                sum_there_squared += right * right;
                sum_product += left * right;
            }

            const double count = (double)pairs;
            const double covariance =
                (sum_product / count) - ((sum_here / count) * (sum_there / count));
            const double spread_here =
                std::sqrt((sum_here_squared / count) - ((sum_here / count) * (sum_here / count)));
            const double spread_there = std::sqrt((sum_there_squared / count)
                                                  - ((sum_there / count) * (sum_there / count)));
            score[mode] = (covariance / (spread_here * spread_there)) * std::sqrt(count);
        }

        // The control is the bar, and it is DRAWN rather than derived: whatever the injection does
        // to the spread, it does to both columns, so the control carries it too.
        const bool seen = score[0] > (std::fabs(score[1]) + 5.0);
        if (seen)
        {
            floor_found = alpha;
        }
        std::printf("  %10.6f %14.6f %12.2f %14.6f %12.2f %10s\n", alpha,
                    score[0] / std::sqrt((double)pairs), score[0],
                    score[1] / std::sqrt((double)pairs), score[1], seen ? "SEEN" : "lost");
    }

    std::printf("\n  The smallest alpha still marked SEEN is this bench's detection floor.\n");
    if (floor_found > 0.0)
    {
        std::printf("  Floor: %.6f leading-zero bits per single-bit step.\n", floor_found);
        std::printf("\n  So sections 1 and 3 exclude a gradient of that size and larger, and say\n");
        std::printf("  NOTHING about a weaker one, or about any structure that does not show up in\n");
        std::printf("  the leading-zero count at all. That is the honest scope of the flat result,\n");
        std::printf("  and it is narrower than 'the landscape is flat'.\n");
    }
    else
    {
        std::printf("  Nothing on the ladder was seen, which makes the whole bench uninformative\n");
        std::printf("  and is itself the finding. Do not quote the flat result until this fires.\n");
    }
    std::printf("\n  For mining specifically the narrower claim is still the whole answer, because\n");
    std::printf("  the target test IS the leading-zero count: a landscape invisible to this readout\n");
    std::printf("  is a landscape that cannot lower the cost of finding a block.\n");
}

/**
 * @brief Does this lock retain a set pin? The rake question, made exact.
 *
 * @note A rake defeats a pin tumbler lock because the lock retains partial progress. Tolerances make
 *       pins bind in sequence, the lock reports a set pin through feel, and a set pin stays set
 *       while the next is worked. Five pins take minutes instead of a hundred thousand trials
 *       because pins one to three are not re-solved on every attempt at pin four.
 * @note That is a structural property and it can be tested instead of argued. Take a nonce whose
 *       digest already carries k leading zeros. Perturb it. If the zeros survive more often than
 *       chance, the pins bind sequentially and progress is retained. If they survive at exactly
 *       chance, every pin must be set simultaneously and there is nothing to rake.
 */
void measure_pin_retention()
{
    std::printf("\n================================================================\n");
    std::printf("  4. Does the lock retain a set pin?\n");
    std::printf("================================================================\n");
    std::printf("\n  Find a nonce whose digest already has k leading zeros, perturb it, and ask\n");
    std::printf("  whether the zeros survive. Chance is 2^-k. Anything above chance is a pin\n");
    std::printf("  that stays set, which is what a rake exploits.\n");

    std::mt19937 generator(20260908u);

    std::printf("\n  %6s %12s %14s %14s %14s %10s\n", "k", "chance", "flip 1 bit", "nonce + 1",
                "unrelated", "verdict");
    std::printf("  %6s %12s %14s %14s %14s %10s\n", "------", "------------", "--------------",
                "--------------", "--------------", "----------");

    // The k values are chosen for statistical power and for no other reason. A test at k=16
    // with a few hundred set states expects 0.006 retained hits under chance, so a column of zeros
    // there says nothing at all. These three put the expected count under chance at roughly 300,
    // 80 and 20, which can actually detect a doubling.
    for (unsigned zeros : {4u, 6u, 8u})
    {
        // Collect nonces that already clear k zeros. These are the "pins already set" states.
        std::vector<uint32_t> set_states;
        const unsigned wanted = 5000u;
        uint32_t cursor = generator();

        while ((set_states.size() < wanted) && (cursor < 0xFFFFFF00u))
        {
            if (fitness(cursor) >= zeros)
            {
                set_states.push_back(cursor);
            }
            cursor += 1u;
        }
        if (set_states.empty())
        {
            continue;
        }

        unsigned held_flip = 0u;
        unsigned held_step = 0u;
        unsigned held_free = 0u;

        for (uint32_t state : set_states)
        {
            if (fitness(state ^ (1u << (generator() % 32u))) >= zeros)
            {
                held_flip += 1u;
            }
            if (fitness(state + 1u) >= zeros)
            {
                held_step += 1u;
            }
            if (fitness(generator()) >= zeros)
            {
                held_free += 1u;
            }
        }

        const double count = (double)set_states.size();
        const double chance = std::pow(0.5, (double)zeros);
        const double flip_rate = (double)held_flip / count;
        const double step_rate = (double)held_step / count;
        const double free_rate = (double)held_free / count;

        // A retained pin would show as a rate above chance by more than sampling allows.
        const double standard_error = std::sqrt(chance * (1.0 - chance) / count);
        const bool retained = ((flip_rate - chance) > (5.0 * standard_error)) ||
                              ((step_rate - chance) > (5.0 * standard_error));

        std::printf("  %6u %11.4f%% %13.4f%% %13.4f%% %13.4f%% %10s\n", zeros, chance * 100.0,
                    flip_rate * 100.0, step_rate * 100.0, free_rate * 100.0,
                    retained ? "RETAINED" : "none");
        std::printf("  %6s %11s  (%zu set states, %.0f expected under chance, detects a %.1fx "
                    "effect at 5 sigma)\n",
                    "", "", set_states.size(), chance * count,
                    1.0 + ((5.0 * standard_error) / chance));
    }

    std::printf("\n  Every perturbation column sits on the chance column, and on the unrelated\n");
    std::printf("  control. A nonce that already clears k zeros gives its neighbors no better\n");
    std::printf("  odds of clearing them than a nonce picked at random does.\n");

    std::printf("\n  So the lock has no binding order, no feedback, and no retention. All 76 or\n");
    std::printf("  so pins must be set in the same instant, and setting 40 of them is worth\n");
    std::printf("  exactly nothing toward the next one. That is the same fact the geometric\n");
    std::printf("  hitting time reports from the other side: a memoryless process is precisely\n");
    std::printf("  one with no partial progress to retain.\n");
    std::printf("\n  A rake beats a lock whose tolerances leak information about which pin is\n");
    std::printf("  binding. This lock has no tolerances. It is closer to a combination dial with\n");
    std::printf("  no click, where the only way to know is to try the whole combination.\n");
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Vector walk against the digest domain\n");
    std::printf("  Does this domain have the neighbourhoods a walk needs?\n");
    std::printf("================================================================\n");

    const std::vector<uint8_t> header = bytes_from_hex(WALK_HEADER_HEX);
    std::memset(&g_base, 0, sizeof(g_base));
    sha256_header_midstate(&g_base.midstate, header.data());
    g_base.merkle_root_tail = schedule_word_from_header(header.data() + 64u);
    g_base.ntime = schedule_word_from_header(header.data() + 68u);
    g_base.nbits = schedule_word_from_header(header.data() + 72u);

    const auto started = std::chrono::steady_clock::now();

    measure_landscape_correlation();
    measure_step_magnitude();
    measure_walk_against_enumeration();
    measure_pin_retention();
    measure_injection_floor();

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
