/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoria_anularis.c
 * @brief Power-of-two byte ring, a segment view over the same bytes, and loculus keepouts.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note The state laid into mmgr_ring is defined here and nowhere else, so the public surface carries
 *       no layout.
 * @note head, tail, claimed, released, gratis and held are atomic. The spans and the sizes are plain.
 * @note A move across the wrap is two runs through ring_move, never a walk over single bytes.
 * @note ring_move and ring_loculus_bit are defined here and mmgr_ring_span in the header, so the
 *       module reaches no other module.
 */
#include "memoria_anularis/memoria_anularis.h"

#include <stdatomic.h>

/**
 * @brief The attributes that make an access at an arbitrary address legal.
 *
 * @note EMBED_ALIGN(1) relaxes the required alignment to one byte. EMBED_ALIAS permits the type to
 *       alias another.
 * @warning Either half expands to nothing where its attribute is unavailable. ring_move's accesses
 *          are ordinary ones then, which a target that traps unaligned loads will fault on.
 */
#define RING_RAW EMBED_ALIGN(1) EMBED_ALIAS

/**
 * @brief Bytes the mover steps at a time: 8 at EMBED_WORD_BITS 64 or more, 4 at 32 or more, 2 otherwise.
 */
#if EMBED_WORD_BITS >= 64
#define RING_STEP 8
#elif EMBED_WORD_BITS >= 32
#define RING_STEP 4
#else
#define RING_STEP 2
#endif

/**
 * @brief The unsigned type RING_STEP bytes wide.
 *
 * @note Named once here so ring_raw_word below, and the pointers ring_move walks through it, follow
 *       the build's step width without any of them naming a fixed type.
 */
#if RING_STEP >= 8
typedef embed_u64 ring_step_word;
#elif RING_STEP >= 4
typedef embed_u32 ring_step_word;
#else
typedef embed_u16 ring_step_word;
#endif

/**
 * @brief The unaligned view of one step, which both of ring_move's walking pointers go through.
 *
 * @note A ring offset is any byte, so neither side can be taken as aligned. The alias half of
 *       RING_RAW is what lets the uint8_t pointers ring_move is given be walked at this width.
 */
typedef ring_step_word ring_raw_word RING_RAW;

/**
 * @brief The first unaligned view the tail narrows to, four bytes wide.
 *
 * @note A tail is shorter than one step, so it is carried by a view of its own rather than by a step
 *       that would reach past what the caller gave.
 * @note Reached only at a RING_STEP of 8. A narrower step never leaves four bytes standing.
 */
typedef embed_u32 ring_raw_u32 RING_RAW;

/**
 * @brief The unaligned view below it, two bytes wide.
 *
 * @note Reached at a RING_STEP of 4 or more.
 * @note The byte rung under this one needs no view of its own, since a byte carries no alignment to
 *       relax and already aliases anything.
 */
typedef embed_u16 ring_raw_u16 RING_RAW;

/**
 * @brief Builds the mask of the lowest bit_count_ bits of type Type_.
 *
 * @param[in] Type_      Unsigned type the mask is built at.
 * @param[in] bit_count_ Bits to set.
 * @param[in] width_     Width of Type_ in bits.
 * @return               A Type_ with its low bit_count_ bits set.
 * @note A bit_count_ at the full width is the case a shift cannot express, so it is answered by
 *       complement instead. A bit_count_ of 0 falls out of the shift, so neither end needs a test of
 *       its own.
 * @warning bit_count_ appears twice in the expansion, so an argument with a side effect is evaluated
 *          twice whenever the mask is built by the shift.
 */
#define RING_LOW_MASK(Type_, bit_count_, width_)                                                                       \
    (((bit_count_) >= (width_)) ? (Type_) ~(Type_)0 : (Type_)(((Type_)(((Type_)1) << (bit_count_))) - (Type_)1))

/**
 * @brief Copies two words at offset offset_ of the mover's walking pointers.
 *
 * @param[in] offset_ First of the two word offsets.
 * @note Reads dest_word and src_word from the enclosing scope, so the cascade below reads as widths
 *       alone.
 * @warning offset_ appears four times in the expansion, so an argument with a side effect is
 *          evaluated four times.
 * @warning Both offsets must lie inside the words dest_word and src_word walk over, and nothing here
 *          bounds them. ring_move is what holds them there, by taking a rung only when the remaining
 *          word count has that bit set.
 */
#define RING_COPY_2(offset_)                                                                                           \
    dest_word[(offset_)] = src_word[(offset_)];                                                                        \
    dest_word[(offset_) + 1] = src_word[(offset_) + 1]

/**
 * @brief Copies four words at offset offset_, as two runs of two.
 *
 * @param[in] offset_ First of the four word offsets.
 * @note Carries both of RING_COPY_2's warnings. offset_ reaches the expansion eight times through
 *       the two runs, and the four offsets are bounded by ring_move rather than here.
 */
#define RING_COPY_4(offset_)                                                                                           \
    RING_COPY_2(offset_);                                                                                              \
    RING_COPY_2((offset_) + 2)

/**
 * @brief Copies eight words at offset offset_, as two runs of four.
 *
 * @param[in] offset_ First of the eight word offsets.
 * @note Carries the same two warnings down the cascade. offset_ reaches the expansion sixteen times,
 *       and the eight offsets are bounded by ring_move rather than here.
 */
#define RING_COPY_8(offset_)                                                                                           \
    RING_COPY_4(offset_);                                                                                              \
    RING_COPY_4((offset_) + 4)

