// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// apxrep_io.cu: words, limbs, the head and the seal
#include "apxrep_internal.h"

static const unsigned char APXREP_MAGIC[8] = {'A', 'P', 'X', 'R', 'E', 'P', 0u, 0u};

static int apxrep_host_little(void)
{
    const unsigned int probe = 1u;
    unsigned char first = 0u;
    memcpy(&first, &probe, 1u);
    return (first == 1u) ? 1 : 0;
}

extern "C" int apxrep_words_write(FILE *file, const unsigned long long *words, size_t count)
{
    if (apxrep_host_little() != 0)
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

extern "C" int apxrep_words_read(FILE *file, unsigned long long *words, size_t count)
{
    if (apxrep_host_little() != 0)
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

extern "C" int apxrep_limbs_write(FILE *file, const unsigned int *limbs, size_t count)
{
    if (apxrep_host_little() != 0)
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

extern "C" int apxrep_limbs_read(FILE *file, unsigned int *limbs, size_t count)
{
    if (apxrep_host_little() != 0)
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

extern "C" int apxrep_head_write(FILE *file, const char *kind)
{
    const unsigned int version = APXREP_VERSION;
    return (fwrite(APXREP_MAGIC, 1u, 8u, file) == 8u) && (fwrite(kind, 1u, 4u, file) == 4u) &&
           (apxrep_limbs_write(file, &version, 1u) != 0);
}

extern "C" int apxrep_head_read(FILE *file, const char *kind)
{
    unsigned char magic[8];
    char named[4];
    unsigned int version = 0u;
    return (fread(magic, 1u, 8u, file) == 8u) && (memcmp(magic, APXREP_MAGIC, 8u) == 0) &&
           (fread(named, 1u, 4u, file) == 4u) && (memcmp(named, kind, 4u) == 0) &&
           (apxrep_limbs_read(file, &version, 1u) != 0) && (version == APXREP_VERSION);
}

unsigned long long apxrep_lanes(const unsigned long long extent[4])
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

static unsigned long long apxrep_side_leaves(const EngineSideSection *section)
{
    return (section != NULL) ? section->side.leaves : 0ull;
}

static unsigned long long apxrep_side_bytes(const EngineSideSection *section)
{
    return (apxrep_side_leaves(section) != 0ull) ? section->side.byte_start[section->side.leaves] : 0ull;
}

static unsigned long long apxrep_names_bytes(const EngineSideSection *section)
{
    return (apxrep_side_leaves(section) != 0ull) ? section->side.name_start[section->side.leaves] : 0ull;
}

static unsigned long long apxrep_member_words(unsigned long long leaves)
{
    return (leaves != 0ull) ? ((6ull * leaves) + 2ull) : 0ull;
}

static unsigned long long apxrep_seal_nodes(const EngineSeal *seal)
{
    return ENGINE_SEAL_ROOTS + seal->lane_count + seal->chunk_count;
}

extern "C" unsigned long long apxrep_input_bytes(const EngineStream *stream, const EngineSideSection *section,
                                                 const EngineSeal *seal)
{
    const unsigned long long leaves = apxrep_side_leaves(section);
    const unsigned long long side =
        (leaves != 0ull) ? (section->packed_bytes + (8ull * apxrep_member_words(leaves)) + apxrep_names_bytes(section))
                         : 0ull;
    return APXREP_HEAD_BYTES + (8ull * APXREP_INPUT_HEAD_WORDS) + (ENGINE_SIGNUM_BYTES * apxrep_seal_nodes(seal)) +
           (8ull * stream->chunks) + (4ull * ((stream->bits + 31ull) / 32ull)) + side;
}

static void apxrep_input_head_words(const EngineStream *stream, const EngineSideSection *section,
                                    const EngineSeal *seal, unsigned long long head[APXREP_INPUT_HEAD_WORDS])
{
    memcpy(&head[APXREP_HEAD_EXTENT], stream->extent, 4u * sizeof(unsigned long long));
    head[APXREP_HEAD_CHUNKS] = stream->chunks;
    head[APXREP_HEAD_BITS] = stream->bits;
    head[APXREP_HEAD_LANE_OFFSET] = stream->lane_offset;
    head[APXREP_HEAD_LEAVES] = apxrep_side_leaves(section);
    head[APXREP_HEAD_SIDE_BYTES] = apxrep_side_bytes(section);
    head[APXREP_HEAD_PACKED_BYTES] = (head[APXREP_HEAD_LEAVES] != 0ull) ? section->packed_bytes : 0ull;
    head[APXREP_HEAD_NAMES_BYTES] = apxrep_names_bytes(section);
    head[APXREP_HEAD_LANE_NODES] = seal->lane_count;
}

static int apxrep_seal_write(FILE *iapx, const EngineSeal *seal, EngineError *error)
{
    return APXREP_IO(fwrite(seal->roots, sizeof(EngineSignum), ENGINE_SEAL_ROOTS, iapx) == ENGINE_SEAL_ROOTS,
                     seal->roots, error) &&
           APXREP_IO(fwrite(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, iapx) ==
                         (size_t)seal->lane_count,
                     seal->lane_nodes, error) &&
           APXREP_IO(fwrite(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, iapx) ==
                         (size_t)seal->chunk_count,
                     seal->chunk_leaves, error);
}

int apxrep_seal_read(FILE *iapx, const unsigned long long head[APXREP_INPUT_HEAD_WORDS], EngineSeal *seal,
                     EngineError *error)
{
    seal->lane_count = head[APXREP_HEAD_LANE_NODES];
    seal->chunk_count = head[APXREP_HEAD_CHUNKS];
    seal->lane_nodes = (EngineSignum *)calloc((size_t)seal->lane_count + 1u, sizeof(EngineSignum));
    seal->chunk_leaves = (EngineSignum *)calloc((size_t)seal->chunk_count + 1u, sizeof(EngineSignum));
    return APXREP_CHECK((seal->lane_nodes != NULL) && (seal->chunk_leaves != NULL), seal, error,
                        ENGINE_ERROR_RESOURCE) &&
           APXREP_IO(fread(seal->roots, sizeof(EngineSignum), ENGINE_SEAL_ROOTS, iapx) == ENGINE_SEAL_ROOTS,
                     seal->roots, error) &&
           APXREP_IO(fread(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, iapx) ==
                         (size_t)seal->lane_count,
                     seal->lane_nodes, error) &&
           APXREP_IO(fread(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, iapx) ==
                         (size_t)seal->chunk_count,
                     seal->chunk_leaves, error);
}

static int apxrep_members_write(FILE *iapx, const EngineSideBytes *side, EngineError *error)
{
    const size_t leaves = (size_t)side->leaves;
    return APXREP_IO(apxrep_words_write(iapx, side->pixel_at, leaves) != 0, side->pixel_at, error) &&
           APXREP_IO(apxrep_words_write(iapx, side->pixel_kept, leaves) != 0, side->pixel_kept, error) &&
           APXREP_IO(apxrep_words_write(iapx, side->byte_start, leaves + 1u) != 0, side->byte_start, error) &&
           APXREP_IO(apxrep_words_write(iapx, side->name_start, leaves + 1u) != 0, side->name_start, error) &&
           APXREP_IO(apxrep_words_write(iapx, side->member_crc, leaves) != 0, side->member_crc, error) &&
           APXREP_IO(apxrep_words_write(iapx, side->member_bytes, leaves) != 0, side->member_bytes, error) &&
           APXREP_IO(fwrite(side->names, 1u, (size_t)side->name_start[leaves], iapx) ==
                         (size_t)side->name_start[leaves],
                     side->names, error);
}

extern "C" int apxrep_input_write(const ApxrepInputRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!APXREP_CHECK((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL) &&
                          (request->seal->chunk_count == request->stream->chunks),
                      request, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const EngineStream *const stream = request->stream;
    const EngineSideSection *const section = request->section;
    const EngineSeal *const seal = request->seal;
    unsigned long long head[APXREP_INPUT_HEAD_WORDS];
    apxrep_input_head_words(stream, section, seal, head);
    const size_t limbs = (size_t)((stream->bits + 31ull) / 32ull);
    FILE *const iapx = fopen(request->path, "wb");
    int ok =
        APXREP_IO(iapx != NULL, request->path, error) &&
        APXREP_IO(apxrep_head_write(iapx, APXREP_KIND_CRYSTAL) != 0, iapx, error) &&
        APXREP_IO(apxrep_words_write(iapx, head, APXREP_INPUT_HEAD_WORDS) != 0, head, error) &&
        apxrep_seal_write(iapx, seal, error) &&
        APXREP_IO(apxrep_words_write(iapx, stream->offsets, (size_t)stream->chunks) != 0, stream->offsets, error) &&
        APXREP_IO(apxrep_limbs_write(iapx, stream->stream, limbs) != 0, stream->stream, error);
    if (ok && (head[APXREP_HEAD_LEAVES] != 0ull))
    {
        ok =
            APXREP_IO(fwrite(section->packed, 1u, (size_t)section->packed_bytes, iapx) == (size_t)section->packed_bytes,
                      section->packed, error) &&
            apxrep_members_write(iapx, &section->side, error);
    }
    if (iapx != NULL)
    {
        ok = APXREP_IO(fclose(iapx) == 0, iapx, error) && ok;
    }
    return ok;
}

int apxrep_input_head_from(const char *path, FILE *iapx, EngineStream *stream,
                           unsigned long long head[APXREP_INPUT_HEAD_WORDS], EngineError *error)
{
    memset(head, 0, APXREP_INPUT_HEAD_WORDS * sizeof(unsigned long long));
    const int ok = APXREP_IO(iapx != NULL, path, error) &&
                   APXREP_IO(apxrep_head_read(iapx, APXREP_KIND_CRYSTAL) != 0, iapx, error) &&
                   APXREP_IO(apxrep_words_read(iapx, head, APXREP_INPUT_HEAD_WORDS) != 0, head, error);
    memcpy(stream->extent, &head[APXREP_HEAD_EXTENT], 4u * sizeof(unsigned long long));
    stream->chunks = head[APXREP_HEAD_CHUNKS];
    stream->bits = head[APXREP_HEAD_BITS];
    stream->lane_offset = head[APXREP_HEAD_LANE_OFFSET];
    const unsigned long long lanes = ok ? apxrep_lanes(stream->extent) : 0ull;
    const int unsided = (head[APXREP_HEAD_SIDE_BYTES] == 0ull) && (head[APXREP_HEAD_PACKED_BYTES] == 0ull) &&
                        (head[APXREP_HEAD_NAMES_BYTES] == 0ull);
    return ok && APXREP_CHECK((lanes != 0ull) && (stream->chunks <= lanes) && (stream->bits <= (64ull * lanes)) &&
                                  ((head[APXREP_HEAD_LEAVES] != 0ull) || unsided) &&
                                  (head[APXREP_HEAD_LANE_NODES] <= ((3ull * lanes) + 1ull)),
                              head, error, ENGINE_ERROR_LOGIC);
}
