// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// S9's faces (cell_tracking/src/faces), faces_find_set on synthetic sets written as .points, .drift, .shape and .links,
// every .faces word checked against a hand's. walk is 4 frames in a 4 x 5 x 6 view. Frame 0 holds a (0, 0, 0) and b
// (3, 4, 5); frame 1, drifted (1, 1, 1) onto, t (0, 0, 0), p (0, 2, 2), s (1, 1, 1), q (2, 0, 2) and r (2, 2, 0); frame
// 2, drifted (-1, -1, -1) onto, c (1, 1, 0), w (2, 2, 5), x (2, 3, 4), v (2, 4, 2) and u (3, 2, 2); frame 3, drifted
// (0, 0, 1) onto, e (0, 0, 0) and c' (1, 1, 3). a links to t and c to c'; p to u is in the gate and not chosen. So p,
// q and r start predicted back to -1 on z, y and x and enter, s to 0 on each and does not, and t, predicted back past
// three low faces, has its link in and is no start; u, v and w start predicted back to the extent on z, y and x and
// enter, and x to the extent less 1 on each and does not; c starts carried back by its link's motion too, past x's low
// face, which without the motion it would not cross, and enters; e starts past x's low face at the last frame and
// enters. b, p, q, w, x, v and u end with their predictions past a face and leave; r ends predicted at 0 on x, s at
// the extent less 1 on each, t inside, and none leaves; c's prediction lies past a face, but it has its link out and
// does not end. a's and b's .shape faces ride at bit 24. still is 1 frame in a 1 x 2 x 3 view, its two points first
// and last at once, one with all six .shape faces; empty is a sample of no frames. The three run as one set and the
// report is checked against the hand's counts. Then each of thirteen broken samples, alone in its set, errors and
// leaves no .faces, a stale one taken away: a back-prediction past 32 bits, an outside flag on a prediction inside the
// view, a .drift of other frames, a .drift with a word past its last frame, a .shape of the wrong limbs, a .shape
// counting other points, a .shape face past the six, no .shape, a .links of another view, two chosen links out of one
// point, a pair record whose chosen count is not its gate's, a .links cut short (each a copy of walk), and a view past
// 2^31 - 1 voxels; and beside a good still, which writes, the first of them makes the set error. Malformed requests
// error. The test is host work and asks nothing of the device.
//
// The test links no engine_*.cu. Engine_sample_path below restates engine/engine_*.cu's; and the formats are written
// here by hand from faces.h, scan.cu, hessian.h and sort.h: a change to any must be made here too. The CRC-64 the
// .faces carries is taken a bit at a time here, apart from cu/includes/codecs/crc/crc.h's table, which faces_find.cu takes
// it by.
#include "faces.h"
#include "scan.h"
#include "sort.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define FACES_TEST_MKDIR(path_) _mkdir(path_)
#else
#include <sys/stat.h>
#define FACES_TEST_MKDIR(path_) mkdir((path_), 0755)
#endif

#define FACES_TEST_WORDS 1024u

#define FACES_TEST_FRAMES 4u

#define FACES_TEST_POINTS 16u

#define FACES_TEST_TEXT 4096u

// the test links no engine_*.cu: the engine's sample path, restated as cu/engine/engine_files.cu's engine_sample_path
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
} FacesTestResults;

static void faces_test_check(FacesTestResults *results, int passed, const char *what)
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
    unsigned int words[FACES_TEST_WORDS];
    unsigned int count;
} FacesTestWords;

static void faces_test_put(FacesTestWords *words, unsigned int word)
{
    if (words->count < FACES_TEST_WORDS)
    {
        words->words[words->count] = word;
    }
    words->count += 1u;
}

// how a copy of walk is broken, or none
typedef enum
{
    FACES_FLAW_NONE = 0,
    FACES_FLAW_PAST_32,
    FACES_FLAW_OUTSIDE,
    FACES_FLAW_DRIFT_FRAMES,
    FACES_FLAW_DRIFT_TRAILING,
    FACES_FLAW_HESSIAN_LIMBS,
    FACES_FLAW_HESSIAN_COUNT,
    FACES_FLAW_HESSIAN_SIX,
    FACES_FLAW_HESSIAN_MISSING,
    FACES_FLAW_LINKS_VIEW,
    FACES_FLAW_TWO_OUT,
    FACES_FLAW_CHOSEN,
    FACES_FLAW_LINKS_SHORT,
    FACES_FLAW_VAST,
    FACES_FLAWS
} FacesFlaw;

