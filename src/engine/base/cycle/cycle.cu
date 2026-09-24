// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle.h"

#include <cooperative_groups.h>
#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#include <vector>

#define CYCLE_BLOCK 256u

static_assert(sizeof(unsigned int) == 4u, "cycle: unsigned int must be 32 bits, a limb");
static_assert(sizeof(unsigned long long) == 8u, "cycle: unsigned long long must be 64 bits, a limb product");

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define CYCLE_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define CYCLE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

struct CycleKey
{
    unsigned int terms;
    unsigned int bits;
    unsigned int columns;
    unsigned int planes;
    unsigned long long reach[3];
    DeviceTerm *device_terms;
    unsigned int *device_weights;
};

struct CycleLaunch
{
    const DeviceTerm *terms;
    const unsigned int *weights;
    const unsigned short *const *lanes;
    const unsigned long long *folds;
    unsigned int *scratch;
    unsigned int *out;
    unsigned long long extent[3];
    unsigned long long stride[3];
    unsigned long long fold_start[3];
    unsigned long long reach[3];
    unsigned long long voxels;
    unsigned long long total;
    unsigned long long step;
    unsigned long long step_digit[4];
    unsigned int term_count;
    unsigned int limbs;
    unsigned int sweep_first;
    unsigned int sweep_last;
};

struct CyclePlace
{
    unsigned long long lane;
    unsigned long long atom;
    unsigned long long atom_start;
    unsigned long long within;
    unsigned long long digit[3];
};

static unsigned long long cycle_reflect(long long position, long long length)
{
    if ((position >= 0ll) && (position < length))
    {
        return (unsigned long long)position;
    }
    if ((position < 0ll) && (position >= -length))
    {
        return (unsigned long long)(-1ll - position);
    }
    if ((position >= length) && (position < (2ll * length)))
    {
        return (unsigned long long)((2ll * length) - 1ll - position);
    }
    const long long period = 2ll * length;
    long long folded = position % period;
    if (folded < 0ll)
    {
        folded += period;
    }
    if (folded >= length)
    {
        folded = period - 1ll - folded;
    }
    return (unsigned long long)folded;
}

__device__ __forceinline__ static void cycle_multiply_add(unsigned int weight, unsigned int sample, unsigned int &low,
                                                          unsigned int &middle, unsigned int &high)
{
    asm("mad.lo.cc.u32 %0, %3, %4, %0;\n\t"
        "madc.hi.cc.u32 %1, %3, %4, %1;\n\t"
        "addc.u32 %2, %2, 0;"
        : "+r"(low), "+r"(middle), "+r"(high)
        : "r"(weight), "r"(sample));
}

__device__ static void cycle_place_at(const CycleLaunch &launch, unsigned long long lane, CyclePlace &place)
{
    place.lane = lane;
    place.atom = lane / launch.voxels;
    place.atom_start = place.atom * launch.voxels;
    place.within = lane - place.atom_start;
    const unsigned long long line = place.within / launch.extent[2];
    place.digit[2] = place.within - (line * launch.extent[2]);
    place.digit[0] = line / launch.extent[1];
    place.digit[1] = line - (place.digit[0] * launch.extent[1]);
}

__device__ static void cycle_place_advance(const CycleLaunch &launch, CyclePlace &place)
{
    unsigned long long carry = 0ull;
    for (unsigned int axis = 3u; axis > 0u; axis -= 1u)
    {
        const unsigned int at = axis - 1u;
        place.digit[at] += launch.step_digit[axis] + carry;
        carry = (place.digit[at] >= launch.extent[at]) ? 1ull : 0ull;
        if (carry != 0ull)
        {
            place.digit[at] -= launch.extent[at];
        }
    }
    place.atom += launch.step_digit[0] + carry;
    place.lane += launch.step;
    place.atom_start = place.atom * launch.voxels;
    place.within = place.lane - place.atom_start;
}

template <unsigned int ROWS, typename Lane>
__device__ static void cycle_rows_multiply(const unsigned int *row, unsigned int taps, const Lane *source,
                                           const unsigned long long *fold, unsigned int (&sum)[ROWS][3])
{
    for (unsigned int tap = 0u; tap < taps; tap += 1u)
    {
        const unsigned int sample = (unsigned int)source[fold[tap]];
#pragma unroll
        for (unsigned int each = 0u; each < ROWS; each += 1u)
        {
            cycle_multiply_add(row[(each * taps) + tap], sample, sum[each][0], sum[each][1], sum[each][2]);
        }
    }
}

template <unsigned int ROWS>
__device__ static void cycle_rows_land(const CycleLaunch &launch, const DeviceSweep &sweep, const CyclePlace &place,
                                       const unsigned long long *fold, unsigned long long line, unsigned int first_row,
                                       unsigned long long *column)
{
    const unsigned int *const row = &launch.weights[sweep.weights + ((unsigned long long)first_row * sweep.taps)];
    for (unsigned int input_limb = 0u; input_limb < sweep.in_limbs; input_limb += 1u)
    {
        unsigned int sum[ROWS][3];
#pragma unroll
        for (unsigned int each = 0u; each < ROWS; each += 1u)
        {
            sum[each][0] = 0u;
            sum[each][1] = 0u;
            sum[each][2] = 0u;
        }
        if (sweep.in_plane == ENGINE_FROM_ATOM)
        {
            cycle_rows_multiply<ROWS>(row, sweep.taps, &launch.lanes[place.atom][line], fold, sum);
        }
        else
        {
            cycle_rows_multiply<ROWS>(row, sweep.taps,
                                      &launch.scratch[((unsigned long long)(sweep.in_plane + input_limb) * launch.total)
                                                      + place.atom_start + line],
                                      fold, sum);
        }
#pragma unroll
        for (unsigned int each = 0u; each < ROWS; each += 1u)
        {
            const unsigned int at = first_row + each + input_limb;
            column[at] += sum[each][0];
            column[at + 1u] += sum[each][1];
            column[at + 2u] += sum[each][2];
        }
    }
}

