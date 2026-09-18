/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_o2_spawn.c
 * @brief The engine turned onto itself: a descent that resumes from another descent's survivors.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * WHAT THIS PROVES. A single descent places at most ANCHOR_STEER_ANCHORS probes and resets its
 * survivor vector to all standing on entry. That caps one descent at four conditions. The resume
 * member of AnchorSteerDescent lifts the cap by composition: run a descent, then run the next over
 * the survivors the last one left. Each level reads only what its parent kept standing and the
 * depth is data-dependent and unbounded. This suite drives that composition and grades it against the
 * controls a recursive search needs.
 *
 *   POSITIVE CONTROL. A field with one planted occurrence over N alignments cannot be isolated in
 *   fewer than log2(N) binary probes, because each probe splits the survivors by one byte value and
 *   carries at most one bit. With N past 2000 that is at least eleven probes. Isolating the target
 *   composes well past one descent's cap of four. The lone survivor is then verified against the
 *   whole needle with a full compare before it is called found, which is this tree's rule that a
 *   survivor is not a match until the exact compare confirms it, carried into the recursive setting.
 *   The premise that the target is unique is checked, not assumed: a repeated target would stall the
 *   descent at its true-occurrence count, and that is a different outcome.
 *
 *   NULL. A flat field matches the needle at every alignment. No probe prunes anything and the
 *   destroy rule ends the composition at depth zero with every alignment still standing. A field with
 *   no cheap condition refuses, it does not answer.
 *
 *   ANYTIME. Stopped early, before the target is isolated, the survivor set is still a superset that
 *   contains the target. Containment holds at every level because a probe only ever turns an
 *   alignment off, never on.
 *
 *   COST. The read cost of the composition is the sum of the survivor counts down the levels, not the
 *   universe times the depth, because a resumed level reads only its parent's survivors. Reported for
 *   a pruning field and for a field whose conditions barely prune, which is the honest boundary: where
 *   nothing prunes cheaply the sum approaches the universe times the depth and the recursion saves
 *   nothing.
 *
 * @note No double, no float, nothing outside the C11 standard headers below. The composition is a
 *       plain loop over anchor_steer_spawn_coarms with resume set after the first call.
 */

#include "anchor_sift.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** @brief Corpus bytes every field carries. */
#define O2_CORPUS 2048u

/** @brief Needle length, long enough that a binary field rarely repeats a gram. */
#define O2_NEEDLE 20u

/**
 * @brief Next value of the generator. A failing run reduces from its printed seed alone.
 *
 * @param[in,out] state Generator state, advanced in place [BORROWS].
 * @return              A value in the low 32 bits.
 */
static uint32_t o2_next(uint64_t *const state)
{
    *state = (*state * 6364136223846793005ULL) + 1442695040888963407ULL;
    return (uint32_t)(*state >> 33);
}

/** @brief Standing alignments in a survivor buffer. */
static size_t o2_alive(const uint8_t *const survivors, const size_t alignments)
{
    size_t alive = 0u;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (survivors[at] != 0u)
        {
            alive += 1u;
        }
    }
    return alive;
}

/**
 * @brief Composes a recursive spawn, one probe per level, resuming from the last level's survivors.
 *
 * @param[in]  corpus     Bytes the search runs over [BORROWS].
 * @param[in]  needle     Bytes to find [BORROWS].
 * @param[out] survivors  One byte per alignment, the composition's output [BORROWS].
 * @param[in]  alignments How many.
 * @param[in]  max_depth  Levels to run at most. The anytime control passes a small one.
 * @param[out] depth_out  Probes actually placed [BORROWS].
 * @param[out] sum_out    Sum of survivor counts down the levels, the read cost [BORROWS].
 * @return                Alignments still standing when the composition stopped.
 * @note The first call resets, every later call resumes. The loop stops when a level prunes nothing,
 *       which is the destroy rule, or when one alignment is left, or at the depth ceiling.
 */
static size_t o2_compose(const uint8_t *const corpus, const uint8_t *const needle,
                         uint8_t *const survivors, const size_t alignments, const size_t max_depth,
                         size_t *const depth_out, uint64_t *const sum_out)
{
    size_t depth = 0u;
    uint64_t survivor_sum = 0u;
    int resume = 0;
    size_t alive = alignments;

    while (depth < max_depth)
    {
        size_t offset = 0u;
        const size_t placed = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                                .offsets = &offset,
                                                .count = 1u,
                                                .corpus = corpus,
                                                .corpus_len = O2_CORPUS,
                                                .needle = needle,
                                                .needle_len = O2_NEEDLE,
                                                .survivors = survivors,
                                                .survivors_length = alignments,
                                                .sample_stride = 1u,
                                                .resume = resume);
        resume = 1;
        alive = o2_alive(survivors, alignments);
        if (placed == 0u)
        {
            // The destroy rule: this level's best candidate pruned nothing. No condition left
            // separates the survivors. The composition stops rather than reading for no gain.
            break;
        }
        depth += 1u;
        survivor_sum += (uint64_t)alive;
        if (alive <= 1u)
        {
            break;
        }
    }

    *depth_out = depth;
    *sum_out = survivor_sum;
    return alive;
}

