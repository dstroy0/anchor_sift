// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "codecs/crc/crc.h"
#include "divide.h"
#include "faces.h"
#include "output.h"
#include "scan.h"
#include "sort.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define OUTPUT_SEEK _fseeki64
#define OUTPUT_TELL _ftelli64
#else
#define OUTPUT_SEEK fseeko
#define OUTPUT_TELL ftello
#endif

// .points opens with frames, depth, height, width, the residual's limbs and the contrast's bits, then the set's
// readings and its cumulative count; a frame is its count, each point's voxel, then each point's levels
#define OUTPUT_POINTS_HEADER_WORDS 6u

// a pair's source records and gate records are read this many at a time
#define OUTPUT_CHUNK 65536u

#define OUTPUT_NONE 0xFFFFFFFFu

#ifdef OUTPUT_TEST_FAULTS
unsigned long long output_test_skew = 0ull;
void (*output_test_between)(const OutputRequest *request) = NULL;
#endif

// a sample's graph as S11 reads it: each frame's first point among the sample's points, and for each point its voxel,
// the chosen link out of it (its target's index in the next frame) with that link's cost, the second link out of it
// when it is a division's parent (daughter two's index), the link into it (its source's index in the frame before),
// whether its prediction lies outside the view, and its .faces flags (0 with no .faces)
typedef struct
{
    unsigned int frames;
    unsigned int view[ENGINE_AXES];
    unsigned long long points;
    unsigned long long *first;
    size_t first_capacity;
    size_t capacity;
    unsigned int *voxels;
    unsigned int *forward;
    unsigned int *second;
    unsigned int *backward;
    unsigned long long *departure;
    unsigned char *outside;
    unsigned int *faces;
} OutputGraph;

// what O20 and H4 count on a sample. The ends are the points before the last frame with no link out, `outside` those of
// them whose prediction lies outside the view; the starts are the points after the first frame with no link in. With
// no lysis (S8) yet, no end is explained but by the view's faces, and with no .faces (S9) none is. `faces` is 1 when
// the sample's .faces was read, `leaving` its ends whose prediction crosses a face, `entering` its starts whose
// back-prediction does, and `first` and `last` the points of its first and last frames, which start and end with the
// movie. `divide` is 1 when the sample's .divide was read, `divisions` its divisions and `moved` those that took
// daughter two from another point's link; daughter two is no start, since the division gives it its link in. The
// fingerprint is a CRC-64 of what the sample's rows are written from (output_graph_fingerprint)
typedef struct
{
    unsigned long long frames;
    unsigned long long nodes;
    unsigned long long edges;
    unsigned long long ends;
    unsigned long long outside;
    unsigned long long ends_max;
    unsigned long long starts;
    unsigned long long starts_max;
    unsigned long long pairs;
    unsigned long long balanced;
    unsigned long long faces;
    unsigned long long leaving;
    unsigned long long entering;
    unsigned long long first;
    unsigned long long last;
    unsigned long long divide;
    unsigned long long divisions;
    unsigned long long moved;
    unsigned long long fingerprint;
} OutputResults;

// the CRC-64 of a sample's .links, taken once for its .faces and its .divide: `summed` once taken, `complete` when the
// file read whole
typedef struct
{
    int summed;
    int complete;
    unsigned long long value;
} OutputLinksCrc;

static int output_read(FILE *file, void *words, size_t bytes)
{
    return (bytes == 0u) || (fread(words, 1u, bytes, file) == bytes);
}

// a skip past 2^63 - 1 bytes is no file this reads
static int output_skip(FILE *file, unsigned long long bytes)
{
    return (bytes <= 0x7FFFFFFFFFFFFFFFull) && (OUTPUT_SEEK(file, (long long)bytes, SEEK_CUR) == 0);
}

// `count` points of `words` 32-bit words each, in bytes, or all ones when that passes 2^63 - 1
static unsigned long long output_frame_bytes(unsigned long long count, unsigned long long words)
{
    return ((count != 0ull) && (words > ((0x7FFFFFFFFFFFFFFFull / 4ull) / count))) ? ~0ull : (count * words * 4ull);
}

// the file's place is its end: every frame read whole, and nothing past the last
static int output_at_end(FILE *file)
{
    const long long place = OUTPUT_TELL(file);
    const int ended = (place >= 0ll) && (OUTPUT_SEEK(file, 0ll, SEEK_END) == 0);
    return ended && (OUTPUT_TELL(file) == place);
}

// the voxels of the view, or 2^32 when there are more: every 32-bit voxel lies below that
static unsigned long long output_view_voxels(const unsigned int view[ENGINE_AXES])
{
    const unsigned long long plane = (unsigned long long)view[1] * view[2];
    return ((plane != 0ull) && (view[0] > (0x100000000ull / plane))) ? 0x100000000ull : (view[0] * plane);
}

static int output_first_reserve(OutputGraph *graph, unsigned int frames)
{
    const size_t wanted = (size_t)frames + 1u;
    if ((wanted <= graph->first_capacity) && (graph->first != NULL))
    {
        return 1;
    }
    unsigned long long *const first = (unsigned long long *)realloc(graph->first, wanted * sizeof(unsigned long long));
    graph->first = (first != NULL) ? first : graph->first;
    graph->first_capacity = (first != NULL) ? wanted : graph->first_capacity;
    return first != NULL;
}

