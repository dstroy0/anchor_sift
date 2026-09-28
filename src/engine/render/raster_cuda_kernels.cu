
// raster_cuda_kernels.cu: the raster and volume kernels
#include "raster_cuda_internal.h"

/** @brief The level at which one alignment died, matching raster_death_level on the host. */
__device__ static unsigned long long device_death_level(const unsigned char *corpus, const unsigned char *needle,
                                                        unsigned long long needle_len, const DeviceProbe *probes,
                                                        unsigned long long probe_count, unsigned long long at,
                                                        int *matched)
{
    *matched = 0;

    for (unsigned long long slot = 0u; slot < probe_count; slot += 1u)
    {
        for (unsigned long long step = 0u; step < probes[slot].length; step += 1u)
        {
            const unsigned long long offset = probes[slot].origin + (step * probes[slot].step);
            if (corpus[at + offset] != needle[offset])
            {
                return slot;
            }
        }
    }
    for (unsigned long long step = 0u; step < needle_len; step += 1u)
    {
        if (corpus[at + step] != needle[step])
        {
            return probe_count;
        }
    }
    *matched = 1;
    return probe_count;
}

/** @brief Gray value for a death level, matching raster_value on the host. */
__device__ static unsigned char device_value(unsigned long long level, int matched)
{
    if (matched != 0)
    {
        return (unsigned char)ANCHOR_RASTER_MATCH;
    }
    const unsigned long long scaled = 1u + (level * RASTER_STEP);
    return (unsigned char)((scaled > RASTER_CEILING) ? RASTER_CEILING : scaled);
}

/** @brief Cell an alignment lands on, matching anchor_raster_cell on the host. */
__device__ static unsigned long long device_cell(const DeviceConfig *config, unsigned long long at,
                                                 unsigned long long alignments)
{
    const unsigned long long cells = config->width * config->height;
    const unsigned long long linear = (at * cells) / alignments;
    const unsigned long long row = linear / config->width;
    const unsigned long long column = linear % config->width;

    if (config->layout == ANCHOR_LAYOUT_SERPENTINE)
    {
        const unsigned long long flipped = ((row % 2u) == 0u) ? column : (config->width - 1u - column);
        return (row * config->width) + flipped;
    }
    if (config->layout == ANCHOR_LAYOUT_COLUMNS)
    {
        const unsigned long long turned_row = linear % config->height;
        const unsigned long long turned_column = linear / config->height;
        if (turned_column >= config->width)
        {
            return linear;
        }
        return (turned_row * config->width) + turned_column;
    }
    if (config->layout == ANCHOR_LAYOUT_DIAGONAL)
    {
        const unsigned long long shifted = (column + row) % config->width;
        return (row * config->width) + shifted;
    }
    return linear;
}

/** @brief Value an alignment contributes, matching anchor_raster_sample on the host. */
__device__ static unsigned char device_sample(const DeviceConfig *config, const unsigned char *corpus,
                                              const unsigned char *needle, unsigned long long needle_len,
                                              const DeviceProbe *probes, unsigned long long probe_count,
                                              unsigned long long at, const unsigned long long *occurrences,
                                              unsigned long long total)
{
    const unsigned int gain = (config->gain == 0u) ? 1u : config->gain;

    if (config->channel == ANCHOR_CHANNEL_BYTE)
    {
        return corpus[at];
    }
    if (config->channel == ANCHOR_CHANNEL_RARITY)
    {
        if (total == 0u)
        {
            return 1u;
        }
        const unsigned long long missing = total - occurrences[corpus[at]];
        return (unsigned char)(1u + ((missing * 254u) / total));
    }

    int matched = 0;
    const unsigned long long level = device_death_level(corpus, needle, needle_len, probes, probe_count, at, &matched);
    if (config->channel == ANCHOR_CHANNEL_PROVEN)
    {
        return (level < probe_count) ? (unsigned char)ANCHOR_RASTER_PROVEN : (unsigned char)ANCHOR_RASTER_UNDETERMINED;
    }
    if (config->channel == ANCHOR_CHANNEL_SURVIVED)
    {
        return (level >= probe_count) ? (unsigned char)ANCHOR_RASTER_MATCH : (unsigned char)1u;
    }
    return device_value(level * (unsigned long long)gain, matched);
}

/**
 * @brief Renders every alignment into the raster, one thread each.
 *
 * @note The atomics run on a 32-bit staging buffer because CUDA has no 8-bit atomicMin. The host
 *       narrows the result afterward, which costs one pass over the cells and keeps the reduction
 *       exact.
 */
