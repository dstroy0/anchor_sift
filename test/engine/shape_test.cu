// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The scan's shape, faces and drift (cell_tracking/src/peaks/shape and cell_tracking/src/scan/drift). Every voxel of a
// drawn exact residual is taken as a point, in descending order. The device's six second differences are held against
// the exact integer library's at 1, 9, 10 and 12 limbs. The fields mix zeros, small and half-width values of both signs,
// and the most and least values each width holds. Each point's faces are held against the host's, and a difference
// whose axes meet a face is zero. The frame's positive set, packed on the device, is the host's bit for bit, with its
// count. The drift's weights are sigma squared, sigma being the voxel's size over the sizes' greatest common divisor;
// for voxel_pm 1625000, 406250, 406250 they are 16, 1, 1. The engine's drift on the device (shift_agreement_run) equals
// its host oracle (shift_agreement_host) in lag, agreement, padding and every count, frame after frame as the scan calls
// it, and both find a drawn set's known shift. Malformed requests refuse. The test is one job on the device's tessera
// daemon, submitted before its first device work.
#include "shape.h"
#include "drift.h"
#include "shift_agreement.h"
#include "exact_integer.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define SHAPE_TEST_SHAPES 5u

#define SHAPE_TEST_WIDTHS 4u

#define SHAPE_TEST_LIMBS_MOST 12u

#define SHAPE_TEST_KINDS 8ull

#define SHAPE_TEST_VOXELS_MOST (16u * 32u * 32u)

// the engine's drift pads each axis to a power of two at least twice its extent less one: 32 x 64 x 64 at the widest
#define SHAPE_TEST_PADDED_MOST (32u * 64u * 64u)

// the volumes the engine's drift holds on the device
#define SHAPE_TEST_DRIFT_VOLUMES 4ull

#define SHAPE_TEST_CHAINS 5u

#define SHAPE_TEST_FRAMES 4u

#define SHAPE_TEST_DENSITIES 8ull

// the most the test puts on the device at once: the residual, the points, their faces and differences, the drift's
// volumes, and the positive sets
#define SHAPE_TEST_DECLARED (((unsigned long long)SHAPE_TEST_VOXELS_MOST                                               \
                              * (SHAPE_TEST_LIMBS_MOST + 2ull + (SHAPE_ENTRIES * (SHAPE_TEST_LIMBS_MOST + 1ull)))       \
                              * sizeof(unsigned int))                                                                   \
                             + (SHAPE_TEST_DRIFT_VOLUMES * SHAPE_TEST_PADDED_MOST * sizeof(unsigned int))              \
                             + (4ull * DRIFT_WORDS(SHAPE_TEST_VOXELS_MOST) * sizeof(unsigned long long)))

static_assert(ANCHOR_EXACT_LIMBS > SHAPE_TEST_LIMBS_MOST,
              "shape_test: the exact integer must hold the widest difference, one limb past the widest residual");

static const unsigned int SHAPE_TEST_SHAPE[SHAPE_TEST_SHAPES][3] = {{6u, 10u, 12u}, {1u, 1u, 1u}, {3u, 1u, 7u},
                                                                    {2u, 5u, 3u}, {16u, 32u, 32u}};

static const unsigned int SHAPE_TEST_WIDTH[SHAPE_TEST_WIDTHS] = {1u, 9u, 10u, SHAPE_TEST_LIMBS_MOST};

static const unsigned int SHAPE_TEST_CHAIN[SHAPE_TEST_CHAINS][3] = {{8u, 16u, 16u}, {5u, 7u, 8u}, {1u, 1u, 1u},
                                                                    {3u, 1u, 7u}, {16u, 32u, 32u}};

static const unsigned long long SHAPE_TEST_DENSITY[SHAPE_TEST_FRAMES] = {3ull, 1ull, 5ull, 0ull};

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int limbs;
    unsigned int *residual;
    AnchorExactInteger *values;
} ShapeTestField;

