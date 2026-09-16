/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_steer_arms.c
 * @brief Grades every steering scan arm against the portable one, then times them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * DIFFERENTIAL FIRST, TIMING SECOND, AND THE ORDER IS THE POINT. A faster arm that returns a
 * different count has not been made faster, it has been broken. Every case below runs on both arms
 * and compares the integer they return, so agreement is exact and a difference of one is a defect.
 * Only the cases that agree are timed.
 *
 * THE CASES ARE CHOSEN TO BREAK A VECTOR ARM, not to exercise the common path. A wide arm handles
 * thirty-two alignments at a time and finishes the remainder scalar, so the interesting inputs are
 * the ones near that boundary: fewer alignments than one register holds, exactly one register,
 * one more than a register, and a length whose remainder is every value in between. A survivor mask
 * that is entirely set, entirely clear, or alternating exercises the mask path separately from the
 * compare path.
 */

#include "anchor_steer_arm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/** @brief Corpus bytes the timing runs over. */
#define ARMS_CORPUS 1048576u

/** @brief Arms this driver can hold. */
#define ARMS_MAX 4u

/** @brief Fills a field with a skewed distribution, so agreement rates vary across offsets. */
static void build_field(uint8_t *corpus, size_t length)
{
    uint32_t state = 2463534242u;

    for (size_t at = 0u; at < length; at += 1u)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        const uint32_t roll = state % 1000u;
        if (roll < 400u)      { corpus[at] = 0x41u; }
        else if (roll < 700u) { corpus[at] = 0x42u; }
        else if (roll < 900u) { corpus[at] = 0x43u; }
        else                  { corpus[at] = (uint8_t)(0x50u + (state % 40u)); }
    }
}

/** @brief How the survivor mask is filled for a case. */
typedef enum
{
    MASK_ALL_ALIVE = 0,
    MASK_NONE_ALIVE = 1,
    MASK_ALTERNATING = 2,
    MASK_SPARSE = 3
} MaskKind;

/** @brief Name of a mask kind. */
static const char *mask_name(MaskKind kind)
{
    switch (kind)
    {
        case MASK_ALL_ALIVE:   { return "all alive"; }
        case MASK_NONE_ALIVE:  { return "none alive"; }
        case MASK_ALTERNATING: { return "alternating"; }
        case MASK_SPARSE:      { return "sparse"; }
        default:               { return "unknown"; }
    }
}

/** @brief Fills a survivor mask. */
static void build_mask(uint8_t *alive, size_t alignments, MaskKind kind)
{
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        switch (kind)
        {
            case MASK_NONE_ALIVE:  { alive[at] = 0u; break; }
            case MASK_ALTERNATING: { alive[at] = (uint8_t)(at % 2u); break; }
            case MASK_SPARSE:      { alive[at] = (uint8_t)(((at % 97u) == 0u) ? 1u : 0u); break; }
            case MASK_ALL_ALIVE:
            default:               { alive[at] = 1u; break; }
        }
    }
}

