// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_bitwise_test_prove.cu: proofs, narrow and wide, known and errored
#include "record_bitwise_test_internal.h"

// fill `lanes` atoms with edge-shaped fields, run the program on both sides, and hold both records to the oracle
static void bitwise_prove(BitwiseResults *results, const BitwiseProgram *program, unsigned int lanes, const char *name)
{
    BitwiseLoaded loaded;
    if (bitwise_load(program, &loaded) == 0)
    {
        scriptura_text(&results->line, "  ");
        scriptura_text(&results->line, name);
        scriptura_character(&results->line, '\n');
        bitwise_check(results, 0, "the program loads");
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
        bitwise_check(results, 0, "the lanes are held");
        free(atoms);
        free(host_out);
        free(device_out);
        free(oracle);
        bitwise_free(&loaded);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        const unsigned int pattern = bitwise_random();
        for (unsigned int field = 0u; field < program->fields; field += 1u)
        {
            bitwise_field_fill(&atoms[lane * in_limbs], program->field_offset[field], program->field_bits[field],
                               pattern >> (3u * field));
        }
    }
    int host_ran = 0;
    int device_ran = 0;
    bitwise_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    unsigned int lanes_equal = 0u;
    for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
    {
        lanes_equal += ((bitwise_oracle_open(oracle, program, &atoms[lane * in_limbs]) != 0) &&
                        (bitwise_record_valid(oracle, loaded.layout.step_table, &host_out[lane * out_limbs]) != 0))
                           ? 1u
                           : 0u;
    }
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, ": ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes, ");
    scriptura_decimal(&results->line, program->output_count, 1u);
    scriptura_text(&results->line, " outputs, file ");
    scriptura_decimal(&results->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs, ");
    scriptura_decimal(&results->line, lanes_equal, 1u);
    scriptura_text(&results->line, " lanes equal the oracle\n");
    bitwise_check(results, (host_ran != 0) && (device_ran != 0), "the program runs on the host and the device");
    bitwise_check(results, memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0,
                  "the device records equal the host's word for word");
    bitwise_check(results, lanes_equal == lanes,
                  "every lane's record equals the oracle, and its sign extends past the width");
    free(atoms);
    free(host_out);
    free(device_out);
    free(oracle);
    bitwise_free(&loaded);
}

// the 64-limb file: signed fields of 100, 37 and 64 bits, xor and and across widths and with themselves, wraps from a
// nibble up to past the source, and a product wrapped and xored
void bitwise_narrow(BitwiseResults *results)
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
    bitwise_prove(results, &program, BITWISE_TEST_NARROW_LANES, "narrow (64-limb file)");
}

// the 256-limb file: signed fields of 1024 and 700 bits, their xor and and, wraps to a nibble, to half, past the
// source, and of the xor itself
void bitwise_wide(BitwiseResults *results)
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
    bitwise_prove(results, &program, BITWISE_TEST_WIDE_LANES, "wide (256-limb file)");
}

// the widths keymath narrows for a register never negative: fields of 32 and 20 bits read unsigned beside a 40-bit
// field read signed. An and with an unsigned field is no wider than that field, the and and the xor of two unsigned are
// no wider than the narrower and the wider, and anything with a signed register keeps the extra bit. The oracle's sign
// must hold past each narrowed width, which a bound set too narrow would break.
void bitwise_narrowed(BitwiseResults *results)
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
        bitwise_check(results, 0, "the narrowed program loads");
        return;
    }
    // each step's width as the encoding derived it: and(u32, s40) 32, and(s40, u20) 20, and(u32, u20) 20,
    // xor(u32, u20) 32, xor(u32, s40) 41, and(s40, s40) 41, xor of two unsigned 32, and(xor with a signed, u32) 32
    const unsigned int expected[8] = {32u, 20u, 20u, 32u, 41u, 41u, 32u, 32u};
    int widths = 1;
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        widths = widths && (loaded.key.term[3u + at].bits == expected[at]);
    }
    bitwise_check(results, widths, "keymath narrows an and with a register never negative, and an xor of two");
    bitwise_free(&loaded);
    bitwise_prove(results, &program, BITWISE_TEST_NARROW_LANES, "narrowed (never negative)");
}

