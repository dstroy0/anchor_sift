// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_writings.c: a writing searched for on the part. Every form of the machine file that writes a register
// from registers, predicates and numbers alone is put in place of the frame's IADD3 with the case's first two words as
// its sources, run on the part over every case at once, and read back against what each ladder relation and each
// precept gives each case. A form that gives every case a relation's word is a writing of that relation in one
// instruction, found by running it and by nothing else: no name, listing or compiler says which form adds. A number
// whose field is eight bits wide is a truth table of three inputs, and a form holding one is put with each of its 256
// values (precept_value.h).
//
// Nothing is compiled and no disassembler is run. The cubins are written here and run by interface_sass_run, which
// holds each to cubin_safe, loads it through the driver and runs it over the cases file this writes, a thread a case.
//
//     interface_sass_writings <pattern cubin> <frame text> <machine file> <folder>
//     interface_sass_writings read <folder> <record>
//     interface_sass_writings chains <pattern cubin> <frame text> <machine file> <folder> <kdm>
//     interface_sass_writings chains-read <folder> <record>
//
// The first writes <folder>/list.txt, the cubins it names, <folder>/cases.txt and <folder>/forms.txt, the
// instruction each cubin holds a line. The second reads <folder>/answers.txt, which interface_sass_run writes, against
// every relation and writes the record. The third writes every arrangement of the .kdm node by node, each node the
// first writing found for its precept, into <folder>/chains, and the fourth reads the chains' answers back against
// the relation each is a row of.
#include "../../../../../../src/c/transpiler/bootstrap/ladder.h"
#include "../../../../../../src/c/transpiler/codegen/precept_value.h"
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
// the most cases put at once, one thread each, the most relations a form is read against, and the longest line read
// back
#define WRITINGS_CASES 256u
#define WRITINGS_RELATIONS 64u
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
#define PRECEPT_TEXT(name_, text_, arity_) text_,
static const char *const s_precept_text[] = {PRECEPTS(PRECEPT_TEXT)};
#undef PRECEPT_TEXT
#define PRECEPT_ARITY(name_, text_, arity_) arity_,
static const unsigned int s_precept_arity[] = {PRECEPTS(PRECEPT_ARITY)};
#undef PRECEPT_ARITY

static SassMachine s_machine;
static unsigned char s_pattern[WRITINGS_CUBIN_BYTES];
static unsigned char s_cubin[WRITINGS_CUBIN_BYTES];
static unsigned char s_code[WRITINGS_CODE_BYTES];
static char s_frame[WRITINGS_TEXT_BYTES];
static char s_asking[WRITINGS_TEXT_BYTES];
static unsigned int s_exits[WRITINGS_EXITS];
static char s_kernel[128];
static unsigned long long s_pattern_size;
// the two words of each case a form is put with
static unsigned int s_case[WRITINGS_CASES][2];
static unsigned int s_cases;
// what a form is read against: a relation of the ladder, answered by ladder_answer, or a precept of the alphabet,
// answered by precept_applied
typedef struct
{
    const char *name;
    int precept;
    unsigned int which;
} WritingsRelation;

static WritingsRelation s_relation[WRITINGS_RELATIONS];
static unsigned int s_relations;

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

// The relations a form is read against: every ladder relation whose answer follows from two words, then every
// precept that carries a word from one or two, NOT and MOV reading the first word alone. NOP, ERR and the branches
// carry no word
static void writings_relations(void)
{
    s_relations = 0u;
    for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        if (writings_anchor_fits(anchor) && (s_relations < WRITINGS_RELATIONS))
        {
            s_relation[s_relations] = (WritingsRelation){s_anchor_text[anchor], 0, anchor};
            s_relations += 1u;
        }
    }
    for (unsigned int precept = 0u; precept < PRECEPT_COUNT; precept += 1u)
    {
        const int carries = (precept != PRECEPT_NOP) && (precept != PRECEPT_ERR) && (precept != PRECEPT_BRA) &&
                            (precept != PRECEPT_JCC) && (s_precept_arity[precept] != 0u);
        if (carries && (s_relations < WRITINGS_RELATIONS))
        {
            s_relation[s_relations] = (WritingsRelation){s_precept_text[precept], 1, precept};
            s_relations += 1u;
        }
    }
}

