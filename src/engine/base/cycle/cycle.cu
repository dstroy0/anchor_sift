// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle.h"

// the CRC that seals a program's block, and the signum that names its program
#include "../crc.h"
#include "obsignatio.h"

#include <cooperative_groups.h>
#include <cuda_runtime.h>
// NVRTC's and nvJitLink's prototypes only: both libraries are loaded at run time, and a build links nothing more
#include <nvJitLink.h>
#include <nvrtc.h>

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <chrono>
#include <string>
#include <vector>

#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <direct.h>
#include <process.h>
#include <windows.h>
#else
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

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

// The stack a launch grew past `before`, given back once its work is done. The runtime raises the stack limit to the
// widest frame a kernel launches with, reserves that frame for every thread the device keeps resident, and holds it
// until the limit is set back (measured on the RTX 3070, 25 September: a 7,600-byte frame held 467,668,992 bytes past
// the 1 KiB default, setting the limit back returned them in 5.0 ms, and the next launch of that kernel took 21.6 ms
// against 1.6 ms warm). A `before` of 0 is a limit never read, and nothing is set.
static int cycle_stack_return(size_t before, const void *evacaddr, EngineError *error)
{
    if (before == 0u)
    {
        return 1;
    }
    size_t after = 0u;
    if (!CYCLE_TOOK(cudaDeviceGetLimit(&after, cudaLimitStackSize), &after, error))
    {
        return 0;
    }
    return (after <= before)
        || (CYCLE_TOOK(cudaDeviceSynchronize(), evacaddr, error)
            && CYCLE_TOOK(cudaDeviceSetLimit(cudaLimitStackSize, before), evacaddr, error));
}

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

// compiled is 1 where the program runs as its own kernel (below, the record program compiled), whose library the
// process's cache holds; 0 where it runs on the interpreter. The block is the host's copy of the program's
// EngineProgramBlock, and device_block the one its thread blocks write; hot is what they share on the device; registers and
// local_bytes are the compiled kernel's registers a thread and local frame a thread, the grant it runs within. places
// are a thread's registers in shared memory and threads a thread block's; register_bytes is the shared memory a thread
// block's registers take, the launch's dynamic shared memory, and shared_bytes all a thread block holds, the kernel's
// own beside them; resident is the thread blocks the device holds at once
struct CycleRecord
{
    unsigned int steps;
    unsigned int members;
    unsigned int file_limbs;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
    unsigned int divides;
    unsigned int compiled;
    cudaKernel_t kernel;
    DeviceRecordStep *device_steps;
    unsigned int *device_refused;
    unsigned int *device_tables;
    EngineProgramBlock *block;
    EngineProgramBlock *device_block;
    struct CycleHot *hot;
    unsigned long long registers;
    unsigned long long local_bytes;
    unsigned int places;
    unsigned int threads;
    unsigned long long register_bytes;
    unsigned long long shared_bytes;
    unsigned long long resident;
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

// limb `at` of a register's two's complement: the magnitude's limb, or its complement where the sign is negative,
// with `carry` running the negation's one up the limbs; it starts at 1 and the limbs are taken from the lowest up
__device__ static unsigned int cycle_record_complement(const unsigned int *value, unsigned int limbs, unsigned int at,
                                                       int sign, unsigned long long *carry)
{
    const unsigned int held = cycle_record_limb(value, limbs, at);
    if (sign >= 0)
    {
        return held;
    }
    const unsigned long long total = (unsigned long long)(~held) + *carry;
    *carry = total >> 32u;
    return (unsigned int)(total & 0xFFFFFFFFull);
}

// the xor or the and of two registers' two's complements over `limbs`, read back as a magnitude; returns its sign.
// The sign is the operands': the xor is negative where exactly one is, the and where both are. A negative result has
// the extra bit over the wider operand in its limbs, so its low limbs read back to the magnitude; a result keymath
// narrowed (an and with a register never negative, an xor of two) is never negative and is its low limbs.
__device__ static int cycle_record_bitwise(unsigned int operation, const unsigned int *left, unsigned int left_limbs,
                                          int left_sign, const unsigned int *right, unsigned int right_limbs,
                                          int right_sign, unsigned int *value, unsigned int limbs)
{
    unsigned long long left_carry = 1ull;
    unsigned long long right_carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned int one = cycle_record_complement(left, left_limbs, at, left_sign, &left_carry);
        const unsigned int other = cycle_record_complement(right, right_limbs, at, right_sign, &right_carry);
        value[at] = (operation == ENGINE_RECORD_XOR) ? (one ^ other) : (one & other);
    }
    const int left_negative = (left_sign < 0) ? 1 : 0;
    const int right_negative = (right_sign < 0) ? 1 : 0;
    const int negative = (operation == ENGINE_RECORD_XOR) ? (left_negative ^ right_negative)
                                                          : (left_negative & right_negative);
    if (negative != 0)
    {
        cycle_record_negate(value, limbs, 32u * limbs);
    }
    return (cycle_record_is_zero(value, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a register wrapped to `bits` of two's complement, read back signed as a magnitude over `limbs`; returns its sign.
// keymath gave the step the fewer of the source's bits and the wrap's, so a wrap wider than the step's 32 limbs is a
// source already inside the signed range, passed through, and any other step holds exactly the wrap's limbs.
__device__ static int cycle_record_wrap(const unsigned int *source, unsigned int source_limbs, int source_sign,
                                       unsigned int bits, unsigned int *value, unsigned int limbs)
{
    if (bits > (32u * limbs))
    {
        for (unsigned int at = 0u; at < limbs; at += 1u)
        {
            value[at] = cycle_record_limb(source, source_limbs, at);
        }
        return source_sign;
    }
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = cycle_record_complement(source, source_limbs, at, source_sign, &carry);
    }
    const unsigned int kept = bits - (32u * (limbs - 1u));
    value[limbs - 1u] = (kept < 32u) ? (value[limbs - 1u] & ((1u << kept) - 1u)) : value[limbs - 1u];
    const unsigned int top = bits - 1u;
    const int negative = (((value[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_record_negate(value, limbs, bits);
    }
    return (cycle_record_is_zero(value, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
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
    // the work runs at the numerator's width: a quotient by a constant can be narrower than its numerator, and the
    // multiply back must see the numerator whole
    const unsigned int work = (top_limbs > limbs) ? top_limbs : limbs;
    cycle_record_shift_down(top, top_limbs, low_zeros, numerator, work);
    cycle_record_shift_down(bottom, bottom_limbs, low_zeros, divisor, divisor_used);
    // an odd word is its own inverse to 3 bits, and each step doubles the bits: 6, 12, 24, 48
    unsigned int word = divisor[0];
    for (unsigned int round = 0u; round < 4u; round += 1u)
    {
        word *= 2u - (divisor[0] * word);
    }
    inverse[0] = word;
    for (unsigned int held = 1u; held < work;)
    {
        const unsigned int reach = ((2u * held) < work) ? (2u * held) : work;
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
    // the whole quotient lands in grown; the inverse and its step product then lie together, room for the whole
    // product of the quotient and the divisor
    unsigned int *const whole = grown;
    cycle_record_product(numerator, work, inverse, work, whole, work);
    unsigned int *const back = inverse;
    cycle_record_product(whole, work, divisor, divisor_used, back, work + divisor_used);
    if (cycle_record_compare(back, work + divisor_used, numerator, work) != 0)
    {
        return 0;
    }
    // a quotient past its register's limbs outgrew it
    for (unsigned int at = limbs; at < work; at += 1u)
    {
        if (whole[at] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = whole[at];
    }
    return 1;
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

// one step that reads registers: the left, and the right, where a table reads the left alone (its right names the
// table, not a step). Each operand's sign is read beside it, at its place in the file, and the result's sign is left
// in `held`; `good` falls to 0 for a lane the step refuses.
template <unsigned int WIDE, unsigned int DIVIDES>
__device__ static void cycle_record_operate(const CycleRecordLaunch &launch, const DeviceRecordStep &step,
                                            const unsigned int *file, const signed char *sign, unsigned int *scratch,
                                            unsigned int *value, signed char *held, int *good)
{
    const unsigned int left_place = launch.steps[step.left].place;
    const unsigned int right_place = (step.operation == ENGINE_RECORD_TABLE) ? left_place
                                                                             : launch.steps[step.right].place;
    const unsigned int *const left = &file[left_place];
    const unsigned int *const right = &file[right_place];
    const int left_sign = sign[left_place];
    const int right_sign = sign[right_place];
    if (step.operation == ENGINE_RECORD_PRODUCT)
    {
        cycle_record_product(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
        *held = (signed char)(left_sign * right_sign);
    }
    else if ((step.operation == ENGINE_RECORD_SUM) || (step.operation == ENGINE_RECORD_DIFFERENCE))
    {
        const int addend_sign = (step.operation == ENGINE_RECORD_SUM) ? right_sign : -right_sign;
        if ((left_sign == addend_sign) || (addend_sign == 0) || (left_sign == 0))
        {
            cycle_record_add(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *held = (signed char)((left_sign != 0) ? left_sign : addend_sign);
        }
        else if (cycle_record_compare(left, step.left_limbs, right, step.right_limbs) >= 0)
        {
            cycle_record_subtract(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *held = (signed char)left_sign;
        }
        else
        {
            cycle_record_subtract(right, step.right_limbs, left, step.left_limbs, value, step.limbs);
            *held = (signed char)addend_sign;
        }
        *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : *held;
    }
    else if (step.operation == ENGINE_RECORD_LADDER)
    {
        *good = (right_sign > 0) ? 1 : 0;
        unsigned int band = 0u;
        if (*good != 0)
        {
            cycle_record_ladder<WIDE>(left, step.left_limbs, right, step.right_limbs, &band);
        }
        value[0] = band;
        *held = (band == 0u) ? 0 : (signed char)left_sign;
    }
    else if (step.operation == ENGINE_RECORD_ABSOLUTE)
    {
        for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
        {
            value[limb] = cycle_record_limb(left, step.left_limbs, limb);
        }
        *held = (left_sign != 0) ? 1 : 0;
    }
    else if (step.operation == ENGINE_RECORD_COMPARE)
    {
        const int order = (left_sign != right_sign)
                        ? ((left_sign > right_sign) ? 1 : -1)
                        : (left_sign * cycle_record_compare(left, step.left_limbs, right, step.right_limbs));
        value[0] = (order != 0) ? 1u : 0u;
        *held = (signed char)order;
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
        *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
    }
    else if ((step.operation == ENGINE_RECORD_XOR) || (step.operation == ENGINE_RECORD_AND))
    {
        *held = (signed char)cycle_record_bitwise(step.operation, left, step.left_limbs, left_sign, right,
                                                  step.right_limbs, right_sign, value, step.limbs);
    }
    else if (step.operation == ENGINE_RECORD_WRAP)
    {
        *held = (signed char)cycle_record_wrap(left, step.left_limbs, left_sign, step.wrap_bits, value, step.limbs);
    }
    else if ((DIVIDES != 0u) && (cycle_record_divides(step.operation) != 0))
    {
        int held_sign = 1;
        if (step.operation == ENGINE_RECORD_QUOTIENT)
        {
            *good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, NULL,
                                              0u, scratch);
            held_sign = left_sign * right_sign;
        }
        else if (step.operation == ENGINE_RECORD_REMAINDER)
        {
            *good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, NULL, 0u, value,
                                              step.limbs, scratch);
            held_sign = left_sign;
        }
        else if (step.operation == ENGINE_RECORD_GCD)
        {
            cycle_record_gcd<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, scratch);
        }
        else
        {
            *good = cycle_record_exact_quotient<WIDE>(left, step.left_limbs, right, step.right_limbs, value,
                                                      step.limbs, scratch);
            held_sign = left_sign * right_sign;
        }
        *held = (signed char)((cycle_record_is_zero(value, step.limbs) != 0) ? 0 : held_sign);
    }
    else
    {
        *good = 0;
    }
}

// DIVIDES is 1 for a program holding a division operation, which alone carries the division scratch
template <unsigned int WIDE, unsigned int DIVIDES>
__global__ static void cycle_record_kernel(CycleRecordLaunch launch)
{
    unsigned int file[WIDE];
    unsigned int scratch[(DIVIDES != 0u) ? CYCLE_RECORD_SCRATCH(WIDE) : 1u];
    // a register's sign lies beside it, at its place in the file, so the steps are bounded by nothing held per step
    signed char sign[WIDE];
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
                                          ? (unsigned long long)launch.index[(lane * launch.members) + member]
                                          : ((launch.bodies[member] == 1ull) ? 0ull : lane);
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
            signed char *const held = &sign[step.place];
            if (step.operation == ENGINE_RECORD_FIELD)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
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
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
            }
            else if (step.operation == ENGINE_RECORD_CONSTANT)
            {
                value[0] = step.left;
                if (step.limbs > 1u)
                {
                    value[1] = step.right;
                }
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_LANE)
            {
                for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
                {
                    value[limb] = (limb == 0u) ? (unsigned int)(lane & 0xFFFFFFFFull)
                                               : ((limb == 1u) ? (unsigned int)(lane >> 32u) : 0u);
                }
                *held = (lane == 0ull) ? 0 : 1;
            }
            else
            {
                cycle_record_operate<WIDE, DIVIDES>(launch, step, file, sign, scratch, value, held, &good);
            }
            if ((good != 0) && (step.out_bits != 0u))
            {
                cycle_record_put(record, step.out_offset, step.out_bits, value, step.limbs, *held);
            }
        }
        if (good == 0)
        {
            atomicAdd(launch.refused, 1u);
        }
    }
}

// The record program compiled. Every record operation lives once, in the operator block: a function of its own, the
// interpreter's arithmetic with its widths taken as arguments, compiled by NVRTC once for this device and kept in the
// cache. A program's lane is written first as PTX (cycle_program_ptx): each step unrolled at its widths into
// straight-line assembly over registers the lane holds, or a call into the block for a step that loops on its values,
// and nvJitLink assembles it as it links it against the block, with no compiler between. Where the lane cannot be written
// so, or its PTX does not build, the lane is C source instead, its steps alone, each one call into the block with its
// places and widths as constants over the register file key_schedule laid, file_limbs the most it holds live at once,
// compiled by NVRTC as relocatable code and linked the same way. A program of any length builds either way. The block's
// registers lie in the thread block's shared memory, sized exactly from its widths, and a thread block holds as many
// threads as that shared memory fits; a PTX lane that calls nothing takes none. The interpreter above stays the oracle,
// and the fallback for a program neither way builds, this process cannot load or shared memory cannot hold one
// thread's registers for.
//
// The compiled program runs as a resident program with a block (EngineProgramBlock) in device memory. Its thread blocks
// take lanes a round at a time from one counter, check in to the block as they go, and leave once the launch has run
// its time to live or the block's command says to. The last one out writes where the program stands, and the run
// launches it again from there until every lane is done: a launch never outlives the display driver's watchdog, and no
// lane runs twice. The host reads the block only once a launch has ended. Six switches, read at each load or run:
// CYCLE_RECORD_INTERPRET=1 keeps every program on the interpreter, CYCLE_RECORD_CHECK=1 runs both on every launch and
// refuses the launch where their records or refusals differ, CYCLE_RECORD_REPORT=1 says on stderr where each program
// came from and how long each kernel ran, CYCLE_RECORD_TTL=<microseconds> sets a launch's time to live,
// CYCLE_RECORD_LTO=1 builds the block and the programs as LTO-IR and links them with link-time optimization, which
// writes no PTX, and CYCLE_RECORD_NVRTC=1 writes every lane as C source.

static_assert(ENGINE_RECORD_MEMBERS_MAX == 3u, "cycle: the compiled program's launch holds three members");

// a launch's time to live where CYCLE_RECORD_TTL names none, well inside Windows' 2 s watchdog
#define CYCLE_PROGRAM_TTL_MICROSECONDS 500000ull

// the check-in the scheduler holds a program to, and how often each of its thread blocks checks in within it
#define CYCLE_PROGRAM_WDT_MICROSECONDS 100000ull

#define CYCLE_PROGRAM_CHECKINS_PER_WDT 4ull

static_assert((sizeof(EngineProgramBlock) % 8u) == 0u, "cycle: the block is 64-bit words");
static_assert(sizeof(EngineSignum) == 32u, "cycle: the block's signature is four words");

// what a compiled program's thread blocks share on the device across one run: the next lane to take, and within one
// launch its start, the thread blocks gone and the check-ins made, laid out as the kernel's own (s_cycle_prelude)
struct CycleHot
{
    unsigned long long next_lane;
    unsigned long long launch_start;
    unsigned long long finished;
    unsigned long long checkins;
};

// the compiled program's argument, laid out as the kernel's own (s_cycle_prelude) declares it: the block is the
// program's EngineProgramBlock as 64-bit words, at its device address, and places a thread's registers in shared memory
struct CycleCompiledLaunch
{
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *refused;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    CycleHot *hot;
    unsigned long long *block;
    unsigned long long ttl;
    unsigned long long checkin_every;
    unsigned long long launch_number;
    unsigned long long places;
};

// every program and the operator block open with this: the launch the kernel takes, the lane a program defines, and
// the operators the block defines. A thread's registers are its places: the file, then the scratch the divisions and
// the ladder work in, laid in the thread block's shared memory across its threads. An operator takes the places and
// limbs of its register and its operands, and one that can refuse a lane returns 0 for it
static const char s_cycle_prelude[] = R"CYCLE(
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;

struct CycleHot
{
    u64 next_lane;
    u64 launch_start;
    u64 finished;
    u64 checkins;
};

struct CycleCompiledLaunch
{
    const u32 *in[3];
    const u32 *index;
    const u32 *tables;
    u32 *out;
    u32 *refused;
    u64 bodies[3];
    u64 count;
    CycleHot *hot;
    u64 *block;
    u64 ttl;
    u64 checkin_every;
    u64 launch_number;
    u64 places;
};

extern "C" __device__ void cycle_lane(const CycleCompiledLaunch *launch, u64 lane);

extern "C" __device__ void cycle_field(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs);

extern "C" __device__ void cycle_field_signed(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs);

extern "C" __device__ void cycle_constant(u32 low, u32 high, u32 place, u32 limbs);

extern "C" __device__ void cycle_lane_index(u64 lane, u32 place, u32 limbs);

extern "C" __device__ void cycle_product(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs);

extern "C" __device__ void cycle_sum(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 difference);

extern "C" __device__ int cycle_ladder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                       u32 scratch);

extern "C" __device__ void cycle_absolute(u32 place, u32 limbs, u32 left, u32 left_limbs);

extern "C" __device__ void cycle_compare(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs);

extern "C" __device__ void cycle_table(u32 place, u32 limbs, u32 left, const u32 *tables, u32 table_offset,
                                       u32 index_bits);

extern "C" __device__ void cycle_bitwise(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 exclusive);

extern "C" __device__ void cycle_wrap(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 bits);

extern "C" __device__ int cycle_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 scratch, u32 wide);

extern "C" __device__ int cycle_remainder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                          u32 scratch, u32 wide);

extern "C" __device__ void cycle_gcd(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 scratch, u32 wide);

extern "C" __device__ int cycle_exact_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right,
                                               u32 right_limbs, u32 scratch, u32 wide);

extern "C" __device__ void cycle_put(u32 *record, u32 out_limbs, u32 offset, u32 bits, u32 place, u32 limbs);
)CYCLE";

// The operator block: every record operation, each the interpreter's own arithmetic with its widths taken at run time,
// and the resident kernel that runs a program's lanes. A thread's registers lie in the thread block's shared memory,
// laid across its threads: place p of thread t is word p * threads + t, so a warp reading one place reads 32
// consecutive words, one to a bank. Each access translates its place by that one multiply-add, and every operator reads
// the shared array itself, so the device reads it as shared memory. A thread's signs follow its places, one byte a
// place of the file, laid the same way. The divisions and the ladder work in the scratch places the program names,
// laid as the interpreter lays its own at `wide` limbs: wide is at least every width the step reads or writes
static const char s_cycle_operators[] = R"CYCLE(
// the places, the file's then the scratch's, and the signs after them
extern __shared__ u32 cycle_words[];

// a thread's places, set by the kernel before any lane runs
__shared__ u32 cycle_places;

// a place's word for this thread and a place's sign
__device__ __forceinline__ static u32 &cycle_word(u32 place)
{
    return cycle_words[(place * blockDim.x) + threadIdx.x];
}

__device__ __forceinline__ static s8 &cycle_sign(u32 place)
{
    // the signs are bytes after every place's word, read back as bytes of the same shared array
    s8 *const signs = (s8 *)&cycle_words[cycle_places * blockDim.x];
    return signs[(place * blockDim.x) + threadIdx.x];
}

// the device's timer, in nanoseconds
__device__ __forceinline__ static u64 cycle_clock(void)
{
    u64 now;
    asm volatile("mov.u64 %0, %%globaltimer;" : "=l"(now));
    return now;
}

__device__ __forceinline__ static u32 cycle_limb(u32 value, u32 limbs, u32 at)
{
    return (at < limbs) ? cycle_word(value + at) : 0u;
}

__device__ static int cycle_order(u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    u32 at = (left_limbs > right_limbs) ? left_limbs : right_limbs;
    while (at > 0u)
    {
        at -= 1u;
        const u32 one = cycle_limb(left, left_limbs, at);
        const u32 other = cycle_limb(right, right_limbs, at);
        if (one != other)
        {
            return (one < other) ? -1 : 1;
        }
    }
    return 0;
}

__device__ static int cycle_is_zero(u32 value, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        if (cycle_word(value + at) != 0u)
        {
            return 0;
        }
    }
    return 1;
}

// a limb of an atom, which lies in device memory
__device__ __forceinline__ static u32 cycle_atom_limb(const u32 *atom, u32 in_limbs, u32 at)
{
    return (at < in_limbs) ? atom[at] : 0u;
}

__device__ static void cycle_gather(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 value, u32 limbs)
{
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        const u32 bit = offset + (32u * limb);
        const u32 word = bit / 32u;
        const u32 shift = bit % 32u;
        u32 gathered = cycle_atom_limb(atom, in_limbs, word) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_atom_limb(atom, in_limbs, word + 1u) << (32u - shift);
        }
        const u32 left = bits - (32u * limb);
        cycle_word(value + limb) = (left < 32u) ? (gathered & ((1u << left) - 1u)) : gathered;
    }
}

