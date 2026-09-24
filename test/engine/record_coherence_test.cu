// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine computes coherently with the 2-adic integers. A two's complement register sign-extended without
// end is a 2-adic integer, and ENGINE_RECORD_WRAP to w bits is the projection onto Z / 2^w. Sum, difference, product,
// xor and and commute with every projection: a program of them run exactly and then wrapped to w equals the same
// program run wrapped to w at every step. Random programs are run both ways at several widths in one record program,
// and both must equal a third reckoning in native 64-bit two's complement reduced to w, on every lane; the device must
// equal the host word for word. A quotient and a comparison read the whole integer rather than its low bits, and must
// break the agreement on some lane. An exact quotient by an odd c is the product by c^-1 in Z_2, and must equal that
// product in every projection. The odd crystals Z_3, Z_5 and Z_7 are orthogonal to Z_2: a ring program commutes with
// the remainder by p^v as it does with the wrap, the machine joins the two windows into the exact run modulo 2^w p^v,
// and an xor, the 2-adic crystal's alone, breaks modulo 3.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "exact_integer.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define COHERENCE_TEST_LINE 8192ull

#define COHERENCE_TEST_STEPS 256u

#define COHERENCE_TEST_OUTPUTS 16u

#define COHERENCE_TEST_INPUTS 4u

#define COHERENCE_TEST_INPUT_BITS 24u

#define COHERENCE_TEST_OPERATIONS 10u

// a program keeps at most this many products, so the exact widths stay well inside the file
#define COHERENCE_TEST_PRODUCTS_MOST 2u

#define COHERENCE_TEST_PROGRAMS 16u

#define COHERENCE_TEST_WIDTHS 6u

#define COHERENCE_TEST_LANES 4096u

static const unsigned int s_coherence_widths[COHERENCE_TEST_WIDTHS] = {5u, 8u, 13u, 16u, 31u, 32u};

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} CoherenceTally;

typedef struct
{
    EngineRecordStep steps[COHERENCE_TEST_STEPS];
    unsigned int count;
    unsigned int outputs[COHERENCE_TEST_OUTPUTS];
    unsigned int output_count;
} CoherenceProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} CoherenceLoaded;

// one operation of a random program: which, and the two earlier values it reads, as indices into the program's values
typedef struct
{
    EngineRecordOperation operation;
    unsigned int left;
    unsigned int right;
} CoherenceOperation;

static unsigned long long s_coherence_state = 0x2AD1C0DE5EED0001ull;

static unsigned int coherence_random(void)
{
    s_coherence_state ^= s_coherence_state << 13u;
    s_coherence_state ^= s_coherence_state >> 7u;
    s_coherence_state ^= s_coherence_state << 17u;
    return (unsigned int)(s_coherence_state >> 16u);
}

static void coherence_check(CoherenceTally *tally, int held, const char *what)
{
    tally->checks += 1ull;
    if (held == 0)
    {
        tally->failures += 1ull;
        scriptura_text(&tally->line, "  FAILED: ");
        scriptura_text(&tally->line, what);
        scriptura_character(&tally->line, '\n');
    }
}

static unsigned int coherence_emit(CoherenceProgram *program, EngineRecordOperation operation, unsigned int left,
                                   unsigned int right)
{
    program->steps[program->count] = EngineRecordStep{operation, left, right, 0u};
    program->count += 1u;
    return program->count - 1u;
}

static void coherence_output(CoherenceProgram *program, unsigned int step)
{
    program->outputs[program->output_count] = step;
    program->output_count += 1u;
}

