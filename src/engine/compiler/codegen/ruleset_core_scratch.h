// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ruleset_core_scratch.h: the scratch each form of a ruleset takes (ruleset_core.h includes the parts in order)
#ifndef RULESET_CORE_SCRATCH_H
#define RULESET_CORE_SCRATCH_H

#include "ruleset_core_words.h"

// where a form's scratch is being laid out: the form, the line of its construct being read, 1 once that line's
// arguments are taken and its form laid out, and where the registers it has taken begin among those taken
struct RulesetCoreFrame
{
    unsigned int name;
    unsigned int line;
    unsigned int line_end;
    unsigned int laid_out;
    unsigned int taken_first;
};

// the scratch of every form of a read ruleset: the constructs, lines and arguments read, the banks at places 0, 1 and
// 2, and the memory the caller gives: the scratch itself, four words a form, which forms are counted, a frame a form,
// and the registers taken, as many as there are arguments
struct RulesetCoreScratch
{
    const RulesetCoreConstruct *constructs;
    const RulesetCoreLine *lines;
    const RulesetCoreArgument *arguments;
    unsigned int form_count;
    unsigned int banks[3];
    unsigned int *scratch;
    unsigned char *counted;
    RulesetCoreFrame *frames;
    unsigned int *taken_bank;
    unsigned int *taken_number;
};

// form `name`'s frame begun where it is not counted yet, as ruleset_scratch_of begins; the frames held returned
CODEGEN_CORE unsigned int ruleset_core_scratch_enter(RulesetCoreScratch *scratch, unsigned int name, unsigned int depth,
                                                     unsigned int taken_top)
{
    if (scratch->counted[name] != 0u)
    {
        return depth;
    }
    scratch->counted[name] = 1u;
    const RulesetCoreConstruct *const construct = &scratch->constructs[name];
    const RulesetCoreFrame frame = {name, construct->line_first, construct->line_first + construct->line_count, 0u,
                                    taken_top};
    scratch->frames[depth] = frame;
    return depth + 1u;
}

// the scratch form `name` takes in one writing, laid out into its four words of the scratch once and marked counted, as
// ruleset_scratch_of lays it out: each scratch register its lines name, once, and what each form its lines write takes,
// which a construct given before it in the file has laid out, and the recursion ends. The host's recursion is held in
// the frames, a form each at most, each line's form laid out before the line's scratch is added, as the host adds it
CODEGEN_CORE void ruleset_core_scratch_of(RulesetCoreScratch *scratch, unsigned int name)
{
    unsigned int taken_top = 0u;
    unsigned int depth = ruleset_core_scratch_enter(scratch, name, 0u, taken_top);
    while (depth != 0u)
    {
        RulesetCoreFrame *const frame = &scratch->frames[depth - 1u];
        if (frame->line == frame->line_end)
        {
            taken_top = frame->taken_first;
            depth -= 1u;
            continue;
        }
        const RulesetCoreLine *const line = &scratch->lines[frame->line];
        unsigned int *const own = &scratch->scratch[4u * frame->name];
        if (frame->laid_out == 0u)
        {
            for (unsigned int given_at = 0u; given_at < line->argument_count; given_at += 1u)
            {
                const RulesetCoreArgument *const given = &scratch->arguments[line->argument_first + given_at];
                int found = 0;
                for (unsigned int at = frame->taken_first; (given->kind == RULESET_CORE_SCRATCH) && (at < taken_top);
                     at += 1u)
                {
                    found = found ||
                            ((scratch->taken_bank[at] == given->slot) && (scratch->taken_number[at] == given->number));
                }
                if ((given->kind != RULESET_CORE_SCRATCH) || (found != 0))
                {
                    continue;
                }
                scratch->taken_bank[taken_top] = given->slot;
                scratch->taken_number[taken_top] = given->number;
                taken_top += 1u;
                const unsigned int bank_index =
                    (given->slot == scratch->banks[0])
                        ? 0u
                        : ((given->slot == scratch->banks[1]) ? 1u : ((given->slot == scratch->banks[2]) ? 2u : 3u));
                own[bank_index] = (bank_index == 3u) ? 1u : (own[bank_index] + 1u);
            }
            frame->laid_out = 1u;
            depth = ruleset_core_scratch_enter(scratch, line->form, depth, taken_top);
            continue;
        }
        const unsigned int *const written = &scratch->scratch[4u * line->form];
        for (unsigned int bank_index = 0u; bank_index < 3u; bank_index += 1u)
        {
            own[bank_index] += written[bank_index];
        }
        own[3] |= written[3];
        frame->line += 1u;
        frame->laid_out = 0u;
    }
}

// the scratch each form of the ruleset takes in one writing, four words a form by its place in the schema, as
// ruleset_scratch lays it out
CODEGEN_CORE void ruleset_core_scratch(RulesetCoreScratch *scratch)
{
    for (unsigned int word = 0u; word < (4u * scratch->form_count); word += 1u)
    {
        scratch->scratch[word] = 0u;
    }
    for (unsigned int name = 0u; name < scratch->form_count; name += 1u)
    {
        scratch->counted[name] = 0u;
    }
    for (unsigned int name = 0u; name < scratch->form_count; name += 1u)
    {
        ruleset_core_scratch_of(scratch, name);
    }
}

#endif
