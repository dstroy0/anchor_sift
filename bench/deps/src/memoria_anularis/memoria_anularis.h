/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoria_anularis.h
 * @brief Single-producer, single-consumer byte ring, a segment view over it, and loculus keepouts.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Nothing of the implementation is spelled here. mmgr_ring is a run of opaque bytes, and the
 *       state laid into it is declared nowhere a consumer can reach. That is what lets the layout
 *       change without a consumer recompiling against a different struct.
 * @note The caller declares the ring and supplies the bytes; every index, mask and span is the ring's.
 * @note Exactly one producer advances head and exactly one consumer advances tail, so ordering is
 *       all that is needed and no entry takes a lock or a read-modify-write on those two.
 * @note No byte of the ring is ever scrubbed, and a drop leaves the loculus record alone, so a
 *       restream can run again. Only mmgr_anular_init clears those records.
 */
#ifndef MMGR_MEMORIA_ANULARIS_H
#define MMGR_MEMORIA_ANULARIS_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief A byte region a held loculus keeps out: the storage, its extent, and how far a reader has gone.
 *
 * @note Carried here rather than taken from spatium, so this module reaches nothing outside config.
 */
typedef struct
{
    uint8_t *buf;       /**< First byte of the region [BORROWS]. */
    size_t bytes;       /**< Bytes at buf. */
    size_t read_offset; /**< How far a reader has walked it, counted in bytes from buf. */
} mmgr_ring_span;

/**
 * @brief Size of the ring storage a caller declares, counted in size_t units.
 *
 * @note The implementation asserts its state fits inside this, so a change there fails a build
 *       rather than overrunning a caller's object.
 * @note Most of the state is the keepout array, so raising MMGR_RING_LOCULI grows it and may leave
 *       this short. The assertion below RingState in memoria_anularis.c is the one that
 *       fails then.
 * @note A build sets this before including this header, the same way it sets the loculus count.
 */
#ifndef MMGR_RING_WORDS

#define MMGR_RING_WORDS 40u
#endif

/**
 * @brief Loculi a mask can address, which is one bit per loculus in a machine word.
 *
 * @warning A build declaring more loculi than this has no bit left to name them. Widening the two
 *          masks or replacing them with a scan is what raises the ceiling. The assertion below fails
 *          until one of those happens.
 */
#define MMGR_RING_LOCULI_MAX EMBED_WORD_BITS

/**
 * @brief Loculi this build reserves, which a build may set before including this header.
 *
 * @note The keepout spans are most of the ring's state, so a build with no use for the loculus view
 *       sets this to 0 and can then lower MMGR_RING_WORDS. Setting this alone shrinks the state. The
 *       storage a caller declares follows MMGR_RING_WORDS alone.
 * @note At 0, mmgr_anular_loculus_ready reports an empty mask, mmgr_anular_loculus_hold refuses every
 *       index, and mmgr_anular_loculus_keepout returns NULL. mmgr_anular_loculus_drop and
 *       mmgr_anular_loculus_mark leave both masks unchanged.
 */
#ifndef MMGR_RING_LOCULI

#define MMGR_RING_LOCULI 8u
#endif

/**
 * @brief Asserts the loculi a build declares fit in one machine word.
 *
 * @note The free and held masks are each one embed_word, one bit per loculus, so a count past
 *       MMGR_RING_LOCULI_MAX has no bit to sit in. ring_loculus_bit in memoria_anularis.c
 *       builds that bit by shifting, and this bound is what keeps the shift inside the word.
 */
EMBED_STATIC_ASSERT(
    MMGR_RING_LOCULI <= MMGR_RING_LOCULI_MAX,
    "the loculus masks are one machine word; widen them or fall back to a scan past MMGR_RING_LOCULI_MAX");

/**
 * @brief Reports whether count_ is a power of two.
 *
 * @param[in] count_ Count to test, either a byte capacity or a segment count.
 * @return           Non-zero when count_ has at most one bit set.
 * @warning Also reports non-zero for a count_ of 0. mmgr_anular_init tests for 0 on a line of its own.
 * @warning count_ appears twice in the expansion, so an argument with a side effect is evaluated twice.
 */
#define MMGR_RING_POW2(count_) (((count_) & ((count_) - 1u)) == 0u)

/**
 * @brief Wraps a ring offset back into a ring of capacity_ bytes.
 *
 * @param[in] index_    Offset to wrap, which may have run past the end of the buffer.
 * @param[in] capacity_ Ring size in bytes, a power of two.
 * @return              index_ masked into the range 0 through capacity_ minus one.
 * @warning Correct only because capacity_ is a power of two, which mmgr_anular_init enforces.
 */