static int output_points_reserve(OutputGraph *graph, unsigned long long needed)
{
    if ((needed <= graph->capacity) && (graph->voxels != NULL))
    {
        return 1;
    }
    const unsigned long long doubled = 2ull * (unsigned long long)graph->capacity;
    const unsigned long long wanted = ((doubled > needed) ? doubled : needed) + 1ull;
    // a capacity whose widest array passes what a size_t counts errors here
    if (wanted > (SIZE_MAX / sizeof(unsigned long long)))
    {
        return 0;
    }
    const size_t capacity = (size_t)wanted;
    unsigned int *const voxels = (unsigned int *)realloc(graph->voxels, capacity * sizeof(unsigned int));
    graph->voxels = (voxels != NULL) ? voxels : graph->voxels;
    unsigned int *const forward = (unsigned int *)realloc(graph->forward, capacity * sizeof(unsigned int));
    graph->forward = (forward != NULL) ? forward : graph->forward;
    unsigned int *const second = (unsigned int *)realloc(graph->second, capacity * sizeof(unsigned int));
    graph->second = (second != NULL) ? second : graph->second;
    unsigned int *const backward = (unsigned int *)realloc(graph->backward, capacity * sizeof(unsigned int));
    graph->backward = (backward != NULL) ? backward : graph->backward;
    unsigned long long *const departure =
        (unsigned long long *)realloc(graph->departure, capacity * sizeof(unsigned long long));
    graph->departure = (departure != NULL) ? departure : graph->departure;
    unsigned char *const outside = (unsigned char *)realloc(graph->outside, capacity);
    graph->outside = (outside != NULL) ? outside : graph->outside;
    unsigned int *const faces = (unsigned int *)realloc(graph->faces, capacity * sizeof(unsigned int));
    graph->faces = (faces != NULL) ? faces : graph->faces;
    const int ok = (voxels != NULL) && (forward != NULL) && (second != NULL) && (backward != NULL) &&
                   (departure != NULL) && (outside != NULL) && (faces != NULL);
    // a grow that failed part way leaves every array at least as long as the capacity it had
    graph->capacity = ok ? capacity : graph->capacity;
    return ok;
}

static void output_graph_free(OutputGraph *graph)
{
    free(graph->first);
    free(graph->voxels);
    free(graph->forward);
    free(graph->second);
    free(graph->backward);
    free(graph->departure);
    free(graph->outside);
    free(graph->faces);
    memset(graph, 0, sizeof(*graph));
}

// frame `frame` of the .points, its points after the frames before it; the levels are passed over, and every voxel must
// lie in the view
static int output_frame_read(FILE *points, const unsigned int head[OUTPUT_POINTS_HEADER_WORDS], unsigned int frame,
                             OutputGraph *graph)
{
    const unsigned long long voxels = output_view_voxels(graph->view);
    const unsigned long long at = graph->points;
    unsigned int count = 0u;
    int ok = output_read(points, &count, sizeof(count)) && (count <= voxels) &&
             output_points_reserve(graph, at + count) &&
             output_read(points, &graph->voxels[at], (size_t)count * sizeof(unsigned int)) &&
             output_skip(points, output_frame_bytes(count, head[4]));
    for (unsigned int point = 0u; ok && (point < count); point += 1u)
    {
        ok = graph->voxels[at + point] < voxels;
        graph->forward[at + point] = OUTPUT_NONE;
        graph->second[at + point] = OUTPUT_NONE;
        graph->backward[at + point] = OUTPUT_NONE;
        graph->departure[at + point] = 0ull;
        graph->outside[at + point] = 0u;
        graph->faces[at + point] = 0u;
    }
    graph->points = ok ? (at + count) : at;
    graph->first[frame + 1u] = graph->points;
    return ok;
}

// frame pair (frame, frame + 1) of the .links: its record against the two frames' points, each source's flags, and each
// chosen gate pair as a link, at most one out of each source and one into each target (O20)
static int output_pair_read(const char *sample, FILE *links, unsigned int frame, OutputGraph *graph,
                            unsigned int *words)
{
    const unsigned long long now = graph->first[frame];
    const unsigned long long next = graph->first[frame + 1u];
    const unsigned long long sources = next - now;
    const unsigned long long targets = graph->first[frame + 2u] - next;
    unsigned int record[SORT_PAIR_WORDS];
    if (output_read(links, record, sizeof(record)) == 0)
    {
        fprintf(stderr, "  output: %s: frames %u and %u: the pair record did not read\n", sample, frame, frame + 1u);
        return 0;
    }
    if ((record[0] != sources) || (record[1] != targets))
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: the pair record reads %u sources and %u targets, the .points"
                " %llu and %llu\n",
                sample, frame, frame + 1u, record[0], record[1], sources, targets);
        return 0;
    }
    for (unsigned int done = 0u; done < record[0];)
    {
        const unsigned int batch = ((record[0] - done) < OUTPUT_CHUNK) ? (record[0] - done) : OUTPUT_CHUNK;
        if (output_read(links, words, (size_t)batch * SORT_SOURCE_WORDS * sizeof(unsigned int)) == 0)
        {
            fprintf(stderr, "  output: %s: frames %u and %u: the source records did not read\n", sample, frame,
                    frame + 1u);
            return 0;
        }
        for (unsigned int at = 0u; at < batch; at += 1u)
        {
            const unsigned int flags = words[(SORT_SOURCE_WORDS * at) + ENGINE_AXES];
            graph->outside[now + done + at] = ((flags & SORT_SOURCE_OUTSIDE) != 0u) ? 1u : 0u;
        }
        done += batch;
    }
    unsigned int chosen = 0u;
    for (unsigned int done = 0u; done < record[2];)
    {
        const unsigned int batch = ((record[2] - done) < OUTPUT_CHUNK) ? (record[2] - done) : OUTPUT_CHUNK;
        if (output_read(links, words, (size_t)batch * SORT_GATE_WORDS * sizeof(unsigned int)) == 0)
        {
            fprintf(stderr, "  output: %s: frames %u and %u: the gate records did not read\n", sample, frame,
                    frame + 1u);
            return 0;
        }
        for (unsigned int at = 0u; at < batch; at += 1u)
        {
            const unsigned int *const pair = &words[SORT_GATE_WORDS * at];
            if ((pair[6] & SORT_GATE_CHOSEN) == 0u)
            {
                continue;
            }
            const unsigned int source = pair[0];
            const unsigned int target = pair[1];
            if ((source >= record[0]) || (target >= record[1]))
            {
                fprintf(stderr, "  output: %s: frames %u and %u: a chosen link %u to %u lies past the frames' points\n",
                        sample, frame, frame + 1u, source, target);
                return 0;
            }
            if (graph->forward[now + source] != OUTPUT_NONE)
            {
                fprintf(stderr, "  output: %s: point %u of frame %u has two chosen links out\n", sample, source, frame);
                return 0;
            }
            if (graph->backward[next + target] != OUTPUT_NONE)
            {
                fprintf(stderr, "  output: %s: point %u of frame %u has two chosen links in\n", sample, target,
                        frame + 1u);
                return 0;
            }
            graph->forward[now + source] = target;
            graph->backward[next + target] = source;
            // the cost as its low word, then its high
            graph->departure[now + source] = (unsigned long long)pair[2] | ((unsigned long long)pair[3] << 32u);
            chosen += 1u;
        }
        done += batch;
    }
    if (chosen != record[4])
    {
        fprintf(stderr, "  output: %s: frames %u and %u: the pair record reads %u chosen links, its gate %u\n", sample,
                frame, frame + 1u, record[4], chosen);
        return 0;
    }
    return 1;
}

