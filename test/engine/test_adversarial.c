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
 * This file asks whether the engine is right, which is a different question. Douglas put the two
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
 * carries. The ordering tests it FIRST, every alignment refutes at the first read, and the full
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
 * FOUR OF THESE ARE DIFFERENTIAL. They compare two routes that must agree. No expected number is
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
 *   5. EVERY SURVIVOR FALSE. The count cannot be read off the survivor set.
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
 * @brief Corpus symbols a projected case carries.
 *
 * @note Smaller than ADVERSARIAL_CORPUS because the projection's closure is quadratic in the joint
 *       field and the sweep runs it once per seed. 512 still reaches past 256 classes when the
 *       alphabet is wide, and case 13 checks that it does.
 */
#define ADVERSARIAL_PROJECTED 512u

/** @brief Longest needle a projected case draws. */
#define ADVERSARIAL_PROJECTED_NEEDLE 8u

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
 * @note NOT A COPY OF CORPUS_SKEWED, checked against bench_corpora.c before this note was written.
 *       This draws uniformly over an alphabet of N. The knob is the SIZE of the alphabet and the
 *       distribution over it is flat. CORPUS_SKEWED draws uniformly over 256 and maps the result
 *       through a table where each successive symbol takes half the space left, giving a fixed
 *       dyadic skew over 27 symbols with no knob at all. Neither can produce the other. Folding this
 *       onto CORPUS_SKEWED would lose the whole sweep, the constant field at alphabet one included,
 *       which is the case the line above exists for.
 * @note adversarial_next stays for the same kind of reason. bench_build_bytes takes a seed and fills
 *       a corpus, and this suite draws alphabet sizes, needle lengths and origins from one stream so
 *       a failing case reduces from its printed seed. bench_corpora exports no general generator to
 *       draw those from.
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

        // Three rows in four take the needle from the corpus. Occurrences exist to be counted.
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
 *       "aaa" in five a's occupies alignments 0, 1 and 2. The answer is 3 and an engine
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
 *       the ordering needed it or not. An arm doing strictly less work can read more bytes and
 *       break an assertion that a scalar arm satisfies. A case that fails on a correct
 *       implementation is a case somebody disables during a vectorization pass and never restores.
 *       Comparing the two arms survives whatever read accounting either of them uses, because both
 *       are counted the same way.
 * @note THE FIELD CARRIES THREE SYMBOLS so the needle's other bytes are common in it. The spatial
 *       order then pays for its first probe agreeing about a third of the time, which separates the
 *       arms by a margin instead of by a rounding. The absent byte stays absent. The count stays
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
        printf("    FAIL the ordering did not pay: steered %llu reads against unsteered %llu. "
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
 * @brief Case 5. Every survivor false. The count cannot be read off the survivor set.
 *
 * @return 0 where the count is zero AND every alignment survived every probe, 1 otherwise.
 * @note THIS CASE CHECKS ITS OWN PREMISE, and it does so because an earlier version did not and
 *       silently stopped testing anything. A field of one repeated symbol and a needle carrying one
 *       different byte only reaches the full compare while no probe reads that byte. The STEERED
 *       arm defeats the construction on purpose: the odd byte is the rarest symbol the needle
 *       carries. The ordering tests it first and refutes every alignment at the first read. The
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
        printf("    FAIL premise: %llu reads against %llu for every probe at every alignment. "
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
    //
    // BUILT HERE ON PURPOSE, THOUGH bench_corpora BUILDS THE SAME FIELD. This was briefly folded
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
 *       probe agrees, a conjunction commutes. The surviving set and the count are the same under
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
 *       full compare. The answer is exactly right and the cost is maximal. If this fails, the
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

    // The empty-needle boundary, which no other case reaches. An empty needle occurs at every
    // alignment. The reference is corpus_len + 1. anchor_steer_count_with_probes returned 0 here
    // until its guard was split, disagreeing with anchor_sift_naive and anchor_steer_count in the
    // same tree. The probes cannot be evaluated on a needle with no positions. The empty probe set
    // is the one to grade it with.
    {
        const size_t empty_reference = anchor_sift_naive(corpus, ADVERSARIAL_CORPUS, needle, 0u);
        const size_t empty_counted =
            anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle, 0u, NULL, 0u);
        if (empty_counted != empty_reference)
        {
            printf("    FAIL empty needle counted %zu against reference %zu\n", empty_counted,
                   empty_reference);
            failed = 1;
        }
    }

    // A probe that reads past the needle. Its last position is (needle_len - 2) + 4*2, which is
    // needle_len + 6. Anchor_steer_probe_fits rejects it and the count is 0. Before the guard,
    // count_with_probes read needle[offset] and corpus[at + offset] off the end of both. The count
    // it returns is not the reference; a refusal is the point, and 0 is the documented one.
    {
        const AnchorProbe overruns = { sizeof(needle) - 2u, 4u, 3u };
        const size_t refused = anchor_steer_count_with_probes(corpus, ADVERSARIAL_CORPUS, needle,
                                                              sizeof(needle), &overruns, 1u);
        if (refused != 0u)
        {
            printf("    FAIL a probe past the needle counted %zu, expected the refusal 0\n", refused);
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
 *       with the level, a fired stop condition would fire at every level below. Stopping and
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
    uint8_t *const survivors = (uint8_t *)malloc(alignments);

    if (survivors == NULL)
    {
        printf("    allocation failed\n");
        free(corpus);
        return 1;
    }

    // The two runs differ in one member and nothing else, which is the whole point of the case.
    // force_full_depth is omitted on the first, and an omitted member is zero, which is the destroy
    // rule honored. Naming it on the second forces every level.
    const size_t stopped = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                             .offsets = shallow,
                                             .count = ANCHOR_STEER_ANCHORS,
                                             .corpus = corpus,
                                             .corpus_len = ADVERSARIAL_CORPUS,
                                             .needle = needle,
                                             .needle_len = sizeof(needle),
                                             .survivors = survivors,
                                             .survivors_length = alignments,
                                             .sample_stride = 1u);
    const size_t forced = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                            .offsets = deep,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments,
                                            .sample_stride = 1u,
                                            .force_full_depth = 1);

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
    free(survivors);
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
/**
 * @brief Case 12. A descent stops, recurses, or refuses, and never revisits a state.
 *
 * @return Count of failures.
 *
 * THE TRICHOTOMY IS A CLAIM AND THIS IS WHERE IT IS ATTACKED. The guide states that a descent takes
 * one of exactly three branches: it stops when the destroy test fires, it recurses when a level
 * prunes, and it refuses to run at all when the question is malformed. The fourth branch it denies
 * is cycling, returning to a state already held.
 *
 * Each branch is checked separately and the refusal is checked hardest, because a refusal that
 * returns zero while having already written to the caller's buffer is indistinguishable from a
 * refusal that wrote nothing, unless somebody looks at the buffer. Every malformed call below is
 * made against a buffer filled with a sentinel, and the sentinel has to survive.
 *
 * No-revisiting is checked by requiring the placed offsets to be pairwise distinct. A descent that
 * placed the same offset twice would have returned to a state it already held, since placing a probe
 * that is already placed leaves the survivor set exactly as it was.
 */
static int adversarial_case_trichotomy(void)
{
    printf("  a descent stops, recurses, or refuses, and never revisits\n");

    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[16];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    uint64_t state = 0xC0FFEEu;
    adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, 6u, &state);
    memcpy(needle, corpus + 128u, sizeof(needle));

    const size_t alignments = (ADVERSARIAL_CORPUS - sizeof(needle)) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("    allocation failed\n");
        free(corpus);
        return 1;
    }

    // REFUSES. Six malformed questions, each against a sentinel filled buffer. The contract is that
    // a refused call returns zero AND writes nothing, and only the second half needs looking for.
    const size_t sentinel = (size_t)0xABCDEF01u;
    struct
    {
        const char *what;
        AnchorSteerDescent args;
    } refusals[6];

    size_t offsets[ANCHOR_STEER_ANCHORS];

    refusals[0].what = "null offsets";
    refusals[0].args = (AnchorSteerDescent){ .offsets = NULL, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle,
        .needle_len = sizeof(needle), .survivors = survivors, .survivors_length = alignments };
    refusals[1].what = "null corpus";
    refusals[1].args = (AnchorSteerDescent){ .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = NULL, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle,
        .needle_len = sizeof(needle), .survivors = survivors, .survivors_length = alignments };
    refusals[2].what = "count over the bound";
    refusals[2].args = (AnchorSteerDescent){ .offsets = offsets, .count = ANCHOR_STEER_ANCHORS + 1u,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle,
        .needle_len = sizeof(needle), .survivors = survivors, .survivors_length = alignments };
    refusals[3].what = "needle length zero";
    refusals[3].args = (AnchorSteerDescent){ .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle, .needle_len = 0u,
        .survivors = survivors, .survivors_length = alignments };
    refusals[4].what = "needle longer than corpus";
    refusals[4].args = (AnchorSteerDescent){ .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = 8u, .needle = needle, .needle_len = sizeof(needle),
        .survivors = survivors, .survivors_length = alignments };
    refusals[5].what = "survivor buffer short by one";
    refusals[5].args = (AnchorSteerDescent){ .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle,
        .needle_len = sizeof(needle), .survivors = survivors,
        .survivors_length = alignments - 1u };

    for (size_t which = 0u; which < 6u; which += 1u)
    {
        for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
        {
            offsets[slot] = sentinel;
        }

        const size_t placed = anchor_steer_spawn_coarms(&refusals[which].args);
        if (placed != 0u)
        {
            printf("    %s ran and placed %zu: FAILS\n", refusals[which].what, placed);
            failed += 1;
        }
        for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
        {
            if (offsets[slot] != sentinel)
            {
                printf("    %s wrote to the caller's buffer: FAILS\n", refusals[which].what);
                failed += 1;
                break;
            }
        }
    }

    // A null argument pointer is the seventh refusal and cannot be expressed in the table above.
    if (anchor_steer_spawn_coarms(NULL) != 0u)
    {
        printf("    a null argument pointer ran: FAILS\n");
        failed += 1;
    }

    // RECURSES, and NEVER REVISITS. A well formed call places distinct offsets. Forcing full depth
    // takes the branch that ignores the destroy test, which is the recursing branch by construction.
    const size_t forced = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                            .offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments,
                                            .sample_stride = 1u,
                                            .force_full_depth = 1);

    for (size_t slot = 0u; slot < forced; slot += 1u)
    {
        for (size_t seen = 0u; seen < slot; seen += 1u)
        {
            if (offsets[slot] == offsets[seen])
            {
                printf("    offset %zu placed twice, a state was revisited: FAILS\n",
                       offsets[slot]);
                failed += 1;
            }
        }
        if (offsets[slot] >= sizeof(needle))
        {
            printf("    offset %zu lies outside the needle: FAILS\n", offsets[slot]);
            failed += 1;
        }
    }

    // STOPS. Honoring the destroy test can only place fewer, never more.
    const size_t stopped = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                             .offsets = offsets,
                                             .count = ANCHOR_STEER_ANCHORS,
                                             .corpus = corpus,
                                             .corpus_len = ADVERSARIAL_CORPUS,
                                             .needle = needle,
                                             .needle_len = sizeof(needle),
                                             .survivors = survivors,
                                             .survivors_length = alignments,
                                             .sample_stride = 1u);

    if (stopped > forced)
    {
        printf("    stopping placed more than forcing: FAILS\n");
        failed += 1;
    }
    if (forced > ANCHOR_STEER_ANCHORS)
    {
        printf("    forcing exceeded the compile time bound: FAILS\n");
        failed += 1;
    }

    printf("    refused 7 malformed questions, recursed to %zu distinct offsets, stopped at %zu,"
           " verdict %s\n", forced, stopped, (failed == 0) ? "ok" : "FAILS");

    free(survivors);
    free(corpus);
    return failed;
}

