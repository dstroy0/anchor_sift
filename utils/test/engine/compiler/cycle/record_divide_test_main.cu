// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_divide_test_main.cu: wide division, constants and main
#include "record_divide_test_internal.h"

// the 256-limb file: 2048-bit numerators over 1024-bit divisors, and a 1024-bit factor multiplied on and divided
// back out
static void divide_wide(DivideResults *results)
{
    DivideProgram program;
    memset(&program, 0, sizeof(program));
    program.fields = 2u;
    program.field_bits[0] = 2048u;
    program.field_bits[1] = 1024u;
    program.field_offset[1] = 2048u;
    program.in_limbs[0] = 96u;
    divide_step(&program, ENGINE_RECORD_FIELD, 0u, 0u);
    divide_step(&program, ENGINE_RECORD_FIELD, 1u, 0u);
    divide_step(&program, ENGINE_RECORD_QUOTIENT, 0u, 1u);
    divide_step(&program, ENGINE_RECORD_REMAINDER, 0u, 1u);
    divide_step(&program, ENGINE_RECORD_GCD, 0u, 1u);
    program.outputs[0] = 2u;
    program.outputs[1] = 3u;
    program.outputs[2] = 4u;
    program.output_count = 3u;

    DivideProgram exact;
    memset(&exact, 0, sizeof(exact));
    exact.fields = 2u;
    exact.field_bits[0] = 1024u;
    exact.field_bits[1] = 1024u;
    exact.field_offset[1] = 1024u;
    exact.in_limbs[0] = 64u;
    divide_step(&exact, ENGINE_RECORD_FIELD, 0u, 0u);
    divide_step(&exact, ENGINE_RECORD_FIELD, 1u, 0u);
    divide_step(&exact, ENGINE_RECORD_PRODUCT, 0u, 1u);
    divide_step(&exact, ENGINE_RECORD_EXACT_QUOTIENT, 2u, 1u);
    exact.outputs[0] = 3u;
    exact.output_count = 1u;

    const unsigned int lanes = DIVIDE_TEST_WIDE_LANES;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * 96u, sizeof(unsigned int));
    AnchorExactInteger *const operand = (AnchorExactInteger *)malloc((size_t)lanes * 2u * sizeof(AnchorExactInteger));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * 256u, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * 256u, sizeof(unsigned int));
    DivideLoaded loaded;
    if ((atoms == NULL) || (operand == NULL) || (host_out == NULL) || (device_out == NULL) ||
        (divide_load(&program, &loaded) == 0))
    {
        divide_check(results, 0, "the wide division program loads");
        free(atoms);
        free(operand);
        free(host_out);
        free(device_out);
        return;
    }
    divide_check(results, loaded.layout.file_limbs > 64u, "the wide division program takes the 256-limb file");
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        AnchorExactInteger *const numerator = &operand[2u * lane];
        AnchorExactInteger *const divisor = &operand[(2u * lane) + 1u];
        const unsigned int pattern = divide_random();
        divide_magnitude(numerator, 2048u, pattern);
        divide_magnitude(divisor, 1024u, pattern >> 2u);
        if ((lane % 4u) == 1u)
        {
            // a shared factor. The gcd runs past one step
            AnchorExactInteger shared;
            AnchorExactInteger product;
            divide_magnitude(&shared, 512u, pattern >> 4u);
            divide_magnitude(divisor, 512u, pattern >> 6u);
            anchor_exact_multiply(divisor, &shared, &product);
            *divisor = product;
            divide_magnitude(&product, 1024u, pattern >> 8u);
            anchor_exact_multiply(&product, &shared, numerator);
        }
        if (divisor->sign == 0)
        {
            divisor->limb[0] = 1u;
            divide_settle(divisor, 1);
        }
        divide_put(&atoms[lane * 96u], 0u, 2048u, numerator);
        divide_put(&atoms[lane * 96u], 2048u, 1024u, divisor);
    }
    int host_ran = 0;
    int device_ran = 0;
    divide_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    const unsigned int out_limbs = loaded.layout.out_limbs;
    divide_check(results, (host_ran != 0) && (device_ran != 0), "the wide program runs on the host and the device");
    divide_check(results, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
                 "the wide device records equal the host's word for word");
    int identities = (host_ran != 0);
    const DeviceRecordStep *const table = loaded.layout.step_table;
    for (unsigned int lane = 0u; (identities != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &host_out[lane * out_limbs];
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        AnchorExactInteger common;
        divide_take(record, table[2].out_offset, table[2].out_bits, &quotient);
        divide_take(record, table[3].out_offset, table[3].out_bits, &remainder);
        divide_take(record, table[4].out_offset, table[4].out_bits, &common);
        identities = divide_valid(&operand[2u * lane], &operand[(2u * lane) + 1u], &quotient, &remainder, &common);
    }
    divide_check(results, identities, "wide: the division identities and the gcd hold on every lane");
    divide_free(&loaded);

    if (divide_load(&exact, &loaded) == 0)
    {
        divide_check(results, 0, "the wide exact program loads");
    }
    else
    {
        memset(atoms, 0, (size_t)lanes * 96u * sizeof(unsigned int));
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            const unsigned int pattern = divide_random();
            divide_magnitude(&operand[2u * lane], 1024u, pattern);
            divide_magnitude(&operand[(2u * lane) + 1u], 1024u, pattern >> 2u);
            if (operand[(2u * lane) + 1u].sign == 0)
            {
                operand[(2u * lane) + 1u].limb[0] = 1u;
                divide_settle(&operand[(2u * lane) + 1u], 1);
            }
            divide_put(&atoms[lane * 64u], 0u, 1024u, &operand[2u * lane]);
            divide_put(&atoms[lane * 64u], 1024u, 1024u, &operand[(2u * lane) + 1u]);
        }
        divide_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        const unsigned int exact_limbs = loaded.layout.out_limbs;
        divide_check(results,
                     (host_ran != 0) && (device_ran != 0) &&
                         (memcmp(host_out, device_out, (size_t)lanes * exact_limbs * sizeof(unsigned int)) == 0),
                     "the wide exact quotient runs and the device equals the host");
        int factors = (host_ran != 0);
        for (unsigned int lane = 0u; (factors != 0) && (lane < lanes); lane += 1u)
        {
            AnchorExactInteger back;
            divide_take(&host_out[lane * exact_limbs], loaded.layout.step_table[3].out_offset,
                        loaded.layout.step_table[3].out_bits, &back);
            factors = anchor_exact_equal(&back, &operand[2u * lane]) != 0;
        }
        divide_check(results, factors, "wide: the exact quotient of factor . divisor by the divisor is the factor");
        divide_free(&loaded);
    }
    free(atoms);
    free(operand);
    free(host_out);
    free(device_out);
}

