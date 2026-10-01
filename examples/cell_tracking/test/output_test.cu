// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// S11, the output (cell_tracking/src/output/output_graph), every point kept. A synthetic set written as .points and
// .links runs through output_graph_set: a chain of four frames in a 4 x 5 x 6 view whose points carry two limbs of
// levels, with a link at a cost past 32 bits, a gate pair left unchosen, an end whose prediction lies outside the view,
// a start, an empty frame and two starts after it; a sample of no frames; and a second sample of two frames whose links
// cross. Its node ids count from 1 again while the submission's row ids run on. Every row of the nodes and of the
// submission, and every line of the counts, is checked against text worked by hand. Then S7's divisions (src/divide): a
// .divide beside the chain, where A divides taking D, which started, and one beside second, where P divides taking R
// from Q, which ends; every row and count is checked against the hand's again, daughter two's state split. A .divide of
// no divisions beside each sample writes the undivided set's nodes and submission byte for byte. Then S9's faces
// (src/faces): a .faces beside each sample, written by hand, where the chain's B ends with its prediction past a face
// and left, D starts carried back past one and entered and ends predicted past another and left, E starts at the last
// frame carried back past one and entered, and A, carried back past one, has its link in and is no start; every state
// and count is checked against the hand's, and the submission is the undivided set's byte for byte. With chain's
// .divide and second's beside them too, D is daughter two, split and left and no start. Then each of thirteen broken
// samples runs after the good chain, and the set errors with nothing written past the headers: .links frames or a view
// that disagree with the .points, a pair whose sources are not the frame's points, a chosen link past the points, two
// links into one point and two out of one, a pair whose chosen count is not its gate's, a .links or a .points with a
// word past its last frame, a .links that stops a pair short, a voxel outside the view, a sample with no .links, and
// a name with a comma. Malformed requests error. A copy of second with its .divide as worked writes after the good
// chain, and each of fourteen broken .divide files in its place errors on the same way: a head cut short, frames or a
// view not the .points', a CRC-64 not its .links', a count past the frame's points, a parent past them, parents out
// of order, daughter one not the parent's link, daughter two daughter one or past the points, daughter two not from
// the point named, a division taking from a point that divides (on a fork), a division cut short, and a word past the
// last pair. A copy of the chain with its .faces as worked writes after the good chain, and each of fifteen broken
// .faces files in its place errors on the same way: a head cut short, frames or a view not the .points', a CRC-64 not
// its .links', a frame's count not its points', a flag no .faces sets, back-prediction faces not its place's,
// prediction faces on a point the .links does not flag outside, a first-frame flag off frame 0, a last frame's point
// without its flag, a carried flag on a point with no link out, an entering or a leaving verdict dropped, a point cut
// short, and a word past the last frame. Then the faults: through the seam output_graph.cu holds for the test alone
// (OUTPUT_TEST_FAULTS), H4 fed one end too many on each frame pair, which the one-to-one links cannot make happen, on
// the set as worked and divided; second's .divide taken away between the two passes and put beside it there;
// second's .faces rewritten between the passes with R carried back past a face, every count the same, and taken away
// there; and "second" rewritten between the passes, once with a link fewer and once with its links crossed the other
// way, every count the same; each errors with nothing of second's written. And, with no seam, a nodes file and a
// submission opened for reading, which no row can be written to: the set errors, and output_close, which the driver
// closes both with, fails on the file. What the C library returns on such a file is printed. The test is host work
// and touches no device. It is no job.
//
// The test links no engine_*.cu. Engine_sample_path below restates engine/engine_*.cu's, and output_graph.cu's paths
// are built by the restatement here: a change to either format must be made in both. The CRC-64 the .divide and the
// .faces carry is taken a bit at a time here, apart from engine/codecs/crc/crc.h's table, which output_graph.cu takes
// it by.
#ifndef OUTPUT_TEST_FAULTS
#error "output_test is built with OUTPUT_TEST_FAULTS (test/output_test.sh): its faults are the seam's"
#endif

#include "divide.h"
#include "faces.h"
#include "output.h"
#include "scan.h"
#include "sort.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define OUTPUT_TEST_MKDIR(path_) _mkdir(path_)
#else
#include <sys/stat.h>
#define OUTPUT_TEST_MKDIR(path_) mkdir((path_), 0755)
#endif

#define OUTPUT_TEST_WORDS 1024u

#define OUTPUT_TEST_TEXT 65536u

// the lines the test writes where open_output writes the headers; nothing may follow them when a set errors
#define OUTPUT_TEST_NODES_HEADER "the nodes header, which open_output writes\n"

// the test links no engine_*.cu: the engine's sample path, restated as engine/engine_files.cu's engine_sample_path
// writes it. A change to that format must be made here too
extern "C" int engine_sample_path(char *out, size_t capacity, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(out, capacity, "%s/%s/%s%s", set, sample, sample, suffix);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

typedef struct
{
    unsigned int checks;
    unsigned int failures;
} OutputTestResults;

static void output_test_check(OutputTestResults *results, int passed, const char *what)
{
    results->checks += 1u;
    if (passed == 0)
    {
        results->failures += 1u;
        printf("  FAILED: %s\n", what);
    }
}

typedef struct
{
    unsigned int words[OUTPUT_TEST_WORDS];
    unsigned int count;
} OutputTestWords;

static void output_test_put(OutputTestWords *words, unsigned int word)
{
    if (words->count < OUTPUT_TEST_WORDS)
    {
        words->words[words->count] = word;
    }
    words->count += 1u;
}

static int output_test_path(char *path, size_t capacity, const char *set, const char *name)
{
    const int written = snprintf(path, capacity, "%s/%s", set, name);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

static int output_test_directory(const char *set, const char *sample)
{
    char path[ENGINE_PATH_CAPACITY];
    (void)OUTPUT_TEST_MKDIR(set);
    if (output_test_path(path, sizeof(path), set, sample) == 0)
    {
        return 0;
    }
    (void)OUTPUT_TEST_MKDIR(path);
    return 1;
}

// a sample's .points: its head (frames, depth, height, width, limbs, bits), the readings and the cumulative count, 0
// here, which S11 passes over, then each frame's count, voxels and levels, each point's levels `limbs` words of
// 0xA5A5A5A5; `trailing` adds one word past the last frame
static int output_test_points(const char *set, const char *sample, const unsigned int head[6],
                              const unsigned int *counts, const unsigned int *voxels, int trailing)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".points") ? fopen(path, "wb") : NULL;
    int ok = (file != NULL) && (fwrite(head, sizeof(unsigned int), 6u, file) == 6u);
    const unsigned long long zero = 0ull;
    for (unsigned int at = 0u; ok && (at < (1u + SCAN_READINGS)); at += 1u)
    {
        ok = fwrite(&zero, sizeof(zero), 1u, file) == 1u;
    }
    const unsigned int level = 0xA5A5A5A5u;
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; ok && (frame < head[0]); frame += 1u)
    {
        ok = (fwrite(&counts[frame], sizeof(unsigned int), 1u, file) == 1u) &&
             (fwrite(&voxels[taken], sizeof(unsigned int), counts[frame], file) == counts[frame]);
        for (unsigned int at = 0u; ok && (at < (counts[frame] * head[4])); at += 1u)
        {
            ok = fwrite(&level, sizeof(level), 1u, file) == 1u;
        }
        taken += counts[frame];
    }
    ok = ok && ((trailing == 0) || (fwrite(&level, sizeof(level), 1u, file) == 1u));
    const int closed = (file != NULL) && (fclose(file) == 0);
    return ok && closed;
}

static int output_test_links(const char *set, const char *sample, const OutputTestWords *words)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".links") ? fopen(path, "wb") : NULL;
    const int written = (file != NULL) && (words->count <= OUTPUT_TEST_WORDS) &&
                        (fwrite(words->words, sizeof(unsigned int), words->count, file) == words->count);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

// the .links header: frames, the view, the weights 16, 1, 1 and the cost's terms
static void output_test_head(OutputTestWords *words, unsigned int frames, unsigned int depth, unsigned int height,
                             unsigned int width)
{
    const unsigned int head[SORT_HEADER_WORDS] = {frames, depth, height, width, 16u, 1u, 1u, SORT_TERMS};
    for (unsigned int at = 0u; at < SORT_HEADER_WORDS; at += 1u)
    {
        output_test_put(words, head[at]);
    }
}

// a pair record: sources, targets, gate pairs, components (one a gate pair here), chosen, and kept, level and crossed
// 0, which S11 does not read
static void output_test_pair(OutputTestWords *words, unsigned int sources, unsigned int targets, unsigned int gate,
                             unsigned int chosen)
{
    const unsigned int record[SORT_PAIR_WORDS] = {sources, targets, gate, gate, chosen, 0u, 0u, 0u, 0u, 0u, 0u};
    for (unsigned int at = 0u; at < SORT_PAIR_WORDS; at += 1u)
    {
        output_test_put(words, record[at]);
    }
}

// a source record: a prediction S11 does not read, and the flags
static void output_test_source(OutputTestWords *words, unsigned int flags)
{
    const unsigned int record[SORT_SOURCE_WORDS] = {0xFFFFFFFFu, 7u, 9u, flags};
    for (unsigned int at = 0u; at < SORT_SOURCE_WORDS; at += 1u)
    {
        output_test_put(words, record[at]);
    }
}

// a gate pair record: source, target, the cost as its low word then its high, a weight and a component S11 does not
// read, and the flags
static void output_test_gate(OutputTestWords *words, unsigned int source, unsigned int target, unsigned long long cost,
                             unsigned int flags)
{
    const unsigned int record[SORT_GATE_WORDS] = {
        source, target, (unsigned int)(cost & 0xFFFFFFFFull), (unsigned int)(cost >> 32u), 1u, 0u, flags};
    for (unsigned int at = 0u; at < SORT_GATE_WORDS; at += 1u)
    {
        output_test_put(words, record[at]);
    }
}

