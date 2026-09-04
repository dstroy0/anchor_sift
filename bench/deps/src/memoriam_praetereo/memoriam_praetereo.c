/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoriam_praetereo.c
 * @brief DMA channel handling, over a weak port layer an application replaces.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @warning The whole file is compiled only when MMGR_ENABLE_DMA is set.
 */
#include "memoriam_praetereo/memoriam_praetereo.h"

#if MMGR_ENABLE_DMA

/**
 * @brief The channel count and buffer size this build was configured with.
 *
 * @note Named only by the assertions in the three checking calls. The default MMGR_ASSERT leaves
 *       them unevaluated.
 */
static const PraetInit praet_init = {
    .channels = MMGR_PRAET_CHANNELS,
    .buf_size = MMGR_PRAET_BUF_SIZE,
};

/**
 * @brief Arguments for opening a channel.
 *
 * @note Mirrors PraetCfg without its top-level const qualifiers. on_complete still points at a const
 *       PraetCallbackCfg.
 */
typedef struct
{
    uint8_t channel;                     /**< Channel to open. */
    uint8_t peripheral;                  /**< Peripheral the channel is wired to. */
    embed_bool loopback;                 /**< Open the channel looped back on itself. */
    const PraetCallbackCfg *on_complete; /**< Called when a transfer finishes [BORROWS]. */
} PraetOpenCtx;

/**
 * @brief Arguments for submitting a transfer, and for closing a channel.
 *
 * @note Mirrors PraetTransferCfg without its top-level const qualifiers. buf still points at const
 *       uint8_t.
 * @note praet_close reads channel alone.
 */
typedef struct
{
    uint8_t channel;    /**< Channel to act on. */
    const uint8_t *buf; /**< Bytes to send [BORROWS]. */
    uint16_t bytes;     /**< Bytes in buf. */
} PraetTransferCtx;

/**
 * @brief Weak default for opening a channel, which refuses every request.
 *
 * @param[in] args Channel, peripheral and completion callback [BORROWS].
 * @return         EMBED_FALSE always.
 * @note EMBED_WEAK marks this weak where EMBED_HAS_ATTRIBUTE(weak) is non-zero. An application
 *       definition replaces it.
 * @note The (void)args discards the argument, since this body reads nothing.
 */
EMBED_WEAK embed_bool mmgr_praet_hw_open(const PraetCfg *args)
{
    (void)args;
    return EMBED_FALSE;
}

/**
 * @brief Weak default for submitting a transfer, which refuses every request.
 *
 * @param[in] args Channel, buffer and byte count [BORROWS].
 * @return         EMBED_FALSE always.
 * @note EMBED_WEAK marks this weak where EMBED_HAS_ATTRIBUTE(weak) is non-zero. An application
 *       definition replaces it.
 * @note The (void)args discards the argument, since this body reads nothing.
 */
EMBED_WEAK embed_bool mmgr_praet_hw_tx_submit(const PraetTransferCfg *args)
{
    (void)args;
    return EMBED_FALSE;
}

/**
 * @brief Weak default for closing a channel, which does nothing.
 *
 * @param[in] args Channel to close [BORROWS].
 * @note EMBED_WEAK marks this weak where EMBED_HAS_ATTRIBUTE(weak) is non-zero. An application
 *       definition replaces it.
 * @note The (void)args discards the argument, since this body reads nothing.
 */
EMBED_WEAK void mmgr_praet_hw_close(const PraetTransferCfg *args)
{
    (void)args;
}

/**
 * @brief Weak default for the poll hook, which does nothing.
 *
 * @param[in] args Channel to poll [BORROWS].
 * @note EMBED_WEAK marks this weak where EMBED_HAS_ATTRIBUTE(weak) is non-zero. An application
 *       definition replaces it.
 * @note The (void)args discards the argument, since this body reads nothing.
 */
EMBED_WEAK void mmgr_praet_hw_poll(const PraetCfg *args)
{
    (void)args;
}

/**
 * @brief Checks the channel and the callback, then hands the request to the port layer.
 *
 * @param[in] args Channel, peripheral, loopback flag and completion callback [BORROWS].
 * @return         Whatever mmgr_praet_hw_open returns.
 * @warning args->channel must be below praet_init.channels, and args->on_complete must not be NULL.
 */
