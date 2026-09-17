/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file shift_agreement.cu
 * @brief The CUDA engine for shift_agreement.h: integers only, equal to shift_agreement.c.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * One thread per element for every stage of every transform. A bit reversal gathers from one buffer
 * into another. A butterfly stage touches disjoint pairs, each owned by the thread of its nearer
 * element, so no two threads write one element. The lag with the most agreement is chosen on the
 * device by a tournament under the same total order the reference applies, so only the winner comes
 * back to the host, and every count only where the caller asks.
 *
 * Along a series each frame is after in one call and before in the next. The moved view's transform is
 * kept, and where the next call's before is the kept after, the reflected transform is gathered from it
 * through negated indices, so every frame is transformed once.
 */

#include "shift_agreement.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define SHIFT_AGREEMENT_BLOCK 256u

static_assert(sizeof(unsigned int) == 4u, "shift_agreement: unsigned int must be 32 bits, a residue");
static_assert(sizeof(unsigned long long) == 8u, "shift_agreement: unsigned long long must be 64 bits, a product");

/** @brief The layout a kernel reads, passed by value. */
struct AgreementLayout
{
    unsigned int axes;
    unsigned int extents[SHIFT_AGREEMENT_AXES];
    unsigned int padded[SHIFT_AGREEMENT_AXES];
    unsigned int padded_strides[SHIFT_AGREEMENT_AXES];
    unsigned int weights[SHIFT_AGREEMENT_AXES];
    unsigned int voxels;
    unsigned int total;
};

/**
 * @brief The weighted squared length of the lag a padded index stands for, as the reference measures it.
 *
 * @param[in] index  Padded raster index.
 * @param[in] layout Extents, padding and weights.
 * @return           Sum over axes of weight times lag squared.
 */
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

/**
 * @brief Starts the choice: every padded index is its own candidate.
 *
 * @param[in]  total  Elements.
 * @param[out] choice Candidate per element [BORROWS].
 */
__global__ static void choice_kernel(unsigned int total, unsigned int *choice)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    choice[element] = element;
}

/**
 * @brief One round of the tournament for the heaviest lag: the candidate at pair * 2 * stride meets the
 *        one stride further, and the better stays.
 *
 * Better is more agreement, then the shorter weighted lag, then the lower padded index. That is a total
 * order, so the tournament's winner is the reference's choice however the pairs are drawn.
 *
 * @param[in]     counts Agreement per padded index [BORROWS].
 * @param[in,out] choice Candidate per element [BORROWS].
 * @param[in]     stride Distance between the two candidates of a pair.
 * @param[in]     pairs  Pairs this round.
 * @param[in]     layout Extents, padding and weights.
 */
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

/** @brief floor(2^62 / SHIFT_AGREEMENT_PRIME), the Barrett multiplier. */
#define SHIFT_AGREEMENT_BARRETT (4611686018427387904ull / (unsigned long long)SHIFT_AGREEMENT_PRIME)

static_assert(SHIFT_AGREEMENT_PRIME < (1u << 30u), "shift_agreement: Barrett reduction here needs the prime below 2^30");

/**
 * @brief product mod SHIFT_AGREEMENT_PRIME for a product below 2^60, by Barrett reduction.
 *
 * With m = floor(2^62 / p), q = floor(floor(x / 2^29) * m / 2^33) lies within two of floor(x / p) and
 * never above it, and floor(x / 2^29) * m stays below 2^64. So x - q p lies in [0, 3p), and at most two
 * subtractions of p leave exactly x mod p. Integers only; the residue is the one % gives.
 *
 * @param[in] product A product of two residues, below 2^60.
 * @return            The product modulo the prime.
 */
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
    // Narrowing is safe: the remainder is below the prime.
    return (unsigned int)remainder;
}

/**
 * @brief Places each set position of the views into the reflected and the moved volumes.
 *
 * @param[in]  before    Bit packed view before [BORROWS].
 * @param[in]  after     Bit packed view after [BORROWS].
 * @param[in]  reflect   1 to place before into reflected, 0 where reflected comes from a held transform.
 * @param[in]  layout    Extents and strides.
 * @param[out] reflected Before, reflected into the period [BORROWS].
 * @param[out] moved     After, in place [BORROWS].
 */
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

