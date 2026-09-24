// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Chaitin's halting probability for Tromp's binary lambda calculus, bracketed exactly.
//
// The machine reads a closed lambda term from its input, self-delimited in de Bruijn form (00 M is
// lambda M, 01 M N is M applied to N, 1^k 0 is the variable bound k lambdas out), and halts where the
// term has a normal form. The codes are prefix free, so Omega = sum of 2^-|t| over the halting terms
// is a probability. Its first n bits settle the halting of every program of n bits or fewer, which is
// why no machine computes them all: Omega is approached from below and never reached.
//
// Every closed term of at most L bits is run by normal order reduction, which reaches a normal form
// whenever one exists, so reaching one proves the halt. A watcher holding a copy of the term at each
// power of two steps (Brent) sees every bit of it, and a term that comes back to a state it held
// is proven never to halt. Held to a bounded space, a term can only halt or repeat, since the space holds
// finitely many terms; so the runs are split by exit: halted, looped, out of steps (the space not yet
// searched), and outgrew the space, the one exit no bounded search closes. A grower is closed where it
// is proven to grow forever: a part of it returns at its own head (omega_grows_forever).
//
// The runs go to the device, one term to a thread, with the host running the few that pass the device's small
// budgets (omega_device); the host's own run of every term through 30 bits must give the same fates and busy
// beavers. Arguments: L, steps, tokens, and "cpu" to run every term on the host instead.
//
// The mass of the closed terms longer than L is bounded by counting, not running: the mass a(n) of
// every term code of n bits and the mass c(n, k) of those closed under k lambdas follow recurrences,
// summed in fixed point rounded toward the bound each side needs. Every code parses to its end with
// probability 1 (the parse is a subcritical branching process, and 1 is the smaller root of
// T^2 - 3T + 2 = 0), so what the counted lengths leave of 1 bounds every longer length at once.
//
//   Omega >= the halted mass,
//   Omega <= the halted mass + the open mass + the closed mass past L,
//
// both exact dyadics, and each bit the two share is a bit of Omega.
#include "sim.h"
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"

#include <atomic>
#include <chrono>
#include <map>
#include <thread>
#include <vector>

#define OMEGA_LENGTH_MOST 60u

#define OMEGA_LENGTH_DEFAULT 28u

#define OMEGA_STEPS_DEFAULT 2048u

#define OMEGA_TOKENS_DEFAULT 2048u

// the longest code whose mass the counting recurrences carry; every longer code is bounded by the parse's tail
#define OMEGA_COUNTED 1200u

// the brute-force parse checks the enumeration through this length
#define OMEGA_PARSED_MOST 22u

#define OMEGA_CHUNK 4096ull

// fixed point: 62 fraction bits, so a mass of 1 and its sums fit a word
#define OMEGA_POINT 62u

#define OMEGA_ONE (1ull << OMEGA_POINT)

// tokens of a term in the order its code is read: a lambda, an application, or a variable's index from 1
#define OMEGA_LAMBDA 0

#define OMEGA_APPLY (-1)

typedef enum
{
    OMEGA_HALTS = 0,
    OMEGA_LOOPS = 1,
    OMEGA_OPEN = 2,
    OMEGA_GREW = 3,
    OMEGA_DIVERGES = 4,
    OMEGA_TYPED = 5
} OmegaFate;

typedef struct
{
    unsigned int length;
    unsigned int steps;
    unsigned int tokens;
    unsigned long long count[OMEGA_LENGTH_MOST + 1u][OMEGA_LENGTH_MOST + 2u];
} OmegaCounts;

// per length, the busy beavers among the halting terms: the most normal order steps to a normal form, and the
// largest normal form in bits (Tromp's BB lambda), each with the first term in rank order to reach it
typedef struct
{
    unsigned long long fate[6][OMEGA_LENGTH_MOST + 1u];
    unsigned long long contradictions;
    unsigned long long most_steps[OMEGA_LENGTH_MOST + 1u];
    unsigned long long steps_champion[OMEGA_LENGTH_MOST + 1u];
    unsigned long long most_bits[OMEGA_LENGTH_MOST + 1u];
    unsigned long long bits_champion[OMEGA_LENGTH_MOST + 1u];
} OmegaTally;

// the closed-under-k count of n-bit codes; k past n - 1 counts as n - 1, since no variable of an n-bit
// code is bound further out than that
static unsigned long long omega_count(const OmegaCounts *counts, unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    const unsigned int reach = (depth < (length - 1u)) ? depth : (length - 1u);
    return counts->count[length][reach];
}

static void omega_count_all(OmegaCounts *counts)
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
static void omega_unrank(const OmegaCounts *counts, unsigned int length, unsigned int depth, unsigned long long index,
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
static size_t omega_end(const int *term, size_t at)
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
static unsigned long long omega_code_bits(const std::vector<int> &term)
{
    unsigned long long bits = 0ull;
    for (size_t at = 0u; at < term.size(); at += 1u)
    {
        bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
    }
    return bits;
}

// a term's code written out
static void omega_code_text(ScripturaLine *line, const std::vector<int> &term)
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
    unsigned int reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    ends.resize((size_t)reach + 1u);
    size_t end = omega_end(term.data(), reach);
    ends[reach] = end;
    for (unsigned int position = reach; position > 0u; position -= 1u)
    {
        end = omega_end(term.data(), end);
        ends[position - 1u] = end;
    }
    return reach;
}

// the spine position of the head redex, where the term is an application spine over a lambda; otherwise the
// step normal order takes is not a head step, and OMEGA_NOT_HEAD is returned
#define OMEGA_NOT_HEAD 0xFFFFFFFFu

static unsigned int omega_head_redex(const std::vector<int> &term)
{
    unsigned int reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    return ((reach > 0u) && (reach < term.size()) && (term[reach] == OMEGA_LAMBDA)) ? (reach - 1u) : OMEGA_NOT_HEAD;
}

// Proven growth without end. Since the checkpoint every step was a head step whose redex sat at spine position
// `least` or deeper, so the checkpoint's spine subterm S at any position a <= least was the only part reduced,
// and it never became a lambda eating an argument outside it. If S now stands at a deeper spine position of the
// term, S reduced by head steps to S B for some arguments B; the same steps then take S B to S B' B and on
// without end (X ->h Y gives X Z ->h Y Z while X is no lambda). S has no head normal form, so neither has the
// term, and normal order, which reduces the head first, never halts.
static int omega_grows_forever(const std::vector<int> &held, const std::vector<size_t> &held_ends,
                               unsigned int held_reach, const std::vector<int> &term, unsigned int least,
                               std::vector<size_t> &ends)
{
    const unsigned int reach = omega_spine(term, ends);
    const unsigned int deepest = (least < held_reach) ? least : held_reach;
    for (unsigned int from = 0u; from <= deepest; from += 1u)
    {
        const size_t size = held_ends[from] - from;
        for (unsigned int to = from + 1u; to <= reach; to += 1u)
        {
            if (((ends[to] - to) == size) && (memcmp(&held[from], &term[to], size * sizeof(int)) == 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// normal order under a step and a size budget, watched by Brent's cycle finder and the growth proof above
// the steps taken are written to `taken`, and on a halt `term` is left holding the normal form
static OmegaFate omega_run(std::vector<int> &term, std::vector<int> &next, std::vector<int> &held, unsigned int steps,
                           unsigned int tokens, unsigned int *taken)
{
    static thread_local std::vector<size_t> held_ends;
    static thread_local std::vector<size_t> ends;
    held = term;
    unsigned int held_reach = omega_spine(held, held_ends);
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
        if (term == held)
        {
            return OMEGA_LOOPS;
        }
        if ((least != OMEGA_NOT_HEAD) && (omega_grows_forever(held, held_ends, held_reach, term, least, ends) != 0))
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
            held = term;
            held_reach = omega_spine(held, held_ends);
            least = OMEGA_NOT_HEAD - 1u;
            power *= 2u;
            since = 0u;
        }
    }
    return (omega_step(term, next) == 0) ? OMEGA_HALTS : OMEGA_OPEN;
}

// an independent parse of a code of exactly `length` bits: 1 where it is one closed term using every bit
static int omega_parse(unsigned long long code, unsigned int length, unsigned int *at, unsigned int depth)
{
    if ((*at + 2u) > length)
    {
        return 0;
    }
    const unsigned int first = (unsigned int)((code >> (length - 1u - *at)) & 1ull);
    const unsigned int second = (unsigned int)((code >> (length - 2u - *at)) & 1ull);
    if (first == 0u)
    {
        *at += 2u;
        if (second == 0u)
        {
            return omega_parse(code, length, at, depth + 1u);
        }
        return omega_parse(code, length, at, depth) && omega_parse(code, length, at, depth);
    }
    unsigned int index = 0u;
    while ((*at < length) && (((code >> (length - 1u - *at)) & 1ull) == 1ull))
    {
        index += 1u;
        *at += 1u;
    }
    if (*at >= length)
    {
        return 0;
    }
    *at += 1u;
    return (index <= depth) ? 1 : 0;
}

// the high and low words of a 64 by 64 bit product, from 32 bit halves
static void omega_wide_product(unsigned long long left, unsigned long long right, unsigned long long *high,
                               unsigned long long *low)
{
    const unsigned long long left_low = left & 0xFFFFFFFFull;
    const unsigned long long left_high = left >> 32u;
    const unsigned long long right_low = right & 0xFFFFFFFFull;
    const unsigned long long right_high = right >> 32u;
    const unsigned long long low_low = left_low * right_low;
    const unsigned long long cross_one = left_high * right_low;
    const unsigned long long cross_two = left_low * right_high;
    const unsigned long long high_high = left_high * right_high;
    const unsigned long long middle = (low_low >> 32u) + (cross_one & 0xFFFFFFFFull) + (cross_two & 0xFFFFFFFFull);
    *low = (low_low & 0xFFFFFFFFull) | (middle << 32u);
    *high = high_high + (cross_one >> 32u) + (cross_two >> 32u) + (middle >> 32u);
}

// a product of two fixed point masses, rounded down or up
static unsigned long long omega_mass_product(unsigned long long left, unsigned long long right, int up)
{
    unsigned long long high = 0ull;
    unsigned long long low = 0ull;
    omega_wide_product(left, right, &high, &low);
    const unsigned long long kept = (high << (64u - OMEGA_POINT)) | (low >> OMEGA_POINT);
    const unsigned long long dropped = low & (OMEGA_ONE - 1ull);
    return kept + (((up != 0) && (dropped != 0ull)) ? 1ull : 0ull);
}

// 2^-length in fixed point, rounded down or up
static unsigned long long omega_mass_of(unsigned int length, int up)
{
    if (length <= OMEGA_POINT)
    {
        return OMEGA_ONE >> length;
    }
    return (up != 0) ? 1ull : 0ull;
}

// a(n), the mass of every n-bit term code, closed or not: a variable, a lambda, or an application
static void omega_all_mass(std::vector<unsigned long long> &mass, int up)
{
    mass.assign(OMEGA_COUNTED + 1u, 0ull);
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        unsigned long long pairs = 0ull;
        for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
        {
            pairs += omega_mass_product(mass[left], mass[length - 2u - left], up);
        }
        const unsigned long long quarter = (up != 0) ? ((mass[length - 2u] + pairs + 3ull) / 4ull)
                                                     : ((mass[length - 2u] + pairs) / 4ull);
        mass[length] = omega_mass_of(length, up) + quarter;
    }
}

// c(n, 0) rounded up, the mass of the n-bit closed codes, from c(n, k) closed under k lambdas; past k = n - 1
// every variable fits and c is a(n)
static void omega_closed_mass(const std::vector<unsigned long long> &all_up, std::vector<unsigned long long> &closed)
{
    std::vector<std::vector<unsigned long long>> under(OMEGA_COUNTED + 1u);
    for (unsigned int length = 0u; length <= OMEGA_COUNTED; length += 1u)
    {
        under[length].assign(length + 1u, 0ull);
    }
    // under[n][k] for k < n; k >= n - 1 reads a(n)
    auto read = [&](unsigned int length, unsigned int depth) -> unsigned long long
    {
        if (length < 2u)
        {
            return 0ull;
        }
        return ((depth + 1u) >= length) ? all_up[length] : under[length][depth];
    };
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        for (unsigned int depth = 0u; (depth + 1u) < length; depth += 1u)
        {
            unsigned long long pairs = 0ull;
            for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
            {
                pairs += omega_mass_product(read(left, depth), read(length - 2u - left, depth), 1);
            }
            under[length][depth] = ((read(length - 2u, depth + 1u) + pairs + 3ull) / 4ull);
        }
    }
    closed.assign(OMEGA_COUNTED + 1u, 0ull);
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        closed[length] = read(length, 0u);
    }
}

// the mass of the n-bit closed terms already in normal form, rounded down: such a term halts without a step, so
// every one past L adds to the halted mass uncounted by any run. A normal form is a lambda over a normal form or a
// neutral term; a neutral term is a variable or a neutral term applied to a normal form.
static void omega_normal_mass(std::vector<unsigned long long> &normal_closed)
{
    // the unconstrained pair first: every variable fits once k reaches n - 1
    std::vector<unsigned long long> normal_all(OMEGA_COUNTED + 1u, 0ull);
    std::vector<unsigned long long> neutral_all(OMEGA_COUNTED + 1u, 0ull);
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        unsigned long long pairs = 0ull;
        for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
        {
            pairs += omega_mass_product(neutral_all[left], normal_all[length - 2u - left], 0);
        }
        neutral_all[length] = omega_mass_of(length, 0) + (pairs / 4ull);
        normal_all[length] = neutral_all[length] + (normal_all[length - 2u] / 4ull);
    }
    std::vector<std::vector<unsigned long long>> normal(OMEGA_COUNTED + 1u);
    std::vector<std::vector<unsigned long long>> neutral(OMEGA_COUNTED + 1u);
    for (unsigned int length = 0u; length <= OMEGA_COUNTED; length += 1u)
    {
        normal[length].assign(length + 1u, 0ull);
        neutral[length].assign(length + 1u, 0ull);
    }
    auto read = [&](std::vector<std::vector<unsigned long long>> &under, std::vector<unsigned long long> &all,
                    unsigned int length, unsigned int depth) -> unsigned long long
    {
        if (length < 2u)
        {
            return 0ull;
        }
        return ((depth + 1u) >= length) ? all[length] : under[length][depth];
    };
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        for (unsigned int depth = 0u; (depth + 1u) < length; depth += 1u)
        {
            unsigned long long pairs = 0ull;
            for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
            {
                pairs += omega_mass_product(read(neutral, neutral_all, left, depth),
                                            read(normal, normal_all, length - 2u - left, depth), 0);
            }
            neutral[length][depth] = pairs / 4ull;
            normal[length][depth] = neutral[length][depth] + (read(normal, normal_all, length - 2u, depth + 1u) / 4ull);
        }
    }
    normal_closed.assign(OMEGA_COUNTED + 1u, 0ull);
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        normal_closed[length] = read(normal, normal_all, length, 0u);
    }
}

