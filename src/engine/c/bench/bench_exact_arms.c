/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_exact_arms.c
 * @brief Grades every arm present against the portable one, then times them on the same data.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Two columns and they are graded to different standards. A disagreement is a defect. A time
 *       is a cost. An arm that is faster and disagrees is still a defect.
 * @note The portable arm is the reference and is never skipped. Every other arm is asked the same
 *       questions on the same data in the same order, and the answers are compared item by item
 *       one at a time and never in aggregate, because two different sets of mistakes can sum to
 *       one total.
 * @note The run is planted. Positions step by a known amount and values cycle on a known period, so
 *       what the agreement should be is arithmetic and not a measurement. An arm that agrees with
 *       portable while both are wrong is still caught.
 */

#include "exact_arm.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

/**
 * @brief The most positions the planted run can hold.
 *
 * @note The run actually used is chosen at run time and defaults to a quarter of this. Size is the
 *       axis that decides whether an arm is worth its overhead: a vectorized arm has no startup
 *       cost and is faster immediately, and the CUDA arm copies the whole run across a bus before it
 *       computes anything, so it loses at every size below where that copy is amortized. Reporting
 *       one size would hide which of those two shapes an arm has.
 */
#define RUN_PLACES 65536u

/** @brief Positions used where the caller names none. */
#define RUN_DEFAULT 4096u

/** @brief How many distinct values cycle through the run. */
#define RUN_CYCLE 4u

/** @brief Decimal places every value is carried at. */
#define PLACES 24u

/** @brief Lags asked of every arm. */
#define LAGS 24u

/** @brief Repeats of the timed loop, enough that a coarse clock still resolves it. */
#define REPEATS 3u

/**
 * @brief Builds the planted run.
 *
 * @param[out] positions Where the positions are written [BORROWS].
 * @param[out] values    Where the value at each position is written [BORROWS].
 * @return               1 where the run was built, 0 where a value would not fit the scale.
 * @note Positions step by a quarter and values cycle every four places, so the value repeats every
 *       whole unit while the positions repeat four times as often. An arm that ignores the value
 *       reads the wrong period and is caught by the count.
 */
static int plant(AnchorExactInteger *positions, uint64_t *values, unsigned int places)
{
    for (unsigned int at = 0u; at < places; at++)
    {
        char text[64];
        (void)snprintf(text, sizeof(text), "%u.%02u", at / 4u, (at % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &positions[at])
            != ANCHOR_EXACT_OK)
        {
            return 0;
        }
        values[at] = (uint64_t)(at % RUN_CYCLE);
    }
    return 1;
}

/**
 * @brief Asks one arm every lag and records what it answered.
 *
 * @param[in]  arm       The arm to ask [BORROWS].
 * @param[in]  positions Positions, ascending [BORROWS].
 * @param[in]  values    The value standing at each position [BORROWS].
 * @param[in]  lags      The lags to ask [BORROWS].
 * @param[out] answers   Where each answer is written [BORROWS].
 * @return               Seconds the whole sweep took.
 */
static double sweep(const AnchorExactArm *arm, const AnchorExactInteger *positions,
                    const uint64_t *values, const AnchorExactInteger *lags, size_t *answers,
                    unsigned int places)
{
    const clock_t started = clock();
    for (unsigned int again = 0u; again < REPEATS; again++)
    {
        for (unsigned int at = 0u; at < LAGS; at++)
        {
            answers[at] = arm->agreement(positions, values, (size_t)places, &lags[at]);
        }
    }
    return (double)(clock() - started) / (double)CLOCKS_PER_SEC;
}