/**
 * @brief Carries bytes_ bytes of the tail through type Type_ when the tail still holds that many.
 *
 * @param[in] Type_  Type bytes_ wide the copy goes through, an unaligned view above one byte.
 * @param[in] bytes_ Bytes this rung carries, always a single bit.
 * @note Reads dest_byte, src_byte and remainder from the enclosing scope, so the cascade reads as
 *       widths alone.
 * @note One rung per bit of remainder, so each runs at most once and together they carry every tail
 *       exactly, without an access reaching past the bytes the caller gave.
 * @warning bytes_ appears three times in the expansion, so an argument with a side effect is
 *          evaluated three times.
 */
#define RING_TAIL(Type_, bytes_)                                                                                       \
    if ((remainder & (bytes_)) != 0u)                                                                                  \
    {                                                                                                                  \
        *(Type_ *)dest_byte = *(const Type_ *)src_byte;                                                                \
        dest_byte += (bytes_);                                                                                         \
        src_byte += (bytes_);                                                                                          \
    }

/**
 * @brief Moves bytes bytes from src to dst at any alignment.
 *
 * @param[out] dst   Destination [BORROWS].
 * @param[in]  src   Source [BORROWS].
 * @param[in]  bytes Bytes to move.
 * @note Steps whole words, then narrows through half a step at a time for the tail, so a tail of
 *       seven bytes is three accesses rather than seven and none of them is a single byte twice.
 * @note Both sides go through the unaligned view. A ring offset is any byte, so neither pointer can
 *       be walked to a boundary first without putting a per-byte head back.
 * @note Every access lies inside bytes. The tail narrows rather than masking a whole step, so
 *       neither region needs room past what the caller gave, and the destination is written, never
 *       read.
 * @warning The two regions must not overlap.
 */
EMBED_INLINE void ring_move(uint8_t *dst, const uint8_t *src, size_t bytes)
{
    // Explicit casts put the step at size_t, holding the divide and the multiply in the type bytes
    // arrives in rather than the int RING_STEP expands to
    size_t words = bytes / (size_t)RING_STEP;
    const size_t remainder = bytes - (words * (size_t)RING_STEP);
    // Explicit casts take the byte pointers to the unaligned word view the loop below steps through,
    // which is what makes a step at an address of any alignment legal
    ring_raw_word *dest_word = (ring_raw_word *)dst;
    const ring_raw_word *src_word = (const ring_raw_word *)src;

    // Here and in the three rungs below, the two pointers and the remaining word count step on lines
    // of their own after the copy, so none of them is a side effect inside the macro that copied
    while (words >= 8u)
    {
        RING_COPY_8(0);
        dest_word += 8;
        src_word += 8;
        words -= 8u;
    }
    if ((words & 4u) != 0u)
    {
        RING_COPY_4(0);
        dest_word += 4;
        src_word += 4;
    }
    if ((words & 2u) != 0u)
    {
        RING_COPY_2(0);
        dest_word += 2;
        src_word += 2;
    }
    if ((words & 1u) != 0u)
    {
        dest_word[0] = src_word[0];
        dest_word += 1;
        src_word += 1;
    }

    // Explicit casts bring the walked pointers back to bytes for the narrowing tail below
    uint8_t *dest_byte = (uint8_t *)dest_word;
    const uint8_t *src_byte = (const uint8_t *)src_word;

#if RING_STEP >= 8
    RING_TAIL(ring_raw_u32, 4u)
#endif
#if RING_STEP >= 4
    RING_TAIL(ring_raw_u16, 2u)
#endif
    RING_TAIL(uint8_t, 1u)
}

/**
 * @brief A word holding 1 in every octet, which is 0x0101...01.
 *
 * @note Multiplying a per-octet count by this sums every octet into the top one.
 */
#define RING_ONES ((embed_word)(((embed_word) ~(embed_word)0) / 0xFFu))

/**
 * @brief A word holding 0x55 in every octet, which pairs the bits for the first fold.
 */
#define RING_PAIRS ((embed_word)(((embed_word) ~(embed_word)0) / 3u))

/**
 * @brief A word holding 0x33 in every octet, which pairs the counts for the second fold.
 */
#define RING_QUADS ((embed_word)(((embed_word) ~(embed_word)0) / 5u))

/**
 * @brief A word holding 0x0F in every octet, which holds each octet's count after the third fold.
 */
#define RING_OCTETS ((embed_word)(((embed_word) ~(embed_word)0) / 17u))

/**
 * @brief Counts the zero bits below the lowest set bit of mask.
 *
 * @param[in] mask Value to measure.
 * @return         Trailing zero count, 0 through EMBED_WORD_BITS.
 * @note Isolating the lowest set bit and taking one off leaves exactly that many bits set, so the
 *       trailing zero count is a population count.
 * @note The count folds in place a lane at a time, then one multiply sums every octet into the top
 *       one, which the final shift reads out. Every constant is derived from the word, so the same
 *       four steps run at any width.
 * @note No step branches on the value.
 * @warning A mask of 0 returns EMBED_WORD_BITS. anular_loculus_next, the one caller, tests for an
 *          empty mask first.
 */
