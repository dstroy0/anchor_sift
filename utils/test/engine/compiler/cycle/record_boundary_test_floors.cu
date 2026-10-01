// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_floors.cu: floor registers, floors and the top
#include "record_boundary_test_internal.h"

// the registers standing at floor k of T then T^-1: at a forward floor l the level-l lows and the highs of levels 1
// to l, at the mirror floor 2L - l the rebuilt lows and the same highs
static unsigned int boundary_floor_registers(const BoundaryTower *tower, const BoundaryTower *back, unsigned int floor,
                                             unsigned int *registers)
{
    const unsigned int level = (floor <= BOUNDARY_TEST_LEVELS) ? floor : ((2u * BOUNDARY_TEST_LEVELS) - floor);
    const unsigned int lows = BOUNDARY_TEST_SAMPLES >> level;
    const BoundaryTower *const side = (floor <= BOUNDARY_TEST_LEVELS) ? tower : back;
    unsigned int count = 0u;
    for (unsigned int at = 0u; at < lows; at += 1u)
    {
        registers[count] = side->low[level][at];
        count += 1u;
    }
    for (unsigned int at = lows; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        registers[count] = tower->crystal[at];
        count += 1u;
    }
    return count;
}

// T then T^-1 with the mirror wraps, every floor's registers an output: the ring from the encoding's widths, the heap
// from the device's values, per floor, per class
void boundary_floors(BoundaryResults *results)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    BoundaryTower *const back = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (tower == NULL) || (back == NULL))
    {
        boundary_check(results, 0, "the floors are held");
        free(program);
        free(tower);
        free(back);
        return;
    }
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        tower->low[0][at] = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_forward(program, tower, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    // the forward's widths, encoded alone, set the mirror wraps
    EngineRecordKey twin_key;
    EngineError twin_error;
    memset(&twin_key, 0, sizeof(twin_key));
    const int twin = boundary_encode(program, program->count, n, &twin_key, &twin_error);
    boundary_check(results, twin, "the forward tower encodes alone for its widths");
    if (twin == 0)
    {
        free(program);
        free(tower);
        free(back);
        return;
    }
    boundary_inverse(program, tower->crystal, tower, &twin_key, back, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    keymath_record_release(&twin_key);
    program->output_count = 0u;
    for (unsigned int level = 0u; level < BOUNDARY_TEST_LEVELS; level += 1u)
    {
        for (unsigned int at = 0u; at < (n >> level); at += 1u)
        {
            boundary_output(program, tower->low[level][at]);
            boundary_output(program, back->low[level][at]);
        }
    }
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, n, &loaded);
    boundary_check(results, loads, "T then T^-1 with mirror wraps, every floor an output, encodes and loads");
    if (loads == 0)
    {
        free(program);
        free(tower);
        free(back);
        return;
    }
    // each output register's place in the record, by register
    unsigned int *const place = (unsigned int *)calloc(program->count, sizeof(unsigned int));
    const unsigned int lanes = BOUNDARY_TEST_CLASSES * BOUNDARY_TEST_CLASS_LANES;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    const int buffers = (place != NULL) && (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
    {
        boundary_class_fill(&atoms[(size_t)lane * n], lane / BOUNDARY_TEST_CLASS_LANES);
    }
    const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
    const int narrow = boundary_narrow_enough(&loaded, program);
    unsigned long long ring[BOUNDARY_TEST_FLOORS];
    unsigned long long heap[BOUNDARY_TEST_CLASSES][BOUNDARY_TEST_FLOORS];
    memset(heap, 0, sizeof(heap));
    unsigned int registers[BOUNDARY_TEST_FLOORS][BOUNDARY_TEST_SAMPLES];
    unsigned int counts[BOUNDARY_TEST_FLOORS];
    for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
    {
        counts[floor] = boundary_floor_registers(tower, back, floor, registers[floor]);
        ring[floor] = 0ull;
        for (unsigned int at = 0u; at < counts[floor]; at += 1u)
        {
            ring[floor] += (unsigned long long)loaded.key.term[registers[floor][at]].bits;
        }
    }
    unsigned int mirrored = 0u;
    unsigned int rebuilt = 0u;
    unsigned int within = 0u;
    for (unsigned int lane = 0u; (ran != 0) && (narrow != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
        unsigned long long lane_heap[BOUNDARY_TEST_FLOORS];
        int fits = 1;
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            lane_heap[floor] = 0ull;
            unsigned long long nonzero = 0ull;
            for (unsigned int at = 0u; at < counts[floor]; at += 1u)
            {
                const long long value = boundary_read(record, &loaded.layout.step_table[registers[floor][at]]);
                lane_heap[floor] += boundary_heap(value);
                nonzero += (value != 0ll) ? 1ull : 0ull;
            }
            fits = fits && (lane_heap[floor] <= (ring[floor] + nonzero));
            heap[lane / BOUNDARY_TEST_CLASS_LANES][floor] += lane_heap[floor];
        }
        int mirror = 1;
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            mirror = mirror && (lane_heap[floor] == lane_heap[(2u * BOUNDARY_TEST_LEVELS) - floor]);
        }
        int samples = 1;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const long long value = boundary_read(record, &loaded.layout.step_table[back->low[0][at]]);
            samples = samples && (value == boundary_field(atoms[((size_t)lane * n) + at]));
        }
        mirrored += (mirror != 0) ? 1u : 0u;
        rebuilt += (samples != 0) ? 1u : 0u;
        within += (fits != 0) ? 1u : 0u;
    }
    int ring_forward = 1;
    int ring_mirror = 1;
    int ring_widest = 1;
    for (unsigned int level = 0u; level <= BOUNDARY_TEST_LEVELS; level += 1u)
    {
        // the first level widens every register by 2 bits and each after it by 1: ring_0 + n + 2(n - n / 2^l)
        const unsigned long long integer = (unsigned long long)n;
        const unsigned long long grown = (level == 0u) ? 0ull : (integer + (2ull * (integer - (integer >> level))));
        ring_forward = ring_forward && (ring[level] == (ring[0] + grown));
        ring_widest = ring_widest && (ring[level] <= ring[BOUNDARY_TEST_LEVELS]);
        if (level < BOUNDARY_TEST_LEVELS)
        {
            ring_mirror = ring_mirror && (ring[(2u * BOUNDARY_TEST_LEVELS) - level] ==
                                          (ring[level] + (unsigned long long)(n >> level)));
            ring_widest = ring_widest && (ring[(2u * BOUNDARY_TEST_LEVELS) - level] <= ring[BOUNDARY_TEST_LEVELS]);
        }
    }
    scriptura_text(&results->line, "  floors: ");
    scriptura_decimal(&results->line, program->count, 1u);
    scriptura_text(&results->line, " steps, file ");
    scriptura_decimal(&results->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs, ");
    scriptura_decimal(&results->line, program->output_count, 1u);
    scriptura_text(&results->line, " outputs; ");
    scriptura_decimal(&results->line, rebuilt, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes rebuilt, ");
    scriptura_decimal(&results->line, mirrored, 1u);
    scriptura_text(&results->line, " with the heap mirrored at every floor, ");
    scriptura_decimal(&results->line, within, 1u);
    scriptura_text(&results->line, " inside the ring\n    ring by floor:");
    for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
    {
        scriptura_character(&results->line, ' ');
        scriptura_decimal(&results->line, ring[floor], 1u);
    }
    scriptura_character(&results->line, '\n');
    const char *const names[BOUNDARY_TEST_CLASSES] = {"ramp", "ramp +-8", "ramp +-1024", "noise"};
    unsigned long long pinch_top[BOUNDARY_TEST_CLASSES];
    unsigned long long pinch_bottom[BOUNDARY_TEST_CLASSES];
    for (unsigned int kind = 0u; kind < BOUNDARY_TEST_CLASSES; kind += 1u)
    {
        scriptura_text(&results->line, "    heap by floor, ");
        scriptura_text(&results->line, names[kind]);
        scriptura_text(&results->line, ":");
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            scriptura_character(&results->line, ' ');
            scriptura_decimal(&results->line, heap[kind][floor] / BOUNDARY_TEST_CLASS_LANES, 1u);
        }
        pinch_top[kind] = heap[kind][0];
        pinch_bottom[kind] = heap[kind][BOUNDARY_TEST_LEVELS];
        scriptura_text(&results->line, "; pinch ");
        boundary_hundredths(&results->line, pinch_top[kind], pinch_bottom[kind]);
        scriptura_character(&results->line, '\n');
    }
    int ordered = 1;
    for (unsigned int kind = 1u; kind < BOUNDARY_TEST_CLASSES; kind += 1u)
    {
        // pinch[kind - 1] > pinch[kind], cross-multiplied; every sum is below 2^40
        ordered =
            ordered && ((pinch_top[kind - 1u] * pinch_bottom[kind]) > (pinch_top[kind] * pinch_bottom[kind - 1u]));
    }
    boundary_check(results, ran != 0, "the floors run on the host and the device, word for word");
    boundary_check(results, narrow != 0, "every floor's register fits a 64-bit word");
    boundary_check(results, rebuilt == lanes, "the last floor returns every sample exactly");
    boundary_check(results, mirrored == lanes, "the heap at floor 2L - k equals the heap at floor k, every lane");
    boundary_check(results, within == lanes,
                   "every floor's heap lies inside its ring and one sign bit per nonzero value");
    boundary_check(results, ring_forward, "the ring at forward floor l >= 1 is ring_0 + n + 2(n - n / 2^l)");
    boundary_check(results, ring_mirror, "the ring at floor 2L - l is the ring at floor l and one bit per wrapped low");
    boundary_check(results, ring_widest, "the ring is widest at the crystal");
    boundary_check(results, ordered, "the heap's pinch at the crystal falls from ramp to +-8 to +-1024 to noise");
    free(place);
    free(atoms);
    free(host_out);
    free(device_out);
    free(program);
    free(tower);
    free(back);
    boundary_free(&loaded);
}