// Simple types by unification (Hindley): a type is a variable or an arrow, held in a union-find. Every simply
// typable term is strongly normalizing (Tait 1967), so a type found is a certificate that the term halts, with
// no step run and no normal form written: it settles terms whose normal forms outgrow any space.
typedef struct
{
    std::vector<unsigned int> parent;
    std::vector<unsigned int> from;
    std::vector<unsigned int> to;
    std::vector<unsigned char> arrow;
    std::vector<unsigned int> bound;
} OmegaTypes;

static unsigned int omega_type_new(OmegaTypes *types, int arrow, unsigned int from, unsigned int to)
{
    const unsigned int made = (unsigned int)types->parent.size();
    types->parent.push_back(made);
    types->from.push_back(from);
    types->to.push_back(to);
    types->arrow.push_back((unsigned char)arrow);
    return made;
}

static unsigned int omega_type_find(OmegaTypes *types, unsigned int type)
{
    while (types->parent[type] != type)
    {
        types->parent[type] = types->parent[types->parent[type]];
        type = types->parent[type];
    }
    return type;
}

static int omega_type_occurs(OmegaTypes *types, unsigned int variable, unsigned int type)
{
    type = omega_type_find(types, type);
    if (type == variable)
    {
        return 1;
    }
    if (types->arrow[type] == 0u)
    {
        return 0;
    }
    return omega_type_occurs(types, variable, types->from[type]) || omega_type_occurs(types, variable, types->to[type]);
}

static int omega_type_unify(OmegaTypes *types, unsigned int one, unsigned int other)
{
    one = omega_type_find(types, one);
    other = omega_type_find(types, other);
    if (one == other)
    {
        return 1;
    }
    if (types->arrow[one] == 0u)
    {
        if (omega_type_occurs(types, one, other) != 0)
        {
            return 0;
        }
        types->parent[one] = other;
        return 1;
    }
    if (types->arrow[other] == 0u)
    {
        return omega_type_unify(types, other, one);
    }
    const unsigned int one_from = types->from[one];
    const unsigned int one_to = types->to[one];
    const unsigned int other_from = types->from[other];
    const unsigned int other_to = types->to[other];
    return omega_type_unify(types, one_from, other_from) && omega_type_unify(types, one_to, other_to);
}

// the type of the subterm at `at` into `type`, and one past it into `end`; 0 where no simple type exists
static int omega_type_infer(OmegaTypes *types, const std::vector<int> &term, size_t at, unsigned int *type,
                            size_t *end)
{
    const int token = term[at];
    if (token == OMEGA_LAMBDA)
    {
        const unsigned int argument = omega_type_new(types, 0, 0u, 0u);
        types->bound.push_back(argument);
        unsigned int body = 0u;
        const int held = omega_type_infer(types, term, at + 1u, &body, end);
        types->bound.pop_back();
        *type = omega_type_new(types, 1, argument, body);
        return held;
    }
    if (token == OMEGA_APPLY)
    {
        unsigned int function = 0u;
        unsigned int argument = 0u;
        size_t middle = 0u;
        if ((omega_type_infer(types, term, at + 1u, &function, &middle) == 0)
            || (omega_type_infer(types, term, middle, &argument, end) == 0))
        {
            return 0;
        }
        const unsigned int result = omega_type_new(types, 0, 0u, 0u);
        *type = result;
        return omega_type_unify(types, function, omega_type_new(types, 1, argument, result));
    }
    *type = types->bound[types->bound.size() - (size_t)token];
    *end = at + 1u;
    return 1;
}

static int omega_simply_typed(const std::vector<int> &term)
{
    static thread_local OmegaTypes types;
    types.parent.clear();
    types.from.clear();
    types.to.clear();
    types.arrow.clear();
    types.bound.clear();
    unsigned int type = 0u;
    size_t end = 0u;
    return omega_type_infer(&types, term, 0u, &type, &end);
}

static void omega_tally_open(OmegaTally *tally)
{
    memset(tally, 0, sizeof(*tally));
    for (unsigned int length = 0u; length <= OMEGA_LENGTH_MOST; length += 1u)
    {
        tally->steps_champion[length] = ~0ull;
        tally->bits_champion[length] = ~0ull;
    }
}

// a busy beaver candidate: runs finish out of rank order, so a tie keeps the lower rank
static void omega_champion(unsigned long long *most, unsigned long long *champion, unsigned long long value,
                           unsigned long long index)
{
    if ((value > *most) || ((value == *most) && (index < *champion)))
    {
        *most = value;
        *champion = index;
    }
}

// one term's fate into the tally. A run that halted leaves the normal form in `term`; any other has the type
// certificate read off the program itself, since the run left the term reduced.
static void omega_settle(const OmegaCounts *counts, unsigned int length, unsigned long long index, OmegaFate fate,
                         unsigned int taken, std::vector<int> &term, OmegaTally *tally)
{
    if (fate != OMEGA_HALTS)
    {
        term.clear();
        omega_unrank(counts, length, 0u, index, term);
        const int typed = omega_simply_typed(term);
        // a typable term halts, so a proven loop or unbounded growth that types is a broken proof
        tally->contradictions += ((typed != 0) && ((fate == OMEGA_LOOPS) || (fate == OMEGA_DIVERGES))) ? 1ull : 0ull;
        fate = ((typed != 0) && ((fate == OMEGA_OPEN) || (fate == OMEGA_GREW))) ? OMEGA_TYPED : fate;
    }
    tally->fate[fate][length] += 1ull;
    if (fate == OMEGA_HALTS)
    {
        omega_champion(&tally->most_steps[length], &tally->steps_champion[length], taken, index);
        omega_champion(&tally->most_bits[length], &tally->bits_champion[length], omega_code_bits(term), index);
    }
}

static void omega_merge(OmegaTally *into, const OmegaTally *one)
{
    into->contradictions += one->contradictions;
    for (unsigned int length = 0u; length <= OMEGA_LENGTH_MOST; length += 1u)
    {
        for (unsigned int fate = 0u; fate < 6u; fate += 1u)
        {
            into->fate[fate][length] += one->fate[fate][length];
        }
        if (one->steps_champion[length] != ~0ull)
        {
            omega_champion(&into->most_steps[length], &into->steps_champion[length], one->most_steps[length],
                           one->steps_champion[length]);
            omega_champion(&into->most_bits[length], &into->bits_champion[length], one->most_bits[length],
                           one->bits_champion[length]);
        }
    }
}

static void omega_worker(const OmegaCounts *counts, const std::vector<unsigned long long> *chunk_length,
                         const std::vector<unsigned long long> *chunk_from, std::atomic<unsigned long long> *next_chunk,
                         OmegaTally *tally)
{
    std::vector<int> term;
    std::vector<int> next;
    std::vector<int> held;
    term.reserve(counts->tokens + 64u);
    next.reserve(counts->tokens + 64u);
    held.reserve(counts->tokens + 64u);
    omega_tally_open(tally);
    for (;;)
    {
        const unsigned long long chunk = next_chunk->fetch_add(1ull);
        if (chunk >= chunk_length->size())
        {
            return;
        }
        const unsigned int length = (unsigned int)(*chunk_length)[chunk];
        const unsigned long long from = (*chunk_from)[chunk];
        const unsigned long long total = omega_count(counts, length, 0u);
        const unsigned long long to = ((from + OMEGA_CHUNK) < total) ? (from + OMEGA_CHUNK) : total;
        for (unsigned long long index = from; index < to; index += 1ull)
        {
            term.clear();
            omega_unrank(counts, length, 0u, index, term);
            unsigned int taken = 0u;
            const OmegaFate fate = omega_run(term, next, held, counts->steps, counts->tokens, &taken);
            omega_settle(counts, length, index, fate, taken, term, tally);
        }
    }
}

// every closed term through `most` bits run on the host's threads
static void omega_host(const OmegaCounts *counts, unsigned int most, unsigned int workers, OmegaTally *fates)
{
    std::vector<unsigned long long> chunk_length;
    std::vector<unsigned long long> chunk_from;
    for (unsigned int length = 2u; length <= most; length += 1u)
    {
        for (unsigned long long from = 0ull; from < omega_count(counts, length, 0u); from += OMEGA_CHUNK)
        {
            chunk_length.push_back(length);
            chunk_from.push_back(from);
        }
    }
    std::vector<OmegaTally> tallies(workers);
    std::vector<std::thread> threads;
    std::atomic<unsigned long long> next_chunk(0ull);
    for (unsigned int worker = 0u; worker < workers; worker += 1u)
    {
        threads.emplace_back(omega_worker, counts, &chunk_length, &chunk_from, &next_chunk, &tallies[worker]);
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }
    omega_tally_open(fates);
    for (unsigned int worker = 0u; worker < workers; worker += 1u)
    {
        omega_merge(fates, &tallies[worker]);
    }
}

// The same run on the device, one term to a thread, steered: the device takes the bulk under small budgets and
// the host the few that need its large ones. Each thread unranks its term from the counts and reduces it in its
// own rooms, taking every decision the host's omega_run takes, in the same order; the recursive walks become
// scans with an explicit stack. A run is deterministic and its budgets only stop it, so a halt, a loop or a
// growth proof reached inside the small budgets is reached at the same step inside the large ones. A halt is
// tallied on the device. Every other term is handed back by rank: a loop or growth proof with its fate, for the
// type certificate, and a run that hit a small budget or outgrew the device's room for the host to run itself
// under the full budgets. No fate rests on the device's limits.
#define OMEGA_BLOCK 128u

// threads resident on a multiprocessor: each thread's rooms are read through the cache, and past this many they
// crowd one another out of it (on an RTX 3070 at 38 bits, 256/256: 384 took 0.91 s, 512 1.01 s, 768 1.34 s)
#define OMEGA_THREADS_PER_SM 384u

// the device's budgets, where the full ones are larger
#define OMEGA_DEVICE_STEPS 256u

#define OMEGA_DEVICE_TOKENS 256u

// a handed back term's code for a run the host must make itself
#define OMEGA_HOST_RUNS 7u

// a stack frame of the scans: the children still to start in the low two bits, and whether it is a lambda
#define OMEGA_FRAME_LAMBDA 4u

#define OMEGA_STEP_NORMAL 0u

#define OMEGA_STEP_TAKEN 1u

#define OMEGA_STEP_OVERFLOW 2u

// the most terms one launch takes, so an offset fits the 32 bits of a busy beaver key and 56 of a handed code
#define OMEGA_BATCH_MOST (1ull << 24u)

// the device's fates are checked against the host's through this length
#define OMEGA_CROSS_MOST 30u

typedef struct
{
    unsigned long long next;
    unsigned long long halts;
    unsigned long long handed;
    // most steps and largest normal form, each the value over (2^32 - 1 - offset), so the largest key is the
    // largest value at the lowest rank, and 0 is none
    unsigned long long steps_key;
    unsigned long long bits_key;
} OmegaBatch;

typedef struct
{
    short *term;
    short *next;
    short *held;
    unsigned short *ends;
    unsigned short *held_ends;
    unsigned char *stack;
} OmegaRooms;

// the counts in global memory through the read-only cache: lanes read different entries, which constant memory
// would serialize
static __device__ unsigned long long omega_device_count(const unsigned long long *__restrict__ counts,
                                                        unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    return __ldg(&counts[(length * (OMEGA_LENGTH_MOST + 2u)) + ((depth < (length - 1u)) ? depth : (length - 1u))]);
}

// omega_unrank with the pending right parts on a stack; each application leaves one more, so a term of at most
// 60 bits leaves at most 15
static __device__ unsigned int omega_device_unrank(const unsigned long long *__restrict__ counts, unsigned int length,
                                                   unsigned long long index, short *term)
{
    unsigned char lengths[16];
    unsigned char depths[16];
    unsigned long long indices[16];
    unsigned int pending = 1u;
    unsigned int size = 0u;
    lengths[0] = (unsigned char)length;
    depths[0] = 0u;
    indices[0] = index;
    while (pending > 0u)
    {
        pending -= 1u;
        unsigned int part = lengths[pending];
        unsigned int depth = depths[pending];
        unsigned long long rank = indices[pending];
        for (;;)
        {
            if ((part - 1u) <= depth)
            {
                if (rank == 0ull)
                {
                    term[size] = (short)(part - 1u);
                    size += 1u;
                    break;
                }
                rank -= 1ull;
            }
            const unsigned long long bodies = omega_device_count(counts, part - 2u, depth + 1u);
            if (rank < bodies)
            {
                term[size] = OMEGA_LAMBDA;
                size += 1u;
                part -= 2u;
                depth += 1u;
                continue;
            }
            rank -= bodies;
            for (unsigned int left = 2u; (left + 4u) <= part; left += 1u)
            {
                const unsigned long long lefts = omega_device_count(counts, left, depth);
                const unsigned long long rights = omega_device_count(counts, part - 2u - left, depth);
                if (rank < (lefts * rights))
                {
                    term[size] = OMEGA_APPLY;
                    size += 1u;
                    lengths[pending] = (unsigned char)(part - 2u - left);
                    depths[pending] = (unsigned char)depth;
                    indices[pending] = rank % rights;
                    pending += 1u;
                    part = left;
                    rank /= rights;
                    break;
                }
                rank -= lefts * rights;
            }
        }
    }
    return size;
}

