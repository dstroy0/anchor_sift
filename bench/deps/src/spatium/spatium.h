/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file spatium.h
 * @brief Spans over a caller's buffer, the two span types, and the spat dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note A span is a region and a cursor into it, with a sticky flag that latches once a walk has run
 *       past the end. It carries no storage of its own.
 * @note The entries take an argument pack, as every other module's do. A span still travels by value
 *       inside that pack. SpatiumCfg holds one rather than pointing at one, so a walk cannot change
 *       the span it was given.
 * @note There are two span types rather than one. mmgr_span is written through and latches overflow.
 *       mmgr_cspan is read from and latches err. Their extents are named cap and len, so handing one
 *       where the other belongs is a compile error.
 * @note The sticky flag is what makes a span worth passing. A caller may walk one through several
 *       steps and test once at the end rather than after each.
 * @note overflow and err do not mean the same kind of thing. A fill span overruns only when what a
 *       writer emits was sized wrong against its buffer, and both of those are settled before the
 *       build, so overflow marks a wrong program. A read span runs out because whatever sent the
 *       bytes sent fewer, which is a runtime fact and nothing built wrong.
 */
#ifndef MMGR_SPATIUM_H
#define MMGR_SPATIUM_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief A buffer being filled: its bytes, how far the writer has gone, and whether it ran out.
 *
 * @note Returned by value. This module keeps no span of its own.
 * @note overflow is sticky. Once a write has run past cap it stays set, and only mmgr_spat_reset
 *       clears it.
 * @note Reaching it at all is a build failure, so it is read to find out that something is wrong
 *       rather than to decide what to do next. It latches so that a wrong program stops writing
 *       instead of walking off the end, and so that one test after a run of appends catches it.
 * @warning buf points at the caller's storage, which must outlive every use of the span [BORROWS].
 */
typedef struct
{
    uint8_t *buf;        /**< The buffer the span covers [BORROWS]. */
    size_t cap;          /**< Bytes in buf. */
    size_t pos;          /**< Bytes written so far, which mmgr_spat_from sets to 0. */
    embed_bool overflow; /**< Set once a write has run past cap, and cleared only by mmgr_spat_reset. */
} mmgr_span;

/**
 * @brief A buffer being read: its bytes, how far the reader has gone, and whether it ran out.
 *
 * @note The read-only counterpart of mmgr_span. buf is const here, so a span handed out for reading
 *       cannot be written through it.
 * @note err is sticky, for the same reason overflow is.
 * @warning buf points at storage that must outlive every use of the span [BORROWS].
 */
typedef struct
{
    const uint8_t *buf; /**< First byte, or NULL when there is nothing to read [BORROWS]. */
    size_t len;         /**< Readable bytes at buf. */
    size_t pos;         /**< Bytes read so far. */
    embed_bool err;     /**< Set once a read has run past len, and never cleared after. */
} mmgr_cspan;

/**
 * @brief Arguments for every spat call, where each call reads only the members it needs.
 *
 * @note Members left unset are zero, and the calls that ignore them never read them.
 * @note span and cspan hold a span rather than pointing at one, so a walk reads the caller's span and
 *       cannot change it. reset is the one entry that must change one, and it takes at.
 * @note cap carries the extent for both constructors: bytes at buf for from, bytes at cbuf for cfrom.
 * @note count carries the byte count for after, first and read.
 */
typedef struct
{
    const mmgr_span span;      /**< Fill span the walks read. */
    const mmgr_cspan cspan;    /**< Read span cok tests. */
    mmgr_span *const at;       /**< Fill span reset rewinds [BORROWS]. */
    uint8_t *const buf;        /**< Buffer from builds over [BORROWS]. */
    const uint8_t *const cbuf; /**< Buffer cfrom builds over [BORROWS]. */
    const size_t cap;          /**< Bytes at buf, or at cbuf. */
    const size_t count;        /**< Byte count after, first and read take. */
} SpatiumCfg;

/**
 * @brief Type of the spat dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the ten members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note There is no len or room entry. mmgr_span is the caller's own value, so span.pos and
 *       span.cap - span.pos are already in hand, and a call to fetch them would duplicate what
 *       reading the member already gives.
 */
typedef struct
{
    mmgr_span (*from)(const SpatiumCfg *args);         /**< Builds a fill span over a buffer. */
    mmgr_cspan (*cfrom)(const SpatiumCfg *args);       /**< Builds a read span over a buffer. */
    embed_bool (*ok)(const SpatiumCfg *args);          /**< Whether a fill span is still usable. */
    embed_bool (*cok)(const SpatiumCfg *args);         /**< Whether a read span is still usable. */
    embed_bool (*has_storage)(const SpatiumCfg *args); /**< Whether the span covers any bytes at all. */
    void (*reset)(const SpatiumCfg *args);             /**< Returns pos to 0 and clears overflow. */
    mmgr_span (*after)(const SpatiumCfg *args);        /**< The span beginning count bytes in. */
    mmgr_span (*first)(const SpatiumCfg *args);        /**< The span covering only the first count bytes. */
    mmgr_cspan (*produced)(const SpatiumCfg *args);    /**< A read span over everything written. */
    mmgr_cspan (*read)(const SpatiumCfg *args);        /**< A read span over the first count written. */
} SpatiumNs;
EMBED_TABLE_LAYOUT(SpatiumNs, from, cfrom, ok, cok, has_storage, reset, after, first, produced, read);

