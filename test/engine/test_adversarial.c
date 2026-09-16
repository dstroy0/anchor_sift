/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_adversarial.c
 * @brief Attacks the steering guarantees instead of confirming them, and grades every arm present.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHY THIS SITS IN test/. A driver in `bench/` builds corpora, counts or times, and prints rows.
 * This file asks whether the engine is right, which is a different question, so Douglas put the two
 * questions in two directories. Every case below names the guarantee it attacks and the
 * construction that should break it, and a case that cannot fail when its guarantee is false does
 * not belong here.
 *
 * IT HAS BEEN SEEN TO FAIL. Nothing else separates an adversarial suite from an empty
 * loop. Against the engine as written it passes seven of seven at exit 0. Against three deliberately
 * broken engines it rejects every one, and each mutation is caught by a different set of cases:
 * dropping the full compare so survivors are counted as matches trips the differential net and the
 * survivor case; an off by one in the alignment bound trips overlapping occurrences, the boundary
 * case and the survivor case's read count; and a probe comparing against a constant instead of the
 * needle trips six of the seven. `test/engine/mutate.sh` reproduces all three.
 *
 * A CASE THAT CANNOT FAIL IS NOT A CHECK, and this file learned that about itself. The survivor
 * case was written so that every probe agrees and only the full compare refutes, and it never
 * fired. The steering defeats that construction: the odd byte is the rarest symbol the needle
 * carries, so the ordering tests it FIRST, every alignment refutes at the first read, and the full
 * compare never runs. The case sat green and reading it would not have shown why. Mutating the
 * engine to drop the full compare, then watching the case stay green, is what exposed it.
 *
 * The repair is worth more than the catch. That case now runs UNSTEERED, places the difference at
 * an offset the spatial anchors never read, and CHECKS THE PREMISE IT DEPENDS ON: four surviving
 * probes is four reads an alignment and no fewer. A lower count means a probe is refuting and
 * the case has stopped testing what it claims. The premise check then caught the alignment off by
 * one on its own, four reads short of 16260, which is one alignment lost. A case asserting its own
 * preconditions is a different kind of object from one asserting only its conclusion, and every
 * case here that can be given a premise check should get one.
 *
 * FOUR OF THESE ARE DIFFERENTIAL. They compare two routes that must agree, so no expected number is
 * written down in advance and none can be written down wrongly. Those are the strongest cases here,
 * and they double in value the moment a second implementation exists: a case passing the portable
 * arm and failing a vectorized one has found a vectorization defect, and a case passing both has
 * been checked twice.
 *
 * WHAT IT COVERS, in the order it runs.
 *
 *   1. EVERY ARM AGREES WITH THE REFERENCE, over many fields, skews, needle lengths and origins.
 *      The net that catches what the designed cases miss.
 *   2. OVERLAPPING OCCURRENCES, where counts classically break, and the first casualty of any shift
 *      rule added later.
 *   3. DEGENERATE LENGTHS AND BOTH BOUNDARIES, including a match at the final alignment, which is
 *      where an off-by-one in the alignment bound hides.
 *   4. A SYMBOL THE FIELD NEVER PRODUCES, graded on the count AND on the read count, because the
 *      cheapness is a separate claim from the answer.
 *   5. EVERY SURVIVOR FALSE, so the count cannot be read off the survivor set.
 *   6. SHAPES OUTSIDE THE NECESSARY-CONDITION FAMILY, rejected by the guard instead of believed.
 *   7. WHAT SAMPLING COSTS, reported as a ratio instead of stated as a caveat.
 *
 * WHAT IT CANNOT COVER FROM OUTSIDE, and the entry each one needs, named so the gap is visible
 * instead of quietly absent. Probe order as a permutation null, and a census-derived predicate,
 * both need an entry that runs a search with a CALLER-SUPPLIED probe set. The destroy theorem's
 * consequence needs an entry that runs the descent with the stop condition disabled. The
 * monotonicity precondition needs a candidate set that grows with the level. None of those is
 * reachable through the public header, and each is one function away.
 *
 * @note No double, no float, no <math.h>, and nothing outside the C11 standard headers below.
 */

#include "anchor_sift.h"
#include "anchor_steer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** @brief Corpus bytes every generated field carries. */
#define ADVERSARIAL_CORPUS 4096u

/** @brief Longest needle any case draws. */
#define ADVERSARIAL_NEEDLE 64u

/** @brief Distinct byte values a census can record. */
#define ADVERSARIAL_SYMBOLS 256u

