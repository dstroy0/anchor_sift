/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoria_externa.c
 * @brief Chooses between internal and external memory, and flips a two-buffer index.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @warning The whole file is compiled only when MMGR_ENABLE_EXTRAM is set.
 */
#include "memoria_externa/memoria_externa.h"

#if MMGR_ENABLE_EXTRAM

/**
 * @brief Argument type built by EMBED_CALL in the five entry points.
 *
 * @note Fields match ExternaCfg, without the const on its six figures and the one on its pingpong
 *       pointer.
 * @note exter_place reads the six figures. The four pingpong backends read pingpong alone, and
 *       EMBED_CALL zeroes the members an entry is not given.
 */
typedef struct
{
    size_t size;             /**< Bytes the caller wants to place. */
    embed_bool dma_required; /**< The bytes must be reachable by DMA. */
    size_t free_dram;        /**< Bytes still free in internal memory. */
    size_t free_psram;       /**< Bytes still free in external memory. */
    size_t psram_threshold;  /**< Size at or above which external memory is tried first. */
    size_t dram_reserve;     /**< Internal bytes that must remain free after the placement. */
    PingPong *pingpong;      /**< Pair the pingpong backends act on [BORROWS]. */
} ExterCtx;

/**
 * @brief Reports whether the request fits internal memory and still leaves the reserve.
 *
 * @param[in] args Request size and the internal memory figures [BORROWS].
 * @return         EMBED_TRUE when the bytes fit and dram_reserve would still be free afterwards.
 * @note Tests the size first, so the subtraction that follows cannot wrap.
 * @note dram_reserve is taken as given. A reserve above free_dram refuses every request, size 0
 *       included. A reserve equal to it admits only a size of 0.
 */
EMBED_INLINE embed_bool exter_dram_fits(const ExterCtx *args)
{
    // Two tests in order: the first is what makes the subtraction in the second safe, since && stops
    // at the first that fails and a size past free_dram would otherwise wrap it
    return (args->size <= args->free_dram) && ((args->free_dram - args->size) >= args->dram_reserve);
}

/**
 * @brief Reports whether the request fits external memory.
 *
 * @param[in] args Request size and the external memory figure [BORROWS].
 * @return         EMBED_TRUE when the bytes fit.
 * @note A single comparison, where exter_dram_fits also checks dram_reserve.
 */
EMBED_INLINE embed_bool exter_psram_fits(const ExterCtx *args)
{
    return args->size <= args->free_psram;
}

/**
 * @brief Decides where a request should be placed.
 *
 * @param[in] args Request size, the DMA requirement and both memory figures [BORROWS].
 * @return         PLACE_DRAM, PLACE_PSRAM, or PLACE_FAIL when neither will take it.
 * @note A size of 0 is refused outright.
 * @note A DMA request only ever goes to internal memory, and fails rather than falling back.
 * @note At or above psram_threshold external memory is tried first, below it internal is. On both
 *       paths the other is tried second, so a non-zero request without the DMA requirement reaches
 *       PLACE_FAIL only when it fits neither.
 * @note Both fit tests are taken once, above the branches, so no arm evaluates one twice.
 * @warning The two tests are not the same shape. Internal placement must also leave dram_reserve
 *          free, where the external one is a size comparison alone.
 */
EMBED_INLINE mmgr_place exter_place(const ExterCtx *args)
{
    if (args->size == 0)
    {
        return PLACE_FAIL;
    }

    const embed_bool dram_fits = exter_dram_fits(args);
    const embed_bool psram_fits = exter_psram_fits(args);

    if (args->dma_required)
    {
        return dram_fits ? PLACE_DRAM : PLACE_FAIL;
    }

    if (args->size >= args->psram_threshold)
    {
        if (psram_fits)
        {
            return PLACE_PSRAM;
        }
        if (dram_fits)
        {
            return PLACE_DRAM;
        }
        return PLACE_FAIL;
    }

    if (dram_fits)
    {
        return PLACE_DRAM;
    }
    if (psram_fits)
    {
        return PLACE_PSRAM;
    }
    return PLACE_FAIL;
}

/**
 * @brief Points the pair at buffer 0.
 *
 * @param[in,out] args Pair to reset, as args->pingpong [BORROWS].
 * @note The store below is what puts fill_index in range. The other three backends read it as it
 *       stands.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it, and the
 *          store below goes through it at once.
 */
EMBED_INLINE void exter_pingpong_init(const ExterCtx *args)
{
    args->pingpong->fill_index = 0;
}

