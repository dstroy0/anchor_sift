// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_floor_massey.cu: bits, Massey, the mock and the transfer kernel
#include "noise_floor_internal.h"

static inline __host__ __device__ unsigned int floor_bit(const FloorStream *stream, unsigned int at)
{
    // a bit is 0 or 1
    return (unsigned int)((stream->word[at / 64u] >> (at % 64u)) & 1ull);
}

static inline __host__ __device__ void floor_flip(FloorStream *stream, unsigned int at)
{
    stream->word[at / 64u] ^= 1ull << (at % 64u);
}

static inline __host__ __device__ void floor_shifted_add(FloorStream *into, const FloorStream *from, unsigned int shift)
{
    for (unsigned int at = 0u; (at + shift) < FLOOR_STREAM_BITS; at += 1u)
    {
        if (floor_bit(from, at) != 0u)
        {
            floor_flip(into, at + shift);
        }
    }
}

static __global__ void floor_massey_kernel(const FloorStream *streams, unsigned int count, unsigned int *lengths,
                                           unsigned int *regenerated)
{
    const unsigned int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= count)
    {
        return;
    }
    const FloorStream *const bits = &streams[index];
    FloorStream connection;
    FloorStream before;
    FloorStream saved;
    for (unsigned int word = 0u; word < FLOOR_STREAM_WORDS; word += 1u)
    {
        connection.word[word] = 0ull;
        before.word[word] = 0ull;
    }
    connection.word[0] = 1ull;
    before.word[0] = 1ull;
    unsigned int length = 0u;
    unsigned int gap = 1u;
    for (unsigned int at = 0u; at < FLOOR_STREAM_BITS; at += 1u)
    {
        unsigned int discrepancy = floor_bit(bits, at);
        for (unsigned int tap = 1u; tap <= length; tap += 1u)
        {
            discrepancy ^= floor_bit(&connection, tap) & floor_bit(bits, at - tap);
        }
        if (discrepancy == 0u)
        {
            gap += 1u;
        }
        else if ((2u * length) <= at)
        {
            saved = connection;
            floor_shifted_add(&connection, &before, gap);
            length = at + 1u - length;
            before = saved;
            gap = 1u;
        }
        else
        {
            floor_shifted_add(&connection, &before, gap);
            gap += 1u;
        }
    }
    unsigned int matches = 1u;
    for (unsigned int at = length; at < FLOOR_STREAM_BITS; at += 1u)
    {
        unsigned int next = 0u;
        for (unsigned int tap = 1u; tap <= length; tap += 1u)
        {
            next ^= floor_bit(&connection, tap) & floor_bit(bits, at - tap);
        }
        matches &= (next == floor_bit(bits, at)) ? 1u : 0u;
    }
    lengths[index] = length;
    regenerated[index] = matches;
}

static int floor_massey(SimResults *results, const FloorStream *streams, unsigned int count, unsigned int *lengths,
                        unsigned int *regenerated)
{
    FloorStream *device_streams = NULL;
    unsigned int *device_lengths = NULL;
    unsigned int *device_regenerated = NULL;
    int ok =
        sim_status_check(results, cudaMalloc((void **)&device_streams, count * sizeof(FloorStream)), "massey: streams");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_lengths, count * sizeof(unsigned int)),
                                "massey: lengths");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_regenerated, count * sizeof(unsigned int)),
                                "massey: regenerated");
    ok = ok && sim_status_check(
                   results, cudaMemcpy(device_streams, streams, count * sizeof(FloorStream), cudaMemcpyHostToDevice),
                   "massey: upload");
    if (ok)
    {
        // the stream count is far below 2^31
        const unsigned int blocks = (unsigned int)sim_launch_blocks(count, FLOOR_THREADS);
        floor_massey_kernel<<<blocks, (unsigned int)FLOOR_THREADS>>>(device_streams, count, device_lengths,
                                                                     device_regenerated);
        ok = sim_status_check(results, cudaGetLastError(), "massey: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "massey: run");
    }
    ok = ok && sim_status_check(
                   results, cudaMemcpy(lengths, device_lengths, count * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                   "massey: lengths read");
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(regenerated, device_regenerated, count * sizeof(unsigned int), cudaMemcpyDeviceToHost),
             "massey: regenerated read");
    cudaFree(device_regenerated);
    cudaFree(device_lengths);
    cudaFree(device_streams);
    return ok;
}