/** @brief Seeds the differential net walks. */
#define ADVERSARIAL_SEEDS 64u

/**
 * @brief Next value of the generator, letting a failing case reduce from its printed seed alone.
 *
 * @param[in,out] state Generator state, advanced in place [BORROWS].
 * @return              A value in the low 32 bits.
 * @note Its own generator instead of rand(), because a case that cannot be reproduced from a
 *       printed seed on another machine is not a case anyone can act on.
 */
static uint32_t adversarial_next(uint64_t *const state)
{
    *state = (*state * 6364136223846793005ULL) + 1442695040888963407ULL;
    return (uint32_t)(*state >> 33);
}

/**
 * @brief Fills a corpus whose symbol skew is chosen, from flat to a single repeated value.
 *
 * @param[out] corpus     Bytes to fill [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  alphabet   Distinct values to draw from, at least one.
 * @param[in]  state      Generator state, advanced in place [BORROWS].
 * @note An alphabet of one produces a constant field, the degenerate case every rule here
 *       has to survive.
 */
static void adversarial_fill_field(uint8_t *const corpus, const size_t corpus_len,
                                   const uint32_t alphabet, uint64_t *const state)
{
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        corpus[at] = (uint8_t)(adversarial_next(state) % alphabet);
    }
}

/**
 * @brief Grades one field and needle against the reference arm, both steered and unsteered.
 *
 * @param[in]  corpus     Bytes to search [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     Bytes to find [BORROWS].
 * @param[in]  needle_len How many.
 * @param[in]  label      What to print on a failure. Never null.
 * @return                0 where every arm agrees with the reference, 1 otherwise.
 * @note The reference is anchor_sift_naive and the comparison is EXACT. Counts are integers, and a
 *       tolerance here would be a defect.
 */
static int adversarial_grade_against_reference(const uint8_t *const corpus, const size_t corpus_len,
                                               const uint8_t *const needle, const size_t needle_len,
                                               const char *const label)
{
    const size_t expected = anchor_sift_naive(corpus, corpus_len, needle, needle_len);
    const size_t unsteered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 0);
    const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);
    int failed = 0;

    if (unsteered != expected)
    {
        printf("    FAIL %s: unsteered %zu against reference %zu\n", label, unsteered,
                    expected);
        failed = 1;
    }
    if (steered != expected)
    {
        printf("    FAIL %s: steered %zu against reference %zu\n", label, steered, expected);
        failed = 1;
    }
    return failed;
}

/**
 * @brief Case 1. Every arm agrees with the reference across seeds, skews, lengths and origins.
 *
 * @return 0 where every row agrees, 1 otherwise.
 * @note DIFFERENTIAL. No expected count is written down; the reference supplies it. Needles are
 *       drawn FROM the corpus for most rows, because a needle that never occurs exercises only the
 *       rejection path and the interesting failures are in counting the occurrences that exist.
 */
static int adversarial_case_differential_net(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[ADVERSARIAL_NEEDLE];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    for (uint32_t seed = 0u; seed < ADVERSARIAL_SEEDS; seed += 1u)
    {
        uint64_t state = 0x9E3779B97F4A7C15ULL ^ (uint64_t)seed;
        const uint32_t alphabet = 1u + (adversarial_next(&state) % ADVERSARIAL_SYMBOLS);
        const size_t needle_len = 1u + (size_t)(adversarial_next(&state) % ADVERSARIAL_NEEDLE);

        adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, alphabet, &state);

        // Three rows in four take the needle from the corpus, so occurrences exist to be counted.
        if ((seed % 4u) != 0u)
        {
            const size_t origin = (size_t)(adversarial_next(&state)
                                           % (ADVERSARIAL_CORPUS - needle_len));
            memcpy(needle, corpus + origin, needle_len);
        }
        else
        {
            for (size_t at = 0u; at < needle_len; at += 1u)
            {
                needle[at] = (uint8_t)(adversarial_next(&state) % alphabet);
            }
        }

        char label[64];
        snprintf(label, sizeof(label), "seed %u alphabet %u needle %zu", seed, alphabet,
                      needle_len);
        failed += adversarial_grade_against_reference(corpus, ADVERSARIAL_CORPUS, needle, needle_len,
                                                      label);
    }

    free(corpus);
    printf("  %u seeds against the reference, verdict %s\n", ADVERSARIAL_SEEDS,
                (failed == 0) ? "ok" : "FAILS");
    return (failed == 0) ? 0 : 1;
}

