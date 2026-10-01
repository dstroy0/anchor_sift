
// exact_integer_hash.c: the hash and the agreement
#include "exact_integer_internal.h"

uint64_t anchor_exact_hash(const AnchorExactInteger *value)
{
    // FNV-1a over the limbs, with the sign folded in last so two magnitudes that differ only in
    // sign do not land on one bucket.
    uint64_t hash = 0xCBF29CE484222325u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        hash ^= (uint64_t)value->limb[at];
        hash *= 0x100000001B3u;
    }
    hash ^= (uint64_t)(uint32_t)value->sign;
    hash *= 0x100000001B3u;
    return hash;
}

/**
 * @brief The agreement count without a table, for when the table cannot be allocated.
 *
 * @param[in] equal     Whether two integers hold the same value [BORROWS].
 * @param[in] positions Positions carrying values, in any order [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              The count anchor_exact_agreement_using returns with a table.
 * @note Quadratic in `count` and needs no memory. A position is counted at its last entry only, and
 *       a displaced position is matched to the last entry equal to it, which keeps the last value
 *       at a repeated position.
 */
static size_t agreement_without_table(int (*equal)(const AnchorExactInteger *left, const AnchorExactInteger *right),
                                      const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                                      const AnchorExactInteger *lag)
{
    EXACT_VALUE(moved);
    if (!EXACT_SCRATCH_VALID(moved))
    {
        return 0u;
    }
    size_t agreed = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        int repeated_later = 0;
        for (size_t later = at + 1u; later < count; later++)
        {
            if (equal(&positions[later], &positions[at]) != 0)
            {
                repeated_later = 1;
                break;
            }
        }
        if (repeated_later != 0)
        {
            continue;
        }

        if (anchor_exact_add(&positions[at], lag, moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t found = count;
        for (size_t other = 0u; other < count; other++)
        {
            if (equal(&positions[other], moved) != 0)
            {
                found = other;
            }
        }
        if ((found < count) && (values[found] == values[at]))
        {
            agreed++;
        }
    }
    EXACT_VALUE_RELEASE(moved);
    return agreed;
}

size_t anchor_exact_agreement(const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                              const AnchorExactInteger *lag)
{
    return anchor_exact_agreement_using(anchor_exact_equal, positions, values, count, lag);
}

size_t anchor_exact_agreement_using(int (*equal)(const AnchorExactInteger *left, const AnchorExactInteger *right),
                                    const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                                    const AnchorExactInteger *lag)
{
    // What the measure asks of the set is membership: is there a point exactly one lag away, and
    // does it carry the same value. A set has no ordering, and a search that walks one imposes a
    // structure the domain never had and pays a full limb comparison at every step of it.
    //
    // An open addressed table keyed on the hash answers the same question in one probe on average.
    // The hash is not trusted on its own: a hit is confirmed with a full comparison, since two
    // distinct coordinates reading as equal is the error this whole path exists to prevent.
    //
    // This is what the python side has always done. Its `placed` is a dict built by overwriting,
    // which keeps the last value at a repeated position and holds each position once. The table
    // below keeps the last entry and the count walks the table, which gives the same count.
    if (count == 0u)
    {
        return 0u;
    }

    // The slot count is the power of two at or above twice `count`, which is below four times
    // `count`. Past this bound that product or its size in bytes wraps size_t, and the scan below
    // needs no allocation to answer.
    const size_t widest = SIZE_MAX / (4u * sizeof(size_t));
    if (count > widest)
    {
        return agreement_without_table(equal, positions, values, count, lag);
    }

    size_t slots = 1u;
    while (slots < (count * 2u))
    {
        slots <<= 1u;
    }

    size_t *table = (size_t *)malloc(slots * sizeof(size_t));
    if (table == NULL)
    {
        // No table. The scan answers instead. Slower and correct beats absent.
        return agreement_without_table(equal, positions, values, count, lag);
    }

    for (size_t at = 0u; at < slots; at++)
    {
        table[at] = count;
    }

    const size_t mask = slots - 1u;
    for (size_t at = 0u; at < count; at++)
    {
        size_t slot = (size_t)(anchor_exact_hash(&positions[at]) & (uint64_t)mask);
        while ((table[slot] != count) && (equal(&positions[table[slot]], &positions[at]) == 0))
        {
            slot = (slot + 1u) & mask;
        }
        // An empty slot takes the entry. A slot already holding this position takes it too. The
        // table ends up holding the last entry for every position.
        table[slot] = at;
    }

    EXACT_VALUE(moved);
    if (!EXACT_SCRATCH_VALID(moved))
    {
        free(table);
        return agreement_without_table(equal, positions, values, count, lag);
    }
    size_t agreed = 0u;
    for (size_t table_slot = 0u; table_slot < slots; table_slot++)
    {
        const size_t at = table[table_slot];
        if (at == count)
        {
            continue;
        }
        if (anchor_exact_add(&positions[at], lag, moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t slot = (size_t)(anchor_exact_hash(moved) & (uint64_t)mask);
        while (table[slot] != count)
        {
            if (equal(&positions[table[slot]], moved) != 0)
            {
                if (values[table[slot]] == values[at])
                {
                    agreed++;
                }
                break;
            }
            slot = (slot + 1u) & mask;
        }
    }

    EXACT_VALUE_RELEASE(moved);
    free(table);
    return agreed;
}
