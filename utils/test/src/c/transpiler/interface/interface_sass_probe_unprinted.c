// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_unprinted.c: bits the disassembler does not print, asked of the part. A question is a few
// instructions put in place of the frame's IADD3, one of them the instruction whose bits are turned. That instruction
// is assembled through the machine file, every value of the field is written into its encoding in turn, and each
// encoding is run on the part over one case. What the part answers for each value is kept, against the answer the
// printed text says. A value that answers as printed leaves the field without effect on this question; one that
// answers otherwise, or does not run, is the part reading the field.
//
// No disassembler is asked. The pattern cubin, the frame's text and the runner are an earlier run's. The runner
// loads a cubin and runs its kernel over one case of eight words.
//
//     interface_sass_probe_unprinted <runner> <pattern cubin> <frame text> <machine file> <folder> <record>
//
// The frame's text opens with its section's label, `.text.<kernel>:`, which names the kernel the cubin is written
// into. The frame loads the case's first two words into R0 and R7 and stores R7 as the first word of the answer.
#include "../../../../../../src/c/transpiler/cubin/cubin_write.h"
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/transpiler/interface/interface.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the most bytes a cubin, its code, a text and a run's output take
#define UNPRINTED_CUBIN_BYTES 262144u
#define UNPRINTED_CODE_BYTES 65536u
#define UNPRINTED_TEXT_BYTES 65536u
#define UNPRINTED_OUTPUT_BYTES 65536u
#define UNPRINTED_EXITS 256u
// a run's limit: one load and one launch, far under a second, and a turned encoding that leaves the part waiting
// is ended here and read as not run
#define UNPRINTED_LIMIT 10000000ull
// the widest field turned, and the most bits a question holds fixed beside it
#define UNPRINTED_FIELD_MOST 6u
#define UNPRINTED_FIXED 2u
// the bits of the high word that are the operation's, 64 to 104, and not the scheduler's
#define UNPRINTED_OPERATION_HIGH 0x1ffffffffffull

// bits a question holds at one value while the field is turned
typedef struct
{
    unsigned int first;
    unsigned int bits;
    unsigned long long value;
} UnprintedFixed;

// one question: the lines put in place of the frame's IADD3, the one among them whose bits are turned, the field
// turned, the bits held beside it, and the word the printed text says the part answers
typedef struct
{
    const char *lines;
    const char *turned;
    unsigned int first;
    unsigned int bits;
    UnprintedFixed fixed[UNPRINTED_FIXED];
    unsigned int answer;
} UnprintedQuestion;

// P1 is set true and P2 false before every question that reads a predicate, so that a field naming one reads a value
// known on each side
#define UNPRINTED_PREDICATES "ISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, RZ, RZ, PT\n"

// the load of the case's first word and the store of R0 into the answer's third word, each through the descriptor
// register the frame loaded
#define UNPRINTED_LOAD "LDG.E.CONSTANT R7, term[UR4][R2.64]"
#define UNPRINTED_STORE "STG.E term[UR4][R4.64+0x8], R0"

// every predicate from P0 to P6 set false, and every one set true
#define UNPRINTED_FALSE                                                                                                \
    "ISETP.NE.U32.AND P0, PT, RZ, RZ, PT\nISETP.NE.U32.AND P1, PT, RZ, RZ, PT\nISETP.NE.U32.AND P2, PT, RZ, RZ, PT\n"  \
    "ISETP.NE.U32.AND P3, PT, RZ, RZ, PT\nISETP.NE.U32.AND P4, PT, RZ, RZ, PT\nISETP.NE.U32.AND P5, PT, RZ, RZ, PT\n"  \
    "ISETP.NE.U32.AND P6, PT, RZ, RZ, PT\n"
#define UNPRINTED_TRUE                                                                                                 \
    "ISETP.NE.U32.AND P0, PT, R0, RZ, PT\nISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, R0, RZ, PT\n"  \
    "ISETP.NE.U32.AND P3, PT, R0, RZ, PT\nISETP.NE.U32.AND P4, PT, R0, RZ, PT\nISETP.NE.U32.AND P5, PT, R0, RZ, PT\n"  \
    "ISETP.NE.U32.AND P6, PT, R0, RZ, PT\n"

