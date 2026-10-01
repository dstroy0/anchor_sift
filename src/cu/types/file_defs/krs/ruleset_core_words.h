// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ruleset_core_words.h: the reader's types, words and texts cut at their parameters (ruleset_core.h includes the parts
// in order)
#ifndef RULESET_CORE_WORDS_H
#define RULESET_CORE_WORDS_H

// The .krs reader past opening the file, ported word for word from the host's (target_parse.cu and
// target_rulesets.cu as they were): the file's lines read against the schema into each bank's, fixed register's and
// form's written form and each construct's lines, and the scratch each form takes (ruleset_scratch). A string the host
// held is a span of the file or of the texts the reader writes; a list is a span of one list the reader appends to.
// The device runs it in one thread (codegen_reader.cu), since each line is read against every line before it.
// The memory is the caller's, sized from the file (ruleset_core_capacities), which no read passes; where the host
// errored, the read ends with why, and the caller writes the host's reason from it

#include "../../../transpiler/codegen/machine_ir_types.h"

// what one argument of a construct's line is, as PseudoOperandKind gives it
#define RULESET_CORE_TEXT 0u
#define RULESET_CORE_PARAMETER 1u
#define RULESET_CORE_SCRATCH 2u

// How a form was given, held in form_given. A ruleset gives every form of its schema one of three ways, and each
// way is deliberate: there is no way to leave a form blank and have it pass.
//
//     form <name> <parameter>... = <text>   the language writes this, and the text is how
//     nop <name> <parameter>...             the language needs no instruction here, or has no such thing at all
//     err <name> <parameter>...             the operation is an error on this language
//
// A nop writes nothing and the lane goes on without it. An err writes nothing and breaks the lane: a program that
// needs one is refused, in place of being written with a hole in it. `form` with nothing after the equals is not a
// third meaning, it is a file that has not said which of these it means, and the read ends on it
#define RULESET_CORE_NOT_GIVEN 0u
#define RULESET_CORE_GIVEN 1u
#define RULESET_CORE_GIVEN_NOP 2u
#define RULESET_CORE_GIVEN_ERR 3u

// how a read ended: read, or the reason the host gave, by the line it was on where it was on one
enum RulesetCoreEnd
{
    RULESET_CORE_OK = 0,
    RULESET_CORE_NOT_KRS = 1,
    RULESET_CORE_NOT_ONE_WORD = 2,
    RULESET_CORE_BANK_WRONG = 3,
    RULESET_CORE_REGISTER_WRONG = 4,
    RULESET_CORE_FORM_WRONG = 5,
    RULESET_CORE_CONSTRUCT_WRONG = 6,
    RULESET_CORE_NO_KIND = 7,
    RULESET_CORE_NO_LINES = 8,
    RULESET_CORE_LINE_FORM = 9,
    RULESET_CORE_SCRATCH_WORD = 10,
    RULESET_CORE_NO_END = 11,
    RULESET_CORE_BANK_MISSING = 12,
    RULESET_CORE_REGISTER_MISSING = 13,
    RULESET_CORE_FORM_MISSING = 14,
    RULESET_CORE_UNNAMED = 15
};

// a string as the reader holds it: where its letters begin, and how many
struct RulesetCoreSpan
{
    unsigned int first;
    unsigned int length;
};

// the schema as the reader takes it: each name's letters in `letters`, and each form's count of parameters
struct RulesetCoreSchema
{
    const unsigned char *letters;
    const RulesetCoreSpan *forms;
    const unsigned int *form_parameters;
    unsigned int form_count;
    const RulesetCoreSpan *banks;
    unsigned int bank_count;
    const RulesetCoreSpan *fixed;
    unsigned int fixed_count;
};

// an InstrTemplate: its pieces, spans of the texts the reader wrote, and its slots, one fewer than its pieces
struct RulesetCoreTemplate
{
    unsigned int piece_first;
    unsigned int piece_count;
    unsigned int slot_first;
};

