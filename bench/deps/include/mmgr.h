/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file mmgr.h
 * @brief The embedded_types headers every module builds on.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-30
 *
 * @note Every module header includes this one. The widths, the word, the static assertion, the
 *       attribute wrappers, the dispatch layout assertions and the entry point macros all come from
 *       embedded_types, and nothing here declares an MMgr copy of any of them.
 * @note No module header is included from here. A module includes what it needs itself, and an
 *       umbrella that pulled them all in could not also be the header each of them includes.
 * @note mmgr_string_shim.h is separate. Including it changes what the <string.h> names mean, which
 *       is a decision a consumer makes for itself.
 */
#ifndef MMGR_H
#define MMGR_H

#include "embed_compiler_directives.h"
#include "embed_dispatch_layout.h"
#include "embed_types.h"

/**
 * @brief The DMA module, reached only when MMGR_ENABLE_DMA is set.
 *
 * @note memoriam_praetereo.h guards its own contents on MMGR_ENABLE_DMA as well.
 */
#if MMGR_ENABLE_DMA
#include "memoriam_praetereo/memoriam_praetereo.h"
#endif

/**
 * @brief The external memory module, reached only when MMGR_ENABLE_EXTRAM is set.
 *
 * @note memoria_externa.h guards its own contents on MMGR_ENABLE_EXTRAM as well.
 */
#if MMGR_ENABLE_EXTRAM
#include "memoria_externa/memoria_externa.h"
#endif

/**
 * @brief Alignment a caller declares its own storage at before handing those bytes to a module.
 *
 * @note Nothing under src reads it. The tests, the benches and the region-edges example are what
 *       write EMBED_ALIGN(MMGR_ALIGN_BYTES) on their arrays. The default is 16.
 * @note Has to be a power of two, which the build checks below. It reaches an alignment specifier,
 *       and one given anything else is ill-formed, so the check is here to name the knob rather than
 *       leave the diagnostic pointing at whichever array was declared with it.
 * @warning Not the alignment a locus_carcerum cell comes back at. That is MMGR_CARCER_ALIGN, which is
 *          sizeof(embed_word), and nothing asserts the two agree.
 */
#ifndef MMGR_ALIGN_BYTES

#define MMGR_ALIGN_BYTES 16u
#endif
#if (MMGR_ALIGN_BYTES < 1) || ((MMGR_ALIGN_BYTES & (MMGR_ALIGN_BYTES - 1)) != 0)
#error "MMGR_ALIGN_BYTES must be a power of two - an alignment specifier takes nothing else"
#endif

/**
 * @brief Attribute that places a pool in external memory.
 *
 * @note Named here and filled by the port. Which section a part puts external memory in is the
 *       part's business, so this library names the knob and supplies no value for it. A build
 *       defines it ahead of this header, or on the command line.
 * @note Read only by ParsMemoriaeExternum, which is declared only where MMGR_ENABLE_EXTRAM is set.
 * @warning Empty by default, and an external pool then lands wherever the linker puts an ordinary
 *          one. Nothing diagnoses that, so a build enabling external memory has to supply this.
 */
#ifndef MMGR_EXTRAM_ATTR
#define MMGR_EXTRAM_ATTR
#endif

/**
 * @brief Marks a declaration so that a reference to it fails the build, carrying a message.
 *
 * @param[in] msg_ Text the diagnostic reports, as a string literal.
 * @note Reported at the site that referenced the declaration, so the message names what a caller did
 *       rather than what the linker found. That is the whole reason to reach for it over a token: the
 *       linker names a symbol, this names the mistake.
 * @warning The diagnostic arrives only where a reference survives to the end of compilation, so what
 *          this marks has to be something nothing legitimately calls.
 * @warning Expands to nothing where EMBED_HAS_ATTRIBUTE(error) is 0. A reference then compiles and
 *          the misuse goes unreported.
 */
#if EMBED_HAS_ATTRIBUTE(error)
#define MMGR_ERROR_ATTR(msg_) __attribute__((error(msg_)))
#else
#define MMGR_ERROR_ATTR(msg_)
#endif

/**
 * @brief States which argument of an allocation entry gives the extent of what it returns.
 *
 * @param[in] arg_ One-based position of the byte count in the entry's parameter list.
 * @note Feeds the compiler's object-size analysis, which is what lets a write past the cell a caller
 *       was given be reported at the line that wrote it. Without it the returned pointer carries the
 *       extent of the pool it came out of, and a cell overrun reads as a legal access.
 * @note Costs nothing. Measured byte-identical with and without, both for a direct call and for one
 *       through a dispatch table.
 * @warning The bound survives only where the call is not folded away. An entry reached through its
 *          dispatch table keeps it; the same entry inlined at a direct call collapses to an offset
 *          into the pool and the cell-level extent is gone.
 * @warning Expands to nothing where EMBED_HAS_ATTRIBUTE(alloc_size) is 0, ignoring arg_. The
 *          diagnostics it would have raised are not raised, and nothing reports that.
 */
