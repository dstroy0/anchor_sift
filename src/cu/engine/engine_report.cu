// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_report.cu: the run's report
#include "engine_internal.h"

static int entry_report_write(ScripturaLine *line, FILE *file)
{
    const int written = scriptura_write(line, file);
    free(line->out);
    return written;
}

extern "C" int engine_ingest_print(const EngineIngestRequest *request, FILE *file)
{
    const EngineSetReport *const report = request->report;
    if ((report == NULL) || (report->samples == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.capacity = entry_report_capacity(request->samples, report->reached, request->source, request->set);
    line.out = (char *)malloc((size_t)line.capacity);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    for (unsigned long long sample = 0ull; sample < report->reached; sample += 1ull)
    {
        const EngineSampleRecord *const record = &report->samples[sample];
        scriptura_text(&line, "  ");
        if (record->sealed != 0ull)
        {
            scriptura_text_columns(&line, request->samples[sample], 24u);
            scriptura_character(&line, ' ');
            scriptura_decimal(&line, record->floors, 1u);
            scriptura_text(&line, " floors, rebuilt from the file, voxel for voxel and pixel for pixel: ");
            scriptura_decimal_columns(&line, record->crystal_bytes, 11u);
            scriptura_text(&line, " bytes of ");
            scriptura_decimal_columns(&line, record->raw_bytes, 11u);
            scriptura_text(&line, ", ");
            entry_percent(&line, record->crystal_bytes, record->raw_bytes);
            scriptura_text(&line, ", sealed ");
            entry_signum_text(&line, &record->root);
        }
        else if (record->placed == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": no source for it under ");
            scriptura_text(&line, request->source);
            scriptura_text(&line, ", or its place in ");
            scriptura_text(&line, request->set);
            scriptura_text(&line, " could not be made");
        }
        else if (record->source_read == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": its source under ");
            scriptura_text(&line, request->source);
            scriptura_text(&line, " could not be read; nothing kept");
        }
        else if (record->crystal_written == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": its " ENTRY_CRYSTAL_SUFFIX " could not be written; nothing kept");
        }
        else
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not rebuild its source: ");
            scriptura_decimal(&line, record->voxels_differ, 1u);
            scriptura_text(&line, " voxels differ on the device, ");
            scriptura_decimal(&line, record->pixels_differ, 1u);
            scriptura_text(&line, " pixels off it, ");
            entry_seal_failure(&line, record);
            scriptura_text(&line, "; nothing kept");
        }
        scriptura_character(&line, '\n');
    }
    entry_report_total(&line, report, request->count);
    return entry_report_write(&line, file);
}

