// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "faces.h"
#include "hessian.h"
#include "scan.h"
#include "sort.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define FACES_SEEK _fseeki64
#define FACES_TELL _ftelli64
#else
#define FACES_SEEK fseeko
#define FACES_TELL ftello
#endif

// .points and .shape each open with frames, depth, height, width, the residual's limbs and a sixth word: the contrast's
// bits in .points, the shape's limbs (the residual's and one more) in .shape. A .points frame is its count, each
// point's voxel, then each point's levels; a .shape frame is its count, each point's faces, then each point's six
// differences
#define FACES_SCAN_HEADER_WORDS 6u

// .drift opens with frames, depth, height, width and the three weights; each frame then holds its positive voxels, and
// every frame after the first the lag (z, y, x) carrying the frame before onto it and the agreement at that lag
#define FACES_DRIFT_HEADER_WORDS 7u

// a pair's source records and gate records, and the .links' bytes for its CRC-64, are read this many at a time
#define FACES_CHUNK 65536u

#define FACES_NONE 0xFFFFFFFFu

// one frame as the part holds it: its lag from the frame before (0 at frame 0), and for each point its place, its own
// faces from the .shape, its chosen link in (the source's index in the frame before) and out (the target's index in
// the next), and the faces its prediction crosses
typedef struct
{
    unsigned int count;
    unsigned int capacity;
    int lag[ENGINE_AXES];
    unsigned int *voxels;
    int *places;
    unsigned int *hessian;
    unsigned int *in;
    unsigned int *out;
    unsigned int *ahead;
} FacesFrame;

typedef struct
{
    FacesFrame frames[2];
    unsigned int *words;
    size_t word_capacity;
    unsigned int *chunk;
} FacesWalk;

// a sample's counts: its starts (the points after frame 0 with no chosen link in) and those entering, its ends (the
// points before the last frame with no chosen link out) and those leaving, the points of the first and last frames, and
// the back-predictions that took a link's motion
typedef struct
{
    unsigned long long frames;
    unsigned long long points;
    unsigned long long starts;
    unsigned long long entering;
    unsigned long long ends;
    unsigned long long leaving;
    unsigned long long first;
    unsigned long long last;
    unsigned long long carried;
} FacesResults;

static int faces_read(FILE *file, void *words, size_t bytes)
{
    return (bytes == 0u) || (fread(words, 1u, bytes, file) == bytes);
}

static int faces_write(FILE *file, const void *words, size_t bytes)
{
    return (bytes == 0u) || (fwrite(words, 1u, bytes, file) == bytes);
}

// a skip past 2^63 - 1 bytes is no file this reads
static int faces_skip(FILE *file, unsigned long long bytes)
{
    return (bytes <= 0x7FFFFFFFFFFFFFFFull) && (FACES_SEEK(file, (long long)bytes, SEEK_CUR) == 0);
}

// `count` points of `words` 32-bit words each, in bytes, or all ones when that passes 2^63 - 1
static unsigned long long faces_frame_bytes(unsigned long long count, unsigned long long words)
{
    return ((count != 0ull) && (words > ((0x7FFFFFFFFFFFFFFFull / 4ull) / count))) ? ~0ull : (count * words * 4ull);
}

// the file's place is its end: every frame read whole, and nothing past the last
static int faces_at_end(FILE *file)
{
    const long long place = FACES_TELL(file);
    const int ended = (place >= 0ll) && (FACES_SEEK(file, 0ll, SEEK_END) == 0);
    return ended && (FACES_TELL(file) == place);
}

// the faces `place` crosses on `axis` of `extent`: below 0 its low face, at or past the extent its high, as the shape's
// face bits order them
static unsigned int faces_crossed(unsigned int axis, long long place, long long extent)
{
    return ((place < 0ll) ? (1u << (2u * axis)) : 0u) | ((place >= extent) ? (2u << (2u * axis)) : 0u);
}

