// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_main.c: each form's operations, each operation's fields, and main. The first argument is
// cell_ptx_probe's path, the second a folder for the cubins, listings and decodings. Exit 0 where every cubin was
// listed and every operation decoded, 1 where one was not, 2 where the probe could not ask at all
#include "cell_sass_probe.h"

#include <stdlib.h>
#include <string.h>

// the most questions and the most operations the probe keeps, and the longest question name
#define SASS_QUESTIONS 256u
#define SASS_OPERATIONS 512u
#define SASS_NAME 160u
// the bits of the low word that name an operation and its operands' kinds
#define SASS_OPERATION_MASK 0xfffull
// the longest category and example a bit's reading is given
#define SASS_CATEGORY 32u
#define SASS_EXAMPLE 160u

// one operation the listings hold, keyed by the low 12 bits of its encoding: the first instruction seen with it
typedef struct
{
    unsigned int key;
    SassInstruction first;
} SassOperation;

typedef struct
{
    const char *folder;
    const char *prober;
    char architecture[16];
    unsigned int questions;
    char names[SASS_QUESTIONS][SASS_NAME];
    unsigned int operations;
    SassOperation operation[SASS_OPERATIONS];
    unsigned int failed;
} SassProbe;

static SassProbe s_sass_probe;
static SassMachine s_sass_machine;
static SassListing s_sass_frame;
static SassListing s_sass_form;
static char s_sass_texts[SASS_ENCODINGS][SASS_TEXT];

// `name`.cubin in the folder listed with its encodings into `listing`, the listing written to `name`.sass, and the
// whole ELF read by cuobjdump -elf into `name`.elf: 1, or 0 with the reason printed
static int sass_list(SassProbe *probe, const char *name, SassListing *listing)
{
    char cubin[1024];
    char output[1024];
    snprintf(cubin, sizeof(cubin), "%s/%s.cubin", probe->folder, name);
    snprintf(output, sizeof(output), "%s/%s.sass", probe->folder, name);
    char *const command[] = {"nvdisasm", "-c", "-hex", cubin, NULL};
    const int status = sass_run(command, output);
    if (status != 0)
    {
        printf("  %s: nvdisasm exited %d\n%s", name, status, (status > 0) ? sass_output() : "");
        return 0;
    }
    if (!sass_listing_read(sass_output(), listing))
    {
        printf("  %s: more than %u instructions\n", name, SASS_LISTING_LIMIT);
        return 0;
    }
    // the rest of the cubin as cuobjdump reads it: its sections, symbols, segments and the kernel's attributes
    snprintf(output, sizeof(output), "%s/%s.elf", probe->folder, name);
    char *const elf[] = {"cuobjdump", "-elf", cubin, NULL};
    const int elf_status = sass_run(elf, output);
    if (elf_status != 0)
    {
        printf("  %s: cuobjdump exited %d\n%s", name, elf_status, (elf_status > 0) ? sass_output() : "");
        return 0;
    }
    return 1;
}

// each instruction of the listing whose operation is not yet kept, kept
static void sass_operations_take(SassProbe *probe, const SassListing *listing)
{
    for (unsigned int number = 0u; number < listing->count; number += 1u)
    {
        const SassInstruction *const instruction = &listing->instructions[number];
        // the key is the low 12 bits of the word, which fit an unsigned int
        const unsigned int key = (unsigned int)(instruction->low & SASS_OPERATION_MASK);
        int known = 0;
        for (unsigned int kept = 0u; kept < probe->operations; kept += 1u)
        {
            known = known || (probe->operation[kept].key == key);
        }
        if (!known && (probe->operations < SASS_OPERATIONS))
        {
            probe->operation[probe->operations].key = key;
            probe->operation[probe->operations].first = *instruction;
            probe->operations += 1u;
        }
    }
}

// how many instructions of the listing have the operation
static unsigned int sass_operation_count(const SassListing *listing, const char *operation)
{
    unsigned int found = 0u;
    for (unsigned int number = 0u; number < listing->count; number += 1u)
    {
        SassParts parts;
        sass_parts_read(listing->instructions[number].text, &parts);
        found += (strcmp(parts.operation, operation) == 0) ? 1u : 0u;
    }
    return found;
}

// the operations the form's listing holds more of than the frame's, each once with how many more, and those it holds
// fewer of
static void sass_form_print(const char *name, const SassListing *form, const SassListing *frame)
{
    printf("form %s:", name);
    for (int more = 1; more >= 0; more -= 1)
    {
        const SassListing *const counted = more ? form : frame;
        const SassListing *const against = more ? frame : form;
        printf("%s", more ? "" : " |");
        for (unsigned int number = 0u; number < counted->count; number += 1u)
        {
            SassParts parts;
            sass_parts_read(counted->instructions[number].text, &parts);
            int earlier = 0;
            for (unsigned int before = 0u; before < number; before += 1u)
            {
                SassParts other;
                sass_parts_read(counted->instructions[before].text, &other);
                earlier = earlier || (strcmp(other.operation, parts.operation) == 0);
            }
            const unsigned int here = sass_operation_count(counted, parts.operation);
            const unsigned int there = sass_operation_count(against, parts.operation);
            // NOP fills the code to its alignment and is none of a form's
            if (!earlier && (here > there) && (strcmp(parts.operation, "NOP") != 0))
            {
                printf(" %s%s x%u", more ? "" : "-", parts.operation, here - there);
            }
        }
    }
    printf("\n");
}