template <unsigned int WIDE>
__device__ static void cycle_sweep(const CycleLaunch &launch, const DeviceSweep &sweep, const CyclePlace &place,
                                   unsigned int *value)
{
    const unsigned int axis = sweep.axis;
    const unsigned long long *const fold = &launch.folds[launch.fold_start[axis] + place.digit[axis] + launch.reach[axis]
                                                         - (unsigned long long)(sweep.taps / 2u)];
    const unsigned long long line = place.within - (place.digit[axis] * launch.stride[axis]);
    const unsigned int used = sweep.row_limbs + sweep.in_limbs + 2u;
    unsigned long long column[WIDE + 2u];
    for (unsigned int at = 0u; at < used; at += 1u)
    {
        column[at] = 0ull;
    }
    unsigned int first_row = 0u;
    while (first_row < sweep.row_limbs)
    {
        const unsigned int left = sweep.row_limbs - first_row;
        if (left >= 4u)
        {
            cycle_rows_land<4u>(launch, sweep, place, fold, line, first_row, column);
            first_row += 4u;
        }
        else if (left == 3u)
        {
            cycle_rows_land<3u>(launch, sweep, place, fold, line, first_row, column);
            first_row += 3u;
        }
        else if (left == 2u)
        {
            cycle_rows_land<2u>(launch, sweep, place, fold, line, first_row, column);
            first_row += 2u;
        }
        else
        {
            cycle_rows_land<1u>(launch, sweep, place, fold, line, first_row, column);
            first_row += 1u;
        }
    }
    unsigned long long carry = 0ull;
    for (unsigned int at = 0u; at < sweep.out_limbs; at += 1u)
    {
        const unsigned long long total = column[at] + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static void cycle_fold(unsigned int *total, unsigned int limbs, const unsigned int *value,
                                  unsigned int filled, unsigned int shift, unsigned int negative)
{
    const unsigned int whole = shift / 32u;
    const unsigned int part = shift % 32u;
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        unsigned int shifted = 0u;
        if (limb >= whole)
        {
            const unsigned int from = limb - whole;
            if (from < filled)
            {
                shifted = value[from] << part;
            }
            if ((part != 0u) && (from > 0u) && ((from - 1u) < filled))
            {
                shifted |= value[from - 1u] >> (32u - part);
            }
        }
        if (negative != 0u)
        {
            const unsigned long long difference = (1ull << 32u) + (unsigned long long)total[limb]
                                                - (unsigned long long)shifted - carry;
            total[limb] = (unsigned int)(difference & 0xFFFFFFFFull);
            carry = (difference < (1ull << 32u)) ? 1ull : 0ull;
        }
        else
        {
            const unsigned long long sum = (unsigned long long)total[limb] + (unsigned long long)shifted + carry;
            total[limb] = (unsigned int)(sum & 0xFFFFFFFFull);
            carry = sum >> 32u;
        }
    }
}

template <unsigned int WIDE>
__global__ static void cycle_kernel(CycleLaunch launch)
{
    const unsigned long long first = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    unsigned int value[WIDE];
    unsigned int total[WIDE];
    for (unsigned int sweep = launch.sweep_first; sweep <= launch.sweep_last; sweep += 1u)
    {
        if (sweep > launch.sweep_first)
        {
            cooperative_groups::this_grid().sync();
        }
        if (first >= launch.total)
        {
            continue;
        }
        CyclePlace place;
        cycle_place_at(launch, first, place);
        for (; place.lane < launch.total; cycle_place_advance(launch, place))
        {
            if (sweep < (ENGINE_AXES - 1u))
            {
                for (unsigned int term = 0u; term < launch.term_count; term += 1u)
                {
                    const DeviceSweep &row = launch.terms[term].sweep[sweep];
                    cycle_sweep<WIDE>(launch, row, place, value);
                    for (unsigned int limb = 0u; limb < row.out_limbs; limb += 1u)
                    {
                        launch.scratch[((unsigned long long)(row.out_plane + limb) * launch.total) + place.lane]
                            = value[limb];
                    }
                }
                continue;
            }
            for (unsigned int limb = 0u; limb < launch.limbs; limb += 1u)
            {
                total[limb] = 0u;
            }
            for (unsigned int term = 0u; term < launch.term_count; term += 1u)
            {
                const DeviceTerm &folded = launch.terms[term];
                cycle_sweep<WIDE>(launch, folded.sweep[sweep], place, value);
                cycle_fold(total, launch.limbs, value, folded.sweep[sweep].out_limbs, folded.shift, folded.negative);
            }
            for (unsigned int limb = 0u; limb < launch.limbs; limb += 1u)
            {
                launch.out[(place.lane * launch.limbs) + limb] = total[limb];
            }
        }
    }
}

extern "C" long cycle_key_load(const EngineKeyLayout *layout, CycleKey **key_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_REFUSED;
    }
    if (!CYCLE_HELD((layout != NULL) && (key_out != NULL), layout, error, ENGINE_ERROR_REQUEST)
     || !CYCLE_HELD((layout->term_table != NULL) && (layout->weights != NULL) && (layout->terms != 0u), layout, error,
                    ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    *key_out = NULL;
    CycleKey *const key = (CycleKey *)calloc(1u, sizeof(CycleKey));
    int ok = CYCLE_HELD(key != NULL, key_out, error, ENGINE_ERROR_RESOURCE);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&key->device_terms, (size_t)layout->terms * sizeof(DeviceTerm)),
                    &key->device_terms, error);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&key->device_weights, (size_t)(layout->weight_count + 1ull) * sizeof(unsigned int)),
                    &key->device_weights, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(key->device_terms, layout->term_table, (size_t)layout->terms * sizeof(DeviceTerm),
                               cudaMemcpyHostToDevice),
                    key->device_terms, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(key->device_weights, layout->weights, (size_t)layout->weight_count * sizeof(unsigned int),
                               cudaMemcpyHostToDevice),
                    key->device_weights, error);
    if (ok == 0)
    {
        cycle_key_release(key);
        return CYCLE_REFUSED;
    }
    key->terms = layout->terms;
    key->bits = layout->bits;
    key->columns = layout->columns;
    key->planes = layout->planes;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        key->reach[axis] = layout->reach[axis];
    }
    *key_out = key;
    return (long)layout->bits;
}