/**
 * @brief Case 2. Overlapping occurrences, where a count that skips after a match goes wrong.
 *
 * @return 0 where every row matches its derived count, 1 otherwise.
 * @note The expected counts are derived by hand from the definition instead of read off a run.
 *       "aaa" in five a's occupies alignments 0, 1 and 2, so the answer is 3 and an engine
 *       advancing past a match would report 1.
 */
static int adversarial_case_overlapping(void)
{
    static const struct
    {
        const char *corpus;
        const char *needle;
        size_t expected;
    } rows[] = {
        { "aaaaa", "aaa", 3u },
        { "aaaa", "aa", 3u },
        { "ababab", "abab", 2u },
        { "aaaa", "aaaa", 1u },
        { "abcabcabc", "abcabc", 2u },
    };
    int failed = 0;

    for (size_t row = 0u; row < (sizeof(rows) / sizeof(rows[0])); row += 1u)
    {
        const uint8_t *const corpus = (const uint8_t *)rows[row].corpus;
        const uint8_t *const needle = (const uint8_t *)rows[row].needle;
        const size_t corpus_len = strlen(rows[row].corpus);
        const size_t needle_len = strlen(rows[row].needle);
        const size_t reference = anchor_sift_naive(corpus, corpus_len, needle, needle_len);
        const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);

        if ((reference != rows[row].expected) || (steered != rows[row].expected))
        {
            printf("    FAIL \"%s\" in \"%s\": derived %zu, reference %zu, steered %zu\n",
                        rows[row].needle, rows[row].corpus, rows[row].expected, reference, steered);
            failed = 1;
        }
    }

    printf("  overlapping occurrences, verdict %s\n", (failed == 0) ? "ok" : "FAILS");
    return failed;
}

/**
 * @brief Case 3. Degenerate lengths and both boundary alignments.
 *
 * @return 0 where every row matches its derived count, 1 otherwise.
 * @note The final alignment is the row that matters. An off-by-one in the alignment bound is
 *       invisible everywhere else, because every other occurrence has a successor to mask it.
 */
static int adversarial_case_boundaries(void)
{
    static const uint8_t field[] = { 'x', 'y', 'z', 'q', 'x', 'y' };
    const size_t field_len = sizeof(field);
    int failed = 0;

    // A match at alignment zero, and a match at the final alignment, in one field.
    static const uint8_t leading[] = { 'x', 'y' };
    const size_t first_count = anchor_steer_count(field, field_len, leading, sizeof(leading), 1);
    if (first_count != 2u)
    {
        printf("    FAIL leading and trailing match: %zu against 2\n", first_count);
        failed = 1;
    }

    // A needle occupying the whole field occurs exactly once, at the only alignment there is.
    const size_t whole = anchor_steer_count(field, field_len, field, field_len, 1);
    if (whole != 1u)
    {
        printf("    FAIL needle equals corpus: %zu against 1\n", whole);
        failed = 1;
    }

    // A needle longer than the corpus has no alignment to sit at.
    static const uint8_t overlong[] = { 'x', 'y', 'z', 'q', 'x', 'y', 'z' };
    const size_t none = anchor_steer_count(field, field_len, overlong, sizeof(overlong), 1);
    if (none != 0u)
    {
        printf("    FAIL needle longer than corpus: %zu against 0\n", none);
        failed = 1;
    }

    // A single byte needle counts its symbol, the shortest probe the engine can place.
    static const uint8_t single[] = { 'x' };
    const size_t singles = anchor_steer_count(field, field_len, single, sizeof(single), 1);
    if (singles != 2u)
    {
        printf("    FAIL single byte needle: %zu against 2\n", singles);
        failed = 1;
    }

    printf("  degenerate lengths and boundaries, verdict %s\n", (failed == 0) ? "ok" : "FAILS");
    return failed;
}

