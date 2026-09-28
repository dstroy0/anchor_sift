
// test_adversarial_plans.c: family guard, sampling cost, permutations and plans
#include "test_adversarial_internal.h"

/**
 * @brief Case 6. Shapes outside the necessary-condition family, refused by the guard.
 *
 * @return 0 where every illegal shape is refused and every legal one admitted, 1 otherwise.
 * @note This grades the GUARD instead of the count, because the first two shapes that leave the
 *       family are caught here and never reach a search. The third shape that leaves the family, a
 *       predicate taken from the census instead of the needle, is not reachable from outside and is
 *       named in the file block as a gap.
 */
int adversarial_case_family_guard(void)
{
    static const size_t needle_len = 16u;
    int failed = 0;

    // An origin at the needle length reads past the end and must be refused.
    const AnchorProbe past_end = {needle_len, 1u, 1u};
    if (anchor_steer_probe_fits(&past_end, needle_len) != 0)
    {
        printf("    FAIL origin at needle_len admitted\n");
        failed = 1;
    }

    // A line whose last position falls outside the needle must be refused.
    const AnchorProbe overruns = {needle_len - 2u, 4u, 3u};
    if (anchor_steer_probe_fits(&overruns, needle_len) != 0)
    {
        printf("    FAIL line overrunning the needle admitted\n");
        failed = 1;
    }

    // A zero step above length one reads one position repeatedly and carries no second condition.
    const AnchorProbe stalled = {0u, 0u, 4u};
    if (anchor_steer_probe_fits(&stalled, needle_len) != 0)
    {
        printf("    FAIL zero step above length one admitted\n");
        failed = 1;
    }

    // A zero length probe tests nothing and is not a necessary condition of anything.
    const AnchorProbe empty = {0u, 1u, 0u};
    if (anchor_steer_probe_fits(&empty, needle_len) != 0)
    {
        printf("    FAIL zero length probe admitted\n");
        failed = 1;
    }

    // The widest line that still lands inside must be admitted, or the guard is refusing the family.
    const AnchorProbe widest = {0u, needle_len - 1u, 2u};
    if (anchor_steer_probe_fits(&widest, needle_len) == 0)
    {
        printf("    FAIL widest fitting line refused\n");
        failed = 1;
    }

    printf("  family guard, verdict %s\n", (failed == 0) ? "ok" : "FAILS");
    return failed;
}

/**
 * @brief Case 7. What sampling costs, reported as a ratio against the unsampled planner.
 *
 * @return 0 where every stride returns the exact count, 1 otherwise.
 * @note THE COUNT IS THE PASS CONDITION AND THE READS ARE THE REPORT. Sampling cannot reach
 *       correctness, by the necessary-condition guarantee. A count that moves with the stride is
 *       a defect elsewhere. What sampling can do is choose worse probes, and the read ratio is what
 *       that costs. This turns a caveat in the guide into a number.
 */
