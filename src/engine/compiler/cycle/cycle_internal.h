// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the cycle_{sweep,launch}.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef CYCLE_INTERNAL_H
#define CYCLE_INTERNAL_H

#include "cycle_shared.h"

struct CycleKey
{
    unsigned int terms;
    unsigned int bits;
    unsigned int columns;
    unsigned int planes;
    unsigned long long range[3];
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
    unsigned long long range[3];
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

unsigned long long cycle_reflect(long long position, long long length);

__device__ __forceinline__ static void cycle_multiply_add(unsigned int weight, unsigned int sample, unsigned int &low,
                                                          unsigned int &middle, unsigned int &high)
{
    asm("mad.lo.cc.u32 %0, %3, %4, %0;\n\t"
        "madc.hi.cc.u32 %1, %3, %4, %1;\n\t"
        "addc.u32 %2, %2, 0;"
        : "+r"(low), "+r"(middle), "+r"(high)
        : "r"(weight), "r"(sample));
}

__device__ static inline void cycle_place_at(const CycleLaunch &launch, unsigned long long lane, CyclePlace &place)
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

__device__ static inline void cycle_place_advance(const CycleLaunch &launch, CyclePlace &place)
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
__device__ static inline void cycle_rows_multiply(const unsigned int *row, unsigned int taps, const Lane *source,
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
__device__ static inline void cycle_rows_land(const CycleLaunch &launch, const DeviceSweep &sweep,
                                              const CyclePlace &place, const unsigned long long *fold,
                                              unsigned long long line, unsigned int first_row,
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
            cycle_rows_multiply<ROWS>(
                row, sweep.taps,
                &launch.scratch[((unsigned long long)(sweep.in_plane + input_limb) * launch.total) + place.atom_start +
                                line],
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
__device__ static inline void cycle_sweep(const CycleLaunch &launch, const DeviceSweep &sweep, const CyclePlace &place,
                                          unsigned int *value)
{
    const unsigned int axis = sweep.axis;
    const unsigned long long *const fold = &launch.folds[launch.fold_start[axis] + place.digit[axis] +
                                                         launch.range[axis] - (unsigned long long)(sweep.taps / 2u)];
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

__device__ static inline void cycle_fold(unsigned int *total, unsigned int limbs, const unsigned int *value,
                                         unsigned int filled, unsigned int shift, unsigned int negative)
{
    const unsigned int limb_shift = shift / 32u;
    const unsigned int part = shift % 32u;
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        unsigned int shifted = 0u;
        if (limb >= limb_shift)
        {
            const unsigned int from = limb - limb_shift;
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
            const unsigned long long difference =
                (1ull << 32u) + (unsigned long long)total[limb] - (unsigned long long)shifted - carry;
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

template <unsigned int WIDE> __global__ static void cycle_kernel(CycleLaunch launch)
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
                        launch.scratch[((unsigned long long)(row.out_plane + limb) * launch.total) + place.lane] =
                            value[limb];
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

struct CycleResident
{
    unsigned int *scratch;
    size_t scratch_words;
    const unsigned short **table;
    size_t table_capacity;
    unsigned long long *folds;
    size_t fold_capacity;
};

#endif