typedef enum
{
    OUTPUT_FLAW_NONE = 0,
    OUTPUT_FLAW_FRAMES,
    OUTPUT_FLAW_VIEW,
    OUTPUT_FLAW_COUNT,
    OUTPUT_FLAW_RANGE,
    OUTPUT_FLAW_IN,
    OUTPUT_FLAW_OUT,
    OUTPUT_FLAW_CHOSEN,
    OUTPUT_FLAW_TRAILING,
    OUTPUT_FLAW_SHORT,
    OUTPUT_FLAW_POINTS_TRAILING,
    OUTPUT_FLAW_POINTS_OUTSIDE,
    OUTPUT_FLAW_MISSING,
    OUTPUT_FLAWS
} OutputFlaw;

static const char *const OUTPUT_FLAW_NAMES[OUTPUT_FLAWS] = {
    "chain",  "frames",   "view",  "count",           "range",          "in",     "out",
    "chosen", "trailing", "short", "points_trailing", "points_outside", "missing"};

// the chain: 4 frames in a 4 x 5 x 6 view, two limbs of levels a point. Frame 0 holds A (voxel 7), B (50) and C (100),
// frame 1 A (8) and D (119), frame 2 nothing, frame 3 E (0) and F (31). A links on at cost 2^32 + 5; C to D is in the
// gate and not chosen; B ends with its prediction outside the view and C ends inside it; A and D end at frame 1, D's
// prediction outside; D starts at frame 1, E and F at frame 3. A flaw breaks it one way. Written as `sample`
static int output_test_chain_as(const char *set, const char *sample, OutputFlaw flaw)
{
    const unsigned int head[6] = {4u, 4u, 5u, 6u, 2u, 34u};
    const unsigned int counts[4] = {3u, 2u, 0u, 2u};
    const unsigned int voxels[7] = {7u, 50u, 100u, 8u, 119u, 0u, (flaw == OUTPUT_FLAW_POINTS_OUTSIDE) ? 120u : 31u};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, (flaw == OUTPUT_FLAW_FRAMES) ? 3u : 4u, 4u, 5u, (flaw == OUTPUT_FLAW_VIEW) ? 7u : 6u);
    const unsigned int doubled = ((flaw == OUTPUT_FLAW_IN) || (flaw == OUTPUT_FLAW_OUT)) ? 1u : 0u;
    output_test_pair(&words, (flaw == OUTPUT_FLAW_COUNT) ? 4u : 3u, 2u, 2u + doubled,
                     (flaw == OUTPUT_FLAW_CHOSEN) ? 2u : (1u + doubled));
    output_test_source(&words, 0u);
    output_test_source(&words, SORT_SOURCE_OUTSIDE);
    output_test_source(&words, SORT_SOURCE_CARRIED);
    output_test_gate(&words, 0u, (flaw == OUTPUT_FLAW_RANGE) ? 2u : 0u, 0x100000005ull,
                     SORT_GATE_CHOSEN | SORT_GATE_FORWARD | SORT_GATE_BACKWARD);
    if (flaw == OUTPUT_FLAW_OUT)
    {
        output_test_gate(&words, 0u, 1u, 7ull, SORT_GATE_CHOSEN | SORT_GATE_FORWARD);
    }
    if (flaw == OUTPUT_FLAW_IN)
    {
        output_test_gate(&words, 1u, 0u, 7ull, SORT_GATE_CHOSEN | SORT_GATE_BACKWARD);
    }
    output_test_gate(&words, 2u, 1u, 9ull, SORT_GATE_FORWARD);
    output_test_pair(&words, 2u, 0u, 0u, 0u);
    output_test_source(&words, SORT_SOURCE_CARRIED);
    output_test_source(&words, SORT_SOURCE_OUTSIDE | SORT_SOURCE_CARRIED);
    if (flaw != OUTPUT_FLAW_SHORT)
    {
        output_test_pair(&words, 0u, 2u, 0u, 0u);
    }
    if (flaw == OUTPUT_FLAW_TRAILING)
    {
        output_test_put(&words, 0u);
    }
    // the sample with no .links has none from an earlier run either
    char stale[ENGINE_PATH_CAPACITY];
    if ((flaw == OUTPUT_FLAW_MISSING) && engine_sample_path(stale, sizeof(stale), set, sample, ".links"))
    {
        (void)remove(stale);
    }
    return output_test_directory(set, sample) &&
           output_test_points(set, sample, head, counts, voxels, flaw == OUTPUT_FLAW_POINTS_TRAILING) &&
           ((flaw == OUTPUT_FLAW_MISSING) || output_test_links(set, sample, &words));
}

static int output_test_chain(const char *set, OutputFlaw flaw)
{
    return output_test_chain_as(set, OUTPUT_FLAW_NAMES[flaw], flaw);
}

// a sample of no frames in the chain's view: the .points head and readings, and the .links header
static int output_test_empty(const char *set)
{
    const unsigned int head[6] = {0u, 4u, 5u, 6u, 2u, 34u};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, 0u, 4u, 5u, 6u);
    return output_test_directory(set, "empty") && output_test_points(set, "empty", head, NULL, NULL, 0) &&
           output_test_links(set, "empty", &words);
}

// how "second" is written: as worked by hand; with Q to R left unchosen, a link fewer, which changes its counts; or
// with its links crossed the other way, P to R and Q to S, which keeps every count
typedef enum
{
    OUTPUT_SECOND_WORKED = 0,
    OUTPUT_SECOND_FEWER,
    OUTPUT_SECOND_CROSSED,
    OUTPUT_SECOND_FORMS
} OutputSecond;

// two frames in a 1 x 2 x 3 view, no levels: P (voxel 0) and Q (5), then R (5) and S (0). As worked, P links to S at
// cost 0 and Q to R at cost 3; P to R is in the gate and not chosen. Q to S is in the gate only when crossed. Written
// as `sample`
static int output_test_second_as(const char *set, const char *sample, OutputSecond form)
{
    const unsigned int head[6] = {2u, 1u, 2u, 3u, 0u, 34u};
    const unsigned int counts[2] = {2u, 2u};
    const unsigned int voxels[4] = {0u, 5u, 5u, 0u};
    // each form's chosen flags on P to R, P to S, Q to R and Q to S
    const unsigned int chosen[OUTPUT_SECOND_FORMS][4] = {{0u, SORT_GATE_CHOSEN, SORT_GATE_CHOSEN, 0u},
                                                         {0u, SORT_GATE_CHOSEN, 0u, 0u},
                                                         {SORT_GATE_CHOSEN, 0u, 0u, SORT_GATE_CHOSEN}};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, 2u, 1u, 2u, 3u);
    output_test_pair(&words, 2u, 2u, (form == OUTPUT_SECOND_CROSSED) ? 4u : 3u,
                     (form == OUTPUT_SECOND_FEWER) ? 1u : 2u);
    output_test_source(&words, 0u);
    output_test_source(&words, 0u);
    output_test_gate(&words, 0u, 0u, 5ull, chosen[form][0] | SORT_GATE_FORWARD);
    output_test_gate(&words, 0u, 1u, 0ull, chosen[form][1] | SORT_GATE_BACKWARD);
    output_test_gate(&words, 1u, 0u, 3ull, chosen[form][2] | SORT_GATE_FORWARD | SORT_GATE_BACKWARD);
    if (form == OUTPUT_SECOND_CROSSED)
    {
        output_test_gate(&words, 1u, 1u, 3ull, chosen[form][3] | SORT_GATE_BACKWARD);
    }
    return output_test_directory(set, sample) && output_test_points(set, sample, head, counts, voxels, 0) &&
           output_test_links(set, sample, &words);
}

static int output_test_second(const char *set, OutputSecond form)
{
    return output_test_second_as(set, "second", form);
}

// a fork, written as `sample`: two frames in the 1 x 2 x 3 view, no levels: P (voxel 0) and Q (5), then R (5), S (0)
// and T (3). P links to S at cost 0 and Q to R at cost 3; P to T is in the gate and not chosen. T starts
static int output_test_fork(const char *set, const char *sample)
{
    const unsigned int head[6] = {2u, 1u, 2u, 3u, 0u, 34u};
    const unsigned int counts[2] = {2u, 3u};
    const unsigned int voxels[5] = {0u, 5u, 5u, 0u, 3u};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, 2u, 1u, 2u, 3u);
    output_test_pair(&words, 2u, 3u, 3u, 2u);
    output_test_source(&words, 0u);
    output_test_source(&words, 0u);
    output_test_gate(&words, 0u, 1u, 0ull, SORT_GATE_CHOSEN | SORT_GATE_BACKWARD);
    output_test_gate(&words, 0u, 2u, 4ull, SORT_GATE_FORWARD | SORT_GATE_BACKWARD);
    output_test_gate(&words, 1u, 0u, 3ull, SORT_GATE_CHOSEN | SORT_GATE_FORWARD | SORT_GATE_BACKWARD);
    return output_test_directory(set, sample) && output_test_points(set, sample, head, counts, voxels, 0) &&
           output_test_links(set, sample, &words);
}

// CRC-64/XZ a bit at a time from its reflected polynomial, restated apart from engine/codecs/crc/crc.h's table: over
// `count` bytes, carried on from `crc`
static unsigned long long output_test_crc_bytes(unsigned long long crc, const unsigned char *bytes, size_t count)
{
    for (size_t at = 0u; at < count; at += 1u)
    {
        crc ^= bytes[at];
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            crc = ((crc & 1ull) != 0ull) ? ((crc >> 1u) ^ 0xC96C5795D7870F42ull) : (crc >> 1u);
        }
    }
    return crc;
}

// the whole file's CRC-64/XZ, or 0 with `read` cleared when it does not read
static unsigned long long output_test_file_crc(const char *path, int *read)
{
    FILE *const file = fopen(path, "rb");
    unsigned char chunk[4096];
    unsigned long long crc = ~0ull;
    size_t got = 0u;
    do
    {
        got = (file != NULL) ? fread(chunk, 1u, sizeof(chunk), file) : 0u;
        crc = output_test_crc_bytes(crc, chunk, got);
    } while (got == sizeof(chunk));
    *read = (file != NULL) && (ferror(file) == 0);
    if (file != NULL)
    {
        fclose(file);
    }
    return *read ? ~crc : 0ull;
}

