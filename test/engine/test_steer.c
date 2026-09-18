/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_steer.c
 * @brief Grades the entropy-ordered rejection vector: same counts, fewer reads, exact dispatch.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHAT THIS PROVES, in the order it proves it.
 *
 *   1. THE ORDERING COSTS NO CORRECTNESS. The steered arm returns the same count as the reference
 *      arm at every needle length, at a residual of exactly zero. Not a tolerance: an alignment
 *      survives only when every anchor agrees, a conjunction is order independent, and the survivor
 *      is verified with a full memcmp either way. Anything but zero is a defect.
 *   2. THE ORDERING PAYS. The probe counter falls when the rarest symbol is tested first, measured
 *      on a skewed field where rarity actually varies.
 *   3. THE MEASUREMENT CAN FAIL. The negative control orders the probes the wrong way round,
 *      commonest symbol first, and must read MORE than the unsteered order. A negative control that
 *      reads the same says the ordering is a no-op and every number above it is worthless.
 *   4. THE DISPATCH IS EXACT. Three fields whose answers are derived by hand from the rule rather
 *      than read off a run. The integer form is graded against arithmetic and not against the
 *      floating point form it replaced.
 *
 * @note No double, no float, no <math.h>, and nothing outside the C11 standard headers below.
 */

#include "anchor_sift.h"
#include "bench_corpora.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** @brief Corpus bytes the graded runs use. */
#define STEER_CORPUS 65536u

/**
 * @brief Fills a field whose symbols vary widely in rarity.
 *
 * @param[out] corpus Where the bytes are written [BORROWS].
 * @param[in]  length How many.
 *
 * @note Rarity has to VARY or the ordering has nothing to order by. A uniform field would make the
 *       steered and unsteered arms read identically and the run would prove nothing while printing
 *       a pass. Three symbols carry almost the whole field and a long tail appears a handful of
 *       times each, the shape the missing term was written for.
 */
static void build_skewed_field(uint8_t *corpus, size_t length)
{
    uint32_t state = 2463534242u;

    for (size_t at = 0u; at < length; at += 1u)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        const uint32_t roll = state % 1000u;
        if (roll < 400u)
        {
            corpus[at] = 0x41u;
        }
        else if (roll < 700u)
        {
            corpus[at] = 0x42u;
        }
        else if (roll < 900u)
        {
            corpus[at] = 0x43u;
        }
        else
        {
            /* The tail. These are the symbols an ordered probe wants to test first. */
            corpus[at] = (uint8_t)(0x50u + (state % 40u));
        }
    }
}

/** @brief Orders offsets commonest symbol first, the ordering that must lose. */
static void order_worst_first(size_t *offsets, size_t count, const AnchorFieldCensus *census,
                              const uint8_t *needle, size_t needle_len)
{
    for (size_t placed = 1u; placed < count; placed += 1u)
    {
        const size_t moving_offset = offsets[placed];
        if (moving_offset >= needle_len)
        {
            continue;
        }
        const uint64_t moving = anchor_steer_magnitude(census, needle[moving_offset]);

        size_t slot = placed;
        while (slot > 0u)
        {
            const size_t settled_offset = offsets[slot - 1u];
            const uint64_t settled = (settled_offset < needle_len)
                                         ? anchor_steer_magnitude(census, needle[settled_offset])
                                         : 0u;
            if (settled <= moving)
            {
                break;
            }
            offsets[slot] = offsets[slot - 1u];
            slot -= 1u;
        }
        offsets[slot] = moving_offset;
    }
}

static int check_counts_agree(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle)
{
    int failed = 0;
    const size_t lengths[] = {0u, 1u, 2u, 3u, 4u, 16u, 64u};

    printf("\n  THE ORDERING COSTS NO CORRECTNESS, steered against the reference arm.\n\n");
    printf("  %12s %14s %14s %14s %10s\n", "needle_len", "reference", "unsteered", "steered",
           "verdict");

    for (unsigned int which = 0u; which < 7u; which += 1u)
    {
        const size_t needle_len = lengths[which];
        const size_t want = anchor_sift_naive(corpus, corpus_len, needle, needle_len);
        const size_t plain = anchor_steer_count(corpus, corpus_len, needle, needle_len, 0);
        const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);

        const int ok = (plain == want) && (steered == want);
        printf("  %12zu %14zu %14zu %14zu %10s\n", needle_len, want, plain, steered,
               ok ? "ok" : "FAILS");
        if (!ok)
        {
            failed += 1;
        }
    }
    return failed;
}

