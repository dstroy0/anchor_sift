
// test_steer_grading.c: counting with probes and grading a field
#include "test_steer_internal.h"

/**
 * @brief Counts occurrences by evaluating a probe list in order, verifying every survivor.
 *
 * @param[out] reads         Corpus bytes the probes read.
 * @param[out] verifications Survivors handed to the exact compare, each of which reads at least one
 *                           corpus byte. Counted separately because the read floor below is a bound
 *                           on TOTAL reads, and a probe set of size zero reads nothing through the
 *                           probes while still deciding every alignment through the compare.
 */
static size_t count_with_probes(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                const AnchorProbe *probes, size_t probe_count, uint64_t *reads, uint64_t *verifications)
{
    size_t found = 0u;
    uint64_t taken = 0u;
    uint64_t verified = 0u;

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < probe_count)
        {
            int agrees = 1;
            for (size_t step = 0u; step < probes[slot].length; step += 1u)
            {
                const size_t offset = probes[slot].origin + (step * probes[slot].step);
                taken += 1u;
                if (corpus[at + offset] != needle[offset])
                {
                    agrees = 0;
                    break;
                }
            }
            if (agrees == 0)
            {
                break;
            }
            slot += 1u;
        }
        if (slot == probe_count)
        {
            verified += 1u;
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    *reads = taken;
    *verifications = verified;
    return found;
}

/** @brief Reads a file whole. Returns 0 and leaves `length` at zero where it cannot. */
uint8_t *read_whole_file(const char *path, size_t *length)
{
    *length = 0u;
    FILE *handle = fopen(path, "rb");
    if (handle == NULL)
    {
        return NULL;
    }
    if (fseek(handle, 0, SEEK_END) != 0)
    {
        fclose(handle);
        return NULL;
    }
    const long span = ftell(handle);
    if (span <= 0)
    {
        fclose(handle);
        return NULL;
    }
    rewind(handle);

    uint8_t *bytes = (uint8_t *)malloc((size_t)span);
    if (bytes == NULL)
    {
        fclose(handle);
        return NULL;
    }
    const size_t elapsed = fread(bytes, 1u, (size_t)span, handle);
    fclose(handle);
    if (elapsed == 0u)
    {
        free(bytes);
        return NULL;
    }
    *length = elapsed;
    return bytes;
}

/**
 * @brief Grades recursion, coarms, eyes and destruction on one field.
 *
 * @param[in] label      What to print this field as.
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @return               Count of failures.
 *
 * EVERY ROUTE MUST RETURN THE REFERENCE COUNT. Placement and order and shape are all nulls: an
 * alignment survives only when every probe agrees, a conjunction is order independent, and the
 * survivor is verified by a full compare whatever probed it. So the count is the invariant and the
 * reads are the measurement. Anything that moves the count is a defect, and it is graded at exactly
 * zero difference and not against a tolerance.
 */