EMBED_INLINE embed_iword ring_trail(embed_word mask)
{
    // Explicit casts hold the two's complement negation, the one taken off and the subtraction all at
    // embed_word. The first isolates the lowest set bit, and taking one off it leaves the trailing
    // zeros standing as set bits
    embed_word folded = (embed_word)((mask & (embed_word)(0u - mask)) - (embed_word)1);

    // Explicit casts hold each fold at embed_word: pairs, then quads, then whole octets
    folded = (embed_word)(folded - ((folded >> 1) & RING_PAIRS));
    folded = (embed_word)((folded & RING_QUADS) + ((folded >> 2) & RING_QUADS));
    folded = (embed_word)((folded + (folded >> 4)) & RING_OCTETS);
    // Explicit casts hold the summing multiply at embed_word, then take the top octet it lands the
    // whole count in into the embed_iword this returns
    return (embed_iword)((embed_word)(folded * RING_ONES) >> (EMBED_WORD_BITS - 8u));
}

/**
 * @brief Acquire load of an atomic member.
 *
 * @param[in] address_ Address of the atomic to read [BORROWS].
 * @return             The value read.
 * @note Acquire ordering, so writes released by the other side are visible after it.
 */
#define MMGR_ATOMIC_LOAD(address_) atomic_load_explicit((address_), memory_order_acquire)

/**
 * @brief Release store to an atomic member.
 *
 * @param[in,out] address_ Address of the atomic to write [BORROWS].
 * @param[in]     value_   Value to store.
 * @note Release ordering, so buffer writes made before it are visible to an acquiring reader.
 */
#define MMGR_ATOMIC_STORE(address_, value_) atomic_store_explicit((address_), (value_), memory_order_release)

/**
 * @brief The whole ring state, laid into the caller's mmgr_ring storage.
 *
 * @warning Reached by casting mmgr_ring::opaque. The assertion below checks it fits inside.
 */
typedef struct
{
    uint8_t *buf;              /**< Ring bytes [BORROWS]. */
    size_t capacity;           /**< Bytes at buf, always a power of two. */
    size_t segment_count;      /**< Segments the ring is divided into, a power of two. */
    size_t segment_bytes;      /**< Bytes per segment, capacity divided by segment_count. */
    _Atomic size_t head;       /**< Write position, advanced by the producer. */
    _Atomic size_t tail;       /**< Read position, advanced by the consumer. */
    _Atomic size_t claimed;    /**< Segments the producer has filled, counting up. */
    _Atomic size_t released;   /**< Segments the consumer has released, counting up. */
    _Atomic embed_word gratis; /**< One bit per loculus, set while that loculus is free to take. */
    _Atomic embed_word held;   /**< One bit per loculus, set while it still owns bytes in flight. */
    /**
     * @brief Region each held loculus keeps out, recorded at the hold.
     *
     * @note Sized to one entry when MMGR_RING_LOCULI is 0, since C has no zero-length array. That
     *       entry is unreachable, since ring_loculus_bit and anular_loculus_keepout both refuse every
     *       index then.
     * @note The buf an entry records points at the caller's region. The ring neither writes through
     *       it nor frees it, and it must outlive the hold [BORROWS].
     */
    mmgr_ring_span keepout[(MMGR_RING_LOCULI > 0u) ? MMGR_RING_LOCULI : 1u];
} RingState;

EMBED_STATIC_ASSERT(sizeof(RingState) <= sizeof(mmgr_ring),
                    "MMGR_RING_WORDS is short: a consumer cannot declare room for the ring");

/**
 * @brief Arguments for every backend in this file, grouped by the calls that read them.
 *
 * @note Each backend reads one group. EMBED_CALL zeroes the members it is not given.
 * @note Not a mirror of AnularisCfg. RING_S turns that type's ring into the state pointer here, and its
 *       buf, capacity and segment_count have no counterpart, since mmgr_anular_init is written by
 *       hand and reads AnularisCfg without building one of these.
 */
typedef struct
{
    RingState *state;   /**< Ring state to act on [BORROWS]. */
    uint8_t *dst;       /**< Destination for read, read_byte and peek [BORROWS]. */
    const uint8_t *src; /**< Bytes put writes, or the region loculus_hold records [BORROWS]. */
    size_t bytes;       /**< Byte count the call moves or records. */
    size_t offset;      /**< Offset ahead of the tail that peek starts at. */
    size_t index;       /**< Loculus or segment the call acts on. */
    embed_word mask;    /**< Mask loculus_next picks the lowest set bit of. */
    size_t *out_index;  /**< Segment index seg_next and seg_front write into [BORROWS]. */
} AnularisCtx;

/**
 * @brief Reads the ring state out of the caller's opaque storage.
 *
 * @param[in] ring Ring storage the caller declared [BORROWS].
 * @return         The state laid into it [BORROWS].
 * @note The cast goes through void *. mmgr_ring aligns opaque to size_t.
 * @warning The state is only valid after mmgr_anular_init has returned EMBED_TRUE for this ring.
 * @warning That alignment is size_t and no more, so the cast holds only while no member of RingState
 *          needs a stricter one. The assertion below the type checks its size, and nothing checks
 *          this.
 */
EMBED_INLINE RingState *ring_of(mmgr_ring *ring)
{
    return (RingState *)(void *)ring->opaque;
}

/**
 * @brief Returns the bit naming loculus index, or 0 when index names none.
 *
 * @param[in] index Loculus index.
 * @return          The bit, or 0.
 * @note The bound is here rather than at each call site, so a shift past the word never happens.
 * @note An out-of-range loculus names nothing, so it reads as held and is never handed out.
 */
EMBED_INLINE embed_word ring_loculus_bit(size_t index)
{
#if MMGR_RING_LOCULI == 0u
    // A build with no loculi names none, so the bound below would compare against zero and always hold
    (void)index;
    return (embed_word)0;
#else
    if (index >= (size_t)MMGR_RING_LOCULI)
    {
        return (embed_word)0;
    }
    // Explicit casts build the loculus bit at embed_word width, matching the masks it is tested against
    return (embed_word)((embed_word)1 << index);
#endif
}

