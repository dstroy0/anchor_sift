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
 * @note Subject text is printed as the hex of its bytes. Several subjects carry spaces, tabs and
 *       line feeds, and a row split on whitespace would cut them apart.
 */

#include "exact_integer.h"

#include <stdio.h>
#include <string.h>

/**
 * @brief Values every operation below is run over. Deposited crystal numbers and awkward cases.
 *
 * @note The second group are contract cases, not arithmetic ones. A cross check against a second
 *       implementation found this arm refusing 1.2300 at a scale that accepted 1.23, which is a
 *       refusal to hold a value that needed no rounding. They are here so the same divergence
 *       cannot return without a row moving.
 * @note The third group are grammar cases found on 2026-09-16. This arm read "1.2(3)4" as 1.2 where
 *       representation.exact read 1.24, accepted trailing text after a space or a bracket that the
 *       python side refused, and both arms refused ".000", a zero.
 * @note The fourth group are uncertainty cases for anchor_exact_from_measured, which counts the
 *       bracketed digits in units of the last place printed.
 */
static const char *const SUBJECTS[] = {
    "4.76050", "0.35216", "10.1000", "8.6633", "14.0574", "0", "1", "-1", "0.000001",
    "999999999.999999999", "3.1049", "-11.4085", "0.5", "2", "4.76050(5)", "1000000000000",

    "1.2300", "1.0000000000000000000000000", "4.7605000000000000000000000", "1.", ".5", "-0",
    "0.000000000000000000000000000", "1.0000000000000000000000001", ".", "1.2.3", "1e6",

    ".000", ".000(1)", "-.000(1)", "1.2(3)4", "1.23 xyz", "1.23(", "1.23(4)junk", " 1.5 ",
    "\n1.5\r\n", "1.23()", "(3)", "5.(3)", "- 5", "+.5", "++1", "1.5\v", "\xef\xbc\x91",
    "\xd9\xa3", "\t-4.76050(5) ", ".(3)", "1.23)", "1(",

    "1.2300(5)", "1.230(10)", "137(2)", "7.2973525643(11)", "0.000000000000000000000001(1)",
    "1.00000000000000000000000000(1)", "1(0)",
};

/** @brief How many subjects, for a driver that has to pair every one with every other. */
#define SUBJECT_COUNT (sizeof(SUBJECTS) / sizeof(SUBJECTS[0]))

/**
 * @brief Decimal places every subject is carried at.
 *
 * @note Smaller than the 1024 places representation.exact ingests at. A product of two subjects at
 *       24 places sits at 48 places and fits the width, which lets the multiply rows check products
 *       and not only refusals.
 */
#define PLACES 24u

/** @brief Digits in the one subject built at run time to overrun the width. */
#define WIDE_DIGITS 1100u

/**
 * @brief Prints the bytes of a text as lowercase hex, with no separator.
 *
 * @param[in] text Text to print [BORROWS].
 */
static void emit_text(const char *text)
{
    const size_t length = strlen(text);
    for (size_t at = 0u; at < length; at++)
    {
        // The byte is printed as its unsigned value. A char above 0x7F is negative where char is
        // signed, and printing it through int would print a sign-extended value.
        printf("%02x", (unsigned int)(unsigned char)text[at]);
    }
}

/**
 * @brief Prints one integer as a sign and its limbs in hex.
 *
 * @param[in] value The integer [BORROWS].
 */
static void emit_limbs(const AnchorExactInteger *value)
{
    printf(" %d", (int)value->sign);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        printf(" %08x", value->limb[at]);
    }
}

/**
 * @brief Prints one integer as a labeled row.
 *
 * @param[in] label What the row is [BORROWS].
 * @param[in] value The integer [BORROWS].
 */
static void emit(const char *label, const AnchorExactInteger *value)
{
    printf("%s", label);
    emit_limbs(value);
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
 * @brief Sets an integer to a recognizable nonzero value, for checking that a refusal left it.
 *
 * @param[out] value Integer to set [BORROWS].
 */
static void set_sentinel(AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        // A limb index is below ANCHOR_EXACT_LIMBS, so it fits the uint32_t it is folded into.
        value->limb[at] = 0x5A5A5A5Au ^ (uint32_t)at;
    }
    value->sign = -1;
}

/**
 * @brief Reads one subject both ways and prints its read, measured and keep rows.
 *
 * @param[in]  index Subject index, printed on every row.
 * @param[in]  text  Subject text [BORROWS].
 * @param[out] held  Where the read value is kept for the arithmetic, zero where refused [BORROWS].
 */
static void read_subject(size_t index, const char *text, AnchorExactInteger *held)
{
    const size_t length = strlen(text);

    AnchorExactInteger value;
    set_sentinel(&value);
    const AnchorExactInteger sentinel = value;
    const AnchorExactStatus status = anchor_exact_from_decimal(text, length, PLACES, &value);
    printf("read %u ", (unsigned)index);
    emit_text(text);
    if (status != ANCHOR_EXACT_OK)
    {
        printf(" refused %d\n", (int)status);
        printf("keep read %u %d\n", (unsigned)index,
               (memcmp(&value, &sentinel, sizeof(value)) == 0) ? 1 : 0);
        anchor_exact_zero(held);
    }
    else
    {
        emit_limbs(&value);
        printf("\n");
        *held = value;
    }

    AnchorExactInteger measured;
    AnchorExactInteger uncertainty;
    int carried = 7;
    set_sentinel(&measured);
    set_sentinel(&uncertainty);
    const AnchorExactStatus measured_status =
        anchor_exact_from_measured(text, length, PLACES, &measured, &uncertainty, &carried);
    printf("meas %u ", (unsigned)index);
    emit_text(text);
    if (measured_status != ANCHOR_EXACT_OK)
    {
        printf(" refused %d\n", (int)measured_status);
        const int unchanged = (memcmp(&measured, &sentinel, sizeof(measured)) == 0)
                              && (memcmp(&uncertainty, &sentinel, sizeof(uncertainty)) == 0)
                              && (carried == 7);
        printf("keep meas %u %d\n", (unsigned)index, unchanged ? 1 : 0);
    }
    else
    {
        printf(" %d", carried);
        emit_limbs(&measured);
        emit_limbs(&uncertainty);
        printf("\n");
    }
}

