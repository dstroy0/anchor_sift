// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// goodstein_terms.cu: terms, towers, cursors and values
#include "goodstein_internal.h"

static GoodsteinBlock goodstein_term(const GoodsteinNotation &exponent, unsigned long long coefficient)
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
GoodsteinNotation goodstein_of(unsigned long long value, unsigned long long base)
{
    GoodsteinNotation form;
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
GoodsteinNotation goodstein_tower(unsigned int height)
{
    GoodsteinNotation form;
    form.blocks.push_back(goodstein_term(GoodsteinNotation(), 1ull));
    for (unsigned int level = 0u; level < height; level += 1u)
    {
        GoodsteinNotation next;
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
int goodstein_compare(const GoodsteinNotation &left, const GoodsteinNotation &right, GoodsteinBudget *budget)
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
        if ((one_block.origin != 0ull) && (one_block.origin == other_block.origin) && (one.high == other.high) &&
            (one_block.coefficient == other_block.coefficient))
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
        GoodsteinNotation one_tree;
        GoodsteinNotation other_tree;
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
int goodstein_power(unsigned long long base, unsigned long long exponent, unsigned long long *out)
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
int goodstein_add_term(unsigned long long *total, unsigned long long coefficient, unsigned long long base,
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
// origin. A run reaching 64 overflows on its first term.
int goodstein_value(const GoodsteinNotation &form, unsigned long long base, unsigned long long *out)
{
    unsigned long long total = 0ull;
    for (const GoodsteinBlock &block : form.blocks)
    {
        if (block.origin == 0ull)
        {
            unsigned long long exponent = 0ull;
            if ((goodstein_value(block.exponent, base, &exponent) == 0) ||
                (goodstein_add_term(&total, block.coefficient, base, exponent) == 0))
            {
                return 0;
            }
            continue;
        }
        for (unsigned long long k = block.high;; k -= 1ull)
        {
            unsigned long long exponent = 0ull;
            if ((goodstein_value(goodstein_of(k, block.origin), base, &exponent) == 0) ||
                (goodstein_add_term(&total, block.coefficient, base, exponent) == 0))
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
// exponents 0 .. L - 1 of this base. 0 where L's value at base leaves 64 bits. The run's range cannot be held.
int goodstein_decrement(GoodsteinNotation &form, unsigned long long base)
{
    const GoodsteinBlock lowest = form.blocks.back();
    GoodsteinNotation exponent;
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
        unsigned long long range = 0ull;
        if (goodstein_value(exponent, base, &range) == 0)
        {
            return 0;
        }
        GoodsteinBlock run;
        run.coefficient = base - 1ull;
        run.origin = base;
        run.low = 0ull;
        run.high = range - 1ull;
        form.blocks.push_back(run);
    }
    return 1;
}