/** @brief Fills a corpus over an alphabet of the given size, least value most common where skewed. */
static void o2_fill(uint8_t *const corpus, const uint32_t alphabet, uint64_t *const state)
{
    for (size_t at = 0u; at < O2_CORPUS; at += 1u)
    {
        corpus[at] = (uint8_t)(o2_next(state) % alphabet);
    }
}

/**
 * @brief Case 1. A unique target is found by composing past one descent's cap, then verified.
 *
 * @return 0 where the composition isolates the planted target at a depth above ANCHOR_STEER_ANCHORS
 *         and the full compare confirms it, 1 otherwise.
 */
static int o2_case_found_past_cap(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(O2_CORPUS);
    const size_t alignments = (O2_CORPUS - O2_NEEDLE) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    int failed = 0;

    if ((corpus == NULL) || (survivors == NULL))
    {
        printf("    allocation failed\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    // A binary field, where each probe carries at most one bit and isolating one of N alignments
    // therefore takes at least log2(N) probes.
    uint64_t state = 0x0123456789ABCDEFULL;
    o2_fill(corpus, 2u, &state);

    // The target is the first alignment whose needle occurs exactly once, searched for rather than
    // assumed. The premise the depth bound rests on is a fact of this field and not a hope.
    size_t origin = alignments;
    for (size_t candidate = 0u; candidate < alignments; candidate += 1u)
    {
        if (anchor_sift_naive(corpus, O2_CORPUS, corpus + candidate, O2_NEEDLE) == 1u)
        {
            origin = candidate;
            break;
        }
    }

    if (origin == alignments)
    {
        printf("    FAIL premise: no unique target in the field, cannot test isolation\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    const uint8_t *const needle = corpus + origin;

    size_t depth = 0u;
    uint64_t survivor_sum = 0u;
    const size_t left = o2_compose(corpus, needle, survivors, alignments, O2_NEEDLE + 1u, &depth,
                                   &survivor_sum);

    if (left != 1u)
    {
        printf("    FAIL the composition left %zu standing, not the single target\n", left);
        failed = 1;
    }
    if (depth <= ANCHOR_STEER_ANCHORS)
    {
        printf("    FAIL depth %zu did not exceed one descent's cap of %u\n", depth,
               ANCHOR_STEER_ANCHORS);
        failed = 1;
    }

    // The lone survivor is not a match until the full compare confirms it against the whole needle.
    size_t survivor = alignments;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (survivors[at] != 0u)
        {
            survivor = at;
            break;
        }
    }
    if ((survivor == alignments)
        || (memcmp(corpus + survivor, needle, O2_NEEDLE) != 0))
    {
        printf("    FAIL the sole survivor did not verify against the needle\n");
        failed = 1;
    }

    printf("  found past the cap: %zu alignments isolated to 1 in %zu probes, verdict %s\n",
           alignments, depth, (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    free(survivors);
    return failed;
}

/**
 * @brief Case 2. A flat field refuses: no probe prunes, and the composition stops at depth zero.
 *
 * @return 0 where nothing is pruned and no single survivor is claimed, 1 otherwise.
 */
static int o2_case_flat_refuses(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(O2_CORPUS);
    const size_t alignments = (O2_CORPUS - O2_NEEDLE) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    int failed = 0;

    if ((corpus == NULL) || (survivors == NULL))
    {
        printf("    allocation failed\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    // One repeated symbol. The needle matches at every alignment. Every probe agrees everywhere
    // and prunes nothing.
    uint8_t needle[O2_NEEDLE];
    memset(corpus, 'q', O2_CORPUS);
    memset(needle, 'q', sizeof(needle));

    size_t depth = 0u;
    uint64_t survivor_sum = 0u;
    const size_t left = o2_compose(corpus, needle, survivors, alignments, O2_NEEDLE + 1u, &depth,
                                   &survivor_sum);

    if (depth != 0u)
    {
        printf("    FAIL a probe was placed on a flat field, depth %zu\n", depth);
        failed = 1;
    }
    if (left != alignments)
    {
        printf("    FAIL the flat field pruned %zu of %zu alignments\n", alignments - left,
               alignments);
        failed = 1;
    }

    printf("  flat field refuses: %zu standing at depth %zu, verdict %s\n", left, depth,
           (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    free(survivors);
    return failed;
}

/**
 * @brief Case 3. Stopped early, the survivor superset still contains the target.
 *
 * @return 0 where the target is still standing after a shallow, incomplete composition, 1 otherwise.
 */
static int o2_case_anytime_superset(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(O2_CORPUS);
    const size_t alignments = (O2_CORPUS - O2_NEEDLE) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    int failed = 0;

    if ((corpus == NULL) || (survivors == NULL))
    {
        printf("    allocation failed\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    uint64_t state = 0x0123456789ABCDEFULL;
    o2_fill(corpus, 2u, &state);

    size_t origin = alignments;
    for (size_t candidate = 0u; candidate < alignments; candidate += 1u)
    {
        if (anchor_sift_naive(corpus, O2_CORPUS, corpus + candidate, O2_NEEDLE) == 1u)
        {
            origin = candidate;
            break;
        }
    }
    if (origin == alignments)
    {
        printf("    FAIL premise: no unique target in the field\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    // Three levels, short of the eleven or more that isolation needs. The target sits inside a
    // superset larger than one.
    size_t depth = 0u;
    uint64_t survivor_sum = 0u;
    const size_t left = o2_compose(corpus, corpus + origin, survivors, alignments, 3u, &depth,
                                   &survivor_sum);

    if (left <= 1u)
    {
        printf("    FAIL premise: the shallow stop already isolated the target, superset is trivial\n");
        failed = 1;
    }
    if (survivors[origin] == 0u)
    {
        printf("    FAIL the target was dropped from the superset by an incomplete composition\n");
        failed = 1;
    }

    printf("  anytime superset: target still standing among %zu after %zu probes, verdict %s\n",
           left, depth, (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    free(survivors);
    return failed;
}

/**
 * @brief Case 4. The read cost, reported for a pruning field against a barely-pruning one.
 *
 * @return 0 always. The cost is reported and not asserted, since the numbers belong to the fields.
 * @note THE HONEST BOUNDARY. A pruning field collapses the survivors fast. The sum of survivor
 *       counts down the levels stays near twice the universe. A field whose conditions barely prune
 *       runs many levels each reading most of the universe. The sum approaches the universe times
 *       the depth and the recursion saves nothing. Both are printed so the boundary is a number.
 */
static int o2_case_cost_boundary(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(O2_CORPUS);
    const size_t alignments = (O2_CORPUS - O2_NEEDLE) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);

    if ((corpus == NULL) || (survivors == NULL))
    {
        printf("    allocation failed\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    // Pruning field: a balanced binary alphabet, where each probe removes about half the survivors.
    uint64_t state = 0x0123456789ABCDEFULL;
    o2_fill(corpus, 2u, &state);
    size_t prune_origin = alignments;
    for (size_t candidate = 0u; candidate < alignments; candidate += 1u)
    {
        if (anchor_sift_naive(corpus, O2_CORPUS, corpus + candidate, O2_NEEDLE) == 1u)
        {
            prune_origin = candidate;
            break;
        }
    }

    size_t prune_depth = 0u;
    uint64_t prune_sum = 0u;
    if (prune_origin != alignments)
    {
        (void)o2_compose(corpus, corpus + prune_origin, survivors, alignments, O2_NEEDLE + 1u,
                         &prune_depth, &prune_sum);
    }

    // Barely-pruning field: the least symbol dominates and the needle is all of it. Most
    // alignments agree at most positions and each probe removes few.
    uint64_t skew_state = 0x0BADC0DE0BADC0DEULL;
    for (size_t at = 0u; at < O2_CORPUS; at += 1u)
    {
        // Nine tenths the common symbol, one tenth a rare one.
        corpus[at] = (uint8_t)(((o2_next(&skew_state) % 10u) == 0u) ? 1u : 0u);
    }
    uint8_t common_needle[O2_NEEDLE];
    memset(common_needle, 0, sizeof(common_needle));

    size_t skew_depth = 0u;
    uint64_t skew_sum = 0u;
    (void)o2_compose(corpus, common_needle, survivors, alignments, O2_NEEDLE + 1u, &skew_depth,
                     &skew_sum);

    const uint64_t rescan_prune = (uint64_t)alignments * (uint64_t)prune_depth;
    const uint64_t rescan_skew = (uint64_t)alignments * (uint64_t)skew_depth;

    printf("  cost, %zu alignments:\n", alignments);
    printf("    pruning field:       %llu reads over %zu levels, a re-scan would read %llu\n",
           (unsigned long long)prune_sum, prune_depth, (unsigned long long)rescan_prune);
    printf("    barely-pruning field: %llu reads over %zu levels, a re-scan would read %llu\n",
           (unsigned long long)skew_sum, skew_depth, (unsigned long long)rescan_skew);

    free(corpus);
    free(survivors);
    return 0;
}

int main(void)
{
    int failed = 0;

    printf("\n  O2 COMPOSITION, a descent resuming from another descent's survivors.\n\n");

    failed += o2_case_found_past_cap();
    failed += o2_case_flat_refuses();
    failed += o2_case_anytime_superset();
    failed += o2_case_cost_boundary();

    printf("\n  %d case(s) failed\n\n", failed);
    return (failed == 0) ? 0 : 1;
}
