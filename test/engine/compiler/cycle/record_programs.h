// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RECORD_PROGRAMS_H
#define RECORD_PROGRAMS_H

// The record programs the host oracle's test runs (record_host_test.c) and the tests that hold another
// language to it (record_vhdl_test.cpp): each program, encoded and laid out, and the one xorshift stream its
// inputs are drawn from: every test that draws them in the same order draws the same atoms, and the
// digest that two parts' lines compare. It compiles as C and as C++

#include "cycle.h"
#include "exact_integer.h"
#include "key_schedule.h"
#include "keymath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HOST_TEST_LANES 4096u

#define HOST_TEST_STEPS 16u

#define HOST_TEST_FIELDS 4u

#define HOST_TEST_TABLES 2u

// the second program's bodies per member, read through an index
#define HOST_TEST_FIRST_BODIES 1000u

#define HOST_TEST_SECOND_BODIES 777u

#define HOST_TEST_FNV_BASIS 0xCBF29CE484222325ull

#define HOST_TEST_FNV_PRIME 0x100000001B3ull

typedef struct
{
    const char *name;
    EngineRecordStep steps[HOST_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[HOST_TEST_FIELDS];
    unsigned int field_offset[HOST_TEST_FIELDS];
    unsigned int fields;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[HOST_TEST_STEPS];
    unsigned int output_count;
    EngineRecordTable tables[HOST_TEST_TABLES];
    unsigned int table_count;
} HostProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    EngineError error;
} HostLoaded;

static unsigned long long s_host_state = 0x5EED0C0FFEE5ull;

static unsigned int host_random(void)
{
    s_host_state ^= s_host_state << 13u;
    s_host_state ^= s_host_state >> 7u;
    s_host_state ^= s_host_state << 17u;
    return (unsigned int)(s_host_state >> 16u);
}

// FNV-1a over each word's four bytes from the lowest: the digest reads the words and not the part's byte order
static unsigned long long host_digest(const unsigned int *words, unsigned long long count)
{
    unsigned long long hash = HOST_TEST_FNV_BASIS;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        for (unsigned int byte = 0u; byte < 4u; byte += 1u)
        {
            hash ^= (unsigned long long)((words[at] >> (8u * byte)) & 0xFFu);
            hash *= HOST_TEST_FNV_PRIME;
        }
    }
    return hash;
}

static void host_step(HostProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right,
                      unsigned int member)
{
    EngineRecordStep *const step = &program->steps[program->count];
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = member;
    program->count += 1u;
}

static void host_field(HostProgram *program, unsigned int bits, unsigned int offset)
{
    program->field_bits[program->fields] = bits;
    program->field_offset[program->fields] = offset;
    program->fields += 1u;
}

