// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_identity.cu: written, read off, through and the identity
#include "record_boundary_test_internal.h"

// write onto the boundary and read back: the fields are a crystal, T^-1 rebuilds the samples and T the crystal again.
// Flips of the crystal's bits are T^-1's precision.
void boundary_written(BoundaryResults *results)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const back = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    BoundaryTower *const again = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (back == NULL) || (again == NULL))
    {
        boundary_check(results, 0, "the written boundary is held");
        free(program);
        free(back);
        free(again);
        return;
    }
    unsigned int crystal[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        crystal[at] = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_inverse(program, crystal, NULL, NULL, back, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    memcpy(again->low[0], back->low[0], sizeof(again->low[0]));
    boundary_forward(program, again, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, back->low[0][at]);
    }
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, again->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, BOUNDARY_TEST_SAMPLES, &loaded);
    boundary_check(results, loads, "T^-1 then T over a written crystal encodes, lays out with reuse and loads");
    if (loads != 0)
    {
        int range = 0;
        boundary_precision(results, &loaded, program, boundary_host_inverse, g_boundary_inverse_matrix,
                           BOUNDARY_TEST_INVERSE_RANGE, 1, "written (T^-1 then T)", &range);
        boundary_check(results, range == (int)BOUNDARY_TEST_INVERSE_RANGE, "T^-1's range L + 2 is met on the device");
        boundary_free(&loaded);
    }
    free(program);
    free(back);
    free(again);
}

// T alone over the samples: its precision, then what passes through it, then the identity null permutations take
static void boundary_through(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program);

static void boundary_identity(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program);

void boundary_read_off(BoundaryResults *results)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (tower == NULL))
    {
        boundary_check(results, 0, "the forward tower is held");
        free(program);
        free(tower);
        return;
    }
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        tower->low[0][at] = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_forward(program, tower, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, BOUNDARY_TEST_SAMPLES, &loaded);
    boundary_check(results, loads, "T over 64 samples encodes, lays out with reuse and loads");
    if (loads != 0)
    {
        int range = 0;
        boundary_precision(results, &loaded, program, boundary_host_forward, g_boundary_forward_matrix,
                           BOUNDARY_TEST_RANGE, 0, "read off (T)", &range);
        boundary_check(results, range == (int)BOUNDARY_TEST_RANGE, "T's range 3L is met on the device");
        boundary_through(results, &loaded, program);
        boundary_identity(results, &loaded, program);
        boundary_free(&loaded);
    }
    free(program);
    free(tower);
}

