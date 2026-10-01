// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_zarr.cu: zarr v2 and v3, n5, and their description
#include "engine_internal.h"

static int entry_zarr_v3_chain(const EntryJson *json, unsigned int codecs, ZarrLayout *layout, int inner)
{
    ZarrChain *const chain = (inner != 0) ? &layout->inner_chain : &layout->chain;
    if ((codecs == 0u) || (json->tokens[codecs].kind != CFG_JSON_ARRAY))
    {
        return 0;
    }
    const unsigned int rank = layout->extent.rank;
    int bytes_seen = 0;
    for (unsigned int slot = 0u; slot < json->tokens[codecs].count; slot += 1u)
    {
        const unsigned int codec = entry_json_element(json, codecs, slot);
        const unsigned int configuration = entry_json_at(json, codec, "configuration");
        char name[64];
        if ((entry_json_text(json, entry_json_at(json, codec, "name"), name, sizeof(name)) == 0) ||
            (chain->crc32c != 0u))
        {
            fprintf(stderr, "  zarr: a codec is unnamed, or follows crc32c\n");
            return 0;
        }
        if (strcmp(name, "bytes") == 0)
        {
            char endian[16] = "little";
            const unsigned int stated = entry_json_at(json, configuration, "endian");
            if ((stated != 0u) && (entry_json_text(json, stated, endian, sizeof(endian)) == 0))
            {
                return 0;
            }
            layout->big_endian = (strcmp(endian, "big") == 0) ? 1u : 0u;
            bytes_seen = 1;
        }
        else if (strcmp(name, "transpose") == 0)
        {
            unsigned long long order[ENGINE_ARRAY_RANK];
            unsigned int count = 0u;
            if ((bytes_seen != 0) ||
                (entry_json_list(json, entry_json_at(json, configuration, "order"), order, &count, ENGINE_ARRAY_RANK) ==
                 0) ||
                (count != rank))
            {
                fprintf(stderr, "  zarr: transpose is supported only as an order list before bytes\n");
                return 0;
            }
            for (unsigned int axis = 0u; axis < rank; axis += 1u)
            {
                layout->order[axis] = (unsigned int)order[axis];
            }
        }
        else if (strcmp(name, "sharding_indexed") == 0)
        {
            unsigned int count = 0u;
            if ((inner != 0) || (slot != 0u) ||
                (entry_json_list(json, entry_json_at(json, configuration, "chunk_shape"), layout->inner, &count,
                                 ENGINE_ARRAY_RANK) == 0) ||
                (count != rank) ||
                (entry_zarr_v3_chain(json, entry_json_at(json, configuration, "codecs"), layout, 1) == 0))
            {
                fprintf(stderr, "  zarr: sharding_indexed is supported only as the first codec, with its own chain\n");
                return 0;
            }
            layout->sharded = 1u;
            const unsigned int index = entry_json_at(json, configuration, "index_codecs");
            for (unsigned int element = 0u; (index != 0u) && (element < json->tokens[index].count); element += 1u)
            {
                const unsigned int step = entry_json_element(json, index, element);
                char step_name[64];
                char endian[16] = "little";
                if (entry_json_text(json, entry_json_at(json, step, "name"), step_name, sizeof(step_name)) == 0)
                {
                    return 0;
                }
                const unsigned int stated = entry_json_at(json, entry_json_at(json, step, "configuration"), "endian");
                if ((strcmp(step_name, "bytes") == 0) && (stated != 0u) &&
                    entry_json_text(json, stated, endian, sizeof(endian)))
                {
                    layout->index_big_endian = (strcmp(endian, "big") == 0) ? 1u : 0u;
                }
                layout->index_chain.crc32c |= (strcmp(step_name, "crc32c") == 0) ? 1u : 0u;
                layout->index_chain.count +=
                    ((strcmp(step_name, "bytes") != 0) && (strcmp(step_name, "crc32c") != 0)) ? 1u : 0u;
            }
            char location[16] = "end";
            const unsigned int placed = entry_json_at(json, configuration, "index_location");
            if ((placed != 0u) && (entry_json_text(json, placed, location, sizeof(location)) == 0))
            {
                return 0;
            }
            layout->index_at_start = (strcmp(location, "start") == 0) ? 1u : 0u;
            bytes_seen = 1;
        }
        else if (strcmp(name, "crc32c") == 0)
        {
            chain->crc32c = 1u;
        }
        else
        {
            EngineCodec byte_codec = ENGINE_CODEC_RAW;
            if ((bytes_seen == 0) || (entry_codec_named(name, &byte_codec) == 0) || (chain->count >= ZARR_CODECS))
            {
                fprintf(stderr, "  zarr: the codec %s is not supported here\n", name);
                return 0;
            }
            chain->codec[chain->count] = byte_codec;
            chain->count += 1u;
        }
    }
    return bytes_seen;
}

