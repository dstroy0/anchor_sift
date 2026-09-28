// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_read.c: the chunk grid, gathering and the entry points
#include "hdf5_internal.h"

static int hdf5_chunk_grid(Hdf5Gather *gather)
{
    Hdf5File *const file = gather->file;
    const Hdf5Object *const object = gather->object;
    const unsigned int rank = object->rank;
    unsigned long long down[ENGINE_ARRAY_RANK];
    down[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        down[axis - 1u] = down[axis] * gather->range[axis];
    }
    Hdf5Fixed fixed;
    memset(&fixed, 0, sizeof(fixed));
    fixed.prefix = NULL;
    fixed.page = NULL;
    int ok = (object->chunk_index != HDF5_INDEX_FIXED) || hdf5_fixed_open(file, object, gather, &fixed);
    const unsigned long long start = gather->first / object->chunk[0u];
    const unsigned long long stop =
        (gather->end / object->chunk[0u]) + (((gather->end % object->chunk[0u]) != 0ull) ? 1ull : 0ull);
    unsigned long long scaled[ENGINE_ARRAY_RANK];
    memset(scaled, 0, sizeof(scaled));
    scaled[0u] = start;
    int more = ok && (start < stop);
    for (unsigned int axis = 1u; axis < rank; axis += 1u)
    {
        more = more && (gather->grid[axis] > 0ull);
    }
    while (more)
    {
        unsigned long long origin[ENGINE_ARRAY_RANK];
        unsigned long long linear = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            origin[axis] = scaled[axis] * object->chunk[axis];
            linear += scaled[axis] * down[axis];
        }
        unsigned long long address = hdf5_all_ones(file->offset_bytes);
        unsigned long long stored = gather->chunk_bytes;
        unsigned int mask = 0u;
        if (object->chunk_index == HDF5_INDEX_SINGLE)
        {
            address = object->data_address;
            stored = (object->filter_count > 0u) ? object->single_bytes : stored;
            mask = object->single_mask;
        }
        else if (object->chunk_index == HDF5_INDEX_IMPLICIT)
        {
            address = hdf5_undefined(file, object->data_address)
                          ? address
                          : (object->data_address + (linear * gather->chunk_bytes));
        }
        else
        {
            ok = hdf5_fixed_entry(file, &fixed, linear, &address, &stored, &mask);
        }
        ok = ok && hdf5_chunk_place(gather, origin, address, stored, mask);
        more = 0;
        for (unsigned int axis = rank; ok && (axis > 0u); axis -= 1u)
        {
            const unsigned int moving = axis - 1u;
            const unsigned long long bound = (moving == 0u) ? stop : gather->grid[moving];
            scaled[moving] += 1ull;
            if (scaled[moving] < bound)
            {
                more = 1;
                break;
            }
            scaled[moving] = (moving == 0u) ? start : 0ull;
        }
    }
    hdf5_fixed_close(&fixed);
    return ok;
}

static void hdf5_swap(unsigned char *bytes, size_t length, unsigned int width)
{
    for (size_t element = 0u; (element + width) <= length; element += width)
    {
        for (unsigned int lane = 0u; lane < (width / 2u); lane += 1u)
        {
            const unsigned char kept = bytes[element + lane];
            bytes[element + lane] = bytes[element + width - 1u - lane];
            bytes[element + width - 1u - lane] = kept;
        }
    }
}

static int hdf5_request_check(Hdf5File *file, const Hdf5Object *object, const EngineArrayRead *request,
                              unsigned long long *bytes)
{
    const EngineArrayExtent *const extent = request->extent;
    int matches =
        (extent == NULL) || ((extent->rank == object->rank) && (extent->element_bytes == object->element_bytes) &&
                             (extent->element_kind == object->element_kind));
    for (unsigned int axis = 0u; matches && (extent != NULL) && (axis < object->rank); axis += 1u)
    {
        matches = (extent->sizes[axis] == object->extent[axis]);
    }
    if (!matches)
    {
        return hdf5_error(file, "a request extent that does not match the dataset");
    }
    if ((request->first > request->end) || (request->end > object->extent[0u]))
    {
        return hdf5_error(file, "a row range outside the dataset");
    }
    unsigned long long row = 0ull;
    const unsigned long long rows = request->end - request->first;
    if (!hdf5_product(&object->extent[1u], object->rank - 1u, object->element_bytes, &row) ||
        ((rows != 0ull) && (row > (~0ull / rows))))
    {
        return hdf5_error(file, "a row range whose byte size overflows");
    }
    const unsigned long long total = rows * row;
    if (((unsigned long long)(size_t)total != total) || (total > request->out_capacity) ||
        ((total > 0ull) && (request->out == NULL)))
    {
        return hdf5_error(file, "an output buffer too small for the rows asked");
    }
    *bytes = total;
    return 1;
}

