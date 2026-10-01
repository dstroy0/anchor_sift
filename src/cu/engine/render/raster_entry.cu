
// raster_entry.cu: the device entry points
#include "raster_cuda_internal.h"

extern "C" int anchor_volume_device_available(void)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }
    return 1;
}

extern "C" int anchor_volume_device(uint8_t *voxels, const AnchorVolumeConfig *config, const uint8_t *corpus,
                                    size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                    const AnchorRasterProbe *probes, size_t probe_count, const void *census)
{
    // RESERVED. Built from the corpus below exactly as the host arm does. The two
    // agree on rarity, and a caller supplied census is discarded on both.
    (void)census;

    if ((voxels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL) || (config->width == 0u) ||
        (config->height == 0u) || (config->depth == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0;
    }
    if ((probes == NULL) && (probe_count != 0u))
    {
        return 0;
    }
    if (anchor_volume_device_available() == 0)
    {
        return 0;
    }

    const size_t cells = config->width * config->height * config->depth;
    const size_t alignments = (corpus_len - needle_len) + 1u;

    unsigned long long occurrences[256];
    for (size_t symbol = 0u; symbol < 256u; symbol += 1u)
    {
        occurrences[symbol] = 0u;
    }
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        occurrences[corpus[at]] += 1u;
    }

    DeviceVolumeConfig plan;
    plan.width = config->width;
    plan.height = config->height;
    plan.depth = config->depth;
    plan.layout = (int)config->layout;
    plan.channel = (int)config->channel;
    plan.reduce = (int)config->reduce;
    plan.gain = config->gain;

    DeviceProbe staged[16];
    if (probe_count > 16u)
    {
        return 0;
    }
    for (size_t slot = 0u; slot < probe_count; slot += 1u)
    {
        staged[slot].origin = probes[slot].origin;
        staged[slot].step = probes[slot].step;
        staged[slot].length = probes[slot].length;
    }

    unsigned int *device_staging = NULL;
    int *device_error = NULL;
    unsigned char *device_corpus = NULL;
    unsigned char *device_needle = NULL;
    DeviceProbe *device_probes = NULL;
    unsigned long long *device_occurrences = NULL;
    int ok = 1;

    ok = ok && (cudaMalloc((void **)&device_staging, cells * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_error, sizeof(int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_corpus, corpus_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_needle, needle_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_occurrences, sizeof(occurrences)) == cudaSuccess);
    if (probe_count > 0u)
    {
        ok = ok && (cudaMalloc((void **)&device_probes, probe_count * sizeof(DeviceProbe)) == cudaSuccess);
    }

    if (ok != 0)
    {
        // The staging buffer starts at the reduction's identity and the narrowing pass turns any
        // untouched cell back into empty, matching the host's fill on first arrival.
        const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX) ? 0u : 0xFFFFFFFFu;
        unsigned int *seed = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (seed == NULL)
        {
            ok = 0;
        }
        else
        {
            for (size_t cell = 0u; cell < cells; cell += 1u)
            {
                seed[cell] = identity;
            }
            ok = ok && (cudaMemcpy(device_staging, seed, cells * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
                        cudaSuccess);
            free(seed);
        }
    }

    if (ok != 0)
    {
        const int zero = 0;
        ok = ok && (cudaMemcpy(device_error, &zero, sizeof(int), cudaMemcpyHostToDevice) == cudaSuccess);
    }
    ok = ok && (cudaMemcpy(device_corpus, corpus, corpus_len, cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(device_needle, needle, needle_len, cudaMemcpyHostToDevice) == cudaSuccess);
    ok =
        ok && (cudaMemcpy(device_occurrences, occurrences, sizeof(occurrences), cudaMemcpyHostToDevice) == cudaSuccess);
    if ((ok != 0) && (probe_count > 0u))
    {
        ok = ok && (cudaMemcpy(device_probes, staged, probe_count * sizeof(DeviceProbe), cudaMemcpyHostToDevice) ==
                    cudaSuccess);
    }

    int error = 0;
    if (ok != 0)
    {
        const unsigned int threads = 256u;
        const unsigned int blocks = (unsigned int)((alignments + threads - 1u) / threads);
        render_volume<<<blocks, threads>>>(
            device_staging, device_error, plan, device_corpus, (unsigned long long)corpus_len, device_needle,
            (unsigned long long)needle_len, device_probes, (unsigned long long)probe_count, device_occurrences,
            (unsigned long long)corpus_len);
        ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
        ok = ok && (cudaMemcpy(&error, device_error, sizeof(int), cudaMemcpyDeviceToHost) == cudaSuccess);
    }

    // The layout errored on this configuration, exactly as the host returns 0 without writing a volume.
    if ((ok != 0) && (error != 0))
    {
        ok = 0;
    }

    if (ok != 0)
    {
        unsigned int *result = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (result == NULL)
        {
            ok = 0;
        }
        else
        {
            ok = ok && (cudaMemcpy(result, device_staging, cells * sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
                        cudaSuccess);
            if (ok != 0)
            {
                const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX) ? 0u : 0xFFFFFFFFu;
                for (size_t cell = 0u; cell < cells; cell += 1u)
                {
                    voxels[cell] = (result[cell] == identity) ? (uint8_t)ANCHOR_RASTER_EMPTY : (uint8_t)result[cell];
                }
            }
            free(result);
        }
    }

    cudaFree(device_staging);
    cudaFree(device_error);
    cudaFree(device_corpus);
    cudaFree(device_needle);
    cudaFree(device_occurrences);
    cudaFree(device_probes);
    return ok;
}

extern "C" int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                                    size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                    const AnchorRasterProbe *probes, size_t probe_count)
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
    if (anchor_raster_device_available() == 0)
    {
        return 0;
    }

    const size_t cells = config->width * config->height;
    const size_t alignments = (corpus_len - needle_len) + 1u;

    /* The census is built on the host and uploaded. It is one pass over the corpus either way, and
     * building it here would add a second reduction to grade against the host's. */
    unsigned long long occurrences[256];
    for (size_t symbol = 0u; symbol < 256u; symbol += 1u)
    {
        occurrences[symbol] = 0u;
    }
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        occurrences[corpus[at]] += 1u;
    }

    DeviceConfig plan;
    plan.width = config->width;
    plan.height = config->height;
    plan.layout = (int)config->layout;
    plan.channel = (int)config->channel;
    plan.reduce = (int)config->reduce;
    plan.gain = config->gain;

    DeviceProbe staged[16];
    if (probe_count > 16u)
    {
        return 0;
    }
    for (size_t slot = 0u; slot < probe_count; slot += 1u)
    {
        staged[slot].origin = probes[slot].origin;
        staged[slot].step = probes[slot].step;
        staged[slot].length = probes[slot].length;
    }

    unsigned int *device_staging = NULL;
    unsigned char *device_corpus = NULL;
    unsigned char *device_needle = NULL;
    DeviceProbe *device_probes = NULL;
    unsigned long long *device_occurrences = NULL;
    int ok = 1;

    ok = ok && (cudaMalloc((void **)&device_staging, cells * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_corpus, corpus_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_needle, needle_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_occurrences, sizeof(occurrences)) == cudaSuccess);
    if (probe_count > 0u)
    {
        ok = ok && (cudaMalloc((void **)&device_probes, probe_count * sizeof(DeviceProbe)) == cudaSuccess);
    }

    if (ok != 0)
    {
        /* An empty cell is the identity for whichever reduction runs. The fill differs by rule.
         * The host marks empty with zero and fills on first arrival; here the staging buffer starts
         * at the identity and the narrowing pass below turns any untouched cell back into zero. */
        const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX) ? 0u : 0xFFFFFFFFu;
        unsigned int *seed = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (seed == NULL)
        {
            ok = 0;
        }
        else
        {
            for (size_t cell = 0u; cell < cells; cell += 1u)
            {
                seed[cell] = identity;
            }
            ok = ok && (cudaMemcpy(device_staging, seed, cells * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
                        cudaSuccess);
            free(seed);
        }
    }

    ok = ok && (cudaMemcpy(device_corpus, corpus, corpus_len, cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(device_needle, needle, needle_len, cudaMemcpyHostToDevice) == cudaSuccess);
    ok =
        ok && (cudaMemcpy(device_occurrences, occurrences, sizeof(occurrences), cudaMemcpyHostToDevice) == cudaSuccess);
    if ((ok != 0) && (probe_count > 0u))
    {
        ok = ok && (cudaMemcpy(device_probes, staged, probe_count * sizeof(DeviceProbe), cudaMemcpyHostToDevice) ==
                    cudaSuccess);
    }

    if (ok != 0)
    {
        const unsigned int threads = 256u;
        const unsigned int blocks = (unsigned int)((alignments + threads - 1u) / threads);
        render_alignments<<<blocks, threads>>>(device_staging, plan, device_corpus, (unsigned long long)corpus_len,
                                               device_needle, (unsigned long long)needle_len, device_probes,
                                               (unsigned long long)probe_count, device_occurrences,
                                               (unsigned long long)corpus_len);
        ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    }

    if (ok != 0)
    {
        unsigned int *result = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (result == NULL)
        {
            ok = 0;
        }
        else
        {
            ok = ok && (cudaMemcpy(result, device_staging, cells * sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
                        cudaSuccess);
            if (ok != 0)
            {
                const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX) ? 0u : 0xFFFFFFFFu;
                for (size_t cell = 0u; cell < cells; cell += 1u)
                {
                    pixels[cell] = (result[cell] == identity) ? (uint8_t)ANCHOR_RASTER_EMPTY : (uint8_t)result[cell];
                }
            }
            free(result);
        }
    }

    cudaFree(device_staging);
    cudaFree(device_corpus);
    cudaFree(device_needle);
    cudaFree(device_occurrences);
    cudaFree(device_probes);
    return ok;
}