// the word `relation` gives the case `word`
static unsigned int writings_expected(const WritingsRelation *relation, const unsigned int *word)
{
    if (relation->precept)
    {
        return precept_applied((unsigned char)relation->which, word[0], word[1]);
    }
    unsigned int answered = 0u;
    ladder_answer(relation->which, word, 2u, &answered);
    return answered;
}

// The cases a form is put with, every relation read on every one: the ladder's own two-word cases, the words a width
// turns on put against the counts a shift turns on, and words drawn as chain_build draws its sweep to fill a launch.
// The ladder's cases are small words, and a form that agrees with a relation on small words alone, as a dot product
// of bytes agrees with a product, is told apart by the drawn ones
static void writings_cases(void)
{
    static const unsigned int s_edge_words[] = {0u, 1u, 0x7fffffffu, 0x80000000u, 0xffffffffu};
    static const unsigned int s_edge_counts[] = {0u, 1u, 31u, 32u, 33u, 0xffffffffu};
    s_cases = 0u;
    for (unsigned int at = 0u; (at < LADDER_CASE_COUNT) && (s_cases < WRITINGS_CASES); at += 1u)
    {
        const LadderQuestion *const question = &s_ladder_cases[at];
        if (writings_anchor_fits(question->anchor) && (question->words == 2u))
        {
            s_case[s_cases][0] = question->word[0];
            s_case[s_cases][1] = question->word[1];
            s_cases += 1u;
        }
    }
    for (unsigned int word = 0u; word < (sizeof(s_edge_words) / sizeof(s_edge_words[0])); word += 1u)
    {
        for (unsigned int count = 0u; count < (sizeof(s_edge_counts) / sizeof(s_edge_counts[0])); count += 1u)
        {
            if (s_cases < WRITINGS_CASES)
            {
                s_case[s_cases][0] = s_edge_words[word];
                s_case[s_cases][1] = s_edge_counts[count];
                s_cases += 1u;
            }
        }
    }
    unsigned int state = 0x9e3779b9u;
    while (s_cases < WRITINGS_CASES)
    {
        s_case[s_cases][0] = ladder_swept(&state);
        s_case[s_cases][1] = ladder_swept(&state);
        s_cases += 1u;
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

// the operand of `form` that is a number whose field is eight bits wide, a truth table of three inputs, or the operand
// count where none is
static unsigned int writings_table(const SassForm *form)
{
    for (unsigned int operand = 1u; operand < form->operands; operand += 1u)
    {
        unsigned int width = 0u;
        for (unsigned int at = 0u; at < form->runs; at += 1u)
        {
            width += (form->run[at].operand == operand) ? (form->run[at].last - form->run[at].first + 1u) : 0u;
        }
        if ((form->kind[operand] == SASS_OPERAND_IMMEDIATE) && (width == 8u))
        {
            return operand;
        }
    }
    return form->operands;
}

// how many register sources `form` reads: every register operand past its result
static unsigned int writings_sources(const SassForm *form)
{
    unsigned int sources = 0u;
    for (unsigned int operand = 1u; operand < form->operands; operand += 1u)
    {
        sources += (form->kind[operand] == SASS_OPERAND_REGISTER) ? 1u : 0u;
    }
    return sources;
}

// the register source `source` of an assignment, read as a number in base three with the first source its lowest
// digit: 0 is WRITINGS_LEFT, 1 WRITINGS_RIGHT and 2 RZ
static unsigned int writings_digit(unsigned int assignment, unsigned int source)
{
    for (unsigned int at = 0u; at < source; at += 1u)
    {
        assignment /= 3u;
    }
    return assignment % 3u;
}

// the assignment that gives the first register source WRITINGS_LEFT, the second WRITINGS_RIGHT and every one past
// those RZ
static unsigned int writings_in_order(unsigned int sources)
{
    unsigned int assignment = 0u;
    unsigned int place = 1u;
    for (unsigned int source = 0u; source < sources; source += 1u)
    {
        assignment += ((source == 0u) ? 0u : ((source == 1u) ? 1u : 2u)) * place;
        place *= 3u;
    }
    return assignment;
}

// `form`'s own instruction written to `out` with its result moved to WRITINGS_RESULT and each register source given
// WRITINGS_LEFT, WRITINGS_RIGHT or RZ by `assignment` (writings_digit). The operand `table` is written as `value`;
// every other predicate and number keeps the value the form was seen with. 1, or 0 where `out` will not hold it
static int writings_instruction(const SassForm *form, unsigned int table, unsigned int value, unsigned int assignment,
                                char *out, size_t room)
{
    static const char *const s_given[3] = {WRITINGS_LEFT, WRITINGS_RIGHT, "RZ"};
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
            const char *const put = (operand == 0u) ? WRITINGS_RESULT : s_given[writings_digit(assignment, source)];
            source += (operand != 0u) ? 1u : 0u;
            writings_swap(parts.operand[operand], put, text, sizeof(text));
        }
        else if (operand == table)
        {
            snprintf(text, sizeof(text), "0x%02x", value);
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
        fprintf(cases, "%08x %08x\n", s_case[at][0], s_case[at][1]);
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
        // A form holding a truth table is put with every value of it, its sources in order: a table over three inputs
        // already holds every order of them. Any other form is put with every assignment of the two words and RZ to
        // its register sources that gives both words, and with the first word alone where it reads one source
        const unsigned int table = writings_table(form);
        const unsigned int values = (table < form->operands) ? 256u : 1u;
        const unsigned int sources = writings_sources(form);
        unsigned int assignments = 1u;
        for (unsigned int source = 0u; source < sources; source += 1u)
        {
            assignments *= 3u;
        }
        for (unsigned int put = 0u; put < (values * assignments); put += 1u)
        {
            const unsigned int value = put / assignments;
            const unsigned int assignment = put % assignments;
            unsigned int lefts = 0u;
            unsigned int rights = 0u;
            for (unsigned int source = 0u; source < sources; source += 1u)
            {
                lefts += (writings_digit(assignment, source) == 0u) ? 1u : 0u;
                rights += (writings_digit(assignment, source) == 1u) ? 1u : 0u;
            }
            const int in_order = (assignment == writings_in_order(sources));
            const int both = (lefts != 0u) && (rights != 0u);
            if (!in_order && ((table < form->operands) || !both))
            {
                continue;
            }
            char instruction[256];
            char lines[2048];
            if (!writings_instruction(form, table, value, assignment, instruction, sizeof(instruction)) ||
                (snprintf(lines, sizeof(lines), WRITINGS_HEAD "%s" WRITINGS_TAIL, instruction) >= (int)sizeof(lines)) ||
                !writings_splice(s_frame, lines, s_asking, sizeof(s_asking)))
            {
                continue;
            }
            const unsigned int count =
                sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code, sizeof(s_code));
            char cubin[1024];
            snprintf(cubin, sizeof(cubin), "%s/form_%05u.cubin", folder, written);
            if ((count == 0u) || !writings_cubin(count, cubin))
            {
                continue;
            }
            fprintf(list, "%s %s\n", cubin, s_kernel);
            fprintf(forms, "%u\t%s\n", written, instruction);
            written += 1u;
        }
    }
    fclose(cases);
    fclose(list);
    fclose(forms);
    printf("interface sass writings: %u forms of %u fit, %u written and held to cubin_safe, %u cases\n", fitting,
           s_machine.forms, written, s_cases);
    return 0;
}

