// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's host oracle on any part (engine_table.md item 11(f) 6, a second target). Programs over every
// record operation are encoded (keymath), laid out (key_schedule) and run by cycle_record_run_host, the exact integer
// library's own steps, with no device and no CUDA toolchain. Each program's inputs come from one xorshift stream:
// every host draws the same atoms, and the test prints a digest of the inputs and of every output word: two parts
// whose lines match run the record machine word for word alike. The device's record tests hold the device to this
// same oracle on the x86 host. A part that matches x86 here matches the device too. It also holds that a laid-out
// program with its registers reused writes the records the unreused one does, and that a zero divisor and an inexact
// division error on the run.
#include "cycle.h"
#include "exact_integer.h"
#include "key_schedule.h"
#include "keymath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "record_programs.h"

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} HostResults;

static void host_check(HostResults *results, int passed, const char *what)
{
    results->checks += 1u;
    results->failed += passed ? 0u : 1u;
    printf("  %s %s\n", passed ? "ok  " : "FAIL", what);
}

// the program laid out and run over its members' atoms, with the index where one is given; its records' digest printed.
// 1 where it ran every lane, the records left in *records for the caller to free
static int host_run(HostResults *results, const HostProgram *program, int reuse, unsigned int *const *atoms,
                    const unsigned long long *bodies, const unsigned int *index, unsigned int **records)
{
    *records = NULL;
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        printf("  %s: not laid out, module %d site %u\n", program->name, (int)loaded.error.module, loaded.error.site);
        host_check(results, 0, program->name);
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
    const long ran = (out != NULL) ? cycle_record_run_host(&request) : CYCLE_ERROR;
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
    host_check(results, ran == (long)HOST_TEST_LANES, what);
    host_free(&loaded);
    *records = out;
    return ran == (long)HOST_TEST_LANES;
}

// a program the host must error on the atoms given: the whole run errors, a request error of the cycle module
static void host_error(HostResults *results, const HostProgram *program, const unsigned int *atoms, const char *what)
{
    HostLoaded loaded;
    int ok = host_load(program, 0, &loaded);
    unsigned int *const out =
        ok ? (unsigned int *)calloc((size_t)HOST_TEST_LANES * loaded.layout.out_limbs, sizeof(unsigned int)) : NULL;
    if (ok)
    {
        CycleRecordHostRequest request;
        memset(&request, 0, sizeof(request));
        request.layout = &loaded.layout;
        request.in[0] = atoms;
        request.bodies[0] = HOST_TEST_LANES;
        request.count = HOST_TEST_LANES;
        request.out = out;
        request.error = &loaded.error;
        ok = (out != NULL) && (cycle_record_run_host(&request) == CYCLE_ERROR) &&
             (loaded.error.kind == ENGINE_ERROR_REQUEST) && (loaded.error.module == ENGINE_MODULE_CYCLE);
        host_free(&loaded);
    }
    free(out);
    host_check(results, ok, what);
}

int main(void)
{
    HostResults results = {0u, 0u};
    printf("  record host test: %u lanes a program, ANCHOR_EXACT_LIMBS %u\n", HOST_TEST_LANES,
           (unsigned int)ANCHOR_EXACT_LIMBS);
    HostProgram program;
    const unsigned long long one_body[1] = {HOST_TEST_LANES};
    unsigned int *records = NULL;

    host_arithmetic(&program);
    unsigned int *atoms[2] = {host_atoms(program.in_limbs[0], HOST_TEST_LANES), NULL};
    int ran = host_run(&results, &program, 0, atoms, one_body, NULL, &records);
    unsigned int *reused = NULL;
    const int reran = host_run(&results, &program, 1, atoms, one_body, NULL, &reused);
    // both layouts write the same record width, the outputs being the same steps
    host_check(&results, ran && reran && (memcmp(records, reused, (size_t)HOST_TEST_LANES * sizeof(unsigned int)) == 0),
               "the reused registers write the records the unreused ones do");
    free(records);
    free(reused);
    free(atoms[0]);

    host_division(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&results, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    // the divisor taken bare errors once a lane's is zero; the numerator divided exactly by the divisor plus one
    // errors once a lane's does not divide
    HostProgram bare;
    host_bare_divisor(&bare);
    host_zero_divisor(atoms[0]);
    host_error(&results, &bare, atoms[0], "a zero divisor errors on the run");
    HostProgram inexact;
    host_inexact(&inexact, &bare);
    host_error(&results, &inexact, atoms[0], "an exact quotient that does not divide errors on the run");
    free(atoms[0]);

    host_bitwise(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&results, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    free(atoms[0]);

    unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
    unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    host_tables(&program, wide, narrow);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    ran = host_run(&results, &program, 0, atoms, one_body, NULL, &records);
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
    ran = (index != NULL) && host_run(&results, &program, 0, atoms, bodies, index, &records);
    printf("  index %016llx\n", (index != NULL) ? host_digest(index, (unsigned long long)HOST_TEST_LANES * 2u) : 0ull);
    (void)ran;
    free(records);
    free(index);
    free(atoms[0]);
    free(atoms[1]);

    // drawn last and from no stream: every digest above stays as it was
    host_affine_limit(&program);
    HostLoaded limit;
    const int load_ok = host_load(&program, 0, &limit);
    const unsigned int doubled_bits = load_ok ? limit.key.term[2].bits : 0u;
    const unsigned int tripled_bits = load_ok ? limit.key.term[4].bits : 0u;
    if (load_ok)
    {
        host_free(&limit);
    }
    printf("  form limit: 2^64 takes %u bits, 3 . 2^63 takes %u\n", doubled_bits, tripled_bits);
    host_check(&results, (doubled_bits >= 65u) && (tripled_bits >= 66u),
               "a sum past the linear forms' limit takes the bits its value needs");
    atoms[0] = (unsigned int *)calloc(HOST_TEST_LANES, sizeof(unsigned int));
    ran = (atoms[0] != NULL) && host_run(&results, &program, 0, atoms, one_body, NULL, &records);
    free(records);
    free(atoms[0]);

    printf("  record host test: %u checks, %u failed\n", results.checks, results.failed);
    return (results.failed == 0u) ? 0 : 1;
}
