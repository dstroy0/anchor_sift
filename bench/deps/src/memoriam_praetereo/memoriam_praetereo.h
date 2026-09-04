/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoriam_praetereo.h
 * @brief DMA channels: the completion event, the port hooks, and the praet dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @warning Everything below is declared only when MMGR_ENABLE_DMA is set.
 */
#ifndef MMGR_MEMORIAM_PRAETEREO_H
#define MMGR_MEMORIAM_PRAETEREO_H

#include "mmgr.h"

#if MMGR_ENABLE_DMA

EMBED_BEGIN_DECLS

/**
 * @brief What the port layer reports when a transfer finishes.
 *
 * @warning data points at the port layer's buffer. It is valid only for the callback's duration [BORROWS].
 */
typedef struct
{
    const uint8_t *data;    /**< Bytes the transfer moved [BORROWS]. */
    uint32_t completion_ms; /**< Completion time, whole milliseconds. */
    uint32_t completion_us; /**< Completion time, microseconds within that millisecond. */
    uint16_t bytes;         /**< Bytes in data. */
    uint16_t sequence;      /**< Sequence number the port layer assigns. */
    uint8_t channel;        /**< Channel the transfer ran on. */
    uint8_t peripheral;     /**< Peripheral the channel is wired to. */
    uint8_t direction;      /**< Direction of the transfer. */
} mmgr_praet_event;

/**
 * @brief Reports a finished transfer to whatever registered this callback.
 *
 * @param[in] event The completion event [BORROWS].
 * @param[in] user  The pointer registered alongside this callback [BORROWS].
 * @note Runs in whatever context the port layer finishes a transfer in. No mmgr_praet_ entry point
 *       calls it.
 * @warning event and event->data belong to the port layer and last only until this returns. Copy
 *          anything kept [BORROWS].
 */
typedef void (*mmgr_praet_callback)(const mmgr_praet_event *event, void *user);

/**
 * @brief The channel count and buffer size a build was configured with.
 *
 * @note The implementation holds one of these, filled from MMGR_PRAET_CHANNELS and MMGR_PRAET_BUF_SIZE.
 */
typedef struct
{
    const size_t channels; /**< Channels available. */
    const size_t buf_size; /**< Largest transfer one channel accepts. */
} PraetInit;

/**
 * @brief A completion callback and the pointer handed back to it.
 *
 * @warning mmgr_praet_open forwards the pointer to this struct unchanged, rather than copying it, so
 *          it must stay valid for as long as the channel is open [BORROWS].
 */
typedef struct
{
    const mmgr_praet_callback callback; /**< Function to call [BORROWS]. */
    void *const user;                   /**< Passed back to callback unexamined [BORROWS]. */
} PraetCallbackCfg;

/**
 * @brief Arguments for opening a channel, and for polling one.
 *
 * @note mmgr_praet_open reads all four members. mmgr_praet_poll passes the whole struct to the port
 *       layer.
 */
typedef struct
{
    const uint8_t channel;                     /**< Channel to act on. */
    const uint8_t peripheral;                  /**< Peripheral the channel is wired to. */
    const embed_bool loopback;                 /**< Open the channel looped back on itself. */
    const PraetCallbackCfg *const on_complete; /**< Called when a transfer finishes [BORROWS]. */
} PraetCfg;

/**
 * @brief Arguments for submitting a transfer, and for closing a channel.
 *
 * @note mmgr_praet_tx_submit reads all three. mmgr_praet_close reads channel alone.
 */
typedef struct
{
    const uint8_t channel;    /**< Channel to act on. */
    const uint8_t *const buf; /**< Bytes to send [BORROWS]. */
    const uint16_t bytes;     /**< Bytes in buf. */
} PraetTransferCfg;

/**
 * @brief Type of the praet dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the four members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    embed_bool (*open)(const PraetCfg *args);              /**< Opens a channel. */
    embed_bool (*tx_submit)(const PraetTransferCfg *args); /**< Submits a transfer. */
    void (*close)(const PraetTransferCfg *args);           /**< Closes a channel. */
    void (*poll)(const PraetCfg *args);                    /**< Drives the port layer's poll hook. */
} MemoriamPraetereoNs;
EMBED_TABLE_LAYOUT(MemoriamPraetereoNs, open, tx_submit, close, poll);

/**
 * @brief Opens args->channel and registers args->on_complete against it.
 *
 * @param[in] args Channel, peripheral, loopback flag and completion callback [BORROWS].
 * @return         EMBED_TRUE when the port layer accepted the request.
 * @note The default mmgr_praet_hw_open refuses, so this returns EMBED_FALSE until a port replaces it.
 * @warning args->channel must be below the configured channel count, and args->on_complete must not be NULL.
 */
