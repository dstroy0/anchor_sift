// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_terms.cu: terms: counting, unranking, reduction
#include "chaitin_omega_internal.h"

// the closed-under-k count of n-bit codes; k past n - 1 counts as n - 1, since no variable of an n-bit
// code is bound further out than that
unsigned long long omega_count(const OmegaCounts *counts, unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    const unsigned int range = (depth < (length - 1u)) ? depth : (length - 1u);
    return counts->count[length][range];
}

void omega_count_all(OmegaCounts *counts)
{
    memset(counts->count, 0, sizeof(counts->count));
    for (unsigned int length = 2u; length <= counts->length; length += 1u)
    {
        for (unsigned int depth = 0u; depth < length; depth += 1u)
        {
            unsigned long long total = ((length - 1u) <= depth) ? 1ull : 0ull;
            total += omega_count(counts, length - 2u, depth + 1u);
            for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
            {
                total += omega_count(counts, left, depth) * omega_count(counts, length - 2u - left, depth);
            }
            counts->count[length][depth] = total;
        }
    }
}

// the term of `length` bits closed under `depth` at `index` in the count's order: the variable, then the
// lambda, then the applications by the left part's length
void omega_unrank(const OmegaCounts *counts, unsigned int length, unsigned int depth, unsigned long long index,
                  std::vector<int> &term)
{
    if ((length - 1u) <= depth)
    {
        if (index == 0ull)
        {
            term.push_back((int)(length - 1u));
            return;
        }
        index -= 1ull;
    }
    const unsigned long long bodies = omega_count(counts, length - 2u, depth + 1u);
    if (index < bodies)
    {
        term.push_back(OMEGA_LAMBDA);
        omega_unrank(counts, length - 2u, depth + 1u, index, term);
        return;
    }
    index -= bodies;
    for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
    {
        const unsigned long long lefts = omega_count(counts, left, depth);
        const unsigned long long rights = omega_count(counts, length - 2u - left, depth);
        if (index < (lefts * rights))
        {
            term.push_back(OMEGA_APPLY);
            omega_unrank(counts, left, depth, index / rights, term);
            omega_unrank(counts, length - 2u - left, depth, index % rights, term);
            return;
        }
        index -= lefts * rights;
    }
}

// one past the subterm starting at `at`
size_t omega_end(const int *term, size_t at)
{
    long need = 1;
    while (need > 0)
    {
        const int token = term[at];
        at += 1u;
        need += (token == OMEGA_APPLY) ? 1 : ((token == OMEGA_LAMBDA) ? 0 : -1);
    }
    return at;
}

// the length of a term's code: two bits a lambda or an application, k + 1 a variable k
unsigned long long omega_code_bits(const std::vector<int> &term)
{
    unsigned long long bits = 0ull;
    for (size_t at = 0u; at < term.size(); at += 1u)
    {
        bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
    }
    return bits;
}

// a term's code written out
void omega_code_text(ScripturaLine *line, const std::vector<int> &term)
{
    for (size_t at = 0u; at < term.size(); at += 1u)
    {
        if (term[at] == OMEGA_LAMBDA)
        {
            scriptura_text(line, "00");
        }
        else if (term[at] == OMEGA_APPLY)
        {
            scriptura_text(line, "01");
        }
        else
        {
            for (int one = 0; one < term[at]; one += 1)
            {
                scriptura_character(line, '1');
            }
            scriptura_character(line, '0');
        }
    }
}

// the argument copied under `lifted` more lambdas: a variable bound outside it moves out by that many
static size_t omega_lift(const int *term, size_t at, int bound, int lifted, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_LAMBDA)
    {
        out.push_back(OMEGA_LAMBDA);
        return omega_lift(term, at + 1u, bound + 1, lifted, out);
    }
    if (token == OMEGA_APPLY)
    {
        out.push_back(OMEGA_APPLY);
        const size_t right = omega_lift(term, at + 1u, bound, lifted, out);
        return omega_lift(term, right, bound, lifted, out);
    }
    out.push_back((token > bound) ? (token + lifted) : token);
    return at + 1u;
}

// the body with the argument put for the variable its lambda binds, and every variable bound past that
// lambda moved in by one
static size_t omega_substitute(const int *term, size_t at, int depth, size_t argument, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_LAMBDA)
    {
        out.push_back(OMEGA_LAMBDA);
        return omega_substitute(term, at + 1u, depth + 1, argument, out);
    }
    if (token == OMEGA_APPLY)
    {
        out.push_back(OMEGA_APPLY);
        const size_t right = omega_substitute(term, at + 1u, depth, argument, out);
        return omega_substitute(term, right, depth, argument, out);
    }
    if (token == (depth + 1))
    {
        (void)omega_lift(term, argument, 0, depth, out);
    }
    else
    {
        out.push_back((token > (depth + 1)) ? (token - 1) : token);
    }
    return at + 1u;
}

