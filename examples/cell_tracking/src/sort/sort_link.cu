// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "../../../../src/c/engine/runtime/device_pool/device_pool.h"
#include "drift.h"
#include "../../../../src/c/engine/nbody/heaviest_matching/heaviest_matching.h"
#include "scan.h"
#include "sort.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define SORT_SEEK _fseeki64
#define SORT_TELL _ftelli64
#else
#define SORT_SEEK fseeko
#define SORT_TELL ftello
#endif

#define SORT_THREADS 256u

// the gate reads two ways: forward, each prediction against the targets; backward, each target against the
// predictions. A direction holds its places, their least lengths, their tie counts, the ties' offsets and the tie list
#define SORT_DIRECTIONS 2u

#define SORT_SLICES_A_DIRECTION 5u

#define SORT_SLICES (SORT_SLICES_A_DIRECTION * SORT_DIRECTIONS)

// a tie list holds twice the capacity, and pass 2 fills it a batch of items at a time; one item's ties are at most the
// other frame's points, at most the capacity. Every batch takes at least one item
#define SORT_LIST_CAPACITY(capacity_) (2ull * (unsigned long long)(capacity_))

// the weighted sum of the squared spans is at most 2^63 - 1, and so is every gate length and every crossing dot
#define SORT_LENGTH_MAX 0x7FFFFFFFFFFFFFFFull

#define SORT_NONE 0xFFFFFFFFu

// .points opens with frames, depth, height, width, the residual's limbs and the contrast's bits, then the set's
// readings and its cumulative count; a frame is its count, each point's voxel, then each point's levels
#define SORT_POINTS_HEADER_WORDS 6u

// .drift opens with frames, depth, height, width and the three weights; a frame is its positive voxels, and every frame
// after the first the lag (z, y, x) carrying the previous frame onto it and the agreement at that lag
#define SORT_DRIFT_HEADER_WORDS 7u

typedef struct
{
    unsigned int w[ENGINE_AXES];
} SortWeights;

typedef struct
{
    DevicePool pool;
    unsigned int capacity;
    int *places[SORT_DIRECTIONS];
    unsigned long long *least[SORT_DIRECTIONS];
    unsigned int *ties[SORT_DIRECTIONS];
    unsigned int *offsets[SORT_DIRECTIONS];
    unsigned int *list[SORT_DIRECTIONS];
} SortResident;

static SortResident s_sort_resident;

// the weighted squared length between two places. Each difference is at most its axis's span. Once the span check
// has passed every term and their sum are at most 2^63 - 1
__host__ __device__ static unsigned long long sort_length(const int *one, const int *other, SortWeights weights)
{
    unsigned long long length = 0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const long long difference = (long long)one[axis] - (long long)other[axis];
        // two 32-bit places differ by below 2^32. The size re-signs to unsigned long long exactly
        const unsigned long long size = (unsigned long long)((difference < 0ll) ? -difference : difference);
        length += (unsigned long long)weights.w[axis] * size * size;
    }
    return length;
}

// pass 1: one thread an item of `from`, its least length over every item of `over` and how many items tie at it. The
// items of `over` pass through shared memory a tile at a time
__global__ static void sort_least_kernel(const int *from, unsigned int from_count, const int *over,
                                         unsigned int over_count, SortWeights weights, unsigned long long *least,
                                         unsigned int *ties)
{
    __shared__ int tile[ENGINE_AXES * SORT_THREADS];
    const unsigned int item = (blockIdx.x * blockDim.x) + threadIdx.x;
    const int live = item < from_count;
    int here[ENGINE_AXES] = {0, 0, 0};
    for (unsigned int axis = 0u; live && (axis < ENGINE_AXES); axis += 1u)
    {
        here[axis] = from[(ENGINE_AXES * item) + axis];
    }
    unsigned long long best = ~0ull;
    unsigned int count = 0u;
    for (unsigned int base = 0u; base < over_count; base += SORT_THREADS)
    {
        const unsigned int span = ((over_count - base) < SORT_THREADS) ? (over_count - base) : SORT_THREADS;
        __syncthreads();
        for (unsigned int axis = 0u; (threadIdx.x < span) && (axis < ENGINE_AXES); axis += 1u)
        {
            tile[(ENGINE_AXES * threadIdx.x) + axis] = over[(ENGINE_AXES * (base + threadIdx.x)) + axis];
        }
        __syncthreads();
        for (unsigned int at = 0u; live && (at < span); at += 1u)
        {
            const unsigned long long length = sort_length(here, &tile[ENGINE_AXES * at], weights);
            count = (length < best) ? 1u : ((length == best) ? (count + 1u) : count);
            best = (length < best) ? length : best;
        }
    }
    if (live)
    {
        least[item] = best;
        ties[item] = count;
    }
}

// pass 2: one thread an item of `from` in [first, end), writing the indices of the items of `over` at its least
// length, in their order, from its offset less the batch's first offset
__global__ static void sort_ties_kernel(const int *from, unsigned int first, unsigned int end, const int *over,
                                        unsigned int over_count, SortWeights weights, const unsigned long long *least,
                                        const unsigned int *offsets, unsigned int *list)
{
    __shared__ int tile[ENGINE_AXES * SORT_THREADS];
    const unsigned int item = first + (blockIdx.x * blockDim.x) + threadIdx.x;
    const int live = item < end;
    int here[ENGINE_AXES] = {0, 0, 0};
    for (unsigned int axis = 0u; live && (axis < ENGINE_AXES); axis += 1u)
    {
        here[axis] = from[(ENGINE_AXES * item) + axis];
    }
    const unsigned long long best = live ? least[item] : 0ull;
    unsigned int written = live ? (offsets[item] - offsets[first]) : 0u;
    for (unsigned int base = 0u; base < over_count; base += SORT_THREADS)
    {
        const unsigned int span = ((over_count - base) < SORT_THREADS) ? (over_count - base) : SORT_THREADS;
        __syncthreads();
        for (unsigned int axis = 0u; (threadIdx.x < span) && (axis < ENGINE_AXES); axis += 1u)
        {
            tile[(ENGINE_AXES * threadIdx.x) + axis] = over[(ENGINE_AXES * (base + threadIdx.x)) + axis];
        }
        __syncthreads();
        for (unsigned int at = 0u; live && (at < span); at += 1u)
        {
            if (sort_length(here, &tile[ENGINE_AXES * at], weights) == best)
            {
                list[written] = base + at;
                written += 1u;
            }
        }
    }
}

// the pool's slices for frames of `capacity` points, in the order they are laid out and taken: each direction's places,
// least lengths, tie counts, offsets and tie list
static DevicePoolPlan sort_plan(unsigned long long capacity, EngineError *error,
                                DevicePoolTakeRequest takes[SORT_SLICES])
{
    SortResident *const resident = &s_sort_resident;
    DevicePoolPlan plan = {0ull, 0ull, 0};
    unsigned int at = 0u;
    for (unsigned int direction = 0u; direction < SORT_DIRECTIONS; direction += 1u)
    {
        const DevicePoolTakeRequest requests[SORT_SLICES_A_DIRECTION] = {
            {&resident->pool, ENGINE_AXES * capacity * sizeof(int), (void **)&resident->places[direction], error},
            {&resident->pool, capacity * sizeof(unsigned long long), (void **)&resident->least[direction], error},
            {&resident->pool, capacity * sizeof(unsigned int), (void **)&resident->ties[direction], error},
            {&resident->pool, capacity * sizeof(unsigned int), (void **)&resident->offsets[direction], error},
            {&resident->pool, SORT_LIST_CAPACITY(capacity) * sizeof(unsigned int), (void **)&resident->list[direction],
             error}};
        for (unsigned int slice = 0u; slice < SORT_SLICES_A_DIRECTION; slice += 1u)
        {
            takes[at] = requests[slice];
            device_pool_plan_slice(&plan, requests[slice].bytes);
            at += 1u;
        }
    }
    return plan;
}

