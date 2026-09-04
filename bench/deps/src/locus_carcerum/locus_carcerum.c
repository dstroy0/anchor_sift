/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file locus_carcerum.c
 * @brief One cellblock allocator, run from both tiers toward the same free gap between them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Both tiers allocate through carcer_grow and coalesce through carcer_coalesce. The persistent
 *       tier allocates upward from base. The temporary tier allocates downward from size.
 * @note Only the persistent tier walks its free list and splits a cell. A temporary allocation moves
 *       the top down and does nothing else.
 * @note A cell from either tier can be released on its own. The release reads which tier a cell came
 *       from off its address, so a caller does not name it. The temporary tier can also be rewound
 *       to a mark, or reset in one step.
 * @note Nothing is zeroed on allocation, so a cell holds whatever the last prisoner left in it. Two
 *       of the five releases zero the cell first. A cellblock's declaration decides which guard its
 *       entries reach.
 * @note Reaches nothing outside config.
 */
#include "locus_carcerum/locus_carcerum.h"

/**
 * @brief What a cell carries ahead of its payload.
 *
 * @note size counts the payload alone. Every walk here adds CARCER_HDR itself to step to the next
 *       cell, and every fit test compares against the payload.
 * @note The header lies immediately ahead of the bytes handed out, so a cell's header is reached by
 *       subtracting CARCER_HDR from its address and no tier is walked to find it.
 */
typedef struct
{
    size_t size; /**< Payload bytes behind this header. */
    size_t used; /**< 0 while the cell is empty, 1 while a prisoner holds it. */
} CarcerCell;

/**
 * @brief Bytes a cell header occupies, rounded up so the payload behind it stays aligned.
 *
 * @note The rounding is a mask, and a mask rounds only because MMGR_CARCER_ALIGN is a power of two,
 *       which locus_carcerum.h asserts.
 * @note Charged on top of the payload every time a cell is allocated, so an allocation of size bytes
 *       costs the gap this much more than size.
 */
#define CARCER_HDR ((sizeof(CarcerCell) + (MMGR_CARCER_ALIGN - 1u)) & ~(MMGR_CARCER_ALIGN - 1u))

/**
 * @brief The half-open offset range one tier occupies.
 *
 * @note lo and hi are offsets from the cellblock's base, not addresses. carcer_blk is what turns one
 *       into a header pointer.
 * @note Both tiers are walked from lo upward, so the fit and the merge take a tier and no direction
 *       argument. Only the merge is handed either tier. The fit belongs to the persistent one.
 */
typedef struct
{
    size_t lo; /**< Offset of the first cell in the tier. */
    size_t hi; /**< One past the last byte the tier occupies. */
} CarcerTier;

/**
 * @brief Rounds want up to a whole machine word.
 *
 * @param[in] want Count to round.
 * @return         want rounded up to a multiple of MMGR_CARCER_ALIGN, and want itself when it
 *                 already is one.
 * @note The mask is what rounds, which holds only because MMGR_CARCER_ALIGN is a power of two.
 * @warning MMGR_CARCER_ALIGN - 1 is added before the mask, so a want within a word of SIZE_MAX wraps
 *          to 0. Every allocation rounds its request through here, and a request that wraps is met
 *          with a small cell rather than refused.
 */
EMBED_INLINE size_t carcer_round(size_t want)
{
    return (want + (MMGR_CARCER_ALIGN - 1u)) & ~(MMGR_CARCER_ALIGN - 1u);
}

/**
 * @brief Zeroes want bytes at *walk, advancing the pointer and taking them off *left.
 *
 * @param[in,out] walk Walking pointer, left one past the last byte cleared [BORROWS].
 * @param[in,out] left Bytes still to clear, reduced by want [BORROWS].
 * @param[in]     want Bytes to clear now.
 * @note Used for the two edges of the zeroing. The word-wide run between them does its own stores,
 *       through its own volatile pointer, and does not come through here.
 * @note The stores are volatile, so clearing bytes nothing reads afterwards is not dropped as dead
 *       work.
 * @warning want comes off *left with no test, so a want above *left wraps it. Both call sites hold
 *          want at or below what is left.
 * @warning *walk must be writable for want bytes.
 */
