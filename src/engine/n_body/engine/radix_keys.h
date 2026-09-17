/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file radix_keys.h
 * @brief Ascending order of unsigned 64 bit keys by least significant digit first radix passes.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * Integers have one ascending order, so this returns exactly what qsort under an ascending comparison
 * returns; only the time differs. Eight passes of one byte each; a pass whose byte is equal across
 * every key moves nothing and is skipped.
 */
#ifndef RADIX_KEYS_H
#define RADIX_KEYS_H

#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Sorts keys ascending in place.
 *
 * @param[in,out] keys  The keys [BORROWS].
 * @param[in]     count How many.
 * @return              1 on success, 0 where the scratch buffer could not be had, keys unchanged.
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
        // A byte equal across every key leaves the order as it is.
        if (histogram[(source[0] >> shift) & 0xFFull] == count)
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
            const size_t digit = (size_t)((source[at] >> shift) & 0xFFull);
            destination[histogram[digit]] = source[at];
            histogram[digit] += 1u;
        }
        unsigned long long *const swapped = source;
        source = destination;
        destination = swapped;
    }
    if (source != keys)
    {
        memcpy(keys, source, count * sizeof(unsigned long long));
    }
    free(scratch);
    return 1;
}

/**
 * @brief Sorts keys ascending in place, each carrying its value with it.
 *
 * Equal keys may land in any order among themselves; a caller that sums the values of equal keys gets
 * the same totals either way.
 *
 * @param[in,out] keys   The keys [BORROWS].
 * @param[in,out] values One value per key [BORROWS].
 * @param[in]     count  How many.
 * @return               1 on success, 0 where the scratch buffers could not be had, both unchanged.
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
        // A byte equal across every key leaves the order as it is.
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

#endif /* RADIX_KEYS_H */