/**
 * @brief Returns every loculus below MMGR_RING_LOCULI, as a mask.
 *
 * @return The mask.
 * @note Full width when the loculus count fills the word, which is the case a shift could not build.
 */
EMBED_INLINE embed_word ring_loculus_all(void)
{
    // Explicit casts put the declared count and the ceiling at size_t, the one type RING_LOW_MASK
    // compares them in
    return RING_LOW_MASK(embed_word, (size_t)MMGR_RING_LOCULI, (size_t)MMGR_RING_LOCULI_MAX);
}

/**
 * @brief How a move of wanted bytes from a ring offset divides across the wrap.
 */
typedef struct
{
    size_t bytes;       /**< Bytes the move will actually carry. */
    size_t before_wrap; /**< Bytes of that lying before the end of the buffer. */
} RingRun;

/**
 * @brief Divides a move at the end of the buffer.
 *
 * @param[in] state  Ring state [BORROWS].
 * @param[in] offset Ring offset to start from.
 * @param[in] wanted Bytes the caller asked for.
 * @return           The count to carry and how much of it precedes the wrap.
 * @note Both directions divide the same way, so the arithmetic lives here once.
 * @warning wanted is held at the capacity. Two runs cannot express more than one lap, so a larger
 *          count would take the second run past the end of the buffer.
 * @warning offset is not held to anything. The room ahead of it is the capacity minus offset, so an
 *          offset at or past the capacity wraps that subtraction and the first run then reaches past
 *          the buffer. What holds it instead is that every cursor reaching here is one the ring
 *          keeps wrapped.
 */
EMBED_INLINE RingRun ring_run(const RingState *state, size_t offset, size_t wanted)
{
    const size_t bytes = (wanted > state->capacity) ? state->capacity : wanted;
    const size_t room = state->capacity - offset;
    RingRun run;

    run.bytes = bytes;
    run.before_wrap = (room < bytes) ? room : bytes;
    return run;
}

/**
 * @brief Moves want bytes out of the ring from offset at, in at most two runs.
 *
 * @param[in]  state  Ring state [BORROWS].
 * @param[in]  offset Ring offset to start from.
 * @param[out] dst    Destination [BORROWS].
 * @param[in]  wanted Bytes to move.
 * @return            The offset one past what was moved, wrapped.
 * @note The first pass stops at the end of the buffer and the second takes whatever wrapped, so the
 *       wrap costs one extra pass rather than a test on every byte.
 * @note A loop rather than a pass and a guarded second one, so the mover is emitted once instead of
 *       twice. Two copies of it made this entry too large to inline well, which cost far more than
 *       the loop does.
 * @warning dst must hold wanted bytes, or the capacity of them when wanted is larger, and must not
 *          lie inside the ring's own bytes, which is the non-overlap ring_move requires. Neither is
 *          checked.
 */
EMBED_INLINE size_t ring_move_out(RingState *state, size_t offset, uint8_t *dst, size_t wanted)
{
    const RingRun run = ring_run(state, offset, wanted);
    size_t done = 0u;
    size_t from = offset;
    size_t bytes = run.before_wrap;

    while (done < run.bytes)
    {
        ring_move(dst + done, &state->buf[from], bytes);
        done += bytes;
        // The second pass starts at the buffer's first byte and carries whatever wrapped
        from = 0u;
        bytes = run.bytes - done;
    }
    return MMGR_RING_WRAP(offset + run.bytes, state->capacity);
}

/**
 * @brief Moves want bytes into the ring at offset at, in at most two runs.
 *
 * @param[in,out] state  Ring state [BORROWS].
 * @param[in]     offset Ring offset to start at.
 * @param[in]     src    Source bytes [BORROWS].
 * @param[in]     wanted Bytes to move.
 * @return               The offset one past what was moved, wrapped.
 * @note The mirror of ring_move_out, and the reason a fill and a drain cost the same per byte.
 * @warning src must hold wanted bytes, or the capacity of them when wanted is larger, and must not
 *          lie inside the ring's own bytes, which is the non-overlap ring_move requires. Neither is
 *          checked.
 */
EMBED_INLINE size_t ring_move_in(RingState *state, size_t offset, const uint8_t *src, size_t wanted)
{
    const RingRun run = ring_run(state, offset, wanted);
    size_t done = 0u;
    size_t to = offset;
    size_t bytes = run.before_wrap;

    while (done < run.bytes)
    {
        ring_move(&state->buf[to], src + done, bytes);
        done += bytes;
        // The second pass starts at the buffer's first byte and carries whatever wrapped
        to = 0u;
        bytes = run.bytes - done;
    }
    return MMGR_RING_WRAP(offset + run.bytes, state->capacity);
}

/**
 * @brief Returns the readable bytes between two cursors already in hand.
 *
 * @param[in] head     Head the caller read.
 * @param[in] tail     Tail the caller read.
 * @param[in] capacity Ring size.
 * @return             Distance from tail to head, wrapped into the ring.
 * @note Takes the cursors rather than the ring, so a caller holding one of them from its own load
 *       reaches the same arithmetic without reading it twice.
 */
EMBED_INLINE size_t ring_used(size_t head, size_t tail, size_t capacity)
{
    return MMGR_RING_WRAP(head - tail, capacity);
}

/**
 * @brief Returns the writable bytes between two cursors already in hand.
 *
 * @param[in] head     Head the caller read.
 * @param[in] tail     Tail the caller read.
 * @param[in] capacity Ring size.
 * @return             capacity minus one, minus the readable bytes.
 * @note One byte is withheld so a full ring and an empty one do not share a cursor pair.
 */
