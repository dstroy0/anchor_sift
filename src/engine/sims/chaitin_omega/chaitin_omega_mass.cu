// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_mass.cu: mass, simple types and the host's workers
#include "chaitin_omega_internal.h"

// an independent parse of a code of exactly `length` bits: 1 where it is one closed term using every bit
int omega_parse(unsigned long long code, unsigned int length, unsigned int *at, unsigned int depth)
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
void omega_all_mass(std::vector<unsigned long long> &mass, int up)
{
    mass.assign(OMEGA_COUNTED + 1u, 0ull);
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        unsigned long long pairs = 0ull;
        for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
        {
            pairs += omega_mass_product(mass[left], mass[length - 2u - left], up);
        }
        const unsigned long long quarter =
            (up != 0) ? ((mass[length - 2u] + pairs + 3ull) / 4ull) : ((mass[length - 2u] + pairs) / 4ull);
        mass[length] = omega_mass_of(length, up) + quarter;
    }
}

// c(n, 0) rounded up, the mass of the n-bit closed codes, from c(n, k) closed under k lambdas; past k = n - 1
// every variable fits and c is a(n)
void omega_closed_mass(const std::vector<unsigned long long> &all_up, std::vector<unsigned long long> &closed)
{
    std::vector<std::vector<unsigned long long>> under(OMEGA_COUNTED + 1u);
    for (unsigned int length = 0u; length <= OMEGA_COUNTED; length += 1u)
    {
        under[length].assign(length + 1u, 0ull);
    }
    // under[n][k] for k < n; k >= n - 1 reads a(n)
    auto read = [&](unsigned int length, unsigned int depth) -> unsigned long long {
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
void omega_normal_mass(std::vector<unsigned long long> &normal_closed)
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
                    unsigned int length, unsigned int depth) -> unsigned long long {
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
static int omega_type_infer(OmegaTypes *types, const std::vector<int> &term, size_t at, unsigned int *type, size_t *end)
{
    const int token = term[at];
    if (token == OMEGA_LAMBDA)
    {
        const unsigned int argument = omega_type_new(types, 0, 0u, 0u);
        types->bound.push_back(argument);
        unsigned int body = 0u;
        const int ok = omega_type_infer(types, term, at + 1u, &body, end);
        types->bound.pop_back();
        *type = omega_type_new(types, 1, argument, body);
        return ok;
    }
    if (token == OMEGA_APPLY)
    {
        unsigned int function = 0u;
        unsigned int argument = 0u;
        size_t middle = 0u;
        if ((omega_type_infer(types, term, at + 1u, &function, &middle) == 0) ||
            (omega_type_infer(types, term, middle, &argument, end) == 0))
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

void omega_results_open(OmegaResults *results)
{
    memset(results, 0, sizeof(*results));
    for (unsigned int length = 0u; length <= OMEGA_LENGTH_MAX; length += 1u)
    {
        results->steps_champion[length] = ~0ull;
        results->bits_champion[length] = ~0ull;
    }
}

// a busy beaver candidate: runs finish out of rank order. A tie keeps the lower rank
void omega_champion(unsigned long long *maximum, unsigned long long *champion, unsigned long long value,
                    unsigned long long index)
{
    if ((value > *maximum) || ((value == *maximum) && (index < *champion)))
    {
        *maximum = value;
        *champion = index;
    }
}

// one term's fate into the results. A run that halted leaves the normal form in `term`; any other has the type
// certificate read off the program itself, since the run left the term reduced.
void omega_settle(const OmegaCounts *counts, unsigned int length, unsigned long long index, OmegaFate fate,
                  unsigned int taken, std::vector<int> &term, OmegaResults *results)
{
    if (fate != OMEGA_HALTS)
    {
        term.clear();
        omega_unrank(counts, length, 0u, index, term);
        const int typed = omega_simply_typed(term);
        // a typable term halts. A proven loop or unbounded growth that types is a broken proof
        results->contradictions += ((typed != 0) && ((fate == OMEGA_LOOPS) || (fate == OMEGA_DIVERGES))) ? 1ull : 0ull;
        fate = ((typed != 0) && ((fate == OMEGA_OPEN) || (fate == OMEGA_GREW))) ? OMEGA_TYPED : fate;
    }
    results->fate[fate][length] += 1ull;
    if (fate == OMEGA_HALTS)
    {
        omega_champion(&results->max_steps[length], &results->steps_champion[length], taken, index);
        omega_champion(&results->max_bits[length], &results->bits_champion[length], omega_code_bits(term), index);
    }
}

void omega_merge(OmegaResults *into, const OmegaResults *one)
{
    into->contradictions += one->contradictions;
    for (unsigned int length = 0u; length <= OMEGA_LENGTH_MAX; length += 1u)
    {
        for (unsigned int fate = 0u; fate < 6u; fate += 1u)
        {
            into->fate[fate][length] += one->fate[fate][length];
        }
        if (one->steps_champion[length] != ~0ull)
        {
            omega_champion(&into->max_steps[length], &into->steps_champion[length], one->max_steps[length],
                           one->steps_champion[length]);
            omega_champion(&into->max_bits[length], &into->bits_champion[length], one->max_bits[length],
                           one->bits_champion[length]);
        }
    }
}

static void omega_worker(const OmegaCounts *counts, const std::vector<unsigned long long> *chunk_length,
                         const std::vector<unsigned long long> *chunk_from, std::atomic<unsigned long long> *next_chunk,
                         OmegaResults *results)
{
    std::vector<int> term;
    std::vector<int> next;
    std::vector<int> stored;
    term.reserve(counts->tokens + 64u);
    next.reserve(counts->tokens + 64u);
    stored.reserve(counts->tokens + 64u);
    omega_results_open(results);
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
            const OmegaFate fate = omega_run(term, next, stored, counts->steps, counts->tokens, &taken);
            omega_settle(counts, length, index, fate, taken, term, results);
        }
    }
}

// every closed term through `maximum` bits run on the host's threads
void omega_host(const OmegaCounts *counts, unsigned int maximum, unsigned int workers, OmegaResults *fates)
{
    std::vector<unsigned long long> chunk_length;
    std::vector<unsigned long long> chunk_from;
    for (unsigned int length = 2u; length <= maximum; length += 1u)
    {
        for (unsigned long long from = 0ull; from < omega_count(counts, length, 0u); from += OMEGA_CHUNK)
        {
            chunk_length.push_back(length);
            chunk_from.push_back(from);
        }
    }
    std::vector<OmegaResults> tallies(workers);
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
    omega_results_open(fates);
    for (unsigned int worker = 0u; worker < workers; worker += 1u)
    {
        omega_merge(fates, &tallies[worker]);
    }
}