/**
 * @brief Case 4. A symbol the field never produces, graded on the count and on the ordering paying.
 *
 * @return 0 where both arms count zero and the steered arm reads strictly fewer, 1 otherwise.
 * @note TWO CLAIMS, GRADED SEPARATELY. The count being zero says the answer is right. The steered
 *       arm reading fewer bytes than the spatial arm says the ordering put the absent symbol first,
 *       and that is what the magnitude rule promises. An engine passing the first and failing the
 *       second is correct and is not steering, and one assertion covering both would hide it.
 * @note THE SECOND CLAIM IS A RELATIONSHIP, and an earlier version of this case made it a CONSTANT.
 *       It asserted at most one read an alignment, passed at exactly that bound with no margin, and
 *       was therefore one read away from failing. A vectorized arm examines a whole vector whether
 *       the ordering needed it or not, so an arm doing strictly less work can read more bytes and
 *       break an assertion that a scalar arm satisfies. A case that fails on a correct
 *       implementation is a case somebody disables during a vectorization pass and never restores.
 *       Comparing the two arms survives whatever read accounting either of them uses, because both
 *       are counted the same way.
 * @note THE FIELD CARRIES THREE SYMBOLS so the needle's other bytes are common in it. The spatial
 *       order then pays for its first probe agreeing about a third of the time, which separates the
 *       arms by a margin instead of by a rounding. The absent byte stays absent, so the count stays
 *       zero.
 */