static int coherence_load(const CoherenceProgram *program, unsigned int fields, CoherenceLoaded *loaded)
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
    const KeymathRecordRequest imprint = {program->steps, program->count, field_bits, fields, 1u, program->outputs,
                                          program->output_count, NULL, 0u, &loaded->key, &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&loaded->key, field_offset, fields, in_limbs, 1, &loaded->layout,
                                          &loaded->error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    if (cycle_record_load(&loaded->layout, &loaded->record, &loaded->error) == CYCLE_REFUSED)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

static void coherence_free(CoherenceLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
static void coherence_run(CoherenceLoaded *loaded, const unsigned int *atoms, unsigned int count,
                          unsigned int *host_out, unsigned int *device_out, int *host_ran, int *device_ran)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out};
    *host_ran = cycle_record_run_host(&host) != CYCLE_REFUSED;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int good = (cudaMalloc((void **)&device_atoms, (size_t)count * in_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&device_record, (size_t)count * out_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMemcpy(device_atoms, atoms, (size_t)count * in_limbs * sizeof(unsigned int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (good != 0)
    {
        const CycleRecordRunRequest run = {loaded->record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL,
                                           count, device_record, &loaded->error};
        good = cycle_record_run(&run) != CYCLE_REFUSED;
        good = good
            && (cudaMemcpy(device_out, device_record, (size_t)count * out_limbs * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost)
                == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    *device_ran = good;
}

// an output of at most 64 bits, read back as two's complement
static long long coherence_take(const unsigned int *record, const DeviceRecordStep *step)
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
static long long coherence_reduce(unsigned long long word, unsigned int bits)
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
static void coherence_draw(CoherenceOperation *operations, int ring_only)
{
    static const EngineRecordOperation kinds[5] = {ENGINE_RECORD_SUM, ENGINE_RECORD_DIFFERENCE, ENGINE_RECORD_PRODUCT,
                                                   ENGINE_RECORD_XOR, ENGINE_RECORD_AND};
    const unsigned int kind_count = (ring_only != 0) ? 3u : 5u;
    unsigned int products = 0u;
    for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
    {
        EngineRecordOperation operation = kinds[coherence_random() % kind_count];
        if ((operation == ENGINE_RECORD_PRODUCT) && (products == COHERENCE_TEST_PRODUCTS_MOST))
        {
            operation = (ring_only != 0) ? ENGINE_RECORD_SUM : ENGINE_RECORD_XOR;
        }
        products += (operation == ENGINE_RECORD_PRODUCT) ? 1u : 0u;
        const unsigned int reach = COHERENCE_TEST_INPUTS + at;
        operations[at].operation = operation;
        operations[at].left = coherence_random() % reach;
        // the last operation reads the one before it, so the output depends on the whole program
        operations[at].right = (at + 1u == COHERENCE_TEST_OPERATIONS) ? (reach - 1u) : (coherence_random() % reach);
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
        value[input] = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, input, 0u);
    }
    for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
    {
        value[COHERENCE_TEST_INPUTS + at] = coherence_emit(program, operations[at].operation,
                                                           value[operations[at].left], value[operations[at].right]);
    }
    const unsigned int exact = value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
    for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
    {
        const unsigned int bits = s_coherence_widths[width];
        coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, exact, bits));
        unsigned int wrapped[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
        for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
        {
            wrapped[input] = coherence_emit(program, ENGINE_RECORD_WRAP, value[input], bits);
        }
        for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
        {
            const unsigned int step = coherence_emit(program, operations[at].operation, wrapped[operations[at].left],
                                                     wrapped[operations[at].right]);
            wrapped[COHERENCE_TEST_INPUTS + at] = coherence_emit(program, ENGINE_RECORD_WRAP, step, bits);
        }
        coherence_output(program, wrapped[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u]);
    }
}

// signed 24-bit inputs in edge shapes: random, zero, -1, the most negative, the most positive, one
static unsigned int coherence_input(unsigned int shape)
{
    const unsigned int mask = (1u << COHERENCE_TEST_INPUT_BITS) - 1u;
    const unsigned int kind = shape % 8u;
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

static long long coherence_signed_input(unsigned int raw)
{
    const unsigned int top = 1u << (COHERENCE_TEST_INPUT_BITS - 1u);
    return ((raw & top) != 0u) ? ((long long)raw - (long long)(1u << COHERENCE_TEST_INPUT_BITS)) : (long long)raw;
}

static void coherence_programs(CoherenceTally *tally)
{
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * COHERENCE_TEST_INPUTS, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(tally, 0, "the coherence lanes are held");
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
        words_all = words_all && host_ran && device_ran
                 && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
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
                native[COHERENCE_TEST_INPUTS + at] = coherence_native(operations[at].operation,
                                                                      native[operations[at].left],
                                                                      native[operations[at].right]);
            }
            const unsigned long long result = native[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
            {
                const long long expected = coherence_reduce(result, s_coherence_widths[width]);
                const long long projected = coherence_take(record, &loaded.layout.step_table[program->outputs[2u * width]]);
                const long long stepped = coherence_take(record,
                                                         &loaded.layout.step_table[program->outputs[(2u * width) + 1u]]);
                comparisons += 1ull;
                agreements += ((projected == expected) && (stepped == expected)) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&tally->line, "  coherence: ");
    scriptura_decimal(&tally->line, COHERENCE_TEST_PROGRAMS, 1u);
    scriptura_text(&tally->line, " random programs of ");
    scriptura_decimal(&tally->line, COHERENCE_TEST_OPERATIONS, 1u);
    scriptura_text(&tally->line, " operations, widest exact register ");
    scriptura_decimal(&tally->line, widest, 1u);
    scriptura_text(&tally->line, " bits; ");
    scriptura_decimal(&tally->line, agreements, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, comparisons, 1u);
    scriptura_text(&tally->line, " lane-widths agree three ways\n");
    coherence_check(tally, loaded_all, "every random program imprints, lays and loads");
    coherence_check(tally, words_all, "every program's device records equal the host's word for word");
    coherence_check(tally, (comparisons != 0ull) && (agreements == comparisons),
                    "wrapping the exact run, running wrapped at every step and native 64-bit two's complement agree at "
                    "every width on every lane");
    free(atoms);
    free(program);
}

// a quotient and a comparison read the whole integer: wrapping before and after them disagree on some lane
static void coherence_broken(CoherenceTally *tally)
{
    const unsigned int bits = 8u;
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    if ((program == NULL) || (atoms == NULL))
    {
        coherence_check(tally, 0, "the broken lanes are held");
        free(program);
        free(atoms);
        return;
    }
    const unsigned int value = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    const unsigned int three = coherence_emit(program, ENGINE_RECORD_CONSTANT, 3u, 0u);
    const unsigned int zero = coherence_emit(program, ENGINE_RECORD_CONSTANT, 0u, 0u);
    const unsigned int wrapped = coherence_emit(program, ENGINE_RECORD_WRAP, value, bits);
    const unsigned int quotient = coherence_emit(program, ENGINE_RECORD_QUOTIENT, value, three);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, quotient, bits));
    const unsigned int quotient_wrapped = coherence_emit(program, ENGINE_RECORD_QUOTIENT, wrapped, three);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, quotient_wrapped, bits));
    const unsigned int compare = coherence_emit(program, ENGINE_RECORD_COMPARE, value, zero);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, compare, bits));
    const unsigned int compare_wrapped = coherence_emit(program, ENGINE_RECORD_COMPARE, wrapped, zero);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, compare_wrapped, bits));
    CoherenceLoaded loaded;
    if (coherence_load(program, 1u, &loaded) == 0)
    {
        coherence_check(tally, 0, "the quotient and comparison program loads");
        free(program);
        free(atoms);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        atoms[lane] = coherence_input(coherence_random());
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
    unsigned int quotient_breaks = 0u;
    unsigned int compare_breaks = 0u;
    for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
        const DeviceRecordStep *const table = loaded.layout.step_table;
        quotient_breaks += (coherence_take(record, &table[program->outputs[0]])
                            != coherence_take(record, &table[program->outputs[1]])) ? 1u : 0u;
        compare_breaks += (coherence_take(record, &table[program->outputs[2]])
                           != coherence_take(record, &table[program->outputs[3]])) ? 1u : 0u;
    }
    scriptura_text(&tally->line, "  broken: the quotient by 3 disagrees on ");
    scriptura_decimal(&tally->line, quotient_breaks, 1u);
    scriptura_text(&tally->line, " and the comparison with 0 on ");
    scriptura_decimal(&tally->line, compare_breaks, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes, wrapped to 8 bits before against after\n");
    coherence_check(tally, host_ran && device_ran
                               && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                    "the quotient and comparison program's device records equal the host's word for word");
    coherence_check(tally, quotient_breaks != 0u, "a quotient does not commute with the wrap");
    coherence_check(tally, compare_breaks != 0u, "a comparison does not commute with the wrap");
    free(host_out);
    free(device_out);
    free(atoms);
    free(program);
    coherence_free(&loaded);
}