// the answers `answers` holds, a line a cubin as interface_sass_run writes them, read into `answered`, which holds
// s_cases words a cubin: s_ran set for each cubin that answered every case, and the counts of those that answered and
// those the part refused through `ran` and `refused`
static void writings_answers_read(FILE *answers, unsigned int count, unsigned int (*answered)[WRITINGS_CASES],
                                  unsigned char *ran_one, unsigned int *ran, unsigned int *refused)
{
    char line[WRITINGS_LINE];
    while (fgets(line, sizeof(line), answers) != NULL)
    {
        char *walk = NULL;
        const unsigned long number = strtoul(line, &walk, 10);
        if ((walk == line) || (number >= count))
        {
            continue;
        }
        walk += strspn(walk, " ");
        if (strncmp(walk, "answered", 8u) != 0)
        {
            *refused += 1u;
            continue;
        }
        walk += 8;
        unsigned int read = 0u;
        while ((read < s_cases) && (*walk != '\0'))
        {
            char *next = NULL;
            answered[number][read] = (unsigned int)strtoul(walk, &next, 16);
            if (next == walk)
            {
                break;
            }
            walk = next;
            read += 1u;
        }
        ran_one[number] = (unsigned char)(read == s_cases);
        *ran += (read == s_cases) ? 1u : 0u;
    }
}