EMBED_INLINE embed_bool praet_open(const PraetOpenCtx *args)
{
    MMGR_ASSERT(args->channel < praet_init.channels, "no such channel");
    MMGR_ASSERT(args->on_complete != NULL, "an open channel reports completion");

    return EMBED_CALL(mmgr_praet_hw_open, PraetCfg, .channel = args->channel, .peripheral = args->peripheral,
                      .loopback = args->loopback, .on_complete = args->on_complete);
}

/**
 * @brief Checks the channel and the byte count, then hands the transfer to the port layer.
 *
 * @param[in] args Channel, buffer and byte count [BORROWS].
 * @return         Whatever mmgr_praet_hw_tx_submit returns.
 * @warning args->channel must be below praet_init.channels, and args->bytes must not exceed praet_init.buf_size.
 */
EMBED_INLINE embed_bool praet_tx_submit(const PraetTransferCtx *args)
{
    MMGR_ASSERT(args->channel < praet_init.channels, "no such channel");
    MMGR_ASSERT(args->bytes <= praet_init.buf_size, "a transfer is bounded by the channel buffer");

    return EMBED_CALL(mmgr_praet_hw_tx_submit, PraetTransferCfg, .channel = args->channel, .buf = args->buf,
                      .bytes = args->bytes);
}

/**
 * @brief Checks the channel, then asks the port layer to close it.
 *
 * @param[in] args Channel to close [BORROWS].
 * @note Passes only the channel on. buf and bytes take no part.
 * @warning args->channel must be below praet_init.channels.
 */
EMBED_INLINE void praet_close(const PraetTransferCtx *args)
{
    MMGR_ASSERT(args->channel < praet_init.channels, "no such channel");

    EMBED_CALL(mmgr_praet_hw_close, PraetTransferCfg, .channel = args->channel);
}

/**
 * @brief Binds this module's fixed arguments to EMBED_ENTRY, with the two types per entry.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] CtxType_    Context type this entry's backend takes.
 * @param[in] CfgType_    Argument type the caller passes.
 * @param[in] name_       Name after the mmgr_praet_ and praet_ prefixes, which the two share.
 * @param[in] ...         Initializers for the CtxType_ literal, written in terms of the CfgType_ the
 *                        entry was handed.
 * @note Both types are parameters here. Opening a channel and moving bytes on one take different
 *       arguments, so the module carries two of each rather than one.
 */
#define PRAET_ENTRY(ReturnType_, CtxType_, CfgType_, name_, ...)                                                       \
    EMBED_ENTRY(mmgr_praet_, praet_, CtxType_, CfgType_, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the same to EMBED_ENTRY_V, for an entry that returns nothing.
 *
 * @param[in] CtxType_ Context type this entry's backend takes.
 * @param[in] CfgType_ Argument type the caller passes.
 * @param[in] name_    Name after the mmgr_praet_ and praet_ prefixes.
 * @param[in] ...      Initializers for the CtxType_ literal, written in terms of the CfgType_ the
 *                     entry was handed.
 */
#define PRAET_ENTRY_V(CtxType_, CfgType_, name_, ...)                                                                  \
    EMBED_ENTRY_V(mmgr_praet_, praet_, CtxType_, CfgType_, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in memoriam_praetereo.h.
 * @note mmgr_praet_close forwards args->channel alone. The rest of its argument type is not read.
 */
PRAET_ENTRY(embed_bool, PraetOpenCtx, PraetCfg, open, .channel = args->channel, .peripheral = args->peripheral,
            .loopback = args->loopback, .on_complete = args->on_complete)
PRAET_ENTRY(embed_bool, PraetTransferCtx, PraetTransferCfg, tx_submit, .channel = args->channel, .buf = args->buf,
            .bytes = args->bytes)
PRAET_ENTRY_V(PraetTransferCtx, PraetTransferCfg, close, .channel = args->channel)

/**
 * @brief Calls the port layer's poll hook.
 *
 * @param[in] args Channel to poll [BORROWS].
 * @note Hand-rolled rather than an entry line, as mmgr_anular_init is. It hands args to the weak hook
 *       unchanged, with no checking call in between, so there is no argument pack to build and no
 *       praet_ backend for EMBED_ENTRY to name.
 * @note Documented at the declaration in memoriam_praetereo.h.
 */
void mmgr_praet_poll(const PraetCfg *args)
{
    mmgr_praet_hw_poll(args);
}

#endif