__global__ void render_alignments(unsigned int *staging, DeviceConfig config, const unsigned char *corpus,
                                  unsigned long long corpus_len, const unsigned char *needle,
                                  unsigned long long needle_len, const DeviceProbe *probes,
                                  unsigned long long probe_count, const unsigned long long *occurrences,
                                  unsigned long long total)
{
    const unsigned long long alignments = (corpus_len - needle_len) + 1u;
    const unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (at >= alignments)
    {
        return;
    }

    const unsigned char value =
        device_sample(&config, corpus, needle, needle_len, probes, probe_count, at, occurrences, total);
    const unsigned long long cell = device_cell(&config, at, alignments);

    if (config.reduce == ANCHOR_REDUCE_MAX)
    {
        atomicMax(&staging[cell], (unsigned int)value);
    }
    else
    {
        atomicMin(&staging[cell], (unsigned int)value);
    }
}

extern "C" int anchor_raster_device_available(void)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }
    return 1;
}

/** @brief Whether a value is a power of two, matching volume_is_power_of_two on the host. */
__device__ static int device_is_power_of_two(unsigned long long value)
{
    return ((value != 0u) && ((value & (value - 1u)) == 0u)) ? 1 : 0;
}

/**
 * @brief Voxel an alignment lands on, matching anchor_volume_cell_for on the host.
 *
 * @note Returns `cells` where the layout errors on the configuration, which is MORTON on extents that
 *       are not all powers of two and any unknown layout. The host returns the block size in the
 *       same cases and the caller reads it as "not placed". Every supported layout wraps the
 *       alignment with `% cells` first. It is a bijection on the block and never errors.
 */
__device__ static unsigned long long device_volume_cell(const DeviceVolumeConfig *config, unsigned long long alignment,
                                                        unsigned long long cells)
{
    const unsigned long long width = config->width;
    const unsigned long long height = config->height;
    const unsigned long long depth = config->depth;
    const unsigned long long at = alignment % cells;
    const unsigned long long sheet = width * height;

    if (config->layout == ANCHOR_VOLUME_SLABS)
    {
        return at;
    }
    if (config->layout == ANCHOR_VOLUME_BOUSTRO)
    {
        const unsigned long long slab = at / sheet;
        const unsigned long long within = at % sheet;
        unsigned long long row = within / width;
        unsigned long long column = within % width;
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
    if (config->layout == ANCHOR_VOLUME_MORTON)
    {
        if ((device_is_power_of_two(width) == 0) || (device_is_power_of_two(height) == 0) ||
            (device_is_power_of_two(depth) == 0))
        {
            return cells;
        }
        unsigned long long x = 0u;
        unsigned long long y = 0u;
        unsigned long long z = 0u;
        for (unsigned long long bit = 0u; bit < (sizeof(unsigned long long) * 8u) / 3u; bit += 1u)
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
    if (config->layout == ANCHOR_VOLUME_HELIX)
    {
        const unsigned long long slab = at / sheet;
        const unsigned long long within = at % sheet;
        const unsigned long long row = within / width;
        const unsigned long long column = (within + slab) % width;
        return (slab * sheet) + (row * width) + column;
    }
    return cells;
}

/**
 * @brief Renders every alignment into the volume, one thread each.
 *
 * @note The value comes from the same device_sample the sheet kernel uses, since a channel means
 *       one thing across both. Only the cell mapping differs, and `error` carries the host's
 *       whole-render error into the parallel form: a thread whose alignment maps out of range
 *       sets it, and the host returns 0 without reading the staging buffer.
 */
__global__ void render_volume(unsigned int *staging, int *error, DeviceVolumeConfig vconfig,
                              const unsigned char *corpus, unsigned long long corpus_len, const unsigned char *needle,
                              unsigned long long needle_len, const DeviceProbe *probes, unsigned long long probe_count,
                              const unsigned long long *occurrences, unsigned long long total)
{
    const unsigned long long alignments = (corpus_len - needle_len) + 1u;
    const unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (at >= alignments)
    {
        return;
    }

    // device_sample reads only the channel and the gain from the configuration. The width, height
    // and layout it is handed are the volume's and go unread.
    DeviceConfig sample_config;
    sample_config.width = vconfig.width;
    sample_config.height = vconfig.height;
    sample_config.layout = ANCHOR_LAYOUT_ROWS;
    sample_config.channel = vconfig.channel;
    sample_config.reduce = vconfig.reduce;
    sample_config.gain = vconfig.gain;

    const unsigned char value =
        device_sample(&sample_config, corpus, needle, needle_len, probes, probe_count, at, occurrences, total);
    const unsigned long long cells = vconfig.width * vconfig.height * vconfig.depth;
    const unsigned long long cell = device_volume_cell(&vconfig, at, cells);
    if (cell >= cells)
    {
        atomicExch(error, 1);
        return;
    }

    if (vconfig.reduce == ANCHOR_REDUCE_MAX)
    {
        atomicMax(&staging[cell], (unsigned int)value);
    }
    else
    {
        atomicMin(&staging[cell], (unsigned int)value);
    }
}
