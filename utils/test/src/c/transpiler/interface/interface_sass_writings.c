// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_writings.c: a writing searched for on the part. Every form of the machine file that writes a register
// from registers alone is put in place of the frame's IADD3 with the case's first two words as its sources, run on the
// part over every case of the ladder's relations at once, and read back against what each relation gives each case.
// A form that gives every case of a relation its word is a writing of that relation in one instruction, found by
// running it and by nothing else: no name, listing or compiler says which form adds.
//
// Nothing is compiled and no disassembler is run. The cubins are written here and run by interface_sass_run, which
// holds each to cubin_safe, loads it through the driver and runs it over the cases file this writes, a thread a case.
//
//     interface_sass_writings <pattern cubin> <frame text> <machine file> <folder>
//     interface_sass_writings read <folder> <record>
//
// The first writes <folder>/list.txt, the cubins it names, <folder>/cases.txt and <folder>/forms.txt, the
// instruction each cubin holds a line. The second reads <folder>/answers.txt, which interface_sass_run writes, against
// the ladder's cases and writes the record.
#include "../../../../../../src/c/transpiler/bootstrap/ladder.h"
#include "../../../../../../src/c/transpiler/cubin/cubin_safe.h"
#include "../../../../../../src/c/transpiler/cubin/cubin_write.h"
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the most bytes a cubin, its code and a text take, the most exits a code holds, and the registers every cubin
// declares a thread
#define WRITINGS_CUBIN_BYTES 262144u
#define WRITINGS_CODE_BYTES 65536u
#define WRITINGS_TEXT_BYTES 65536u
#define WRITINGS_EXITS 256u
#define WRITINGS_REGISTERS 255u
// the registers the case's two words are moved onto, each with a zero beside it for a form that reads a pair, and the
// register the form's result is moved to, which the frame then stores as the answer
#define WRITINGS_LEFT "R10"
#define WRITINGS_RIGHT "R12"
#define WRITINGS_RESULT "R8"
// the most cases put at once, one thread each, the words drawn past the ladder's cases for each relation, and the
// longest line read back
#define WRITINGS_CASES 256u
#define WRITINGS_SWEPT 32u
#define WRITINGS_LINE 4096u

// the lines a form is run between: the case's words, which the frame leaves in R0 and R7, moved onto the sources, the
// result's register cleared, and every predicate the form may read set false. After the form its result is moved to
// R7, which the frame's own store writes as the answer's first word
#define WRITINGS_HEAD                                                                                                  \
    "IMAD.MOV.U32 R10, RZ, RZ, R0\nMOV R11, RZ\nIMAD.MOV.U32 R12, RZ, RZ, R7\nMOV R13, RZ\nMOV R8, RZ\nMOV R9, RZ\n"  \
    "ISETP.NE.AND P0, PT, RZ, RZ, PT\nISETP.NE.AND P1, PT, RZ, RZ, PT\nISETP.NE.AND P2, PT, RZ, RZ, PT\n"              \
    "ISETP.NE.AND P3, PT, RZ, RZ, PT\nISETP.NE.AND P4, PT, RZ, RZ, PT\nISETP.NE.AND P5, PT, RZ, RZ, PT\n"              \
    "ISETP.NE.AND P6, PT, RZ, RZ, PT\n"
#define WRITINGS_TAIL "\nIMAD.MOV.U32 R7, RZ, RZ, R8"

#define LADDER_TEXT(name_, text_, words_, measured_) text_,
static const char *const s_anchor_text[] = {LADDER_ANCHORS(LADDER_TEXT)};
#undef LADDER_TEXT
#define LADDER_WORD_COUNT(name_, text_, words_, measured_) words_,
static const unsigned int s_anchor_words[] = {LADDER_ANCHORS(LADDER_WORD_COUNT)};
#undef LADDER_WORD_COUNT