extern "C" int engine_prove_print(const EngineSetRequest *request, FILE *file)
{
    const EngineSetReport *const report = request->report;
    if ((report == NULL) || (report->samples == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.capacity = entry_report_capacity(request->samples, report->reached, "", request->set);
    line.out = (char *)malloc((size_t)line.capacity);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    for (unsigned long long sample = 0ull; sample < report->reached; sample += 1ull)
    {
        const EngineSampleRecord *const record = &report->samples[sample];
        scriptura_text(&line, "  ");
        if (record->sealed != 0ull)
        {
            scriptura_text_columns(&line, request->samples[sample], 24u);
            scriptura_text(&line, " decoded from the file alone, every node of its seal holds, root ");
            entry_signum_text(&line, &record->root);
            scriptura_text(&line, ": ");
            scriptura_decimal_columns(&line, record->crystal_bytes, 11u);
            scriptura_text(&line, " bytes of ");
            scriptura_decimal_columns(&line, record->raw_bytes, 11u);
            scriptura_text(&line, ", ");
            entry_percent(&line, record->crystal_bytes, record->raw_bytes);
        }
        else
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not hold: ");
            entry_seal_failure(&line, record);
        }
        scriptura_character(&line, '\n');
    }
    entry_report_total(&line, report, request->count);
    return entry_report_write(&line, file);
}

extern "C" long engine_ingest_set(const EngineIngestRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    if (ENGINE_CHECK((request->source != NULL) && (request->set != NULL) &&
                         ((request->samples != NULL) || (request->count == 0u)),
                     request, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    EngineSetReport silent;
    memset(&silent, 0, sizeof(silent));
    EngineSetReport *const report = (request->report != NULL) ? request->report : &silent;
    EngineSampleRecord *const records = report->samples;
    memset(report, 0, sizeof(*report));
    report->samples = records;
    const unsigned long long began = engine_clock_microseconds();
    EngineSignum *const sample_roots = (EngineSignum *)calloc((size_t)request->count + 1u, sizeof(EngineSignum));
    int ok = ENGINE_CHECK(sample_roots != NULL, &sample_roots, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        EngineSampleRecord unkept;
        EngineSampleRecord *const record = (records != NULL) ? &records[sample] : &unkept;
        memset(record, 0, sizeof(*record));
        report->reached = sample + 1ull;
        char source_path[ENTRY_PATH_CAPACITY];
        char iapx_path[ENTRY_PATH_CAPACITY];
        const int archived = entry_is_file(request->source);
        const int placed =
            archived ? (snprintf(source_path, sizeof(source_path), "%s", request->source) > 0)
                     : engine_source_find(request->source, request->samples[sample], source_path, sizeof(source_path));
        unsigned int made = 0u;
        ok = ENGINE_CHECK(placed != 0, request->samples[sample], error, ENGINE_ERROR_REQUEST) &&
             ENGINE_CHECK(engine_sample_path(iapx_path, sizeof(iapx_path), request->set, request->samples[sample],
                                             ENTRY_CRYSTAL_SUFFIX) != 0,
                          request->samples[sample], error, ENGINE_ERROR_REQUEST) &&
             ENGINE_IO(entry_directories_make(iapx_path, 0, &made) != 0, iapx_path, error);
        if (ok == 0)
        {
            entry_directories_remove(iapx_path, 0, made);
            break;
        }
        record->placed = 1ull;
        EngineSideSection section;
        memset(&section, 0, sizeof(section));
        unsigned long long lane_offset = 0ull;
        EngineSourceRequest source;
        source.path = source_path;
        source.member = archived ? request->samples[sample] : NULL;
        source.axes = request->axes;
        source.channel = request->channel;
        source.side = &section.side;
        source.lane_offset = &lane_offset;
        source.error = error;
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *host_lanes = NULL;
        ok = ENGINE_CHECK(engine_source_read(&source, extent, &host_lanes) == 0L, source_path, error,
                          ENGINE_ERROR_REQUEST) &&
             entry_side_pack(&section, error);
        section.side.lane_offset = lane_offset;
        source.side = NULL;
        record->source_read = ok ? 1ull : 0ull;
        const unsigned long long lanes = ok ? entry_lanes(extent) : 0ull;
        unsigned short *device_lanes = NULL;
        ok = ok && ENGINE_CHECK(lanes != 0ull, extent, error, ENGINE_ERROR_REQUEST) &&
             ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_lanes, (size_t)lanes * sizeof(unsigned short)),
                                 &device_lanes, error) &&
             ENGINE_STATUS_CHECK(
                 cudaMemcpy(device_lanes, host_lanes, (size_t)lanes * sizeof(unsigned short), cudaMemcpyHostToDevice),
                 device_lanes, error);
        free(host_lanes);

        EngineStream written;
        unsigned int floors = 0u;
        memset(&written, 0, sizeof(written));
        EngineSeal seal;
        memset(&seal, 0, sizeof(seal));
        ok = ok && (entry_iapx_encode(device_lanes, extent, &written, &floors, error) != 0);
        written.lane_offset = lane_offset;
        ok = ok && entry_seal_make(device_lanes, &written, &section, &seal, error);
        const ApxrepInputRequest write = {iapx_path, &written, &section, &seal, error};
        ok = ok && (apxrep_input_write(&write) != 0);
        record->crystal_written = ok ? 1ull : 0ull;

        EngineStream file;
        memset(&file, 0, sizeof(file));
        EngineSideSection back;
        memset(&back, 0, sizeof(back));
        EngineSeal back_seal;
        memset(&back_seal, 0, sizeof(back_seal));
        unsigned long long pixels_differ = 0ull;
        std::vector<unsigned short> rebuilt(ok ? (size_t)lanes : 0u);
        const ApxrepInputRequest read = {iapx_path, &file, &back, &back_seal, error};
        ok = ok && apxrep_input_read(&read) &&
             ENGINE_CHECK((memcmp(file.extent, extent, sizeof(extent)) == 0) && (file.chunks == written.chunks) &&
                              (file.bits == written.bits) && (file.lane_offset == written.lane_offset) &&
                              entry_signum_same(&back_seal.roots[ENGINE_SEAL_SAMPLE], &seal.roots[ENGINE_SEAL_SAMPLE]),
                          &file, error, ENGINE_ERROR_LOGIC) &&
             entry_crystal_verify(&file, &back, &back_seal, device_lanes, rebuilt.data(), record, error) &&
             ENGINE_CHECK(entry_side_same(&back.side, &section.side), &back, error, ENGINE_ERROR_LOGIC);
        apxrep_input_release(&file);
        apxrep_side_release(&back);
        apxrep_seal_release(&back_seal);
        cudaFree(device_lanes);
        unsigned long long again[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *disk = NULL;
        ok = ok &&
             ENGINE_CHECK(engine_source_read(&source, again, &disk) == 0L, source_path, error, ENGINE_ERROR_REQUEST) &&
             ENGINE_CHECK(memcmp(again, extent, sizeof(again)) == 0, again, error, ENGINE_ERROR_LOGIC);
        if (ok)
        {
            for (size_t pixel = 0u; pixel < (size_t)lanes; pixel += 1u)
            {
                pixels_differ += (disk[pixel] != rebuilt[pixel]) ? 1ull : 0ull;
            }
            ok = ENGINE_CHECK(pixels_differ == 0ull, &pixels_differ, error, ENGINE_ERROR_LOGIC);
        }
        free(disk);
        record->floors = floors;
        record->crystal_bytes = apxrep_input_bytes(&written, &section, &seal);
        record->raw_bytes = lanes * 2ull;
        record->root = seal.roots[ENGINE_SEAL_SAMPLE];
        record->pixels_differ = pixels_differ;
        apxrep_side_release(&section);
        apxrep_seal_release(&seal);
        if (ok == 0)
        {
            remove(iapx_path);
            entry_directories_remove(iapx_path, 0, made);
            break;
        }
        record->sealed = 1ull;
        sample_roots[report->sealed] = record->root;
        report->sealed += 1ull;
        report->raw_bytes += record->raw_bytes;
        report->crystal_bytes += record->crystal_bytes;
        report->voxels += lanes;
    }
    zip_resident_release();
    ok = ok && entry_set_root(sample_roots, report->sealed, &report->set_root, error);
    free(sample_roots);
    report->microseconds = engine_clock_microseconds() - began;
    if ((ok == 0) || (report->sealed != request->count))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" long engine_iapx_prove_set(const EngineSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    if (ENGINE_CHECK((request->set != NULL) && ((request->samples != NULL) || (request->count == 0u)), request, error,
                     ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    EngineSetReport silent;
    memset(&silent, 0, sizeof(silent));
    EngineSetReport *const report = (request->report != NULL) ? request->report : &silent;
    EngineSampleRecord *const records = report->samples;
    memset(report, 0, sizeof(*report));
    report->samples = records;
    const unsigned long long began = engine_clock_microseconds();
    EngineSignum *const sample_roots = (EngineSignum *)calloc((size_t)request->count + 1u, sizeof(EngineSignum));
    const int rooted = ENGINE_CHECK(sample_roots != NULL, &sample_roots, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; rooted && (sample < request->count); sample += 1u)
    {
        EngineSampleRecord unkept;
        EngineSampleRecord *const record = (records != NULL) ? &records[sample] : &unkept;
        memset(record, 0, sizeof(*record));
        report->reached = sample + 1ull;
        char iapx_path[ENTRY_PATH_CAPACITY];
        EngineStream file;
        memset(&file, 0, sizeof(file));
        EngineSideSection section;
        memset(&section, 0, sizeof(section));
        EngineSeal seal;
        memset(&seal, 0, sizeof(seal));
        const ApxrepInputRequest read = {iapx_path, &file, &section, &seal, error};
        const int ok = ENGINE_CHECK(engine_sample_path(iapx_path, sizeof(iapx_path), request->set,
                                                       request->samples[sample], ENTRY_CRYSTAL_SUFFIX) != 0,
                                    request->samples[sample], error, ENGINE_ERROR_REQUEST) &&
                       apxrep_input_read(&read) &&
                       entry_crystal_verify(&file, &section, &seal, NULL, NULL, record, error);
        const unsigned long long lanes = entry_lanes(file.extent);
        record->placed = 1ull;
        record->crystal_bytes = apxrep_input_bytes(&file, &section, &seal);
        record->raw_bytes = lanes * 2ull;
        apxrep_input_release(&file);
        apxrep_side_release(&section);
        apxrep_seal_release(&seal);
        if (ok == 0)
        {
            continue;
        }
        record->sealed = 1ull;
        sample_roots[report->sealed] = record->root;
        report->sealed += 1ull;
        report->raw_bytes += record->raw_bytes;
        report->crystal_bytes += record->crystal_bytes;
        report->voxels += lanes;
    }
    const int sealed = rooted && entry_set_root(sample_roots, report->sealed, &report->set_root, error);
    free(sample_roots);
    report->microseconds = engine_clock_microseconds() - began;
    if ((sealed == 0) || (report->sealed != request->count))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" void engine_side_release(EngineSideBytes *side)
{
    EngineSideSection section;
    memset(&section, 0, sizeof(section));
    section.side = *side;
    apxrep_side_release(&section);
    memset(side, 0, sizeof(*side));
}

extern "C" long engine_iapx_load(const char *set, const char *sample, unsigned long long extent[4],
                                 unsigned short **volume, EngineSignum *root, EngineSideBytes *side, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    if (ENGINE_CHECK((extent != NULL) && (volume != NULL) && (root != NULL), &volume, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    *volume = NULL;
    memset(root, 0, sizeof(*root));
    char iapx_path[ENTRY_PATH_CAPACITY];
    EngineStream file;
    memset(&file, 0, sizeof(file));
    EngineSideSection section;
    memset(&section, 0, sizeof(section));
    EngineSeal seal;
    memset(&seal, 0, sizeof(seal));
    EngineSampleRecord record;
    memset(&record, 0, sizeof(record));
    const ApxrepInputRequest read = {iapx_path, &file, &section, &seal, error};
    int ok = ENGINE_CHECK(engine_sample_path(iapx_path, sizeof(iapx_path), set, sample, ENTRY_CRYSTAL_SUFFIX) != 0,
                          sample, error, ENGINE_ERROR_REQUEST) &&
             apxrep_input_read(&read);
    const unsigned long long lanes = ok ? entry_lanes(file.extent) : 0ull;
    unsigned short *const rebuilt = ok ? (unsigned short *)malloc((size_t)lanes * sizeof(unsigned short)) : NULL;
    ok = ok && ENGINE_CHECK(rebuilt != NULL, &rebuilt, error, ENGINE_ERROR_RESOURCE) &&
         entry_crystal_verify(&file, &section, &seal, NULL, rebuilt, &record, error);
    apxrep_input_release(&file);
    apxrep_seal_release(&seal);
    if (ok == 0)
    {
        free(rebuilt);
        apxrep_side_release(&section);
        ScripturaLine line;
        line.capacity = ENTRY_ROW_TEXT + scriptura_length(sample, ENTRY_PATH_CAPACITY);
        line.out = (char *)malloc((size_t)line.capacity);
        line.at = 0ull;
        if (line.out != NULL)
        {
            scriptura_text(&line, "  ");
            scriptura_text(&line, sample);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not load: ");
            entry_seal_failure(&line, &record);
            scriptura_character(&line, '\n');
            entry_report_write(&line, stderr);
        }
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    memcpy(extent, file.extent, sizeof(file.extent));
    *volume = rebuilt;
    *root = record.root;
    if (side != NULL)
    {
        *side = section.side;
        side->lane_offset = file.lane_offset;
        free(section.packed);
    }
    else
    {
        apxrep_side_release(&section);
    }
    return 0L;
}
