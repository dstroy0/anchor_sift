// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's bitwise operations (ENGINE_RECORD_XOR, _AND) and its two's complement wrap (ENGINE_RECORD_WRAP),
// proved against an oracle that never reads a register. Every bit of every output is rebuilt from the raw two's
// complement fields in the atom, sign-extended, xored, anded and wrapped one bit at a time; a product's bits come from
// the exact integer library's multiply. Each program runs on the device and on the host, the two records must agree
// word for word, and the host's must equal the oracle on every written bit. The oracle's sign must also already
// extend for BITWISE_TEST_BEYOND bits past each written width, so a bound keymath set too narrow cannot hide in a
// truncated record. Hand-worked answers, both register files, and the refusals at imprint (a wrap below 4 bits, an
// operation reading a later step) are checked too. Last, a stack of floors far past a thousand steps (rounds over four
// 32-bit words, each floored by a wrap) runs as one program with register reuse, held to the CPU's own 64-bit two's
// complement at every tapped floor.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "exact_integer.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define BITWISE_TEST_LINE 8192ull

#define BITWISE_TEST_STEPS 24u

#define BITWISE_TEST_FIELDS 4u

#define BITWISE_TEST_NARROW_LANES 4096u

#define BITWISE_TEST_WIDE_LANES 512u

// how far past each output's written width the oracle's sign must already extend
#define BITWISE_TEST_BEYOND 64u

// the stack: floors of one round each over four 32-bit words, the round's steps, and the lanes it runs
#define BITWISE_TEST_FLOORS 700u

#define BITWISE_TEST_FLOOR_STEPS 6u

#define BITWISE_TEST_STACK_WORDS 4u

#define BITWISE_TEST_STACK_LANES 1024u

// the floors whose word is read out: the first, the middle, and the last four, which are the final state
#define BITWISE_TEST_STACK_TAPS 6u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} BitwiseTally;

typedef struct
{
    EngineRecordStep steps[BITWISE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[BITWISE_TEST_FIELDS];
    unsigned int field_offset[BITWISE_TEST_FIELDS];
    unsigned int fields;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[BITWISE_TEST_STEPS];
    unsigned int output_count;
} BitwiseProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} BitwiseLoaded;

// one lane's oracle: its atom, and each product step's exact value with its magnitude less one
typedef struct
{
    const BitwiseProgram *program;
    const unsigned int *atom;
    AnchorExactInteger product[BITWISE_TEST_STEPS];
    AnchorExactInteger product_less_one[BITWISE_TEST_STEPS];
} BitwiseOracle;

static unsigned long long s_bitwise_state = 0xB17B15E0A4D5EEDull;

static unsigned int bitwise_random(void)
{
    s_bitwise_state ^= s_bitwise_state << 13u;
    s_bitwise_state ^= s_bitwise_state >> 7u;
    s_bitwise_state ^= s_bitwise_state << 17u;
    return (unsigned int)(s_bitwise_state >> 16u);
}

static void bitwise_check(BitwiseTally *tally, int held, const char *what)
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

