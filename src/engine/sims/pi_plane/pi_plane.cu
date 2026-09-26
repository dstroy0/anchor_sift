// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// pi in the plane (Doug, 24 September: "write it bitwise in 2d and look for a line or spiral", "let's do 2kb, 16k
// bits", then "write it out horizontally as a tower of n widths and heights, then try circle shapes of bits written
// as horizontal lines first then write the bits in a circular fill"). pi's bits after the point, certified by
// Machin's bracket on the exact integer, are laid out as shapes; each shape is drawn as a PNG and read for its longest
// straight line of equal bits, against keyed shuffles of the same bits laid out the same way.
//
// 1. The bits: floor((pi - 3) 2^N) is one integer at both ends of Machin's bracket, and it begins 0x243F6A8885A308D3.
// 2. Every width at once: laid in rows of width W, a line of step (dy, dx) is the progression of difference dy W + dx
//    along the bits, so the longest run of equal bits at every difference L below N reads every line in every width,
//    a line that wraps a row's end included. The device reads it, one thread a difference, and the host reads it again
//    for pi.
// 3. The shapes: rows of width 7, 16, 32, 64, 106, 113, 128 and 256 (7, 106 and 113 are pi's floors); the tower whose
//    row k holds k bits; a disc filled by horizontal lines and the same disc filled ring by ring; the square spiral;
//    and the twindragon, bit n at the Gaussian integer that n's binary digits name in base -1 + i. Each lays every bit
//    on its own pixel. A shape's line is read along every step (dy, dx) with coprime parts of at most 6.
// 4. Against chance: every reading is taken again on keyed Fisher-Yates shuffles of the bits, which keep the count of
//    ones, and pi's is ranked among them.
#include "sim.h"

#include <algorithm>
#include <string>
#include <vector>

#define PLANE_BITS 16384u

// the lag scan holds the bits in one block's shared memory, one byte a bit
#define PLANE_BITS_MOST 32768u

// the guard bits Machin's bracket is taken at past the bits read
#define PLANE_GUARD 32u

#define PLANE_PUBLISHED_BITS 0x243F6A8885A308D3ull

#define PLANE_DRAWS 99u

#define PLANE_KEY 0x504C414E45ull

#define PLANE_THREADS 256u

// the widest part of a line's step on a shape
#define PLANE_STEP_MOST 6ll

// a picture's longer side is scaled up to at most this many pixels
#define PLANE_PICTURE_MOST 1024ull

// the shade of a pixel no bit lands on, midway, so neither a one nor a zero stands out against it
#define PLANE_EMPTY_SHADE 128u

// the twindragon's pixels are read by their depth from its edge, 1 to this, the deepest class holding the rest
#define PLANE_DEPTHS 8u

// the golden sphere's spirals join point i to i + F_k: the Fibonacci differences below the bits
#define PLANE_FIBONACCI 20u

// the empty columns between the sphere's four views in its picture
#define PLANE_SPHERE_GAP 3ll

// the rings are drawn unrolled at this many pixels across, each ring a row this tall
#define PLANE_RING_UNROLLED_WIDTH 2048ull

#define PLANE_RING_ROW 24ull

// the fixed point, 2^this, the rings' turn is taken in
#define PLANE_FIXED 40u

// the rings drawn enlarged about the centre, and how much
#define PLANE_RING_CENTRE 10u

#define PLANE_RING_CENTRE_SCALE 2ll

typedef struct
{
    unsigned long long agree;
    unsigned long long pairs;
    unsigned long long run;
    unsigned long long run_ring;
    unsigned long long run_place;
} PlaneRingReading;

static const unsigned int s_plane_fibonacci[PLANE_FIBONACCI] = {1u, 2u, 3u, 5u, 8u, 13u, 21u, 34u, 55u, 89u, 144u,
                                                                233u, 377u, 610u, 987u, 1597u, 2584u, 4181u, 6765u,
                                                                10946u};

typedef struct
{
    long long x;
    long long y;
    long long z;
} PlaneSpherePoint;

#define PLANE_WIDTHS 8u

#define PLANE_TOP_LAGS 8u

// the density of ones is read over 2^m classes of the bits' index for m = 1 to this, each class two bits or more
#define PLANE_SCALES 13u

static const unsigned long long s_plane_widths[PLANE_WIDTHS] = {7ull, 16ull, 32ull, 64ull, 106ull, 113ull, 128ull,
                                                                256ull};

static int s_plane_refused = 0;

typedef struct
{
    std::string name;
    unsigned long long height;
    unsigned long long width;
    std::vector<long long> cell;
} PlaneShape;

typedef struct
{
    long long row;
    long long column;
} PlaneStep;

typedef struct
{
    unsigned long long length;
    PlaneStep step;
    long long start;
} PlaneLine;

typedef struct
{
    long long x;
    long long y;
} PlanePoint;

static void plane_took(AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        s_plane_refused = 1;
    }
}

static AnchorExactInteger plane_whole(unsigned long long whole)
{
    AnchorExactInteger value;
    sim_exact_whole(&value, whole);
    return value;
}

static AnchorExactInteger plane_power_two(unsigned int bits)
{
    AnchorExactInteger value;
    anchor_exact_zero(&value);
    value.limb[bits / 32u] = 1u << (bits % 32u);
    value.sign = 1;
    return value;
}

static AnchorExactInteger plane_sum(const AnchorExactInteger &left, const AnchorExactInteger &right)
{
    AnchorExactInteger value;
    anchor_exact_zero(&value);
    plane_took(anchor_exact_add(&left, &right, &value));
    return value;
}

static AnchorExactInteger plane_difference(const AnchorExactInteger &left, const AnchorExactInteger &right)
{
    AnchorExactInteger value;
    anchor_exact_zero(&value);
    plane_took(anchor_exact_subtract(&left, &right, &value));
    return value;
}

static AnchorExactInteger plane_product(const AnchorExactInteger &left, const AnchorExactInteger &right)
{
    AnchorExactInteger value;
    anchor_exact_zero(&value);
    plane_took(anchor_exact_multiply(&left, &right, &value));
    return value;
}

// the floor of a quotient of two non-negative integers
static AnchorExactInteger plane_quotient(const AnchorExactInteger &numerator, const AnchorExactInteger &divisor)
{
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    anchor_exact_zero(&quotient);
    anchor_exact_zero(&remainder);
    plane_took(anchor_exact_divide(&numerator, &divisor, &quotient, &remainder));
    return quotient;
}

// 2^bits . arctan(1 / x) within terms + 1: the alternating series, each term floored
static AnchorExactInteger plane_arctan(unsigned long long x, unsigned int bits, unsigned long long *terms)
{
    const AnchorExactInteger square = plane_whole(x * x);
    AnchorExactInteger power = plane_quotient(plane_power_two(bits), plane_whole(x));
    AnchorExactInteger total = plane_whole(0ull);
    unsigned long long index = 0ull;
    *terms = 0ull;
    while (power.sign != 0)
    {
        const AnchorExactInteger term = plane_quotient(power, plane_whole((2ull * index) + 1ull));
        total = ((index & 1ull) == 0ull) ? plane_sum(total, term) : plane_difference(total, term);
        *terms += 1ull;
        power = plane_quotient(power, square);
        index += 1ull;
    }
    return total;
}

// the bits of pi - 3 after the point, most significant first, where Machin's bracket agrees on all of them
static int plane_bits(SimTally *tally, unsigned int count, std::vector<unsigned char> *bits)
{
    const unsigned int precision = count + PLANE_GUARD;
    unsigned long long fifth_terms = 0ull;
    unsigned long long far_terms = 0ull;
    const AnchorExactInteger fifth = plane_arctan(5ull, precision, &fifth_terms);
    const AnchorExactInteger far = plane_arctan(239ull, precision, &far_terms);
    const AnchorExactInteger middle = plane_difference(plane_product(fifth, plane_whole(16ull)),
                                                       plane_product(far, plane_whole(4ull)));
    const AnchorExactInteger spread = plane_whole((16ull * (fifth_terms + 1ull)) + (4ull * (far_terms + 1ull)));
    const AnchorExactInteger guard = plane_power_two(PLANE_GUARD);
    const AnchorExactInteger below = plane_quotient(plane_difference(middle, spread), guard);
    const AnchorExactInteger above = plane_quotient(plane_sum(middle, spread), guard);
    const int agree = (s_plane_refused == 0) && (anchor_exact_compare(&below, &above) == 0);
    const AnchorExactInteger turn = plane_difference(below, plane_product(plane_whole(3ull), plane_power_two(count)));
    bits->assign(count, 0u);
    for (unsigned int place = 1u; place <= count; place += 1u)
    {
        const unsigned int bit = count - place;
        // one bit of a 32-bit limb, taken from the bottom after the shift
        (*bits)[place - 1u] = (unsigned char)((turn.limb[bit / 32u] >> (bit % 32u)) & 1u);
    }
    unsigned long long leading = 0ull;
    for (unsigned int place = 0u; place < 64u; place += 1u)
    {
        leading = (leading << 1u) | (unsigned long long)(*bits)[place];
    }
    unsigned long long ones = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        ones += (unsigned long long)(*bits)[place];
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  pi by Machin's formula at ");
    scriptura_decimal(line, precision, 1u);
    scriptura_text(line, " bits, ");
    scriptura_decimal(line, fifth_terms + far_terms, 1u);
    scriptura_text(line, " terms: ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " bits after the point, ");
    scriptura_decimal(line, ones, 1u);
    scriptura_text(line, " of them ones\n");
    sim_check(tally, agree, "floor((pi - 3) 2^N) is one integer at both ends of Machin's bracket");
    sim_check(tally, leading == PLANE_PUBLISHED_BITS, "pi's first 64 bits after the point are 0x243F6A8885A308D3");
    return agree && (leading == PLANE_PUBLISHED_BITS);
}

// the shape's pixels from each bit's place; 0 where two bits land on one pixel
static int plane_shape_lay(PlaneShape *shape, const std::string &name, const std::vector<long long> &rows,
                           const std::vector<long long> &columns)
{
    shape->name = name;
    long long top = rows[0];
    long long bottom = rows[0];
    long long left = columns[0];
    long long right = columns[0];
    for (size_t bit = 1u; bit < rows.size(); bit += 1u)
    {
        top = std::min(top, rows[bit]);
        bottom = std::max(bottom, rows[bit]);
        left = std::min(left, columns[bit]);
        right = std::max(right, columns[bit]);
    }
    // both spans are at least one and below the bit count, so they widen to unsigned exactly
    shape->height = (unsigned long long)(bottom - top + 1ll);
    shape->width = (unsigned long long)(right - left + 1ll);
    shape->cell.assign((size_t)(shape->height * shape->width), -1ll);
    for (size_t bit = 0u; bit < rows.size(); bit += 1u)
    {
        // the offsets from the top left corner are never negative
        const size_t index = (size_t)((unsigned long long)(rows[bit] - top) * shape->width
                                      + (unsigned long long)(columns[bit] - left));
        if (shape->cell[index] >= 0ll)
        {
            return 0;
        }
        // a bit's index is below 2^15, so it fits a signed word
        shape->cell[index] = (long long)bit;
    }
    return 1;
}

static int plane_rows(PlaneShape *shape, unsigned int count, unsigned long long width)
{
    std::vector<long long> rows(count);
    std::vector<long long> columns(count);
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        // the row and column are below the bit count, so they fit a signed word
        rows[bit] = (long long)(bit / width);
        columns[bit] = (long long)(bit % width);
    }
    return plane_shape_lay(shape, "rows_" + std::to_string(width), rows, columns);
}

