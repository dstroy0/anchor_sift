
// anchor_sift_field.h: fields and their projections (anchor_sift.h includes the parts in order)
#ifndef ANCHOR_SIFT_FIELD_H
#define ANCHOR_SIFT_FIELD_H

#include "anchor_sift_core.h"

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * @brief Answers whether two positions carry the same symbol.
     *
     * @param[in] field     Whatever the caller is searching, opaque to the engine [BORROWS].
     * @param[in] corpus_at Position in the field.
     * @param[in] needle_at Position in the pattern.
     * @return              Non-zero where the two positions carry the same symbol, zero otherwise.
     *
     * @note THIS IS THE WHOLE INTERFACE THE ENGINE NEEDS TO A SYMBOL. Not an order, not a hash, not a
     *       size, not an enumeration of the alphabet. Equality at two positions only, the
     *       one relation the soundness proof uses: a subset of a pattern's points is a necessary
     *       condition, and the proof reads no order, no dimension and no alphabet.
     * @note A symbol may therefore be a byte, a 32 bit sample, an exact rational, a point in eight
     *       dimensions, a pointer compared by identity, or a value only its owner can compare. The
     *       engine never learns which. An alphabet that cannot be enumerated or hashed costs it
     *       nothing.
     * @note THIS ENGINE WAS THE NARROW ONE AND THE REST OF THE TREE WAS NOT. bench_lattice has taken a
     *       callback since it was written, and the python cascade has never needed bytes either: its
     *       `survivors` indexes a dict by symbol and `positions_by_symbol` builds that dict from any
     *       iterable of values. It requires equality and hashability only. A
     *       crystallography example feeds it element strings and has done so for longer than this note
     *       has existed. The C entries demanded a `uint8_t *` and were therefore narrower both than the
     *       proof they implement and than the python engine they are checked against.
     * @note The two are STILL not equivalent and the difference runs the other way now. A dict key must
     *       be hashable; this oracle asks only whether two positions are equal. A value that cannot be
     *       hashed, or whose equality is expensive and whose hash would be a lie, can be searched here
     *       and cannot be searched there. Anyone grading the two engines against each other should know
     *       which fields only one of them can accept.
     * @warning Must be a pure function of the two positions for the duration of a call. The engine
     *          reads the same position more than once and assumes the answer does not move under it.
     */
    typedef int (*AnchorSameAt)(const void *field, size_t corpus_at, size_t needle_at);

    /**
     * @brief A field of any symbol type, reached only through equality.
     *
     * @note Carries no element size and no element pointer. The engine indexes positions and asks the
     *       oracle about them. Where the symbols live and how wide they are belong to the caller.
     * @warning `alignments` is the number of positions that can host a pattern, which for a linear field
     *          of `n` symbols is `n - needle_len + 1`. The engine cannot compute it, because it does not
     *          know the field's shape, and a caller that supplies it wrongly gets a wrong sweep and
     *          no error.
     */
    typedef struct
    {
        AnchorSameAt same; /**< Equality oracle. Never null. */
        const void *field; /**< Passed to the oracle untouched, never dereferenced here [BORROWS]. May
                            *   be null ONLY where the ORACLE does not dereference it either, which
                            *   means an oracle reaching its data some other way. The engine never uses
                            *   it. "if unused" read as a condition always satisfied; the condition
                            *   is on the oracle. Passing null to an oracle that reads it faults inside
                            *   the oracle, where the engine cannot see it coming. */
        size_t alignments; /**< Positions that can host the pattern. Non-zero. */
        size_t needle_len; /**< Positions the pattern holds. Non-zero. */
    } AnchorField;

    /**
     * @brief Projects a field of any symbol type onto a field of rarity ranks.
     *
     * @param[in] args What to project and where to put it [BORROWS].
     * @return         1 where the projection was written, 0 where it errored.
     *
     * @warning RANKS FROM TWO CALLS ARE NOT COMPARABLE, AND COMPARING THEM LOSES TRUE OCCURRENCES.
     *          A rank is not a property of a symbol. It is a property of a symbol WITHIN THE POPULATION
     *          THIS CALL SAW, and the population is part of the answer. The class a position falls in
     *          comes from the oracle, which the CALLER supplies. It is the same relation whatever
     *          field it is applied to. The rarity place comes from counting THIS field. It is not.
     *          The rank fuses the two and only the first half survives the trip to another field.
     *
     *          It is a hash and a nonce. The class is the digest and the population is the nonce, and a
     *          digest computed under one nonce cannot be checked against a digest computed under
     *          another however identical the input was.
     *
     *          THE FAILURE IS SILENT AND IT IS IN THE UNSAFE DIRECTION. Take symbols where A occurs
     *          once, B ten times and C a hundred times, and search for the needle C C B A. Projected
     *          alone, the corpus ranks A below B because one is rarer than ten. Projected alone, the
     *          needle holds one A and one B, they TIE, and the tie breaks on class index the other way
     *          round. Rank disagreement then reports symbol disagreement where the symbols agree, a
     *          probe refutes an alignment that truly matches, and the count comes back one short with
     *          nothing in the return value to say so.
     *
     *          That inverts the necessary condition this construction rests on. Everywhere else in this
     *          file an ordering decision is a null: a wrong order costs reads and leaves the count
     *          unchanged. Here a wrong order loses a true occurrence.
     *
     *          Use anchor_field_pair_project to search one field for another. It numbers both in one
     *          call, which gives one population and one rarity order, and the ranks it writes are
     *          comparable by construction. This entry remains the one to call for describing a single
     *          field.
     *
     * @note THE COMPONENT COUNT IS UNBOUNDED AND ONLY THE OUTPUT IS CLAMPED. Classes are discovered
     *       with no ceiling, ordered by rarity across every one of them, and the byte rank is clamped
     *       at relabel time. A field with a thousand classes keeps its 255 rarest apart and merges
     *       the commonest into rank 255. That is the direction the steering needs, because a probe's
     *       survivor count is its class frequency and the rarest class is the best probe available.
     *       The class buffers exist to carry those components; the kernel allocates nothing.
     *
     * @note `same_in_field` NEED NOT BE TRANSITIVE, AND THE CLASSES ARE ITS TRANSITIVE CLOSURE. This
     *       matters because the predicate that motivates having an oracle at all is not transitive: a
     *       tolerance match over real valued coordinates is meaningful, and `a` within tolerance of `b`
     *       and `b` of `c` does not put `a` within tolerance of `c`.
     *       `examples/proteins/5_sift/protein_domain.py:66-74` is exactly that, and states why exact
     *       equality is the wrong test on a continuous domain.
     *
     *       Soundness needs agreement to imply a shared rank. It does NOT need a shared rank to imply
     *       agreement. The labeling has to be a superset of the relation, and the smallest superset
     *       that is an equivalence is the transitive closure. Classes are therefore connected
     *       components: a position joins every class it matches and merges them.
     *
     * @warning THE COST OF TAKING THE CLOSURE IS CHAINING. A loose tolerance can walk the whole field
     *          into one component through a path of near neighbors, none of which agree with the ends.
     *          One class ranks everything alike, every rank probe then refutes nothing, and the search
     *          falls back to the exact compare at every alignment. That is useless and it is exactly
     *          sound, since a probe that rejects nothing is still a necessary condition. Tighten the
     *          predicate where it happens; the symptom is `distinct` coming back as one on a field the
     *          caller expects to be varied.
     * @warning TAKES A DIFFERENT ORACLE FROM AnchorField's, AND THE DISTINCTION IS NOT COSMETIC.
     *          AnchorSameAt as used by a descent answers about a CORPUS position against a NEEDLE
     *          position, which are two index spaces. Grouping a field into classes compares two
     *          positions of the FIELD. Passing a descent's oracle here indexes the needle with a field
     *          position and reads off the end of it. That fault segfaulted the suite, and this signature was
     *          changed to prevent it.
     *
     * WHY PROJECT AT ALL. A probe only has to be a necessary condition of an occurrence. Within one
     * projection, two positions in one class carry one rank. Rank disagreement proves symbol
     * disagreement and a rank probe refutes a subset of what a symbol probe refutes. Rank agreement does
     * not prove symbol agreement, and a filter does not need it to. The engine's construction is that a
     * necessary condition may be weaker than the thing it screens for.
     *
     * What that buys is the wide path. An equality oracle cannot be vectorized, because a wide compare
     * is a statement about a representation and the oracle deliberately hides one. Ranks are bytes.
     * A field of any symbol type therefore becomes a field the existing byte engine reads at full speed, AVX2
     * scan included. A real valued alphabet, a point in eight dimensions and an opaque handle all
     * project to the same shape and all run on the same loop.
     *
     * @note Ranks are ORDERED BY RARITY, rarest first, the order the steering already wants.
     *       The rank is therefore not an arbitrary label: rank zero is the class that refutes most
     *       alignments, and a planner reading the projected field gets the entropy ordering for free.
     * @note A SEARCH OVER RANK FIELDS COUNTS RANK MATCHES, AND THAT EQUALS THE SYMBOL COUNT ONLY AT 256
     *       CLASSES OR FEWER. Places then run from 0 to 255 and none is clamped. One rank names one
     *       class and the two counts are the same integer. Past 256 classes every class at place 255 or
     *       later takes rank 255, alignments whose symbols differ can agree on every rank, and the byte
     *       engine's full compare cannot remove them, because on rank fields it compares ranks. The
     *       count is then an upper bound. It never falls below the symbol count, and case 13 in
     *       utils/test/engine/nbody/anchor_sift/test_adversarial_*.c measures it above: 44 against 1 on a 300-class field.
     * For an exact count past 256 classes, check the rank survivors against the symbols through the oracle, or give the
     * oracle to a descent directly.
     * @warning COSTS UP TO `length` SQUARED ORACLE CALLS AND THAT IS NOT A LOOSE BOUND. Computing the
     *          transitive closure of a graph reachable only through a pairwise probe needs the pairs,
     *          and the predicate may be one the caller chose for being approximate. There is no
     *          correct shortcut. The only saving taken is skipping a pair already in one component,
     *          which is real on a chained field and nothing on a field of singletons.
     *
     *          Comparing each position against one representative per class is `length` times
     *          `distinct` and is correct ONLY for a transitive predicate. It is not offered as a fast
     *          path, because selecting it would be asserting transitivity and the cost of being wrong
     *          is a silently wrong answer.
     *
     *          A field of a few thousand positions projects in a moment; one of a hundred thousand does
     *          not. Project a representative slice, or do not project at all and pass the oracle
     *          straight to a descent, which needs no closure and no projection and costs nothing extra.
     */
    typedef struct
    {
        AnchorSameAt same_in_field;      /**< Equality between two positions OF THE FIELD. Never null. */
        const void *field;               /**< Passed to the oracle untouched, never dereferenced here
                                          *   [BORROWS]. May be null ONLY where the oracle does not
                                          *   dereference it either, which means an oracle reaching its
                                          *   data some other way. Passing null to an oracle that reads
                                          *   it faults inside the oracle, and the engine cannot see
                                          *   that coming. */
        size_t length;                   /**< Positions to project. Non-zero. */
        uint8_t *ranks;                  /**< One rarity rank per position, written whole [BORROWS]. */
        uint32_t *class_of_position;     /**< Which class each position fell in, one entry per position,
                                          *   written during the call [BORROWS]. */
        uint32_t *members_in_class;      /**< How many positions each class holds, indexed by the class,
                                          *   written during the call [BORROWS]. */
        uint32_t *rarity_place_of_class; /**< Where each class sits in the rarity order, indexed by the
                                          *   class, written during the call [BORROWS]. */
        size_t classes_length;           /**< Entries each of the three above holds. Must reach
                                          *   `length`, since every position can be its own class. */
        size_t *distinct;                /**< Where the class count is written, or NULL [BORROWS]. */
    } AnchorFieldProjection;

    int anchor_field_project(const AnchorFieldProjection *args);

    /**
     * @brief Numbers a corpus and a needle in ONE population. Their ranks can be compared.
     *
     * @note WHY THIS EXISTS AT ALL. anchor_field_project projects one field and its ranks mean something
     *       only inside it. Two separate calls produce two rarity orders over two populations, and a
     *       rank probe run across them refutes alignments whose symbols agree. The other ordering
     *       decisions in this file cost reads when they are wrong. This one loses true occurrences. A
     *       warning on the single-field entry can be read past. A caller of this entry cannot reach the
     *       broken construction at all, because the entry numbers both sides in one call.
     *
     * @note THE JOINT INDEX SPACE, which the caller's oracle must answer over. Positions `0` through
     *       `corpus_length - 1` are the corpus. Positions `corpus_length` through
     *       `corpus_length + needle_length - 1` are the needle. `same_in_field` is asked about two
     *       JOINT positions and has to reach whichever side each one names. Concatenation is the
     *       obvious way to hold that and it is not the only one; the engine never dereferences the
     *       field and does not care.
     *
     * @note THE ORACLE HERE IS FIELD AGAINST FIELD, NOT CORPUS AGAINST NEEDLE. It takes two joint
     *       positions drawn from one space. `AnchorField.same` in a descent takes a CORPUS position and
     *       a NEEDLE position, which are two spaces. The two have the same C type and different
     *       meanings. The compiler cannot catch the swap and passing one where the other belongs
     *       reads off the end of something.
     */
    typedef struct
    {
        AnchorSameAt same_in_field;      /**< Equality between two positions of the JOINT field. Never
                                          *   null. Asked about joint positions, never about a corpus
                                          *   position paired with a needle position. */
        const void *field;               /**< Passed to the oracle untouched, never dereferenced here
                                          *   [BORROWS]. May be null ONLY where the oracle reaches its
                                          *   data some other way. */
        size_t corpus_length;            /**< Corpus positions, at joint `0` onward. Non-zero. */
        size_t needle_length;            /**< Needle positions, at joint `corpus_length` onward.
                                          *   Non-zero, and no longer than `corpus_length`. */
        uint8_t *corpus_ranks;           /**< `corpus_length` ranks for the corpus side [BORROWS]. */
        uint8_t *needle_ranks;           /**< `needle_length` ranks for the needle side [BORROWS]. */
        uint32_t *class_of_position;     /**< Which class each joint position fell in, one entry per
                                          *   joint position, written during the call [BORROWS]. */
        uint32_t *members_in_class;      /**< How many joint positions each class holds, indexed by the
                                          *   class, written during the call [BORROWS]. */
        uint32_t *rarity_place_of_class; /**< Where each class sits in the one rarity order, indexed by
                                          *   the class, written during the call [BORROWS]. */
        size_t classes_length;           /**< Entries each of the three above holds. Must reach
                                          *   `corpus_length + needle_length`, since every joint
                                          *   position can be its own class. */
        size_t *distinct;                /**< Where the class count over the JOINT field is written, or
                                          *   NULL [BORROWS]. */
    } AnchorFieldPairProjection;

    /**
     * @brief Projects a corpus and a needle onto one rarity order, writing each side its own ranks.
     *
     * @param[in] args What to project and where to put it [BORROWS].
     * @return         1 where both rank arrays were written, 0 where the call errored.
     *
     * @note WHAT THE CALLER DOES WITH THE RESULT. `corpus_ranks` and `needle_ranks` are byte fields
     *       numbered by one rule. They can go to anchor_steer_count or to any entry here that takes
     *       bytes. What the count means depends on how many classes the joint field holds, and
     *       `distinct` tells the caller which case applies.
     *
     * @note AT 256 CLASSES OR FEWER THE RANK COUNT IS THE EXACT COUNT. Places run from 0 to 255 and
     *       none is clamped. One rank names one class, rank agreement is class agreement, and a
     *       search over the rank fields returns the integer a search over the symbols would.
     *
     * @note PAST 256 CLASSES THE RANK COUNT IS AN UPPER BOUND. Every class at
     *       place 255 or later takes rank 255. Two different classes can agree on rank. A search
     *       over the rank fields counts those alignments too, and its full compare cannot remove them,
     *       because on rank fields the full compare compares ranks. The direction the filter needs
     *       still holds: one class takes one rank across the whole joint field. Symbol agreement
     *       implies rank agreement and no true occurrence is lost. For an exact count past 256 classes,
     *       check the rank survivors against the symbols through the oracle, or run the descent on the
     *       oracle directly.
     *
     * @note Errors, writing nothing, where `args` or any pointer but `distinct` is null, where either
     *       length is zero, where `needle_length` exceeds `corpus_length`, where the joint length
     *       `corpus_length + needle_length` would wrap `size_t`, where that joint length exceeds
     *       `UINT32_MAX` (class labels are stored as 32 bit positions and a wider field would alias two
     *       of them onto one label), or where `classes_length` does not reach the joint length. The
     *       return value is the whole report, as it is for anchor_field_project.
     *
     * @warning COSTS THE SAME CLOSURE THE SINGLE FIELD ENTRY DOES, over a longer field. The pairwise
     *          closure is quadratic in `corpus_length + needle_length`. This is for fields small
     *          enough to project at all. A descent takes the oracle directly, needs no closure, and
     *          costs nothing extra.
     */
    int anchor_field_pair_project(const AnchorFieldPairProjection *args);

#ifdef __cplusplus
}
#endif

#endif
