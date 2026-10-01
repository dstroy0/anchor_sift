
// orior_steer_plan.c: descent, the recursive plan and the probes
#include "orior_internal.h"

/** @brief Shared entry the two planners differ only in their candidate set. */
static size_t steer_descend(size_t *offsets, size_t count, const uint8_t *corpus, size_t corpus_len,
                            const uint8_t *needle, size_t needle_len, uint8_t *survivors, size_t survivors_length,
                            size_t sample_stride, int spawning, int force_full_depth, const AnchorField *any,
                            int resume)
{
    // A field of any symbol type supplies its own extents and its own validity, and the byte
    // pointers go unread. Checked separately and not by casting the field into the byte
    // pointers to satisfy a null test, which would pass the guard while meaning nothing.
    if (any != NULL)
    {
        if ((offsets == NULL) || (survivors == NULL) || (count == 0u) || (any->same == NULL) ||
            (any->alignments == 0u) || (any->needle_len == 0u))
        {
            return 0u;
        }
        needle_len = any->needle_len;
        corpus_len = (any->alignments + any->needle_len) - 1u;
    }
    else if ((offsets == NULL) || (corpus == NULL) || (needle == NULL) || (survivors == NULL) || (count == 0u) ||
             (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0u;
    }
    if (count > ANCHOR_STEER_ANCHORS)
    {
        return 0u;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    if (survivors_length < alignments)
    {
        // FAILS CLOSED. The kernel allocates nothing. A buffer that does not reach the alignment
        // count errors, and never worked around by planning on part of the field.
        return 0u;
    }

    const size_t stride = (sample_stride == 0u) ? 1u : sample_stride;

    // Every alignment starts standing and a probe can only ever take one down. That direction
    // makes the descent safe to stop at any level: the set shrinks and never grows back.
    //
    // ON RESUME THE SURVIVORS ARE THE INPUT, NOT RESET. A caller composes a recursive spawn by
    // running one descent, then running the next over the survivors the last one left. The child
    // reads only what the parent kept standing and its cost is the survivor count and not the whole
    // field. The engine cannot check that an incoming survivor set is a valid superset of the true
    // occurrences; that obligation is the caller's, and it holds when the set came from an earlier
    // descent on this field. A lone survivor is still not an answer: it has passed only the probes
    // placed so far, and the caller verifies it against the conditions not yet asked with a full
    // compare before calling it found.
    if (resume == 0)
    {
        for (size_t at = 0u; at < alignments; at += 1u)
        {
            survivors[at] = 1u;
        }
    }

    size_t chosen[ANCHOR_STEER_ANCHORS];
    size_t placed = 0u;

    // THE BOUNDED DESCENT. One coarm per level, the level count fixed at `count`, which the guard
    // above holds at or under ANCHOR_STEER_ANCHORS. No branch in here lets the corpus change how
    // many levels run, only which offset a level picks. The depth is decided before the program
    // starts and this loop terminates for the same reason a for loop over a fixed array does.
    while (placed < count)
    {
        size_t best_offset = 0u;
        size_t best_standing = (size_t)-1;
        int found = 0;

        const size_t candidates = spawning ? needle_len : count;
        for (size_t which = 0u; which < candidates; which += 1u)
        {
            const size_t offset = spawning ? which : offsets[which];
            if (offset >= needle_len)
            {
                continue;
            }

            int already = 0;
            for (size_t seen = 0u; seen < placed; seen += 1u)
            {
                if (chosen[seen] == offset)
                {
                    already = 1;
                    break;
                }
            }
            if (already != 0)
            {
                continue;
            }

            const size_t standing =
                steer_truthy_after(corpus, corpus_len, needle, needle_len, survivors, offset, stride, any);
            // Strictly fewer survivors wins. A tie keeps the earlier candidate, and
            // the descent is therefore deterministic on identical input.
            if ((found == 0) || (standing < best_standing))
            {
                best_standing = standing;
                best_offset = offset;
                found = 1;
            }
        }

        if (found == 0)
        {
            break;
        }

        // DESTROY WHAT DOES NOT PRUNE. A probe that leaves the truthy population exactly as it
        // found it rejects nothing an earlier probe had not already rejected. Placing it would read
        // a byte per alignment and buy none. The descent stops instead, and every level below it is
        // destroyed with it. `placed` is returned. The caller learns how many probes survived
        // and is never handed dead ones to evaluate.
        //
        // This is the general form of what orior_anchors_for does in one special case. That
        // function returns a single anchor on a periodic corpus, because at a period every anchor
        // tests the same congruence and the ones after the first are pure cost. Here the judgment
        // is MEASURED per level against the field instead of inferred from a period, which also
        // catches fields whose redundancy no period search would name.
        if ((force_full_depth == 0) && (best_standing >= steer_truthy_total(survivors, alignments, stride)))
        {
            break;
        }

        chosen[placed] = best_offset;
        placed += 1u;
        steer_make_falsy(corpus, corpus_len, needle, needle_len, survivors, best_offset, any);
    }

    for (size_t slot = 0u; slot < placed; slot += 1u)
    {
        offsets[slot] = chosen[slot];
    }
    return placed;
}

size_t anchor_steer_plan_recursive(const AnchorSteerDescent *args)
{
    if (args == NULL)
    {
        return 0u;
    }

    // Reordering. `spawning` is 0 and the candidates are the offsets the caller already placed.
    // force_full_depth is read from the argument even here: a caller checking that stopping equals
    // continuing has to be able to force the reordering descent too, not only the spawning one.
    return steer_descend(args->offsets, args->count, args->corpus, args->corpus_len, args->needle, args->needle_len,
                         args->survivors, args->survivors_length, args->sample_stride, 0, args->force_full_depth,
                         args->any, args->resume);
}

size_t anchor_steer_spawn_coarms(const AnchorSteerDescent *args)
{
    if (args == NULL)
    {
        return 0u;
    }

    // Spawning. `spawning` is 1 and the candidates are every position in the needle.
    return steer_descend(args->offsets, args->count, args->corpus, args->corpus_len, args->needle, args->needle_len,
                         args->survivors, args->survivors_length, args->sample_stride, 1, args->force_full_depth,
                         args->any, args->resume);
}

int anchor_steer_probe_fits(const AnchorProbe *probe, size_t needle_len)
{
    if ((probe == NULL) || (probe->length == 0u) || (needle_len == 0u))
    {
        return 0;
    }
    if (probe->origin >= needle_len)
    {
        return 0;
    }
    if (probe->length == 1u)
    {
        return 1;
    }
    if (probe->step == 0u)
    {
        // A line of length greater than one with no step reads one position repeatedly. That is an
        // arm wearing an eye's shape. It errors here and never silently collapsed.
        return 0;
    }

    // The last position is origin + step*(length-1). Formed by division against the capacity actually
    // left, which errors on a step and length whose product would wrap size_t instead of letting it
    // wrap into a position that passes a bounds test.
    const size_t range = needle_len - 1u - probe->origin;
    return ((probe->length - 1u) <= (range / probe->step)) ? 1 : 0;
}

/** @brief Whether one alignment agrees with the needle at every position a probe reads. */
static int steer_probe_agrees(const uint8_t *corpus, const uint8_t *needle, const AnchorProbe *probe, size_t at)
{
    for (size_t step = 0u; step < probe->length; step += 1u)
    {
        const size_t offset = probe->origin + (step * probe->step);
        if (corpus[at + offset] != needle[offset])
        {
            return 0;
        }
    }
    return 1;
}

/** @brief Truthy alignments remaining if `probe` were placed, in the sampled population. */
size_t steer_truthy_after_probe(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                const uint8_t *alive, const AnchorProbe *probe, size_t stride)
{
    const size_t alignments = (corpus_len - needle_len) + 1u;
    size_t standing = 0u;

    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (steer_probe_agrees(corpus, needle, probe, at) != 0)
        {
            standing += 1u;
        }
    }
    return standing;
}

/** @brief Turns falsy every alignment a probe rejects, over the whole population. */
void steer_make_falsy_probe(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            uint8_t *alive, const AnchorProbe *probe)
{
    const size_t alignments = (corpus_len - needle_len) + 1u;

    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (steer_probe_agrees(corpus, needle, probe, at) == 0)
        {
            alive[at] = 0u;
        }
    }
}