static void entry_fill(const EntryJson *json, unsigned int token, ZarrLayout *layout)
{
    unsigned long long value = 0ull;
    const int counted = (token != 0u) && cfg_json_unsigned(json->text, &json->tokens[token], &value);
    for (unsigned int place = 0u; place < 8u; place += 1u)
    {
        layout->fill[place] = (counted != 0) ? (unsigned char)((value >> (8u * place)) & 0xFFull) : 0u;
    }
}

static int entry_zarr_v3(const EntryJson *json, ZarrLayout *layout)
{
    unsigned int rank = 0u;
    char type[32];
    if ((entry_json_list(json, entry_json_at(json, 0u, "shape"), layout->extent.sizes, &rank, ENGINE_ARRAY_RANK) ==
         0) ||
        (rank == 0u) || (entry_json_text(json, entry_json_at(json, 0u, "data_type"), type, sizeof(type)) == 0) ||
        (entry_element_named(type, &layout->extent, &layout->big_endian) == 0))
    {
        fprintf(stderr, "  zarr: the array's shape or data type is not supported\n");
        return 0;
    }
    layout->extent.rank = rank;
    unsigned int chunk_rank = 0u;
    const unsigned int grid = entry_json_at(json, entry_json_at(json, 0u, "chunk_grid"), "configuration");
    if ((entry_json_list(json, entry_json_at(json, grid, "chunk_shape"), layout->chunk, &chunk_rank,
                         ENGINE_ARRAY_RANK) == 0) ||
        (chunk_rank != rank))
    {
        fprintf(stderr, "  zarr: only a regular chunk grid is held\n");
        return 0;
    }
    const unsigned int encoding = entry_json_at(json, 0u, "chunk_key_encoding");
    char encoding_name[16] = "default";
    char separator[4] = "";
    entry_json_text(json, entry_json_at(json, encoding, "name"), encoding_name, sizeof(encoding_name));
    const int split =
        entry_json_text(json, entry_json_at(json, entry_json_at(json, encoding, "configuration"), "separator"),
                        separator, sizeof(separator));
    layout->prefixed = (strcmp(encoding_name, "v2") == 0) ? 0u : 1u;
    layout->separator = (split != 0) ? separator[0] : ((layout->prefixed != 0u) ? '/' : '.');
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->order[axis] = axis;
    }
    entry_fill(json, entry_json_at(json, 0u, "fill_value"), layout);
    layout->format = ZARR_FORMAT_V3;
    const int chained = entry_zarr_v3_chain(json, entry_json_at(json, 0u, "codecs"), layout, 0);
    if ((chained == 0) || ((layout->sharded != 0u) && ((layout->chain.count != 0u) || (layout->chain.crc32c != 0u))))
    {
        fprintf(stderr, "  zarr: the codec chain is not supported\n");
        return 0;
    }
    return 1;
}

