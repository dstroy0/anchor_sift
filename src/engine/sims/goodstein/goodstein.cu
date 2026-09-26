// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Goodstein's sequences, held exactly and never expanded (R. L. Goodstein, "On the restricted ordinal theorem",
// J. Symbolic Logic 9, 1944; L. Kirby and J. Paris, "Accessible independence results for Peano arithmetic", Bull.
// London Math. Soc. 14, 1982). n is written in hereditary base b, every exponent written in base b again; a step writes
// every b as b + 1 and subtracts one. With b read as omega the same tree is an ordinal below epsilon_0 in Cantor normal
// form: the bump leaves the tree as it is, and the subtraction lowers it, so every sequence reaches 0. The start 2^^k
// is omega^^k, so 16 is omega^omega^omega. The values grow as towers and are never formed: a form is the tree itself,
// with the base a separate number, and b^L - 1 at a large L is held as one run of coefficient b - 1 over the exponents
// 0 .. L - 1 of the base the run was made at (Doug, 24 September: "perform tetration of omega").
// 1. The bump keeps the tree: for every n below GOODSTEIN_LEMMA_BELOW at bases 2 to 6, n bumped numerically and
//    written in base b + 1 is the tree of n in base b.
// 2. 2^^k in hereditary base 2 is omega^^k for k = 1 to 4, and the towers climb.
// 3. The starts 1, 2 and 3 reach 0 in 1, 3 and 5 steps, every value the numeric sequence's.
// 4. The starts 4, 16 and 65536 run GOODSTEIN_STEPS steps: every ordinal stands strictly below the one before, and
//    every value equals the numeric sequence's wherever that fits 64 bits.

#include "sim.h"

#include <algorithm>
#include <vector>

#define GOODSTEIN_STEPS 1000000ull

#define GOODSTEIN_LEMMA_BELOW 20000ull

#define GOODSTEIN_LEMMA_BASE_MOST 6ull

#define GOODSTEIN_TOWER 4u

#define GOODSTEIN_SMALL_STEPS_MOST 64ull

// the most term comparisons one ordinal comparison may make before it is reported unfinished
#define GOODSTEIN_COMPARE_TERMS 1000000ull

// the most characters an ordinal is printed with
#define GOODSTEIN_PRINT_ROOM 360u

struct GoodsteinBlock;

// a hereditary form, its terms highest first; the empty form is 0
struct GoodsteinForm
{
    std::vector<GoodsteinBlock> blocks;
};

// one term c . b^E (origin 0), or a run: c . b^tree(k) for every integer k from high down to low, tree(k) being k
// written hereditarily in the base the run was made at (origin)
struct GoodsteinBlock
{
    GoodsteinForm exponent;
    unsigned long long coefficient;
    unsigned long long origin;
    unsigned long long low;
    unsigned long long high;
};

typedef struct
{
    unsigned long long terms;
    int exhausted;
} GoodsteinBudget;

typedef struct
{
    const GoodsteinForm *form;
    size_t block;
    unsigned long long high;
} GoodsteinCursor;

static GoodsteinBlock goodstein_term(const GoodsteinForm &exponent, unsigned long long coefficient)
{
    GoodsteinBlock block;
    block.exponent = exponent;
    block.coefficient = coefficient;
    block.origin = 0ull;
    block.low = 0ull;
    block.high = 0ull;
    return block;
}

// value written hereditarily in base
static GoodsteinForm goodstein_of(unsigned long long value, unsigned long long base)
{
    GoodsteinForm form;
    unsigned long long position = 0ull;
    unsigned long long rest = value;
    while (rest != 0ull)
    {
        const unsigned long long digit = rest % base;
        if (digit != 0ull)
        {
            form.blocks.push_back(goodstein_term(goodstein_of(position, base), digit));
        }
        rest /= base;
        position += 1ull;
    }
    std::reverse(form.blocks.begin(), form.blocks.end());
    return form;
}

// omega^^height: omega^1 at height 1, and omega raised to the tower below at each height above
static GoodsteinForm goodstein_tower(unsigned int height)
{
    GoodsteinForm form;
    form.blocks.push_back(goodstein_term(GoodsteinForm(), 1ull));
    for (unsigned int level = 0u; level < height; level += 1u)
    {
        GoodsteinForm next;
        next.blocks.push_back(goodstein_term(form, 1ull));
        form = next;
    }
    return form;
}

static void goodstein_cursor_enter(GoodsteinCursor *cursor)
{
    if (cursor->block < cursor->form->blocks.size())
    {
        cursor->high = cursor->form->blocks[cursor->block].high;
    }
}

