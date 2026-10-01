
// orior_steer.c: the census and the steering probe order
#include "orior_internal.h"

/* ---- the steering, folded in ---- */

void anchor_field_census(const uint8_t *corpus, size_t corpus_len, AnchorFieldCensus *census)
{
    if (census == NULL)
    {
        return;
    }

    memset(census, 0, sizeof(*census));
    if ((corpus == NULL) || (corpus_len == 0u))
    {
        return;
    }

    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        census->occurrences[corpus[at]] += 1u;
    }
    census->total = (uint64_t)corpus_len;

    for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
    {
        if (census->occurrences[symbol] != 0u)
        {
            census->distinct += 1u;
        }
    }
}

uint64_t anchor_steer_magnitude(const AnchorFieldCensus *census, uint8_t symbol)
{
    if (census == NULL)
    {
        return 0u;
    }
    return census->total - census->occurrences[symbol];
}

void anchor_steer_probe_order(size_t *offsets, size_t count, const AnchorFieldCensus *census, const uint8_t *needle,
                              size_t needle_len)
{
    if ((offsets == NULL) || (census == NULL) || (needle == NULL) || (count == 0u) || (needle_len == 0u) ||
        (census->total == 0u))
    {
        return;
    }

    // Insertion sort, descending by magnitude, and STABLE. The strict greater-than in the shift
    // test keeps it stable: an equal magnitude does not displace the entry already placed, and
    // anchors testing equally rare symbols keep the spatial spread choose_offsets gave them.
    for (size_t placed = 1u; placed < count; placed += 1u)
    {
        const size_t moving_offset = offsets[placed];
        if (moving_offset >= needle_len)
        {
            continue;
        }
        const uint64_t moving = anchor_steer_magnitude(census, needle[moving_offset]);

        size_t slot = placed;
        while (slot > 0u)
        {
            const size_t settled_offset = offsets[slot - 1u];
            const uint64_t settled =
                (settled_offset < needle_len) ? anchor_steer_magnitude(census, needle[settled_offset]) : 0u;
            if (settled > moving)
            {
                break;
            }
            if (settled == moving)
            {
                break;
            }
            offsets[slot] = offsets[slot - 1u];
            slot -= 1u;
        }
        offsets[slot] = moving_offset;
    }
}

/**
 * @brief Loads a 64 bit value into the fixed width limb form.
 *
 * @param[out] value Where the limbs are written [BORROWS].
 * @param[in]  from  The value to carry.
 * @note Base 2^32 least significant limb first, the layout exact_integer.h declares.
 *       Writing the two limbs directly is reading that declaration, not reaching around it;
 *       there is no decimal text here to route through anchor_exact_from_decimal and converting a
 *       counter to text to parse it back would be slower and just as exact.
 * @note limb[1] exists because the assert at the top of this file holds the engine to 8 limbs or
 *       more.
 */
static void steer_exact_from_u64(AnchorExactInteger *value, uint64_t from)
{
    anchor_exact_zero(value);
    if (from == 0u)
    {
        return;
    }
    value->limb[0] = (uint32_t)(from & 0xFFFFFFFFu);
    value->limb[1] = (uint32_t)(from >> 32);
    value->sign = 1;
}

