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
#include "interface_sass_probe.h"

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
// each operation key, the low word's bits the sweep puts every value of: whether the machine file holds a form under
// it, and whether any form it holds there transfers control or waits
static unsigned char s_key_known[SASS_OPERATION_MASK + 1u];
static unsigned char s_key_control[SASS_OPERATION_MASK + 1u];

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

// 1 where the operation transfers control or waits, which run on the part can loop or stall it: a branch, a call, a
// return, a barrier, a sleep and a trap are each held off the part, since a turned bit that writes one is run as it is
// and not refused. A straight instruction falls through to the next and cannot loop by itself
static int fields_control_or_wait(const char *operation)
{
    static const char *const unsafe[] = {"BRA",  "BRX",       "JMP", "JMX",    "CALL",   "RET",
                                         "EXIT", "BSSY",      "BSYNC", "BREAK", "BMOV",   "WARPSYNC",
                                         "YIELD", "BAR",      "DEPBAR", "NANOSLEEP", "BPT", "RTT",
                                         "KILL", "RPCMOV",    "RETIRE", "PMTRIG"};
    for (unsigned int at = 0u; at < (sizeof(unsafe) / sizeof(unsafe[0])); at += 1u)
    {
        if (strncmp(operation, unsafe[at], strlen(unsafe[at])) == 0)
        {
            return 1;
        }
    }
    return 0;
}

// the key table filled from the machine file's forms: a key is known where any form sits under it, and control where
// any form under it transfers control or waits. The sweep put every key to the disassembler from each of several
// carriers, and the file holds every operation a key named there. The counts go to the standard output
static void fields_keys(void)
{
    unsigned int known = 0u;
    unsigned int control = 0u;
    for (unsigned int at = 0u; at < s_machine.forms; at += 1u)
    {
        const unsigned long long key = s_machine.form[at].low & SASS_OPERATION_MASK;
        known += (s_key_known[key] == 0u) ? 1u : 0u;
        s_key_known[key] = 1u;
        if (fields_control_or_wait(s_machine.form[at].operation) && (s_key_control[key] == 0u))
        {
            s_key_control[key] = 1u;
            control += 1u;
        }
    }
    printf("operation keys: %u known, %u holding a control or wait form\n", known, control);
}

// 1 where the instruction at `place` in s_code, turned at `bit`, is safe to run on the part. The operation key names
// the operation, and the turned encoding is run only where the machine file holds forms under its key and no control
// transfer or wait among them: such an instruction falls through whatever its other bits hold, and cannot loop or
// stall the part. A turn past the key leaves the key, and the instruction's own operation, as they were. `name` takes
// the operation the turned encoding reads back as, or the key where no form reads it back. A `bit` of 128 turns nothing
static int fields_flip_safe(unsigned int place, unsigned int bit, char *name, size_t room)
{
    unsigned long long low = fields_word_read(&s_code[16u * place]);
    unsigned long long high = fields_word_read(&s_code[(16u * place) + 8u]);
    if (bit < 64u)
    {
        low ^= 1ull << bit;
    }
    else if (bit < 128u)
    {
        high ^= 1ull << (bit - 64u);
    }
    const unsigned long long key = low & SASS_OPERATION_MASK;
    char text[256];
    if (sass_encoding_read(&s_machine, low, high, 0ull, text, sizeof(text)))
    {
        SassInstructionParts parts;
        sass_instruction_read(text, &parts);
        snprintf(name, room, "%s", parts.operation);
    }
    else
    {
        snprintf(name, room, "key_0x%03llx", key);
    }
    return (s_key_known[key] != 0u) && (s_key_control[key] == 0u);
}

// the lines a form is run in: the instruction with its result moved to R8, the register the frame stores as the answer,
// and its source registers moved to R10 up. Each source register is set to a distinct value with a zero beside it:
// turning a bit of a source's field reaches a register of another value and changes the answer. R6 keeps the case's
// second word, which the frame leaves in R7
#define FIELDS_LINES_HEAD                                                                                              \
    "MOV R10, 0xb\nMOV R11, RZ\nMOV R12, 0x7\nMOV R13, RZ\nMOV R14, 0x3\nMOV R15, RZ\n"                                \
    "MOV R16, 0x5\nMOV R17, RZ\nMOV R18, 0x2\nMOV R19, RZ\nMOV R20, 0x9\nMOV R21, RZ\n"                                \
    "IMAD.MOV.U32 R6, RZ, RZ, R7\n"
