// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_locate.c: finding a dataset, the survey, and the checks on it
#include "hdf5_internal.h"

static Hdf5Walk hdf5_group_links(Hdf5File *file, unsigned long long header, Hdf5LinkVisit visit, void *state,
                                 const char *name, size_t name_length)
{
    const uint32_t hash = (name != NULL) ? hdf5_lookup3((const unsigned char *)name, name_length) : 0u;
    Hdf5GroupWalk walk = {
        visit,      state, 0, 0ull, 0ull, 0, 0ull, 0ull, name != NULL, hash, NULL, 0u, (const unsigned char *)name,
        name_length};
    const Hdf5Walk messages = hdf5_header_walk(file, header, hdf5_group_message, &walk);
    if (messages != HDF5_WALK_ON)
    {
        return messages;
    }
    if (walk.table)
    {
        return hdf5_table_links(file, &walk);
    }
    if (walk.dense && !hdf5_undefined(file, walk.dense_heap))
    {
        return hdf5_dense_links(file, &walk);
    }
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_find_link(Hdf5File *file, void *state, const unsigned char *name, size_t name_length,
                               unsigned int link_type, unsigned long long address)
{
    Hdf5Find *const find = (Hdf5Find *)state;
    (void)file;
    if ((name_length != find->length) || (memcmp(name, find->name, name_length) != 0))
    {
        return HDF5_WALK_ON;
    }
    find->found = 1;
    find->link_type = link_type;
    find->address = address;
    return HDF5_WALK_STOPPED;
}

static void hdf5_print_candidate(const char *path, const Hdf5Object *object)
{
    fprintf(stderr, "hdf5: candidate %s extent (", path);
    const unsigned int shown = (object->rank > ENGINE_ARRAY_RANK) ? 0u : object->rank;
    for (unsigned int axis = 0u; axis < shown; axis += 1u)
    {
        fprintf(stderr, "%s%llu", (axis == 0u) ? "" : ", ", object->extent[axis]);
    }
    if (shown == 0u)
    {
        fprintf(stderr, "rank %u", object->rank);
    }
    fprintf(stderr, ")\n");
}

static int hdf5_survey_mark(Hdf5File *file, Hdf5Survey *survey, unsigned long long address)
{
    for (size_t place = 0u; place < survey->seen_count; place += 1u)
    {
        if (survey->seen[place] == address)
        {
            return 1;
        }
    }
    if (survey->seen_count == survey->seen_capacity)
    {
        const size_t grown = (survey->seen_capacity == 0u) ? 64u : (survey->seen_capacity * 2u);
        unsigned long long *const larger =
            (grown <= HDF5_OBJECTS) ? (unsigned long long *)realloc(survey->seen, grown * sizeof(*larger)) : NULL;
        if (larger == NULL)
        {
            return (hdf5_refuse(file, "more objects than the survey holds") - 1);
        }
        survey->seen = larger;
        survey->seen_capacity = grown;
    }
    survey->seen[survey->seen_count] = address;
    survey->seen_count += 1u;
    return 0;
}

static Hdf5Walk hdf5_survey_link(Hdf5File *file, void *state, const unsigned char *name, size_t name_length,
                                 unsigned int link_type, unsigned long long address)
{
    Hdf5Survey *const survey = (Hdf5Survey *)state;
    if (link_type != 0u)
    {
        return HDF5_WALK_ON;
    }
    const int marked = hdf5_survey_mark(file, survey, address);
    if (marked != 0)
    {
        return (marked < 0) ? HDF5_WALK_FAILED : HDF5_WALK_ON;
    }
    const size_t mark = survey->path_length;
    if ((name_length >= HDF5_PATH_CAPACITY) || ((mark + 1u + name_length) >= HDF5_PATH_CAPACITY))
    {
        return hdf5_walk_refuse(file, "a member path longer than the survey holds");
    }
    survey->path[mark] = '/';
    memcpy(&survey->path[mark + 1u], name, name_length);
    survey->path_length = mark + 1u + name_length;
    survey->path[survey->path_length] = '\0';
    Hdf5Object object;
    Hdf5Walk step = hdf5_object_open(file, address, &object) ? HDF5_WALK_ON : HDF5_WALK_FAILED;
    if ((step == HDF5_WALK_ON) && object.has_layout && (object.rank >= 2u))
    {
        survey->candidates += 1u;
        survey->chosen = (survey->candidates == 1u) ? address : survey->chosen;
        if (survey->printing)
        {
            hdf5_print_candidate(survey->path, &object);
        }
    }
    else if ((step == HDF5_WALK_ON) && object.group && !object.has_layout)
    {
        survey->depth += 1u;
        step = (survey->depth > HDF5_GROUP_DEPTH) ? hdf5_walk_refuse(file, "groups nested deeper than the survey goes")
                                                  : hdf5_group_links(file, address, hdf5_survey_link, survey, NULL, 0u);
        survey->depth -= 1u;
    }
    hdf5_object_close(&object);
    survey->path_length = mark;
    survey->path[mark] = '\0';
    return (step == HDF5_WALK_FAILED) ? HDF5_WALK_FAILED : HDF5_WALK_ON;
}

static int hdf5_survey_pass(Hdf5File *file, Hdf5Survey *survey, int printing)
{
    survey->printing = printing;
    survey->candidates = 0u;
    survey->chosen = 0ull;
    survey->depth = 0u;
    survey->path_length = 0u;
    survey->path[0u] = '\0';
    survey->seen_count = 0u;
    return (hdf5_survey_mark(file, survey, file->root) >= 0) &&
           (hdf5_group_links(file, file->root, hdf5_survey_link, survey, NULL, 0u) != HDF5_WALK_FAILED);
}

static int hdf5_survey(Hdf5File *file, unsigned long long *address)
{
    Hdf5Survey *const survey = (Hdf5Survey *)calloc(1u, sizeof(Hdf5Survey));
    if (survey == NULL)
    {
        return hdf5_refuse(file, "no memory for the survey");
    }
    survey->seen = NULL;
    int ok = hdf5_survey_pass(file, survey, 0);
    if (ok && (survey->candidates == 0u))
    {
        ok = hdf5_refuse(file, "no dataset of rank 2 or more in the file");
    }
    if (ok && (survey->candidates > 1u))
    {
        fprintf(stderr, "hdf5: %s holds %u datasets of rank 2 or more; name one:\n", file->path, survey->candidates);
        (void)hdf5_survey_pass(file, survey, 1);
        ok = hdf5_refuse(file, "more than one dataset of rank 2 or more; name the member");
    }
    *address = survey->chosen;
    free(survey->seen);
    free(survey);
    return ok;
}

int hdf5_locate(Hdf5File *file, const char *member, unsigned long long *address)
{
    if (member == NULL)
    {
        return hdf5_survey(file, address);
    }
    unsigned long long current = file->root;
    const size_t length = strlen(member);
    size_t at = 0u;
    while (at < length)
    {
        if (member[at] == '/')
        {
            at += 1u;
            continue;
        }
        size_t end = at;
        while ((end < length) && (member[end] != '/'))
        {
            end += 1u;
        }
        Hdf5Find find = {&member[at], end - at, 0, 0u, 0ull};
        if (hdf5_group_links(file, current, hdf5_find_link, &find, find.name, find.length) == HDF5_WALK_FAILED)
        {
            return 0;
        }
        if (!find.found)
        {
            if (file->reason[0u] == '\0')
            {
                (void)snprintf(file->reason, sizeof(file->reason), "no member named %s", member);
            }
            return 0;
        }
        if (find.link_type != 0u)
        {
            return hdf5_refuse_number(file, "a soft or external link on the member path; link type", find.link_type);
        }
        current = find.address;
        at = end;
    }
    *address = current;
    return 1;
}

static int hdf5_codec_ready(const Hdf5File *file, unsigned int identifier)
{
    const EngineBytesDecode *const decode = file->tools->decode;
    return (identifier == 2u) || (identifier == 3u) || ((identifier == 1u) && (decode[ENGINE_CODEC_ZLIB] != NULL)) ||
           ((identifier == 32001u) && (decode[ENGINE_CODEC_BLOSC] != NULL)) ||
           ((identifier == 32004u) && (decode[ENGINE_CODEC_LZ4] != NULL)) ||
           ((identifier == 32015u) && (decode[ENGINE_CODEC_ZSTD] != NULL));
}

static int hdf5_codec_known(unsigned int identifier)
{
    return (identifier == 1u) || (identifier == 2u) || (identifier == 3u) || (identifier == 32001u) ||
           (identifier == 32004u) || (identifier == 32015u);
}

static int hdf5_chunking_check(Hdf5File *file, const Hdf5Object *object)
{
    const unsigned int rank = object->rank;
    if (object->chunk_rank != (rank + 1u))
    {
        return hdf5_refuse(file, "a chunk rank that does not match the dataspace");
    }
    if (object->chunk[rank] != object->element_bytes)
    {
        return hdf5_refuse(file, "a chunk element size that does not match the datatype");
    }
    unsigned long long chunk_bytes = 0ull;
    if (!hdf5_product(object->chunk, rank + 1u, 1ull, &chunk_bytes) || (chunk_bytes == 0ull) ||
        ((unsigned long long)(size_t)chunk_bytes != chunk_bytes) || (chunk_bytes > HDF5_LARGEST_CHUNK))
    {
        return hdf5_refuse(file, "a chunk of zero size or larger than 4 GiB");
    }
    unsigned long long range = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const int bounded = (object->maximum[axis] != hdf5_all_ones(file->length_bytes)) &&
                            (object->maximum[axis] >= object->extent[axis]);
        const unsigned long long cells = bounded
                                             ? ((object->maximum[axis] / object->chunk[axis]) +
                                                (((object->maximum[axis] % object->chunk[axis]) != 0ull) ? 1ull : 0ull))
                                             : 1ull;
        if (((object->chunk_index == HDF5_INDEX_FIXED) || (object->chunk_index == HDF5_INDEX_IMPLICIT)) &&
            (!bounded || ((cells != 0ull) && (range > (~0ull / cells)))))
        {
            return hdf5_refuse(file, "an unlimited or impossible dimension on a fixed-size chunk index");
        }
        range *= (cells != 0ull) ? cells : 1ull;
        if ((object->chunk_index == HDF5_INDEX_SINGLE) && (object->chunk[axis] < object->extent[axis]))
        {
            return hdf5_refuse(file, "a single-chunk index whose chunk is smaller than the dataset");
        }
    }
    if ((object->chunk_index == HDF5_INDEX_IMPLICIT) && (object->filter_count > 0u))
    {
        return hdf5_refuse(file, "a filtered dataset on the implicit chunk index");
    }
    if ((object->chunk_index == HDF5_INDEX_SINGLE) && (object->filter_count > 0u) && ((object->chunk_flags & 2u) == 0u))
    {
        return hdf5_refuse(file, "a filtered single chunk with no stored size");
    }
    for (unsigned int place = 0u; place < object->filter_count; place += 1u)
    {
        const unsigned int identifier = object->filters[place].identifier;
        if (!hdf5_codec_known(identifier))
        {
            return hdf5_refuse_number(file, "an unsupported filter; filter", identifier);
        }
        if (!hdf5_codec_ready(file, identifier))
        {
            return hdf5_refuse_number(file, "a filter whose decoder slot is empty; filter", identifier);
        }
    }
    return 1;
}

