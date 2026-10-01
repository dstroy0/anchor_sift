
// test_steer_projection.c: projection and type agreement, and main
#include "test_steer_internal.h"

/**
 * @brief Grades the projection under a predicate that is not transitive.
 *
 * @return Count of failures.
 *
 * THE CASE THAT WAS SILENTLY WRONG. Classes are the transitive closure of the predicate.
 * Agreement must imply a shared rank even where the predicate chains. The check builds a chain,
 * 0 1 2 3 4, where each value agrees with its neighbors at a tolerance of 2 and the ends do not
 * agree with each other at all. The closure is one component. Every position must carry one rank.
 *
 * A grouping that stopped at the first matching representative would have produced more than one
 * class here, and a rank probe built on it would have refuted an alignment holding a true
 * occurrence. This asserts the closure and not the first match, the difference between
 * useless and wrong.
 */
static int check_projection_closes(void)
{
    printf("\n  PROJECTION UNDER A PREDICATE THAT IS NOT TRANSITIVE.\n\n");

    int failed = 0;
    const size_t length = 5u;
    const uint32_t chain[5] = {0u, 1u, 2u, 3u, 4u};
    uint8_t ranks[5];
    uint32_t class_of[5];
    uint32_t members[5];
    uint32_t place[5];
    size_t classes = 0u;

    const AnchorFieldProjection loose = {
        near_same_in_field, chain, length, ranks, class_of, members, place, length, &classes};

    if (anchor_field_project(&loose) == 0)
    {
        printf("  the projection errored on the chain: FAILS\n");
        return 1;
    }

    // The ends disagree, which makes the predicate non-transitive and not merely coarse.
    if (near_same_in_field(chain, 0u, 4u) != 0)
    {
        printf("  the chain ends agree. This is not the case under test: FAILS\n");
        failed += 1;
    }

    size_t differing = 0u;
    for (size_t at = 1u; at < length; at += 1u)
    {
        if (ranks[at] != ranks[0])
        {
            differing += 1u;
        }
    }

    printf("  %38s %8zu %8s %10s\n", "chain of 5, tolerance 2, classes", classes, "1",
           (classes == 1u) ? "closed" : "SPLIT");
    failed += (classes == 1u) ? 0 : 1;

    printf("  %38s %8zu %8s %10s\n", "positions carrying a different rank", differing, "0",
           (differing == 0u) ? "sound" : "UNSOUND");
    failed += (differing == 0u) ? 0 : 1;

    // A FIELD WITH MORE CLASSES THAN A BYTE RANK CAN NAME MUST BE ERROR AND NOT DEGRADED. The
    // degradation it replaces was measured: the overflow was decided at discovery, before
    // the rarity sort. The merged set was chosen by arrival order, and since a rare class arrives
    // late the overflow ate the rarest classes. Two fields with identical histograms merged sets
    // whose mean occupancies differed by a factor of 8.5. Erroring is checked here because a silent
    // degradation is indistinguishable from a good projection at the call site.
    const size_t wide_len = 400u;
    uint32_t *const wide = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint8_t *const wide_ranks = (uint8_t *)malloc(wide_len);
    uint32_t *const wide_class_of = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint32_t *const wide_members = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint32_t *const wide_place = (uint32_t *)malloc(wide_len * sizeof(uint32_t));

    if ((wide == NULL) || (wide_ranks == NULL) || (wide_class_of == NULL) || (wide_members == NULL) ||
        (wide_place == NULL))
    {
        printf("  allocation failed\n");
        failed += 1;
    }
    else
    {
        for (size_t at = 0u; at < wide_len; at += 1u)
        {
            wide[at] = (uint32_t)at;
        }

        size_t wide_classes = 0u;
        const AnchorFieldProjection wide_args = {sample_same_in_field, wide,          wide_len,
                                                 wide_ranks,           wide_class_of, wide_members,
                                                 wide_place,           wide_len,      &wide_classes};
        const int elapsed = anchor_field_project(&wide_args);

        printf("  %38s %8zu %8s %10s\n", "400 classes, counted not capped", wide_classes, "400",
               ((elapsed != 0) && (wide_classes == wide_len)) ? "ok" : "FAILS");
        failed += ((elapsed != 0) && (wide_classes == wide_len)) ? 0 : 1;

        // THE RAREST 255 KEEP THEIR OWN RANKS AND THE COMMONEST MERGE. Every class here holds one
        // member. Ties break by class index and the first 255 positions take ranks 0 to 254 while
        // the rest share 255. The form this replaced capped during discovery and merged by ARRIVAL,
        // which on a natural field eats the rarest classes instead of the commonest.
        size_t distinct_ranks = 0u;
        int seen[256];
        for (size_t slot = 0u; slot < 256u; slot += 1u)
        {
            seen[slot] = 0;
        }
        for (size_t at = 0u; at < wide_len; at += 1u)
        {
            if (seen[wide_ranks[at]] == 0)
            {
                seen[wide_ranks[at]] = 1;
                distinct_ranks += 1u;
            }
        }

        printf("  %38s %8zu %8s %10s\n", "ranks used, rarest kept apart", distinct_ranks, "256",
               (distinct_ranks == 256u) ? "ok" : "FAILS");
        failed += (distinct_ranks == 256u) ? 0 : 1;
    }

    free(wide);
    free(wide_ranks);
    free(wide_class_of);
    free(wide_members);
    free(wide_place);

    // A ERROR WRITES NOTHING, AND THAT IS CHECKED BY PLANTING A SENTINEL. Fail closed says a
    // request that cannot be met changes no state. The undersize path used to zero `distinct` while
    // the null and zero-length paths left it alone. A caller could not tell an errored zero from a
    // measured zero. The realistic caller error is sizing the buffers by an expected class count
    // and not by `length`, which hands over buffers correct for the field they had in mind.
    {
        const size_t sentinel_count = 43981u;
        size_t planted = sentinel_count;
        const AnchorFieldProjection undersize = {near_same_in_field, chain,   length, ranks, class_of, members, place,
                                                 length - 1u,        &planted};

        const int error = anchor_field_project(&undersize);

        printf("  %38s %8d %8s %10s\n", "buffers one short, errored", error, "0", (error == 0) ? "errored" : "RAN");
        failed += (error == 0) ? 0 : 1;

        printf("  %38s %8zu %8zu %10s\n", "and distinct left untouched", planted, sentinel_count,
               (planted == sentinel_count) ? "ok" : "WROTE");
        failed += (planted == sentinel_count) ? 0 : 1;
    }

    // The exact predicate on the same field must NOT collapse, or the check above would pass for
    // the wrong reason: a projection that always returned one class would satisfy it.
    size_t exact_classes = 0u;
    const AnchorFieldProjection strict = {sample_same_in_field, chain, length, ranks, class_of, members, place, length,
                                          &exact_classes};

    if (anchor_field_project(&strict) == 0)
    {
        printf("  the projection errored on the exact predicate: FAILS\n");
        failed += 1;
    }
    else
    {
        printf("  %38s %8zu %8s %10s\n", "same field, exact predicate, classes", exact_classes, "5",
               (exact_classes == 5u) ? "distinct" : "FAILS");
        failed += (exact_classes == 5u) ? 0 : 1;
    }
    return failed;
}

