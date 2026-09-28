// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ruleset_core_read.h: a ruleset's entries, constructs' lines and file read (ruleset_core.h includes the parts in
// order)
#ifndef RULESET_CORE_READ_H
#define RULESET_CORE_READ_H

#include "ruleset_core_words.h"

// the read ended with `end`, naming the bank, register or form `at` and the file's span `word`; 0 returned
CODEGEN_CORE int ruleset_core_ended(RulesetCoreRead *read, unsigned int end, unsigned int at, RulesetCoreSpan word)
{
    read->end = end;
    read->at = at;
    read->word = word;
    return 0;
}

// one entry of a ruleset, `kind` the first word of its line and `rest` the rest of the line, read against the
// ruleset's schema, as ruleset_entry reads it: 1 where the entry holds, else 0 and why in the read's end
CODEGEN_CORE int ruleset_core_entry(RulesetCoreRead *read, RulesetCoreSpan kind, RulesetCoreSpan rest)
{
    const RulesetCoreSchema *const schema = &read->schema;
    // a named entry's head is its name and parameters, and its text follows the head's "= "
    const unsigned int equals = ruleset_core_find_letter(read, rest, (unsigned char)'=', 0u);
    const int has_equals = equals != rest.length;
    const unsigned int head_count = ruleset_core_words(read, ruleset_core_part(rest, 0u, equals));
    const unsigned int text_at =
        (has_equals == 0)
            ? rest.length
            : ((((equals + 1u) < rest.length) && (read->text[rest.first + equals + 1u] == ' ')) ? (equals + 2u)
                                                                                                : (equals + 1u));
    const RulesetCoreSpan text = ruleset_core_part(rest, text_at, rest.length);
    const RulesetCoreSpan none = {0u, 0u};
    const RulesetCoreSpan name = (head_count == 0u) ? none : read->words[0];
    const RulesetCoreSpan *const parameters = &read->words[1];
    const unsigned int parameter_count = (head_count == 0u) ? 0u : (head_count - 1u);
    RulesetCoreTemplate form = {0u, 0u, 0u};
    if (ruleset_core_is(read, kind, "ruleset") || ruleset_core_is(read, kind, "toolchain") ||
        ruleset_core_is(read, kind, "header"))
    {
        RulesetCoreSpan *const value = ruleset_core_is(read, kind, "ruleset")     ? &read->name
                                       : ruleset_core_is(read, kind, "toolchain") ? &read->toolchain
                                                                                  : &read->header;
        if ((has_equals != 0) || (head_count != 1u) || (value->length != 0u))
        {
            return ruleset_core_ended(read, RULESET_CORE_NOT_ONE_WORD, 0u, kind);
        }
        *value = name;
        return 1;
    }
    if (ruleset_core_is(read, kind, "bank"))
    {
        const unsigned int bank = ruleset_core_find(read, schema->banks, schema->bank_count, name);
        const RulesetCoreSpan bank_parameter = {0u, 1u};
        if ((has_equals == 0) || (bank == schema->bank_count) || (parameter_count != 0u) ||
            (read->bank_given[bank] != 0u) ||
            !ruleset_core_split(read, text, (const unsigned char *)RULESET_CORE_BANK_PARAMETER, &bank_parameter, 1u,
                                &form))
        {
            return ruleset_core_ended(read, RULESET_CORE_BANK_WRONG, 0u, name);
        }
        read->banks[bank] = form;
        read->bank_given[bank] = 1u;
        return 1;
    }
    if (ruleset_core_is(read, kind, "fixed"))
    {
        const unsigned int fixed = ruleset_core_find(read, schema->fixed, schema->fixed_count, name);
        if ((has_equals == 0) || (fixed == schema->fixed_count) || (parameter_count != 0u) ||
            (read->fixed_given[fixed] != 0u) || !ruleset_core_split(read, text, read->text, parameters, 0u, &form))
        {
            return ruleset_core_ended(read, RULESET_CORE_REGISTER_WRONG, 0u, name);
        }
        read->fixed[fixed] = read->pieces[form.piece_first];
        read->fixed_given[fixed] = 1u;
        return 1;
    }
    if (ruleset_core_is(read, kind, "form"))
    {
        const unsigned int named = ruleset_core_find(read, schema->forms, schema->form_count, name);
        if ((has_equals == 0) || (named == schema->form_count) || (parameter_count != schema->form_parameters[named]) ||
            (read->form_given[named] != 0u) ||
            !ruleset_core_split(read, text, read->text, parameters, parameter_count, &form))
        {
            return ruleset_core_ended(read, RULESET_CORE_FORM_WRONG, 0u, name);
        }
        read->forms[named] = form;
        read->form_given[named] = 1u;
        return 1;
    }
    if (ruleset_core_is(read, kind, "construct"))
    {
        // a construct's head is its name and parameters as a form's is, with no text: its lines follow, to `end`
        const unsigned int named = ruleset_core_find(read, schema->forms, schema->form_count, name);
        if ((has_equals != 0) || (named == schema->form_count) || (parameter_count != schema->form_parameters[named]) ||
            (read->form_given[named] != 0u))
        {
            return ruleset_core_ended(read, RULESET_CORE_CONSTRUCT_WRONG, 0u, name);
        }
        read->building = named;
        for (unsigned int parameter = 0u; parameter < parameter_count; parameter += 1u)
        {
            read->building_parameters[parameter] = parameters[parameter];
        }
        read->building_parameter_count = parameter_count;
        read->constructs[named].line_first = read->line_count;
        read->constructs[named].line_count = 0u;
        return 1;
    }
    return ruleset_core_ended(read, RULESET_CORE_NO_KIND, 0u, kind);
}

