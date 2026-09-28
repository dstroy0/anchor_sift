// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_CORE_H
#define EMIT_CORE_H

// The register lane's decisions, as one source the host and the device both compile (engine_table.md item 11(f)(a),
// the emitter on the device). For each step it decides which forms of the language's ruleset the step is written in
// and with which arguments, and it decides the lane's declarations, opening, close and resident, and the cut of its
// body into states; it writes nothing. An argument is a register of a bank by its number, a register the lane holds
// throughout, or a number. The forms it decides are the same on any language, and the ruleset writes them
// (emit_lane.cu on the host, the text program on the device, emit_text.h). What a step decides from outside
// itself is laid before any step is decided, and steps are decided apart and in any order: each record word's first
// and last put, each atom word's first reader, and the loop number each step begins at. A step writes its forms into a
// sink, or counts them where the sink holds none. A device decides a lane in two passes, a count and a write, a
// thread a step. The lane's own forms come after every step, from what the steps left: the scratch a construct takes
// goes on from where the last step left each bank, as the lane was always written.
//
// The forms and what they do are the lane's as emit_lane.cu wrote them before this header held them, form for form and
// argument for argument, and the lane's text is unchanged (engine_table.md item 11(f)(a) holds the two to each other).

#include "emit.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define EMIT_CORE __host__ __device__ static inline
#else
#define EMIT_CORE static inline
#endif

// every form the emitter writes: its name here, its name in a .krs file, and how many parameters it takes
#define EMIT_FORMS(form_) \
    form_(PROGRAM_NOTE, "program_note", 6u) \
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
    form_(STATES_DECLARE, "states_declare", 1u) \
    form_(STATE_START, "state_start", 1u) \
    form_(STATE_OPEN, "state_open", 1u) \
    form_(STATE_NEXT, "state_next", 2u) \
    form_(STATE_EXIT, "state_exit", 0u) \
    form_(DISPATCH_TO, "dispatch_to", 2u) \
    form_(LAUNCH_ASK, "launch_ask", 1u) \
    form_(GLOBAL_ASK, "global_ask", 2u) \
    form_(GUARDED_ASK, "guarded_ask", 2u) \
    form_(COUNT_ASK, "count_ask", 1u) \
    form_(LOOP_LABEL, "loop_label", 1u) \
    form_(LOOP_BACK, "loop_back", 2u) \
    form_(STATE_LOOP, "state_loop", 3u) \
    form_(PROGRAM_UNIT, "program_unit", 25u)

// every bank of registers the emitter takes from, each written with one parameter, the register's number n
#define EMIT_BANKS(bank_) \
    bank_(FILE, "file") \
    bank_(SIGN, "sign") \
    bank_(OUT, "out") \
    bank_(ATOM, "atom") \
    bank_(TEMPORARY, "temporary") \
    bank_(WIDE, "wide") \
    bank_(PREDICATE, "predicate") \
    bank_(MEMBER, "member") \
    bank_(IMMEDIATE, "immediate")

// every register the lane holds throughout that the emitter passes to a form by name
#define EMIT_FIXED(fixed_) \
    fixed_(ZERO, "zero") \
    fixed_(LANE_NUMBER, "lane_number") \
    fixed_(RECORD, "record") \
    fixed_(INDEX, "index") \
    fixed_(BODY, "body") \
    fixed_(BODIES, "bodies") \
    fixed_(TABLES, "tables") \
    fixed_(THREADS, "threads") \
    fixed_(SIGN_BASE, "sign_base") \
    fixed_(INDEXED, "indexed") \
    fixed_(ONE, "one") \
    fixed_(GOOD, "good")

#define EMIT_FORM_NAMED(name_, text_, parameters_) EMIT_FORM_##name_,
#define EMIT_BANK_NAMED(name_, text_) EMIT_BANK_##name_,
#define EMIT_FIXED_NAMED(name_, text_) EMIT_FIXED_##name_,

enum EmitFormName
{
    EMIT_FORMS(EMIT_FORM_NAMED) EMIT_FORM_COUNT
};

enum EmitBankName
{
    EMIT_BANKS(EMIT_BANK_NAMED) EMIT_BANK_COUNT
};

enum EmitFixedName
{
    EMIT_FIXED(EMIT_FIXED_NAMED) EMIT_FIXED_COUNT
};

// the parameters each form takes, by its place in the schema
#define EMIT_FORM_PARAMETERS(name_, text_, parameters_) \
    case EMIT_FORM_##name_: \
        return parameters_;

EMIT_CORE unsigned int emit_core_parameters(unsigned int form)
{
    switch (form)
    {
        EMIT_FORMS(EMIT_FORM_PARAMETERS)
    default:
        return 0u;
    }
}

// the most limb products a lane unrolls a product into; a wider product is a loop over the left's limbs
#define EMIT_LANE_PRODUCT_MOST 1024u

// the state a refused lane goes to, which sends it on to its refusal's states, and the state the lane's opening begins
// in; state 0 is the language's own, where the lane waits to begin
#define EMIT_LANE_STATE_DISPATCH 1u
#define EMIT_LANE_STATE_FIRST 2u

// the most arguments a form a step decides takes. The program's note and its resident take more, every one of them the
// target's or the launch's layout, and are written from those (emit_core_unit)
#define EMIT_CORE_ARGUMENTS 4u

// the resident's parameters (program_unit)
#define EMIT_CORE_UNIT_PARAMETERS 25u

// a loop no state has begun, in the cut
#define EMIT_CORE_UNBEGUN 0xFFFFFFFFu

// what an argument is: a register of a bank by its number (the bank immediate a word's value), a register the lane
// holds throughout, a count or an offset in decimal, or a small signed number in decimal
enum EmitCoreKind
{
    EMIT_CORE_REGISTER = 1,
    EMIT_CORE_FIXED = 2,
    EMIT_CORE_NUMBER = 3,
    EMIT_CORE_SIGNED = 4
};

// an argument: its kind, the bank or the fixed register it names, and its number, or its value for a number (a signed
// number's two's complement)
struct EmitCoreArgument
{
    unsigned int kind;
    unsigned int which;
    unsigned int number;
};

// a form decided: its place in the schema, how many arguments it takes, its arguments, and where the scratch its
// construct takes begins in each of the temporaries, the 64-bit temporaries and the predicates, where the ruleset gives
// it as a construct. The program's note holds its step count alone and its resident none
struct EmitCoreItem
{
    unsigned int form;
    unsigned int count;
    EmitCoreArgument arguments[EMIT_CORE_ARGUMENTS];
    unsigned int scratch[3];
};

// a run of registers: element i is `first` with i added to its number below `count`, and the zero register from there
// to `width`; a register read past its limbs reads 0
struct EmitCoreRange
{
    EmitCoreArgument first;
    unsigned int count;
    unsigned int width;
};

