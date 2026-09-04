/* embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_embed_compiler_directives.c
 * @brief Exercises the feature gates, the static assertion, the linkage guards, the diagnostic
 *        bracket, and each attribute wrapper the header declares.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-30
 *
 * @note This reaches <stdint.h> and not embed_types.h. The header under test declares no width of
 *       its own, and a suite that borrowed embed_types.h could fail for a defect in either one.
 * @note EMBED_NARG, EMBED_CAT and EMBED_CALL are not covered here. They are declared in
 *       embed_dispatch_layout.h, which this suite does not include, and
 *       test_embed_dispatch_layout.c exercises all three against that header.
 * @note An attribute wrapper expands to nothing where its attribute is unavailable. That costs
 *       speed or a diagnostic, never correctness. A case for one of those is guarded on
 *       EMBED_HAS_ATTRIBUTE and calls TEST_IGNORE_MESSAGE on the other arm. Unity marks the case
 *       ignored, and a case that measured nothing does not count as a pass.
 * @note Unity's generator reads case names out of the source text and does not evaluate a
 *       preprocessor conditional. No case below is defined inside an #if. A case defined inside one
 *       would be called by the runner on the arm where its definition is gone, and the suite would
 *       fail to link. The conditionals at file scope here define macros, and a case that needs a
 *       conditional puts it inside its own body.
 */
#include <stdint.h>
#include <string.h>

#include "embed_compiler_directives.h"

#include "unity.h"

/**
 * @brief Asserts EMBED_GNU_ATTRIBUTES holds a value and not only a definition.
 *
 * @note The header defines it on both arms so that #if always has a number. An arm that failed to
 *       define it would make #if evaluate 0 and switch off every attribute in a build that
 *       supports them. Nothing else diagnoses that.
 */
EMBED_STATIC_ASSERT(EMBED_GNU_ATTRIBUTES == 0 || EMBED_GNU_ATTRIBUTES == 1, "EMBED_GNU_ATTRIBUTES must be 0 or 1");

/** @brief Asserts EMBED_BIG_ENDIAN holds a value, for the reason given on EMBED_GNU_ATTRIBUTES. */
EMBED_STATIC_ASSERT(EMBED_BIG_ENDIAN == 0 || EMBED_BIG_ENDIAN == 1, "EMBED_BIG_ENDIAN must be 0 or 1");

/** @brief Asserts EMBED_FAST_UNALIGNED_LOAD holds a value, for the reason given on EMBED_GNU_ATTRIBUTES. */
EMBED_STATIC_ASSERT(EMBED_FAST_UNALIGNED_LOAD == 0 || EMBED_FAST_UNALIGNED_LOAD == 1,
                    "EMBED_FAST_UNALIGNED_LOAD must be 0 or 1");

/**
 * @brief Records what EMBED_HAS_BUILTIN evaluated to for a name no compiler defines, as 1 or 0.
 *
 * @note __has_builtin is a preprocessor operator and a case body cannot evaluate one. The #if below
 *       evaluates it and leaves a literal a case can compare against.
 * @note EMBED_HAS_BUILTIN is 0 on both of its arms for this name. __has_builtin expands to 0 for a
 *       name that is not a builtin, and the fallback arm expands to 0 whatever it is handed.
 */
#if EMBED_HAS_BUILTIN(embed_probe_not_a_builtin)
#define TEST_UNKNOWN_BUILTIN_ANSWER 1
#else

#define TEST_UNKNOWN_BUILTIN_ANSWER 0
#endif

/**
 * @brief Records what EMBED_HAS_ATTRIBUTE evaluated to for a name no compiler defines, as 1 or 0.
 *
 * @note Recorded for the reason given on TEST_UNKNOWN_BUILTIN_ANSWER.
 * @warning Only the arm where __has_attribute is defined carries a checkable value. The fallback
 *          arm expands to EMBED_GNU_ATTRIBUTES for every name it is handed. An unknown attribute is
 *          indistinguishable from a known one there. The case reading this is guarded to match.
 */
