// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The device pool (engine/runtime/device_pool): a job's device buffers as slices of one allocation. A plan lays out
// each slice at the running sum rounded up to 256 bytes, and the pool is the sum rounded up to the 2 MiB page once:
// a job knows the bytes it declares before any device work. Eight slices of none to 1,000 bytes are laid out at offsets
// worked by hand; single slices on either side of a page round as worked by hand; a plan that would pass 2^62 bytes
// is spoiled and names no pool, and its hold errors. The pool is held as one allocation: each take in the plan's
// order returns the slice the plan laid out, a kernel writes each slice and another reads it back with nothing landing
// between slices, a take past the pool errors and leaves the pool as it was, and a return gives every slice back.
// The pool's cost is read through the counter tessera's daemon reads, for the tower's four buffers as one pool and as
// four allocations. The test is one job on the device's tessera daemon, submitted before its first device work.
#include "../../../../../../../src/c/engine/runtime/device_pool/device_pool.h"
#include "sim.h"
#include "../../../../../../../src/c/engine/runtime/daemon/tessera_measure.h"

#include <cuda_runtime.h>

#include <stdint.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <unistd.h>
#endif

#define DEVICE_POOL_TEST_SLICES 8u

// the last slice's end, 2,560 + 8
#define DEVICE_POOL_TEST_SUM 2568ull

// where a take after the plan's slices starts: the sum rounded up to 256
#define DEVICE_POOL_TEST_NEXT 2816ull

// the first seven slices, none to 1,000 bytes, are marked by the kernels; the last is their counter
static const unsigned long long s_device_pool_test_bytes[DEVICE_POOL_TEST_SLICES] = {1ull, 255ull,  256ull, 257ull,
                                                                                     0ull, 1000ull, 3ull,   8ull};

// worked by hand: each slice starts at the running sum rounded up to 256
static const unsigned long long s_device_pool_test_offset[DEVICE_POOL_TEST_SLICES] = {
    0ull, 256ull, 512ull, 768ull, 1280ull, 1280ull, 2304ull, 2560ull};

#define DEVICE_POOL_TEST_PAGINGS 6u

// a lone slice's bytes and its pool's bytes, worked by hand against a page of 2,097,152
static const unsigned long long s_device_pool_test_paged[DEVICE_POOL_TEST_PAGINGS][2] = {{0ull, 0ull},
                                                                                         {1ull, 2097152ull},
                                                                                         {2097151ull, 2097152ull},
                                                                                         {2097152ull, 2097152ull},
                                                                                         {2097153ull, 4194304ull},
                                                                                         {3145728ull, 4194304ull}};

// the tower's four buffers for a block of 1,100,000 voxels: the coefficients and the scratch, an int a voxel, the
// overflow flag and the mismatch count
#define DEVICE_POOL_TEST_TOWER_LANES 1100000ull

#define DEVICE_POOL_TEST_TOWER_BUFFERS 4u

// the most the test holds at once is the tower's four buffers as four allocations, each page-rounded: 6, 6 and 2 MiB
// for the two small ones sharing a page
#define DEVICE_POOL_TEST_DECLARED (16ull << 20u)

#define DEVICE_POOL_TEST_SETTLE_MILLISECONDS 600u

#define DEVICE_POOL_TEST_THREADS 256u

__global__ static void device_pool_test_fill(unsigned char *slice, unsigned long long bytes, unsigned char mark)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; at < bytes; at += jump)
    {
        slice[at] = mark;
    }
}

__global__ static void device_pool_test_count(const unsigned char *slice, unsigned long long bytes, unsigned char mark,
                                              unsigned long long *matched)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long found = 0ull;
    for (unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; at < bytes; at += jump)
    {
        found += (slice[at] == mark) ? 1ull : 0ull;
    }
    if (found != 0ull)
    {
        atomicAdd(matched, found);
    }
}

// an error the pool raised as a request it cannot meet
static int device_pool_test_error(long result, const EngineError *error)
{
    return (result == DEVICE_POOL_ERROR) && (error->kind == ENGINE_ERROR_REQUEST) &&
           (error->module == ENGINE_MODULE_DEVICE_POOL);
}