// the forms a search wrote, the answers the part gave them, and which relations each form holds
#define WRITINGS_FORMS_MOST 16384u
static char s_forms[WRITINGS_FORMS_MOST][256];
static unsigned int s_form_count;
static unsigned int s_answered[WRITINGS_FORMS_MOST][WRITINGS_CASES];
static unsigned char s_ran[WRITINGS_FORMS_MOST];
static unsigned char s_holds[WRITINGS_FORMS_MOST][WRITINGS_RELATIONS];
static unsigned int s_forms_ran;
static unsigned int s_forms_refused;

// <folder>/forms.txt and <folder>/answers.txt read, and each form that answered held to every relation: 1, or 0
// where either file did not read
static int writings_load(const char *folder)
{
    writings_cases();
    writings_relations();
    char path[1024];
    char line[WRITINGS_LINE];
    snprintf(path, sizeof(path), "%s/forms.txt", folder);
    FILE *const forms = fopen(path, "rb");
    snprintf(path, sizeof(path), "%s/answers.txt", folder);
    FILE *const answers = fopen(path, "rb");
    if ((forms == NULL) || (answers == NULL))
    {
        fprintf(stderr, "the forms or the answers in %s did not read\n", folder);
        return 0;
    }
    s_form_count = 0u;
    while ((s_form_count < WRITINGS_FORMS_MOST) && (fgets(line, sizeof(line), forms) != NULL))
    {
        const char *const tab = strchr(line, '\t');
        if (tab != NULL)
        {
            snprintf(s_forms[s_form_count], sizeof(s_forms[0]), "%.*s", (int)strcspn(tab + 1, "\r\n"), tab + 1);
            s_form_count += 1u;
        }
    }
    fclose(forms);
    s_forms_ran = 0u;
    s_forms_refused = 0u;
    writings_answers_read(answers, s_form_count, s_answered, s_ran, &s_forms_ran, &s_forms_refused);
    fclose(answers);
    for (unsigned int number = 0u; number < s_form_count; number += 1u)
    {
        for (unsigned int relation = 0u; s_ran[number] && (relation < s_relations); relation += 1u)
        {
            unsigned int agreed = 0u;
            for (unsigned int at = 0u; at < s_cases; at += 1u)
            {
                agreed +=
                    (s_answered[number][at] == writings_expected(&s_relation[relation], s_case[at])) ? 1u : 0u;
            }
            s_holds[number][relation] = (unsigned char)(agreed == s_cases);
        }
    }
    return 1;
}