/**
 * @brief Returns the index of the buffer currently being filled.
 *
 * @param[in] args Pair to read, as args->pingpong [BORROWS].
 * @return         0 or 1.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning Hands back fill_index as it stands. It is 0 or 1 on a pair exter_pingpong_init has set,
 *          and whatever the storage held on one that has not been.
 */
EMBED_INLINE uint8_t exter_pingpong_fill_index(const ExterCtx *args)
{
    return args->pingpong->fill_index;
}

/**
 * @brief Returns the index of the buffer currently being drained.
 *
 * @param[in] args Pair to read, as args->pingpong [BORROWS].
 * @return         The other index, 0 or 1.
 * @note Flips the low bit of fill_index rather than keeping a second member, so the two indexes
 *       cannot drift apart.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning The answer is an index only while fill_index is 0 or 1. On a pair exter_pingpong_init has
 *          not set it is the flip of whatever the storage held.
 */
EMBED_INLINE uint8_t exter_pingpong_drain_index(const ExterCtx *args)
{
    // Explicit cast keeps the result in uint8_t after the exclusive or promotes to int
    return (uint8_t)(args->pingpong->fill_index ^ 1u);
}

/**
 * @brief Swaps the two roles and returns the new fill index.
 *
 * @param[in,out] args Pair to flip, as args->pingpong [BORROWS].
 * @return             The index now being filled, 0 or 1.
 * @note Flips the low bit, so a swap of a swap is where it started.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning One caller at a time. The flip and the read below it are two steps on a plain byte, with
 *          no atomic and no lock, so two callers swapping the same pair can come away holding the
 *          same index.
 */
EMBED_INLINE uint8_t exter_pingpong_swap(const ExterCtx *args)
{
    // The flip stands on its own line and the answer is read back on the next, so neither is a side
    // effect inside the other. That second read is a fresh load, which is where a concurrent swap
    // would show up
    args->pingpong->fill_index ^= 1u;
    return args->pingpong->fill_index;
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_extern_ and exter_ prefixes.
 * @param[in] ...         Initializers for the ExterCtx literal, written in terms of args.
 * @note place is the only entry under these prefixes. The other four carry the pingpong pair below.
 */
#define EXTER_ENTRY(ReturnType_, name_, ...)                                                                           \
    EMBED_ENTRY(mmgr_extern_, exter_, ExterCtx, ExternaCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the pingpong entries, which carry their own pair of prefixes.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_pingpong_ and exter_pingpong_ prefixes.
 * @param[in] ...         Initializers for the ExterCtx literal, written in terms of args.
 * @note A second macro rather than one, because these entries are named mmgr_pingpong_ rather than
 *       mmgr_extern_. EMBED_ENTRY pastes one prefix onto one name, so the pair differs, not the form.
 */
#define PINGPONG_ENTRY(ReturnType_, name_, ...)                                                                        \
    EMBED_ENTRY(mmgr_pingpong_, exter_pingpong_, ExterCtx, ExternaCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the same pair to EMBED_ENTRY_V, for the entry that returns nothing.
 *
 * @param[in] name_ Name after the mmgr_pingpong_ and exter_pingpong_ prefixes.
 * @param[in] ...   Initializers for the ExterCtx literal, written in terms of args.
 * @note Separate from PINGPONG_ENTRY because a return with an expression is not allowed in a void
 *       function, so the two cannot share one body.
 * @note init is the only entry that reaches it. The other three pingpong entries hand back an index.
 */
#define PINGPONG_ENTRY_V(name_, ...)                                                                                   \
    EMBED_ENTRY_V(mmgr_pingpong_, exter_pingpong_, ExterCtx, ExternaCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in memoria_externa.h.
 * @note The fields each line forwards are the ones that entry reads, and EMBED_CALL zeroes the rest.
 * @note The four pingpong lines pass args->pingpong through as it stands [BORROWS]. EMBED_CALL builds
 *       its literal inside the emitted function, so the literal lives for that call alone and the
 *       pair has to outlive it. Nothing here copies the pair or frees it.
 * @warning No line tests what it forwards. A null pingpong reaches a backend that dereferences it
 *          with no check and no assertion.
 */
EXTER_ENTRY(mmgr_place, place, .size = args->size, .dma_required = args->dma_required, .free_dram = args->free_dram,
            .free_psram = args->free_psram, .psram_threshold = args->psram_threshold,
            .dram_reserve = args->dram_reserve)
PINGPONG_ENTRY_V(init, .pingpong = args->pingpong)
PINGPONG_ENTRY(uint8_t, fill_index, .pingpong = args->pingpong)
PINGPONG_ENTRY(uint8_t, drain_index, .pingpong = args->pingpong)
PINGPONG_ENTRY(uint8_t, swap, .pingpong = args->pingpong)

#endif
