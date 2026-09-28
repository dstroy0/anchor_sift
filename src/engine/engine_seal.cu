// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_seal.cu: side bytes, the seal and the crystal's verification
#include "engine_internal.h"

int entry_side_pack(EngineSideSection *section, EngineError *error)
{
    if (section->side.leaves == 0ull)
    {
        return 1;
    }
    const unsigned long long bytes = section->side.byte_start[section->side.leaves];
    const unsigned long long capacity = deflate_raw_bound(bytes);
    section->packed = (unsigned char *)malloc((size_t)capacity + 1u);
    if (ENGINE_CHECK(section->packed != NULL, &section->packed, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    EngineBytesRequest pack;
    pack.in = section->side.bytes;
    pack.in_bytes = bytes;
    pack.out = section->packed;
    pack.out_capacity = capacity;
    const long long packed = deflate_raw_encode(&pack);
    // a packed count that is not refused is at least zero, and fits an unsigned long long exactly
    section->packed_bytes = (packed >= 0ll) ? (unsigned long long)packed : 0ull;
    return ENGINE_CHECK(packed >= 0ll, section->packed, error, ENGINE_ERROR_RESOURCE);
}

static int entry_side_unpack(EngineSideSection *section, EngineError *error)
{
    if (section->side.leaves == 0ull)
    {
        return 1;
    }
    const unsigned long long bytes = section->side.byte_start[section->side.leaves];
    section->side.bytes = (unsigned char *)malloc((size_t)bytes + 1u);
    if (ENGINE_CHECK(section->side.bytes != NULL, &section->side.bytes, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    EngineBytesRequest unpack;
    unpack.in = section->packed;
    unpack.in_bytes = section->packed_bytes;
    unpack.out = section->side.bytes;
    unpack.out_capacity = bytes;
    const long long unpacked = inflate_raw_decode(&unpack);
    // the count is compared against a size in memory, which fits a long long
    return ENGINE_CHECK(unpacked == (long long)bytes, section->side.bytes, error, ENGINE_ERROR_LOGIC);
}

int entry_side_same(const EngineSideBytes *one, const EngineSideBytes *other)
{
    const size_t leaves = (size_t)one->leaves;
    const size_t words = leaves * sizeof(unsigned long long);
    const size_t fenced = (leaves + 1u) * sizeof(unsigned long long);
    if (one->leaves != other->leaves)
    {
        return 0;
    }
    if (leaves == 0u)
    {
        return 1;
    }
    return (memcmp(one->pixel_at, other->pixel_at, words) == 0) &&
           (memcmp(one->pixel_kept, other->pixel_kept, words) == 0) &&
           (memcmp(one->byte_start, other->byte_start, fenced) == 0) &&
           (memcmp(one->name_start, other->name_start, fenced) == 0) &&
           (memcmp(one->member_crc, other->member_crc, words) == 0) &&
           (memcmp(one->member_bytes, other->member_bytes, words) == 0) &&
           (memcmp(one->bytes, other->bytes, (size_t)one->byte_start[leaves]) == 0) &&
           (memcmp(one->names, other->names, (size_t)one->name_start[leaves]) == 0);
}

#define ENTRY_SAMPLE_WORDS 12u

#define ENTRY_SAMPLE_ROOTS 4u

int entry_signum_same(const EngineSignum *one, const EngineSignum *other)
{
    return memcmp(one->bytes, other->bytes, ENGINE_SIGNUM_BYTES) == 0;
}

static int entry_keyed(ObsignatioLevel level, const unsigned char *bytes, unsigned long long count, EngineSignum *out,
                       EngineError *error)
{
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    if (obsignatio_level_key(level, key, error) != 0L)
    {
        return 0;
    }
    const ObsignatioSignumRequest request = {bytes, count, key, OBSIGNATIO_MODE_KEYED, out->bytes, ENGINE_SIGNUM_BYTES,
                                             error};
    return obsignatio_signum(&request) == 0L;
}

static void entry_words_place(unsigned char *out, const unsigned long long *words, unsigned long long count)
{
    for (unsigned long long word = 0ull; word < count; word += 1ull)
    {
        for (unsigned int place = 0u; place < 8u; place += 1u)
        {
            // one byte of the word, shifted down and masked, fits an unsigned char
            out[(8ull * word) + place] = (unsigned char)((words[word] >> (8u * place)) & 0xFFull);
        }
    }
}

static int entry_seal_lanes(const unsigned short *device_lanes, const unsigned long long extent[4], EngineSignum *nodes,
                            unsigned long long count, EngineError *error)
{
    const size_t bytes = (size_t)count * sizeof(EngineSignum);
    unsigned char *device_nodes = NULL;
    int ok = ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_nodes, bytes), &device_nodes, error);
    if (ok)
    {
        const ObsignatioLanesRequest request = {device_lanes, extent, device_nodes, error};
        ok = (obsignatio_lanes(&request) == 0L) &&
             ENGINE_STATUS_CHECK(cudaMemcpy(nodes, device_nodes, bytes, cudaMemcpyDeviceToHost), nodes, error);
    }
    cudaFree(device_nodes);
    return ok;
}

static int entry_seal_chunks(const EngineStream *stream, EngineSignum *leaves, EngineError *error)
{
    if (stream->chunks == 0ull)
    {
        return 1;
    }
    const size_t limbs = (size_t)((stream->bits + 31ull) / 32ull);
    const size_t leaf_bytes = (size_t)stream->chunks * sizeof(EngineSignum);
    unsigned long long *device_offsets = NULL;
    unsigned int *device_limbs = NULL;
    unsigned char *device_leaves = NULL;
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    int ok =
        (obsignatio_level_key(OBSIGNATIO_LEVEL_CHUNK, key, error) == 0L) &&
        ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_offsets, (size_t)stream->chunks * sizeof(unsigned long long)),
                            &device_offsets, error) &&
        ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_limbs, (limbs + 1u) * sizeof(unsigned int)), &device_limbs,
                            error) &&
        ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_leaves, leaf_bytes), &device_leaves, error) &&
        ENGINE_STATUS_CHECK(cudaMemcpy(device_offsets, stream->offsets,
                                       (size_t)stream->chunks * sizeof(unsigned long long), cudaMemcpyHostToDevice),
                            device_offsets, error) &&
        ENGINE_STATUS_CHECK(
            cudaMemcpy(device_limbs, stream->stream, limbs * sizeof(unsigned int), cudaMemcpyHostToDevice),
            device_limbs, error);
    if (ok)
    {
        const ObsignatioBitsRequest request = {device_limbs, device_offsets,        stream->chunks, stream->bits,
                                               key,          OBSIGNATIO_MODE_KEYED, device_leaves,  error};
        ok = (obsignatio_bits(&request) == 0L) &&
             ENGINE_STATUS_CHECK(cudaMemcpy(leaves, device_leaves, leaf_bytes, cudaMemcpyDeviceToHost), leaves, error);
    }
    cudaFree(device_leaves);
    cudaFree(device_limbs);
    cudaFree(device_offsets);
    return ok;
}

