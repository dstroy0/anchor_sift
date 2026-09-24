// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The exact integer's division as key primitives (ENGINE_RECORD_QUOTIENT, _REMAINDER, _GCD, _EXACT_QUOTIENT),
// proved on the register bit arrays. Each program runs on the device and on the host (whose steps are the
// exact integer library itself), the two records must agree word for word, and the decoded registers must meet
// numerator = quotient . divisor + remainder with the remainder below the divisor and carrying the numerator's
// sign, a gcd dividing both, and an exact quotient returning the factor it was built from. A zero divisor and an
// inexact division refuse, on both sides. Both register files are exercised: the 64-limb kernel on signed
// 160-bit numerators and the 256-limb kernel on 2048-bit numerators.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "exact_integer.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define DIVIDE_TEST_LINE 8192ull

#define DIVIDE_TEST_STEPS 16u

#define DIVIDE_TEST_FIELDS 4u

#define DIVIDE_TEST_NARROW_LANES 4096u

#define DIVIDE_TEST_WIDE_LANES 512u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} DivideTally;

typedef struct
{
    EngineRecordStep steps[DIVIDE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[DIVIDE_TEST_FIELDS];
    unsigned int field_offset[DIVIDE_TEST_FIELDS];
    unsigned int fields;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[DIVIDE_TEST_FIELDS];
    unsigned int output_count;
} DivideProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} DivideLoaded;

static unsigned long long s_divide_state = 0x5EED0F0D1D1DEull;

static unsigned int divide_random(void)
{
    s_divide_state ^= s_divide_state << 13u;
    s_divide_state ^= s_divide_state >> 7u;
    s_divide_state ^= s_divide_state << 17u;
    return (unsigned int)(s_divide_state >> 16u);
}

static void divide_check(DivideTally *tally, int held, const char *what)
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