static void goodstein_cursor_next(GoodsteinCursor *cursor)
{
    const GoodsteinBlock &block = cursor->form->blocks[cursor->block];
    if ((block.origin == 0ull) || (cursor->high == block.low))
    {
        cursor->block += 1u;
        goodstein_cursor_enter(cursor);
    }
    else
    {
        cursor->high -= 1ull;
    }
}

// the order of two forms as ordinals, which is their order as numbers at any one base: terms compared highest first,
// exponents recursively, then coefficients. Two runs made at one base, level at their tops with one coefficient, agree
// term for term down to the higher of their lows, and are passed in one move.
static int goodstein_compare(const GoodsteinForm &left, const GoodsteinForm &right, GoodsteinBudget *budget)
{
    GoodsteinCursor one = {&left, 0u, 0ull};
    GoodsteinCursor other = {&right, 0u, 0ull};
    goodstein_cursor_enter(&one);
    goodstein_cursor_enter(&other);
    for (;;)
    {
        const int one_done = one.block >= left.blocks.size();
        const int other_done = other.block >= right.blocks.size();
        if ((one_done != 0) || (other_done != 0))
        {
            return (one_done == other_done) ? 0 : ((one_done != 0) ? -1 : 1);
        }
        if (budget->terms == 0ull)
        {
            budget->exhausted = 1;
            return 0;
        }
        budget->terms -= 1ull;
        const GoodsteinBlock &one_block = left.blocks[one.block];
        const GoodsteinBlock &other_block = right.blocks[other.block];
        if ((one_block.origin != 0ull) && (one_block.origin == other_block.origin) && (one.high == other.high)
            && (one_block.coefficient == other_block.coefficient))
        {
            const unsigned long long floor = std::max(one_block.low, other_block.low);
            if (one_block.low == floor)
            {
                one.block += 1u;
                goodstein_cursor_enter(&one);
            }
            else
            {
                one.high = floor - 1ull;
            }
            if (other_block.low == floor)
            {
                other.block += 1u;
                goodstein_cursor_enter(&other);
            }
            else
            {
                other.high = floor - 1ull;
            }
            continue;
        }
        GoodsteinForm one_tree;
        GoodsteinForm other_tree;
        if (one_block.origin != 0ull)
        {
            one_tree = goodstein_of(one.high, one_block.origin);
        }
        if (other_block.origin != 0ull)
        {
            other_tree = goodstein_of(other.high, other_block.origin);
        }
        const int top = goodstein_compare((one_block.origin == 0ull) ? one_block.exponent : one_tree,
                                          (other_block.origin == 0ull) ? other_block.exponent : other_tree, budget);
        if (budget->exhausted != 0)
        {
            return 0;
        }
        if (top != 0)
        {
            return top;
        }
        if (one_block.coefficient != other_block.coefficient)
        {
            return (one_block.coefficient > other_block.coefficient) ? 1 : -1;
        }
        goodstein_cursor_next(&one);
        goodstein_cursor_next(&other);
    }
}

// base^exponent, 0 where it leaves 64 bits
static int goodstein_power(unsigned long long base, unsigned long long exponent, unsigned long long *out)
{
    unsigned long long result = 1ull;
    for (unsigned long long done = 0ull; done < exponent; done += 1ull)
    {
        if (result > (~0ull / base))
        {
            return 0;
        }
        result *= base;
    }
    *out = result;
    return 1;
}

// total += coefficient . base^exponent, 0 where it leaves 64 bits
static int goodstein_add_term(unsigned long long *total, unsigned long long coefficient, unsigned long long base,
                              unsigned long long exponent)
{
    unsigned long long power = 0ull;
    if ((goodstein_power(base, exponent, &power) == 0) || (power > (~0ull / coefficient)))
    {
        return 0;
    }
    const unsigned long long term = power * coefficient;
    if (term > (~0ull - *total))
    {
        return 0;
    }
    *total += term;
    return 1;
}

// the form's value at base, 0 where it leaves 64 bits. A run's k-th exponent is at least k at any base at or above its
// origin, so a run reaching 64 overflows on its first term.
static int goodstein_value(const GoodsteinForm &form, unsigned long long base, unsigned long long *out)
{
    unsigned long long total = 0ull;
    for (const GoodsteinBlock &block : form.blocks)
    {
        if (block.origin == 0ull)
        {
            unsigned long long exponent = 0ull;
            if ((goodstein_value(block.exponent, base, &exponent) == 0)
                || (goodstein_add_term(&total, block.coefficient, base, exponent) == 0))
            {
                return 0;
            }
            continue;
        }
        for (unsigned long long k = block.high;; k -= 1ull)
        {
            unsigned long long exponent = 0ull;
            if ((goodstein_value(goodstein_of(k, block.origin), base, &exponent) == 0)
                || (goodstein_add_term(&total, block.coefficient, base, exponent) == 0))
            {
                return 0;
            }
            if (k == block.low)
            {
                break;
            }
        }
    }
    *out = total;
    return 1;
}