static int entry_seal_stream(const EngineStream *stream, const EngineSignum *leaves, EngineSignum *root,
                             EngineError *error)
{
    const unsigned long long offset_bytes = 8ull * stream->chunks;
    const unsigned long long bytes = offset_bytes + 8ull + (ENGINE_SIGNUM_BYTES * stream->chunks);
    unsigned char *const buffer = (unsigned char *)malloc((size_t)bytes);
    if (ENGINE_CHECK(buffer != NULL, &buffer, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    entry_words_place(buffer, stream->offsets, stream->chunks);
    entry_words_place(&buffer[offset_bytes], &stream->bits, 1ull);
    memcpy(&buffer[offset_bytes + 8ull], leaves, (size_t)(ENGINE_SIGNUM_BYTES * stream->chunks));
    const int ok = entry_keyed(OBSIGNATIO_LEVEL_STREAM, buffer, bytes, root, error);
    free(buffer);
    return ok;
}

static int entry_seal_side_stored(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const unsigned long long stored = (section->side.leaves != 0ull) ? section->packed_bytes : 0ull;
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE_STORED, section->packed, stored, root, error);
}

static int entry_seal_side_inflated(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const unsigned long long inflated =
        (section->side.leaves != 0ull) ? section->side.byte_start[section->side.leaves] : 0ull;
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE_INFLATED, section->side.bytes, inflated, root, error);
}

static int entry_seal_side_root(EngineSignum *roots, EngineError *error)
{
    unsigned char both[2u * ENGINE_SIGNUM_BYTES];
    memcpy(both, roots[ENGINE_SEAL_SIDE_STORED].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&both[ENGINE_SIGNUM_BYTES], roots[ENGINE_SEAL_SIDE_INFLATED].bytes, ENGINE_SIGNUM_BYTES);
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE, both, sizeof(both), &roots[ENGINE_SEAL_SIDE], error);
}