#if defined(__has_attribute)
#if EMBED_HAS_ATTRIBUTE(embed_probe_not_an_attribute)
#define TEST_UNKNOWN_ATTRIBUTE_ANSWER 1
#else
#define TEST_UNKNOWN_ATTRIBUTE_ANSWER 0
#endif
#else

#define TEST_UNKNOWN_ATTRIBUTE_ANSWER EMBED_GNU_ATTRIBUTES
#endif

/**
 * @brief A one-byte enum, declared to prove EMBED_ENUM_PACKED reaches the compiler.
 *
 * @note Its range needs a single byte, and test_a_packed_enum_takes_the_width_its_range_needs
 *       checks for that width. Without the attribute the enum takes int's width. A compiler may
 *       also accept the attribute and disregard it, and no #if distinguishes that case.
 */
typedef enum EMBED_ENUM_PACKED
{
    TEST_PACKED_ENUM_MIN = 0,   /**< Low end of the probe range. */
    TEST_PACKED_ENUM_MAX = 255, /**< High end, the largest value eight bits hold. */
} PackedEnumProbe;

/**
 * @brief A word whose alignment EMBED_ALIGN raised above its natural one.
 *
 * @note Sixteen bytes. The widest type this file declares is four bytes wide and aligns to four,
 *       and nothing else here aligns to sixteen. A reported alignment of sixteen came from the
 *       attribute.
 */
typedef uint32_t RaisedAlignmentProbe EMBED_ALIGN(16);

/**
 * @brief A word whose alignment EMBED_ALIGN lowered to one byte.
 *
 * @note embed_types.h depends on this direction. EMBED_RAW lowers a word to alignment one there.
 *       Where the attribute expands to nothing the type keeps its natural alignment, and the code
 *       still reads it from any address.
 */
typedef uint32_t LoweredAlignmentProbe EMBED_ALIGN(1);

/**
 * @brief A word carrying both halves of EMBED_RAW, readable from any address.
 *
 * @note The alignment attribute permits the address. The aliasing attribute permits reading bytes
 *       another type owns. Either one alone leaves the read undefined, and EMBED_RAW carries both.
 */
typedef uint32_t RawProbeWord EMBED_RAW;

/**
 * @brief Doubles its operand.
 *
 * @param[in] operand Value to double.
 * @return            Twice operand.
 * @note Marked EMBED_INLINE. That macro is static inline, plus the always_inline attribute where
 *       the compiler has it. A case can check that the marked definition is still a definition and
 *       that its body still runs. Whether the call was inlined is not observable from the language.
 */
EMBED_INLINE uint32_t inline_probe_doubled(uint32_t operand)
{
    return operand * 2u;
}

/**
 * @brief Quadruples its operand by calling inline_probe_doubled twice.
 *
 * @param[in] operand Value to quadruple.
 * @return            Four times operand.
 * @note Marked EMBED_FLATTEN. GCC and clang inline the bodies this function calls into it. A case
 *       checks the result here, as it does for EMBED_INLINE, and the result must not change.
 */
static EMBED_FLATTEN uint32_t flatten_probe_quadrupled(uint32_t operand)
{
    return inline_probe_doubled(inline_probe_doubled(operand));
}

/**
 * @brief Declares the weak default ahead of its definition.
 *
 * @return 7, the value a build that supplies no replacement reaches.
 * @note The attribute sits on the declaration. GCC diagnoses a weak declaration that follows its
 *       own definition, and the attribute has no effect there. Putting it first works on GCC and
 *       clang alike.
 */
EMBED_WEAK uint32_t weak_probe_default(void);

uint32_t weak_probe_default(void)
{
    return 7u;
}

EMBED_BEGIN_DECLS

/**
 * @brief Declared between the two linkage guards, to prove they leave a C declaration alone.
 *
 * @return 5, the value a case compares against to confirm the call reached this definition.
 * @note Both guards expand to nothing in C. This suite compiles as C, so the extern "C" arm is
 *       never selected here.
 */
static uint32_t guarded_probe_entry(void);

EMBED_END_DECLS

static uint32_t guarded_probe_entry(void)
{
    return 5u;
}

