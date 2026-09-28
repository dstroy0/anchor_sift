// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// omega_computer_terms.cu: terms: counting, unranking, parsing, reduction
#include "omega_computer_internal.h"

// the closed-under-k count of n-bit codes; k past n - 1 counts as n - 1
unsigned long long omega_computer_count(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    const unsigned int range = (depth < (length - 1u)) ? depth : (length - 1u);
    return counts->count[length][range];
}

void omega_computer_count_all(OmegaComputerCounts *counts, unsigned int maximum)
{
    memset(counts->count, 0, sizeof(counts->count));
    for (unsigned int length = 2u; length <= maximum; length += 1u)
    {
        for (unsigned int depth = 0u; depth < length; depth += 1u)
        {
            unsigned long long total = ((length - 1u) <= depth) ? 1ull : 0ull;
            total += omega_computer_count(counts, length - 2u, depth + 1u);
            for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
            {
                total +=
                    omega_computer_count(counts, left, depth) * omega_computer_count(counts, length - 2u - left, depth);
            }
            counts->count[length][depth] = total;
        }
    }
}

// the term of `length` bits closed under `depth` at `index` in the count's order: the variable, then the lambda, then
// the applications by the left part's length
void omega_computer_unrank(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth,
                           unsigned long long index, std::vector<int> &term)
{
    if ((length - 1u) <= depth)
    {
        if (index == 0ull)
        {
            // an index below the length, which is at most 40
            term.push_back((int)(length - 1u));
            return;
        }
        index -= 1ull;
    }
    const unsigned long long bodies = omega_computer_count(counts, length - 2u, depth + 1u);
    if (index < bodies)
    {
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        omega_computer_unrank(counts, length - 2u, depth + 1u, index, term);
        return;
    }
    index -= bodies;
    for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
    {
        const unsigned long long lefts = omega_computer_count(counts, left, depth);
        const unsigned long long rights = omega_computer_count(counts, length - 2u - left, depth);
        if (index < (lefts * rights))
        {
            term.push_back(OMEGA_COMPUTER_APPLY);
            omega_computer_unrank(counts, left, depth, index / rights, term);
            omega_computer_unrank(counts, length - 2u - left, depth, index % rights, term);
            return;
        }
        index -= lefts * rights;
    }
}

// a code read into tokens from `at`; 1 where it is one term with every variable bound
int omega_computer_parse(const std::string &code, size_t *at, int depth, std::vector<int> &term)
{
    if ((*at + 2u) > code.size())
    {
        return 0;
    }
    if (code[*at] == '0')
    {
        const int lambda = code[*at + 1u] == '0';
        *at += 2u;
        if (lambda != 0)
        {
            term.push_back(OMEGA_COMPUTER_LAMBDA);
            return omega_computer_parse(code, at, depth + 1, term);
        }
        term.push_back(OMEGA_COMPUTER_APPLY);
        return omega_computer_parse(code, at, depth, term) && omega_computer_parse(code, at, depth, term);
    }
    int index = 0;
    while ((*at < code.size()) && (code[*at] == '1'))
    {
        index += 1;
        *at += 1u;
    }
    if (*at >= code.size())
    {
        return 0;
    }
    *at += 1u;
    term.push_back(index);
    return (index <= depth) ? 1 : 0;
}

std::string omega_computer_code(const std::vector<int> &term)
{
    std::string code;
    for (size_t at = 0u; at < term.size(); at += 1u)
    {
        if (term[at] == OMEGA_COMPUTER_LAMBDA)
        {
            code += "00";
        }
        else if (term[at] == OMEGA_COMPUTER_APPLY)
        {
            code += "01";
        }
        else
        {
            // an index from 1, at most the lambdas above it
            code.append((size_t)term[at], '1');
            code += '0';
        }
    }
    return code;
}

// the bits as Tromp's list: cons b rest = \z. z b rest, a 0 the true \x\y. x, a 1 the false \x\y. y, and nil false
void omega_computer_list_tokens(const std::string &bits, std::vector<int> &term)
{
    for (size_t at = 0u; at < bits.size(); at += 1u)
    {
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back(OMEGA_COMPUTER_APPLY);
        term.push_back(OMEGA_COMPUTER_APPLY);
        term.push_back(1);
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back((bits[at] == '0') ? 2 : 1);
    }
    term.push_back(OMEGA_COMPUTER_LAMBDA);
    term.push_back(OMEGA_COMPUTER_LAMBDA);
    term.push_back(1);
}