// The questions of the machine file's open item. The case is 0xb and 0x7, and R2 holds the case's address, R4 the
// answer's, UR4 the memory descriptor the frame loaded from c[0x0][0x118].
static const UnprintedQuestion s_questions[] = {
    // IMAD's carry-in predicate, which IMAD reads as IMAD.X and prints nowhere else
    {UNPRINTED_PREDICATES "IMAD.IADD R7, R0, 0x1, R7", "IMAD.IADD R7, R0, 0x1, R7", 87u, 4u, {{0u, 0u, 0ull}},
     0x00000012u},
    {UNPRINTED_PREDICATES "IMAD.IADD R7, R0, 0x1, -R7", "IMAD.IADD R7, R0, 0x1, -R7", 87u, 4u, {{0u, 0u, 0ull}},
     0x00000004u},
    // ISETP's predicate beside its printed ones, which ISETP reads as .EX, asked where the comparison holds and where
    // it does not
    {UNPRINTED_PREDICATES "ISETP.GE.U32.AND P0, PT, R0, R7, PT\nSEL R7, R0, RZ, P0",
     "ISETP.GE.U32.AND P0, PT, R0, R7, PT", 68u, 4u, {{0u, 0u, 0ull}}, 0x0000000bu},
    {UNPRINTED_PREDICATES "ISETP.GE.U32.AND P0, PT, R7, R0, PT\nSEL R7, R0, RZ, P0",
     "ISETP.GE.U32.AND P0, PT, R7, R0, PT", 68u, 4u, {{0u, 0u, 0ull}}, 0x00000000u},
    // the load's predicate at 64 to 67, its number inverted at 64 to 66 and bit 67 negating it, asked with every
    // predicate false and then with every predicate true
    {UNPRINTED_FALSE UNPRINTED_LOAD, UNPRINTED_LOAD, 64u, 4u, {{0u, 0u, 0ull}}, 0x0000000bu},
    {UNPRINTED_TRUE UNPRINTED_LOAD, UNPRINTED_LOAD, 64u, 4u, {{0u, 0u, 0ull}}, 0x0000000bu},
    // the load's predicate printed, each assembled into the field at 64 and run as written: P1 is true and P2 false
    {UNPRINTED_PREDICATES UNPRINTED_LOAD ", P1", UNPRINTED_LOAD ", P1", 0u, 0u, {{0u, 0u, 0ull}}, 0x0000000bu},
    {UNPRINTED_PREDICATES UNPRINTED_LOAD ", P2", UNPRINTED_LOAD ", P2", 0u, 0u, {{0u, 0u, 0ull}}, 0x00000000u},
    {UNPRINTED_PREDICATES UNPRINTED_LOAD ", !P1", UNPRINTED_LOAD ", !P1", 0u, 0u, {{0u, 0u, 0ull}}, 0x00000000u},
    {UNPRINTED_PREDICATES UNPRINTED_LOAD ", !P2", UNPRINTED_LOAD ", !P2", 0u, 0u, {{0u, 0u, 0ull}}, 0x0000000bu},
    {UNPRINTED_PREDICATES UNPRINTED_LOAD ", !PT", UNPRINTED_LOAD ", !PT", 0u, 0u, {{0u, 0u, 0ull}}, 0x00000000u},
    // the load's descriptor register, with bit 101 clear and with it set
    {UNPRINTED_LOAD, UNPRINTED_LOAD, 32u, 6u, {{101u, 1u, 0ull}}, 0x0000000bu},
    {UNPRINTED_LOAD, UNPRINTED_LOAD, 32u, 6u, {{101u, 1u, 1ull}}, 0x0000000bu},
    // the two bits past the load's descriptor register
    {UNPRINTED_LOAD, UNPRINTED_LOAD, 38u, 2u, {{0u, 0u, 0ull}}, 0x0000000bu},
    // the store's descriptor register with bit 101 clear, and the two bits past it, read back through a load
    {UNPRINTED_STORE "\nLDG.E.CONSTANT R7, term[UR4][R4.64+0x8]", UNPRINTED_STORE, 64u, 6u, {{101u, 1u, 0ull}},
     0x0000000bu},
    {UNPRINTED_STORE "\nLDG.E.CONSTANT R7, term[UR4][R4.64+0x8]", UNPRINTED_STORE, 70u, 2u, {{0u, 0u, 0ull}},
     0x0000000bu},
};

static SassMachine s_machine;
static unsigned char s_pattern[UNPRINTED_CUBIN_BYTES];
static unsigned char s_cubin[UNPRINTED_CUBIN_BYTES];
static unsigned char s_code[UNPRINTED_CODE_BYTES];
static unsigned char s_turned[UNPRINTED_CODE_BYTES];
static char s_frame[UNPRINTED_TEXT_BYTES];
static char s_asking[UNPRINTED_TEXT_BYTES];
static char s_output[UNPRINTED_OUTPUT_BYTES];
static unsigned int s_exits[UNPRINTED_EXITS];