int main(int argc, char **argv)
{
    static AnchorExactInteger positions[RUN_PLACES];
    static uint64_t values[RUN_PLACES];
    static AnchorExactInteger lags[LAGS];
    static size_t reference[LAGS];
    static size_t held[LAGS];

    unsigned int places = RUN_DEFAULT;
    if (argc > 1)
    {
        const long asked = strtol(argv[1], NULL, 10);
        if ((asked < 16) || (asked > (long)RUN_PLACES))
        {
            printf("  positions must be between 16 and %u\n", RUN_PLACES);
            return 1;
        }
        places = (unsigned int)asked;
    }

    if (plant(positions, values, places) == 0)
    {
        printf("  the run would not fit the scale\n");
        return 1;
    }
    for (unsigned int at = 0u; at < LAGS; at++)
    {
        char text[64];
        (void)snprintf(text, sizeof(text), "%u.%02u", (at + 1u) / 4u, ((at + 1u) % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &lags[at]) != ANCHOR_EXACT_OK)
        {
            printf("  lag %u would not fit the scale\n", at);
            return 1;
        }
    }

    printf("\n  %u positions, %u lags, %u limbs of 32 bits, %u decimal places\n\n", places,
           LAGS, (unsigned int)ANCHOR_EXACT_LIMBS, PLACES);

    const AnchorExactArm *portable = anchor_exact_portable_arm();
    const double portable_seconds = sweep(portable, positions, values, lags, reference, places);
    printf("  %-14s %-10s %-12s %s\n", "arm", "seconds", "against", "verdict");
    printf("  %-14s %-10.3f %-12s %s\n", portable->name, portable_seconds, "itself",
           "the reference");

    const AnchorExactArm *arms[6];
    unsigned int count = 0u;
#if defined(ANCHOR_EXACT_HAVE_AVX2) && ANCHOR_EXACT_HAVE_AVX2
    arms[count] = anchor_exact_avx2_arm();
    if (arms[count] != NULL) { count++; }
#endif
#if defined(ANCHOR_EXACT_HAVE_AVX512) && ANCHOR_EXACT_HAVE_AVX512
    arms[count] = anchor_exact_avx512_arm();
    if (arms[count] != NULL) { count++; }
#endif
#if defined(ANCHOR_EXACT_HAVE_SVE) && ANCHOR_EXACT_HAVE_SVE
    arms[count] = anchor_exact_sve_arm();
    if (arms[count] != NULL) { count++; }
#endif
#if defined(ANCHOR_EXACT_HAVE_NEON) && ANCHOR_EXACT_HAVE_NEON
    arms[count] = anchor_exact_neon_arm();
    if (arms[count] != NULL) { count++; }
#endif
#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA
    arms[count] = anchor_exact_cuda_arm();
    if (arms[count] != NULL) { count++; }
#endif

    int wrong = 0;
    for (unsigned int which = 0u; which < count; which++)
    {
        const AnchorExactArm *arm = arms[which];
        const double seconds = sweep(arm, positions, values, lags, held, places);

        unsigned int differs = 0u;
        for (unsigned int at = 0u; at < LAGS; at++)
        {
            if (held[at] != reference[at])
            {
                differs++;
            }
        }
        if (differs != 0u)
        {
            wrong = 1;
        }

        char verdict[96];
        if (differs != 0u)
        {
            (void)snprintf(verdict, sizeof(verdict), "DISAGREES on %u of %u lags", differs, LAGS);
        }
        else if (seconds > 0.0)
        {
            (void)snprintf(verdict, sizeof(verdict), "agrees, %.2fx", portable_seconds / seconds);
        }
        else
        {
            (void)snprintf(verdict, sizeof(verdict), "agrees, too fast to time");
        }
        printf("  %-14s %-10.3f %-12s %s\n", arm->name, seconds, portable->name, verdict);
    }

    if (count == 0u)
    {
        printf("\n  no arm beyond portable was built into this binary or answered on this machine\n");
    }

    // The planted period is one whole unit, which is lag 4 of the twenty four asked. Checking the
    // reference against arithmetic keeps every arm from agreeing on one wrong number together.
    const size_t expected_at_period = (size_t)(places - 4u);
    // Cast to the widest unsigned instead of using %zu. The MinGW runtime's printf does not carry
    // the z length modifier, and a format it cannot read prints the wrong thing silently.
    printf("\n  planted period is lag 4. portable read %llu, arithmetic says %llu: %s\n",
           (unsigned long long)reference[3], (unsigned long long)expected_at_period,
           (reference[3] == expected_at_period) ? "agree" : "DISAGREE");
    if (reference[3] != expected_at_period)
    {
        wrong = 1;
    }

    printf("\n");
    return wrong;
}