/**
 * @brief Builds a fill span over args->buf, with pos at 0 and overflow clear.
 *
 * @param[in] args Buffer buf and its extent cap [BORROWS].
 * @return         The span, by value.
 * @note Asserts args->buf is not NULL and args->cap is not 0. The default MMGR_ASSERT leaves both
 *       unevaluated.
 * @warning The span carries args->buf away, so that buffer must outlive every use of the span [BORROWS].
 */
mmgr_span mmgr_spat_from(const SpatiumCfg *args);

/**
 * @brief Builds a read span over args->cbuf, with pos at 0 and err clear.
 *
 * @param[in] args Buffer cbuf and its extent cap [BORROWS].
 * @return         The span, by value.
 * @note cbuf rather than buf, so a buffer that may not be written cannot reach the fill constructor.
 * @note Takes cbuf and cap as handed over, with none of the asserts mmgr_spat_from makes. A null cbuf
 *       or a zero cap still builds, and mmgr_spat_cok is what reports the span unusable.
 * @warning The span carries args->cbuf away, so that buffer must outlive every use of the span [BORROWS].
 */
mmgr_cspan mmgr_spat_cfrom(const SpatiumCfg *args);

/**
 * @brief Returns whether args->span has storage and has not overflowed.
 *
 * @param[in] args Span to test, as args->span [BORROWS].
 * @return         EMBED_TRUE when the span is still usable.
 */
embed_bool mmgr_spat_ok(const SpatiumCfg *args);

/**
 * @brief Returns whether args->cspan has storage and has recorded no error.
 *
 * @param[in] args Read span to test, as args->cspan [BORROWS].
 * @return         EMBED_TRUE when the span is still usable.
 */
embed_bool mmgr_spat_cok(const SpatiumCfg *args);

/**
 * @brief Returns whether args->span covers any bytes at all.
 *
 * @param[in] args Span to test, as args->span [BORROWS].
 * @return         EMBED_TRUE when buf is not NULL and cap is not 0.
 */
embed_bool mmgr_spat_has_storage(const SpatiumCfg *args);

/**
 * @brief Returns the span at args->at to its start and clears its overflow.
 *
 * @param[in,out] args Span to rewind, as args->at [BORROWS].
 * @note The one entry that takes a span by pointer, because it is the one that changes one.
 * @note The one call that clears overflow, which is otherwise sticky for the span's whole life.
 * @warning args->at is written through with no check of its own, so it must point at a live span. The
 *          const on the pack covers the pack, not the span at the far end of at.
 */
void mmgr_spat_reset(const SpatiumCfg *args);

/**
 * @brief Returns the span beginning args->count bytes into args->span.
 *
 * @param[in] args Span to walk, as args->span, and the bytes to skip as args->count [BORROWS].
 * @return         A span over what is left, or a failed span when args->count is past cap.
 * @note The span that comes back covers the same buffer args->span does [BORROWS]: a second view of
 *       those bytes rather than a copy, so a write through either is seen by both.
 * @note An args->count of exactly cap gives an empty span that has not failed: nothing is left, but
 *       nothing went wrong either.
 */
mmgr_span mmgr_spat_after(const SpatiumCfg *args);

/**
 * @brief Returns the span covering only the first args->count bytes of args->span.
 *
 * @param[in] args Span to narrow, as args->span, and the bytes to keep as args->count [BORROWS].
 * @return         A span over those bytes, or a failed span when args->count is past cap.
 * @note The span that comes back starts on the same byte args->span starts on [BORROWS], holding a
 *       shorter cap over the same storage, so a fill through one is read by the other.
 */
mmgr_span mmgr_spat_first(const SpatiumCfg *args);

/**
 * @brief Returns a read span over everything written into args->span.
 *
 * @param[in] args Span to read back, as args->span [BORROWS].
 * @return         A read span over its first pos bytes, carrying span's overflow as its err.
 * @note The same step as mmgr_spat_read against span's own pos, which is the case that cannot ask for
 *       more than was written and so cannot fail on its own account.
 */
mmgr_cspan mmgr_spat_produced(const SpatiumCfg *args);

/**
 * @brief Returns a read span over the first args->count bytes written into args->span.
 *
 * @param[in] args Span to read back, as args->span, and the bytes to cover as args->count [BORROWS].
 * @return         A read span over them, marked err when args->count is past what was written.
 * @warning The read span points at the fill span's own bytes [BORROWS], and the const on it binds this
 *          view, not the storage. Filling args->span again moves what the reader sees, so read it back
 *          before the next fill or copy the bytes out.
 */
mmgr_cspan mmgr_spat_read(const SpatiumCfg *args);

/**
 * @brief Dispatch table instance named spat, with each member set to its mmgr_spat_ function.
 */
EMBED_TABLE_STORAGE SpatiumNs spat EMBED_UNUSED = {
    .from = mmgr_spat_from,
    .cfrom = mmgr_spat_cfrom,
    .ok = mmgr_spat_ok,
    .cok = mmgr_spat_cok,
    .has_storage = mmgr_spat_has_storage,
    .reset = mmgr_spat_reset,
    .after = mmgr_spat_after,
    .first = mmgr_spat_first,
    .produced = mmgr_spat_produced,
    .read = mmgr_spat_read,
};

EMBED_END_DECLS

#endif