#if EMBED_HAS_ATTRIBUTE(alloc_size)
#define MMGR_ALLOC_SIZE(arg_) __attribute__((alloc_size(arg_)))
#else
#define MMGR_ALLOC_SIZE(arg_)
#endif

/**
 * @brief Fails the link when a pool name is declared in a second translation unit.
 *
 * @param[in] name_ Pool being declared.
 * @note An initialized object with external linkage, so two units declaring one pool name give the
 *       linker two strong definitions of this symbol and it refuses them by name. The enumerator
 *       guard cannot see across a unit boundary; this is what does.
 * @note The pool's own array stays static, so it is this token and not the bytes that collide. That
 *       keeps the storage private to its unit while the name stays answerable across all of them.
 * @warning Costs one object per pool, in .bss or .data depending on the toolchain. Fixed and small,
 *          but not nothing on a part where pools are the point.
 */
#define MMGR_PARS_TOKEN(name_) int mmgr_pars_token_##name_ = 0

/**
 * @brief Fails the build when a pool name is declared a second time.
 *
 * @param[in] name_ Pool being declared.
 * @note The enumerator is the guard. A second declaration of one name collides on it, and the
 *       compiler prints the identifier, which is why the identifier reads as the reason rather than
 *       naming a mechanism.
 * @note Two pools of one name would sit at unique addresses and the language would take them. The
 *       name is the whole of what a consumer is handed, so a name meaning internal memory in one
 *       place and external in another leaves the placement out of reach of the line that uses it,
 *       and those two differ in what a DMA engine can address and in settling time.
 * @warning One translation unit is as far as this guard reaches. The enumerator is settled while a
 *          unit is compiled, so a pool of the same name declared in a separate unit does not collide
 *          on it. Catching that one is the linker's to do, over a symbol it can see.
 */
#define MMGR_PARS_DECLARED_ONCE(name_)                                                                                 \
    enum                                                                                                               \
    {                                                                                                                  \
        name_##_declared_twice_but_a_pool_symbol_names_one_region_only = 0                                             \
    }

/**
 * @brief Fails the build when a pool is dressed a second time.
 *
 * @param[in] name_ Pool being claimed.
 * @note Emitted by whatever lays state over a pool - a cellblock, a ring, anything that writes its
 *       own records into those bytes. It sits here rather than in any one of them because the rule
 *       is the pool's and not a dresser's, and a copy in each would let the next dresser be written
 *       without one.
 * @note Keyed on the pool alone, with no dresser's name in it. Every other symbol a site emits
 *       carries the site's name, so two sites over one pool collide on nothing else and each would
 *       lay its own records over the same bytes while holding that it owned them.
 * @note Costs nothing. An enumerator emits no storage and is settled while the unit compiles.
 * @warning Says a pool is dressed once. It says nothing about the bytes being reached directly,
 *          which is a separate question with separate guards.
 */
#define MMGR_PARS_CLAIMED_ONCE(name_)                                                                                  \
    enum                                                                                                               \
    {                                                                                                                  \
        name_##_claimed_twice_but_a_pool_is_dressed_once = 0                                                           \
    }

/**
 * @brief Declares a pool of bytes in internal memory.
 *
 * @param[in] name_  Name the pool is reached by, which is also the array.
 * @param[in] bytes_ Bytes in it.
 * @note A pool is a block of bytes and nothing else. Hand it to LocusCarcerum to have it dressed as
 *       a cellblock, to mmgr_anular_init to have it dressed as a ring, or to a memor entry to work
 *       on it as the bytes it is. A pool nobody hands anywhere is a pool that exists and is unclaimed.
 * @note The count is carried as name_##_bytes as well as laid down as the array, so a consumer has
 *       the extent without deriving it. The assertion is what compares the two, and it has content
 *       only because the two are produced separately.
 * @note Aligned to MMGR_ALIGN_BYTES, which is what makes that knob the contract it is documented as
 *       rather than something every caller writes out.
 */
