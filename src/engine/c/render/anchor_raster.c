/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_raster.c
 * @brief The host rasterizer and the P5 writer. Integer arithmetic throughout.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHY THIS IS FAST, AND IT IS THE SAME REASON THE SEARCH IS. A pixel costs what the alignment under
 * it costs, and a steered probe set rejects most alignments on the first read. The renderer inherits
 * that directly: driving reads per alignment toward one drives the cost of a frame toward one read
 * per alignment. Nothing here is optimized separately from the search, and there is no second code
 * path to keep in agreement with it.
 */

#include "anchor_raster.h"

#include <stdio.h>

/** @brief Death level step in the gray ramp, chosen so four probes stay far apart in 8 bits. */
#define ANCHOR_RASTER_STEP 40u

/** @brief Brightest value a death level may reach, leaving ANCHOR_RASTER_MATCH above it. */
#define ANCHOR_RASTER_CEILING 250u

/**
 * @brief Gray value for an alignment that died at `level`, or passed every probe.
 *
 * @param[in] level       Probe index that rejected the alignment, or `probe_count` where none did.
 * @param[in] probe_count How many probes were evaluated.
 * @param[in] matched     Non-zero where the full compare confirmed an occurrence.
 * @return                The pixel value.
 *
 * @note Exact integer arithmetic. The host and device ramps cannot drift apart by a rounding.
 */
static uint8_t raster_value(size_t level, size_t probe_count, int matched)
{
    if (matched != 0)
    {
        return (uint8_t)ANCHOR_RASTER_MATCH;
    }
    (void)probe_count;

    const size_t scaled = 1u + (level * ANCHOR_RASTER_STEP);
    return (uint8_t)((scaled > ANCHOR_RASTER_CEILING) ? ANCHOR_RASTER_CEILING : scaled);
}

/**
 * @brief The level at which one alignment died, and whether it matched.
 *
 * @param[out] matched Set non-zero where the full compare confirmed an occurrence [BORROWS].
 * @return             Probe index that rejected it, or `probe_count` where none did.
 */
static size_t raster_death_level(const uint8_t *corpus, const uint8_t *needle, size_t needle_len,
                                 const AnchorRasterProbe *probes, size_t probe_count, size_t at,
                                 int *matched)
{
    *matched = 0;

    for (size_t slot = 0u; slot < probe_count; slot += 1u)
    {
        for (size_t step = 0u; step < probes[slot].length; step += 1u)
        {
            const size_t offset = probes[slot].origin + (step * probes[slot].step);
            if (corpus[at + offset] != needle[offset])
            {
                return slot;
            }
        }
    }

    /* Survived every probe. The full compare is what decides an occurrence, and a survivor that
     * fails it is a false positive the probe set could not refute cheaply. Both outcomes are worth
     * seeing. They take different values. */
    for (size_t step = 0u; step < needle_len; step += 1u)
    {
        if (corpus[at + step] != needle[step])
        {
            return probe_count;
        }
    }
    *matched = 1;
    return probe_count;
}

/**
 * @brief Symbol counts over the object, held apart from anchor_steer so the device links neither.
 *
 * @note The rarity channel needs the same counts anchor_steer builds, and the device rasterizer
 *       cannot link the limb library those live behind. Counting bytes is eight lines. The
 *       duplication costs less than the dependency and neither copy can drift into a different
 *       answer: both are a histogram of the same bytes.
 */
typedef struct
{
    uint64_t occurrences[256];
    uint64_t total;
} AnchorRasterCensus;

/** @brief Counts what the object under examination is made of. */
static void raster_census(AnchorRasterCensus *census, const uint8_t *corpus, size_t corpus_len)
{
    for (size_t symbol = 0u; symbol < 256u; symbol += 1u)
    {
        census->occurrences[symbol] = 0u;
    }
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        census->occurrences[corpus[at]] += 1u;
    }
    census->total = (uint64_t)corpus_len;
}

