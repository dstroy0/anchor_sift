// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "device_pool.h"

#include <cuda_runtime.h>

#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

static_assert((DEVICE_POOL_SLICE_ALIGN & (DEVICE_POOL_SLICE_ALIGN - 1ull)) == 0ull,
              "a slice's alignment is a power of two, so rounding to it is a mask");

static_assert((DEVICE_POOL_PAGE_BYTES & (DEVICE_POOL_PAGE_BYTES - 1ull)) == 0ull,
              "the page is a power of two, so rounding to it is a mask");

static_assert(sizeof(size_t) >= sizeof(unsigned long long), "cudaMalloc's size_t holds a pool's 64-bit byte count");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define DEVICE_POOL_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_DEVICE_POOL, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define DEVICE_POOL_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_DEVICE_POOL, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// a plan's sum is held to this, a whole number of slices and of pages, so its rounding to either never wraps and never
// passes it
#define DEVICE_POOL_BYTES_MOST (1ull << 62u)

static_assert(((DEVICE_POOL_BYTES_MOST % DEVICE_POOL_SLICE_ALIGN) == 0ull)
                  && ((DEVICE_POOL_BYTES_MOST % DEVICE_POOL_PAGE_BYTES) == 0ull),
              "the most a plan holds rounds to itself on the slice and on the page");

static unsigned long long device_pool_round(unsigned long long bytes, unsigned long long step)
{
    return (bytes + (step - 1ull)) & ~(step - 1ull);
}

extern "C" unsigned long long device_pool_plan_slice(DevicePoolPlan *plan, unsigned long long bytes)
{
    // an unspoiled plan's sum is at most 2^62, so its offset is too, and the room left never wraps
    const unsigned long long offset = device_pool_round(plan->bytes, DEVICE_POOL_SLICE_ALIGN);
    if ((plan->spoiled != 0) || (bytes > (DEVICE_POOL_BYTES_MOST - offset)))
    {
        plan->spoiled = 1;
        return offset;
    }
    plan->bytes = offset + bytes;
    plan->slices += 1ull;
    return offset;
}

extern "C" unsigned long long device_pool_plan_bytes(const DevicePoolPlan *plan)
{
    return (plan->spoiled != 0) ? 0ull : device_pool_round(plan->bytes, DEVICE_POOL_PAGE_BYTES);
}

extern "C" long device_pool_hold(const DevicePoolHoldRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return DEVICE_POOL_REFUSED;
    }
    EngineError *const error = request->error;
    if (!DEVICE_POOL_HELD((request->plan != NULL) && (request->pool != NULL) && (request->plan->spoiled == 0), request,
                          error, ENGINE_ERROR_REQUEST))
    {
        return DEVICE_POOL_REFUSED;
    }
    DevicePool *const pool = request->pool;
    memset(pool, 0, sizeof(*pool));
    const unsigned long long bytes = device_pool_plan_bytes(request->plan);
    if (bytes == 0ull)
    {
        return 0L;
    }
    unsigned char *base = NULL;
    // a plan's bytes are at most 2^62, and size_t is at least 64 bits (asserted above)
    if (!DEVICE_POOL_TOOK(cudaMalloc((void **)&base, (size_t)bytes), pool, error))
    {
        return DEVICE_POOL_REFUSED;
    }
    pool->base = base;
    pool->bytes = bytes;
    return 0L;
}

extern "C" long device_pool_take(const DevicePoolTakeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return DEVICE_POOL_REFUSED;
    }
    EngineError *const error = request->error;
    if (!DEVICE_POOL_HELD((request->pool != NULL) && (request->slice != NULL), request, error, ENGINE_ERROR_REQUEST))
    {
        return DEVICE_POOL_REFUSED;
    }
    DevicePool *const pool = request->pool;
    // what is taken never passes the pool, which is at most 2^62 bytes, so the rounding never wraps
    const unsigned long long offset = device_pool_round(pool->used, DEVICE_POOL_SLICE_ALIGN);
    if (!DEVICE_POOL_HELD((offset <= pool->bytes) && (request->bytes <= (pool->bytes - offset)), pool, error,
                          ENGINE_ERROR_REQUEST))
    {
        return DEVICE_POOL_REFUSED;
    }
    *request->slice = (void *)(pool->base + offset);
    pool->used = offset + request->bytes;
    return 0L;
}

extern "C" void device_pool_return(DevicePool *pool)
{
    pool->used = 0ull;
}

extern "C" void device_pool_release(DevicePool *pool)
{
    cudaFree(pool->base);
    memset(pool, 0, sizeof(*pool));
}
