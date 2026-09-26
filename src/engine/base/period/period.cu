// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "period.h"

#include "device_pool.h"
#include "scriptura.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define PERIOD_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_PERIOD, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define PERIOD_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_PERIOD, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define PERIOD_THREADS 256u

#define PERIOD_VALUES 65536u

#define PERIOD_GRID_ROWS_MOST 65535u

#define PERIOD_VOXELS_MOST 0xFFFFFFFFull

#define PERIOD_LOW_HALF 0xFFFFFFFFull

#define PERIOD_ROUNDS 4u

#define PERIOD_SEED_WORDS 4u

#define PERIOD_ROW_TEXT 576ull

static_assert((PERIOD_SEED_WORDS * 8u) == ENGINE_SIGNUM_BYTES, "period: the seed words must cover the content signum");

typedef struct
{
    unsigned int rank;
    unsigned int extent[ENGINE_ARRAY_RANK];
    unsigned int stride[ENGINE_ARRAY_RANK];
    unsigned int usable[ENGINE_ARRAY_RANK];
    unsigned int pairs[ENGINE_ARRAY_RANK];
    unsigned long long first[ENGINE_ARRAY_RANK];
    unsigned long long lag_total;
    unsigned long long voxels;
} PeriodLattice;

typedef struct
{
    unsigned int keys[PERIOD_ROUNDS];
} PeriodShuffle;

typedef struct
{
    unsigned long long candidate;
    unsigned long long at;
    unsigned long long beside;
    unsigned long long doubled;
    unsigned long long beside_double;
    unsigned long long height;
} PeriodPeak;

typedef struct
{
    unsigned long long high;
    unsigned long long low;
} PeriodWide;

typedef struct
{
    const unsigned short *lanes;
    unsigned long long voxels;
    unsigned int columns;
    unsigned int *device_histogram;
    unsigned long long *device_agreement;
    unsigned int *histogram;
    unsigned long long *agreement;
    size_t held_entries;
} PeriodPass;

// the histogram, the agreement and the shuffled lanes are slices of one pool, kept after the call and held for the
// most voxels and the most agreement entries asked so far
typedef struct
{
    DevicePool pool;
    unsigned int *histogram;
    unsigned long long *agreement;
    unsigned short *shuffled;
    unsigned long long voxels;
    unsigned long long entries;
} PeriodHeld;

static PeriodHeld s_period_held;

#define PERIOD_SLICES 3u

__global__ static void period_histogram_kernel(const unsigned short *lanes, unsigned long long voxels,
                                               unsigned int *histogram)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        atomicAdd(&histogram[lanes[voxel]], 1u);
    }
}

__global__ static void period_agreement_kernel(const unsigned short *lanes, PeriodLattice lattice,
                                               unsigned long long *agreement)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long entry = blockIdx.y; entry < lattice.lag_total; entry += gridDim.y)
    {
        unsigned int axis = 0u;
        while (((axis + 1u) < lattice.rank) && (entry >= lattice.first[axis + 1u]))
        {
            axis += 1u;
        }
        // entry - first counts this axis's lags, below its extent, so it narrows to 32 bits exactly
        const unsigned int lag = (unsigned int)(entry - lattice.first[axis]) + 1u;
        const unsigned int stride = lattice.stride[axis];
        const unsigned int usable = lattice.usable[axis];
        const unsigned int extent = lattice.extent[axis];
        const unsigned int reach = lag * stride;
        unsigned int same = 0u;
        for (unsigned long long position = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
             position < lattice.pairs[axis]; position += jump)
        {
            // position is below this axis's pairs, a 32 bit count, so it narrows exactly
            const unsigned int place = (unsigned int)position;
            const unsigned int inner = place % stride;
            const unsigned int rest = place / stride;
            const unsigned int along = rest % usable;
            const unsigned int outer = rest / usable;
            const unsigned int voxel = (((outer * extent) + along) * stride) + inner;
            same += (lanes[voxel] == lanes[voxel + reach]) ? 1u : 0u;
        }
        for (unsigned int offset = 16u; offset > 0u; offset >>= 1u)
        {
            same += __shfl_down_sync(0xFFFFFFFFu, same, offset);
        }
        if (((threadIdx.x & 31u) == 0u) && (same != 0u))
        {
            atomicAdd(&agreement[entry], (unsigned long long)same);
        }
    }
}

