// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <cstddef>
#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
static int cycle_program_operand(const EngineRecordLayout *layout, unsigned int at, unsigned int operand,
                                 unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= layout->step_table[operand].limbs);
}

static int cycle_program_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

// 1 where the operation reads a left register: every one but the fields, the constant and the lane's number
static int cycle_program_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED)
        && (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid: its operands are earlier steps, each read whole (a table
// reads its source's low limb alone, and key_schedule leaves its left_limbs 0), its own limbs lie inside the file, and
// a field reads a member the program has, a signed field's top bit inside its limbs. A step that fails this leaves the
// whole program on the interpreter
static int cycle_program_held(const EngineRecordLayout *layout, unsigned int at)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const int reads_left = cycle_program_reads_left(operation);
    const int reads_left_whole = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at))
        && !(reads_left_whole && !cycle_program_operand(layout, at, step->left, step->left_limbs))
        && !(cycle_program_reads_right(operation) && !cycle_program_operand(layout, at, step->right, step->right_limbs))
        && (((unsigned long long)step->place + step->limbs) <= (unsigned long long)layout->file_limbs)
        && (!field || (step->member < layout->members))
        && ((operation != ENGINE_RECORD_FIELD_SIGNED)
            || ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// the width the divisions and the ladder share one scratch at: the widest any of them reads or writes, 0 for none
static unsigned int cycle_program_wide(const EngineRecordLayout *layout)
{
    unsigned int wide = 0u;
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        const DeviceRecordStep *const step = &layout->step_table[at];
        const unsigned int operation = step->operation;
        if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
            || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
            || (operation == ENGINE_RECORD_LADDER))
        {
            wide = (step->left_limbs > wide) ? step->left_limbs : wide;
            wide = (step->right_limbs > wide) ? step->right_limbs : wide;
            wide = (step->limbs > wide) ? step->limbs : wide;
        }
    }
    return wide;
}

// a thread's places: the file's, then the scratch's where the program divides or climbs the ladder. The ladder's rung
// and its multiple take right_limbs + 4 of them, inside the divisions' 5 * wide + 4
unsigned int cycle_program_places(const EngineRecordLayout *layout)
{
    const unsigned int wide = cycle_program_wide(layout);
    return layout->file_limbs + ((wide != 0u) ? CYCLE_RECORD_SCRATCH(wide) : 0u);
}

// The rulesets a lane is written in, one a target, each read once a process from its .krs file in
// engine/base/emit/rulesets, or in the folder $CYCLE_RULESETS names: ptx.krs for the lane as PTX and c.krs for the lane
// as C source. The format is the comment at the head of ptx.krs. Each emitter names every bank of registers it takes
// from, every register it passes to a form by name, and every form it writes with the parameters each takes, in its
// schema below; a ruleset that lacks one of them, holds one they do not name, or gives a form other parameters is
// refused whole. A refused ptx.krs sends programs to the C source, and a refused c.krs leaves the programs the PTX
// does not hold on the interpreter. A form is kept cut at its parameters, so writing one appends its pieces with each
// argument between them

// every form the emitter writes: its name here, its name in a .krs file, and how many parameters it takes
#define CYCLE_FORMS(form_) \
    form_(PROGRAM_NOTE, "program_note", 6u) \
    form_(SHARED_EXTERN, "shared_extern", 0u) \
    form_(CALLEE_DECLARE_ANSWERED, "callee_declare_answered", 1u) \
    form_(CALLEE_DECLARE, "callee_declare", 1u) \
    form_(CALLEE_PARAMETER, "callee_parameter", 2u) \
    form_(CALLEE_PARAMETER_LAST, "callee_parameter_last", 2u) \
    form_(CALLEE_CLOSE, "callee_close", 0u) \
    form_(LANE_OPEN, "lane_open", 0u) \
    form_(LANE_BODY, "lane_body", 0u) \
    form_(LANE_CLOSE, "lane_close", 0u) \
    form_(DECLARE_PREDICATES, "declare_predicates", 1u) \
    form_(DECLARE_FIXED_PREDICATES, "declare_fixed_predicates", 0u) \
    form_(DECLARE_FILE, "declare_file", 1u) \
    form_(DECLARE_SIGNS, "declare_signs", 1u) \
    form_(DECLARE_OUT, "declare_out", 1u) \
    form_(DECLARE_ATOMS, "declare_atoms", 1u) \
    form_(DECLARE_TEMPORARIES, "declare_temporaries", 1u) \
    form_(DECLARE_WIDES, "declare_wides", 1u) \
    form_(DECLARE_FIXED_WORDS, "declare_fixed_words", 0u) \
    form_(DECLARE_FIXED_WIDES, "declare_fixed_wides", 0u) \
    form_(DECLARE_MEMBERS, "declare_members", 1u) \
    form_(OPEN_LAUNCH, "open_launch", 0u) \
    form_(LAUNCH_LOAD, "launch_load", 2u) \
    form_(TO_GLOBAL, "to_global", 1u) \
    form_(SHARED_OPEN, "shared_open", 0u) \
    form_(SHARED_CLOSE, "shared_close", 0u) \
    form_(GUARDED_LOAD, "guarded_load", 3u) \
    form_(GUARDED_WIDEN, "guarded_widen", 3u) \
    form_(OPEN_REFUSED_UNLESS, "open_refused_unless", 1u) \
    form_(REFUSE, "refuse", 2u) \
    form_(LABEL_REFUSED_OPEN, "label_refused_open", 0u) \
    form_(LABEL_REFUSED, "label_refused", 1u) \
    form_(COUNT_ADD, "count_add", 1u) \
    form_(RETURN, "return", 0u) \
    form_(STEP_NOTE, "step_note", 2u) \
    form_(ADD_ALONE, "add_alone", 3u) \
    form_(ADD_FIRST, "add_first", 3u) \
    form_(ADD_MIDDLE, "add_middle", 3u) \
    form_(ADD_LAST, "add_last", 3u) \
    form_(SUBTRACT_ALONE, "subtract_alone", 3u) \
    form_(SUBTRACT_FIRST, "subtract_first", 3u) \
    form_(SUBTRACT_MIDDLE, "subtract_middle", 3u) \
    form_(SUBTRACT_LAST, "subtract_last", 3u) \
    form_(BORROW_ALONE, "borrow_alone", 3u) \
    form_(BORROW_FIRST, "borrow_first", 3u) \
    form_(BORROW_MIDDLE, "borrow_middle", 3u) \
    form_(BORROW_LAST, "borrow_last", 3u) \
    form_(BORROW_READ, "borrow_read", 2u) \
    form_(WORD_COPY, "word_copy", 2u) \
    form_(WORD_SET, "word_set", 2u) \
    form_(WORD_AND, "word_and", 3u) \
    form_(WORD_OR, "word_or", 3u) \
    form_(WORD_XOR, "word_xor", 3u) \
    form_(WORD_SHIFT_LEFT, "word_shift_left", 3u) \
    form_(WORD_SHIFT_RIGHT, "word_shift_right", 3u) \
    form_(WORD_FUNNEL_RIGHT, "word_funnel_right", 4u) \
    form_(WORD_MULTIPLY, "word_multiply", 3u) \
    form_(WORD_MULTIPLY_ADD, "word_multiply_add", 4u) \
    form_(WORD_DIVIDE, "word_divide", 3u) \
    form_(WORD_SELECT, "word_select", 4u) \
    form_(PRODUCT_LOW, "product_low", 4u) \
    form_(PRODUCT_HIGH, "product_high", 3u) \
    form_(SIGN_SET, "sign_set", 2u) \
    form_(SIGN_SELECT, "sign_select", 4u) \
    form_(SIGN_MULTIPLY, "sign_multiply", 3u) \
    form_(SIGN_ABSOLUTE, "sign_absolute", 2u) \
    form_(SIGN_NEGATE, "sign_negate", 2u) \
    form_(TEST_NONZERO, "test_nonzero", 2u) \
    form_(TEST_ZERO, "test_zero", 2u) \
    form_(TEST_NEGATIVE, "test_negative", 2u) \
    form_(TEST_SIGNED_ZERO, "test_signed_zero", 2u) \
    form_(TEST_SIGNED_DIFFER, "test_signed_differ", 3u) \
    form_(TEST_SIGNED_GREATER, "test_signed_greater", 3u) \
    form_(TEST_WIDE_NONZERO, "test_wide_nonzero", 2u) \
    form_(TEST_WIDE_EQUAL, "test_wide_equal", 3u) \
    form_(TEST_WIDE_BELOW, "test_wide_below", 3u) \
    form_(TEST_WIDE_BELOW_AND, "test_wide_below_and", 4u) \
    form_(PREDICATE_XOR, "predicate_xor", 3u) \
    form_(PREDICATE_AND, "predicate_and", 3u) \
    form_(WIDE_FROM_WORD, "wide_from_word", 2u) \
    form_(WORD_FROM_WIDE, "word_from_wide", 2u) \
    form_(WIDE_PACK, "wide_pack", 3u) \
    form_(WIDE_UNPACK, "wide_unpack", 3u) \
    form_(WIDE_MULTIPLY, "wide_multiply", 3u) \
    form_(WIDE_MULTIPLY_WORD, "wide_multiply_word", 3u) \
    form_(WIDE_ADD, "wide_add", 3u) \
    form_(WIDE_ADD_UNSIGNED, "wide_add_unsigned", 3u) \
    form_(WIDE_SHIFT_LEFT, "wide_shift_left", 3u) \
    form_(WIDE_SELECT, "wide_select", 4u) \
    form_(WIDE_DIVIDE, "wide_divide", 3u) \
    form_(GLOBAL_LOAD, "global_load", 3u) \
    form_(RECORD_STORE, "record_store", 2u) \
    form_(SHARED_STORE, "shared_store", 2u) \
    form_(SHARED_STORE_BYTE, "shared_store_byte", 2u) \
    form_(SHARED_LOAD, "shared_load", 2u) \
    form_(SHARED_LOAD_SIGNED_BYTE, "shared_load_signed_byte", 2u) \
    form_(CALL_OPEN, "call_open", 0u) \
    form_(CALL_ARGUMENT, "call_argument", 2u) \
    form_(CALL_ANSWER_DECLARE, "call_answer_declare", 0u) \
    form_(CALL_ANSWERED, "call_answered", 1u) \
    form_(CALL, "call", 1u) \
    form_(CALL_PARAMETER_FIRST, "call_parameter_first", 1u) \
    form_(CALL_PARAMETER_NEXT, "call_parameter_next", 1u) \
    form_(CALL_PARAMETERS_CLOSE, "call_parameters_close", 0u) \
    form_(ANSWER_LOAD, "answer_load", 1u) \
    form_(CALL_CLOSE, "call_close", 0u)

// every bank of registers the emitter takes from, each spelled with one parameter, the register's number n
#define CYCLE_BANKS(bank_) \
    bank_(FILE, "file") \
    bank_(SIGN, "sign") \
    bank_(OUT, "out") \
    bank_(ATOM, "atom") \
    bank_(TEMPORARY, "temporary") \
    bank_(WIDE, "wide") \
    bank_(PREDICATE, "predicate") \
    bank_(MEMBER, "member")

// every register the lane holds throughout that the emitter passes to a form by name
#define CYCLE_FIXED(fixed_) \
    fixed_(ZERO, "zero") \
    fixed_(LANE_NUMBER, "lane_number") \
    fixed_(RECORD, "record") \
    fixed_(INDEX, "index") \
    fixed_(BODY, "body") \
    fixed_(BODIES, "bodies") \
    fixed_(TABLES, "tables") \
    fixed_(THREADS, "threads") \
    fixed_(WORD_BASE, "word_base") \
    fixed_(WORD_STRIDE, "word_stride") \
    fixed_(SIGN_BASE, "sign_base") \
    fixed_(INDEXED, "indexed") \
    fixed_(ONE, "one") \
    fixed_(GOOD, "good")

// every form the C source's emitter writes, the same way: a step is one call into the operator block and its put, and
// the C source takes no bank and names no register
#define CYCLE_SOURCE_FORMS(form_) \
    form_(PROGRAM_NOTE, "program_note", 6u) \
    form_(LANE_OPEN, "lane_open", 0u) \
    form_(MEMBER_OPEN, "member_open", 3u) \
    form_(RECORD_OPEN, "record_open", 1u) \
    form_(FIELD, "field", 6u) \
    form_(FIELD_SIGNED, "field_signed", 6u) \
    form_(CONSTANT, "constant", 4u) \
    form_(LANE_NUMBER, "lane_number", 2u) \
    form_(PRODUCT, "product", 6u) \
    form_(COMPARE, "compare", 6u) \
    form_(SUM, "sum", 6u) \
    form_(DIFFERENCE, "difference", 6u) \
    form_(XOR, "xor", 6u) \
    form_(AND, "and", 6u) \
    form_(ABSOLUTE, "absolute", 4u) \
    form_(TABLE, "table", 5u) \
    form_(WRAP, "wrap", 5u) \
    form_(GCD, "gcd", 8u) \
    form_(LADDER, "ladder", 7u) \
    form_(QUOTIENT, "quotient", 8u) \
    form_(REMAINDER, "remainder", 8u) \
    form_(EXACT_QUOTIENT, "exact_quotient", 8u) \
    form_(PUT, "put", 5u) \
    form_(LANE_CLOSE, "lane_close", 0u)