/**
 * @brief A table defined, marked EMBED_UNUSED, and deliberately never named again.
 *
 * @note A case that read this table would reference it, and a referenced object raises no
 *       unused-variable warning for the marker to suppress. Nothing here checks the marker at run
 *       time. The suite compiles without a diagnostic for this definition.
 */
static const uint32_t unreferenced_probe_table[] EMBED_UNUSED = {1u, 2u, 4u};

/**
 * @brief A file-scope value that test_the_diagnostic_bracket_bounds_a_suppression shadows.
 *
 * @note This object exists for that case. Shadowing an object the suite already uses would make
 *       the warning depend on what else the file declares. The case reads this value before
 *       shadowing it, and that read keeps the outer name referenced.
 */
static const uint32_t shadowed_probe_value = 11u;

/**
 * @brief Runs before each case, and has nothing to prepare.
 *
 * @note Unity calls this before every case, and a suite has to define it. Every case here reads
 *       types, macros and const objects, and none of those carries state to reset.
 */
void setUp(void)
{
}

/** @brief Runs after each case, and has nothing to release. */
void tearDown(void)
{
}

/**
 * @brief Checks that each feature gate holds one of the two values it is documented to hold.
 *
 * @note The file-scope assertions above check the same three gates at compile time. This case
 *       checks them again at run time. The suite's report then lists them alongside every other case.
 */
void test_every_feature_gate_carries_a_value_of_zero_or_one(void)
{
    TEST_ASSERT_TRUE_MESSAGE(EMBED_GNU_ATTRIBUTES == 0 || EMBED_GNU_ATTRIBUTES == 1, "EMBED_GNU_ATTRIBUTES is 0 or 1");
    TEST_ASSERT_TRUE_MESSAGE(EMBED_BIG_ENDIAN == 0 || EMBED_BIG_ENDIAN == 1, "EMBED_BIG_ENDIAN is 0 or 1");
    TEST_ASSERT_TRUE_MESSAGE(EMBED_FAST_UNALIGNED_LOAD == 0 || EMBED_FAST_UNALIGNED_LOAD == 1,
                             "EMBED_FAST_UNALIGNED_LOAD is 0 or 1");
}

/**
 * @brief Checks that the static assertion is a declaration at block scope and that the dialect is C11.
 *
 * @note The assertions above prove the file-scope form by compiling. A consumer writes the
 *       block-scope form inside a function, where the expansion plus the semicolon written at the
 *       call site has to form one valid declaration.
 * @note The header raises #error below C11. A build that reached this line is therefore C11 or
 *       later, and whichever keyword EMBED_STATIC_ASSERT expands to is available.
 */
void test_the_static_assertion_compiles_at_file_and_block_scope(void)
{
    EMBED_STATIC_ASSERT(sizeof(uint32_t) == 4u, "a block-scope assertion is a declaration like any other");

    TEST_ASSERT_TRUE_MESSAGE(__STDC_VERSION__ >= 201112L, "the dialect is C11 or later");
}

/**
 * @brief Checks that the feature tests evaluate to zero for a name no compiler defines.
 *
 * @note A feature test that returned non-zero for an invented name would return non-zero for every
 *       name. Every attribute below would then be emitted on a compiler that does not support it.
 * @note The attribute half runs only where __has_attribute is defined. The fallback arm expands to
 *       EMBED_GNU_ATTRIBUTES for every name it is handed. The header documents that as a warning
 *       on EMBED_HAS_ATTRIBUTE, and no case can find a defect there.
 */
void test_the_feature_tests_evaluate_to_zero_for_an_unknown_name(void)
{
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, TEST_UNKNOWN_BUILTIN_ANSWER, "an unknown builtin evaluates to 0");
#if defined(__has_attribute)
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, TEST_UNKNOWN_ATTRIBUTE_ANSWER, "an unknown attribute evaluates to 0");
#endif
}