// what turning one bit over did to the base's text: its category and an example of the change
static void sass_bit_read(const SassParts *base, const char *base_text, const char *text, char *category, char *example)
{
    SassParts parts;
    sass_parts_read(text, &parts);
    snprintf(example, SASS_EXAMPLE, "%s", text);
    if ((strcmp(text, "illegal") == 0) || (strcmp(text, "unprinted") == 0))
    {
        snprintf(category, SASS_CATEGORY, "%s", text);
        return;
    }
    if (strcmp(text, base_text) == 0)
    {
        snprintf(category, SASS_CATEGORY, "unchanged");
        return;
    }
    if (strcmp(parts.operation, base->operation) != 0)
    {
        const size_t stem = strcspn(base->operation, ".");
        const int same_stem =
            (strcspn(parts.operation, ".") == stem) && (strncmp(parts.operation, base->operation, stem) == 0);
        snprintf(category, SASS_CATEGORY, "%s", same_stem ? "modifier" : "operation");
        snprintf(example, SASS_EXAMPLE, "%s -> %s", base->operation, parts.operation);
        return;
    }
    if (strcmp(parts.predicate, base->predicate) != 0)
    {
        snprintf(category, SASS_CATEGORY, "predicate");
        snprintf(example, SASS_EXAMPLE, "'%s' -> '%s'", base->predicate, parts.predicate);
        return;
    }
    unsigned int changed = 0u;
    unsigned int which = 0u;
    for (unsigned int operand = 0u; (operand < parts.operands) && (operand < base->operands); operand += 1u)
    {
        if (strcmp(parts.operand[operand], base->operand[operand]) != 0)
        {
            changed += 1u;
            which = operand;
        }
    }
    if ((parts.operands == base->operands) && (changed == 1u))
    {
        snprintf(category, SASS_CATEGORY, "operand %u", which);
        snprintf(example, SASS_EXAMPLE, "%s -> %s", base->operand[which], parts.operand[which]);
        return;
    }
    snprintf(category, SASS_CATEGORY, "operands");
}

