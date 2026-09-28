// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_ring_report.cu: rings, paths and printing
#include "pi_plane_internal.h"

// the rings mod floor(pi 2^k) (Doug, 24 September: "make each ring the mod of a known digit"): drawn, and each bit
// read against the bit at its angle one ring in, against keyed shuffles of the rings' bits
int plane_rings(SimResults *results, const std::vector<unsigned char> &bits, unsigned int draws, unsigned int blind,
                unsigned int blind_first, int balanced, unsigned int funnels, const std::string &directory)
{
    ScripturaLine *const line = &results->line;
    const std::vector<unsigned long long> sizes = plane_ring_sizes(bits, PLANE_BITS_MAX);
    const unsigned long long total = plane_ring_total(sizes);
    if ((sizes.size() < 2u) || (total + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the rings need ");
        scriptura_decimal(line, total, 1u);
        scriptura_text(line, " bits and a wider exact integer\n");
        sim_check(results, 0, "the rings fit the exact width");
        return 0;
    }
    std::vector<unsigned char> ring_bits(bits.begin(), bits.begin() + (ptrdiff_t)std::min<size_t>(bits.size(), total));
    // the bits are unsigned int wide, and the total is at most PLANE_BITS_MAX
    int ok = (ring_bits.size() == total) || plane_bits(results, (unsigned int)total, &ring_bits);
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
    const size_t center = std::min<size_t>(PLANE_RING_CENTER, sizes.size());
    ok = ok && plane_ring_unrolled(sizes, ring_bits.data(), directory + "/pi_rings_unrolled.png") &&
         plane_ring_unrolled(sizes, drawn.data(), directory + "/shuffled_rings_unrolled.png") &&
         plane_ring_circle(sizes, ring_bits.data(), turn, sizes.size(), 1ll, directory + "/pi_rings.png") &&
         plane_ring_circle(sizes, drawn.data(), turn, sizes.size(), 1ll, directory + "/shuffled_rings.png") &&
         plane_ring_circle(sizes, ring_bits.data(), turn, center, PLANE_RING_CENTER_SCALE,
                           directory + "/pi_rings_center.png") &&
         plane_ring_circle(sizes, drawn.data(), turn, center, PLANE_RING_CENTER_SCALE,
                           directory + "/shuffled_rings_center.png");
    sim_check(results, ok, "the rings are drawn for pi and for one shuffle of their bits");
    if (!ok)
    {
        return 0;
    }
    const PlaneRingMeasurement measurement = plane_ring_read(sizes, ring_bits.data());
    std::vector<unsigned long long> agree_band;
    std::vector<unsigned long long> run_band;
    for (unsigned int draw = 0u; draw < draws; draw += 1u)
    {
        plane_shuffle(ring_bits, draw, &drawn);
        const PlaneRingMeasurement drawn_measurement = plane_ring_read(sizes, drawn.data());
        agree_band.push_back(drawn_measurement.agree);
        run_band.push_back(drawn_measurement.run);
    }
    scriptura_text(line, "  each bit against the bit at its angle one ring in: ");
    scriptura_decimal(line, measurement.agree, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, measurement.pairs, 1u);
    scriptura_text(line, " agree");
    plane_band_print(line, agree_band, measurement.agree);
    scriptura_text(line, "  the longest chain of equal bits running outward: ");
    scriptura_decimal(line, measurement.run, 1u);
    scriptura_text(line, " rings, ending on ring ");
    scriptura_decimal(line, measurement.run_ring, 1u);
    scriptura_text(line, " at place ");
    scriptura_decimal(line, measurement.run_place, 1u);
    plane_band_print(line, run_band, measurement.run);
    scriptura_text(line, "  the pictures pi_rings.png (true radius 2^(k - 1)), pi_rings_center.png (rings 0 to ");
    scriptura_decimal(line, center - 1u, 1u);
    scriptura_text(line, " at twice the size) and pi_rings_unrolled.png (ring k as row k), each with its shuffle\n");
    sim_flush(results);

    // the spirals, on the bits the pictures showed and on pi's next block of as many bits, which no picture showed
    plane_ring_spiral_read(results, sizes, ring_bits, draws, "the rings' bits");
    if (2ull * total + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS)
    {
        scriptura_text(line, "  the next block needs an exact width of ");
        scriptura_decimal(line, (2ull * total) + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits, not read\n");
        sim_flush(results);
        return 1;
    }
    std::vector<unsigned char> both;
    // twice the total is at most 2 PLANE_BITS_MAX, below 2^17
    const int more = plane_bits(results, (unsigned int)(2ull * total), &both);
    sim_check(results, more, "pi's next block of the rings' size is certified");
    if (more)
    {
        const std::vector<unsigned char> next(both.begin() + (ptrdiff_t)total, both.end());
        sim_check(results, plane_ring_unrolled(sizes, next.data(), directory + "/pi_rings_unrolled_next.png"),
                  "the next block is drawn unrolled");
        plane_ring_spiral_read(results, sizes, next, draws, "pi's next block, unseen");
    }
    if (more && (blind > 0u))
    {
        plane_blind(results, sizes, 2ull * total, blind_first, blind, balanced, directory);
    }
    if (more && (funnels > 0u))
    {
        plane_funnels(results, sizes, 2ull * total, funnels, draws, directory);
    }
    return 1;
}

// the bits under the cells a drawn path covers on a shape, the cells read as "row column" lines
std::vector<long long> plane_path_cells(const PlaneExtent &extent, const char *path)
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
        const long long cell = plane_cell_at(extent, row, column);
        if (cell >= 0ll)
        {
            under.push_back(cell);
        }
    }
    fclose(in);
    return under;
}

unsigned long long plane_ones_under(const std::vector<long long> &under, const unsigned char *bits)
{
    unsigned long long ones = 0ull;
    for (const long long cell : under)
    {
        ones += (unsigned long long)bits[cell];
    }
    return ones;
}

// a named text argument, or NULL where it is not given
const char *plane_text(int count, char **arguments, const char *name)
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

std::string plane_directory(int count, char **arguments)
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
unsigned int plane_number(int count, char **arguments, const char *name, unsigned int fallback)
{
    for (int argument = 1; argument + 1 < count; argument += 1)
    {
        if (strcmp(arguments[argument], name) == 0)
        {
            // a request past its most is refused by its reader. The conversion's range does not matter here
            return (unsigned int)strtoul(arguments[argument + 1], NULL, 10);
        }
    }
    return fallback;
}

void plane_line_print(ScripturaLine *line, const PlaneLine &found)
{
    scriptura_decimal(line, found.length, 1u);
    scriptura_text(line, " bits along (");
    scriptura_signed(line, found.step.row);
    scriptura_text(line, ", ");
    scriptura_signed(line, found.step.column);
    scriptura_text(line, ") from bit ");
    scriptura_signed(line, found.start);
}

void plane_band_print(ScripturaLine *line, std::vector<unsigned long long> band, unsigned long long measurement)
{
    std::sort(band.begin(), band.end());
    unsigned long long reached = 0ull;
    for (const unsigned long long each : band)
    {
        reached += (each >= measurement) ? 1ull : 0ull;
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
