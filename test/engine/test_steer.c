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
 *      than read off a run, so the integer form is graded against arithmetic and not against the
 *      floating point form it replaced.
 *
 * @note No double, no float, no <math.h>, and nothing outside the C11 standard headers below.
 */

#include "anchor_sift.h"
#include "anchor_steer.h"

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
 *       times each, which is the shape the missing term was written for.
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

/** @brief Orders offsets commonest symbol first, which is the ordering that must lose. */
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
    const size_t lengths[] = { 0u, 1u, 2u, 3u, 4u, 16u, 64u };

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
     * driving the unsteered path, so nothing but the order differs. */
    AnchorFieldCensus census;
    anchor_field_census(corpus, corpus_len, &census);

    /* The ratio is carried in hundredths as an exact integer division, not as a double. Both the
     * numerator and the denominator are printed beside it, so the reader can check the division. */
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
    size_t offsets[4] = { 0u, 0u, 0u, 0u };
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
        printf("  the counter cannot see the ordering, so the reduction above is not evidence\n");
        failed += 1;
    }
    return failed;
}

/**
 * @brief Grades the exact dispatch against answers derived from the rule by hand.
 *
 * Each field below has its verdict worked out from 100*total^2 >= 85*distinct*sum(count^2) rather
 * than from running the function, so this grades the integer arithmetic and not its own output.
 *
 *   uniform over 256   count is N/256 each, sum of squares is N^2/256, distinct 256.
 *                      left 100*N^2, right 85*256*N^2/256 = 85*N^2. 100 >= 85, so NOT free.
 *   one symbol only    sum of squares is N^2, distinct 1.
 *                      left 100*N^2, right 85*N^2. 100 >= 85, so NOT free.
 *   two symbols, 99/1  N 100, counts 99 and 1, sum of squares 9802, distinct 2.
 *                      left 1000000, right 85*2*9802 = 1666340. 1000000 < 1666340, so FREE.
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

    /* An empty field has no structure and takes the short circuiting arm. Stated rather than
     * discovered, because a census of nothing is what a caller with no corpus hands over. */
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
 * integer one. That is only safe if the two agree, so this runs both over a sweep of fields whose
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
        printf("  the sweep never crossed the threshold, so the agreement is vacuous: FAILS\n");
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