#define FIELDS_LINES_TAIL "\nIMAD.MOV.U32 R7, RZ, RZ, R8\nSTG.E term[UR4][R4.64], R7"
// the line after a form that sets a predicate, its first operand moved to P0: R8 takes R12's 0x7 where P0 holds and
// R10's 0xb where it does not, which carries the predicate to the answer as one of two values
#define FIELDS_LINES_PREDICATE "\nSEL R8, R12, R10, P0"
// the registers a form's source operands are moved onto, in order, each set in the head above
#define FIELDS_SOURCES 6u

// the first instruction of the file at `path` that is a form to probe, into `instruction`: 1, or 0 where the file
// holds none. The frame's own IADD3 and blank lines are passed over, as the write pass passes them
static int fields_first(const char *path, char *instruction, size_t room)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    char line[512];
    int found = 0;
    while (!found && (fgets(line, sizeof(line), file) != NULL))
    {
        line[strcspn(line, "\r\n")] = '\0';
        const char *const walk = line + strspn(line, " \t");
        if ((*walk != '\0') && (strncmp(walk, "IADD3 R8", 8u) != 0))
        {
            found = snprintf(instruction, room, "%s", walk) < (int)room;
        }
    }
    fclose(file);
    return found;
}

// the operand whose run covers operation bit `bit` in `form`, or the operand count where none does
static unsigned int fields_operand_at(const SassForm *form, unsigned int bit)
{
    for (unsigned int at = 0u; at < form->runs; at += 1u)
    {
        if ((bit >= form->run[at].first) && (bit <= form->run[at].last))
        {
            return form->run[at].operand;
        }
    }
    return form->operands;
}

// the answers interface_sass_run wrote for the write pass's cubins, read against the form the first instruction holds
// and labeled a bit a row to `record`. A bit the part refused, one it read inside a run the machine file records for
// an operand, one it read outside every recorded run, and one it left the answer unchanged are told apart
static int fields_read(const char *machine_path, const char *instructions, const char *answers, const char *record)
{
    if (!sass_machine_read(&s_machine, machine_path))
    {
        fprintf(stderr, "the machine file %s did not read\n", machine_path);
        return 2;
    }
    char instruction[512];
    if (!fields_first(instructions, instruction, sizeof(instruction)))
    {
        fprintf(stderr, "the instructions %s hold no form\n", instructions);
        return 2;
    }
    SassInstructionParts parts;
    sass_instruction_read(instruction, &parts);
    const SassForm *const form = sass_machine_form(&s_machine, &parts);
    if (form == NULL)
    {
        fprintf(stderr, "the machine file holds no form for %s\n", instruction);
        return 2;
    }
    FILE *const in = fopen(answers, "rb");
    FILE *const out = fopen(record, "wb");
    if ((in == NULL) || (out == NULL))
    {
        fprintf(stderr, "the answers %s or the record %s was not reached\n", answers, record);
        return 2;
    }
    fprintf(out, "# A form's fields, found on the part\n\n");
    fprintf(out, "Written by `interface_sass_probe_fields read`. The form is `%s`. Each row is one of its operation "
                 "bits turned over and run on the part, against the answer the form gives untouched. A bit the part "
                 "refuses, one it reads inside a run the machine file records for an operand, one it reads outside "
                 "every recorded run, and one that leaves the answer unchanged are told apart. A bit held off the "
                 "part, whose turned operation key holds a control transfer, a wait or no form in the machine file, "
                 "is marked skipped and run on nothing.\n\n",
            instruction);
    fprintf(out, "| bit | operand | part |\n|---|---|---|\n");
    char line[256];
    char hidden_bits[512] = "";
    unsigned long long baseline = 0ull;
    int have_baseline = 0;
    unsigned int refused = 0u;
    unsigned int inside = 0u;
    unsigned int hidden = 0u;
    unsigned int unread = 0u;
    while (fgets(line, sizeof(line), in) != NULL)
    {
        unsigned int number = 0u;
        char kind[64];
        char word[64];
        if (sscanf(line, "%u %63s %63s", &number, kind, word) < 2)
        {
            continue;
        }
        if (number == 0u)
        {
            have_baseline = (strcmp(kind, "answered") == 0) && (sscanf(word, "%llx", &baseline) == 1);
            continue;
        }
        const unsigned int bit = number - 1u;
        const unsigned int operand = fields_operand_at(form, bit);
        const int in_run = (operand < form->operands);
        char place[32];
        if (in_run)
        {
            snprintf(place, sizeof(place), "%u", operand);
        }
        else
        {
            snprintf(place, sizeof(place), "-");
        }
        const char *part = NULL;
        if ((strcmp(kind, "refused") == 0) || (strcmp(kind, "hung") == 0) || (strcmp(kind, "skipped") == 0))
        {
            // a bit the part refused, one it ran too long on, and one held off the part as unsafe to run are each no
            // operand field; they share the first column and the row says which
            refused += 1u;
            part = (kind[0] == 'h') ? "hung" : ((kind[0] == 's') ? "skipped" : "refused");
        }
        else
        {
            unsigned long long answered = 0ull;
            const int read = have_baseline && (sscanf(word, "%llx", &answered) == 1) && (answered != baseline);
            if (!read)
            {
                unread += 1u;
                part = "unread";
            }
            else if (in_run)
            {
                inside += 1u;
                part = "read";
            }
            else
            {
                hidden += 1u;
                part = "read, no recorded run";
                const size_t at = strlen(hidden_bits);
                snprintf(&hidden_bits[at], sizeof(hidden_bits) - at, "%s%u", (at == 0u) ? "" : " ", bit);
            }
        }
        fprintf(out, "| %u | %s | %s |\n", bit, place, part);
    }
    fprintf(out, "\n%u refused, %u read inside a recorded run, %u read outside every recorded run, %u unread.\n",
            refused, inside, hidden, unread);
    fclose(in);
    fclose(out);
    // a tab-delimited line the gathering script turns into one row: the form, its counts, and the bits it reads that
    // the machine file records for no operand
    printf("FORMFIELDS\t%s\t%u\t%u\t%u\t%u\t%s\n", instruction, refused, inside, hidden, unread, hidden_bits);
    return 0;
}