// `path` read whole into `bytes`, which holds `room` of them: how many were read, 0 where the file was not read
static unsigned long long unprinted_file_read(const char *path, unsigned char *bytes, unsigned long long room)
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

static int unprinted_file_write(const char *path, const unsigned char *bytes, unsigned long long size)
{
    FILE *const file = fopen(path, "wb");
    const int written = (file != NULL) && (fwrite(bytes, 1u, (size_t)size, file) == size);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

// `bits` bits of `value` written into the encoding at `first`, the two words taken as one of 128 bits
static void unprinted_bits_write(unsigned long long *low, unsigned long long *high, unsigned int first,
                                 unsigned int bits, unsigned long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int at = first + bit;
        unsigned long long *const word = (at < 64u) ? low : high;
        const unsigned long long mask = 1ull << (at % 64u);
        *word = ((value >> bit) & 1ull) ? (*word | mask) : (*word & ~mask);
    }
}

// `bits` bits of the encoding read from `first`
static unsigned long long unprinted_bits_read(unsigned long long low, unsigned long long high, unsigned int first,
                                              unsigned int bits)
{
    unsigned long long value = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int at = first + bit;
        const unsigned long long word = (at < 64u) ? low : high;
        value |= ((word >> (at % 64u)) & 1ull) << bit;
    }
    return value;
}

// the eight bytes at `bytes` as one word, the lowest first
static unsigned long long unprinted_word_read(const unsigned char *bytes)
{
    unsigned long long word = 0ull;
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        word |= (unsigned long long)bytes[at] << (8u * at);
    }
    return word;
}

static void unprinted_word_write(unsigned char *bytes, unsigned long long word)
{
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        // each byte is the word's next eight bits, which a byte holds
        bytes[at] = (unsigned char)(word >> (8u * at));
    }
}

// `value` written as `bits` binary digits, the highest first, into `text`
static void unprinted_binary(unsigned long long value, unsigned int bits, char *text)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        text[bit] = ((value >> (bits - 1u - bit)) & 1ull) ? '1' : '0';
    }
    text[bits] = '\0';
}

// the frame's text with its line that begins `IADD3 ` replaced by `lines`, into `text`: 1, or 0 where the frame holds
// no such line or `text` will not hold the whole
static int unprinted_text(const char *frame, const char *lines, char *text, size_t room)
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

// the kernel the frame's text opens with, `.text.<kernel>:`, into `kernel`: 1, or 0 where it opens otherwise
static int unprinted_kernel(const char *frame, char *kernel, size_t room)
{
    if (strncmp(frame, ".text.", 6u) != 0)
    {
        return 0;
    }
    const size_t length = strcspn(frame + 6, ":\r\n");
    return (frame[6u + length] == ':') && (snprintf(kernel, room, "%.*s", (int)length, frame + 6) < (int)room);
}

// the instruction of `code`, `count` of them, whose operation bits are `low` and `high`'s: its number, or `count`
// where none is or more than one is
static unsigned int unprinted_find(const unsigned char *code, unsigned int count, unsigned long long low,
                                   unsigned long long high)
{
    unsigned int found = count;
    unsigned int matches = 0u;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        const unsigned long long one = unprinted_word_read(&code[16u * number]);
        const unsigned long long other = unprinted_word_read(&code[(16u * number) + 8u]);
        if ((one == low) && ((other & UNPRINTED_OPERATION_HIGH) == (high & UNPRINTED_OPERATION_HIGH)))
        {
            found = number;
            matches += 1u;
        }
    }
    return (matches == 1u) ? found : count;
}

