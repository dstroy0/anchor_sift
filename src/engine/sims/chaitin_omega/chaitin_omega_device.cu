// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_device.cu: the kernel, the ledger and the device run
#include "chaitin_omega_internal.h"

// the bytes of one thread's buffers, each rounded to 16
static __host__ __device__ size_t omega_buffers_bytes(unsigned int tokens, unsigned int token_capacity)
{
    const size_t shorts = (((size_t)token_capacity * 2u) + 15u) & ~(size_t)15u;
    const size_t token_bytes = (((size_t)tokens * 2u) + 15u) & ~(size_t)15u;
    const size_t ends = ((((size_t)token_capacity + 1u) * 2u) + 15u) & ~(size_t)15u;
    const size_t stored_ends = ((((size_t)tokens + 1u) * 2u) + 15u) & ~(size_t)15u;
    const size_t stack = (((size_t)token_capacity + 1u) + 15u) & ~(size_t)15u;
    return (2u * shorts) + token_bytes + ends + stored_ends + stack;
}

static __global__ void omega_kernel(OmegaBatch *batch, const unsigned long long *__restrict__ counts,
                                    unsigned int length, unsigned long long from, unsigned long long total,
                                    unsigned int steps, unsigned int tokens, int steps_short, int tokens_short,
                                    unsigned int buffer, unsigned char *scratch, unsigned long long *hand)
{
    const size_t thread = ((size_t)blockIdx.x * blockDim.x) + threadIdx.x;
    unsigned char *base = scratch + (thread * omega_buffers_bytes(tokens, buffer));
    const size_t shorts = (((size_t)buffer * 2u) + 15u) & ~(size_t)15u;
    OmegaBuffers buffers;
    buffers.term = (short *)base;
    buffers.next = (short *)(base + shorts);
    buffers.stored = (short *)(base + (2u * shorts));
    base += (2u * shorts) + ((((size_t)tokens * 2u) + 15u) & ~(size_t)15u);
    buffers.ends = (unsigned short *)base;
    base += ((((size_t)buffer + 1u) * 2u) + 15u) & ~(size_t)15u;
    buffers.stored_ends = (unsigned short *)base;
    base += ((((size_t)tokens + 1u) * 2u) + 15u) & ~(size_t)15u;
    buffers.stack = base;
    unsigned long long halts = 0ull;
    unsigned long long steps_key = 0ull;
    unsigned long long bits_key = 0ull;
    for (;;)
    {
        const unsigned long long offset = atomicAdd(&batch->next, 1ull);
        if (offset >= total)
        {
            break;
        }
        short *term = buffers.term;
        short *next = buffers.next;
        unsigned int size = omega_device_unrank(counts, length, from + offset, term);
        unsigned int taken = 0u;
        unsigned int fate = omega_device_run(&buffers, &term, &next, &size, steps, tokens, buffer, &taken);
        if (fate == OMEGA_HALTS)
        {
            unsigned long long bits = 0ull;
            for (unsigned int at = 0u; at < size; at += 1u)
            {
                bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
            }
            if (bits <= 0xFFFFFFFFull)
            {
                const unsigned long long rank = 0xFFFFFFFFull - offset;
                halts += 1ull;
                steps_key = max(steps_key, ((unsigned long long)taken << 32u) | rank);
                bits_key = max(bits_key, (bits << 32u) | rank);
                continue;
            }
            fate = OMEGA_HOST_RUNS;
        }
        // a small budget reached is no fate: the host runs the term under the full ones
        fate = (((fate == OMEGA_OPEN) && (steps_short != 0)) || ((fate == OMEGA_GREW) && (tokens_short != 0)))
                   ? OMEGA_HOST_RUNS
                   : fate;
        hand[atomicAdd(&batch->handed, 1ull)] = (offset << 8u) | fate;
    }
    atomicAdd(&batch->halts, halts);
    atomicMax(&batch->steps_key, steps_key);
    atomicMax(&batch->bits_key, bits_key);
}