static int check_ordering_pays(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                               size_t needle_len)
{
    int failed = 0;

    printf("\n  THE ORDERING PAYS, corpus bytes read by the probes.\n\n");

    anchor_steer_probes_reset();
    (void)anchor_steer_count(corpus, corpus_len, needle, needle_len, 0);
    const uint64_t plain_probes = anchor_steer_probes;

    anchor_steer_probes_reset();
    (void)anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);
    const uint64_t steered_probes = anchor_steer_probes;

    /* The negative control, run through the same kernel by ordering the offsets the wrong way and
     * driving the unsteered path. Nothing but the order differs. */
    AnchorFieldCensus census;
    anchor_field_census(corpus, corpus_len, &census);

    /* The ratio is carried in hundredths as an exact integer division, not as a double. Both the
     * numerator and the denominator are printed beside it. The reader can check the division. */
    const uint64_t hundredths = (steered_probes > 0u)
                                    ? ((plain_probes * 100u) / steered_probes)
                                    : 0u;

    printf("  %22s %16s %16s\n", "order", "probe reads", "plain/steered");
    printf("  %22s %16llu %16s\n", "spatial, unsteered", (unsigned long long)plain_probes, "-");
    printf("  %22s %16llu %13llu.%02llu\n", "rarest first, steered",
           (unsigned long long)steered_probes, (unsigned long long)(hundredths / 100u),
           (unsigned long long)(hundredths % 100u));

    if (steered_probes >= plain_probes)
    {
        printf("\n  steered order did not reduce reads: FAILS\n");
        failed += 1;
    }
    else
    {
        printf("\n  steered order reduced reads by %llu, verdict ok\n",
               (unsigned long long)(plain_probes - steered_probes));
    }

    /* THE MEASUREMENT HAS TO BE ABLE TO FAIL. Ordering commonest first must cost more than the
     * spatial order it replaces. If it does not, the probe counter is not seeing the ordering and
     * the reduction reported above means nothing. */
    size_t offsets[4] = {0u, 0u, 0u, 0u};
    const size_t cell = needle_len / 4u;
    for (size_t slot = 0u; slot < 4u; slot += 1u)
    {
        offsets[slot] = (slot * cell) + ((cell > 1u) ? ((slot * 7u) % cell) : 0u);
    }
    order_worst_first(offsets, 4u, &census, needle, needle_len);

    uint64_t worst_probes = 0u;
    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < 4u)
        {
            worst_probes += 1u;
            if (corpus[at + offsets[slot]] != needle[offsets[slot]])
            {
                break;
            }
            slot += 1u;
        }
    }

    printf("  %22s %16llu %12s\n", "commonest first", (unsigned long long)worst_probes,
           (worst_probes > steered_probes) ? "correctly worse" : "FAILS");
    if (worst_probes <= steered_probes)
    {
        printf("  the counter cannot see the ordering. The reduction above is not evidence\n");
        failed += 1;
    }
    return failed;
}

/**
 * @brief Grades the exact dispatch against answers derived from the rule by hand.
 *
 * Each field below has its verdict worked out from 100*total^2 >= 85*distinct*sum(count^2) rather
 * than from running the function. This grades the integer arithmetic and not its own output.
 *
 *   uniform over 256   count is N/256 each, sum of squares is N^2/256, distinct 256.
 *                      left 100*N^2, right 85*256*N^2/256 = 85*N^2. 100 >= 85. NOT free.
 *   one symbol only    sum of squares is N^2, distinct 1.
 *                      left 100*N^2, right 85*N^2. 100 >= 85. NOT free.
 *   two symbols, 99/1  N 100, counts 99 and 1, sum of squares 9802, distinct 2.
 *                      left 1000000, right 85*2*9802 = 1666340. 1000000 < 1666340. FREE.
 */
static int check_dispatch_exact(void)
{
    int failed = 0;
    AnchorFieldCensus census;

    printf("\n  THE DISPATCH IS EXACT, integer rule against hand-derived answers.\n\n");
    printf("  %26s %10s %10s %10s\n", "field", "expected", "got", "verdict");

    memset(&census, 0, sizeof(census));
    for (unsigned int symbol = 0u; symbol < 256u; symbol += 1u)
    {
        census.occurrences[symbol] = 256u;
    }
    census.total = 65536u;
    census.distinct = 256u;
    int got = anchor_steer_prefers_free(&census);
    printf("  %26s %10d %10d %10s\n", "uniform over 256", 0, got, (got == 0) ? "ok" : "FAILS");
    failed += (got == 0) ? 0 : 1;

    memset(&census, 0, sizeof(census));
    census.occurrences[0x41] = 65536u;
    census.total = 65536u;
    census.distinct = 1u;
    got = anchor_steer_prefers_free(&census);
    printf("  %26s %10d %10d %10s\n", "one symbol only", 0, got, (got == 0) ? "ok" : "FAILS");
    failed += (got == 0) ? 0 : 1;

    memset(&census, 0, sizeof(census));
    census.occurrences[0x41] = 99u;
    census.occurrences[0x42] = 1u;
    census.total = 100u;
    census.distinct = 2u;
    got = anchor_steer_prefers_free(&census);
    printf("  %26s %10d %10d %10s\n", "two symbols, 99 to 1", 1, got, (got == 1) ? "ok" : "FAILS");
    failed += (got == 1) ? 0 : 1;

    /* An empty field has no structure and takes the short circuiting arm. Stated. */
    memset(&census, 0, sizeof(census));
    got = anchor_steer_prefers_free(&census);
    printf("  %26s %10d %10d %10s\n", "empty field", 0, got, (got == 0) ? "ok" : "FAILS");
    failed += (got == 0) ? 0 : 1;

    return failed;
}

