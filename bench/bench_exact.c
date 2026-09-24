// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "exact_integer.h"

#include <stdio.h>
#include <string.h>

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

#define SUBJECT_COUNT (sizeof(SUBJECTS) / sizeof(SUBJECTS[0]))

#define PLACES_HELD ((((unsigned long long)ANCHOR_EXACT_BITS - 5ull) * 30102ull) / 100000ull)

#define PLACES ((PLACES_HELD < 24ull) ? (uint32_t)PLACES_HELD : 24u)

#if defined(__cplusplus)
static_assert(PLACES_HELD >= 2ull, "the narrowest width must hold the two places a quarter step takes");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert(PLACES_HELD >= 2ull, "the narrowest width must hold the two places a quarter step takes");
#else
typedef char bench_exact_places_hold_a_quarter[(PLACES_HELD >= 2ull) ? 1 : -1];
#endif

#define WIDE_DIGITS ((((unsigned long long)ANCHOR_EXACT_BITS * 30103ull) / 100000ull) + 2ull)

#define SCALE_PAST_WIDTH ((uint32_t)WIDE_DIGITS)

static void emit_text(const char *text)
{
    const size_t length = strlen(text);
    for (size_t at = 0u; at < length; at++)
    {
        printf("%02x", (unsigned int)(unsigned char)text[at]);
    }
}

static void emit_limbs(const AnchorExactInteger *value)
{
    size_t used = (size_t)ANCHOR_EXACT_LIMBS;
    while ((used > 0u) && (value->limb[used - 1u] == 0u))
    {
        used--;
    }
    printf(" %d %u", (int)value->sign, (unsigned)used);
    for (size_t at = 0u; at < used; at++)
    {
        printf(" %08x", value->limb[at]);
    }
}

static void emit(const char *label, const AnchorExactInteger *value)
{
    printf("%s", label);
    emit_limbs(value);
    printf("\n");
}

static void emit_status(const char *label, AnchorExactStatus status)
{
    printf("%s refused %d\n", label, (int)status);
}

static void set_sentinel(AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        value->limb[at] = 0x5A5A5A5Au ^ (uint32_t)at;
    }
    value->sign = -1;
}

static void read_subject(size_t index, const char *text, AnchorExactInteger *held)
{
    const size_t length = strlen(text);

    static AnchorExactInteger sentinel;
    set_sentinel(&sentinel);
    static AnchorExactInteger value;
    set_sentinel(&value);
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

    static AnchorExactInteger measured;
    static AnchorExactInteger uncertainty;
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

static void run_arithmetic(void)
{
    static char wide[WIDE_DIGITS + 1ull];
    memset(wide, '9', (size_t)WIDE_DIGITS);
    wide[WIDE_DIGITS] = '\0';

    const size_t total = SUBJECT_COUNT + 1u;
    static AnchorExactInteger held[SUBJECT_COUNT + 1u];
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
            static AnchorExactInteger result;

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

static void run_refusals(void)
{
    static AnchorExactInteger seven;
    (void)anchor_exact_from_decimal("7", 1u, 0u, &seven);
    static AnchorExactInteger scaled;
    scaled = seven;
    const AnchorExactStatus scale_status = anchor_exact_scale_by_ten(&scaled, SCALE_PAST_WIDTH);
    printf("keep scale %d %d\n", (int)scale_status,
           ((scale_status != ANCHOR_EXACT_OK) && (memcmp(&scaled, &seven, sizeof(scaled)) == 0))
               ? 1 : 0);

    static AnchorExactInteger largest;
    memset(largest.limb, 0xFF, sizeof(largest.limb));
    largest.sign = 1;

    static AnchorExactInteger sentinel;
    set_sentinel(&sentinel);
    static AnchorExactInteger result;
    set_sentinel(&result);
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

static void run_agreement(void)
{
    enum { PLACES_IN_RUN = 64 };
    static AnchorExactInteger positions[PLACES_IN_RUN];
    uint64_t values[PLACES_IN_RUN];
    char label[128];

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
        static AnchorExactInteger lag;
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

static const char *const REPEATED_POSITIONS[] = {
    "2.00", "0.25", "1.00", "0.25", "0.50", "2.00", "1.25", "0.75", "1.00", "0.00", "1.50", "0.50",
};

static const uint64_t REPEATED_VALUES[] = {1u, 2u, 3u, 4u, 1u, 2u, 3u, 4u, 1u, 2u, 3u, 4u};

static void run_repeated_agreement(void)
{
    enum { ENTRIES = sizeof(REPEATED_POSITIONS) / sizeof(REPEATED_POSITIONS[0]) };
    static AnchorExactInteger positions[ENTRIES];
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
        static AnchorExactInteger lag;
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