static int faces_frame_reserve(FacesFrame *frame, unsigned int count)
{
    if ((count <= frame->capacity) && (frame->voxels != NULL))
    {
        return 1;
    }
    const size_t capacity = (size_t)count + 1u;
    unsigned int *const voxels = (unsigned int *)realloc(frame->voxels, capacity * sizeof(unsigned int));
    frame->voxels = (voxels != NULL) ? voxels : frame->voxels;
    int *const places = (int *)realloc(frame->places, ENGINE_AXES * capacity * sizeof(int));
    frame->places = (places != NULL) ? places : frame->places;
    unsigned int *const hessian = (unsigned int *)realloc(frame->hessian, capacity * sizeof(unsigned int));
    frame->hessian = (hessian != NULL) ? hessian : frame->hessian;
    unsigned int *const in = (unsigned int *)realloc(frame->in, capacity * sizeof(unsigned int));
    frame->in = (in != NULL) ? in : frame->in;
    unsigned int *const out = (unsigned int *)realloc(frame->out, capacity * sizeof(unsigned int));
    frame->out = (out != NULL) ? out : frame->out;
    unsigned int *const ahead = (unsigned int *)realloc(frame->ahead, capacity * sizeof(unsigned int));
    frame->ahead = (ahead != NULL) ? ahead : frame->ahead;
    const int ok =
        (voxels != NULL) && (places != NULL) && (hessian != NULL) && (in != NULL) && (out != NULL) && (ahead != NULL);
    frame->capacity = ok ? count : 0u;
    return ok;
}

static void faces_frame_free(FacesFrame *frame)
{
    free(frame->voxels);
    free(frame->places);
    free(frame->hessian);
    free(frame->in);
    free(frame->out);
    free(frame->ahead);
    memset(frame, 0, sizeof(*frame));
}

static int faces_words_reserve(FacesWalk *walk, size_t words)
{
    if ((words <= walk->word_capacity) && (walk->words != NULL))
    {
        return 1;
    }
    unsigned int *const grown = (unsigned int *)realloc(walk->words, (words + 1u) * sizeof(unsigned int));
    walk->words = (grown != NULL) ? grown : walk->words;
    walk->word_capacity = (grown != NULL) ? words : walk->word_capacity;
    return grown != NULL;
}

