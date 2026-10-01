// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_run.cu: loading, running and reading, precision and bands
#include "record_boundary_test_internal.h"

// each field its own 32-bit word, `fields` words a lane, laid out with register reuse
int boundary_load(const BoundaryProgram *program, unsigned int fields, BoundaryLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    if ((program->overflow != 0) ||
        (boundary_encode(program, program->count, fields, &loaded->key, &loaded->error) == 0))
    {
        return 0;
    }
    unsigned int field_offset[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < fields; at += 1u)
    {
        field_offset[at] = 32u * at;
    }
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {fields, 0u, 0u};
    const KeyScheduleRecordRequest layout_request = {&loaded->key,    field_offset,  fields, in_limbs, 1,
                                                     &loaded->layout, &loaded->error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    if (cycle_record_load(&loaded->layout, &loaded->record, &loaded->error) == CYCLE_ERROR)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

void boundary_free(BoundaryLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host and on the device; 1 where both ran and their records agree
// word for word
int boundary_run(BoundaryLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                 unsigned int *device_out)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out,        &loaded->error};
    const int host_ran = cycle_record_run_host(&host) != CYCLE_ERROR;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int ok = (cudaMalloc((void **)&device_atoms, (size_t)count * in_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_record, (size_t)count * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMemcpy(device_atoms, atoms, (size_t)count * in_limbs * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {
            loaded->record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count, device_record,
            &loaded->error};
        ok = cycle_record_run(&run) != CYCLE_ERROR;
        ok = ok && (cudaMemcpy(device_out, device_record, (size_t)count * out_limbs * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    return (host_ran != 0) && (ok != 0) &&
           (memcmp(host_out, device_out, (size_t)count * out_limbs * sizeof(unsigned int)) == 0);
}

// a field's word: the value's low 24 bits of two's complement
unsigned int boundary_word(long long value)
{
    // the mask keeps the low 24 bits, the field's whole content
    return (unsigned int)((unsigned long long)value & ((1ull << BOUNDARY_TEST_FIELD_BITS) - 1ull));
}

// a field's word read back signed: 2^24 comes off where its top bit is set
long long boundary_field(unsigned int word)
{
    const long long raw = (long long)word;
    return ((word >> (BOUNDARY_TEST_FIELD_BITS - 1u)) != 0u) ? (raw - (1ll << BOUNDARY_TEST_FIELD_BITS)) : raw;
}

// one output's value from a lane's record: its out_bits of two's complement, the top written bit the sign. Every
// output here is 64 bits or narrower, which the caller holds before reading.
long long boundary_read(const unsigned int *record, const DeviceRecordStep *step)
{
    unsigned long long raw = 0ull;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        raw |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if ((step->out_bits < 64u) && (((raw >> (step->out_bits - 1u)) & 1u) != 0ull))
    {
        raw |= ~0ull << step->out_bits;
    }
    // the word is the value's two's complement. The conversion reads it back signed
    return (long long)raw;
}

// every output of a loaded program fits the oracle's 64-bit word
int boundary_narrow_enough(const BoundaryLoaded *loaded, const BoundaryProgram *program)
{
    int passed = 1;
    for (unsigned int output = 0u; output < program->output_count; output += 1u)
    {
        passed = passed && (loaded->layout.step_table[program->outputs[output]].out_bits <= 64u);
    }
    return passed;
}

// flip one input bit b per lane pair and read the move at the first n outputs. For b >= REACH the move must be
// exactly 2^b times column i of the map's matrix; for every b it must lie at bit b - bound or above. Each lane must
// also equal the host's map, and with readback the next n outputs must return the inputs. The greatest reach met
// comes back in range_seen.
void boundary_precision(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program,
                        BoundaryMap map, const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int bound,
                        int readback, const char *name, int *range_seen)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int lanes = 2u * BOUNDARY_TEST_PAIRS;
    const unsigned int out_limbs = loaded->layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const flip_at = (unsigned int *)calloc(BOUNDARY_TEST_PAIRS, sizeof(unsigned int));
    unsigned int *const flip_bit = (unsigned int *)calloc(BOUNDARY_TEST_PAIRS, sizeof(unsigned int));
    const int buffers =
        (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (flip_at != NULL) && (flip_bit != NULL);
    for (unsigned int pair = 0u; (buffers != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        unsigned int *const base = &atoms[(size_t)(2u * pair) * n];
        unsigned int *const moved = &atoms[(size_t)((2u * pair) + 1u) * n];
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            base[at] = boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u);
            moved[at] = base[at];
        }
        flip_at[pair] = boundary_random() % n;
        flip_bit[pair] = boundary_random() % (BOUNDARY_TEST_FLIP_TOP + 1u);
        moved[flip_at[pair]] ^= 1u << flip_bit[pair];
    }
    const int ran = (buffers != 0) && (boundary_run(loaded, atoms, lanes, host_out, device_out) != 0);
    const int narrow = boundary_narrow_enough(loaded, program);
    unsigned int mapped = 0u;
    unsigned int returned = 0u;
    unsigned int lawful = 0u;
    unsigned int lawful_pairs = 0u;
    unsigned int bounded = 0u;
    // a single flipped bit must move some output: the map is one to one. No flip leaves the image unchanged
    unsigned int changed = 0u;
    int seen = -1000;
    for (unsigned int pair = 0u; (ran != 0) && (narrow != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        long long out[2][BOUNDARY_TEST_SAMPLES];
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int lane = (2u * pair) + side;
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            long long in[BOUNDARY_TEST_SAMPLES];
            long long expected[BOUNDARY_TEST_SAMPLES];
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                in[at] = boundary_field(atoms[((size_t)lane * n) + at]);
            }
            map(in, expected);
            int equal = 1;
            int back = 1;
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                out[side][at] = boundary_read(record, &loaded->layout.step_table[program->outputs[at]]);
                equal = equal && (out[side][at] == expected[at]);
                if (readback != 0)
                {
                    back =
                        back && (boundary_read(record, &loaded->layout.step_table[program->outputs[n + at]]) == in[at]);
                }
            }
            mapped += (equal != 0) ? 1u : 0u;
            returned += (back != 0) ? 1u : 0u;
        }
        const unsigned int input = flip_at[pair];
        const unsigned int bit = flip_bit[pair];
        // a set bit cleared moves the value down by 2^b, a clear bit set moves it up
        const long long sign = (((atoms[((size_t)(2u * pair) * n) + input] >> bit) & 1u) != 0u) ? -1ll : 1ll;
        const int in_law = bit >= BOUNDARY_TEST_RANGE;
        int law = 1;
        int within = 1;
        int moved_any = 0;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const long long move = out[1][at] - out[0][at];
            moved_any = moved_any || (move != 0ll);
            if (in_law != 0)
            {
                law = law && (move == (sign * matrix[at][input] * (1ll << (bit - BOUNDARY_TEST_RANGE))));
            }
            if (move != 0ll)
            {
                const int range = (int)bit - boundary_valuation(move);
                within = within && (range <= (int)bound);
                seen = (range > seen) ? range : seen;
            }
        }
        lawful_pairs += (in_law != 0) ? 1u : 0u;
        lawful += ((in_law != 0) && (law != 0)) ? 1u : 0u;
        bounded += (within != 0) ? 1u : 0u;
        changed += (moved_any != 0) ? 1u : 0u;
    }
    *range_seen = seen;
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, ": ");
    scriptura_decimal(&results->line, program->count, 1u);
    scriptura_text(&results->line, " steps, file ");
    scriptura_decimal(&results->line, loaded->layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs; ");
    scriptura_decimal(&results->line, mapped, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes equal the host's map");
    if (readback != 0)
    {
        scriptura_text(&results->line, ", ");
        scriptura_decimal(&results->line, returned, 1u);
        scriptura_text(&results->line, " return their crystal exactly");
    }
    scriptura_text(&results->line, "\n    flips: ");
    scriptura_decimal(&results->line, lawful, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lawful_pairs, 1u);
    scriptura_text(&results->line, " at bit 12 or above move by exactly 2^b M e_i; ");
    scriptura_decimal(&results->line, bounded, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, BOUNDARY_TEST_PAIRS, 1u);
    scriptura_text(&results->line, " reach no further than ");
    scriptura_decimal(&results->line, bound, 1u);
    scriptura_text(&results->line, " bits below the flip; the furthest reach met is ");
    scriptura_signed(&results->line, seen);
    scriptura_text(&results->line, "; ");
    scriptura_decimal(&results->line, changed, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, BOUNDARY_TEST_PAIRS, 1u);
    scriptura_text(&results->line, " flips change the image\n");
    boundary_check(results, ran != 0,
                   "the program runs on the host and the device, and the records agree word for word");
    boundary_check(results, narrow != 0, "every output fits a 64-bit word");
    boundary_check(results, mapped == lanes, "every lane equals the host's map");
    if (readback != 0)
    {
        boundary_check(results, returned == lanes,
                       "a crystal written onto the boundary is read back exactly: T . T^-1 = id");
    }
    boundary_check(results, (lawful_pairs != 0u) && (lawful == lawful_pairs),
                   "a flip at bit 3L or above moves the outputs by exactly 2^b times the matrix's column");
    boundary_check(results, bounded == BOUNDARY_TEST_PAIRS, "no flip reaches further below itself than the bound");
    boundary_check(results, changed == BOUNDARY_TEST_PAIRS,
                   "every single flipped bit changes the image: the map is one to one");
    free(atoms);
    free(host_out);
    free(device_out);
    free(flip_at);
    free(flip_bit);
}

// the crystal band a coefficient lies in: 0 for the level-L lows, l for the highs of level l
static unsigned int boundary_band(unsigned int at)
{
    if (at < (BOUNDARY_TEST_SAMPLES >> BOUNDARY_TEST_LEVELS))
    {
        return 0u;
    }
    unsigned int level = BOUNDARY_TEST_LEVELS;
    while (at >= (BOUNDARY_TEST_SAMPLES >> (level - 1u)))
    {
        level -= 1u;
    }
    return level;
}

// T's range read off its matrix per band, against the count: 3L for the level-L lows, 3l - 2 for the highs of level l
void boundary_bands(BoundaryResults *results)
{
    int range[BOUNDARY_TEST_LEVELS + 1u];
    for (unsigned int band = 0u; band <= BOUNDARY_TEST_LEVELS; band += 1u)
    {
        range[band] = -1000;
    }
    int inverse_range = -1000;
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        const unsigned int band = boundary_band(at);
        const int here = boundary_row_range(g_boundary_forward_matrix, at);
        range[band] = (here > range[band]) ? here : range[band];
        const int back = boundary_row_range(g_boundary_inverse_matrix, at);
        inverse_range = (back > inverse_range) ? back : inverse_range;
    }
    int counted = range[0] == (int)(3u * BOUNDARY_TEST_LEVELS);
    scriptura_text(&results->line, "  bands: T's matrix reaches ");
    scriptura_signed(&results->line, range[0]);
    scriptura_text(&results->line, " bits from the level-4 lows, and from the highs of levels 4 to 1");
    for (unsigned int level = BOUNDARY_TEST_LEVELS; level >= 1u; level -= 1u)
    {
        scriptura_character(&results->line, ' ');
        scriptura_signed(&results->line, range[level]);
        counted = counted && (range[level] == ((3 * (int)level) - 2));
    }
    scriptura_text(&results->line, "; T^-1's matrix reaches ");
    scriptura_signed(&results->line, inverse_range);
    scriptura_text(&results->line, " bits\n");
    boundary_check(results, counted, "T's range is 3l at the level-l lows and 3l - 2 at its highs, on the matrix");
    boundary_check(results, inverse_range == (int)BOUNDARY_TEST_INVERSE_RANGE, "T^-1's range is L + 2, on the matrix");
}