static void shape_test_value(unsigned long long key, unsigned long long voxel, unsigned int limbs,
                             unsigned int *residual)
{
    const unsigned long long draw = sim_draw(key, voxel);
    // a remainder below the kinds' count fits unsigned int
    const unsigned int kind = (unsigned int)(draw % SHAPE_TEST_KINDS);
    // a remainder below 3, plus one, fits unsigned int
    const unsigned int small = 1u + (unsigned int)((draw >> 8u) % 3ull);
    const unsigned int middle = limbs / 2u;
    memset(residual, 0, limbs * sizeof(unsigned int));
    if (kind == 1u)
    {
        residual[0] = small;
    }
    else if (kind == 2u)
    {
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            residual[limb] = 0xFFFFFFFFu;
        }
        residual[0] = 0u - small;
    }
    else if (kind == 3u)
    {
        residual[middle] = small;
    }
    else if (kind == 4u)
    {
        residual[middle] = 1u;
        residual[0] = small;
    }
    else if (kind == 5u)
    {
        residual[0] = small;
        // the high half of the draw, shifted down, is below 2^32
        residual[limbs - 1u] = 0x80000000u | (unsigned int)(draw >> 32u);
    }
    else if (kind == 6u)
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            residual[limb] = 0xFFFFFFFFu;
        }
        residual[limbs - 1u] = 0x7FFFFFFFu;
    }
    else if (kind == 7u)
    {
        residual[limbs - 1u] = 0x80000000u;
    }
}

static void shape_test_exact(const unsigned int *words, unsigned int limbs, AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    const unsigned int negative = words[limbs - 1u] >> 31u;
    unsigned int carry = negative;
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int flipped = (negative != 0u) ? ~words[limb] : words[limb];
        const unsigned int sum = flipped + carry;
        carry = ((carry != 0u) && (sum == 0u)) ? 1u : 0u;
        value->limb[limb] = sum;
        any |= sum;
    }
    value->sign = (any == 0u) ? 0 : ((negative != 0u) ? -1 : 1);
}

static unsigned int shape_test_faces(const ShapeTestField *field, unsigned int voxel)
{
    const unsigned int plane = field->height * field->width;
    const unsigned int place[3] = {voxel / plane, (voxel % plane) / field->width, voxel % field->width};
    const unsigned int extent[3] = {field->depth, field->height, field->width};
    const unsigned int low[3] = {SHAPE_FACE_Z_LOW, SHAPE_FACE_Y_LOW, SHAPE_FACE_X_LOW};
    const unsigned int high[3] = {SHAPE_FACE_Z_HIGH, SHAPE_FACE_Y_HIGH, SHAPE_FACE_X_HIGH};
    unsigned int faces = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        faces |= (place[axis] == 0u) ? low[axis] : 0u;
        faces |= ((place[axis] + 1u) == extent[axis]) ? high[axis] : 0u;
    }
    return faces;
}

// the host's difference at a voxel, through the exact integer library; returns 1 where it is defined, 0 where a face
// makes it undefined, and -1 where the library could not hold it
static int shape_test_expected(const ShapeTestField *field, unsigned int voxel, unsigned int entry, unsigned int faces,
                               AnchorExactInteger *sum)
{
    const unsigned int axis_faces[3] = {SHAPE_FACE_Z_LOW | SHAPE_FACE_Z_HIGH, SHAPE_FACE_Y_LOW | SHAPE_FACE_Y_HIGH,
                                        SHAPE_FACE_X_LOW | SHAPE_FACE_X_HIGH};
    const unsigned int pairs[SHAPE_ENTRIES][2] = {{0u, 0u}, {1u, 1u}, {2u, 2u}, {0u, 1u}, {0u, 2u}, {1u, 2u}};
    const unsigned int first = pairs[entry][0];
    const unsigned int second = pairs[entry][1];
    anchor_exact_zero(sum);
    if (((faces & axis_faces[first]) != 0u) || ((faces & axis_faces[second]) != 0u))
    {
        return 0;
    }
    const unsigned int stride[3] = {field->height * field->width, field->width, 1u};
    const AnchorExactInteger *const values = field->values;
    int good = 1;
    if (first == second)
    {
        const unsigned int step = stride[first];
        good = (anchor_exact_add(&values[voxel + step], &values[voxel - step], sum) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(sum, &values[voxel], sum) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(sum, &values[voxel], sum) == ANCHOR_EXACT_OK);
    }
    else
    {
        const unsigned int one = stride[first];
        const unsigned int other = stride[second];
        good = (anchor_exact_subtract(&values[(voxel + one) + other], &values[(voxel + one) - other], sum)
                == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(sum, &values[(voxel - one) + other], sum) == ANCHOR_EXACT_OK)
            && (anchor_exact_add(sum, &values[(voxel - one) - other], sum) == ANCHOR_EXACT_OK);
    }
    return (good != 0) ? 1 : -1;
}