static __device__ unsigned int omega_device_end(const short *term, unsigned int at)
{
    int need = 1;
    while (need > 0)
    {
        const short token = term[at];
        at += 1u;
        need += (token == OMEGA_APPLY) ? 1 : ((token == OMEGA_LAMBDA) ? 0 : -1);
    }
    return at;
}

// a token started under the open frames: it fills one of the top frame's children, and a lambda or an
// application opens a frame of its own
static __device__ void omega_device_open(unsigned char *stack, unsigned int base, unsigned int *top, short token)
{
    if (*top > base)
    {
        stack[*top - 1u] -= 1u;
    }
    if (token == OMEGA_LAMBDA)
    {
        stack[*top] = (unsigned char)(OMEGA_FRAME_LAMBDA | 1u);
        *top += 1u;
    }
    else if (token == OMEGA_APPLY)
    {
        stack[*top] = 2u;
        *top += 1u;
    }
}

// a variable ends every frame whose children have all started; returns the lambdas closed
static __device__ int omega_device_close(const unsigned char *stack, unsigned int base, unsigned int *top)
{
    int closed = 0;
    while ((*top > base) && ((stack[*top - 1u] & 3u) == 0u))
    {
        closed += ((stack[*top - 1u] & OMEGA_FRAME_LAMBDA) != 0u) ? 1 : 0;
        *top -= 1u;
    }
    return closed;
}

// omega_lift: the argument [at, end) copied under `lifted` more lambdas; 0 where it outgrows the room
static __device__ int omega_device_lift(const short *term, unsigned int at, unsigned int end, int lifted, short *next,
                                        unsigned int *out, unsigned int room, unsigned char *stack, unsigned int base)
{
    if ((*out + (end - at)) > room)
    {
        return 0;
    }
    if (lifted == 0)
    {
        for (unsigned int from = at; from < end; from += 1u)
        {
            next[*out + (from - at)] = term[from];
        }
        *out += end - at;
        return 1;
    }
    unsigned int top = base;
    int bound = 0;
    for (unsigned int from = at; from < end; from += 1u)
    {
        const short token = term[from];
        omega_device_open(stack, base, &top, token);
        if (token <= 0)
        {
            next[*out] = token;
            *out += 1u;
            bound += (token == OMEGA_LAMBDA) ? 1 : 0;
            continue;
        }
        // an index is at most the lambdas above it, within the room, so the sum fits a short
        next[*out] = (short)((token > bound) ? (token + lifted) : token);
        *out += 1u;
        bound -= omega_device_close(stack, base, &top);
    }
    return 1;
}

// omega_substitute: the body [at, end) with the argument [argument, argument_end) put for its lambda's variable
static __device__ int omega_device_substitute(const short *term, unsigned int at, unsigned int end,
                                              unsigned int argument, unsigned int argument_end, short *next,
                                              unsigned int *out, unsigned int room, unsigned char *stack)
{
    unsigned int top = 0u;
    int depth = 0;
    for (unsigned int from = at; from < end; from += 1u)
    {
        if (*out >= room)
        {
            return 0;
        }
        const short token = term[from];
        omega_device_open(stack, 0u, &top, token);
        if (token <= 0)
        {
            next[*out] = token;
            *out += 1u;
            depth += (token == OMEGA_LAMBDA) ? 1 : 0;
            continue;
        }
        if (token == (depth + 1))
        {
            if (omega_device_lift(term, argument, argument_end, depth, next, out, room, stack, top) == 0)
            {
                return 0;
            }
        }
        else
        {
            next[*out] = (short)((token > (depth + 1)) ? (token - 1) : token);
            *out += 1u;
        }
        depth -= omega_device_close(stack, 0u, &top);
    }
    return 1;
}

// omega_step into a room of `room` tokens
static __device__ unsigned int omega_device_step(const short *term, unsigned int size, short *next,
                                                 unsigned int *next_size, unsigned int room, unsigned char *stack)
{
    for (unsigned int at = 0u; (at + 1u) < size; at += 1u)
    {
        if ((term[at] == OMEGA_APPLY) && (term[at + 1u] == OMEGA_LAMBDA))
        {
            const unsigned int argument = omega_device_end(term, at + 1u);
            const unsigned int after = omega_device_end(term, argument);
            for (unsigned int copy = 0u; copy < at; copy += 1u)
            {
                next[copy] = term[copy];
            }
            unsigned int out = at;
            if (omega_device_substitute(term, at + 2u, argument, argument, after, next, &out, room, stack) == 0)
            {
                return OMEGA_STEP_OVERFLOW;
            }
            if ((out + (size - after)) > room)
            {
                return OMEGA_STEP_OVERFLOW;
            }
            for (unsigned int copy = after; copy < size; copy += 1u)
            {
                next[out + (copy - after)] = term[copy];
            }
            *next_size = out + (size - after);
            return OMEGA_STEP_TAKEN;
        }
    }
    return OMEGA_STEP_NORMAL;
}