// one normal order step: the leftmost outermost redex is the first application whose left part is a
// lambda, read in code order; 0 at a normal form
static int omega_step(const std::vector<int> &term, std::vector<int> &next)
{
    for (size_t at = 0u; (at + 1u) < term.size(); at += 1u)
    {
        if ((term[at] == OMEGA_APPLY) && (term[at + 1u] == OMEGA_LAMBDA))
        {
            const size_t argument = omega_end(term.data(), at + 1u);
            const size_t after = omega_end(term.data(), argument);
            next.assign(term.begin(), term.begin() + (long)at);
            (void)omega_substitute(term.data(), at + 2u, 0, argument, next);
            next.insert(next.end(), term.begin() + (long)after, term.end());
            return 1;
        }
    }
    return 0;
}

// A term's spine: k leading applications, then the head, then its k arguments. The spine subterm at position a
// (the term less its last a arguments) runs from token a to ends[a]. Returns k.
static unsigned int omega_spine(const std::vector<int> &term, std::vector<size_t> &ends)
{
    unsigned int range = 0u;
    while ((range < term.size()) && (term[range] == OMEGA_APPLY))
    {
        range += 1u;
    }
    ends.resize((size_t)range + 1u);
    size_t end = omega_end(term.data(), range);
    ends[range] = end;
    for (unsigned int position = range; position > 0u; position -= 1u)
    {
        end = omega_end(term.data(), end);
        ends[position - 1u] = end;
    }
    return range;
}

static unsigned int omega_head_redex(const std::vector<int> &term)
{
    unsigned int range = 0u;
    while ((range < term.size()) && (term[range] == OMEGA_APPLY))
    {
        range += 1u;
    }
    return ((range > 0u) && (range < term.size()) && (term[range] == OMEGA_LAMBDA)) ? (range - 1u) : OMEGA_NOT_HEAD;
}

// Proven growth without end. Since the checkpoint every step was a head step whose redex sat at spine position
// `least` or deeper. The checkpoint's spine subterm S at any position a <= least was the only part reduced,
// and it never became a lambda eating an argument outside it. If S now stands at a deeper spine position of the
// term, S reduced by head steps to S B for some arguments B; the same steps then take S B to S B' B and on
// without end (X ->h Y gives X Z ->h Y Z while X is no lambda). S has no head normal form. Neither has the
// term, and normal order, which reduces the head first, never halts.
static int omega_grows_forever(const std::vector<int> &stored, const std::vector<size_t> &stored_ends,
                               unsigned int stored_range, const std::vector<int> &term, unsigned int least,
                               std::vector<size_t> &ends)
{
    const unsigned int range = omega_spine(term, ends);
    const unsigned int deepest = (least < stored_range) ? least : stored_range;
    for (unsigned int from = 0u; from <= deepest; from += 1u)
    {
        const size_t size = stored_ends[from] - from;
        for (unsigned int to = from + 1u; to <= range; to += 1u)
        {
            if (((ends[to] - to) == size) && (memcmp(&stored[from], &term[to], size * sizeof(int)) == 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// normal order under a step and a size budget, watched by Brent's cycle finder and the growth proof above
// the steps taken are written to `taken`, and on a halt `term` is left holding the normal form
OmegaFate omega_run(std::vector<int> &term, std::vector<int> &next, std::vector<int> &stored, unsigned int steps,
                    unsigned int tokens, unsigned int *taken)
{
    static thread_local std::vector<size_t> stored_ends;
    static thread_local std::vector<size_t> ends;
    stored = term;
    unsigned int stored_range = omega_spine(stored, stored_ends);
    // the least spine position of a head redex since the checkpoint; OMEGA_NOT_HEAD once a step was not a head step
    unsigned int least = OMEGA_NOT_HEAD - 1u;
    unsigned int power = 1u;
    unsigned int since = 0u;
    *taken = steps;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int redex = omega_head_redex(term);
        if (omega_step(term, next) == 0)
        {
            *taken = step;
            return OMEGA_HALTS;
        }
        least = ((redex == OMEGA_NOT_HEAD) || (least == OMEGA_NOT_HEAD)) ? OMEGA_NOT_HEAD
                                                                         : ((redex < least) ? redex : least);
        term.swap(next);
        if (term == stored)
        {
            return OMEGA_LOOPS;
        }
        if ((least != OMEGA_NOT_HEAD) &&
            (omega_grows_forever(stored, stored_ends, stored_range, term, least, ends) != 0))
        {
            return OMEGA_DIVERGES;
        }
        if (term.size() > (size_t)tokens)
        {
            // outgrew the space it was given: the one exit a bounded search cannot close
            return OMEGA_GREW;
        }
        since += 1u;
        if (since == power)
        {
            stored = term;
            stored_range = omega_spine(stored, stored_ends);
            least = OMEGA_NOT_HEAD - 1u;
            power *= 2u;
            since = 0u;
        }
    }
    return (omega_step(term, next) == 0) ? OMEGA_HALTS : OMEGA_OPEN;
}