static int entry_seal_members(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const EngineSideBytes *const side = &section->side;
    const unsigned long long leaves = side->leaves;
    const unsigned long long words = (leaves != 0ull) ? ((6ull * leaves) + 2ull) : 0ull;
    const unsigned long long names = (leaves != 0ull) ? side->name_start[leaves] : 0ull;
    const unsigned long long bytes = (8ull * words) + names;
    unsigned char *const buffer = (unsigned char *)malloc((size_t)bytes + 1u);
    if (ENGINE_CHECK(buffer != NULL, &buffer, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    if (leaves != 0ull)
    {
        unsigned char *at = buffer;
        entry_words_place(at, side->pixel_at, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->pixel_kept, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->byte_start, leaves + 1ull);
        at = &at[8ull * (leaves + 1ull)];
        entry_words_place(at, side->name_start, leaves + 1ull);
        at = &at[8ull * (leaves + 1ull)];
        entry_words_place(at, side->member_crc, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->member_bytes, leaves);
        at = &at[8ull * leaves];
        memcpy(at, side->names, (size_t)names);
    }
    const int ok = entry_keyed(OBSIGNATIO_LEVEL_MEMBERS, buffer, bytes, root, error);
    free(buffer);
    return ok;
}

static int entry_seal_sample(const EngineStream *stream, const EngineSideSection *section, EngineSeal *seal,
                             EngineError *error)
{
    const EngineSideBytes *const side = &section->side;
    const int sided = side->leaves != 0ull;
    const unsigned long long words[ENTRY_SAMPLE_WORDS] = {stream->extent[0],
                                                          stream->extent[1],
                                                          stream->extent[2],
                                                          stream->extent[3],
                                                          stream->chunks,
                                                          stream->bits,
                                                          stream->lane_offset,
                                                          side->leaves,
                                                          sided ? side->byte_start[side->leaves] : 0ull,
                                                          sided ? section->packed_bytes : 0ull,
                                                          sided ? side->name_start[side->leaves] : 0ull,
                                                          seal->lane_count};
    unsigned char byte[(8u * ENTRY_SAMPLE_WORDS) + (ENTRY_SAMPLE_ROOTS * ENGINE_SIGNUM_BYTES)];
    entry_words_place(byte, words, ENTRY_SAMPLE_WORDS);
    unsigned char *const roots = &byte[8u * ENTRY_SAMPLE_WORDS];
    memcpy(roots, seal->lane_nodes[seal->lane_count - 1ull].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_STREAM].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[2u * ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_SIDE].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[3u * ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_MEMBERS].bytes, ENGINE_SIGNUM_BYTES);
    return entry_keyed(OBSIGNATIO_LEVEL_SAMPLE, byte, sizeof(byte), &seal->roots[ENGINE_SEAL_SAMPLE], error);
}

static int entry_seal_open(const EngineStream *stream, EngineSeal *seal, EngineError *error)
{
    memset(seal, 0, sizeof(*seal));
    seal->lane_count = obsignatio_lanes_nodes(stream->extent);
    seal->chunk_count = stream->chunks;
    seal->lane_nodes = (EngineSignum *)calloc((size_t)seal->lane_count + 1u, sizeof(EngineSignum));
    seal->chunk_leaves = (EngineSignum *)calloc((size_t)seal->chunk_count + 1u, sizeof(EngineSignum));
    return ENGINE_CHECK((seal->lane_count != 0ull) && (seal->lane_nodes != NULL) && (seal->chunk_leaves != NULL), seal,
                        error, ENGINE_ERROR_RESOURCE);
}

int entry_seal_make(const unsigned short *device_lanes, const EngineStream *stream, const EngineSideSection *section,
                    EngineSeal *seal, EngineError *error)
{
    const int ok = entry_seal_open(stream, seal, error) &&
                   entry_seal_lanes(device_lanes, stream->extent, seal->lane_nodes, seal->lane_count, error) &&
                   entry_seal_chunks(stream, seal->chunk_leaves, error) &&
                   entry_seal_stream(stream, seal->chunk_leaves, &seal->roots[ENGINE_SEAL_STREAM], error) &&
                   entry_seal_side_stored(section, &seal->roots[ENGINE_SEAL_SIDE_STORED], error) &&
                   entry_seal_side_inflated(section, &seal->roots[ENGINE_SEAL_SIDE_INFLATED], error) &&
                   entry_seal_side_root(seal->roots, error) &&
                   entry_seal_members(section, &seal->roots[ENGINE_SEAL_MEMBERS], error) &&
                   entry_seal_sample(stream, section, seal, error);
    if (ok == 0)
    {
        apxrep_seal_release(seal);
    }
    return ok;
}

static unsigned long long entry_roots_differ(const EngineSeal *fresh, const EngineSeal *stored, EngineSealRoot root)
{
    return entry_signum_same(&fresh->roots[root], &stored->roots[root]) ? 0ull : 1ull;
}

int entry_crystal_verify(const EngineStream *file, EngineSideSection *section, const EngineSeal *seal,
                         const unsigned short *device_source, unsigned short *rebuilt, EngineSampleRecord *record,
                         EngineError *error)
{
    record->crystal_read = 1ull;
    memcpy(record->extent, file->extent, sizeof(record->extent));
    record->root = seal->roots[ENGINE_SEAL_SAMPLE];
    EngineSeal fresh;
    int ok = entry_seal_open(file, &fresh, error);
    record->extent_differ =
        (ok && ((seal->lane_count != fresh.lane_count) || (seal->chunk_count != fresh.chunk_count))) ? 1ull : 0ull;
    ok = ok && ENGINE_CHECK(record->extent_differ == 0ull, seal, error, ENGINE_ERROR_LOGIC) &&
         entry_seal_chunks(file, fresh.chunk_leaves, error);
    for (unsigned long long chunk = 0ull; ok && (chunk < fresh.chunk_count); chunk += 1ull)
    {
        const int differs = entry_signum_same(&fresh.chunk_leaves[chunk], &seal->chunk_leaves[chunk]) ? 0 : 1;
        record->first_chunk_differ =
            ((differs != 0) && (record->chunks_differ == 0ull)) ? chunk : record->first_chunk_differ;
        record->chunks_differ += (differs != 0) ? 1ull : 0ull;
    }
    ok = ok && entry_seal_stream(file, fresh.chunk_leaves, &fresh.roots[ENGINE_SEAL_STREAM], error) &&
         entry_seal_side_stored(section, &fresh.roots[ENGINE_SEAL_SIDE_STORED], error) &&
         entry_seal_members(section, &fresh.roots[ENGINE_SEAL_MEMBERS], error);
    if (ok)
    {
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_STREAM) +
                                entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE_STORED) +
                                entry_roots_differ(&fresh, seal, ENGINE_SEAL_MEMBERS);
    }
    const unsigned short *device_rebuilt = NULL;
    ok = ok &&
         ENGINE_CHECK((record->chunks_differ == 0ull) && (record->roots_differ == 0ull), seal, error,
                      ENGINE_ERROR_LOGIC) &&
         entry_side_unpack(section, error) &&
         entry_seal_side_inflated(section, &fresh.roots[ENGINE_SEAL_SIDE_INFLATED], error) &&
         entry_seal_side_root(fresh.roots, error);
    if (ok)
    {
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE_INFLATED) +
                                entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE);
    }
    ok = ok && ENGINE_CHECK(record->roots_differ == 0ull, seal, error, ENGINE_ERROR_LOGIC) &&
         (entry_iapx_decode(file, device_source, rebuilt, &record->voxels_differ, &device_rebuilt, error) != 0) &&
         entry_seal_lanes(device_rebuilt, file->extent, fresh.lane_nodes, fresh.lane_count, error);
    const unsigned long long rows = file->extent[0] * file->extent[1] * file->extent[2];
    for (unsigned long long node = 0ull; ok && (node < fresh.lane_count); node += 1ull)
    {
        const int differs = entry_signum_same(&fresh.lane_nodes[node], &seal->lane_nodes[node]) ? 0 : 1;
        const int row = node < rows;
        record->first_row_differ =
            ((differs != 0) && row && (record->rows_differ == 0ull)) ? node : record->first_row_differ;
        record->rows_differ += ((differs != 0) && row) ? 1ull : 0ull;
        record->roots_differ += ((differs != 0) && !row) ? 1ull : 0ull;
    }
    ok = ok && entry_seal_sample(file, section, &fresh, error);
    if (ok)
    {
        record->rebuilt_root = fresh.roots[ENGINE_SEAL_SAMPLE];
        record->root_rebuilt = 1ull;
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_SAMPLE);
    }
    ok = ok && ENGINE_CHECK((record->rows_differ == 0ull) && (record->roots_differ == 0ull) &&
                                (record->voxels_differ == 0ull),
                            seal, error, ENGINE_ERROR_LOGIC);
    apxrep_seal_release(&fresh);
    return ok;
}

