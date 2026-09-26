// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// S11, the output (cell_tracking/src/output/output_graph), every point kept. A synthetic set written as .points and
// .links runs through output_graph_set: a chain of four frames in a 4 x 5 x 6 view whose points carry two limbs of
// levels, with a link at a cost past 32 bits, a gate pair left unchosen, an end whose prediction lies outside the view,
// a start, an empty frame and two starts after it; a sample of no frames; and a second sample of two frames whose links
// cross, so its node ids count from 1 again while the submission's row ids run on. Every row of the nodes and of the
// submission, and every line of the counts, is held against text worked by hand. Then each of thirteen broken samples
// runs after the good chain, and the set refuses with nothing written past the headers: .links frames or a view that
// disagree with the .points, a pair whose sources are not the frame's points, a chosen link past the points, two links
// into one point and two out of one, a pair whose chosen count is not its gate's, a .links or a .points with a word
// past its last frame, a .links that stops a pair short, a voxel outside the view, a sample with no .links, and a name
// with a comma. Malformed requests refuse. H4 failing is not forced: the one-to-one links imply it, and the output says
// so; nor is a sample that changes between the two passes. The test is host work and touches no device, so it is no
// job.
//
// The test links no engine.cu, so engine_sample_path below restates engine/engine.cu's, and output_graph.cu's paths
// are built by the restatement here: a change to either format must be made in both.
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

// the lines the test writes where open_output writes the headers; nothing may follow them when a set refuses
#define OUTPUT_TEST_NODES_HEADER "the nodes header, which open_output writes\n"

// the test links no engine.cu: the engine's sample path, restated as engine/engine.cu's engine_sample_path writes it.
// A change to that format must be made here too
extern "C" int engine_sample_path(char *out, size_t room, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(out, room, "%s/%s/%s%s", set, sample, sample, suffix);
    // a non-negative length is compared whole against the room
    return (written > 0) && ((size_t)written < room);
}

typedef struct
{
    unsigned int checks;
    unsigned int failures;
} OutputTestTally;

static void output_test_check(OutputTestTally *tally, int held, const char *what)
{
    tally->checks += 1u;
    if (held == 0)
    {
        tally->failures += 1u;
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

static int output_test_path(char *path, size_t room, const char *set, const char *name)
{
    const int written = snprintf(path, room, "%s/%s", set, name);
    // a non-negative length is compared whole against the room
    return (written > 0) && ((size_t)written < room);
}

static int output_test_directory(const char *set, const char *sample)
{
    char path[ENGINE_PATH_ROOM];
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
    char path[ENGINE_PATH_ROOM];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".points") ? fopen(path, "wb") : NULL;
    int good = (file != NULL) && (fwrite(head, sizeof(unsigned int), 6u, file) == 6u);
    const unsigned long long zero = 0ull;
    for (unsigned int at = 0u; good && (at < (1u + SCAN_READINGS)); at += 1u)
    {
        good = fwrite(&zero, sizeof(zero), 1u, file) == 1u;
    }
    const unsigned int level = 0xA5A5A5A5u;
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; good && (frame < head[0]); frame += 1u)
    {
        good = (fwrite(&counts[frame], sizeof(unsigned int), 1u, file) == 1u)
            && (fwrite(&voxels[taken], sizeof(unsigned int), counts[frame], file) == counts[frame]);
        for (unsigned int at = 0u; good && (at < (counts[frame] * head[4])); at += 1u)
        {
            good = fwrite(&level, sizeof(level), 1u, file) == 1u;
        }
        taken += counts[frame];
    }
    good = good && ((trailing == 0) || (fwrite(&level, sizeof(level), 1u, file) == 1u));
    const int closed = (file != NULL) && (fclose(file) == 0);
    return good && closed;
}

static int output_test_links(const char *set, const char *sample, const OutputTestWords *words)
{
    char path[ENGINE_PATH_ROOM];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".links") ? fopen(path, "wb") : NULL;
    const int written = (file != NULL) && (words->count <= OUTPUT_TEST_WORDS)
                     && (fwrite(words->words, sizeof(unsigned int), words->count, file) == words->count);
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
    const unsigned int record[SORT_GATE_WORDS] = {source, target, (unsigned int)(cost & 0xFFFFFFFFull),
                                                  (unsigned int)(cost >> 32u), 1u, 0u, flags};
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

static const char *const OUTPUT_FLAW_NAMES[OUTPUT_FLAWS] = {"chain", "frames", "view", "count", "range", "in", "out",
                                                            "chosen", "trailing", "short", "points_trailing",
                                                            "points_outside", "missing"};