EMBED_INLINE void carcer_zero_bytes(volatile uint8_t **walk, size_t *left, size_t want)
{
    size_t index = 0u;

    while (index < want)
    {
        // Store, pointer advance and count advance are separate statements. Folding them into
        // *(*walk)++ = 0u would put an increment inside the volatile store
        **walk = 0u;
        (*walk)++;
        index++;
    }
    *left -= want;
}

/**
 * @brief Reads the cell header at offset off in the cellblock.
 *
 * @param[in] cellblock Cellblock to look in [BORROWS].
 * @param[in] off       Offset of the header, always a multiple of MMGR_CARCER_ALIGN.
 * @return              The header [BORROWS].
 * @note The cast goes through void *. base is aligned by the site macro and every offset a tier
 *       walks is a whole number of words, so the header is always correctly aligned.
 * @warning The cellblock is const here and the header is not. The fit, the split and the merge all
 *          hold a const cellblock and write through what this hands back.
 * @warning off is added to base with nothing holding it against the cellblock's size. Every caller
 *          here walks a tier whose bounds came from the cellblock, except the two releases, which
 *          pass an offset taken from the address the caller handed them.
 */
EMBED_INLINE CarcerCell *carcer_blk(const CarcerCellBlock *cellblock, size_t off)
{
    return (CarcerCell *)(void *)(cellblock->base + off);
}

/**
 * @brief Steps past the cell at off to the next one in its tier.
 *
 * @param[in] cellblock Cellblock the tier runs in [BORROWS].
 * @param[in] off       Offset of the cell to step past.
 * @return              Offset of the cell after it.
 * @note A cell is its header plus its payload, and every walk here steps by that.
 * @warning The step is the cell's own recorded size, and the result is not held against the
 *          cellblock. It reaches or passes the tier's hi at the end of a walk, which is what each
 *          loop test is there for.
 */
EMBED_INLINE size_t carcer_next(const CarcerCellBlock *cellblock, size_t off)
{
    return off + CARCER_HDR + carcer_blk(cellblock, off)->size;
}

/**
 * @brief Returns the offset of a cell's own header.
 *
 * @param[in] cellblock Cellblock the cell came from [BORROWS].
 * @param[in] at        First byte of the cell [BORROWS].
 * @return              Offset of its header in the cellblock.
 * @warning at is taken to be a cell of this cellblock and nothing here tests that it is. Both
 *          releases bound their address with mmgr_who_owns_buf before reaching this, so what arrives
 *          lies inside the cellblock. That bound does not say a cell begins there, so an address
 *          inside these bytes but off a cell boundary still yields an offset reading bytes which are
 *          not a header.
 */
EMBED_INLINE size_t carcer_off_of(const CarcerCellBlock *cellblock, const void *at)
{
    // Explicit casts take at to a byte pointer so the difference is in bytes, then that ptrdiff_t to
    // the size_t the offset is carried in. An at below base makes the difference negative and the
    // cast wraps it high, which is the unchecked case the warning above describes
    return (size_t)((const uint8_t *)at - cellblock->base) - CARCER_HDR;
}

/**
 * @brief Returns the persistent tier's extent.
 *
 * @param[in] cellblock Cellblock to read [BORROWS].
 * @return              lo of 0, hi of persistent_end.
 * @note A copy of the bounds as they stand at the call, not a view of them. A release that trims
 *       persistent_end leaves a tier taken before it naming a hi the tier no longer reaches.
 */
EMBED_INLINE CarcerTier carcer_up(const CarcerCellBlock *cellblock)
{
    CarcerTier tier;

    tier.lo = 0u;
    tier.hi = cellblock->persistent_end;
    return tier;
}

