#include "binomial_transform.h"
#include "transform_constants.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define TRANSFORM_LINE_ROOM 256u

#define TRANSFORM_SLOT_ROOM 320u

#define TRANSFORM_BLOCK 256u

static_assert(sizeof(unsigned int) == 4u, "binomial_transform: unsigned int must be 32 bits, a residue");
static_assert(sizeof(unsigned long long) == 8u, "binomial_transform: unsigned long long must be 64 bits, a product");
static_assert((TRANSFORM_ROOT_ORDER % (4u * TRANSFORM_LINE_ROOM)) == 0u,
              "binomial_transform: psi must carry a root of order 4N for the longest axis");

#define TRANSFORM_AT_PRIMES 0u
#define TRANSFORM_AT_BARRETT_LOW (TRANSFORM_AT_PRIMES + TRANSFORM_PRIMES)
#define TRANSFORM_AT_BARRETT_HIGH (TRANSFORM_AT_BARRETT_LOW + TRANSFORM_PRIMES)
#define TRANSFORM_AT_IMAGINARY (TRANSFORM_AT_BARRETT_HIGH + TRANSFORM_PRIMES)
#define TRANSFORM_AT_TWO_GAIN (TRANSFORM_AT_IMAGINARY + (3u * TRANSFORM_PRIMES))
#define TRANSFORM_AT_FOLD (TRANSFORM_AT_TWO_GAIN + TRANSFORM_PRIMES)
#define TRANSFORM_AT_COEFFICIENT (TRANSFORM_AT_FOLD + TRANSFORM_PRIMES)
#define TRANSFORM_AT_INVERSE (TRANSFORM_AT_COEFFICIENT + (TRANSFORM_PRIMES * TRANSFORM_PRIMES))
#define TRANSFORM_AT_HALF (TRANSFORM_AT_INVERSE + TRANSFORM_PRIMES)
#define TRANSFORM_AT_MODULUS (TRANSFORM_AT_HALF + TRANSFORM_PRIMES)
#define TRANSFORM_CONSTANT_ROOM (TRANSFORM_AT_MODULUS + BINOMIAL_BASINS_LIMBS)

static_assert((TRANSFORM_CONSTANT_ROOM * 4u) <= 65536u, "binomial_transform: the constant block must fit constant memory");

#define TRANSFORM_AT_ROOTS 0ull
#define TRANSFORM_AT_INVERSE_ROOTS (TRANSFORM_AT_ROOTS + (1ull * TRANSFORM_SLOT_ROOM * TRANSFORM_PRIMES))
#define TRANSFORM_AT_PSI (TRANSFORM_AT_INVERSE_ROOTS + (1ull * TRANSFORM_SLOT_ROOM * TRANSFORM_PRIMES))
#define TRANSFORM_AT_PSI_INVERSE (TRANSFORM_AT_PSI + (1ull * TRANSFORM_SLOT_ROOM * TRANSFORM_PRIMES))
#define TRANSFORM_AT_PARTNER (TRANSFORM_AT_PSI_INVERSE + (1ull * TRANSFORM_SLOT_ROOM * TRANSFORM_PRIMES))
#define TRANSFORM_AT_REVERSED (TRANSFORM_AT_PARTNER + TRANSFORM_SLOT_ROOM)
#define TRANSFORM_AT_ORDER (TRANSFORM_AT_REVERSED + TRANSFORM_SLOT_ROOM)
#define TRANSFORM_AT_PLACE (TRANSFORM_AT_ORDER + TRANSFORM_SLOT_ROOM)
#define TRANSFORM_AT_SMOOTH (TRANSFORM_AT_PLACE + TRANSFORM_SLOT_ROOM)
#define TRANSFORM_AT_BACKGROUND (TRANSFORM_AT_SMOOTH + (3ull * TRANSFORM_LINE_ROOM * TRANSFORM_PRIMES))
#define TRANSFORM_AT_WORK (TRANSFORM_AT_BACKGROUND + (3ull * TRANSFORM_LINE_ROOM * TRANSFORM_PRIMES))

__constant__ unsigned int s_transform[TRANSFORM_CONSTANT_ROOM];

