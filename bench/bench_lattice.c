// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <complex.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef bool embed_bool;
#define EMBED_TRUE true
#define EMBED_FALSE false

#define PATTERN_POINTS 8u

#define PATTERN_POINTS_MAX 32u

#define LATTICE_MAX_ANCHORS PATTERN_POINTS_MAX

#define SYMBOL_LEVELS 2u

static const unsigned ALPHABET_SIZES[] = {2u, 3u, 4u, 16u, 64u, 256u};

static const unsigned POINT_COUNTS[] = {1u, 2u, 3u, 5u, 8u, 13u, 21u, 32u};

#define PLANTED_COPIES 24u

#define PATTERN_SAMPLES 64u

typedef embed_bool (*SameSymbol)(const void *domain, size_t left, size_t right);

typedef struct
{
    const char *name;
    const void *domain;
    SameSymbol same;
    const size_t *bases;
    size_t base_count;
    const ptrdiff_t *displacements;
    unsigned point_count;
} LatticeCase;

typedef enum
{
    ANCHOR_LEADING = 0,
    ANCHOR_SPREAD = 1,
    ANCHOR_SHUFFLED = 2
} LatticeRule;

static const char *rule_name(LatticeRule rule)
{
    switch (rule)
    {
    case ANCHOR_SPREAD:
    {
        return "spread";
    }
    case ANCHOR_SHUFFLED:
    {
        return "shuffled";
    }
    case ANCHOR_LEADING:
    default:
    {
        return "leading";
    }
    }
}

static uint64_t next_random(uint64_t *state)
{
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t held = *state;

    held = (held ^ (held >> 30)) * 0xBF58476D1CE4E5B9ULL;
    held = (held ^ (held >> 27)) * 0x94D049BB133111EBULL;
    return held ^ (held >> 31);
}

static void draw_bytes(uint8_t *into, size_t length, uint64_t salt)
{
    uint64_t state = salt;
    size_t written = 0u;

    while (written < length)
    {
        const uint64_t held = next_random(&state);
        size_t taking = length - written;

        if (taking > sizeof held)
        {
            taking = sizeof held;
        }
        memcpy(into + written, &held, taking);
        written += taking;
    }
}

static uint32_t candidates_lattice(SameSymbol same, const void *domain, const size_t *bases, size_t base_count,
                                   size_t pattern_base, const ptrdiff_t *displacements, const unsigned *anchors,
                                   unsigned anchor_count)
{
    uint32_t surviving = 0u;

    for (size_t index = 0u; index < base_count; index++)
    {
        const ptrdiff_t base = (ptrdiff_t)bases[index];
        unsigned matched = 0u;

        while ((matched < anchor_count) &&
               (same(domain, (size_t)(base + displacements[anchors[matched]]),
                     (size_t)((ptrdiff_t)pattern_base + displacements[anchors[matched]])) != EMBED_FALSE))
        {
            matched++;
        }
        if (matched == anchor_count)
        {
            surviving++;
        }
    }
    return surviving;
}

static uint32_t refused_lattice(SameSymbol same, const void *domain, const size_t *bases, size_t base_count,
                                size_t pattern_base, const ptrdiff_t *displacements, unsigned point_count,
                                const unsigned *anchors, unsigned anchor_count, uint32_t *found)
{
    uint32_t refused = 0u;
    uint32_t occurrences = 0u;

    for (size_t index = 0u; index < base_count; index++)
    {
        const ptrdiff_t base = (ptrdiff_t)bases[index];
        unsigned matched = 0u;

        while ((matched < point_count) &&
               (same(domain, (size_t)(base + displacements[matched]),
                     (size_t)((ptrdiff_t)pattern_base + displacements[matched])) != EMBED_FALSE))
        {
            matched++;
        }
        if (matched < point_count)
        {
            continue;
        }
        occurrences++;

        for (unsigned which = 0u; which < anchor_count; which++)
        {
            const ptrdiff_t reach = displacements[anchors[which]];

            if (same(domain, (size_t)(base + reach), (size_t)((ptrdiff_t)pattern_base + reach)) == EMBED_FALSE)
            {
                refused++;
                break;
            }
        }
    }
    *found = occurrences;
    return refused;
}