static int entry_zarr_v2(const EntryJson *json, ZarrLayout *layout)
{
    unsigned int rank = 0u;
    unsigned int chunk_rank = 0u;
    char type[32];
    if ((entry_json_list(json, entry_json_at(json, 0u, "shape"), layout->extent.sizes, &rank, ENGINE_ARRAY_RANK) ==
         0) ||
        (rank == 0u) ||
        (entry_json_list(json, entry_json_at(json, 0u, "chunks"), layout->chunk, &chunk_rank, ENGINE_ARRAY_RANK) ==
         0) ||
        (chunk_rank != rank) || (entry_json_text(json, entry_json_at(json, 0u, "dtype"), type, sizeof(type)) == 0) ||
        (entry_element_named(type, &layout->extent, &layout->big_endian) == 0))
    {
        fprintf(stderr, "  zarr: the v2 array's shape, chunks or dtype is not supported\n");
        return 0;
    }
    layout->extent.rank = rank;
    const unsigned int filters = entry_json_at(json, 0u, "filters");
    if ((filters != 0u) && (json->tokens[filters].kind != CFG_JSON_NULL) &&
        !((json->tokens[filters].kind == CFG_JSON_ARRAY) && (json->tokens[filters].count == 0u)))
    {
        fprintf(stderr, "  zarr: v2 filters are not supported\n");
        return 0;
    }
    const unsigned int compressor = entry_json_at(json, 0u, "compressor");
    if ((compressor != 0u) && (json->tokens[compressor].kind == CFG_JSON_OBJECT))
    {
        char name[32];
        EngineCodec codec = ENGINE_CODEC_RAW;
        if ((entry_json_text(json, entry_json_at(json, compressor, "id"), name, sizeof(name)) == 0) ||
            (entry_codec_named(name, &codec) == 0))
        {
            fprintf(stderr, "  zarr: the v2 compressor is not supported\n");
            return 0;
        }
        layout->chain.codec[0] = codec;
        layout->chain.count = 1u;
    }
    char order[4] = "C";
    entry_json_text(json, entry_json_at(json, 0u, "order"), order, sizeof(order));
    char separator[4] = ".";
    entry_json_text(json, entry_json_at(json, 0u, "dimension_separator"), separator, sizeof(separator));
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->order[axis] = (order[0] == 'F') ? (rank - 1u - axis) : axis;
    }
    layout->separator = separator[0];
    layout->prefixed = 0u;
    entry_fill(json, entry_json_at(json, 0u, "fill_value"), layout);
    layout->format = ZARR_FORMAT_V2;
    return 1;
}

static int entry_n5(const EntryJson *json, ZarrLayout *layout)
{
    unsigned long long dimensions[ENGINE_ARRAY_RANK];
    unsigned long long blocks[ENGINE_ARRAY_RANK];
    unsigned int rank = 0u;
    unsigned int block_rank = 0u;
    char type[32];
    unsigned int ignored = 0u;
    if ((entry_json_list(json, entry_json_at(json, 0u, "dimensions"), dimensions, &rank, ENGINE_ARRAY_RANK) == 0) ||
        (rank == 0u) ||
        (entry_json_list(json, entry_json_at(json, 0u, "blockSize"), blocks, &block_rank, ENGINE_ARRAY_RANK) == 0) ||
        (block_rank != rank) || (entry_json_text(json, entry_json_at(json, 0u, "dataType"), type, sizeof(type)) == 0) ||
        (entry_element_named(type, &layout->extent, &ignored) == 0))
    {
        fprintf(stderr, "  n5: the dataset's dimensions, blockSize or dataType is not supported\n");
        return 0;
    }
    layout->extent.rank = rank;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->extent.sizes[axis] = dimensions[rank - 1u - axis];
        layout->chunk[axis] = blocks[rank - 1u - axis];
        layout->order[axis] = axis;
    }
    const unsigned int compression = entry_json_at(json, 0u, "compression");
    char kind[32] = "raw";
    if (compression != 0u)
    {
        entry_json_text(json, entry_json_at(json, compression, "type"), kind, sizeof(kind));
    }
    else
    {
        entry_json_text(json, entry_json_at(json, 0u, "compressionType"), kind, sizeof(kind));
    }
    const unsigned int zlib = entry_json_at(json, compression, "useZlib");
    if (strcmp(kind, "gzip") == 0)
    {
        layout->chain.codec[0] =
            ((zlib != 0u) && (json->tokens[zlib].kind == CFG_JSON_TRUE)) ? ENGINE_CODEC_ZLIB : ENGINE_CODEC_GZIP;
        layout->chain.count = 1u;
    }
    else if ((strcmp(kind, "blosc") == 0) || (strcmp(kind, "zstd") == 0))
    {
        layout->chain.codec[0] = (kind[0] == 'b') ? ENGINE_CODEC_BLOSC : ENGINE_CODEC_ZSTD;
        layout->chain.count = 1u;
    }
    else if (strcmp(kind, "raw") != 0)
    {
        fprintf(stderr, "  n5: the compression %s is not supported\n", kind);
        return 0;
    }
    layout->big_endian = 1u;
    layout->separator = '/';
    layout->prefixed = 0u;
    layout->format = ZARR_FORMAT_N5;
    const unsigned int axes = entry_json_at(json, 0u, "axes");
    for (unsigned int slot = 0u; (axes != 0u) && (json->tokens[axes].count == rank) && (slot < rank); slot += 1u)
    {
        char name[32];
        layout->extent.axes[rank - 1u - slot] =
            entry_json_text(json, entry_json_element(json, axes, slot), name, sizeof(name)) ? entry_axis_named(name)
                                                                                            : '\0';
    }
    return 1;
}