embed_bool mmgr_praet_open(const PraetCfg *args);

/**
 * @brief Submits args->bytes of args->buf on args->channel.
 *
 * @param[in] args Channel, buffer and byte count [BORROWS].
 * @return         EMBED_TRUE when the port layer accepted the transfer.
 * @note The default mmgr_praet_hw_tx_submit refuses, so this returns EMBED_FALSE until a port replaces it.
 * @warning args->buf must stay valid until the completion callback runs [BORROWS].
 * @warning args->channel must be below the configured channel count, and args->bytes must not exceed
 *          the buffer size.
 */
embed_bool mmgr_praet_tx_submit(const PraetTransferCfg *args);

/**
 * @brief Closes args->channel.
 *
 * @param[in] args Channel to close [BORROWS].
 * @note Only args->channel is read. buf and bytes take no part.
 * @warning args->channel must be below the configured channel count.
 */
void mmgr_praet_close(const PraetTransferCfg *args);

/**
 * @brief Drives the port layer's poll hook.
 *
 * @param[in] args Channel to poll [BORROWS].
 * @note Passes args straight to mmgr_praet_hw_poll, unlike the other three entries, which assert first.
 * @warning No assertion runs here, so args and args->channel reach the port layer exactly as the caller gave them.
 */
void mmgr_praet_poll(const PraetCfg *args);

/**
 * @brief Opens a DMA channel on real hardware.
 *
 * @param[in] args Channel, peripheral, loopback flag and completion callback, as mmgr_praet_open
 *                 forwards them [BORROWS].
 * @return         EMBED_TRUE when the hardware accepted the request.
 * @note The default in memoriam_praetereo.c refuses every request, so a build links without a port.
 * @note An application definition of this name replaces that default where EMBED_HAS_ATTRIBUTE(weak)
 *       is non-zero.
 * @warning Reached through mmgr_praet_open, which asserts the channel and the callback first.
 */
embed_bool mmgr_praet_hw_open(const PraetCfg *args);

/**
 * @brief Submits a transfer on real hardware.
 *
 * @param[in] args Channel, buffer and byte count, as mmgr_praet_tx_submit forwards them [BORROWS].
 * @return         EMBED_TRUE when the hardware accepted the transfer.
 * @note The default in memoriam_praetereo.c refuses every transfer, so a build links without a port.
 * @note An application definition of this name replaces that default where EMBED_HAS_ATTRIBUTE(weak)
 *       is non-zero.
 * @warning Reached through mmgr_praet_tx_submit, which asserts the channel and the byte count first.
 * @warning args->buf must stay valid until this reports completion through the registered callback [BORROWS].
 */
embed_bool mmgr_praet_hw_tx_submit(const PraetTransferCfg *args);

/**
 * @brief Closes a DMA channel on real hardware.
 *
 * @param[in] args Channel to close, as mmgr_praet_close forwards it [BORROWS].
 * @note The default in memoriam_praetereo.c does nothing, so a build links without a port.
 * @note An application definition of this name replaces that default where EMBED_HAS_ATTRIBUTE(weak)
 *       is non-zero.
 * @note Only args->channel is forwarded. buf and bytes take no part.
 * @warning Reached through mmgr_praet_close, which asserts the channel first.
 */
void mmgr_praet_hw_close(const PraetTransferCfg *args);

/**
 * @brief Advances whatever polling the port layer needs.
 *
 * @param[in] args Channel to poll, exactly as the caller gave it [BORROWS].
 * @note The default in memoriam_praetereo.c does nothing, so a build links without a port.
 * @note An application definition of this name replaces that default where EMBED_HAS_ATTRIBUTE(weak)
 *       is non-zero.
 * @warning mmgr_praet_poll calls this directly, with no checking call in between. args and
 *          args->channel arrive exactly as the caller wrote them, unasserted.
 */
void mmgr_praet_hw_poll(const PraetCfg *args);

/**
 * @brief Dispatch table instance named praet.
 *
 * @note Each member calls the matching mmgr_praet_ function, one to one. No member is pointed at
 *       another's function, which is where this differs from the memor table.
 */
EMBED_TABLE_STORAGE MemoriamPraetereoNs praet EMBED_UNUSED = {
    .open = mmgr_praet_open,
    .tx_submit = mmgr_praet_tx_submit,
    .close = mmgr_praet_close,
    .poll = mmgr_praet_poll,
};

EMBED_END_DECLS

#endif

#endif
