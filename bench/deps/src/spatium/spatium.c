/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file spatium.c
 * @brief Spans over a caller's buffer, the two constructors and the walks over them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Holds no storage of its own, and every entry returns by value rather than through a pointer.
 * @note A span only points at the caller's bytes [BORROWS]. Every span cut from a buffer, and every
 *       span cut from that one, is good for exactly as long as the buffer is, and none of them frees
 *       it.
 * @note A span travels inside the argument pack rather than being pointed at, so a walk reads the
 *       caller's span and cannot change it. reset is the exception and takes args->at.
 * @note Reaches nothing outside config.
 */
#include "spatium/spatium.h"

/**
 * @brief Arguments for every spat backend, grouped by the calls that read them.
 *
 * @note Mirrors SpatiumCfg without its const qualifiers.
 */
typedef struct
{
    mmgr_span span;      /**< Fill span the walks read. */
    mmgr_cspan cspan;    /**< Read span cok tests. */
    mmgr_span *at;       /**< Fill span reset rewinds [BORROWS]. */
    uint8_t *buf;        /**< Buffer from builds over [BORROWS]. */
    const uint8_t *cbuf; /**< Buffer cfrom builds over [BORROWS]. */
    size_t cap;          /**< Bytes at buf, or at cbuf. */
    size_t count;        /**< Byte count after, first and read take. */
} SpatiumCtx;

/**
 * @brief Builds a fill span over args->buf, with pos at 0 and overflow clear.
 *
 * @param[in] args Buffer buf and its extent cap [BORROWS].
 * @return         The span, by value, still aimed at args->buf [BORROWS].
 * @warning cap is taken as given: the caller promises cap writable bytes at buf, and the two asserts
 *          only catch a null buffer and an empty one. A cap larger than the buffer is not caught here
 *          and the walks will hand out spans past its end.
 */
EMBED_INLINE mmgr_span spat_from(const SpatiumCtx *args)
{
    MMGR_ASSERT(args->buf != NULL, "a span needs a buffer");
    MMGR_ASSERT(args->cap != 0u, "a span needs a capacity");

    mmgr_span span;

    span.buf = args->buf;
    span.cap = args->cap;
    span.pos = 0u;
    span.overflow = EMBED_FALSE;
    return span;
}

/**
 * @brief Builds a read span over args->cbuf, with pos at 0 and err clear.
 *
 * @param[in] args Buffer cbuf and its extent cap [BORROWS].
 * @return         The span, by value, still aimed at args->cbuf [BORROWS].
 * @warning Takes cbuf and cap exactly as handed over, with none of the asserts spat_from makes. A
 *          null cbuf or a zero cap still builds, and it is cok that later reports it unusable. A cap
 *          reaching past the end of the buffer is the one cok cannot see, and it reads as usable.
 */
EMBED_INLINE mmgr_cspan spat_cfrom(const SpatiumCtx *args)
{
    mmgr_cspan span;

    span.buf = args->cbuf;
    span.len = args->cap;
    span.pos = 0u;
    span.err = EMBED_FALSE;
    return span;
}

/**
 * @brief Returns whether args->span covers any bytes at all.
 *
 * @param[in] args Span to test, as args->span [BORROWS].
 * @return         EMBED_TRUE when buf is not NULL and cap is not 0.
 */
EMBED_INLINE embed_bool spat_has_storage(const SpatiumCtx *args)
{
    // Explicit cast narrows the combined test into the embed_bool container
    return (embed_bool)((args->span.buf != NULL) && (args->span.cap != 0u));
}

/**
 * @brief Returns whether args->span is still usable.
 *
 * @param[in] args Span to test, as args->span [BORROWS].
 * @return         EMBED_TRUE when the span has storage and has not overflowed.
 */
EMBED_INLINE embed_bool spat_ok(const SpatiumCtx *args)
{
    // Explicit cast narrows the combined test into the embed_bool container
    return (embed_bool)(spat_has_storage(args) && !args->span.overflow);
}

/**
 * @brief Returns whether args->cspan is still usable.
 *
 * @param[in] args Read span to test, as args->cspan [BORROWS].
 * @return         EMBED_TRUE when the span has storage and has recorded no error.
 * @note The read side of spat_ok. The two cannot share a body, because a read span names its extent
 *       len and a fill span names it cap, which is what keeps the two from being mixed up.
 */
EMBED_INLINE embed_bool spat_cok(const SpatiumCtx *args)
{
    // Explicit cast narrows the combined test into the embed_bool container
    return (embed_bool)((args->cspan.buf != NULL) && (args->cspan.len != 0u) && !args->cspan.err);
}

/**
 * @brief Returns the span at args->at to its start and clears its overflow.
 *
 * @param[in,out] args Span to rewind, as args->at [BORROWS].
 * @warning at is written through with no check of its own, so it has to point at a live span. The
 *          const on the pack covers the pack, not the span at the far end of at.
 * @note Rewinds the span only. The bytes it covers are left exactly as they were, so a reset span
 *       hands out storage that still holds whatever the last fill wrote.
 */
EMBED_INLINE void spat_reset(const SpatiumCtx *args)
{
    args->at->pos = 0u;
    args->at->overflow = EMBED_FALSE;
}

/**
 * @brief Returns a span that has already failed, for a narrowing that ran past the storage.
 *
 * @return An empty span with overflow set.
 * @note Both narrowings answer a request past the end this way rather than with a shorter span: a
 *       caller that asked for bytes that are not there has a bug, and a span that looked whole
 *       would hide it.
 */
