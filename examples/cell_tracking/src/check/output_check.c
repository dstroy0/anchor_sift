// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// output_check: S11's nodes file and submission, read apart from the output by a reader of their own. From each named
// sample's .points, .links, and its .faces and .divide when it has them, it rebuilds the sample's graph (each point's
// voxel, the chosen link out of it with that link's cost, a division's second link, the link into it, and the faces
// its back-prediction and its prediction cross) and from the graph every row both files should hold, then holds each
// row of each file against its rebuilt row, byte for byte. It also checks the graph as it reads it: the .links' frames
// and view are the .points', each pair record's sources and targets are its frames' points, each chosen link lies
// within them, no point has two chosen links out or two in, each pair's chosen links are its record's count, and both
// files end at their last frame. A .faces must hold the .points' frames and view and the CRC-64 of the .links beside
// it, and each point's back-prediction and flags as this reader rebuilds them from the .points, the .drift's lags, the
// .shape's faces and the sort's links and predictions, before any .divide; each .links outside flag must be its
// prediction's, and the .faces, the .drift and the .shape end at their last frame. A .divide must hold the .points'
// frames and view and the CRC-64 of the .links beside it, and each division, in its parents' order, a parent within
// the frame whose chosen link goes to daughter one, a daughter two within the next frame other than daughter one whose
// link in comes from the point the division names (none for a start), and that point not a parent; the .divide ends
// at its last pair. It counts every file's bytes, line feeds and carriage returns. Reads only.
//   output_check <set> <nodes.tsv> <submission.csv> <sample> [<sample> ...]
//
// The formats, restated here from what the scan, the sort and the output write, not read from their code: a change to
// them must be made here too. Every word is little-endian.
//   .points     six 32-bit words (frames, depth, height, width, limbs, bits), the readings (64 bits), C (65536 64-bit
//               words), then a frame after another: its count, each point's voxel, each point's levels (limbs words)
//   .links      eight 32-bit words (frames, depth, height, width, three weights, the cost's terms), then for each frame
//               pair a record of 11 words (sources, targets, gate pairs, components, chosen, then kept, level and
//               crossed at 64 bits), each source's 4 words (a prediction z, y, x and flags), and each gate pair's 7
//               words (source, target, the cost's low word and high word, weight, component, flags; flag 1 chosen)
//   .drift      seven 32-bit words (frames, depth, height, width, three weights), then a frame after another: its
//               positive voxels, and after frame 0 the lag (z, y, x, signed) carrying the frame before onto it and the
//               agreement at that lag
//   .shape      six 32-bit words (frames, depth, height, width, the .points' limbs, and one more), then a frame after
//               another: its count, each point's faces (bit 1 << 2 axis for the low face of axis z, y, x cutting its
//               neighborhood, 2 << 2 axis for the high), then each point's six differences of limbs + 1 words
//   .faces      six 32-bit words (frames, depth, height, width, then the .links' CRC-64 as its low word and its high),
//               then a frame after another: its count, and each point's 4 words: its back-prediction z, y, x, signed,
//               and its flags. A place crosses the faces bit 1 << 2 axis when it lies below 0 on the axis, 2 << 2 axis
//               when it lies at or past the extent. The back-prediction of a point of frame 0 is its place; of a point
//               q of frame f > 0 it is q's place less the lag at f, and when f is not the last frame and q has a
//               chosen link out to q', less q' - q - the lag at f + 1 too. The flags: entering 1 (a start, a point
//               after frame 0 with no chosen link in, whose back-prediction crosses a face), leaving 2 (an end, a point
//               before the last frame with no chosen link out, whose prediction crosses one), first 4 (frame 0), last
//               8 (the last frame), carried 16 (a point of neither with a chosen link out), then the faces its
//               back-prediction crosses at bit 8, those its .links prediction crosses at bit 16 (none in the last
//               frame), and its .shape faces at bit 24. The links are the sort's, before any .divide
//   .divide     six 32-bit words (frames, depth, height, width, then the .links' CRC-64 as its low word and its high),
//               then for each frame pair its count of divisions and each division's 4 words (the parent in frame t,
//               daughter one, daughter two, and the point of t daughter two's link came from, or 0xFFFFFFFF for none).
//               The CRC-64 is CRC-64/XZ over the whole .links: reflected, the polynomial 0xC96C5795D7870F42, from all
//               ones, ended complemented. A division moves daughter two's link to the parent, and the point it left
//               ends
//   nodes       the header below; then a row a point, sample by sample in the order named, frame by frame, point by
//               point: sample, time, leaf (its index in the frame), z, y, x, then voxels 0, object (the leaf), members
//               1, forward (the target's leaf, or -1), departure (the link's cost, or 0), held 0, object_link (the
//               forward), object_links (its links out: 0, 1, or 2 for a division's parent), the null's three 0,
//               tower_target -1, tower_rounds 0, backward (the source's leaf, or -1), body (the point's node id),
//               state, parent -1, touches 0, split_from (daughter two's parent's leaf, else -1). The state is the sum
//               of 8 for daughter two, 1 for a start whose back-prediction crosses a face and 32 for an end whose
//               prediction crosses one, a start and an end being the graph's after any .divide; 0 with no .faces and
//               no .divide
//   submission  the header below; then for each sample its node rows (id, sample, "node", node id, t, z, y, x, -1, -1),
//               the node ids from 1 in the sample, and then its edge rows (id, sample, "edge", five -1, the source's
//               node id, the target's), in their sources' order, a parent's link to daughter one before its link to
//               daughter two; the ids count every row of the file from 0
// A voxel v of a view depth x height x width lies at z = v / (height width), y = (v mod height width) / width,
// x = v mod width.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OUTPUT_CHECK_READINGS 65536u

#define OUTPUT_CHECK_POINTS_HEAD 6u

#define OUTPUT_CHECK_LINKS_HEAD 8u

#define OUTPUT_CHECK_PAIR_WORDS 11u

#define OUTPUT_CHECK_SOURCE_WORDS 4u

#define OUTPUT_CHECK_GATE_WORDS 7u

#define OUTPUT_CHECK_CHOSEN 0x1u

// a source record's flag: its prediction lies outside the view
#define OUTPUT_CHECK_OUTSIDE 0x1u

#define OUTPUT_CHECK_NONE 0xFFFFFFFFu

#define OUTPUT_CHECK_DIVIDE_HEAD 6u

#define OUTPUT_CHECK_DIVISION_WORDS 4u

#define OUTPUT_CHECK_DRIFT_HEAD 7u