// how a .divide is broken, each errored in the output
typedef enum
{
    OUTPUT_DIVIDE_OK = 0,
    OUTPUT_DIVIDE_HEAD,
    OUTPUT_DIVIDE_FRAMES,
    OUTPUT_DIVIDE_VIEW,
    OUTPUT_DIVIDE_CRC,
    OUTPUT_DIVIDE_COUNT,
    OUTPUT_DIVIDE_PARENT,
    OUTPUT_DIVIDE_ORDER,
    OUTPUT_DIVIDE_ONE,
    OUTPUT_DIVIDE_TWO,
    OUTPUT_DIVIDE_TWO_PAST,
    OUTPUT_DIVIDE_LEFT,
    OUTPUT_DIVIDE_DIVIDES,
    OUTPUT_DIVIDE_SHORT,
    OUTPUT_DIVIDE_TRAILING,
    OUTPUT_DIVIDE_FLAWS
} OutputDivideFlaw;

static const char *const OUTPUT_DIVIDE_NAMES[OUTPUT_DIVIDE_FLAWS] = {
    "divide_good",     "divide_head",   "divide_frames",  "divide_view",  "divide_crc",
    "divide_count",    "divide_parent", "divide_order",   "divide_one",   "divide_two",
    "divide_two_past", "divide_left",   "divide_divides", "divide_short", "divide_trailing"};

// .divide and .faces open with the same six words: the frames, the view and the CRC-64 of the .links
static_assert(DIVIDE_HEADER_WORDS == FACES_HEADER_WORDS, "the .divide head and the .faces head are one layout");