__device__ static void cycle_negate(u32 value, u32 limbs, u32 bits)
{
    u64 carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (u64)(~cycle_word(value + at)) + carry;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    const u32 left = bits - (32u * (limbs - 1u));
    const u32 top = cycle_word(value + limbs - 1u);
    cycle_word(value + limbs - 1u) = (left < 32u) ? (top & ((1u << left) - 1u)) : top;
}

// limb `at` of a register's two's complement: the magnitude's limb, or its complement where the sign is negative,
// with `carry` running the negation's one up the limbs; it starts at 1 and the limbs are taken from the lowest up
__device__ static u32 cycle_complement(u32 value, u32 limbs, u32 at, int sign, u64 *carry)
{
    const u32 held = cycle_limb(value, limbs, at);
    if (sign >= 0)
    {
        return held;
    }
    const u64 total = (u64)(~held) + *carry;
    *carry = total >> 32u;
    return (u32)(total & 0xFFFFFFFFull);
}

__device__ static void cycle_add(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    u64 carry = 0ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (u64)cycle_limb(left, left_limbs, at) + (u64)cycle_limb(right, right_limbs, at) + carry;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static void cycle_subtract(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    u64 borrow = 0ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (1ull << 32u) + (u64)cycle_limb(left, left_limbs, at) - (u64)cycle_limb(right, right_limbs, at)
                        - borrow;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__device__ static void cycle_multiply(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = 0u;
    }
    for (u32 low = 0u; low < left_limbs; low += 1u)
    {
        u64 carry = 0ull;
        const u64 multiplier = (u64)cycle_word(left + low);
        for (u32 high = 0u; (high < right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const u64 total = (multiplier * (u64)cycle_word(right + high)) + (u64)cycle_word(value + low + high) + carry;
            cycle_word(value + low + high) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        for (u32 at = low + right_limbs; (carry != 0ull) && (at < limbs); at += 1u)
        {
            const u64 total = (u64)cycle_word(value + at) + carry;
            cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

__device__ static u32 cycle_used(u32 value, u32 limbs)
{
    while ((limbs > 0u) && (cycle_word(value + limbs - 1u) == 0u))
    {
        limbs -= 1u;
    }
    return limbs;
}

// value shifted toward the low end by `bits` (below 32 times its limbs), into `limbs` of out
__device__ static void cycle_shift_down(u32 value, u32 value_limbs, u32 bits, u32 out, u32 limbs)
{
    const u32 words = bits / 32u;
    const u32 shift = bits % 32u;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        u32 gathered = cycle_limb(value, value_limbs, at + words) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_limb(value, value_limbs, at + words + 1u) << (32u - shift);
        }
        cycle_word(out + at) = gathered;
    }
}

// a place that names no register: a division's quotient or rest left out
#define CYCLE_NO_PLACE 0xFFFFFFFFu

// Knuth's Algorithm D on the magnitudes: top = quotient . bottom + rest, each output kept to its own limbs and either
// one left out where it is CYCLE_NO_PLACE; 0 for a zero divisor. scratch holds 2 * wide + 2 limbs.
__device__ static int cycle_divide(u32 top, u32 top_limbs, u32 bottom, u32 bottom_limbs, u32 quotient,
                                   u32 quotient_limbs, u32 rest, u32 rest_limbs, u32 scratch, u32 wide)
{
    const u32 divisor_used = cycle_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    const u32 numerator_used = cycle_used(top, top_limbs);
    for (u32 at = 0u; (quotient != CYCLE_NO_PLACE) && (at < quotient_limbs); at += 1u)
    {
        cycle_word(quotient + at) = 0u;
    }
    if (numerator_used < divisor_used)
    {
        for (u32 at = 0u; (rest != CYCLE_NO_PLACE) && (at < rest_limbs); at += 1u)
        {
            cycle_word(rest + at) = cycle_limb(top, numerator_used, at);
        }
        return 1;
    }
    if (divisor_used == 1u)
    {
        const u64 divisor = (u64)cycle_word(bottom);
        u64 carried = 0ull;
        for (u32 at = numerator_used; at > 0u; at -= 1u)
        {
            const u64 part = (carried << 32u) | (u64)cycle_word(top + at - 1u);
            if ((quotient != CYCLE_NO_PLACE) && ((at - 1u) < quotient_limbs))
            {
                cycle_word(quotient + at - 1u) = (u32)(part / divisor);
            }
            carried = part % divisor;
        }
        for (u32 at = 0u; (rest != CYCLE_NO_PLACE) && (at < rest_limbs); at += 1u)
        {
            cycle_word(rest + at) = (at == 0u) ? (u32)carried : 0u;
        }
        return 1;
    }
    const u32 numerator = scratch;
    const u32 divisor = scratch + wide + 2u;
    const u32 shift = (u32)__clz(cycle_word(bottom + divisor_used - 1u));
    for (u32 at = 0u; at < divisor_used; at += 1u)
    {
        const u32 below = ((shift != 0u) && (at > 0u)) ? (cycle_word(bottom + at - 1u) >> (32u - shift)) : 0u;
        cycle_word(divisor + at) = (cycle_word(bottom + at) << shift) | below;
    }
    for (u32 at = 0u; at <= numerator_used; at += 1u)
    {
        const u32 here = cycle_limb(top, numerator_used, at);
        const u32 below = ((shift != 0u) && (at > 0u)) ? (cycle_word(top + at - 1u) >> (32u - shift)) : 0u;
        cycle_word(numerator + at) = (here << shift) | below;
    }
    const u64 lead = (u64)cycle_word(divisor + divisor_used - 1u);
    const u64 next = (u64)cycle_word(divisor + divisor_used - 2u);
    for (u32 place = numerator_used - divisor_used + 1u; place > 0u; place -= 1u)
    {
        const u32 at = place - 1u;
        const u64 part = ((u64)cycle_word(numerator + at + divisor_used) << 32u)
                       | (u64)cycle_word(numerator + at + divisor_used - 1u);
        u64 guess = part / lead;
        u64 over = part % lead;
        while (((guess >> 32u) != 0ull)
               || ((guess * next) > ((over << 32u) | (u64)cycle_word(numerator + at + divisor_used - 2u))))
        {
            guess -= 1ull;
            over += lead;
            if ((over >> 32u) != 0ull)
            {
                break;
            }
        }
        u64 borrow = 0ull;
        for (u32 limb = 0u; limb < divisor_used; limb += 1u)
        {
            const u64 taken = (guess * (u64)cycle_word(divisor + limb)) + borrow;
            const u64 held = (u64)cycle_word(numerator + at + limb);
            cycle_word(numerator + at + limb) = (u32)((held - (taken & 0xFFFFFFFFull)) & 0xFFFFFFFFull);
            borrow = (taken >> 32u) + ((held < (taken & 0xFFFFFFFFull)) ? 1ull : 0ull);
        }
        const u64 held = (u64)cycle_word(numerator + at + divisor_used);
        cycle_word(numerator + at + divisor_used) = (u32)((held - borrow) & 0xFFFFFFFFull);
        if (held < borrow)
        {
            // the guess was one too many (Knuth D6): add the divisor back
            guess -= 1ull;
            u64 carry = 0ull;
            for (u32 limb = 0u; limb < divisor_used; limb += 1u)
            {
                const u64 total = (u64)cycle_word(numerator + at + limb) + (u64)cycle_word(divisor + limb) + carry;
                cycle_word(numerator + at + limb) = (u32)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
            cycle_word(numerator + at + divisor_used)
                = (u32)((cycle_word(numerator + at + divisor_used) + carry) & 0xFFFFFFFFull);
        }
        if ((quotient != CYCLE_NO_PLACE) && (at < quotient_limbs))
        {
            cycle_word(quotient + at) = (u32)guess;
        }
    }
    if (rest != CYCLE_NO_PLACE)
    {
        cycle_shift_down(numerator, divisor_used + 1u, shift, rest, rest_limbs);
        for (u32 at = divisor_used; at < rest_limbs; at += 1u)
        {
            cycle_word(rest + at) = 0u;
        }
    }
    return 1;
}

// Euclid's gcd of the magnitudes by the long division above, into `limbs` of value; scratch holds 5 * wide + 2
__device__ static void cycle_euclid(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs,
                                    u32 scratch, u32 wide)
{
    u32 larger = scratch;
    u32 smaller = scratch + wide;
    u32 rest = scratch + (2u * wide);
    for (u32 at = 0u; at < wide; at += 1u)
    {
        cycle_word(larger + at) = cycle_limb(left, left_limbs, at);
        cycle_word(smaller + at) = cycle_limb(right, right_limbs, at);
    }
    while (cycle_used(smaller, wide) != 0u)
    {
        cycle_divide(larger, wide, smaller, wide, CYCLE_NO_PLACE, 0u, rest, wide, scratch + (3u * wide), wide);
        const u32 held = larger;
        larger = smaller;
        smaller = rest;
        rest = held;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = cycle_word(larger + at);
    }
}

// the quotient of an exact division by a multiply with the divisor's inverse and a mask: both are shifted past the
// divisor's low zero bits, the odd divisor's inverse modulo 2^(32 limbs) is grown by Newton's x(2 - dx) from one word,
// and the quotient is the low limbs of numerator . inverse; multiplying back proves it. 0 for a zero divisor or a
// remainder. scratch holds 5 * wide limbs.
__device__ static int cycle_inverse_quotient(u32 top, u32 top_limbs, u32 bottom, u32 bottom_limbs, u32 value,
                                             u32 limbs, u32 scratch, u32 wide)
{
    const u32 divisor_used = cycle_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = 0u;
    }
    if (cycle_used(top, top_limbs) == 0u)
    {
        return 1;
    }
    u32 low_zeros = 0u;
    while (cycle_word(bottom + (low_zeros / 32u)) == 0u)
    {
        low_zeros += 32u;
    }
    low_zeros += (u32)(__ffs((int)cycle_word(bottom + (low_zeros / 32u))) - 1);
    for (u32 bit = 0u; bit < low_zeros; bit += 1u)
    {
        if (((cycle_limb(top, top_limbs, bit / 32u) >> (bit % 32u)) & 1u) != 0u)
        {
            return 0;
        }
    }
    const u32 numerator = scratch;
    const u32 divisor = scratch + wide;
    const u32 inverse = scratch + (2u * wide);
    const u32 stepped = scratch + (3u * wide);
    const u32 grown = scratch + (4u * wide);
    // the work runs at the numerator's width: a quotient by a constant can be narrower than its numerator, and the
    // multiply back must see the numerator whole
    const u32 work = (top_limbs > limbs) ? top_limbs : limbs;
    cycle_shift_down(top, top_limbs, low_zeros, numerator, work);
    cycle_shift_down(bottom, bottom_limbs, low_zeros, divisor, divisor_used);
    // an odd word is its own inverse to 3 bits, and each step doubles the bits: 6, 12, 24, 48
    const u32 odd = cycle_word(divisor);
    u32 word = odd;
    for (u32 round = 0u; round < 4u; round += 1u)
    {
        word *= 2u - (odd * word);
    }
    cycle_word(inverse) = word;
    for (u32 held = 1u; held < work;)
    {
        const u32 reach = ((2u * held) < work) ? (2u * held) : work;
        cycle_multiply(divisor, (divisor_used < reach) ? divisor_used : reach, inverse, held, stepped, reach);
        // 2 - d x modulo 2^(32 reach): the two's complement of d x, plus 2
        u64 carry = 2ull;
        for (u32 at = 0u; at < reach; at += 1u)
        {
            const u64 total = (u64)(~cycle_word(stepped + at)) + ((at == 0u) ? 1ull : 0ull) + carry;
            cycle_word(stepped + at) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        cycle_multiply(inverse, held, stepped, reach, grown, reach);
        for (u32 at = 0u; at < reach; at += 1u)
        {
            cycle_word(inverse + at) = cycle_word(grown + at);
        }
        held = reach;
    }
    // the whole quotient lands in grown; the inverse and its step product then lie together, room for the whole
    // product of the quotient and the divisor
    const u32 whole = grown;
    cycle_multiply(numerator, work, inverse, work, whole, work);
    const u32 back = inverse;
    cycle_multiply(whole, work, divisor, divisor_used, back, work + divisor_used);
    if (cycle_order(back, work + divisor_used, numerator, work) != 0)
    {
        return 0;
    }
    // a quotient past its register's limbs outgrew it
    for (u32 at = limbs; at < work; at += 1u)
    {
        if (cycle_word(whole + at) != 0u)
        {
            return 0;
        }
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = cycle_word(whole + at);
    }
    return 1;
}

extern "C" __device__ void cycle_field(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    cycle_gather(atom, in_limbs, offset, bits, place, limbs);
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

extern "C" __device__ void cycle_field_signed(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    cycle_gather(atom, in_limbs, offset, bits, place, limbs);
    const u32 top = bits - 1u;
    const int negative = (((cycle_word(place + (top / 32u)) >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_negate(place, limbs, bits);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a constant's two words, and every limb above them cleared
extern "C" __device__ void cycle_constant(u32 low, u32 high, u32 place, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? low : ((at == 1u) ? high : 0u);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

// the lane's own number, its two words and every limb above them cleared; never negative
extern "C" __device__ void cycle_lane_index(u64 lane, u32 place, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? (u32)(lane & 0xFFFFFFFFull) : ((at == 1u) ? (u32)(lane >> 32u) : 0u);
    }
    cycle_sign(place) = (lane == 0ull) ? 0 : 1;
}

extern "C" __device__ void cycle_product(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    cycle_multiply(left, left_limbs, right, right_limbs, place, limbs);
    cycle_sign(place) = (s8)(left_sign * right_sign);
}

extern "C" __device__ void cycle_sum(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 difference)
{
    const int left_sign = cycle_sign(left);
    const int addend_sign = (difference != 0u) ? -cycle_sign(right) : cycle_sign(right);
    int held = 0;
    if ((left_sign == addend_sign) || (addend_sign == 0) || (left_sign == 0))
    {
        cycle_add(left, left_limbs, right, right_limbs, place, limbs);
        held = (left_sign != 0) ? left_sign : addend_sign;
    }
    else if (cycle_order(left, left_limbs, right, right_limbs) >= 0)
    {
        cycle_subtract(left, left_limbs, right, right_limbs, place, limbs);
        held = left_sign;
    }
    else
    {
        cycle_subtract(right, right_limbs, left, left_limbs, place, limbs);
        held = addend_sign;
    }
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
}

// the golden ladder's band: the rungs of the Fibonacci numbers whose multiple of the right stays at or below the left.
// A right that is not positive refuses the lane; the band is its register's low limb, every limb above cleared. The
// rung's two words lie at the scratch's first two places and its multiple after them
extern "C" __device__ int cycle_ladder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                       u32 scratch)
{
    const int left_sign = cycle_sign(left);
    const int good = (cycle_sign(right) > 0) ? 1 : 0;
    const u32 reached = scratch + 2u;
    u32 band = 0u;
    u64 lower = 0ull;
    u64 upper = 1ull;
    int below = good;
    for (u32 rung = 1u; (below != 0) && (rung < CYCLE_GOLDEN_RUNGS); rung += 1u)
    {
        cycle_word(scratch) = (u32)(upper & 0xFFFFFFFFull);
        cycle_word(scratch + 1u) = (u32)(upper >> 32u);
        cycle_multiply(right, right_limbs, scratch, 2u, reached, right_limbs + 2u);
        below = (cycle_order(reached, right_limbs + 2u, left, left_limbs) <= 0) ? 1 : 0;
        band += (u32)below;
        const u64 next = lower + upper;
        lower = upper;
        upper = next;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? band : 0u;
    }
    cycle_sign(place) = (band == 0u) ? 0 : (s8)left_sign;
    return good;
}

extern "C" __device__ void cycle_absolute(u32 place, u32 limbs, u32 left, u32 left_limbs)
{
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_word(place + limb) = cycle_limb(left, left_limbs, limb);
    }
    cycle_sign(place) = (cycle_sign(left) != 0) ? 1 : 0;
}

// the order of two signed registers: its sign is the step's, and its low limb 1 where they differ
extern "C" __device__ void cycle_compare(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    const int order = (left_sign != right_sign)
                    ? ((left_sign > right_sign) ? 1 : -1)
                    : (left_sign * cycle_order(left, left_limbs, right, right_limbs));
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? ((order != 0) ? 1u : 0u) : 0u;
    }
    cycle_sign(place) = (s8)order;
}

// the low index_bits of the source register (index_bits <= 32, one limb) select a row of the program's tables
extern "C" __device__ void cycle_table(u32 place, u32 limbs, u32 left, const u32 *tables, u32 table_offset,
                                       u32 index_bits)
{
    const u32 source = cycle_word(left);
    const u32 index = (index_bits >= 32u) ? source : (source & ((1u << index_bits) - 1u));
    const u32 *const entry = &tables[table_offset + (index * limbs)];
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_word(place + limb) = entry[limb];
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

// the xor (exclusive) or the and of two registers' two's complements over `limbs`, read back as a magnitude. The sign
// is the operands': the xor is negative where exactly one is, the and where both are. A negative result has the
// extra bit over the wider operand in its limbs, so its low limbs read back to the magnitude.
extern "C" __device__ void cycle_bitwise(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 exclusive)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    u64 left_carry = 1ull;
    u64 right_carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u32 one = cycle_complement(left, left_limbs, at, left_sign, &left_carry);
        const u32 other = cycle_complement(right, right_limbs, at, right_sign, &right_carry);
        cycle_word(place + at) = (exclusive != 0u) ? (one ^ other) : (one & other);
    }
    const int left_negative = (left_sign < 0) ? 1 : 0;
    const int right_negative = (right_sign < 0) ? 1 : 0;
    const int negative = (exclusive != 0u) ? (left_negative ^ right_negative) : (left_negative & right_negative);
    if (negative != 0)
    {
        cycle_negate(place, limbs, 32u * limbs);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a register wrapped to `bits` of two's complement, read back signed as a magnitude over `limbs`. keymath gave the step
// the fewer of the source's bits and the wrap's, so a wrap wider than the step's 32 limbs is a source already inside
// the signed range, passed through, and any other step holds exactly the wrap's limbs.
extern "C" __device__ void cycle_wrap(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 bits)
{
    const int left_sign = cycle_sign(left);
    if (bits > (32u * limbs))
    {
        for (u32 at = 0u; at < limbs; at += 1u)
        {
            cycle_word(place + at) = cycle_limb(left, left_limbs, at);
        }
        cycle_sign(place) = (s8)left_sign;
        return;
    }
    u64 carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = cycle_complement(left, left_limbs, at, left_sign, &carry);
    }
    const u32 kept = bits - (32u * (limbs - 1u));
    const u32 high = cycle_word(place + limbs - 1u);
    cycle_word(place + limbs - 1u) = (kept < 32u) ? (high & ((1u << kept) - 1u)) : high;
    const u32 top = bits - 1u;
    const int negative = (((cycle_word(place + (top / 32u)) >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_negate(place, limbs, bits);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

extern "C" __device__ int cycle_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 scratch, u32 wide)
{
    const int held = cycle_sign(left) * cycle_sign(right);
    const int good = cycle_divide(left, left_limbs, right, right_limbs, place, limbs, CYCLE_NO_PLACE, 0u, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

extern "C" __device__ int cycle_remainder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                          u32 scratch, u32 wide)
{
    const int held = cycle_sign(left);
    const int good = cycle_divide(left, left_limbs, right, right_limbs, CYCLE_NO_PLACE, 0u, place, limbs, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

extern "C" __device__ void cycle_gcd(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 scratch, u32 wide)
{
    cycle_euclid(left, left_limbs, right, right_limbs, place, limbs, scratch, wide);
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

extern "C" __device__ int cycle_exact_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right,
                                               u32 right_limbs, u32 scratch, u32 wide)
{
    const int held = cycle_sign(left) * cycle_sign(right);
    const int good = cycle_inverse_quotient(left, left_limbs, right, right_limbs, place, limbs, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

// the register's low `bits` bits, as two's complement where its sign is negative, laid into the record at `offset`
extern "C" __device__ void cycle_put(u32 *record, u32 out_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    const int negative = (cycle_sign(place) < 0) ? 1 : 0;
    const u32 words = (bits + 31u) / 32u;
    const u32 top = bits - (32u * (words - 1u));
    const u32 first = offset / 32u;
    const u32 shift = offset % 32u;
    u64 carry = 1ull;
    for (u32 at = 0u; at < words; at += 1u)
    {
        u32 word = cycle_limb(place, limbs, at);
        if (negative != 0)
        {
            const u64 total = (u64)(~word) + carry;
            word = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        word = ((at == (words - 1u)) && (top < 32u)) ? (word & ((1u << top) - 1u)) : word;
        if ((first + at) < out_limbs)
        {
            record[first + at] |= word << shift;
        }
        if ((shift != 0u) && ((first + at + 1u) < out_limbs))
        {
            record[first + at + 1u] |= word >> (32u - shift);
        }
    }
}

// The program resident: each thread block takes the next round of lanes from the one counter, and before each round
// its first thread reads the clock. Past the launch's time to live, or told by the block's command, the thread block
// leaves without taking more; every so often it checks in to the block. The thread block that opens the launch runs
// one round before the clock can send it out, so every launch moves the program on however short its time to live. A
// launch that does not find its number as the block's owner leaves at once and writes nothing. The last thread block
// out writes where the program stands, its state last.
extern "C" __global__ void __launch_bounds__(256) cycle_program(CycleCompiledLaunch launch)
{
    __shared__ u64 claimed;
    volatile u64 *const block = launch.block;
    u64 checked = 0ull;
    u64 rounds = 0ull;
    int opened = 0;
    if (threadIdx.x == 0u)
    {
        // a program's places are its record's file and scratch limbs, far under 2^32
        cycle_places = (u32)launch.places;
        opened = (atomicCAS(&launch.hot->launch_start, 0ull, cycle_clock()) == 0ull) ? 1 : 0;
    }
    for (;;)
    {
        if (threadIdx.x == 0u)
        {
            const u64 now = cycle_clock();
            const u64 ran = now - *(volatile u64 *)&launch.hot->launch_start;
            int leave = (((opened == 0) || (rounds != 0ull)) && (ran >= launch.ttl)) ? 1 : 0;
            if ((now - checked) >= launch.checkin_every)
            {
                checked = now;
                const int owned = (block[CYCLE_BLOCK_OWNER] == launch.launch_number) ? 1 : 0;
                leave = ((owned == 0) || (block[CYCLE_BLOCK_COMMAND] != CYCLE_PROGRAM_RUN)) ? 1 : leave;
                if (owned != 0)
                {
                    const u64 next = *(volatile u64 *)&launch.hot->next_lane;
                    block[CYCLE_BLOCK_CHECKIN] = atomicAdd(&launch.hot->checkins, 1ull) + 1ull;
                    block[CYCLE_BLOCK_CHECKIN_TIME] = now;
                    block[CYCLE_BLOCK_OFFSET] = (next < launch.count) ? next : launch.count;
                }
            }
            claimed = (leave != 0) ? launch.count : atomicAdd(&launch.hot->next_lane, (u64)blockDim.x);
            rounds += 1ull;
        }
        __syncthreads();
        const u64 first = claimed;
        __syncthreads();
        if (first >= launch.count)
        {
            break;
        }
        if ((first + threadIdx.x) < launch.count)
        {
            cycle_lane(&launch, first + threadIdx.x);
        }
    }
    if (threadIdx.x == 0u)
    {
        __threadfence();
        if (atomicAdd(&launch.hot->finished, 1ull) == ((u64)gridDim.x - 1ull))
        {
            const u64 now = cycle_clock();
            const u64 next = *(volatile u64 *)&launch.hot->next_lane;
            const u64 start = *(volatile u64 *)&launch.hot->launch_start;
            if (block[CYCLE_BLOCK_OWNER] == launch.launch_number)
            {
                const u64 command = block[CYCLE_BLOCK_COMMAND];
                block[CYCLE_BLOCK_OFFSET] = (next < launch.count) ? next : launch.count;
                block[CYCLE_BLOCK_STEP] = 0ull;
                block[CYCLE_BLOCK_LAUNCH_TIME] = start;
                block[CYCLE_BLOCK_EXECTIME] = now - start;
                block[CYCLE_BLOCK_CHECKIN] = atomicAdd(&launch.hot->checkins, 1ull) + 1ull;
                block[CYCLE_BLOCK_CHECKIN_TIME] = now;
                __threadfence();
                block[CYCLE_BLOCK_STATE] = (next >= launch.count) ? CYCLE_PROGRAM_DONE
                                         : ((command == CYCLE_PROGRAM_STOP) ? CYCLE_PROGRAM_STOPPED
                                                                            : CYCLE_PROGRAM_YIELDED);
                __threadfence();
            }
        }
    }
}
)CYCLE";

// NVRTC, loaded once a process first compiles
struct CycleCompiler
{
    int tried;
    int ready;
    int major;
    int minor;
    decltype(&nvrtcCreateProgram) create;
    decltype(&nvrtcCompileProgram) compile;
    decltype(&nvrtcGetCUBINSize) cubin_size;
    decltype(&nvrtcGetCUBIN) cubin;
    decltype(&nvrtcGetLTOIRSize) ltoir_size;
    decltype(&nvrtcGetLTOIR) ltoir;
    // PTX is read once a process, for its header alone (cycle_ptx_header); an NVRTC without it leaves every program's
    // lane to the C source
    decltype(&nvrtcGetPTXSize) ptx_size;
    decltype(&nvrtcGetPTX) ptx;
    decltype(&nvrtcGetProgramLogSize) log_size;
    decltype(&nvrtcGetProgramLog) log;
    decltype(&nvrtcDestroyProgram) destroy;
};

static CycleCompiler s_cycle_compiler;

// nvJitLink, loaded once a process first links: each call by the versioned name the header was built against
struct CycleLinker
{
    int tried;
    int ready;
    decltype(&nvJitLinkCreate) create;
    decltype(&nvJitLinkAddData) add;
    decltype(&nvJitLinkComplete) complete;
    decltype(&nvJitLinkGetLinkedCubinSize) cubin_size;
    decltype(&nvJitLinkGetLinkedCubin) cubin;
    decltype(&nvJitLinkGetErrorLogSize) log_size;
    decltype(&nvJitLinkGetErrorLog) log;
    decltype(&nvJitLinkDestroy) destroy;
};

static CycleLinker s_cycle_linker;

// the operator block for one device and one kind of link, built once a process: its source, and the relocatable
// cubin or LTO-IR every program is linked against. hash names the block in each program's source, so a program's
// cubin is found in the cache only against the block it was linked with
struct CycleOperatorBlock
{
    int tried;
    int ready;
    int major;
    int minor;
    unsigned long long hash;
    std::string source;
    std::vector<char> image;
};

// the block for relocatable cubin, then the block for LTO-IR
static CycleOperatorBlock s_cycle_operator_blocks[2];

// a program compiled in this process, found again by its whole source, and the records loaded that hold it: the last
// one released unloads it
struct CycleCompiledProgram
{
    std::string source;
    cudaLibrary_t library;
    cudaKernel_t kernel;
    unsigned long long holders;
};

static std::vector<CycleCompiledProgram> s_cycle_programs;

static int cycle_environment_set(const char *name)
{
    const char *const value = getenv(name);
    return ((value != NULL) && (value[0] == '1')) ? 1 : 0;
}

// a count of microseconds the environment names, or `otherwise` where it names none or one that is not a whole number
static unsigned long long cycle_environment_microseconds(const char *name, unsigned long long otherwise)
{
    const char *const value = getenv(name);
    if ((value == NULL) || (value[0] < '0') || (value[0] > '9'))
    {
        return otherwise;
    }
    char *end = NULL;
    const unsigned long long named = strtoull(value, &end, 10);
    return ((end != NULL) && (*end == '\0')) ? named : otherwise;
}

static void cycle_emit(std::string &text, const char *format, ...)
{
    char line[512];
    va_list arguments;
    va_start(arguments, format);
    const int written = vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    // a line the room does not hold is cut, and the source then fails to compile rather than run wrong; written is
    // read as a size only once it is known positive
    text.append(line, ((written > 0) && ((size_t)written < sizeof(line))) ? (size_t)written : sizeof(line) - 1u);
}

static void *cycle_compiler_symbol(void *library, const char *name)
{
#if defined(_WIN32)
    // a symbol's address is the function it names, held as a plain pointer until it is cast back to that function
    return (void *)GetProcAddress((HMODULE)library, name);
#else
    return dlsym(library, name);
#endif
}

static int cycle_compiler_ready(void)
{
    CycleCompiler *const compiler = &s_cycle_compiler;
    if (compiler->tried != 0)
    {
        return compiler->ready;
    }
    compiler->tried = 1;
    char name[64];
#if defined(_WIN32)
    snprintf(name, sizeof(name), "nvrtc64_%d0_0.dll", CUDART_VERSION / 1000);
    // a module handle is held as a plain pointer beside the Linux one
    void *const library = (void *)LoadLibraryA(name);
#else
    snprintf(name, sizeof(name), "libnvrtc.so.%d", CUDART_VERSION / 1000);
    void *library = dlopen(name, RTLD_NOW);
    library = (library != NULL) ? library : dlopen("libnvrtc.so", RTLD_NOW);
#endif
    if (library == NULL)
    {
        return 0;
    }
    // each symbol's address is cast back to the function NVRTC's header gives it
    const decltype(&nvrtcVersion) version = (decltype(&nvrtcVersion))cycle_compiler_symbol(library, "nvrtcVersion");
    compiler->create = (decltype(&nvrtcCreateProgram))cycle_compiler_symbol(library, "nvrtcCreateProgram");
    compiler->compile = (decltype(&nvrtcCompileProgram))cycle_compiler_symbol(library, "nvrtcCompileProgram");
    compiler->cubin_size = (decltype(&nvrtcGetCUBINSize))cycle_compiler_symbol(library, "nvrtcGetCUBINSize");
    compiler->cubin = (decltype(&nvrtcGetCUBIN))cycle_compiler_symbol(library, "nvrtcGetCUBIN");
    compiler->ltoir_size = (decltype(&nvrtcGetLTOIRSize))cycle_compiler_symbol(library, "nvrtcGetLTOIRSize");
    compiler->ltoir = (decltype(&nvrtcGetLTOIR))cycle_compiler_symbol(library, "nvrtcGetLTOIR");
    compiler->ptx_size = (decltype(&nvrtcGetPTXSize))cycle_compiler_symbol(library, "nvrtcGetPTXSize");
    compiler->ptx = (decltype(&nvrtcGetPTX))cycle_compiler_symbol(library, "nvrtcGetPTX");
    compiler->log_size = (decltype(&nvrtcGetProgramLogSize))cycle_compiler_symbol(library, "nvrtcGetProgramLogSize");
    compiler->log = (decltype(&nvrtcGetProgramLog))cycle_compiler_symbol(library, "nvrtcGetProgramLog");
    compiler->destroy = (decltype(&nvrtcDestroyProgram))cycle_compiler_symbol(library, "nvrtcDestroyProgram");
    compiler->ready = (version != NULL) && (compiler->create != NULL) && (compiler->compile != NULL)
                   && (compiler->cubin_size != NULL) && (compiler->cubin != NULL) && (compiler->ltoir_size != NULL)
                   && (compiler->ltoir != NULL) && (compiler->log_size != NULL) && (compiler->log != NULL)
                   && (compiler->destroy != NULL) && (version(&compiler->major, &compiler->minor) == NVRTC_SUCCESS);
    return compiler->ready;
}

// one nvJitLink call by its versioned name, __nvJitLink<call>_<major>_<minor> of the toolkit built against
static void *cycle_linker_symbol(void *library, const char *call)
{
    char name[64];
    snprintf(name, sizeof(name), "__nvJitLink%s_%d_%d", call, CUDART_VERSION / 1000, (CUDART_VERSION % 1000) / 10);
    return cycle_compiler_symbol(library, name);
}

static int cycle_linker_ready(void)
{
    CycleLinker *const linker = &s_cycle_linker;
    if (linker->tried != 0)
    {
        return linker->ready;
    }
    linker->tried = 1;
    char name[64];
#if defined(_WIN32)
    snprintf(name, sizeof(name), "nvJitLink_%d0_0.dll", CUDART_VERSION / 1000);
    // a module handle is held as a plain pointer beside the Linux one
    void *const library = (void *)LoadLibraryA(name);
#else
    snprintf(name, sizeof(name), "libnvJitLink.so.%d", CUDART_VERSION / 1000);
    void *library = dlopen(name, RTLD_NOW);
    library = (library != NULL) ? library : dlopen("libnvJitLink.so", RTLD_NOW);
#endif
    if (library == NULL)
    {
        return 0;
    }
    // each symbol's address is cast back to the function nvJitLink's header gives it
    linker->create = (decltype(&nvJitLinkCreate))cycle_linker_symbol(library, "Create");
    linker->add = (decltype(&nvJitLinkAddData))cycle_linker_symbol(library, "AddData");
    linker->complete = (decltype(&nvJitLinkComplete))cycle_linker_symbol(library, "Complete");
    linker->cubin_size = (decltype(&nvJitLinkGetLinkedCubinSize))cycle_linker_symbol(library, "GetLinkedCubinSize");
    linker->cubin = (decltype(&nvJitLinkGetLinkedCubin))cycle_linker_symbol(library, "GetLinkedCubin");
    linker->log_size = (decltype(&nvJitLinkGetErrorLogSize))cycle_linker_symbol(library, "GetErrorLogSize");
    linker->log = (decltype(&nvJitLinkGetErrorLog))cycle_linker_symbol(library, "GetErrorLog");
    linker->destroy = (decltype(&nvJitLinkDestroy))cycle_linker_symbol(library, "Destroy");
    linker->ready = (linker->create != NULL) && (linker->add != NULL) && (linker->complete != NULL)
                 && (linker->cubin_size != NULL) && (linker->cubin != NULL) && (linker->log_size != NULL)
                 && (linker->log != NULL) && (linker->destroy != NULL);
    return linker->ready;
}

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
static int cycle_program_operand(const EngineRecordLayout *layout, unsigned int at, unsigned int operand,
                                 unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= layout->step_table[operand].limbs);
}

static int cycle_program_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

// 1 where the operation reads a left register: every one but the fields, the constant and the lane's number
static int cycle_program_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED)
        && (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid: its operands are earlier steps, each read whole (a table
// reads its source's low limb alone, and key_schedule leaves its left_limbs 0), its own limbs lie inside the file, and
// a field reads a member the program has, a signed field's top bit inside its limbs. A step that fails this leaves the
// whole program on the interpreter
static int cycle_program_held(const EngineRecordLayout *layout, unsigned int at)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const int reads_left = cycle_program_reads_left(operation);
    const int reads_left_whole = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at))
        && !(reads_left_whole && !cycle_program_operand(layout, at, step->left, step->left_limbs))
        && !(cycle_program_reads_right(operation) && !cycle_program_operand(layout, at, step->right, step->right_limbs))
        && (((unsigned long long)step->place + step->limbs) <= (unsigned long long)layout->file_limbs)
        && (!field || (step->member < layout->members))
        && ((operation != ENGINE_RECORD_FIELD_SIGNED)
            || ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// one step's source, one call into the operator block and its put; 0 for a step this compiler does not hold, which
// leaves the whole program on the interpreter. `wide` is the width the program's scratch is laid at, and the scratch's
// places follow the file's
static int cycle_program_step(const EngineRecordLayout *layout, unsigned int at, unsigned int wide, std::string &text)
{
    const unsigned int scratch = layout->file_limbs;
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    if (!cycle_program_held(layout, at))
    {
        return 0;
    }
    const unsigned int left = step->left;
    const unsigned int right = step->right;
    const unsigned int left_limbs = step->left_limbs;
    const unsigned int right_limbs = step->right_limbs;
    // every register is its step's place in the file, and its sign the sign at that place. key_schedule frees an
    // operand's place only once the step after its last reader begins, so no step's value lies over its own operands
    const unsigned int place = step->place;
    const unsigned int left_place = cycle_program_reads_left(operation) ? layout->step_table[left].place : 0u;
    const unsigned int right_place = cycle_program_reads_right(operation) ? layout->step_table[right].place : 0u;
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        cycle_emit(text, "            cycle_field%s(atom%u, %uu, %uu, %uu, %uu, %uu);\n",
                   (operation == ENGINE_RECORD_FIELD_SIGNED) ? "_signed" : "", step->member,
                   layout->in_limbs[step->member], left, right, place, limbs);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_emit(text, "            cycle_constant(%uu, %uu, %uu, %uu);\n", left, right, place, limbs);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        cycle_emit(text, "            cycle_lane_index(lane, %uu, %uu);\n", place, limbs);
    }
    else if ((operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_COMPARE))
    {
        cycle_emit(text, "            cycle_%s(%uu, %uu, %uu, %uu, %uu, %uu);\n",
                   (operation == ENGINE_RECORD_PRODUCT) ? "product" : "compare", place, limbs, left_place, left_limbs,
                   right_place, right_limbs);
    }
    else if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE))
    {
        cycle_emit(text, "            cycle_sum(%uu, %uu, %uu, %uu, %uu, %uu, %uu);\n", place, limbs,
                   left_place, left_limbs, right_place, right_limbs, (operation == ENGINE_RECORD_DIFFERENCE) ? 1u : 0u);
    }
    else if ((operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        cycle_emit(text, "            cycle_bitwise(%uu, %uu, %uu, %uu, %uu, %uu, %uu);\n", place, limbs,
                   left_place, left_limbs, right_place, right_limbs, (operation == ENGINE_RECORD_XOR) ? 1u : 0u);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        cycle_emit(text, "            cycle_absolute(%uu, %uu, %uu, %uu);\n", place, limbs, left_place,
                   left_limbs);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        cycle_emit(text, "            cycle_table(%uu, %uu, %uu, launch->tables, %uu, %uu);\n", place, limbs,
                   left_place, step->table_offset, step->index_bits);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        cycle_emit(text, "            cycle_wrap(%uu, %uu, %uu, %uu, %uu);\n", place, limbs, left_place,
                   left_limbs, step->wrap_bits);
    }
    else if (operation == ENGINE_RECORD_GCD)
    {
        cycle_emit(text, "            cycle_gcd(%uu, %uu, %uu, %uu, %uu, %uu, %uu, %uu);\n", place, limbs, left_place,
                   left_limbs, right_place, right_limbs, scratch, wide);
    }
    else if (operation == ENGINE_RECORD_LADDER)
    {
        // a right that is not positive refuses the lane
        cycle_emit(text,
                   "            good = cycle_ladder(%uu, %uu, %uu, %uu, %uu, %uu, %uu);\n"
                   "            if (good == 0)\n"
                   "            {\n"
                   "                break;\n"
                   "            }\n",
                   place, limbs, left_place, left_limbs, right_place, right_limbs, scratch);
    }
    else if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
             || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
    {
        // a zero divisor, or an exact quotient that leaves a remainder, refuses the lane
        const char *const name = (operation == ENGINE_RECORD_QUOTIENT)
                               ? "quotient" : ((operation == ENGINE_RECORD_REMAINDER) ? "remainder" : "exact_quotient");
        cycle_emit(text,
                   "            good = cycle_%s(%uu, %uu, %uu, %uu, %uu, %uu, %uu, %uu);\n"
                   "            if (good == 0)\n"
                   "            {\n"
                   "                break;\n"
                   "            }\n",
                   name, place, limbs, left_place, left_limbs, right_place, right_limbs, scratch, wide);
    }
    else
    {
        // an operation this compiler does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        cycle_emit(text, "            cycle_put(record, %uu, %uu, %uu, %uu, %uu);\n", layout->out_limbs,
                   step->out_offset, step->out_bits, place, limbs);
    }
    return 1;
}

// the operator block's source for the device and the kind of link, which names both: the block's words the kernel
// reads and writes and the command and states it compares, from the one layout, then the prelude and the operators
static std::string cycle_operator_source(int major, int minor, int lto)
{
    std::string text;
    cycle_emit(text, "// the operator block, for sm_%d%d, NVRTC %d.%d, as %s\n", major, minor, s_cycle_compiler.major,
               s_cycle_compiler.minor, (lto != 0) ? "LTO-IR" : "relocatable cubin");
    cycle_emit(text, "#define CYCLE_GOLDEN_RUNGS %uu\n", ENGINE_GOLDEN_RUNGS);
    cycle_emit(text, "#define CYCLE_BLOCK_OWNER %zuu\n", offsetof(EngineProgramBlock, owner) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_COMMAND %zuu\n", offsetof(EngineProgramBlock, command) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_STATE %zuu\n", offsetof(EngineProgramBlock, state) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_OFFSET %zuu\n", offsetof(EngineProgramBlock, offset) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_STEP %zuu\n", offsetof(EngineProgramBlock, step) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_LAUNCH_TIME %zuu\n", offsetof(EngineProgramBlock, launch_time) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_EXECTIME %zuu\n", offsetof(EngineProgramBlock, exectime) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_CHECKIN %zuu\n", offsetof(EngineProgramBlock, checkin) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_CHECKIN_TIME %zuu\n", offsetof(EngineProgramBlock, checkin_time) / 8u);
    cycle_emit(text, "#define CYCLE_PROGRAM_RUN %uull\n", (unsigned int)ENGINE_PROGRAM_RUN);
    cycle_emit(text, "#define CYCLE_PROGRAM_STOP %uull\n", (unsigned int)ENGINE_PROGRAM_STOP);
    cycle_emit(text, "#define CYCLE_PROGRAM_YIELDED %uull\n", (unsigned int)ENGINE_PROGRAM_YIELDED);
    cycle_emit(text, "#define CYCLE_PROGRAM_DONE %uull\n", (unsigned int)ENGINE_PROGRAM_DONE);
    cycle_emit(text, "#define CYCLE_PROGRAM_STOPPED %uull\n", (unsigned int)ENGINE_PROGRAM_STOPPED);
    text += s_cycle_prelude;
    text += s_cycle_operators;
    return text;
}

// the width the divisions and the ladder share one scratch at: the widest any of them reads or writes, 0 for none
static unsigned int cycle_program_wide(const EngineRecordLayout *layout)
{
    unsigned int wide = 0u;
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        const DeviceRecordStep *const step = &layout->step_table[at];
        const unsigned int operation = step->operation;
        if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
            || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
            || (operation == ENGINE_RECORD_LADDER))
        {
            wide = (step->left_limbs > wide) ? step->left_limbs : wide;
            wide = (step->right_limbs > wide) ? step->right_limbs : wide;
            wide = (step->limbs > wide) ? step->limbs : wide;
        }
    }
    return wide;
}

// a thread's places: the file's, then the scratch's where the program divides or climbs the ladder. The ladder's rung
// and its multiple take right_limbs + 4 of them, inside the divisions' 5 * wide + 4
static unsigned int cycle_program_places(const EngineRecordLayout *layout)
{
    const unsigned int wide = cycle_program_wide(layout);
    return layout->file_limbs + ((wide != 0u) ? CYCLE_RECORD_SCRATCH(wide) : 0u);
}

// a program's source: its lane, its atoms and its record cleared, then each step one call into the operator block.
// It names the device, NVRTC and the operator block it is linked against; empty where a step is one this compiler does
// not hold. The registers are the operator block's places in shared memory, so the lane holds none of its own
static std::string cycle_program_source(const EngineRecordLayout *layout, const CycleOperatorBlock *operators)
{
    std::string text;
    cycle_emit(text, "// a record program of %u steps, for sm_%d%d, NVRTC %d.%d, against the operator block %016llx\n",
               layout->steps, operators->major, operators->minor, s_cycle_compiler.major, s_cycle_compiler.minor,
               operators->hash);
    text += s_cycle_prelude;
    const unsigned int wide = cycle_program_wide(layout);
    text += "\nextern \"C\" __device__ void cycle_lane(const CycleCompiledLaunch *launch, const u64 lane)\n{\n";
    text += "    int good = 1;\n";
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        cycle_emit(text,
                   "    const u64 body%u = (launch->index != nullptr) ? (u64)launch->index[(lane * %uull) + %uull]\n"
                   "                    : ((launch->bodies[%u] == 1ull) ? 0ull : lane);\n"
                   "    good = ((good != 0) && (body%u < launch->bodies[%u])) ? 1 : 0;\n"
                   "    const u32 *const atom%u = &launch->in[%u][((good != 0) ? body%u : 0ull) * %uull];\n",
                   member, layout->members, member, member, member, member, member, member, member,
                   layout->in_limbs[member]);
    }
    cycle_emit(text, "    u32 *const record = &launch->out[lane * %uull];\n", layout->out_limbs);
    cycle_emit(text, "    for (u32 limb = 0u; limb < %uu; limb += 1u)\n    {\n", layout->out_limbs);
    text += "        record[limb] = 0u;\n    }\n    do\n    {\n        if (good == 0)\n";
    text += "        {\n            break;\n        }\n";
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (!cycle_program_step(layout, at, wide, text))
        {
            return std::string();
        }
    }
    text += "    } while (0);\n    if (good == 0)\n    {\n        atomicAdd(launch->refused, 1u);\n    }\n}\n";
    return text;
}

// the folder compiled programs are kept in across processes: $CYCLE_CACHE, else the user's cache, then cycle
static std::string cycle_cache_folder(void)
{
    const char *const named = getenv("CYCLE_CACHE");
    if ((named != NULL) && (named[0] != '\0'))
    {
        return std::string(named);
    }
#if defined(_WIN32)
    const char *const local = getenv("LOCALAPPDATA");
    return (local != NULL) ? (std::string(local) + "\\cycle") : std::string();
#else
    const char *const cache = getenv("XDG_CACHE_HOME");
    const char *const home = getenv("HOME");
    if ((cache != NULL) && (cache[0] != '\0'))
    {
        return std::string(cache) + "/cycle";
    }
    if (home == NULL)
    {
        return std::string();
    }
    mkdir((std::string(home) + "/.cache").c_str(), 0755);
    return std::string(home) + "/.cache/cycle";
#endif
}

// a source's FNV-1a
static unsigned long long cycle_source_hash(const std::string &source)
{
    unsigned long long hash = 0xCBF29CE484222325ull;
    for (size_t at = 0u; at < source.size(); at += 1u)
    {
        // a source byte is read as its unsigned value
        hash = (hash ^ (unsigned long long)(unsigned char)source[at]) * 0x100000001B3ull;
    }
    return hash;
}

// a source's file in the cache, the image built from it (a program's linked cubin, the operator block's relocatable
// cubin or LTO-IR): its source's FNV-1a in hex. The name need not be unique: a file is used only where the source it
// holds is this source, byte for byte
static std::string cycle_cache_path(const std::string &folder, const std::string &source)
{
    char name[32];
    snprintf(name, sizeof(name), "%016llx.image", cycle_source_hash(source));
#if defined(_WIN32)
    return folder + "\\" + name;
#else
    return folder + "/" + name;
#endif
}

static const char s_cycle_cache_magic[] = "cycle image 2\n";

// the image a cache file holds for this very source; empty where there is none
static std::vector<char> cycle_cache_read(const std::string &path, const std::string &source)
{
    std::vector<char> image;
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return image;
    }
    std::vector<char> whole;
    char block[65536];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        whole.insert(whole.end(), block, block + read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    const size_t magic = sizeof(s_cycle_cache_magic) - 1u;
    const size_t head = magic + sizeof(unsigned long long);
    unsigned long long length = 0ull;
    if (whole.size() >= head)
    {
        memcpy(&length, &whole[magic], sizeof(length));
    }
    const int held = (whole.size() >= head) && (memcmp(&whole[0], s_cycle_cache_magic, magic) == 0)
                  && (length == source.size()) && ((whole.size() - head) > length)
                  && (memcmp(&whole[head], source.data(), source.size()) == 0);
    if (held)
    {
        // a source length the file held whole is below its size, held whole
        image.assign(whole.begin() + (ptrdiff_t)(head + length), whole.end());
    }
    return image;
}

// the source and its image written beside the name and then renamed to it, and no reader finds half a file; a name
// already taken is left as it is
static void cycle_cache_write(const std::string &folder, const std::string &path, const std::string &source,
                              const std::vector<char> &image)
{
#if defined(_WIN32)
    _mkdir(folder.c_str());
    const int process = _getpid();
#else
    mkdir(folder.c_str(), 0755);
    // a pid is positive, held whole
    const int process = (int)getpid();
#endif
    char suffix[32];
    snprintf(suffix, sizeof(suffix), ".%d.partial", process);
    const std::string partial = path + suffix;
    FILE *const file = fopen(partial.c_str(), "wb");
    if (file == NULL)
    {
        return;
    }
    const unsigned long long length = source.size();
    const int whole = (fwrite(s_cycle_cache_magic, 1u, sizeof(s_cycle_cache_magic) - 1u, file)
                       == (sizeof(s_cycle_cache_magic) - 1u))
                   && (fwrite(&length, sizeof(length), 1u, file) == 1u)
                   && (fwrite(source.data(), 1u, source.size(), file) == source.size())
                   && (fwrite(image.data(), 1u, image.size(), file) == image.size());
    const int closed = fclose(file) == 0;
    if (!whole || !closed || (rename(partial.c_str(), path.c_str()) != 0))
    {
        remove(partial.c_str());
    }
}

// the source compiled by NVRTC as relocatable code for the device's architecture: a relocatable cubin, or LTO-IR where
// `lto`; empty where it refuses, its log then on stderr when reporting
static std::vector<char> cycle_program_compile(const std::string &source, const char *name, int major, int minor,
                                               int lto, int report)
{
    CycleCompiler *const compiler = &s_cycle_compiler;
    std::vector<char> image;
    nvrtcProgram program = NULL;
    if (compiler->create(&program, source.c_str(), name, 0, NULL, NULL) != NVRTC_SUCCESS)
    {
        return image;
    }
    char architecture[48];
    snprintf(architecture, sizeof(architecture), "--gpu-architecture=sm_%d%d", major, minor);
    const char *const options[] = {architecture, "--std=c++17", "--relocatable-device-code=true", "-dlto"};
    const nvrtcResult compiled = compiler->compile(program, (lto != 0) ? 4 : 3, options);
    size_t size = 0u;
    const nvrtcResult sized = (lto != 0) ? compiler->ltoir_size(program, &size) : compiler->cubin_size(program, &size);
    if ((compiled == NVRTC_SUCCESS) && (sized == NVRTC_SUCCESS) && (size != 0u))
    {
        image.resize(size);
        const nvrtcResult taken = (lto != 0) ? compiler->ltoir(program, image.data())
                                             : compiler->cubin(program, image.data());
        if (taken != NVRTC_SUCCESS)
        {
            image.clear();
        }
    }
    size_t log_size = 0u;
    if ((compiled != NVRTC_SUCCESS) && (report != 0) && (compiler->log_size(program, &log_size) == NVRTC_SUCCESS)
        && (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (compiler->log(program, log.data()) == NVRTC_SUCCESS)
        {
            fprintf(stderr, "  cycle: NVRTC refused %s (%d):\n%s\n", name, (int)compiled, log.data());
        }
    }
    compiler->destroy(&program);
    return image;
}

// a program's relocatable image linked against the operator block's by nvJitLink into one cubin, with link-time
// optimization where `lto`; where `ptx` the program is PTX's text, NUL and all, which nvJitLink assembles as it links.
// Empty where it refuses, its log then on stderr when reporting
static std::vector<char> cycle_program_link(const CycleOperatorBlock *operators, const std::vector<char> &object,
                                            int lto, int ptx, int report)
{
    CycleLinker *const linker = &s_cycle_linker;
    std::vector<char> cubin;
    char architecture[32];
    snprintf(architecture, sizeof(architecture), "-arch=sm_%d%d", operators->major, operators->minor);
    const char *options[] = {architecture, "-lto"};
    nvJitLinkHandle handle = NULL;
    if (linker->create(&handle, (lto != 0) ? 2u : 1u, options) != NVJITLINK_SUCCESS)
    {
        return cubin;
    }
    const nvJitLinkInputType kind = (lto != 0) ? NVJITLINK_INPUT_LTOIR : NVJITLINK_INPUT_CUBIN;
    const nvJitLinkInputType program_kind = (ptx != 0) ? NVJITLINK_INPUT_PTX : kind;
    size_t size = 0u;
    const int linked = (linker->add(handle, kind, operators->image.data(), operators->image.size(), "cycle_operators")
                        == NVJITLINK_SUCCESS)
                    && (linker->add(handle, program_kind, object.data(), object.size(), "cycle_program")
                        == NVJITLINK_SUCCESS)
                    && (linker->complete(handle) == NVJITLINK_SUCCESS)
                    && (linker->cubin_size(handle, &size) == NVJITLINK_SUCCESS) && (size != 0u);
    if (linked)
    {
        cubin.resize(size);
        if (linker->cubin(handle, cubin.data()) != NVJITLINK_SUCCESS)
        {
            cubin.clear();
        }
    }
    size_t log_size = 0u;
    if (!linked && (report != 0) && (linker->log_size(handle, &log_size) == NVJITLINK_SUCCESS) && (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (linker->log(handle, log.data()) == NVJITLINK_SUCCESS)
        {
            fprintf(stderr, "  cycle: nvJitLink refused a record program:\n%s\n", log.data());
        }
    }
    linker->destroy(&handle);
    return cubin;
}

// the operator block for the device and the kind of link, built once a process: found in the cache, else compiled and
// kept there. NULL where NVRTC refuses it
static const CycleOperatorBlock *cycle_operator_block(int major, int minor, int lto, int report)
{
    CycleOperatorBlock *const operators = &s_cycle_operator_blocks[(lto != 0) ? 1 : 0];
    if ((operators->tried != 0) && (operators->major == major) && (operators->minor == minor))
    {
        return (operators->ready != 0) ? operators : NULL;
    }
    operators->tried = 1;
    operators->major = major;
    operators->minor = minor;
    operators->source = cycle_operator_source(major, minor, lto);
    operators->hash = cycle_source_hash(operators->source);
    const auto began = std::chrono::steady_clock::now();
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, operators->source);
    operators->image = path.empty() ? std::vector<char>() : cycle_cache_read(path, operators->source);
    const int found = !operators->image.empty();
    if (!found)
    {
        operators->image = cycle_program_compile(operators->source, "cycle_operators.cu", major, minor, lto, report);
        if (!operators->image.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, operators->source, operators->image);
        }
    }
    const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    operators->ready = operators->image.empty() ? 0 : 1;
    if ((report != 0) && (operators->ready != 0))
    {
        fprintf(stderr, "  cycle: the operator block %016llx, %zu bytes of %s, %s for sm_%d%d in %.1f ms\n",
                operators->hash, operators->image.size(), (lto != 0) ? "LTO-IR" : "relocatable cubin",
                found ? "read from the cache" : "compiled", major, minor, milliseconds);
    }
    return (operators->ready != 0) ? operators : NULL;
}

// The record program as PTX. The lane is written in NVIDIA's own assembly, with no compiler between the steps and
// ptxas: each step unrolled at its widths into straight-line PTX over registers the lane holds itself. The file is %v
// by place and its signs %g by place, as key_schedule laid them; the record's words are %o, laid by each put and stored
// once as the lane ends; the atoms' words are %a, each loaded at its first reader. What a compiler would loop over a
// register's limbs is written out here limb by limb from the program's own widths, so ptxas is handed the unrolled
// block and has nothing to unroll. The rules the unrolling follows are PTX's, held as data: the carry chains a
// register's limbs are laid through (s_cycle_ptx_add and the two after it) and the operator block's functions a lane
// calls by the calling convention (s_cycle_ptx_callees). The steps that loop on their values call into the block: the
// gcd, the golden ladder, a division by more than one limb, and a product too wide to unroll. Their operands go to
// their places in shared memory, where the block reads them, and the result comes back; a program that calls nothing
// takes no shared memory. Every step is the interpreter's arithmetic limb for limb, branch-free where the interpreter
// branches on a sign or a borrow, and CYCLE_RECORD_CHECK=1 holds the two to each other.

// the most limb products a lane unrolls a product into; a wider product calls the operator block
#define CYCLE_PTX_PRODUCT_MOST 1024u

// a carry chain through a register's limbs: the one instruction a register of one limb takes, then the first, the
// middle and the last of a longer one, each setting or reading the carry flag as PTX defines them
struct CyclePtxChain
{
    const char *alone;
    const char *first;
    const char *middle;
    const char *last;
};

static const CyclePtxChain s_cycle_ptx_add = {"add.u32", "add.cc.u32", "addc.cc.u32", "addc.u32"};

static const CyclePtxChain s_cycle_ptx_subtract = {"sub.u32", "sub.cc.u32", "subc.cc.u32", "subc.u32"};

// the subtract chain whose top limb leaves its borrow in the carry flag, for cycle_ptx_borrowed to read
static const CyclePtxChain s_cycle_ptx_borrow = {"sub.cc.u32", "sub.cc.u32", "subc.cc.u32", "subc.cc.u32"};

// one of the operator block's functions a lane calls: the operation it does, its name, its arguments, each 32 bits,
// and 1 where it answers whether the lane holds
struct CyclePtxCallee
{
    unsigned int operation;
    const char *name;
    unsigned int arguments;
    unsigned int answers;
};

// the arguments are the step's place and limbs, its operands' places and limbs, then the scratch's first place and the
// width it is laid at, as s_cycle_prelude declares them
static const CyclePtxCallee s_cycle_ptx_callees[] = {
    {ENGINE_RECORD_PRODUCT, "cycle_product", 6u, 0u},
    {ENGINE_RECORD_LADDER, "cycle_ladder", 7u, 1u},
    {ENGINE_RECORD_QUOTIENT, "cycle_quotient", 8u, 1u},
    {ENGINE_RECORD_REMAINDER, "cycle_remainder", 8u, 1u},
    {ENGINE_RECORD_GCD, "cycle_gcd", 8u, 0u},
    {ENGINE_RECORD_EXACT_QUOTIENT, "cycle_exact_quotient", 8u, 1u},
};

// a handful of functions, counted whole in 32 bits
#define CYCLE_PTX_CALLEES ((unsigned int)(sizeof(s_cycle_ptx_callees) / sizeof(s_cycle_ptx_callees[0])))

// the most arguments a callee takes, the eight cycle_ptx_call passes
#define CYCLE_PTX_ARGUMENTS_MOST 8u

// a lane being written: its steps' text; the temporaries, 64-bit temporaries and predicates the step being written has
// taken and the most any step took; where each member's words begin among the atoms' words and which are loaded; which
// of the block's functions it calls and whether it reads the tables; and the scratch's first place and width, which
// every call shares
struct CyclePtx
{
    const EngineRecordLayout *layout;
    std::string text;
    unsigned int temps;
    unsigned int temps_most;
    unsigned int wides;
    unsigned int wides_most;
    unsigned int predicates;
    unsigned int predicates_most;
    unsigned int atom_first[ENGINE_RECORD_MEMBERS_MAX];
    std::vector<unsigned char> loaded;
    unsigned int called[CYCLE_PTX_CALLEES];
    unsigned int tables;
    unsigned int scratch;
    unsigned int wide;
};

// a step as its emitter reads it: the step, and its register's place and its operands'
struct CyclePtxStep
{
    const DeviceRecordStep *step;
    unsigned int place;
    unsigned int left_place;
    unsigned int right_place;
};

static std::string cycle_ptx_register(const char *bank, unsigned int at)
{
    char name[32];
    snprintf(name, sizeof(name), "%%%s%u", bank, at);
    return std::string(name);
}

// the next of a bank's registers for the step being written, the most any step took kept for the lane to declare
static std::string cycle_ptx_take(const char *bank, unsigned int *taken, unsigned int *most)
{
    const std::string name = cycle_ptx_register(bank, *taken);
    *taken += 1u;
    *most = (*taken > *most) ? *taken : *most;
    return name;
}

static std::string cycle_ptx_temporary(CyclePtx *ptx)
{
    return cycle_ptx_take("t", &ptx->temps, &ptx->temps_most);
}

static std::vector<std::string> cycle_ptx_temporaries(CyclePtx *ptx, unsigned int count)
{
    std::vector<std::string> names(count);
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        names[at] = cycle_ptx_temporary(ptx);
    }
    return names;
}

static std::string cycle_ptx_wide(CyclePtx *ptx)
{
    return cycle_ptx_take("w", &ptx->wides, &ptx->wides_most);
}

static std::string cycle_ptx_predicate(CyclePtx *ptx)
{
    return cycle_ptx_take("p", &ptx->predicates, &ptx->predicates_most);
}

// a register's first `count` limbs at `place`, then %zero up to `width`: a register read past its limbs reads 0
static std::vector<std::string> cycle_ptx_limbs(unsigned int place, unsigned int count, unsigned int width)
{
    std::vector<std::string> names(width, std::string("%zero"));
    for (unsigned int at = 0u; (at < count) && (at < width); at += 1u)
    {
        names[at] = cycle_ptx_register("v", place + at);
    }
    return names;
}

// one chain laid through `limbs` limbs from the lowest: each limb of `to` is left's and right's by the chain's
// instruction for its place in the chain
static void cycle_ptx_chain(CyclePtx *ptx, const CyclePtxChain *chain, const std::vector<std::string> &to,
                            const std::vector<std::string> &left, const std::vector<std::string> &right,
                            unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const char *const instruction = (limbs == 1u) ? chain->alone
                                      : ((at == 0u) ? chain->first
                                                    : ((at == (limbs - 1u)) ? chain->last : chain->middle));
        cycle_emit(ptx->text, "\t%s \t%s, %s, %s;\n", instruction, to[at].c_str(), left[at].c_str(),
                   right[at].c_str());
    }
}

// to = -from modulo 2^(32 limbs), the two's complement, as zero less the register
static void cycle_ptx_negate(CyclePtx *ptx, const std::vector<std::string> &to, const std::vector<std::string> &from,
                             unsigned int limbs)
{
    const std::vector<std::string> zero(limbs, std::string("%zero"));
    cycle_ptx_chain(ptx, &s_cycle_ptx_subtract, to, zero, from, limbs);
}

// a predicate set where the borrow chain just laid borrowed past its top limb, read from the carry flag it left
static std::string cycle_ptx_borrowed(CyclePtx *ptx)
{
    const std::string borrow = cycle_ptx_temporary(ptx);
    const std::string borrowed = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsubc.u32 \t%s, %%zero, %%zero;\n", borrow.c_str());
    cycle_emit(ptx->text, "\tsetp.ne.u32 \t%s, %s, 0;\n", borrowed.c_str(), borrow.c_str());
    return borrowed;
}

// a limb kept to its low `kept` bits where kept is under 32; kept is reckoned as the interpreter reckons it, in 32
// bits, wrapping
static void cycle_ptx_mask(CyclePtx *ptx, const std::string &limb, unsigned int kept)
{
    if (kept < 32u)
    {
        cycle_emit(ptx->text, "\tand.b32 \t%s, %s, %u;\n", limb.c_str(), limb.c_str(), (1u << kept) - 1u);
    }
}

// to = chosen where `where` holds, else otherwise, limb by limb
static void cycle_ptx_select(CyclePtx *ptx, const std::vector<std::string> &to, const std::vector<std::string> &chosen,
                             const std::vector<std::string> &otherwise, const std::string &where, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        cycle_emit(ptx->text, "\tselp.b32 \t%s, %s, %s, %s;\n", to[at].c_str(), chosen[at].c_str(),
                   otherwise[at].c_str(), where.c_str());
    }
}

// a predicate set where any of the first `limbs` limbs is not zero
static std::string cycle_ptx_nonzero(CyclePtx *ptx, const std::vector<std::string> &value, unsigned int limbs)
{
    const std::string nonzero = cycle_ptx_predicate(ptx);
    if (limbs == 1u)
    {
        cycle_emit(ptx->text, "\tsetp.ne.u32 \t%s, %s, 0;\n", nonzero.c_str(), value[0].c_str());
        return nonzero;
    }
    const std::string any = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tor.b32 \t%s, %s, %s;\n", any.c_str(), value[0].c_str(), value[1].c_str());
    for (unsigned int at = 2u; at < limbs; at += 1u)
    {
        cycle_emit(ptx->text, "\tor.b32 \t%s, %s, %s;\n", any.c_str(), any.c_str(), value[at].c_str());
    }
    cycle_emit(ptx->text, "\tsetp.ne.u32 \t%s, %s, 0;\n", nonzero.c_str(), any.c_str());
    return nonzero;
}

// a predicate set where bit `bit` of the register is 1
static std::string cycle_ptx_bit(CyclePtx *ptx, const std::vector<std::string> &value, unsigned int bit)
{
    const std::string held = cycle_ptx_temporary(ptx);
    const std::string set = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tand.b32 \t%s, %s, %u;\n", held.c_str(), value[bit / 32u].c_str(), 1u << (bit % 32u));
    cycle_emit(ptx->text, "\tsetp.ne.u32 \t%s, %s, 0;\n", set.c_str(), held.c_str());
    return set;
}

// the step's sign: `held`, a register or an immediate, where its register is not zero, and 0 where it is
static void cycle_ptx_sign(CyclePtx *ptx, const CyclePtxStep *at, const std::string &held)
{
    const unsigned int limbs = at->step->limbs;
    const std::string nonzero = cycle_ptx_nonzero(ptx, cycle_ptx_limbs(at->place, limbs, limbs), limbs);
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, 0, %s;\n", cycle_ptx_register("g", at->place).c_str(), held.c_str(),
               nonzero.c_str());
}

// the step's sign as -1 where `negative` holds and 1 where not, and 0 where its register is zero
static void cycle_ptx_sign_negative(CyclePtx *ptx, const CyclePtxStep *at, const std::string &negative)
{
    const std::string held = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tselp.s32 \t%s, -1, 1, %s;\n", held.c_str(), negative.c_str());
    cycle_ptx_sign(ptx, at, held);
}

// word `word` of a member's atom, loaded once at its first reader, and %zero past the atom's limbs. The lane runs its
// steps in one straight line, which a refused lane leaves for good, so every later reader follows the load
static std::string cycle_ptx_atom(CyclePtx *ptx, unsigned int member, unsigned int word)
{
    if (word >= ptx->layout->in_limbs[member])
    {
        return std::string("%zero");
    }
    const unsigned int at = ptx->atom_first[member] + word;
    const std::string name = cycle_ptx_register("a", at);
    if (ptx->loaded[at] == 0u)
    {
        cycle_emit(ptx->text, "\tld.global.nc.u32 \t%s, [%%member%u+%u];\n", name.c_str(), member, 4u * word);
        ptx->loaded[at] = 1u;
    }
    return name;
}

// a field, unsigned or signed, gathered as cycle_record_field gathers it: each limb its two atom words funnel-shifted,
// masked to the bits left where fewer than 32 are. A signed field whose top bit is set is negated within its bits, the
// magnitude kept and the sign -1
static void cycle_ptx_field(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->right;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = step->left + (32u * limb);
        const unsigned int shift = bit % 32u;
        const std::string low = cycle_ptx_atom(ptx, step->member, bit / 32u);
        if (shift == 0u)
        {
            cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", value[limb].c_str(), low.c_str());
        }
        else
        {
            const std::string high = cycle_ptx_atom(ptx, step->member, (bit / 32u) + 1u);
            cycle_emit(ptx->text, "\tshf.r.clamp.b32 \t%s, %s, %s, %u;\n", value[limb].c_str(), low.c_str(),
                       high.c_str(), shift);
        }
        cycle_ptx_mask(ptx, value[limb], bits - (32u * limb));
    }
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        cycle_ptx_sign(ptx, at, std::string("1"));
        return;
    }
    const std::string negative = cycle_ptx_bit(ptx, value, bits - 1u);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_mask(ptx, negated[limbs - 1u], bits - (32u * (limbs - 1u)));
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// a constant's two words, every limb above them cleared, its sign known as it is written
static void cycle_ptx_constant(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        const unsigned int word = (limb == 0u) ? step->left : ((limb == 1u) ? step->right : 0u);
        cycle_emit(ptx->text, "\tmov.u32 \t%s, %u;\n", cycle_ptx_register("v", at->place + limb).c_str(), word);
    }
    const int nonzero = (step->left != 0u) || ((step->limbs > 1u) && (step->right != 0u));
    cycle_emit(ptx->text, "\tmov.s32 \t%s, %d;\n", cycle_ptx_register("g", at->place).c_str(), nonzero ? 1 : 0);
}

// the lane's own number, its two words and every limb above them cleared; never negative
static void cycle_ptx_lane(CyclePtx *ptx, const CyclePtxStep *at)
{
    const unsigned int limbs = at->step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    if (limbs == 1u)
    {
        cycle_emit(ptx->text, "\tcvt.u32.u64 \t%s, %%lane_number;\n", value[0].c_str());
    }
    else
    {
        cycle_emit(ptx->text, "\tmov.b64 \t{%s, %s}, %%lane_number;\n", value[0].c_str(), value[1].c_str());
    }
    for (unsigned int limb = 2u; limb < limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tmov.u32 \t%s, 0;\n", value[limb].c_str());
    }
    const std::string counted = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsetp.ne.u64 \t%s, %%lane_number, 0;\n", counted.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, 1, 0, %s;\n", cycle_ptx_register("g", at->place).c_str(), counted.c_str());
}