static SassMachine s_machine;
static unsigned char s_pattern[WRITINGS_CUBIN_BYTES];
static unsigned char s_cubin[WRITINGS_CUBIN_BYTES];
static unsigned char s_code[WRITINGS_CODE_BYTES];
static char s_frame[WRITINGS_TEXT_BYTES];
static char s_asking[WRITINGS_TEXT_BYTES];
static unsigned int s_exits[WRITINGS_EXITS];
static char s_kernel[128];
static unsigned long long s_pattern_size;
// the cases a form is put with: the ladder's own, then WRITINGS_SWEPT words past them for each relation
typedef struct
{
    unsigned int anchor;
    unsigned int word[2];
    unsigned int expected;
} WritingsCase;

static WritingsCase s_case[WRITINGS_CASES];
static unsigned int s_cases;

// `path` read whole into `bytes`, which holds `room`: the bytes read, 0 where it was not read
static unsigned long long writings_file_read(const char *path, unsigned char *bytes, unsigned long long room)
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

// 1 where `anchor` is a relation whose answer follows from two words. A measure's answer is the system's and no form
// gives it; a relation of other than two words does not fit the frame's two sources
static int writings_anchor_fits(unsigned int anchor)
{
    return (s_ladder_measured[anchor] == 0) && (s_anchor_words[anchor] == 2u);
}

// The cases a form is put with: every ladder case of a relation that fits, then for each such relation WRITINGS_SWEPT
// words past them, drawn as chain_build draws its sweep and answered by ladder_answer. The ladder's cases are small
// words, and a form that agrees with a relation on small words alone, as a dot product of bytes agrees with a product,
// is told apart by the swept ones
static void writings_cases(void)
{
    s_cases = 0u;
    for (unsigned int at = 0u; (at < LADDER_CASE_COUNT) && (s_cases < WRITINGS_CASES); at += 1u)
    {
        const LadderQuestion *const question = &s_ladder_cases[at];
        if (writings_anchor_fits(question->anchor) && (question->words == 2u))
        {
            s_case[s_cases].anchor = question->anchor;
            s_case[s_cases].word[0] = question->word[0];
            s_case[s_cases].word[1] = question->word[1];
            s_case[s_cases].expected = question->expected;
            s_cases += 1u;
        }
    }
    for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        unsigned int state = 0x9e3779b9u + anchor;
        for (unsigned int drawn = 0u; writings_anchor_fits(anchor) && (drawn < WRITINGS_SWEPT); drawn += 1u)
        {
            unsigned int word[2];
            word[0] = ladder_swept(&state);
            word[1] = ladder_swept(&state);
            unsigned int expected = 0u;
            if ((s_cases < WRITINGS_CASES) && ladder_answer(anchor, word, 2u, &expected))
            {
                s_case[s_cases].anchor = anchor;
                s_case[s_cases].word[0] = word[0];
                s_case[s_cases].word[1] = word[1];
                s_case[s_cases].expected = expected;
                s_cases += 1u;
            }
        }
    }
}

// the kernel the frame opens with, `.text.<kernel>:`, into `kernel`: 1, or 0 where it opens otherwise
static int writings_kernel(const char *frame, char *kernel, size_t room)
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
static int writings_splice(const char *frame, const char *lines, char *text, size_t room)
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

// the sign an operand carries back as its text, since the parts reader cuts it off
static const char *writings_mark(unsigned int mark)
{
    if (mark == SASS_MARK_NEGATE)
    {
        return "-";
    }
    if (mark == SASS_MARK_INVERT)
    {
        return "~";
    }
    if (mark == SASS_MARK_NOT)
    {
        return "!";
    }
    return "";
}

