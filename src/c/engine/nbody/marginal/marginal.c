// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "marginal.h"
#include "../../../types/integers/exact_integer.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(MARGINAL_LIMBS <= ANCHOR_EXACT_LIMBS, "marginal: the host's exact integer must hold every sum");

long marginal_arrangements(const MarginalRequest *request, const MarginalQuestion *asked)
{
    if ((asked->sources == 0u) || (asked->sources > MARGINAL_SOURCES_MAX) ||
        (asked->source_first > request->source_count) ||
        (asked->sources > (request->source_count - asked->source_first)))
    {
        return MARGINAL_ERROR;
    }
    unsigned long long arrangements = 1ull;
    for (unsigned int local = 0u; local < asked->sources; local += 1u)
    {
        const MarginalSource *const source = &request->sources[asked->source_first + local];
        if ((source->option_first > request->option_count) ||
            (source->options > (request->option_count - source->option_first)))
        {
            return MARGINAL_ERROR;
        }
        for (unsigned int option = 0u; option < source->options; option += 1u)
        {
            if (request->options[source->option_first + option].target >= MARGINAL_TARGETS_MAX)
            {
                return MARGINAL_ERROR;
            }
        }
        arrangements *= (unsigned long long)source->options + 1ull;
        if (arrangements > MARGINAL_ARRANGEMENTS_MAX)
        {
            return MARGINAL_ERROR;
        }
    }
    return (long)arrangements;
}

static void marginal_host_word(AnchorExactInteger *value, unsigned int word)
{
    anchor_exact_zero(value);
    value->limb[0] = word;
    value->sign = (word != 0u) ? 1 : 0;
}

static int marginal_host_put(const AnchorExactInteger *value, unsigned int *limbs)
{
    for (unsigned int limb = MARGINAL_LIMBS; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        if (value->limb[limb] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int limb = 0u; limb < MARGINAL_LIMBS; limb += 1u)
    {
        limbs[limb] = value->limb[limb];
    }
    return 1;
}

static int marginal_host_question(const MarginalRequest *request, unsigned int question)
{
    const MarginalQuestion *const asked = &request->questions[question];
    const MarginalSource *const sources = &request->sources[asked->source_first];
    AnchorExactInteger *const totals =
        (AnchorExactInteger *)malloc(((size_t)sources[0].options + MARGINAL_SUMS) * sizeof(AnchorExactInteger));
    if (totals == NULL)
    {
        return 0;
    }
    for (unsigned int outcome = 0u; outcome < (sources[0].options + MARGINAL_SUMS); outcome += 1u)
    {
        anchor_exact_zero(&totals[outcome]);
    }
    AnchorExactInteger product[MARGINAL_SOURCES_MAX + 1u];
    unsigned long long taken[MARGINAL_SOURCES_MAX + 1u];
    unsigned int choice[MARGINAL_SOURCES_MAX + 1u];
    marginal_host_word(&product[0], 1u);
    taken[0] = 0ull;
    choice[0] = 0u;
    unsigned int depth = 0u;
    int ok = 1;
    while (ok)
    {
        if (depth == asked->sources)
        {
            AnchorExactInteger sum;
            const unsigned int outcome = (choice[0] == 0u) ? MARGINAL_ABSENT : (MARGINAL_SUMS + choice[0] - 1u);
            ok = (anchor_exact_add(&totals[MARGINAL_TOTAL], &product[depth], &sum) == ANCHOR_EXACT_OK);
            totals[MARGINAL_TOTAL] = sum;
            ok = ok && (anchor_exact_add(&totals[outcome], &product[depth], &sum) == ANCHOR_EXACT_OK);
            totals[outcome] = sum;
            depth -= 1u;
            choice[depth] += 1u;
            continue;
        }
        const MarginalSource *const source = &sources[depth];
        if (choice[depth] > source->options)
        {
            if (depth == 0u)
            {
                break;
            }
            depth -= 1u;
            choice[depth] += 1u;
            continue;
        }
        unsigned int weight = source->absent;
        unsigned long long mark = 0ull;
        if (choice[depth] != 0u)
        {
            const MarginalOption *const option = &request->options[source->option_first + choice[depth] - 1u];
            weight = option->weight;
            mark = 1ull << option->target;
        }
        if ((taken[depth] & mark) != 0ull)
        {
            choice[depth] += 1u;
            continue;
        }
        AnchorExactInteger factor;
        marginal_host_word(&factor, weight);
        ok = (anchor_exact_multiply(&product[depth], &factor, &product[depth + 1u]) == ANCHOR_EXACT_OK);
        taken[depth + 1u] = taken[depth] | mark;
        depth += 1u;
        choice[depth] = 0u;
    }
    unsigned int *const sums = &request->question_sums[(size_t)question * MARGINAL_SUMS * MARGINAL_LIMBS];
    ok = ok && marginal_host_put(&totals[MARGINAL_TOTAL], &sums[MARGINAL_TOTAL * MARGINAL_LIMBS]) &&
         marginal_host_put(&totals[MARGINAL_ABSENT], &sums[MARGINAL_ABSENT * MARGINAL_LIMBS]);
    for (unsigned int option = 0u; ok && (option < sources[0].options); option += 1u)
    {
        ok = marginal_host_put(&totals[MARGINAL_SUMS + option],
                               &request->option_sums[(size_t)(sources[0].option_first + option) * MARGINAL_LIMBS]);
    }
    free(totals);
    return ok;
}

long marginal_run_host(const MarginalRequest *request)
{
    if ((request == NULL) || (request->questions == NULL) || (request->sources == NULL) || (request->options == NULL) ||
        (request->question_sums == NULL) || (request->option_sums == NULL))
    {
        return MARGINAL_ERROR;
    }
    memset(request->option_sums, 0, (size_t)request->option_count * MARGINAL_LIMBS * sizeof(unsigned int));
    for (unsigned int question = 0u; question < request->question_count; question += 1u)
    {
        if ((marginal_arrangements(request, &request->questions[question]) == MARGINAL_ERROR) ||
            (marginal_host_question(request, question) == 0))
        {
            return MARGINAL_ERROR;
        }
    }
    return (long)request->question_count;
}
