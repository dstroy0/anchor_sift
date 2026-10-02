// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_fields.c: a form's fields found by running it on the part, not by reading a disassembler. An
// instruction is assembled through the machine file, put in place of the frame's IADD3, and run once for its answer;
// then each of its 104 operation bits is turned over one at a time and run again. A turned bit that changes the answer
// or stops the instruction running is a bit the part reads; one that changes nothing is control or unused.
//
// Which operand a read bit belongs to is matched, not guessed: the same instruction is run with each source operand's
// register number or number moved by a known amount, and a turned encoding bit belongs to the operand whose move
// gives the same answer. A read bit no operand's move explains is the operation's own, or a field the text does not
// print.
//
// Nothing is compiled and no disassembler is run. The cubins are written here and run by interface_sass_run, which
// loads each through the driver and answers over one case; a cubin the part refuses ends that runner, and this restarts
// it past the refusal.
//
//     interface_sass_probe_fields <pattern cubin> <frame text> <machine file> <folder> <instructions>
//
// The instructions file holds one instruction a line, as sass_krs_assemble writes the forms a ruleset uses. The tool
// writes <folder>/list.txt and the cubins it names; interface_sass_run runs that list and writes the answers, which a
// later pass reads back against the form's runs. The frame opens with its section's label, loads the case into
// registers and stores the answer's first word from R7.
#include "../../../../../../src/c/transpiler/cubin/cubin_write.h"
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/transpiler/interface/interface.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the most bytes a cubin, its code and a text take, and the most exits a code holds
#define FIELDS_CUBIN_BYTES 262144u
#define FIELDS_CODE_BYTES 65536u
#define FIELDS_TEXT_BYTES 65536u
#define FIELDS_EXITS 256u
// the operation bits of an instruction, 0 to 104, and the scheduler's at 105 and above, which this never turns
#define FIELDS_OPERATION_BITS 105u
// the registers a thread of every cubin declares, R0 to R254: a register field reaches every number the part holds
#define FIELDS_REGISTERS 255u

static SassMachine s_machine;
static unsigned char s_pattern[FIELDS_CUBIN_BYTES];
static unsigned char s_cubin[FIELDS_CUBIN_BYTES];
static unsigned char s_code[FIELDS_CODE_BYTES];
static char s_frame[FIELDS_TEXT_BYTES];
static char s_asking[FIELDS_TEXT_BYTES];
static unsigned int s_exits[FIELDS_EXITS];
static char s_kernel[128];
static unsigned long long s_pattern_size;

// `path` read whole into `bytes`, which holds `room`: the bytes read, 0 where it was not read
static unsigned long long fields_file_read(const char *path, unsigned char *bytes, unsigned long long room)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0ull;
    }
    const unsigned long long read = (unsigned long long)fread(bytes, 1u, (size_t)room, file);
    fclose(file);
    return read;
}

static int fields_file_write(const char *path, const unsigned char *bytes, unsigned long long size)
{
    FILE *const file = fopen(path, "wb");
    const int written = (file != NULL) && (fwrite(bytes, 1u, (size_t)size, file) == size);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

// the eight bytes at `bytes` read as one word, lowest first, and written back
static unsigned long long fields_word_read(const unsigned char *bytes)
{
    unsigned long long word = 0ull;
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        word |= (unsigned long long)bytes[at] << (8u * at);
    }
    return word;
}

static void fields_word_write(unsigned char *bytes, unsigned long long word)
{
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        bytes[at] = (unsigned char)(word >> (8u * at));
    }
}

// the kernel the frame opens with, `.text.<kernel>:`, into `kernel`: 1, or 0 where it opens otherwise
static int fields_kernel(const char *frame, char *kernel, size_t room)
{
    if (strncmp(frame, ".text.", 6u) != 0)
    {
        return 0;
    }
    const size_t length = strcspn(frame + 6, ":\r\n");
    return (frame[6u + length] == ':') && (snprintf(kernel, room, "%.*s", (int)length, frame + 6) < (int)room);
}

// the frame with its line that begins `IADD3 ` replaced by `lines`, into `text`: 1, or 0 where the frame holds no such
// line or `text` will not hold the whole
static int fields_splice(const char *frame, const char *lines, char *text, size_t room)
{
    const char *const line = strstr(frame, "\nIADD3 ");
    if (line == NULL)
    {
        return 0;
    }
    const char *const after = strchr(line + 1, '\n');
    const size_t before = (size_t)(line - frame) + 1u;
    return snprintf(text, room, "%.*s%s%s", (int)before, frame, lines, (after != NULL) ? after : "") < (int)room;
}

// the instruction of `code`, `count` of them, whose operation bits are `low` and `high`'s: its number, or `count`
// where none is or more than one is. The scheduler's bits, 105 and above, are left out of the match
static unsigned int fields_find(const unsigned char *code, unsigned int count, unsigned long long low,
                                unsigned long long high)
{
    const unsigned long long mask = (1ull << (FIELDS_OPERATION_BITS - 64u)) - 1ull;
    unsigned int found = count;
    unsigned int matches = 0u;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        const unsigned long long one = fields_word_read(&code[16u * number]);
        const unsigned long long two = fields_word_read(&code[(16u * number) + 8u]);
        if ((one == low) && ((two & mask) == (high & mask)))
        {
            found = number;
            matches += 1u;
        }
    }
    return (matches == 1u) ? found : count;
}