// `operand`, which begins with a register token, written to `out` with that token replaced by `put`, a .hi dropped and
// any other suffix kept
static void writings_swap(const char *operand, const char *put, char *out, size_t room)
{
    size_t length = 0u;
    if (operand[0] == 'R')
    {
        length = (operand[1] == 'Z') ? 2u : (1u + strspn(operand + 1, "0123456789"));
    }
    const char *const rest = operand + length;
    const size_t kept = strlen(rest) - (sass_high_half(operand) ? 3u : 0u);
    snprintf(out, room, "%s%.*s", put, (int)kept, rest);
}

// 1 where `form` is put to the part: it writes its first operand, a register, it neither transfers control nor waits,
// and every operand is a register, a predicate or a number, which reach no memory and no state of the part's own
static int writings_form_fits(const SassForm *form)
{
    if ((form->operands < 2u) || (form->kind[0] != SASS_OPERAND_REGISTER) ||
        sass_operation_control_or_wait(form->operation) || (strncmp(form->operation, "NOP", 3u) == 0))
    {
        return 0;
    }
    unsigned int sources = 0u;
    for (unsigned int at = 0u; at < form->operands; at += 1u)
    {
        const unsigned int kind = form->kind[at];
        if ((kind != SASS_OPERAND_REGISTER) && (kind != SASS_OPERAND_PREDICATE) && (kind != SASS_OPERAND_IMMEDIATE))
        {
            return 0;
        }
        sources += ((at != 0u) && (kind == SASS_OPERAND_REGISTER)) ? 1u : 0u;
    }
    return sources != 0u;
}

// `form`'s own instruction written to `out` with its result moved to WRITINGS_RESULT, its first register source to
// WRITINGS_LEFT, its second to WRITINGS_RIGHT and every register source past those to RZ. A predicate and a number keep
// the values the form was seen with. 1, or 0 where `out` will not hold it
static int writings_instruction(const SassForm *form, char *out, size_t room)
{
    SassInstructionParts parts;
    sass_instruction_read(form->text, &parts);
    if (parts.operands != form->operands)
    {
        return 0;
    }
    size_t at = (size_t)snprintf(out, room, "%s", parts.operation);
    unsigned int source = 0u;
    for (unsigned int operand = 0u; operand < parts.operands; operand += 1u)
    {
        char text[SASS_MACHINE_TOKEN];
        if (parts.kind[operand] == SASS_OPERAND_REGISTER)
        {
            const char *put = "RZ";
            if (operand == 0u)
            {
                put = WRITINGS_RESULT;
            }
            else if (source == 0u)
            {
                put = WRITINGS_LEFT;
            }
            else if (source == 1u)
            {
                put = WRITINGS_RIGHT;
            }
            source += (operand != 0u) ? 1u : 0u;
            writings_swap(parts.operand[operand], put, text, sizeof(text));
        }
        else
        {
            snprintf(text, sizeof(text), "%s", parts.operand[operand]);
        }
        at += (size_t)snprintf(&out[at], (at < room) ? (room - at) : 0u, "%s%s%s", (operand == 0u) ? " " : ", ",
                               writings_mark(parts.mark[operand]), text);
    }
    return at < room;
}

// `code`, `count` instructions, laid into a cubin and written to `path`: 1, or 0 where it was not
static int writings_cubin(unsigned int count, const char *path)
{
    const unsigned long long code_size = 16ull * count;
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = s_pattern_size;
    written.kernel = s_kernel;
    written.code = s_code;
    written.code_size = code_size;
    written.registers = WRITINGS_REGISTERS;
    written.exit_count = cubin_exits_find(s_code, code_size, sass_exit_encoding(&s_machine), s_exits, WRITINGS_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    unsigned long long at = 0ull;
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size) ||
        (cubin_safe_image(&s_machine, s_cubin, size, &at) != CUBIN_SAFE))
    {
        return 0;
    }
    FILE *const file = fopen(path, "wb");
    const int put = (file != NULL) && (fwrite(s_cubin, 1u, (size_t)size, file) == size);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return put && closed;
}