// what every step reads and none decides: the step table and the program's shape; each record word's first put, and 1
// past its last (0 for a word no put lays); each atom word's first reader (the step count for a word none reads), where
// each member's words begin among the atoms' words; and for each form four words, the scratch its construct takes in
// the temporaries, the 64-bit temporaries and the predicates, and 1 where it takes scratch of a bank the lane gives none
// of (emit_ruleset_scratch, emit_rules.h)
struct EmitCoreProgram
{
    const DeviceRecordStep *steps;
    unsigned int step_count;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int file_limbs;
    unsigned int out_limbs;
    const unsigned int *put_first;
    const unsigned int *put_last;
    const unsigned int *atom_reader;
    unsigned int atom_first[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *scratch;
};

// a lane being decided: the program; the step being decided; the temporaries, 64-bit temporaries and predicates taken
// and the most taken; the next loop's number; 1 where the step can leave the lane refused, where it reads the tables,
// and where a form breaks the lane; one past the atom word the step last read; and the sink the forms go to, the forms it
// holds, and how many were decided, which a sink too small for them does not stop
struct EmitCoreLane
{
    const EmitCoreProgram *program;
    unsigned int at;
    unsigned int temps;
    unsigned int temps_most;
    unsigned int wides;
    unsigned int wides_most;
    unsigned int predicates;
    unsigned int predicates_most;
    unsigned int loops;
    unsigned int refuses;
    unsigned int tables;
    unsigned int broken;
    unsigned int atom_seen;
    EmitCoreItem *items;
    unsigned long long capacity;
    unsigned long long count;
};

// a carry chain through a register's limbs: the form a register of one limb takes, then the first, the middle and the
// last of a longer one, each setting or reading the carry as the ruleset writes it
struct EmitCoreChain
{
    unsigned int alone;
    unsigned int first;
    unsigned int middle;
    unsigned int last;
};

// a step as its forms read it: the step, and its register's place and its operands'
struct EmitCoreStep
{
    const DeviceRecordStep *step;
    unsigned int place;
    unsigned int left_place;
    unsigned int right_place;
};

// the lane's body being cut into states, a clock each: each form's cost by its place in the schema, how much a state
// may chain and how many memory writes it may make; the state being written, the cost it has chained and the writes it
// has made, 1 where it holds a form, 1 where its last form ends it and 1 where its last form left the lane; the states,
// the most cost one state chains, and the forms that alone cost more than a state holds; each refusal's label, by the
// refusal it names (-1 the opening's), and its first state, as many as `dispatch_most`; and each loop's first state, by
// the loop's number, as many as `loop_count`
struct EmitCoreCut
{
    const unsigned int *cost;
    unsigned int budget;
    unsigned int writes_most;
    unsigned int state;
    unsigned int chained;
    unsigned int writes;
    unsigned int filled;
    unsigned int ending;
    unsigned int left;
    unsigned int most;
    unsigned int over;
    EmitCoreArgument *dispatch_refusal;
    unsigned int *dispatch_state;
    unsigned int dispatch_count;
    unsigned int dispatch_most;
    unsigned int *loop_state;
    unsigned int loop_count;
};

// the arguments
EMIT_CORE EmitCoreArgument emit_core_register(unsigned int bank, unsigned int number)
{
    const EmitCoreArgument argument = {EMIT_CORE_REGISTER, bank, number};
    return argument;
}

// a word's value written into a form, as the ruleset's bank `immediate` writes a number: a language whose bare numbers
// are narrower than a word writes it as a word
EMIT_CORE EmitCoreArgument emit_core_immediate(unsigned int value)
{
    return emit_core_register(EMIT_BANK_IMMEDIATE, value);
}

EMIT_CORE EmitCoreArgument emit_core_fixed(unsigned int fixed)
{
    const EmitCoreArgument argument = {EMIT_CORE_FIXED, fixed, 0u};
    return argument;
}

EMIT_CORE EmitCoreArgument emit_core_number(unsigned int value)
{
    const EmitCoreArgument argument = {EMIT_CORE_NUMBER, 0u, value};
    return argument;
}

// -1, the one negative number a form is written with, as its two's complement word
EMIT_CORE EmitCoreArgument emit_core_minus_one(void)
{
    const EmitCoreArgument argument = {EMIT_CORE_SIGNED, 0u, 0xFFFFFFFFu};
    return argument;
}

EMIT_CORE EmitCoreArgument emit_core_zero(void)
{
    return emit_core_fixed(EMIT_FIXED_ZERO);
}

EMIT_CORE EmitCoreArgument emit_core_file(unsigned int place)
{
    return emit_core_register(EMIT_BANK_FILE, place);
}

EMIT_CORE EmitCoreArgument emit_core_sign(unsigned int place)
{
    return emit_core_register(EMIT_BANK_SIGN, place);
}

// the ranges
EMIT_CORE EmitCoreRange emit_core_range(EmitCoreArgument first, unsigned int count, unsigned int width)
{
    const EmitCoreRange range = {first, (count < width) ? count : width, width};
    return range;
}

EMIT_CORE EmitCoreArgument emit_core_at(const EmitCoreRange &range, unsigned int at)
{
    EmitCoreArgument element = range.first;
    element.number += at;
    return (at < range.count) ? element : emit_core_zero();
}

// `width` of a range's elements from its element `low`
EMIT_CORE EmitCoreRange emit_core_slice(const EmitCoreRange &range, unsigned int low, unsigned int width)
{
    const unsigned int count = (range.count > low) ? (range.count - low) : 0u;
    return emit_core_range((count != 0u) ? emit_core_at(range, low) : emit_core_zero(), count, width);
}

// a register alone, and none at all as wide as `width`, which reads 0 throughout
EMIT_CORE EmitCoreRange emit_core_one(EmitCoreArgument argument)
{
    return emit_core_range(argument, 1u, 1u);
}

EMIT_CORE EmitCoreRange emit_core_none(unsigned int width)
{
    return emit_core_range(emit_core_zero(), 0u, width);
}

// a register's first `count` limbs at `place`, then the zero register up to `width`: a register read past its limbs
// reads 0
EMIT_CORE EmitCoreRange emit_core_limbs(unsigned int place, unsigned int count, unsigned int width)
{
    return emit_core_range(emit_core_file(place), count, width);
}

// a form decided into the lane's sink, or counted where the sink holds none. A form the ruleset gives as a construct
// takes its scratch as the step's own temporaries, 64-bit temporaries and predicates, fresh for it, from where each
// bank stands, and declared with them; a construct that takes scratch of another bank breaks the lane
EMIT_CORE void emit_core_form(EmitCoreLane *lane, unsigned int form, unsigned int count, EmitCoreArgument first,
                              EmitCoreArgument second, EmitCoreArgument third, EmitCoreArgument fourth)
{
    if ((lane->items != NULL) && (lane->count < lane->capacity))
    {
        EmitCoreItem *const item = &lane->items[lane->count];
        item->form = form;
        item->count = count;
        item->arguments[0] = first;
        item->arguments[1] = second;
        item->arguments[2] = third;
        item->arguments[3] = fourth;
        item->scratch[0] = lane->temps;
        item->scratch[1] = lane->wides;
        item->scratch[2] = lane->predicates;
    }
    lane->count += 1ull;
    const unsigned int *const scratch = &lane->program->scratch[4u * form];
    lane->temps += scratch[0];
    lane->wides += scratch[1];
    lane->predicates += scratch[2];
    lane->broken = lane->broken | scratch[3];
    lane->temps_most = (lane->temps > lane->temps_most) ? lane->temps : lane->temps_most;
    lane->wides_most = (lane->wides > lane->wides_most) ? lane->wides : lane->wides_most;
    lane->predicates_most = (lane->predicates > lane->predicates_most) ? lane->predicates : lane->predicates_most;
}

EMIT_CORE void emit_core_form0(EmitCoreLane *lane, unsigned int form)
{
    const EmitCoreArgument none = emit_core_zero();
    emit_core_form(lane, form, 0u, none, none, none, none);
}

EMIT_CORE void emit_core_form1(EmitCoreLane *lane, unsigned int form, EmitCoreArgument first)
{
    const EmitCoreArgument none = emit_core_zero();
    emit_core_form(lane, form, 1u, first, none, none, none);
}

EMIT_CORE void emit_core_form2(EmitCoreLane *lane, unsigned int form, EmitCoreArgument first,
                               EmitCoreArgument second)
{
    const EmitCoreArgument none = emit_core_zero();
    emit_core_form(lane, form, 2u, first, second, none, none);
}

EMIT_CORE void emit_core_form3(EmitCoreLane *lane, unsigned int form, EmitCoreArgument first,
                               EmitCoreArgument second, EmitCoreArgument third)
{
    emit_core_form(lane, form, 3u, first, second, third, emit_core_zero());
}

EMIT_CORE void emit_core_form4(EmitCoreLane *lane, unsigned int form, EmitCoreArgument first,
                               EmitCoreArgument second, EmitCoreArgument third, EmitCoreArgument fourth)
{
    emit_core_form(lane, form, 4u, first, second, third, fourth);
}

// a form decided before into the lane's sink as it was, its scratch where it was taken
EMIT_CORE void emit_core_take(EmitCoreLane *lane, const EmitCoreItem *item)
{
    if ((lane->items != NULL) && (lane->count < lane->capacity))
    {
        lane->items[lane->count] = *item;
    }
    lane->count += 1ull;
}

// the next of a bank's registers for the step, the most any step took kept for the lane to declare
EMIT_CORE EmitCoreArgument emit_core_temporary(EmitCoreLane *lane)
{
    const EmitCoreArgument taken = emit_core_register(EMIT_BANK_TEMPORARY, lane->temps);
    lane->temps += 1u;
    lane->temps_most = (lane->temps > lane->temps_most) ? lane->temps : lane->temps_most;
    return taken;
}

EMIT_CORE EmitCoreRange emit_core_temporaries(EmitCoreLane *lane, unsigned int count)
{
    const EmitCoreRange taken = emit_core_range(emit_core_register(EMIT_BANK_TEMPORARY, lane->temps), count, count);
    lane->temps += count;
    lane->temps_most = (lane->temps > lane->temps_most) ? lane->temps : lane->temps_most;
    return taken;
}

EMIT_CORE EmitCoreArgument emit_core_wide(EmitCoreLane *lane)
{
    const EmitCoreArgument taken = emit_core_register(EMIT_BANK_WIDE, lane->wides);
    lane->wides += 1u;
    lane->wides_most = (lane->wides > lane->wides_most) ? lane->wides : lane->wides_most;
    return taken;
}

EMIT_CORE EmitCoreArgument emit_core_predicate(EmitCoreLane *lane)
{
    const EmitCoreArgument taken = emit_core_register(EMIT_BANK_PREDICATE, lane->predicates);
    lane->predicates += 1u;
    lane->predicates_most = (lane->predicates > lane->predicates_most) ? lane->predicates : lane->predicates_most;
    return taken;
}

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
EMIT_CORE int emit_core_operand(const EmitCoreProgram *program, unsigned int at, unsigned int operand,
                                unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= program->steps[operand].limbs);
}

// 1 where the operation reads a right register, and where it reads a left one: every one but the fields, the constant
// and the lane's number (emit_program_reads_right and emit_program_reads_left, emit.cu)
EMIT_CORE int emit_core_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

EMIT_CORE int emit_core_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED)
        && (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid (emit_program_held, emit.cu)
EMIT_CORE int emit_core_held(const EmitCoreProgram *program, unsigned int at)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    const int reads_left = emit_core_reads_left(operation);
    const int reads_left_whole = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at))
        && !(reads_left_whole && !emit_core_operand(program, at, step->left, step->left_limbs))
        && !(emit_core_reads_right(operation) && !emit_core_operand(program, at, step->right, step->right_limbs))
        && (((unsigned long long)step->place + step->limbs) <= (unsigned long long)program->file_limbs)
        && (!field || (step->member < program->members))
        && ((operation != ENGINE_RECORD_FIELD_SIGNED)
            || ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// the atom words a field step reads, [*low, *high) of its member's: each limb's word and, where the field is shifted
// within a word, the word after it, below the member's limbs; none for any other step or one the lane does not hold
EMIT_CORE void emit_core_atom_words(const EmitCoreProgram *program, unsigned int at, unsigned int *low,
                                    unsigned int *high)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const int field = (step->operation == ENGINE_RECORD_FIELD) || (step->operation == ENGINE_RECORD_FIELD_SIGNED);
    *low = 0u;
    *high = 0u;
    if (!field || !emit_core_held(program, at))
    {
        return;
    }
    const unsigned long long first = step->left / 32u;
    const unsigned long long past = first + step->limbs + (((step->left % 32u) != 0u) ? 1u : 0u);
    const unsigned long long limbs = program->in_limbs[step->member];
    // clipped to the member's limbs, 32-bit counts
    *low = (unsigned int)((first < limbs) ? first : limbs);
    *high = (unsigned int)((past < limbs) ? past : limbs);
}

// the record words a step's put lays, [*low, *high): its out_bits' words from out_offset / 32, one more where the put
// is shifted within a word, and none at or past the record's limbs; empty for a step that puts nothing
EMIT_CORE void emit_core_put_words(const EmitCoreProgram *program, const DeviceRecordStep *step, unsigned int *low,
                                   unsigned int *high)
{
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int first = step->out_offset / 32u;
    const unsigned long long past = (unsigned long long)first + words + (((step->out_offset % 32u) != 0u) ? 1u : 0u);
    // clipped to the record's limbs, a 32-bit count
    const unsigned int end = (unsigned int)((past < program->out_limbs) ? past : program->out_limbs);
    *low = (step->out_bits == 0u) ? 0u : ((first < end) ? first : end);
    *high = (step->out_bits == 0u) ? 0u : end;
}

// the loops step `at` writes, which the loop numbers each step begins at are the running sum of: the gcd's two, and one
// for the ladder, a division by more than one limb and a product too wide to unroll
EMIT_CORE unsigned int emit_core_loops(const EmitCoreProgram *program, unsigned int at)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                     || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    const int wide_product = (operation == ENGINE_RECORD_PRODUCT)
                          && (((unsigned long long)step->left_limbs * step->right_limbs) > EMIT_LANE_PRODUCT_MOST);
    return (operation == ENGINE_RECORD_GCD) ? 2u
         : (((divides && (step->right_limbs > 1u)) || (operation == ENGINE_RECORD_LADDER) || wide_product) ? 1u : 0u);
}

// the resident's arguments in its parameters' order: the launch's size, and by their byte offsets its count, hot words,
// block, number, time to live and check-in, the hot words' next lane, start, thread blocks finished and check-ins, and
// the block's owner, command, state, offset, step, launch time, running time, check-in and check-in time; then the
// commands and states it reads and writes
EMIT_CORE unsigned long long emit_core_unit(unsigned int at)
{
    const unsigned long long values[EMIT_CORE_UNIT_PARAMETERS] = {
        sizeof(CycleCompiledLaunch),
        offsetof(CycleCompiledLaunch, count),
        offsetof(CycleCompiledLaunch, hot),
        offsetof(CycleCompiledLaunch, block),
        offsetof(CycleCompiledLaunch, launch_number),
        offsetof(CycleCompiledLaunch, ttl),
        offsetof(CycleCompiledLaunch, checkin_every),
        offsetof(CycleHot, next_lane),
        offsetof(CycleHot, launch_start),
        offsetof(CycleHot, finished),
        offsetof(CycleHot, checkins),
        offsetof(EngineProgramBlock, owner),
        offsetof(EngineProgramBlock, command),
        offsetof(EngineProgramBlock, state),
        offsetof(EngineProgramBlock, offset),
        offsetof(EngineProgramBlock, step),
        offsetof(EngineProgramBlock, launch_time),
        offsetof(EngineProgramBlock, exectime),
        offsetof(EngineProgramBlock, checkin),
        offsetof(EngineProgramBlock, checkin_time),
        (unsigned long long)ENGINE_PROGRAM_RUN,
        (unsigned long long)ENGINE_PROGRAM_STOP,
        (unsigned long long)ENGINE_PROGRAM_DONE,
        (unsigned long long)ENGINE_PROGRAM_STOPPED,
        (unsigned long long)ENGINE_PROGRAM_YIELDED};
    return (at < EMIT_CORE_UNIT_PARAMETERS) ? values[at] : 0ull;
}

// the carry chains: the add chain, the subtract chain, and the subtract chain whose top limb leaves its borrow for
// emit_core_borrowed to read
EMIT_CORE EmitCoreChain emit_core_add_chain(void)
{
    const EmitCoreChain chain = {EMIT_FORM_ADD_ALONE, EMIT_FORM_ADD_FIRST, EMIT_FORM_ADD_MIDDLE, EMIT_FORM_ADD_LAST};
    return chain;
}

