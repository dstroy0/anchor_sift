// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// bus_enum_check.c: the classify ask and the width ask over memory the test owns, the enumeration region found in a
// run of kinds, and the classify walk driven over a span of addresses in probes the interface can lose.
//
//     bus_enum_check <classify_walk> <output file>
//
// The region finder is put runs of kinds a walk would have read. Given the classify_walk program the walk runs too,
// over low addresses nothing maps, where every address ends its probe and the region is none.
#include "../../../../../../src/c/transpiler/bootstrap/bus_enum_walk.h"

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

static int find(const unsigned int *kinds, unsigned long long count, unsigned long long *base,
                unsigned long long *stride, unsigned long long *records)
{
    *base = 0ull;
    *stride = 0ull;
    *records = 0ull;
    return bus_enum_find(kinds, count, base, stride, records);
}

int main(int count_of_words, char **words)
{
    // the classify ask and the width ask over memory the test owns: it holds what the ask puts, is left as it was
    // found, and sized gives width 0, since memory gives back the ones it was put
    static volatile unsigned int owned[4] = {0x01020304u, 0u, 0xdeadbeefu, 0xffffffffu};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        const unsigned int was = owned[at];
        unsigned int read_back = 0u;
        const unsigned int kind = host_address_ask((unsigned long long)(unsigned long long *)&owned[at], &read_back);
        check_that(kind == HOST_HOLDS, "memory the test owns holds what the ask puts");
        const unsigned int width = host_width_ask((unsigned long long)(unsigned long long *)&owned[at]);
        check_that(width == 0u, "memory sized gives width 0, since it holds the ones it was put");
        check_that(owned[at] == was, "the ask leaves memory it read as it found it");
    }

    // a clean region: records at samples 2, 6, 10, every four samples apart
    const unsigned int clean[14] = {
        HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED, HOST_LIVE, HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED, HOST_LIVE, HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED, HOST_LIVE, HOST_HOLDS, HOST_HOLDS};
    unsigned long long base = 0ull;
    unsigned long long stride = 0ull;
    unsigned long long records = 0ull;
    check_that(find(clean, 14ull, &base, &stride, &records) == 1, "a region of three records is found");
    check_that((base == 2ull) && (stride == 4ull) && (records == 3ull),
               "the region begins at sample 2, strides by 4, and holds 3 records");

    // an empty slot at sample 10: records at 2, 6, 14; the gaps 4 and 8 keep the stride at 4
    const unsigned int gapped[18] = {
        HOST_HOLDS,   HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,    HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,    HOST_HOLDS, HOST_HOLDS,
        HOST_NOTHING, HOST_NOTHING, HOST_HOLDS, HOST_HOLDS,
        HOST_FIXED,   HOST_LIVE,    HOST_HOLDS, HOST_HOLDS};
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

    // the records read out of a region: each FIXED identifier, and each LIVE sizing register's width from its mask
    const unsigned int list_values[14] = {
        0u, 0u,
        0x0000aa01u, 0xfffff000u, 0u, 0u,
        0x0000aa02u, 0xffff0000u, 0u, 0u,
        0x0000aa03u, 0xffffff00u, 0u, 0u};
    BusRecord out[4] = {{0}, {0}, {0}, {0}};
    const unsigned long long listed = bus_enum_list(clean, list_values, 14ull, out, 4ull);
    check_that(listed == 3ull, "three records are read out of the region");
    check_that((out[0].sample == 2ull) && (out[0].identifier == 0x0000aa01u) && (out[0].width == 12u),
               "the first record's identifier and its sizing register's width of 12 are read");
    check_that((out[1].identifier == 0x0000aa02u) && (out[1].width == 16u),
               "the second record names width 16");
    check_that((out[2].identifier == 0x0000aa03u) && (out[2].width == 8u),
               "the third record names width 8");

    // an empty slot is passed over: records at 2, 6, 14 read out as three, the slot at 10 left out
    const unsigned int gap_values[18] = {
        0u, 0u,
        0x0000bb01u, 0xfffff000u, 0u, 0u,
        0x0000bb02u, 0xffff0000u, 0u, 0u,
        0u, 0u, 0u, 0u,
        0x0000bb03u, 0xfff00000u, 0u, 0u};
    BusRecord gap_out[4] = {{0}, {0}, {0}, {0}};
    const unsigned long long gap_listed = bus_enum_list(gapped, gap_values, 18ull, gap_out, 4ull);
    check_that(gap_listed == 3ull, "a region with an empty slot reads out its three present records");
    check_that((gap_out[2].sample == 14ull) && (gap_out[2].identifier == 0x0000bb03u) && (gap_out[2].width == 20u),
               "the third present record sits at sample 14 with width 20");

    // room for fewer records than the region holds caps what is read out
    BusRecord two_out[2] = {{0}, {0}};
    check_that(bus_enum_list(clean, list_values, 14ull, two_out, 2ull) == 2ull, "room for two caps the read at two");

    // flat memory reads out no records
    BusRecord none_out[1] = {{0}};
    check_that(bus_enum_list(flat, flat, 6ull, none_out, 1ull) == 0ull, "flat memory reads out no records");

    // the classify walk driven over low addresses nothing maps: each ends its probe and reads as nothing
    if (count_of_words == 3)
    {
        static unsigned int kinds[4] = {0u, 0u, 0u, 0u};
        QueryWalk walk = {0};
        walk.program = words[1];
        walk.output_path = words[2];
        walk.from = 0ull;
        walk.count = 4ull;
        walk.stride = 0x1000ull;
        walk.limit_microseconds = 2000000ull;
        unsigned long long walk_base = 0ull;
        unsigned long long walk_stride = 0ull;
        unsigned long long walk_records = 0ull;
        EngineError error = {0};
        const int region = bus_enum_walk(&walk, kinds, &walk_base, &walk_stride, &walk_records, &error);
        check_that(region == 0, "low addresses nothing maps are no enumeration region");
        int all_nothing = 1;
        for (unsigned int at = 0u; at < 4u; at += 1u)
        {
            all_nothing = (kinds[at] == HOST_NOTHING) ? all_nothing : 0;
        }
        check_that(all_nothing == 1, "each address a probe asked there ended it and reads as nothing");
    }

    printf("  bus enum: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