static __device__ unsigned int omega_device_spine(const short *term, unsigned int size, unsigned short *ends)
{
    unsigned int reach = 0u;
    while ((reach < size) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    unsigned int end = omega_device_end(term, reach);
    ends[reach] = (unsigned short)end;
    for (unsigned int position = reach; position > 0u; position -= 1u)
    {
        end = omega_device_end(term, end);
        ends[position - 1u] = (unsigned short)end;
    }
    return reach;
}

static __device__ unsigned int omega_device_head_redex(const short *term, unsigned int size)
{
    unsigned int reach = 0u;
    while ((reach < size) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    return ((reach > 0u) && (reach < size) && (term[reach] == OMEGA_LAMBDA)) ? (reach - 1u) : OMEGA_NOT_HEAD;
}

static __device__ int omega_device_same(const short *one, const short *other, unsigned int size)
{
    for (unsigned int at = 0u; at < size; at += 1u)
    {
        if (one[at] != other[at])
        {
            return 0;
        }
    }
    return 1;
}

// omega_grows_forever
static __device__ int omega_device_grows_forever(const OmegaRooms *rooms, unsigned int held_reach,
                                                 const short *term, unsigned int size, unsigned int least)
{
    const unsigned int reach = omega_device_spine(term, size, rooms->ends);
    const unsigned int deepest = (least < held_reach) ? least : held_reach;
    for (unsigned int from = 0u; from <= deepest; from += 1u)
    {
        const unsigned int part = (unsigned int)rooms->held_ends[from] - from;
        for (unsigned int to = from + 1u; to <= reach; to += 1u)
        {
            if ((((unsigned int)rooms->ends[to] - to) == part)
                && (omega_device_same(&rooms->held[from], &term[to], part) != 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// omega_run; the term ends in *term (the rooms' term and next swap as it steps), and a step that outgrows the room
// returns OMEGA_HOST_RUNS
static __device__ unsigned int omega_device_run(const OmegaRooms *rooms, short **term, short **next,
                                                unsigned int *size, unsigned int steps, unsigned int tokens,
                                                unsigned int room, unsigned int *taken)
{
    for (unsigned int at = 0u; at < *size; at += 1u)
    {
        rooms->held[at] = (*term)[at];
    }
    unsigned int held_size = *size;
    unsigned int held_reach = omega_device_spine(rooms->held, held_size, rooms->held_ends);
    unsigned int least = OMEGA_NOT_HEAD - 1u;
    unsigned int power = 1u;
    unsigned int since = 0u;
    *taken = steps;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int redex = omega_device_head_redex(*term, *size);
        unsigned int next_size = 0u;
        const unsigned int stepped = omega_device_step(*term, *size, *next, &next_size, room, rooms->stack);
        if (stepped == OMEGA_STEP_NORMAL)
        {
            *taken = step;
            return OMEGA_HALTS;
        }
        if (stepped == OMEGA_STEP_OVERFLOW)
        {
            return OMEGA_HOST_RUNS;
        }
        least = ((redex == OMEGA_NOT_HEAD) || (least == OMEGA_NOT_HEAD)) ? OMEGA_NOT_HEAD
              : ((redex < least) ? redex : least);
        short *const swap = *term;
        *term = *next;
        *next = swap;
        *size = next_size;
        if ((*size == held_size) && (omega_device_same(*term, rooms->held, held_size) != 0))
        {
            return OMEGA_LOOPS;
        }
        if ((least != OMEGA_NOT_HEAD) && (omega_device_grows_forever(rooms, held_reach, *term, *size, least) != 0))
        {
            return OMEGA_DIVERGES;
        }
        if (*size > tokens)
        {
            return OMEGA_GREW;
        }
        since += 1u;
        if (since == power)
        {
            for (unsigned int at = 0u; at < *size; at += 1u)
            {
                rooms->held[at] = (*term)[at];
            }
            held_size = *size;
            held_reach = omega_device_spine(rooms->held, held_size, rooms->held_ends);
            least = OMEGA_NOT_HEAD - 1u;
            power *= 2u;
            since = 0u;
        }
    }
    for (unsigned int at = 0u; (at + 1u) < *size; at += 1u)
    {
        if (((*term)[at] == OMEGA_APPLY) && ((*term)[at + 1u] == OMEGA_LAMBDA))
        {
            return OMEGA_OPEN;
        }
    }
    return OMEGA_HALTS;
}

// the bytes of one thread's rooms, each rounded to 16
static __host__ __device__ size_t omega_rooms_bytes(unsigned int tokens, unsigned int room)
{
    const size_t shorts = (((size_t)room * 2u) + 15u) & ~(size_t)15u;
    const size_t held = (((size_t)tokens * 2u) + 15u) & ~(size_t)15u;
    const size_t ends = ((((size_t)room + 1u) * 2u) + 15u) & ~(size_t)15u;
    const size_t held_ends = ((((size_t)tokens + 1u) * 2u) + 15u) & ~(size_t)15u;
    const size_t stack = (((size_t)room + 1u) + 15u) & ~(size_t)15u;
    return (2u * shorts) + held + ends + held_ends + stack;
}

static __global__ void omega_kernel(OmegaBatch *batch, const unsigned long long *__restrict__ counts,
                                    unsigned int length, unsigned long long from, unsigned long long total,
                                    unsigned int steps, unsigned int tokens, int steps_short, int tokens_short,
                                    unsigned int room, unsigned char *scratch, unsigned long long *hand)
{
    const size_t thread = ((size_t)blockIdx.x * blockDim.x) + threadIdx.x;
    unsigned char *base = scratch + (thread * omega_rooms_bytes(tokens, room));
    const size_t shorts = (((size_t)room * 2u) + 15u) & ~(size_t)15u;
    OmegaRooms rooms;
    rooms.term = (short *)base;
    rooms.next = (short *)(base + shorts);
    rooms.held = (short *)(base + (2u * shorts));
    base += (2u * shorts) + ((((size_t)tokens * 2u) + 15u) & ~(size_t)15u);
    rooms.ends = (unsigned short *)base;
    base += ((((size_t)room + 1u) * 2u) + 15u) & ~(size_t)15u;
    rooms.held_ends = (unsigned short *)base;
    base += ((((size_t)tokens + 1u) * 2u) + 15u) & ~(size_t)15u;
    rooms.stack = base;
    unsigned long long halts = 0ull;
    unsigned long long steps_key = 0ull;
    unsigned long long bits_key = 0ull;
    for (;;)
    {
        const unsigned long long offset = atomicAdd(&batch->next, 1ull);
        if (offset >= total)
        {
            break;
        }
        short *term = rooms.term;
        short *next = rooms.next;
        unsigned int size = omega_device_unrank(counts, length, from + offset, term);
        unsigned int taken = 0u;
        unsigned int fate = omega_device_run(&rooms, &term, &next, &size, steps, tokens, room, &taken);
        if (fate == OMEGA_HALTS)
        {
            unsigned long long bits = 0ull;
            for (unsigned int at = 0u; at < size; at += 1u)
            {
                bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
            }
            if (bits <= 0xFFFFFFFFull)
            {
                const unsigned long long rank = 0xFFFFFFFFull - offset;
                halts += 1ull;
                steps_key = max(steps_key, ((unsigned long long)taken << 32u) | rank);
                bits_key = max(bits_key, (bits << 32u) | rank);
                continue;
            }
            fate = OMEGA_HOST_RUNS;
        }
        // a small budget reached is no fate: the host runs the term under the full ones
        fate = (((fate == OMEGA_OPEN) && (steps_short != 0)) || ((fate == OMEGA_GREW) && (tokens_short != 0)))
             ? OMEGA_HOST_RUNS : fate;
        hand[atomicAdd(&batch->handed, 1ull)] = (offset << 8u) | fate;
    }
    atomicAdd(&batch->halts, halts);
    atomicMax(&batch->steps_key, steps_key);
    atomicMax(&batch->bits_key, bits_key);
}

// a launch's handed back terms settled on the host: the fate each carries, or the host's own run
static void omega_hand_worker(const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              const unsigned long long *hand, unsigned long long handed, unsigned int worker,
                              unsigned int workers, OmegaTally *tally)
{
    std::vector<int> term;
    std::vector<int> next;
    std::vector<int> held;
    for (unsigned long long at = worker; at < handed; at += workers)
    {
        const unsigned long long index = from + (hand[at] >> 8u);
        OmegaFate fate = (OmegaFate)(hand[at] & 0xFFull);
        unsigned int taken = 0u;
        if ((hand[at] & 0xFFull) == OMEGA_HOST_RUNS)
        {
            term.clear();
            omega_unrank(counts, length, 0u, index, term);
            fate = omega_run(term, next, held, counts->steps, counts->tokens, &taken);
        }
        omega_settle(counts, length, index, fate, taken, term, tally);
    }
}

static void omega_hand_settle(const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              const std::vector<unsigned long long> &hand, unsigned int workers,
                              std::vector<OmegaTally> &tallies, OmegaTally *fates)
{
    const unsigned int helpers = (hand.size() < 64u) ? 1u : workers;
    std::vector<std::thread> threads;
    for (unsigned int worker = 0u; worker < helpers; worker += 1u)
    {
        omega_tally_open(&tallies[worker]);
        threads.emplace_back(omega_hand_worker, counts, length, from, hand.data(), (unsigned long long)hand.size(),
                             worker, helpers, &tallies[worker]);
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }
    for (unsigned int worker = 0u; worker < helpers; worker += 1u)
    {
        omega_merge(fates, &tallies[worker]);
    }
}

// The run planned as jobs: each length's terms in rank order, cut every OMEGA_JOB_TERMS, so the plan is the same
// on every run. A finished job's exact tally is one line of the ledger, written whole and flushed, and a run finds
// every job its ledger already holds under the same budgets and runs only the rest. A run stopped at any point
// resumes where it stopped, and reaching a longer L costs only the new lengths.
#define OMEGA_JOB_TERMS (1ull << 28u)

// the ledger's fields a line: steps, tokens, length, from, count, the six fates, the contradictions, and the two
// busy beavers with their champions
#define OMEGA_LEDGER_FIELDS 16

typedef struct
{
    unsigned int steps;
    unsigned int tokens;
    unsigned int length;
    unsigned long long from;
    unsigned long long count;
    OmegaTally tally;
} OmegaLedgerJob;

// every whole line of the ledger; a line cut short by a stop mid-write is not a job and is run again
static void omega_ledger_read(const char *path, std::vector<OmegaLedgerJob> &jobs)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
    {
        return;
    }
    char line[1024];
    while (fgets(line, (int)sizeof(line), file) != NULL)
    {
        OmegaLedgerJob job;
        omega_tally_open(&job.tally);
        unsigned long long fate[6];
        unsigned long long contradictions = 0ull;
        unsigned long long most[4];
        const size_t written = strlen(line);
        if ((written == 0u) || (line[written - 1u] != '\n'))
        {
            continue;
        }
        int read = 0;
        if (sscanf(line, "%u %u %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu%n", &job.steps,
                   &job.tokens, &job.length, &job.from, &job.count, &fate[0], &fate[1], &fate[2], &fate[3], &fate[4],
                   &fate[5], &contradictions, &most[0], &most[1], &most[2], &most[3], &read) != OMEGA_LEDGER_FIELDS)
        {
            continue;
        }
        // the whole line and nothing after, and every term of the job given one fate
        if (((size_t)read != (written - 1u)) || (job.length > OMEGA_LENGTH_MOST)
            || ((fate[0] + fate[1] + fate[2] + fate[3] + fate[4] + fate[5]) != job.count))
        {
            continue;
        }
        for (unsigned int one = 0u; one < 6u; one += 1u)
        {
            job.tally.fate[one][job.length] = fate[one];
        }
        job.tally.contradictions = contradictions;
        job.tally.most_steps[job.length] = most[0];
        job.tally.steps_champion[job.length] = most[1];
        job.tally.most_bits[job.length] = most[2];
        job.tally.bits_champion[job.length] = most[3];
        jobs.push_back(job);
    }
    fclose(file);
}

static int omega_ledger_write(const char *path, const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              unsigned long long count, const OmegaTally *tally)
{
    // a line cut short by a stop mid-write is ended first, so this job's line starts a line of its own
    int ended = 1;
    FILE *before = fopen(path, "rb");
    if (before != NULL)
    {
        if (fseek(before, -1L, SEEK_END) == 0)
        {
            ended = (fgetc(before) == '\n');
        }
        fclose(before);
    }
    FILE *file = fopen(path, "a");
    if (file == NULL)
    {
        return 0;
    }
    if (ended == 0)
    {
        fputc('\n', file);
    }
    fprintf(file, "%u %u %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu\n", counts->steps,
            counts->tokens, length, from, count, tally->fate[0][length], tally->fate[1][length],
            tally->fate[2][length], tally->fate[3][length], tally->fate[4][length], tally->fate[5][length],
            tally->contradictions, tally->most_steps[length], tally->steps_champion[length], tally->most_bits[length],
            tally->bits_champion[length]);
    const int written = (fflush(file) == 0);
    return (fclose(file) == 0) && written;
}

// every closed term through L bits run on the device as jobs, the host settling each launch's handed back terms
// while the device runs the next; launches are sized toward a quarter second of device time. `ledger` may be NULL.
static int omega_device(SimTally *tally, const OmegaCounts *counts, unsigned int workers, const char *ledger,
                        unsigned int *threads_used, unsigned long long *host_runs, unsigned long long *jobs_run,
                        unsigned long long *jobs_kept, OmegaTally *fates)
{
    omega_tally_open(fates);
    std::vector<OmegaLedgerJob> done;
    if (ledger != NULL)
    {
        omega_ledger_read(ledger, done);
    }
    const unsigned int steps = (counts->steps < OMEGA_DEVICE_STEPS) ? counts->steps : OMEGA_DEVICE_STEPS;
    const unsigned int tokens = (counts->tokens < OMEGA_DEVICE_TOKENS) ? counts->tokens : OMEGA_DEVICE_TOKENS;
    const unsigned int room = 2u * tokens;
    cudaDeviceProp properties;
    int good = sim_took(tally, cudaGetDeviceProperties(&properties, 0), "device: properties");
    size_t free_bytes = 0u;
    size_t total_bytes = 0u;
    good = good && sim_took(tally, cudaMemGetInfo(&free_bytes, &total_bytes), "device: memory");
    if (good == 0)
    {
        return 0;
    }
    const size_t rooms_bytes = omega_rooms_bytes(tokens, room);
    size_t blocks = ((size_t)properties.multiProcessorCount * OMEGA_THREADS_PER_SM) / OMEGA_BLOCK;
    while ((blocks > 1u) && ((blocks * OMEGA_BLOCK * rooms_bytes) > (free_bytes / 2u)))
    {
        blocks -= 1u;
    }
    *threads_used = (unsigned int)(blocks * OMEGA_BLOCK);
    unsigned char *scratch = NULL;
    unsigned long long *hand = NULL;
    unsigned long long *device_counts = NULL;
    OmegaBatch *batch = NULL;
    cudaEvent_t launched = NULL;
    cudaEvent_t finished = NULL;
    good = sim_took(tally, cudaMalloc((void **)&device_counts, sizeof(counts->count)), "device: counts");
    good = good && sim_took(tally, cudaMemcpy(device_counts, counts->count, sizeof(counts->count),
                                              cudaMemcpyHostToDevice), "device: counts");
    good = good && sim_took(tally, cudaMalloc((void **)&scratch, blocks * OMEGA_BLOCK * rooms_bytes), "device: rooms");
    good = good && sim_took(tally, cudaMalloc((void **)&hand, OMEGA_BATCH_MOST * sizeof(unsigned long long)),
                            "device: hand");
    good = good && sim_took(tally, cudaMalloc((void **)&batch, sizeof(OmegaBatch)), "device: batch");
    good = good && sim_took(tally, cudaEventCreate(&launched), "device: event");
    good = good && sim_took(tally, cudaEventCreate(&finished), "device: event");
    std::vector<OmegaTally> tallies(workers);
    // the launch before this one, whose handed back terms the host settles while this one runs
    std::vector<unsigned long long> held_hand;
    unsigned int held_length = 0u;
    unsigned long long held_from = 0ull;
    unsigned long long size = 1ull << 12u;
    static OmegaTally job;
    for (unsigned int length = 2u; (good != 0) && (length <= counts->length); length += 1u)
    {
        const unsigned long long total = omega_count(counts, length, 0u);
        for (unsigned long long job_from = 0ull; (good != 0) && (job_from < total); job_from += OMEGA_JOB_TERMS)
        {
            const unsigned long long job_count = ((total - job_from) < OMEGA_JOB_TERMS) ? (total - job_from)
                                                                                         : OMEGA_JOB_TERMS;
            const OmegaLedgerJob *kept = NULL;
            for (const OmegaLedgerJob &one : done)
            {
                if ((one.steps == counts->steps) && (one.tokens == counts->tokens) && (one.length == length)
                    && (one.from == job_from) && (one.count == job_count))
                {
                    kept = &one;
                    break;
                }
            }
            if (kept != NULL)
            {
                omega_merge(fates, &kept->tally);
                *jobs_kept += 1ull;
                continue;
            }
            omega_tally_open(&job);
            const unsigned long long job_end = job_from + job_count;
            unsigned long long from = job_from;
            while ((good != 0) && (from < job_end))
            {
                const unsigned long long take = ((job_end - from) < size) ? (job_end - from) : size;
                good = sim_took(tally, cudaMemset(batch, 0, sizeof(OmegaBatch)), "device: open");
                good = good && sim_took(tally, cudaEventRecord(launched), "device: event");
                omega_kernel<<<(unsigned int)blocks, OMEGA_BLOCK>>>(batch, device_counts, length, from, take, steps,
                                                                   tokens, steps < counts->steps,
                                                                   tokens < counts->tokens, room, scratch, hand);
                good = good && sim_took(tally, cudaGetLastError(), "device: launch");
                good = good && sim_took(tally, cudaEventRecord(finished), "device: event");
                omega_hand_settle(counts, held_length, held_from, held_hand, workers, tallies, &job);
                held_hand.clear();
                good = good && sim_took(tally, cudaEventSynchronize(finished), "device: run");
                OmegaBatch result;
                good = good && sim_took(tally, cudaMemcpy(&result, batch, sizeof(result), cudaMemcpyDeviceToHost),
                                        "device: batch read");
                float milliseconds = 0.0f;
                good = good && sim_took(tally, cudaEventElapsedTime(&milliseconds, launched, finished),
                                        "device: event");
                if (good == 0)
                {
                    break;
                }
                held_hand.resize(result.handed);
                good = (result.handed == 0ull)
                    || sim_took(tally, cudaMemcpy(held_hand.data(), hand, result.handed * sizeof(unsigned long long),
                                                  cudaMemcpyDeviceToHost), "device: hand read");
                held_length = length;
                held_from = from;
                job.fate[OMEGA_HALTS][length] += result.halts;
                if (result.steps_key != 0ull)
                {
                    omega_champion(&job.most_steps[length], &job.steps_champion[length], result.steps_key >> 32u,
                                   from + (0xFFFFFFFFull - (result.steps_key & 0xFFFFFFFFull)));
                    omega_champion(&job.most_bits[length], &job.bits_champion[length], result.bits_key >> 32u,
                                   from + (0xFFFFFFFFull - (result.bits_key & 0xFFFFFFFFull)));
                }
                for (unsigned long long at = 0ull; at < result.handed; at += 1ull)
                {
                    *host_runs += ((held_hand[at] & 0xFFull) == OMEGA_HOST_RUNS) ? 1ull : 0ull;
                }
                from += take;
                if ((milliseconds < 100.0f) && (take == size) && (size < OMEGA_BATCH_MOST))
                {
                    size *= 2ull;
                }
                else if ((milliseconds > 500.0f) && (size > 1024ull))
                {
                    size /= 2ull;
                }
            }
            // the job is whole only once its last launch's handed back terms are settled
            omega_hand_settle(counts, held_length, held_from, held_hand, workers, tallies, &job);
            held_hand.clear();
            if (good == 0)
            {
                break;
            }
            if ((ledger != NULL) && (omega_ledger_write(ledger, counts, length, job_from, job_count, &job) == 0))
            {
                sim_check(tally, 0, "device: the ledger takes each finished job");
                good = 0;
                break;
            }
            omega_merge(fates, &job);
            *jobs_run += 1ull;
        }
    }
    (void)cudaEventDestroy(finished);
    (void)cudaEventDestroy(launched);
    (void)cudaFree(batch);
    (void)cudaFree(hand);
    (void)cudaFree(scratch);
    (void)cudaFree(device_counts);
    return good;
}

// The run by the engine: every normal order step of every live term is one sweep of the engine's record machine,
// and nothing bounds it but the machine. A term is as many records as it has tokens, so it grows by adding records
// and no register or field holds a whole term. Each round the host's threads find each live term's leftmost redex
// and lay out where every token of the reduct comes from: the prefix and the suffix copied, the body's tokens with
// the depth they sit at, and a copy of the argument for each variable the redex's lambda binds, with the depth it
// is put under and the lambdas above each of its tokens. The record machine gathers each source token through its
// index list and computes the reduct's token: a body variable bound past the redex moves in by one, an argument's
// variable bound outside it moves out by the depth, and the rest are copied. The record program is imprinted for
// the widths the round's values need, so no width is set anywhere. The host then takes the same decisions as
// omega_run, in the same order: a normal form halts, Brent's watcher proves a loop, and omega_grows_forever's proof
// is made on the new term. There is no step budget and no token budget: a term runs until one of those settles it.
// A term the machine's memory cannot hold for its next step is parked as outgrown, which is the only exit left
// open, and a stop leaves every live term open.

// a job: one length's terms from `from`, at most this many, admitted to the live pool as the pool drains
#define OMEGA_ENGINE_JOB (1ull << 22u)

// the pool takes the next job once fewer terms than this are live
#define OMEGA_ENGINE_ADMIT (1ull << 21u)

// the engine's index is 32 bits, so a sweep is cut where its sources would span more, and at this many lanes
#define OMEGA_ENGINE_SWEEP (1ull << 26u)

#define OMEGA_ENGINE_NONE (~(size_t)0u)

// the terms settled on the engine are checked against omega_run through this length
#define OMEGA_ENGINE_CROSS_MOST 24u

typedef long long OmegaToken;

typedef struct
{
    unsigned int length;
    unsigned int job;
    unsigned long long index;
    unsigned long long steps;
    unsigned long long power;
    unsigned long long since;
    size_t least;
    size_t held_reach;
    std::vector<OmegaToken> term;
    std::vector<OmegaToken> held;
    std::vector<size_t> held_ends;
    // this round: the head redex's spine position, the leftmost redex, its argument and what follows it
    size_t head;
    size_t redex;
    size_t argument;
    size_t after;
    size_t out_size;
    size_t in_base;
    size_t out_base;
    unsigned long long most_depth;
    unsigned long long most_bound;
    unsigned long long most_token;
    // settled: a fate, and a halt's normal form in bits
    int fate;
    unsigned long long bits;
} OmegaLive;

typedef struct
{
    unsigned int length;
    unsigned long long index;
    int fate;
    unsigned long long steps;
    unsigned long long bits;
} OmegaSettled;

static size_t omega_engine_end(const OmegaToken *term, size_t at)
{
    long long need = 1;
    while (need > 0)
    {
        const OmegaToken token = term[at];
        at += 1u;
        need += (token == OMEGA_APPLY) ? 1 : ((token == OMEGA_LAMBDA) ? 0 : -1);
    }
    return at;
}

static size_t omega_engine_spine(const std::vector<OmegaToken> &term, std::vector<size_t> &ends)
{
    size_t reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    ends.resize(reach + 1u);
    size_t end = omega_engine_end(term.data(), reach);
    ends[reach] = end;
    for (size_t position = reach; position > 0u; position -= 1u)
    {
        end = omega_engine_end(term.data(), end);
        ends[position - 1u] = end;
    }
    return reach;
}

static size_t omega_engine_head(const std::vector<OmegaToken> &term)
{
    size_t reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_APPLY))
    {
        reach += 1u;
    }
    return ((reach > 0u) && (reach < term.size()) && (term[reach] == OMEGA_LAMBDA)) ? (reach - 1u) : OMEGA_ENGINE_NONE;
}

// omega_grows_forever on the engine's terms
static int omega_engine_grows(const OmegaLive *live, size_t least, std::vector<size_t> &ends)
{
    const size_t reach = omega_engine_spine(live->term, ends);
    const size_t deepest = (least < live->held_reach) ? least : live->held_reach;
    for (size_t from = 0u; from <= deepest; from += 1u)
    {
        const size_t part = live->held_ends[from] - from;
        for (size_t to = from + 1u; to <= reach; to += 1u)
        {
            if (((ends[to] - to) == part)
                && (memcmp(&live->held[from], &live->term[to], part * sizeof(OmegaToken)) == 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// a walk over one subterm keeping the lambdas above each token: the frames hold the children still to start, and
// whether the frame is a lambda
typedef struct
{
    std::vector<unsigned char> frames;
    unsigned long long depth;
} OmegaWalk;

static void omega_walk_open(OmegaWalk *walk, OmegaToken token)
{
    if (!walk->frames.empty())
    {
        walk->frames.back() -= 1u;
    }
    if (token == OMEGA_LAMBDA)
    {
        walk->frames.push_back((unsigned char)(OMEGA_FRAME_LAMBDA | 1u));
        walk->depth += 1ull;
    }
    else if (token == OMEGA_APPLY)
    {
        walk->frames.push_back(2u);
    }
}

// after a variable: every frame whose children have all started is ended
static void omega_walk_close(OmegaWalk *walk)
{
    while ((!walk->frames.empty()) && ((walk->frames.back() & 3u) == 0u))
    {
        walk->depth -= ((walk->frames.back() & OMEGA_FRAME_LAMBDA) != 0u) ? 1ull : 0ull;
        walk->frames.pop_back();
    }
}

static unsigned int omega_engine_bits_of(unsigned long long value)
{
    unsigned int bits = 1u;
    while ((bits < 64u) && ((value >> bits) != 0ull))
    {
        bits += 1u;
    }
    return bits;
}

// `bits` of a value into a record at `offset`, two's complement when negative
static void omega_engine_put(unsigned int *record, unsigned int offset, unsigned int bits, OmegaToken value)
{
    const unsigned long long word = (unsigned long long)value;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int held = (bit < 64u) ? (unsigned int)((word >> bit) & 1ull) : ((value < 0) ? 1u : 0u);
        const unsigned int to = offset + bit;
        record[to / 32u] |= held << (to % 32u);
    }
}

// `bits` of a record at `offset` as two's complement; 0 where the value does not fit a token
static int omega_engine_take(const unsigned int *record, unsigned int offset, unsigned int bits, OmegaToken *value)
{
    const unsigned int top = offset + bits - 1u;
    const unsigned int sign = (record[top / 32u] >> (top % 32u)) & 1u;
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        const unsigned int held = (record[from / 32u] >> (from % 32u)) & 1u;
        if (bit < 64u)
        {
            word |= (unsigned long long)held << bit;
        }
        else if (held != sign)
        {
            return 0;
        }
    }
    if ((bits < 64u) && (sign != 0u))
    {
        word |= ~0ull << bits;
    }
    *value = (OmegaToken)word;
    return 1;
}

// the reduct's token from the source token s and its plan: a body token at depth p, or an argument's token put
// under p lambdas with b lambdas above it inside the argument, or a copy
//   s - body . [s > p + 1] + argument . [s > b] . p
typedef struct
{
    unsigned int token_bits;
    unsigned int depth_bits;
    unsigned int bound_bits;
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    unsigned int out_offset;
    unsigned int out_bits;
} OmegaProgram;

#define OMEGA_PROGRAM_OUT 20u

static void omega_program_step(EngineRecordStep *steps, unsigned int *count, EngineRecordOperation operation,
                               unsigned int left, unsigned int right, unsigned int member)
{
    steps[*count].operation = operation;
    steps[*count].left = left;
    steps[*count].right = right;
    steps[*count].member = member;
    *count += 1u;
}

static int omega_program_load(OmegaProgram *program, EngineError *error)
{
    EngineRecordStep steps[OMEGA_PROGRAM_OUT + 1u];
    unsigned int count = 0u;
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 s
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 1u, 0u, 1u);        // 1 p
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 2u, 0u, 1u);        // 2 b
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 3u, 0u, 1u);        // 3 body
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 4u, 0u, 1u);        // 4 argument
    omega_program_step(steps, &count, ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);     // 5 1
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 1u, 5u, 0u);          // 6 p + 1
    omega_program_step(steps, &count, ENGINE_RECORD_COMPARE, 0u, 6u, 0u);      // 7 sign(s - p - 1)
    omega_program_step(steps, &count, ENGINE_RECORD_ABSOLUTE, 7u, 0u, 0u);     // 8
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);          // 9 2 [s > p + 1]
    omega_program_step(steps, &count, ENGINE_RECORD_CONSTANT, 2u, 0u, 0u);     // 10 2
    omega_program_step(steps, &count, ENGINE_RECORD_QUOTIENT, 9u, 10u, 0u);    // 11 [s > p + 1]
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 11u, 0u);     // 12 the body's move in
    omega_program_step(steps, &count, ENGINE_RECORD_COMPARE, 0u, 2u, 0u);      // 13 sign(s - b)
    omega_program_step(steps, &count, ENGINE_RECORD_ABSOLUTE, 13u, 0u, 0u);    // 14
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 13u, 14u, 0u);        // 15 2 [s > b]
    omega_program_step(steps, &count, ENGINE_RECORD_QUOTIENT, 15u, 10u, 0u);   // 16 [s > b]
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 16u, 1u, 0u);     // 17 [s > b] p
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 17u, 0u);     // 18 the argument's move out
    omega_program_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 0u, 12u, 0u);  // 19
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 19u, 18u, 0u);        // 20 the reduct's token
    const unsigned int field_bits[5] = {program->token_bits, program->depth_bits, program->bound_bits, 1u, 1u};
    const unsigned int field_offset[5] = {0u, 0u, program->depth_bits, program->depth_bits + program->bound_bits,
                                          program->depth_bits + program->bound_bits + 1u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {
        (program->token_bits + 31u) / 32u, (program->depth_bits + program->bound_bits + 2u + 31u) / 32u, 0u};
    const unsigned int outputs[1] = {OMEGA_PROGRAM_OUT};
    memset(&program->key, 0, sizeof(program->key));
    memset(&program->layout, 0, sizeof(program->layout));
    program->record = NULL;
    const KeymathRecordRequest imprint = {steps, count, field_bits, 5u, 2u, outputs, 1u, NULL, 0u, &program->key,
                                          error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&program->key, field_offset, 5u, in_limbs, 1, &program->layout, error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&program->key);
        return 0;
    }
    if (cycle_record_load(&program->layout, &program->record, error) == CYCLE_REFUSED)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    program->out_offset = program->layout.step_table[OMEGA_PROGRAM_OUT].out_offset;
    program->out_bits = program->layout.step_table[OMEGA_PROGRAM_OUT].out_bits;
    return 1;
}

