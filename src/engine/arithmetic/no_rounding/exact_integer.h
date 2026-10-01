
/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_integer.h
 * @brief An exact integer held as a fixed width array of limbs, and the operations a measure needs.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 *
 * @note A limb array is a transform of an integer, the same way decimal text is one. The value is
 *       identical in every form. What changes is which machine can work on it.
 *       Python carries the arbitrary precision form, this carries the fixed width form, and a GPU
 *       carries the same fixed width form one warp to a number. No arm is allowed its own
 *       arithmetic doctrine.
 * @note The width is fixed at compile time because a GPU register file cannot grow at run time.
 *       That is the only bound this representation has, and it is declared instead of discovered.
 *       Every entry point errors on a value that will not fit instead of truncating it.
 * @note Base 2^32 with a 64 bit accumulator. Wider limbs would need 128 bit products, which are a
 *       compiler extension on some targets and absent on others. 32 bit limbs also map onto both
 *       SIMD widths this tree builds for and onto a CUDA lane. One representation serves every
 *       arm.
 * @note The reference implementation is portable C11. Every vectorized arm is checked against it
 *       and is wrong where it disagrees, whatever it measures.
 * @note Division is integer division: a quotient and a remainder, an exact quotient that errors on a
 *       remainder, and a greatest common divisor. A constant that is no integer quotient, such as h
 *       over 2 pi, is still computed in arbitrary precision outside this type and read in as finished
 *       decimal text.
 * @note Multiplication climbs a ladder: long multiplication, then Karatsuba from
 *       ANCHOR_EXACT_KARATSUBA_LIMBS, then the Schonhage-Strassen transform from
 *       ANCHOR_EXACT_TRANSFORM_LIMBS. Division is Knuth's long division, then Newton's reciprocal on
 *       that ladder from ANCHOR_EXACT_NEWTON_LIMBS. Every rung is measured by
 *       utils/test/src/cu/types/integers/exact_transform_test.sh and gives the product or
 *       quotient the rung below it gives.
 * @note A width-sized working copy sits on the stack up to ANCHOR_EXACT_STACK_LIMBS and is held
 *       from the heap past it. No width is bounded by a stack. Where the heap cannot hold a
 *       copy, the call errors with ANCHOR_EXACT_WILL_NOT_FIT. A caller holding many integers at a
 *       wide width keeps them in static or allocated storage. A main thread stack defaults to 1 MiB
 *       under the MSVC linker and 8 MiB under a stock Linux.
 */
#ifndef ANCHOR_EXACT_LIMBS_H
#define ANCHOR_EXACT_LIMBS_H

#include "exact_integer_api.h"

#endif
