#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <vector>

#define BLOCK 64ull
#define K_BITS 5ull
#define ESCAPE 24ull

#define GOLDEN_TURN 0x9E3779B97F4A7C15ull

typedef int Integer;

static unsigned int zigzag(long long value)
{
    return (value >= 0) ? (unsigned int)(2 * value) : (unsigned int)(-2 * value - 1);
}

static long long unzigzag(unsigned int value)
{
    return ((value & 1u) == 0u) ? (long long)(value >> 1u) : -(long long)((value + 1u) >> 1u);
}

static long long floor_shift(long long value, unsigned int shift)
{
    return (value >= 0) ? (value >> shift) : -(((-value) + (1ll << shift) - 1) >> shift);
}

static unsigned long long rice_bits(const std::vector<unsigned int> &values)
{
    unsigned long long total = 0ull;
    const unsigned long long count = values.size();
    for (unsigned long long at = 0ull; at < count; at += BLOCK)
    {
        const unsigned long long take = ((count - at) < BLOCK) ? (count - at) : BLOCK;
        unsigned long long sum = 0ull;
        for (unsigned long long i = 0ull; i < take; i += 1ull) sum += values[at + i];
        unsigned int guess = 0u;
        while ((guess < 32u) && (((sum / take) >> guess) != 0ull)) guess += 1u;
        const unsigned int low = (guess > 2u) ? guess - 2u : 0u, high = ((guess + 1u) < 31u) ? guess + 1u : 31u;
        unsigned long long best = ~0ull;
        for (unsigned int k = low; k <= high; k += 1u)
        {
            unsigned long long bits = K_BITS;
            for (unsigned long long i = 0ull; i < take; i += 1ull)
            {
                const unsigned long long q = values[at + i] >> k;
                bits += (q < ESCAPE) ? (q + 1ull + k) : (ESCAPE + 32ull);
            }
            best = (bits < best) ? bits : best;
        }
        total += best;
    }
    return total;
}

static void lift_forward(Integer *line, unsigned long long n, Integer *scratch)
{
    if (n < 2ull) return;
    const unsigned long long lows = (n + 1ull) / 2ull, highs = n / 2ull;
    Integer *const high = scratch;
    for (unsigned long long i = 0ull; i < highs; i += 1ull)
    {
        const long long left = line[2ull * i];
        const long long right = ((2ull * i + 2ull) < n) ? line[2ull * i + 2ull] : left;
        high[i] = (Integer)(line[2ull * i + 1ull] - floor_shift(left + right, 1u));
    }
    Integer *const low = scratch + highs;
    for (unsigned long long i = 0ull; i < lows; i += 1ull)
    {
        const long long before = (i > 0ull) ? high[i - 1ull] : high[0];
        const long long after = (i < highs) ? high[i] : before;
        low[i] = (Integer)(line[2ull * i] + floor_shift(before + after + 2, 2u));
    }
    for (unsigned long long i = 0ull; i < lows; i += 1ull) line[i] = low[i];
    for (unsigned long long i = 0ull; i < highs; i += 1ull) line[lows + i] = high[i];
}

static void lift_axis(Integer *data, const unsigned long long *stride, const unsigned long long *extent, unsigned int axis)
{
    std::vector<Integer> line(extent[axis]), scratch(extent[axis] * 2ull + 2ull);
    unsigned long long other[3], other_stride[3];
    unsigned int at = 0u;
    for (unsigned int a = 0u; a < 4u; a += 1u)
    {
        if (a != axis) { other[at] = extent[a]; other_stride[at] = stride[a]; at += 1u; }
    }
    for (unsigned long long i = 0ull; i < other[0]; i += 1ull)
    for (unsigned long long j = 0ull; j < other[1]; j += 1ull)
    for (unsigned long long k = 0ull; k < other[2]; k += 1ull)
    {
        const unsigned long long base = i * other_stride[0] + j * other_stride[1] + k * other_stride[2];
        for (unsigned long long p = 0ull; p < extent[axis]; p += 1ull) line[p] = data[base + p * stride[axis]];
        lift_forward(line.data(), extent[axis], scratch.data());
        for (unsigned long long p = 0ull; p < extent[axis]; p += 1ull) data[base + p * stride[axis]] = line[p];
    }
}

struct Rectangle { unsigned long long y0, y1, x0, x1; };
struct Place { long long dy, dx; unsigned long long offset; };

