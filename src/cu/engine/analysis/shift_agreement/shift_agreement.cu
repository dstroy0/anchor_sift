// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// shift_agreement.cu: the kernels and the agreement's arithmetic
#include "shift_agreement_internal.h"

__device__ static unsigned long long lag_length(unsigned int index, const AgreementLayout *layout)
{
    unsigned int rest = index;
    unsigned long long length = 0ull;
    for (unsigned int axis = layout->axes; axis > 0u; axis -= 1u)
    {
        const long long coordinate = (long long)(rest % layout->padded[axis - 1u]);
        rest /= layout->padded[axis - 1u];
        const long long lag = (coordinate < (long long)(layout->padded[axis - 1u] / 2u))
                                  ? coordinate
                                  : (coordinate - (long long)layout->padded[axis - 1u]);
        length += (unsigned long long)layout->weights[axis - 1u] * (unsigned long long)(lag * lag);
    }
    return length;
}

__global__ void choice_kernel(unsigned int total, unsigned int *choice)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    choice[element] = element;
}

__global__ void tournament_kernel(const unsigned int *counts, unsigned int *choice, unsigned int stride,
                                  unsigned int pairs, AgreementLayout layout)
{
    const unsigned int pair = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (pair >= pairs)
    {
        return;
    }
    const unsigned int here = pair * 2u * stride;
    const unsigned int there = here + stride;
    if (there >= layout.total)
    {
        return;
    }
    const unsigned int left = choice[here];
    const unsigned int right = choice[there];
    int right_better = 0;
    if (counts[right] != counts[left])
    {
        right_better = (counts[right] > counts[left]) ? 1 : 0;
    }
    else
    {
        const unsigned long long left_length = lag_length(left, &layout);
        const unsigned long long right_length = lag_length(right, &layout);
        right_better = ((right_length < left_length) || ((right_length == left_length) && (right < left))) ? 1 : 0;
    }
    if (right_better != 0)
    {
        choice[here] = right;
    }
}

#define SHIFT_AGREEMENT_BARRETT (4611686018427387904ull / (unsigned long long)SHIFT_AGREEMENT_PRIME)

__device__ static unsigned int reduce_product(unsigned long long product)
{
    const unsigned long long quotient = ((product >> 29u) * SHIFT_AGREEMENT_BARRETT) >> 33u;
    unsigned long long remainder = product - (quotient * (unsigned long long)SHIFT_AGREEMENT_PRIME);
    if (remainder >= (unsigned long long)SHIFT_AGREEMENT_PRIME)
    {
        remainder -= (unsigned long long)SHIFT_AGREEMENT_PRIME;
    }
    if (remainder >= (unsigned long long)SHIFT_AGREEMENT_PRIME)
    {
        remainder -= (unsigned long long)SHIFT_AGREEMENT_PRIME;
    }
    return (unsigned int)remainder;
}

__global__ void scatter_kernel(const unsigned long long *before, const unsigned long long *after, unsigned int reflect,
                               AgreementLayout layout, unsigned int *reflected, unsigned int *moved)
{
    const unsigned int position = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (position >= layout.voxels)
    {
        return;
    }
    const unsigned long long bit = 1ull << (position % 64u);
    const int in_before = (reflect != 0u) && ((before[position / 64u] & bit) != 0ull);
    const int in_after = (after[position / 64u] & bit) != 0ull;
    if ((in_before == 0) && (in_after == 0))
    {
        return;
    }
    unsigned int rest = position;
    unsigned int direct = 0u;
    unsigned int negated = 0u;
    for (unsigned int axis = layout.axes; axis > 0u; axis -= 1u)
    {
        const unsigned int coordinate = rest % layout.extents[axis - 1u];
        rest /= layout.extents[axis - 1u];
        direct += coordinate * layout.padded_strides[axis - 1u];
        negated +=
            ((layout.padded[axis - 1u] - coordinate) % layout.padded[axis - 1u]) * layout.padded_strides[axis - 1u];
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

__global__ void negate_kernel(const unsigned int *source, const unsigned int *negation, AgreementLayout layout,
                              unsigned int *destination)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= layout.total)
    {
        return;
    }
    unsigned int rest = element;
    unsigned int negated = 0u;
    for (unsigned int axis = layout.axes; axis > 0u; axis -= 1u)
    {
        const unsigned int coordinate = rest % layout.padded[axis - 1u];
        rest /= layout.padded[axis - 1u];
        negated += negation[layout.table_offsets[axis - 1u] + coordinate] * layout.padded_strides[axis - 1u];
    }
    destination[element] = source[negated];
}