// the CRC-64 of the whole file (cu/includes/codecs/crc/crc.h's key), read through `chunk`, which holds FACES_CHUNK * 4 bytes
static int faces_file_crc(const char *path, unsigned int *chunk, unsigned long long *crc)
{
    FILE *const file = fopen(path, "rb");
    unsigned char *const bytes = (unsigned char *)chunk;
    const size_t capacity = (size_t)FACES_CHUNK * sizeof(unsigned int);
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

// frame `frame` of the .points, the .drift and the .shape: the points' voxels (the levels passed over) and places, the
// lag onto the frame, and each point's faces (the differences passed over). Every voxel lies in the view, the .shape
// counts the .points' points, and a point's faces are among the six
static int faces_frame_read(const char *sample, FILE *points, FILE *drift, FILE *hessian,
                            const unsigned int head[FACES_SCAN_HEADER_WORDS], unsigned int hessian_limbs,
                            unsigned int frame, FacesFrame *read)
{
    const unsigned int plane = head[2] * head[3];
    const unsigned int voxels = head[1] * plane;
    unsigned int count = 0u;
    unsigned int shaped = 0u;
    unsigned int positives = 0u;
    unsigned int agreement = 0u;
    int lag[ENGINE_AXES] = {0, 0, 0};
    int ok = faces_read(points, &count, sizeof(count)) && (count <= voxels) && faces_frame_reserve(read, count) &&
             faces_read(points, read->voxels, (size_t)count * sizeof(unsigned int)) &&
             faces_skip(points, faces_frame_bytes(count, head[4]));
    ok = ok && faces_read(drift, &positives, sizeof(positives)) &&
         ((frame == 0u) || (faces_read(drift, lag, sizeof(lag)) && faces_read(drift, &agreement, sizeof(agreement))));
    ok = ok && faces_read(hessian, &shaped, sizeof(shaped)) && (shaped == count) &&
         faces_read(hessian, read->hessian, (size_t)count * sizeof(unsigned int)) &&
         faces_skip(hessian, faces_frame_bytes(count, (unsigned long long)HESSIAN_ENTRIES * hessian_limbs));
    for (unsigned int point = 0u; ok && (point < count); point += 1u)
    {
        const unsigned int voxel = read->voxels[point];
        ok = (voxel < voxels) && ((read->hessian[point] & ~FACES_SIX) == 0u);
        // a voxel below the view's voxels, below 2^31, gives places below 2^31, each fitting int
        read->places[(ENGINE_AXES * (size_t)point) + 0u] = (int)(voxel / plane);
        read->places[(ENGINE_AXES * (size_t)point) + 1u] = (int)((voxel % plane) / head[3]);
        read->places[(ENGINE_AXES * (size_t)point) + 2u] = (int)(voxel % head[3]);
        read->in[point] = FACES_NONE;
        read->out[point] = FACES_NONE;
        read->ahead[point] = 0u;
    }
    if (ok == 0)
    {
        fprintf(stderr,
                "  faces: %s: frame %u did not read whole from the .points, .drift and .shape, a voxel lies"
                " outside the view, the .shape counts other points, or a point's faces are not among the"
                " six\n",
                sample, frame);
    }
    read->count = ok ? count : 0u;
    memcpy(read->lag, lag, sizeof(lag));
    return ok;
}

// frame pair (frame, frame + 1) of the .links: its record against the two frames' points, each source's prediction's
// faces against the source's own flag, and each chosen gate pair as a link, at most one out of each source and one
// into each target (O20)
static int faces_pair_read(const char *sample, FILE *links, const unsigned int head[FACES_SCAN_HEADER_WORDS],
                           unsigned int frame, FacesFrame *now, FacesFrame *next, unsigned int *chunk)
{
    const long long extent[ENGINE_AXES] = {head[1], head[2], head[3]};
    unsigned int record[SORT_PAIR_WORDS];
    if (faces_read(links, record, sizeof(record)) == 0)
    {
        fprintf(stderr, "  faces: %s: frames %u and %u: the pair record did not read\n", sample, frame, frame + 1u);
        return 0;
    }
    if ((record[0] != now->count) || (record[1] != next->count))
    {
        fprintf(stderr,
                "  faces: %s: frames %u and %u: the pair record reads %u sources and %u targets, the .points"
                " %u and %u\n",
                sample, frame, frame + 1u, record[0], record[1], now->count, next->count);
        return 0;
    }
    const unsigned int batch_max = FACES_CHUNK / SORT_GATE_WORDS;
    for (unsigned int done = 0u; done < record[0];)
    {
        const unsigned int batch = ((record[0] - done) < batch_max) ? (record[0] - done) : batch_max;
        if (faces_read(links, chunk, (size_t)batch * SORT_SOURCE_WORDS * sizeof(unsigned int)) == 0)
        {
            fprintf(stderr, "  faces: %s: frames %u and %u: the source records did not read\n", sample, frame,
                    frame + 1u);
            return 0;
        }
        for (unsigned int at = 0u; at < batch; at += 1u)
        {
            const unsigned int *const source = &chunk[SORT_SOURCE_WORDS * at];
            unsigned int ahead = 0u;
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                // a prediction is written as its two's complement word
                ahead |= faces_crossed(axis, (long long)(int)source[axis], extent[axis]);
            }
            const int flagged = (source[ENGINE_AXES] & SORT_SOURCE_OUTSIDE) != 0u;
            if (flagged != (ahead != 0u))
            {
                fprintf(stderr,
                        "  faces: %s: frames %u and %u: point %u's prediction (%d, %d, %d) is %s the view, and"
                        " the .links flags it %s\n",
                        sample, frame, frame + 1u, done + at, (int)source[0], (int)source[1], (int)source[2],
                        (ahead != 0u) ? "outside" : "inside", flagged ? "outside" : "inside");
                return 0;
            }
            now->ahead[done + at] = ahead;
        }
        done += batch;
    }
    unsigned int chosen = 0u;
    for (unsigned int done = 0u; done < record[2];)
    {
        const unsigned int batch = ((record[2] - done) < batch_max) ? (record[2] - done) : batch_max;
        if (faces_read(links, chunk, (size_t)batch * SORT_GATE_WORDS * sizeof(unsigned int)) == 0)
        {
            fprintf(stderr, "  faces: %s: frames %u and %u: the gate records did not read\n", sample, frame,
                    frame + 1u);
            return 0;
        }
        for (unsigned int at = 0u; at < batch; at += 1u)
        {
            const unsigned int *const pair = &chunk[SORT_GATE_WORDS * at];
            if ((pair[6] & SORT_GATE_CHOSEN) == 0u)
            {
                continue;
            }
            const unsigned int source = pair[0];
            const unsigned int target = pair[1];
            if ((source >= record[0]) || (target >= record[1]))
            {
                fprintf(stderr, "  faces: %s: frames %u and %u: a chosen link %u to %u lies past the frames' points\n",
                        sample, frame, frame + 1u, source, target);
                return 0;
            }
            if ((now->out[source] != FACES_NONE) || (next->in[target] != FACES_NONE))
            {
                fprintf(stderr,
                        "  faces: %s: frames %u and %u: the chosen link %u to %u makes two links out of its"
                        " source or two into its target\n",
                        sample, frame, frame + 1u, source, target);
                return 0;
            }
            now->out[source] = target;
            next->in[target] = source;
            chosen += 1u;
        }
        done += batch;
    }
    if (chosen != record[4])
    {
        fprintf(stderr, "  faces: %s: frames %u and %u: the pair record reads %u chosen links, its gate %u\n", sample,
                frame, frame + 1u, record[4], chosen);
        return 0;
    }
    return 1;
}