EMIT_CORE EmitCoreChain emit_core_subtract_chain(void)
{
    const EmitCoreChain chain = {EMIT_FORM_SUBTRACT_ALONE, EMIT_FORM_SUBTRACT_FIRST, EMIT_FORM_SUBTRACT_MIDDLE,
                                  EMIT_FORM_SUBTRACT_LAST};
    return chain;
}

EMIT_CORE EmitCoreChain emit_core_borrow_chain(void)
{
    const EmitCoreChain chain = {EMIT_FORM_BORROW_ALONE, EMIT_FORM_BORROW_FIRST, EMIT_FORM_BORROW_MIDDLE,
                                  EMIT_FORM_BORROW_LAST};
    return chain;
}

// the lane leaves the step being decided refused where `refused` holds, for the store of the record words it has not
// stored yet: those whose last put is this step's or a later one's
EMIT_CORE void emit_core_refuse(EmitCoreLane *lane, EmitCoreArgument refused)
{
    lane->refuses = 1u;
    emit_core_form2(lane, EMIT_FORM_REFUSE, refused, emit_core_number(lane->at));
}

// one chain laid through `limbs` limbs from the lowest: each limb of `to` is left's and right's by the chain's form
// for its place in the chain
EMIT_CORE void emit_core_chain(EmitCoreLane *lane, EmitCoreChain chain, const EmitCoreRange &to,
                               const EmitCoreRange &left, const EmitCoreRange &right, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned int form = (limbs == 1u) ? chain.alone
                                : ((at == 0u) ? chain.first : ((at == (limbs - 1u)) ? chain.last : chain.middle));
        emit_core_form3(lane, form, emit_core_at(to, at), emit_core_at(left, at), emit_core_at(right, at));
    }
}

// to = -from modulo 2^(32 limbs), the two's complement, as zero less the register
EMIT_CORE void emit_core_negate(EmitCoreLane *lane, const EmitCoreRange &to, const EmitCoreRange &from,
                                unsigned int limbs)
{
    emit_core_chain(lane, emit_core_subtract_chain(), to, emit_core_none(limbs), from, limbs);
}

// a predicate set where the borrow chain just laid borrowed past its top limb, read from the borrow it left
EMIT_CORE EmitCoreArgument emit_core_borrowed(EmitCoreLane *lane)
{
    const EmitCoreArgument borrow = emit_core_temporary(lane);
    const EmitCoreArgument borrowed = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_BORROW_READ, borrow, borrowed);
    return borrowed;
}

// a limb kept to its low `kept` bits where kept is under 32; kept is reckoned as the interpreter reckons it, in 32
// bits, wrapping
EMIT_CORE void emit_core_mask(EmitCoreLane *lane, EmitCoreArgument limb, unsigned int kept)
{
    if (kept < 32u)
    {
        emit_core_form3(lane, EMIT_FORM_WORD_AND, limb, limb, emit_core_immediate((1u << kept) - 1u));
    }
}

// to = chosen where `where` holds, else otherwise, limb by limb
EMIT_CORE void emit_core_select(EmitCoreLane *lane, const EmitCoreRange &to, const EmitCoreRange &chosen,
                                const EmitCoreRange &otherwise, EmitCoreArgument where, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        emit_core_form4(lane, EMIT_FORM_WORD_SELECT, emit_core_at(to, at), emit_core_at(chosen, at),
                        emit_core_at(otherwise, at), where);
    }
}

// a predicate set by `test`, TEST_NONZERO or TEST_ZERO, on the first `limbs` limbs or'd together
EMIT_CORE EmitCoreArgument emit_core_any(EmitCoreLane *lane, const EmitCoreRange &value, unsigned int limbs,
                                         unsigned int test)
{
    const EmitCoreArgument held = emit_core_predicate(lane);
    if (limbs == 1u)
    {
        emit_core_form2(lane, test, held, emit_core_at(value, 0u));
        return held;
    }
    const EmitCoreArgument any = emit_core_temporary(lane);
    emit_core_form3(lane, EMIT_FORM_WORD_OR, any, emit_core_at(value, 0u), emit_core_at(value, 1u));
    for (unsigned int at = 2u; at < limbs; at += 1u)
    {
        emit_core_form3(lane, EMIT_FORM_WORD_OR, any, any, emit_core_at(value, at));
    }
    emit_core_form2(lane, test, held, any);
    return held;
}

// a predicate set where any of the first `limbs` limbs is not zero, and one where every one of them is zero
EMIT_CORE EmitCoreArgument emit_core_nonzero(EmitCoreLane *lane, const EmitCoreRange &value, unsigned int limbs)
{
    return emit_core_any(lane, value, limbs, EMIT_FORM_TEST_NONZERO);
}

EMIT_CORE EmitCoreArgument emit_core_zeroed(EmitCoreLane *lane, const EmitCoreRange &value, unsigned int limbs)
{
    return emit_core_any(lane, value, limbs, EMIT_FORM_TEST_ZERO);
}

// a predicate set where bit `bit` of the register is 1
EMIT_CORE EmitCoreArgument emit_core_bit(EmitCoreLane *lane, const EmitCoreRange &value, unsigned int bit)
{
    const EmitCoreArgument held = emit_core_temporary(lane);
    const EmitCoreArgument set = emit_core_predicate(lane);
    emit_core_form3(lane, EMIT_FORM_WORD_AND, held, emit_core_at(value, bit / 32u),
                    emit_core_immediate(1u << (bit % 32u)));
    emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, set, held);
    return set;
}

// the step's sign: `held`, a register or a number, where its register is not zero, and 0 where it is
EMIT_CORE void emit_core_signed(EmitCoreLane *lane, const EmitCoreStep *at, EmitCoreArgument held)
{
    const unsigned int limbs = at->step->limbs;
    const EmitCoreArgument nonzero = emit_core_nonzero(lane, emit_core_limbs(at->place, limbs, limbs), limbs);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, emit_core_sign(at->place), held, emit_core_number(0u), nonzero);
}

// the step's sign as -1 where `negative` holds and 1 where not, and 0 where its register is zero
EMIT_CORE void emit_core_signed_negative(EmitCoreLane *lane, const EmitCoreStep *at, EmitCoreArgument negative)
{
    const EmitCoreArgument held = emit_core_temporary(lane);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, held, emit_core_minus_one(), emit_core_number(1u), negative);
    emit_core_signed(lane, at, held);
}

// word `word` of a member's atom, loaded at its first reader, and the zero register past the atom's limbs. The lane
// runs its steps in one straight line, which a refused lane leaves for good: every later reader follows the load. A
// field reads its words in order: a word the step has read already is below the one past the last it read
EMIT_CORE EmitCoreArgument emit_core_atom(EmitCoreLane *lane, unsigned int member, unsigned int word)
{
    const EmitCoreProgram *const program = lane->program;
    if (word >= program->in_limbs[member])
    {
        return emit_core_zero();
    }
    const unsigned int at = program->atom_first[member] + word;
    const EmitCoreArgument name = emit_core_register(EMIT_BANK_ATOM, at);
    if ((program->atom_reader[at] == lane->at) && (at >= lane->atom_seen))
    {
        const EmitCoreArgument address = emit_core_register(EMIT_BANK_MEMBER, member);
        emit_core_form2(lane, EMIT_FORM_GLOBAL_ASK, address, emit_core_number(4u * word));
        emit_core_form3(lane, EMIT_FORM_GLOBAL_LOAD, name, address, emit_core_number(4u * word));
    }
    lane->atom_seen = (at >= lane->atom_seen) ? (at + 1u) : lane->atom_seen;
    return name;
}

// a field, unsigned or signed, gathered as cycle_record_field gathers it: each limb its two atom words funnel-shifted,
// masked to the bits left where fewer than 32 are. A signed field whose top bit is set is negated within its bits, the
// magnitude kept and the sign -1
EMIT_CORE void emit_core_field(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->right;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = step->left + (32u * limb);
        const unsigned int shift = bit % 32u;
        const EmitCoreArgument low = emit_core_atom(lane, step->member, bit / 32u);
        if (shift == 0u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(value, limb), low);
        }
        else
        {
            const EmitCoreArgument high = emit_core_atom(lane, step->member, (bit / 32u) + 1u);
            emit_core_form4(lane, EMIT_FORM_WORD_FUNNEL_RIGHT, emit_core_at(value, limb), low, high,
                            emit_core_number(shift));
        }
        emit_core_mask(lane, emit_core_at(value, limb), bits - (32u * limb));
    }
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        emit_core_signed(lane, at, emit_core_number(1u));
        return;
    }
    const EmitCoreArgument negative = emit_core_bit(lane, value, bits - 1u);
    const EmitCoreRange negated = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, negated, value, limbs);
    emit_core_mask(lane, emit_core_at(negated, limbs - 1u), bits - (32u * (limbs - 1u)));
    emit_core_select(lane, value, negated, value, negative, limbs);
    emit_core_signed_negative(lane, at, negative);
}

// a constant's two words, every limb above them cleared, its sign known as it is written
EMIT_CORE void emit_core_constant(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        const unsigned int word = (limb == 0u) ? step->left : ((limb == 1u) ? step->right : 0u);
        emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_file(at->place + limb), emit_core_immediate(word));
    }
    const int nonzero = (step->left != 0u) || ((step->limbs > 1u) && (step->right != 0u));
    emit_core_form2(lane, EMIT_FORM_SIGN_SET, emit_core_sign(at->place), emit_core_number(nonzero ? 1u : 0u));
}

// the lane's own number, its two words and every limb above them cleared; never negative
EMIT_CORE void emit_core_own_number(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const unsigned int limbs = at->step->limbs;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreArgument lane_number = emit_core_fixed(EMIT_FIXED_LANE_NUMBER);
    if (limbs == 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_FROM_WIDE, emit_core_at(value, 0u), lane_number);
    }
    else
    {
        emit_core_form3(lane, EMIT_FORM_WIDE_UNPACK, emit_core_at(value, 0u), emit_core_at(value, 1u), lane_number);
    }
    for (unsigned int limb = 2u; limb < limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(value, limb), emit_core_number(0u));
    }
    const EmitCoreArgument counted = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_WIDE_NONZERO, counted, lane_number);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, emit_core_sign(at->place), emit_core_number(1u),
                    emit_core_number(0u), counted);
}

// the magnitude, and a sign of 1 for any register not zero
EMIT_CORE void emit_core_absolute(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const EmitCoreRange value = emit_core_limbs(at->place, step->limbs, step->limbs);
    const EmitCoreRange left = emit_core_limbs(at->left_place, step->left_limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(value, limb), emit_core_at(left, limb));
    }
    emit_core_form2(lane, EMIT_FORM_SIGN_ABSOLUTE, emit_core_sign(at->place), emit_core_sign(at->left_place));
}

// the order of two signed registers, as cycle_record_operate takes it: signs that differ order the registers alone,
// and signs that agree order them by their magnitudes, read from their difference's borrow and whether it is zero,
// times the sign. The order is the step's sign, and its low limb 1 where the registers differ
EMIT_CORE void emit_core_compare(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const EmitCoreRange difference = emit_core_temporaries(lane, width);
    emit_core_chain(lane, emit_core_borrow_chain(), difference, emit_core_limbs(at->left_place, step->left_limbs, width),
                    emit_core_limbs(at->right_place, step->right_limbs, width), width);
    const EmitCoreArgument below = emit_core_borrowed(lane);
    const EmitCoreArgument differs = emit_core_nonzero(lane, difference, width);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    const EmitCoreArgument right_sign = emit_core_sign(at->right_place);
    const EmitCoreArgument sign = emit_core_sign(at->place);
    const EmitCoreArgument order = emit_core_temporary(lane);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, order, emit_core_minus_one(), emit_core_number(1u), below);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, order, order, emit_core_number(0u), differs);
    emit_core_form3(lane, EMIT_FORM_SIGN_MULTIPLY, order, left_sign, order);
    const EmitCoreArgument greater = emit_core_predicate(lane);
    const EmitCoreArgument apart = emit_core_temporary(lane);
    emit_core_form3(lane, EMIT_FORM_TEST_SIGNED_GREATER, greater, left_sign, right_sign);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, apart, emit_core_number(1u), emit_core_minus_one(), greater);
    const EmitCoreArgument unlike = emit_core_predicate(lane);
    emit_core_form3(lane, EMIT_FORM_TEST_SIGNED_DIFFER, unlike, left_sign, right_sign);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, sign, apart, order, unlike);
    const EmitCoreRange value = emit_core_limbs(at->place, step->limbs, step->limbs);
    emit_core_form2(lane, EMIT_FORM_SIGN_ABSOLUTE, emit_core_at(value, 0u), sign);
    for (unsigned int limb = 1u; limb < step->limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(value, limb), emit_core_number(0u));
    }
}