/**
 * @brief Returns the temporary tier's extent.
 *
 * @param[in] cellblock Cellblock to read [BORROWS].
 * @return              lo of temporary_top, hi of the cellblock's size.
 * @note A copy of the bounds as they stand at the call, not a view of them. Here it is lo that
 *       moves, since every allocation on this tier lowers the top. The persistent tier's lo is
 *       always 0.
 */
EMBED_INLINE CarcerTier carcer_down(const CarcerCellBlock *cellblock)
{
    CarcerTier tier;

    tier.lo = cellblock->temporary_top;
    tier.hi = cellblock->size;
    return tier;
}

/**
 * @brief Splits the cell at walk when what is left would hold another cell.
 *
 * @param[in]     cellblock Cellblock the cell sits in [BORROWS].
 * @param[in,out] walk      Cell to split, left carrying want [BORROWS].
 * @param[in]     off       Offset of walk in the cellblock.
 * @param[in]     want      Payload the first half keeps.
 * @note Only splits when the remainder can carry a header and a payload of its own. Otherwise the
 *       prisoner keeps the whole cell and its slack.
 * @note The remainder is left empty where it lies. Nothing links it to its neighbors and nothing
 *       merges it here. A later walk steps onto it and the merge finds it then.
 * @warning off must be walk's own offset. The two are not checked against each other, and a
 *          mismatched pair writes the second header where no cell begins.
 */
EMBED_INLINE void carcer_split(const CarcerCellBlock *cellblock, CarcerCell *walk, size_t off, size_t want)
{
    // Split only when the tail left over can carry its own header and a whole word behind it
    if (walk->size >= (want + CARCER_HDR + MMGR_CARCER_ALIGN))
    {
        CarcerCell *const next_cell = carcer_blk(cellblock, off + CARCER_HDR + want);

        next_cell->size = walk->size - want - CARCER_HDR;
        next_cell->used = 0u;
        walk->size = want;
    }
}

/**
 * @brief Finds an empty cell in tier large enough for want and takes it.
 *
 * @param[in] cellblock Cellblock to search [BORROWS].
 * @param[in] tier      Tier to walk.
 * @param[in] want      Payload wanted, already rounded.
 * @return              The cell, or NULL when no cell in the tier fits [RETURNS OWNERSHIP].
 * @note First fit, not best fit. A best fit would walk the whole tier to save slack the split
 *       already recovers.
 * @note The cell is marked used inside the walk, so a tier that yields a cell has already given it
 *       away. There is no found-but-not-taken result.
 * @warning The whole tier is walked in the failing case, so an allocation on a tier holding many
 *          cells costs their number.
 */
EMBED_INLINE void *carcer_fit(const CarcerCellBlock *cellblock, CarcerTier tier, size_t want)
{
    size_t off = tier.lo;

    while (off < tier.hi)
    {
        CarcerCell *const walk = carcer_blk(cellblock, off);

        // A cell fits only on both counts: empty, and holding at least the payload asked for
        if ((walk->used == 0u) && (walk->size >= want))
        {
            carcer_split(cellblock, walk, off, want);
            walk->used = 1u;
            return cellblock->base + off + CARCER_HDR;
        }
        off = carcer_next(cellblock, off);
    }
    return NULL;
}

/**
 * @brief Lays a fresh cell of want payload bytes at offset off.
 *
 * @param[in] cellblock Cellblock to allocate in [BORROWS].
 * @param[in] off       Offset the header goes at.
 * @param[in] want      Payload the cell carries.
 * @return              The cell [RETURNS OWNERSHIP].
 * @note Only the header is written. The payload behind it is left holding whatever the last prisoner
 *       of those bytes put there.
 * @warning off must have CARCER_HDR + want bytes behind it, and nothing here tests that it does.
 *          carcer_grow measures the gap first and is the only caller.
 */
EMBED_INLINE void *carcer_alloc(const CarcerCellBlock *cellblock, size_t off, size_t want)
{
    CarcerCell *const walk = carcer_blk(cellblock, off);

    walk->size = want;
    walk->used = 1u;
    return cellblock->base + off + CARCER_HDR;
}

