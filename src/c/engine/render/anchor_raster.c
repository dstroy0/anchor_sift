
// anchor_raster.c: the raster on the host
#include "anchor_raster_internal.h"

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
                                 const AnchorRasterProbe *probes, size_t probe_count, size_t at, int *matched)
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

    /* Survived every probe. The full compare decides an occurrence, and a survivor that
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

/** @brief Counts what the object under examination is made of. */
void raster_census(AnchorRasterCensus *census, const uint8_t *corpus, size_t corpus_len)
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
    case ANCHOR_LAYOUT_SERPENTINE: {
        const size_t flipped = ((row % 2u) == 0u) ? column : (config->width - 1u - column);
        return (row * config->width) + flipped;
    }
    case ANCHOR_LAYOUT_COLUMNS: {
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
    case ANCHOR_LAYOUT_DIAGONAL: {
        const size_t shifted = (column + row) % config->width;
        return (row * config->width) + shifted;
    }
    case ANCHOR_LAYOUT_ROWS:
    default: {
        return linear;
    }
    }
}

uint8_t anchor_raster_sample(const AnchorRasterConfig *config, const uint8_t *corpus, const uint8_t *needle,
                             size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count, size_t at,
                             const uint64_t *occurrences, uint64_t total)
{
    const uint8_t gain = (config->gain == 0u) ? 1u : config->gain;

    switch (config->channel)
    {
    case ANCHOR_CHANNEL_BYTE: {
        return corpus[at];
    }
    case ANCHOR_CHANNEL_RARITY: {
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
    case ANCHOR_CHANNEL_PROVEN: {
        /* A refuted alignment is proven to hold no occurrence. A survivor is undetermined: the
         * probes could not refute it and only the full compare decides. Proven takes the higher
         * value, a minimum reduction behaves as the conjunction this channel needs, a cell
         * staying proven only while every alignment under it was refuted. */
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes, probe_count, at, &matched);
        return (level < probe_count) ? (uint8_t)ANCHOR_RASTER_PROVEN : (uint8_t)ANCHOR_RASTER_UNDETERMINED;
    }
    case ANCHOR_CHANNEL_SURVIVED: {
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes, probe_count, at, &matched);
        return (level >= probe_count) ? (uint8_t)ANCHOR_RASTER_MATCH : 1u;
    }
    case ANCHOR_CHANNEL_DEATH_LEVEL:
    default: {
        int matched = 0;
        const size_t level = raster_death_level(corpus, needle, needle_len, probes, probe_count, at, &matched);
        return raster_value(level * (size_t)gain, probe_count, matched);
    }
    }
}

int anchor_raster_host(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus, size_t corpus_len,
                       const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count)
{
    if ((pixels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL) || (config->width == 0u) ||
        (config->height == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
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
        const uint8_t value = anchor_raster_sample(config, corpus, needle, needle_len, probes, probe_count, at,
                                                   census.occurrences, census.total);
        const size_t cell = anchor_raster_cell(config, at, alignments);

        /* An empty cell holds zero, which would win every minimum and lose every maximum. It is
         * filled on first arrival and not compared against. */
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
    case ANCHOR_LAYOUT_ROWS: {
        return "rows";
    }
    case ANCHOR_LAYOUT_SERPENTINE: {
        return "serpentine";
    }
    case ANCHOR_LAYOUT_COLUMNS: {
        return "columns";
    }
    case ANCHOR_LAYOUT_DIAGONAL: {
        return "diagonal";
    }
    default: {
        return "unknown";
    }
    }
}

const char *anchor_raster_channel_name(AnchorRasterChannel channel)
{
    switch (channel)
    {
    case ANCHOR_CHANNEL_PROVEN: {
        return "proven";
    }
    case ANCHOR_CHANNEL_DEATH_LEVEL: {
        return "death-level";
    }
    case ANCHOR_CHANNEL_SURVIVED: {
        return "survived";
    }
    case ANCHOR_CHANNEL_RARITY: {
        return "rarity";
    }
    case ANCHOR_CHANNEL_BYTE: {
        return "byte";
    }
    default: {
        return "unknown";
    }
    }
}

int anchor_raster_render(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needle, size_t needle_len, const AnchorRasterProbe *probes, size_t probe_count)
{
    /* DEVICE FIRST WHERE THERE IS ONE. Both arms produce the same bytes. This is a performance
     * choice and never a correctness one, and a machine carrying a device should use it without the
     * caller asking for it. */
    if (anchor_raster_device_available() != 0)
    {
        if (anchor_raster_device(pixels, config, corpus, corpus_len, needle, needle_len, probes, probe_count) != 0)
        {
            return 1;
        }
    }
    return anchor_raster_host(pixels, config, corpus, corpus_len, needle, needle_len, probes, probe_count);
}