// every fitting form written into a cubin of its own, with the list, the cases and the forms beside them: 0, or 2
// where nothing could be read or written
static int writings_write(const char *pattern, const char *frame, const char *machine, const char *folder)
{
    s_pattern_size = writings_file_read(pattern, s_pattern, sizeof(s_pattern));
    const unsigned long long frame_size = writings_file_read(frame, (unsigned char *)s_frame, sizeof(s_frame) - 1u);
    s_frame[frame_size] = '\0';
    if ((s_pattern_size == 0ull) || (frame_size == 0ull) || !writings_kernel(s_frame, s_kernel, sizeof(s_kernel)) ||
        !sass_machine_read(&s_machine, machine))
    {
        fprintf(stderr, "the pattern %s, the frame %s or the machine file %s did not read\n", pattern, frame, machine);
        return 2;
    }
    writings_cases();
    char path[1024];
    snprintf(path, sizeof(path), "%s/cases.txt", folder);
    FILE *const cases = fopen(path, "wb");
    snprintf(path, sizeof(path), "%s/list.txt", folder);
    FILE *const list = fopen(path, "wb");
    snprintf(path, sizeof(path), "%s/forms.txt", folder);
    FILE *const forms = fopen(path, "wb");
    if ((cases == NULL) || (list == NULL) || (forms == NULL))
    {
        fprintf(stderr, "the folder %s was not written\n", folder);
        return 2;
    }
    for (unsigned int at = 0u; at < s_cases; at += 1u)
    {
        fprintf(cases, "%08x %08x\n", s_case[at].word[0], s_case[at].word[1]);
    }
    unsigned int fitting = 0u;
    unsigned int written = 0u;
    for (unsigned int at = 0u; at < s_machine.forms; at += 1u)
    {
        const SassForm *const form = &s_machine.form[at];
        if (!writings_form_fits(form))
        {
            continue;
        }
        fitting += 1u;
        char instruction[256];
        char lines[2048];
        if (!writings_instruction(form, instruction, sizeof(instruction)) ||
            (snprintf(lines, sizeof(lines), WRITINGS_HEAD "%s" WRITINGS_TAIL, instruction) >= (int)sizeof(lines)) ||
            !writings_splice(s_frame, lines, s_asking, sizeof(s_asking)))
        {
            continue;
        }
        const unsigned int count = sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code, sizeof(s_code));
        char cubin[1024];
        snprintf(cubin, sizeof(cubin), "%s/form_%04u.cubin", folder, written);
        if ((count == 0u) || !writings_cubin(count, cubin))
        {
            continue;
        }
        fprintf(list, "%s %s\n", cubin, s_kernel);
        fprintf(forms, "%u\t%s\n", written, instruction);
        written += 1u;
    }
    fclose(cases);
    fclose(list);
    fclose(forms);
    printf("interface sass writings: %u forms of %u fit, %u written and held to cubin_safe, %u cases\n", fitting,
           s_machine.forms, written, s_cases);
    return 0;
}

