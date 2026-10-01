// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_engine_ledger.cu: the engine's threads, ledger and buffers
#include "chaitin_omega_internal.h"

// the engine's ledger: one line a finished job, "engine" first and "end" last. A line cut anywhere is not a job
void omega_engine_ledger_read(const char *path, std::vector<OmegaEngineJob> &jobs)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
    {
        return;
    }
    char line[1024];
    while (fgets(line, (int)sizeof(line), file) != NULL)
    {
        OmegaEngineJob job;
        omega_results_open(&job.results);
        unsigned long long fate[6];
        unsigned long long contradictions = 0ull;
        unsigned long long maximum[4];
        int read = 0;
        const size_t written = strlen(line);
        if ((written == 0u) || (line[written - 1u] != '\n'))
        {
            continue;
        }
        if ((sscanf(line, "engine %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu end%n",
                    &job.length, &job.from, &job.count, &fate[0], &fate[1], &fate[2], &fate[3], &fate[4], &fate[5],
                    &contradictions, &maximum[0], &maximum[1], &maximum[2], &maximum[3], &read) != 14) ||
            ((size_t)read != (written - 1u)) || (job.length > OMEGA_LENGTH_MAX) ||
            ((fate[0] + fate[1] + fate[2] + fate[3] + fate[4] + fate[5]) != job.count))
        {
            continue;
        }
        for (unsigned int one = 0u; one < 6u; one += 1u)
        {
            job.results.fate[one][job.length] = fate[one];
        }
        job.results.contradictions = contradictions;
        job.results.max_steps[job.length] = maximum[0];
        job.results.steps_champion[job.length] = maximum[1];
        job.results.max_bits[job.length] = maximum[2];
        job.results.bits_champion[job.length] = maximum[3];
        job.settled = job.count;
        jobs.push_back(job);
    }
    fclose(file);
}

int omega_engine_ledger_write(const char *path, const OmegaEngineJob *job)
{
    int ended = 1;
    FILE *before = fopen(path, "rb");
    if (before != NULL)
    {
        if (fseek(before, -1L, SEEK_END) == 0)
        {
            ended = (fgetc(before) == '\n');
        }
        fclose(before);
    }
    FILE *file = fopen(path, "a");
    if (file == NULL)
    {
        return 0;
    }
    if (ended == 0)
    {
        fputc('\n', file);
    }
    const unsigned int length = job->length;
    const OmegaResults *const results = &job->results;
    fprintf(file, "engine %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu end\n", length, job->from,
            job->count, results->fate[0][length], results->fate[1][length], results->fate[2][length],
            results->fate[3][length], results->fate[4][length], results->fate[5][length], results->contradictions,
            results->max_steps[length], results->steps_champion[length], results->max_bits[length],
            results->bits_champion[length]);
    const int flushed = (fflush(file) == 0);
    return (fclose(file) == 0) && flushed;
}

void omega_engine_settle(const OmegaCounts *counts, OmegaEngineJob *job, const OmegaSettled *settled,
                         std::vector<int> &scratch, std::vector<OmegaSettled> *crossed)
{
    OmegaResults *const results = &job->results;
    if (settled->fate == OMEGA_HALTS)
    {
        results->fate[OMEGA_HALTS][settled->length] += 1ull;
        omega_champion(&results->max_steps[settled->length], &results->steps_champion[settled->length], settled->steps,
                       settled->index);
        omega_champion(&results->max_bits[settled->length], &results->bits_champion[settled->length], settled->bits,
                       settled->index);
    }
    else
    {
        // the type certificate and the contradiction check, read off the program
        omega_settle(counts, settled->length, settled->index, (OmegaFate)settled->fate, 0u, scratch, results);
    }
    job->settled += 1ull;
    if (settled->length <= OMEGA_ENGINE_CROSS_MAX)
    {
        crossed->push_back(*settled);
    }
}