__device__ static unsigned int agreement_add(unsigned int left, unsigned int right)
{
    const unsigned int sum = left + right;
    return (sum >= SHIFT_AGREEMENT_PRIME) ? (sum - SHIFT_AGREEMENT_PRIME) : sum;
}

__device__ static unsigned int agreement_subtract(unsigned int left, unsigned int right)
{
    const unsigned int difference = left + SHIFT_AGREEMENT_PRIME - right;
    return (difference >= SHIFT_AGREEMENT_PRIME) ? (difference - SHIFT_AGREEMENT_PRIME) : difference;
}

__device__ static unsigned int agreement_times(unsigned int left, unsigned int right)
{
    return reduce_product((unsigned long long)left * (unsigned long long)right);
}

__global__ void forward_kernel(unsigned int *values, const unsigned int *roots, unsigned int level, unsigned int levels,
                               unsigned int length, unsigned int stride, unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    const unsigned int position = (element / stride) % length;
    const unsigned int size = length >> level;
    const unsigned int part = size >> levels;
    if ((position & (size - 1u)) >= part)
    {
        return;
    }
    const unsigned int block = position / size;
    const unsigned int root = roots[(1u << level) + block];
    const unsigned int step = part * stride;
    if (levels == 1u)
    {
        const unsigned int upper = values[element];
        const unsigned int lower = agreement_times(values[element + step], root);
        values[element] = agreement_add(upper, lower);
        values[element + step] = agreement_subtract(upper, lower);
        return;
    }
    const unsigned int first = values[element];
    const unsigned int second = values[element + step];
    const unsigned int third_scaled = agreement_times(values[element + (2u * step)], root);
    const unsigned int fourth_scaled = agreement_times(values[element + (3u * step)], root);
    const unsigned int low_first = agreement_add(first, third_scaled);
    const unsigned int high_first = agreement_subtract(first, third_scaled);
    const unsigned int low_second = agreement_add(second, fourth_scaled);
    const unsigned int high_second = agreement_subtract(second, fourth_scaled);
    const unsigned int low_root = roots[(2u << level) + (2u * block)];
    const unsigned int high_root = roots[(2u << level) + (2u * block) + 1u];
    const unsigned int low_scaled = agreement_times(low_second, low_root);
    const unsigned int high_scaled = agreement_times(high_second, high_root);
    values[element] = agreement_add(low_first, low_scaled);
    values[element + step] = agreement_subtract(low_first, low_scaled);
    values[element + (2u * step)] = agreement_add(high_first, high_scaled);
    values[element + (3u * step)] = agreement_subtract(high_first, high_scaled);
}

__global__ void inverse_kernel(unsigned int *values, const unsigned int *inverse_roots, unsigned int level,
                               unsigned int levels, unsigned int length, unsigned int stride, unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    const unsigned int position = (element / stride) % length;
    const unsigned int size = length >> level;
    const unsigned int part = size >> levels;
    if ((position & (size - 1u)) >= part)
    {
        return;
    }
    const unsigned int block = position / size;
    const unsigned int inverse_root = inverse_roots[(1u << level) + block];
    const unsigned int step = part * stride;
    if (levels == 1u)
    {
        const unsigned int upper = values[element];
        const unsigned int lower = values[element + step];
        values[element] = agreement_add(upper, lower);
        values[element + step] = agreement_times(agreement_subtract(upper, lower), inverse_root);
        return;
    }
    const unsigned int first = values[element];
    const unsigned int second = values[element + step];
    const unsigned int third = values[element + (2u * step)];
    const unsigned int fourth = values[element + (3u * step)];
    const unsigned int low_inverse = inverse_roots[(2u << level) + (2u * block)];
    const unsigned int high_inverse = inverse_roots[(2u << level) + (2u * block) + 1u];
    const unsigned int low_first = agreement_add(first, second);
    const unsigned int low_second = agreement_times(agreement_subtract(first, second), low_inverse);
    const unsigned int high_first = agreement_add(third, fourth);
    const unsigned int high_second = agreement_times(agreement_subtract(third, fourth), high_inverse);
    values[element] = agreement_add(low_first, high_first);
    values[element + (2u * step)] = agreement_times(agreement_subtract(low_first, high_first), inverse_root);
    values[element + step] = agreement_add(low_second, high_second);
    values[element + (3u * step)] = agreement_times(agreement_subtract(low_second, high_second), inverse_root);
}