// one line of the construct being read, as ruleset_pseudo_line reads it: `end` closes it, and any other line is a
// form, or a construct given before it in the file, and its arguments, split at spaces. 1 where the line holds, else 0
// and why in the read's end
CODEGEN_CORE int ruleset_core_pseudo_line(RulesetCoreRead *read, RulesetCoreSpan line)
{
    const RulesetCoreSchema *const schema = &read->schema;
    RulesetCoreConstruct *const construct = &read->constructs[read->building];
    const RulesetCoreSpan none = {0u, 0u};
    if (ruleset_core_is(read, line, "end"))
    {
        if (construct->line_count == 0u)
        {
            return ruleset_core_ended(read, RULESET_CORE_NO_LINES, read->building, none);
        }
        read->form_given[read->building] = 1u;
        read->building = schema->form_count;
        return 1;
    }
    const unsigned int word_count = ruleset_core_words(read, line);
    const unsigned int named = (word_count == 0u)
                                   ? schema->form_count
                                   : ruleset_core_find(read, schema->forms, schema->form_count, read->words[0]);
    // a form or construct the file has given already: one given later, or the construct itself, would make a loop
    if ((named == schema->form_count) || (read->form_given[named] == 0u) ||
        ((word_count - 1u) != schema->form_parameters[named]))
    {
        return ruleset_core_ended(read, RULESET_CORE_LINE_FORM, read->building,
                                  (word_count == 0u) ? none : read->words[0]);
    }
    RulesetCoreLine written = {named, read->argument_count, 0u};
    for (unsigned int at = 1u; at < word_count; at += 1u)
    {
        const RulesetCoreSpan word = read->words[at];
        RulesetCoreArgument argument = {RULESET_CORE_TEXT, 0u, 0u, word};
        for (unsigned int parameter = 0u; parameter < read->building_parameter_count; parameter += 1u)
        {
            if (ruleset_core_equal(&read->text[word.first], word.length,
                                   &read->text[read->building_parameters[parameter].first],
                                   read->building_parameters[parameter].length))
            {
                argument.kind = RULESET_CORE_PARAMETER;
                argument.slot = parameter;
            }
        }
        const unsigned int colon = ruleset_core_find_letter(read, word, (unsigned char)':', 0u);
        const int braced = (word.length > 4u) && (read->text[word.first] == '{') &&
                           (read->text[word.first + word.length - 1u] == '}') && (colon != word.length);
        if (braced)
        {
            const unsigned int bank =
                ruleset_core_find(read, schema->banks, schema->bank_count, ruleset_core_part(word, 1u, colon - 1u));
            const RulesetCoreSpan digits = ruleset_core_part(word, colon + 1u, word.length - colon - 2u);
            int counted = (digits.length != 0u) && (digits.length < 6u);
            unsigned int number = 0u;
            for (unsigned int digit = 0u; digit < digits.length; digit += 1u)
            {
                const unsigned char letter = read->text[digits.first + digit];
                counted = counted && (letter >= '0') && (letter <= '9');
                number = (number * 10u) + (unsigned int)(letter - '0');
            }
            if ((bank == schema->bank_count) || !counted)
            {
                return ruleset_core_ended(read, RULESET_CORE_SCRATCH_WORD, read->building, word);
            }
            argument.kind = RULESET_CORE_SCRATCH;
            argument.slot = bank;
            // five digits at most, which fits in 32 bits
            argument.number = number;
        }
        read->arguments[read->argument_count] = argument;
        read->argument_count += 1u;
    }
    written.argument_count = read->argument_count - written.argument_first;
    read->lines[read->line_count] = written;
    read->line_count += 1u;
    construct->line_count += 1u;
    return 1;
}