// The rewriting, as chaitin_omega's: one past the subterm starting at `at`
static size_t omega_computer_end(const int *term, size_t at)
{
    long need = 1;
    while (need > 0)
    {
        const int token = term[at];
        at += 1u;
        need += (token == OMEGA_COMPUTER_APPLY) ? 1 : ((token == OMEGA_COMPUTER_LAMBDA) ? 0 : -1);
    }
    return at;
}

// the argument copied under `lifted` more lambdas: a variable bound outside it moves out by that many
static size_t omega_computer_lift(const int *term, size_t at, int bound, int lifted, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_COMPUTER_LAMBDA)
    {
        out.push_back(OMEGA_COMPUTER_LAMBDA);
        return omega_computer_lift(term, at + 1u, bound + 1, lifted, out);
    }
    if (token == OMEGA_COMPUTER_APPLY)
    {
        out.push_back(OMEGA_COMPUTER_APPLY);
        const size_t right = omega_computer_lift(term, at + 1u, bound, lifted, out);
        return omega_computer_lift(term, right, bound, lifted, out);
    }
    out.push_back((token > bound) ? (token + lifted) : token);
    return at + 1u;
}

// the body with the argument put for the variable its lambda binds, and every variable bound past that lambda moved
// in by one
static size_t omega_computer_substitute(const int *term, size_t at, int depth, size_t argument, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_COMPUTER_LAMBDA)
    {
        out.push_back(OMEGA_COMPUTER_LAMBDA);
        return omega_computer_substitute(term, at + 1u, depth + 1, argument, out);
    }
    if (token == OMEGA_COMPUTER_APPLY)
    {
        out.push_back(OMEGA_COMPUTER_APPLY);
        const size_t right = omega_computer_substitute(term, at + 1u, depth, argument, out);
        return omega_computer_substitute(term, right, depth, argument, out);
    }
    if (token == (depth + 1))
    {
        (void)omega_computer_lift(term, argument, 0, depth, out);
    }
    else
    {
        out.push_back((token > (depth + 1)) ? (token - 1) : token);
    }
    return at + 1u;
}

// one normal order step: the leftmost outermost redex is the first application whose left part is a lambda, read in
// code order; 0 at a normal form
int omega_computer_step(const std::vector<int> &term, std::vector<int> &next)
{
    for (size_t at = 0u; (at + 1u) < term.size(); at += 1u)
    {
        if ((term[at] == OMEGA_COMPUTER_APPLY) && (term[at + 1u] == OMEGA_COMPUTER_LAMBDA))
        {
            const size_t argument = omega_computer_end(term.data(), at + 1u);
            const size_t after = omega_computer_end(term.data(), argument);
            // the positions are within the term. They fit its iterator's difference
            next.assign(term.begin(), term.begin() + (long)at);
            (void)omega_computer_substitute(term.data(), at + 2u, 0, argument, next);
            next.insert(next.end(), term.begin() + (long)after, term.end());
            return 1;
        }
    }
    return 0;
}

// A term's spine: k leading applications, then the head, then its k arguments. The spine subterm at position a runs
// from token a to ends[a]. Returns k.
unsigned int omega_computer_spine(const std::vector<int> &term, std::vector<size_t> &ends)
{
    unsigned int range = 0u;
    while ((range < term.size()) && (term[range] == OMEGA_COMPUTER_APPLY))
    {
        range += 1u;
    }
    ends.resize((size_t)range + 1u);
    size_t end = omega_computer_end(term.data(), range);
    ends[range] = end;
    for (unsigned int position = range; position > 0u; position -= 1u)
    {
        end = omega_computer_end(term.data(), end);
        ends[position - 1u] = end;
    }
    return range;
}

// the spine position of the head redex, where the term is an application spine over a lambda
unsigned int omega_computer_head_redex(const std::vector<int> &term)
{
    unsigned int range = 0u;
    while ((range < term.size()) && (term[range] == OMEGA_COMPUTER_APPLY))
    {
        range += 1u;
    }
    return ((range > 0u) && (range < term.size()) && (term[range] == OMEGA_COMPUTER_LAMBDA)) ? (range - 1u)
                                                                                             : OMEGA_COMPUTER_NOT_HEAD;
}

// proven growth without end (chaitin_omega's omega_grows_forever): a spine subterm reduced only by head steps comes
// back deeper on the spine. It has no head normal form and neither has the term
int omega_computer_grows_forever(const std::vector<int> &stored, const std::vector<size_t> &stored_ends,
                                 unsigned int stored_range, const std::vector<int> &term, unsigned int least,
                                 std::vector<size_t> &ends)
{
    const unsigned int range = omega_computer_spine(term, ends);
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

// normal order under a step and a size budget, watched by Brent's cycle finder and the growth proof; on a halt `term`
// is left holding the normal form
size_t g_omega_computer_peak = 0u;