// frame `frame`'s words: its count, then each point's back-prediction and flags. `next` is frame + 1, or NULL at the
// last frame
static int faces_frame_write(const char *sample, FILE *faces, const unsigned int head[FACES_SCAN_HEADER_WORDS],
                             unsigned int frame, const FacesFrame *now, const FacesFrame *next, FacesWalk *walk,
                             FacesResults *results)
{
    const long long extent[ENGINE_AXES] = {head[1], head[2], head[3]};
    const size_t words = 1u + (FACES_POINT_WORDS * (size_t)now->count);
    if (faces_words_reserve(walk, words) == 0)
    {
        fprintf(stderr, "  faces: %s: frame %u: the memory for its words could not be reserved\n", sample, frame);
        return 0;
    }
    walk->words[0] = now->count;
    for (unsigned int point = 0u; point < now->count; point += 1u)
    {
        unsigned int *const word = &walk->words[1u + (FACES_POINT_WORDS * (size_t)point)];
        const unsigned int onto = now->out[point];
        const int carried = (frame != 0u) && (next != NULL) && (onto != FACES_NONE);
        unsigned int back = 0u;
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            const long long place = now->places[(ENGINE_AXES * (size_t)point) + axis];
            long long backward = (frame == 0u) ? place : (place - (long long)now->lag[axis]);
            if (carried)
            {
                const long long motion =
                    (long long)next->places[(ENGINE_AXES * (size_t)onto) + axis] - place - (long long)next->lag[axis];
                backward -= motion;
            }
            if ((backward < -0x80000000ll) || (backward > 0x7FFFFFFFll))
            {
                fprintf(stderr, "  faces: %s: frame %u: point %u's back-prediction on axis %u, %lld, passes 32 bits\n",
                        sample, frame, point, axis, backward);
                return 0;
            }
            // a back-prediction held in [-2^31, 2^31) is written as its two's complement word
            word[axis] = (unsigned int)(int)backward;
            back |= faces_crossed(axis, backward, extent[axis]);
        }
        const int start = (frame != 0u) && (now->in[point] == FACES_NONE);
        const int end = (next != NULL) && (onto == FACES_NONE);
        unsigned int flags = (back << FACES_BACK_SHIFT) | (now->ahead[point] << FACES_AHEAD_SHIFT) |
                             (now->hessian[point] << FACES_HESSIAN_SHIFT);
        flags |= (frame == 0u) ? FACES_FIRST : 0u;
        flags |= (next == NULL) ? FACES_LAST : 0u;
        flags |= carried ? FACES_CARRIED : 0u;
        flags |= (start && (back != 0u)) ? FACES_ENTERING : 0u;
        flags |= (end && (now->ahead[point] != 0u)) ? FACES_LEAVING : 0u;
        word[ENGINE_AXES] = flags;
        results->starts += start ? 1ull : 0ull;
        results->entering += ((flags & FACES_ENTERING) != 0u) ? 1ull : 0ull;
        results->ends += end ? 1ull : 0ull;
        results->leaving += ((flags & FACES_LEAVING) != 0u) ? 1ull : 0ull;
        results->carried += carried ? 1ull : 0ull;
    }
    results->frames += 1ull;
    results->points += now->count;
    results->first += (frame == 0u) ? now->count : 0ull;
    results->last += (next == NULL) ? now->count : 0ull;
    if (faces_write(faces, walk->words, words * sizeof(unsigned int)) == 0)
    {
        fprintf(stderr, "  faces: %s: frame %u could not be written\n", sample, frame);
        return 0;
    }
    return 1;
}

