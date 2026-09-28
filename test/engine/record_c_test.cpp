// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's lane as C source held to the host oracle word for word, off the device (engine_table.md item
// 11(f), C a language of the register lane). record_host_test's programs, drawn from the same stream in the same order
// (record_image.h), are imprinted, laid and run by cycle_record_run_host; each is written as C by EmitSource
// (emit/rulesets/c.krs) into one translation unit with a host shim ahead of it, which writes what NVRTC gives a
// device's C (__device__, __shared__, threadIdx, blockDim, atomicAdd) for one thread, and a bench after it, which
// reads the memory image, turns its byte offsets into the host's addresses, runs every lane and writes the refusals and
// the records. The host's C++ compiler builds it and it runs in a work folder, and its records are compared with the
// host's word for word. Its lines give the same input digests as the host test's. Each lane of at most
// RECORD_C_TEXT_BYTES_MOST bytes is written again as the device writes it, on the host: the core's forms laid as the
// text program's records and written by the host oracle (emit_text.h), held to the emitter's text byte for byte.
#include "record_image.h"
#include "emit_source.h"
#include "emit_text.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <string>
#include <vector>

// the longest lane the text program writes on the host oracle here: a lane a byte, each a few hundred steps
#define RECORD_C_TEXT_BYTES_MOST 32768u

// the checks made and failed, and the programs the emitter did not write; where the test runs, and the compiler that
// builds each program
struct CTally
{
    unsigned int checks;
    unsigned int failed;
    unsigned int not_held;
    std::string work;
    std::string compiler;
};

static void c_check(CTally *tally, int held, const std::string &what)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what.c_str());
}

// what NVRTC gives a device's C, written for one thread on the host, and the launch as the prelude lays it. The
// program's resident kernel (c.krs, program_unit) compiles against it and is not run: the bench runs the lanes
static const char s_c_shim[] = "#include <stdio.h>\n"
                               "#include <stdlib.h>\n"
                               "\n"
                               "typedef unsigned int u32;\n"
                               "typedef unsigned long long u64;\n"
                               "typedef signed char s8;\n"
                               "struct CycleHot\n"
                               "{\n"
                               "    u64 next_lane;\n"
                               "    u64 launch_start;\n"
                               "    u64 finished;\n"
                               "    u64 checkins;\n"
                               "};\n"
                               "struct CycleCompiledLaunch\n"
                               "{\n"
                               "    const u32 *in[3];\n"
                               "    const u32 *index;\n"
                               "    const u32 *tables;\n"
                               "    u32 *out;\n"
                               "    u32 *refused;\n"
                               "    u64 bodies[3];\n"
                               "    u64 count;\n"
                               "    CycleHot *hot;\n"
                               "    u64 *block;\n"
                               "    u64 ttl;\n"
                               "    u64 checkin_every;\n"
                               "    u64 launch_number;\n"
                               "    u64 places;\n"
                               "};\n"
                               "#define __device__\n"
                               "#define __shared__\n"
                               "#define __global__\n"
                               "#define __forceinline__ inline\n"
                               "#define __launch_bounds__(threads_)\n"
                               "static const struct\n"
                               "{\n"
                               "    u32 x;\n"
                               "} threadIdx = {0u}, blockDim = {1u}, gridDim = {1u};\n"
                               "static u32 atomicAdd(u32 *const at, const u32 value)\n"
                               "{\n"
                               "    const u32 held = *at;\n"
                               "    *at = held + value;\n"
                               "    return held;\n"
                               "}\n"
                               "static u64 atomicAdd(u64 *const at, const u64 value)\n"
                               "{\n"
                               "    const u64 held = *at;\n"
                               "    *at = held + value;\n"
                               "    return held;\n"
                               "}\n"
                               "static u64 atomicCAS(u64 *const at, const u64 compared, const u64 value)\n"
                               "{\n"
                               "    const u64 held = *at;\n"
                               "    *at = (held == compared) ? value : held;\n"
                               "    return held;\n"
                               "}\n"
                               "static void __syncthreads(void)\n"
                               "{\n"
                               "}\n"
                               "static void __threadfence(void)\n"
                               "{\n"
                               "}\n";

