
// test_adversarial_joint.c: trichotomy and joint symbols
#include "test_adversarial_internal.h"

/**
 * @brief Runs every case and returns how many failed.
 *
 * @return 0 where every case passes, otherwise the count that failed.
 * @note Order matters only in that the differential net runs first. It is the cheapest case that
 *       can fail for the widest set of reasons, and a failure there makes the designed cases below
 *       it easier to read.
 */
/**
 * @brief Case 12. A descent stops, recurses, or refuses, and never revisits a state.
 *
 * @return Count of failures.
 *
 * THE TRICHOTOMY IS A CLAIM, AND THIS TEST ATTACKS IT. The guide states that a descent takes
 * one of exactly three branches: it stops when the destroy test fires, it recurses when a level
 * prunes, and it refuses to run at all when the question is malformed. The fourth branch it denies
 * is cycling, returning to a state already held.
 *
 * Each branch is checked separately and the refusal is checked hardest, because a refusal that
 * returns zero while having already written to the caller's buffer is indistinguishable from a
 * refusal that wrote nothing, unless somebody looks at the buffer. Every malformed call below is
 * made against a buffer filled with a sentinel, and the sentinel has to survive.
 *
 * No-revisiting is checked by requiring the placed offsets to be pairwise distinct. A descent that
 * placed the same offset twice would have returned to a state it already held, since placing a probe
 * that is already placed leaves the survivor set exactly as it was.
 */
int adversarial_case_trichotomy(void)
{
    printf("  a descent stops, recurses, or refuses, and never revisits\n");

    uint8_t *const corpus = (uint8_t *)malloc(ADVERSARIAL_CORPUS);
    uint8_t needle[16];
    int failed = 0;

    if (corpus == NULL)
    {
        printf("    allocation failed\n");
        return 1;
    }

    uint64_t state = 0xC0FFEEu;
    adversarial_fill_field(corpus, ADVERSARIAL_CORPUS, 6u, &state);
    memcpy(needle, corpus + 128u, sizeof(needle));

    const size_t alignments = (ADVERSARIAL_CORPUS - sizeof(needle)) + 1u;
    uint8_t *const survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("    allocation failed\n");
        free(corpus);
        return 1;
    }

    // REFUSES. Six malformed questions, each against a sentinel filled buffer. The contract is that
    // a refused call returns zero AND writes nothing, and only the second half needs looking for.
    const size_t sentinel = (size_t)0xABCDEF01u;
    struct
    {
        const char *what;
        AnchorSteerDescent args;
    } refusals[6];

    size_t offsets[ANCHOR_STEER_ANCHORS];

    refusals[0].what = "null offsets";
    refusals[0].args = (AnchorSteerDescent){.offsets = NULL,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments};
    refusals[1].what = "null corpus";
    refusals[1].args = (AnchorSteerDescent){.offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = NULL,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments};
    refusals[2].what = "count over the bound";
    refusals[2].args = (AnchorSteerDescent){.offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS + 1u,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments};
    refusals[3].what = "needle length zero";
    refusals[3].args = (AnchorSteerDescent){.offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = 0u,
                                            .survivors = survivors,
                                            .survivors_length = alignments};
    refusals[4].what = "needle longer than corpus";
    refusals[4].args = (AnchorSteerDescent){.offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = 8u,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments};
    refusals[5].what = "survivor buffer short by one";
    refusals[5].args = (AnchorSteerDescent){.offsets = offsets,
                                            .count = ANCHOR_STEER_ANCHORS,
                                            .corpus = corpus,
                                            .corpus_len = ADVERSARIAL_CORPUS,
                                            .needle = needle,
                                            .needle_len = sizeof(needle),
                                            .survivors = survivors,
                                            .survivors_length = alignments - 1u};

    for (size_t which = 0u; which < 6u; which += 1u)
    {
        for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
        {
            offsets[slot] = sentinel;
        }

        const size_t placed = anchor_steer_spawn_coarms(&refusals[which].args);
        if (placed != 0u)
        {
            printf("    %s ran and placed %zu: FAILS\n", refusals[which].what, placed);
            failed += 1;
        }
        for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
        {
            if (offsets[slot] != sentinel)
            {
                printf("    %s wrote to the caller's buffer: FAILS\n", refusals[which].what);
                failed += 1;
                break;
            }
        }
    }

    // A null argument pointer is the seventh refusal and cannot be expressed in the table above.
    if (anchor_steer_spawn_coarms(NULL) != 0u)
    {
        printf("    a null argument pointer ran: FAILS\n");
        failed += 1;
    }

    // RECURSES, and NEVER REVISITS. A well formed call places distinct offsets. Forcing full depth
    // takes the branch that ignores the destroy test, the recursing branch by construction.
    const size_t forced = ANCHOR_STEER_CALL(
        anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle, .needle_len = sizeof(needle),
        .survivors = survivors, .survivors_length = alignments, .sample_stride = 1u, .force_full_depth = 1);

    for (size_t slot = 0u; slot < forced; slot += 1u)
    {
        for (size_t seen = 0u; seen < slot; seen += 1u)
        {
            if (offsets[slot] == offsets[seen])
            {
                printf("    offset %zu placed twice, a state was revisited: FAILS\n", offsets[slot]);
                failed += 1;
            }
        }
        if (offsets[slot] >= sizeof(needle))
        {
            printf("    offset %zu lies outside the needle: FAILS\n", offsets[slot]);
            failed += 1;
        }
    }

    // STOPS. Honoring the destroy test can only place fewer, never more.
    const size_t stopped = ANCHOR_STEER_CALL(
        anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = offsets, .count = ANCHOR_STEER_ANCHORS,
        .corpus = corpus, .corpus_len = ADVERSARIAL_CORPUS, .needle = needle, .needle_len = sizeof(needle),
        .survivors = survivors, .survivors_length = alignments, .sample_stride = 1u);

    if (stopped > forced)
    {
        printf("    stopping placed more than forcing: FAILS\n");
        failed += 1;
    }
    if (forced > ANCHOR_STEER_ANCHORS)
    {
        printf("    forcing exceeded the compile time bound: FAILS\n");
        failed += 1;
    }

    printf("    refused 7 malformed questions, recursed to %zu distinct offsets, stopped at %zu,"
           " verdict %s\n",
           forced, stopped, (failed == 0) ? "ok" : "FAILS");

    free(survivors);
    free(corpus);
    return failed;
}

