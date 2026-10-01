// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RECORD_IMAGE_H
#define RECORD_IMAGE_H

// The tests that run a language's lane off the device and hold it to the host oracle (record_vhdl_test.cpp,
// record_c_test.cpp): the programs drawn as record_host_test draws them, in its order, each handed to the test's own
// run; the memory image a lane runs over, laid out as the device lays out its launch; and the files a lane's bench
// reads the image from and writes its records to. It compiles as C++

#include "record_programs.h"
#include "target.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <string>
#include <vector>

// the launch's words at address 0 of the memory image, before every array
#define RECORD_IMAGE_LAUNCH_WORDS 64u

static_assert(sizeof(CycleCompiledLaunch) <= (4u * RECORD_IMAGE_LAUNCH_WORDS),
              "record image: the launch fits its words");

// the launch's number, which the program's block names as its owner
#define RECORD_IMAGE_LAUNCH_NUMBER 1ull

// the image: its words, each address in it a byte offset from its first word; the records' address and words, and the
// errors' address
struct RecordImage
{
    std::vector<unsigned int> memory;
    unsigned long long records;
    unsigned long long record_words;
    unsigned long long error;
};

// `count` words laid out at the end of the image; their byte address
static unsigned long long record_image_layout(std::vector<unsigned int> &memory, const unsigned int *words,
                                              unsigned long long count)
{
    const unsigned long long address = 4ull * memory.size();
    memory.insert(memory.end(), words, words + count);
    return address;
}

// a 64-bit field of the launch, little-endian, at its byte offset
static void record_image_wide(std::vector<unsigned int> &memory, size_t offset, unsigned long long value)
{
    memory[offset / 4u] = (unsigned int)(value & 0xFFFFFFFFull);
    memory[(offset / 4u) + 1u] = (unsigned int)(value >> 32u);
}

// the image of a program's HOST_TEST_LANES lanes: the launch at 0, laid out as CycleCompiledLaunch, then the members'
// atoms, the index, the tables, the records, the errors, the hot words and the program's block
static RecordImage record_image(const EngineRecordLayout *layout, unsigned int *const *atoms,
                                const unsigned long long *bodies, const unsigned int *index)
{
    RecordImage image = {std::vector<unsigned int>(RECORD_IMAGE_LAUNCH_WORDS, 0u), 0ull,
                         (unsigned long long)HOST_TEST_LANES * layout->out_limbs, 0ull};
    std::vector<unsigned int> &memory = image.memory;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        const unsigned long long address =
            record_image_layout(memory, atoms[member], bodies[member] * layout->in_limbs[member]);
        record_image_wide(memory, offsetof(CycleCompiledLaunch, in) + (8u * (size_t)member), address);
        record_image_wide(memory, offsetof(CycleCompiledLaunch, bodies) + (8u * (size_t)member), bodies[member]);
    }
    if (index != NULL)
    {
        record_image_wide(memory, offsetof(CycleCompiledLaunch, index),
                          record_image_layout(memory, index, (unsigned long long)HOST_TEST_LANES * layout->members));
    }
    if (layout->table_word_count != 0ull)
    {
        record_image_wide(memory, offsetof(CycleCompiledLaunch, tables),
                          record_image_layout(memory, layout->table_values, layout->table_word_count));
    }
    image.records = 4ull * memory.size();
    memory.resize(memory.size() + (size_t)image.record_words, 0u);
    image.error = 4ull * memory.size();
    memory.push_back(0u);
    // the hot words and the program's block, each at an address of whole 64-bit words: the next lane 0, and the block
    // owned by the launch's number and told to run, as the host lays them out before the first launch
    memory.resize(memory.size() + (memory.size() % 2u), 0u);
    const unsigned long long hot = 4ull * memory.size();
    memory.resize(memory.size() + (sizeof(CycleHot) / 4u), 0u);
    const unsigned long long block = 4ull * memory.size();
    memory.resize(memory.size() + (sizeof(EngineProgramBlock) / 4u), 0u);
    record_image_wide(memory, (size_t)block + offsetof(EngineProgramBlock, owner), RECORD_IMAGE_LAUNCH_NUMBER);
    record_image_wide(memory, (size_t)block + offsetof(EngineProgramBlock, command), ENGINE_PROGRAM_RUN);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, out), image.records);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, error), image.error);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, count), HOST_TEST_LANES);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, hot), hot);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, block), block);
    record_image_wide(memory, offsetof(CycleCompiledLaunch, launch_number), RECORD_IMAGE_LAUNCH_NUMBER);
    return image;
}

