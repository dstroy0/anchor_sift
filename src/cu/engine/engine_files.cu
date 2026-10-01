// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_files.cu: directories, decoders and the JSON reader of an entry
#include "engine_internal.h"

static int entry_directory_end(const char *walk, size_t at, size_t length, int include_last)
{
    const int separator = (walk[at] == '/') || (walk[at] == '\\');
    const int last = (at == length) && (include_last != 0);
    const int drive = (at == 2u) && (walk[1] == ':');
    return ((separator != 0) || (last != 0)) && (drive == 0);
}

int entry_directories_make(const char *path, int include_last, unsigned int *made)
{
    *made = 0u;
    const size_t length = strlen(path);
    char *const walk = (char *)malloc(length + 1u);
    if (walk == NULL)
    {
        return 0;
    }
    memcpy(walk, path, length + 1u);
    int ok = 1;
    for (size_t at = 1u; ok && (at <= length); at += 1u)
    {
        if (entry_directory_end(walk, at, length, include_last) == 0)
        {
            continue;
        }
        const char character = walk[at];
        walk[at] = '\0';
        const int created = ENGINE_DIRECTORY_MAKE(walk) == 0;
        ok = created || (errno == EEXIST);
        *made += created ? 1u : 0u;
        walk[at] = character;
    }
    free(walk);
    return ok;
}

void entry_directories_remove(const char *path, int include_last, unsigned int made)
{
    if (made == 0u)
    {
        return;
    }
    const size_t length = strlen(path);
    char *const walk = (char *)malloc(length + 1u);
    if (walk == NULL)
    {
        return;
    }
    memcpy(walk, path, length + 1u);
    unsigned int left = made;
    for (size_t at = length; (left != 0u) && (at >= 1u); at -= 1u)
    {
        if (entry_directory_end(walk, at, length, include_last) == 0)
        {
            continue;
        }
        walk[at] = '\0';
        ENGINE_DIRECTORY_REMOVE(walk);
        left -= 1u;
    }
    free(walk);
}

extern "C" int engine_directories_make(const char *path, int include_last)
{
    unsigned int made = 0u;
    return entry_directories_make(path, include_last, &made);
}

extern "C" int engine_program_directory(char *out, size_t capacity)
{
    if ((out == NULL) || (capacity < 2u))
    {
        return 0;
    }
#ifdef _WIN32
    // the capacity is a buffer size the caller holds, which a DWORD counts on every Windows target
    const DWORD written = GetModuleFileNameA(NULL, out, (DWORD)capacity);
    const size_t length = (size_t)written;
#else
    const ssize_t written = readlink("/proc/self/exe", out, capacity - 1u);
    // a failed read is -1 and is held as no length at all
    const size_t length = (written > 0) ? (size_t)written : 0u;
#endif
    size_t directory_length = (length < capacity) ? length : 0u;
    out[directory_length] = '\0';
    while ((directory_length != 0u) && (out[directory_length - 1u] != '/') && (out[directory_length - 1u] != '\\'))
    {
        directory_length -= 1u;
    }
    if (directory_length == 0u)
    {
        out[0] = '\0';
        return 0;
    }
    out[directory_length - 1u] = '\0';
    return 1;
}

extern "C" int engine_sample_path(char *out, size_t capacity, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(out, capacity, "%s/%s/%s%s", set, sample, sample, suffix);
    return (written > 0) && ((size_t)written < capacity);
}

static long long entry_raw_decode(const EngineBytesRequest *request)
{
    if ((request == NULL) || (request->in_bytes > request->out_capacity))
    {
        return ENGINE_BYTES_ERROR;
    }
    memcpy(request->out, request->in, (size_t)request->in_bytes);
    return (long long)request->in_bytes;
}

static EngineIngestTools s_ingest_tools;

static long long entry_blosc_decode(const EngineBytesRequest *request)
{
    BloscDecodeRequest blosc;
    blosc.bytes = *request;
    blosc.decode = s_ingest_tools.decode;
    return blosc_decode(&blosc);
}

const EngineIngestTools *entry_ingest_tools(void)
{
    EngineIngestTools *const tools = &s_ingest_tools;
    tools->decode[ENGINE_CODEC_RAW] = entry_raw_decode;
    tools->decode[ENGINE_CODEC_ZSTD] = zstd_decode;
    tools->decode[ENGINE_CODEC_ZLIB] = inflate_zlib_decode;
    tools->decode[ENGINE_CODEC_GZIP] = inflate_gzip_decode;
    tools->decode[ENGINE_CODEC_DEFLATE] = inflate_raw_decode;
    tools->decode[ENGINE_CODEC_LZ4] = lz4_block_decode;
    tools->decode[ENGINE_CODEC_LZ4_FRAME] = lz4_frame_decode;
    tools->decode[ENGINE_CODEC_SNAPPY] = snappy_decode;
    tools->decode[ENGINE_CODEC_BLOSCLZ] = blosclz_decode;
    tools->decode[ENGINE_CODEC_BLOSC] = entry_blosc_decode;
    tools->decode[ENGINE_CODEC_LZ4_SIZED] = lz4_numcodecs_decode;
    tools->read = stack_file_read;
    tools->size = stack_file_size;
    return tools;
}