/**
 * @brief The transform of a view reflected through the origin, from the transform of the view in place.
 *
 * The transform's element k is the view's polynomial at w^k, summed over positions n of v[n] w^(k n) per
 * axis. The reflected view is r[n] = v[-n mod N], so its element k is the sum of v[m] w^(-k m): the view's
 * element -k mod N. The reflected transform is a gather through negated indices, and no transform is run.
 *
 * @param[in]  source      The transform of the view in place [BORROWS].
 * @param[in]  layout      Padding and strides.
 * @param[out] destination The transform of the reflected view [BORROWS].
 */
__global__ static void negate_kernel(const unsigned int *source, AgreementLayout layout, unsigned int *destination)
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
        negated += ((layout.padded[axis - 1u] - coordinate) % layout.padded[axis - 1u]) * layout.padded_strides[axis - 1u];
    }
    destination[element] = source[negated];
}

/**
 * @brief Gathers every line along an axis into bit reversed order.
 *
 * @param[in]  source      Volume read [BORROWS].
 * @param[in]  reversal    Bit reversed position for each position along the axis [BORROWS].
 * @param[in]  length      Padded extent of the axis.
 * @param[in]  stride      Elements between neighbours along the axis.
 * @param[in]  total       Elements in the volume.
 * @param[out] destination Volume written [BORROWS].
 */
__global__ static void reverse_kernel(const unsigned int *source, const unsigned int *reversal,
                                      unsigned int length, unsigned int stride, unsigned int total,
                                      unsigned int *destination)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    const unsigned int position = (element / stride) % length;
    const unsigned int base = element - (position * stride);
    destination[element] = source[base + (reversal[position] * stride)];
}

/**
 * @brief One butterfly stage of size `size` along an axis.
 *
 * @param[in,out] values Volume [BORROWS].
 * @param[in]     roots  Powers of the stage's root, size / 2 of them [BORROWS].
 * @param[in]     size   Stage size, a power of two no larger than length.
 * @param[in]     length Padded extent of the axis.
 * @param[in]     stride Elements between neighbours along the axis.
 * @param[in]     total  Elements in the volume.
 */
__global__ static void butterfly_kernel(unsigned int *values, const unsigned int *roots, unsigned int size,
                                        unsigned int length, unsigned int stride, unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    const unsigned int position = (element / stride) % length;
    const unsigned int within = position % size;
    const unsigned int half = size / 2u;
    if (within >= half)
    {
        return;
    }
    const unsigned int far = element + (half * stride);
    const unsigned int upper = values[element];
    // Both residues are below 2^30, so their product is below 2^60.
    const unsigned int lower = reduce_product((unsigned long long)values[far] * (unsigned long long)roots[within]);
    // Both are below the prime, so one subtraction reduces each sum; below 2^31, neither wraps.
    const unsigned int sum = upper + lower;
    const unsigned int difference = upper + SHIFT_AGREEMENT_PRIME - lower;
    values[element] = (sum >= SHIFT_AGREEMENT_PRIME) ? (sum - SHIFT_AGREEMENT_PRIME) : sum;
    values[far] = (difference >= SHIFT_AGREEMENT_PRIME) ? (difference - SHIFT_AGREEMENT_PRIME) : difference;
}

/**
 * @brief Multiplies every element by a factor, or by the matching element of another volume.
 *
 * @param[in,out] values Volume [BORROWS].
 * @param[in]     other  Second volume, or NULL to use `factor` [BORROWS].
 * @param[in]     factor Factor where `other` is NULL.
 * @param[in]     total  Elements.
 */
__global__ static void multiply_kernel(unsigned int *values, const unsigned int *other, unsigned int factor,
                                       unsigned int total)
{
    const unsigned int element = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (element >= total)
    {
        return;
    }
    const unsigned long long by = (other != NULL) ? (unsigned long long)other[element] : (unsigned long long)factor;
    // Both residues are below 2^30, so their product is below 2^60.
    values[element] = reduce_product((unsigned long long)values[element] * by);
}

/**
 * @brief base^exponent modulo the prime, on the host.
 *
 * @param[in] base     Base, below the prime.
 * @param[in] exponent Exponent.
 * @return             The power.
 */
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
    // Narrowing is safe: every value is reduced below the prime.
    return (unsigned int)result;
}