int omega_buffer_reserve(OmegaBuffer *buffer, size_t bytes, int keep)
{
    if (bytes <= buffer->bytes)
    {
        return 1;
    }
    void *grown = NULL;
    if (cudaMalloc(&grown, bytes) != cudaSuccess)
    {
        (void)cudaGetLastError();
        return 0;
    }
    if ((keep != 0) && (buffer->bytes != 0u) &&
        (cudaMemcpy(grown, buffer->data, buffer->bytes, cudaMemcpyDeviceToDevice) != cudaSuccess))
    {
        (void)cudaFree(grown);
        return -1;
    }
    (void)cudaFree(buffer->data);
    buffer->data = grown;
    buffer->bytes = bytes;
    return 1;
}

void omega_buffer_release(OmegaBuffer *buffer)
{
    (void)cudaFree(buffer->data);
    buffer->data = NULL;
    buffer->bytes = 0u;
}

void omega_buffer_swap(OmegaBuffer *one, OmegaBuffer *other)
{
    const OmegaBuffer temporary = *one;
    *one = *other;
    *other = temporary;
}

// the exclusive prefix sum of `count` values, and their total; 0 where the device errored
int omega_buffer_scan(SimResults *results, OmegaBuffer *scratch, const unsigned long long *values,
                      unsigned long long *sums, unsigned long long count, unsigned long long *total)
{
    size_t bytes = 0u;
    int ok = sim_status_check(results, cub::DeviceScan::ExclusiveSum(NULL, bytes, values, sums, (long long)count),
                              "engine: scan size");
    ok = ok && (omega_buffer_reserve(scratch, bytes, 0) == 1);
    ok = ok &&
         sim_status_check(results, cub::DeviceScan::ExclusiveSum(scratch->data, bytes, values, sums, (long long)count),
                          "engine: scan");
    unsigned long long last[2] = {0ull, 0ull};
    ok = ok &&
         sim_status_check(results, cudaMemcpy(&last[0], &sums[count - 1ull], sizeof(last[0]), cudaMemcpyDeviceToHost),
                          "engine: scan read") &&
         sim_status_check(results, cudaMemcpy(&last[1], &values[count - 1ull], sizeof(last[1]), cudaMemcpyDeviceToHost),
                          "engine: scan read");
    *total = last[0] + last[1];
    return ok;
}

// a grid for a launch over `count` items, each thread taking every stride-th
unsigned int omega_pool_grid(unsigned long long count)
{
    const unsigned long long blocks = (count + OMEGA_POOL_BLOCK - 1ull) / OMEGA_POOL_BLOCK;
    const unsigned long long grid = (blocks == 0ull) ? 1ull : blocks;
    // at most OMEGA_POOL_GRID_MAX, which an unsigned int holds
    return (unsigned int)((grid < OMEGA_POOL_GRID_MAX) ? grid : OMEGA_POOL_GRID_MAX);
}