#define MMGR_RING_WRAP(index_, capacity_) ((index_) & ((capacity_) - 1u))

/**
 * @brief Storage a caller declares for one ring, whose contents belong to the implementation.
 *
 * @note EMBED_ALIGN aligns opaque to size_t.
 * @note From mmgr_anular_init onward these bytes hold the buffer that call was given, which must
 *       outlive the ring [BORROWS].
 * @warning The bytes carry no layout a consumer can reach. RingState is defined in
 *          memoria_anularis.c and nowhere else, so the mmgr_anular_ entries are the
 *          only way into them.
 */
typedef struct
{
    EMBED_ALIGN(sizeof(size_t)) uint8_t opaque[MMGR_RING_WORDS * sizeof(size_t)]; /**< Private ring state. */
} mmgr_ring;

/**
 * @brief Declares a ring's storage and claims the pool it is laid over.
 *
 * @param[in] name_ Name the ring is reached by.
 * @param[in] pool_ Pool the ring covers, as ParsMemoriaeInternae or ParsMemoriaeExternum declared it
 *                  [BORROWS].
 * @note The claim is what keeps one pool from being dressed twice. A pool already holding a cellblock
 *       and then laid out as a ring carries two sets of records over the same bytes, each written
 *       without regard to the other, and nothing at run time reports it.
 * @note A declaration, because MMGR_PARS_CLAIMED_ONCE emits an enumerator and an enumerator inside a
 *       function body is block scoped. Put at the mmgr_anular_init call it would shadow the
 *       cellblock's and never collide.
 * @note Emits the storage and nothing in it. mmgr_anular_init lays the state into those bytes and
 *       still has to run, since the sizes it is handed can be refused.
 * @warning The pool is named here and named again at mmgr_anular_init. Nothing holds those two to the
 *          same pool. A ring declared over one pool and initialized over another compiles.
 */
#define MemoriaAnularis(name_, pool_)                                                                                  \
    MMGR_PARS_CLAIMED_ONCE(pool_);                                                                                     \
    static mmgr_ring name_

/**
 * @brief Arguments for every mmgr_anular_ entry, each reading only the members it needs.
 *
 * @note Every entry but mmgr_anular_loculus_next reads ring. mmgr_anular_init reads buf, capacity and
 *       segment_count on top of it.
 * @note Members left unset are zero, and the entries that ignore them never read them.
 */
typedef struct
{
    mmgr_ring *const ring;      /**< Ring to act on [BORROWS]. */
    uint8_t *const buf;         /**< Ring bytes, taken by mmgr_anular_init [BORROWS]. */
    const size_t capacity;      /**< Bytes at buf, a non-zero power of two. */
    const size_t segment_count; /**< Segments to divide the ring into, a power of two no larger than capacity. */
    uint8_t *const dst;         /**< Destination for read, read_byte and peek [BORROWS]. */
    const uint8_t *const src;   /**< Bytes put writes, or the region loculus_hold records [BORROWS]. */
    const size_t bytes;         /**< Byte count the call moves or records. */
    const size_t offset;        /**< Offset ahead of the tail that peek starts at. */
    const size_t index;         /**< Loculus or segment the call acts on. */
    const embed_word mask;      /**< Mask loculus_next picks the lowest set bit of. */
    size_t *const out_index;    /**< Segment index seg_next and seg_front write into [BORROWS]. */
} AnularisCfg;

/**
 * @brief Type of the anularis dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the twenty members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note The twenty are mmgr_anular_init and three layers over the same bytes, and that call lays all
 *       three down. Seven members follow it for the byte ring, six for the segment view, and six for
 *       the loculi.
 */