// the sum or the difference of two signed registers, branch-free: the magnitudes' sum, their difference with its
// borrow, and that difference negated are all taken, and the signs choose among them as cycle_record_operate does.
// Signs that agree, or either one zero, add, and take the left's sign where it has one; signs that differ subtract the
// lesser magnitude from the greater, the borrow saying which is greater, and take the greater's sign
EMIT_CORE void emit_core_sum(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const unsigned int reach = (width > limbs) ? width : limbs;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    emit_core_chain(lane, emit_core_add_chain(), value, emit_core_limbs(at->left_place, step->left_limbs, limbs),
                    emit_core_limbs(at->right_place, step->right_limbs, limbs), limbs);
    // the difference runs over every limb either operand holds, and its borrow is their order
    const EmitCoreRange difference = emit_core_temporaries(lane, reach);
    emit_core_chain(lane, emit_core_borrow_chain(), difference,
                    emit_core_limbs(at->left_place, step->left_limbs, reach),
                    emit_core_limbs(at->right_place, step->right_limbs, reach), reach);
    const EmitCoreArgument below = emit_core_borrowed(lane);
    const EmitCoreRange negated = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, negated, difference, limbs);
    EmitCoreArgument addend_sign = emit_core_sign(at->right_place);
    if (step->operation == ENGINE_RECORD_DIFFERENCE)
    {
        const EmitCoreArgument turned = emit_core_temporary(lane);
        emit_core_form2(lane, EMIT_FORM_SIGN_NEGATE, turned, addend_sign);
        addend_sign = turned;
    }
    const EmitCoreArgument signs = emit_core_temporary(lane);
    const EmitCoreArgument opposed = emit_core_predicate(lane);
    emit_core_form3(lane, EMIT_FORM_SIGN_MULTIPLY, signs, left_sign, addend_sign);
    emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, opposed, signs);
    emit_core_select(lane, difference, negated, difference, below, limbs);
    emit_core_select(lane, value, difference, value, opposed, limbs);
    const EmitCoreArgument greater = emit_core_temporary(lane);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, greater, addend_sign, left_sign, below);
    const EmitCoreArgument leads = emit_core_predicate(lane);
    const EmitCoreArgument kept = emit_core_temporary(lane);
    emit_core_form3(lane, EMIT_FORM_TEST_SIGNED_DIFFER, leads, left_sign, emit_core_number(0u));
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, kept, left_sign, addend_sign, leads);
    emit_core_form4(lane, EMIT_FORM_SIGN_SELECT, greater, greater, kept, opposed);
    emit_core_signed(lane, at, greater);
}

// one schoolbook row: `value` += multiplier . right over value's `limbs`, each limb product a low and high pair on the
// carry with the row's carry added in, and the row's last carry run up the limbs above it. `carry` and `upper` are the
// row's two temporaries
EMIT_CORE void emit_core_row(EmitCoreLane *lane, const EmitCoreRange &value, EmitCoreArgument multiplier,
                             const EmitCoreRange &right, unsigned int limbs, EmitCoreArgument carry,
                             EmitCoreArgument upper)
{
    const EmitCoreArgument zero = emit_core_zero();
    const unsigned int right_limbs = right.width;
    for (unsigned int high = 0u; (high < right_limbs) && (high < limbs); high += 1u)
    {
        const EmitCoreArgument to = emit_core_at(value, high);
        emit_core_form4(lane, EMIT_FORM_PRODUCT_LOW, to, multiplier, emit_core_at(right, high), to);
        if (high == 0u)
        {
            emit_core_form3(lane, EMIT_FORM_PRODUCT_HIGH, carry, multiplier, emit_core_at(right, high));
        }
        else
        {
            emit_core_form3(lane, EMIT_FORM_PRODUCT_HIGH, upper, multiplier, emit_core_at(right, high));
            emit_core_form3(lane, EMIT_FORM_ADD_FIRST, to, to, carry);
            emit_core_form3(lane, EMIT_FORM_ADD_LAST, carry, upper, zero);
        }
    }
    if (right_limbs < limbs)
    {
        const unsigned int above = limbs - right_limbs;
        const EmitCoreRange run = emit_core_slice(value, right_limbs, above);
        emit_core_chain(lane, emit_core_add_chain(), run, run, emit_core_range(carry, 1u, above), above);
    }
}

// value = left . right truncated to value's limbs, cycle_record_product's schoolbook rows unrolled
EMIT_CORE void emit_core_multiply(EmitCoreLane *lane, const EmitCoreRange &value, const EmitCoreRange &left,
                                  const EmitCoreRange &right)
{
    const unsigned int limbs = value.width;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(value, limb), emit_core_number(0u));
    }
    const EmitCoreArgument carry = emit_core_temporary(lane);
    const EmitCoreArgument upper = emit_core_temporary(lane);
    for (unsigned int low = 0u; (low < left.width) && (low < limbs); low += 1u)
    {
        emit_core_row(lane, emit_core_slice(value, low, limbs - low), emit_core_at(left, low), right, limbs - low,
                      carry, upper);
    }
}

// the loops a lane has written, each named by its number: a label, and a branch back to it where `where` holds
EMIT_CORE EmitCoreArgument emit_core_loop_open(EmitCoreLane *lane)
{
    const EmitCoreArgument loop = emit_core_number(lane->loops);
    lane->loops += 1u;
    emit_core_form1(lane, EMIT_FORM_LOOP_LABEL, loop);
    return loop;
}

EMIT_CORE void emit_core_loop_back(EmitCoreLane *lane, EmitCoreArgument loop, EmitCoreArgument where)
{
    emit_core_form2(lane, EMIT_FORM_LOOP_BACK, loop, where);
}

// to = from shifted one bit toward the low end, the top limb's bit from 0; in place where to is from
EMIT_CORE void emit_core_halve(EmitCoreLane *lane, const EmitCoreRange &to, const EmitCoreRange &from)
{
    const unsigned int limbs = to.width;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const EmitCoreArgument high = ((at + 1u) < limbs) ? emit_core_at(from, at + 1u) : emit_core_zero();
        emit_core_form4(lane, EMIT_FORM_WORD_FUNNEL_RIGHT, emit_core_at(to, at), emit_core_at(from, at), high,
                        emit_core_number(1u));
    }
}

// to = from shifted one bit toward the high end, the low limb's bit from `below`'s top bit; in place where to is
// from, which the limbs taken from the top down allow
EMIT_CORE void emit_core_double(EmitCoreLane *lane, const EmitCoreRange &to, const EmitCoreRange &from,
                                EmitCoreArgument below)
{
    const unsigned int limbs = to.width;
    for (unsigned int at = limbs; at > 0u; at -= 1u)
    {
        const EmitCoreArgument low = (at > 1u) ? emit_core_at(from, at - 2u) : below;
        emit_core_form4(lane, EMIT_FORM_WORD_FUNNEL_RIGHT, emit_core_at(to, at - 1u), low, emit_core_at(from, at - 1u),
                        emit_core_number(31u));
    }
}

// the product truncated to the step's limbs, the operands' signs multiplied as the interpreter takes it: unrolled up
// to EMIT_LANE_PRODUCT_MOST limb products, and past it a loop of one row a pass. The loop keeps the running sum's
// limbs from the row's own limb up. Each pass adds the left's lowest limb left times the right at the same
// registers, then shifts the sum and the left down a limb, the sum's lowest limb, which no later row reaches, going
// to the top of the product's low limbs as they shift down too
EMIT_CORE void emit_core_product(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreRange left = emit_core_limbs(at->left_place, step->left_limbs, step->left_limbs);
    const EmitCoreRange right = emit_core_limbs(at->right_place, step->right_limbs, step->right_limbs);
    if (((unsigned long long)step->left_limbs * step->right_limbs) <= EMIT_LANE_PRODUCT_MOST)
    {
        emit_core_multiply(lane, value, left, right);
    }
    else
    {
        const EmitCoreArgument zero = emit_core_zero();
        const unsigned int rows = (step->left_limbs < limbs) ? step->left_limbs : limbs;
        const EmitCoreRange sum = emit_core_temporaries(lane, limbs);
        const EmitCoreRange multiplier = emit_core_temporaries(lane, rows);
        const EmitCoreRange low = emit_core_temporaries(lane, rows);
        const EmitCoreArgument count = emit_core_temporary(lane);
        const EmitCoreArgument carry = emit_core_temporary(lane);
        const EmitCoreArgument upper = emit_core_temporary(lane);
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(sum, limb), emit_core_number(0u));
        }
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(multiplier, limb), emit_core_at(left, limb));
        }
        emit_core_form2(lane, EMIT_FORM_WORD_SET, count, emit_core_immediate(rows));
        const EmitCoreArgument loop = emit_core_loop_open(lane);
        emit_core_row(lane, sum, emit_core_at(multiplier, 0u), right, limbs, carry, upper);
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(low, limb),
                            ((limb + 1u) < rows) ? emit_core_at(low, limb + 1u) : emit_core_at(sum, 0u));
        }
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(sum, limb),
                            ((limb + 1u) < limbs) ? emit_core_at(sum, limb + 1u) : zero);
        }
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(multiplier, limb),
                            ((limb + 1u) < rows) ? emit_core_at(multiplier, limb + 1u) : zero);
        }
        emit_core_form3(lane, EMIT_FORM_SUBTRACT_ALONE, count, count, emit_core_immediate(1u));
        const EmitCoreArgument going = emit_core_predicate(lane);
        emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, going, count);
        emit_core_loop_back(lane, loop, going);
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(value, limb),
                            (limb < rows) ? emit_core_at(low, limb) : emit_core_at(sum, limb - rows));
        }
    }
    emit_core_form3(lane, EMIT_FORM_SIGN_MULTIPLY, emit_core_sign(at->place), emit_core_sign(at->left_place),
                    emit_core_sign(at->right_place));
}

// a table's row: the source's low index_bits select it, and its limbs are loaded from the program's tables at
// table_offset + index . limbs, reckoned in 32 bits as the interpreter reckons it
EMIT_CORE void emit_core_table(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    lane->tables = 1u;
    const EmitCoreArgument index = emit_core_temporary(lane);
    const EmitCoreArgument source = emit_core_file(at->left_place);
    if (step->index_bits >= 32u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_COPY, index, source);
    }
    else
    {
        emit_core_form3(lane, EMIT_FORM_WORD_AND, index, source, emit_core_immediate((1u << step->index_bits) - 1u));
    }
    emit_core_form3(lane, EMIT_FORM_WORD_MULTIPLY, index, index, emit_core_immediate(step->limbs));
    emit_core_form3(lane, EMIT_FORM_ADD_ALONE, index, index, emit_core_immediate(step->table_offset));
    const EmitCoreArgument address = emit_core_wide(lane);
    emit_core_form3(lane, EMIT_FORM_WIDE_MULTIPLY_WORD, address, index, emit_core_number(4u));
    emit_core_form3(lane, EMIT_FORM_WIDE_ADD, address, emit_core_fixed(EMIT_FIXED_TABLES), address);
    const EmitCoreRange value = emit_core_limbs(at->place, step->limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_GLOBAL_ASK, address, emit_core_number(4u * limb));
        emit_core_form3(lane, EMIT_FORM_GLOBAL_LOAD, emit_core_at(value, limb), address, emit_core_number(4u * limb));
    }
    emit_core_signed(lane, at, emit_core_number(1u));
}