/** @brief A corpus and a needle of 32 bit symbols, addressed through one joint index space. */
typedef struct
{
    const uint32_t *corpus; /**< Corpus symbols [BORROWS]. */
    size_t corpus_length;   /**< How many. Joint positions below this are corpus positions. */
    const uint32_t *needle; /**< Needle symbols, at joint positions from corpus_length on [BORROWS]. */
} AdversarialJointSymbols;

/** @brief The three class arrays a projection writes, sized for the widest joint field used here. */
typedef struct
{
    uint32_t *class_of_position;     /**< Which class each position fell in [BORROWS]. */
    uint32_t *members_in_class;      /**< How many positions each class holds [BORROWS]. */
    uint32_t *rarity_place_of_class; /**< Where each class sits in the rarity order [BORROWS]. */
    size_t classes_length;           /**< Entries each of the three holds. */
} AdversarialClassBuffers;

/**
 * @brief The symbol at one joint position, corpus first and needle after it.
 *
 * @param[in] joint    Both sides [BORROWS].
 * @param[in] position Joint position.
 * @return             The symbol held there.
 */
static uint32_t adversarial_joint_symbol(const AdversarialJointSymbols *joint, size_t position)
{
    if (position < joint->corpus_length)
    {
        return joint->corpus[position];
    }
    return joint->needle[position - joint->corpus_length];
}