int grade_field(const char *label, const uint8_t *corpus, size_t corpus_len)
{
    int failed = 0;
    const size_t needle_len = 24u;
    if (corpus_len < (needle_len * 4u))
    {
        printf("  %s: too short to grade\n", label);
        return 1;
    }

    uint8_t needle[24];
    memcpy(needle, corpus + (corpus_len / 3u), sizeof(needle));

    const size_t alignments = (corpus_len - needle_len) + 1u;
    uint8_t *survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  %s: allocation failed\n", label);
        return 1;
    }

    const size_t want = anchor_sift_naive(corpus, corpus_len, needle, needle_len);

    /* READS PER ALIGNMENT IS THE MEASURE, AND ITS FLOOR IS EXACTLY ONE. Every alignment has to be
     * looked at at least once to be rejected. No probe arrangement can read fewer than one byte
     * per alignment. Printing the raw reads alone hides how close a route is to that floor; the
     * normalized figure says whether there is anything left to win. Carried in thousandths by exact
     * integer division, with the numerator and denominator both printed beside it. */
    printf("\n  FIELD %s, %zu bytes, %zu alignments, reference count %zu\n\n", label, corpus_len, alignments, want);
    printf("  %26s %8s %10s %14s %12s %10s\n", "route", "probes", "count", "reads", "per align", "verdict");

    /* Spatial placement, unsteered, as the engine did before any of this. */
    AnchorProbe spatial[ANCHOR_STEER_ANCHORS];
    const size_t cell = needle_len / ANCHOR_STEER_ANCHORS;
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        spatial[slot].origin = (slot * cell) + ((cell > 1u) ? ((slot * 7u) % cell) : 0u);
        spatial[slot].step = 1u;
        spatial[slot].length = 1u;
    }
    uint64_t spatial_reads = 0u;
    uint64_t spatial_verifications = 0u;
    const size_t spatial_count = count_with_probes(corpus, corpus_len, needle, needle_len, spatial,
                                                   ANCHOR_STEER_ANCHORS, &spatial_reads, &spatial_verifications);
    print_route_row("spatial, unsteered", ANCHOR_STEER_ANCHORS, spatial_count, spatial_reads, alignments,
                    spatial_count == want);
    failed += (spatial_count == want) ? 0 : 1;

    /* Recursive reorder of those same placements. */
    size_t reordered[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < ANCHOR_STEER_ANCHORS; slot += 1u)
    {
        reordered[slot] = spatial[slot].origin;
    }
    const size_t depth = ANCHOR_STEER_CALL(anchor_steer_plan_recursive, AnchorSteerDescent, .offsets = reordered,
                                           .count = ANCHOR_STEER_ANCHORS, .corpus = corpus, .corpus_len = corpus_len,
                                           .needle = needle, .needle_len = needle_len, .survivors = survivors,
                                           .survivors_length = alignments, .sample_stride = 1u);
    AnchorProbe recursive[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < depth; slot += 1u)
    {
        recursive[slot].origin = reordered[slot];
        recursive[slot].step = 1u;
        recursive[slot].length = 1u;
    }
    uint64_t recursive_reads = 0u;
    uint64_t recursive_verifications = 0u;
    const size_t recursive_count = count_with_probes(corpus, corpus_len, needle, needle_len, recursive, depth,
                                                     &recursive_reads, &recursive_verifications);
    print_route_row("recursive reorder", depth, recursive_count, recursive_reads, alignments, recursive_count == want);
    failed += (recursive_count == want) ? 0 : 1;

    /* Coarms spawned wherever the field says, and not where a spread rule put them. */
    size_t spawned[ANCHOR_STEER_ANCHORS];
    const size_t coarms = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = spawned,
                                            .count = ANCHOR_STEER_ANCHORS, .corpus = corpus, .corpus_len = corpus_len,
                                            .needle = needle, .needle_len = needle_len, .survivors = survivors,
                                            .survivors_length = alignments, .sample_stride = 1u);
    AnchorProbe coarm_probes[ANCHOR_STEER_ANCHORS];
    for (size_t slot = 0u; slot < coarms; slot += 1u)
    {
        coarm_probes[slot].origin = spawned[slot];
        coarm_probes[slot].step = 1u;
        coarm_probes[slot].length = 1u;
    }
    uint64_t coarm_reads = 0u;
    uint64_t coarm_verifications = 0u;
    const size_t coarm_count = count_with_probes(corpus, corpus_len, needle, needle_len, coarm_probes, coarms,
                                                 &coarm_reads, &coarm_verifications);
    print_route_row("coarms spawned", coarms, coarm_count, coarm_reads, alignments, coarm_count == want);
    failed += (coarm_count == want) ? 0 : 1;

    /* Eyes allowed. A line probe reads more per alignment and has to prune harder to earn it. */
    AnchorProbe swept[ANCHOR_STEER_ANCHORS];
    const size_t eyes = ANCHOR_STEER_CALL(anchor_steer_sweep_probes, AnchorSteerSweep, .probes = swept,
                                          .count = ANCHOR_STEER_ANCHORS, .corpus = corpus, .corpus_len = corpus_len,
                                          .needle = needle, .needle_len = needle_len, .max_length = 3u,
                                          .survivors = survivors, .survivors_length = alignments, .sample_stride = 1u);
    uint64_t eye_reads = 0u;
    uint64_t eye_verifications = 0u;
    const size_t eye_count =
        count_with_probes(corpus, corpus_len, needle, needle_len, swept, eyes, &eye_reads, &eye_verifications);
    print_route_row("eyes and arms swept", eyes, eye_count, eye_reads, alignments, eye_count == want);
    failed += (eye_count == want) ? 0 : 1;

    printf("    shapes spawned:");
    for (size_t slot = 0u; slot < eyes; slot += 1u)
    {
        printf(" %s(origin %zu, step %zu, length %zu)", (swept[slot].length == 1u) ? "arm" : "eye", swept[slot].origin,
               swept[slot].step, swept[slot].length);
    }
    printf("\n");

    /* THE DEPTH IS A COMPILE TIME FACT AND THIS ASSERTS IT. */
    if ((depth > ANCHOR_STEER_ANCHORS) || (coarms > ANCHOR_STEER_ANCHORS) || (eyes > ANCHOR_STEER_ANCHORS))
    {
        printf("    a descent exceeded its compile time bound: FAILS\n");
        failed += 1;
    }

    // THE READ FLOOR, ASSERTED ON EVERY ROUTE AND ON THE EMPTY PROBE SET BESIDE THEM.
    //
    // The theorem: an engine that decides each alignment from reads taken AT that alignment performs
    // at least one read per alignment. An alignment decided on zero reads is decided by a function
    // whose domain is the empty tuple. Its range holds one value and it answers identically at
    // every alignment. An adversary edits the corpus there and flips whether that alignment matches,
    // the engine observes nothing different, and one of the two answers is wrong. So total reads,
    // probe reads plus the compares that follow them, is at least the alignment count, always.
    //
    // The empty probe set is the sharp case and it is graded here as a route and not described.
    // It takes zero probe reads and sends every alignment to the compare. Its total equals
    // the alignment count. The floor is ATTAINED by the configuration that steers least, and
    // that shows the floor is a property of the problem and not an artifact of the steering.
    uint64_t bare_reads = 0u;
    uint64_t bare_verifications = 0u;
    const size_t bare_count =
        count_with_probes(corpus, corpus_len, needle, needle_len, NULL, 0u, &bare_reads, &bare_verifications);
    failed += (bare_count == want) ? 0 : 1;

    // REPORTED OUTSIDE THE TABLE, BECAUSE IT IS NOT IN THE TABLE'S UNITS. Every row above counts
    // PROBE reads. The floor is a statement about TOTAL reads, probe reads plus the compares that
    // follow, and mixing the two down one column would invite a reader to compare a bound against a
    // cost. The empty probe set takes zero probe reads and one compare per alignment. In floor
    // units it sits exactly on the floor. In real bytes it is the most expensive route there is,
    // since every alignment takes a full compare of up to needle_len bytes.
    printf("    read floor: %zu alignments, empty probe set takes %llu probe reads and %llu"
           " compares\n",
           alignments, (unsigned long long)bare_reads, (unsigned long long)bare_verifications);

    if ((bare_reads != 0u) || (bare_verifications != (uint64_t)alignments))
    {
        printf("    the empty probe set did not read exactly once per alignment: FAILS\n");
        failed += 1;
    }

    const uint64_t floor_total[5] = {spatial_reads + spatial_verifications, recursive_reads + recursive_verifications,
                                     coarm_reads + coarm_verifications, eye_reads + eye_verifications,
                                     bare_reads + bare_verifications};
    for (size_t route = 0u; route < 5u; route += 1u)
    {
        if (floor_total[route] < (uint64_t)alignments)
        {
            printf("    route %zu broke the read floor, %llu reads over %zu alignments: FAILS\n", route,
                   (unsigned long long)floor_total[route], alignments);
            failed += 1;
        }
    }

    free(survivors);
    return failed;
}