static int output_graph_read(const char *sample, FILE *points, FILE *links, OutputGraph *graph, unsigned int *words)
{
    unsigned int head[OUTPUT_POINTS_HEADER_WORDS];
    unsigned int links_head[SORT_HEADER_WORDS];
    int ok = output_read(points, head, sizeof(head)) &&
             output_skip(points, (1ull + SCAN_READINGS) * sizeof(unsigned long long)) &&
             output_read(links, links_head, sizeof(links_head));
    if (ok == 0)
    {
        fprintf(stderr, "  output: %s: its .points or .links head did not read\n", sample);
        return 0;
    }
    if ((head[0] != links_head[0]) || (head[1] != links_head[1]) || (head[2] != links_head[2]) ||
        (head[3] != links_head[3]))
    {
        fprintf(stderr,
                "  output: %s: its .points reads %u frames of %u x %u x %u, its .links %u frames of %u x %u x"
                " %u\n",
                sample, head[0], head[1], head[2], head[3], links_head[0], links_head[1], links_head[2], links_head[3]);
        return 0;
    }
    if (output_first_reserve(graph, head[0]) == 0)
    {
        fprintf(stderr, "  output: %s: the memory for %u frames could not be reserved\n", sample, head[0]);
        return 0;
    }
    graph->frames = head[0];
    memcpy(graph->view, &head[1], sizeof(graph->view));
    graph->points = 0ull;
    graph->first[0] = 0ull;
    ok = (head[0] == 0u) || output_frame_read(points, head, 0u, graph);
    if (ok == 0)
    {
        fprintf(stderr, "  output: %s: frame 0 did not read, or a voxel lies outside the view\n", sample);
    }
    for (unsigned int frame = 0u; ok && ((frame + 1u) < head[0]); frame += 1u)
    {
        const int read_complete = output_frame_read(points, head, frame + 1u, graph);
        if (read_complete == 0)
        {
            fprintf(stderr, "  output: %s: frame %u did not read, or a voxel lies outside the view\n", sample,
                    frame + 1u);
        }
        ok = read_complete && output_pair_read(sample, links, frame, graph, words);
    }
    const int ended = ok && output_at_end(points) && output_at_end(links);
    if (ok && (ended == 0))
    {
        fprintf(stderr, "  output: %s: its .points or .links does not end at its last frame\n", sample);
    }
    return ended;
}

// the CRC-64 of the whole file (engine/codecs/crc/crc.h's key), read through `words`, which holds OUTPUT_CHUNK gate
// records
static int output_file_crc(const char *path, unsigned int *words, unsigned long long *crc)
{
    FILE *const file = fopen(path, "rb");
    unsigned char *const bytes = (unsigned char *)words;
    const size_t capacity = (size_t)OUTPUT_CHUNK * SORT_GATE_WORDS * sizeof(unsigned int);
    unsigned long long running = ~0ull;
    size_t read = 0u;
    do
    {
        read = (file != NULL) ? fread(bytes, 1u, capacity, file) : 0u;
        for (size_t at = 0u; at < read; at += 1u)
        {
            running = crc_step(CRC_TABLE, running, bytes[at]);
        }
    } while (read == capacity);
    const int complete = (file != NULL) && (ferror(file) == 0) && (feof(file) != 0);
    if (file != NULL)
    {
        fclose(file);
    }
    *crc = ~running;
    return complete;
}

// the .links' CRC-64 at `links_path`, taken the first time a file beside it asks for it and kept for the next
static int output_links_crc(const char *links_path, unsigned int *words, OutputLinksCrc *crc)
{
    if (crc->summed == 0)
    {
        crc->complete = output_file_crc(links_path, words, &crc->value);
        crc->summed = 1;
    }
    return crc->complete;
}

// the faces a place crosses on `axis` of `extent`, as the shape's face bits order them (src/faces/faces.h)
static unsigned int output_crossed(unsigned int axis, long long place, long long extent)
{
    return ((place < 0ll) ? (1u << (2u * axis)) : 0u) | ((place >= extent) ? (2u << (2u * axis)) : 0u);
}

// every flag a .faces point may carry
#define OUTPUT_FACES_KNOWN                                                                                             \
    (FACES_ENTERING | FACES_LEAVING | FACES_FIRST | FACES_LAST | FACES_CARRIED | (FACES_SIX << FACES_BACK_SHIFT) |     \
     (FACES_SIX << FACES_AHEAD_SHIFT) | (FACES_SIX << FACES_HESSIAN_SHIFT))