static const char *const FACES_FLAW_NAMES[FACES_FLAWS] = {
    "walk",      "past_32",       "outside",    "drift_frames", "drift_trailing", "shape_limbs", "shape_count",
    "shape_six", "shape_missing", "links_view", "two_out",      "chosen",         "links_short", "vast"};

// a sample as the test writes it: its frames in a view, each frame's points (their voxels in order), each point's
// .shape faces, the lag onto each frame after the first, each point's prediction (z, y, x, flags; the last frame's
// unwritten), and the gate pairs, each (frame, source, target, chosen), the source and target their frames' indices
typedef struct
{
    unsigned int frames;
    unsigned int view[3];
    unsigned int limbs;
    unsigned int counts[FACES_TEST_FRAMES];
    unsigned int voxels[FACES_TEST_POINTS];
    unsigned int hessian[FACES_TEST_POINTS];
    int lags[FACES_TEST_FRAMES][3];
    int predictions[FACES_TEST_POINTS][3];
    unsigned int outside[FACES_TEST_POINTS];
    unsigned int gates[4][4];
    unsigned int gate_count;
} FacesTestSample;

static int faces_test_join(char *path, size_t capacity, const char *one, const char *two)
{
    const int written = snprintf(path, capacity, "%s/%s", one, two);
    return (written > 0) && ((size_t)written < capacity);
}

static int faces_test_directory(const char *set, const char *sample)
{
    char path[ENGINE_PATH_CAPACITY];
    (void)FACES_TEST_MKDIR(set);
    if (faces_test_join(path, sizeof(path), set, sample) == 0)
    {
        return 0;
    }
    (void)FACES_TEST_MKDIR(path);
    return 1;
}

static int faces_test_write(const char *set, const char *sample, const char *suffix, const FacesTestWords *words)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, suffix) ? fopen(path, "wb") : NULL;
    const int written = (file != NULL) && (words->count <= FACES_TEST_WORDS) &&
                        (fwrite(words->words, sizeof(unsigned int), words->count, file) == words->count);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

// the .points: its head (frames, the view, limbs, bits 34), the readings and C, 0 here, which the part passes over,
// then each frame's count, voxels and levels, each level `limbs` words of 0xA5A5A5A5
static int faces_test_points(const char *set, const char *sample, const FacesTestSample *walk)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".points") ? fopen(path, "wb") : NULL;
    const unsigned int head[6] = {walk->frames, walk->view[0], walk->view[1], walk->view[2], walk->limbs, 34u};
    int ok = (file != NULL) && (fwrite(head, sizeof(unsigned int), 6u, file) == 6u);
    const unsigned long long zero = 0ull;
    for (unsigned int at = 0u; ok && (at < (1u + SCAN_READINGS)); at += 1u)
    {
        ok = fwrite(&zero, sizeof(zero), 1u, file) == 1u;
    }
    const unsigned int level = 0xA5A5A5A5u;
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; ok && (frame < walk->frames); frame += 1u)
    {
        ok = (fwrite(&walk->counts[frame], sizeof(unsigned int), 1u, file) == 1u) &&
             (fwrite(&walk->voxels[taken], sizeof(unsigned int), walk->counts[frame], file) == walk->counts[frame]);
        for (unsigned int at = 0u; ok && (at < (walk->counts[frame] * walk->limbs)); at += 1u)
        {
            ok = fwrite(&level, sizeof(level), 1u, file) == 1u;
        }
        taken += walk->counts[frame];
    }
    const int closed = (file != NULL) && (fclose(file) == 0);
    return ok && closed;
}