static int shape_test_hold(ShapeTestField *field, unsigned int depth, unsigned int height, unsigned int width,
                           unsigned int limbs)
{
    memset(field, 0, sizeof(*field));
    field->depth = depth;
    field->height = height;
    field->width = width;
    field->voxels = depth * height * width;
    field->limbs = limbs;
    field->residual = (unsigned int *)malloc(((size_t)field->voxels * limbs + 1u) * sizeof(unsigned int));
    field->values = (AnchorExactInteger *)malloc(((size_t)field->voxels + 1u) * sizeof(AnchorExactInteger));
    return (field->residual != NULL) && (field->values != NULL);
}

static void shape_test_release(ShapeTestField *field)
{
    free(field->residual);
    free(field->values);
    memset(field, 0, sizeof(*field));
}

static void shape_test_prove(SimTally *tally, ShapeTestField *field)
{
    const unsigned int limbs = field->limbs;
    const unsigned int wide = limbs + 1u;
    const unsigned int voxels = field->voxels;
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        shape_test_exact(&field->residual[(size_t)voxel * limbs], limbs, &field->values[voxel]);
    }
    const size_t bytes = (size_t)voxels * limbs * sizeof(unsigned int);
    const size_t words = (size_t)DRIFT_WORDS(voxels);
    unsigned int *device = NULL;
    int good = sim_took(tally, cudaMalloc((void **)&device, bytes), "the residual is held on the device")
            && sim_took(tally, cudaMemcpy(device, field->residual, bytes, cudaMemcpyHostToDevice),
                        "the residual reaches the device");
    unsigned int *const points = (unsigned int *)malloc(((size_t)voxels + 1u) * sizeof(unsigned int));
    unsigned int *const faces = (unsigned int *)malloc(((size_t)voxels + 1u) * sizeof(unsigned int));
    unsigned int *const differences = (unsigned int *)malloc((((size_t)voxels * SHAPE_ENTRIES * wide) + 1u)
                                                             * sizeof(unsigned int));
    unsigned long long *const packed = (unsigned long long *)malloc((words + 1u) * sizeof(unsigned long long));
    unsigned long long *const expected = (unsigned long long *)calloc(words + 1u, sizeof(unsigned long long));
    good = good && (points != NULL) && (faces != NULL) && (differences != NULL) && (packed != NULL)
        && (expected != NULL);
    sim_check(tally, good, "the points and their records are held on the host");
    for (unsigned int point = 0u; good && (point < voxels); point += 1u)
    {
        points[point] = voxels - 1u - point;
    }
    const ShapeRequest request = {device, field->depth, field->height, field->width, limbs, voxels, points, faces,
                                  differences};
    const long found = good ? shape_find(&request) : SHAPE_REFUSED;
    // a count that is not a refusal is not negative, so it re-signs to unsigned long long exactly
    const int counted = (found >= 0L) && ((unsigned long long)found == voxels);
    sim_check(tally, counted, "the shape answers for every point");
    int faces_agree = counted;
    int differences_agree = counted;
    unsigned long long defined = 0ull;
    unsigned long long faced = 0ull;
    for (unsigned int point = 0u; counted && (point < voxels); point += 1u)
    {
        const unsigned int voxel = points[point];
        const unsigned int cut = shape_test_faces(field, voxel);
        faces_agree = faces_agree && (faces[point] == cut);
        faced += (cut != 0u) ? 1ull : 0ull;
        for (unsigned int entry = 0u; entry < SHAPE_ENTRIES; entry += 1u)
        {
            const unsigned int *const held = &differences[(((size_t)point * SHAPE_ENTRIES) + entry) * wide];
            AnchorExactInteger want;
            AnchorExactInteger got;
            const int is_defined = shape_test_expected(field, voxel, entry, cut, &want);
            shape_test_exact(held, wide, &got);
            differences_agree = differences_agree && (is_defined >= 0)
                             && ((is_defined > 0) ? (anchor_exact_compare(&got, &want) == 0) : (got.sign == 0));
            defined += (is_defined > 0) ? 1ull : 0ull;
        }
    }
    sim_check(tally, faces_agree, "each point's faces are the host's");
    sim_check(tally, differences_agree,
              "each defined difference is the exact integer library's, and each undefined one is zero");
    unsigned long long positive_count = 0ull;
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const int positive = (field->values[voxel].sign > 0);
        expected[voxel / 64u] |= (positive != 0) ? (1ull << (voxel % 64u)) : 0ull;
        positive_count += (positive != 0) ? 1ull : 0ull;
    }
    const DriftPositiveRequest pack = {device, field->depth, field->height, field->width, limbs, packed};
    const long positives = good ? drift_positive(&pack) : DRIFT_REFUSED;
    // a count that is not a refusal is not negative, so it re-signs to unsigned long long exactly
    const int packed_alike = (positives >= 0L) && ((unsigned long long)positives == positive_count)
                          && (memcmp(packed, expected, words * sizeof(unsigned long long)) == 0);
    sim_check(tally, packed_alike, "the positive set packed on the device is the host's, with its count");
    scriptura_text(&tally->line, "  ");
    scriptura_decimal(&tally->line, limbs, 1u);
    scriptura_text(&tally->line, " limbs, ");
    scriptura_decimal(&tally->line, field->depth, 1u);
    scriptura_character(&tally->line, 'x');
    scriptura_decimal(&tally->line, field->height, 1u);
    scriptura_character(&tally->line, 'x');
    scriptura_decimal(&tally->line, field->width, 1u);
    scriptura_text(&tally->line, ": ");
    scriptura_decimal(&tally->line, defined, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, (unsigned long long)voxels * SHAPE_ENTRIES, 1u);
    scriptura_text(&tally->line, " differences defined, ");
    scriptura_decimal(&tally->line, faced, 1u);
    scriptura_text(&tally->line, " points on a face, ");
    scriptura_decimal(&tally->line, positive_count, 1u);
    scriptura_text(&tally->line, " positive voxels; ");
    scriptura_text(&tally->line, (counted && faces_agree && differences_agree && packed_alike) ? "all the host's\n"
                                                                                                  : "NOT the host's\n");
    sim_flush(tally);
    free(points);
    free(faces);
    free(differences);
    free(packed);
    free(expected);
    cudaFree(device);
}

