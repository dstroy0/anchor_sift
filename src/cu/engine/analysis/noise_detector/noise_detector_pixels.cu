// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_pixels.cu: the noise table and pixel noise
#include "noise_detector_internal.h"

// opens <set>/<file> for writing and writes its header
int noise_table_open(const char *set, const char *file, const char *header, char path[ENGINE_PATH_CAPACITY],
                     FILE **table, EngineError *error)
{
    const int written = snprintf(path, ENGINE_PATH_CAPACITY, "%s/%s", set, file);
    const int named = (written > 0) && ((size_t)written < ENGINE_PATH_CAPACITY);
    *table = named ? fopen(path, "wb") : NULL;
    return NOISE_DETECTOR_CHECK(named, set, error, ENGINE_ERROR_REQUEST) &&
           NOISE_DETECTOR_IO(*table != NULL, path, error) &&
           NOISE_DETECTOR_IO(fputs(header, *table) >= 0, *table, error);
}

extern "C" long noise_clips_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    static const char *const files[NOISE_CLIPS_TABLES] = {"noise_clips.tsv", "noise_values.tsv", "noise_spikes.tsv"};
    static const char *const headers[NOISE_CLIPS_TABLES] = {
        "sample\tleast\tmost\tnever_held_between\tat_zero\tat_top\tconstant\tconstant_zero\tconstant_top\tz_least"
        "\tz_most\ty_least\ty_most\tx_least\tx_most\n",
        "sample\tvalue\tcount\tconstant_voxels\n",
        "sample\tlowest_mean\ttriples\tspikes_16\tdips_16\tspikes_32\tdips_32\tspikes_64\tdips_64\tspikes_128"
        "\tdips_128\n"};
    char paths[NOISE_CLIPS_TABLES][ENGINE_PATH_CAPACITY];
    FILE *tables[NOISE_CLIPS_TABLES] = {NULL, NULL, NULL};
    int ok = NOISE_DETECTOR_CHECK((request->set != NULL) && (request->samples != NULL) && (request->load != NULL),
                                  request, error, ENGINE_ERROR_REQUEST);
    for (unsigned int kind = 0u; ok && (kind < NOISE_CLIPS_TABLES); kind += 1u)
    {
        ok = noise_table_open(request->set, files[kind], headers[kind], paths[kind], &tables[kind], error);
    }
    printf("  clips: every value counted; the voxel-frames at 0 and at the lane's top, 65535; the voxels whose every"
           " frame holds one value, and the box they sit in\n");
    printf("  and each frame against the frames beside it: a spike clears both from above by 16, 32, 64 or 128, a dip"
           " from below (symmetric noise holds them equal)\n");
    NoiseClips *const clips = (NoiseClips *)malloc(sizeof(NoiseClips));
    ok = ok && NOISE_DETECTOR_CHECK(clips != NULL, &clips, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        ok = NOISE_DETECTOR_CHECK(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                  ENGINE_ERROR_REQUEST) &&
             (noise_clips_sample(volume, extent, clips, error) == 0L);
        free(volume);
        ok = ok && NOISE_DETECTOR_IO(noise_clips_rows(tables, name, clips) != 0, tables[NOISE_TABLE_CLIPS], error);
        if (ok != 0)
        {
            noise_clips_summary(name, clips);
        }
    }
    free(clips);
    for (unsigned int kind = 0u; kind < NOISE_CLIPS_TABLES; kind += 1u)
    {
        if (tables[kind] != NULL)
        {
            ok = NOISE_DETECTOR_IO(fclose(tables[kind]) == 0, paths[kind], error) && ok;
        }
    }
    if (ok != 0)
    {
        printf("  clips: %u samples in %llu ms; the counts are in %s, %s and %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, paths[NOISE_TABLE_CLIPS], paths[NOISE_TABLE_VALUES],
               paths[NOISE_TABLE_SPIKES]);
    }
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

// the pixel maps' halves: the z planes below the middle, then those from it up
#define NOISE_PIXEL_HALVES 2u

// each pixel and half holds its static voxels, their values summed over the frames, and their frame differences
// squared and summed
#define NOISE_PIXEL_VOXELS 0u

#define NOISE_PIXEL_VALUES 1u

#define NOISE_PIXEL_SQUARES 2u

#define NOISE_PIXEL_SUMS 3u

#define NOISE_PIXEL_CELLS(plane_voxels_) ((plane_voxels_) * NOISE_PIXEL_HALVES * NOISE_PIXEL_SUMS)

