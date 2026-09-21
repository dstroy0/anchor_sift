#include "shift_agreement.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(unsigned int) == 4u, "shift_agreement: unsigned int must be 32 bits, a residue");
_Static_assert(sizeof(unsigned long long) == 8u, "shift_agreement: unsigned long long must be 64 bits, a product");

static unsigned int agreement_power(unsigned int base, unsigned long long exponent)
{
    unsigned long long result = 1ull;
    unsigned long long square = (unsigned long long)base;
    while (exponent != 0ull)
    {
        if ((exponent & 1ull) != 0ull)
        {
            result = (result * square) % SHIFT_AGREEMENT_PRIME;
        }
        square = (square * square) % SHIFT_AGREEMENT_PRIME;
        exponent >>= 1u;
    }

    return (unsigned int)result;
}

static unsigned int agreement_power_of_two(unsigned long long value)
{
    unsigned long long power = 1ull;
    while (power < value)
    {
        power <<= 1u;
    }

    return (unsigned int)power;
}

static void agreement_transform_axis(unsigned int *values, size_t total, unsigned int length, size_t stride,
                                     int inverse)
{
    if (length < 2u)
    {
        return;
    }
    size_t logarithm = 0u;
    while ((1u << logarithm) < length)
    {
        logarithm += 1u;
    }
    const size_t span = (size_t)length * stride;
    for (size_t line = 0u; line < total; line += 1u)
    {

        if ((line % span) >= stride)
        {
            continue;
        }
        for (unsigned int position = 0u; position < length; position += 1u)
        {
            unsigned int reversed = 0u;
            for (size_t bit = 0u; bit < logarithm; bit += 1u)
            {
                reversed |= ((position >> bit) & 1u) << (logarithm - 1u - bit);
            }
            if (position < reversed)
            {
                const unsigned int held = values[line + ((size_t)position * stride)];
                values[line + ((size_t)position * stride)] = values[line + ((size_t)reversed * stride)];
                values[line + ((size_t)reversed * stride)] = held;
            }
        }
        for (unsigned int size = 2u; size <= length; size <<= 1u)
        {
            unsigned int root = agreement_power(3u, (SHIFT_AGREEMENT_PRIME - 1u) / size);
            if (inverse != 0)
            {
                root = agreement_power(root, SHIFT_AGREEMENT_PRIME - 2u);
            }
            const unsigned int half = size / 2u;
            for (unsigned int start = 0u; start < length; start += size)
            {
                unsigned long long factor = 1ull;
                for (unsigned int offset = 0u; offset < half; offset += 1u)
                {
                    const size_t near = line + ((size_t)(start + offset) * stride);
                    const size_t far = line + ((size_t)(start + offset + half) * stride);
                    const unsigned long long upper = (unsigned long long)values[near];
                    const unsigned long long lower = ((unsigned long long)values[far] * factor) % SHIFT_AGREEMENT_PRIME;

                    values[near] = (unsigned int)((upper + lower) % SHIFT_AGREEMENT_PRIME);
                    values[far] = (unsigned int)((upper + SHIFT_AGREEMENT_PRIME - lower) % SHIFT_AGREEMENT_PRIME);
                    factor = (factor * (unsigned long long)root) % SHIFT_AGREEMENT_PRIME;
                }
            }
        }
        if (inverse != 0)
        {
            const unsigned long long scale = (unsigned long long)agreement_power(length, SHIFT_AGREEMENT_PRIME - 2u);
            for (unsigned int position = 0u; position < length; position += 1u)
            {
                const size_t at = line + ((size_t)position * stride);

                values[at] = (unsigned int)(((unsigned long long)values[at] * scale) % SHIFT_AGREEMENT_PRIME);
            }
        }
    }
}