// row k holds k + 1 bits, left aligned
static int plane_tower(PlaneShape *shape, unsigned int count)
{
    std::vector<long long> rows(count);
    std::vector<long long> columns(count);
    long long row = 0ll;
    long long start = 0ll;
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        if ((long long)bit >= start + row + 1ll)
        {
            start += row + 1ll;
            row += 1ll;
        }
        rows[bit] = row;
        // the bit's index is below 2^15, so it fits a signed word
        columns[bit] = (long long)bit - start;
    }
    return plane_shape_lay(shape, "tower", rows, columns);
}

static int plane_half(const PlanePoint &point)
{
    return (point.y < 0ll) || ((point.y == 0ll) && (point.x < 0ll));
}

// by the square of the radius, then counterclockwise from the positive x axis, in integers
static bool plane_ring_before(const PlanePoint &left, const PlanePoint &right)
{
    const long long left_radius = (left.x * left.x) + (left.y * left.y);
    const long long right_radius = (right.x * right.x) + (right.y * right.y);
    if (left_radius != right_radius)
    {
        return left_radius < right_radius;
    }
    const int left_half = plane_half(left);
    const int right_half = plane_half(right);
    if (left_half != right_half)
    {
        return left_half < right_half;
    }
    return ((left.x * right.y) - (left.y * right.x)) > 0ll;
}

static bool plane_raster_before(const PlanePoint &left, const PlanePoint &right)
{
    if (left.y != right.y)
    {
        return left.y > right.y;
    }
    return left.x < right.x;
}

// the count lattice points nearest the centre, by radius then angle, filled ring by ring or by horizontal lines
static int plane_disc(PlaneShape *by_rows, PlaneShape *by_rings, unsigned int count)
{
    long long radius = 1ll;
    unsigned long long inside = 0ull;
    while (inside < count)
    {
        radius += 1ll;
        inside = 0ull;
        for (long long y = -radius; y <= radius; y += 1ll)
        {
            for (long long x = -radius; x <= radius; x += 1ll)
            {
                inside += (((x * x) + (y * y)) <= (radius * radius)) ? 1ull : 0ull;
            }
        }
    }
    std::vector<PlanePoint> points;
    for (long long y = -radius; y <= radius; y += 1ll)
    {
        for (long long x = -radius; x <= radius; x += 1ll)
        {
            if (((x * x) + (y * y)) <= (radius * radius))
            {
                points.push_back(PlanePoint{x, y});
            }
        }
    }
    std::sort(points.begin(), points.end(), plane_ring_before);
    points.resize(count);
    std::vector<long long> rows(count);
    std::vector<long long> columns(count);
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        rows[bit] = -points[bit].y;
        columns[bit] = points[bit].x;
    }
    int good = plane_shape_lay(by_rings, "disc_rings", rows, columns);
    std::sort(points.begin(), points.end(), plane_raster_before);
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        rows[bit] = -points[bit].y;
        columns[bit] = points[bit].x;
    }
    good = good && plane_shape_lay(by_rows, "disc_rows", rows, columns);
    return good;
}

// the square spiral from the centre, right, up, left, down, with runs 1, 1, 2, 2, 3, 3, ...
static int plane_spiral(PlaneShape *shape, unsigned int count)
{
    long long side = 1ll;
    while (side * side < (long long)count)
    {
        side += 1ll;
    }
    const long long step_row[4] = {0ll, -1ll, 0ll, 1ll};
    const long long step_column[4] = {1ll, 0ll, -1ll, 0ll};
    std::vector<long long> rows;
    std::vector<long long> columns;
    long long row = side / 2ll;
    long long column = (side - 1ll) / 2ll;
    rows.push_back(row);
    columns.push_back(column);
    long long run = 1ll;
    unsigned int turn = 0u;
    while (rows.size() < count)
    {
        for (long long walked = 0ll; (walked < run) && (rows.size() < count); walked += 1ll)
        {
            row += step_row[turn % 4u];
            column += step_column[turn % 4u];
            if ((row >= 0ll) && (row < side) && (column >= 0ll) && (column < side))
            {
                rows.push_back(row);
                columns.push_back(column);
            }
        }
        turn += 1u;
        run += ((turn % 2u) == 0u) ? 1ll : 0ll;
    }
    return plane_shape_lay(shape, "spiral", rows, columns);
}

// bit n at the Gaussian integer sum over n's set bits k of (-1 + i)^k, drawn with the imaginary axis up
static int plane_twindragon(PlaneShape *shape, unsigned int count)
{
    std::vector<long long> rows(count);
    std::vector<long long> columns(count);
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        long long real = 0ll;
        long long imaginary = 0ll;
        long long power_real = 1ll;
        long long power_imaginary = 0ll;
        for (unsigned int digit = bit; digit != 0u; digit >>= 1u)
        {
            if ((digit & 1u) != 0u)
            {
                real += power_real;
                imaginary += power_imaginary;
            }
            // (a + bi)(-1 + i) = (-a - b) + (a - b)i
            const long long next_real = -power_real - power_imaginary;
            power_imaginary = power_real - power_imaginary;
            power_real = next_real;
        }
        rows[bit] = -imaginary;
        columns[bit] = real;
    }
    return plane_shape_lay(shape, "twindragon", rows, columns);
}

// the integer points whose distance from the centre rounds to radius: R^2 - R + 1 <= x^2 + y^2 + z^2 <= R^2 + R
static std::vector<PlaneSpherePoint> plane_shell_points(long long radius)
{
    std::vector<PlaneSpherePoint> points;
    const long long least = (radius * radius) - radius + 1ll;
    const long long most = (radius * radius) + radius;
    for (long long z = -radius - 1ll; z <= radius + 1ll; z += 1ll)
    {
        for (long long y = -radius - 1ll; y <= radius + 1ll; y += 1ll)
        {
            for (long long x = -radius - 1ll; x <= radius + 1ll; x += 1ll)
            {
                const long long square = (x * x) + (y * y) + (z * z);
                if ((square >= least) && (square <= most))
                {
                    points.push_back(PlaneSpherePoint{x, y, z});
                }
            }
        }
    }
    return points;
}

// the widest shell that holds no more points than the bits
static std::vector<PlaneSpherePoint> plane_shell(unsigned int count, long long *radius)
{
    std::vector<PlaneSpherePoint> kept;
    *radius = 0ll;
    for (long long trial = 1ll;; trial += 1ll)
    {
        std::vector<PlaneSpherePoint> points = plane_shell_points(trial);
        if (points.size() > count)
        {
            return kept;
        }
        kept.swap(points);
        *radius = trial;
    }
}

// by longitude, counterclockwise from the positive x axis, in integers; the poles' points, on the axis, first
static int plane_longitude_order(const PlaneSpherePoint &left, const PlaneSpherePoint &right)
{
    const int left_pole = (left.x == 0ll) && (left.y == 0ll);
    const int right_pole = (right.x == 0ll) && (right.y == 0ll);
    if ((left_pole != 0) || (right_pole != 0))
    {
        return right_pole - left_pole;
    }
    const PlanePoint left_flat = {left.x, left.y};
    const PlanePoint right_flat = {right.x, right.y};
    const int left_half = plane_half(left_flat);
    const int right_half = plane_half(right_flat);
    if (left_half != right_half)
    {
        return (left_half < right_half) ? -1 : 1;
    }
    const long long cross = (left.x * right.y) - (left.y * right.x);
    return (cross > 0ll) ? -1 : ((cross < 0ll) ? 1 : 0);
}

static long long plane_axis_square(const PlaneSpherePoint &point)
{
    return (point.x * point.x) + (point.y * point.y);
}

// latitude circles from the north pole down, each by longitude
static bool plane_latitude_before(const PlaneSpherePoint &left, const PlaneSpherePoint &right)
{
    if (left.z != right.z)
    {
        return left.z > right.z;
    }
    const int order = plane_longitude_order(left, right);
    if (order != 0)
    {
        return order < 0;
    }
    return plane_axis_square(left) < plane_axis_square(right);
}

// meridians by longitude, each from the north pole down
static bool plane_meridian_before(const PlaneSpherePoint &left, const PlaneSpherePoint &right)
{
    const int order = plane_longitude_order(left, right);
    if (order != 0)
    {
        return order < 0;
    }
    if (left.z != right.z)
    {
        return left.z > right.z;
    }
    return plane_axis_square(left) < plane_axis_square(right);
}

// the sphere seen from +z, -z, +x and -x, side by side, each pixel the bit of the point nearest the eye
static void plane_sphere_views(PlaneShape *shape, const std::string &name, const std::vector<PlaneSpherePoint> &points,
                               long long radius)
{
    const long long side = (2ll * radius) + 3ll;
    shape->name = name;
    // both extents are small and positive
    shape->height = (unsigned long long)side;
    shape->width = (unsigned long long)((4ll * side) + (3ll * PLANE_SPHERE_GAP));
    shape->cell.assign((size_t)(shape->height * shape->width), -1ll);
    std::vector<long long> nearest(shape->cell.size(), 0ll);
    for (size_t bit = 0u; bit < points.size(); bit += 1u)
    {
        const PlaneSpherePoint &point = points[bit];
        // each view: its row, its column, and how near the eye the point stands
        const long long row[4] = {-point.y, -point.y, -point.z, -point.z};
        const long long column[4] = {point.x, -point.x, -point.y, point.y};
        const long long toward[4] = {point.z, -point.z, point.x, -point.x};
        for (long long view = 0ll; view < 4ll; view += 1ll)
        {
            const long long at_row = row[view] + radius + 1ll;
            const long long at_column = column[view] + radius + 1ll + (view * (side + PLANE_SPHERE_GAP));
            // the offsets lie inside the picture, so the index is never negative
            const size_t index = (size_t)((at_row * (long long)shape->width) + at_column);
            if ((shape->cell[index] < 0ll) || (toward[view] > nearest[index]))
            {
                // a bit's index is below 2^15, so it fits a signed word
                shape->cell[index] = (long long)bit;
                nearest[index] = toward[view];
            }
        }
    }
}

// the ones on each circle of latitude, and their spread over the circles, sum over them of (2 ones - size)^2
static unsigned long long plane_latitude_spread(const std::vector<PlaneSpherePoint> &points, long long radius,
                                                const unsigned char *bits)
{
    const size_t levels = (size_t)((2ll * radius) + 3ll);
    std::vector<long long> ones(levels, 0ll);
    std::vector<long long> sizes(levels, 0ll);
    for (size_t bit = 0u; bit < points.size(); bit += 1u)
    {
        // the height lies within the radius plus one, so the offset is never negative
        const size_t level = (size_t)(points[bit].z + radius + 1ll);
        ones[level] += (long long)bits[bit];
        sizes[level] += 1ll;
    }
    unsigned long long spread = 0ull;
    for (size_t level = 0u; level < levels; level += 1u)
    {
        const long long excess = (2ll * ones[level]) - sizes[level];
        // a square is never negative
        spread += (unsigned long long)(excess * excess);
    }
    return spread;
}

static long long plane_gcd(long long left, long long right)
{
    while (right != 0ll)
    {
        const long long rest = left % right;
        left = right;
        right = rest;
    }
    return left;
}

// the steps (dy, dx) with coprime parts of at most PLANE_STEP_MOST, one of each pair of opposites
static std::vector<PlaneStep> plane_steps(void)
{
    std::vector<PlaneStep> steps;
    for (long long row = 0ll; row <= PLANE_STEP_MOST; row += 1ll)
    {
        for (long long column = -PLANE_STEP_MOST; column <= PLANE_STEP_MOST; column += 1ll)
        {
            const int forward = (row > 0ll) || (column > 0ll);
            const long long magnitude = (column < 0ll) ? -column : column;
            if (forward && (plane_gcd(row, magnitude) == 1ll))
            {
                steps.push_back(PlaneStep{row, column});
            }
        }
    }
    return steps;
}