/**
 * @brief Checks that EMBED_BIG_ENDIAN agrees with how the target lays a word out in memory.
 *
 * @note The byte layout is measured here independently. EMBED_BIG_ENDIAN comes from __BYTE_ORDER__,
 *       and reading that macro back would restate the derivation instead of checking it.
 * @note The first two assertions hold on every target. The header falls to 0 where the compiler
 *       defines neither __BYTE_ORDER__ nor __ORDER_BIG_ENDIAN__, and that is its documented safe
 *       direction. A big-endian part built with such a compiler is not a failure here. The third
 *       assertion is guarded on those two macros for that reason.
 */
void test_the_endian_flag_agrees_with_the_bytes_of_a_word(void)
{
    const uint32_t probe_value = 1u;
    uint8_t as_bytes[sizeof(uint32_t)];

    (void)memcpy(as_bytes, &probe_value, sizeof(as_bytes));

    const int bytes_are_big_endian = (as_bytes[sizeof(as_bytes) - 1u] == 1u);
    const int bytes_are_little_endian = (as_bytes[0] == 1u);

    TEST_ASSERT_TRUE_MESSAGE(bytes_are_big_endian || bytes_are_little_endian,
                             "the target lays a word out in one of the two orders");
    TEST_ASSERT_FALSE_MESSAGE(EMBED_BIG_ENDIAN && bytes_are_little_endian,
                              "EMBED_BIG_ENDIAN is never 1 where the low byte comes first");
#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__)
    TEST_ASSERT_EQUAL_INT_MESSAGE(EMBED_BIG_ENDIAN, bytes_are_big_endian, "EMBED_BIG_ENDIAN matches the byte layout");
#endif
}

/**
 * @brief Checks that inline_probe_doubled and flatten_probe_quadrupled compute what their bodies
 *        define.
 *
 * @note Neither attribute changes what the bodies compute. Both affect inlining and nothing else,
 *       and this case checks the two results, ten and twenty.
 */
void test_the_inline_and_flattened_helpers_run_their_bodies(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(10u, inline_probe_doubled(5u), "the inline helper doubles");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(20u, flatten_probe_quadrupled(5u), "the flattened helper quadruples");
}

/**
 * @brief Checks that a packed enum is the one byte its range needs.
 *
 * @note embed_types.h asserts the same width on its own probe enum. This case checks
 *       EMBED_ENUM_PACKED directly on a type declared here. A failure means the attribute did not
 *       reach the compiler, and every enum a consumer declares would widen to int.
 */
void test_a_packed_enum_takes_the_width_its_range_needs(void)
{
    TEST_ASSERT_EQUAL_INT_MESSAGE(255, TEST_PACKED_ENUM_MAX, "the range survives the attribute");
#if EMBED_HAS_ATTRIBUTE(packed)
    TEST_ASSERT_EQUAL_size_t_MESSAGE(1u, sizeof(PackedEnumProbe), "a packed enum is one byte");
#else
    TEST_IGNORE_MESSAGE("EMBED_HAS_ATTRIBUTE(packed) is 0 here, so EMBED_ENUM_PACKED expands to nothing");
#endif
}

/**
 * @brief Checks that the alignment attribute raises alignment and lowers it.
 *
 * @note EMBED_ALIGN is used in both directions in this library. Raising an object's alignment
 *       matters where later code assumes it. Lowering it to one is half of EMBED_RAW, and
 *       embed_types.h needs that for a read at an odd address.
 */
void test_the_alignment_attribute_raises_and_lowers(void)
{
#if EMBED_HAS_ATTRIBUTE(aligned)
    TEST_ASSERT_EQUAL_size_t_MESSAGE(16u, _Alignof(RaisedAlignmentProbe), "the raised type aligns to sixteen");
    TEST_ASSERT_EQUAL_size_t_MESSAGE(1u, _Alignof(LoweredAlignmentProbe), "the lowered type aligns to one");
#else
    TEST_IGNORE_MESSAGE("EMBED_HAS_ATTRIBUTE(aligned) is 0 here, so EMBED_ALIGN expands to nothing");
#endif
}

/**
 * @brief Checks that a word carrying EMBED_RAW reads correctly from an odd address.
 *
 * @note memcpy assembles the expectation over the same bytes. A copy through memcpy is defined at
 *       any address and does not depend on byte order.
 * @note This case is guarded on EMBED_HAS_ATTRIBUTE(aligned). Without that attribute the type is
 *       the plain word, and the read below would be undefined. Undefined behavior gives a case
 *       nothing to assert against.
 */