struct TransformSeeds
{
    unsigned int primes[TRANSFORM_PRIMES];
    unsigned int barrett_low[TRANSFORM_PRIMES];
    unsigned int barrett_high[TRANSFORM_PRIMES];
    unsigned int psi[TRANSFORM_PRIMES];
    unsigned int coefficient[TRANSFORM_PRIMES * TRANSFORM_PRIMES];
    unsigned int inverse[TRANSFORM_PRIMES];
    unsigned int half[TRANSFORM_PRIMES];
    unsigned int modulus[BINOMIAL_BASINS_LIMBS];
};

struct TransformLayout
{
    unsigned int extents[3];
    unsigned int logarithms[3];
    unsigned int slot_offsets[3];
    unsigned int stride_shifts[3];
    unsigned int total;
    unsigned int shift_z;
    unsigned int shift_y;
    unsigned int mask_y;
    unsigned int mask_x;
};

struct AxisLines
{
    unsigned int axis;
    unsigned int length_log;
    unsigned int low_log;
    unsigned int slot_offset;
};

__forceinline__ __device__ static unsigned int field_reduce(unsigned long long product, unsigned int prime)
{
    const unsigned long long modulus = (unsigned long long)s_transform[TRANSFORM_AT_PRIMES + prime];
    const unsigned long long barrett = ((unsigned long long)s_transform[TRANSFORM_AT_BARRETT_HIGH + prime] << 32u)
                                     | (unsigned long long)s_transform[TRANSFORM_AT_BARRETT_LOW + prime];
    const unsigned long long quotient = ((product >> 29u) * barrett) >> 33u;
    unsigned long long remainder = product - (quotient * modulus);
    remainder -= (remainder >= modulus) ? modulus : 0ull;
    remainder -= (remainder >= modulus) ? modulus : 0ull;

    return (unsigned int)remainder;
}

__forceinline__ __device__ static unsigned int field_add(unsigned int left, unsigned int right, unsigned int prime)
{

    const unsigned int modulus = s_transform[TRANSFORM_AT_PRIMES + prime];
    const unsigned int sum = left + right;
    return sum - ((sum >= modulus) ? modulus : 0u);
}

__forceinline__ __device__ static unsigned int field_subtract(unsigned int left, unsigned int right, unsigned int prime)
{

    const unsigned int modulus = s_transform[TRANSFORM_AT_PRIMES + prime];
    const unsigned int difference = left + modulus - right;
    return difference - ((difference >= modulus) ? modulus : 0u);
}

__forceinline__ __device__ static unsigned int field_times(unsigned int left, unsigned int right, unsigned int prime)
{

    return field_reduce((unsigned long long)left * (unsigned long long)right, prime);
}

__forceinline__ __device__ static unsigned int field_power(unsigned int base, unsigned int exponent, unsigned int prime)
{
    unsigned int result = 1u;
    unsigned int square = base;
    for (unsigned int rest = exponent; rest != 0u; rest >>= 1u)
    {
        result = ((rest & 1u) != 0u) ? field_times(result, square, prime) : result;
        square = field_times(square, square, prime);
    }
    return result;
}

__forceinline__ __device__ static unsigned int bits_reversed(unsigned int position, unsigned int bits)
{
    unsigned int reversed = 0u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        reversed |= ((position >> bit) & 1u) << (bits - 1u - bit);
    }
    return reversed;
}

__global__ static void seed_kernel(unsigned int *location, TransformSeeds seeds)
{
    const unsigned int prime = threadIdx.x;
    location[TRANSFORM_AT_PRIMES + prime] = seeds.primes[prime];
    location[TRANSFORM_AT_BARRETT_LOW + prime] = seeds.barrett_low[prime];
    location[TRANSFORM_AT_BARRETT_HIGH + prime] = seeds.barrett_high[prime];
    location[TRANSFORM_AT_INVERSE + prime] = seeds.inverse[prime];
    location[TRANSFORM_AT_HALF + prime] = seeds.half[prime];
    for (unsigned int digit = 0u; digit < TRANSFORM_PRIMES; digit += 1u)
    {
        location[TRANSFORM_AT_COEFFICIENT + (prime * TRANSFORM_PRIMES) + digit] = seeds.coefficient[(prime * TRANSFORM_PRIMES) + digit];
    }
    if (prime < BINOMIAL_BASINS_LIMBS)
    {
        location[TRANSFORM_AT_MODULUS + prime] = seeds.modulus[prime];
    }
}