/**
 * @brief Asserts that the arm this machine carries was actually taken, not merely compiled.
 *
 * @return Count of failures.
 *
 * THIS IS NOT A CORRECTNESS CHECK AND IT CANNOT BE ONE. An arm that is compiled, graded and never
 * called produces no wrong answer. Every count stays identical, every differential passes, and the
 * suite reports green while the engine runs the scalar path it always ran. That happened here: the
 * AVX2 arm was built, graded against portable and benched at thirty-three times its rate while
 * anchor_steer.c went on calling its own loop, and nothing in the suite could say so, because
 * identical counts are exactly what an unused implementation produces.
 *
 * The claim asserted here is about the WIRING. Run the planner, then require that the scan counter
 * says the widest arm reporting itself present ran. A machine with no wide arm passes
 * on the portable count alone, which is correct and not a waiver: there is nothing to have
 * failed to wire.
 */
int check_arm_is_wired(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len)
{
    int failed = 0;
    const size_t alignments = (corpus_len - needle_len) + 1u;
    uint8_t *survivors = (uint8_t *)malloc(alignments);
    if (survivors == NULL)
    {
        printf("  allocation failed in the wiring check\n");
        return 1;
    }

    const AnchorSteerEngine *best = anchor_steer_best_engine();
    const int wide_present = (strcmp(best->name, "portable") != 0) ? 1 : 0;

    printf("\n  THE ARM IS WIRED, not merely compiled.\n\n");

    anchor_steer_scan_counters_reset();
    size_t spawned[ANCHOR_STEER_ANCHORS];
    (void)ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = spawned,
                            .count = ANCHOR_STEER_ANCHORS, .corpus = corpus, .corpus_len = corpus_len, .needle = needle,
                            .needle_len = needle_len, .survivors = survivors, .survivors_length = alignments,
                            .sample_stride = 1u);

    printf("  %18s %14s %14s %10s %10s\n", "widest arm", "scans", "wide scans", "share", "verdict");

    /* A COUNT SAYS THE ARM RAN. A SHARE SAYS IT RAN ON THE WORK IT WAS GIVEN. The distinction
     * matters because they fail differently: a count above zero is satisfied by a single dispatch,
     * and a change that accidentally routed almost every sweep to the scalar fall-through would keep
     * the count non-zero and be entirely wrong. This whole planner run is at stride one, the
     * only stride an arm serves. Every scan in it should reach the wide arm and the share
     * should be the full hundred. */
    const uint64_t share =
        (anchor_steer_scan_calls > 0u) ? ((anchor_steer_wide_calls * 100u) / anchor_steer_scan_calls) : 0u;

    const int ok = (anchor_steer_scan_calls > 0u) && ((wide_present == 0) || (share == 100u));
    printf("  %18s %14llu %14llu %9llu%% %10s\n", best->name, (unsigned long long)anchor_steer_scan_calls,
           (unsigned long long)anchor_steer_wide_calls, (unsigned long long)share, ok ? "ok" : "FAILS");

    if (anchor_steer_scan_calls == 0u)
    {
        printf("    the planner served no scan through an arm at all\n");
        failed += 1;
    }
    else if ((wide_present != 0) && (anchor_steer_wide_calls == 0u))
    {
        printf("    %s reports present and the planner never called it\n", best->name);
        failed += 1;
    }
    else if ((wide_present != 0) && (share != 100u))
    {
        printf("    %s ran on %llu%% of the scans at stride one. The rest fell through\n", best->name,
               (unsigned long long)share);
        failed += 1;
    }
    else if (wide_present == 0)
    {
        printf("    no wide arm on this machine. The portable count is the whole claim\n");
    }

    free(survivors);
    return failed;
}

