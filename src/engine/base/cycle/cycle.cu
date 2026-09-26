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
// cache. A program's source is its steps alone, each one call into the block with its places and widths as constants
// over the register file key_schedule laid, file_limbs the most it holds live at once. It is compiled as relocatable
// code and linked against the block by nvJitLink into the cubin that is loaded. A program of any length compiles. Its
// registers lie in the thread block's shared memory, sized exactly from its widths, and a thread block holds as many
// threads as that shared memory fits. The interpreter above stays the oracle, and the fallback for a program NVRTC or
// nvJitLink cannot build, this process cannot load or shared memory cannot hold one thread's registers for.
//
// The compiled program runs as a resident program with a block (EngineProgramBlock) in device memory. Its thread blocks
// take lanes a round at a time from one counter, check in to the block as they go, and leave once the launch has run
// its time to live or the block's command says to. The last one out writes where the program stands, and the run
// launches it again from there until every lane is done: a launch never outlives the display driver's watchdog, and no
// lane runs twice. The host reads the block only once a launch has ended. Five switches, read at each load or run:
// CYCLE_RECORD_INTERPRET=1 keeps every program on the interpreter, CYCLE_RECORD_CHECK=1 runs both on every launch and
// refuses the launch where their records or refusals differ, CYCLE_RECORD_REPORT=1 says on stderr where each program
// came from and how long each kernel ran, CYCLE_RECORD_TTL=<microseconds> sets a launch's time to live, and
// CYCLE_RECORD_LTO=1 builds the block and the programs as LTO-IR and links them with link-time optimization.

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

