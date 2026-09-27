// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's lane as VHDL held to the host oracle word for word (engine_table.md item 11(f), VHDL a
// language of the register lane). record_host_test's programs, drawn from the same stream in the same order, are
// imprinted, laid and run by cycle_record_run_host; each is written as VHDL by CycleEmitVhdl (emit/rulesets/vhdl.krs),
// analyzed and run by GHDL under record_vhdl_bench.vhd over a memory image laid as the device lays its launch, and its
// records compared with the host's word for word. Its lines give the same input digests as the host test's. A program
// whose lane calls the operator block is not held in VHDL yet, and is counted as not held, not as held or failed.
#include "record_programs.h"
#include "emit_vhdl.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <string>
#include <vector>

// the launch's words at address 0 of the memory image, before every array
#define VHDL_TEST_LAUNCH_WORDS 64u

static_assert(sizeof(CycleCompiledLaunch) <= (4u * VHDL_TEST_LAUNCH_WORDS), "vhdl test: the launch fits its words");

struct VhdlTally
{
    unsigned int checks;
    unsigned int failed;
    unsigned int not_held;
};

// where GHDL runs: the folder it analyzes into and runs in, and the bench's file
struct VhdlPlace
{
    std::string work;
    std::string bench;
};

static void vhdl_check(VhdlTally *tally, int held, const std::string &what)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what.c_str());
}

// `count` words laid at the end of the image; their byte address
static unsigned long long vhdl_lay(std::vector<unsigned int> &memory, const unsigned int *words, unsigned long long count)
{
    const unsigned long long address = 4ull * memory.size();
    memory.insert(memory.end(), words, words + count);
    return address;
}

// a 64-bit field of the launch, little-endian, at its byte offset
static void vhdl_wide(std::vector<unsigned int> &memory, size_t offset, unsigned long long value)
{
    memory[offset / 4u] = (unsigned int)(value & 0xFFFFFFFFull);
    memory[(offset / 4u) + 1u] = (unsigned int)(value >> 32u);
}

static int vhdl_write(const std::string &path, const std::string &text)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(text.data(), 1u, text.size(), file) == text.size();
    return (fclose(file) == 0) && written;
}

// the image and its line of places, as record_vhdl_bench.vhd reads them
static int vhdl_write_image(const std::string &path, const std::vector<unsigned int> &memory, unsigned long long lanes,
                            unsigned long long records, unsigned long long record_words, unsigned long long refused)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    fprintf(file, "%zu %llu %llu %llu %llu\n", memory.size(), lanes, records, record_words, refused);
    for (const unsigned int word : memory)
    {
        fprintf(file, "%08X\n", word);
    }
    return fclose(file) == 0;
}

// the refusals and the records' words record_vhdl_bench.vhd wrote; 0 where they cannot be read whole
static int vhdl_read(const std::string &path, unsigned long long words, unsigned int *refused,
                     std::vector<unsigned int> &records)
{
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return 0;
    }
    records.assign((size_t)words, 0u);
    int held = fscanf(file, "%u", refused) == 1;
    for (unsigned long long at = 0ull; held && (at < words); at += 1ull)
    {
        held = fscanf(file, "%x", &records[(size_t)at]) == 1;
    }
    fclose(file);
    return held;
}