/**
 * @brief Runs every unary and binary operation over the subjects and prints each result.
 */
static void run_arithmetic(void)
{
    static char wide[WIDE_DIGITS + 1u];
    memset(wide, '9', WIDE_DIGITS);
    wide[WIDE_DIGITS] = '\0';

    const size_t total = SUBJECT_COUNT + 1u;
    AnchorExactInteger held[SUBJECT_COUNT + 1u];
    char label[128];

    for (size_t at = 0u; at < SUBJECT_COUNT; at++)
    {
        read_subject(at, SUBJECTS[at], &held[at]);
    }
    read_subject(SUBJECT_COUNT, wide, &held[SUBJECT_COUNT]);

    for (size_t low = 0u; low < total; low++)
    {
        for (size_t high = 0u; high < total; high++)
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
 * @brief Checks that a refused scale, add and multiply leave their output as it was.
 *
 * @note Each prints a keep row the checker requires to read 1. anchor_exact_scale_by_ten once wrote
 *       the low limbs of an overrun product into its value before refusing.
 */
static void run_refusals(void)
{
    AnchorExactInteger seven;
    (void)anchor_exact_from_decimal("7", 1u, 0u, &seven);
    AnchorExactInteger scaled = seven;
    const AnchorExactStatus scale_status = anchor_exact_scale_by_ten(&scaled, 2000u);
    printf("keep scale %d %d\n", (int)scale_status,
           ((scale_status != ANCHOR_EXACT_OK) && (memcmp(&scaled, &seven, sizeof(scaled)) == 0))
               ? 1 : 0);

    AnchorExactInteger largest;
    memset(largest.limb, 0xFF, sizeof(largest.limb));
    largest.sign = 1;

    AnchorExactInteger result;
    set_sentinel(&result);
    const AnchorExactInteger sentinel = result;
    const AnchorExactStatus add_status = anchor_exact_add(&largest, &largest, &result);
    printf("keep add %d %d\n", (int)add_status,
           ((add_status != ANCHOR_EXACT_OK) && (memcmp(&result, &sentinel, sizeof(result)) == 0))
               ? 1 : 0);

    set_sentinel(&result);
    const AnchorExactStatus multiply_status = anchor_exact_multiply(&largest, &largest, &result);
    printf("keep mul %d %d\n", (int)multiply_status,
           ((multiply_status != ANCHOR_EXACT_OK)
            && (memcmp(&result, &sentinel, sizeof(result)) == 0)) ? 1 : 0);
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

/**
 * @brief The positions of the run with repeats, in the order they are listed.
 *
 * @note Unsorted, with 0.25, 0.50, 1.00 and 2.00 each listed twice carrying two different values.
 *       check_exact_limbs.py holds its own copy of this plan and of REPEATED_VALUES, and builds the
 *       count from a dict, which keeps the last value at a repeated position.
 */
static const char *const REPEATED_POSITIONS[] = {
    "2.00", "0.25", "1.00", "0.25", "0.50", "2.00", "1.25", "0.75", "1.00", "0.00", "1.50", "0.50",
};

/** @brief The value standing at each entry of REPEATED_POSITIONS. */
static const uint64_t REPEATED_VALUES[] = {1u, 2u, 3u, 4u, 1u, 2u, 3u, 4u, 1u, 2u, 3u, 4u};

/**
 * @brief Prints the agreement count over the run with repeats at lags 0 through 2 in quarters.
 *
 * @note At lag 0 every distinct position agrees with itself. The count is then the number of
 *       distinct positions, and an arm counting every entry reads more.
 */
static void run_repeated_agreement(void)
{
    enum { ENTRIES = sizeof(REPEATED_POSITIONS) / sizeof(REPEATED_POSITIONS[0]) };
    AnchorExactInteger positions[ENTRIES];
    for (size_t at = 0u; at < (size_t)ENTRIES; at++)
    {
        if (anchor_exact_from_decimal(REPEATED_POSITIONS[at], strlen(REPEATED_POSITIONS[at]),
                                      PLACES, &positions[at]) != ANCHOR_EXACT_OK)
        {
            printf("repeated run refused at %u\n", (unsigned)at);
            return;
        }
    }

    for (unsigned step = 0u; step <= 8u; step++)
    {
        char text[64];
        AnchorExactInteger lag;
        (void)snprintf(text, sizeof(text), "%u.%02u", step / 4u, (step % 4u) * 25u);
        if (anchor_exact_from_decimal(text, strlen(text), PLACES, &lag) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        const size_t agreed =
            anchor_exact_agreement(positions, REPEATED_VALUES, (size_t)ENTRIES, &lag);
        printf("agreerep %s %u\n", text, (unsigned)agreed);
    }
}

int main(void)
{
    printf("limbs %u places %u\n", (unsigned)ANCHOR_EXACT_LIMBS, (unsigned)PLACES);
    run_arithmetic();
    run_refusals();
    run_agreement();
    run_repeated_agreement();
    return 0;
}
