/* embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file embed_types.h
 * @brief The exact-width integers, the boolean, and the machine word and index types a consumer
 *        builds on.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-30
 *
 * @note Every name here is defined once. A consumer that wants its own vocabulary aliases these
 *       names. Two libraries in one build then agree on what a word is.
 * @note uint8_t is optional in C11, and a part whose byte is not eight bits has none. Porting to
 *       such a part means editing this header.
 */
#ifndef EMBED_TYPES_H
#define EMBED_TYPES_H

#include <stdint.h>

#include "embed_compiler_directives.h"

EMBED_BEGIN_DECLS

/**
 * @brief The eight-bit unsigned integer that every scan and copy walks.
 *
 * @note The assertion below pins the width. On a part whose byte is not eight bits, stdint omits
 *       uint8_t and this typedef fails before the assertion is reached.
 */
typedef uint8_t embed_u8;

/** @brief The sixteen-bit unsigned integer, pinned by the assertion below. */
typedef uint16_t embed_u16;

/** @brief The thirty-two-bit unsigned integer, pinned by the assertion below. */
typedef uint32_t embed_u32;

/** @brief The sixty-four-bit unsigned integer, pinned by the assertion below. */
typedef uint64_t embed_u64;

/**
 * @brief The eight-bit signed integer.
 *
 * @note The four signed aliases carry no assertion of their own. int8_t through int64_t are
 *       exact-width by definition in stdint. The assertion on embed_iword below holds the signed
 *       word to embed_word's size.
 */
typedef int8_t embed_i8;

/** @brief The sixteen-bit signed integer, carrying no assertion for the reason given on embed_i8. */
typedef int16_t embed_i16;

/** @brief The thirty-two-bit signed integer, carrying no assertion for the reason given on embed_i8. */
typedef int32_t embed_i32;

/** @brief The sixty-four-bit signed integer, carrying no assertion for the reason given on embed_i8. */
typedef int64_t embed_i64;

/**
 * @brief The truth value.
 *
 * @note C++ gets bool and C gets _Bool. Both are keywords, so this typedef needs no header.
 * @note <stdbool.h> is not included here. Its bool macro collides with the bool that some embedded
 *       SDKs define for themselves.
 * @note Both types normalize any nonzero value to 1 on conversion. A value crossing between a
 *       library and its caller then compares equal on either side. A plain eight-bit alias keeps
 *       the value it was given, and two true values can differ.
 */
#ifdef __cplusplus
typedef bool embed_bool;
#else

typedef _Bool embed_bool;
#endif

/**
 * @brief True, cast to embed_bool.
 *
 * @note The cast gives the macro embed_bool type. A bare 1 would have type int, and sizeof would
 *       measure it as int.
 */
#define EMBED_TRUE ((embed_bool)1)

/**
 * @brief False, cast to embed_bool.
 *
 * @note The cast gives the macro embed_bool type, for the reason given on EMBED_TRUE.
 */
#define EMBED_FALSE ((embed_bool)0)

/**
 * @brief The width of the machine word in bits, derived from the target's pointer width.
 *
 * @note UINTPTR_MAX comes from the compiler. The build supplies no width of its own here, and it
 *       cannot supply a wrong one.
 * @note A build whose register width differs from its pointer width defines this on the command
 *       line ahead of this header. x32 and ILP32-on-64 are that case. A large-model eight-bit
 *       target is another, with a pointer wider than the register that indexes with it.
 * @warning The #error arms below fire where UINTPTR_MAX is absent and where it is not 16, 32 or 64
 *          bits wide. C11 makes uintptr_t optional, so its absence is legal. Neither case is
 *          guessed at. Falling silently to the narrowest width would halve every lane on a machine
 *          that has more.
 */
#ifndef EMBED_WORD_BITS
/**
 * @brief Set to 0 where the word width was derived here, 1 where the build defined it.
 *
 * @note This header sets the flag itself. A build that overrode the width would otherwise have to
 *       set a second macro to match, and the two would drift apart.
 * @note A check that the word width matches the pointer width holds only where the derivation ran.
 *       An override means the two differ on purpose.
 * @note Both arms define this macro, so #ifdef EMBED_WORD_BITS_WAS_OVERRIDDEN is always true. Test
 *       it with #if.
 */
#define EMBED_WORD_BITS_WAS_OVERRIDDEN 0

#if !defined(UINTPTR_MAX)
#error "embed_types.h needs UINTPTR_MAX to derive the word width - define EMBED_WORD_BITS instead"
#elif UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
#define EMBED_WORD_BITS 64
#elif UINTPTR_MAX == 0xFFFFFFFFu
#define EMBED_WORD_BITS 32
#elif UINTPTR_MAX == 0xFFFFu
#define EMBED_WORD_BITS 16
#else
#error "UINTPTR_MAX is not 16, 32 or 64 bits wide - define EMBED_WORD_BITS for this target"
#endif
#else

/** @brief Set to 1 where the build defined EMBED_WORD_BITS ahead of this header. */
#define EMBED_WORD_BITS_WAS_OVERRIDDEN 1
#endif

/**
 * @brief The width of an offset or a length in bits.
 *
 * @note This is separate from the word width because an offset does not need the register's full
 *       width. A 64-bit host carrying 32-bit offsets halves what a descriptor costs.
 * @note The default is the word width at 16 bits and 32 above it. That gives 16 on a 16-bit word,
 *       32 on a 32-bit word, and 32 on a 64-bit word, so the index fits the register in all three.
 * @warning A build wanting 16-bit offsets on a wider register defines this ahead of this header.
 *          The assertion below catches an override wider than the word.
 */