size_t anchor_raster_cell(const AnchorRasterConfig *config, size_t at, size_t alignments)
{
    const size_t cells = config->width * config->height;

    /* Corpus order maps onto a linear cell index by integer division first. Every layout below is
     * then a permutation of that index, which keeps each transform a bijection and keeps the count
     * of alignments reaching a cell independent of which layout was chosen. */
    const size_t linear = (at * cells) / alignments;
    const size_t row = linear / config->width;
    const size_t column = linear % config->width;

    switch (config->layout)
    {
    case ANCHOR_LAYOUT_SERPENTINE:
    {
        const size_t flipped = ((row % 2u) == 0u) ? column : (config->width - 1u - column);
        return (row * config->width) + flipped;
    }
    case ANCHOR_LAYOUT_COLUMNS:
    {
        /* Transposed through the shorter side so the index stays inside the raster on a
         * rectangle. Reading down a column puts corpus neighbors a row apart. */
        const size_t turned_row = linear % config->height;
        const size_t turned_column = linear / config->height;
        if (turned_column >= config->width)
        {
            return linear;
        }
        return (turned_row * config->width) + turned_column;
    }
    case ANCHOR_LAYOUT_DIAGONAL:
    {
        const size_t shifted = (column + row) % config->width;
        return (row * config->width) + shifted;
    }
    case ANCHOR_LAYOUT_ROWS:
    default:
    {
        return linear;
    }
    }
}

uint8_t anchor_raster_sample(const AnchorRasterConfig *config, const uint8_t *corpus,
                             const uint8_t *needle, size_t needle_len,
                             const AnchorRasterProbe *probes, size_t probe_count, size_t at,
                             const uint64_t *occurrences, uint64_t total)
{
    const uint8_t gain = (config->gain == 0u) ? 1u : config->gain;

    switch (config->channel)
    {
    case ANCHOR_CHANNEL_BYTE:
    {
        return corpus[at];
    }
    case ANCHOR_CHANNEL_RARITY:
    {
        /* Rarity as the steering term defines it, scaled into eight bits by exact integer
         * division. A symbol the field never produces reaches the top of the ramp. */
        if (total == 0u)
        {
            return 1u;
        }
        const uint64_t missing = total - occurrences[corpus[at]];
        const uint64_t scaled = (missing * 254u) / total;
        return (uint8_t)(1u + scaled);
    }
    case ANCHOR_CHANNEL_PROVEN:
    {
        /* A refuted alignment is proven to hold no occurrence. A survivor is undetermined: the
         * probes could not refute it and only the full compare decides. Proven takes the higher
         * value, a minimum reduction behaves as the conjunction this channel needs, a cell
         * staying proven only while every alignment under it was refuted. */
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes,
                                                probe_count, at, &matched);
        return (level < probe_count)
                   ? (uint8_t)ANCHOR_RASTER_PROVEN
                   : (uint8_t)ANCHOR_RASTER_UNDETERMINED;
    }
    case ANCHOR_CHANNEL_SURVIVED:
    {
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes,
                                                probe_count, at, &matched);
        return (level >= probe_count) ? (uint8_t)ANCHOR_RASTER_MATCH : 1u;
    }
    case ANCHOR_CHANNEL_DEATH_LEVEL:
    default:
    {
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes,
                                                probe_count, at, &matched);
        return raster_value(level * (size_t)gain, probe_count, matched);
    }
    }
}

int anchor_raster_host(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                       size_t corpus_len, const uint8_t *needle, size_t needle_len,
                       const AnchorRasterProbe *probes, size_t probe_count)
{
    if ((pixels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL) || (config->width == 0u) || (config->height == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0;
    }
    if ((probes == NULL) && (probe_count != 0u))
    {
        return 0;
    }

    const size_t cells = config->width * config->height;
    for (size_t cell = 0u; cell < cells; cell += 1u)
    {
        pixels[cell] = (uint8_t)ANCHOR_RASTER_EMPTY;
    }

    AnchorRasterCensus census;
    raster_census(&census, corpus, corpus_len);

    const size_t alignments = (corpus_len - needle_len) + 1u;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        const uint8_t value = anchor_raster_sample(config, corpus, needle, needle_len, probes,
                                                   probe_count, at, census.occurrences,
                                                   census.total);
        const size_t cell = anchor_raster_cell(config, at, alignments);

        /* An empty cell holds zero, which would win every minimum and lose every maximum. It is
         * filled on first arrival. */
        if (pixels[cell] == (uint8_t)ANCHOR_RASTER_EMPTY)
        {
            pixels[cell] = value;
            continue;
        }
        if (config->reduce == ANCHOR_REDUCE_MAX)
        {
            if (value > pixels[cell])
            {
                pixels[cell] = value;
            }
        }
        else if (value < pixels[cell])
        {
            pixels[cell] = value;
        }
    }
    return 1;
}