__global__ static void slot_kernel(unsigned int *arena, TransformSeeds seeds, TransformLayout slot_lengths_layout)
{
    const unsigned int entry = blockIdx.x;
    const unsigned int prime = threadIdx.x;
    unsigned int length = 0u;
    unsigned int start = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int axis_start = slot_lengths_layout.slot_offsets[axis];
        const unsigned int axis_length = slot_lengths_layout.extents[axis];
        if ((entry >= axis_start) && (entry < (axis_start + axis_length)))
        {
            length = axis_length;
            start = axis_start;
        }
    }
    if (length == 0u)
    {
        return;
    }
    const unsigned int position = entry - start;
    unsigned int length_log = 0u;
    while ((1u << length_log) < length)
    {
        length_log += 1u;
    }
    const unsigned int frequency = bits_reversed(position, length_log);
    if (prime == 0u)
    {
        arena[TRANSFORM_AT_REVERSED + entry] = frequency;
        arena[TRANSFORM_AT_PARTNER + entry] = bits_reversed((length - frequency) & (length - 1u), length_log);

        arena[TRANSFORM_AT_ORDER + entry] = (position < (length >> 1u)) ? (position << 1u)
                                                                           : (((length - 1u - position) << 1u) + 1u);
        arena[TRANSFORM_AT_PLACE + entry] = ((position & 1u) == 0u) ? (position >> 1u)
                                                                       : (length - 1u - ((position - 1u) >> 1u));
    }
    const unsigned int psi_length = field_power(seeds.psi[prime], TRANSFORM_ROOT_ORDER / (4u * length), prime);
    const unsigned int omega = field_power(psi_length, 4u, prime);
    const unsigned long long at = ((unsigned long long)entry * TRANSFORM_PRIMES) + prime;
    if (position >= 1u)
    {
        unsigned int level = 0u;
        while ((2u << level) <= position)
        {
            level += 1u;
        }
        const unsigned int exponent = (length >> (level + 1u)) * bits_reversed(position - (1u << level), level);
        arena[TRANSFORM_AT_ROOTS + at] = field_power(omega, exponent, prime);
        arena[TRANSFORM_AT_INVERSE_ROOTS + at] = field_power(omega, (length - exponent) & (length - 1u), prime);
    }
    const unsigned int period = 4u * length;
    arena[TRANSFORM_AT_PSI + at] = field_power(psi_length, frequency, prime);
    arena[TRANSFORM_AT_PSI_INVERSE + at] = field_power(psi_length, (period - frequency) & (period - 1u), prime);
}

__global__ static void view_kernel(unsigned int *location, TransformSeeds seeds, TransformLayout layout, unsigned int gain)
{
    const unsigned int prime = threadIdx.x;
    const unsigned int modulus = seeds.primes[prime];
    unsigned int fold = 1u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int length = layout.extents[axis];
        const unsigned int psi_length = field_power(seeds.psi[prime], TRANSFORM_ROOT_ORDER / (4u * length), prime);
        location[TRANSFORM_AT_IMAGINARY + (axis * TRANSFORM_PRIMES) + prime] = field_power(psi_length, length, prime);
        fold = field_times(fold, field_power(2u * length, modulus - 2u, prime), prime);
    }
    location[TRANSFORM_AT_TWO_GAIN + prime] = field_power(2u, gain, prime);
    location[TRANSFORM_AT_FOLD + prime] = fold;
}

