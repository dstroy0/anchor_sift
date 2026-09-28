// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim_camera.h"

#include "noise_detector.h"

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

// the static pairs' neighbour correlation is held within 5 / sqrt(N) of 0, this squared times N. A frame difference
// shares a frame with the next, so over 23 frame pairs a voxel the product sum spreads by sqrt(1.478) of an
// independent one's, and the reach is about 4.1 standard errors
#define FLOOR_CORRELATION_REACH_SQUARED 25ll

// the truth route's slope and intercept are held within 5 standard errors of the law, this squared, and the intercept
// at least 5 above 0
#define FLOOR_ERROR_REACH_SQUARED 25ull

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
        scriptura_text(line, " consecutive lanes a plane\n    plane  mean complexity / n   streams read as random (at least n/2 - 16)\n");
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

// the line over the level through the noise detector's fit (build plan item 38), each level a place and its squares a
// total, at scale 1 on both
static int floor_fit(const unsigned long long *count, const unsigned long long *total, FloorLine *fit)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseLineSums sums;
    noise_line_sums_zero(&sums);
    fit->samples = 0ull;
    int good = 1;
    for (unsigned long long level = 0ull; good && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        fit->samples += count[level];
        AnchorExactInteger measured;
        sim_exact_whole(&measured, total[level]);
        good = noise_line_sums_add(&sums, count[level], level, &measured, &error) == 0L;
    }
    NoiseLine line;
    good = good && (noise_line_fit(&sums, 1ull, 1ull, &line, &error) == 0L);
    if (good != 0)
    {
        fit->slope = line.slope;
        fit->intercept = line.intercept;
        fit->denominator = line.denominator;
    }
    return good;
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

