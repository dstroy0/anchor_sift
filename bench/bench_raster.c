// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "anchor_raster.h"
#include "anchor_sift.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define RASTER_CORPUS 65536u

#define RASTER_EDGE 256u

#define RASTER_NEEDLE 24u

static void build_field(uint8_t *corpus, size_t length)
{
    uint32_t state = 2463534242u;

    for (size_t at = 0u; at < length; at += 1u)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        const uint32_t roll = state % 1000u;
        if (roll < 400u)
        {
            corpus[at] = 0x41u;
        }
        else if (roll < 700u)
        {
            corpus[at] = 0x42u;
        }
        else if (roll < 900u)
        {
            corpus[at] = 0x43u;
        }
        else
        {
            corpus[at] = (uint8_t)(0x50u + (state % 40u));
        }
    }
}

static size_t filled_cells(const uint8_t *pixels, size_t cells)
{
    size_t filled = 0u;

    for (size_t cell = 0u; cell < cells; cell += 1u)
    {
        if (pixels[cell] != (uint8_t)ANCHOR_RASTER_EMPTY)
        {
            filled += 1u;
        }
    }
    return filled;
}

static size_t first_difference(const uint8_t *left, const uint8_t *right, size_t cells)
{
    for (size_t cell = 0u; cell < cells; cell += 1u)
    {
        if (left[cell] != right[cell])
        {
            return cell;
        }
    }
    return cells;
}