__global__ static void response_kernel(unsigned int *arena, TransformSeeds seeds, TransformLayout layout,
                                       TransformLayout orders)
{
    const unsigned int axis = blockIdx.x / TRANSFORM_LINE_ROOM;
    const unsigned int position = blockIdx.x % TRANSFORM_LINE_ROOM;
    const unsigned int prime = threadIdx.x;
    const unsigned int length = layout.extents[axis];
    if (position >= length)
    {
        return;
    }
    const unsigned int psi_length = field_power(seeds.psi[prime], TRANSFORM_ROOT_ORDER / (4u * length), prime);
    const unsigned int period = 4u * length;
    const unsigned int frequency = bits_reversed(position, layout.logarithms[axis]);
    const unsigned int lift = field_add(1u, field_power(psi_length, (2u * frequency) & (period - 1u), prime), prime);
    const unsigned long long at = ((unsigned long long)blockIdx.x * TRANSFORM_PRIMES) + prime;

    const unsigned int smooth_order = orders.extents[axis];
    const unsigned int background_order = orders.logarithms[axis];
    const unsigned int smooth_turn = field_power(psi_length, (period - ((frequency * smooth_order) & (period - 1u))) & (period - 1u), prime);
    const unsigned int background_turn = field_power(psi_length, (period - ((frequency * background_order) & (period - 1u))) & (period - 1u),
                                                     prime);
    arena[TRANSFORM_AT_SMOOTH + at] = field_times(smooth_turn, field_power(lift, smooth_order, prime), prime);
    arena[TRANSFORM_AT_BACKGROUND + at] = field_times(background_turn, field_power(lift, background_order, prime), prime);
}

__global__ static void line_forward_kernel(const unsigned short *volume, unsigned int *arena, unsigned int respond,
                                           TransformLayout layout, AxisLines axis)
{
    __shared__ unsigned int line[TRANSFORM_LINE_ROOM * TRANSFORM_PRIMES];
    const unsigned int position = threadIdx.x;
    const unsigned int slot = axis.slot_offset;
    const unsigned int high = (blockIdx.x >> axis.low_log) << (axis.low_log + axis.length_log);
    const unsigned int low = blockIdx.x & ((1u << axis.low_log) - 1u);
    const unsigned int read = high + (arena[TRANSFORM_AT_ORDER + slot + position] << axis.low_log) + low;
    for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
    {

        line[(position * TRANSFORM_PRIMES) + prime] = (volume != NULL)
                                                    ? (unsigned int)volume[read]
                                                    : arena[TRANSFORM_AT_WORK + ((unsigned long long)read * TRANSFORM_PRIMES) + prime];
    }
    __syncthreads();
    for (unsigned int level = 0u; level < axis.length_log; level += 1u)
    {
        const unsigned int size_log = axis.length_log - level;
        const unsigned int half = 1u << (size_log - 1u);
        if ((position & ((1u << size_log) - 1u)) < half)
        {
            const unsigned long long roots = TRANSFORM_AT_ROOTS + ((slot + (1u << level) + (position >> size_log)) * TRANSFORM_PRIMES);
            for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
            {
                const unsigned int here = (position * TRANSFORM_PRIMES) + prime;
                const unsigned int there = here + (half * TRANSFORM_PRIMES);
                const unsigned int upper = line[here];
                const unsigned int lower = field_times(line[there], arena[roots + prime], prime);
                line[here] = field_add(upper, lower, prime);
                line[there] = field_subtract(upper, lower, prime);
            }
        }
        __syncthreads();
    }
    const unsigned int other = arena[TRANSFORM_AT_PARTNER + slot + position];
    if (other >= position)
    {
        const unsigned int psi_here = (slot + position) * TRANSFORM_PRIMES;
        const unsigned int psi_other = (slot + other) * TRANSFORM_PRIMES;
        for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
        {
            const unsigned int here_value = line[(position * TRANSFORM_PRIMES) + prime];
            const unsigned int other_value = line[(other * TRANSFORM_PRIMES) + prime];
            line[(position * TRANSFORM_PRIMES) + prime] = field_add(
                field_times(arena[TRANSFORM_AT_PSI + psi_here + prime], here_value, prime),
                field_times(arena[TRANSFORM_AT_PSI_INVERSE + psi_here + prime], other_value, prime), prime);
            if (other != position)
            {
                line[(other * TRANSFORM_PRIMES) + prime] = field_add(
                    field_times(arena[TRANSFORM_AT_PSI + psi_other + prime], other_value, prime),
                    field_times(arena[TRANSFORM_AT_PSI_INVERSE + psi_other + prime], here_value, prime), prime);
            }
        }
    }
    __syncthreads();
    const unsigned int element = high + (position << axis.low_log) + low;
    const unsigned long long destination = TRANSFORM_AT_WORK + ((unsigned long long)element * TRANSFORM_PRIMES);
    const unsigned long long z = (element >> layout.shift_z) * TRANSFORM_PRIMES;
    const unsigned long long y = ((1ull * TRANSFORM_LINE_ROOM) + ((element >> layout.shift_y) & layout.mask_y)) * TRANSFORM_PRIMES;
    const unsigned long long x = ((2ull * TRANSFORM_LINE_ROOM) + (element & layout.mask_x)) * TRANSFORM_PRIMES;
    for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
    {
        unsigned int value = line[(position * TRANSFORM_PRIMES) + prime];
        if (respond != 0u)
        {
            const unsigned int smooth_product = field_times(field_times(arena[TRANSFORM_AT_SMOOTH + z + prime],
                                                                        arena[TRANSFORM_AT_SMOOTH + y + prime], prime),
                                                            arena[TRANSFORM_AT_SMOOTH + x + prime], prime);
            const unsigned int background_product = field_times(field_times(arena[TRANSFORM_AT_BACKGROUND + z + prime],
                                                                            arena[TRANSFORM_AT_BACKGROUND + y + prime], prime),
                                                                arena[TRANSFORM_AT_BACKGROUND + x + prime], prime);
            const unsigned int response = field_times(smooth_product,
                                                      field_subtract(s_transform[TRANSFORM_AT_TWO_GAIN + prime],
                                                                     background_product, prime),
                                                      prime);
            value = field_times(field_times(value, response, prime), s_transform[TRANSFORM_AT_FOLD + prime], prime);
        }
        arena[destination + prime] = value;
    }
}