// the image and its line of places as a bench reads them: its words, the lanes, the records' address and words and the
// errors' address, then each word in hex
static int record_image_write(const std::string &path, const RecordImage *image)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    fprintf(file, "%zu %u %llu %llu %llu\n", image->memory.size(), HOST_TEST_LANES, image->records, image->record_words,
            image->error);
    for (const unsigned int word : image->memory)
    {
        fprintf(file, "%08X\n", word);
    }
    return fclose(file) == 0;
}

// the errors, the records' words and the clocks a bench wrote, the clocks 0 from a language that is not clocked; 0
// where they cannot be read whole
static int record_image_read(const std::string &path, const RecordImage *image, unsigned int *error,
                             std::vector<unsigned int> &records, unsigned long long *clocks)
{
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return 0;
    }
    records.assign((size_t)image->record_words, 0u);
    int passed = fscanf(file, "%u", error) == 1;
    for (unsigned long long at = 0ull; passed && (at < image->record_words); at += 1ull)
    {
        passed = fscanf(file, "%x", &records[(size_t)at]) == 1;
    }
    passed = passed && (fscanf(file, "%llu", clocks) == 1);
    fclose(file);
    return passed;
}

// a test's run of one program: the program, 1 where its registers are reused, its members' atoms and bodies, the
// index or NULL, and 1 where the host must error on it
typedef void (*RecordImageRun)(void *context, const HostProgram *program, int reuse, unsigned int *const *atoms,
                               const unsigned long long *bodies, const unsigned int *index, int errors);

// every program record_host_test runs, drawn as it draws them, in its order, each handed to `run`
static void record_image_programs(void *context, RecordImageRun run)
{
    HostProgram program;
    const unsigned long long one_body[1] = {HOST_TEST_LANES};

    host_arithmetic(&program);
    unsigned int *atoms[2] = {host_atoms(program.in_limbs[0], HOST_TEST_LANES), NULL};
    run(context, &program, 0, atoms, one_body, NULL, 0);
    run(context, &program, 1, atoms, one_body, NULL, 0);
    free(atoms[0]);

    host_division(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    run(context, &program, 0, atoms, one_body, NULL, 0);
    HostProgram bare;
    host_bare_divisor(&bare);
    host_zero_divisor(atoms[0]);
    run(context, &bare, 0, atoms, one_body, NULL, 1);
    HostProgram inexact;
    host_inexact(&inexact, &bare);
    run(context, &inexact, 0, atoms, one_body, NULL, 1);
    free(atoms[0]);

    host_bitwise(&program);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    run(context, &program, 0, atoms, one_body, NULL, 0);
    free(atoms[0]);

    unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
    unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    host_tables(&program, wide, narrow);
    atoms[0] = host_atoms(program.in_limbs[0], HOST_TEST_LANES);
    run(context, &program, 0, atoms, one_body, NULL, 0);
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
    run(context, &program, 0, atoms, bodies, index, 0);
    printf("  index %016llx\n", host_digest(index, (unsigned long long)HOST_TEST_LANES * 2u));
    free(index);
    free(atoms[0]);
    free(atoms[1]);

    host_affine_limit(&program);
    atoms[0] = (unsigned int *)calloc(HOST_TEST_LANES, sizeof(unsigned int));
    atoms[1] = NULL;
    run(context, &program, 0, atoms, one_body, NULL, 0);
    free(atoms[0]);
}

#endif