static void omega_program_free(OmegaProgram *program)
{
    cycle_record_release(program->record);
    key_schedule_record_release(&program->layout);
    keymath_record_release(&program->key);
}

// phase one of a round: the redex, what the reduct holds, and the widths its values need; a normal form settles
static void omega_engine_survey(std::vector<OmegaLive> *pool, size_t first, size_t last)
{
    OmegaWalk walk;
    for (size_t at = first; at < last; at += 1u)
    {
        OmegaLive *const live = &(*pool)[at];
        const std::vector<OmegaToken> &term = live->term;
        live->head = omega_engine_head(term);
        live->redex = OMEGA_ENGINE_NONE;
        unsigned long long most_token = 1ull;
        for (size_t token = 0u; token < term.size(); token += 1u)
        {
            const unsigned long long size = (unsigned long long)((term[token] < 0) ? -term[token] : term[token]);
            most_token = (size > most_token) ? size : most_token;
            if ((live->redex == OMEGA_ENGINE_NONE) && ((token + 1u) < term.size()) && (term[token] == OMEGA_APPLY)
                && (term[token + 1u] == OMEGA_LAMBDA))
            {
                live->redex = token;
            }
        }
        live->most_token = most_token;
        if (live->redex == OMEGA_ENGINE_NONE)
        {
            unsigned long long bits = 0ull;
            for (size_t token = 0u; token < term.size(); token += 1u)
            {
                bits += (term[token] <= 0) ? 2ull : ((unsigned long long)term[token] + 1ull);
            }
            live->fate = OMEGA_HALTS;
            live->bits = bits;
            continue;
        }
        live->argument = omega_engine_end(term.data(), live->redex + 1u);
        live->after = omega_engine_end(term.data(), live->argument);
        walk.frames.clear();
        walk.depth = 0ull;
        size_t uses = 0u;
        unsigned long long most_depth = 0ull;
        for (size_t token = live->redex + 2u; token < live->argument; token += 1u)
        {
            omega_walk_open(&walk, term[token]);
            most_depth = (walk.depth > most_depth) ? walk.depth : most_depth;
            if (term[token] > 0)
            {
                uses += (term[token] == (OmegaToken)(walk.depth + 1ull)) ? 1u : 0u;
                omega_walk_close(&walk);
            }
        }
        walk.frames.clear();
        walk.depth = 0ull;
        unsigned long long most_bound = 0ull;
        for (size_t token = live->argument; token < live->after; token += 1u)
        {
            omega_walk_open(&walk, term[token]);
            most_bound = (walk.depth > most_bound) ? walk.depth : most_bound;
            if (term[token] > 0)
            {
                omega_walk_close(&walk);
            }
        }
        live->most_depth = most_depth;
        live->most_bound = most_bound;
        const size_t body = live->argument - (live->redex + 2u);
        const size_t argument = live->after - live->argument;
        live->out_size = live->redex + (body - uses) + (uses * argument) + (term.size() - live->after);
    }
}

// phase two: the round's records. Each live term's tokens become records of member 0, and each reduct token a plan
// record of member 1 and the source it gathers.
typedef struct
{
    unsigned int token_bits;
    unsigned int depth_bits;
    unsigned int bound_bits;
    unsigned int token_limbs;
    unsigned int plan_limbs;
    unsigned int *tokens;
    unsigned int *plans;
    unsigned long long *sources;
} OmegaRound;

static void omega_engine_plan_put(const OmegaRound *round, size_t out, unsigned long long source,
                                  unsigned long long depth, unsigned long long bound, unsigned int body,
                                  unsigned int argument)
{
    unsigned int *const plan = &round->plans[out * round->plan_limbs];
    omega_engine_put(plan, 0u, round->depth_bits, (OmegaToken)depth);
    omega_engine_put(plan, round->depth_bits, round->bound_bits, (OmegaToken)bound);
    omega_engine_put(plan, round->depth_bits + round->bound_bits, 1u, (OmegaToken)body);
    omega_engine_put(plan, round->depth_bits + round->bound_bits + 1u, 1u, (OmegaToken)argument);
    round->sources[out] = source;
}

static void omega_engine_lay(std::vector<OmegaLive> *pool, const std::vector<size_t> *stepping, size_t first,
                             size_t last, const OmegaRound *round)
{
    OmegaWalk walk;
    OmegaWalk inner;
    for (size_t at = first; at < last; at += 1u)
    {
        const OmegaLive *const live = &(*pool)[(*stepping)[at]];
        const std::vector<OmegaToken> &term = live->term;
        for (size_t token = 0u; token < term.size(); token += 1u)
        {
            omega_engine_put(&round->tokens[(live->in_base + token) * round->token_limbs], 0u, round->token_bits,
                             term[token]);
        }
        size_t out = live->out_base;
        for (size_t token = 0u; token < live->redex; token += 1u)
        {
            omega_engine_plan_put(round, out, live->in_base + token, 0ull, 0ull, 0u, 0u);
            out += 1u;
        }
        walk.frames.clear();
        walk.depth = 0ull;
        for (size_t token = live->redex + 2u; token < live->argument; token += 1u)
        {
            omega_walk_open(&walk, term[token]);
            if ((term[token] > 0) && (term[token] == (OmegaToken)(walk.depth + 1ull)))
            {
                inner.frames.clear();
                inner.depth = 0ull;
                for (size_t copy = live->argument; copy < live->after; copy += 1u)
                {
                    omega_walk_open(&inner, term[copy]);
                    omega_engine_plan_put(round, out, live->in_base + copy, walk.depth, inner.depth, 0u, 1u);
                    out += 1u;
                    if (term[copy] > 0)
                    {
                        omega_walk_close(&inner);
                    }
                }
            }
            else
            {
                omega_engine_plan_put(round, out, live->in_base + token, walk.depth, 0ull, 1u, 0u);
                out += 1u;
            }
            if (term[token] > 0)
            {
                omega_walk_close(&walk);
            }
        }
        for (size_t token = live->after; token < term.size(); token += 1u)
        {
            omega_engine_plan_put(round, out, live->in_base + token, 0ull, 0ull, 0u, 0u);
            out += 1u;
        }
    }
}

