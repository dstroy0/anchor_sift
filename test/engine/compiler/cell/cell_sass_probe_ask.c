// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_ask.c: the questions the cell puts to the part in code no toolchain wrote. Every other piece here
// reads what the part's own tools say about it; this one runs the part and reads back what it answers. Nothing else
// tells an encoding the part executes from one its disassembler merely named
#include "cell_sass_probe.h"

#include <stdlib.h>
#include <string.h>

// the cubin at `path` run on the device through cell_ptx_probe over one case, its answer into `answered`: 1, or 0
// with the reason printed
int sass_cubin_answer(SassProbe *probe, const char *path, char *answered, size_t room)
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

// A question of preference, not of membership. Every question above asks whether the part CAN do a thing;
// this asks which of two codings of one thing the part prefers. Both must answer the same, or they are not
// two codings of one thing and the reading is void. What the part prefers is not what a listing says and not what
// the encoding says: it is the part's own answer, in its own clock.
typedef struct
{
    const char *what;
    const char *one;
    const char *other;
    unsigned int answer;
} SassPrefer;

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

// The count a coding is turned over to lift its cost out of the harness. A run costs about 497 us of
// launch and copy whatever the kernel holds, and one instruction costs under a nanosecond. A coding is asked for
// once and turned this many times: the difference between two codings is then the difference between two costs,
// multiplied, and the harness is the same under both. The turns are raised until the loop is the
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
    // the answer emptied first: a coding the assembler refuses is read as refused and not as the last one's word
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