static unsigned pick_lattice_anchors(LatticeRule rule, unsigned point_count, unsigned want, unsigned *anchors,
                                     uint64_t salt)
{
    if (want > point_count)
    {
        return 0u;
    }

    switch (rule)
    {
    case ANCHOR_SPREAD:
    {
        for (unsigned index = 0u; index < want; index++)
        {
            anchors[index] = (index * point_count) / want;
        }
        break;
    }
    case ANCHOR_SHUFFLED:
    {
        unsigned order[PATTERN_POINTS_MAX];
        uint8_t noise[PATTERN_POINTS_MAX];

        draw_bytes(noise, sizeof noise, salt);

        for (unsigned index = 0u; index < point_count; index++)
        {
            order[index] = index;
        }
        for (unsigned slot = point_count - 1u; slot > 0u; slot--)
        {
            const unsigned pick = (unsigned)noise[slot] % (slot + 1u);
            const unsigned held = order[slot];

            order[slot] = order[pick];
            order[pick] = held;
        }
        for (unsigned index = 0u; index < want; index++)
        {
            anchors[index] = order[index];
        }
        break;
    }
    case ANCHOR_LEADING:
    default:
    {
        for (unsigned index = 0u; index < want; index++)
        {
            anchors[index] = index;
        }
        break;
    }
    }
    return want;
}

static void report_lattice(const LatticeCase *shape)
{
    static const LatticeRule rules[] = {ANCHOR_LEADING, ANCHOR_SPREAD, ANCHOR_SHUFFLED};

    const size_t step = (shape->base_count > PATTERN_SAMPLES) ? (shape->base_count / PATTERN_SAMPLES) : 1u;

    for (size_t which = 0u; which < (sizeof rules / sizeof rules[0]); which++)
    {
        const LatticeRule rule = rules[which];

        for (unsigned count = 1u; (count <= LATTICE_MAX_ANCHORS) && (count <= shape->point_count); count++)
        {
            uint32_t checked = 0u;
            uint32_t refused = 0u;
            double candidates = 0.0;
            unsigned samples = 0u;

            for (size_t index = 0u; index < shape->base_count; index += step)
            {
                const size_t pattern_base = shape->bases[index];
                unsigned anchors[LATTICE_MAX_ANCHORS];
                uint32_t found = 0u;

                if (pick_lattice_anchors(rule, shape->point_count, count, anchors, (uint64_t)index) < count)
                {
                    continue;
                }

                refused += refused_lattice(shape->same, shape->domain, shape->bases, shape->base_count, pattern_base,
                                           shape->displacements, shape->point_count, anchors, count, &found);
                checked += found;
                candidates += (double)candidates_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                                         pattern_base, shape->displacements, anchors, count);
                samples++;
            }

            if (samples == 0u)
            {
                continue;
            }

            printf("ancorae_lattice,%s,%s,%u,%u,%u,%u,%u,%.2f,%s\n", shape->name, rule_name(rule),
                   shape->point_count, count, (unsigned)shape->base_count, samples, checked,
                   candidates / (double)samples,
                   (checked == 0u) ? "none" : ((refused == 0u) ? "hold" : "BROKEN"));
        }
    }
}

#define LINE_LENGTH 4096u

#define GRID_SIDE 64u

#define CUBE_SIDE 16u

#define FIELD_LENGTH 4096u

#define SCATTER_SIDE 5u

static uint8_t s_line[LINE_LENGTH];
static uint8_t s_grid[GRID_SIDE * GRID_SIDE];
static uint8_t s_cube[CUBE_SIDE * CUBE_SIDE * CUBE_SIDE];

static double _Complex s_field[FIELD_LENGTH];

static size_t s_line_bases[LINE_LENGTH];

static size_t s_shuffled_bases[LINE_LENGTH];
static size_t s_grid_bases[GRID_SIDE * GRID_SIDE];
static size_t s_cube_bases[CUBE_SIDE * CUBE_SIDE * CUBE_SIDE];
static size_t s_field_bases[FIELD_LENGTH];

static ptrdiff_t s_line_points[PATTERN_POINTS_MAX];
static ptrdiff_t s_grid_box[PATTERN_POINTS];
static ptrdiff_t s_grid_scatter[PATTERN_POINTS];
static ptrdiff_t s_grid_turned[PATTERN_POINTS];
static ptrdiff_t s_cube_box[PATTERN_POINTS];

static unsigned plant(uint8_t *domain, const size_t *bases, size_t base_count, size_t pattern_base,
                      const ptrdiff_t *displacements, unsigned point_count, unsigned copies)
{
    unsigned written = 0u;

    if ((base_count == 0u) || (copies == 0u))
    {
        return 0u;
    }

    const size_t step = (base_count > copies) ? (base_count / copies) : 1u;

    for (size_t index = 0u; (index < base_count) && (written < copies); index += step)
    {
        const ptrdiff_t target = (ptrdiff_t)bases[index];

        if (bases[index] == pattern_base)
        {
            continue;
        }
        for (unsigned point = 0u; point < point_count; point++)
        {
            const ptrdiff_t reach = displacements[point];

            domain[(size_t)(target + reach)] = domain[(size_t)((ptrdiff_t)pattern_base + reach)];
        }
        written++;
    }
    return written;
}