static int faces_frames(const char *sample, FILE *points, FILE *drift, FILE *hessian, FILE *links,
                        unsigned long long crc, FILE *faces, FacesWalk *walk, FacesResults *results)
{
    unsigned int head[FACES_SCAN_HEADER_WORDS];
    unsigned int drift_head[FACES_DRIFT_HEADER_WORDS];
    unsigned int hessian_head[FACES_SCAN_HEADER_WORDS];
    unsigned int links_head[SORT_HEADER_WORDS];
    int ok = faces_read(points, head, sizeof(head)) &&
             faces_skip(points, (1ull + SCAN_READINGS) * sizeof(unsigned long long)) &&
             faces_read(drift, drift_head, sizeof(drift_head)) &&
             faces_read(hessian, hessian_head, sizeof(hessian_head)) &&
             faces_read(links, links_head, sizeof(links_head));
    if (ok == 0)
    {
        fprintf(stderr, "  faces: %s: its .points, .drift, .shape or .links head did not read\n", sample);
        return 0;
    }
    const int agree = (memcmp(head, drift_head, 4u * sizeof(unsigned int)) == 0) &&
                      (memcmp(head, hessian_head, 4u * sizeof(unsigned int)) == 0) &&
                      (memcmp(head, links_head, 4u * sizeof(unsigned int)) == 0);
    // the residual's limbs are below 2^30 for any orders of 32 bits. One more does not wrap
    const int limbed = (hessian_head[4] == head[4]) && (hessian_head[5] == (head[4] + 1u));
    const unsigned long long plane = (unsigned long long)head[2] * head[3];
    const int sized = (head[1] != 0u) && (plane != 0ull) && (plane <= (0x7FFFFFFFull / head[1]));
    if (agree == 0)
    {
        fprintf(stderr,
                "  faces: %s: its .points reads %u frames of %u x %u x %u, its .drift %u of %u x %u x %u, its"
                " .shape %u of %u x %u x %u, its .links %u of %u x %u x %u\n",
                sample, head[0], head[1], head[2], head[3], drift_head[0], drift_head[1], drift_head[2], drift_head[3],
                hessian_head[0], hessian_head[1], hessian_head[2], hessian_head[3], links_head[0], links_head[1],
                links_head[2], links_head[3]);
        return 0;
    }
    if (limbed == 0)
    {
        fprintf(stderr, "  faces: %s: its .shape reads %u and %u limbs, its .points %u\n", sample, hessian_head[4],
                hessian_head[5], head[4]);
        return 0;
    }
    if (sized == 0)
    {
        fprintf(stderr, "  faces: %s: its view %u x %u x %u passes 2^31 - 1 voxels\n", sample, head[1], head[2],
                head[3]);
        return 0;
    }
    const unsigned int header[FACES_HEADER_WORDS] = {
        head[0], head[1], head[2], head[3], (unsigned int)(crc & 0xFFFFFFFFull), (unsigned int)(crc >> 32u)};
    if (faces_write(faces, header, sizeof(header)) == 0)
    {
        fprintf(stderr, "  faces: %s: its .faces header could not be written\n", sample);
        return 0;
    }
    FacesFrame *now = &walk->frames[0];
    FacesFrame *next = &walk->frames[1];
    ok = (head[0] == 0u) || faces_frame_read(sample, points, drift, hessian, head, hessian_head[5], 0u, now);
    for (unsigned int frame = 0u; ok && (frame < head[0]); frame += 1u)
    {
        const int later = (frame + 1u) < head[0];
        ok = (later == 0) ||
             (faces_frame_read(sample, points, drift, hessian, head, hessian_head[5], frame + 1u, next) &&
              faces_pair_read(sample, links, head, frame, now, next, walk->chunk));
        ok = ok && faces_frame_write(sample, faces, head, frame, now, later ? next : NULL, walk, results);
        FacesFrame *const passed = now;
        now = next;
        next = passed;
    }
    const int ended = ok && faces_at_end(points) && faces_at_end(drift) && faces_at_end(hessian) && faces_at_end(links);
    if (ok && (ended == 0))
    {
        fprintf(stderr, "  faces: %s: its .points, .drift, .shape or .links does not end at its last frame\n", sample);
    }
    return ended;
}

