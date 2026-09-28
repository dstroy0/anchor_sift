// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_record_kernel.cu: the record kernel, the block seal and the shared lanes
#include "cycle_record_internal.h"

// the block's CRC-64 over every word before its checksum
unsigned long long cycle_block_seal(const EngineProgramBlock *block)
{
    // the block is 64-bit words throughout, asserted above. It reads as them
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

// the compiled program's registers laid out in shared memory: a thread's places a word each and the file's signs a byte
// each, for as many threads as one thread block's shared memory holds beside the kernel's own, a whole number of warps
// up to CYCLE_BLOCK where a warp fits. A program written as PTX that calls nothing holds its registers itself and takes
// no places, and runs CYCLE_BLOCK threads a thread block. The kernel is let take that much and prefers shared memory to
// L1, and the device is asked how many such thread blocks it holds at once. 0 where not one thread's registers fit or
// the runtime errors on any of it, which leaves the program on the interpreter
static int cycle_record_share(CycleRecord *record, size_t kernel_bytes)
{
    int device = 0;
    int maximum = 0;
    int processors = 0;
    if ((cudaGetDevice(&device) != cudaSuccess) ||
        (cudaDeviceGetAttribute(&maximum, cudaDevAttrMaxSharedMemoryPerBlockOptin, device) != cudaSuccess) ||
        (cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device) != cudaSuccess))
    {
        return 0;
    }
    const unsigned long long thread_bytes =
        (record->places != 0u) ? ((4ull * record->places) + record->file_limbs) : 0ull;
    // a device's shared memory a thread block is never negative
    const unsigned long long capacity =
        ((unsigned long long)maximum > kernel_bytes) ? ((unsigned long long)maximum - kernel_bytes) : 0ull;
    const unsigned long long fit = (thread_bytes != 0ull) ? (capacity / thread_bytes) : CYCLE_BLOCK;
    const unsigned long long block_threads = (fit < CYCLE_BLOCK) ? fit : CYCLE_BLOCK;
    const unsigned long long threads =
        (block_threads >= 32ull) ? (block_threads - (block_threads % 32ull)) : block_threads;
    if (threads == 0ull)
    {
        return 0;
    }
    // at most CYCLE_BLOCK threads, and at most the device's shared memory a thread block, both far under 2^31
    record->threads = (unsigned int)threads;
    record->thread_bytes = thread_bytes;
    // a count of processors is positive where the runtime gave it
    record->processors = (unsigned long long)processors;
    record->register_bytes = threads * thread_bytes;
    record->shared_bytes = record->register_bytes + kernel_bytes;
    int blocks = 0;
    const int ok =
        (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributeMaxDynamicSharedMemorySize,
                              (int)record->register_bytes) == cudaSuccess) &&
        (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributePreferredSharedMemoryCarveout,
                              (int)cudaSharedmemCarveoutMaxShared) == cudaSuccess) &&
        (cudaOccupancyMaxActiveBlocksPerMultiprocessor(&blocks, (const void *)record->kernel, (int)record->threads,
                                                       (size_t)record->register_bytes) == cudaSuccess) &&
        (blocks > 0);
    // a count of thread blocks and of processors are positive where the runtime gave them
    record->resident = (ok != 0) ? ((unsigned long long)blocks * (unsigned long long)processors) : 0ull;
    return ok;
}

