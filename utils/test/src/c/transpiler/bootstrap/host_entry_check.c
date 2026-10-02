// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// host_entry_check.c: the kind an address shows and the width a sizing register names, read from the two words put
// and the word given back, with no bus. The reads and writes themselves are held elsewhere (query_interface_check.c);
// here the decision over the read-back words and the width over a sizing register's mask are put their own values
#include "../../../../../../src/c/transpiler/bootstrap/host_entry.h"

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

int main(void)
{
    // the four kinds, each from the words a register of that kind gives back
    check_that(host_address_classify(HOST_ASKED_FIRST, HOST_ASKED_THEN) == HOST_HOLDS,
               "a register that gives back each word it was put holds");
    check_that(host_address_classify(HOST_NO_ANSWER, HOST_NO_ANSWER) == HOST_NOTHING,
               "an address that gives back all ones twice answers nothing");
    check_that(host_address_classify(0x00001234u, 0x00001234u) == HOST_FIXED,
               "a register that gives back one constant whatever it was put is fixed");
    check_that(host_address_classify(0xa5a50000u, 0x5a5a0000u) == HOST_LIVE,
               "a sizing register that masks each word it was put is live");
    check_that(host_address_classify(0x0000ffffu, 0xffff0000u) == HOST_LIVE,
               "a register that gives back two words of its own is live");

    // a register that holds all ones unwritten reads nothing, not a fixed constant
    check_that(host_address_classify(HOST_NO_ANSWER, HOST_NO_ANSWER) != HOST_FIXED,
               "all ones twice is nothing and not a fixed constant");
    // a register that holds the first word but not the second decided the second: it is live, not holding
    check_that(host_address_classify(HOST_ASKED_FIRST, 0x11111111u) == HOST_LIVE,
               "holding only the first word put is live and not holding");

    // the width a sizing register names: the low zero bits it forces when all ones are put to it
    check_that(host_width(0xffffffffu) == 0u, "a register that holds all ones decodes no width");
    check_that(host_width(0xfffff000u) == 12u, "twelve low zero bits name a width of twelve");
    check_that(host_width(0xffff0000u) == 16u, "sixteen low zero bits name a width of sixteen");
    check_that(host_width(0xfffffffeu) == 1u, "one low zero bit names a width of one");
    check_that(host_width(0x00000000u) == 32u, "all zero decodes every one of the word's bits");

    printf("  host entry: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