#define OUTPUT_CHECK_HESSIAN_HEAD 6u

// a .shape point's differences, each of the shape's limbs
#define OUTPUT_CHECK_HESSIAN_ENTRIES 6u

#define OUTPUT_CHECK_FACES_HEAD 6u

#define OUTPUT_CHECK_FACES_WORDS 4u

#define OUTPUT_CHECK_AXES 3u

// the six faces, z low and high, y low and high, x low and high
#define OUTPUT_CHECK_SIX 0x3Fu

#define OUTPUT_CHECK_ENTERING 0x1u

#define OUTPUT_CHECK_LEAVING 0x2u

#define OUTPUT_CHECK_FIRST 0x4u

#define OUTPUT_CHECK_LAST 0x8u

#define OUTPUT_CHECK_CARRIED 0x10u

#define OUTPUT_CHECK_BACK_SHIFT 8u

#define OUTPUT_CHECK_AHEAD_SHIFT 16u

#define OUTPUT_CHECK_HESSIAN_SHIFT 24u

// the nodes' state: a start entering the view, daughter two, an end leaving it
#define OUTPUT_CHECK_STATE_ENTERED 0x1u

#define OUTPUT_CHECK_STATE_SPLIT 0x8u

#define OUTPUT_CHECK_STATE_LEFT 0x20u

// CRC-64/XZ's polynomial, reflected
#define OUTPUT_CHECK_POLYNOMIAL 0xC96C5795D7870F42ull

#define OUTPUT_CHECK_PATH 4096u

#define OUTPUT_CHECK_ROW 1024u

#define OUTPUT_CHECK_CHUNK (1u << 20u)

// the differing rows shown in full, each file's first
#define OUTPUT_CHECK_SHOWN 5u

static const char OUTPUT_CHECK_NODES_HEADER[] =
    "sample\ttime\tleaf\tz\ty\tx\tvoxels\tobject\tobject_members\tforward\tdeparture\theld\tobject_link\tobject_links"
    "\tnull_draws\tnull_at_least\tnull_best\ttower_target\ttower_rounds\tbackward\tbody\tstate\tparent\ttouches"
    "\tsplit_from";

static const char OUTPUT_CHECK_SUBMISSION_HEADER[] = "id,dataset,row_type,node_id,t,z,y,x,source_id,target_id";

// a file read a line at a time through a chunk, counting its bytes, line feeds and carriage returns as they pass
typedef struct
{
    const char *name;
    FILE *file;
    unsigned char *chunk;
    size_t size;
    size_t at;
    char *line;
    size_t capacity;
    size_t length;
    int ended;
    unsigned long long bytes;
    unsigned long long feeds;
    unsigned long long returns;
    unsigned long long lines;
    unsigned long long compared;
    unsigned long long differing;
    unsigned long long missing;
} OutputCheckText;

// a sample's graph: each frame's first point among the sample's points, and each point's voxel, its link out (the
// target's leaf) with the link's cost, its second link out when it is a division's parent (daughter two's leaf), its
// link in (the source's leaf), the faces its .links prediction crosses with the .links' outside flag, and its .faces
// flags (0 without a .faces). `divisions` and `moved` count the divisions its .divide made, and those that moved a
// link; `faced` is 1 when it has a .faces; `summed` is 1 once the .links' CRC-64 is `crc`, -1 when it did not read
typedef struct
{
    unsigned int head[OUTPUT_CHECK_POINTS_HEAD];
    unsigned long long points;
    unsigned long long *first;
    unsigned int *voxels;
    unsigned int *forward;
    unsigned int *second;
    unsigned int *backward;
    unsigned long long *cost;
    unsigned int *ahead;
    unsigned int *outside;
    unsigned int *faces;
    size_t capacity;
    size_t first_capacity;
    unsigned long long edges;
    unsigned long long divisions;
    unsigned long long moved;
    unsigned long long faults;
    unsigned long long crc;
    int summed;
    int faced;
} OutputCheckGraph;

static int output_check_read(FILE *file, void *words, size_t bytes)
{
    return (bytes == 0u) || (fread(words, 1u, bytes, file) == bytes);
}

static int output_check_ended(FILE *file)
{
    return (fgetc(file) == EOF) && (feof(file) != 0);
}