// phase three: each reduct taken back and watched, as omega_run watches it
static void omega_engine_watch(std::vector<OmegaLive> *pool, const std::vector<size_t> *stepping, size_t first,
                               size_t last, const std::vector<OmegaToken> *reducts)
{
    static thread_local std::vector<size_t> ends;
    for (size_t at = first; at < last; at += 1u)
    {
        OmegaLive *const live = &(*pool)[(*stepping)[at]];
        live->term.assign(reducts->begin() + (long long)live->out_base,
                          reducts->begin() + (long long)(live->out_base + live->out_size));
        live->least = ((live->head == OMEGA_ENGINE_NONE) || (live->least == OMEGA_ENGINE_NONE))
                    ? OMEGA_ENGINE_NONE : ((live->head < live->least) ? live->head : live->least);
        live->steps += 1ull;
        if (live->term == live->held)
        {
            live->fate = OMEGA_LOOPS;
            continue;
        }
        if ((live->least != OMEGA_ENGINE_NONE) && (omega_engine_grows(live, live->least, ends) != 0))
        {
            live->fate = OMEGA_DIVERGES;
            continue;
        }
        live->since += 1ull;
        if (live->since == live->power)
        {
            live->held = live->term;
            live->held_reach = omega_engine_spine(live->held, live->held_ends);
            live->least = OMEGA_ENGINE_NONE - 1u;
            live->power *= 2ull;
            live->since = 0ull;
        }
    }
}

// a function over [0, count) cut across the host's threads
template <typename Work>
static void omega_engine_threads(size_t count, unsigned int workers, Work work)
{
    if (count < 4096u)
    {
        work((size_t)0u, count);
        return;
    }
    std::vector<std::thread> threads;
    for (unsigned int worker = 0u; worker < workers; worker += 1u)
    {
        const size_t first = (count * worker) / workers;
        const size_t last = (count * (worker + 1u)) / workers;
        threads.emplace_back(work, first, last);
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }
}

typedef struct
{
    unsigned int length;
    unsigned long long from;
    unsigned long long count;
    unsigned long long settled;
    OmegaTally tally;
} OmegaEngineJob;

// the engine's ledger: one line a finished job, "engine" first and "end" last, so a line cut anywhere is not a job
static void omega_engine_ledger_read(const char *path, std::vector<OmegaEngineJob> &jobs)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
    {
        return;
    }
    char line[1024];
    while (fgets(line, (int)sizeof(line), file) != NULL)
    {
        OmegaEngineJob job;
        omega_tally_open(&job.tally);
        unsigned long long fate[6];
        unsigned long long contradictions = 0ull;
        unsigned long long most[4];
        int read = 0;
        const size_t written = strlen(line);
        if ((written == 0u) || (line[written - 1u] != '\n'))
        {
            continue;
        }
        if ((sscanf(line, "engine %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu end%n",
                    &job.length, &job.from, &job.count, &fate[0], &fate[1], &fate[2], &fate[3], &fate[4], &fate[5],
                    &contradictions, &most[0], &most[1], &most[2], &most[3], &read) != 14)
            || ((size_t)read != (written - 1u)) || (job.length > OMEGA_LENGTH_MOST)
            || ((fate[0] + fate[1] + fate[2] + fate[3] + fate[4] + fate[5]) != job.count))
        {
            continue;
        }
        for (unsigned int one = 0u; one < 6u; one += 1u)
        {
            job.tally.fate[one][job.length] = fate[one];
        }
        job.tally.contradictions = contradictions;
        job.tally.most_steps[job.length] = most[0];
        job.tally.steps_champion[job.length] = most[1];
        job.tally.most_bits[job.length] = most[2];
        job.tally.bits_champion[job.length] = most[3];
        job.settled = job.count;
        jobs.push_back(job);
    }
    fclose(file);
}

static int omega_engine_ledger_write(const char *path, const OmegaEngineJob *job)
{
    int ended = 1;
    FILE *before = fopen(path, "rb");
    if (before != NULL)
    {
        if (fseek(before, -1L, SEEK_END) == 0)
        {
            ended = (fgetc(before) == '\n');
        }
        fclose(before);
    }
    FILE *file = fopen(path, "a");
    if (file == NULL)
    {
        return 0;
    }
    if (ended == 0)
    {
        fputc('\n', file);
    }
    const unsigned int length = job->length;
    const OmegaTally *const tally = &job->tally;
    fprintf(file, "engine %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu end\n", length,
            job->from, job->count, tally->fate[0][length], tally->fate[1][length], tally->fate[2][length],
            tally->fate[3][length], tally->fate[4][length], tally->fate[5][length], tally->contradictions,
            tally->most_steps[length], tally->steps_champion[length], tally->most_bits[length],
            tally->bits_champion[length]);
    const int flushed = (fflush(file) == 0);
    return (fclose(file) == 0) && flushed;
}

// the engine's run of every closed term through L bits
typedef struct
{
    unsigned long long rounds;
    unsigned long long sweeps;
    unsigned long long records;
    unsigned long long most_steps;
    size_t most_tokens;
    unsigned long long jobs_run;
    unsigned long long jobs_kept;
    unsigned long long parked;
} OmegaEngineReport;

static void omega_engine_settle(const OmegaCounts *counts, OmegaEngineJob *job, const OmegaLive *live,
                                std::vector<int> &scratch, std::vector<OmegaSettled> *crossed)
{
    OmegaTally *const tally = &job->tally;
    if (live->fate == OMEGA_HALTS)
    {
        tally->fate[OMEGA_HALTS][live->length] += 1ull;
        omega_champion(&tally->most_steps[live->length], &tally->steps_champion[live->length], live->steps,
                       live->index);
        omega_champion(&tally->most_bits[live->length], &tally->bits_champion[live->length], live->bits, live->index);
    }
    else
    {
        // the type certificate and the contradiction check, read off the program
        omega_settle(counts, live->length, live->index, (OmegaFate)live->fate, 0u, scratch, tally);
    }
    job->settled += 1ull;
    if (live->length <= OMEGA_ENGINE_CROSS_MOST)
    {
        const OmegaSettled settled = {live->length, live->index, live->fate, live->steps, live->bits};
        crossed->push_back(settled);
    }
}

static void omega_engine_admit(const OmegaCounts *counts, std::vector<OmegaEngineJob> &jobs, size_t job,
                               std::vector<OmegaLive> &pool)
{
    std::vector<int> term;
    for (unsigned long long index = jobs[job].from; index < (jobs[job].from + jobs[job].count); index += 1ull)
    {
        term.clear();
        omega_unrank(counts, jobs[job].length, 0u, index, term);
        OmegaLive live;
        live.length = jobs[job].length;
        live.job = (unsigned int)job;
        live.index = index;
        live.steps = 0ull;
        live.power = 1ull;
        live.since = 0ull;
        live.least = OMEGA_ENGINE_NONE - 1u;
        live.term.assign(term.begin(), term.end());
        live.held = live.term;
        live.held_reach = omega_engine_spine(live.held, live.held_ends);
        live.fate = -1;
        live.bits = 0ull;
        pool.push_back(std::move(live));
    }
}