// Which of two codings of one thing the part prefers, asked of the part in its own clock. Both are
// run and both must answer what the question says, or they are not two codings of one thing; then both are timed,
// and the part's preference is the difference. How many were asked, and how many gave a reading
unsigned int sass_cubin_prefers(SassProbe *probe, const SassMachine *machine, unsigned int *asked)
{
    static const SassPrefer s_prefers[] = {
        // A move has two codings on this part, and no listing says which to write: the compiler alternates them,
        // which is a hint that they go to different pipes and neither is free. R0 holds the case's first word
        {"a move", "MOV R7, R0", "IMAD.MOV.U32 R7, RZ, RZ, R0", 0x0000000bu},
        // A long operation, which is where this is going: the high word of a 64-bit add. sass.krs writes wide_add
        // as IADD3 then IADD3.X; the other coding takes the carry with IMAD.X and adds the high word after, three
        // instructions against two. Both read R0, which the loop never writes. A turn leaves the next one what
        // it found: a body that carries its own answer forward measures a chain 400000 long and not the coding
        {"a wide add's high word", "IADD3 R8, P6, R0, R0, RZ\nIADD3.X R9, R0, R0, RZ, P6, !PT\nMOV R7, R9",
         "IADD3 R8, P6, R0, R0, RZ\nIMAD.X R9, RZ, RZ, R0, P6\nIADD3 R9, R9, R0, RZ\nMOV R7, R9", 0x00000016u},
        // a word doubled, added to itself against shifted left by one. SHF.L.U32 takes its count in a register on
        // this part and no listing gave it an immediate: the shift pays a move for the 1 it shifts by
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
            // one of the two codings would not run, or answered something the question does not say: there is
            // no pair left to weigh
            sass_class_take(SASS_CHANNEL_CLOCK, SASS_CLASS_ILLEGAL, prefer->what, 0u);
            continue;
        }
        read += 1u;
        const double apart = (least[0] > least[1]) ? (least[0] - least[1]) : (least[1] - least[0]);
        const double each = apart / (double)SASS_PREFER_TURNS;
        // A reading the part gave, or a pair it ran and told nothing apart on: the two stood closer together than
        // the same coding stood to itself across its own runs, a question asked with no answer in it.
        //
        // The word kept is 0 and never the time. How long a coding took is a cost and belongs in the .kdm; what
        // belongs here is whether the question got an answer at all. Writing the time would also put a number that
        // moves a nanosecond between runs into a file meant to be read against the last one, and every run would
        // differ from the tree's copy for no reason the part could name
        sass_class_take(SASS_CHANNEL_CLOCK, (apart <= spread) ? SASS_CLASS_NOTHING : SASS_CLASS_ANSWERS, prefer->what,
                        0u);
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
unsigned int sass_cubin_asks(SassProbe *probe, const SassMachine *machine, unsigned int *asked)
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
        // (sass_machine_widen): the compiler read zero and below off the negations of NE and GE: nothing had run
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
        // .hi on a number is the high half of it as .hi on a register is the pair's second register. No
        // listing prints this: nvdisasm writes a pair's second register out: every instruction ever assembled
        // carried .hi on a register alone, and a ruleset writing a 64-bit form against a literal is the first thing
        // to ask for the other half. 0x7_0000000b answers 7 where the half is taken and 11 where the whole number
        // is written and the field truncates it; 0x1_00000000 answers 1 against 0
        {"IMAD.MOV.U32 R7, RZ, RZ, 30064771083.hi", 0x00000007u},
        {"IMAD.MOV.U32 R7, RZ, RZ, 4294967296.hi", 0x00000001u},
        // A 64-bit load, which launch_load wants: a ruleset cannot write [R2.64+{offset}] and [R2.64+{offset}+4],
        // since adding 4 to a parameter is arithmetic and a .krs does none: the pair must come in one
        // instruction. R2 still holds the case's address here, whose two words are 0xb and 0x7
        {"LDG.E.64.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R8", 0x0000000bu},
        {"LDG.E.64.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R9", 0x00000007u},
        // The other widths, which are names until the part is asked. .128 should write four registers from R8:
        // R9 still reads the case's second word; .U8 should write one byte zero extended, which 0xffffffff stored
        // and read back as 0xff tells apart from a word. The store is to the answer's third slot, which nothing
        // reads, and the safe control the assembler writes waits on it before the load
        {"LDG.E.128.CONSTANT R8, [R2.64]\nIMAD.MOV.U32 R7, RZ, RZ, R9", 0x00000007u},
        {"IMAD.MOV.U32 R8, RZ, RZ, 4294967295\nSTG.E [R4.64+0x8], R8\nLDG.E.U8.CONSTANT R9, [R4.64+0x8]\n"
         "IMAD.MOV.U32 R7, RZ, RZ, R9",
         0x000000ffu},
        // product_low and product_high, which the compiler fused into one IMAD.WIDE.U32 writing an aligned pair
        // (form_13: MOV R7, RZ then IMAD.WIDE.U32 R6, R9, R0, R6). The core names the two halves apart: a pair
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
        // count_add, which the PTX question could only assemble and run: what the reduction leaves is read here,
        // where the instructions are ours. The answer's third slot is set to zero, added to twice - once by one out
        // of a register, since the reduction reads no number out of the instruction, and once by the case's first
        // word - and read back. 0 + 1 + 0xb is 0xc, and a reduction that added nothing would answer 0
        {"STG.E [R4.64+0x8], RZ\nMOV R6, 0x1\nRED.E.ADD.STRONG.GPU [R4.64+0x8], R6\n"
         "RED.E.ADD.STRONG.GPU [R4.64+0x8], R0\nLDG.E.CONSTANT R7, [R4.64+0x8]",
         0x0000000cu},
        // Which numbers the part keeps for itself. R255 reads zero whatever is written into it, and that alone is
        // what RZ is: nothing about the file says so, the part does.
        //
        // The high numbers are a different question and are not asked here. R254 and R238, which sass.krs claims,
        // were asked and the kernel errored on the device both times. Asked again in a kernel written to declare
        // 255 registers, every number from R0 to R254 held what was written into it. So how many registers the lane
        // is given is not the part's answer alone - it is the count the kernel declared, and the part gives exactly
        // that many. A question spliced into form_0 inherits form_0's count, which is far below 238, and cannot ask
        // about a number above it. What sass.krs claims of R238, R239 and R254 rests on the lane's own cubin
        // declaring 255, which is written down where the claim is made
        {"MOV R255, 0x5a3c69a5\nIMAD.MOV.U32 R7, RZ, RZ, R255", 0x00000000u},
        // The precepts of the alphabet (precepts.h) the part has never been asked for. Everything above this point
        // was asked because a ruleset wanted it; these are asked because the alphabet has them, and a part that has
        // no word for one is a part the web has to spell it for.
        //
        // NOT, NAND and NOR cost nothing to ask: LOP3's immediate is the truth table of its three inputs, indexed by
        // a<<2|b<<1|c, and the part already answered for AND at 0xc0, OR at 0xfc and XOR at 0x3c. Their complements
        // are 0x3f, 0x03 and, for NOT of the first input alone, 0x0f. The case is 0xb and 0x7
        {"LOP3.LUT R7, R0, RZ, RZ, 0x0f, !PT", 0xfffffff4u},
        {"LOP3.LUT R7, R0, R7, RZ, 0x3f, !PT", 0xfffffffcu},
        {"LOP3.LUT R7, R0, R7, RZ, 0x03, !PT", 0xfffffff0u},
        // ASR, which differs from SHR only where the sign is set. The case's first word is negated first: -11 is
        // 0xfffffff5 and carrying its sign right 7 places leaves every bit set
        {"IADD3 R6, -R0, RZ, RZ\nSHF.R.S32.HI R7, RZ, R7, R6", 0xffffffffu},
        // ROR and ROL, on the two spellings that carry a funnel. The .U32 spellings were asked first and the part
        // said no to both: SHF.R.U32.HI R7, R0, R7, R0 answered 0 and SHF.L.U32 R7, R6, R7, R6 answered 0xfffffa80,
        // each the plain shift with the bits that left dropped. Giving a 32-bit shift the same register twice does
        // not rotate it, because there is no second half of the funnel for it to read. The .U64 spellings have one,
        // and neither reached a listing: the compiler never wrote either, and both came here from turning a listed
        // form's bits one at a time. 0xb carried right 7 places brings its low 7 bits back at the top, and
        // 0xfffffff5 carried left 7 brings its top 7 back at the bottom
        {"SHF.R.U64 R7, R0, R7, R0", 0x16000000u},
        {"IADD3 R6, -R0, RZ, RZ\nSHF.L.U64.HI R7, R6, R7, R6", 0xfffffaffu},
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
            // the question could not be written as the part's own code, which is a refusal before the part sees it
            sass_class_take(SASS_CHANNEL_RUN, SASS_CLASS_ILLEGAL, s_asks[number].instruction, 0u);
            printf("  ask %s: not written\n", s_asks[number].instruction);
            continue;
        }
        snprintf(path, sizeof(path), "%s/asked.cubin", probe->folder);
        if (!sass_cubin_answer(probe, path, answered, sizeof(answered)))
        {
            // the part was handed the question and would not run it: illegal on its own, however it assembled
            sass_class_take(SASS_CHANNEL_RUN, SASS_CLASS_ILLEGAL, s_asks[number].instruction, 0u);
            continue;
        }
        // the answer's first word, which the run prints after "answered "
        word = (unsigned int)strtoul(answered + 9, NULL, 16);
        const int same = (word == s_asks[number].answer);
        right += same ? 1u : 0u;
        // it ran and answered. Where the answer is what the question says, the part holds the question; where it
        // differs, the part took the question and what came back is not what it was read as, which is nothing this
        // can build on
        sass_class_take(SASS_CHANNEL_RUN, same ? SASS_CLASS_ANSWERS : SASS_CLASS_NOTHING, s_asks[number].instruction,
                        word);
        char named[SASS_TEXT];
        sass_ask_named(s_asks[number].instruction, named, sizeof(named));
        printf("  ask %-52s the part answers %08x, the question says %08x%s\n", named, word, s_asks[number].answer,
               same ? "" : " <- differs");
    }
    return right;
}

// the questions cell_ptx_probe assembled, read from its lines "cubin <number> <name>", and the architecture from its
// first line, "sm_86, ...": 1, or 0 where it printed none
