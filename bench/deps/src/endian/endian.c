/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file endian.c
 * @brief Reads and writes at two, four or eight bytes, in the host's own order and in the reverse of it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note The le pair stores and loads straight through proximus_operor, which moves bytes in the host's
 *       order. The be pair adds endian_rev to that, before the store in endian_wr_be and after the load
 *       in endian_rd_be. Nothing here reads MMGR_HW_BIG_ENDIAN, so which absolute order a table stands
 *       for follows from the host.
 * @note One reversal serves both tables: endian_rev reverses whatever it is given and carries no order
 *       of its own.
 */
#include "endian/endian.h"
#include "proximus_operor/proximus_operor.h"

/**
 * @brief Arguments for the endian backends.
 *
 * @note Mirrors EndianCfg with the top-level const dropped from every member. src keeps the const on
 *       what it points at, so nothing here writes through it.
 * @note endian_put reads dst, val and width. endian_get reads src and width. endian_rev reads val and
 *       width. EMBED_CALL zeroes the members a call is not given.
 */
typedef struct
{
    uint8_t *dst;            /**< Destination for the write calls [BORROWS]. */
    const uint8_t *src;      /**< Source for the read calls [BORROWS]. */
    uint64_t val;            /**< Value to write, or the value to reverse. */
    mmgr_endian_width width; /**< Bytes the call moves. The put and get switches take anything but 2 or 4 at eight. */
} EndianCtx;

/**
 * @brief Writes args->width bytes of args->val to args->dst in the target's own order.
 *
 * @param[in,out] args Destination, value and width [BORROWS].
 * @note Dispatches to proxim.put16, put32 or put64 on the width.
 * @note The labels are the byte counts themselves, which is what the mmgr_endian_width enumerators are.
 * @warning Any width other than 2 or 4 takes the default branch and writes eight bytes.
 * @warning args->dst must be writable for args->width bytes. Nothing checks it here, and nothing checks
 *          it in proximus_operor either, where the store is a plain dereference.
 */
EMBED_INLINE void endian_put(const EndianCtx *args)
{
    switch (args->width)
    {
    case 2:
        EMBED_CALL(proxim.put16, ProximusCfg, .dst = args->dst, .val = args->val);
        break;
    case 4:
        EMBED_CALL(proxim.put32, ProximusCfg, .dst = args->dst, .val = args->val);
        break;
    default:
        EMBED_CALL(proxim.put64, ProximusCfg, .dst = args->dst, .val = args->val);
        break;
    }
}

/**
 * @brief Reads args->width bytes from args->src in the target's own order.
 *
 * @param[in] args Source and width [BORROWS].
 * @return         The value read, in the low bytes of the result.
 * @note Dispatches to proxim.load16, load32 or load64 on the width.
 * @note The labels are the byte counts themselves, which is what the mmgr_endian_width enumerators are.
 * @warning Any width other than 2 or 4 takes the default branch and reads eight bytes.
 * @warning args->src must be readable for args->width bytes. Nothing checks it here, and nothing checks
 *          it in proximus_operor either, where the load is a plain dereference.
 */
EMBED_INLINE uint64_t endian_get(const EndianCtx *args)
{
    switch (args->width)
    {
    case 2:
        return EMBED_CALL(proxim.load16, ProximusCfg, .at = args->src);
    case 4:
        return EMBED_CALL(proxim.load32, ProximusCfg, .at = args->src);
    default:
        return EMBED_CALL(proxim.load64, ProximusCfg, .at = args->src);
    }
}

/**
 * @brief Reverses the byte order of args->val and returns the low args->width bytes.
 *
 * @param[in] args Value and width [BORROWS].
 * @return         The reversed value, right-aligned into the low args->width bytes.
 * @note Swaps at eight, then sixteen, then thirty-two bits, so the whole 64-bit value is reversed first.
 * @note The final shift drops the 8 - width bytes the reversal moved above the result, which is a shift
 *       of 8 * (8 - width) bits.
 * @warning 8u - args->width is unsigned, so an args->width above 8 wraps into a very large shift count,
 *          and a width of 0 shifts a 64-bit value by 64, which is undefined.
 */
EMBED_INLINE uint64_t endian_rev(const EndianCtx *args)
{
    uint64_t reversed = args->val;

    // Suffixed constants keep each mask at uint64_t, matching the value being swapped
    reversed = ((reversed & 0x00FF00FF00FF00FFull) << 8) | ((reversed >> 8) & 0x00FF00FF00FF00FFull);
    reversed = ((reversed & 0x0000FFFF0000FFFFull) << 16) | ((reversed >> 16) & 0x0000FFFF0000FFFFull);
    reversed = (reversed << 32) | (reversed >> 32);
    return reversed >> (8u * (8u - args->width));
}