// a launch's handed back terms settled on the host: the fate each carries, or the host's own run
static void omega_hand_worker(const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              const unsigned long long *hand, unsigned long long handed, unsigned int worker,
                              unsigned int workers, OmegaResults *results)
{
    std::vector<int> term;
    std::vector<int> next;
    std::vector<int> stored;
    for (unsigned long long at = worker; at < handed; at += workers)
    {
        const unsigned long long index = from + (hand[at] >> 8u);
        OmegaFate fate = (OmegaFate)(hand[at] & 0xFFull);
        unsigned int taken = 0u;
        if ((hand[at] & 0xFFull) == OMEGA_HOST_RUNS)
        {
            term.clear();
            omega_unrank(counts, length, 0u, index, term);
            fate = omega_run(term, next, stored, counts->steps, counts->tokens, &taken);
        }
        omega_settle(counts, length, index, fate, taken, term, results);
    }
}

static void omega_hand_settle(const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              const std::vector<unsigned long long> &hand, unsigned int workers,
                              std::vector<OmegaResults> &tallies, OmegaResults *fates)
{
    const unsigned int helpers = (hand.size() < 64u) ? 1u : workers;
    std::vector<std::thread> threads;
    for (unsigned int worker = 0u; worker < helpers; worker += 1u)
    {
        omega_results_open(&tallies[worker]);
        threads.emplace_back(omega_hand_worker, counts, length, from, hand.data(), (unsigned long long)hand.size(),
                             worker, helpers, &tallies[worker]);
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }
    for (unsigned int worker = 0u; worker < helpers; worker += 1u)
    {
        omega_merge(fates, &tallies[worker]);
    }
}

// The run planned as jobs: each length's terms in rank order, cut every OMEGA_JOB_TERMS. The plan is the same
// on every run. A finished job's exact counts are one line of the ledger, written whole and flushed, and a run finds
// every job its ledger already holds under the same budgets and runs only the rest. A run stopped at any point
// resumes where it stopped, and reaching a longer L costs only the new lengths.
#define OMEGA_JOB_TERMS (1ull << 28u)

// the ledger's fields a line: steps, tokens, length, from, count, the six fates, the contradictions, and the two
// busy beavers with their champions
#define OMEGA_LEDGER_FIELDS 16

// every whole line of the ledger; a line cut short by a stop mid-write is not a job and is run again
static void omega_ledger_read(const char *path, std::vector<OmegaLedgerJob> &jobs)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
    {
        return;
    }
    char line[1024];
    while (fgets(line, (int)sizeof(line), file) != NULL)
    {
        OmegaLedgerJob job;
        omega_results_open(&job.results);
        unsigned long long fate[6];
        unsigned long long contradictions = 0ull;
        unsigned long long maximum[4];
        const size_t written = strlen(line);
        if ((written == 0u) || (line[written - 1u] != '\n'))
        {
            continue;
        }
        int read = 0;
        if (sscanf(line, "%u %u %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu%n", &job.steps,
                   &job.tokens, &job.length, &job.from, &job.count, &fate[0], &fate[1], &fate[2], &fate[3], &fate[4],
                   &fate[5], &contradictions, &maximum[0], &maximum[1], &maximum[2], &maximum[3],
                   &read) != OMEGA_LEDGER_FIELDS)
        {
            continue;
        }
        // the whole line and nothing after, and every term of the job given one fate
        if (((size_t)read != (written - 1u)) || (job.length > OMEGA_LENGTH_MAX) ||
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
        jobs.push_back(job);
    }
    fclose(file);
}

static int omega_ledger_write(const char *path, const OmegaCounts *counts, unsigned int length, unsigned long long from,
                              unsigned long long count, const OmegaResults *results)
{
    // a line cut short by a stop mid-write is ended first. This job's line starts a line of its own
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
    fprintf(file, "%u %u %u %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu\n", counts->steps,
            counts->tokens, length, from, count, results->fate[0][length], results->fate[1][length],
            results->fate[2][length], results->fate[3][length], results->fate[4][length], results->fate[5][length],
            results->contradictions, results->max_steps[length], results->steps_champion[length],
            results->max_bits[length], results->bits_champion[length]);
    const int written = (fflush(file) == 0);
    return (fclose(file) == 0) && written;
}