static void shape_test_fields(SimTally *tally, unsigned int width_at)
{
    const unsigned int limbs = SHAPE_TEST_WIDTH[width_at];
    for (unsigned int shape = 0u; shape < SHAPE_TEST_SHAPES; shape += 1u)
    {
        ShapeTestField field;
        const int held = shape_test_hold(&field, SHAPE_TEST_SHAPE[shape][0], SHAPE_TEST_SHAPE[shape][1],
                                         SHAPE_TEST_SHAPE[shape][2], limbs);
        sim_check(tally, held, "the field is held on the host");
        const unsigned long long key = 0x5EA9Eull + ((unsigned long long)width_at * SHAPE_TEST_SHAPES) + shape;
        for (unsigned int voxel = 0u; held && (voxel < field.voxels); voxel += 1u)
        {
            shape_test_value(key, voxel, limbs, &field.residual[(size_t)voxel * limbs]);
        }
        if (held)
        {
            shape_test_prove(tally, &field);
        }
        shape_test_release(&field);
    }
}

static void shape_test_draw_set(unsigned long long key, unsigned int voxels, unsigned long long density,
                                unsigned long long *set)
{
    memset(set, 0, (size_t)DRIFT_WORDS(voxels) * sizeof(unsigned long long));
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        set[voxel / 64u] |= ((sim_draw(key, voxel) % SHAPE_TEST_DENSITIES) < density) ? (1ull << (voxel % 64u)) : 0ull;
    }
}