int anchor_steer_prefers_free(const AnchorFieldCensus *census)
{
    if ((census == NULL) || (census->total == 0u) || (census->distinct == 0u))
    {
        // An empty field distinguishes nothing. It takes the short circuiting engine, the
        // one that ran before any of this and the cheaper of the two on a field with no
        // structure to exploit.
        return 0;
    }

    // Three integers, each built in place, since every exact operation accepts its result aliasing
    // an input. The six this held before came to 768 KiB at 32768 limbs, and with the multiply's
    // accumulator that passes the 1 MiB stack the MSVC linker gives a main thread.
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger term;

    // left = 100 * total^2
    steer_exact_from_u64(&left, census->total);
    if (anchor_exact_multiply(&left, &left, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&term, 100u);
    if (anchor_exact_multiply(&left, &term, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    // right = sum over symbols of count^2, accumulated in the limb form and not in a 64 bit
    // counter. A single count squares to at most total^2, which already passes 2^64 on a four
    // gigabyte corpus, and 256 of them are summed on top of that.
    anchor_exact_zero(&right);
    for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
    {
        if (census->occurrences[symbol] == 0u)
        {
            continue;
        }
        steer_exact_from_u64(&term, census->occurrences[symbol]);
        if (anchor_exact_multiply(&term, &term, &term) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
        if (anchor_exact_add(&right, &term, &right) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
    }

    // right = 85 * distinct * right
    steer_exact_from_u64(&term, 85u);
    if (anchor_exact_multiply(&right, &term, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&term, (uint64_t)census->distinct);
    if (anchor_exact_multiply(&right, &term, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    // The rule reads "flat corpora take the short circuiting engine". The free order one is
    // therefore the branch taken when the effective alphabet does NOT reach the threshold.
    return (anchor_exact_compare(&left, &right) < 0) ? 1 : 0;
}

/* ------------------------------------------------------------------------------------------------
 * Truthy and falsy steering. The signal is the survivor vector, not the symbol histogram.
 *
 * EACH PERMUTATION OF THE ANCHORS IS A NULL, AND EACH NULL IS A STEER. An alignment survives only
 * when every anchor agrees, and a conjunction does not depend on the order of its terms. Every
 * ordering of a given anchor set returns the same count. The orderings therefore form a group of
 * moves that CANNOT change the answer, called a null in this tree. Steering is choosing
 * which element of that group to apply.
 *
 * The safety argument for everything below rests on this alone, and it is structural and not
 * defensive. A planner that samples badly, ranks wrongly, or is outright broken still lands on some
 * element of the null group, and every element yields the same count. The planner moves inside the
 * null and the null has one value. Correctness is therefore not something the planner can spend,
 * and speed is the only currency it holds.
 * ---------------------------------------------------------------------------------------------- */

/**
 * @brief How many currently truthy alignments stay truthy when `offset` is tested.
 *
 * @param[in] alive  One flag per alignment, non-zero for truthy [BORROWS].
 * @param[in] stride Sample every Nth alignment. The ranking is a comparison between candidates.
 *                   A consistent sample ranks them consistently without reading them all.
 * @return           Count of survivors, in the sampled population.
 */
size_t steer_truthy_after(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                          const uint8_t *alive, size_t offset, size_t stride, const AnchorField *any)
{
    // ANY SYMBOL TYPE TAKES THE SCALAR LOOP AND CANNOT TAKE A WIDE ONE. A vectorized scan compares
    // bytes against a broadcast byte, which is a statement about the representation. The oracle is
    // a statement about equality and the engine never learns what it is comparing. There is
    // nothing to broadcast. This path is slower, and the theory describes it; the byte
    // path below is the specialization that can be made wide.
    if (any != NULL)
    {
        size_t standing_any = 0u;

        for (size_t at = 0u; at < any->alignments; at += stride)
        {
            if (alive[at] == 0u)
            {
                continue;
            }
            if (any->same(any->field, at + offset, offset) != 0)
            {
                standing_any += 1u;
            }
        }
        return standing_any;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    const uint8_t wanted = needle[offset];

    // THE WIDEST ENGINE THIS MACHINE CARRIES, ASKED ONCE. The scan is where a planner spends its
    // time, and an engine graded against the portable one but never called is a measurement instead
    // of a speedup. The engine is resolved once and held, because asking the processor on every
    // candidate would cost more than the candidates do.
    //
    // Only at stride one. A sampled scan walks every Nth alignment and the engines count every one.
    // Handing a sampled sweep to one would change what is being counted. Sampling falls through
    // to the loop below, the same code the portable engine runs.
    if (stride == 1u)
    {
        // Resolved through anchor_steer_best_engine, which holds the one dispatch every arm is added
        // to. Reproducing the #if ladder here would be a second copy that a new arm could miss, and a
        // scan that keeps running the old widest arm while a wider one reports itself present has
        // the unused-implementation defect the scan counters exist to catch.
        static const AnchorSteerEngine *chosen = NULL;
        static int resolved = 0;
        if (resolved == 0)
        {
            chosen = anchor_steer_best_engine();
            resolved = 1;
        }
        if (chosen != NULL)
        {
            return chosen->count(corpus, alignments, alive, wanted, offset);
        }
    }

    size_t standing = 0u;
    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] == wanted)
        {
            standing += 1u;
        }
    }
    return standing;
}

/**
 * @brief How many alignments are truthy right now, in the sampled population.
 *
 * @note Sampled at the same stride the candidate scores use. The comparison between "survivors
 *       after this probe" and "survivors before it" is between two counts of the same population.
 *       Mixing a full count with a sampled one would make every probe look like it pruned.
 */
size_t steer_truthy_total(const uint8_t *alive, size_t alignments, size_t stride)
{
    size_t standing = 0u;

    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] != 0u)
        {
            standing += 1u;
        }
    }
    return standing;
}

/**
 * @brief Turns falsy every alignment that disagrees at `offset`, over the whole population.
 *
 * @note Applied at stride one even where the ranking was sampled. The ranking is allowed to be
 *       approximate because it only picks between nulls; the survivor set is not, because the next
 *       level ranks against it and an approximate survivor set would compound.
 */
void steer_make_falsy(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                      uint8_t *alive, size_t offset, const AnchorField *any)
{
    if (any != NULL)
    {
        for (size_t at = 0u; at < any->alignments; at += 1u)
        {
            if (alive[at] == 0u)
            {
                continue;
            }
            if (any->same(any->field, at + offset, offset) == 0)
            {
                alive[at] = 0u;
            }
        }
        return;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    const uint8_t wanted = needle[offset];

    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] != wanted)
        {
            alive[at] = 0u;
        }
    }
}
