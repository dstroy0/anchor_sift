// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "shift_agreement.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define SHIFT_AGREEMENT_BLOCK 256u

static_assert(sizeof(unsigned int) == 4u, "shift_agreement: unsigned int must be 32 bits, a residue");
static_assert(sizeof(unsigned long long) == 8u, "shift_agreement: unsigned long long must be 64 bits, a product");

struct AgreementLayout
{
    unsigned int axes;
    unsigned int extents[SHIFT_AGREEMENT_AXES];
    unsigned int padded[SHIFT_AGREEMENT_AXES];
    unsigned int padded_strides[SHIFT_AGREEMENT_AXES];
    unsigned int weights[SHIFT_AGREEMENT_AXES];
    unsigned int table_offsets[SHIFT_AGREEMENT_AXES];
    unsigned int voxels;
    unsigned int total;
};

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

__global__ static void choice_kernel(unsigned int total, unsigned int *choice)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    choice[element] = element;
}

__global__ static void tournament_kernel(const unsigned int *counts, unsigned int *choice, unsigned int stride,
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

static_assert(SHIFT_AGREEMENT_PRIME < (1u << 30u), "shift_agreement: Barrett reduction here needs the prime below 2^30");

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

__global__ static void scatter_kernel(const unsigned long long *before, const unsigned long long *after,
                                      unsigned int reflect, AgreementLayout layout, unsigned int *reflected,
                                      unsigned int *moved)
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
        negated += ((layout.padded[axis - 1u] - coordinate) % layout.padded[axis - 1u])
                 * layout.padded_strides[axis - 1u];
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

__global__ static void negate_kernel(const unsigned int *source, const unsigned int *negation, AgreementLayout layout,
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

__global__ static void forward_kernel(unsigned int *values, const unsigned int *roots, unsigned int level,
                                      unsigned int levels, unsigned int length, unsigned int stride,
                                      unsigned int total)
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

__global__ static void inverse_kernel(unsigned int *values, const unsigned int *inverse_roots, unsigned int level,
                                      unsigned int levels, unsigned int length, unsigned int stride,
                                      unsigned int total)
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

__global__ static void multiply_kernel(unsigned int *values, const unsigned int *other, unsigned int factor,
                                       unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    values[element] = agreement_times(agreement_times(values[element], other[element]), factor);
}

static unsigned int device_agreement_power(unsigned int base, unsigned long long exponent)
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

static int agreement_launched(void)
{
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

#define SHIFT_AGREEMENT_TABLES 8u

struct AxisTables
{
    unsigned int length;
    unsigned int *roots[2];
    unsigned int *negation;
};

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

static const AxisTables *axis_tables(unsigned int length)
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
                const unsigned long long exponent = (unsigned long long)(length >> (level + 1u))
                                                  * (unsigned long long)agreement_reverse(block, level);
                const unsigned int root = device_agreement_power(generator, exponent);
                host[(1u << level) + block] = (inverse != 0) ? device_agreement_power(root, SHIFT_AGREEMENT_PRIME - 2u) : root;
            }
        }
        ok = (cudaMemcpy(tables->roots[inverse], host, (size_t)length * sizeof(unsigned int), cudaMemcpyHostToDevice)
              == cudaSuccess) ? 1 : 0;
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

static int agreement_axis(unsigned int *values, AgreementLayout layout, unsigned int axis, int inverse)
{
    const unsigned int length = layout.padded[axis];
    if (length < 2u)
    {
        return 1;
    }
    const unsigned int stride = layout.padded_strides[axis];
    const unsigned int blocks = (layout.total + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    const AxisTables *const tables = axis_tables(length);
    int ok = (tables != NULL) ? 1 : 0;
    unsigned int logarithm = 0u;
    while ((1u << logarithm) < length)
    {
        logarithm += 1u;
    }
    if (inverse == 0)
    {
        for (unsigned int level = 0u; (ok != 0) && (level < logarithm); level += 2u)
        {
            const unsigned int levels = ((level + 1u) < logarithm) ? 2u : 1u;
            forward_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(values, tables->roots[0], level, levels, length, stride,
                                                              layout.total);
            ok = agreement_launched();
        }
        return ok;
    }
    unsigned int remaining = logarithm;
    while ((ok != 0) && (remaining > 0u))
    {
        const unsigned int levels = (((remaining % 2u) == 1u) && (remaining == logarithm)) ? 1u : 2u;
        const unsigned int level = remaining - levels;
        inverse_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(values, tables->roots[1], level, levels, length, stride,
                                                          layout.total);
        ok = agreement_launched();
        remaining = level;
    }
    return ok;
}

#define SHIFT_AGREEMENT_VOLUMES 4u

#define SHIFT_AGREEMENT_NONE_KEPT SHIFT_AGREEMENT_VOLUMES

struct HeldVolumes
{
    size_t total;
    size_t words;
    unsigned long long *before;
    unsigned long long *after;
    unsigned int *volumes[SHIFT_AGREEMENT_VOLUMES];
    unsigned int kept;
    unsigned long long *kept_words;
};

static HeldVolumes s_held_volumes;

static int hold_volumes(size_t total, size_t words)
{
    HeldVolumes *const held = &s_held_volumes;
    if ((held->total == total) && (held->words == words) && (total != 0u))
    {
        return 1;
    }
    cudaFree(held->before);
    cudaFree(held->after);
    for (unsigned int slot = 0u; slot < SHIFT_AGREEMENT_VOLUMES; slot += 1u)
    {
        cudaFree(held->volumes[slot]);
    }
    free(held->kept_words);
    memset(held, 0, sizeof(*held));
    held->kept = SHIFT_AGREEMENT_NONE_KEPT;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&held->before, words * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&held->after, words * sizeof(unsigned long long)) == cudaSuccess);
    for (unsigned int slot = 0u; (ok != 0) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        ok = (cudaMalloc((void **)&held->volumes[slot], total * sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
    }
    held->kept_words = (unsigned long long *)malloc(words * sizeof(unsigned long long));
    ok = ok && (held->kept_words != NULL);
    if (ok == 0)
    {
        cudaFree(held->before);
        cudaFree(held->after);
        for (unsigned int slot = 0u; slot < SHIFT_AGREEMENT_VOLUMES; slot += 1u)
        {
            cudaFree(held->volumes[slot]);
        }
        free(held->kept_words);
        memset(held, 0, sizeof(*held));
        held->kept = SHIFT_AGREEMENT_NONE_KEPT;
        return 0;
    }
    held->total = total;
    held->words = words;
    return 1;
}

struct HeldNegation
{
    unsigned int axes;
    unsigned int padded[SHIFT_AGREEMENT_AXES];
    unsigned int *negation;
};

static HeldNegation s_held_negation;

static int hold_negation(const AgreementLayout *layout)
{
    HeldNegation *const held = &s_held_negation;
    if ((held->negation != NULL) && (held->axes == layout->axes)
     && (memcmp(held->padded, layout->padded, sizeof(held->padded)) == 0))
    {
        return 1;
    }
    s_held_volumes.kept = SHIFT_AGREEMENT_NONE_KEPT;
    cudaFree(held->negation);
    memset(held, 0, sizeof(*held));
    size_t entries = 0u;
    for (unsigned int axis = 0u; axis < layout->axes; axis += 1u)
    {
        entries += (size_t)layout->padded[axis];
    }
    unsigned int *const host = (unsigned int *)malloc((entries + 1u) * sizeof(unsigned int));
    int ok = (host != NULL) ? 1 : 0;
    for (unsigned int axis = 0u; (ok != 0) && (axis < layout->axes); axis += 1u)
    {
        if (layout->padded[axis] < 2u)
        {
            host[layout->table_offsets[axis]] = 0u;
            continue;
        }
        const AxisTables *const tables = axis_tables(layout->padded[axis]);
        ok = (tables != NULL) ? 1 : 0;
        if (ok != 0)
        {
            memcpy(&host[layout->table_offsets[axis]], tables->negation, (size_t)layout->padded[axis] * sizeof(unsigned int));
        }
    }
    ok = ok && (cudaMalloc((void **)&held->negation, (entries + 1u) * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemcpy(held->negation, host, entries * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    free(host);
    if (ok == 0)
    {
        cudaFree(held->negation);
        memset(held, 0, sizeof(*held));
        return 0;
    }
    held->axes = layout->axes;
    memcpy(held->padded, layout->padded, sizeof(held->padded));
    return 1;
}

extern "C" long shift_agreement_run(ShiftAgreementRequest *args)
{
    if ((args == NULL) || (args->before == NULL) || (args->after == NULL) || (args->axes == 0u)
     || (args->axes > SHIFT_AGREEMENT_AXES))
    {
        return SHIFT_AGREEMENT_REFUSED;
    }
    AgreementLayout layout;
    memset(&layout, 0, sizeof(layout));
    layout.axes = args->axes;
    unsigned long long voxels = 1ull;
    unsigned long long padded_total = 1ull;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        if ((args->extents[axis] == 0u) || (args->extents[axis] > (SHIFT_AGREEMENT_LONGEST_AXIS / 2u)))
        {
            return SHIFT_AGREEMENT_REFUSED;
        }
        layout.extents[axis] = args->extents[axis];
        layout.weights[axis] = args->weights[axis];
        voxels *= (unsigned long long)args->extents[axis];
        unsigned long long power = 1ull;
        while (power < ((2ull * (unsigned long long)args->extents[axis]) - 1ull))
        {
            power <<= 1u;
        }
        layout.padded[axis] = (unsigned int)power;
        padded_total *= power;
        if ((voxels >= (unsigned long long)SHIFT_AGREEMENT_PRIME) || (padded_total > 0x7FFFFFFFull))
        {
            return SHIFT_AGREEMENT_REFUSED;
        }
    }
    layout.voxels = (unsigned int)voxels;
    layout.total = (unsigned int)padded_total;
    unsigned int stride = layout.total;
    unsigned int table_offset = 0u;
    for (unsigned int axis = 0u; axis < layout.axes; axis += 1u)
    {
        stride /= layout.padded[axis];
        layout.padded_strides[axis] = stride;
        layout.table_offsets[axis] = table_offset;
        table_offset += layout.padded[axis];
    }
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return SHIFT_AGREEMENT_REFUSED;
    }

    const size_t total = (size_t)layout.total;
    const size_t words = ((size_t)layout.voxels + 63u) / 64u;
    unsigned int *const host_counts = (args->counts != NULL) ? (unsigned int *)malloc(total * sizeof(unsigned int)) : NULL;
    int ok = ((args->counts == NULL) || (host_counts != NULL)) ? 1 : 0;
    ok = ok && hold_volumes(total, words);
    ok = ok && hold_negation(&layout);
    HeldVolumes *const held = &s_held_volumes;
    unsigned long long *const device_before = held->before;
    unsigned long long *const device_after = held->after;
    const int reuse = (ok != 0) && (held->kept != SHIFT_AGREEMENT_NONE_KEPT)
                   && (memcmp(held->kept_words, args->before, words * sizeof(unsigned long long)) == 0);
    unsigned int *roles[SHIFT_AGREEMENT_VOLUMES - 1u] = {NULL, NULL, NULL};
    unsigned int filled = 0u;
    for (unsigned int slot = 0u; (ok != 0) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        if (((reuse != 0) && (slot == held->kept)) || (filled == (SHIFT_AGREEMENT_VOLUMES - 1u)))
        {
            continue;
        }
        roles[filled] = held->volumes[slot];
        filled += 1u;
    }
    unsigned int *reflected = roles[0];
    unsigned int *moved = roles[1];
    unsigned int *spare = roles[2];
    const unsigned int blocks = (layout.total + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    ok = ok && ((reuse != 0) || (cudaMemcpy(device_before, args->before, words * sizeof(unsigned long long),
                                            cudaMemcpyHostToDevice) == cudaSuccess));
    ok = ok && (cudaMemcpy(device_after, args->after, words * sizeof(unsigned long long), cudaMemcpyHostToDevice)
                == cudaSuccess);
    ok = ok && ((reuse != 0) || (cudaMemset(reflected, 0, total * sizeof(unsigned int)) == cudaSuccess));
    ok = ok && (cudaMemset(moved, 0, total * sizeof(unsigned int)) == cudaSuccess);
    const unsigned int voxel_blocks = (layout.voxels + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    if (ok != 0)
    {
        scatter_kernel<<<voxel_blocks, SHIFT_AGREEMENT_BLOCK>>>(device_before, device_after, (reuse != 0) ? 0u : 1u,
                                                                layout, reflected, moved);
        ok = agreement_launched();
    }
    if ((ok != 0) && (reuse != 0))
    {
        negate_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(held->volumes[held->kept], s_held_negation.negation, layout,
                                                         reflected);
        ok = agreement_launched();
    }

    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = (reuse != 0) || (agreement_axis(reflected, layout, axis, 0) != 0);
        ok = ok && agreement_axis(moved, layout, axis, 0);
    }
    if (ok != 0)
    {
        multiply_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(reflected, moved,
                                                          device_agreement_power(layout.total, SHIFT_AGREEMENT_PRIME - 2u),
                                                          layout.total);
        ok = agreement_launched();
    }
    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = agreement_axis(reflected, layout, axis, 1);
    }
    if ((ok != 0) && (host_counts != NULL))
    {
        ok = (cudaMemcpy(host_counts, reflected, total * sizeof(unsigned int), cudaMemcpyDeviceToHost)
              == cudaSuccess) ? 1 : 0;
    }

    if (ok != 0)
    {
        choice_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(layout.total, spare);
        ok = agreement_launched();
    }
    for (unsigned int stride = 1u; (stride < layout.total) && (ok != 0); stride <<= 1u)
    {
        const unsigned int pairs = (layout.total + (2u * stride) - 1u) / (2u * stride);
        const unsigned int pair_blocks = (pairs + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
        tournament_kernel<<<pair_blocks, SHIFT_AGREEMENT_BLOCK>>>(reflected, spare, stride, pairs, layout);
        ok = agreement_launched();
    }
    unsigned int winner = 0u;
    unsigned int winner_count = 0u;
    ok = ok && (cudaMemcpy(&winner, spare, sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(&winner_count, &reflected[winner], sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);

    long answer = SHIFT_AGREEMENT_REFUSED;
    if (ok != 0)
    {
        const size_t best = (size_t)winner;
        size_t rest = best;
        for (unsigned int axis = layout.axes; axis > 0u; axis -= 1u)
        {
            const long long coordinate = (long long)(rest % layout.padded[axis - 1u]);
            rest /= layout.padded[axis - 1u];
            args->lag[axis - 1u] = (int)((coordinate < (long long)(layout.padded[axis - 1u] / 2u))
                                         ? coordinate
                                         : (coordinate - (long long)layout.padded[axis - 1u]));
        }
        for (unsigned int axis = 0u; axis < SHIFT_AGREEMENT_AXES; axis += 1u)
        {
            args->padded[axis] = (axis < layout.axes) ? layout.padded[axis] : 0u;
            if (axis >= layout.axes)
            {
                args->lag[axis] = 0;
            }
        }
        args->agreement = winner_count;
        if (args->counts != NULL)
        {
            memcpy(args->counts, host_counts, total * sizeof(unsigned int));
        }
        answer = 0L;
    }
    held->kept = SHIFT_AGREEMENT_NONE_KEPT;
    for (unsigned int slot = 0u; (answer == 0L) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        if (held->volumes[slot] == moved)
        {
            held->kept = slot;
            memcpy(held->kept_words, args->after, words * sizeof(unsigned long long));
        }
    }
    free(host_counts);
    return answer;
}