// the xor or the and of two registers' two's complements, each taken over the step's limbs by negating where its sign
// is negative, then read back as a magnitude: negated again where the result's sign is negative, the xor's where
// exactly one operand is and the and's where both are
EMIT_CORE void emit_core_bitwise(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreArgument left_negative = emit_core_predicate(lane);
    const EmitCoreArgument right_negative = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, left_negative, emit_core_sign(at->left_place));
    emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, right_negative, emit_core_sign(at->right_place));
    const EmitCoreRange left = emit_core_limbs(at->left_place, step->left_limbs, limbs);
    const EmitCoreRange right = emit_core_limbs(at->right_place, step->right_limbs, limbs);
    const EmitCoreRange one = emit_core_temporaries(lane, limbs);
    const EmitCoreRange other = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, one, left, limbs);
    emit_core_select(lane, one, one, left, left_negative, limbs);
    emit_core_negate(lane, other, right, limbs);
    emit_core_select(lane, other, other, right, right_negative, limbs);
    const int exclusive = (step->operation == ENGINE_RECORD_XOR);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        emit_core_form3(lane, (exclusive != 0) ? EMIT_FORM_WORD_XOR : EMIT_FORM_WORD_AND, emit_core_at(value, limb),
                        emit_core_at(one, limb), emit_core_at(other, limb));
    }
    const EmitCoreArgument negative = emit_core_predicate(lane);
    emit_core_form3(lane, (exclusive != 0) ? EMIT_FORM_PREDICATE_XOR : EMIT_FORM_PREDICATE_AND, negative,
                    left_negative, right_negative);
    const EmitCoreRange negated = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, negated, value, limbs);
    emit_core_select(lane, value, negated, value, negative, limbs);
    emit_core_signed_negative(lane, at, negative);
}

// the left register wrapped to wrap_bits of two's complement and read back signed, as cycle_record_wrap wraps it: a
// wrap wider than the step's limbs passes the register through, and any other takes its two's complement over the
// limbs, keeps the wrap's bits, and negates within them where the top one is set
EMIT_CORE void emit_core_wrap(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->wrap_bits;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreRange left = emit_core_limbs(at->left_place, step->left_limbs, limbs);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    if (bits > (32u * limbs))
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(value, limb), emit_core_at(left, limb));
        }
        emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_sign(at->place), left_sign);
        return;
    }
    const EmitCoreArgument left_negative = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, left_negative, left_sign);
    const EmitCoreRange complement = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, complement, left, limbs);
    emit_core_select(lane, value, complement, left, left_negative, limbs);
    const unsigned int kept = bits - (32u * (limbs - 1u));
    emit_core_mask(lane, emit_core_at(value, limbs - 1u), kept);
    const EmitCoreArgument negative = emit_core_bit(lane, value, bits - 1u);
    const EmitCoreRange negated = emit_core_temporaries(lane, limbs);
    emit_core_negate(lane, negated, value, limbs);
    emit_core_mask(lane, emit_core_at(negated, limbs - 1u), kept);
    emit_core_select(lane, value, negated, value, negative, limbs);
    emit_core_signed_negative(lane, at, negative);
}

// a division by a divisor of one limb, cycle_record_divide's one-limb long division unrolled from the numerator's top
// limb down: each limb's quotient word by div, and the carried remainder the limb less the quotient word times the
// divisor, which is exact in 32 bits since it is below the divisor. The numerator's zero limbs above its used ones
// divide to zero and carry nothing, as the interpreter's skipping them does. A zero divisor refuses the lane; an exact
// quotient refuses a remainder and a quotient that outgrows its register, as the inverse's multiply back does. The
// quotient's words are the step's own limbs where the step keeps them, below `kept`, and its own temporaries above
EMIT_CORE void emit_core_short_division(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreArgument divisor = emit_core_file(at->right_place);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    const EmitCoreArgument nothing = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_ZERO, nothing, divisor);
    emit_core_refuse(lane, nothing);
    const EmitCoreArgument carried = emit_core_temporary(lane);
    const EmitCoreArgument taken = emit_core_temporary(lane);
    const EmitCoreArgument wide_divisor = emit_core_wide(lane);
    const EmitCoreArgument part = emit_core_wide(lane);
    const unsigned int kept = (operation == ENGINE_RECORD_REMAINDER) ? 0u : ((limbs < left_limbs) ? limbs : left_limbs);
    const EmitCoreRange above = emit_core_temporaries(lane, left_limbs - kept);
    emit_core_form2(lane, EMIT_FORM_WIDE_FROM_WORD, wide_divisor, divisor);
    for (unsigned int word = left_limbs; word > 0u; word -= 1u)
    {
        const EmitCoreArgument numerator = emit_core_file(at->left_place + word - 1u);
        const EmitCoreArgument quotient_word = ((word - 1u) < kept) ? emit_core_at(value, word - 1u)
                                                                     : emit_core_at(above, (word - 1u) - kept);
        if (word == left_limbs)
        {
            // nothing is carried into the top limb, and its word divides alone
            emit_core_form3(lane, EMIT_FORM_WORD_DIVIDE, quotient_word, numerator, divisor);
        }
        else
        {
            emit_core_form3(lane, EMIT_FORM_WIDE_PACK, part, numerator, carried);
            emit_core_form3(lane, EMIT_FORM_WIDE_DIVIDE, part, part, wide_divisor);
            emit_core_form2(lane, EMIT_FORM_WORD_FROM_WIDE, quotient_word, part);
        }
        emit_core_form3(lane, EMIT_FORM_WORD_MULTIPLY, taken, quotient_word, divisor);
        emit_core_form3(lane, EMIT_FORM_SUBTRACT_ALONE, carried, numerator, taken);
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(value, 0u), carried);
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(value, limb), emit_core_number(0u));
        }
        emit_core_signed(lane, at, left_sign);
        return;
    }
    for (unsigned int limb = left_limbs; limb < limbs; limb += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(value, limb), emit_core_number(0u));
    }
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        const EmitCoreArgument remains = emit_core_predicate(lane);
        emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, remains, carried);
        emit_core_refuse(lane, remains);
        if (left_limbs > limbs)
        {
            // the words past the step's limbs are the temporaries above it, every one
            emit_core_refuse(lane, emit_core_nonzero(lane, above, left_limbs - limbs));
        }
    }
    const EmitCoreArgument held = emit_core_temporary(lane);
    emit_core_form3(lane, EMIT_FORM_SIGN_MULTIPLY, held, left_sign, emit_core_sign(at->right_place));
    emit_core_signed(lane, at, held);
}

// to[k] = from[k] for the limbs from spans and 0 above them
EMIT_CORE void emit_core_copy_out(EmitCoreLane *lane, const EmitCoreRange &to, const EmitCoreRange &from)
{
    for (unsigned int limb = 0u; limb < to.width; limb += 1u)
    {
        if (limb < from.width)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(to, limb), emit_core_at(from, limb));
        }
        else
        {
            emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(to, limb), emit_core_number(0u));
        }
    }
}

// a division by a divisor of more than one limb, the magnitudes' long division a bit a pass as a divider in
// hardware does it: the numerator's limbs, which become the quotient, and a rest one limb wider than the divisor are
// shifted up a bit together; the divisor is taken from the rest where it does not borrow, and the quotient's new low
// bit is 1 where it was. After 32 passes a numerator limb, the quotient and the rest are cycle_record_divide's. A zero
// divisor refuses the lane; an exact quotient refuses a rest and a quotient that outgrows its register, as the
// inverse's multiply back does
EMIT_CORE void emit_core_long_division(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const unsigned int right_limbs = step->right_limbs;
    const EmitCoreArgument zero = emit_core_zero();
    const EmitCoreRange value = emit_core_limbs(at->place, limbs, limbs);
    const EmitCoreRange divisor = emit_core_limbs(at->right_place, right_limbs, right_limbs + 1u);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    emit_core_refuse(lane, emit_core_zeroed(lane, divisor, right_limbs));
    const EmitCoreRange quotient = emit_core_temporaries(lane, left_limbs);
    const EmitCoreRange rest = emit_core_temporaries(lane, right_limbs + 1u);
    const EmitCoreRange taken = emit_core_temporaries(lane, right_limbs + 1u);
    const EmitCoreArgument count = emit_core_temporary(lane);
    const EmitCoreArgument bit = emit_core_temporary(lane);
    emit_core_copy_out(lane, quotient, emit_core_limbs(at->left_place, left_limbs, left_limbs));
    emit_core_copy_out(lane, rest, emit_core_none(0u));
    emit_core_form2(lane, EMIT_FORM_WORD_SET, count, emit_core_immediate(32u * left_limbs));
    const EmitCoreArgument loop = emit_core_loop_open(lane);
    emit_core_double(lane, rest, rest, emit_core_at(quotient, left_limbs - 1u));
    emit_core_double(lane, quotient, quotient, zero);
    emit_core_chain(lane, emit_core_borrow_chain(), taken, rest, divisor, right_limbs + 1u);
    const EmitCoreArgument below = emit_core_borrowed(lane);
    emit_core_select(lane, rest, rest, taken, below, right_limbs + 1u);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, bit, zero, emit_core_immediate(1u), below);
    emit_core_form3(lane, EMIT_FORM_WORD_OR, emit_core_at(quotient, 0u), emit_core_at(quotient, 0u), bit);
    emit_core_form3(lane, EMIT_FORM_SUBTRACT_ALONE, count, count, emit_core_immediate(1u));
    const EmitCoreArgument going = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, going, count);
    emit_core_loop_back(lane, loop, going);
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        emit_core_copy_out(lane, value, emit_core_slice(rest, 0u, right_limbs));
        emit_core_signed(lane, at, left_sign);
        return;
    }
    emit_core_copy_out(lane, value, (left_limbs > limbs) ? emit_core_slice(quotient, 0u, limbs) : quotient);
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        emit_core_refuse(lane, emit_core_nonzero(lane, rest, right_limbs));
        if (left_limbs > limbs)
        {
            emit_core_refuse(lane, emit_core_nonzero(lane, emit_core_slice(quotient, limbs, left_limbs - limbs),
                                                     left_limbs - limbs));
        }
    }
    const EmitCoreArgument held = emit_core_temporary(lane);
    emit_core_form3(lane, EMIT_FORM_SIGN_MULTIPLY, held, left_sign, emit_core_sign(at->right_place));
    emit_core_signed(lane, at, held);
}