// one point's .faces words checked against the sort's links as the .links gave them, before any .divide: its flags
// known, its back-prediction's faces those its words cross, its prediction's faces crossed just when the .links flags
// it outside (and none in the last frame), and each verdict the one its links give. Returns the fault, or NULL
static const char *output_faces_fault(const OutputGraph *graph, unsigned int frame, unsigned long long point,
                                      const unsigned int words[FACES_POINT_WORDS])
{
    const unsigned int flags = words[ENGINE_AXES];
    unsigned int back = 0u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        // a back-prediction is written as its two's complement word
        back |= output_crossed(axis, (long long)(int)words[axis], (long long)graph->view[axis]);
    }
    const unsigned int ahead = (flags >> FACES_AHEAD_SHIFT) & FACES_SIX;
    const int later = (frame + 1u) < graph->frames;
    const int start = (frame != 0u) && (graph->backward[point] == OUTPUT_NONE);
    const int end = later && (graph->forward[point] == OUTPUT_NONE);
    const int carried = (frame != 0u) && later && (graph->forward[point] != OUTPUT_NONE);
    if ((flags & ~OUTPUT_FACES_KNOWN) != 0u)
    {
        return "a flag no .faces sets";
    }
    if (((flags >> FACES_BACK_SHIFT) & FACES_SIX) != back)
    {
        return "the back-prediction's faces are not those its place crosses";
    }
    if ((ahead != 0u) != (later && (graph->outside[point] != 0u)))
    {
        return "the prediction's faces disagree with the .links' outside flag";
    }
    if ((((flags & FACES_FIRST) != 0u) != (frame == 0u)) || (((flags & FACES_LAST) != 0u) == later))
    {
        return "the first or last frame's flag is not the point's frame";
    }
    if (((flags & FACES_CARRIED) != 0u) != carried)
    {
        return "the carried flag disagrees with the point's link out";
    }
    if (((flags & FACES_ENTERING) != 0u) != (start && (back != 0u)))
    {
        return "the entering verdict is not the one its link in and its back-prediction give";
    }
    if (((flags & FACES_LEAVING) != 0u) != (end && (ahead != 0u)))
    {
        return "the leaving verdict is not the one its link out and its prediction give";
    }
    return NULL;
}

// the sample's .faces, when it has one: its head against the .points' frames and view and against the CRC-64 of the
// .links at `links_path`, then each frame's count and each point's words checked against the sort's links
// (output_faces_fault), and the file ended at its last frame. A .faces that does not open is none, and every point's
// flags stay 0
static int output_faces_read(const char *sample, const char *set, const char *links_path, OutputGraph *graph,
                             unsigned int *words, OutputLinksCrc *crc, OutputResults *results)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".faces") ? fopen(path, "rb") : NULL;
    if (file == NULL)
    {
        return 1;
    }
    results->faces = 1ull;
    unsigned int head[FACES_HEADER_WORDS];
    int ok = output_read(file, head, sizeof(head));
    if (ok == 0)
    {
        fprintf(stderr, "  output: %s: its .faces head did not read\n", sample);
    }
    else if ((head[0] != graph->frames) || (head[1] != graph->view[0]) || (head[2] != graph->view[1]) ||
             (head[3] != graph->view[2]))
    {
        fprintf(stderr,
                "  output: %s: its .faces reads %u frames of %u x %u x %u, its .points %u frames of %u x %u x"
                " %u\n",
                sample, head[0], head[1], head[2], head[3], graph->frames, graph->view[0], graph->view[1],
                graph->view[2]);
        ok = 0;
    }
    else if (output_links_crc(links_path, words, crc) == 0)
    {
        fprintf(stderr, "  output: %s: its .links did not read whole for its CRC-64\n", sample);
        ok = 0;
    }
    else if (((unsigned long long)head[4] | ((unsigned long long)head[5] << 32u)) != crc->value)
    {
        fprintf(stderr,
                "  output: %s: its .faces was made from a .links of CRC-64 %016llX, and its .links reads"
                " %016llX\n",
                sample, (unsigned long long)head[4] | ((unsigned long long)head[5] << 32u), crc->value);
        ok = 0;
    }
    const unsigned int batch_max = (OUTPUT_CHUNK * SORT_GATE_WORDS) / FACES_POINT_WORDS;
    for (unsigned int frame = 0u; ok && (frame < graph->frames); frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long points = graph->first[frame + 1u] - now;
        unsigned int count = 0u;
        ok = output_read(file, &count, sizeof(count)) && (count == points);
        if (ok == 0)
        {
            fprintf(stderr,
                    "  output: %s: frame %u: the .faces' count did not read, or is not the frame's %llu"
                    " points\n",
                    sample, frame, points);
        }
        for (unsigned int done = 0u; ok && (done < count);)
        {
            const unsigned int batch = ((count - done) < batch_max) ? (count - done) : batch_max;
            ok = output_read(file, words, (size_t)batch * FACES_POINT_WORDS * sizeof(unsigned int));
            if (ok == 0)
            {
                fprintf(stderr, "  output: %s: frame %u: the .faces' points did not read\n", sample, frame);
                break;
            }
            for (unsigned int at = 0u; ok && (at < batch); at += 1u)
            {
                const unsigned int *const point_words = &words[FACES_POINT_WORDS * at];
                const char *const fault = output_faces_fault(graph, frame, now + done + at, point_words);
                if (fault != NULL)
                {
                    fprintf(stderr, "  output: %s: frame %u: point %u of its .faces: %s\n", sample, frame, done + at,
                            fault);
                    ok = 0;
                }
                graph->faces[now + done + at] = point_words[ENGINE_AXES];
            }
            done += batch;
        }
    }
    const int ended = ok && output_at_end(file);
    if (ok && (ended == 0))
    {
        fprintf(stderr, "  output: %s: its .faces does not end at its last frame\n", sample);
    }
    fclose(file);
    return ended;
}

// a point index as the messages print it: DIVIDE_NONE is -1
static long long output_index(unsigned int index)
{
    return (index == DIVIDE_NONE) ? -1ll : (long long)index;
}