// the .drift: frames, the view and the weights 16, 1, 1, then each frame's positives (its points here) and after frame
// 0 its lag and an agreement of 1
static int faces_test_drift(const char *set, const char *sample, const FacesTestSample *walk, FacesFlaw flaw)
{
    FacesTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[7] = {(flaw == FACES_FLAW_DRIFT_FRAMES) ? (walk->frames - 1u) : walk->frames,
                                  walk->view[0],
                                  walk->view[1],
                                  walk->view[2],
                                  16u,
                                  1u,
                                  1u};
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        faces_test_put(&words, head[at]);
    }
    for (unsigned int frame = 0u; frame < walk->frames; frame += 1u)
    {
        faces_test_put(&words, walk->counts[frame]);
        for (unsigned int axis = 0u; (frame > 0u) && (axis < 3u); axis += 1u)
        {
            // a lag is written as its two's complement word
            faces_test_put(&words, (unsigned int)walk->lags[frame][axis]);
        }
        if (frame > 0u)
        {
            faces_test_put(&words, 1u);
        }
    }
    if (flaw == FACES_FLAW_DRIFT_TRAILING)
    {
        faces_test_put(&words, 0u);
    }
    return faces_test_write(set, sample, ".drift", &words);
}

// the .shape: frames, the view, the limbs and one more, then each frame's count, each point's faces, and each point's
// six differences of limbs + 1 words, each 0x5A5A5A5A
static int faces_test_hessian(const char *set, const char *sample, const FacesTestSample *walk, FacesFlaw flaw)
{
    FacesTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[6] = {walk->frames,  walk->view[0],
                                  walk->view[1], walk->view[2],
                                  walk->limbs,   (flaw == FACES_FLAW_HESSIAN_LIMBS) ? walk->limbs : (walk->limbs + 1u)};
    for (unsigned int at = 0u; at < 6u; at += 1u)
    {
        faces_test_put(&words, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; frame < walk->frames; frame += 1u)
    {
        const unsigned int count = walk->counts[frame];
        faces_test_put(&words, ((flaw == FACES_FLAW_HESSIAN_COUNT) && (frame == 1u)) ? (count - 1u) : count);
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            faces_test_put(
                &words, ((flaw == FACES_FLAW_HESSIAN_SIX) && ((taken + at) == 0u)) ? 0x40u : walk->hessian[taken + at]);
        }
        for (unsigned int at = 0u; at < (count * HESSIAN_ENTRIES * (walk->limbs + 1u)); at += 1u)
        {
            faces_test_put(&words, 0x5A5A5A5Au);
        }
        taken += count;
    }
    return (flaw == FACES_FLAW_HESSIAN_MISSING) || faces_test_write(set, sample, ".shape", &words);
}