long shift_agreement_host(ShiftAgreementRequest *args)
{
    if ((args == NULL) || (args->before == NULL) || (args->after == NULL) || (args->axes == 0u)
     || (args->axes > SHIFT_AGREEMENT_AXES))
    {
        return SHIFT_AGREEMENT_REFUSED;
    }
    unsigned long long voxels = 1ull;
    unsigned long long padded_total = 1ull;
    unsigned int padded[SHIFT_AGREEMENT_AXES];
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        if ((args->extents[axis] == 0u) || (args->extents[axis] > (SHIFT_AGREEMENT_LONGEST_AXIS / 2u)))
        {
            return SHIFT_AGREEMENT_REFUSED;
        }
        voxels *= (unsigned long long)args->extents[axis];
        padded[axis] = agreement_power_of_two((2ull * (unsigned long long)args->extents[axis]) - 1ull);
        padded_total *= (unsigned long long)padded[axis];
        if ((voxels >= (unsigned long long)SHIFT_AGREEMENT_PRIME) || (padded_total > 0x7FFFFFFFull))
        {
            return SHIFT_AGREEMENT_REFUSED;
        }
    }

    const size_t total = (size_t)padded_total;
    const size_t count = (size_t)voxels;
    unsigned int *const reflected = (unsigned int *)calloc(total, sizeof(unsigned int));
    unsigned int *const moved = (unsigned int *)calloc(total, sizeof(unsigned int));
    if ((reflected == NULL) || (moved == NULL))
    {
        free(reflected);
        free(moved);
        return SHIFT_AGREEMENT_REFUSED;
    }

    for (size_t position = 0u; position < count; position += 1u)
    {
        const unsigned long long bit = 1ull << (position % 64u);
        const int in_before = (args->before[position / 64u] & bit) != 0ull;
        const int in_after = (args->after[position / 64u] & bit) != 0ull;
        if ((in_before == 0) && (in_after == 0))
        {
            continue;
        }
        size_t rest = position;
        size_t direct = 0u;
        size_t negated = 0u;
        for (unsigned int axis = args->axes; axis > 0u; axis -= 1u)
        {
            const size_t coordinate = rest % args->extents[axis - 1u];
            rest /= args->extents[axis - 1u];
            size_t stride = 1u;
            for (unsigned int later = axis; later < args->axes; later += 1u)
            {
                stride *= padded[later];
            }
            direct += coordinate * stride;
            negated += ((padded[axis - 1u] - coordinate) % padded[axis - 1u]) * stride;
        }
        if (in_before != 0)
        {
            reflected[negated] = 1u;
        }
        if (in_after != 0)
        {
            moved[direct] = 1u;
        }
    }

    size_t stride = total;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        stride /= padded[axis];
        agreement_transform_axis(reflected, total, padded[axis], stride, 0);
        agreement_transform_axis(moved, total, padded[axis], stride, 0);
    }
    for (size_t at = 0u; at < total; at += 1u)
    {

        reflected[at] = (unsigned int)(((unsigned long long)reflected[at] * (unsigned long long)moved[at])
                                       % SHIFT_AGREEMENT_PRIME);
    }
    stride = total;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        stride /= padded[axis];
        agreement_transform_axis(reflected, total, padded[axis], stride, 1);
    }

    size_t best = 0u;
    unsigned long long best_length = 0xFFFFFFFFFFFFFFFFull;
    for (size_t at = 0u; at < total; at += 1u)
    {
        if (reflected[at] < reflected[best])
        {
            continue;
        }
        size_t rest = at;
        unsigned long long length = 0ull;
        for (unsigned int axis = args->axes; axis > 0u; axis -= 1u)
        {
            const long long coordinate = (long long)(rest % padded[axis - 1u]);
            rest /= padded[axis - 1u];
            const long long lag = (coordinate < (long long)(padded[axis - 1u] / 2u))
                                ? coordinate
                                : (coordinate - (long long)padded[axis - 1u]);
            length += (unsigned long long)args->weights[axis - 1u] * (unsigned long long)(lag * lag);
        }
        if ((reflected[at] > reflected[best]) || (length < best_length))
        {
            best = at;
            best_length = length;
        }
    }

    size_t rest = best;
    for (unsigned int axis = args->axes; axis > 0u; axis -= 1u)
    {
        const long long coordinate = (long long)(rest % padded[axis - 1u]);
        rest /= padded[axis - 1u];

        args->lag[axis - 1u] = (int)((coordinate < (long long)(padded[axis - 1u] / 2u))
                                     ? coordinate
                                     : (coordinate - (long long)padded[axis - 1u]));
    }
    for (unsigned int axis = 0u; axis < SHIFT_AGREEMENT_AXES; axis += 1u)
    {
        args->padded[axis] = (axis < args->axes) ? padded[axis] : 0u;
        if (axis >= args->axes)
        {
            args->lag[axis] = 0;
        }
    }
    args->agreement = reflected[best];
    if (args->counts != NULL)
    {
        memcpy(args->counts, reflected, total * sizeof(unsigned int));
    }
    free(reflected);
    free(moved);
    return 0L;
}
