// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// npy_read.c: the layout, zip archives and the read
#include "npy_internal.h"

static const NpySource npy_empty_source = {NULL, NULL, 0ull, 0ull, NULL};

static const NpyLayout npy_empty_layout = {{0u, {0ull}, {'\0'}, 0u, ENGINE_ELEMENT_UNSIGNED}, 0u, 0u, 0ull, 0ull};

static const ZipEntry npy_empty_entry = {NULL, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull};

static const unsigned char npy_magic[6u] = {0x93u, 'N', 'U', 'M', 'P', 'Y'};

static const unsigned char npy_zip_local[4u] = {'P', 'K', 0x03u, 0x04u};

static const unsigned char npy_zip_end[4u] = {'P', 'K', 0x05u, 0x06u};

static unsigned int npy_total(const EngineArrayExtent *extent, unsigned int from_axis, unsigned long long *total)
{
    unsigned long long product = extent->element_bytes;
    unsigned int empty = 0u;
    for (unsigned int axis = from_axis; axis < extent->rank; axis += 1u)
    {
        empty |= (extent->sizes[axis] == 0ull) ? 1u : 0u;
    }
    for (unsigned int axis = from_axis; (empty == 0u) && (axis < extent->rank); axis += 1u)
    {
        if (!npy_multiply(product, extent->sizes[axis], &product))
        {
            return 0u;
        }
    }
    *total = (empty != 0u) ? 0ull : product;
    return 1u;
}

static unsigned int npy_layout(const NpySource *source, NpyLayout *layout)
{
    unsigned char preamble[12u];
    const unsigned long long preamble_bytes = (source->length < 12ull) ? source->length : 12ull;
    if ((preamble_bytes < 10ull) || !npy_source_fetch(source, 0ull, preamble_bytes, preamble) ||
        (memcmp(preamble, npy_magic, sizeof npy_magic) != 0))
    {
        return 0u;
    }
    const unsigned int major = preamble[6u];
    const unsigned int minor = preamble[7u];
    if ((minor != 0u) || (major < 1u) || (major > 3u) || ((major > 1u) && (preamble_bytes < 12ull)))
    {
        return 0u;
    }
    const unsigned long long header_start = (major == 1u) ? 10ull : 12ull;
    const unsigned long long header_length = npy_load(preamble + 8u, (major == 1u) ? 2u : 4u);
    if (header_length > (source->length - header_start))
    {
        return 0u;
    }
    unsigned char *const header = malloc((size_t)header_length + 1u);
    if (header == NULL)
    {
        return 0u;
    }
    NpyLayout parsed = npy_empty_layout;
    const int understood =
        npy_source_fetch(source, header_start, header_length, header) && npy_dictionary(header, header_length, &parsed);
    free(header);
    unsigned long long data_bytes = 0ull;
    if (!understood || !npy_total(&parsed.extent, 0u, &data_bytes))
    {
        return 0u;
    }
    parsed.data_offset = header_start + header_length;
    parsed.data_bytes = data_bytes;
    if (data_bytes > (source->length - parsed.data_offset))
    {
        return 0u;
    }
    *layout = parsed;
    return 1u;
}

static unsigned int npy_zip_open(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                                 const ZipEntry *entry, NpySource *source, unsigned char **owned, EngineError *error)
{
    if (entry->method == 0ull)
    {
        unsigned long long data_start = 0ull;
        if (!zip_member_data(tools, path, archive, entry, &data_start, error) ||
            !NPY_CHECK(entry->compressed == entry->uncompressed, entry, error, ENGINE_ERROR_REQUEST))
        {
            return 0u;
        }
        const NpySource stored = {tools, path, data_start, entry->uncompressed, NULL};
        *source = stored;
        return 1u;
    }
    unsigned char *const unpacked =
        npy_fits_memory(entry->uncompressed + 1ull) ? malloc((size_t)entry->uncompressed + 1u) : NULL;
    if (!NPY_CHECK(unpacked != NULL, entry, error, ENGINE_ERROR_RESOURCE))
    {
        return 0u;
    }
    if (zip_member_read(tools, path, archive, entry, unpacked, entry->uncompressed, error) == ZIP_ERROR)
    {
        free(unpacked);
        return 0u;
    }
    const NpySource inflated = {tools, path, 0ull, entry->uncompressed, unpacked};
    *source = inflated;
    *owned = unpacked;
    return 1u;
}

static unsigned int npy_zip_candidate(const ZipEntry *entry, const char *member)
{
    const int directory = (entry->name_length > 0ull) && (entry->name[entry->name_length - 1ull] == '/');
    if (directory)
    {
        return 0u;
    }
    if (member == NULL)
    {
        return 1u;
    }
    const size_t member_length = strlen(member);
    const int exact = (entry->name_length == member_length) && (memcmp(entry->name, member, member_length) == 0);
    const int suffixed = (entry->name_length == (member_length + 4u)) &&
                         (memcmp(entry->name, member, member_length) == 0) &&
                         (memcmp(entry->name + member_length, ".npy", 4u) == 0);
    return (exact || suffixed) ? 1u : 0u;
}

