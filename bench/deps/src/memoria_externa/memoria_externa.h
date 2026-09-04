/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoria_externa.h
 * @brief Placement between internal and external memory, and a two-buffer index.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @warning Everything below is declared only when MMGR_ENABLE_EXTRAM is set.
 */
#ifndef MMGR_MEMORIA_EXTERNA_H
#define MMGR_MEMORIA_EXTERNA_H

#include "mmgr.h"

#if MMGR_ENABLE_EXTRAM

EMBED_BEGIN_DECLS

/**
 * @brief Where a request should be placed.
 *
 * @note Packed to one byte. mmgr_types.h asserts that packing reaches the compiler.
 */
typedef enum EMBED_ENUM_PACKED
{
    PLACE_DRAM = 0,  /**< Internal memory. */
    PLACE_PSRAM = 1, /**< External memory. */
    PLACE_FAIL = 2   /**< Neither will take it. */
} mmgr_place;

/**
 * @brief A pair of buffers, one being filled while the other is drained.
 *
 * @note fill_index is the only member. The buffers it indexes are held elsewhere.
 * @note The two roles are one bit. The drain index is this one's complement, so a swap is a flip and
 *       there is no second member to keep in step.
 * @warning What holds fill_index to 0 or 1 is mmgr_pingpong_init setting it and mmgr_pingpong_swap
 *          flipping it. A pair that has not been through mmgr_pingpong_init carries whatever its
 *          storage held, and no call here tests the value.
 */
typedef struct
{
    uint8_t fill_index; /**< Index of the buffer being filled, 0 or 1. */
} PingPong;

/**
 * @brief Arguments for every exter call, where each call reads only the members it needs.
 *
 * @note free_dram and free_psram are supplied by the caller and used as given.
 * @note place reads the six figures. The pingpong entries read pingpong alone.
 */
typedef struct
{
    const size_t size;             /**< Bytes to place. */
    const embed_bool dma_required; /**< The bytes must be reachable by DMA. */
    const size_t free_dram;        /**< Bytes still free in internal memory. */
    const size_t free_psram;       /**< Bytes still free in external memory. */
    const size_t psram_threshold;  /**< Size at or above which external memory is tried first. */
    const size_t dram_reserve;     /**< Internal bytes that must remain free afterwards. */
    PingPong *const pingpong;      /**< Pair the pingpong entries act on [BORROWS]. */
} ExternaCfg;

/**
 * @brief Type of the exter dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the five members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note Every entry takes the same argument pack, as in locus_carcerum and memoria_anularis.
 */
typedef struct
{
    mmgr_place (*place)(const ExternaCfg *args);       /**< Decides where a request goes. */
    void (*pingpong_init)(const ExternaCfg *args);     /**< Points the pair at buffer 0. */
    uint8_t (*pingpong_fill)(const ExternaCfg *args);  /**< Index being filled. */
    uint8_t (*pingpong_drain)(const ExternaCfg *args); /**< Index being drained. */
    uint8_t (*pingpong_swap)(const ExternaCfg *args);  /**< Swaps the two roles. */
} MemoriaExternaNs;
EMBED_TABLE_LAYOUT(MemoriaExternaNs, place, pingpong_init, pingpong_fill, pingpong_drain, pingpong_swap);

/**
 * @brief Decides whether a request belongs in internal or external memory.
 *
 * @param[in] args Request size, the DMA requirement and both memory figures [BORROWS].
 * @return         PLACE_DRAM, PLACE_PSRAM, or PLACE_FAIL when neither will take it.
 * @note A size of 0 gives PLACE_FAIL.
 * @note A DMA request only ever gives PLACE_DRAM or PLACE_FAIL, never external memory.
 * @note At or above psram_threshold external memory is preferred, below it internal is.
 * @warning The two tests are not the same shape. Internal placement must also leave dram_reserve
 *          free, where the external one is a size comparison alone.
 */
mmgr_place mmgr_extern_place(const ExternaCfg *args);

/**
 * @brief Points the pair at buffer 0.
 *
 * @param[in,out] args Pair to reset, as args->pingpong [BORROWS].
 * @note The other three pingpong entries read a pair this call has set.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it, and this
 *          call writes through it at once.
 */
void mmgr_pingpong_init(const ExternaCfg *args);

/**
 * @brief Returns the index of the buffer being filled.
 *
 * @param[in] args Pair to read, as args->pingpong [BORROWS].
 * @return         0 or 1.
 * @note Does not modify args->pingpong.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning Reports fill_index as it stands. On a pair that has not been through mmgr_pingpong_init
 *          that is whatever its storage held, and this call does not bound it to 0 or 1.
 */
uint8_t mmgr_pingpong_fill_index(const ExternaCfg *args);

/**
 * @brief Returns the index of the buffer being drained.
 *
 * @param[in] args Pair to read, as args->pingpong [BORROWS].
 * @return         The other index, 0 or 1.
 * @note The answer is fill_index with its low bit flipped, so the two indexes always disagree.
 * @note Does not modify args->pingpong.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning The answer is an index only while fill_index is 0 or 1. On a pair that has not been
 *          through mmgr_pingpong_init it is the flip of whatever its storage held.
 */
uint8_t mmgr_pingpong_drain_index(const ExternaCfg *args);

/**
 * @brief Swaps which buffer is filled and which is drained.
 *
 * @param[in,out] args Pair to flip, as args->pingpong [BORROWS].
 * @return             The index now being filled, 0 or 1.
 * @note Flips the low bit, so a swap of a swap is where it started.
 * @warning args->pingpong must not be null. Nothing checks it and no assertion covers it.
 * @warning One caller at a time. The flip and the read that follows it are two steps on a plain byte,
 *          with no atomic and no lock, so two callers swapping the same pair can come away holding
 *          the same index.
 */
uint8_t mmgr_pingpong_swap(const ExternaCfg *args);

/**
 * @brief Dispatch table instance named exter.
 *
 * @note pingpong_fill calls mmgr_pingpong_fill_index and pingpong_drain calls mmgr_pingpong_drain_index.
 */
EMBED_TABLE_STORAGE MemoriaExternaNs exter EMBED_UNUSED = {
    .place = mmgr_extern_place,
    .pingpong_init = mmgr_pingpong_init,
    .pingpong_fill = mmgr_pingpong_fill_index,
    .pingpong_drain = mmgr_pingpong_drain_index,
    .pingpong_swap = mmgr_pingpong_swap,
};

EMBED_END_DECLS

#endif

#endif