int entry_exists(const char *path)
{
#ifdef _WIN32
    return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
#else
    struct stat status;
    return stat(path, &status) == 0;
#endif
}

int entry_is_file(const char *path)
{
#ifdef _WIN32
    const DWORD attributes = GetFileAttributesA(path);
    return (attributes != INVALID_FILE_ATTRIBUTES) && ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0u);
#else
    struct stat status;
    return (stat(path, &status) == 0) && S_ISREG(status.st_mode);
#endif
}

int entry_joined(char *out, size_t capacity, const char *root, const char *leaf)
{
    const int written = snprintf(out, capacity, "%s/%s", root, leaf);
    return (written > 0) && ((size_t)written < capacity);
}

void entry_json_release(EntryJson *json)
{
    free(json->text);
    free(json->tokens);
    memset(json, 0, sizeof(*json));
}

static int entry_file_read_all(const char *path, char **bytes, size_t *length)
{
    const long long size = stack_file_size(path);
    if (size < 0ll)
    {
        return 0;
    }
    char *const text = (char *)malloc((size_t)size + 1u);
    EngineFileRange range;
    range.path = path;
    range.offset = 0ull;
    range.bytes = (unsigned long long)size;
    range.out = (unsigned char *)text;
    if ((text == NULL) || (stack_file_read(&range) != size))
    {
        free(text);
        return 0;
    }
    text[size] = '\0';
    *bytes = text;
    *length = (size_t)size;
    return 1;
}

int entry_json_load(const char *path, EntryJson *json)
{
    memset(json, 0, sizeof(*json));
    if (entry_file_read_all(path, &json->text, &json->length) == 0)
    {
        return 0;
    }
    const unsigned int capacity = (unsigned int)(json->length / 2u) + 4u;
    json->tokens = (CfgJsonToken *)malloc((size_t)capacity * sizeof(CfgJsonToken));
    CfgJsonParse parse;
    memset(&parse, 0, sizeof(parse));
    const int ok = (json->tokens != NULL) &&
                   cfg_json_parse_metadata(json->text, json->length, json->tokens, capacity, &parse) &&
                   (json->tokens[0].kind == CFG_JSON_OBJECT);
    if (ok == 0)
    {
        fprintf(stderr, "  %s: %s\n", path, (parse.reason != NULL) ? parse.reason : "not one JSON object");
        entry_json_release(json);
        return 0;
    }
    json->count = parse.tokens;
    return 1;
}

unsigned int entry_json_at(const EntryJson *json, unsigned int object, const char *name)
{
    const int ok = (object < json->count) && (json->tokens[object].kind == CFG_JSON_OBJECT);
    return (ok != 0) ? cfg_json_member(json->text, json->tokens, object, name) : 0u;
}

unsigned int entry_json_element(const EntryJson *json, unsigned int array, unsigned int slot)
{
    if ((array == 0u) || (array >= json->count) || (json->tokens[array].kind != CFG_JSON_ARRAY) ||
        (slot >= json->tokens[array].count))
    {
        return 0u;
    }
    unsigned int at = array + 1u;
    for (unsigned int step = 0u; step < slot; step += 1u)
    {
        at = json->tokens[at].next;
    }
    return at;
}

int entry_json_text(const EntryJson *json, unsigned int token, char *out, size_t capacity)
{
    return (token != 0u) && cfg_json_string(json->text, &json->tokens[token], out, capacity);
}

int entry_json_list(const EntryJson *json, unsigned int array, unsigned long long *values, unsigned int *count,
                    unsigned int capacity)
{
    if ((array == 0u) || (json->tokens[array].kind != CFG_JSON_ARRAY) || (json->tokens[array].count > capacity))
    {
        return 0;
    }
    *count = json->tokens[array].count;
    int ok = 1;
    for (unsigned int slot = 0u; ok && (slot < *count); slot += 1u)
    {
        ok = cfg_json_unsigned(json->text, &json->tokens[entry_json_element(json, array, slot)], &values[slot]);
    }
    return ok;
}