/**
 * @brief The symbol at one joint position, corpus first and needle after it.
 *
 * @param[in] joint    Both sides [BORROWS].
 * @param[in] position Joint position.
 * @return             The symbol held there.
 */
static uint32_t adversarial_joint_symbol(const AdversarialJointSymbols *joint, size_t position)
{
    if (position < joint->corpus_length)
    {
        return joint->corpus[position];
    }
    return joint->needle[position - joint->corpus_length];
}

/** @brief Equality between two joint positions, the oracle anchor_field_pair_project asks. */
static int adversarial_same_joint(const void *field, size_t left, size_t right)
{
    const AdversarialJointSymbols *const joint = (const AdversarialJointSymbols *)field;

    return (adversarial_joint_symbol(joint, left) == adversarial_joint_symbol(joint, right)) ? 1 : 0;
}

/** @brief Equality between two positions of one symbol array, for projecting one side alone. */
static int adversarial_same_symbol(const void *field, size_t left, size_t right)
{
    const uint32_t *const symbols = (const uint32_t *)field;

    return (symbols[left] == symbols[right]) ? 1 : 0;
}

/**
 * @brief Exact occurrences of a needle of 32 bit symbols, found by comparing the symbols directly.
 *
 * @param[in] corpus        Symbols searched [BORROWS].
 * @param[in] corpus_length How many.
 * @param[in] needle        Symbols searched for [BORROWS].
 * @param[in] needle_length How many. Non-zero.
 * @return                  Alignments where every symbol agrees.
 * @note The truth both projected routes answer to. It shares no code with the projection or with the
 *       byte engine, which makes agreement with it agreement between two independent routes.
 */
size_t adversarial_count_symbols(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle,
                                 size_t needle_length)
{
    size_t found = 0u;

    for (size_t at = 0u; (at + needle_length) <= corpus_length; at += 1u)
    {
        size_t offset = 0u;

        while ((offset < needle_length) && (corpus[at + offset] == needle[offset]))
        {
            offset += 1u;
        }
        if (offset == needle_length)
        {
            found += 1u;
        }
    }
    return found;
}

/**
 * @brief Counts through two separate projections, one per side. THE BROKEN CONSTRUCTION.
 *
 * @return 1 where both projections ran and `count` was written, 0 where either refused.
 * @note Kept in the suite as the negative control. A case that cannot show this route
 *       losing an occurrence cannot show the joint route recovering one.
 */
int adversarial_count_apart(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle, size_t needle_length,
                            uint8_t *corpus_ranks, uint8_t *needle_ranks, const AdversarialClassBuffers *buffers,
                            size_t *count)
{
    const AnchorFieldProjection corpus_side = {.same_in_field = adversarial_same_symbol,
                                               .field = corpus,
                                               .length = corpus_length,
                                               .ranks = corpus_ranks,
                                               .class_of_position = buffers->class_of_position,
                                               .members_in_class = buffers->members_in_class,
                                               .rarity_place_of_class = buffers->rarity_place_of_class,
                                               .classes_length = buffers->classes_length};
    const AnchorFieldProjection needle_side = {.same_in_field = adversarial_same_symbol,
                                               .field = needle,
                                               .length = needle_length,
                                               .ranks = needle_ranks,
                                               .class_of_position = buffers->class_of_position,
                                               .members_in_class = buffers->members_in_class,
                                               .rarity_place_of_class = buffers->rarity_place_of_class,
                                               .classes_length = buffers->classes_length};

    const int corpus_projected = anchor_field_project(&corpus_side);
    const int needle_projected = anchor_field_project(&needle_side);

    if ((corpus_projected == 0) || (needle_projected == 0))
    {
        return 0;
    }
    *count = anchor_steer_count(corpus_ranks, corpus_length, needle_ranks, needle_length, 1);
    return 1;
}

/**
 * @brief Counts through anchor_field_pair_project, which numbers both sides in one population.
 *
 * @return 1 where the projection ran and `count` and `distinct` were written, 0 where it refused.
 */
int adversarial_count_together(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle,
                               size_t needle_length, uint8_t *corpus_ranks, uint8_t *needle_ranks,
                               const AdversarialClassBuffers *buffers, size_t *count, size_t *distinct)
{
    const AdversarialJointSymbols joint = {.corpus = corpus, .corpus_length = corpus_length, .needle = needle};
    const AnchorFieldPairProjection both = {.same_in_field = adversarial_same_joint,
                                            .field = &joint,
                                            .corpus_length = corpus_length,
                                            .needle_length = needle_length,
                                            .corpus_ranks = corpus_ranks,
                                            .needle_ranks = needle_ranks,
                                            .class_of_position = buffers->class_of_position,
                                            .members_in_class = buffers->members_in_class,
                                            .rarity_place_of_class = buffers->rarity_place_of_class,
                                            .classes_length = buffers->classes_length,
                                            .distinct = distinct};

    const int projected = anchor_field_pair_project(&both);

    if (projected == 0)
    {
        return 0;
    }
    *count = anchor_steer_count(corpus_ranks, corpus_length, needle_ranks, needle_length, 1);
    return 1;
}