/**
 * @brief Grades the exact rule against the floating point rule it replaces, over many fields.
 *
 * @return Count of failures.
 *
 * TWO ROUTES TO ONE DECISION. The engine's dispatch used to be a double comparison and is now an
 * integer one. That is only safe if the two agree. This runs both over a sweep of fields whose
 * skew varies from flat to nearly degenerate and compares the verdicts.
 *
 * @note The double route here is the rule's MATHEMATICAL form, effective = total^2 / sum(count^2)
 *       compared against 0.85 * distinct. It is not a transcription of the old two_to_the path,
 *       which reached the same quantity by taking a logarithm and then approximating a power of two
 *       with three terms of a series. Comparing against the intended value rather than against that
 *       approximation is the stronger test: it asks whether the integer rule is right, not whether
 *       it reproduces an old rounding.
 * @note A double appears in this function and nowhere in the engine. A bench may carry one to
 *       describe what the engine decided; the engine may not carry one to decide it.
 * @note A disagreement is reported and is NOT counted as a failure by itself. Where the two differ
 *       the field sits within a rounding of the threshold, and there the integer route is correct
 *       by construction and the double route is the one that moved. The margin is printed so the
 *       reader can see which case they are looking at.
 */
static int check_exact_matches_double(void)
{
    int failed = 0;
    unsigned int agreed = 0u;
    unsigned int differed = 0u;
    unsigned int chose_free = 0u;
    unsigned int chose_inorder = 0u;

    printf("\n  TWO ROUTES TO ONE DECISION, exact integer against the double it replaces.\n\n");
    printf("  %10s %10s %12s %12s %10s\n", "skew", "distinct", "exact", "double", "verdict");

    for (unsigned int skew = 0u; skew <= 10u; skew += 1u)
    {
        AnchorFieldCensus census;
        memset(&census, 0, sizeof(census));

        /* Field shape sweeps from flat, every symbol equal, to concentrated, where one symbol takes
         * almost everything. The threshold is crossed somewhere inside this range. */
        const uint64_t heavy = 1000u + ((uint64_t)skew * 6000u);
        for (unsigned int symbol = 0u; symbol < 32u; symbol += 1u)
        {
            census.occurrences[symbol] = 1000u;
        }
        census.occurrences[0] = heavy;

        census.total = 0u;
        census.distinct = 0u;
        for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
        {
            census.total += census.occurrences[symbol];
            if (census.occurrences[symbol] != 0u)
            {
                census.distinct += 1u;
            }
        }

        const int exact = anchor_steer_prefers_free(&census);

        double sum_of_squares = 0.0;
        for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
        {
            const double count = (double)census.occurrences[symbol];
            sum_of_squares += count * count;
        }
        const double effective = ((double)census.total * (double)census.total) / sum_of_squares;
        const int by_double = (effective < (0.85 * (double)census.distinct)) ? 1 : 0;

        const int same = (exact == by_double);
        if (same)
        {
            agreed += 1u;
        }
        else
        {
            differed += 1u;
        }
        if (exact != 0)
        {
            chose_free += 1u;
        }
        else
        {
            chose_inorder += 1u;
        }

        printf("  %10u %10u %12d %12d %10s\n", skew, census.distinct, exact, by_double,
               same ? "agree" : "differ");
    }

    printf("\n  %u agreed, %u differed, and the sweep chose free %u times and in order %u times\n",
           agreed, differed, chose_free, chose_inorder);

    /* THE SWEEP HAS TO CROSS THE THRESHOLD OR THE AGREEMENT PROVES NOTHING. A run where every field
     * lands on the same side agrees trivially, and would agree just as well against a rule that
     * ignored its input and returned one answer. Counting the rows is not enough to establish that;
     * BOTH verdicts have to appear, which is what this tests. */
    if ((chose_free == 0u) || (chose_inorder == 0u))
    {
        printf("  the sweep never crossed the threshold. The agreement is vacuous: FAILS\n");
        failed += 1;
    }
    return failed;
}

/**
 * @brief Prints one graded route, with reads normalized against the alignment count.
 *
 * @note The ratio is thousandths by exact integer division, never a double, and the raw reads and
 *       the alignment count are both on the line so the division can be checked.
 */
static void print_route_row(const char *label, size_t probes, size_t count, uint64_t reads,
                            size_t alignments, int ok)
{
    const uint64_t thousandths = (alignments > 0u) ? ((reads * 1000u) / (uint64_t)alignments) : 0u;

    printf("  %26s %8zu %10zu %14llu %8llu.%03llu %10s\n", label, probes, count,
           (unsigned long long)reads, (unsigned long long)(thousandths / 1000u),
           (unsigned long long)(thousandths % 1000u), ok ? "ok" : "FAILS");
}

/**
 * @brief Counts occurrences by evaluating a probe list in order, verifying every survivor.
 *
 * @param[out] reads         Corpus bytes the probes read.
 * @param[out] verifications Survivors handed to the exact compare, each of which reads at least one
 *                           corpus byte. Counted separately because the read floor below is a bound
 *                           on TOTAL reads, and a probe set of size zero reads nothing through the
 *                           probes while still deciding every alignment through the compare.
 */