int entry_zarr_describe(const char *root, const char *member, ZarrLayout *layout, char *array_root, size_t capacity)
{
    memset(layout, 0, sizeof(*layout));
    char path[ENTRY_PATH_CAPACITY];
    EntryJson json;
    memset(&json, 0, sizeof(json));
    EntryOme ome;
    memset(&ome, 0, sizeof(ome));
    int ok = 0;
    if (entry_joined(path, sizeof(path), root, "zarr.json") && entry_json_load(path, &json))
    {
        char node[16] = "";
        entry_json_text(&json, entry_json_at(&json, 0u, "node_type"), node, sizeof(node));
        const int group = (strcmp(node, "group") == 0);
        const int described = group ? entry_ome(&json, entry_json_at(&json, 0u, "attributes"), &ome) : 0;
        const char *const leaf = (member != NULL) ? member : (described ? ome.path : NULL);
        entry_json_release(&json);
        if (group && (leaf == NULL))
        {
            fprintf(stderr, "  %s: a group with no multiscales; name the array\n", root);
            return 0;
        }
        ok = (group ? entry_joined(array_root, capacity, root, leaf) : entry_joined(array_root, capacity, root, ".")) &&
             entry_joined(path, sizeof(path), array_root, "zarr.json") && entry_json_load(path, &json);
        ok = ok && entry_zarr_v3(&json, layout);
        if (ok)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, ".zarray") && entry_exists(path))
    {
        ok = entry_joined(array_root, capacity, root, ".") && entry_json_load(path, &json);
        ok = ok && entry_zarr_v2(&json, layout);
        if (ok)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, ".zgroup") && entry_exists(path))
    {
        const int attributed = entry_joined(path, sizeof(path), root, ".zattrs") && entry_json_load(path, &json);
        const int described = attributed && entry_ome(&json, 0u, &ome);
        if (attributed)
        {
            entry_json_release(&json);
        }
        const char *const leaf = (member != NULL) ? member : (described ? ome.path : NULL);
        ok = (leaf != NULL) && entry_joined(array_root, capacity, root, leaf) &&
             entry_joined(path, sizeof(path), array_root, ".zarray") && entry_json_load(path, &json);
        ok = ok && entry_zarr_v2(&json, layout);
        if (ok)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, "attributes.json") && entry_json_load(path, &json))
    {
        const int dataset = (entry_json_at(&json, 0u, "dimensions") != 0u);
        entry_json_release(&json);
        const char *const leaf = (member != NULL) ? member : (dataset ? "." : "s0");
        ok = entry_joined(array_root, capacity, root, leaf) &&
             entry_joined(path, sizeof(path), array_root, "attributes.json") && entry_json_load(path, &json);
        ok = ok && entry_n5(&json, layout);
        if (ok)
        {
            entry_json_release(&json);
        }
    }
    if (ok == 0)
    {
        entry_json_release(&json);
        return 0;
    }
    for (unsigned int axis = 0u; (ome.rank == layout->extent.rank) && (axis < ome.rank); axis += 1u)
    {
        layout->extent.axes[axis] = ome.axes[axis];
    }
    return 1;
}