/**
 * @brief Returns the bytes lying between the two tiers.
 *
 * @param[in] cellblock Cellblock to read [BORROWS].
 * @return              temporary_top minus persistent_end, or 0 once the tiers have met.
 * @note Both offsets are unsigned, so the test is what stops a crossing from reading as a gap larger
 *       than the cellblock. carcer_grow's size test is what keeps them from crossing at all.
 * @warning The two tiers are read one after the other, so the answer is a snapshot. carcer_grow
 *          tests a request against it and then moves a boundary, and an allocation from a preempting
 *          handler landing between the two allocates from the same value this one did.
 */
EMBED_INLINE size_t carcer_middle(const CarcerCellBlock *cellblock)
{
    return (cellblock->temporary_top > cellblock->persistent_end)
               ? (cellblock->temporary_top - cellblock->persistent_end)
               : 0u;
}

/**
 * @brief Merges every run of adjacent empty cells in tier, and reports the last cell's offset.
 *
 * @param[in] cellblock Cellblock whose tier to walk [BORROWS].
 * @param[in] tier      Tier to merge.
 * @return              Offset of the last cell, or tier.lo when the tier is empty.
 * @note A merged cell is revisited rather than stepped past, so a run of three or more collapses in
 *       one pass. The walk still ends, because the revisited cell is larger by what it swallowed and
 *       the step recomputed from it reaches further than the one before.
 * @note The last offset is returned from this walk so trimming needs no second one.
 */
EMBED_INLINE size_t carcer_coalesce(const CarcerCellBlock *cellblock, CarcerTier tier)
{
    size_t off = tier.lo;
    size_t last = tier.lo;

    while (off < tier.hi)
    {
        CarcerCell *const current_cell = carcer_blk(cellblock, off);
        const size_t next_off = carcer_next(cellblock, off);

        // A merge needs both: this cell empty, and a next cell still inside the tier to merge in
        if ((current_cell->used == 0u) && (next_off < tier.hi))
        {
            CarcerCell *const next_cell = carcer_blk(cellblock, next_off);

            if (next_cell->used == 0u)
            {
                current_cell->size += CARCER_HDR + next_cell->size;
                continue;
            }
        }
        last = off;
        off = next_off;
    }
    return last;
}

/**
 * @brief Records a new high-water mark for one tier.
 *
 * @param[in,out] hw   Mark to raise [BORROWS].
 * @param[in]     used Bytes in use by the tier that moved.
 * @note Branchless. The comparison becomes a mask that selects the larger of the two.
 * @warning The mark is read and then written, as two steps. An allocation from a preempting handler
 *          landing between them leaves that allocation's reach unrecorded.
 */
EMBED_INLINE void carcer_hw(size_t *hw, size_t used)
{
    // Explicit cast widens the int result of > to size_t, so the negation builds a mask the full
    // width of the members it selects between
    const size_t hw_mask = 0u - (size_t)(used > *hw);

    *hw = (*hw & ~hw_mask) | (used & hw_mask);
}

/**
 * @brief Raises one tier's high-water mark, or expands to nothing where the build tracks none.
 *
 * @param[in] cellblock_ Cellblock to record against.
 * @param[in] member_    Mark to raise, which only exists when the build tracks one.
 * @param[in] used_      Bytes in use by the tier that moved.
 * @note A macro, not a call. The member does not exist when the build tracks none, and an argument
 *       cannot name a member that is not declared.
 * @warning The two arms do not evaluate the same things. Where the build tracks none, not one of the
 *          three arguments is evaluated, so nothing passed here may carry a side effect.
 */
#if MMGR_ENABLE_HW_MEM_CAPACITY_CB
#define CARCER_HW(cellblock_, member_, used_) carcer_hw(&(cellblock_)->member_, (used_))
#else
#define CARCER_HW(cellblock_, member_, used_) ((void)0)
#endif

