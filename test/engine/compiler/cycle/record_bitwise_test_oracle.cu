// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_bitwise_test_oracle.cu: fields, the oracle and held records
#include "record_bitwise_test_internal.h"

static unsigned long long s_bitwise_state = 0xB17B15E0A4D5EEDull;

unsigned int bitwise_random(void)
{
    s_bitwise_state ^= s_bitwise_state << 13u;
    s_bitwise_state ^= s_bitwise_state >> 7u;
    s_bitwise_state ^= s_bitwise_state << 17u;
    return (unsigned int)(s_bitwise_state >> 16u);
}

void bitwise_check(BitwiseResults *results, int passed, const char *what)
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

void bitwise_step(BitwiseProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = 0u;
    program->count += 1u;
}

void bitwise_field(BitwiseProgram *program, unsigned int bits)
{
    const unsigned int field = program->fields;
    program->field_bits[field] = bits;
    program->field_offset[field] =
        (field == 0u) ? 0u : (program->field_offset[field - 1u] + program->field_bits[field - 1u]);
    program->in_limbs[0] = (program->field_offset[field] + bits + 31u) / 32u;
    program->fields += 1u;
}

int bitwise_load(const BitwiseProgram *program, BitwiseLoaded *loaded)
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

void bitwise_free(BitwiseLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
void bitwise_run(BitwiseLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
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

// raw two's complement bits for one field, in an edge case picked by `pattern`: random bits, zero, all ones (-1), the
// top bit alone (the most negative), all but the top bit (the most positive), one, or random under a set top bit
void bitwise_field_fill(unsigned int *atom, unsigned int offset, unsigned int bits, unsigned int pattern)
{
    const unsigned int kind = pattern % 7u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int top = (bit == (bits - 1u)) ? 1u : 0u;
        unsigned int bit_value = bitwise_random() & 1u;
        if (kind == 1u)
        {
            bit_value = 0u;
        }
        else if (kind == 2u)
        {
            bit_value = 1u;
        }
        else if (kind == 3u)
        {
            bit_value = top;
        }
        else if (kind == 4u)
        {
            bit_value = top ^ 1u;
        }
        else if (kind == 5u)
        {
            bit_value = (bit == 0u) ? 1u : 0u;
        }
        else if ((kind == 6u) && (top != 0u))
        {
            bit_value = 1u;
        }
        const unsigned int to = offset + bit;
        atom[to / 32u] |= bit_value << (to % 32u);
    }
}

// bit `bit` of a field's two's complement, sign-extended past its top bit
static unsigned int bitwise_field_bit(const unsigned int *atom, unsigned int offset, unsigned int bits,
                                      unsigned int bit)
{
    const unsigned int at = offset + ((bit < bits) ? bit : (bits - 1u));
    return (atom[at / 32u] >> (at % 32u)) & 1u;
}

// read `bits` at offset as two's complement into an exact integer
void bitwise_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value)
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
    const unsigned int bit_value =
        (bit < (32u * ANCHOR_EXACT_LIMBS)) ? ((source->limb[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
    return (value->sign < 0) ? (bit_value ^ 1u) : bit_value;
}

// the field a field step reads, as an exact integer
static void bitwise_field_value(const BitwiseOracle *oracle, unsigned int at, AnchorExactInteger *value)
{
    const unsigned int field = oracle->program->steps[at].left;
    bitwise_take(oracle->atom, oracle->program->field_offset[field], oracle->program->field_bits[field], value);
}

// each product step's exact value and magnitude less one, from the library's multiply of the two fields it reads
int bitwise_oracle_open(BitwiseOracle *oracle, const BitwiseProgram *program, const unsigned int *atom)
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
        if ((magnitude.sign != 0) &&
            (anchor_exact_subtract(&magnitude, &one, &oracle->product_less_one[at]) != ANCHOR_EXACT_OK))
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
                   ? bitwise_field_bit(oracle->atom, program->field_offset[step->left], program->field_bits[step->left],
                                       bit)
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
int bitwise_record_valid(const BitwiseOracle *oracle, const DeviceRecordStep *table, const unsigned int *record)
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