static embed_bool same_byte(const void *domain, size_t left, size_t right)
{
    const uint8_t *const bytes = (const uint8_t *)domain;

    return (bytes[left] == bytes[right]) ? EMBED_TRUE : EMBED_FALSE;
}

static embed_bool same_field(const void *domain, size_t left, size_t right)
{
    const double _Complex *const values = (const double _Complex *)domain;

    return (memcmp(&values[left], &values[right], sizeof values[0]) == 0) ? EMBED_TRUE : EMBED_FALSE;
}

static void fill_levels(uint8_t *into, size_t length, uint64_t salt, unsigned levels)
{
    draw_bytes(into, length, salt);

    if (levels < 256u)
    {
        for (size_t index = 0u; index < length; index++)
        {
            into[index] = (uint8_t)(into[index] % levels);
        }
    }
}

static void fill_field(void)
{
    double _Complex alphabet[SYMBOL_LEVELS];
    uint8_t picks[FIELD_LENGTH];

    for (unsigned level = 0u; level < SYMBOL_LEVELS; level++)
    {
        const double real = sqrt((double)(2u + (level * 3u)));
        const double imaginary = sqrt((double)(5u + (level * 7u)));

        alphabet[level] = real + (imaginary * I);
    }

    draw_bytes(picks, sizeof picks, 0x5EEDu);

    for (size_t index = 0u; index < FIELD_LENGTH; index++)
    {
        s_field[index] = alphabet[picks[index] % SYMBOL_LEVELS];
    }
}

static size_t build_line(unsigned points)
{
    size_t count = 0u;

    for (unsigned point = 0u; point < points; point++)
    {
        s_line_points[point] = (ptrdiff_t)point;
    }
    for (size_t start = 0u; (start + points) <= LINE_LENGTH; start++)
    {
        s_line_bases[count] = start;
        count++;
    }
    return count;
}

static void build_shuffled(size_t count)
{
    uint64_t state = 0x9A17C0DEULL;

    for (size_t index = 0u; index < count; index++)
    {
        s_shuffled_bases[index] = s_line_bases[index];
    }
    for (size_t slot = count - 1u; slot > 0u; slot--)
    {
        const size_t pick = (size_t)(next_random(&state) % (uint64_t)(slot + 1u));
        const size_t kept = s_shuffled_bases[slot];

        s_shuffled_bases[slot] = s_shuffled_bases[pick];
        s_shuffled_bases[pick] = kept;
    }
}

static size_t build_field(void)
{
    size_t count = 0u;

    for (size_t start = 0u; (start + PATTERN_POINTS) <= FIELD_LENGTH; start++)
    {
        s_field_bases[count] = start;
        count++;
    }
    return count;
}

static size_t build_grid(void)
{
    static const unsigned scatter[PATTERN_POINTS][2] = {{0u, 0u}, {0u, 3u}, {1u, 1u}, {2u, 4u}, {3u, 0u}, {3u, 2u}, {4u, 1u}, {4u, 4u}};
    size_t count = 0u;

    for (unsigned point = 0u; point < PATTERN_POINTS; point++)
    {
        const unsigned row = point / 4u;
        const unsigned column = point % 4u;

        s_grid_box[point] = (ptrdiff_t)((row * GRID_SIDE) + column);
        s_grid_scatter[point] = (ptrdiff_t)((scatter[point][0] * GRID_SIDE) + scatter[point][1]);
        s_grid_turned[point] =
            (ptrdiff_t)((scatter[point][1] * GRID_SIDE) + ((SCATTER_SIDE - 1u) - scatter[point][0]));
    }

    for (unsigned row = 0u; (row + SCATTER_SIDE) <= GRID_SIDE; row++)
    {
        for (unsigned column = 0u; (column + SCATTER_SIDE) <= GRID_SIDE; column++)
        {
            s_grid_bases[count] = (size_t)((row * GRID_SIDE) + column);
            count++;
        }
    }
    return count;
}