// the .links: its head, then each frame pair's record (sources, targets, gate pairs, components one a gate pair,
// chosen, and kept, level and crossed 0, which the part does not read), each source's prediction and flags, and each
// gate pair (source, target, cost 1, weight 1, component 0, flags)
static int faces_test_links(const char *set, const char *sample, const FacesTestSample *walk, FacesFlaw flaw)
{
    FacesTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[SORT_HEADER_WORDS] = {walk->frames,
                                                  walk->view[0],
                                                  walk->view[1],
                                                  (flaw == FACES_FLAW_LINKS_VIEW) ? (walk->view[2] + 1u)
                                                                                  : walk->view[2],
                                                  16u,
                                                  1u,
                                                  1u,
                                                  SORT_TERMS};
    for (unsigned int at = 0u; at < SORT_HEADER_WORDS; at += 1u)
    {
        faces_test_put(&words, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; (frame + 1u) < walk->frames; frame += 1u)
    {
        unsigned int gates = 0u;
        unsigned int chosen = 0u;
        for (unsigned int at = 0u; at < walk->gate_count; at += 1u)
        {
            gates += (walk->gates[at][0] == frame) ? 1u : 0u;
            chosen += ((walk->gates[at][0] == frame) && (walk->gates[at][3] != 0u)) ? 1u : 0u;
        }
        // two out: a to p chosen too, beside a to t
        const unsigned int doubled = ((flaw == FACES_FLAW_TWO_OUT) && (frame == 0u)) ? 1u : 0u;
        const unsigned int told = ((flaw == FACES_FLAW_CHOSEN) && (frame == 0u)) ? 1u : 0u;
        const unsigned int record[SORT_PAIR_WORDS] = {walk->counts[frame],
                                                      walk->counts[frame + 1u],
                                                      gates + doubled,
                                                      gates + doubled,
                                                      chosen + doubled + told,
                                                      0u,
                                                      0u,
                                                      0u,
                                                      0u,
                                                      0u,
                                                      0u};
        for (unsigned int at = 0u; at < SORT_PAIR_WORDS; at += 1u)
        {
            faces_test_put(&words, record[at]);
        }
        for (unsigned int at = 0u; at < walk->counts[frame]; at += 1u)
        {
            const unsigned int point = taken + at;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                // a prediction is written as its two's complement word
                faces_test_put(&words, (unsigned int)walk->predictions[point][axis]);
            }
            // outside: s's prediction, inside the view, flagged outside
            const unsigned int astray = ((flaw == FACES_FLAW_OUTSIDE) && (point == 4u)) ? SORT_SOURCE_OUTSIDE : 0u;
            faces_test_put(&words, (walk->outside[point] ? SORT_SOURCE_OUTSIDE : 0u) | astray);
        }
        for (unsigned int at = 0u; at < walk->gate_count; at += 1u)
        {
            if (walk->gates[at][0] != frame)
            {
                continue;
            }
            const unsigned int gate[SORT_GATE_WORDS] = {walk->gates[at][1],
                                                        walk->gates[at][2],
                                                        1u,
                                                        0u,
                                                        1u,
                                                        0u,
                                                        SORT_GATE_FORWARD |
                                                            ((walk->gates[at][3] != 0u) ? SORT_GATE_CHOSEN : 0u)};
            for (unsigned int word = 0u; word < SORT_GATE_WORDS; word += 1u)
            {
                faces_test_put(&words, gate[word]);
            }
        }
        if (doubled != 0u)
        {
            const unsigned int gate[SORT_GATE_WORDS] = {0u, 1u, 1u, 0u, 1u, 0u, SORT_GATE_FORWARD | SORT_GATE_CHOSEN};
            for (unsigned int word = 0u; word < SORT_GATE_WORDS; word += 1u)
            {
                faces_test_put(&words, gate[word]);
            }
        }
        taken += walk->counts[frame];
    }
    words.count -= ((flaw == FACES_FLAW_LINKS_SHORT) && (words.count > 0u)) ? 1u : 0u;
    return faces_test_write(set, sample, ".links", &words);
}

// walk as worked in the head comment; past_32 drifts frame 1 by -2^31 on z, which carries t back to 2^31
static void faces_test_walk(FacesTestSample *walk, FacesFlaw flaw)
{
    memset(walk, 0, sizeof(*walk));
    walk->frames = 4u;
    walk->view[0] = 4u;
    walk->view[1] = 5u;
    walk->view[2] = 6u;
    walk->limbs = 1u;
    const unsigned int counts[4] = {2u, 5u, 5u, 2u};
    memcpy(walk->counts, counts, sizeof(counts));
    // a, b; t, p, s, q, r; c, w, x, v, u; e, c'
    const unsigned int voxels[14] = {0u, 119u, 0u, 14u, 37u, 62u, 72u, 36u, 77u, 82u, 86u, 104u, 0u, 39u};
    memcpy(walk->voxels, voxels, sizeof(voxels));
    walk->hessian[0] = HESSIAN_FACE_Z_LOW | HESSIAN_FACE_Y_LOW | HESSIAN_FACE_X_LOW;
    walk->hessian[1] = HESSIAN_FACE_Z_HIGH | HESSIAN_FACE_Y_HIGH | HESSIAN_FACE_X_HIGH;
    const int lags[4][3] = {{0, 0, 0}, {1, 1, 1}, {-1, -1, -1}, {0, 0, 1}};
    memcpy(walk->lags, lags, sizeof(lags));
    if (flaw == FACES_FLAW_PAST_32)
    {
        walk->lags[1][0] = -2147483647 - 1;
    }
    const int predictions[12][3] = {{0, 0, 0}, {3, 4, 6},  {0, 0, 0}, {-1, 2, 2}, {3, 4, 5},  {2, 5, 2},
                                    {2, 2, 0}, {-1, 1, 3}, {2, 2, 6}, {2, 3, -1}, {2, -1, 2}, {4, 2, 2}};
    memcpy(walk->predictions, predictions, sizeof(predictions));
    const unsigned int outside[12] = {0u, 1u, 0u, 1u, 0u, 1u, 0u, 1u, 1u, 1u, 1u, 1u};
    memcpy(walk->outside, outside, sizeof(outside));
    // a to t chosen; p to u in the gate, not chosen; c to c' chosen
    const unsigned int gates[3][4] = {{0u, 0u, 0u, 1u}, {1u, 1u, 4u, 0u}, {2u, 0u, 1u, 1u}};
    memcpy(walk->gates, gates, sizeof(gates));
    walk->gate_count = 3u;
}

