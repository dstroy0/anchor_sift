// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "krep.h"

#include "crc.h"

#include <stdlib.h>
#include <string.h>

#define KREP_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_KREP, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define KREP_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_KREP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

static const unsigned char KREP_MAGIC[8] = {'K', 'R', 'E', 'P', 0u, 0u, 0u, 0u};

static int krep_host_little(void)
{
    const unsigned int probe = 1u;
    unsigned char first = 0u;
    memcpy(&first, &probe, 1u);
    return (first == 1u) ? 1 : 0;
}

extern "C" int krep_words_write(FILE *file, const unsigned long long *words, size_t count)
{
    if (krep_host_little() != 0)
    {
        return (fwrite(words, sizeof(unsigned long long), count, file) == count) ? 1 : 0;
    }
    for (size_t at = 0u; at < count; at += 1u)
    {
        unsigned char bytes[8];
        for (unsigned int place = 0u; place < 8u; place += 1u)
        {
            bytes[place] = (unsigned char)((words[at] >> (8u * place)) & 0xFFull);
        }
        if (fwrite(bytes, 1u, 8u, file) != 8u)
        {
            return 0;
        }
    }
    return 1;
}

extern "C" int krep_words_read(FILE *file, unsigned long long *words, size_t count)
{
    if (krep_host_little() != 0)
    {
        return (fread(words, sizeof(unsigned long long), count, file) == count) ? 1 : 0;
    }
    for (size_t at = 0u; at < count; at += 1u)
    {
        unsigned char bytes[8];
        if (fread(bytes, 1u, 8u, file) != 8u)
        {
            return 0;
        }
        words[at] = 0ull;
        for (unsigned int place = 0u; place < 8u; place += 1u)
        {
            words[at] |= (unsigned long long)bytes[place] << (8u * place);
        }
    }
    return 1;
}

extern "C" int krep_limbs_write(FILE *file, const unsigned int *limbs, size_t count)
{
    if (krep_host_little() != 0)
    {
        return (fwrite(limbs, sizeof(unsigned int), count, file) == count) ? 1 : 0;
    }
    for (size_t at = 0u; at < count; at += 1u)
    {
        unsigned char bytes[4];
        for (unsigned int place = 0u; place < 4u; place += 1u)
        {
            bytes[place] = (unsigned char)((limbs[at] >> (8u * place)) & 0xFFu);
        }
        if (fwrite(bytes, 1u, 4u, file) != 4u)
        {
            return 0;
        }
    }
    return 1;
}

extern "C" int krep_limbs_read(FILE *file, unsigned int *limbs, size_t count)
{
    if (krep_host_little() != 0)
    {
        return (fread(limbs, sizeof(unsigned int), count, file) == count) ? 1 : 0;
    }
    for (size_t at = 0u; at < count; at += 1u)
    {
        unsigned char bytes[4];
        if (fread(bytes, 1u, 4u, file) != 4u)
        {
            return 0;
        }
        limbs[at] = 0u;
        for (unsigned int place = 0u; place < 4u; place += 1u)
        {
            limbs[at] |= (unsigned int)bytes[place] << (8u * place);
        }
    }
    return 1;
}

extern "C" int krep_head_write(FILE *file, const char *kind)
{
    const unsigned int version = KREP_VERSION;
    return (fwrite(KREP_MAGIC, 1u, 8u, file) == 8u) && (fwrite(kind, 1u, 4u, file) == 4u)
        && (krep_limbs_write(file, &version, 1u) != 0);
}

extern "C" int krep_head_read(FILE *file, const char *kind)
{
    unsigned char magic[8];
    char named[4];
    unsigned int version = 0u;
    return (fread(magic, 1u, 8u, file) == 8u) && (memcmp(magic, KREP_MAGIC, 8u) == 0)
        && (fread(named, 1u, 4u, file) == 4u) && (memcmp(named, kind, 4u) == 0)
        && (krep_limbs_read(file, &version, 1u) != 0) && (version == KREP_VERSION);
}