/**
 * @brief Writes args->width bytes of args->val to args->dst without reversing them.
 *
 * @param[in,out] args Destination, value and width [BORROWS].
 * @return             args->width.
 * @note Calls endian_put directly, where endian_wr_be reverses first.
 * @note Hands back args->width as it was given, which is not what endian_put wrote when the width is
 *       outside the enumerators.
 */
EMBED_INLINE size_t endian_wr_le(const EndianCtx *args)
{
    endian_put(args);
    return args->width;
}

/**
 * @brief Reverses args->val, then writes args->width bytes of it to args->dst.
 *
 * @param[in,out] args Destination, value and width [BORROWS].
 * @return             args->width.
 * @note Builds a fresh EndianCtx holding the reversed value, leaving args untouched. EMBED_CALL names
 *       the initializers once, so endian_rev runs once.
 * @note Hands back args->width as it was given, which is not what endian_put wrote when the width is
 *       outside the enumerators.
 * @warning The width reaches endian_rev unchanged, so one above 8 wraps its shift count and one of 0
 *          shifts by 64, which is undefined.
 */
EMBED_INLINE size_t endian_wr_be(const EndianCtx *args)
{
    EMBED_CALL(endian_put, EndianCtx, .dst = args->dst, .val = endian_rev(args), .width = args->width);
    return args->width;
}

/**
 * @brief Reads args->width bytes from args->src without reversing them.
 *
 * @param[in] args Source and width [BORROWS].
 * @return         The value read, in the low args->width bytes.
 * @note Calls endian_get directly, where endian_rd_be reverses the result.
 * @note The upper bytes are zero, since the narrow loads widen into the uint64_t rather than filling it.
 */
EMBED_INLINE uint64_t endian_rd_le(const EndianCtx *args)
{
    return endian_get(args);
}

/**
 * @brief Reads args->width bytes from args->src, then reverses them.
 *
 * @param[in] args Source and width [BORROWS].
 * @return         The reversed value, right-aligned into the low args->width bytes.
 * @note Feeds endian_get's result into endian_rev through a fresh EndianCtx. EMBED_CALL names the
 *       initializers once, so endian_get runs once.
 * @warning The width reaches endian_rev unchanged, so one above 8 wraps its shift count and one of 0
 *          shifts by 64, which is undefined.
 */
EMBED_INLINE uint64_t endian_rd_be(const EndianCtx *args)
{
    return EMBED_CALL(endian_rev, EndianCtx, .val = endian_get(args), .width = args->width);
}

/**
 * @brief Binds the four order entries to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_ and endian_ prefixes, which the two share.
 * @param[in] ...         Initializers for the EndianCtx literal, written in terms of args.
 * @note The public prefix is mmgr_ on its own, so these four are named mmgr_wr_le and its kin rather
 *       than mmgr_endian_ anything. ENDIAN_REV_ENTRY carries the longer prefix for the one that needs it.
 */
#define ENDIAN_ENTRY(ReturnType_, name_, ...)                                                                          \
    EMBED_ENTRY(mmgr_, endian_, EndianCtx, EndianCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the reversal entry, which carries the longer public prefix.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_endian_ and endian_ prefixes.
 * @param[in] ...         Initializers for the EndianCtx literal, written in terms of args.
 * @note A second macro because this entry is named mmgr_endian_rev while the four above are named
 *       mmgr_wr_le and its kin. EMBED_ENTRY pastes one prefix onto one name, so only the pair differs.
 */
#define ENDIAN_REV_ENTRY(ReturnType_, name_, ...)                                                                      \
    EMBED_ENTRY(mmgr_endian_, endian_, EndianCtx, EndianCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in endian.h.
 * @note args->width is forwarded as it stands. EndianCfg and EndianCtx both declare it mmgr_endian_width,
 *       so there is no conversion to make.
 * @note The four wr and rd lines pass args->dst or args->src through as they stand [BORROWS]. EMBED_CALL
 *       builds its literal inside the emitted function, so the literal lives for that call alone and the
 *       buffer has to outlive it. Nothing here copies the buffer or frees it.
 * @warning No line tests what it forwards. A null dst or src reaches a backend that dereferences it with
 *          no check and no assertion.
 */
ENDIAN_ENTRY(size_t, wr_le, .dst = args->dst, .val = args->val, .width = args->width)
ENDIAN_ENTRY(uint64_t, rd_le, .src = args->src, .width = args->width)
ENDIAN_ENTRY(size_t, wr_be, .dst = args->dst, .val = args->val, .width = args->width)
ENDIAN_ENTRY(uint64_t, rd_be, .src = args->src, .width = args->width)
ENDIAN_REV_ENTRY(uint64_t, rev, .val = args->val, .width = args->width)