EMBED_INLINE size_t ring_free(size_t head, size_t tail, size_t capacity)
{
    return (capacity - 1u) - ring_used(head, tail, capacity);
}

/**
 * @brief Returns the bytes the consumer may still read.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         Distance from tail to head, wrapped into the ring.
 * @warning The head and the tail are read one after the other, so this is only a snapshot. A
 *          producer may add more between the two loads, or after both.
 */
EMBED_INLINE size_t anular_available(const AnularisCtx *args)
{
    return ring_used(MMGR_ATOMIC_LOAD(&args->state->head), MMGR_ATOMIC_LOAD(&args->state->tail), args->state->capacity);
}

/**
 * @brief Returns the bytes the producer may still write.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The capacity minus one, minus the readable bytes.
 * @warning The head and the tail are read one after the other, so this is only a snapshot. A
 *          consumer may free more between the two loads, or after both.
 */
EMBED_INLINE size_t anular_vacant(const AnularisCtx *args)
{
    return ring_free(MMGR_ATOMIC_LOAD(&args->state->head), MMGR_ATOMIC_LOAD(&args->state->tail), args->state->capacity);
}

/**
 * @brief Takes one byte from the tail and advances past it.
 *
 * @param[in,out] args Ring and the destination byte [BORROWS].
 * @return             EMBED_TRUE when a byte was taken, EMBED_FALSE when the ring was empty.
 * @note Writes through args->dst only on the EMBED_TRUE path. An empty ring leaves it untouched.
 * @warning args->dst must be writable for one byte, and nothing here checks it.
 */
EMBED_INLINE embed_bool anular_read_byte(const AnularisCtx *args)
{
    const size_t tail = MMGR_ATOMIC_LOAD(&args->state->tail);

    if (tail == MMGR_ATOMIC_LOAD(&args->state->head))
    {
        return EMBED_FALSE;
    }
    *args->dst = args->state->buf[tail];
    MMGR_ATOMIC_STORE(&args->state->tail, MMGR_RING_WRAP(tail + 1u, args->state->capacity));
    return EMBED_TRUE;
}

/**
 * @brief Takes up to args->bytes into args->dst and advances the tail once at the end.
 *
 * @param[in,out] args Ring, destination and the most to take [BORROWS].
 * @return             Bytes actually taken.
 * @note Publishes the tail once, after the move, rather than per byte.
 * @warning args->dst must be writable for as many bytes as this takes, which is at most
 *          args->bytes, and nothing here checks it.
 */
EMBED_INLINE size_t anular_read(const AnularisCtx *args)
{
    const size_t tail = MMGR_ATOMIC_LOAD(&args->state->tail);
    const size_t have = ring_used(MMGR_ATOMIC_LOAD(&args->state->head), tail, args->state->capacity);
    const size_t bytes = (have < args->bytes) ? have : args->bytes;

    MMGR_ATOMIC_STORE(&args->state->tail, ring_move_out(args->state, tail, args->dst, bytes));
    return bytes;
}

/**
 * @brief Copies args->bytes out of the ring starting args->offset past the tail, leaving the tail
 *        alone.
 *
 * @param[in,out] args Ring, destination, byte count and starting offset [BORROWS].
 * @warning Copies args->bytes whether or not that many are available.
 * @warning ring_run holds the count at the capacity, so a request above it copies the capacity and
 *          no more.
 * @warning args->dst must be writable for the bytes copied, and nothing here checks it.
 */
EMBED_INLINE void anular_peek(const AnularisCtx *args)
{
    const size_t at = MMGR_RING_WRAP(MMGR_ATOMIC_LOAD(&args->state->tail) + args->offset, args->state->capacity);

    (void)ring_move_out(args->state, at, args->dst, args->bytes);
}

/**
 * @brief Advances the tail past args->bytes.
 *
 * @param[in,out] args Ring and the byte count to drop [BORROWS].
 * @warning Advances whether or not that many have arrived. A count past the readable bytes puts the
 *          tail beyond the head, and anular_available then reports the capacity less the overshoot
 *          rather than nothing.
 */
EMBED_INLINE void anular_consume(const AnularisCtx *args)
{
    MMGR_ATOMIC_STORE(&args->state->tail,
                      MMGR_RING_WRAP(MMGR_ATOMIC_LOAD(&args->state->tail) + args->bytes, args->state->capacity));
}

/**
 * @brief Writes args->bytes of args->src into the ring, or refuses the whole span.
 *
 * @param[in,out] args Ring, the bytes to write and their count [BORROWS].
 * @return             EMBED_TRUE when the span was written, EMBED_FALSE when it would not fit.
 * @note The head stays local across the move and is published once, so no half span is visible.
 * @warning args->src must be readable for args->bytes, and nothing here checks it.
 */
EMBED_INLINE embed_bool anular_put(const AnularisCtx *args)
{
    const size_t head = MMGR_ATOMIC_LOAD(&args->state->head);

    if (args->bytes > ring_free(head, MMGR_ATOMIC_LOAD(&args->state->tail), args->state->capacity))
    {
        return EMBED_FALSE;
    }
    MMGR_ATOMIC_STORE(&args->state->head, ring_move_in(args->state, head, args->src, args->bytes));
    return EMBED_TRUE;
}

/**
 * @brief Returns the segments filled and not yet released.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The distance between the two counters.
 * @warning The two counters are read one after the other, so the answer is only a snapshot. A
 *          publish or a release may land between the reads, or after both.
 */
