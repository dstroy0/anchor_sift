/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file proximus_operor.h
 * @brief Typed loads and stores, and the proxim dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note load16 through put64, load, put and read take any address.
 * @note The four al_ entries need an address aligned for the type they carry.
 */
#ifndef MMGR_PROXIMUS_OPEROR_H
#define MMGR_PROXIMUS_OPEROR_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Arguments for the proxim calls.
 *
 * @note The loads read at. The stores read dst and val. Only the read entry reads size.
 */
typedef struct
{
    void *const dst;      /**< Destination for the stores and for read [BORROWS]. */
    const void *const at; /**< Source for the loads and for read [BORROWS]. */
    const uint64_t val;   /**< Value the stores write, taken from its low bytes. */
    const size_t size;    /**< Bytes the read entry copies. */
} ProximusCfg;

/**
 * @brief Type of the proxim dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the thirteen members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note Each member below states its own alignment requirement.
 */
typedef struct
{
    uint16_t (*load16)(const ProximusCfg *args);    /**< Reads two bytes. */
    uint32_t (*load32)(const ProximusCfg *args);    /**< Reads four bytes. */
    uint64_t (*load64)(const ProximusCfg *args);    /**< Reads eight bytes. */
    void (*put16)(const ProximusCfg *args);         /**< Writes two bytes. */
    void (*put32)(const ProximusCfg *args);         /**< Writes four bytes. */
    void (*put64)(const ProximusCfg *args);         /**< Writes eight bytes. */
    embed_word (*load)(const ProximusCfg *args);    /**< Reads one word. */
    void (*put)(const ProximusCfg *args);           /**< Writes one word. */
    embed_word (*al_load)(const ProximusCfg *args); /**< Reads one word from an aligned address. */
    void (*al_put)(const ProximusCfg *args);        /**< Writes one word to an aligned address. */
    uint64_t (*al_load64)(const ProximusCfg *args); /**< Reads eight bytes from an aligned address. */
    void (*al_put64)(const ProximusCfg *args);      /**< Writes eight bytes to an aligned address. */
    void (*read)(const ProximusCfg *args);          /**< Copies size bytes, aligning the destination first. */
} ProximusOperorNs;
EMBED_TABLE_LAYOUT(ProximusOperorNs, load16, load32, load64, put16, put32, put64, load, put, al_load, al_put, al_load64,
                   al_put64, read);

/**
 * @brief Reads two bytes from args->at in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The two bytes as a uint16_t.
 * @warning args->at must be readable for two bytes, at any alignment.
 */
uint16_t mmgr_proxim_load16(const ProximusCfg *args);

/**
 * @brief Reads four bytes from args->at in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The four bytes as a uint32_t.
 * @warning args->at must be readable for four bytes, at any alignment.
 */
uint32_t mmgr_proxim_load32(const ProximusCfg *args);

/**
 * @brief Reads eight bytes from args->at in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The eight bytes as a uint64_t.
 * @warning args->at must be readable for eight bytes, at any alignment.
 */
uint64_t mmgr_proxim_load64(const ProximusCfg *args);

/**
 * @brief Writes the low two bytes of args->val to args->dst in the target's own order.
 *
 * @param[in] args Destination and value [BORROWS].
 * @note The upper six bytes of args->val take no part.
 * @warning args->dst must be writable for two bytes, at any alignment.
 */
void mmgr_proxim_put16(const ProximusCfg *args);

/**
 * @brief Writes the low four bytes of args->val to args->dst in the target's own order.
 *
 * @param[in] args Destination and value [BORROWS].
 * @note The upper four bytes of args->val take no part.
 * @warning args->dst must be writable for four bytes, at any alignment.
 */
void mmgr_proxim_put32(const ProximusCfg *args);

/**
 * @brief Writes all eight bytes of args->val to args->dst in the target's own order.
 *
 * @param[in] args Destination and value [BORROWS].
 * @warning args->dst must be writable for eight bytes, at any alignment.
 */
void mmgr_proxim_put64(const ProximusCfg *args);

/**
 * @brief Reads one word from args->at in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The bytes as an embed_word.
 * @warning args->at must be readable for a whole embed_word, at any alignment.
 */
embed_word mmgr_proxim_load(const ProximusCfg *args);

/**
 * @brief Writes the low word of args->val to args->dst in the target's own order.
 *
 * @param[in] args Destination and value [BORROWS].
 * @warning args->dst must be writable for a whole embed_word, at any alignment.
 */
void mmgr_proxim_put(const ProximusCfg *args);

/**
 * @brief Reads one word from an aligned args->at, in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The bytes as an embed_word.
 * @note Reaches the same bytes as mmgr_proxim_load, through a type that keeps embed_word's alignment.
 * @warning args->at must be readable for a whole embed_word and aligned for one.
 */
embed_word mmgr_aequus_load(const ProximusCfg *args);

/**
 * @brief Writes the low word of args->val to an aligned args->dst.
 *
 * @param[in] args Destination and value [BORROWS].
 * @note Reaches the same bytes as mmgr_proxim_put, through a type that keeps embed_word's alignment.
 * @warning args->dst must be writable for a whole embed_word and aligned for one.
 */
void mmgr_aequus_put(const ProximusCfg *args);

/**
 * @brief Reads eight bytes from an aligned args->at, in the target's own order.
 *
 * @param[in] args Address to read from [BORROWS].
 * @return         The eight bytes as a uint64_t.
 * @note Reaches the same bytes as mmgr_proxim_load64, through a type that keeps uint64_t's alignment.
 * @warning args->at must be readable for eight bytes and aligned for a uint64_t.
 */
uint64_t mmgr_aequus_load64(const ProximusCfg *args);

/**
 * @brief Writes all eight bytes of args->val to an aligned args->dst.
 *
 * @param[in] args Destination and value [BORROWS].
 * @note Reaches the same bytes as mmgr_proxim_put64, through a type that keeps uint64_t's alignment.
 * @warning args->dst must be writable for eight bytes and aligned for a uint64_t.
 */
void mmgr_aequus_put64(const ProximusCfg *args);

/**
 * @brief Copies args->size bytes from args->at to args->dst.
 *
 * @param[in] args Destination, source and count [BORROWS].
 * @note Copies bytes until args->dst reaches a word boundary, then whole words, then the odd bytes left.
 * @note This is the only entry that reads args->size.
 * @warning Copies forward, so an args->dst above args->at within one region would read bytes it has already written.
 */
void mmgr_proxim_read(const ProximusCfg *args);

/**
 * @brief Dispatch table instance named proxim.
 *
 * @note The nine unaligned members call the mmgr_proxim_ functions.
 * @note The four al_ members call the mmgr_aequus_ ones.
 */
EMBED_TABLE_STORAGE ProximusOperorNs proxim EMBED_UNUSED = {
    .load16 = mmgr_proxim_load16,
    .load32 = mmgr_proxim_load32,
    .load64 = mmgr_proxim_load64,
    .put16 = mmgr_proxim_put16,
    .put32 = mmgr_proxim_put32,
    .put64 = mmgr_proxim_put64,
    .load = mmgr_proxim_load,
    .put = mmgr_proxim_put,
    .al_load = mmgr_aequus_load,
    .al_put = mmgr_aequus_put,
    .al_load64 = mmgr_aequus_load64,
    .al_put64 = mmgr_aequus_put64,
    .read = mmgr_proxim_read,
};

EMBED_END_DECLS

#endif
