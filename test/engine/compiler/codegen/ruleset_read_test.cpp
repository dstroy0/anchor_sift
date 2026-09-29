// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Every ruleset read against its code generator's schema, and the SASS ruleset's forms written out and checked
// against the machine code the cell's probes read back (engine_table.md item 11(f); sass.krs). A ruleset that lacks a
// form, holds one its schema does not name, or gives a form other parameters errors on whole, and this says which.
// The SASS checks are the probes' own findings held: each expected text below is the instruction a question's
// listing held past the frame's, with the probe's registers put back as the ruleset's parameters. A form sass.krs
// leaves empty, because no question gave it, is checked empty here, so that one written later is a change this test
// shows.
#include "c_target.h"
#include "ptx_target.h"
#include "sass_target.h"
#include "vhdl_target.h"
#include "yosys_script.h"

#include <stdio.h>

#include <string>
#include <vector>

static unsigned int s_checks;
static unsigned int s_failed;

// a ruleset a process holds, read and reported; NULL where it errored
static const Ruleset *read_ruleset(Target &target, const char *name)
{
    const Ruleset *const rules = target.ruleset(1);
    s_checks += 1u;
    s_failed += (rules == NULL) ? 1u : 0u;
    printf("  %s: %s\n", name, (rules != NULL) ? "read" : "errored");
    return rules;
}

// the scratch a construct takes, which no form checked here takes: none
static std::string no_scratch(const std::string &bank)
{
    (void)bank;
    return std::string();
}

// form `name` written with `arguments` and checked against `expected`
static void check_form(const Ruleset *rules, const char *name, const std::vector<std::string> &arguments,
                       const std::string &expected)
{
    s_checks += 1u;
    std::string text;
    const int written = (rules != NULL) && (ruleset_opcode(rules, name, arguments, no_scratch, text) != 0);
    if (!written || (text != expected))
    {
        s_failed += 1u;
        printf("  %s: wrote \"%s\", not \"%s\"\n", name, written ? text.c_str() : "", expected.c_str());
    }
}

// register `number` of `bank` checked against `expected`
static void check_register(const Ruleset *rules, const char *bank, unsigned int number, const char *expected)
{
    s_checks += 1u;
    const std::string written = (rules != NULL) ? ruleset_register(rules, bank, number) : std::string();
    if (written != expected)
    {
        s_failed += 1u;
        printf("  bank %s: register %u is \"%s\", not \"%s\"\n", bank, number, written.c_str(), expected);
    }
}

// the register every lane holds named `name` checked against `expected`
static void check_physreg(const Ruleset *rules, const char *name, const char *expected)
{
    s_checks += 1u;
    const std::string written = (rules != NULL) ? ruleset_physreg(rules, name) : std::string();
    if (written != expected)
    {
        s_failed += 1u;
        printf("  fixed %s: \"%s\", not \"%s\"\n", name, written.c_str(), expected);
    }
}

// sass.krs's registers: one file of 32-bit registers, RZ reading 0, the predicates, and the lane's fixed registers
// reserved at the file's top
static void check_sass_registers(const Ruleset *rules)
{
    check_register(rules, "temporary", 7u, "R7");
    check_register(rules, "wide", 12u, "R12");
    check_register(rules, "predicate", 2u, "P2");
    check_register(rules, "immediate", 4294967295u, "4294967295");
    check_physreg(rules, "zero", "RZ");
    check_physreg(rules, "record", "R242");
    check_physreg(rules, "ok", "P5");
}