static int output_check_path(char *path, size_t capacity, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(path, capacity, "%s/%s/%s%s", set, sample, sample, suffix);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

// the next line, its line feed taken off, into text->line; 0 at the file's end
static int output_check_next(OutputCheckText *text)
{
    text->length = 0u;
    int any = 0;
    for (;;)
    {
        if (text->at == text->size)
        {
            text->size = text->ended ? 0u : fread(text->chunk, 1u, OUTPUT_CHECK_CHUNK, text->file);
            text->at = 0u;
            text->ended = text->ended || (text->size == 0u);
            if (text->size == 0u)
            {
                text->lines += any ? 1ull : 0ull;
                return any;
            }
            text->bytes += text->size;
            for (size_t at = 0u; at < text->size; at += 1u)
            {
                text->feeds += (text->chunk[at] == '\n') ? 1ull : 0ull;
                text->returns += (text->chunk[at] == '\r') ? 1ull : 0ull;
            }
        }
        const unsigned char *const start = &text->chunk[text->at];
        const unsigned char *const feed = (const unsigned char *)memchr(start, '\n', text->size - text->at);
        const size_t taken = (feed != NULL) ? (size_t)(feed - start) : (text->size - text->at);
        if ((text->length + taken + 1u) > text->capacity)
        {
            const size_t capacity = 2u * (text->length + taken + 1u);
            char *const grown = (char *)realloc(text->line, capacity);
            if (grown == NULL)
            {
                printf("  %s: a line's memory could not be reserved\n", text->name);
                return 0;
            }
            text->line = grown;
            text->capacity = capacity;
        }
        memcpy(&text->line[text->length], start, taken);
        text->length += taken;
        text->line[text->length] = '\0';
        any = 1;
        text->at += taken + ((feed != NULL) ? 1u : 0u);
        if (feed != NULL)
        {
            text->lines += 1ull;
            return 1;
        }
    }
}

static int output_check_open(OutputCheckText *text, const char *name)
{
    memset(text, 0, sizeof(*text));
    text->name = name;
    text->file = fopen(name, "rb");
    text->chunk = (unsigned char *)malloc(OUTPUT_CHECK_CHUNK);
    text->capacity = OUTPUT_CHECK_ROW;
    text->line = (char *)malloc(text->capacity);
    return (text->file != NULL) && (text->chunk != NULL) && (text->line != NULL);
}

static void output_check_close(OutputCheckText *text)
{
    if (text->file != NULL)
    {
        fclose(text->file);
    }
    free(text->chunk);
    free(text->line);
    text->file = NULL;
    text->chunk = NULL;
    text->line = NULL;
}

// the file's next row against the rebuilt one; `number` is the row's line in the file, counting from 1
static void output_check_row(OutputCheckText *text, const char *expected, size_t length)
{
    if (output_check_next(text) == 0)
    {
        text->missing += 1ull;
        return;
    }
    text->compared += 1ull;
    const int same = (text->length == length) && (memcmp(text->line, expected, length) == 0);
    if (same == 0)
    {
        text->differing += 1ull;
        if (text->differing <= OUTPUT_CHECK_SHOWN)
        {
            printf("  %s line %llu reads:\n    %s\n  and was rebuilt as:\n    %s\n", text->name, text->lines,
                   text->line, expected);
        }
    }
}

static int output_check_reserve(OutputCheckGraph *graph, unsigned long long points, unsigned int frames)
{
    if (((size_t)frames + 2u) > graph->first_capacity)
    {
        unsigned long long *const first =
            (unsigned long long *)realloc(graph->first, ((size_t)frames + 2u) * sizeof(unsigned long long));
        graph->first = (first != NULL) ? first : graph->first;
        graph->first_capacity = (first != NULL) ? ((size_t)frames + 2u) : graph->first_capacity;
    }
    if ((points > (SIZE_MAX / sizeof(unsigned long long))) || ((size_t)frames + 2u) > graph->first_capacity)
    {
        return 0;
    }
    if ((size_t)points <= graph->capacity)
    {
        return 1;
    }
    const size_t capacity = ((size_t)points > (2u * graph->capacity)) ? (size_t)points : (2u * graph->capacity);
    unsigned int *const voxels = (unsigned int *)realloc(graph->voxels, (capacity + 1u) * sizeof(unsigned int));
    graph->voxels = (voxels != NULL) ? voxels : graph->voxels;
    unsigned int *const forward = (unsigned int *)realloc(graph->forward, (capacity + 1u) * sizeof(unsigned int));
    graph->forward = (forward != NULL) ? forward : graph->forward;
    unsigned int *const second = (unsigned int *)realloc(graph->second, (capacity + 1u) * sizeof(unsigned int));
    graph->second = (second != NULL) ? second : graph->second;
    unsigned int *const backward = (unsigned int *)realloc(graph->backward, (capacity + 1u) * sizeof(unsigned int));
    graph->backward = (backward != NULL) ? backward : graph->backward;
    unsigned long long *const cost =
        (unsigned long long *)realloc(graph->cost, (capacity + 1u) * sizeof(unsigned long long));
    graph->cost = (cost != NULL) ? cost : graph->cost;
    unsigned int *const ahead = (unsigned int *)realloc(graph->ahead, (capacity + 1u) * sizeof(unsigned int));
    graph->ahead = (ahead != NULL) ? ahead : graph->ahead;
    unsigned int *const outside = (unsigned int *)realloc(graph->outside, (capacity + 1u) * sizeof(unsigned int));
    graph->outside = (outside != NULL) ? outside : graph->outside;
    unsigned int *const faces = (unsigned int *)realloc(graph->faces, (capacity + 1u) * sizeof(unsigned int));
    graph->faces = (faces != NULL) ? faces : graph->faces;
    const int ok = (voxels != NULL) && (forward != NULL) && (second != NULL) && (backward != NULL) && (cost != NULL) &&
                   (ahead != NULL) && (outside != NULL) && (faces != NULL);
    graph->capacity = ok ? capacity : graph->capacity;
    return ok;
}

// a fault in the graph, named and counted
static void output_check_fault(OutputCheckGraph *graph, const char *sample, const char *what, unsigned int frame)
{
    graph->faults += 1ull;
    printf("  %s: frame %u: %s\n", sample, frame, what);
}

// the faces `place` crosses on `axis` (z 0, y 1, x 2) of `extent`: below 0 the low face, bit 1 << 2 axis, and at or
// past the extent the high, bit 2 << 2 axis
static unsigned int output_check_crossed(unsigned int axis, long long place, long long extent)
{
    return ((place < 0ll) ? (1u << (2u * axis)) : 0u) | ((place >= extent) ? (2u << (2u * axis)) : 0u);
}

// the sample's .points: its head and each frame's voxels, the levels passed over
static int output_check_points(const char *set, const char *sample, OutputCheckGraph *graph)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".points") ? fopen(path, "rb") : NULL;
    // the readings and C, passed over
    unsigned long long *const skipped =
        (unsigned long long *)malloc((1u + OUTPUT_CHECK_READINGS) * sizeof(unsigned long long));
    memset(graph->head, 0, sizeof(graph->head));
    int ok = (file != NULL) && (skipped != NULL) && output_check_read(file, graph->head, sizeof(graph->head)) &&
             output_check_read(file, skipped, (1u + OUTPUT_CHECK_READINGS) * sizeof(unsigned long long));
    free(skipped);
    const unsigned long long view = (unsigned long long)graph->head[1] * graph->head[2] * graph->head[3];
    graph->points = 0ull;
    ok = ok && output_check_reserve(graph, 0ull, graph->head[0]);
    unsigned int *levels = NULL;
    size_t level_capacity = 0u;
    for (unsigned int frame = 0u; ok && (frame < graph->head[0]); frame += 1u)
    {
        unsigned int count = 0u;
        graph->first[frame] = graph->points;
        ok = output_check_read(file, &count, sizeof(count)) && ((unsigned long long)count <= view) &&
             output_check_reserve(graph, graph->points + count, graph->head[0]) &&
             output_check_read(file, &graph->voxels[graph->points], (size_t)count * sizeof(unsigned int));
        const size_t words = (size_t)count * graph->head[4];
        if (ok && (words > level_capacity))
        {
            unsigned int *const grown = (unsigned int *)realloc(levels, (words + 1u) * sizeof(unsigned int));
            levels = (grown != NULL) ? grown : levels;
            level_capacity = (grown != NULL) ? words : level_capacity;
        }
        ok = ok && (words <= level_capacity) && output_check_read(file, levels, words * sizeof(unsigned int));
        for (unsigned int point = 0u; ok && (point < count); point += 1u)
        {
            const unsigned long long at = graph->points + point;
            if ((unsigned long long)graph->voxels[at] >= view)
            {
                output_check_fault(graph, sample, "a voxel lies outside the view", frame);
            }
            graph->forward[at] = OUTPUT_CHECK_NONE;
            graph->second[at] = OUTPUT_CHECK_NONE;
            graph->backward[at] = OUTPUT_CHECK_NONE;
            graph->cost[at] = 0ull;
            graph->ahead[at] = 0u;
            graph->outside[at] = 0u;
            graph->faces[at] = 0u;
        }
        graph->points += ok ? count : 0u;
    }
    if (ok)
    {
        graph->first[graph->head[0]] = graph->points;
    }
    ok = ok && output_check_ended(file);
    if (file != NULL)
    {
        fclose(file);
    }
    free(levels);
    if (ok == 0)
    {
        printf("  %s: its .points does not open, stops short, or goes on past its last frame\n", sample);
        graph->faults += 1ull;
    }
    return ok;
}

