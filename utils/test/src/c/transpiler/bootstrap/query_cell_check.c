// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_cell_check.c: walks of asks put from inside the cell, held to addresses whose answers are known
//
//     query_cell_check <query_walk> <output file>
//
// Address 0 is mapped in no process: a read there ends the asker on every host, and the walk reads that ending as
// the address's answer and goes on. On Windows the kernel keeps a page at 0x7FFE0000 that every process reads and
// none may write. A put there ends the asker, a read answers, and two of its words are counters: the interrupt time
// at 0x8 and the system time at 0x14, each the low word of a count in hundred nanoseconds. That layout is the answer
// key here and is never read by the walk: the walk asks every word of the page's head whether it advances, and the
// check holds what came back to the key.
#include "../../../../../../src/c/transpiler/bootstrap/query_cell.h"

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

int main(int count_of_words, char **words)
{
    if (count_of_words != 3)
    {
        printf("  query_cell_check <query_walk> <output file>\n");
        return 2;
    }
    EngineError error = {0};
    static QueryAsk s_answers[256];

    // three reads at address 0 and the two words after it: each ends its own child
    QueryWalk nothing = {0};
    nothing.program = words[1];
    nothing.output_path = words[2];
    nothing.qualifier = QUERY_EQUALS;
    nothing.from = 0ull;
    nothing.count = 3ull;
    nothing.stride = 4ull;
    nothing.limit_microseconds = 10000000ull;
    const unsigned long long nothing_children = query_cell_walk(&nothing, s_answers, &error);
    check_that(nothing_children == 3ull, "three addresses that end the asker take three children");
    unsigned int nothing_ended = 0u;
    for (unsigned int number = 0u; number < 3u; number += 1u)
    {
        const QueryAsk *const answer = &s_answers[number];
        nothing_ended += ((answer->kind == QUERY_ENDED) && (answer->fault == CELL_FAULT_ADDRESS)) ? 1u : 0u;
    }
    check_that(nothing_ended == 3u, "a read at address 0 and the words after it ends the asker on an address fault");

#if defined(_WIN32)
    const unsigned long long page = 0x7ffe0000ull;

    // the page reads in one child: no read there ends the asker
    QueryWalk reads = nothing;
    reads.qualifier = QUERY_EQUALS;
    reads.from = page;
    reads.count = 64ull;
    const unsigned long long reads_children = query_cell_walk(&reads, s_answers, &error);
    unsigned int reads_answered = 0u;
    for (unsigned int number = 0u; number < 64u; number += 1u)
    {
        reads_answered += (s_answers[number].kind != QUERY_ENDED) ? 1u : 0u;
    }
    check_that((reads_children == 1ull) && (reads_answered == 64u), "the shared page answers 64 reads in one child");

    // a put there ends the asker, each address in its own child
    QueryWalk puts = nothing;
    puts.qualifier = QUERY_HOLDS;
    puts.from = page;
    puts.count = 4ull;
    const unsigned long long puts_children = query_cell_walk(&puts, s_answers, &error);
    unsigned int puts_ended = 0u;
    for (unsigned int number = 0u; number < 4u; number += 1u)
    {
        const QueryAsk *const answer = &s_answers[number];
        puts_ended += ((answer->kind == QUERY_ENDED) && (answer->fault == CELL_FAULT_ADDRESS)) ? 1u : 0u;
    }
    check_that((puts_children == 4ull) && (puts_ended == 4u), "a put on the shared page ends the asker at each word");

    // which words of the page's head advance, asked of every one; a word is put until it advances or its turns run
    // out, and the turns outlast a clock interrupt
    QueryWalk counts = nothing;
    counts.qualifier = QUERY_ADVANCES;
    counts.from = page;
    counts.count = 16ull;
    counts.turns = 0x2000000ull;
    counts.limit_microseconds = 60000000ull;
    const unsigned long long counts_children = query_cell_walk(&counts, s_answers, &error);
    check_that(counts_children == 1ull, "asking whether the page's words advance ends no asker");
    printf("  the shared page's head, words that advance:");
    for (unsigned int number = 0u; number < 16u; number += 1u)
    {
        if (s_answers[number].bit == 1u)
        {
            printf(" 0x%llx", s_answers[number].address - page);
        }
    }
    printf("\n");
    check_that(s_answers[2].bit == 1u, "the interrupt time's low word, at 0x8, advances");
    check_that(s_answers[5].bit == 1u, "the system time's low word, at 0x14, advances");
    check_that((s_answers[3].bit == 0u) && (s_answers[6].bit == 0u), "the high words beside them do not");
#else
    printf("  no shared page named to this test on this platform: the page checks are skipped\n");
#endif

    printf("  query cell: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