// A job's terms unranked on the device after the pool's live terms. 1 where admitted, 2 where the device cannot
// hold them beside the live terms. The job waits for the pool to drain, and 0 where the device errored.
int omega_pool_insert_job(SimResults *results, OmegaBuffer *buffers, const OmegaEngineJob *job, unsigned int job_at,
                          OmegaPoolExtent *extent)
{
    const unsigned long long count = job->count;
    const size_t word = sizeof(unsigned long long);
    if ((omega_buffer_reserve(&buffers[OMEGA_BUFFER_OUT_SIZES], count * word, 0) != 1) ||
        (omega_buffer_reserve(&buffers[OMEGA_BUFFER_OUT_BASES], count * word, 0) != 1))
    {
        return 2;
    }
    unsigned long long *const sizes = OMEGA_BUFFER(buffers, OMEGA_BUFFER_OUT_SIZES, unsigned long long);
    unsigned long long *const bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_OUT_BASES, unsigned long long);
    omega_pool_insert_sizes<<<omega_pool_grid(count), OMEGA_POOL_BLOCK>>>(
        OMEGA_BUFFER(buffers, OMEGA_BUFFER_COUNTS, unsigned long long), job->length, job->from, count, sizes);
    unsigned long long total = 0ull;
    if ((sim_status_check(results, cudaGetLastError(), "engine: admission sizes") == 0) ||
        (omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], sizes, bases, count, &total) == 0))
    {
        return 0;
    }
    const OmegaBufferName grown[4] = {OMEGA_BUFFER_TERMS, OMEGA_BUFFER_TOKENS, OMEGA_BUFFER_STORED, OMEGA_BUFFER_ENDS};
    const size_t bytes[4] = {
        (size_t)(extent->live + count) * sizeof(OmegaTerm), (size_t)(extent->tokens + total) * sizeof(OmegaToken),
        (size_t)(extent->stored + total) * sizeof(OmegaToken), (size_t)(extent->ends + total + count) * word};
    for (unsigned int buffer = 0u; buffer < 4u; buffer += 1u)
    {
        const int reserved = omega_buffer_reserve(&buffers[grown[buffer]], bytes[buffer], 1);
        if (reserved == 0)
        {
            return 2;
        }
        if (reserved < 0)
        {
            sim_check(results, 0, "engine: a grown buffer carries the pool over");
            return 0;
        }
    }
    omega_pool_insert<<<omega_pool_grid(count), OMEGA_POOL_BLOCK>>>(
        OMEGA_BUFFER(buffers, OMEGA_BUFFER_COUNTS, unsigned long long), job->length, job_at, job->from, count, bases,
        extent->live, extent->tokens, extent->stored, extent->ends,
        OMEGA_BUFFER(buffers, OMEGA_BUFFER_TERMS, OmegaTerm), OMEGA_BUFFER(buffers, OMEGA_BUFFER_TOKENS, OmegaToken),
        OMEGA_BUFFER(buffers, OMEGA_BUFFER_STORED, OmegaToken),
        OMEGA_BUFFER(buffers, OMEGA_BUFFER_ENDS, unsigned long long));
    if (sim_status_check(results, cudaGetLastError(), "engine: admission") == 0)
    {
        return 0;
    }
    extent->live += count;
    extent->tokens += total;
    extent->stored += total;
    extent->ends += total + count;
    return 1;
}

// a term's bytes across a round's buffers: itself twice, its settled record and its twelve sizes and bases
#define OMEGA_ENGINE_TERM_BYTES ((2u * sizeof(OmegaTerm)) + sizeof(OmegaSettled) + (12u * sizeof(unsigned long long)))

// a token's bytes across a round's buffers: its token, its watcher's copy and a spine end, each twice (16 each), its
// two frames (2), its record and its plan (8 each at most), its index pair (8), its reduct and the reduct's spine
// end (8 each): 90, taken as 96
#define OMEGA_ENGINE_TOKEN_BYTES 96ull

// The bytes a run on the engine declares to tessera: its first round's admitted terms, each at the most tokens its
// length holds (a token takes 2 bits at least), and the counts it copies to the device.
unsigned long long omega_engine_declared(const OmegaCounts *counts)
{
    unsigned long long terms = 0ull;
    unsigned long long tokens = 0ull;
    for (unsigned int length = 2u; (length <= counts->length) && (terms < OMEGA_ENGINE_REFILL); length += 1u)
    {
        const unsigned long long total = omega_count(counts, length, 0u);
        for (unsigned long long from = 0ull; (from < total) && (terms < OMEGA_ENGINE_REFILL); from += OMEGA_ENGINE_JOB)
        {
            const unsigned long long count = ((total - from) < OMEGA_ENGINE_JOB) ? (total - from) : OMEGA_ENGINE_JOB;
            terms += count;
            tokens += count * (length / 2u);
        }
    }
    return (terms * OMEGA_ENGINE_TERM_BYTES) + (tokens * OMEGA_ENGINE_TOKEN_BYTES) + sizeof(counts->count);
}
