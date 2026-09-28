// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_table_test_compose.cu: file limbs, composition, reuse, errors and main
#include "record_table_test_internal.h"

static long table_file_limbs(TableProgram *program)
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const KeymathRecordRequest encode_request = {program->steps,
                                                 program->count,
                                                 program->field_bits,
                                                 program->fields,
                                                 program->members,
                                                 program->outputs,
                                                 program->output_count,
                                                 program->tables,
                                                 program->table_count,
                                                 &key,
                                                 &error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return -1L;
    }
    const KeyScheduleRecordRequest layout_request = {
        &key, program->field_offset, program->fields, program->in_limbs, program->reuse, &layout, &error};
    const long file_limbs = key_schedule_record_layout(&layout_request);
    keymath_record_release(&key);
    if (file_limbs != KEY_SCHEDULE_ERROR)
    {
        key_schedule_record_release(&layout);
    }
    return file_limbs;
}

// Build the ops oracles, then run a two-table program (a table read through a table) against an ops
// oracle for the same composed function; a single table composed on the host must match it too, and the
// reversed order must not, since a chain collapses onto the floor in order.
static void table_compose(TableResults *results)
{
    unsigned int *const values_f = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const values_g = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const values_h = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const two = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const one = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const oracle = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const reversed = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    int ok = (values_f != NULL) && (values_g != NULL) && (values_h != NULL) && (atoms != NULL) && (two != NULL) &&
             (one != NULL) && (oracle != NULL) && (reversed != NULL);

    // f(x) = 65535 - x
    TableProgram oracle_f;
    table_program_init(&oracle_f);
    table_step(&oracle_f, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&oracle_f, ENGINE_RECORD_CONSTANT, 65535u, 0u);
    table_step(&oracle_f, ENGINE_RECORD_DIFFERENCE, 1u, 0u);
    oracle_f.outputs[0] = 2u;
    oracle_f.output_count = 1u;
    ok = ok && table_fill_from_ops(&oracle_f, 16u, values_f);

    // g(y) = |y - 30000|
    TableProgram oracle_g;
    table_program_init(&oracle_g);
    table_step(&oracle_g, ENGINE_RECORD_FIELD, 0u, 0u);
    table_step(&oracle_g, ENGINE_RECORD_CONSTANT, 30000u, 0u);
    table_step(&oracle_g, ENGINE_RECORD_DIFFERENCE, 0u, 1u);
    table_step(&oracle_g, ENGINE_RECORD_ABSOLUTE, 2u, 0u);
    oracle_g.outputs[0] = 3u;
    oracle_g.output_count = 1u;
    ok = ok && table_fill_from_ops(&oracle_g, 16u, values_g);

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
    for (unsigned int value = 0u; (ok != 0) && (value < TABLE_TEST_ALPHABET); value += 1u)
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
    ok = ok && table_run_device(&two_step, atoms, TABLE_TEST_LANES, two, &limbs);
    ok = ok && table_run_host(&oracle_h, atoms, TABLE_TEST_LANES, oracle, &limbs);
    ok = ok && table_run_device(&single, atoms, TABLE_TEST_LANES, one, &limbs);
    ok = ok && table_run_host(&reverse_step, atoms, TABLE_TEST_LANES, reversed, &limbs);
    const size_t bytes = (size_t)TABLE_TEST_LANES * sizeof(unsigned int);
    table_check(results, ok && (memcmp(two, oracle, bytes) == 0), "a table read through a table equals the ops");
    table_check(results, ok && (memcmp(one, oracle, bytes) == 0), "the host-composed single table equals the two");
    int order_matters = 0;
    for (unsigned int lane = 0u; ok && (lane < TABLE_TEST_LANES); lane += 1u)
    {
        order_matters = order_matters || (reversed[lane] != two[lane]);
    }
    table_check(results, ok && (order_matters != 0), "the reversed composition differs: the chain keeps its order");
    if (ok != 0)
    {
        scriptura_text(&results->line,
                       "  composition: g(f(x)) as two tables, one composed table and the ops all agree\n");
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
static void table_reuse(TableResults *results)
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
    unsigned int *const kept =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    unsigned int *const reused =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    int ok = (atoms != NULL) && (kept != NULL) && (reused != NULL);
    for (unsigned int lane = 0u; lane < TABLE_TEST_LANES; lane += 1u)
    {
        atoms[lane] = table_random();
    }
    chain.reuse = 0;
    const long file_kept = table_file_limbs(&chain);
    unsigned int a = 0u;
    ok = ok && table_run_device(&chain, atoms, TABLE_TEST_LANES, kept, &a);
    chain.reuse = 1;
    const long file_reused = table_file_limbs(&chain);
    unsigned int b = 0u;
    ok = ok && table_run_device(&chain, atoms, TABLE_TEST_LANES, reused, &b);
    table_check(results,
                ok && (a == b) && (memcmp(kept, reused, (size_t)TABLE_TEST_LANES * a * sizeof(unsigned int)) == 0),
                "register reuse leaves the output unchanged");
    table_check(results, (file_kept > 0L) && (file_reused > 0L) && (file_reused < file_kept),
                "register reuse shrinks the file");
    if (ok != 0)
    {
        scriptura_text(&results->line, "  reuse: a ");
        scriptura_decimal(&results->line, chain.count, 1u);
        scriptura_text(&results->line, "-step chain fits ");
        scriptura_decimal(&results->line, (unsigned long long)file_reused, 1u);
        scriptura_text(&results->line, " limbs reused against ");
        scriptura_decimal(&results->line, (unsigned long long)file_kept, 1u);
        scriptura_text(&results->line, " kept\n");
    }
    free(atoms);
    free(kept);
    free(reused);
}

static void table_errors(TableResults *results)
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
    table_check(results, table_file_limbs(&wide) < 0L, "an index wider than its source errors");

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
    table_check(results, table_file_limbs(&missing) < 0L, "a table index with no table errors");
    free(values);
}

int main(int count, char **arguments)
{
    TableResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = TABLE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)TABLE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_table_test", count, arguments, TABLE_TEST_DECLARED);
    if (admitted != 0)
    {
        // the square, the whole 32-bit product through the table
        TableProgram square;
        table_program_init(&square);
        table_step(&square, ENGINE_RECORD_FIELD, 0u, 0u);
        table_step(&square, ENGINE_RECORD_PRODUCT, 0u, 0u);
        square.outputs[0] = 1u;
        square.output_count = 1u;
        table_case(&results, "x squared", &square, 32u);

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
        table_case(&results, "the absolute deviation plus 100", &deviate, 18u);

        table_compose(&results);
        table_reuse(&results);
        table_errors(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    table_check(&results, (admitted != 0) && (job.failures == 0ull),
                "tessera: the device's daemon admits the test's job and it releases");

    scriptura_text(&results.line, "  record table test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