// a file the output reads beside the sample's .links, written as `suffix`: its head (the .points' frames and view
// given, and the CRC-64 of the .links, `skew` added), then `blocks` blocks, each its count from `counts` and that many
// records of `record_words` words from `records`, in order, and `extra` words of 0 past the last block. `head_words` of
// the head are written, the blocks only when that is all of it, and `short_by` words are taken off the end
static int output_test_beside(const char *set, const char *sample, const char *suffix, const unsigned int view[4],
                              unsigned long long skew, unsigned int blocks, const unsigned int *counts,
                              const unsigned int *records, unsigned int record_words, unsigned int extra,
                              unsigned int head_words, unsigned int short_by)
{
    char path[ENGINE_PATH_CAPACITY];
    int read = 0;
    const unsigned long long crc = engine_sample_path(path, sizeof(path), set, sample, ".links")
                                       ? (output_test_file_crc(path, &read) + skew)
                                       : 0ull;
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[DIVIDE_HEADER_WORDS] = {
        view[0], view[1], view[2], view[3], (unsigned int)(crc & 0xFFFFFFFFull), (unsigned int)(crc >> 32u)};
    for (unsigned int at = 0u; at < head_words; at += 1u)
    {
        output_test_put(&words, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int block = 0u; (head_words == DIVIDE_HEADER_WORDS) && (block < blocks); block += 1u)
    {
        output_test_put(&words, counts[block]);
        for (unsigned int at = 0u; at < (counts[block] * record_words); at += 1u)
        {
            output_test_put(&words, records[taken + at]);
        }
        taken += counts[block] * record_words;
    }
    for (unsigned int at = 0u; at < extra; at += 1u)
    {
        output_test_put(&words, 0u);
    }
    words.count -= (short_by < words.count) ? short_by : words.count;
    FILE *const file = (read && engine_sample_path(path, sizeof(path), set, sample, suffix)) ? fopen(path, "wb") : NULL;
    const int written = (file != NULL) && (words.count <= OUTPUT_TEST_WORDS) &&
                        (fwrite(words.words, sizeof(unsigned int), words.count, file) == words.count);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

// the sample's .divide: each pair's divisions from `divisions` (`counts[pair]` of DIVIDE_WORDS words, in order), the
// rest as output_test_beside writes it
static int output_test_divide(const char *set, const char *sample, const unsigned int view[4], unsigned long long skew,
                              const unsigned int *counts, const unsigned int *divisions, unsigned int extra,
                              unsigned int head_words, unsigned int short_by)
{
    return output_test_beside(set, sample, ".divide", view, skew, (view[0] != 0u) ? (view[0] - 1u) : 0u, counts,
                              divisions, DIVIDE_WORDS, extra, head_words, short_by);
}

// the sample's .faces: each frame's points' words from `points` (`counts[frame]` of FACES_POINT_WORDS words, in
// order), the rest as output_test_beside writes it
static int output_test_faces(const char *set, const char *sample, const unsigned int view[4], unsigned long long skew,
                             const unsigned int *counts, const unsigned int *points, unsigned int extra,
                             unsigned int head_words, unsigned int short_by)
{
    return output_test_beside(set, sample, ".faces", view, skew, view[0], counts, points, FACES_POINT_WORDS, extra,
                              head_words, short_by);
}

// the sample's .divide taken away, or none there
static void output_test_undivide(const char *set, const char *sample)
{
    char path[ENGINE_PATH_CAPACITY];
    if (engine_sample_path(path, sizeof(path), set, sample, ".divide"))
    {
        (void)remove(path);
    }
}

// chain's .divide: at frames 0 and 1, A divides, keeping its link to A and taking D, which starts, as daughter two
static int output_test_chain_divide(const char *set)
{
    const unsigned int view[4] = {4u, 4u, 5u, 6u};
    const unsigned int counts[3] = {1u, 0u, 0u};
    const unsigned int divisions[DIVIDE_WORDS] = {0u, 0u, 1u, DIVIDE_NONE};
    return output_test_divide(set, "chain", view, 0ull, counts, divisions, 0u, DIVIDE_HEADER_WORDS, 0u);
}

// a copy of second as `sample` and its .divide, as worked or broken one way. As worked, P divides, keeping its link to
// S and taking R from Q, which ends. A count past the frame's points is written with its three divisions' words, and
// a short .divide stops after its count
static int output_test_second_divide(const char *set, const char *sample, OutputDivideFlaw flaw)
{
    unsigned int view[4] = {2u, 1u, 2u, 3u};
    view[0] = (flaw == OUTPUT_DIVIDE_FRAMES) ? 3u : view[0];
    view[3] = (flaw == OUTPUT_DIVIDE_VIEW) ? 4u : view[3];
    unsigned int counts[2] = {(flaw == OUTPUT_DIVIDE_COUNT) ? 3u : 1u, 0u};
    unsigned int divisions[3u * DIVIDE_WORDS] = {0u, 1u, 0u, 1u};
    switch (flaw)
    {
    case OUTPUT_DIVIDE_PARENT:
        divisions[0] = 2u;
        break;
    case OUTPUT_DIVIDE_ONE:
        divisions[1] = 0u;
        divisions[2] = 1u;
        divisions[3] = 0u;
        break;
    case OUTPUT_DIVIDE_TWO:
        divisions[2] = 1u;
        divisions[3] = 0u;
        break;
    case OUTPUT_DIVIDE_TWO_PAST:
        divisions[2] = 2u;
        divisions[3] = DIVIDE_NONE;
        break;
    case OUTPUT_DIVIDE_LEFT:
        divisions[3] = DIVIDE_NONE;
        break;
    case OUTPUT_DIVIDE_ORDER: {
        // Q divides first, taking S from P; then P, which comes before Q
        const unsigned int two[2u * DIVIDE_WORDS] = {1u, 0u, 1u, 0u, 0u, 1u, 0u, 1u};
        memcpy(divisions, two, sizeof(two));
        counts[0] = 2u;
    }
    break;
    default:
        break;
    }
    return output_test_second_as(set, sample, OUTPUT_SECOND_WORKED) &&
           output_test_divide(set, sample, view, (flaw == OUTPUT_DIVIDE_CRC) ? 1ull : 0ull, counts, divisions,
                              (flaw == OUTPUT_DIVIDE_TRAILING) ? 1u : 0u,
                              (flaw == OUTPUT_DIVIDE_HEAD) ? 3u : DIVIDE_HEADER_WORDS,
                              (flaw == OUTPUT_DIVIDE_SHORT) ? DIVIDE_WORDS : 0u);
}

// fork's .divide for "divides": P takes T, which starts; then Q, keeping its link to R, takes S from P, which divides
static int output_test_fork_divide(const char *set, const char *sample)
{
    const unsigned int view[4] = {2u, 1u, 2u, 3u};
    const unsigned int counts[1] = {2u};
    const unsigned int divisions[2u * DIVIDE_WORDS] = {0u, 1u, 2u, DIVIDE_NONE, 1u, 0u, 1u, 0u};
    return output_test_fork(set, sample) &&
           output_test_divide(set, sample, view, 0ull, counts, divisions, 0u, DIVIDE_HEADER_WORDS, 0u);
}

// the sample's .faces taken away, or none there
static void output_test_unface(const char *set, const char *sample)
{
    char path[ENGINE_PATH_CAPACITY];
    if (engine_sample_path(path, sizeof(path), set, sample, ".faces"))
    {
        (void)remove(path);
    }
}

// how a .faces is broken, each errored in the output
typedef enum
{
    OUTPUT_FACES_OK = 0,
    OUTPUT_FACES_HEAD,
    OUTPUT_FACES_FRAMES,
    OUTPUT_FACES_VIEW,
    OUTPUT_FACES_CRC,
    OUTPUT_FACES_COUNT,
    OUTPUT_FACES_FLAG,
    OUTPUT_FACES_BACK,
    OUTPUT_FACES_AHEAD,
    OUTPUT_FACES_FIRST,
    OUTPUT_FACES_LAST,
    OUTPUT_FACES_CARRIED,
    OUTPUT_FACES_ENTERING,
    OUTPUT_FACES_LEAVING,
    OUTPUT_FACES_SHORT,
    OUTPUT_FACES_TRAILING,
    OUTPUT_FACES_FLAWS
} OutputFacesFlaw;

static const char *const OUTPUT_FACES_NAMES[OUTPUT_FACES_FLAWS] = {
    "faces_good",     "faces_head",    "faces_frames", "faces_view",    "faces_crc",  "faces_count",
    "faces_flag",     "faces_back",    "faces_ahead",  "faces_first",   "faces_last", "faces_carried",
    "faces_entering", "faces_leaving", "faces_short",  "faces_trailing"};

// a point's faces as the .faces flags hold them: those its back-prediction crosses and those its prediction crosses
#define OUTPUT_TEST_BACK(faces_) ((unsigned int)(faces_) << FACES_BACK_SHIFT)
#define OUTPUT_TEST_AHEAD(faces_) ((unsigned int)(faces_) << FACES_AHEAD_SHIFT)

// a copy of the chain as `sample` and its .faces, as worked by hand or broken one way. Frame 0's points are first and
// carry their places back: A (0, 1, 1), B (1, 3, 2), which ends with its prediction past the high x face and leaves,
// and C (3, 1, 4), whose own neighborhood the high x face cuts. At frame 1 A, which A links into, is carried back
// below the low x face, is no start, and enters nothing; D, which starts, is carried back past the high z face and
// enters, and ends with its prediction past the high y face and leaves. At frame 3, the last, E is carried back below
// the low z face and enters, and F, inside, does not. No point is carried by a link out: A and D end at frame 1 and
// frame 3 has none
static int output_test_chain_faces(const char *set, const char *sample, OutputFacesFlaw flaw)
{
    unsigned int view[4] = {4u, 4u, 5u, 6u};
    view[0] = (flaw == OUTPUT_FACES_FRAMES) ? 3u : view[0];
    view[3] = (flaw == OUTPUT_FACES_VIEW) ? 7u : view[3];
    unsigned int counts[4] = {(flaw == OUTPUT_FACES_COUNT) ? 2u : 3u, 2u, 0u, 2u};
    unsigned int points[7u * FACES_POINT_WORDS] = {
        0u,          1u,
        1u,          FACES_FIRST,
        1u,          3u,
        2u,          FACES_FIRST | FACES_LEAVING | OUTPUT_TEST_AHEAD(0x20u),
        3u,          1u,
        4u,          FACES_FIRST | (0x20u << FACES_HESSIAN_SHIFT),
        0u,          1u,
        0xFFFFFFFFu, OUTPUT_TEST_BACK(0x10u),
        4u,          4u,
        5u,          FACES_ENTERING | FACES_LEAVING | OUTPUT_TEST_BACK(0x02u) | OUTPUT_TEST_AHEAD(0x08u),
        0xFFFFFFFFu, 0u,
        0u,          FACES_ENTERING | FACES_LAST | OUTPUT_TEST_BACK(0x01u),
        1u,          0u,
        1u,          FACES_LAST};
    switch (flaw)
    {
    case OUTPUT_FACES_FLAG:
        points[3] |= 0x40u;
        break;
    case OUTPUT_FACES_BACK:
        points[3] |= OUTPUT_TEST_BACK(0x01u);
        break;
    case OUTPUT_FACES_AHEAD:
        points[11] |= OUTPUT_TEST_AHEAD(0x20u);
        break;
    case OUTPUT_FACES_FIRST:
        points[15] |= FACES_FIRST;
        break;
    case OUTPUT_FACES_LAST:
        points[27] &= ~FACES_LAST;
        break;
    case OUTPUT_FACES_CARRIED:
        points[15] |= FACES_CARRIED;
        break;
    case OUTPUT_FACES_ENTERING:
        points[19] &= ~FACES_ENTERING;
        break;
    case OUTPUT_FACES_LEAVING:
        points[7] &= ~FACES_LEAVING;
        break;
    default:
        break;
    }
    return output_test_chain_as(set, sample, OUTPUT_FLAW_NONE) &&
           output_test_faces(set, sample, view, (flaw == OUTPUT_FACES_CRC) ? 1ull : 0ull, counts, points,
                             (flaw == OUTPUT_FACES_TRAILING) ? 1u : 0u,
                             (flaw == OUTPUT_FACES_HEAD) ? 3u : FACES_HEADER_WORDS,
                             (flaw == OUTPUT_FACES_SHORT) ? FACES_POINT_WORDS : 0u);
}

// the empty sample's .faces: its head, and no frame
static int output_test_empty_faces(const char *set)
{
    const unsigned int view[4] = {0u, 4u, 5u, 6u};
    return output_test_faces(set, "empty", view, 0ull, NULL, NULL, 0u, FACES_HEADER_WORDS, 0u);
}

// second's .faces, beside second as it stands: P and Q, at frame 0, carry their places back; at frame 1, the last, R
// is carried back to (0, 1, 2), or with `moved` past the high x face, and S below the low x face. R and S have their
// links in. Neither is a start and neither enters, and no count moves with R
static int output_test_second_faces(const char *set, int moved)
{
    const unsigned int view[4] = {2u, 1u, 2u, 3u};
    const unsigned int counts[2] = {2u, 2u};
    const unsigned int points[4u * FACES_POINT_WORDS] = {0u,
                                                         0u,
                                                         0u,
                                                         FACES_FIRST,
                                                         0u,
                                                         1u,
                                                         2u,
                                                         FACES_FIRST,
                                                         0u,
                                                         1u,
                                                         moved ? 3u : 2u,
                                                         FACES_LAST | (moved ? OUTPUT_TEST_BACK(0x20u) : 0u),
                                                         0u,
                                                         0u,
                                                         0xFFFFFFFFu,
                                                         FACES_LAST | OUTPUT_TEST_BACK(0x10u)};
    return output_test_faces(set, "second", view, 0ull, counts, points, 0u, FACES_HEADER_WORDS, 0u);
}

// the whole file's bytes, or NULL
static char *output_test_text(const char *path)
{
    FILE *const file = fopen(path, "rb");
    char *const text = (char *)malloc(OUTPUT_TEST_TEXT);
    if ((file == NULL) || (text == NULL))
    {
        if (file != NULL)
        {
            fclose(file);
        }
        free(text);
        return NULL;
    }
    const size_t read = fread(text, 1u, OUTPUT_TEST_TEXT - 1u, file);
    const int ended = (feof(file) != 0);
    fclose(file);
    text[read] = '\0';
    if (ended == 0)
    {
        free(text);
        return NULL;
    }
    return text;
}

typedef struct
{
    char nodes[ENGINE_PATH_CAPACITY];
    char submission[ENGINE_PATH_CAPACITY];
    char report[ENGINE_PATH_CAPACITY];
    FILE *files[3];
} OutputTestFiles;

// the nodes, the submission and the report, opened binary as open_output opens the nodes and the submission, the
// headers written
static int output_test_open(const char *set, const char *stem, OutputTestFiles *files)
{
    memset(files->files, 0, sizeof(files->files));
    char name[256];
    int ok = 1;
    char *const paths[3] = {files->nodes, files->submission, files->report};
    const char *const suffixes[3] = {"_nodes.tsv", "_submission.csv", "_report.txt"};
    for (unsigned int at = 0u; ok && (at < 3u); at += 1u)
    {
        const int named = snprintf(name, sizeof(name), "%s%s", stem, suffixes[at]);
        ok = (named > 0) && ((size_t)named < sizeof(name)) &&
             output_test_path(paths[at], ENGINE_PATH_CAPACITY, set, name);
        files->files[at] = ok ? fopen(paths[at], "wb") : NULL;
        ok = files->files[at] != NULL;
    }
    ok = ok && (fputs(OUTPUT_TEST_NODES_HEADER, files->files[0]) >= 0) &&
         (fputs(OUTPUT_SUBMISSION_HEADER, files->files[1]) >= 0);
    return ok;
}

static int output_test_close(OutputTestFiles *files)
{
    int ok = 1;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        ok = ok && (files->files[at] != NULL);
        ok = ((files->files[at] != NULL) && (fclose(files->files[at]) == 0)) && ok;
        files->files[at] = NULL;
    }
    return ok;
}

static int output_test_same(const char *path, const char *expected)
{
    char *const text = output_test_text(path);
    const int same = (text != NULL) && (strcmp(text, expected) == 0);
    if ((text != NULL) && (same == 0))
    {
        printf("  %s reads:\n%s  and was to read:\n%s", path, text, expected);
    }
    free(text);
    return same;
}

// the `count` samples run as a set into the files named `stem`, closed after: the set's result, and in `closed_all`
// whether the files opened and closed
static long output_test_run(const char *set, char *const *samples, unsigned int count, const char *stem,
                            OutputTestFiles *files, int *closed_all)
{
    const int opened = output_test_open(set, stem, files);
    const OutputRequest request = {set, samples, count, files->files[0], files->files[1], files->files[2]};
    fflush(stdout);
    const long result = opened ? output_graph_set(&request) : OUTPUT_ERROR;
    fflush(stderr);
    const int closed = output_test_close(files);
    *closed_all = opened && closed;
    return result;
}

static const char OUTPUT_TEST_NODES[] = OUTPUT_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t5\t0\t-1\t0\t-1\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t0\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t0\t3\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t1\t3\t0\t-1\t0\t-1\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

static const char OUTPUT_TEST_SUBMISSION[] = OUTPUT_SUBMISSION_HEADER "0,chain,node,1,0,0,1,1,-1,-1\n"
                                                                      "1,chain,node,2,0,1,3,2,-1,-1\n"
                                                                      "2,chain,node,3,0,3,1,4,-1,-1\n"
                                                                      "3,chain,node,4,1,0,1,2,-1,-1\n"
                                                                      "4,chain,node,5,1,3,4,5,-1,-1\n"
                                                                      "5,chain,node,6,3,0,0,0,-1,-1\n"
                                                                      "6,chain,node,7,3,1,0,1,-1,-1\n"
                                                                      "7,chain,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                      "8,second,node,1,0,0,0,0,-1,-1\n"
                                                                      "9,second,node,2,0,0,1,2,-1,-1\n"
                                                                      "10,second,node,3,1,0,1,2,-1,-1\n"
                                                                      "11,second,node,4,1,0,0,0,-1,-1\n"
                                                                      "12,second,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                      "13,second,edge,-1,-1,-1,-1,-1,2,3\n";

// a sample's line of the counts: its name, frames, nodes and edges, and the rest as the set writes it
typedef struct
{
    const char *sample;
    unsigned long long frames;
    unsigned long long nodes;
    unsigned long long edges;
    const char *rest;
} OutputTestLine;

// the counts as the set writes them: the header, a line for each of the three samples, and then `tail`
static int output_test_counts(char *expected, size_t capacity, const OutputTestLine lines[3], const char *tail)
{
    int written = snprintf(expected, capacity, "  %-24s %6s %10s %10s %s\n", "sample", "frames", "nodes", "edges",
                           "ends (outside the view; most a frame), starts (most a frame); H4");
    // a non-negative length is compared whole against the capacity left
    int ok = (written > 0) && ((size_t)written < capacity);
    size_t used = ok ? (size_t)written : 0u;
    for (unsigned int line = 0u; ok && (line < 3u); line += 1u)
    {
        written = snprintf(&expected[used], capacity - used, "  %-24s %6llu %10llu %10llu %s\n", lines[line].sample,
                           lines[line].frames, lines[line].nodes, lines[line].edges, lines[line].rest);
        ok = (written > 0) && ((size_t)written < (capacity - used));
        used += ok ? (size_t)written : 0u;
    }
    written = ok ? snprintf(&expected[used], capacity - used, "%s", tail) : 0;
    return ok && (written > 0) && ((size_t)written < (capacity - used));
}

// the counts, worked by hand: the chain's ends are B and C at frame 0 and A and D at frame 1, B and D predicted
// outside; its starts D at frame 1 and E and F at frame 3
static int output_test_report(char *expected, size_t capacity)
{
    const OutputTestLine lines[3] = {{"chain", 4ull, 7ull, 1ull, "4 (2; 2), 3 (2); held on 3 of 3 frame pairs"},
                                     {"empty", 0ull, 0ull, 0ull, "0 (0; 0), 0 (0); held on 0 of 0 frame pairs"},
                                     {"second", 2ull, 4ull, 2ull, "0 (0; 0), 0 (0); held on 1 of 1 frame pairs"}};
    return output_test_counts(expected, capacity, lines,
                              "  checked 3 of 3 samples: 6 frames, 11 nodes, 3 edges; no point has two links in or two"
                              " out, and none divides; 4 ends (2 with their prediction outside the view), 3 starts,"
                              " none explained before S8 and S9; H4 held on 4 of 4 frame pairs\n"
                              "  the nodes: 11 rows after the header\n"
                              "  the submission: 14 rows after the header, 11 node rows and 3 edge rows\n");
}

static const char OUTPUT_TEST_DIVIDED_NODES[] = OUTPUT_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t5\t8\t-1\t0\t0\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t0\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t3\t8\t-1\t0\t0\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

static const char OUTPUT_TEST_DIVIDED_SUBMISSION[] = OUTPUT_SUBMISSION_HEADER "0,chain,node,1,0,0,1,1,-1,-1\n"
                                                                              "1,chain,node,2,0,1,3,2,-1,-1\n"
                                                                              "2,chain,node,3,0,3,1,4,-1,-1\n"
                                                                              "3,chain,node,4,1,0,1,2,-1,-1\n"
                                                                              "4,chain,node,5,1,3,4,5,-1,-1\n"
                                                                              "5,chain,node,6,3,0,0,0,-1,-1\n"
                                                                              "6,chain,node,7,3,1,0,1,-1,-1\n"
                                                                              "7,chain,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                              "8,chain,edge,-1,-1,-1,-1,-1,1,5\n"
                                                                              "9,second,node,1,0,0,0,0,-1,-1\n"
                                                                              "10,second,node,2,0,0,1,2,-1,-1\n"
                                                                              "11,second,node,3,1,0,1,2,-1,-1\n"
                                                                              "12,second,node,4,1,0,0,0,-1,-1\n"
                                                                              "13,second,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                              "14,second,edge,-1,-1,-1,-1,-1,1,3\n";

// the divided set's counts, worked by hand. The chain's A divides at frame 0, taking D, which started. D no longer
// starts; second's P divides, taking R from Q, which now ends. Each .divide's division and its move are counted
static int output_test_divided_report(char *expected, size_t capacity)
{
    const OutputTestLine lines[3] = {{"chain", 4ull, 7ull, 2ull,
                                      "4 (2; 2), 2 (2); held on 3 of 3 frame pairs; its .divide: 1 divisions, 0 of them"
                                      " moving a link"},
                                     {"empty", 0ull, 0ull, 0ull, "0 (0; 0), 0 (0); held on 0 of 0 frame pairs"},
                                     {"second", 2ull, 4ull, 2ull,
                                      "1 (0; 1), 0 (0); held on 1 of 1 frame pairs; its .divide: 1 divisions, 1 of them"
                                      " moving a link"}};
    return output_test_counts(expected, capacity, lines,
                              "  checked 3 of 3 samples: 6 frames, 11 nodes, 4 edges; no point has two links in, and"
                              " only a division's parent has two out: 2 divisions from 2 .divide files, 1 of them"
                              " moving a link; 5 ends (2 with their prediction outside the view), 2 starts, none"
                              " explained before S8 and S9; H4 held on 4 of 4 frame pairs\n"
                              "  the nodes: 11 rows after the header\n"
                              "  the submission: 15 rows after the header, 11 node rows and 4 edge rows\n");
}

// the set with a .faces beside each sample: the rows are the undivided set's but for three states. The chain's B, an
// end whose prediction crosses a face, left (0x020); D, a start carried back across one that ends crossing another,
// entered and left (0x021); E, a start carried back across one, entered (0x001). A, carried back across a face, has
// its link in and is none of them, and so are second's R and S
static const char OUTPUT_TEST_FACED_NODES[] = OUTPUT_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t32\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t5\t33\t-1\t0\t-1\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t1\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t0\t3\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t1\t3\t0\t-1\t0\t-1\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

// the faced set's counts, worked by hand: the chain's ends B, C, A and D, of which B and D leave the view; its starts
// D, E and F, of which D and E enter it; 3 points in its first frame and 2 in its last. Neither empty nor second has an
// end or a start, and second has 2 points in each of its frames
static int output_test_faced_report(char *expected, size_t capacity)
{
    const OutputTestLine lines[3] = {{"chain", 4ull, 7ull, 1ull,
                                      "4 (2; 2), 3 (2); held on 3 of 3 frame pairs; its .faces: 2 of the ends leave the"
                                      " view, 2 of the starts enter it; 3 points in the first frame, 2 in the last"},
                                     {"empty", 0ull, 0ull, 0ull,
                                      "0 (0; 0), 0 (0); held on 0 of 0 frame pairs; its .faces: 0 of the ends leave the"
                                      " view, 0 of the starts enter it; 0 points in the first frame, 0 in the last"},
                                     {"second", 2ull, 4ull, 2ull,
                                      "0 (0; 0), 0 (0); held on 1 of 1 frame pairs; its .faces: 0 of the ends leave the"
                                      " view, 0 of the starts enter it; 2 points in the first frame, 2 in the last"}};
    return output_test_counts(expected, capacity, lines,
                              "  checked 3 of 3 samples: 6 frames, 11 nodes, 3 edges; no point has two links in or two"
                              " out, and none divides; 4 ends (2 with their prediction outside the view), 3 starts, and"
                              " in the 3 samples with a .faces 2 of their 4 ends leave the view and 2 of their 3 starts"
                              " enter it, the rest unexplained before S8, with 5 points in their first frames and 4 in"
                              " their last; H4 held on 4 of 4 frame pairs\n"
                              "  the nodes: 11 rows after the header\n"
                              "  the submission: 14 rows after the header, 11 node rows and 3 edge rows\n");
}

// the faced set with chain's .divide and second's: the divided rows, and the states the .faces give on the output's
// links. D, daughter two, has its link in. It split (0x008) and left (0x020) but entered nothing: 0x028. The
// .faces is the sort's links' and was checked against them before the .divide
static const char OUTPUT_TEST_FACED_DIVIDED_NODES[] = OUTPUT_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t32\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t5\t40\t-1\t0\t0\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t1\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t3\t8\t-1\t0\t0\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

// the faced and divided set's counts, worked by hand: the chain still ends at B, C, A and D, B and D leaving, and
// starts at E and F alone, E entering; second's Q, which R was taken from, ends inside the view
static int output_test_faced_divided_report(char *expected, size_t capacity)
{
    const OutputTestLine lines[3] = {{"chain", 4ull, 7ull, 2ull,
                                      "4 (2; 2), 2 (2); held on 3 of 3 frame pairs; its .divide: 1 divisions, 0 of them"
                                      " moving a link; its .faces: 2 of the ends leave the view, 1 of the starts enter"
                                      " it; 3 points in the first frame, 2 in the last"},
                                     {"empty", 0ull, 0ull, 0ull,
                                      "0 (0; 0), 0 (0); held on 0 of 0 frame pairs; its .faces: 0 of the ends leave the"
                                      " view, 0 of the starts enter it; 0 points in the first frame, 0 in the last"},
                                     {"second", 2ull, 4ull, 2ull,
                                      "1 (0; 1), 0 (0); held on 1 of 1 frame pairs; its .divide: 1 divisions, 1 of them"
                                      " moving a link; its .faces: 0 of the ends leave the view, 0 of the starts enter"
                                      " it; 2 points in the first frame, 2 in the last"}};
    return output_test_counts(expected, capacity, lines,
                              "  checked 3 of 3 samples: 6 frames, 11 nodes, 4 edges; no point has two links in, and"
                              " only a division's parent has two out: 2 divisions from 2 .divide files, 1 of them"
                              " moving a link; 5 ends (2 with their prediction outside the view), 2 starts, and in the"
                              " 3 samples with a .faces 2 of their 5 ends leave the view and 1 of their 2 starts enter"
                              " it, the rest unexplained before S8, with 5 points in their first frames and 4 in their"
                              " last; H4 held on 4 of 4 frame pairs\n"
                              "  the nodes: 11 rows after the header\n"
                              "  the submission: 15 rows after the header, 11 node rows and 4 edge rows\n");
}

static void output_test_complete(OutputTestResults *results, const char *set)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    // a .divide or a .faces left by a run that stopped short would divide the set or give it states
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        output_test_undivide(set, samples[at]);
        output_test_unface(set, samples[at]);
    }
    OutputTestFiles files;
    const int written = output_test_chain(set, OUTPUT_FLAW_NONE) && output_test_empty(set) &&
                        output_test_second(set, OUTPUT_SECOND_WORKED) && output_test_open(set, "whole", &files);
    output_test_check(results, written, "the synthetic set is written: the chain, a sample of no frames, and a second");
    if (written == 0)
    {
        return;
    }
    const OutputRequest request = {set, samples, 3u, files.files[0], files.files[1], files.files[2]};
    fflush(stdout);
    const long result = output_graph_set(&request);
    fflush(stderr);
    const int closed = output_test_close(&files);
    output_test_check(results, (result == 0L) && closed, "the set writes and its files close");
    output_test_check(results, output_test_same(files.nodes, OUTPUT_TEST_NODES),
                      "the nodes are the hand's to the character: 11 rows of 25 columns");
    output_test_check(results, output_test_same(files.submission, OUTPUT_TEST_SUBMISSION),
                      "the submission is the hand's to the character: ids from 0 over the set, node ids from 1 in a"
                      " sample, its nodes and then its edges");
    char *const expected = (char *)malloc(OUTPUT_TEST_TEXT);
    output_test_check(results,
                      (expected != NULL) && output_test_report(expected, OUTPUT_TEST_TEXT) &&
                          output_test_same(files.report, expected),
                      "the counts are the hand's: frames, nodes, edges, ends and those outside, starts, and H4");
    char *const shown = output_test_text(files.report);
    printf("  the counts the set wrote:\n%s", (shown != NULL) ? shown : "  (they did not read)\n");
    free(shown);
    free(expected);

    // no nodes and no submission named: the set is checked and counted, and nothing is written
    OutputTestFiles quiet;
    const int opened = output_test_open(set, "quiet", &quiet);
    const OutputRequest unnamed = {set, samples, 3u, NULL, NULL, quiet.files[2]};
    const long counted = opened ? output_graph_set(&unnamed) : OUTPUT_ERROR;
    output_test_close(&quiet);
    char *const said = output_test_text(quiet.report);
    const char *const tail = "  the nodes: no output named, none written\n"
                             "  the submission: no output named, none written\n";
    const size_t tail_length = strlen(tail);
    output_test_check(results,
                      (counted == 0L) && (said != NULL) && (strlen(said) >= tail_length) &&
                          (strcmp(&said[strlen(said) - tail_length], tail) == 0),
                      "with no nodes and no submission named, the set is counted and says nothing was written");
    free(said);
}