int main(void)
{
    int failed = 0;

    uint8_t *corpus = (uint8_t *)malloc(RASTER_CORPUS);
    const size_t cells = (size_t)RASTER_EDGE * RASTER_EDGE;
    uint8_t *host_pixels = (uint8_t *)malloc(cells);
    uint8_t *device_pixels = (uint8_t *)malloc(cells);
    uint8_t *survivors = NULL;
    if ((corpus == NULL) || (host_pixels == NULL) || (device_pixels == NULL))
    {
        printf("  allocation failed\n");
        free(corpus);
        free(host_pixels);
        free(device_pixels);
        return 1;
    }
    build_field(corpus, RASTER_CORPUS);

    uint8_t needle[RASTER_NEEDLE];
    memcpy(needle, corpus + (RASTER_CORPUS / 3u), sizeof(needle));

    const size_t alignments = (RASTER_CORPUS - RASTER_NEEDLE) + 1u;
    survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  allocation failed\n");
        free(corpus);
        free(host_pixels);
        free(device_pixels);
        return 1;
    }

    size_t spawned[ANCHOR_STEER_ANCHORS];
    const size_t coarms = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent,
                                            .offsets = spawned,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = RASTER_CORPUS,
                                            .needle = needle,
                                            .needle_len = RASTER_NEEDLE,
                                            .survivors = survivors,
                                            .survivors_length = alignments,
                                            .sample_stride = 1u);
    AnchorRasterProbe steered[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < coarms; slot += 1u)
    {
        steered[slot].origin = spawned[slot];
        steered[slot].step = 1u;
        steered[slot].length = 1u;
    }

    AnchorRasterProbe plain[ANCHOR_STEER_ANCHORS];
    const size_t cell_span = RASTER_NEEDLE / ANCHOR_STEER_ANCHORS;
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        plain[slot].origin = (slot * cell_span) + ((cell_span > 1u) ? ((slot * 7u) % cell_span) : 0u);
        plain[slot].step = 1u;
        plain[slot].length = 1u;
    }

    const int have_device = anchor_raster_device_available();
    printf("\n  OBJECT UNDER EXAMINATION: %u bytes, %zu alignments, raster %ux%u\n", RASTER_CORPUS,
           alignments, RASTER_EDGE, RASTER_EDGE);
    printf("  steered probe set: %zu probes. device rasterizer: %s\n\n", coarms,
           have_device ? "present" : "absent, host graded alone");

    printf("  %12s %14s %10s %12s %14s\n", "layout", "channel", "filled", "host/device", "verdict");

    size_t reference_filled = 0u;
    int reference_taken = 0;

    for (unsigned int which_layout = 0u; which_layout < ANCHOR_RASTER_LAYOUTS; which_layout += 1u)
    {
        for (unsigned int which_channel = 0u; which_channel < ANCHOR_RASTER_CHANNELS;
             which_channel += 1u)
        {
            AnchorRasterConfig config;
            config.width = RASTER_EDGE;
            config.height = RASTER_EDGE;
            config.layout = (AnchorRasterLayout)which_layout;
            config.channel = (AnchorRasterChannel)which_channel;
            config.reduce = ANCHOR_REDUCE_MIN;
            config.gain = 1u;

            if (anchor_raster_host(host_pixels, &config, corpus, RASTER_CORPUS, needle,
                                   RASTER_NEEDLE, steered, coarms) == 0)
            {
                printf("  %12s %14s   host render refused\n",
                       anchor_raster_layout_name(config.layout),
                       anchor_raster_channel_name(config.channel));
                failed += 1;
                continue;
            }

            const size_t filled = filled_cells(host_pixels, cells);

            if (reference_taken == 0)
            {
                reference_filled = filled;
                reference_taken = 1;
            }

            const char *verdict = "ok";
            if (filled != reference_filled)
            {
                verdict = "FAILS";
                failed += 1;
            }

            const char *agreement = "host only";
            if (have_device != 0)
            {
                if (anchor_raster_device(device_pixels, &config, corpus, RASTER_CORPUS, needle,
                                         RASTER_NEEDLE, steered, coarms) == 0)
                {
                    agreement = "device refused";
                    verdict = "FAILS";
                    failed += 1;
                }
                else
                {
                    const size_t differ = first_difference(host_pixels, device_pixels, cells);
                    if (differ == cells)
                    {
                        agreement = "identical";
                    }
                    else
                    {
                        agreement = "DIFFER";
                        verdict = "FAILS";
                        failed += 1;
                    }
                }
            }

            printf("  %12s %14s %10zu %12s %14s\n", anchor_raster_layout_name(config.layout),
                   anchor_raster_channel_name(config.channel), filled, agreement, verdict);

            char path[128];
            snprintf(path, sizeof(path), "raster_%s_%s.pgm",
                     anchor_raster_layout_name(config.layout),
                     anchor_raster_channel_name(config.channel));
            if (anchor_raster_write_pgm(path, host_pixels, config.width, config.height) == 0)
            {
                printf("    could not write %s\n", path);
                failed += 1;
            }
        }
    }

    printf("\n  FRAME RATE, death-level channel, rows layout, %zu frames each\n\n", (size_t)200u);
    printf("  %22s %12s %12s %14s\n", "probe set", "frames", "seconds", "frames/second");

    AnchorRasterConfig timing;
    timing.width = RASTER_EDGE;
    timing.height = RASTER_EDGE;
    timing.layout = ANCHOR_LAYOUT_ROWS;
    timing.channel = ANCHOR_CHANNEL_DEATH_LEVEL;
    timing.reduce = ANCHOR_REDUCE_MIN;
    timing.gain = 1u;

    const size_t frames = 200u;
    for (unsigned int which = 0u; which < 2u; which += 1u)
    {
        const AnchorRasterProbe *set = (which == 0u) ? plain : steered;
        const size_t count = (which == 0u) ? (size_t)ANCHOR_STEER_ANCHORS : coarms;

        const clock_t opened = clock();
        for (size_t frame = 0u; frame < frames; frame += 1u)
        {
            (void)anchor_raster_host(host_pixels, &timing, corpus, RASTER_CORPUS, needle,
                                     RASTER_NEEDLE, set, count);
        }
        const clock_t closed = clock();

        const double seconds = (double)(closed - opened) / (double)CLOCKS_PER_SEC;
        const double rate = (seconds > 0.0) ? ((double)frames / seconds) : 0.0;
        printf("  %22s %12zu %12.3f %14.1f\n",
               (which == 0u) ? "spatial, unsteered" : "steered coarms", frames, seconds, rate);
    }

    printf("\n  VOLUME SWEEP, %u layouts by %u channels into 32 by 32 by 32\n\n",
           (unsigned)ANCHOR_VOLUME_LAYOUTS, (unsigned)ANCHOR_RASTER_CHANNELS);
    const int have_device_volume = anchor_volume_device_available();
    printf("  %16s %14s %10s %12s %14s %10s\n", "layout", "channel", "filled", "collisions",
           "host/device", "verdict");

    const size_t volume_edge = 32u;
    const size_t volume_cells = volume_edge * volume_edge * volume_edge;
    uint8_t *const voxels = (uint8_t *)malloc(volume_cells);
    uint8_t *const device_voxels = (uint8_t *)malloc(volume_cells);
    size_t *const seen = (size_t *)malloc(volume_cells * sizeof(size_t));

    if ((voxels == NULL) || (device_voxels == NULL) || (seen == NULL))
    {
        printf("  volume allocation failed\n");
        failed += 1;
    }
    else
    {
        for (unsigned layout = 0u; layout < ANCHOR_VOLUME_LAYOUTS; layout += 1u)
        {
            for (unsigned channel = 0u; channel < ANCHOR_RASTER_CHANNELS; channel += 1u)
            {
                const AnchorVolumeConfig config = {
                    volume_edge, volume_edge, volume_edge, (AnchorVolumeLayout)layout,
                    (AnchorRasterChannel)channel, ANCHOR_REDUCE_MAX, 1u};

                const int rendered = anchor_volume_render_host(voxels, &config, corpus,
                                                               RASTER_CORPUS, needle, RASTER_NEEDLE,
                                                               steered, coarms, NULL);
                if (rendered == 0)
                {
                    printf("  %16s %14s %10s %12s %14s %10s\n",
                           anchor_volume_layout_name((AnchorVolumeLayout)layout),
                           anchor_raster_channel_name((AnchorRasterChannel)channel),
                           "-", "-", "-", "REFUSED");
                    failed += 1;
                    continue;
                }

                for (size_t cell = 0u; cell < volume_cells; cell += 1u)
                {
                    seen[cell] = 0u;
                }

                size_t collisions = 0u;
                const size_t checked = (alignments < volume_cells) ? alignments : volume_cells;
                for (size_t at = 0u; at < checked; at += 1u)
                {
                    const size_t cell = anchor_volume_cell_for(&config, at);
                    if (cell >= volume_cells)
                    {
                        collisions += 1u;
                        continue;
                    }
                    seen[cell] += 1u;
                    if (seen[cell] > 1u)
                    {
                        collisions += 1u;
                    }
                }

                size_t filled = 0u;
                for (size_t cell = 0u; cell < volume_cells; cell += 1u)
                {
                    if (voxels[cell] != (uint8_t)ANCHOR_RASTER_EMPTY)
                    {
                        filled += 1u;
                    }
                }

                const char *agreement = "host only";
                int device_failed = 0;
                if (have_device_volume != 0)
                {
                    if (anchor_volume_device(device_voxels, &config, corpus, RASTER_CORPUS, needle,
                                             RASTER_NEEDLE, steered, coarms, NULL) == 0)
                    {
                        agreement = "device refused";
                        device_failed = 1;
                    }
                    else if (first_difference(voxels, device_voxels, volume_cells) != volume_cells)
                    {
                        agreement = "DIFFERS";
                        device_failed = 1;
                    }
                    else
                    {
                        agreement = "ok";
                    }
                }

                const int row_ok = (collisions == 0u) && (device_failed == 0);
                printf("  %16s %14s %10zu %12zu %14s %10s\n",
                       anchor_volume_layout_name((AnchorVolumeLayout)layout),
                       anchor_raster_channel_name((AnchorRasterChannel)channel),
                       filled, collisions, agreement, row_ok ? "ok" : "FAILS");
                failed += (row_ok == 0) ? 1 : 0;
            }
        }

        const AnchorVolumeConfig sample = {
            volume_edge, volume_edge, volume_edge, ANCHOR_VOLUME_MORTON,
            ANCHOR_CHANNEL_DEATH_LEVEL, ANCHOR_REDUCE_MAX, 1u};
        if (anchor_volume_render_host(voxels, &sample, corpus, RASTER_CORPUS, needle, RASTER_NEEDLE,
                                      steered, coarms, NULL) != 0)
        {
            if (anchor_volume_write_raw("anchor_volume_morton_death.raw", voxels, &sample) == 0)
            {
                printf("  the volume could not be written\n");
                failed += 1;
            }
            else
            {
                printf("\n  wrote anchor_volume_morton_death.raw with its sidecar, %zu bytes\n",
                       volume_cells);
            }
        }

        printf("  device volume renderer: %s\n",
               (anchor_volume_device_available() != 0) ? "present" : "absent, host only");
    }

    free(voxels);
    free(device_voxels);
    free(seen);

    printf("\n  %d check(s) failed\n", failed);
    free(corpus);
    free(host_pixels);
    free(device_pixels);
    free(survivors);
    return (failed == 0) ? 0 : 1;
}