typedef struct
{
    embed_bool (*init)(const AnularisCfg *args);          /**< Lays a fresh ring into the caller's storage. */
    size_t (*available)(const AnularisCfg *args);         /**< Bytes waiting to be read. */
    size_t (*vacant)(const AnularisCfg *args);            /**< Bytes still free to write. */
    embed_bool (*read_byte)(const AnularisCfg *args);     /**< Takes one byte and advances the tail. */
    size_t (*read)(const AnularisCfg *args);              /**< Takes up to bytes and advances the tail once. */
    void (*peek)(const AnularisCfg *args);                /**< Copies bytes out without advancing the tail. */
    void (*consume)(const AnularisCfg *args);             /**< Advances the tail past bytes. */
    embed_bool (*put)(const AnularisCfg *args);           /**< Writes a whole span, or refuses it entire. */
    size_t (*seg_inflight)(const AnularisCfg *args);      /**< Segments filled and not yet released. */
    embed_bool (*seg_next)(const AnularisCfg *args);      /**< Index of the segment the producer fills next. */
    void (*seg_publish)(const AnularisCfg *args);         /**< Makes the filled segment visible to the consumer. */
    embed_bool (*seg_front)(const AnularisCfg *args);     /**< Index of the segment the consumer takes next. */
    void (*seg_release)(const AnularisCfg *args);         /**< Frees the front segment. */
    uint8_t *(*seg_at)(const AnularisCfg *args);          /**< The contiguous span of one segment. */
    embed_word (*loculus_ready)(const AnularisCfg *args); /**< Loculi that are free and not held. */
    embed_iword (*loculus_next)(const AnularisCfg *args); /**< Lowest set bit of a mask, or -1. */
    embed_bool (*loculus_hold)(const AnularisCfg *args);  /**< Takes a loculus and records its keepout. */
    const mmgr_ring_span *(*loculus_keepout)(const AnularisCfg *args); /**< The region a held loculus keeps out. */
    void (*loculus_drop)(const AnularisCfg *args); /**< Gives a loculus back, leaving its bytes alone. */
    void (*loculus_mark)(const AnularisCfg *args); /**< Marks a loculus free. */
} MemoriaAnularisNs;
EMBED_TABLE_LAYOUT(MemoriaAnularisNs, init, available, vacant, read_byte, read, peek, consume, put, seg_inflight,
                   seg_next, seg_publish, seg_front, seg_release, seg_at, loculus_ready, loculus_next, loculus_hold,
                   loculus_keepout, loculus_drop, loculus_mark);

/**
 * @brief Lays a fresh ring into args->ring, over the bytes at args->buf.
 *
 * @param[in,out] args Storage, bytes, capacity and segment count [BORROWS].
 * @return             EMBED_TRUE when the ring is ready, EMBED_FALSE when a size was rejected.
 * @note Refuses a capacity or a segment_count that is 0 or not a power of two, and a segment_count
 *       above capacity.
 * @note Marks every loculus free and none held, and clears the recorded keepouts.
 * @warning args->ring and args->buf are both the caller's, and args->buf is kept by the ring [BORROWS].
 * @warning Neither may be null, and nothing holds them there outside a MMGR_DEBUG_CHECKS build. A null
 *          ring is written through as soon as the sizes pass, and a null buf is taken and not noticed
 *          until the first move.
 * @warning args->buf must carry the alignment the caller's own accesses need. This call does not
 *          align it.
 */
embed_bool mmgr_anular_init(const AnularisCfg *args);

/**
 * @brief Returns the bytes waiting to be read.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         Distance from the tail to the head, wrapped into the ring.
 * @warning The answer is only a snapshot. A concurrent producer may add more before the caller acts
 *          on it.
 */
size_t mmgr_anular_available(const AnularisCfg *args);

/**
 * @brief Returns the bytes still free to write.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The capacity mmgr_anular_init was given, less one, less the readable bytes.
 * @note One byte is held back always, which is what keeps a full ring apart from an empty one.
 * @warning The answer is only a snapshot. A concurrent consumer may free more before the caller acts
 *          on it.
 */
size_t mmgr_anular_vacant(const AnularisCfg *args);

/**
 * @brief Takes one byte into args->dst and advances the tail past it.
 *
 * @param[in,out] args Ring and the destination byte [BORROWS].
 * @return             EMBED_TRUE when a byte was taken, EMBED_FALSE when the ring was empty.
 * @note Writes through args->dst only when it returns EMBED_TRUE.
 * @note One byte per call, so the cost is the call and not the move. A caller drawing a run of bytes
 *       wants mmgr_anular_read, which moves them a word at a time under one tail store.
 * @warning args->dst must be writable for one byte.
 */
embed_bool mmgr_anular_read_byte(const AnularisCfg *args);

/**
 * @brief Takes up to args->bytes into args->dst and advances the tail once at the end.
 *
 * @param[in,out] args Ring, destination and the most to take [BORROWS].
 * @return             Bytes actually taken, which is 0 when the ring was empty.
 * @note Moves the bytes in at most two runs, so the wrap costs one extra move rather than one per byte.
 * @note Reads the tail once and publishes it once, not per byte.
 * @warning args->dst must be writable for args->bytes.
 */
size_t mmgr_anular_read(const AnularisCfg *args);