int entry_element_named(const char *name, EngineArrayExtent *extent, unsigned int *big_endian)
{
    static const char *const NAMES[10] = {"uint8", "uint16", "uint32", "uint64",  "int8",
                                          "int16", "int32",  "int64",  "float32", "float64"};
    static const unsigned int BYTES[10] = {1u, 2u, 4u, 8u, 1u, 2u, 4u, 8u, 4u, 8u};
    static const EngineElementKind KINDS[10] = {
        ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_UNSIGNED,
        ENGINE_ELEMENT_SIGNED,   ENGINE_ELEMENT_SIGNED,   ENGINE_ELEMENT_SIGNED,   ENGINE_ELEMENT_SIGNED,
        ENGINE_ELEMENT_FLOAT,    ENGINE_ELEMENT_FLOAT};
    for (unsigned int slot = 0u; slot < 10u; slot += 1u)
    {
        if (strcmp(name, NAMES[slot]) == 0)
        {
            extent->element_bytes = BYTES[slot];
            extent->element_kind = KINDS[slot];
            return 1;
        }
    }
    const size_t length = strlen(name);
    const int ordered =
        (length >= 3u) && ((name[0] == '<') || (name[0] == '>') || (name[0] == '|') || (name[0] == '='));
    const char kind = ordered ? name[1] : '\0';
    const unsigned long width = ordered ? strtoul(&name[2], NULL, 10) : 0ul;
    if ((ordered == 0) || ((kind != 'u') && (kind != 'i') && (kind != 'f')) ||
        ((width != 1ul) && (width != 2ul) && (width != 4ul) && (width != 8ul)))
    {
        return 0;
    }
    extent->element_bytes = (unsigned int)width;
    extent->element_kind = (kind == 'u')   ? ENGINE_ELEMENT_UNSIGNED
                           : (kind == 'i') ? ENGINE_ELEMENT_SIGNED
                                           : ENGINE_ELEMENT_FLOAT;
    *big_endian = (name[0] == '>') ? 1u : 0u;
    return 1;
}

int entry_codec_named(const char *name, EngineCodec *codec)
{
    static const char *const NAMES[6] = {"blosc", "zstd", "gzip", "zlib", "lz4", "snappy"};
    static const EngineCodec CODECS[6] = {ENGINE_CODEC_BLOSC, ENGINE_CODEC_ZSTD,      ENGINE_CODEC_GZIP,
                                          ENGINE_CODEC_ZLIB,  ENGINE_CODEC_LZ4_SIZED, ENGINE_CODEC_SNAPPY};
    for (unsigned int slot = 0u; slot < 6u; slot += 1u)
    {
        if (strcmp(name, NAMES[slot]) == 0)
        {
            *codec = CODECS[slot];
            return 1;
        }
    }
    return 0;
}

char entry_axis_named(const char *name)
{
    static const char *const NAMES[7] = {"t", "time", "c", "channel", "z", "y", "x"};
    static const char AXES[7] = {'t', 't', 'c', 'c', 'z', 'y', 'x'};
    char lowered[16];
    size_t length = 0u;
    while ((name[length] != '\0') && (length + 1u < sizeof(lowered)))
    {
        lowered[length] = (char)(((name[length] >= 'A') && (name[length] <= 'Z')) ? (name[length] + 32) : name[length]);
        length += 1u;
    }
    lowered[length] = '\0';
    for (unsigned int slot = 0u; slot < 7u; slot += 1u)
    {
        if (strcmp(lowered, NAMES[slot]) == 0)
        {
            return AXES[slot];
        }
    }
    return '\0';
}

int entry_ome(const EntryJson *json, unsigned int attributes, EntryOme *ome)
{
    memset(ome, 0, sizeof(*ome));
    unsigned int scales = entry_json_at(json, attributes, "multiscales");
    scales = (scales != 0u) ? scales : entry_json_at(json, entry_json_at(json, attributes, "ome"), "multiscales");
    const unsigned int first = entry_json_element(json, scales, 0u);
    const unsigned int datasets = entry_json_at(json, first, "datasets");
    if (entry_json_text(json, entry_json_at(json, entry_json_element(json, datasets, 0u), "path"), ome->path,
                        sizeof(ome->path)) == 0)
    {
        return 0;
    }
    const unsigned int axes = entry_json_at(json, first, "axes");
    const unsigned int named =
        ((axes != 0u) && (json->tokens[axes].kind == CFG_JSON_ARRAY)) ? json->tokens[axes].count : 0u;
    ome->rank = (named <= ENGINE_ARRAY_RANK) ? named : 0u;
    for (unsigned int slot = 0u; slot < ome->rank; slot += 1u)
    {
        const unsigned int axis = entry_json_element(json, axes, slot);
        const unsigned int name_token =
            (json->tokens[axis].kind == CFG_JSON_OBJECT) ? entry_json_at(json, axis, "name") : axis;
        char name[32];
        ome->axes[slot] = entry_json_text(json, name_token, name, sizeof(name)) ? entry_axis_named(name) : '\0';
    }
    return 1;
}