static long long radius_of(const Place &place) { return place.dy * place.dy + place.dx * place.dx; }

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: measure_scan <file.stack>\n"); return 1; }
    FILE *const stack = fopen(argv[1], "rb");
    unsigned int header[5];
    if ((stack == NULL) || (fread(header, 4, 5, stack) != 5)) { fprintf(stderr, "bad stack\n"); return 1; }
    const unsigned long long extent[4] = {header[0], header[1], header[2], header[3]};
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long lanes = extent[0] * voxels;
    std::vector<unsigned short> raw(lanes);
    if (fread(raw.data(), 2, lanes, stack) != lanes) { fprintf(stderr, "short read\n"); return 1; }
    fclose(stack);
    const unsigned long long raw_bytes = lanes * 2ull;
    const unsigned long long stride[4] = {voxels, extent[2] * extent[3], extent[3], 1ull};

    std::vector<Integer> data(lanes);
    for (unsigned long long i = 0ull; i < lanes; i += 1ull) data[i] = raw[i];
    std::vector<std::vector<unsigned long long>> box;
    unsigned long long sub[4] = {extent[0], extent[1], extent[2], extent[3]};
    while ((sub[0] > 1ull) || (sub[1] > 1ull) || (sub[2] > 1ull) || (sub[3] > 1ull))
    {
        box.push_back(std::vector<unsigned long long>(sub, sub + 4));
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            if (sub[axis] > 1ull) lift_axis(data.data(), stride, sub, axis);
        }
        for (unsigned int axis = 0u; axis < 4u; axis += 1u) sub[axis] = (sub[axis] + 1ull) / 2ull;
    }
    const size_t floors = box.size();
    box.push_back(std::vector<unsigned long long>(4u, 1ull));
    std::vector<unsigned int> naturals(lanes);
    for (unsigned long long i = 0ull; i < lanes; i += 1ull) naturals[i] = zigzag(data[i]);
    const unsigned long long base_bytes = (rice_bits(naturals) + 7ull) / 8ull;
    printf("  %-44s %12llu bytes, %3llu.%llu%% of raw\n", "the residue as the .iapx writes it", base_bytes,
           100ull * base_bytes / raw_bytes, (1000ull * base_bytes / raw_bytes) % 10ull);
    fflush(stdout);

    std::vector<Rectangle> rectangles;
    for (size_t level = 0u; level < floors; level += 1u)
    {
        const unsigned long long ey = box[level][2], ex = box[level][3], iy = box[level + 1u][2], ix = box[level + 1u][3];
        const Rectangle pieces[3] = {{0ull, iy, ix, ex}, {iy, ey, 0ull, ix}, {iy, ey, ix, ex}};
        for (const Rectangle &piece : pieces)
        {
            if ((piece.y1 > piece.y0) && (piece.x1 > piece.x0)) rectangles.push_back(piece);
        }
    }
    rectangles.push_back({0ull, box[floors][2], 0ull, box[floors][3]});

    const char *const names[3] = {"each floor's rectangles row by row", "shells, each swept by angle (21 September)",
                                  "shells, each in the golden order"};
    for (int order = 0; order < 3; order += 1)
    {
        std::vector<std::vector<unsigned long long>> scan(rectangles.size());
        for (size_t index = 0u; index < rectangles.size(); index += 1u)
        {
            const Rectangle &piece = rectangles[index];
            std::vector<Place> places;
            for (unsigned long long y = piece.y0; y < piece.y1; y += 1ull)
            {
                for (unsigned long long x = piece.x0; x < piece.x1; x += 1ull)
                {
                    places.push_back({(long long)(2ull * y) - (long long)(piece.y0 + piece.y1 - 1ull),
                                      (long long)(2ull * x) - (long long)(piece.x0 + piece.x1 - 1ull), y * extent[3] + x});
                }
            }
            if (order == 1)
            {
                std::sort(places.begin(), places.end(), [](const Place &one, const Place &other)
                {
                    if (radius_of(one) != radius_of(other)) return radius_of(one) < radius_of(other);
                    const int half_one = ((one.dy < 0) || ((one.dy == 0) && (one.dx < 0))) ? 1 : 0;
                    const int half_other = ((other.dy < 0) || ((other.dy == 0) && (other.dx < 0))) ? 1 : 0;
                    if (half_one != half_other) return half_one < half_other;
                    return (one.dx * other.dy - one.dy * other.dx) > 0;
                });
            }
            else if (order == 2)
            {
                std::sort(places.begin(), places.end(), [](const Place &one, const Place &other)
                {
                    if (radius_of(one) != radius_of(other)) return radius_of(one) < radius_of(other);
                    return (one.dy != other.dy) ? (one.dy < other.dy) : (one.dx < other.dx);
                });
                std::vector<Place> golden;
                golden.reserve(places.size());
                for (size_t start = 0u; start < places.size();)
                {
                    size_t end = start;
                    while ((end < places.size()) && (radius_of(places[end]) == radius_of(places[start]))) end += 1u;
                    std::vector<size_t> ranked;
                    for (size_t at = 0u; at < (end - start); at += 1u) ranked.push_back(at);
                    std::sort(ranked.begin(), ranked.end(), [](size_t one, size_t other)
                    {
                        return ((unsigned long long)(one + 1u) * GOLDEN_TURN) < ((unsigned long long)(other + 1u) * GOLDEN_TURN);
                    });
                    for (const size_t at : ranked) golden.push_back(places[start + at]);
                    start = end;
                }
                places.swap(golden);
            }
            for (const Place &place : places) scan[index].push_back(place.offset);
        }
        std::vector<unsigned int> stream;
        stream.reserve(lanes);
        for (unsigned long long plane = 0ull; plane < extent[0] * extent[1]; plane += 1ull)
        {
            for (const std::vector<unsigned long long> &piece : scan)
            {
                for (const unsigned long long offset : piece) stream.push_back(naturals[plane * stride[1] + offset]);
            }
        }
        const unsigned long long bytes = (rice_bits(stream) + 7ull) / 8ull;
        std::vector<Integer> undone(lanes, 0);
        size_t cursor = 0u;
        for (unsigned long long plane = 0ull; plane < extent[0] * extent[1]; plane += 1ull)
        {
            for (const std::vector<unsigned long long> &piece : scan)
            {
                for (const unsigned long long offset : piece)
                {
                    undone[plane * stride[1] + offset] = (Integer)unzigzag(stream[cursor]);
                    cursor += 1u;
                }
            }
        }
        unsigned long long differ = (cursor == lanes) ? 0ull : 1ull;
        for (unsigned long long i = 0ull; i < lanes; i += 1ull) differ += (undone[i] != data[i]) ? 1ull : 0ull;
        printf("  %-44s %12llu bytes, %3llu.%llu%% of raw, %+lld bytes; decoded back: %llu differ\n", names[order], bytes,
               100ull * bytes / raw_bytes, (1000ull * bytes / raw_bytes) % 10ull, (long long)bytes - (long long)base_bytes,
               differ);
        fflush(stdout);
    }
    return 0;
}