// one division of frame pair (frame, frame + 1) checked against the links as they stand and then made: the parent takes
// daughter two as its second link, and the point daughter two leaves, if any, loses its link and ends. `previous` is
// the pair's last parent, or -1
static int output_division(const char *sample, unsigned int frame, const unsigned int division[DIVIDE_WORDS],
                           long long previous, OutputGraph *graph, OutputResults *results)
{
    const unsigned long long now = graph->first[frame];
    const unsigned long long next = graph->first[frame + 1u];
    const unsigned long long sources = next - now;
    const unsigned long long targets = graph->first[frame + 2u] - next;
    const unsigned int parent = division[0];
    const unsigned int one = division[1];
    const unsigned int two = division[2];
    const unsigned int left = division[3];
    if ((parent >= sources) || ((long long)parent <= previous))
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: a division's parent %u lies past the frame's points or does not"
                " follow the parent before it\n",
                sample, frame, frame + 1u, parent);
        return 0;
    }
    if ((graph->forward[now + parent] == OUTPUT_NONE) || (graph->forward[now + parent] != one))
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: the division of parent %u names daughter one %lld, and the"
                " parent's link goes to %lld\n",
                sample, frame, frame + 1u, parent, output_index(one), output_index(graph->forward[now + parent]));
        return 0;
    }
    if ((two >= targets) || (two == one))
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: the division of parent %u names daughter two %lld, past the"
                " frame's points or daughter one\n",
                sample, frame, frame + 1u, parent, output_index(two));
        return 0;
    }
    if (graph->backward[next + two] != left)
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: the division of parent %u takes daughter two %u from %lld,"
                " and its link comes from %lld\n",
                sample, frame, frame + 1u, parent, two, output_index(left), output_index(graph->backward[next + two]));
        return 0;
    }
    if ((left != DIVIDE_NONE) && (graph->second[now + left] != OUTPUT_NONE))
    {
        fprintf(stderr,
                "  output: %s: frames %u and %u: the division of parent %u takes daughter two %u from point %u,"
                " which divides\n",
                sample, frame, frame + 1u, parent, two, left);
        return 0;
    }
    if (left != DIVIDE_NONE)
    {
        graph->forward[now + left] = OUTPUT_NONE;
        graph->departure[now + left] = 0ull;
        results->moved += 1ull;
    }
    graph->second[now + parent] = two;
    graph->backward[next + two] = parent;
    results->divisions += 1ull;
    return 1;
}

// the sample's .divide, when it has one: its head against the .points' frames and view and against the CRC-64 of the
// .links at `links_path`, then each frame pair's divisions made on the sort's links (output_division), and the file
// ended at its last pair. A .divide that does not open is none, and the graph stays the sort's
static int output_divide_read(const char *sample, const char *set, const char *links_path, OutputGraph *graph,
                              unsigned int *words, OutputLinksCrc *crc, OutputResults *results)
{
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, ".divide") ? fopen(path, "rb") : NULL;
    if (file == NULL)
    {
        return 1;
    }
    results->divide = 1ull;
    unsigned int head[DIVIDE_HEADER_WORDS];
    int ok = output_read(file, head, sizeof(head));
    if (ok == 0)
    {
        fprintf(stderr, "  output: %s: its .divide head did not read\n", sample);
    }
    else if ((head[0] != graph->frames) || (head[1] != graph->view[0]) || (head[2] != graph->view[1]) ||
             (head[3] != graph->view[2]))
    {
        fprintf(stderr,
                "  output: %s: its .divide reads %u frames of %u x %u x %u, its .points %u frames of %u x %u x"
                " %u\n",
                sample, head[0], head[1], head[2], head[3], graph->frames, graph->view[0], graph->view[1],
                graph->view[2]);
        ok = 0;
    }
    else if (output_links_crc(links_path, words, crc) == 0)
    {
        fprintf(stderr, "  output: %s: its .links did not read whole for its CRC-64\n", sample);
        ok = 0;
    }
    else if (((unsigned long long)head[4] | ((unsigned long long)head[5] << 32u)) != crc->value)
    {
        fprintf(stderr,
                "  output: %s: its .divide was made from a .links of CRC-64 %016llX, and its .links reads"
                " %016llX\n",
                sample, (unsigned long long)head[4] | ((unsigned long long)head[5] << 32u), crc->value);
        ok = 0;
    }
    for (unsigned int frame = 0u; ok && ((frame + 1u) < graph->frames); frame += 1u)
    {
        unsigned int count = 0u;
        const unsigned long long sources = graph->first[frame + 1u] - graph->first[frame];
        ok = output_read(file, &count, sizeof(count)) && (count <= sources);
        if (ok == 0)
        {
            fprintf(stderr,
                    "  output: %s: frames %u and %u: the .divide's count did not read, or passes the frame's"
                    " points\n",
                    sample, frame, frame + 1u);
        }
        long long previous = -1ll;
        for (unsigned int at = 0u; ok && (at < count); at += 1u)
        {
            unsigned int division[DIVIDE_WORDS];
            ok = output_read(file, division, sizeof(division));
            if (ok == 0)
            {
                fprintf(stderr, "  output: %s: frames %u and %u: a division did not read\n", sample, frame, frame + 1u);
                break;
            }
            ok = output_division(sample, frame, division, previous, graph, results);
            previous = (long long)division[0];
        }
    }
    const int ended = ok && output_at_end(file);
    if (ok && (ended == 0))
    {
        fprintf(stderr, "  output: %s: its .divide does not end at its last frame pair\n", sample);
    }
    fclose(file);
    return ended;
}