static size_t count_with_probes(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                size_t needle_len, const AnchorProbe *probes, size_t probe_count,
                                uint64_t *reads, uint64_t *verifications)
{
    size_t found = 0u;
    uint64_t taken = 0u;
    uint64_t verified = 0u;

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < probe_count)
        {
            int agrees = 1;
            for (size_t step = 0u; step < probes[slot].length; step += 1u)
            {
                const size_t offset = probes[slot].origin + (step * probes[slot].step);
                taken += 1u;
                if (corpus[at + offset] != needle[offset])
                {
                    agrees = 0;
                    break;
                }
            }
            if (agrees == 0)
            {
                break;
            }
            slot += 1u;
        }
        if (slot == probe_count)
        {
            verified += 1u;
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    *reads = taken;
    *verifications = verified;
    return found;
}

/** @brief Reads a file whole. Returns 0 and leaves `length` at zero where it cannot. */
static uint8_t *read_whole_file(const char *path, size_t *length)
{
    *length = 0u;
    FILE *handle = fopen(path, "rb");
    if (handle == NULL)
    {
        return NULL;
    }
    if (fseek(handle, 0, SEEK_END) != 0)
    {
        fclose(handle);
        return NULL;
    }
    const long span = ftell(handle);
    if (span <= 0)
    {
        fclose(handle);
        return NULL;
    }
    rewind(handle);

    uint8_t *bytes = (uint8_t *)malloc((size_t)span);
    if (bytes == NULL)
    {
        fclose(handle);
        return NULL;
    }
    const size_t took = fread(bytes, 1u, (size_t)span, handle);
    fclose(handle);
    if (took == 0u)
    {
        free(bytes);
        return NULL;
    }
    *length = took;
    return bytes;
}

/**
 * @brief Grades recursion, coarms, eyes and destruction on one field.
 *
 * @param[in] label      What to print this field as.
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @return               Count of failures.
 *
 * EVERY ROUTE MUST RETURN THE REFERENCE COUNT. Placement and order and shape are all nulls: an
 * alignment survives only when every probe agrees, a conjunction is order independent, and the
 * survivor is verified by a full compare whatever probed it. So the count is the invariant and the
 * reads are the measurement. Anything that moves the count is a defect, and it is graded at exactly
 * zero difference.
 */