static size_t shape_test_padded_total(const unsigned int extents[3])
{
    size_t total = 1u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        size_t power = 1u;
        while (power < ((2u * (size_t)extents[axis]) - 1u))
        {
            power <<= 1u;
        }
        total *= power;
    }
    return total;
}

// the device's drift and the host's on one pair, compared whole; the device's lag is left in `lag`
static int shape_test_agree(const unsigned int extents[3], const unsigned int weights[3],
                            const unsigned long long *before, const unsigned long long *after, int lag[3])
{
    const size_t total = shape_test_padded_total(extents);
    unsigned int *const device_counts = (unsigned int *)malloc((total + 1u) * sizeof(unsigned int));
    unsigned int *const host_counts = (unsigned int *)malloc((total + 1u) * sizeof(unsigned int));
    ShiftAgreementRequest device;
    memset(&device, 0, sizeof(device));
    device.axes = 3u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        device.extents[axis] = extents[axis];
        device.weights[axis] = weights[axis];
    }
    device.before = before;
    device.after = after;
    device.counts = device_counts;
    ShiftAgreementRequest host = device;
    host.counts = host_counts;
    const int ran = (device_counts != NULL) && (host_counts != NULL) && (shift_agreement_run(&device) == 0L)
                 && (shift_agreement_host(&host) == 0L);
    const int agree = ran && (memcmp(device.lag, host.lag, sizeof(device.lag)) == 0)
                   && (device.agreement == host.agreement)
                   && (memcmp(device.padded, host.padded, sizeof(device.padded)) == 0)
                   && (memcmp(device_counts, host_counts, total * sizeof(unsigned int)) == 0);
    memcpy(lag, device.lag, 3u * sizeof(int));
    free(device_counts);
    free(host_counts);
    return agree;
}

