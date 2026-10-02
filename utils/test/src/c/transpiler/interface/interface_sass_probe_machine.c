// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_machine.c: every instruction of the listings taken as a form, each form's operand fields found by
// turning its bits over, and the two searches that find the forms no listing held -- widening, which walks out from
// a form a bit at a time, and the sweep, which puts every operation key to the disassembler (sass_machine.h)
#include "interface_sass_probe.h"

#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <string.h>

// the encodings one form is decoded with: itself, and the 128 that are one bit from it
static unsigned long long s_low[SASS_ENCODINGS];
static unsigned long long s_high[SASS_ENCODINGS];
static char s_texts[SASS_ENCODINGS][SASS_TEXT];

void sass_machine_listing(SassMachine *machine, const SassListing *listing)
{
    for (unsigned int number = 0u; number < listing->count; number += 1u)
    {
        const SassInstruction *const instruction = &listing->instructions[number];
        SassForm *kept = NULL;
        // an instruction the listing gave no encoding for says nothing about how its form encodes
        if ((instruction->low != 0ull) || (instruction->high != 0ull))
        {
            sass_machine_take(machine, instruction->text, instruction->low, instruction->high, &kept);
        }
    }
}

// the operand `text` changed against `base`, or the operand count where it changed none of them, more than one of
// them, the operation, or the guard
static unsigned int sass_operand_changed(const SassInstructionParts *base, const char *text)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    if ((strcmp(parts.operation, base->operation) != 0) || (parts.operands != base->operands) ||
        (strcmp(parts.guard, base->guard) != 0))
    {
        return base->operands;
    }
    unsigned int changed = base->operands;
    unsigned int count = 0u;
    for (unsigned int place = 0u; place < base->operands; place += 1u)
    {
        if ((strcmp(parts.operand[place], base->operand[place]) != 0) || (parts.mark[place] != base->mark[place]))
        {
            changed = place;
            count += 1u;
        }
    }
    return (count == 1u) ? changed : base->operands;
}

// a form's encoding and the 128 that are one bit from it, laid into s_low and s_high
static void sass_form_turned(const SassForm *form)
{
    s_low[0] = form->low;
    s_high[0] = form->high;
    for (unsigned int bit = 0u; bit < SASS_BITS; bit += 1u)
    {
        s_low[1u + bit] = s_low[0] ^ ((bit < 64u) ? (1ull << bit) : 0ull);
        s_high[1u + bit] = s_high[0] ^ ((bit >= 64u) ? (1ull << (bit - 64u)) : 0ull);
    }
}

// one form's fields found: each of its 128 bits turned over and decoded, and each run of bits that changes one
// printed operand kept as that operand's. 1, or 0 where the disassembler failed
static int sass_form_fields(SassForm *form, const char *architecture, const char *folder, unsigned int number)
{
    sass_form_turned(form);
    char path[1024];
    snprintf(path, sizeof(path), "%s/form_%03u", folder, number);
    if (!sass_decode(architecture, path, s_low, s_high, SASS_ENCODINGS, s_texts))
    {
        return 0;
    }
    SassInstructionParts base;
    sass_instruction_read(s_texts[0], &base);
    form->runs = 0u;
    unsigned int running = base.operands;
    unsigned int first = 0u;
    for (unsigned int bit = 0u; bit <= SASS_BITS; bit += 1u)
    {
        const unsigned int changed =
            (bit < SASS_BITS) ? sass_operand_changed(&base, s_texts[1u + bit]) : base.operands;
        // a run ends where the operand it changes does, and the two words never share one
        const int joined = (changed == running) && (changed != base.operands) && (bit != 64u);
        if (!joined && (running != base.operands) && (form->runs < SASS_MACHINE_RUNS))
        {
            form->run[form->runs].operand = running;
            form->run[form->runs].first = first;
            form->run[form->runs].last = bit - 1u;
            form->runs += 1u;
        }
        if (!joined)
        {
            running = changed;
            first = bit;
        }
    }
    return 1;
}