// .divide files of no divisions beside the chain, empty and second: each head as the .points' and the CRC-64 of its
// .links, and a count of 0 for each frame pair
static int output_test_undivided(const char *set)
{
    const unsigned int chain[4] = {4u, 4u, 5u, 6u};
    const unsigned int empty[4] = {0u, 4u, 5u, 6u};
    const unsigned int second[4] = {2u, 1u, 2u, 3u};
    const unsigned int counts[3] = {0u, 0u, 0u};
    return output_test_divide(set, "chain", chain, 0ull, counts, NULL, 0u, DIVIDE_HEADER_WORDS, 0u) &&
           output_test_divide(set, "empty", empty, 0ull, counts, NULL, 0u, DIVIDE_HEADER_WORDS, 0u) &&
           output_test_divide(set, "second", second, 0ull, counts, NULL, 0u, DIVIDE_HEADER_WORDS, 0u);
}

// S7's divisions: the set with chain's .divide and second's, every row and count checked against the hand's. Then each
// of the three with a .divide of no divisions, whose nodes and submission are the undivided set's byte for byte. The
// .divide files are taken away after
static void output_test_divided(OutputTestResults *results, const char *set)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    int closed_all = 0;
    const int written = output_test_chain(set, OUTPUT_FLAW_NONE) && output_test_empty(set) &&
                        output_test_chain_divide(set) && output_test_second_divide(set, "second", OUTPUT_DIVIDE_OK);
    output_test_check(results, written, "the divided set is written: chain's .divide and second's beside their .links");
    const long result = written ? output_test_run(set, samples, 3u, "divided", &files, &closed_all) : OUTPUT_ERROR;
    output_test_check(results, (result == 0L) && closed_all, "the divided set writes and its files close");
    output_test_check(results, closed_all && output_test_same(files.nodes, OUTPUT_TEST_DIVIDED_NODES),
                      "the divided nodes are the hand's to the character: a parent's two links out, daughter two's"
                      " link in and split_from, and the point it left ended");
    output_test_check(results, closed_all && output_test_same(files.submission, OUTPUT_TEST_DIVIDED_SUBMISSION),
                      "the divided submission is the hand's to the character: a parent's edge to daughter one and then"
                      " its edge to daughter two, and none from the point daughter two left");
    char *const expected = (char *)malloc(OUTPUT_TEST_TEXT);
    output_test_check(results,
                      closed_all && (expected != NULL) && output_test_divided_report(expected, OUTPUT_TEST_TEXT) &&
                          output_test_same(files.report, expected),
                      "the divided counts are the hand's: H4 with each parent counted, and the divisions and moves of"
                      " each .divide");
    char *const shown = closed_all ? output_test_text(files.report) : NULL;
    printf("  the counts the divided set wrote:\n%s", (shown != NULL) ? shown : "  (they did not read)\n");
    free(shown);
    free(expected);

    const int undivided = output_test_undivided(set);
    const long plain = undivided ? output_test_run(set, samples, 3u, "undivided", &files, &closed_all) : OUTPUT_ERROR;
    output_test_check(results,
                      undivided && (plain == 0L) && closed_all && output_test_same(files.nodes, OUTPUT_TEST_NODES) &&
                          output_test_same(files.submission, OUTPUT_TEST_SUBMISSION),
                      "a .divide of no divisions beside each sample: the nodes and the submission are the undivided"
                      " set's byte for byte");
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        output_test_undivide(set, samples[at]);
    }
}