// still: 1 frame in a 1 x 2 x 3 view, voxels 0 and 5, the first with all six .shape faces
static void faces_test_still(FacesTestSample *still)
{
    memset(still, 0, sizeof(*still));
    still->frames = 1u;
    still->view[0] = 1u;
    still->view[1] = 2u;
    still->view[2] = 3u;
    still->limbs = 0u;
    still->counts[0] = 2u;
    still->voxels[1] = 5u;
    still->hessian[0] = FACES_SIX;
}

// empty: no frames, in walk's view
static void faces_test_empty(FacesTestSample *empty)
{
    memset(empty, 0, sizeof(*empty));
    empty->view[0] = 4u;
    empty->view[1] = 5u;
    empty->view[2] = 6u;
    empty->limbs = 1u;
}

// vast: no frames, in a view of 2048 x 1024 x 1024, 2^31 voxels
static void faces_test_vast(FacesTestSample *vast)
{
    memset(vast, 0, sizeof(*vast));
    vast->view[0] = 2048u;
    vast->view[1] = 1024u;
    vast->view[2] = 1024u;
    vast->limbs = 1u;
}

static int faces_test_sample(const char *set, const char *sample, const FacesTestSample *walk, FacesFlaw flaw)
{
    return faces_test_directory(set, sample) && faces_test_points(set, sample, walk) &&
           faces_test_drift(set, sample, walk, flaw) && faces_test_hessian(set, sample, walk, flaw) &&
           faces_test_links(set, sample, walk, flaw);
}

// CRC-64/XZ a bit at a time from its reflected polynomial, restated apart from cu/includes/codecs/crc/crc.h's table, over
// the whole file; 0 when it does not read
static int faces_test_crc(const char *path, unsigned long long *crc)
{
    FILE *const file = fopen(path, "rb");
    unsigned long long running = ~0ull;
    int byte = (file != NULL) ? fgetc(file) : EOF;
    while (byte != EOF)
    {
        running ^= (unsigned long long)byte;
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            running = ((running & 1ull) != 0ull) ? ((running >> 1u) ^ 0xC96C5795D7870F42ull) : (running >> 1u);
        }
        byte = fgetc(file);
    }
    const int complete = (file != NULL) && (ferror(file) == 0);
    if (file != NULL)
    {
        fclose(file);
    }
    *crc = ~running;
    return complete;
}

// the sample's .faces held word by word against its head (the view and the CRC-64 of its .links) and `points`, four
// words a point, frame by frame
static int faces_test_matches(const char *set, const char *sample, const FacesTestSample *walk,
                              const unsigned int *points)
{
    char path[ENGINE_PATH_CAPACITY];
    unsigned long long crc = 0ull;
    if ((engine_sample_path(path, sizeof(path), set, sample, ".links") == 0) || (faces_test_crc(path, &crc) == 0))
    {
        return 0;
    }
    FacesTestWords want;
    memset(&want, 0, sizeof(want));
    const unsigned int head[FACES_HEADER_WORDS] = {walk->frames,
                                                   walk->view[0],
                                                   walk->view[1],
                                                   walk->view[2],
                                                   (unsigned int)(crc & 0xFFFFFFFFull),
                                                   (unsigned int)(crc >> 32u)};
    for (unsigned int at = 0u; at < FACES_HEADER_WORDS; at += 1u)
    {
        faces_test_put(&want, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; frame < walk->frames; frame += 1u)
    {
        faces_test_put(&want, walk->counts[frame]);
        for (unsigned int at = 0u; at < (FACES_POINT_WORDS * walk->counts[frame]); at += 1u)
        {
            faces_test_put(&want, points[taken + at]);
        }
        taken += FACES_POINT_WORDS * walk->counts[frame];
    }
    FacesTestWords read;
    memset(&read, 0, sizeof(read));
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".faces") ? fopen(path, "rb") : NULL;
    read.count = (file != NULL) ? (unsigned int)fread(read.words, sizeof(unsigned int), FACES_TEST_WORDS, file) : 0u;
    if (file != NULL)
    {
        fclose(file);
    }
    int same = (file != NULL) && (read.count == want.count);
    for (unsigned int at = 0u; same && (at < want.count); at += 1u)
    {
        same = read.words[at] == want.words[at];
        if (same == 0)
        {
            printf("  %s's .faces word %u reads %08X, and the hand's is %08X\n", sample, at, read.words[at],
                   want.words[at]);
        }
    }
    if ((file != NULL) && (read.count != want.count))
    {
        printf("  %s's .faces holds %u words, and the hand's %u\n", sample, read.count, want.count);
    }
    return same;
}

