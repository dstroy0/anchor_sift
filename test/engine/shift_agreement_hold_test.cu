// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// shift_agreement_hold_bytes against sums worked by hand from the layout: the pool's six slices, each on 256 bytes,
// rounded up to the 2 MiB page once, and the negation and root tables rounded up to the page together. The test is
// host arithmetic and touches no device.
#include "shift_agreement.h"

#include <stdio.h>

typedef struct
{
    unsigned int checks;
    unsigned int failures;
} HoldTestTally;

static void hold_test_check(HoldTestTally *tally, int held, const char *what)
{
    tally->checks += 1u;
    if (held == 0)
    {
        tally->failures += 1u;
        printf("  FAILED: %s\n", what);
    }
}

int main(void)
{
    HoldTestTally tally = {0u, 0u};

    // padded 128 x 512 x 512, 2^25 elements, 65536 words: the words 524288 bytes each, the volumes 2^27 each, the
    // slices end at 537919488, 257 pages; the tables 1 + 1152 + 256 + 1024 entries, 9732 bytes, one page
    const unsigned int frame[3] = {64u, 256u, 256u};
    hold_test_check(&tally, shift_agreement_hold_bytes(3u, frame) == 541065216ull,
                    "64 x 256 x 256 holds 257 pages of pool and one of tables");

    // padded 1: every slice under 256 bytes, the slices end at 1284, one page; the tables 2 entries, one page
    const unsigned int point[1] = {1u};
    hold_test_check(&tally, shift_agreement_hold_bytes(1u, point) == 4194304ull, "one voxel holds one page of each");

    // padded 2^23 and 1: the words 524288 bytes each, the volumes 2^25 each, the slices end at 135266304, 65 pages;
    // the tables 1 + 2^23 + 1 + 2^24 entries, 100663304 bytes, 49 pages
    const unsigned int longest[2] = {1u << 22u, 1u};
    hold_test_check(&tally, shift_agreement_hold_bytes(2u, longest) == 239075328ull,
                    "the longest axis holds 65 pages of pool and 49 of tables");

    const unsigned int empty[1] = {0u};
    const unsigned int past[1] = {(1u << 22u) + 1u};
    const unsigned int at_prime[2] = {32768u, 32768u};
    const unsigned int past_total[2] = {40000u, 20000u};
    const unsigned int nine[9] = {1u, 1u, 1u, 1u, 1u, 1u, 1u, 1u, 1u};
    hold_test_check(&tally, shift_agreement_hold_bytes(0u, frame) == 0ull, "no axes is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(9u, nine) == 0ull, "nine axes is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(1u, NULL) == 0ull, "no extents is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(1u, empty) == 0ull, "an extent of 0 is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(1u, past) == 0ull, "an extent past 2^22 is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(2u, at_prime) == 0ull, "2^30 voxels, past the prime, is refused");
    hold_test_check(&tally, shift_agreement_hold_bytes(2u, past_total) == 0ull,
                    "a padded total of 2^17 x 2^16, past 2^31 - 1, is refused");

    printf("  shift_agreement hold test: %u checks, %u failed\n", tally.checks, tally.failures);
    return (tally.failures == 0u) ? 0 : 1;
}