__device__ static unsigned int period_round(unsigned int half, unsigned int key)
{
    unsigned int mixed = (half ^ key) * 0x9E3779B1u;
    mixed ^= mixed >> 15u;
    mixed *= 0x85EBCA77u;
    mixed ^= mixed >> 13u;
    return mixed;
}

__device__ static unsigned int period_line_random(const PeriodShuffle &shuffle, unsigned long long line,
                                                  unsigned int step)
{
    // the line index narrows to two 32-bit halves, each mixed into the hash separately
    unsigned int hash = period_round((unsigned int)line ^ shuffle.keys[0], shuffle.keys[1]);
    hash = period_round(hash ^ (unsigned int)(line >> 32u), shuffle.keys[2]);
    hash = period_round(hash ^ step, shuffle.keys[3]);
    return hash;
}

// The null for one axis: each line along that axis is permuted alone, so the axis loses its own
// coherence while every other axis keeps its structure and each line keeps its values. A global
// shuffle instead destroys every axis at once, which drops the agreement level and reads a period
// on an axis that carries none whenever another axis is structured (A12).
__global__ static void period_line_shuffle_kernel(unsigned short *shuffled, PeriodShuffle shuffle,
                                                  PeriodLattice lattice, unsigned int axis, unsigned long long lines)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    const unsigned int stride = lattice.stride[axis];
    const unsigned int extent = lattice.extent[axis];
    for (unsigned long long line = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; line < lines;
         line += jump)
    {
        const unsigned int inner = (unsigned int)(line % stride);
        const unsigned long long outer = line / stride;
        const unsigned long long base = ((outer * extent) * stride) + inner;
        for (unsigned int step = (extent >= 1u) ? (extent - 1u) : 0u; step >= 1u; step -= 1u)
        {
            const unsigned int other = period_line_random(shuffle, line, step) % (step + 1u);
            const unsigned long long here = base + ((unsigned long long)step * stride);
            const unsigned long long there = base + ((unsigned long long)other * stride);
            const unsigned short held = shuffled[here];
            shuffled[here] = shuffled[there];
            shuffled[there] = held;
        }
    }
}

static PeriodWide period_wide_product(unsigned long long left, unsigned long long right)
{
    const unsigned long long left_low = left & PERIOD_LOW_HALF;
    const unsigned long long left_high = left >> 32u;
    const unsigned long long right_low = right & PERIOD_LOW_HALF;
    const unsigned long long right_high = right >> 32u;
    const unsigned long long low_low = left_low * right_low;
    const unsigned long long high_low = left_high * right_low;
    const unsigned long long low_high = left_low * right_high;
    const unsigned long long middle = (low_low >> 32u) + (high_low & PERIOD_LOW_HALF) + (low_high & PERIOD_LOW_HALF);
    PeriodWide product;
    product.low = (middle << 32u) | (low_low & PERIOD_LOW_HALF);
    product.high = (left_high * right_high) + (high_low >> 32u) + (low_high >> 32u) + (middle >> 32u);
    return product;
}

static int period_wide_order(PeriodWide one, PeriodWide other)
{
    if (one.high != other.high)
    {
        return (one.high > other.high) ? 1 : -1;
    }
    if (one.low != other.low)
    {
        return (one.low > other.low) ? 1 : -1;
    }
    return 0;
}

static int period_margin_order(const PeriodMargin *one, const PeriodMargin *other)
{
    return period_wide_order(period_wide_product(one->numerator, other->denominator),
                             period_wide_product(other->numerator, one->denominator));
}

static int period_margin_compare(const void *one, const void *other)
{
    return period_margin_order((const PeriodMargin *)one, (const PeriodMargin *)other);
}

static unsigned long long period_mix(unsigned long long word)
{
    unsigned long long mixed = word + 0x9E3779B97F4A7C15ull;
    mixed = (mixed ^ (mixed >> 30u)) * 0xBF58476D1CE4E5B9ull;
    mixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return mixed ^ (mixed >> 31u);
}