static void npy_zip_list(const EngineIngestTools *tools, const char *path, const char *member,
                         const ZipArchive *archive, unsigned long long matches)
{
    fprintf(stderr, "npy: %s holds %llu candidate arrays%s%s; name one as the member\n", path, matches,
            (member != NULL) ? " named " : "", (member != NULL) ? member : "");
    unsigned long long at = 0ull;
    for (unsigned long long entry_index = 0ull; entry_index < archive->entries; entry_index += 1ull)
    {
        EngineError probe;
        memset(&probe, 0, sizeof(probe));
        ZipEntry entry = npy_empty_entry;
        if (!zip_entry_next(archive, &at, &entry, &probe))
        {
            return;
        }
        if (!npy_zip_candidate(&entry, member))
        {
            continue;
        }
        NpySource source = npy_empty_source;
        unsigned char *owned = NULL;
        NpyLayout layout = npy_empty_layout;
        const int parsed =
            npy_zip_open(tools, path, archive, &entry, &source, &owned, &probe) && npy_layout(&source, &layout);
        free(owned);
        fprintf(stderr, "npy:   %.*s ", (int)entry.name_length, (const char *)entry.name);
        if (!parsed)
        {
            fprintf(stderr, "unreadable\n");
            continue;
        }
        fprintf(stderr, "(");
        for (unsigned int axis = 0u; axis < layout.extent.rank; axis += 1u)
        {
            fprintf(stderr, (axis == 0u) ? "%llu" : ", %llu", layout.extent.sizes[axis]);
        }
        fprintf(stderr, ")\n");
    }
}

static unsigned int npy_zip_select(const EngineIngestTools *tools, const char *path, const char *member,
                                   const ZipArchive *archive, ZipEntry *chosen, EngineError *error)
{
    unsigned long long matches = 0ull;
    unsigned long long at = 0ull;
    for (unsigned long long entry_index = 0ull; entry_index < archive->entries; entry_index += 1ull)
    {
        ZipEntry entry = npy_empty_entry;
        if (!zip_entry_next(archive, &at, &entry, error))
        {
            return 0u;
        }
        if (npy_zip_candidate(&entry, member))
        {
            matches += 1ull;
            *chosen = entry;
        }
    }
    if (matches > 1ull)
    {
        npy_zip_list(tools, path, member, archive, matches);
    }
    return NPY_CHECK(matches == 1ull, &matches, error, ENGINE_ERROR_REQUEST) ? 1u : 0u;
}

static unsigned int npy_resolve(const char *path, const char *member, const EngineIngestTools *tools, NpySource *source,
                                unsigned char **owned, NpyLayout *layout, EngineError *error)
{
    *owned = NULL;
    const long long size = tools->size(path);
    unsigned char magic[4u];
    if (!NPY_CHECK((size >= 4LL) && npy_file_fetch(tools, path, 0ull, 4ull, magic), path, error, ENGINE_ERROR_REQUEST))
    {
        return 0u;
    }
    // a size of at least four converts to unsigned long long exactly
    const unsigned long long file_bytes = (unsigned long long)size;
    if (memcmp(magic, npy_magic, sizeof magic) == 0)
    {
        const NpySource entire_file = {tools, path, 0ull, file_bytes, NULL};
        *source = entire_file;
        return NPY_CHECK((member == NULL) && npy_layout(source, layout), path, error, ENGINE_ERROR_REQUEST) ? 1u : 0u;
    }
    if (!NPY_CHECK((memcmp(magic, npy_zip_local, sizeof magic) == 0) || (memcmp(magic, npy_zip_end, sizeof magic) == 0),
                   magic, error, ENGINE_ERROR_REQUEST))
    {
        return 0u;
    }
    ZipArchive archive;
    if (!zip_archive_open(tools, path, &archive, error))
    {
        return 0u;
    }
    ZipEntry entry = npy_empty_entry;
    const int ok = npy_zip_select(tools, path, member, &archive, &entry, error) &&
                   npy_zip_open(tools, path, &archive, &entry, source, owned, error) &&
                   NPY_CHECK(npy_layout(source, layout), source, error, ENGINE_ERROR_REQUEST);
    zip_archive_release(&archive);
    if (!ok)
    {
        free(*owned);
        *owned = NULL;
    }
    return ok ? 1u : 0u;
}