/** @brief Equality oracle over bytes. The engine never learns that these are bytes. */
int byte_same_at(const void *field, size_t corpus_at, size_t needle_at)
{
    const ByteField *const byte_field = (const ByteField *)field;

    return (byte_field->corpus[corpus_at] == byte_field->needle[needle_at]) ? 1 : 0;
}

/** @brief Equality oracle over 32 bit samples, corpus position against needle position. */
int sample_same_at(const void *field, size_t corpus_at, size_t needle_at)
{
    const SampleField *const sample_field = (const SampleField *)field;

    return (sample_field->corpus[corpus_at] == sample_field->needle[needle_at]) ? 1 : 0;
}

/**
 * @brief Equality between two positions OF THE FIELD, which is a different oracle.
 *
 * @note Separate from sample_same_at because the two index different spaces. A descent's oracle
 *       takes a corpus position and a needle position; grouping a field into classes takes two
 *       field positions. Handing the first to anchor_field_project indexes the needle with a field
 *       position and reads past its end. That is how this was found.
 */
int sample_same_in_field(const void *field, size_t left, size_t right)
{
    const uint32_t *const samples = (const uint32_t *)field;

    return (samples[left] == samples[right]) ? 1 : 0;
}

/** @brief Tolerance of the non-transitive predicate below, in raw units. */
#define STEER_TOLERANCE 2u

/**
 * @brief Within a tolerance, which is meaningful and is NOT transitive.
 *
 * @note This is the protein case in miniature. A value within 2 of another and that one within 2 of
 *       a third does not put the first within 2 of the third. The relation does not partition the
 *       field and a grouping that stopped at the first matching representative would put agreeing
 *       positions in different classes.
 */
int near_same_in_field(const void *field, size_t left, size_t right)
{
    const uint32_t *const values = (const uint32_t *)field;
    const uint32_t a = values[left];
    const uint32_t b = values[right];
    const uint32_t gap = (a > b) ? (a - b) : (b - a);

    return (gap <= STEER_TOLERANCE) ? 1 : 0;
}