EMBED_INLINE size_t anular_seg_inflight(const AnularisCtx *args)
{
    return MMGR_ATOMIC_LOAD(&args->state->claimed) - MMGR_ATOMIC_LOAD(&args->state->released);
}

/**
 * @brief Hands back the segment a counter names, when its side says one is there.
 *
 * @param[in,out] args         Ring, and where to write the index [BORROWS].
 * @param[in]     cursor       Counter naming the segment.
 * @param[in]     have_segment Whether the caller's side has a segment to give.
 * @return                     have_segment, and args->out_index is only written when it holds.
 * @note Both ends reduce to this. The counter is wrapped into range and reported, and only the test
 *       for whether a segment exists differs, so each end keeps its own and passes the answer down.
 * @warning args->out_index must be writable whenever have_segment holds, and nothing here checks it.
 */
EMBED_INLINE embed_bool ring_seg_pick(const AnularisCtx *args, size_t cursor, embed_bool have_segment)
{
    if (!have_segment)
    {
        return EMBED_FALSE;
    }
    *args->out_index = cursor & (args->state->segment_count - 1u);
    return EMBED_TRUE;
}

/**
 * @brief Reports the index of the segment the producer fills next.
 *
 * @param[in,out] args Ring, and where to write the index [BORROWS].
 * @return             EMBED_TRUE with the index in args->out_index, EMBED_FALSE when every segment is
 *                     in flight.
 * @note Writes through args->out_index only when it returns EMBED_TRUE.
 * @note A EMBED_FALSE can go stale the moment the consumer releases a segment. A EMBED_TRUE cannot,
 *       since releases only make room.
 */
EMBED_INLINE embed_bool anular_seg_next(const AnularisCtx *args)
{
    const size_t claimed = MMGR_ATOMIC_LOAD(&args->state->claimed);

    return ring_seg_pick(args, claimed,
                         (claimed - MMGR_ATOMIC_LOAD(&args->state->released)) < args->state->segment_count);
}

/**
 * @brief Advances one of the segment counters by one.
 *
 * @param[in,out] counter Counter to advance [BORROWS].
 * @note Publishing and releasing are the same step on opposite counters, so both reach this.
 * @note One side owns each counter, so the read and the write need no atomicity between them.
 */
EMBED_INLINE void ring_bump(_Atomic size_t *counter)
{
    MMGR_ATOMIC_STORE(counter, MMGR_ATOMIC_LOAD(counter) + 1u);
}

/**
 * @brief Makes the filled segment visible to the consumer.
 *
 * @param[in,out] args Ring to advance [BORROWS].
 * @note Only the producer calls this, which is what lets ring_bump read and write claimed as two
 *       steps.
 * @warning Advances whether or not a segment was filled, so a publish with no matching
 *          anular_seg_next puts more in flight than the ring holds, and that call then refuses until
 *          releases catch up.
 */
EMBED_INLINE void anular_seg_publish(const AnularisCtx *args)
{
    ring_bump(&args->state->claimed);
}

/**
 * @brief Reports the index of the segment the consumer takes next.
 *
 * @param[in,out] args Ring, and where to write the index [BORROWS].
 * @return             EMBED_TRUE with the index in args->out_index, EMBED_FALSE when none is in
 *                     flight.
 * @note Writes through args->out_index only when it returns EMBED_TRUE.
 * @note A EMBED_FALSE can go stale the moment the producer publishes a segment. A EMBED_TRUE cannot,
 *       since publishes only add.
 */
EMBED_INLINE embed_bool anular_seg_front(const AnularisCtx *args)
{
    const size_t released = MMGR_ATOMIC_LOAD(&args->state->released);

    return ring_seg_pick(args, released, MMGR_ATOMIC_LOAD(&args->state->claimed) != released);
}

/**
 * @brief Frees the front segment.
 *
 * @param[in,out] args Ring to advance [BORROWS].
 * @note Only the consumer calls this, which is what lets ring_bump read and write released as two
 *       steps.
 * @warning Advances whether or not a segment was in flight, so a release with no matching
 *          anular_seg_front wraps the subtraction in anular_seg_inflight and leaves anular_seg_front
 *          handing out a segment that was never filled.
 */
EMBED_INLINE void anular_seg_release(const AnularisCtx *args)
{
    ring_bump(&args->state->released);
}

/**
 * @brief Returns the contiguous span of segment args->index.
 *
 * @param[in] args Ring and the segment index [BORROWS].
 * @return         Its first byte inside the ring buffer [BORROWS].
 * @note The span runs for segment_bytes, which mmgr_anular_init set to the capacity divided by the
 *       segment_count it was given.
 * @warning args->index is not checked against segment_count here or anywhere below. An index at or
 *          past that count multiplies past the buffer and the pointer returned lies outside the
 *          ring's bytes.
 */
EMBED_INLINE uint8_t *anular_seg_at(const AnularisCtx *args)
{
    return &args->state->buf[args->index * args->state->segment_bytes];
}

/**
 * @brief Returns the loculi that are free and not held.
 *
 * @param[in] args Ring to inspect [BORROWS].
 * @return         The free mask with the held ones cleared, bounded to the loculi this build has.
 * @note A loculus is takeable only when it is free and not held, which is what makes reuse safe.
 * @warning The two masks are read one after the other, so this is only a snapshot. A hold or a drop
 *          may land between the loads, or after both. anular_loculus_hold settles that race, refusing
 *          a loculus another caller took first.
 */