static void bitwise_step(BitwiseProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

static void bitwise_field(BitwiseProgram *program, unsigned int bits)
{
    const unsigned int field = program->fields;
    program->field_bits[field] = bits;
    program->field_offset[field] = (field == 0u) ? 0u : (program->field_offset[field - 1u] + program->field_bits[field - 1u]);
    program->in_limbs[0] = (program->field_offset[field] + bits + 31u) / 32u;
    program->fields += 1u;
}

static int bitwise_load(const BitwiseProgram *program, BitwiseLoaded *loaded)
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

static void bitwise_free(BitwiseLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
static void bitwise_run(BitwiseLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
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

// raw two's complement bits for one field, in an edge shape picked by `shape`: random bits, zero, all ones (-1), the
// top bit alone (the most negative), all but the top bit (the most positive), one, or random under a set top bit
static void bitwise_field_fill(unsigned int *atom, unsigned int offset, unsigned int bits, unsigned int shape)
{
    const unsigned int kind = shape % 7u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int top = (bit == (bits - 1u)) ? 1u : 0u;
        unsigned int held = bitwise_random() & 1u;
        if (kind == 1u)
        {
            held = 0u;
        }
        else if (kind == 2u)
        {
            held = 1u;
        }
        else if (kind == 3u)
        {
            held = top;
        }
        else if (kind == 4u)
        {
            held = top ^ 1u;
        }
        else if (kind == 5u)
        {
            held = (bit == 0u) ? 1u : 0u;
        }
        else if ((kind == 6u) && (top != 0u))
        {
            held = 1u;
        }
        const unsigned int to = offset + bit;
        atom[to / 32u] |= held << (to % 32u);
    }
}

// bit `bit` of a field's two's complement, sign-extended past its top bit
static unsigned int bitwise_field_bit(const unsigned int *atom, unsigned int offset, unsigned int bits, unsigned int bit)
{
    const unsigned int at = offset + ((bit < bits) ? bit : (bits - 1u));
    return (atom[at / 32u] >> (at % 32u)) & 1u;
}

// read `bits` at offset as two's complement into an exact integer
static void bitwise_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value)
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

// bit `bit` of an exact integer's two's complement, sign-extended without end: the magnitude's bit where the value
// is not negative, and the complement of the magnitude less one's bit where it is
static unsigned int bitwise_exact_bit(const AnchorExactInteger *value, const AnchorExactInteger *less_one,
                                      unsigned int bit)
{
    const AnchorExactInteger *const source = (value->sign < 0) ? less_one : value;
    const unsigned int held = (bit < (32u * ANCHOR_EXACT_LIMBS)) ? ((source->limb[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
    return (value->sign < 0) ? (held ^ 1u) : held;
}

// the field a field step reads, as an exact integer
static void bitwise_field_value(const BitwiseOracle *oracle, unsigned int at, AnchorExactInteger *value)
{
    const unsigned int field = oracle->program->steps[at].left;
    bitwise_take(oracle->atom, oracle->program->field_offset[field], oracle->program->field_bits[field], value);
}

// each product step's exact value and magnitude less one, from the library's multiply of the two fields it reads
static int bitwise_oracle_open(BitwiseOracle *oracle, const BitwiseProgram *program, const unsigned int *atom)
{
    oracle->program = program;
    oracle->atom = atom;
    for (unsigned int at = 0u; at < program->count; at += 1u)
    {
        if (program->steps[at].operation != ENGINE_RECORD_PRODUCT)
        {
            continue;
        }
        AnchorExactInteger left;
        AnchorExactInteger right;
        bitwise_field_value(oracle, program->steps[at].left, &left);
        bitwise_field_value(oracle, program->steps[at].right, &right);
        if (anchor_exact_multiply(&left, &right, &oracle->product[at]) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
        AnchorExactInteger magnitude = oracle->product[at];
        magnitude.sign = (magnitude.sign != 0) ? 1 : 0;
        AnchorExactInteger one;
        anchor_exact_zero(&one);
        one.limb[0] = 1u;
        one.sign = 1;
        oracle->product_less_one[at] = magnitude;
        if ((magnitude.sign != 0)
            && (anchor_exact_subtract(&magnitude, &one, &oracle->product_less_one[at]) != ANCHOR_EXACT_OK))
        {
            return 0;
        }
    }
    return 1;
}

// bit `bit` of step `at`'s value, sign-extended, rebuilt from the fields alone
static unsigned int bitwise_oracle_bit(const BitwiseOracle *oracle, unsigned int at, unsigned int bit)
{
    const BitwiseProgram *const program = oracle->program;
    const EngineRecordStep *const step = &program->steps[at];
    if (step->operation == ENGINE_RECORD_FIELD_SIGNED)
    {
        return bitwise_field_bit(oracle->atom, program->field_offset[step->left], program->field_bits[step->left], bit);
    }
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        // a field read unsigned extends with zeros past its top bit
        return (bit < program->field_bits[step->left])
                 ? bitwise_field_bit(oracle->atom, program->field_offset[step->left], program->field_bits[step->left], bit)
                 : 0u;
    }
    if (step->operation == ENGINE_RECORD_XOR)
    {
        return bitwise_oracle_bit(oracle, step->left, bit) ^ bitwise_oracle_bit(oracle, step->right, bit);
    }
    if (step->operation == ENGINE_RECORD_AND)
    {
        return bitwise_oracle_bit(oracle, step->left, bit) & bitwise_oracle_bit(oracle, step->right, bit);
    }
    if (step->operation == ENGINE_RECORD_WRAP)
    {
        // the low `right` bits kept, and the kept top bit extended as the sign
        return bitwise_oracle_bit(oracle, step->left, (bit < step->right) ? bit : (step->right - 1u));
    }
    return bitwise_exact_bit(&oracle->product[at], &oracle->product_less_one[at], bit);
}

// every written bit of each output equals the oracle's, and the oracle's sign already holds BITWISE_TEST_BEYOND bits
// past the written width
static int bitwise_record_holds(const BitwiseOracle *oracle, const DeviceRecordStep *table, const unsigned int *record)
{
    const BitwiseProgram *const program = oracle->program;
    for (unsigned int output = 0u; output < program->output_count; output += 1u)
    {
        const unsigned int at = program->outputs[output];
        const unsigned int offset = table[at].out_offset;
        const unsigned int bits = table[at].out_bits;
        const unsigned int sign = bitwise_oracle_bit(oracle, at, bits - 1u);
        for (unsigned int bit = 0u; bit < (bits + BITWISE_TEST_BEYOND); bit += 1u)
        {
            const unsigned int expected = bitwise_oracle_bit(oracle, at, bit);
            const unsigned int to = offset + bit;
            const unsigned int written = (bit < bits) ? ((record[to / 32u] >> (to % 32u)) & 1u) : sign;
            if (expected != written)
            {
                return 0;
            }
        }
    }
    return 1;
}

// fill `lanes` atoms with edge-shaped fields, run the program on both sides, and hold both records to the oracle
static void bitwise_prove(BitwiseTally *tally, const BitwiseProgram *program, unsigned int lanes, const char *name)
{
    BitwiseLoaded loaded;
    if (bitwise_load(program, &loaded) == 0)
    {
        scriptura_text(&tally->line, "  ");
        scriptura_text(&tally->line, name);
        scriptura_character(&tally->line, '\n');
        bitwise_check(tally, 0, "the program loads");
        return;
    }
    const unsigned int in_limbs = program->in_limbs[0];
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * in_limbs, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    BitwiseOracle *const oracle = (BitwiseOracle *)malloc(sizeof(BitwiseOracle));
    if ((atoms == NULL) || (host_out == NULL) || (device_out == NULL) || (oracle == NULL))
    {
        bitwise_check(tally, 0, "the lanes are held");
        free(atoms);
        free(host_out);
        free(device_out);
        free(oracle);
        bitwise_free(&loaded);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        const unsigned int shape = bitwise_random();
        for (unsigned int field = 0u; field < program->fields; field += 1u)
        {
            bitwise_field_fill(&atoms[lane * in_limbs], program->field_offset[field], program->field_bits[field],
                               shape >> (3u * field));
        }
    }
    int host_ran = 0;
    int device_ran = 0;
    bitwise_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    unsigned int held = 0u;
    for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
    {
        held += ((bitwise_oracle_open(oracle, program, &atoms[lane * in_limbs]) != 0)
                 && (bitwise_record_holds(oracle, loaded.layout.step_table, &host_out[lane * out_limbs]) != 0))
              ? 1u : 0u;
    }
    scriptura_text(&tally->line, "  ");
    scriptura_text(&tally->line, name);
    scriptura_text(&tally->line, ": ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes, ");
    scriptura_decimal(&tally->line, program->output_count, 1u);
    scriptura_text(&tally->line, " outputs, file ");
    scriptura_decimal(&tally->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs, ");
    scriptura_decimal(&tally->line, held, 1u);
    scriptura_text(&tally->line, " lanes equal the oracle\n");
    bitwise_check(tally, (host_ran != 0) && (device_ran != 0), "the program runs on the host and the device");
    bitwise_check(tally, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
                  "the device records equal the host's word for word");
    bitwise_check(tally, held == lanes, "every lane's record equals the oracle, and its sign extends past the width");
    free(atoms);
    free(host_out);
    free(device_out);
    free(oracle);
    bitwise_free(&loaded);
}

// the 64-limb file: signed fields of 100, 37 and 64 bits, xor and and across widths and with themselves, wraps from a
// nibble up to past the source, and a product wrapped and xored
static void bitwise_narrow(BitwiseTally *tally)
{
    BitwiseProgram program;
    memset(&program, 0, sizeof(program));
    bitwise_field(&program, 100u);
    bitwise_field(&program, 37u);
    bitwise_field(&program, 64u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_AND, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 1u, 2u);
    bitwise_step(&program, ENGINE_RECORD_AND, 2u, 2u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 4u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 33u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 64u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 1u, 200u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 100u);
    bitwise_step(&program, ENGINE_RECORD_PRODUCT, 0u, 2u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 12u, 96u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 12u, 7u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 12u, 1u);
    bitwise_step(&program, ENGINE_RECORD_AND, 3u, 5u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 3u, 101u);
    for (unsigned int at = 3u; at < program.count; at += 1u)
    {
        program.outputs[program.output_count] = at;
        program.output_count += 1u;
    }
    bitwise_prove(tally, &program, BITWISE_TEST_NARROW_LANES, "narrow (64-limb file)");
}

// the 256-limb file: signed fields of 1024 and 700 bits, their xor and and, wraps to a nibble, to half, past the
// source, and of the xor itself
static void bitwise_wide(BitwiseTally *tally)
{
    BitwiseProgram program;
    memset(&program, 0, sizeof(program));
    bitwise_field(&program, 1024u);
    bitwise_field(&program, 700u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_AND, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 4u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 513u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 1u, 3000u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 2u, 1025u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 2u, 3u);
    for (unsigned int at = 2u; at < program.count; at += 1u)
    {
        program.outputs[program.output_count] = at;
        program.output_count += 1u;
    }
    bitwise_prove(tally, &program, BITWISE_TEST_WIDE_LANES, "wide (256-limb file)");
}

// the widths keymath narrows for a register never negative: fields of 32 and 20 bits read unsigned beside a 40-bit
// field read signed. An and with an unsigned field is no wider than that field, the and and the xor of two unsigned are
// no wider than the narrower and the wider, and anything with a signed register keeps the extra bit. The oracle's sign
// must hold past each narrowed width, which a bound set too narrow would break.
static void bitwise_narrowed(BitwiseTally *tally)
{
    BitwiseProgram program;
    memset(&program, 0, sizeof(program));
    bitwise_field(&program, 32u);
    bitwise_field(&program, 20u);
    bitwise_field(&program, 40u);
    bitwise_step(&program, ENGINE_RECORD_FIELD, 0u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD, 1u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u);
    bitwise_step(&program, ENGINE_RECORD_AND, 0u, 2u);
    bitwise_step(&program, ENGINE_RECORD_AND, 2u, 1u);
    bitwise_step(&program, ENGINE_RECORD_AND, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 0u, 2u);
    bitwise_step(&program, ENGINE_RECORD_AND, 2u, 2u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 6u, 5u);
    bitwise_step(&program, ENGINE_RECORD_AND, 7u, 0u);
    for (unsigned int at = 3u; at < program.count; at += 1u)
    {
        program.outputs[program.output_count] = at;
        program.output_count += 1u;
    }
    BitwiseLoaded loaded;
    if (bitwise_load(&program, &loaded) == 0)
    {
        bitwise_check(tally, 0, "the narrowed program loads");
        return;
    }
    // each step's width as the imprint derived it: and(u32, s40) 32, and(s40, u20) 20, and(u32, u20) 20,
    // xor(u32, u20) 32, xor(u32, s40) 41, and(s40, s40) 41, xor of two unsigned 32, and(xor with a signed, u32) 32
    const unsigned int expected[8] = {32u, 20u, 20u, 32u, 41u, 41u, 32u, 32u};
    int widths = 1;
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        widths = widths && (loaded.key.term[3u + at].bits == expected[at]);
    }
    bitwise_check(tally, widths, "keymath narrows an and with a register never negative, and an xor of two");
    bitwise_free(&loaded);
    bitwise_prove(tally, &program, BITWISE_TEST_NARROW_LANES, "narrowed (never negative)");
}

// hand-worked answers over 16-bit fields: the xor, the and, and the wraps to 8 and 4 bits
static void bitwise_known(BitwiseTally *tally)
{
    BitwiseProgram program;
    memset(&program, 0, sizeof(program));
    bitwise_field(&program, 16u);
    bitwise_field(&program, 16u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    bitwise_step(&program, ENGINE_RECORD_XOR, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_AND, 0u, 1u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 8u);
    bitwise_step(&program, ENGINE_RECORD_WRAP, 0u, 4u);
    for (unsigned int at = 2u; at < program.count; at += 1u)
    {
        program.outputs[program.output_count] = at;
        program.output_count += 1u;
    }
    // left, right, then left xor right, left and right, left wrapped to 8 bits and to 4
    const long long cases[4][6] = {{-6, 3, -7, 2, -6, -6},
                                   {200, 5, 205, 0, -56, -8},
                                   {-1, -1, 0, -1, -1, -1},
                                   {-32768, 32767, -1, 0, 0, 0}};
    BitwiseLoaded loaded;
    if (bitwise_load(&program, &loaded) == 0)
    {
        bitwise_check(tally, 0, "the hand-worked program loads");
        return;
    }
    unsigned int atoms[4];
    for (unsigned int lane = 0u; lane < 4u; lane += 1u)
    {
        // a 16-bit field holds each value's low 16 bits of two's complement
        atoms[lane] = ((unsigned int)cases[lane][0] & 0xFFFFu) | (((unsigned int)cases[lane][1] & 0xFFFFu) << 16u);
    }
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const host_out = (unsigned int *)calloc((size_t)4u * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)4u * out_limbs, sizeof(unsigned int));
    int held = (host_out != NULL) && (device_out != NULL);
    int host_ran = 0;
    int device_ran = 0;
    if (held != 0)
    {
        bitwise_run(&loaded, atoms, 4u, host_out, device_out, &host_ran, &device_ran);
        held = (host_ran != 0) && (device_ran != 0)
            && (memcmp(host_out, device_out, (size_t)4u * out_limbs * sizeof(unsigned int)) == 0);
    }
    for (unsigned int lane = 0u; (held != 0) && (lane < 4u); lane += 1u)
    {
        for (unsigned int output = 0u; output < program.output_count; output += 1u)
        {
            const DeviceRecordStep *const step = &loaded.layout.step_table[program.outputs[output]];
            AnchorExactInteger value;
            bitwise_take(&host_out[lane * out_limbs], step->out_offset, step->out_bits, &value);
            // every answer is below 2^16 in magnitude, one limb
            const long long read = (long long)value.sign * (long long)value.limb[0];
            held = held && (read == cases[lane][2u + output]);
        }
    }
    bitwise_check(tally, held,
                  "-6 ^ 3 = -7, -6 & 3 = 2, 200 wraps to -56 in 8 bits and -8 in 4, -32768 ^ 32767 = -1, and the rest");
    free(host_out);
    free(device_out);
    bitwise_free(&loaded);
}

// a wrap below 4 bits, and an xor, an and or a wrap reading a later step, refuse at imprint
static void bitwise_refused(BitwiseTally *tally)
{
    const EngineRecordOperation operations[4] = {ENGINE_RECORD_WRAP, ENGINE_RECORD_XOR, ENGINE_RECORD_AND,
                                                 ENGINE_RECORD_WRAP};
    const unsigned int rights[4] = {3u, 2u, 2u, 8u};
    const unsigned int lefts[4] = {0u, 0u, 2u, 2u};
    const char *const what[4] = {"a wrap to 3 bits is refused at imprint", "an xor reading a later step is refused",
                                 "an and reading a later step is refused", "a wrap reading a later step is refused"};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        BitwiseProgram program;
        memset(&program, 0, sizeof(program));
        bitwise_field(&program, 16u);
        bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        bitwise_step(&program, operations[at], lefts[at], rights[at]);
        bitwise_step(&program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        program.outputs[0] = 1u;
        program.output_count = 1u;
        BitwiseLoaded loaded;
        const int loads = bitwise_load(&program, &loaded);
        bitwise_check(tally, loads == 0, what[at]);
        if (loads != 0)
        {
            bitwise_free(&loaded);
        }
    }
    BitwiseProgram nibble;
    memset(&nibble, 0, sizeof(nibble));
    bitwise_field(&nibble, 16u);
    bitwise_step(&nibble, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    bitwise_step(&nibble, ENGINE_RECORD_WRAP, 0u, ENGINE_RECORD_WRAP_BITS_LEAST);
    nibble.outputs[0] = 1u;
    nibble.output_count = 1u;
    BitwiseLoaded loaded;
    const int loads = bitwise_load(&nibble, &loaded);
    bitwise_check(tally, loads != 0, "a wrap to 4 bits loads");
    if (loads != 0)
    {
        bitwise_free(&loaded);
    }
}

// a value's low `bits` read back signed, on the CPU's own two's complement
static long long bitwise_wrap_native(long long value, unsigned int bits)
{
    const unsigned long long mask = (bits >= 64u) ? ~0ull : ((1ull << bits) - 1ull);
    const unsigned long long low = (unsigned long long)value & mask;
    const unsigned long long top = 1ull << (bits - 1u);
    // a set top kept bit means 2^bits comes off: low - top - top, taken apart so neither half leaves the signed range
    return ((low & top) != 0ull) ? ((long long)(low - top) - (long long)top) : (long long)low;
}

// the floor's constant: the low 32 bits of the floor times the golden ratio's 32-bit word
static unsigned int bitwise_floor_constant(unsigned int floor)
{
    return floor * 0x9E3779B9u;
}

// a stack of BITWISE_TEST_FLOORS floors over four 32-bit words (w0, w1, w2, w3). Each floor's round is
// n = wrap32(((w2 and (w0 xor w1)) + w3) xor constant), and the words move down one: (w1, w2, w3, n). One program,
// register reuse on, far past a thousand steps; the oracle runs the same rounds on long long.
static void bitwise_stack(BitwiseTally *tally)
{
    const unsigned int count = BITWISE_TEST_STACK_WORDS + (BITWISE_TEST_FLOORS * BITWISE_TEST_FLOOR_STEPS);
    EngineRecordStep *const steps = (EngineRecordStep *)calloc(count, sizeof(EngineRecordStep));
    long long *const oracle = (long long *)malloc((size_t)count * sizeof(long long));
    if ((steps == NULL) || (oracle == NULL))
    {
        bitwise_check(tally, 0, "the stack is held");
        free(steps);
        free(oracle);
        return;
    }
    unsigned int field_bits[BITWISE_TEST_STACK_WORDS];
    unsigned int field_offset[BITWISE_TEST_STACK_WORDS];
    unsigned int word[BITWISE_TEST_STACK_WORDS];
    for (unsigned int at = 0u; at < BITWISE_TEST_STACK_WORDS; at += 1u)
    {
        field_bits[at] = 32u;
        field_offset[at] = 32u * at;
        steps[at].operation = ENGINE_RECORD_FIELD_SIGNED;
        steps[at].left = at;
        word[at] = at;
    }
    unsigned int outputs[BITWISE_TEST_STACK_TAPS];
    unsigned int output_count = 0u;
    unsigned int at = BITWISE_TEST_STACK_WORDS;
    for (unsigned int floor = 0u; floor < BITWISE_TEST_FLOORS; floor += 1u)
    {
        const unsigned int mixed = at;
        steps[at] = EngineRecordStep{ENGINE_RECORD_XOR, word[0], word[1], 0u};
        steps[at + 1u] = EngineRecordStep{ENGINE_RECORD_AND, word[2], mixed, 0u};
        steps[at + 2u] = EngineRecordStep{ENGINE_RECORD_SUM, at + 1u, word[3], 0u};
        steps[at + 3u] = EngineRecordStep{ENGINE_RECORD_CONSTANT, bitwise_floor_constant(floor), 0u, 0u};
        steps[at + 4u] = EngineRecordStep{ENGINE_RECORD_XOR, at + 2u, at + 3u, 0u};
        steps[at + 5u] = EngineRecordStep{ENGINE_RECORD_WRAP, at + 4u, 32u, 0u};
        word[0] = word[1];
        word[1] = word[2];
        word[2] = word[3];
        word[3] = at + 5u;
        if ((floor == 0u) || (floor == (BITWISE_TEST_FLOORS / 2u)) || ((floor + 4u) >= BITWISE_TEST_FLOORS))
        {
            outputs[output_count] = at + 5u;
            output_count += 1u;
        }
        at += BITWISE_TEST_FLOOR_STEPS;
    }
    BitwiseLoaded loaded;
    memset(&loaded, 0, sizeof(loaded));
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {BITWISE_TEST_STACK_WORDS, 0u, 0u};
    const KeymathRecordRequest imprint = {steps, count, field_bits, BITWISE_TEST_STACK_WORDS, 1u, outputs,
                                          output_count, NULL, 0u, &loaded.key, &loaded.error};
    const KeyScheduleRecordRequest lay = {&loaded.key, field_offset, BITWISE_TEST_STACK_WORDS, in_limbs, 1,
                                          &loaded.layout, &loaded.error};
    int loads = keymath_record_imprint(&imprint) != KEYMATH_REFUSED;
    loads = loads && (key_schedule_record_lay(&lay) != KEY_SCHEDULE_REFUSED);
    loads = loads && (cycle_record_load(&loaded.layout, &loaded.record, &loaded.error) != CYCLE_REFUSED);
    bitwise_check(tally, loads, "a stack of 4204 steps imprints, lays with reuse and loads");
    if (loads == 0)
    {
        free(steps);
        free(oracle);
        return;
    }
    const unsigned int lanes = BITWISE_TEST_STACK_LANES;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * BITWISE_TEST_STACK_WORDS, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    int host_ran = 0;
    int device_ran = 0;
    unsigned int held = 0u;
    if ((atoms != NULL) && (host_out != NULL) && (device_out != NULL))
    {
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            const unsigned int shape = bitwise_random();
            for (unsigned int field = 0u; field < BITWISE_TEST_STACK_WORDS; field += 1u)
            {
                bitwise_field_fill(&atoms[lane * BITWISE_TEST_STACK_WORDS], field_offset[field], 32u,
                                   shape >> (3u * field));
            }
        }
        bitwise_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
        {
            const unsigned int *const atom = &atoms[lane * BITWISE_TEST_STACK_WORDS];
            for (unsigned int step = 0u; step < count; step += 1u)
            {
                const EngineRecordStep *const doing = &steps[step];
                if (doing->operation == ENGINE_RECORD_FIELD_SIGNED)
                {
                    // a 32-bit field read signed: 2^32 comes off where its top bit is set
                    const unsigned int raw = atom[doing->left];
                    oracle[step] = ((raw & 0x80000000u) != 0u) ? ((long long)raw - 4294967296ll) : (long long)raw;
                }
                else if (doing->operation == ENGINE_RECORD_XOR)
                {
                    oracle[step] = oracle[doing->left] ^ oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_AND)
                {
                    oracle[step] = oracle[doing->left] & oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_SUM)
                {
                    oracle[step] = oracle[doing->left] + oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_CONSTANT)
                {
                    oracle[step] = (long long)doing->left;
                }
                else
                {
                    oracle[step] = bitwise_wrap_native(oracle[doing->left], doing->right);
                }
            }
            int lane_held = 1;
            for (unsigned int output = 0u; output < output_count; output += 1u)
            {
                const DeviceRecordStep *const tapped = &loaded.layout.step_table[outputs[output]];
                AnchorExactInteger value;
                bitwise_take(&host_out[lane * out_limbs], tapped->out_offset, tapped->out_bits, &value);
                // a floor's word lies in [-2^31, 2^31), one limb of magnitude
                const long long read = (long long)value.sign * (long long)value.limb[0];
                lane_held = lane_held && (read == oracle[outputs[output]]);
            }
            held += (lane_held != 0) ? 1u : 0u;
        }
    }
    scriptura_text(&tally->line, "  stack: ");
    scriptura_decimal(&tally->line, BITWISE_TEST_FLOORS, 1u);
    scriptura_text(&tally->line, " floors, ");
    scriptura_decimal(&tally->line, count, 1u);
    scriptura_text(&tally->line, " steps, file ");
    scriptura_decimal(&tally->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs, ");
    scriptura_decimal(&tally->line, held, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes equal the CPU's rounds at every tapped floor\n");
    bitwise_check(tally, (host_ran != 0) && (device_ran != 0), "the stack runs on the host and the device");
    bitwise_check(tally,
                  (host_ran != 0) && (device_ran != 0)
                      && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                  "the stack's device records equal the host's word for word");
    bitwise_check(tally, held == lanes, "every lane's tapped floors equal the CPU's rounds");
    free(atoms);
    free(host_out);
    free(device_out);
    free(steps);
    free(oracle);
    bitwise_free(&loaded);
}

int main(void)
{
    BitwiseTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = BITWISE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)BITWISE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    bitwise_known(&tally);
    bitwise_narrow(&tally);
    bitwise_narrowed(&tally);
    bitwise_wide(&tally);
    bitwise_refused(&tally);
    bitwise_stack(&tally);
    scriptura_text(&tally.line, "  record bitwise test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