// the counts O20 and H4 ask for, frame pair by frame pair, and H4 on each: N(t + 1) - N(t) = D(t) - E(t) + S(t + 1),
// with D(t) the points of t with two links out, the parents of the pair's divisions. With a .faces, the ends whose
// prediction crosses a face leave the view, and the starts whose back-prediction crosses one enter it; the links are
// the output's, the .divide's made. The results come in as output_sample_read zeroed them, with the .faces' and the
// .divide's counts
static int output_graph_results(const char *sample, const OutputGraph *graph, OutputResults *results)
{
    results->frames = graph->frames;
    results->nodes = graph->points;
    if ((results->faces != 0ull) && (graph->frames != 0u))
    {
        results->first = graph->first[1] - graph->first[0];
        results->last = graph->first[graph->frames] - graph->first[graph->frames - 1u];
    }
    int ok = 1;
    for (unsigned int frame = 0u; (frame + 1u) < graph->frames; frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long next = graph->first[frame + 1u];
        const unsigned long long frame_end = graph->first[frame + 2u];
        unsigned long long ends = 0ull;
        unsigned long long outside = 0ull;
        unsigned long long starts = 0ull;
        unsigned long long parents = 0ull;
        for (unsigned long long point = now; point < next; point += 1u)
        {
            const unsigned long long end = (graph->forward[point] == OUTPUT_NONE) ? 1ull : 0ull;
            ends += end;
            outside += end * graph->outside[point];
            results->leaving += (((graph->faces[point] >> FACES_AHEAD_SHIFT) & FACES_SIX) != 0u) ? end : 0ull;
            parents += (graph->second[point] != OUTPUT_NONE) ? 1ull : 0ull;
        }
        for (unsigned long long point = next; point < frame_end; point += 1u)
        {
            const unsigned long long start = (graph->backward[point] == OUTPUT_NONE) ? 1ull : 0ull;
            starts += start;
            results->entering += (((graph->faces[point] >> FACES_BACK_SHIFT) & FACES_SIX) != 0u) ? start : 0ull;
        }
#ifdef OUTPUT_TEST_FAULTS
        ends += output_test_skew;
#endif
        // the counts are below 2^63. Each difference is a long long exactly
        const long long change = (long long)(frame_end - next) - (long long)(next - now);
        const long long divided = (long long)parents;
        const int balanced = (change == (divided - (long long)ends + (long long)starts));
        if (balanced == 0)
        {
            fprintf(stderr,
                    "  output: %s: frames %u and %u: H4 does not hold: N(t + 1) - N(t) = %lld, D - E + S ="
                    " %lld - %llu + %llu\n",
                    sample, frame, frame + 1u, change, divided, ends, starts);
        }
        ok = ok && balanced;
        results->edges += (next - now) - ends + parents;
        results->ends += ends;
        results->outside += outside;
        results->ends_max = (ends > results->ends_max) ? ends : results->ends_max;
        results->starts += starts;
        results->starts_max = (starts > results->starts_max) ? starts : results->starts_max;
        results->pairs += 1ull;
        results->balanced += (unsigned long long)balanced;
    }
    return ok;
}

// a word into the CRC-64, its bytes low to high
static unsigned long long output_crc_word(unsigned long long crc, unsigned long long word)
{
    for (unsigned int place = 0u; place < 8u; place += 1u)
    {
        crc = crc_step(CRC_TABLE, crc, (unsigned int)((word >> (8u * place)) & 0xFFull));
    }
    return crc;
}

// a CRC-64 of everything a sample's rows are written from: the view, each frame's count, and each point's voxel, its
// links out, the first link's cost and its .faces flags, from which its state is made; the links in are the links out
// read backward. The second pass holds each sample to its first pass's. A sample that changed between the passes
// is found even where every count is the same
static unsigned long long output_graph_fingerprint(const OutputGraph *graph)
{
    unsigned long long crc = ~0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        crc = output_crc_word(crc, graph->view[axis]);
    }
    for (unsigned int frame = 0u; frame < graph->frames; frame += 1u)
    {
        crc = output_crc_word(crc, graph->first[frame + 1u] - graph->first[frame]);
    }
    for (unsigned long long point = 0ull; point < graph->points; point += 1ull)
    {
        crc = output_crc_word(crc, graph->voxels[point]);
        crc = output_crc_word(crc, graph->forward[point]);
        crc = output_crc_word(crc, graph->second[point]);
        crc = output_crc_word(crc, graph->departure[point]);
        crc = output_crc_word(crc, graph->faces[point]);
    }
    return ~crc;
}

static int output_sample_read(const OutputRequest *request, const char *sample, OutputGraph *graph, unsigned int *words,
                              OutputResults *results)
{
    memset(results, 0, sizeof(*results));
    // a sample's name is a field of both files, which neither separator nor line break may cut
    if (strpbrk(sample, ",\"\t\r\n") != NULL)
    {
        fprintf(stderr, "  output: %s: its name holds a comma, a quote, a tab or a line break\n", sample);
        return 0;
    }
    char points_path[ENGINE_PATH_CAPACITY];
    char links_path[ENGINE_PATH_CAPACITY];
    FILE *const points = engine_sample_path(points_path, sizeof(points_path), request->set, sample, ".points")
                             ? fopen(points_path, "rb")
                             : NULL;
    FILE *const links = engine_sample_path(links_path, sizeof(links_path), request->set, sample, ".links")
                            ? fopen(links_path, "rb")
                            : NULL;
    if ((points == NULL) || (links == NULL))
    {
        fprintf(stderr, "  output: %s: its .points or .links in %s did not open\n", sample, request->set);
    }
    const int read = (points != NULL) && (links != NULL) && output_graph_read(sample, points, links, graph, words);
    if (points != NULL)
    {
        fclose(points);
    }
    if (links != NULL)
    {
        fclose(links);
    }
    // the .faces is checked against the sort's links before the .divide moves any
    OutputLinksCrc crc;
    memset(&crc, 0, sizeof(crc));
    const int ok = read && output_faces_read(sample, request->set, links_path, graph, words, &crc, results) &&
                   output_divide_read(sample, request->set, links_path, graph, words, &crc, results) &&
                   output_graph_results(sample, graph, results);
    results->fingerprint = ok ? output_graph_fingerprint(graph) : 0ull;
    return ok;
}