typedef enum
{
    KREP_HEAD_EXTENT = 0,
    KREP_HEAD_CHUNKS = 4,
    KREP_HEAD_BITS = 5,
    KREP_HEAD_LANE_OFFSET = 6,
    KREP_HEAD_LEAVES = 7,
    KREP_HEAD_SIDE_BYTES = 8,
    KREP_HEAD_PACKED_BYTES = 9,
    KREP_HEAD_NAMES_BYTES = 10,
    KREP_HEAD_LANE_NODES = 11
} KrepCrystalHead;

static_assert(KREP_HEAD_LANE_NODES + 1 == KREP_CRYSTAL_HEAD_WORDS, "the crystal's head words end at its lane nodes");

static_assert(sizeof(EngineSignum) == ENGINE_SIGNUM_BYTES, "a signum is its 32 bytes and nothing more");

static unsigned long long krep_lanes(const unsigned long long extent[4])
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

static unsigned long long krep_side_leaves(const EngineSideSection *section)
{
    return (section != NULL) ? section->side.leaves : 0ull;
}

static unsigned long long krep_side_bytes(const EngineSideSection *section)
{
    return (krep_side_leaves(section) != 0ull) ? section->side.byte_start[section->side.leaves] : 0ull;
}

static unsigned long long krep_names_bytes(const EngineSideSection *section)
{
    return (krep_side_leaves(section) != 0ull) ? section->side.name_start[section->side.leaves] : 0ull;
}

static unsigned long long krep_member_words(unsigned long long leaves)
{
    return (leaves != 0ull) ? ((6ull * leaves) + 2ull) : 0ull;
}

static unsigned long long krep_seal_nodes(const EngineSeal *seal)
{
    return ENGINE_SEAL_ROOTS + seal->lane_count + seal->chunk_count;
}

extern "C" unsigned long long krep_crystal_bytes(const EngineStream *stream, const EngineSideSection *section,
                                                 const EngineSeal *seal)
{
    const unsigned long long leaves = krep_side_leaves(section);
    const unsigned long long side = (leaves != 0ull) ? (section->packed_bytes + (8ull * krep_member_words(leaves))
                                                        + krep_names_bytes(section))
                                                     : 0ull;
    return KREP_HEAD_BYTES + (8ull * KREP_CRYSTAL_HEAD_WORDS) + (ENGINE_SIGNUM_BYTES * krep_seal_nodes(seal))
         + (8ull * stream->chunks) + (4ull * ((stream->bits + 31ull) / 32ull)) + side;
}

static void krep_crystal_head_words(const EngineStream *stream, const EngineSideSection *section,
                                    const EngineSeal *seal, unsigned long long head[KREP_CRYSTAL_HEAD_WORDS])
{
    memcpy(&head[KREP_HEAD_EXTENT], stream->extent, 4u * sizeof(unsigned long long));
    head[KREP_HEAD_CHUNKS] = stream->chunks;
    head[KREP_HEAD_BITS] = stream->bits;
    head[KREP_HEAD_LANE_OFFSET] = stream->lane_offset;
    head[KREP_HEAD_LEAVES] = krep_side_leaves(section);
    head[KREP_HEAD_SIDE_BYTES] = krep_side_bytes(section);
    head[KREP_HEAD_PACKED_BYTES] = (head[KREP_HEAD_LEAVES] != 0ull) ? section->packed_bytes : 0ull;
    head[KREP_HEAD_NAMES_BYTES] = krep_names_bytes(section);
    head[KREP_HEAD_LANE_NODES] = seal->lane_count;
}