static void device_pool_test_plan(SimResults *results)
{
    DevicePoolPlan plan = {0ull, 0ull, 0};
    int offsets_ok = 1;
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_SLICES; at += 1u)
    {
        const unsigned long long offset = device_pool_plan_slice(&plan, s_device_pool_test_bytes[at]);
        offsets_ok = offsets_ok && (offset == s_device_pool_test_offset[at]);
    }
    sim_check(results, offsets_ok,
              "each slice is laid out at the offset worked by hand, the running sum rounded up to 256 bytes");
    sim_check(results,
              (plan.bytes == DEVICE_POOL_TEST_SUM) && (plan.slices == DEVICE_POOL_TEST_SLICES) && (plan.spoiled == 0),
              "the plan's sum is its last slice's end, over every slice laid out");
    sim_check(results, device_pool_plan_bytes(&plan) == 2097152ull, "the plan's 2,568 bytes are a pool of one page");
    int paged = 1;
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_PAGINGS; at += 1u)
    {
        DevicePoolPlan lone = {0ull, 0ull, 0};
        device_pool_plan_slice(&lone, s_device_pool_test_paged[at][0]);
        paged = paged && (device_pool_plan_bytes(&lone) == s_device_pool_test_paged[at][1]);
    }
    sim_check(results, paged,
              "a pool is its plan's sum rounded up to the 2 MiB page once, and a plan of nothing no pool");
    DevicePoolPlan maximum = {0ull, 0ull, 0};
    device_pool_plan_slice(&maximum, 1ull << 62u);
    sim_check(results, (maximum.spoiled == 0) && (device_pool_plan_bytes(&maximum) == (1ull << 62u)),
              "a plan of 2^62 bytes holds, and is its own pool");
    device_pool_plan_slice(&maximum, 1ull);
    sim_check(results,
              (maximum.spoiled != 0) && (maximum.bytes == (1ull << 62u)) && (maximum.slices == 1ull) &&
                  (device_pool_plan_bytes(&maximum) == 0ull),
              "a byte past 2^62 spoils the plan, its sum and count left as they were, and it names no pool");
    DevicePoolPlan wide = {0ull, 0ull, 0};
    device_pool_plan_slice(&wide, 1ull);
    device_pool_plan_slice(&wide, 0xFFFFFFFFFFFFFFFFull);
    device_pool_plan_slice(&wide, 1ull);
    sim_check(
        results, (wide.spoiled != 0) && (wide.bytes == 1ull) && (wide.slices == 1ull),
        "a slice of 2^64 - 1 bytes spoils the plan without wrapping its sum, and a spoiled plan lays out nothing more");
}

static void device_pool_test_reserve(SimResults *results)
{
    DevicePoolPlan spoiled = {0ull, 0ull, 0};
    device_pool_plan_slice(&spoiled, 0xFFFFFFFFFFFFFFFFull);
    unsigned char marker = 0u;
    DevicePool pool = {&marker, 7ull, 3ull};
    EngineError error;
    memset(&error, 0, sizeof(error));
    const DevicePoolReserveRequest from_spoiled = {&spoiled, &pool, &error};
    sim_check(results,
              device_pool_test_error(device_pool_reserve(&from_spoiled), &error) && (pool.base == &marker) &&
                  (pool.bytes == 7ull) && (pool.used == 3ull),
              "a spoiled plan's hold errors, and the pool is left as it was");
    memset(&error, 0, sizeof(error));
    const DevicePoolReserveRequest planless = {NULL, &pool, &error};
    sim_check(results, device_pool_test_error(device_pool_reserve(&planless), &error) && (pool.base == &marker),
              "a hold with no plan errors");
    const DevicePoolReserveRequest unanswered = {&spoiled, &pool, NULL};
    sim_check(results, (device_pool_reserve(&unanswered) == DEVICE_POOL_ERROR) && (pool.base == &marker),
              "a hold with no error to raise errors");
    DevicePoolPlan empty = {0ull, 0ull, 0};
    memset(&error, 0, sizeof(error));
    const DevicePoolReserveRequest from_empty = {&empty, &pool, &error};
    sim_check(results,
              (device_pool_reserve(&from_empty) == 0L) && (pool.base == NULL) && (pool.bytes == 0ull) &&
                  (pool.used == 0ull) && (error.kind == ENGINE_ERROR_NONE),
              "a plan of nothing holds an empty pool and allocates nothing");
    device_pool_release(&pool);
}

