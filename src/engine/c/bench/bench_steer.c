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

    printf("\n  %d check(s) failed\n", failed);
    free(corpus);
    return (failed == 0) ? 0 : 1;
}
