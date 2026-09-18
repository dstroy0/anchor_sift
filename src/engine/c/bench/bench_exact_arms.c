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
 * @note The run is planted. Positions step by a known amount and values cycle on a known period. An arm that agrees with
 *       portable while both are wrong is still caught.
 * @note Every arm is asked a second time over the same run with a repeated position at every eighth
 *       entry. The portable count on repeated positions is checked against python by
 *       maint/engine/check_exact_limbs.py, and this grades every other arm against portable there.
 * @note The run is allocated at the size asked for. A static array of RUN_PLACES integers is 33 MiB
 *       at 128 limbs and 8.6 GB at 32768, and a build at the widest width could not load it.
 */

#include "arm.h"
#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA
#include "arm_cuda.h"
#endif

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
 *       computes anything. It loses at every size below where that copy is amortized. Reporting
 *       one size would hide which of those two shapes an arm has.
 */
#define RUN_PLACES 65536u

/** @brief Positions used where the caller names none. */
#define RUN_DEFAULT 4096u

/** @brief How many distinct values cycle through the run. */
#define RUN_CYCLE 4u

/**
 * @brief Decimal places the width holds for the largest value the run reaches.
 *
 * @note Positions run to RUN_PLACES / 4 and the lags to 6.25, below 2^15. A value at p places
 *       needs 15 bits plus p * log2(10). log10(2) is carried as 30102 parts in 100000, rounded down,
 *       and this never names more places than the width holds.
 */
#define PLACES_HELD ((((unsigned long long)ANCHOR_EXACT_BITS - 15ull) * 30102ull) / 100000ull)

/**
 * @brief Decimal places every value is carried at: 24, or what a narrower width holds.
 *
 * @note The narrowing to uint32_t is taken only where PLACES_HELD is below 24.
 */
#define PLACES ((PLACES_HELD < 24ull) ? (uint32_t)PLACES_HELD : 24u)

/* The run steps by a quarter, which takes two places. The narrowest width, 32 bits, holds five.
 * Written in the three forms exact_integer.h uses: static_assert for C++, _Static_assert for C11,
 * and a negative array size before C11. nvcc also compiles this file, and its MSVC host compiler
 * may take it in a C mode that has no _Static_assert. */
#if defined(__cplusplus)
static_assert(PLACES_HELD >= 2ull, "the narrowest width must hold the two places a quarter step takes");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert(PLACES_HELD >= 2ull, "the narrowest width must hold the two places a quarter step takes");
#else
typedef char bench_exact_arms_places_hold_a_quarter[(PLACES_HELD >= 2ull) ? 1 : -1];
#endif

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
 * @note Positions step by a quarter and values cycle every four places. The value repeats every
 *       whole unit while the positions repeat four times as often. An arm that ignores the value
 *       reads the wrong period and is caught by the count.
 */