// the cubin of `code` run on the part over the case: 1 with the first word it answered in `answered`, or 0 where the
// cubin was not written or did not run, with how it ended in `ended`
static int unprinted_run(const char *runner, const char *folder, const char *kernel, const unsigned char *code,
                         unsigned long long code_size, unsigned long long pattern_size, unsigned int *answered,
                         char *ended, size_t room)
{
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = pattern_size;
    written.kernel = kernel;
    written.code = code;
    written.code_size = code_size;
    written.registers = cubin_registers_read(s_pattern, kernel);
    written.exit_count = cubin_exits_find(code, code_size, sass_exit_encoding(&s_machine), s_exits, UNPRINTED_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    char cubin[1024];
    snprintf(cubin, sizeof(cubin), "%s/unprinted.cubin", folder);
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size) || !unprinted_file_write(cubin, s_cubin, size))
    {
        snprintf(ended, room, "not written");
        return 0;
    }
    char output[1024];
    snprintf(output, sizeof(output), "%s/unprinted.out", folder);
    // one case of eight words, none of the other seven zero, the case every question of the probe is asked over
    char *const command[] = {(char *)runner,     (char *)"run",      cubin,              (char *)"0000000b",
                             (char *)"00000007", (char *)"00000003", (char *)"00000005", (char *)"00000002",
                             (char *)"00000009", (char *)"00000001", (char *)"00000004", NULL};
    const InterfaceProbe probe = {command, output, UNPRINTED_LIMIT};
    InterfaceAnswer answer;
    memset(&answer, 0, sizeof(answer));
    answer.output = s_output;
    answer.output_capacity = sizeof(s_output);
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (interface_probe_run(&probe, &answer, &error) != 0L)
    {
        snprintf(ended, room, "the interface failed");
        return 0;
    }
    const char *const line = strstr(s_output, "answered ");
    if ((answer.ending != INTERFACE_ENDING_EXITED) || (answer.code != 0ull) || (line == NULL))
    {
        // the runner names the error the part raised on a line of its own, "error <number> <name>"
        const char *const raised = strstr(s_output, "error ");
        const char *const name = (raised != NULL) ? strchr(raised + 6, ' ') : NULL;
        snprintf(ended, room, "%s, code %llu%s%.*s", interface_ending_name(answer.ending), answer.code,
                 (name != NULL) ? ", " : "", (name != NULL) ? (int)strcspn(name + 1, "\r\n") : 0,
                 (name != NULL) ? name + 1 : "");
        return 0;
    }
    // the runner prints each answered word as eight hexadecimal digits, which an unsigned int holds
    *answered = (unsigned int)strtoul(line + 9, NULL, 16);
    return 1;
}

// question `number` asked at every value of its field, each value's answer printed and written into `record`: how many
// values answered as printed, or -1 where the question was not put
static int unprinted_ask(const UnprintedQuestion *question, unsigned int number, const char *runner,
                         const char *folder, const char *kernel, unsigned long long pattern_size, FILE *record)
{
    // the field's bits as the record names them, none where the question turns no bit and runs its instruction as
    // the assembler wrote it
    char span[32];
    if (question->bits == 0u)
    {
        snprintf(span, sizeof(span), "none");
    }
    else
    {
        snprintf(span, sizeof(span), "%u-%u", question->first, (question->first + question->bits) - 1u);
    }
    unsigned long long low = 0ull;
    unsigned long long high = 0ull;
    const unsigned int count = unprinted_text(s_frame, question->lines, s_asking, sizeof(s_asking))
                                   ? sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code,
                                                         sizeof(s_code))
                                   : 0u;
    const int alone = (count != 0u) && sass_assemble(&s_machine, question->turned, 0ull, 0ull, SASS_CONTROL_SAFE,
                                                     &low, &high);
    const unsigned int place = alone ? unprinted_find(s_code, count, low, high) : count;
    if (place == count)
    {
        printf("  %s: not put, the question did not assemble or its instruction was not found once\n",
               question->turned);
        fprintf(record, "| %u | `%s` | %s | not put | | |\n", number, question->turned, span);
        return -1;
    }
    // the instruction read back through the machine file, which gives its text where the reader holds its field
    char read[SASS_MACHINE_TEXT];
    if (!sass_encoding_read(&s_machine, low, high, 0ull, read, sizeof(read)) || (strcmp(read, question->turned) != 0))
    {
        printf("  %s reads back as %s\n", question->turned, read);
    }
    const unsigned long long code_size = 16ull * count;
    char held[UNPRINTED_FIELD_MOST + 1u];
    unprinted_binary(unprinted_bits_read(low, high, question->first, question->bits), question->bits, held);
    char fixed[64] = "";
    for (unsigned int number = 0u; number < UNPRINTED_FIXED; number += 1u)
    {
        const UnprintedFixed *const one = &question->fixed[number];
        if (one->bits != 0u)
        {
            const size_t at = strlen(fixed);
            snprintf(&fixed[at], sizeof(fixed) - at, ", bit %u held at %llu", one->first, one->value);
        }
    }
    printf("  %s, bits %s%s, the form holds %s, as printed %08x\n", question->turned, span, fixed, held,
           question->answer);
    int printed = 0;
    const unsigned long long values = 1ull << question->bits;
    for (unsigned long long value = 0ull; value < values; value += 1ull)
    {
        memcpy(s_turned, s_code, (size_t)code_size);
        unsigned long long turned_low = unprinted_word_read(&s_turned[16u * place]);
        unsigned long long turned_high = unprinted_word_read(&s_turned[(16u * place) + 8u]);
        for (unsigned int number = 0u; number < UNPRINTED_FIXED; number += 1u)
        {
            const UnprintedFixed *const one = &question->fixed[number];
            unprinted_bits_write(&turned_low, &turned_high, one->first, one->bits, one->value);
        }
        unprinted_bits_write(&turned_low, &turned_high, question->first, question->bits, value);
        unprinted_word_write(&s_turned[16u * place], turned_low);
        unprinted_word_write(&s_turned[(16u * place) + 8u], turned_high);
        unsigned int answered = 0u;
        char ended[96] = "";
        const int ran = unprinted_run(runner, folder, kernel, s_turned, code_size, pattern_size, &answered, ended,
                                      sizeof(ended));
        char digits[UNPRINTED_FIELD_MOST + 1u];
        unprinted_binary(value, question->bits, digits);
        const int same = ran && (answered == question->answer);
        printed += same;
        char reading[128];
        if (ran)
        {
            snprintf(reading, sizeof(reading), "%08x%s", answered, same ? ", as printed" : "");
        }
        else
        {
            snprintf(reading, sizeof(reading), "did not run: %s", ended);
        }
        printf("    %s %s\n", digits, reading);
        fprintf(record, "| %u | `%s` | %s%s | %s | %s | %s |\n", number, question->turned, span, fixed, held, digits,
                reading);
    }
    printf("    %d of %llu values answer as printed\n", printed, values);
    return printed;
}