// what passes through T, one kind per quarter of the pairs: a constant c added to every sample must move only the
// crystal's lows, each by c; a vector 2^(3L) z must move the crystal by M z exactly; negation and doubling are
// counted where they pass
static void boundary_through(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int lows = BOUNDARY_TEST_SAMPLES >> BOUNDARY_TEST_LEVELS;
    const unsigned int lanes = 2u * BOUNDARY_TEST_PAIRS;
    const unsigned int out_limbs = loaded->layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    long long *const added = (long long *)calloc((size_t)BOUNDARY_TEST_PAIRS * n, sizeof(long long));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (added != NULL);
    for (unsigned int pair = 0u; (buffers != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        const unsigned int kind = pair % 4u;
        // a constant below 2^19 in magnitude, shared by every sample
        const long long constant = (long long)(boundary_random() & 0xFFFFFu) - (1ll << 19u);
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            // a base sample below 2^21 in magnitude. Every moved sample stays inside the field
            const long long base = (long long)(boundary_random() & 0x3FFFFFu) - (1ll << 21u);
            long long moved = base;
            if (kind == 0u)
            {
                added[((size_t)pair * n) + at] = constant;
                moved = base + constant;
            }
            else if (kind == 1u)
            {
                const long long lattice = (long long)(boundary_random() & 0xFFu) - 128ll;
                added[((size_t)pair * n) + at] = lattice;
                moved = base + (lattice * (1ll << BOUNDARY_TEST_RANGE));
            }
            else if (kind == 2u)
            {
                moved = -base;
            }
            else
            {
                moved = 2ll * base;
            }
            atoms[((size_t)(2u * pair) * n) + at] = boundary_word(base);
            atoms[((size_t)((2u * pair) + 1u) * n) + at] = boundary_word(moved);
        }
    }
    const int ran = (buffers != 0) && (boundary_run(loaded, atoms, lanes, host_out, device_out) != 0);
    unsigned int passed[4] = {0u, 0u, 0u, 0u};
    for (unsigned int pair = 0u; (ran != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        const unsigned int kind = pair % 4u;
        const unsigned int *const base = &device_out[(size_t)(2u * pair) * out_limbs];
        const unsigned int *const moved = &device_out[(size_t)((2u * pair) + 1u) * out_limbs];
        int passes = 1;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const DeviceRecordStep *const step = &loaded->layout.step_table[program->outputs[at]];
            const long long before = boundary_read(base, step);
            const long long after = boundary_read(moved, step);
            long long expected = 0ll;
            if (kind == 0u)
            {
                expected = before + ((at < lows) ? added[(size_t)pair * n] : 0ll);
            }
            else if (kind == 1u)
            {
                expected = before;
                for (unsigned int input = 0u; input < n; input += 1u)
                {
                    expected += g_boundary_forward_matrix[at][input] * added[((size_t)pair * n) + input];
                }
            }
            else if (kind == 2u)
            {
                expected = -before;
            }
            else
            {
                expected = 2ll * before;
            }
            passes = passes && (after == expected);
        }
        passed[kind] += (passes != 0) ? 1u : 0u;
    }
    const unsigned int each = BOUNDARY_TEST_PAIRS / 4u;
    scriptura_text(&results->line, "  through T, of ");
    scriptura_decimal(&results->line, each, 1u);
    scriptura_text(&results->line, " pairs each: a constant lands on the lows alone on ");
    scriptura_decimal(&results->line, passed[0], 1u);
    scriptura_text(&results->line, ", 2^12 z lands as M z on ");
    scriptura_decimal(&results->line, passed[1], 1u);
    scriptura_text(&results->line, "; negation passes on ");
    scriptura_decimal(&results->line, passed[2], 1u);
    scriptura_text(&results->line, ", doubling on ");
    scriptura_decimal(&results->line, passed[3], 1u);
    scriptura_character(&results->line, '\n');
    boundary_check(results, ran != 0, "the pairs run on the host and the device, word for word");
    boundary_check(results, passed[0] == each, "a constant on every sample moves only the crystal's lows, each by it");
    boundary_check(results, passed[1] == each, "a vector in 2^(3L) Z^n moves the crystal by M times it exactly");
    boundary_check(results, (passed[2] < each) && (passed[3] < each), "negation and doubling do not pass through T");
    free(atoms);
    free(host_out);
    free(device_out);
    free(added);
}

// one lane's samples in a complexity class: 0 a ramp, 1 a ramp +-8, 2 a ramp +-1024, 3 noise over the field
void boundary_class_fill(unsigned int *atom, unsigned int kind)
{
    const long long start = (long long)(boundary_random() & 0xFFFFFu) - (1ll << 19u);
    const long long slope = (long long)(boundary_random() & 0xFFFu) - 2048ll;
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        long long value = start + (slope * (long long)at);
        if (kind == 1u)
        {
            value += (long long)(boundary_random() % 17u) - 8ll;
        }
        else if (kind == 2u)
        {
            value += (long long)(boundary_random() % 2049u) - 1024ll;
        }
        atom[at] = (kind == 3u) ? (boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u)) : boundary_word(value);
    }
}