__global__ void multiply_kernel(unsigned int *values, const unsigned int *other, unsigned int factor,
                                unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    values[element] = agreement_times(agreement_times(values[element], other[element]), factor);
}

unsigned int device_agreement_power(unsigned int base, unsigned long long exponent)
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

int agreement_launched(void)
{
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

#define SHIFT_AGREEMENT_TABLES 8u

static AxisTables s_axis_tables[SHIFT_AGREEMENT_TABLES];

static unsigned int agreement_reverse(unsigned int position, unsigned int bits)
{
    unsigned int reversed = 0u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        reversed |= ((position >> bit) & 1u) << (bits - 1u - bit);
    }
    return reversed;
}

const AxisTables *axis_tables(unsigned int length)
{
    for (unsigned int slot = 0u; slot < SHIFT_AGREEMENT_TABLES; slot += 1u)
    {
        if (s_axis_tables[slot].length == length)
        {
            return &s_axis_tables[slot];
        }
    }
    unsigned int free_slot = SHIFT_AGREEMENT_TABLES;
    for (unsigned int slot = 0u; (slot < SHIFT_AGREEMENT_TABLES) && (free_slot == SHIFT_AGREEMENT_TABLES); slot += 1u)
    {
        free_slot = (s_axis_tables[slot].length == 0u) ? slot : free_slot;
    }
    if (free_slot == SHIFT_AGREEMENT_TABLES)
    {
        return NULL;
    }
    AxisTables *const tables = &s_axis_tables[free_slot];
    unsigned int logarithm = 0u;
    while ((1u << logarithm) < length)
    {
        logarithm += 1u;
    }
    unsigned int *const host = (unsigned int *)malloc((size_t)length * sizeof(unsigned int));
    tables->negation = (unsigned int *)malloc((size_t)length * sizeof(unsigned int));
    int ok = (host != NULL) && (tables->negation != NULL);
    ok = ok && (cudaMalloc((void **)&tables->roots[0], (size_t)length * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&tables->roots[1], (size_t)length * sizeof(unsigned int)) == cudaSuccess);
    for (unsigned int position = 0u; (ok != 0) && (position < length); position += 1u)
    {
        const unsigned int exponent = (length - agreement_reverse(position, logarithm)) % length;
        tables->negation[position] = agreement_reverse(exponent, logarithm);
    }
    const unsigned int generator = device_agreement_power(3u, (SHIFT_AGREEMENT_PRIME - 1u) / length);
    for (int inverse = 0; (ok != 0) && (inverse < 2); inverse += 1)
    {
        host[0] = 1u;
        for (unsigned int level = 0u; level < logarithm; level += 1u)
        {
            for (unsigned int block = 0u; block < (1u << level); block += 1u)
            {
                const unsigned long long exponent =
                    (unsigned long long)(length >> (level + 1u)) * (unsigned long long)agreement_reverse(block, level);
                const unsigned int root = device_agreement_power(generator, exponent);
                host[(1u << level) + block] =
                    (inverse != 0) ? device_agreement_power(root, SHIFT_AGREEMENT_PRIME - 2u) : root;
            }
        }
        ok = (cudaMemcpy(tables->roots[inverse], host, (size_t)length * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
              cudaSuccess)
                 ? 1
                 : 0;
    }
    free(host);
    if (ok == 0)
    {
        cudaFree(tables->roots[0]);
        cudaFree(tables->roots[1]);
        free(tables->negation);
        memset(tables, 0, sizeof(*tables));
        return NULL;
    }
    tables->length = length;
    return tables;
}
