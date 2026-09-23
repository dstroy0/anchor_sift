/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_space.cpp
 * @brief How much space each of SHA-256's four mixing functions throws away, exactly.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The state functions are built from rotations alone - Sigma0 is ROTR2 ^ ROTR13 ^ ROTR22 and
 *       Sigma1 is ROTR6 ^ ROTR11 ^ ROTR25 - while the schedule functions each carry a shift:
 *       sigma0 is ROTR7 ^ ROTR18 ^ SHR3 and sigma1 is ROTR17 ^ ROTR19 ^ SHR10. A rotation is a
 *       permutation of bit positions and loses nothing. A shift is not, and can.
 * @note All four are GF(2)-linear, so this is not a question that wants sampling. Each is a 32 by 32
 *       matrix over GF(2), its rank is an elimination away, and the size of its image is two to that
 *       rank exactly. Where the rank falls short of 32 the function is not a bijection and distinct
 *       inputs are already colliding before anything else in the round has run.
 * @note The narrowed forms are included because bench_narrow sweeps the state functions across
 *       widths and has never touched these, and because a nonce travels through sigma0 and sigma1
 *       instead of through Sigma0 and Sigma1.
 */

#include <cstdint>
#include <cstdio>

namespace
{

/** @brief Bits in a word of the standard. */
const unsigned WORD_BITS = 32u;

/** @brief Rotates right within a stated width. */
uint32_t turn_right(uint32_t value, unsigned by, unsigned width)
{
    const uint32_t mask = (width >= 32u) ? 0xffffffffu : ((1u << width) - 1u);
    const unsigned amount = by % width;
    if (amount == 0u)
    {
        return value & mask;
    }
    return ((value >> amount) | (value << (width - amount))) & mask;
}

/** @brief Shifts right within a stated width. */
uint32_t shift_right(uint32_t value, unsigned by, unsigned width)
{
    const uint32_t mask = (width >= 32u) ? 0xffffffffu : ((1u << width) - 1u);
    if (by >= width)
    {
        return 0u;
    }
    return (value >> by) & mask;
}

/** @brief One of SHA-256's four mixing functions, named by which it is. */
struct Mixer
{
    const char *name;       ///< How the standard spells it.
    unsigned first;         ///< First rotation amount.
    unsigned second;        ///< Second rotation amount.
    unsigned third;         ///< Third amount, a rotation or a shift.
    int third_is_shift;     ///< Nonzero where the third term is a shift instead of a rotation.
    const char *belongs_to; ///< Which half of the function it serves.
};

/**
 * @brief Applies one mixing function at a stated width.
 *
 * @param[in] mixer Which function.
 * @param[in] value Input word.
 * @param[in] width Bits per word.
 * @return          The mixed word.
 * @note The amounts are scaled the way bench_narrow scales the state functions, so a narrowed
 *       sigma is the same kind of object as a narrowed Sigma and the two sweeps are comparable.
 */
uint32_t apply(const Mixer &mixer, uint32_t value, unsigned width)
{
    const uint32_t first = turn_right(value, ((mixer.first * width) + 16u) / 32u, width);
    const uint32_t second = turn_right(value, ((mixer.second * width) + 16u) / 32u, width);
    const unsigned third_amount = ((mixer.third * width) + 16u) / 32u;
    const uint32_t third = (mixer.third_is_shift != 0) ? shift_right(value, third_amount, width)
                                                       : turn_right(value, third_amount, width);
    return first ^ second ^ third;
}

/**
 * @brief The amounts bench_narrow actually uses, which are clamped instead of raw.
 *
 * @param[in]  mixer   Which function.
 * @param[in]  width   Bits per word.
 * @param[out] amounts Three amounts [BORROWS].
 * @note bench_narrow forces every amount nonzero and forces the three distinct within a function by
 *       stepping upward and wrapping. Raw scaling does neither, so the two trees hold two different
 *       narrowed SHA-256s and a rank measured on one says nothing about the other. This reproduces
 *       bench_narrow's rule exactly so both objects can be read in one table.
 */
void clamped_amounts(const Mixer &mixer, unsigned width, unsigned *amounts)
{
    const unsigned standard[3] = {mixer.first, mixer.second, mixer.third};
    for (unsigned at = 0u; at < 3u; at += 1u)
    {
        unsigned value = ((standard[at] * width) + 16u) / 32u;
        if (value == 0u)
        {
            value = 1u;
        }
        if (value >= width)
        {
            value = width - 1u;
        }
        amounts[at] = value;
    }

    for (unsigned at = 1u; at < 3u; at += 1u)
    {
        for (unsigned attempt = 0u; attempt < width; attempt += 1u)
        {
            int clashes = 0;
            for (unsigned before = 0u; before < at; before += 1u)
            {
                clashes |= (amounts[at] == amounts[before]) ? 1 : 0;
            }
            if (clashes == 0)
            {
                break;
            }
            amounts[at] = (amounts[at] % (width - 1u)) + 1u;
        }
    }
}

/**
 * @brief Rank over GF(2) of a linear map given by the images of the basis vectors.
 *
 * @param[in] columns One image per input bit [BORROWS].
 * @param[in] width   How many input bits.
 * @return            The rank.
 * @note Plain elimination. The map is linear over GF(2) because every term is a rotation, a shift
 *       or an exclusive-or, so the images of the basis vectors determine it completely and nothing
 *       here is an approximation.
 */
unsigned rank_of(const uint32_t *columns, unsigned width)
{
    uint32_t working[32];
    for (unsigned at = 0u; at < width; at += 1u)
    {
        working[at] = columns[at];
    }

    unsigned found = 0u;
    for (unsigned bit = 0u; bit < width; bit += 1u)
    {
        unsigned pivot = found;
        while ((pivot < width) && ((working[pivot] & (1u << bit)) == 0u))
        {
            pivot += 1u;
        }
        if (pivot == width)
        {
            continue;
        }
        const uint32_t swap = working[found];
        working[found] = working[pivot];
        working[pivot] = swap;

        for (unsigned other = 0u; other < width; other += 1u)
        {
            if ((other != found) && ((working[other] & (1u << bit)) != 0u))
            {
                working[other] ^= working[found];
            }
        }
        found += 1u;
    }
    return found;
}

/**
 * @brief Degree of a polynomial over GF(2) held as a bit per coefficient.
 *
 * @param[in] polynomial Bit i is the coefficient of x to the i.
 * @return               The degree, or zero for the zero polynomial.
 */
unsigned degree_of(uint64_t polynomial)
{
    unsigned highest = 0u;
    for (unsigned at = 0u; at < 64u; at += 1u)
    {
        if ((polynomial & ((uint64_t)1u << at)) != 0u)
        {
            highest = at;
        }
    }
    return highest;
}

/**
 * @brief Greatest common divisor of two polynomials over GF(2).
 *
 * @param[in] left  First polynomial.
 * @param[in] right Second.
 * @return          Their gcd.
 * @note Euclid, with remainder by repeated shift-and-exclusive-or, which is what division is when
 *       the coefficients are bits and subtraction is exclusive-or.
 */
uint64_t common_divisor(uint64_t left, uint64_t right)
{
    while (right != 0u)
    {
        while ((left != 0u) && (degree_of(left) >= degree_of(right)))
        {
            left ^= (right << (degree_of(left) - degree_of(right)));
        }
        const uint64_t carry = left;
        left = right;
        right = carry;
    }
    return left;
}

/**
 * @brief What the polynomial law predicts a rotation-only function's kernel to be.
 *
 * @param[in] mixer Which function. Must be rotation-only for the law to apply.
 * @param[in] width Bits per word.
 * @return          The predicted kernel dimension.
 * @note A rotation right by a on a w-bit word is multiplication by x to the (w-a) in
 *       GF(2)[x]/(x^w + 1), so an exclusive-or of three rotations is multiplication by the sum of
 *       three such terms, and the kernel of multiplication by p is the degree of gcd(p, x^w + 1)
 *       exactly. Nothing about this is approximate and it is checked against the measured rank
 *       instead of reported alone.
 * @note Two equal amounts cancel instead of reinforcing, because the terms are added over GF(2).
 *       That is physical: ROTRa ^ ROTRa is zero, not 2 ROTRa.
 */
unsigned predicted_kernel(const Mixer &mixer, unsigned width)
{
    const unsigned amounts[3] = {((mixer.first * width) + 16u) / 32u,
                                 ((mixer.second * width) + 16u) / 32u,
                                 ((mixer.third * width) + 16u) / 32u};

    uint64_t polynomial = 0u;
    for (unsigned at = 0u; at < 3u; at += 1u)
    {
        const unsigned exponent = (width - (amounts[at] % width)) % width;
        polynomial ^= ((uint64_t)1u << exponent);
    }
    if (polynomial == 0u)
    {
        return width;
    }

    const uint64_t cycle = ((uint64_t)1u << width) ^ (uint64_t)1u;
    return degree_of(common_divisor(polynomial, cycle));
}

/**
 * @brief Kernel dimension of a rotation-only function given three amounts directly.
 *
 * @param[in] amounts Three rotation amounts [BORROWS].
 * @param[in] width   Bits per word.
 * @return            The kernel dimension.
 * @note Separate from predicted_kernel because that one scales the standard's amounts itself, and
 *       this one is handed the amounts bench_narrow arrived at after clamping.
 */
unsigned kernel_from_amounts(const unsigned *amounts, unsigned width)
{
    uint64_t polynomial = 0u;
    for (unsigned at = 0u; at < 3u; at += 1u)
    {
        polynomial ^= ((uint64_t)1u << ((width - (amounts[at] % width)) % width));
    }
    if (polynomial == 0u)
    {
        return width;
    }
    const uint64_t cycle = ((uint64_t)1u << width) ^ (uint64_t)1u;
    return degree_of(common_divisor(polynomial, cycle));
}

} // namespace

