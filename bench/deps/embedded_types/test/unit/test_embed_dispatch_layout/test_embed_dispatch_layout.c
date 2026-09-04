/* embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_embed_dispatch_layout.c
 * @brief Exercises the argument count, the token paste, the compound-literal call, both entry point
 *        generators, and that each table member reaches the function it was wired to.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-31
 *
 * @note EMBED_NARG, EMBED_CAT and EMBED_CALL are declared in embed_dispatch_layout.h and are
 *       covered here. test_embed_compiler_directives.c includes embed_compiler_directives.h alone
 *       and reaches none of the three.
 * @note EMBED_TABLE_LAYOUT expands to static assertions. A table whose members sat at the wrong
 *       offsets would fail the build, and no case below would run.
 * @note A table can satisfy every offset assertion and still be wired to the wrong functions. An
 *       initializer names members, and the assertions measure positions. The cases below call
 *       through the table to catch that.
 * @note The arity family runs from one member to twenty-four. Three tables are declared below, at
 *       one, three and twenty-four members. That covers the shortest line, the longest line, and
 *       one in between.
 * @note Unity's generator reads case names out of the source text and does not evaluate a
 *       preprocessor conditional. Every case below sits at file scope with no #if around it.
 */
#include <stddef.h>

#include "embed_dispatch_layout.h"
#include "embed_types.h"

#include "unity.h"

/** @brief A value reached only by building its name from two tokens. */
#define TEST_PASTED_NAME_7 7

/** @brief The operand block the compound-literal call builds at its call site. */
typedef struct
{
    embed_index first;
    embed_index second;
    embed_index third;
} CallProbeArgs;

/**
 * @brief Sums the three members under distinct weights.
 *
 * @param[in] args Operand block built by the caller [BORROWS].
 * @return         first plus twice second plus four times third.
 * @note The weights are 1, 2 and 4. With each member set to 0 or 1, no two combinations produce
 *       the same sum.
 */
static embed_index call_probe(const CallProbeArgs *args)
{
    // The 2u and 4u operands promote the sum to unsigned int. Narrowing back to embed_index is safe
    // because every call site passes members of 0 or 1, and the sum is at most 7.
    return (embed_index)(args->first + (2u * args->second) + (4u * args->third));
}

/**
 * @brief Returns 1, the value wired into slot 0 of the probe table.
 *
 * @return 1.
 * @note The three entries return 1, 2 and 4, and no subset of those totals the same as another.
 *       test_each_member_reaches_the_function_it_names sums all three and reads the total back.
 */
static embed_index first_entry(void)
{
    return 1u;
}

/**
 * @brief Returns 2, the value wired into slot 1 of the probe table.
 *
 * @return 2.
 * @note Distinct from first_entry's 1 and third_entry's 4, for the reason given on first_entry.
 */
static embed_index second_entry(void)
{
    return 2u;
}

/**
 * @brief Returns 4, the value wired into slot 2 of the probe table.
 *
 * @return 4.
 * @note Distinct from first_entry's 1 and second_entry's 2, for the reason given on first_entry.
 */
static embed_index third_entry(void)
{
    return 4u;
}

/**
 * @brief A dispatch table of three entries, whose layout the assertion below pins.
 *
 * @note Each entry returns a distinct power of two. No two subsets of the three entries sum to the
 *       same total.
 */
typedef struct
{
    embed_index (*first)(void);
    embed_index (*second)(void);
    embed_index (*third)(void);
} ProbeTable;
EMBED_TABLE_LAYOUT(ProbeTable, first, second, third);

/**
 * @brief The table under test, wired in the order its members are declared.
 *
 * @note EMBED_TABLE_STORAGE expands to static const. EMBED_UNUSED suppresses the unused-object
 *       warning on a table nothing calls through. The cases below call through this one.
 */
EMBED_TABLE_STORAGE ProbeTable dispatch_probe_table EMBED_UNUSED = {
    .first = first_entry,
    .second = second_entry,
    .third = third_entry,
};

/**
 * @brief A table of one member, the shortest arity EMBED_TABLE_LAYOUT covers.
 *
 * @note The assertion below selects EMBED_TABLE_SLOTS_1, the one line in the family that calls
 *       EMBED_TABLE_SLOT directly instead of expanding a shorter line first. No other table here
 *       reaches it.
 * @note No object of this type is declared. EMBED_TABLE_LAYOUT asserts against the struct type, and
 *       test_the_shortest_and_longest_tables_hold_only_their_slots measures that type.
 */
typedef struct
{
    embed_index (*only_slot)(void);
} ShortestProbeTable;
EMBED_TABLE_LAYOUT(ShortestProbeTable, only_slot);