const char *anchor_raster_layout_name(AnchorRasterLayout layout)
{
    switch (layout)
    {
    case ANCHOR_LAYOUT_ROWS:
    {
        return "rows";
    }
    case ANCHOR_LAYOUT_SERPENTINE:
    {
        return "serpentine";
    }
    case ANCHOR_LAYOUT_COLUMNS:
    {
        return "columns";
    }
    case ANCHOR_LAYOUT_DIAGONAL:
    {
        return "diagonal";
    }
    default:
    {
        return "unknown";
    }
    }
}

const char *anchor_raster_channel_name(AnchorRasterChannel channel)
{
    switch (channel)
    {
    case ANCHOR_CHANNEL_PROVEN:
    {
        return "proven";
    }
    case ANCHOR_CHANNEL_DEATH_LEVEL:
    {
        return "death-level";
    }
    case ANCHOR_CHANNEL_SURVIVED:
    {
        return "survived";
    }
    case ANCHOR_CHANNEL_RARITY:
    {
        return "rarity";
    }
    case ANCHOR_CHANNEL_BYTE:
    {
        return "byte";
    }
    default:
    {
        return "unknown";
    }
    }
}

int anchor_raster_render(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count)
{
    /* DEVICE FIRST WHERE THERE IS ONE. Both arms produce the same bytes. This is a performance
     * choice and never a correctness one, and a machine carrying a device should use it without the
     * caller asking for it. */
    if (anchor_raster_device_available() != 0)
    {
        if (anchor_raster_device(pixels, config, corpus, corpus_len, needle, needle_len, probes,
                                 probe_count) != 0)
        {
            return 1;
        }
    }
    return anchor_raster_host(pixels, config, corpus, corpus_len, needle, needle_len, probes,
                              probe_count);
}

int anchor_raster_write_pgm(const char *path, const uint8_t *pixels, size_t width, size_t height)
{
    if ((path == NULL) || (pixels == NULL) || (width == 0u) || (height == 0u))
    {
        return 0;
    }

    FILE *handle = fopen(path, "wb");
    if (handle == NULL)
    {
        return 0;
    }

    if (fprintf(handle, "P5\n%zu %zu\n255\n", width, height) < 0)
    {
        fclose(handle);
        return 0;
    }

    const size_t cells = width * height;
    const size_t written = fwrite(pixels, 1u, cells, handle);
    fclose(handle);
    return (written == cells) ? 1 : 0;
}

const char *anchor_volume_layout_name(AnchorVolumeLayout layout)
{
    if (layout == ANCHOR_VOLUME_SLABS)
    {
        return "slabs";
    }
    if (layout == ANCHOR_VOLUME_BOUSTRO)
    {
        return "boustrophedon";
    }
    if (layout == ANCHOR_VOLUME_MORTON)
    {
        return "morton";
    }
    if (layout == ANCHOR_VOLUME_HELIX)
    {
        return "helix";
    }
    return "unknown";
}

/**
 * @brief Whether a value is a power of two and not zero.
 *
 * @param[in] value The extent to test.
 * @return          1 where the value is a power of two, 0 otherwise.
 */
static int volume_is_power_of_two(size_t value)
{
    return ((value != 0u) && ((value & (value - 1u)) == 0u)) ? 1 : 0;
}