/**
 * @brief Allocates a fresh cell for want bytes out of the free gap, on whichever tier asked.
 *
 * @param[in,out] cellblock Cellblock to allocate in [BORROWS].
 * @param[in]     want      Payload wanted, already rounded.
 * @param[in]     down      EMBED_TRUE for the tier that grows down.
 * @return                  The cell, or NULL when the gap cannot meet it [RETURNS OWNERSHIP].
 * @note Both tiers reach this, so the size test, the allocation and the high-water mark are written
 *       once.
 * @note The test is the header plus the payload against the gap, so a want the size of the whole gap
 *       is refused.
 * @note Fails closed. A request the gap cannot meet moves no boundary at all.
 */
EMBED_INLINE void *carcer_grow(CarcerCellBlock *cellblock, size_t want, embed_bool down)
{
    const size_t need = CARCER_HDR + want;

    if (need > carcer_middle(cellblock))
    {
        return NULL;
    }
    if (down)
    {
        cellblock->temporary_top -= need;
        CARCER_HW(cellblock, temporary_hw, cellblock->size - cellblock->temporary_top);
        return carcer_alloc(cellblock, cellblock->temporary_top, want);
    }

    void *const payload = carcer_alloc(cellblock, cellblock->persistent_end, want);

    cellblock->persistent_end += need;
    CARCER_HW(cellblock, persistent_hw, cellblock->persistent_end);
    return payload;
}

/**
 * @brief Rounds a request up to a whole word.
 *
 * @param[in] want Bytes the caller asked for.
 * @return         The least payload a cell may carry for this request, since a reused cell keeps its
 *                 slack. A want of 0 returns MMGR_CARCER_ALIGN.
 * @note Both tiers round the same way, so it is done in one place.
 * @warning A want within a word of SIZE_MAX wraps in the rounding and comes back small, so the cell
 *          carries far less than was asked for. Neither allocator tests the request before this.
 */
EMBED_INLINE size_t carcer_want(size_t want)
{
    return carcer_round((want != 0u) ? want : MMGR_CARCER_ALIGN);
}

/**
 * @brief Takes size bytes from the persistent tier.
 *
 * @param[in,out] cellblock Cellblock to take from [BORROWS].
 * @param[in]     size      Bytes wanted.
 * @return                  Start of the cell, or NULL when the cellblock cannot meet it [RETURNS OWNERSHIP].
 * @note Reuses a released cell before moving the boundary, which is what makes this tier a free list
 *       rather than a cursor.
 * @note The reuse walk runs first and costs the tier its full length whenever nothing in it fits.
 *       Only then does the boundary move.
 */
void *mmgr_persistent_buf_alloc(CarcerCellBlock *cellblock, size_t size)
{
    const size_t want = carcer_want(size);
    void *const reused = carcer_fit(cellblock, carcer_up(cellblock), want);

    return (reused != NULL) ? reused : carcer_grow(cellblock, want, EMBED_FALSE);
}

/**
 * @brief Takes size bytes from the temporary tier.
 *
 * @param[in,out] cellblock Cellblock to take from [BORROWS].
 * @param[in]     size      Bytes wanted.
 * @return                  Start of the cell, or NULL when the cellblock cannot meet it [RETURNS OWNERSHIP].
 * @note Allocates like the persistent tier but moves the boundary down, and does no fit walk.
 * @note The walk is omitted deliberately, not missing. A first fit would make a run of allocations
 *       quadratic, and this tier is meant to be released wholesale rather than picked over. An
 *       allocation stays O(1), which is what this tier buys over the persistent one.
 * @note A single release on this tier trims only when the released cell sits at the top. Anything
 *       released below it merges with its empty neighbors and stays in the tier, and since no
 *       allocation here walks that tier, nothing reuses it before the next rewind.
 */
void *mmgr_temporary_buf_alloc(CarcerCellBlock *cellblock, size_t size)
{
    return carcer_grow(cellblock, carcer_want(size), EMBED_TRUE);
}

/**
 * @brief Writes zeros over size bytes at prisoner.
 *
 * @param[in,out] prisoner First byte to clear [BORROWS].
 * @param[in]     size     Bytes to clear.
 * @note The stores are volatile, so clearing bytes nothing reads afterwards is not dropped as dead
 *       work. Whole words go down between the two edges, and volatile counts per access, so a word
 *       store is kept for the same reason a byte store is.
 * @warning prisoner must be writable for size bytes.
 */
