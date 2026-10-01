
// anchor_sift_field.c: field classes and projections
#include "anchor_sift_internal.h"

/**
 * @brief Numbers one population into classes and puts those classes in rarity order.
 *
 * @param[in]  same_in_field         Equality between two positions of the population [BORROWS].
 * @param[in]  field                 Passed to the oracle untouched [BORROWS].
 * @param[in]  length                Positions in the population.
 * @param[out] class_of_position     Which class each position fell in [BORROWS].
 * @param[out] members_in_class      How many positions each class holds [BORROWS].
 * @param[out] rarity_place_of_class Where each class sits in the rarity order [BORROWS].
 * @return                           Classes surviving the merges.
 *
 * @note Static and positional, which is where a long parameter list is allowed to live, and the
 *       same shape steer_descend uses for the same reason. The public entries take one const
 *       argument pointer each and both call this.
 * @note THE POPULATION IS THE ARGUMENT. One call numbers one
 *       population. Every rank it produces is comparable with every other rank it produced and
 *       with none produced elsewhere. anchor_field_pair_project hands it a corpus and a needle
 *       together for exactly that reason.
 */
static size_t field_number_classes(AnchorSameAt same_in_field, const void *field, size_t length,
                                   uint32_t *class_of_position, uint32_t *members_in_class,
                                   uint32_t *rarity_place_of_class)
{
    for (size_t at = 0u; at < length; at += 1u)
    {
        class_of_position[at] = (uint32_t)at;
        members_in_class[at] = 0u;
        rarity_place_of_class[at] = 0u;
    }

    // CLASSES ARE CONNECTED COMPONENTS AND NOT FIRST MATCHES. THIS KEEPS IT SOUND FOR A
    // PREDICATE THAT IS NOT TRANSITIVE. Soundness needs agreement to imply a shared rank. It does
    // NOT need a shared rank to imply agreement. The labeling must be a superset of the
    // relation, and the smallest superset that is an equivalence is the transitive closure.
    //
    // EVERY PAIR, NOT EVERY REPRESENTATIVE. Comparing a position against one member of each class is
    // correct only where agreement is transitive. Over 0 1 2 3 4 at a tolerance of two, position 3
    // agrees with 2 and not with 0. Comparing against class zero's representative opens a second
    // class while 2 and 3 agree, and two agreeing positions in different classes breaks the
    // necessary condition outright. The closure of a graph reachable only through a pairwise probe
    // needs the pairs.
    for (size_t at = 0u; at < length; at += 1u)
    {
        for (size_t before = 0u; before < at; before += 1u)
        {
            size_t mine = at;
            size_t theirs = before;

            while (class_of_position[mine] != mine)
            {
                mine = class_of_position[mine];
            }
            while (class_of_position[theirs] != theirs)
            {
                theirs = class_of_position[theirs];
            }

            // Already one class. The predicate can say nothing new about this pair. The only
            // saving available, and a real one on a chained field.
            if (mine == theirs)
            {
                continue;
            }
            if (same_in_field(field, at, before) == 0)
            {
                continue;
            }
            class_of_position[theirs] = (uint32_t)mine;
        }
    }

    // Resolve every position onto its class, then count the members of each.
    for (size_t at = 0u; at < length; at += 1u)
    {
        size_t root = at;

        while (class_of_position[root] != root)
        {
            root = class_of_position[root];
        }
        class_of_position[at] = (uint32_t)root;
        members_in_class[root] += 1u;
    }

    size_t classes = 0u;
    for (size_t which = 0u; which < length; which += 1u)
    {
        if (members_in_class[which] != 0u)
        {
            classes += 1u;
        }
    }

    // THE CLASS COUNT IS UNBOUNDED AND ONLY THE OUTPUT RANK IS CLAMPED, the whole point of
    // carrying these buffers. Classes are ordered by rarity across every one of them and the clamp
    // is applied at relabel time. A field of a thousand classes keeps its 255 rarest apart and
    // merges the commonest into rank 255.
    //
    // The rarest class is the best probe the steering has.
    //
    // A class's place is the number of classes strictly rarer than it, with the class index breaking
    // ties so the order is total and does not depend on the arrangement. THE TIE BREAK IS WHY TWO
    // POPULATIONS CANNOT SHARE AN ORDER: two singletons tie, the index decides, and the indices come
    // from where the positions sat in whichever field was numbered. Number the two together and
    // there is one index space and one answer.
    for (size_t which = 0u; which < length; which += 1u)
    {
        if (members_in_class[which] == 0u)
        {
            continue;
        }

        size_t rarer = 0u;
        for (size_t other = 0u; other < length; other += 1u)
        {
            if (members_in_class[other] == 0u)
            {
                continue;
            }
            if (members_in_class[other] < members_in_class[which])
            {
                rarer += 1u;
            }
            else if ((members_in_class[other] == members_in_class[which]) && (other < which))
            {
                rarer += 1u;
            }
        }
        rarity_place_of_class[which] = (uint32_t)rarer;
    }
    return classes;
}