__global__ static void line_inverse_kernel(unsigned int *arena, TransformLayout layout, AxisLines axis)
{
    __shared__ unsigned int line[TRANSFORM_LINE_ROOM * TRANSFORM_PRIMES];
    const unsigned int position = threadIdx.x;
    const unsigned int slot = axis.slot_offset;
    const unsigned int high = (blockIdx.x >> axis.low_log) << (axis.low_log + axis.length_log);
    const unsigned int low = blockIdx.x & ((1u << axis.low_log) - 1u);
    const unsigned int element = high + (position << axis.low_log) + low;
    const unsigned long long stored = TRANSFORM_AT_WORK + ((unsigned long long)element * TRANSFORM_PRIMES);
    for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
    {
        line[(position * TRANSFORM_PRIMES) + prime] = arena[stored + prime];
    }
    __syncthreads();
    const unsigned int other = arena[TRANSFORM_AT_PARTNER + slot + position];
    if ((other >= position) && (arena[TRANSFORM_AT_REVERSED + slot + position] != 0u))
    {
        const unsigned long long psi_here = TRANSFORM_AT_PSI_INVERSE + ((slot + position) * TRANSFORM_PRIMES);
        const unsigned long long psi_other = TRANSFORM_AT_PSI_INVERSE + ((slot + other) * TRANSFORM_PRIMES);
        const unsigned int imaginary = TRANSFORM_AT_IMAGINARY + (axis.axis * TRANSFORM_PRIMES);
        for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
        {
            const unsigned int here_value = line[(position * TRANSFORM_PRIMES) + prime];
            const unsigned int other_value = line[(other * TRANSFORM_PRIMES) + prime];
            const unsigned int turn = s_transform[imaginary + prime];
            line[(position * TRANSFORM_PRIMES) + prime] = field_times(
                arena[psi_here + prime], field_add(here_value, field_times(turn, other_value, prime), prime), prime);
            if (other != position)
            {
                line[(other * TRANSFORM_PRIMES) + prime] = field_times(
                    arena[psi_other + prime], field_add(other_value, field_times(turn, here_value, prime), prime), prime);
            }
        }
    }
    __syncthreads();
    for (unsigned int remaining = axis.length_log; remaining > 0u; remaining -= 1u)
    {
        const unsigned int level = remaining - 1u;
        const unsigned int size_log = axis.length_log - level;
        const unsigned int half = 1u << (size_log - 1u);
        if ((position & ((1u << size_log) - 1u)) < half)
        {
            const unsigned long long roots = TRANSFORM_AT_INVERSE_ROOTS + ((slot + (1u << level) + (position >> size_log)) * TRANSFORM_PRIMES);
            for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
            {
                const unsigned int here = (position * TRANSFORM_PRIMES) + prime;
                const unsigned int there = here + (half * TRANSFORM_PRIMES);
                const unsigned int upper = line[here];
                const unsigned int lower = line[there];
                line[here] = field_add(upper, lower, prime);
                line[there] = field_times(field_subtract(upper, lower, prime), arena[roots + prime], prime);
            }
        }
        __syncthreads();
    }
    const unsigned int from = arena[TRANSFORM_AT_PLACE + slot + position];
    for (unsigned int prime = 0u; prime < TRANSFORM_PRIMES; prime += 1u)
    {
        arena[stored + prime] = line[(from * TRANSFORM_PRIMES) + prime];
    }
}

