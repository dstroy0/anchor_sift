// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// krep_io.cu: words, limbs, the head and the seal
#include "krep_internal.h"

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
    return (fwrite(KREP_MAGIC, 1u, 8u, file) == 8u) && (fwrite(kind, 1u, 4u, file) == 4u) &&
           (krep_limbs_write(file, &version, 1u) != 0);
}

extern "C" int krep_head_read(FILE *file, const char *kind)
{
    unsigned char magic[8];
    char named[4];
    unsigned int version = 0u;
    return (fread(magic, 1u, 8u, file) == 8u) && (memcmp(magic, KREP_MAGIC, 8u) == 0) &&
           (fread(named, 1u, 4u, file) == 4u) && (memcmp(named, kind, 4u) == 0) &&
           (krep_limbs_read(file, &version, 1u) != 0) && (version == KREP_VERSION);
}

unsigned long long krep_lanes(const unsigned long long extent[4])
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
    const unsigned long long side =
        (leaves != 0ull) ? (section->packed_bytes + (8ull * krep_member_words(leaves)) + krep_names_bytes(section))
                         : 0ull;
    return KREP_HEAD_BYTES + (8ull * KREP_CRYSTAL_HEAD_WORDS) + (ENGINE_SIGNUM_BYTES * krep_seal_nodes(seal)) +
           (8ull * stream->chunks) + (4ull * ((stream->bits + 31ull) / 32ull)) + side;
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
                   seal->roots, error) &&
           KREP_IO(fwrite(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, crystal) ==
                       (size_t)seal->lane_count,
                   seal->lane_nodes, error) &&
           KREP_IO(fwrite(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, crystal) ==
                       (size_t)seal->chunk_count,
                   seal->chunk_leaves, error);
}

int krep_seal_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineSeal *seal,
                   EngineError *error)
{
    seal->lane_count = head[KREP_HEAD_LANE_NODES];
    seal->chunk_count = head[KREP_HEAD_CHUNKS];
    seal->lane_nodes = (EngineSignum *)calloc((size_t)seal->lane_count + 1u, sizeof(EngineSignum));
    seal->chunk_leaves = (EngineSignum *)calloc((size_t)seal->chunk_count + 1u, sizeof(EngineSignum));
    return KREP_CHECK((seal->lane_nodes != NULL) && (seal->chunk_leaves != NULL), seal, error, ENGINE_ERROR_RESOURCE) &&
           KREP_IO(fread(seal->roots, sizeof(EngineSignum), ENGINE_SEAL_ROOTS, crystal) == ENGINE_SEAL_ROOTS,
                   seal->roots, error) &&
           KREP_IO(fread(seal->lane_nodes, sizeof(EngineSignum), (size_t)seal->lane_count, crystal) ==
                       (size_t)seal->lane_count,
                   seal->lane_nodes, error) &&
           KREP_IO(fread(seal->chunk_leaves, sizeof(EngineSignum), (size_t)seal->chunk_count, crystal) ==
                       (size_t)seal->chunk_count,
                   seal->chunk_leaves, error);
}

static int krep_members_write(FILE *crystal, const EngineSideBytes *side, EngineError *error)
{
    const size_t leaves = (size_t)side->leaves;
    return KREP_IO(krep_words_write(crystal, side->pixel_at, leaves) != 0, side->pixel_at, error) &&
           KREP_IO(krep_words_write(crystal, side->pixel_kept, leaves) != 0, side->pixel_kept, error) &&
           KREP_IO(krep_words_write(crystal, side->byte_start, leaves + 1u) != 0, side->byte_start, error) &&
           KREP_IO(krep_words_write(crystal, side->name_start, leaves + 1u) != 0, side->name_start, error) &&
           KREP_IO(krep_words_write(crystal, side->member_crc, leaves) != 0, side->member_crc, error) &&
           KREP_IO(krep_words_write(crystal, side->member_bytes, leaves) != 0, side->member_bytes, error) &&
           KREP_IO(fwrite(side->names, 1u, (size_t)side->name_start[leaves], crystal) ==
                       (size_t)side->name_start[leaves],
                   side->names, error);
}

