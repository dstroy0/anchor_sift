// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_launch.cu: keys loaded and the sweep launched
#include "cycle_internal.h"

extern "C" long cycle_key_load(const EngineKeyLayout *layout, CycleKey **key_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_ERROR;
    }
    if (!CYCLE_CHECK((layout != NULL) && (key_out != NULL), layout, error, ENGINE_ERROR_REQUEST) ||
        !CYCLE_CHECK((layout->term_table != NULL) && (layout->weights != NULL) && (layout->terms != 0u), layout, error,
                     ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    *key_out = NULL;
    CycleKey *const key = (CycleKey *)calloc(1u, sizeof(CycleKey));
    int ok = CYCLE_CHECK(key != NULL, key_out, error, ENGINE_ERROR_RESOURCE);
    ok = ok && CYCLE_STATUS_CHECK(cudaMalloc((void **)&key->device_terms, (size_t)layout->terms * sizeof(DeviceTerm)),
                                  &key->device_terms, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaMalloc((void **)&key->device_weights,
                                             (size_t)(layout->weight_count + 1ull) * sizeof(unsigned int)),
                                  &key->device_weights, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaMemcpy(key->device_terms, layout->term_table,
                                             (size_t)layout->terms * sizeof(DeviceTerm), cudaMemcpyHostToDevice),
                                  key->device_terms, error);
    ok = ok &&
         CYCLE_STATUS_CHECK(cudaMemcpy(key->device_weights, layout->weights,
                                       (size_t)layout->weight_count * sizeof(unsigned int), cudaMemcpyHostToDevice),
                            key->device_weights, error);
    if (ok == 0)
    {
        cycle_key_release(key);
        return CYCLE_ERROR;
    }
    key->terms = layout->terms;
    key->bits = layout->bits;
    key->columns = layout->columns;
    key->planes = layout->planes;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        key->range[axis] = layout->range[axis];
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

static CycleResident s_cycle_resident;

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
    if (!CYCLE_STATUS_CHECK(cudaDeviceGetLimit(&after, cudaLimitStackSize), &after, error))
    {
        return 0;
    }
    return (after <= before) || (CYCLE_STATUS_CHECK(cudaDeviceSynchronize(), evacaddr, error) &&
                                 CYCLE_STATUS_CHECK(cudaDeviceSetLimit(cudaLimitStackSize, before), evacaddr, error));
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

template <unsigned int WIDE> static int cycle_launch(CycleLaunch launch, EngineError *error)
{
    int device = 0;
    int cooperative = 0;
    int processors = 0;
    int per_processor = 0;
    int ok = CYCLE_STATUS_CHECK(cudaGetDevice(&device), &device, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaDeviceGetAttribute(&cooperative, cudaDevAttrCooperativeLaunch, device),
                                  &cooperative, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device),
                                  &processors, error);
    // the block size is 256. It converts to int exactly
    ok = ok && CYCLE_STATUS_CHECK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&per_processor, cycle_kernel<WIDE>,
                                                                                (int)CYCLE_BLOCK, 0u),
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
        return CYCLE_STATUS_CHECK(cudaLaunchCooperativeKernel((const void *)cycle_kernel<WIDE>, dim3(blocks),
                                                              dim3(CYCLE_BLOCK), arguments, 0u, 0),
                                  launch.out, error);
    }
    const unsigned int blocks = (unsigned int)((needed < 0x7FFFFFFFull) ? needed : 0x7FFFFFFFull);
    cycle_step_digits(launch, (unsigned long long)blocks * CYCLE_BLOCK);
    for (unsigned int sweep = 0u; (sweep < ENGINE_AXES) && (ok != 0); sweep += 1u)
    {
        launch.sweep_first = sweep;
        launch.sweep_last = sweep;
        cycle_kernel<WIDE><<<blocks, CYCLE_BLOCK>>>(launch);
        ok = CYCLE_STATUS_CHECK(cudaGetLastError(), launch.out, error);
    }
    return ok;
}