// the gcd of the magnitudes, Stein's binary gcd, which is Euclid's gcd since the gcd is one number. While neither is
// zero, a pass halves each even one, takes the lesser from the greater and halves the difference where both are odd,
// and counts the twos both shared; the one left not zero is then shifted up by the shared twos, a bit a pass. Each
// pass is laid whole and taken only where its predicate holds: a loop the lane leaves at once changes nothing
EMIT_CORE void emit_core_gcd(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const EmitCoreArgument zero = emit_core_zero();
    const EmitCoreArgument one = emit_core_immediate(1u);
    const EmitCoreRange left = emit_core_temporaries(lane, width);
    const EmitCoreRange right = emit_core_temporaries(lane, width);
    const EmitCoreRange difference = emit_core_temporaries(lane, width);
    const EmitCoreRange turned = emit_core_temporaries(lane, width);
    const EmitCoreRange left_half = emit_core_temporaries(lane, width);
    const EmitCoreRange right_half = emit_core_temporaries(lane, width);
    const EmitCoreRange difference_half = emit_core_temporaries(lane, width);
    const EmitCoreRange turned_half = emit_core_temporaries(lane, width);
    const EmitCoreRange chosen = emit_core_temporaries(lane, width);
    const EmitCoreArgument twos = emit_core_temporary(lane);
    const EmitCoreArgument counted = emit_core_temporary(lane);
    const EmitCoreArgument left_odd = emit_core_temporary(lane);
    const EmitCoreArgument right_odd = emit_core_temporary(lane);
    const EmitCoreArgument odd = emit_core_temporary(lane);
    emit_core_copy_out(lane, left, emit_core_limbs(at->left_place, step->left_limbs, step->left_limbs));
    emit_core_copy_out(lane, right, emit_core_limbs(at->right_place, step->right_limbs, step->right_limbs));
    emit_core_form2(lane, EMIT_FORM_WORD_SET, twos, emit_core_number(0u));
    const EmitCoreArgument halving = emit_core_loop_open(lane);
    const EmitCoreArgument going = emit_core_predicate(lane);
    // the two tests are taken in the order a call's arguments were, the left's first
    const EmitCoreArgument left_going = emit_core_nonzero(lane, left, width);
    const EmitCoreArgument right_going = emit_core_nonzero(lane, right, width);
    emit_core_form3(lane, EMIT_FORM_PREDICATE_AND, going, left_going, right_going);
    emit_core_form3(lane, EMIT_FORM_WORD_AND, left_odd, emit_core_at(left, 0u), one);
    emit_core_form3(lane, EMIT_FORM_WORD_AND, right_odd, emit_core_at(right, 0u), one);
    const EmitCoreArgument left_even = emit_core_predicate(lane);
    const EmitCoreArgument right_even = emit_core_predicate(lane);
    const EmitCoreArgument both_odd = emit_core_predicate(lane);
    const EmitCoreArgument both_even = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_ZERO, left_even, left_odd);
    emit_core_form2(lane, EMIT_FORM_TEST_ZERO, right_even, right_odd);
    emit_core_form3(lane, EMIT_FORM_WORD_AND, odd, left_odd, right_odd);
    emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, both_odd, odd);
    emit_core_form3(lane, EMIT_FORM_WORD_OR, odd, left_odd, right_odd);
    emit_core_form2(lane, EMIT_FORM_TEST_ZERO, both_even, odd);
    emit_core_chain(lane, emit_core_borrow_chain(), difference, left, right, width);
    const EmitCoreArgument below = emit_core_borrowed(lane);
    emit_core_negate(lane, turned, difference, width);
    emit_core_halve(lane, left_half, left);
    emit_core_halve(lane, right_half, right);
    emit_core_halve(lane, difference_half, difference);
    emit_core_halve(lane, turned_half, turned);
    // the left: halved where even, else the halved difference where both are odd and it is not below, else itself
    emit_core_select(lane, chosen, left, difference_half, below, width);
    emit_core_select(lane, chosen, chosen, left, both_odd, width);
    emit_core_select(lane, chosen, left_half, chosen, left_even, width);
    emit_core_select(lane, left, chosen, left, going, width);
    // the right: halved where even, else the halved difference turned where both are odd and the left is below
    emit_core_select(lane, chosen, turned_half, right, below, width);
    emit_core_select(lane, chosen, chosen, right, both_odd, width);
    emit_core_select(lane, chosen, right_half, chosen, right_even, width);
    emit_core_select(lane, right, chosen, right, going, width);
    emit_core_form3(lane, EMIT_FORM_ADD_ALONE, counted, twos, one);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, counted, counted, twos, both_even);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, twos, counted, twos, going);
    emit_core_loop_back(lane, halving, going);
    // one of the two is zero, and the other is their or
    for (unsigned int limb = 0u; limb < width; limb += 1u)
    {
        emit_core_form3(lane, EMIT_FORM_WORD_OR, emit_core_at(left, limb), emit_core_at(left, limb),
                        emit_core_at(right, limb));
    }
    const EmitCoreArgument doubling = emit_core_loop_open(lane);
    const EmitCoreArgument shifting = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, shifting, twos);
    emit_core_double(lane, left_half, left, zero);
    emit_core_select(lane, left, left_half, left, shifting, width);
    emit_core_form3(lane, EMIT_FORM_SUBTRACT_ALONE, counted, twos, one);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, twos, counted, twos, shifting);
    emit_core_loop_back(lane, doubling, shifting);
    emit_core_copy_out(lane, emit_core_limbs(at->place, step->limbs, step->limbs),
                       (width > step->limbs) ? emit_core_slice(left, 0u, step->limbs) : left);
    emit_core_signed(lane, at, emit_core_number(1u));
}

// the golden ladder's band, as cycle_record_ladder counts it: a right that is not positive refuses the lane; else
// each pass multiplies the right by the next Fibonacci number and counts the rung where the multiple stays at or below
// the left's magnitude, until one does not or the rungs run out. The pass is taken only while the ladder climbs. The
// band is the register's low limb, its sign the left's
EMIT_CORE void emit_core_ladder(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int right_limbs = step->right_limbs;
    const unsigned int reach = right_limbs + 2u;
    const unsigned int width = (step->left_limbs > reach) ? step->left_limbs : reach;
    const EmitCoreArgument zero = emit_core_zero();
    const EmitCoreArgument one = emit_core_immediate(1u);
    const EmitCoreArgument left_sign = emit_core_sign(at->left_place);
    // the right's sign less 1 is negative where the sign is not positive
    const EmitCoreArgument lessened = emit_core_temporary(lane);
    const EmitCoreArgument not_positive = emit_core_predicate(lane);
    emit_core_form3(lane, EMIT_FORM_SUBTRACT_ALONE, lessened, emit_core_sign(at->right_place), one);
    emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, not_positive, lessened);
    emit_core_refuse(lane, not_positive);
    const EmitCoreRange fibonacci_lower = emit_core_temporaries(lane, 2u);
    const EmitCoreRange fibonacci_upper = emit_core_temporaries(lane, 2u);
    const EmitCoreRange fibonacci_next = emit_core_temporaries(lane, 2u);
    const EmitCoreRange reached = emit_core_temporaries(lane, reach);
    const EmitCoreRange difference = emit_core_temporaries(lane, width);
    const EmitCoreArgument band = emit_core_temporary(lane);
    const EmitCoreArgument rung = emit_core_temporary(lane);
    const EmitCoreArgument climbing = emit_core_temporary(lane);
    const EmitCoreArgument counted = emit_core_temporary(lane);
    const EmitCoreArgument moved = emit_core_temporary(lane);
    emit_core_copy_out(lane, fibonacci_lower, emit_core_none(0u));
    emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(fibonacci_upper, 0u), one);
    emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_at(fibonacci_upper, 1u), emit_core_number(0u));
    emit_core_form2(lane, EMIT_FORM_WORD_SET, band, emit_core_number(0u));
    emit_core_form2(lane, EMIT_FORM_WORD_SET, rung, one);
    emit_core_form2(lane, EMIT_FORM_WORD_SET, climbing, one);
    const EmitCoreArgument loop = emit_core_loop_open(lane);
    const EmitCoreArgument going = emit_core_predicate(lane);
    emit_core_form2(lane, EMIT_FORM_TEST_NONZERO, going, climbing);
    emit_core_multiply(lane, reached, emit_core_limbs(at->right_place, right_limbs, right_limbs), fibonacci_upper);
    emit_core_chain(lane, emit_core_borrow_chain(), difference, emit_core_limbs(at->left_place, step->left_limbs, width),
                    emit_core_range(reached.first, reach, width), width);
    const EmitCoreArgument over = emit_core_borrowed(lane);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, counted, zero, one, over);
    emit_core_form3(lane, EMIT_FORM_ADD_ALONE, moved, band, counted);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, band, moved, band, going);
    emit_core_chain(lane, emit_core_add_chain(), fibonacci_next, fibonacci_lower, fibonacci_upper, 2u);
    emit_core_select(lane, fibonacci_lower, fibonacci_upper, fibonacci_lower, going, 2u);
    emit_core_select(lane, fibonacci_upper, fibonacci_next, fibonacci_upper, going, 2u);
    emit_core_form3(lane, EMIT_FORM_ADD_ALONE, moved, rung, one);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, rung, moved, rung, going);
    // the ladder climbs on where this rung counted and the next is still below ENGINE_GOLDEN_RUNGS
    emit_core_chain(lane, emit_core_borrow_chain(), emit_core_one(moved), emit_core_one(rung),
                    emit_core_one(emit_core_immediate(ENGINE_GOLDEN_RUNGS)), 1u);
    const EmitCoreArgument within = emit_core_borrowed(lane);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, moved, counted, zero, within);
    emit_core_form4(lane, EMIT_FORM_WORD_SELECT, climbing, moved, climbing, going);
    emit_core_loop_back(lane, loop, going);
    emit_core_copy_out(lane, emit_core_limbs(at->place, step->limbs, step->limbs), emit_core_one(band));
    emit_core_signed(lane, at, left_sign);
}

// 1 where an operation's register is never negative: its put needs no two's complement
EMIT_CORE int emit_core_never_negative(unsigned int operation)
{
    return (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT)
        || (operation == ENGINE_RECORD_LANE) || (operation == ENGINE_RECORD_ABSOLUTE)
        || (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_GCD);
}

// each record word stored as the last put that lays it ends; the lane does not hold it to its end
EMIT_CORE void emit_core_store_laid(EmitCoreLane *lane, const DeviceRecordStep *step)
{
    unsigned int low = 0u;
    unsigned int high = 0u;
    emit_core_put_words(lane->program, step, &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        if (lane->program->put_last[word] == (lane->at + 1u))
        {
            emit_core_form2(lane, EMIT_FORM_RECORD_STORE, emit_core_number(4u * word),
                            emit_core_register(EMIT_BANK_OUT, word));
        }
    }
}

// the step's register laid into the record's words at out_offset, out_bits of it, as two's complement where its sign
// is negative, as cycle_put lays it; each word is the lane's own register until its last put
EMIT_CORE void emit_core_put(EmitCoreLane *lane, const EmitCoreStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int top = step->out_bits - (32u * (words - 1u));
    const unsigned int first = step->out_offset / 32u;
    const unsigned int shift = step->out_offset % 32u;
    const unsigned int out_limbs = lane->program->out_limbs;
    const EmitCoreRange held = emit_core_limbs(at->place, step->limbs, words);
    const EmitCoreRange word = emit_core_temporaries(lane, words);
    if (emit_core_never_negative(step->operation) != 0)
    {
        for (unsigned int each = 0u; each < words; each += 1u)
        {
            emit_core_form2(lane, EMIT_FORM_WORD_COPY, emit_core_at(word, each), emit_core_at(held, each));
        }
    }
    else
    {
        const EmitCoreArgument negative = emit_core_predicate(lane);
        emit_core_form2(lane, EMIT_FORM_TEST_NEGATIVE, negative, emit_core_sign(at->place));
        const EmitCoreRange negated = emit_core_temporaries(lane, words);
        emit_core_negate(lane, negated, held, words);
        emit_core_select(lane, word, negated, held, negative, words);
    }
    emit_core_mask(lane, emit_core_at(word, words - 1u), top);
    unsigned int low_word = 0u;
    unsigned int high_word = 0u;
    emit_core_put_words(lane->program, step, &low_word, &high_word);
    for (unsigned int laid = low_word; laid < high_word; laid += 1u)
    {
        if (lane->program->put_first[laid] == lane->at)
        {
            // the word's first put: its register begins here, cleared, and not at the lane's open
            emit_core_form2(lane, EMIT_FORM_WORD_SET, emit_core_register(EMIT_BANK_OUT, laid), emit_core_number(0u));
        }
    }
    const EmitCoreArgument moved = emit_core_temporary(lane);
    for (unsigned int each = 0u; each < words; each += 1u)
    {
        const unsigned int low = first + each;
        if ((low < out_limbs) && (shift == 0u))
        {
            const EmitCoreArgument record = emit_core_register(EMIT_BANK_OUT, low);
            emit_core_form3(lane, EMIT_FORM_WORD_OR, record, record, emit_core_at(word, each));
        }
        else if (low < out_limbs)
        {
            const EmitCoreArgument record = emit_core_register(EMIT_BANK_OUT, low);
            emit_core_form3(lane, EMIT_FORM_WORD_SHIFT_LEFT, moved, emit_core_at(word, each), emit_core_number(shift));
            emit_core_form3(lane, EMIT_FORM_WORD_OR, record, record, moved);
        }
        if ((shift != 0u) && ((low + 1u) < out_limbs))
        {
            const EmitCoreArgument record = emit_core_register(EMIT_BANK_OUT, low + 1u);
            emit_core_form3(lane, EMIT_FORM_WORD_SHIFT_RIGHT, moved, emit_core_at(word, each),
                            emit_core_number(32u - shift));
            emit_core_form3(lane, EMIT_FORM_WORD_OR, record, record, moved);
        }
    }
}

