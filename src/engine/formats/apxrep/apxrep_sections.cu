// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// apxrep_sections.cu: members, side, input, history and bodies
#include "apxrep_internal.h"

static int apxrep_members_read(FILE *iapx, const unsigned long long head[APXREP_INPUT_HEAD_WORDS],
                               EngineSideBytes *side, EngineError *error)
{
    const size_t leaves = (size_t)head[APXREP_HEAD_LEAVES];
    side->leaves = head[APXREP_HEAD_LEAVES];
    side->pixel_at = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->pixel_kept = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->byte_start = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->name_start = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->member_crc = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->member_bytes = (unsigned long long *)calloc(leaves + 1u, sizeof(unsigned long long));
    side->names = (char *)malloc((size_t)head[APXREP_HEAD_NAMES_BYTES] + 1u);
    return APXREP_CHECK((side->pixel_at != NULL) && (side->pixel_kept != NULL) && (side->byte_start != NULL) &&
                            (side->name_start != NULL) && (side->member_crc != NULL) && (side->member_bytes != NULL) &&
                            (side->names != NULL),
                        side, error, ENGINE_ERROR_RESOURCE) &&
           APXREP_IO(apxrep_words_read(iapx, side->pixel_at, leaves) != 0, side->pixel_at, error) &&
           APXREP_IO(apxrep_words_read(iapx, side->pixel_kept, leaves) != 0, side->pixel_kept, error) &&
           APXREP_IO(apxrep_words_read(iapx, side->byte_start, leaves + 1u) != 0, side->byte_start, error) &&
           APXREP_IO(apxrep_words_read(iapx, side->name_start, leaves + 1u) != 0, side->name_start, error) &&
           APXREP_CHECK((side->byte_start[leaves] == head[APXREP_HEAD_SIDE_BYTES]) &&
                            (side->name_start[leaves] == head[APXREP_HEAD_NAMES_BYTES]),
                        side, error, ENGINE_ERROR_LOGIC) &&
           APXREP_IO(apxrep_words_read(iapx, side->member_crc, leaves) != 0, side->member_crc, error) &&
           APXREP_IO(apxrep_words_read(iapx, side->member_bytes, leaves) != 0, side->member_bytes, error) &&
           APXREP_IO(fread(side->names, 1u, (size_t)head[APXREP_HEAD_NAMES_BYTES], iapx) ==
                         (size_t)head[APXREP_HEAD_NAMES_BYTES],
                     side->names, error);
}

static int apxrep_side_read(FILE *iapx, const unsigned long long head[APXREP_INPUT_HEAD_WORDS],
                            EngineSideSection *section, EngineError *error)
{
    memset(section, 0, sizeof(*section));
    if (head[APXREP_HEAD_LEAVES] == 0ull)
    {
        return 1;
    }
    const unsigned long long packed = head[APXREP_HEAD_PACKED_BYTES];
    section->packed_bytes = packed;
    section->packed = (unsigned char *)malloc((size_t)packed + 1u);
    return APXREP_CHECK(section->packed != NULL, &section->packed, error, ENGINE_ERROR_RESOURCE) &&
           APXREP_IO(fread(section->packed, 1u, (size_t)packed, iapx) == (size_t)packed, section->packed, error) &&
           apxrep_members_read(iapx, head, &section->side, error);
}

