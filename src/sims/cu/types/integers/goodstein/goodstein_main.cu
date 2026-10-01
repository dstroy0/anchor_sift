// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// goodstein_main.cu: bumps, printing, the lemma and main
#include "goodstein_internal.h"

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
            if ((goodstein_bump(position, base, &exponent) == 0) ||
                (goodstein_add_term(&total, digit, base + 1ull, exponent) == 0))
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

static void goodstein_print_term(ScripturaLine *line, const GoodsteinNotation &exponent, unsigned long long coefficient,
                                 unsigned int *capacity);

// the form as an ordinal in Cantor normal form, w for omega, cut at the capacity left
static void goodstein_print(ScripturaLine *line, const GoodsteinNotation &form, unsigned int *capacity)
{
    if (form.blocks.empty())
    {
        scriptura_character(line, '0');
        return;
    }
    for (size_t at = 0u; at < form.blocks.size(); at += 1u)
    {
        if (*capacity == 0u)
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
            goodstein_print_term(line, block.exponent, block.coefficient, capacity);
            continue;
        }
        scriptura_character(line, '[');
        goodstein_print_term(line, goodstein_of(block.high, block.origin), block.coefficient, capacity);
        if (block.high != block.low)
        {
            scriptura_text(line, " + ... + ");
            goodstein_print_term(line, goodstein_of(block.low, block.origin), block.coefficient, capacity);
        }
        scriptura_text(line, "; ");
        scriptura_decimal(line, block.high - block.low + 1ull, 1u);
        scriptura_text(line, " terms]");
    }
}

static void goodstein_print_term(ScripturaLine *line, const GoodsteinNotation &exponent, unsigned long long coefficient,
                                 unsigned int *capacity)
{
    *capacity = (*capacity > 8u) ? (*capacity - 8u) : 0u;
    if (exponent.blocks.empty())
    {
        scriptura_decimal(line, coefficient, 1u);
        return;
    }
    const int power_one = (exponent.blocks.size() == 1u) && (exponent.blocks[0].origin == 0ull) &&
                          exponent.blocks[0].exponent.blocks.empty() && (exponent.blocks[0].coefficient == 1ull);
    const int power_finite = (exponent.blocks.size() == 1u) && (exponent.blocks[0].origin == 0ull) &&
                             exponent.blocks[0].exponent.blocks.empty();
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
        goodstein_print(line, exponent, capacity);
        scriptura_character(line, ')');
    }
    if (coefficient != 1ull)
    {
        scriptura_character(line, '.');
        scriptura_decimal(line, coefficient, 1u);
    }
}

// 1. the bump keeps the tree
static void goodstein_lemma(SimResults *results)
{
    unsigned long long tested = 0ull;
    unsigned long long terminated = 0ull;
    for (unsigned long long base = 2ull; base <= GOODSTEIN_LEMMA_BASE_MAX; base += 1ull)
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
            terminated += ((order == 0) && (budget.exhausted == 0)) ? 1ull : 0ull;
        }
    }
    scriptura_text(&results->line, "  the bump keeps the tree: ");
    scriptura_decimal(&results->line, terminated, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, tested, 1u);
    scriptura_text(&results->line, " values below ");
    scriptura_decimal(&results->line, GOODSTEIN_LEMMA_BELOW, 1u);
    scriptura_text(&results->line, " at bases 2 to 6 whose bump fits 64 bits\n");
    sim_check(results, (tested != 0ull) && (terminated == tested),
              "every n bumped to base b + 1 has the hereditary tree n had in base b");
}

// 2. 2^^k is omega^^k
static void goodstein_towers(SimResults *results)
{
    unsigned long long value = 1ull;
    int same = 1;
    int climbs = 1;
    GoodsteinNotation below;
    for (unsigned int height = 1u; height <= GOODSTEIN_TOWER; height += 1u)
    {
        // 2^^height from 2^^(height - 1): 1, 2, 4, 16, 65536
        unsigned long long next = 0ull;
        same = same && (goodstein_power(2ull, value, &next) != 0);
        value = next;
        const GoodsteinNotation tower = goodstein_tower(height);
        GoodsteinBudget budget = {GOODSTEIN_COMPARE_TERMS, 0};
        same = same && (goodstein_compare(goodstein_of(value, 2ull), tower, &budget) == 0) && (budget.exhausted == 0);
        if (height > 1u)
        {
            GoodsteinBudget climb = {GOODSTEIN_COMPARE_TERMS, 0};
            climbs = climbs && (goodstein_compare(below, tower, &climb) < 0) && (climb.exhausted == 0);
        }
        below = tower;
        unsigned int capacity = GOODSTEIN_PRINT_CAPACITY;
        scriptura_text(&results->line, "  2^^");
        scriptura_decimal(&results->line, height, 1u);
        scriptura_text(&results->line, " = ");
        scriptura_decimal(&results->line, value, 1u);
        scriptura_text(&results->line, " in hereditary base 2 is ");
        goodstein_print(&results->line, goodstein_of(value, 2ull), &capacity);
        scriptura_character(&results->line, '\n');
    }
    sim_check(results, same, "2^^k in hereditary base 2 is omega^^k, for k = 1 to 4");
    sim_check(results, climbs, "omega < omega^omega < omega^omega^omega < omega^omega^omega^omega");
}