static int omega_engine(SimTally *tally, const OmegaCounts *counts, unsigned int workers, const char *ledger,
                        OmegaEngineReport *report, std::vector<OmegaSettled> *crossed, OmegaTally *fates)
{
    omega_tally_open(fates);
    memset(report, 0, sizeof(*report));
    std::vector<OmegaEngineJob> kept;
    if (ledger != NULL)
    {
        omega_engine_ledger_read(ledger, kept);
    }
    // the plan: each length in rank order, cut every OMEGA_ENGINE_JOB terms
    std::vector<OmegaEngineJob> jobs;
    for (unsigned int length = 2u; length <= counts->length; length += 1u)
    {
        const unsigned long long total = omega_count(counts, length, 0u);
        for (unsigned long long from = 0ull; from < total; from += OMEGA_ENGINE_JOB)
        {
            OmegaEngineJob job;
            job.length = length;
            job.from = from;
            job.count = ((total - from) < OMEGA_ENGINE_JOB) ? (total - from) : OMEGA_ENGINE_JOB;
            job.settled = 0ull;
            omega_tally_open(&job.tally);
            const OmegaEngineJob *found = NULL;
            for (const OmegaEngineJob &one : kept)
            {
                if ((one.length == length) && (one.from == from) && (one.count == job.count))
                {
                    found = &one;
                    break;
                }
            }
            if (found != NULL)
            {
                omega_merge(fates, &found->tally);
                report->jobs_kept += 1ull;
                continue;
            }
            jobs.push_back(job);
        }
    }
    std::map<unsigned long long, OmegaProgram> programs;
    EngineError error;
    memset(&error, 0, sizeof(error));
    std::vector<OmegaLive> pool;
    std::vector<size_t> stepping;
    std::vector<OmegaToken> reducts;
    std::vector<unsigned int> round_tokens;
    std::vector<unsigned int> round_plans;
    std::vector<unsigned long long> round_sources;
    std::vector<unsigned int> index;
    std::vector<unsigned int> out;
    std::vector<int> scratch;
    unsigned int *device_tokens = NULL;
    unsigned int *device_plans = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    size_t device_room[4] = {0u, 0u, 0u, 0u};
    size_t next_job = 0u;
    int good = 1;
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    unsigned long long report_at = 1ull;
    while ((good != 0) && ((next_job < jobs.size()) || !pool.empty()))
    {
        while ((next_job < jobs.size()) && (pool.size() < OMEGA_ENGINE_ADMIT))
        {
            omega_engine_admit(counts, jobs, next_job, pool);
            next_job += 1u;
        }
        omega_engine_threads(pool.size(), workers, [&pool](size_t first, size_t last)
                             { omega_engine_survey(&pool, first, last); });
        // the terms that step this round, their records laid end to end
        stepping.clear();
        size_t in_total = 0u;
        size_t out_total = 0u;
        unsigned long long most_token = 1ull;
        unsigned long long most_depth = 0ull;
        unsigned long long most_bound = 0ull;
        for (size_t at = 0u; at < pool.size(); at += 1u)
        {
            OmegaLive *const live = &pool[at];
            report->most_tokens = (live->term.size() > report->most_tokens) ? live->term.size() : report->most_tokens;
            if (live->fate >= 0)
            {
                continue;
            }
            live->in_base = in_total;
            live->out_base = out_total;
            in_total += live->term.size();
            out_total += live->out_size;
            most_token = (live->most_token > most_token) ? live->most_token : most_token;
            most_depth = (live->most_depth > most_depth) ? live->most_depth : most_depth;
            most_bound = (live->most_bound > most_bound) ? live->most_bound : most_bound;
            stepping.push_back(at);
        }
        // the round's host records; a term the machine's memory cannot hold is parked, the largest first
        int held = 0;
        while ((held == 0) && !stepping.empty())
        {
            OmegaRound round;
            round.token_bits = omega_engine_bits_of(most_token) + 1u;
            round.depth_bits = omega_engine_bits_of(most_depth);
            round.bound_bits = omega_engine_bits_of(most_bound);
            round.token_limbs = (round.token_bits + 31u) / 32u;
            round.plan_limbs = (round.depth_bits + round.bound_bits + 2u + 31u) / 32u;
            try
            {
                round_tokens.assign(in_total * round.token_limbs, 0u);
                round_plans.assign(out_total * round.plan_limbs, 0u);
                round_sources.resize(out_total);
                reducts.resize(out_total);
                held = 1;
            }
            catch (const std::bad_alloc &)
            {
                size_t largest = 0u;
                for (size_t at = 1u; at < stepping.size(); at += 1u)
                {
                    largest = (pool[stepping[at]].out_size > pool[stepping[largest]].out_size) ? at : largest;
                }
                OmegaLive *const live = &pool[stepping[largest]];
                live->fate = OMEGA_GREW;
                report->parked += 1ull;
                stepping.erase(stepping.begin() + (long long)largest);
                in_total = 0u;
                out_total = 0u;
                for (size_t at = 0u; at < stepping.size(); at += 1u)
                {
                    pool[stepping[at]].in_base = in_total;
                    pool[stepping[at]].out_base = out_total;
                    in_total += pool[stepping[at]].term.size();
                    out_total += pool[stepping[at]].out_size;
                }
                continue;
            }
            round.tokens = round_tokens.data();
            round.plans = round_plans.data();
            round.sources = round_sources.data();
            omega_engine_threads(stepping.size(), workers, [&pool, &stepping, &round](size_t first, size_t last)
                                 { omega_engine_lay(&pool, &stepping, first, last, &round); });
            // the record program for this round's widths
            const unsigned long long widths = ((unsigned long long)round.token_bits << 40u)
                                            | ((unsigned long long)round.depth_bits << 20u) | round.bound_bits;
            if (programs.find(widths) == programs.end())
            {
                OmegaProgram program;
                program.token_bits = round.token_bits;
                program.depth_bits = round.depth_bits;
                program.bound_bits = round.bound_bits;
                if (omega_program_load(&program, &error) == 0)
                {
                    sim_check(tally, 0, "engine: the reduct program imprints and loads for the round's widths");
                    good = 0;
                    break;
                }
                programs[widths] = program;
            }
            const OmegaProgram *const program = &programs[widths];
            const unsigned int out_limbs = program->layout.out_limbs;
            // the sweeps, each cut where its sources would span past the engine's 32-bit index
            size_t sweep_first = 0u;
            while ((good != 0) && (sweep_first < out_total))
            {
                unsigned long long lowest = round_sources[sweep_first];
                unsigned long long highest = lowest;
                size_t sweep_last = sweep_first + 1u;
                while ((sweep_last < out_total) && ((sweep_last - sweep_first) < OMEGA_ENGINE_SWEEP))
                {
                    const unsigned long long source = round_sources[sweep_last];
                    const unsigned long long low = (source < lowest) ? source : lowest;
                    const unsigned long long high = (source > highest) ? source : highest;
                    if ((high - low) > 0xFFFFFFFFull)
                    {
                        break;
                    }
                    lowest = low;
                    highest = high;
                    sweep_last += 1u;
                }
                const size_t lanes = sweep_last - sweep_first;
                const size_t sources = (size_t)(highest - lowest) + 1u;
                index.resize(lanes * 2u);
                for (size_t lane = 0u; lane < lanes; lane += 1u)
                {
                    index[2u * lane] = (unsigned int)(round_sources[sweep_first + lane] - lowest);
                    index[(2u * lane) + 1u] = (unsigned int)lane;
                }
                const size_t need[4] = {sources * round.token_limbs * sizeof(unsigned int),
                                        lanes * round.plan_limbs * sizeof(unsigned int),
                                        lanes * 2u * sizeof(unsigned int), lanes * out_limbs * sizeof(unsigned int)};
                unsigned int **const rooms[4] = {&device_tokens, &device_plans, &device_index, &device_out};
                for (unsigned int room = 0u; (good != 0) && (room < 4u); room += 1u)
                {
                    if (need[room] > device_room[room])
                    {
                        (void)cudaFree(*rooms[room]);
                        *rooms[room] = NULL;
                        device_room[room] = 0u;
                        good = sim_took(tally, cudaMalloc((void **)rooms[room], need[room]), "engine: device room");
                        device_room[room] = (good != 0) ? need[room] : 0u;
                    }
                }
                good = good
                    && sim_took(tally, cudaMemcpy(device_tokens, &round_tokens[lowest * round.token_limbs], need[0],
                                                  cudaMemcpyHostToDevice), "engine: tokens")
                    && sim_took(tally, cudaMemcpy(device_plans, &round_plans[sweep_first * round.plan_limbs], need[1],
                                                  cudaMemcpyHostToDevice), "engine: plans")
                    && sim_took(tally, cudaMemcpy(device_index, index.data(), need[2], cudaMemcpyHostToDevice),
                                "engine: index");
                if (good == 0)
                {
                    break;
                }
                const CycleRecordRunRequest run = {program->record,
                                                   {device_tokens, device_plans, NULL},
                                                   {(unsigned long long)sources, (unsigned long long)lanes, 0ull},
                                                   device_index,
                                                   (unsigned long long)lanes,
                                                   device_out,
                                                   &error};
                if (cycle_record_run(&run) == CYCLE_REFUSED)
                {
                    sim_check(tally, 0, "engine: the record machine runs the round's sweep");
                    good = 0;
                    break;
                }
                out.resize(lanes * out_limbs);
                good = sim_took(tally, cudaMemcpy(out.data(), device_out, need[3], cudaMemcpyDeviceToHost),
                                "engine: reducts");
                for (size_t lane = 0u; (good != 0) && (lane < lanes); lane += 1u)
                {
                    if (omega_engine_take(&out[lane * out_limbs], program->out_offset, program->out_bits,
                                          &reducts[sweep_first + lane]) == 0)
                    {
                        sim_check(tally, 0, "engine: every reduct token is read back whole");
                        good = 0;
                    }
                }
                report->sweeps += 1ull;
                report->records += lanes;
                sweep_first = sweep_last;
            }
        }
        if (good == 0)
        {
            break;
        }
        omega_engine_threads(stepping.size(), workers, [&pool, &stepping, &reducts](size_t first, size_t last)
                             { omega_engine_watch(&pool, &stepping, first, last, &reducts); });
        report->rounds += 1ull;
        // the settled leave the pool into their jobs; a job whose every term settled is written to the ledger
        size_t kept_live = 0u;
        for (size_t at = 0u; at < pool.size(); at += 1u)
        {
            OmegaLive *const live = &pool[at];
            if (live->fate < 0)
            {
                if (kept_live != at)
                {
                    pool[kept_live] = std::move(*live);
                }
                kept_live += 1u;
                continue;
            }
            report->most_steps = (live->steps > report->most_steps) ? live->steps : report->most_steps;
            OmegaEngineJob *const job = &jobs[live->job];
            omega_engine_settle(counts, job, live, scratch, crossed);
            if (job->settled == job->count)
            {
                if ((ledger != NULL) && (omega_engine_ledger_write(ledger, job) == 0))
                {
                    sim_check(tally, 0, "engine: the ledger takes each finished job");
                    good = 0;
                }
                omega_merge(fates, &job->tally);
                report->jobs_run += 1ull;
            }
        }
        pool.resize(kept_live);
        if (report->rounds == report_at)
        {
            const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
            scriptura_text(&tally->line, "  round ");
            scriptura_decimal(&tally->line, report->rounds, 1u);
            scriptura_text(&tally->line, ": ");
            scriptura_decimal(&tally->line, pool.size(), 1u);
            scriptura_text(&tally->line, " live, ");
            scriptura_decimal(&tally->line, report->jobs_run, 1u);
            scriptura_text(&tally->line, " of ");
            scriptura_decimal(&tally->line, jobs.size(), 1u);
            scriptura_text(&tally->line, " jobs done, ");
            scriptura_decimal(&tally->line, report->records, 1u);
            scriptura_text(&tally->line, " records swept, the largest term ");
            scriptura_decimal(&tally->line, report->most_tokens, 1u);
            scriptura_text(&tally->line, " tokens, ");
            scriptura_decimal(&tally->line, (unsigned long long)(seconds * 1000.0), 1u);
            scriptura_text(&tally->line, " ms\n");
            sim_flush(tally);
            report_at *= 2ull;
        }
    }
    for (std::map<unsigned long long, OmegaProgram>::iterator one = programs.begin(); one != programs.end(); ++one)
    {
        omega_program_free(&one->second);
    }
    (void)cudaFree(device_tokens);
    (void)cudaFree(device_plans);
    (void)cudaFree(device_index);
    (void)cudaFree(device_out);
    return good;
}

// a term from its code, for the checks below
static std::vector<int> omega_term(const char *code)
{
    std::vector<int> term;
    size_t at = 0u;
    while (code[at] != '\0')
    {
        if (code[at] == '0')
        {
            term.push_back((code[at + 1u] == '0') ? OMEGA_LAMBDA : OMEGA_APPLY);
            at += 2u;
        }
        else
        {
            int index = 0;
            while (code[at] == '1')
            {
                index += 1;
                at += 1u;
            }
            term.push_back(index);
            at += 1u;
        }
    }
    return term;
}

static OmegaFate omega_fate_of(const char *code, unsigned int steps, unsigned int tokens)
{
    std::vector<int> term = omega_term(code);
    std::vector<int> next;
    std::vector<int> held;
    unsigned int taken = 0u;
    return omega_run(term, next, held, steps, tokens, &taken);
}

// the bits of a mass scaled by 2^64
static void omega_bits(ScripturaLine *line, const AnchorExactInteger *value, unsigned int bits)
{
    scriptura_text(line, "0.");
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int place = 63u - bit;
        scriptura_character(line, (((value->limb[place / 32u] >> (place % 32u)) & 1u) != 0u) ? '1' : '0');
    }
}