// the sample's .links: each pair's chosen links, checked against the points
static int output_check_links(const char *set, const char *sample, OutputCheckGraph *graph)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".links") ? fopen(path, "rb") : NULL;
    unsigned int head[OUTPUT_CHECK_LINKS_HEAD];
    int ok = (file != NULL) && output_check_read(file, head, sizeof(head));
    if (ok && (memcmp(head, graph->head, 4u * sizeof(unsigned int)) != 0))
    {
        output_check_fault(graph, sample, "the .links' frames or view are not the .points'", 0u);
        ok = 0;
    }
    unsigned int words[OUTPUT_CHECK_GATE_WORDS];
    for (unsigned int frame = 0u; ok && ((frame + 1u) < graph->head[0]); frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long next = graph->first[frame + 1u];
        const unsigned long long sources = next - now;
        const unsigned long long targets = graph->first[frame + 2u] - next;
        unsigned int record[OUTPUT_CHECK_PAIR_WORDS];
        ok = output_check_read(file, record, sizeof(record));
        if (ok && ((record[0] != sources) || (record[1] != targets)))
        {
            output_check_fault(graph, sample, "the pair record's sources or targets are not the frames' points", frame);
            ok = 0;
        }
        for (unsigned int source = 0u; ok && (source < record[0]); source += 1u)
        {
            ok = output_check_read(file, words, OUTPUT_CHECK_SOURCE_WORDS * sizeof(unsigned int));
            unsigned int ahead = 0u;
            for (unsigned int axis = 0u; ok && (axis < OUTPUT_CHECK_AXES); axis += 1u)
            {
                // a prediction is written as its two's complement word
                ahead |= output_check_crossed(axis, (long long)(int)words[axis], (long long)graph->head[1u + axis]);
            }
            graph->ahead[now + source] = ok ? ahead : 0u;
            graph->outside[now + source] = (ok && ((words[3] & OUTPUT_CHECK_OUTSIDE) != 0u)) ? 1u : 0u;
        }
        unsigned int chosen = 0u;
        for (unsigned int pair = 0u; ok && (pair < record[2]); pair += 1u)
        {
            ok = output_check_read(file, words, OUTPUT_CHECK_GATE_WORDS * sizeof(unsigned int));
            if ((ok == 0) || ((words[6] & OUTPUT_CHECK_CHOSEN) == 0u))
            {
                continue;
            }
            chosen += 1u;
            if ((words[0] >= record[0]) || (words[1] >= record[1]))
            {
                output_check_fault(graph, sample, "a chosen link lies past the frames' points", frame);
                continue;
            }
            if (graph->forward[now + words[0]] != OUTPUT_CHECK_NONE)
            {
                output_check_fault(graph, sample, "a point has two chosen links out", frame);
            }
            if (graph->backward[next + words[1]] != OUTPUT_CHECK_NONE)
            {
                output_check_fault(graph, sample, "a point has two chosen links in", frame + 1u);
            }
            graph->forward[now + words[0]] = words[1];
            graph->backward[next + words[1]] = words[0];
            graph->cost[now + words[0]] = (unsigned long long)words[2] | ((unsigned long long)words[3] << 32u);
        }
        if (ok && (chosen != record[4]))
        {
            output_check_fault(graph, sample, "the pair's chosen links are not its record's count", frame);
        }
    }
    ok = ok && output_check_ended(file);
    if (file != NULL)
    {
        fclose(file);
    }
    if (ok == 0)
    {
        printf("  %s: its .links does not open, stops short, disagrees with its .points, or goes on past its last"
               " frame\n",
               sample);
        graph->faults += 1ull;
    }
    return ok;
}

// the whole file's CRC-64/XZ, a bit at a time from the polynomial; 0 when the file does not read whole
static int output_check_crc(const char *path, unsigned long long *crc)
{
    FILE *const file = fopen(path, "rb");
    unsigned char *const chunk = (unsigned char *)malloc(OUTPUT_CHECK_CHUNK);
    unsigned long long table[256];
    for (unsigned int byte = 0u; byte < 256u; byte += 1u)
    {
        unsigned long long value = byte;
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            value = ((value & 1ull) != 0ull) ? ((value >> 1u) ^ OUTPUT_CHECK_POLYNOMIAL) : (value >> 1u);
        }
        table[byte] = value;
    }
    unsigned long long running = ~0ull;
    size_t read = 0u;
    do
    {
        read = ((file != NULL) && (chunk != NULL)) ? fread(chunk, 1u, OUTPUT_CHECK_CHUNK, file) : 0u;
        for (size_t at = 0u; at < read; at += 1u)
        {
            running = table[(running ^ chunk[at]) & 0xFFull] ^ (running >> 8u);
        }
    } while (read == OUTPUT_CHECK_CHUNK);
    const int complete = (file != NULL) && (chunk != NULL) && (ferror(file) == 0) && (feof(file) != 0);
    if (file != NULL)
    {
        fclose(file);
    }
    free(chunk);
    *crc = ~running;
    return complete;
}

// the CRC-64 of the sample's .links, read once for its .faces and its .divide; 0 when the .links does not read whole
static int output_check_links_crc(const char *set, const char *sample, OutputCheckGraph *graph)
{
    if (graph->summed == 0)
    {
        char path[OUTPUT_CHECK_PATH];
        const int complete =
            output_check_path(path, sizeof(path), set, sample, ".links") && output_check_crc(path, &graph->crc);
        graph->summed = complete ? 1 : -1;
    }
    return graph->summed == 1;
}

// `bytes` of the file read and passed over through `chunk`, which holds OUTPUT_CHECK_CHUNK bytes
static int output_check_pass(FILE *file, unsigned long long bytes, unsigned char *chunk)
{
    while (bytes > 0ull)
    {
        const size_t taken = (bytes < OUTPUT_CHECK_CHUNK) ? (size_t)bytes : OUTPUT_CHECK_CHUNK;
        if (fread(chunk, 1u, taken, file) != taken)
        {
            return 0;
        }
        bytes -= taken;
    }
    return 1;
}

