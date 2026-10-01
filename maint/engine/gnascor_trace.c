// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// gnascor_trace.c: a trace of real asks for gnascor_read.py, put to the host a cycle at a time
//
//     gnascor_trace <scenario> <trace>
//
// A scenario holds one line a cycle, a spec for each side: held, not, late or unasked. Each side is a run of asks
// put through query_ask (src/engine/compiler/bootstrap/query_ask.h) between two reads of the clock, and the trace
// line written for it is the kind its asks came back as and the clock's advance across the run:
//
//     held     QUERY_EQUALS at a word the program owns, carrying the word it holds
//     not      QUERY_EQUALS at that word, carrying a word it does not hold
//     late     QUERY_ADVANCES at the clock itself: it holds, and each ask waits out a step of the clock
//     unasked  nothing is put, and the side is written as -
//
// The clock is the first word of the page every Windows process shares that the protocol finds advancing. The bound
// is derived and never written in. Sixteen runs of held asks are put unbound first, and the bound is the largest of
// them, plus their spread, plus one step of the clock, the least the clock can tell apart. A run that holds and costs
// past the bound is written PAST_BOUND. The four baseline cycles gnascor_read.py reads its edge from are written at
// the head of the trace, from four of those runs.
#include "../../src/engine/compiler/bootstrap/query_ask.h"

#include <stdio.h>
#include <string.h>

// asks in one side's run: enough for a held run to span several steps of the clock
#define TRACE_RUN 1000000ull
// held runs put unbound to derive the bound
#define TRACE_BASELINE 16u

#if defined(_WIN32)
static volatile unsigned int s_owned = 0x5a5au;
// The bound a late run has to pass, 0 until the bound is derived. The clock's step is not one length on every part,
// and a run of so many steps can land short of a bound read off runs of so many asks: a late run is put until its
// cost passes the bound, and late means that
static unsigned long long s_late_past = 0ull;

// one side's run: the kind its asks came back as, and the clock's advance across it
static unsigned int trace_run(const char *spec, unsigned long long clock, unsigned long long *cost)
{
    QueryAsk asked = {0};
    unsigned long long count = TRACE_RUN;
    const int late = (strcmp(spec, "late") == 0);
    if (late)
    {
        asked.address = clock;
        asked.qualifier = QUERY_ADVANCES;
        asked.turns = 1ull << 30;
        count = 0ull;
    }
    else
    {
        // a pointer widened to the 64-bit integer an ask carries, which host_entry.h narrows back to the same pointer
        asked.address = (unsigned long long)&s_owned;
        asked.qualifier = QUERY_EQUALS;
        asked.word = (strcmp(spec, "held") == 0) ? 0x5a5au : 0xa5a5u;
    }
    const unsigned int start = host_read(clock);
    for (unsigned long long turn = 0ull; turn < count; turn += 1ull)
    {
        query_ask(&asked);
    }
    // a late run waits out steps of the clock until its cost is past the bound
    while (late && ((unsigned long long)(host_read(clock) - start) <= s_late_past))
    {
        query_ask(&asked);
    }
    const unsigned int end = host_read(clock);
    *cost = (unsigned long long)(end - start);
    return asked.kind;
}

static const char *trace_kind(unsigned int kind, unsigned long long cost, unsigned long long bound)
{
    if (kind != QUERY_HELD)
    {
        return "NOT_HELD";
    }
    return (cost > bound) ? "PAST_BOUND" : "HELD";
}

static void trace_side(FILE *out, const char *spec, unsigned long long clock, unsigned long long bound)
{
    if (strcmp(spec, "unasked") == 0)
    {
        fprintf(out, "- - ");
        return;
    }
    unsigned long long cost = 0ull;
    const unsigned int kind = trace_run(spec, clock, &cost);
    fprintf(out, "%s %llu ", trace_kind(kind, cost, bound), cost);
}
#endif

int main(int count_of_words, char **words)
{
    if (count_of_words != 3)
    {
        printf("  gnascor_trace <scenario> <trace>\n");
        return 2;
    }
#if defined(_WIN32)
    const unsigned long long page = 0x7ffe0000ull;
    unsigned long long clock = 0ull;
    unsigned long long step = 0ull;
    for (unsigned long long word = 0ull; (word < 16ull) && (clock == 0ull); word += 1ull)
    {
        QueryAsk counts = {0};
        counts.address = page + (word * 4ull);
        counts.qualifier = QUERY_ADVANCES;
        counts.turns = 1ull << 26;
        if (query_ask(&counts) == 1u)
        {
            clock = counts.address;
        }
    }
    if (clock == 0ull)
    {
        printf("  no word of the shared page advanced: there is no clock to trace on\n");
        return 1;
    }
    // one step of the clock: the advance a single late ask waits out
    {
        QueryAsk once = {0};
        once.address = clock;
        once.qualifier = QUERY_ADVANCES;
        once.turns = 1ull << 30;
        const unsigned int before = host_read(clock);
        query_ask(&once);
        const unsigned int after = host_read(clock);
        step = (unsigned long long)(after - before);
    }

    unsigned long long baseline[TRACE_BASELINE];
    unsigned long long most = 0ull;
    unsigned long long least = ~0ull;
    for (unsigned int run = 0u; run < TRACE_BASELINE; run += 1u)
    {
        trace_run("held", clock, &baseline[run]);
        most = (baseline[run] > most) ? baseline[run] : most;
        least = (baseline[run] < least) ? baseline[run] : least;
    }
    const unsigned long long bound = most + (most - least) + step;
    s_late_past = bound;

    FILE *scenario = fopen(words[1], "r");
    FILE *out = fopen(words[2], "w");
    if ((scenario == NULL) || (out == NULL))
    {
        printf("  could not open the scenario or the trace\n");
        return 1;
    }
    fprintf(out, "# clock 0x%llx, step %llu, bound %llu from %u unbound held runs (%llu to %llu)\n", clock, step,
            bound, TRACE_BASELINE, least, most);
    for (unsigned int run = 0u; run < 4u; run += 1u)
    {
        fprintf(out, "HELD %llu HELD %llu %llu\n", baseline[2u * run], baseline[(2u * run) + 1u], bound);
    }
    char left[32];
    char right[32];
    unsigned int cycles = 0u;
    while (fscanf(scenario, "%31s %31s", left, right) == 2)
    {
        trace_side(out, left, clock, bound);
        trace_side(out, right, clock, bound);
        fprintf(out, "%llu\n", bound);
        cycles += 1u;
    }
    fclose(scenario);
    fclose(out);
    printf("  %u cycles traced on the clock at 0x%llx, bound %llu counts\n", cycles, clock, bound);
    return 0;
#else
    printf("  no shared page named to this program on this platform: nothing is traced\n");
    return 0;
#endif
}