// 1 where the operation writes its first register operand, which the redirect may move to the observed register. A
// return, a register branch or a call reads its first register instead and leaves it where it stands; a store, a branch
// to a label and a predicate setter carry no register first operand and never reach here
static int fields_writes_first(const char *operation)
{
    static const char *const reads[] = {"RET", "BRX", "JMX", "CALL", "BRA", "JMP", "EXIT", "BAR", "NOP"};
    for (unsigned int at = 0u; at < (sizeof(reads) / sizeof(reads[0])); at += 1u)
    {
        if (strncmp(operation, reads[at], strlen(reads[at])) == 0)
        {
            return 0;
        }
    }
    return 1;
}

// the sign an operand carries back as its text, since the parts reader cuts it off: the negate, the bitwise not and the
// predicate not, or nothing
static const char *fields_mark(unsigned int mark)
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

// `operand`, which begins with a register token (R then digits, or RZ), written to `out` with that token replaced by
// `put`. A .hi names the second register of a pair and leaves the operand a register of the same form: it is dropped,
// and `put` itself is the register read or written. Any other suffix is kept
static void fields_swap(const char *operand, const char *put, char *out, size_t room)
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

// `instruction` written to `redirected`, rebuilt from its parts, with its first operand moved where the frame reads it
// and each source register operand moved to the next of the head's set registers, where the form's result and its
// source fields reach the answer. A first operand that is a register moves to R8, the register the frame stores as the
// answer. A first operand that is a predicate moves to P0, and `observe` takes the line that turns P0 into a value in
// R8; it is left empty otherwise. A form whose first operand is neither, or is one the operation reads, is copied as it
// stands, since nothing of it would be observed through R8. 1, or 0 where `redirected` or `observe` will not hold it
static int fields_redirect(const char *instruction, char *redirected, size_t room, char *observe, size_t observe_room)
{
    static const char *const sources[FIELDS_SOURCES] = {"R10", "R12", "R14", "R16", "R18", "R20"};
    SassInstructionParts parts;
    sass_instruction_read(instruction, &parts);
    observe[0] = '\0';
    const int writes_register = (parts.operands != 0u) && (parts.kind[0] == SASS_OPERAND_REGISTER);
    const int writes_predicate = (parts.operands != 0u) && (parts.kind[0] == SASS_OPERAND_PREDICATE);
    if ((!writes_register && !writes_predicate) || !fields_writes_first(parts.operation))
    {
        return snprintf(redirected, room, "%s", instruction) < (int)room;
    }
    if (writes_predicate && (snprintf(observe, observe_room, "%s", FIELDS_LINES_PREDICATE) >= (int)observe_room))
    {
        return 0;
    }
    size_t at = 0u;
    if (parts.guard[0] != '\0')
    {
        at += (size_t)snprintf(&redirected[at], (at < room) ? (room - at) : 0u, "%s ", parts.guard);
    }
    at += (size_t)snprintf(&redirected[at], (at < room) ? (room - at) : 0u, "%s", parts.operation);
    unsigned int source = 0u;
    for (unsigned int operand = 0u; operand < parts.operands; operand += 1u)
    {
        char text[SASS_MACHINE_TOKEN];
        const char *put = NULL;
        if (parts.kind[operand] == SASS_OPERAND_REGISTER)
        {
            if (operand == 0u)
            {
                put = "R8";
            }
            else if (source < FIELDS_SOURCES)
            {
                put = sources[source];
                source += 1u;
            }
        }
        if ((operand == 0u) && writes_predicate)
        {
            snprintf(text, sizeof(text), "P0");
        }
        else if (put != NULL)
        {
            fields_swap(parts.operand[operand], put, text, sizeof(text));
        }
        else
        {
            snprintf(text, sizeof(text), "%s", parts.operand[operand]);
        }
        at += (size_t)snprintf(&redirected[at], (at < room) ? (room - at) : 0u, "%s%s%s", (operand == 0u) ? " " : ", ",
                               fields_mark(parts.mark[operand]), text);
    }
    return at < room;
}

