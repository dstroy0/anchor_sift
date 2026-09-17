/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file heaviest_matching.h
 * @brief The one-to-one pairing of objects across a frame pair that carries the most overlap, exactly.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * Each object before is paired with at most one object after and each object after with at most
 * one before, and the pairing chosen maximises the total shared voxel count. Successive shortest
 * augmenting paths on the negated counts, with integer potentials so every search is Dijkstra over
 * non-negative reduced costs, one connected component at a time. Augmentation stops when the
 * cheapest remaining path adds no overlap. Every value is a 64 bit integer, so the pairing is the
 * maximum and not an approximation of it.
 *
 * @note Portable C11 and single threaded. An augmenting path depends on every path before it, so
 *       this is a sequential algorithm and has no device engine.
 * @note Where two pairings carry equal overlap, the one returned is fixed by node index order in the
 *       search, so the same input always yields the same pairing.
 */
#ifndef HEAVIEST_MATCHING_H
#define HEAVIEST_MATCHING_H

#ifdef __cplusplus
extern "C" {
#endif

/* The export spelling for a DLL build, and nothing otherwise. Both arms are defined. */
#if defined(HEAVIEST_MATCHING_BUILD_DLL) && HEAVIEST_MATCHING_BUILD_DLL && defined(_WIN32)
#define HEAVIEST_MATCHING_EXPORT __declspec(dllexport)
#else
#define HEAVIEST_MATCHING_EXPORT
#endif

/** @brief Returned where the work was refused. */
#define HEAVIEST_MATCHING_REFUSED (-1L)

/**
 * @brief Weighted pairs and where the choice goes.
 *
 * @note Objects are dense indices: every `before` is below `before_count` and every `after` below
 *       `after_count`. A pair may appear once. Counts must be positive.
 */
typedef struct
{
    const unsigned int *before;       /**< Object before, per pair [BORROWS]. */
    const unsigned int *after;        /**< Object after, per pair [BORROWS]. */
    const unsigned int *counts;       /**< Shared voxels, per pair [BORROWS]. */
    unsigned int pairs;               /**< How many pairs. */
    unsigned int before_count;        /**< Objects before. */
    unsigned int after_count;         /**< Objects after. */
    unsigned char *chosen;            /**< Out: 1 per pair in the pairing, 0 otherwise [BORROWS]. */
} HeaviestMatchingRequest;

/**
 * @brief Chooses the heaviest one-to-one pairing.
 *
 * @param[in] args The request [BORROWS].
 * @return         Pairs chosen, or HEAVIEST_MATCHING_REFUSED. `chosen` is written only on success.
 */
HEAVIEST_MATCHING_EXPORT long heaviest_matching_run(const HeaviestMatchingRequest *args);

#ifdef __cplusplus
}
#endif

#endif /* HEAVIEST_MATCHING_H */