static size_t build_cube(void)
{
    size_t count = 0u;

    for (unsigned point = 0u; point < PATTERN_POINTS; point++)
    {
        const unsigned plane = point / 4u;
        const unsigned row = (point / 2u) % 2u;
        const unsigned column = point % 2u;

        s_cube_box[point] = (ptrdiff_t)((plane * CUBE_SIDE * CUBE_SIDE) + (row * CUBE_SIDE) + column);
    }

    for (unsigned plane = 0u; (plane + 2u) <= CUBE_SIDE; plane++)
    {
        for (unsigned row = 0u; (row + 2u) <= CUBE_SIDE; row++)
        {
            for (unsigned column = 0u; (column + 2u) <= CUBE_SIDE; column++)
            {
                s_cube_bases[count] = (size_t)((plane * CUBE_SIDE * CUBE_SIDE) + (row * CUBE_SIDE) + column);
                count++;
            }
        }
    }
    return count;
}

#define MAX_DIMENSION 8u

#define DOMAIN_MAX 65536u

static uint8_t s_hypercube[DOMAIN_MAX];
static size_t s_hypercube_bases[DOMAIN_MAX];
static ptrdiff_t s_hypercube_points[PATTERN_POINTS_MAX];

static size_t build_hypercube(unsigned dimension, unsigned side, unsigned points, size_t *cells)
{
    const unsigned extent = (points <= 1u) ? 1u : (2u + ((points - 2u) / dimension));

    size_t stride[MAX_DIMENSION];
    size_t total = 1u;

    for (unsigned axis = 0u; axis < dimension; axis++)
    {
        stride[axis] = total;
        total *= side;
    }
    *cells = total;

    if (side < extent)
    {
        return 0u;
    }

    s_hypercube_points[0] = 0;

    for (unsigned point = 1u; point < points; point++)
    {
        const unsigned axis = (point - 1u) % dimension;
        const unsigned step = 1u + ((point - 1u) / dimension);

        s_hypercube_points[point] = (ptrdiff_t)((size_t)step * stride[axis]);
    }

    const unsigned room = (side - extent) + 1u;
    size_t written = 0u;
    size_t combinations = 1u;

    for (unsigned axis = 0u; axis < dimension; axis++)
    {
        combinations *= room;
    }

    for (size_t which = 0u; which < combinations; which++)
    {
        size_t offset = 0u;
        size_t remaining = which;

        for (unsigned axis = 0u; axis < dimension; axis++)
        {
            offset += (remaining % room) * stride[axis];
            remaining /= room;
        }
        s_hypercube_bases[written] = offset;
        written++;
    }
    return written;
}

static void report_swept(const LatticeCase *shape, unsigned levels, unsigned planted,
                         size_t pattern_base)
{
    static const LatticeRule rules[] = {ANCHOR_LEADING, ANCHOR_SPREAD, ANCHOR_SHUFFLED};

    for (size_t which = 0u; which < (sizeof rules / sizeof rules[0]); which++)
    {
        const LatticeRule rule = rules[which];

        for (unsigned count = 1u; count <= shape->point_count; count++)
        {
            unsigned anchors[LATTICE_MAX_ANCHORS];
            uint32_t found = 0u;

            if (pick_lattice_anchors(rule, shape->point_count, count, anchors, (uint64_t)count) <
                count)
            {
                continue;
            }

            const uint32_t refused =
                refused_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                pattern_base, shape->displacements, shape->point_count, anchors,
                                count, &found);
            const uint32_t surviving =
                candidates_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                   pattern_base, shape->displacements, anchors, count);

            printf("ancorae_sweep,%s,%s,%u,%u,%u,%u,%u,%u,%u,%s\n", shape->name, rule_name(rule),
                   levels, shape->point_count, count, (unsigned)shape->base_count, found, planted,
                   surviving, (found == 0u) ? "none" : ((refused == 0u) ? "hold" : "BROKEN"));
        }
    }
}