static void floor_seeded_stream(FloorStream *stream, unsigned int degree, unsigned long long key,
                                unsigned long long index)
{
    memset(stream, 0, sizeof(*stream));
    const unsigned long long range = (degree == 64u) ? 0xFFFFFFFFFFFFFFFFull : ((1ull << degree) - 1ull);
    const unsigned long long taps = (sim_draw(key, (index * 4ull) + 0ull) & range) | (1ull << (degree - 1u));
    unsigned long long state = sim_draw(key, (index * 4ull) + 1ull) & range;
    state = (state == 0ull) ? 1ull : state;
    for (unsigned int at = 0u; at < FLOOR_STREAM_BITS; at += 1u)
    {
        if (at < degree)
        {
            if (((state >> at) & 1ull) != 0ull)
            {
                floor_flip(stream, at);
            }
            continue;
        }
        unsigned int next = 0u;
        for (unsigned int tap = 1u; tap <= degree; tap += 1u)
        {
            // one tap bit, 0 or 1
            next ^= (unsigned int)((taps >> (tap - 1u)) & 1ull) & floor_bit(stream, at - tap);
        }
        if (next != 0u)
        {
            floor_flip(stream, at);
        }
    }
}

void floor_mock(SimResults *results, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated)
{
    unsigned int degree[FLOOR_STREAMS];
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        // the draw is below the degree span, far under 2^32
        degree[index] = FLOOR_DEGREE_LEAST +
                        (unsigned int)sim_draw_below(FLOOR_KEY, index, (FLOOR_DEGREE_MAX - FLOOR_DEGREE_LEAST) + 1u);
        floor_seeded_stream(&streams[index], degree[index], FLOOR_KEY ^ 0x5EEDull, index);
    }
    if (floor_massey(results, streams, FLOOR_STREAMS, lengths, regenerated) == 0)
    {
        return;
    }
    unsigned long long within = 0ull;
    unsigned long long rebuilt = 0ull;
    unsigned long long description = 0ull;
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        within += (lengths[index] <= degree[index]) ? 1ull : 0ull;
        rebuilt += regenerated[index];
        description += 2ull * lengths[index];
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  the Kolmogorov mock: ");
    scriptura_decimal(line, FLOOR_STREAMS, 1u);
    scriptura_text(line, " streams of ");
    scriptura_decimal(line, FLOOR_STREAM_BITS, 1u);
    scriptura_text(line, " bits, each from a linear generator of degree ");
    scriptura_decimal(line, FLOOR_DEGREE_LEAST, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, FLOOR_DEGREE_MAX, 1u);
    scriptura_text(line, " and a drawn seed\n    Berlekamp-Massey: complexity within the degree on ");
    scriptura_decimal(line, within, 1u);
    scriptura_text(line, ", the whole stream regenerated from its first L bits on ");
    scriptura_decimal(line, rebuilt, 1u);
    scriptura_text(line, "\n    the streams' description, 2L bits each: ");
    scriptura_decimal(line, description, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, (unsigned long long)FLOOR_STREAMS * FLOOR_STREAM_BITS, 1u);
    scriptura_text(line, " bits (");
    sim_fraction_print(line, description * 100ull, (unsigned long long)FLOOR_STREAMS * FLOOR_STREAM_BITS, 2u);
    scriptura_text(line, "%)\n");
    sim_check(results, within == FLOOR_STREAMS, "every seeded stream's complexity lies within its degree");
    sim_check(results, rebuilt == FLOOR_STREAMS, "every seeded stream regenerates from its recovered seed");
}

void floor_random(SimResults *results, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated)
{
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        for (unsigned int word = 0u; word < FLOOR_STREAM_WORDS; word += 1u)
        {
            streams[index].word[word] = sim_draw(FLOOR_KEY ^ 0xD1CEull, (index * FLOOR_STREAM_WORDS) + word);
        }
    }
    if (floor_massey(results, streams, FLOOR_STREAMS, lengths, regenerated) == 0)
    {
        return;
    }
    unsigned int least = FLOOR_STREAM_BITS;
    unsigned int maximum = 0u;
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        least = (lengths[index] < least) ? lengths[index] : least;
        maximum = (lengths[index] > maximum) ? lengths[index] : maximum;
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  keyed draws, the same count: complexity from ");
    scriptura_decimal(line, least, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, maximum, 1u);
    scriptura_text(line, " against n/2 = ");
    scriptura_decimal(line, FLOOR_STREAM_BITS / 2u, 1u);
    scriptura_character(line, '\n');
    sim_check(results,
              ((least + FLOOR_RANDOM_RANGE) >= (FLOOR_STREAM_BITS / 2u)) &&
                  (maximum <= ((FLOOR_STREAM_BITS / 2u) + FLOOR_RANDOM_RANGE)),
              "every keyed stream's complexity lies within 16 of n/2");
}