static int faces_sample(const FacesRequest *request, const char *sample, FacesWalk *walk, FacesResults *results)
{
    memset(results, 0, sizeof(*results));
    char points_path[ENGINE_PATH_CAPACITY];
    char drift_path[ENGINE_PATH_CAPACITY];
    char hessian_path[ENGINE_PATH_CAPACITY];
    char links_path[ENGINE_PATH_CAPACITY];
    char faces_path[ENGINE_PATH_CAPACITY];
    FILE *const points = engine_sample_path(points_path, sizeof(points_path), request->set, sample, ".points")
                             ? fopen(points_path, "rb")
                             : NULL;
    FILE *const drift = engine_sample_path(drift_path, sizeof(drift_path), request->set, sample, ".drift")
                            ? fopen(drift_path, "rb")
                            : NULL;
    FILE *const hessian = engine_sample_path(hessian_path, sizeof(hessian_path), request->set, sample, ".shape")
                              ? fopen(hessian_path, "rb")
                              : NULL;
    const int linked = engine_sample_path(links_path, sizeof(links_path), request->set, sample, ".links");
    FILE *const links = linked ? fopen(links_path, "rb") : NULL;
    const int named = engine_sample_path(faces_path, sizeof(faces_path), request->set, sample, ".faces");
    const int opened = (points != NULL) && (drift != NULL) && (hessian != NULL) && (links != NULL) && named;
    unsigned long long crc = 0ull;
    const int summed = opened && faces_file_crc(links_path, walk->chunk, &crc);
    FILE *const faces = summed ? fopen(faces_path, "wb") : NULL;
    if (opened == 0)
    {
        fprintf(stderr, "  faces: %s: its .points, .drift, .shape or .links in %s did not open\n", sample,
                request->set);
    }
    else if (summed == 0)
    {
        fprintf(stderr, "  faces: %s: its .links did not read whole for its CRC-64\n", sample);
    }
    else if (faces == NULL)
    {
        fprintf(stderr, "  faces: %s: its .faces could not be made\n", sample);
    }
    const int ok = (faces != NULL) && faces_frames(sample, points, drift, hessian, links, crc, faces, walk, results);
    const int closed = (faces != NULL) && (fclose(faces) == 0);
    FILE *const opens[4] = {points, drift, hessian, links};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        if (opens[at] != NULL)
        {
            fclose(opens[at]);
        }
    }
    // a sample that errors leaves no .faces, not even one an earlier run wrote
    if (named && ((ok == 0) || (closed == 0)))
    {
        (void)remove(faces_path);
    }
    return ok && closed;
}

extern "C" long faces_find_set(const FacesRequest *request)
{
    if ((request == NULL) || (request->set == NULL) || (request->samples == NULL) || (request->count == 0u) ||
        (request->report == NULL))
    {
        return FACES_ERROR;
    }
    FILE *const report = request->report;
    FacesWalk walk;
    memset(&walk, 0, sizeof(walk));
    walk.chunk = (unsigned int *)malloc((size_t)FACES_CHUNK * sizeof(unsigned int));
    if (walk.chunk == NULL)
    {
        fprintf(stderr, "  faces: the memory for reading could not be reserved\n");
        return FACES_ERROR;
    }
    fprintf(report, "  %-24s %6s %10s %s\n", "sample", "frames", "points",
            "starts (entering the view), ends (leaving it); first frame, last frame; carried back");
    FacesResults totals;
    memset(&totals, 0, sizeof(totals));
    unsigned int failed = 0u;
    for (unsigned int at = 0u; at < request->count; at += 1u)
    {
        FacesResults results;
        const char *const sample = request->samples[at];
        if (faces_sample(request, sample, &walk, &results) == 0)
        {
            fprintf(stderr, "  faces: %s failed\n", sample);
            failed += 1u;
            continue;
        }
        fprintf(report, "  %-24s %6llu %10llu %llu (%llu), %llu (%llu); %llu, %llu; %llu\n", sample, results.frames,
                results.points, results.starts, results.entering, results.ends, results.leaving, results.first,
                results.last, results.carried);
        totals.frames += results.frames;
        totals.points += results.points;
        totals.starts += results.starts;
        totals.entering += results.entering;
        totals.ends += results.ends;
        totals.leaving += results.leaving;
        totals.first += results.first;
        totals.last += results.last;
        totals.carried += results.carried;
    }
    fprintf(report,
            "  faces on %u of %u samples: %llu frames, %llu points; %llu starts, %llu of them entering the"
            " view; %llu ends, %llu of them leaving it; %llu points in the first frames, %llu in the last;"
            " %llu back-predictions carried by a link's motion\n",
            request->count - failed, request->count, totals.frames, totals.points, totals.starts, totals.entering,
            totals.ends, totals.leaving, totals.first, totals.last, totals.carried);
    faces_frame_free(&walk.frames[0]);
    faces_frame_free(&walk.frames[1]);
    free(walk.words);
    free(walk.chunk);
    return (failed == 0u) ? 0L : FACES_ERROR;
}