extern "C" long cycle_run(const CycleRunRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_ERROR;
    }
    EngineError *const error = request->error;
    if (!CYCLE_CHECK((request->key != NULL) && (request->atoms != NULL) && (request->count != 0ull) &&
                         (request->device_out != NULL),
                     request, error, ENGINE_ERROR_REQUEST) ||
        !CYCLE_CHECK(((unsigned long long)request->limbs * 32ull) >= request->key->bits, &request->limbs, error,
                     ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    const Atom *const extent = &request->atoms[0];
    if (!CYCLE_CHECK((extent->depth != 0ull) && (extent->height != 0ull) && (extent->width != 0ull), extent, error,
                     ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    for (unsigned long long atom = 0ull; atom < request->count; atom += 1ull)
    {
        const Atom *const each = &request->atoms[atom];
        if (!CYCLE_CHECK((each->lanes != NULL) && (each->depth == extent->depth) && (each->height == extent->height) &&
                             (each->width == extent->width),
                         each, error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_ERROR;
        }
    }
    const unsigned long long maximum = 0xFFFFFFFFFFFFFFFFull;
    if (!CYCLE_CHECK((extent->height <= (maximum / extent->width)) &&
                         (extent->depth <= (maximum / (extent->height * extent->width))),
                     extent, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    const unsigned long long voxels = extent->depth * extent->height * extent->width;
    if (!CYCLE_CHECK((request->count <= (maximum / voxels)) &&
                         ((request->count * voxels) <= (maximum / 4ull / (request->key->planes + 1u))),
                     &request->count, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    const unsigned long long total = request->count * voxels;

    CycleResident *const resident = &s_cycle_resident;
    const size_t scratch_words = (size_t)(total * request->key->planes);
    int ok = 1;
    if (scratch_words > resident->scratch_words)
    {
        cudaFree(resident->scratch);
        resident->scratch = NULL;
        resident->scratch_words = 0u;
        ok = CYCLE_STATUS_CHECK(cudaMalloc((void **)&resident->scratch, scratch_words * sizeof(unsigned int)),
                                &resident->scratch, error);
        resident->scratch_words = (ok != 0) ? scratch_words : 0u;
    }
    if ((ok != 0) && (request->count > resident->table_capacity))
    {
        cudaFree(resident->table);
        resident->table = NULL;
        resident->table_capacity = 0u;
        ok = CYCLE_STATUS_CHECK(
            cudaMalloc((void **)&resident->table, (size_t)request->count * sizeof(const unsigned short *)),
            &resident->table, error);
        resident->table_capacity = (ok != 0) ? (size_t)request->count : 0u;
    }
    std::vector<const unsigned short *> table((size_t)request->count);
    for (size_t atom = 0u; atom < table.size(); atom += 1u)
    {
        table[atom] = request->atoms[atom].lanes;
    }
    ok = ok && CYCLE_STATUS_CHECK(cudaMemcpy(resident->table, table.data(),
                                             table.size() * sizeof(const unsigned short *), cudaMemcpyHostToDevice),
                                  resident->table, error);

    CycleLaunch launch;
    memset(&launch, 0, sizeof(launch));
    launch.extent[0] = extent->depth;
    launch.extent[1] = extent->height;
    launch.extent[2] = extent->width;
    launch.stride[0] = extent->height * extent->width;
    launch.stride[1] = extent->width;
    launch.stride[2] = 1ull;
    std::vector<unsigned long long> folds;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        launch.fold_start[axis] = (unsigned long long)folds.size();
        launch.range[axis] = request->key->range[axis];
        const unsigned long long span = launch.extent[axis] + (2ull * launch.range[axis]);
        for (unsigned long long entry = 0ull; entry < span; entry += 1ull)
        {
            const long long position = (long long)entry - (long long)launch.range[axis];
            folds.push_back(cycle_reflect(position, (long long)launch.extent[axis]) * launch.stride[axis]);
        }
    }
    if ((ok != 0) && (folds.size() > resident->fold_capacity))
    {
        cudaFree(resident->folds);
        resident->folds = NULL;
        resident->fold_capacity = 0u;
        ok = CYCLE_STATUS_CHECK(cudaMalloc((void **)&resident->folds, folds.size() * sizeof(unsigned long long)),
                                &resident->folds, error);
        resident->fold_capacity = (ok != 0) ? folds.size() : 0u;
    }
    ok = ok && CYCLE_STATUS_CHECK(cudaMemcpy(resident->folds, folds.data(), folds.size() * sizeof(unsigned long long),
                                             cudaMemcpyHostToDevice),
                                  resident->folds, error);
    if (ok == 0)
    {
        return CYCLE_ERROR;
    }

    launch.terms = request->key->device_terms;
    launch.weights = request->key->device_weights;
    launch.lanes = resident->table;
    launch.folds = resident->folds;
    launch.scratch = resident->scratch;
    launch.out = request->device_out;
    launch.voxels = voxels;
    launch.total = total;
    launch.term_count = request->key->terms;
    launch.limbs = request->limbs;
    size_t stack = 0u;
    if (!CYCLE_STATUS_CHECK(cudaDeviceGetLimit(&stack, cudaLimitStackSize), &stack, error))
    {
        return CYCLE_ERROR;
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
        ok = CYCLE_CHECK(need <= 256u, &request->key->columns, error, ENGINE_ERROR_REQUEST);
    }
    // the sweep runs on after its launch. A grown stack is given back once it ends
    const int returned = cycle_stack_return(stack, request->device_out, error);
    return ((ok != 0) && (returned != 0)) ? (long)request->count : CYCLE_ERROR;
}
