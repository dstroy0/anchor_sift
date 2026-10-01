// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_main.c: each form's operations, each operation's fields, and main. The first argument is
// cell_ptx_probe's path, the second a folder for the cubins, listings and decodings. Exit 0 where every cubin was
// listed and every operation decoded, 1 where one was not, 2 where the probe could not ask at all. Given `loop` and a
// machine file after those two, the folder is one an earlier run left its cubins in and only the loop ask is put:
// exit 0 where a form came back on every count, 1 where none did, 2 where the machine file was not read
#include "cell_sass_probe.h"

#include <stdlib.h>
#include <string.h>

// the longest category and example a bit's reading is given
#define SASS_CATEGORY 32u
#define SASS_EXAMPLE 160u

static SassProbe s_sass_probe;
static SassMachine s_sass_machine;
static SassListing s_sass_frame;
static SassListing s_sass_resident;
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

// A lane of the cell's own written into the resident's cubin, and the resident checked for having survived it. What
// goes in is the frame's own text, which assembles and asks nothing of the launch: under test here is the cubin
// writer, not the lane. 1 where every instruction of the resident is still in the cubin afterwards
static int sass_lane_written(SassProbe *probe)
{
    // A lane is a function the resident calls, and a function ends where it was called from. Putting a kernel's
    // body here in place of this would be writing something that EXITs where the part expects a RET, which the
    // cubin writer refuses and should
    static const char s_lane[] = "\tIMAD.MOV.U32 R16, RZ, RZ, R4;\n"
                                 "\tIMAD.MOV.U32 R17, RZ, RZ, R5;\n"
                                 "\tRET.ABS.NODEC R20 0x0;\n";
    if (!sass_cubin_lane_into(&s_sass_machine, probe->folder, s_lane, "program"))
    {
        printf("cell sass lane: the lane did not go into the resident's cubin\n");
        return 0;
    }
    static SassListing s_before;
    static SassListing s_after;
    if (!sass_list(probe, "resident", &s_before) || !sass_list(probe, "program", &s_after))
    {
        printf("cell sass lane: the cubin did not list\n");
        return 0;
    }
    // every instruction the resident's cubin held, looked for in the one the lane went into. cycle_program is the
    // bulk of both and none of it may have moved; the empty cycle_lane it was built with is two instructions, and
    // those are the ones expected to be gone
    unsigned int held = 0u;
    for (unsigned int number = 0u; number < s_before.count; number += 1u)
    {
        int found = 0;
        for (unsigned int at = 0u; (found == 0) && (at < s_after.count); at += 1u)
        {
            found = ((s_before.instructions[number].low == s_after.instructions[at].low) &&
                     (s_before.instructions[number].high == s_after.instructions[at].high))
                        ? 1
                        : 0;
        }
        held += (unsigned int)found;
    }
    printf("cell sass lane: %u instructions in the cubin the lane went into, %u of the resident's %u still in it\n",
           s_after.count, held, s_before.count);
    // the resident's own instructions all survive; what the empty lane held is what the new lane replaced
    return (s_before.count - held) <= 2u;
}

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

// The loop ask alone, against the machine file at `path` and the cubins already in the probe's folder: the part is
// asked how it loops without the machine being learned again. The system's classification is written beside them
static int sass_loop_main(SassProbe *probe, const char *path)
{
    if (!sass_machine_read(&s_sass_machine, path))
    {
        return 2;
    }
    unsigned int asked = 0u;
    const unsigned int kept = sass_cubin_loops(probe, &s_sass_machine, &asked);
    const int written = sass_class_write(probe->folder, s_sass_machine.part);
    return ((kept != 0u) && written) ? 0 : 1;
}

