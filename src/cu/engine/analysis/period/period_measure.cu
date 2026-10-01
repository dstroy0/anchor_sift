// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// period_measure.cu: the histogram and agreement kernels and the fundamental
#include "period_internal.h"

PeriodResident g_period_resident;

__global__ void period_histogram_kernel(const unsigned short *lanes, unsigned long long voxels, unsigned int *histogram)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        atomicAdd(&histogram[lanes[voxel]], 1u);
    }
}

__global__ void period_agreement_kernel(const unsigned short *lanes, PeriodLattice lattice,
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
        // entry - first counts this axis's lags, below its extent. It narrows to 32 bits exactly
        const unsigned int lag = (unsigned int)(entry - lattice.first[axis]) + 1u;
        const unsigned int stride = lattice.stride[axis];
        const unsigned int usable = lattice.usable[axis];
        const unsigned int extent = lattice.extent[axis];
        const unsigned int range = lag * stride;
        unsigned int same = 0u;
        for (unsigned long long position = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
             position < lattice.pairs[axis]; position += jump)
        {
            // position is below this axis's pairs, a 32 bit count. It narrows exactly
            const unsigned int place = (unsigned int)position;
            const unsigned int inner = place % stride;
            const unsigned int rest = place / stride;
            const unsigned int along = rest % usable;
            const unsigned int outer = rest / usable;
            const unsigned int voxel = (((outer * extent) + along) * stride) + inner;
            same += (lanes[voxel] == lanes[voxel + range]) ? 1u : 0u;
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

// The null for one axis: each line along that axis is permuted alone. The axis loses its own
// coherence while every other axis keeps its structure and each line keeps its values. A global
// shuffle instead destroys every axis at once, which drops the agreement level and reads a period
// on an axis that carries none whenever another axis is structured (A12).
__global__ void period_line_shuffle_kernel(unsigned short *shuffled, PeriodShuffle shuffle, PeriodLattice lattice,
                                           unsigned int axis, unsigned long long lines)
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
            const unsigned short temporary = shuffled[here];
            shuffled[here] = shuffled[there];
            shuffled[there] = temporary;
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

int period_margin_compare(const void *one, const void *other)
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

void period_shuffle_fill(PeriodShuffle *shuffle, const EngineSignum *content, unsigned long long counter)
{
    unsigned long long words[PERIOD_SEED_WORDS];
    for (unsigned int word = 0u; word < PERIOD_SEED_WORDS; word += 1u)
    {
        unsigned long long word_value = 0ull;
        for (unsigned int byte = 0u; byte < 8u; byte += 1u)
        {
            word_value |= (unsigned long long)content->bytes[(word * 8u) + byte] << (8u * byte);
        }
        words[word] = word_value;
    }
    for (unsigned int round = 0u; round < PERIOD_ROUNDS; round += 1u)
    {
        const unsigned long long mixed =
            period_mix(words[round % PERIOD_SEED_WORDS] ^ period_mix((counter * PERIOD_ROUNDS) + round));
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
void period_strongest(const unsigned long long *same, PeriodAxis *axis)
{
    const unsigned long long lags = axis->lags;
    for (unsigned long long candidate = 2ull; ((2ull * candidate) + 1ull) <= lags; candidate += 1ull)
    {
        PeriodPeak peak;
        if ((period_peak(same, candidate, &peak) != 0) &&
            ((axis->candidate == 0ull) || (peak.height > axis->margin.numerator)))
        {
            period_axis_set(axis, &peak);
        }
    }
}

// The fundamental: the smallest candidate whose peak clears the null band top. It answers both the
// harmonic (a period P also peaks at 2P, 3P, whose heights match P's. The strongest rule picked a
// multiple) and, with the per-axis null, the axis that carries no period (A12).
int period_fundamental(const unsigned long long *same, const PeriodMargin *top, PeriodAxis *axis)
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

extern "C" unsigned long long period_agreement_entries(unsigned int rank, const unsigned long long *extent)
{
    unsigned long long entries = 0ull;
    for (unsigned int axis = 0u; (extent != NULL) && (axis < rank) && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        entries += extent[axis] / 2ull;
    }
    return entries;
}

// the pool's slices for `voxels` and `entries`, in the order they are laid out and taken: the histogram, the agreement
// and the shuffled lanes; the plan is laid out from them, and a pool reserved from it takes them
static DevicePoolPlan period_plan(unsigned long long voxels, unsigned long long entries, EngineError *error,
                                  DevicePoolTakeRequest takes[PERIOD_SLICES])
{
    PeriodResident *const resident = &g_period_resident;
    const DevicePoolTakeRequest requests[PERIOD_SLICES] = {
        {&resident->pool, PERIOD_VALUES * sizeof(unsigned int), (void **)&resident->histogram, error},
        {&resident->pool, entries * sizeof(unsigned long long), (void **)&resident->agreement, error},
        {&resident->pool, voxels * sizeof(unsigned short), (void **)&resident->shuffled, error}};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < PERIOD_SLICES; at += 1u)
    {
        takes[at] = requests[at];
        device_pool_plan_slice(&plan, requests[at].bytes);
    }
    return plan;
}

// the pool grown to hold `voxels` and `entries`. A pool that already holds both is kept as it is, and a grown pool
// holds the most of each asked so far: extents that take turns grow it once.
int period_reserve(unsigned long long voxels, unsigned long long entries, EngineError *error)
{
    PeriodResident *const resident = &g_period_resident;
    if ((voxels <= resident->voxels) && (entries <= resident->entries))
    {
        return 1;
    }
    const unsigned long long max_voxels = (voxels > resident->voxels) ? voxels : resident->voxels;
    const unsigned long long max_entries = (entries > resident->entries) ? entries : resident->entries;
    device_pool_release(&resident->pool);
    resident->histogram = NULL;
    resident->agreement = NULL;
    resident->shuffled = NULL;
    resident->voxels = 0ull;
    resident->entries = 0ull;
    DevicePoolTakeRequest takes[PERIOD_SLICES];
    const DevicePoolPlan plan = period_plan(max_voxels, max_entries, error, takes);
    const DevicePoolReserveRequest reserve = {&plan, &resident->pool, error};
    int ok = device_pool_reserve(&reserve) == 0L;
    // the slices are taken in the plan's order, and each lands where the plan laid it out with none errored
    for (unsigned int at = 0u; (ok != 0) && (at < PERIOD_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    resident->voxels = (ok != 0) ? max_voxels : 0ull;
    resident->entries = (ok != 0) ? max_entries : 0ull;
    return ok;
}

extern "C" unsigned long long period_reserve_bytes(unsigned long long voxels, unsigned long long entries)
{
    if ((voxels == 0ull) || (voxels > PERIOD_VOXELS_MAX))
    {
        return 0ull;
    }
    DevicePoolTakeRequest takes[PERIOD_SLICES];
    // the agreement's slice holds one entry at the least, as the calls hold it
    const DevicePoolPlan plan = period_plan(voxels, (entries != 0ull) ? entries : 1ull, NULL, takes);
    return device_pool_plan_bytes(&plan);
}
