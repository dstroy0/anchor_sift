// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chain_check.c: how much of a relation the ladder's own cases decide
//
// A ladder climbs by putting a few small words and reading what comes back. This builds each relation's chains
// twice: once against those cases alone, and once against the relation on words the cases do not carry. The gap is
// the count of arrangements the cases let through that are not the relation at all - right about the words they
// were fitted to and wrong about the rest.
//
// That gap is the reading this exists for. It is how many answers a target can give before an answer means
// anything, and a case added to the ladder is worth adding exactly insofar as it closes it.
#include "../../../../src/engine/compiler/bootstrap/chain_build.h"

#include <stdio.h>
#include <string.h>

#define LADDER_TEXT(name_, text_, words_, measured_) text_,
static const char *const s_anchor_text[] = {LADDER_ANCHORS(LADDER_TEXT)};
#undef LADDER_TEXT

static unsigned int anchor_cases(unsigned int anchor, LadderQuestion *held)
{
    unsigned int found = 0u;
    for (unsigned int at = 0u; at < LADDER_CASE_COUNT; at += 1u)
    {
        if (s_ladder_cases[at].anchor == anchor)
        {
            held[found] = s_ladder_cases[at];
            found += 1u;
        }
    }
    return found;
}

int main(void)
{
    static ChainSet fitted;
    static ChainSet swept;
    static LadderQuestion cases[LADDER_CASE_COUNT];
    char text[512];
    unsigned int let_through_whole = 0u;
    unsigned int chains_whole = 0u;
    for (unsigned int anchor = 0u; anchor < (unsigned int)LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        const unsigned int found = anchor_cases(anchor, cases);
        if ((found == 0u) || (s_ladder_measured[anchor] != 0))
        {
            continue;
        }
        const unsigned int held = chain_build_cases(&swept, cases, found, 1);
        chain_build_cases(&fitted, cases, found, 0);
        const unsigned int let_through = fitted.chains - held;
        printf("  %-8s %2u cases  %5u are the relation  %5u more fit the cases and are not it\n", s_anchor_text[anchor],
               found, held, let_through);
        // the shortest arrangement the cases alone would have taken for the relation, which is the one a ladder
        // that stopped at its own cases would have written down
        for (unsigned int at = 0u; (at < fitted.chains) && (let_through != 0u); at += 1u)
        {
            unsigned int is_relation = 0u;
            for (unsigned int which = 0u; which < held; which += 1u)
            {
                is_relation += (memcmp(&fitted.chain[at], &swept.chain[which], sizeof(Chain)) == 0) ? 1u : 0u;
            }
            if (is_relation != 0u)
            {
                continue;
            }
            chain_text(&fitted.chain[at], text, sizeof(text));
            printf("      shortest one that is not: %s\n", text);
            break;
        }
        let_through_whole += let_through;
        chains_whole += held;
    }
    printf("  chain check: %u chains are the relation, %u more fit the ladder's cases and are not\n", chains_whole,
           let_through_whole);
    return 0;
}