#define CYCLE_FORM_NAMED(name_, spelling_, parameters_) CYCLE_FORM_##name_,
#define CYCLE_SOURCE_FORM_NAMED(name_, spelling_, parameters_) CYCLE_SOURCE_FORM_##name_,
#define CYCLE_BANK_NAMED(name_, spelling_) CYCLE_BANK_##name_,
#define CYCLE_FIXED_NAMED(name_, spelling_) CYCLE_FIXED_##name_,

enum CycleFormName
{
    CYCLE_FORMS(CYCLE_FORM_NAMED) CYCLE_FORM_COUNT
};

enum CycleSourceFormName
{
    CYCLE_SOURCE_FORMS(CYCLE_SOURCE_FORM_NAMED) CYCLE_SOURCE_FORM_COUNT
};

enum CycleBankName
{
    CYCLE_BANKS(CYCLE_BANK_NAMED) CYCLE_BANK_COUNT
};

enum CycleFixedName
{
    CYCLE_FIXED(CYCLE_FIXED_NAMED) CYCLE_FIXED_COUNT
};

// a form, a bank or a held register as a .krs file spells it, and the parameters it takes
struct CycleRuleName
{
    const char *spelling;
    unsigned int parameters;
};

#define CYCLE_FORM_SPELLED(name_, spelling_, parameters_) {spelling_, parameters_},
#define CYCLE_BANK_SPELLED(name_, spelling_) {spelling_, 1u},
#define CYCLE_FIXED_SPELLED(name_, spelling_) {spelling_, 0u},

static const CycleRuleName s_cycle_form_names[CYCLE_FORM_COUNT] = {CYCLE_FORMS(CYCLE_FORM_SPELLED)};

static const CycleRuleName s_cycle_source_form_names[CYCLE_SOURCE_FORM_COUNT] = {
    CYCLE_SOURCE_FORMS(CYCLE_FORM_SPELLED)};

static const CycleRuleName s_cycle_bank_names[CYCLE_BANK_COUNT] = {CYCLE_BANKS(CYCLE_BANK_SPELLED)};

static const CycleRuleName s_cycle_fixed_names[CYCLE_FIXED_COUNT] = {CYCLE_FIXED(CYCLE_FIXED_SPELLED)};

// what an emitter asks of its ruleset: the file it is read from, the toolchain and the header the emitter's path
// builds with, and the forms, banks and held registers the emitter names
struct CycleRuleSchema
{
    const char *file;
    const char *toolchain;
    const char *header;
    const CycleRuleName *forms;
    unsigned int form_count;
    const CycleRuleName *banks;
    unsigned int bank_count;
    const CycleRuleName *fixed;
    unsigned int fixed_count;
};

// the lane as PTX: nvJitLink assembles it against the operator block, and its header is asked of NVRTC
static const CycleRuleSchema s_cycle_ptx_schema = {"ptx.krs",          "nvjitlink",        "probe_nvrtc",
                                                   s_cycle_form_names, CYCLE_FORM_COUNT,   s_cycle_bank_names,
                                                   CYCLE_BANK_COUNT,   s_cycle_fixed_names, CYCLE_FIXED_COUNT};

// the lane as C source: NVRTC compiles it, and its header is the operator block's prelude
static const CycleRuleSchema s_cycle_source_schema = {
    "c.krs", "nvrtc", "prelude", s_cycle_source_form_names, CYCLE_SOURCE_FORM_COUNT, NULL, 0u, NULL, 0u};

// a text cut at its parameters: pieces[k] comes before the argument of parameter slots[k], and the last piece after the
// last argument, one piece more than slots
struct CycleForm
{
    std::vector<std::string> pieces;
    std::vector<unsigned int> slots;
};

// what one argument of a construct's line is: text written as it stands, the construct's own parameter at a slot, or
// a scratch register of a bank, `number` naming it within one writing of the construct
enum CycleConstructArgumentKind
{
    CYCLE_CONSTRUCT_TEXT = 0,
    CYCLE_CONSTRUCT_PARAMETER = 1,
    CYCLE_CONSTRUCT_SCRATCH = 2
};

struct CycleConstructArgument
{
    CycleConstructArgumentKind kind;
    unsigned int slot;
    unsigned int number;
    std::string text;
};

// one line of a construct: a form, or a construct given before it in the file, and its arguments
struct CycleConstructLine
{
    unsigned int form;
    std::vector<CycleConstructArgument> arguments;
};

// a form built from more basic ones (engine_table.md item 11(f) 5): where the target's own instruction for a form
// leaves its rules, the ruleset gives the form as a construct of the same name and parameters, and each writing of
// the form writes the construct's lines. No lines is the form as its text gives it
struct CycleConstruct
{
    std::vector<CycleConstructLine> lines;
};

// a scratch register a construct takes: a fresh register of the bank at that place in the schema, or empty where the
// writer has none of that bank to give
typedef std::function<std::string(unsigned int bank)> CycleScratch;

// a ruleset read from its file against its emitter's schema: where it was read, and why it was refused where it was;
// its own name, the toolchain that builds its text and where its header comes from; each bank's spelling of a
// register, each held register's spelling, and each form, by their places in the schema; and which of them the file
// gave, so that none is given twice or left out
struct CycleRuleset
{
    const CycleRuleSchema *schema;
    int tried;
    int ready;
    std::string path;
    std::string refused;
    std::string name;
    std::string toolchain;
    std::string header;
    std::vector<CycleForm> banks;
    std::vector<std::string> fixed;
    std::vector<CycleForm> forms;
    std::vector<CycleConstruct> constructs;
    std::vector<unsigned char> bank_given;
    std::vector<unsigned char> fixed_given;
    std::vector<unsigned char> form_given;
    // the construct being read, its place among the forms (the form count where none is), and its parameters' names
    unsigned int building;
    std::vector<std::string> building_parameters;
};

static CycleRuleset s_cycle_ptx_ruleset;

static CycleRuleset s_cycle_source_ruleset;

// the folder rulesets are read from: $CYCLE_RULESETS, else rulesets in this file's folder in the tree it was built from
static std::string cycle_ruleset_folder(void)
{
    const char *const named = getenv("CYCLE_RULESETS");
    if ((named != NULL) && (named[0] != '\0'))
    {
        return std::string(named);
    }
    const std::string file = __FILE__;
    const size_t cut = file.find_last_of("/\\");
    return (cut == std::string::npos) ? std::string("rulesets") : (file.substr(0u, cut + 1u) + "rulesets");
}

// a text as a .krs file writes it, cut at its parameters: \t, \n and \\ are a tab, a line's end and a backslash, and
// {p} is parameter p's argument where p is one of `parameters`, a brace that opens no parameter's name being itself. 0
// where a backslash begins no escape the format knows
static int cycle_ruleset_cut(const std::string &text, const std::vector<std::string> &parameters, CycleForm *form)
{
    form->pieces.assign(1u, std::string());
    form->slots.clear();
    size_t at = 0u;
    while (at < text.size())
    {
        const char held = text[at];
        const char next = ((at + 1u) < text.size()) ? text[at + 1u] : '\0';
        const size_t close = (held == '{') ? text.find('}', at + 1u) : std::string::npos;
        size_t slot = parameters.size();
        for (size_t parameter = 0u; (close != std::string::npos) && (parameter < parameters.size()); parameter += 1u)
        {
            slot = (text.compare(at + 1u, close - (at + 1u), parameters[parameter]) == 0) ? parameter : slot;
        }
        if ((held == '\\') && (next != 't') && (next != 'n') && (next != '\\'))
        {
            return 0;
        }
        if (held == '\\')
        {
            form->pieces.back() += (next == 't') ? '\t' : ((next == 'n') ? '\n' : '\\');
            at += 2u;
        }
        else if (slot < parameters.size())
        {
            // a parameter's place among a form's few, held whole in 32 bits
            form->slots.push_back((unsigned int)slot);
            form->pieces.push_back(std::string());
            at = close + 1u;
        }
        else
        {
            form->pieces.back() += held;
            at += 1u;
        }
    }
    return 1;
}

// the words of a line's head, split at its spaces
static std::vector<std::string> cycle_ruleset_words(const std::string &head)
{
    std::vector<std::string> words;
    size_t at = 0u;
    while (at < head.size())
    {
        const size_t space = head.find(' ', at);
        const size_t end = (space == std::string::npos) ? head.size() : space;
        if (end > at)
        {
            words.push_back(head.substr(at, end - at));
        }
        at = end + 1u;
    }
    return words;
}

// the place of `word` among `count` names, or `count` where it is none of them
static unsigned int cycle_ruleset_find(const CycleRuleName *names, unsigned int count, const std::string &word)
{
    unsigned int found = count;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = (word == names[at].spelling) ? at : found;
    }
    return found;
}

// one entry of a ruleset, `kind` the first word of its line and `rest` the rest of the line, read against the
// ruleset's schema; empty where the entry holds, else why it does not
static std::string cycle_ruleset_entry(CycleRuleset *rules, const std::string &kind, const std::string &rest)
{
    const CycleRuleSchema *const schema = rules->schema;
    // a named entry's head is its name and parameters, and its text follows the head's "= "
    const size_t equals = rest.find('=');
    const std::vector<std::string> head = cycle_ruleset_words(rest.substr(0u, equals));
    const size_t text_at = (equals == std::string::npos) ? rest.size()
                         : ((((equals + 1u) < rest.size()) && (rest[equals + 1u] == ' ')) ? (equals + 2u)
                                                                                          : (equals + 1u));
    const std::string text = rest.substr(text_at);
    const std::string name = head.empty() ? std::string() : head[0];
    const std::vector<std::string> parameters(head.empty() ? head.end() : (head.begin() + 1), head.end());
    CycleForm form;
    if ((kind == "ruleset") || (kind == "toolchain") || (kind == "header"))
    {
        std::string *const value = (kind == "ruleset") ? &rules->name
                                 : ((kind == "toolchain") ? &rules->toolchain : &rules->header);
        if ((equals != std::string::npos) || (head.size() != 1u) || !value->empty())
        {
            return kind + " is not one word given once";
        }
        *value = name;
        return std::string();
    }
    if (kind == "bank")
    {
        const unsigned int bank = cycle_ruleset_find(schema->banks, schema->bank_count, name);
        if ((equals == std::string::npos) || (bank == schema->bank_count) || !parameters.empty()
            || (rules->bank_given[bank] != 0u)
            || !cycle_ruleset_cut(text, std::vector<std::string>(1u, std::string("n")), &form))
        {
            return "the bank " + name + " is not one the emitter takes from, or is given twice or written wrong";
        }
        rules->banks[bank] = form;
        rules->bank_given[bank] = 1u;
        return std::string();
    }
    if (kind == "fixed")
    {
        const unsigned int fixed = cycle_ruleset_find(schema->fixed, schema->fixed_count, name);
        if ((equals == std::string::npos) || (fixed == schema->fixed_count) || !parameters.empty()
            || (rules->fixed_given[fixed] != 0u) || !cycle_ruleset_cut(text, std::vector<std::string>(), &form))
        {
            return "the register " + name + " is not one the emitter names, or is given twice or written wrong";
        }
        rules->fixed[fixed] = form.pieces[0];
        rules->fixed_given[fixed] = 1u;
        return std::string();
    }
    if (kind == "form")
    {
        const unsigned int named = cycle_ruleset_find(schema->forms, schema->form_count, name);
        if ((equals == std::string::npos) || (named == schema->form_count)
            || (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u)
            || !cycle_ruleset_cut(text, parameters, &form))
        {
            return "the form " + name + " is not one the emitter writes, takes other parameters, or is given twice or "
                   "written wrong";
        }
        rules->forms[named] = form;
        rules->form_given[named] = 1u;
        return std::string();
    }
    if (kind == "construct")
    {
        // a construct's head is its name and parameters as a form's is, with no text: its lines follow, to `end`
        const unsigned int named = cycle_ruleset_find(schema->forms, schema->form_count, name);
        if ((equals != std::string::npos) || (named == schema->form_count)
            || (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u))
        {
            return "the construct " + name + " is not a form the emitter writes, takes other parameters, or is given "
                   "twice";
        }
        rules->building = named;
        rules->building_parameters = parameters;
        rules->constructs[named].lines.clear();
        return std::string();
    }
    return "no entry is of the kind " + kind;
}

