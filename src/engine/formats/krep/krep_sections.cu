// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// krep_sections.cu: the crystal, side, history, bodies and forms
#include "krep_internal.h"

extern "C" int krep_crystal_head(const char *path, EngineStream *stream, EngineSignum *root, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_CHECK((path != NULL) && (stream != NULL), &stream, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(stream, 0, sizeof(*stream));
    unsigned long long head[KREP_CRYSTAL_HEAD_WORDS];
    FILE *const crystal = fopen(path, "rb");
    int ok = krep_crystal_head_from(path, crystal, stream, head, error);
    if (ok && (root != NULL))
    {
        ok = KREP_IO(fread(root, sizeof(EngineSignum), 1u, crystal) == 1u, root, error);
    }
    if (crystal != NULL)
    {
        fclose(crystal);
    }
    return ok;
}

extern "C" int krep_crystal_read(const KrepCrystalRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!KREP_CHECK((request->path != NULL) && (request->stream != NULL) && (request->seal != NULL), request, error,
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
    EngineSideSection *const side_section = (request->section != NULL) ? request->section : &discarded;
    memset(side_section, 0, sizeof(*side_section));
    FILE *const crystal = fopen(request->path, "rb");
    int ok = krep_crystal_head_from(request->path, crystal, stream, head, error) &&
             krep_seal_read(crystal, head, seal, error);
    const size_t limbs = ok ? (size_t)((stream->bits + 31ull) / 32ull) : 0u;
    unsigned long long *const offsets =
        ok ? (unsigned long long *)calloc((size_t)stream->chunks + 1u, sizeof(unsigned long long)) : NULL;
    unsigned int *const limb_table = ok ? (unsigned int *)calloc(limbs + 1u, sizeof(unsigned int)) : NULL;
    ok = ok && KREP_CHECK(offsets != NULL, &offsets, error, ENGINE_ERROR_RESOURCE) &&
         KREP_CHECK(limb_table != NULL, &limb_table, error, ENGINE_ERROR_RESOURCE) &&
         KREP_IO(krep_words_read(crystal, offsets, (size_t)stream->chunks) != 0, offsets, error) &&
         KREP_IO(krep_limbs_read(crystal, limb_table, limbs) != 0, limb_table, error) &&
         krep_side_read(crystal, head, side_section, error) &&
         KREP_CHECK(fgetc(crystal) == EOF, crystal, error, ENGINE_ERROR_LOGIC);
    if (crystal != NULL)
    {
        fclose(crystal);
    }
    stream->offsets = offsets;
    stream->stream = limb_table;
    if ((ok == 0) || (request->section == NULL))
    {
        krep_side_release(side_section);
    }
    if (ok == 0)
    {
        krep_crystal_release(stream);
        krep_seal_release(seal);
    }
    return ok;
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
    if (!KREP_CHECK((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long head[4] = {ENGINE_HISTORY_WINDOW, history->windows, history->payload_crc,
                                        history->cloud_crc};
    FILE *const out = fopen(path, "wb");
    int ok =
        KREP_IO(out != NULL, path, error) && KREP_IO(krep_head_write(out, KREP_KIND_NOISE_FLOOR) != 0, out, error) &&
        KREP_IO(krep_words_write(out, history->extent, 4u) != 0, history->extent, error) &&
        KREP_IO(krep_words_write(out, head, 4u) != 0, head, error) &&
        KREP_IO(fwrite(&history->sample, sizeof(EngineSignum), 1u, out) == 1u, &history->sample, error) &&
        KREP_IO(krep_words_write(out, history->cloud, (size_t)(history->windows * history->windows)) != 0,
                history->cloud, error) &&
        KREP_IO(krep_words_write(out, history->history, krep_history_words(history)) != 0, history->history, error);
    if (out != NULL)
    {
        ok = KREP_IO(fclose(out) == 0, out, error) && ok;
    }
    return ok;
}

extern "C" int krep_history_read(const char *path, EngineHistory *history, unsigned int payload, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_CHECK((path != NULL) && (history != NULL), &history, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(history, 0, sizeof(*history));
    FILE *const back = fopen(path, "rb");
    unsigned long long head[4] = {0ull, 0ull, 0ull, 0ull};
    int ok = KREP_IO(back != NULL, path, error) &&
             KREP_IO(krep_head_read(back, KREP_KIND_NOISE_FLOOR) != 0, back, error) &&
             KREP_IO(krep_words_read(back, history->extent, 4u) != 0, history->extent, error) &&
             KREP_IO(krep_words_read(back, head, 4u) != 0, head, error) &&
             KREP_IO(fread(&history->sample, sizeof(EngineSignum), 1u, back) == 1u, &history->sample, error) &&
             KREP_CHECK((head[0] == ENGINE_HISTORY_WINDOW) && (history->extent[0] >= 2ull) &&
                            (head[1] ==
                             (((history->extent[0] - 1ull) + ENGINE_HISTORY_WINDOW - 1ull) / ENGINE_HISTORY_WINDOW)) &&
                            (head[1] <= ENGINE_HISTORY_WINDOWS_MAX) && (history->extent[1] <= (1ull << 20u)) &&
                            (history->extent[2] <= (1ull << 20u)) && (history->extent[3] <= (1ull << 20u)),
                        head, error, ENGINE_ERROR_LOGIC);
    history->windows = ok ? head[1] : 0ull;
    history->payload_crc = head[2];
    history->cloud_crc = head[3];
    const size_t entries = (size_t)(history->windows * history->windows);
    history->cloud = ok ? (unsigned long long *)calloc(entries, sizeof(unsigned long long)) : NULL;
    ok = ok && KREP_CHECK(history->cloud != NULL, &history->cloud, error, ENGINE_ERROR_RESOURCE) &&
         KREP_IO(krep_words_read(back, history->cloud, entries) != 0, history->cloud, error) &&
         KREP_CHECK(crc_words(CRC_TABLE, history->cloud, entries) == history->cloud_crc, &history->cloud_crc, error,
                    ENGINE_ERROR_LOGIC);
    if (ok && (payload != 0u))
    {
        const size_t words = krep_history_words(history);
        history->history = (unsigned long long *)calloc(words, sizeof(unsigned long long));
        ok = KREP_CHECK(history->history != NULL, &history->history, error, ENGINE_ERROR_RESOURCE) &&
             KREP_IO(krep_words_read(back, history->history, words) != 0, history->history, error) &&
             KREP_CHECK(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC) &&
             KREP_CHECK(crc_words(CRC_TABLE, history->history, words) == history->payload_crc, &history->payload_crc,
                        error, ENGINE_ERROR_LOGIC);
    }
    if (back != NULL)
    {
        fclose(back);
    }
    if (ok == 0)
    {
        krep_history_release(history);
    }
    return ok;
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
    if (!KREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long counts[3] = {table->frames, table->bodies, table->crc};
    FILE *const out = fopen(path, "wb");
    int ok = KREP_IO(out != NULL, path, error) &&
             KREP_IO(krep_head_write(out, KREP_KIND_CONSTRUCTION_SET) != 0, out, error) &&
             KREP_IO(krep_words_write(out, table->extent, 4u) != 0, table->extent, error) &&
             KREP_IO(krep_words_write(out, counts, 3u) != 0, counts, error) &&
             KREP_IO(krep_words_write(out, table->frame_start, (size_t)table->frames + 1u) != 0, table->frame_start,
                     error) &&
             KREP_IO(krep_words_write(out, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0,
                     table->words, error);
    if (out != NULL)
    {
        ok = KREP_IO(fclose(out) == 0, out, error) && ok;
    }
    return ok;
}

extern "C" int krep_bodies_read(const char *path, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(table, 0, sizeof(*table));
    FILE *const back = fopen(path, "rb");
    unsigned long long counts[3] = {0ull, 0ull, 0ull};
    int ok = KREP_IO(back != NULL, path, error) &&
             KREP_IO(krep_head_read(back, KREP_KIND_CONSTRUCTION_SET) != 0, back, error) &&
             KREP_IO(krep_words_read(back, table->extent, 4u) != 0, table->extent, error) &&
             KREP_IO(krep_words_read(back, counts, 3u) != 0, counts, error) &&
             KREP_CHECK((counts[0] == table->extent[0]) && (krep_lanes(table->extent) != 0ull) &&
                            (counts[1] <= krep_lanes(table->extent)),
                        counts, error, ENGINE_ERROR_LOGIC);
    table->frames = ok ? counts[0] : 0ull;
    table->bodies = ok ? counts[1] : 0ull;
    table->crc = counts[2];
    table->frame_start =
        ok ? (unsigned long long *)calloc((size_t)table->frames + 1u, sizeof(unsigned long long)) : NULL;
    table->words =
        ok ? (unsigned long long *)calloc((size_t)(table->bodies * ENGINE_BODY_WORDS) + 1u, sizeof(unsigned long long))
           : NULL;
    ok =
        ok && KREP_CHECK(table->frame_start != NULL, &table->frame_start, error, ENGINE_ERROR_RESOURCE) &&
        KREP_CHECK(table->words != NULL, &table->words, error, ENGINE_ERROR_RESOURCE) &&
        KREP_IO(krep_words_read(back, table->frame_start, (size_t)table->frames + 1u) != 0, table->frame_start,
                error) &&
        KREP_IO(krep_words_read(back, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) != 0, table->words,
                error) &&
        KREP_CHECK(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC) &&
        KREP_CHECK(table->frame_start[table->frames] == table->bodies, table->frame_start, error, ENGINE_ERROR_LOGIC) &&
        KREP_CHECK(crc_words(CRC_TABLE, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS)) == table->crc,
                   &table->crc, error, ENGINE_ERROR_LOGIC);
    if (back != NULL)
    {
        fclose(back);
    }
    if (ok == 0)
    {
        krep_bodies_release(table);
    }
    return ok;
}

extern "C" void krep_bodies_release(EngineBodyTable *table)
{
    free(table->frame_start);
    free(table->words);
    table->frame_start = NULL;
    table->words = NULL;
}

extern "C" int krep_forms_write(const char *path, const KrepFormTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long counts[3] = {table->forms, table->name_words, table->crc};
    FILE *const out = fopen(path, "wb");
    int ok = KREP_IO(out != NULL, path, error) &&
             KREP_IO(krep_head_write(out, KREP_KIND_CONSTRUCTION_SET) != 0, out, error) &&
             KREP_IO(krep_words_write(out, counts, 3u) != 0, counts, error) &&
             KREP_IO(krep_words_write(out, table->words, (size_t)(table->forms + table->name_words)) != 0, table->words,
                     error);
    if (out != NULL)
    {
        ok = KREP_IO(fclose(out) == 0, out, error) && ok;
    }
    return ok;
}

extern "C" int krep_forms_read(const char *path, KrepFormTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!KREP_CHECK((path != NULL) && (table != NULL), &table, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(table, 0, sizeof(*table));
    FILE *const back = fopen(path, "rb");
    unsigned long long counts[3] = {0ull, 0ull, 0ull};
    int ok =
        KREP_IO(back != NULL, path, error) &&
        KREP_IO(krep_head_read(back, KREP_KIND_CONSTRUCTION_SET) != 0, back, error) &&
        KREP_IO(krep_words_read(back, counts, 3u) != 0, counts, error) &&
        KREP_CHECK((counts[0] <= KREP_FORMS_MAX) && (counts[1] <= KREP_FORMS_MAX), counts, error, ENGINE_ERROR_LOGIC);
    table->forms = ok ? counts[0] : 0ull;
    table->name_words = ok ? counts[1] : 0ull;
    table->crc = counts[2];
    table->words =
        ok ? (unsigned long long *)calloc((size_t)(table->forms + table->name_words) + 1u, sizeof(unsigned long long))
           : NULL;
    ok = ok && KREP_CHECK(table->words != NULL, &table->words, error, ENGINE_ERROR_RESOURCE) &&
         KREP_IO(krep_words_read(back, table->words, (size_t)(table->forms + table->name_words)) != 0, table->words,
                 error) &&
         KREP_CHECK(fgetc(back) == EOF, back, error, ENGINE_ERROR_LOGIC) &&
         KREP_CHECK(crc_words(CRC_TABLE, table->words, (size_t)(table->forms + table->name_words)) == table->crc,
                    &table->crc, error, ENGINE_ERROR_LOGIC);
    if (back != NULL)
    {
        fclose(back);
    }
    if (ok == 0)
    {
        krep_forms_release(table);
    }
    return ok;
}

extern "C" void krep_forms_release(KrepFormTable *table)
{
    free(table->words);
    table->words = NULL;
}
