/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_depth_score.h
 * @brief The single place that turns a sum of Hamming distances into a distance from saturation.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Both the host scan and the device scan produce the same thing - a sum of Hamming distances
 *       and a count - and both need it turned into standard errors from saturation. That is four
 *       lines of arithmetic, exactly the size of thing that gets written twice and then
 *       disagrees. Failure mode fifteen in docs/failure-modes.md is a formula written twice, and it
 *       has already put two wrong numbers in this tree's headline tables.
 * @note The null is exact and not fitted. Once a difference has diffused, an output word
 *       differs in a Binomial(32, 1/2) number of bits, so the mean sits at 16 with a standard
 *       deviation of sqrt(32)/2. Nothing about that depends on the function under test.
 */

#ifndef BENCH_DEPTH_SCORE_H
#define BENCH_DEPTH_SCORE_H

#include <cmath>

/** @brief Bits in the word whose Hamming distance is being read. */
#define BENCH_DEPTH_WORD_BITS 32.0

/**
 * @brief How far a mean Hamming distance sits from saturation, at a stated word width.
 *
 * @param[in] total   Sum of the observed Hamming distances.
 * @param[in] counted How many observations went into that sum.
 * @param[in] bits    Bits per word, which sets the null.
 * @return            Distance from the saturated mean, in standard errors, or zero where nothing
 *                    was counted.
 * @note A narrowed word saturates at bits/2 with deviation sqrt(bits)/2, so the null moves with the
 *       width and a fixed 32-bit null would report a width sweep's every row as biased.
 */
static inline double bench_depth_score_at_width(double total, double counted, double bits)
{
    if ((counted <= 0.0) || (bits <= 0.0))
    {
        return 0.0;
    }
    const double mean = total / counted;
    const double deviation = std::sqrt(bits) / 2.0;
    const double standard_error = deviation / std::sqrt(counted);
    return (mean - (bits / 2.0)) / standard_error;
}

/**
 * @brief The largest magnitude this statistic can reach, which is a completely untouched word.
 *
 * @param[in] counted How many observations went into the sum.
 * @param[in] bits    Bits per word.
 * @return            The ceiling, or zero where nothing was counted.
 * @note A word no difference has reached yet reads a mean distance of zero, the furthest
 *       from saturation the statistic goes. Successive rounds all pin there and read identically,
 *       so those rounds carry no decay information and must be kept out of any fitted slope. Left
 *       in, they flatten the fit toward the ceiling and not toward the trend.
 */
static inline double bench_depth_ceiling(double counted, double bits)
{
    if ((counted <= 0.0) || (bits <= 0.0))
    {
        return 0.0;
    }
    return (bits / 2.0) / ((std::sqrt(bits) / 2.0) / std::sqrt(counted));
}

/**
 * @brief How far a mean Hamming distance sits from saturation, in standard errors.
 *
 * @param[in] total   Sum of the observed Hamming distances.
 * @param[in] counted How many observations went into that sum.
 * @return            Distance from the saturated mean, in standard errors, or zero where nothing
 *                    was counted.
 * @note Positive and negative are both meaningful and the caller takes the magnitude where it wants
 *       a depth. A difference that has not diffused reads far below sixteen because the output
 *       still resembles the input.
 */
static inline double bench_depth_score(double total, double counted)
{
    return bench_depth_score_at_width(total, counted, BENCH_DEPTH_WORD_BITS);
}

/**
 * @brief How far one bit position's difference rate sits from a coin, in standard errors.
 *
 * @param[in] differed How often that position differed.
 * @param[in] counted  How many observations went into that count.
 * @return             Distance from one half, in standard errors, or zero where nothing was
 *                     counted.
 * @note The mean Hamming distance a word reports is the sum of thirty-two of these, and a pair of
 *       positions leaning opposite ways cancels there and survives here. That makes this a strict
 *       refinement and not a second opinion: it sees everything the word statistic sees, plus
 *       what summing throws away.
 * @note The null is a coin, so the deviation is one half exactly and does not depend on the
 *       function under test any more than the word null does.
 */
static inline double bench_depth_bit_score(double differed, double counted)
{
    if (counted <= 0.0)
    {
        return 0.0;
    }
    const double rate = differed / counted;
    const double standard_error = 0.5 / std::sqrt(counted);
    return (rate - 0.5) / standard_error;
}

#endif