// The answers read back against every relation: the forms that give each relation's every case its word, written to
// `record`. A relation no form gives in one instruction is one the part has no single instruction for, among the forms
// the machine file holds. 0, or 2 where nothing could be read
static int writings_read(const char *folder, const char *record)
{
    FILE *const out = writings_load(folder) ? fopen(record, "wb") : NULL;
    if (out == NULL)
    {
        fprintf(stderr, "the record %s was not written\n", record);
        return 2;
    }
    const unsigned int form_count = s_form_count;
    const unsigned int ran = s_forms_ran;
    const unsigned int refused = s_forms_refused;
    fprintf(out, "# Writings found on the part\n\n");
    fprintf(out, "Written by `interface_sass_writings.sh` whole on every run. Every form of the machine file that writes a "
                 "register from registers, predicates and numbers alone is run on the part in place of the frame's "
                 "IADD3, its first two register sources given each case's two words and every other register source "
                 "RZ. The cases are the ladder's own two-word cases, the words a width turns on against the counts a "
                 "shift turns on, and drawn words, put at once. A form is listed under a ladder relation or a precept "
                 "where it gives every case the word that relation or precept gives it. %u forms ran over %u cases "
                 "and %u were refused by the part.\n\n",
            ran, s_cases, refused);
    unsigned int found_total = 0u;
    for (unsigned int relation = 0u; relation < s_relations; relation += 1u)
    {
        unsigned int found = 0u;
        for (unsigned int number = 0u; number < form_count; number += 1u)
        {
            found += (s_ran[number] && s_holds[number][relation]) ? 1u : 0u;
        }
        fprintf(out, "## %s %s\n\n%u forms give every case its word.\n\n",
                s_relation[relation].precept ? "precept" : "relation", s_relation[relation].name, found);
        for (unsigned int number = 0u; number < form_count; number += 1u)
        {
            if (s_ran[number] && s_holds[number][relation])
            {
                fprintf(out, "- `%s`\n", s_forms[number]);
            }
        }
        fprintf(out, "\n");
        found_total += found;
        printf("  %-8s %-8s %u forms give every case its word\n", s_relation[relation].precept ? "precept" : "relation",
               s_relation[relation].name, found);
    }
    fclose(out);
    printf("interface sass writings: %u forms ran, %u refused, %u writings found, the record written to %s\n", ran,
           refused, found_total, record);
    return 0;
}

// the register each node of a chain writes its word to, the root's being WRITINGS_RESULT, and the register a word of
// ones is set in for a chain that reads one
#define WRITINGS_NODE_FIRST 16u
#define WRITINGS_ONES "R24"
#define WRITINGS_CHAIN_HEAD "IMAD.MOV.U32 R24, RZ, RZ, 4294967295\n"
// the most nodes a chain is written with, and the most chains of a .kdm written
#define WRITINGS_CHAIN_NODES 8u
#define WRITINGS_CHAINS_MOST 8192u

// one node of a chain: its precept, and the register text of each operand, a leaf's or an earlier node's
typedef struct
{
    unsigned int precept;
    char operand[2][8];
} WritingsNode;

// the expression at `*walk`, a leaf or a precept applied to one or two expressions as the .kdm writes a chain, read
// into `nodes` with its children first, its register text into `operand`: 1, or 0 where it does not read
static int writings_chain_read(const char **walk, WritingsNode *nodes, unsigned int *count, char *operand, size_t room)
{
    *walk += strspn(*walk, " ");
    const size_t length = strspn(*walk, "abcdefghijklmnopqrstuvwxyz0123456789");
    char name[16];
    if ((length == 0u) || (length >= sizeof(name)))
    {
        return 0;
    }
    snprintf(name, sizeof(name), "%.*s", (int)length, *walk);
    *walk += length;
    if (**walk != '(')
    {
        const char *const leaves[4][2] = {{"w0", WRITINGS_LEFT}, {"w1", WRITINGS_RIGHT}, {"zero", "RZ"},
                                          {"ones", WRITINGS_ONES}};
        for (unsigned int at = 0u; at < 4u; at += 1u)
        {
            if (strcmp(name, leaves[at][0]) == 0)
            {
                return snprintf(operand, room, "%s", leaves[at][1]) < (int)room;
            }
        }
        return 0;
    }
    unsigned int precept = PRECEPT_COUNT;
    for (unsigned int at = 0u; at < PRECEPT_COUNT; at += 1u)
    {
        precept = (strcmp(name, s_precept_text[at]) == 0) ? at : precept;
    }
    WritingsNode node;
    memset(&node, 0, sizeof(node));
    snprintf(node.operand[1], sizeof(node.operand[1]), "RZ");
    node.precept = precept;
    *walk += 1;
    int read = (precept < PRECEPT_COUNT) &&
               writings_chain_read(walk, nodes, count, node.operand[0], sizeof(node.operand[0]));
    *walk += strspn(*walk, " ");
    if (read && (**walk == ','))
    {
        *walk += 1;
        read = writings_chain_read(walk, nodes, count, node.operand[1], sizeof(node.operand[1]));
        *walk += strspn(*walk, " ");
    }
    if (!read || (**walk != ')') || (*count >= WRITINGS_CHAIN_NODES))
    {
        return 0;
    }
    *walk += 1;
    nodes[*count] = node;
    snprintf(operand, room, "R%u", WRITINGS_NODE_FIRST + (2u * *count));
    *count += 1u;
    return 1;
}

