// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The lookup table (ENGINE_RECORD_TABLE) proved against the ordinary record operations. Every table is
// filled by running an ordinary-ops program over its whole alphabet, so the ops are the oracle: a table
// step must then reproduce those ops lane for lane, on the device and on the host, and a chain of table
// steps must compose the way reading one table through another does. The register reuse the scheduler
// grew for long programs is proved to leave the output unchanged while shrinking the file.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define TABLE_TEST_LINE 8192ull

#define TABLE_TEST_ALPHABET 65536u

#define TABLE_TEST_LANES 4096u

#define TABLE_TEST_STEPS 64u

// The widest output record any program here writes, in 32-bit words.
#define ANCHOR_RECORD_OUT_WORDS 4u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} TableTally;

typedef struct
{
    EngineRecordStep steps[TABLE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[4];
    unsigned int field_offset[4];
    unsigned int fields;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[4];
    unsigned int output_count;
    EngineRecordTable tables[4];
    unsigned int table_count;
    int reuse;
} TableProgram;

static unsigned long long s_table_state = 0xD1CE5EEDF00DCAFEull;

static unsigned int table_random(void)
{
    s_table_state ^= s_table_state << 13u;
    s_table_state ^= s_table_state >> 7u;
    s_table_state ^= s_table_state << 17u;
    return (unsigned int)(s_table_state & 0xFFFFull);
}

static void table_check(TableTally *tally, int held, const char *what)
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

static void table_program_init(TableProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->fields = 1u;
    program->field_bits[0] = 16u;
    program->field_offset[0] = 0u;
    program->members = 1u;
    program->in_limbs[0] = 1u;
}

static void table_step(TableProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

// Lay a program out and load it to the device. Returns the layout's file_limbs, or -1 refused.
static long table_load(TableProgram *program, EngineRecordKey *key, EngineRecordLayout *layout, CycleRecord **record,
                       EngineError *error)
{
    memset(error, 0, sizeof(*error));
    const KeymathRecordRequest imprint = {program->steps, program->count, program->field_bits, program->fields,
                                          program->members, program->outputs, program->output_count, program->tables,
                                          program->table_count, key, error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return -1L;
    }
    const KeyScheduleRecordRequest lay = {key, program->field_offset, program->fields, program->in_limbs,
                                          program->reuse, layout, error};
    const long file_limbs = key_schedule_record_lay(&lay);
    if (file_limbs == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(key);
        return -1L;
    }
    if (cycle_record_load(layout, record, error) == CYCLE_REFUSED)
    {
        keymath_record_release(key);
        key_schedule_record_release(layout);
        return -1L;
    }
    return file_limbs;
}

static void table_free(EngineRecordKey *key, EngineRecordLayout *layout, CycleRecord *record)
{
    cycle_record_release(record);
    key_schedule_record_release(layout);
    keymath_record_release(key);
}

// Run one program on the host over `count` single-word atoms, into `out` (count * out_limbs words).
static int table_run_host(TableProgram *program, const unsigned int *atoms, unsigned long long count,
                          unsigned int *out, unsigned int *out_limbs)
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record = NULL;
    EngineError error;
    if (table_load(program, &key, &layout, &record, &error) < 0L)
    {
        return 0;
    }
    *out_limbs = layout.out_limbs;
    const CycleRecordHostRequest request = {&layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count, out};
    const int good = cycle_record_run_host(&request) != CYCLE_REFUSED;
    table_free(&key, &layout, record);
    return good;
}

// Run one program on the device over `count` single-word atoms, into `out` (count * out_limbs words).
static int table_run_device(TableProgram *program, const unsigned int *atoms, unsigned long long count,
                            unsigned int *out, unsigned int *out_limbs)
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record = NULL;
    EngineError error;
    if (table_load(program, &key, &layout, &record, &error) < 0L)
    {
        return 0;
    }
    *out_limbs = cycle_record_out_limbs(record);
    unsigned int *device_atoms = NULL;
    unsigned int *device_out = NULL;
    int good = cudaMalloc((void **)&device_atoms, (size_t)count * sizeof(unsigned int)) == cudaSuccess
            && cudaMalloc((void **)&device_out, (size_t)count * (*out_limbs) * sizeof(unsigned int)) == cudaSuccess
            && cudaMemcpy(device_atoms, atoms, (size_t)count * sizeof(unsigned int), cudaMemcpyHostToDevice)
                   == cudaSuccess;
    if (good != 0)
    {
        const CycleRecordRunRequest run = {record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                           device_out, &error};
        good = cycle_record_run(&run) != CYCLE_REFUSED;
        good = good
            && cudaMemcpy(out, device_out, (size_t)count * (*out_limbs) * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                   == cudaSuccess;
    }
    cudaFree(device_atoms);
    cudaFree(device_out);
    table_free(&key, &layout, record);
    return good;
}

// Fill a table by running an ordinary-ops program over the whole 16-bit alphabet: table[x] is the low
// `value_bits` of the ops' output at input x. This makes the ops the table's oracle.
static int table_fill_from_ops(TableProgram *oracle, unsigned int value_bits, unsigned int *values)
{
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const out = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * ANCHOR_RECORD_OUT_WORDS
                                                     * sizeof(unsigned int));
    if ((atoms == NULL) || (out == NULL))
    {
        free(atoms);
        free(out);
        return 0;
    }
    for (unsigned int value = 0u; value < TABLE_TEST_ALPHABET; value += 1u)
    {
        atoms[value] = value;
    }
    unsigned int out_limbs = 0u;
    const int good = table_run_host(oracle, atoms, TABLE_TEST_ALPHABET, out, &out_limbs);
    const unsigned int mask = (value_bits >= 32u) ? 0xFFFFFFFFu : ((1u << value_bits) - 1u);
    for (unsigned int value = 0u; (good != 0) && (value < TABLE_TEST_ALPHABET); value += 1u)
    {
        values[value] = out[value * out_limbs] & mask;
    }
    free(atoms);
    free(out);
    return good;
}