int main(int count, char **arguments)
{
    if (count < 3)
    {
        fprintf(stderr, "  cell_sass_probe: <cell_ptx_probe> <output folder> [<machines> | loop <machine file>]\n");
        return 2;
    }
    SassProbe *const probe = &s_sass_probe;
    probe->folder = arguments[2];
    probe->prober = arguments[1];
    if ((count > 4) && (strcmp(arguments[3], "loop") == 0))
    {
        return sass_loop_main(probe, arguments[4]);
    }
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
    // The resident, the kernel the host launches, which no question covers. Its PTX already runs and the part's own
    // compiler turned it into SASS that already runs. What is read here is that SASS: the floor a rearrangement
    // has to beat, and the operations a whole coherent program needs that no single question reaches.
    //
    // It is listed after the questions, and the order carries weight. A form is keyed by its operation and the kinds
    // of its operands: the resident's CALL.ABS.NOINC `(cycle_lane) and the division question's
    // CALL.ABS.NOINC `(__cuda_sm20_div_u64) are one form, and the first listing seen keeps it. The assembler holds
    // a symbol operand by the text the form was learned with, having no way to write a relocation for another:
    // whichever call is listed first is the only call that assembles. Listing the resident first took that form and
    // the division question stopped being writable. That limit on symbol operands is real and stands either way;
    // the order keeps it from costing a question that used to pass
    if (sass_list(probe, "resident", &s_sass_resident))
    {
        sass_form_print("the program resident", &s_sass_resident, &s_sass_frame);
        sass_operations_take(probe, &s_sass_resident);
        sass_machine_listing(&s_sass_machine, &s_sass_resident);
    }
    else
    {
        probe->failed += 1u;
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
    // and every operation the part has a coding for at all, asked without starting from a compiler's output
    sass_machine_sweep(&s_sass_machine, probe->architecture, probe->folder);
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
    // The resident put through the same check, counted apart. Everything above came from a membership question, and
    // an instruction of one that stops assembling is this assembler breaking. The resident is a whole program the
    // part's compiler wrote, and it reaches operands no question ever produced - a convergence barrier B0, the
    // predicate file PR, a uniform predicate UP0, a constant bank past 0, a call to a symbol the form was not
    // learned with. Those are refused and never guessed at: the reader working. Counting them beside the
    // questions would read as a break where it is a frontier: they are counted and named on their own
    SassCheck reached;
    memset(&reached, 0, sizeof(reached));
    unsigned int resident_differed = 0u;
    if (sass_list(probe, "resident", &s_sass_resident))
    {
        resident_differed =
            sass_machine_check(&s_sass_machine, &s_sass_resident, probe->architecture, probe->folder, &reached, 8u);
    }
    printf("cell sass resident: %u written back, %u refused, %u the same bytes, %u read back as the same text, %u "
           "same to their bytes alone, %u the assembler does not reach yet\n",
           reached.checked, reached.refused, reached.same_bits, reached.same_text, reached.by_bytes,
           resident_differed);
    // A lane of our own put into the resident's cubin: how a SASS program is built. The resident keeps the
    // code the part's own compiler gave it and only cycle_lane is replaced: what is checked here is that
    // replacing one function of a cubin leaves the other as it was, byte for byte
    probe->failed += sass_lane_written(probe) ? 0u : 1u;
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
    // and the questions of preference: which of two codings of one thing the part prefers. A reading
    // that does not come back is not a failure, since nothing yet depends on one
    unsigned int weighed = 0u;
    const unsigned int read = sass_cubin_prefers(probe, &s_sass_machine, &weighed);
    printf("cell sass prefer: %u codings weighed against each other, %u read in the part's own clock\n", weighed,
           read);
    // How this system was asked and what came back. Written beside the machine this run learned, in the run's own
    // folder, and copied into the tree by a hand the same way the machine is: a test writes nothing into the source
    // tree, and a record of what the part said is worth reading before it replaces the one already there
    probe->failed += sass_class_write(probe->folder, s_sass_machine.part) ? 0u : 1u;
    return (probe->failed == 0u) ? 0 : 1;
}