// one line of the construct being read: `end` closes it, and any other line is a form, or a construct given before
// it in the file, and its arguments, split at spaces. An argument that is one of the construct's parameters stands for
// that parameter's argument, {bank:n} for scratch register n of that bank, taken fresh each time the construct is
// written, and any other word for itself. Empty where the line holds, else why it does not
static std::string cycle_ruleset_construct_line(CycleRuleset *rules, const std::string &line)
{
    const CycleRuleSchema *const schema = rules->schema;
    CycleConstruct *const construct = &rules->constructs[rules->building];
    const std::string building = schema->forms[rules->building].spelling;
    if (line == "end")
    {
        if (construct->lines.empty())
        {
            return "the construct " + building + " has no lines";
        }
        rules->form_given[rules->building] = 1u;
        rules->building = schema->form_count;
        return std::string();
    }
    const std::vector<std::string> words = cycle_ruleset_words(line);
    const unsigned int named = words.empty() ? schema->form_count
                                             : cycle_ruleset_find(schema->forms, schema->form_count, words[0]);
    // a form or construct the file has given already: one given later, or the construct itself, would make a loop
    if ((named == schema->form_count) || (rules->form_given[named] == 0u)
        || ((words.size() - 1u) != schema->forms[named].parameters))
    {
        return "the construct " + building + " writes " + (words.empty() ? std::string() : words[0])
             + ", which the file has not given before it or which takes other arguments";
    }
    CycleConstructLine written;
    written.form = named;
    for (size_t at = 1u; at < words.size(); at += 1u)
    {
        const std::string &word = words[at];
        CycleConstructArgument argument = {CYCLE_CONSTRUCT_TEXT, 0u, 0u, word};
        for (size_t parameter = 0u; parameter < rules->building_parameters.size(); parameter += 1u)
        {
            if (word == rules->building_parameters[parameter])
            {
                argument.kind = CYCLE_CONSTRUCT_PARAMETER;
                // a parameter's place among a form's few, held whole in 32 bits
                argument.slot = (unsigned int)parameter;
            }
        }
        const size_t colon = word.find(':');
        const int braced = (word.size() > 4u) && (word[0] == '{') && (word[word.size() - 1u] == '}')
                        && (colon != std::string::npos);
        if (braced)
        {
            const unsigned int bank = cycle_ruleset_find(schema->banks, schema->bank_count, word.substr(1u, colon - 1u));
            const std::string digits = word.substr(colon + 1u, word.size() - colon - 2u);
            const int counted = !digits.empty() && (digits.size() < 6u)
                             && (digits.find_first_not_of("0123456789") == std::string::npos);
            if ((bank == schema->bank_count) || !counted)
            {
                return "the construct " + building + " takes a scratch register " + word
                     + " of no bank the ruleset gives, or with no number";
            }
            argument.kind = CYCLE_CONSTRUCT_SCRATCH;
            argument.slot = bank;
            // five digits at most, held whole in 32 bits
            argument.number = (unsigned int)strtoul(digits.c_str(), NULL, 10);
        }
        written.arguments.push_back(argument);
    }
    construct->lines.push_back(written);
    return std::string();
}

// the ruleset at `path` read whole into `rules` against its schema: 1 where its first line is krs 1, every entry holds,
// and every bank, held register and form the emitter names is given with the ruleset's name, toolchain and header,
// else 0 with the reason in rules->refused. A line that begins with # is a comment, and a blank line is nothing
static int cycle_ruleset_read(CycleRuleset *rules, const std::string &path)
{
    const CycleRuleSchema *const schema = rules->schema;
    rules->path = path;
    rules->banks.assign(schema->bank_count, CycleForm());
    rules->fixed.assign(schema->fixed_count, std::string());
    rules->forms.assign(schema->form_count, CycleForm());
    rules->constructs.assign(schema->form_count, CycleConstruct());
    rules->building = schema->form_count;
    rules->bank_given.assign(schema->bank_count, 0u);
    rules->fixed_given.assign(schema->fixed_count, 0u);
    rules->form_given.assign(schema->form_count, 0u);
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        rules->refused = "it could not be opened";
        return 0;
    }
    std::string whole;
    char block[4096];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        whole.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    unsigned int number = 0u;
    size_t at = 0u;
    while ((at < whole.size()) && rules->refused.empty())
    {
        const size_t found = whole.find('\n', at);
        const size_t end = (found == std::string::npos) ? whole.size() : found;
        // a checkout that ends its lines with a carriage return as well leaves each line as it was written
        const size_t kept = ((end > at) && (whole[end - 1u] == '\r')) ? (end - 1u) : end;
        const std::string line = whole.substr(at, kept - at);
        number += 1u;
        at = end + 1u;
        const size_t space = line.find(' ');
        const int constructing = rules->building != schema->form_count;
        const std::string why = (number == 1u) ? ((line == "krs 1") ? std::string() : std::string("it is not krs 1"))
                              : ((line.empty() || (line[0] == '#'))
                                     ? std::string()
                                     : (constructing ? cycle_ruleset_construct_line(rules, line)
                                                     : cycle_ruleset_entry(rules, line.substr(0u, space),
                                                                           (space == std::string::npos)
                                                                               ? std::string()
                                                                               : line.substr(space + 1u))));
        if (!why.empty())
        {
            char where[32];
            snprintf(where, sizeof(where), "line %u: ", number);
            rules->refused = where + why;
        }
    }
    if (rules->refused.empty() && (rules->building != schema->form_count))
    {
        rules->refused = "the construct " + std::string(schema->forms[rules->building].spelling) + " has no end";
    }
    for (unsigned int bank = 0u; rules->refused.empty() && (bank < schema->bank_count); bank += 1u)
    {
        if (rules->bank_given[bank] == 0u)
        {
            rules->refused = "the bank " + std::string(schema->banks[bank].spelling) + " is not given";
        }
    }
    for (unsigned int fixed = 0u; rules->refused.empty() && (fixed < schema->fixed_count); fixed += 1u)
    {
        if (rules->fixed_given[fixed] == 0u)
        {
            rules->refused = "the register " + std::string(schema->fixed[fixed].spelling) + " is not given";
        }
    }
    for (unsigned int named = 0u; rules->refused.empty() && (named < schema->form_count); named += 1u)
    {
        if (rules->form_given[named] == 0u)
        {
            rules->refused = "the form " + std::string(schema->forms[named].spelling) + " is not given";
        }
    }
    if (rules->refused.empty() && (rules->name.empty() || rules->toolchain.empty() || rules->header.empty()))
    {
        rules->refused = "its ruleset, toolchain or header is not named";
    }
    return rules->refused.empty() ? 1 : 0;
}

// a ruleset read once a process into `rules` from its schema's file; NULL where it is refused. A ruleset naming
// another toolchain or header than its emitter's path builds with is refused with the rest
static const CycleRuleset *cycle_ruleset_load(CycleRuleset *rules, const CycleRuleSchema *schema, int report)
{
    if (rules->tried != 0)
    {
        return (rules->ready != 0) ? rules : NULL;
    }
    rules->tried = 1;
    rules->schema = schema;
    rules->ready = cycle_ruleset_read(rules, cycle_ruleset_folder() + "/" + schema->file);
    if ((rules->ready != 0) && ((rules->toolchain != schema->toolchain) || (rules->header != schema->header)))
    {
        rules->ready = 0;
        rules->refused = "its path builds with " + std::string(schema->toolchain) + " and takes its header from "
                       + schema->header;
    }
    if ((report != 0) && (rules->ready != 0))
    {
        fprintf(stderr, "  cycle: the ruleset %s read from %s\n", rules->name.c_str(), rules->path.c_str());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: the ruleset at %s is refused (%s)\n", rules->path.c_str(), rules->refused.c_str());
    }
    return (rules->ready != 0) ? rules : NULL;
}

// the PTX ruleset, ptx.krs; NULL where it is refused, which leaves programs to the C source
const CycleRuleset *cycle_ruleset_ptx(int report)
{
    return cycle_ruleset_load(&s_cycle_ptx_ruleset, &s_cycle_ptx_schema, report);
}

// the C source's ruleset, c.krs; NULL where it is refused, which leaves a program the PTX does not hold on the
// interpreter
const CycleRuleset *cycle_ruleset_source(int report)
{
    return cycle_ruleset_load(&s_cycle_source_ruleset, &s_cycle_source_schema, report);
}

// form `name` of `rules` appended to `text`, `argument` holding as many arguments as it takes, in the order of its
// parameters: its text cut at them, or where the ruleset gives it as a construct, each of the construct's lines
// written the same way, a scratch register taken of `scratch` the first time a writing names it. `broken` set where a
// scratch register cannot be taken
static void cycle_ruleset_spell(const CycleRuleset *rules, std::string &text, unsigned int name,
                                const std::string *argument, const CycleScratch &scratch, int *broken)
{
    const CycleConstruct *const construct = &rules->constructs[name];
    if (construct->lines.empty())
    {
        const CycleForm *const form = &rules->forms[name];
        text += form->pieces[0];
        for (size_t at = 0u; at < form->slots.size(); at += 1u)
        {
            text += argument[form->slots[at]];
            text += form->pieces[at + 1u];
        }
        return;
    }
    // the scratch registers this writing has taken, each by its bank and number
    std::vector<unsigned int> scratch_bank;
    std::vector<unsigned int> scratch_number;
    std::vector<std::string> scratch_taken;
    for (const CycleConstructLine &line : construct->lines)
    {
        std::vector<std::string> arguments;
        for (const CycleConstructArgument &given : line.arguments)
        {
            size_t found = scratch_taken.size();
            for (size_t at = 0u; (given.kind == CYCLE_CONSTRUCT_SCRATCH) && (at < scratch_taken.size()); at += 1u)
            {
                found = ((scratch_bank[at] == given.slot) && (scratch_number[at] == given.number)) ? at : found;
            }
            if ((given.kind == CYCLE_CONSTRUCT_SCRATCH) && (found == scratch_taken.size()))
            {
                const std::string taken = scratch(given.slot);
                *broken = *broken || taken.empty();
                scratch_bank.push_back(given.slot);
                scratch_number.push_back(given.number);
                scratch_taken.push_back(taken);
            }
            arguments.push_back((given.kind == CYCLE_CONSTRUCT_TEXT)        ? given.text
                                : (given.kind == CYCLE_CONSTRUCT_PARAMETER) ? argument[given.slot]
                                                                            : scratch_taken[found]);
        }
        cycle_ruleset_spell(rules, text, line.form, arguments.data(), scratch, broken);
    }
}

// the scratch a writer with no registers of its own to give answers: none
static std::string cycle_ruleset_no_scratch(unsigned int bank)
{
    (void)bank;
    return std::string();
}

// form `name` of `rules` appended to `text`, its arguments in the order of its parameters, a construct's scratch taken
// of `scratch`; `broken` set, and nothing written, where they are not as many as the form takes
static void cycle_ruleset_write_taking(const CycleRuleset *rules, std::string &text, unsigned int name,
                                       std::initializer_list<std::string> arguments, const CycleScratch &scratch,
                                       int *broken)
{
    if (arguments.size() != rules->schema->forms[name].parameters)
    {
        *broken = 1;
        return;
    }
    cycle_ruleset_spell(rules, text, name, arguments.begin(), scratch, broken);
}

// the same, by a writer with no scratch to give: a construct that takes scratch breaks what it is written into
static void cycle_ruleset_write(const CycleRuleset *rules, std::string &text, unsigned int name,
                                std::initializer_list<std::string> arguments, int *broken)
{
    cycle_ruleset_write_taking(rules, text, name, arguments, CycleScratch(cycle_ruleset_no_scratch), broken);
}

// a form written by the name its .krs file gives it, for a reader outside the emitter (emit.h), a construct's scratch
// taken of `scratch` by its bank's name
int cycle_ruleset_form(const CycleRuleset *rules, const std::string &name, const std::vector<std::string> &arguments,
                       const std::function<std::string(const std::string &bank)> &scratch, std::string &text)
{
    const CycleRuleSchema *const schema = rules->schema;
    const unsigned int named = cycle_ruleset_find(schema->forms, schema->form_count, name);
    if ((named == schema->form_count) || (arguments.size() != schema->forms[named].parameters))
    {
        return 0;
    }
    int broken = 0;
    const CycleScratch by_place = [&](unsigned int bank) {
        return scratch(std::string(schema->banks[bank].spelling));
    };
    cycle_ruleset_spell(rules, text, named, arguments.data(), by_place, &broken);
    return (broken == 0) ? 1 : 0;
}