EMBED_INLINE mmgr_span spat_failed(void)
{
    mmgr_span failed;

    failed.buf = NULL;
    failed.cap = 0u;
    failed.pos = 0u;
    failed.overflow = EMBED_TRUE;
    return failed;
}

/**
 * @brief Returns the span beginning args->count bytes into args->span.
 *
 * @param[in] args Span to walk, as args->span, and the bytes to skip as args->count [BORROWS].
 * @return         A span over what is left, or a failed span when args->count is past cap.
 * @note The span that comes back starts inside the same buffer args->span covers [BORROWS]. It is a
 *       second view of those bytes, not a copy of them, and writes through either one are seen by
 *       both. pos comes forward with it, rebased to the new start and resting at 0 once the skip
 *       has passed it.
 */
EMBED_INLINE mmgr_span spat_after(const SpatiumCtx *args)
{
    mmgr_span rest;

    if (args->count > args->span.cap)
    {
        return spat_failed();
    }
    rest.buf = (args->span.buf != NULL) ? (args->span.buf + args->count) : NULL;
    rest.cap = args->span.cap - args->count;
    rest.pos = (args->span.pos > args->count) ? (args->span.pos - args->count) : 0u;
    rest.overflow = args->span.overflow;
    return rest;
}

/**
 * @brief Returns the span covering only the first args->count bytes of args->span.
 *
 * @param[in] args Span to narrow, as args->span, and the bytes to keep as args->count [BORROWS].
 * @return         A span over those bytes, or a failed span when args->count is past cap.
 * @note The span that comes back starts on the same byte args->span starts on [BORROWS], holding a
 *       shorter cap over the same storage. Both cover the opening bytes, so a fill through one is
 *       read by the other. pos comes forward, held down to the shorter cap when it sat past it.
 */
EMBED_INLINE mmgr_span spat_first(const SpatiumCtx *args)
{
    mmgr_span head;

    if (args->count > args->span.cap)
    {
        return spat_failed();
    }
    head.buf = args->span.buf;
    head.cap = args->count;
    head.pos = (args->span.pos < args->count) ? args->span.pos : args->count;
    head.overflow = args->span.overflow;
    return head;
}

/**
 * @brief Returns a read span over the first args->count bytes written into args->span.
 *
 * @param[in] args Span to read back, as args->span, and the bytes to cover as args->count [BORROWS].
 * @return         A read span over them, marked err when args->count is past what was written.
 * @warning The read span points at the fill span's own bytes [BORROWS], and the const on it binds
 *          this view, not the storage. Filling args->span again moves what the reader sees, so read
 *          it back before the next fill or copy the bytes out.
 */
EMBED_INLINE mmgr_cspan spat_read(const SpatiumCtx *args)
{
    mmgr_cspan view;

    view.buf = args->span.buf;
    view.len = (args->count < args->span.pos) ? args->count : args->span.pos;
    view.pos = 0u;
    // A span that overflowed produced fewer bytes than were asked of it, and the read side is told
    // so rather than being handed a shorter span that looks whole
    // Explicit cast narrows the combined test into the embed_bool container
    view.err = (embed_bool)(args->span.overflow || (args->count > args->span.pos));
    return view;
}

/**
 * @brief Returns a read span over everything written into args->span.
 *
 * @param[in] args Span to read back, as args->span [BORROWS].
 * @return         A read span over its first pos bytes, carrying span's overflow as its err.
 * @warning Hands back spat_read's span, so it points at args->span's own bytes [BORROWS] and the
 *          same caution holds. What it covers is whatever the next fill leaves there.
 */
EMBED_INLINE mmgr_cspan spat_produced(const SpatiumCtx *args)
{
    return EMBED_CALL(spat_read, SpatiumCtx, .span = args->span, .count = args->span.pos);
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_spat_ and spat_ prefixes, which the two share.
 * @param[in] ...         Initializers for the SpatiumCtx literal, written in terms of args.
 *                        EMBED_CALL zeroes every field left out.
 */
#define SPAT_ENTRY(ReturnType_, name_, ...)                                                                            \
    EMBED_ENTRY(mmgr_spat_, spat_, SpatiumCtx, SpatiumCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY_V, for an entry returning nothing.
 *
 * @param[in] name_ Name after the mmgr_spat_ and spat_ prefixes.
 * @param[in] ...   The same initializers SPAT_ENTRY takes, with no return type, since the entry this
 *                  builds returns nothing.
 */
#define SPAT_ENTRY_V(name_, ...) EMBED_ENTRY_V(mmgr_spat_, spat_, SpatiumCtx, SpatiumCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in spatium.h.
 * @note The fields each line forwards are the ones that entry reads; EMBED_CALL zeroes the rest.
 * @note from forwards buf and cfrom forwards cbuf, so a buffer that may not be written cannot reach
 *       the fill constructor. Both take their extent from cap.
 */
SPAT_ENTRY(mmgr_span, from, .buf = args->buf, .cap = args->cap)
SPAT_ENTRY(mmgr_cspan, cfrom, .cbuf = args->cbuf, .cap = args->cap)
SPAT_ENTRY(embed_bool, ok, .span = args->span)
SPAT_ENTRY(embed_bool, cok, .cspan = args->cspan)
SPAT_ENTRY(embed_bool, has_storage, .span = args->span)
SPAT_ENTRY_V(reset, .at = args->at)
SPAT_ENTRY(mmgr_span, after, .span = args->span, .count = args->count)
SPAT_ENTRY(mmgr_span, first, .span = args->span, .count = args->count)
SPAT_ENTRY(mmgr_cspan, produced, .span = args->span)
SPAT_ENTRY(mmgr_cspan, read, .span = args->span, .count = args->count)