static int hdf5_gather_chunks(Hdf5Gather *gather)
{
    const Hdf5Object *const object = gather->object;
    const unsigned int rank = object->rank;
    unsigned long long chunk_bytes = 0ull;
    (void)hdf5_product(object->chunk, rank + 1u, 1ull, &chunk_bytes);
    gather->chunk_bytes = (size_t)chunk_bytes;
    gather->chunk_stride[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        gather->chunk_stride[axis - 1u] = gather->chunk_stride[axis] * object->chunk[axis];
    }
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned long long span = object->chunk[axis];
        const unsigned long long bounded =
            (object->maximum[axis] >= object->extent[axis]) ? object->maximum[axis] : object->extent[axis];
        gather->grid[axis] = (object->extent[axis] / span) + (((object->extent[axis] % span) != 0ull) ? 1ull : 0ull);
        gather->range[axis] = (bounded / span) + (((bounded % span) != 0ull) ? 1ull : 0ull);
    }
    if (object->chunk_index == HDF5_INDEX_TREE)
    {
        return hdf5_undefined(gather->file, object->data_address) ||
               hdf5_chunk_tree(gather, object->data_address, 0u, 1, 0u);
    }
    return hdf5_chunk_grid(gather);
}

static long long hdf5_gather(Hdf5File *file, const Hdf5Object *object, const EngineArrayRead *request,
                             unsigned long long bytes)
{
    if (bytes == 0ull)
    {
        return 0LL;
    }
    Hdf5Gather gather;
    memset(&gather, 0, sizeof(gather));
    gather.file = file;
    gather.object = object;
    gather.first = request->first;
    gather.end = request->end;
    gather.out = request->out;
    const unsigned int rank = object->rank;
    gather.out_stride[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        gather.out_stride[axis - 1u] = gather.out_stride[axis] * object->extent[axis];
    }
    const unsigned long long row_bytes = gather.out_stride[0u] * object->element_bytes;
    const size_t length = (size_t)bytes;
    const unsigned long long fill_bytes = object->has_fill ? object->fill_bytes : object->old_fill_bytes;
    const unsigned char *const fill = object->has_fill ? object->fill : object->old_fill;
    const int unallocated = (object->layout_class == 1u) && hdf5_undefined(file, object->data_address);
    if ((object->layout_class == 2u) || unallocated)
    {
        memset(request->out, 0, length);
        for (size_t element = 0u; (fill_bytes == object->element_bytes) && (element < length);
             element += object->element_bytes)
        {
            memcpy(&request->out[element], fill, object->element_bytes);
        }
    }
    int ok = 1;
    if (object->layout_class == 0u)
    {
        memcpy(request->out, &object->compact[request->first * row_bytes], length);
    }
    else if ((object->layout_class == 1u) && !unallocated)
    {
        ok = hdf5_fetch(file, object->data_address + (request->first * row_bytes), bytes, request->out);
    }
    else if (object->layout_class == 2u)
    {
        ok = hdf5_gather_chunks(&gather);
    }
    if (!ok)
    {
        memset(request->out, 0, length);
        return -1LL;
    }
    if (object->big_endian && (object->element_bytes > 1u))
    {
        hdf5_swap(request->out, length, object->element_bytes);
    }
    return (long long)bytes;
}

long hdf5_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->extent == NULL))
    {
        fprintf(stderr, "hdf5: a describe request with no extent to fill\n");
        return -1L;
    }
    Hdf5File file;
    Hdf5Object object;
    memset(&object, 0, sizeof(object));
    object.compact = NULL;
    unsigned long long address = 0ull;
    int ok = hdf5_open(&file, request->path, request->tools);
    ok = ok && hdf5_locate(&file, request->member, &address);
    ok = ok && hdf5_object_open(&file, address, &object);
    ok = ok && hdf5_dataset_check(&file, &object);
    if (ok)
    {
        EngineArrayExtent *const extent = request->extent;
        memset(extent, 0, sizeof(*extent));
        extent->rank = object.rank;
        for (unsigned int axis = 0u; axis < object.rank; axis += 1u)
        {
            extent->sizes[axis] = object.extent[axis];
            extent->axes[axis] = 0;
        }
        extent->element_bytes = object.element_bytes;
        extent->element_kind = object.element_kind;
    }
    hdf5_object_close(&object);
    if (!ok)
    {
        hdf5_report(&file);
        return -1L;
    }
    return 0L;
}

long long hdf5_read(const EngineArrayRead *request)
{
    if (request == NULL)
    {
        fprintf(stderr, "hdf5: a read request that is missing\n");
        return -1LL;
    }
    Hdf5File file;
    Hdf5Object object;
    memset(&object, 0, sizeof(object));
    object.compact = NULL;
    unsigned long long address = 0ull;
    unsigned long long bytes = 0ull;
    int ok = hdf5_open(&file, request->path, request->tools);
    ok = ok && hdf5_locate(&file, request->member, &address);
    ok = ok && hdf5_object_open(&file, address, &object);
    ok = ok && hdf5_dataset_check(&file, &object);
    ok = ok && hdf5_request_check(&file, &object, request, &bytes);
    const long long written = ok ? hdf5_gather(&file, &object, request, bytes) : -1LL;
    hdf5_object_close(&object);
    if (written < 0LL)
    {
        hdf5_report(&file);
    }
    return written;
}
