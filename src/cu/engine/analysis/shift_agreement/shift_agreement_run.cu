// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// shift_agreement_run.cu: the axis, volumes and the run
#include "shift_agreement_internal.h"

static int agreement_axis(unsigned int *values, AgreementLayout layout, unsigned int axis, int inverse)
{
    const unsigned int length = layout.padded[axis];
    if (length < 2u)
    {
        return 1;
    }
    const unsigned int stride = layout.padded_strides[axis];
    const unsigned int blocks = (layout.total + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    const AxisTables *const tables = axis_tables(length);
    int ok = (tables != NULL) ? 1 : 0;
    unsigned int logarithm = 0u;
    while ((1u << logarithm) < length)
    {
        logarithm += 1u;
    }
    if (inverse == 0)
    {
        for (unsigned int level = 0u; (ok != 0) && (level < logarithm); level += 2u)
        {
            const unsigned int levels = ((level + 1u) < logarithm) ? 2u : 1u;
            forward_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(values, tables->roots[0], level, levels, length, stride,
                                                              layout.total);
            ok = agreement_launched();
        }
        return ok;
    }
    unsigned int remaining = logarithm;
    while ((ok != 0) && (remaining > 0u))
    {
        const unsigned int levels = (((remaining % 2u) == 1u) && (remaining == logarithm)) ? 1u : 2u;
        const unsigned int level = remaining - levels;
        inverse_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(values, tables->roots[1], level, levels, length, stride,
                                                          layout.total);
        ok = agreement_launched();
        remaining = level;
    }
    return ok;
}

// The layout for `axes` extents, `weights` NULL for none: each axis padded to the power of two at or above 2e - 1, the
// length a cyclic transform needs to hold every lag without wrap. 0 for extents the run errors: an extent of 0 or past
// half the longest axis, a voxel count at the prime or past it, or a padded total past 2^31 - 1.
static int agreement_layout(unsigned int axes, const unsigned int *extents, const unsigned int *weights,
                            AgreementLayout *layout)
{
    memset(layout, 0, sizeof(*layout));
    layout->axes = axes;
    unsigned long long voxels = 1ull;
    unsigned long long padded_total = 1ull;
    for (unsigned int axis = 0u; axis < axes; axis += 1u)
    {
        if ((extents[axis] == 0u) || (extents[axis] > (SHIFT_AGREEMENT_LONGEST_AXIS / 2u)))
        {
            return 0;
        }
        layout->extents[axis] = extents[axis];
        layout->weights[axis] = (weights != NULL) ? weights[axis] : 0u;
        voxels *= (unsigned long long)extents[axis];
        unsigned long long power = 1ull;
        while (power < ((2ull * (unsigned long long)extents[axis]) - 1ull))
        {
            power <<= 1u;
        }
        // the extent is at most 2^22, and its power at most 2^23
        layout->padded[axis] = (unsigned int)power;
        padded_total *= power;
        if ((voxels >= (unsigned long long)SHIFT_AGREEMENT_PRIME) || (padded_total > 0x7FFFFFFFull))
        {
            return 0;
        }
    }
    // the voxel count is below the prime, under 2^30, and the padded total at most 2^31 - 1
    layout->voxels = (unsigned int)voxels;
    layout->total = (unsigned int)padded_total;
    unsigned int stride = layout->total;
    unsigned int table_offset = 0u;
    for (unsigned int axis = 0u; axis < axes; axis += 1u)
    {
        stride /= layout->padded[axis];
        layout->padded_strides[axis] = stride;
        layout->table_offsets[axis] = table_offset;
        table_offset += layout->padded[axis];
    }
    return 1;
}

#define SHIFT_AGREEMENT_NONE_KEPT SHIFT_AGREEMENT_VOLUMES

static VolumesResident s_volumes_resident;

#define SHIFT_AGREEMENT_SLICES (2u + SHIFT_AGREEMENT_VOLUMES)

// the pool's slices for `total` padded elements and `words` bit words, in the order they are laid out and taken: the
// before and after words, then the four volumes; the plan is laid out from them, and a pool reserved from it takes them
static DevicePoolPlan plan_volumes(size_t total, size_t words, EngineError *error,
                                   DevicePoolTakeRequest takes[SHIFT_AGREEMENT_SLICES])
{
    VolumesResident *const resident = &s_volumes_resident;
    const DevicePoolTakeRequest requests[SHIFT_AGREEMENT_SLICES] = {
        {&resident->pool, words * sizeof(unsigned long long), (void **)&resident->before, error},
        {&resident->pool, words * sizeof(unsigned long long), (void **)&resident->after, error},
        {&resident->pool, total * sizeof(unsigned int), (void **)&resident->volumes[0], error},
        {&resident->pool, total * sizeof(unsigned int), (void **)&resident->volumes[1], error},
        {&resident->pool, total * sizeof(unsigned int), (void **)&resident->volumes[2], error},
        {&resident->pool, total * sizeof(unsigned int), (void **)&resident->volumes[3], error}};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < SHIFT_AGREEMENT_SLICES; at += 1u)
    {
        takes[at] = requests[at];
        device_pool_plan_slice(&plan, requests[at].bytes);
    }
    return plan;
}