// the chain: 4 frames in a 4 x 5 x 6 view, two limbs of levels a point. Frame 0 holds A (voxel 7), B (50) and C (100),
// frame 1 A (8) and D (119), frame 2 nothing, frame 3 E (0) and F (31). A links on at cost 2^32 + 5; C to D is in the
// gate and not chosen; B ends with its prediction outside the view and C ends inside it; A and D end at frame 1, D's
// prediction outside; D starts at frame 1, E and F at frame 3. A flaw breaks it one way
static int output_test_chain(const char *set, OutputFlaw flaw)
{
    const char *const sample = OUTPUT_FLAW_NAMES[flaw];
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
    char stale[ENGINE_PATH_ROOM];
    if ((flaw == OUTPUT_FLAW_MISSING) && engine_sample_path(stale, sizeof(stale), set, sample, ".links"))
    {
        (void)remove(stale);
    }
    return output_test_directory(set, sample)
        && output_test_points(set, sample, head, counts, voxels, flaw == OUTPUT_FLAW_POINTS_TRAILING)
        && ((flaw == OUTPUT_FLAW_MISSING) || output_test_links(set, sample, &words));
}

// a sample of no frames in the chain's view: the .points head and readings, and the .links header
static int output_test_empty(const char *set)
{
    const unsigned int head[6] = {0u, 4u, 5u, 6u, 2u, 34u};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, 0u, 4u, 5u, 6u);
    return output_test_directory(set, "empty") && output_test_points(set, "empty", head, NULL, NULL, 0)
        && output_test_links(set, "empty", &words);
}

// two frames in a 1 x 2 x 3 view, no levels: P (voxel 0) and Q (5), then R (5) and S (0). P links to S at cost 0 and
// Q to R at cost 3; P to R is in the gate and not chosen
static int output_test_second(const char *set)
{
    const unsigned int head[6] = {2u, 1u, 2u, 3u, 0u, 34u};
    const unsigned int counts[2] = {2u, 2u};
    const unsigned int voxels[4] = {0u, 5u, 5u, 0u};
    OutputTestWords words;
    memset(&words, 0, sizeof(words));
    output_test_head(&words, 2u, 1u, 2u, 3u);
    output_test_pair(&words, 2u, 2u, 3u, 2u);
    output_test_source(&words, 0u);
    output_test_source(&words, 0u);
    output_test_gate(&words, 0u, 0u, 5ull, SORT_GATE_FORWARD);
    output_test_gate(&words, 0u, 1u, 0ull, SORT_GATE_CHOSEN | SORT_GATE_BACKWARD);
    output_test_gate(&words, 1u, 0u, 3ull, SORT_GATE_CHOSEN | SORT_GATE_FORWARD | SORT_GATE_BACKWARD);
    return output_test_directory(set, "second") && output_test_points(set, "second", head, counts, voxels, 0)
        && output_test_links(set, "second", &words);
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
    char nodes[ENGINE_PATH_ROOM];
    char submission[ENGINE_PATH_ROOM];
    char report[ENGINE_PATH_ROOM];
    FILE *files[3];
} OutputTestFiles;

// the nodes, the submission and the report, opened binary as open_output opens the nodes and the submission, the
// headers written
static int output_test_open(const char *set, const char *stem, OutputTestFiles *files)
{
    memset(files->files, 0, sizeof(files->files));
    char name[256];
    int good = 1;
    char *const paths[3] = {files->nodes, files->submission, files->report};
    const char *const suffixes[3] = {"_nodes.tsv", "_submission.csv", "_report.txt"};
    for (unsigned int at = 0u; good && (at < 3u); at += 1u)
    {
        const int named = snprintf(name, sizeof(name), "%s%s", stem, suffixes[at]);
        good = (named > 0) && ((size_t)named < sizeof(name))
            && output_test_path(paths[at], ENGINE_PATH_ROOM, set, name);
        files->files[at] = good ? fopen(paths[at], "wb") : NULL;
        good = files->files[at] != NULL;
    }
    good = good && (fputs(OUTPUT_TEST_NODES_HEADER, files->files[0]) >= 0)
        && (fputs(OUTPUT_SUBMISSION_HEADER, files->files[1]) >= 0);
    return good;
}

static int output_test_close(OutputTestFiles *files)
{
    int good = 1;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        good = good && (files->files[at] != NULL);
        good = ((files->files[at] != NULL) && (fclose(files->files[at]) == 0)) && good;
        files->files[at] = NULL;
    }
    return good;
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

static const char OUTPUT_TEST_NODES[] =
    OUTPUT_TEST_NODES_HEADER
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

static const char OUTPUT_TEST_SUBMISSION[] =
    OUTPUT_SUBMISSION_HEADER
    "0,chain,node,1,0,0,1,1,-1,-1\n"
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