static void shape_test_chains(SimTally *tally)
{
    const unsigned int weights[3] = {16u, 1u, 1u};
    const size_t words = (size_t)DRIFT_WORDS(SHAPE_TEST_VOXELS_MOST);
    unsigned long long *const frames = (unsigned long long *)malloc(((SHAPE_TEST_FRAMES * words) + 1u)
                                                                    * sizeof(unsigned long long));
    sim_check(tally, frames != NULL, "the drawn frames are held on the host");
    unsigned long long pairs = 0ull;
    unsigned long long agreed = 0ull;
    for (unsigned int chain = 0u; (frames != NULL) && (chain < SHAPE_TEST_CHAINS); chain += 1u)
    {
        const unsigned int *const extents = SHAPE_TEST_CHAIN[chain];
        const unsigned int voxels = extents[0] * extents[1] * extents[2];
        for (unsigned int frame = 0u; frame < SHAPE_TEST_FRAMES; frame += 1u)
        {
            shape_test_draw_set(0xD41F7ull + ((unsigned long long)chain * SHAPE_TEST_FRAMES) + frame, voxels,
                                SHAPE_TEST_DENSITY[frame], &frames[(size_t)frame * words]);
        }
        for (unsigned int frame = 1u; frame < SHAPE_TEST_FRAMES; frame += 1u)
        {
            int lag[3];
            const int agree = shape_test_agree(extents, weights, &frames[(size_t)(frame - 1u) * words],
                                               &frames[(size_t)frame * words], lag);
            pairs += 1ull;
            agreed += (agree != 0) ? 1ull : 0ull;
            sim_check(tally, agree, "the device's drift is the host's, frame after frame as the scan calls it");
        }
    }
    const unsigned int other_weights[3] = {9u, 4u, 25u};
    const unsigned int *const extents = SHAPE_TEST_CHAIN[0];
    int lag[3];
    const int weighed = (frames != NULL)
                     && shape_test_agree(extents, other_weights, &frames[0], &frames[words], lag);
    sim_check(tally, weighed, "the device's drift is the host's under weights 9, 4, 25");
    pairs += 1ull;
    agreed += (weighed != 0) ? 1ull : 0ull;
    scriptura_text(&tally->line, "  the drift on the device is the host's in lag, agreement, padding and every count on ");
    scriptura_decimal(&tally->line, agreed, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, pairs, 1u);
    scriptura_text(&tally->line, " frame pairs\n");
    sim_flush(tally);
    free(frames);
}

static void shape_test_known_shift(SimTally *tally)
{
    const unsigned int extents[3] = {8u, 16u, 16u};
    const int shift[3] = {1, -2, 3};
    const unsigned int weights[3] = {16u, 1u, 1u};
    const unsigned int voxels = extents[0] * extents[1] * extents[2];
    const size_t words = (size_t)DRIFT_WORDS(voxels);
    unsigned long long *const before = (unsigned long long *)malloc((words + 1u) * sizeof(unsigned long long));
    unsigned long long *const after = (unsigned long long *)calloc(words + 1u, sizeof(unsigned long long));
    int good = (before != NULL) && (after != NULL);
    sim_check(tally, good, "the shifted sets are held on the host");
    if (good)
    {
        shape_test_draw_set(0x5A1F7ull, voxels, 2ull, before);
    }
    const unsigned int plane = extents[1] * extents[2];
    for (unsigned int voxel = 0u; good && (voxel < voxels); voxel += 1u)
    {
        // each coordinate is below its extent, below 2^31, so each widens to long long exactly
        const long long place[3] = {(long long)(voxel / plane), (long long)((voxel % plane) / extents[2]),
                                    (long long)(voxel % extents[2])};
        const long long moved[3] = {place[0] + shift[0], place[1] + shift[1], place[2] + shift[2]};
        const int inside = (moved[0] >= 0ll) && (moved[0] < (long long)extents[0]) && (moved[1] >= 0ll)
                        && (moved[1] < (long long)extents[1]) && (moved[2] >= 0ll)
                        && (moved[2] < (long long)extents[2]);
        const int set = (before[voxel / 64u] >> (voxel % 64u)) & 1ull;
        // an inside place's index is below the voxels, so it narrows to unsigned int exactly
        const unsigned int to = inside ? (unsigned int)((((moved[0] * extents[1]) + moved[1]) * extents[2]) + moved[2])
                                       : 0u;
        after[to / 64u] |= (inside && set) ? (1ull << (to % 64u)) : 0ull;
    }
    int lag[3] = {0, 0, 0};
    const int agree = good && shape_test_agree(extents, weights, before, after, lag);
    sim_check(tally, agree, "the device's drift is the host's on a shifted set");
    const int found = agree && (lag[0] == shift[0]) && (lag[1] == shift[1]) && (lag[2] == shift[2]);
    sim_check(tally, found, "the drift carries a set onto its copy shifted by 1, -2, 3 with the lag 1, -2, 3");
    scriptura_text(&tally->line, "  a set shifted by 1, -2, 3 is found at the lag ");
    scriptura_signed(&tally->line, lag[0]);
    scriptura_text(&tally->line, ", ");
    scriptura_signed(&tally->line, lag[1]);
    scriptura_text(&tally->line, ", ");
    scriptura_signed(&tally->line, lag[2]);
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
    free(before);
    free(after);
}