extern "C" void cycle_key_release(CycleKey *key)
{
    if (key == NULL)
    {
        return;
    }
    cudaFree(key->device_terms);
    cudaFree(key->device_weights);
    free(key);
}

extern "C" unsigned int cycle_key_scratch_limbs(const CycleKey *key)
{
    return (key != NULL) ? key->planes : 0u;
}

struct CycleHeld
{
    unsigned int *scratch;
    size_t scratch_words;
    const unsigned short **table;
    size_t table_room;
    unsigned long long *folds;
    size_t fold_room;
};

static CycleHeld s_cycle_held;

static void cycle_step_digits(CycleLaunch &launch, unsigned long long step)
{
    launch.step = step;
    launch.step_digit[0] = step / launch.voxels;
    const unsigned long long within = step - (launch.step_digit[0] * launch.voxels);
    const unsigned long long line = within / launch.extent[2];
    launch.step_digit[3] = within - (line * launch.extent[2]);
    launch.step_digit[1] = line / launch.extent[1];
    launch.step_digit[2] = line - (launch.step_digit[1] * launch.extent[1]);
}

template <unsigned int WIDE>
static int cycle_launch(CycleLaunch launch, EngineError *error)
{
    int device = 0;
    int cooperative = 0;
    int processors = 0;
    int per_processor = 0;
    int ok = CYCLE_TOOK(cudaGetDevice(&device), &device, error);
    ok = ok && CYCLE_TOOK(cudaDeviceGetAttribute(&cooperative, cudaDevAttrCooperativeLaunch, device), &cooperative, error);
    ok = ok && CYCLE_TOOK(cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device), &processors, error);
    // the block size is 256, so it converts to int exactly
    ok = ok
      && CYCLE_TOOK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&per_processor, cycle_kernel<WIDE>, (int)CYCLE_BLOCK, 0u),
                    &per_processor, error);
    if (ok == 0)
    {
        return 0;
    }
    const unsigned long long needed = (launch.total + CYCLE_BLOCK - 1u) / CYCLE_BLOCK;
    if ((cooperative != 0) && (per_processor > 0))
    {
        const unsigned long long resident = (unsigned long long)per_processor * (unsigned long long)processors;
        const unsigned int blocks = (unsigned int)((needed < resident) ? needed : resident);
        cycle_step_digits(launch, (unsigned long long)blocks * CYCLE_BLOCK);
        launch.sweep_first = 0u;
        launch.sweep_last = ENGINE_AXES - 1u;
        void *arguments[1] = {&launch};
        return CYCLE_TOOK(cudaLaunchCooperativeKernel((const void *)cycle_kernel<WIDE>, dim3(blocks), dim3(CYCLE_BLOCK),
                                                      arguments, 0u, 0),
                          launch.out, error);
    }
    const unsigned int blocks = (unsigned int)((needed < 0x7FFFFFFFull) ? needed : 0x7FFFFFFFull);
    cycle_step_digits(launch, (unsigned long long)blocks * CYCLE_BLOCK);
    for (unsigned int sweep = 0u; (sweep < ENGINE_AXES) && (ok != 0); sweep += 1u)
    {
        launch.sweep_first = sweep;
        launch.sweep_last = sweep;
        cycle_kernel<WIDE><<<blocks, CYCLE_BLOCK>>>(launch);
        ok = CYCLE_TOOK(cudaGetLastError(), launch.out, error);
    }
    return ok;
}

struct CycleRecord
{
    unsigned int steps;
    unsigned int members;
    unsigned int file_limbs;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
    unsigned int divides;
    DeviceRecordStep *device_steps;
    unsigned int *device_refused;
    unsigned int *device_tables;
};

struct CycleRecordLaunch
{
    const DeviceRecordStep *steps;
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *refused;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    unsigned int step_count;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
};

#define CYCLE_RECORD_BLOCKS_MOST 4096ull

__device__ static unsigned int cycle_record_limb(const unsigned int *value, unsigned int limbs, unsigned int at)
{
    return (at < limbs) ? value[at] : 0u;
}

__device__ static int cycle_record_compare(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                           unsigned int right_limbs)
{
    unsigned int at = (left_limbs > right_limbs) ? left_limbs : right_limbs;
    while (at > 0u)
    {
        at -= 1u;
        const unsigned int one = cycle_record_limb(left, left_limbs, at);
        const unsigned int other = cycle_record_limb(right, right_limbs, at);
        if (one != other)
        {
            return (one < other) ? -1 : 1;
        }
    }
    return 0;
}

__device__ static int cycle_record_is_zero(const unsigned int *value, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        if (value[at] != 0u)
        {
            return 0;
        }
    }
    return 1;
}

__device__ static void cycle_record_field(const unsigned int *atom, unsigned int in_limbs, unsigned int offset,
                                          unsigned int bits, unsigned int *value, unsigned int limbs)
{
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = offset + (32u * limb);
        const unsigned int word = bit / 32u;
        const unsigned int shift = bit % 32u;
        unsigned int gathered = cycle_record_limb(atom, in_limbs, word) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_record_limb(atom, in_limbs, word + 1u) << (32u - shift);
        }
        const unsigned int left = bits - (32u * limb);
        value[limb] = (left < 32u) ? (gathered & ((1u << left) - 1u)) : gathered;
    }
}

__device__ static void cycle_record_negate(unsigned int *value, unsigned int limbs, unsigned int bits)
{
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (unsigned long long)(~value[at]) + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    const unsigned int left = bits - (32u * (limbs - 1u));
    value[limbs - 1u] = (left < 32u) ? (value[limbs - 1u] & ((1u << left) - 1u)) : value[limbs - 1u];
}