/**
 * @brief Grades the any-type path against the byte path, and the projection against the truth.
 *
 * @return Count of failures.
 *
 * TWO CLAIMS, AND ONLY THE SECOND COULD BE WRONG.
 *
 * First, that reaching a byte field through an equality oracle places the SAME offsets as reading it
 * as bytes. The oracle hides only the representation. A different answer would mean
 * the byte path was using something the proof does not license.
 *
 * Second, that projecting a field of any symbol type onto rarity ranks preserves soundness. Two
 * positions carrying the same symbol necessarily carry the same rank. Rank disagreement proves
 * symbol disagreement and a rank probe is a necessary condition. Rank agreement proves nothing,
 * and survivors therefore still reach an exact compare. The check is therefore NOT that the projected
 * count equals the true count: it is that the projected engine loses no true occurrence, the
 * only claim soundness makes. A projection that lost one would be a broken necessary condition
 * and the whole construction with it.
 *
 * The 32 bit sample field is here because a byte engine cannot read it at all. If the projection
 * works the sample field searches at full speed on the same loop bytes use, the point.
 */
static int check_any_type_agrees(void)
{
    printf("\n  ANY SYMBOL TYPE, AGAINST THE BYTE PATH AND AGAINST THE TRUTH.\n\n");

    int failed = 0;
    const size_t length = 16384u;
    uint8_t *const corpus = (uint8_t *)malloc(length);
    if (corpus == NULL)
    {
        printf("  allocation failed\n");
        return 1;
    }
    build_skewed_field(corpus, length);

    uint8_t needle[24];
    memcpy(needle, corpus + 2048u, sizeof(needle));

    const size_t alignments = (length - sizeof(needle)) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  allocation failed\n");
        free(corpus);
        return 1;
    }

    size_t by_bytes[ANCHOR_STEER_ANCHORS];
    const size_t placed_bytes = ANCHOR_STEER_CALL(
        anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = by_bytes, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = length, .needle = needle, .needle_len = sizeof(needle), .survivors = survivors,
        .survivors_length = alignments, .sample_stride = 1u);

    const ByteField byte_field = {corpus, needle};
    const AnchorField as_any = {byte_same_at, &byte_field, alignments, sizeof(needle)};

    size_t by_oracle[ANCHOR_STEER_ANCHORS];
    const size_t placed_oracle = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = by_oracle,
                                                   .count = ANCHOR_STEER_ANCHORS, .survivors = survivors,
                                                   .survivors_length = alignments, .sample_stride = 1u, .any = &as_any);

    if (placed_bytes != placed_oracle)
    {
        printf("  the oracle placed %zu where bytes placed %zu: FAILS\n", placed_oracle, placed_bytes);
        failed += 1;
    }
    else
    {
        size_t differing = 0u;
        for (size_t slot = 0u; slot < placed_bytes; slot += 1u)
        {
            if (by_bytes[slot] != by_oracle[slot])
            {
                differing += 1u;
            }
        }
        printf("  %38s %8zu %8zu %10s\n", "offsets placed, bytes against oracle", placed_bytes, placed_oracle,
               (differing == 0u) ? "identical" : "DIFFER");
        failed += (differing == 0u) ? 0 : 1;
    }

    // A field no byte engine can read. Projected to ranks it becomes one that every byte engine can.
    const size_t sample_len = 4096u;
    uint32_t *const samples = (uint32_t *)malloc(sample_len * sizeof(uint32_t));
    if (samples == NULL)
    {
        printf("  allocation failed\n");
        free(survivors);
        free(corpus);
        return 1;
    }

    uint64_t state = 0x5EEDu;
    for (size_t at = 0u; at < sample_len; at += 1u)
    {
        state = (state * 6364136223846793005ULL) + 1442695040888963407ULL;

        // Six distinct values at wildly different rates, each far outside a byte. The rarity
        // ordering has something to order and no byte engine could have read them.
        const uint32_t roll = (uint32_t)(state >> 33) % 1000u;
        if (roll < 500u)
        {
            samples[at] = 0xDEADBEEFu;
        }
        else if (roll < 800u)
        {
            samples[at] = 0xFEEDFACEu;
        }
        else if (roll < 950u)
        {
            samples[at] = 0x0BADC0DEu;
        }
        else if (roll < 990u)
        {
            samples[at] = 0xCAFEBABEu;
        }
        else if (roll < 999u)
        {
            samples[at] = 0x8BADF00Du;
        }
        else
        {
            samples[at] = 0xABADCAFEu;
        }
    }

    uint32_t sample_needle[8];
    memcpy(sample_needle, samples + 1024u, sizeof(sample_needle));

    const size_t sample_needle_len = sizeof(sample_needle) / sizeof(sample_needle[0]);
    const size_t sample_alignments = (sample_len - sample_needle_len) + 1u;

    const SampleField sample_field = {samples, sample_needle};
    const AnchorField sample_any = {sample_same_at, &sample_field, sample_alignments, sample_needle_len};

    // The true count, taken through the oracle alone with no projection and no probes. This is what
    // the projected engine is graded against.
    size_t truth = 0u;
    for (size_t at = 0u; at < sample_alignments; at += 1u)
    {
        size_t agreed = 0u;
        while (agreed < sample_needle_len)
        {
            if (sample_same_at(&sample_field, at + agreed, agreed) == 0)
            {
                break;
            }
            agreed += 1u;
        }
        if (agreed == sample_needle_len)
        {
            truth += 1u;
        }
    }

    uint8_t *const ranks = (uint8_t *)malloc(sample_len);
    uint32_t *const class_of = (uint32_t *)malloc(sample_len * sizeof(uint32_t));
    uint32_t *const members = (uint32_t *)malloc(sample_len * sizeof(uint32_t));
    uint32_t *const place = (uint32_t *)malloc(sample_len * sizeof(uint32_t));
    size_t classes = 0u;
    if ((ranks == NULL) || (class_of == NULL) || (members == NULL) || (place == NULL))
    {
        printf("  allocation failed\n");
        free(ranks);
        free(class_of);
        free(members);
        free(place);
        free(samples);
        free(survivors);
        free(corpus);
        return 1;
    }

    const AnchorFieldProjection sample_projection = {
        sample_same_in_field, samples, sample_len, ranks, class_of, members, place, sample_len, &classes};

    if (anchor_field_project(&sample_projection) == 0)
    {
        printf("  the projection errored on the sample field: FAILS\n");
        failed += 1;
    }
    else
    {
        uint8_t rank_needle[8];
        for (size_t at = 0u; at < sample_needle_len; at += 1u)
        {
            rank_needle[at] = ranks[1024u + at];
        }

        // The projected field run on the ordinary byte engine, the whole point: a 32 bit
        // alphabet reaching the same loop bytes use, AVX2 scan included.
        const size_t projected = anchor_sift_naive(ranks, sample_len, rank_needle, sample_needle_len);

        printf("  %38s %8zu %8zu %10s\n", "classes found, true count", classes, truth,
               (classes == 6u) ? "ok" : "CLASSES");
        failed += (classes == 6u) ? 0 : 1;

        // SOUNDNESS IS THE CLAIM, AND THE CLAIM IS ONE SIDED. The projected engine may return MORE than the
        // truth, because two symbols sharing a rank survive a rank probe. It may never return less,
        // because same symbol implies same rank. Fewer would mean a true occurrence was lost and the
        // necessary condition was not one.
        printf("  %38s %8zu %8zu %10s\n", "projected survivors, never below truth", projected, truth,
               (projected >= truth) ? "sound" : "UNSOUND");
        failed += (projected >= truth) ? 0 : 1;
    }

    free(ranks);
    free(samples);
    free(survivors);
    free(corpus);
    return failed;
}