std::string cycle_ruleset_register(const CycleRuleset *rules, const std::string &bank, unsigned int number)
{
    const CycleRuleSchema *const schema = rules->schema;
    const unsigned int named = cycle_ruleset_find(schema->banks, schema->bank_count, bank);
    if (named == schema->bank_count)
    {
        return std::string();
    }
    // a bank's spelling takes one parameter, the register's number, in every slot it is cut at
    const CycleForm *const form = &rules->banks[named];
    std::string spelled = form->pieces[0];
    for (size_t at = 0u; at < form->slots.size(); at += 1u)
    {
        spelled += std::to_string(number);
        spelled += form->pieces[at + 1u];
    }
    return spelled;
}

std::string cycle_ruleset_fixed(const CycleRuleset *rules, const std::string &name)
{
    const CycleRuleSchema *const schema = rules->schema;
    const unsigned int named = cycle_ruleset_find(schema->fixed, schema->fixed_count, name);
    return (named == schema->fixed_count) ? std::string() : rules->fixed[named];
}

// The record program as C source, in the ruleset c.krs: each step one call into the operator block, whose registers
// are its places in shared memory, and NVRTC compiles the lane. The emitter decides which call a step makes and with
// what; the ruleset spells the call

// one step's source, one call into the operator block and its put; 0 for a step this compiler does not hold, which
// leaves the whole program on the interpreter. `wide` is the width the program's scratch is laid at, and the scratch's
// places follow the file's
static int cycle_program_step(const EngineRecordLayout *layout, const CycleRuleset *rules, unsigned int at,
                              unsigned int wide, std::string &text, int *broken)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    if (!cycle_program_held(layout, at))
    {
        return 0;
    }
    // every register is its step's place in the file, and its sign the sign at that place. key_schedule frees an
    // operand's place only once the step after its last reader begins, so no step's value lies over its own operands
    const std::string place = std::to_string(step->place);
    const std::string limbs = std::to_string(step->limbs);
    const std::string left =
        std::to_string(cycle_program_reads_left(operation) ? layout->step_table[step->left].place : 0u);
    const std::string left_limbs = std::to_string(step->left_limbs);
    const std::string right =
        std::to_string(cycle_program_reads_right(operation) ? layout->step_table[step->right].place : 0u);
    const std::string right_limbs = std::to_string(step->right_limbs);
    const std::string scratch = std::to_string(layout->file_limbs);
    const std::string widest = std::to_string(wide);
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        cycle_ruleset_write(rules, text,
                            (operation == ENGINE_RECORD_FIELD_SIGNED) ? CYCLE_SOURCE_FORM_FIELD_SIGNED
                                                                      : CYCLE_SOURCE_FORM_FIELD,
                            {std::to_string(step->member), std::to_string(layout->in_limbs[step->member]),
                             std::to_string(step->left), std::to_string(step->right), place, limbs},
                            broken);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_CONSTANT,
                            {std::to_string(step->left), std::to_string(step->right), place, limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_NUMBER, {place, limbs}, broken);
    }
    else if ((operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_COMPARE)
             || (operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE)
             || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        const CycleSourceFormName form = (operation == ENGINE_RECORD_PRODUCT)    ? CYCLE_SOURCE_FORM_PRODUCT
                                       : (operation == ENGINE_RECORD_COMPARE)    ? CYCLE_SOURCE_FORM_COMPARE
                                       : (operation == ENGINE_RECORD_SUM)        ? CYCLE_SOURCE_FORM_SUM
                                       : (operation == ENGINE_RECORD_DIFFERENCE) ? CYCLE_SOURCE_FORM_DIFFERENCE
                                       : (operation == ENGINE_RECORD_XOR)        ? CYCLE_SOURCE_FORM_XOR
                                                                                 : CYCLE_SOURCE_FORM_AND;
        cycle_ruleset_write(rules, text, form, {place, limbs, left, left_limbs, right, right_limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_ABSOLUTE, {place, limbs, left, left_limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_TABLE,
                            {place, limbs, left, std::to_string(step->table_offset), std::to_string(step->index_bits)},
                            broken);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_WRAP,
                            {place, limbs, left, left_limbs, std::to_string(step->wrap_bits)}, broken);
    }
    else if (operation == ENGINE_RECORD_GCD)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_GCD,
                            {place, limbs, left, left_limbs, right, right_limbs, scratch, widest}, broken);
    }
    else if (operation == ENGINE_RECORD_LADDER)
    {
        // a right that is not positive refuses the lane
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LADDER,
                            {place, limbs, left, left_limbs, right, right_limbs, scratch}, broken);
    }
    else if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
             || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
    {
        // a zero divisor, or an exact quotient that leaves a remainder, refuses the lane
        const CycleSourceFormName form = (operation == ENGINE_RECORD_QUOTIENT)    ? CYCLE_SOURCE_FORM_QUOTIENT
                                       : (operation == ENGINE_RECORD_REMAINDER) ? CYCLE_SOURCE_FORM_REMAINDER
                                                                                : CYCLE_SOURCE_FORM_EXACT_QUOTIENT;
        cycle_ruleset_write(rules, text, form, {place, limbs, left, left_limbs, right, right_limbs, scratch, widest},
                            broken);
    }
    else
    {
        // an operation this compiler does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_PUT,
                            {std::to_string(layout->out_limbs), std::to_string(step->out_offset),
                             std::to_string(step->out_bits), place, limbs},
                            broken);
    }
    return 1;
}

// a program's source: its lane, its atoms and its record cleared, then each step one call into the operator block.
// It names the device, NVRTC and the operator block it is linked against, from `target`; empty where a step is one this
// compiler does not hold, or a form was written with other arguments than it takes. The registers are the operator
// block's places in shared memory, so the lane holds none of its own
std::string cycle_program_source(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                                 const CycleRuleset *rules)
{
    std::string text;
    int broken = 0;
    char block[32];
    snprintf(block, sizeof(block), "%016llx", target->block_hash);
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_PROGRAM_NOTE,
                        {std::to_string(layout->steps), std::to_string(target->major), std::to_string(target->minor),
                         std::to_string(target->nvrtc_major), std::to_string(target->nvrtc_minor), std::string(block)},
                        &broken);
    text += target->prelude;
    const unsigned int wide = cycle_program_wide(layout);
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_OPEN, {}, &broken);
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_MEMBER_OPEN,
                            {std::to_string(member), std::to_string(layout->members),
                             std::to_string(layout->in_limbs[member])},
                            &broken);
    }
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_RECORD_OPEN, {std::to_string(layout->out_limbs)}, &broken);
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (!cycle_program_step(layout, rules, at, wide, text, &broken))
        {
            return std::string();
        }
    }
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_CLOSE, {}, &broken);
    return (broken != 0) ? std::string() : text;
}

// The record program as PTX. The lane is written in NVIDIA's own assembly, with no compiler between the steps and
// ptxas: each step unrolled at its widths into straight-line PTX over registers the lane holds itself. The file is %v
// by place and its signs %g by place, as key_schedule laid them; the record's words are %o, laid by each put and each
// stored once the last put that lays it has run; the atoms' words are %a, each loaded at its first reader. What a compiler would loop over a
// register's limbs is written out here limb by limb from the program's own widths, so ptxas is handed the unrolled
// block and has nothing to unroll. The emitter writes no PTX of its own: every line is a form of the ruleset read
// from emit/rulesets/ptx.krs, and every register a spelling of its banks and fixed registers, so the emitter decides
// what a step does and the ruleset how the target spells it. What stays here is the order the forms are laid in: the
// carry chains a register's limbs are laid through (s_cycle_ptx_add and the two after it) and the operator block's
// functions a lane calls by the calling convention (s_cycle_ptx_callees). The steps that loop on their values call
// into the block: the gcd, the golden ladder, a division by more than one limb, and a product too wide to unroll.
// Their operands go to their places in shared memory, where the block reads them, and the result comes back; a
// program that calls nothing takes no shared memory. Every step is the interpreter's arithmetic limb for limb,
// branch-free where the interpreter branches on a sign or a borrow, and CYCLE_RECORD_CHECK=1 holds the two to each
// other.

// the most limb products a lane unrolls a product into; a wider product calls the operator block
#define CYCLE_PTX_PRODUCT_MOST 1024u

// a carry chain through a register's limbs: the form a register of one limb takes, then the first, the middle and the
// last of a longer one, each setting or reading the carry as the ruleset spells it
struct CyclePtxChain
{
    CycleFormName alone;
    CycleFormName first;
    CycleFormName middle;
    CycleFormName last;
};

static const CyclePtxChain s_cycle_ptx_add = {CYCLE_FORM_ADD_ALONE, CYCLE_FORM_ADD_FIRST, CYCLE_FORM_ADD_MIDDLE,
                                              CYCLE_FORM_ADD_LAST};

static const CyclePtxChain s_cycle_ptx_subtract = {CYCLE_FORM_SUBTRACT_ALONE, CYCLE_FORM_SUBTRACT_FIRST,
                                                   CYCLE_FORM_SUBTRACT_MIDDLE, CYCLE_FORM_SUBTRACT_LAST};

// the subtract chain whose top limb leaves its borrow for cycle_ptx_borrowed to read
static const CyclePtxChain s_cycle_ptx_borrow = {CYCLE_FORM_BORROW_ALONE, CYCLE_FORM_BORROW_FIRST,
                                                 CYCLE_FORM_BORROW_MIDDLE, CYCLE_FORM_BORROW_LAST};

// one of the operator block's functions a lane calls: the operation it does, its name, its arguments, each 32 bits,
// and 1 where it answers whether the lane holds
struct CyclePtxCallee
{
    unsigned int operation;
    const char *name;
    unsigned int arguments;
    unsigned int answers;
};

// the arguments are the step's place and limbs, its operands' places and limbs, then the scratch's first place and the
// width it is laid at, as the prelude (cycle.cu, s_cycle_prelude) declares them
static const CyclePtxCallee s_cycle_ptx_callees[] = {
    {ENGINE_RECORD_PRODUCT, "cycle_product", 6u, 0u},
    {ENGINE_RECORD_LADDER, "cycle_ladder", 7u, 1u},
    {ENGINE_RECORD_QUOTIENT, "cycle_quotient", 8u, 1u},
    {ENGINE_RECORD_REMAINDER, "cycle_remainder", 8u, 1u},
    {ENGINE_RECORD_GCD, "cycle_gcd", 8u, 0u},
    {ENGINE_RECORD_EXACT_QUOTIENT, "cycle_exact_quotient", 8u, 1u},
};

// a handful of functions, counted whole in 32 bits
#define CYCLE_PTX_CALLEES ((unsigned int)(sizeof(s_cycle_ptx_callees) / sizeof(s_cycle_ptx_callees[0])))

// the most arguments a callee takes, the eight cycle_ptx_call passes
#define CYCLE_PTX_ARGUMENTS_MOST 8u

// a lane being written: the ruleset it is written in, and 1 where a form was written with other arguments than it
// takes; its steps' text and the step being written; the temporaries, 64-bit temporaries and predicates that step has
// taken and the most any step took; where each member's words begin among the atoms' words, which are loaded, and each
// one's first and last reader; which of the block's functions it calls and whether it reads the tables; the scratch's
// first place and width, which every call shares; for each record word, 1 past the last step whose put lays it (0 for
// a word no put lays) and the first such step; for each step, 1 where the lane can leave it refused, and the 32-bit
// words its own temporaries take
struct CyclePtx
{
    const EngineRecordLayout *layout;
    const CycleRuleset *rules;
    int broken;
    std::string text;
    unsigned int at;
    unsigned int temps;
    unsigned int temps_most;
    unsigned int wides;
    unsigned int wides_most;
    unsigned int predicates;
    unsigned int predicates_most;
    unsigned int atom_first[ENGINE_RECORD_MEMBERS_MAX];
    std::vector<unsigned char> loaded;
    std::vector<unsigned int> atom_read_first;
    std::vector<unsigned int> atom_read_last;
    unsigned int called[CYCLE_PTX_CALLEES];
    unsigned int tables;
    unsigned int scratch;
    unsigned int wide;
    std::vector<unsigned int> put_last;
    std::vector<unsigned int> put_first;
    std::vector<unsigned char> refuses;
    std::vector<unsigned int> step_words;
};

// a step as its emitter reads it: the step, and its register's place and its operands'
struct CyclePtxStep
{
    const DeviceRecordStep *step;
    unsigned int place;
    unsigned int left_place;
    unsigned int right_place;
};

// a count or an offset as the forms take it, in decimal
static std::string cycle_ptx_number(unsigned long long value)
{
    return std::to_string(value);
}

static std::string cycle_ptx_temporary(CyclePtx *ptx);

static std::string cycle_ptx_wide(CyclePtx *ptx);

static std::string cycle_ptx_predicate(CyclePtx *ptx);

