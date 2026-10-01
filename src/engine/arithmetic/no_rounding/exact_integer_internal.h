
// What the exact_integer_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef EXACT_INTEGER_INTERNAL_H
#define EXACT_INTEGER_INTERNAL_H

/* orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_integer_internal.h
 * @brief The portable C11 reference for the limb transform, which every other arm is checked on.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 *
 * @note Nothing here uses an intrinsic, a compiler extension or a 128 bit type. A target with a
 *       C11 compiler builds this and gets the right answer, and the vectorized arms exist only to
 *       get the same answer sooner.
 */
#include "exact_integer.h"

#include <stdlib.h>
#include <string.h>

/** @brief Bits per limb. */
#define LIMB_BITS 32u

/** @brief The base a limb counts in, held as 64 bit, wide enough that two limbs multiply cleanly. */
#define LIMB_BASE ((uint64_t)1u << LIMB_BITS)

/** @brief Everything below the limb boundary, for taking the low half of a 64 bit accumulator. */
#define LIMB_MASK ((uint64_t)0xFFFFFFFFu)

/** @brief Most decimal digits one limb takes in a single multiply, since 10^9 is below 2^32. */
#define LIMB_DECIMAL_DIGITS 9u

#define EXACT_LIMBS ((size_t)ANCHOR_EXACT_LIMBS)

// A call's width-sized working copies are one block, placed at compile time: on the stack while the width is at most
// ANCHOR_EXACT_STACK_LIMBS, from the heap beyond it. No width is bounded by a stack. A block from the heap that
// cannot be held errors as ANCHOR_EXACT_WILL_NOT_FIT.
#if (ANCHOR_EXACT_LIMBS) <= (ANCHOR_EXACT_STACK_LIMBS)
#define EXACT_SCRATCH(name_, count_)                                                                                   \
    uint32_t name_##_on_stack[count_];                                                                                 \
    uint32_t *const name_ = name_##_on_stack
#define EXACT_SCRATCH_VALID(name_) (1)
#define EXACT_SCRATCH_RELEASE(name_) ((void)(name_))
#define EXACT_VALUE(name_)                                                                                             \
    AnchorExactInteger name_##_on_stack;                                                                               \
    AnchorExactInteger *const name_ = &name_##_on_stack
#define EXACT_VALUE_RELEASE(name_) ((void)(name_))
#else
#define EXACT_SCRATCH(name_, count_) uint32_t *const name_ = (uint32_t *)malloc((size_t)(count_) * sizeof(uint32_t))
#define EXACT_SCRATCH_VALID(name_) ((name_) != NULL)
#define EXACT_SCRATCH_RELEASE(name_) free(name_)
#define EXACT_VALUE(name_) AnchorExactInteger *const name_ = (AnchorExactInteger *)malloc(sizeof(AnchorExactInteger))
#define EXACT_VALUE_RELEASE(name_) free(name_)
#endif

void anchor_exact_zero(AnchorExactInteger *value);

int magnitude_compare(const uint32_t *left, const uint32_t *right);

int magnitude_is_zero(const uint32_t *value);

size_t magnitude_used(const uint32_t *value);

int anchor_exact_equal(const AnchorExactInteger *left, const AnchorExactInteger *right);

void settle_sign(AnchorExactInteger *result, int32_t sign);

AnchorExactStatus anchor_exact_add(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                   AnchorExactInteger *result);

uint32_t limbs_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count);

uint32_t limbs_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count);

uint32_t limbs_accumulate(uint32_t *value, size_t count, const uint32_t *added, size_t added_count);

uint32_t limbs_deduct(uint32_t *value, size_t count, const uint32_t *taken, size_t taken_count);

void limbs_long_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                        size_t right_count);

int limbs_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right, size_t right_count);

// A ring element modulo 2^n + 1, n = 32 limbs, is limbs + 1 words holding a value from 0 to 2^n. In this ring 2 is a
// root of unity (2^(2n) = 1). Every twiddle of the transform is a shift, and nothing is rounded.
#define TRANSFORM_BASE_LIMBS 64u

unsigned int bits_ceiling_log(size_t value);

void fermat_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs);

void fermat_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs);

void fermat_negate(uint32_t *value, size_t limbs);

void fermat_shift(uint32_t *result, const uint32_t *value, size_t shift, size_t limbs, uint32_t *scratch);

int transform_product(uint32_t *wide, const uint32_t *left, size_t left_used, const uint32_t *right, size_t right_used);

unsigned int limb_leading_zeros(uint32_t word);

size_t limbs_used(const uint32_t *value, size_t count);

void magnitude_divide(const uint32_t *top, const uint32_t *bottom, uint32_t *quotient, uint32_t *rest, uint32_t *work);

void limbs_ladder_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                          size_t right_count);

/**
 * @brief Where each part of a decimal text sits, found before any arithmetic is done.
 *
 * @note Every range is a pair of byte offsets into the text, the second one past the last byte. An
 *       empty range has both offsets equal.
 */
typedef struct
{
    int32_t sign;            /**< -1 where the text opened with '-', 1 otherwise. */
    size_t integer_from;     /**< First digit before the point. */
    size_t integer_to;       /**< One past the last digit before the point. */
    size_t fraction_from;    /**< First digit after the point. */
    size_t fraction_to;      /**< One past the last digit after the point. */
    size_t uncertainty_from; /**< First digit inside the brackets. */
    size_t uncertainty_to;   /**< One past the last digit inside the brackets. */
    int carried;             /**< 1 where the text carried a bracketed uncertainty, else 0. */
} DecimalLayout;

#endif