int main(int count, char **words)
{
    if (count != 7)
    {
        fprintf(stderr, "interface_sass_probe_unprinted <runner> <pattern cubin> <frame text> <machine file> <folder> "
                        "<record>\n");
        return 2;
    }
    const unsigned long long pattern_size = unprinted_file_read(words[2], s_pattern, sizeof(s_pattern));
    const unsigned long long frame_size =
        unprinted_file_read(words[3], (unsigned char *)s_frame, sizeof(s_frame) - 1u);
    s_frame[frame_size] = '\0';
    char kernel[128];
    if ((pattern_size == 0ull) || (frame_size == 0ull) || !unprinted_kernel(s_frame, kernel, sizeof(kernel)))
    {
        fprintf(stderr, "the pattern cubin %s or the frame %s did not read\n", words[2], words[3]);
        return 2;
    }
    if (!sass_machine_read(&s_machine, words[4]))
    {
        fprintf(stderr, "the machine file %s did not read\n", words[4]);
        return 2;
    }
    FILE *const record = fopen(words[6], "wb");
    if (record == NULL)
    {
        fprintf(stderr, "the record %s could not be written\n", words[6]);
        return 2;
    }
    const unsigned int questions = (unsigned int)(sizeof(s_questions) / sizeof(s_questions[0]));
    fprintf(record, "# Bits the disassembler does not print, asked of the part\n\n"
                    "Written by `interface_sass_probe_unprinted` (`interface_sass_unprinted.sh`) whole on every run. "
                    "Each row is one value of the field written into the question's instruction and run on the part "
                    "over the case 0xb, 0x7. A value that answers as printed leaves the field without effect on that "
                    "question.\n\n"
                    "Each question's lines, put in place of the frame's `IADD3`:\n\n");
    for (unsigned int number = 0u; number < questions; number += 1u)
    {
        fprintf(record, "%u. `", number + 1u);
        for (const char *walk = s_questions[number].lines; *walk != '\0'; walk += 1)
        {
            if (*walk == '\n')
            {
                fputs("`; `", record);
            }
            else
            {
                fputc(*walk, record);
            }
        }
        fprintf(record, "`\n");
    }
    fprintf(record, "\n| question | instruction | bits | the form holds | value | answer |\n"
                    "|---|---|---|---|---|---|\n");
    unsigned int put = 0u;
    for (unsigned int number = 0u; number < questions; number += 1u)
    {
        put += (unprinted_ask(&s_questions[number], number + 1u, words[1], words[5], kernel, pattern_size, record) >= 0)
                   ? 1u
                   : 0u;
    }
    fclose(record);
    printf("interface sass unprinted: %u of %u questions put, the record written to %s\n", put, questions, words[6]);
    return (put == questions) ? 0 : 1;
}