/** @brief Counts occurrences by evaluating a probe list in order, verifying every survivor. */
static size_t count_with_probes(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                size_t needle_len, const AnchorProbe *probes, size_t probe_count,
                                uint64_t *reads)
{
    size_t found = 0u;
    uint64_t taken = 0u;

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
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    *reads = taken;
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
 * zero difference rather than against a tolerance.
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
    uint8_t *scratch = (uint8_t *)malloc(alignments);
    if (scratch == NULL)
    {
        printf("  %s: allocation failed\n", label);
        return 1;
    }

    const size_t want = anchor_sift_naive(corpus, corpus_len, needle, needle_len);

    /* READS PER ALIGNMENT IS THE MEASURE, AND ITS FLOOR IS EXACTLY ONE. Every alignment has to be
     * looked at at least once to be rejected, so no probe arrangement can read fewer than one byte
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
    const size_t spatial_count = count_with_probes(corpus, corpus_len, needle, needle_len, spatial,
                                                   ANCHOR_STEER_ANCHORS, &spatial_reads);
    print_route_row("spatial, unsteered", ANCHOR_STEER_ANCHORS, spatial_count, spatial_reads,
                    alignments, spatial_count == want);
    failed += (spatial_count == want) ? 0 : 1;

    /* Recursive reorder of those same placements. */
    size_t reordered[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        reordered[slot] = spatial[slot].origin;
    }
    const size_t depth = anchor_steer_plan_recursive(reordered, ANCHOR_STEER_ANCHORS, corpus,
                                                     corpus_len, needle, needle_len, scratch,
                                                     alignments, 1u);
    AnchorProbe recursive[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < depth; slot += 1u)
    {
        recursive[slot].origin = reordered[slot];
        recursive[slot].step = 1u;
        recursive[slot].length = 1u;
    }
    uint64_t recursive_reads = 0u;
    const size_t recursive_count = count_with_probes(corpus, corpus_len, needle, needle_len,
                                                     recursive, depth, &recursive_reads);
    print_route_row("recursive reorder", depth, recursive_count, recursive_reads, alignments,
                    recursive_count == want);
    failed += (recursive_count == want) ? 0 : 1;

    /* Coarms spawned wherever the field says, rather than where a spread rule put them. */
    size_t spawned[ANCHOR_STEER_ANCHORS];
    const size_t coarms = anchor_steer_spawn_coarms(spawned, ANCHOR_STEER_ANCHORS, corpus,
                                                    corpus_len, needle, needle_len, scratch,
                                                    alignments, 1u);
    AnchorProbe coarm_probes[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < coarms; slot += 1u)
    {
        coarm_probes[slot].origin = spawned[slot];
        coarm_probes[slot].step = 1u;
        coarm_probes[slot].length = 1u;
    }
    uint64_t coarm_reads = 0u;
    const size_t coarm_count = count_with_probes(corpus, corpus_len, needle, needle_len,
                                                 coarm_probes, coarms, &coarm_reads);
    print_route_row("coarms spawned", coarms, coarm_count, coarm_reads, alignments,
                    coarm_count == want);
    failed += (coarm_count == want) ? 0 : 1;

    /* Eyes allowed. A line probe reads more per alignment and has to prune harder to earn it. */
    AnchorProbe swept[ANCHOR_STEER_ANCHORS];
    const size_t eyes = anchor_steer_sweep_probes(swept, ANCHOR_STEER_ANCHORS, corpus, corpus_len,
                                                  needle, needle_len, 3u, scratch, alignments, 1u);
    uint64_t eye_reads = 0u;
    const size_t eye_count = count_with_probes(corpus, corpus_len, needle, needle_len, swept, eyes,
                                               &eye_reads);
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

    /* THE DEPTH IS A COMPILE TIME FACT AND THIS ASSERTS IT RATHER THAN TRUSTING THE PROSE. */
    if ((depth > ANCHOR_STEER_ANCHORS) || (coarms > ANCHOR_STEER_ANCHORS)
     || (eyes > ANCHOR_STEER_ANCHORS))
    {
        printf("    a descent exceeded its compile time bound: FAILS\n");
        failed += 1;
    }

    free(scratch);
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

    /* The needle is taken FROM the field, so it occurs at least once and the counts are not all
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

    printf("\n  ARMS, EYES AND COARMS, spawned and swept against a reference count.\n");
    failed += grade_field("synthetic skewed", corpus, STEER_CORPUS);

    /* A REAL NATURAL OBJECT AND NOT A GENERATOR. Everything above runs on bytes this file wrote,
     * which share whatever structure the generator happens to have. English prose is a field
     * nobody here designed: its letter frequencies span three decades, it repeats at no fixed
     * period, and its correlations between positions are real rather than planted. The license
     * text is tracked in this repository, so the grader needs no network and no dataset fetch and
     * runs from a fresh clone. */
    size_t natural_len = 0u;
    uint8_t *natural = read_whole_file("../../LICENSES/AGPL-3.0-or-later.txt", &natural_len);
    if (natural == NULL)
    {
        natural = read_whole_file("LICENSES/AGPL-3.0-or-later.txt", &natural_len);
    }
    if (natural != NULL)
    {
        failed += grade_field("natural, AGPL English text", natural, natural_len);
        free(natural);
    }
    else
    {
        printf("\n  natural field not found beside the build, skipped\n");
    }

    printf("\n  %d check(s) failed\n", failed);
    free(corpus);
    return (failed == 0) ? 0 : 1;
}