// the engine's drift keeps its last transform and reuses it when the next pair's first set is the last pair's second;
// here the extents change while the padding and the word count stay the same
static void shape_test_kept(SimTally *tally)
{
    const unsigned int first[3] = {5u, 7u, 8u};
    const unsigned int second[3] = {6u, 6u, 8u};
    const unsigned int weights[3] = {16u, 1u, 1u};
    const unsigned int voxels = second[0] * second[1] * second[2];
    const size_t words = (size_t)DRIFT_WORDS(voxels);
    unsigned long long *const sets = (unsigned long long *)malloc(((3u * words) + 1u) * sizeof(unsigned long long));
    const int good = (sets != NULL) && (DRIFT_WORDS(first[0] * first[1] * first[2]) == words);
    sim_check(tally, good, "the kept sets are held on the host, with one word count for both extents");
    if (good)
    {
        shape_test_draw_set(0x6E97ull, first[0] * first[1] * first[2], 3ull, &sets[0]);
        shape_test_draw_set(0x6E98ull, first[0] * first[1] * first[2], 3ull, &sets[words]);
        shape_test_draw_set(0x6E99ull, voxels, 3ull, &sets[2u * words]);
    }
    int lag[3];
    const int earlier = good && shape_test_agree(first, weights, &sets[0], &sets[words], lag);
    const int later = good && shape_test_agree(second, weights, &sets[words], &sets[2u * words], lag);
    sim_check(tally, earlier, "the device's drift is the host's on 5x7x8");
    sim_check(tally, later,
              "the device's drift is the host's on 6x6x8 right after 5x7x8, the first set the last pair's second");
    scriptura_text(&tally->line, "  extents 5x7x8 then 6x6x8, one padding and one word count: the device is ");
    scriptura_text(&tally->line, (earlier != 0) ? "the host's" : "NOT the host's");
    scriptura_text(&tally->line, ", then ");
    scriptura_text(&tally->line, (later != 0) ? "the host's\n" : "NOT the host's\n");
    sim_flush(tally);
    free(sets);
}

static void shape_test_weights(SimTally *tally)
{
    const unsigned long long measured[3] = {1625000ull, 406250ull, 406250ull};
    const unsigned long long coprime[3] = {6ull, 4ull, 10ull};
    const unsigned long long widest[3] = {65535ull, 1ull, 1ull};
    const unsigned long long past[3] = {65536ull, 1ull, 1ull};
    const unsigned long long empty[3] = {1ull, 0ull, 1ull};
    unsigned int weights[3] = {0u, 0u, 0u};
    const int held = drift_weights(measured, weights);
    sim_check(tally, held && (weights[0] == 16u) && (weights[1] == 1u) && (weights[2] == 1u),
              "voxel_pm 1625000, 406250, 406250 gives the weights 16, 1, 1");
    scriptura_text(&tally->line, "  the drift's weights for voxel_pm 1625000, 406250, 406250: ");
    scriptura_decimal(&tally->line, weights[0], 1u);
    scriptura_text(&tally->line, ", ");
    scriptura_decimal(&tally->line, weights[1], 1u);
    scriptura_text(&tally->line, ", ");
    scriptura_decimal(&tally->line, weights[2], 1u);
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
    sim_check(tally, drift_weights(coprime, weights) && (weights[0] == 9u) && (weights[1] == 4u)
                         && (weights[2] == 25u),
              "voxel_pm 6, 4, 10 gives the weights 9, 4, 25");
    sim_check(tally, drift_weights(widest, weights) && (weights[0] == 4294836225u) && (weights[1] == 1u)
                         && (weights[2] == 1u),
              "a sigma of 65535 squares to 4294836225 and is kept");
    sim_check(tally, drift_weights(past, weights) == 0, "a sigma of 65536 squares past 32 bits and refuses");
    sim_check(tally, drift_weights(empty, weights) == 0, "a size of zero refuses");
}