int main(void)
{
    fill_levels(s_line, sizeof s_line, 0x11u, SYMBOL_LEVELS);
    fill_levels(s_grid, sizeof s_grid, 0x22u, SYMBOL_LEVELS);
    fill_levels(s_cube, sizeof s_cube, 0x33u, SYMBOL_LEVELS);
    fill_field();

    const size_t line_bases = build_line(PATTERN_POINTS);

    build_shuffled(line_bases);

    const size_t grid_bases = build_grid();
    const size_t cube_bases = build_cube();
    const size_t field_bases = build_field();

    const LatticeCase cases[] = {
        {"line1d", s_line, same_byte, s_line_bases, line_bases, s_line_points, PATTERN_POINTS},
        {"line1d_unordered", s_line, same_byte, s_shuffled_bases, line_bases, s_line_points,
         PATTERN_POINTS},
        {"grid2d_box", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_box, PATTERN_POINTS},
        {"grid2d_scatter", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_scatter, PATTERN_POINTS},
        {"grid2d_turned", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_turned, PATTERN_POINTS},
        {"cube3d_box", s_cube, same_byte, s_cube_bases, cube_bases, s_cube_box, PATTERN_POINTS},
        {"field1d_complex", s_field, same_field, s_field_bases, field_bases, s_line_points, PATTERN_POINTS},
    };

    printf("bench,domain,rule,points,anchors,positions,samples,occurrences,candidates,verdict\n");

    for (size_t index = 0u; index < (sizeof cases / sizeof cases[0]); index++)
    {
        report_lattice(&cases[index]);
    }

    printf("bench,domain,points,disagreements,verdict\n");
    {
        unsigned anchors[LATTICE_MAX_ANCHORS];
        unsigned disagreed = 0u;

        for (unsigned count = 1u; count <= PATTERN_POINTS; count++)
        {
            if (pick_lattice_anchors(ANCHOR_SPREAD, PATTERN_POINTS, count, anchors, 0u) < count)
            {
                continue;
            }

            for (size_t sample = 0u; sample < PATTERN_SAMPLES; sample++)
            {
                const size_t pattern_base = s_line_bases[(sample * line_bases) / PATTERN_SAMPLES];
                uint32_t ordered_found = 0u;
                uint32_t shuffled_found = 0u;

                const uint32_t ordered_refused =
                    refused_lattice(same_byte, s_line, s_line_bases, line_bases, pattern_base,
                                    s_line_points, PATTERN_POINTS, anchors, count, &ordered_found);
                const uint32_t shuffled_refused =
                    refused_lattice(same_byte, s_line, s_shuffled_bases, line_bases, pattern_base,
                                    s_line_points, PATTERN_POINTS, anchors, count, &shuffled_found);

                if ((ordered_found != shuffled_found) || (ordered_refused != shuffled_refused))
                {
                    disagreed++;
                }
            }
        }
        printf("ancorae_order,line1d,%u,%u,%s\n", PATTERN_POINTS, disagreed,
               (disagreed == 0u) ? "hold" : "BROKEN");
    }

    static const unsigned sides[MAX_DIMENSION + 1u] = {0u, 4096u, 64u, 20u, 10u, 6u, 5u, 4u, 3u};

    for (unsigned dimension = 1u; dimension <= MAX_DIMENSION; dimension++)
    {
        size_t cells = 0u;
        const size_t bases = build_hypercube(dimension, sides[dimension], PATTERN_POINTS, &cells);
        char label[16];

        if (bases == 0u)
        {
            continue;
        }
        fill_levels(s_hypercube, cells, 0x400u + dimension, SYMBOL_LEVELS);
        snprintf(label, sizeof label, "cube%ud", dimension);

        const LatticeCase shape = {label, s_hypercube, same_byte, s_hypercube_bases,
                                   bases, s_hypercube_points, PATTERN_POINTS};

        report_lattice(&shape);
    }

    printf("bench,geometry,rule,levels,points,anchors,positions,occurrences,planted,candidates,"
           "verdict\n");

    for (size_t which_level = 0u;
         which_level < (sizeof ALPHABET_SIZES / sizeof ALPHABET_SIZES[0]); which_level++)
    {
        const unsigned levels = ALPHABET_SIZES[which_level];

        for (size_t which_points = 0u;
             which_points < (sizeof POINT_COUNTS / sizeof POINT_COUNTS[0]); which_points++)
        {
            const unsigned points = POINT_COUNTS[which_points];

            fill_levels(s_line, sizeof s_line, 0x11u, levels);

            const size_t swept_bases = build_line(points);
            const size_t seat = s_line_bases[0];
            const unsigned planted = plant(s_line, s_line_bases, swept_bases, seat, s_line_points,
                                           points, PLANTED_COPIES);
            const LatticeCase line = {"line1d", s_line, same_byte, s_line_bases,
                                      swept_bases, s_line_points, points};

            report_swept(&line, levels, planted, seat);

            size_t cells = 0u;
            const size_t cube_swept = build_hypercube(3u, 20u, points, &cells);

            if (cube_swept == 0u)
            {
                continue;
            }
            fill_levels(s_hypercube, cells, 0x77u, levels);

            const size_t cube_seat = s_hypercube_bases[0];
            const unsigned cube_planted =
                plant(s_hypercube, s_hypercube_bases, cube_swept, cube_seat, s_hypercube_points,
                      points, PLANTED_COPIES);
            const LatticeCase cube = {"cube3d", s_hypercube, same_byte, s_hypercube_bases,
                                      cube_swept, s_hypercube_points, points};

            report_swept(&cube, levels, cube_planted, cube_seat);
        }
    }
    return 0;
}