/**
 * @brief Whether the kernel just launched ran without a device error.
 *
 * @return 1 where it did, 0 otherwise.
 */
static int agreement_launched(void)
{
    // No synchronise: kernels queue in order and the host's reads wait for them, so a launch only has to be accepted.
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

/** @brief Most distinct padded axis lengths whose tables are held. */
#define SHIFT_AGREEMENT_TABLES 8u

/**
 * @brief The tables one padded axis length needs, uploaded once: the bit reversal, and every butterfly stage's
 *        root powers, forward and inverse, laid end to end so stage size s starts at s / 2 - 1.
 */
struct AxisTables
{
    unsigned int length;
    unsigned int *reversal;
    unsigned int *roots[2];
};

static AxisTables s_axis_tables[SHIFT_AGREEMENT_TABLES];

/**
 * @brief The held tables for a padded length, built and uploaded the first time the length is seen.
 *
 * @param[in] length A padded axis length, a power of two.
 * @return           The tables, or NULL on a failure.
 */
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
    int ok = (host != NULL) ? 1 : 0;
    ok = ok && (cudaMalloc((void **)&tables->reversal, (size_t)length * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&tables->roots[0], (size_t)length * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&tables->roots[1], (size_t)length * sizeof(unsigned int)) == cudaSuccess);
    if (ok != 0)
    {
        for (unsigned int position = 0u; position < length; position += 1u)
        {
            unsigned int reversed = 0u;
            for (unsigned int bit = 0u; bit < logarithm; bit += 1u)
            {
                reversed |= ((position >> bit) & 1u) << (logarithm - 1u - bit);
            }
            host[position] = reversed;
        }
        ok = (cudaMemcpy(tables->reversal, host, (size_t)length * sizeof(unsigned int), cudaMemcpyHostToDevice)
              == cudaSuccess) ? 1 : 0;
    }
    for (int inverse = 0; (ok != 0) && (inverse < 2); inverse += 1)
    {
        for (unsigned int size = 2u; size <= length; size <<= 1u)
        {
            unsigned int root = device_agreement_power(3u, (SHIFT_AGREEMENT_PRIME - 1u) / size);
            if (inverse != 0)
            {
                root = device_agreement_power(root, SHIFT_AGREEMENT_PRIME - 2u);
            }
            unsigned long long factor = 1ull;
            for (unsigned int offset = 0u; offset < (size / 2u); offset += 1u)
            {
                // Narrowing is safe: factor is reduced below the prime.
                host[(size / 2u) - 1u + offset] = (unsigned int)factor;
                factor = (factor * (unsigned long long)root) % SHIFT_AGREEMENT_PRIME;
            }
        }
        ok = (cudaMemcpy(tables->roots[inverse], host, (size_t)(length - 1u) * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess) ? 1 : 0;
    }
    free(host);
    if (ok == 0)
    {
        cudaFree(tables->reversal);
        cudaFree(tables->roots[0]);
        cudaFree(tables->roots[1]);
        memset(tables, 0, sizeof(*tables));
        return NULL;
    }
    tables->length = length;
    return tables;
}

/**
 * @brief One transform along one axis on the device.
 *
 * @param[in,out] values   Volume [BORROWS].
 * @param[in,out] spare    A second volume for the reversal [BORROWS].
 * @param[in]     layout   Layout.
 * @param[in]     axis     The axis.
 * @param[in]     inverse  1 for the inverse transform.
 * @return                 1 on success, 0 on a device error.
 * @note On return the transformed volume is in *values; the two buffers may have traded places.
 */
static int agreement_axis(unsigned int **values, unsigned int **spare, AgreementLayout layout, unsigned int axis,
                          int inverse)
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
    if (ok != 0)
    {
        reverse_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(*values, tables->reversal, length, stride, layout.total, *spare);
        ok = agreement_launched();
        unsigned int *const swapped = *values;
        *values = *spare;
        *spare = swapped;
    }
    for (unsigned int size = 2u; (size <= length) && (ok != 0); size <<= 1u)
    {
        // Stage size s reads its root powers where the held table laid them, from s / 2 - 1.
        const unsigned int *const roots = &tables->roots[(inverse != 0) ? 1 : 0][(size / 2u) - 1u];
        butterfly_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(*values, roots, size, length, stride, layout.total);
        ok = agreement_launched();
    }
    if ((ok != 0) && (inverse != 0))
    {
        multiply_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(*values, NULL,
                                                          device_agreement_power(length, SHIFT_AGREEMENT_PRIME - 2u),
                                                          layout.total);
        ok = agreement_launched();
    }
    return ok;
}