// 1 where the disassembler named every modifier of `operation`. It has three ways of saying it could not: it prints
// INVALID<n>, it prints ???<n>, or it leaves the trailing dot with nothing after it. An encoding whose meaning the
// disassembler will not state is not a form, because assembling from it would write bits nothing can say the part
// reads. The three are one refusal wearing three spellings, and a form kept under any of them is a false branch
static int sass_operation_named(const char *operation)
{
    const size_t length = strlen(operation);
    return (length != 0u) && (operation[length - 1u] != '.') && (strstr(operation, "INVALID") == NULL) &&
           (strstr(operation, "???") == NULL);
}

// 1 where `text` is an instruction a form can be kept from: the disassembler took it, it names an operation it could
// spell whole, and every operand it prints is a kind the assembler knows where to put.
//
// The operation's name alone does not say which form this is. A form is keyed by its operation and the kind of each
// operand together, because those are what decide where the assembler puts a number: SHF.L.U32 with a register in
// the shift slot and SHF.L.U32 with a number there read the same name and are two forms. So nothing here is turned
// away for naming the operation it was turned from, and what is genuinely the form already in hand -- its registers
// moved, or its control bits -- is turned away by sass_machine_take, which finds the operation and the kinds
static int sass_widened_holds(const char *text, SassInstructionParts *parts)
{
    if ((strcmp(text, "illegal") == 0) || (strcmp(text, "unprinted") == 0))
    {
        return 0;
    }
    sass_instruction_read(text, parts);
    if (!sass_operation_named(parts->operation))
    {
        return 0;
    }
    for (unsigned int place = 0u; place < parts->operands; place += 1u)
    {
        if (parts->kind[place] == SASS_OPERAND_UNKNOWN)
        {
            return 0;
        }
    }
    return 1;
}

unsigned int sass_machine_widen(SassMachine *machine, const char *architecture, const char *folder)
{
    // the forms the listings gave, before any this pass adds: a form is widened from an instruction the part ran
    const unsigned int listed = machine->forms;
    unsigned int failed = 0u;
    unsigned int rounds = 0u;
    // A form one bit from a listed one is a form the next round can be a bit from in turn. Widening only the
    // listings reaches whatever is one bit out and stops, which leaves a form two bits out unreached even where the
    // bit between them is a form the part takes. The kind of a slot is such a field, and the lane is short of it:
    // the low word picks a register, a number or a constant for the second and the third operand, and on sm_86 those
    // read 0x2 for a register in both, 0xa and 0x8 for a constant and a number in the second, 0x6 and 0x4 for a
    // constant and a number in the third. A register to a number is two bits either way, through the constant that
    // lies between. One round reaches the constant and the round after reaches the number.
    //
    // SASS_WIDEN_ROUNDS is that reach. Letting the walk run to its own end does not close: it keeps finding more,
    // because the component reachable a bit at a time is most of what the part decodes. Two things are wrong with
    // taking all of it. It
    // does not close anywhere near the 16384 a machine holds: the run ends in `refused` and reports nothing. And a
    // form reached far out carries the operand bits of a chain of forms it has nothing to do with, the PLOP3.LUT
    // reading written down below -- a form that decodes and that no operation can be written from. The bound is the
    // field the lane is short of, measured, in place of a guess at how far is far enough
    unsigned int done = 0u;
    while ((done < machine->forms) && (rounds < SASS_WIDEN_ROUNDS))
    {
        const unsigned int reach = machine->forms;
        for (unsigned int number = done; number < reach; number += 1u)
        {
            sass_form_turned(&machine->form[number]);
            char path[1024];
            snprintf(path, sizeof(path), "%s/widen_%04u", folder, number);
            if (!sass_decode(architecture, path, s_low, s_high, SASS_ENCODINGS, s_texts))
            {
                failed += 1u;
                continue;
            }
            for (unsigned int bit = 0u; bit < SASS_BITS; bit += 1u)
            {
                SassInstructionParts parts;
                SassForm *kept = NULL;
                const char *const said = s_texts[1u + bit];
                // what the decoder said about this one bit, for the .ksc: it refused the encoding, it took it and
                // printed no line, or it named it. Every bit of every form goes through here: they are counted and
                // not kept whole
                sass_class_count(SASS_CHANNEL_DECODE, (strcmp(said, "illegal") == 0)     ? SASS_CLASS_ILLEGAL
                                                      : (strcmp(said, "unprinted") == 0) ? SASS_CLASS_NOTHING
                                                                                         : SASS_CLASS_ANSWERS);
                if (sass_widened_holds(said, &parts))
                {
                    sass_machine_take(machine, said, s_low[1u + bit], s_high[1u + bit], &kept);
                }
            }
        }
        done = reach;
        rounds += 1u;
    }
    printf("interface sass widen: %u forms listed, %u a bit at a time from them over %u rounds, %u forms the "
           "disassembler failed\n",
           listed, machine->forms - listed, rounds, failed);
    return machine->forms - listed;
}