void test_a_raw_word_reads_from_an_odd_address(void)
{
#if EMBED_HAS_ATTRIBUTE(aligned)
    static const uint8_t bytes[sizeof(uint32_t) * 2u] = {0x11u, 0x22u, 0x33u, 0x44u, 0x55u, 0x66u, 0x77u, 0x88u};
    const RawProbeWord *const at_one = (const RawProbeWord *)(const void *)(&bytes[1]);
    uint32_t expected = 0u;

    (void)memcpy(&expected, &bytes[1], sizeof(expected));
    TEST_ASSERT_EQUAL_HEX32_MESSAGE(expected, *at_one, "a raw word at offset one matches the bytes it covers");
#else
    TEST_IGNORE_MESSAGE("EMBED_HAS_ATTRIBUTE(aligned) is 0 here, the read would be undefined");
#endif
}

/**
 * @brief Checks that the diagnostic bracket suppresses a warning and stringizes its pragma text.
 *
 * @note The inner declaration shadows shadowed_probe_value. EMBED_DIAGNOSTIC_IGNORE("-Wshadow")
 *       suppresses the warning a compiler raises for that shadowing, and the bracket keeps the
 *       suppression to those lines.
 * @note EMBED_DIAGNOSTIC_STRING is the part a case can read back. _Pragma takes a string literal,
 *       and the text EMBED_DIAGNOSTIC_IGNORE builds has to come out with the warning name still
 *       quoted inside it.
 * @note Nothing below the bracket shadows anything, and a suppression left in force would not show
 *       up in this case. It would silence the rest of the translation unit instead.
 *       EMBED_DIAGNOSTIC_PUSH and EMBED_DIAGNOSTIC_POP are written as a pair for that reason.
 */
void test_the_diagnostic_bracket_bounds_a_suppression(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(11u, shadowed_probe_value, "the outer read reaches the file-scope value");

    {
        EMBED_DIAGNOSTIC_PUSH
        EMBED_DIAGNOSTIC_IGNORE("-Wshadow")
        const uint32_t shadowed_probe_value = 3u;
        EMBED_DIAGNOSTIC_POP

        TEST_ASSERT_EQUAL_UINT_MESSAGE(3u, shadowed_probe_value, "the inner declaration shadows the outer one");
    }

    TEST_ASSERT_EQUAL_STRING_MESSAGE("GCC diagnostic ignored \"-Wpadded\"",
                                     EMBED_DIAGNOSTIC_STRING(GCC diagnostic ignored "-Wpadded"),
                                     "the whole pragma text stringizes, quotes included");
}

/**
 * @brief Checks that the weak default links as itself where nothing replaces it.
 *
 * @note This case covers one half of EMBED_WEAK. The other half is a strong definition of the same
 *       name overriding the weak one, and that needs a definition in another translation unit.
 */
void test_the_weak_default_links_as_itself(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(7u, weak_probe_default(), "the call reached the weak definition");
}

/**
 * @brief Checks that the linkage guards leave a C declaration reachable.
 *
 * @note The call below reaches this definition through the declaration between the guards. A
 *       defect in either guard would leave a stray brace, and the compiler catches that.
 */
void test_the_declaration_guards_leave_a_c_declaration_intact(void)
{
    TEST_ASSERT_EQUAL_UINT_MESSAGE(5u, guarded_probe_entry(), "the declaration between the guards is reachable");
}

/**
 * @brief Records that a definition marked EMBED_UNUSED and never referenced compiled quietly.
 *
 * @note This case passes whenever the suite builds. The marker suppresses a diagnostic, and a
 *       suppressed diagnostic leaves nothing for a case to read. Naming unreferenced_probe_table
 *       here would reference it and remove the condition the marker exists for.
 */
void test_an_unreferenced_marked_definition_compiles_quietly(void)
{
    TEST_PASS_MESSAGE("unreferenced_probe_table is defined, marked EMBED_UNUSED, and never named again");
}