static int host_load(const HostProgram *program, int reuse, HostLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    const KeymathRecordRequest encode_request = {
        program->steps,        program->count,
        program->field_bits,   program->fields,
        program->members,      program->outputs,
        program->output_count, (program->table_count != 0u) ? program->tables : NULL,
        program->table_count,  &loaded->key,
        &loaded->error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {
        &loaded->key, program->field_offset, program->fields, program->in_limbs,
        reuse,        &loaded->layout,       &loaded->error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

static void host_free(HostLoaded *loaded)
{
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

static unsigned int *host_atoms(unsigned int limbs, unsigned int bodies)
{
    unsigned int *const atoms = (unsigned int *)malloc((size_t)limbs * bodies * sizeof(unsigned int));
    for (unsigned long long at = 0ull; (atoms != NULL) && (at < ((unsigned long long)limbs * bodies)); at += 1ull)
    {
        atoms[at] = host_random();
    }
    return atoms;
}

// fields, a constant, the product, sum, difference, absolute and compare, and the golden ladder over a positive
// constant: a signed 160-bit field, a 64-bit and a 32-bit one
static void host_arithmetic(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "arithmetic";
    program->members = 1u;
    program->in_limbs[0] = 8u;
    host_field(program, 160u, 0u);
    host_field(program, 64u, 160u);
    host_field(program, 32u, 224u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 2u, 0u, 0u);
    host_step(program, ENGINE_RECORD_PRODUCT, 0u, 1u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 3u, 2u, 0u);
    host_step(program, ENGINE_RECORD_DIFFERENCE, 0u, 3u, 0u);
    host_step(program, ENGINE_RECORD_ABSOLUTE, 5u, 0u, 0u);
    host_step(program, ENGINE_RECORD_COMPARE, 0u, 1u, 0u);
    host_step(program, ENGINE_RECORD_CONSTANT, 0x9E3779B9u, 0x7F4A7C15u, 0u);
    host_step(program, ENGINE_RECORD_PRODUCT, 4u, 8u, 0u);
    host_step(program, ENGINE_RECORD_CONSTANT, 3u, 0u, 0u);
    host_step(program, ENGINE_RECORD_LADDER, 2u, 10u, 0u);
    const unsigned int outputs[] = {3u, 4u, 5u, 6u, 7u, 9u, 11u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// the division over a divisor of at least 1 (a 64-bit field plus one): the quotient, remainder and gcd of a signed
// 192-bit numerator, and the exact quotient of the numerator times the divisor, less the numerator, which is zero
static void host_division(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "division";
    program->members = 1u;
    program->in_limbs[0] = 8u;
    host_field(program, 192u, 0u);
    host_field(program, 64u, 192u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 1u, 2u, 0u);
    host_step(program, ENGINE_RECORD_QUOTIENT, 0u, 3u, 0u);
    host_step(program, ENGINE_RECORD_REMAINDER, 0u, 3u, 0u);
    host_step(program, ENGINE_RECORD_GCD, 0u, 3u, 0u);
    host_step(program, ENGINE_RECORD_PRODUCT, 0u, 3u, 0u);
    host_step(program, ENGINE_RECORD_EXACT_QUOTIENT, 7u, 3u, 0u);
    host_step(program, ENGINE_RECORD_DIFFERENCE, 8u, 0u, 0u);
    const unsigned int outputs[] = {4u, 5u, 6u, 8u, 9u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// the xor and the and of two signed fields, 96 and 70 bits, and the wrap to 13, 64 and 4 bits
static void host_bitwise(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "bitwise";
    program->members = 1u;
    program->in_limbs[0] = 6u;
    host_field(program, 96u, 0u);
    host_field(program, 70u, 96u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_XOR, 0u, 1u, 0u);
    host_step(program, ENGINE_RECORD_AND, 0u, 1u, 0u);
    host_step(program, ENGINE_RECORD_WRAP, 2u, 13u, 0u);
    host_step(program, ENGINE_RECORD_WRAP, 3u, 64u, 0u);
    host_step(program, ENGINE_RECORD_WRAP, 0u, 4u, 0u);
    const unsigned int outputs[] = {2u, 3u, 4u, 5u, 6u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// the lane's number, a table read through its low 8 bits (40-bit entries), one through a 16-bit field's low 12 bits
// (20-bit entries), their sum, and the first table read again through the sum
static void host_tables(HostProgram *program, unsigned int *wide, unsigned int *narrow)
{
    memset(program, 0, sizeof(*program));
    program->name = "tables";
    program->members = 1u;
    program->in_limbs[0] = 1u;
    host_field(program, 16u, 0u);
    for (unsigned int entry = 0u; entry < 256u; entry += 1u)
    {
        wide[2u * entry] = host_random();
        wide[(2u * entry) + 1u] = host_random() & 0xFFu;
    }
    for (unsigned int entry = 0u; entry < 4096u; entry += 1u)
    {
        narrow[entry] = host_random() & 0xFFFFFu;
    }
    program->tables[0].index_bits = 8u;
    program->tables[0].out_bits = 40u;
    program->tables[0].values = wide;
    program->tables[1].index_bits = 12u;
    program->tables[1].out_bits = 20u;
    program->tables[1].values = narrow;
    program->table_count = 2u;
    host_step(program, ENGINE_RECORD_LANE, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_TABLE, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_TABLE, 2u, 1u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 1u, 3u, 0u);
    host_step(program, ENGINE_RECORD_TABLE, 4u, 0u, 0u);
    const unsigned int outputs[] = {0u, 1u, 3u, 4u, 5u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// two members read through an index: a 64-bit field of the first, a signed 90-bit field of the second, their product
// and the product less the second
static void host_members(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "members";
    program->members = 2u;
    program->in_limbs[0] = 2u;
    program->in_limbs[1] = 3u;
    host_field(program, 64u, 0u);
    host_field(program, 90u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 1u);
    host_step(program, ENGINE_RECORD_PRODUCT, 0u, 1u, 0u);
    host_step(program, ENGINE_RECORD_DIFFERENCE, 2u, 1u, 0u);
    const unsigned int outputs[] = {2u, 3u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// the linear forms' limit (keymath, KEYMATH_COEFFICIENT_MAX, 2^62): 2^62 added to itself, the sum added to itself,
// and the first sum times 3. The sums pass the limit: each is an atom of its own width, 64 and 65 bits, and the
// product 66; a sum formed past a signed word would give 2^64 a width of 1 bit
static void host_affine_limit(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "form limit";
    program->members = 1u;
    program->in_limbs[0] = 1u;
    host_step(program, ENGINE_RECORD_CONSTANT, 0u, 0x40000000u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 1u, 1u, 0u);
    host_step(program, ENGINE_RECORD_CONSTANT, 3u, 0u, 0u);
    host_step(program, ENGINE_RECORD_PRODUCT, 1u, 3u, 0u);
    const unsigned int outputs[] = {2u, 4u};
    program->output_count = (unsigned int)(sizeof(outputs) / sizeof(outputs[0]));
    memcpy(program->outputs, outputs, sizeof(outputs));
}

// the divisor taken bare, which errors once a lane's is zero: the division program's fields, the quotient alone
static void host_bare_divisor(HostProgram *program)
{
    memset(program, 0, sizeof(*program));
    program->name = "bare divisor";
    program->members = 1u;
    program->in_limbs[0] = 8u;
    host_field(program, 192u, 0u);
    host_field(program, 64u, 192u);
    host_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    host_step(program, ENGINE_RECORD_FIELD, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_QUOTIENT, 0u, 1u, 0u);
    program->outputs[0] = 2u;
    program->output_count = 1u;
}

// lane 17's divisor, bits 192 to 255 of the division program's atoms, set to zero
static void host_zero_divisor(unsigned int *atoms)
{
    atoms[(17u * 8u) + 6u] = 0u;
    atoms[(17u * 8u) + 7u] = 0u;
}

// the numerator divided exactly by the divisor plus one, which errors once a lane's does not divide
static void host_inexact(HostProgram *program, const HostProgram *bare)
{
    *program = *bare;
    program->name = "inexact";
    program->count = 2u;
    host_step(program, ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);
    host_step(program, ENGINE_RECORD_SUM, 1u, 2u, 0u);
    host_step(program, ENGINE_RECORD_EXACT_QUOTIENT, 0u, 3u, 0u);
    program->outputs[0] = 4u;
}

#endif