// the sample's rows: in the nodes, one a point in the order (frame, index); in the submission, its node rows in that
// order, the node ids counting from 1 in the sample, then its edge rows in their sources' order, a parent's link to
// daughter one and then its link to daughter two. `row` is the submission's running id
static void output_sample_write(const OutputRequest *request, const char *sample, const OutputGraph *graph,
                                unsigned long long *row, unsigned long long *node_rows, unsigned long long *edge_rows)
{
    const unsigned long long plane = (unsigned long long)graph->view[1] * graph->view[2];
    for (unsigned int frame = 0u; frame < graph->frames; frame += 1u)
    {
        for (unsigned long long point = graph->first[frame]; point < graph->first[frame + 1u]; point += 1u)
        {
            // a point lies in a view of at least one voxel. The plane and the width are not 0
            const unsigned int voxel = graph->voxels[point];
            const unsigned long long z = voxel / plane;
            const unsigned long long y = (voxel % plane) / graph->view[2];
            const unsigned long long x = voxel % graph->view[2];
            const unsigned long long leaf = point - graph->first[frame];
            const long long forward = (graph->forward[point] != OUTPUT_NONE) ? (long long)graph->forward[point] : -1ll;
            const long long backward =
                (graph->backward[point] != OUTPUT_NONE) ? (long long)graph->backward[point] : -1ll;
            const int links = ((forward >= 0ll) ? 1 : 0) + ((graph->second[point] != OUTPUT_NONE) ? 1 : 0);
            // daughter two's split_from is its parent's leaf: a point whose link in is its source's second link
            const long long split_from =
                ((backward >= 0ll) &&
                 (graph->second[graph->first[frame - 1u] + (unsigned long long)backward] == (unsigned int)leaf))
                    ? backward
                    : -1ll;
            // its state: daughter two split; a start whose back-prediction crosses a face entered, and an end whose
            // prediction crosses one left, each by its .faces flags, which are 0 with no .faces
            const unsigned int faces = graph->faces[point];
            const int start = (frame != 0u) && (backward < 0ll);
            const int end = ((frame + 1u) < graph->frames) && (forward < 0ll);
            const unsigned int state =
                ((split_from >= 0ll) ? OUTPUT_STATE_SPLIT : 0u) |
                ((start && (((faces >> FACES_BACK_SHIFT) & FACES_SIX) != 0u)) ? OUTPUT_STATE_ENTERED : 0u) |
                ((end && (((faces >> FACES_AHEAD_SHIFT) & FACES_SIX) != 0u)) ? OUTPUT_STATE_LEFT : 0u);
            // the sort forms no region. A point is its own object of 0 voxels; its body is its node id
            if (request->nodes != NULL)
            {
                fprintf(request->nodes,
                        "%s\t%u\t%llu\t%llu\t%llu\t%llu\t0\t%llu\t1\t%lld\t%llu\t0\t%lld\t%d\t0\t0\t0"
                        "\t-1\t0\t%lld\t%llu\t%u\t-1\t0\t%lld\n",
                        sample, frame, leaf, z, y, x, leaf, forward, graph->departure[point], forward, links, backward,
                        point + 1ull, state, split_from);
            }
            if (request->submission != NULL)
            {
                fprintf(request->submission, "%llu,%s,node,%llu,%u,%llu,%llu,%llu,-1,-1\n", *row, sample, point + 1ull,
                        frame, z, y, x);
                *row += 1ull;
                *node_rows += 1ull;
            }
        }
    }
    for (unsigned int frame = 0u; (request->submission != NULL) && ((frame + 1u) < graph->frames); frame += 1u)
    {
        for (unsigned long long point = graph->first[frame]; point < graph->first[frame + 1u]; point += 1u)
        {
            const unsigned int targets[2] = {graph->forward[point], graph->second[point]};
            for (unsigned int at = 0u; at < 2u; at += 1u)
            {
                if (targets[at] == OUTPUT_NONE)
                {
                    continue;
                }
                fprintf(request->submission, "%llu,%s,edge,-1,-1,-1,-1,-1,%llu,%llu\n", *row, sample, point + 1ull,
                        graph->first[frame + 1u] + targets[at] + 1ull);
                *row += 1ull;
                *edge_rows += 1ull;
            }
        }
    }
}

// a file flushed whole, or none named
static int output_flushed(FILE *file)
{
    return (file == NULL) || ((fflush(file) == 0) && (ferror(file) == 0));
}

