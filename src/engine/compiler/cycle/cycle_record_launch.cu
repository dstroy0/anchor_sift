// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_record_launch.cu: the resident program, the launch, the check against the interpreter, the latch
#include "cycle_record_internal.h"

// The compiled program run resident. Its block is laid out for this run and sent to the device, and the program is
// launched, then launched again from where its block says it stands, until every lane is done. The host reads the
// block back only between launches, when it is sealed: a device block whose seal does not hold (written while no launch
// held it), a launch that failed, or a launch that left the block anywhere but yielded or done errors on the run, and
// the host's copy is left sealed at the fault with the error's module and site. It runs on as many thread blocks as the
// device holds at once, or fewer where the lanes need fewer. A thread block takes the threads its registers' shared
// memory holds, or where the lanes are few, their share of the device's processors in whole warps, so that a launch of
// a few thousand lanes reaches every processor and not only a few thread blocks' worth.
static int cycle_record_resident(const CycleRecord *record, CycleCompiledLaunch program, EngineError *error)
{
    const unsigned long long share = (program.count + record->processors - 1ull) / record->processors;
    const unsigned long long warps = ((share + 31ull) / 32ull) * 32ull;
    // at most record->threads, itself at most CYCLE_BLOCK
    const unsigned int threads = (unsigned int)((warps < record->threads) ? warps : record->threads);
    const unsigned long long needed = (program.count + threads - 1ull) / threads;
    // the device's thread blocks at once are a small count, far under 2^31
    const unsigned int blocks = (unsigned int)((needed < record->resident) ? needed : record->resident);
    const unsigned long long register_bytes = threads * record->thread_bytes;
    EngineProgramBlock *const block = record->block;
    const unsigned long long ttl =
        1000ull * cycle_environment_microseconds("CYCLE_RECORD_TTL", CYCLE_PROGRAM_TTL_MICROSECONDS);
    const unsigned long long wdt = 1000ull * CYCLE_PROGRAM_WDT_MICROSECONDS;
    const EngineSignum signature = block->signature;
    const unsigned long long generation = block->generation + 1ull;
    memset(block, 0, sizeof(EngineProgramBlock));
    block->signature = signature;
    block->generation = generation;
    block->command = ENGINE_PROGRAM_RUN;
    block->grant_registers = record->registers;
    block->grant_threads = (unsigned long long)blocks * threads;
    block->grant_bytes = record->local_bytes * block->grant_threads;
    // the kernel's own shared memory, and its threads' registers at this launch's threads
    block->grant_shared = (record->shared_bytes - record->register_bytes) + register_bytes;
    block->state = ENGINE_PROGRAM_PLACED;
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
    int ok = CYCLE_STATUS_CHECK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                                device_block, error) &&
             CYCLE_STATUS_CHECK(cudaMemset(record->hot, 0, sizeof(CycleHot)), record->hot, error);
    int running = ok;
    while (running != 0)
    {
        ok = CYCLE_STATUS_CHECK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost),
                                device_block, error) &&
             CYCLE_CHECK(block->checksum == cycle_block_seal(block), block, error, ENGINE_ERROR_LOGIC);
        if (ok == 0)
        {
            break;
        }
        block->launches += 1ull;
        block->owner = block->launches;
        block->state = ENGINE_PROGRAM_RUNNING;
        program.launch_number = block->launches;
        ok = CYCLE_STATUS_CHECK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                                device_block, error);
        // a launch's start and its thread blocks gone begin at 0, and the next lane runs on from the last launch's
        ok = ok && CYCLE_STATUS_CHECK(cudaMemset(&record->hot->launch_start, 0, 2u * sizeof(unsigned long long)),
                                      record->hot, error);
        void *arguments[1] = {&program};
        // a library's kernel handle is what the runtime launches in place of a kernel's address
        ok = ok && CYCLE_STATUS_CHECK(cudaLaunchKernel((const void *)record->kernel, dim3(blocks), dim3(threads),
                                                       arguments, (size_t)register_bytes, 0),
                                      program.out, error);
        ok = ok && CYCLE_STATUS_CHECK(cudaDeviceSynchronize(), program.out, error);
        unsigned int error_count = 0u;
        ok = ok &&
             CYCLE_STATUS_CHECK(
                 cudaMemcpy(&error_count, record->device_error, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                 record->device_error, error) &&
             CYCLE_STATUS_CHECK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost),
                                device_block, error);
        const unsigned long long state = block->state;
        ok = ok && CYCLE_CHECK((state == ENGINE_PROGRAM_YIELDED) || (state == ENGINE_PROGRAM_DONE), block, error,
                               ENGINE_ERROR_LOGIC);
        block->error = error_count;
        block->runtime += block->exectime;
        if (ok == 0)
        {
            block->state = ENGINE_PROGRAM_FAULT;
            // an engine module and a site are small non-negative counts, which fit in a 64-bit word
            block->error_module = (unsigned long long)error->module;
            block->error_site = (unsigned long long)error->site;
        }
        block->checksum = cycle_block_seal(block);
        // the sealed block goes back to the device, where the next launch finds it; a fault is left sealed on the
        // host's copy whether or not the device can still take it
        const cudaError_t sent = cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice);
        ok = ok && CYCLE_STATUS_CHECK(sent, device_block, error);
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
    int ok = (milliseconds == NULL) || (CYCLE_STATUS_CHECK(cudaEventCreate(&began), &began, error) &&
                                        CYCLE_STATUS_CHECK(cudaEventCreate(&ended), &ended, error) &&
                                        CYCLE_STATUS_CHECK(cudaEventRecord(began, 0), began, error));
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
        program.error = launch.error;
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
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MAX, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if (ok != 0)
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MAX, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    // the launch's own error is read and reset whichever way it launched
    const cudaError_t launched = cudaGetLastError();
    ok = ok && CYCLE_STATUS_CHECK(launched, launch.out, error);
    ok = ok && ((milliseconds == NULL) || CYCLE_STATUS_CHECK(cudaEventRecord(ended, 0), ended, error));
    ok = ok && CYCLE_STATUS_CHECK(cudaDeviceSynchronize(), launch.out, error);
    ok = ok && ((milliseconds == NULL) ||
                CYCLE_STATUS_CHECK(cudaEventElapsedTime(milliseconds, began, ended), milliseconds, error));
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
// into records of its own, and both runs' records and errors must be the same word for word. The compiled run's
// errors are put back for the run to read
static int cycle_record_check(const CycleRecord *record, CycleRecordLaunch launch, unsigned int blocks,
                              float compiled_milliseconds, int report, EngineError *error)
{
    const size_t words = (size_t)launch.count * record->out_limbs;
    std::vector<unsigned int> compiled_records(words);
    std::vector<unsigned int> interpreted_records(words);
    unsigned int compiled_error = 0u;
    unsigned int interpreted_error = 0u;
    unsigned int *interpreted = NULL;
    float interpreted_milliseconds = 0.0f;
    int ok =
        CYCLE_STATUS_CHECK(
            cudaMemcpy(&compiled_error, record->device_error, sizeof(unsigned int), cudaMemcpyDeviceToHost),
            record->device_error, error) &&
        CYCLE_STATUS_CHECK(
            cudaMemcpy(compiled_records.data(), launch.out, words * sizeof(unsigned int), cudaMemcpyDeviceToHost),
            launch.out, error) &&
        CYCLE_STATUS_CHECK(cudaMalloc((void **)&interpreted, words * sizeof(unsigned int)), &interpreted, error) &&
        CYCLE_STATUS_CHECK(cudaMemset(record->device_error, 0, sizeof(unsigned int)), record->device_error, error);
    launch.out = interpreted;
    ok = ok && cycle_record_launch(record, launch, blocks, 0, (report != 0) ? &interpreted_milliseconds : NULL, error);
    ok = ok &&
         CYCLE_STATUS_CHECK(
             cudaMemcpy(&interpreted_error, record->device_error, sizeof(unsigned int), cudaMemcpyDeviceToHost),
             record->device_error, error) &&
         CYCLE_STATUS_CHECK(
             cudaMemcpy(interpreted_records.data(), interpreted, words * sizeof(unsigned int), cudaMemcpyDeviceToHost),
             interpreted, error) &&
         CYCLE_STATUS_CHECK(
             cudaMemcpy(record->device_error, &compiled_error, sizeof(unsigned int), cudaMemcpyHostToDevice),
             record->device_error, error);
    cudaFree(interpreted);
    size_t differs = words;
    for (size_t at = 0u; (ok != 0) && (differs == words) && (at < words); at += 1u)
    {
        differs = (compiled_records[at] != interpreted_records[at]) ? at : words;
    }
    const int same = (differs == words) && (compiled_error == interpreted_error);
    if ((ok != 0) && (report != 0))
    {
        fprintf(stderr, "  cycle: %llu lanes, compiled %.3f ms, interpreted %.3f ms, errored %u and %u, %s\n",
                launch.count, compiled_milliseconds, interpreted_milliseconds, compiled_error, interpreted_error,
                (same != 0) ? "the same records" : "records differ");
    }
    if ((ok != 0) && (same == 0) && (differs != words))
    {
        fprintf(stderr,
                "  cycle: the compiled record program differs from the interpreter at lane %zu, word %zu: %08x "
                "against %08x\n",
                differs / record->out_limbs, differs % record->out_limbs, compiled_records[differs],
                interpreted_records[differs]);
    }
    return ok && CYCLE_CHECK(same != 0, record->device_error, error, ENGINE_ERROR_LOGIC);
}