static void divide_step(DivideProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

static int divide_load(DivideProgram *program, DivideLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    const KeymathRecordRequest imprint = {program->steps, program->count, program->field_bits, program->fields, 1u,
                                          program->outputs, program->output_count, NULL, 0u, &loaded->key,
                                          &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&loaded->key, program->field_offset, program->fields, program->in_limbs, 0,
                                          &loaded->layout, &loaded->error};
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

static void divide_free(DivideLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
static void divide_run(DivideLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                       unsigned int *device_out, int *host_ran, int *device_ran)
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

// write value into `bits` of the atom at offset, two's complement when negative
static void divide_put(unsigned int *atom, unsigned int offset, unsigned int bits, const AnchorExactInteger *value)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int held = (value->limb[bit / 32u] >> (bit % 32u)) & 1u;
        unsigned int written = held;
        if (value->sign < 0)
        {
            const unsigned int flipped = (held ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        atom[to / 32u] |= written << (to % 32u);
    }
}

// read `bits` at offset as two's complement
static void divide_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value)
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

static void divide_settle(AnchorExactInteger *value, int sign)
{
    int zero = 1;
    for (unsigned int limb = 0u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        zero = zero && (value->limb[limb] == 0u);
    }
    value->sign = (zero != 0) ? 0 : sign;
}

// a magnitude below 2^bits, in an edge shape picked by `shape`: random words over a random length, all ones, a
// lone top bit, or a top limb of 0x80000000 over random words
static void divide_magnitude(AnchorExactInteger *value, unsigned int bits, unsigned int shape)
{
    anchor_exact_zero(value);
    const unsigned int limbs = (bits + 31u) / 32u;
    const unsigned int used = 1u + (divide_random() % limbs);
    for (unsigned int limb = 0u; limb < used; limb += 1u)
    {
        const unsigned int word = divide_random();
        value->limb[limb] = ((shape % 4u) == 1u) ? 0xFFFFFFFFu : (((shape % 4u) == 2u) ? 0u : word);
    }
    if ((shape % 4u) == 2u)
    {
        value->limb[used - 1u] = 0x80000000u;
    }
    if ((shape % 4u) == 3u)
    {
        value->limb[used - 1u] = 0x80000000u | (divide_random() & 0x7FFFFFFFu);
    }
    const unsigned int spare = (32u * limbs) - bits;
    value->limb[limbs - 1u] &= 0xFFFFFFFFu >> spare;
    divide_settle(value, 1);
}

// the registers of one lane meet the division's identities and agree with the library on the operands
static int divide_holds(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                        const AnchorExactInteger *quotient, const AnchorExactInteger *remainder,
                        const AnchorExactInteger *common)
{
    AnchorExactInteger product;
    AnchorExactInteger rebuilt;
    int held = (anchor_exact_multiply(quotient, divisor, &product) == ANCHOR_EXACT_OK)
            && (anchor_exact_add(&product, remainder, &rebuilt) == ANCHOR_EXACT_OK)
            && (anchor_exact_equal(&rebuilt, numerator) != 0);
    AnchorExactInteger remainder_size = *remainder;
    AnchorExactInteger divisor_size = *divisor;
    remainder_size.sign = (remainder->sign != 0) ? 1 : 0;
    divisor_size.sign = 1;
    held = held && (anchor_exact_compare(&remainder_size, &divisor_size) < 0)
        && ((remainder->sign == 0) || (remainder->sign == numerator->sign));
    AnchorExactInteger whole;
    AnchorExactInteger rest;
    held = held && (common->sign >= 0)
        && (anchor_exact_divide(numerator, common, &whole, &rest) == ANCHOR_EXACT_OK) && (rest.sign == 0)
        && (anchor_exact_divide(divisor, common, &whole, &rest) == ANCHOR_EXACT_OK) && (rest.sign == 0);
    AnchorExactInteger library;
    held = held && (anchor_exact_gcd(numerator, divisor, &library) == ANCHOR_EXACT_OK)
        && (anchor_exact_equal(&library, common) != 0);
    return held;
}

// the 64-limb file: signed 160-bit numerators, 128-bit divisors, and 64-bit factors multiplied onto the divisor
// and divided back out exactly
static void divide_narrow(DivideTally *tally)
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
        divide_check(tally, 0, "the narrow division program loads");
        return;
    }
    divide_check(tally, loaded.layout.file_limbs <= 64u, "the narrow division program fits the 64-limb file");
    const unsigned int lanes = DIVIDE_TEST_NARROW_LANES;
    const unsigned int in_limbs = program.in_limbs[0];
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * in_limbs, sizeof(unsigned int));
    AnchorExactInteger *const operand = (AnchorExactInteger *)malloc((size_t)lanes * 3u * sizeof(AnchorExactInteger));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    if ((atoms == NULL) || (operand == NULL) || (host_out == NULL) || (device_out == NULL))
    {
        divide_check(tally, 0, "the narrow lanes are held");
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
        const unsigned int shape = divide_random();
        divide_magnitude(numerator, 159u, shape);
        divide_magnitude(divisor, 127u, shape >> 2u);
        divide_magnitude(factor, 63u, shape >> 4u);
        const unsigned int form = lane % 8u;
        if (form == 1u)
        {
            // a numerator one small step off a multiple, so the guessed quotient digits run near their bounds
            AnchorExactInteger small;
            AnchorExactInteger product;
            divide_magnitude(&small, 31u, shape >> 6u);
            anchor_exact_zero(factor);
            factor->limb[0] = divide_random() | 1u;
            divide_settle(factor, 1);
            anchor_exact_multiply(divisor, &small, &product);
            anchor_exact_add(&product, factor, numerator);
            divide_magnitude(factor, 63u, shape >> 4u);
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
            divide_magnitude(numerator, 64u, shape >> 6u);
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
    divide_check(tally, (host_ran != 0) && (device_ran != 0), "the narrow program runs on the host and the device");
    divide_check(tally, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
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
        identities = divide_holds(&operand[3u * lane], &operand[(3u * lane) + 1u], &quotient, &remainder, &common);
        factors = factors && (anchor_exact_equal(&exact, &operand[(3u * lane) + 2u]) != 0);
    }
    divide_check(tally, identities,
                 "narrow: numerator = quotient . divisor + remainder, the remainder below the divisor with the "
                 "numerator's sign, and the gcd divides both and equals the library's");
    divide_check(tally, factors, "narrow: the exact quotient of divisor . factor by the divisor is the factor");

    // a zero divisor and an inexact division refuse on both sides
    AnchorExactInteger zero;
    anchor_exact_zero(&zero);
    memset(atoms, 0, (size_t)in_limbs * sizeof(unsigned int));
    divide_put(atoms, 0u, 160u, &operand[0]);
    divide_put(atoms, 160u, 128u, &zero);
    divide_run(&loaded, atoms, 1u, host_out, device_out, &host_ran, &device_ran);
    divide_check(tally, (host_ran == 0) && (device_ran == 0), "a zero divisor refuses the lane, host and device");
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
        divide_check(tally, 0, "the inexact program loads");
    }
    else
    {
        // 3^40 + 1 over 3^20, then 3^40 over 3^20 = 3^20; and 40 over 24, whose low zeros pass but whose odd parts
        // (5 over 3) do not
        const unsigned int cases[3][4] = {{0x291FE822u, 0xA8B8B452u, 0xCFD41B91u, 0u},
                                          {0x291FE821u, 0xA8B8B452u, 0xCFD41B91u, 0u},
                                          {40u, 0u, 24u, 0u}};
        int refused = 1;
        int kept = 1;
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            divide_run(&loaded, cases[at], 1u, host_out, device_out, &host_ran, &device_ran);
            if (at == 1u)
            {
                kept = (host_ran != 0) && (device_ran != 0) && (host_out[0] == 0xCFD41B91u) && (device_out[0] == 0xCFD41B91u)
                    && (host_out[1] == 0u) && (device_out[1] == 0u);
            }
            else
            {
                refused = refused && (host_ran == 0) && (device_ran == 0);
            }
        }
        divide_check(tally, refused, "an inexact division refuses the lane, host and device");
        divide_check(tally, kept, "3^40 divides exactly by 3^20 to 3^20, host and device");
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
    divide_check(tally, divide_load(&forward, &loaded) == 0, "a quotient reading a later step is refused at imprint");
    free(atoms);
    free(operand);
    free(host_out);
    free(device_out);
}