extern "C" int krep_crystal_write(const KrepCrystalRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!KREP_CHECK((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL) &&
                        (request->seal->chunk_count == request->stream->chunks),
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
    int ok = KREP_IO(crystal != NULL, request->path, error) &&
             KREP_IO(krep_head_write(crystal, KREP_KIND_CRYSTAL) != 0, crystal, error) &&
             KREP_IO(krep_words_write(crystal, head, KREP_CRYSTAL_HEAD_WORDS) != 0, head, error) &&
             krep_seal_write(crystal, seal, error) &&
             KREP_IO(krep_words_write(crystal, stream->offsets, (size_t)stream->chunks) != 0, stream->offsets, error) &&
             KREP_IO(krep_limbs_write(crystal, stream->stream, limbs) != 0, stream->stream, error);
    if (ok && (head[KREP_HEAD_LEAVES] != 0ull))
    {
        ok = KREP_IO(fwrite(section->packed, 1u, (size_t)section->packed_bytes, crystal) ==
                         (size_t)section->packed_bytes,
                     section->packed, error) &&
             krep_members_write(crystal, &section->side, error);
    }
    if (crystal != NULL)
    {
        ok = KREP_IO(fclose(crystal) == 0, crystal, error) && ok;
    }
    return ok;
}

int krep_crystal_head_from(const char *path, FILE *crystal, EngineStream *stream,
                           unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineError *error)
{
    memset(head, 0, KREP_CRYSTAL_HEAD_WORDS * sizeof(unsigned long long));
    const int ok = KREP_IO(crystal != NULL, path, error) &&
                   KREP_IO(krep_head_read(crystal, KREP_KIND_CRYSTAL) != 0, crystal, error) &&
                   KREP_IO(krep_words_read(crystal, head, KREP_CRYSTAL_HEAD_WORDS) != 0, head, error);
    memcpy(stream->extent, &head[KREP_HEAD_EXTENT], 4u * sizeof(unsigned long long));
    stream->chunks = head[KREP_HEAD_CHUNKS];
    stream->bits = head[KREP_HEAD_BITS];
    stream->lane_offset = head[KREP_HEAD_LANE_OFFSET];
    const unsigned long long lanes = ok ? krep_lanes(stream->extent) : 0ull;
    const int unsided = (head[KREP_HEAD_SIDE_BYTES] == 0ull) && (head[KREP_HEAD_PACKED_BYTES] == 0ull) &&
                        (head[KREP_HEAD_NAMES_BYTES] == 0ull);
    return ok && KREP_CHECK((lanes != 0ull) && (stream->chunks <= lanes) && (stream->bits <= (64ull * lanes)) &&
                                ((head[KREP_HEAD_LEAVES] != 0ull) || unsided) &&
                                (head[KREP_HEAD_LANE_NODES] <= ((3ull * lanes) + 1ull)),
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
    return KREP_CHECK((side->pixel_at != NULL) && (side->pixel_kept != NULL) && (side->byte_start != NULL) &&
                          (side->name_start != NULL) && (side->member_crc != NULL) && (side->member_bytes != NULL) &&
                          (side->names != NULL),
                      side, error, ENGINE_ERROR_RESOURCE) &&
           KREP_IO(krep_words_read(crystal, side->pixel_at, leaves) != 0, side->pixel_at, error) &&
           KREP_IO(krep_words_read(crystal, side->pixel_kept, leaves) != 0, side->pixel_kept, error) &&
           KREP_IO(krep_words_read(crystal, side->byte_start, leaves + 1u) != 0, side->byte_start, error) &&
           KREP_IO(krep_words_read(crystal, side->name_start, leaves + 1u) != 0, side->name_start, error) &&
           KREP_CHECK((side->byte_start[leaves] == head[KREP_HEAD_SIDE_BYTES]) &&
                          (side->name_start[leaves] == head[KREP_HEAD_NAMES_BYTES]),
                      side, error, ENGINE_ERROR_LOGIC) &&
           KREP_IO(krep_words_read(crystal, side->member_crc, leaves) != 0, side->member_crc, error) &&
           KREP_IO(krep_words_read(crystal, side->member_bytes, leaves) != 0, side->member_bytes, error) &&
           KREP_IO(fread(side->names, 1u, (size_t)head[KREP_HEAD_NAMES_BYTES], crystal) ==
                       (size_t)head[KREP_HEAD_NAMES_BYTES],
                   side->names, error);
}

int krep_side_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineSideSection *section,
                   EngineError *error)
{
    memset(section, 0, sizeof(*section));
    if (head[KREP_HEAD_LEAVES] == 0ull)
    {
        return 1;
    }
    const unsigned long long packed = head[KREP_HEAD_PACKED_BYTES];
    section->packed_bytes = packed;
    section->packed = (unsigned char *)malloc((size_t)packed + 1u);
    return KREP_CHECK(section->packed != NULL, &section->packed, error, ENGINE_ERROR_RESOURCE) &&
           KREP_IO(fread(section->packed, 1u, (size_t)packed, crystal) == (size_t)packed, section->packed, error) &&
           krep_members_read(crystal, head, &section->side, error);
}