EMBED_INLINE embed_word anular_loculus_ready(const AnularisCtx *args)
{
    return MMGR_ATOMIC_LOAD(&args->state->gratis) & ~MMGR_ATOMIC_LOAD(&args->state->held) & ring_loculus_all();
}

/**
 * @brief Returns the index of the lowest set bit of args->mask.
 *
 * @param[in] args The mask to pick from [BORROWS].
 * @return         The index, or -1 when args->mask is empty.
 * @note Counts rather than scans, and branches on nothing but the empty mask.
 * @note Only args->mask is read. This is the one backend here that never reaches the ring state.
 * @note The test below is the one ring_trail asks of its callers, since an empty mask reaches it as a
 *       count of EMBED_WORD_BITS rather than as no bit at all.
 * @warning The mask is taken as given, so a bit above the loculi this build has comes back as its
 *          index. That index names no loculus, and anular_loculus_hold refuses it.
 */
EMBED_INLINE embed_iword anular_loculus_next(const AnularisCtx *args)
{
    // Explicit cast puts the empty test at embed_word, the width the mask is carried in
    if (args->mask == (embed_word)0)
    {
        // Explicit cast builds the miss at the signed embed_iword this returns, the one type that
        // holds both an index and a -1
        return (embed_iword)-1;
    }
    return ring_trail(args->mask);
}

/**
 * @brief Takes loculus args->index and records the region it keeps out.
 *
 * @param[in,out] args Ring, the loculus, and the region to record [BORROWS].
 * @return             EMBED_TRUE when this caller took the loculus, EMBED_FALSE when args->index names
 *                     none or another caller already holds it.
 * @note The fetch_or is what settles a race between two callers. Whichever finds the bit clear takes
 *       the loculus, and the other sees it already set and is refused.
 * @note Records the region only on the EMBED_TRUE path, so a refused caller leaves the span alone.
 * @warning An out-of-range args->index names no bit, so it reads as held and is never handed out.
 * @warning args->src is kept by the ring and handed back by anular_loculus_keepout, so it must outlive
 *          the hold [BORROWS].
 */
EMBED_INLINE embed_bool anular_loculus_hold(const AnularisCtx *args)
{
    const embed_word bit = ring_loculus_bit(args->index);

    // Explicit cast puts the no-bit test at embed_word, the width ring_loculus_bit answers in
    if (bit == (embed_word)0)
    {
        return EMBED_FALSE;
    }

    const embed_word prev = atomic_fetch_or_explicit(&args->state->held, bit, memory_order_acquire);

    if ((prev & bit) != 0u)
    {
        return EMBED_FALSE;
    }
    // Explicit casts round the const source through uintptr_t and back to the writable uint8_t * the
    // span holds, so the qualifier goes at the integer rather than at a pointer cast, which is what
    // -Wcast-qual is there to catch. The ring only records the region and never writes through it.
    args->state->keepout[args->index].buf = (uint8_t *)(uintptr_t)args->src;
    args->state->keepout[args->index].bytes = args->bytes;
    args->state->keepout[args->index].read_offset = 0u;
    return EMBED_TRUE;
}

/**
 * @brief Returns the region loculus args->index is keeping out.
 *
 * @param[in] args Ring and the loculus [BORROWS].
 * @return         The recorded span, or NULL when args->index names none [BORROWS].
 * @note Handed back const, so a reader walks it without moving the ring's own record.
 * @note A loculus that was never held reads back as the span mmgr_anular_init cleared, a NULL buf and
 *       a bytes of zero.
 * @warning The const covers the span and not the bytes it names. buf comes back as a writable
 *          pointer, though the region reached anular_loculus_hold as const.
 */
EMBED_INLINE const mmgr_ring_span *anular_loculus_keepout(const AnularisCtx *args)
{
#if MMGR_RING_LOCULI == 0u
    // A build with no loculi keeps nothing out, so there is no span to hand back and args goes
    // unread. Explicit cast to void is what states that, since an unused parameter is a diagnostic here
    (void)args;
    return NULL;
#else
    if (args->index >= (size_t)MMGR_RING_LOCULI)
    {
        return NULL;
    }
    return &args->state->keepout[args->index];
#endif
}

/**
 * @brief Gives loculus args->index back.
 *
 * @param[in,out] args Ring and the loculus [BORROWS].
 * @note Leaves the recorded span and the bytes alone, so a restream can run again.
 * @note Releases what the acquire in anular_loculus_hold took, so the writes a holder made before the
 *       drop are visible to whoever takes the loculus next.
 * @note An out-of-range args->index names no bit and clears nothing, and dropping a loculus that is
 *       not held does nothing.
 */
EMBED_INLINE void anular_loculus_drop(const AnularisCtx *args)
{
    // Explicit cast keeps the complement at embed_word width, matching the atomic it clears, and the
    // cast to void drops the mask the fetch returns, which this call has no use for
    (void)atomic_fetch_and_explicit(&args->state->held, (embed_word)~ring_loculus_bit(args->index),
                                    memory_order_release);
}

/**
 * @brief Marks loculus args->index free.
 *
 * @param[in,out] args Ring and the loculus [BORROWS].
 * @note Sets the free bit. The held bit is anular_loculus_drop's to clear, and a loculus is takeable
 *       only when it is free and not held.
 * @note mmgr_anular_init sets the free bit for every loculus and nothing in this file clears it, so on
 *       a ring that call has laid down this changes nothing.
 * @note An out-of-range args->index names no bit and sets nothing.
 */
