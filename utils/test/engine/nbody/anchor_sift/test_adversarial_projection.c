
// test_adversarial_projection.c: the joint projection and main
#include "test_adversarial_internal.h"

/**
 * @brief Case 13. A corpus and needle projected apart lose true occurrences; projected together
 *        they do not.
 *
 * @return 0 where the joint route never undercounts, is exact at 256 classes or fewer, and every
 *         premise holds, 1 otherwise.
 *
 * @note THE DEFECT. A rank is a symbol's place in the rarity order of the population one call
 *       counted. The class comes from the oracle the caller supplies, and it is the same
 *       function on both sides. The place comes from counting, and two calls count two populations.
 *       Their orders disagree, rank disagreement stops proving symbol disagreement, and a probe
 *       refutes an alignment whose symbols match.
 *
 * @note THREE PARTS, EACH WITH ITS PREMISE CHECKED.
 *       Part one is the counterexample in its original form, built by hand. The separate
 *       route MUST return 0 there. If it does not, the case no longer reaches the defect and a
 *       passing joint route proves nothing.
 *       Part two is a seeded sweep, needles cut from the corpus on even seeds and drawn
 *       independently on odd ones, over alphabets from 2 to 399 symbols. It grades the joint route
 *       against a direct symbol count on every seed, and requires that the sweep reached both the
 *       exact regime and the clamped one and that the separate route lost at least one occurrence.
 *       Part three builds a field past 256 classes where the clamp merges the two classes the
 *       needle uses. The joint rank count must stay at or above the truth and must exceed it, or
 *       the upper bound anchor_field_pair_project documents has not been measured.
 *
 * @note WHY THE SUITE DID NOT CATCH IT. The one projected search in test_steer builds its rank
 *       needle by copying out of the corpus's own projected ranks (`utils/test/engine/nbody/anchor_sift/test_steer_*.c`,
 *       the loop filling `rank_needle`). Its needle and corpus come from one population by
 *       construction and the two orders could never disagree.
 */
