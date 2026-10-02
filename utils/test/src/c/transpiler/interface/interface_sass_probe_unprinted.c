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
// the widest field turned through every value, and the most bits a question holds fixed beside it
#define UNPRINTED_FIELD_MOST 6u
#define UNPRINTED_FIXED 2u
// the words a run answers: the frame stores R7 as the first and zero as the other three, and a question may store
// over those three
#define UNPRINTED_COPIES 4u
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
// the runner, the folder a cubin is written into, the kernel and the pattern cubin's size, as main was given them
static const char *s_runner;
static const char *s_folder;
static char s_kernel[128];
static unsigned long long s_pattern_size;
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

// every instruction of `code`, `count` of them, whose operation bits are `low` and `high`'s, their numbers in order
// into `found`, which holds `room`: how many there are
static unsigned int unprinted_find(const unsigned char *code, unsigned int count, unsigned long long low,
                                   unsigned long long high, unsigned int *found, unsigned int room)
{
    unsigned int matches = 0u;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        const unsigned long long one = unprinted_word_read(&code[16u * number]);
        const unsigned long long other = unprinted_word_read(&code[(16u * number) + 8u]);
        if ((one == low) && ((other & UNPRINTED_OPERATION_HIGH) == (high & UNPRINTED_OPERATION_HIGH)))
        {
            if (matches < room)
            {
                found[matches] = number;
            }
            matches += 1u;
        }
    }
    return matches;
}

// the encoding at place `place` of `code` with `bits` bits from `first` set to `value`, and the bits each question
// holds fixed beside it
static void unprinted_place_write(unsigned char *code, unsigned int place, const UnprintedFixed *fixed,
                                  unsigned int fixed_count, unsigned int first, unsigned int bits,
                                  unsigned long long value)
{
    unsigned long long low = unprinted_word_read(&code[16u * place]);
    unsigned long long high = unprinted_word_read(&code[(16u * place) + 8u]);
    for (unsigned int number = 0u; number < fixed_count; number += 1u)
    {
        unprinted_bits_write(&low, &high, fixed[number].first, fixed[number].bits, fixed[number].value);
    }
    unprinted_bits_write(&low, &high, first, bits, value);
    unprinted_word_write(&code[16u * place], low);
    unprinted_word_write(&code[(16u * place) + 8u], high);
}

// the cubin of `code` run on the part over the case: 1 with the four words it answered in `answered`, or 0 where the
// cubin was not written or did not run, with how it ended in `ended`
static int unprinted_run(const unsigned char *code, unsigned long long code_size, unsigned int *answered, char *ended,
                         size_t room)
{
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = s_pattern_size;
    written.kernel = s_kernel;
    written.code = code;
    written.code_size = code_size;
    written.registers = cubin_registers_read(s_pattern, s_kernel);
    written.exit_count = cubin_exits_find(code, code_size, sass_exit_encoding(&s_machine), s_exits, UNPRINTED_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    char cubin[1024];
    snprintf(cubin, sizeof(cubin), "%s/unprinted.cubin", s_folder);
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size) || !unprinted_file_write(cubin, s_cubin, size))
    {
        snprintf(ended, room, "not written");
        return 0;
    }
    char output[1024];
    snprintf(output, sizeof(output), "%s/unprinted.out", s_folder);
    // one case of eight words, none of the other seven zero, the case every question of the probe is asked over
    char *const command[] = {(char *)s_runner,   (char *)"run",      cubin,              (char *)"0000000b",
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
    const char *walk = line + 9;
    for (unsigned int word = 0u; word < UNPRINTED_COPIES; word += 1u)
    {
        char *after = NULL;
        answered[word] = (unsigned int)strtoul(walk, &after, 16);
        walk = after;
    }
    return 1;
}

