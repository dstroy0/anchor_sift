// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_rings.cu: rings, turns and spirals
#include "pi_plane_internal.h"

// ring k holds floor(pi 2^k) bits, floor(pi 2^(k + 1)) = 2 floor(pi 2^k) + pi's bit k + 1; the rings that fit most
std::vector<unsigned long long> plane_ring_sizes(const std::vector<unsigned char> &bits, unsigned long long maximum)
{
    std::vector<unsigned long long> sizes;
    unsigned long long size = 3ull;
    unsigned long long total = 0ull;
    for (size_t level = 0u; (level < bits.size()) && (total + size <= maximum); level += 1u)
    {
        sizes.push_back(size);
        total += size;
        size = (2ull * size) + (unsigned long long)bits[level];
    }
    return sizes;
}

unsigned long long plane_ring_total(const std::vector<unsigned long long> &sizes)
{
    unsigned long long total = 0ull;
    for (const unsigned long long size : sizes)
    {
        total += size;
    }
    return total;
}

// each bit against its parent, the bit at the same angle one ring in, place floor(j c_(k - 1) / c_k): how many agree,
// and the longest chain of equal bits running outward
PlaneRingMeasurement plane_ring_read(const std::vector<unsigned long long> &sizes, const unsigned char *bits)
{
    PlaneRingMeasurement measurement = {0ull, 0ull, 1ull, 0ull, 0ull};
    std::vector<unsigned long long> previous_run;
    unsigned long long start = 0ull;
    unsigned long long previous_start = 0ull;
    for (size_t ring = 0u; ring < sizes.size(); ring += 1u)
    {
        std::vector<unsigned long long> run((size_t)sizes[ring], 1ull);
        for (unsigned long long place = 0ull; (ring > 0u) && (place < sizes[ring]); place += 1ull)
        {
            const unsigned long long parent = (place * sizes[ring - 1u]) / sizes[ring];
            const int same = bits[start + place] == bits[previous_start + parent];
            measurement.pairs += 1ull;
            measurement.agree += same ? 1ull : 0ull;
            run[(size_t)place] = same ? (previous_run[(size_t)parent] + 1ull) : 1ull;
            if (run[(size_t)place] > measurement.run)
            {
                measurement.run = run[(size_t)place];
                measurement.run_ring = ring;
                measurement.run_place = place;
            }
        }
        previous_run.swap(run);
        previous_start = start;
        start += sizes[ring];
    }
    return measurement;
}

// the rings unrolled, ring k row k, bit j across [j W / c_k, (j + 1) W / c_k), each pixel the share of ones on it
int plane_ring_unrolled(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                        const std::string &path)
{
    const unsigned long long width = PLANE_RING_UNROLLED_WIDTH;
    const unsigned long long height = sizes.size() * PLANE_RING_ROW;
    std::vector<unsigned char> pixels((size_t)(width * height), (unsigned char)PLANE_EMPTY_SHADE);
    unsigned long long start = 0ull;
    for (size_t ring = 0u; ring < sizes.size(); ring += 1u)
    {
        std::vector<unsigned long long> ones((size_t)width, 0ull);
        std::vector<unsigned long long> counted((size_t)width, 0ull);
        for (unsigned long long place = 0ull; place < sizes[ring]; place += 1ull)
        {
            const unsigned long long from = (place * width) / sizes[ring];
            const unsigned long long to = std::max(from + 1ull, ((place + 1ull) * width) / sizes[ring]);
            for (unsigned long long column = from; column < to; column += 1ull)
            {
                ones[(size_t)column] += (unsigned long long)bits[start + place];
                counted[(size_t)column] += 1ull;
            }
        }
        for (unsigned long long row = 1ull; row + 1ull < PLANE_RING_ROW; row += 1ull)
        {
            for (unsigned long long column = 0ull; column < width; column += 1ull)
            {
                // the share of ones, scaled to 255, is at most 255
                pixels[(size_t)((((ring * PLANE_RING_ROW) + row) * width) + column)] =
                    (unsigned char)((255ull * ones[(size_t)column]) / counted[(size_t)column]);
            }
        }
        start += sizes[ring];
    }
    return plane_png(path, pixels, width, height, 1u);
}

// a signed quotient by 2^shift, rounded toward zero, as CORDIC takes it
static long long plane_halve(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -((-value) >> shift);
}

// a signed quotient rounded to the nearest, halves away from zero
static long long plane_round(long long numerator, long long denominator)
{
    return (numerator >= 0ll) ? ((numerator + (denominator / 2ll)) / denominator)
                              : -(((-numerator) + (denominator / 2ll)) / denominator);
}