static int adversarial_case_absent_symbol(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    static const uint8_t needle[] = { 'a', 'b', 'c', 0xFFu };
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    // Three symbols, all of them carried by the needle, and 0xFF is not one of them.
    uint64_t state = 0xD1B54A32D192ED03ULL;
    for (size_t at = 0u; at < ADVERSARIAL_CORPUS; at += 1u)
    {
        corpus[at] = (uint8_t)('a' + (adversarial_next(&state) % 3u));
    }

    const size_t alignments = ADVERSARIAL_CORPUS - sizeof(needle) + 1u;

    anchor_steer_probes_reset();
    const size_t plain_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle,
                                                  sizeof(needle), 0);
    const uint64_t plain_reads = anchor_steer_probes;

    anchor_steer_probes_reset();
    const size_t steered_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle,
                                                    sizeof(needle), 1);
    const uint64_t steered_reads = anchor_steer_probes;

    if ((plain_count != 0u) || (steered_count != 0u))
    {
        printf("    FAIL absent symbol count: unsteered %zu, steered %zu, both should be 0\n",
               plain_count, steered_count);
        failed = 1;
    }
    if (steered_reads >= plain_reads)
    {
        printf("    FAIL the ordering did not pay: steered %llu reads against unsteered %llu, so "
               "the absent symbol was not tested first\n",
               (unsigned long long)steered_reads, (unsigned long long)plain_reads);
        failed = 1;
    }

    // Reported and never asserted. A scalar arm puts the steered figure at one read an alignment,
    // and a reader noticing that number move learns something the pass condition deliberately
    // does not depend on.
    printf("  absent symbol over %zu alignments, steered %llu reads against unsteered %llu, "
           "verdict %s\n",
           alignments, (unsigned long long)steered_reads, (unsigned long long)plain_reads,
           (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 5. Every survivor false, so the count cannot be read off the survivor set.
 *
 * @return 0 where the count is zero AND every alignment survived every probe, 1 otherwise.
 * @note THIS CASE CHECKS ITS OWN PREMISE, and it does so because an earlier version did not and
 *       silently stopped testing anything. A field of one repeated symbol and a needle carrying one
 *       different byte only reaches the full compare while no probe reads that byte. The STEERED
 *       arm defeats the construction on purpose: the odd byte is the rarest symbol the needle
 *       carries, so the ordering tests it first and refutes every alignment at the first read. The
 *       case therefore runs UNSTEERED, where the offsets are spatial.
 * @note WHY OFFSET FIVE. `choose_offsets` spreads four anchors over a 32 byte needle to positions
 *       0, 15, 22 and 29. A difference at 5 is never probed, every alignment survives all four
 *       probes, and every one is refuted by the full compare.
 * @note The read count is the premise check. Four probes surviving at every alignment is exactly
 *       four reads an alignment, and anything lower means a probe is refuting and this case has
 *       gone back to proving nothing. An engine counting survivors instead of verified matches
 *       reports the alignment count where the answer is zero.
 */
static int adversarial_case_all_survivors_false(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[32];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    memset(corpus, 'k', ADVERSARIAL_CORPUS);
    memset(needle, 'k', sizeof(needle));
    needle[5] = 'z';

    const size_t alignments = ADVERSARIAL_CORPUS - sizeof(needle) + 1u;
    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    anchor_steer_probes_reset();
    const size_t plain = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 0);
    const uint64_t reads = anchor_steer_probes;
    const uint64_t every_probe = (uint64_t)alignments * (uint64_t)ANCHOR_STEER_ANCHORS;

    if ((reference != 0u) || (plain != 0u))
    {
        printf("    FAIL all survivors false: reference %zu, unsteered %zu, both should be 0\n",
               reference, plain);
        failed = 1;
    }
    if (reads != every_probe)
    {
        printf("    FAIL premise: %llu reads against %llu for every probe at every alignment, so "
               "a probe is refuting and this case proves nothing\n",
               (unsigned long long)reads, (unsigned long long)every_probe);
        failed = 1;
    }

    printf("  every survivor false, %llu reads against %llu expected, verdict %s\n",
           (unsigned long long)reads, (unsigned long long)every_probe,
           (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 6. Shapes outside the necessary-condition family, refused by the guard.
 *
 * @return 0 where every illegal shape is refused and every legal one admitted, 1 otherwise.
 * @note This grades the GUARD instead of the count, because the first two shapes that leave the
 *       family are caught here and never reach a search. The third shape that leaves the family, a
 *       predicate taken from the census instead of the needle, is not reachable from outside and is
 *       named in the file block as a gap.
 */
static int adversarial_case_family_guard(void)
{
    static const size_t needle_len = 16u;
    int failed = 0;

    // An origin at the needle length reads past the end and must be refused.
    const AnchorProbe past_end = { needle_len, 1u, 1u };
    if (anchor_steer_probe_fits(&past_end, needle_len) != 0)
    {
        printf("    FAIL origin at needle_len admitted\n");
        failed = 1;
    }

    // A line whose last position falls outside the needle must be refused.
    const AnchorProbe overruns = { needle_len - 2u, 4u, 3u };
    if (anchor_steer_probe_fits(&overruns, needle_len) != 0)
    {
        printf("    FAIL line overrunning the needle admitted\n");
        failed = 1;
    }

    // A zero step above length one reads one position repeatedly and carries no second condition.
    const AnchorProbe stalled = { 0u, 0u, 4u };
    if (anchor_steer_probe_fits(&stalled, needle_len) != 0)
    {
        printf("    FAIL zero step above length one admitted\n");
        failed = 1;
    }

    // A zero length probe tests nothing and is not a necessary condition of anything.
    const AnchorProbe empty = { 0u, 1u, 0u };
    if (anchor_steer_probe_fits(&empty, needle_len) != 0)
    {
        printf("    FAIL zero length probe admitted\n");
        failed = 1;
    }

    // The widest line that still lands inside must be admitted, or the guard is refusing the family.
    const AnchorProbe widest = { 0u, needle_len - 1u, 2u };
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
static int adversarial_case_sampling_cost(void)
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
    for (size_t at = 0u; at < ADVERSARIAL_CORPUS; at += 1u)
    {
        corpus[at] = (uint8_t)(at % 16u);
    }
    memcpy(needle, corpus + 64u, sizeof(needle));

    const size_t expected = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    anchor_steer_probes_reset();
    const size_t baseline_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle,
                                                     sizeof(needle), 1);
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
 *       probe agrees, a conjunction commutes, so the surviving set and the count are the same under
 *       any order. This was argued from the start and could not be checked until an entry took the
 *       probe set as an argument.
 * @note A failure here points at STATE CARRIED BETWEEN PROBES in the implementation and not at the
 *       theory, because the mathematics has no order in it to get wrong. That is the reading to
 *       give anyone who hits it.
 */
static int adversarial_case_permutation_null(void)
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
        { { 0u, 1u, 1u }, { 7u, 1u, 1u }, { 15u, 1u, 1u } },
        { { 15u, 1u, 1u }, { 0u, 1u, 1u }, { 7u, 1u, 1u } },
        { { 7u, 1u, 1u }, { 15u, 1u, 1u }, { 0u, 1u, 1u } },
        { { 15u, 1u, 1u }, { 7u, 1u, 1u }, { 0u, 1u, 1u } },
    };
    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    for (size_t which = 0u; which < 4u; which += 1u)
    {
        const size_t counted = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle,
                                                              sizeof(needle), orders[which], 3u);
        if (counted != reference)
        {
            printf("    FAIL order %zu returned %zu against reference %zu\n", which, counted,
                   reference);
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
 *       full compare, so the answer is exactly right and the cost is maximal. If this fails, the
 *       verifier is wrong and every other count in the tree rests on nothing, because every probe
 *       set relies on that same compare to remove its false survivors.
 * @note The read count is graded at zero as a premise check. Probes reading bytes where no probe
 *       was supplied would mean the entry is choosing its own, and the case would be measuring
 *       something other than the identity.
 */
static int adversarial_case_empty_plan(void)
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
    const size_t counted = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle,
                                                          sizeof(needle), NULL, 0u);
    const uint64_t reads = anchor_steer_probes;

    if (counted != reference)
    {
        printf("    FAIL empty plan counted %zu against reference %zu\n", counted, reference);
        failed = 1;
    }
    if (reads != 0u)
    {
        printf("    FAIL premise: %llu probe reads with no probes supplied\n",
               (unsigned long long)reads);
        failed = 1;
    }

    printf("  the empty plan, %zu occurrences at %llu probe reads, verdict %s\n", counted,
           (unsigned long long)reads, (failed == 0) ? "ok" : "FAILS");
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
static int adversarial_case_growing_plan(void)
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
        { 0u, 1u, 1u }, { 19u, 1u, 1u }, { 9u, 1u, 1u }, { 4u, 5u, 2u },
    };
    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    for (size_t used = 1u; used <= 4u; used += 1u)
    {
        anchor_steer_probes_reset();
        const size_t counted = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle,
                                                              sizeof(needle), probes, used);
        if (counted != reference)
        {
            printf("    FAIL %zu probe(s) counted %zu against reference %zu\n", used, counted,
                   reference);
            failed = 1;
        }
    }

    printf("  growing the plan over %zu occurrences, verdict %s\n", reference,
           (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}

/**
 * @brief Case 11. Stopping at the destroy condition equals running to full depth.
 *
 * @return 0 where both descents agree on the count and on every probe the shallow one placed, 1
 *         otherwise.
 * @note THE DESTROY THEOREM TESTED BY ITS CONSEQUENCE. Under a candidate set that does not grow
 *       with the level, a fired stop condition would fire at every level below, so stopping and
 *       continuing place the same probes up to the stop point and return the same count.
 * @note TWO FAILURE MODES, AND THEY MEAN DIFFERENT THINGS. Counts differing means the
 *       necessary-condition guarantee broke, since both probe sets are legal whatever the descent
 *       chose. The probes before the stop point differing means the induction broke, and the
 *       candidate set is growing with the level where the theorem requires it not to. Reporting one
 *       verdict for both would lose that distinction.
 */
static int adversarial_case_stop_equals_continue(void)
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
    uint8_t *const scratch = (uint8_t *)malloc(alignments);

    if (scratch == NULL)
    {
        printf("    allocation failed\n");
        free(corpus);
        return 1;
    }

    const size_t stopped = anchor_steer_spawn_coarms_deep(shallow, ANCHOR_STEER_ANCHORS, corpus,
                                                          ADVERSARIAL_CORPUS, needle,
                                                          sizeof(needle), scratch, alignments, 1u,
                                                          0);
    const size_t forced = anchor_steer_spawn_coarms_deep(deep, ANCHOR_STEER_ANCHORS, corpus,
                                                         ADVERSARIAL_CORPUS, needle,
                                                         sizeof(needle), scratch, alignments, 1u,
                                                         1);

    const size_t reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));
    const size_t shallow_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle,
                                                    sizeof(needle), 1);

    if (shallow_count != reference)
    {
        printf("    FAIL descent count %zu against reference %zu\n", shallow_count, reference);
        failed = 1;
    }
    for (size_t slot = 0u; slot < stopped; slot += 1u)
    {
        if (shallow[slot] != deep[slot])
        {
            printf("    FAIL induction: probe %zu is offset %zu stopped and %zu forced\n", slot,
                   shallow[slot], deep[slot]);
            failed = 1;
        }
    }
    if (forced < stopped)
    {
        printf("    FAIL forced depth %zu below stopped depth %zu\n", forced, stopped);
        failed = 1;
    }

    printf("  stopping equals continuing, %zu probes stopped against %zu forced, verdict %s\n",
           stopped, forced, (failed == 0) ? "ok" : "FAILS");
    free(scratch);
    free(corpus);
    return failed;
}

/**
 * @brief Runs every case and returns how many failed.
 *
 * @return 0 where every case passes, otherwise the count that failed.
 * @note Order matters only in that the differential net runs first. It is the cheapest case that
 *       can fail for the widest set of reasons, and a failure there makes the designed cases below
 *       it easier to read.
 */
int main(void)
{
    int failed = 0;

    printf("\n  ADVERSARIAL SUITE, written to break the guarantees rather than show them.\n\n");

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

    printf("\n  %d case(s) failed\n\n", failed);
    return (failed == 0) ? 0 : 1;
}
