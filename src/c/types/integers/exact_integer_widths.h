
// exact_integer_widths.h: the width, limbs and the thresholds that choose each arm (exact_integer.h includes the parts
// in order)
#ifndef EXACT_INTEGER_WIDTHS_H
#define EXACT_INTEGER_WIDTHS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
/* The GPU arm is compiled as C++ by nvcc and calls straight into these, which are compiled as C.
 * Without this the C++ side would look for mangled names that no C translation unit ever emits. */
extern "C"
{
#endif

/**
 * @brief Limbs per exact integer, at 32 bits each, a power of two for a power-of-two width.
 *
 * @note Given as limbs here or as bits in ANCHOR_EXACT_BITS. The one not given follows from the
 *       other, and both given must agree. The widths are written without casts so #if can weigh
 *       them.
 * @note 128 limbs is 4096 bits, which holds 1024 decimal digits with room over. That is the scale
 *       representation/exact.py ingests at, and the two forms have to agree on the same values or
 *       a cross check between them means nothing.
 * @note The value a limb array carries is the expansion sum(limb[i] * (2^32)^i), whose top
 *       coefficient is the width 2^ANCHOR_EXACT_BITS. A power of two limb count makes that width a
 *       power of two. The top magnitude bit then lands at a fixed position, and the width scales by
 *       doubling, 4096 to 8192 to 16384 bits, with the position fixed at each. The guard below
 *       errors on a width that is not a power of two.
 * @note A build selects any power of two from 1 limb up, 32 bits up, with no ceiling. Every arm is
 *       graded from 1 limb to 32768 by utils/maint/engine/check_exact_widths.sh, and the portable
 *       reference to 4194304 bits by utils/test/src/cu/types/integers/exact_transform_test.sh.
 * @note A width below 4096 bits cannot hold the 1024 digit floor. A build selecting one declares
 *       its own ANCHOR_EXACT_DIGITS, and the floor assert below errors on it by name where it does not.
 * @note Defined on both arms so #if always has a value and an unset build is never a silent false.
 */
#if defined(ANCHOR_EXACT_BITS) && !defined(ANCHOR_EXACT_LIMBS)
#define ANCHOR_EXACT_LIMBS ((ANCHOR_EXACT_BITS) / 32ull)
#endif

#ifndef ANCHOR_EXACT_LIMBS
#define ANCHOR_EXACT_LIMBS 128u
#endif

/**
 * @brief Bits the fixed width actually carries. Every size is taken from this or from the limbs.
 */
#ifndef ANCHOR_EXACT_BITS
#define ANCHOR_EXACT_BITS ((ANCHOR_EXACT_LIMBS) * 32ull)
#endif

/**
 * @brief Decimal digits the fixed width is guaranteed to hold, matching representation.exact.
 *
 * @note A declared floor and never the capacity. 128 limbs is 4096 bits, which actually holds 1232
 *       decimal digits. 208 of them are headroom this constant does not promise.
 * @note The floor counts every digit of the stored integer, the integer part of the value included.
 *       A value carried at d decimal places is stored as value times 10^d. At d = 1024 the width
 *       holds a magnitude below 2^4096 / 10^1024, about 1e209, and errors on anything larger. The
 *       CODATA 2022 kilogram-hertz relationship, 1.35639248965e50, needs 3569 bits at 1024 places,
 *       which this width holds and the earlier 3456-bit width errored.
 * @warning Never size a buffer from this. A width computed from digits is short the moment anybody
 *          raises the floor toward the real capacity, and a device allocation sized that way would
 *          be short by exactly the amount nobody was watching. Size from ANCHOR_EXACT_LIMBS or from
 *          sizeof(AnchorExactInteger), which cannot drift apart from the array they describe.
 * @note Defined on both arms, like the limb count. A build can then raise the floor and the assert
 *       below decides whether the width holds it. A knob the build cannot set is a knob whose guard
 *       has never been exercised.
 */
#ifndef ANCHOR_EXACT_DIGITS
#define ANCHOR_EXACT_DIGITS 1024u
#endif

/* The width is a power of two of at least one limb. The expansion's top coefficient
 * 2^ANCHOR_EXACT_BITS is then a power of two and the top magnitude bit sits at a fixed position at
 * every size the build selects. Scaling is by doubling the limb count, 128 to 256 to 512, holding
 * 4096, 8192, 16384 bits. A width that is not a power of two, an override such as the earlier 108
 * limbs, fails compilation here. The power of two test alone passes a width of zero, because
 * 0 & (0 - 1) is 0. The bottom of the range is tested with it. */
/* The declared floor has to fit the width, and the build can decide that. A decimal digit needs
 * log2(10) bits, which is 3.3219, carried here as 3322 parts in a thousand and rounded up so the
 * test is never optimistic. A floor raised past the width fails compilation with this line. */
/* Three arms and every one defined, keyed on what the LANGUAGE offers and not on which
 * compiler is driving. C++ spells it static_assert, C11 spells it _Static_assert, and a C compiler
 * older than C11 has neither, where a negative array width fails at compile time on any of them.
 * Naming a vendor here would only move the hole to the next toolchain that is not that vendor.
 * Unguarded, this header once failed to compile under nvcc, the GPU arm was never built, and a stale
 * bench binary carrying no CUDA symbols went on reporting a "cuda" arm that agreed with the portable
 * one. It agreed because it WAS the portable one. */
#if defined(__cplusplus)
    static_assert(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull) &&
                      (((unsigned long long)(ANCHOR_EXACT_BITS) & ((unsigned long long)(ANCHOR_EXACT_BITS)-1ull)) ==
                       0ull),
                  "ANCHOR_EXACT_BITS must be a power of two of at least 32, so the width scales by doubling");
    static_assert((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull),
                  "ANCHOR_EXACT_BITS and ANCHOR_EXACT_LIMBS must name the same width");
    static_assert(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) + 1ull) <=
                      (unsigned long long)(ANCHOR_EXACT_BITS),
                  "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull) &&
                   (((unsigned long long)(ANCHOR_EXACT_BITS) & ((unsigned long long)(ANCHOR_EXACT_BITS)-1ull)) == 0ull),
               "ANCHOR_EXACT_BITS must be a power of two of at least 32, so the width scales by doubling");