// the bench after the lane: the image read from memory.txt, the launch's addresses moved from byte offsets to the
// host's, which an address of 0 is not, every lane run, and the refusals, the records and a clock count of 0 written to
// records.txt. `places` is the lane's in shared memory, a word and a sign byte each
static std::string c_bench(unsigned int places)
{
    const unsigned int words = places + ((places + 3u) / 4u) + 1u;
    std::string text = "\nu32 cycle_words[" + std::to_string(words) + "];\n";
    text += "\nint main(void)\n{\n";
    text += "    FILE *const given = fopen(\"memory.txt\", \"rb\");\n";
    text += "    unsigned long long image_words = 0ull;\n";
    text += "    unsigned long long lanes = 0ull;\n";
    text += "    unsigned long long records = 0ull;\n";
    text += "    unsigned long long record_words = 0ull;\n";
    text += "    unsigned long long refused = 0ull;\n";
    text += "    if ((given == NULL) || (fscanf(given, \"%llu %llu %llu %llu %llu\", &image_words, &lanes, &records, "
            "&record_words, &refused) != 5))\n";
    text += "    {\n        return 2;\n    }\n";
    text += "    u32 *const memory = (u32 *)calloc((size_t)image_words + 2u, sizeof(u32));\n";
    text += "    for (unsigned long long at = 0ull; at < image_words; at += 1ull)\n";
    text += "    {\n        if (fscanf(given, \"%x\", &memory[at]) != 1)\n        {\n            return 2;\n        }\n    }\n";
    text += "    fclose(given);\n";
    text += "    const u64 base = (u64)memory;\n";
    const size_t addresses[] = {offsetof(CycleCompiledLaunch, in), offsetof(CycleCompiledLaunch, in) + 8u,
                                offsetof(CycleCompiledLaunch, in) + 16u, offsetof(CycleCompiledLaunch, index),
                                offsetof(CycleCompiledLaunch, tables), offsetof(CycleCompiledLaunch, out),
                                offsetof(CycleCompiledLaunch, refused)};
    for (const size_t address : addresses)
    {
        text += "    if (*(u64 *)((char *)memory + " + std::to_string(address) + "u) != 0ull)\n";
        text += "    {\n        *(u64 *)((char *)memory + " + std::to_string(address) + "u) += base;\n    }\n";
    }
    text += "    for (u64 lane = 0ull; lane < lanes; lane += 1ull)\n";
    text += "    {\n        cycle_lane((const CycleCompiledLaunch *)memory, lane);\n    }\n";
    text += "    FILE *const written = fopen(\"records.txt\", \"wb\");\n";
    text += "    fprintf(written, \"%u\\n\", memory[refused / 4ull]);\n";
    text += "    for (unsigned long long at = 0ull; at < record_words; at += 1ull)\n";
    text += "    {\n        fprintf(written, \"%08X\\n\", memory[(records / 4ull) + at]);\n    }\n";
    text += "    fprintf(written, \"0\\n\");\n";
    text += "    return (fclose(written) == 0) ? 0 : 1;\n}\n";
    return text;
}

static int c_write(const std::string &path, const std::string &text)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(text.data(), 1u, text.size(), file) == text.size();
    return (fclose(file) == 0) && written;
}