/**
 * @brief Clamps one class's rarity place into a byte rank.
 *
 * @param[in] place Where the class sits in the rarity order.
 * @return          The place, or 255 where it sits past the last rank a byte can hold.
 *
 * @note Merging costs discrimination and never soundness. One class takes one place across the
 *       whole population. Symbol agreement still implies rank agreement after the clamp, and
 *       that is the direction the filter needs. The alignments a merge admits are rejected by the
 *       full compare.
 */
static uint8_t field_rank_from_place(uint32_t place)
{
    return (uint8_t)((place < 255u) ? place : 255u);
}

int anchor_field_project(const AnchorFieldProjection *args)
{
    if (args == NULL)
    {
        return 0;
    }
    if ((args->same_in_field == NULL) || (args->ranks == NULL) || (args->length == 0u) ||
        (args->class_of_position == NULL) || (args->members_in_class == NULL) || (args->rarity_place_of_class == NULL))
    {
        return 0;
    }

    // Class labels are stored as uint32_t positions. A field wider than that would alias two
    // positions onto one label and merge classes the oracle never joined. It errors. The cast
    // widens a 32 bit constant into size_t, which holds it on every target this builds for.
    if (args->length > (size_t)UINT32_MAX)
    {
        return 0;
    }

    // FAILS CLOSED ON A SHORT BUFFER. Every position can be its own class. The three arrays have
    // to reach `length` or a field of singletons writes past their end.
    if (args->classes_length < args->length)
    {
        // WRITES NOTHING, LIKE EVERY OTHER ERROR HERE. Fail closed says a request that cannot be met
        // changes no state: a caller cannot tell an errored zero from a measured zero. No error
        // touches `distinct` and the return value is the only thing to read.
        return 0;
    }

    const size_t length = args->length;
    const size_t classes = field_number_classes(args->same_in_field, args->field, length, args->class_of_position,
                                                args->members_in_class, args->rarity_place_of_class);

    for (size_t at = 0u; at < length; at += 1u)
    {
        args->ranks[at] = field_rank_from_place(args->rarity_place_of_class[args->class_of_position[at]]);
    }

    if (args->distinct != NULL)
    {
        // CLASSES AND NOT SLOTS EVER OPENED. A chained field once reported 18 while every position
        // carried one rank, because the count returned was the number of labels discovery had
        // opened and not the number surviving the merges. A caller reads this to decide whether
        // a projection is worth running. A healthy number on a collapsed field sends them onto a
        // projection that refutes nothing.
        *args->distinct = classes;
    }
    return 1;
}

int anchor_field_pair_project(const AnchorFieldPairProjection *args)
{
    if (args == NULL)
    {
        return 0;
    }
    if ((args->same_in_field == NULL) || (args->corpus_ranks == NULL) || (args->needle_ranks == NULL) ||
        (args->class_of_position == NULL) || (args->members_in_class == NULL) ||
        (args->rarity_place_of_class == NULL) || (args->corpus_length == 0u) || (args->needle_length == 0u) ||
        (args->needle_length > args->corpus_length))
    {
        return 0;
    }

    // THE JOINT LENGTH IS A SUM. IT IS CHECKED BEFORE IT IS FORMED. Past this point the addition
    // would wrap to a small length, pass the buffer check below, and project a field far shorter than
    // the one the caller described.
    if (args->corpus_length > (SIZE_MAX - args->needle_length))
    {
        return 0;
    }
    const size_t length = args->corpus_length + args->needle_length;

    // Class labels are stored as uint32_t positions. A joint field wider than that would alias two
    // positions onto one label and merge classes the oracle never joined. It errors. The cast
    // widens a 32 bit constant into size_t, which holds it on every target this builds for.
    if (length > (size_t)UINT32_MAX)
    {
        return 0;
    }
    if (args->classes_length < length)
    {
        return 0;
    }

    const size_t classes = field_number_classes(args->same_in_field, args->field, length, args->class_of_position,
                                                args->members_in_class, args->rarity_place_of_class);

    // ONE POPULATION READ TWO WAYS. Both loops look up the same rarity order. A class present on both
    // sides takes one rank on both, and rank disagreement between a corpus position and a needle
    // position proves the two fell in different classes. Two separate projections cannot give that
    // necessary condition.
    for (size_t at = 0u; at < args->corpus_length; at += 1u)
    {
        args->corpus_ranks[at] = field_rank_from_place(args->rarity_place_of_class[args->class_of_position[at]]);
    }
    for (size_t at = 0u; at < args->needle_length; at += 1u)
    {
        const size_t joint = args->corpus_length + at;

        args->needle_ranks[at] = field_rank_from_place(args->rarity_place_of_class[args->class_of_position[joint]]);
    }

    if (args->distinct != NULL)
    {
        *args->distinct = classes;
    }
    return 1;
}
