// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's host oracle on any part (engine_table.md item 11(f) 6, a second target). Programs over every
// record operation are imprinted (keymath), laid (key_schedule) and run by cycle_record_run_host, the exact integer
// library's own steps, with no device and no CUDA toolchain. Each program's inputs come from one xorshift stream, so
// every host draws the same atoms, and the test prints a digest of the inputs and of every output word: two parts
// whose lines match run the record machine word for word alike. The device's record tests hold the device to this
// same oracle on the x86 host, so a part that matches x86 here matches the device too. It also holds that a laid
// program with its registers reused writes the records the unreused one does, and that a zero divisor and an inexact
// division refuse the run.
#include "cycle.h"
#include "exact_integer.h"
#include "keymath.h"
#include "key_schedule.h"

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

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} HostTally;

static unsigned long long s_host_state = 0x5EED0C0FFEE5ull;

static unsigned int host_random(void)
{
    s_host_state ^= s_host_state << 13u;
    s_host_state ^= s_host_state >> 7u;
    s_host_state ^= s_host_state << 17u;
    return (unsigned int)(s_host_state >> 16u);
}

static void host_check(HostTally *tally, int held, const char *what)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what);
}

// FNV-1a over each word's four bytes from the lowest, so the digest reads the words and not the part's byte order
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
    const KeymathRecordRequest imprint = {program->steps,        program->count,
                                          program->field_bits,   program->fields,
                                          program->members,      program->outputs,
                                          program->output_count, (program->table_count != 0u) ? program->tables : NULL,
                                          program->table_count,  &loaded->key,
                                          &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&loaded->key,     program->field_offset, program->fields, program->in_limbs,
                                          reuse,            &loaded->layout,       &loaded->error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
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

// the program laid and run over its members' atoms, with the index where one is given; its records' digest printed.
// 1 where it ran every lane, the records left in *records for the caller to free
static int host_run(HostTally *tally, const HostProgram *program, int reuse, unsigned int *const *atoms,
                    const unsigned long long *bodies, const unsigned int *index, unsigned int **records)
{
    *records = NULL;
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        printf("  %s: not laid, module %d site %u\n", program->name, (int)loaded.error.module, loaded.error.site);
        host_check(tally, 0, program->name);
        return 0;
    }
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const out = (unsigned int *)calloc((size_t)HOST_TEST_LANES * out_limbs, sizeof(unsigned int));
    CycleRecordHostRequest request;
    memset(&request, 0, sizeof(request));
    request.layout = &loaded.layout;
    for (unsigned int member = 0u; member < program->members; member += 1u)
    {
        request.in[member] = atoms[member];
        request.bodies[member] = bodies[member];
    }
    request.index = index;
    request.count = HOST_TEST_LANES;
    request.out = out;
    request.error = &loaded.error;
    const long ran = (out != NULL) ? cycle_record_run_host(&request) : CYCLE_REFUSED;
    unsigned long long inputs = HOST_TEST_FNV_BASIS;
    for (unsigned int member = 0u; member < program->members; member += 1u)
    {
        inputs ^= host_digest(atoms[member], bodies[member] * loaded.layout.in_limbs[member]);
    }
    printf("  %s%s: %u steps, %u out limbs, inputs %016llx, records %016llx\n", program->name,
           reuse ? " (registers reused)" : "", program->count, out_limbs, inputs,
           (ran == (long)HOST_TEST_LANES) ? host_digest(out, (unsigned long long)HOST_TEST_LANES * out_limbs) : 0ull);
    char what[160];
    snprintf(what, sizeof(what), "%s%s runs its %u lanes on the host", program->name,
             reuse ? " (registers reused)" : "", HOST_TEST_LANES);
    host_check(tally, ran == (long)HOST_TEST_LANES, what);
    host_free(&loaded);
    *records = out;
    return ran == (long)HOST_TEST_LANES;
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

// a program the host must refuse on the atoms given: the whole run refuses, a request error of the cycle module
static void host_refused(HostTally *tally, const HostProgram *program, const unsigned int *atoms, const char *what)
{
    HostLoaded loaded;
    int held = host_load(program, 0, &loaded);
    unsigned int *const out = held ? (unsigned int *)calloc((size_t)HOST_TEST_LANES * loaded.layout.out_limbs,
                                                             sizeof(unsigned int))
                                   : NULL;
    if (held)
    {
        CycleRecordHostRequest request;
        memset(&request, 0, sizeof(request));
        request.layout = &loaded.layout;
        request.in[0] = atoms;
        request.bodies[0] = HOST_TEST_LANES;
        request.count = HOST_TEST_LANES;
        request.out = out;
        request.error = &loaded.error;
        held = (out != NULL) && (cycle_record_run_host(&request) == CYCLE_REFUSED)
            && (loaded.error.kind == ENGINE_ERROR_REQUEST) && (loaded.error.module == ENGINE_MODULE_CYCLE);
        host_free(&loaded);
    }
    free(out);
    host_check(tally, held, what);
}

int main(void)
{
    HostTally tally = {0u, 0u};
    printf("  record host test: %u lanes a program, ANCHOR_EXACT_LIMBS %u\n", HOST_TEST_LANES,
           (unsigned int)ANCHOR_EXACT_LIMBS);
    HostProgram program;
    const unsigned long long one_body[1] = {HOST_TEST_LANES};
    unsigned int *records = NULL;

    host_arithmetic(&program);
    unsigned int *atoms[2] = {host_atoms(program.in_limbs[0], HOST_TEST_LANES), NULL};
    int ran = host_run(&tally, &program, 0, atoms, one_body, NULL, &records);
    unsigned int *reused = NULL;
    const int reran = host_run(&tally, &program, 1, atoms, one_body, NULL, &reused);
    // both layouts write the same record width, the outputs being the same steps
    host_check(&tally, ran && reran
                           && (memcmp(records, reused, (size_t)HOST_TEST_LANES * sizeof(unsigned int)) == 0),
               "the reused registers write the records the unreused ones do");
    free(records);
    free(reused);
    free(atoms[0]);

    host_division(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&tally, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    // the divisor taken bare refuses once a lane's is zero; the numerator divided exactly by the divisor plus one
    // refuses once a lane's does not divide
    HostProgram bare;
    memset(&bare, 0, sizeof(bare));
    bare.name = "bare divisor";
    bare.members = 1u;
    bare.in_limbs[0] = 8u;
    host_field(&bare, 192u, 0u);
    host_field(&bare, 64u, 192u);
    host_step(&bare, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    host_step(&bare, ENGINE_RECORD_FIELD, 1u, 0u, 0u);
    host_step(&bare, ENGINE_RECORD_QUOTIENT, 0u, 1u, 0u);
    bare.outputs[0] = 2u;
    bare.output_count = 1u;
    // lane 17's divisor, bits 192 to 255, set to zero
    atoms[0][(17u * 8u) + 6u] = 0u;
    atoms[0][(17u * 8u) + 7u] = 0u;
    host_refused(&tally, &bare, atoms[0], "a zero divisor refuses the run");
    HostProgram inexact = bare;
    inexact.name = "inexact";
    inexact.count = 2u;
    host_step(&inexact, ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);
    host_step(&inexact, ENGINE_RECORD_SUM, 1u, 2u, 0u);
    host_step(&inexact, ENGINE_RECORD_EXACT_QUOTIENT, 0u, 3u, 0u);
    inexact.outputs[0] = 4u;
    host_refused(&tally, &inexact, atoms[0], "an exact quotient that does not divide refuses the run");
    free(atoms[0]);

    host_bitwise(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&tally, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    free(atoms[0]);

    unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
    unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    host_tables(&program, wide, narrow);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&tally, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    free(atoms[0]);
    free(wide);
    free(narrow);

    host_members(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_FIRST_BODIES);
    atoms[1] = host_atoms(program.in_limbs[1], HOST_TEST_SECOND_BODIES);
    const unsigned long long bodies[2] = {HOST_TEST_FIRST_BODIES, HOST_TEST_SECOND_BODIES};
    unsigned int *const index = (unsigned int *)malloc((size_t)HOST_TEST_LANES * 2u * sizeof(unsigned int));
    for (unsigned int lane = 0u; (index != NULL) && (lane < HOST_TEST_LANES); lane += 1u)
    {
        index[2u * lane] = host_random() % HOST_TEST_FIRST_BODIES;
        index[(2u * lane) + 1u] = host_random() % HOST_TEST_SECOND_BODIES;
    }
    ran = (index != NULL) && host_run(&tally, &program, 0, atoms, bodies, index, &records);
    printf("  index %016llx\n", (index != NULL) ? host_digest(index, (unsigned long long)HOST_TEST_LANES * 2u) : 0ull);
    (void)ran;
    free(records);
    free(index);
    free(atoms[0]);
    free(atoms[1]);

    printf("  record host test: %u checks, %u failed\n", tally.checks, tally.failed);
    return (tally.failed == 0u) ? 0 : 1;
}