int sass_machine_fields(SassMachine *machine, const char *architecture, const char *folder)
{
    unsigned int failed = 0u;
    for (unsigned int number = 0u; number < machine->forms; number += 1u)
    {
        failed += sass_form_fields(&machine->form[number], architecture, folder, number) ? 0u : 1u;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/machine", folder);
    // the disassembler spells the part SM86 and everything else here spells it sm_86
    snprintf(machine->part, sizeof(machine->part), "sm_%s", architecture + 2);
    const int written = sass_machine_write(machine, path);
    // the file read back, so that the assembler reading it elsewhere is reading what this wrote
    static SassMachine s_again;
    const int again = written && sass_machine_read(&s_again, path);
    unsigned int differed = again ? 0u : machine->forms;
    for (unsigned int number = 0u; again && (number < machine->forms); number += 1u)
    {
        const SassForm *const was = &machine->form[number];
        const SassForm *const now = &s_again.form[number];
        differed += ((number >= s_again.forms) || (was->low != now->low) || (was->high != now->high) ||
                     (was->runs != now->runs) || (strcmp(was->text, now->text) != 0))
                        ? 1u
                        : 0u;
    }
    printf("interface sass machine: %u forms of the %u it holds, %u without fields, %s, %u differing when read back, %u "
           "forms it had no room for\n",
           machine->forms, (unsigned int)SASS_MACHINE_FORMS, failed, written ? "written" : "not written", differed,
           machine->refused);
    // a machine that filled up is a machine missing forms nobody named: a truncation, not a reading
    return (written != 0) && (failed == 0u) && (differed == 0u) && (machine->refused == 0u);
}

// the carriers the sweep runs from, at most. Each is a form the part ran whose operands are shaped unlike the ones
// before it, since an operation that reads an address decodes as nothing from a carrier whose operand bits held two
// registers. More carriers reach more operations and cost a batch of decodes apiece
#define SASS_CARRIERS 8u

// The carriers picked out of the forms already held: the first form, then each later one whose operands are shaped
// unlike every carrier taken so far. A shape is the count of operands and the kind of each, and it decides
// where the bits outside the key sit. How many were taken
static unsigned int sass_sweep_carriers(const SassMachine *machine, unsigned int *carrier)
{
    unsigned int taken = 0u;
    for (unsigned int number = 0u; (number < machine->forms) && (taken < SASS_CARRIERS); number += 1u)
    {
        const SassForm *const one = &machine->form[number];
        int seen = 0;
        for (unsigned int at = 0u; at < taken; at += 1u)
        {
            const SassForm *const already = &machine->form[carrier[at]];
            int same = (already->operands == one->operands);
            for (unsigned int place = 0u; same && (place < one->operands); place += 1u)
            {
                same = (already->kind[place] == one->kind[place]);
            }
            seen = seen || same;
        }
        if (!seen)
        {
            carrier[taken] = number;
            taken += 1u;
        }
    }
    return taken;
}

unsigned int sass_machine_sweep(SassMachine *machine, const char *architecture, const char *folder)
{
    const unsigned int held = machine->forms;
    if (held == 0u)
    {
        return 0u;
    }
    unsigned int carrier[SASS_CARRIERS];
    const unsigned int carriers = sass_sweep_carriers(machine, carrier);
    unsigned int failed = 0u;
    unsigned int named = 0u;
    for (unsigned int which = 0u; which < carriers; which += 1u)
    {
        // a carrier the part is known to take, with its operation cut away. Every question below is this encoding
        // with one of the 4096 keys put back, leaving every bit outside the key as a real instruction carried it
        const unsigned long long low = machine->form[carrier[which]].low & ~SASS_OPERATION_MASK;
        const unsigned long long high = machine->form[carrier[which]].high;
        for (unsigned int first = 0u; first <= SASS_OPERATION_MASK; first += SASS_BITS)
        {
            const unsigned int count = (((unsigned long long)first + SASS_BITS) > (SASS_OPERATION_MASK + 1ull))
                                           ? ((unsigned int)(SASS_OPERATION_MASK + 1ull) - first)
                                           : SASS_BITS;
            for (unsigned int at = 0u; at < count; at += 1u)
            {
                s_low[at] = low | (unsigned long long)(first + at);
                s_high[at] = high;
            }
            char path[1024];
            snprintf(path, sizeof(path), "%s/sweep_%u_%04u", folder, which, first);
            if (!sass_decode(architecture, path, s_low, s_high, count, s_texts))
            {
                failed += 1u;
                continue;
            }
            for (unsigned int at = 0u; at < count; at += 1u)
            {
                const char *const said = s_texts[at];
                sass_class_count(SASS_CHANNEL_DECODE, (strcmp(said, "illegal") == 0)     ? SASS_CLASS_ILLEGAL
                                                      : (strcmp(said, "unprinted") == 0) ? SASS_CLASS_NOTHING
                                                                                         : SASS_CLASS_ANSWERS);
                named += ((strcmp(said, "illegal") != 0) && (strcmp(said, "unprinted") != 0)) ? 1u : 0u;
                SassInstructionParts parts;
                SassForm *kept = NULL;
                // a swept encoding came from no form, and is read the same way a widened one is: every operation the
                // decoder names, with every operand a kind the assembler can place, is one to keep
                if (sass_widened_holds(said, &parts))
                {
                    sass_machine_take(machine, said, s_low[at], s_high[at], &kept);
                }
            }
        }
    }
    printf("interface sass sweep: %u keys put to the disassembler from each of %u carriers, %u named, %u forms it had "
           "not already, %u batches the disassembler failed, %u forms past what the machine holds\n",
           (unsigned int)(SASS_OPERATION_MASK + 1ull), carriers, named, machine->forms - held, failed,
           machine->refused);
    return machine->forms - held;
}

int sass_machine_same(const SassMachine *machine, const char *machines)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", machines, machine->part);
    static SassMachine s_tree;
    if (!sass_machine_read(&s_tree, path))
    {
        printf("interface sass machine: the tree holds no %s, so this part's is the probe's alone\n", machine->part);
        return 1;
    }
    unsigned int differed = (s_tree.forms == machine->forms) ? 0u : 1u;
    for (unsigned int number = 0u; (number < machine->forms) && (number < s_tree.forms); number += 1u)
    {
        const SassForm *const filled = &s_tree.form[number];
        const SassForm *const found = &machine->form[number];
        differed += ((filled->low != found->low) || (filled->high != found->high) ||
                     (strcmp(filled->text, found->text) != 0) || (filled->runs != found->runs))
                        ? 1u
                        : 0u;
    }
    printf("interface sass machine: the tree's %s holds %u forms, %u of them differing from this run's\n",
           machine->part, s_tree.forms, differed);
    if (differed != 0u)
    {
        printf("  the part or its toolchain has moved: copy the run's machine over %s\n", path);
    }
    return (differed == 0u) ? 1 : 0;
}