// c^-1 modulo 2^32 for an odd c, by Newton's x(2 - cx): an odd c is its own inverse to 3 bits, and each step doubles
// the bits, 6, 12, 24, 48
static unsigned int coherence_inverse(unsigned int odd)
{
    unsigned int inverse = odd;
    for (unsigned int round = 0u; round < 4u; round += 1u)
    {
        inverse *= 2u - (odd * inverse);
    }
    return inverse;
}

// An exact quotient by an odd c is multiplication by c^-1 in Z_2. For v = c . u, the exact quotient wrapped to w equals
// the product of v wrapped to w and c^-1 modulo 2^w, wrapped to w: the division reaches into Z_2 through its
// projections.
static void coherence_odd_divisors(CoherenceTally *tally)
{
    static const unsigned int divisors[3] = {3u, 7u, 12345u};
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(tally, 0, "the odd divisor lanes are held");
        free(atoms);
        free(program);
        return;
    }
    unsigned int loaded_all = 1u;
    unsigned int words_all = 1u;
    unsigned long long agreements = 0ull;
    unsigned long long comparisons = 0ull;
    for (unsigned int pick = 0u; pick < 3u; pick += 1u)
    {
        const unsigned int divisor = divisors[pick];
        const unsigned int inverse = coherence_inverse(divisor);
        memset(program, 0, sizeof(*program));
        const unsigned int factor = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        const unsigned int constant = coherence_emit(program, ENGINE_RECORD_CONSTANT, divisor, 0u);
        const unsigned int product = coherence_emit(program, ENGINE_RECORD_PRODUCT, factor, constant);
        const unsigned int quotient = coherence_emit(program, ENGINE_RECORD_EXACT_QUOTIENT, product, constant);
        for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
        {
            const unsigned int bits = s_coherence_widths[width];
            // c^-1 modulo 2^w, never negative, as a constant
            const unsigned int kept = (bits == 32u) ? inverse : (inverse & ((1u << bits) - 1u));
            coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, quotient, bits));
            const unsigned int projected = coherence_emit(program, ENGINE_RECORD_WRAP, product, bits);
            const unsigned int unit = coherence_emit(program, ENGINE_RECORD_CONSTANT, kept, 0u);
            const unsigned int times = coherence_emit(program, ENGINE_RECORD_PRODUCT, projected, unit);
            coherence_output(program, coherence_emit(program, ENGINE_RECORD_WRAP, times, bits));
        }
        CoherenceLoaded loaded;
        if (coherence_load(program, 1u, &loaded) == 0)
        {
            loaded_all = 0u;
            continue;
        }
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            atoms[lane] = coherence_input(coherence_random());
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
        words_all = words_all && host_ran && device_ran
                 && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const long long factor_value = coherence_signed_input(atoms[lane]);
            for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
            {
                const DeviceRecordStep *const table = loaded.layout.step_table;
                const long long divided = coherence_take(record, &table[program->outputs[2u * width]]);
                const long long multiplied = coherence_take(record, &table[program->outputs[(2u * width) + 1u]]);
                // the factor itself, wrapped: what both must be
                const long long expected = coherence_reduce((unsigned long long)factor_value, s_coherence_widths[width]);
                comparisons += 1ull;
                agreements += ((divided == expected) && (multiplied == expected)) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&tally->line, "  odd divisors: 3, 7 and 12345; ");
    scriptura_decimal(&tally->line, agreements, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, comparisons, 1u);
    scriptura_text(&tally->line, " lane-widths: the exact quotient wrapped equals the wrapped product by c^-1 mod 2^w\n");
    coherence_check(tally, loaded_all, "every odd divisor program loads");
    coherence_check(tally, words_all, "the odd divisor programs' device records equal the host's word for word");
    coherence_check(tally, (comparisons != 0ull) && (agreements == comparisons),
                    "an exact quotient by an odd c is the product by c^-1 in every projection");
    free(atoms);
    free(program);
}