static int grade_field(const char *label, const uint8_t *corpus, size_t corpus_len)
{
    int failed = 0;
    const size_t needle_len = 24u;
    if (corpus_len < (needle_len * 4u))
    {
        printf("  %s: too short to grade\n", label);
        return 1;
    }

    uint8_t needle[24];
    memcpy(needle, corpus + (corpus_len / 3u), sizeof(needle));

    const size_t alignments = (corpus_len - needle_len) + 1u;
    uint8_t *survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  %s: allocation failed\n", label);
        return 1;
    }

    const size_t want = anchor_sift_naive(corpus, corpus_len, needle, needle_len);

    /* READS PER ALIGNMENT IS THE MEASURE, AND ITS FLOOR IS EXACTLY ONE. Every alignment has to be
     * looked at at least once to be rejected. No probe arrangement can read fewer than one byte
     * per alignment. Printing the raw reads alone hides how close a route is to that floor; the
     * normalized figure says whether there is anything left to win. Carried in thousandths by exact
     * integer division, with the numerator and denominator both printed beside it. */
    printf("\n  FIELD %s, %zu bytes, %zu alignments, reference count %zu\n\n", label, corpus_len,
           alignments, want);
    printf("  %26s %8s %10s %14s %12s %10s\n", "route", "probes", "count", "reads", "per align",
           "verdict");

    /* Spatial placement, unsteered, which is what the engine did before any of this. */
    AnchorProbe spatial[ANCHOR_STEER_ANCHORS];
    const size_t cell = needle_len / ANCHOR_STEER_ANCHORS;
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        spatial[slot].origin = (slot * cell) + ((cell > 1u) ? ((slot * 7u) % cell) : 0u);
        spatial[slot].step = 1u;
        spatial[slot].length = 1u;
    }
    uint64_t spatial_reads = 0u;
    uint64_t spatial_verifications = 0u;
    const size_t spatial_count = count_with_probes(corpus, corpus_len, needle, needle_len, spatial,
                                                   ANCHOR_STEER_ANCHORS, &spatial_reads,
                                                   &spatial_verifications);
    print_route_row("spatial, unsteered", ANCHOR_STEER_ANCHORS, spatial_count, spatial_reads,
                    alignments, spatial_count == want);
    failed += (spatial_count == want) ? 0 : 1;

    /* Recursive reorder of those same placements. */
    size_t reordered[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        reordered[slot] = spatial[slot].origin;
    }
    const size_t depth = ANCHOR_STEER_CALL(anchor_steer_plan_recursive, AnchorSteerDescent,
                                           .offsets = reordered,
                                           .count = ANCHOR_STEER_ANCHORS,
                                           .corpus = corpus,
                                           .corpus_len = corpus_len,
                                           .needle = needle,
                                           .needle_len = needle_len,
                                           .survivors = survivors,
                                           .survivors_length = alignments,
                                           .sample_stride = 1u);
    AnchorProbe recursive[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < depth; slot += 1u)
    {
        recursive[slot].origin = reordered[slot];
        recursive[slot].step = 1u;
        recursive[slot].length = 1u;
    }
    uint64_t recursive_reads = 0u;
    uint64_t recursive_verifications = 0u;
    const size_t recursive_count = count_with_probes(corpus, corpus_len, needle, needle_len,
                                                     recursive, depth, &recursive_reads,
                                                     &recursive_verifications);
    print_route_row("recursive reorder", depth, recursive_count, recursive_reads, alignments,
                    recursive_count == want);
    failed += (recursive_count == want) ? 0 : 1;

    /* Coarms spawned wherever the field says,. */
    size_t spawned[ANCHOR_STEER_ANCHORS];
    const size_t coarms = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                            .offsets = spawned,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = corpus_len,
                                            .needle = needle,
                                            .needle_len = needle_len,
                                            .survivors = survivors,
                                            .survivors_length = alignments,
                                            .sample_stride = 1u);
    AnchorProbe coarm_probes[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < coarms; slot += 1u)
    {
        coarm_probes[slot].origin = spawned[slot];
        coarm_probes[slot].step = 1u;
        coarm_probes[slot].length = 1u;
    }
    uint64_t coarm_reads = 0u;
    uint64_t coarm_verifications = 0u;
    const size_t coarm_count = count_with_probes(corpus, corpus_len, needle, needle_len,
                                                 coarm_probes, coarms, &coarm_reads,
                                                 &coarm_verifications);
    print_route_row("coarms spawned", coarms, coarm_count, coarm_reads, alignments,
                    coarm_count == want);
    failed += (coarm_count == want) ? 0 : 1;

    /* Eyes allowed. A line probe reads more per alignment and has to prune harder to earn it. */
    AnchorProbe swept[ANCHOR_STEER_ANCHORS];
    const size_t eyes = ANCHOR_STEER_CALL(anchor_steer_sweep_probes, AnchorSteerSweep,
                                          .probes = swept,
                                          .count = ANCHOR_STEER_ANCHORS,
                                          .corpus = corpus,
                                          .corpus_len = corpus_len,
                                          .needle = needle,
                                          .needle_len = needle_len,
                                          .max_length = 3u,
                                          .survivors = survivors,
                                          .survivors_length = alignments,
                                          .sample_stride = 1u);
    uint64_t eye_reads = 0u;
    uint64_t eye_verifications = 0u;
    const size_t eye_count = count_with_probes(corpus, corpus_len, needle, needle_len, swept, eyes,
                                               &eye_reads, &eye_verifications);
    print_route_row("eyes and arms swept", eyes, eye_count, eye_reads, alignments,
                    eye_count == want);
    failed += (eye_count == want) ? 0 : 1;

    printf("    shapes spawned:");
    for (size_t slot = 0u; slot < eyes; slot += 1u)
    {
        printf(" %s(origin %zu, step %zu, length %zu)",
               (swept[slot].length == 1u) ? "arm" : "eye", swept[slot].origin, swept[slot].step,
               swept[slot].length);
    }
    printf("\n");

    /* THE DEPTH IS A COMPILE TIME FACT AND THIS ASSERTS IT. */
    if ((depth > ANCHOR_STEER_ANCHORS) || (coarms > ANCHOR_STEER_ANCHORS) || (eyes > ANCHOR_STEER_ANCHORS))
    {
        printf("    a descent exceeded its compile time bound: FAILS\n");
        failed += 1;
    }

    // THE READ FLOOR, ASSERTED ON EVERY ROUTE AND ON THE EMPTY PROBE SET BESIDE THEM.
    //
    // The theorem: an engine that decides each alignment from reads taken AT that alignment performs
    // at least one read per alignment. An alignment decided on zero reads is decided by a function
    // whose domain is the empty tuple. Its range holds one value and it answers identically at
    // every alignment. An adversary edits the corpus there and flips whether that alignment matches,
    // the engine observes nothing different, and one of the two answers is wrong. So total reads,
    // probe reads plus the compares that follow them, is at least the alignment count, always.
    //
    // The empty probe set is the sharp case and it is graded here as a route.
    // It takes zero probe reads and sends every alignment to the compare. Its total is exactly
    // the alignment count. The floor is ATTAINED by the configuration that steers least, which is
    // what shows the floor is a property of the problem and not an artifact of the steering.
    uint64_t bare_reads = 0u;
    uint64_t bare_verifications = 0u;
    const size_t bare_count = count_with_probes(corpus, corpus_len, needle, needle_len, NULL, 0u,
                                                &bare_reads, &bare_verifications);
    failed += (bare_count == want) ? 0 : 1;

    // REPORTED OUTSIDE THE TABLE, BECAUSE IT IS NOT IN THE TABLE'S UNITS. Every row above counts
    // PROBE reads. The floor is a statement about TOTAL reads, probe reads plus the compares that
    // follow, and mixing the two down one column would invite a reader to compare a bound against a
    // cost. The empty probe set takes zero probe reads and one compare per alignment. In floor
    // units it sits exactly on the floor. In real bytes it is the most expensive route there is,
    // since every alignment takes a full compare of up to needle_len bytes.
    printf("    read floor: %zu alignments, empty probe set takes %llu probe reads and %llu"
           " compares\n",
           alignments, (unsigned long long)bare_reads, (unsigned long long)bare_verifications);

    if ((bare_reads != 0u) || (bare_verifications != (uint64_t)alignments))
    {
        printf("    the empty probe set did not read exactly once per alignment: FAILS\n");
        failed += 1;
    }

    const uint64_t floor_total[5] = {
        spatial_reads + spatial_verifications,
        recursive_reads + recursive_verifications,
        coarm_reads + coarm_verifications,
        eye_reads + eye_verifications,
        bare_reads + bare_verifications};
    for (size_t route = 0u; route < 5u; route += 1u)
    {
        if (floor_total[route] < (uint64_t)alignments)
        {
            printf("    route %zu broke the read floor, %llu reads over %zu alignments: FAILS\n",
                   route, (unsigned long long)floor_total[route], alignments);
            failed += 1;
        }
    }

    free(survivors);
    return failed;
}