extern "C" long cycle_record_load(const EngineRecordLayout *layout, CycleRecord **record_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_ERROR;
    }
    int asked = CYCLE_CHECK((layout != NULL) && (record_out != NULL), layout, error, ENGINE_ERROR_REQUEST) &&
                CYCLE_CHECK((layout->step_table != NULL) && (layout->steps != 0u) &&
                                (layout->file_limbs <= ENGINE_RECORD_LIMBS_MAX) && (layout->out_limbs != 0u) &&
                                (layout->members != 0u) && (layout->members <= ENGINE_RECORD_MEMBERS_MAX),
                            layout, error, ENGINE_ERROR_REQUEST);
    for (unsigned int member = 0u; (asked != 0) && (member < layout->members); member += 1u)
    {
        asked = CYCLE_CHECK(layout->in_limbs[member] != 0u, &layout->in_limbs[member], error, ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return CYCLE_ERROR;
    }
    *record_out = NULL;
    CycleRecord *const record = (CycleRecord *)calloc(1u, sizeof(CycleRecord));
    int ok = CYCLE_CHECK(record != NULL, record_out, error, ENGINE_ERROR_RESOURCE);
    ok = ok && CYCLE_STATUS_CHECK(
                   cudaMalloc((void **)&record->device_steps, (size_t)layout->steps * sizeof(DeviceRecordStep)),
                   &record->device_steps, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaMalloc((void **)&record->device_error, sizeof(unsigned int)),
                                  &record->device_error, error);
    ok = ok && CYCLE_STATUS_CHECK(cudaMemcpy(record->device_steps, layout->step_table,
                                             (size_t)layout->steps * sizeof(DeviceRecordStep), cudaMemcpyHostToDevice),
                                  record->device_steps, error);
    if ((ok != 0) && (layout->table_word_count != 0ull))
    {
        ok = CYCLE_STATUS_CHECK(
                 cudaMalloc((void **)&record->device_tables, (size_t)layout->table_word_count * sizeof(unsigned int)),
                 &record->device_tables, error) &&
             CYCLE_STATUS_CHECK(cudaMemcpy(record->device_tables, layout->table_values,
                                           (size_t)layout->table_word_count * sizeof(unsigned int),
                                           cudaMemcpyHostToDevice),
                                record->device_tables, error);
    }
    // the block lies in device memory, where the program's thread blocks check in without leaving the device; the host
    // keeps its own copy, read back once each launch has ended
    record->block = (EngineProgramBlock *)calloc(1u, sizeof(EngineProgramBlock));
    ok = ok && CYCLE_CHECK(record->block != NULL, &record->block, error, ENGINE_ERROR_RESOURCE) &&
         CYCLE_STATUS_CHECK(cudaMalloc((void **)&record->device_block, sizeof(EngineProgramBlock)),
                            &record->device_block, error) &&
         CYCLE_STATUS_CHECK(cudaMalloc((void **)&record->hot, sizeof(CycleHot)), &record->hot, error);
    if (ok == 0)
    {
        cycle_record_release(record);
        return CYCLE_ERROR;
    }
    // the program is its steps, its sizes and its tables, and its signum is taken over all three in that order
    const unsigned int extent[6] = {layout->members,     layout->in_limbs[0], layout->in_limbs[1],
                                    layout->in_limbs[2], layout->out_bits,    layout->file_limbs};
    std::vector<unsigned char> program((size_t)layout->steps * sizeof(DeviceRecordStep));
    memcpy(program.data(), layout->step_table, program.size());
    // a word's bytes are read as bytes, as the signum takes them
    const unsigned char *const extent_bytes = (const unsigned char *)extent;
    program.insert(program.end(), extent_bytes, extent_bytes + sizeof(extent));
    if (layout->table_word_count != 0ull)
    {
        // a table's words are read as bytes, as the signum takes them
        const unsigned char *const table_bytes = (const unsigned char *)layout->table_values;
        program.insert(program.end(), table_bytes,
                       table_bytes + ((size_t)layout->table_word_count * sizeof(unsigned int)));
    }
    const ObsignatioSignumRequest signum = {
        program.data(),      program.size(), NULL, OBSIGNATIO_MODE_HASH, record->block->signature.bytes,
        ENGINE_SIGNUM_BYTES, error};
    if (obsignatio_signum(&signum) == OBSIGNATIO_ERROR)
    {
        cycle_record_release(record);
        return CYCLE_ERROR;
    }
    record->block->span = layout->file_limbs;
    record->block->state = ENGINE_PROGRAM_PLACED;
    record->block->checksum = cycle_block_seal(record->block);
    if (!CYCLE_STATUS_CHECK(
            cudaMemcpy(record->device_block, record->block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
            record->device_block, error))
    {
        cycle_record_release(record);
        return CYCLE_ERROR;
    }
    record->steps = layout->steps;
    record->members = layout->members;
    record->file_limbs = layout->file_limbs;
    memcpy(record->in_limbs, layout->in_limbs, sizeof(record->in_limbs));
    record->out_limbs = layout->out_limbs;
    record->table_words = layout->table_word_count;
    for (unsigned int step = 0u; step < layout->steps; step += 1u)
    {
        const unsigned int operation = layout->step_table[step].operation;
        record->divides |= ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER) ||
                            (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
                               ? 1u
                               : 0u;
    }
    if ((cycle_environment_set("CYCLE_RECORD_INTERPRET") == 0) && (cycle_record_compile(layout, record) == 0))
    {
        // every call above held, and an error the runtime still holds is the attempt's own: the interpreter runs in
        // its place, and the error is dropped before a run reads the runtime's last error as its own
        cudaGetLastError();
    }
    // a host program holds no device grant: it runs as one thread of one thread block
    const int host = (record->compiled != 0u) && (record->host_program != NULL);
    record->threads = (host != 0) ? 1u : record->threads;
    cudaFuncAttributes attributes;
    const int attributed = (record->compiled != 0u) && (host == 0) &&
                           (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) == cudaSuccess);
    if (attributed != 0)
    {
        // a register count and a frame's bytes are never negative
        record->registers = (unsigned long long)attributes.numRegs;
        record->local_bytes = (unsigned long long)attributes.localSizeBytes;
    }
    // a compiled program whose registers shared memory cannot hold runs on the interpreter
    record->compiled =
        ((host != 0) || ((attributed != 0) && cycle_record_share(record, attributes.sharedSizeBytes))) ? 1u : 0u;
    if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (host != 0))
    {
        fprintf(stderr, "  cycle: the program holds %u places a thread, and runs on the host as one thread\n",
                record->places);
    }
    else if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (record->compiled != 0u))
    {
        fprintf(stderr,
                "  cycle: the program holds %llu registers a thread, a %llu-byte local frame and %u places a "
                "thread in shared memory: %u threads a thread block in %llu bytes, %llu thread blocks at once\n",
                record->registers, record->local_bytes, record->places, record->threads, record->shared_bytes,
                record->resident);
    }
    else if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (attributed != 0))
    {
        fprintf(stderr,
                "  cycle: a program of %u places a thread runs on the interpreter (shared memory does not "
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
    cudaFree(record->device_error);
    cudaFree(record->device_tables);
    cudaFree(record->hot);
    cudaFree(record->device_block);
    // the record gives back its hold on the program it loaded, compiled or left on the interpreter after
    cycle_program_release(record->kernel);
    cycle_host_program_release(record->host_program);
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