// The answers read back against every relation: the forms that give each relation's every case its word, written to
// `record`. A relation no form gives in one instruction is one the part has no single instruction for, among the forms
// the machine file holds. 0, or 2 where nothing could be read
static int writings_read(const char *folder, const char *record)
{
    writings_cases();
    static char s_forms[16384][256];
    unsigned int form_count = 0u;
    char path[1024];
    char line[WRITINGS_LINE];
    snprintf(path, sizeof(path), "%s/forms.txt", folder);
    FILE *const forms = fopen(path, "rb");
    snprintf(path, sizeof(path), "%s/answers.txt", folder);
    FILE *const answers = fopen(path, "rb");
    FILE *const out = fopen(record, "wb");
    if ((forms == NULL) || (answers == NULL) || (out == NULL))
    {
        fprintf(stderr, "the forms, the answers in %s or the record %s was not reached\n", folder, record);
        return 2;
    }
    while ((form_count < 16384u) && (fgets(line, sizeof(line), forms) != NULL))
    {
        const char *const tab = strchr(line, '\t');
        if (tab != NULL)
        {
            snprintf(s_forms[form_count], sizeof(s_forms[0]), "%.*s", (int)strcspn(tab + 1, "\r\n"), tab + 1);
            form_count += 1u;
        }
    }
    fclose(forms);
    static unsigned char s_holds[16384][LADDER_ANCHOR_COUNT];
    static int s_ran[16384];
    unsigned int ran = 0u;
    unsigned int refused = 0u;
    while (fgets(line, sizeof(line), answers) != NULL)
    {
        char *walk = NULL;
        const unsigned long number = strtoul(line, &walk, 10);
        if ((walk == line) || (number >= form_count))
        {
            continue;
        }
        walk += strspn(walk, " ");
        if (strncmp(walk, "answered", 8u) != 0)
        {
            refused += 1u;
            continue;
        }
        walk += 8;
        unsigned int answered[WRITINGS_CASES];
        unsigned int read = 0u;
        while ((read < s_cases) && (*walk != '\0'))
        {
            char *next = NULL;
            answered[read] = (unsigned int)strtoul(walk, &next, 16);
            if (next == walk)
            {
                break;
            }
            walk = next;
            read += 1u;
        }
        if (read != s_cases)
        {
            continue;
        }
        s_ran[number] = 1;
        ran += 1u;
        for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
        {
            unsigned int put = 0u;
            unsigned int agreed = 0u;
            for (unsigned int at = 0u; at < s_cases; at += 1u)
            {
                if (s_case[at].anchor == anchor)
                {
                    put += 1u;
                    agreed += (answered[at] == s_case[at].expected) ? 1u : 0u;
                }
            }
            s_holds[number][anchor] = (unsigned char)((put != 0u) && (agreed == put));
        }
    }
    fclose(answers);
    fprintf(out, "# Writings found on the part\n\n");
    fprintf(out, "Written by `interface_sass_writings.sh` whole on every run. Every form of the machine file that writes a "
                 "register from registers alone is run on the part in place of the frame's IADD3, its first two "
                 "register sources given each case's two words and every other register source RZ, over every case "
                 "of the ladder's relations and %u words drawn past them for each, at once. A form is listed under a "
                 "relation where it gives every case of that relation its word. %u forms ran over %u cases and %u "
                 "were refused by the part.\n\n",
            WRITINGS_SWEPT, ran, s_cases, refused);
    unsigned int found_total = 0u;
    for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        if (!writings_anchor_fits(anchor))
        {
            continue;
        }
        unsigned int found = 0u;
        for (unsigned int number = 0u; number < form_count; number += 1u)
        {
            found += (s_ran[number] && s_holds[number][anchor]) ? 1u : 0u;
        }
        fprintf(out, "## %s\n\n%u forms give every case its word.\n\n", s_anchor_text[anchor], found);
        for (unsigned int number = 0u; number < form_count; number += 1u)
        {
            if (s_ran[number] && s_holds[number][anchor])
            {
                fprintf(out, "- `%s`\n", s_forms[number]);
            }
        }
        fprintf(out, "\n");
        found_total += found;
        printf("  %-8s %u forms give every case its word\n", s_anchor_text[anchor], found);
    }
    fclose(out);
    printf("interface sass writings: %u forms ran, %u refused, %u writings found, the record written to %s\n", ran,
           refused, found_total, record);
    return 0;
}

int main(int count, char **words)
{
    if ((count == 4) && (strcmp(words[1], "read") == 0))
    {
        return writings_read(words[2], words[3]);
    }
    if (count != 5)
    {
        fprintf(stderr, "interface_sass_writings <pattern cubin> <frame text> <machine file> <folder>\n"
                        "interface_sass_writings read <folder> <record>\n");
        return 2;
    }
    return writings_write(words[1], words[2], words[3], words[4]);
}
