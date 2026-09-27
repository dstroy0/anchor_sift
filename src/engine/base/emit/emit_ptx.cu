// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_ptx.h"
#include "emit_rules.h"

#include <stddef.h>
#include <stdio.h>

#include <cstddef>
#include <initializer_list>
#include <string>
#include <vector>

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

#define CYCLE_FORM_NAMED(name_, spelling_, parameters_) CYCLE_FORM_##name_,
#define CYCLE_BANK_NAMED(name_, spelling_) CYCLE_BANK_##name_,
#define CYCLE_FIXED_NAMED(name_, spelling_) CYCLE_FIXED_##name_,

enum CycleFormName
{
    CYCLE_FORMS(CYCLE_FORM_NAMED) CYCLE_FORM_COUNT
};

enum CycleBankName
{
    CYCLE_BANKS(CYCLE_BANK_NAMED) CYCLE_BANK_COUNT
};

enum CycleFixedName
{
    CYCLE_FIXED(CYCLE_FIXED_NAMED) CYCLE_FIXED_COUNT
};

static const CycleRuleName s_cycle_form_names[CYCLE_FORM_COUNT] = {CYCLE_FORMS(CYCLE_FORM_SPELLED)};

static const CycleRuleName s_cycle_bank_names[CYCLE_BANK_COUNT] = {CYCLE_BANKS(CYCLE_BANK_SPELLED)};

static const CycleRuleName s_cycle_fixed_names[CYCLE_FIXED_COUNT] = {CYCLE_FIXED(CYCLE_FIXED_SPELLED)};

// the lane as PTX: nvJitLink assembles it against the operator block, and its header is asked of NVRTC
static const CycleRuleSchema s_cycle_ptx_schema = {"ptx.krs",          "nvjitlink",        "probe_nvrtc",
                                                   s_cycle_form_names, CYCLE_FORM_COUNT,   s_cycle_bank_names,
                                                   CYCLE_BANK_COUNT,   s_cycle_fixed_names, CYCLE_FIXED_COUNT};

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
// as CycleEmitSource::program finds it, a lane whose atom lies past its member refused before any step; then the words a
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

CycleEmitPtx::CycleEmitPtx(void) : CycleEmit(&s_cycle_ptx_schema)
{
}

CycleEmitPtx &cycle_emit_ptx(void)
{
    static CycleEmitPtx emit;
    return emit;
}

// a program's lane as PTX in ptx.krs under the header this toolkit writes, the places a thread holds in shared memory
// for the steps that call the operator block (the file's and the scratch's, 0 where no step calls), and the most words
// it holds live at once. It names the device, NVRTC and the operator block it is linked against, from `target`; empty
// where a step is one the lane does not hold, or a form was written with other arguments than it takes
std::string CycleEmitPtx::program(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                                  const std::string &header, unsigned int *places, unsigned int *live)
{
    const CycleRuleset *const rules = ready();
    if (rules == NULL)
    {
        return std::string();
    }
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
