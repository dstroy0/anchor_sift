// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DEVICE_POOL_H
#define DEVICE_POOL_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define DEVICE_POOL_ERROR (-1L)

// every slice starts on 256 bytes, the alignment cudaMalloc gives its own allocations. Any kernel or cub workspace
// reads a slice as it would read an allocation of its own
#define DEVICE_POOL_SLICE_ALIGN 256ull

// the device's allocation page: the driver maps allocations in whole pages, small ones sharing a page. A pool is one
// allocation, rounded to the page once
#define DEVICE_POOL_PAGE_BYTES (2ull << 20u)

    // A job's device buffers as one allocation. A plan lays out each buffer as a slice whose offset is the running
    // total rounded up to DEVICE_POOL_SLICE_ALIGN. The pool's size is known before any device work: the slices' sum,
    // rounded up to the page once, the size the job declares. A plan whose sum would pass 2^62 bytes is spoiled,
    // and no pool is reserved from it.
    typedef struct
    {
        unsigned long long bytes;
        unsigned long long slices;
        int spoiled;
    } DevicePoolPlan;

    // The held pool: `bytes` from `base`, of which `used` are taken. Slices are taken in the plan's order, each at the
    // offset the plan gave it, and a take past the pool errors.
    typedef struct
    {
        unsigned char *base;
        unsigned long long bytes;
        unsigned long long used;
    } DevicePool;

    // lays out a slice of `bytes` in the plan and returns its offset
    unsigned long long device_pool_plan_slice(DevicePoolPlan *plan, unsigned long long bytes);

    // the bytes a pool reserved from the plan takes: the slices' sum rounded up to the page; 0 for a spoiled plan
    unsigned long long device_pool_plan_bytes(const DevicePoolPlan *plan);

    typedef struct
    {
        const DevicePoolPlan *plan;
        DevicePool *pool;
        EngineError *error;
    } DevicePoolReserveRequest;

    // holds the plan's pool as one allocation of device_pool_plan_bytes, with nothing taken yet; a plan of no bytes
    // holds an empty pool and allocates nothing. The pool is written, not read. A pool already held is released
    // first.
    long device_pool_reserve(const DevicePoolReserveRequest *request);

    typedef struct
    {
        DevicePool *pool;
        unsigned long long bytes;
        void **slice;
        EngineError *error;
    } DevicePoolTakeRequest;

    // takes the next slice of `bytes` at the next 256-byte offset; a slice past the pool errors and nothing is
    // taken
    long device_pool_take(const DevicePoolTakeRequest *request);

    // every slice given back at once, the pool still held
    void device_pool_return(DevicePool *pool);

    void device_pool_release(DevicePool *pool);

#ifdef __cplusplus
}
#endif

#endif
