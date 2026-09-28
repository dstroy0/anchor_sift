// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_history.cu: the history and the public entry points
#include "engine_internal.h"

static int entry_history_same(const EngineHistory *one, const EngineHistory *other)
{
    const size_t entries = (size_t)(one->windows * one->windows);
    const size_t words = (size_t)(one->windows * one->extent[1] * one->extent[2] * one->extent[3]);
    return (memcmp(one->extent, other->extent, sizeof(one->extent)) == 0) && (one->windows == other->windows) &&
           entry_signum_same(&one->sample, &other->sample) && (one->payload_crc == other->payload_crc) &&
           (one->cloud_crc == other->cloud_crc) &&
           (memcmp(one->cloud, other->cloud, entries * sizeof(unsigned long long)) == 0) &&
           (memcmp(one->history, other->history, words * sizeof(unsigned long long)) == 0);
}

extern "C" long engine_entropy_set(const EngineEntropySetRequest *request)
{
    if ((request == NULL) || (request->set.error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->set.error;
    if (ENGINE_CHECK((request->set.set != NULL) && (request->set.samples != NULL), request, error,
                     ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    int ok = 1;
    for (unsigned int sample = 0u; ok && (sample < request->set.count); sample += 1u)
    {
        const char *const name = request->set.samples[sample];
        char path[ENTRY_PATH_CAPACITY];
        char iapx_path[ENTRY_PATH_CAPACITY];
        ok = ENGINE_CHECK(engine_sample_path(path, sizeof(path), request->set.set, name, ".oapx") != 0, name, error,
                          ENGINE_ERROR_REQUEST) &&
             ENGINE_CHECK(
                 engine_sample_path(iapx_path, sizeof(iapx_path), request->set.set, name, ENTRY_CRYSTAL_SUFFIX) != 0,
                 name, error, ENGINE_ERROR_REQUEST);
        if (ok == 0)
        {
            break;
        }
        const unsigned long long began = engine_clock_microseconds();
        EngineStream standing;
        EngineSignum standing_root;
        EngineError probe;
        memset(&probe, 0, sizeof(probe));
        if ((request->keep != 0u) && apxrep_input_head(iapx_path, &standing, &standing_root, &probe))
        {
            EngineHistory kept;
            const int read_back = apxrep_history_read(path, &kept, 1u, &probe);
            const int same = read_back && entry_signum_same(&kept.sample, &standing_root);
            apxrep_history_release(&kept);
            if (same)
            {
                printf("  %-24s laid down already: read back whole, projected from the " ENTRY_CRYSTAL_SUFFIX
                       " as it stands, in %llu ms\n",
                       name, (engine_clock_microseconds() - began) / 1000ull);
                fflush(stdout);
                continue;
            }
        }

        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        EngineSignum sample_root;
        memset(&sample_root, 0, sizeof(sample_root));
        ok = (engine_iapx_load(request->set.set, name, extent, &volume, &sample_root, NULL, error) == 0L);
        const long windows = ok ? entropy_history_windows(extent, error) : ENTROPY_HISTORY_ERROR;
        ok = ok && (windows != ENTROPY_HISTORY_ERROR);
        const unsigned long long window_count = ok ? (unsigned long long)windows : 0ull;
        std::vector<unsigned long long> cloud((size_t)(window_count * window_count));
        std::vector<unsigned long long> payload((size_t)(window_count * extent[1] * extent[2] * extent[3]));
        EngineHistory history;
        memset(&history, 0, sizeof(history));
        history.cloud = cloud.data();
        history.history = payload.data();
        EntropyHistoryProjectRequest project;
        memset(&project, 0, sizeof(project));
        project.volume = volume;
        memcpy(project.extent, extent, sizeof(project.extent));
        project.sample = sample_root;
        project.history = &history;
        project.error = error;
        unsigned long long broken = 0ull;
        ok = ok && (entropy_history_project(&project, &broken) == 0L);
        free(volume);
        if (ENGINE_CHECK(broken == 0ull, &broken, error, ENGINE_ERROR_LOGIC) == 0)
        {
            fprintf(stderr, "  %s: entropy not conserved: %llu voxels' flips break parity with their net change\n",
                    name, broken);
            ok = 0;
            break;
        }

        EngineHistory read;
        memset(&read, 0, sizeof(read));
        ok = ok && ENGINE_IO(engine_directories_make(path, 0) != 0, path, error) &&
             apxrep_history_write(path, &history, error) && apxrep_history_read(path, &read, 1u, error) &&
             ENGINE_CHECK(entry_history_same(&history, &read) != 0, &read, error, ENGINE_ERROR_LOGIC);
        apxrep_history_release(&read);
        if (ok == 0)
        {
            fprintf(stderr, "  %s: the entropy history was not written and read back whole\n", name);
            break;
        }
        printf("  %-24s %llu frames, %llu windows of %u transitions, entropy conserved at every voxel, %llu MiB, read "
               "back whole, CRC-64 %016llx, in %llu ms\n",
               name, extent[0], window_count, ENGINE_HISTORY_WINDOW,
               (unsigned long long)(payload.size() * sizeof(unsigned long long)) >> 20u, history.payload_crc,
               (engine_clock_microseconds() - began) / 1000ull);
        entropy_history_report(&history);
        fflush(stdout);
    }
    if (ok == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" long engine_entropy_cloud(const char *path, unsigned int *windows, unsigned long long *cloud,
                                     EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    EngineHistory history;
    if ((ENGINE_CHECK((windows != NULL) && (cloud != NULL), &cloud, error, ENGINE_ERROR_REQUEST) == 0) ||
        (apxrep_history_read(path, &history, 0u, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    *windows = (unsigned int)history.windows;
    memcpy(cloud, history.cloud, (size_t)(history.windows * history.windows) * sizeof(unsigned long long));
    apxrep_history_release(&history);
    return 0L;
}

extern "C" long engine_entropy_history_read(const char *path, EngineHistory *history, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    if (apxrep_history_read(path, history, 1u, error) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" void engine_entropy_history_release(EngineHistory *history)
{
    apxrep_history_release(history);
}

extern "C" long engine_bodies_write(const char *set, const char *sample, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    if (ENGINE_CHECK(table != NULL, &table, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    char path[ENTRY_PATH_CAPACITY];
    table->crc = crc_words(CRC_TABLE, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS));
    if ((ENGINE_CHECK(engine_sample_path(path, sizeof(path), set, sample, ".bapx") != 0, sample, error,
                      ENGINE_ERROR_REQUEST) == 0) ||
        (apxrep_bodies_write(path, table, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    EngineBodyTable back;
    const int ok = apxrep_bodies_read(path, &back, error);
    const int same =
        (ok != 0) &&
        ENGINE_CHECK((back.bodies == table->bodies) && (back.crc == table->crc) &&
                         (memcmp(back.frame_start, table->frame_start,
                                 (size_t)(table->frames + 1ull) * sizeof(unsigned long long)) == 0) &&
                         (memcmp(back.words, table->words,
                                 (size_t)(table->bodies * ENGINE_BODY_WORDS) * sizeof(unsigned long long)) == 0),
                     &back, error, ENGINE_ERROR_LOGIC);
    apxrep_bodies_release(&back);
    if (same == 0)
    {
        remove(path);
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" long engine_bodies_read(const char *set, const char *sample, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    char path[ENTRY_PATH_CAPACITY];
    if ((ENGINE_CHECK(engine_sample_path(path, sizeof(path), set, sample, ".bapx") != 0, sample, error,
                      ENGINE_ERROR_REQUEST) == 0) ||
        (apxrep_bodies_read(path, table, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    return 0L;
}

extern "C" void engine_bodies_release(EngineBodyTable *table)
{
    apxrep_bodies_release(table);
}