// the counts, worked by hand: the chain's ends are B and C at frame 0 and A and D at frame 1, B and D predicted
// outside; its starts D at frame 1 and E and F at frame 3
static int output_test_report(char *expected, size_t room)
{
    size_t used = 0u;
    int good = 1;
    const char *const lines[7] = {"  %-24s %6s %10s %10s %s\n", "  %-24s %6llu %10llu %10llu %s\n",
                                  "  %-24s %6llu %10llu %10llu %s\n", "  %-24s %6llu %10llu %10llu %s\n", "%s", "%s",
                                  "%s"};
    for (unsigned int line = 0u; good && (line < 7u); line += 1u)
    {
        int written = 0;
        if (line == 0u)
        {
            written = snprintf(&expected[used], room - used, lines[line], "sample", "frames", "nodes", "edges",
                               "ends (outside the view; most a frame), starts (most a frame); H4");
        }
        else if (line == 1u)
        {
            written = snprintf(&expected[used], room - used, lines[line], "chain", 4ull, 7ull, 1ull,
                               "4 (2; 2), 3 (2); held on 3 of 3 frame pairs");
        }
        else if (line == 2u)
        {
            written = snprintf(&expected[used], room - used, lines[line], "empty", 0ull, 0ull, 0ull,
                               "0 (0; 0), 0 (0); held on 0 of 0 frame pairs");
        }
        else if (line == 3u)
        {
            written = snprintf(&expected[used], room - used, lines[line], "second", 2ull, 4ull, 2ull,
                               "0 (0; 0), 0 (0); held on 1 of 1 frame pairs");
        }
        else if (line == 4u)
        {
            written = snprintf(&expected[used], room - used, lines[line],
                               "  checked 3 of 3 samples: 6 frames, 11 nodes, 3 edges; no point has two links in or"
                               " two out, and none divides; 4 ends (2 with their prediction outside the view), 3"
                               " starts, none explained before S8 and S9; H4 held on 4 of 4 frame pairs\n");
        }
        else if (line == 5u)
        {
            written = snprintf(&expected[used], room - used, lines[line], "  the nodes: 11 rows after the header\n");
        }
        else
        {
            written = snprintf(&expected[used], room - used, lines[line],
                               "  the submission: 14 rows after the header, 11 node rows and 3 edge rows\n");
        }
        // a non-negative length is compared whole against the room left
        good = (written > 0) && ((size_t)written < (room - used));
        used += good ? (size_t)written : 0u;
    }
    return good;
}

static void output_test_whole(OutputTestTally *tally, const char *set)
{
    char *const samples[3] = {(char *)"chain", (char *)"empty", (char *)"second"};
    OutputTestFiles files;
    const int written = output_test_chain(set, OUTPUT_FLAW_NONE) && output_test_empty(set) && output_test_second(set)
                     && output_test_open(set, "whole", &files);
    output_test_check(tally, written, "the synthetic set is written: the chain, a sample of no frames, and a second");
    if (written == 0)
    {
        return;
    }
    const OutputRequest request = {set, samples, 3u, files.files[0], files.files[1], files.files[2]};
    fflush(stdout);
    const long result = output_graph_set(&request);
    fflush(stderr);
    const int closed = output_test_close(&files);
    output_test_check(tally, (result == 0L) && closed, "the set writes and its files close");
    output_test_check(tally, output_test_same(files.nodes, OUTPUT_TEST_NODES),
                      "the nodes are the hand's to the character: 11 rows of 25 columns");
    output_test_check(tally, output_test_same(files.submission, OUTPUT_TEST_SUBMISSION),
                      "the submission is the hand's to the character: ids from 0 over the set, node ids from 1 in a"
                      " sample, its nodes and then its edges");
    char *const expected = (char *)malloc(OUTPUT_TEST_TEXT);
    output_test_check(tally, (expected != NULL) && output_test_report(expected, OUTPUT_TEST_TEXT)
                                 && output_test_same(files.report, expected),
                      "the counts are the hand's: frames, nodes, edges, ends and those outside, starts, and H4");
    char *const shown = output_test_text(files.report);
    printf("  the counts the set wrote:\n%s", (shown != NULL) ? shown : "  (they did not read)\n");
    free(shown);
    free(expected);

    // no nodes and no submission named: the set is checked and counted, and nothing is written
    OutputTestFiles quiet;
    const int opened = output_test_open(set, "quiet", &quiet);
    const OutputRequest unnamed = {set, samples, 3u, NULL, NULL, quiet.files[2]};
    const long counted = opened ? output_graph_set(&unnamed) : OUTPUT_REFUSED;
    output_test_close(&quiet);
    char *const said = output_test_text(quiet.report);
    const char *const tail = "  the nodes: no output named, none written\n"
                             "  the submission: no output named, none written\n";
    const size_t tail_length = strlen(tail);
    output_test_check(tally, (counted == 0L) && (said != NULL) && (strlen(said) >= tail_length)
                                 && (strcmp(&said[strlen(said) - tail_length], tail) == 0),
                      "with no nodes and no submission named, the set is counted and says nothing was written");
    free(said);
}