/** @brief Equality between two joint positions, the oracle anchor_field_pair_project asks. */
static int adversarial_same_joint(const void *field, size_t left, size_t right)
{
    const AdversarialJointSymbols *const joint = (const AdversarialJointSymbols *)field;

    return (adversarial_joint_symbol(joint, left) == adversarial_joint_symbol(joint, right)) ? 1 : 0;
}

/** @brief Equality between two positions of one symbol array, for projecting one side alone. */
static int adversarial_same_symbol(const void *field, size_t left, size_t right)
{
    const uint32_t *const symbols = (const uint32_t *)field;

    return (symbols[left] == symbols[right]) ? 1 : 0;
}

/**
 * @brief Exact occurrences of a needle of 32 bit symbols, found by comparing the symbols directly.
 *
 * @param[in] corpus        Symbols searched [BORROWS].
 * @param[in] corpus_length How many.
 * @param[in] needle        Symbols searched for [BORROWS].
 * @param[in] needle_length How many. Non-zero.
 * @return                  Alignments where every symbol agrees.
 * @note The truth both projected routes answer to. It shares no code with the projection or with the
 *       byte engine, which makes agreement with it agreement between two independent routes.
 */
static size_t adversarial_count_symbols(const uint32_t *corpus, size_t corpus_length,
                                        const uint32_t *needle, size_t needle_length)
{
    size_t found = 0u;

    for (size_t at = 0u; (at + needle_length) <= corpus_length; at += 1u)
    {
        size_t offset = 0u;

        while ((offset < needle_length) && (corpus[at + offset] == needle[offset]))
        {
            offset += 1u;
        }
        if (offset == needle_length)
        {
            found += 1u;
        }
    }
    return found;
}