// One oracle-versus-table case: build the ops oracle, fill a table from it, run both a table program and
// the oracle over random inputs, and require the four outputs (table device, table host, oracle device,
// oracle host) to agree word for word.
static void table_case(TableTally *tally, const char *name, TableProgram *oracle, unsigned int value_bits)
{
    unsigned int *const values = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const oracle_device = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                              * sizeof(unsigned int));
    unsigned int *const oracle_host = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                            * sizeof(unsigned int));
    unsigned int *const table_device = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                             * sizeof(unsigned int));
    unsigned int *const table_host = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                           * sizeof(unsigned int));
    int good = (values != NULL) && (atoms != NULL) && (oracle_device != NULL) && (oracle_host != NULL)
            && (table_device != NULL) && (table_host != NULL);
    good = good && table_fill_from_ops(oracle, value_bits, values);

    TableProgram table;
    table_program_init(&table);
    table_step(&table, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&table, ENGINE_RECORD_TABLE, 0u, 0u);
    table.outputs[0] = 1u;
    table.output_count = 1u;
    table.tables[0].index_bits = 16u;
    table.tables[0].out_bits = value_bits;
    table.tables[0].values = values;
    table.table_count = 1u;

    for (unsigned int lane = 0u; lane < TABLE_TEST_LANES; lane += 1u)
    {
        atoms[lane] = table_random();
    }
    unsigned int a = 0u;
    unsigned int b = 0u;
    unsigned int c = 0u;
    unsigned int d = 0u;
    good = good && table_run_device(oracle, atoms, TABLE_TEST_LANES, oracle_device, &a);
    good = good && table_run_host(oracle, atoms, TABLE_TEST_LANES, oracle_host, &b);
    good = good && table_run_device(&table, atoms, TABLE_TEST_LANES, table_device, &c);
    good = good && table_run_host(&table, atoms, TABLE_TEST_LANES, table_host, &d);
    table_check(tally, good && (a == b) && (b == c) && (c == d), name);
    if (good != 0)
    {
        const size_t bytes = (size_t)TABLE_TEST_LANES * a * sizeof(unsigned int);
        table_check(tally, memcmp(oracle_device, oracle_host, bytes) == 0, name);
        table_check(tally, memcmp(table_device, oracle_device, bytes) == 0, name);
        table_check(tally, memcmp(table_host, oracle_device, bytes) == 0, name);
        scriptura_text(&tally->line, "  ");
        scriptura_text(&tally->line, name);
        scriptura_text(&tally->line, ": the table reproduces the ops over ");
        scriptura_decimal(&tally->line, TABLE_TEST_LANES, 1u);
        scriptura_text(&tally->line, " lanes, device and host\n");
    }
    free(values);
    free(atoms);
    free(oracle_device);
    free(oracle_host);
    free(table_device);
    free(table_host);
}