static int adversarial_case_joint_projection(void)
{
    const size_t buffer_positions = ADVERSARIAL_PROJECTED + ADVERSARIAL_PROJECTED_NEEDLE;
    uint32_t *const corpus = (uint32_t *)malloc(ADVERSARIAL_PROJECTED * sizeof(uint32_t));
    uint8_t *const corpus_ranks = (uint8_t *)malloc(ADVERSARIAL_PROJECTED);
    const AdversarialClassBuffers buffers = {
        .class_of_position = (uint32_t *)malloc(buffer_positions * sizeof(uint32_t)),
        .members_in_class = (uint32_t *)malloc(buffer_positions * sizeof(uint32_t)),
        .rarity_place_of_class = (uint32_t *)malloc(buffer_positions * sizeof(uint32_t)),
        .classes_length = buffer_positions};
    uint32_t needle[ADVERSARIAL_PROJECTED_NEEDLE];
    uint8_t needle_ranks[ADVERSARIAL_PROJECTED_NEEDLE];
    int failed = 0;

    if ((corpus == NULL) || (corpus_ranks == NULL) || (buffers.class_of_position == NULL) ||
        (buffers.members_in_class == NULL) || (buffers.rarity_place_of_class == NULL))
    {
        printf("    allocation failed\n");
        free(corpus);
        free(corpus_ranks);
        free(buffers.class_of_position);
        free(buffers.members_in_class);
        free(buffers.rarity_place_of_class);
        return 1;
    }

    // PART ONE. The counterexample as reported: one rare symbol, ten of a middle one, a hundred of a
    // common one, and the needle common common middle rare occurring once, at 98.
    const uint32_t symbol_rare = 0x000A0001u;
    const uint32_t symbol_middle = 0x000B0002u;
    const uint32_t symbol_common = 0x000C0003u;
    const size_t reported_length = 1u + 10u + 100u;
    const size_t reported_needle_length = 4u;

    for (size_t at = 0u; at < reported_length; at += 1u)
    {
        corpus[at] = symbol_common;
    }
    for (size_t at = 0u; at < 9u; at += 1u)
    {
        corpus[at] = symbol_middle;
    }
    corpus[100] = symbol_middle;
    corpus[101] = symbol_rare;
    needle[0] = symbol_common;
    needle[1] = symbol_common;
    needle[2] = symbol_middle;
    needle[3] = symbol_rare;

    const size_t reported_truth = adversarial_count_symbols(corpus, reported_length, needle, reported_needle_length);
    size_t reported_apart = 0u;
    size_t reported_together = 0u;
    size_t reported_distinct = 0u;
    const int reported_apart_ran = adversarial_count_apart(corpus, reported_length, needle, reported_needle_length,
                                                           corpus_ranks, needle_ranks, &buffers, &reported_apart);
    const int reported_together_ran =
        adversarial_count_together(corpus, reported_length, needle, reported_needle_length, corpus_ranks, needle_ranks,
                                   &buffers, &reported_together, &reported_distinct);

    printf("  %34s %8s %8s %8s %8s\n", "reported counterexample", "truth", "apart", "together", "classes");
    printf("  %34s %8zu %8zu %8zu %8zu\n", "C C B A once, at 98", reported_truth, reported_apart, reported_together,
           reported_distinct);

    if (reported_truth != 1u)
    {
        printf("    FAIL premise: the hand built field holds %zu occurrences, not 1\n", reported_truth);
        failed = 1;
    }
    if ((reported_apart_ran == 0) || (reported_apart != 0u))
    {
        printf("    FAIL negative control: the separate route did not lose the occurrence. This"
               " case no longer reaches the defect\n");
        failed = 1;
    }
    if ((reported_together_ran == 0) || (reported_together != reported_truth))
    {
        printf("    FAIL the joint route returned %zu against truth %zu\n", reported_together, reported_truth);
        failed = 1;
    }

    // PART TWO. A seeded sweep. Alphabets run from 2 to 399 symbols, which puts 512 positions both
    // under and over 256 classes.
    uint64_t state = 0x9E3779B97F4A7C15ULL;
    size_t exact_regime = 0u;
    size_t clamped_regime = 0u;
    size_t apart_losses = 0u;

    for (size_t seed = 0u; seed < ADVERSARIAL_SEEDS; seed += 1u)
    {
        const uint32_t alphabet = 2u + (adversarial_next(&state) % 398u);
        const size_t needle_length = 1u + (adversarial_next(&state) % ADVERSARIAL_PROJECTED_NEEDLE);

        for (size_t at = 0u; at < ADVERSARIAL_PROJECTED; at += 1u)
        {
            corpus[at] = 0x00100000u + (adversarial_next(&state) % alphabet);
        }

        // Even seeds cut the needle out of the corpus. The true count is at least one. Odd seeds draw
        // it independently. The needle holds symbols in proportions the corpus does not.
        if ((seed % 2u) == 0u)
        {
            const size_t origin = adversarial_next(&state) % ((ADVERSARIAL_PROJECTED - needle_length) + 1u);

            for (size_t at = 0u; at < needle_length; at += 1u)
            {
                needle[at] = corpus[origin + at];
            }
        }
        else
        {
            for (size_t at = 0u; at < needle_length; at += 1u)
            {
                needle[at] = 0x00100000u + (adversarial_next(&state) % alphabet);
            }
        }

        const size_t truth = adversarial_count_symbols(corpus, ADVERSARIAL_PROJECTED, needle, needle_length);
        size_t apart = 0u;
        size_t together = 0u;
        size_t distinct = 0u;
        const int apart_ran = adversarial_count_apart(corpus, ADVERSARIAL_PROJECTED, needle, needle_length,
                                                      corpus_ranks, needle_ranks, &buffers, &apart);
        const int together_ran = adversarial_count_together(corpus, ADVERSARIAL_PROJECTED, needle, needle_length,
                                                            corpus_ranks, needle_ranks, &buffers, &together, &distinct);

        if ((apart_ran == 0) || (together_ran == 0))
        {
            printf("    FAIL seed %zu: a projection errored on a valid field\n", seed);
            failed = 1;
            continue;
        }
        if (apart < truth)
        {
            apart_losses += 1u;
        }

        // At 256 classes or fewer no place is clamped. The rank count must equal the truth. Past
        // that the clamp can merge classes and the rank count must not fall below it.
        if (distinct <= 256u)
        {
            exact_regime += 1u;
            if (together != truth)
            {
                printf("    FAIL seed %zu: %zu classes, joint route %zu against truth %zu\n", seed, distinct, together,
                       truth);
                failed = 1;
            }
        }
        else
        {
            clamped_regime += 1u;
            if (together < truth)
            {
                printf("    FAIL seed %zu: %zu classes, joint route %zu BELOW truth %zu\n", seed, distinct, together,
                       truth);
                failed = 1;
            }
        }
    }

    printf("  %34s %8s %8s %8s\n", "seeded sweep", "exact", "clamped", "lost");
    printf("  %34s %8zu %8zu %8zu\n", "seeds by regime, apart losses", exact_regime, clamped_regime, apart_losses);

    if ((exact_regime == 0u) || (clamped_regime == 0u))
    {
        printf("    FAIL premise: the sweep did not reach both regimes\n");
        failed = 1;
    }
    if (apart_losses == 0u)
    {
        printf("    FAIL negative control: the separate route never lost an occurrence across the"
               " sweep\n");
        failed = 1;
    }

    // PART THREE. Three hundred distinct symbols, and a needle cut from positions 260 and 261. Joint
    // places 0 to 254 stay apart and every class from place 255 on takes rank 255, including both of
    // the needle's. Every adjacent pair from position 255 on agrees with the needle on rank.
    const size_t singleton_length = 300u;

    for (size_t at = 0u; at < singleton_length; at += 1u)
    {
        // Narrows a position below 300 into 32 bits, which holds it.
        corpus[at] = 0x00200000u + (uint32_t)at;
    }
    needle[0] = corpus[260];
    needle[1] = corpus[261];

    const size_t clamp_truth = adversarial_count_symbols(corpus, singleton_length, needle, 2u);
    size_t clamp_together = 0u;
    size_t clamp_distinct = 0u;
    const int clamp_ran = adversarial_count_together(corpus, singleton_length, needle, 2u, corpus_ranks, needle_ranks,
                                                     &buffers, &clamp_together, &clamp_distinct);

    printf("  %34s %8s %8s %8s\n", "clamp merges the needle", "truth", "together", "classes");
    printf("  %34s %8zu %8zu %8zu\n", "upper bound, never below", clamp_truth, clamp_together, clamp_distinct);

    if ((clamp_ran == 0) || (clamp_distinct <= 256u))
    {
        printf("    FAIL premise: the field did not pass 256 classes\n");
        failed = 1;
    }
    if (clamp_together < clamp_truth)
    {
        printf("    FAIL the joint route fell below the truth past the clamp\n");
        failed = 1;
    }
    if (clamp_together <= clamp_truth)
    {
        printf("    FAIL premise: the clamp merged nothing the needle uses. The upper bound is"
               " unmeasured\n");
        failed = 1;
    }

    printf("  joint projection keeps every true occurrence, verdict %s\n", (failed == 0) ? "ok" : "FAILS");

    free(corpus);
    free(corpus_ranks);
    free(buffers.class_of_position);
    free(buffers.members_in_class);
    free(buffers.rarity_place_of_class);
    return failed;
}

int main(void)
{
    int failed = 0;

    printf("\n  ADVERSARIAL SUITE, written to break the guarantees and not show them.\n\n");

    failed += adversarial_case_differential_net();
    failed += adversarial_case_overlapping();
    failed += adversarial_case_boundaries();
    failed += adversarial_case_absent_symbol();
    failed += adversarial_case_all_survivors_false();
    failed += adversarial_case_family_guard();
    failed += adversarial_case_sampling_cost();
    failed += adversarial_case_permutation_null();
    failed += adversarial_case_empty_plan();
    failed += adversarial_case_growing_plan();
    failed += adversarial_case_stop_equals_continue();
    failed += adversarial_case_trichotomy();
    failed += adversarial_case_joint_projection();

    printf("\n  %d case(s) failed\n\n", failed);
    return (failed == 0) ? 0 : 1;
}