static int reserve_volumes(size_t total, size_t words)
{
    VolumesResident *const resident = &s_volumes_resident;
    if ((resident->total == total) && (resident->words == words) && (total != 0u))
    {
        return 1;
    }
    device_pool_release(&resident->pool);
    free(resident->kept_words);
    memset(resident, 0, sizeof(*resident));
    resident->kept = SHIFT_AGREEMENT_NONE_KEPT;
    // the run errors without detail, and the pool's error is kept here and dropped
    EngineError error;
    memset(&error, 0, sizeof(error));
    DevicePoolTakeRequest takes[SHIFT_AGREEMENT_SLICES];
    const DevicePoolPlan plan = plan_volumes(total, words, &error, takes);
    const DevicePoolReserveRequest reserve = {&plan, &resident->pool, &error};
    int ok = device_pool_reserve(&reserve) == 0L;
    // the slices are taken in the plan's order, and each lands where the plan laid it out with none errored
    for (unsigned int at = 0u; (ok != 0) && (at < SHIFT_AGREEMENT_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    resident->kept_words = (unsigned long long *)malloc(words * sizeof(unsigned long long));
    ok = ok && (resident->kept_words != NULL);
    if (ok == 0)
    {
        device_pool_release(&resident->pool);
        free(resident->kept_words);
        memset(resident, 0, sizeof(*resident));
        resident->kept = SHIFT_AGREEMENT_NONE_KEPT;
        return 0;
    }
    resident->total = total;
    resident->words = words;
    return 1;
}

static NegationResident s_negation_resident;

static int reserve_negation(const AgreementLayout *layout)
{
    NegationResident *const resident = &s_negation_resident;
    if ((resident->negation != NULL) && (resident->axes == layout->axes) &&
        (memcmp(resident->padded, layout->padded, sizeof(resident->padded)) == 0))
    {
        return 1;
    }
    s_volumes_resident.kept = SHIFT_AGREEMENT_NONE_KEPT;
    cudaFree(resident->negation);
    memset(resident, 0, sizeof(*resident));
    size_t entries = 0u;
    for (unsigned int axis = 0u; axis < layout->axes; axis += 1u)
    {
        entries += (size_t)layout->padded[axis];
    }
    unsigned int *const host = (unsigned int *)malloc((entries + 1u) * sizeof(unsigned int));
    int ok = (host != NULL) ? 1 : 0;
    for (unsigned int axis = 0u; (ok != 0) && (axis < layout->axes); axis += 1u)
    {
        if (layout->padded[axis] < 2u)
        {
            host[layout->table_offsets[axis]] = 0u;
            continue;
        }
        const AxisTables *const tables = axis_tables(layout->padded[axis]);
        ok = (tables != NULL) ? 1 : 0;
        if (ok != 0)
        {
            memcpy(&host[layout->table_offsets[axis]], tables->negation,
                   (size_t)layout->padded[axis] * sizeof(unsigned int));
        }
    }
    ok = ok && (cudaMalloc((void **)&resident->negation, (entries + 1u) * sizeof(unsigned int)) == cudaSuccess);
    ok = ok &&
         (cudaMemcpy(resident->negation, host, entries * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    free(host);
    if (ok == 0)
    {
        cudaFree(resident->negation);
        memset(resident, 0, sizeof(*resident));
        return 0;
    }
    resident->axes = layout->axes;
    memcpy(resident->padded, layout->padded, sizeof(resident->padded));
    return 1;
}

extern "C" unsigned long long shift_agreement_reserve_bytes(unsigned int axes, const unsigned int *extents)
{
    AgreementLayout layout;
    if ((extents == NULL) || (axes == 0u) || (axes > SHIFT_AGREEMENT_AXES) ||
        (agreement_layout(axes, extents, NULL, &layout) == 0))
    {
        return 0ull;
    }
    DevicePoolTakeRequest takes[SHIFT_AGREEMENT_SLICES];
    const DevicePoolPlan plan = plan_volumes((size_t)layout.total, ((size_t)layout.voxels + 63u) / 64u, NULL, takes);
    // the negation table, one entry past every padded coordinate, and each distinct length's two root tables
    unsigned long long tables = 1ull;
    for (unsigned int axis = 0u; axis < axes; axis += 1u)
    {
        tables += layout.padded[axis];
        unsigned int earlier = 0u;
        while ((earlier < axis) && (layout.padded[earlier] != layout.padded[axis]))
        {
            earlier += 1u;
        }
        tables += ((earlier == axis) && (layout.padded[axis] >= 2u)) ? (2ull * layout.padded[axis]) : 0ull;
    }
    // the tables are small allocations beside the pool, which the device maps into shared pages: they are counted
    // together, rounded up to the page
    DevicePoolPlan tables_plan = {0ull, 0ull, 0};
    device_pool_plan_slice(&tables_plan, tables * sizeof(unsigned int));
    return device_pool_plan_bytes(&plan) + device_pool_plan_bytes(&tables_plan);
}

extern "C" long shift_agreement_run(ShiftAgreementRequest *args)
{
    if ((args == NULL) || (args->before == NULL) || (args->after == NULL) || (args->axes == 0u) ||
        (args->axes > SHIFT_AGREEMENT_AXES))
    {
        return SHIFT_AGREEMENT_ERROR;
    }
    AgreementLayout layout;
    if (agreement_layout(args->axes, args->extents, args->weights, &layout) == 0)
    {
        return SHIFT_AGREEMENT_ERROR;
    }
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return SHIFT_AGREEMENT_ERROR;
    }

    const size_t total = (size_t)layout.total;
    const size_t words = ((size_t)layout.voxels + 63u) / 64u;
    unsigned int *const host_counts =
        (args->counts != NULL) ? (unsigned int *)malloc(total * sizeof(unsigned int)) : NULL;
    int ok = ((args->counts == NULL) || (host_counts != NULL)) ? 1 : 0;
    ok = ok && reserve_volumes(total, words);
    ok = ok && reserve_negation(&layout);
    VolumesResident *const resident = &s_volumes_resident;
    unsigned long long *const device_before = resident->before;
    unsigned long long *const device_after = resident->after;
    // the kept transform was scattered by its own extents, and one padding and one word count hold several extents
    const int reuse = (ok != 0) && (resident->kept != SHIFT_AGREEMENT_NONE_KEPT) &&
                      (resident->kept_axes == layout.axes) &&
                      (memcmp(resident->kept_extents, layout.extents, sizeof(resident->kept_extents)) == 0) &&
                      (memcmp(resident->kept_words, args->before, words * sizeof(unsigned long long)) == 0);
    unsigned int *roles[SHIFT_AGREEMENT_VOLUMES - 1u] = {NULL, NULL, NULL};
    unsigned int filled = 0u;
    for (unsigned int slot = 0u; (ok != 0) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        if (((reuse != 0) && (slot == resident->kept)) || (filled == (SHIFT_AGREEMENT_VOLUMES - 1u)))
        {
            continue;
        }
        roles[filled] = resident->volumes[slot];
        filled += 1u;
    }
    unsigned int *reflected = roles[0];
    unsigned int *moved = roles[1];
    unsigned int *spare = roles[2];
    const unsigned int blocks = (layout.total + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    ok = ok && ((reuse != 0) || (cudaMemcpy(device_before, args->before, words * sizeof(unsigned long long),
                                            cudaMemcpyHostToDevice) == cudaSuccess));
    ok = ok && (cudaMemcpy(device_after, args->after, words * sizeof(unsigned long long), cudaMemcpyHostToDevice) ==
                cudaSuccess);
    ok = ok && ((reuse != 0) || (cudaMemset(reflected, 0, total * sizeof(unsigned int)) == cudaSuccess));
    ok = ok && (cudaMemset(moved, 0, total * sizeof(unsigned int)) == cudaSuccess);
    const unsigned int voxel_blocks = (layout.voxels + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
    if (ok != 0)
    {
        scatter_kernel<<<voxel_blocks, SHIFT_AGREEMENT_BLOCK>>>(device_before, device_after, (reuse != 0) ? 0u : 1u,
                                                                layout, reflected, moved);
        ok = agreement_launched();
    }
    if ((ok != 0) && (reuse != 0))
    {
        negate_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(resident->volumes[resident->kept],
                                                         s_negation_resident.negation, layout, reflected);
        ok = agreement_launched();
    }

    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = (reuse != 0) || (agreement_axis(reflected, layout, axis, 0) != 0);
        ok = ok && agreement_axis(moved, layout, axis, 0);
    }
    if (ok != 0)
    {
        multiply_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(
            reflected, moved, device_agreement_power(layout.total, SHIFT_AGREEMENT_PRIME - 2u), layout.total);
        ok = agreement_launched();
    }
    for (unsigned int axis = 0u; (axis < layout.axes) && (ok != 0); axis += 1u)
    {
        ok = agreement_axis(reflected, layout, axis, 1);
    }
    if ((ok != 0) && (host_counts != NULL))
    {
        ok = (cudaMemcpy(host_counts, reflected, total * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess)
                 ? 1
                 : 0;
    }

    if (ok != 0)
    {
        choice_kernel<<<blocks, SHIFT_AGREEMENT_BLOCK>>>(layout.total, spare);
        ok = agreement_launched();
    }
    for (unsigned int stride = 1u; (stride < layout.total) && (ok != 0); stride <<= 1u)
    {
        const unsigned int pairs = (layout.total + (2u * stride) - 1u) / (2u * stride);
        const unsigned int pair_blocks = (pairs + SHIFT_AGREEMENT_BLOCK - 1u) / SHIFT_AGREEMENT_BLOCK;
        tournament_kernel<<<pair_blocks, SHIFT_AGREEMENT_BLOCK>>>(reflected, spare, stride, pairs, layout);
        ok = agreement_launched();
    }
    unsigned int winner = 0u;
    unsigned int winner_count = 0u;
    ok = ok && (cudaMemcpy(&winner, spare, sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok &&
         (cudaMemcpy(&winner_count, &reflected[winner], sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);

    long answer = SHIFT_AGREEMENT_ERROR;
    if (ok != 0)
    {
        const size_t best = (size_t)winner;
        size_t rest = best;
        for (unsigned int axis = layout.axes; axis > 0u; axis -= 1u)
        {
            const long long coordinate = (long long)(rest % layout.padded[axis - 1u]);
            rest /= layout.padded[axis - 1u];
            args->lag[axis - 1u] = (int)((coordinate < (long long)(layout.padded[axis - 1u] / 2u))
                                             ? coordinate
                                             : (coordinate - (long long)layout.padded[axis - 1u]));
        }
        for (unsigned int axis = 0u; axis < SHIFT_AGREEMENT_AXES; axis += 1u)
        {
            args->padded[axis] = (axis < layout.axes) ? layout.padded[axis] : 0u;
            if (axis >= layout.axes)
            {
                args->lag[axis] = 0;
            }
        }
        args->agreement = winner_count;
        if (args->counts != NULL)
        {
            memcpy(args->counts, host_counts, total * sizeof(unsigned int));
        }
        answer = 0L;
    }
    resident->kept = SHIFT_AGREEMENT_NONE_KEPT;
    for (unsigned int slot = 0u; (answer == 0L) && (slot < SHIFT_AGREEMENT_VOLUMES); slot += 1u)
    {
        if (resident->volumes[slot] == moved)
        {
            resident->kept = slot;
            memcpy(resident->kept_words, args->after, words * sizeof(unsigned long long));
            resident->kept_axes = layout.axes;
            memcpy(resident->kept_extents, layout.extents, sizeof(resident->kept_extents));
        }
    }
    free(host_counts);
    return answer;
}