/**
 * @brief A table of twenty-four members, the longest arity EMBED_TABLE_LAYOUT covers.
 *
 * @note The assertion below selects EMBED_TABLE_SLOTS_24, the last line in the family. That line
 *       expands the other twenty-three, so this one table reaches every line in the family and
 *       every constant in EMBED_NARG.
 * @note A twenty-fifth member has no line to expand to. The header carries that limit as a warning
 *       on EMBED_TABLE_SLOTS_24, and a table that crossed it would fail the build here.
 */
typedef struct
{
    embed_index (*slot01)(void);
    embed_index (*slot02)(void);
    embed_index (*slot03)(void);
    embed_index (*slot04)(void);
    embed_index (*slot05)(void);
    embed_index (*slot06)(void);
    embed_index (*slot07)(void);
    embed_index (*slot08)(void);
    embed_index (*slot09)(void);
    embed_index (*slot10)(void);
    embed_index (*slot11)(void);
    embed_index (*slot12)(void);
    embed_index (*slot13)(void);
    embed_index (*slot14)(void);
    embed_index (*slot15)(void);
    embed_index (*slot16)(void);
    embed_index (*slot17)(void);
    embed_index (*slot18)(void);
    embed_index (*slot19)(void);
    embed_index (*slot20)(void);
    embed_index (*slot21)(void);
    embed_index (*slot22)(void);
    embed_index (*slot23)(void);
    embed_index (*slot24)(void);
} LongestProbeTable;
EMBED_TABLE_LAYOUT(LongestProbeTable, slot01, slot02, slot03, slot04, slot05, slot06, slot07, slot08, slot09, slot10,
                   slot11, slot12, slot13, slot14, slot15, slot16, slot17, slot18, slot19, slot20, slot21, slot22,
                   slot23, slot24);

/** @brief The configuration a generated entry point takes a pointer to. */
typedef struct
{
    embed_index first_operand;
    embed_index second_operand;
} EntryProbeConfig;

/**
 * @brief The context a generated entry point builds for the backend it names.
 *
 * @note The two carried members are renamed from their EntryProbeConfig counterparts. A generated
 *       entry that forwarded the wrong member would compile if the names matched across the two
 *       types, and the rename removes that.
 * @note Neither EMBED_ENTRY expansion below names omitted_member in its initializer. C zero
 *       initializes it, and both backends weight it by four. A value other than zero then changes
 *       the sum a case reads back.
 */
typedef struct
{
    embed_index carried_first;
    embed_index carried_second;
    embed_index omitted_member;
} EntryProbeContext;

/**
 * @brief The value setUp writes into recorded_weighted_sum ahead of every case.
 *
 * @note No configuration a case builds produces this sum. The largest sum either backend computes
 *       is seven, from three members of one. Reading 255 back means the void entry never reached
 *       its backend.
 */
#define ENTRY_PROBE_UNSET 255u

/**
 * @brief What the void backend last computed, or ENTRY_PROBE_UNSET where it has not run.
 *
 * @note A void entry returns nothing, and this object is what a case reads instead. setUp resets it
 *       so that one case cannot pass on a value another case left behind.
 */
static embed_index recorded_weighted_sum;

/**
 * @brief Sums the three context members under distinct weights.
 *
 * @param[in] args Context built by the generated entry point [BORROWS].
 * @return         carried_first plus twice carried_second plus four times omitted_member.
 * @note This is the backend EMBED_ENTRY names below. The weights are 1, 2 and 4, so the sum
 *       identifies exactly which members arrived set.
 */
static embed_index entry_probe_backend_weighted_sum(const EntryProbeContext *args)
{
    // The 2u and 4u operands promote the sum to unsigned int. Narrowing back to embed_index is safe
    // because every case passes members of 0 or 1, and the sum is at most 7.
    return (embed_index)(args->carried_first + (2u * args->carried_second) + (4u * args->omitted_member));
}

/**
 * @brief Stores the same weighted sum into recorded_weighted_sum and returns nothing.
 *
 * @param[in] args Context built by the generated entry point [BORROWS].
 * @note This is the backend EMBED_ENTRY_V names below. That macro emits no return, and the store
 *       here is what makes the call observable.
 */
static void entry_probe_backend_record_sum(const EntryProbeContext *args)
{
    recorded_weighted_sum = entry_probe_backend_weighted_sum(args);
}

/**
 * @brief Declares the value-returning entry point ahead of the macro that defines it.
 *
 * @param[in] args Configuration the entry forwards to its backend [BORROWS].
 * @return         What entry_probe_backend_weighted_sum computed.
 * @note EMBED_ENTRY emits a definition with external linkage. A consumer keeps this prototype in
 *       its public header, and the suite writes it here for the same reason.
 */
embed_index entry_probe_weighted_sum(const EntryProbeConfig *args);

EMBED_ENTRY(entry_probe_, entry_probe_backend_, EntryProbeContext, EntryProbeConfig, embed_index, weighted_sum,
            .carried_first = args->first_operand, .carried_second = args->second_operand)