// The truth route's spreads, D^2 times a bound on its intercept's and its slope's variance (Derived). A pair whose
// signal holds at S reads y = d^2, d = X' - X, X = offset + pattern + g Poisson(S) + read, the read
// Binomial(4 r^2, 1/2) - 2 r^2 with kappa4 = -r^2 / 2. The pattern cancels in d, sigma^2 = g^2 S + r^2,
// k4 = kappa4(X) = g^4 S - r^2 / 2, kappa4(d) = 2 k4, and var(y) = v = 8 sigma^4 + 2 k4. Two pairs sharing a frame
// have cov(y, y') = c = mu4 - sigma^4 = 2 sigma^4 + k4 >= 0, and pairs sharing none are independent. The bound
// assumes pairs correlate only within one voxel's run of held pairs, and a run holds one level: each run carries one
// weight, and a run of m pairs has variance m v + 2 (m - 1) c = m (v + 2 c) - 2 c <= m u, with
// u = v + 2 c = 12 sigma^4 + 4 k4 = 12 (g^2 S + r^2)^2 + 4 g^4 S - 2 r^2. With N, A and B the counts' sums of 1, S
// and S^2 and D = N B - A^2, the fit's intercept is a D = sum y (B - A S) and its slope b D = sum y (N S - A), and
// Va = sum_S count(S) (B - A S)^2 u(S) >= D^2 var(a), Vb = sum_S count(S) (N S - A)^2 u(S) >= D^2 var(b).
static int floor_spreads(const unsigned long long *count, const SimCamera *camera, AnchorExactInteger *intercept_spread,
                         AnchorExactInteger *slope_spread)
{
    AnchorExactInteger samples;
    AnchorExactInteger along;
    AnchorExactInteger along_square;
    anchor_exact_zero(&samples);
    anchor_exact_zero(&along);
    anchor_exact_zero(&along_square);
    anchor_exact_zero(intercept_spread);
    anchor_exact_zero(slope_spread);
    int good = 1;
    for (unsigned long long level = 0ull; good && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        AnchorExactInteger number;
        AnchorExactInteger weighted;
        AnchorExactInteger squared;
        sim_exact_whole(&number, count[level]);
        good = sim_exact_sum(&samples, &number, &samples) && sim_exact_scaled(&number, level, &weighted)
            && sim_exact_sum(&along, &weighted, &along) && sim_exact_scaled(&weighted, level, &squared)
            && sim_exact_sum(&along_square, &squared, &along_square);
    }
    AnchorExactInteger gain;
    AnchorExactInteger gain_square;
    AnchorExactInteger gain_fourth;
    AnchorExactInteger read;
    AnchorExactInteger read_twice;
    sim_exact_whole(&gain, camera->gain);
    sim_exact_whole(&read, camera->read_square);
    good = good && sim_exact_product(&gain, &gain, &gain_square)
        && sim_exact_product(&gain_square, &gain_square, &gain_fourth) && sim_exact_scaled(&read, 2ull, &read_twice);
    for (unsigned long long level = 0ull; good && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        // u(S) = 12 (g^2 S + r^2)^2 + 4 g^4 S - 2 r^2, non-negative for a whole r^2
        AnchorExactInteger shot;
        AnchorExactInteger variance;
        AnchorExactInteger fourth;
        AnchorExactInteger fourth_twelve;
        AnchorExactInteger shot_fourth;
        AnchorExactInteger spread;
        AnchorExactInteger unit;
        // a level is below 2^18, so 4 S fits a word
        good = sim_exact_scaled(&gain_square, level, &shot) && sim_exact_sum(&shot, &read, &variance)
            && sim_exact_product(&variance, &variance, &fourth) && sim_exact_scaled(&fourth, 12ull, &fourth_twelve)
            && sim_exact_scaled(&gain_fourth, 4ull * level, &shot_fourth)
            && sim_exact_sum(&fourth_twelve, &shot_fourth, &spread) && sim_exact_less(&spread, &read_twice, &unit);
        // the intercept's weight B - A S and the slope's N S - A, each squared, times count(S) u(S)
        AnchorExactInteger product;
        AnchorExactInteger weight;
        AnchorExactInteger weight_square;
        AnchorExactInteger counted;
        AnchorExactInteger term;
        good = good && sim_exact_scaled(&along, level, &product) && sim_exact_less(&along_square, &product, &weight)
            && sim_exact_product(&weight, &weight, &weight_square) && sim_exact_scaled(&weight_square, count[level], &counted)
            && sim_exact_product(&counted, &unit, &term) && sim_exact_sum(intercept_spread, &term, intercept_spread);
        good = good && sim_exact_scaled(&samples, level, &product) && sim_exact_less(&product, &along, &weight)
            && sim_exact_product(&weight, &weight, &weight_square) && sim_exact_scaled(&weight_square, count[level], &counted)
            && sim_exact_product(&counted, &unit, &term) && sim_exact_sum(slope_spread, &term, slope_spread);
    }
    return good;
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
    // the truth route's counts, kept for its spreads after the other routes reuse count
    unsigned long long *const truth_count = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    good = good && (count != NULL) && (total != NULL) && (truth_count != NULL);
    FloorLine fit[FLOOR_ROUTES];
    for (unsigned int route = 0u; good && (route < FLOOR_ROUTES); route += 1u)
    {
        good = floor_bins_fit(tally, &bins[route], count, total, &fit[route]);
        if (good && (route == 0u))
        {
            memcpy(truth_count, count, FLOOR_LEVELS * sizeof(unsigned long long));
        }
    }
    FloorCoherence coherence;
    good = good && sim_took(tally, cudaMemcpy(&coherence, device_coherence, sizeof(FloorCoherence), cudaMemcpyDeviceToHost),
                            "coherence read");
    sim_check(tally, good, "the transfer curve's three routes were measured");
    // the truth route's D = N B - A^2, checked positive before any ratio over it
    const int spanned = good && (fit[0].denominator.sign > 0);
    sim_check(tally, spanned, "the truth route's levels span two: D = N B - A^2 > 0");
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

        // the truth route's standard errors squared, SE^2 = V / D^2, from floor_spreads' bounds (Derived); every check
        // squares both sides against 25 V, exact
        AnchorExactInteger intercept_spread;
        AnchorExactInteger slope_spread;
        AnchorExactInteger denominator_square;
        const int spread = spanned && floor_spreads(truth_count, camera, &intercept_spread, &slope_spread)
                        && sim_exact_product(&fit[0].denominator, &fit[0].denominator, &denominator_square);
        sim_check(tally, spread, "the truth route's spreads were formed");
        if (spread != 0)
        {
            scriptura_text(line, "      SE^2 bounded above: intercept ");
            sim_ratio_print(line, &intercept_spread, &denominator_square, 8u);
            scriptura_text(line, ", slope ");
            sim_ratio_print(line, &slope_spread, &denominator_square, 8u);
            scriptura_character(line, '\n');
        }
        AnchorExactInteger law;
        AnchorExactInteger scaled;
        AnchorExactInteger apart;
        AnchorExactInteger apart_square;
        AnchorExactInteger bound;
        sim_exact_whole(&law, 2ull * camera->gain * camera->gain);
        good = spread && sim_exact_product(&law, &fit[0].denominator, &scaled)
            && sim_exact_less(&fit[0].slope, &scaled, &apart) && sim_exact_product(&apart, &apart, &apart_square)
            && sim_exact_scaled(&slope_spread, FLOOR_ERROR_REACH_SQUARED, &bound)
            && (anchor_exact_compare(&apart_square, &bound) <= 0);
        sim_check(tally, good, "the truth route's slope lies within 5 SE_b of 2 g^2");
        sim_exact_whole(&law, 2ull * camera->read_square);
        good = spread && sim_exact_product(&law, &fit[0].denominator, &scaled)
            && sim_exact_less(&fit[0].intercept, &scaled, &apart) && sim_exact_product(&apart, &apart, &apart_square)
            && sim_exact_scaled(&intercept_spread, FLOOR_ERROR_REACH_SQUARED, &bound)
            && (anchor_exact_compare(&apart_square, &bound) <= 0);
        sim_check(tally, good, "the truth route's intercept lies within 5 SE_a of 2 r^2");
        good = spread && (fit[0].intercept.sign > 0)
            && sim_exact_product(&fit[0].intercept, &fit[0].intercept, &apart_square)
            && sim_exact_scaled(&intercept_spread, FLOOR_ERROR_REACH_SQUARED, &bound)
            && (anchor_exact_compare(&apart_square, &bound) >= 0);
        sim_check(tally, good, "the truth route's intercept stands at least 5 SE_a above 0: the read noise is there");

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
        // twenty-five, the reach squared, is a small positive constant
        good = good && sim_exact_scaled(&right, (unsigned long long)FLOOR_CORRELATION_REACH_SQUARED, &right);
        sim_exact_whole(&term, coherence.both_static);
        good = good && sim_exact_product(&left, &term, &left) && (anchor_exact_compare(&left, &right) <= 0);
        sim_check(tally, good, "static pairs' neighbour correlation lies within 5 / sqrt(N) of 0, about 4.1 sigma");
    }
    free(truth_count);
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