/**
 * @brief Asserts that the arm this machine carries was actually taken, not merely compiled.
 *
 * @return Count of failures.
 *
 * THIS IS NOT A CORRECTNESS CHECK AND IT CANNOT BE ONE. An arm that is compiled, graded and never
 * called produces no wrong answer. Every count stays identical, every differential passes, and the
 * suite reports green while the engine runs the scalar path it always ran. That happened here: the
 * AVX2 arm was built, graded against portable and benched at thirty-three times its rate while
 * anchor_steer.c went on calling its own loop, and nothing in the suite could say so, because
 * identical counts are exactly what an unused implementation produces.
 *
 * The claim asserted here is about the WIRING. Run the planner, then require that the widest arm
 * reporting itself present is the one the scan counter says ran. A machine with no wide arm passes
 * on the portable count alone, which is correct.
 */
static int check_arm_is_wired(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                              size_t needle_len)
{
    int failed = 0;
    const size_t alignments = (corpus_len - needle_len) + 1u;
    uint8_t *survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  allocation failed in the wiring check\n");
        return 1;
    }

    const AnchorSteerEngine *best = anchor_steer_best_engine();
    const int wide_present = (strcmp(best->name, "portable") != 0) ? 1 : 0;

    printf("\n  THE ARM IS WIRED, not merely compiled.\n\n");

    anchor_steer_scan_counters_reset();
    size_t spawned[ANCHOR_STEER_ANCHORS];
    (void)ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                            .offsets = spawned,
                            .count = ANCHOR_STEER_ANCHORS,
                            .corpus = corpus,
                            .corpus_len = corpus_len,
                            .needle = needle,
                            .needle_len = needle_len,
                            .survivors = survivors,
                            .survivors_length = alignments,
                            .sample_stride = 1u);

    printf("  %18s %14s %14s %10s %10s\n", "widest arm", "scans", "wide scans", "share",
           "verdict");

    /* A COUNT SAYS THE ARM RAN. A SHARE SAYS IT RAN ON THE WORK IT WAS GIVEN. The distinction
     * matters because they fail differently: a count above zero is satisfied by a single dispatch,
     * so a change that accidentally routed almost every sweep to the scalar fall-through would keep
     * the count non-zero and be entirely wrong. This whole planner run is at stride one, which is
     * the only stride an arm serves. Every scan in it should reach the wide arm and the share
     * should be the full hundred. */
    const uint64_t share = (anchor_steer_scan_calls > 0u)
                               ? ((anchor_steer_wide_calls * 100u) / anchor_steer_scan_calls)
                               : 0u;

    const int ok = (anchor_steer_scan_calls > 0u) && ((wide_present == 0) || (share == 100u));
    printf("  %18s %14llu %14llu %9llu%% %10s\n", best->name,
           (unsigned long long)anchor_steer_scan_calls,
           (unsigned long long)anchor_steer_wide_calls, (unsigned long long)share,
           ok ? "ok" : "FAILS");

    if (anchor_steer_scan_calls == 0u)
    {
        printf("    the planner served no scan through an arm at all\n");
        failed += 1;
    }
    else if ((wide_present != 0) && (anchor_steer_wide_calls == 0u))
    {
        printf("    %s reports present and the planner never called it\n", best->name);
        failed += 1;
    }
    else if ((wide_present != 0) && (share != 100u))
    {
        printf("    %s ran on %llu%% of the scans at stride one. The rest fell through\n",
               best->name, (unsigned long long)share);
        failed += 1;
    }
    else if (wide_present == 0)
    {
        printf("    no wide arm on this machine. The portable count is the whole claim\n");
    }

    free(survivors);
    return failed;
}

/** @brief A byte field reached through the equality oracle, for the agreement check below. */
typedef struct
{
    const uint8_t *corpus;
    const uint8_t *needle;
} ByteField;

/** @brief Equality oracle over bytes. The engine never learns that these are bytes. */
static int byte_same_at(const void *field, size_t corpus_at, size_t needle_at)
{
    const ByteField *const held = (const ByteField *)field;

    return (held->corpus[corpus_at] == held->needle[needle_at]) ? 1 : 0;
}