/**
 * @brief Declares the void entry point ahead of the macro that defines it.
 *
 * @param[in] args Configuration the entry forwards to its backend [BORROWS].
 * @note Declared for the reason given on entry_probe_weighted_sum. EMBED_ENTRY_V emits the same
 *       body without the return.
 */
void entry_probe_record_sum(const EntryProbeConfig *args);

EMBED_ENTRY_V(entry_probe_, entry_probe_backend_, EntryProbeContext, EntryProbeConfig, record_sum,
              .carried_first = args->first_operand, .carried_second = args->second_operand)

/**
 * @brief Runs before each case and resets what the void backend recorded.
 *
 * @note Unity calls this before every case, and a suite has to define it. recorded_weighted_sum is
 *       the only object here a case writes to. Every other file-scope object is const.
 */
void setUp(void)
{
    recorded_weighted_sum = ENTRY_PROBE_UNSET;
}

/** @brief Runs after each case, and has nothing to release. */
void tearDown(void)
{
}

/**
 * @brief Checks that EMBED_NARG evaluates to the number of arguments it was handed.
 *
 * @note Each expectation is the literal number of items written on the same line. Deriving it from
 *       EMBED_NARG would compare the macro with itself.
 * @note The arguments are number words, and the last word on each line names the count the
 *       assertion expects. A reader checks the length without counting commas.
 * @note The five lengths are one, two, eight, twenty-three and twenty-four. One is the shortest
 *       list EMBED_NARG covers and twenty-four is the longest. Twenty-three sits one below the
 *       longest, and two and eight fall in between.
 */
void test_the_argument_count_matches_the_length_of_the_list(void)
{
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, EMBED_NARG(one), "one argument counts as one");
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, EMBED_NARG(one, two), "two arguments count as two");
    TEST_ASSERT_EQUAL_INT_MESSAGE(8, EMBED_NARG(one, two, three, four, five, six, seven, eight),
                                  "eight arguments count as eight");
    TEST_ASSERT_EQUAL_INT_MESSAGE(23,
                                  EMBED_NARG(one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve,
                                             thirteen, fourteen, fifteen, sixteen, seventeen, eighteen, nineteen,
                                             twenty, twenty_one, twenty_two, twenty_three),
                                  "twenty-three arguments count as twenty-three");
    TEST_ASSERT_EQUAL_INT_MESSAGE(24,
                                  EMBED_NARG(one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve,
                                             thirteen, fourteen, fifteen, sixteen, seventeen, eighteen, nineteen,
                                             twenty, twenty_one, twenty_two, twenty_three, twenty_four),
                                  "twenty-four arguments count as twenty-four");
}

/**
 * @brief Checks that the two-step paste joins a name to an expanded count.
 *
 * @note ## suppresses expansion of its own operands. EMBED_CAT expands its arguments first and
 *       then pastes the results. EMBED_TABLE_LAYOUT needs that order, because it pastes
 *       EMBED_NARG's count onto EMBED_TABLE_SLOTS_ to select an arity line.
 */
void test_a_macro_name_is_built_from_an_expanded_count(void)
{
    TEST_ASSERT_EQUAL_INT_MESSAGE(7, EMBED_CAT(TEST_PASTED_NAME_, 7), "a literal suffix pastes");
    TEST_ASSERT_EQUAL_INT_MESSAGE(7, EMBED_CAT(TEST_PASTED_NAME_, EMBED_NARG(one, two, three, four, five, six, seven)),
                                  "an expanded count pastes");
}

/**
 * @brief Checks that the call shape passes named members and zeroes the ones left out.
 *
 * @note C zero initializes any member a compound literal's initializer does not name. That comes
 *       from the language, and a consumer relies on it every time it omits a default.
 */
void test_the_call_passes_named_members_and_zeroes_the_rest(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(7u, EMBED_CALL(call_probe, CallProbeArgs, .first = 1u, .second = 1u, .third = 1u),
                                   "all three members arrive");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(2u, EMBED_CALL(call_probe, CallProbeArgs, .second = 1u),
                                   "an omitted member is zero");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(4u, EMBED_CALL(call_probe, CallProbeArgs, .third = 1u),
                                   "only the named member is set");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(7u, EMBED_CALL(call_probe, CallProbeArgs, 1u, 1u, 1u),
                                   "positional initializers arrive");
}

/**
 * @brief Checks that each member reaches the function it was wired to.
 *
 * @note EMBED_TABLE_LAYOUT asserts offsets on the struct type. The initializer is on the object, and
 *       naming the wrong function there changes no offset. Calling through each member catches it.
 */