/** @brief Volumes held: the reflected, the moved, a spare, and the transform kept from the call before. */
#define SHIFT_AGREEMENT_VOLUMES 4u

/** @brief No transform is kept. */
#define SHIFT_AGREEMENT_NONE_KEPT SHIFT_AGREEMENT_VOLUMES

/**
 * @brief The volumes one extent needs, held between calls, and the moved view's transform from the last call
 *        with the sign words it was made from: a series calls with this call's after as the next call's before,
 *        and that before's reflected transform is a gather of the kept one.
 */
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

/**
 * @brief Holds the device volumes for a padded total and a word count, allocating only when either changes.
 *
 * @param[in] total Padded elements.
 * @param[in] words Sign words of the view.
 * @return          1 with the volumes held, 0 on a failure with nothing held.
 */
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
        // Narrowing is safe: power is at most SHIFT_AGREEMENT_LONGEST_AXIS.
        layout.padded[axis] = (unsigned int)power;
        padded_total *= power;
        if ((voxels >= (unsigned long long)SHIFT_AGREEMENT_PRIME) || (padded_total > 0x7FFFFFFFull))
        {
            return SHIFT_AGREEMENT_REFUSED;
        }
    }
    // Narrowing is safe: both totals were just bounded below 2^31.
    layout.voxels = (unsigned int)voxels;
    layout.total = (unsigned int)padded_total;
    unsigned int stride = layout.total;
    for (unsigned int axis = 0u; axis < layout.axes; axis += 1u)
    {
        stride /= layout.padded[axis];
        layout.padded_strides[axis] = stride;
    }
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return SHIFT_AGREEMENT_REFUSED;
    }

    const size_t total = (size_t)layout.total;
    const size_t words = ((size_t)layout.voxels + 63u) / 64u;
    // Every count comes to the host only where the caller asked for them.
    unsigned int *const host_counts = (args->counts != NULL) ? (unsigned int *)malloc(total * sizeof(unsigned int)) : NULL;
    int ok = ((args->counts == NULL) || (host_counts != NULL)) ? 1 : 0;
    ok = ok && hold_volumes(total, words);
    HeldVolumes *const held = &s_held_volumes;
    unsigned long long *const device_before = held->before;
    unsigned long long *const device_after = held->after;
    // Where this call's before is the last call's after, its transform is kept and the reflected transform is
    // gathered from it; the three other volumes are the reflected, the moved and the spare.
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
        negate_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(held->volumes[held->kept], layout, reflected);
        ok = agreement_launched();
    }

    // The spare takes part in every reversal, trading places with the volume reversed.
    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = (reuse != 0) || (agreement_axis(&reflected, &spare, layout, axis, 0) != 0);
        ok = ok && agreement_axis(&moved, &spare, layout, axis, 0);
    }
    if (ok != 0)
    {
        multiply_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(reflected, moved, 0u, layout.total);
        ok = agreement_launched();
    }
    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = agreement_axis(&reflected, &spare, layout, axis, 1);
    }
    if ((ok != 0) && (host_counts != NULL))
    {
        ok = (cudaMemcpy(host_counts, reflected, total * sizeof(unsigned int), cudaMemcpyDeviceToHost)
              == cudaSuccess) ? 1 : 0;
    }

    // The heaviest lag, then the shortest weighted lag, then the lowest padded index, as the reference
    // chooses, found on the device by a tournament; only the winner and its count come back. `spare`
    // holds the candidates.
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
            // Narrowing is safe: a lag lies within half a padded extent.
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
    // The moved transform is kept for the next call, whose before this call's after may be; the multiply and
    // the inverse wrote only the reflected and the spare, so it is whole.
    held->kept = SHIFT_AGREEMENT_NONE_KEPT;
    for (unsigned int slot = 0u; (answer == 0L) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        if (held->volumes[slot] == moved)
        {
            held->kept = slot;
            memcpy(held->kept_words, args->after, words * sizeof(unsigned long long));
        }
    }
    // The volumes stay held for the next call of the same extents.
    free(host_counts);
    return answer;
}