// the sample's .drift: its head against the .points' frames and view, and each frame's lag onto it (0 at frame 0) into
// `lags`, three a frame; the file ended at its last frame
static int output_check_drift(const char *set, const char *sample, OutputCheckGraph *graph, int *lags)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".drift") ? fopen(path, "rb") : NULL;
    unsigned int head[OUTPUT_CHECK_DRIFT_HEAD];
    int ok = (file != NULL) && output_check_read(file, head, sizeof(head));
    if (ok && (memcmp(head, graph->head, 4u * sizeof(unsigned int)) != 0))
    {
        output_check_fault(graph, sample, "the .drift's frames or view are not the .points'", 0u);
        ok = 0;
    }
    for (unsigned int frame = 0u; ok && (frame < graph->head[0]); frame += 1u)
    {
        unsigned int positives = 0u;
        unsigned int agreement = 0u;
        int *const lag = &lags[OUTPUT_CHECK_AXES * (size_t)frame];
        memset(lag, 0, OUTPUT_CHECK_AXES * sizeof(int));
        ok = output_check_read(file, &positives, sizeof(positives)) &&
             ((frame == 0u) || (output_check_read(file, lag, OUTPUT_CHECK_AXES * sizeof(int)) &&
                                output_check_read(file, &agreement, sizeof(agreement))));
    }
    ok = ok && output_check_ended(file);
    if (file != NULL)
    {
        fclose(file);
    }
    if (ok == 0)
    {
        printf("  %s: its .drift does not open, stops short, disagrees with its .points, or goes on past its last"
               " frame\n",
               sample);
    }
    return ok;
}

// the sample's .shape: its head against the .points' frames, view and limbs, and each point's faces into
// graph->faces, the differences passed over; each frame counts its points, each point's faces are among the six, and
// the file ends at its last frame
static int output_check_hessian(const char *set, const char *sample, OutputCheckGraph *graph, unsigned char *chunk)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".shape") ? fopen(path, "rb") : NULL;
    unsigned int head[OUTPUT_CHECK_HESSIAN_HEAD];
    int ok = (file != NULL) && output_check_read(file, head, sizeof(head));
    if (ok && ((memcmp(head, graph->head, 4u * sizeof(unsigned int)) != 0) || (head[4] != graph->head[4]) ||
               ((unsigned long long)head[5] != ((unsigned long long)graph->head[4] + 1ull))))
    {
        output_check_fault(graph, sample, "the .shape's frames, view or limbs are not the .points'", 0u);
        ok = 0;
    }
    // a point's differences, in words: six of the shape's limbs, below 6 x 2^32
    const unsigned long long differences = (unsigned long long)OUTPUT_CHECK_HESSIAN_ENTRIES * head[5];
    for (unsigned int frame = 0u; ok && (frame < graph->head[0]); frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long points = graph->first[frame + 1u] - now;
        unsigned int count = 0u;
        ok = output_check_read(file, &count, sizeof(count));
        if (ok && (count != points))
        {
            output_check_fault(graph, sample, "the .shape's count is not the frame's points", frame);
            ok = 0;
        }
        const int fits = (count == 0u) || (differences <= ((0x7FFFFFFFFFFFFFFFull / 4ull) / count));
        ok = ok && fits && output_check_read(file, &graph->faces[now], (size_t)count * sizeof(unsigned int)) &&
             output_check_pass(file, (unsigned long long)count * differences * 4ull, chunk);
        for (unsigned long long point = now; ok && (point < (now + count)); point += 1ull)
        {
            if ((graph->faces[point] & ~OUTPUT_CHECK_SIX) != 0u)
            {
                output_check_fault(graph, sample, "a point's .shape faces are not among the six", frame);
                ok = 0;
            }
        }
    }
    ok = ok && output_check_ended(file);
    if (file != NULL)
    {
        fclose(file);
    }
    if (ok == 0)
    {
        printf("  %s: its .shape does not open, stops short, disagrees with its .points, or goes on past its last"
               " frame\n",
               sample);
    }
    return ok;
}

// each point's .faces words as this reader makes them from the graph as the .links gave it, before any .divide, the
// lags and the .shape's faces in graph->faces; the flags go back into graph->faces. Each .links outside flag must be
// its prediction's. `words` holds OUTPUT_CHECK_FACES_WORDS a point
static int output_check_rebuild(const char *sample, OutputCheckGraph *graph, const int *lags, unsigned int *words)
{
    const unsigned long long plane = (unsigned long long)graph->head[2] * graph->head[3];
    const unsigned long long width = graph->head[3];
    const long long extent[OUTPUT_CHECK_AXES] = {graph->head[1], graph->head[2], graph->head[3]};
    for (unsigned int frame = 0u; frame < graph->head[0]; frame += 1u)
    {
        const int later = (frame + 1u) < graph->head[0];
        for (unsigned long long point = graph->first[frame]; point < graph->first[frame + 1u]; point += 1ull)
        {
            const unsigned long long voxel = graph->voxels[point];
            const long long place[OUTPUT_CHECK_AXES] = {
                (long long)(voxel / plane), (long long)((voxel % plane) / width), (long long)(voxel % width)};
            const unsigned int onto = graph->forward[point];
            const int carried = (frame != 0u) && later && (onto != OUTPUT_CHECK_NONE);
            long long target[OUTPUT_CHECK_AXES] = {0ll, 0ll, 0ll};
            if (carried)
            {
                const unsigned long long reached = graph->voxels[graph->first[frame + 1u] + onto];
                target[0] = (long long)(reached / plane);
                target[1] = (long long)((reached % plane) / width);
                target[2] = (long long)(reached % width);
            }
            unsigned int back = 0u;
            unsigned int *const word = &words[OUTPUT_CHECK_FACES_WORDS * point];
            for (unsigned int axis = 0u; axis < OUTPUT_CHECK_AXES; axis += 1u)
            {
                long long backward = place[axis];
                if (frame != 0u)
                {
                    backward -= lags[(OUTPUT_CHECK_AXES * (size_t)frame) + axis];
                }
                if (carried)
                {
                    // the link's motion less the drift onto its target's frame
                    backward -= target[axis] - place[axis] - lags[(OUTPUT_CHECK_AXES * ((size_t)frame + 1u)) + axis];
                }
                if ((backward < -0x80000000ll) || (backward > 0x7FFFFFFFll))
                {
                    output_check_fault(graph, sample, "a point's back-prediction passes 32 bits", frame);
                    return 0;
                }
                // a back-prediction held in [-2^31, 2^31) is written as its two's complement word
                word[axis] = (unsigned int)(int)backward;
                back |= output_check_crossed(axis, backward, extent[axis]);
            }
            const unsigned int ahead = later ? graph->ahead[point] : 0u;
            if (later && ((ahead != 0u) != (graph->outside[point] != 0u)))
            {
                output_check_fault(graph, sample, "a .links outside flag is not its prediction's", frame);
                return 0;
            }
            const int start = (frame != 0u) && (graph->backward[point] == OUTPUT_CHECK_NONE);
            const int end = later && (onto == OUTPUT_CHECK_NONE);
            unsigned int flags = (back << OUTPUT_CHECK_BACK_SHIFT) | (ahead << OUTPUT_CHECK_AHEAD_SHIFT) |
                                 (graph->faces[point] << OUTPUT_CHECK_HESSIAN_SHIFT);
            flags |= (frame == 0u) ? OUTPUT_CHECK_FIRST : 0u;
            flags |= later ? 0u : OUTPUT_CHECK_LAST;
            flags |= carried ? OUTPUT_CHECK_CARRIED : 0u;
            flags |= (start && (back != 0u)) ? OUTPUT_CHECK_ENTERING : 0u;
            flags |= (end && (ahead != 0u)) ? OUTPUT_CHECK_LEAVING : 0u;
            word[OUTPUT_CHECK_AXES] = flags;
            graph->faces[point] = flags;
        }
    }
    return 1;
}