int entry_set_root(const EngineSignum *roots, unsigned long long count, EngineSignum *root, EngineError *error)
{
    // the roots are an array of 32-byte signa, hashed as their bytes
    return entry_keyed(OBSIGNATIO_LEVEL_SET, (const unsigned char *)roots, count * ENGINE_SIGNUM_BYTES, root, error);
}

void entry_signum_text(ScripturaLine *line, const EngineSignum *signum)
{
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        scriptura_hex(line, signum->bytes[byte], 2u);
    }
}

void entry_percent(ScripturaLine *line, unsigned long long part, unsigned long long total)
{
    scriptura_decimal_columns(line, (total != 0ull) ? ((100ull * part) / total) : 0ull, 3u);
    scriptura_character(line, '.');
    scriptura_decimal(line, (total != 0ull) ? (((1000ull * part) / total) % 10ull) : 0ull, 1u);
    scriptura_character(line, '%');
}

unsigned long long entry_report_capacity(char *const *samples, unsigned long long reached, const char *source,
                                         const char *set)
{
    const unsigned long long fixed =
        scriptura_length(source, ENTRY_PATH_CAPACITY) + scriptura_length(set, ENTRY_PATH_CAPACITY);
    unsigned long long needed = (2ull * ENTRY_ROW_TEXT) + fixed;
    for (unsigned long long sample = 0ull; sample < reached; sample += 1ull)
    {
        needed += ENTRY_ROW_TEXT + fixed + scriptura_length(samples[sample], ENTRY_PATH_CAPACITY);
    }
    return needed;
}