// the mass sum of count[n] 2^-n scaled by 2^64, exactly
static void omega_dyadic(AnchorExactInteger *value, const unsigned long long *count, unsigned int length)
{
    anchor_exact_zero(value);
    for (unsigned int bits = 2u; bits <= length; bits += 1u)
    {
        AnchorExactInteger part;
        AnchorExactInteger scale;
        sim_exact_whole(&part, count[bits]);
        sim_exact_whole(&scale, 1ull << (64u - bits));
        AnchorExactInteger product;
        (void)sim_exact_product(&part, &scale, &product);
        (void)sim_exact_sum(value, &product, value);
    }
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    static char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    static OmegaCounts counts;
    // L alone runs on the engine, bounded by nothing. L, steps and tokens run the budgeted kernel on the device
    // ("cpu" after them: on the host), kept as the cross-check. "--ledger <path>" plans either run as jobs.
    counts.length = (argc > 1) ? (unsigned int)strtoul(argv[1], NULL, 10) : OMEGA_LENGTH_DEFAULT;
    const int budgeted = (argc > 2) && (argv[2][0] >= '0') && (argv[2][0] <= '9');
    counts.steps = budgeted ? (unsigned int)strtoul(argv[2], NULL, 10) : OMEGA_STEPS_DEFAULT;
    counts.tokens = (budgeted && (argc > 3)) ? (unsigned int)strtoul(argv[3], NULL, 10) : OMEGA_TOKENS_DEFAULT;
    const int on_engine = !budgeted;
    int on_device = budgeted;
    const char *ledger = NULL;
    for (int at = 2; at < argc; at += 1)
    {
        if (strcmp(argv[at], "cpu") == 0)
        {
            on_device = 0;
        }
        else if ((strcmp(argv[at], "--ledger") == 0) && ((at + 1) < argc))
        {
            at += 1;
            ledger = argv[at];
        }
    }
    if ((counts.length < 4u) || (counts.length > OMEGA_LENGTH_MOST))
    {
        scriptura_text(&tally.line, "  the length must be from 4 to 60 bits\n");
        sim_flush(&tally);
        return 2;
    }
    if ((on_device != 0) && ((counts.tokens < 64u) || (counts.tokens > 16383u)))
    {
        // the device holds a term, its indices and its spine ends in 16 bits, in rooms twice the token budget
        scriptura_text(&tally.line, "  on the device the token budget must be from 64 to 16383\n");
        sim_flush(&tally);
        return 2;
    }
    omega_count_all(&counts);

    // the enumeration is checked against an independent parse of every code
    int counted = 1;
    const unsigned int parsed_most = (counts.length < OMEGA_PARSED_MOST) ? counts.length : OMEGA_PARSED_MOST;
    for (unsigned int length = 2u; length <= parsed_most; length += 1u)
    {
        unsigned long long closed = 0ull;
        for (unsigned long long code = 0ull; code < (1ull << length); code += 1ull)
        {
            unsigned int at = 0u;
            closed += ((omega_parse(code, length, &at, 0u) != 0) && (at == length)) ? 1ull : 0ull;
        }
        counted = counted && (closed == omega_count(&counts, length, 0u));
    }
    sim_check(&tally, counted, "the closed term counts equal a parse of every code through 22 bits");
    int ranked = 1;
    for (unsigned int length = 2u; (length <= 16u) && (length <= counts.length); length += 1u)
    {
        for (unsigned long long index = 0ull; index < omega_count(&counts, length, 0u); index += 1ull)
        {
            std::vector<int> term;
            omega_unrank(&counts, length, 0u, index, term);
            unsigned long long bits = 0ull;
            for (size_t at = 0u; at < term.size(); at += 1u)
            {
                bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
            }
            ranked = ranked && (bits == length) && (omega_end(term.data(), 0u) == term.size());
        }
    }
    sim_check(&tally, ranked, "every unranked term through 16 bits is one term of its length");
    // I, I I, omega omega, K I (omega omega), and (lambda x. x x x)(lambda x. x x x)
    sim_check(&tally, omega_fate_of("0010", 64u, 256u) == OMEGA_HALTS, "the identity is a normal form");
    sim_check(&tally, omega_fate_of("0100100010", 64u, 256u) == OMEGA_HALTS, "I I reduces to I");
    sim_check(&tally, omega_fate_of("010001101000011010", 64u, 256u) == OMEGA_LOOPS,
              "omega omega is watched returning to itself");
    sim_check(&tally, omega_fate_of("010100001100010010001101000011010", 64u, 256u) == OMEGA_HALTS,
              "K I (omega omega) halts, normal order dropping the loop");
    sim_check(&tally, omega_fate_of("01000101101010000101101010", 1000000u, 4096u) == OMEGA_DIVERGES,
              "(x x x)(x x x) is proven to grow forever: it returns at its own head");

    // a run on the device is one tessera job; it declares the count table it copies there, and the daemon measures
    // the rooms and the batch it grows to and keeps that peak under the run's arguments
    if (((on_engine != 0) || (on_device != 0))
        && !sim_job_submit(&tally, "chaitin_omega", argc, argv, sizeof(counts.count)))
    {
        return sim_close(&tally, "chaitin_omega");
    }

    // every closed term of at most L bits, run on the device unless the host is asked for
    const unsigned int workers = (std::thread::hardware_concurrency() == 0u) ? 1u : std::thread::hardware_concurrency();
    static OmegaTally fates;
    unsigned int device_threads = 0u;
    unsigned long long host_runs = 0ull;
    unsigned long long jobs_run = 0ull;
    unsigned long long jobs_kept = 0ull;
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    OmegaEngineReport engine_report;
    memset(&engine_report, 0, sizeof(engine_report));
    std::vector<OmegaSettled> crossed;
    if (on_engine != 0)
    {
        if (omega_engine(&tally, &counts, workers, ledger, &engine_report, &crossed, &fates) == 0)
        {
            return sim_close(&tally, "chaitin_omega");
        }
    }
    else if (on_device != 0)
    {
        if (omega_device(&tally, &counts, workers, ledger, &device_threads, &host_runs, &jobs_run, &jobs_kept, &fates)
            == 0)
        {
            return sim_close(&tally, "chaitin_omega");
        }
    }
    else
    {
        omega_host(&counts, counts.length, workers, &fates);
    }
    const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    if (on_device != 0)
    {
        // the host's run of the same terms under the same budgets must give every fate and busy beaver alike
        const unsigned int cross = (counts.length < OMEGA_CROSS_MOST) ? counts.length : OMEGA_CROSS_MOST;
        static OmegaTally host;
        omega_host(&counts, cross, workers, &host);
        int alike = (host.contradictions == 0ull);
        for (unsigned int length = 2u; length <= cross; length += 1u)
        {
            for (unsigned int fate = 0u; fate < 6u; fate += 1u)
            {
                alike = alike && (host.fate[fate][length] == fates.fate[fate][length]);
            }
            alike = alike && (host.most_steps[length] == fates.most_steps[length])
                 && (host.most_bits[length] == fates.most_bits[length])
                 && ((host.fate[OMEGA_HALTS][length] == 0ull)
                     || ((host.steps_champion[length] == fates.steps_champion[length])
                         && (host.bits_champion[length] == fates.bits_champion[length])));
        }
        sim_check(&tally, alike,
                  "the device's fates and busy beavers, champions included, equal the host's through 30 bits");
    }
    if (on_engine != 0)
    {
        // every term the engine settled through 24 bits, run again by omega_run with steps enough to reach the step
        // the engine settled it at and no token budget: the same fate at the same step, and the same normal form
        std::atomic<int> every(1);
        omega_engine_threads(crossed.size(), workers,
                             [&crossed, &every](size_t first, size_t last)
                             {
                                 std::vector<int> term;
                                 std::vector<int> next;
                                 std::vector<int> held;
                                 int same = 1;
                                 for (size_t at = first; at < last; at += 1u)
                                 {
                                     const OmegaSettled *const one = &crossed[at];
                                     if (one->fate == OMEGA_GREW)
                                     {
                                         continue;
                                     }
                                     term.clear();
                                     omega_unrank(&counts, one->length, 0u, one->index, term);
                                     unsigned int taken = 0u;
                                     const OmegaFate fate = omega_run(term, next, held, (unsigned int)one->steps + 1u,
                                                                      0xFFFFFFFFu, &taken);
                                     same = same && ((int)fate == one->fate)
                                         && ((fate != OMEGA_HALTS)
                                             || ((taken == one->steps) && (omega_code_bits(term) == one->bits)));
                                 }
                                 if (same == 0)
                                 {
                                     every = 0;
                                 }
                             });
        sim_check(&tally, (every.load() != 0) && !crossed.empty(),
                  "every term the engine settled through 24 bits: omega_run gives the same fate at the same step "
                  "and the same normal form");
    }

    // the mass past L, counted
    std::vector<unsigned long long> all_down;
    std::vector<unsigned long long> all_up;
    std::vector<unsigned long long> closed_up;
    omega_all_mass(all_down, 0);
    omega_all_mass(all_up, 1);
    omega_closed_mass(all_up, closed_up);
    unsigned long long parsed = 0ull;
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        parsed += all_down[length];
    }
    unsigned long long past = OMEGA_ONE - parsed;
    for (unsigned int length = counts.length + 1u; length <= OMEGA_COUNTED; length += 1u)
    {
        past += closed_up[length];
    }
    sim_check(&tally, parsed <= OMEGA_ONE, "the counted parse mass stays below 1");
    std::vector<unsigned long long> normal_down;
    omega_normal_mass(normal_down);
    unsigned long long normal_past = 0ull;
    int normal_within = 1;
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        normal_within = normal_within && (normal_down[length] <= closed_up[length]);
        normal_past += (length > counts.length) ? normal_down[length] : 0ull;
    }
    sim_check(&tally, normal_within, "the normal form mass is within the closed mass at every length");

    AnchorExactInteger lower;
    AnchorExactInteger open;
    AnchorExactInteger upper;
    AnchorExactInteger tail;
    AnchorExactInteger four;
    AnchorExactInteger programs;
    // a halt is a normal form reached or a type found
    std::vector<unsigned long long> halted(counts.length + 1u, 0ull);
    std::vector<unsigned long long> unsettled(counts.length + 1u, 0ull);
    for (unsigned int length = 0u; length <= counts.length; length += 1u)
    {
        halted[length] = fates.fate[OMEGA_HALTS][length] + fates.fate[OMEGA_TYPED][length];
        unsettled[length] = fates.fate[OMEGA_OPEN][length] + fates.fate[OMEGA_GREW][length];
    }
    omega_dyadic(&lower, halted.data(), counts.length);
    sim_check(&tally, fates.contradictions == 0ull,
              "no term proven to loop or to grow forever has a simple type (every typable term halts)");
    omega_dyadic(&open, unsettled.data(), counts.length);
    std::vector<unsigned long long> closed_counts(counts.length + 1u, 0ull);
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        closed_counts[length] = omega_count(&counts, length, 0u);
    }
    omega_dyadic(&programs, closed_counts.data(), counts.length);
    // the fixed point's 2^-62 scaled to 2^-64
    sim_exact_whole(&tail, past);
    sim_exact_whole(&four, 4ull);
    (void)sim_exact_product(&tail, &four, &tail);
    (void)sim_exact_sum(&lower, &open, &upper);
    (void)sim_exact_sum(&upper, &tail, &upper);
    // the normal forms past L halt unrun
    AnchorExactInteger normal;
    sim_exact_whole(&normal, normal_past);
    (void)sim_exact_product(&normal, &four, &normal);
    (void)sim_exact_sum(&lower, &normal, &lower);
    sim_check(&tally, (lower.sign > 0) && (anchor_exact_compare(&lower, &upper) < 0),
              "the bracket is proper: 0 < lower < upper");

    unsigned int shared = 0u;
    while (shared < 64u)
    {
        const unsigned int place = 63u - shared;
        const unsigned int low_bit = (lower.limb[place / 32u] >> (place % 32u)) & 1u;
        const unsigned int high_bit = (upper.limb[place / 32u] >> (place % 32u)) & 1u;
        if (low_bit != high_bit)
        {
            break;
        }
        shared += 1u;
    }

    unsigned long long totals[6] = {0ull, 0ull, 0ull, 0ull, 0ull, 0ull};
    for (unsigned int fate = 0u; fate < 6u; fate += 1u)
    {
        for (unsigned int length = 0u; length <= counts.length; length += 1u)
        {
            totals[fate] += fates.fate[fate][length];
        }
    }
    scriptura_text(&tally.line, "  Chaitin's Omega for the binary lambda calculus, every closed term through ");
    scriptura_decimal(&tally.line, counts.length, 1u);
    scriptura_text(&tally.line, " bits (");
    scriptura_decimal(&tally.line, counts.steps, 1u);
    scriptura_text(&tally.line, " steps, ");
    scriptura_decimal(&tally.line, counts.tokens, 1u);
    scriptura_text(&tally.line, " tokens, ");
    if (on_device != 0)
    {
        scriptura_decimal(&tally.line, device_threads, 1u);
        scriptura_text(&tally.line, " device threads, ");
        scriptura_decimal(&tally.line, host_runs, 1u);
        scriptura_text(&tally.line, " runs past the device's budgets ran on the host, ");
        scriptura_decimal(&tally.line, jobs_run, 1u);
        scriptura_text(&tally.line, " jobs run, ");
        scriptura_decimal(&tally.line, jobs_kept, 1u);
        scriptura_text(&tally.line, " from the ledger, ");
    }
    else
    {
        scriptura_decimal(&tally.line, workers, 1u);
        scriptura_text(&tally.line, " host threads, ");
    }
    scriptura_decimal(&tally.line, (unsigned long long)(seconds * 1000.0), 1u);
    scriptura_text(&tally.line, " ms)\n  length    closed      halts  typed halts     loops  grows forever  out of steps"
                                "  outgrew\n");
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        scriptura_decimal_columns(&tally.line, length, 8u);
        scriptura_decimal_columns(&tally.line, omega_count(&counts, length, 0u), 10u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_HALTS][length], 11u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_TYPED][length], 13u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_LOOPS][length], 10u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_DIVERGES][length], 15u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_OPEN][length], 14u);
        scriptura_decimal_columns(&tally.line, fates.fate[OMEGA_GREW][length], 9u);
        scriptura_character(&tally.line, '\n');
    }
    scriptura_text(&tally.line, "  terms run ");
    scriptura_decimal(&tally.line, totals[0] + totals[1] + totals[2] + totals[3] + totals[4] + totals[5], 1u);
    scriptura_text(&tally.line, ": halted ");
    scriptura_decimal(&tally.line, totals[OMEGA_HALTS], 1u);
    scriptura_text(&tally.line, ", proven to halt by a simple type ");
    scriptura_decimal(&tally.line, totals[OMEGA_TYPED], 1u);
    scriptura_text(&tally.line, ", proven to loop ");
    scriptura_decimal(&tally.line, totals[OMEGA_LOOPS], 1u);
    scriptura_text(&tally.line, ", proven to grow forever ");
    scriptura_decimal(&tally.line, totals[OMEGA_DIVERGES], 1u);
    scriptura_text(&tally.line, ", out of steps ");
    scriptura_decimal(&tally.line, totals[OMEGA_OPEN], 1u);
    scriptura_text(&tally.line, ", outgrew the space ");
    scriptura_decimal(&tally.line, totals[OMEGA_GREW], 1u);
    scriptura_text(&tally.line, "\n  program mass through L  ");
    omega_bits(&tally.line, &programs, 64u);
    scriptura_text(&tally.line, "\n  normal forms past L     ");
    omega_bits(&tally.line, &normal, 64u);
    scriptura_text(&tally.line, "\n  Omega lower             ");
    omega_bits(&tally.line, &lower, 64u);
    scriptura_text(&tally.line, "\n  open mass               ");
    omega_bits(&tally.line, &open, 64u);
    scriptura_text(&tally.line, "\n  closed mass past L      ");
    omega_bits(&tally.line, &tail, 64u);
    scriptura_text(&tally.line, "\n  Omega upper             ");
    omega_bits(&tally.line, &upper, 64u);
    scriptura_text(&tally.line, "\n  Omega = 0.");
    for (unsigned int bit = 0u; bit < shared; bit += 1u)
    {
        const unsigned int place = 63u - bit;
        scriptura_character(&tally.line, (((lower.limb[place / 32u] >> (place % 32u)) & 1u) != 0u) ? '1' : '0');
    }
    scriptura_text(&tally.line, "...  (");
    scriptura_decimal(&tally.line, shared, 1u);
    scriptura_text(&tally.line, " bits proven)\n");
    sim_flush(&tally);

    // the busy beaver table: a length with an open term reads "at least", since the open one may halt later
    // and larger
    scriptura_text(&tally.line, "\n  busy beavers of the halting terms (>= where a term of that length is still open)\n"
                                "  length  most steps  step champion                             BB lambda  normal form "
                                "champion\n");
    sim_flush(&tally);
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        if (fates.fate[OMEGA_HALTS][length] == 0ull)
        {
            continue;
        }
        // a typed halt proves a normal form exists without writing it, so its size is still unknown
        const int settled = ((unsettled[length] + fates.fate[OMEGA_TYPED][length]) == 0ull);
        scriptura_decimal_columns(&tally.line, length, 8u);
        scriptura_text(&tally.line, settled ? "    " : "  >=");
        scriptura_decimal_columns(&tally.line, fates.most_steps[length], 8u);
        scriptura_text(&tally.line, "  ");
        std::vector<int> champion;
        omega_unrank(&counts, length, 0u, fates.steps_champion[length], champion);
        omega_code_text(&tally.line, champion);
        for (unsigned int pad = length; pad < 42u; pad += 1u)
        {
            scriptura_character(&tally.line, ' ');
        }
        scriptura_text(&tally.line, settled ? "  " : ">=");
        scriptura_decimal_columns(&tally.line, fates.most_bits[length], 8u);
        scriptura_text(&tally.line, "  ");
        champion.clear();
        omega_unrank(&counts, length, 0u, fates.bits_champion[length], champion);
        omega_code_text(&tally.line, champion);
        scriptura_character(&tally.line, '\n');
        sim_flush(&tally);
    }
    // BusyBeaverWiki's BB lambda (OEIS A333479) from 4 through 33 bits; 0 where no closed term exists. A row with a
    // term still open holds only a lower bound, and the published value is the true maximum, so the two meeting
    // means the run reached the champion; past 33 the champions outgrow any space here (327686 bits at 34)
    static const unsigned long long published_most[34] = {0ull,  0ull,  0ull,  0ull,  4ull,   0ull,   6ull,
                                                          7ull,  8ull,  9ull,  10ull, 11ull,  12ull,  13ull,
                                                          14ull, 15ull, 16ull, 17ull, 18ull,  19ull,  20ull,
                                                          22ull, 24ull, 26ull, 30ull, 42ull,  52ull,  44ull,
                                                          58ull, 223ull, 160ull, 267ull, 298ull, 1812ull};
    int published = 1;
    int bounded = 1;
    for (unsigned int length = 4u; (length <= 33u) && (length <= counts.length); length += 1u)
    {
        const int settled = ((unsettled[length] + fates.fate[OMEGA_TYPED][length]) == 0ull);
        published = published && (fates.most_bits[length] == published_most[length]);
        bounded = bounded && (fates.most_bits[length] <= published_most[length])
               && ((settled == 0) || (fates.most_bits[length] == published_most[length]));
    }
    // under any budgets: never past the true maximum, and on it wherever every term of the length halted
    sim_check(&tally, bounded, "BB lambda is at most BusyBeaverWiki's (OEIS A333479) through 33 bits, and equal to it "
                               "at every settled length");
    if ((counts.steps >= OMEGA_STEPS_DEFAULT) && (counts.tokens >= OMEGA_TOKENS_DEFAULT))
    {
        // the default budgets reach every champion through 33 bits, the 1812-bit normal form at 33 the largest
        sim_check(&tally, published,
                  "BB lambda equals BusyBeaverWiki's (OEIS A333479) at every length through 33 bits");
    }
    return sim_close(&tally, "chaitin_omega");
}
