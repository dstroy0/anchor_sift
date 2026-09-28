// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_table_test_run.cu: programs, loading and running on host and device
#include "record_table_test_internal.h"

static unsigned long long s_table_state = 0xD1CE5EEDF00DCAFEull;

unsigned int table_random(void)
{
    s_table_state ^= s_table_state << 13u;
    s_table_state ^= s_table_state >> 7u;
    s_table_state ^= s_table_state << 17u;
    return (unsigned int)(s_table_state & 0xFFFFull);
}

void table_check(TableResults *results, int passed, const char *what)
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

void table_program_init(TableProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->fields = 1u;
    program->field_bits[0] = 16u;
    program->field_offset[0] = 0u;
    program->members = 1u;
    program->in_limbs[0] = 1u;
}

void table_step(TableProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

// Lay a program out and load it to the device. Returns the layout's file_limbs, or -1 errored.
static long table_load(TableProgram *program, EngineRecordKey *key, EngineRecordLayout *layout, CycleRecord **record,
                       EngineError *error)
{
    memset(error, 0, sizeof(*error));
    const KeymathRecordRequest encode_request = {program->steps,
                                                 program->count,
                                                 program->field_bits,
                                                 program->fields,
                                                 program->members,
                                                 program->outputs,
                                                 program->output_count,
                                                 program->tables,
                                                 program->table_count,
                                                 key,
                                                 error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return -1L;
    }
    const KeyScheduleRecordRequest layout_request = {
        key, program->field_offset, program->fields, program->in_limbs, program->reuse, layout, error};
    const long file_limbs = key_schedule_record_layout(&layout_request);
    if (file_limbs == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(key);
        return -1L;
    }
    if (cycle_record_load(layout, record, error) == CYCLE_ERROR)
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
int table_run_host(TableProgram *program, const unsigned int *atoms, unsigned long long count, unsigned int *out,
                   unsigned int *out_limbs)
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
    const CycleRecordHostRequest request = {&layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count, out,
                                            &error};
    const int ok = cycle_record_run_host(&request) != CYCLE_ERROR;
    table_free(&key, &layout, record);
    return ok;
}

// Run one program on the device over `count` single-word atoms, into `out` (count * out_limbs words).
int table_run_device(TableProgram *program, const unsigned int *atoms, unsigned long long count, unsigned int *out,
                     unsigned int *out_limbs)
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
    int ok =
        cudaMalloc((void **)&device_atoms, (size_t)count * sizeof(unsigned int)) == cudaSuccess &&
        cudaMalloc((void **)&device_out, (size_t)count * (*out_limbs) * sizeof(unsigned int)) == cudaSuccess &&
        cudaMemcpy(device_atoms, atoms, (size_t)count * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess;
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {
            record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count, device_out, &error};
        ok = cycle_record_run(&run) != CYCLE_ERROR;
        ok = ok && cudaMemcpy(out, device_out, (size_t)count * (*out_limbs) * sizeof(unsigned int),
                              cudaMemcpyDeviceToHost) == cudaSuccess;
    }
    cudaFree(device_atoms);
    cudaFree(device_out);
    table_free(&key, &layout, record);
    return ok;
}

// Fill a table by running an ordinary-ops program over the whole 16-bit alphabet: table[x] is the low
// `value_bits` of the ops' output at input x. This makes the ops the table's oracle.
int table_fill_from_ops(TableProgram *oracle, unsigned int value_bits, unsigned int *values)
{
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const out =
        (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
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
    const int ok = table_run_host(oracle, atoms, TABLE_TEST_ALPHABET, out, &out_limbs);
    const unsigned int mask = (value_bits >= 32u) ? 0xFFFFFFFFu : ((1u << value_bits) - 1u);
    for (unsigned int value = 0u; (ok != 0) && (value < TABLE_TEST_ALPHABET); value += 1u)
    {
        values[value] = out[value * out_limbs] & mask;
    }
    free(atoms);
    free(out);
    return ok;
}

// One oracle-versus-table case: build the ops oracle, fill a table from it, run both a table program and
// the oracle over random inputs, and require the four outputs (table device, table host, oracle device,
// oracle host) to agree word for word.
void table_case(TableResults *results, const char *name, TableProgram *oracle, unsigned int value_bits)
{
    unsigned int *const values = (unsigned int *)malloc((size_t)TABLE_TEST_ALPHABET * sizeof(unsigned int));
    unsigned int *const atoms = (unsigned int *)malloc((size_t)TABLE_TEST_LANES * sizeof(unsigned int));
    unsigned int *const oracle_device =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    unsigned int *const oracle_host =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    unsigned int *const table_device =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    unsigned int *const table_host =
        (unsigned int *)malloc((size_t)TABLE_TEST_LANES * ANCHOR_RECORD_OUT_WORDS * sizeof(unsigned int));
    int ok = (values != NULL) && (atoms != NULL) && (oracle_device != NULL) && (oracle_host != NULL) &&
             (table_device != NULL) && (table_host != NULL);
    ok = ok && table_fill_from_ops(oracle, value_bits, values);

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
    ok = ok && table_run_device(oracle, atoms, TABLE_TEST_LANES, oracle_device, &a);
    ok = ok && table_run_host(oracle, atoms, TABLE_TEST_LANES, oracle_host, &b);
    ok = ok && table_run_device(&table, atoms, TABLE_TEST_LANES, table_device, &c);
    ok = ok && table_run_host(&table, atoms, TABLE_TEST_LANES, table_host, &d);
    table_check(results, ok && (a == b) && (b == c) && (c == d), name);
    if (ok != 0)
    {
        const size_t bytes = (size_t)TABLE_TEST_LANES * a * sizeof(unsigned int);
        table_check(results, memcmp(oracle_device, oracle_host, bytes) == 0, name);
        table_check(results, memcmp(table_device, oracle_device, bytes) == 0, name);
        table_check(results, memcmp(table_host, oracle_device, bytes) == 0, name);
        scriptura_text(&results->line, "  ");
        scriptura_text(&results->line, name);
        scriptura_text(&results->line, ": the table reproduces the ops over ");
        scriptura_decimal(&results->line, TABLE_TEST_LANES, 1u);
        scriptura_text(&results->line, " lanes, device and host\n");
    }
    free(values);
    free(atoms);
    free(oracle_device);
    free(oracle_host);
    free(table_device);
    free(table_host);
}