static void period_shuffle_fill(PeriodShuffle *shuffle, const EngineSignum *content, unsigned long long counter)
{
    unsigned long long words[PERIOD_SEED_WORDS];
    for (unsigned int word = 0u; word < PERIOD_SEED_WORDS; word += 1u)
    {
        unsigned long long held = 0ull;
        for (unsigned int byte = 0u; byte < 8u; byte += 1u)
        {
            held |= (unsigned long long)content->bytes[(word * 8u) + byte] << (8u * byte);
        }
        words[word] = held;
    }
    for (unsigned int round = 0u; round < PERIOD_ROUNDS; round += 1u)
    {
        const unsigned long long mixed = period_mix(words[round % PERIOD_SEED_WORDS]
                                                    ^ period_mix((counter * PERIOD_ROUNDS) + round));
        // the key is the low 32 bits of the mixed word
        shuffle->keys[round] = (unsigned int)(mixed & PERIOD_LOW_HALF);
    }
}

static unsigned long long period_beside(const unsigned long long *same, unsigned long long lag)
{
    const unsigned long long before = same[lag - 2ull];
    const unsigned long long after = same[lag];
    return (before > after) ? before : after;
}

static int period_peak(const unsigned long long *same, unsigned long long candidate, PeriodPeak *peak)
{
    const unsigned long long at = same[candidate - 1ull];
    const unsigned long long beside = period_beside(same, candidate);
    const unsigned long long doubled = same[(2ull * candidate) - 1ull];
    const unsigned long long beside_double = period_beside(same, 2ull * candidate);
    if ((at <= beside) || (doubled <= beside_double))
    {
        return 0;
    }
    const unsigned long long rise = at - beside;
    const unsigned long long rise_double = doubled - beside_double;
    peak->candidate = candidate;
    peak->at = at;
    peak->beside = beside;
    peak->doubled = doubled;
    peak->beside_double = beside_double;
    peak->height = (rise < rise_double) ? rise : rise_double;
    return 1;
}

static void period_axis_set(PeriodAxis *axis, const PeriodPeak *peak)
{
    axis->candidate = peak->candidate;
    axis->agreement_at_candidate = peak->at;
    axis->agreement_beside_candidate = peak->beside;
    axis->agreement_at_double = peak->doubled;
    axis->agreement_beside_double = peak->beside_double;
    axis->margin.numerator = peak->height;
    axis->margin.denominator = axis->pairs_per_lag;
}

// The strongest peak (the largest height, the smallest period on a tie): the display candidate when
// no peak clears the null band.
static void period_strongest(const unsigned long long *same, PeriodAxis *axis)
{
    const unsigned long long lags = axis->lags;
    for (unsigned long long candidate = 2ull; ((2ull * candidate) + 1ull) <= lags; candidate += 1ull)
    {
        PeriodPeak peak;
        if ((period_peak(same, candidate, &peak) != 0) && ((axis->candidate == 0ull) || (peak.height > axis->margin.numerator)))
        {
            period_axis_set(axis, &peak);
        }
    }
}

// The fundamental: the smallest candidate whose peak clears the null band top. It answers both the
// harmonic (a period P also peaks at 2P, 3P, whose heights match P's, so the strongest rule picked a
// multiple) and, with the per-axis null, the axis that carries no period (A12).
static int period_fundamental(const unsigned long long *same, const PeriodMargin *top, PeriodAxis *axis)
{
    const unsigned long long lags = axis->lags;
    for (unsigned long long candidate = 2ull; ((2ull * candidate) + 1ull) <= lags; candidate += 1ull)
    {
        PeriodPeak peak;
        if (period_peak(same, candidate, &peak) == 0)
        {
            continue;
        }
        const PeriodMargin here = {peak.height, axis->pairs_per_lag};
        if (period_margin_order(&here, top) > 0)
        {
            period_axis_set(axis, &peak);
            return 1;
        }
    }
    return 0;
}

extern "C" unsigned long long period_agreement_entries(unsigned int rank, const unsigned long long *shape)
{
    unsigned long long entries = 0ull;
    for (unsigned int axis = 0u; (shape != NULL) && (axis < rank) && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        entries += shape[axis] / 2ull;
    }
    return entries;
}