static void shape_test_refusals(SimTally *tally)
{
    unsigned int *device = NULL;
    const int held = sim_took(tally, cudaMalloc((void **)&device, SHAPE_TEST_LIMBS_MOST * sizeof(unsigned int)),
                              "one voxel is held on the device");
    unsigned int inside = 0u;
    unsigned int outside = 1u;
    unsigned int faces = 0u;
    unsigned int differences[SHAPE_ENTRIES * 2u];
    unsigned long long positive[1] = {0ull};
    const ShapeRequest none = {NULL, 1u, 1u, 1u, 1u, 1u, &inside, &faces, differences};
    const ShapeRequest flat = {device, 0u, 1u, 1u, 1u, 1u, &inside, &faces, differences};
    const ShapeRequest narrow = {device, 1u, 1u, 1u, 0u, 1u, &inside, &faces, differences};
    const ShapeRequest unplaced = {device, 1u, 1u, 1u, 1u, 1u, &inside, NULL, differences};
    const ShapeRequest beyond = {device, 1u, 1u, 1u, 1u, 1u, &outside, &faces, differences};
    const ShapeRequest crowded = {device, 1u, 1u, 1u, 1u, 2u, &inside, &faces, differences};
    const ShapeRequest empty = {device, 1u, 1u, 1u, 1u, 0u, NULL, NULL, NULL};
    sim_check(tally, shape_find(NULL) == SHAPE_REFUSED, "the shape: no request refuses");
    sim_check(tally, shape_find(&none) == SHAPE_REFUSED, "the shape: no residual refuses");
    sim_check(tally, held && (shape_find(&flat) == SHAPE_REFUSED), "the shape: an empty extent refuses");
    sim_check(tally, held && (shape_find(&narrow) == SHAPE_REFUSED), "the shape: a width of no limbs refuses");
    sim_check(tally, held && (shape_find(&unplaced) == SHAPE_REFUSED), "the shape: nowhere to write refuses");
    sim_check(tally, held && (shape_find(&beyond) == SHAPE_REFUSED), "the shape: a point outside the frame refuses");
    sim_check(tally, held && (shape_find(&crowded) == SHAPE_REFUSED),
              "the shape: more points than the frame has voxels refuses");
    sim_check(tally, held && (shape_find(&empty) == 0L), "the shape: no points gives none and writes nothing");
    const DriftPositiveRequest unset = {NULL, 1u, 1u, 1u, 1u, positive};
    const DriftPositiveRequest nowhere = {device, 1u, 1u, 1u, 1u, NULL};
    const DriftPositiveRequest thin = {device, 1u, 1u, 1u, 0u, positive};
    sim_check(tally, drift_positive(NULL) == DRIFT_REFUSED, "the positive set: no request refuses");
    sim_check(tally, drift_positive(&unset) == DRIFT_REFUSED, "the positive set: no residual refuses");
    sim_check(tally, held && (drift_positive(&nowhere) == DRIFT_REFUSED), "the positive set: nowhere to write refuses");
    sim_check(tally, held && (drift_positive(&thin) == DRIFT_REFUSED), "the positive set: a width of no limbs refuses");
    cudaFree(device);
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    const int admitted = sim_job_submit(&tally, "shape_test", count, arguments, SHAPE_TEST_DECLARED);
    for (unsigned int width_at = 0u; (admitted != 0) && (width_at < SHAPE_TEST_WIDTHS); width_at += 1u)
    {
        shape_test_fields(&tally, width_at);
    }
    if (admitted != 0)
    {
        shape_test_weights(&tally);
        shape_test_chains(&tally);
        shape_test_known_shift(&tally);
        shape_test_kept(&tally);
        shape_test_refusals(&tally);
    }
    return sim_close(&tally, "shape test");
}