// Every camera pixel's static voxels in each half of the z planes: counted, their values summed over the frames, and
// their frame differences squared and summed. A voxel's pixel is its (y, x); every z plane of a light sheet stack is
// one exposure of the same pixels. A fixed pattern, a hot pixel or a dust shadow repeats in both halves, and the
// cells, which differ between the halves, do not.
static long noise_pixels_sample(const unsigned short *volume, const unsigned long long extent[4],
                                unsigned long long *maps, unsigned long long *ceiling, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long plane_voxels = extent[2] * extent[3];
    const unsigned long long voxels = depth * plane_voxels;
    // a pixel's squares total at most the sample's voxel-frames times 65535 squared
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    int ok = NOISE_DETECTOR_CHECK(mask != NULL, &mask, error, ENGINE_ERROR_RESOURCE) &&
             NOISE_DETECTOR_CHECK(noise_static_mask(volume, frames, voxels, 0u, mask, ceiling) != 0, mask, error,
                                  ENGINE_ERROR_RESOURCE);
    if (ok != 0)
    {
        memset(maps, 0, (size_t)NOISE_PIXEL_CELLS(plane_voxels) * sizeof(unsigned long long));
        const unsigned long long middle = depth / 2ull;
        // frame by frame and plane by plane. The volume is read in order; the first frame also counts the voxels
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            for (unsigned long long z = 0ull; z < depth; z += 1ull)
            {
                const unsigned long long half = (z < middle) ? 0ull : 1ull;
                const unsigned char *const kept = &mask[z * plane_voxels];
                const unsigned short *const lanes = &volume[(frame * voxels) + (z * plane_voxels)];
                // the same plane one frame earlier; the first frame has none and reads itself
                const unsigned short *const earlier =
                    (frame != 0ull) ? &volume[((frame - 1ull) * voxels) + (z * plane_voxels)] : lanes;
                for (unsigned long long pixel = 0ull; pixel < plane_voxels; pixel += 1ull)
                {
                    if (kept[pixel] == 0u)
                    {
                        continue;
                    }
                    unsigned long long *const cell = &maps[((pixel * NOISE_PIXEL_HALVES) + half) * NOISE_PIXEL_SUMS];
                    cell[NOISE_PIXEL_VOXELS] += (frame == 0ull) ? 1ull : 0ull;
                    cell[NOISE_PIXEL_VALUES] += lanes[pixel];
                    if (frame != 0ull)
                    {
                        const long long moved = (long long)lanes[pixel] - (long long)earlier[pixel];
                        // a square is never negative. It re-signs to unsigned long long exactly
                        cell[NOISE_PIXEL_SQUARES] += (unsigned long long)(moved * moved);
                    }
                }
            }
        }
    }
    free(mask);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

static int noise_pixels_rows(FILE *table, const char *name, const unsigned long long extent[4],
                             const unsigned long long *maps)
{
    const unsigned long long width = extent[3];
    const unsigned long long plane_voxels = extent[2] * width;
    int ok = 1;
    for (unsigned long long pixel = 0ull; ok && (pixel < plane_voxels); pixel += 1ull)
    {
        const unsigned long long *const lower = &maps[(pixel * NOISE_PIXEL_HALVES) * NOISE_PIXEL_SUMS];
        const unsigned long long *const upper = &lower[NOISE_PIXEL_SUMS];
        if ((lower[NOISE_PIXEL_VOXELS] == 0ull) && (upper[NOISE_PIXEL_VOXELS] == 0ull))
        {
            continue;
        }
        ok = fprintf(table, "%s\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, pixel / width, pixel % width,
                     lower[NOISE_PIXEL_VOXELS], lower[NOISE_PIXEL_VALUES], lower[NOISE_PIXEL_SQUARES],
                     upper[NOISE_PIXEL_VOXELS], upper[NOISE_PIXEL_VALUES], upper[NOISE_PIXEL_SQUARES]) > 0;
    }
    return ok;
}

extern "C" long noise_pixels_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_CAPACITY];
    FILE *table = NULL;
    int ok = NOISE_DETECTOR_CHECK((request->set != NULL) && (request->samples != NULL) && (request->load != NULL),
                                  request, error, ENGINE_ERROR_REQUEST) &&
             noise_table_open(request->set, "noise_pixels.tsv",
                              "sample\ty\tx\tlower_voxels\tlower_values\tlower_squares\tupper_voxels\tupper_values"
                              "\tupper_squares\n",
                              path, &table, error);
    printf("  pixels: every camera pixel's static voxels (the dimmest quarter by mean of those that change and never"
           " touch either end of the lane), counted, their values summed and their frame differences squared, in the"
           " z planes below the middle and from it up\n");
    const unsigned long long began = engine_clock_microseconds();
    unsigned long long *maps = NULL;
    unsigned long long max_cells = 0ull;
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        ok = NOISE_DETECTOR_CHECK(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                  ENGINE_ERROR_REQUEST);
        const unsigned long long cells = NOISE_PIXEL_CELLS(extent[2] * extent[3]);
        // the maps grow to the widest plane the set holds
        if (ok && (cells > max_cells))
        {
            free(maps);
            maps = (unsigned long long *)malloc((size_t)cells * sizeof(unsigned long long));
            max_cells = (maps != NULL) ? cells : 0ull;
            ok = NOISE_DETECTOR_CHECK(maps != NULL, &maps, error, ENGINE_ERROR_RESOURCE);
        }
        unsigned long long ceiling = 0ull;
        ok = ok && (noise_pixels_sample(volume, extent, maps, &ceiling, error) == 0L);
        free(volume);
        ok = ok && NOISE_DETECTOR_IO(noise_pixels_rows(table, name, extent, maps) != 0, table, error);
        if (ok != 0)
        {
            printf("  %-24s static means up to %llu\n", name, ceiling);
            fflush(stdout);
        }
    }
    free(maps);
    if (table != NULL)
    {
        ok = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && ok;
    }
    if (ok != 0)
    {
        printf("  pixels: %u samples in %llu ms; every pixel's sums are in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}