// the top projection x -> x / 2^k toward zero, the machine's own quotient by a power of two, against the 2-adic
// projection's wrap: nested quotients by 2^k and by c commute, a comparison through it is never reversed, and a sum
// through it is off by at most one. The comparison through an 8-bit wrap is counted where it reverses.
void boundary_top(BoundaryResults *results)
{
    const unsigned int shifts[BOUNDARY_TEST_TOP_SETTINGS] = {3u, 7u, 5u};
    const unsigned int divisors[BOUNDARY_TEST_TOP_SETTINGS] = {3u, 5u, 12345u};
    const unsigned int lanes = BOUNDARY_TEST_TOP_LANES;
    unsigned long long commuted = 0ull;
    unsigned long long kept = 0ull;
    unsigned long long tied = 0ull;
    unsigned long long near = 0ull;
    unsigned long long carried = 0ull;
    unsigned long long reversed = 0ull;
    int ran_all = 1;
    for (unsigned int setting = 0u; setting < BOUNDARY_TEST_TOP_SETTINGS; setting += 1u)
    {
        BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
        if (program == NULL)
        {
            ran_all = 0;
            continue;
        }
        const unsigned int x = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        const unsigned int y = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
        const unsigned int power = boundary_append(program, ENGINE_RECORD_CONSTANT, 1u << shifts[setting], 0u);
        const unsigned int divisor = boundary_append(program, ENGINE_RECORD_CONSTANT, divisors[setting], 0u);
        const unsigned int top_x = boundary_append(program, ENGINE_RECORD_QUOTIENT, x, power);
        const unsigned int top_first = boundary_append(program, ENGINE_RECORD_QUOTIENT, top_x, divisor);
        const unsigned int divided = boundary_append(program, ENGINE_RECORD_QUOTIENT, x, divisor);
        const unsigned int top_last = boundary_append(program, ENGINE_RECORD_QUOTIENT, divided, power);
        const unsigned int order = boundary_append(program, ENGINE_RECORD_COMPARE, x, y);
        const unsigned int top_y = boundary_append(program, ENGINE_RECORD_QUOTIENT, y, power);
        const unsigned int top_order = boundary_append(program, ENGINE_RECORD_COMPARE, top_x, top_y);
        const unsigned int sum = boundary_append(program, ENGINE_RECORD_SUM, x, y);
        const unsigned int top_sum = boundary_append(program, ENGINE_RECORD_QUOTIENT, sum, power);
        const unsigned int sum_top = boundary_append(program, ENGINE_RECORD_SUM, top_x, top_y);
        const unsigned int wrapped_x = boundary_append(program, ENGINE_RECORD_WRAP, x, 8u);
        const unsigned int wrapped_y = boundary_append(program, ENGINE_RECORD_WRAP, y, 8u);
        const unsigned int wrapped_order = boundary_append(program, ENGINE_RECORD_COMPARE, wrapped_x, wrapped_y);
        const unsigned int outputs[7] = {top_first, top_last, order, top_order, top_sum, sum_top, wrapped_order};
        for (unsigned int at = 0u; at < 7u; at += 1u)
        {
            boundary_output(program, outputs[at]);
        }
        BoundaryLoaded loaded;
        if (boundary_load(program, 2u, &loaded) == 0)
        {
            ran_all = 0;
            free(program);
            continue;
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * 2u, sizeof(unsigned int));
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
        for (unsigned int word = 0u; (buffers != 0) && (word < (2u * lanes)); word += 1u)
        {
            atoms[word] = boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u);
        }
        const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
        ran_all = ran_all && ran && boundary_narrow_enough(&loaded, program);
        for (unsigned int lane = 0u; (ran != 0) && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            long long value[7];
            for (unsigned int at = 0u; at < 7u; at += 1u)
            {
                value[at] = boundary_read(record, &loaded.layout.step_table[outputs[at]]);
            }
            commuted += (value[0] == value[1]) ? 1ull : 0ull;
            kept += ((value[3] == 0ll) || (value[3] == value[2])) ? 1ull : 0ull;
            tied += ((value[3] == 0ll) && (value[2] != 0ll)) ? 1ull : 0ull;
            const long long off = value[4] - value[5];
            near += ((off >= -1ll) && (off <= 1ll)) ? 1ull : 0ull;
            carried += (off != 0ll) ? 1ull : 0ull;
            reversed += ((value[6] != 0ll) && (value[6] == -value[2])) ? 1ull : 0ull;
        }
        free(atoms);
        free(host_out);
        free(device_out);
        free(program);
        boundary_free(&loaded);
    }
    const unsigned long long total = (unsigned long long)BOUNDARY_TEST_TOP_SETTINGS * lanes;
    scriptura_text(&results->line, "  top projection, x / 2^k for k = 3, 7, 5 and c = 3, 5, 12345 over ");
    scriptura_decimal(&results->line, total, 1u);
    scriptura_text(&results->line, " lanes: nested quotients agree on ");
    scriptura_decimal(&results->line, commuted, 1u);
    scriptura_text(&results->line, ", the order is kept on ");
    scriptura_decimal(&results->line, kept, 1u);
    scriptura_text(&results->line, " (tied on ");
    scriptura_decimal(&results->line, tied, 1u);
    scriptura_text(&results->line, "), the sum is within one on ");
    scriptura_decimal(&results->line, near, 1u);
    scriptura_text(&results->line, " (carried on ");
    scriptura_decimal(&results->line, carried, 1u);
    scriptura_text(&results->line, "); the 8-bit wrap reverses the order on ");
    scriptura_decimal(&results->line, reversed, 1u);
    scriptura_character(&results->line, '\n');
    boundary_check(results, ran_all != 0, "the top projections run on the host and the device, word for word");
    boundary_check(results, commuted == total,
                   "the quotient by c passes through the top projection: (x / 2^k) / c = (x / c) / 2^k");
    boundary_check(results, kept == total, "the top projection never reverses a comparison, it only ties");
    boundary_check(results, (near == total) && (carried != 0ull),
                   "a sum through the top projection is off by the carry from below, at most one");
    boundary_check(results, reversed != 0ull, "the 8-bit wrap reverses comparisons the top projection keeps");
}