// one step of the lane and its put, from the loop number the step begins at, which lane->loops holds; 0 for a step the
// lane does not hold, which leaves the program to the C source. The step's temporaries, 64-bit temporaries and
// predicates are its own from 0: what it took is lane->temps and lane->wides after it; lane->refuses is 1 where it
// can leave the lane refused
EMIT_CORE int emit_core_step(EmitCoreLane *lane, unsigned int at)
{
    const EmitCoreProgram *const program = lane->program;
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    // a wrap of no bits has no top bit to read
    if (!emit_core_held(program, at) || ((operation == ENGINE_RECORD_WRAP) && (step->wrap_bits == 0u)))
    {
        return 0;
    }
    EmitCoreStep view;
    view.step = step;
    view.place = step->place;
    view.left_place = emit_core_reads_left(operation) ? program->steps[step->left].place : 0u;
    view.right_place = emit_core_reads_right(operation) ? program->steps[step->right].place : 0u;
    lane->at = at;
    lane->temps = 0u;
    lane->wides = 0u;
    lane->predicates = 0u;
    lane->refuses = 0u;
    lane->atom_seen = 0u;
    emit_core_form2(lane, EMIT_FORM_STEP_NOTE, emit_core_number(at), emit_core_number(operation));
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                     || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    if (divides && (step->right_limbs > 1u))
    {
        emit_core_long_division(lane, &view);
    }
    else if (operation == ENGINE_RECORD_GCD)
    {
        emit_core_gcd(lane, &view);
    }
    else if (operation == ENGINE_RECORD_LADDER)
    {
        emit_core_ladder(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        emit_core_field(lane, &view);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        emit_core_constant(lane, &view);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        emit_core_own_number(lane, &view);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        emit_core_absolute(lane, &view);
    }
    else if (operation == ENGINE_RECORD_COMPARE)
    {
        emit_core_compare(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE))
    {
        emit_core_sum(lane, &view);
    }
    else if (operation == ENGINE_RECORD_PRODUCT)
    {
        emit_core_product(lane, &view);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        emit_core_table(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        emit_core_bitwise(lane, &view);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        emit_core_wrap(lane, &view);
    }
    else if (divides)
    {
        emit_core_short_division(lane, &view);
    }
    else
    {
        // an operation this lane does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        emit_core_put(lane, &view);
        emit_core_store_laid(lane, step);
    }
    return 1;
}

// The lane's own forms, decided after every step from what the steps left in the lane: the most of each bank any step
// took, whether any reads the tables, and which can leave the lane refused. Each is decided in the order the lane was
// always written, the note, the lane's opening and its declarations, then its opening, its close, and where the body is
// cut, the cut, then the body's opening and the lane's end, since a construct's scratch goes on from where each bank
// stands; they are laid into the text in another order (emit_lane.cu)

// the program's note, which the text program writes from the step count it holds and the target
EMIT_CORE void emit_core_note(EmitCoreLane *lane)
{
    const EmitCoreArgument none = emit_core_zero();
    emit_core_form(lane, EMIT_FORM_PROGRAM_NOTE, 6u, emit_core_number(lane->program->step_count), none, none, none);
}

// the lane's registers, each bank as many as the lane takes
EMIT_CORE void emit_core_declare(EmitCoreLane *lane, unsigned int atoms)
{
    const EmitCoreProgram *const program = lane->program;
    if (lane->predicates_most != 0u)
    {
        emit_core_form1(lane, EMIT_FORM_DECLARE_PREDICATES, emit_core_number(lane->predicates_most));
    }
    emit_core_form0(lane, EMIT_FORM_DECLARE_FIXED_PREDICATES);
    emit_core_form1(lane, EMIT_FORM_DECLARE_FILE, emit_core_number(program->file_limbs));
    emit_core_form1(lane, EMIT_FORM_DECLARE_SIGNS, emit_core_number(program->file_limbs));
    emit_core_form1(lane, EMIT_FORM_DECLARE_OUT, emit_core_number(program->out_limbs));
    if (atoms != 0u)
    {
        emit_core_form1(lane, EMIT_FORM_DECLARE_ATOMS, emit_core_number(atoms));
    }
    emit_core_form1(lane, EMIT_FORM_DECLARE_TEMPORARIES, emit_core_number(lane->temps_most));
    emit_core_form1(lane, EMIT_FORM_DECLARE_WIDES, emit_core_number(lane->wides_most));
    emit_core_form0(lane, EMIT_FORM_DECLARE_FIXED_WORDS);
    emit_core_form0(lane, EMIT_FORM_DECLARE_FIXED_WIDES);
    emit_core_form1(lane, EMIT_FORM_DECLARE_MEMBERS, emit_core_number(ENGINE_RECORD_MEMBERS_MAX));
}

// a 64-bit field of the launch read into `to` from its offset: asked for, then taken, as a language that clocks the
// lane reads its memory a clock after it names the address
EMIT_CORE void emit_core_launch(EmitCoreLane *lane, EmitCoreArgument to, unsigned int offset)
{
    emit_core_form1(lane, EMIT_FORM_LAUNCH_ASK, emit_core_number(offset));
    emit_core_form2(lane, EMIT_FORM_LAUNCH_LOAD, to, emit_core_number(offset));
}

// the lane's opening: its launch and number, the record's words no put lays stored as 0, and each member's atom found
// as the interpreter finds it, a lane whose atom lies past its member refused before any step; then the words a
// refusal would leave unlaid stored as 0, the program's tables where `tables` is 1, and where the language holds the
// file in shared memory, its `places` there and where its signs begin after them. `refuses` is 1 for each step that can
// leave the lane refused
EMIT_CORE void emit_core_open(EmitCoreLane *lane, const unsigned int *refuses, unsigned int tables,
                              unsigned int places)
{
    const EmitCoreProgram *const program = lane->program;
    const EmitCoreArgument zero = emit_core_zero();
    const EmitCoreArgument lane_number = emit_core_fixed(EMIT_FIXED_LANE_NUMBER);
    const EmitCoreArgument record = emit_core_fixed(EMIT_FIXED_RECORD);
    const EmitCoreArgument index = emit_core_fixed(EMIT_FIXED_INDEX);
    const EmitCoreArgument body = emit_core_fixed(EMIT_FIXED_BODY);
    const EmitCoreArgument bodies = emit_core_fixed(EMIT_FIXED_BODIES);
    const EmitCoreArgument indexed = emit_core_fixed(EMIT_FIXED_INDEXED);
    const EmitCoreArgument one = emit_core_fixed(EMIT_FIXED_ONE);
    const EmitCoreArgument good = emit_core_fixed(EMIT_FIXED_GOOD);
    // the opening's own 32- and 64-bit temporaries, the first of each bank, which no step has taken yet
    const EmitCoreArgument temporary = emit_core_register(EMIT_BANK_TEMPORARY, 0u);
    const EmitCoreArgument wide = emit_core_register(EMIT_BANK_WIDE, 0u);
    // the launch's offsets are a few dozen bytes
    emit_core_form0(lane, EMIT_FORM_OPEN_LAUNCH);
    emit_core_launch(lane, record, (unsigned int)offsetof(CycleCompiledLaunch, out));
    emit_core_form1(lane, EMIT_FORM_TO_GLOBAL, record);
    emit_core_form3(lane, EMIT_FORM_WIDE_MULTIPLY, wide, lane_number, emit_core_immediate(4u * program->out_limbs));
    emit_core_form3(lane, EMIT_FORM_WIDE_ADD, record, record, wide);
    // a word no put lays is 0 on every lane, refused or not, and is stored before anything can refuse
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if (program->put_last[word] == 0u)
        {
            emit_core_form2(lane, EMIT_FORM_RECORD_STORE, emit_core_number(4u * word), zero);
        }
    }
    emit_core_launch(lane, index, (unsigned int)offsetof(CycleCompiledLaunch, index));
    emit_core_form2(lane, EMIT_FORM_TEST_WIDE_NONZERO, indexed, index);
    emit_core_form1(lane, EMIT_FORM_TO_GLOBAL, index);
    for (unsigned int member = 0u; member < program->members; member += 1u)
    {
        const EmitCoreArgument address = emit_core_register(EMIT_BANK_MEMBER, member);
        // with no index, lane i reads record i of a member, or its one record where it has one
        emit_core_launch(lane, bodies, (unsigned int)offsetof(CycleCompiledLaunch, bodies) + (8u * member));
        emit_core_form3(lane, EMIT_FORM_TEST_WIDE_EQUAL, one, bodies, emit_core_number(1u));
        emit_core_form4(lane, EMIT_FORM_WIDE_SELECT, body, emit_core_number(0u), lane_number, one);
        emit_core_form3(lane, EMIT_FORM_WIDE_MULTIPLY, wide, lane_number, emit_core_immediate(program->members));
        emit_core_form3(lane, EMIT_FORM_WIDE_ADD_UNSIGNED, wide, wide, emit_core_immediate(member));
        emit_core_form3(lane, EMIT_FORM_WIDE_SHIFT_LEFT, wide, wide, emit_core_number(2u));
        emit_core_form3(lane, EMIT_FORM_WIDE_ADD, wide, index, wide);
        emit_core_form2(lane, EMIT_FORM_GUARDED_ASK, indexed, wide);
        emit_core_form3(lane, EMIT_FORM_GUARDED_LOAD, indexed, temporary, wide);
        emit_core_form3(lane, EMIT_FORM_GUARDED_WIDEN, indexed, body, temporary);
        if (member == 0u)
        {
            emit_core_form3(lane, EMIT_FORM_TEST_WIDE_BELOW, good, body, bodies);
        }
        else
        {
            emit_core_form4(lane, EMIT_FORM_TEST_WIDE_BELOW_AND, good, body, bodies, good);
        }
        emit_core_form4(lane, EMIT_FORM_WIDE_SELECT, body, body, emit_core_number(0u), good);
        emit_core_launch(lane, address, (unsigned int)offsetof(CycleCompiledLaunch, in) + (8u * member));
        emit_core_form1(lane, EMIT_FORM_TO_GLOBAL, address);
        emit_core_form3(lane, EMIT_FORM_WIDE_MULTIPLY, wide, body, emit_core_immediate(4u * program->in_limbs[member]));
        emit_core_form3(lane, EMIT_FORM_WIDE_ADD, address, address, wide);
    }
    emit_core_form1(lane, EMIT_FORM_OPEN_REFUSED_UNLESS, good);
    // a word whose first put comes at or after a step the lane can leave refused is 0 in the record until its last put
    // stores it, and the refusal stores only the words it holds in flight
    unsigned int refusal_first = program->step_count;
    for (unsigned int at = 0u; (at < program->step_count) && (refusal_first == program->step_count); at += 1u)
    {
        refusal_first = (refuses[at] != 0u) ? at : refusal_first;
    }
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if ((program->put_last[word] != 0u) && (program->put_first[word] >= refusal_first))
        {
            emit_core_form2(lane, EMIT_FORM_RECORD_STORE, emit_core_number(4u * word), zero);
        }
    }
    if (tables != 0u)
    {
        const EmitCoreArgument table_address = emit_core_fixed(EMIT_FIXED_TABLES);
        emit_core_launch(lane, table_address, (unsigned int)offsetof(CycleCompiledLaunch, tables));
        emit_core_form1(lane, EMIT_FORM_TO_GLOBAL, table_address);
    }
    if (places != 0u)
    {
        // a word's address is its place . threads + thread, a sign's 4 places . threads + place . threads + thread
        const EmitCoreArgument sign_base = emit_core_fixed(EMIT_FIXED_SIGN_BASE);
        emit_core_form0(lane, EMIT_FORM_SHARED_OPEN);
        emit_core_form4(lane, EMIT_FORM_WORD_MULTIPLY_ADD, sign_base, emit_core_fixed(EMIT_FIXED_THREADS),
                        emit_core_immediate(4u * places), sign_base);
        emit_core_form0(lane, EMIT_FORM_SHARED_CLOSE);
    }
}