// `writing`, a form as the search put it, written to `out` with its result register WRITINGS_RESULT and its two sources
// WRITINGS_LEFT and WRITINGS_RIGHT replaced by `to`, `left` and `right`, each only where it is a whole register token.
// 1, or 0 where `out` will not hold it
static int writings_put(const char *writing, const char *to, const char *left, const char *right, char *out,
                        size_t room)
{
    const char *const from[3] = {WRITINGS_RESULT, WRITINGS_LEFT, WRITINGS_RIGHT};
    const char *const into[3] = {to, left, right};
    size_t at = 0u;
    const char *walk = writing;
    while ((*walk != '\0') && (at < room))
    {
        const int starts = (*walk == 'R') && ((walk == writing) || (strchr(" ,[-~!", walk[-1]) != NULL));
        unsigned int which = 3u;
        for (unsigned int one = 0u; starts && (one < 3u); one += 1u)
        {
            const size_t length = strlen(from[one]);
            if ((strncmp(walk, from[one], length) == 0) && ((walk[length] < '0') || (walk[length] > '9')))
            {
                which = one;
            }
        }
        if (which < 3u)
        {
            at += (size_t)snprintf(&out[at], room - at, "%s", into[which]);
            walk += strlen(from[which]);
            continue;
        }
        out[at] = *walk;
        at += 1u;
        walk += 1;
    }
    if (at >= room)
    {
        return 0;
    }
    out[at] = '\0';
    return 1;
}

// the first form the search found holding `precept`, by its number among the forms, or s_form_count where none does
static unsigned int writings_for(unsigned int precept)
{
    unsigned int relation = s_relations;
    for (unsigned int at = 0u; at < s_relations; at += 1u)
    {
        relation = (s_relation[at].precept && (s_relation[at].which == precept)) ? at : relation;
    }
    for (unsigned int number = 0u; (relation < s_relations) && (number < s_form_count); number += 1u)
    {
        if (s_ran[number] && s_holds[number][relation])
        {
            return number;
        }
    }
    return s_form_count;
}