// the sample's .faces, when there is one: its head against the .points' frames and view and the CRC-64 of the .links
// beside it, then each point's words against those rebuilt from the .points, the .drift, the .shape and the .links
// (output_check_rebuild), the file ended at its last frame. A .faces that does not open is none, and every point's
// flags stay 0
static int output_check_faces(const char *set, const char *sample, OutputCheckGraph *graph)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".faces") ? fopen(path, "rb") : NULL;
    graph->faced = 0;
    if (file == NULL)
    {
        return 1;
    }
    graph->faced = 1;
    unsigned int head[OUTPUT_CHECK_FACES_HEAD];
    int ok = output_check_read(file, head, sizeof(head));
    if (ok && (memcmp(head, graph->head, 4u * sizeof(unsigned int)) != 0))
    {
        output_check_fault(graph, sample, "the .faces' frames or view are not the .points'", 0u);
        ok = 0;
    }
    if (ok && ((output_check_links_crc(set, sample, graph) == 0) ||
               (graph->crc != ((unsigned long long)head[4] | ((unsigned long long)head[5] << 32u)))))
    {
        output_check_fault(graph, sample, "the .faces was not made from the .links beside it: the CRC-64 differs", 0u);
        ok = 0;
    }
    int *const lags = (int *)malloc(((size_t)graph->head[0] + 1u) * OUTPUT_CHECK_AXES * sizeof(int));
    unsigned char *const chunk = (unsigned char *)malloc(OUTPUT_CHECK_CHUNK);
    unsigned int *const rebuilt =
        (unsigned int *)malloc(((size_t)graph->points + 1u) * OUTPUT_CHECK_FACES_WORDS * sizeof(unsigned int));
    ok = ok && (lags != NULL) && (chunk != NULL) && (rebuilt != NULL) && output_check_drift(set, sample, graph, lags) &&
         output_check_hessian(set, sample, graph, chunk) && output_check_rebuild(sample, graph, lags, rebuilt);
    for (unsigned int frame = 0u; ok && (frame < graph->head[0]); frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long points = graph->first[frame + 1u] - now;
        unsigned int count = 0u;
        ok = output_check_read(file, &count, sizeof(count));
        if (ok && (count != points))
        {
            output_check_fault(graph, sample, "the .faces' count is not the frame's points", frame);
            ok = 0;
        }
        for (unsigned long long point = now; ok && (point < (now + count)); point += 1ull)
        {
            unsigned int words[OUTPUT_CHECK_FACES_WORDS];
            ok = output_check_read(file, words, sizeof(words));
            const unsigned int *const expected = &rebuilt[OUTPUT_CHECK_FACES_WORDS * point];
            if (ok && (memcmp(words, expected, sizeof(words)) != 0))
            {
                printf("  %s: frame %u: point %llu of its .faces reads (%d, %d, %d) %08X, and was rebuilt as (%d, %d,"
                       " %d) %08X\n",
                       sample, frame, point - now, (int)words[0], (int)words[1], (int)words[2], words[3],
                       (int)expected[0], (int)expected[1], (int)expected[2], expected[3]);
                output_check_fault(graph, sample,
                                   (memcmp(words, expected, 3u * sizeof(unsigned int)) != 0)
                                       ? "a point's back-prediction is not the one rebuilt"
                                       : "a point's flags are not the ones rebuilt",
                                   frame);
                ok = 0;
            }
        }
    }
    ok = ok && output_check_ended(file);
    fclose(file);
    free(lags);
    free(chunk);
    free(rebuilt);
    if (ok == 0)
    {
        printf("  %s: its .faces stops short, breaks a rule above, or goes on past its last frame\n", sample);
        graph->faults += 1ull;
    }
    return ok;
}