// a refused lane counted in the launch's refusals
EMIT_CORE void emit_core_count_refused(EmitCoreLane *lane)
{
    const EmitCoreArgument wide = emit_core_register(EMIT_BANK_WIDE, 0u);
    emit_core_launch(lane, wide, (unsigned int)offsetof(CycleCompiledLaunch, refused));
    emit_core_form1(lane, EMIT_FORM_TO_GLOBAL, wide);
    emit_core_form1(lane, EMIT_FORM_COUNT_ASK, wide);
    emit_core_form1(lane, EMIT_FORM_COUNT_ADD, wide);
}

// the lane's close. A lane that ran every step has stored each record word as its last put laid it, and returns. A lane
// refused leaves its record as its puts laid it before it ended, as the interpreter does: refused at the open, every
// word the steps lay is 0; refused at a step, it stores the words it holds in flight, their first put before that step
// and their last put that step or a later one. Every other word is already in the record, laid or 0
EMIT_CORE void emit_core_close(EmitCoreLane *lane, const unsigned int *refuses)
{
    const EmitCoreProgram *const program = lane->program;
    emit_core_form0(lane, EMIT_FORM_RETURN);
    emit_core_form0(lane, EMIT_FORM_LABEL_REFUSED_OPEN);
    emit_core_count_refused(lane);
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if (program->put_last[word] != 0u)
        {
            emit_core_form2(lane, EMIT_FORM_RECORD_STORE, emit_core_number(4u * word), emit_core_zero());
        }
    }
    emit_core_form0(lane, EMIT_FORM_RETURN);
    for (unsigned int at = 0u; at < program->step_count; at += 1u)
    {
        if (refuses[at] == 0u)
        {
            continue;
        }
        emit_core_form1(lane, EMIT_FORM_LABEL_REFUSED, emit_core_number(at));
        emit_core_count_refused(lane);
        for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
        {
            // put_last is 1 past the last put's step
            if ((program->put_last[word] > at) && (program->put_first[word] < at))
            {
                emit_core_form2(lane, EMIT_FORM_RECORD_STORE, emit_core_number(4u * word),
                                emit_core_register(EMIT_BANK_OUT, word));
            }
        }
        emit_core_form0(lane, EMIT_FORM_RETURN);
    }
}

// the body's opening: where it is cut, the states it was cut into, declared first; and the lane's end, its close and
// the program resident around it, the kernel or the circuit that runs a launch's lanes, which the text program writes from
// the launch's layout (emit_core_unit)
EMIT_CORE void emit_core_body_open(EmitCoreLane *lane, int cut, unsigned int states)
{
    if (cut != 0)
    {
        emit_core_form1(lane, EMIT_FORM_STATES_DECLARE, emit_core_number(states));
    }
    emit_core_form0(lane, EMIT_FORM_LANE_BODY);
}

EMIT_CORE void emit_core_end(EmitCoreLane *lane)
{
    const EmitCoreArgument none = emit_core_zero();
    emit_core_form0(lane, EMIT_FORM_LANE_CLOSE);
    emit_core_form(lane, EMIT_FORM_PROGRAM_UNIT, EMIT_CORE_UNIT_PARAMETERS, none, none, none, none);
}

// The cut: the lane's body, its opening, steps and close in the order they run, cut into states, a clock each, then the
// dispatch state, which sends a refused lane to its refusal's first state

// 1 where the form names a memory address to read, which a clocked target reads by the next state, and the memory writes
// the form makes
EMIT_CORE int emit_core_asks(unsigned int form)
{
    return (form == EMIT_FORM_LAUNCH_ASK) || (form == EMIT_FORM_GLOBAL_ASK) || (form == EMIT_FORM_GUARDED_ASK)
        || (form == EMIT_FORM_COUNT_ASK);
}

EMIT_CORE unsigned int emit_core_writes(unsigned int form)
{
    return ((form == EMIT_FORM_RECORD_STORE) || (form == EMIT_FORM_COUNT_ADD)) ? 1u : 0u;
}

// a state begun in the cut
EMIT_CORE void emit_core_state_open(EmitCoreLane *lane, EmitCoreCut *cut)
{
    emit_core_form1(lane, EMIT_FORM_STATE_OPEN, emit_core_number(cut->state));
    cut->chained = 0u;
    cut->writes = 0u;
    cut->filled = 0u;
    cut->ending = 0u;
    cut->left = 0u;
}

// the next state begun, the one before going on to it unless the lane was refused in it
EMIT_CORE void emit_core_state_next(EmitCoreLane *lane, EmitCoreCut *cut)
{
    cut->state += 1u;
    emit_core_form2(lane, EMIT_FORM_STATE_NEXT, emit_core_number(cut->state),
                    emit_core_number(EMIT_LANE_STATE_DISPATCH));
    emit_core_state_open(lane, cut);
}

// the cut begun: its first state opened. The writes a state may make are at least the one write a form makes
EMIT_CORE void emit_core_cut_open(EmitCoreLane *lane, EmitCoreCut *cut, unsigned int writes, unsigned int ports)
{
    cut->writes_most = (writes < ports) ? writes : ports;
    cut->writes_most = (cut->writes_most == 0u) ? 1u : cut->writes_most;
    cut->state = EMIT_LANE_STATE_FIRST;
    cut->most = 0u;
    cut->over = 0u;
    cut->dispatch_count = 0u;
    for (unsigned int loop = 0u; loop < cut->loop_count; loop += 1u)
    {
        cut->loop_state[loop] = EMIT_CORE_UNBEGUN;
    }
    emit_core_form1(lane, EMIT_FORM_STATE_START, emit_core_number(EMIT_LANE_STATE_FIRST));
    emit_core_state_open(lane, cut);
}

// one of the body's forms laid into the cut. A refusal's label begins a state of its own, which the dispatch state
// sends the lane to, and a loop's label begins one the loop's branch back goes back to; a form that would take the
// state past its budget or its writes, or follows one that ends a state, begins the next state, which the state before
// goes on to unless the lane was refused in it. A refusal's test and a memory read's address end their state, a loop's
// branch back ends its state going back or on by its predicate, and a return leaves the lane. A form after a return
// other than a refusal's label, or a branch back to a loop not begun, is a lane the pass cannot cut
EMIT_CORE void emit_core_cut_item(EmitCoreLane *lane, EmitCoreCut *cut, const EmitCoreItem *item)
{
    const unsigned int form = item->form;
    if ((form == EMIT_FORM_LABEL_REFUSED_OPEN) || (form == EMIT_FORM_LABEL_REFUSED))
    {
        cut->state += 1u;
        emit_core_state_open(lane, cut);
        if (cut->dispatch_count < cut->dispatch_most)
        {
            cut->dispatch_refusal[cut->dispatch_count] =
                (form == EMIT_FORM_LABEL_REFUSED_OPEN) ? emit_core_minus_one() : item->arguments[0];
            cut->dispatch_state[cut->dispatch_count] = cut->state;
        }
        lane->broken = lane->broken | ((cut->dispatch_count < cut->dispatch_most) ? 0u : 1u);
        cut->dispatch_count += 1u;
        emit_core_take(lane, item);
        return;
    }
    if (cut->left != 0u)
    {
        lane->broken = 1u;
        return;
    }
    if (form == EMIT_FORM_LOOP_LABEL)
    {
        if ((cut->ending != 0u) || (cut->filled != 0u))
        {
            emit_core_state_next(lane, cut);
        }
        const unsigned int loop = item->arguments[0].number;
        if (loop < cut->loop_count)
        {
            cut->loop_state[loop] = cut->state;
        }
        lane->broken = lane->broken | ((loop < cut->loop_count) ? 0u : 1u);
        emit_core_take(lane, item);
        return;
    }
    const unsigned int cost = cut->cost[form];
    const unsigned int writes = emit_core_writes(form);
    // a cost or a count held against its bound by subtraction, where no sum can pass 2^32
    const int full = (cost > (cut->budget - cut->chained)) || (writes > (cut->writes_most - cut->writes));
    if ((cut->ending != 0u) || ((cut->filled != 0u) && full))
    {
        emit_core_state_next(lane, cut);
    }
    cut->over += (cost > cut->budget) ? 1u : 0u;
    emit_core_take(lane, item);
    // a form alone past the budget is counted over and stays alone in its state, and the sum stays under 2^32 as well
    cut->chained = (cost > (cut->budget - cut->chained)) ? cut->budget : (cut->chained + cost);
    cut->writes += writes;
    cut->filled = 1u;
    cut->most = (cut->chained > cut->most) ? cut->chained : cut->most;
    cut->ending = ((form == EMIT_FORM_REFUSE) || (form == EMIT_FORM_OPEN_REFUSED_UNLESS) || emit_core_asks(form))
                    ? 1u
                    : 0u;
    if (form == EMIT_FORM_LOOP_BACK)
    {
        const unsigned int loop = item->arguments[0].number;
        const unsigned int begun = (loop < cut->loop_count) ? cut->loop_state[loop] : EMIT_CORE_UNBEGUN;
        if (begun == EMIT_CORE_UNBEGUN)
        {
            lane->broken = 1u;
            return;
        }
        cut->state += 1u;
        emit_core_form3(lane, EMIT_FORM_STATE_LOOP, emit_core_number(begun), item->arguments[1],
                        emit_core_number(cut->state));
        emit_core_state_open(lane, cut);
    }
    if (form == EMIT_FORM_RETURN)
    {
        emit_core_form0(lane, EMIT_FORM_STATE_EXIT);
        cut->left = 1u;
    }
}

// the cut ended: the dispatch state, which sends a refused lane to its refusal's first state. The states are cut->state
EMIT_CORE void emit_core_cut_close(EmitCoreLane *lane, EmitCoreCut *cut)
{
    emit_core_form1(lane, EMIT_FORM_STATE_OPEN, emit_core_number(EMIT_LANE_STATE_DISPATCH));
    const unsigned int held = (cut->dispatch_count < cut->dispatch_most) ? cut->dispatch_count : cut->dispatch_most;
    for (unsigned int refusal = 0u; refusal < held; refusal += 1u)
    {
        emit_core_form2(lane, EMIT_FORM_DISPATCH_TO, cut->dispatch_refusal[refusal],
                        emit_core_number(cut->dispatch_state[refusal]));
    }
}

#endif