static void output_test_refusals(OutputTestTally *tally, const char *set)
{
    char *refusing[2] = {(char *)"chain", NULL};
    for (unsigned int flaw = OUTPUT_FLAW_FRAMES; flaw < (unsigned int)OUTPUT_FLAWS; flaw += 1u)
    {
        refusing[1] = (char *)OUTPUT_FLAW_NAMES[flaw];
        OutputTestFiles files;
        const int written = output_test_chain(set, (OutputFlaw)flaw) && output_test_open(set, "refused", &files);
        const OutputRequest request = {set, refusing, 2u, files.files[0], files.files[1], files.files[2]};
        fflush(stdout);
        const long result = written ? output_graph_set(&request) : 0L;
        fflush(stderr);
        const int closed = written && output_test_close(&files);
        char what[256];
        snprintf(what, sizeof(what), "the good chain and then %s: the set refuses and writes nothing past the headers",
                 OUTPUT_FLAW_NAMES[flaw]);
        output_test_check(tally, written && closed && (result == OUTPUT_REFUSED)
                                     && output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER)
                                     && output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                          what);
    }
    // a name with a comma refuses before its files are sought
    refusing[1] = (char *)"comma,name";
    OutputTestFiles files;
    const int opened = output_test_open(set, "refused", &files);
    const OutputRequest request = {set, refusing, 2u, files.files[0], files.files[1], files.files[2]};
    fflush(stdout);
    const long result = opened ? output_graph_set(&request) : 0L;
    fflush(stderr);
    const int closed = opened && output_test_close(&files);
    output_test_check(tally, opened && closed && (result == OUTPUT_REFUSED)
                                 && output_test_same(files.nodes, OUTPUT_TEST_NODES_HEADER)
                                 && output_test_same(files.submission, OUTPUT_SUBMISSION_HEADER),
                      "the good chain and then a name with a comma: the set refuses and writes nothing past the"
                      " headers");

    char *const one[1] = {(char *)"chain"};
    const OutputRequest none = {set, one, 0u, NULL, NULL, stdout};
    const OutputRequest unset = {NULL, one, 1u, NULL, NULL, stdout};
    const OutputRequest unlisted = {set, NULL, 1u, NULL, NULL, stdout};
    const OutputRequest unreported = {set, one, 1u, NULL, NULL, NULL};
    output_test_check(tally, output_graph_set(NULL) == OUTPUT_REFUSED, "no request refuses");
    output_test_check(tally, output_graph_set(&none) == OUTPUT_REFUSED, "a set of no samples refuses");
    output_test_check(tally, output_graph_set(&unset) == OUTPUT_REFUSED, "no set refuses");
    output_test_check(tally, output_graph_set(&unlisted) == OUTPUT_REFUSED, "no sample list refuses");
    output_test_check(tally, output_graph_set(&unreported) == OUTPUT_REFUSED, "no report refuses");
    printf("  not forced here: H4 failing, which the one-to-one links imply cannot; a sample changing between the two"
           " passes\n");
}

// every file the test wrote, the whole, the quiet and the last refused, read as bytes: a carriage return in any of
// them is a line not ended in LF alone
static void output_test_line_ends(OutputTestTally *tally, const char *set)
{
    const char *const stems[3] = {"whole", "quiet", "refused"};
    const char *const suffixes[3] = {"_nodes.tsv", "_submission.csv", "_report.txt"};
    int clean = 1;
    for (unsigned int stem = 0u; stem < 3u; stem += 1u)
    {
        for (unsigned int suffix = 0u; suffix < 3u; suffix += 1u)
        {
            char name[256];
            char path[ENGINE_PATH_ROOM];
            const int named = snprintf(name, sizeof(name), "%s%s", stems[stem], suffixes[suffix]);
            char *const text = ((named > 0) && ((size_t)named < sizeof(name))
                                && output_test_path(path, sizeof(path), set, name))
                ? output_test_text(path)
                : NULL;
            clean = clean && (text != NULL) && (strchr(text, '\r') == NULL);
            free(text);
        }
    }
    output_test_check(tally, clean, "no file the test wrote holds a carriage return: every line ends in LF alone");
}

int main(int count, char **arguments)
{
    OutputTestTally tally = {0u, 0u};
    const char *const set = (count > 1) ? arguments[1] : NULL;
    output_test_check(&tally, set != NULL, "the synthetic set's directory is named");
    if (set != NULL)
    {
        output_test_whole(&tally, set);
        output_test_refusals(&tally, set);
        output_test_line_ends(&tally, set);
    }
    printf("  output test: %u checks, %u failed\n", tally.checks, tally.failures);
    return (tally.failures == 0u) ? 0 : 1;
}