// S9's faces: the set with a .faces beside each sample, every row and count checked against the hand's; its submission
// is the undivided set's byte for byte, since the state is the nodes' alone. Then with chain's .divide and second's
// beside them too, every row and count checked against the hand's again. The .faces and .divide files are taken away
// after
static void output_test_faced(OutputTestResults *results, const char *set)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    int closed_all = 0;
    const int written = output_test_chain_faces(set, "chain", OUTPUT_FACES_OK) && output_test_empty(set) &&
                        output_test_empty_faces(set) && output_test_second(set, OUTPUT_SECOND_WORKED) &&
                        output_test_second_faces(set, 0);
    output_test_check(results, written, "the faced set is written: a .faces beside each sample's .links");
    const long result = written ? output_test_run(set, samples, 3u, "faced", &files, &closed_all) : OUTPUT_ERROR;
    output_test_check(results, (result == 0L) && closed_all, "the faced set writes and its files close");
    output_test_check(results, closed_all && output_test_same(files.nodes, OUTPUT_TEST_FACED_NODES),
                      "the faced nodes are the hand's to the character: an end whose prediction crosses a face left,"
                      " a start whose back-prediction crosses one entered, and a point with its link in did neither");
    output_test_check(results, closed_all && output_test_same(files.submission, OUTPUT_TEST_SUBMISSION),
                      "the faced submission is the undivided set's byte for byte: the state is the nodes' alone");
    char *const expected = (char *)malloc(OUTPUT_TEST_TEXT);
    output_test_check(results,
                      closed_all && (expected != NULL) && output_test_faced_report(expected, OUTPUT_TEST_TEXT) &&
                          output_test_same(files.report, expected),
                      "the faced counts are the hand's: the ends that leave the view, the starts that enter it, and"
                      " the points of the first and last frames");
    char *const shown = closed_all ? output_test_text(files.report) : NULL;
    printf("  the counts the faced set wrote:\n%s", (shown != NULL) ? shown : "  (they did not read)\n");
    free(shown);

    const int divided = output_test_chain_divide(set) && output_test_second_divide(set, "second", OUTPUT_DIVIDE_OK);
    output_test_check(results, divided, "chain's .divide and second's are written beside the faced set");
    const long both = divided ? output_test_run(set, samples, 3u, "faced_divided", &files, &closed_all) : OUTPUT_ERROR;
    output_test_check(results, (both == 0L) && closed_all, "the faced and divided set writes and its files close");
    output_test_check(results, closed_all && output_test_same(files.nodes, OUTPUT_TEST_FACED_DIVIDED_NODES),
                      "the faced and divided nodes are the hand's to the character: daughter two split, and left by"
                      " its .faces, and enters nothing, having its link in");
    output_test_check(results, closed_all && output_test_same(files.submission, OUTPUT_TEST_DIVIDED_SUBMISSION),
                      "the faced and divided submission is the divided set's byte for byte");
    output_test_check(results,
                      closed_all && (expected != NULL) &&
                          output_test_faced_divided_report(expected, OUTPUT_TEST_TEXT) &&
                          output_test_same(files.report, expected),
                      "the faced and divided counts are the hand's: the ends and starts on the output's links, the"
                      " division's daughter no start");
    char *const said = closed_all ? output_test_text(files.report) : NULL;
    printf("  the counts the faced and divided set wrote:\n%s", (said != NULL) ? said : "  (they did not read)\n");
    free(said);
    free(expected);
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        output_test_undivide(set, samples[at]);
        output_test_unface(set, samples[at]);
    }
}