// the pool's slices for `voxels` and `entries`, in the order they are laid and taken: the histogram, the agreement and
// the shuffled lanes; the plan is laid from them, and a pool held from it takes them
static DevicePoolPlan period_plan(unsigned long long voxels, unsigned long long entries, EngineError *error,
                                  DevicePoolTakeRequest takes[PERIOD_SLICES])
{
    PeriodHeld *const held = &s_period_held;
    const DevicePoolTakeRequest laid[PERIOD_SLICES] = {
        {&held->pool, PERIOD_VALUES * sizeof(unsigned int), (void **)&held->histogram, error},
        {&held->pool, entries * sizeof(unsigned long long), (void **)&held->agreement, error},
        {&held->pool, voxels * sizeof(unsigned short), (void **)&held->shuffled, error}};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < PERIOD_SLICES; at += 1u)
    {
        takes[at] = laid[at];
        device_pool_plan_slice(&plan, laid[at].bytes);
    }
    return plan;
}

// the pool grown to hold `voxels` and `entries`. A pool that already holds both is kept as it is, and a grown pool
// holds the most of each asked so far: shapes that take turns grow it once.
static int period_hold(unsigned long long voxels, unsigned long long entries, EngineError *error)
{
    PeriodHeld *const held = &s_period_held;
    if ((voxels <= held->voxels) && (entries <= held->entries))
    {
        return 1;
    }
    const unsigned long long most_voxels = (voxels > held->voxels) ? voxels : held->voxels;
    const unsigned long long most_entries = (entries > held->entries) ? entries : held->entries;
    device_pool_release(&held->pool);
    held->histogram = NULL;
    held->agreement = NULL;
    held->shuffled = NULL;
    held->voxels = 0ull;
    held->entries = 0ull;
    DevicePoolTakeRequest takes[PERIOD_SLICES];
    const DevicePoolPlan plan = period_plan(most_voxels, most_entries, error, takes);
    const DevicePoolHoldRequest hold = {&plan, &held->pool, error};
    int ok = device_pool_hold(&hold) == 0L;
    // the slices are taken in the plan's order, and each lands where the plan laid it with none refused
    for (unsigned int at = 0u; (ok != 0) && (at < PERIOD_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    held->voxels = (ok != 0) ? most_voxels : 0ull;
    held->entries = (ok != 0) ? most_entries : 0ull;
    return ok;
}

extern "C" unsigned long long period_hold_bytes(unsigned long long voxels, unsigned long long entries)
{
    if ((voxels == 0ull) || (voxels > PERIOD_VOXELS_MOST))
    {
        return 0ull;
    }
    DevicePoolTakeRequest takes[PERIOD_SLICES];
    // the agreement's slice holds one entry at the least, as the calls hold it
    const DevicePoolPlan plan = period_plan(voxels, (entries != 0ull) ? entries : 1ull, NULL, takes);
    return device_pool_plan_bytes(&plan);
}

static int period_lattice_fill(const PeriodRequest *request, PeriodLattice *lattice, unsigned long long *voxels)
{
    EngineError *const error = request->error;
    const unsigned int rank = request->rank;
    if (!PERIOD_HELD((rank >= 1u) && (rank <= ENGINE_ARRAY_RANK), &request->rank, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned long long count = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned long long extent = request->shape[axis];
        if (!PERIOD_HELD((extent >= 1ull) && (extent <= (PERIOD_VOXELS_MOST / count)), &request->shape[axis], error,
                         ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        count *= extent;
    }
    memset(lattice, 0, sizeof(*lattice));
    lattice->rank = rank;
    unsigned long long stride = 1ull;
    for (unsigned int axis = rank; axis > 0u; axis -= 1u)
    {
        const unsigned long long extent = request->shape[axis - 1u];
        const unsigned long long lags = extent / 2ull;
        // every count here is at most the voxel count, which was held below 2^32, so each narrows exactly
        lattice->extent[axis - 1u] = (unsigned int)extent;
        lattice->stride[axis - 1u] = (unsigned int)stride;
        lattice->usable[axis - 1u] = (unsigned int)(extent - lags);
        lattice->pairs[axis - 1u] = (unsigned int)((extent - lags) * (count / extent));
        stride *= extent;
    }
    unsigned long long first = 0ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        lattice->first[axis] = first;
        first += request->shape[axis] / 2ull;
    }
    lattice->lag_total = first;
    lattice->voxels = count;
    *voxels = count;
    return 1;
}

static unsigned int period_grid_columns(const PeriodLattice *lattice, EngineError *error)
{
    int device = 0;
    int processors = 0;
    int threads_each = 0;
    const int read = PERIOD_TOOK(cudaGetDevice(&device), &device, error)
                  && PERIOD_TOOK(cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device),
                                 &processors, error)
                  && PERIOD_TOOK(cudaDeviceGetAttribute(&threads_each, cudaDevAttrMaxThreadsPerMultiProcessor, device),
                                 &threads_each, error);
    if (read == 0)
    {
        return 0u;
    }
    // both attributes are positive counts the runtime reports, so they re-sign to unsigned exactly
    const unsigned long long resident = (unsigned long long)processors * ((unsigned long long)threads_each / PERIOD_THREADS);
    unsigned long long widest = 0ull;
    for (unsigned int axis = 0u; axis < lattice->rank; axis += 1u)
    {
        widest = (lattice->pairs[axis] > widest) ? lattice->pairs[axis] : widest;
    }
    const unsigned long long needed = (widest + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
    const unsigned long long columns = (needed < resident) ? needed : resident;
    // columns is at most the resident block count, far below 2^32
    return (unsigned int)((columns != 0ull) ? columns : 1ull);
}

static int period_count(const PeriodPass *pass, const PeriodLattice *lattice, int with_agreement, EngineError *error)
{
    int good = PERIOD_TOOK(cudaMemset(pass->device_histogram, 0, PERIOD_VALUES * sizeof(unsigned int)),
                           pass->device_histogram, error)
            && PERIOD_TOOK(cudaMemset(pass->device_agreement, 0, pass->held_entries * sizeof(unsigned long long)),
                           pass->device_agreement, error);
    if (good != 0)
    {
        const unsigned long long needed = (pass->voxels + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
        // the block count is held below the resident count, far below 2^32
        const unsigned int blocks = (unsigned int)((needed < (unsigned long long)pass->columns) ? needed : pass->columns);
        period_histogram_kernel<<<blocks, PERIOD_THREADS>>>(pass->lanes, pass->voxels, pass->device_histogram);
        good = PERIOD_TOOK(cudaGetLastError(), pass->device_histogram, error);
    }
    if ((good != 0) && (with_agreement != 0) && (lattice->lag_total != 0ull))
    {
        // the row count is held at or below the grid's row limit
        const unsigned int rows = (unsigned int)((lattice->lag_total < PERIOD_GRID_ROWS_MOST) ? lattice->lag_total
                                                                                             : PERIOD_GRID_ROWS_MOST);
        const dim3 grid(pass->columns, rows, 1u);
        period_agreement_kernel<<<grid, PERIOD_THREADS>>>(pass->lanes, *lattice, pass->device_agreement);
        good = PERIOD_TOOK(cudaGetLastError(), pass->device_agreement, error);
    }
    return good
        && PERIOD_TOOK(cudaMemcpy(pass->histogram, pass->device_histogram, PERIOD_VALUES * sizeof(unsigned int),
                                  cudaMemcpyDeviceToHost),
                       pass->histogram, error)
        && PERIOD_TOOK(cudaMemcpy(pass->agreement, pass->device_agreement,
                                  pass->held_entries * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                       pass->agreement, error);
}

static int period_request_held(const PeriodRequest *request, unsigned long long entries)
{
    EngineError *const error = request->error;
    const unsigned long long band_needed = request->draws * request->rank;
    const int drawn = (request->null_top == NULL)
                    ? ((request->draws >= 1ull) && (request->draws <= (PERIOD_VOXELS_MOST / ENGINE_ARRAY_RANK)))
                    : (request->draws == 0ull);
    return PERIOD_HELD(drawn, &request->draws, error, ENGINE_ERROR_REQUEST)
        && PERIOD_HELD((request->agreement == NULL) || (request->agreement_room >= entries), &request->agreement_room,
                       error, ENGINE_ERROR_REQUEST)
        && PERIOD_HELD((request->band == NULL) || (request->band_room >= band_needed), &request->band_room, error,
                       ENGINE_ERROR_REQUEST);
}

static void period_axis_open(const PeriodLattice *lattice, unsigned int axis, PeriodAxis *held)
{
    memset(held, 0, sizeof(*held));
    held->extent = lattice->extent[axis];
    held->lags = lattice->extent[axis] / 2u;
    held->pairs_per_lag = lattice->pairs[axis];
}

// The one axis's null: shuffle each line along the axis, count agreement, and read the strongest peak
// the shuffle reaches. That best height is one draw of the band.
static int period_null_axis(const PeriodRequest *request, const PeriodLattice *lattice, unsigned long long counter,
                            unsigned int axis, unsigned short *device_shuffled, const PeriodPass *shuffled_pass,
                            const unsigned int *histogram, PeriodMargin *height, EngineError *error)
{
    PeriodShuffle shuffle;
    period_shuffle_fill(&shuffle, &request->content, counter);
    if (!PERIOD_TOOK(cudaMemcpy(device_shuffled, request->device_lanes,
                                (size_t)lattice->voxels * sizeof(unsigned short), cudaMemcpyDeviceToDevice),
                     device_shuffled, error))
    {
        return 0;
    }
    const unsigned long long lines = lattice->voxels / lattice->extent[axis];
    const unsigned long long needed = (lines + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
    // the block count is held below the resident count, far below 2^32
    const unsigned int blocks = (unsigned int)((needed < (unsigned long long)shuffled_pass->columns)
                                               ? needed : shuffled_pass->columns);
    period_line_shuffle_kernel<<<blocks, PERIOD_THREADS>>>(device_shuffled, shuffle, *lattice, axis, lines);
    int good = PERIOD_TOOK(cudaGetLastError(), device_shuffled, error)
            && period_count(shuffled_pass, lattice, 1, error)
            && PERIOD_HELD(memcmp(histogram, shuffled_pass->histogram, PERIOD_VALUES * sizeof(unsigned int)) == 0,
                           shuffled_pass->histogram, error, ENGINE_ERROR_LOGIC);
    if (good != 0)
    {
        PeriodAxis drawn;
        period_axis_open(lattice, axis, &drawn);
        period_strongest(&shuffled_pass->agreement[lattice->first[axis]], &drawn);
        height->numerator = (drawn.candidate != 0ull) ? drawn.margin.numerator : 0ull;
        height->denominator = drawn.pairs_per_lag;
    }
    return good;
}

// The period is the smallest candidate whose height clears the band top. An empty band, or a given
// top of zero, lets any peak through, so the smallest peak wins; when nothing clears, the period is
// zero and the display candidate is the strongest peak.
static void period_select(const unsigned long long *same, const PeriodLattice *lattice, unsigned int axis,
                          PeriodMargin *band, unsigned long long count, const PeriodMargin *given_top, PeriodAxis *held)
{
    period_axis_open(lattice, axis, held);
    qsort(band, (size_t)count, sizeof(PeriodMargin), period_margin_compare);
    held->band_count = count;
    PeriodMargin top = {0ull, held->pairs_per_lag};
    if (count != 0ull)
    {
        held->band_bottom = band[0];
        held->band_top = band[count - 1ull];
        top = band[count - 1ull];
    }
    if (given_top != NULL)
    {
        held->band_bottom = *given_top;
        held->band_top = *given_top;
        top = *given_top;
    }
    if (period_fundamental(same, &top, held) != 0)
    {
        held->period = held->candidate;
    }
    else
    {
        period_strongest(same, held);
        held->period = 0ull;
    }
}

extern "C" long period_read(const PeriodRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return PERIOD_REFUSED;
    }
    EngineError *const error = request->error;
    if (!PERIOD_HELD((request->device_lanes != NULL) && (request->reading != NULL), request, error,
                     ENGINE_ERROR_REQUEST))
    {
        return PERIOD_REFUSED;
    }
    PeriodLattice lattice;
    unsigned long long voxels = 0ull;
    if (period_lattice_fill(request, &lattice, &voxels) == 0)
    {
        return PERIOD_REFUSED;
    }
    const unsigned long long entries = lattice.lag_total;
    if (period_request_held(request, entries) == 0)
    {
        return PERIOD_REFUSED;
    }
    const unsigned int columns = period_grid_columns(&lattice, error);
    if (columns == 0u)
    {
        return PERIOD_REFUSED;
    }
    const unsigned long long draws = request->draws;
    const size_t held_entries = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned int *const histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned int *const shuffled_histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned long long *const agreement = (unsigned long long *)calloc(held_entries, sizeof(unsigned long long));
    unsigned long long *const shuffled_agreement = (unsigned long long *)calloc(held_entries, sizeof(unsigned long long));
    const size_t held_bands = (size_t)((draws != 0ull) ? (draws * lattice.rank) : 1ull);
    PeriodMargin *const bands = (PeriodMargin *)calloc(held_bands, sizeof(PeriodMargin));
    unsigned long long band_counts[ENGINE_ARRAY_RANK] = {0ull};
    int good = PERIOD_HELD((histogram != NULL) && (shuffled_histogram != NULL) && (agreement != NULL)
                               && (shuffled_agreement != NULL) && (bands != NULL),
                           request, error, ENGINE_ERROR_RESOURCE)
            && period_hold(voxels, held_entries, error);
    const PeriodHeld *const held = &s_period_held;
    PeriodPass pass = {request->device_lanes, voxels, columns, held->histogram, held->agreement, histogram, agreement,
                       held_entries};
    good = good && period_count(&pass, &lattice, 1, error);
    unsigned long long collisions = 0ull;
    if (good != 0)
    {
        unsigned long long counted = 0ull;
        for (unsigned int value = 0u; value < PERIOD_VALUES; value += 1u)
        {
            counted += histogram[value];
            collisions += (unsigned long long)histogram[value] * histogram[value];
        }
        good = PERIOD_HELD(counted == voxels, histogram, error, ENGINE_ERROR_LOGIC);
    }
    PeriodReading *const reading = request->reading;
    memset(reading, 0, sizeof(*reading));
    reading->rank = lattice.rank;
    reading->voxels = voxels;
    reading->collisions = collisions;
    reading->draws = draws;
    PeriodPass shuffled_pass = {held->shuffled, voxels, columns, held->histogram, held->agreement, shuffled_histogram,
                                shuffled_agreement, held_entries};
    for (unsigned long long draw = 0ull; (good != 0) && (voxels >= 2ull) && (draw < draws); draw += 1ull)
    {
        for (unsigned int axis = 0u; (good != 0) && (axis < lattice.rank); axis += 1u)
        {
            PeriodMargin height;
            good = period_null_axis(request, &lattice, (draw * lattice.rank) + axis, axis, held->shuffled,
                                    &shuffled_pass, histogram, &height, error);
            if ((good != 0) && (height.numerator != 0ull))
            {
                bands[(axis * draws) + band_counts[axis]] = height;
                band_counts[axis] += 1ull;
            }
        }
    }
    for (unsigned int axis = 0u; (good != 0) && (axis < lattice.rank); axis += 1u)
    {
        period_select(&agreement[lattice.first[axis]], &lattice, axis, &bands[axis * draws], band_counts[axis],
                      (request->null_top != NULL) ? &request->null_top[axis] : NULL, &reading->axis[axis]);
    }
    if ((good != 0) && (request->agreement != NULL) && (entries != 0ull))
    {
        memcpy(request->agreement, agreement, (size_t)entries * sizeof(unsigned long long));
    }
    if ((good != 0) && (request->band != NULL))
    {
        memcpy(request->band, bands, (size_t)(draws * lattice.rank) * sizeof(PeriodMargin));
    }
    free(histogram);
    free(shuffled_histogram);
    free(agreement);
    free(shuffled_agreement);
    free(bands);
    return (good != 0) ? 0L : PERIOD_REFUSED;
}

extern "C" long period_draw(const PeriodRequest *request, unsigned long long draw, PeriodMargin *heights)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return PERIOD_REFUSED;
    }
    EngineError *const error = request->error;
    if (!PERIOD_HELD((request->device_lanes != NULL) && (heights != NULL), request, error, ENGINE_ERROR_REQUEST))
    {
        return PERIOD_REFUSED;
    }
    PeriodLattice lattice;
    unsigned long long voxels = 0ull;
    if (period_lattice_fill(request, &lattice, &voxels) == 0)
    {
        return PERIOD_REFUSED;
    }
    const unsigned int columns = period_grid_columns(&lattice, error);
    if (columns == 0u)
    {
        return PERIOD_REFUSED;
    }
    const unsigned long long entries = lattice.lag_total;
    const size_t held_entries = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned int *const histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned int *const shuffled_histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned long long *const shuffled_agreement = (unsigned long long *)calloc(held_entries, sizeof(unsigned long long));
    int good = PERIOD_HELD((histogram != NULL) && (shuffled_histogram != NULL) && (shuffled_agreement != NULL), request,
                           error, ENGINE_ERROR_RESOURCE)
            && period_hold(voxels, held_entries, error);
    const PeriodHeld *const held = &s_period_held;
    PeriodPass pass = {request->device_lanes, voxels, columns, held->histogram, held->agreement, histogram,
                       shuffled_agreement, held_entries};
    PeriodPass shuffled_pass = {held->shuffled, voxels, columns, held->histogram, held->agreement, shuffled_histogram,
                                shuffled_agreement, held_entries};
    good = good && period_count(&pass, &lattice, 0, error);
    for (unsigned int axis = 0u; (good != 0) && (axis < lattice.rank); axis += 1u)
    {
        PeriodAxis open;
        period_axis_open(&lattice, axis, &open);
        heights[axis].numerator = 0ull;
        heights[axis].denominator = open.pairs_per_lag;
        if (voxels >= 2ull)
        {
            good = period_null_axis(request, &lattice, (draw * lattice.rank) + axis, axis, held->shuffled,
                                    &shuffled_pass, histogram, &heights[axis], error);
        }
    }
    free(histogram);
    free(shuffled_histogram);
    free(shuffled_agreement);
    return (good != 0) ? 0L : PERIOD_REFUSED;
}

static void period_margin_text(ScripturaLine *line, const PeriodMargin *margin)
{
    scriptura_decimal(line, margin->numerator, 1u);
    scriptura_character(line, '/');
    scriptura_decimal(line, margin->denominator, 1u);
}

extern "C" int period_print(const PeriodReading *reading, FILE *file)
{
    if ((reading == NULL) || (file == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.room = PERIOD_ROW_TEXT * ((unsigned long long)reading->rank + 1ull);
    line.out = (char *)malloc((size_t)line.room);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    scriptura_text(&line, "  period over ");
    scriptura_decimal(&line, reading->voxels, 1u);
    scriptura_text(&line, " voxels, ");
    scriptura_decimal(&line, reading->collisions, 1u);
    scriptura_text(&line, " colliding pairs, a null band of ");
    scriptura_decimal(&line, reading->draws, 1u);
    scriptura_text(&line, " shuffles\n");
    for (unsigned int axis = 0u; axis < reading->rank; axis += 1u)
    {
        const PeriodAxis *const held = &reading->axis[axis];
        scriptura_text(&line, "    axis ");
        scriptura_decimal(&line, axis, 1u);
        scriptura_text(&line, ": extent ");
        scriptura_decimal(&line, held->extent, 1u);
        scriptura_text(&line, ", lags 1 to ");
        scriptura_decimal(&line, held->lags, 1u);
        scriptura_text(&line, " over ");
        scriptura_decimal(&line, held->pairs_per_lag, 1u);
        scriptura_text(&line, " pairs each; period ");
        scriptura_decimal(&line, held->period, 1u);
        scriptura_text(&line, " (candidate ");
        scriptura_decimal(&line, held->candidate, 1u);
        scriptura_text(&line, ", agreeing ");
        scriptura_decimal(&line, held->agreement_at_candidate, 1u);
        scriptura_text(&line, " against ");
        scriptura_decimal(&line, held->agreement_beside_candidate, 1u);
        scriptura_text(&line, " beside it, ");
        scriptura_decimal(&line, held->agreement_at_double, 1u);
        scriptura_text(&line, " against ");
        scriptura_decimal(&line, held->agreement_beside_double, 1u);
        scriptura_text(&line, " beside twice it; height ");
        period_margin_text(&line, &held->margin);
        scriptura_text(&line, "; ");
        scriptura_decimal(&line, held->band_count, 1u);
        scriptura_text(&line, " shuffles reached a peak");
        if (held->band_count != 0ull)
        {
            scriptura_text(&line, ", from ");
            period_margin_text(&line, &held->band_bottom);
            scriptura_text(&line, " to ");
            period_margin_text(&line, &held->band_top);
        }
        scriptura_text(&line, ")\n");
    }
    const int written = scriptura_write(&line, file);
    free(line.out);
    return written;
}