__global__ static void join_kernel(const unsigned int *arena, unsigned int voxels, unsigned int *residual)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long stored = TRANSFORM_AT_WORK + ((unsigned long long)voxel * TRANSFORM_PRIMES);
    unsigned int digits[TRANSFORM_PRIMES];
    digits[0] = arena[stored];
    for (unsigned int prime = 1u; prime < TRANSFORM_PRIMES; prime += 1u)
    {
        const unsigned int modulus = s_transform[TRANSFORM_AT_PRIMES + prime];

        unsigned int partial = digits[0] - ((digits[0] >= modulus) ? modulus : 0u);
        for (unsigned int digit = 1u; digit < prime; digit += 1u)
        {
            partial = field_add(partial,
                                field_times(digits[digit], s_transform[TRANSFORM_AT_COEFFICIENT + (prime * TRANSFORM_PRIMES) + digit], prime),
                                prime);
        }
        digits[prime] = field_times(field_subtract(arena[stored + prime], partial, prime),
                                    s_transform[TRANSFORM_AT_INVERSE + prime], prime);
    }
    int negative = 0;
    for (unsigned int prime = TRANSFORM_PRIMES; prime > 0u; prime -= 1u)
    {
        const unsigned int half = s_transform[TRANSFORM_AT_HALF + prime - 1u];
        if (digits[prime - 1u] != half)
        {
            negative = (digits[prime - 1u] > half) ? 1 : 0;
            break;
        }
    }
    unsigned int limbs[BINOMIAL_BASINS_LIMBS];
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        limbs[limb] = 0u;
    }
    limbs[0] = digits[TRANSFORM_PRIMES - 1u];
    for (unsigned int prime = TRANSFORM_PRIMES - 1u; prime > 0u; prime -= 1u)
    {
        unsigned long long carry = (unsigned long long)digits[prime - 1u];
        const unsigned long long factor = (unsigned long long)s_transform[TRANSFORM_AT_PRIMES + prime - 1u];
        for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
        {

            const unsigned long long total = ((unsigned long long)limbs[limb] * factor) + carry;

            limbs[limb] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
    unsigned long long borrow = 0ull;
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        const unsigned long long subtracted = (negative != 0) ? (unsigned long long)s_transform[TRANSFORM_AT_MODULUS + limb] : 0ull;
        const unsigned long long difference = ((unsigned long long)limbs[limb] - subtracted) - borrow;

        residual[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
        borrow = (difference >> 63u) & 1ull;
    }
}

struct TransformContext
{
    unsigned int extents[3];
    unsigned int smooth[3];
    unsigned int background[3];
    TransformLayout layout;
    unsigned int *arena;
};

static TransformContext s_transform_context;

static int transform_launched(void)
{

    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

static int transform_layout(const unsigned int *extents, TransformLayout *layout)
{
    memset(layout, 0, sizeof(*layout));
    unsigned long long total = 1ull;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        layout->extents[axis] = extents[axis];
        while ((1u << layout->logarithms[axis]) < extents[axis])
        {
            layout->logarithms[axis] += 1u;
        }
        total *= (unsigned long long)extents[axis];
    }

    layout->total = (unsigned int)total;
    layout->stride_shifts[2] = 0u;
    layout->stride_shifts[1] = layout->logarithms[2];
    layout->stride_shifts[0] = layout->logarithms[1] + layout->logarithms[2];
    layout->shift_z = layout->stride_shifts[0];
    layout->shift_y = layout->stride_shifts[1];
    layout->mask_y = extents[1] - 1u;
    layout->mask_x = extents[2] - 1u;
    unsigned int used = 0u;
    for (unsigned int length = TRANSFORM_LINE_ROOM; length >= 2u; length >>= 1u)
    {
        int present = 0;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            if (extents[axis] == length)
            {
                layout->slot_offsets[axis] = used;
                present = 1;
            }
        }
        used += (present != 0) ? length : 0u;
    }
    return (used <= TRANSFORM_SLOT_ROOM) ? 1 : 0;
}