// the magnitude, and a sign of 1 for any register not zero
static void cycle_ptx_absolute(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, step->limbs, step->limbs);
    const std::vector<std::string> left = cycle_ptx_limbs(at->left_place, step->left_limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", value[limb].c_str(), left[limb].c_str());
    }
    cycle_emit(ptx->text, "\tabs.s32 \t%s, %s;\n", cycle_ptx_register("g", at->place).c_str(),
               cycle_ptx_register("g", at->left_place).c_str());
}

// the order of two signed registers, as cycle_record_operate takes it: signs that differ order the registers alone,
// and signs that agree order them by their magnitudes, read from their difference's borrow and whether it is zero,
// times the sign. The order is the step's sign, and its low limb 1 where the registers differ
static void cycle_ptx_compare(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const std::vector<std::string> difference = cycle_ptx_temporaries(ptx, width);
    cycle_ptx_chain(ptx, &s_cycle_ptx_borrow, difference, cycle_ptx_limbs(at->left_place, step->left_limbs, width),
                    cycle_ptx_limbs(at->right_place, step->right_limbs, width), width);
    const std::string below = cycle_ptx_borrowed(ptx);
    const std::string differs = cycle_ptx_nonzero(ptx, difference, width);
    const std::string left_sign = cycle_ptx_register("g", at->left_place);
    const std::string right_sign = cycle_ptx_register("g", at->right_place);
    const std::string sign = cycle_ptx_register("g", at->place);
    const std::string order = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tselp.s32 \t%s, -1, 1, %s;\n", order.c_str(), below.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, 0, %s;\n", order.c_str(), order.c_str(), differs.c_str());
    cycle_emit(ptx->text, "\tmul.lo.s32 \t%s, %s, %s;\n", order.c_str(), left_sign.c_str(), order.c_str());
    const std::string greater = cycle_ptx_predicate(ptx);
    const std::string apart = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tsetp.gt.s32 \t%s, %s, %s;\n", greater.c_str(), left_sign.c_str(), right_sign.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, 1, -1, %s;\n", apart.c_str(), greater.c_str());
    const std::string unlike = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsetp.ne.s32 \t%s, %s, %s;\n", unlike.c_str(), left_sign.c_str(), right_sign.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, %s, %s;\n", sign.c_str(), apart.c_str(), order.c_str(),
               unlike.c_str());
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, step->limbs, step->limbs);
    cycle_emit(ptx->text, "\tabs.s32 \t%s, %s;\n", value[0].c_str(), sign.c_str());
    for (unsigned int limb = 1u; limb < step->limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tmov.u32 \t%s, 0;\n", value[limb].c_str());
    }
}