size_t anchor_volume_cell_for(const AnchorVolumeConfig *config, size_t alignment)
{
    if (config == NULL)
    {
        return 0u;
    }

    const size_t width = config->width;
    const size_t height = config->height;
    const size_t depth = config->depth;
    const size_t cells = width * height * depth;

    if ((width == 0u) || (height == 0u) || (depth == 0u))
    {
        return 0u;
    }

    // Out of range folds back into the block. Every layout below is a bijection on [0, cells), and
    // an alignment count above the block size has to land somewhere; wrapping keeps the map total
    // and is stated.
    const size_t at = alignment % cells;
    const size_t sheet = width * height;

    switch (config->layout)
    {
    case ANCHOR_VOLUME_SLABS:
    {
        return at;
    }
    case ANCHOR_VOLUME_BOUSTRO:
    {
        const size_t slab = at / sheet;
        const size_t within = at % sheet;
        size_t row = within / width;
        size_t column = within % width;

        // Reverse every other row, then reverse the row order of every other slab. Consecutive
        // alignments stay adjacent across a row boundary and across a slab boundary both.
        if ((row % 2u) == 1u)
        {
            column = (width - 1u) - column;
        }
        if ((slab % 2u) == 1u)
        {
            row = (height - 1u) - row;
        }
        return (slab * sheet) + (row * width) + column;
    }
    case ANCHOR_VOLUME_MORTON:
    {
        // Refused  because the
        // interleave is a bijection only then and a silent fallback would make two
        // configurations render identically while reporting different layouts.
        if ((volume_is_power_of_two(width) == 0) || (volume_is_power_of_two(height) == 0) || (volume_is_power_of_two(depth) == 0))
        {
            return cells;
        }

        size_t x = 0u;
        size_t y = 0u;
        size_t z = 0u;
        for (size_t bit = 0u; bit < (sizeof(size_t) * 8u) / 3u; bit += 1u)
        {
            x |= ((at >> ((3u * bit) + 0u)) & 1u) << bit;
            y |= ((at >> ((3u * bit) + 1u)) & 1u) << bit;
            z |= ((at >> ((3u * bit) + 2u)) & 1u) << bit;
        }
        x %= width;
        y %= height;
        z %= depth;
        return (z * sheet) + (y * width) + x;
    }
    case ANCHOR_VOLUME_HELIX:
    {
        const size_t slab = at / sheet;
        const size_t within = at % sheet;
        const size_t row = within / width;
        const size_t column = (within + slab) % width;

        // A shear by the depth index. Adding the slab to the column is a bijection on each row
        // because it is addition modulo the width, and a feature at a fixed corpus offset
        // therefore advances one column per slab and winds through the block.
        return (slab * sheet) + (row * width) + column;
    }
    default:
    {
        return cells;
    }
    }
}

int anchor_volume_render_host(uint8_t *voxels, const AnchorVolumeConfig *config,
                              const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                              size_t needle_len, const AnchorRasterProbe *probes,
                              size_t probe_count, const void *census_in)
{
    // RESERVED, NOT READ, AND NOT DELETED. The census below is built from `corpus`. A caller
    // supplied one is discarded here. The parameter stays because a tunable with no reader is an
    // integration point  and the header says at the declaration instead
    // of calling it the rarity source, which is what it said until it was measured.
    (void)census_in;

    if ((voxels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL) || (config->width == 0u) || (config->height == 0u) || (config->depth == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0;
    }
    if ((probes == NULL) && (probe_count != 0u))
    {
        return 0;
    }

    const size_t cells = config->width * config->height * config->depth;
    for (size_t cell = 0u; cell < cells; cell += 1u)
    {
        voxels[cell] = (uint8_t)ANCHOR_RASTER_EMPTY;
    }

    // The channel, the gain and the reduce rule are the raster's and are read through a raster
    // configuration built here. Re-implementing them for three dimensions would be a second copy of
    // a decision that has one place, and the two copies would answer differently the first time a
    // channel was added to one of them.
    const AnchorRasterConfig flat = {
        config->width, config->height, ANCHOR_LAYOUT_ROWS, config->channel, config->reduce,
        config->gain};

    AnchorRasterCensus census;
    raster_census(&census, corpus, corpus_len);

    const size_t alignments = (corpus_len - needle_len) + 1u;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        const size_t cell = anchor_volume_cell_for(config, at);
        if (cell >= cells)
        {
            // The layout refused this configuration. Refusing every alignment identically is what
            // makes the refusal visible as an empty volume.
            return 0;
        }

        const uint8_t value = anchor_raster_sample(&flat, corpus, needle, needle_len, probes,
                                                   probe_count, at, census.occurrences,
                                                   census.total);

        if (voxels[cell] == (uint8_t)ANCHOR_RASTER_EMPTY)
        {
            voxels[cell] = value;
            continue;
        }
        if (config->reduce == ANCHOR_REDUCE_MAX)
        {
            if (value > voxels[cell])
            {
                voxels[cell] = value;
            }
        }
        else if (value < voxels[cell])
        {
            voxels[cell] = value;
        }
    }
    return 1;
}