// `code` of `count` instructions, with the instruction at `place` turned at bit `bit` where `bit` is under 128, laid
// into a cubin and written to `path`: 1, or 0 with the reason printed. A bit of 128 writes the code as it stands
static int fields_cubin(const unsigned char *code, unsigned int count, unsigned int place, unsigned int bit,
                        const char *path)
{
    static unsigned char s_turned[FIELDS_CODE_BYTES];
    const unsigned long long code_size = 16ull * count;
    memcpy(s_turned, code, (size_t)code_size);
    if (bit < 128u)
    {
        const unsigned int at = (16u * place) + ((bit < 64u) ? 0u : 8u);
        unsigned long long word = fields_word_read(&s_turned[at]);
        word ^= 1ull << (bit % 64u);
        fields_word_write(&s_turned[at], word);
    }
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = s_pattern_size;
    written.kernel = s_kernel;
    written.code = s_turned;
    written.code_size = code_size;
    written.registers = FIELDS_REGISTERS;
    written.exit_count = cubin_exits_find(s_turned, code_size, sass_exit_encoding(&s_machine), s_exits, FIELDS_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size) || !fields_file_write(path, s_cubin, size))
    {
        printf("  %s was not written\n", path);
        return 0;
    }
    return 1;
}

// the lines a form is run in: the instruction `one` with the result in R8 and its reads R0 and R6, R8 stored as the
// answer's first word. R6 is set to the case's second word first, which the frame leaves in R7
#define FIELDS_LINES_HEAD "IMAD.MOV.U32 R6, RZ, RZ, R7\n"
#define FIELDS_LINES_TAIL "\nIMAD.MOV.U32 R7, RZ, RZ, R8\nSTG.E term[UR4][R4.64], R7"

int main(int count, char **words)
{
    if (count != 6)
    {
        fprintf(stderr,
                "interface_sass_probe_fields <pattern cubin> <frame text> <machine file> <folder> <instructions>\n");
        return 2;
    }
    const char *const folder = words[4];
    s_pattern_size = fields_file_read(words[1], s_pattern, sizeof(s_pattern));
    const unsigned long long frame_size = fields_file_read(words[2], (unsigned char *)s_frame, sizeof(s_frame) - 1u);
    s_frame[frame_size] = '\0';
    if ((s_pattern_size == 0ull) || (frame_size == 0ull) || !fields_kernel(s_frame, s_kernel, sizeof(s_kernel)))
    {
        fprintf(stderr, "the pattern cubin %s or the frame %s did not read\n", words[1], words[2]);
        return 2;
    }
    if (!sass_machine_read(&s_machine, words[3]))
    {
        fprintf(stderr, "the machine file %s did not read\n", words[3]);
        return 2;
    }
    FILE *const instructions = fopen(words[5], "rb");
    if (instructions == NULL)
    {
        fprintf(stderr, "the instructions %s did not read\n", words[5]);
        return 2;
    }
    // step one: the first instruction turned bit by bit into cubins and a list, which interface_sass_run runs
    char line[512];
    while (fgets(line, sizeof(line), instructions) != NULL)
    {
        line[strcspn(line, "\r\n")] = '\0';
        const char *walk = line + strspn(line, " \t");
        if ((*walk == '\0') || (strncmp(walk, "IADD3 R8", 8u) == 0))
        {
            continue;
        }
        char lines[512];
        snprintf(lines, sizeof(lines), FIELDS_LINES_HEAD "%s" FIELDS_LINES_TAIL, walk);
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        const unsigned int assembled = fields_splice(s_frame, lines, s_asking, sizeof(s_asking))
                                           ? sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code,
                                                                 sizeof(s_code))
                                           : 0u;
        const int alone =
            (assembled != 0u) && sass_assemble(&s_machine, walk, 0ull, 0ull, SASS_CONTROL_SAFE, &low, &high);
        const unsigned int place = alone ? fields_find(s_code, assembled, low, high) : assembled;
        if (place == assembled)
        {
            printf("skip %s: did not assemble or was not found once\n", walk);
            continue;
        }
        char path[1024];
        snprintf(path, sizeof(path), "%s/list.txt", folder);
        FILE *const made = fopen(path, "wb");
        // the baseline first, its bit 128 turning nothing, then one cubin an operation bit
        for (unsigned int bit = 0u; bit <= FIELDS_OPERATION_BITS; bit += 1u)
        {
            const unsigned int turned = (bit == 0u) ? 128u : (bit - 1u);
            char cubin[1024];
            snprintf(cubin, sizeof(cubin), "%s/bit_%03u.cubin", folder, bit);
            if (fields_cubin(s_code, assembled, place, turned, cubin) && (made != NULL))
            {
                fprintf(made, "%s %s\n", cubin, s_kernel);
            }
        }
        if (made != NULL)
        {
            fclose(made);
        }
        printf("wrote %u cubins for %s to %s\n", FIELDS_OPERATION_BITS + 1u, walk, path);
        break;
    }
    fclose(instructions);
    return 0;
}