// subtract one at base: the lowest term c . b^L leaves (c - 1) . b^L and, where L > 0, the run of b - 1 over the
// exponents 0 .. L - 1 of this base. 0 where L's value at base leaves 64 bits, so the run's reach cannot be held.
static int goodstein_decrement(GoodsteinForm &form, unsigned long long base)
{
    const GoodsteinBlock lowest = form.blocks.back();
    GoodsteinForm exponent;
    if (lowest.origin == 0ull)
    {
        exponent = lowest.exponent;
        form.blocks.pop_back();
    }
    else
    {
        exponent = goodstein_of(lowest.low, lowest.origin);
        if (lowest.low == lowest.high)
        {
            form.blocks.pop_back();
        }
        else
        {
            form.blocks.back().low += 1ull;
        }
    }
    if (lowest.coefficient > 1ull)
    {
        form.blocks.push_back(goodstein_term(exponent, lowest.coefficient - 1ull));
    }
    if (!exponent.blocks.empty())
    {
        unsigned long long reach = 0ull;
        if (goodstein_value(exponent, base, &reach) == 0)
        {
            return 0;
        }
        GoodsteinBlock run;
        run.coefficient = base - 1ull;
        run.origin = base;
        run.low = 0ull;
        run.high = reach - 1ull;
        form.blocks.push_back(run);
    }
    return 1;
}

// the numeric step's bump: value in hereditary base b with every b made b + 1, 0 where it leaves 64 bits
static int goodstein_bump(unsigned long long value, unsigned long long base, unsigned long long *out)
{
    unsigned long long total = 0ull;
    unsigned long long position = 0ull;
    unsigned long long rest = value;
    while (rest != 0ull)
    {
        const unsigned long long digit = rest % base;
        if (digit != 0ull)
        {
            unsigned long long exponent = 0ull;
            if ((goodstein_bump(position, base, &exponent) == 0)
                || (goodstein_add_term(&total, digit, base + 1ull, exponent) == 0))
            {
                return 0;
            }
        }
        rest /= base;
        position += 1ull;
    }
    *out = total;
    return 1;
}

static void goodstein_print_term(ScripturaLine *line, const GoodsteinForm &exponent, unsigned long long coefficient,
                                 unsigned int *room);

// the form as an ordinal in Cantor normal form, w for omega, cut at the room left
static void goodstein_print(ScripturaLine *line, const GoodsteinForm &form, unsigned int *room)
{
    if (form.blocks.empty())
    {
        scriptura_character(line, '0');
        return;
    }
    for (size_t at = 0u; at < form.blocks.size(); at += 1u)
    {
        if (*room == 0u)
        {
            scriptura_text(line, " ...");
            return;
        }
        if (at != 0u)
        {
            scriptura_text(line, " + ");
        }
        const GoodsteinBlock &block = form.blocks[at];
        if (block.origin == 0ull)
        {
            goodstein_print_term(line, block.exponent, block.coefficient, room);
            continue;
        }
        scriptura_character(line, '[');
        goodstein_print_term(line, goodstein_of(block.high, block.origin), block.coefficient, room);
        if (block.high != block.low)
        {
            scriptura_text(line, " + ... + ");
            goodstein_print_term(line, goodstein_of(block.low, block.origin), block.coefficient, room);
        }
        scriptura_text(line, "; ");
        scriptura_decimal(line, block.high - block.low + 1ull, 1u);
        scriptura_text(line, " terms]");
    }
}