static long table_file_limbs(TableProgram *program)
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const KeymathRecordRequest imprint = {program->steps, program->count, program->field_bits, program->fields,
                                          program->members, program->outputs, program->output_count, program->tables,
                                          program->table_count, &key, &error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return -1L;
    }
    const KeyScheduleRecordRequest lay = {&key, program->field_offset, program->fields, program->in_limbs,
                                          program->reuse, &layout, &error};
    const long file_limbs = key_schedule_record_lay(&lay);
    keymath_record_release(&key);
    if (file_limbs != KEY_SCHEDULE_REFUSED)
    {
        key_schedule_record_release(&layout);
    }
    return file_limbs;
}

// Build the ops oracles, then run a two-table program (a table read through a table) against an ops
// oracle for the same composed function; a single table composed on the host must match it too, and the
// reversed order must not, since a chain collapses onto the floor in order.
static void table_compose(TableTally *tally)
{
    unsigned int *const values_f = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const values_g = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const values_h = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const two = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const one = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const oracle = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const reversed = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    int good = (values_f != NULL) && (values_g != NULL) && (values_h != NULL) && (atoms != NULL) && (two != NULL)
            && (one != NULL) && (oracle != NULL) && (reversed != NULL);

    // f(x) = 65535 - x
    TableProgram oracle_f;
    table_program_init(&oracle_f);
    table_step(&oracle_f, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&oracle_f, ENGINE_RECORD_CONSTANT, 65535u, 0u);
    table_step(&oracle_f, ENGINE_RECORD_DIFFERENCE, 1u, 0u);
    oracle_f.outputs[0] = 2u;
    oracle_f.output_count = 1u;
    good = good && table_fill_from_ops(&oracle_f, 16u, values_f);

    // g(y) = |y - 30000|
    TableProgram oracle_g;
    table_program_init(&oracle_g);
    table_step(&oracle_g, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&oracle_g, ENGINE_RECORD_CONSTANT, 30000u, 0u);
    table_step(&oracle_g, ENGINE_RECORD_DIFFERENCE, 0u, 1u);
    table_step(&oracle_g, ENGINE_RECORD_ABSOLUTE, 2u, 0u);
    oracle_g.outputs[0] = 3u;
    oracle_g.output_count = 1u;
    good = good && table_fill_from_ops(&oracle_g, 16u, values_g);

    // h(x) = g(f(x)) = |(65535 - x) - 30000| = |35535 - x|, as ordinary ops
    TableProgram oracle_h;
    table_program_init(&oracle_h);
    table_step(&oracle_h, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&oracle_h, ENGINE_RECORD_CONSTANT, 65535u, 0u);
    table_step(&oracle_h, ENGINE_RECORD_DIFFERENCE, 1u, 0u);
    table_step(&oracle_h, ENGINE_RECORD_CONSTANT, 30000u, 0u);
    table_step(&oracle_h, ENGINE_RECORD_DIFFERENCE, 2u, 3u);
    table_step(&oracle_h, ENGINE_RECORD_ABSOLUTE, 4u, 0u);
    oracle_h.outputs[0] = 5u;
    oracle_h.output_count = 1u;

    // the composed table, g read through f on the host
    for (unsigned int value = 0u; (good != 0) && (value < TABLE_TEST_ALPHABET); value += 1u)
    {
        values_h[value] = values_g[values_f[value]];
    }

    TableProgram two_step;
    table_program_init(&two_step);
    table_step(&two_step, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&two_step, ENGINE_RECORD_TABLE, 0u, 0u);
    table_step(&two_step, ENGINE_RECORD_TABLE, 1u, 1u);
    two_step.outputs[0] = 2u;
    two_step.output_count = 1u;
    two_step.tables[0].index_bits = 16u;
    two_step.tables[0].out_bits = 16u;
    two_step.tables[0].values = values_f;
    two_step.tables[1].index_bits = 16u;
    two_step.tables[1].out_bits = 16u;
    two_step.tables[1].values = values_g;
    two_step.table_count = 2u;

    TableProgram reverse_step = two_step;
    reverse_step.tables[0].values = values_g;
    reverse_step.tables[1].values = values_f;

    TableProgram single;
    table_program_init(&single);
    table_step(&single, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&single, ENGINE_RECORD_TABLE, 0u, 0u);
    single.outputs[0] = 1u;
    single.output_count = 1u;
    single.tables[0].index_bits = 16u;
    single.tables[0].out_bits = 16u;
    single.tables[0].values = values_h;
    single.table_count = 1u;

    for (unsigned int lane = 0u; lane < TABLE_TEST_LANES; lane += 1u)
    {
        atoms[lane] = table_random();
    }
    unsigned int limbs = 0u;
    good = good && table_run_device(&two_step, atoms, TABLE_TEST_LANES, two, &limbs);
    good = good && table_run_host(&oracle_h, atoms, TABLE_TEST_LANES, oracle, &limbs);
    good = good && table_run_device(&single, atoms, TABLE_TEST_LANES, one, &limbs);
    good = good && table_run_host(&reverse_step, atoms, TABLE_TEST_LANES, reversed, &limbs);
    const size_t bytes = (size_t)TABLE_TEST_LANES * sizeof(unsigned int);
    table_check(tally, good && (memcmp(two, oracle, bytes) == 0), "a table read through a table equals the ops");
    table_check(tally, good && (memcmp(one, oracle, bytes) == 0), "the host-composed single table equals the two");
    int order_matters = 0;
    for (unsigned int lane = 0u; good && (lane < TABLE_TEST_LANES); lane += 1u)
    {
        order_matters = order_matters || (reversed[lane] != two[lane]);
    }
    table_check(tally, good && (order_matters != 0), "the reversed composition differs: the chain keeps its order");
    if (good != 0)
    {
        scriptura_text(&tally->line, "  composition: g(f(x)) as two tables, one composed table and the ops all agree\n");
    }
    free(values_f);
    free(values_g);
    free(values_h);
    free(atoms);
    free(two);
    free(one);
    free(oracle);
    free(reversed);
}

