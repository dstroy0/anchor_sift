
// test_adversarial_cases.c: the adversarial cases: nets, overlaps, boundaries, symbols
#include "test_adversarial_internal.h"

/**
 * @brief Next value of the generator, letting a failing case reduce from its printed seed alone.
 *
 * @param[in,out] state Generator state, advanced in place [BORROWS].
 * @return              A value in the low 32 bits.
 * @note Its own generator instead of rand(), because a case that cannot be reproduced from a
 *       printed seed on another machine is not a case anyone can act on.
 */
uint32_t adversarial_next(uint64_t *const state)
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
 *       the case the line above exists for.
 * @note adversarial_next stays for the same kind of reason. bench_build_bytes takes a seed and fills
 *       a corpus, and this suite draws alphabet sizes, needle lengths and origins from one stream, and
 *       a failing case reduces from its printed seed. bench_corpora exports no general generator to
 *       draw those from.
 */
void adversarial_fill_field(uint8_t *const corpus, const size_t corpus_len, const uint32_t alphabet,
                            uint64_t *const state)
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
 * @note The reference is orior_naive and the comparison is EXACT. Counts are integers, and a
 *       tolerance here would be a defect.
 */
static int adversarial_grade_against_reference(const uint8_t *const corpus, const size_t corpus_len,
                                               const uint8_t *const needle, const size_t needle_len,
                                               const char *const label)
{
    const size_t expected = orior_naive(corpus, corpus_len, needle, needle_len);
    const size_t unsteered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 0);
    const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);
    int failed = 0;

    if (unsteered != expected)
    {
        printf("    FAIL %s: unsteered %zu against reference %zu\n", label, unsteered, expected);
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
int adversarial_case_differential_net(void)
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
            const size_t origin = (size_t)(adversarial_next(&state) % (ADVERSARIAL_CORPUS - needle_len));
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
        snprintf(label, sizeof(label), "seed %u alphabet %u needle %zu", seed, alphabet, needle_len);
        failed += adversarial_grade_against_reference(corpus, ADVERSARIAL_CORPUS, needle, needle_len, label);
    }

    free(corpus);
    printf("  %u seeds against the reference, verdict %s\n", ADVERSARIAL_SEEDS, (failed == 0) ? "ok" : "FAILS");
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
int adversarial_case_overlapping(void)
{
    static const struct
    {
        const char *corpus;
        const char *needle;
        size_t expected;
    } rows[] = {
        {"aaaaa", "aaa", 3u}, {"aaaa", "aa", 3u},          {"ababab", "abab", 2u},
        {"aaaa", "aaaa", 1u}, {"abcabcabc", "abcabc", 2u},
    };
    int failed = 0;

    for (size_t row = 0u; row < (sizeof(rows) / sizeof(rows[0])); row += 1u)
    {
        const uint8_t *const corpus = (const uint8_t *)rows[row].corpus;
        const uint8_t *const needle = (const uint8_t *)rows[row].needle;
        const size_t corpus_len = strlen(rows[row].corpus);
        const size_t needle_len = strlen(rows[row].needle);
        const size_t reference = orior_naive(corpus, corpus_len, needle, needle_len);
        const size_t steered = anchor_steer_count(corpus, corpus_len, needle, needle_len, 1);

        if ((reference != rows[row].expected) || (steered != rows[row].expected))
        {
            printf("    FAIL \"%s\" in \"%s\": derived %zu, reference %zu, steered %zu\n", rows[row].needle,
                   rows[row].corpus, rows[row].expected, reference, steered);
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
int adversarial_case_boundaries(void)
{
    static const uint8_t field[] = {'x', 'y', 'z', 'q', 'x', 'y'};
    const size_t field_len = sizeof(field);
    int failed = 0;

    // A match at alignment zero, and a match at the final alignment, in one field.
    static const uint8_t leading[] = {'x', 'y'};
    const size_t first_count = anchor_steer_count(field, field_len, leading, sizeof(leading), 1);
    if (first_count != 2u)
    {
        printf("    FAIL leading and trailing match: %zu against 2\n", first_count);
        failed = 1;
    }

    // A needle occupying the whole field occurs exactly once, at the only alignment there is.
    const size_t self_count = anchor_steer_count(field, field_len, field, field_len, 1);
    if (self_count != 1u)
    {
        printf("    FAIL needle equals corpus: %zu against 1\n", self_count);
        failed = 1;
    }

    // A needle longer than the corpus has no alignment to sit at.
    static const uint8_t overlong[] = {'x', 'y', 'z', 'q', 'x', 'y', 'z'};
    const size_t none = anchor_steer_count(field, field_len, overlong, sizeof(overlong), 1);
    if (none != 0u)
    {
        printf("    FAIL needle longer than corpus: %zu against 0\n", none);
        failed = 1;
    }

    // A single byte needle counts its symbol, the shortest probe the engine can place.
    static const uint8_t single[] = {'x'};
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
 *       as the magnitude rule promises. An engine passing the first and failing the
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
int adversarial_case_absent_symbol(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    static const uint8_t needle[] = {'a', 'b', 'c', 0xFFu};
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
    const size_t plain_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 0);
    const uint64_t plain_reads = anchor_steer_probes;

    anchor_steer_probes_reset();
    const size_t steered_count = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 1);
    const uint64_t steered_reads = anchor_steer_probes;

    if ((plain_count != 0u) || (steered_count != 0u))
    {
        printf("    FAIL absent symbol count: unsteered %zu, steered %zu, both should be 0\n", plain_count,
               steered_count);
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
 *       arm defeats the construction by design: the odd byte is the rarest symbol the needle
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
int adversarial_case_all_survivors_false(void)
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
    const size_t reference = orior_naive(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle));

    anchor_steer_probes_reset();
    const size_t plain = anchor_steer_count(corpus, ADVERSARIAL_CORPUS, needle, sizeof(needle), 0);
    const uint64_t reads = anchor_steer_probes;
    const uint64_t every_probe = (uint64_t)alignments * (uint64_t)ANCHOR_STEER_ANCHORS;

    if ((reference != 0u) || (plain != 0u))
    {
        printf("    FAIL all survivors false: reference %zu, unsteered %zu, both should be 0\n", reference, plain);
        failed = 1;
    }
    if (reads != every_probe)
    {
        printf("    FAIL premise: %llu reads against %llu for every probe at every alignment. "
               "a probe is refuting and this case proves nothing\n",
               (unsigned long long)reads, (unsigned long long)every_probe);
        failed = 1;
    }

    printf("  every survivor false, %llu reads against %llu expected, verdict %s\n", (unsigned long long)reads,
           (unsigned long long)every_probe, (failed == 0) ? "ok" : "FAILS");
    free(corpus);
    return failed;
}