static int faces_test_exists(const char *set, const char *sample)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".faces") ? fopen(path, "rb") : NULL;
    if (file != NULL)
    {
        fclose(file);
    }
    return file != NULL;
}

// a .faces an earlier run left, which an error must take away
static int faces_test_stale(const char *set, const char *sample)
{
    FacesTestWords words;
    memset(&words, 0, sizeof(words));
    faces_test_put(&words, 0x57A1Eu);
    return faces_test_write(set, sample, ".faces", &words);
}

// the whole report file into `text`; 0 when it does not read
static int faces_test_text(const char *path, char *text, size_t capacity)
{
    FILE *const file = fopen(path, "rb");
    const size_t read = (file != NULL) ? fread(text, 1u, capacity - 1u, file) : 0u;
    text[read] = '\0';
    if (file != NULL)
    {
        fclose(file);
    }
    return file != NULL;
}

// walk's words, frame by frame: each point's back-prediction and flags
static const unsigned int FACES_TEST_WALK[56] = {
    // frame 0: a first, its .shape's three low faces; b first, left past x's high face, its three high faces
    0u, 0u, 0u, 0x15000004u, 3u, 4u, 5u, 0x2A200006u,
    // frame 1: t back past three low faces, linked in; p entered past z's low face and left past it; s neither; q
    // entered past y's low face, left past y's high; r entered past x's low face, predicted at 0 on x
    0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0x00001500u, 0xFFFFFFFFu, 1u, 1u, 0x00010103u, 0u, 0u, 0u, 0x00000000u, 1u,
    0xFFFFFFFFu, 1u, 0x00080403u, 1u, 1u, 0xFFFFFFFFu, 0x00001001u,
    // frame 2: c carried back by its link past x's low face and entered, its prediction past z's low face and no end;
    // w entered past x's high face, left past it; x at the extent less 1, left past x's low face; v entered past y's
    // high face, left past y's low; u entered past z's high face, left past it
    2u, 2u, 0xFFFFFFFFu, 0x00011011u, 3u, 3u, 6u, 0x00202003u, 3u, 4u, 5u, 0x00100002u, 3u, 5u, 3u, 0x00040803u, 4u, 3u,
    3u, 0x00020203u,
    // frame 3: e last, entered past x's low face; c' last, linked in
    0u, 0u, 0xFFFFFFFFu, 0x00001009u, 1u, 1u, 2u, 0x00000008u};

// still's words: both first and last, the first with all six .shape faces
static const unsigned int FACES_TEST_STILL[8] = {0u, 0u, 0u, 0x3F00000Cu, 0u, 1u, 2u, 0x0000000Cu};