// the sum or the difference of two signed registers, branch-free: the magnitudes' sum, their difference with its
// borrow, and that difference negated are all taken, and the signs choose among them as cycle_record_operate does.
// Signs that agree, or either one zero, add, and take the left's sign where it has one; signs that differ subtract the
// lesser magnitude from the greater, the borrow saying which is greater, and take the greater's sign
static void cycle_ptx_sum(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const unsigned int reach = (width > limbs) ? width : limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    const std::string left_sign = cycle_ptx_register("g", at->left_place);
    cycle_ptx_chain(ptx, &s_cycle_ptx_add, value, cycle_ptx_limbs(at->left_place, step->left_limbs, limbs),
                    cycle_ptx_limbs(at->right_place, step->right_limbs, limbs), limbs);
    // the difference runs over every limb either operand holds, so its borrow is their order
    const std::vector<std::string> difference = cycle_ptx_temporaries(ptx, reach);
    cycle_ptx_chain(ptx, &s_cycle_ptx_borrow, difference, cycle_ptx_limbs(at->left_place, step->left_limbs, reach),
                    cycle_ptx_limbs(at->right_place, step->right_limbs, reach), reach);
    const std::string below = cycle_ptx_borrowed(ptx);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, difference, limbs);
    std::string addend_sign = cycle_ptx_register("g", at->right_place);
    if (step->operation == ENGINE_RECORD_DIFFERENCE)
    {
        const std::string turned = cycle_ptx_temporary(ptx);
        cycle_emit(ptx->text, "\tneg.s32 \t%s, %s;\n", turned.c_str(), addend_sign.c_str());
        addend_sign = turned;
    }
    const std::string signs = cycle_ptx_temporary(ptx);
    const std::string opposed = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tmul.lo.s32 \t%s, %s, %s;\n", signs.c_str(), left_sign.c_str(), addend_sign.c_str());
    cycle_emit(ptx->text, "\tsetp.lt.s32 \t%s, %s, 0;\n", opposed.c_str(), signs.c_str());
    cycle_ptx_select(ptx, difference, negated, difference, below, limbs);
    cycle_ptx_select(ptx, value, difference, value, opposed, limbs);
    const std::string greater = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, %s, %s;\n", greater.c_str(), addend_sign.c_str(), left_sign.c_str(),
               below.c_str());
    const std::string leads = cycle_ptx_predicate(ptx);
    const std::string kept = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tsetp.ne.s32 \t%s, %s, 0;\n", leads.c_str(), left_sign.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, %s, %s;\n", kept.c_str(), left_sign.c_str(), addend_sign.c_str(),
               leads.c_str());
    cycle_emit(ptx->text, "\tselp.s32 \t%s, %s, %s, %s;\n", greater.c_str(), greater.c_str(), kept.c_str(),
               opposed.c_str());
    cycle_ptx_sign(ptx, at, greater);
}