#define COHERENCE_TEST_MODULI 4u

// the odd crystals' windows: 3^5, 3^10, 5^4 and 7^3
static const unsigned int s_coherence_moduli[COHERENCE_TEST_MODULI] = {243u, 59049u, 625u, 343u};

// the 2-adic window the odd crystals are joined to
#define COHERENCE_TEST_JOIN_BITS 8u

// a residue in [0, m)
static long long coherence_residue(long long value, long long modulus)
{
    const long long residue = value % modulus;
    return (residue < 0ll) ? (residue + modulus) : residue;
}

// the orthogonal crystals. A remainder by an odd prime power m = p^v is the projection onto Z / p^v, and a program of
// sums, differences and products commutes with it as the wrap does with 2^w: the exact run's remainder, the run
// reduced at every step and the host's own arithmetic modulo m agree on every lane. The 2-adic window and the p-adic
// one are independent (Z / 2^w p^v = Z / 2^w x Z / p^v), so the machine joins them: y = y_2 + 2^w ((y_p - y_2)
// 2^-w mod m) must equal the exact run modulo 2^w m. An xor is the 2-adic crystal's alone and must break modulo 3.
static void coherence_orthogonal(CoherenceTally *tally)
{
    const unsigned int lanes = COHERENCE_TEST_LANES;
    const long long join = 1ll << COHERENCE_TEST_JOIN_BITS;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * COHERENCE_TEST_INPUTS, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(tally, 0, "the orthogonal lanes are held");
        free(atoms);
        free(program);
        return;
    }
    unsigned int loaded_all = 1u;
    unsigned int words_all = 1u;
    unsigned long long agreements = 0ull;
    unsigned long long joined = 0ull;
    unsigned long long comparisons = 0ull;
    for (unsigned int drawn = 0u; drawn < COHERENCE_TEST_PROGRAMS; drawn += 1u)
    {
        CoherenceOperation operations[COHERENCE_TEST_OPERATIONS];
        coherence_draw(operations, 1);
        memset(program, 0, sizeof(*program));
        unsigned int value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
        for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
        {
            value[input] = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, input, 0u);
        }
        for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
        {
            value[COHERENCE_TEST_INPUTS + at] = coherence_emit(program, operations[at].operation,
                                                               value[operations[at].left], value[operations[at].right]);
        }
        const unsigned int exact = value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
        const unsigned int two_adic = coherence_emit(program, ENGINE_RECORD_WRAP, exact, COHERENCE_TEST_JOIN_BITS);
        const unsigned int scale = coherence_emit(program, ENGINE_RECORD_CONSTANT, (unsigned int)join, 0u);
        for (unsigned int pick = 0u; pick < COHERENCE_TEST_MODULI; pick += 1u)
        {
            const long long modulus = (long long)s_coherence_moduli[pick];
            // 2^-w modulo m, found by trial: m is odd, so it exists below m
            long long unit = 1ll;
            while (((unit * join) % modulus) != 1ll)
            {
                unit += 1ll;
            }
            const unsigned int window = coherence_emit(program, ENGINE_RECORD_CONSTANT, s_coherence_moduli[pick], 0u);
            const unsigned int projected = coherence_emit(program, ENGINE_RECORD_REMAINDER, exact, window);
            coherence_output(program, projected);
            unsigned int reduced[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
            for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
            {
                reduced[input] = coherence_emit(program, ENGINE_RECORD_REMAINDER, value[input], window);
            }
            for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
            {
                const unsigned int step = coherence_emit(program, operations[at].operation, reduced[operations[at].left],
                                                         reduced[operations[at].right]);
                reduced[COHERENCE_TEST_INPUTS + at] = coherence_emit(program, ENGINE_RECORD_REMAINDER, step, window);
            }
            coherence_output(program, reduced[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u]);
            // the join: y_2 + 2^w (((y_p - y_2) 2^-w) rem m), from the machine's two windows alone
            const unsigned int apart = coherence_emit(program, ENGINE_RECORD_DIFFERENCE, projected, two_adic);
            const unsigned int inverse = coherence_emit(program, ENGINE_RECORD_CONSTANT, (unsigned int)unit, 0u);
            const unsigned int lifted = coherence_emit(program, ENGINE_RECORD_PRODUCT, apart, inverse);
            const unsigned int digit = coherence_emit(program, ENGINE_RECORD_REMAINDER, lifted, window);
            const unsigned int placed = coherence_emit(program, ENGINE_RECORD_PRODUCT, digit, scale);
            coherence_output(program, coherence_emit(program, ENGINE_RECORD_SUM, two_adic, placed));
            // the exact run's remainder by 2^w m, what the join must equal modulo 2^w m
            const unsigned int whole = coherence_emit(program, ENGINE_RECORD_CONSTANT,
                                                      (unsigned int)(join * modulus), 0u);
            coherence_output(program, coherence_emit(program, ENGINE_RECORD_REMAINDER, exact, whole));
        }
        CoherenceLoaded loaded;
        if (coherence_load(program, COHERENCE_TEST_INPUTS, &loaded) == 0)
        {
            loaded_all = 0u;
            continue;
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
        words_all = words_all && host_ran && device_ran
                 && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const DeviceRecordStep *const table = loaded.layout.step_table;
            for (unsigned int pick = 0u; pick < COHERENCE_TEST_MODULI; pick += 1u)
            {
                const long long modulus = (long long)s_coherence_moduli[pick];
                // the third reckoning: the host's own arithmetic, reduced modulo m at every step
                long long host[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
                for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
                {
                    host[input] = coherence_residue(coherence_signed_input(atoms[lane * COHERENCE_TEST_INPUTS + input]),
                                                    modulus);
                }
                for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
                {
                    const long long left = host[operations[at].left];
                    const long long right = host[operations[at].right];
                    // each residue is below 59049, so a product stays far inside the word
                    const long long step = (operations[at].operation == ENGINE_RECORD_SUM) ? (left + right)
                                         : ((operations[at].operation == ENGINE_RECORD_DIFFERENCE) ? (left - right)
                                                                                                   : (left * right));
                    host[COHERENCE_TEST_INPUTS + at] = coherence_residue(step, modulus);
                }
                const long long expected = host[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
                const long long projected = coherence_take(record, &table[program->outputs[4u * pick]]);
                const long long stepped = coherence_take(record, &table[program->outputs[(4u * pick) + 1u]]);
                const long long rebuilt = coherence_take(record, &table[program->outputs[(4u * pick) + 2u]]);
                const long long whole = coherence_take(record, &table[program->outputs[(4u * pick) + 3u]]);
                comparisons += 1ull;
                agreements += ((coherence_residue(projected, modulus) == expected)
                               && (coherence_residue(stepped, modulus) == expected))
                            ? 1ull : 0ull;
                joined += (coherence_residue(rebuilt - whole, join * modulus) == 0ll) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    // the xor modulo 3: the xor of the residues against the residue of the xor
    memset(program, 0, sizeof(*program));
    const unsigned int left = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    const unsigned int right = coherence_emit(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    const unsigned int three = coherence_emit(program, ENGINE_RECORD_CONSTANT, 3u, 0u);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_REMAINDER,
                                             coherence_emit(program, ENGINE_RECORD_XOR, left, right), three));
    const unsigned int left_residue = coherence_emit(program, ENGINE_RECORD_REMAINDER, left, three);
    const unsigned int right_residue = coherence_emit(program, ENGINE_RECORD_REMAINDER, right, three);
    coherence_output(program, coherence_emit(program, ENGINE_RECORD_REMAINDER,
                                             coherence_emit(program, ENGINE_RECORD_XOR, left_residue, right_residue),
                                             three));
    unsigned int xor_breaks = 0u;
    CoherenceLoaded loaded;
    const int xor_loads = coherence_load(program, 2u, &loaded);
    if (xor_loads != 0)
    {
        for (unsigned int at = 0u; at < lanes * 2u; at += 1u)
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
        words_all = words_all && host_ran && device_ran
                 && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const long long whole = coherence_take(record, &loaded.layout.step_table[program->outputs[0]]);
            const long long parts = coherence_take(record, &loaded.layout.step_table[program->outputs[1]]);
            xor_breaks += (coherence_residue(whole, 3ll) != coherence_residue(parts, 3ll)) ? 1u : 0u;
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&tally->line, "  orthogonal crystals: 3^5, 3^10, 5^4 and 7^3 over ");
    scriptura_decimal(&tally->line, COHERENCE_TEST_PROGRAMS, 1u);
    scriptura_text(&tally->line, " ring programs; ");
    scriptura_decimal(&tally->line, agreements, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, comparisons, 1u);
    scriptura_text(&tally->line, " lane-moduli agree three ways, ");
    scriptura_decimal(&tally->line, joined, 1u);
    scriptura_text(&tally->line, " join with the 8-bit window exactly; the xor breaks modulo 3 on ");
    scriptura_decimal(&tally->line, xor_breaks, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes\n");
    coherence_check(tally, loaded_all && (xor_loads != 0), "every orthogonal program loads");
    coherence_check(tally, words_all, "the orthogonal programs' device records equal the host's word for word");
    coherence_check(tally, (comparisons != 0ull) && (agreements == comparisons),
                    "a ring program commutes with the projection onto Z / p^v for p = 3, 5 and 7");
    coherence_check(tally, joined == comparisons,
                    "the machine joins the 2-adic and p-adic windows into the exact run modulo 2^w p^v");
    coherence_check(tally, xor_breaks != 0u, "an xor is the 2-adic crystal's alone: it breaks modulo 3");
    free(atoms);
    free(program);
}

int main(void)
{
    CoherenceTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = COHERENCE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)COHERENCE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    coherence_programs(&tally);
    coherence_broken(&tally);
    coherence_odd_divisors(&tally);
    coherence_orthogonal(&tally);
    scriptura_text(&tally.line, "  record coherence test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