/**
 * @brief Copies args->bytes starting args->offset ahead of the tail into args->dst, leaving the tail
 *        alone.
 *
 * @param[in,out] args Ring, destination, byte count and starting offset [BORROWS].
 * @note Moves the bytes in at most two runs, the same way mmgr_anular_read does.
 * @warning Copies args->bytes whether or not that many have arrived. Read mmgr_anular_available first.
 * @warning An args->bytes above the ring's capacity is held there. Two runs cover one lap and no more.
 * @warning args->dst must be writable for args->bytes.
 */
void mmgr_anular_peek(const AnularisCfg *args);

/**
 * @brief Advances the tail past args->bytes.
 *
 * @param[in,out] args Ring and the byte count to drop [BORROWS].
 * @warning Advances whether or not that many have arrived. Read mmgr_anular_available first.
 */
void mmgr_anular_consume(const AnularisCfg *args);

/**
 * @brief Writes args->bytes of args->src into the ring, or refuses the whole span.
 *
 * @param[in,out] args Ring, the bytes to write and their count [BORROWS].
 * @return             EMBED_TRUE when the span was written, EMBED_FALSE when it would not fit.
 * @note Checks the whole span against the vacant bytes first, so a partial write never happens.
 * @note Advances a local head across the wrap and publishes it once, so no half span is ever visible.
 * @warning args->src must be readable for args->bytes.
 */
embed_bool mmgr_anular_put(const AnularisCfg *args);

/**
 * @brief Returns the segments filled and not yet released.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The distance between the claim and release counters.
 * @warning The two counters are read one after the other, so the answer is only a snapshot. A publish
 *          or a release may land between the reads, or after both.
 */
size_t mmgr_anular_seg_inflight(const AnularisCfg *args);

/**
 * @brief Reports the index of the segment the producer fills next.
 *
 * @param[in,out] args Ring, and where to write the index [BORROWS].
 * @return             EMBED_TRUE with the index in args->out_index, EMBED_FALSE when every segment is
 *                     in flight.
 * @note Writes through args->out_index only when it returns EMBED_TRUE.
 * @note Publishing is separate, so a half-filled segment is never visible to the consumer.
 * @note A EMBED_FALSE can go stale the moment the consumer releases a segment. A EMBED_TRUE cannot,
 *       since releases only make room.
 * @warning args->out_index must be writable.
 */
embed_bool mmgr_anular_seg_next(const AnularisCfg *args);

/**
 * @brief Makes the filled segment visible to the consumer.
 *
 * @param[in,out] args Ring to advance [BORROWS].
 * @note Only the producer calls this. The counter is read and written as two steps, which needs no
 *       atomicity between them only because one side owns it.
 * @warning Advances whether or not a segment was filled, so a publish with no matching
 *          mmgr_anular_seg_next puts more in flight than the ring holds, and that call then refuses
 *          until releases catch up.
 */
void mmgr_anular_seg_publish(const AnularisCfg *args);

/**
 * @brief Reports the index of the segment the consumer takes next.
 *
 * @param[in,out] args Ring, and where to write the index [BORROWS].
 * @return             EMBED_TRUE with the index in args->out_index, EMBED_FALSE when none is in flight.
 * @note Writes through args->out_index only when it returns EMBED_TRUE.
 * @note A EMBED_FALSE can go stale the moment the producer publishes a segment. A EMBED_TRUE cannot,
 *       since publishes only add.
 * @warning args->out_index must be writable.
 */
embed_bool mmgr_anular_seg_front(const AnularisCfg *args);

/**
 * @brief Frees the front segment.
 *
 * @param[in,out] args Ring to advance [BORROWS].
 * @note Segments release in the order they were claimed.
 * @note Only the consumer calls this. The counter is read and written as two steps, which needs no
 *       atomicity between them only because one side owns it.
 * @warning Advances whether or not a segment was in flight. A release past what has been published
 *          wraps the in-flight count and leaves mmgr_anular_seg_front handing out a segment that was
 *          never filled.
 */
void mmgr_anular_seg_release(const AnularisCfg *args);

/**
 * @brief Returns the contiguous span of segment args->index.
 *
 * @param[in] args Ring and the segment index [BORROWS].
 * @return         Its first byte inside the ring buffer [BORROWS].
 * @note The span runs for the capacity divided by the segment_count mmgr_anular_init was given.
 * @warning args->index is not checked against the segment count, and no assertion covers it. An index
 *          at or past that count returns a pointer outside the ring's bytes.
 */
uint8_t *mmgr_anular_seg_at(const AnularisCfg *args);