extern "C" long output_graph_set(const OutputRequest *request)
{
    if ((request == NULL) || (request->set == NULL) || (request->samples == NULL) || (request->count == 0u) ||
        (request->report == NULL))
    {
        return OUTPUT_ERROR;
    }
    FILE *const report = request->report;
    unsigned int *const words = (unsigned int *)malloc((size_t)OUTPUT_CHUNK * SORT_GATE_WORDS * sizeof(unsigned int));
    OutputResults *const tallies = (OutputResults *)calloc(request->count, sizeof(OutputResults));
    if ((words == NULL) || (tallies == NULL))
    {
        fprintf(stderr, "  output: the memory for reading could not be reserved\n");
        free(words);
        free(tallies);
        return OUTPUT_ERROR;
    }
    OutputGraph graph;
    memset(&graph, 0, sizeof(graph));
    fprintf(report, "  %-24s %6s %10s %10s %s\n", "sample", "frames", "nodes", "edges",
            "ends (outside the view; most a frame), starts (most a frame); H4");
    OutputResults totals;
    memset(&totals, 0, sizeof(totals));
    unsigned long long faced_ends = 0ull;
    unsigned long long faced_starts = 0ull;
    unsigned int failed = 0u;
    for (unsigned int at = 0u; at < request->count; at += 1u)
    {
        const char *const sample = request->samples[at];
        OutputResults *const results = &tallies[at];
        if (output_sample_read(request, sample, &graph, words, results) == 0)
        {
            fprintf(stderr, "  output: %s failed\n", sample);
            failed += 1u;
            continue;
        }
        fprintf(report,
                "  %-24s %6llu %10llu %10llu %llu (%llu; %llu), %llu (%llu); held on %llu of %llu frame"
                " pairs",
                sample, results->frames, results->nodes, results->edges, results->ends, results->outside,
                results->ends_max, results->starts, results->starts_max, results->balanced, results->pairs);
        // a sample with no .divide and no .faces reads as it did before S7 and S9
        if (results->divide != 0ull)
        {
            fprintf(report, "; its .divide: %llu divisions, %llu of them moving a link", results->divisions,
                    results->moved);
        }
        if (results->faces != 0ull)
        {
            fprintf(report,
                    "; its .faces: %llu of the ends leave the view, %llu of the starts enter it; %llu points"
                    " in the first frame, %llu in the last",
                    results->leaving, results->entering, results->first, results->last);
        }
        fprintf(report, "\n");
        totals.frames += results->frames;
        totals.nodes += results->nodes;
        totals.edges += results->edges;
        totals.ends += results->ends;
        totals.outside += results->outside;
        totals.starts += results->starts;
        totals.pairs += results->pairs;
        totals.balanced += results->balanced;
        totals.divide += results->divide;
        totals.divisions += results->divisions;
        totals.moved += results->moved;
        totals.faces += results->faces;
        totals.leaving += results->leaving;
        totals.entering += results->entering;
        totals.first += results->first;
        totals.last += results->last;
        faced_ends += (results->faces != 0ull) ? results->ends : 0ull;
        faced_starts += (results->faces != 0ull) ? results->starts : 0ull;
    }
    // a set with no .divide and no .faces reads as it did before S7 and S9
    fprintf(report, "  checked %u of %u samples: %llu frames, %llu nodes, %llu edges; ", request->count - failed,
            request->count, totals.frames, totals.nodes, totals.edges);
    if (totals.divide == 0ull)
    {
        fprintf(report, "no point has two links in or two out, and none divides; ");
    }
    else
    {
        fprintf(report,
                "no point has two links in, and only a division's parent has two out: %llu divisions from %llu"
                " .divide files, %llu of them moving a link; ",
                totals.divisions, totals.divide, totals.moved);
    }
    fprintf(report, "%llu ends (%llu with their prediction outside the view), %llu starts, ", totals.ends,
            totals.outside, totals.starts);
    if (totals.faces == 0ull)
    {
        fprintf(report, "none explained before S8 and S9; ");
    }
    else
    {
        fprintf(report,
                "and in the %llu samples with a .faces %llu of their %llu ends leave the view and %llu of their"
                " %llu starts enter it, the rest unexplained before S8, with %llu points in their first frames"
                " and %llu in their last; ",
                totals.faces, totals.leaving, faced_ends, totals.entering, faced_starts, totals.first, totals.last);
    }
    fprintf(report, "H4 held on %llu of %llu frame pairs\n", totals.balanced, totals.pairs);
    if (failed != 0u)
    {
        fprintf(stderr, "  output: %u of %u samples broke: nothing is written past the headers\n", failed,
                request->count);
        output_graph_free(&graph);
        free(words);
        free(tallies);
        return OUTPUT_ERROR;
    }
#ifdef OUTPUT_TEST_FAULTS
    if (output_test_between != NULL)
    {
        output_test_between(request);
    }
#endif
    // the second pass reads each sample again and writes it; a sample whose counts or fingerprint read otherwise than
    // they did has changed between the passes, and the rows before it are already written
    unsigned long long row = 0ull;
    unsigned long long node_rows = 0ull;
    unsigned long long edge_rows = 0ull;
    unsigned long long nodes_rows = 0ull;
    int ok = 1;
    for (unsigned int at = 0u; ok && (at < request->count); at += 1u)
    {
        const char *const sample = request->samples[at];
        OutputResults again;
        ok = output_sample_read(request, sample, &graph, words, &again) &&
             (memcmp(&again, &tallies[at], sizeof(again)) == 0);
        if (ok == 0)
        {
            fprintf(stderr, "  output: %s did not read again as it read before: the outputs are incomplete\n", sample);
            break;
        }
        output_sample_write(request, sample, &graph, &row, &node_rows, &edge_rows);
        nodes_rows += (request->nodes != NULL) ? graph.points : 0ull;
    }
    const int nodes_complete = output_flushed(request->nodes);
    const int submission_complete = output_flushed(request->submission);
    if (nodes_complete == 0)
    {
        fprintf(stderr, "  output: the nodes could not be written whole\n");
    }
    if (submission_complete == 0)
    {
        fprintf(stderr, "  output: the submission could not be written whole\n");
    }
    if (request->nodes != NULL)
    {
        fprintf(report, "  the nodes: %llu rows after the header\n", nodes_rows);
    }
    else
    {
        fprintf(report, "  the nodes: no output named, none written\n");
    }
    if (request->submission != NULL)
    {
        fprintf(report, "  the submission: %llu rows after the header, %llu node rows and %llu edge rows\n", row,
                node_rows, edge_rows);
    }
    else
    {
        fprintf(report, "  the submission: no output named, none written\n");
    }
    output_graph_free(&graph);
    free(words);
    free(tallies);
    return (ok && nodes_complete && submission_complete) ? 0L : OUTPUT_ERROR;
}

extern "C" int output_close(FILE *file, const char *name)
{
    if (file == NULL)
    {
        return 1;
    }
    // the error is read before the close ends the file
    const int unwritten = ferror(file);
    const int closed = (fclose(file) == 0);
    if ((unwritten != 0) || (closed == 0))
    {
        fprintf(stderr, "  %s could not be closed whole\n", (name != NULL) ? name : "a file");
        return 0;
    }
    return 1;
}