int main(void)
{
    uint8_t *corpus = (uint8_t *)malloc(STEER_CORPUS);
    if (corpus == NULL)
    {
        printf("  allocation failed\n");
        return 1;
    }
    build_skewed_field(corpus, STEER_CORPUS);

    /* The needle is taken FROM the field. It occurs at least once and the counts are not all
     * zero. A needle that never occurs grades the rejection path only and never the verification
     * path, and the two are where the arms could disagree. */
    uint8_t needle[64];
    memcpy(needle, corpus + 4096u, sizeof(needle));

    AnchorFieldCensus census;
    anchor_field_census(corpus, STEER_CORPUS, &census);
    printf("\n  field: %u bytes, %u distinct symbols, prefers %s arm\n", STEER_CORPUS, census.distinct,
           anchor_steer_prefers_free(&census) ? "free order" : "short circuiting");

    int failed = 0;
    failed += check_counts_agree(corpus, STEER_CORPUS, needle);
    failed += check_ordering_pays(corpus, STEER_CORPUS, needle, sizeof(needle));
    failed += check_dispatch_exact();
    failed += check_exact_matches_double();
    failed += check_arm_is_wired(corpus, STEER_CORPUS, needle, sizeof(needle));
    failed += check_any_type_agrees();
    failed += check_projection_closes();

    printf("\n  ARMS, EYES AND COARMS, spawned and swept against a reference count.\n");
    failed += grade_field("synthetic skewed", corpus, STEER_CORPUS);

    // THE CORPUS FAMILY AND NOT ONE CORPUS. The ordering was built against the field
    // above, and a route graded only there reports the tuning instead of the route. These three
    // span what a byte field can be: no structure to find, rarity that varies, and a field that
    // repeats. A route that pays on one of them and costs on another is a route with a domain, and
    // the domain is what a reader needs.
    uint8_t *swept = (uint8_t *)malloc(STEER_CORPUS);
    if (swept == NULL)
    {
        printf("  allocation failed\n");
        free(corpus);
        return 1;
    }
    for (CorpusKind kind = CORPUS_UNIFORM; kind <= CORPUS_PERIODIC; kind += 1)
    {
        bench_build_bytes(swept, STEER_CORPUS, kind, 0x5EEDu + (uint64_t)kind);
        failed += grade_field(bench_corpus_name(kind), swept, STEER_CORPUS);
    }
    free(swept);

    /* A REAL NATURAL OBJECT AND NOT A GENERATOR. Everything above runs on bytes this file wrote,
     * which share whatever structure the generator happens to have. English prose is a field
     * nobody here designed: its letter frequencies span three decades, it repeats at no fixed
     * period, and its correlations between positions are real and not planted. The license
     * text is tracked in this repository. The grader needs no network and no dataset fetch and
     * runs from a fresh clone. */
    size_t natural_len = 0u;
    uint8_t *natural = read_whole_file(ANCHOR_SIFT_SOURCE_ROOT "/LICENSES/AGPL-3.0-or-later.txt", &natural_len);
    if (natural != NULL)
    {
        failed += grade_field("natural, AGPL English text", natural, natural_len);
        free(natural);
    }
    else
    {
        // A FAILURE AND NOT A SKIP. The path is compiled in. The file is either there or the
        // repository is not what this binary was built against. Printing a skip and returning zero
        // is how the natural field went ungraded without anybody being told.
        printf("\n  natural field absent at %s, FAILS\n", ANCHOR_SIFT_SOURCE_ROOT "/LICENSES/AGPL-3.0-or-later.txt");
        failed += 1;
    }

    printf("\n  %d check(s) failed\n", failed);
    free(corpus);
    return (failed == 0) ? 0 : 1;
}
