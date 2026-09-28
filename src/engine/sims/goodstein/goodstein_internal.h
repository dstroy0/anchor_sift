// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the goodstein_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef GOODSTEIN_INTERNAL_H
#define GOODSTEIN_INTERNAL_H

// Goodstein's sequences, held exactly and never expanded (R. L. Goodstein, "On the restricted ordinal theorem",
// J. Symbolic Logic 9, 1944; L. Kirby and J. Paris, "Accessible independence results for Peano arithmetic", Bull.
// London Math. Soc. 14, 1982). n is written in hereditary base b, every exponent written in base b again; a step writes
// every b as b + 1 and subtracts one. With b read as omega the same tree is an ordinal below epsilon_0 in Cantor normal
// form: the bump leaves the tree as it is, and the subtraction lowers it. Every sequence reaches 0. The start 2^^k
// is omega^^k. 16 is omega^omega^omega. The values grow as towers and are never formed: a form is the tree itself,
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

#define GOODSTEIN_LEMMA_BASE_MAX 6ull

#define GOODSTEIN_TOWER 4u

#define GOODSTEIN_SMALL_STEPS_MAX 64ull

// the most term comparisons one ordinal comparison may make before it is reported unfinished
#define GOODSTEIN_COMPARE_TERMS 1000000ull

// the most characters an ordinal is printed with
#define GOODSTEIN_PRINT_CAPACITY 360u

struct GoodsteinBlock;

// a hereditary form, its terms highest first; the empty form is 0
struct GoodsteinNotation
{
    std::vector<GoodsteinBlock> blocks;
};

// one term c . b^E (origin 0), or a run: c . b^tree(k) for every integer k from high down to low, tree(k) being k
// written hereditarily in the base the run was made at (origin)
struct GoodsteinBlock
{
    GoodsteinNotation exponent;
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
    const GoodsteinNotation *form;
    size_t block;
    unsigned long long high;
} GoodsteinCursor;

GoodsteinNotation goodstein_of(unsigned long long value, unsigned long long base);

GoodsteinNotation goodstein_tower(unsigned int height);

int goodstein_compare(const GoodsteinNotation &left, const GoodsteinNotation &right, GoodsteinBudget *budget);

int goodstein_power(unsigned long long base, unsigned long long exponent, unsigned long long *out);

int goodstein_add_term(unsigned long long *total, unsigned long long coefficient, unsigned long long base,
                       unsigned long long exponent);

int goodstein_value(const GoodsteinNotation &form, unsigned long long base, unsigned long long *out);

int goodstein_decrement(GoodsteinNotation &form, unsigned long long base);

#endif