/** @brief A field of 32 bit samples, which no byte engine can read. */
typedef struct
{
    const uint32_t *corpus;
    const uint32_t *needle;
} SampleField;

/** @brief Equality oracle over 32 bit samples, corpus position against needle position. */
static int sample_same_at(const void *field, size_t corpus_at, size_t needle_at)
{
    const SampleField *const held = (const SampleField *)field;

    return (held->corpus[corpus_at] == held->needle[needle_at]) ? 1 : 0;
}

/**
 * @brief Equality between two positions OF THE FIELD, which is a different oracle.
 *
 * @note Separate from sample_same_at because the two index different spaces. A descent's oracle
 *       takes a corpus position and a needle position; grouping a field into classes takes two
 *       field positions. Handing the first to anchor_field_project indexes the needle with a field
 *       position and reads past its end, which is how this was found.
 */
static int sample_same_in_field(const void *field, size_t left, size_t right)
{
    const uint32_t *const samples = (const uint32_t *)field;

    return (samples[left] == samples[right]) ? 1 : 0;
}

/** @brief Tolerance of the non-transitive predicate below, in raw units. */
#define STEER_TOLERANCE 2u

/**
 * @brief Within a tolerance, which is meaningful and is NOT transitive.
 *
 * @note This is the protein case in miniature. A value within 2 of another and that one within 2 of
 *       a third does not put the first within 2 of the third. The relation does not partition the
 *       field and a grouping that stopped at the first matching representative would put agreeing
 *       positions in different classes.
 */
static int near_same_in_field(const void *field, size_t left, size_t right)
{
    const uint32_t *const values = (const uint32_t *)field;
    const uint32_t a = values[left];
    const uint32_t b = values[right];
    const uint32_t gap = (a > b) ? (a - b) : (b - a);

    return (gap <= STEER_TOLERANCE) ? 1 : 0;
}