/**
 * @brief Counts through two separate projections, one per side. THE BROKEN CONSTRUCTION.
 *
 * @return 1 where both projections ran and `count` was written, 0 where either refused.
 * @note Kept in the suite as the negative control. A case that cannot show this route
 *       losing an occurrence cannot show the joint route recovering one.
 */
static int adversarial_count_apart(const uint32_t *corpus, size_t corpus_length,
                                   const uint32_t *needle, size_t needle_length,
                                   uint8_t *corpus_ranks, uint8_t *needle_ranks,
                                   const AdversarialClassBuffers *buffers, size_t *count)
{
    const AnchorFieldProjection corpus_side = {
        .same_in_field = adversarial_same_symbol,
        .field = corpus,
        .length = corpus_length,
        .ranks = corpus_ranks,
        .class_of_position = buffers->class_of_position,
        .members_in_class = buffers->members_in_class,
        .rarity_place_of_class = buffers->rarity_place_of_class,
        .classes_length = buffers->classes_length
    };
    const AnchorFieldProjection needle_side = {
        .same_in_field = adversarial_same_symbol,
        .field = needle,
        .length = needle_length,
        .ranks = needle_ranks,
        .class_of_position = buffers->class_of_position,
        .members_in_class = buffers->members_in_class,
        .rarity_place_of_class = buffers->rarity_place_of_class,
        .classes_length = buffers->classes_length
    };

    const int corpus_projected = anchor_field_project(&corpus_side);
    const int needle_projected = anchor_field_project(&needle_side);

    if ((corpus_projected == 0) || (needle_projected == 0))
    {
        return 0;
    }
    *count = anchor_steer_count(corpus_ranks, corpus_length, needle_ranks, needle_length, 1);
    return 1;
}

/**
 * @brief Counts through anchor_field_pair_project, which numbers both sides in one population.
 *
 * @return 1 where the projection ran and `count` and `distinct` were written, 0 where it refused.
 */