static int plant(AnchorExactInteger *positions, uint64_t *values, unsigned int places)
{
    for (unsigned int at = 0u; at < places; at++)
    {
        char text[64];
        (void)snprintf(text, sizeof(text), "%u.%02u", at / 4u, (at % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &positions[at]) != ANCHOR_EXACT_OK)
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

/**
 * @brief Asks every arm the same lags as portable and prints one verdict row per arm.
 *
 * @param[in]  arms             The arms beyond portable [BORROWS].
 * @param[in]  count            How many arms.
 * @param[in]  positions        Positions, ascending [BORROWS].
 * @param[in]  values           The value standing at each position [BORROWS].
 * @param[in]  lags             The lags to ask [BORROWS].
 * @param[in]  reference        What portable answered at each lag [BORROWS].
 * @param[out] held             Scratch for each arm's answers [BORROWS].
 * @param[in]  places           How many positions.
 * @param[in]  portable_seconds Seconds the portable sweep took, for the ratio.
 * @param[in]  portable_name    Name to print in the against column [BORROWS].
 * @return                      1 where any arm disagreed with portable at any lag, 0 otherwise.
 */
static int grade_arms(const AnchorExactArm *const *arms, unsigned int count,
                      const AnchorExactInteger *positions, const uint64_t *values,
                      const AnchorExactInteger *lags, const size_t *reference, size_t *held,
                      unsigned int places, double portable_seconds, const char *portable_name)
{
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
        printf("  %-14s %-10.3f %-12s %s\n", arm->name, seconds, portable_name, verdict);
    }
    return wrong;
}

int main(int argc, char **argv)
{
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

    AnchorExactInteger *const positions =
        (AnchorExactInteger *)malloc((size_t)places * sizeof(AnchorExactInteger));
    if (positions == NULL)
    {
        printf("  %u positions of %u limbs could not be allocated\n", places,
               (unsigned int)ANCHOR_EXACT_LIMBS);
        return 1;
    }

    if (plant(positions, values, places) == 0)
    {
        printf("  the run would not fit the scale\n");
        free(positions);
        return 1;
    }
    for (unsigned int at = 0u; at < LAGS; at++)
    {
        char text[64];
        (void)snprintf(text, sizeof(text), "%u.%02u", (at + 1u) / 4u, ((at + 1u) % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &lags[at]) != ANCHOR_EXACT_OK)
        {
            printf("  lag %u would not fit the scale\n", at);
            free(positions);
            return 1;
        }
    }

    printf("\n  %u positions, %u lags, %u limbs of 32 bits, %u decimal places\n\n", places,
           LAGS, (unsigned int)ANCHOR_EXACT_LIMBS, (unsigned int)PLACES);

    const AnchorExactArm *portable = anchor_exact_portable_arm();
    const double portable_seconds = sweep(portable, positions, values, lags, reference, places);
    printf("  %-14s %-10s %-12s %s\n", "arm", "seconds", "against", "verdict");
    printf("  %-14s %-10.3f %-12s %s\n", portable->name, portable_seconds, "itself",
           "the reference");

    const AnchorExactArm *arms[6];
    unsigned int count = 0u;
#if defined(ANCHOR_EXACT_HAVE_AVX2) && ANCHOR_EXACT_HAVE_AVX2
    arms[count] = anchor_exact_avx2_arm();
    if (arms[count] != NULL)
    {
        count++;
    }
#endif
#if defined(ANCHOR_EXACT_HAVE_AVX512) && ANCHOR_EXACT_HAVE_AVX512
    arms[count] = anchor_exact_avx512_arm();
    if (arms[count] != NULL)
    {
        count++;
    }
#endif
#if defined(ANCHOR_EXACT_HAVE_SVE) && ANCHOR_EXACT_HAVE_SVE
    arms[count] = anchor_exact_sve_arm();
    if (arms[count] != NULL)
    {
        count++;
    }
#endif
#if defined(ANCHOR_EXACT_HAVE_NEON) && ANCHOR_EXACT_HAVE_NEON
    arms[count] = anchor_exact_neon_arm();
    if (arms[count] != NULL)
    {
        count++;
    }
#endif
#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA
    arms[count] = anchor_exact_cuda_arm();
    if (arms[count] != NULL)
    {
        count++;
    }
#endif

    int wrong = grade_arms(arms, count, positions, values, lags, reference, held, places,
                           portable_seconds, portable->name);

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

    // Every eighth entry takes the position before it. That position is listed twice with two
    // values from the cycle. The run stays ascending, which the CUDA arm's binary search needs.
    for (unsigned int at = 7u; at < places; at += 8u)
    {
        positions[at] = positions[at - 1u];
    }
    printf("\n  the same run with the position before every eighth entry repeated\n\n");
    const double repeated_seconds = sweep(portable, positions, values, lags, reference, places);
    printf("  %-14s %-10.3f %-12s %s\n", portable->name, repeated_seconds, "itself",
           "the reference");
    if (grade_arms(arms, count, positions, values, lags, reference, held, places, repeated_seconds,
                   portable->name) != 0)
    {
        wrong = 1;
    }

#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA
    // The cuda arm answers from the portable one where the device refuses the work. Its row above
    // agrees whether or not the device ran. Asked once more here without that fallback, a refusal
    // is visible and counts as a failure. An agreement the device never computed grades nothing
    // about the device.
    if (anchor_exact_cuda_available() != 0)
    {
        const size_t device_answer =
            anchor_exact_agreement_cuda(positions, values, (size_t)places, &lags[3]);
        if (device_answer == (size_t)-1)
        {
            printf("\n  the device refused the run at %u limbs. The cuda row is the portable arm\n",
                   (unsigned int)ANCHOR_EXACT_LIMBS);
            wrong = 1;
        }
        else
        {
            printf("\n  the device itself answered lag 4: %llu, portable says %llu: %s\n",
                   (unsigned long long)device_answer, (unsigned long long)reference[3],
                   (device_answer == reference[3]) ? "agree" : "DISAGREE");
            if (device_answer != reference[3])
            {
                wrong = 1;
            }
        }
    }
#endif

    printf("\n");
    free(positions);
    return wrong;
}