int hdf5_dataset_check(Hdf5File *file, const Hdf5Object *object)
{
    if (object->unsupported[0u] != '\0')
    {
        return hdf5_refuse(file, object->unsupported);
    }
    if (!object->has_layout || !object->has_space || !object->has_type)
    {
        return hdf5_refuse(file,
                           object->group ? "the member is a group, not a dataset" : "the member is not a dataset");
    }
    if (object->external)
    {
        return hdf5_refuse(file, "a dataset stored in external data files");
    }
    if (object->rank == 0u)
    {
        return hdf5_refuse(file, "a scalar or null dataspace; there is no axis 0");
    }
    const unsigned long long fill_bytes = object->has_fill ? object->fill_bytes : object->old_fill_bytes;
    if ((fill_bytes != 0ull) && (fill_bytes != object->element_bytes))
    {
        return hdf5_refuse(file, "a fill value whose size is not the element size");
    }
    unsigned long long total = 0ull;
    if (!hdf5_product(object->extent, object->rank, object->element_bytes, &total))
    {
        return hdf5_refuse(file, "a dataset whose byte size overflows");
    }
    if ((object->layout_class != 2u) && (object->filter_count > 0u))
    {
        return hdf5_refuse(file, "a filter pipeline on an unchunked dataset");
    }
    if (object->layout_class == 0u)
    {
        return (object->data_bytes >= total) ? 1 : hdf5_refuse(file, "compact data shorter than the dataset");
    }
    if (object->layout_class == 1u)
    {
        return (hdf5_undefined(file, object->data_address) || (object->data_bytes >= total))
                   ? 1
                   : hdf5_refuse(file, "contiguous data shorter than the dataset");
    }
    return hdf5_chunking_check(file, object);
}