static int krep_seal_write(FILE *crystal, const EngineSeal *seal, EngineError *error)
{
    return KREP_IO(fwrite(seal->roots, sizeof(EngineSignum), ENGINE_SEAL_ROOTS, crystal) == ENGINE_SEAL_ROOTS,
                   seal->roots, error)
        && KREP_IO(fwrite(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, crystal)
                       == (size_t)seal->lane_count,
                   seal->lane_nodes, error)
        && KREP_IO(fwrite(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, crystal)
                       == (size_t)seal->chunk_count,
                   seal->chunk_leaves, error);
}

static int krep_seal_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineSeal *seal,
                          EngineError *error)
{
    seal->lane_count = head[KREP_HEAD_LANE_NODES];
    seal->chunk_count = head[KREP_HEAD_CHUNKS];
    seal->lane_nodes = (EngineSignum *)calloc((size_t)seal->lane_count + 1u, sizeof(EngineSignum));
    seal->chunk_leaves = (EngineSignum *)calloc((size_t)seal->chunk_count + 1u, sizeof(EngineSignum));
    return KREP_HELD((seal->lane_nodes != NULL) && (seal->chunk_leaves != NULL), seal, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(fread(seal->roots, sizeof(EngineSignum), ENGINE_SEAL_ROOTS, crystal) == ENGINE_SEAL_ROOTS,
                   seal->roots, error)
        && KREP_IO(fread(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, crystal)
                       == (size_t)seal->lane_count,
                   seal->lane_nodes, error)
        && KREP_IO(fread(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, crystal)
                       == (size_t)seal->chunk_count,
                   seal->chunk_leaves, error);
}

static int krep_members_write(FILE *crystal, const EngineSideBytes *side, EngineError *error)
{
    const size_t leaves = (size_t)side->leaves;
    return KREP_IO(krep_words_write(crystal, side->pixel_at, leaves) != 0, side->pixel_at, error)
        && KREP_IO(krep_words_write(crystal, side->pixel_kept, leaves) != 0, side->pixel_kept, error)
        && KREP_IO(krep_words_write(crystal, side->byte_start, leaves + 1u) != 0, side->byte_start, error)
        && KREP_IO(krep_words_write(crystal, side->name_start, leaves + 1u) != 0, side->name_start, error)
        && KREP_IO(krep_words_write(crystal, side->member_crc, leaves) != 0, side->member_crc, error)
        && KREP_IO(krep_words_write(crystal, side->member_bytes, leaves) != 0, side->member_bytes, error)
        && KREP_IO(fwrite(side->names, 1u, (size_t)side->name_start[leaves], crystal) == (size_t)side->name_start[leaves],
                   side->names, error);
}

extern "C" int krep_crystal_write(const KrepCrystalRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!KREP_HELD((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL)
                       && (request->seal->chunk_count == request->stream->chunks),
                   request, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const EngineStream *const stream = request->stream;
    const EngineSideSection *const section = request->section;
    const EngineSeal *const seal = request->seal;
    unsigned long long head[KREP_CRYSTAL_HEAD_WORDS];
    krep_crystal_head_words(stream, section, seal, head);
    const size_t limbs = (size_t)((stream->bits + 31ull) / 32ull);
    FILE *const crystal = fopen(request->path, "wb");
    int good = KREP_IO(crystal != NULL, request->path, error)
            && KREP_IO(krep_head_write(crystal, KREP_KIND_CRYSTAL) != 0, crystal, error)
            && KREP_IO(krep_words_write(crystal, head, KREP_CRYSTAL_HEAD_WORDS) != 0, head, error)
            && krep_seal_write(crystal, seal, error)
            && KREP_IO(krep_words_write(crystal, stream->offsets, (size_t)stream->chunks) != 0, stream->offsets, error)
            && KREP_IO(krep_limbs_write(crystal, stream->stream, limbs) != 0, stream->stream, error);
    if (good && (head[KREP_HEAD_LEAVES] != 0ull))
    {
        good = KREP_IO(fwrite(section->packed, 1u, (size_t)section->packed_bytes, crystal) == (size_t)section->packed_bytes,
                       section->packed, error)
            && krep_members_write(crystal, &section->side, error);
    }
    if (crystal != NULL)
    {
        good = KREP_IO(fclose(crystal) == 0, crystal, error) && good;
    }
    return good;
}

static int krep_crystal_head_from(const char *path, FILE *crystal, EngineStream *stream,
                                  unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineError *error)
{
    memset(head, 0, KREP_CRYSTAL_HEAD_WORDS * sizeof(unsigned long long));
    const int good = KREP_IO(crystal != NULL, path, error)
                  && KREP_IO(krep_head_read(crystal, KREP_KIND_CRYSTAL) != 0, crystal, error)
                  && KREP_IO(krep_words_read(crystal, head, KREP_CRYSTAL_HEAD_WORDS) != 0, head, error);
    memcpy(stream->extent, &head[KREP_HEAD_EXTENT], 4u * sizeof(unsigned long long));
    stream->chunks = head[KREP_HEAD_CHUNKS];
    stream->bits = head[KREP_HEAD_BITS];
    stream->lane_offset = head[KREP_HEAD_LANE_OFFSET];
    const unsigned long long lanes = good ? krep_lanes(stream->extent) : 0ull;
    const int unsided = (head[KREP_HEAD_SIDE_BYTES] == 0ull) && (head[KREP_HEAD_PACKED_BYTES] == 0ull)
                     && (head[KREP_HEAD_NAMES_BYTES] == 0ull);
    return good
        && KREP_HELD((lanes != 0ull) && (stream->chunks <= lanes) && (stream->bits <= (64ull * lanes))
                         && ((head[KREP_HEAD_LEAVES] != 0ull) || unsided)
                         && (head[KREP_HEAD_LANE_NODES] <= ((3ull * lanes) + 1ull)),
                     head, error, ENGINE_ERROR_LOGIC);
}

static int krep_members_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS],
                             EngineSideBytes *side, EngineError *error)
{
    const size_t leaves = (size_t)head[KREP_HEAD_LEAVES];
    side->leaves = head[KREP_HEAD_LEAVES];
    side->pixel_at = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->pixel_kept = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->byte_start = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->name_start = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->member_crc = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->member_bytes = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->names = (char *)malloc((size_t)head[KREP_HEAD_NAMES_BYTES] + 1u);
    return KREP_HELD((side->pixel_at != NULL) && (side->pixel_kept != NULL) && (side->byte_start != NULL)
                         && (side->name_start != NULL) && (side->member_crc != NULL) && (side->member_bytes != NULL)
                         && (side->names != NULL),
                     side, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(krep_words_read(crystal, side->pixel_at, leaves) != 0, side->pixel_at, error)
        && KREP_IO(krep_words_read(crystal, side->pixel_kept, leaves) != 0, side->pixel_kept, error)
        && KREP_IO(krep_words_read(crystal, side->byte_start, leaves + 1u) != 0, side->byte_start, error)
        && KREP_IO(krep_words_read(crystal, side->name_start, leaves + 1u) != 0, side->name_start, error)
        && KREP_HELD((side->byte_start[leaves] == head[KREP_HEAD_SIDE_BYTES])
                         && (side->name_start[leaves] == head[KREP_HEAD_NAMES_BYTES]),
                     side, error, ENGINE_ERROR_LOGIC)
        && KREP_IO(krep_words_read(crystal, side->member_crc, leaves) != 0, side->member_crc, error)
        && KREP_IO(krep_words_read(crystal, side->member_bytes, leaves) != 0, side->member_bytes, error)
        && KREP_IO(fread(side->names, 1u, (size_t)head[KREP_HEAD_NAMES_BYTES], crystal)
                       == (size_t)head[KREP_HEAD_NAMES_BYTES],
                   side->names, error);
}

static int krep_side_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS],
                          EngineSideSection *section, EngineError *error)
{
    memset(section, 0, sizeof(*section));
    if (head[KREP_HEAD_LEAVES] == 0ull)
    {
        return 1;
    }
    const unsigned long long packed = head[KREP_HEAD_PACKED_BYTES];
    section->packed_bytes = packed;
    section->packed = (unsigned char *)malloc((size_t)packed + 1u);
    return KREP_HELD(section->packed != NULL, &section->packed, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(fread(section->packed, 1u, (size_t)packed, crystal) == (size_t)packed, section->packed, error)
        && krep_members_read(crystal, head, &section->side, error);
}

extern "C" int krep_crystal_head(const char *path, EngineStream *stream, EngineSignum *root, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_HELD((path != NULL) && (stream != NULL), &stream, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(stream, 0, sizeof(*stream));
    unsigned long long head[KREP_CRYSTAL_HEAD_WORDS];
    FILE *const crystal = fopen(path, "rb");
    int good = krep_crystal_head_from(path, crystal, stream, head, error);
    if (good && (root != NULL))
    {
        good = KREP_IO(fread(root, sizeof(EngineSignum), 1u, crystal) == 1u, root, error);
    }
    if (crystal != NULL)
    {
        fclose(crystal);
    }
    return good;
}

extern "C" int krep_crystal_read(const KrepCrystalRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!KREP_HELD((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL), request, error,
                   ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    EngineStream *const stream = request->stream;
    EngineSeal *const seal = request->seal;
    memset(stream, 0, sizeof(*stream));
    memset(seal, 0, sizeof(*seal));
    unsigned long long head[KREP_CRYSTAL_HEAD_WORDS];
    EngineSideSection discarded;
    EngineSideSection *const held = (request->section != NULL) ? request->section : &discarded;
    memset(held, 0, sizeof(*held));
    FILE *const crystal = fopen(request->path, "rb");
    int good = krep_crystal_head_from(request->path, crystal, stream, head, error)
            && krep_seal_read(crystal, head, seal, error);
    const size_t limbs = good ? (size_t)((stream->bits + 31ull) / 32ull) : 0u;
    unsigned long long *const offsets
        = good ? (unsigned long long *)calloc((size_t)stream->chunks + 1u, sizeof(unsigned long long)) : NULL;
    unsigned int *const limb_table = good ? (unsigned int *)calloc(limbs + 1u, sizeof(unsigned int)) : NULL;
    good = good && KREP_HELD(offsets != NULL, &offsets, error, ENGINE_ERROR_RESOURCE)
        && KREP_HELD(limb_table != NULL, &limb_table, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(krep_words_read(crystal, offsets, (size_t)stream->chunks) != 0, offsets, error)
        && KREP_IO(krep_limbs_read(crystal, limb_table, limbs) != 0, limb_table, error)
        && krep_side_read(crystal, head, held, error)
        && KREP_HELD(fgetc(crystal) == EOF, crystal, error, ENGINE_ERROR_LOGIC);
    if (crystal != NULL)
    {
        fclose(crystal);
    }
    stream->offsets = offsets;
    stream->stream = limb_table;
    if ((good == 0) || (request->section == NULL))
    {
        krep_side_release(held);
    }
    if (good == 0)
    {
        krep_crystal_release(stream);
        krep_seal_release(seal);
    }
    return good;
}

extern "C" void krep_seal_release(EngineSeal *seal)
{
    free(seal->lane_nodes);
    free(seal->chunk_leaves);
    memset(seal, 0, sizeof(*seal));
}

extern "C" void krep_side_release(EngineSideSection *section)
{
    EngineSideBytes *const side = &section->side;
    free(side->pixel_at);
    free(side->pixel_kept);
    free(side->byte_start);
    free(side->bytes);
    free(side->name_start);
    free(side->names);
    free(side->member_crc);
    free(side->member_bytes);
    free(section->packed);
    memset(section, 0, sizeof(*section));
}

extern "C" void krep_crystal_release(EngineStream *stream)
{
    free((void *)stream->offsets);
    free((void *)stream->stream);
    stream->offsets = NULL;
    stream->stream = NULL;
}

static size_t krep_history_words(const EngineHistory *history)
{
    return (size_t)(history->windows * history->extent[1] * history->extent[2] * history->extent[3]);
}

extern "C" int krep_history_write(const char *path, const EngineHistory *history, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_HELD((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long head[4] = {ENGINE_HISTORY_WINDOW, history->windows, history->payload_crc,
                                        history->cloud_crc};
    FILE *const out = fopen(path, "wb");
    int good = KREP_IO(out != NULL, path, error)
            && KREP_IO(krep_head_write(out, KREP_KIND_NOISE_FLOOR) != 0, out, error)
            && KREP_IO(krep_words_write(out, history->extent, 4u) != 0, history->extent, error)
            && KREP_IO(krep_words_write(out, head, 4u) != 0, head, error)
            && KREP_IO(fwrite(&history->sample, sizeof(EngineSignum), 1u, out) == 1u, &history->sample, error)
            && KREP_IO(krep_words_write(out, history->cloud, (size_t)(history->windows * history->windows)) != 0,
                       history->cloud, error)
            && KREP_IO(krep_words_write(out, history->history, krep_history_words(history)) != 0,
                       history->history, error);
    if (out != NULL)
    {
        good = KREP_IO(fclose(out) == 0, out, error) && good;
    }
    return good;
}

extern "C" int krep_history_read(const char *path, EngineHistory *history, unsigned int payload, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_HELD((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(history, 0, sizeof(*history));
    FILE *const back = fopen(path, "rb");
    unsigned long long head[4] = {0ull, 0ull, 0ull, 0ull};
    int good = KREP_IO(back != NULL, path, error)
            && KREP_IO(krep_head_read(back, KREP_KIND_NOISE_FLOOR) != 0, back, error)
            && KREP_IO(krep_words_read(back, history->extent, 4u) != 0, history->extent, error)
            && KREP_IO(krep_words_read(back, head, 4u) != 0, head, error)
            && KREP_IO(fread(&history->sample, sizeof(EngineSignum), 1u, back) == 1u, &history->sample, error)
            && KREP_HELD((head[0] == ENGINE_HISTORY_WINDOW) && (history->extent[0] >= 2ull)
                             && (head[1]
                                 == (((history->extent[0] - 1ull) + ENGINE_HISTORY_WINDOW - 1ull) / ENGINE_HISTORY_WINDOW))
                             && (head[1] <= ENGINE_HISTORY_WINDOWS_MAX) && (history->extent[1] <= (1ull << 20u))
                             && (history->extent[2] <= (1ull << 20u)) && (history->extent[3] <= (1ull << 20u)),
                         head, error, ENGINE_ERROR_LOGIC);
    history->windows = good ? head[1] : 0ull;
    history->payload_crc = head[2];
    history->cloud_crc = head[3];
    const size_t entries = (size_t)(history->windows * history->windows);
    history->cloud = good ? (unsigned long long *)calloc(entries, sizeof(unsigned long long)) : NULL;
    good = good && KREP_HELD(history->cloud != NULL, &history->cloud, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(krep_words_read(back, history->cloud, entries) != 0, history->cloud, error)
        && KREP_HELD(crc_words(CRC_TABLE, history->cloud, entries) == history->cloud_crc, &history->cloud_crc, error,
                     ENGINE_ERROR_LOGIC);
    if (good && (payload != 0u))
    {
        const size_t words = krep_history_words(history);
        history->history = (unsigned long long *)calloc(words, sizeof(unsigned long long));
        good = KREP_HELD(history->history != NULL, &history->history, error, ENGINE_ERROR_RESOURCE)
            && KREP_IO(krep_words_read(back, history->history, words) != 0, history->history, error)
            && KREP_HELD(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC)
            && KREP_HELD(crc_words(CRC_TABLE, history->history, words) == history->payload_crc, &history->payload_crc,
                         error, ENGINE_ERROR_LOGIC);
    }
    if (back != NULL)
    {
        fclose(back);
    }
    if (good == 0)
    {
        krep_history_release(history);
    }
    return good;
}

extern "C" void krep_history_release(EngineHistory *history)
{
    free(history->cloud);
    free(history->history);
    history->cloud = NULL;
    history->history = NULL;
}

extern "C" int krep_bodies_write(const char *path, const EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_HELD((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long counts[3] = {table->frames, table->bodies, table->crc};
    FILE *const out = fopen(path, "wb");
    int good = KREP_IO(out != NULL, path, error)
            && KREP_IO(krep_head_write(out, KREP_KIND_CONSTRUCTION_SET) != 0, out, error)
            && KREP_IO(krep_words_write(out, table->extent, 4u) != 0, table->extent, error)
            && KREP_IO(krep_words_write(out, counts, 3u) != 0, counts, error)
            && KREP_IO(krep_words_write(out, table->frame_start, (size_t)table->frames + 1u) != 0,
                       table->frame_start, error)
            && KREP_IO(krep_words_write(out, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0,
                       table->words, error);
    if (out != NULL)
    {
        good = KREP_IO(fclose(out) == 0, out, error) && good;
    }
    return good;
}

extern "C" int krep_bodies_read(const char *path, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_HELD((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(table, 0, sizeof(*table));
    FILE *const back = fopen(path, "rb");
    unsigned long long counts[3] = {0ull, 0ull, 0ull};
    int good = KREP_IO(back != NULL, path, error)
            && KREP_IO(krep_head_read(back, KREP_KIND_CONSTRUCTION_SET) != 0, back, error)
            && KREP_IO(krep_words_read(back, table->extent, 4u) != 0, table->extent, error)
            && KREP_IO(krep_words_read(back, counts, 3u) != 0, counts, error)
            && KREP_HELD((counts[0] == table->extent[0]) && (krep_lanes(table->extent) != 0ull)
                             && (counts[1] <= krep_lanes(table->extent)),
                         counts, error, ENGINE_ERROR_LOGIC);
    table->frames = good ? counts[0] : 0ull;
    table->bodies = good ? counts[1] : 0ull;
    table->crc = counts[2];
    table->frame_start = good ? (unsigned long long *)calloc((size_t)table->frames + 1u, sizeof(unsigned long long))
                              : NULL;
    table->words = good ? (unsigned long long *)calloc((size_t)(table->bodies * ENGINE_BODY_WORDS) + 1u,
                                                       sizeof(unsigned long long))
                        : NULL;
    good = good && KREP_HELD(table->frame_start != NULL, &table->frame_start, error, ENGINE_ERROR_RESOURCE)
        && KREP_HELD(table->words != NULL, &table->words, error, ENGINE_ERROR_RESOURCE)
        && KREP_IO(krep_words_read(back, table->frame_start, (size_t)table->frames + 1u) != 0, table->frame_start,
                   error)
        && KREP_IO(krep_words_read(back, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0,
                   table->words, error)
        && KREP_HELD(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC)
        && KREP_HELD(table->frame_start[table->frames] == table->bodies, table->frame_start, error, ENGINE_ERROR_LOGIC)
        && KREP_HELD(crc_words(CRC_TABLE, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) == table->crc,
                     &table->crc, error, ENGINE_ERROR_LOGIC);
    if (back != NULL)
    {
        fclose(back);
    }
    if (good == 0)
    {
        krep_bodies_release(table);
    }
    return good;
}

extern "C" void krep_bodies_release(EngineBodyTable *table)
{
    free(table->frame_start);
    free(table->words);
    table->frame_start = NULL;
    table->words = NULL;
}