int anchor_volume_render(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count, const void *census)
{
    // DEVICE FIRST WHERE THERE IS ONE, exactly as anchor_raster_render does for a sheet. Both arms
    // produce the same bytes. This is a performance choice and never a correctness one.
    if (anchor_volume_device_available() != 0)
    {
        if (anchor_volume_device(voxels, config, corpus, corpus_len, needle, needle_len, probes,
                                 probe_count, census) != 0)
        {
            return 1;
        }
    }
    return anchor_volume_render_host(voxels, config, corpus, corpus_len, needle, needle_len, probes,
                                     probe_count, census);
}

int anchor_volume_write_raw(const char *path, const uint8_t *voxels,
                            const AnchorVolumeConfig *config)
{
    if ((path == NULL) || (voxels == NULL) || (config == NULL) || (config->width == 0u) || (config->height == 0u) || (config->depth == 0u))
    {
        return 0;
    }

    FILE *const handle = fopen(path, "wb");
    if (handle == NULL)
    {
        return 0;
    }

    const size_t cells = config->width * config->height * config->depth;
    const size_t written = fwrite(voxels, 1u, cells, handle);
    fclose(handle);

    if (written != cells)
    {
        return 0;
    }

    // The sidecar, because Netpbm has no volume container and inventing one would make this tree
    // the only reader of its own output. A generated file says it is generated and names what made
    // it, which is what lets somebody meeting the .raw alone work out what to do with it.
    char sidecar[512];
    const int used = snprintf(sidecar, sizeof(sidecar), "%s.txt", path);
    if ((used <= 0) || ((size_t)used >= sizeof(sidecar)))
    {
        return 0;
    }

    FILE *const notes = fopen(sidecar, "wb");
    if (notes == NULL)
    {
        return 0;
    }
    fprintf(notes, "generated by anchor_volume_write_raw in src/engine/c/render/anchor_raster.c\n");
    fprintf(notes, "format raw unsigned 8 bit, x fastest then y then z, no header, no padding\n");
    fprintf(notes, "width %zu\nheight %zu\ndepth %zu\nbytes %zu\n",
            config->width, config->height, config->depth, cells);
    fprintf(notes, "layout %s\nchannel %s\n", anchor_volume_layout_name(config->layout),
            anchor_raster_channel_name(config->channel));
    fprintf(notes, "reduce %s\ngain %u\n",
            (config->reduce == ANCHOR_REDUCE_MAX) ? "max" : "min", (unsigned)config->gain);
    fclose(notes);
    return 1;
}

#if !defined(ANCHOR_RASTER_HAVE_CUDA) || !ANCHOR_RASTER_HAVE_CUDA

/* BOTH ARMS DEFINED. A build without the device renderer still carries these symbols. A driver
 * written against both arms links and runs against either. The available test returning zero is what
 * a caller checks before calling the other, and the other refuses. */

int anchor_raster_device_available(void)
{
    return 0;
}

int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count)
{
    (void)pixels;
    (void)config;
    (void)corpus;
    (void)corpus_len;
    (void)needle;
    (void)needle_len;
    (void)probes;
    (void)probe_count;
    return 0;
}

int anchor_volume_device_available(void)
{
    return 0;
}

int anchor_volume_device(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count, const void *census)
{
    (void)voxels;
    (void)config;
    (void)corpus;
    (void)corpus_len;
    (void)needle;
    (void)needle_len;
    (void)probes;
    (void)probe_count;
    (void)census;
    return 0;
}

#endif
