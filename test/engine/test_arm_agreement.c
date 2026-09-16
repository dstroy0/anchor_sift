/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_arm_agreement.c
 * @brief Grades every arm against the naive one at the lengths that bound the input, and at none.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note The kernel's own contract is that every arm is sound, so no arm can lose a true occurrence
 *       and every arm must return what the naive one returns. This driver asks that question at the
 *       lengths nobody searches with: none, one, and two. A needle of one byte puts all four anchors
 *       on the same offset, and a needle of no bytes has no offset to put them on at all.
 *
 * @note It links the kernel rather than restating it. A grader holding its own copy of the function
 *       it grades keeps passing forever after somebody repairs the original, which is the one way a
 *       test can be worse than no test.
 *
 * @warning This is a negative control and it is expected to FAIL before the repair it accompanies.
 *          On a kernel where choose_offsets clamps a zero length needle to needle_len - 1u, that
 *          expression wraps to SIZE_MAX on size_t and the arms read far outside both pointers. The
 *          run may crash rather than print a row, and a crash here is the finding.
 */

#include "anchor_sift.h"

#include <stdio.h>
#include <stdlib.h>

/* Long enough that an anchor spread is meaningful and short enough to stay a unit test. */
#define AGREEMENT_CORPUS_BYTES 4096u

/* Where the needle is lifted from, so every needle tested occurs at least once. */
#define AGREEMENT_NEEDLE_AT 1000u

/* The lengths under test. Zero and one are the bounds this driver exists for; the rest are ordinary
 * lengths present so a failure at a bound is distinguishable from an arm that is simply broken. */
static const size_t AGREEMENT_LENGTHS[] = {0u, 1u, 2u, 3u, 4u, 16u, 64u};

static unsigned failures = 0u;

/**
 * @brief Fills a corpus with a small repeating alphabet, deterministically.
 *
 * @param[out] corpus     Bytes to fill [BORROWS].
 * @param[in]  corpus_len How many.
 * @note A small alphabet makes anchor agreement common, so the arms actually reach their verify
 *       step rather than refuting on the first probe everywhere.
 */
static void fill_corpus(uint8_t *corpus, size_t corpus_len)
{
    uint64_t state = 0x9E3779B97F4A7C15uLL;

    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        // Five symbols, so a four anchor cascade survives often enough to be worth verifying.
        corpus[at] = (uint8_t)('a' + (state % 5u));
    }
}

/**
 * @brief Reports one graded comparison and counts it where it disagrees.
 *
 * @param[in] what     What was compared.
 * @param[in] measured What the arm returned.
 * @param[in] expected What the naive arm returned.
 */
static void grade(const char *what, size_t measured, size_t expected)
{
    const int agrees = (measured == expected);

    if (!agrees)
    {
        failures += 1u;
    }
    // Widened to the widest unsigned the format can name, which loses nothing. size_t has no
    // printf spelling every runtime this builds on accepts: the MinGW runtime rejects %zu and
    // prints the letter. Carrying the value up is portable where reaching for a length modifier
    // one library understands is not.
    printf("  %-34s measured %-12llu expected %-12llu %s\n", what, (unsigned long long)measured,
           (unsigned long long)expected, agrees ? "OK" : "DISAGREES");
}

int main(void)
{
    uint8_t *const corpus = (uint8_t *)malloc(AGREEMENT_CORPUS_BYTES);

    if (corpus == NULL)
    {
        printf("  no corpus could be allocated, so nothing was graded.\n");
        return 2;
    }
    fill_corpus(corpus, AGREEMENT_CORPUS_BYTES);

    printf("Every arm against the naive one. A disagreement is a defect, whatever it measures.\n\n");

    for (size_t which = 0u; which < (sizeof AGREEMENT_LENGTHS / sizeof AGREEMENT_LENGTHS[0]);
         which += 1u)
    {
        const size_t needle_len = AGREEMENT_LENGTHS[which];
        const uint8_t *const needle = corpus + AGREEMENT_NEEDLE_AT;
        const size_t expected = anchor_sift_naive(corpus, AGREEMENT_CORPUS_BYTES, needle,
                                                  needle_len);
        char label[64];

        // Widened for the same reason as in grade().
        printf("needle_len %llu\n", (unsigned long long)needle_len);

        snprintf(label, sizeof label, "anchor_sift_inorder");
        grade(label, anchor_sift_inorder(corpus, AGREEMENT_CORPUS_BYTES, needle, needle_len),
              expected);

        snprintf(label, sizeof label, "anchor_sift_free");
        grade(label, anchor_sift_free(corpus, AGREEMENT_CORPUS_BYTES, needle, needle_len),
              expected);

        // A plan carrying no period and the corpus's own census, so the dispatcher has a real
        // decision to make rather than being steered by a degenerate one. The census replaced the
        // entropy and distinct count the plan used to carry: the rule reads integer counts now and
        // the engine holds no floating point value anywhere.
        AnchorFieldCensus census;
        anchor_field_census(corpus, AGREEMENT_CORPUS_BYTES, &census);
        const AnchorSiftPlan plan = {.census = &census, .period = 0u};

        snprintf(label, sizeof label, "anchor_sift_run");
        grade(label, anchor_sift_run(&plan, corpus, AGREEMENT_CORPUS_BYTES, needle, needle_len),
              expected);
    }

    printf("\nA null plan, which the header states no precondition against.\n");

    grade("anchor_sift_choose is naive", (size_t)(anchor_sift_choose(NULL) == anchor_sift_naive),
          1u);
    grade("anchor_sift_anchors_for", anchor_sift_anchors_for(NULL), (size_t)ANCHOR_SIFT_ANCHORS);

    {
        const uint8_t *const needle = corpus + AGREEMENT_NEEDLE_AT;
        const size_t expected = anchor_sift_naive(corpus, AGREEMENT_CORPUS_BYTES, needle, 16u);

        grade("anchor_sift_run on a null plan",
              anchor_sift_run(NULL, corpus, AGREEMENT_CORPUS_BYTES, needle, 16u), expected);
    }

    free(corpus);

    printf("\n  %u disagreement(s)\n", failures);
    return (failures == 0u) ? 0 : 1;
}
