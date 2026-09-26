// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "schedule.h"

#include "engine.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *g_schedule_path = NULL;

int schedule_program(const char *set, char *const *names, unsigned int count)
{
    size_t free_bytes = 0u;
    size_t total_bytes = 0u;
    if (cudaMemGetInfo(&free_bytes, &total_bytes) != cudaSuccess)
    {
        fprintf(stderr, "  the tower did not answer how much it holds\n");
        return 0;
    }
    const unsigned long long cap = (unsigned long long)free_bytes / 3ull * 2ull;
    FILE *const out = fopen(g_schedule_path, "w");
    if (out == NULL)
    {
        fprintf(stderr, "  could not open %s\n", g_schedule_path);
        return 0;
    }
    printf("  tower: %llu MiB free of %llu, scheduling against %llu MiB\n",
           (unsigned long long)free_bytes >> 20u, (unsigned long long)total_bytes >> 20u, cap >> 20u);
    fprintf(out, "{\n  \"scheme\": \"cell_tracking.program\",\n  \"version\": 1,\n");
    fprintf(out, "  \"tower\": {\"free\": %llu, \"total\": %llu, \"cap\": %llu},\n",
            (unsigned long long)free_bytes, (unsigned long long)total_bytes, cap);
    fprintf(out, "  \"stages\": [\n");
    unsigned int written = 0u;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        unsigned long long head[4] = {0ull, 0ull, 0ull, 0ull};
        EngineError error;
        memset(&error, 0, sizeof(error));
        if (engine_iapx_head(set, names[at], head, &error) != 0L)
        {
            fprintf(stderr, "  %s: no .iapx in %s; not scheduled\n", names[at], set);
            continue;
        }
        const unsigned long long frames = head[0];
        const unsigned long long voxels = head[1] * head[2] * head[3];
        const unsigned long long each = (voxels * 2ull)
                                      + (voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int))
                                      + (voxels * sizeof(unsigned int))
                                      + ((voxels + 63ull) / 64ull * sizeof(unsigned long long));
        unsigned long long hold = (each != 0ull) ? (cap / each) : 0ull;
        hold = (hold < 2ull) ? 2ull : hold;
        hold = (hold > frames) ? frames : hold;
        const unsigned long long steps = (hold > 1ull) ? (hold - 1ull) : 1ull;
        const unsigned long long chunks = ((frames > 1ull) ? (frames - 2ull + steps) : 0ull) / steps;
        printf("    %-24s %llu frames of %llu voxels, %llu MiB each, %llu per chunk, %llu chunks\n",
               names[at], frames, voxels, each >> 20u, hold, chunks);
        for (unsigned long long chunk = 0u; chunk < chunks; chunk += 1u)
        {
            const unsigned long long first = chunk * steps;
            unsigned long long past = first + hold;
            past = (past > frames) ? frames : past;
            fprintf(out, "%s    {\"sample\": \"%s\", \"first\": %llu, \"past\": %llu, \"bytes\": %llu}",
                    (written != 0u) ? ",\n" : "", names[at], first, past, (past - first) * each);
            written += 1u;
        }
    }
    fprintf(out, "\n  ]\n}\n");
    fclose(out);
    printf("  %u stages written to %s\n", written, g_schedule_path);
    return 1;
}