extern "C" long cycle_record_run(const CycleRecordRunRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_ERROR;
    }
    EngineError *const error = request->error;
    if (!CYCLE_CHECK((request->record != NULL) && (request->device_out != NULL) && (request->count != 0ull), request,
                     error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    const CycleRecord *const record = request->record;
    CycleRecordLaunch launch;
    memset(&launch, 0, sizeof(launch));
    for (unsigned int member = 0u; member < record->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        if (!CYCLE_CHECK((request->device_in[member] != NULL) && (request->bodies[member] != 0ull) &&
                             ((request->device_index != NULL) || (request->count <= request->bodies[member]) ||
                              (request->bodies[member] == 1ull)),
                         &request->device_in[member], error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_ERROR;
        }
        launch.in[member] = request->device_in[member];
        launch.bodies[member] = request->bodies[member];
        launch.in_limbs[member] = record->in_limbs[member];
    }
    launch.steps = record->device_steps;
    launch.index = request->device_index;
    launch.tables = record->device_tables;
    launch.out = request->device_out;
    launch.error = record->device_error;
    launch.count = request->count;
    launch.step_count = record->steps;
    launch.members = record->members;
    launch.out_limbs = record->out_limbs;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MAX) ? needed : CYCLE_RECORD_BLOCKS_MAX);
    const int compiled = (record->compiled != 0u) ? 1 : 0;
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int check = (compiled != 0) && (cycle_environment_set("CYCLE_RECORD_CHECK") != 0);
    unsigned int error_count = 1u;
    size_t stack = 0u;
    float milliseconds = 0.0f;
    int ok =
        CYCLE_STATUS_CHECK(cudaDeviceGetLimit(&stack, cudaLimitStackSize), &stack, error) &&
        CYCLE_STATUS_CHECK(cudaMemset(record->device_error, 0, sizeof(unsigned int)), record->device_error, error);
    ok = ok && cycle_record_launch(record, launch, blocks, compiled, (report != 0) ? &milliseconds : NULL, error);
    ok = ok && ((check == 0) || cycle_record_check(record, launch, blocks, milliseconds, report, error));
    if ((ok != 0) && (report != 0) && (check == 0))
    {
        fprintf(stderr, "  cycle: %llu lanes %s in %.3f ms\n", request->count,
                (compiled != 0) ? "compiled" : "interpreted", milliseconds);
    }
    if ((ok != 0) && (report != 0) && (compiled != 0))
    {
        fprintf(stderr, "  cycle: the program ran %llu launches, %llu check-ins, %.3f ms on the device, %llu threads\n",
                record->block->launches, record->block->checkin, (double)record->block->runtime / 1e6,
                record->block->grant_threads);
    }
    // the frame's reservation is given back whether or not the sweep held
    const int returned = cycle_stack_return(stack, request->device_out, error);
    ok =
        ok && returned &&
        CYCLE_STATUS_CHECK(cudaMemcpy(&error_count, record->device_error, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                           record->device_error, error) &&
        CYCLE_CHECK(error_count == 0u, record->device_error, error, ENGINE_ERROR_REQUEST);
    return (ok != 0) ? (long)request->count : CYCLE_ERROR;
}

// 1 where a record's `bits` bits at `offset` are not all zero
__device__ static int cycle_latch_valid(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned int set_bits = 0u;
    for (unsigned int bit = offset; bit < (offset + bits);)
    {
        const unsigned int shift = bit % 32u;
        const unsigned int left = offset + bits - bit;
        const unsigned int taken = (left < (32u - shift)) ? left : (32u - shift);
        const unsigned int mask = (taken == 32u) ? 0xFFFFFFFFu : (((1u << taken) - 1u) << shift);
        set_bits |= record[bit / 32u] & mask;
        bit += taken;
    }
    return (set_bits != 0u) ? 1 : 0;
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
        found = (cycle_latch_valid(&records[lane * out_limbs], offset, bits) != 0) ? lane : CYCLE_LATCH_NONE;
    }
    for (unsigned int range = 16u; range > 0u; range /= 2u)
    {
        const unsigned long long other = __shfl_down_sync(0xFFFFFFFFu, found, range);
        found = (other < found) ? other : found;
    }
    if (((threadIdx.x % 32u) == 0u) && (found != CYCLE_LATCH_NONE))
    {
        atomicMin(first, found);
    }
}