static void goodstein_print_term(ScripturaLine *line, const GoodsteinForm &exponent, unsigned long long coefficient,
                                 unsigned int *room)
{
    *room = (*room > 8u) ? (*room - 8u) : 0u;
    if (exponent.blocks.empty())
    {
        scriptura_decimal(line, coefficient, 1u);
        return;
    }
    const int power_one = (exponent.blocks.size() == 1u) && (exponent.blocks[0].origin == 0ull)
                       && exponent.blocks[0].exponent.blocks.empty() && (exponent.blocks[0].coefficient == 1ull);
    const int power_finite = (exponent.blocks.size() == 1u) && (exponent.blocks[0].origin == 0ull)
                          && exponent.blocks[0].exponent.blocks.empty();
    scriptura_character(line, 'w');
    if (power_finite != 0)
    {
        if (power_one == 0)
        {
            scriptura_character(line, '^');
            scriptura_decimal(line, exponent.blocks[0].coefficient, 1u);
        }
    }
    else
    {
        scriptura_text(line, "^(");
        goodstein_print(line, exponent, room);
        scriptura_character(line, ')');
    }
    if (coefficient != 1ull)
    {
        scriptura_character(line, '.');
        scriptura_decimal(line, coefficient, 1u);
    }
}

// 1. the bump keeps the tree
static void goodstein_lemma(SimTally *tally)
{
    unsigned long long tested = 0ull;
    unsigned long long held = 0ull;
    for (unsigned long long base = 2ull; base <= GOODSTEIN_LEMMA_BASE_MOST; base += 1ull)
    {
        for (unsigned long long value = 0ull; value < GOODSTEIN_LEMMA_BELOW; value += 1ull)
        {
            unsigned long long bumped = 0ull;
            if (goodstein_bump(value, base, &bumped) == 0)
            {
                continue;
            }
            GoodsteinBudget budget = {GOODSTEIN_COMPARE_TERMS, 0};
            const int order = goodstein_compare(goodstein_of(bumped, base + 1ull), goodstein_of(value, base), &budget);
            tested += 1ull;
            held += ((order == 0) && (budget.exhausted == 0)) ? 1ull : 0ull;
        }
    }
    scriptura_text(&tally->line, "  the bump keeps the tree: ");
    scriptura_decimal(&tally->line, held, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, tested, 1u);
    scriptura_text(&tally->line, " values below ");
    scriptura_decimal(&tally->line, GOODSTEIN_LEMMA_BELOW, 1u);
    scriptura_text(&tally->line, " at bases 2 to 6 whose bump fits 64 bits\n");
    sim_check(tally, (tested != 0ull) && (held == tested),
              "every n bumped to base b + 1 has the hereditary tree n had in base b");
}

// 2. 2^^k is omega^^k
static void goodstein_towers(SimTally *tally)
{
    unsigned long long value = 1ull;
    int same = 1;
    int climbs = 1;
    GoodsteinForm below;
    for (unsigned int height = 1u; height <= GOODSTEIN_TOWER; height += 1u)
    {
        // 2^^height from 2^^(height - 1): 1, 2, 4, 16, 65536
        unsigned long long next = 0ull;
        same = same && (goodstein_power(2ull, value, &next) != 0);
        value = next;
        const GoodsteinForm tower = goodstein_tower(height);
        GoodsteinBudget budget = {GOODSTEIN_COMPARE_TERMS, 0};
        same = same && (goodstein_compare(goodstein_of(value, 2ull), tower, &budget) == 0) && (budget.exhausted == 0);
        if (height > 1u)
        {
            GoodsteinBudget climb = {GOODSTEIN_COMPARE_TERMS, 0};
            climbs = climbs && (goodstein_compare(below, tower, &climb) < 0) && (climb.exhausted == 0);
        }
        below = tower;
        unsigned int room = GOODSTEIN_PRINT_ROOM;
        scriptura_text(&tally->line, "  2^^");
        scriptura_decimal(&tally->line, height, 1u);
        scriptura_text(&tally->line, " = ");
        scriptura_decimal(&tally->line, value, 1u);
        scriptura_text(&tally->line, " in hereditary base 2 is ");
        goodstein_print(&tally->line, goodstein_of(value, 2ull), &room);
        scriptura_character(&tally->line, '\n');
    }
    sim_check(tally, same, "2^^k in hereditary base 2 is omega^^k, for k = 1 to 4");
    sim_check(tally, climbs, "omega < omega^omega < omega^omega^omega < omega^omega^omega^omega");
}