void mmgr_zero_buf(void *prisoner, size_t size)
{
    // Explicit cast takes the prisoner to a volatile byte pointer, the scope the edge walks use
    volatile uint8_t *walk = (volatile uint8_t *)prisoner;
    size_t left = size;
    // Explicit casts take walk to uintptr_t for the alignment test, then that result to the size_t
    // edge is carried in
    size_t edge = (size_t)(((uintptr_t)walk) & (MMGR_CARCER_ALIGN - 1u));

    // Head: bytes up to the first word boundary, so the loop below starts aligned
    edge = (edge != 0u) ? (MMGR_CARCER_ALIGN - edge) : 0u;
    edge = (edge < left) ? edge : left;
    carcer_zero_bytes(&walk, &left, edge);

    // Explicit casts go through volatile void * to reach the word scope the run stores in. The head
    // above leaves walk on a word boundary whenever it had the bytes to reach one. Where it ran out
    // first, left is 0 and neither the loop nor the tail reads through this pointer
    volatile embed_word *word_walk = (volatile embed_word *)(volatile void *)walk;

    while (left >= MMGR_CARCER_ALIGN)
    {
        // Store, pointer advance and count advance are separate statements; *word_walk++ = 0 would
        // put an increment inside the volatile store. Explicit cast gives the zero the word scope
        *word_walk = (embed_word)0;
        word_walk++;
        left -= MMGR_CARCER_ALIGN;
    }

    // Explicit casts return to the byte scope for the tail, which is under one word
    walk = (volatile uint8_t *)(volatile void *)word_walk;
    carcer_zero_bytes(&walk, &left, left);
}

/**
 * @brief Releases a prisoner, leaving the cell's bytes as they are.
 *
 * @param[in,out] cellblock Cellblock the prisoner came from [BORROWS].
 * @param[in]     prisoner  First byte of the cell [TAKES OWNERSHIP].
 * @note Which tier the cell came from is read from its address rather than named by the caller, so a
 *       release cannot be given to the wrong tier.
 * @note After coalescing, an empty cell at the tier's own boundary is returned to the gap, so the
 *       tiers recover. That boundary is the last cell on the persistent tier and the first on the
 *       temporary one.
 * @note A NULL prisoner returns without touching the cellblock.
 * @warning prisoner is dead once this returns. The cellblock may hand those bytes out again.
 * @warning A prisoner from another cellblock stops the program through MMGR_FATAL. Releasing it here
 *          would move this cellblock's boundaries using a header read out of another's bytes, and a
 *          caller that reached this has shown it does not know which cellblock owns that memory.
 * @warning The bound is the cellblock's storage, not a cell boundary. An address inside these bytes
 *          that is not the first byte of a cell passes the test and is still read as a header, so
 *          mmgr_who_owns_buf narrows this and does not close it.
 */
void mmgr_persistent_buf_release(CarcerCellBlock *cellblock, void *prisoner)
{
    if (prisoner == NULL)
    {
        return;
    }
    // One unsigned compare catches a prisoner from another cellblock. Releasing it is illegal rather
    // than merely unlucky, so this stops instead of returning: there is no state to carry on from
    if (!mmgr_who_owns_buf(cellblock, prisoner))
    {
        MMGR_FATAL("a prisoner was released to a cellblock that does not hold it");
    }

    const size_t off = carcer_off_of(cellblock, prisoner);

    carcer_blk(cellblock, off)->used = 0u;

    if (off < cellblock->persistent_end)
    {
        const CarcerTier tier = carcer_up(cellblock);
        const size_t last = carcer_coalesce(cellblock, tier);

        // Give bytes back to the gap only when the tier holds cells and its last one is empty
        if ((cellblock->persistent_end > 0u) && (carcer_blk(cellblock, last)->used == 0u))
        {
            cellblock->persistent_end = last;
        }
    }
    else
    {
        const CarcerTier tier = carcer_down(cellblock);

        (void)carcer_coalesce(cellblock, tier);

        CarcerCell *const first = carcer_blk(cellblock, cellblock->temporary_top);

        // Same trim on the other tier: it must hold cells, and the one at the top must be empty
        if ((cellblock->temporary_top < cellblock->size) && (first->used == 0u))
        {
            cellblock->temporary_top += CARCER_HDR + first->size;
        }
    }
}