// form `name` of the lane's ruleset written into `text` with `arguments` in its parameters' places. A form written with
// other arguments than it takes writes nothing and marks the lane broken, and its program goes to the C source. A form
// the ruleset gives as a construct takes its scratch as the step's own temporaries, 64-bit temporaries and predicates,
// fresh for the step and declared with them; a construct that takes scratch of another bank breaks the lane
static void cycle_ptx_form(CyclePtx *ptx, std::string &text, CycleFormName name,
                           std::initializer_list<std::string> arguments)
{
    const CycleScratch scratch = [ptx](unsigned int bank) {
        return (bank == CYCLE_BANK_TEMPORARY) ? cycle_ptx_temporary(ptx)
             : ((bank == CYCLE_BANK_WIDE) ? cycle_ptx_wide(ptx)
                                          : ((bank == CYCLE_BANK_PREDICATE) ? cycle_ptx_predicate(ptx) : std::string()));
    };
    // a form's name is its place in the schema, from 0
    cycle_ruleset_write_taking(ptx->rules, text, (unsigned int)name, arguments, scratch, &ptx->broken);
}

// register `at` of a bank, as the ruleset spells it
static std::string cycle_ptx_register(const CyclePtx *ptx, CycleBankName bank, unsigned int at)
{
    const CycleForm *const form = &ptx->rules->banks[bank];
    const std::string number = cycle_ptx_number(at);
    std::string name = form->pieces[0];
    for (size_t slot = 0u; slot < form->slots.size(); slot += 1u)
    {
        name += number;
        name += form->pieces[slot + 1u];
    }
    return name;
}

// a register the lane holds throughout, as the ruleset spells it
static const std::string &cycle_ptx_fixed(const CyclePtx *ptx, CycleFixedName fixed)
{
    return ptx->rules->fixed[fixed];
}

// the next of a bank's registers for the step being written, the most any step took kept for the lane to declare
static std::string cycle_ptx_take(const CyclePtx *ptx, CycleBankName bank, unsigned int *taken, unsigned int *most)
{
    const std::string name = cycle_ptx_register(ptx, bank, *taken);
    *taken += 1u;
    *most = (*taken > *most) ? *taken : *most;
    return name;
}

static std::string cycle_ptx_temporary(CyclePtx *ptx)
{
    return cycle_ptx_take(ptx, CYCLE_BANK_TEMPORARY, &ptx->temps, &ptx->temps_most);
}

static std::vector<std::string> cycle_ptx_temporaries(CyclePtx *ptx, unsigned int count)
{
    std::vector<std::string> names(count);
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        names[at] = cycle_ptx_temporary(ptx);
    }
    return names;
}

static std::string cycle_ptx_wide(CyclePtx *ptx)
{
    return cycle_ptx_take(ptx, CYCLE_BANK_WIDE, &ptx->wides, &ptx->wides_most);
}

static std::string cycle_ptx_predicate(CyclePtx *ptx)
{
    return cycle_ptx_take(ptx, CYCLE_BANK_PREDICATE, &ptx->predicates, &ptx->predicates_most);
}

// the lane leaves the step being written refused where `refused` holds, for the store of the record words it has not
// stored yet: those whose last put is this step's or a later one's
static void cycle_ptx_refuse(CyclePtx *ptx, const std::string &refused)
{
    ptx->refuses[ptx->at] = 1u;
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_REFUSE, {refused, cycle_ptx_number(ptx->at)});
}

// a register's first `count` limbs at `place`, then the zero register up to `width`: a register read past its limbs
// reads 0
static std::vector<std::string> cycle_ptx_limbs(const CyclePtx *ptx, unsigned int place, unsigned int count,
                                                unsigned int width)
{
    std::vector<std::string> names(width, cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO));
    for (unsigned int at = 0u; (at < count) && (at < width); at += 1u)
    {
        names[at] = cycle_ptx_register(ptx, CYCLE_BANK_FILE, place + at);
    }
    return names;
}

// one chain laid through `limbs` limbs from the lowest: each limb of `to` is left's and right's by the chain's form
// for its place in the chain
static void cycle_ptx_chain(CyclePtx *ptx, const CyclePtxChain *chain, const std::vector<std::string> &to,
                            const std::vector<std::string> &left, const std::vector<std::string> &right,
                            unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const CycleFormName form = (limbs == 1u) ? chain->alone
                                 : ((at == 0u) ? chain->first : ((at == (limbs - 1u)) ? chain->last : chain->middle));
        cycle_ptx_form(ptx, ptx->text, form, {to[at], left[at], right[at]});
    }
}

// to = -from modulo 2^(32 limbs), the two's complement, as zero less the register
static void cycle_ptx_negate(CyclePtx *ptx, const std::vector<std::string> &to, const std::vector<std::string> &from,
                             unsigned int limbs)
{
    const std::vector<std::string> zero(limbs, cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO));
    cycle_ptx_chain(ptx, &s_cycle_ptx_subtract, to, zero, from, limbs);
}

// a predicate set where the borrow chain just laid borrowed past its top limb, read from the borrow it left
static std::string cycle_ptx_borrowed(CyclePtx *ptx)
{
    const std::string borrow = cycle_ptx_temporary(ptx);
    const std::string borrowed = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_BORROW_READ, {borrow, borrowed});
    return borrowed;
}

// a limb kept to its low `kept` bits where kept is under 32; kept is reckoned as the interpreter reckons it, in 32
// bits, wrapping
static void cycle_ptx_mask(CyclePtx *ptx, const std::string &limb, unsigned int kept)
{
    if (kept < 32u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_AND, {limb, limb, cycle_ptx_number((1u << kept) - 1u)});
    }
}

// to = chosen where `where` holds, else otherwise, limb by limb
static void cycle_ptx_select(CyclePtx *ptx, const std::vector<std::string> &to, const std::vector<std::string> &chosen,
                             const std::vector<std::string> &otherwise, const std::string &where, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SELECT, {to[at], chosen[at], otherwise[at], where});
    }
}

// a predicate set where any of the first `limbs` limbs is not zero
static std::string cycle_ptx_nonzero(CyclePtx *ptx, const std::vector<std::string> &value, unsigned int limbs)
{
    const std::string nonzero = cycle_ptx_predicate(ptx);
    if (limbs == 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NONZERO, {nonzero, value[0]});
        return nonzero;
    }
    const std::string any = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_OR, {any, value[0], value[1]});
    for (unsigned int at = 2u; at < limbs; at += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_OR, {any, any, value[at]});
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NONZERO, {nonzero, any});
    return nonzero;
}

// a predicate set where bit `bit` of the register is 1
static std::string cycle_ptx_bit(CyclePtx *ptx, const std::vector<std::string> &value, unsigned int bit)
{
    const std::string held = cycle_ptx_temporary(ptx);
    const std::string set = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_AND, {held, value[bit / 32u], cycle_ptx_number(1u << (bit % 32u))});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NONZERO, {set, held});
    return set;
}

// the step's sign: `held`, a register or an immediate, where its register is not zero, and 0 where it is
static void cycle_ptx_sign(CyclePtx *ptx, const CyclePtxStep *at, const std::string &held)
{
    const unsigned int limbs = at->step->limbs;
    const std::string nonzero = cycle_ptx_nonzero(ptx, cycle_ptx_limbs(ptx, at->place, limbs, limbs), limbs);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT,
                   {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place), held, std::string("0"), nonzero});
}

// the step's sign as -1 where `negative` holds and 1 where not, and 0 where its register is zero
static void cycle_ptx_sign_negative(CyclePtx *ptx, const CyclePtxStep *at, const std::string &negative)
{
    const std::string held = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {held, std::string("-1"), std::string("1"), negative});
    cycle_ptx_sign(ptx, at, held);
}

// word `word` of a member's atom, loaded once at its first reader, and the zero register past the atom's limbs. The
// lane runs its steps in one straight line, which a refused lane leaves for good, so every later reader follows the
// load
static std::string cycle_ptx_atom(CyclePtx *ptx, unsigned int member, unsigned int word)
{
    if (word >= ptx->layout->in_limbs[member])
    {
        return cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO);
    }
    const unsigned int at = ptx->atom_first[member] + word;
    const std::string name = cycle_ptx_register(ptx, CYCLE_BANK_ATOM, at);
    if (ptx->loaded[at] == 0u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_GLOBAL_LOAD,
                       {name, cycle_ptx_register(ptx, CYCLE_BANK_MEMBER, member), cycle_ptx_number(4u * word)});
        ptx->loaded[at] = 1u;
        ptx->atom_read_first[at] = ptx->at;
    }
    ptx->atom_read_last[at] = ptx->at;
    return name;
}

// a field, unsigned or signed, gathered as cycle_record_field gathers it: each limb its two atom words funnel-shifted,
// masked to the bits left where fewer than 32 are. A signed field whose top bit is set is negated within its bits, the
// magnitude kept and the sign -1
static void cycle_ptx_field(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->right;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = step->left + (32u * limb);
        const unsigned int shift = bit % 32u;
        const std::string low = cycle_ptx_atom(ptx, step->member, bit / 32u);
        if (shift == 0u)
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {value[limb], low});
        }
        else
        {
            const std::string high = cycle_ptx_atom(ptx, step->member, (bit / 32u) + 1u);
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_FUNNEL_RIGHT,
                           {value[limb], low, high, cycle_ptx_number(shift)});
        }
        cycle_ptx_mask(ptx, value[limb], bits - (32u * limb));
    }
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        cycle_ptx_sign(ptx, at, std::string("1"));
        return;
    }
    const std::string negative = cycle_ptx_bit(ptx, value, bits - 1u);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_mask(ptx, negated[limbs - 1u], bits - (32u * (limbs - 1u)));
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// a constant's two words, every limb above them cleared, its sign known as it is written
static void cycle_ptx_constant(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        const unsigned int word = (limb == 0u) ? step->left : ((limb == 1u) ? step->right : 0u);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET,
                       {cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->place + limb), cycle_ptx_number(word)});
    }
    const int nonzero = (step->left != 0u) || ((step->limbs > 1u) && (step->right != 0u));
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SET,
                   {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place), std::string(nonzero ? "1" : "0")});
}

// the lane's own number, its two words and every limb above them cleared; never negative
static void cycle_ptx_lane(CyclePtx *ptx, const CyclePtxStep *at)
{
    const unsigned int limbs = at->step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::string &lane_number = cycle_ptx_fixed(ptx, CYCLE_FIXED_LANE_NUMBER);
    if (limbs == 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_FROM_WIDE, {value[0], lane_number});
    }
    else
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_UNPACK, {value[0], value[1], lane_number});
    }
    for (unsigned int limb = 2u; limb < limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET, {value[limb], std::string("0")});
    }
    const std::string counted = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_WIDE_NONZERO, {counted, lane_number});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT,
                   {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place), std::string("1"), std::string("0"), counted});
}

// the magnitude, and a sign of 1 for any register not zero
static void cycle_ptx_absolute(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, step->limbs, step->limbs);
    const std::vector<std::string> left = cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {value[limb], left[limb]});
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_ABSOLUTE,
                   {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place),
                    cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place)});
}

// the order of two signed registers, as cycle_record_operate takes it: signs that differ order the registers alone,
// and signs that agree order them by their magnitudes, read from their difference's borrow and whether it is zero,
// times the sign. The order is the step's sign, and its low limb 1 where the registers differ
static void cycle_ptx_compare(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const std::vector<std::string> difference = cycle_ptx_temporaries(ptx, width);
    cycle_ptx_chain(ptx, &s_cycle_ptx_borrow, difference, cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, width),
                    cycle_ptx_limbs(ptx, at->right_place, step->right_limbs, width), width);
    const std::string below = cycle_ptx_borrowed(ptx);
    const std::string differs = cycle_ptx_nonzero(ptx, difference, width);
    const std::string left_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place);
    const std::string right_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->right_place);
    const std::string sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place);
    const std::string order = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {order, std::string("-1"), std::string("1"), below});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {order, order, std::string("0"), differs});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_MULTIPLY, {order, left_sign, order});
    const std::string greater = cycle_ptx_predicate(ptx);
    const std::string apart = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_SIGNED_GREATER, {greater, left_sign, right_sign});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {apart, std::string("1"), std::string("-1"), greater});
    const std::string unlike = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_SIGNED_DIFFER, {unlike, left_sign, right_sign});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {sign, apart, order, unlike});
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, step->limbs, step->limbs);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_ABSOLUTE, {value[0], sign});
    for (unsigned int limb = 1u; limb < step->limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET, {value[limb], std::string("0")});
    }
}

