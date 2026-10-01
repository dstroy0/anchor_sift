// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_funnels.cu: the blind reading and funnels
#include "pi_plane_internal.h"

// blind pairs: pi's unseen blocks, from block first past
// the seen bits, each laid out in the rings unrolled beside a shuffle of the same block, which is which decided by a
// keyed coin, or where balanced by a keyed deal of pi to A in exactly half the pairs, and written only to
// blind_answer.txt. The coin is keyed by the block and the deal by the first block. A round from --blind-from deals its
// own sides; the round from block 0 keeps the sides it was shown with
int plane_blind(SimResults *results, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                unsigned int first, unsigned int pairs, int balanced, const std::string &directory)
{
    ScripturaLine *const line = &results->line;
    const std::vector<unsigned long long> rings(
        sizes.begin(), sizes.begin() + (ptrdiff_t)std::min<size_t>(PLANE_BLIND_RINGS, sizes.size()));
    const unsigned long long block = plane_ring_total(rings);
    const unsigned long long needed = seen + ((first + pairs) * block);
    if ((first + pairs > PLANE_BLIND_MAX) || (needed + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the blind pairs lie in the first ");
        scriptura_decimal(line, PLANE_BLIND_MAX, 1u);
        scriptura_text(line, " blocks and need an exact width of ");
        scriptura_decimal(line, needed + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits\n");
        sim_check(results, 0, "the blind pairs fit the exact width");
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
        // the draw is below the pair count. It narrows to unsigned int exactly
        const unsigned int other = (unsigned int)sim_draw_below(
            PLANE_KEY ^ 0x42414C414E4345ull ^ ((unsigned long long)first << 32u), pair - 1u, pair);
        std::swap(sides[pair - 1u], sides[other]);
    }
    std::vector<unsigned char> all;
    // the bits needed are at most 2^18 or so, far below 2^32
    int ok = plane_bits(results, (unsigned int)needed, &all);
    FILE *const answer = ok ? fopen((directory + "/blind_answer.txt").c_str(), "w") : NULL;
    ok = ok && (answer != NULL);
    for (unsigned int pair = 0u; ok && (pair < pairs); pair += 1u)
    {
        const size_t from = (size_t)(seen + ((first + pair) * block));
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)from, all.begin() + (ptrdiff_t)(from + block));
        std::vector<unsigned char> other;
        plane_shuffle(mine, 7919u + first + pair, &other);
        const int pi_first =
            balanced ? (sides[pair] != 0u) : ((sim_draw(PLANE_KEY ^ 0x424C494E44ull, first + pair) & 1ull) == 0ull);
        const std::string stem = directory + "/blind_" + std::to_string(pair + 1u);
        ok = plane_ring_unrolled(rings, pi_first ? mine.data() : other.data(), stem + "_A.png") &&
             plane_ring_unrolled(rings, pi_first ? other.data() : mine.data(), stem + "_B.png");
        fprintf(answer, "pair %u: pi is %s (pi's bits %llu to %llu)\n", pair + 1u, pi_first ? "A" : "B",
                (unsigned long long)from + 1ull, (unsigned long long)(from + block));
    }
    if (answer != NULL)
    {
        ok = (fclose(answer) == 0) && ok;
    }
    sim_check(results, ok, "the blind pairs are drawn and their answer written");
    scriptura_text(line, "  blind: ");
    scriptura_decimal(line, pairs, 1u);
    scriptura_text(line, " pairs, blind_<n>_A.png and blind_<n>_B.png, rings 0 to ");
    scriptura_decimal(line, rings.size() - 1u, 1u);
    scriptura_text(line, " unrolled; each pair is one unseen block of pi from bit ");
    scriptura_decimal(line, seen + (first * block) + 1ull, 1u);
    scriptura_text(line, " on and a shuffle of the same block; ");
    scriptura_text(line, balanced ? "pi is A in exactly half the pairs, dealt by a keyed shuffle; " : "");
    scriptura_text(line, "which is pi is in blind_answer.txt and nowhere else\n");
    sim_flush(results);
    return ok;
}

// the funnels. A funnel's mouth is a run of two equal bits or more on rings 1 to PLANE_FUNNEL_MOUTH_LAST; each bar below
// it is the widest run of the same bit among the cells whose parent lies under the bar above, and the funnel ends on
// the ring where no such cell holds the bit. Its depth is how many bars it has below the mouth, the dense rings, two
// bits or more to a pixel, included; three bars w0, w1, w2, each in turns, fit one ratio as w1^2 comes near w0 w2.
#define PLANE_FUNNEL_MOUTH_LAST 8u

#define PLANE_FUNNEL_FRESH_MAX 16u

// the funnels drawn over a picture are those from a mouth this many bits wide or wider that reach the last ring
#define PLANE_FUNNEL_DRAWN_MOUTH 3ull

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
static void plane_funnel_trace(const std::vector<unsigned long long> &sizes,
                               const std::vector<unsigned long long> &starts, const unsigned char *bits, size_t ring,
                               unsigned long long first, unsigned long long last, std::vector<PlaneBar> *bars)
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