// A long additive chain, run with the register reuse on and off: the same output, from a smaller file.
static void table_reuse(TableTally *tally)
{
    TableProgram chain;
    table_program_init(&chain);
    table_step(&chain, ENGINE_RECORD_FIELD, 0u, 0u);
    unsigned int last = 0u;
    for (unsigned int stage = 0u; stage < 10u; stage += 1u)
    {
        table_step(&chain, ENGINE_RECORD_CONSTANT, (stage * 37u) + 1u, 0u);
        table_step(&chain, ENGINE_RECORD_SUM, last, chain.count - 1u);
        last = chain.count - 1u;
    }
    chain.outputs[0] = last;
    chain.output_count = 1u;

    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const kept = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                     * sizeof(unsigned int));
    unsigned int *const reused = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS
                                                       * sizeof(unsigned int));
    int good = (atoms != NULL) && (kept != NULL) && (reused != NULL);
    for (unsigned int lane = 0u; lane < TABLE_TEST_LANES; lane += 1u)
    {
        atoms[lane] = table_random();
    }
    chain.reuse = 0;
    const long file_kept = table_file_limbs(&chain);
    unsigned int a = 0u;
    good = good && table_run_device(&chain, atoms, TABLE_TEST_LANES, kept, &a);
    chain.reuse = 1;
    const long file_reused = table_file_limbs(&chain);
    unsigned int b = 0u;
    good = good && table_run_device(&chain, atoms, TABLE_TEST_LANES, reused, &b);
    table_check(tally, good && (a == b) && (memcmp(kept, reused, (size_t)TABLE_TEST_LANES * a * sizeof(unsigned int)) == 0),
                "register reuse leaves the output unchanged");
    table_check(tally, (file_kept > 0L) && (file_reused > 0L) && (file_reused < file_kept),
                "register reuse shrinks the file");
    if (good != 0)
    {
        scriptura_text(&tally->line, "  reuse: a ");
        scriptura_decimal(&tally->line, chain.count, 1u);
        scriptura_text(&tally->line, "-step chain fits ");
        scriptura_decimal(&tally->line, (unsigned long long)file_reused, 1u);
        scriptura_text(&tally->line, " limbs reused against ");
        scriptura_decimal(&tally->line, (unsigned long long)file_kept, 1u);
        scriptura_text(&tally->line, " kept\n");
    }
    free(atoms);
    free(kept);
    free(reused);
}