// the 32-bit arithmetic, each form the instruction its question's listing held
static void check_sass_words(const Ruleset *rules)
{
    // add_alone, and the chain of add_first, add_middle and add_last over 96 bits
    check_form(rules, "add_alone", {"R8", "R0", "R1"}, "\tIADD3 \tR8, R0, R1, RZ;\n");
    check_form(rules, "add_first", {"R8", "R0", "R3"}, "\tIADD3 \tR8, P6, R0, R3, RZ;\n");
    check_form(rules, "add_middle", {"R9", "R1", "R4"}, "\tIADD3.X \tR9, P6, R1, R4, RZ, P6, !PT;\n");
    check_form(rules, "add_last", {"R10", "R2", "R5"}, "\tIADD3.X \tR10, R2, R5, RZ, P6, !PT;\n");
    // a subtraction adds the right's negation, and its chain takes the borrow back as ~right
    check_form(rules, "subtract_alone", {"R8", "R0", "R1"}, "\tIADD3 \tR8, R0, -R1, RZ;\n");
    check_form(rules, "subtract_middle", {"R9", "R1", "R4"}, "\tIADD3.X \tR9, P6, R1, ~R4, RZ, P6, !PT;\n");
    check_form(rules, "borrow_read", {"R9", "P0"},
               "\tIMAD.X \tR9, RZ, RZ, -0x1, P6;\n\tISETP.NE.U32.AND \tP0, PT, R9, RZ, PT;\n");
    // one LOP3 over a lookup of its three inputs: 0xc0 is a and b, 0xfc a or b, 0x3c a xor b
    check_form(rules, "word_and", {"R8", "R0", "R1"}, "\tLOP3.LUT \tR8, R0, R1, RZ, 0xc0, !PT;\n");
    check_form(rules, "word_or", {"R9", "R0", "R1"}, "\tLOP3.LUT \tR9, R0, R1, RZ, 0xfc, !PT;\n");
    check_form(rules, "word_xor", {"R10", "R0", "R1"}, "\tLOP3.LUT \tR10, R0, R1, RZ, 0x3c, !PT;\n");
    // a shift names RZ for the half of the pair it does not have, and .HI takes the result's high word
    check_form(rules, "word_shift_left", {"R8", "R0", "R1"}, "\tSHF.L.U32 \tR8, R0, R1, RZ;\n");
    check_form(rules, "word_shift_right", {"R9", "R0", "R1"}, "\tSHF.R.U32.HI \tR9, RZ, R1, R0;\n");
    check_form(rules, "word_funnel_right", {"R8", "R0", "R1", "R2"}, "\tSHF.R.U32 \tR8, R0, R2, R1;\n");
    check_form(rules, "word_multiply", {"R8", "R0", "R1"}, "\tIMAD \tR8, R0, R1, RZ;\n");
    check_form(rules, "word_multiply_add", {"R9", "R0", "R1", "R2"}, "\tIMAD \tR9, R0, R1, R2;\n");
    check_form(rules, "word_select", {"R8", "R0", "R1", "P0"}, "\tSEL \tR8, R0, R1, P0;\n");
    check_form(rules, "sign_absolute", {"R9", "R0"}, "\tIABS \tR9, R0;\n");
    check_form(rules, "sign_negate", {"R10", "R0"}, "\tIADD3 \tR10, -R0, RZ, RZ;\n");
    check_form(rules, "test_nonzero", {"P0", "R0"}, "\tISETP.NE.U32.AND \tP0, PT, R0, RZ, PT;\n");
    check_form(rules, "test_signed_greater", {"P1", "R0", "R1"}, "\tISETP.GT.AND \tP1, PT, R0, R1, PT;\n");
}