// the program laid, run on the host, written as VHDL and run by GHDL over the same atoms; its line printed and its
// check made. `refuses` is 1 for a program the host must refuse: the lane as VHDL must then refuse a lane
static void vhdl_run(VhdlTally *tally, const VhdlPlace *place, const HostProgram *program, int reuse,
                     unsigned int *const *atoms, const unsigned long long *bodies, const unsigned int *index,
                     int refuses)
{
    const std::string name = std::string(program->name) + (reuse ? " (registers reused)" : "");
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        vhdl_check(tally, 0, name + " is laid");
        return;
    }
    const EngineRecordLayout *const layout = &loaded.layout;
    const unsigned long long record_words = (unsigned long long)HOST_TEST_LANES * layout->out_limbs;
    std::vector<unsigned int> host_records((size_t)record_words, 0u);
    CycleRecordHostRequest request;
    memset(&request, 0, sizeof(request));
    request.layout = layout;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        request.in[member] = atoms[member];
        request.bodies[member] = bodies[member];
    }
    request.index = index;
    request.count = HOST_TEST_LANES;
    request.out = host_records.data();
    request.error = &loaded.error;
    const long ran = cycle_record_run_host(&request);
    unsigned long long inputs = HOST_TEST_FNV_BASIS;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        inputs ^= host_digest(atoms[member], bodies[member] * layout->in_limbs[member]);
    }
    CycleEmitVhdl &emit = cycle_emit_vhdl();
    const CycleEmitTarget target = {0ull, 0, 0, 0, 0, ""};
    unsigned int places = 0u;
    unsigned int live = 0u;
    const std::string text =
        (emit.ruleset(1) != NULL) ? emit.program(layout, &target, std::string(), &places, &live) : std::string();
    if (text.empty() || (places != 0u))
    {
        printf("  %s: %u steps, not held in VHDL (%s)\n", name.c_str(), layout->steps,
               text.empty() ? "a step the lane does not hold, or its ruleset refused"
                            : "its lane calls the operator block, which is not written in VHDL yet");
        tally->not_held += 1u;
        host_free(&loaded);
        return;
    }
    // the image: the launch at 0, laid as CycleCompiledLaunch, then the members' atoms, the index, the tables, the
    // records and the refusals
    std::vector<unsigned int> memory(VHDL_TEST_LAUNCH_WORDS, 0u);
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        const unsigned long long address =
            vhdl_lay(memory, atoms[member], bodies[member] * layout->in_limbs[member]);
        vhdl_wide(memory, offsetof(CycleCompiledLaunch, in) + (8u * (size_t)member), address);
        vhdl_wide(memory, offsetof(CycleCompiledLaunch, bodies) + (8u * (size_t)member), bodies[member]);
    }
    if (index != NULL)
    {
        vhdl_wide(memory, offsetof(CycleCompiledLaunch, index),
                  vhdl_lay(memory, index, (unsigned long long)HOST_TEST_LANES * layout->members));
    }
    if (layout->table_word_count != 0ull)
    {
        vhdl_wide(memory, offsetof(CycleCompiledLaunch, tables),
                  vhdl_lay(memory, layout->table_values, layout->table_word_count));
    }
    const unsigned long long records = 4ull * memory.size();
    memory.resize(memory.size() + (size_t)record_words, 0u);
    const unsigned long long refused_at = 4ull * memory.size();
    memory.push_back(0u);
    vhdl_wide(memory, offsetof(CycleCompiledLaunch, out), records);
    vhdl_wide(memory, offsetof(CycleCompiledLaunch, refused), refused_at);
    vhdl_wide(memory, offsetof(CycleCompiledLaunch, count), HOST_TEST_LANES);
    const std::string records_path = place->work + "/records.txt";
    remove(records_path.c_str());
    const int written = vhdl_write(place->work + "/program.vhd", text)
                     && vhdl_write_image(place->work + "/memory.txt", memory, HOST_TEST_LANES, records, record_words,
                                         refused_at);
    const std::string command = "cd '" + place->work + "' && ghdl -a --std=08 program.vhd '" + place->bench
                              + "' > ghdl.log 2>&1 && ghdl --elab-run --std=08 record_vhdl_bench >> ghdl.log 2>&1";
    const int status = written ? system(command.c_str()) : -1;
    unsigned int refused = 0u;
    std::vector<unsigned int> vhdl_records;
    const int read = (status == 0) && vhdl_read(records_path, record_words, &refused, vhdl_records);
    if (read == 0)
    {
        printf("  %s: GHDL did not run the lane (status %d); its log begins:\n", name.c_str(), status);
        const std::string show = "head -20 '" + place->work + "/ghdl.log'";
        fflush(stdout);
        (void)system(show.c_str());
    }
    const int host_ran = ran == (long)HOST_TEST_LANES;
    printf("  %s: %u steps, %u out limbs, %zu lines of VHDL, inputs %016llx, records %016llx as VHDL, %016llx on the "
           "host, %u lanes refused as VHDL\n",
           name.c_str(), layout->steps, layout->out_limbs, (size_t)std::count(text.begin(), text.end(), '\n'), inputs,
           read ? host_digest(vhdl_records.data(), record_words) : 0ull,
           host_ran ? host_digest(host_records.data(), record_words) : 0ull, refused);
    if (refuses != 0)
    {
        vhdl_check(tally, read && !host_ran && (refused != 0u),
                   name + " as VHDL refuses a lane where the host refuses the run");
    }
    else
    {
        vhdl_check(tally, read && host_ran && (refused == 0u) && (vhdl_records == host_records),
                   name + " as VHDL writes the host's records word for word");
    }
    host_free(&loaded);
}