// the pool only grows: a pair within the capacity it holds takes it as it is
static int sort_reserve(unsigned int capacity)
{
    SortResident *const resident = &s_sort_resident;
    if ((resident->capacity != 0u) && (resident->capacity >= capacity))
    {
        return 1;
    }
    device_pool_release(&resident->pool);
    memset(resident, 0, sizeof(*resident));
    // the pair errors as a hold, and the pool's error is kept here and dropped
    EngineError error;
    memset(&error, 0, sizeof(error));
    DevicePoolTakeRequest takes[SORT_SLICES];
    const DevicePoolPlan plan = sort_plan(capacity, &error, takes);
    const DevicePoolReserveRequest reserve = {&plan, &resident->pool, &error};
    int ok = device_pool_reserve(&reserve) == 0L;
    // the slices are taken in the plan's order, and each lands where the plan laid it out with none errored
    for (unsigned int at = 0u; (ok != 0) && (at < SORT_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    if (ok == 0)
    {
        device_pool_release(&resident->pool);
        memset(resident, 0, sizeof(*resident));
        return 0;
    }
    resident->capacity = capacity;
    return 1;
}

extern "C" unsigned long long sort_reserve_bytes(unsigned int maximum)
{
    // a frame past the matching's bound errors and holds nothing
    DevicePoolTakeRequest takes[SORT_SLICES];
    const DevicePoolPlan plan = sort_plan((maximum <= SORT_COUNT_MAX) ? maximum : 0u, NULL, takes);
    return device_pool_plan_bytes(&plan);
}

extern "C" void sort_release(void)
{
    device_pool_release(&s_sort_resident.pool);
    memset(&s_sort_resident, 0, sizeof(s_sort_resident));
}

extern "C" void sort_links_release(SortLinks *links)
{
    free(links->source);
    free(links->target);
    free(links->cost);
    free(links->weight);
    free(links->component);
    free(links->flags);
    memset(links, 0, sizeof(*links));
}

static int sort_links_reserve(SortLinks *links, unsigned int pairs)
{
    if ((pairs <= links->capacity) && (links->source != NULL))
    {
        return 1;
    }
    const size_t capacity = (size_t)pairs + 1u;
    unsigned int *const source = (unsigned int *)realloc(links->source, capacity * sizeof(unsigned int));
    links->source = (source != NULL) ? source : links->source;
    unsigned int *const target = (unsigned int *)realloc(links->target, capacity * sizeof(unsigned int));
    links->target = (target != NULL) ? target : links->target;
    unsigned long long *const cost = (unsigned long long *)realloc(links->cost, capacity * sizeof(unsigned long long));
    links->cost = (cost != NULL) ? cost : links->cost;
    unsigned int *const weight = (unsigned int *)realloc(links->weight, capacity * sizeof(unsigned int));
    links->weight = (weight != NULL) ? weight : links->weight;
    unsigned int *const component = (unsigned int *)realloc(links->component, capacity * sizeof(unsigned int));
    links->component = (component != NULL) ? component : links->component;
    unsigned int *const flags = (unsigned int *)realloc(links->flags, capacity * sizeof(unsigned int));
    links->flags = (flags != NULL) ? flags : links->flags;
    const int ok = (source != NULL) && (target != NULL) && (cost != NULL) && (weight != NULL) && (component != NULL) &&
                   (flags != NULL);
    // a capacity is kept only when every array reached it
    links->capacity = ok ? pairs : 0u;
    return ok;
}

// the host's arrays for one pair, freed whole at its end. The still ties, offsets and list are allocated only with the
// still term: each still place's nearest targets
typedef struct
{
    unsigned int *ties[SORT_DIRECTIONS];
    unsigned int *offsets[SORT_DIRECTIONS];
    unsigned int *list[SORT_DIRECTIONS];
    unsigned int *still_ties;
    unsigned int *still_offsets;
    unsigned int *still_list;
    unsigned int *back_start;
    unsigned int *back_list;
    unsigned int *parent;
    unsigned int *label;
    unsigned long long *need;
    unsigned char *passed;
    unsigned char *chosen;
    unsigned int *group_start;
    unsigned int *group;
} SortScratch;

static void sort_scratch_free(SortScratch *scratch)
{
    for (unsigned int direction = 0u; direction < SORT_DIRECTIONS; direction += 1u)
    {
        free(scratch->ties[direction]);
        free(scratch->offsets[direction]);
        free(scratch->list[direction]);
    }
    free(scratch->still_ties);
    free(scratch->still_offsets);
    free(scratch->still_list);
    free(scratch->back_start);
    free(scratch->back_list);
    free(scratch->parent);
    free(scratch->label);
    free(scratch->need);
    free(scratch->passed);
    free(scratch->chosen);
    free(scratch->group_start);
    free(scratch->group);
    memset(scratch, 0, sizeof(*scratch));
}

// the places' span on each axis over the sources, the predictions, the still places when there are any, and the
// targets together. Every gate length and every crossing dot is at most the weighted sum of the squared spans, which
// must be at most 2^63 - 1
static int sort_span_fits(const SortPairRequest *request)
{
    unsigned long long remaining = SORT_LENGTH_MAX;
    int fits = 1;
    for (unsigned int axis = 0u; fits && (axis < ENGINE_AXES); axis += 1u)
    {
        long long least = request->target_places[axis];
        long long maximum = least;
        for (unsigned int source = 0u; source < request->sources; source += 1u)
        {
            const long long place = request->source_places[(ENGINE_AXES * (size_t)source) + axis];
            const long long predicted = request->predictions[(ENGINE_AXES * (size_t)source) + axis];
            least = (place < least) ? place : least;
            maximum = (place > maximum) ? place : maximum;
            least = (predicted < least) ? predicted : least;
            maximum = (predicted > maximum) ? predicted : maximum;
            if (request->stills != NULL)
            {
                const long long stilled = request->stills[(ENGINE_AXES * (size_t)source) + axis];
                least = (stilled < least) ? stilled : least;
                maximum = (stilled > maximum) ? stilled : maximum;
            }
        }
        for (unsigned int target = 0u; target < request->targets; target += 1u)
        {
            const long long place = request->target_places[(ENGINE_AXES * (size_t)target) + axis];
            least = (place < least) ? place : least;
            maximum = (place > maximum) ? place : maximum;
        }
        // two 32-bit places differ by below 2^32. The span re-signs exactly and squares below 2^64
        const unsigned long long span = (unsigned long long)(maximum - least);
        const unsigned long long square = span * span;
        fits = (square == 0ull) || (request->weights[axis] <= (remaining / square));
        remaining -= fits ? ((unsigned long long)request->weights[axis] * square) : 0ull;
    }
    return fits;
}

// the still pass, after both directions are read: each still place's nearest targets, its two passes run on direction
// 0's slices once the predictions there are spent, into the scratch's still ties, offsets and list. `total` is the
// list's length; past SORT_COUNT_MAX the list is not read, and the caller errors on the gate
static int sort_gate_still(const SortPairRequest *request, SortWeights weights, SortScratch *scratch,
                           unsigned long long *total)
{
    SortResident *const resident = &s_sort_resident;
    const unsigned int sources = request->sources;
    const unsigned int targets = request->targets;
    *total = 0ull;
    scratch->still_ties = (unsigned int *)malloc(((size_t)sources + 1u) * sizeof(unsigned int));
    scratch->still_offsets = (unsigned int *)malloc(((size_t)sources + 1u) * sizeof(unsigned int));
    int ok = (scratch->still_ties != NULL) && (scratch->still_offsets != NULL) &&
             (cudaMemcpy(resident->places[0], request->stills, ENGINE_AXES * (size_t)sources * sizeof(int),
                         cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        // the sources are at most 2^30. The blocks fit unsigned int
        const unsigned int blocks = (sources + SORT_THREADS - 1u) / SORT_THREADS;
        sort_least_kernel<<<blocks, SORT_THREADS>>>(resident->places[0], sources, resident->places[1], targets, weights,
                                                    resident->least[0], resident->ties[0]);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(scratch->still_ties, resident->ties[0], (size_t)sources * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    for (unsigned int item = 0u; (ok != 0) && (item < sources); item += 1u)
    {
        *total += scratch->still_ties[item];
    }
    if ((ok == 0) || (*total > SORT_COUNT_MAX))
    {
        return ok;
    }
    unsigned int running = 0u;
    for (unsigned int item = 0u; item < sources; item += 1u)
    {
        scratch->still_offsets[item] = running;
        // the running sum is at most the total, below 2^30
        running += scratch->still_ties[item];
    }
    scratch->still_list = (unsigned int *)malloc(((size_t)*total + 1u) * sizeof(unsigned int));
    ok = (scratch->still_list != NULL) &&
         (cudaMemcpy(resident->offsets[0], scratch->still_offsets, (size_t)sources * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    const unsigned long long list_capacity = SORT_LIST_CAPACITY(resident->capacity);
    unsigned int first = 0u;
    while ((ok != 0) && (first < sources))
    {
        unsigned int end = first;
        unsigned long long taken = 0ull;
        while ((end < sources) && ((taken + scratch->still_ties[end]) <= list_capacity))
        {
            taken += scratch->still_ties[end];
            end += 1u;
        }
        const unsigned int blocks = ((end - first) + SORT_THREADS - 1u) / SORT_THREADS;
        sort_ties_kernel<<<blocks, SORT_THREADS>>>(resident->places[0], first, end, resident->places[1], targets,
                                                   weights, resident->least[0], resident->offsets[0],
                                                   resident->list[0]);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(&scratch->still_list[scratch->still_offsets[first]], resident->list[0],
                         (size_t)taken * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
        first = end;
    }
    return ok;
}

// the gate on the device, two passes each way and with the still term the still pass, then merged on the host into
// (source, target) order with each pair's directions flagged and its cost
static int sort_gate(const SortPairRequest *request, SortLinks *links, SortScratch *scratch)
{
    const unsigned int counts[SORT_DIRECTIONS] = {request->sources, request->targets};
    const int *const places[SORT_DIRECTIONS] = {request->predictions, request->target_places};
    const unsigned int capacity = (counts[0] > counts[1]) ? counts[0] : counts[1];
    const SortWeights weights = {{request->weights[0], request->weights[1], request->weights[2]}};
    SortResident *const resident = &s_sort_resident;
    int ok = sort_reserve(capacity);
    for (unsigned int direction = 0u; (ok != 0) && (direction < SORT_DIRECTIONS); direction += 1u)
    {
        scratch->ties[direction] = (unsigned int *)malloc(((size_t)counts[direction] + 1u) * sizeof(unsigned int));
        scratch->offsets[direction] = (unsigned int *)malloc(((size_t)counts[direction] + 1u) * sizeof(unsigned int));
        ok = (scratch->ties[direction] != NULL) && (scratch->offsets[direction] != NULL) &&
             (cudaMemcpy(resident->places[direction], places[direction],
                         ENGINE_AXES * (size_t)counts[direction] * sizeof(int), cudaMemcpyHostToDevice) == cudaSuccess);
    }
    for (unsigned int direction = 0u; (ok != 0) && (direction < SORT_DIRECTIONS); direction += 1u)
    {
        const unsigned int other = 1u - direction;
        // the counts are at most 2^30. The blocks fit unsigned int
        const unsigned int blocks = (counts[direction] + SORT_THREADS - 1u) / SORT_THREADS;
        sort_least_kernel<<<blocks, SORT_THREADS>>>(resident->places[direction], counts[direction],
                                                    resident->places[other], counts[other], weights,
                                                    resident->least[direction], resident->ties[direction]);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(scratch->ties[direction], resident->ties[direction],
                         (size_t)counts[direction] * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    if (ok == 0)
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    // the gate is at most both tie lists, which the matching bounds
    unsigned long long totals[SORT_DIRECTIONS] = {0ull, 0ull};
    for (unsigned int direction = 0u; direction < SORT_DIRECTIONS; direction += 1u)
    {
        for (unsigned int item = 0u; item < counts[direction]; item += 1u)
        {
            totals[direction] += scratch->ties[direction][item];
        }
    }
    if ((totals[0] + totals[1]) > SORT_COUNT_MAX)
    {
        links->why = SORT_WHY_GATE;
        return 0;
    }
    for (unsigned int direction = 0u; (ok != 0) && (direction < SORT_DIRECTIONS); direction += 1u)
    {
        unsigned int running = 0u;
        for (unsigned int item = 0u; item < counts[direction]; item += 1u)
        {
            scratch->offsets[direction][item] = running;
            // the running sum is at most the total, below 2^30
            running += scratch->ties[direction][item];
        }
        scratch->list[direction] = (unsigned int *)malloc(((size_t)totals[direction] + 1u) * sizeof(unsigned int));
        ok = (scratch->list[direction] != NULL) &&
             (cudaMemcpy(resident->offsets[direction], scratch->offsets[direction],
                         (size_t)counts[direction] * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    }
    const unsigned long long list_capacity = SORT_LIST_CAPACITY(resident->capacity);
    for (unsigned int direction = 0u; (ok != 0) && (direction < SORT_DIRECTIONS); direction += 1u)
    {
        const unsigned int other = 1u - direction;
        unsigned int first = 0u;
        while ((ok != 0) && (first < counts[direction]))
        {
            unsigned int end = first;
            unsigned long long taken = 0ull;
            while ((end < counts[direction]) && ((taken + scratch->ties[direction][end]) <= list_capacity))
            {
                taken += scratch->ties[direction][end];
                end += 1u;
            }
            const unsigned int blocks = ((end - first) + SORT_THREADS - 1u) / SORT_THREADS;
            sort_ties_kernel<<<blocks, SORT_THREADS>>>(resident->places[direction], first, end, resident->places[other],
                                                       counts[other], weights, resident->least[direction],
                                                       resident->offsets[direction], resident->list[direction]);
            ok = (cudaGetLastError() == cudaSuccess) &&
                 (cudaMemcpy(&scratch->list[direction][scratch->offsets[direction][first]], resident->list[direction],
                             (size_t)taken * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
            first = end;
        }
    }
    unsigned long long still_total = 0ull;
    if ((ok != 0) && (request->stills != NULL))
    {
        ok = sort_gate_still(request, weights, scratch, &still_total);
    }
    if ((ok != 0) && ((totals[0] + totals[1] + still_total) > SORT_COUNT_MAX))
    {
        links->why = SORT_WHY_GATE;
        return 0;
    }
    const unsigned int sources = counts[0];
    scratch->back_start = (ok != 0) ? (unsigned int *)calloc((size_t)sources + 2u, sizeof(unsigned int)) : NULL;
    scratch->back_list = (ok != 0) ? (unsigned int *)malloc(((size_t)totals[1] + 1u) * sizeof(unsigned int)) : NULL;
    // the gate's pairs are at most the three totals, below 2^30
    ok = ok && (scratch->back_start != NULL) && (scratch->back_list != NULL) &&
         sort_links_reserve(links, (unsigned int)(totals[0] + totals[1] + still_total));
    if (ok == 0)
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    // each backward tie, a target naming a source, regrouped by the source with its targets kept in order
    for (unsigned int target = 0u; target < counts[1]; target += 1u)
    {
        for (unsigned int tie = 0u; tie < scratch->ties[1][target]; tie += 1u)
        {
            scratch->back_start[scratch->list[1][scratch->offsets[1][target] + tie] + 2u] += 1u;
        }
    }
    for (unsigned int source = 0u; source < sources; source += 1u)
    {
        scratch->back_start[source + 2u] += scratch->back_start[source + 1u];
    }
    // back_start[source + 1] is where the source's regrouped targets are written next, and after the scatter it is
    // where they end
    for (unsigned int target = 0u; target < counts[1]; target += 1u)
    {
        for (unsigned int tie = 0u; tie < scratch->ties[1][target]; tie += 1u)
        {
            const unsigned int source = scratch->list[1][scratch->offsets[1][target] + tie];
            scratch->back_list[scratch->back_start[source + 1u]] = target;
            scratch->back_start[source + 1u] += 1u;
        }
    }
    unsigned int pairs = 0u;
    for (unsigned int source = 0u; source < sources; source += 1u)
    {
        const unsigned int *const ahead = &scratch->list[0][scratch->offsets[0][source]];
        const unsigned int ahead_count = scratch->ties[0][source];
        const unsigned int *const back = &scratch->back_list[scratch->back_start[source]];
        const unsigned int back_count = scratch->back_start[source + 1u] - scratch->back_start[source];
        const unsigned int *const still =
            (request->stills != NULL) ? &scratch->still_list[scratch->still_offsets[source]] : NULL;
        const unsigned int still_count = (request->stills != NULL) ? scratch->still_ties[source] : 0u;
        unsigned int at_ahead = 0u;
        unsigned int at_back = 0u;
        unsigned int at_still = 0u;
        while ((at_ahead < ahead_count) || (at_back < back_count) || (at_still < still_count))
        {
            // each list ascends. The pair's target is the least at their heads, and each list whose head it is
            // names a direction
            unsigned int target = SORT_NONE;
            target = ((at_ahead < ahead_count) && (ahead[at_ahead] < target)) ? ahead[at_ahead] : target;
            target = ((at_back < back_count) && (back[at_back] < target)) ? back[at_back] : target;
            target = ((at_still < still_count) && (still[at_still] < target)) ? still[at_still] : target;
            const int forward = (at_ahead < ahead_count) && (ahead[at_ahead] == target);
            const int backward = (at_back < back_count) && (back[at_back] == target);
            const int stilled = (at_still < still_count) && (still[at_still] == target);
            const int *const place = &request->target_places[ENGINE_AXES * (size_t)target];
            const unsigned long long moved =
                sort_length(&request->predictions[ENGINE_AXES * (size_t)source], place, weights);
            // with the still term a pair's cost is the lesser of its lengths from the prediction and the still place
            const unsigned long long resting =
                (request->stills != NULL) ? sort_length(&request->stills[ENGINE_AXES * (size_t)source], place, weights)
                                          : moved;
            links->source[pairs] = source;
            links->target[pairs] = target;
            links->cost[pairs] = (resting < moved) ? resting : moved;
            links->weight[pairs] = 0u;
            links->component[pairs] = 0u;
            links->flags[pairs] = (forward ? SORT_GATE_FORWARD : 0u) | (backward ? SORT_GATE_BACKWARD : 0u) |
                                  (stilled ? SORT_GATE_STILL : 0u);
            pairs += 1u;
            at_ahead += forward ? 1u : 0u;
            at_back += backward ? 1u : 0u;
            at_still += stilled ? 1u : 0u;
        }
    }
    links->pairs = pairs;
    return 1;
}

// the support components, numbered by first appearance in gate order, and each pair's weight K - cost, with K one more
// than its component's summed costs: in a component, any matching of more links outweighs every matching of fewer,
// and among matchings of as many links the lighter cost weighs more
static int sort_weigh(const SortPairRequest *request, SortLinks *links, SortScratch *scratch)
{
    const unsigned int sources = request->sources;
    // the sources and targets are at most 2^30 each. Their nodes fit unsigned int
    const unsigned int nodes = sources + request->targets;
    scratch->parent = (unsigned int *)malloc(((size_t)nodes + 1u) * sizeof(unsigned int));
    scratch->label = (unsigned int *)malloc(((size_t)nodes + 1u) * sizeof(unsigned int));
    if ((scratch->parent == NULL) || (scratch->label == NULL))
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    for (unsigned int node = 0u; node < nodes; node += 1u)
    {
        scratch->parent[node] = node;
        scratch->label[node] = SORT_NONE;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        const unsigned int left = engine_find_root(scratch->parent, links->source[pair]);
        const unsigned int right = engine_find_root(scratch->parent, sources + links->target[pair]);
        if (left != right)
        {
            scratch->parent[right] = left;
        }
    }
    unsigned int components = 0u;
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        const unsigned int root = engine_find_root(scratch->parent, links->source[pair]);
        if (scratch->label[root] == SORT_NONE)
        {
            scratch->label[root] = components;
            components += 1u;
        }
        links->component[pair] = scratch->label[root];
    }
    links->components = components;
    scratch->need = (unsigned long long *)malloc(((size_t)components + 1u) * sizeof(unsigned long long));
    scratch->passed = (unsigned char *)calloc((size_t)components + 1u, 1u);
    if ((scratch->need == NULL) || (scratch->passed == NULL))
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    for (unsigned int component = 0u; component < components; component += 1u)
    {
        scratch->need[component] = 1ull;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        const unsigned int component = links->component[pair];
        const int passes = links->cost[pair] > (~0ull - scratch->need[component]);
        scratch->passed[component] = passes ? 1u : scratch->passed[component];
        scratch->need[component] += ((passes == 0) && (scratch->passed[component] == 0u)) ? links->cost[pair] : 0ull;
    }
    for (unsigned int component = 0u; component < components; component += 1u)
    {
        if ((scratch->passed[component] != 0u) || (scratch->need[component] > 0xFFFFFFFFull))
        {
            links->why = SORT_WHY_WIDE;
            links->wide_component = component;
            links->needs = (scratch->passed[component] != 0u) ? 0ull : scratch->need[component];
            links->needs_past_64 = (scratch->passed[component] != 0u) ? 1 : 0;
            return 0;
        }
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        // K is at most 2^32 - 1 and past every cost in its component. K - cost is 1 or more and fits unsigned int
        links->weight[pair] = (unsigned int)(scratch->need[links->component[pair]] - links->cost[pair]);
    }
    return 1;
}

static int sort_match(const SortPairRequest *request, SortLinks *links, SortScratch *scratch)
{
    scratch->chosen = (unsigned char *)calloc((size_t)links->pairs + 1u, 1u);
    if (scratch->chosen == NULL)
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    const HeaviestMatchingRequest matching = {links->source,    links->target,    links->weight,  links->pairs,
                                              request->sources, request->targets, scratch->chosen};
    const long picked = heaviest_matching_run(&matching);
    if (picked < 0L)
    {
        links->why = SORT_WHY_MATCHING;
        return 0;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        links->flags[pair] |= (scratch->chosen[pair] != 0u) ? SORT_GATE_CHOSEN : 0u;
    }
    // the chosen links are at most the gate's pairs, below 2^30. They narrow to unsigned int exactly
    links->chosen = (unsigned int)picked;
    return 1;
}

// every two chosen links A -> A' and B -> B' in one component: their sources' difference dotted with their targets',
// each axis weighted. Positive keeps their order, zero is level, negative crosses. Each difference is at most its
// axis's span. Every term and the dot are at most 2^63 - 1 in size
static int sort_cross(const SortPairRequest *request, SortLinks *links, SortScratch *scratch)
{
    scratch->group_start = (unsigned int *)calloc((size_t)links->components + 2u, sizeof(unsigned int));
    scratch->group = (unsigned int *)malloc(((size_t)links->chosen + 1u) * sizeof(unsigned int));
    if ((scratch->group_start == NULL) || (scratch->group == NULL))
    {
        links->why = SORT_WHY_DEVICE;
        return 0;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        scratch->group_start[links->component[pair] + 2u] += scratch->chosen[pair];
    }
    for (unsigned int component = 0u; component < links->components; component += 1u)
    {
        scratch->group_start[component + 2u] += scratch->group_start[component + 1u];
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        if (scratch->chosen[pair] != 0u)
        {
            scratch->group[scratch->group_start[links->component[pair] + 1u]] = pair;
            scratch->group_start[links->component[pair] + 1u] += 1u;
        }
    }
    for (unsigned int component = 0u; component < links->components; component += 1u)
    {
        const unsigned int end = scratch->group_start[component + 1u];
        for (unsigned int one = scratch->group_start[component]; one < end; one += 1u)
        {
            const unsigned int a = scratch->group[one];
            for (unsigned int other = one + 1u; other < end; other += 1u)
            {
                const unsigned int b = scratch->group[other];
                long long dot = 0ll;
                for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
                {
                    const long long before =
                        (long long)request->source_places[(ENGINE_AXES * (size_t)links->source[a]) + axis] -
                        (long long)request->source_places[(ENGINE_AXES * (size_t)links->source[b]) + axis];
                    const long long after =
                        (long long)request->target_places[(ENGINE_AXES * (size_t)links->target[a]) + axis] -
                        (long long)request->target_places[(ENGINE_AXES * (size_t)links->target[b]) + axis];
                    dot += (long long)request->weights[axis] * (before * after);
                }
                links->kept += (dot > 0ll) ? 1ull : 0ull;
                links->level += (dot == 0ll) ? 1ull : 0ull;
                links->crossed += (dot < 0ll) ? 1ull : 0ull;
            }
        }
    }
    return 1;
}

// everything a pair's run sets, cleared; the gate's pairs are kept
static void sort_links_clear(SortLinks *links)
{
    links->components = 0u;
    links->chosen = 0u;
    links->kept = 0ull;
    links->level = 0ull;
    links->crossed = 0ull;
    links->why = SORT_WHY_NONE;
    links->wide_component = 0u;
    links->needs = 0ull;
    links->needs_past_64 = 0;
    links->gate_microseconds = 0ull;
    links->match_microseconds = 0ull;
}

extern "C" long sort_link_pair(const SortPairRequest *request, SortLinks *links)
{
    if (links == NULL)
    {
        return SORT_ERROR;
    }
    links->pairs = 0u;
    sort_links_clear(links);
    const int placed =
        (request != NULL) &&
        ((request->sources == 0u) || ((request->source_places != NULL) && (request->predictions != NULL))) &&
        ((request->targets == 0u) || (request->target_places != NULL));
    if ((placed == 0) || (request->sources > SORT_COUNT_MAX) || (request->targets > SORT_COUNT_MAX))
    {
        links->why = SORT_WHY_REQUEST;
        return SORT_ERROR;
    }
    if ((request->sources == 0u) || (request->targets == 0u))
    {
        return 0L;
    }
    if (sort_span_fits(request) == 0)
    {
        links->why = SORT_WHY_SPAN;
        return SORT_ERROR;
    }
    SortScratch scratch;
    memset(&scratch, 0, sizeof(scratch));
    unsigned long long mark = engine_clock_microseconds();
    int ok = sort_gate(request, links, &scratch);
    links->gate_microseconds = engine_clock_microseconds() - mark;
    mark = engine_clock_microseconds();
    ok = ok && sort_weigh(request, links, &scratch) && sort_match(request, links, &scratch) &&
         sort_cross(request, links, &scratch);
    links->match_microseconds = engine_clock_microseconds() - mark;
    sort_scratch_free(&scratch);
    // the chosen links are below 2^30. They widen to long exactly
    return ok ? (long)links->chosen : SORT_ERROR;
}

// O7's second pass on one frame pair whose gate `links` holds, its sources, targets, costs and flags with the chosen
// flag clear: the components, the weights K - cost, the matching and the crossings made again. The predictions are not
// read. Returns the chosen links, or SORT_ERROR with `why` set
static long sort_link_again(const SortPairRequest *request, SortLinks *links)
{
    sort_links_clear(links);
    if (links->pairs == 0u)
    {
        return 0L;
    }
    SortScratch scratch;
    memset(&scratch, 0, sizeof(scratch));
    const unsigned long long mark = engine_clock_microseconds();
    const int ok = sort_weigh(request, links, &scratch) && sort_match(request, links, &scratch) &&
                   sort_cross(request, links, &scratch);
    links->match_microseconds = engine_clock_microseconds() - mark;
    sort_scratch_free(&scratch);
    // the chosen links are below 2^30. They widen to long exactly
    return ok ? (long)links->chosen : SORT_ERROR;
}

// a * b whole, as its high and low 64 bits. Each product of two 32-bit halves is below 2^64, and the middle sum of
// three values below 2^32 is below 2^34
static void sort_product(unsigned long long a, unsigned long long b, unsigned long long *high, unsigned long long *low)
{
    const unsigned long long a_low = a & 0xFFFFFFFFull;
    const unsigned long long a_high = a >> 32u;
    const unsigned long long b_low = b & 0xFFFFFFFFull;
    const unsigned long long b_high = b >> 32u;
    const unsigned long long low_low = a_low * b_low;
    const unsigned long long low_high = a_low * b_high;
    const unsigned long long high_low = a_high * b_low;
    const unsigned long long middle = (low_low >> 32u) + (low_high & 0xFFFFFFFFull) + (high_low & 0xFFFFFFFFull);
    *low = (middle << 32u) | (low_low & 0xFFFFFFFFull);
    // the whole product is below 2^128. Its high word fits
    *high = (a_high * b_high) + (low_high >> 32u) + (high_low >> 32u) + (middle >> 32u);
}

// f / a against g / b, a and b not zero, as f * b against g * a whole: 1 when f / a is the greater, -1 the lesser,
// 0 equal
static int sort_ratio_order(unsigned long long f, unsigned long long a, unsigned long long g, unsigned long long b)
{
    unsigned long long left_high = 0ull;
    unsigned long long left_low = 0ull;
    unsigned long long right_high = 0ull;
    unsigned long long right_low = 0ull;
    sort_product(f, b, &left_high, &left_low);
    sort_product(g, a, &right_high, &right_low);
    if (left_high != right_high)
    {
        return (left_high > right_high) ? 1 : -1;
    }
    return (left_low > right_low) ? 1 : ((left_low < right_low) ? -1 : 0);
}

// a block of the pooling: its summed firsts and pairs, and its first distance's index
typedef struct
{
    unsigned long long firsts;
    unsigned long long pairs;
    unsigned long long first;
} SortBlock;

extern "C" int sort_first_pool(SortFirstCount *counts, unsigned long long count, unsigned long long *blocks,
                               unsigned long long *levels)
{
    if (((counts == NULL) && (count != 0ull)) || (blocks == NULL) || (levels == NULL))
    {
        return 0;
    }
    // every block's sums are at most the pairs' total, which must fit 64 bits
    unsigned long long total = 0ull;
    int ok = 1;
    for (unsigned long long at = 0ull; ok && (at < count); at += 1ull)
    {
        ok = (counts[at].pairs != 0ull) && (counts[at].firsts <= counts[at].pairs) &&
             ((at == 0ull) || (counts[at - 1ull].length < counts[at].length)) && (counts[at].pairs <= (~0ull - total));
        total += ok ? counts[at].pairs : 0ull;
    }
    SortBlock *const stack = ok ? (SortBlock *)malloc(((size_t)count + 1u) * sizeof(SortBlock)) : NULL;
    if (stack == NULL)
    {
        return 0;
    }
    unsigned long long depth = 0ull;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        stack[depth].firsts = counts[at].firsts;
        stack[depth].pairs = counts[at].pairs;
        stack[depth].first = at;
        depth += 1ull;
        // the last block's share above the one before it is a violation: the two pool
        while ((depth >= 2ull) && (sort_ratio_order(stack[depth - 1ull].firsts, stack[depth - 1ull].pairs,
                                                    stack[depth - 2ull].firsts, stack[depth - 2ull].pairs) > 0))
        {
            stack[depth - 2ull].firsts += stack[depth - 1ull].firsts;
            stack[depth - 2ull].pairs += stack[depth - 1ull].pairs;
            depth -= 1ull;
        }
    }
    unsigned long long level = 0ull;
    for (unsigned long long block = 0ull; block < depth; block += 1ull)
    {
        // a block whose share is below the one before it opens a new level; an equal one shares it
        if ((block != 0ull) && (sort_ratio_order(stack[block].firsts, stack[block].pairs, stack[block - 1ull].firsts,
                                                 stack[block - 1ull].pairs) < 0))
        {
            level += 1ull;
        }
        const unsigned long long end = ((block + 1ull) < depth) ? stack[block + 1ull].first : count;
        for (unsigned long long at = stack[block].first; at < end; at += 1ull)
        {
            counts[at].level = level;
        }
    }
    *blocks = depth;
    *levels = (depth == 0ull) ? 0ull : (level + 1ull);
    free(stack);
    return 1;
}

static int sort_read(FILE *file, void *words, size_t bytes)
{
    return (bytes == 0u) || (fread(words, 1u, bytes, file) == bytes);
}

static int sort_write(FILE *file, const void *words, size_t bytes)
{
    return (bytes == 0u) || (fwrite(words, 1u, bytes, file) == bytes);
}

// a skip past 2^63 - 1 bytes is no file this reads
static int sort_skip(FILE *file, unsigned long long bytes)
{
    return (bytes <= 0x7FFFFFFFFFFFFFFFull) && (SORT_SEEK(file, (long long)bytes, SEEK_CUR) == 0);
}

// `count` points of `words` 32-bit words each, in bytes, or all ones when that passes 2^63 - 1
static unsigned long long sort_frame_bytes(unsigned long long count, unsigned long long words)
{
    return ((count != 0ull) && (words > ((0x7FFFFFFFFFFFFFFFull / 4ull) / count))) ? ~0ull : (count * words * 4ull);
}

extern "C" int sort_points_max(const char *set, char *const *samples, unsigned int count, unsigned int *maximum)
{
    if ((set == NULL) || (samples == NULL) || (maximum == NULL))
    {
        return 0;
    }
    unsigned int found = 0u;
    int ok = 1;
    for (unsigned int at = 0u; ok && (at < count); at += 1u)
    {
        char path[ENGINE_PATH_CAPACITY];
        FILE *const file =
            engine_sample_path(path, sizeof(path), set, samples[at], ".points") ? fopen(path, "rb") : NULL;
        unsigned int head[SORT_POINTS_HEADER_WORDS];
        ok = (file != NULL) && sort_read(file, head, sizeof(head)) &&
             sort_skip(file, (1ull + SCAN_READINGS) * sizeof(unsigned long long));
        for (unsigned int frame = 0u; ok && (frame < head[0]); frame += 1u)
        {
            unsigned int points = 0u;
            ok = sort_read(file, &points, sizeof(points)) &&
                 sort_skip(file, sort_frame_bytes(points, 1ull + (unsigned long long)head[4]));
            found = (ok && (points > found)) ? points : found;
        }
        if (file != NULL)
        {
            fclose(file);
        }
        if (ok == 0)
        {
            fprintf(stderr, "  sort: %s: its .points in %s did not read for the most points a frame\n", samples[at],
                    set);
        }
    }
    *maximum = ok ? found : 0u;
    return ok;
}

// a frame as the sort reads it: its points' voxels and places, the lag its .drift record carries the previous frame
// onto it by, and for each point whether a chosen link reached it and that link's motion less the drift. As the
// sources it also holds each point's prediction and flags, and with the still term each point's still place
typedef struct
{
    unsigned int capacity;
    unsigned int count;
    int lag[ENGINE_AXES];
    unsigned int *voxels;
    int *places;
    unsigned int *carried;
    long long *motion;
    int *predictions;
    unsigned int *flags;
    int *stills;
} SortFrame;

// with O7, `keys` holds each gate pair of the sample's first pass as its distance doubled, plus 1 when it is
// first-rank, and `counts` the count they give, one entry a distinct distance
typedef struct
{
    SortFrame frames[2];
    SortLinks links;
    unsigned int *words;
    size_t word_capacity;
    unsigned long long *keys;
    size_t key_count;
    size_t key_capacity;
    SortFirstCount *counts;
    size_t counted;
    size_t count_capacity;
} SortWalk;

typedef struct
{
    unsigned long long frames;
    unsigned long long pairs;
    unsigned long long sources;
    unsigned long long gate;
    unsigned long long components;
    unsigned long long chosen;
    unsigned long long kept;
    unsigned long long level;
    unsigned long long crossed;
    unsigned long long outside;
    unsigned long long carried;
    unsigned long long gate_microseconds;
    unsigned long long match_microseconds;
    unsigned long long distinct;
    unsigned long long blocks;
    unsigned long long levels;
    unsigned long long changed;
} SortResults;

static int sort_frame_reserve(SortFrame *frame, unsigned int count)
{
    if ((count <= frame->capacity) && (frame->voxels != NULL))
    {
        return 1;
    }
    const size_t capacity = (size_t)count + 1u;
    unsigned int *const voxels = (unsigned int *)realloc(frame->voxels, capacity * sizeof(unsigned int));
    frame->voxels = (voxels != NULL) ? voxels : frame->voxels;
    int *const places = (int *)realloc(frame->places, ENGINE_AXES * capacity * sizeof(int));
    frame->places = (places != NULL) ? places : frame->places;
    unsigned int *const carried = (unsigned int *)realloc(frame->carried, capacity * sizeof(unsigned int));
    frame->carried = (carried != NULL) ? carried : frame->carried;
    long long *const motion = (long long *)realloc(frame->motion, ENGINE_AXES * capacity * sizeof(long long));
    frame->motion = (motion != NULL) ? motion : frame->motion;
    int *const predictions = (int *)realloc(frame->predictions, ENGINE_AXES * capacity * sizeof(int));
    frame->predictions = (predictions != NULL) ? predictions : frame->predictions;
    unsigned int *const flags = (unsigned int *)realloc(frame->flags, capacity * sizeof(unsigned int));
    frame->flags = (flags != NULL) ? flags : frame->flags;
    int *const stills = (int *)realloc(frame->stills, ENGINE_AXES * capacity * sizeof(int));
    frame->stills = (stills != NULL) ? stills : frame->stills;
    const int ok = (voxels != NULL) && (places != NULL) && (carried != NULL) && (motion != NULL) &&
                   (predictions != NULL) && (flags != NULL) && (stills != NULL);
    frame->capacity = ok ? count : 0u;
    return ok;
}

static void sort_frame_free(SortFrame *frame)
{
    free(frame->voxels);
    free(frame->places);
    free(frame->carried);
    free(frame->motion);
    free(frame->predictions);
    free(frame->flags);
    free(frame->stills);
    memset(frame, 0, sizeof(*frame));
}

static int sort_words_reserve(SortWalk *walk, size_t words)
{
    if ((words <= walk->word_capacity) && (walk->words != NULL))
    {
        return 1;
    }
    unsigned int *const grown = (unsigned int *)realloc(walk->words, (words + 1u) * sizeof(unsigned int));
    walk->words = (grown != NULL) ? grown : walk->words;
    walk->word_capacity = (grown != NULL) ? words : walk->word_capacity;
    return grown != NULL;
}

// O7: the pair's gate kept for the sample's count, each pair as its distance doubled, plus 1 when it is first-rank.
// Every distance is at most 2^63 - 1. Doubled it fits 64 bits
static int sort_first_keep(SortWalk *walk)
{
    const SortLinks *const links = &walk->links;
    const size_t wanted = walk->key_count + (size_t)links->pairs;
    if (wanted > walk->key_capacity)
    {
        const size_t capacity = (wanted > (2u * walk->key_capacity)) ? wanted : (2u * walk->key_capacity);
        unsigned long long *const grown =
            (unsigned long long *)realloc(walk->keys, (capacity + 1u) * sizeof(unsigned long long));
        if (grown == NULL)
        {
            return 0;
        }
        walk->keys = grown;
        walk->key_capacity = capacity;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        walk->keys[walk->key_count] =
            (links->cost[pair] << 1u) | (((links->flags[pair] & SORT_GATE_FORWARD) != 0u) ? 1ull : 0ull);
        walk->key_count += 1u;
    }
    return 1;
}

// frame `frame` of the .points and its record in the .drift. The levels are passed over, and every voxel must lie in
// the view of `voxels`
static int sort_frame_read(FILE *points, FILE *drift, const unsigned int head[SORT_POINTS_HEADER_WORDS],
                           unsigned int frame, SortFrame *read)
{
    const unsigned int plane = head[2] * head[3];
    const unsigned int voxels = head[1] * plane;
    unsigned int count = 0u;
    int ok = sort_read(points, &count, sizeof(count)) && (count <= voxels) && (count <= SORT_COUNT_MAX) &&
             sort_frame_reserve(read, count) && sort_read(points, read->voxels, (size_t)count * sizeof(unsigned int)) &&
             sort_skip(points, sort_frame_bytes(count, head[4]));
    unsigned int positives = 0u;
    unsigned int agreement = 0u;
    int lag[ENGINE_AXES] = {0, 0, 0};
    ok = ok && sort_read(drift, &positives, sizeof(positives));
    ok = ok &&
         ((frame == 0u) || (sort_read(drift, lag, sizeof(lag)) && sort_read(drift, &agreement, sizeof(agreement))));
    for (unsigned int point = 0u; ok && (point < count); point += 1u)
    {
        const unsigned int voxel = read->voxels[point];
        ok = voxel < voxels;
        // a voxel below the view's voxels, below 2^31, gives places below 2^31, each fitting int
        read->places[(ENGINE_AXES * (size_t)point) + 0u] = (int)(voxel / plane);
        read->places[(ENGINE_AXES * (size_t)point) + 1u] = (int)((voxel % plane) / head[3]);
        read->places[(ENGINE_AXES * (size_t)point) + 2u] = (int)(voxel % head[3]);
        read->carried[point] = 0u;
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            read->motion[(ENGINE_AXES * (size_t)point) + axis] = 0ll;
        }
    }
    read->count = ok ? count : 0u;
    memcpy(read->lag, lag, sizeof(lag));
    return ok;
}

// each source's prediction: its place, the drift onto the next frame, and the motion its chosen link brought, less
// the drift then. A prediction outside the view is kept and flagged; one past 32 bits errors. With `still` set, each
// source's still place too: its place and the drift alone, no motion; one past 32 bits errors as well
static int sort_predict(const unsigned int head[SORT_POINTS_HEADER_WORDS], SortFrame *now, const SortFrame *next,
                        unsigned int still, SortResults *results)
{
    const long long extent[ENGINE_AXES] = {head[1], head[2], head[3]};
    int ok = 1;
    for (unsigned int point = 0u; ok && (point < now->count); point += 1u)
    {
        unsigned int flags = (now->carried[point] != 0u) ? SORT_SOURCE_CARRIED : 0u;
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            const size_t at = (ENGINE_AXES * (size_t)point) + axis;
            const long long predicted = (long long)now->places[at] + (long long)next->lag[axis] + now->motion[at];
            ok = ok && (predicted >= -0x80000000ll) && (predicted <= 0x7FFFFFFFll);
            // a prediction held in [-2^31, 2^31) narrows to int exactly
            now->predictions[at] = ok ? (int)predicted : 0;
            flags |= ((predicted < 0ll) || (predicted >= extent[axis])) ? SORT_SOURCE_OUTSIDE : 0u;
            if (still != 0u)
            {
                const long long stilled = (long long)now->places[at] + (long long)next->lag[axis];
                ok = ok && (stilled >= -0x80000000ll) && (stilled <= 0x7FFFFFFFll);
                // a still place held in [-2^31, 2^31) narrows to int exactly
                now->stills[at] = ok ? (int)stilled : 0;
            }
        }
        now->flags[point] = flags;
        results->outside += ((flags & SORT_SOURCE_OUTSIDE) != 0u) ? 1ull : 0ull;
        results->carried += ((flags & SORT_SOURCE_CARRIED) != 0u) ? 1ull : 0ull;
    }
    return ok;
}

// the pair's record, its sources' records and its gate's records, as one run of words
static int sort_pair_write(FILE *file, SortWalk *walk, const SortFrame *now, const SortFrame *next)
{
    const SortLinks *const links = &walk->links;
    const size_t words =
        SORT_PAIR_WORDS + (SORT_SOURCE_WORDS * (size_t)now->count) + (SORT_GATE_WORDS * (size_t)links->pairs);
    if (sort_words_reserve(walk, words) == 0)
    {
        return 0;
    }
    unsigned int *word = walk->words;
    const unsigned long long counted[3] = {links->kept, links->level, links->crossed};
    word[0] = now->count;
    word[1] = next->count;
    word[2] = links->pairs;
    word[3] = links->components;
    word[4] = links->chosen;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        // a 64-bit count as its low word, then its high
        word[5u + (2u * at)] = (unsigned int)(counted[at] & 0xFFFFFFFFull);
        word[6u + (2u * at)] = (unsigned int)(counted[at] >> 32u);
    }
    word += SORT_PAIR_WORDS;
    for (unsigned int point = 0u; point < now->count; point += 1u)
    {
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            // a signed prediction is written as its two's complement word
            word[axis] = (unsigned int)now->predictions[(ENGINE_AXES * (size_t)point) + axis];
        }
        word[ENGINE_AXES] = now->flags[point];
        word += SORT_SOURCE_WORDS;
    }
    for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
    {
        word[0] = links->source[pair];
        word[1] = links->target[pair];
        // the cost as its low word, then its high
        word[2] = (unsigned int)(links->cost[pair] & 0xFFFFFFFFull);
        word[3] = (unsigned int)(links->cost[pair] >> 32u);
        word[4] = links->weight[pair];
        word[5] = links->component[pair];
        word[6] = links->flags[pair];
        word += SORT_GATE_WORDS;
    }
    return sort_write(file, walk->words, words * sizeof(unsigned int));
}

static void sort_error_print(const char *sample, unsigned int frame, const SortLinks *links)
{
    if ((links->why == SORT_WHY_WIDE) && (links->needs_past_64 != 0))
    {
        fprintf(stderr, "  sort: %s: frames %u and %u: component %u needs K past 64 bits, past 32 bits\n", sample,
                frame, frame + 1u, links->wide_component);
    }
    else if (links->why == SORT_WHY_WIDE)
    {
        fprintf(stderr, "  sort: %s: frames %u and %u: component %u needs K = %llu, past 32 bits\n", sample, frame,
                frame + 1u, links->wide_component, links->needs);
    }
    else if (links->why == SORT_WHY_SPAN)
    {
        fprintf(stderr, "  sort: %s: frames %u and %u: the places' weighted squared spans sum past 2^63 - 1\n", sample,
                frame, frame + 1u);
    }
    else if (links->why == SORT_WHY_GATE)
    {
        fprintf(stderr, "  sort: %s: frames %u and %u: the gate's ties pass %u pairs\n", sample, frame, frame + 1u,
                SORT_COUNT_MAX);
    }
    else if (links->why == SORT_WHY_MATCHING)
    {
        fprintf(stderr, "  sort: %s: frames %u and %u: the matching errored\n", sample, frame, frame + 1u);
    }
    else
    {
        fprintf(
            stderr,
            "  sort: %s: frames %u and %u: the gate's memory could not be reserved or the device errored (why %u)\n",
            sample, frame, frame + 1u, links->why);
    }
}

// the file's place is its end: every frame read whole, and nothing past the last
static int sort_at_end(FILE *file)
{
    const long long place = SORT_TELL(file);
    const int ended = (place >= 0ll) && (SORT_SEEK(file, 0ll, SEEK_END) == 0);
    return ended && (SORT_TELL(file) == place);
}

// the sample's first pass, written whole. With `first` set the header names O7's term, which the second pass makes
// true, and every pair's gate is kept for O7's count
static int sort_frames(const char *sample, const unsigned int weights[ENGINE_AXES], unsigned int still,
                       unsigned int first, FILE *points, FILE *drift, FILE *links_file, SortWalk *walk,
                       SortResults *results)
{
    unsigned int head[SORT_POINTS_HEADER_WORDS];
    unsigned int drift_head[SORT_DRIFT_HEADER_WORDS];
    int ok = sort_read(points, head, sizeof(head)) &&
             sort_skip(points, (1ull + SCAN_READINGS) * sizeof(unsigned long long)) &&
             sort_read(drift, drift_head, sizeof(drift_head));
    if (ok == 0)
    {
        fprintf(stderr, "  sort: %s: its .points or .drift head did not read\n", sample);
        return 0;
    }
    const int agree = (head[0] == drift_head[0]) && (head[1] == drift_head[1]) && (head[2] == drift_head[2]) &&
                      (head[3] == drift_head[3]);
    const int weighed = (drift_head[4] == weights[0]) && (drift_head[5] == weights[1]) && (drift_head[6] == weights[2]);
    const unsigned long long plane = (unsigned long long)head[2] * head[3];
    const int sized = (head[1] != 0u) && (plane != 0ull) && (plane <= (0x7FFFFFFFull / head[1]));
    if (agree == 0)
    {
        fprintf(stderr,
                "  sort: %s: its .points reads %u frames of %u x %u x %u, its .drift %u frames of %u x %u x %u\n",
                sample, head[0], head[1], head[2], head[3], drift_head[0], drift_head[1], drift_head[2], drift_head[3]);
    }
    else if (weighed == 0)
    {
        fprintf(stderr, "  sort: %s: its .drift weights %u, %u, %u are not voxel_pm's %u, %u, %u\n", sample,
                drift_head[4], drift_head[5], drift_head[6], weights[0], weights[1], weights[2]);
    }
    else if (sized == 0)
    {
        fprintf(stderr, "  sort: %s: its view %u x %u x %u passes 2^31 - 1 voxels\n", sample, head[1], head[2],
                head[3]);
    }
    const unsigned int header[SORT_HEADER_WORDS] = {
        head[0],    head[1],
        head[2],    head[3],
        weights[0], weights[1],
        weights[2], SORT_TERMS | ((still != 0u) ? SORT_TERM_STILL : 0u) | ((first != 0u) ? SORT_TERM_FIRST : 0u)};
    // a head that errored has said why above; the header's write and frame 0's read each say their own
    const int headed = agree && weighed && sized;
    const int written = headed && sort_write(links_file, header, sizeof(header));
    ok = written && ((head[0] == 0u) || sort_frame_read(points, drift, head, 0u, &walk->frames[0]));
    if (headed && (written == 0))
    {
        fprintf(stderr, "  sort: %s: its .links header could not be written\n", sample);
    }
    else if (written && (ok == 0))
    {
        fprintf(stderr, "  sort: %s: frame 0 did not read, or a voxel lies outside the view\n", sample);
    }
    results->frames = (ok && (head[0] != 0u)) ? 1ull : 0ull;
    SortFrame *now = &walk->frames[0];
    SortFrame *next = &walk->frames[1];
    for (unsigned int frame = 0u; ok && ((frame + 1u) < head[0]); frame += 1u)
    {
        const int read_complete = sort_frame_read(points, drift, head, frame + 1u, next);
        ok = read_complete && sort_predict(head, now, next, still, results);
        if (read_complete == 0)
        {
            fprintf(stderr, "  sort: %s: frame %u did not read, or a voxel lies outside the view\n", sample,
                    frame + 1u);
        }
        else if (ok == 0)
        {
            fprintf(stderr, "  sort: %s: frames %u and %u: a prediction passes 32 bits\n", sample, frame, frame + 1u);
        }
        const SortPairRequest pair = {
            {weights[0], weights[1], weights[2]}, now->count, next->count, now->places, now->predictions, next->places,
            (still != 0u) ? now->stills : NULL};
        const long chosen = ok ? sort_link_pair(&pair, &walk->links) : SORT_ERROR;
        if (ok && (chosen == SORT_ERROR))
        {
            sort_error_print(sample, frame, &walk->links);
        }
        ok = ok && (chosen != SORT_ERROR) && sort_pair_write(links_file, walk, now, next);
        const int counted = (ok == 0) || (first == 0u) || sort_first_keep(walk);
        if (counted == 0)
        {
            fprintf(stderr, "  sort: %s: frames %u and %u: O7's count could not hold the gate\n", sample, frame,
                    frame + 1u);
        }
        ok = ok && counted;
        // each chosen link carries its motion, less the drift, to its target
        for (unsigned int at = 0u; ok && (at < walk->links.pairs); at += 1u)
        {
            if ((walk->links.flags[at] & SORT_GATE_CHOSEN) == 0u)
            {
                continue;
            }
            const unsigned int source = walk->links.source[at];
            const unsigned int target = walk->links.target[at];
            next->carried[target] = 1u;
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                next->motion[(ENGINE_AXES * (size_t)target) + axis] =
                    (long long)next->places[(ENGINE_AXES * (size_t)target) + axis] -
                    (long long)now->places[(ENGINE_AXES * (size_t)source) + axis] - (long long)next->lag[axis];
            }
        }
        results->frames += ok ? 1ull : 0ull;
        results->pairs += ok ? 1ull : 0ull;
        results->sources += ok ? now->count : 0ull;
        results->gate += ok ? walk->links.pairs : 0ull;
        results->components += ok ? walk->links.components : 0ull;
        results->chosen += ok ? walk->links.chosen : 0ull;
        results->kept += ok ? walk->links.kept : 0ull;
        results->level += ok ? walk->links.level : 0ull;
        results->crossed += ok ? walk->links.crossed : 0ull;
        results->gate_microseconds += walk->links.gate_microseconds;
        results->match_microseconds += walk->links.match_microseconds;
        SortFrame *const passed = now;
        now = next;
        next = passed;
    }
    const int ended = ok && sort_at_end(points) && sort_at_end(drift);
    if (ok && (ended == 0))
    {
        fprintf(stderr, "  sort: %s: its .points or .drift does not end at its last frame\n", sample);
    }
    if ((agree != 0) && (weighed != 0) && (sized != 0) && (ended == 0))
    {
        fprintf(stderr, "  sort: %s: the links stopped at frame %llu of %u\n", sample, results->frames, head[0]);
    }
    return ended;
}

static int sort_key_order(const void *one, const void *other)
{
    const unsigned long long left = *(const unsigned long long *)one;
    const unsigned long long right = *(const unsigned long long *)other;
    return (left < right) ? -1 : ((left > right) ? 1 : 0);
}

static int sort_count_find(const void *key, const void *entry)
{
    const unsigned long long length = *(const unsigned long long *)key;
    const unsigned long long there = ((const SortFirstCount *)entry)->length;
    return (length < there) ? -1 : ((length > there) ? 1 : 0);
}

// O7's count over the sample's kept keys, sorted: each distinct distance with its pairs and first-rank pairs, in
// ascending order, then pooled
static int sort_first_count(SortWalk *walk, SortResults *results)
{
    qsort(walk->keys, walk->key_count, sizeof(unsigned long long), sort_key_order);
    size_t distinct = 0u;
    for (size_t at = 0u; at < walk->key_count; at += 1u)
    {
        distinct += ((at == 0u) || ((walk->keys[at] >> 1u) != (walk->keys[at - 1u] >> 1u))) ? 1u : 0u;
    }
    if ((distinct > walk->count_capacity) || (walk->counts == NULL))
    {
        SortFirstCount *const grown = (SortFirstCount *)realloc(walk->counts, (distinct + 1u) * sizeof(SortFirstCount));
        if (grown == NULL)
        {
            return 0;
        }
        walk->counts = grown;
        walk->count_capacity = distinct;
    }
    walk->counted = 0u;
    for (size_t at = 0u; at < walk->key_count; at += 1u)
    {
        const unsigned long long length = walk->keys[at] >> 1u;
        if ((walk->counted == 0u) || (walk->counts[walk->counted - 1u].length != length))
        {
            SortFirstCount *const opened = &walk->counts[walk->counted];
            opened->length = length;
            opened->firsts = 0ull;
            opened->pairs = 0ull;
            opened->level = 0ull;
            walk->counted += 1u;
        }
        walk->counts[walk->counted - 1u].firsts += walk->keys[at] & 1ull;
        walk->counts[walk->counted - 1u].pairs += 1ull;
    }
    results->distinct = walk->counted;
    return sort_first_pool(walk->counts, walk->counted, &results->blocks, &results->levels);
}

// O7 on one frame pair of the written first pass, the .links at its pair record: each gate pair's cost becomes its
// distance's level, the pair is weighed, matched and its crossings counted again, and its pair record and gate records
// are rewritten in place. Its source records are passed over as they are
static int sort_first_pair(const char *sample, unsigned int frame, const unsigned int weights[ENGINE_AXES],
                           const SortFrame *now, const SortFrame *next, FILE *links_file, SortWalk *walk,
                           SortResults *results)
{
    SortLinks *const links = &walk->links;
    const long long start = SORT_TELL(links_file);
    unsigned int record[SORT_PAIR_WORDS];
    int ok = (start >= 0ll) && sort_read(links_file, record, sizeof(record)) && (record[0] == now->count) &&
             (record[1] == next->count);
    const unsigned int pairs = ok ? record[2] : 0u;
    const unsigned long long source_bytes = SORT_SOURCE_WORDS * (unsigned long long)now->count * sizeof(unsigned int);
    const size_t gate_words = SORT_GATE_WORDS * (size_t)pairs;
    ok = ok && sort_skip(links_file, source_bytes) && sort_links_reserve(links, pairs) &&
         sort_words_reserve(walk, gate_words) && sort_read(links_file, walk->words, gate_words * sizeof(unsigned int));
    for (unsigned int pair = 0u; ok && (pair < pairs); pair += 1u)
    {
        const unsigned int *const word = &walk->words[SORT_GATE_WORDS * (size_t)pair];
        // the cost as its low word, then its high
        const unsigned long long length = (unsigned long long)word[2] | ((unsigned long long)word[3] << 32u);
        const SortFirstCount *const found = (const SortFirstCount *)bsearch(&length, walk->counts, walk->counted,
                                                                            sizeof(SortFirstCount), sort_count_find);
        ok = found != NULL;
        links->source[pair] = word[0];
        links->target[pair] = word[1];
        links->cost[pair] = ok ? found->level : 0ull;
        links->flags[pair] = word[6] & ~SORT_GATE_CHOSEN;
    }
    links->pairs = ok ? pairs : 0u;
    const SortPairRequest request = {
        {weights[0], weights[1], weights[2]}, now->count, next->count, now->places, NULL, next->places, NULL};
    const long chosen = ok ? sort_link_again(&request, links) : SORT_ERROR;
    if (ok && (chosen == SORT_ERROR))
    {
        sort_error_print(sample, frame, links);
    }
    // the components are the gate's, which the costs do not change
    ok = ok && (chosen != SORT_ERROR) && (links->components == record[3]);
    const unsigned long long counted[3] = {links->kept, links->level, links->crossed};
    record[4] = links->chosen;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        // a 64-bit count as its low word, then its high
        record[5u + (2u * at)] = (unsigned int)(counted[at] & 0xFFFFFFFFull);
        record[6u + (2u * at)] = (unsigned int)(counted[at] >> 32u);
    }
    for (unsigned int pair = 0u; ok && (pair < pairs); pair += 1u)
    {
        unsigned int *const word = &walk->words[SORT_GATE_WORDS * (size_t)pair];
        results->changed += (((word[6] ^ links->flags[pair]) & SORT_GATE_CHOSEN) != 0u) ? 1ull : 0ull;
        // the cost as its low word, then its high
        word[2] = (unsigned int)(links->cost[pair] & 0xFFFFFFFFull);
        word[3] = (unsigned int)(links->cost[pair] >> 32u);
        word[4] = links->weight[pair];
        word[5] = links->component[pair];
        word[6] = links->flags[pair];
    }
    // a stream read and then written is placed between the two, and again before the next read
    ok = ok && (SORT_SEEK(links_file, start, SEEK_SET) == 0) && sort_write(links_file, record, sizeof(record)) &&
         sort_skip(links_file, source_bytes) &&
         sort_write(links_file, walk->words, gate_words * sizeof(unsigned int)) &&
         (SORT_SEEK(links_file, 0ll, SEEK_CUR) == 0);
    results->components += ok ? links->components : 0ull;
    results->chosen += ok ? links->chosen : 0ull;
    results->kept += ok ? links->kept : 0ull;
    results->level += ok ? links->level : 0ull;
    results->crossed += ok ? links->crossed : 0ull;
    results->match_microseconds += links->match_microseconds;
    return ok;
}

// O7's second pass over a sample whose first pass is written whole: the count, pooled, then each frame pair again from
// the .points' places and the .links' gates, its records rewritten in place. The predictions and the source records
// stay the first pass's, and the results' components, chosen links and crossings become the second pass's
static int sort_first(const char *sample, const unsigned int weights[ENGINE_AXES], FILE *points, FILE *drift,
                      FILE *links_file, SortWalk *walk, SortResults *results)
{
    if (sort_first_count(walk, results) == 0)
    {
        fprintf(stderr, "  sort: %s: O7's count of %llu gate pairs could not be reserved or did not pool\n", sample,
                (unsigned long long)walk->key_count);
        return 0;
    }
    unsigned int head[SORT_POINTS_HEADER_WORDS];
    unsigned int drift_head[SORT_DRIFT_HEADER_WORDS];
    // the first pass read both files whole and checked their heads; they are read again from their starts
    int ok = (SORT_SEEK(points, 0ll, SEEK_SET) == 0) && (SORT_SEEK(drift, 0ll, SEEK_SET) == 0) &&
             (SORT_SEEK(links_file, (long long)(SORT_HEADER_WORDS * sizeof(unsigned int)), SEEK_SET) == 0) &&
             sort_read(points, head, sizeof(head)) &&
             sort_skip(points, (1ull + SCAN_READINGS) * sizeof(unsigned long long)) &&
             sort_read(drift, drift_head, sizeof(drift_head)) &&
             ((head[0] == 0u) || sort_frame_read(points, drift, head, 0u, &walk->frames[0]));
    results->components = 0ull;
    results->chosen = 0ull;
    results->kept = 0ull;
    results->level = 0ull;
    results->crossed = 0ull;
    results->changed = 0ull;
    SortFrame *now = &walk->frames[0];
    SortFrame *next = &walk->frames[1];
    unsigned int frame = 0u;
    while (ok && ((frame + 1u) < head[0]))
    {
        ok = sort_frame_read(points, drift, head, frame + 1u, next) &&
             sort_first_pair(sample, frame, weights, now, next, links_file, walk, results);
        SortFrame *const passed = now;
        now = next;
        next = passed;
        frame += ok ? 1u : 0u;
    }
    ok = ok && sort_at_end(links_file);
    if (ok == 0)
    {
        fprintf(stderr, "  sort: %s: O7's second pass stopped at frame %u\n", sample, frame);
    }
    return ok;
}

static int sort_sample(const SortRequest *request, const char *sample, const unsigned int weights[ENGINE_AXES],
                       SortWalk *walk, SortResults *results)
{
    memset(results, 0, sizeof(*results));
    char points_path[ENGINE_PATH_CAPACITY];
    char drift_path[ENGINE_PATH_CAPACITY];
    char links_path[ENGINE_PATH_CAPACITY];
    FILE *const points = engine_sample_path(points_path, sizeof(points_path), request->set, sample, ".points")
                             ? fopen(points_path, "rb")
                             : NULL;
    FILE *const drift = engine_sample_path(drift_path, sizeof(drift_path), request->set, sample, ".drift")
                            ? fopen(drift_path, "rb")
                            : NULL;
    const int named = engine_sample_path(links_path, sizeof(links_path), request->set, sample, ".links");
    // opened for update: O7's second pass reads the written first pass back and rewrites it in place
    FILE *const links_file = ((points != NULL) && (drift != NULL) && named) ? fopen(links_path, "w+b") : NULL;
    if (links_file == NULL)
    {
        fprintf(stderr, "  sort: %s: its .points or .drift in %s did not open, or its .links could not be made\n",
                sample, request->set);
    }
    walk->key_count = 0u;
    const int ok =
        (links_file != NULL) &&
        sort_frames(sample, weights, request->still, request->first, points, drift, links_file, walk, results) &&
        ((request->first == 0u) || sort_first(sample, weights, points, drift, links_file, walk, results));
    const int closed = (links_file != NULL) && (fclose(links_file) == 0);
    if (points != NULL)
    {
        fclose(points);
    }
    if (drift != NULL)
    {
        fclose(drift);
    }
    // a sample that errors leaves no .links, not even one an earlier run wrote
    if (named && ((ok == 0) || (closed == 0)))
    {
        (void)remove(links_path);
    }
    return ok && closed;
}

extern "C" long sort_link_set(const SortRequest *request)
{
    if ((request == NULL) || (request->set == NULL) || (request->samples == NULL) || (request->count == 0u) ||
        (request->error == NULL))
    {
        return SORT_ERROR;
    }
    unsigned int weights[ENGINE_AXES];
    if (drift_weights(request->voxel_pm, weights) == 0)
    {
        fprintf(stderr,
                "  sort: voxel_pm %llu, %llu, %llu gives no weights: a size is zero, or a size over their"
                " greatest common divisor squares past 32 bits\n",
                request->voxel_pm[0], request->voxel_pm[1], request->voxel_pm[2]);
        return SORT_ERROR;
    }
    const unsigned int terms =
        SORT_TERMS | ((request->still != 0u) ? SORT_TERM_STILL : 0u) | ((request->first != 0u) ? SORT_TERM_FIRST : 0u);
    printf("  the sort's weights: %u, %u, %u, each the square of voxel_pm %llu, %llu, %llu over their greatest common"
           " divisor; the cost's terms %u: the weighted squared distance, %s%sand no shape term\n",
           weights[0], weights[1], weights[2], request->voxel_pm[0], request->voxel_pm[1], request->voxel_pm[2], terms,
           (request->still != 0u) ? "the still term, " : "", (request->first != 0u) ? "O7's first term, " : "");
    if (request->still != 0u)
    {
        printf("  the still term: the gate also takes each source's still place, its place carried by the lag alone,"
               " forward to its nearest targets, and a pair's cost is the lesser of its distances from the prediction"
               " and from the still place\n");
    }
    if (request->first != 0u)
    {
        printf("  O7's first term: once a sample's first pass is written, each gate pair's cost is its distance's level"
               " in the sample's share of first-rank pairs at that distance, pooled by pool-adjacent-violators until it"
               " never rises with the distance, the most first; each frame pair is weighed and matched again on those"
               " costs, its predictions the first pass's\n");
    }
    printf("  %-24s %6s %10s %s\n", "sample", "frames", "chosen",
           "gate pairs, components, sources; kept, level,"
           " crossed; outside, carried; gate us, match us");
    SortWalk walk;
    memset(&walk, 0, sizeof(walk));
    SortResults totals;
    memset(&totals, 0, sizeof(totals));
    unsigned int failed = 0u;
    for (unsigned int at = 0u; at < request->count; at += 1u)
    {
        SortResults results;
        const char *const sample = request->samples[at];
        if (sort_sample(request, sample, weights, &walk, &results) == 0)
        {
            fprintf(stderr, "  sort: %s failed\n", sample);
            failed += 1u;
            continue;
        }
        printf("  %-24s %6llu %10llu %llu, %llu, %llu; %llu, %llu, %llu; %llu, %llu; %llu, %llu\n", sample,
               results.frames, results.chosen, results.gate, results.components, results.sources, results.kept,
               results.level, results.crossed, results.outside, results.carried, results.gate_microseconds,
               results.match_microseconds);
        if (request->first != 0u)
        {
            printf("  %-24s O7: %llu distinct distances pooled into %llu blocks at %llu levels; %llu chosen flags"
                   " changed from the first pass\n",
                   sample, results.distinct, results.blocks, results.levels, results.changed);
        }
        totals.changed += results.changed;
        totals.frames += results.frames;
        totals.pairs += results.pairs;
        totals.sources += results.sources;
        totals.gate += results.gate;
        totals.components += results.components;
        totals.chosen += results.chosen;
        totals.kept += results.kept;
        totals.level += results.level;
        totals.crossed += results.crossed;
        totals.outside += results.outside;
        totals.carried += results.carried;
        totals.gate_microseconds += results.gate_microseconds;
        totals.match_microseconds += results.match_microseconds;
    }
    printf(
        "  sorted %u of %u samples: %llu frames, %llu frame pairs; %llu sources, %llu gate pairs, %llu components,"
        " %llu chosen; %llu kept, %llu level, %llu crossed; %llu outside, %llu carried; gate %llu us, match %llu us\n",
        request->count - failed, request->count, totals.frames, totals.pairs, totals.sources, totals.gate,
        totals.components, totals.chosen, totals.kept, totals.level, totals.crossed, totals.outside, totals.carried,
        totals.gate_microseconds, totals.match_microseconds);
    if (request->first != 0u)
    {
        printf("  O7 over the samples sorted: %llu chosen flags changed from the first pass\n", totals.changed);
    }
    sort_frame_free(&walk.frames[0]);
    sort_frame_free(&walk.frames[1]);
    sort_links_release(&walk.links);
    free(walk.words);
    free(walk.keys);
    free(walk.counts);
    sort_release();
    return (failed == 0u) ? 0L : SORT_ERROR;
}