// how near three bars come to one ratio, in millionths: the smaller of w1^2 and w0 w2 over the larger, with w = bits /
// c_k
static unsigned long long plane_funnel_fit(const std::vector<unsigned long long> &sizes, const PlaneBar *bar)
{
    const unsigned long long wide = bar[0].last - bar[0].first + 1ull;
    const unsigned long long middle = bar[1].last - bar[1].first + 1ull;
    const unsigned long long narrow = bar[2].last - bar[2].first + 1ull;
    // w1^2 against w0 w2 is middle^2 c_k c_(k + 2) against wide narrow c_(k + 1)^2; every width and size is below
    // 2^13. Each product stays under 2^52
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

// every funnel of the block: the bars below every mouth summed, the mean fit of every three bars whose first is two
// bits or wider, and the bits agreeing with their parent
static PlaneFunnelMeasurement plane_funnel_read(const std::vector<unsigned long long> &sizes,
                                                const std::vector<unsigned long long> &starts,
                                                const unsigned char *bits)
{
    PlaneFunnelMeasurement measurement = {{0ull, 0ull, plane_ring_read(sizes, bits).agree}};
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
                measurement.value[0] += bars.size() - 1u;
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
    measurement.value[1] = (triples == 0ull) ? 0ull : (fit / triples);
    return measurement;
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
static void plane_funnel_blocks(SimResults *results, const std::vector<unsigned long long> &sizes,
                                const std::vector<unsigned char> &all, unsigned long long from, unsigned int blocks,
                                unsigned int draws, const char *label)
{
    ScripturaLine *const line = &results->line;
    const std::vector<unsigned long long> starts = plane_ring_starts(sizes);
    const unsigned long long block = plane_ring_total(sizes);
    PlaneFunnelMeasurement pi_total = {{0ull, 0ull, 0ull}};
    std::vector<PlaneFunnelMeasurement> drawn_total(draws, pi_total);
    std::vector<std::vector<unsigned long long>> reached(PLANE_FUNNEL_READINGS,
                                                         std::vector<unsigned long long>(blocks, 0ull));
    std::vector<unsigned char> drawn;
    for (unsigned int each = 0u; each < blocks; each += 1u)
    {
        const size_t at = (size_t)(from + (each * block));
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)at, all.begin() + (ptrdiff_t)(at + block));
        const PlaneFunnelMeasurement measurement = plane_funnel_read(sizes, starts, mine.data());
        for (unsigned int kind = 0u; kind < PLANE_FUNNEL_READINGS; kind += 1u)
        {
            pi_total.value[kind] += measurement.value[kind];
        }
        for (unsigned int draw = 0u; draw < draws; draw += 1u)
        {
            plane_shuffle(mine, draw, &drawn);
            const PlaneFunnelMeasurement drawn_measurement = plane_funnel_read(sizes, starts, drawn.data());
            for (unsigned int kind = 0u; kind < PLANE_FUNNEL_READINGS; kind += 1u)
            {
                drawn_total[draw].value[kind] += drawn_measurement.value[kind];
                reached[kind][each] += (drawn_measurement.value[kind] >= measurement.value[kind]) ? 1ull : 0ull;
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
        sim_flush(results);
    }
}

// the funnels on the six blind blocks the eye picked pi from, then on fresh blocks past them that no picture showed;
// the first blind pair, pi and the shuffle it was shown beside, drawn with their funnels
int plane_funnels(SimResults *results, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                  unsigned int fresh, unsigned int draws, const std::string &directory)
{
    ScripturaLine *const line = &results->line;
    const std::vector<unsigned long long> rings(
        sizes.begin(), sizes.begin() + (ptrdiff_t)std::min<size_t>(PLANE_BLIND_RINGS, sizes.size()));
    const unsigned long long block = plane_ring_total(rings);
    const unsigned long long needed = seen + ((PLANE_BLIND_SCORED + fresh) * block);
    if ((fresh > PLANE_FUNNEL_FRESH_MAX) || (needed + PLANE_GUARD + 64ull > ANCHOR_EXACT_BITS))
    {
        scriptura_text(line, "  the funnels read at most ");
        scriptura_decimal(line, PLANE_FUNNEL_FRESH_MAX, 1u);
        scriptura_text(line, " fresh blocks and need an exact width of ");
        scriptura_decimal(line, needed + PLANE_GUARD + 64ull, 1u);
        scriptura_text(line, " bits\n");
        sim_check(results, 0, "the funnels' blocks fit the exact width");
        return 0;
    }
    std::vector<unsigned char> all;
    // the bits needed are at most 2^18 or so, far below 2^32
    int ok = plane_bits(results, (unsigned int)needed, &all);
    if (ok)
    {
        const std::vector<unsigned char> mine(all.begin() + (ptrdiff_t)seen, all.begin() + (ptrdiff_t)(seen + block));
        std::vector<unsigned char> other;
        plane_shuffle(mine, 7919u, &other);
        ok = plane_funnel_picture(rings, mine.data(), directory + "/funnels_pi.png") &&
             plane_funnel_picture(rings, other.data(), directory + "/funnels_shuffled.png");
        sim_check(results, ok, "the first blind pair is drawn with its funnels");
    }
    if (ok)
    {
        scriptura_text(line, "  the funnels: mouths of two bits or more on rings 1 to ");
        scriptura_decimal(line, PLANE_FUNNEL_MOUTH_LAST, 1u);
        scriptura_text(line, ", traced to ring ");
        scriptura_decimal(line, rings.size() - 1u, 1u);
        scriptura_text(line,
                       "; funnels_pi.png and funnels_shuffled.png are the first blind pair, the funnels from a mouth ");
        scriptura_decimal(line, PLANE_FUNNEL_DRAWN_MOUTH, 1u);
        scriptura_text(line, " bits wide or wider that reach the last ring in red\n");
        sim_flush(results);
        plane_funnel_blocks(results, rings, all, seen, PLANE_BLIND_SCORED, draws, "the six blind blocks");
        if (fresh > 0u)
        {
            plane_funnel_blocks(results, rings, all, seen + (PLANE_BLIND_SCORED * block), fresh, draws,
                                "fresh blocks, unseen");
        }
    }
    return ok;
}
