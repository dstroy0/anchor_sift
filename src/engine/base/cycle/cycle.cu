// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

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
int cycle_stack_return(size_t before, const void *evacaddr, EngineError *error)
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