// the operation's 128 bits turned over one at a time and decoded: each run of bits of one category printed, and each
// bit's reading written to opcode_<key>.bits in the folder. 1, or 0 where the disassembler failed
static int sass_fields(SassProbe *probe, const SassOperation *operation)
{
    unsigned long long low[SASS_ENCODINGS];
    unsigned long long high[SASS_ENCODINGS];
    low[0] = operation->first.low;
    high[0] = operation->first.high;
    for (unsigned int bit = 0u; bit < SASS_BITS; bit += 1u)
    {
        low[1u + bit] = low[0] ^ ((bit < 64u) ? (1ull << bit) : 0ull);
        high[1u + bit] = high[0] ^ ((bit >= 64u) ? (1ull << (bit - 64u)) : 0ull);
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/opcode_%03x", probe->folder, operation->key);
    printf("operation %03x: %s (0x%016llx 0x%016llx)\n", operation->key, operation->first.text, low[0], high[0]);
    if (!sass_decode(probe->architecture, path, low, high, SASS_ENCODINGS, s_sass_texts))
    {
        printf("  not decoded\n");
        return 0;
    }
    SassParts base;
    sass_parts_read(s_sass_texts[0], &base);
    snprintf(path, sizeof(path), "%s/opcode_%03x.bits", probe->folder, operation->key);
    FILE *const bits = fopen(path, "w");
    if (bits != NULL)
    {
        fprintf(bits, "base: %s\n", s_sass_texts[0]);
    }
    char run_category[SASS_CATEGORY] = "";
    char run_example[SASS_EXAMPLE] = "";
    unsigned int run_start = 0u;
    for (unsigned int bit = 0u; bit <= SASS_BITS; bit += 1u)
    {
        char category[SASS_CATEGORY] = "";
        char example[SASS_EXAMPLE] = "";
        if (bit < SASS_BITS)
        {
            sass_bit_read(&base, s_sass_texts[0], s_sass_texts[1u + bit], category, example);
            if (bits != NULL)
            {
                fprintf(bits, "bit %u: %s: %s\n", bit, category, s_sass_texts[1u + bit]);
            }
        }
        // a modifier bit is a run of its own, since each names a modifier of its own
        const int joined = (bit < SASS_BITS) && (bit != 0u) && (strcmp(category, run_category) == 0) &&
                           (strcmp(category, "modifier") != 0) && (bit != 64u);
        if (!joined && (bit != 0u))
        {
            printf("  bits %3u-%3u %s: %s\n", run_start, bit - 1u, run_category, run_example);
        }
        if (!joined)
        {
            run_start = bit;
            memcpy(run_category, category, sizeof(run_category));
            memcpy(run_example, example, sizeof(run_example));
        }
    }
    if (bits != NULL)
    {
        fclose(bits);
    }
    return 1;
}

// the cubin at `path` run on the device through cell_ptx_probe over one case, its answer into `answered`: 1, or 0
// with the reason printed
static int sass_cubin_answer(SassProbe *probe, const char *path, char *answered, size_t room)
{
    char output[1024];
    snprintf(output, sizeof(output), "%s/run.out", probe->folder);
    // one case of eight words, none of them zero, so that a question that divides is not asked for a zero divisor
    char *const command[] = {(char *)probe->prober, (char *)"run",   (char *)path,        (char *)"0000000b",
                             (char *)"00000007",    (char *)"00000003", (char *)"00000005", (char *)"00000002",
                             (char *)"00000009",    (char *)"00000001", (char *)"00000004", NULL};
    const int status = sass_run(command, output);
    const char *const line = (status == 0) ? strstr(sass_output(), "answered ") : NULL;
    if (line == NULL)
    {
        printf("  cubin: %s did not run (exit %d)\n%s", path, status, (status > 0) ? sass_output() : "");
        return 0;
    }
    snprintf(answered, room, "%.*s", (int)strcspn(line, "\r\n"), line);
    return 1;
}

// `name` set to `value` in this process's environment, which the runner it starts inherits. MSVC spells putenv with
// an underscore and warns on the other; POSIX has setenv and takes the two apart
static void sass_environment(const char *name, const char *value)
{
#if defined(_WIN32)
    char both[64];
    snprintf(both, sizeof(both), "%s=%s", name, value);
    _putenv(both);
#else
    setenv(name, value, 1);
#endif
}

// The nanoseconds a run took, as the runner timed it by the host's clock, or 0 where it printed none. The runner
// times a run only where PROBE_REPEATS is set, and the count is what the caller set before calling
static double sass_cubin_nanoseconds(void)
{
    const char *const line = strstr(sass_output(), "timed ");
    const char *const taken = (line != NULL) ? strstr(line, ", ") : NULL;
    return (taken != NULL) ? strtod(taken + 2, NULL) : 0.0;
}

// A question of preference rather than of membership. Every question above asks whether the part CAN do a thing;
// this asks which of two codings of one thing it would rather be given. Both must answer the same, or they are not
// two codings of one thing and the reading is void. What the part prefers is not what a listing says and not what
// the encoding says: it is the part's own answer, in its own clock, and nothing else gives it
typedef struct
{
    const char *what;
    const char *one;
    const char *other;
    unsigned int answer;
} SassPrefer;

// the kernel `name` written again from its own listing, then both cubins run and their answers compared: 1 where the
// two answer the same
static int sass_cubin_same(SassProbe *probe, const SassMachine *machine, const char *name)
{
    if (!sass_cubin_round(machine, probe->folder, name))
    {
        return 0;
    }
    char path[1024];
    char was[256];
    char now[256];
    snprintf(path, sizeof(path), "%s/%s.cubin", probe->folder, name);
    if (!sass_cubin_answer(probe, path, was, sizeof(was)))
    {
        return 0;
    }
    snprintf(path, sizeof(path), "%s/%s_written.cubin", probe->folder, name);
    if (!sass_cubin_answer(probe, path, now, sizeof(now)))
    {
        return 0;
    }
    if (strcmp(was, now) != 0)
    {
        printf("  cubin %s: the toolchain's %s, the one written %s\n", name, was, now);
        return 0;
    }
    return 1;
}

// a question of the cell's own, asked in the part's code: the instruction to put in place of form_0's own, and the
// word the device should answer for the case sass_cubin_answer gives it
typedef struct
{
    const char *instruction;
    unsigned int answer;
} SassAsk;

// form_0's text with the line that begins `IADD3 ` replaced by `instruction`, into `text`: 1, or 0 where the text
// holds no such line
static int sass_ask_text(const char *was, const char *instruction, char *text, size_t room)
{
    size_t at = 0u;
    int put = 0;
    const char *walk = was;
    while ((*walk != '\0') && (at < (room - 1u)))
    {
        const size_t length = strcspn(walk, "\n");
        const char *const keep = (strncmp(walk, "IADD3 ", 6u) == 0) ? instruction : walk;
        const size_t kept = (keep == instruction) ? strlen(instruction) : length;
        put = put || (keep == instruction);
        if ((at + kept + 1u) < room)
        {
            memcpy(&text[at], keep, kept);
            at += kept;
            text[at] = '\n';
            at += 1u;
        }
        walk += length + ((walk[length] == '\n') ? 1u : 0u);
    }
    text[at] = '\0';
    return put;
}

// a question of more than one instruction named in one line: its instructions joined by a semicolon, and cut short
// with an ellipsis where the line will not hold them
static void sass_ask_named(const char *instruction, char *named, size_t room)
{
    size_t at = 0u;
    for (const char *walk = instruction; (*walk != '\0') && (at < (room - 1u)); walk += 1)
    {
        named[at] = (*walk == '\n') ? ';' : *walk;
        at += 1u;
    }
    named[at] = '\0';
    // 52 is the column the answers line up in, and a question past it is named by its opening
    if (at > 52u)
    {
        memcpy(&named[49], "...", 4u);
    }
}

// The count a coding is turned over, which is what lifts its cost out of the harness. A run costs about 497 us of
// launch and copy whatever the kernel holds, and one instruction costs under a nanosecond, so a coding is asked for
// once and turned this many times: the difference between two codings is then the difference between two costs,
// multiplied, and the harness is the same under both
// Measured 29 Sep: at 20000 turns the two codings of a move came out 7.3 ns a turn apart one run and 3.7 ns the
// other way the next, so the reading was the harness and not the part. The turns are raised until the loop is the
// run, and each coding is timed SASS_PREFER_TAKES times and read at its least, since a run can only be lengthened
// by what else the host is doing. A difference under the spread of a coding's own takes is no reading
#define SASS_PREFER_TURNS 400000u
#define SASS_PREFER_RUNS 20u
#define SASS_PREFER_TAKES 3u

// one tick of the part's clock in nanoseconds, which it named itself: 1770000 kHz (cell_ptx_probe clocks)
#define SASS_PREFER_TICK (1000.0 / 1770000.0 * 1000.0)

// `coding` wrapped in a loop of SASS_PREFER_TURNS turns, the count in R9, which the frame leaves free. The loop's
// own four instructions are under both codings alike and cancel out of the difference
static int sass_prefer_loop(const char *coding, char *text, size_t room)
{
    return snprintf(text, room,
                    "IMAD.MOV.U32 R6, RZ, RZ, %u\n"
                    ".L_turn:\n"
                    "%s\n"
                    "IADD3 R6, P6, R6, -0x1, RZ\n"
                    "ISETP.NE.U32.AND P1, PT, R6, RZ, PT\n"
                    "@P1 BRA `(.L_turn)",
                    SASS_PREFER_TURNS, coding) < (int)room;
}

// one coding written into a cubin, run, and timed; its answer through `answered` and its nanoseconds returned, 0
// where it did not assemble or did not run
static double sass_prefer_time(SassProbe *probe, const SassMachine *machine, const char *was, const char *coding,
                               char *answered, size_t room)
{
    static char s_looped[8192];
    static char s_asking[65536];
    char path[1024];
    // the answer emptied first, so a coding the assembler refuses is read as refused and not as the last one's word
    snprintf(answered, room, "refused");
    if (!sass_prefer_loop(coding, s_looped, sizeof(s_looped)) ||
        !sass_ask_text(was, s_looped, s_asking, sizeof(s_asking)) ||
        !sass_cubin_from_text(machine, probe->folder, "form_0", s_asking, "asked"))
    {
        return 0.0;
    }
    snprintf(path, sizeof(path), "%s/asked.cubin", probe->folder);
    char repeats[32];
    snprintf(repeats, sizeof(repeats), "%u", SASS_PREFER_RUNS);
    sass_environment("PROBE_REPEATS", repeats);
    const int ran = sass_cubin_answer(probe, path, answered, room);
    const double nanoseconds = ran ? sass_cubin_nanoseconds() : 0.0;
    sass_environment("PROBE_REPEATS", "0");
    return nanoseconds;
}

// Which of two codings of one thing the part would rather be given, asked of the part in its own clock. Both are
// run and both must answer what the question says, or they are not two codings of one thing; then both are timed,
// and the part's preference is the difference. How many were asked, and how many gave a reading
static unsigned int sass_cubin_prefers(SassProbe *probe, const SassMachine *machine, unsigned int *asked)
{
    static const SassPrefer s_prefers[] = {
        // A move has two codings on this part, and no listing says which to write: the compiler alternates them,
        // which is a hint that they go to different pipes and neither is free. R0 holds the case's first word
        {"a move", "MOV R7, R0", "IMAD.MOV.U32 R7, RZ, RZ, R0", 0x0000000bu},
        // A long operation, which is where this is going: the high word of a 64-bit add, the pair being the case's
        // two words (0x7 and 0xb) added to itself. sass.krs writes wide_add as IADD3 then IADD3.X; the other coding
        // takes the carry with IMAD.X and adds the high word after. Two instructions against three, and 11 + 11
        // carries nothing, so both answer 7 + 7
        // A long operation, which is where this is going: the high word of a 64-bit add. sass.krs writes wide_add
        // as IADD3 then IADD3.X; the other coding takes the carry with IMAD.X and adds the high word after, three
        // instructions against two. Both read R0, which the loop never writes, so a turn leaves the next one what
        // it found: a body that carries its own answer forward measures a chain 400000 long and not the coding
        {"a wide add's high word", "IADD3 R8, P6, R0, R0, RZ\nIADD3.X R9, R0, R0, RZ, P6, !PT\nMOV R7, R9",
         "IADD3 R8, P6, R0, R0, RZ\nIMAD.X R9, RZ, RZ, R0, P6\nIADD3 R9, R9, R0, RZ\nMOV R7, R9", 0x00000016u},
        // a word doubled, added to itself against shifted left by one. SHF.L.U32 takes its count in a register on
        // this part and no listing gave it an immediate, so the shift pays a move for the 1 it shifts by
        {"doubled", "IADD3 R7, R0, R0, RZ", "IMAD.MOV.U32 R8, RZ, RZ, 0x1\nSHF.L.U32 R7, R0, R8, RZ", 0x00000016u},
    };
    static char s_was[65536];
    if (sass_cubin_text(probe->folder, "form_0", s_was, sizeof(s_was)) == 0u)
    {
        return 0u;
    }
    unsigned int read = 0u;
    for (unsigned int number = 0u; number < (sizeof(s_prefers) / sizeof(s_prefers[0])); number += 1u)
    {
        const SassPrefer *const prefer = &s_prefers[number];
        *asked += 1u;
        double least[2] = {0.0, 0.0};
        double spread = 0.0;
        int held = 1;
        for (unsigned int side = 0u; held && (side < 2u); side += 1u)
        {
            const char *const coding = (side == 0u) ? prefer->one : prefer->other;
            double most = 0.0;
            for (unsigned int take = 0u; held && (take < SASS_PREFER_TAKES); take += 1u)
            {
                char answer[256];
                const double taken = sass_prefer_time(probe, machine, s_was, coding, answer, sizeof(answer));
                // the answer is "answered <word> ..." where it ran, and "refused" where it did not assemble
                const unsigned int word = (strncmp(answer, "answered ", 9u) == 0)
                                              ? (unsigned int)strtoul(answer + 9, NULL, 16)
                                              : 0u;
                if ((taken == 0.0) || (strncmp(answer, "answered ", 9u) != 0) || (word != prefer->answer))
                {
                    printf("  prefer %-24s no reading: the %s coding %s\n", prefer->what,
                           (side == 0u) ? "first" : "second",
                           (taken == 0.0) ? "did not assemble" : "answers what the question does not say");
                    held = 0;
                    continue;
                }
                least[side] = ((least[side] == 0.0) || (taken < least[side])) ? taken : least[side];
                most = (taken > most) ? taken : most;
            }
            spread = ((most - least[side]) > spread) ? (most - least[side]) : spread;
        }
        if (held == 0)
        {
            continue;
        }
        read += 1u;
        const double apart = (least[0] > least[1]) ? (least[0] - least[1]) : (least[1] - least[0]);
        const double each = apart / (double)SASS_PREFER_TURNS;
        printf("  prefer %-24s first %9.0f ns, second %9.0f ns, %.0f ns apart against a spread of %.0f: %s\n",
               prefer->what, least[0], least[1], apart, spread,
               (apart <= spread) ? "no preference above the floor"
                                 : ((least[0] < least[1]) ? "the first" : "the second"));
        if (apart > spread)
        {
            printf("    %.4f ns a turn, %.2f of the part's ticks\n", each, each / SASS_PREFER_TICK);
        }
    }
    return read;
}

// each question of the cell's own written into a cubin of its own, run, and its answer same to what the question
// says the part should say: how many answered so. form_0's kernel is the frame, which loads the case's first two
// words into R0 and R7, and stores R7 as the first word of the answer
static unsigned int sass_cubin_asks(SassProbe *probe, const SassMachine *machine, unsigned int *asked)
{
    static const SassAsk s_asks[] = {
        // the case is 0x0000000b and 0x00000007, and the part is asked what each instruction makes of them
        {"IADD3 R7, R0, R7, RZ", 0x00000012u},
        {"LOP3.LUT R7, R0, R7, RZ, 0x3c, !PT", 0x0000000cu},
        {"LOP3.LUT R7, R0, R7, RZ, 0xc0, !PT", 0x00000003u},
        {"LOP3.LUT R7, R0, R7, RZ, 0xfc, !PT", 0x0000000fu},
        {"IMAD R7, R0, R7, RZ", 0x0000004du},
        {"SHF.L.U32 R7, R0, R7, RZ", 0x00000580u},
        {"SHF.R.U32.HI R7, RZ, R7, R0", 0x00000000u},
        {"IABS R7, R0", 0x0000000bu},
        {"IADD3 R7, -R0, RZ, RZ", 0xfffffff5u},
        {"SEL R7, R0, R7, PT", 0x0000000bu},
        // The three comparisons no listing ever held, which the widening round found one bit from ones that were
        // (sass_machine_widen): the compiler read zero and below off the negations of NE and GE, so nothing had run
        // these until here. Each is asked once where it should fire and once where it should not, and the answer is
        // the case's first word where the predicate held and zero where it did not
        {"ISETP.EQ.U32.AND P0, PT, R7, R7, PT\nSEL R7, R0, RZ, P0", 0x0000000bu},
        {"ISETP.EQ.U32.AND P0, PT, R7, R0, PT\nSEL R7, R0, RZ, P0", 0x00000000u},
        {"ISETP.LT.AND P0, PT, R7, R0, PT\nSEL R7, R0, RZ, P0", 0x0000000bu},
        {"ISETP.LT.AND P0, PT, R0, R7, PT\nSEL R7, R0, RZ, P0", 0x00000000u},
        // the .EX of it, which takes the low words' answer as its last operand: the pair R0 and R7 against itself,
        // then against one whose high word differs
        {"ISETP.EQ.U32.AND P6, PT, R0, R0, PT\nISETP.EQ.U32.AND.EX P0, PT, R7, R7, PT, P6\nSEL R7, R0, RZ, P0",
         0x0000000bu},
        {"ISETP.EQ.U32.AND P6, PT, R0, R0, PT\nISETP.EQ.U32.AND.EX P0, PT, R7, R0, PT, P6\nSEL R7, R0, RZ, P0",
         0x00000000u},
        // .hi on a number, which is the high half of it as .hi on a register is the pair's second register. No
        // listing prints this: nvdisasm writes a pair's second register out, so every instruction ever assembled
        // carried .hi on a register alone, and a ruleset writing a 64-bit form against a literal is the first thing
        // to ask for the other half. 0x7_0000000b answers 7 where the half is taken and 11 where the whole number
        // is written and the field truncates it; 0x1_00000000 answers 1 against 0
        {"IMAD.MOV.U32 R7, RZ, RZ, 30064771083.hi", 0x00000007u},
        {"IMAD.MOV.U32 R7, RZ, RZ, 4294967296.hi", 0x00000001u},
        // A 64-bit load, which launch_load wants: a ruleset cannot write [R2.64+{offset}] and [R2.64+{offset}+4],
        // since adding 4 to a parameter is arithmetic and a .krs does none, so the pair must come in one
        // instruction. R2 still holds the case's address here, whose two words are 0xb and 0x7
        {"LDG.E.64.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R8", 0x0000000bu},
        {"LDG.E.64.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R9", 0x00000007u},
        // The other widths, which are names until the part is asked. .128 should write four registers from R8, so
        // R9 still reads the case's second word; .U8 should write one byte zero extended, which 0xffffffff stored
        // and read back as 0xff tells apart from a word. The store is to the answer's third slot, which nothing
        // reads, and the safe control the assembler writes waits on it before the load
        {"LDG.E.128.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R9", 0x00000007u},
        {"IMAD.MOV.U32 R8, RZ, RZ, 4294967295\nSTG.E [R4.64+0x8], R8\nLDG.E.U8.CONSTANT R9, [R4.64+0x8]\n"
         "IMAD.MOV.U32 R7, RZ, RZ, R9",
         0x000000ffu},
        // product_low and product_high, which the compiler fused into one IMAD.WIDE.U32 writing an aligned pair
        // (form_13: MOV R7, RZ then IMAD.WIDE.U32 R6, R9, R0, R6). The core names the two halves apart, so a pair
        // cannot be promised, and each half is asked here on its own: the low is the product's low word plus the
        // addend with its carry kept, and the high is the product's high word plus that carry. 0xffffffff squared
        // is 0xfffffffe00000001, and with 0xffffffff added the low is 0 carrying 1 and the high is 0xffffffff
        {"IMAD.MOV.U32 R2, RZ, RZ, 4294967295\nIMAD.MOV.U32 R3, RZ, RZ, 4294967295\n"
         "IMAD.MOV.U32 R6, RZ, RZ, 4294967295\nIMAD R8, R2, R3, RZ\nIADD3 R8, P6, R8, R6, RZ\n"
         "IMAD.MOV.U32 R7, RZ, RZ, R8",
         0x00000000u},
        {"IMAD.MOV.U32 R2, RZ, RZ, 4294967295\nIMAD.MOV.U32 R3, RZ, RZ, 4294967295\n"
         "IMAD.MOV.U32 R6, RZ, RZ, 4294967295\nIMAD R8, R2, R3, RZ\nIADD3 R8, P6, R8, R6, RZ\n"
         "IMAD.HI.U32 R9, R2, R3, RZ\nIMAD.X R9, RZ, RZ, R9, P6\nIMAD.MOV.U32 R7, RZ, RZ, R9",
         0xffffffffu},
        // predicate_xor and predicate_and as sass.krs writes them, their scratch in R2, R3 and R6, which the frame
        // leaves free: R4 and R5 hold the address the answer is stored to and R7 holds the answer. P1 is true, since
        // the case's first word is not zero, and P2 is given the word that makes it true or the zero that does not
        {"ISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, RZ, RZ, PT\nSEL R2, RZ, 0x1, P1\n"
         "SEL R3, RZ, 0x1, P2\nLOP3.LUT R2, R2, R3, RZ, 0x3c, !PT\nISETP.NE.U32.AND P0, PT, R2, RZ, PT\n"
         "SEL R7, R0, RZ, P0",
         0x0000000bu},
        {"ISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, R7, RZ, PT\nSEL R2, RZ, 0x1, P1\n"
         "SEL R3, RZ, 0x1, P2\nLOP3.LUT R2, R2, R3, RZ, 0x3c, !PT\nISETP.NE.U32.AND P0, PT, R2, RZ, PT\n"
         "SEL R7, R0, RZ, P0",
         0x00000000u},
        {"ISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, R7, RZ, PT\nMOV R6, 0x1\n"
         "SEL R2, R6, 0x0, P1\nSEL R3, R6, 0x0, P2\nLOP3.LUT R2, R2, R3, RZ, 0xc0, !PT\n"
         "ISETP.NE.U32.AND P0, PT, R2, RZ, PT\nSEL R7, R0, RZ, P0",
         0x0000000bu},
        {"ISETP.NE.U32.AND P1, PT, R0, RZ, PT\nISETP.NE.U32.AND P2, PT, RZ, RZ, PT\nMOV R6, 0x1\n"
         "SEL R2, R6, 0x0, P1\nSEL R3, R6, 0x0, P2\nLOP3.LUT R2, R2, R3, RZ, 0xc0, !PT\n"
         "ISETP.NE.U32.AND P0, PT, R2, RZ, PT\nSEL R7, R0, RZ, P0",
         0x00000000u},
    };
    static char s_was[65536];
    static char s_asking[65536];
    if (sass_cubin_text(probe->folder, "form_0", s_was, sizeof(s_was)) == 0u)
    {
        return 0u;
    }
    unsigned int right = 0u;
    for (unsigned int number = 0u; number < (sizeof(s_asks) / sizeof(s_asks[0])); number += 1u)
    {
        *asked += 1u;
        char answered[256];
        char path[1024];
        unsigned int word = 0u;
        if (!sass_ask_text(s_was, s_asks[number].instruction, s_asking, sizeof(s_asking)) ||
            !sass_cubin_from_text(machine, probe->folder, "form_0", s_asking, "asked"))
        {
            printf("  ask %s: not written\n", s_asks[number].instruction);
            continue;
        }
        snprintf(path, sizeof(path), "%s/asked.cubin", probe->folder);
        if (!sass_cubin_answer(probe, path, answered, sizeof(answered)))
        {
            continue;
        }
        // the answer's first word, which the run prints after "answered "
        word = (unsigned int)strtoul(answered + 9, NULL, 16);
        const int same = (word == s_asks[number].answer);
        right += same ? 1u : 0u;
        char named[SASS_TEXT];
        sass_ask_named(s_asks[number].instruction, named, sizeof(named));
        printf("  ask %-52s the part answers %08x, the question says %08x%s\n", named, word, s_asks[number].answer,
               same ? "" : " <- differs");
    }
    return right;
}

// the questions cell_ptx_probe assembled, read from its lines "cubin <number> <name>", and the architecture from its
// first line, "sm_86, ...": 1, or 0 where it printed none
static int sass_questions_read(SassProbe *probe, const char *output)
{
    // the line may follow others the ruleset's reader printed
    const char *const line = (strncmp(output, "sm_", 3u) == 0) ? output : strstr(output, "\nsm_");
    if (line == NULL)
    {
        return 0;
    }
    const unsigned long version = strtoul(line + ((*line == '\n') ? 4 : 3), NULL, 10);
    snprintf(probe->architecture, sizeof(probe->architecture), "SM%lu", version);
    probe->questions = 0u;
    for (const char *line = strstr(output, "\ncubin "); line != NULL; line = strstr(line + 1, "\ncubin "))
    {
        char *after = NULL;
        const unsigned long number = strtoul(line + 7, &after, 10);
        if ((number != (unsigned long)probe->questions) || (probe->questions == SASS_QUESTIONS) || (*after != ' '))
        {
            return 0;
        }
        const size_t length = strcspn(after + 1, "\r\n");
        snprintf(probe->names[probe->questions], SASS_NAME, "%.*s", (int)length, after + 1);
        probe->questions += 1u;
    }
    return probe->questions != 0u;
}

int main(int count, char **arguments)
{
    if (count < 3)
    {
        fprintf(stderr, "  cell_sass_probe: <cell_ptx_probe> <output folder>\n");
        return 2;
    }
    SassProbe *const probe = &s_sass_probe;
    probe->folder = arguments[2];
    probe->prober = arguments[1];
    char output[1024];
    snprintf(output, sizeof(output), "%s/cubins.out", probe->folder);
    char *const command[] = {arguments[1], "cubins", arguments[2], NULL};
    const int status = sass_run(command, output);
    if ((status != 0) || !sass_questions_read(probe, sass_output()))
    {
        printf("  cell_ptx_probe cubins exited %d\n%s", status, (status >= 0) ? sass_output() : "");
        return 2;
    }
    printf("%s: %u questions\n", probe->architecture, probe->questions);
    if (!sass_list(probe, "frame", &s_sass_frame))
    {
        return 2;
    }
    sass_operations_take(probe, &s_sass_frame);
    sass_machine_listing(&s_sass_machine, &s_sass_frame);
    for (unsigned int number = 0u; number < probe->questions; number += 1u)
    {
        char name[32];
        snprintf(name, sizeof(name), "form_%u", number);
        if (!sass_list(probe, name, &s_sass_form))
        {
            probe->failed += 1u;
            continue;
        }
        sass_form_print(probe->names[number], &s_sass_form, &s_sass_frame);
        sass_operations_take(probe, &s_sass_form);
        sass_machine_listing(&s_sass_machine, &s_sass_form);
    }
    for (unsigned int number = 0u; number < probe->operations; number += 1u)
    {
        probe->failed += sass_fields(probe, &probe->operation[number]) ? 0u : 1u;
    }
    printf("cell sass probe: %u questions, %u operations, %u failed\n", probe->questions, probe->operations,
           probe->failed);
    // every operation one bit from one the listings gave, asked of the disassembler before the fields are found, so
    // that the widened forms get their operand runs in the same pass
    sass_machine_widen(&s_sass_machine, probe->architecture, probe->folder);
    // the forms the listings hold and the bits each one's operands sit in, written out for the assembler
    probe->failed += sass_machine_fields(&s_sass_machine, probe->architecture, probe->folder) ? 0u : 1u;
    if (count > 3)
    {
        probe->failed += sass_machine_same(&s_sass_machine, arguments[3]) ? 0u : 1u;
    }
    // every instruction listed, assembled back from its text alone, then disassembled and same to that text
    SassCheck tally;
    memset(&tally, 0, sizeof(tally));
    unsigned int differed = 0u;
    if (sass_list(probe, "frame", &s_sass_frame))
    {
        differed += sass_machine_check(&s_sass_machine, &s_sass_frame, probe->architecture, probe->folder, &tally, 4u);
    }
    for (unsigned int number = 0u; number < probe->questions; number += 1u)
    {
        char name[32];
        snprintf(name, sizeof(name), "form_%u", number);
        if (sass_list(probe, name, &s_sass_form))
        {
            differed += sass_machine_check(&s_sass_machine, &s_sass_form, probe->architecture, probe->folder, &tally,
                                           (differed < 4u) ? 4u : 0u);
        }
    }
    printf("cell sass assemble: %u written back, %u refused, %u the same bytes, %u read back as the same text, %u "
           "same to their bytes alone, %u failed\n",
           tally.checked, tally.refused, tally.same_bits, tally.same_text, tally.by_bytes, differed);
    probe->failed += (differed == 0u) ? 0u : 1u;
    // each kernel written again into a cubin of its own, loaded and run, and its answer same to the toolchain's
    unsigned int cubins = 0u;
    unsigned int same = 0u;
    same += sass_cubin_same(probe, &s_sass_machine, "frame") ? 1u : 0u;
    cubins += 1u;
    for (unsigned int number = 0u; number < probe->questions; number += 1u)
    {
        char name[32];
        snprintf(name, sizeof(name), "form_%u", number);
        same += sass_cubin_same(probe, &s_sass_machine, name) ? 1u : 0u;
        cubins += 1u;
    }
    printf("cell sass cubin: %u kernels written again, %u answering as the toolchain's did\n", cubins, same);
    probe->failed += (same == cubins) ? 0u : 1u;
    // the cell's own questions, in code no toolchain wrote
    unsigned int asked = 0u;
    const unsigned int answered = sass_cubin_asks(probe, &s_sass_machine, &asked);
    printf("cell sass ask: %u questions asked in the part's own code, %u answered as the question says\n", asked,
           answered);
    probe->failed += (answered == asked) ? 0u : 1u;
    // and the questions of preference: which of two codings of one thing the part would rather be given. A reading
    // that does not come back is not a failure, since nothing yet depends on one
    unsigned int weighed = 0u;
    const unsigned int read = sass_cubin_prefers(probe, &s_sass_machine, &weighed);
    printf("cell sass prefer: %u codings weighed against each other, %u read in the part's own clock\n", weighed,
           read);
    return (probe->failed == 0u) ? 0 : 1;
}