static void faces_test_ok(FacesTestResults *results, const char *root)
{
    char set[ENGINE_PATH_CAPACITY];
    char report_path[ENGINE_PATH_CAPACITY];
    FacesTestSample walk;
    FacesTestSample still;
    FacesTestSample empty;
    faces_test_walk(&walk, FACES_FLAW_NONE);
    faces_test_still(&still);
    faces_test_empty(&empty);
    const int written = faces_test_join(set, sizeof(set), root, "good") &&
                        faces_test_sample(set, "walk", &walk, FACES_FLAW_NONE) &&
                        faces_test_sample(set, "still", &still, FACES_FLAW_NONE) &&
                        faces_test_sample(set, "empty", &empty, FACES_FLAW_NONE) &&
                        faces_test_join(report_path, sizeof(report_path), set, "report.txt");
    faces_test_check(results, written, "the good set was written");
    if (written == 0)
    {
        return;
    }
    char walk_name[] = "walk";
    char still_name[] = "still";
    char empty_name[] = "empty";
    char *const samples[3] = {walk_name, still_name, empty_name};
    FILE *const report = fopen(report_path, "wb");
    FacesRequest request = {set, samples, 3u, report};
    const long result = (report != NULL) ? faces_find_set(&request) : FACES_ERROR;
    const int closed = (report != NULL) && (fclose(report) == 0);
    printf("  the good set: faces_find_set returned %ld\n", result);
    faces_test_check(results, (result == 0L) && closed, "the good set writes");
    faces_test_check(results, faces_test_matches(set, "walk", &walk, FACES_TEST_WALK), "walk's .faces is the hand's");
    faces_test_check(results, faces_test_matches(set, "still", &still, FACES_TEST_STILL),
                     "still's .faces is the hand's");
    faces_test_check(results, faces_test_matches(set, "empty", &empty, NULL), "empty's .faces is its head alone");
    // the report as the hand counts it: walk's 10 starts, 8 entering, 10 ends, 7 leaving, 2 first, 2 last, 1 carried
    char want[FACES_TEST_TEXT];
    char text[FACES_TEST_TEXT];
    int length = snprintf(want, sizeof(want), "  %-24s %6s %10s %s\n", "sample", "frames", "points",
                          "starts (entering the view), ends (leaving it); first frame, last frame; carried back");
    const unsigned long long rows[3][9] = {{4ull, 14ull, 10ull, 8ull, 10ull, 7ull, 2ull, 2ull, 1ull},
                                           {1ull, 2ull, 0ull, 0ull, 0ull, 0ull, 2ull, 2ull, 0ull},
                                           {0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull}};
    for (unsigned int at = 0u; (length > 0) && (at < 3u); at += 1u)
    {
        const int more = snprintf(&want[length], sizeof(want) - (size_t)length,
                                  "  %-24s %6llu %10llu %llu (%llu), %llu (%llu); %llu, %llu; %llu\n", samples[at],
                                  rows[at][0], rows[at][1], rows[at][2], rows[at][3], rows[at][4], rows[at][5],
                                  rows[at][6], rows[at][7], rows[at][8]);
        length = (more > 0) ? (length + more) : -1;
    }
    if (length > 0)
    {
        (void)snprintf(&want[length], sizeof(want) - (size_t)length,
                       "  faces on 3 of 3 samples: 5 frames, 16 points; 10 starts, 8 of them entering the view; 10"
                       " ends, 7 of them leaving it; 4 points in the first frames, 4 in the last; 1 back-predictions"
                       " carried by a link's motion\n");
    }
    const int same = faces_test_text(report_path, text, sizeof(text)) && (strcmp(text, want) == 0);
    if (same == 0)
    {
        printf("  the report reads:\n%s  and the hand's is:\n%s", text, want);
    }
    faces_test_check(results, same, "the report is the hand's");
    printf("%s", text);
}

// each broken copy of walk alone in its set, a stale .faces beside it: the set errors and no .faces is left
static void faces_test_errors(FacesTestResults *results, const char *root)
{
    for (unsigned int flaw = 1u; flaw < (unsigned int)FACES_FLAWS; flaw += 1u)
    {
        char set[ENGINE_PATH_CAPACITY];
        char name[128];
        char report_path[ENGINE_PATH_CAPACITY];
        snprintf(name, sizeof(name), "error_%s", FACES_FLAW_NAMES[flaw]);
        FacesTestSample walk;
        if (flaw == (unsigned int)FACES_FLAW_VAST)
        {
            faces_test_vast(&walk);
        }
        else
        {
            faces_test_walk(&walk, (FacesFlaw)flaw);
        }
        const int written = faces_test_join(set, sizeof(set), root, name) &&
                            faces_test_sample(set, "walk", &walk, (FacesFlaw)flaw) && faces_test_stale(set, "walk") &&
                            faces_test_join(report_path, sizeof(report_path), set, "report.txt");
        char what[256];
        snprintf(what, sizeof(what), "%s was written", name);
        faces_test_check(results, written, what);
        if (written == 0)
        {
            continue;
        }
        char walk_name[] = "walk";
        char *const samples[1] = {walk_name};
        FILE *const report = fopen(report_path, "wb");
        FacesRequest request = {set, samples, 1u, report};
        printf("  %s:\n", name);
        fflush(stdout);
        const long result = (report != NULL) ? faces_find_set(&request) : 0L;
        if (report != NULL)
        {
            fclose(report);
        }
        fflush(stderr);
        snprintf(what, sizeof(what), "%s errors", name);
        faces_test_check(results, result == FACES_ERROR, what);
        snprintf(what, sizeof(what), "%s leaves no .faces", name);
        faces_test_check(results, faces_test_exists(set, "walk") == 0, what);
    }
}

