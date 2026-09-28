// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// shift_agreement_reserve_bytes against sums worked by hand from the layout: the pool's six slices, each on 256 bytes,
// rounded up to the 2 MiB page once, and the negation and root tables rounded up to the page together. The test is
// host arithmetic and touches no device.
#include "shift_agreement.h"

#include <stdio.h>

typedef struct
{
    unsigned int checks;
    unsigned int failures;
} AgreementTestResults;

static void agreement_test_check(AgreementTestResults *results, int passed, const char *what)
{
    results->checks += 1u;
    if (passed == 0)
    {
        results->failures += 1u;
        printf("  FAILED: %s\n", what);
    }
}

int main(void)
{
    AgreementTestResults results = {0u, 0u};

    // padded 128 x 512 x 512, 2^25 elements, 65536 words: the words 524288 bytes each, the volumes 2^27 each, the
    // slices end at 537919488, 257 pages; the tables 1 + 1152 + 256 + 1024 entries, 9732 bytes, one page
    const unsigned int frame[3] = {64u, 256u, 256u};
    agreement_test_check(&results, shift_agreement_reserve_bytes(3u, frame) == 541065216ull,
                         "64 x 256 x 256 holds 257 pages of pool and one of tables");

    // padded 1: every slice under 256 bytes, the slices end at 1284, one page; the tables 2 entries, one page
    const unsigned int point[1] = {1u};
    agreement_test_check(&results, shift_agreement_reserve_bytes(1u, point) == 4194304ull,
                         "one voxel holds one page of each");

    // padded 2^23 and 1: the words 524288 bytes each, the volumes 2^25 each, the slices end at 135266304, 65 pages;
    // the tables 1 + 2^23 + 1 + 2^24 entries, 100663304 bytes, 49 pages
    const unsigned int longest[2] = {1u << 22u, 1u};
    agreement_test_check(&results, shift_agreement_reserve_bytes(2u, longest) == 239075328ull,
                         "the longest axis holds 65 pages of pool and 49 of tables");

    const unsigned int empty[1] = {0u};
    const unsigned int over_limit[1] = {(1u << 22u) + 1u};
    const unsigned int at_prime[2] = {32768u, 32768u};
    const unsigned int over_limit_total[2] = {40000u, 20000u};
    const unsigned int nine[9] = {1u, 1u, 1u, 1u, 1u, 1u, 1u, 1u, 1u};
    agreement_test_check(&results, shift_agreement_reserve_bytes(0u, frame) == 0ull, "no axes is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(9u, nine) == 0ull, "nine axes is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(1u, NULL) == 0ull, "no extents is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(1u, empty) == 0ull, "an extent of 0 is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(1u, over_limit) == 0ull,
                         "an extent past 2^22 is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(2u, at_prime) == 0ull,
                         "2^30 voxels, past the prime, is refused");
    agreement_test_check(&results, shift_agreement_reserve_bytes(2u, over_limit_total) == 0ull,
                         "a padded total of 2^17 x 2^16, past 2^31 - 1, is refused");

    printf("  shift_agreement hold test: %u checks, %u failed\n", results.checks, results.failures);
    return (results.failures == 0u) ? 0 : 1;
}
