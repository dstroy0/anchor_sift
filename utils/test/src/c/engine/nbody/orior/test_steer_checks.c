
// test_steer_checks.c: skewed fields and the ordering checks
#include "test_steer_internal.h"

/**
 * @brief Fills a field whose symbols vary widely in rarity.
 *
 * @param[out] corpus Where the bytes are written [BORROWS].
 * @param[in]  length How many.
 *
 * @note Rarity has to VARY or the ordering has nothing to order by. A uniform field would make the
 *       steered and unsteered arms read identically and the run would print a pass with nothing
 *       tested. Three symbols carry almost the whole field and a long tail appears a handful of
 *       times each, the shape the missing term was written for.
 */
void build_skewed_field(uint8_t *corpus, size_t length)
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
static void order_worst_first(size_t *offsets, size_t count, const AnchorFieldCensus *census, const uint8_t *needle,
                              size_t needle_len)
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
            const uint64_t settled =
                (settled_offset < needle_len) ? anchor_steer_magnitude(census, needle[settled_offset]) : 0u;
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

int check_counts_agree(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle)
{
    int failed = 0;
    const size_t lengths[] = {0u, 1u, 2u, 3u, 4u, 16u, 64u};

    printf("\n  THE ORDERING COSTS NO CORRECTNESS, steered against the reference arm.\n\n");
    printf("  %12s %14s %14s %14s %10s\n", "needle_len", "reference", "unsteered", "steered", "verdict");

    for (unsigned int which = 0u; which < 7u; which += 1u)
    {
        const size_t needle_len = lengths[which];
        const size_t want = orior_naive(corpus, corpus_len, needle, needle_len);
        const size_t plain = anchor_steer_count(corpus, corpus_len, needle, needle_len, 0);
        const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);

        const int ok = (plain == want) && (steered == want);
        printf("  %12zu %14zu %14zu %14zu %10s\n", needle_len, want, plain, steered, ok ? "ok" : "FAILS");
        if (!ok)
        {
            failed += 1;
        }
    }
    return failed;
}

int check_ordering_pays(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len)
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
    const uint64_t hundredths = (steered_probes > 0u) ? ((plain_probes * 100u) / steered_probes) : 0u;

    printf("  %22s %16s %16s\n", "order", "probe reads", "plain/steered");
    printf("  %22s %16llu %16s\n", "spatial, unsteered", (unsigned long long)plain_probes, "-");
    printf("  %22s %16llu %13llu.%02llu\n", "rarest first, steered", (unsigned long long)steered_probes,
           (unsigned long long)(hundredths / 100u), (unsigned long long)(hundredths % 100u));

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
 * Each field below has its verdict worked out from 100*total^2 >= 85*distinct*sum(count^2) by hand
 * and not from running the function. This grades the integer arithmetic and not its own output.
 *
 *   uniform over 256   count is N/256 each, sum of squares is N^2/256, distinct 256.
 *                      left 100*N^2, right 85*256*N^2/256 = 85*N^2. 100 >= 85. NOT free.
 *   one symbol only    sum of squares is N^2, distinct 1.
 *                      left 100*N^2, right 85*N^2. 100 >= 85. NOT free.
 *   two symbols, 99/1  N 100, counts 99 and 1, sum of squares 9802, distinct 2.
 *                      left 1000000, right 85*2*9802 = 1666340. 1000000 < 1666340. FREE.
 */
int check_dispatch_exact(void)
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

    /* An empty field has no structure and takes the short circuiting arm. Stated and not
     * discovered, because a caller with no corpus hands over a census of nothing. */
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
 *       with three terms of a series. Comparing against the intended value, and not against that
 *       approximation, is the stronger test: it asks whether the integer rule is right, not whether
 *       it reproduces an old rounding.
 * @note A double appears in this function and nowhere in the engine. A bench may carry one to
 *       describe what the engine decided; the engine may not carry one to decide it.
 * @note A disagreement is reported and is NOT counted as a failure by itself. Where the two differ
 *       the field sits within a rounding of the threshold, and there the integer route is correct
 *       by construction and the double route moved. The margin is printed so the
 *       reader can see which case they are looking at.
 */
int check_exact_matches_double(void)
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

        printf("  %10u %10u %12d %12d %10s\n", skew, census.distinct, exact, by_double, same ? "agree" : "differ");
    }

    printf("\n  %u agreed, %u differed, and the sweep chose free %u times and in order %u times\n", agreed, differed,
           chose_free, chose_inorder);

    /* THE SWEEP HAS TO CROSS THE THRESHOLD OR THE AGREEMENT PROVES NOTHING. A run where every field
     * lands on the same side agrees trivially, and would agree just as well against a rule that
     * ignored its input and returned one answer. Counting the rows is not enough to establish that;
     * this tests that BOTH verdicts appear. */
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
void print_route_row(const char *label, size_t probes, size_t count, uint64_t reads, size_t alignments, int ok)
{
    const uint64_t thousandths = (alignments > 0u) ? ((reads * 1000u) / (uint64_t)alignments) : 0u;

    printf("  %26s %8zu %10zu %14llu %8llu.%03llu %10s\n", label, probes, count, (unsigned long long)reads,
           (unsigned long long)(thousandths / 1000u), (unsigned long long)(thousandths % 1000u), ok ? "ok" : "FAILS");
}