extern "C" int apxrep_input_head(const char *path, EngineStream *stream, EngineSignum *root, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!APXREP_CHECK((path != NULL) && (stream != NULL), &stream, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(stream, 0, sizeof(*stream));
    unsigned long long head[APXREP_INPUT_HEAD_WORDS];
    FILE *const iapx = fopen(path, "rb");
    int ok = apxrep_input_head_from(path, iapx, stream, head, error);
    if (ok && (root != NULL))
    {
        ok = APXREP_IO(fread(root, sizeof(EngineSignum), 1u, iapx) == 1u, root, error);
    }
    if (iapx != NULL)
    {
        fclose(iapx);
    }
    return ok;
}

extern "C" int apxrep_input_read(const ApxrepInputRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!APXREP_CHECK((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL), request, error,
                      ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    EngineStream *const stream = request->stream;
    EngineSeal *const seal = request->seal;
    memset(stream, 0, sizeof(*stream));
    memset(seal, 0, sizeof(*seal));
    unsigned long long head[APXREP_INPUT_HEAD_WORDS];
    EngineSideSection discarded;
    EngineSideSection *const side_section = (request->section != NULL) ? request->section : &discarded;
    memset(side_section, 0, sizeof(*side_section));
    FILE *const iapx = fopen(request->path, "rb");
    int ok =
        apxrep_input_head_from(request->path, iapx, stream, head, error) && apxrep_seal_read(iapx, head, seal, error);
    const size_t limbs = ok ? (size_t)((stream->bits + 31ull) / 32ull) : 0u;
    unsigned long long *const offsets =
        ok ? (unsigned long long *)calloc((size_t)stream->chunks + 1u, sizeof(unsigned long long)) : NULL;
    unsigned int *const limb_table = ok ? (unsigned int *)calloc(limbs + 1u, sizeof(unsigned int)) : NULL;
    ok = ok && APXREP_CHECK(offsets != NULL, &offsets, error, ENGINE_ERROR_RESOURCE) &&
         APXREP_CHECK(limb_table != NULL, &limb_table, error, ENGINE_ERROR_RESOURCE) &&
         APXREP_IO(apxrep_words_read(iapx, offsets, (size_t)stream->chunks) != 0, offsets, error) &&
         APXREP_IO(apxrep_limbs_read(iapx, limb_table, limbs) != 0, limb_table, error) &&
         apxrep_side_read(iapx, head, side_section, error) &&
         APXREP_CHECK(fgetc(iapx) == EOF, iapx, error, ENGINE_ERROR_LOGIC);
    if (iapx != NULL)
    {
        fclose(iapx);
    }
    stream->offsets = offsets;
    stream->stream = limb_table;
    if ((ok == 0) || (request->section == NULL))
    {
        apxrep_side_release(side_section);
    }
    if (ok == 0)
    {
        apxrep_input_release(stream);
        apxrep_seal_release(seal);
    }
    return ok;
}

extern "C" void apxrep_seal_release(EngineSeal *seal)
{
    free(seal->lane_nodes);
    free(seal->chunk_leaves);
    memset(seal, 0, sizeof(*seal));
}

extern "C" void apxrep_side_release(EngineSideSection *section)
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

extern "C" void apxrep_input_release(EngineStream *stream)
{
    free((void *)stream->offsets);
    free((void *)stream->stream);
    stream->offsets = NULL;
    stream->stream = NULL;
}

static size_t apxrep_history_words(const EngineHistory *history)
{
    return (size_t)(history->windows * history->extent[1] * history->extent[2] * history->extent[3]);
}

extern "C" int apxrep_history_write(const char *path, const EngineHistory *history, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!APXREP_CHECK((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long head[4] = {ENGINE_HISTORY_WINDOW, history->windows, history->payload_crc,
                                        history->cloud_crc};
    FILE *const out = fopen(path, "wb");
    int ok = APXREP_IO(out != NULL, path, error) &&
             APXREP_IO(apxrep_head_write(out, APXREP_KIND_OUTPUT) != 0, out, error) &&
             APXREP_IO(apxrep_words_write(out, history->extent, 4u) != 0, history->extent, error) &&
             APXREP_IO(apxrep_words_write(out, head, 4u) != 0, head, error) &&
             APXREP_IO(fwrite(&history->sample, sizeof(EngineSignum), 1u, out) == 1u, &history->sample, error) &&
             APXREP_IO(apxrep_words_write(out, history->cloud, (size_t)(history->windows * history->windows)) != 0,
                       history->cloud, error) &&
             APXREP_IO(apxrep_words_write(out, history->history, apxrep_history_words(history)) != 0, history->history,
                       error);
    if (out != NULL)
    {
        ok = APXREP_IO(fclose(out) == 0, out, error) && ok;
    }
    return ok;
}

extern "C" int apxrep_history_read(const char *path, EngineHistory *history, unsigned int payload, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!APXREP_CHECK((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(history, 0, sizeof(*history));
    FILE *const back = fopen(path, "rb");
    unsigned long long head[4] = {0ull, 0ull, 0ull, 0ull};
    int ok = APXREP_IO(back != NULL, path, error) &&
             APXREP_IO(apxrep_head_read(back, APXREP_KIND_OUTPUT) != 0, back, error) &&
             APXREP_IO(apxrep_words_read(back, history->extent, 4u) != 0, history->extent, error) &&
             APXREP_IO(apxrep_words_read(back, head, 4u) != 0, head, error) &&
             APXREP_IO(fread(&history->sample, sizeof(EngineSignum), 1u, back) == 1u, &history->sample, error) &&
             APXREP_CHECK((head[0] == ENGINE_HISTORY_WINDOW) && (history->extent[0] >= 2ull) &&
                              (head[1] == (((history->extent[0] - 1ull) + ENGINE_HISTORY_WINDOW - 1ull) /
                                           ENGINE_HISTORY_WINDOW)) &&
                              (head[1] <= ENGINE_HISTORY_WINDOWS_MAX) && (history->extent[1] <= (1ull << 20u)) &&
                              (history->extent[2] <= (1ull << 20u)) && (history->extent[3] <= (1ull << 20u)),
                          head, error, ENGINE_ERROR_LOGIC);
    history->windows = ok ? head[1] : 0ull;
    history->payload_crc = head[2];
    history->cloud_crc = head[3];
    const size_t entries = (size_t)(history->windows * history->windows);
    history->cloud = ok ? (unsigned long long *)calloc(entries, sizeof(unsigned long long)) : NULL;
    ok = ok && APXREP_CHECK(history->cloud != NULL, &history->cloud, error, ENGINE_ERROR_RESOURCE) &&
         APXREP_IO(apxrep_words_read(back, history->cloud, entries) != 0, history->cloud, error) &&
         APXREP_CHECK(crc_words(CRC_TABLE, history->cloud, entries) == history->cloud_crc, &history->cloud_crc, error,
                      ENGINE_ERROR_LOGIC);
    if (ok && (payload != 0u))
    {
        const size_t words = apxrep_history_words(history);
        history->history = (unsigned long long *)calloc(words, sizeof(unsigned long long));
        ok = APXREP_CHECK(history->history != NULL, &history->history, error, ENGINE_ERROR_RESOURCE) &&
             APXREP_IO(apxrep_words_read(back, history->history, words) != 0, history->history, error) &&
             APXREP_CHECK(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC) &&
             APXREP_CHECK(crc_words(CRC_TABLE, history->history, words) == history->payload_crc, &history->payload_crc,
                          error, ENGINE_ERROR_LOGIC);
    }
    if (back != NULL)
    {
        fclose(back);
    }
    if (ok == 0)
    {
        apxrep_history_release(history);
    }
    return ok;
}

extern "C" void apxrep_history_release(EngineHistory *history)
{
    free(history->cloud);
    free(history->history);
    history->cloud = NULL;
    history->history = NULL;
}

extern "C" int apxrep_bodies_write(const char *path, const EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!APXREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long counts[3] = {table->frames, table->bodies, table->crc};
    FILE *const out = fopen(path, "wb");
    int ok = APXREP_IO(out != NULL, path, error) &&
             APXREP_IO(apxrep_head_write(out, APXREP_KIND_BODIES) != 0, out, error) &&
             APXREP_IO(apxrep_words_write(out, table->extent, 4u) != 0, table->extent, error) &&
             APXREP_IO(apxrep_words_write(out, counts, 3u) != 0, counts, error) &&
             APXREP_IO(apxrep_words_write(out, table->frame_start, (size_t)table->frames + 1u) != 0, table->frame_start,
                       error) &&
             APXREP_IO(apxrep_words_write(out, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0,
                       table->words, error);
    if (out != NULL)
    {
        ok = APXREP_IO(fclose(out) == 0, out, error) && ok;
    }
    return ok;
}

extern "C" int apxrep_bodies_read(const char *path, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!APXREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(table, 0, sizeof(*table));
    FILE *const back = fopen(path, "rb");
    unsigned long long counts[3] = {0ull, 0ull, 0ull};
    int ok = APXREP_IO(back != NULL, path, error) &&
             APXREP_IO(apxrep_head_read(back, APXREP_KIND_BODIES) != 0, back, error) &&
             APXREP_IO(apxrep_words_read(back, table->extent, 4u) != 0, table->extent, error) &&
             APXREP_IO(apxrep_words_read(back, counts, 3u) != 0, counts, error) &&
             APXREP_CHECK((counts[0] == table->extent[0]) && (apxrep_lanes(table->extent) != 0ull) &&
                              (counts[1] <= apxrep_lanes(table->extent)),
                          counts, error, ENGINE_ERROR_LOGIC);
    table->frames = ok ? counts[0] : 0ull;
    table->bodies = ok ? counts[1] : 0ull;
    table->crc = counts[2];
    table->frame_start =
        ok ? (unsigned long long *)calloc((size_t)table->frames + 1u, sizeof(unsigned long long)) : NULL;
    table->words =
        ok ? (unsigned long long *)calloc((size_t)(table->bodies * ENGINE_BODY_WORDS) + 1u, sizeof(unsigned long long))
           : NULL;
    ok = ok && APXREP_CHECK(table->frame_start != NULL, &table->frame_start, error, ENGINE_ERROR_RESOURCE) &&
         APXREP_CHECK(table->words != NULL, &table->words, error, ENGINE_ERROR_RESOURCE) &&
         APXREP_IO(apxrep_words_read(back, table->frame_start, (size_t)table->frames + 1u) != 0, table->frame_start,
                   error) &&
         APXREP_IO(apxrep_words_read(back, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0,
                   table->words, error) &&
         APXREP_CHECK(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC) &&
         APXREP_CHECK(table->frame_start[table->frames] == table->bodies, table->frame_start, error,
                      ENGINE_ERROR_LOGIC) &&
         APXREP_CHECK(crc_words(CRC_TABLE, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) == table->crc,
                      &table->crc, error, ENGINE_ERROR_LOGIC);
    if (back != NULL)
    {
        fclose(back);
    }
    if (ok == 0)
    {
        apxrep_bodies_release(table);
    }
    return ok;
}

extern "C" void apxrep_bodies_release(EngineBodyTable *table)
{
    free(table->frame_start);
    free(table->words);
    table->frame_start = NULL;
    table->words = NULL;
}
