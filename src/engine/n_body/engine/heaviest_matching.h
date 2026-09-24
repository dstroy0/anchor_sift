/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file heaviest_matching.h
 * @brief The heaviest one to one matching between two sets of objects, over integer weights.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Given candidate pairs, each joining an object on the before side to one on the after side
 *       with a positive integer count, this chooses the pairs to keep so no object is kept twice and
 *       the kept counts sum as high as any such choice can. Every weight and every path cost is an
 *       integer, and no tolerance enters the choice.
 * @note Ties are broken by node index inside the search. One input always yields one choice.
 */
#ifndef HEAVIEST_MATCHING_H
#define HEAVIEST_MATCHING_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(HEAVIEST_MATCHING_BUILD_DLL) && HEAVIEST_MATCHING_BUILD_DLL && defined(_WIN32)
#define HEAVIEST_MATCHING_EXPORT __declspec(dllexport)
#else
#define HEAVIEST_MATCHING_EXPORT
#endif

/** @brief What heaviest_matching_run returns for a request it will not run or could not finish. */
#define HEAVIEST_MATCHING_REFUSED (-1L)

/** @brief The candidate pairs and where the choice is written. */
typedef struct
{
    const unsigned int *before; /**< Before-side object of each pair, below before_count [BORROWS]. */
    const unsigned int *after;  /**< After-side object of each pair, below after_count [BORROWS]. */
    const unsigned int *counts; /**< Weight of each pair, never 0 [BORROWS]. */
    unsigned int pairs;         /**< How many pairs. */
    unsigned int before_count;  /**< Objects on the before side. */
    unsigned int after_count;   /**< Objects on the after side. */
    unsigned char *chosen;      /**< One byte per pair, 1 where kept and 0 where not [BORROWS]. */
} HeaviestMatchingRequest;

/**
 * @brief Chooses the heaviest set of pairs in which no object appears twice.
 *
 * @param[in] args The pairs and the output array [BORROWS].
 * @return         How many pairs were kept, or HEAVIEST_MATCHING_REFUSED where a pointer is null, a
 *                 count is above 0x3FFFFFFF, a pair names an object past its side's count, a pair
 *                 carries a count of 0, or an allocation failed.
 * @note Objects linked through shared pairs form components, and each component is matched on its
 *       own. Pairs in different components never compete.
 * @note A pair is kept only where it adds weight. The result is the heaviest matching, which need
 *       not be the one keeping the most pairs.
 * @note On a refusal `chosen` is left unchanged.
 * @warning A component's edge count is computed in int as 2 * (before objects + after objects +
 *          pairs). The 0x3FFFFFFF limits each keep one term below 2^30, and three such terms
 *          doubled pass 2^31 and wrap. No bound on the sum is checked.
 */
HEAVIEST_MATCHING_EXPORT long heaviest_matching_run(const HeaviestMatchingRequest *args);

#ifdef __cplusplus
}
#endif

#endif