// 3. the starts that finish
static void goodstein_small(SimTally *tally)
{
    const unsigned long long expected[3] = {1ull, 3ull, 5ull};
    int finish = 1;
    int values = 1;
    for (unsigned long long start = 1ull; start <= 3ull; start += 1ull)
    {
        GoodsteinForm form = goodstein_of(start, 2ull);
        unsigned long long numeric = start;
        unsigned long long base = 2ull;
        unsigned long long steps = 0ull;
        while (!form.blocks.empty() && (steps < GOODSTEIN_SMALL_STEPS_MOST))
        {
            unsigned long long bumped = 0ull;
            values = values && (goodstein_bump(numeric, base, &bumped) != 0);
            numeric = bumped - 1ull;
            base += 1ull;
            values = values && (goodstein_decrement(form, base) != 0);
            unsigned long long held = 0ull;
            values = values && (goodstein_value(form, base, &held) != 0) && (held == numeric);
            steps += 1ull;
        }
        finish = finish && form.blocks.empty() && (numeric == 0ull) && (steps == expected[start - 1ull]);
        scriptura_text(&tally->line, "  start ");
        scriptura_decimal(&tally->line, start, 1u);
        scriptura_text(&tally->line, ": 0 after ");
        scriptura_decimal(&tally->line, steps, 1u);
        scriptura_text(&tally->line, " steps\n");
    }
    sim_check(tally, finish, "the starts 1, 2 and 3 reach 0 in 1, 3 and 5 steps");
    sim_check(tally, values, "every step of the starts 1, 2 and 3 equals the numeric sequence");
}

// 4. a tower start, run for GOODSTEIN_STEPS steps
static void goodstein_run(SimTally *tally, unsigned long long start, int *falls, int *agrees,
                          unsigned long long *compared)
{
    GoodsteinForm form = goodstein_of(start, 2ull);
    unsigned int room = GOODSTEIN_PRINT_ROOM;
    scriptura_text(&tally->line, "  start ");
    scriptura_decimal(&tally->line, start, 1u);
    scriptura_text(&tally->line, ", the ordinal ");
    goodstein_print(&tally->line, form, &room);
    scriptura_character(&tally->line, '\n');
    unsigned long long numeric = start;
    int numeric_fits = 1;
    unsigned long long base = 2ull;
    unsigned long long steps = 0ull;
    unsigned long long fell = 0ull;
    unsigned long long matched = 0ull;
    int held = 1;
    while (!form.blocks.empty() && (steps < GOODSTEIN_STEPS) && (held != 0))
    {
        const GoodsteinForm before = form;
        if (numeric_fits != 0)
        {
            unsigned long long bumped = 0ull;
            numeric_fits = goodstein_bump(numeric, base, &bumped);
            numeric = bumped - 1ull;
        }
        base += 1ull;
        held = goodstein_decrement(form, base);
        GoodsteinBudget budget = {GOODSTEIN_COMPARE_TERMS, 0};
        fell += ((held != 0) && (goodstein_compare(form, before, &budget) < 0) && (budget.exhausted == 0)) ? 1ull : 0ull;
        unsigned long long value = 0ull;
        const int value_fits = goodstein_value(form, base, &value);
        if (numeric_fits != value_fits)
        {
            *agrees = 0;
        }
        else if (numeric_fits != 0)
        {
            matched += 1ull;
            *agrees = *agrees && (value == numeric);
        }
        steps += 1ull;
    }
    *falls = *falls && (held != 0) && (fell == steps) && (steps == GOODSTEIN_STEPS);
    *compared += matched;
    room = GOODSTEIN_PRINT_ROOM;
    scriptura_text(&tally->line, "    after ");
    scriptura_decimal(&tally->line, steps, 1u);
    scriptura_text(&tally->line, " steps, base ");
    scriptura_decimal(&tally->line, base, 1u);
    scriptura_text(&tally->line, ", ");
    scriptura_decimal(&tally->line, form.blocks.size(), 1u);
    scriptura_text(&tally->line, " blocks; the ordinal fell on ");
    scriptura_decimal(&tally->line, fell, 1u);
    scriptura_text(&tally->line, "; the value equals the numeric sequence's on ");
    scriptura_decimal(&tally->line, matched, 1u);
    scriptura_text(&tally->line, " steps, where it fits 64 bits\n    now ");
    goodstein_print(&tally->line, form, &room);
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    goodstein_lemma(&tally);
    goodstein_towers(&tally);
    goodstein_small(&tally);
    sim_flush(&tally);
    const unsigned long long starts[3] = {4ull, 16ull, 65536ull};
    int falls = 1;
    int agrees = 1;
    unsigned long long compared[3] = {0ull, 0ull, 0ull};
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        goodstein_run(&tally, starts[at], &falls, &agrees, &compared[at]);
    }
    sim_check(&tally, falls, "the starts 4, 16 and 65536 run every step, and each step's ordinal falls below the last");
    sim_check(&tally, agrees && (compared[0] != 0ull) && (compared[1] != 0ull),
              "every value equals the numeric sequence's wherever that fits 64 bits, and fits exactly then");
    return sim_close(&tally, "goodstein");
}