// Every chain of the .kdm at `kdm` written into a cubin of its own, each node the first writing the search found for
// its precept, with <folder>/chains/list.txt and <folder>/chains/chains.txt beside them: 0, or 2 where nothing could be
// read or written
static int writings_chains_write(const char *pattern, const char *frame, const char *machine, const char *folder,
                                 const char *kdm)
{
    s_pattern_size = writings_file_read(pattern, s_pattern, sizeof(s_pattern));
    const unsigned long long frame_size = writings_file_read(frame, (unsigned char *)s_frame, sizeof(s_frame) - 1u);
    s_frame[frame_size] = '\0';
    if ((s_pattern_size == 0ull) || (frame_size == 0ull) || !writings_kernel(s_frame, s_kernel, sizeof(s_kernel)) ||
        !sass_machine_read(&s_machine, machine) || !writings_load(folder))
    {
        fprintf(stderr, "the pattern, the frame, the machine file or the search in %s did not read\n", folder);
        return 2;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/chains/list.txt", folder);
    FILE *const list = fopen(path, "wb");
    snprintf(path, sizeof(path), "%s/chains/chains.txt", folder);
    FILE *const chains = fopen(path, "wb");
    FILE *const rows = fopen(kdm, "rb");
    if ((list == NULL) || (chains == NULL) || (rows == NULL))
    {
        fprintf(stderr, "the folder %s/chains or the .kdm %s was not reached\n", folder, kdm);
        return 2;
    }
    for (unsigned int precept = 0u; precept < PRECEPT_COUNT; precept += 1u)
    {
        const unsigned int writing = writings_for(precept);
        if (writing < s_form_count)
        {
            printf("  %-4s %s\n", s_precept_text[precept], s_forms[writing]);
        }
    }
    char line[WRITINGS_LINE];
    unsigned int read = 0u;
    unsigned int unwritten = 0u;
    unsigned int written = 0u;
    while ((written < WRITINGS_CHAINS_MOST) && (fgets(line, sizeof(line), rows) != NULL))
    {
        char operator_name[32];
        unsigned int nodes_said = 0u;
        char chain[512];
        if ((line[0] == '#') || (sscanf(line, "%31[^\t]\t%u\t%511[^\t]", operator_name, &nodes_said, chain) != 3) ||
            (nodes_said == 0u))
        {
            continue;
        }
        read += 1u;
        WritingsNode nodes[WRITINGS_CHAIN_NODES];
        unsigned int count = 0u;
        char root[8];
        const char *walk = chain;
        int fits = writings_chain_read(&walk, nodes, &count, root, sizeof(root)) && (count != 0u);
        char lines[4096];
        size_t at = (size_t)snprintf(lines, sizeof(lines), WRITINGS_HEAD WRITINGS_CHAIN_HEAD);
        for (unsigned int node = 0u; fits && (node < count); node += 1u)
        {
            const unsigned int writing = writings_for(nodes[node].precept);
            char to[8];
            snprintf(to, sizeof(to), "R%u", WRITINGS_NODE_FIRST + (2u * node));
            char put[256];
            fits = (writing < s_form_count) &&
                   writings_put(s_forms[writing], (node + 1u == count) ? WRITINGS_RESULT : to, nodes[node].operand[0],
                                nodes[node].operand[1], put, sizeof(put)) &&
                   ((at += (size_t)snprintf(&lines[at], sizeof(lines) - at, "%s%s", (node == 0u) ? "" : "\n", put)) <
                    sizeof(lines));
        }
        fits = fits && (snprintf(&lines[at], sizeof(lines) - at, WRITINGS_TAIL) < (int)(sizeof(lines) - at)) &&
               writings_splice(s_frame, lines, s_asking, sizeof(s_asking));
        const unsigned int instructions =
            fits ? sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code, sizeof(s_code)) : 0u;
        char cubin[1024];
        snprintf(cubin, sizeof(cubin), "%s/chains/chain_%05u.cubin", folder, written);
        if ((instructions == 0u) || !writings_cubin(instructions, cubin))
        {
            unwritten += 1u;
            continue;
        }
        fprintf(list, "%s %s\n", cubin, s_kernel);
        fprintf(chains, "%u\t%s\t%s\n", written, operator_name, chain);
        written += 1u;
    }
    fclose(rows);
    fclose(list);
    fclose(chains);
    printf("interface sass chains: %u chains of the .kdm read, %u written and held to cubin_safe, %u not written\n", read,
           written, unwritten);
    return 0;
}