// one step's source, one call into the operator block and its put; 0 for a step this compiler does not hold, which
// leaves the whole program on the interpreter. `wide` is the width the program's scratch is laid at, and the scratch's
// places follow the file's
static int cycle_program_step(const EngineRecordLayout *layout, unsigned int at, unsigned int wide, std::string &text)
{
    const unsigned int scratch = layout->file_limbs;
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const int reads_left = (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED)
                        && (operation != ENGINE_RECORD_CONSTANT);
    // a table reads its source's low limb alone, and key_schedule leaves its left_limbs 0
    const int reads_left_whole = reads_left && (operation != ENGINE_RECORD_TABLE);
    if ((limbs == 0u) || (reads_left && (step->left >= at))
        || (reads_left_whole && !cycle_program_operand(layout, at, step->left, step->left_limbs))
        || (cycle_program_reads_right(operation) && !cycle_program_operand(layout, at, step->right, step->right_limbs)))
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
    const unsigned int left_place = reads_left ? layout->step_table[left].place : 0u;
    const unsigned int right_place = cycle_program_reads_right(operation) ? layout->step_table[right].place : 0u;
    // the step's own limbs lie inside the file, and an operand's inside its own step's
    if (((unsigned long long)place + limbs) > (unsigned long long)layout->file_limbs)
    {
        return 0;
    }
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        if ((step->member >= layout->members) || ((operation == ENGINE_RECORD_FIELD_SIGNED)
                                                  && ((right == 0u) || (((right - 1u) / 32u) >= limbs))))
        {
            return 0;
        }
        cycle_emit(text, "            cycle_field%s(atom%u, %uu, %uu, %uu, %uu, %uu);\n",
                   (operation == ENGINE_RECORD_FIELD_SIGNED) ? "_signed" : "", step->member,
                   layout->in_limbs[step->member], left, right, place, limbs);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_emit(text, "            cycle_constant(%uu, %uu, %uu, %uu);\n", left, right, place, limbs);
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
        cycle_emit(text,
                   "    const u64 body%u = (launch->index != nullptr) ? (u64)launch->index[(lane * %uull) + %uull] : lane;\n"
                   "    good = ((good != 0) && (body%u < launch->bodies[%u])) ? 1 : 0;\n"
                   "    const u32 *const atom%u = &launch->in[%u][((good != 0) ? body%u : 0ull) * %uull];\n",
                   member, layout->members, member, member, member, member, member, member, layout->in_limbs[member]);
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
// optimization where `lto`; empty where it refuses, its log then on stderr when reporting
static std::vector<char> cycle_program_link(const CycleOperatorBlock *operators, const std::vector<char> &object,
                                            int lto, int report)
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
    size_t size = 0u;
    const int linked = (linker->add(handle, kind, operators->image.data(), operators->image.size(), "cycle_operators")
                        == NVJITLINK_SUCCESS)
                    && (linker->add(handle, kind, object.data(), object.size(), "cycle_program") == NVJITLINK_SUCCESS)
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

// the program found in this process, else in the cache, else compiled, linked against the operator block and kept in
// both, then loaded as a library. 0 where it stays on the interpreter: a step not held, no NVRTC or nvJitLink, or a
// compile, link or load that failed
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
    const std::string source = cycle_program_source(layout, operators);
    if (source.empty())
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (a step it does not hold)\n",
                    layout->steps);
        }
        return 0;
    }
    for (size_t at = 0u; at < s_cycle_programs.size(); at += 1u)
    {
        if (s_cycle_programs[at].source == source)
        {
            s_cycle_programs[at].holders += 1ull;
            record->kernel = s_cycle_programs[at].kernel;
            record->compiled = 1u;
            if (report != 0)
            {
                fprintf(stderr, "  cycle: a program of %u steps found in this process\n", layout->steps);
            }
            return 1;
        }
    }
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, source);
    std::vector<char> cubin = path.empty() ? std::vector<char>() : cycle_cache_read(path, source);
    const int found = !cubin.empty();
    size_t object_bytes = 0u;
    double compile_milliseconds = 0.0;
    double link_milliseconds = 0.0;
    if (!found)
    {
        const auto began = std::chrono::steady_clock::now();
        const std::vector<char> object = cycle_program_compile(source, "cycle_program.cu", major, minor, lto, report);
        const auto compiled = std::chrono::steady_clock::now();
        cubin = object.empty() ? std::vector<char>() : cycle_program_link(operators, object, lto, report);
        const auto linked = std::chrono::steady_clock::now();
        object_bytes = object.size();
        compile_milliseconds = std::chrono::duration<double, std::milli>(compiled - began).count();
        link_milliseconds = std::chrono::duration<double, std::milli>(linked - compiled).count();
        if (!cubin.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, source, cubin);
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
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (%s)\n", layout->steps,
                    cubin.empty() ? "NVRTC or nvJitLink refused it" : "its cubin did not load");
        }
        return 0;
    }
    program.source = source;
    s_cycle_programs.push_back(program);
    record->kernel = program.kernel;
    record->compiled = 1u;
    if ((report != 0) && found)
    {
        fprintf(stderr, "  cycle: a program of %u steps read from the cache, %zu bytes of cubin\n", layout->steps,
                cubin.size());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: a program of %u steps for sm_%d%d as %s: compiled in %.1f ms to %zu bytes, linked in "
                        "%.1f ms to %zu bytes of cubin\n",
                layout->steps, major, minor, (lto != 0) ? "LTO-IR" : "relocatable cubin", compile_milliseconds,
                object_bytes, link_milliseconds, cubin.size());
    }
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
// up to CYCLE_BLOCK where a warp fits. The kernel is let take that much and prefers shared memory to L1, and the device
// is asked how many such thread blocks it holds at once. 0 where not one thread's registers fit or the runtime refuses
// any of it, which leaves the program on the interpreter
static int cycle_record_share(CycleRecord *record, const EngineRecordLayout *layout, size_t kernel_bytes)
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
    record->places = cycle_program_places(layout);
    const unsigned long long thread_bytes = (4ull * record->places) + record->file_limbs;
    // a device's shared memory a thread block is never negative
    const unsigned long long room = ((unsigned long long)most > kernel_bytes) ? ((unsigned long long)most - kernel_bytes)
                                                                               : 0ull;
    const unsigned long long fit = room / thread_bytes;
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
    record->compiled = ((attributed != 0) && cycle_record_share(record, layout, attributes.sharedSizeBytes)) ? 1u : 0u;
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