EMBED_INLINE void anular_loculus_mark(const AnularisCtx *args)
{
    // Explicit cast to void drops the mask the fetch returns, which this call has no use for
    (void)atomic_fetch_or_explicit(&args->state->gratis, ring_loculus_bit(args->index), memory_order_release);
}

/**
 * @brief Lays a fresh ring into args->ring, over the bytes at args->buf.
 *
 * @note Documented at the declaration in memoria_anularis.h.
 */
embed_bool mmgr_anular_init(const AnularisCfg *args)
{
    MMGR_ASSERT(args->ring != NULL, "a ring needs storage");
    MMGR_ASSERT(args->buf != NULL, "a ring needs a buffer");

    // Two tests because MMGR_RING_POW2 reports true for a capacity of 0 as well, so the empty buffer
    // is refused on its own. The power of two is what lets every wrap here be a mask, not a divide
    if ((args->capacity == 0u) || !MMGR_RING_POW2(args->capacity))
    {
        return EMBED_FALSE;
    }
    // The same two tests on the segment count, so ring_seg_pick can wrap a counter by mask, plus one
    // that keeps a segment at a byte or more. A count above the capacity divides to a segment of zero
    if ((args->segment_count == 0u) || !MMGR_RING_POW2(args->segment_count) || (args->segment_count > args->capacity))
    {
        return EMBED_FALSE;
    }

    RingState *const state = ring_of(args->ring);

    state->buf = args->buf;
    state->capacity = args->capacity;
    state->segment_count = args->segment_count;
    state->segment_bytes = args->capacity / args->segment_count;
    atomic_init(&state->head, 0u);
    atomic_init(&state->tail, 0u);
    atomic_init(&state->claimed, 0u);
    atomic_init(&state->released, 0u);
    atomic_init(&state->gratis, ring_loculus_all());
    atomic_init(&state->held, (embed_word)0);
#if MMGR_RING_LOCULI > 0u
    // A build with no loculi has one keepout entry that nothing reaches, so this loop is compiled out
    // rather than run over it
    // Explicit cast puts the declared count at size_t, the type the index below is walked in
    for (size_t index = 0; index < (size_t)MMGR_RING_LOCULI; index++)
    {
        state->keepout[index].buf = NULL;
        state->keepout[index].bytes = 0u;
        state->keepout[index].read_offset = 0u;
    }
#endif
    return EMBED_TRUE;
}

/**
 * @brief The state argument every entry point but one forwards.
 *
 * @note Reads args, the entry point's own parameter, so the table below carries fields alone.
 * @note Valid only inside a EMBED_ENTRY body, which is where that parameter is in scope.
 * @note loculus_next is the entry that leaves it out, since it reads a mask and never the ring.
 */
#define RING_S .state = ring_of(args->ring)

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_anular_ and anular_ prefixes, which the two share.
 * @param[in] ...         Initializers for the AnularisCtx literal, written in terms of args.
 * @note The prefixes and the two structure types are the same for every entry, so they are named
 *       once here and the table below states only what each entry differs in.
 * @note The variadic part is the argument pack, never empty, so no comma needs eliding.
 */
#define RING_ENTRY(ReturnType_, name_, ...)                                                                            \
    EMBED_ENTRY(mmgr_anular_, anular_, AnularisCtx, AnularisCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the same four to EMBED_ENTRY_V, for an entry that returns nothing.
 *
 * @param[in] name_ Name after the mmgr_anular_ and anular_ prefixes, which the two share.
 * @param[in] ...   Initializers for the AnularisCtx literal, written in terms of args.
 * @note Separate from RING_ENTRY because a return with an expression is not allowed in a void
 *       function, so the two cannot share one body.
 */
#define RING_ENTRY_V(name_, ...) EMBED_ENTRY_V(mmgr_anular_, anular_, AnularisCtx, AnularisCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in memoria_anularis.h.
 * @note The fields each line forwards are the ones that entry reads, and EMBED_CALL zeroes the rest.
 * @note mmgr_anular_init is not among them. It checks the sizes and lays the state down, which no
 *       argument pack expresses, so it is written by hand above.
 */
RING_ENTRY(size_t, available, RING_S)
RING_ENTRY(size_t, vacant, RING_S)
RING_ENTRY(embed_bool, read_byte, RING_S, .dst = args->dst)
RING_ENTRY(size_t, read, RING_S, .dst = args->dst, .bytes = args->bytes)
RING_ENTRY_V(peek, RING_S, .dst = args->dst, .bytes = args->bytes, .offset = args->offset)
RING_ENTRY_V(consume, RING_S, .bytes = args->bytes)
RING_ENTRY(embed_bool, put, RING_S, .src = args->src, .bytes = args->bytes)
RING_ENTRY(size_t, seg_inflight, RING_S)
RING_ENTRY(embed_bool, seg_next, RING_S, .out_index = args->out_index)
RING_ENTRY_V(seg_publish, RING_S)
RING_ENTRY(embed_bool, seg_front, RING_S, .out_index = args->out_index)
RING_ENTRY_V(seg_release, RING_S)
RING_ENTRY(uint8_t *, seg_at, RING_S, .index = args->index)
RING_ENTRY(embed_word, loculus_ready, RING_S)
RING_ENTRY(embed_iword, loculus_next, .mask = args->mask)
RING_ENTRY(embed_bool, loculus_hold, RING_S, .index = args->index, .src = args->src, .bytes = args->bytes)
RING_ENTRY(const mmgr_ring_span *, loculus_keepout, RING_S, .index = args->index)
RING_ENTRY_V(loculus_drop, RING_S, .index = args->index)
RING_ENTRY_V(loculus_mark, RING_S, .index = args->index)