// a value's heap: its magnitude's bits and a sign bit where it is not zero
unsigned int boundary_heap(long long value)
{
    // the magnitude of any value here is below 2^63
    unsigned long long magnitude = (value < 0ll) ? (unsigned long long)(-value) : (unsigned long long)value;
    unsigned int bits = 0u;
    while (magnitude != 0ull)
    {
        magnitude >>= 1u;
        bits += 1u;
    }
    return (bits == 0u) ? 0u : (bits + 1u);
}

// The identity of a lane's structure, taken with T and null permutations of T's input. Each lane is drawn with
// BOUNDARY_TEST_IDENTITY_DRAWS keyed shuffles
// of its own samples. A shuffle keeps every value. The samples' heap is the same on every draw, and T keeps the
// count exactly (det M = 1, Haar measure). Whatever the crystal's heap tells apart is the arrangement alone. A
// lane is identified when its crystal's heap stands below every draw's. With no arrangement to find, the lane and its
// draws are exchangeable and a lane is identified with probability at most 1/(draws + 1), as the period reading's
// null (A12).
static void boundary_identity(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int group = 1u + BOUNDARY_TEST_IDENTITY_DRAWS;
    const unsigned int lanes = BOUNDARY_TEST_CLASSES * BOUNDARY_TEST_IDENTITY_BASES * group;
    const unsigned int out_limbs = loaded->layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int first = 0u; (buffers != 0) && (first < lanes); first += group)
    {
        unsigned int *const own = &atoms[(size_t)first * n];
        boundary_class_fill(own, first / (BOUNDARY_TEST_IDENTITY_BASES * group));
        for (unsigned int draw = 1u; draw < group; draw += 1u)
        {
            unsigned int *const shuffled = &atoms[(size_t)(first + draw) * n];
            memcpy(shuffled, own, (size_t)n * sizeof(unsigned int));
            // Fisher-Yates from the top: each place swaps with one at or below it
            for (unsigned int at = n - 1u; at >= 1u; at -= 1u)
            {
                const unsigned int with = boundary_random() % (at + 1u);
                const unsigned int temporary = shuffled[at];
                shuffled[at] = shuffled[with];
                shuffled[with] = temporary;
            }
        }
    }
    const int ran = (buffers != 0) && (boundary_run(loaded, atoms, lanes, host_out, device_out) != 0);
    unsigned int identified[BOUNDARY_TEST_CLASSES] = {0u, 0u, 0u, 0u};
    unsigned long long own_heap[BOUNDARY_TEST_CLASSES] = {0ull, 0ull, 0ull, 0ull};
    unsigned long long null_heap[BOUNDARY_TEST_CLASSES] = {0ull, 0ull, 0ull, 0ull};
    int kept = 1;
    // the crystal is a one-to-one identity of its samples: a draw's crystal equals the lane's exactly when the
    // shuffle moved no value, and every draw that moved one must change the crystal
    unsigned int draws_fixed = 0u;
    unsigned int draws_one_to_one = 0u;
    for (unsigned int first = 0u; (ran != 0) && (first < lanes); first += group)
    {
        const unsigned int kind = first / (BOUNDARY_TEST_IDENTITY_BASES * group);
        unsigned long long crystal[1u + BOUNDARY_TEST_IDENTITY_DRAWS];
        unsigned long long samples[1u + BOUNDARY_TEST_IDENTITY_DRAWS];
        for (unsigned int member = 0u; member < group; member += 1u)
        {
            const unsigned int lane = first + member;
            crystal[member] = 0ull;
            samples[member] = 0ull;
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                crystal[member] += boundary_heap(boundary_read(&device_out[(size_t)lane * out_limbs],
                                                               &loaded->layout.step_table[program->outputs[at]]));
                samples[member] += boundary_heap(boundary_field(atoms[((size_t)lane * n) + at]));
            }
            kept = kept && (samples[member] == samples[0]);
        }
        int below = 1;
        for (unsigned int draw = 1u; draw < group; draw += 1u)
        {
            below = below && (crystal[0] < crystal[draw]);
            null_heap[kind] += crystal[draw];
            const int same_samples = memcmp(&atoms[(size_t)first * n], &atoms[(size_t)(first + draw) * n],
                                            (size_t)n * sizeof(unsigned int)) == 0;
            int same_crystal = 1;
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                const DeviceRecordStep *const step = &loaded->layout.step_table[program->outputs[at]];
                same_crystal = same_crystal && (boundary_read(&device_out[(size_t)first * out_limbs], step) ==
                                                boundary_read(&device_out[(size_t)(first + draw) * out_limbs], step));
            }
            draws_fixed += (same_samples != 0) ? 1u : 0u;
            draws_one_to_one += (same_samples == same_crystal) ? 1u : 0u;
        }
        own_heap[kind] += crystal[0];
        identified[kind] += (below != 0) ? 1u : 0u;
    }
    const char *const names[BOUNDARY_TEST_CLASSES] = {"ramp", "ramp +-8", "ramp +-1024", "noise"};
    scriptura_text(&results->line, "  identity by null permutation, ");
    scriptura_decimal(&results->line, BOUNDARY_TEST_IDENTITY_DRAWS, 1u);
    scriptura_text(&results->line, " draws a lane, lanes identified of ");
    scriptura_decimal(&results->line, BOUNDARY_TEST_IDENTITY_BASES, 1u);
    scriptura_text(&results->line, " (crystal heap against the draws' mean):");
    for (unsigned int kind = 0u; kind < BOUNDARY_TEST_CLASSES; kind += 1u)
    {
        scriptura_text(&results->line, (kind == 0u) ? " " : "; ");
        scriptura_text(&results->line, names[kind]);
        scriptura_character(&results->line, ' ');
        scriptura_decimal(&results->line, identified[kind], 1u);
        scriptura_text(&results->line, " (");
        boundary_hundredths(&results->line, own_heap[kind] * BOUNDARY_TEST_IDENTITY_DRAWS, null_heap[kind]);
        scriptura_character(&results->line, ')');
    }
    const unsigned int draws_total =
        BOUNDARY_TEST_CLASSES * BOUNDARY_TEST_IDENTITY_BASES * BOUNDARY_TEST_IDENTITY_DRAWS;
    scriptura_text(&results->line, "\n    one to one: ");
    scriptura_decimal(&results->line, draws_one_to_one, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, draws_total, 1u);
    scriptura_text(&results->line, " draws change the crystal exactly when they move a value (");
    scriptura_decimal(&results->line, draws_fixed, 1u);
    scriptura_text(&results->line, " moved none)\n");
    // the null's bound on identified noise lanes: bases / (draws + 1) and five of its standard deviations
    const double rate = 1.0 / (double)(BOUNDARY_TEST_IDENTITY_DRAWS + 1u);
    const double bases = (double)BOUNDARY_TEST_IDENTITY_BASES;
    const double ceiling = (bases * rate) + (5.0 * sqrt(bases * rate * (1.0 - rate)));
    boundary_check(results, ran != 0, "the identity lanes run on the host and the device, word for word");
    boundary_check(results, kept, "a null permutation keeps every value: the samples' heap is the same on every draw");
    boundary_check(results, draws_one_to_one == draws_total,
                   "the crystal is a one-to-one identity: T(pi x) = T(x) exactly when pi x = x");
    // a structured lane is not promised to be identified: a shallow ramp under +-1024 is mostly noise, and its
    // shuffles have little arrangement to destroy. What the null bounds is the rate; each structured class must
    // stand far past it
    boundary_check(results,
                   ((double)identified[0] > ceiling) && ((double)identified[1] > ceiling) &&
                       ((double)identified[2] > ceiling),
                   "each structured class is identified past the null's bound");
    boundary_check(results, (double)identified[3] <= ceiling,
                   "noise is identified no more often than the null allows, 1 / (draws + 1) within five deviations");
    free(atoms);
    free(host_out);
    free(device_out);
}