// the sum or the difference of two signed registers, branch-free: the magnitudes' sum, their difference with its
// borrow, and that difference negated are all taken, and the signs choose among them as cycle_record_operate does.
// Signs that agree, or either one zero, add, and take the left's sign where it has one; signs that differ subtract the
// lesser magnitude from the greater, the borrow saying which is greater, and take the greater's sign
static void cycle_ptx_sum(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const unsigned int reach = (width > limbs) ? width : limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::string left_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place);
    cycle_ptx_chain(ptx, &s_cycle_ptx_add, value, cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, limbs),
                    cycle_ptx_limbs(ptx, at->right_place, step->right_limbs, limbs), limbs);
    // the difference runs over every limb either operand holds, so its borrow is their order
    const std::vector<std::string> difference = cycle_ptx_temporaries(ptx, reach);
    cycle_ptx_chain(ptx, &s_cycle_ptx_borrow, difference, cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, reach),
                    cycle_ptx_limbs(ptx, at->right_place, step->right_limbs, reach), reach);
    const std::string below = cycle_ptx_borrowed(ptx);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, difference, limbs);
    std::string addend_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->right_place);
    if (step->operation == ENGINE_RECORD_DIFFERENCE)
    {
        const std::string turned = cycle_ptx_temporary(ptx);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_NEGATE, {turned, addend_sign});
        addend_sign = turned;
    }
    const std::string signs = cycle_ptx_temporary(ptx);
    const std::string opposed = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_MULTIPLY, {signs, left_sign, addend_sign});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NEGATIVE, {opposed, signs});
    cycle_ptx_select(ptx, difference, negated, difference, below, limbs);
    cycle_ptx_select(ptx, value, difference, value, opposed, limbs);
    const std::string greater = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {greater, addend_sign, left_sign, below});
    const std::string leads = cycle_ptx_predicate(ptx);
    const std::string kept = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_SIGNED_DIFFER, {leads, left_sign, std::string("0")});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {kept, left_sign, addend_sign, leads});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_SELECT, {greater, greater, kept, opposed});
    cycle_ptx_sign(ptx, at, greater);
}

// the product truncated to the step's limbs, cycle_record_product's schoolbook rows unrolled: each limb product a
// mad.lo and madc.hi pair on the carry flag with the row's carry added in, and the row's last carry run up the limbs
// above it. The sign is the operands' signs multiplied, as the interpreter takes it
static void cycle_ptx_product(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::string &zero = cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET, {value[limb], std::string("0")});
    }
    const std::string carry = cycle_ptx_temporary(ptx);
    const std::string upper = cycle_ptx_temporary(ptx);
    for (unsigned int low = 0u; low < step->left_limbs; low += 1u)
    {
        const std::string multiplier = cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->left_place + low);
        for (unsigned int high = 0u; (high < step->right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const std::string multiplicand = cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->right_place + high);
            const std::string &to = value[low + high];
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_PRODUCT_LOW, {to, multiplier, multiplicand, to});
            if (high == 0u)
            {
                cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_PRODUCT_HIGH, {carry, multiplier, multiplicand});
            }
            else
            {
                cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_PRODUCT_HIGH, {upper, multiplier, multiplicand});
                cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_ADD_FIRST, {to, to, carry});
                cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_ADD_LAST, {carry, upper, zero});
            }
        }
        if ((low + step->right_limbs) < limbs)
        {
            const unsigned int above = limbs - (low + step->right_limbs);
            const std::vector<std::string> run(value.begin() + (std::ptrdiff_t)(low + step->right_limbs), value.end());
            std::vector<std::string> added(above, zero);
            added[0] = carry;
            cycle_ptx_chain(ptx, &s_cycle_ptx_add, run, run, added, above);
        }
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_MULTIPLY,
                   {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place),
                    cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place),
                    cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->right_place)});
}

// a table's row: the source's low index_bits select it, and its limbs are loaded from the program's tables at
// table_offset + index . limbs, reckoned in 32 bits as the interpreter reckons it
static void cycle_ptx_table(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    ptx->tables = 1u;
    const std::string index = cycle_ptx_temporary(ptx);
    const std::string source = cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->left_place);
    if (step->index_bits >= 32u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {index, source});
    }
    else
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_AND,
                       {index, source, cycle_ptx_number((1u << step->index_bits) - 1u)});
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_MULTIPLY, {index, index, cycle_ptx_number(step->limbs)});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_ADD_ALONE, {index, index, cycle_ptx_number(step->table_offset)});
    const std::string address = cycle_ptx_wide(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_MULTIPLY_WORD, {address, index, std::string("4")});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_ADD, {address, cycle_ptx_fixed(ptx, CYCLE_FIXED_TABLES), address});
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, step->limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_GLOBAL_LOAD, {value[limb], address, cycle_ptx_number(4u * limb)});
    }
    cycle_ptx_sign(ptx, at, std::string("1"));
}

// the xor or the and of two registers' two's complements, each taken over the step's limbs by negating where its sign
// is negative, then read back as a magnitude: negated again where the result's sign is negative, which is the xor's
// where exactly one operand is and the and's where both are
static void cycle_ptx_bitwise(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::string left_negative = cycle_ptx_predicate(ptx);
    const std::string right_negative = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NEGATIVE,
                   {left_negative, cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place)});
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NEGATIVE,
                   {right_negative, cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->right_place)});
    const std::vector<std::string> left = cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, limbs);
    const std::vector<std::string> right = cycle_ptx_limbs(ptx, at->right_place, step->right_limbs, limbs);
    const std::vector<std::string> one = cycle_ptx_temporaries(ptx, limbs);
    const std::vector<std::string> other = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, one, left, limbs);
    cycle_ptx_select(ptx, one, one, left, left_negative, limbs);
    cycle_ptx_negate(ptx, other, right, limbs);
    cycle_ptx_select(ptx, other, other, right, right_negative, limbs);
    const int exclusive = (step->operation == ENGINE_RECORD_XOR);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, (exclusive != 0) ? CYCLE_FORM_WORD_XOR : CYCLE_FORM_WORD_AND,
                       {value[limb], one[limb], other[limb]});
    }
    const std::string negative = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, (exclusive != 0) ? CYCLE_FORM_PREDICATE_XOR : CYCLE_FORM_PREDICATE_AND,
                   {negative, left_negative, right_negative});
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// the left register wrapped to wrap_bits of two's complement and read back signed, as cycle_record_wrap wraps it: a
// wrap wider than the step's limbs passes the register through, and any other takes its two's complement over the
// limbs, keeps the wrap's bits, and negates within them where the top one is set
static void cycle_ptx_wrap(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->wrap_bits;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::vector<std::string> left = cycle_ptx_limbs(ptx, at->left_place, step->left_limbs, limbs);
    const std::string left_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place);
    if (bits > (32u * limbs))
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {value[limb], left[limb]});
        }
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY,
                       {cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place), left_sign});
        return;
    }
    const std::string left_negative = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NEGATIVE, {left_negative, left_sign});
    const std::vector<std::string> complement = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, complement, left, limbs);
    cycle_ptx_select(ptx, value, complement, left, left_negative, limbs);
    const unsigned int kept = bits - (32u * (limbs - 1u));
    cycle_ptx_mask(ptx, value[limbs - 1u], kept);
    const std::string negative = cycle_ptx_bit(ptx, value, bits - 1u);
    const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, limbs);
    cycle_ptx_negate(ptx, negated, value, limbs);
    cycle_ptx_mask(ptx, negated[limbs - 1u], kept);
    cycle_ptx_select(ptx, value, negated, value, negative, limbs);
    cycle_ptx_sign_negative(ptx, at, negative);
}

// a division by a divisor of one limb, cycle_record_divide's one-limb long division unrolled from the numerator's top
// limb down: each limb's quotient word by div, and the carried remainder the limb less the quotient word times the
// divisor, which is exact in 32 bits since it is below the divisor. The numerator's zero limbs above its used ones
// divide to zero and carry nothing, as the interpreter's skipping them does. A zero divisor refuses the lane; an exact
// quotient refuses a remainder and a quotient that outgrows its register, as the inverse's multiply back does
static void cycle_ptx_short_division(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const std::vector<std::string> value = cycle_ptx_limbs(ptx, at->place, limbs, limbs);
    const std::string divisor = cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->right_place);
    const std::string left_sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->left_place);
    const std::string nothing = cycle_ptx_predicate(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_ZERO, {nothing, divisor});
    cycle_ptx_refuse(ptx, nothing);
    const std::string carried = cycle_ptx_temporary(ptx);
    const std::string taken = cycle_ptx_temporary(ptx);
    const std::string wide_divisor = cycle_ptx_wide(ptx);
    const std::string part = cycle_ptx_wide(ptx);
    std::vector<std::string> quotient(left_limbs);
    for (unsigned int word = 0u; word < left_limbs; word += 1u)
    {
        quotient[word] = ((operation != ENGINE_RECORD_REMAINDER) && (word < limbs)) ? value[word]
                                                                                   : cycle_ptx_temporary(ptx);
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_FROM_WORD, {wide_divisor, divisor});
    for (unsigned int word = left_limbs; word > 0u; word -= 1u)
    {
        const std::string numerator = cycle_ptx_register(ptx, CYCLE_BANK_FILE, at->left_place + word - 1u);
        const std::string &quotient_word = quotient[word - 1u];
        if (word == left_limbs)
        {
            // nothing is carried into the top limb, so its word divides alone
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_DIVIDE, {quotient_word, numerator, divisor});
        }
        else
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_PACK, {part, numerator, carried});
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WIDE_DIVIDE, {part, part, wide_divisor});
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_FROM_WIDE, {quotient_word, part});
        }
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_MULTIPLY, {taken, quotient_word, divisor});
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SUBTRACT_ALONE, {carried, numerator, taken});
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {value[0], carried});
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET, {value[limb], std::string("0")});
        }
        cycle_ptx_sign(ptx, at, left_sign);
        return;
    }
    for (unsigned int limb = left_limbs; limb < limbs; limb += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET, {value[limb], std::string("0")});
    }
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        const std::string remains = cycle_ptx_predicate(ptx);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NONZERO, {remains, carried});
        cycle_ptx_refuse(ptx, remains);
        if (left_limbs > limbs)
        {
            const std::vector<std::string> outgrown(quotient.begin() + (std::ptrdiff_t)limbs, quotient.end());
            const std::string over = cycle_ptx_nonzero(ptx, outgrown, left_limbs - limbs);
            cycle_ptx_refuse(ptx, over);
        }
    }
    const std::string held = cycle_ptx_temporary(ptx);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SIGN_MULTIPLY,
                   {held, left_sign, cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->right_place)});
    cycle_ptx_sign(ptx, at, held);
}

// a register's limbs and its sign to their places in shared memory where `out`, else back from them: place p of this
// thread is word p . threads + thread, and its sign the byte at p . threads + thread past every place's word, as the
// operator block lays them
static void cycle_ptx_share(CyclePtx *ptx, unsigned int place, unsigned int limbs, int out)
{
    const std::string address = cycle_ptx_temporary(ptx);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const std::string word = cycle_ptx_register(ptx, CYCLE_BANK_FILE, place + limb);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_MULTIPLY_ADD,
                       {address, cycle_ptx_fixed(ptx, CYCLE_FIXED_WORD_STRIDE), cycle_ptx_number(place + limb),
                        cycle_ptx_fixed(ptx, CYCLE_FIXED_WORD_BASE)});
        if (out != 0)
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SHARED_STORE, {address, word});
        }
        else
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SHARED_LOAD, {word, address});
        }
    }
    const std::string sign = cycle_ptx_register(ptx, CYCLE_BANK_SIGN, place);
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_MULTIPLY_ADD,
                   {address, cycle_ptx_fixed(ptx, CYCLE_FIXED_THREADS), cycle_ptx_number(place),
                    cycle_ptx_fixed(ptx, CYCLE_FIXED_SIGN_BASE)});
    if (out != 0)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SHARED_STORE_BYTE, {address, sign});
    }
    else
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_SHARED_LOAD_SIGNED_BYTE, {sign, address});
    }
}

// a step the operator block does: its operands to their places in shared memory, one call by the calling convention,
// and its register and sign back from its own. A function that answers refuses the lane with 0
static void cycle_ptx_call(CyclePtx *ptx, const CyclePtxStep *at, unsigned int callee)
{
    const DeviceRecordStep *const step = at->step;
    const CyclePtxCallee *const called = &s_cycle_ptx_callees[callee];
    ptx->called[callee] = 1u;
    cycle_ptx_share(ptx, at->left_place, step->left_limbs, 1);
    cycle_ptx_share(ptx, at->right_place, step->right_limbs, 1);
    const unsigned int arguments[CYCLE_PTX_ARGUMENTS_MOST] = {at->place,         step->limbs,       at->left_place,
                                                              step->left_limbs,  at->right_place,   step->right_limbs,
                                                              ptx->scratch,      ptx->wide};
    const std::string answer = (called->answers != 0u) ? cycle_ptx_temporary(ptx) : std::string();
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_OPEN, {});
    for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_ARGUMENT,
                       {cycle_ptx_number(argument), cycle_ptx_number(arguments[argument])});
    }
    if (called->answers != 0u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_ANSWER_DECLARE, {});
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_ANSWERED, {std::string(called->name)});
    }
    else
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL, {std::string(called->name)});
    }
    for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
    {
        cycle_ptx_form(ptx, ptx->text, (argument != 0u) ? CYCLE_FORM_CALL_PARAMETER_NEXT : CYCLE_FORM_CALL_PARAMETER_FIRST,
                       {cycle_ptx_number(argument)});
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_PARAMETERS_CLOSE, {});
    if (called->answers != 0u)
    {
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_ANSWER_LOAD, {answer});
    }
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_CALL_CLOSE, {});
    cycle_ptx_share(ptx, at->place, step->limbs, 0);
    if (called->answers != 0u)
    {
        const std::string refused = cycle_ptx_predicate(ptx);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_SIGNED_ZERO, {refused, answer});
        cycle_ptx_refuse(ptx, refused);
    }
}

