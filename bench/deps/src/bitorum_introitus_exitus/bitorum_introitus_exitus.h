/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bitorum_introitus_exitus.h
 * @brief Bit writer state, its arguments, and the bitio dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Packs bit fields of any width into a byte buffer without a bit ever crossing a call. The
 *       writer holds the partial byte, so a caller states widths and values and never does its own
 *       shifting or masking.
 * @note The writer is a value the caller owns, not state this module keeps. Two streams are two
 *       writers, and neither module state nor a lock is involved.
 * @warning put writes whole bytes only, so bits that do not fill one stay in the writer's residue
 *          and align is what puts that last partial byte out. A stream whose length is not a
 *          multiple of eight and that never calls align ends one byte short, with no flag raised
 *          and nothing to notice at the call.
 */
#ifndef MMGR_BITORUM_INTROITUS_EXITUS_H
#define MMGR_BITORUM_INTROITUS_EXITUS_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Bit writer state: the buffer, how much is written, and the partial byte.
 *
 * @note Built by mmgr_bitor_init, advanced by mmgr_bitor_put, and finished by mmgr_bitor_align.
 */
typedef struct
{
    uint8_t *out;         /**< Destination buffer [BORROWS]. */
    size_t cap;           /**< Bytes available in out. */
    size_t bytes_written; /**< Whole bytes written so far. */
    uint8_t residue;      /**< Bits not yet written, in the low bit_count positions. */
    embed_word bit_count; /**< Bits held in residue, always under 8. */
    embed_bool overflow;  /**< Set once a request would pass cap, which blocks later writes. */
} mmgr_bitor;

/**
 * @brief Arguments for the bitor calls, where each call reads only the members it needs.
 *
 * @note mmgr_bitor_init reads out and cap. mmgr_bitor_put reads writer, val and bit_count.
 *       mmgr_bitor_align reads writer alone.
 * @note One argument type for all three entries, so every call has the same shape and an unnamed
 *       member is zeroed rather than left undefined.
 */
typedef struct
{
    mmgr_bitor *const writer;   /**< Writer for mmgr_bitor_put and mmgr_bitor_align [BORROWS]. */
    uint8_t *const out;         /**< Buffer for mmgr_bitor_init [BORROWS]. */
    const size_t cap;           /**< Bytes available in out. */
    const uint64_t val;         /**< Bits for mmgr_bitor_put, taken from the low end. */
    const embed_word bit_count; /**< Bits of val to write, which must not exceed 64. */
} BitorumCfg;

/**
 * @brief Type of the bitio dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the three members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    mmgr_bitor (*init)(const BitorumCfg *args); /**< Builds a writer over a buffer. */
    void (*put)(const BitorumCfg *args);        /**< Appends bits, writing whole bytes only. */
    void (*align)(const BitorumCfg *args);      /**< Writes the partial byte still held. */
} BitorumIntroitusExitusNs;
EMBED_TABLE_LAYOUT(BitorumIntroitusExitusNs, init, put, align);

/**
 * @brief Builds a bit writer over args->out with capacity args->cap.
 *
 * @param[in] args Buffer and capacity [BORROWS].
 * @return         A writer with no bytes written and no residue.
 * @note The returned writer keeps args->out, which must outlive it [BORROWS].
 * @warning args->out must not be null and args->cap must not be zero. Neither is held to outside a
 *          MMGR_DEBUG_CHECKS build, and a null out is not noticed here: mmgr_bitor_put writes
 *          through it on the first whole byte.
 */
mmgr_bitor mmgr_bitor_init(const BitorumCfg *args);

/**
 * @brief Appends the low args->bit_count bits of args->val to args->writer.
 *
 * @param[in,out] args Writer, value and bit count [BORROWS].
 * @note Writes whole bytes only. Leftover bits stay in the writer's residue.
 * @note Does nothing when the writer's overflow is already set, so a caller may write a whole
 *       stream and test overflow once at the end rather than after every call.
 * @note Sets the writer's overflow and clears its residue when the bytes would pass its cap.
 * @warning args->bit_count must not exceed 64, and nothing holds it there outside a
 *          MMGR_DEBUG_CHECKS build. A larger count writes zeros past the sixty-fourth bit and
 *          advances the writer as though they were data.
 */
void mmgr_bitor_put(const BitorumCfg *args);

/**
 * @brief Writes the partial byte the writer still holds, padded with zeros above its bits.
 *
 * @param[in,out] args Writer to finish [BORROWS].
 * @note mmgr_bitor_put writes whole bytes only. Without this call the residue is never written.
 * @note Does nothing when the residue is empty, so a second call writes nothing.
 * @note Does nothing when the writer's overflow is already set.
 * @note Only args->writer is read.
 * @warning Sets the writer's overflow when the byte would pass its cap.
 */
void mmgr_bitor_align(const BitorumCfg *args);

/**
 * @brief Dispatch table instance named bitio, with each member set to its mmgr_bitor_ function.
 */
EMBED_TABLE_STORAGE BitorumIntroitusExitusNs bitio EMBED_UNUSED = {
    .init = mmgr_bitor_init,
    .put = mmgr_bitor_put,
    .align = mmgr_bitor_align,
};

EMBED_END_DECLS

#endif