// 3. the starts that finish
static void goodstein_small(SimResults *results)
{
    const unsigned long long expected[3] = {1ull, 3ull, 5ull};
    int finish = 1;
    int values = 1;
    for (unsigned long long start = 1ull; start <= 3ull; start += 1ull)
    {
        GoodsteinNotation form = goodstein_of(start, 2ull);
        unsigned long long numeric = start;
        unsigned long long base = 2ull;
        unsigned long long steps = 0ull;
        while (!form.blocks.empty() && (steps < GOODSTEIN_SMALL_STEPS_MAX))
        {
            unsigned long long bumped = 0ull;
            values = values && (goodstein_bump(numeric, base, &bumped) != 0);
            numeric = bumped - 1ull;
            base += 1ull;
            values = values && (goodstein_decrement(form, base) != 0);
            unsigned long long value = 0ull;
            values = values && (goodstein_value(form, base, &value) != 0) && (value == numeric);
            steps += 1ull;
        }
        finish = finish && form.blocks.empty() && (numeric == 0ull) && (steps == expected[start - 1ull]);
        scriptura_text(&results->line, "  start ");
        scriptura_decimal(&results->line, start, 1u);
        scriptura_text(&results->line, ": 0 after ");
        scriptura_decimal(&results->line, steps, 1u);
        scriptura_text(&results->line, " steps\n");
    }
    sim_check(results, finish, "the starts 1, 2 and 3 reach 0 in 1, 3 and 5 steps");
    sim_check(results, values, "every step of the starts 1, 2 and 3 equals the numeric sequence");
}

// 4. a tower start, run for GOODSTEIN_STEPS steps
static void goodstein_run(SimResults *results, unsigned long long start, int *falls, int *agrees,
                          unsigned long long *compared)
{
    GoodsteinNotation form = goodstein_of(start, 2ull);
    unsigned int capacity = GOODSTEIN_PRINT_CAPACITY;
    scriptura_text(&results->line, "  start ");
    scriptura_decimal(&results->line, start, 1u);
    scriptura_text(&results->line, ", the ordinal ");
    goodstein_print(&results->line, form, &capacity);
    scriptura_character(&results->line, '\n');
    unsigned long long numeric = start;
    int numeric_fits = 1;
    unsigned long long base = 2ull;
    unsigned long long steps = 0ull;
    unsigned long long fell = 0ull;
    unsigned long long matched = 0ull;
    int ok = 1;
    while (!form.blocks.empty() && (steps < GOODSTEIN_STEPS) && (ok != 0))
    {
        const GoodsteinNotation before = form;
        if (numeric_fits != 0)
        {
            unsigned long long bumped = 0ull;
            numeric_fits = goodstein_bump(numeric, base, &bumped);
            numeric = bumped - 1ull;
        }
        base += 1ull;
        ok = goodstein_decrement(form, base);
        GoodsteinBudget budget = {GOODSTEIN_COMPARE_TERMS, 0};
        fell += ((ok != 0) && (goodstein_compare(form, before, &budget) < 0) && (budget.exhausted == 0)) ? 1ull : 0ull;
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
    *falls = *falls && (ok != 0) && (fell == steps) && (steps == GOODSTEIN_STEPS);
    *compared += matched;
    capacity = GOODSTEIN_PRINT_CAPACITY;
    scriptura_text(&results->line, "    after ");
    scriptura_decimal(&results->line, steps, 1u);
    scriptura_text(&results->line, " steps, base ");
    scriptura_decimal(&results->line, base, 1u);
    scriptura_text(&results->line, ", ");
    scriptura_decimal(&results->line, form.blocks.size(), 1u);
    scriptura_text(&results->line, " blocks; the ordinal fell on ");
    scriptura_decimal(&results->line, fell, 1u);
    scriptura_text(&results->line, "; the value equals the numeric sequence's on ");
    scriptura_decimal(&results->line, matched, 1u);
    scriptura_text(&results->line, " steps, where it fits 64 bits\n    now ");
    goodstein_print(&results->line, form, &capacity);
    scriptura_character(&results->line, '\n');
    sim_flush(results);
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    goodstein_lemma(&results);
    goodstein_towers(&results);
    goodstein_small(&results);
    sim_flush(&results);
    const unsigned long long starts[3] = {4ull, 16ull, 65536ull};
    int falls = 1;
    int agrees = 1;
    unsigned long long compared[3] = {0ull, 0ull, 0ull};
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        goodstein_run(&results, starts[at], &falls, &agrees, &compared[at]);
    }
    sim_check(&results, falls,
              "the starts 4, 16 and 65536 run every step, and each step's ordinal falls below the last");
    sim_check(&results, agrees && (compared[0] != 0ull) && (compared[1] != 0ull),
              "every value equals the numeric sequence's wherever that fits 64 bits, and fits exactly then");
    return sim_close(&results, "goodstein");
}