/**
 * @brief Zeroes a cell, then releases the prisoner.
 *
 * @param[in,out] cellblock Cellblock the prisoner came from [BORROWS].
 * @param[in,out] prisoner  First byte of the cell, zeroed before release [TAKES OWNERSHIP].
 * @note The one step that separates a zeroing release from a plain one. The release itself is
 *       shared.
 * @note The extent comes from the cell's own header, so a caller cannot under-zero a cell.
 * @note A NULL prisoner returns without touching the cellblock.
 * @warning prisoner is dead once this returns. The cellblock may hand those bytes out again.
 * @warning A prisoner from another cellblock stops the program through MMGR_FATAL, ahead of the
 *          zeroing. Returning quietly instead would leave the caller believing bytes were wiped that
 *          were not, which is the failure this security level exists to prevent.
 * @warning The bound is the cellblock's storage, not a cell boundary. An address inside these bytes
 *          that is not the first byte of a cell passes the test, has its extent read from the bytes
 *          lying ahead of it, and is zeroed for whatever length those hold.
 */
void mmgr_persistent_max_security_buf_release(CarcerCellBlock *cellblock, void *prisoner)
{
    if (prisoner == NULL)
    {
        return;
    }
    // The same test as the plain release, taken ahead of the header read below. A quiet return here
    // would report a wipe that never happened, so this stops instead
    if (!mmgr_who_owns_buf(cellblock, prisoner))
    {
        MMGR_FATAL("a prisoner was released to a maximum security cellblock that does not hold it");
    }

    const CarcerCell *const walk = carcer_blk(cellblock, carcer_off_of(cellblock, prisoner));

    mmgr_zero_buf(prisoner, walk->size);
    mmgr_persistent_buf_release(cellblock, prisoner);
}

/**
 * @brief Returns the cellblock's current temporary top.
 *
 * @param[in] cellblock Cellblock to read [BORROWS].
 * @return              The value of temporary_top.
 * @note Good against this cellblock alone, and only until a restore to an older mark. The restore
 *       assigns the value it is handed without testing it.
 * @warning The value is a snapshot. An allocation from a preempting handler lowers the top after
 *          this has read it, and restoring the mark then releases that allocation's bytes as well.
 */
size_t mmgr_temporary_buf_mark(const CarcerCellBlock *cellblock)
{
    return cellblock->temporary_top;
}

/**
 * @brief Assigns the temporary top the value mark carries.
 *
 * @param[in,out] cellblock Cellblock to rewind [BORROWS].
 * @param[in]     mark      Top to restore, as mmgr_temporary_buf_mark reported it.
 * @note Drops every cell the tier allocated since that mark in one step, without walking them.
 * @note A mark past the cellblock's size, or below the current top, is one this cellblock never
 *       reported, and either returns without moving the tier.
 * @warning The two tests bound the mark to the cellblock. They do not tell one of its own marks from
 *          another, so an older mark still releases every cell taken since it.
 * @warning Every temporary cell taken since mark is dead once this returns. Nothing is zeroed, so
 *          such a pointer still dereferences and reads whatever the next allocation puts there.
 */
void mmgr_temporary_buf_release(CarcerCellBlock *cellblock, size_t mark)
{
    // Two compares: a mark past the cellblock's own bytes, and one below the current top, are both
    // marks this cellblock never handed out. Either would put the tier where it does not reach
    if ((mark > cellblock->size) || (mark < cellblock->temporary_top))
    {
        return;
    }
    cellblock->temporary_top = mark;
}