// the file read into the read against its schema, as ruleset_read reads it past opening the file: its first line is
// krs 1, every entry holds, and every bank, fixed register and form the code generator names is given with the
// ruleset's name, toolchain and header, else the read ends with why. A line that begins with # is a comment, and a
// blank line is nothing
CODEGEN_CORE void ruleset_core_read(RulesetCoreRead *read)
{
    const RulesetCoreSchema *const schema = &read->schema;
    const RulesetCoreSpan none = {0u, 0u};
    const RulesetCoreTemplate empty = {0u, 0u, 0u};
    read->letter_count = 0u;
    read->piece_count = 0u;
    read->slot_count = 0u;
    read->line_count = 0u;
    read->argument_count = 0u;
    read->name = none;
    read->toolchain = none;
    read->header = none;
    read->building = schema->form_count;
    read->building_parameter_count = 0u;
    read->end = RULESET_CORE_OK;
    read->line = 0u;
    read->at = 0u;
    read->word = none;
    for (unsigned int bank = 0u; bank < schema->bank_count; bank += 1u)
    {
        read->banks[bank] = empty;
        read->bank_given[bank] = 0u;
    }
    for (unsigned int fixed = 0u; fixed < schema->fixed_count; fixed += 1u)
    {
        read->fixed[fixed] = none;
        read->fixed_given[fixed] = 0u;
    }
    for (unsigned int form = 0u; form < schema->form_count; form += 1u)
    {
        read->forms[form] = empty;
        read->form_given[form] = 0u;
        read->constructs[form].line_first = 0u;
        read->constructs[form].line_count = 0u;
    }
    const RulesetCoreSpan file = {0u, read->text_length};
    unsigned int number = 0u;
    unsigned int at = 0u;
    int holds = 1;
    while ((at < read->text_length) && (holds != 0))
    {
        const unsigned int end = ruleset_core_find_letter(read, file, (unsigned char)'\n', at);
        // a checkout that ends its lines with a carriage return as well leaves each line as it was written
        const unsigned int kept = ((end > at) && (read->text[end - 1u] == '\r')) ? (end - 1u) : end;
        const RulesetCoreSpan line = {at, kept - at};
        number += 1u;
        at = end + 1u;
        const unsigned int space = ruleset_core_find_letter(read, line, (unsigned char)' ', 0u);
        const int constructing = read->building != schema->form_count;
        read->line = number;
        if (number == 1u)
        {
            holds = ruleset_core_is(read, line, "krs 1") ? 1 : ruleset_core_ended(read, RULESET_CORE_NOT_KRS, 0u, none);
        }
        else if ((line.length == 0u) || (read->text[line.first] == '#'))
        {
            holds = 1;
        }
        else if (constructing)
        {
            holds = ruleset_core_pseudo_line(read, line);
        }
        else
        {
            const RulesetCoreSpan rest =
                (space == line.length) ? none : ruleset_core_part(line, space + 1u, line.length);
            holds = ruleset_core_entry(read, ruleset_core_part(line, 0u, space), rest);
        }
    }
    if (holds == 0)
    {
        return;
    }
    read->line = 0u;
    if (read->building != schema->form_count)
    {
        ruleset_core_ended(read, RULESET_CORE_NO_END, read->building, none);
        return;
    }
    for (unsigned int bank = 0u; bank < schema->bank_count; bank += 1u)
    {
        if (read->bank_given[bank] == 0u)
        {
            ruleset_core_ended(read, RULESET_CORE_BANK_MISSING, bank, none);
            return;
        }
    }
    for (unsigned int fixed = 0u; fixed < schema->fixed_count; fixed += 1u)
    {
        if (read->fixed_given[fixed] == 0u)
        {
            ruleset_core_ended(read, RULESET_CORE_REGISTER_MISSING, fixed, none);
            return;
        }
    }
    for (unsigned int named = 0u; named < schema->form_count; named += 1u)
    {
        if (read->form_given[named] == 0u)
        {
            ruleset_core_ended(read, RULESET_CORE_FORM_MISSING, named, none);
            return;
        }
    }
    if ((read->name.length == 0u) || (read->toolchain.length == 0u) || (read->header.length == 0u))
    {
        ruleset_core_ended(read, RULESET_CORE_UNNAMED, 0u, none);
    }
}

#endif