// a PseudoOperand, its text a span of the file
struct RulesetCoreArgument
{
    unsigned int kind;
    unsigned int slot;
    unsigned int number;
    RulesetCoreSpan text;
};

// a PseudoLine, its arguments a span of the reader's arguments
struct RulesetCoreLine
{
    unsigned int form;
    unsigned int argument_first;
    unsigned int argument_count;
};

// a Pseudo: its lines, a span of the reader's lines, which one construct's are since one is read at a time
struct RulesetCoreConstruct
{
    unsigned int line_first;
    unsigned int line_count;
};

// a read: the schema and the file, the capacities the caller sized, what the reader writes, and how it ended: the end,
// the line it ended on, the bank, register or form it names and the word of the file it names
struct RulesetCoreRead
{
    RulesetCoreSchema schema;
    const unsigned char *text;
    unsigned int text_length;
    unsigned int letter_capacity;
    unsigned int piece_capacity;
    unsigned int word_capacity;
    unsigned char *letters;
    unsigned int letter_count;
    RulesetCoreSpan *pieces;
    unsigned int piece_count;
    unsigned int *slots;
    unsigned int slot_count;
    RulesetCoreSpan *words;
    unsigned int word_count;
    RulesetCoreTemplate *banks;
    RulesetCoreSpan *fixed;
    RulesetCoreTemplate *forms;
    RulesetCoreConstruct *constructs;
    RulesetCoreLine *lines;
    unsigned int line_count;
    RulesetCoreArgument *arguments;
    unsigned int argument_count;
    unsigned char *bank_given;
    unsigned char *fixed_given;
    unsigned char *form_given;
    RulesetCoreSpan name;
    RulesetCoreSpan toolchain;
    RulesetCoreSpan header;
    unsigned int building;
    RulesetCoreSpan *building_parameters;
    unsigned int building_parameter_count;
    unsigned int end;
    unsigned int line;
    unsigned int at;
    RulesetCoreSpan word;
};

// the parameter a bank's written form takes, the register's number
#define RULESET_CORE_BANK_PARAMETER "n"

// 1 where the `length` letters at `left` are the `other` letters at `right`, as std::string's == gives it
CODEGEN_CORE int ruleset_core_equal(const unsigned char *left, unsigned int length, const unsigned char *right,
                                    unsigned int other)
{
    int equal = length == other;
    for (unsigned int at = 0u; (equal != 0) && (at < length); at += 1u)
    {
        equal = left[at] == right[at];
    }
    return equal;
}

// 1 where the file's span `word` is the text `literal`
CODEGEN_CORE int ruleset_core_is(const RulesetCoreRead *read, RulesetCoreSpan word, const char *literal)
{
    unsigned int length = 0u;
    while (literal[length] != '\0')
    {
        length += 1u;
    }
    return ruleset_core_equal(&read->text[word.first], word.length, (const unsigned char *)literal, length);
}

// the place of `letter` in the file's span `within` from `from` on, or its length where it is not there, as
// std::string::find gives it and the length stands for npos
CODEGEN_CORE unsigned int ruleset_core_find_letter(const RulesetCoreRead *read, RulesetCoreSpan within,
                                                   unsigned char letter, unsigned int from)
{
    unsigned int found = within.length;
    for (unsigned int at = from; (found == within.length) && (at < within.length); at += 1u)
    {
        found = (read->text[within.first + at] == letter) ? at : found;
    }
    return found;
}

// the file's span `word` from `at`, `length` letters long, as std::string::substr gives it
CODEGEN_CORE RulesetCoreSpan ruleset_core_part(RulesetCoreSpan word, unsigned int at, unsigned int length)
{
    const unsigned int kept = (length < (word.length - at)) ? length : (word.length - at);
    const RulesetCoreSpan part = {word.first + at, kept};
    return part;
}