/**
 * @brief Zeroes every temporary byte taken since mark, then restores the top.
 *
 * @param[in,out] cellblock Cellblock to rewind [BORROWS].
 * @param[in]     mark      Top to restore.
 * @note Zeroes before the top moves, so the bytes are already zero at the instant they become
 *       available. Reclaiming first would leave a window in which the very next allocation sees
 *       them.
 * @note The extent comes from the two tops rather than a cell header, so a run of allocations is
 *       cleared in one pass and a caller cannot under-zero by naming fewer bytes than it holds.
 * @note The zeroing and the restore now agree on which marks they accept. A mark past the
 *       cellblock's size zeroes nothing and moves nothing, since mmgr_temporary_buf_release turns it
 *       away too. A mark equal to the current top zeroes nothing and restores the top to itself.
 * @warning The top is read once, ahead of the zeroing. An allocation from a preempting handler
 *          landing between that read and the restore is dropped unzeroed, since the extent was
 *          settled from the older top.
 */
void mmgr_max_security_buf_return(CarcerCellBlock *cellblock, size_t mark)
{
    const size_t top = cellblock->temporary_top;

    // Zero only for a mark above the top and inside the cellblock; [top, mark) is what is live
    if ((mark > top) && (mark <= cellblock->size))
    {
        mmgr_zero_buf(cellblock->base + top, mark - top);
    }
    mmgr_temporary_buf_release(cellblock, mark);
}

/**
 * @brief Releases the whole temporary tier at once, zeroing nothing.
 *
 * @param[in,out] cellblock Cellblock to act on [BORROWS].
 * @note mmgr_temporary_buf_release against the cellblock's own size, which is where the tier starts.
 * @note No cellblock entry reaches this one. A site's reset is its own generated wrapper, and that
 *       goes to the zeroing rewind wherever the cellblock was declared MMGR_MAXIMUM_SECURITY.
 * @warning Every temporary cell the cellblock has handed out is dead once this returns, and none of
 *          those bytes are zeroed.
 */
void mmgr_temporary_buf_reset(CarcerCellBlock *cellblock)
{
    mmgr_temporary_buf_release(cellblock, cellblock->size);
}

/**
 * @brief Returns whether at lies inside the cellblock's bytes.
 *
 * @param[in] cellblock Cellblock to test against [BORROWS].
 * @param[in] at        Address to test [BORROWS].
 * @return              EMBED_TRUE when at lies in [base, base + size), the last byte included.
 * @note Any address in the cellblock answers true, not only the first byte of a cell. This tells a
 *       caller where an address is, not what is there.
 */
embed_bool mmgr_who_owns_buf(const CarcerCellBlock *cellblock, const void *at)
{

    // Explicit casts to uintptr_t let one unsigned compare cover both ends: below base wraps high
    // Explicit cast narrows the int result of < to the embed_bool container
    return (embed_bool)(((uintptr_t)at - (uintptr_t)cellblock->base) < cellblock->size);
}

/**
 * @brief Returns the bytes lying between the two tiers.
 *
 * @param[in] cellblock Cellblock to read [BORROWS].
 * @return              The free gap, as carcer_middle reports it.
 * @note An allocation out of that gap needs a cell header from the same bytes, so a request of
 *       exactly this many cannot be met.
 * @warning The two tiers are read one after the other, so the answer is a snapshot. carcer_middle
 *          carries what that costs a caller.
 */
size_t mmgr_buf_available(const CarcerCellBlock *cellblock)
{
    return carcer_middle(cellblock);
}

/**
 * @brief Rounds size up to a whole machine word.
 *
 * @param[in] size Count to round.
 * @return         The rounded count.
 * @note A size of 0 rounds to 0. The allocators carry a request of 0 up to one word before rounding
 *       it.
 * @warning MMGR_CARCER_ALIGN - 1 is added before the mask, so a size within a word of SIZE_MAX wraps
 *          to 0.
 */
size_t mmgr_align_up_buf(size_t size)
{
    return carcer_round(size);
}