PlaneTurn plane_turn(const std::vector<unsigned char> &bits)
{
    PlaneTurn turn;
    const long long one = 1ll << PLANE_FIXED;
    turn.pi = 3ll * one;
    for (unsigned int place = 0u; place < PLANE_FIXED; place += 1u)
    {
        turn.pi += (long long)bits[place] << (PLANE_FIXED - 1u - place);
    }
    turn.arctangent[0] = turn.pi / 4ll;
    for (unsigned int shift = 1u; shift < PLANE_FIXED; shift += 1u)
    {
        long long total = 0ll;
        for (unsigned int term = 0u; (shift * ((2u * term) + 1u)) < PLANE_FIXED; term += 1u)
        {
            const long long part = (one >> (shift * ((2u * term) + 1u))) / (long long)((2u * term) + 1u);
            total += ((term & 1u) == 0u) ? part : -part;
        }
        turn.arctangent[shift] = total;
    }
    // the rotation by every arctangent in turn scales every vector by the same gain: read it off the turn by 0 of (1,
    // 0)
    long long gain_x = one;
    long long gain_y = 0ll;
    long long angle = 0ll;
    for (unsigned int shift = 0u; shift < PLANE_FIXED; shift += 1u)
    {
        const int up = angle >= 0ll;
        const long long next_x = up ? (gain_x - plane_halve(gain_y, shift)) : (gain_x + plane_halve(gain_y, shift));
        gain_y = up ? (gain_y + plane_halve(gain_x, shift)) : (gain_y - plane_halve(gain_x, shift));
        gain_x = next_x;
        angle += up ? -turn.arctangent[shift] : turn.arctangent[shift];
    }
    turn.gain = gain_x;
    return turn;
}

// the point at the fraction place / size of a turn, at radius, rounded to the pixel
static void plane_turn_point(const PlaneTurn &turn, unsigned long long place, unsigned long long size, long long radius,
                             long long *column, long long *row)
{
    // 2 pi 2^40 times a place below 2^15 is below 2^58, and the size is below 2^15
    long long angle = (2ll * turn.pi * (long long)place) / (long long)size;
    long long x = 1ll << PLANE_FIXED;
    long long y = 0ll;
    if (angle > turn.pi)
    {
        angle -= 2ll * turn.pi;
    }
    if (angle > turn.pi / 2ll)
    {
        x = 0ll;
        y = 1ll << PLANE_FIXED;
        angle -= turn.pi / 2ll;
    }
    else if (angle < -(turn.pi / 2ll))
    {
        x = 0ll;
        y = -(1ll << PLANE_FIXED);
        angle += turn.pi / 2ll;
    }
    for (unsigned int shift = 0u; shift < PLANE_FIXED; shift += 1u)
    {
        const int up = angle >= 0ll;
        const long long next_x = up ? (x - plane_halve(y, shift)) : (x + plane_halve(y, shift));
        y = up ? (y + plane_halve(x, shift)) : (y - plane_halve(x, shift));
        x = next_x;
        angle += up ? -turn.arctangent[shift] : turn.arctangent[shift];
    }
    // the radius is at most 2^12 and each part at most 2^41. The products stay below 2^53
    *column = plane_round(radius * x, turn.gain);
    *row = -plane_round(radius * y, turn.gain);
}

// the rings as circles, ring k at radius 2^(k - 1) times the scale, bit j at the fraction j / c_k of the turn, each
// pixel the share of ones on it, the ground gray
int plane_ring_circle(const std::vector<unsigned long long> &sizes, const unsigned char *bits, const PlaneTurn &turn,
                      size_t rings, long long scale, const std::string &path)
{
    const long long range = ((1ll << (rings - 2u)) * scale) + 4ll;
    const unsigned long long side = (unsigned long long)((2ll * range) + 1ll);
    std::vector<unsigned long long> ones((size_t)(side * side), 0ull);
    std::vector<unsigned long long> counted((size_t)(side * side), 0ull);
    unsigned long long start = 0ull;
    for (size_t ring = 0u; ring < rings; ring += 1u)
    {
        // ring 0, radius a half, is drawn at the center
        const long long radius = (ring == 0u) ? 0ll : ((1ll << (ring - 1u)) * scale);
        for (unsigned long long place = 0ull; place < sizes[ring]; place += 1ull)
        {
            long long column = 0ll;
            long long row = 0ll;
            plane_turn_point(turn, place, sizes[ring], radius, &column, &row);
            // the point lies within the radius of the center. The index is never negative
            const size_t index =
                (size_t)(((unsigned long long)(row + range) * side) + (unsigned long long)(column + range));
            ones[index] += (unsigned long long)bits[start + place];
            counted[index] += 1ull;
        }
        start += sizes[ring];
    }
    std::vector<unsigned char> pixels((size_t)(side * side), (unsigned char)PLANE_EMPTY_SHADE);
    for (size_t index = 0u; index < pixels.size(); index += 1u)
    {
        if (counted[index] != 0ull)
        {
            // the share of ones, scaled to 255, is at most 255
            pixels[index] = (unsigned char)((255ull * ones[index]) / counted[index]);
        }
    }
    return plane_png(path, pixels, side, side, 1u);
}

