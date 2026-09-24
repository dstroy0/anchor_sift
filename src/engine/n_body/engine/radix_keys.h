/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file radix_keys.h
 * @brief Least significant digit radix sorts over 64 bit keys, alone or carrying a 32 bit value.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Callers pack several fields into one key, most significant field in the highest bits: the
 *       two ends of a pair in binomial_basins.cu, a capped distance above a pair index in
 *       track_driver.cu, two labels above a contact face in track_driver.cu. Sorting the packed key
 *       orders by the highest field and breaks ties on the lower ones, with no comparison function.
 * @note Eight passes of one byte each, in time linear in the key count. No two keys are ever
 *       compared, and the same keys sort to the same order on every run.
 * @note Header only and static inline, since the sorts run on the host inside several translation
 *       units that nvcc and cl each compile.
 */
#ifndef RADIX_KEYS_H
#define RADIX_KEYS_H

#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

    /**
     * @brief Sorts 64 bit keys ascending in place.
     *
     * @param[in,out] keys  Keys to sort [BORROWS].
     * @param[in]     count How many keys.
     * @return              1 where the keys are sorted, 0 where the scratch array could not be
     *                      allocated.
     * @note A pass is skipped where every key carries the same byte at that shift. Keys that differ
     *       only in their low bytes then cost only the passes over those bytes.
     * @warning On a return of 0 the keys are left in their input order. A caller that goes on to read
     *          them as sorted gets an unsorted array and no other sign of it.
     */
static inline int radix_sort_keys(unsigned long long *keys, size_t count)
{
    if (count < 2u)
    {
        return 1;
    }
    unsigned long long *const scratch = (unsigned long long *)malloc(count * sizeof(unsigned long long));
    if (scratch == NULL)
    {
        return 0;
    }
    unsigned long long *source = keys;
    unsigned long long *destination = scratch;
    size_t histogram[256];
    for (unsigned int shift = 0u; shift < 64u; shift += 8u)
    {
        memset(histogram, 0, sizeof(histogram));
        for (size_t at = 0u; at < count; at += 1u)
        {
            histogram[(source[at] >> shift) & 0xFFull] += 1u;
        }

            // Every key landed in one bucket, the bucket of the first key. The pass would copy
            // the array unchanged.
        if (histogram[(source[0] >> shift) & 0xFFull] == count)
        {
            continue;
        }
            // The counts become starting offsets, an exclusive prefix sum over the 256 buckets.
        size_t running = 0u;
        for (unsigned int digit = 0u; digit < 256u; digit += 1u)
        {
            const size_t here = histogram[digit];
            histogram[digit] = running;
            running += here;
        }
            // Scattered in input order within each bucket, which keeps the sort stable and lets the
            // later, higher passes preserve the order the earlier ones set.
        for (size_t at = 0u; at < count; at += 1u)
        {
            const size_t digit = (size_t)((source[at] >> shift) & 0xFFull);
            destination[histogram[digit]] = source[at];
            histogram[digit] += 1u;
        }
        unsigned long long *const swapped = source;
        source = destination;
        destination = swapped;
    }
        // An odd number of passes that moved data leaves the result in the scratch array.
    if (source != keys)
    {
        memcpy(keys, source, count * sizeof(unsigned long long));
    }
    free(scratch);
    return 1;
}

    /**
     * @brief Sorts 64 bit keys ascending in place and moves a 32 bit value with each key.
     *
     * @param[in,out] keys   Keys to sort [BORROWS].
     * @param[in,out] values One value per key, reordered with it [BORROWS].
     * @param[in]     count  How many keys.
     * @return               1 where the keys are sorted, 0 where either scratch array could not be
     *                       allocated.
     * @note The same passes as radix_sort_keys. The value rides in the scatter step and plays no part
     *       in the order. Two equal keys keep their values in input order.
     * @warning On a return of 0 the keys and values are left in their input order.
     */
static inline int radix_sort_keyed(unsigned long long *keys, unsigned int *values, size_t count)
{
    if (count < 2u)
    {
        return 1;
    }
    unsigned long long *const scratch_keys = (unsigned long long *)malloc(count * sizeof(unsigned long long));
    unsigned int *const scratch_values = (unsigned int *)malloc(count * sizeof(unsigned int));
    if ((scratch_keys == NULL) || (scratch_values == NULL))
    {
        free(scratch_keys);
        free(scratch_values);
        return 0;
    }
    unsigned long long *source_keys = keys;
    unsigned int *source_values = values;
    unsigned long long *destination_keys = scratch_keys;
    unsigned int *destination_values = scratch_values;
    size_t histogram[256];
    for (unsigned int shift = 0u; shift < 64u; shift += 8u)
    {
        memset(histogram, 0, sizeof(histogram));
        for (size_t at = 0u; at < count; at += 1u)
        {
            histogram[(source_keys[at] >> shift) & 0xFFull] += 1u;
        }

            // Every key shares this byte, and the pass would move nothing.
        if (histogram[(source_keys[0] >> shift) & 0xFFull] == count)
        {
            continue;
        }
        size_t running = 0u;
        for (unsigned int digit = 0u; digit < 256u; digit += 1u)
        {
            const size_t here = histogram[digit];
            histogram[digit] = running;
            running += here;
        }
        for (size_t at = 0u; at < count; at += 1u)
        {
            const size_t digit = (size_t)((source_keys[at] >> shift) & 0xFFull);
            destination_keys[histogram[digit]] = source_keys[at];
            destination_values[histogram[digit]] = source_values[at];
            histogram[digit] += 1u;
        }
        unsigned long long *const swapped_keys = source_keys;
        source_keys = destination_keys;
        destination_keys = swapped_keys;
        unsigned int *const swapped_values = source_values;
        source_values = destination_values;
        destination_values = swapped_values;
    }
    if (source_keys != keys)
    {
        memcpy(keys, source_keys, count * sizeof(unsigned long long));
        memcpy(values, source_values, count * sizeof(unsigned int));
    }
    free(scratch_keys);
    free(scratch_values);
    return 1;
}

#ifdef __cplusplus
}
#endif

#endif
