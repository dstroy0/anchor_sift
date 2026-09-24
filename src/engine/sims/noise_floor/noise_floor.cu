// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim_camera.h"

#define FLOOR_KEY 0x464C4F4F52ull

#define FLOOR_STREAM_BITS 512u

#define FLOOR_STREAM_WORDS (FLOOR_STREAM_BITS / 64u)

#define FLOOR_STREAMS 4096u

#define FLOOR_DEGREE_LEAST 8u

#define FLOOR_DEGREE_MOST 64u

#define FLOOR_RANDOM_REACH 16u

#define FLOOR_PLANES 16u

#define FLOOR_THREADS 128ull

#define FLOOR_LEVELS 262144ull

#define FLOOR_ROUTES 3u

#define FLOOR_FOUNDERS 8u

#define FLOOR_SIGMAS_SQUARED 25ll

#define FLOOR_SLOPE_PARTS 50ull

#define FLOOR_INTERCEPT_REACH 6ll

typedef struct
{
    unsigned long long word[FLOOR_STREAM_WORDS];
} FloorStream;

typedef struct
{
    unsigned long long *count;
    unsigned long long *total;
} FloorBins;

typedef struct
{
    unsigned long long pairs;
    unsigned long long both_static;
    unsigned long long neighbour_product;
    unsigned long long square_here;
    unsigned long long square_beside;
    unsigned long long neighbour_product_all;
    unsigned long long square_here_all;
    unsigned long long square_beside_all;
} FloorCoherence;

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
    unsigned int held = 1u;
    for (unsigned int at = length; at < FLOOR_STREAM_BITS; at += 1u)
    {
        unsigned int next = 0u;
        for (unsigned int tap = 1u; tap <= length; tap += 1u)
        {
            next ^= floor_bit(&connection, tap) & floor_bit(bits, at - tap);
        }
        held &= (next == floor_bit(bits, at)) ? 1u : 0u;
    }
    lengths[index] = length;
    regenerated[index] = held;
}