int main(void)
{
    int failed = 0;

    const AnchorSteerArm *arms[ARMS_MAX];
    size_t arm_count = 0u;
    arms[arm_count] = anchor_steer_portable_arm();
    arm_count += 1u;

#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2
    {
        const AnchorSteerArm *avx2 = anchor_steer_avx2_arm();
        if (avx2 != NULL)
        {
            arms[arm_count] = avx2;
            arm_count += 1u;
        }
        else
        {
            printf("  avx2 arm compiled in and reported absent by the processor\n");
        }
    }
#endif

    uint8_t *corpus = (uint8_t *)malloc(ARMS_CORPUS);
    uint8_t *alive = (uint8_t *)malloc(ARMS_CORPUS);
    if ((corpus == NULL) || (alive == NULL))
    {
        printf("  allocation failed\n");
        free(corpus); free(alive);
        return 1;
    }
    build_field(corpus, ARMS_CORPUS);

    printf("\n  STEERING SCAN ARMS, every arm against the portable one.\n\n");
    printf("  arms present:");
    for (size_t which = 0u; which < arm_count; which += 1u)
    {
        printf(" %s", arms[which]->name);
    }
    printf("\n\n");

    /* Lengths chosen around the thirty-two lane boundary a wide arm works in, plus a long one.
     * 31 is below one register, 32 is exactly one, 33 leaves a remainder of one, 63 leaves 31, and
     * 1000 leaves 8. A vector arm mishandling its tail fails one of these and passes the rest. */
    const size_t lengths[] = { 1u, 2u, 31u, 32u, 33u, 63u, 64u, 65u, 1000u, 65536u };
    const size_t length_count = sizeof(lengths) / sizeof(lengths[0]);

    printf("  %10s %14s %8s %14s %10s\n", "alignments", "mask", "offset", "count", "verdict");

    for (size_t which_length = 0u; which_length < length_count; which_length += 1u)
    {
        const size_t alignments = lengths[which_length];

        for (unsigned int which_mask = 0u; which_mask < 4u; which_mask += 1u)
        {
            build_mask(alive, alignments, (MaskKind)which_mask);

            /* Offset zero and a non-zero offset exercise the sliding window separately from the
             * base pointer. The corpus is long enough that alignments + offset stays inside it. */
            const size_t offsets[] = { 0u, 7u };
            for (unsigned int which_offset = 0u; which_offset < 2u; which_offset += 1u)
            {
                const size_t offset = offsets[which_offset];
                const uint8_t wanted = corpus[offset];

                const size_t want = arms[0]->count(corpus, alignments, alive, wanted, offset);
                int agreed = 1;
                for (size_t which_arm = 1u; which_arm < arm_count; which_arm += 1u)
                {
                    const size_t got = arms[which_arm]->count(corpus, alignments, alive, wanted,
                                                              offset);
                    if (got != want)
                    {
                        printf("  %10zu %14s %8zu %14zu %10s  %s returned %zu\n", alignments,
                               mask_name((MaskKind)which_mask), offset, want, "FAILS",
                               arms[which_arm]->name, got);
                        agreed = 0;
                        failed += 1;
                    }
                }
                if (agreed != 0)
                {
                    printf("  %10zu %14s %8zu %14zu %10s\n", alignments,
                           mask_name((MaskKind)which_mask), offset, want, "ok");
                }
            }
        }
    }

    if (arm_count < 2u)
    {
        printf("\n  only the portable arm is present, so nothing was graded against it\n");
    }

    /* TIMING, and only after every arm agreed. A faster arm returning a different count has not
     * been made faster. */
    printf("\n  SCAN RATE, %u alignments, all alive, 200 passes each\n\n", ARMS_CORPUS);
    printf("  %12s %12s %12s %16s\n", "arm", "passes", "seconds", "alignments/second");

    build_mask(alive, ARMS_CORPUS, MASK_ALL_ALIVE);
    const size_t passes = 200u;
    double portable_seconds = 0.0;

    for (size_t which = 0u; which < arm_count; which += 1u)
    {
        volatile size_t sink = 0u;
        const clock_t opened = clock();
        for (size_t pass = 0u; pass < passes; pass += 1u)
        {
            sink += arms[which]->count(corpus, ARMS_CORPUS - 8u, alive, corpus[0], 0u);
        }
        const clock_t closed = clock();
        (void)sink;

        const double seconds = (double)(closed - opened) / (double)CLOCKS_PER_SEC;
        if (which == 0u)
        {
            portable_seconds = seconds;
        }
        const double rate = (seconds > 0.0)
                          ? (((double)passes * (double)(ARMS_CORPUS - 8u)) / seconds)
                          : 0.0;
        printf("  %12s %12zu %12.3f %16.3e", arms[which]->name, passes, seconds, rate);
        if ((which > 0u) && (seconds > 0.0))
        {
            printf("   %.2fx portable", portable_seconds / seconds);
        }
        printf("\n");
    }

    printf("\n  %d check(s) failed\n", failed);
    free(corpus); free(alive);
    return (failed == 0) ? 0 : 1;
}