extern "C" long cycle_record_latch(const CycleRecordLatchRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_ERROR;
    }
    EngineError *const error = request->error;
    if (!CYCLE_CHECK((request->records != NULL) && (request->first != NULL) && (request->count != 0ull) &&
                         (request->out_limbs != 0u) && (request->bits != 0u) &&
                         (((unsigned long long)request->offset + request->bits) <=
                          (32ull * (unsigned long long)request->out_limbs)),
                     request, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    unsigned long long *device_first = NULL;
    unsigned long long first = CYCLE_LATCH_NONE;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MAX) ? needed : CYCLE_RECORD_BLOCKS_MAX);
    int ok = CYCLE_STATUS_CHECK(cudaMalloc((void **)&device_first, sizeof(unsigned long long)), &device_first, error) &&
             CYCLE_STATUS_CHECK(cudaMemcpy(device_first, &first, sizeof(unsigned long long), cudaMemcpyHostToDevice),
                                device_first, error);
    if (ok != 0)
    {
        cycle_latch_kernel<<<blocks, CYCLE_BLOCK>>>(request->records, request->count, request->out_limbs,
                                                    request->offset, request->bits, device_first);
    }
    ok = ok && CYCLE_STATUS_CHECK(cudaGetLastError(), device_first, error) &&
         CYCLE_STATUS_CHECK(cudaDeviceSynchronize(), device_first, error) &&
         CYCLE_STATUS_CHECK(cudaMemcpy(&first, device_first, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                            device_first, error);
    cudaFree(device_first);
    if (ok == 0)
    {
        return CYCLE_ERROR;
    }
    *request->first = first;
    return (long)request->count;
}