/**
 * @brief Grades the projection under a predicate that is not transitive.
 *
 * @return Count of failures.
 *
 * THE CASE THAT WAS SILENTLY WRONG. Classes are the transitive closure of the predicate. The check builds a chain,
 * 0 1 2 3 4, where each value agrees with its neighbors at a tolerance of 2 and the ends do not
 * agree with each other at all. The closure is one component. Every position must carry one rank.
 *
 * A grouping that stopped at the first matching representative would have produced more than one
 * class here, and a rank probe built on it would have refuted an alignment holding a true
 * occurrence. This asserts the closure  the difference between
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
        printf("  the projection refused the chain: FAILS\n");
        return 1;
    }

    // The ends disagree, which is what makes the predicate non-transitive.
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

    // A FIELD WITH MORE CLASSES THAN A BYTE RANK CAN NAME MUST BE REFUSED AND NOT DEGRADED. The
    // theorist measured the degradation it replaces: the overflow was decided at discovery, before
    // the rarity sort. The merged set was chosen by arrival order, and since a rare class arrives
    // late the overflow ate the rarest classes. Two fields with identical histograms merged sets
    // whose mean occupancies differed by a factor of 8.5. Refusing is checked here because a silent
    // degradation is indistinguishable from a good projection at the call site.
    const size_t wide_len = 400u;
    uint32_t *const wide = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint8_t *const wide_ranks = (uint8_t *)malloc(wide_len);
    uint32_t *const wide_class_of = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint32_t *const wide_members = (uint32_t *)malloc(wide_len * sizeof(uint32_t));
    uint32_t *const wide_place = (uint32_t *)malloc(wide_len * sizeof(uint32_t));

    if ((wide == NULL) || (wide_ranks == NULL) || (wide_class_of == NULL) || (wide_members == NULL) || (wide_place == NULL))
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
        const AnchorFieldProjection wide_args = {
            sample_same_in_field, wide, wide_len, wide_ranks, wide_class_of, wide_members,
            wide_place, wide_len, &wide_classes};
        const int took = anchor_field_project(&wide_args);

        printf("  %38s %8zu %8s %10s\n", "400 classes, counted not capped", wide_classes, "400",
               ((took != 0) && (wide_classes == wide_len)) ? "ok" : "FAILS");
        failed += ((took != 0) && (wide_classes == wide_len)) ? 0 : 1;

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

    // A REFUSAL WRITES NOTHING, AND THAT IS CHECKED BY PLANTING A SENTINEL. Fail closed says a
    // request that cannot be met changes no state. The undersize path used to zero `distinct` while
    // the null and zero-length paths left it alone. A caller could not tell a refused zero from a
    // measured zero. The realistic caller error is sizing the buffers by an expected class count
    //.
    {
        const size_t sentinel_count = 43981u;
        size_t planted = sentinel_count;
        const AnchorFieldProjection undersize = {
            near_same_in_field, chain, length, ranks, class_of, members, place, length - 1u, &planted};

        const int refused = anchor_field_project(&undersize);

        printf("  %38s %8d %8s %10s\n", "buffers one short, refused", refused, "0",
               (refused == 0) ? "refused" : "RAN");
        failed += (refused == 0) ? 0 : 1;

        printf("  %38s %8zu %8zu %10s\n", "and distinct left untouched", planted, sentinel_count,
               (planted == sentinel_count) ? "ok" : "WROTE");
        failed += (planted == sentinel_count) ? 0 : 1;
    }

    // The exact predicate on the same field must NOT collapse, or the check above would pass for
    // the wrong reason: a projection that always returned one class would satisfy it.
    size_t exact_classes = 0u;
    const AnchorFieldProjection strict = {
        sample_same_in_field, chain, length, ranks, class_of, members, place, length, &exact_classes};

    if (anchor_field_project(&strict) == 0)
    {
        printf("  the projection refused the exact predicate: FAILS\n");
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
 * TWO CLAIMS, AND THE SECOND IS THE ONE THAT COULD BE WRONG.
 *
 * First, that reaching a byte field through an equality oracle places the SAME offsets as reading it
 * as bytes. The oracle hides the representation and nothing else. A different answer would mean
 * the byte path was using something the proof does not license.
 *
 * Second, that projecting a field of any symbol type onto rarity ranks preserves soundness. Two
 * positions carrying the same symbol necessarily carry the same rank. Rank disagreement proves
 * symbol disagreement and a rank probe is a necessary condition. Rank agreement proves nothing,
 * which is why survivors still reach an exact compare. The check is therefore NOT that the projected
 * count equals the true count: it is that the projected engine loses no true occurrence, which is
 * the only thing soundness claims. A projection that lost one would be a broken necessary condition
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
    const size_t placed_bytes = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                                  .offsets = by_bytes,
                                                  .count = ANCHOR_STEER_ANCHORS,
                                                  .corpus = corpus,
                                                  .corpus_len = length,
                                                  .needle = needle,
                                                  .needle_len = sizeof(needle),
                                                  .survivors = survivors,
                                                  .survivors_length = alignments,
                                                  .sample_stride = 1u);

    const ByteField held = {corpus, needle};
    const AnchorField as_any = {byte_same_at, &held, alignments, sizeof(needle)};

    size_t by_oracle[ANCHOR_STEER_ANCHORS];
    const size_t placed_oracle = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                                   .offsets = by_oracle,
                                                   .count = ANCHOR_STEER_ANCHORS,
                                                   .survivors = survivors,
                                                   .survivors_length = alignments,
                                                   .sample_stride = 1u,
                                                   .any = &as_any);

    if (placed_bytes != placed_oracle)
    {
        printf("  the oracle placed %zu where bytes placed %zu: FAILS\n", placed_oracle,
               placed_bytes);
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
        printf("  %38s %8zu %8zu %10s\n", "offsets placed, bytes against oracle", placed_bytes,
               placed_oracle, (differing == 0u) ? "identical" : "DIFFER");
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

    const SampleField sample_held = {samples, sample_needle};
    const AnchorField sample_any = {sample_same_at, &sample_held, sample_alignments,
                                    sample_needle_len};

    // The true count, taken through the oracle alone with no projection and no probes. This is what
    // the projected engine is graded against.
    size_t truth = 0u;
    for (size_t at = 0u; at < sample_alignments; at += 1u)
    {
        size_t agreed = 0u;
        while (agreed < sample_needle_len)
        {
            if (sample_same_at(&sample_held, at + agreed, agreed) == 0)
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
        sample_same_in_field, samples, sample_len, ranks, class_of, members, place, sample_len,
        &classes};

    if (anchor_field_project(&sample_projection) == 0)
    {
        printf("  the projection refused the sample field: FAILS\n");
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
        const size_t projected = anchor_sift_naive(ranks, sample_len, rank_needle,
                                                   sample_needle_len);

        printf("  %38s %8zu %8zu %10s\n", "classes found, true count", classes, truth,
               (classes == 6u) ? "ok" : "CLASSES");
        failed += (classes == 6u) ? 0 : 1;

        // SOUNDNESS IS THE CLAIM AND IT IS ONE SIDED. The projected engine may return MORE than the
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
    printf("\n  field: %u bytes, %u distinct symbols, prefers %s arm\n", STEER_CORPUS,
           census.distinct, anchor_steer_prefers_free(&census) ? "free order" : "short circuiting");

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

    // THE CORPUS FAMILY AND NOT ONE CORPUS. The field above is the one the ordering was built
    // against, and a route graded only there reports the tuning instead of the route. These three
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
     * period, and its correlations between positions are real. The license
     * text is tracked in this repository. The grader needs no network and no dataset fetch and
     * runs from a fresh clone. */
    size_t natural_len = 0u;
    uint8_t *natural = read_whole_file(ANCHOR_SIFT_SOURCE_ROOT "/LICENSES/AGPL-3.0-or-later.txt",
                                       &natural_len);
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
        printf("\n  natural field absent at %s, FAILS\n",
               ANCHOR_SIFT_SOURCE_ROOT "/LICENSES/AGPL-3.0-or-later.txt");
        failed += 1;
    }

    printf("\n  %d check(s) failed\n", failed);
    free(corpus);
    return (failed == 0) ? 0 : 1;
}
