
// anchor_raster_output.c: the PGM, the volume and the device entry points
#include "anchor_raster_internal.h"

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
    // and is stated and not left to an out of bounds write.
    const size_t at = alignment % cells;
    const size_t sheet = width * height;

    switch (config->layout)
    {
    case ANCHOR_VOLUME_SLABS: {
        return at;
    }
    case ANCHOR_VOLUME_BOUSTRO: {
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
    case ANCHOR_VOLUME_MORTON: {
        // Refused and not remapped where the extents are not powers of two, because the
        // interleave is a bijection only then and a silent fallback would make two
        // configurations render identically while reporting different layouts.
        if ((volume_is_power_of_two(width) == 0) || (volume_is_power_of_two(height) == 0) ||
            (volume_is_power_of_two(depth) == 0))
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
    case ANCHOR_VOLUME_HELIX: {
        const size_t slab = at / sheet;
        const size_t within = at % sheet;
        const size_t row = within / width;
        const size_t column = (within + slab) % width;

        // A shear by the depth index. Adding the slab to the column is a bijection on each row
        // because it is addition modulo the width, and a feature at a fixed corpus offset
        // therefore advances one column per slab and winds through the block.
        return (slab * sheet) + (row * width) + column;
    }
    default: {
        return cells;
    }
    }
}

int anchor_volume_render_host(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus,
                              size_t corpus_len, const uint8_t *needle, size_t needle_len,
                              const AnchorRasterProbe *probes, size_t probe_count, const void *census_in)
{
    // RESERVED, NOT READ, AND NOT DELETED. The census below is built from `corpus`. A caller
    // supplied one is discarded here. The parameter stays because a tunable with no reader is an
    // integration point and not dead weight, and the header says so at the declaration instead
    // of calling it the rarity source, as it did until it was measured.
    (void)census_in;

    if ((voxels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL) || (config->width == 0u) ||
        (config->height == 0u) || (config->depth == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
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
    const AnchorRasterConfig flat = {config->width,   config->height, ANCHOR_LAYOUT_ROWS,
                                     config->channel, config->reduce, config->gain};

    AnchorRasterCensus census;
    raster_census(&census, corpus, corpus_len);

    const size_t alignments = (corpus_len - needle_len) + 1u;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        const size_t cell = anchor_volume_cell_for(config, at);
        if (cell >= cells)
        {
            // The layout refused this configuration. Refusing every alignment identically
            // makes the refusal visible as an empty volume and not as a partial one.
            return 0;
        }

        const uint8_t value = anchor_raster_sample(&flat, corpus, needle, needle_len, probes, probe_count, at,
                                                   census.occurrences, census.total);

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

int anchor_volume_render(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count,
                         const void *census)
{
    // DEVICE FIRST WHERE THERE IS ONE, exactly as anchor_raster_render does for a sheet. Both arms
    // produce the same bytes. This is a performance choice and never a correctness one.
    if (anchor_volume_device_available() != 0)
    {
        if (anchor_volume_device(voxels, config, corpus, corpus_len, needle, needle_len, probes, probe_count, census) !=
            0)
        {
            return 1;
        }
    }
    return anchor_volume_render_host(voxels, config, corpus, corpus_len, needle, needle_len, probes, probe_count,
                                     census);
}

int anchor_volume_write_raw(const char *path, const uint8_t *voxels, const AnchorVolumeConfig *config)
{
    if ((path == NULL) || (voxels == NULL) || (config == NULL) || (config->width == 0u) || (config->height == 0u) ||
        (config->depth == 0u))
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
    // it, and somebody meeting the .raw alone can work out what to do with it.
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
    fprintf(notes, "generated by anchor_volume_write_raw in the engine's render/anchor_raster_*.c\n");
    fprintf(notes, "format raw unsigned 8 bit, x fastest then y then z, no header, no padding\n");
    fprintf(notes, "width %zu\nheight %zu\ndepth %zu\nbytes %zu\n", config->width, config->height, config->depth,
            cells);
    fprintf(notes, "layout %s\nchannel %s\n", anchor_volume_layout_name(config->layout),
            anchor_raster_channel_name(config->channel));
    fprintf(notes, "reduce %s\ngain %u\n", (config->reduce == ANCHOR_REDUCE_MAX) ? "max" : "min",
            (unsigned)config->gain);
    fclose(notes);
    return 1;
}

#if !defined(ANCHOR_RASTER_HAVE_CUDA) || !ANCHOR_RASTER_HAVE_CUDA

/* BOTH ARMS DEFINED. A build without the device renderer still carries these symbols. A driver
 * written against both arms links and runs against either. The available test returning zero is what
 * a caller checks before calling the other, and the other refuses instead of pretending. */

int anchor_raster_device_available(void)
{
    return 0;
}

int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count)
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

int anchor_volume_device(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count,
                         const void *census)
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