static int device_pool_test_marks(SimResults *results, unsigned char *const *slice, unsigned long long *matched)
{
    int ran = 1;
    for (unsigned int at = 0u; (ran != 0) && (at < (DEVICE_POOL_TEST_SLICES - 1u)); at += 1u)
    {
        // a slice's mark is its place, 1 to 7
        device_pool_test_fill<<<1u, DEVICE_POOL_TEST_THREADS>>>(slice[at], s_device_pool_test_bytes[at],
                                                                (unsigned char)(at + 1u));
        ran = sim_status_check(results, cudaGetLastError(), "a slice is marked");
    }
    int counted = ran;
    for (unsigned int at = 0u; (ran != 0) && (at < (DEVICE_POOL_TEST_SLICES - 1u)); at += 1u)
    {
        unsigned long long found = 0ull;
        ran = sim_status_check(results, cudaMemset(matched, 0, sizeof(unsigned long long)), "the counter is zeroed");
        if (ran != 0)
        {
            // a slice's mark is its place, 1 to 7
            device_pool_test_count<<<1u, DEVICE_POOL_TEST_THREADS>>>(slice[at], s_device_pool_test_bytes[at],
                                                                     (unsigned char)(at + 1u), matched);
            ran = sim_status_check(results, cudaGetLastError(), "a slice is counted") &&
                  sim_status_check(results,
                                   cudaMemcpy(&found, matched, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                                   "the count is read");
        }
        counted = counted && (ran != 0) && (found == s_device_pool_test_bytes[at]);
    }
    sim_check(results, counted, "a kernel marks each slice and another reads every byte of it back");
    return ran;
}

static void device_pool_test_slices(SimResults *results)
{
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_SLICES; at += 1u)
    {
        device_pool_plan_slice(&plan, s_device_pool_test_bytes[at]);
    }
    DevicePool pool;
    memset(&pool, 0, sizeof(pool));
    EngineError error;
    memset(&error, 0, sizeof(error));
    const DevicePoolReserveRequest reserve = {&plan, &pool, &error};
    const int ok = device_pool_reserve(&reserve) == 0L;
    // a device address read as an integer, for its alignment only
    sim_check(results,
              ok && (pool.base != NULL) && (pool.bytes == 2097152ull) && (pool.used == 0ull) &&
                  ((((uintptr_t)pool.base) % 256u) == 0u),
              "the plan's pool is held as one allocation of 2 MiB on a 256-byte boundary, nothing taken");
    if (!ok)
    {
        return;
    }
    unsigned char *slice[DEVICE_POOL_TEST_SLICES];
    int taken = 1;
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_SLICES; at += 1u)
    {
        void *slice_base = NULL;
        const DevicePoolTakeRequest take = {&pool, s_device_pool_test_bytes[at], &slice_base, &error};
        taken = taken && (device_pool_take(&take) == 0L) &&
                (slice_base == (void *)(pool.base + s_device_pool_test_offset[at]));
        slice[at] = (unsigned char *)slice_base;
    }
    sim_check(results, taken && (pool.used == DEVICE_POOL_TEST_SUM),
              "each take in the plan's order returns the slice the plan laid out");
    // the pool is one page, 2 MiB
    int ran = taken && sim_status_check(results, cudaMemset(pool.base, 0, (size_t)pool.bytes), "the pool is zeroed");
    // the last slice, 8 bytes on a 256-byte boundary, holds the kernels' count
    ran = ran && device_pool_test_marks(results, slice, (unsigned long long *)slice[DEVICE_POOL_TEST_SLICES - 1u]);
    unsigned char read[2560];
    ran = ran && sim_status_check(results, cudaMemcpy(read, pool.base, sizeof(read), cudaMemcpyDeviceToHost),
                                  "the slices are read");
    int apart = ran;
    for (unsigned long long byte = 0ull; byte < sizeof(read); byte += 1ull)
    {
        unsigned char mark = 0u;
        for (unsigned int at = 0u; at < (DEVICE_POOL_TEST_SLICES - 1u); at += 1u)
        {
            const unsigned long long start = s_device_pool_test_offset[at];
            // a slice's mark is its place, 1 to 7
            mark =
                ((byte >= start) && (byte < (start + s_device_pool_test_bytes[at]))) ? (unsigned char)(at + 1u) : mark;
        }
        apart = apart && (read[byte] == mark);
    }
    sim_check(results, apart, "every byte before the counter is its slice's mark, and every byte between slices is 0");
    const unsigned long long remaining = pool.bytes - DEVICE_POOL_TEST_NEXT;
    void *untouched = &error;
    memset(&error, 0, sizeof(error));
    const DevicePoolTakeRequest over = {&pool, remaining + 1ull, &untouched, &error};
    sim_check(results,
              device_pool_test_error(device_pool_take(&over), &error) && (pool.used == DEVICE_POOL_TEST_SUM) &&
                  (untouched == (void *)&error),
              "a take one byte past the pool errors, nothing taken and the slice not written");
    void *last = NULL;
    const DevicePoolTakeRequest rest = {&pool, remaining, &last, &error};
    sim_check(results,
              (device_pool_take(&rest) == 0L) && (last == (void *)(pool.base + DEVICE_POOL_TEST_NEXT)) &&
                  (pool.used == pool.bytes),
              "a take of the rest of the pool is held, at the next 256-byte offset, and fills the pool");
    memset(&error, 0, sizeof(error));
    const DevicePoolTakeRequest full = {&pool, 1ull, &untouched, &error};
    sim_check(results,
              device_pool_test_error(device_pool_take(&full), &error) && (pool.used == pool.bytes) &&
                  (untouched == (void *)&error),
              "a take from a full pool errors");
    device_pool_return(&pool);
    const int returned = pool.used == 0ull;
    void *first = NULL;
    const DevicePoolTakeRequest again = {&pool, 1ull, &first, &error};
    sim_check(results,
              returned && (device_pool_take(&again) == 0L) && (first == (void *)pool.base) && (pool.used == 1ull),
              "a return gives every slice back, and the next take starts the pool again");
    memset(&error, 0, sizeof(error));
    const DevicePoolTakeRequest nowhere = {&pool, 1ull, NULL, &error};
    sim_check(results, device_pool_test_error(device_pool_take(&nowhere), &error) && (pool.used == 1ull),
              "a take with nowhere to write its slice errors");
    device_pool_release(&pool);
    sim_check(results, (pool.base == NULL) && (pool.bytes == 0ull) && (pool.used == 0ull),
              "a release leaves the pool empty");
}