static long long plane_cell_at(const PlaneShape &shape, long long row, long long column)
{
    // the extents are below 2^16, so they fit a signed word
    const long long height = (long long)shape.height;
    const long long width = (long long)shape.width;
    if ((row < 0ll) || (row >= height) || (column < 0ll) || (column >= width))
    {
        return -1ll;
    }
    // the row and column are inside the shape, so the index is never negative
    return shape.cell[(size_t)((row * width) + column)];
}

// the longest straight run of equal bits on the shape, along any of the steps
static PlaneLine plane_longest_line(const PlaneShape &shape, const unsigned char *bits,
                                    const std::vector<PlaneStep> &steps)
{
    PlaneLine best = {0ull, {0ll, 0ll}, -1ll};
    // the extents are below 2^16, so they fit a signed word
    const long long height = (long long)shape.height;
    const long long width = (long long)shape.width;
    for (const PlaneStep &step : steps)
    {
        for (long long row = 0ll; row < height; row += 1ll)
        {
            for (long long column = 0ll; column < width; column += 1ll)
            {
                const long long here = shape.cell[(size_t)((row * width) + column)];
                if (here < 0ll)
                {
                    continue;
                }
                const long long before = plane_cell_at(shape, row - step.row, column - step.column);
                if ((before >= 0ll) && (bits[before] == bits[here]))
                {
                    continue;
                }
                unsigned long long length = 1ull;
                long long next = plane_cell_at(shape, row + step.row, column + step.column);
                long long walked = 1ll;
                while ((next >= 0ll) && (bits[next] == bits[here]))
                {
                    length += 1ull;
                    walked += 1ll;
                    next = plane_cell_at(shape, row + (walked * step.row), column + (walked * step.column));
                }
                if (length > best.length)
                {
                    best.length = length;
                    best.step = step;
                    best.start = here;
                }
            }
        }
    }
    return best;
}

// the longest run of equal bits along the progressions of difference lag, one thread a lag, the bits in shared memory
static __global__ void plane_lag_kernel(const unsigned char *bits, unsigned int count, unsigned int *longest)
{
    extern __shared__ unsigned char plane_shared[];
    for (unsigned int index = threadIdx.x; index < count; index += blockDim.x)
    {
        plane_shared[index] = bits[index];
    }
    __syncthreads();
    const unsigned int lag = (blockIdx.x * blockDim.x) + threadIdx.x + 1u;
    if (lag >= count)
    {
        return;
    }
    unsigned int best = 1u;
    for (unsigned int residue = 0u; residue < lag; residue += 1u)
    {
        unsigned int run = 1u;
        for (unsigned int place = residue + lag; place < count; place += lag)
        {
            run = (plane_shared[place] == plane_shared[place - lag]) ? (run + 1u) : 1u;
            best = (run > best) ? run : best;
        }
    }
    longest[lag] = best;
}

static void plane_lag_host(const unsigned char *bits, unsigned int count, unsigned int *longest)
{
    longest[0] = 0u;
    for (unsigned int lag = 1u; lag < count; lag += 1u)
    {
        unsigned int best = 1u;
        for (unsigned int residue = 0u; residue < lag; residue += 1u)
        {
            unsigned int run = 1u;
            for (unsigned int place = residue + lag; place < count; place += lag)
            {
                run = (bits[place] == bits[place - lag]) ? (run + 1u) : 1u;
                best = (run > best) ? run : best;
            }
        }
        longest[lag] = best;
    }
}

static int plane_lag_device(SimTally *tally, const unsigned char *bits, unsigned int count, unsigned char *device_bits,
                            unsigned int *device_longest, unsigned int *longest)
{
    int good = sim_took(tally, cudaMemcpy(device_bits, bits, count, cudaMemcpyHostToDevice), "bits to the device");
    good = good && sim_took(tally, cudaMemset(device_longest, 0, (size_t)count * sizeof(unsigned int)), "lag clear");
    if (good)
    {
        // the block count is below 2^8 for the bits this sim holds
        const unsigned int blocks = (unsigned int)sim_launch_blocks(count - 1u, PLANE_THREADS);
        plane_lag_kernel<<<blocks, PLANE_THREADS, count>>>(device_bits, count, device_longest);
        good = sim_took(tally, cudaGetLastError(), "lag kernel launch");
    }
    good = good && sim_took(tally, cudaMemcpy(longest, device_longest, (size_t)count * sizeof(unsigned int),
                                              cudaMemcpyDeviceToHost), "lag read");
    return good;
}

static unsigned int plane_lag_most(const unsigned int *longest, unsigned int count, unsigned int *lag)
{
    unsigned int best = 0u;
    *lag = 0u;
    for (unsigned int each = 1u; each < count; each += 1u)
    {
        if (longest[each] > best)
        {
            best = longest[each];
            *lag = each;
        }
    }
    return best;
}

// the spread of the ones over 2^scale classes of the bits' index, sum over the classes of (2 ones - size)^2. By
// residue, a class is one place on every arm of the twindragon; by block, it is one whole sub-dragon.
static unsigned long long plane_spread(const unsigned char *bits, unsigned int count, unsigned int scale, int by_block)
{
    const unsigned int classes = 1u << scale;
    const unsigned int size = count / classes;
    std::vector<long long> ones(classes, 0ll);
    for (unsigned int bit = 0u; bit < classes * size; bit += 1u)
    {
        const unsigned int place = (by_block != 0) ? (bit / size) : (bit % classes);
        ones[place] += (long long)bits[bit];
    }
    unsigned long long spread = 0ull;
    for (unsigned int place = 0u; place < classes; place += 1u)
    {
        // the size is below 2^15, so it fits a signed word
        const long long excess = (2ll * ones[place]) - (long long)size;
        // a square is never negative
        spread += (unsigned long long)(excess * excess);
    }
    return spread;
}

// each pixel's depth, the fewest steps to a pixel no bit lands on or past the shape's edge, stepping to the four
// neighbours; 1 on the edge, and PLANE_DEPTHS for that depth and deeper. 0 where no bit lands.
static std::vector<unsigned int> plane_depth(const PlaneShape &shape)
{
    // the extents are below 2^16, so they fit a signed word
    const long long height = (long long)shape.height;
    const long long width = (long long)shape.width;
    const long long step_row[4] = {-1ll, 1ll, 0ll, 0ll};
    const long long step_column[4] = {0ll, 0ll, -1ll, 1ll};
    std::vector<unsigned int> depth(shape.cell.size(), 0u);
    std::vector<long long> frontier;
    for (long long row = 0ll; row < height; row += 1ll)
    {
        for (long long column = 0ll; column < width; column += 1ll)
        {
            // the row and column are inside the shape, so the index is never negative
            const size_t index = (size_t)((row * width) + column);
            if (shape.cell[index] < 0ll)
            {
                continue;
            }
            int edge = 0;
            for (unsigned int neighbour = 0u; neighbour < 4u; neighbour += 1u)
            {
                edge = edge || (plane_cell_at(shape, row + step_row[neighbour], column + step_column[neighbour]) < 0ll);
            }
            if (edge)
            {
                depth[index] = 1u;
                // the index is below 2^31, so it fits a signed word
                frontier.push_back((long long)index);
            }
        }
    }
    for (unsigned int level = 2u; !frontier.empty(); level += 1u)
    {
        std::vector<long long> next;
        for (const long long index : frontier)
        {
            const long long row = index / width;
            const long long column = index % width;
            for (unsigned int neighbour = 0u; neighbour < 4u; neighbour += 1u)
            {
                const long long near_row = row + step_row[neighbour];
                const long long near_column = column + step_column[neighbour];
                if (plane_cell_at(shape, near_row, near_column) < 0ll)
                {
                    continue;
                }
                // the neighbour is inside the shape, so its index is never negative
                const size_t near = (size_t)((near_row * width) + near_column);
                if (depth[near] == 0u)
                {
                    depth[near] = level;
                    // the index is below 2^31, so it fits a signed word
                    next.push_back((long long)near);
                }
            }
        }
        frontier.swap(next);
    }
    for (unsigned int &each : depth)
    {
        each = std::min(each, PLANE_DEPTHS);
    }
    return depth;
}

// the ones at each depth, and their spread over the depths, sum over the depths of (2 ones - size)^2
static unsigned long long plane_depth_spread(const PlaneShape &shape, const std::vector<unsigned int> &depth,
                                             const unsigned char *bits, unsigned long long *ones,
                                             unsigned long long *sizes)
{
    for (unsigned int level = 0u; level <= PLANE_DEPTHS; level += 1u)
    {
        ones[level] = 0ull;
        sizes[level] = 0ull;
    }
    for (size_t index = 0u; index < shape.cell.size(); index += 1u)
    {
        if (shape.cell[index] >= 0ll)
        {
            ones[depth[index]] += (unsigned long long)bits[shape.cell[index]];
            sizes[depth[index]] += 1ull;
        }
    }
    unsigned long long spread = 0ull;
    for (unsigned int level = 1u; level <= PLANE_DEPTHS; level += 1u)
    {
        // both counts are below 2^15, so they fit a signed word
        const long long excess = (2ll * (long long)ones[level]) - (long long)sizes[level];
        // a square is never negative
        spread += (unsigned long long)(excess * excess);
    }
    return spread;
}

static void plane_crc(unsigned int *crc, const unsigned char *bytes, size_t count)
{
    for (size_t byte = 0u; byte < count; byte += 1u)
    {
        *crc ^= bytes[byte];
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            *crc = (*crc >> 1u) ^ (0xEDB88320u & (0u - (*crc & 1u)));
        }
    }
}

// big endian, as PNG writes every word
static void plane_put_word(std::vector<unsigned char> *out, unsigned int word)
{
    for (unsigned int byte = 0u; byte < 4u; byte += 1u)
    {
        // one byte of the word, taken from the bottom after the shift
        out->push_back((unsigned char)(word >> (24u - (8u * byte))));
    }
}

static void plane_chunk(std::vector<unsigned char> *out, const char *type, const std::vector<unsigned char> &data)
{
    // a chunk holds at most one picture, far below 2^31 bytes
    plane_put_word(out, (unsigned int)data.size());
    const size_t start = out->size();
    for (unsigned int letter = 0u; letter < 4u; letter += 1u)
    {
        // the chunk type is four ASCII letters
        out->push_back((unsigned char)type[letter]);
    }
    out->insert(out->end(), data.begin(), data.end());
    unsigned int crc = 0xFFFFFFFFu;
    plane_crc(&crc, out->data() + start, out->size() - start);
    plane_put_word(out, crc ^ 0xFFFFFFFFu);
}