__device__ static void cycle_record_add(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                        unsigned int right_limbs, unsigned int *value, unsigned int limbs)
{
    unsigned long long carry = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (unsigned long long)cycle_record_limb(left, left_limbs, at)
                                       + (unsigned long long)cycle_record_limb(right, right_limbs, at) + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static void cycle_record_subtract(const unsigned int *left, unsigned int left_limbs,
                                             const unsigned int *right, unsigned int right_limbs, unsigned int *value,
                                             unsigned int limbs)
{
    unsigned long long borrow = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (1ull << 32u) + (unsigned long long)cycle_record_limb(left, left_limbs, at)
                                       - (unsigned long long)cycle_record_limb(right, right_limbs, at) - borrow;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__device__ static void cycle_record_product(const unsigned int *left, unsigned int left_limbs,
                                            const unsigned int *right, unsigned int right_limbs, unsigned int *value,
                                            unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = 0u;
    }
    for (unsigned int low = 0u; low < left_limbs; low += 1u)
    {
        unsigned long long carry = 0ull;
        for (unsigned int high = 0u; (high < right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const unsigned long long total = ((unsigned long long)left[low] * (unsigned long long)right[high])
                                           + (unsigned long long)value[low + high] + carry;
            value[low + high] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        for (unsigned int at = low + right_limbs; (carry != 0ull) && (at < limbs); at += 1u)
        {
            const unsigned long long total = (unsigned long long)value[at] + carry;
            value[at] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

template <unsigned int WIDE>
__device__ static int cycle_record_ladder(const unsigned int *numerator, unsigned int numerator_limbs,
                                          const unsigned int *denominator, unsigned int denominator_limbs,
                                          unsigned int *band)
{
    unsigned int reached[WIDE + 2u];
    unsigned long long lower = 0ull;
    unsigned long long upper = 1ull;
    unsigned int counted = 0u;
    int below = 1;
    for (unsigned int rung = 1u; (below != 0) && (rung < ENGINE_GOLDEN_RUNGS); rung += 1u)
    {
        const unsigned int step[2] = {(unsigned int)(upper & 0xFFFFFFFFull), (unsigned int)(upper >> 32u)};
        cycle_record_product(denominator, denominator_limbs, step, 2u, reached, denominator_limbs + 2u);
        below = (cycle_record_compare(reached, denominator_limbs + 2u, numerator, numerator_limbs) <= 0) ? 1 : 0;
        counted += (unsigned int)below;
        const unsigned long long next = lower + upper;
        lower = upper;
        upper = next;
    }
    *band = counted;
    return 1;
}

// the division operations' scratch per lane, in limbs: long division holds the normalized numerator (one limb
// over) and divisor; the gcd holds its three remainders ahead of that; the exact quotient holds the shifted
// numerator and divisor, the inverse with its step product, and the next inverse
#define CYCLE_RECORD_SCRATCH(wide_) ((5u * (wide_)) + 4u)

__device__ static int cycle_record_divides(unsigned int operation)
{
    return (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

__device__ static unsigned int cycle_record_used(const unsigned int *value, unsigned int limbs)
{
    while ((limbs > 0u) && (value[limbs - 1u] == 0u))
    {
        limbs -= 1u;
    }
    return limbs;
}

// value shifted toward the low end by `bits` (below 32 times the limbs), into `limbs` of out
__device__ static void cycle_record_shift_down(const unsigned int *value, unsigned int value_limbs, unsigned int bits,
                                               unsigned int *out, unsigned int limbs)
{
    const unsigned int words = bits / 32u;
    const unsigned int shift = bits % 32u;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        unsigned int gathered = cycle_record_limb(value, value_limbs, at + words) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_record_limb(value, value_limbs, at + words + 1u) << (32u - shift);
        }
        out[at] = gathered;
    }
}

// Knuth's Algorithm D on the magnitudes: top = quotient . bottom + rest, each output kept to its own limbs and
// either one left out when NULL; 0 for a zero divisor. scratch holds 2 * WIDE + 2 limbs.
template <unsigned int WIDE>
__device__ static int cycle_record_divide(const unsigned int *top, unsigned int top_limbs, const unsigned int *bottom,
                                          unsigned int bottom_limbs, unsigned int *quotient,
                                          unsigned int quotient_limbs, unsigned int *rest, unsigned int rest_limbs,
                                          unsigned int *scratch)
{
    const unsigned int divisor_used = cycle_record_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    const unsigned int numerator_used = cycle_record_used(top, top_limbs);
    for (unsigned int at = 0u; (quotient != NULL) && (at < quotient_limbs); at += 1u)
    {
        quotient[at] = 0u;
    }
    if (numerator_used < divisor_used)
    {
        for (unsigned int at = 0u; (rest != NULL) && (at < rest_limbs); at += 1u)
        {
            rest[at] = cycle_record_limb(top, numerator_used, at);
        }
        return 1;
    }
    if (divisor_used == 1u)
    {
        const unsigned long long divisor = (unsigned long long)bottom[0];
        unsigned long long carried = 0ull;
        for (unsigned int at = numerator_used; at > 0u; at -= 1u)
        {
            const unsigned long long part = (carried << 32u) | (unsigned long long)top[at - 1u];
            if ((quotient != NULL) && ((at - 1u) < quotient_limbs))
            {
                quotient[at - 1u] = (unsigned int)(part / divisor);
            }
            carried = part % divisor;
        }
        for (unsigned int at = 0u; (rest != NULL) && (at < rest_limbs); at += 1u)
        {
            rest[at] = (at == 0u) ? (unsigned int)carried : 0u;
        }
        return 1;
    }
    unsigned int *const numerator = scratch;
    unsigned int *const divisor = &scratch[WIDE + 2u];
    const unsigned int shift = (unsigned int)__clz(bottom[divisor_used - 1u]);
    for (unsigned int at = 0u; at < divisor_used; at += 1u)
    {
        const unsigned int below = ((shift != 0u) && (at > 0u)) ? (bottom[at - 1u] >> (32u - shift)) : 0u;
        divisor[at] = (bottom[at] << shift) | below;
    }
    for (unsigned int at = 0u; at <= numerator_used; at += 1u)
    {
        const unsigned int here = cycle_record_limb(top, numerator_used, at);
        const unsigned int below = ((shift != 0u) && (at > 0u)) ? (top[at - 1u] >> (32u - shift)) : 0u;
        numerator[at] = (here << shift) | below;
    }
    const unsigned long long lead = (unsigned long long)divisor[divisor_used - 1u];
    const unsigned long long next = (unsigned long long)divisor[divisor_used - 2u];
    for (unsigned int place = numerator_used - divisor_used + 1u; place > 0u; place -= 1u)
    {
        const unsigned int at = place - 1u;
        const unsigned long long part = ((unsigned long long)numerator[at + divisor_used] << 32u)
                                      | (unsigned long long)numerator[at + divisor_used - 1u];
        unsigned long long guess = part / lead;
        unsigned long long over = part % lead;
        while ((guess >> 32u) != 0ull
               || ((guess * next) > ((over << 32u) | (unsigned long long)numerator[at + divisor_used - 2u])))
        {
            guess -= 1ull;
            over += lead;
            if ((over >> 32u) != 0ull)
            {
                break;
            }
        }
        unsigned long long borrow = 0ull;
        for (unsigned int limb = 0u; limb < divisor_used; limb += 1u)
        {
            const unsigned long long taken = (guess * (unsigned long long)divisor[limb]) + borrow;
            const unsigned long long held = (unsigned long long)numerator[at + limb];
            numerator[at + limb] = (unsigned int)((held - (taken & 0xFFFFFFFFull)) & 0xFFFFFFFFull);
            borrow = (taken >> 32u) + ((held < (taken & 0xFFFFFFFFull)) ? 1ull : 0ull);
        }
        const unsigned long long held = (unsigned long long)numerator[at + divisor_used];
        numerator[at + divisor_used] = (unsigned int)((held - borrow) & 0xFFFFFFFFull);
        if (held < borrow)
        {
            // the guess was one too many (Knuth D6): add the divisor back
            guess -= 1ull;
            unsigned long long carry = 0ull;
            for (unsigned int limb = 0u; limb < divisor_used; limb += 1u)
            {
                const unsigned long long total = (unsigned long long)numerator[at + limb]
                                               + (unsigned long long)divisor[limb] + carry;
                numerator[at + limb] = (unsigned int)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
            numerator[at + divisor_used] = (unsigned int)((numerator[at + divisor_used] + carry) & 0xFFFFFFFFull);
        }
        if ((quotient != NULL) && (at < quotient_limbs))
        {
            quotient[at] = (unsigned int)guess;
        }
    }
    if (rest != NULL)
    {
        cycle_record_shift_down(numerator, divisor_used + 1u, shift, rest, rest_limbs);
        for (unsigned int at = divisor_used; at < rest_limbs; at += 1u)
        {
            rest[at] = 0u;
        }
    }
    return 1;
}

// Euclid's gcd of the magnitudes by the long division above, into `limbs` of value; scratch holds 5 * WIDE + 2
template <unsigned int WIDE>
__device__ static void cycle_record_gcd(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                        unsigned int right_limbs, unsigned int *value, unsigned int limbs,
                                        unsigned int *scratch)
{
    unsigned int *larger = scratch;
    unsigned int *smaller = &scratch[WIDE];
    unsigned int *rest = &scratch[2u * WIDE];
    for (unsigned int at = 0u; at < WIDE; at += 1u)
    {
        larger[at] = cycle_record_limb(left, left_limbs, at);
        smaller[at] = cycle_record_limb(right, right_limbs, at);
    }
    while (cycle_record_used(smaller, WIDE) != 0u)
    {
        cycle_record_divide<WIDE>(larger, WIDE, smaller, WIDE, NULL, 0u, rest, WIDE, &scratch[3u * WIDE]);
        unsigned int *const held = larger;
        larger = smaller;
        smaller = rest;
        rest = held;
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = larger[at];
    }
}

// the quotient of an exact division by a multiply with the divisor's inverse and a mask: both are shifted past the
// divisor's low zero bits, the odd divisor's inverse modulo 2^(32 limbs) is grown by Newton's x(2 - dx) from one
// word, and the quotient is the low limbs of numerator . inverse; multiplying back proves it. 0 for a zero divisor or
// a remainder. scratch holds 5 * WIDE limbs.
template <unsigned int WIDE>
__device__ static int cycle_record_exact_quotient(const unsigned int *top, unsigned int top_limbs,
                                                  const unsigned int *bottom, unsigned int bottom_limbs,
                                                  unsigned int *value, unsigned int limbs, unsigned int *scratch)
{
    const unsigned int divisor_used = cycle_record_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = 0u;
    }
    if (cycle_record_used(top, top_limbs) == 0u)
    {
        return 1;
    }
    unsigned int low_zeros = 0u;
    while (bottom[low_zeros / 32u] == 0u)
    {
        low_zeros += 32u;
    }
    low_zeros += (unsigned int)(__ffs((int)bottom[low_zeros / 32u]) - 1);
    for (unsigned int bit = 0u; bit < low_zeros; bit += 1u)
    {
        if (((cycle_record_limb(top, top_limbs, bit / 32u) >> (bit % 32u)) & 1u) != 0u)
        {
            return 0;
        }
    }
    unsigned int *const numerator = scratch;
    unsigned int *const divisor = &scratch[WIDE];
    unsigned int *const inverse = &scratch[2u * WIDE];
    unsigned int *const stepped = &scratch[3u * WIDE];
    unsigned int *const grown = &scratch[4u * WIDE];
    cycle_record_shift_down(top, top_limbs, low_zeros, numerator, limbs);
    cycle_record_shift_down(bottom, bottom_limbs, low_zeros, divisor, divisor_used);
    // an odd word is its own inverse to 3 bits, and each step doubles the bits: 6, 12, 24, 48
    unsigned int word = divisor[0];
    for (unsigned int round = 0u; round < 4u; round += 1u)
    {
        word *= 2u - (divisor[0] * word);
    }
    inverse[0] = word;
    for (unsigned int held = 1u; held < limbs;)
    {
        const unsigned int reach = ((2u * held) < limbs) ? (2u * held) : limbs;
        cycle_record_product(divisor, (divisor_used < reach) ? divisor_used : reach, inverse, held, stepped, reach);
        // 2 - d x modulo 2^(32 reach): the two's complement of d x, plus 2
        unsigned long long carry = 2ull;
        for (unsigned int at = 0u; at < reach; at += 1u)
        {
            const unsigned long long total = (unsigned long long)(~stepped[at]) + ((at == 0u) ? 1ull : 0ull) + carry;
            stepped[at] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        cycle_record_product(inverse, held, stepped, reach, grown, reach);
        for (unsigned int at = 0u; at < reach; at += 1u)
        {
            inverse[at] = grown[at];
        }
        held = reach;
    }
    cycle_record_product(numerator, limbs, inverse, limbs, value, limbs);
    // the inverse and its step product lie together, room for the whole product of the quotient and the divisor
    unsigned int *const back = inverse;
    cycle_record_product(value, limbs, divisor, divisor_used, back, limbs + divisor_used);
    return (cycle_record_compare(back, limbs + divisor_used, numerator, limbs) == 0) ? 1 : 0;
}

__device__ static void cycle_record_put(unsigned int *record, unsigned int offset, unsigned int bits,
                                        const unsigned int *value, unsigned int limbs, int sign)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int held = (bit < (32u * limbs)) ? ((value[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
        unsigned int written = held;
        if (sign < 0)
        {
            const unsigned int flipped = (held ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        record[to / 32u] |= written << (to % 32u);
    }
}

// DIVIDES is 1 for a program holding a division operation, which alone carries the division scratch
template <unsigned int WIDE, unsigned int DIVIDES>
__global__ static void cycle_record_kernel(CycleRecordLaunch launch)
{
    unsigned int file[WIDE];
    unsigned int scratch[(DIVIDES != 0u) ? CYCLE_RECORD_SCRATCH(WIDE) : 1u];
    signed char sign[ENGINE_RECORD_STEPS_MAX];
    const DeviceRecordStep *const steps = launch.steps;
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; lane < launch.count;
         lane += stride)
    {
        const unsigned int *atom[ENGINE_RECORD_MEMBERS_MAX];
        int good = 1;
        for (unsigned int member = 0u; member < launch.members; member += 1u)
        {
            const unsigned long long body = (launch.index != NULL)
                                          ? (unsigned long long)launch.index[(lane * launch.members) + member] : lane;
            good = good && (body < launch.bodies[member]);
            atom[member] = &launch.in[member][((good != 0) ? body : 0ull) * launch.in_limbs[member]];
        }
        unsigned int *const record = &launch.out[lane * launch.out_limbs];
        for (unsigned int limb = 0u; limb < launch.out_limbs; limb += 1u)
        {
            record[limb] = 0u;
        }
        for (unsigned int at = 0u; (good != 0) && (at < launch.step_count); at += 1u)
        {
            const DeviceRecordStep step = steps[at];
            unsigned int *const value = &file[step.place];
            const unsigned int *const left = &file[steps[step.left].place];
            const unsigned int *const right = &file[steps[step.right].place];
            if (step.operation == ENGINE_RECORD_FIELD)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                sign[at] = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_FIELD_SIGNED)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                const unsigned int top = step.right - 1u;
                const int negative = (((value[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
                if (negative != 0)
                {
                    cycle_record_negate(value, step.limbs, step.right);
                }
                sign[at] = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
            }
            else if (step.operation == ENGINE_RECORD_CONSTANT)
            {
                value[0] = step.left;
                if (step.limbs > 1u)
                {
                    value[1] = step.right;
                }
                sign[at] = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_PRODUCT)
            {
                cycle_record_product(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
                sign[at] = (signed char)(sign[step.left] * sign[step.right]);
            }
            else if ((step.operation == ENGINE_RECORD_SUM) || (step.operation == ENGINE_RECORD_DIFFERENCE))
            {
                const int left_sign = sign[step.left];
                const int right_sign = (step.operation == ENGINE_RECORD_SUM) ? sign[step.right] : -sign[step.right];
                if ((left_sign == right_sign) || (right_sign == 0) || (left_sign == 0))
                {
                    cycle_record_add(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
                    sign[at] = (signed char)((left_sign != 0) ? left_sign : right_sign);
                }
                else if (cycle_record_compare(left, step.left_limbs, right, step.right_limbs) >= 0)
                {
                    cycle_record_subtract(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
                    sign[at] = (signed char)left_sign;
                }
                else
                {
                    cycle_record_subtract(right, step.right_limbs, left, step.left_limbs, value, step.limbs);
                    sign[at] = (signed char)right_sign;
                }
                sign[at] = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : sign[at];
            }
            else if (step.operation == ENGINE_RECORD_LADDER)
            {
                good = (sign[step.right] > 0) ? 1 : 0;
                unsigned int band = 0u;
                if (good != 0)
                {
                    cycle_record_ladder<WIDE>(left, step.left_limbs, right, step.right_limbs, &band);
                }
                value[0] = band;
                sign[at] = (band == 0u) ? 0 : sign[step.left];
            }
            else if (step.operation == ENGINE_RECORD_ABSOLUTE)
            {
                for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
                {
                    value[limb] = cycle_record_limb(left, step.left_limbs, limb);
                }
                sign[at] = (sign[step.left] != 0) ? 1 : 0;
            }
            else if (step.operation == ENGINE_RECORD_COMPARE)
            {
                const int left_sign = sign[step.left];
                const int right_sign = sign[step.right];
                const int order = (left_sign != right_sign)
                                ? ((left_sign > right_sign) ? 1 : -1)
                                : (left_sign * cycle_record_compare(left, step.left_limbs, right, step.right_limbs));
                value[0] = (order != 0) ? 1u : 0u;
                sign[at] = (signed char)order;
            }
            else if (step.operation == ENGINE_RECORD_TABLE)
            {
                // the low index_bits of the source register (index_bits <= 32, one limb) select a row
                const unsigned int index = (step.index_bits >= 32u) ? left[0] : (left[0] & ((1u << step.index_bits) - 1u));
                const unsigned int *const entry = &launch.tables[step.table_offset + (index * step.limbs)];
                for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
                {
                    value[limb] = entry[limb];
                }
                sign[at] = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if ((DIVIDES != 0u) && (cycle_record_divides(step.operation) != 0))
            {
                const int left_sign = sign[step.left];
                const int right_sign = sign[step.right];
                int held_sign = 1;
                if (step.operation == ENGINE_RECORD_QUOTIENT)
                {
                    good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs,
                                                     NULL, 0u, scratch);
                    held_sign = left_sign * right_sign;
                }
                else if (step.operation == ENGINE_RECORD_REMAINDER)
                {
                    good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, NULL, 0u, value,
                                                     step.limbs, scratch);
                    held_sign = left_sign;
                }
                else if (step.operation == ENGINE_RECORD_GCD)
                {
                    cycle_record_gcd<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, scratch);
                }
                else
                {
                    good = cycle_record_exact_quotient<WIDE>(left, step.left_limbs, right, step.right_limbs, value,
                                                             step.limbs, scratch);
                    held_sign = left_sign * right_sign;
                }
                sign[at] = (signed char)((cycle_record_is_zero(value, step.limbs) != 0) ? 0 : held_sign);
            }
            else
            {
                good = 0;
            }
            if ((good != 0) && (step.out_bits != 0u))
            {
                cycle_record_put(record, step.out_offset, step.out_bits, value, step.limbs, sign[at]);
            }
        }
        if (good == 0)
        {
            atomicAdd(launch.refused, 1u);
        }
    }
}

extern "C" long cycle_record_load(const EngineRecordLayout *layout, CycleRecord **record_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_REFUSED;
    }
    int asked = CYCLE_HELD((layout != NULL) && (record_out != NULL), layout, error, ENGINE_ERROR_REQUEST)
             && CYCLE_HELD((layout->step_table != NULL) && (layout->steps != 0u)
                               && (layout->steps <= ENGINE_RECORD_STEPS_MAX)
                               && (layout->file_limbs <= ENGINE_RECORD_LIMBS_MOST) && (layout->out_limbs != 0u)
                               && (layout->members != 0u) && (layout->members <= ENGINE_RECORD_MEMBERS_MAX),
                           layout, error, ENGINE_ERROR_REQUEST);
    for (unsigned int member = 0u; (asked != 0) && (member < layout->members); member += 1u)
    {
        asked = CYCLE_HELD(layout->in_limbs[member] != 0u, &layout->in_limbs[member], error, ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return CYCLE_REFUSED;
    }
    *record_out = NULL;
    CycleRecord *const record = (CycleRecord *)calloc(1u, sizeof(CycleRecord));
    int ok = CYCLE_HELD(record != NULL, record_out, error, ENGINE_ERROR_RESOURCE);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_steps, (size_t)layout->steps * sizeof(DeviceRecordStep)),
                    &record->device_steps, error);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_refused, sizeof(unsigned int)), &record->device_refused, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(record->device_steps, layout->step_table,
                               (size_t)layout->steps * sizeof(DeviceRecordStep), cudaMemcpyHostToDevice),
                    record->device_steps, error);
    if ((ok != 0) && (layout->table_word_count != 0ull))
    {
        ok = CYCLE_TOOK(cudaMalloc((void **)&record->device_tables,
                                   (size_t)layout->table_word_count * sizeof(unsigned int)),
                        &record->device_tables, error)
          && CYCLE_TOOK(cudaMemcpy(record->device_tables, layout->table_values,
                                   (size_t)layout->table_word_count * sizeof(unsigned int), cudaMemcpyHostToDevice),
                        record->device_tables, error);
    }
    if (ok == 0)
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    record->steps = layout->steps;
    record->members = layout->members;
    record->file_limbs = layout->file_limbs;
    memcpy(record->in_limbs, layout->in_limbs, sizeof(record->in_limbs));
    record->out_limbs = layout->out_limbs;
    for (unsigned int step = 0u; step < layout->steps; step += 1u)
    {
        const unsigned int operation = layout->step_table[step].operation;
        record->divides |= ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                            || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
                         ? 1u : 0u;
    }
    *record_out = record;
    return (long)layout->out_bits;
}

extern "C" void cycle_record_release(CycleRecord *record)
{
    if (record == NULL)
    {
        return;
    }
    cudaFree(record->device_steps);
    cudaFree(record->device_refused);
    cudaFree(record->device_tables);
    free(record);
}

extern "C" unsigned int cycle_record_out_limbs(const CycleRecord *record)
{
    return (record != NULL) ? record->out_limbs : 0u;
}

extern "C" unsigned int cycle_record_members(const CycleRecord *record)
{
    return (record != NULL) ? record->members : 0u;
}

extern "C" unsigned int cycle_record_in_limbs(const CycleRecord *record, unsigned int member)
{
    return ((record != NULL) && (member < record->members)) ? record->in_limbs[member] : 0u;
}

extern "C" long cycle_record_run(const CycleRecordRunRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!CYCLE_HELD((request->record != NULL) && (request->device_out != NULL) && (request->count != 0ull), request,
                    error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    const CycleRecord *const record = request->record;
    CycleRecordLaunch launch;
    memset(&launch, 0, sizeof(launch));
    for (unsigned int member = 0u; member < record->members; member += 1u)
    {
        if (!CYCLE_HELD((request->device_in[member] != NULL) && (request->bodies[member] != 0ull)
                            && ((request->device_index != NULL) || (request->count <= request->bodies[member])),
                        &request->device_in[member], error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_REFUSED;
        }
        launch.in[member] = request->device_in[member];
        launch.bodies[member] = request->bodies[member];
        launch.in_limbs[member] = record->in_limbs[member];
    }
    launch.steps = record->device_steps;
    launch.index = request->device_index;
    launch.tables = record->device_tables;
    launch.out = request->device_out;
    launch.refused = record->device_refused;
    launch.count = request->count;
    launch.step_count = record->steps;
    launch.members = record->members;
    launch.out_limbs = record->out_limbs;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MOST) ? needed : CYCLE_RECORD_BLOCKS_MOST);
    unsigned int refused = 1u;
    int ok = CYCLE_TOOK(cudaMemset(record->device_refused, 0, sizeof(unsigned int)), record->device_refused, error);
    if ((ok != 0) && (record->file_limbs <= 64u))
    {
        if (record->divides != 0u)
        {
            cycle_record_kernel<64u, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
        }
        else
        {
            cycle_record_kernel<64u, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
        }
    }
    else if ((ok != 0) && (record->divides != 0u))
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if (ok != 0)
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    ok = ok && CYCLE_TOOK(cudaGetLastError(), request->device_out, error)
      && CYCLE_TOOK(cudaDeviceSynchronize(), request->device_out, error)
      && CYCLE_TOOK(cudaMemcpy(&refused, record->device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    record->device_refused, error)
      && CYCLE_HELD(refused == 0u, record->device_refused, error, ENGINE_ERROR_REQUEST);
    return (ok != 0) ? (long)request->count : CYCLE_REFUSED;
}

extern "C" long cycle_run(const CycleRunRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!CYCLE_HELD((request->key != NULL) && (request->atoms != NULL) && (request->count != 0ull)
                        && (request->device_out != NULL),
                    request, error, ENGINE_ERROR_REQUEST)
     || !CYCLE_HELD(((unsigned long long)request->limbs * 32ull) >= request->key->bits, &request->limbs, error,
                    ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    const Atom *const shape = &request->atoms[0];
    if (!CYCLE_HELD((shape->depth != 0ull) && (shape->height != 0ull) && (shape->width != 0ull), shape, error,
                    ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    for (unsigned long long atom = 0ull; atom < request->count; atom += 1ull)
    {
        const Atom *const each = &request->atoms[atom];
        if (!CYCLE_HELD((each->lanes != NULL) && (each->depth == shape->depth) && (each->height == shape->height)
                            && (each->width == shape->width),
                        each, error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_REFUSED;
        }
    }
    const unsigned long long most = 0xFFFFFFFFFFFFFFFFull;
    if (!CYCLE_HELD((shape->height <= (most / shape->width)) && (shape->depth <= (most / (shape->height * shape->width))),
                    shape, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    const unsigned long long voxels = shape->depth * shape->height * shape->width;
    if (!CYCLE_HELD((request->count <= (most / voxels))
                        && ((request->count * voxels) <= (most / 4ull / (request->key->planes + 1u))),
                    &request->count, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    const unsigned long long total = request->count * voxels;

    CycleHeld *const held = &s_cycle_held;
    const size_t scratch_words = (size_t)(total * request->key->planes);
    int ok = 1;
    if (scratch_words > held->scratch_words)
    {
        cudaFree(held->scratch);
        held->scratch = NULL;
        held->scratch_words = 0u;
        ok = CYCLE_TOOK(cudaMalloc((void **)&held->scratch, scratch_words * sizeof(unsigned int)), &held->scratch, error);
        held->scratch_words = (ok != 0) ? scratch_words : 0u;
    }
    if ((ok != 0) && (request->count > held->table_room))
    {
        cudaFree(held->table);
        held->table = NULL;
        held->table_room = 0u;
        ok = CYCLE_TOOK(cudaMalloc((void **)&held->table, (size_t)request->count * sizeof(const unsigned short *)),
                        &held->table, error);
        held->table_room = (ok != 0) ? (size_t)request->count : 0u;
    }
    std::vector<const unsigned short *> table((size_t)request->count);
    for (size_t atom = 0u; atom < table.size(); atom += 1u)
    {
        table[atom] = request->atoms[atom].lanes;
    }
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(held->table, table.data(), table.size() * sizeof(const unsigned short *),
                               cudaMemcpyHostToDevice),
                    held->table, error);

    CycleLaunch launch;
    memset(&launch, 0, sizeof(launch));
    launch.extent[0] = shape->depth;
    launch.extent[1] = shape->height;
    launch.extent[2] = shape->width;
    launch.stride[0] = shape->height * shape->width;
    launch.stride[1] = shape->width;
    launch.stride[2] = 1ull;
    std::vector<unsigned long long> folds;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        launch.fold_start[axis] = (unsigned long long)folds.size();
        launch.reach[axis] = request->key->reach[axis];
        const unsigned long long span = launch.extent[axis] + (2ull * launch.reach[axis]);
        for (unsigned long long entry = 0ull; entry < span; entry += 1ull)
        {
            const long long position = (long long)entry - (long long)launch.reach[axis];
            folds.push_back(cycle_reflect(position, (long long)launch.extent[axis]) * launch.stride[axis]);
        }
    }
    if ((ok != 0) && (folds.size() > held->fold_room))
    {
        cudaFree(held->folds);
        held->folds = NULL;
        held->fold_room = 0u;
        ok = CYCLE_TOOK(cudaMalloc((void **)&held->folds, folds.size() * sizeof(unsigned long long)), &held->folds,
                        error);
        held->fold_room = (ok != 0) ? folds.size() : 0u;
    }
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(held->folds, folds.data(), folds.size() * sizeof(unsigned long long),
                               cudaMemcpyHostToDevice),
                    held->folds, error);
    if (ok == 0)
    {
        return CYCLE_REFUSED;
    }

    launch.terms = request->key->device_terms;
    launch.weights = request->key->device_weights;
    launch.lanes = held->table;
    launch.folds = held->folds;
    launch.scratch = held->scratch;
    launch.out = request->device_out;
    launch.voxels = voxels;
    launch.total = total;
    launch.term_count = request->key->terms;
    launch.limbs = request->limbs;
    const unsigned int need = (request->key->columns > request->limbs) ? request->key->columns : request->limbs;
    if (need <= 16u)
    {
        ok = cycle_launch<16u>(launch, error);
    }
    else if (need <= 64u)
    {
        ok = cycle_launch<64u>(launch, error);
    }
    else if (need <= 256u)
    {
        ok = cycle_launch<256u>(launch, error);
    }
    else
    {
        ok = CYCLE_HELD(need <= 256u, &request->key->columns, error, ENGINE_ERROR_REQUEST);
    }
    return (ok != 0) ? (long)request->count : CYCLE_REFUSED;
}