static int transform_hold(const unsigned int *extents, const unsigned int *smooth_orders,
                          const unsigned int *background_orders)
{
    TransformContext *const context = &s_transform_context;
    if ((context->arena != NULL) && (memcmp(context->extents, extents, sizeof(context->extents)) == 0)
     && (memcmp(context->smooth, smooth_orders, sizeof(context->smooth)) == 0)
     && (memcmp(context->background, background_orders, sizeof(context->background)) == 0))
    {
        return 1;
    }
    cudaFree(context->arena);
    memset(context, 0, sizeof(*context));
    int ok = transform_layout(extents, &context->layout);
    const TransformLayout layout = context->layout;

    static const unsigned int primes[TRANSFORM_PRIMES] = {TRANSFORM_PRIME_VALUES};
    static const unsigned int barrett_low[TRANSFORM_PRIMES] = {TRANSFORM_BARRETT_LOW};
    static const unsigned int barrett_high[TRANSFORM_PRIMES] = {TRANSFORM_BARRETT_HIGH};
    static const unsigned int psi[TRANSFORM_PRIMES] = {TRANSFORM_PSI_VALUES};
    static const unsigned int coefficient[TRANSFORM_PRIMES * TRANSFORM_PRIMES] = {TRANSFORM_COEFFICIENT_VALUES};
    static const unsigned int inverse[TRANSFORM_PRIMES] = {TRANSFORM_INVERSE_VALUES};
    static const unsigned int half[TRANSFORM_PRIMES] = {TRANSFORM_HALF_VALUES};
    static const unsigned int modulus[BINOMIAL_BASINS_LIMBS] = {TRANSFORM_MODULUS_VALUES};
    TransformSeeds seeds;
    memcpy(seeds.primes, primes, sizeof(primes));
    memcpy(seeds.barrett_low, barrett_low, sizeof(barrett_low));
    memcpy(seeds.barrett_high, barrett_high, sizeof(barrett_high));
    memcpy(seeds.psi, psi, sizeof(psi));
    memcpy(seeds.coefficient, coefficient, sizeof(coefficient));
    memcpy(seeds.inverse, inverse, sizeof(inverse));
    memcpy(seeds.half, half, sizeof(half));
    memcpy(seeds.modulus, modulus, sizeof(modulus));

    void *address = NULL;
    ok = ok && (cudaGetSymbolAddress(&address, s_transform) == cudaSuccess);
    unsigned int *const location = (unsigned int *)address;
    if (ok != 0)
    {
        seed_kernel<<<1u, TRANSFORM_PRIMES>>>(location, seeds);
        ok = transform_launched();
    }
    const size_t arena_bytes = ((size_t)TRANSFORM_AT_WORK + ((size_t)layout.total * TRANSFORM_PRIMES)) * sizeof(unsigned int);
    ok = ok && (cudaMalloc((void **)&context->arena, arena_bytes) == cudaSuccess);
    if (ok != 0)
    {
        slot_kernel<<<TRANSFORM_SLOT_ROOM, TRANSFORM_PRIMES>>>(context->arena, seeds, layout);
        ok = transform_launched();
    }
    unsigned int gain = 0u;
    TransformLayout orders;
    memset(&orders, 0, sizeof(orders));
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        gain += background_orders[axis];

        orders.extents[axis] = smooth_orders[axis];
        orders.logarithms[axis] = background_orders[axis];
    }
    if (ok != 0)
    {
        view_kernel<<<1u, TRANSFORM_PRIMES>>>(location, seeds, layout, gain);
        ok = transform_launched();
    }
    if (ok != 0)
    {
        response_kernel<<<3u * TRANSFORM_LINE_ROOM, TRANSFORM_PRIMES>>>(context->arena, seeds, layout, orders);
        ok = transform_launched();
    }
    ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    if (ok == 0)
    {
        cudaFree(context->arena);
        memset(context, 0, sizeof(*context));
        return 0;
    }
    memcpy(context->extents, extents, sizeof(context->extents));
    memcpy(context->smooth, smooth_orders, sizeof(context->smooth));
    memcpy(context->background, background_orders, sizeof(context->background));
    return 1;
}

