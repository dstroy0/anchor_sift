/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_exact.c
 * @brief Emits limb results for a fixed set of operations, for the Python engine to check.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note This driver decides nothing. It prints what the limb arithmetic produced and the answer
 *       comes from somewhere else. maint/engine/check_exact_limbs.py recomputes every row with python
 *       integers, which are arbitrary precision and share no code with this, and compares.
 * @note A library cannot be its own oracle. Checking these operations against a second routine in
 *       this same file would pass forever, because both would carry any error the author made about
 *       what the answer is.
 * @note Rows are printed as a sign and the limbs in hex, least significant first. Rendering a
 *       decimal here would need division, which this representation does not implement, and would
 *       put a second thing to be wrong between the arithmetic and the check.
 */

#include "exact_limbs.h"

#include <stdio.h>
#include <string.h>

/** @brief Values every operation below is run over. Deposited crystal numbers and awkward cases. */
static const char *const SUBJECTS[] = {
    "4.76050", "0.35216", "10.1000", "8.6633", "14.0574", "0", "1", "-1", "0.000001",
    "999999999.999999999", "3.1049", "-11.4085", "0.5", "2", "4.76050(5)", "1000000000000",
};

/** @brief How many subjects, for a driver that has to pair every one with every other. */
#define SUBJECT_COUNT (sizeof(SUBJECTS) / sizeof(SUBJECTS[0]))

/** @brief Decimal places every subject is carried at. Matches representation.exact by default. */
#define PLACES 24u

/**
 * @brief Prints one integer as a sign and its limbs in hex.
 *
 * @param[in] label What the row is [BORROWS].
 * @param[in] value The integer [BORROWS].
 */
static void emit(const char *label, const AnchorExactInteger *value)
{
    printf("%s %d", label, (int)value->sign);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        printf(" %08x", value->limb[at]);
    }
    printf("\n");
}

/**
 * @brief Prints a row saying an operation refused, keeping a refusal checkable and not a gap.
 *
 * @param[in] label  What the row is [BORROWS].
 * @param[in] status What the operation returned.
 */
static void emit_status(const char *label, AnchorExactStatus status)
{
    printf("%s refused %d\n", label, (int)status);
}

/**
 * @brief Runs every unary and binary operation over the subjects and prints each result.
 */
static void run_arithmetic(void)
{
    AnchorExactInteger held[SUBJECT_COUNT];
    char label[128];

    for (size_t at = 0u; at < SUBJECT_COUNT; at++)
    {
        const AnchorExactStatus status =
            anchor_exact_from_decimal(SUBJECTS[at], strlen(SUBJECTS[at]), PLACES, &held[at]);
        // The subject text rides along on the row, which keeps the checker from carrying a second
        // copy of this list to drift against.
        (void)snprintf(label, sizeof(label), "read %u %s", (unsigned)at, SUBJECTS[at]);
        if (status != ANCHOR_EXACT_OK)
        {
            emit_status(label, status);
            anchor_exact_zero(&held[at]);
            continue;
        }
        emit(label, &held[at]);
    }

    for (size_t low = 0u; low < SUBJECT_COUNT; low++)
    {
        for (size_t high = 0u; high < SUBJECT_COUNT; high++)
        {
            AnchorExactInteger result;

            (void)snprintf(label, sizeof(label), "add %u %u", (unsigned)low, (unsigned)high);
            AnchorExactStatus status = anchor_exact_add(&held[low], &held[high], &result);
            if (status == ANCHOR_EXACT_OK) { emit(label, &result); }
            else { emit_status(label, status); }

            (void)snprintf(label, sizeof(label), "sub %u %u", (unsigned)low, (unsigned)high);
            status = anchor_exact_subtract(&held[low], &held[high], &result);
            if (status == ANCHOR_EXACT_OK) { emit(label, &result); }
            else { emit_status(label, status); }

            (void)snprintf(label, sizeof(label), "mul %u %u", (unsigned)low, (unsigned)high);
            status = anchor_exact_multiply(&held[low], &held[high], &result);
            if (status == ANCHOR_EXACT_OK) { emit(label, &result); }
            else { emit_status(label, status); }

            (void)snprintf(label, sizeof(label), "cmp %u %u", (unsigned)low, (unsigned)high);
            printf("%s %d %d\n", label, anchor_exact_compare(&held[low], &held[high]),
                   anchor_exact_equal(&held[low], &held[high]));
        }
    }
}

/**
 * @brief Builds a run with a known period and prints the agreement count at a sweep of lags.
 *
 * @note The period is planted, so what the count should be is arithmetic and not a measurement.
 *       Every lag that divides the run's step agrees at every position that has a neighbor, and no
 *       other lag agrees anywhere. The checker recomputes both from the same plan.
 */
static void run_agreement(void)
{
    enum { PLACES_IN_RUN = 64 };
    AnchorExactInteger positions[PLACES_IN_RUN];
    uint64_t values[PLACES_IN_RUN];
    char label[128];

    // A run stepping by 0.25 with the value cycling every four places, which is a period of one
    // whole unit in a set whose positions repeat four times as often.
    for (size_t at = 0u; at < (size_t)PLACES_IN_RUN; at++)
    {
        char text[64];
        (void)snprintf(text, sizeof(text), "%u.%02u", (unsigned)(at / 4u),
                       (unsigned)((at % 4u) * 25u));
        const AnchorExactStatus status =
            anchor_exact_from_decimal(text, strlen(text), PLACES, &positions[at]);
        if (status != ANCHOR_EXACT_OK)
        {
            printf("run refused at %u\n", (unsigned)at);
            return;
        }
        values[at] = (uint64_t)(at % 4u);
    }

    for (unsigned step = 1u; step <= 12u; step++)
    {
        char text[64];
        AnchorExactInteger lag;
        (void)snprintf(text, sizeof(text), "%u.%02u", step / 4u, (step % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &lag) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        const size_t agreed =
            anchor_exact_agreement(positions, values, (size_t)PLACES_IN_RUN, &lag);
        (void)snprintf(label, sizeof(label), "agree %s", text);
        printf("%s %u\n", label, (unsigned)agreed);
    }
}

int main(void)
{
    printf("limbs %u places %u\n", (unsigned)ANCHOR_EXACT_LIMBS, (unsigned)PLACES);
    run_arithmetic();
    run_agreement();
    return 0;
}