static int floor_massey(SimTally *tally, const FloorStream *streams, unsigned int count, unsigned int *lengths,
                        unsigned int *regenerated)
{
    FloorStream *device_streams = NULL;
    unsigned int *device_lengths = NULL;
    unsigned int *device_regenerated = NULL;
    int good = sim_took(tally, cudaMalloc((void **)&device_streams, count * sizeof(FloorStream)), "massey: streams");
    good = good && sim_took(tally, cudaMalloc((void **)&device_lengths, count * sizeof(unsigned int)), "massey: lengths");
    good = good && sim_took(tally, cudaMalloc((void **)&device_regenerated, count * sizeof(unsigned int)),
                            "massey: regenerated");
    good = good && sim_took(tally, cudaMemcpy(device_streams, streams, count * sizeof(FloorStream), cudaMemcpyHostToDevice),
                            "massey: upload");
    if (good)
    {
        // the stream count is far below 2^31
        const unsigned int blocks = (unsigned int)sim_launch_blocks(count, FLOOR_THREADS);
        floor_massey_kernel<<<blocks, (unsigned int)FLOOR_THREADS>>>(device_streams, count, device_lengths,
                                                                    device_regenerated);
        good = sim_took(tally, cudaGetLastError(), "massey: launch");
        good = good && sim_took(tally, cudaDeviceSynchronize(), "massey: run");
    }
    good = good && sim_took(tally, cudaMemcpy(lengths, device_lengths, count * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                            "massey: lengths read");
    good = good && sim_took(tally, cudaMemcpy(regenerated, device_regenerated, count * sizeof(unsigned int),
                                              cudaMemcpyDeviceToHost), "massey: regenerated read");
    cudaFree(device_regenerated);
    cudaFree(device_lengths);
    cudaFree(device_streams);
    return good;
}

static void floor_seeded_stream(FloorStream *stream, unsigned int degree, unsigned long long key, unsigned long long index)
{
    memset(stream, 0, sizeof(*stream));
    const unsigned long long reach = (degree == 64u) ? 0xFFFFFFFFFFFFFFFFull : ((1ull << degree) - 1ull);
    const unsigned long long taps = (sim_draw(key, (index * 4ull) + 0ull) & reach) | (1ull << (degree - 1u));
    unsigned long long state = sim_draw(key, (index * 4ull) + 1ull) & reach;
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

static void floor_mock(SimTally *tally, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated)
{
    unsigned int degree[FLOOR_STREAMS];
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        // the draw is below the degree span, far under 2^32
        degree[index] = FLOOR_DEGREE_LEAST + (unsigned int)sim_draw_below(FLOOR_KEY, index,
                                                                          (FLOOR_DEGREE_MOST - FLOOR_DEGREE_LEAST) + 1u);
        floor_seeded_stream(&streams[index], degree[index], FLOOR_KEY ^ 0x5EEDull, index);
    }
    if (floor_massey(tally, streams, FLOOR_STREAMS, lengths, regenerated) == 0)
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
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  the Kolmogorov mock: ");
    scriptura_decimal(line, FLOOR_STREAMS, 1u);
    scriptura_text(line, " streams of ");
    scriptura_decimal(line, FLOOR_STREAM_BITS, 1u);
    scriptura_text(line, " bits, each from a linear generator of degree ");
    scriptura_decimal(line, FLOOR_DEGREE_LEAST, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, FLOOR_DEGREE_MOST, 1u);
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
    sim_check(tally, within == FLOOR_STREAMS, "every seeded stream's complexity lies within its degree");
    sim_check(tally, rebuilt == FLOOR_STREAMS, "every seeded stream regenerates from its recovered seed");
}

static void floor_random(SimTally *tally, FloorStream *streams, unsigned int *lengths, unsigned int *regenerated)
{
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        for (unsigned int word = 0u; word < FLOOR_STREAM_WORDS; word += 1u)
        {
            streams[index].word[word] = sim_draw(FLOOR_KEY ^ 0xD1CEull, (index * FLOOR_STREAM_WORDS) + word);
        }
    }
    if (floor_massey(tally, streams, FLOOR_STREAMS, lengths, regenerated) == 0)
    {
        return;
    }
    unsigned int least = FLOOR_STREAM_BITS;
    unsigned int most = 0u;
    for (unsigned int index = 0u; index < FLOOR_STREAMS; index += 1u)
    {
        least = (lengths[index] < least) ? lengths[index] : least;
        most = (lengths[index] > most) ? lengths[index] : most;
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  keyed draws, the same count: complexity from ");
    scriptura_decimal(line, least, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, most, 1u);
    scriptura_text(line, " against n/2 = ");
    scriptura_decimal(line, FLOOR_STREAM_BITS / 2u, 1u);
    scriptura_character(line, '\n');
    sim_check(tally, ((least + FLOOR_RANDOM_REACH) >= (FLOOR_STREAM_BITS / 2u))
                         && (most <= ((FLOOR_STREAM_BITS / 2u) + FLOOR_RANDOM_REACH)),
              "every keyed stream's complexity lies within 16 of n/2");
}

static void floor_planes(SimTally *tally, const unsigned short *lanes, unsigned long long lanes_count)
{
    // the lane count over a stream's bits is far below 2^32 here
    const unsigned int per_plane = (unsigned int)(lanes_count / FLOOR_STREAM_BITS);
    const unsigned int count = per_plane * FLOOR_PLANES;
    FloorStream *const streams = (FloorStream *)calloc(count, sizeof(FloorStream));
    unsigned int *const lengths = (unsigned int *)malloc(count * sizeof(unsigned int));
    unsigned int *const regenerated = (unsigned int *)malloc(count * sizeof(unsigned int));
    const int good = (streams != NULL) && (lengths != NULL) && (regenerated != NULL);
    sim_check(tally, good, "plane buffers");
    if (good)
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
    if (good && (floor_massey(tally, streams, count, lengths, regenerated) != 0))
    {
        ScripturaLine *const line = &tally->line;
        scriptura_text(line, "  the camera lattice's bit planes, ");
        scriptura_decimal(line, per_plane, 1u);
        scriptura_text(line, " streams of ");
        scriptura_decimal(line, FLOOR_STREAM_BITS, 1u);
        scriptura_text(line, " consecutive lanes a plane\n    plane  mean complexity / n   streams read as random (within 16 of n/2)\n");
        unsigned long long random_low_planes = 0ull;
        for (unsigned int plane = 0u; plane < FLOOR_PLANES; plane += 1u)
        {
            unsigned long long total = 0ull;
            unsigned long long random = 0ull;
            for (unsigned int stream = 0u; stream < per_plane; stream += 1u)
            {
                const unsigned int length = lengths[(plane * per_plane) + stream];
                total += length;
                random += ((length + FLOOR_RANDOM_REACH) >= (FLOOR_STREAM_BITS / 2u)) ? 1ull : 0ull;
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
        sim_check(tally, random_low_planes == 1ull, "the lowest bit plane reads as random on every stream");
    }
    free(regenerated);
    free(lengths);
    free(streams);
}

static __global__ void floor_transfer_kernel(unsigned short *lanes, const unsigned int *signal, unsigned long long frames,
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
    const int held = signal[later] == signal[index];
    atomicAdd(&coherence->pairs, 1ull);
    if (held)
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
    // the neighbour's difference, like this one, is below 2^16 in magnitude
    const long long beside = (long long)lanes[later + 1ull] - (long long)lanes[index + 1ull];
    const long long across = difference - beside;
    const unsigned long long quad = sum + (unsigned long long)lanes[later + 1ull] + (unsigned long long)lanes[index + 1ull];
    // the square of a difference of two differences is below 2^34
    atomicAdd(&coherent.count[quad], 1ull);
    atomicAdd(&coherent.total[quad], (unsigned long long)(across * across));
    // a product of two differences is below 2^32 in magnitude; added modulo 2^64 it keeps its sign in the total
    const unsigned long long product = (unsigned long long)(difference * beside);
    // a square of a difference is non-negative
    const unsigned long long beside_square = (unsigned long long)(beside * beside);
    atomicAdd(&coherence->neighbour_product_all, product);
    atomicAdd(&coherence->square_here_all, square);
    atomicAdd(&coherence->square_beside_all, beside_square);
    if (held && (signal[later + 1ull] == signal[index + 1ull]))
    {
        atomicAdd(&coherence->both_static, 1ull);
        atomicAdd(&coherence->neighbour_product, product);
        atomicAdd(&coherence->square_here, square);
        atomicAdd(&coherence->square_beside, beside_square);
    }
}

typedef struct
{
    AnchorExactInteger slope;
    AnchorExactInteger intercept;
    AnchorExactInteger denominator;
    unsigned long long samples;
} FloorLine;

static int floor_fit(const unsigned long long *count, const unsigned long long *total, FloorLine *fit)
{
    AnchorExactInteger samples;
    AnchorExactInteger along;
    AnchorExactInteger along_square;
    AnchorExactInteger measured;
    AnchorExactInteger cross;
    anchor_exact_zero(&samples);
    anchor_exact_zero(&along);
    anchor_exact_zero(&along_square);
    anchor_exact_zero(&measured);
    anchor_exact_zero(&cross);
    fit->samples = 0ull;
    int good = 1;
    for (unsigned long long level = 0ull; good && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        fit->samples += count[level];
        AnchorExactInteger number;
        AnchorExactInteger place;
        AnchorExactInteger term;
        sim_exact_whole(&number, count[level]);
        sim_exact_whole(&place, level);
        good = good && sim_exact_sum(&samples, &number, &samples);
        good = good && sim_exact_product(&number, &place, &term) && sim_exact_sum(&along, &term, &along);
        good = good && sim_exact_product(&term, &place, &term) && sim_exact_sum(&along_square, &term, &along_square);
        sim_exact_whole(&number, total[level]);
        good = good && sim_exact_sum(&measured, &number, &measured);
        good = good && sim_exact_product(&number, &place, &term) && sim_exact_sum(&cross, &term, &cross);
    }
    AnchorExactInteger left;
    AnchorExactInteger right;
    good = good && sim_exact_product(&samples, &along_square, &left) && sim_exact_product(&along, &along, &right)
        && sim_exact_less(&left, &right, &fit->denominator);
    good = good && sim_exact_product(&samples, &cross, &left) && sim_exact_product(&along, &measured, &right)
        && sim_exact_less(&left, &right, &fit->slope);
    good = good && sim_exact_product(&measured, &along_square, &left) && sim_exact_product(&along, &cross, &right)
        && sim_exact_less(&left, &right, &fit->intercept);
    return good && (fit->denominator.sign > 0);
}

static void floor_print_fit(ScripturaLine *line, const char *name, const FloorLine *fit)
{
    scriptura_text(line, name);
    scriptura_text(line, "slope ");
    sim_ratio_print(line, &fit->slope, &fit->denominator, 4u);
    scriptura_text(line, ", intercept ");
    sim_ratio_print(line, &fit->intercept, &fit->denominator, 3u);
    scriptura_text(line, ", over ");
    scriptura_decimal(line, fit->samples, 1u);
    scriptura_text(line, " pairs\n");
}

static int floor_bins_open(SimTally *tally, FloorBins *bins)
{
    bins->count = NULL;
    bins->total = NULL;
    int good = sim_took(tally, cudaMalloc((void **)&bins->count, FLOOR_LEVELS * sizeof(unsigned long long)), "bins");
    good = good && sim_took(tally, cudaMalloc((void **)&bins->total, FLOOR_LEVELS * sizeof(unsigned long long)), "bins");
    good = good && sim_took(tally, cudaMemset(bins->count, 0, FLOOR_LEVELS * sizeof(unsigned long long)), "bins zero");
    good = good && sim_took(tally, cudaMemset(bins->total, 0, FLOOR_LEVELS * sizeof(unsigned long long)), "bins zero");
    return good;
}

static int floor_bins_fit(SimTally *tally, const FloorBins *bins, unsigned long long *count, unsigned long long *total,
                          FloorLine *fit)
{
    int good = sim_took(tally, cudaMemcpy(count, bins->count, FLOOR_LEVELS * sizeof(unsigned long long),
                                          cudaMemcpyDeviceToHost), "bins read");
    good = good && sim_took(tally, cudaMemcpy(total, bins->total, FLOOR_LEVELS * sizeof(unsigned long long),
                                              cudaMemcpyDeviceToHost), "bins read");
    return good && floor_fit(count, total, fit);
}

static void floor_bins_close(FloorBins *bins)
{
    cudaFree(bins->total);
    cudaFree(bins->count);
}

static void floor_print_correlation(ScripturaLine *line, const char *name, unsigned long long product,
                                    unsigned long long here)
{
    // the product total was accumulated modulo 2^64 and its magnitude is below 2^63
    const long long signed_product = (long long)product;
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    sim_exact_signed(&top, signed_product);
    sim_exact_whole(&bottom, here);
    scriptura_text(line, name);
    scriptura_text(line, "sum d d' ");
    scriptura_signed(line, signed_product);
    scriptura_text(line, ", over sum d^2 ");
    scriptura_decimal(line, here, 1u);
    scriptura_text(line, ": ");
    sim_ratio_print(line, &top, &bottom, 4u);
    scriptura_character(line, '\n');
}

static void floor_transfer(SimTally *tally, const SimScene *scene, const SimCamera *camera, unsigned short *device_lanes,
                           unsigned int *device_signal)
{
    const unsigned long long voxels = sim_scene_voxels(scene);
    FloorBins bins[FLOOR_ROUTES];
    FloorCoherence *device_coherence = NULL;
    int good = 1;
    for (unsigned int route = 0u; route < FLOOR_ROUTES; route += 1u)
    {
        good = floor_bins_open(tally, &bins[route]) && good;
    }
    good = good && sim_took(tally, cudaMalloc((void **)&device_coherence, sizeof(FloorCoherence)), "coherence");
    good = good && sim_took(tally, cudaMemset(device_coherence, 0, sizeof(FloorCoherence)), "coherence zero");
    if (good)
    {
        const unsigned long long blocks = sim_launch_blocks((scene->frames - 1ull) * voxels, SIM_RENDER_THREADS);
        // the grid is below 2^31 blocks here
        floor_transfer_kernel<<<(unsigned int)blocks, (unsigned int)SIM_RENDER_THREADS>>>(
            device_lanes, device_signal, scene->frames, voxels, scene->extent[2], bins[0], bins[1], bins[2],
            device_coherence);
        good = sim_took(tally, cudaGetLastError(), "transfer: launch");
        good = good && sim_took(tally, cudaDeviceSynchronize(), "transfer: run");
    }
    unsigned long long *const count = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    unsigned long long *const total = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    good = good && (count != NULL) && (total != NULL);
    FloorLine fit[FLOOR_ROUTES];
    for (unsigned int route = 0u; good && (route < FLOOR_ROUTES); route += 1u)
    {
        good = floor_bins_fit(tally, &bins[route], count, total, &fit[route]);
    }
    FloorCoherence coherence;
    good = good && sim_took(tally, cudaMemcpy(&coherence, device_coherence, sizeof(FloorCoherence), cudaMemcpyDeviceToHost),
                            "coherence read");
    sim_check(tally, good, "the transfer curve's three routes were measured");
    if (good)
    {
        ScripturaLine *const line = &tally->line;
        scriptura_text(line, "  the photon transfer curve, frame differences d = I(t+1) - I(t) over ");
        scriptura_decimal(line, coherence.pairs, 1u);
        scriptura_text(line, " pairs; planted gain ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_text(line, ", read variance ");
        scriptura_decimal(line, camera->read_square, 1u);
        scriptura_character(line, '\n');
        scriptura_text(line, "    truth, motion removed exactly (signal unchanged), d^2 on S: law slope 2 g^2 = ");
        scriptura_decimal(line, 2ull * camera->gain * camera->gain, 1u);
        scriptura_text(line, ", intercept 2 r^2 = ");
        scriptura_decimal(line, 2ull * camera->read_square, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[0]);
        scriptura_text(line, "    data only, every pair, d^2 on I(t) + I(t+1): law slope g = ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[1]);
        scriptura_text(line, "    data only, neighbour coherence, (d - d')^2 on the four lanes' sum: law slope g = ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[2]);

        AnchorExactInteger law;
        AnchorExactInteger scaled;
        AnchorExactInteger apart;
        sim_exact_whole(&law, 2ull * camera->gain * camera->gain);
        good = sim_exact_product(&law, &fit[0].denominator, &scaled) && sim_exact_less(&fit[0].slope, &scaled, &apart);
        apart.sign = (apart.sign < 0) ? 1 : apart.sign;
        AnchorExactInteger bound;
        good = good && sim_exact_scaled(&apart, FLOOR_SLOPE_PARTS, &apart) && (anchor_exact_compare(&apart, &scaled) <= 0);
        sim_check(tally, good, "the truth route's slope lies within 2% of 2 g^2");
        sim_exact_whole(&law, 2ull * camera->read_square);
        good = sim_exact_product(&law, &fit[0].denominator, &scaled) && sim_exact_less(&fit[0].intercept, &scaled, &apart);
        apart.sign = (apart.sign < 0) ? 1 : apart.sign;
        sim_exact_signed(&law, FLOOR_INTERCEPT_REACH);
        good = good && sim_exact_product(&law, &fit[0].denominator, &bound) && (anchor_exact_compare(&apart, &bound) <= 0);
        sim_check(tally, good, "the truth route's intercept lies within 6 of 2 r^2");

        scriptura_text(line, "  the neighbour coherence of d (x against x + 1)\n");
        floor_print_correlation(line, "    truth-static pairs: ", coherence.neighbour_product, coherence.square_here);
        floor_print_correlation(line, "    every pair:         ", coherence.neighbour_product_all,
                                coherence.square_here_all);
        // the product total's magnitude is below 2^63, so it is read back signed
        const long long product = (long long)coherence.neighbour_product;
        AnchorExactInteger left;
        AnchorExactInteger right;
        AnchorExactInteger term;
        sim_exact_signed(&term, product);
        good = sim_exact_product(&term, &term, &left);
        sim_exact_whole(&term, coherence.square_here);
        sim_exact_whole(&right, coherence.square_beside);
        good = good && sim_exact_product(&term, &right, &right);
        // twenty-five, the square of five sigma, is a small positive constant
        good = good && sim_exact_scaled(&right, (unsigned long long)FLOOR_SIGMAS_SQUARED, &right);
        sim_exact_whole(&term, coherence.both_static);
        good = good && sim_exact_product(&left, &term, &left) && (anchor_exact_compare(&left, &right) <= 0);
        sim_check(tally, good, "static pairs' neighbour correlation lies within 5 sigma of 0");
    }
    free(total);
    free(count);
    cudaFree(device_coherence);
    for (unsigned int route = 0u; route < FLOOR_ROUTES; route += 1u)
    {
        floor_bins_close(&bins[route]);
    }
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    scriptura_text(&tally.line, "  the noise floor, measured on the camera law with the answer known\n");

    FloorStream *const streams = (FloorStream *)malloc(FLOOR_STREAMS * sizeof(FloorStream));
    unsigned int *const lengths = (unsigned int *)malloc(FLOOR_STREAMS * sizeof(unsigned int));
    unsigned int *const regenerated = (unsigned int *)malloc(FLOOR_STREAMS * sizeof(unsigned int));
    int good = (streams != NULL) && (lengths != NULL) && (regenerated != NULL);
    sim_check(&tally, good, "stream buffers");
    // the streams on the device, and the camera-law scene below: 24 frames of 20 x 96 x 96 lanes
    good = good && sim_job_submit(&tally, "noise_floor", 0, NULL,
                                  (FLOOR_STREAMS * (sizeof(FloorStream) + (2u * sizeof(unsigned int))))
                                      + (24ull * 20ull * 96ull * 96ull * sizeof(unsigned short)));
    if (good)
    {
        floor_mock(&tally, streams, lengths, regenerated);
        floor_random(&tally, streams, lengths, regenerated);
    }
    sim_flush(&tally);

    SimBody body[FLOOR_FOUNDERS];
    memset(body, 0, sizeof(body));
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = 24ull;
    scene.extent[0] = 20ull;
    scene.extent[1] = 96ull;
    scene.extent[2] = 96ull;
    scene.background = 40ull;
    scene.ramp = 2ull;
    scene.bodies = FLOOR_FOUNDERS;
    scene.body = body;
    SimDraws draws;
    draws.key = FLOOR_KEY;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, body, FLOOR_FOUNDERS);
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = FLOOR_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_reach = 8ull;
    camera.shot = 1ull;

    const unsigned long long lanes_count = scene.frames * sim_scene_voxels(&scene);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)lanes_count * sizeof(unsigned short));
    unsigned short *device_lanes = NULL;
    unsigned int *device_signal = NULL;
    unsigned long long clipped = 0ull;
    good = good && (lanes != NULL);
    good = good && sim_took(&tally, cudaMalloc((void **)&device_lanes, lanes_count * sizeof(unsigned short)), "lanes");
    good = good && sim_took(&tally, cudaMalloc((void **)&device_signal, lanes_count * sizeof(unsigned int)), "signal");
    good = good && sim_render(&tally, &scene, &camera, device_lanes, device_signal, NULL, &clipped);
    good = good && sim_took(&tally, cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short),
                                               cudaMemcpyDeviceToHost), "lanes read");
    sim_check(&tally, good && (clipped == 0ull), "the lattice rendered with no lane clipped");
    if (good)
    {
        floor_planes(&tally, lanes, lanes_count);
        sim_flush(&tally);
        floor_transfer(&tally, &scene, &camera, device_lanes, device_signal);
    }

    cudaFree(device_signal);
    cudaFree(device_lanes);
    free(lanes);
    free(regenerated);
    free(lengths);
    free(streams);
    return sim_close(&tally, "noise floor");
}