void entry_report_total(ScripturaLine *line, const EngineSetReport *report, unsigned int count)
{
    scriptura_text(line, "\n  ");
    scriptura_decimal(line, report->sealed, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " samples held, ");
    scriptura_decimal(line, report->voxels, 1u);
    scriptura_text(line, " voxels: ");
    scriptura_decimal(line, report->crystal_bytes, 1u);
    scriptura_text(line, " bytes of ");
    scriptura_decimal(line, report->raw_bytes, 1u);
    scriptura_text(line, " raw, ");
    entry_percent(line, report->crystal_bytes, report->raw_bytes);
    scriptura_text(line, ", in ");
    scriptura_decimal(line, report->microseconds / 1000ull, 1u);
    if (report->sealed != count)
    {
        scriptura_text(line, " ms\n  no set root: it seals every sample's, and not every sample held\n");
        return;
    }
    scriptura_text(line, " ms\n  the set's root, sealing every sample's in the order named: ");
    entry_signum_text(line, &report->set_root);
    scriptura_character(line, '\n');
}

void entry_seal_failure(ScripturaLine *line, const EngineSampleRecord *record)
{
    if (record->crystal_read == 0ull)
    {
        scriptura_text(line, "the file did not read as a crystal (missing, short, or laid out otherwise than its head "
                             "describes), so no node was compared");
        return;
    }
    if (record->extent_differ != 0ull)
    {
        scriptura_text(line, "the head's extent disagrees with its seal's node counts, so no node was compared");
        return;
    }
    scriptura_decimal(line, record->chunks_differ, 1u);
    scriptura_text(line, " stored chunks differ");
    if (record->chunks_differ != 0ull)
    {
        scriptura_text(line, " (first chunk ");
        scriptura_decimal(line, record->first_chunk_differ, 1u);
        scriptura_character(line, ')');
    }
    scriptura_text(line, ", ");
    scriptura_decimal(line, record->rows_differ, 1u);
    scriptura_text(line, " rows differ");
    if ((record->rows_differ != 0ull) && (record->extent[1] != 0ull) && (record->extent[2] != 0ull))
    {
        const unsigned long long row = record->first_row_differ;
        scriptura_text(line, " (first at t ");
        scriptura_decimal(line, row / (record->extent[1] * record->extent[2]), 1u);
        scriptura_text(line, ", z ");
        scriptura_decimal(line, (row / record->extent[2]) % record->extent[1], 1u);
        scriptura_text(line, ", y ");
        scriptura_decimal(line, row % record->extent[2], 1u);
        scriptura_character(line, ')');
    }
    scriptura_text(line, ", ");
    scriptura_decimal(line, record->roots_differ, 1u);
    scriptura_text(line, " other nodes differ; ");
    if (record->root_rebuilt == 0ull)
    {
        scriptura_text(line, "the check stopped before a root was rebuilt, against the file's ");
        entry_signum_text(line, &record->root);
        return;
    }
    scriptura_text(line, "root ");
    entry_signum_text(line, &record->rebuilt_root);
    scriptura_text(line, " rebuilt against the file's ");
    entry_signum_text(line, &record->root);
}
