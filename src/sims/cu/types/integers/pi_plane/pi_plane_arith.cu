// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_arith.cu: exact arithmetic, shapes and orders
#include "pi_plane_internal.h"

static int s_plane_error = 0;

static void plane_took(AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        s_plane_error = 1;
    }
}

static AnchorExactInteger plane_exact_unsigned(unsigned long long number)
{
    AnchorExactInteger value;
    sim_exact_unsigned(&value, number);
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
    const AnchorExactInteger square = plane_exact_unsigned(x * x);
    AnchorExactInteger power = plane_quotient(plane_power_two(bits), plane_exact_unsigned(x));
    AnchorExactInteger total = plane_exact_unsigned(0ull);
    unsigned long long index = 0ull;
    *terms = 0ull;
    while (power.sign != 0)
    {
        const AnchorExactInteger term = plane_quotient(power, plane_exact_unsigned((2ull * index) + 1ull));
        total = ((index & 1ull) == 0ull) ? plane_sum(total, term) : plane_difference(total, term);
        *terms += 1ull;
        power = plane_quotient(power, square);
        index += 1ull;
    }
    return total;
}

// the bits of pi - 3 after the point, most significant first, where Machin's bracket agrees on all of them
int plane_bits(SimResults *results, unsigned int count, std::vector<unsigned char> *bits)
{
    const unsigned int precision = count + PLANE_GUARD;
    unsigned long long fifth_terms = 0ull;
    unsigned long long far_terms = 0ull;
    const AnchorExactInteger fifth = plane_arctan(5ull, precision, &fifth_terms);
    const AnchorExactInteger far = plane_arctan(239ull, precision, &far_terms);
    const AnchorExactInteger middle = plane_difference(plane_product(fifth, plane_exact_unsigned(16ull)),
                                                       plane_product(far, plane_exact_unsigned(4ull)));
    const AnchorExactInteger spread =
        plane_exact_unsigned((16ull * (fifth_terms + 1ull)) + (4ull * (far_terms + 1ull)));
    const AnchorExactInteger guard = plane_power_two(PLANE_GUARD);
    const AnchorExactInteger below = plane_quotient(plane_difference(middle, spread), guard);
    const AnchorExactInteger above = plane_quotient(plane_sum(middle, spread), guard);
    const int agree = (s_plane_error == 0) && (anchor_exact_compare(&below, &above) == 0);
    const AnchorExactInteger turn =
        plane_difference(below, plane_product(plane_exact_unsigned(3ull), plane_power_two(count)));
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
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  pi by Machin's formula at ");
    scriptura_decimal(line, precision, 1u);
    scriptura_text(line, " bits, ");
    scriptura_decimal(line, fifth_terms + far_terms, 1u);
    scriptura_text(line, " terms: ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " bits after the point, ");
    scriptura_decimal(line, ones, 1u);
    scriptura_text(line, " of them ones\n");
    sim_check(results, agree, "floor((pi - 3) 2^N) is one integer at both ends of Machin's bracket");
    sim_check(results, leading == PLANE_PUBLISHED_BITS, "pi's first 64 bits after the point are 0x243F6A8885A308D3");
    return agree && (leading == PLANE_PUBLISHED_BITS);
}

// the shape's pixels from each bit's place; 0 where two bits land on one pixel
int plane_extent_place(PlaneExtent *extent, const std::string &name, const std::vector<long long> &rows,
                       const std::vector<long long> &columns)
{
    extent->name = name;
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
    // both spans are at least one and below the bit count. They widen to unsigned exactly
    extent->height = (unsigned long long)(bottom - top + 1ll);
    extent->width = (unsigned long long)(right - left + 1ll);
    extent->cell.assign((size_t)(extent->height * extent->width), -1ll);
    for (size_t bit = 0u; bit < rows.size(); bit += 1u)
    {
        // the offsets from the top left corner are never negative
        const size_t index =
            (size_t)((unsigned long long)(rows[bit] - top) * extent->width + (unsigned long long)(columns[bit] - left));
        if (extent->cell[index] >= 0ll)
        {
            return 0;
        }
        // a bit's index is below 2^15. It fits a signed word
        extent->cell[index] = (long long)bit;
    }
    return 1;
}

int plane_rows(PlaneExtent *extent, unsigned int count, unsigned long long width)
{
    std::vector<long long> rows(count);
    std::vector<long long> columns(count);
    for (unsigned int bit = 0u; bit < count; bit += 1u)
    {
        // the row and column are below the bit count. They fit a signed word
        rows[bit] = (long long)(bit / width);
        columns[bit] = (long long)(bit % width);
    }
    return plane_extent_place(extent, "rows_" + std::to_string(width), rows, columns);
}

// row k holds k + 1 bits, left aligned
int plane_tower(PlaneExtent *extent, unsigned int count)
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
        // the bit's index is below 2^15. It fits a signed word
        columns[bit] = (long long)bit - start;
    }
    return plane_extent_place(extent, "tower", rows, columns);
}

int plane_half(const PlanePoint &point)
{
    return (point.y < 0ll) || ((point.y == 0ll) && (point.x < 0ll));
}

// by the square of the radius, then counterclockwise from the positive x axis, in integers
bool plane_ring_before(const PlanePoint &left, const PlanePoint &right)
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

bool plane_raster_before(const PlanePoint &left, const PlanePoint &right)
{
    if (left.y != right.y)
    {
        return left.y > right.y;
    }
    return left.x < right.x;
}