// question `number` asked at every value of its field, each value's answer printed and written into `record`: how many
// values answered as printed, or -1 where the question was not put
static int unprinted_ask(const UnprintedQuestion *question, unsigned int number, FILE *record)
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
    unsigned int place = 0u;
    if (!alone || (unprinted_find(s_code, count, low, high, &place, 1u) != 1u))
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
    for (unsigned int at = 0u; at < UNPRINTED_FIXED; at += 1u)
    {
        const UnprintedFixed *const one = &question->fixed[at];
        if (one->bits != 0u)
        {
            const size_t written = strlen(fixed);
            snprintf(&fixed[written], sizeof(fixed) - written, ", bit %u held at %llu", one->first, one->value);
        }
    }
    printf("  %s, bits %s%s, the form holds %s, as printed %08x\n", question->turned, span, fixed, held,
           question->answer);
    int printed = 0;
    const unsigned long long values = 1ull << question->bits;
    for (unsigned long long value = 0ull; value < values; value += 1ull)
    {
        memcpy(s_turned, s_code, (size_t)code_size);
        unprinted_place_write(s_turned, place, question->fixed, UNPRINTED_FIXED, question->first, question->bits,
                              value);
        unsigned int answered[UNPRINTED_COPIES] = {0u, 0u, 0u, 0u};
        char ended[96] = "";
        const int ran = unprinted_run(s_turned, code_size, answered, ended, sizeof(ended));
        char digits[UNPRINTED_FIELD_MOST + 1u];
        unprinted_binary(value, question->bits, digits);
        const int same = ran && (answered[0] == question->answer);
        printed += same;
        char reading[128];
        if (ran)
        {
            snprintf(reading, sizeof(reading), "%08x%s", answered[0], same ? ", as printed" : "");
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

// One operand of a form filled for the forms question, from its form's own operand `base` of `kind` at `place`, into
// `operand`. The first operand is the result: R8, P0 or UR6. A register read is R0 and R6 in turn, which hold 0xb and
// 0x7, a predicate read P1, which is true, and a uniform register read UR4, which holds the memory descriptor. RZ, PT,
// URZ, a number and a constant past bank 0 are kept, and a constant in bank 0 reads c[0x0][0x0], which every run
// holds alike. A register keeps what follows its name, a half or a width. 1, or 0 where the kind is one this question
// does not fill
static int unprinted_operand(const char *base, unsigned int kind, unsigned int mark, unsigned int place,
                             unsigned int *reads, char *operand, size_t room)
{
    static const char *const s_marks[] = {"", "-", "~", "!"};
    const char *const shown = (mark < (sizeof(s_marks) / sizeof(s_marks[0]))) ? s_marks[mark] : "";
    const char *const dot = strchr(base, '.');
    const char *const after = (dot != NULL) ? dot : "";
    switch (kind)
    {
    case SASS_OPERAND_REGISTER:
        if ((place != 0u) && (strncmp(base, "RZ", 2u) == 0))
        {
            return snprintf(operand, room, "%s%s", shown, base) < (int)room;
        }
        *reads += (place != 0u) ? 1u : 0u;
        return snprintf(operand, room, "%s%s%s", shown, (place == 0u) ? "R8" : (((*reads % 2u) == 1u) ? "R0" : "R6"),
                        after) < (int)room;
    case SASS_OPERAND_PREDICATE:
        return snprintf(operand, room, "%s%s", shown,
                        (place == 0u) ? "P0" : ((strcmp(base, "PT") == 0) ? "PT" : "P1")) < (int)room;
    case SASS_OPERAND_UNIFORM:
        return snprintf(operand, room, "%s%s", shown,
                        (place == 0u) ? "UR6" : ((strcmp(base, "URZ") == 0) ? "URZ" : "UR4")) < (int)room;
    case SASS_OPERAND_IMMEDIATE:
        return (place != 0u) && (snprintf(operand, room, "%s%s", shown, base) < (int)room);
    case SASS_OPERAND_CONSTANT:
        return (place != 0u) && (snprintf(operand, room, "%s%s", shown,
                                          (strncmp(base, "c[0x0]", 6u) == 0) ? "c[0x0][0x0]" : base) < (int)room);
    default:
        return 0;
    }
}

// `form` written with its operands filled (unprinted_operand) into `text`: 1, or 0 with the reason in `why`, where its
// result is no register, predicate or uniform register, or an operand is a kind the question does not fill
static int unprinted_form_text(const SassForm *form, char *text, size_t room, const char **why)
{
    const int result = (form->operands != 0u) &&
                       ((form->kind[0] == SASS_OPERAND_REGISTER) || (form->kind[0] == SASS_OPERAND_PREDICATE) ||
                        (form->kind[0] == SASS_OPERAND_UNIFORM));
    if (!result)
    {
        *why = "its first operand is no register, predicate or uniform register to read an answer from";
        return 0;
    }
    SassInstructionParts base;
    sass_instruction_read(form->text, &base);
    size_t at = (size_t)snprintf(text, room, "%s", form->operation);
    unsigned int reads = 0u;
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        char operand[SASS_MACHINE_TOKEN + 8u];
        if (!unprinted_operand(base.operand[place], form->kind[place], form->mark[place], place, &reads, operand,
                               sizeof(operand)))
        {
            *why = "an operand is an address, a label or a kind the question does not fill";
            return 0;
        }
        at += (size_t)snprintf(text + at, (at < room) ? (room - at) : 0u, "%s%s", (place == 0u) ? " " : ", ",
                               operand);
    }
    return at < room;
}

// The lines of the forms question: UNPRINTED_COPIES copies of `instruction`, each after P1 and P2 are set again and
// each moving its result into R8 where the result is a predicate or a uniform register. The first copy's R8 is moved
// into R7, which the frame stores as the first word, and each copy past it stores its R8 as a word of its own
static int unprinted_form_lines(const char *instruction, unsigned int result, char *lines, size_t room)
{
    size_t at = (size_t)snprintf(lines, room, "IMAD.MOV.U32 R6, RZ, RZ, R7\n");
    for (unsigned int copy = 0u; (copy < UNPRINTED_COPIES) && (at < room); copy += 1u)
    {
        const char *const moved = (result == SASS_OPERAND_PREDICATE) ? "SEL R8, R0, RZ, P0\n"
                                  : (result == SASS_OPERAND_UNIFORM) ? "MOV R8, UR6\n"
                                                                     : "";
        char kept[64];
        if (copy == 0u)
        {
            snprintf(kept, sizeof(kept), "IMAD.MOV.U32 R7, RZ, RZ, R8");
        }
        else
        {
            snprintf(kept, sizeof(kept), "STG.E term[UR4][R4.64+0x%x], R8", 4u * copy);
        }
        at += (size_t)snprintf(lines + at, room - at, "%s%s\n%s%s%s", UNPRINTED_PREDICATES, instruction, moved, kept,
                               (copy + 1u < UNPRINTED_COPIES) ? "\n" : "");
    }
    return at < room;
}

// how a form's unprinted run answered, value by value
typedef struct
{
    unsigned int alike;
    unsigned int asked;
    char otherwise[512];
} UnprintedTally;

// `value` written as `bits` binary digits and what it answered appended to the tally's list of values answering
// otherwise than the form's own bits
static void unprinted_tally_otherwise(UnprintedTally *tally, unsigned long long value, unsigned int bits,
                                      const char *reading)
{
    char digits[64];
    unprinted_binary(value, (bits < 63u) ? bits : 63u, digits);
    const size_t at = strlen(tally->otherwise);
    snprintf(&tally->otherwise[at], sizeof(tally->otherwise) - at, "%s%s %s", (at == 0u) ? "" : "; ", digits, reading);
}

// The values asked of one run: every one where the run is UNPRINTED_FIELD_MOST bits or fewer, else the form's own
// value with each bit turned in turn. Value `index` of them, or the count where `index` is past them
static unsigned long long unprinted_value(unsigned int bits, unsigned long long own, unsigned long long index,
                                          unsigned long long *count)
{
    *count = (bits <= UNPRINTED_FIELD_MOST) ? (1ull << bits) : (unsigned long long)bits;
    return (bits <= UNPRINTED_FIELD_MOST) ? index : (own ^ (1ull << index));
}

// one unprinted run of a form asked at its values, UNPRINTED_COPIES at a run, against `own`, what the form's own bits
// answered. A run that did not run asks each of its values again alone, the other copies at the form's own bits
static void unprinted_form_run(const unsigned int *places, unsigned long long code_size, const SassRun *run,
                               unsigned long long held, unsigned int own, UnprintedTally *tally)
{
    const unsigned int bits = (run->last - run->first) + 1u;
    unsigned long long count = 0ull;
    unprinted_value(bits, held, 0ull, &count);
    for (unsigned long long start = 0ull; start < count; start += UNPRINTED_COPIES)
    {
        memcpy(s_turned, s_code, (size_t)code_size);
        for (unsigned int copy = 0u; (copy < UNPRINTED_COPIES) && ((start + copy) < count); copy += 1u)
        {
            unprinted_place_write(s_turned, places[copy], NULL, 0u, run->first, bits,
                                  unprinted_value(bits, held, start + copy, &count));
        }
        unsigned int answered[UNPRINTED_COPIES] = {0u, 0u, 0u, 0u};
        char ended[96] = "";
        const int ran = unprinted_run(s_turned, code_size, answered, ended, sizeof(ended));
        for (unsigned int copy = 0u; (copy < UNPRINTED_COPIES) && ((start + copy) < count); copy += 1u)
        {
            const unsigned long long value = unprinted_value(bits, held, start + copy, &count);
            unsigned int word = answered[copy];
            int alone = ran;
            if (!ran)
            {
                memcpy(s_turned, s_code, (size_t)code_size);
                unprinted_place_write(s_turned, places[0], NULL, 0u, run->first, bits, value);
                alone = unprinted_run(s_turned, code_size, answered, ended, sizeof(ended));
                word = answered[0];
            }
            tally->asked += 1u;
            char reading[128];
            if (!alone)
            {
                snprintf(reading, sizeof(reading), "did not run: %s", ended);
            }
            else
            {
                snprintf(reading, sizeof(reading), "%08x", word);
            }
            if (alone && (word == own))
            {
                tally->alike += 1u;
                continue;
            }
            unprinted_tally_otherwise(tally, value, bits, reading);
        }
    }
}

// Every form the machine file holds with an operand it does not print, each written with its operands filled
// (unprinted_form_text), UNPRINTED_COPIES copies to a cubin, and each unprinted run asked at its values against what
// the form's own bits answer. A row of `record` for each run asked and each form not asked
static void unprinted_forms(FILE *record)
{
    fprintf(record, "# Every form's unprinted operands, asked of the part\n\n"
                    "Written by `interface_sass_probe_unprinted` (`interface_sass_unprinted.sh --forms`) whole on "
                    "every run. Each form holding a run of an operand it does not print is written with its operands "
                    "filled: its result R8, P0 or UR6, registers it reads R0 and R6 (0xb and 0x7), predicates it "
                    "reads P1 (true), uniform registers UR4, a constant in bank 0 c[0x0][0x0]. Each run is asked at "
                    "every value where it is %u bits or fewer, else at the form's own value with each bit turned, "
                    "against what the form's own bits answer. A run every value of which answers alike is one the "
                    "part does not read on that question.\n\n"
                    "| form | asked as | bits | the form holds | its own bits answer | values alike | values "
                    "otherwise |\n|---|---|---|---|---|---|---|\n",
            UNPRINTED_FIELD_MOST);
    unsigned int forms = 0u;
    unsigned int asked = 0u;
    unsigned int unread = 0u;
    for (unsigned int number = 0u; number < s_machine.forms; number += 1u)
    {
        const SassForm *const form = &s_machine.form[number];
        int holds = 0;
        for (unsigned int at = 0u; at < form->runs; at += 1u)
        {
            holds = holds || (form->run[at].operand >= form->operands);
        }
        if (!holds)
        {
            continue;
        }
        forms += 1u;
        char instruction[SASS_MACHINE_TEXT];
        static char s_lines[4096];
        const char *why = "";
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        unsigned int places[UNPRINTED_COPIES] = {0u, 0u, 0u, 0u};
        const int written = unprinted_form_text(form, instruction, sizeof(instruction), &why);
        const unsigned int count =
            (written && unprinted_form_lines(instruction, form->kind[0], s_lines, sizeof(s_lines)) &&
             unprinted_text(s_frame, s_lines, s_asking, sizeof(s_asking)))
                ? sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code, sizeof(s_code))
                : 0u;
        const int alone =
            (count != 0u) && sass_assemble(&s_machine, instruction, 0ull, 0ull, SASS_CONTROL_SAFE, &low, &high);
        const int found = alone && (unprinted_find(s_code, count, low, high, places, UNPRINTED_COPIES) ==
                                    UNPRINTED_COPIES);
        why = (!written) ? why : (!found ? "the question did not assemble, or its copies were not found" : why);
        unsigned int own[UNPRINTED_COPIES] = {0u, 0u, 0u, 0u};
        char ended[96] = "";
        const int ran = found && unprinted_run(s_code, 16ull * count, own, ended, sizeof(ended));
        const int steady = ran && (own[1] == own[0]) && (own[2] == own[0]) && (own[3] == own[0]);
        if (found && !ran)
        {
            why = "its own bits did not run";
        }
        if (ran && !steady)
        {
            why = "its copies answered unlike one another at its own bits";
        }
        if (!steady)
        {
            printf("  %s: not asked, %s%s%s\n", form->text, why, (found && !ran) ? ": " : "",
                   (found && !ran) ? ended : "");
            fprintf(record, "| `%s` | %s | | | not asked: %s | | |\n", form->text,
                    written ? instruction : "", why);
            continue;
        }
        asked += 1u;
        for (unsigned int at = 0u; at < form->runs; at += 1u)
        {
            const SassRun *const run = &form->run[at];
            if (run->operand < form->operands)
            {
                continue;
            }
            const unsigned int bits = (run->last - run->first) + 1u;
            const unsigned long long held = unprinted_bits_read(low, high, run->first, bits);
            UnprintedTally tally;
            memset(&tally, 0, sizeof(tally));
            unprinted_form_run(places, 16ull * count, run, held, own[0], &tally);
            unread += (tally.alike == tally.asked) ? 1u : 0u;
            char digits[64];
            unprinted_binary(held, (bits < 63u) ? bits : 63u, digits);
            printf("  %s, bits %u-%u, %u of %u values alike%s%s\n", instruction, run->first, run->last, tally.alike,
                   tally.asked, (tally.otherwise[0] != '\0') ? ": " : "", tally.otherwise);
            fprintf(record, "| `%s` | `%s` | %u-%u | %s | %08x | %u of %u | %s |\n", form->text, instruction,
                    run->first, run->last, digits, own[0], tally.alike, tally.asked, tally.otherwise);
        }
    }
    fprintf(record, "\n%u forms hold an unprinted run, %u asked, %u runs answering alike at every value asked.\n",
            forms, asked, unread);
    printf("interface sass unprinted: %u forms hold an unprinted run, %u asked, %u runs answering alike\n", forms,
           asked, unread);
}

int main(int count, char **words)
{
    const int forms = (count == 8) && (strcmp(words[7], "forms") == 0);
    if ((count != 7) && !forms)
    {
        fprintf(stderr, "interface_sass_probe_unprinted <runner> <pattern cubin> <frame text> <machine file> <folder> "
                        "<record> [forms]\n");
        return 2;
    }
    s_runner = words[1];
    s_folder = words[5];
    s_pattern_size = unprinted_file_read(words[2], s_pattern, sizeof(s_pattern));
    const unsigned long long frame_size =
        unprinted_file_read(words[3], (unsigned char *)s_frame, sizeof(s_frame) - 1u);
    s_frame[frame_size] = '\0';
    if ((s_pattern_size == 0ull) || (frame_size == 0ull) || !unprinted_kernel(s_frame, s_kernel, sizeof(s_kernel)))
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
    if (forms)
    {
        unprinted_forms(record);
        fclose(record);
        return 0;
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
        put += (unprinted_ask(&s_questions[number], number + 1u, record) >= 0) ? 1u : 0u;
    }
    fclose(record);
    printf("interface sass unprinted: %u of %u questions put, the record written to %s\n", put, questions, words[6]);
    return (put == questions) ? 0 : 1;
}
