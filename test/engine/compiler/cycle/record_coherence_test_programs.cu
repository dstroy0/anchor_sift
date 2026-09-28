// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_coherence_test_programs.cu: draws, builds and programs
#include "record_coherence_test_internal.h"

static unsigned long long s_coherence_state = 0x2AD1C0DE5EED0001ull;

unsigned int coherence_random(void)
{
    s_coherence_state ^= s_coherence_state << 13u;
    s_coherence_state ^= s_coherence_state >> 7u;
    s_coherence_state ^= s_coherence_state << 17u;
    return (unsigned int)(s_coherence_state >> 16u);
}

void coherence_check(CoherenceResults *results, int passed, const char *what)
{
    results->checks += 1ull;
    if (passed == 0)
    {
        results->failures += 1ull;
        scriptura_text(&results->line, "  FAILED: ");
        scriptura_text(&results->line, what);
        scriptura_character(&results->line, '\n');
    }
}

unsigned int coherence_append(CoherenceProgram *program, EngineRecordOperation operation, unsigned int left,
                              unsigned int right)
{
    program->steps[program->count] = EngineRecordStep{operation, left, right, 0u};
    program->count += 1u;
    return program->count - 1u;
}

void coherence_output(CoherenceProgram *program, unsigned int step)
{
    program->outputs[program->output_count] = step;
    program->output_count += 1u;
}

int coherence_load(const CoherenceProgram *program, unsigned int fields, CoherenceLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    unsigned int field_bits[COHERENCE_TEST_INPUTS];
    unsigned int field_offset[COHERENCE_TEST_INPUTS];
    for (unsigned int field = 0u; field < fields; field += 1u)
    {
        field_bits[field] = COHERENCE_TEST_INPUT_BITS;
        field_offset[field] = 32u * field;
    }
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {fields, 0u, 0u};
    const KeymathRecordRequest encode_request = {
        program->steps,  program->count,       field_bits,   fields,        1u, program->outputs, program->output_count,
        program->tables, program->table_count, &loaded->key, &loaded->error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
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

void coherence_free(CoherenceLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
void coherence_run(CoherenceLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                   unsigned int *device_out, int *host_ran, int *device_ran)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out,        &loaded->error};
    *host_ran = cycle_record_run_host(&host) != CYCLE_ERROR;
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
    *device_ran = ok;
}

// an output of at most 64 bits, read back as two's complement
long long coherence_take(const unsigned int *record, const DeviceRecordStep *step)
{
    unsigned long long low = 0ull;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        low |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if ((step->out_bits < 64u) && (((low >> (step->out_bits - 1u)) & 1ull) != 0ull))
    {
        low |= ~0ull << step->out_bits;
    }
    // a two's complement word read back as signed: the bit pattern is the value
    return (long long)low;
}

// a native 64-bit two's complement word reduced to w bits and read back signed, as ENGINE_RECORD_WRAP reads it
long long coherence_reduce(unsigned long long word, unsigned int bits)
{
    const unsigned long long low = word & ((1ull << bits) - 1ull);
    const unsigned long long top = 1ull << (bits - 1u);
    // a set top kept bit means 2^bits comes off: low - top - top, taken apart so neither half leaves the signed range
    return ((low & top) != 0ull) ? ((long long)(low - top) - (long long)top) : (long long)low;
}

static unsigned long long coherence_native(EngineRecordOperation operation, unsigned long long left,
                                           unsigned long long right)
{
    if (operation == ENGINE_RECORD_SUM)
    {
        return left + right;
    }
    if (operation == ENGINE_RECORD_DIFFERENCE)
    {
        return left - right;
    }
    if (operation == ENGINE_RECORD_PRODUCT)
    {
        return left * right;
    }
    if (operation == ENGINE_RECORD_XOR)
    {
        return left ^ right;
    }
    return left & right;
}

// one random program of COHERENCE_TEST_OPERATIONS operations over the inputs and the values before: the ring and the
// bitwise operations, or with ring_only the sum, difference and product alone
void coherence_draw(CoherenceOperation *operations, int ring_only)
{
    static const EngineRecordOperation kinds[5] = {ENGINE_RECORD_SUM, ENGINE_RECORD_DIFFERENCE, ENGINE_RECORD_PRODUCT,
                                                   ENGINE_RECORD_XOR, ENGINE_RECORD_AND};
    const unsigned int kind_count = (ring_only != 0) ? 3u : 5u;
    unsigned int products = 0u;
    for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
    {
        EngineRecordOperation operation = kinds[coherence_random() % kind_count];
        if ((operation == ENGINE_RECORD_PRODUCT) && (products == COHERENCE_TEST_PRODUCTS_MAX))
        {
            operation = (ring_only != 0) ? ENGINE_RECORD_SUM : ENGINE_RECORD_XOR;
        }
        products += (operation == ENGINE_RECORD_PRODUCT) ? 1u : 0u;
        const unsigned int range = COHERENCE_TEST_INPUTS + at;
        operations[at].operation = operation;
        operations[at].left = coherence_random() % range;
        // the last operation reads the one before it. The output depends on the whole program
        operations[at].right = (at + 1u == COHERENCE_TEST_OPERATIONS) ? (range - 1u) : (coherence_random() % range);
    }
}

// the record program for one drawn program: the exact run, then at each width its wrap and the run wrapped at every
// step. Outputs, in order: for each width, the wrapped exact result, then the result wrapped at every step.
static void coherence_build(const CoherenceOperation *operations, CoherenceProgram *program)
{
    memset(program, 0, sizeof(*program));
    unsigned int value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
    for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
    {
        value[input] = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, input, 0u);
    }
    for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
    {
        value[COHERENCE_TEST_INPUTS + at] = coherence_append(program, operations[at].operation,
                                                             value[operations[at].left], value[operations[at].right]);
    }
    const unsigned int exact = value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
    for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
    {
        const unsigned int bits = s_coherence_widths[width];
        coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, exact, bits));
        unsigned int wrapped[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
        for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
        {
            wrapped[input] = coherence_append(program, ENGINE_RECORD_WRAP, value[input], bits);
        }
        for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
        {
            const unsigned int step = coherence_append(program, operations[at].operation, wrapped[operations[at].left],
                                                       wrapped[operations[at].right]);
            wrapped[COHERENCE_TEST_INPUTS + at] = coherence_append(program, ENGINE_RECORD_WRAP, step, bits);
        }
        coherence_output(program, wrapped[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u]);
    }
}