int main(int count, char **words)
{
    if ((count == 6) && (strcmp(words[1], "read") == 0))
    {
        return fields_read(words[2], words[3], words[4], words[5]);
    }
    if (count != 6)
    {
        fprintf(stderr,
                "interface_sass_probe_fields <pattern cubin> <frame text> <machine file> <folder> <instructions>\n"
                "interface_sass_probe_fields read <machine file> <instructions> <answers> <record>\n");
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
    fields_keys();
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
        // the first operand moved to R8, the register the frame stores as the answer, which then holds what the form
        // writes
        char redirected[512];
        char observe[64];
        if (!fields_redirect(walk, redirected, sizeof(redirected), observe, sizeof(observe)))
        {
            printf("skip %s: could not be redirected\n", walk);
            continue;
        }
        char lines[1024];
        snprintf(lines, sizeof(lines), FIELDS_LINES_HEAD "%s%s" FIELDS_LINES_TAIL, redirected, observe);
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        const unsigned int assembled = fields_splice(s_frame, lines, s_asking, sizeof(s_asking))
                                           ? sass_assemble_lines(&s_machine, s_asking, SASS_CONTROL_SAFE, s_code,
                                                                 sizeof(s_code))
                                           : 0u;
        const int alone =
            (assembled != 0u) && sass_assemble(&s_machine, redirected, 0ull, 0ull, SASS_CONTROL_SAFE, &low, &high);
        const unsigned int place = alone ? fields_find(s_code, assembled, low, high) : assembled;
        if (place == assembled)
        {
            printf("skip %s: did not assemble or was not found once\n", walk);
            continue;
        }
        char path[1024];
        snprintf(path, sizeof(path), "%s/list.txt", folder);
        FILE *const made = fopen(path, "wb");
        // the baseline first, its bit 128 turning nothing, then one line an operation bit. A bit whose turned operation
        // key holds a control transfer, a wait or no form is held off the part with a skip line in its place: a
        // bit-flip never loops or stalls the part, and the line order still names the bit a row belongs to
        for (unsigned int bit = 0u; bit <= FIELDS_OPERATION_BITS; bit += 1u)
        {
            const unsigned int turned = (bit == 0u) ? 128u : (bit - 1u);
            char name[64];
            char cubin[1024];
            snprintf(cubin, sizeof(cubin), "%s/bit_%03u.cubin", folder, bit);
            const int safe = fields_flip_safe(place, turned, name, sizeof(name));
            if (safe && fields_cubin(s_code, assembled, place, turned, cubin))
            {
                if (made != NULL)
                {
                    fprintf(made, "%s %s\n", cubin, s_kernel);
                }
            }
            else if (made != NULL)
            {
                fprintf(made, "skip %s\n", name);
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