// 1 where an operation's register is never negative, so its put needs no two's complement
static int cycle_ptx_never_negative(unsigned int operation)
{
    return (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT)
        || (operation == ENGINE_RECORD_LANE) || (operation == ENGINE_RECORD_ABSOLUTE)
        || (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_GCD);
}

// the record words a step's put lays, [*low, *high): its out_bits' words from out_offset / 32, one more where the put
// is shifted within a word, and none at or past the record's limbs; empty for a step that puts nothing
static void cycle_ptx_put_words(const EngineRecordLayout *layout, const DeviceRecordStep *step, unsigned int *low,
                                unsigned int *high)
{
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int first = step->out_offset / 32u;
    const unsigned long long past = (unsigned long long)first + words + (((step->out_offset % 32u) != 0u) ? 1u : 0u);
    // clipped to the record's limbs, a 32-bit count
    const unsigned int end = (unsigned int)((past < layout->out_limbs) ? past : layout->out_limbs);
    *low = (step->out_bits == 0u) ? 0u : ((first < end) ? first : end);
    *high = (step->out_bits == 0u) ? 0u : end;
}

// each record word stored as the last put that lays it ends, so the lane does not hold it to its end
static void cycle_ptx_store_laid(CyclePtx *ptx, const DeviceRecordStep *step)
{
    unsigned int low = 0u;
    unsigned int high = 0u;
    cycle_ptx_put_words(ptx->layout, step, &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        if (ptx->put_last[word] == (ptx->at + 1u))
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_RECORD_STORE,
                           {cycle_ptx_number(4u * word), cycle_ptx_register(ptx, CYCLE_BANK_OUT, word)});
        }
    }
}

// the step's register laid into the record's words at out_offset, out_bits of it, as two's complement where its sign
// is negative, as cycle_put lays it; each word is the lane's own register until its last put
static void cycle_ptx_put(CyclePtx *ptx, const CyclePtxStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int top = step->out_bits - (32u * (words - 1u));
    const unsigned int first = step->out_offset / 32u;
    const unsigned int shift = step->out_offset % 32u;
    const unsigned int out_limbs = ptx->layout->out_limbs;
    const std::vector<std::string> held = cycle_ptx_limbs(ptx, at->place, step->limbs, words);
    const std::vector<std::string> word = cycle_ptx_temporaries(ptx, words);
    if (cycle_ptx_never_negative(step->operation) != 0)
    {
        for (unsigned int each = 0u; each < words; each += 1u)
        {
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_COPY, {word[each], held[each]});
        }
    }
    else
    {
        const std::string negative = cycle_ptx_predicate(ptx);
        cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_TEST_NEGATIVE,
                       {negative, cycle_ptx_register(ptx, CYCLE_BANK_SIGN, at->place)});
        const std::vector<std::string> negated = cycle_ptx_temporaries(ptx, words);
        cycle_ptx_negate(ptx, negated, held, words);
        cycle_ptx_select(ptx, word, negated, held, negative, words);
    }
    cycle_ptx_mask(ptx, word[words - 1u], top);
    unsigned int low_word = 0u;
    unsigned int high_word = 0u;
    cycle_ptx_put_words(ptx->layout, step, &low_word, &high_word);
    for (unsigned int laid = low_word; laid < high_word; laid += 1u)
    {
        if (ptx->put_first[laid] == ptx->at)
        {
            // the word's first put: its register begins here, cleared, and not at the lane's open
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SET,
                           {cycle_ptx_register(ptx, CYCLE_BANK_OUT, laid), std::string("0")});
        }
    }
    const std::string moved = cycle_ptx_temporary(ptx);
    for (unsigned int each = 0u; each < words; each += 1u)
    {
        const unsigned int low = first + each;
        if ((low < out_limbs) && (shift == 0u))
        {
            const std::string record = cycle_ptx_register(ptx, CYCLE_BANK_OUT, low);
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_OR, {record, record, word[each]});
        }
        else if (low < out_limbs)
        {
            const std::string record = cycle_ptx_register(ptx, CYCLE_BANK_OUT, low);
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SHIFT_LEFT, {moved, word[each], cycle_ptx_number(shift)});
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_OR, {record, record, moved});
        }
        if ((shift != 0u) && ((low + 1u) < out_limbs))
        {
            const std::string record = cycle_ptx_register(ptx, CYCLE_BANK_OUT, low + 1u);
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_SHIFT_RIGHT,
                           {moved, word[each], cycle_ptx_number(32u - shift)});
            cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_WORD_OR, {record, record, moved});
        }
    }
}

// the operator block's function a step calls, an index into s_cycle_ptx_callees, or CYCLE_PTX_CALLEES for a step the
// lane unrolls: every one but the gcd, the ladder, a division by more than one limb, and a product of more than
// CYCLE_PTX_PRODUCT_MOST limb products
static unsigned int cycle_ptx_callee(const DeviceRecordStep *step)
{
    const unsigned int operation = step->operation;
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                     || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    const int unrolled = ((operation == ENGINE_RECORD_PRODUCT)
                          && (((unsigned long long)step->left_limbs * step->right_limbs) <= CYCLE_PTX_PRODUCT_MOST))
                      || (divides && (step->right_limbs == 1u));
    for (unsigned int callee = 0u; (unrolled == 0) && (callee < CYCLE_PTX_CALLEES); callee += 1u)
    {
        if (s_cycle_ptx_callees[callee].operation == operation)
        {
            return callee;
        }
    }
    return CYCLE_PTX_CALLEES;
}

// one step of the lane and its put; 0 for a step the lane does not hold, which leaves the program to the C source
static int cycle_ptx_step(CyclePtx *ptx, unsigned int at)
{
    const EngineRecordLayout *const layout = ptx->layout;
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    // a wrap of no bits has no top bit to read
    if (!cycle_program_held(layout, at) || ((operation == ENGINE_RECORD_WRAP) && (step->wrap_bits == 0u)))
    {
        return 0;
    }
    CyclePtxStep view;
    view.step = step;
    view.place = step->place;
    view.left_place = cycle_program_reads_left(operation) ? layout->step_table[step->left].place : 0u;
    view.right_place = cycle_program_reads_right(operation) ? layout->step_table[step->right].place : 0u;
    ptx->at = at;
    ptx->temps = 0u;
    ptx->wides = 0u;
    ptx->predicates = 0u;
    cycle_ptx_form(ptx, ptx->text, CYCLE_FORM_STEP_NOTE, {cycle_ptx_number(at), cycle_ptx_number(operation)});
    const unsigned int callee = cycle_ptx_callee(step);
    if (callee < CYCLE_PTX_CALLEES)
    {
        cycle_ptx_call(ptx, &view, callee);
    }
    else if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        cycle_ptx_field(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_ptx_constant(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        cycle_ptx_lane(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        cycle_ptx_absolute(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_COMPARE)
    {
        cycle_ptx_compare(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE))
    {
        cycle_ptx_sum(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_PRODUCT)
    {
        cycle_ptx_product(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        cycle_ptx_table(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        cycle_ptx_bitwise(ptx, &view);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        cycle_ptx_wrap(ptx, &view);
    }
    else if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
             || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
    {
        cycle_ptx_short_division(ptx, &view);
    }
    else
    {
        // an operation this lane does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        cycle_ptx_put(ptx, &view);
        cycle_ptx_store_laid(ptx, step);
    }
    // a 64-bit temporary takes two words
    ptx->step_words[at] = ptx->temps + (2u * ptx->wides);
    return 1;
}

// the lane's registers, each bank as many as the lane takes
static void cycle_ptx_declare(std::string &text, CyclePtx *ptx, unsigned int atoms)
{
    const EngineRecordLayout *const layout = ptx->layout;
    if (ptx->predicates_most != 0u)
    {
        cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_PREDICATES, {cycle_ptx_number(ptx->predicates_most)});
    }
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_FIXED_PREDICATES, {});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_FILE, {cycle_ptx_number(layout->file_limbs)});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_SIGNS, {cycle_ptx_number(layout->file_limbs)});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_OUT, {cycle_ptx_number(layout->out_limbs)});
    if (atoms != 0u)
    {
        cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_ATOMS, {cycle_ptx_number(atoms)});
    }
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_TEMPORARIES, {cycle_ptx_number(ptx->temps_most)});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_WIDES, {cycle_ptx_number(ptx->wides_most)});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_FIXED_WORDS, {});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_FIXED_WIDES, {});
    cycle_ptx_form(ptx, text, CYCLE_FORM_DECLARE_MEMBERS, {cycle_ptx_number(ENGINE_RECORD_MEMBERS_MAX)});
}

// the lane's opening: its launch and number, the record's words no put lays stored as 0, and each member's atom found
// as cycle_program_source finds it, a lane whose atom lies past its member refused before any step; then the words a
// refusal would leave unlaid stored as 0, the program's tables, and the lane's places in shared memory where it calls
// the operator block
static void cycle_ptx_open(std::string &text, CyclePtx *ptx, unsigned int places, int calls)
{
    const EngineRecordLayout *const layout = ptx->layout;
    const std::string &zero = cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO);
    const std::string &lane_number = cycle_ptx_fixed(ptx, CYCLE_FIXED_LANE_NUMBER);
    const std::string &record = cycle_ptx_fixed(ptx, CYCLE_FIXED_RECORD);
    const std::string &index = cycle_ptx_fixed(ptx, CYCLE_FIXED_INDEX);
    const std::string &body = cycle_ptx_fixed(ptx, CYCLE_FIXED_BODY);
    const std::string &bodies = cycle_ptx_fixed(ptx, CYCLE_FIXED_BODIES);
    const std::string &indexed = cycle_ptx_fixed(ptx, CYCLE_FIXED_INDEXED);
    const std::string &one = cycle_ptx_fixed(ptx, CYCLE_FIXED_ONE);
    const std::string &good = cycle_ptx_fixed(ptx, CYCLE_FIXED_GOOD);
    // the opening's own 32- and 64-bit temporaries, the first of each bank, which no step has taken yet
    const std::string temporary = cycle_ptx_register(ptx, CYCLE_BANK_TEMPORARY, 0u);
    const std::string wide = cycle_ptx_register(ptx, CYCLE_BANK_WIDE, 0u);
    cycle_ptx_form(ptx, text, CYCLE_FORM_OPEN_LAUNCH, {});
    cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD, {record, cycle_ptx_number(offsetof(CycleCompiledLaunch, out))});
    cycle_ptx_form(ptx, text, CYCLE_FORM_TO_GLOBAL, {record});
    cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_MULTIPLY, {wide, lane_number, cycle_ptx_number(4u * layout->out_limbs)});
    cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_ADD, {record, record, wide});
    // a word no put lays is 0 on every lane, refused or not, and is stored before anything can refuse
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        if (ptx->put_last[word] == 0u)
        {
            cycle_ptx_form(ptx, text, CYCLE_FORM_RECORD_STORE, {cycle_ptx_number(4u * word), zero});
        }
    }
    cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD, {index, cycle_ptx_number(offsetof(CycleCompiledLaunch, index))});
    cycle_ptx_form(ptx, text, CYCLE_FORM_TEST_WIDE_NONZERO, {indexed, index});
    cycle_ptx_form(ptx, text, CYCLE_FORM_TO_GLOBAL, {index});
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        const std::string address = cycle_ptx_register(ptx, CYCLE_BANK_MEMBER, member);
        // with no index, lane i reads record i of a member, or its one record where it has one
        cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD,
                       {bodies, cycle_ptx_number(offsetof(CycleCompiledLaunch, bodies) + (8u * (size_t)member))});
        cycle_ptx_form(ptx, text, CYCLE_FORM_TEST_WIDE_EQUAL, {one, bodies, std::string("1")});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_SELECT, {body, std::string("0"), lane_number, one});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_MULTIPLY, {wide, lane_number, cycle_ptx_number(layout->members)});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_ADD_UNSIGNED, {wide, wide, cycle_ptx_number(member)});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_SHIFT_LEFT, {wide, wide, std::string("2")});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_ADD, {wide, index, wide});
        cycle_ptx_form(ptx, text, CYCLE_FORM_GUARDED_LOAD, {indexed, temporary, wide});
        cycle_ptx_form(ptx, text, CYCLE_FORM_GUARDED_WIDEN, {indexed, body, temporary});
        if (member == 0u)
        {
            cycle_ptx_form(ptx, text, CYCLE_FORM_TEST_WIDE_BELOW, {good, body, bodies});
        }
        else
        {
            cycle_ptx_form(ptx, text, CYCLE_FORM_TEST_WIDE_BELOW_AND, {good, body, bodies, good});
        }
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_SELECT, {body, body, std::string("0"), good});
        cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD,
                       {address, cycle_ptx_number(offsetof(CycleCompiledLaunch, in) + (8u * (size_t)member))});
        cycle_ptx_form(ptx, text, CYCLE_FORM_TO_GLOBAL, {address});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_MULTIPLY,
                       {wide, body, cycle_ptx_number(4u * layout->in_limbs[member])});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WIDE_ADD, {address, address, wide});
    }
    cycle_ptx_form(ptx, text, CYCLE_FORM_OPEN_REFUSED_UNLESS, {good});
    // a word whose first put comes at or after a step the lane can leave refused is 0 in the record until its last put
    // stores it, so the refusal stores only the words it holds in flight
    unsigned int refusal_first = layout->steps;
    for (unsigned int at = 0u; (at < layout->steps) && (refusal_first == layout->steps); at += 1u)
    {
        refusal_first = (ptx->refuses[at] != 0u) ? at : refusal_first;
    }
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        if ((ptx->put_last[word] != 0u) && (ptx->put_first[word] >= refusal_first))
        {
            cycle_ptx_form(ptx, text, CYCLE_FORM_RECORD_STORE, {cycle_ptx_number(4u * word), zero});
        }
    }
    if (ptx->tables != 0u)
    {
        const std::string &tables = cycle_ptx_fixed(ptx, CYCLE_FIXED_TABLES);
        cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD,
                       {tables, cycle_ptx_number(offsetof(CycleCompiledLaunch, tables))});
        cycle_ptx_form(ptx, text, CYCLE_FORM_TO_GLOBAL, {tables});
    }
    if (calls != 0)
    {
        // a word's address is cycle_words + 4 (place . threads + thread), a sign's cycle_words + 4 places . threads +
        // place . threads + thread
        const std::string &sign_base = cycle_ptx_fixed(ptx, CYCLE_FIXED_SIGN_BASE);
        cycle_ptx_form(ptx, text, CYCLE_FORM_SHARED_OPEN, {});
        cycle_ptx_form(ptx, text, CYCLE_FORM_WORD_MULTIPLY_ADD,
                       {sign_base, cycle_ptx_fixed(ptx, CYCLE_FIXED_THREADS), cycle_ptx_number(4u * places), sign_base});
        cycle_ptx_form(ptx, text, CYCLE_FORM_SHARED_CLOSE, {});
    }
}