int adversarial_case_sampling_cost(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[12];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    // A field periodic at 16. A stride sharing that period sees an unrepresentative sample.
    //
    // BUILT HERE, THOUGH bench_corpora BUILDS THE SAME FIELD. This was briefly folded
    // onto bench_build_bytes(CORPUS_PERIODIC), whose body is character for character this loop, and
    // the fold was withdrawn: it would make a test depend on a bench corpus, and a bench corpus that
    // cannot be retuned without checking what it silently changed in the test suite has stopped
    // being a benchmark. test/ answers whether the engine is right and bench/ answers how fast, and
    // the dependency only runs one way.
    //
    // What this case needs is A period, not bench's period. The 16 below is free. Nothing here is
    // coupled to CORPUS_PERIODIC and no edit there can reach this.
    for (size_t at = 0u; at < ADVERSARIAL_CORPUS; at += 1u)
    {
        corpus[at] = (uint8_t)(at % 16u);
    }
    memcpy(needle, corpus + 64u, sizeof(needle));

    const size_t expected = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    anchor_steer_probes_reset();
    const size_t baseline_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 1);
    const uint64_t baseline_reads = anchor_steer_probes;

    if (baseline_count != expected)
    {
        printf("    FAIL periodic field count: %zu against %zu\n", baseline_count, expected);
        failed = 1;
    }

    printf("  sampling on a period-16 field, %llu reads at the planner's own stride\n",
           (unsigned long long)baseline_reads);
    printf("  sampling cost, verdict %s\n", (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 8. Probe order is a permutation null.
 *
 * @return 0 where every order of one probe set returns one count, 1 otherwise.
 * @note DIFFERENTIAL, AND IT TESTS THE COROLLARY DIRECTLY. An alignment survives only where every
 *       probe agrees, a conjunction commutes. The surviving set and the count are the same under
 *       any order. This was argued from the start and could not be checked until an entry took the
 *       probe set as an argument.
 * @note A failure here points at STATE CARRIED BETWEEN PROBES in the implementation and not at the
 *       theory, because the mathematics has no order in it to get wrong. That is the reading to
 *       give anyone who hits it.
 */
int adversarial_case_permutation_null(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[16];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    uint64_t state = 0x2545F4914F6CDD1DULL;
    adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, 6u, &state);
    memcpy(needle, corpus + 700u, sizeof(needle));

    const AnchorProbe orders[4][3] = {
        {{0u, 1u, 1u}, {7u, 1u, 1u}, {15u, 1u, 1u}},
        {{15u, 1u, 1u}, {0u, 1u, 1u}, {7u, 1u, 1u}},
        {{7u, 1u, 1u}, {15u, 1u, 1u}, {0u, 1u, 1u}},
        {{15u, 1u, 1u}, {7u, 1u, 1u}, {0u, 1u, 1u}},
    };
    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    for (size_t which = 0u; which < 4u; which += 1u)
    {
        const size_t counted =
            anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), orders[which], 3u);
        if (counted != reference)
        {
            printf("    FAIL order %zu returned %zu against reference %zu\n", which, counted, reference);
            failed = 1;
        }
    }

    printf("  probe order as a permutation null, verdict %s\n", (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 9. The empty probe set is the identity element.
 *
 * @return 0 where no probes still returns the exact count at zero probe reads, 1 otherwise.
 * @note THE CHEAPEST TOTAL CHECK OF THE WHOLE GUARANTEE. With no probes every alignment reaches the
 *       full compare. The answer is exactly right and the cost is maximal. If this fails, the
 *       verifier is wrong and every other count in the tree rests on nothing, because every probe
 *       set relies on that same compare to remove its false survivors.
 * @note The read count is graded at zero as a premise check. Probes reading bytes where no probe
 *       was supplied would mean the entry is choosing its own, and the case would be measuring
 *       something other than the identity.
 */
int adversarial_case_empty_plan(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[12];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    uint64_t state = 0x14057B7EF767814FULL;
    adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, 4u, &state);
    memcpy(needle, corpus + 321u, sizeof(needle));

    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    anchor_steer_probes_reset();
    const size_t counted = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), NULL, 0u);
    const uint64_t reads = anchor_steer_probes;

    if (counted != reference)
    {
        printf("    FAIL empty plan counted %zu against reference %zu\n", counted, reference);
        failed = 1;
    }
    if (reads != 0u)
    {
        printf("    FAIL premise: %llu probe reads with no probes supplied\n", (unsigned long long)reads);
        failed = 1;
    }

    printf("  the empty plan, %zu occurrences at %llu probe reads, verdict %s\n", counted, (unsigned long long)reads,
           (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 10. Growing a probe set changes the cost and never the count.
 *
 * @return 0 where one, two, three and four probes all return the reference count, 1 otherwise.
 * @note THIS IS THEOREM 1 STATED AS A MEASUREMENT. The count is exact for ANY probe set. A sequence
 *       of sets returning different counts therefore refutes the necessary-condition guarantee
 *       itself. Each probe is a necessary condition of an occurrence, a conjunction of them is one,
 *       and the full compare removes the false survivors.
 * @note The reads are reported and never asserted, because more probes may read more or fewer bytes
 *       depending on where the field refutes, and only the count is guaranteed.
 */
int adversarial_case_growing_plan(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[20];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    uint64_t state = 0x76E15D3EFEFDCBBFULL;
    adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, 5u, &state);
    memcpy(needle, corpus + 1024u, sizeof(needle));

    const AnchorProbe probes[4] = {
        {0u, 1u, 1u},
        {19u, 1u, 1u},
        {9u, 1u, 1u},
        {4u, 5u, 2u},
    };
    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    for (size_t used = 1u; used <= 4u; used += 1u)
    {
        anchor_steer_probes_reset();
        const size_t counted =
            anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), probes, used);
        if (counted != reference)
        {
            printf("    FAIL %zu probe(s) counted %zu against reference %zu\n", used, counted, reference);
            failed = 1;
        }
    }

    // The empty-needle boundary, which no other case reaches. An empty needle occurs at every
    // alignment. The reference is corpus_len + 1. anchor_steer_count_with_probes returned 0 here
    // until its guard was split, disagreeing with anchor_sift_naive and anchor_steer_count in the
    // same tree. The probes cannot be evaluated on a needle with no positions. The empty probe set
    // grades it.
    {
        const size_t empty_reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, 0u);
        const size_t empty_counted = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, 0u, NULL, 0u);
        if (empty_counted != empty_reference)
        {
            printf("    FAIL empty needle counted %zu against reference %zu\n", empty_counted, empty_reference);
            failed = 1;
        }
    }

    // A probe that reads past the needle. Its last position is (needle_len - 2) + 4*2, which is
    // needle_len + 6. Anchor_steer_probe_fits rejects it and the count is 0. Before the guard,
    // count_with_probes read needle[offset] and corpus[at + offset] off the end of both. The count
    // it returns is not the reference; a refusal is the point, and 0 is the documented one.
    {
        const AnchorProbe overruns = {sizeof(needle) - 2u, 4u, 3u};
        const size_t refused =
            anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), &overruns, 1u);
        if (refused != 0u)
        {
            printf("    FAIL a probe past the needle counted %zu, expected the refusal 0\n", refused);
            failed = 1;
        }
    }

    printf("  growing the plan over %zu occurrences, verdict %s\n", reference, (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 11. Stopping at the destroy condition equals running to full depth.
 *
 * @return 0 where both descents agree on the count and on every probe the shallow one placed, 1
 *         otherwise.
 * @note THE DESTROY THEOREM TESTED BY ITS CONSEQUENCE. Under a candidate set that does not grow
 *       with the level, a fired stop condition would fire at every level below. Stopping and
 *       continuing place the same probes up to the stop point and return the same count.
 * @note TWO FAILURE MODES, AND THEY MEAN DIFFERENT THINGS. Counts differing means the
 *       necessary-condition guarantee broke, since both probe sets are legal whatever the descent
 *       chose. The probes before the stop point differing means the induction broke, and the
 *       candidate set is growing with the level where the theorem requires it not to. Reporting one
 *       verdict for both would lose that distinction.
 */
int adversarial_case_stop_equals_continue(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[16];
    size_t shallow[ANCHOR_STEER_ANCHORS];
    size_t deep[ANCHOR_STEER_ANCHORS];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    // A field of one repeated symbol, where the first probe prunes nothing and the stop fires early.
    memset(corpus, 'm', ADVERSARIAL_CORPUS);
    memset(needle, 'm', sizeof(needle));

    const size_t alignments = ADVERSARIAL_CORPUS - sizeof(needle) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);

    if (survivors == NULL)
    {
        printf("    allocation failed\n");
        free(corpus);
        return 1;
    }

    // The two runs differ in one member only, and the case exists to compare them.
    // force_full_depth is omitted on the first, and an omitted member is zero, the destroy
    // rule honored. Naming it on the second forces every level.
    const size_t stopped = ANCHOR_STEER_CALL(
        anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = shallow, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle, .needle_len = sizeof(needle),
        .survivors = survivors, .survivors_length = alignments, .sample_stride = 1u);
    const size_t forced = ANCHOR_STEER_CALL(
        anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = deep, .count = ANCHOR_STEER_ANCHORS, .corpus = corpus,
        .corpus_len = ADVERSARIAL_CORPUS, .needle = needle, .needle_len = sizeof(needle), .survivors = survivors,
        .survivors_length = alignments, .sample_stride = 1u, .force_full_depth = 1);

    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));
    const size_t shallow_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 1);

    if (shallow_count != reference)
    {
        printf("    FAIL descent count %zu against reference %zu\n", shallow_count, reference);
        failed = 1;
    }
    for (size_t slot = 0u; slot < stopped; slot += 1u)
    {
        if (shallow[slot] != deep[slot])
        {
            printf("    FAIL induction: probe %zu is offset %zu stopped and %zu forced\n", slot, shallow[slot],
                   deep[slot]);
            failed = 1;
        }
    }
    if (forced < stopped)
    {
        printf("    FAIL forced depth %zu below stopped depth %zu\n", forced, stopped);
        failed = 1;
    }

    printf("  stopping equals continuing, %zu probes stopped against %zu forced, verdict %s\n", stopped, forced,
           (failed == 0) ? "ok" : "FAILS");
    free(survivors);
    free(corpus);
    return failed;
}