// the place of the file's span `word` among `count` names of the schema, or `count` where it is none of them
CODEGEN_CORE unsigned int ruleset_core_find(const RulesetCoreRead *read, const RulesetCoreSpan *names,
                                            unsigned int count, RulesetCoreSpan word)
{
    unsigned int found = count;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = ruleset_core_equal(&read->text[word.first], word.length, &read->schema.letters[names[at].first],
                                   names[at].length)
                    ? at
                    : found;
    }
    return found;
}

// the words of the file's span `head`, split at its spaces, into the reader's words; their count returned
CODEGEN_CORE unsigned int ruleset_core_words(RulesetCoreRead *read, RulesetCoreSpan head)
{
    read->word_count = 0u;
    unsigned int at = 0u;
    while (at < head.length)
    {
        const unsigned int end = ruleset_core_find_letter(read, head, (unsigned char)' ', at);
        if (end > at)
        {
            const RulesetCoreSpan word = {head.first + at, end - at};
            read->words[read->word_count] = word;
            read->word_count += 1u;
        }
        at = end + 1u;
    }
    return read->word_count;
}

// a piece begun after the pieces written, empty
CODEGEN_CORE void ruleset_core_piece(RulesetCoreRead *read)
{
    const RulesetCoreSpan piece = {read->letter_count, 0u};
    read->pieces[read->piece_count] = piece;
    read->piece_count += 1u;
}

// `letter` written onto the last piece, which the letters written end with
CODEGEN_CORE void ruleset_core_letter(RulesetCoreRead *read, unsigned char letter)
{
    read->letters[read->letter_count] = letter;
    read->letter_count += 1u;
    read->pieces[read->piece_count - 1u].length += 1u;
}

// the file's span `text` cut at its parameters into `form`, as ruleset_split cuts it: \t, \n and \\ are a tab, a
// line's end and a backslash, and {p} is parameter p's argument where p is one of the `count` `parameters`, each a span
// of `parameter_letters`. 0 where a backslash begins no escape the format knows
CODEGEN_CORE int ruleset_core_split(RulesetCoreRead *read, RulesetCoreSpan text, const unsigned char *parameter_letters,
                                    const RulesetCoreSpan *parameters, unsigned int count, RulesetCoreTemplate *form)
{
    form->piece_first = read->piece_count;
    form->slot_first = read->slot_count;
    ruleset_core_piece(read);
    unsigned int at = 0u;
    while (at < text.length)
    {
        const unsigned char character = read->text[text.first + at];
        const unsigned char next = ((at + 1u) < text.length) ? read->text[text.first + at + 1u] : (unsigned char)'\0';
        const unsigned int close =
            (character == '{') ? ruleset_core_find_letter(read, text, (unsigned char)'}', at + 1u) : text.length;
        unsigned int slot = count;
        for (unsigned int parameter = 0u; (close != text.length) && (parameter < count); parameter += 1u)
        {
            slot = ruleset_core_equal(&read->text[text.first + at + 1u], close - (at + 1u),
                                      &parameter_letters[parameters[parameter].first], parameters[parameter].length)
                       ? parameter
                       : slot;
        }
        if ((character == '\\') && (next != 't') && (next != 'n') && (next != '\\'))
        {
            form->piece_count = read->piece_count - form->piece_first;
            return 0;
        }
        if (character == '\\')
        {
            ruleset_core_letter(read, (next == 't') ? (unsigned char)'\t'
                                                    : ((next == 'n') ? (unsigned char)'\n' : (unsigned char)'\\'));
            at += 2u;
        }
        else if (slot < count)
        {
            read->slots[read->slot_count] = slot;
            read->slot_count += 1u;
            ruleset_core_piece(read);
            at = close + 1u;
        }
        else
        {
            ruleset_core_letter(read, character);
            at += 1u;
        }
    }
    form->piece_count = read->piece_count - form->piece_first;
    return 1;
}

#endif