static void output_test_errors(OutputTestResults *results, const char *set)
{
    char *error[2] = {(char *)"chain", NULL};
    for (unsigned int flaw = OUTPUT_FLAW_FRAMES; flaw < (unsigned int)OUTPUT_FLAWS; flaw += 1u)
    {
        error[1] = (char *)OUTPUT_FLAW_NAMES[flaw];
        OutputTestFiles files;
        const int written = output_test_chain(set, (OutputFlaw)flaw) && output_test_open(set, "errored", &files);
        const OutputRequest request = {set, error, 2u, files.files[0], files.files[1], files.files[2]};
        fflush(stdout);
        const long result = written ? output_graph_set(&request) : 0L;
        fflush(stderr);
        const int closed = written && output_test_close(&files);
        char what[256];
        snprintf(what, sizeof(what), "the good chain and then %s: the set errors and writes nothing past the headers",
                 OUTPUT_FLAW_NAMES[flaw]);
        output_test_check(results,
                          written && closed && (result == OUTPUT_ERROR) &&
                              output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER) &&
                              output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                          what);
    }
    // a name with a comma errors before its files are sought
    error[1] = (char *)"comma,name";
    OutputTestFiles files;
    const int opened = output_test_open(set, "errored", &files);
    const OutputRequest request = {set, error, 2u, files.files[0], files.files[1], files.files[2]};
    fflush(stdout);
    const long result = opened ? output_graph_set(&request) : 0L;
    fflush(stderr);
    const int closed = opened && output_test_close(&files);
    output_test_check(results,
                      opened && closed && (result == OUTPUT_ERROR) &&
                          output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER) &&
                          output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                      "the good chain and then a name with a comma: the set errors and writes nothing past the"
                      " headers");

    char *const one[1] = {(char *)"chain"};
    const OutputRequest none = {set, one, 0u, NULL, NULL, stdout};
    const OutputRequest unset = {NULL, one, 1u, NULL, NULL, stdout};
    const OutputRequest unlisted = {set, NULL, 1u, NULL, NULL, stdout};
    const OutputRequest unreported = {set, one, 1u, NULL, NULL, NULL};
    output_test_check(results, output_graph_set(NULL) == OUTPUT_ERROR, "no request errors");
    output_test_check(results, output_graph_set(&none) == OUTPUT_ERROR, "a set of no samples errors");
    output_test_check(results, output_graph_set(&unset) == OUTPUT_ERROR, "no set errors");
    output_test_check(results, output_graph_set(&unlisted) == OUTPUT_ERROR, "no sample list errors");
    output_test_check(results, output_graph_set(&unreported) == OUTPUT_ERROR, "no report errors");
}

// the good chain and then a copy of second with its .divide as worked, which writes; then with each broken .divide in
// its place, and fork's for a division taking from a point that divides: the set errors and writes nothing past the
// headers
static void output_test_divide_errors(OutputTestResults *results, const char *set)
{
    char *error[2] = {(char *)"chain", NULL};
    for (unsigned int flaw = OUTPUT_DIVIDE_OK; flaw < (unsigned int)OUTPUT_DIVIDE_FLAWS; flaw += 1u)
    {
        const char *const sample = OUTPUT_DIVIDE_NAMES[flaw];
        error[1] = (char *)sample;
        const int made =
            output_test_chain(set, OUTPUT_FLAW_NONE) &&
            ((flaw == OUTPUT_DIVIDE_DIVIDES) ? output_test_fork_divide(set, sample)
                                             : output_test_second_divide(set, sample, (OutputDivideFlaw)flaw));
        OutputTestFiles files;
        int closed_all = 0;
        const long result = made ? output_test_run(set, error, 2u, "errored", &files, &closed_all) : 0L;
        char what[256];
        if (flaw == OUTPUT_DIVIDE_OK)
        {
            snprintf(what, sizeof(what), "the good chain and then %s: the set writes", sample);
            output_test_check(results, made && closed_all && (result == 0L), what);
            continue;
        }
        snprintf(what, sizeof(what), "the good chain and then %s: the set errors and writes nothing past the headers",
                 sample);
        output_test_check(results,
                          made && closed_all && (result == OUTPUT_ERROR) &&
                              output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER) &&
                              output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                          what);
    }
}

// the good chain and then a copy of it with its .faces as worked, which writes; then with each broken .faces in its
// place: a head cut short, frames or a view not the .points', a CRC-64 not its .links', a frame's count not its
// points', a flag no .faces sets, back-prediction faces not its place's, prediction faces on a point the .links does
// not flag outside, a first-frame flag off frame 0, no last-frame flag on the last, a carried flag on a point with no
// link out, a start carried back across a face not entering, an end predicted across one not leaving, a point cut
// short, and a word past the last frame. The set errors and writes nothing past the headers
static void output_test_faces_errors(OutputTestResults *results, const char *set)
{
    char *error[2] = {(char *)"chain", NULL};
    for (unsigned int flaw = OUTPUT_FACES_OK; flaw < (unsigned int)OUTPUT_FACES_FLAWS; flaw += 1u)
    {
        const char *const sample = OUTPUT_FACES_NAMES[flaw];
        error[1] = (char *)sample;
        const int made =
            output_test_chain(set, OUTPUT_FLAW_NONE) && output_test_chain_faces(set, sample, (OutputFacesFlaw)flaw);
        OutputTestFiles files;
        int closed_all = 0;
        const long result = made ? output_test_run(set, error, 2u, "errored", &files, &closed_all) : 0L;
        char what[256];
        if (flaw == OUTPUT_FACES_OK)
        {
            snprintf(what, sizeof(what), "the good chain and then %s: the set writes", sample);
            output_test_check(results, made && closed_all && (result == 0L), what);
            continue;
        }
        snprintf(what, sizeof(what), "the good chain and then %s: the set errors and writes nothing past the headers",
                 sample);
        output_test_check(results,
                          made && closed_all && (result == OUTPUT_ERROR) &&
                              output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER) &&
                              output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                          what);
    }
}

// the start of `text` up to the first place `stop` begins, or 0 when `stop` is not in it or the capacity is too small
static int output_test_before(char *out, size_t capacity, const char *text, const char *stop)
{
    const char *const at = strstr(text, stop);
    const size_t length = (at != NULL) ? (size_t)(at - text) : 0u;
    if ((at == NULL) || (length >= capacity))
    {
        return 0;
    }
    memcpy(out, text, length);
    out[length] = '\0';
    return 1;
}

// H4 fed one end too many on each frame pair, through the seam, on the set as worked or with chain's .divide and
// second's: the set errors and writes nothing past the headers
static void output_test_skewed(OutputTestResults *results, const char *set, int divided, const char *what)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    const int written =
        divided ? (output_test_chain_divide(set) && output_test_second_divide(set, "second", OUTPUT_DIVIDE_OK))
                : output_test_second(set, OUTPUT_SECOND_WORKED);
    int closed_all = 0;
    output_test_skew = 1ull;
    const long result = written ? output_test_run(set, samples, 3u, "skewed", &files, &closed_all) : 0L;
    output_test_skew = 0ull;
    output_test_check(results,
                      written && closed_all && (result == OUTPUT_ERROR) &&
                          output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER) &&
                          output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                      what);
    output_test_undivide(set, "chain");
    output_test_undivide(set, "second");
}

// the form "second" is rewritten to between the two passes, and whether the rewrite was written
static OutputSecond output_test_rewrite = OUTPUT_SECOND_WORKED;
static int output_test_rewritten = 0;

static void output_test_rewrite_second(const OutputRequest *request)
{
    output_test_rewritten = output_test_second(request->set, output_test_rewrite);
}

// "second" rewritten to `form` between the two passes, through the seam: the set errors at it, with chain's rows
// written, and empty's, which are none, and nothing of second's
static void output_test_changed(OutputTestResults *results, const char *set, OutputSecond form, const char *what)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    const int written = output_test_second(set, OUTPUT_SECOND_WORKED) && output_test_open(set, "changed", &files);
    const OutputRequest request = {set, samples, 3u, files.files[0], files.files[1], files.files[2]};
    output_test_rewrite = form;
    output_test_rewritten = 0;
    output_test_between = output_test_rewrite_second;
    fflush(stdout);
    const long result = written ? output_graph_set(&request) : 0L;
    fflush(stderr);
    output_test_between = NULL;
    const int closed = written && output_test_close(&files);
    char nodes[sizeof(OUTPUT_TEST_NODES)];
    char submission[sizeof(OUTPUT_TEST_SUBMISSION)];
    const int expected = output_test_before(nodes, sizeof(nodes), OUTPUT_TEST_NODES, "second\t") &&
                         output_test_before(submission, sizeof(submission), OUTPUT_TEST_SUBMISSION, "8,second,");
    output_test_check(results,
                      written && closed && output_test_rewritten && expected && (result == OUTPUT_ERROR) &&
                          output_test_same(files.nodes, nodes) && output_test_same(files.submission, submission),
                      what);
}

// whether the call between the passes puts second's .divide beside it, as worked, or takes it away
static int output_test_dividing = 0;

static void output_test_redivide_second(const OutputRequest *request)
{
    char path[ENGINE_PATH_CAPACITY];
    output_test_rewritten =
        output_test_dividing
            ? output_test_second_divide(request->set, "second", OUTPUT_DIVIDE_OK)
            : (engine_sample_path(path, sizeof(path), request->set, "second", ".divide") && (remove(path) == 0));
}

// chain's .divide beside it, and second's .divide taken away between the two passes, or put beside it there, through
// the seam: the set errors at second, with chain's rows written, divided, and empty's, and nothing of second's
static void output_test_divide_changed(OutputTestResults *results, const char *set, int dividing, const char *what)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    output_test_undivide(set, "second");
    const int written =
        output_test_chain_divide(set) && (dividing ? output_test_second(set, OUTPUT_SECOND_WORKED)
                                                   : output_test_second_divide(set, "second", OUTPUT_DIVIDE_OK));
    OutputTestFiles files;
    int closed_all = 0;
    output_test_dividing = dividing;
    output_test_rewritten = 0;
    output_test_between = output_test_redivide_second;
    const long result = written ? output_test_run(set, samples, 3u, "changed", &files, &closed_all) : 0L;
    output_test_between = NULL;
    char nodes[sizeof(OUTPUT_TEST_DIVIDED_NODES)];
    char submission[sizeof(OUTPUT_TEST_DIVIDED_SUBMISSION)];
    const int expected =
        output_test_before(nodes, sizeof(nodes), OUTPUT_TEST_DIVIDED_NODES, "second\t") &&
        output_test_before(submission, sizeof(submission), OUTPUT_TEST_DIVIDED_SUBMISSION, "9,second,");
    output_test_check(results,
                      written && closed_all && output_test_rewritten && expected && (result == OUTPUT_ERROR) &&
                          output_test_same(files.nodes, nodes) && output_test_same(files.submission, submission),
                      what);
    output_test_undivide(set, "chain");
    output_test_undivide(set, "second");
}