// the sample's .divide, when there is one: its head, then each division checked against the graph as it stands and
// made. A .divide that does not open is none
static int output_check_divide(const char *set, const char *sample, OutputCheckGraph *graph)
{
    char path[OUTPUT_CHECK_PATH];
    FILE *const file = output_check_path(path, sizeof(path), set, sample, ".divide") ? fopen(path, "rb") : NULL;
    graph->divisions = 0ull;
    graph->moved = 0ull;
    if (file == NULL)
    {
        return 1;
    }
    unsigned int head[OUTPUT_CHECK_DIVIDE_HEAD];
    int ok = output_check_read(file, head, sizeof(head));
    if (ok && (memcmp(head, graph->head, 4u * sizeof(unsigned int)) != 0))
    {
        output_check_fault(graph, sample, "the .divide's frames or view are not the .points'", 0u);
        ok = 0;
    }
    if (ok && ((output_check_links_crc(set, sample, graph) == 0) ||
               (graph->crc != ((unsigned long long)head[4] | ((unsigned long long)head[5] << 32u)))))
    {
        output_check_fault(graph, sample, "the .divide was not made from the .links beside it: the CRC-64 differs", 0u);
        ok = 0;
    }
    for (unsigned int frame = 0u; ok && ((frame + 1u) < graph->head[0]); frame += 1u)
    {
        const unsigned long long now = graph->first[frame];
        const unsigned long long next = graph->first[frame + 1u];
        const unsigned long long sources = next - now;
        const unsigned long long targets = graph->first[frame + 2u] - next;
        unsigned int count = 0u;
        ok = output_check_read(file, &count, sizeof(count)) && ((unsigned long long)count <= sources);
        long long previous = -1ll;
        for (unsigned int at = 0u; ok && (at < count); at += 1u)
        {
            unsigned int words[OUTPUT_CHECK_DIVISION_WORDS];
            ok = output_check_read(file, words, sizeof(words));
            if (ok == 0)
            {
                break;
            }
            const unsigned int parent = words[0];
            const unsigned int one = words[1];
            const unsigned int two = words[2];
            const unsigned int left = words[3];
            const char *fault = NULL;
            if (((unsigned long long)parent >= sources) || ((long long)parent <= previous))
            {
                fault = "a division's parent lies past the frame's points or out of order";
            }
            else if ((graph->forward[now + parent] == OUTPUT_CHECK_NONE) || (graph->forward[now + parent] != one))
            {
                fault = "a division's daughter one is not its parent's link";
            }
            else if (((unsigned long long)two >= targets) || (two == one))
            {
                fault = "a division's daughter two lies past the frame's points or is daughter one";
            }
            else if (graph->backward[next + two] != left)
            {
                fault = "a division's daughter two does not come from the point it names";
            }
            else if ((left != OUTPUT_CHECK_NONE) && (graph->second[now + left] != OUTPUT_CHECK_NONE))
            {
                fault = "a division takes daughter two from a point that divides";
            }
            if (fault != NULL)
            {
                output_check_fault(graph, sample, fault, frame);
                ok = 0;
                break;
            }
            if (left != OUTPUT_CHECK_NONE)
            {
                graph->forward[now + left] = OUTPUT_CHECK_NONE;
                graph->cost[now + left] = 0ull;
                graph->moved += 1ull;
            }
            graph->second[now + parent] = two;
            graph->backward[next + two] = parent;
            graph->divisions += 1ull;
            previous = (long long)parent;
        }
    }
    ok = ok && output_check_ended(file);
    fclose(file);
    if (ok == 0)
    {
        printf("  %s: its .divide stops short, breaks a rule above, or goes on past its last frame pair\n", sample);
        graph->faults += 1ull;
    }
    return ok;
}

// every rebuilt row of the sample, each checked against the files' next rows; `row` is the submission's running id
static void output_check_rows(const char *sample, const OutputCheckGraph *graph, OutputCheckText *nodes,
                              OutputCheckText *submission, unsigned long long *row)
{
    char expected[OUTPUT_CHECK_ROW];
    const unsigned long long plane = (unsigned long long)graph->head[2] * graph->head[3];
    const unsigned long long width = graph->head[3];
    for (unsigned int frame = 0u; frame < graph->head[0]; frame += 1u)
    {
        for (unsigned long long point = graph->first[frame]; point < graph->first[frame + 1u]; point += 1u)
        {
            const unsigned long long voxel = graph->voxels[point];
            const unsigned long long z = voxel / plane;
            const unsigned long long y = (voxel % plane) / width;
            const unsigned long long x = voxel % width;
            const unsigned long long leaf = point - graph->first[frame];
            const long long forward =
                (graph->forward[point] != OUTPUT_CHECK_NONE) ? (long long)graph->forward[point] : -1ll;
            const long long backward =
                (graph->backward[point] != OUTPUT_CHECK_NONE) ? (long long)graph->backward[point] : -1ll;
            const int links = ((forward >= 0ll) ? 1 : 0) + ((graph->second[point] != OUTPUT_CHECK_NONE) ? 1 : 0);
            long long split_from = -1ll;
            if ((frame > 0u) && (backward >= 0ll) &&
                (graph->second[graph->first[frame - 1u] + (unsigned long long)backward] == (unsigned int)leaf))
            {
                split_from = backward;
            }
            // a start and an end are the graph's as it stands, after any .divide
            const int start = (frame != 0u) && (backward < 0ll);
            const int end = ((frame + 1u) < graph->head[0]) && (forward < 0ll);
            const unsigned int faces = graph->faces[point];
            const unsigned int state =
                ((split_from >= 0ll) ? OUTPUT_CHECK_STATE_SPLIT : 0u) |
                ((start && (((faces >> OUTPUT_CHECK_BACK_SHIFT) & OUTPUT_CHECK_SIX) != 0u)) ? OUTPUT_CHECK_STATE_ENTERED
                                                                                            : 0u) |
                ((end && (((faces >> OUTPUT_CHECK_AHEAD_SHIFT) & OUTPUT_CHECK_SIX) != 0u)) ? OUTPUT_CHECK_STATE_LEFT
                                                                                           : 0u);
            int length = snprintf(expected, sizeof(expected),
                                  "%s\t%u\t%llu\t%llu\t%llu\t%llu\t0\t%llu\t1\t%lld\t%llu\t0\t%lld\t%d\t0\t0\t0\t-1\t0"
                                  "\t%lld\t%llu\t%u\t-1\t0\t%lld",
                                  sample, frame, leaf, z, y, x, leaf, forward, graph->cost[point], forward, links,
                                  backward, point + 1ull, state, split_from);
            output_check_row(nodes, expected, (length > 0) ? (size_t)length : 0u);
            length = snprintf(expected, sizeof(expected), "%llu,%s,node,%llu,%u,%llu,%llu,%llu,-1,-1", *row, sample,
                              point + 1ull, frame, z, y, x);
            output_check_row(submission, expected, (length > 0) ? (size_t)length : 0u);
            *row += 1ull;
        }
    }
    for (unsigned int frame = 0u; (frame + 1u) < graph->head[0]; frame += 1u)
    {
        for (unsigned long long point = graph->first[frame]; point < graph->first[frame + 1u]; point += 1u)
        {
            const unsigned int targets[2] = {graph->forward[point], graph->second[point]};
            for (unsigned int at = 0u; at < 2u; at += 1u)
            {
                if (targets[at] == OUTPUT_CHECK_NONE)
                {
                    continue;
                }
                const int length = snprintf(expected, sizeof(expected), "%llu,%s,edge,-1,-1,-1,-1,-1,%llu,%llu", *row,
                                            sample, point + 1ull, graph->first[frame + 1u] + targets[at] + 1ull);
                output_check_row(submission, expected, (length > 0) ? (size_t)length : 0u);
                *row += 1ull;
            }
        }
    }
}

