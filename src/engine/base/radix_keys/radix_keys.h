// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RADIX_KEYS_H
#define RADIX_KEYS_H

#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

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