static int adversarial_count_together(const uint32_t *corpus, size_t corpus_length,
                                      const uint32_t *needle, size_t needle_length,
                                      uint8_t *corpus_ranks, uint8_t *needle_ranks,
                                      const AdversarialClassBuffers *buffers, size_t *count,
                                      size_t *distinct)
{
    const AdversarialJointSymbols joint = {
        .corpus = corpus,
        .corpus_length = corpus_length,
        .needle = needle
    };
    const AnchorFieldPairProjection both = {
        .same_in_field = adversarial_same_joint,
        .field = &joint,
        .corpus_length = corpus_length,
        .needle_length = needle_length,
        .corpus_ranks = corpus_ranks,
        .needle_ranks = needle_ranks,
        .class_of_position = buffers->class_of_position,
        .members_in_class = buffers->members_in_class,
        .rarity_place_of_class = buffers->rarity_place_of_class,
        .classes_length = buffers->classes_length,
        .distinct = distinct
    };

    const int projected = anchor_field_pair_project(&both);

    if (projected == 0)
    {
        return 0;
    }
    *count = anchor_steer_count(corpus_ranks, corpus_length, needle_ranks, needle_length, 1);
    return 1;
}

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
 *       Part one is the counterexample as the theorist reported it, built by hand. The separate
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
 *       needle by copying out of the corpus's own projected ranks (`test/engine/test_steer.c`,
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
        .classes_length = buffer_positions
    };
    uint32_t needle[ADVERSARIAL_PROJECTED_NEEDLE];
    uint8_t needle_ranks[ADVERSARIAL_PROJECTED_NEEDLE];
    int failed = 0;

    if ((corpus == NULL) || (corpus_ranks == NULL) || (buffers.class_of_position == NULL)
     || (buffers.members_in_class == NULL) || (buffers.rarity_place_of_class == NULL))
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

    const size_t reported_truth = adversarial_count_symbols(corpus, reported_length, needle,
                                                            reported_needle_length);
    size_t reported_apart = 0u;
    size_t reported_together = 0u;
    size_t reported_distinct = 0u;
    const int reported_apart_ran = adversarial_count_apart(corpus, reported_length, needle,
                                                           reported_needle_length, corpus_ranks,
                                                           needle_ranks, &buffers,
                                                           &reported_apart);
    const int reported_together_ran = adversarial_count_together(corpus, reported_length, needle,
                                                                 reported_needle_length,
                                                                 corpus_ranks, needle_ranks,
                                                                 &buffers, &reported_together,
                                                                 &reported_distinct);

    printf("  %34s %8s %8s %8s %8s\n", "reported counterexample", "truth", "apart", "together",
           "classes");
    printf("  %34s %8zu %8zu %8zu %8zu\n", "C C B A once, at 98", reported_truth, reported_apart,
           reported_together, reported_distinct);

    if (reported_truth != 1u)
    {
        printf("    FAIL premise: the hand built field holds %zu occurrences, not 1\n",
               reported_truth);
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
        printf("    FAIL the joint route returned %zu against truth %zu\n", reported_together,
               reported_truth);
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

        // Even seeds cut the needle out of the corpus. The truth is at least one. Odd seeds draw
        // it independently. The needle holds symbols in proportions the corpus does not.
        if ((seed % 2u) == 0u)
        {
            const size_t origin =
                adversarial_next(&state) % ((ADVERSARIAL_PROJECTED - needle_length) + 1u);

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

        const size_t truth = adversarial_count_symbols(corpus, ADVERSARIAL_PROJECTED, needle,
                                                       needle_length);
        size_t apart = 0u;
        size_t together = 0u;
        size_t distinct = 0u;
        const int apart_ran = adversarial_count_apart(corpus, ADVERSARIAL_PROJECTED, needle,
                                                      needle_length, corpus_ranks, needle_ranks,
                                                      &buffers, &apart);
        const int together_ran = adversarial_count_together(corpus, ADVERSARIAL_PROJECTED, needle,
                                                            needle_length, corpus_ranks,
                                                            needle_ranks, &buffers, &together,
                                                            &distinct);

        if ((apart_ran == 0) || (together_ran == 0))
        {
            printf("    FAIL seed %zu: a projection refused a valid field\n", seed);
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
                printf("    FAIL seed %zu: %zu classes, joint route %zu against truth %zu\n", seed,
                       distinct, together, truth);
                failed = 1;
            }
        }
        else
        {
            clamped_regime += 1u;
            if (together < truth)
            {
                printf("    FAIL seed %zu: %zu classes, joint route %zu BELOW truth %zu\n", seed,
                       distinct, together, truth);
                failed = 1;
            }
        }
    }

    printf("  %34s %8s %8s %8s\n", "seeded sweep", "exact", "clamped", "lost");
    printf("  %34s %8zu %8zu %8zu\n", "seeds by regime, apart losses", exact_regime,
           clamped_regime, apart_losses);

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
    const int clamp_ran = adversarial_count_together(corpus, singleton_length, needle, 2u,
                                                     corpus_ranks, needle_ranks, &buffers,
                                                     &clamp_together, &clamp_distinct);

    printf("  %34s %8s %8s %8s\n", "clamp merges the needle", "truth", "together", "classes");
    printf("  %34s %8zu %8zu %8zu\n", "upper bound, never below", clamp_truth, clamp_together,
           clamp_distinct);

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

    printf("  joint projection keeps every true occurrence, verdict %s\n",
           (failed == 0) ? "ok" : "FAILS");

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
    failed += adversarial_case_trichotomy();
    failed += adversarial_case_joint_projection();

    printf("\n  %d case(s) failed\n\n", failed);
    return (failed == 0) ? 0 : 1;
}