// the 256-limb file: 2048-bit numerators over 1024-bit divisors, and a 1024-bit factor multiplied on and divided
// back out
static void divide_wide(DivideTally *tally)
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
    if ((atoms == NULL) || (operand == NULL) || (host_out == NULL) || (device_out == NULL)
        || (divide_load(&program, &loaded) == 0))
    {
        divide_check(tally, 0, "the wide division program loads");
        free(atoms);
        free(operand);
        free(host_out);
        free(device_out);
        return;
    }
    divide_check(tally, loaded.layout.file_limbs > 64u, "the wide division program takes the 256-limb file");
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        AnchorExactInteger *const numerator = &operand[2u * lane];
        AnchorExactInteger *const divisor = &operand[(2u * lane) + 1u];
        const unsigned int shape = divide_random();
        divide_magnitude(numerator, 2048u, shape);
        divide_magnitude(divisor, 1024u, shape >> 2u);
        if ((lane % 4u) == 1u)
        {
            // a shared factor, so the gcd runs past one step
            AnchorExactInteger shared;
            AnchorExactInteger product;
            divide_magnitude(&shared, 512u, shape >> 4u);
            divide_magnitude(divisor, 512u, shape >> 6u);
            anchor_exact_multiply(divisor, &shared, &product);
            *divisor = product;
            divide_magnitude(&product, 1024u, shape >> 8u);
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
    divide_check(tally, (host_ran != 0) && (device_ran != 0), "the wide program runs on the host and the device");
    divide_check(tally, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
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
        identities = divide_holds(&operand[2u * lane], &operand[(2u * lane) + 1u], &quotient, &remainder, &common);
    }
    divide_check(tally, identities, "wide: the division identities and the gcd hold on every lane");
    divide_free(&loaded);

    if (divide_load(&exact, &loaded) == 0)
    {
        divide_check(tally, 0, "the wide exact program loads");
    }
    else
    {
        memset(atoms, 0, (size_t)lanes * 96u * sizeof(unsigned int));
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            const unsigned int shape = divide_random();
            divide_magnitude(&operand[2u * lane], 1024u, shape);
            divide_magnitude(&operand[(2u * lane) + 1u], 1024u, shape >> 2u);
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
        divide_check(tally, (host_ran != 0) && (device_ran != 0)
                                && (memcmp(host_out, device_out, (size_t)lanes * exact_limbs * sizeof(unsigned int)) == 0),
                     "the wide exact quotient runs and the device equals the host");
        int factors = (host_ran != 0);
        for (unsigned int lane = 0u; (factors != 0) && (lane < lanes); lane += 1u)
        {
            AnchorExactInteger back;
            divide_take(&host_out[lane * exact_limbs], loaded.layout.step_table[3].out_offset,
                        loaded.layout.step_table[3].out_bits, &back);
            factors = anchor_exact_equal(&back, &operand[2u * lane]) != 0;
        }
        divide_check(tally, factors, "wide: the exact quotient of factor . divisor by the divisor is the factor");
        divide_free(&loaded);
    }
    free(atoms);
    free(operand);
    free(host_out);
    free(device_out);
}

int main(void)
{
    DivideTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = DIVIDE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)DIVIDE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    divide_narrow(&tally);
    divide_wide(&tally);
    scriptura_text(&tally.line, "  record divide test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