typedef struct
{
    TesseraMeasure *measure;
    unsigned long long pid;
} DevicePoolTestCounter;

static int device_pool_test_read(const DevicePoolTestCounter *counter, unsigned long long *used)
{
    // the counter settles a moment after the driver maps or unmaps a page
#if defined(_WIN32)
    Sleep(DEVICE_POOL_TEST_SETTLE_MILLISECONDS);
#else
    usleep(DEVICE_POOL_TEST_SETTLE_MILLISECONDS * 1000u);
#endif
    return tessera_measure_process(counter->measure, counter->pid, used);
}

static void device_pool_test_measurement(SimResults *results, const char *what, unsigned long long from,
                                         unsigned long long to)
{
    scriptura_text(&results->line, what);
    // a difference of two readings of one process's device bytes, each below 2^40
    scriptura_signed(&results->line, (long long)to - (long long)from);
    scriptura_text(&results->line, " bytes\n");
}

static void device_pool_test_cost(SimResults *results)
{
    int device = 0;
    cudaDeviceProp properties;
    memset(&properties, 0, sizeof(properties));
    const int known =
        sim_status_check(results, cudaGetDevice(&device), "the device is named") &&
        sim_status_check(results, cudaGetDeviceProperties(&properties, device), "the device's properties are read");
    unsigned long long luid = 0ull;
#if defined(_WIN32)
    memcpy(&luid, properties.luid, sizeof(luid));
    const unsigned long long pid = (unsigned long long)GetCurrentProcessId();
#else
    // a process id is positive
    const unsigned long long pid = (unsigned long long)getpid();
#endif
    TesseraMeasure *const measure =
        known ? tessera_measure_open((const unsigned char *)properties.uuid.bytes, luid) : NULL;
    const DevicePoolTestCounter counter = {measure, pid};
    sim_check(results, counter.measure != NULL, "the device's counter opens for this process");
    if (counter.measure == NULL)
    {
        return;
    }
    const unsigned long long buffer_bytes[DEVICE_POOL_TEST_TOWER_BUFFERS] = {
        DEVICE_POOL_TEST_TOWER_LANES * sizeof(int), DEVICE_POOL_TEST_TOWER_LANES * sizeof(int), sizeof(unsigned int),
        sizeof(unsigned long long)};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_TOWER_BUFFERS; at += 1u)
    {
        device_pool_plan_slice(&plan, buffer_bytes[at]);
    }
    const unsigned long long pool_bytes = device_pool_plan_bytes(&plan);
    unsigned long long before = 0ull;
    unsigned long long pooled = 0ull;
    unsigned long long freed = 0ull;
    unsigned long long apart = 0ull;
    DevicePool pool;
    memset(&pool, 0, sizeof(pool));
    EngineError error;
    memset(&error, 0, sizeof(error));
    const DevicePoolReserveRequest reserve = {&plan, &pool, &error};
    int read = device_pool_test_read(&counter, &before) && (device_pool_reserve(&reserve) == 0L) &&
               device_pool_test_read(&counter, &pooled);
    device_pool_release(&pool);
    read = read && device_pool_test_read(&counter, &freed);
    void *buffers[DEVICE_POOL_TEST_TOWER_BUFFERS] = {NULL, NULL, NULL, NULL};
    for (unsigned int at = 0u; (read != 0) && (at < DEVICE_POOL_TEST_TOWER_BUFFERS); at += 1u)
    {
        // each buffer is below 2^32 bytes
        read = sim_status_check(results, cudaMalloc(&buffers[at], (size_t)buffer_bytes[at]), "a buffer is held apart");
    }
    read = read && device_pool_test_read(&counter, &apart);
    for (unsigned int at = 0u; at < DEVICE_POOL_TEST_TOWER_BUFFERS; at += 1u)
    {
        cudaFree(buffers[at]);
    }
    tessera_measure_close(counter.measure);
    sim_check(results, read, "every reading of the device's counter is taken");
    scriptura_text(&results->line, "  the tower's four buffers for 1,100,000 voxels: ");
    scriptura_decimal(&results->line, plan.bytes, 1u);
    scriptura_text(&results->line, " bytes planned, a pool of ");
    scriptura_decimal(&results->line, pool_bytes, 1u);
    scriptura_text(&results->line, "\n");
    device_pool_test_measurement(results, "    held as one pool:         ", before, pooled);
    device_pool_test_measurement(results, "    the pool released:        ", pooled, freed);
    device_pool_test_measurement(results, "    held as four allocations: ", freed, apart);
    sim_flush(results);
    sim_check(results, read && (pooled >= before) && ((pooled - before) == pool_bytes),
              "the pool costs its plan's page-rounded bytes, to the byte");
    sim_check(results, read && (freed == before), "a release gives every page of the pool back");
    sim_check(results, read && (apart >= freed) && ((apart - freed) >= (pooled - before)),
              "the pool costs no more than its four buffers held apart");
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    scriptura_text(&results.line,
                   "  the device pool: a job's buffers as slices of one allocation, rounded to the page once\n");
    device_pool_test_plan(&results);
    if (sim_job_submit(&results, "device_pool_test", count, arguments, DEVICE_POOL_TEST_DECLARED) != 0)
    {
        device_pool_test_reserve(&results);
        device_pool_test_slices(&results);
        device_pool_test_cost(&results);
    }
    return sim_close(&results, "device pool test");
}