int main(int argc, char **argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "usage: record_vhdl_test <work folder> <record_vhdl_bench.vhd>\n");
        return 2;
    }
    const VhdlPlace place = {std::string(argv[1]), std::string(argv[2])};
    VhdlTally tally = {0u, 0u, 0u};
    printf("  record vhdl test: %u lanes a program, ANCHOR_EXACT_LIMBS %u\n", HOST_TEST_LANES,
           (unsigned int)ANCHOR_EXACT_LIMBS);
    HostProgram program;
    const unsigned long long one_body[1] = {HOST_TEST_LANES};

    // drawn as record_host_test draws them, in its order
    host_arithmetic(&program);
    unsigned int *atoms[2] = {host_atoms(program.in_limbs[0], HOST_TEST_LANES), NULL};
    vhdl_run(&tally, &place, &program, 0, atoms, one_body, NULL, 0);
    vhdl_run(&tally, &place, &program, 1, atoms, one_body, NULL, 0);
    free(atoms[0]);

    host_division(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    vhdl_run(&tally, &place, &program, 0, atoms, one_body, NULL, 0);
    HostProgram bare;
    host_bare_divisor(&bare);
    host_zero_divisor(atoms[0]);
    vhdl_run(&tally, &place, &bare, 0, atoms, one_body, NULL, 1);
    HostProgram inexact;
    host_inexact(&inexact, &bare);
    vhdl_run(&tally, &place, &inexact, 0, atoms, one_body, NULL, 1);
    free(atoms[0]);

    host_bitwise(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    vhdl_run(&tally, &place, &program, 0, atoms, one_body, NULL, 0);
    free(atoms[0]);

    unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
    unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    host_tables(&program, wide, narrow);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    vhdl_run(&tally, &place, &program, 0, atoms, one_body, NULL, 0);
    free(atoms[0]);
    free(wide);
    free(narrow);

    host_members(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_FIRST_BODIES);
    atoms[1] = host_atoms(program.in_limbs[1], HOST_TEST_SECOND_BODIES);
    const unsigned long long bodies[2] = {HOST_TEST_FIRST_BODIES, HOST_TEST_SECOND_BODIES};
    unsigned int *const index = (unsigned int *)malloc((size_t)HOST_TEST_LANES * 2u * sizeof(unsigned int));
    for (unsigned int lane = 0u; lane < HOST_TEST_LANES; lane += 1u)
    {
        index[2u * lane] = host_random() % HOST_TEST_FIRST_BODIES;
        index[(2u * lane) + 1u] = host_random() % HOST_TEST_SECOND_BODIES;
    }
    vhdl_run(&tally, &place, &program, 0, atoms, bodies, index, 0);
    printf("  index %016llx\n", host_digest(index, (unsigned long long)HOST_TEST_LANES * 2u));
    free(index);
    free(atoms[0]);
    free(atoms[1]);

    host_form_limit(&program);
    atoms[0] = (unsigned int *)calloc(HOST_TEST_LANES, sizeof(unsigned int));
    atoms[1] = NULL;
    vhdl_run(&tally, &place, &program, 0, atoms, one_body, NULL, 0);
    free(atoms[0]);

    printf("  record vhdl test: %u checks, %u failed, %u programs not held in VHDL\n", tally.checks, tally.failed,
           tally.not_held);
    return (tally.failed == 0u) ? 0 : 1;
}
