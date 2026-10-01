// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the ka_psi_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef KA_PSI_INTERNAL_H
#define KA_PSI_INTERNAL_H

// Kolmogorov's inner function, exactly (Braun and Griebel, Constructive Approximation 30(3) (2009) 653-675, the
// preprint's section 2). Every value is exact: on the grids by exact integers over a common denominator, and at
// depth by a sparse sum of c . gamma^-e whose exponent e = beta(L) = (n^L - 1)/(n - 1) is carried as an integer and
// never expanded.
// 1. Sprecher's psi (2.4) reproduces the paper's counterexample exactly and its descents are counted.
// 2. Koppen's psi, in two readings the paper gives: (2.9)/(2.10), which its proofs use, where the carried midpoint
//    adds (gamma - 2)/2 units; and (2.7) as printed, which adds (gamma - 1)/2. On every point of D_1 to D_5 the
//    pair recursion (the scale step) equals the level-by-level recursion, psi is strictly increasing, its smallest
//    gap is exactly gamma^-beta(L), and its largest gap is what the gap recursion predicts.
// 3. Every scale, by the chained step: the smallest gap stays gamma^-beta(L) and the step stays monotone because
//    gamma^(n^(L-1)) > gamma + 1, checked symbolically to depth; the largest gap stays below 2^-(L-1)/gamma and below
//    the paper's Lemma 2.3 bound. Psi extends to a continuous strictly increasing function; a keyed point at
//    depth lands its gap between the two.

#include "sim_rational.h"

#define PSI_TERMS 64u

#define PSI_LEVELS_MAX 61u

#define PSI_EXHAUSTIVE 5u

// the widest relative exponent the sign test expands into an exact power
#define PSI_EXPAND_MAX 1024ull

#define PSI_KEY 0x505349ull

typedef struct
{
    unsigned int count;
    SimRational coefficient[PSI_TERMS];
    unsigned long long exponent[PSI_TERMS];
} PsiValue;

typedef struct
{
    unsigned long long dimension;
    unsigned long long base;
    unsigned int depth;
    unsigned long long weight[PSI_LEVELS_MAX + 1u];
} PsiCase;

typedef struct
{
    AnchorExactInteger lift[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger up[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger unit[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger half[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger denominator[PSI_EXHAUSTIVE + 1u];
} PsiScale;

int psi_case_open(PsiCase *psi_case, unsigned long long dimension, unsigned long long base, unsigned int depth);

void psi_times_integer(const AnchorExactInteger *value, unsigned long long factor, AnchorExactInteger *result);

void psi_add(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result);

void psi_multiply(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result);

SimRational psi_rational_exact(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator);

void psi_value_zero(PsiValue *value);

void psi_value_add_term(PsiValue *value, SimRational coefficient, unsigned long long exponent);

void psi_value_add(PsiValue *into, const PsiValue *from, SimRational scale);

void psi_value_scale(PsiValue *value, SimRational scale);

int psi_value_sign(const PsiValue *value, unsigned long long base);

int psi_value_compare(const PsiValue *left, const PsiValue *right, unsigned long long base);

SimRational psi_value_expand(const PsiValue *value, unsigned long long base);

void psi_value_print(ScripturaLine *line, const PsiValue *value);

void psi_sprecher_numerator(const PsiCase *psi_case, const unsigned char *digit, AnchorExactInteger *numerator);

void psi_digits(unsigned long long index, unsigned long long base, unsigned int levels, unsigned char *digit);

void psi_sprecher(SimResults *results, const PsiCase *psi_case);

void psi_scale_open(const PsiCase *psi_case, PsiScale *scale);

void psi_table_next(const PsiCase *psi_case, const PsiScale *scale, unsigned int level, unsigned long long tilt,
                    const AnchorExactInteger *below, unsigned long long below_count, AnchorExactInteger *table);

unsigned long long psi_wide_side(const PsiCase *psi_case, unsigned long long tilt);

void psi_exhaustive(SimResults *results, const PsiCase *psi_case, const PsiScale *scale, unsigned long long tilt,
                    AnchorExactInteger *measured_widest);

void psi_pair_symbolic(const PsiCase *psi_case, const unsigned char *digit, unsigned int levels,
                       unsigned long long tilt, PsiValue *value, PsiValue *plus);

void psi_all_scales(SimResults *results, const PsiCase *psi_case, const PsiScale *scale, unsigned long long tilt,
                    const AnchorExactInteger *measured_widest);

// a value below 2^128, as two words
typedef struct
{
    unsigned long long high;
    unsigned long long low;
} PsiWide;

typedef struct
{
    PsiWide value;
    unsigned int index;
} PsiImage;

void psi_separate(SimResults *results, const PsiCase *psi_case, const PsiScale *scale, unsigned int level);

#endif