// an 8-bit PNG, grey for one channel and colour for three, its image data in stored deflate blocks, so nothing is
// encoded
static int plane_png(const std::string &path, const std::vector<unsigned char> &pixels, unsigned long long width,
                     unsigned long long height, unsigned int channels)
{
    const unsigned long long stride = width * channels;
    std::vector<unsigned char> raw;
    for (unsigned long long row = 0ull; row < height; row += 1ull)
    {
        raw.push_back(0u);
        raw.insert(raw.end(), pixels.begin() + (ptrdiff_t)(row * stride),
                   pixels.begin() + (ptrdiff_t)((row + 1ull) * stride));
    }
    std::vector<unsigned char> header;
    // the extents are below 2^16, so they fit the header's words
    plane_put_word(&header, (unsigned int)width);
    plane_put_word(&header, (unsigned int)height);
    header.push_back(8u);
    header.push_back((channels == 3u) ? 2u : 0u);
    header.push_back(0u);
    header.push_back(0u);
    header.push_back(0u);
    std::vector<unsigned char> stream;
    stream.push_back(0x78u);
    stream.push_back(0x01u);
    size_t at = 0u;
    do
    {
        const size_t take = std::min((size_t)65535u, raw.size() - at);
        stream.push_back((at + take == raw.size()) ? 1u : 0u);
        // a stored block's length and its complement, little endian
        stream.push_back((unsigned char)(take & 0xFFu));
        stream.push_back((unsigned char)(take >> 8u));
        stream.push_back((unsigned char)(~take & 0xFFu));
        stream.push_back((unsigned char)((~take >> 8u) & 0xFFu));
        stream.insert(stream.end(), raw.begin() + (ptrdiff_t)at, raw.begin() + (ptrdiff_t)(at + take));
        at += take;
    } while (at < raw.size());
    unsigned int low = 1u;
    unsigned int high = 0u;
    for (size_t byte = 0u; byte < raw.size(); byte += 1u)
    {
        low = (low + raw[byte]) % 65521u;
        high = (high + low) % 65521u;
    }
    plane_put_word(&stream, (high << 16u) | low);
    std::vector<unsigned char> file = {137u, 80u, 78u, 71u, 13u, 10u, 26u, 10u};
    plane_chunk(&file, "IHDR", header);
    plane_chunk(&file, "IDAT", stream);
    plane_chunk(&file, "IEND", std::vector<unsigned char>());
    FILE *const out = fopen(path.c_str(), "wb");
    if (out == NULL)
    {
        return 0;
    }
    const size_t written = fwrite(file.data(), 1u, file.size(), out);
    const int closed = fclose(out) == 0;
    return closed && (written == file.size());
}

// the shape drawn with each bit a square of pixels, a one white, a zero black, and no bit grey
static int plane_picture(const PlaneShape &shape, const unsigned char *bits, const std::string &path)
{
    const unsigned long long longer = std::max(shape.height, shape.width);
    const unsigned long long scale = std::max(1ull, PLANE_PICTURE_MOST / longer);
    const unsigned long long width = shape.width * scale;
    const unsigned long long height = shape.height * scale;
    std::vector<unsigned char> pixels((size_t)(width * height));
    for (unsigned long long row = 0ull; row < height; row += 1ull)
    {
        for (unsigned long long column = 0ull; column < width; column += 1ull)
        {
            const long long cell = shape.cell[(size_t)(((row / scale) * shape.width) + (column / scale))];
            const unsigned char shade = (cell < 0ll) ? (unsigned char)PLANE_EMPTY_SHADE
                                                     : ((bits[cell] != 0u) ? (unsigned char)255u : (unsigned char)0u);
            pixels[(size_t)((row * width) + column)] = shade;
        }
    }
    return plane_png(path, pixels, width, height, 1u);
}

// the shape drawn sparse: each bit a dot with a gap around it, only the ones lit, the line's bits in red whatever
// their value, and the pixels no bit lands on a little lighter than the ground
static int plane_sparse_picture(const PlaneShape &shape, const unsigned char *bits, const PlaneLine &found,
                                const std::string &path)
{
    const unsigned long long cell = 7ull;
    const unsigned long long dot = 5ull;
    std::vector<unsigned char> marked(shape.cell.size(), 0u);
    // the extents are below 2^16, so they fit a signed word
    const long long height = (long long)shape.height;
    const long long width = (long long)shape.width;
    for (long long index = 0ll; index < height * width; index += 1ll)
    {
        if (shape.cell[(size_t)index] != found.start)
        {
            continue;
        }
        for (unsigned long long walked = 0ull; walked < found.length; walked += 1ull)
        {
            // the walk is at most the line's length, below 2^15
            const long long row = (index / width) + ((long long)walked * found.step.row);
            const long long column = (index % width) + ((long long)walked * found.step.column);
            if ((row >= 0ll) && (row < height) && (column >= 0ll) && (column < width))
            {
                // the row and column are inside the shape, so the index is never negative
                marked[(size_t)((row * width) + column)] = 1u;
            }
        }
    }
    const unsigned long long picture_width = shape.width * cell;
    const unsigned long long picture_height = shape.height * cell;
    std::vector<unsigned char> pixels((size_t)(picture_width * picture_height * 3ull), 0u);
    for (unsigned long long row = 0ull; row < picture_height; row += 1ull)
    {
        for (unsigned long long column = 0ull; column < picture_width; column += 1ull)
        {
            const size_t index = (size_t)(((row / cell) * shape.width) + (column / cell));
            const unsigned long long inside_row = row % cell;
            const unsigned long long inside_column = column % cell;
            const int in_dot = (inside_row >= 1ull) && (inside_row <= dot) && (inside_column >= 1ull)
                            && (inside_column <= dot);
            unsigned char red = 0u;
            unsigned char green = 0u;
            unsigned char blue = 0u;
            if (shape.cell[index] < 0ll)
            {
                red = 24u;
                green = 24u;
                blue = 24u;
            }
            else if (in_dot && (marked[index] != 0u))
            {
                red = 255u;
                green = (bits[shape.cell[index]] != 0u) ? 96u : 0u;
                blue = green;
            }
            else if (in_dot && (bits[shape.cell[index]] != 0u))
            {
                red = 255u;
                green = 255u;
                blue = 255u;
            }
            const size_t at = (size_t)(((row * picture_width) + column) * 3ull);
            pixels[at] = red;
            pixels[at + 1u] = green;
            pixels[at + 2u] = blue;
        }
    }
    return plane_png(path, pixels, picture_width, picture_height, 3u);
}

// ring k holds floor(pi 2^k) bits, floor(pi 2^(k + 1)) = 2 floor(pi 2^k) + pi's bit k + 1; the rings that fit most
static std::vector<unsigned long long> plane_ring_sizes(const std::vector<unsigned char> &bits, unsigned long long most)
{
    std::vector<unsigned long long> sizes;
    unsigned long long size = 3ull;
    unsigned long long total = 0ull;
    for (size_t level = 0u; (level < bits.size()) && (total + size <= most); level += 1u)
    {
        sizes.push_back(size);
        total += size;
        size = (2ull * size) + (unsigned long long)bits[level];
    }
    return sizes;
}

static unsigned long long plane_ring_total(const std::vector<unsigned long long> &sizes)
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
static PlaneRingReading plane_ring_read(const std::vector<unsigned long long> &sizes, const unsigned char *bits)
{
    PlaneRingReading reading = {0ull, 0ull, 1ull, 0ull, 0ull};
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
            reading.pairs += 1ull;
            reading.agree += same ? 1ull : 0ull;
            run[(size_t)place] = same ? (previous_run[(size_t)parent] + 1ull) : 1ull;
            if (run[(size_t)place] > reading.run)
            {
                reading.run = run[(size_t)place];
                reading.run_ring = ring;
                reading.run_place = place;
            }
        }
        previous_run.swap(run);
        previous_start = start;
        start += sizes[ring];
    }
    return reading;
}

// the rings unrolled, ring k row k, bit j across [j W / c_k, (j + 1) W / c_k), each pixel the share of ones on it
static int plane_ring_unrolled(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
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
                pixels[(size_t)((((ring * PLANE_RING_ROW) + row) * width) + column)]
                    = (unsigned char)((255ull * ones[(size_t)column]) / counted[(size_t)column]);
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

// the turn in integers: pi from its certified bits in 2^PLANE_FIXED, atan(2^-i) by its series, and CORDIC
typedef struct
{
    long long pi;
    long long gain;
    long long arctangent[PLANE_FIXED];
} PlaneTurn;

static PlaneTurn plane_turn(const std::vector<unsigned char> &bits)
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
    // the rotation by every arctangent in turn scales every vector by the same gain: read it off the turn by 0 of (1, 0)
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
    // the radius is at most 2^12 and each part at most 2^41, so the products stay below 2^53
    *column = plane_round(radius * x, turn.gain);
    *row = -plane_round(radius * y, turn.gain);
}