void plane_shuffle(const std::vector<unsigned char> &bits, unsigned int draw, std::vector<unsigned char> *drawn)
{
    *drawn = bits;
    for (size_t place = drawn->size() - 1u; place > 0u; place -= 1u)
    {
        // the draw is below place + 1, a bit's index. It narrows to size_t exactly
        const size_t other = (size_t)sim_draw_below(PLANE_KEY ^ ((unsigned long long)draw << 32u), place, place + 1u);
        std::swap((*drawn)[place], (*drawn)[other]);
    }
}

// the spirals are read at every slope from -this to this, in 1 / PLANE_RING_UNROLLED_WIDTH of a turn a ring
#define PLANE_RING_SLOPES 32ll

static long long plane_floor_quotient(long long numerator, long long denominator)
{
    const long long quotient = numerator / denominator;
    return (((numerator % denominator) != 0ll) && (numerator < 0ll)) ? (quotient - 1ll) : quotient;
}

// each bit against the bit one ring in at its angle turned back by slope / W of a turn: on the unrolled rings, a line
// leaning slope pixels a row, and on the circle a logarithmic spiral
static unsigned long long plane_ring_slope(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                                           long long slope, unsigned long long *pairs)
{
    // the width is 2^11. It fits a signed word
    const long long width = (long long)PLANE_RING_UNROLLED_WIDTH;
    unsigned long long agree = 0ull;
    unsigned long long start = sizes[0];
    unsigned long long previous_start = 0ull;
    *pairs = 0ull;
    for (size_t ring = 1u; ring < sizes.size(); ring += 1u)
    {
        // the sizes are below 2^15. They fit a signed word, and every product below stays under 2^45
        const long long size = (long long)sizes[ring];
        const long long inner = (long long)sizes[ring - 1u];
        for (long long place = 0ll; place < size; place += 1ll)
        {
            const long long turned = plane_floor_quotient(((place * width) - (slope * size)) * inner, size * width);
            const long long parent = ((turned % inner) + inner) % inner;
            // the place and its parent are never negative
            agree += (bits[start + (unsigned long long)place] == bits[previous_start + (unsigned long long)parent])
                         ? 1ull
                         : 0ull;
            *pairs += 1ull;
        }
        previous_start = start;
        start += sizes[ring];
    }
    return agree;
}

// the spirals' excess over every slope, sum over the slopes of (2 agree - pairs)^2, and the best slope
static unsigned long long plane_ring_spirals(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                                             long long *best_slope, unsigned long long *best_agree)
{
    unsigned long long excess = 0ull;
    *best_slope = 0ll;
    *best_agree = 0ull;
    for (long long slope = -PLANE_RING_SLOPES; slope <= PLANE_RING_SLOPES; slope += 1ll)
    {
        unsigned long long pairs = 0ull;
        const unsigned long long agree = plane_ring_slope(sizes, bits, slope, &pairs);
        // both counts are below 2^16. They fit a signed word
        const long long lean = (2ll * (long long)agree) - (long long)pairs;
        // a square is never negative
        excess += (unsigned long long)(lean * lean);
        if (agree > *best_agree)
        {
            *best_agree = agree;
            *best_slope = slope;
        }
    }
    return excess;
}

// one block of the rings' bits read for spirals against keyed shuffles of the same block
void plane_ring_spiral_read(SimResults *results, const std::vector<unsigned long long> &sizes,
                            const std::vector<unsigned char> &block, unsigned int draws, const char *label)
{
    ScripturaLine *const line = &results->line;
    long long slope = 0ll;
    unsigned long long agree = 0ull;
    const unsigned long long excess = plane_ring_spirals(sizes, block.data(), &slope, &agree);
    std::vector<unsigned long long> excess_band;
    std::vector<unsigned long long> agree_band;
    std::vector<unsigned char> drawn;
    for (unsigned int draw = 0u; draw < draws; draw += 1u)
    {
        plane_shuffle(block, draw, &drawn);
        long long drawn_slope = 0ll;
        unsigned long long drawn_agree = 0ull;
        excess_band.push_back(plane_ring_spirals(sizes, drawn.data(), &drawn_slope, &drawn_agree));
        agree_band.push_back(drawn_agree);
    }
    unsigned long long pairs = 0ull;
    const unsigned long long radial = plane_ring_slope(sizes, block.data(), 0ll, &pairs);
    scriptura_text(line, "  ");
    scriptura_text(line, label);
    scriptura_text(line, ": the radial agreement ");
    scriptura_decimal(line, radial, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, pairs, 1u);
    scriptura_text(line, "; the best spiral, slope ");
    scriptura_signed(line, slope);
    scriptura_text(line, ", agrees on ");
    scriptura_decimal(line, agree, 1u);
    plane_band_print(line, agree_band, agree);
    scriptura_text(line, "  ");
    scriptura_text(line, label);
    scriptura_text(line, ": the spirals' excess over every slope from -");
    scriptura_decimal(line, PLANE_RING_SLOPES, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, PLANE_RING_SLOPES, 1u);
    scriptura_text(line, ", ");
    scriptura_decimal(line, excess, 1u);
    plane_band_print(line, excess_band, excess);
    sim_flush(results);
}