// a constant divisor narrows its quotient by floor(log2 c) bits. Signed 40-bit factors multiplied by 3, 12 and
// 2^32 + 7 divide back exactly; the last is a 3-limb numerator whose 41-bit quotient takes 2 limbs. The device's
// exact quotient must work at the numerator's width and keep only the register's. A signed 64-bit value over
// 2^32 + 7 is a 32-bit quotient in one limb, against the library's.
static void divide_constant(DivideResults *results)
{
    DivideProgram program;
    memset(&program, 0, sizeof(program));
    program.fields = 2u;
    program.field_bits[0] = 40u;
    program.field_bits[1] = 64u;
    program.field_offset[1] = 64u;
    program.in_limbs[0] = 4u;
    divide_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    divide_step(&program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    divide_step(&program, ENGINE_RECORD_CONSTANT, 3u, 0u);
    divide_step(&program, ENGINE_RECORD_CONSTANT, 12u, 0u);
    divide_step(&program, ENGINE_RECORD_CONSTANT, 7u, 1u);
    divide_step(&program, ENGINE_RECORD_PRODUCT, 0u, 2u);
    divide_step(&program, ENGINE_RECORD_EXACT_QUOTIENT, 5u, 2u);
    divide_step(&program, ENGINE_RECORD_PRODUCT, 0u, 3u);
    divide_step(&program, ENGINE_RECORD_EXACT_QUOTIENT, 7u, 3u);
    divide_step(&program, ENGINE_RECORD_PRODUCT, 0u, 4u);
    divide_step(&program, ENGINE_RECORD_EXACT_QUOTIENT, 9u, 4u);
    divide_step(&program, ENGINE_RECORD_QUOTIENT, 1u, 4u);
    program.outputs[0] = 6u;
    program.outputs[1] = 8u;
    program.outputs[2] = 10u;
    program.outputs[3] = 11u;
    program.output_count = 4u;
    DivideLoaded loaded;
    if (divide_load(&program, &loaded) == 0)
    {
        divide_check(results, 0, "the constant division program loads");
        return;
    }
    // 40 + 2 bits over 3 (2 bits) keeps 41; 40 + 4 over 12 (4 bits) keeps 41; 40 + 33 over 2^32 + 7 keeps 41 in 2
    // limbs from 73 in 3; 64 over 2^32 + 7 keeps 32
    const EngineRecordTerm *const term = loaded.key.term;
    divide_check(results,
                 (term[6].bits == 41u) && (term[8].bits == 41u) && (term[10].bits == 41u) && (term[9].bits == 73u) &&
                     (term[11].bits == 32u),
                 "a constant divisor narrows the quotient by floor(log2 c) bits");
    const unsigned int lanes = DIVIDE_TEST_NARROW_LANES;
    const unsigned int in_limbs = program.in_limbs[0];
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * in_limbs, sizeof(unsigned int));
    AnchorExactInteger *const operand = (AnchorExactInteger *)malloc((size_t)lanes * 2u * sizeof(AnchorExactInteger));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    if ((atoms == NULL) || (operand == NULL) || (host_out == NULL) || (device_out == NULL))
    {
        divide_check(results, 0, "the constant lanes are held");
        free(atoms);
        free(operand);
        free(host_out);
        free(device_out);
        divide_free(&loaded);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        AnchorExactInteger *const factor = &operand[2u * lane];
        AnchorExactInteger *const value = &operand[(2u * lane) + 1u];
        const unsigned int pattern = divide_random();
        divide_magnitude(factor, 39u, pattern);
        divide_magnitude(value, 63u, pattern >> 2u);
        factor->sign = ((divide_random() & 1u) != 0u) ? -factor->sign : factor->sign;
        value->sign = ((divide_random() & 1u) != 0u) ? -value->sign : value->sign;
        divide_put(&atoms[lane * in_limbs], 0u, 40u, factor);
        divide_put(&atoms[lane * in_limbs], 64u, 64u, value);
    }
    int host_ran = 0;
    int device_ran = 0;
    divide_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    divide_check(results,
                 (host_ran != 0) && (device_ran != 0) &&
                     (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                 "the constant program runs and the device equals the host word for word");
    AnchorExactInteger wide;
    anchor_exact_zero(&wide);
    wide.limb[0] = 7u;
    wide.limb[1] = 1u;
    wide.sign = 1;
    int factors = (host_ran != 0);
    int quotients = (host_ran != 0);
    const DeviceRecordStep *const table = loaded.layout.step_table;
    for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device_out[lane * out_limbs];
        for (unsigned int output = 0u; output < 3u; output += 1u)
        {
            AnchorExactInteger back;
            const unsigned int step = program.outputs[output];
            divide_take(record, table[step].out_offset, table[step].out_bits, &back);
            factors = factors && (anchor_exact_equal(&back, &operand[2u * lane]) != 0);
        }
        AnchorExactInteger quotient;
        AnchorExactInteger library;
        AnchorExactInteger rest;
        divide_take(record, table[11].out_offset, table[11].out_bits, &quotient);
        quotients = quotients &&
                    (anchor_exact_divide(&operand[(2u * lane) + 1u], &wide, &library, &rest) == ANCHOR_EXACT_OK) &&
                    (anchor_exact_equal(&quotient, &library) != 0);
    }
    divide_check(results, factors, "factor . c divides back exactly by 3, 12 and 2^32 + 7, the last narrowed a limb");
    divide_check(results, quotients, "a 64-bit value over 2^32 + 7 is the library's quotient in 32 bits");
    free(atoms);
    free(operand);
    free(host_out);
    free(device_out);
    divide_free(&loaded);
}

int main(int count, char **arguments)
{
    DivideResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = DIVIDE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)DIVIDE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_divide_test", count, arguments, DIVIDE_TEST_DECLARED);
    if (admitted != 0)
    {
        divide_narrow(&results);
        divide_wide(&results);
        divide_constant(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    divide_check(&results, (admitted != 0) && (job.failures == 0ull),
                 "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record divide test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