// every closed term through L bits run on the device as jobs, the host settling each launch's handed back terms
// while the device runs the next; launches are sized toward a quarter second of device time. `ledger` may be NULL.
int omega_device(SimResults *results, const OmegaCounts *counts, unsigned int workers, const char *ledger,
                 unsigned int *threads_used, unsigned long long *host_runs, unsigned long long *jobs_run,
                 unsigned long long *jobs_kept, OmegaResults *fates)
{
    omega_results_open(fates);
    std::vector<OmegaLedgerJob> done;
    if (ledger != NULL)
    {
        omega_ledger_read(ledger, done);
    }
    const unsigned int steps = (counts->steps < OMEGA_DEVICE_STEPS) ? counts->steps : OMEGA_DEVICE_STEPS;
    const unsigned int tokens = (counts->tokens < OMEGA_DEVICE_TOKENS) ? counts->tokens : OMEGA_DEVICE_TOKENS;
    const unsigned int token_capacity = 2u * tokens;
    cudaDeviceProp properties;
    int ok = sim_status_check(results, cudaGetDeviceProperties(&properties, 0), "device: properties");
    size_t free_bytes = 0u;
    size_t total_bytes = 0u;
    ok = ok && sim_status_check(results, cudaMemGetInfo(&free_bytes, &total_bytes), "device: memory");
    if (ok == 0)
    {
        return 0;
    }
    const size_t buffers_bytes = omega_buffers_bytes(tokens, token_capacity);
    size_t blocks = ((size_t)properties.multiProcessorCount * OMEGA_THREADS_PER_SM) / OMEGA_BLOCK;
    while ((blocks > 1u) && ((blocks * OMEGA_BLOCK * buffers_bytes) > (free_bytes / 2u)))
    {
        blocks -= 1u;
    }
    *threads_used = (unsigned int)(blocks * OMEGA_BLOCK);
    unsigned char *scratch = NULL;
    unsigned long long *hand = NULL;
    unsigned long long *device_counts = NULL;
    OmegaBatch *batch = NULL;
    cudaEvent_t launched = NULL;
    cudaEvent_t finished = NULL;
    ok = sim_status_check(results, cudaMalloc((void **)&device_counts, sizeof(counts->count)), "device: counts");
    ok = ok && sim_status_check(results,
                                cudaMemcpy(device_counts, counts->count, sizeof(counts->count), cudaMemcpyHostToDevice),
                                "device: counts");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&scratch, blocks * OMEGA_BLOCK * buffers_bytes),
                                "device: buffers");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&hand, OMEGA_BATCH_MAX * sizeof(unsigned long long)),
                                "device: hand");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&batch, sizeof(OmegaBatch)), "device: batch");
    ok = ok && sim_status_check(results, cudaEventCreate(&launched), "device: event");
    ok = ok && sim_status_check(results, cudaEventCreate(&finished), "device: event");
    std::vector<OmegaResults> tallies(workers);
    // the launch before this one, whose handed back terms the host settles while this one runs
    std::vector<unsigned long long> stored_hand;
    unsigned int stored_length = 0u;
    unsigned long long stored_from = 0ull;
    unsigned long long size = 1ull << 12u;
    static OmegaResults job;
    for (unsigned int length = 2u; (ok != 0) && (length <= counts->length); length += 1u)
    {
        const unsigned long long total = omega_count(counts, length, 0u);
        for (unsigned long long job_from = 0ull; (ok != 0) && (job_from < total); job_from += OMEGA_JOB_TERMS)
        {
            const unsigned long long job_count =
                ((total - job_from) < OMEGA_JOB_TERMS) ? (total - job_from) : OMEGA_JOB_TERMS;
            const OmegaLedgerJob *kept = NULL;
            for (const OmegaLedgerJob &one : done)
            {
                if ((one.steps == counts->steps) && (one.tokens == counts->tokens) && (one.length == length) &&
                    (one.from == job_from) && (one.count == job_count))
                {
                    kept = &one;
                    break;
                }
            }
            if (kept != NULL)
            {
                omega_merge(fates, &kept->results);
                *jobs_kept += 1ull;
                continue;
            }
            omega_results_open(&job);
            const unsigned long long job_end = job_from + job_count;
            unsigned long long from = job_from;
            while ((ok != 0) && (from < job_end))
            {
                const unsigned long long take = ((job_end - from) < size) ? (job_end - from) : size;
                ok = sim_status_check(results, cudaMemset(batch, 0, sizeof(OmegaBatch)), "device: open");
                ok = ok && sim_status_check(results, cudaEventRecord(launched), "device: event");
                omega_kernel<<<(unsigned int)blocks, OMEGA_BLOCK>>>(
                    batch, device_counts, length, from, take, steps, tokens, steps < counts->steps,
                    tokens < counts->tokens, token_capacity, scratch, hand);
                ok = ok && sim_status_check(results, cudaGetLastError(), "device: launch");
                ok = ok && sim_status_check(results, cudaEventRecord(finished), "device: event");
                omega_hand_settle(counts, stored_length, stored_from, stored_hand, workers, tallies, &job);
                stored_hand.clear();
                ok = ok && sim_status_check(results, cudaEventSynchronize(finished), "device: run");
                OmegaBatch result;
                ok = ok && sim_status_check(results, cudaMemcpy(&result, batch, sizeof(result), cudaMemcpyDeviceToHost),
                                            "device: batch read");
                float milliseconds = 0.0f;
                ok = ok && sim_status_check(results, cudaEventElapsedTime(&milliseconds, launched, finished),
                                            "device: event");
                if (ok == 0)
                {
                    break;
                }
                stored_hand.resize(result.handed);
                ok = (result.handed == 0ull) ||
                     sim_status_check(results,
                                      cudaMemcpy(stored_hand.data(), hand, result.handed * sizeof(unsigned long long),
                                                 cudaMemcpyDeviceToHost),
                                      "device: hand read");
                stored_length = length;
                stored_from = from;
                job.fate[OMEGA_HALTS][length] += result.halts;
                if (result.steps_key != 0ull)
                {
                    omega_champion(&job.max_steps[length], &job.steps_champion[length], result.steps_key >> 32u,
                                   from + (0xFFFFFFFFull - (result.steps_key & 0xFFFFFFFFull)));
                    omega_champion(&job.max_bits[length], &job.bits_champion[length], result.bits_key >> 32u,
                                   from + (0xFFFFFFFFull - (result.bits_key & 0xFFFFFFFFull)));
                }
                for (unsigned long long at = 0ull; at < result.handed; at += 1ull)
                {
                    *host_runs += ((stored_hand[at] & 0xFFull) == OMEGA_HOST_RUNS) ? 1ull : 0ull;
                }
                from += take;
                if ((milliseconds < 100.0f) && (take == size) && (size < OMEGA_BATCH_MAX))
                {
                    size *= 2ull;
                }
                else if ((milliseconds > 500.0f) && (size > 1024ull))
                {
                    size /= 2ull;
                }
            }
            // the job is whole only once its last launch's handed back terms are settled
            omega_hand_settle(counts, stored_length, stored_from, stored_hand, workers, tallies, &job);
            stored_hand.clear();
            if (ok == 0)
            {
                break;
            }
            if ((ledger != NULL) && (omega_ledger_write(ledger, counts, length, job_from, job_count, &job) == 0))
            {
                sim_check(results, 0, "device: the ledger takes each finished job");
                ok = 0;
                break;
            }
            omega_merge(fates, &job);
            *jobs_run += 1ull;
        }
    }
    (void)cudaEventDestroy(finished);
    (void)cudaEventDestroy(launched);
    (void)cudaFree(batch);
    (void)cudaFree(hand);
    (void)cudaFree(scratch);
    (void)cudaFree(device_counts);
    return ok;
}