// whether the call between the passes rewrites second's .faces with R carried back past a face, or takes it away
static int output_test_refacing = 0;

static void output_test_reface_second(const OutputRequest *request)
{
    char path[ENGINE_PATH_CAPACITY];
    output_test_rewritten =
        output_test_refacing
            ? output_test_second_faces(request->set, 1)
            : (engine_sample_path(path, sizeof(path), request->set, "second", ".faces") && (remove(path) == 0));
}

// second's .faces as worked, then rewritten between the two passes with R carried back past a face, which moves no
// count, or taken away there, through the seam: the set errors at second, with chain's rows written, and empty's,
// and nothing of second's
static void output_test_faces_changed(OutputTestResults *results, const char *set, int refacing, const char *what)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    const int written = output_test_second(set, OUTPUT_SECOND_WORKED) && output_test_second_faces(set, 0);
    OutputTestFiles files;
    int closed_all = 0;
    output_test_refacing = refacing;
    output_test_rewritten = 0;
    output_test_between = output_test_reface_second;
    const long result = written ? output_test_run(set, samples, 3u, "changed", &files, &closed_all) : 0L;
    output_test_between = NULL;
    char nodes[sizeof(OUTPUT_TEST_NODES)];
    char submission[sizeof(OUTPUT_TEST_SUBMISSION)];
    const int expected = output_test_before(nodes, sizeof(nodes), OUTPUT_TEST_NODES, "second\t") &&
                         output_test_before(submission, sizeof(submission), OUTPUT_TEST_SUBMISSION, "8,second,");
    output_test_check(results,
                      written && closed_all && output_test_rewritten && expected && (result == OUTPUT_ERROR) &&
                          output_test_same(files.nodes, nodes) && output_test_same(files.submission, submission),
                      what);
    output_test_unface(set, "second");
}

// "second" crossed reads every count the first pass reads as worked: the counts of the set with it, nothing named, are
// the hand's for the worked set. Only its links tell it apart
static void output_test_crossed_counts(OutputTestResults *results, const char *set)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    const int written = output_test_second(set, OUTPUT_SECOND_CROSSED) && output_test_open(set, "crossed", &files);
    const OutputRequest request = {set, samples, 3u, NULL, NULL, files.files[2]};
    const long result = written ? output_graph_set(&request) : OUTPUT_ERROR;
    const int closed = written && output_test_close(&files);
    char *const worked = (char *)malloc(OUTPUT_TEST_TEXT);
    char *const counts = (char *)malloc(OUTPUT_TEST_TEXT);
    const char *const tail = "  the nodes: no output named, none written\n"
                             "  the submission: no output named, none written\n";
    const int expected = (worked != NULL) && (counts != NULL) && output_test_report(worked, OUTPUT_TEST_TEXT) &&
                         output_test_before(counts, OUTPUT_TEST_TEXT - strlen(tail), worked, "  the nodes:");
    // the capacity left for the counts before the tail holds the tail and its end
    if (expected)
    {
        memcpy(&counts[strlen(counts)], tail, strlen(tail) + 1u);
    }
    output_test_check(results,
                      written && closed && (result == 0L) && expected && output_test_same(files.report, counts),
                      "\"second\" crossed reads the same counts as worked: frames, nodes, edges, ends, starts and H4");
    free(worked);
    free(counts);
}

// a file opened for reading, which no row can be written to. First what the C library returns on one written to, as
// output_flushed and then output_close meet it; then the set with its nodes such a file, and then its submission: each
// errors, output_close fails on that file and holds on the other, which is written whole
static void output_test_unwritable(OutputTestResults *results, const char *set)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const made = output_test_path(path, sizeof(path), set, "unwritable.txt") ? fopen(path, "wb") : NULL;
    const int made_closed = (made != NULL) && (fclose(made) == 0);
    FILE *const measurement = made_closed ? fopen(path, "rb") : NULL;
    if (measurement != NULL)
    {
        const int printed = fprintf(measurement, "a row\n");
        const int flushed = fflush(measurement);
        const int error = ferror(measurement);
        const int closed = fclose(measurement);
        printf("  a file opened for reading, written to: fprintf returned %d, fflush %d, ferror %d, then fclose %d\n",
               printed, flushed, error, closed);
    }
    output_test_check(results, measurement != NULL,
                      "a file is opened for reading, and what the C library returns is shown");

    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    const char *const names[2] = {"the nodes", "the submission"};
    const char *const expected_files[2] = {OUTPUT_TEST_NODES, OUTPUT_TEST_SUBMISSION};
    for (unsigned int which = 0u; which < 2u; which += 1u)
    {
        const unsigned int other = 1u - which;
        OutputTestFiles files;
        int written = output_test_second(set, OUTPUT_SECOND_WORKED) && output_test_open(set, "unwritable", &files);
        // the file in `which`'s place, its header written, is closed and opened again for reading
        char *const paths[2] = {files.nodes, files.submission};
        written = written && (fclose(files.files[which]) == 0);
        files.files[which] = written ? fopen(paths[which], "rb") : NULL;
        written = written && (files.files[which] != NULL);
        const OutputRequest request = {set, samples, 3u, files.files[0], files.files[1], files.files[2]};
        fflush(stdout);
        const long result = written ? output_graph_set(&request) : 0L;
        fflush(stderr);
        const int unwritten = written && (ferror(files.files[which]) != 0);
        const int errored = written && (output_close(files.files[which], paths[which]) == 0);
        fflush(stderr);
        const int other_closed = written && (output_close(files.files[other], paths[other]) == 1);
        files.files[which] = NULL;
        files.files[other] = NULL;
        const int report_closed = (files.files[2] != NULL) && (fclose(files.files[2]) == 0);
        files.files[2] = NULL;
        char what[256];
        snprintf(what, sizeof(what),
                 "%s opened for reading: the set errors, the file's error is set, output_close"
                 " fails on it and holds on %s, written whole",
                 names[which], names[other]);
        output_test_check(results,
                          written && report_closed && (result == OUTPUT_ERROR) && unwritten && errored &&
                              other_closed && output_test_same(paths[other], expected_files[other]),
                          what);
    }
    output_test_check(results, output_close(NULL, "no file") == 1, "output_close on no file holds: nothing was named");
}

static void output_test_faults(OutputTestResults *results, const char *set)
{
    output_test_skewed(results, set, 0,
                       "H4 fed one end too many on each frame pair: the set errors and writes nothing past the"
                       " headers");
    output_test_skewed(results, set, 1,
                       "H4 fed one end too many on each frame pair of the divided set: the set errors and writes"
                       " nothing past the headers");
    output_test_divide_changed(results, set, 0,
                               "second's .divide taken away between the passes: the set errors with only chain's"
                               " divided rows and empty's written");
    output_test_divide_changed(results, set, 1,
                               "a .divide put beside second between the passes: the set errors with only chain's"
                               " divided rows and empty's written");
    output_test_faces_changed(results, set, 1,
                              "second's .faces rewritten between the passes, R carried back past a face and every"
                              " count the same: the set errors with only chain's and empty's rows written");
    output_test_faces_changed(results, set, 0,
                              "second's .faces taken away between the passes: the set errors with only chain's and"
                              " empty's rows written");
    output_test_changed(results, set, OUTPUT_SECOND_FEWER,
                        "\"second\" rewritten between the passes with a link fewer: the set errors with only chain's"
                        " and empty's rows written");
    output_test_changed(results, set, OUTPUT_SECOND_CROSSED,
                        "\"second\" rewritten between the passes with its links crossed, every count the same: the"
                        " set errors with only chain's and empty's rows written");
    output_test_crossed_counts(results, set);
    output_test_unwritable(results, set);
    output_test_check(results, output_test_second(set, OUTPUT_SECOND_WORKED), "\"second\" is written back as worked");
}

// every file the test wrote, the whole, the quiet, the divided, the faced, the faced and divided and the last errored,
// read as bytes: a carriage return in any of them is a line not ended in LF alone
static void output_test_line_ends(OutputTestResults *results, const char *set)
{
    const char *const stems[6] = {"whole", "quiet", "divided", "faced", "faced_divided", "errored"};
    const char *const suffixes[3] = {"_nodes.tsv", "_submission.csv", "_report.txt"};
    int clean = 1;
    for (unsigned int stem = 0u; stem < 6u; stem += 1u)
    {
        for (unsigned int suffix = 0u; suffix < 3u; suffix += 1u)
        {
            char name[256];
            char path[ENGINE_PATH_CAPACITY];
            const int named = snprintf(name, sizeof(name), "%s%s", stems[stem], suffixes[suffix]);
            char *const text =
                ((named > 0) && ((size_t)named < sizeof(name)) && output_test_path(path, sizeof(path), set, name))
                    ? output_test_text(path)
                    : NULL;
            clean = clean && (text != NULL) && (strchr(text, '\r') == NULL);
            free(text);
        }
    }
    output_test_check(results, clean, "no file the test wrote holds a carriage return: every line ends in LF alone");
}

int main(int count, char **arguments)
{
    OutputTestResults results = {0u, 0u};
    const char *const set = (count > 1) ? arguments[1] : NULL;
    output_test_check(&results, set != NULL, "the synthetic set's directory is named");
    if (set != NULL)
    {
        output_test_complete(&results, set);
        output_test_divided(&results, set);
        output_test_faced(&results, set);
        output_test_errors(&results, set);
        output_test_divide_errors(&results, set);
        output_test_faces_errors(&results, set);
        output_test_faults(&results, set);
        output_test_line_ends(&results, set);
    }
    printf("  output test: %u checks, %u failed\n", results.checks, results.failures);
    return (results.failures == 0u) ? 0 : 1;
}