static void table_refusals(TableTally *tally)
{
    unsigned int *const values = (unsigned int *)calloc(TABLE_TEST_ALPHABET, sizeof(unsigned int));
    // an index wider than the source register's bits
    TableProgram wide;
    table_program_init(&wide);
    table_step(&wide, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&wide, ENGINE_RECORD_TABLE, 0u, 0u);
    wide.outputs[0] = 1u;
    wide.output_count = 1u;
    wide.tables[0].index_bits = 17u;
    wide.tables[0].out_bits = 16u;
    wide.tables[0].values = values;
    wide.table_count = 1u;
    table_check(tally, table_file_limbs(&wide) < 0L, "an index wider than its source is refused");

    // a table index with no table behind it
    TableProgram missing;
    table_program_init(&missing);
    table_step(&missing, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&missing, ENGINE_RECORD_TABLE, 0u, 3u);
    missing.outputs[0] = 1u;
    missing.output_count = 1u;
    missing.tables[0].index_bits = 16u;
    missing.tables[0].out_bits = 16u;
    missing.tables[0].values = values;
    missing.table_count = 1u;
    table_check(tally, table_file_limbs(&missing) < 0L, "a table index with no table is refused");
    free(values);
}

int main(void)
{
    TableTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = TABLE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)TABLE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }

    // the square, the whole 32-bit product through the table
    TableProgram square;
    table_program_init(&square);
    table_step(&square, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&square, ENGINE_RECORD_PRODUCT, 0u, 0u);
    square.outputs[0] = 1u;
    square.output_count = 1u;
    table_case(&tally, "x squared", &square, 32u);

    // an absolute difference plus a constant, exercising constant, difference, absolute and sum
    TableProgram deviate;
    table_program_init(&deviate);
    table_step(&deviate, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&deviate, ENGINE_RECORD_CONSTANT, 30000u, 0u);
    table_step(&deviate, ENGINE_RECORD_DIFFERENCE, 0u, 1u);
    table_step(&deviate, ENGINE_RECORD_ABSOLUTE, 2u, 0u);
    table_step(&deviate, ENGINE_RECORD_CONSTANT, 100u, 0u);
    table_step(&deviate, ENGINE_RECORD_SUM, 3u, 4u);
    deviate.outputs[0] = 5u;
    deviate.output_count = 1u;
    table_case(&tally, "the absolute deviation plus 100", &deviate, 18u);

    table_compose(&tally);
    table_reuse(&tally);
    table_refusals(&tally);

    scriptura_text(&tally.line, "  record table test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}