#ifndef EMBED_INDEX_BITS
#if EMBED_WORD_BITS == 16
#define EMBED_INDEX_BITS 16
#else
#define EMBED_INDEX_BITS 32
#endif
#endif

/**
 * @brief The unsigned word that every lane operation runs in, EMBED_WORD_BITS wide.
 *
 * @note A consumer reasons in this register. A lane mask, a zero test and a byte count are all
 *       built to this width, so changing EMBED_WORD_BITS changes what a single operation covers.
 * @note All three arms below declare this type. The 64-bit arm carries this block because the
 *       compiler reaches it first.
 */
#if EMBED_WORD_BITS == 64
typedef embed_u64 embed_word;

/**
 * @brief The signed word, the same register as embed_word.
 *
 * @note This type carries a result that has gone negative. An unsigned word would wrap it. The
 *       assertion below holds this type to embed_word's size.
 */
typedef embed_i64 embed_iword;
#elif EMBED_WORD_BITS == 32
typedef embed_u32 embed_word;
typedef embed_i32 embed_iword;
#elif EMBED_WORD_BITS == 16
typedef embed_u16 embed_word;
typedef embed_i16 embed_iword;
#else
#error "EMBED_WORD_BITS must be 16, 32 or 64"
#endif

/**
 * @brief The index type, EMBED_INDEX_BITS wide, carrying every offset and length.
 *
 * @note This type is not size_t. size_t is as wide as the target's pointer, so the same expression
 *       would be 32-bit index arithmetic on a device and 64-bit on the host that tests it. One
 *       source would then emit different code on the two.
 * @note Both arms below declare this type. The 32-bit arm carries this block because the compiler
 *       reaches it first.
 */
#if EMBED_INDEX_BITS == 32
typedef embed_u32 embed_index;
#elif EMBED_INDEX_BITS == 16
typedef embed_u16 embed_index;
#else
#error "EMBED_INDEX_BITS must be 16 or 32"
#endif

/**
 * @brief The word again, readable from an address that is not a multiple of its width.
 *
 * @note EMBED_RAW lowers the alignment to one and permits the aliasing. Both are needed for a load
 *       through this type to be defined at any address. A load through the plain embed_word at an
 *       unaligned address stays undefined.
 * @warning Where either attribute is unavailable this type is the plain word, and reads through it
 *          are undefined. Nothing diagnoses that. The warnings on EMBED_ALIGN and EMBED_ALIAS in
 *          embed_compiler_directives.h cover the same failure.
 */
typedef embed_word embed_raw_word EMBED_RAW;

/**
 * @brief Asserts embed_u8 is exactly eight bits.
 *
 * @note A conforming stdint defines uint8_t at exactly eight bits, so this assertion guards against
 *       a stdint that does not conform.
 */
EMBED_STATIC_ASSERT(sizeof(embed_u8) == 1u, "embed_u8 must be exactly 8 bits: this target has no 8-bit type");

/** @brief Asserts embed_u16 is exactly sixteen bits. */
EMBED_STATIC_ASSERT(sizeof(embed_u16) == 2u, "embed_u16 must be exactly 16 bits");

/** @brief Asserts embed_u32 is exactly thirty-two bits. */
EMBED_STATIC_ASSERT(sizeof(embed_u32) == 4u, "embed_u32 must be exactly 32 bits");

/** @brief Asserts embed_u64 is exactly sixty-four bits. */
EMBED_STATIC_ASSERT(sizeof(embed_u64) == 8u, "embed_u64 must be exactly 64 bits");

/**
 * @brief Asserts embed_word is EMBED_WORD_BITS wide.
 *
 * @note A consumer derives every offset from this width at compile time. Nothing measures it at run
 *       time. A width that differs from what the code assumed has to fail the build.
 */
EMBED_STATIC_ASSERT(sizeof(embed_word) == EMBED_WORD_BITS / 8u, "embed_word must be exactly EMBED_WORD_BITS wide");

/** @brief Asserts embed_iword is the same size as embed_word. */
EMBED_STATIC_ASSERT(sizeof(embed_iword) == sizeof(embed_word), "the signed word must be the same register as the word");

/** @brief Asserts embed_index is EMBED_INDEX_BITS wide. */
EMBED_STATIC_ASSERT(sizeof(embed_index) == EMBED_INDEX_BITS / 8u, "embed_index must be exactly EMBED_INDEX_BITS wide");

/** @brief Asserts embed_index is no larger than embed_word. */
EMBED_STATIC_ASSERT(sizeof(embed_index) <= sizeof(embed_word), "an index must fit the register it is carried in");

/**
 * @brief A one-byte enum used only to prove EMBED_ENUM_PACKED reaches the compiler.
 *
 * @note Its range needs a single byte. An unpacked enum takes int's width, so the assertion below
 *       fails when packing is ignored.
 * @warning A failure means EMBED_ENUM_PACKED expanded to nothing, or the compiler accepted the
 *          attribute and disregarded it. No #if distinguishes those two. Every enum a consumer
 *          declares then widens to int, and any offset computed from a struct holding one is wrong.
 */
typedef enum EMBED_ENUM_PACKED
{
    EMBED_ENUM_PROBE_MIN = 0,   /**< Low end of the probe range. */
    EMBED_ENUM_PROBE_MAX = 255, /**< High end, the largest value eight bits hold. */
} EmbedEnumProbe;

/** @brief Asserts EMBED_ENUM_PACKED is honored on this enum. */
EMBED_STATIC_ASSERT(sizeof(EmbedEnumProbe) == 1,
                    "EMBED_ENUM_PACKED is not honored here, so no enum keeps its declared width "
                    "(TI: pass --small_enum)");

EMBED_END_DECLS

#endif