_Static_assert((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull),
               "ANCHOR_EXACT_BITS and ANCHOR_EXACT_LIMBS must name the same width");
_Static_assert(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) + 1ull) <=
                   (unsigned long long)(ANCHOR_EXACT_BITS),
               "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#else
typedef char anchor_exact_bits_are_a_power_of_two[(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull) &&
                                                   (((unsigned long long)(ANCHOR_EXACT_BITS) &
                                                     ((unsigned long long)(ANCHOR_EXACT_BITS)-1ull)) == 0ull))
                                                      ? 1
                                                      : -1];
typedef char anchor_exact_bits_and_limbs_agree
    [((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull)) ? 1 : -1];
typedef char anchor_exact_digits_fit_the_width[(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) +
                                                 1ull) <= (unsigned long long)(ANCHOR_EXACT_BITS))
                                                   ? 1
                                                   : -1];
#endif

/**
 * @brief The widest width whose working copies are held on the stack, in limbs.
 *
 * @note Past it every width-sized working copy is allocated from the heap. 4096 limbs is 16 KiB a copy,
 *       and the widest call, the gcd, holds nine of them.
 */
#ifndef ANCHOR_EXACT_STACK_LIMBS
#define ANCHOR_EXACT_STACK_LIMBS 4096u
#endif

/**
 * @brief The shorter factor's limbs from which a product is taken by Karatsuba instead of long
 *        multiplication.
 *
 * @note Karatsuba splits each factor in halves and recurses into three half products. Its cost
 *       grows as n^1.585 against the long multiplication's n^2.
 */
#ifndef ANCHOR_EXACT_KARATSUBA_LIMBS
#define ANCHOR_EXACT_KARATSUBA_LIMBS 32u
#endif

/**
 * @brief The shorter factor's limbs from which a product is taken by the Schonhage-Strassen
 *        transform.
 *
 * @note The transform works in the ring of integers modulo 2^n + 1, where a power of two is a root
 *       of unity and every twiddle is a shift, and weights by the square root of that root for a
 *       negacyclic product. Its depth is chosen by an integer cost model.
 * @note Measured on an RTX 3070 host (x86-64, MSVC -O2): Karatsuba and the transform meet near 8192
 *       limbs, and the transform is 1.44x ahead at 16384, 1.55x at 32768 and 1.85x at 65536.
 * @note Those ratios are one reading. Repeated readings of the same code on the same host differ by up
 *       to about 1.3x, and 16384 has read 1.02x and 1.32x. The crossover at 8192 held on every run.
 */
#ifndef ANCHOR_EXACT_TRANSFORM_LIMBS
#define ANCHOR_EXACT_TRANSFORM_LIMBS 8192u
#endif

/**
 * @brief The limbs the divisor and the quotient must both reach before a division is taken by
 *        Newton's reciprocal instead of long division.
 *
 * @note Newton's reciprocal is grown at half precision recursively, taken one Newton step, and
 *       corrected exactly. The quotient is then one product on the ladder.
 * @note Measured on the same host, a 2n-limb numerator by an n-limb divisor on the Karatsuba ladder
 *       alone: long division leads to 4096 limbs, and Newton is 1.21x ahead at 8192, 1.06x at 16384,
 *       1.81x at 32768 and 2.44x at 65536.
 * @note One reading as well. Another run read 1.09x at 8192 and 1.45x at 16384. Ratios within about
 *       1.3x are not settled by one reading, and the crossover at 8192 held on every run.
 */
#ifndef ANCHOR_EXACT_NEWTON_LIMBS
#define ANCHOR_EXACT_NEWTON_LIMBS 8192u
#endif

#if defined(__cplusplus)
    static_assert((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u, "Newton's division needs a divisor of at least one limb");
    static_assert((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u, "Karatsuba splits in halves of at least two limbs");
    static_assert((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS),
                  "the transform's rung sits at or above Karatsuba's");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u, "Newton's division needs a divisor of at least one limb");
_Static_assert((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u, "Karatsuba splits in halves of at least two limbs");
_Static_assert((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS),
               "the transform's rung sits at or above Karatsuba's");
#else
typedef char anchor_exact_newton_has_a_divisor[((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u) ? 1 : -1];
typedef char anchor_exact_karatsuba_splits[((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u) ? 1 : -1];
typedef char anchor_exact_rungs_in_order[((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS)) ? 1 : -1];
#endif

#ifdef __cplusplus
}
#endif

#endif