// the product truncated to the step's limbs, cycle_record_product's schoolbook rows unrolled: each limb product a
// mad.lo and madc.hi pair on the carry flag with the row's carry added in, and the row's last carry run up the limbs
// above it. The sign is the operands' signs multiplied, as the interpreter takes it
static void cycle_ptx_product(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tmov.u32 \t%s, 0;\n", value[limb].c_str());
    }
    const std::string carry = cycle_ptx_temporary(ptx);
    const std::string upper = cycle_ptx_temporary(ptx);
    for (unsigned int low = 0u; low < step->left_limbs; low += 1u)
    {
        const std::string multiplier = cycle_ptx_register("v", at->left_place + low);
        for (unsigned int high = 0u; (high < step->right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const std::string multiplicand = cycle_ptx_register("v", at->right_place + high);
            const char *const to = value[low + high].c_str();
            cycle_emit(ptx->text, "\tmad.lo.cc.u32 \t%s, %s, %s, %s;\n", to, multiplier.c_str(), multiplicand.c_str(),
                       to);
            if (high == 0u)
            {
                cycle_emit(ptx->text, "\tmadc.hi.u32 \t%s, %s, %s, %%zero;\n", carry.c_str(), multiplier.c_str(),
                           multiplicand.c_str());
            }
            else
            {
                cycle_emit(ptx->text, "\tmadc.hi.u32 \t%s, %s, %s, %%zero;\n", upper.c_str(), multiplier.c_str(),
                           multiplicand.c_str());
                cycle_emit(ptx->text, "\tadd.cc.u32 \t%s, %s, %s;\n", to, to, carry.c_str());
                cycle_emit(ptx->text, "\taddc.u32 \t%s, %s, %%zero;\n", carry.c_str(), upper.c_str());
            }
        }
        if ((low + step->right_limbs) < limbs)
        {
            const unsigned int above = limbs - (low + step->right_limbs);
            const std::vector<std::string> run(value.begin() + (std::ptrdiff_t)(low + step->right_limbs), value.end());
            std::vector<std::string> added(above, std::string("%zero"));
            added[0] = carry;
            cycle_ptx_chain(ptx, &s_cycle_ptx_add, run, run, added, above);
        }
    }
    cycle_emit(ptx->text, "\tmul.lo.s32 \t%s, %s, %s;\n", cycle_ptx_register("g", at->place).c_str(),
               cycle_ptx_register("g", at->left_place).c_str(), cycle_ptx_register("g", at->right_place).c_str());
}

// a table's row: the source's low index_bits select it, and its limbs are loaded from the program's tables at
// table_offset + index . limbs, reckoned in 32 bits as the interpreter reckons it
static void cycle_ptx_table(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    ptx->tables = 1u;
    const std::string index = cycle_ptx_temporary(ptx);
    const std::string source = cycle_ptx_register("v", at->left_place);
    if (step->index_bits >= 32u)
    {
        cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", index.c_str(), source.c_str());
    }
    else
    {
        cycle_emit(ptx->text, "\tand.b32 \t%s, %s, %u;\n", index.c_str(), source.c_str(),
                   (1u << step->index_bits) - 1u);
    }
    cycle_emit(ptx->text, "\tmul.lo.u32 \t%s, %s, %u;\n", index.c_str(), index.c_str(), step->limbs);
    cycle_emit(ptx->text, "\tadd.u32 \t%s, %s, %u;\n", index.c_str(), index.c_str(), step->table_offset);
    const std::string address = cycle_ptx_wide(ptx);
    cycle_emit(ptx->text, "\tmul.wide.u32 \t%s, %s, 4;\n", address.c_str(), index.c_str());
    cycle_emit(ptx->text, "\tadd.s64 \t%s, %%tables, %s;\n", address.c_str(), address.c_str());
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, step->limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tld.global.nc.u32 \t%s, [%s+%u];\n", value[limb].c_str(), address.c_str(), 4u * limb);
    }
    cycle_ptx_sign(ptx, at, std::string("1"));
}

