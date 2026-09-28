// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_main.cu: main
#include "pi_plane_internal.h"

static const unsigned int s_plane_fibonacci[PLANE_FIBONACCI] = {
    1u, 2u, 3u, 5u, 8u, 13u, 21u, 34u, 55u, 89u, 144u, 233u, 377u, 610u, 987u, 1597u, 2584u, 4181u, 6765u, 10946u};

static const unsigned long long s_plane_widths[PLANE_WIDTHS] = {7ull,   16ull,  32ull,  64ull,
                                                                106ull, 113ull, 128ull, 256ull};

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    ScripturaLine *const line = &results.line;
    const unsigned int bits_count = plane_number(count, arguments, "--bits", PLANE_BITS);
    const unsigned int draws = plane_number(count, arguments, "--draws", PLANE_DRAWS);
    const std::string directory = plane_directory(count, arguments);
    const unsigned long long needed = (unsigned long long)bits_count + PLANE_GUARD + 64ull;
    if ((bits_count < 64u) || (bits_count > PLANE_BITS_MAX) || (needed > ANCHOR_EXACT_BITS) || (draws == 0u))
    {
        unsigned long long limbs = 1ull;
        while (limbs * 32ull < needed)
        {
            limbs *= 2ull;
        }
        scriptura_text(line, "  refused: the draws are at least 1, the bits are 64 to ");
        scriptura_decimal(line, PLANE_BITS_MAX, 1u);
        scriptura_text(line, ", and the bracket needs an exact width of ");
        scriptura_decimal(line, needed, 1u);
        scriptura_text(line, " bits: run with SIM_EXACT_LIMBS=");
        scriptura_decimal(line, limbs, 1u);
        scriptura_character(line, '\n');
        sim_check(&results, 0, "the request fits the exact width");
        return sim_close(&results, "pi plane");
    }

    std::vector<unsigned char> bits;
    int ok = plane_bits(&results, bits_count, &bits);
    sim_flush(&results);

    std::vector<PlaneExtent> extents(PLANE_WIDTHS + 5u);
    int built = ok;
    for (unsigned int width = 0u; built && (width < PLANE_WIDTHS); width += 1u)
    {
        built = plane_rows(&extents[width], bits_count, s_plane_widths[width]);
    }
    built = built && plane_tower(&extents[PLANE_WIDTHS], bits_count);
    built = built && plane_disc(&extents[PLANE_WIDTHS + 1u], &extents[PLANE_WIDTHS + 2u], bits_count);
    built = built && plane_spiral(&extents[PLANE_WIDTHS + 3u], bits_count);
    built = built && plane_twindragon(&extents[PLANE_WIDTHS + 4u], bits_count);
    sim_check(&results, built, "every shape lays out each bit on its own pixel");
    ok = ok && built;

    std::vector<unsigned char> drawn;
    plane_shuffle(bits, 0u, &drawn);
    int drew = ok;
    for (size_t extent = 0u; drew && (extent < extents.size()); extent += 1u)
    {
        drew = plane_picture(extents[extent], bits.data(), directory + "/pi_" + extents[extent].name + ".png") &&
               plane_picture(extents[extent], drawn.data(), directory + "/shuffled_" + extents[extent].name + ".png");
    }
    sim_check(&results, drew, "every shape is drawn for pi and for one shuffle of its bits");
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
    ok = ok && sim_job_submit(&results, "pi_plane", count, arguments,
                              (unsigned long long)bits_count * (1ull + sizeof(unsigned int)));
    ok = ok && sim_status_check(&results, cudaMalloc((void **)&device_bits, bits_count), "bits");
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_longest, (size_t)bits_count * sizeof(unsigned int)),
                          "the lags' longest runs");
    ok = ok && plane_lag_device(&results, bits.data(), bits_count, device_bits, device_longest, longest.data());
    if (ok)
    {
        plane_lag_host(bits.data(), bits_count, host_longest.data());
        longest[0] = 0u;
        sim_check(&results, memcmp(longest.data(), host_longest.data(), (size_t)bits_count * sizeof(unsigned int)) == 0,
                  "the device's longest run at every difference equals the host's, for pi");
    }

    const std::vector<PlaneStep> steps = plane_steps();
    std::vector<PlaneLine> found(extents.size());
    for (size_t extent = 0u; ok && (extent < extents.size()); extent += 1u)
    {
        found[extent] = plane_longest_line(extents[extent], bits.data(), steps);
    }
    if (ok)
    {
        const PlaneExtent &rings = extents[PLANE_WIDTHS + 2u];
        const PlaneLine &spoke = found[PLANE_WIDTHS + 2u];
        std::vector<unsigned char> first_drawn;
        plane_shuffle(bits, 0u, &first_drawn);
        const PlaneLine drawn_line = plane_longest_line(rings, first_drawn.data(), steps);
        const int sparse =
            plane_sparse_picture(rings, bits.data(), spoke, directory + "/pi_disc_rings_sparse.png") &&
            plane_sparse_picture(rings, first_drawn.data(), drawn_line, directory + "/shuffled_disc_rings_sparse.png");
        sim_check(&results, sparse, "the ring-filled disc is drawn sparse, its longest line in red");
        scriptura_text(line, "  the sparse ring: pi's longest line on the ring-filled disc is ");
        plane_line_print(line, spoke);
        scriptura_text(line, ", every bit of it a ");
        scriptura_decimal(line, bits[(size_t)spoke.start], 1u);
        scriptura_text(line, "; the shuffle's is ");
        plane_line_print(line, drawn_line);
        scriptura_character(line, '\n');
        sim_flush(&results);
    }
    unsigned int pi_lag = 0u;
    const unsigned int pi_lag_length = ok ? plane_lag_max(longest.data(), bits_count, &pi_lag) : 0u;

    std::vector<std::vector<unsigned long long>> band(extents.size());
    std::vector<unsigned long long> lag_band;
    std::vector<unsigned int> drawn_longest(bits_count);
    std::vector<std::vector<unsigned long long>> spread_band(2u * PLANE_SCALES);
    const PlaneExtent &dragon = extents[PLANE_WIDTHS + 4u];
    std::vector<unsigned int> dragon_depth;
    if (ok)
    {
        dragon_depth = plane_depth(dragon);
    }
    std::vector<unsigned long long> depth_band;
    unsigned long long depth_ones[PLANE_DEPTHS + 1u];
    unsigned long long depth_sizes[PLANE_DEPTHS + 1u];

    // the sphere: the widest integer shell the bits fill, bit n at the n-th point by latitude circles or by meridians
    long long sphere_radius = 0ll;
    std::vector<std::vector<PlaneSpherePoint>> sphere_orders(2u);
    std::vector<PlaneExtent> spheres(2u);
    size_t sphere_count = 0u;
    if (ok)
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
    int sphere_drew = ok && (sphere_count > 0u);
    for (size_t fill = 0u; sphere_drew && (fill < spheres.size()); fill += 1u)
    {
        sphere_drew =
            plane_picture(spheres[fill], sphere_bits.data(), directory + "/pi_" + spheres[fill].name + ".png") &&
            plane_picture(spheres[fill], sphere_drawn.data(), directory + "/shuffled_" + spheres[fill].name + ".png");
    }
    sim_check(&results, sphere_drew, "the sphere is laid out and drawn for pi and for one shuffle of its bits");
    ok = ok && sphere_drew;
    std::vector<PlaneLine> sphere_found(spheres.size());
    std::vector<unsigned long long> sphere_latitude(spheres.size(), 0ull);
    for (size_t fill = 0u; ok && (fill < spheres.size()); fill += 1u)
    {
        sphere_found[fill] = plane_longest_line(spheres[fill], sphere_bits.data(), steps);
        sphere_latitude[fill] = plane_latitude_spread(sphere_orders[fill], sphere_radius, sphere_bits.data());
    }
    std::vector<std::vector<unsigned long long>> sphere_line_band(spheres.size());
    std::vector<std::vector<unsigned long long>> sphere_latitude_band(spheres.size());
    std::vector<std::vector<unsigned long long>> fibonacci_band(PLANE_FIBONACCI + 1u);
    int shuffled = ok;
    for (unsigned int draw = 0u; shuffled && (draw < draws); draw += 1u)
    {
        plane_shuffle(bits, draw, &drawn);
        shuffled =
            plane_lag_device(&results, drawn.data(), bits_count, device_bits, device_longest, drawn_longest.data());
        unsigned int drawn_lag = 0u;
        lag_band.push_back(plane_lag_max(drawn_longest.data(), bits_count, &drawn_lag));
        for (size_t extent = 0u; shuffled && (extent < extents.size()); extent += 1u)
        {
            band[extent].push_back(plane_longest_line(extents[extent], drawn.data(), steps).length);
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
            sphere_latitude_band[fill].push_back(
                plane_latitude_spread(sphere_orders[fill], sphere_radius, sphere_drawn.data()));
        }
        unsigned long long golden_max = 0ull;
        for (unsigned int fibonacci = 0u; fibonacci < PLANE_FIBONACCI; fibonacci += 1u)
        {
            const unsigned long long run =
                (s_plane_fibonacci[fibonacci] < bits_count) ? drawn_longest[s_plane_fibonacci[fibonacci]] : 0ull;
            fibonacci_band[fibonacci].push_back(run);
            golden_max = std::max(golden_max, run);
        }
        fibonacci_band[PLANE_FIBONACCI].push_back(golden_max);
    }
    sim_check(&results, shuffled, "every draw is shuffled and read");

    if (ok && shuffled)
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
        scriptura_text(line, "  pi's convergent denominators as differences:");
        const unsigned int denominators[3] = {7u, 106u, 113u};
        for (unsigned int convergent = 0u; convergent < 3u; convergent += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_decimal(line, longest[denominators[convergent]], 1u);
            scriptura_text(line, " at ");
            scriptura_decimal(line, denominators[convergent], 1u);
        }
        scriptura_character(line, '\n');
        sim_flush(&results);
        for (size_t extent = 0u; extent < extents.size(); extent += 1u)
        {
            scriptura_text(line, "  ");
            scriptura_text(line, extents[extent].name.c_str());
            scriptura_text(line, " (");
            scriptura_decimal(line, extents[extent].width, 1u);
            scriptura_text(line, " x ");
            scriptura_decimal(line, extents[extent].height, 1u);
            scriptura_text(line, "): pi's longest line ");
            plane_line_print(line, found[extent]);
            plane_band_print(line, band[extent], found[extent].length);
            sim_flush(&results);
        }
        scriptura_text(
            line, "  the ones' spread, sum over the classes of (2 ones - size)^2; a residue is one place on every");
        scriptura_text(line, " arm of the twindragon, a block one whole sub-dragon\n");
        for (unsigned int kind = 0u; kind < 2u * PLANE_SCALES; kind += 1u)
        {
            const unsigned int scale = (kind / 2u) + 1u;
            // the kind's low bit chooses residues or blocks
            const unsigned long long measurement = plane_spread(bits.data(), bits_count, scale, (int)(kind % 2u));
            scriptura_text(line, ((kind % 2u) == 0u) ? "  residues mod 2^" : "  blocks, 2^");
            scriptura_decimal(line, scale, 1u);
            scriptura_text(line, ((kind % 2u) == 0u) ? ": pi's spread " : " of them: pi's spread ");
            scriptura_decimal(line, measurement, 1u);
            plane_band_print(line, spread_band[kind], measurement);
            sim_flush(&results);
        }
        const unsigned long long depth_measurement =
            plane_depth_spread(dragon, dragon_depth, bits.data(), depth_ones, depth_sizes);
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
        scriptura_decimal(line, depth_measurement, 1u);
        plane_band_print(line, depth_band, depth_measurement);
        sim_flush(&results);

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
            sim_flush(&results);
        }
        scriptura_text(line, "  the golden sphere's spirals, pi's longest run at each Fibonacci difference:\n");
        unsigned long long golden_max = 0ull;
        for (unsigned int fibonacci = 0u; fibonacci < PLANE_FIBONACCI; fibonacci += 1u)
        {
            if (s_plane_fibonacci[fibonacci] >= bits_count)
            {
                continue;
            }
            const unsigned long long run = longest[s_plane_fibonacci[fibonacci]];
            golden_max = std::max(golden_max, run);
            scriptura_text(line, "    F = ");
            scriptura_decimal(line, s_plane_fibonacci[fibonacci], 1u);
            scriptura_text(line, ": ");
            scriptura_decimal(line, run, 1u);
            plane_band_print(line, fibonacci_band[fibonacci], run);
        }
        scriptura_text(line, "  the longest over every Fibonacci difference ");
        scriptura_decimal(line, golden_max, 1u);
        plane_band_print(line, fibonacci_band[PLANE_FIBONACCI], golden_max);
        sim_flush(&results);
    }

    if (ok)
    {
        plane_rings(&results, bits, draws, plane_number(count, arguments, "--blind", 0u),
                    plane_number(count, arguments, "--blind-from", 0u),
                    plane_number(count, arguments, "--balanced", 0u) != 0u,
                    plane_number(count, arguments, "--funnels", 0u), directory);
    }

    // a path drawn over the ring-filled disc: pi's ones under it against the same cells in each shuffle
    const char *const cells_path = plane_text(count, arguments, "--cells");
    if (ok && (cells_path != NULL))
    {
        const std::vector<long long> under = plane_path_cells(extents[PLANE_WIDTHS + 2u], cells_path);
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
        sim_check(&results, !under.empty(), "the drawn path lies on the disc");
        sim_flush(&results);
    }

    cudaFree(device_bits);
    cudaFree(device_longest);
    return sim_close(&results, "pi plane");
}