int main(void)
{
    const Mixer every[4] = {
        {"Sigma0", 2u, 13u, 22u, 0, "state"},
        {"Sigma1", 6u, 11u, 25u, 0, "state"},
        {"sigma0", 7u, 18u, 3u, 1, "schedule"},
        {"sigma1", 17u, 19u, 10u, 1, "schedule"}};

    std::printf("================================================================\n");
    std::printf("  How much space each mixing function throws away\n");
    std::printf("================================================================\n");
    std::printf("\n  All four are GF(2)-linear, so none of this is sampled. Each is a 32 by 32\n");
    std::printf("  matrix over GF(2), its rank is an elimination away, and the size of its image\n");
    std::printf("  is two to that rank exactly.\n");
    std::printf("\n  The state functions are rotations only. A rotation permutes bit positions and\n");
    std::printf("  loses nothing. The schedule functions each carry a shift, which does not.\n");

    std::printf("\n  %-8s %-10s %-18s %8s %8s %14s\n", "function", "serves", "terms", "rank",
                "kernel", "image");
    std::printf("  %-8s %-10s %-18s %8s %8s %14s\n", "--------", "----------",
                "------------------", "--------", "--------", "--------------");

    for (unsigned which = 0u; which < 4u; which += 1u)
    {
        const Mixer &mixer = every[which];
        uint32_t columns[32];
        for (unsigned bit = 0u; bit < WORD_BITS; bit += 1u)
        {
            columns[bit] = apply(mixer, (uint32_t)1u << bit, WORD_BITS);
        }
        const unsigned rank = rank_of(columns, WORD_BITS);
        const unsigned kernel = WORD_BITS - rank;

        char terms[32];
        std::snprintf(terms, sizeof(terms), "ROTR%u^ROTR%u^%s%u", mixer.first, mixer.second,
                      (mixer.third_is_shift != 0) ? "SHR" : "ROTR", mixer.third);

        char image[16];
        std::snprintf(image, sizeof(image), "2^%u", rank);
        std::printf("  %-8s %-10s %-18s %8u %8u %14s\n", mixer.name, mixer.belongs_to, terms, rank,
                    kernel, image);
    }

    std::printf("\n  A kernel of zero is a bijection: every input reaches its own output and nothing\n");
    std::printf("  has collided yet. A kernel above zero means that many bits of input are already\n");
    std::printf("  unrecoverable from the output of this one function, before the round it sits in\n");
    std::printf("  has done anything else.\n");

    // The same four narrowed, because bench_narrow sweeps the state pair across widths and has
    // never touched the schedule pair, and because the amounts move with the width and their
    // arithmetic relationship to it moves with them.
    std::printf("\n================================================================\n");
    std::printf("  The same four, narrowed\n");
    std::printf("================================================================\n");
    std::printf("\n  Amounts scaled the way bench_narrow scales the state pair, so a narrowed sigma\n");
    std::printf("  is the same kind of object as a narrowed Sigma. A rank short of the width is a\n");
    std::printf("  function that has stopped being a bijection at that width.\n");

    const unsigned WIDTHS = 8u;
    const unsigned width_of[WIDTHS] = {4u, 6u, 8u, 12u, 16u, 20u, 24u, 32u};

    std::printf("\n  %8s", "width");
    for (unsigned which = 0u; which < 4u; which += 1u)
    {
        std::printf(" %16s", every[which].name);
    }
    std::printf("\n  %8s", "--------");
    for (unsigned which = 0u; which < 4u; which += 1u)
    {
        std::printf(" %16s", "----------------");
    }
    std::printf("\n");

    for (unsigned at = 0u; at < WIDTHS; at += 1u)
    {
        const unsigned width = width_of[at];
        std::printf("  %8u", width);
        for (unsigned which = 0u; which < 4u; which += 1u)
        {
            uint32_t columns[32];
            for (unsigned bit = 0u; bit < width; bit += 1u)
            {
                columns[bit] = apply(every[which], (uint32_t)1u << bit, width);
            }
            const unsigned rank = rank_of(columns, width);

            char cell[24];
            std::snprintf(cell, sizeof(cell), "%u of %u%s", rank, width,
                          (rank < width) ? " lossy" : "");
            std::printf(" %16s", cell);
        }
        std::printf("\n");
    }

    std::printf("\n  A row where the schedule pair loses rank and the state pair does not is the\n");
    std::printf("  shift doing it, since that is the only structural difference between them.\n");
    std::printf("\n  These amounts are the raw scaled ones and an amount can come out zero, which\n");
    std::printf("  makes a term the identity. bench_narrow forces its amounts nonzero and distinct\n");
    std::printf("  instead, so its narrowed object and this one are not the same object and their\n");
    std::printf("  rows should not be read against each other.\n");

    // The rank deficit above is not an empirical curiosity. A rotation right by a on a w-bit word
    // is multiplication by x^(w-a) in GF(2)[x]/(x^w + 1), so three rotations exclusive-ored is
    // multiplication by a three-term polynomial, and the kernel of that is the degree of its gcd
    // with x^w + 1, exactly. That is a closed form for the whole column and it is checked here
    // instead of asserted, against the elimination that produced the table above.
    std::printf("\n================================================================\n");
    std::printf("  The rank deficit in closed form\n");
    std::printf("================================================================\n");
    std::printf("\n  A rotation right by a is multiplication by x^(w-a) in GF(2)[x]/(x^w + 1), so\n");
    std::printf("  three rotations exclusive-ored is multiplication by a three-term polynomial and\n");
    std::printf("  the kernel is the degree of its gcd with x^w + 1, exactly. This checks that\n");
    std::printf("  against the elimination instead of asserting it.\n");
    std::printf("\n  The law covers the state pair, which is rotations only. The schedule pair\n");
    std::printf("  carries a shift, which is multiplication modulo x^w instead of x^w + 1, so the\n");
    std::printf("  law does not apply to it and it is not claimed to.\n");

    std::printf("\n  %8s %10s %10s %10s %10s %10s\n", "width", "Sig0 meas", "Sig0 pred",
                "Sig1 meas", "Sig1 pred", "agrees");
    std::printf("  %8s %10s %10s %10s %10s %10s\n", "--------", "----------", "----------",
                "----------", "----------", "----------");

    unsigned disagreements = 0u;
    for (unsigned at = 0u; at < WIDTHS; at += 1u)
    {
        const unsigned width = width_of[at];
        unsigned measured[2];
        unsigned predicted[2];
        for (unsigned which = 0u; which < 2u; which += 1u)
        {
            uint32_t columns[32];
            for (unsigned bit = 0u; bit < width; bit += 1u)
            {
                columns[bit] = apply(every[which], (uint32_t)1u << bit, width);
            }
            measured[which] = width - rank_of(columns, width);
            predicted[which] = predicted_kernel(every[which], width);
        }
        const int agrees = ((measured[0] == predicted[0]) && (measured[1] == predicted[1])) ? 1 : 0;
        disagreements += (agrees == 0) ? 1u : 0u;
        std::printf("  %8u %10u %10u %10u %10u %10s\n", width, measured[0], predicted[0],
                    measured[1], predicted[1], (agrees != 0) ? "yes" : "NO");
    }

    // The object bench_narrow actually narrows, which is not this one. Its amounts are clamped
    // nonzero and forced distinct, and whether that repairs the damaged widths or moves the damage
    // somewhere else is a question about that bench's rows and has to be measured instead of
    // assumed from these.
    std::printf("\n  The same widths for the object bench_narrow narrows, whose amounts are clamped\n");
    std::printf("  nonzero and forced distinct instead of left raw. Its rows are the ones the\n");
    std::printf("  width sweep reports, so its deficits are the ones that bear on that table.\n");

    std::printf("\n  %6s %11s %7s %11s %7s %11s %7s %11s %7s\n", "width", "Sig0 amts", "kernel",
                "Sig1 amts", "kernel", "sig0 amts", "kernel", "sig1 amts", "kernel");
    std::printf("  %6s %11s %7s %11s %7s %11s %7s %11s %7s\n", "------", "-----------", "-------",
                "-----------", "-------", "-----------", "-------", "-----------", "-------");

    unsigned damaged_widths = 0u;
    unsigned consecutive_total = 0u;
    unsigned real_consecutive = 0u;
    for (unsigned at = 0u; at < WIDTHS; at += 1u)
    {
        const unsigned width = width_of[at];
        std::printf("  %6u", width);
        unsigned worst_here = 0u;
        for (unsigned which = 0u; which < 4u; which += 1u)
        {
            unsigned amounts[3];
            clamped_amounts(every[which], width, amounts);

            // The state pair is rotations only, so the closed form applies to it. The schedule pair
            // carries a shift and is measured by elimination instead, on the clamped amounts.
            unsigned kernel = 0u;
            if (every[which].third_is_shift == 0)
            {
                kernel = kernel_from_amounts(amounts, width);
            }
            else
            {
                uint32_t columns[32];
                for (unsigned bit = 0u; bit < width; bit += 1u)
                {
                    const uint32_t value = (uint32_t)1u << bit;
                    columns[bit] = turn_right(value, amounts[0], width) ^
                                   turn_right(value, amounts[1], width) ^
                                   shift_right(value, amounts[2], width);
                }
                kernel = width - rank_of(columns, width);
            }
            worst_here = (kernel > worst_here) ? kernel : worst_here;

            // Two amounts one apart is a regularity the standard does not have at any of its four
            // functions, and the distinctness rule manufactures it: two amounts that scale onto the
            // same value get stepped apart by exactly one. Counting it here instead of noticing it
            // by eye, because it applies to every narrowed row and to none of the real ones.
            unsigned adjacent = 0u;
            for (unsigned left = 0u; left < 3u; left += 1u)
            {
                for (unsigned right = left + 1u; right < 3u; right += 1u)
                {
                    const unsigned apart = (amounts[left] > amounts[right])
                                               ? (amounts[left] - amounts[right])
                                               : (amounts[right] - amounts[left]);
                    adjacent += (apart == 1u) ? 1u : 0u;
                }
            }
            consecutive_total += (width < 32u) ? adjacent : 0u;
            real_consecutive += (width == 32u) ? adjacent : 0u;

            char text[16];
            std::snprintf(text, sizeof(text), "%u,%u,%u", amounts[0], amounts[1], amounts[2]);
            std::printf(" %11s %7u", text, kernel);
        }
        damaged_widths += (worst_here > 0u) ? 1u : 0u;
        std::printf("\n");
    }

    std::printf("\n  %u of %u widths carry a kernel in bench_narrow's object.\n", damaged_widths,
                WIDTHS);
    std::printf("  %u pairs of amounts sit one apart across the narrowed widths, against %u at\n",
                consecutive_total, real_consecutive);
    std::printf("  width 32. Two amounts one apart is a regularity the standard has at none of its\n");
    std::printf("  four functions, and the distinctness rule manufactures it whenever two amounts\n");
    std::printf("  scale onto the same value. Every narrowed row therefore carries structure the\n");
    std::printf("  real thing does not, which is a fourth reason the width sweep compares different\n");
    std::printf("  constructions instead of one at several sizes.\n");

    if (disagreements == 0u)
    {
        std::printf("\n  Every row agrees, so the deficit is the gcd and not a coincidence of these\n");
        std::printf("  particular amounts. A width sharing a factor with the polynomial loses that\n");
        std::printf("  much rank and a width coprime to it loses none, which is why the narrowed\n");
        std::printf("  sweep in bench_narrow is measuring seven different constructions.\n");
    }
    else
    {
        std::printf("\n  [!] %u rows disagree, so either the law is wrong here or the elimination is,\n",
                    disagreements);
        std::printf("  and nothing above that leans on either of them should be believed until it\n");
        std::printf("  is settled.\n");
    }

    // Rank was the wrong place to look for schedule weakness, because there is none there. Where a
    // linear schedule is actually weak is sparsity: a difference that stays low-weight for many
    // words is a differential an attacker can follow, and the schedule is linear enough over GF(2)
    // that a one-bit nonce flip need not fan out quickly.
    //
    // The expansion adds instead of exclusive-ors, so the difference a flip produces depends on
    // the header it is flipped in, through carries. That makes the minimum over headers the honest
    // figure and the mean the typical one, and the two apart is the carry structure.
    std::printf("\n================================================================\n");
    std::printf("  How sparse a nonce difference stays\n");
    std::printf("================================================================\n");
    std::printf("\n  Rank found no weakness, so this asks the question a linear schedule is actually\n");
    std::printf("  weak at: how long a one-bit nonce flip stays low-weight as it expands. A word\n");
    std::printf("  whose difference is zero is a word the nonce has not reached at all; a word whose\n");
    std::printf("  difference stays at one or two bits is one an attacker can follow.\n");
    std::printf("\n  Expansion adds instead of exclusive-ors, so the difference depends on the\n");
    std::printf("  header through carries. The minimum over headers is the honest figure.\n");

    {
        const unsigned HEADERS = 4096u;
        const unsigned NONCE_WORD = 3u;

        unsigned smallest[64];
        double running[64];
        unsigned never[64];
        for (unsigned at = 0u; at < 64u; at += 1u)
        {
            smallest[at] = 33u;
            running[at] = 0.0;
            never[at] = 0u;
        }
        double counted = 0.0;

        uint64_t generator = 20260909ull;
        for (unsigned header = 0u; header < HEADERS; header += 1u)
        {
            uint32_t base[64];
            for (unsigned at = 0u; at < 16u; at += 1u)
            {
                generator += 0x9e3779b97f4a7c15ull;
                uint64_t mixed = generator;
                mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
                mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
                base[at] = (uint32_t)(mixed ^ (mixed >> 31));
            }

            for (unsigned bit = 0u; bit < WORD_BITS; bit += 1u)
            {
                uint32_t left[64];
                uint32_t right[64];
                for (unsigned at = 0u; at < 16u; at += 1u)
                {
                    left[at] = base[at];
                    right[at] = base[at];
                }
                right[NONCE_WORD] ^= ((uint32_t)1u << bit);

                for (unsigned at = 16u; at < 64u; at += 1u)
                {
                    for (unsigned side = 0u; side < 2u; side += 1u)
                    {
                        uint32_t *const walk = (side == 0u) ? left : right;
                        const uint32_t low = turn_right(walk[at - 15u], 7u, WORD_BITS) ^
                                             turn_right(walk[at - 15u], 18u, WORD_BITS) ^
                                             shift_right(walk[at - 15u], 3u, WORD_BITS);
                        const uint32_t high = turn_right(walk[at - 2u], 17u, WORD_BITS) ^
                                              turn_right(walk[at - 2u], 19u, WORD_BITS) ^
                                              shift_right(walk[at - 2u], 10u, WORD_BITS);
                        walk[at] = walk[at - 16u] + low + walk[at - 7u] + high;
                    }
                }

                for (unsigned at = 0u; at < 64u; at += 1u)
                {
                    const unsigned weight = (unsigned)__builtin_popcount(left[at] ^ right[at]);
                    smallest[at] = (weight < smallest[at]) ? weight : smallest[at];
                    running[at] += (double)weight;
                    never[at] += (weight == 0u) ? 1u : 0u;
                }
            }
            counted += (double)WORD_BITS;
        }

        std::printf("\n  %6s %10s %10s %14s   %6s %10s %10s %14s\n", "word", "min bits",
                    "mean bits", "never reached", "word", "min bits", "mean bits",
                    "never reached");
        std::printf("  %6s %10s %10s %14s   %6s %10s %10s %14s\n", "------", "----------",
                    "----------", "--------------", "------", "----------", "----------",
                    "--------------");
        for (unsigned at = 0u; at < 32u; at += 1u)
        {
            const unsigned other = at + 32u;
            std::printf("  %6u %10u %10.2f %13.1f%%   %6u %10u %10.2f %13.1f%%\n", at,
                        smallest[at], running[at] / counted,
                        (100.0 * (double)never[at]) / counted, other, smallest[other],
                        running[other] / counted, (100.0 * (double)never[other]) / counted);
        }

        // Where the difference is first guaranteed nonzero, and where it first saturates. Sixteen
        // is half of thirty-two, which is what an unrelated pair of words averages.
        unsigned first_forced = 64u;
        unsigned first_full = 64u;
        for (unsigned at = 0u; at < 64u; at += 1u)
        {
            if ((first_forced == 64u) && (never[at] == 0u) && (smallest[at] > 0u))
            {
                first_forced = at;
            }
            if ((first_full == 64u) && ((running[at] / counted) > 15.0))
            {
                first_full = at;
            }
        }
        std::printf("\n  %-52s %8u\n", "first word the nonce always reaches", first_forced);
        std::printf("  %-52s %8u\n", "first word averaging over 15 bits of difference", first_full);
        std::printf("  %-52s %8u\n", "rounds between those two", first_full - first_forced);

        std::printf("\n  A min column holding at one for several words is a one-bit difference the\n");
        std::printf("  schedule carries without fanning out, which is the shape a differential\n");
        std::printf("  attack follows. A mean near sixteen is a word behaving like an unrelated\n");
        std::printf("  word, since half of thirty-two is what two unrelated words differ by.\n");
    }
    return 0;
}
