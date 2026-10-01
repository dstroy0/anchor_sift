// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_listing.cu: the listing, geff arrays, lanes and the iapx codec
#include "engine_internal.h"

static int entry_order_names(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static unsigned int entry_listing(const char *directory, char ***names, int samples_of_set)
{
    std::vector<char *> found;
#ifdef _WIN32
    char pattern[ENTRY_PATH_CAPACITY];
    snprintf(pattern, sizeof(pattern), "%s/*", directory);
    struct __finddata64_t entry;
    const intptr_t search = _findfirst64(pattern, &entry);
    for (int more = (search != -1) ? 0 : -1; more == 0; more = _findnext64(search, &entry))
    {
        const char *const name = entry.name;
#else
    DIR *const search = opendir(directory);
    for (struct dirent *entry = (search != NULL) ? readdir(search) : NULL; entry != NULL; entry = readdir(search))
    {
        const char *const name = entry->d_name;
#endif
        if (name[0] == '.')
        {
            continue;
        }
        char stem[ENTRY_PATH_CAPACITY];
        snprintf(stem, sizeof(stem), "%s", name);
        int kept = 0;
        if (samples_of_set != 0)
        {
            char character[ENTRY_PATH_CAPACITY];
            kept = engine_sample_path(character, sizeof(character), directory, name, ENTRY_CRYSTAL_SUFFIX) &&
                   entry_exists(character);
        }
        for (unsigned int suffix = 0u; (samples_of_set == 0) && (kept == 0) && (suffix < ENTRY_SOURCE_SUFFIX_COUNT);
             suffix += 1u)
        {
            if (entry_ends(stem, ENTRY_SOURCE_SUFFIXES[suffix]))
            {
                stem[strlen(stem) - strlen(ENTRY_SOURCE_SUFFIXES[suffix])] = '\0';
                kept = 1;
            }
        }
        if (kept != 0)
        {
            const size_t size = strlen(stem) + 1u;
            char *const copy = (char *)malloc(size);
            if (copy != NULL)
            {
                memcpy(copy, stem, size);
                found.push_back(copy);
            }
        }
    }
#ifdef _WIN32
    if (search != -1)
    {
        _findclose(search);
    }
#else
    if (search != NULL)
    {
        closedir(search);
    }
#endif
    char **const listed = (char **)calloc(found.size() + 1u, sizeof(char *));
    if (listed == NULL)
    {
        for (size_t slot = 0u; slot < found.size(); slot += 1u)
        {
            free(found[slot]);
        }
        *names = NULL;
        return 0u;
    }
    for (size_t slot = 0u; slot < found.size(); slot += 1u)
    {
        listed[slot] = found[slot];
    }
    qsort(listed, found.size(), sizeof(char *), entry_order_names);
    *names = listed;
    return (unsigned int)found.size();
}

extern "C" unsigned int engine_source_samples(const char *source, char ***names)
{
    return entry_listing(source, names, 0);
}

extern "C" unsigned int engine_set_samples(const char *set, char ***names)
{
    return entry_listing(set, names, 1);
}

static long long entry_geff_array(const char *root, const char *leaf, unsigned long long want_rank,
                                  unsigned long long *rows, unsigned char **bytes)
{
    char path[ENTRY_PATH_CAPACITY];
    char array_root[ENTRY_PATH_CAPACITY];
    ZarrLayout layout;
    *bytes = NULL;
    if ((entry_joined(path, sizeof(path), root, leaf) == 0) ||
        (entry_zarr_describe(path, NULL, &layout, array_root, sizeof(array_root)) == 0) ||
        (layout.extent.rank != want_rank) || (layout.extent.element_bytes != 8u) ||
        (layout.extent.element_kind == ENGINE_ELEMENT_FLOAT))
    {
        fprintf(stderr, "  %s/%s: not an 8 byte integer array of rank %llu\n", root, leaf, want_rank);
        return -1ll;
    }
    unsigned long long elements = 1ull;
    for (unsigned int axis = 0u; axis < layout.extent.rank; axis += 1u)
    {
        elements *= layout.extent.sizes[axis];
    }
    *rows = layout.extent.sizes[0];
    unsigned char *const out = (unsigned char *)malloc((size_t)(elements * 8ull) + 8u);
    ZarrReadRequest read;
    read.root = array_root;
    read.layout = &layout;
    read.tools = entry_ingest_tools();
    read.first = 0ull;
    read.end = layout.extent.sizes[0];
    read.out = out;
    read.out_capacity = elements * 8ull;
    if ((out == NULL) || ((elements != 0ull) && (zarr_read(&read) != (long long)(elements * 8ull))))
    {
        free(out);
        return -1ll;
    }
    *bytes = out;
    return (long long)elements;
}

extern "C" void engine_geff_release(EngineGeff *geff)
{
    free(geff->node_identity);
    free(geff->node_place);
    free(geff->edge_ends);
    memset(geff, 0, sizeof(*geff));
}

extern "C" long engine_geff_read(const char *path, EngineGeff *geff)
{
    memset(geff, 0, sizeof(*geff));
    static const char *const PLACES[4] = {"nodes/props/t/values", "nodes/props/z/values", "nodes/props/y/values",
                                          "nodes/props/x/values"};
    unsigned long long rows = 0ull;
    unsigned char *ids = NULL;
    unsigned char *edges = NULL;
    unsigned char *places[4] = {NULL, NULL, NULL, NULL};
    int ok = (entry_geff_array(path, "nodes/ids", 1ull, &geff->nodes, &ids) >= 0ll);
    for (unsigned int axis = 0u; ok && (axis < 4u); axis += 1u)
    {
        ok = (entry_geff_array(path, PLACES[axis], 1ull, &rows, &places[axis]) >= 0ll) && (rows == geff->nodes);
    }
    ok = ok && (entry_geff_array(path, "edges/ids", 2ull, &geff->edges, &edges) >= 0ll);
    geff->node_identity =
        ok ? (unsigned long long *)malloc((size_t)(geff->nodes + 1ull) * sizeof(unsigned long long)) : NULL;
    geff->node_place = ok ? (long long *)malloc((size_t)(geff->nodes + 1ull) * 4u * sizeof(long long)) : NULL;
    ok = ok && (geff->node_identity != NULL) && (geff->node_place != NULL);
    for (unsigned long long node = 0ull; ok && (node < geff->nodes); node += 1ull)
    {
        memcpy(&geff->node_identity[node], &ids[8ull * node], 8u);
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            memcpy(&geff->node_place[(4ull * node) + axis], &places[axis][8ull * node], 8u);
        }
    }
    if (ok)
    {
        geff->edge_ends = (unsigned long long *)edges;
        edges = NULL;
    }
    free(ids);
    free(edges);
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        free(places[axis]);
    }
    if (ok == 0)
    {
        engine_geff_release(geff);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" long engine_iapx_head(const char *set, const char *sample, unsigned long long extent[4], EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    char path[ENTRY_PATH_CAPACITY];
    EngineStream stream;
    memset(&stream, 0, sizeof(stream));
    if ((ENGINE_CHECK(engine_sample_path(path, sizeof(path), set, sample, ENTRY_CRYSTAL_SUFFIX) != 0, sample, error,
                      ENGINE_ERROR_REQUEST) == 0) ||
        (apxrep_input_head(path, &stream, NULL, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    memcpy(extent, stream.extent, sizeof(stream.extent));
    return 0L;
}

unsigned long long entry_lanes(const unsigned long long extent[4])
{
    unsigned long long lanes = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        if ((extent[axis] == 0ull) || (extent[axis] > (1ull << 40u)) || (lanes > ((1ull << 40u) / extent[axis])))
        {
            return 0ull;
        }
        lanes *= extent[axis];
    }
    return lanes;
}

int entry_iapx_decode(const EngineStream *stream, const unsigned short *device_lanes, unsigned short *rebuilt,
                      unsigned long long *mismatches, const unsigned short **device_rebuilt, EngineError *error)
{
    int *coefficients = NULL;
    if (tower_capacity(stream->extent, &coefficients, error) != 0L)
    {
        return 0;
    }
    CompressionDecodeRequest code;
    memset(&code, 0, sizeof(code));
    code.offsets = stream->offsets;
    code.chunks = stream->chunks;
    code.stream = stream->stream;
    code.bits = stream->bits;
    code.count = entry_lanes(stream->extent);
    code.device_coefficients = coefficients;
    code.error = error;
    if (compression_decode(&code) != 0L)
    {
        return 0;
    }
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    lower.device_lanes = device_lanes;
    memcpy(lower.extent, stream->extent, sizeof(lower.extent));
    lower.mismatches = mismatches;
    lower.device_rebuilt = device_rebuilt;
    lower.rebuilt = rebuilt;
    lower.error = error;
    return (tower_lower(&lower) == 0L) ? 1 : 0;
}

int entry_iapx_encode(const unsigned short *device_lanes, const unsigned long long extent[4], EngineStream *stream,
                      unsigned int *floors, EngineError *error)
{
    memset(stream, 0, sizeof(*stream));
    memcpy(stream->extent, extent, sizeof(stream->extent));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = device_lanes;
    memcpy(lift.extent, extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = floors;
    lift.error = error;
    if (tower_lift(&lift) != 0L)
    {
        return 0;
    }
    CompressionEncodeRequest code;
    memset(&code, 0, sizeof(code));
    code.device_coefficients = coefficients;
    code.count = entry_lanes(extent);
    code.device_scratch = scratch;
    code.chunks = &stream->chunks;
    code.bits = &stream->bits;
    code.offsets = &stream->offsets;
    code.stream = &stream->stream;
    code.error = error;
    return (compression_encode(&code) == 0L) ? 1 : 0;
}

extern "C" long engine_lattice_bits(const int *values, const unsigned long long extent[4], unsigned long long *bits,
                                    EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    const unsigned long long lanes = (extent != NULL) ? entry_lanes(extent) : 0ull;
    int *device_values = NULL;
    int ok =
        ENGINE_CHECK((values != NULL) && (bits != NULL) && (lanes != 0ull), &values, error, ENGINE_ERROR_REQUEST) &&
        ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_values, (size_t)lanes * sizeof(int)), &device_values, error) &&
        ENGINE_STATUS_CHECK(cudaMemcpy(device_values, values, (size_t)lanes * sizeof(int), cudaMemcpyHostToDevice),
                            device_values, error);
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    if (ok != 0)
    {
        TowerLiftRequest lift;
        memset(&lift, 0, sizeof(lift));
        lift.device_values = device_values;
        memcpy(lift.extent, extent, sizeof(lift.extent));
        lift.coefficients = &coefficients;
        lift.scratch = &scratch;
        lift.floors = &floors;
        lift.error = error;
        ok = tower_lift(&lift) == 0L;
    }
    if (ok != 0)
    {
        // the offsets and the stream are compression's own, kept for its next call; only the bits are kept
        EngineStream stream;
        memset(&stream, 0, sizeof(stream));
        CompressionEncodeRequest code;
        memset(&code, 0, sizeof(code));
        code.device_coefficients = coefficients;
        code.count = lanes;
        code.device_scratch = scratch;
        code.chunks = &stream.chunks;
        code.bits = bits;
        code.offsets = &stream.offsets;
        code.stream = &stream.stream;
        code.error = error;
        ok = compression_encode(&code) == 0L;
    }
    cudaFree(device_values);
    if (ok == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}
