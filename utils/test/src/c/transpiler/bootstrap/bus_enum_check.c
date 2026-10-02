// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// bus_enum_check.c: the classify ask over memory the test owns, and the enumeration region found in a run of kinds.
// The ask reads and writes real addresses here; the region finder is put runs of kinds a walk would have read.
#include "../../../../../../src/c/transpiler/bootstrap/bus_enum.h"

#include <stdio.h>

static unsigned int s_checks = 0u;
static unsigned int s_failed = 0u;

static void check_that(int held, const char *what)
{
    s_checks += 1u;
    if (held == 0)
    {
        s_failed += 1u;
        printf("  FAILED: %s\n", what);
    }
}

// the first record's sample, the samples between records, and the records, from a run of kinds
static int find(const unsigned int *kinds, unsigned long long count, unsigned long long *base,
                unsigned long long *stride, unsigned long long *records)
{
    *base = 0ull;
    *stride = 0ull;
    *records = 0ull;
    return bus_enum_find(kinds, count, base, stride, records);
}

int main(void)
{
    // the classify ask over memory the test owns: each word holds what it was put, and is left as it was found
    static volatile unsigned int owned[4] = {0x01020304u, 0u, 0xdeadbeefu, 0xffffffffu};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        const unsigned int was = owned[at];
        unsigned int read_back = 0u;
        const unsigned int kind = host_address_ask((unsigned long long)(unsigned long long *)&owned[at], &read_back);
        check_that(kind == HOST_HOLDS, "memory the test owns holds what the ask puts");
        check_that(owned[at] == was, "the ask leaves memory it read as it found it");
    }

    // a clean region: records at samples 2, 6, 10, every four samples apart
    const unsigned int clean[14] = {
        HOST_HOLDS,   HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS};
    unsigned long long base = 0ull;
    unsigned long long stride = 0ull;
    unsigned long long records = 0ull;
    check_that(find(clean, 14ull, &base, &stride, &records) == 1, "a region of three records is found");
    check_that((base == 2ull) && (stride == 4ull) && (records == 3ull),
               "the region begins at sample 2, strides by 4, and holds 3 records");

    // an empty slot: records at 2 and 14, a slot at 10 answering nothing; the gaps 4 and 8 keep the stride at 4
    const unsigned int gapped[18] = {
        HOST_HOLDS,   HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS,
        HOST_NOTHING, HOST_NOTHING, HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,  HOST_HOLDS, HOST_HOLDS};
    check_that(find(gapped, 18ull, &base, &stride, &records) == 1, "a region with an empty slot is found");
    check_that((base == 2ull) && (stride == 4ull) && (records == 3ull),
               "an empty slot leaves the stride at 4 over its three present records");

    // flat memory is no region
    const unsigned int flat[6] = {HOST_HOLDS, HOST_HOLDS, HOST_HOLDS, HOST_HOLDS, HOST_HOLDS, HOST_HOLDS};
    check_that(find(flat, 6ull, &base, &stride, &records) == 0, "flat memory is no enumeration region");

    // a FIXED with no LIVE next to it is no record
    const unsigned int lonely[6] = {HOST_HOLDS, HOST_FIXED, HOST_HOLDS, HOST_HOLDS, HOST_FIXED, HOST_HOLDS};
    check_that(find(lonely, 6ull, &base, &stride, &records) == 0,
               "a fixed identifier with no sizing register beside it is no record");

    // one record alone is no region
    const unsigned int alone[4] = {HOST_HOLDS, HOST_FIXED, HOST_LIVE, HOST_HOLDS};
    check_that(find(alone, 4ull, &base, &stride, &records) == 0, "one record alone is no region");

    printf("  bus enum: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