// a refused lane counted in the launch's refusals
static void cycle_ptx_count_refused(std::string &text, CyclePtx *ptx)
{
    const std::string wide = cycle_ptx_register(ptx, CYCLE_BANK_WIDE, 0u);
    cycle_ptx_form(ptx, text, CYCLE_FORM_LAUNCH_LOAD, {wide, cycle_ptx_number(offsetof(CycleCompiledLaunch, refused))});
    cycle_ptx_form(ptx, text, CYCLE_FORM_TO_GLOBAL, {wide});
    cycle_ptx_form(ptx, text, CYCLE_FORM_COUNT_ADD, {wide});
}

// the lane's close. A lane that ran every step has stored each record word as its last put laid it, and returns. A lane
// refused leaves its record as its puts laid it before it ended, as the interpreter does: refused at the open, every
// word the steps lay is 0; refused at a step, it stores the words it holds in flight, their first put before that step
// and their last put that step or a later one. Every other word is already in the record, laid or 0
static void cycle_ptx_close(std::string &text, CyclePtx *ptx)
{
    const EngineRecordLayout *const layout = ptx->layout;
    cycle_ptx_form(ptx, text, CYCLE_FORM_RETURN, {});
    cycle_ptx_form(ptx, text, CYCLE_FORM_LABEL_REFUSED_OPEN, {});
    cycle_ptx_count_refused(text, ptx);
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        if (ptx->put_last[word] != 0u)
        {
            cycle_ptx_form(ptx, text, CYCLE_FORM_RECORD_STORE,
                           {cycle_ptx_number(4u * word), cycle_ptx_fixed(ptx, CYCLE_FIXED_ZERO)});
        }
    }
    cycle_ptx_form(ptx, text, CYCLE_FORM_RETURN, {});
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (ptx->refuses[at] == 0u)
        {
            continue;
        }
        cycle_ptx_form(ptx, text, CYCLE_FORM_LABEL_REFUSED, {cycle_ptx_number(at)});
        cycle_ptx_count_refused(text, ptx);
        for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
        {
            // put_last is 1 past the last put's step
            if ((ptx->put_last[word] > at) && (ptx->put_first[word] < at))
            {
                cycle_ptx_form(ptx, text, CYCLE_FORM_RECORD_STORE,
                               {cycle_ptx_number(4u * word), cycle_ptx_register(ptx, CYCLE_BANK_OUT, word)});
            }
        }
        cycle_ptx_form(ptx, text, CYCLE_FORM_RETURN, {});
    }
}

// the 32-bit words every lane holds throughout: %zero, %thread, %threads, %word_base, %word_stride and %sign_base, and
// the seven 64-bit %launch, %lane_number, %record, %index, %body, %bodies and %tables; each member's atom address adds
// two more
#define CYCLE_PTX_HELD_WORDS 20u

// the most 32-bit words the lane holds live at once, reckoned from the lifetimes its text gives ptxas: each value's
// limbs and sign from its step to its last reader, each record word from its first put to its last, each atom word from
// its first reader to its last, each step's own temporaries at that step, and the words every lane holds throughout
static unsigned int cycle_ptx_live_most(const CyclePtx *ptx)
{
    const EngineRecordLayout *const layout = ptx->layout;
    const unsigned int steps = layout->steps;
    std::vector<unsigned int> read_last(steps);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        read_last[at] = at;
    }
    // every operand is an earlier step, so the readers seen in order leave each value's last one
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        const DeviceRecordStep *const step = &layout->step_table[at];
        if (cycle_program_reads_left(step->operation))
        {
            read_last[step->left] = at;
        }
        if (cycle_program_reads_right(step->operation))
        {
            read_last[step->right] = at;
        }
    }
    // the change in live words at each step, their count its running sum
    std::vector<long long> change((size_t)steps + 1u, 0ll);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        const long long value = (long long)layout->step_table[at].limbs + 1ll;
        change[at] += value + (long long)ptx->step_words[at];
        change[read_last[at] + 1u] -= value;
        change[at + 1u] -= (long long)ptx->step_words[at];
    }
    for (unsigned int word = 0u; word < layout->out_limbs; word += 1u)
    {
        if (ptx->put_last[word] != 0u)
        {
            change[ptx->put_first[word]] += 1ll;
            change[ptx->put_last[word]] -= 1ll;
        }
    }
    for (size_t atom = 0u; atom < ptx->loaded.size(); atom += 1u)
    {
        if (ptx->loaded[atom] != 0u)
        {
            change[ptx->atom_read_first[atom]] += 1ll;
            change[(size_t)ptx->atom_read_last[atom] + 1u] -= 1ll;
        }
    }
    long long live = 0ll;
    long long most = 0ll;
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        live += change[at];
        most = (live > most) ? live : most;
    }
    // at most the file's limbs and signs, the record's words, the atoms' words and one step's temporaries, far under 2^32
    return (unsigned int)most + CYCLE_PTX_HELD_WORDS + (2u * layout->members);
}

// a program's lane as PTX in the ruleset `rules` under the header this toolkit writes, the places a thread holds in
// shared memory for the steps that call the operator block (the file's and the scratch's, 0 where no step calls), and
// the most words it holds live at once. It names the device, NVRTC and the operator block it is linked against, from
// `target`; empty where a step is one the lane does not hold, or a form was written with other arguments than it takes
std::string cycle_program_ptx(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                              const CycleRuleset *rules, const std::string &header, unsigned int *places,
                              unsigned int *live)
{
    CyclePtx ptx{};
    ptx.layout = layout;
    ptx.rules = rules;
    // the lane's opening takes %t0 and %w0 before any step does
    ptx.temps_most = 1u;
    ptx.wides_most = 1u;
    unsigned int atoms = 0u;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        ptx.atom_first[member] = atoms;
        atoms += layout->in_limbs[member];
    }
    ptx.loaded.assign(atoms, (unsigned char)0u);
    ptx.atom_read_first.assign(atoms, 0u);
    ptx.atom_read_last.assign(atoms, 0u);
    ptx.scratch = layout->file_limbs;
    ptx.put_last.assign(layout->out_limbs, 0u);
    ptx.put_first.assign(layout->out_limbs, 0u);
    ptx.refuses.assign(layout->steps, (unsigned char)0u);
    ptx.step_words.assign(layout->steps, 0u);
    // the calls that work in the scratch share it at the widest of their widths, and each record word's first and last
    // put are found before any step is written
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        const DeviceRecordStep *const step = &layout->step_table[at];
        const unsigned int callee = cycle_ptx_callee(step);
        if ((callee < CYCLE_PTX_CALLEES) && (s_cycle_ptx_callees[callee].arguments > 6u))
        {
            ptx.wide = (step->left_limbs > ptx.wide) ? step->left_limbs : ptx.wide;
            ptx.wide = (step->right_limbs > ptx.wide) ? step->right_limbs : ptx.wide;
            ptx.wide = (step->limbs > ptx.wide) ? step->limbs : ptx.wide;
        }
        unsigned int low = 0u;
        unsigned int high = 0u;
        cycle_ptx_put_words(layout, step, &low, &high);
        for (unsigned int word = low; word < high; word += 1u)
        {
            ptx.put_first[word] = (ptx.put_last[word] == 0u) ? at : ptx.put_first[word];
            ptx.put_last[word] = at + 1u;
        }
    }
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (cycle_ptx_step(&ptx, at) == 0)
        {
            return std::string();
        }
    }
    int calls = 0;
    for (unsigned int callee = 0u; callee < CYCLE_PTX_CALLEES; callee += 1u)
    {
        calls = calls || (ptx.called[callee] != 0u);
    }
    *places = (calls != 0) ? (layout->file_limbs + ((ptx.wide != 0u) ? CYCLE_RECORD_SCRATCH(ptx.wide) : 0u)) : 0u;
    std::string text;
    char block[32];
    snprintf(block, sizeof(block), "%016llx", target->block_hash);
    // a device's compute capability and NVRTC's version are small counts, never negative
    cycle_ptx_form(&ptx, text, CYCLE_FORM_PROGRAM_NOTE,
                   {cycle_ptx_number(layout->steps), cycle_ptx_number((unsigned long long)target->major),
                    cycle_ptx_number((unsigned long long)target->minor),
                    cycle_ptx_number((unsigned long long)target->nvrtc_major),
                    cycle_ptx_number((unsigned long long)target->nvrtc_minor), std::string(block)});
    text += header;
    if (calls != 0)
    {
        cycle_ptx_form(&ptx, text, CYCLE_FORM_SHARED_EXTERN, {});
    }
    for (unsigned int callee = 0u; callee < CYCLE_PTX_CALLEES; callee += 1u)
    {
        const CyclePtxCallee *const called = &s_cycle_ptx_callees[callee];
        if (ptx.called[callee] == 0u)
        {
            continue;
        }
        const std::string name(called->name);
        cycle_ptx_form(&ptx, text, (called->answers != 0u) ? CYCLE_FORM_CALLEE_DECLARE_ANSWERED : CYCLE_FORM_CALLEE_DECLARE,
                       {name});
        for (unsigned int argument = 0u; argument < called->arguments; argument += 1u)
        {
            cycle_ptx_form(&ptx, text,
                           ((argument + 1u) < called->arguments) ? CYCLE_FORM_CALLEE_PARAMETER
                                                                  : CYCLE_FORM_CALLEE_PARAMETER_LAST,
                           {name, cycle_ptx_number(argument)});
        }
        cycle_ptx_form(&ptx, text, CYCLE_FORM_CALLEE_CLOSE, {});
    }
    cycle_ptx_form(&ptx, text, CYCLE_FORM_LANE_OPEN, {});
    cycle_ptx_declare(text, &ptx, atoms);
    cycle_ptx_form(&ptx, text, CYCLE_FORM_LANE_BODY, {});
    cycle_ptx_open(text, &ptx, *places, calls);
    text += ptx.text;
    cycle_ptx_close(text, &ptx);
    cycle_ptx_form(&ptx, text, CYCLE_FORM_LANE_CLOSE, {});
    if (ptx.broken != 0)
    {
        return std::string();
    }
    *live = cycle_ptx_live_most(&ptx);
    return text;
}