// the program laid, run on the host, written as C, built and run over the same atoms; its line printed and its check
// made. `refuses` is 1 for a program the host must refuse: the lane as C must then refuse a lane
static void c_run(void *context, const HostProgram *program, int reuse, unsigned int *const *atoms,
                  const unsigned long long *bodies, const unsigned int *index, int refuses)
{
    CTally *const tally = (CTally *)context;
    const std::string name = std::string(program->name) + (reuse ? " (registers reused)" : "");
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        c_check(tally, 0, name + " is laid");
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
    EmitSource &emit = emit_source();
    const EmitTarget target = {0ull, 0, 0, 0, 0, ""};
    unsigned int places = 0u;
    unsigned int live = 0u;
    const std::string lane =
        (emit.ruleset(1) != NULL) ? emit.program(layout, &target, std::string(s_c_shim), &places, &live) : std::string();
    if (lane.empty())
    {
        printf("  %s: %u steps, not held in C (a step the lane does not hold, or its ruleset refused)\n", name.c_str(),
               layout->steps);
        tally->not_held += 1u;
        host_free(&loaded);
        return;
    }
    // the lane as the device writes it, on the host: the core's forms laid as the text program's records by the
    // functions the device runs, and written by the host oracle (emit_text.h)
    if (lane.size() <= RECORD_C_TEXT_BYTES_MOST)
    {
        std::vector<EmitCoreItem> items;
        unsigned int item_places = 0u;
        EmitTextRuleset text_rules{};
        std::string refused;
        std::string from_items;
        const int decided = emit.decided(layout, &item_places, &items);
        const int laid =
            decided && emit_text_ruleset_lay(emit.ruleset(0), &target, std::string(s_c_shim), &text_rules, &refused);
        const int ran = laid && emit_text_host(&text_rules, items, &from_items, &refused);
        if (laid)
        {
            emit_text_ruleset_release(&text_rules);
        }
        if (ran == 0)
        {
            printf("  %s: the text program did not write the lane (%s)\n", name.c_str(),
                   decided ? refused.c_str() : "the core's forms were not decided");
        }
        c_check(tally, ran && (from_items == lane) && (item_places == places),
                name + " written from the core's forms by the text program is the emitter's text");
    }
    const RecordImage image = record_image(layout, atoms, bodies, index);
    const std::string records_path = tally->work + "/records.txt";
    remove(records_path.c_str());
    const int written = c_write(tally->work + "/program.cpp", lane + c_bench(places))
                     && record_image_write(tally->work + "/memory.txt", &image);
    const std::string command = "cd '" + tally->work + "' && " + tally->compiler
                              + " -std=c++17 -O1 -Wall -Wextra -Wno-unused-variable -Wno-unused-but-set-variable "
                                "-Wno-unused-label -Wno-unused-function program.cpp -o program > build.log 2>&1 && "
                                "./program > run.log 2>&1";
    const int status = written ? system(command.c_str()) : -1;
    unsigned int refused = 0u;
    unsigned long long clocks = 0ull;
    std::vector<unsigned int> records;
    const int read = (status == 0) && record_image_read(records_path, &image, &refused, records, &clocks);
    if (read == 0)
    {
        printf("  %s: the lane as C did not build or run (status %d); its logs begin:\n", name.c_str(), status);
        const std::string show = "head -30 '" + tally->work + "/build.log' '" + tally->work + "/run.log'";
        fflush(stdout);
        const int shown = system(show.c_str());
        printf("  (the logs' head exited %d)\n", shown);
    }
    const int host_ran = ran == (long)HOST_TEST_LANES;
    printf("  %s: %u steps, %u out limbs, %zu lines of C, %u places, inputs %016llx, records %016llx as C, %016llx on "
           "the host, %u lanes refused as C\n",
           name.c_str(), layout->steps, layout->out_limbs, (size_t)std::count(lane.begin(), lane.end(), '\n'), places,
           inputs, read ? host_digest(records.data(), record_words) : 0ull,
           host_ran ? host_digest(host_records.data(), record_words) : 0ull, refused);
    if (refuses != 0)
    {
        c_check(tally, read && !host_ran && (refused != 0u), name + " as C refuses a lane where the host refuses the run");
    }
    else
    {
        c_check(tally, read && host_ran && (refused == 0u) && (records == host_records),
                name + " as C writes the host's records word for word");
    }
    host_free(&loaded);
}

int main(int argc, char **argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "usage: record_c_test <work folder> <C++ compiler>\n");
        return 2;
    }
    CTally tally = {0u, 0u, 0u, std::string(argv[1]), std::string(argv[2])};
    printf("  record c test: %u lanes a program, ANCHOR_EXACT_LIMBS %u, built by %s\n", HOST_TEST_LANES,
           (unsigned int)ANCHOR_EXACT_LIMBS, argv[2]);
    record_image_programs(&tally, c_run);
    printf("  record c test: %u checks, %u failed, %u programs not held in C\n", tally.checks, tally.failed,
           tally.not_held);
    return (tally.failed == 0u) ? 0 : 1;
}