// signed 24-bit inputs in edge cases: random, zero, -1, the most negative, the most positive, one
unsigned int coherence_input(unsigned int pattern)
{
    const unsigned int mask = (1u << COHERENCE_TEST_INPUT_BITS) - 1u;
    const unsigned int kind = pattern % 8u;
    if (kind == 1u)
    {
        return 0u;
    }
    if (kind == 2u)
    {
        return mask;
    }
    if (kind == 3u)
    {
        return 1u << (COHERENCE_TEST_INPUT_BITS - 1u);
    }
    if (kind == 4u)
    {
        return mask >> 1u;
    }
    if (kind == 5u)
    {
        return 1u;
    }
    return coherence_random() & mask;
}

long long coherence_signed_input(unsigned int raw)
{
    const unsigned int top = 1u << (COHERENCE_TEST_INPUT_BITS - 1u);
    return ((raw & top) != 0u) ? ((long long)raw - (long long)(1u << COHERENCE_TEST_INPUT_BITS)) : (long long)raw;
}

void coherence_programs(CoherenceResults *results)
{
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * COHERENCE_TEST_INPUTS, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(results, 0, "the coherence lanes are held");
        free(atoms);
        free(program);
        return;
    }
    unsigned int loaded_all = 1u;
    unsigned int words_all = 1u;
    unsigned long long agreements = 0ull;
    unsigned long long comparisons = 0ull;
    unsigned int widest = 0u;
    for (unsigned int drawn = 0u; drawn < COHERENCE_TEST_PROGRAMS; drawn += 1u)
    {
        CoherenceOperation operations[COHERENCE_TEST_OPERATIONS];
        coherence_draw(operations, 0);
        coherence_build(operations, program);
        CoherenceLoaded loaded;
        if (coherence_load(program, COHERENCE_TEST_INPUTS, &loaded) == 0)
        {
            loaded_all = 0u;
            continue;
        }
        for (unsigned int step = 0u; step < program->count; step += 1u)
        {
            widest = (loaded.key.term[step].bits > widest) ? loaded.key.term[step].bits : widest;
        }
        for (unsigned int at = 0u; at < lanes * COHERENCE_TEST_INPUTS; at += 1u)
        {
            atoms[at] = coherence_input(coherence_random());
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        int host_ran = 0;
        int device_ran = 0;
        if ((host_out != NULL) && (device_out != NULL))
        {
            coherence_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        }
        words_all = words_all && host_ran && device_ran &&
                    (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            // the third reckoning: native 64-bit two's complement, itself a projection of the same 2-adic run
            unsigned long long native[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
            for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
            {
                // a signed input's two's complement word: the cast keeps its bits
                native[input] = (unsigned long long)coherence_signed_input(atoms[lane * COHERENCE_TEST_INPUTS + input]);
            }
            for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
            {
                native[COHERENCE_TEST_INPUTS + at] = coherence_native(
                    operations[at].operation, native[operations[at].left], native[operations[at].right]);
            }
            const unsigned long long result = native[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
            {
                const long long expected = coherence_reduce(result, s_coherence_widths[width]);
                const long long projected =
                    coherence_take(record, &loaded.layout.step_table[program->outputs[2u * width]]);
                const long long stepped =
                    coherence_take(record, &loaded.layout.step_table[program->outputs[(2u * width) + 1u]]);
                comparisons += 1ull;
                agreements += ((projected == expected) && (stepped == expected)) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&results->line, "  coherence: ");
    scriptura_decimal(&results->line, COHERENCE_TEST_PROGRAMS, 1u);
    scriptura_text(&results->line, " random programs of ");
    scriptura_decimal(&results->line, COHERENCE_TEST_OPERATIONS, 1u);
    scriptura_text(&results->line, " operations, widest exact register ");
    scriptura_decimal(&results->line, widest, 1u);
    scriptura_text(&results->line, " bits; ");
    scriptura_decimal(&results->line, agreements, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, comparisons, 1u);
    scriptura_text(&results->line, " lane-widths agree three ways\n");
    coherence_check(results, loaded_all, "every random program encodes, lays out and loads");
    coherence_check(results, words_all, "every program's device records equal the host's word for word");
    coherence_check(results, (comparisons != 0ull) && (agreements == comparisons),
                    "wrapping the exact run, running wrapped at every step and native 64-bit two's complement agree at "
                    "every width on every lane");
    free(atoms);
    free(program);
}