// hand-worked answers over 16-bit fields: the xor, the and, and the wraps to 8 and 4 bits
void bitwise_known(BitwiseResults *results)
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
    const long long cases[4][6] = {
        {-6, 3, -7, 2, -6, -6}, {200, 5, 205, 0, -56, -8}, {-1, -1, 0, -1, -1, -1}, {-32768, 32767, -1, 0, 0, 0}};
    BitwiseLoaded loaded;
    if (bitwise_load(&program, &loaded) == 0)
    {
        bitwise_check(results, 0, "the hand-worked program loads");
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
    int passed = (host_out != NULL) && (device_out != NULL);
    int host_ran = 0;
    int device_ran = 0;
    if (passed != 0)
    {
        bitwise_run(&loaded, atoms, 4u, host_out, device_out, &host_ran, &device_ran);
        passed = (host_ran != 0) && (device_ran != 0) &&
                 (memcmp(host_out, device_out, (size_t)4u * out_limbs * sizeof(unsigned int)) == 0);
    }
    for (unsigned int lane = 0u; (passed != 0) && (lane < 4u); lane += 1u)
    {
        for (unsigned int output = 0u; output < program.output_count; output += 1u)
        {
            const DeviceRecordStep *const step = &loaded.layout.step_table[program.outputs[output]];
            AnchorExactInteger value;
            bitwise_take(&host_out[lane * out_limbs], step->out_offset, step->out_bits, &value);
            // every answer is below 2^16 in magnitude, one limb
            const long long read = (long long)value.sign * (long long)value.limb[0];
            passed = passed && (read == cases[lane][2u + output]);
        }
    }
    bitwise_check(results, passed,
                  "-6 ^ 3 = -7, -6 & 3 = 2, 200 wraps to -56 in 8 bits and -8 in 4, -32768 ^ 32767 = -1, and the rest");
    free(host_out);
    free(device_out);
    bitwise_free(&loaded);
}

// a wrap below 4 bits, and an xor, an and or a wrap reading a later step, error at encode
void bitwise_error(BitwiseResults *results)
{
    const EngineRecordOperation operations[4] = {ENGINE_RECORD_WRAP, ENGINE_RECORD_XOR, ENGINE_RECORD_AND,
                                                 ENGINE_RECORD_WRAP};
    const unsigned int rights[4] = {3u, 2u, 2u, 8u};
    const unsigned int lefts[4] = {0u, 0u, 2u, 2u};
    const char *const what[4] = {"a wrap to 3 bits errors at encode", "an xor reading a later step errors",
                                 "an and reading a later step errors", "a wrap reading a later step errors"};
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
        bitwise_check(results, loads == 0, what[at]);
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
    bitwise_check(results, loads != 0, "a wrap to 4 bits loads");
    if (loads != 0)
    {
        bitwise_free(&loaded);
    }
}

// a value's low `bits` read back signed, on the CPU's own two's complement
long long bitwise_wrap_native(long long value, unsigned int bits)
{
    const unsigned long long mask = (bits >= 64u) ? ~0ull : ((1ull << bits) - 1ull);
    const unsigned long long low = (unsigned long long)value & mask;
    const unsigned long long top = 1ull << (bits - 1u);
    // a set top kept bit means 2^bits comes off: low - top - top, taken apart so neither half leaves the signed range
    return ((low & top) != 0ull) ? ((long long)(low - top) - (long long)top) : (long long)low;
}

// the floor's constant: the low 32 bits of the floor times the golden ratio's 32-bit word
unsigned int bitwise_floor_constant(unsigned int floor)
{
    return floor * 0x9E3779B9u;
}