// the xor or the and of two registers' two's complements, each taken over the step's limbs by negating where its sign
// is negative, then read back as a magnitude: negated again where the result's sign is negative, which is the xor's
// where exactly one operand is and the and's where both are
static void cycle_ptx_bitwise(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    const std::string left_negative = cycle_ptx_predicate(ptx);
    const std::string right_negative = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsetp.lt.s32 \t%s, %s, 0;\n", left_negative.c_str(),
               cycle_ptx_register("g", at->left_place).c_str());
    cycle_emit(ptx->text, "\tsetp.lt.s32 \t%s, %s, 0;\n", right_negative.c_str(),
               cycle_ptx_register("g", at->right_place).c_str());
    const std::vector<std::string> left = cycle_ptx_limbs(at->left_place, step->left_limbs, limbs);
    const std::vector<std::string> right = cycle_ptx_limbs(at->right_place, step->right_limbs, limbs);
    const std::vector<std::string> one = cycle_ptx_temporaries(ptx, limbs);
    const std::vector<std::string> other = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, one, left, limbs);
    cycle_ptx_select(ptx, one, one, left, left_negative, limbs);
    cycle_ptx_negate(ptx, other, right, limbs);
    cycle_ptx_select(ptx, other, other, right, right_negative, limbs);
    const char *const operation = (step->operation == ENGINE_RECORD_XOR) ? "xor" : "and";
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\t%s.b32 \t%s, %s, %s;\n", operation, value[limb].c_str(), one[limb].c_str(),
                   other[limb].c_str());
    }
    const std::string negative = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\t%s.pred \t%s, %s, %s;\n", operation, negative.c_str(), left_negative.c_str(),
               right_negative.c_str());
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// the left register wrapped to wrap_bits of two's complement and read back signed, as cycle_record_wrap wraps it: a
// wrap wider than the step's limbs passes the register through, and any other takes its two's complement over the
// limbs, keeps the wrap's bits, and negates within them where the top one is set
static void cycle_ptx_wrap(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->wrap_bits;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    const std::vector<std::string> left = cycle_ptx_limbs(at->left_place, step->left_limbs, limbs);
    const std::string left_sign = cycle_ptx_register("g", at->left_place);
    if (bits > (32u * limbs))
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", value[limb].c_str(), left[limb].c_str());
        }
        cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", cycle_ptx_register("g", at->place).c_str(), left_sign.c_str());
        return;
    }
    const std::string left_negative = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsetp.lt.s32 \t%s, %s, 0;\n", left_negative.c_str(), left_sign.c_str());
    const std::vector<std::string> complement = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, complement, left, limbs);
    cycle_ptx_select(ptx, value, complement, left, left_negative, limbs);
    const unsigned int kept = bits - (32u * (limbs - 1u));
    cycle_ptx_mask(ptx, value[limbs - 1u], kept);
    const std::string negative = cycle_ptx_bit(ptx, value, bits - 1u);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_mask(ptx, negated[limbs - 1u], kept);
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// a division by a divisor of one limb, cycle_record_divide's one-limb long division unrolled from the numerator's top
// limb down: each limb's quotient word by div, and the carried remainder the limb less the quotient word times the
// divisor, which is exact in 32 bits since it is below the divisor. The numerator's zero limbs above its used ones
// divide to zero and carry nothing, as the interpreter's skipping them does. A zero divisor refuses the lane; an exact
// quotient refuses a remainder and a quotient that outgrows its register, as the inverse's multiply back does
static void cycle_ptx_short_division(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(at->place, limbs, limbs);
    const std::string divisor = cycle_ptx_register("v", at->right_place);
    const std::string left_sign = cycle_ptx_register("g", at->left_place);
    const std::string nothing = cycle_ptx_predicate(ptx);
    cycle_emit(ptx->text, "\tsetp.eq.u32 \t%s, %s, 0;\n", nothing.c_str(), divisor.c_str());
    cycle_emit(ptx->text, "\t@%s bra \t$Lrefused;\n", nothing.c_str());
    const std::string carried = cycle_ptx_temporary(ptx);
    const std::string taken = cycle_ptx_temporary(ptx);
    const std::string wide_divisor = cycle_ptx_wide(ptx);
    const std::string part = cycle_ptx_wide(ptx);
    std::vector<std::string> quotient(left_limbs);
    for (unsigned int word = 0u; word < left_limbs; word += 1u)
    {
        quotient[word] = ((operation != ENGINE_RECORD_REMAINDER) && (word < limbs)) ? value[word]
                                                                                   : cycle_ptx_temporary(ptx);
    }
    cycle_emit(ptx->text, "\tcvt.u64.u32 \t%s, %s;\n", wide_divisor.c_str(), divisor.c_str());
    for (unsigned int word = left_limbs; word > 0u; word -= 1u)
    {
        const std::string numerator = cycle_ptx_register("v", at->left_place + word - 1u);
        const char *const quotient_word = quotient[word - 1u].c_str();
        if (word == left_limbs)
        {
            // nothing is carried into the top limb, so its word divides alone
            cycle_emit(ptx->text, "\tdiv.u32 \t%s, %s, %s;\n", quotient_word, numerator.c_str(), divisor.c_str());
        }
        else
        {
            cycle_emit(ptx->text, "\tmov.b64 \t%s, {%s, %s};\n", part.c_str(), numerator.c_str(), carried.c_str());
            cycle_emit(ptx->text, "\tdiv.u64 \t%s, %s, %s;\n", part.c_str(), part.c_str(), wide_divisor.c_str());
            cycle_emit(ptx->text, "\tcvt.u32.u64 \t%s, %s;\n", quotient_word, part.c_str());
        }
        cycle_emit(ptx->text, "\tmul.lo.u32 \t%s, %s, %s;\n", taken.c_str(), quotient_word, divisor.c_str());
        cycle_emit(ptx->text, "\tsub.u32 \t%s, %s, %s;\n", carried.c_str(), numerator.c_str(), taken.c_str());
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", value[0].c_str(), carried.c_str());
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            cycle_emit(ptx->text, "\tmov.u32 \t%s, 0;\n", value[limb].c_str());
        }
        cycle_ptx_sign(ptx, at, left_sign);
        return;
    }
    for (unsigned int limb = left_limbs; limb < limbs; limb += 1u)
    {
        cycle_emit(ptx->text, "\tmov.u32 \t%s, 0;\n", value[limb].c_str());
    }
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        const std::string remains = cycle_ptx_predicate(ptx);
        cycle_emit(ptx->text, "\tsetp.ne.u32 \t%s, %s, 0;\n", remains.c_str(), carried.c_str());
        cycle_emit(ptx->text, "\t@%s bra \t$Lrefused;\n", remains.c_str());
        if (left_limbs > limbs)
        {
            const std::vector<std::string> outgrown(quotient.begin() + (std::ptrdiff_t)limbs, quotient.end());
            const std::string over = cycle_ptx_nonzero(ptx, outgrown, left_limbs - limbs);
            cycle_emit(ptx->text, "\t@%s bra \t$Lrefused;\n", over.c_str());
        }
    }
    const std::string held = cycle_ptx_temporary(ptx);
    cycle_emit(ptx->text, "\tmul.lo.s32 \t%s, %s, %s;\n", held.c_str(), left_sign.c_str(),
               cycle_ptx_register("g", at->right_place).c_str());
    cycle_ptx_sign(ptx, at, held);
}

// a register's limbs and its sign to their places in shared memory where `out`, else back from them: place p of this
// thread is word p . threads + thread, and its sign the byte at p . threads + thread past every place's word, as the
// operator block lays them
static void cycle_ptx_share(CyclePtx *ptx, unsigned int place, unsigned int limbs, int out)
{
    const std::string address = cycle_ptx_temporary(ptx);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const std::string word = cycle_ptx_register("v", place + limb);
        cycle_emit(ptx->text, "\tmad.lo.u32 \t%s, %%word_stride, %u, %%word_base;\n", address.c_str(), place + limb);
        if (out != 0)
        {
            cycle_emit(ptx->text, "\tst.shared.u32 \t[%s], %s;\n", address.c_str(), word.c_str());
        }
        else
        {
            cycle_emit(ptx->text, "\tld.shared.u32 \t%s, [%s];\n", word.c_str(), address.c_str());
        }
    }
    const std::string sign = cycle_ptx_register("g", place);
    cycle_emit(ptx->text, "\tmad.lo.u32 \t%s, %%threads, %u, %%sign_base;\n", address.c_str(), place);
    if (out != 0)
    {
        cycle_emit(ptx->text, "\tst.shared.u8 \t[%s], %s;\n", address.c_str(), sign.c_str());
    }
    else
    {
        cycle_emit(ptx->text, "\tld.shared.s8 \t%s, [%s];\n", sign.c_str(), address.c_str());
    }
}

// a step the operator block does: its operands to their places in shared memory, one call by the calling convention,
// and its register and sign back from its own. A function that answers refuses the lane with 0
static void cycle_ptx_call(CyclePtx *ptx, const CyclePtxStep *at, unsigned int callee)
{
    const DeviceRecordStep *const step = at->step;
    const CyclePtxCallee *const called = &s_cycle_ptx_callees[callee];
    ptx->called[callee] = 1u;
    cycle_ptx_share(ptx, at->left_place, step->left_limbs, 1);
    cycle_ptx_share(ptx, at->right_place, step->right_limbs, 1);
    const unsigned int arguments[CYCLE_PTX_ARGUMENTS_MOST] = {at->place,         step->limbs,       at->left_place,
                                                              step->left_limbs,  at->right_place,   step->right_limbs,
                                                              ptx->scratch,      ptx->wide};
    const std::string answer = (called->answers != 0u) ? cycle_ptx_temporary(ptx) : std::string();
    ptx->text += "\t{\n";
    for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
    {
        cycle_emit(ptx->text, "\t.param .b32 param%u;\n\tst.param.b32 \t[param%u+0], %u;\n", argument, argument,
                   arguments[argument]);
    }
    if (called->answers != 0u)
    {
        ptx->text += "\t.param .b32 retval0;\n";
        cycle_emit(ptx->text, "\tcall (retval0), %s, (", called->name);
    }
    else
    {
        cycle_emit(ptx->text, "\tcall %s, (", called->name);
    }
    for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
    {
        cycle_emit(ptx->text, "%sparam%u", (argument != 0u) ? ", " : "", argument);
    }
    ptx->text += ");\n";
    if (called->answers != 0u)
    {
        cycle_emit(ptx->text, "\tld.param.b32 \t%s, [retval0+0];\n", answer.c_str());
    }
    ptx->text += "\t}\n";
    cycle_ptx_share(ptx, at->place, step->limbs, 0);
    if (called->answers != 0u)
    {
        const std::string refused = cycle_ptx_predicate(ptx);
        cycle_emit(ptx->text, "\tsetp.eq.s32 \t%s, %s, 0;\n", refused.c_str(), answer.c_str());
        cycle_emit(ptx->text, "\t@%s bra \t$Lrefused;\n", refused.c_str());
    }
}

// 1 where an operation's register is never negative, so its put needs no two's complement
static int cycle_ptx_never_negative(unsigned int operation)
{
    return (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT)
        || (operation == ENGINE_RECORD_LANE) || (operation == ENGINE_RECORD_ABSOLUTE)
        || (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_GCD);
}

// the step's register laid into the record's words at out_offset, out_bits of it, as two's complement where its sign
// is negative, as cycle_put lays it; the words are the lane's own registers until the lane ends
static void cycle_ptx_put(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int top = step->out_bits - (32u * (words - 1u));
    const unsigned int first = step->out_offset / 32u;
    const unsigned int shift = step->out_offset % 32u;
    const unsigned int out_limbs = ptx->layout->out_limbs;
    const std::vector<std::string> held = cycle_ptx_limbs(at->place, step->limbs, words);
    const std::vector<std::string> word = cycle_ptx_temporaries(ptx, words);
    if (cycle_ptx_never_negative(step->operation) != 0)
    {
        for (unsigned int each = 0u; each < words; each += 1u)
        {
            cycle_emit(ptx->text, "\tmov.b32 \t%s, %s;\n", word[each].c_str(), held[each].c_str());
        }
    }
    else
    {
        const std::string negative = cycle_ptx_predicate(ptx);
        cycle_emit(ptx->text, "\tsetp.lt.s32 \t%s, %s, 0;\n", negative.c_str(),
                   cycle_ptx_register("g", at->place).c_str());
        const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, words);
        cycle_ptx_negate(ptx, negated, held, words);
        cycle_ptx_select(ptx, word, negated, held, negative, words);
    }
    cycle_ptx_mask(ptx, word[words - 1u], top);
    const std::string moved = cycle_ptx_temporary(ptx);
    for (unsigned int each = 0u; each < words; each += 1u)
    {
        const unsigned int low = first + each;
        if ((low < out_limbs) && (shift == 0u))
        {
            const std::string record = cycle_ptx_register("o", low);
            cycle_emit(ptx->text, "\tor.b32 \t%s, %s, %s;\n", record.c_str(), record.c_str(), word[each].c_str());
        }
        else if (low < out_limbs)
        {
            const std::string record = cycle_ptx_register("o", low);
            cycle_emit(ptx->text, "\tshl.b32 \t%s, %s, %u;\n", moved.c_str(), word[each].c_str(), shift);
            cycle_emit(ptx->text, "\tor.b32 \t%s, %s, %s;\n", record.c_str(), record.c_str(), moved.c_str());
        }
        if ((shift != 0u) && ((low + 1u) < out_limbs))
        {
            const std::string record = cycle_ptx_register("o", low + 1u);
            cycle_emit(ptx->text, "\tshr.b32 \t%s, %s, %u;\n", moved.c_str(), word[each].c_str(), 32u - shift);
            cycle_emit(ptx->text, "\tor.b32 \t%s, %s, %s;\n", record.c_str(), record.c_str(), moved.c_str());
        }
    }
}

// the operator block's function a step calls, an index into s_cycle_ptx_callees, or CYCLE_PTX_CALLEES for a step the
// lane unrolls: every one but the gcd, the ladder, a division by more than one limb, and a product of more than
// CYCLE_PTX_PRODUCT_MOST limb products
static unsigned int cycle_ptx_callee(const DeviceRecordStep *step)
{
    const unsigned int operation = step->operation;
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                     || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    const int unrolled = ((operation == ENGINE_RECORD_PRODUCT)
                          && (((unsigned long long)step->left_limbs * step->right_limbs) <= CYCLE_PTX_PRODUCT_MOST))
                      || (divides && (step->right_limbs == 1u));
    for (unsigned int callee = 0u; (unrolled == 0) && (callee < CYCLE_PTX_CALLEES); callee += 1u)
    {
        if (s_cycle_ptx_callees[callee].operation == operation)
        {
            return callee;
        }
    }
    return CYCLE_PTX_CALLEES;
}