extern "C" int binomial_transform_admits(const unsigned int *extents, const unsigned int *smooth_orders,
                                         const unsigned int *background_orders)
{
    unsigned long long bits = 16ull;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int extent = extents[axis];

        if ((extent < 2u) || (extent > TRANSFORM_LINE_ROOM) || ((extent & (extent - 1u)) != 0u)
         || ((smooth_orders[axis] % 2u) != 0u) || ((background_orders[axis] % 2u) != 0u))
        {
            return 0;
        }
        bits += (unsigned long long)smooth_orders[axis] + (unsigned long long)background_orders[axis];
    }
    TransformLayout layout;

    return ((bits + 1ull) <= (32ull * BINOMIAL_BASINS_LIMBS)) && ((bits + 1ull) < (29ull * TRANSFORM_PRIMES))
        && (transform_layout(extents, &layout) != 0);
}

extern "C" int binomial_transform_residual(const unsigned short *volume, const unsigned int *extents,
                                           const unsigned int *smooth_orders, const unsigned int *background_orders,
                                           unsigned int *residual)
{
    if ((binomial_transform_admits(extents, smooth_orders, background_orders) == 0)
     || (transform_hold(extents, smooth_orders, background_orders) == 0))
    {
        return 0;
    }
    const TransformContext *const context = &s_transform_context;
    const TransformLayout layout = context->layout;
    int ok = 1;

    for (unsigned int axis = 0u; (ok != 0) && (axis < 3u); axis += 1u)
    {
        AxisLines lines;
        lines.axis = axis;
        lines.length_log = layout.logarithms[axis];
        lines.low_log = layout.stride_shifts[axis];
        lines.slot_offset = layout.slot_offsets[axis];
        line_forward_kernel<<<layout.total >> layout.logarithms[axis], layout.extents[axis]>>>(
            (axis == 0u) ? volume : NULL, context->arena, (axis == 2u) ? 1u : 0u, layout, lines);
        ok = transform_launched();
    }
    for (unsigned int axis = 0u; (ok != 0) && (axis < 3u); axis += 1u)
    {
        AxisLines lines;
        lines.axis = axis;
        lines.length_log = layout.logarithms[axis];
        lines.low_log = layout.stride_shifts[axis];
        lines.slot_offset = layout.slot_offsets[axis];
        line_inverse_kernel<<<layout.total >> layout.logarithms[axis], layout.extents[axis]>>>(context->arena, layout, lines);
        ok = transform_launched();
    }
    if (ok != 0)
    {
        const unsigned int blocks = (layout.total + TRANSFORM_BLOCK - 1u) / TRANSFORM_BLOCK;
        join_kernel<<<blocks, TRANSFORM_BLOCK>>>(context->arena, layout.total, residual);
        ok = transform_launched();
    }
    return ok;
}