#define ParsMemoriaeInternae(name_, bytes_)                                                                            \
    MMGR_PARS_DECLARED_ONCE(name_);                                                                                    \
    MMGR_PARS_TOKEN(name_);                                                                                            \
    enum                                                                                                               \
    {                                                                                                                  \
        name_##_bytes = (bytes_)                                                                                       \
    };                                                                                                                 \
    EMBED_ALIGN(MMGR_ALIGN_BYTES) static uint8_t mmgr_pars_storage_##name_[bytes_];                                    \
    static const uint8_t *const name_ EMBED_UNUSED = mmgr_pars_storage_##name_;                                        \
    EMBED_STATIC_ASSERT(sizeof(mmgr_pars_storage_##name_) == name_##_bytes, #name_ " is not the size it was declared")

/**
 * @brief Declares a pool of bytes in external memory.
 *
 * @param[in] name_  Name the pool is reached by, which is also the array.
 * @param[in] bytes_ Bytes in it.
 * @note The same declaration as ParsMemoriaeInternae, carrying MMGR_EXTRAM_ATTR. Which memory a pool
 *       sits in is settled by which of the two a caller writes, and nothing afterwards inspects an
 *       address to find out.
 * @warning Declared only where MMGR_ENABLE_EXTRAM is set, so a build without external memory fails
 *          on the name rather than quietly placing the bytes internally.
 */
#if MMGR_ENABLE_EXTRAM
#define ParsMemoriaeExternum(name_, bytes_)                                                                            \
    MMGR_PARS_DECLARED_ONCE(name_);                                                                                    \
    MMGR_PARS_TOKEN(name_);                                                                                            \
    enum                                                                                                               \
    {                                                                                                                  \
        name_##_bytes = (bytes_)                                                                                       \
    };                                                                                                                 \
    EMBED_ALIGN(MMGR_ALIGN_BYTES) static uint8_t mmgr_pars_storage_##name_[bytes_] MMGR_EXTRAM_ATTR;                   \
    static const uint8_t *const name_ EMBED_UNUSED = mmgr_pars_storage_##name_;                                        \
    EMBED_STATIC_ASSERT(sizeof(mmgr_pars_storage_##name_) == name_##_bytes, #name_ " is not the size it was declared")
#endif

/**
 * @brief Runtime assertion hook, inert here.
 *
 * @param[in] cond_ Condition the caller expects to hold.
 * @param[in] msg_  String literal describing the expectation.
 * @note An expectation the library asserts is one a correct caller cannot break, so the form here
 *       pays nothing for it. It expands to a sizeof, which type checks cond_ and never evaluates it.
 * @note A build wanting a failed expectation to report and stop defines its own ahead of this
 *       header, and the guard below stands down. That is what test/support/mmgr_host_traps.h does
 *       for the checks environment, and it is where the stdio and stdlib that reporting needs live.
 * @warning Not a runtime check and cannot be read as one. A failed expectation produces no
 *          diagnostic and no trap in this form.
 * @warning cond_ must carry no side effect, since this form never evaluates it.
 */
#ifndef MMGR_ASSERT
#define MMGR_ASSERT(cond_, msg_) ((void)sizeof((cond_) ? 1 : 0), (void)0)
#endif

/**
 * @brief Stops the program on an illegal call, in every build.
 *
 * @param[in] msg_ String literal naming what was violated.
 * @note Separate from MMGR_ASSERT because the two answer different questions. MMGR_ASSERT states an
 *       expectation a correct caller cannot break, and it is inert in the build that ships. This one
 *       marks a call that is illegal to make, so it has to hold in that build too.
 * @note Reached where continuing would be worse than stopping. A release handed a prisoner from
 *       another cellblock is the case it exists for: the caller has shown it does not know which
 *       cellblock owns that memory, so its next release and its next allocation are both suspect,
 *       and on a maximum security cellblock a quiet return would leave bytes unzeroed that the
 *       caller believes were wiped.
 * @note Does not return. Every call site is written on that basis and carries no fallback after it.
 * @note What is unconditional is the stop, not the diagnostic. The form here halts and names nothing,
 *       which is what keeps this header free of libc.
 * @warning A build may define its own before including this header, and the form below is then not
 *          used. A target reporting a fault through its own handler wants that, and so does a test
 *          harness, which would otherwise hang on this form rather than failing.
 * @warning This form spins. A target without abort has no other way to stop, and a halt is what a
 *          debugger can catch.
 */
#ifndef MMGR_FATAL
// No libc here, so the trap is a halt. The cast to void discards msg_, which nothing reads on this
// arm and would otherwise be an unused argument
#define MMGR_FATAL(msg_)                                                                                               \
    do                                                                                                                 \
    {                                                                                                                  \
        (void)(msg_);                                                                                                  \
        for (;;)                                                                                                       \
        {                                                                                                              \
        }                                                                                                              \
    } while (0)
#endif

#endif