static void output_check_report(OutputCheckText *text)
{
    unsigned long long extra = 0ull;
    while (output_check_next(text))
    {
        extra += 1ull;
    }
    printf("  %s: %llu bytes, %llu LF, %llu CR, %llu lines; %llu rows checked against the rebuilt, %llu differ, %llu"
           " missing, %llu past the rebuilt\n",
           text->name, text->bytes, text->feeds, text->returns, text->lines, text->compared, text->differing,
           text->missing, extra);
    text->missing += extra;
}

int main(int count, char **arguments)
{
    const uint32_t probe = 1u;
    if (*(const unsigned char *)&probe != 1u)
    {
        printf("  this host is not little-endian, and the files are\n");
        return 2;
    }
    if (count < 5)
    {
        printf("  usage: output_check <set> <nodes.tsv> <submission.csv> <sample> [<sample> ...]\n");
        return 2;
    }
    const char *const set = arguments[1];
    OutputCheckText nodes;
    OutputCheckText submission;
    // both are opened, and so both are set, before either is closed
    const int nodes_opened = output_check_open(&nodes, arguments[2]);
    const int submission_opened = output_check_open(&submission, arguments[3]);
    const int opened = nodes_opened && submission_opened;
    if (opened == 0)
    {
        printf("  the nodes or the submission does not open\n");
        output_check_close(&nodes);
        output_check_close(&submission);
        return 1;
    }
    output_check_row(&nodes, OUTPUT_CHECK_NODES_HEADER, sizeof(OUTPUT_CHECK_NODES_HEADER) - 1u);
    output_check_row(&submission, OUTPUT_CHECK_SUBMISSION_HEADER, sizeof(OUTPUT_CHECK_SUBMISSION_HEADER) - 1u);
    OutputCheckGraph graph;
    memset(&graph, 0, sizeof(graph));
    unsigned long long row = 0ull;
    unsigned long long frames = 0ull;
    unsigned long long points = 0ull;
    unsigned long long edges = 0ull;
    unsigned long long divisions = 0ull;
    unsigned long long moved = 0ull;
    unsigned long long faults = 0ull;
    unsigned int read = 0u;
    // the samples with a .faces, and on the graphs as they stand their starts and ends and those crossing a face
    unsigned int faced = 0u;
    unsigned long long totals[4] = {0ull, 0ull, 0ull, 0ull};
    printf("  %-16s %6s %10s %10s %s\n", "sample", "frames", "nodes", "edges",
           "faults in its graph; divisions (moving a link)");
    for (int at = 4; at < count; at += 1)
    {
        const char *const sample = arguments[at];
        graph.faults = 0ull;
        graph.divisions = 0ull;
        graph.moved = 0ull;
        graph.summed = 0;
        graph.faced = 0;
        const int complete = output_check_points(set, sample, &graph) && output_check_links(set, sample, &graph) &&
                             output_check_faces(set, sample, &graph) && output_check_divide(set, sample, &graph);
        unsigned long long linked = 0ull;
        // starts, those entering the view, ends, those leaving it
        unsigned long long crossed[4] = {0ull, 0ull, 0ull, 0ull};
        for (unsigned int frame = 0u; complete && (frame < graph.head[0]); frame += 1u)
        {
            for (unsigned long long point = graph.first[frame]; point < graph.first[frame + 1u]; point += 1ull)
            {
                linked += (graph.forward[point] != OUTPUT_CHECK_NONE) ? 1ull : 0ull;
                linked += (graph.second[point] != OUTPUT_CHECK_NONE) ? 1ull : 0ull;
                const unsigned long long start =
                    ((frame != 0u) && (graph.backward[point] == OUTPUT_CHECK_NONE)) ? 1ull : 0ull;
                const unsigned long long end =
                    (((frame + 1u) < graph.head[0]) && (graph.forward[point] == OUTPUT_CHECK_NONE)) ? 1ull : 0ull;
                crossed[0] += start;
                crossed[1] +=
                    (((graph.faces[point] >> OUTPUT_CHECK_BACK_SHIFT) & OUTPUT_CHECK_SIX) != 0u) ? start : 0ull;
                crossed[2] += end;
                crossed[3] +=
                    (((graph.faces[point] >> OUTPUT_CHECK_AHEAD_SHIFT) & OUTPUT_CHECK_SIX) != 0u) ? end : 0ull;
            }
        }
        printf("  %-16s %6u %10llu %10llu %llu; %llu (%llu)\n", sample, graph.head[0], graph.points, linked,
               graph.faults, graph.divisions, graph.moved);
        faults += graph.faults;
        if (complete == 0)
        {
            continue;
        }
        if (graph.faced)
        {
            printf("  %-16s its .faces: %llu of its %llu starts enter the view, %llu of its %llu ends leave it\n",
                   sample, crossed[1], crossed[0], crossed[3], crossed[2]);
            faced += 1u;
            for (unsigned int kind = 0u; kind < 4u; kind += 1u)
            {
                totals[kind] += crossed[kind];
            }
        }
        read += 1u;
        frames += graph.head[0];
        points += graph.points;
        edges += linked;
        divisions += graph.divisions;
        moved += graph.moved;
        output_check_rows(sample, &graph, &nodes, &submission, &row);
    }
    printf("  rebuilt %u of %d samples: %llu frames, %llu nodes, %llu edges, %llu divisions (%llu moving a link); %llu"
           " faults in the graphs; the nodes should hold %llu rows after the header, the submission %llu\n",
           read, count - 4, frames, points, edges, divisions, moved, faults, points, row);
    if (faced != 0u)
    {
        printf("  %u of them with a .faces: %llu of their %llu starts enter the view, %llu of their %llu ends leave"
               " it\n",
               faced, totals[1], totals[0], totals[3], totals[2]);
    }
    output_check_report(&nodes);
    output_check_report(&submission);
    const unsigned long long problems = faults + nodes.differing + nodes.missing + submission.differing +
                                        submission.missing + nodes.returns + submission.returns +
                                        (unsigned long long)(count - 4 - (int)read);
    printf("  %llu problems\n", problems);
    output_check_close(&nodes);
    output_check_close(&submission);
    free(graph.first);
    free(graph.voxels);
    free(graph.forward);
    free(graph.second);
    free(graph.backward);
    free(graph.cost);
    free(graph.ahead);
    free(graph.outside);
    free(graph.faces);
    return (problems == 0ull) ? 0 : 1;
}