// the 64-bit forms, each two registers: the pair's high half written .hi, which sass.krs names and no listing prints
static void check_sass_wides(const Ruleset *rules)
{
    check_form(rules, "wide_pack", {"R12", "R0", "R1"}, "\tMOV \tR12, R0;\n\tMOV \tR12.hi, R1;\n");
    check_form(rules, "wide_unpack", {"R8", "R9", "R12"}, "\tMOV \tR8, R12;\n\tMOV \tR9, R12.hi;\n");
    check_form(rules, "wide_add", {"R14", "R12", "R16"},
               "\tIADD3 \tR14, P6, R12, R16, RZ;\n\tIADD3.X \tR14.hi, R12.hi, R16.hi, RZ, P6, !PT;\n");
    check_form(rules, "wide_multiply_word", {"R14", "R4", "R5"}, "\tIMAD.WIDE.U32 \tR14, R4, R5, RZ;\n");
    // the cross products are added into the high half after the pair's write, which would undo them
    check_form(rules, "wide_multiply", {"R14", "R12", "R16"},
               "\tIMAD.WIDE.U32 \tR14, R12, R16, RZ;\n\tIMAD \tR14.hi, R12.hi, R16, R14.hi;\n\tIMAD \tR14.hi, R12, "
               "R16.hi, R14.hi;\n");
    // the high half reads both halves of the value shifted, and is written before the low half overwrites it
    check_form(rules, "wide_shift_left", {"R14", "R12", "R2"},
               "\tSHF.L.U64.HI \tR14.hi, R12, R2, R12.hi;\n\tSHF.L.U32 \tR14, R12, R2, RZ;\n");
    check_form(rules, "wide_select", {"R14", "R12", "R16", "P0"},
               "\tSEL \tR14, R12, R16, P0;\n\tSEL \tR14.hi, R12.hi, R16.hi, P0;\n");
    // a wide comparison compares the low words into P6, then the high words with .EX, which takes it as its last
    // operand, and the one before it is the predicate anded into the answer
    check_form(rules, "test_wide_nonzero", {"P0", "R12"},
               "\tISETP.NE.U32.AND \tP6, PT, R12, RZ, PT;\n\tISETP.NE.U32.AND.EX \tP0, PT, R12.hi, RZ, PT, P6;\n");
    check_form(rules, "test_wide_below_and", {"P3", "R12", "R16", "P3"},
               "\tISETP.LT.U32.AND \tP6, PT, R12, R16, PT;\n\tISETP.LT.U32.AND.EX \tP3, PT, R12.hi, R16.hi, P3, P6;\n");
}

// memory, the lane's branches and its return, and the forms sass.krs leaves empty because no question gave them
static void check_sass_lane(const Ruleset *rules)
{
    check_form(rules, "global_load", {"R0", "R2", "4"}, "\tLDG.E.CONSTANT \tR0, [R2.64+4];\n");
    check_form(rules, "record_store", {"8", "R7"}, "\tSTG.E \t[R242.64+8], R7;\n");
    check_form(rules, "guarded_load", {"P3", "R7", "R12"}, "\t@P3 LDG.E.CONSTANT \tR7, [R12.64];\n");
    check_form(rules, "open_error_unless", {"P5"}, "\t@!P5 BRA \t`(.L_error_open);\n");
    check_form(rules, "error", {"P0", "3"}, "\t@P0 BRA \t`(.L_error3);\n");
    check_form(rules, "loop_back", {"2", "P0"}, "\t@P0 BRA \t`(.L_loop2);\n");
    check_form(rules, "return", {}, "\tRET.ABS.NODEC R20 0x0;\n");
    // no instruction declares a register: how many the lane holds is the ELF's
    check_form(rules, "declare_temporaries", {"12"}, "");
    // PTX's cvta.to.global left no instruction in any listing
    check_form(rules, "to_global", {"R2"}, "");
    // the part has no integer divide, and a form's text can take no scratch for the reciprocal the compiler writes
    check_form(rules, "word_divide", {"R8", "R0", "R1"}, "");
    check_form(rules, "wide_divide", {"R14", "R12", "R16"}, "");
    // SASS writes both halves of a word product with one IMAD.WIDE.U32 into an aligned pair
    check_form(rules, "product_low", {"R8", "R0", "R1", "R2"}, "");
    check_form(rules, "product_high", {"R9", "R0", "R1"}, "");
    // no question asked for an operation over predicates alone
    check_form(rules, "predicate_xor", {"P2", "P0", "P1"}, "");
    check_form(rules, "predicate_and", {"P3", "P0", "P1"}, "");
}

int main(void)
{
    printf("ruleset read test\n");
    read_ruleset(c_target(), "c.krs");
    read_ruleset(ptx_target(), "ptx.krs");
    read_ruleset(vhdl_target(), "vhdl.krs");
    read_ruleset(yosys_script(), "yosys.krs");
    const Ruleset *const sass = read_ruleset(sass_target(), "sass.krs");
    check_sass_registers(sass);
    check_sass_words(sass);
    check_sass_wides(sass);
    check_sass_lane(sass);
    printf("ruleset read test: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