// one step of the lane and its put; 0 for a step the lane does not hold, which leaves the program to the C source
static int cycle_ptx_step(CyclePtx *ptx, unsigned int at)
{
    const EngineRecordLayout *const layout = ptx->layout;
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    // a wrap of no bits has no top bit to read
    if (!cycle_program_held(layout, at) || ((operation == ENGINE_RECORD_WRAP) && (step->wrap_bits == 0u)))
    {
        return 0;
    }
    CyclePtxStep view;
    view.step = step;
    view.place = step->place;
    view.left_place = cycle_program_reads_left(operation) ? layout->step_table[step->left].place : 0u;
    view.right_place = cycle_program_reads_right(operation) ? layout->step_table[step->right].place : 0u;
    ptx->temps = 0u;
    ptx->wides = 0u;
    ptx->predicates = 0u;
    cycle_emit(ptx->text, "\t// step %u, operation %u\n", at, operation);
    const unsigned int callee = cycle_ptx_callee(step);
    if (callee < CYCLE_PTX_CALLEES)
    {
        cycle_ptx_call(ptx, &view, callee);
    }
    else if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        cycle_ptx_field(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_ptx_constant(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        cycle_ptx_lane(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        cycle_ptx_absolute(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_COMPARE)
    {
        cycle_ptx_compare(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE))
    {
        cycle_ptx_sum(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_PRODUCT)
    {
        cycle_ptx_product(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        cycle_ptx_table(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        cycle_ptx_bitwise(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        cycle_ptx_wrap(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
             || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
    {
        cycle_ptx_short_division(ptx, &view);
    }
    else
    {
        // an operation this lane does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        cycle_ptx_put(ptx, &view);
    }
    return 1;
}

// the lane's registers, each bank as many as the lane takes
static void cycle_ptx_declare(std::string &text, const CyclePtx *ptx, unsigned int atoms)
{
    const EngineRecordLayout *const layout = ptx->layout;
    if (ptx->predicates_most != 0u)
    {
        cycle_emit(text, "\t.reg .pred \t%%p<%u>;\n", ptx->predicates_most);
    }
    text += "\t.reg .pred \t%indexed, %one, %good;\n";
    cycle_emit(text, "\t.reg .b32 \t%%v<%u>;\n", layout->file_limbs);
    cycle_emit(text, "\t.reg .b32 \t%%g<%u>;\n", layout->file_limbs);
    cycle_emit(text, "\t.reg .b32 \t%%o<%u>;\n", layout->out_limbs);
    if (atoms != 0u)
    {
        cycle_emit(text, "\t.reg .b32 \t%%a<%u>;\n", atoms);
    }
    cycle_emit(text, "\t.reg .b32 \t%%t<%u>;\n", ptx->temps_most);
    cycle_emit(text, "\t.reg .b64 \t%%w<%u>;\n", ptx->wides_most);
    text += "\t.reg .b32 \t%zero, %thread, %threads, %word_base, %word_stride, %sign_base;\n";
    text += "\t.reg .b64 \t%launch, %lane_number, %record, %index, %body, %bodies, %tables;\n";
    cycle_emit(text, "\t.reg .b64 \t%%member<%u>;\n", ENGINE_RECORD_MEMBERS_MAX);
}

// the lane's opening: its launch and number, the record's words cleared, and each member's atom found as
// cycle_program_source finds it, a lane whose atom lies past its member refused before any step; then the program's
// tables, and the lane's places in shared memory where it calls the operator block
static void cycle_ptx_open(std::string &text, const CyclePtx *ptx, unsigned int places, int calls)
{
    const EngineRecordLayout *const layout = ptx->layout;
    text += "\tld.param.u64 \t%launch, [cycle_lane_param_0];\n";
    text += "\tld.param.u64 \t%lane_number, [cycle_lane_param_1];\n";
    text += "\tmov.u32 \t%zero, 0;\n";
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        cycle_emit(text, "\tmov.u32 \t%%o%u, 0;\n", word);
    }
    cycle_emit(text, "\tld.u64 \t%%record, [%%launch+%zu];\n", offsetof(CycleCompiledLaunch, out));
    text += "\tcvta.to.global.u64 \t%record, %record;\n";
    cycle_emit(text, "\tmul.lo.u64 \t%%w0, %%lane_number, %u;\n", 4u * layout->out_limbs);
    text += "\tadd.s64 \t%record, %record, %w0;\n";
    cycle_emit(text, "\tld.u64 \t%%index, [%%launch+%zu];\n", offsetof(CycleCompiledLaunch, index));
    text += "\tsetp.ne.u64 \t%indexed, %index, 0;\n";
    text += "\tcvta.to.global.u64 \t%index, %index;\n";
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        cycle_emit(text, "\tld.u64 \t%%bodies, [%%launch+%zu];\n",
                   offsetof(CycleCompiledLaunch, bodies) + (8u * (size_t)member));
        text += "\tsetp.eq.u64 \t%one, %bodies, 1;\n";
        text += "\tselp.b64 \t%body, 0, %lane_number, %one;\n";
        cycle_emit(text, "\tmul.lo.u64 \t%%w0, %%lane_number, %u;\n", layout->members);
        cycle_emit(text, "\tadd.u64 \t%%w0, %%w0, %u;\n", member);
        text += "\tshl.b64 \t%w0, %w0, 2;\n";
        text += "\tadd.s64 \t%w0, %index, %w0;\n";
        text += "\t@%indexed ld.global.nc.u32 \t%t0, [%w0];\n";
        text += "\t@%indexed cvt.u64.u32 \t%body, %t0;\n";
        text += (member == 0u) ? "\tsetp.lt.u64 \t%good, %body, %bodies;\n"
                               : "\tsetp.lt.and.u64 \t%good, %body, %bodies, %good;\n";
        text += "\tselp.b64 \t%body, %body, 0, %good;\n";
        cycle_emit(text, "\tld.u64 \t%%member%u, [%%launch+%zu];\n", member,
                   offsetof(CycleCompiledLaunch, in) + (8u * (size_t)member));
        cycle_emit(text, "\tcvta.to.global.u64 \t%%member%u, %%member%u;\n", member, member);
        cycle_emit(text, "\tmul.lo.u64 \t%%w0, %%body, %u;\n", 4u * layout->in_limbs[member]);
        cycle_emit(text, "\tadd.s64 \t%%member%u, %%member%u, %%w0;\n", member, member);
    }
    text += "\t@!%good bra \t$Lrefused;\n";
    if (ptx->tables != 0u)
    {
        cycle_emit(text, "\tld.u64 \t%%tables, [%%launch+%zu];\n", offsetof(CycleCompiledLaunch, tables));
        text += "\tcvta.to.global.u64 \t%tables, %tables;\n";
    }
    if (calls != 0)
    {
        // a word's address is cycle_words + 4 (place . threads + thread), a sign's cycle_words + 4 places . threads +
        // place . threads + thread
        text += "\tmov.u32 \t%thread, %tid.x;\n";
        text += "\tmov.u32 \t%threads, %ntid.x;\n";
        text += "\tmov.u32 \t%word_base, cycle_words;\n";
        text += "\tadd.u32 \t%sign_base, %word_base, %thread;\n";
        cycle_emit(text, "\tmad.lo.u32 \t%%sign_base, %%threads, %u, %%sign_base;\n", 4u * places);
        text += "\tmad.lo.u32 \t%word_base, %thread, 4, %word_base;\n";
        text += "\tshl.b32 \t%word_stride, %threads, 2;\n";
    }
}

// the lane's close: a refused lane counted, and every lane's record stored whole, the words its puts laid before it
// ended
static void cycle_ptx_close(std::string &text, const EngineRecordLayout *layout)
{
    text += "\tbra \t$Lstore;\n";
    text += "$Lrefused:\n";
    cycle_emit(text, "\tld.u64 \t%%w0, [%%launch+%zu];\n", offsetof(CycleCompiledLaunch, refused));
    text += "\tcvta.to.global.u64 \t%w0, %w0;\n";
    text += "\tred.global.add.u32 \t[%w0], 1;\n";
    text += "$Lstore:\n";
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        cycle_emit(text, "\tst.global.u32 \t[%%record+%u], %%o%u;\n", 4u * word, word);
    }
    text += "\tret;\n";
}

// a program's lane as PTX under the header this toolkit writes, and the places a thread holds in shared memory for the
// steps that call the operator block: the file's and the scratch's, 0 where no step calls. It names the device, NVRTC
// and the operator block it is linked against; empty where a step is one the lane does not hold
static std::string cycle_program_ptx(const EngineRecordLayout *layout, const CycleOperatorBlock *operators,
                                     const std::string &header, unsigned int *places)
{
    CyclePtx ptx{};
    ptx.layout = layout;
    // the lane's opening takes %t0 and %w0 before any step does
    ptx.temps_most = 1u;
    ptx.wides_most = 1u;
    unsigned int atoms = 0u;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        ptx.atom_first[member] = atoms;
        atoms += layout->in_limbs[member];
    }
    ptx.loaded.assign(atoms, (unsigned char)0u);
    ptx.scratch = layout->file_limbs;
    // the calls that work in the scratch share it at the widest of their widths
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        const DeviceRecordStep *const step = &layout->step_table[at];
        const unsigned int callee = cycle_ptx_callee(step);
        if ((callee < CYCLE_PTX_CALLEES) && (s_cycle_ptx_callees[callee].arguments > 6u))
        {
            ptx.wide = (step->left_limbs > ptx.wide) ? step->left_limbs : ptx.wide;
            ptx.wide = (step->right_limbs > ptx.wide) ? step->right_limbs : ptx.wide;
            ptx.wide = (step->limbs > ptx.wide) ? step->limbs : ptx.wide;
        }
    }
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (cycle_ptx_step(&ptx, at) == 0)
        {
            return std::string();
        }
    }
    int calls = 0;
    for (unsigned int callee = 0u; callee < CYCLE_PTX_CALLEES; callee += 1u)
    {
        calls = calls || (ptx.called[callee] != 0u);
    }
    *places = (calls != 0) ? (layout->file_limbs + ((ptx.wide != 0u) ? CYCLE_RECORD_SCRATCH(ptx.wide) : 0u)) : 0u;
    std::string text;
    cycle_emit(text, "// a record program of %u steps, for sm_%d%d, NVRTC %d.%d, as PTX against the operator block "
                     "%016llx\n",
               layout->steps, operators->major, operators->minor, s_cycle_compiler.major, s_cycle_compiler.minor,
               operators->hash);
    text += header;
    if (calls != 0)
    {
        text += "\n.extern .shared .align 4 .b8 cycle_words[];\n";
    }
    for (unsigned int callee = 0u; callee < CYCLE_PTX_CALLEES; callee += 1u)
    {
        const CyclePtxCallee *const called = &s_cycle_ptx_callees[callee];
        if (ptx.called[callee] == 0u)
        {
            continue;
        }
        cycle_emit(text, "\n.extern .func %s%s\n(\n", (called->answers != 0u) ? "(.param .b32 func_retval0) " : "",
                   called->name);
        for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
        {
            cycle_emit(text, "\t.param .b32 %s_param_%u%s\n", called->name, argument,
                       ((argument + 1u) < called->arguments) ? "," : "");
        }
        text += ")\n;\n";
    }
    text += "\n.visible .func cycle_lane(\n\t.param .b64 cycle_lane_param_0,\n\t.param .b64 cycle_lane_param_1\n)\n{\n";
    cycle_ptx_declare(text, &ptx, atoms);
    text += "\n";
    cycle_ptx_open(text, &ptx, *places, calls);
    text += ptx.text;
    cycle_ptx_close(text, layout);
    text += "}\n";
    return text;
}

// the .version, .target and .address_size lines of a PTX text, the first of each, in that order; empty where one is
// missing or the address size is not 64, which the lane's pointers are written for
static std::string cycle_ptx_header_lines(const char *ptx)
{
    std::string version;
    std::string target;
    std::string address_size;
    const char *line = ptx;
    while (*line != '\0')
    {
        const char *const end = strchr(line, '\n');
        // a line ends past its start, so its length is never negative
        const size_t length = (end != NULL) ? (size_t)(end - line) : strlen(line);
        const std::string held(line, length);
        if (version.empty() && (held.compare(0u, 9u, ".version ") == 0))
        {
            version = held;
        }
        else if (target.empty() && (held.compare(0u, 8u, ".target ") == 0))
        {
            target = held;
        }
        else if (address_size.empty() && (held.compare(0u, 14u, ".address_size ") == 0))
        {
            address_size = held;
        }
        line = (end != NULL) ? (end + 1) : (line + length);
    }
    const int whole = !version.empty() && !target.empty() && (address_size == ".address_size 64");
    return whole ? (version + "\n" + target + "\n" + address_size + "\n") : std::string();
}

// PTX's header as this toolkit writes it for the device, asked of NVRTC once a process by compiling an empty kernel to
// PTX, the answer kept in the cache against the question: the one part of PTX's rules the lane does not carry itself
struct CyclePtxHeader
{
    int tried;
    int major;
    int minor;
    std::string lines;
};

static CyclePtxHeader s_cycle_ptx_header;

// the header's three lines; empty where NVRTC cannot be asked or does not answer, which leaves programs to the C source
static const std::string &cycle_ptx_header(int major, int minor, int report)
{
    CyclePtxHeader *const header = &s_cycle_ptx_header;
    if ((header->tried != 0) && (header->major == major) && (header->minor == minor))
    {
        return header->lines;
    }
    header->tried = 1;
    header->major = major;
    header->minor = minor;
    header->lines.clear();
    CycleCompiler *const compiler = &s_cycle_compiler;
    if ((compiler->ptx_size == NULL) || (compiler->ptx == NULL))
    {
        return header->lines;
    }
    std::string question;
    cycle_emit(question, "// PTX's header, asked for sm_%d%d of NVRTC %d.%d\n", major, minor, compiler->major,
               compiler->minor);
    question += "extern \"C\" __global__ void cycle_probe(void)\n{\n}\n";
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, question);
    const std::vector<char> kept = path.empty() ? std::vector<char>() : cycle_cache_read(path, question);
    std::string answer(kept.begin(), kept.end());
    const int found = !answer.empty();
    nvrtcProgram program = NULL;
    if (!found && (compiler->create(&program, question.c_str(), "cycle_probe.cu", 0, NULL, NULL) == NVRTC_SUCCESS))
    {
        char architecture[48];
        snprintf(architecture, sizeof(architecture), "--gpu-architecture=compute_%d%d", major, minor);
        const char *const options[] = {architecture};
        size_t size = 0u;
        if ((compiler->compile(program, 1, options) == NVRTC_SUCCESS)
            && (compiler->ptx_size(program, &size) == NVRTC_SUCCESS) && (size > 1u))
        {
            std::vector<char> ptx(size);
            if (compiler->ptx(program, ptx.data()) == NVRTC_SUCCESS)
            {
                ptx[size - 1u] = '\0';
                answer = cycle_ptx_header_lines(ptx.data());
            }
        }
        compiler->destroy(&program);
        if (!answer.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, question, std::vector<char>(answer.begin(), answer.end()));
        }
    }
    header->lines = answer;
    if (report != 0)
    {
        fprintf(stderr, "  cycle: PTX's header for sm_%d%d %s: %s\n", major, minor,
                found ? "read from the cache" : "asked of NVRTC", answer.empty() ? "none" : answer.c_str());
    }
    return header->lines;
}

// the program found in this process by its text, else in the cache, else built and kept in both, then loaded as a
// library: PTX where `ptx`, which nvJitLink assembles as it links it against the operator block, else C source that
// NVRTC compiles first. `written` is the milliseconds the text took to write, for the report. 0 where the build or the
// load failed
static int cycle_program_hold(const EngineRecordLayout *layout, CycleRecord *record, const CycleOperatorBlock *operators,
                              const std::string &text, int ptx, int lto, double written, int report)
{
    const char *const kind = (ptx != 0) ? "PTX" : ((lto != 0) ? "LTO-IR" : "relocatable cubin");
    for (size_t at = 0u; at < s_cycle_programs.size(); at += 1u)
    {
        if (s_cycle_programs[at].source == text)
        {
            s_cycle_programs[at].holders += 1ull;
            record->kernel = s_cycle_programs[at].kernel;
            record->compiled = 1u;
            if (report != 0)
            {
                fprintf(stderr, "  cycle: a program of %u steps found in this process, as %s\n", layout->steps, kind);
            }
            return 1;
        }
    }
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, text);
    std::vector<char> cubin = path.empty() ? std::vector<char>() : cycle_cache_read(path, text);
    const int found = !cubin.empty();
    size_t object_bytes = 0u;
    double compile_milliseconds = 0.0;
    double link_milliseconds = 0.0;
    if (!found)
    {
        const auto began = std::chrono::steady_clock::now();
        // PTX goes to nvJitLink as its text with the NUL that ends it
        const std::vector<char> object = (ptx != 0)
                                       ? std::vector<char>(text.c_str(), text.c_str() + text.size() + 1u)
                                       : cycle_program_compile(text, "cycle_program.cu", operators->major,
                                                               operators->minor, lto, report);
        const auto compiled = std::chrono::steady_clock::now();
        cubin = object.empty() ? std::vector<char>() : cycle_program_link(operators, object, lto, ptx, report);
        const auto linked = std::chrono::steady_clock::now();
        object_bytes = object.size();
        compile_milliseconds = std::chrono::duration<double, std::milli>(compiled - began).count();
        link_milliseconds = std::chrono::duration<double, std::milli>(linked - compiled).count();
        if (!cubin.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, text, cubin);
        }
    }
    CycleCompiledProgram program;
    program.library = NULL;
    program.kernel = NULL;
    program.holders = 1ull;
    const int loaded = !cubin.empty()
                    && (cudaLibraryLoadData(&program.library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u) == cudaSuccess)
                    && (cudaLibraryGetKernel(&program.kernel, program.library, "cycle_program") == cudaSuccess);
    if (!loaded)
    {
        if (program.library != NULL)
        {
            cudaLibraryUnload(program.library);
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps as %s did not build (%s)\n", layout->steps, kind,
                    cubin.empty() ? ((ptx != 0) ? "nvJitLink refused it" : "NVRTC or nvJitLink refused it")
                                  : "its cubin did not load");
        }
        return 0;
    }
    program.source = text;
    s_cycle_programs.push_back(program);
    record->kernel = program.kernel;
    record->compiled = 1u;
    if ((report != 0) && found)
    {
        fprintf(stderr, "  cycle: a program of %u steps read from the cache, %zu bytes of cubin, as %s\n",
                layout->steps, cubin.size(), kind);
    }
    else if ((report != 0) && (ptx != 0))
    {
        fprintf(stderr, "  cycle: a program of %u steps for sm_%d%d as PTX: written in %.1f ms to %zu bytes, "
                        "assembled and linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, operators->major, operators->minor, written, object_bytes, link_milliseconds,
                cubin.size());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: a program of %u steps for sm_%d%d as %s: written in %.1f ms, compiled in %.1f ms to "
                        "%zu bytes, linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, operators->major, operators->minor, kind, written, compile_milliseconds, object_bytes,
                link_milliseconds, cubin.size());
    }
    return 1;
}

// the program's lane written as PTX and built, else its C source compiled by NVRTC and built, found in this process or
// the cache where either was built before, and the places it holds in shared memory set. PTX is not written where the
// block is LTO-IR or CYCLE_RECORD_NVRTC=1. 0 where it stays on the interpreter: no NVRTC or nvJitLink, a step neither
// holds, or a compile, link or load that failed
static int cycle_record_compile(const EngineRecordLayout *layout, CycleRecord *record)
{
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int lto = cycle_environment_set("CYCLE_RECORD_LTO");
    int device = 0;
    int major = 0;
    int minor = 0;
    if (!cycle_compiler_ready() || !cycle_linker_ready() || (cudaGetDevice(&device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, device) != cudaSuccess))
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (NVRTC, nvJitLink or the device "
                            "could not be read)\n",
                    layout->steps);
        }
        return 0;
    }
    const CycleOperatorBlock *const operators = cycle_operator_block(major, minor, lto, report);
    if (operators == NULL)
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (the operator block did not "
                            "compile)\n",
                    layout->steps);
        }
        return 0;
    }
    if ((lto == 0) && (cycle_environment_set("CYCLE_RECORD_NVRTC") == 0))
    {
        const std::string &header = cycle_ptx_header(major, minor, report);
        unsigned int places = 0u;
        const auto began = std::chrono::steady_clock::now();
        const std::string ptx = header.empty() ? std::string() : cycle_program_ptx(layout, operators, header, &places);
        const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
        if (!ptx.empty() && cycle_program_hold(layout, record, operators, ptx, 1, lto, written, report))
        {
            record->places = places;
            return 1;
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps goes to NVRTC (%s)\n", layout->steps,
                    header.empty() ? "PTX's header could not be read" : (ptx.empty() ? "a step the lane does not hold"
                                                                                    : "its PTX did not build"));
        }
    }
    const auto began = std::chrono::steady_clock::now();
    const std::string source = cycle_program_source(layout, operators);
    const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    if (source.empty())
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (a step it does not hold)\n",
                    layout->steps);
        }
        return 0;
    }
    if (!cycle_program_hold(layout, record, operators, source, 0, lto, written, report))
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter\n", layout->steps);
        }
        return 0;
    }
    record->places = cycle_program_places(layout);
    return 1;
}

// the block's CRC-64 over every word before its checksum
static unsigned long long cycle_block_seal(const EngineProgramBlock *block)
{
    // the block is 64-bit words throughout, asserted above, so it reads as them
    return crc_words(CRC_TABLE, (const unsigned long long *)block, offsetof(EngineProgramBlock, checksum) / 8u);
}

extern "C" int cycle_record_compiled(const CycleRecord *record)
{
    return ((record != NULL) && (record->compiled != 0u)) ? 1 : 0;
}

extern "C" const EngineProgramBlock *cycle_record_block(const CycleRecord *record)
{
    return (record != NULL) ? record->block : NULL;
}

// the compiled program's registers laid in shared memory: a thread's places a word each and the file's signs a byte
// each, for as many threads as one thread block's shared memory holds beside the kernel's own, a whole number of warps
// up to CYCLE_BLOCK where a warp fits. A program written as PTX that calls nothing holds its registers itself and takes
// no places, and runs CYCLE_BLOCK threads a thread block. The kernel is let take that much and prefers shared memory to
// L1, and the device is asked how many such thread blocks it holds at once. 0 where not one thread's registers fit or
// the runtime refuses any of it, which leaves the program on the interpreter
static int cycle_record_share(CycleRecord *record, size_t kernel_bytes)
{
    int device = 0;
    int most = 0;
    int processors = 0;
    if ((cudaGetDevice(&device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&most, cudaDevAttrMaxSharedMemoryPerBlockOptin, device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device) != cudaSuccess))
    {
        return 0;
    }
    const unsigned long long thread_bytes = (record->places != 0u) ? ((4ull * record->places) + record->file_limbs)
                                                                    : 0ull;
    // a device's shared memory a thread block is never negative
    const unsigned long long room = ((unsigned long long)most > kernel_bytes) ? ((unsigned long long)most - kernel_bytes)
                                                                               : 0ull;
    const unsigned long long fit = (thread_bytes != 0ull) ? (room / thread_bytes) : CYCLE_BLOCK;
    const unsigned long long held = (fit < CYCLE_BLOCK) ? fit : CYCLE_BLOCK;
    const unsigned long long threads = (held >= 32ull) ? (held - (held % 32ull)) : held;
    if (threads == 0ull)
    {
        return 0;
    }
    // at most CYCLE_BLOCK threads, and at most the device's shared memory a thread block, both far under 2^31
    record->threads = (unsigned int)threads;
    record->register_bytes = threads * thread_bytes;
    record->shared_bytes = record->register_bytes + kernel_bytes;
    int blocks = 0;
    const int ok = (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributeMaxDynamicSharedMemorySize,
                                         (int)record->register_bytes) == cudaSuccess)
                && (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributePreferredSharedMemoryCarveout,
                                         (int)cudaSharedmemCarveoutMaxShared) == cudaSuccess)
                && (cudaOccupancyMaxActiveBlocksPerMultiprocessor(&blocks, (const void *)record->kernel,
                                                                  (int)record->threads,
                                                                  (size_t)record->register_bytes) == cudaSuccess)
                && (blocks > 0);
    // a count of thread blocks and of processors are positive where the runtime gave them
    record->resident = (ok != 0) ? ((unsigned long long)blocks * (unsigned long long)processors) : 0ull;
    return ok;
}

