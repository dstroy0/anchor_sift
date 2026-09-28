// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_divide_test_run.cu: steps, loading, running and narrow division
#include "record_divide_test_internal.h"

static unsigned long long s_divide_state = 0x5EED0F0D1D1DEull;

unsigned int divide_random(void)
{
    s_divide_state ^= s_divide_state << 13u;
    s_divide_state ^= s_divide_state >> 7u;
    s_divide_state ^= s_divide_state << 17u;
    return (unsigned int)(s_divide_state >> 16u);
}

void divide_check(DivideResults *results, int passed, const char *what)
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

void divide_step(DivideProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

int divide_load(DivideProgram *program, DivideLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    const KeymathRecordRequest encode_request = {program->steps,
                                                 program->count,
                                                 program->field_bits,
                                                 program->fields,
                                                 1u,
                                                 program->outputs,
                                                 program->output_count,
                                                 NULL,
                                                 0u,
                                                 &loaded->key,
                                                 &loaded->error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {
        &loaded->key, program->field_offset, program->fields, program->in_limbs, 0, &loaded->layout, &loaded->error};
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

void divide_free(DivideLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 errored
void divide_run(DivideLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
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

// write value into `bits` of the atom at offset, two's complement when negative
void divide_put(unsigned int *atom, unsigned int offset, unsigned int bits, const AnchorExactInteger *value)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int bit_value = (value->limb[bit / 32u] >> (bit % 32u)) & 1u;
        unsigned int written = bit_value;
        if (value->sign < 0)
        {
            const unsigned int flipped = (bit_value ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        atom[to / 32u] |= written << (to % 32u);
    }
}

// read `bits` at offset as two's complement
void divide_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        value->limb[bit / 32u] |= ((record[from / 32u] >> (from % 32u)) & 1u) << (bit % 32u);
    }
    const unsigned int top = bits - 1u;
    const int negative = ((value->limb[top / 32u] >> (top % 32u)) & 1u) != 0u;
    if (negative != 0)
    {
        unsigned long long carry = 1ull;
        for (unsigned int bit = 0u; bit < bits; bit += 32u)
        {
            const unsigned long long total = (unsigned long long)(~value->limb[bit / 32u] & 0xFFFFFFFFu) + carry;
            value->limb[bit / 32u] = (uint32_t)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        const unsigned int left = bits % 32u;
        value->limb[(bits - 1u) / 32u] &= (left == 0u) ? 0xFFFFFFFFu : ((1u << left) - 1u);
    }
    int zero = 1;
    for (unsigned int limb = 0u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        zero = zero && (value->limb[limb] == 0u);
    }
    value->sign = (zero != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

void divide_settle(AnchorExactInteger *value, int sign)
{
    int zero = 1;
    for (unsigned int limb = 0u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        zero = zero && (value->limb[limb] == 0u);
    }
    value->sign = (zero != 0) ? 0 : sign;
}

// a magnitude below 2^bits, in an edge case picked by `pattern`: random words over a random length, all ones, a
// lone top bit, or a top limb of 0x80000000 over random words
void divide_magnitude(AnchorExactInteger *value, unsigned int bits, unsigned int pattern)
{
    anchor_exact_zero(value);
    const unsigned int limbs = (bits + 31u) / 32u;
    const unsigned int used = 1u + (divide_random() % limbs);
    for (unsigned int limb = 0u; limb < used; limb += 1u)
    {
        const unsigned int word = divide_random();
        value->limb[limb] = ((pattern % 4u) == 1u) ? 0xFFFFFFFFu : (((pattern % 4u) == 2u) ? 0u : word);
    }
    if ((pattern % 4u) == 2u)
    {
        value->limb[used - 1u] = 0x80000000u;
    }
    if ((pattern % 4u) == 3u)
    {
        value->limb[used - 1u] = 0x80000000u | (divide_random() & 0x7FFFFFFFu);
    }
    const unsigned int spare = (32u * limbs) - bits;
    value->limb[limbs - 1u] &= 0xFFFFFFFFu >> spare;
    divide_settle(value, 1);
}

// the registers of one lane meet the division's identities and agree with the library on the operands
int divide_valid(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                 const AnchorExactInteger *quotient, const AnchorExactInteger *remainder,
                 const AnchorExactInteger *common)
{
    AnchorExactInteger product;
    AnchorExactInteger rebuilt;
    int passed = (anchor_exact_multiply(quotient, divisor, &product) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_add(&product, remainder, &rebuilt) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_equal(&rebuilt, numerator) != 0);
    AnchorExactInteger remainder_size = *remainder;
    AnchorExactInteger divisor_size = *divisor;
    remainder_size.sign = (remainder->sign != 0) ? 1 : 0;
    divisor_size.sign = 1;
    passed = passed && (anchor_exact_compare(&remainder_size, &divisor_size) < 0) &&
             ((remainder->sign == 0) || (remainder->sign == numerator->sign));
    AnchorExactInteger integer_part;
    AnchorExactInteger rest;
    passed = passed && (common->sign >= 0) &&
             (anchor_exact_divide(numerator, common, &integer_part, &rest) == ANCHOR_EXACT_OK) && (rest.sign == 0) &&
             (anchor_exact_divide(divisor, common, &integer_part, &rest) == ANCHOR_EXACT_OK) && (rest.sign == 0);
    AnchorExactInteger library;
    passed = passed && (anchor_exact_gcd(numerator, divisor, &library) == ANCHOR_EXACT_OK) &&
             (anchor_exact_equal(&library, common) != 0);
    return passed;
}

// the 64-limb file: signed 160-bit numerators, 128-bit divisors, and 64-bit factors multiplied onto the divisor
// and divided back out exactly
void divide_narrow(DivideResults *results)
{
    DivideProgram program;
    memset(&program, 0, sizeof(program));
    program.fields = 3u;
    program.field_bits[0] = 160u;
    program.field_bits[1] = 128u;
    program.field_bits[2] = 64u;
    program.field_offset[0] = 0u;
    program.field_offset[1] = 160u;
    program.field_offset[2] = 288u;
    program.in_limbs[0] = 11u;
    divide_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    divide_step(&program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    divide_step(&program, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u);
    divide_step(&program, ENGINE_RECORD_QUOTIENT, 0u, 1u);
    divide_step(&program, ENGINE_RECORD_REMAINDER, 0u, 1u);
    divide_step(&program, ENGINE_RECORD_GCD, 0u, 1u);
    divide_step(&program, ENGINE_RECORD_PRODUCT, 1u, 2u);
    divide_step(&program, ENGINE_RECORD_EXACT_QUOTIENT, 6u, 1u);
    program.outputs[0] = 3u;
    program.outputs[1] = 4u;
    program.outputs[2] = 5u;
    program.outputs[3] = 7u;
    program.output_count = 4u;
    DivideLoaded loaded;
    if (divide_load(&program, &loaded) == 0)
    {
        divide_check(results, 0, "the narrow division program loads");
        return;
    }
    divide_check(results, loaded.layout.file_limbs <= 64u, "the narrow division program fits the 64-limb file");
    const unsigned int lanes = DIVIDE_TEST_NARROW_LANES;
    const unsigned int in_limbs = program.in_limbs[0];
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * in_limbs, sizeof(unsigned int));
    AnchorExactInteger *const operand = (AnchorExactInteger *)malloc((size_t)lanes * 3u * sizeof(AnchorExactInteger));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    if ((atoms == NULL) || (operand == NULL) || (host_out == NULL) || (device_out == NULL))
    {
        divide_check(results, 0, "the narrow lanes are held");
        free(atoms);
        free(operand);
        free(host_out);
        free(device_out);
        divide_free(&loaded);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        AnchorExactInteger *const numerator = &operand[(3u * lane) + 0u];
        AnchorExactInteger *const divisor = &operand[(3u * lane) + 1u];
        AnchorExactInteger *const factor = &operand[(3u * lane) + 2u];
        const unsigned int pattern = divide_random();
        divide_magnitude(numerator, 159u, pattern);
        divide_magnitude(divisor, 127u, pattern >> 2u);
        divide_magnitude(factor, 63u, pattern >> 4u);
        const unsigned int form = lane % 8u;
        if (form == 1u)
        {
            // a numerator one small step off a multiple. The guessed quotient digits run near their bounds
            AnchorExactInteger small;
            AnchorExactInteger product;
            divide_magnitude(&small, 31u, pattern >> 6u);
            anchor_exact_zero(factor);
            factor->limb[0] = divide_random() | 1u;
            divide_settle(factor, 1);
            anchor_exact_multiply(divisor, &small, &product);
            anchor_exact_add(&product, factor, numerator);
            divide_magnitude(factor, 63u, pattern >> 4u);
        }
        else if (form == 2u)
        {
            anchor_exact_zero(divisor);
            divisor->limb[0] = 1u;
            divide_settle(divisor, 1);
        }
        else if (form == 3u)
        {
            anchor_exact_zero(numerator);
        }
        else if (form == 4u)
        {
            *numerator = *divisor;
        }
        else if (form == 5u)
        {
            divide_magnitude(numerator, 64u, pattern >> 6u);
        }
        else if ((form == 6u) && (lane == 6u))
        {
            // Knuth's add-back step: the guessed digit is one too many
            anchor_exact_zero(numerator);
            numerator->limb[2] = 0x80000000u;
            numerator->limb[3] = 0x7FFFFFFFu;
            divide_settle(numerator, 1);
            anchor_exact_zero(divisor);
            divisor->limb[0] = 1u;
            divisor->limb[2] = 0x80000000u;
            divide_settle(divisor, 1);
        }
        if (divisor->sign == 0)
        {
            divisor->limb[0] = 1u;
            divide_settle(divisor, 1);
        }
        numerator->sign = ((divide_random() & 1u) != 0u) ? -numerator->sign : numerator->sign;
        divisor->sign = ((divide_random() & 1u) != 0u) ? -divisor->sign : divisor->sign;
        factor->sign = ((divide_random() & 1u) != 0u) ? -factor->sign : factor->sign;
        unsigned int *const atom = &atoms[lane * in_limbs];
        divide_put(atom, 0u, 160u, numerator);
        divide_put(atom, 160u, 128u, divisor);
        divide_put(atom, 288u, 64u, factor);
    }
    int host_ran = 0;
    int device_ran = 0;
    divide_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    divide_check(results, (host_ran != 0) && (device_ran != 0), "the narrow program runs on the host and the device");
    divide_check(results, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
                 "the narrow device records equal the host's word for word");
    int identities = (host_ran != 0);
    int factors = (host_ran != 0);
    const DeviceRecordStep *const table = loaded.layout.step_table;
    for (unsigned int lane = 0u; (identities != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &host_out[lane * out_limbs];
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        AnchorExactInteger common;
        AnchorExactInteger exact;
        divide_take(record, table[3].out_offset, table[3].out_bits, &quotient);
        divide_take(record, table[4].out_offset, table[4].out_bits, &remainder);
        divide_take(record, table[5].out_offset, table[5].out_bits, &common);
        divide_take(record, table[7].out_offset, table[7].out_bits, &exact);
        identities = divide_valid(&operand[3u * lane], &operand[(3u * lane) + 1u], &quotient, &remainder, &common);
        factors = factors && (anchor_exact_equal(&exact, &operand[(3u * lane) + 2u]) != 0);
    }
    divide_check(results, identities,
                 "narrow: numerator = quotient . divisor + remainder, the remainder below the divisor with the "
                 "numerator's sign, and the gcd divides both and equals the library's");
    divide_check(results, factors, "narrow: the exact quotient of divisor . factor by the divisor is the factor");

    // a zero divisor and an inexact division error on both sides
    AnchorExactInteger zero;
    anchor_exact_zero(&zero);
    memset(atoms, 0, (size_t)in_limbs * sizeof(unsigned int));
    divide_put(atoms, 0u, 160u, &operand[0]);
    divide_put(atoms, 160u, 128u, &zero);
    divide_run(&loaded, atoms, 1u, host_out, device_out, &host_ran, &device_ran);
    divide_check(results, (host_ran == 0) && (device_ran == 0), "a zero divisor errors on the lane, host and device");
    divide_free(&loaded);

    DivideProgram inexact;
    memset(&inexact, 0, sizeof(inexact));
    inexact.fields = 2u;
    inexact.field_bits[0] = 64u;
    inexact.field_bits[1] = 64u;
    inexact.field_offset[1] = 64u;
    inexact.in_limbs[0] = 4u;
    divide_step(&inexact, ENGINE_RECORD_FIELD, 0u, 0u);
    divide_step(&inexact, ENGINE_RECORD_FIELD, 1u, 0u);
    divide_step(&inexact, ENGINE_RECORD_EXACT_QUOTIENT, 0u, 1u);
    inexact.outputs[0] = 2u;
    inexact.output_count = 1u;
    if (divide_load(&inexact, &loaded) == 0)
    {
        divide_check(results, 0, "the inexact program loads");
    }
    else
    {
        // 3^40 + 1 over 3^20, then 3^40 over 3^20 = 3^20; and 40 over 24, whose low zeros pass but whose odd parts
        // (5 over 3) do not
        const unsigned int cases[3][4] = {{0x291FE822u, 0xA8B8B452u, 0xCFD41B91u, 0u},
                                          {0x291FE821u, 0xA8B8B452u, 0xCFD41B91u, 0u},
                                          {40u, 0u, 24u, 0u}};
        int error = 1;
        int kept = 1;
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            divide_run(&loaded, cases[at], 1u, host_out, device_out, &host_ran, &device_ran);
            if (at == 1u)
            {
                kept = (host_ran != 0) && (device_ran != 0) && (host_out[0] == 0xCFD41B91u) &&
                       (device_out[0] == 0xCFD41B91u) && (host_out[1] == 0u) && (device_out[1] == 0u);
            }
            else
            {
                error = error && (host_ran == 0) && (device_ran == 0);
            }
        }
        divide_check(results, error, "an inexact division errors on the lane, host and device");
        divide_check(results, kept, "3^40 divides exactly by 3^20 to 3^20, host and device");
        divide_free(&loaded);
    }

    DivideProgram forward;
    memset(&forward, 0, sizeof(forward));
    forward.fields = 1u;
    forward.field_bits[0] = 32u;
    forward.in_limbs[0] = 1u;
    divide_step(&forward, ENGINE_RECORD_FIELD, 0u, 0u);
    divide_step(&forward, ENGINE_RECORD_QUOTIENT, 0u, 2u);
    divide_step(&forward, ENGINE_RECORD_FIELD, 0u, 0u);
    forward.outputs[0] = 1u;
    forward.output_count = 1u;
    divide_check(results, divide_load(&forward, &loaded) == 0, "a quotient reading a later step errors at encode");
    free(atoms);
    free(operand);
    free(host_out);
    free(device_out);
}