// The chains' answers read back against the relation each chain is a row of, written to `record`: 0, or 2 where
// nothing could be read
static int writings_chains_read(const char *folder, const char *record)
{
    writings_cases();
    static char s_chain[WRITINGS_CHAINS_MOST][512];
    static unsigned int s_chain_anchor[WRITINGS_CHAINS_MOST];
    static unsigned int s_chain_answered[WRITINGS_CHAINS_MOST][WRITINGS_CASES];
    static unsigned char s_chain_ran[WRITINGS_CHAINS_MOST];
    char path[1024];
    char line[WRITINGS_LINE];
    snprintf(path, sizeof(path), "%s/chains/chains.txt", folder);
    FILE *const chains = fopen(path, "rb");
    snprintf(path, sizeof(path), "%s/chains/answers.txt", folder);
    FILE *const answers = fopen(path, "rb");
    FILE *const out = fopen(record, "wb");
    if ((chains == NULL) || (answers == NULL) || (out == NULL))
    {
        fprintf(stderr, "the chains, their answers in %s or the record %s was not reached\n", folder, record);
        return 2;
    }
    unsigned int count = 0u;
    while ((count < WRITINGS_CHAINS_MOST) && (fgets(line, sizeof(line), chains) != NULL))
    {
        unsigned int number = 0u;
        char operator_name[32];
        if (sscanf(line, "%u\t%31[^\t]\t%511[^\r\n]", &number, operator_name, s_chain[count]) != 3)
        {
            continue;
        }
        s_chain_anchor[count] = LADDER_ANCHOR_COUNT;
        for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
        {
            s_chain_anchor[count] = (strcmp(operator_name, s_anchor_text[anchor]) == 0) ? anchor : s_chain_anchor[count];
        }
        count += 1u;
    }
    fclose(chains);
    unsigned int ran = 0u;
    unsigned int refused = 0u;
    writings_answers_read(answers, count, s_chain_answered, s_chain_ran, &ran, &refused);
    fclose(answers);
    unsigned int put[LADDER_ANCHOR_COUNT] = {0u};
    unsigned int held[LADDER_ANCHOR_COUNT] = {0u};
    fprintf(out, "# Chains run on the part\n\n");
    fprintf(out, "Written by `interface_sass_writings.sh` whole on every run. Every arrangement of the part's .kdm is "
                 "written node by node, each node the first writing `interface_sass_writings.md` found for its "
                 "precept, run on the part over the search's cases, and read back against the relation the "
                 "arrangement is a row of. %u chains ran and %u were refused by the part.\n\n",
            ran, refused);
    fprintf(out, "## Chains that did not answer as their relation\n\n");
    unsigned int differed = 0u;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        const unsigned int anchor = s_chain_anchor[number];
        if (!s_chain_ran[number] || (anchor >= LADDER_ANCHOR_COUNT))
        {
            continue;
        }
        unsigned int agreed = 0u;
        for (unsigned int at = 0u; at < s_cases; at += 1u)
        {
            unsigned int expected = 0u;
            ladder_answer(anchor, s_case[at], 2u, &expected);
            agreed += (s_chain_answered[number][at] == expected) ? 1u : 0u;
        }
        put[anchor] += 1u;
        held[anchor] += (agreed == s_cases) ? 1u : 0u;
        if (agreed != s_cases)
        {
            fprintf(out, "- %s `%s`: %u of %u cases\n", s_anchor_text[anchor], s_chain[number], agreed, s_cases);
            differed += 1u;
        }
    }
    fprintf(out, "%s\n## By relation\n\n| relation | chains run | answering every case |\n|---|---|---|\n",
            (differed == 0u) ? "None.\n" : "");
    for (unsigned int anchor = 0u; anchor < LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        if (put[anchor] != 0u)
        {
            fprintf(out, "| %s | %u | %u |\n", s_anchor_text[anchor], put[anchor], held[anchor]);
            printf("  %-8s %u chains run, %u answering every case\n", s_anchor_text[anchor], put[anchor], held[anchor]);
        }
    }
    fclose(out);
    printf("interface sass chains: %u ran, %u refused, %u answered otherwise than their relation, the record written to "
           "%s\n",
           ran, refused, differed, record);
    return 0;
}

int main(int count, char **words)
{
    if ((count == 7) && (strcmp(words[1], "chains") == 0))
    {
        return writings_chains_write(words[2], words[3], words[4], words[5], words[6]);
    }
    if ((count == 4) && (strcmp(words[1], "chains-read") == 0))
    {
        return writings_chains_read(words[2], words[3]);
    }
    if ((count == 4) && (strcmp(words[1], "read") == 0))
    {
        return writings_read(words[2], words[3]);
    }
    if (count != 5)
    {
        fprintf(stderr, "interface_sass_writings <pattern cubin> <frame text> <machine file> <folder>\n"
                        "interface_sass_writings read <folder> <record>\n"
                        "interface_sass_writings chains <pattern cubin> <frame text> <machine file> <folder> <kdm>\n"
                        "interface_sass_writings chains-read <folder> <record>\n");
        return 2;
    }
    return writings_write(words[1], words[2], words[3], words[4]);
}