extern "C" long cycle_record_load(const EngineRecordLayout *layout, CycleRecord **record_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_REFUSED;
    }
    int asked = CYCLE_HELD((layout != NULL) && (record_out != NULL), layout, error, ENGINE_ERROR_REQUEST)
             && CYCLE_HELD((layout->step_table != NULL) && (layout->steps != 0u)
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
    // the block lies in device memory, where the program's thread blocks check in without leaving the device; the host
    // keeps its own copy, read back once each launch has ended
    record->block = (EngineProgramBlock *)calloc(1u, sizeof(EngineProgramBlock));
    ok = ok && CYCLE_HELD(record->block != NULL, &record->block, error, ENGINE_ERROR_RESOURCE)
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_block, sizeof(EngineProgramBlock)), &record->device_block, error)
      && CYCLE_TOOK(cudaMalloc((void **)&record->hot, sizeof(CycleHot)), &record->hot, error);
    if (ok == 0)
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    // the program is its steps, its shape and its tables, and its signum is taken over all three in that order
    const unsigned int shape[6] = {layout->members,   layout->in_limbs[0], layout->in_limbs[1],
                                   layout->in_limbs[2], layout->out_bits,  layout->file_limbs};
    std::vector<unsigned char> program((size_t)layout->steps * sizeof(DeviceRecordStep));
    memcpy(program.data(), layout->step_table, program.size());
    // a word's bytes are read as bytes, as the signum takes them
    const unsigned char *const shape_bytes = (const unsigned char *)shape;
    program.insert(program.end(), shape_bytes, shape_bytes + sizeof(shape));
    if (layout->table_word_count != 0ull)
    {
        // a table's words are read as bytes, as the signum takes them
        const unsigned char *const table_bytes = (const unsigned char *)layout->table_values;
        program.insert(program.end(), table_bytes,
                       table_bytes + ((size_t)layout->table_word_count * sizeof(unsigned int)));
    }
    const ObsignatioSignumRequest signum = {program.data(), program.size(), NULL, OBSIGNATIO_MODE_HASH,
                                            record->block->signature.bytes, ENGINE_SIGNUM_BYTES, error};
    if (obsignatio_signum(&signum) == OBSIGNATIO_REFUSED)
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    record->block->span = layout->file_limbs;
    record->block->state = ENGINE_PROGRAM_LAID;
    record->block->checksum = cycle_block_seal(record->block);
    if (!CYCLE_TOOK(cudaMemcpy(record->device_block, record->block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                    record->device_block, error))
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
    if ((cycle_environment_set("CYCLE_RECORD_INTERPRET") == 0) && (cycle_record_compile(layout, record) == 0))
    {
        // every call above held, and an error the runtime still holds is the attempt's own: the interpreter runs in
        // its place, and the error is dropped before a run reads the runtime's last error as its own
        cudaGetLastError();
    }
    cudaFuncAttributes attributes;
    const int attributed = (record->compiled != 0u)
                        && (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) == cudaSuccess);
    if (attributed != 0)
    {
        // a register count and a frame's bytes are never negative
        record->registers = (unsigned long long)attributes.numRegs;
        record->local_bytes = (unsigned long long)attributes.localSizeBytes;
    }
    // a compiled program whose registers shared memory cannot hold runs on the interpreter
    record->compiled = ((attributed != 0) && cycle_record_share(record, attributes.sharedSizeBytes)) ? 1u : 0u;
    if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (record->compiled != 0u))
    {
        fprintf(stderr, "  cycle: the program holds %llu registers a thread, a %llu-byte local frame and %u places a "
                        "thread in shared memory: %u threads a thread block in %llu bytes, %llu thread blocks at once\n",
                record->registers, record->local_bytes, record->places, record->threads, record->shared_bytes,
                record->resident);
    }
    else if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (attributed != 0))
    {
        fprintf(stderr, "  cycle: a program of %u places a thread runs on the interpreter (shared memory does not "
                        "hold one thread's)\n",
                record->places);
    }
    // a grant the runtime could not read is left 0, and its error is dropped as the attempt's own
    cudaGetLastError();
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
    cudaFree(record->hot);
    cudaFree(record->device_block);
    // the record gives back its hold on the program it loaded, compiled or left on the interpreter after, and the last
    // hold released unloads it
    for (size_t at = 0u; (record->kernel != NULL) && (at < s_cycle_programs.size()); at += 1u)
    {
        if (s_cycle_programs[at].kernel == record->kernel)
        {
            s_cycle_programs[at].holders -= 1ull;
            if (s_cycle_programs[at].holders == 0ull)
            {
                cudaLibraryUnload(s_cycle_programs[at].library);
                s_cycle_programs.erase(s_cycle_programs.begin() + (std::ptrdiff_t)at);
            }
            break;
        }
    }
    free(record->block);
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

// The compiled program run resident. Its block is laid for this run and sent to the device, and the program is
// launched, then launched again from where its block says it stands, until every lane is done. The host reads the
// block back only between launches, when it is sealed: a device block whose seal does not hold (written while no launch
// held it), a launch that failed, or a launch that left the block anywhere but yielded or done refuses the run, and
// the host's copy is left sealed at the fault with the error's module and site. It runs on as many thread blocks as the
// device holds at once, or fewer where the lanes need fewer, each of the threads its registers' shared memory holds.
static int cycle_record_resident(const CycleRecord *record, CycleCompiledLaunch program, EngineError *error)
{
    const unsigned long long needed = (program.count + record->threads - 1ull) / record->threads;
    // the device's thread blocks at once are a small count, far under 2^31
    const unsigned int blocks = (unsigned int)((needed < record->resident) ? needed : record->resident);
    EngineProgramBlock *const block = record->block;
    const unsigned long long ttl = 1000ull * cycle_environment_microseconds("CYCLE_RECORD_TTL",
                                                                              CYCLE_PROGRAM_TTL_MICROSECONDS);
    const unsigned long long wdt = 1000ull * CYCLE_PROGRAM_WDT_MICROSECONDS;
    const EngineSignum signature = block->signature;
    const unsigned long long generation = block->generation + 1ull;
    memset(block, 0, sizeof(EngineProgramBlock));
    block->signature = signature;
    block->generation = generation;
    block->command = ENGINE_PROGRAM_RUN;
    block->grant_registers = record->registers;
    block->grant_threads = (unsigned long long)blocks * record->threads;
    block->grant_bytes = record->local_bytes * block->grant_threads;
    block->grant_shared = record->shared_bytes;
    block->state = ENGINE_PROGRAM_LAID;
    block->span = record->file_limbs;
    block->ttl = ttl;
    block->wdt = wdt;
    block->lanes = program.count;
    // a device address is held as a 64-bit word, as every word of the block is
    block->result = (unsigned long long)(uintptr_t)program.out;
    block->result_words = program.count * record->out_limbs;
    block->checksum = cycle_block_seal(block);
    program.hot = record->hot;
    // the block is 64-bit words throughout, and the program reads it as them at its device address
    program.block = (unsigned long long *)record->device_block;
    program.ttl = ttl;
    program.checkin_every = wdt / CYCLE_PROGRAM_CHECKINS_PER_WDT;
    program.places = record->places;
    EngineProgramBlock *const device_block = record->device_block;
    int ok = CYCLE_TOOK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                        device_block, error)
          && CYCLE_TOOK(cudaMemset(record->hot, 0, sizeof(CycleHot)), record->hot, error);
    int running = ok;
    while (running != 0)
    {
        ok = CYCLE_TOOK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost), device_block,
                        error)
          && CYCLE_HELD(block->checksum == cycle_block_seal(block), block, error, ENGINE_ERROR_LOGIC);
        if (ok == 0)
        {
            break;
        }
        block->launches += 1ull;
        block->owner = block->launches;
        block->state = ENGINE_PROGRAM_RUNNING;
        program.launch_number = block->launches;
        ok = CYCLE_TOOK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                        device_block, error);
        // a launch's start and its thread blocks gone begin at 0, and the next lane runs on from the last launch's
        ok = ok
          && CYCLE_TOOK(cudaMemset(&record->hot->launch_start, 0, 2u * sizeof(unsigned long long)), record->hot, error);
        void *arguments[1] = {&program};
        // a library's kernel handle is what the runtime launches in place of a kernel's address
        ok = ok
          && CYCLE_TOOK(cudaLaunchKernel((const void *)record->kernel, dim3(blocks), dim3(record->threads), arguments,
                                         (size_t)record->register_bytes, 0),
                        program.out, error);
        ok = ok && CYCLE_TOOK(cudaDeviceSynchronize(), program.out, error);
        unsigned int refused = 0u;
        ok = ok
          && CYCLE_TOOK(cudaMemcpy(&refused, record->device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                        record->device_refused, error)
          && CYCLE_TOOK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost),
                        device_block, error);
        const unsigned long long state = block->state;
        ok = ok && CYCLE_HELD((state == ENGINE_PROGRAM_YIELDED) || (state == ENGINE_PROGRAM_DONE), block, error,
                              ENGINE_ERROR_LOGIC);
        block->refused = refused;
        block->runtime += block->exectime;
        if (ok == 0)
        {
            block->state = ENGINE_PROGRAM_FAULT;
            // an engine module and a site are small non-negative counts, held whole in a 64-bit word
            block->error_module = (unsigned long long)error->module;
            block->error_site = (unsigned long long)error->site;
        }
        block->checksum = cycle_block_seal(block);
        // the sealed block goes back to the device, where the next launch finds it; a fault is left sealed on the
        // host's copy whether or not the device can still take it
        const cudaError_t sent = cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice);
        ok = ok && CYCLE_TOOK(sent, device_block, error);
        running = (ok != 0) && (state == ENGINE_PROGRAM_YIELDED);
    }
    return ok;
}

// one launch of a record program, compiled or on the interpreter, run to its end: a compiled program runs resident,
// launched again until it is done. With `milliseconds` it is timed by events on either side of it, the device's own
// time between them
static int cycle_record_launch(const CycleRecord *record, const CycleRecordLaunch &launch, unsigned int blocks,
                               int compiled, float *milliseconds, EngineError *error)
{
    cudaEvent_t began = NULL;
    cudaEvent_t ended = NULL;
    int ok = (milliseconds == NULL)
          || (CYCLE_TOOK(cudaEventCreate(&began), &began, error) && CYCLE_TOOK(cudaEventCreate(&ended), &ended, error)
              && CYCLE_TOOK(cudaEventRecord(began, 0), began, error));
    if ((ok != 0) && (compiled != 0))
    {
        CycleCompiledLaunch program;
        memset(&program, 0, sizeof(program));
        for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
        {
            program.in[member] = launch.in[member];
            program.bodies[member] = launch.bodies[member];
        }
        program.index = launch.index;
        program.tables = launch.tables;
        program.out = launch.out;
        program.refused = launch.refused;
        program.count = launch.count;
        ok = cycle_record_resident(record, program, error);
    }
    else if ((ok != 0) && (record->file_limbs <= 64u) && (record->divides != 0u))
    {
        cycle_record_kernel<64u, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if ((ok != 0) && (record->file_limbs <= 64u))
    {
        cycle_record_kernel<64u, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if ((ok != 0) && (record->divides != 0u))
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if (ok != 0)
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    // the launch's own error is read and reset whichever way it launched
    const cudaError_t launched = cudaGetLastError();
    ok = ok && CYCLE_TOOK(launched, launch.out, error);
    ok = ok && ((milliseconds == NULL) || CYCLE_TOOK(cudaEventRecord(ended, 0), ended, error));
    ok = ok && CYCLE_TOOK(cudaDeviceSynchronize(), launch.out, error);
    ok = ok && ((milliseconds == NULL) || CYCLE_TOOK(cudaEventElapsedTime(milliseconds, began, ended), milliseconds, error));
    if (began != NULL)
    {
        cudaEventDestroy(began);
    }
    if (ended != NULL)
    {
        cudaEventDestroy(ended);
    }
    return ok;
}

// CYCLE_RECORD_CHECK: the compiled program has run into the request's records; the interpreter runs the same lanes
// into records of its own, and both runs' records and refusals must be the same word for word. The compiled run's
// refusals are put back for the run to read
static int cycle_record_check(const CycleRecord *record, CycleRecordLaunch launch, unsigned int blocks,
                              float compiled_milliseconds, int report, EngineError *error)
{
    const size_t words = (size_t)launch.count * record->out_limbs;
    std::vector<unsigned int> compiled_records(words);
    std::vector<unsigned int> interpreted_records(words);
    unsigned int compiled_refused = 0u;
    unsigned int interpreted_refused = 0u;
    unsigned int *interpreted = NULL;
    float interpreted_milliseconds = 0.0f;
    int ok = CYCLE_TOOK(cudaMemcpy(&compiled_refused, record->device_refused, sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost),
                        record->device_refused, error)
          && CYCLE_TOOK(cudaMemcpy(compiled_records.data(), launch.out, words * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost),
                        launch.out, error)
          && CYCLE_TOOK(cudaMalloc((void **)&interpreted, words * sizeof(unsigned int)), &interpreted, error)
          && CYCLE_TOOK(cudaMemset(record->device_refused, 0, sizeof(unsigned int)), record->device_refused, error);
    launch.out = interpreted;
    ok = ok && cycle_record_launch(record, launch, blocks, 0, (report != 0) ? &interpreted_milliseconds : NULL, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(&interpreted_refused, record->device_refused, sizeof(unsigned int),
                               cudaMemcpyDeviceToHost),
                    record->device_refused, error)
      && CYCLE_TOOK(cudaMemcpy(interpreted_records.data(), interpreted, words * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost),
                    interpreted, error)
      && CYCLE_TOOK(cudaMemcpy(record->device_refused, &compiled_refused, sizeof(unsigned int), cudaMemcpyHostToDevice),
                    record->device_refused, error);
    cudaFree(interpreted);
    size_t differs = words;
    for (size_t at = 0u; (ok != 0) && (differs == words) && (at < words); at += 1u)
    {
        differs = (compiled_records[at] != interpreted_records[at]) ? at : words;
    }
    const int same = (differs == words) && (compiled_refused == interpreted_refused);
    if ((ok != 0) && (report != 0))
    {
        fprintf(stderr, "  cycle: %llu lanes, compiled %.3f ms, interpreted %.3f ms, refused %u and %u, %s\n",
                launch.count, compiled_milliseconds, interpreted_milliseconds, compiled_refused, interpreted_refused,
                (same != 0) ? "the same records" : "records differ");
    }
    if ((ok != 0) && (same == 0) && (differs != words))
    {
        fprintf(stderr, "  cycle: the compiled record program differs from the interpreter at lane %zu, word %zu: %08x "
                        "against %08x\n",
                differs / record->out_limbs, differs % record->out_limbs, compiled_records[differs],
                interpreted_records[differs]);
    }
    return ok && CYCLE_HELD(same != 0, record->device_refused, error, ENGINE_ERROR_LOGIC);
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
        // with no index, lane i reads record i of a member, or its one record where it has one
        if (!CYCLE_HELD((request->device_in[member] != NULL) && (request->bodies[member] != 0ull)
                            && ((request->device_index != NULL) || (request->count <= request->bodies[member])
                                || (request->bodies[member] == 1ull)),
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
    const int compiled = (record->compiled != 0u) ? 1 : 0;
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int check = (compiled != 0) && (cycle_environment_set("CYCLE_RECORD_CHECK") != 0);
    unsigned int refused = 1u;
    size_t stack = 0u;
    float milliseconds = 0.0f;
    int ok = CYCLE_TOOK(cudaDeviceGetLimit(&stack, cudaLimitStackSize), &stack, error)
          && CYCLE_TOOK(cudaMemset(record->device_refused, 0, sizeof(unsigned int)), record->device_refused, error);
    ok = ok && cycle_record_launch(record, launch, blocks, compiled, (report != 0) ? &milliseconds : NULL, error);
    ok = ok && ((check == 0) || cycle_record_check(record, launch, blocks, milliseconds, report, error));
    if ((ok != 0) && (report != 0) && (check == 0))
    {
        fprintf(stderr, "  cycle: %llu lanes %s in %.3f ms\n", request->count,
                (compiled != 0) ? "compiled" : "interpreted", milliseconds);
    }
    if ((ok != 0) && (report != 0) && (compiled != 0))
    {
        fprintf(stderr, "  cycle: the program ran %llu launches, %llu check-ins, %.3f ms on the device\n",
                record->block->launches, record->block->checkin, (double)record->block->runtime / 1e6);
    }
    // the frame's reservation is given back whether or not the sweep held
    const int returned = cycle_stack_return(stack, request->device_out, error);
    ok = ok && returned
      && CYCLE_TOOK(cudaMemcpy(&refused, record->device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    record->device_refused, error)
      && CYCLE_HELD(refused == 0u, record->device_refused, error, ENGINE_ERROR_REQUEST);
    return (ok != 0) ? (long)request->count : CYCLE_REFUSED;
}

// 1 where a record's `bits` bits at `offset` are not all zero
__device__ static int cycle_latch_holds(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned int held = 0u;
    for (unsigned int bit = offset; bit < (offset + bits);)
    {
        const unsigned int shift = bit % 32u;
        const unsigned int left = offset + bits - bit;
        const unsigned int taken = (left < (32u - shift)) ? left : (32u - shift);
        const unsigned int mask = (taken == 32u) ? 0xFFFFFFFFu : (((1u << taken) - 1u) << shift);
        held |= record[bit / 32u] & mask;
        bit += taken;
    }
    return (held != 0u) ? 1 : 0;
}

// the latch over the records: each thread scans its lanes from its lowest and stops at the first whose output holds,
// each warp takes the least of its threads' by a tree of shuffles, and each warp's goes to one atomic minimum over the
// device. Every thread of a warp reaches the shuffles, the block being whole warps
__global__ static void cycle_latch_kernel(const unsigned int *records, unsigned long long count, unsigned int out_limbs,
                                          unsigned int offset, unsigned int bits, unsigned long long *first)
{
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long found = CYCLE_LATCH_NONE;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         (found == CYCLE_LATCH_NONE) && (lane < count); lane += stride)
    {
        found = (cycle_latch_holds(&records[lane * out_limbs], offset, bits) != 0) ? lane : CYCLE_LATCH_NONE;
    }
    for (unsigned int reach = 16u; reach > 0u; reach /= 2u)
    {
        const unsigned long long other = __shfl_down_sync(0xFFFFFFFFu, found, reach);
        found = (other < found) ? other : found;
    }
    if (((threadIdx.x % 32u) == 0u) && (found != CYCLE_LATCH_NONE))
    {
        atomicMin(first, found);
    }
}

static_assert((CYCLE_BLOCK % 32u) == 0u, "cycle: the latch's thread blocks are whole warps");

extern "C" long cycle_record_latch(const CycleRecordLatchRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!CYCLE_HELD((request->records != NULL) && (request->first != NULL) && (request->count != 0ull)
                        && (request->out_limbs != 0u) && (request->bits != 0u)
                        && (((unsigned long long)request->offset + request->bits)
                            <= (32ull * (unsigned long long)request->out_limbs)),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    unsigned long long *device_first = NULL;
    unsigned long long first = CYCLE_LATCH_NONE;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MOST) ? needed : CYCLE_RECORD_BLOCKS_MOST);
    int ok = CYCLE_TOOK(cudaMalloc((void **)&device_first, sizeof(unsigned long long)), &device_first, error)
          && CYCLE_TOOK(cudaMemcpy(device_first, &first, sizeof(unsigned long long), cudaMemcpyHostToDevice),
                        device_first, error);
    if (ok != 0)
    {
        cycle_latch_kernel<<<blocks, CYCLE_BLOCK>>>(request->records, request->count, request->out_limbs,
                                                    request->offset, request->bits, device_first);
    }
    ok = ok && CYCLE_TOOK(cudaGetLastError(), device_first, error)
      && CYCLE_TOOK(cudaDeviceSynchronize(), device_first, error)
      && CYCLE_TOOK(cudaMemcpy(&first, device_first, sizeof(unsigned long long), cudaMemcpyDeviceToHost), device_first,
                    error);
    cudaFree(device_first);
    if (ok == 0)
    {
        return CYCLE_REFUSED;
    }
    *request->first = first;
    return (long)request->count;
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
    size_t stack = 0u;
    if (!CYCLE_TOOK(cudaDeviceGetLimit(&stack, cudaLimitStackSize), &stack, error))
    {
        return CYCLE_REFUSED;
    }
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
    // the sweep runs on after its launch, so a grown stack is given back once it ends
    const int returned = cycle_stack_return(stack, request->device_out, error);
    return ((ok != 0) && (returned != 0)) ? (long)request->count : CYCLE_REFUSED;
}