// a set of the past_32 walk and a good still: still writes, walk leaves none, and the set errors
static void faces_test_mixed(FacesTestResults *results, const char *root)
{
    char set[ENGINE_PATH_CAPACITY];
    char report_path[ENGINE_PATH_CAPACITY];
    FacesTestSample walk;
    FacesTestSample still;
    faces_test_walk(&walk, FACES_FLAW_PAST_32);
    faces_test_still(&still);
    const int written = faces_test_join(set, sizeof(set), root, "mixed") &&
                        faces_test_sample(set, "walk", &walk, FACES_FLAW_PAST_32) &&
                        faces_test_sample(set, "still", &still, FACES_FLAW_NONE) &&
                        faces_test_join(report_path, sizeof(report_path), set, "report.txt");
    faces_test_check(results, written, "the mixed set was written");
    if (written == 0)
    {
        return;
    }
    char walk_name[] = "walk";
    char still_name[] = "still";
    char *const samples[2] = {walk_name, still_name};
    FILE *const report = fopen(report_path, "wb");
    FacesRequest request = {set, samples, 2u, report};
    printf("  mixed:\n");
    fflush(stdout);
    const long result = (report != NULL) ? faces_find_set(&request) : 0L;
    if (report != NULL)
    {
        fclose(report);
    }
    fflush(stderr);
    char text[FACES_TEST_TEXT];
    faces_test_check(results, result == FACES_ERROR, "the mixed set errors");
    faces_test_check(results, faces_test_exists(set, "walk") == 0, "the mixed set's walk leaves no .faces");
    faces_test_check(results, faces_test_matches(set, "still", &still, FACES_TEST_STILL),
                     "the mixed set's still writes the hand's .faces");
    faces_test_check(results,
                     faces_test_text(report_path, text, sizeof(text)) &&
                         (strstr(text, "  faces on 1 of 2 samples: 1 frames, 2 points;") != NULL),
                     "the mixed set's report counts 1 of 2 samples");
    printf("%s", text);
}

static void faces_test_requests(FacesTestResults *results, const char *root)
{
    char name[] = "walk";
    char *const samples[1] = {name};
    const FacesRequest no_set = {NULL, samples, 1u, stdout};
    const FacesRequest no_samples = {root, NULL, 1u, stdout};
    const FacesRequest none = {root, samples, 0u, stdout};
    const FacesRequest no_report = {root, samples, 1u, NULL};
    faces_test_check(results, faces_find_set(NULL) == FACES_ERROR, "no request errors");
    faces_test_check(results, faces_find_set(&no_set) == FACES_ERROR, "a request with no set errors");
    faces_test_check(results, faces_find_set(&no_samples) == FACES_ERROR, "a request with no samples errors");
    faces_test_check(results, faces_find_set(&none) == FACES_ERROR, "a request of 0 samples errors");
    faces_test_check(results, faces_find_set(&no_report) == FACES_ERROR, "a request with no report errors");
}

int main(int count, char **arguments)
{
    if (count != 2)
    {
        printf("  usage: faces_test <directory>\n");
        return 2;
    }
    (void)FACES_TEST_MKDIR(arguments[1]);
    FacesTestResults results = {0u, 0u};
    faces_test_ok(&results, arguments[1]);
    faces_test_errors(&results, arguments[1]);
    faces_test_mixed(&results, arguments[1]);
    faces_test_requests(&results, arguments[1]);
    printf("  faces test: %u checks, %u failed\n", results.checks, results.failures);
    return (results.failures == 0u) ? 0 : 1;
}