/**
 * @brief Returns the loculi that are free and not held.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The free mask with the held ones cleared, bounded to MMGR_RING_LOCULI.
 * @note A loculus is takeable only when it is free and not held, which is what makes reuse safe.
 * @warning The answer is only a snapshot. The two masks are read one after the other, and a hold or a
 *          drop may land before the caller acts on it. mmgr_anular_loculus_hold settles that race,
 *          refusing a loculus another caller took first.
 */
embed_word mmgr_anular_loculus_ready(const AnularisCfg *args);

/**
 * @brief Returns the index of the lowest set bit of args->mask.
 *
 * @param[in] args The mask to pick from [BORROWS].
 * @return         The index, or -1 when args->mask is empty.
 * @note Counts rather than scans, and branches on nothing but the empty mask.
 * @note Only args->mask is read. This is the one entry that never reaches the ring.
 * @warning The mask is taken as given. A bit at or above MMGR_RING_LOCULI comes back as its index,
 *          and that index names no loculus, so mmgr_anular_loculus_hold refuses it.
 */
embed_iword mmgr_anular_loculus_next(const AnularisCfg *args);

/**
 * @brief Takes loculus args->index and records the args->bytes at args->src that it keeps out.
 *
 * @param[in,out] args Ring, the loculus, and the region to record [BORROWS].
 * @return             EMBED_TRUE when this caller took it, EMBED_FALSE when args->index names none or
 *                     another caller already holds it.
 * @note The recorded region stays valid until mmgr_anular_loculus_drop, so a reader walks it in place.
 * @warning An out-of-range args->index names nothing, so it reads as held and is never handed out.
 * @warning args->src is kept by the ring and handed back by mmgr_anular_loculus_keepout, so it must
 *          outlive the hold [BORROWS].
 */
embed_bool mmgr_anular_loculus_hold(const AnularisCfg *args);

/**
 * @brief Returns the region loculus args->index is keeping out.
 *
 * @param[in] args Ring and the loculus [BORROWS].
 * @return         The recorded span, or NULL when args->index is out of range [BORROWS].
 * @note Handed back const, so a reader walks it without moving the ring's own record.
 * @warning The const covers the span and not the bytes it names. buf is reachable as a writable
 *          pointer, though the region reached mmgr_anular_loculus_hold as const.
 * @warning The record comes back for any loculus in range, held or not. A drop leaves it standing, so
 *          afterwards it still names the last region that loculus recorded [BORROWS].
 */
const mmgr_ring_span *mmgr_anular_loculus_keepout(const AnularisCfg *args);

/**
 * @brief Gives loculus args->index back.
 *
 * @param[in,out] args Ring and the loculus [BORROWS].
 * @note Leaves the recorded span and the bytes alone, so a restream can run again.
 * @note An out-of-range args->index names no bit and clears nothing, and dropping a loculus that is
 *       not held does nothing.
 */
void mmgr_anular_loculus_drop(const AnularisCfg *args);

/**
 * @brief Marks loculus args->index free.
 *
 * @param[in,out] args Ring and the loculus [BORROWS].
 * @note Sets the free bit. The held bit is mmgr_anular_loculus_drop's to clear, and a loculus is
 *       takeable only when it is free and not held.
 * @note mmgr_anular_init sets the free bit for every loculus and no entry clears it, so on a ring that
 *       call has laid down this changes nothing.
 * @note An out-of-range args->index names no bit and sets nothing.
 */
void mmgr_anular_loculus_mark(const AnularisCfg *args);

/**
 * @brief Dispatch table instance named anularis, whose members are the mmgr_anular_ entries.
 */
EMBED_TABLE_STORAGE MemoriaAnularisNs anularis EMBED_UNUSED = {
    .init = mmgr_anular_init,
    .available = mmgr_anular_available,
    .vacant = mmgr_anular_vacant,
    .read_byte = mmgr_anular_read_byte,
    .read = mmgr_anular_read,
    .peek = mmgr_anular_peek,
    .consume = mmgr_anular_consume,
    .put = mmgr_anular_put,
    .seg_inflight = mmgr_anular_seg_inflight,
    .seg_next = mmgr_anular_seg_next,
    .seg_publish = mmgr_anular_seg_publish,
    .seg_front = mmgr_anular_seg_front,
    .seg_release = mmgr_anular_seg_release,
    .seg_at = mmgr_anular_seg_at,
    .loculus_ready = mmgr_anular_loculus_ready,
    .loculus_next = mmgr_anular_loculus_next,
    .loculus_hold = mmgr_anular_loculus_hold,
    .loculus_keepout = mmgr_anular_loculus_keepout,
    .loculus_drop = mmgr_anular_loculus_drop,
    .loculus_mark = mmgr_anular_loculus_mark,
};

EMBED_END_DECLS

#endif