// the rings as circles, ring k at radius 2^(k - 1) times the scale, bit j at the fraction j / c_k of the turn, each
// pixel the share of ones on it, the ground grey
static int plane_ring_circle(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                             const PlaneTurn &turn, size_t rings, long long scale, const std::string &path)
{
    const long long reach = ((1ll << (rings - 2u)) * scale) + 4ll;
    const unsigned long long side = (unsigned long long)((2ll * reach) + 1ll);
    std::vector<unsigned long long> ones((size_t)(side * side), 0ull);
    std::vector<unsigned long long> counted((size_t)(side * side), 0ull);
    unsigned long long start = 0ull;
    for (size_t ring = 0u; ring < rings; ring += 1u)
    {
        // ring 0, radius a half, is drawn at the centre
        const long long radius = (ring == 0u) ? 0ll : ((1ll << (ring - 1u)) * scale);
        for (unsigned long long place = 0ull; place < sizes[ring]; place += 1ull)
        {
            long long column = 0ll;
            long long row = 0ll;
            plane_turn_point(turn, place, sizes[ring], radius, &column, &row);
            // the point lies within the reach of the centre, so the index is never negative
            const size_t index = (size_t)(((unsigned long long)(row + reach) * side) + (unsigned long long)(column + reach));
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

static void plane_shuffle(const std::vector<unsigned char> &bits, unsigned int draw, std::vector<unsigned char> *drawn)
{
    *drawn = bits;
    for (size_t place = drawn->size() - 1u; place > 0u; place -= 1u)
    {
        // the draw is below place + 1, a bit's index, so it narrows to size_t exactly
        const size_t other = (size_t)sim_draw_below(PLANE_KEY ^ ((unsigned long long)draw << 32u), place, place + 1u);
        std::swap((*drawn)[place], (*drawn)[other]);
    }
}

static void plane_band_print(ScripturaLine *line, std::vector<unsigned long long> band, unsigned long long reading);

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
    // the width is 2^11, so it fits a signed word
    const long long width = (long long)PLANE_RING_UNROLLED_WIDTH;
    unsigned long long agree = 0ull;
    unsigned long long start = sizes[0];
    unsigned long long previous_start = 0ull;
    *pairs = 0ull;
    for (size_t ring = 1u; ring < sizes.size(); ring += 1u)
    {
        // the sizes are below 2^15, so they fit a signed word, and every product below stays under 2^45
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
        // both counts are below 2^16, so they fit a signed word
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
static void plane_ring_spiral_read(SimTally *tally, const std::vector<unsigned long long> &sizes,
                                   const std::vector<unsigned char> &block, unsigned int draws, const char *label)
{
    ScripturaLine *const line = &tally->line;
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
    sim_flush(tally);
}

// the blind pairs hold rings 0 to this less one, and lie in the first this many blocks past the seen bits
#define PLANE_BLIND_RINGS 12u

#define PLANE_BLIND_MOST 16u

// the first round of blind pairs, which the eye scored 6 of 6 (Doug, 25 September)
#define PLANE_BLIND_SCORED 6u

// blind pairs (Doug, 24 September, the roots drawn over the unrolled rings): pi's unseen blocks, from block first past
// the seen bits, each laid in the rings unrolled beside a shuffle of the same block, which is which decided by a keyed
// coin, or where balanced by a keyed deal of pi to A in exactly half the pairs, and written only to blind_answer.txt
static int plane_blind(SimTally *tally, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                       unsigned int first, unsigned int pairs, int balanced, const std::string &directory)
{
    ScripturaLine *const line = &tally->line;
    const std::vector<unsigned long long> rings(sizes.begin(),
                                                sizes.begin() + (ptrdiff_t)std::min<size_t>(PLANE_BLIND_RINGS, sizes.size()));
    const unsigned long long block = plane_ring_total(rings);
    const unsigned long long needed = seen + ((first + pairs) * block);
    if ((first + pairs > PLANE_BLIND_MOST) || (needed + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the blind pairs lie in the first ");
        scriptura_decimal(line, PLANE_BLIND_MOST, 1u);
        scriptura_text(line, " blocks and need an exact width of ");
        scriptura_decimal(line, needed + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits\n");
        sim_check(tally, 0, "the blind pairs fit the exact width");
        return 0;
    }
    // pi on A in the first half of the pairs, then dealt by a keyed Fisher-Yates shuffle
    std::vector<unsigned char> sides(pairs, 0u);
    for (unsigned int pair = 0u; pair < pairs / 2u; pair += 1u)
    {
        sides[pair] = 1u;
    }
    for (unsigned int pair = pairs; pair > 1u; pair -= 1u)
    {
        // the draw is below the pair count, so it narrows to unsigned int exactly
        const unsigned int other = (unsigned int)sim_draw_below(PLANE_KEY ^ 0x42414C414E4345ull, pair - 1u, pair);
        std::swap(sides[pair - 1u], sides[other]);
    }
    std::vector<unsigned char> all;
    // the bits needed are at most 2^18 or so, far below 2^32
    int good = plane_bits(tally, (unsigned int)needed, &all);
    FILE *const answer = good ? fopen((directory + "/blind_answer.txt").c_str(), "w") : NULL;
    good = good && (answer != NULL);
    for (unsigned int pair = 0u; good && (pair < pairs); pair += 1u)
    {
        const size_t from = (size_t)(seen + ((first + pair) * block));
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)from, all.begin() + (ptrdiff_t)(from + block));
        std::vector<unsigned char> other;
        plane_shuffle(mine, 7919u + first + pair, &other);
        const int pi_first = balanced ? (sides[pair] != 0u)
                                      : ((sim_draw(PLANE_KEY ^ 0x424C494E44ull, pair) & 1ull) == 0ull);
        const std::string stem = directory + "/blind_" + std::to_string(pair + 1u);
        good = plane_ring_unrolled(rings, pi_first ? mine.data() : other.data(), stem + "_A.png")
            && plane_ring_unrolled(rings, pi_first ? other.data() : mine.data(), stem + "_B.png");
        fprintf(answer, "pair %u: pi is %s (pi's bits %llu to %llu)\n", pair + 1u, pi_first ? "A" : "B",
                (unsigned long long)from + 1ull, (unsigned long long)(from + block));
    }
    if (answer != NULL)
    {
        good = (fclose(answer) == 0) && good;
    }
    sim_check(tally, good, "the blind pairs are drawn and their answer written");
    scriptura_text(line, "  blind: ");
    scriptura_decimal(line, pairs, 1u);
    scriptura_text(line, " pairs, blind_<n>_A.png and blind_<n>_B.png, rings 0 to ");
    scriptura_decimal(line, rings.size() - 1u, 1u);
    scriptura_text(line, " unrolled; each pair is one unseen block of pi from bit ");
    scriptura_decimal(line, seen + (first * block) + 1ull, 1u);
    scriptura_text(line, " on and a shuffle of the same block; ");
    scriptura_text(line, balanced ? "pi is A in exactly half the pairs, dealt by a keyed shuffle; " : "");
    scriptura_text(line, "which is pi is in blind_answer.txt and nowhere else\n");
    sim_flush(tally);
    return good;
}

// the funnels (Doug, 25 September, after picking pi in all six blind pairs: "it's the distribution of bits and there
// are extremely telltale natural funnel shapes not steep Vs", then "look for shadow traces in the denser packed bits"
// and "a low res log curve can be 3 bars that look stepped to you but the ratio between the bar heights fits your
// curve"). A funnel's mouth is a run of two equal bits or more on rings 1 to PLANE_FUNNEL_MOUTH_LAST; each bar below
// it is the widest run of the same bit among the cells whose parent lies under the bar above, and the funnel ends on
// the ring where no such cell holds the bit. Its depth is how many bars it has below the mouth, the dense rings, two
// bits or more to a pixel, included; three bars w0, w1, w2, each in turns, fit one ratio as w1^2 comes near w0 w2.
#define PLANE_FUNNEL_MOUTH_LAST 8u

#define PLANE_FUNNEL_FRESH_MOST 16u

// the funnels drawn over a picture are those from a mouth this many bits wide or wider that reach the last ring
#define PLANE_FUNNEL_DRAWN_MOUTH 3ull

#define PLANE_FUNNEL_READINGS 3u

typedef struct
{
    size_t ring;
    unsigned long long first;
    unsigned long long last;
} PlaneBar;

// the funnels' depth, their bars' fit to one ratio, and the bits agreeing with their parent
typedef struct
{
    unsigned long long value[PLANE_FUNNEL_READINGS];
} PlaneFunnelReading;

static const char *const s_plane_funnel_names[PLANE_FUNNEL_READINGS] = {
    "the funnels' depth, the bars below every mouth", "three bars' fit to one ratio, the mean in millionths",
    "the bits agreeing with their parent"};

static std::vector<unsigned long long> plane_ring_starts(const std::vector<unsigned long long> &sizes)
{
    std::vector<unsigned long long> starts(sizes.size(), 0ull);
    for (size_t ring = 1u; ring < sizes.size(); ring += 1u)
    {
        starts[ring] = starts[ring - 1u] + sizes[ring - 1u];
    }
    return starts;
}

// the bars of the funnel whose mouth is cells first to last of the ring
static void plane_funnel_trace(const std::vector<unsigned long long> &sizes, const std::vector<unsigned long long> &starts,
                               const unsigned char *bits, size_t ring, unsigned long long first,
                               unsigned long long last, std::vector<PlaneBar> *bars)
{
    const unsigned char bit = bits[starts[ring] + first];
    bars->assign(1u, PlaneBar{ring, first, last});
    while (ring + 1u < sizes.size())
    {
        const unsigned long long inner = sizes[ring];
        const unsigned long long outer = sizes[ring + 1u];
        // the cells whose parent, floor(place c_k / c_(k + 1)), lies from first to last: at least one, since the ring
        // out is at least as large
        const unsigned long long from = ((first * outer) + inner - 1ull) / inner;
        const unsigned long long to = ((((last + 1ull) * outer) + inner - 1ull) / inner) - 1ull;
        const unsigned char *const cells = bits + starts[ring + 1u];
        unsigned long long best_first = 0ull;
        unsigned long long best_length = 0ull;
        unsigned long long run_first = from;
        for (unsigned long long place = from; place <= to; place += 1ull)
        {
            if (cells[place] != bit)
            {
                continue;
            }
            if ((place == from) || (cells[place - 1ull] != bit))
            {
                run_first = place;
            }
            if (place - run_first + 1ull > best_length)
            {
                best_length = place - run_first + 1ull;
                best_first = run_first;
            }
        }
        if (best_length == 0ull)
        {
            return;
        }
        ring += 1u;
        first = best_first;
        last = best_first + best_length - 1ull;
        bars->push_back(PlaneBar{ring, first, last});
    }
}

// how near three bars come to one ratio, in millionths: the smaller of w1^2 and w0 w2 over the larger, with w = bits / c_k
static unsigned long long plane_funnel_fit(const std::vector<unsigned long long> &sizes, const PlaneBar *bar)
{
    const unsigned long long wide = bar[0].last - bar[0].first + 1ull;
    const unsigned long long middle = bar[1].last - bar[1].first + 1ull;
    const unsigned long long narrow = bar[2].last - bar[2].first + 1ull;
    // w1^2 against w0 w2 is middle^2 c_k c_(k + 2) against wide narrow c_(k + 1)^2; every width and size is below
    // 2^13, so each product stays under 2^52
    unsigned long long square = middle * middle * sizes[bar[0].ring] * sizes[bar[2].ring];
    unsigned long long across = wide * narrow * sizes[bar[1].ring] * sizes[bar[1].ring];
    unsigned long long smaller = std::min(square, across);
    unsigned long long larger = std::max(square, across);
    // both are halved together until a million times the smaller fits a word
    while (larger >= (1ull << 43u))
    {
        smaller >>= 1u;
        larger >>= 1u;
    }
    return (smaller * 1000000ull) / larger;
}

// every funnel of the block: the bars below every mouth summed, the mean fit of every three bars whose first is two bits
// or wider, and the bits agreeing with their parent
static PlaneFunnelReading plane_funnel_read(const std::vector<unsigned long long> &sizes,
                                            const std::vector<unsigned long long> &starts, const unsigned char *bits)
{
    PlaneFunnelReading reading = {{0ull, 0ull, plane_ring_read(sizes, bits).agree}};
    unsigned long long fit = 0ull;
    unsigned long long triples = 0ull;
    std::vector<PlaneBar> bars;
    const size_t last_mouth = std::min<size_t>(PLANE_FUNNEL_MOUTH_LAST, sizes.size() - 1u);
    for (size_t ring = 1u; ring <= last_mouth; ring += 1u)
    {
        const unsigned char *const cells = bits + starts[ring];
        unsigned long long place = 0ull;
        while (place < sizes[ring])
        {
            unsigned long long end = place;
            while ((end + 1ull < sizes[ring]) && (cells[end + 1ull] == cells[place]))
            {
                end += 1ull;
            }
            if (end > place)
            {
                plane_funnel_trace(sizes, starts, bits, ring, place, end, &bars);
                reading.value[0] += bars.size() - 1u;
                for (size_t bar = 0u; bar + 2u < bars.size(); bar += 1u)
                {
                    if (bars[bar].last > bars[bar].first)
                    {
                        fit += plane_funnel_fit(sizes, &bars[bar]);
                        triples += 1ull;
                    }
                }
            }
            place = end + 1ull;
        }
    }
    reading.value[1] = (triples == 0ull) ? 0ull : (fit / triples);
    return reading;
}

// the rings unrolled as plane_ring_unrolled draws them, the bits of every funnel from a mouth PLANE_FUNNEL_DRAWN_MOUTH
// bits wide or wider that reaches the last ring tinted red
static int plane_funnel_picture(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                                const std::string &path)
{
    const std::vector<unsigned long long> starts = plane_ring_starts(sizes);
    std::vector<unsigned char> marked((size_t)plane_ring_total(sizes), 0u);
    std::vector<PlaneBar> bars;
    const size_t last_mouth = std::min<size_t>(PLANE_FUNNEL_MOUTH_LAST, sizes.size() - 1u);
    for (size_t ring = 1u; ring <= last_mouth; ring += 1u)
    {
        const unsigned char *const cells = bits + starts[ring];
        unsigned long long place = 0ull;
        while (place < sizes[ring])
        {
            unsigned long long end = place;
            while ((end + 1ull < sizes[ring]) && (cells[end + 1ull] == cells[place]))
            {
                end += 1ull;
            }
            if (end + 1ull >= place + PLANE_FUNNEL_DRAWN_MOUTH)
            {
                plane_funnel_trace(sizes, starts, bits, ring, place, end, &bars);
            }
            if ((end + 1ull >= place + PLANE_FUNNEL_DRAWN_MOUTH) && (bars.back().ring + 1u == sizes.size()))
            {
                for (const PlaneBar &bar : bars)
                {
                    for (unsigned long long cell = bar.first; cell <= bar.last; cell += 1ull)
                    {
                        marked[(size_t)(starts[bar.ring] + cell)] = 1u;
                    }
                }
            }
            place = end + 1ull;
        }
    }
    const unsigned long long width = PLANE_RING_UNROLLED_WIDTH;
    const unsigned long long height = sizes.size() * PLANE_RING_ROW;
    std::vector<unsigned char> pixels((size_t)(width * height * 3ull), (unsigned char)PLANE_EMPTY_SHADE);
    for (size_t ring = 0u; ring < sizes.size(); ring += 1u)
    {
        std::vector<unsigned long long> ones((size_t)width, 0ull);
        std::vector<unsigned long long> counted((size_t)width, 0ull);
        std::vector<unsigned long long> tinted((size_t)width, 0ull);
        for (unsigned long long place = 0ull; place < sizes[ring]; place += 1ull)
        {
            const unsigned long long from = (place * width) / sizes[ring];
            const unsigned long long to = std::max(from + 1ull, ((place + 1ull) * width) / sizes[ring]);
            for (unsigned long long column = from; column < to; column += 1ull)
            {
                ones[(size_t)column] += (unsigned long long)bits[starts[ring] + place];
                counted[(size_t)column] += 1ull;
                tinted[(size_t)column] += (unsigned long long)marked[(size_t)(starts[ring] + place)];
            }
        }
        for (unsigned long long row = 1ull; row + 1ull < PLANE_RING_ROW; row += 1ull)
        {
            for (unsigned long long column = 0ull; column < width; column += 1ull)
            {
                // the share of ones, scaled to 255, is at most 255, and each tint below stays within a byte
                const unsigned long long shade = (255ull * ones[(size_t)column]) / counted[(size_t)column];
                const int red = tinted[(size_t)column] != 0ull;
                const size_t at = (size_t)(((((ring * PLANE_RING_ROW) + row) * width) + column) * 3ull);
                pixels[at] = (unsigned char)(red ? (110ull + ((145ull * shade) / 255ull)) : shade);
                pixels[at + 1u] = (unsigned char)(red ? ((150ull * shade) / 255ull) : shade);
                pixels[at + 2u] = pixels[at + 1u];
            }
        }
    }
    return plane_png(path, pixels, width, height, 3u);
}

// a set of pi's blocks, each read against the same keyed shuffles of itself: each reading summed over the blocks, pi's
// against the draws', and for each block how many draws reach pi's
static void plane_funnel_blocks(SimTally *tally, const std::vector<unsigned long long> &sizes,
                                const std::vector<unsigned char> &all, unsigned long long from, unsigned int blocks,
                                unsigned int draws, const char *label)
{
    ScripturaLine *const line = &tally->line;
    const std::vector<unsigned long long> starts = plane_ring_starts(sizes);
    const unsigned long long block = plane_ring_total(sizes);
    PlaneFunnelReading pi_total = {{0ull, 0ull, 0ull}};
    std::vector<PlaneFunnelReading> drawn_total(draws, pi_total);
    std::vector<std::vector<unsigned long long>> reached(PLANE_FUNNEL_READINGS,
                                                         std::vector<unsigned long long>(blocks, 0ull));
    std::vector<unsigned char> drawn;
    for (unsigned int each = 0u; each < blocks; each += 1u)
    {
        const size_t at = (size_t)(from + (each * block));
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)at, all.begin() + (ptrdiff_t)(at + block));
        const PlaneFunnelReading reading = plane_funnel_read(sizes, starts, mine.data());
        for (unsigned int kind = 0u; kind < PLANE_FUNNEL_READINGS; kind += 1u)
        {
            pi_total.value[kind] += reading.value[kind];
        }
        for (unsigned int draw = 0u; draw < draws; draw += 1u)
        {
            plane_shuffle(mine, draw, &drawn);
            const PlaneFunnelReading drawn_reading = plane_funnel_read(sizes, starts, drawn.data());
            for (unsigned int kind = 0u; kind < PLANE_FUNNEL_READINGS; kind += 1u)
            {
                drawn_total[draw].value[kind] += drawn_reading.value[kind];
                reached[kind][each] += (drawn_reading.value[kind] >= reading.value[kind]) ? 1ull : 0ull;
            }
        }
    }
    scriptura_text(line, "  ");
    scriptura_text(line, label);
    scriptura_text(line, ", ");
    scriptura_decimal(line, blocks, 1u);
    scriptura_text(line, " blocks from bit ");
    scriptura_decimal(line, from + 1ull, 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, from + (blocks * block), 1u);
    scriptura_character(line, '\n');
    for (unsigned int kind = 0u; kind < PLANE_FUNNEL_READINGS; kind += 1u)
    {
        std::vector<unsigned long long> band;
        for (unsigned int draw = 0u; draw < draws; draw += 1u)
        {
            band.push_back(drawn_total[draw].value[kind]);
        }
        scriptura_text(line, "    ");
        scriptura_text(line, s_plane_funnel_names[kind]);
        scriptura_text(line, ", summed over the blocks: pi's ");
        scriptura_decimal(line, pi_total.value[kind], 1u);
        plane_band_print(line, band, pi_total.value[kind]);
        scriptura_text(line, "      each block, the draws of ");
        scriptura_decimal(line, draws, 1u);
        scriptura_text(line, " reaching pi's:");
        for (unsigned int each = 0u; each < blocks; each += 1u)
        {
            scriptura_character(line, ' ');
            scriptura_decimal(line, reached[kind][each], 1u);
        }
        scriptura_character(line, '\n');
        sim_flush(tally);
    }
}

// the funnels on the six blind blocks the eye picked pi from, then on fresh blocks past them that no picture showed;
// the first blind pair, pi and the shuffle it was shown beside, drawn with their funnels
static int plane_funnels(SimTally *tally, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                         unsigned int fresh, unsigned int draws, const std::string &directory)
{
    ScripturaLine *const line = &tally->line;
    const std::vector<unsigned long long> rings(sizes.begin(),
                                                sizes.begin() + (ptrdiff_t)std::min<size_t>(PLANE_BLIND_RINGS, sizes.size()));
    const unsigned long long block = plane_ring_total(rings);
    const unsigned long long needed = seen + ((PLANE_BLIND_SCORED + fresh) * block);
    if ((fresh > PLANE_FUNNEL_FRESH_MOST) || (needed + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the funnels read at most ");
        scriptura_decimal(line, PLANE_FUNNEL_FRESH_MOST, 1u);
        scriptura_text(line, " fresh blocks and need an exact width of ");
        scriptura_decimal(line, needed + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits\n");
        sim_check(tally, 0, "the funnels' blocks fit the exact width");
        return 0;
    }
    std::vector<unsigned char> all;
    // the bits needed are at most 2^18 or so, far below 2^32
    int good = plane_bits(tally, (unsigned int)needed, &all);
    if (good)
    {
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)seen, all.begin() + (ptrdiff_t)(seen + block));
        std::vector<unsigned char> other;
        plane_shuffle(mine, 7919u, &other);
        good = plane_funnel_picture(rings, mine.data(), directory + "/funnels_pi.png")
            && plane_funnel_picture(rings, other.data(), directory + "/funnels_shuffled.png");
        sim_check(tally, good, "the first blind pair is drawn with its funnels");
    }
    if (good)
    {
        scriptura_text(line, "  the funnels: mouths of two bits or more on rings 1 to ");
        scriptura_decimal(line, PLANE_FUNNEL_MOUTH_LAST, 1u);
        scriptura_text(line, ", traced to ring ");
        scriptura_decimal(line, rings.size() - 1u, 1u);
        scriptura_text(line, "; funnels_pi.png and funnels_shuffled.png are the first blind pair, the funnels from a mouth ");
        scriptura_decimal(line, PLANE_FUNNEL_DRAWN_MOUTH, 1u);
        scriptura_text(line, " bits wide or wider that reach the last ring in red\n");
        sim_flush(tally);
        plane_funnel_blocks(tally, rings, all, seen, PLANE_BLIND_SCORED, draws, "the six blind blocks");
        if (fresh > 0u)
        {
            plane_funnel_blocks(tally, rings, all, seen + (PLANE_BLIND_SCORED * block), fresh, draws,
                                "fresh blocks, unseen");
        }
    }
    return good;
}

// the rings mod floor(pi 2^k) (Doug, 24 September: "make each ring the mod of a known digit"): drawn, and each bit
// read against the bit at its angle one ring in, against keyed shuffles of the rings' bits
static int plane_rings(SimTally *tally, const std::vector<unsigned char> &bits, unsigned int draws, unsigned int blind,
                       unsigned int blind_first, int balanced, unsigned int funnels, const std::string &directory)
{
    ScripturaLine *const line = &tally->line;
    const std::vector<unsigned long long> sizes = plane_ring_sizes(bits, PLANE_BITS_MOST);
    const unsigned long long total = plane_ring_total(sizes);
    if ((sizes.size() < 2u) || (total + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the rings need ");
        scriptura_decimal(line, total, 1u);
        scriptura_text(line, " bits and a wider exact integer\n");
        sim_check(tally, 0, "the rings fit the exact width");
        return 0;
    }
    std::vector<unsigned char> ring_bits(bits.begin(), bits.begin() + (ptrdiff_t)std::min<size_t>(bits.size(), total));
    // the bits are unsigned int wide, and the total is at most PLANE_BITS_MOST
    int good = (ring_bits.size() == total) || plane_bits(tally, (unsigned int)total, &ring_bits);
    scriptura_text(line, "  the rings: ring k holds floor(pi 2^k) bits,");
    for (const unsigned long long size : sizes)
    {
        scriptura_character(line, ' ');
        scriptura_decimal(line, size, 1u);
    }
    scriptura_text(line, ", ");
    scriptura_decimal(line, total, 1u);
    scriptura_text(line, " bits in all\n");
    const PlaneTurn turn = plane_turn(ring_bits);
    std::vector<unsigned char> drawn;
    plane_shuffle(ring_bits, 0u, &drawn);
    const size_t centre = std::min<size_t>(PLANE_RING_CENTRE, sizes.size());
    good = good && plane_ring_unrolled(sizes, ring_bits.data(), directory + "/pi_rings_unrolled.png")
        && plane_ring_unrolled(sizes, drawn.data(), directory + "/shuffled_rings_unrolled.png")
        && plane_ring_circle(sizes, ring_bits.data(), turn, sizes.size(), 1ll, directory + "/pi_rings.png")
        && plane_ring_circle(sizes, drawn.data(), turn, sizes.size(), 1ll, directory + "/shuffled_rings.png")
        && plane_ring_circle(sizes, ring_bits.data(), turn, centre, PLANE_RING_CENTRE_SCALE,
                             directory + "/pi_rings_centre.png")
        && plane_ring_circle(sizes, drawn.data(), turn, centre, PLANE_RING_CENTRE_SCALE,
                             directory + "/shuffled_rings_centre.png");
    sim_check(tally, good, "the rings are drawn for pi and for one shuffle of their bits");
    if (!good)
    {
        return 0;
    }
    const PlaneRingReading reading = plane_ring_read(sizes, ring_bits.data());
    std::vector<unsigned long long> agree_band;
    std::vector<unsigned long long> run_band;
    for (unsigned int draw = 0u; draw < draws; draw += 1u)
    {
        plane_shuffle(ring_bits, draw, &drawn);
        const PlaneRingReading drawn_reading = plane_ring_read(sizes, drawn.data());
        agree_band.push_back(drawn_reading.agree);
        run_band.push_back(drawn_reading.run);
    }
    scriptura_text(line, "  each bit against the bit at its angle one ring in: ");
    scriptura_decimal(line, reading.agree, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, reading.pairs, 1u);
    scriptura_text(line, " agree");
    plane_band_print(line, agree_band, reading.agree);
    scriptura_text(line, "  the longest chain of equal bits running outward: ");
    scriptura_decimal(line, reading.run, 1u);
    scriptura_text(line, " rings, ending on ring ");
    scriptura_decimal(line, reading.run_ring, 1u);
    scriptura_text(line, " at place ");
    scriptura_decimal(line, reading.run_place, 1u);
    plane_band_print(line, run_band, reading.run);
    scriptura_text(line, "  the pictures pi_rings.png (true radius 2^(k - 1)), pi_rings_centre.png (rings 0 to ");
    scriptura_decimal(line, centre - 1u, 1u);
    scriptura_text(line, " at twice the size) and pi_rings_unrolled.png (ring k as row k), each with its shuffle\n");
    sim_flush(tally);

    // the spirals, on the bits the pictures showed and on pi's next block of as many bits, which no picture showed
    plane_ring_spiral_read(tally, sizes, ring_bits, draws, "the rings' bits");
    if (2ull * total + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS)
    {
        scriptura_text(line, "  the next block needs an exact width of ");
        scriptura_decimal(line, (2ull * total) + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits, not read\n");
        sim_flush(tally);
        return 1;
    }
    std::vector<unsigned char> both;
    // twice the total is at most 2 PLANE_BITS_MOST, below 2^17
    const int more = plane_bits(tally, (unsigned int)(2ull * total), &both);
    sim_check(tally, more, "pi's next block of the rings' size is certified");
    if (more)
    {
        const std::vector<unsigned char> next(both.begin() + (ptrdiff_t)total, both.end());
        sim_check(tally, plane_ring_unrolled(sizes, next.data(), directory + "/pi_rings_unrolled_next.png"),
                  "the next block is drawn unrolled");
        plane_ring_spiral_read(tally, sizes, next, draws, "pi's next block, unseen");
    }
    if (more && (blind > 0u))
    {
        plane_blind(tally, sizes, 2ull * total, blind_first, blind, balanced, directory);
    }
    if (more && (funnels > 0u))
    {
        plane_funnels(tally, sizes, 2ull * total, funnels, draws, directory);
    }
    return 1;
}

// the bits under the cells a drawn path covers on a shape, the cells read as "row column" lines
static std::vector<long long> plane_path_cells(const PlaneShape &shape, const char *path)
{
    std::vector<long long> under;
    FILE *const in = fopen(path, "r");
    if (in == NULL)
    {
        return under;
    }
    long long row = 0ll;
    long long column = 0ll;
    while (fscanf(in, "%lld %lld", &row, &column) == 2)
    {
        const long long cell = plane_cell_at(shape, row, column);
        if (cell >= 0ll)
        {
            under.push_back(cell);
        }
    }
    fclose(in);
    return under;
}

static unsigned long long plane_ones_under(const std::vector<long long> &under, const unsigned char *bits)
{
    unsigned long long ones = 0ull;
    for (const long long cell : under)
    {
        ones += (unsigned long long)bits[cell];
    }
    return ones;
}

// a named text argument, or NULL where it is not given
static const char *plane_text(int count, char **arguments, const char *name)
{
    for (int argument = 1; argument + 1 < count; argument += 1)
    {
        if (strcmp(arguments[argument], name) == 0)
        {
            return arguments[argument + 1];
        }
    }
    return NULL;
}

static std::string plane_directory(int count, char **arguments)
{
    for (int argument = 1; argument + 1 < count; argument += 1)
    {
        if (strcmp(arguments[argument], "--out") == 0)
        {
            return arguments[argument + 1];
        }
    }
    const std::string program = arguments[0];
    const size_t slash = program.find_last_of("/\\");
    return (slash == std::string::npos) ? std::string(".") : program.substr(0u, slash);
}

// a named whole-number argument, or the fallback where it is not given
static unsigned int plane_number(int count, char **arguments, const char *name, unsigned int fallback)
{
    for (int argument = 1; argument + 1 < count; argument += 1)
    {
        if (strcmp(arguments[argument], name) == 0)
        {
            // a request past its most is refused by its reader, so the conversion's range does not matter here
            return (unsigned int)strtoul(arguments[argument + 1], NULL, 10);
        }
    }
    return fallback;
}

static void plane_line_print(ScripturaLine *line, const PlaneLine &found)
{
    scriptura_decimal(line, found.length, 1u);
    scriptura_text(line, " bits along (");
    scriptura_signed(line, found.step.row);
    scriptura_text(line, ", ");
    scriptura_signed(line, found.step.column);
    scriptura_text(line, ") from bit ");
    scriptura_signed(line, found.start);
}

static void plane_band_print(ScripturaLine *line, std::vector<unsigned long long> band, unsigned long long reading)
{
    std::sort(band.begin(), band.end());
    unsigned long long reached = 0ull;
    for (const unsigned long long each : band)
    {
        reached += (each >= reading) ? 1ull : 0ull;
    }
    scriptura_text(line, "; the draws: least ");
    scriptura_decimal(line, band.front(), 1u);
    scriptura_text(line, ", median ");
    scriptura_decimal(line, band[band.size() / 2u], 1u);
    scriptura_text(line, ", most ");
    scriptura_decimal(line, band.back(), 1u);
    scriptura_text(line, "; ");
    scriptura_decimal(line, reached, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, band.size(), 1u);
    scriptura_text(line, " reach pi's\n");
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    ScripturaLine *const line = &tally.line;
    const unsigned int bits_count = plane_number(count, arguments, "--bits", PLANE_BITS);
    const unsigned int draws = plane_number(count, arguments, "--draws", PLANE_DRAWS);
    const std::string directory = plane_directory(count, arguments);
    const unsigned long long needed = (unsigned long long)bits_count + PLANE_GUARD + 64ull;
    if ((bits_count < 64u) || (bits_count > PLANE_BITS_MOST) || (needed > ANCHOR_EXACT_BITS) || (draws == 0u))
    {
        unsigned long long limbs = 1ull;
        while (limbs * 32ull < needed)
        {
            limbs *= 2ull;
        }
        scriptura_text(line, "  refused: the draws are at least 1, the bits are 64 to ");
        scriptura_decimal(line, PLANE_BITS_MOST, 1u);
        scriptura_text(line, ", and the bracket needs an exact width of ");
        scriptura_decimal(line, needed, 1u);
        scriptura_text(line, " bits: run with SIM_EXACT_LIMBS=");
        scriptura_decimal(line, limbs, 1u);
        scriptura_character(line, '\n');
        sim_check(&tally, 0, "the request fits the exact width");
        return sim_close(&tally, "pi plane");
    }

    std::vector<unsigned char> bits;
    int good = plane_bits(&tally, bits_count, &bits);
    sim_flush(&tally);

    std::vector<PlaneShape> shapes(PLANE_WIDTHS + 5u);
    int laid = good;
    for (unsigned int width = 0u; laid && (width < PLANE_WIDTHS); width += 1u)
    {
        laid = plane_rows(&shapes[width], bits_count, s_plane_widths[width]);
    }
    laid = laid && plane_tower(&shapes[PLANE_WIDTHS], bits_count);
    laid = laid && plane_disc(&shapes[PLANE_WIDTHS + 1u], &shapes[PLANE_WIDTHS + 2u], bits_count);
    laid = laid && plane_spiral(&shapes[PLANE_WIDTHS + 3u], bits_count);
    laid = laid && plane_twindragon(&shapes[PLANE_WIDTHS + 4u], bits_count);
    sim_check(&tally, laid, "every shape lays each bit on its own pixel");
    good = good && laid;

    std::vector<unsigned char> drawn;
    plane_shuffle(bits, 0u, &drawn);
    int drew = good;
    for (size_t shape = 0u; drew && (shape < shapes.size()); shape += 1u)
    {
        drew = plane_picture(shapes[shape], bits.data(), directory + "/pi_" + shapes[shape].name + ".png")
            && plane_picture(shapes[shape], drawn.data(), directory + "/shuffled_" + shapes[shape].name + ".png");
    }
    sim_check(&tally, drew, "every shape is drawn for pi and for one shuffle of its bits");
    if (drew)
    {
        scriptura_text(line, "  the pictures, pi_<shape>.png and shuffled_<shape>.png, are in ");
        scriptura_text(line, directory.c_str());
        scriptura_character(line, '\n');
    }

    std::vector<unsigned int> longest(bits_count);
    std::vector<unsigned int> host_longest(bits_count);
    unsigned char *device_bits = NULL;
    unsigned int *device_longest = NULL;
    good = good && sim_job_submit(&tally, "pi_plane", count, arguments,
                                  (unsigned long long)bits_count * (1ull + sizeof(unsigned int)));
    good = good && sim_took(&tally, cudaMalloc((void **)&device_bits, bits_count), "bits");
    good = good && sim_took(&tally, cudaMalloc((void **)&device_longest, (size_t)bits_count * sizeof(unsigned int)),
                            "the lags' longest runs");
    good = good && plane_lag_device(&tally, bits.data(), bits_count, device_bits, device_longest, longest.data());
    if (good)
    {
        plane_lag_host(bits.data(), bits_count, host_longest.data());
        longest[0] = 0u;
        sim_check(&tally, memcmp(longest.data(), host_longest.data(), (size_t)bits_count * sizeof(unsigned int)) == 0,
                  "the device's longest run at every difference equals the host's, for pi");
    }

    const std::vector<PlaneStep> steps = plane_steps();
    std::vector<PlaneLine> found(shapes.size());
    for (size_t shape = 0u; good && (shape < shapes.size()); shape += 1u)
    {
        found[shape] = plane_longest_line(shapes[shape], bits.data(), steps);
    }
    if (good)
    {
        const PlaneShape &rings = shapes[PLANE_WIDTHS + 2u];
        const PlaneLine &spoke = found[PLANE_WIDTHS + 2u];
        std::vector<unsigned char> first_drawn;
        plane_shuffle(bits, 0u, &first_drawn);
        const PlaneLine drawn_line = plane_longest_line(rings, first_drawn.data(), steps);
        const int sparse = plane_sparse_picture(rings, bits.data(), spoke, directory + "/pi_disc_rings_sparse.png")
                        && plane_sparse_picture(rings, first_drawn.data(), drawn_line,
                                                directory + "/shuffled_disc_rings_sparse.png");
        sim_check(&tally, sparse, "the ring-filled disc is drawn sparse, its longest line in red");
        scriptura_text(line, "  the sparse ring: pi's longest line on the ring-filled disc is ");
        plane_line_print(line, spoke);
        scriptura_text(line, ", every bit of it a ");
        scriptura_decimal(line, bits[(size_t)spoke.start], 1u);
        scriptura_text(line, "; the shuffle's is ");
        plane_line_print(line, drawn_line);
        scriptura_character(line, '\n');
        sim_flush(&tally);
    }
    unsigned int pi_lag = 0u;
    const unsigned int pi_lag_length = good ? plane_lag_most(longest.data(), bits_count, &pi_lag) : 0u;

    std::vector<std::vector<unsigned long long>> band(shapes.size());
    std::vector<unsigned long long> lag_band;
    std::vector<unsigned int> drawn_longest(bits_count);
    std::vector<std::vector<unsigned long long>> spread_band(2u * PLANE_SCALES);
    const PlaneShape &dragon = shapes[PLANE_WIDTHS + 4u];
    std::vector<unsigned int> dragon_depth;
    if (good)
    {
        dragon_depth = plane_depth(dragon);
    }
    std::vector<unsigned long long> depth_band;
    unsigned long long depth_ones[PLANE_DEPTHS + 1u];
    unsigned long long depth_sizes[PLANE_DEPTHS + 1u];

    // the sphere: the widest integer shell the bits fill, bit n at the n-th point by latitude circles or by meridians
    long long sphere_radius = 0ll;
    std::vector<std::vector<PlaneSpherePoint>> sphere_orders(2u);
    std::vector<PlaneShape> spheres(2u);
    size_t sphere_count = 0u;
    if (good)
    {
        sphere_orders[0] = plane_shell(bits_count, &sphere_radius);
        sphere_orders[1] = sphere_orders[0];
        std::sort(sphere_orders[0].begin(), sphere_orders[0].end(), plane_latitude_before);
        std::sort(sphere_orders[1].begin(), sphere_orders[1].end(), plane_meridian_before);
        plane_sphere_views(&spheres[0], "sphere_latitudes", sphere_orders[0], sphere_radius);
        plane_sphere_views(&spheres[1], "sphere_meridians", sphere_orders[1], sphere_radius);
        sphere_count = sphere_orders[0].size();
    }
    const std::vector<unsigned char> sphere_bits(bits.begin(), bits.begin() + (ptrdiff_t)sphere_count);
    std::vector<unsigned char> sphere_drawn;
    plane_shuffle(sphere_bits, 0u, &sphere_drawn);
    int sphere_drew = good && (sphere_count > 0u);
    for (size_t fill = 0u; sphere_drew && (fill < spheres.size()); fill += 1u)
    {
        sphere_drew = plane_picture(spheres[fill], sphere_bits.data(), directory + "/pi_" + spheres[fill].name + ".png")
                   && plane_picture(spheres[fill], sphere_drawn.data(),
                                    directory + "/shuffled_" + spheres[fill].name + ".png");
    }
    sim_check(&tally, sphere_drew, "the sphere is laid and drawn for pi and for one shuffle of its bits");
    good = good && sphere_drew;
    std::vector<PlaneLine> sphere_found(spheres.size());
    std::vector<unsigned long long> sphere_latitude(spheres.size(), 0ull);
    for (size_t fill = 0u; good && (fill < spheres.size()); fill += 1u)
    {
        sphere_found[fill] = plane_longest_line(spheres[fill], sphere_bits.data(), steps);
        sphere_latitude[fill] = plane_latitude_spread(sphere_orders[fill], sphere_radius, sphere_bits.data());
    }
    std::vector<std::vector<unsigned long long>> sphere_line_band(spheres.size());
    std::vector<std::vector<unsigned long long>> sphere_latitude_band(spheres.size());
    std::vector<std::vector<unsigned long long>> fibonacci_band(PLANE_FIBONACCI + 1u);
    int shuffled = good;
    for (unsigned int draw = 0u; shuffled && (draw < draws); draw += 1u)
    {
        plane_shuffle(bits, draw, &drawn);
        shuffled = plane_lag_device(&tally, drawn.data(), bits_count, device_bits, device_longest,
                                    drawn_longest.data());
        unsigned int drawn_lag = 0u;
        lag_band.push_back(plane_lag_most(drawn_longest.data(), bits_count, &drawn_lag));
        for (size_t shape = 0u; shuffled && (shape < shapes.size()); shape += 1u)
        {
            band[shape].push_back(plane_longest_line(shapes[shape], drawn.data(), steps).length);
        }
        for (unsigned int kind = 0u; kind < 2u * PLANE_SCALES; kind += 1u)
        {
            // the kind's low bit chooses residues or blocks
            spread_band[kind].push_back(plane_spread(drawn.data(), bits_count, (kind / 2u) + 1u, (int)(kind % 2u)));
        }
        depth_band.push_back(plane_depth_spread(dragon, dragon_depth, drawn.data(), depth_ones, depth_sizes));
        plane_shuffle(sphere_bits, draw, &sphere_drawn);
        for (size_t fill = 0u; fill < spheres.size(); fill += 1u)
        {
            sphere_line_band[fill].push_back(plane_longest_line(spheres[fill], sphere_drawn.data(), steps).length);
            sphere_latitude_band[fill].push_back(plane_latitude_spread(sphere_orders[fill], sphere_radius,
                                                                       sphere_drawn.data()));
        }
        unsigned long long golden_most = 0ull;
        for (unsigned int fibonacci = 0u; fibonacci < PLANE_FIBONACCI; fibonacci += 1u)
        {
            const unsigned long long run = (s_plane_fibonacci[fibonacci] < bits_count)
                                               ? drawn_longest[s_plane_fibonacci[fibonacci]]
                                               : 0ull;
            fibonacci_band[fibonacci].push_back(run);
            golden_most = std::max(golden_most, run);
        }
        fibonacci_band[PLANE_FIBONACCI].push_back(golden_most);
    }
    sim_check(&tally, shuffled, "every draw is shuffled and read");

    if (good && shuffled)
    {
        scriptura_text(line, "  every width at once, the longest run of equal bits at any difference 1 to ");
        scriptura_decimal(line, bits_count - 1u, 1u);
        scriptura_text(line, ": ");
        scriptura_decimal(line, pi_lag_length, 1u);
        scriptura_text(line, " at difference ");
        scriptura_decimal(line, pi_lag, 1u);
        plane_band_print(line, lag_band, pi_lag_length);
        std::vector<unsigned int> order(bits_count - 1u);
        for (unsigned int lag = 1u; lag < bits_count; lag += 1u)
        {
            order[lag - 1u] = lag;
        }
        std::stable_sort(order.begin(), order.end(),
                         [&longest](unsigned int left, unsigned int right) { return longest[left] > longest[right]; });
        scriptura_text(line, "  pi's longest runs by difference:");
        for (unsigned int rank = 0u; rank < PLANE_TOP_LAGS; rank += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_decimal(line, longest[order[rank]], 1u);
            scriptura_text(line, " at ");
            scriptura_decimal(line, order[rank], 1u);
        }
        scriptura_character(line, '\n');
        scriptura_text(line, "  pi's floors as differences:");
        const unsigned int floors[3] = {7u, 106u, 113u};
        for (unsigned int floor = 0u; floor < 3u; floor += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_decimal(line, longest[floors[floor]], 1u);
            scriptura_text(line, " at ");
            scriptura_decimal(line, floors[floor], 1u);
        }
        scriptura_character(line, '\n');
        sim_flush(&tally);
        for (size_t shape = 0u; shape < shapes.size(); shape += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_text(line, shapes[shape].name.c_str());
            scriptura_text(line, " (");
            scriptura_decimal(line, shapes[shape].width, 1u);
            scriptura_text(line, " x ");
            scriptura_decimal(line, shapes[shape].height, 1u);
            scriptura_text(line, "): pi's longest line ");
            plane_line_print(line, found[shape]);
            plane_band_print(line, band[shape], found[shape].length);
            sim_flush(&tally);
        }
        scriptura_text(line, "  the ones' spread, sum over the classes of (2 ones - size)^2; a residue is one place on every");
        scriptura_text(line, " arm of the twindragon, a block one whole sub-dragon\n");
        for (unsigned int kind = 0u; kind < 2u * PLANE_SCALES; kind += 1u)
        {
            const unsigned int scale = (kind / 2u) + 1u;
            // the kind's low bit chooses residues or blocks
            const unsigned long long reading = plane_spread(bits.data(), bits_count, scale, (int)(kind % 2u));
            scriptura_text(line, ((kind % 2u) == 0u) ? "  residues mod 2^" : "  blocks, 2^");
            scriptura_decimal(line, scale, 1u);
            scriptura_text(line, ((kind % 2u) == 0u) ? ": pi's spread " : " of them: pi's spread ");
            scriptura_decimal(line, reading, 1u);
            plane_band_print(line, spread_band[kind], reading);
            sim_flush(&tally);
        }
        const unsigned long long depth_reading = plane_depth_spread(dragon, dragon_depth, bits.data(), depth_ones,
                                                                    depth_sizes);
        scriptura_text(line, "  the twindragon by depth from its edge, 1 the arm points and the lace to ");
        scriptura_decimal(line, PLANE_DEPTHS, 1u);
        scriptura_text(line, " and deeper the middle; pi's ones of the pixels at each depth:");
        for (unsigned int level = 1u; level <= PLANE_DEPTHS; level += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_decimal(line, depth_ones[level], 1u);
            scriptura_character(line, '/');
            scriptura_decimal(line, depth_sizes[level], 1u);
        }
        scriptura_text(line, "\n  pi's spread over the depths ");
        scriptura_decimal(line, depth_reading, 1u);
        plane_band_print(line, depth_band, depth_reading);
        sim_flush(&tally);

        scriptura_text(line, "  the sphere: the integer shell of radius ");
        scriptura_signed(line, sphere_radius);
        scriptura_text(line, ", ");
        scriptura_decimal(line, sphere_count, 1u);
        scriptura_text(line, " points, holding pi's first ");
        scriptura_decimal(line, sphere_count, 1u);
        scriptura_text(line, " bits, seen from +z, -z, +x and -x\n");
        for (size_t fill = 0u; fill < spheres.size(); fill += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_text(line, spheres[fill].name.c_str());
            scriptura_text(line, ": pi's longest line on the views ");
            plane_line_print(line, sphere_found[fill]);
            plane_band_print(line, sphere_line_band[fill], sphere_found[fill].length);
            scriptura_text(line, "  ");
            scriptura_text(line, spheres[fill].name.c_str());
            scriptura_text(line, ": pi's spread over the circles of latitude ");
            scriptura_decimal(line, sphere_latitude[fill], 1u);
            plane_band_print(line, sphere_latitude_band[fill], sphere_latitude[fill]);
            sim_flush(&tally);
        }
        scriptura_text(line, "  the golden sphere's spirals, pi's longest run at each Fibonacci difference:\n");
        unsigned long long golden_most = 0ull;
        for (unsigned int fibonacci = 0u; fibonacci < PLANE_FIBONACCI; fibonacci += 1u)
        {
            if (s_plane_fibonacci[fibonacci] >= bits_count)
            {
                continue;
            }
            const unsigned long long run = longest[s_plane_fibonacci[fibonacci]];
            golden_most = std::max(golden_most, run);
            scriptura_text(line, "    F = ");
            scriptura_decimal(line, s_plane_fibonacci[fibonacci], 1u);
            scriptura_text(line, ": ");
            scriptura_decimal(line, run, 1u);
            plane_band_print(line, fibonacci_band[fibonacci], run);
        }
        scriptura_text(line, "  the longest over every Fibonacci difference ");
        scriptura_decimal(line, golden_most, 1u);
        plane_band_print(line, fibonacci_band[PLANE_FIBONACCI], golden_most);
        sim_flush(&tally);
    }

    if (good)
    {
        plane_rings(&tally, bits, draws, plane_number(count, arguments, "--blind", 0u),
                    plane_number(count, arguments, "--blind-from", 0u),
                    plane_number(count, arguments, "--balanced", 0u) != 0u, plane_number(count, arguments, "--funnels", 0u),
                    directory);
    }

    // a path drawn over the ring-filled disc: pi's ones under it against the same cells in each shuffle
    const char *const cells_path = plane_text(count, arguments, "--cells");
    if (good && (cells_path != NULL))
    {
        const std::vector<long long> under = plane_path_cells(shapes[PLANE_WIDTHS + 2u], cells_path);
        const unsigned long long ones = plane_ones_under(under, bits.data());
        std::vector<unsigned long long> path_band;
        unsigned long long at_or_below = 0ull;
        for (unsigned int draw = 0u; draw < draws; draw += 1u)
        {
            plane_shuffle(bits, draw, &drawn);
            const unsigned long long drawn_ones = plane_ones_under(under, drawn.data());
            path_band.push_back(drawn_ones);
            at_or_below += (drawn_ones <= ones) ? 1ull : 0ull;
        }
        scriptura_text(line, "  the drawn path: ");
        scriptura_decimal(line, under.size(), 1u);
        scriptura_text(line, " cells of the ring-filled disc, pi's ones on them ");
        scriptura_decimal(line, ones, 1u);
        scriptura_text(line, ", its zeros ");
        scriptura_decimal(line, under.size() - ones, 1u);
        scriptura_text(line, "; ");
        scriptura_decimal(line, at_or_below, 1u);
        scriptura_text(line, " of the draws at or below pi's ones");
        if (!under.empty() && !path_band.empty())
        {
            plane_band_print(line, path_band, ones);
        }
        else
        {
            scriptura_character(line, '\n');
        }
        sim_check(&tally, !under.empty(), "the drawn path lies on the disc");
        sim_flush(&tally);
    }

    cudaFree(device_bits);
    cudaFree(device_longest);
    return sim_close(&tally, "pi plane");
}