void floor_planes(SimResults *results, const unsigned short *lanes, unsigned long long lanes_count)
{
    // the lane count over a stream's bits is far below 2^32 here
    const unsigned int per_plane = (unsigned int)(lanes_count / FLOOR_STREAM_BITS);
    const unsigned int count = per_plane * FLOOR_PLANES;
    FloorStream *const streams = (FloorStream *)calloc(count, sizeof(FloorStream));
    unsigned int *const lengths = (unsigned int *)malloc(count * sizeof(unsigned int));
    unsigned int *const regenerated = (unsigned int *)malloc(count * sizeof(unsigned int));
    const int ok = (streams != NULL) && (lengths != NULL) && (regenerated != NULL);
    sim_check(results, ok, "plane buffers");
    if (ok)
    {
        for (unsigned int plane = 0u; plane < FLOOR_PLANES; plane += 1u)
        {
            for (unsigned int stream = 0u; stream < per_plane; stream += 1u)
            {
                FloorStream *const into = &streams[(plane * per_plane) + stream];
                for (unsigned int at = 0u; at < FLOOR_STREAM_BITS; at += 1u)
                {
                    if (((lanes[((unsigned long long)stream * FLOOR_STREAM_BITS) + at] >> plane) & 1u) != 0u)
                    {
                        floor_flip(into, at);
                    }
                }
            }
        }
    }
    if (ok && (floor_massey(results, streams, count, lengths, regenerated) != 0))
    {
        ScripturaLine *const line = &results->line;
        scriptura_text(line, "  the camera lattice's bit planes, ");
        scriptura_decimal(line, per_plane, 1u);
        scriptura_text(line, " streams of ");
        scriptura_decimal(line, FLOOR_STREAM_BITS, 1u);
        scriptura_text(line, " consecutive lanes a plane\n    plane  mean complexity / n   streams read as random (at "
                             "least n/2 - 16)\n");
        unsigned long long random_low_planes = 0ull;
        for (unsigned int plane = 0u; plane < FLOOR_PLANES; plane += 1u)
        {
            unsigned long long total = 0ull;
            unsigned long long random = 0ull;
            for (unsigned int stream = 0u; stream < per_plane; stream += 1u)
            {
                const unsigned int length = lengths[(plane * per_plane) + stream];
                total += length;
                random += ((length + FLOOR_RANDOM_RANGE) >= (FLOOR_STREAM_BITS / 2u)) ? 1ull : 0ull;
            }
            scriptura_text(line, "    ");
            scriptura_decimal_columns(line, plane, 5u);
            scriptura_text(line, "  ");
            sim_fraction_print(line, total, (unsigned long long)per_plane * FLOOR_STREAM_BITS, 4u);
            scriptura_text(line, "              ");
            scriptura_decimal(line, random, 1u);
            scriptura_text(line, " of ");
            scriptura_decimal(line, per_plane, 1u);
            scriptura_character(line, '\n');
            random_low_planes += ((plane == 0u) && (random == per_plane)) ? 1ull : 0ull;
        }
        sim_check(results, random_low_planes == 1ull, "the lowest bit plane reads as random on every stream");
    }
    free(regenerated);
    free(lengths);
    free(streams);
}

__global__ void floor_transfer_kernel(unsigned short *lanes, const unsigned int *signal, unsigned long long frames,
                                      unsigned long long voxels, unsigned long long columns, FloorBins truth,
                                      FloorBins level, FloorBins coherent, FloorCoherence *coherence)
{
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= ((frames - 1ull) * voxels))
    {
        return;
    }
    const unsigned long long later = index + voxels;
    // two u16 lanes differ by less than 2^16 in magnitude
    const long long difference = (long long)lanes[later] - (long long)lanes[index];
    // the square of a difference below 2^16 in magnitude is below 2^32
    const unsigned long long square = (unsigned long long)(difference * difference);
    const unsigned long long sum = (unsigned long long)lanes[later] + (unsigned long long)lanes[index];
    const int ok = signal[later] == signal[index];
    atomicAdd(&coherence->pairs, 1ull);
    if (ok)
    {
        atomicAdd(&truth.count[signal[index]], 1ull);
        atomicAdd(&truth.total[signal[index]], square);
    }
    atomicAdd(&level.count[sum], 1ull);
    atomicAdd(&level.total[sum], square);
    if (((index % voxels) % columns) + 1ull >= columns)
    {
        return;
    }
    // the neighbor's difference, like this one, is below 2^16 in magnitude
    const long long beside = (long long)lanes[later + 1ull] - (long long)lanes[index + 1ull];
    const long long across = difference - beside;
    const unsigned long long quad =
        sum + (unsigned long long)lanes[later + 1ull] + (unsigned long long)lanes[index + 1ull];
    // the square of a difference of two differences is below 2^34
    atomicAdd(&coherent.count[quad], 1ull);
    atomicAdd(&coherent.total[quad], (unsigned long long)(across * across));
    // a product of two differences is below 2^32 in magnitude; added modulo 2^64 it keeps its sign in the total
    const unsigned long long product = (unsigned long long)(difference * beside);
    // a square of a difference is non-negative
    const unsigned long long beside_square = (unsigned long long)(beside * beside);
    atomicAdd(&coherence->neighbor_product_all, product);
    atomicAdd(&coherence->square_here_all, square);
    atomicAdd(&coherence->square_beside_all, beside_square);
    if (ok && (signal[later + 1ull] == signal[index + 1ull]))
    {
        atomicAdd(&coherence->both_static, 1ull);
        atomicAdd(&coherence->neighbor_product, product);
        atomicAdd(&coherence->square_here, square);
        atomicAdd(&coherence->square_beside, beside_square);
    }
}