static unsigned int npy_same_extent(const EngineArrayExtent *found, const EngineArrayExtent *given)
{
    int same = (found->rank == given->rank) && (found->element_bytes == given->element_bytes) &&
               (found->element_kind == given->element_kind);
    for (unsigned int axis = 0u; same && (axis < found->rank); axis += 1u)
    {
        same = (found->sizes[axis] == given->sizes[axis]) && (found->axes[axis] == given->axes[axis]);
    }
    return same ? 1u : 0u;
}

static unsigned int npy_fortran_copy(const NpySource *source, const NpyLayout *layout, unsigned long long first,
                                     unsigned long long count, unsigned char *out)
{
    const EngineArrayExtent *const extent = &layout->extent;
    const unsigned long long element = extent->element_bytes;
    const unsigned long long stride = extent->sizes[0u];
    unsigned long long output_step[ENGINE_ARRAY_RANK];
    unsigned long long position[ENGINE_ARRAY_RANK];
    unsigned long long columns = 1ull;
    for (unsigned int axis = extent->rank; axis > 0u; axis -= 1u)
    {
        output_step[axis - 1u] = columns;
        position[axis - 1u] = 0ull;
        columns *= (axis > 1u) ? extent->sizes[axis - 1u] : 1ull;
    }
    if (columns == 0ull)
    {
        return 1u;
    }
    const unsigned long long run = count * element;
    const unsigned long long column_bytes = stride * element;
    const unsigned long long range =
        (run < NPY_FORTRAN_BLOCK) ? (1ull + ((NPY_FORTRAN_BLOCK - run) / column_bytes)) : 1ull;
    const unsigned long long group = (range < columns) ? range : columns;
    unsigned char *const block = malloc((size_t)(((group - 1ull) * column_bytes) + run));
    if (block == NULL)
    {
        return 0u;
    }
    unsigned long long place = 0ull;
    unsigned long long column = 0ull;
    unsigned int ok = 1u;
    while ((ok != 0u) && (column < columns))
    {
        const unsigned long long taken = ((columns - column) < group) ? (columns - column) : group;
        const unsigned long long span = ((taken - 1ull) * column_bytes) + run;
        ok = npy_source_fetch(source, layout->data_offset + (((column * stride) + first) * element), span, block);
        for (unsigned long long within = 0ull; (ok != 0u) && (within < taken); within += 1ull)
        {
            const unsigned char *const from = block + (within * column_bytes);
            for (unsigned long long row = 0ull; row < count; row += 1ull)
            {
                memcpy(out + (((row * columns) + place) * element), from + (row * element), (size_t)element);
            }
            for (unsigned int axis = 1u; axis < extent->rank; axis += 1u)
            {
                position[axis] += 1ull;
                place += output_step[axis];
                if (position[axis] < extent->sizes[axis])
                {
                    break;
                }
                place -= position[axis] * output_step[axis];
                position[axis] = 0ull;
            }
        }
        column += taken;
    }
    free(block);
    return ok;
}

long npy_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1L;
    }
    NpySource source = npy_empty_source;
    unsigned char *owned = NULL;
    NpyLayout layout = npy_empty_layout;
    const unsigned int resolved =
        npy_resolve(request->path, request->member, request->tools, &source, &owned, &layout, request->error);
    free(owned);
    if (!resolved)
    {
        return -1L;
    }
    *request->extent = layout.extent;
    return 0L;
}

long long npy_read(const EngineArrayRead *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1LL;
    }
    NpySource source = npy_empty_source;
    unsigned char *owned = NULL;
    NpyLayout layout = npy_empty_layout;
    const unsigned int resolved =
        npy_resolve(request->path, request->member, request->tools, &source, &owned, &layout, request->error);
    unsigned long long row_bytes = 0ull;
    const int agrees = resolved && npy_same_extent(&layout.extent, request->extent) &&
                       (request->first <= request->end) && (request->end <= layout.extent.sizes[0u]) &&
                       npy_total(&layout.extent, 1u, &row_bytes);
    const unsigned long long count = agrees ? (request->end - request->first) : 0ull;
    const unsigned long long wanted = count * row_bytes;
    if (!agrees || (wanted > request->out_capacity) || !npy_fits_memory(wanted))
    {
        free(owned);
        return -1LL;
    }
    if (wanted == 0ull)
    {
        free(owned);
        return 0LL;
    }
    const unsigned int copied =
        (layout.fortran_order != 0u)
            ? npy_fortran_copy(&source, &layout, request->first, count, request->out)
            : npy_source_fetch(&source, layout.data_offset + (request->first * row_bytes), wanted, request->out);
    free(owned);
    if (!copied)
    {
        memset(request->out, 0, (size_t)wanted);
        return -1LL;
    }
    if (layout.big_endian != 0u)
    {
        npy_swap(request->out, wanted, layout.extent.element_bytes);
    }
    return (long long)wanted;
}