void test_each_member_reaches_the_function_it_names(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(1u, dispatch_probe_table.first(), "the first member reaches its own function");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(2u, dispatch_probe_table.second(), "the second member reaches its own function");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(4u, dispatch_probe_table.third(), "the third member reaches its own function");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(
        7u, dispatch_probe_table.first() + dispatch_probe_table.second() + dispatch_probe_table.third(),
        "no two members reach the same function");
}

/**
 * @brief Checks that the slot stride matches the width of a member a table actually holds.
 *
 * @note EMBED_FUNCTION_POINTER_BYTES measures void (*)(void). Every table here holds
 *       embed_index (*)(void) instead. C does not require the two to be the same width, and every
 *       offset the family asserts would be wrong where they differ.
 * @note EMBED_TABLE_SLOT measures the offset and the stride with the same macro. A stride that was
 *       wrong for the member type would still agree with itself, and no static assertion in the
 *       header catches that.
 */
void test_the_slot_stride_is_the_width_of_a_table_member(void)
{
    TEST_ASSERT_EQUAL_size_t_MESSAGE(sizeof(embed_index (*)(void)), EMBED_FUNCTION_POINTER_BYTES,
                                     "the stride is the width of a member of the probe tables");
}

/**
 * @brief Checks that the table holds nothing but its function pointers.
 *
 * @note EMBED_TABLE_LAYOUT asserts this size at compile time. This case checks it again at run time.
 *       The suite's report then lists it alongside every other case.
 */
void test_the_table_is_exactly_its_three_pointers(void)
{
    TEST_ASSERT_EQUAL_size_t_MESSAGE(3u * EMBED_FUNCTION_POINTER_BYTES, sizeof(ProbeTable),
                                     "the table is three pointers wide");
}

/**
 * @brief Checks the two ends of the arity family against the sizes their member counts imply.
 *
 * @note The two counts are literals, one and twenty-four. Deriving either from EMBED_NARG would
 *       compare the macro with itself.
 * @note The offset of slot24 is measured as well. EMBED_TABLE_SLOTS_24 asserts that offset at
 *       compile time, and this case reads it back at run time, the same way
 *       test_the_table_is_exactly_its_three_pointers reads back a size.
 */
void test_the_shortest_and_longest_tables_hold_only_their_slots(void)
{
    TEST_ASSERT_EQUAL_size_t_MESSAGE(1u * EMBED_FUNCTION_POINTER_BYTES, sizeof(ShortestProbeTable),
                                     "the one-member table is one pointer wide");
    TEST_ASSERT_EQUAL_size_t_MESSAGE(24u * EMBED_FUNCTION_POINTER_BYTES, sizeof(LongestProbeTable),
                                     "the twenty-four-member table is twenty-four pointers wide");
    TEST_ASSERT_EQUAL_size_t_MESSAGE(23u * EMBED_FUNCTION_POINTER_BYTES, offsetof(LongestProbeTable, slot24),
                                     "the last member sits at slot twenty-three");
}

/**
 * @brief Checks that the generated value-returning entry forwards its configuration and returns
 *        what its backend computed.
 *
 * @note The entry names carried_first and carried_second in its initializer and leaves
 *       omitted_member out. The third assertion passes a configuration of zeroes. The weight of
 *       four on omitted_member would show in the sum if C had not zeroed it.
 */
void test_a_generated_entry_forwards_its_configuration_to_its_backend(void)
{
    const EntryProbeConfig both_operands = {.first_operand = 1u, .second_operand = 1u};
    const EntryProbeConfig second_operand_only = {.first_operand = 0u, .second_operand = 1u};
    const EntryProbeConfig neither_operand = {.first_operand = 0u, .second_operand = 0u};

    TEST_ASSERT_EQUAL_UINT_MESSAGE(3u, entry_probe_weighted_sum(&both_operands),
                                   "both configuration members reach the backend");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(2u, entry_probe_weighted_sum(&second_operand_only),
                                   "the second member arrives under its own weight");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(0u, entry_probe_weighted_sum(&neither_operand),
                                   "the context member the entry leaves unnamed arrives as zero");
}

/**
 * @brief Checks that the generated void entry reaches its backend.
 *
 * @note A void entry returns nothing, and recorded_weighted_sum is what the backend leaves behind.
 *       The first assertion reads the sentinel setUp wrote, which separates a backend that ran and
 *       computed zero from one that never ran at all.
 */
void test_a_generated_void_entry_reaches_its_backend(void)
{
    const EntryProbeConfig both_operands = {.first_operand = 1u, .second_operand = 1u};

    TEST_ASSERT_EQUAL_UINT_MESSAGE(ENTRY_PROBE_UNSET, recorded_weighted_sum,
                                   "setUp left the sentinel in place ahead of the call");

    entry_probe_record_sum(&both_operands);

    TEST_ASSERT_EQUAL_UINT_MESSAGE(3u, recorded_weighted_sum, "the void entry reached its backend");
}
