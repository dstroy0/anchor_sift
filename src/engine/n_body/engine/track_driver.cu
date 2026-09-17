/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file track_driver.cu
 * @brief The native tracker: basins, view motion, overlap, the growing tree and its score against the
 *        answer key, in one compiled process with the engines on the device.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * Usage:
 *     track_driver [--pick] [--merge-split] [--merge-target] [--forward-only] [--keep-view]
 *                  [--no-resolve] <directory> <sample> [<sample> ...]
 *
 * Each sample is read from <directory>/<sample>.stack and <directory>/<sample>.truth, written once by
 * maint/dump_frames.py. The rules are the reference's, src/exact_track.py grow_tree, restated here rule
 * for rule so the two give the same links and the same score; no Python runs between engine stages.
 *
 * NO FLOATING POINT VALUE IS FORMED. Counts are integers, percentages are written by integer division,
 * and times are whole milliseconds.
 */

#include "binomial_basins.h"
#include "basin_overlap.h"
#include "cfg_json.h"
#include "climb_machine.h"
#include "radix_keys.h"
#include "shift_agreement.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#include <io.h>
/** @brief A seek past 2 GiB: a stack of forty frames of a 4,194,304-voxel view is 335 MiB, and larger views pass 2 GiB. */
#define STACK_SEEK _fseeki64
#else
#include <dirent.h>
#define STACK_SEEK fseeko
#endif

/** @brief First smoothing, binomial orders z y x: src/exact_track.py SMOOTH_ORDERS. */
static const unsigned int SMOOTH_ORDERS[3] = {2u, 34u, 34u};

/** @brief Background smoothing, binomial orders z y x: src/exact_track.py BACKGROUND_ORDERS. */
static const unsigned int BACKGROUND_ORDERS[3] = {6u, 96u, 96u};

/** @brief Squared length weight per axis in the y voxel unit: AXIS_UNITS (4, 1, 1) squared. */
static const unsigned int AXIS_WEIGHTS[3] = {16u, 1u, 1u};

/** @brief Steps of the link's jitter sweep: a box a voxel wide, doubling out past the whole view. */
#define LINK_SWEEP_STEPS 12u

/** @brief Bits a swept vector's magnitude is given, leaving the step it was met at above them. */
#define LINK_MAGNITUDE_BITS 40u

/** @brief Every bit a swept vector's magnitude may hold. */
#define LINK_MAGNITUDE_MASK ((1ull << LINK_MAGNITUDE_BITS) - 1ull)

static_assert(((unsigned long long)LINK_SWEEP_STEPS << LINK_MAGNITUDE_BITS) != 0ull,
              "track_driver: the swept step must stay inside an unsigned long long");

/** @brief The rules the tree is grown by, one flag per rule of the reference. */
typedef struct
{
    int pick;             /**< Keep the branch sharing the most positive voxels; exact ties stay. */
    int share;            /**< Weigh a branch by the exact fraction it shares of the two cells together. */
    int agree;            /**< Repair an over-cut cell only where its halves agree about where they are going. */
    int unbound;          /**< Nothing is kept out of the pool: the nearest centre by vector magnitude is taken. */
    int cast;             /**< Each cell casts its voxels by its own climbed lag, and the landings are the shares. */
    int parallax;         /**< The view moves with each candidate: what stays still under that move is the share. */
    int arc;              /**< Where the pool is contested, the track that arcs most smoothly through it wins. */
    int settle;           /**< Cells that reach for one target settle it between them, the strongest keeping it. */
    int merge_split;      /**< Unify joined leaves whose peaks came from one earlier object. */
    int merge_target;     /**< Link a peak landing in a target reached by two or more sources. */
    int forward_only;     /**< Link wherever a peak lands, with no back landing. */
    int resolve;          /**< Read branches at the end of the series. */
    int keep_view;        /**< Compare voxel v with v: do not remove the view's motion. */
    int climb;            /**< Each basin climbs its own lag by its truthy falsy coherence, from the view's lag. */
    int sticky;           /**< The climb scores a basin with every basin it touches: sticky cells move together. */
    int motion_check;     /**< Every pair's motion is run again without the kept transform and every count compared. */
    unsigned int null_draws; /**< Null draws per climbed pair: frames far off in time, climbed from the same lag. */
    unsigned int arms;       /**< Arms fired from every frame: the same climb at every gap up to this many. */
    FILE *coherence;      /**< Where coherence rows go, or NULL for none [BORROWS]. */
    FILE *edges;          /**< Where one row per scored edge goes, or NULL for none [BORROWS]. */
    FILE *pool;           /**< Where every candidate weighed for a scored edge goes, refusals and all [BORROWS]. */
    const char *export_directory; /**< Where the room view's vectors go, or NULL for none [BORROWS]. */
    bool object;          /**< Each sample is written as the object the card is fed: runs, leaves, cells, links. */
    const char *object_directory; /**< Where the objects go, read only where object is true [BORROWS]. */
    const char *vis_directory; /**< Where the vis arm draws failing edges, or NULL for none [BORROWS]. */
    FILE *vis_index;      /**< The vis arm's page [BORROWS]. */
    const char *cfg_text; /**< The .cfg the run is taking, every rule written out, carried into each object [BORROWS]. */
    size_t cfg_length;    /**< Its bytes. */
} TreeRules;

/** @brief One sample's answer key, nodes ascending by id. */
typedef struct
{
    unsigned int node_count;          /**< Labelled nodes. */
    unsigned int edge_count;          /**< Labelled edges. */
    long long *node_identity;         /**< Node ids, ascending [OWNS]. */
    int *node_coordinates;            /**< t z y x per node [OWNS]. */
    long long *edge_ends;             /**< Source and target id per edge [OWNS]. */
} AnswerKey;

/** @brief One frame of the tree, and its links to the next frame where that frame follows at once. */
typedef struct
{
    unsigned int time;                /**< Frame index in the stack. */
    unsigned int leaf_count;          /**< Positive basins. */
    unsigned int *peaks;              /**< Peak raster index per leaf, ascending [OWNS]. */
    unsigned int *sizes;              /**< Positive voxels per leaf [OWNS]. */
    unsigned long long *sums;         /**< Index sums z y x per leaf [OWNS]. */
    unsigned long long *moments;      /**< Six per leaf: sums of zz yy xx zy zx yx, where exported, or NULL [OWNS]. */
    unsigned int *exposed;            /**< Per leaf, faces of its positive voxels meeting no positive voxel, where exported [OWNS]. */
    unsigned int *contact_faces;      /**< Per joined pair, the faces its two basins share, where exported [OWNS]. */
    unsigned int joined_count;        /**< Joined pairs. */
    unsigned int *joined;             /**< Leaf pairs, two per pair, engine order [OWNS]. */
    int lag_to_next[3];               /**< The view's lag to the next frame, z y x, where it follows. */
    unsigned int step_back;           /**< Frames from the frame before this one, 0 where none comes before. */
    unsigned int step_next;           /**< Frames to the frame after this one, 0 where none follows. */
    int *forward;                     /**< Leaf of the next frame each peak lands in, or -1 [OWNS]. */
    int *backward;                    /**< Leaf of the previous frame each peak lands in, or -1 [OWNS]. */
    int *forward_lag;                 /**< Three per leaf: the lag its peak was carried by, or NULL [OWNS]. */
    int *backward_lag;                /**< Three per leaf: the lag its peak was carried back by, or NULL [OWNS]. */
    int *check_forward_lag;           /**< Where the climb is checked, the host reference's forward_lag [OWNS]. */
    int *check_backward_lag;          /**< Where the climb is checked, the host reference's backward_lag [OWNS]. */
    unsigned int *forward_held;       /**< Per leaf, its coherence at its climbed lag against the next frame, or NULL [OWNS]. */
    unsigned int null_count;          /**< Null draws taken for this frame's leaves. */
    // The arms: the same climb fired at every gap at once, so a cell that cannot be told from its neighbour one
    // frame on has moved clear of it two or three frames on, and what the arms land in has to compose.
    unsigned int arm_count;           /**< Arms fired from this frame, one per gap beyond the next frame. */
    int *arm_forward;                 /**< Per arm, per leaf, the leaf of that gap's frame it landed in [OWNS]. */
    unsigned int *null_held;          /**< null_count per leaf: its coherence climbed against each null frame [OWNS]. */
    unsigned int triple_count;        /**< Overlap pairs with the next frame. */
    unsigned int *triple_start;       /**< leaf_count + 1 offsets by leaf before [OWNS]. */
    unsigned int *triple_after;       /**< Leaf after per pair [OWNS]. */
    unsigned int *triple_shared;      /**< Shared positive voxels per pair [OWNS]. */
    unsigned int *triple_still;       /**< Per pair, the voxels that stay still when the view moves with it [OWNS]. */
    unsigned int object_count;        /**< Objects the leaves group into. */
    unsigned int *object_of;          /**< Object per leaf [OWNS]. */
    unsigned int *member_start;       /**< object_count + 1 offsets [OWNS]. */
    unsigned int *members;            /**< Leaves grouped by object, ascending within each [OWNS]. */
    unsigned int *link_start;         /**< object_count + 1 offsets into link_target, or NULL [OWNS]. */
    unsigned int *link_target;        /**< Objects of the next frame each object links to [OWNS]. */
    // The pool every object weighed, kept whole: what was refused is what a better question is asked of.
    unsigned int *pool_start;         /**< object_count + 1 offsets into the pool, or NULL [OWNS]. */
    unsigned int *pool_target;        /**< Per pool entry, the object of the next frame it stands for [OWNS]. */
    unsigned int *pool_weight;        /**< Per pool entry, the voxels the two meet in [OWNS]. */
    unsigned long long *pool_cost;    /**< Per pool entry, the swept vector: the step above, the magnitude below [OWNS]. */
} TreeFrame;

/** @brief Tallies of scored edges. */
typedef struct
{
    unsigned long long correct;       /**< Links exactly the true target, or a division. */
    unsigned long long branched;      /**< The true target among other branches. */
    unsigned long long wrong;         /**< Links that miss the true target. */
    unsigned long long unlinked;      /**< No link from the source. */
    unsigned long long missed;        /**< An endpoint in no object. */
} EdgeTally;

/**
 * @brief Whole milliseconds since an arbitrary epoch.
 *
 * @return The clock in milliseconds.
 */
static unsigned long long clock_milliseconds(void)
{
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    // Widening: seconds and nanoseconds are nonnegative on this clock.
    return (unsigned long long)now.tv_sec * 1000ULL + (unsigned long long)now.tv_nsec / 1000000ULL;
}

/**
 * @brief Whole microseconds since an arbitrary epoch.
 *
 * @return The clock in microseconds.
 */
static unsigned long long clock_microseconds(void)
{
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    // Widening: seconds and nanoseconds are nonnegative on this clock.
    return (unsigned long long)now.tv_sec * 1000000ULL + (unsigned long long)now.tv_nsec / 1000ULL;
}

/** @brief Microseconds spent per stage over one sample. */
typedef struct
{
    unsigned long long read;          /**< Reading frames from the stack. */
    unsigned long long basins;        /**< The basin engine. */
    unsigned long long ties;          /**< Placing the answer key's nodes. */
    unsigned long long motion;        /**< The shift agreement engine. */
    unsigned long long landing;       /**< Landing peaks both ways, or pending them with the machine. */
    unsigned long long store;         /**< Grouping each frame's basins and storing the frame on the device. */
    unsigned long long climb;         /**< The machine climbing every pending pair. */
    unsigned long long overlap;       /**< The overlap engine and its mapping to leaves. */
} StageClock;

/**
 * @brief numerator/denominator to one decimal place, by integer division, half rounding up.
 *
 * @param[in]  numerator   Tally.
 * @param[in]  denominator Total, nonzero.
 * @param[out] whole       The whole part [BORROWS].
 * @param[out] tenth       The tenths digit [BORROWS].
 */
static void percent_of(unsigned long long numerator, unsigned long long denominator, unsigned long long *whole,
                       unsigned long long *tenth)
{
    const unsigned long long scaled = (numerator * 1000ULL * 2ULL + denominator) / (2ULL * denominator);
    *whole = scaled / 10ULL;
    *tenth = scaled % 10ULL;
}

/**
 * @brief Ascending order of unsigned 64 bit keys, for qsort and bsearch.
 *
 * @param[in] left  First key [BORROWS].
 * @param[in] right Second key [BORROWS].
 * @return          Negative, zero or positive.
 */
static int order_keys(const void *left, const void *right)
{
    const unsigned long long first = *(const unsigned long long *)left;
    const unsigned long long second = *(const unsigned long long *)right;
    return (first < second) ? -1 : ((first > second) ? 1 : 0);
}

/**
 * @brief Sorts keys ascending and removes repeats.
 *
 * @param[in,out] keys  The keys [BORROWS].
 * @param[in]     count How many.
 * @return              How many distinct keys remain at the front.
 */
static unsigned int sort_unique(unsigned long long *keys, unsigned int count)
{
    if (count == 0u)
    {
        return 0u;
    }
    qsort(keys, count, sizeof(unsigned long long), order_keys);
    unsigned int kept = 1u;
    for (unsigned int position = 1u; position < count; position += 1u)
    {
        if (keys[position] != keys[kept - 1u])
        {
            keys[kept] = keys[position];
            kept += 1u;
        }
    }
    return kept;
}

/**
 * @brief The set bits of a word, by the SWAR count: pairs, nibbles, bytes, then one multiply gathers the bytes.
 *
 * @param[in] word The word.
 * @return         Its set bits.
 */
static inline unsigned int word_population(unsigned long long word)
{
    const unsigned long long pairs = word - ((word >> 1u) & 0x5555555555555555ULL);
    const unsigned long long nibbles = (pairs & 0x3333333333333333ULL) + ((pairs >> 2u) & 0x3333333333333333ULL);
    const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0FULL;
    // Narrowing is safe: the count is at most 64.
    return (unsigned int)((bytes * 0x0101010101010101ULL) >> 56u);
}

/**
 * @brief Fits a growing array of words to what is wanted: where the room falls short it doubles past the want, and
 *        otherwise it is left as it is. The array is resized either way, so the steering is by value, not by branch.
 *
 * @param[in,out] words  The array, kept where the resize fails [OWNS].
 * @param[in,out] room   Its room, in records.
 * @param[in]     wanted Records wanted.
 * @param[in]     width  Words per record; one record past the room is always held.
 * @return               True where the array holds the room.
 */
static inline bool object_room_fit(unsigned int **words, size_t *room, size_t wanted, size_t width)
{
    // Where the room is enough the product is zero, whatever the wrapped difference.
    *room += (size_t)(wanted > *room) * ((2u * wanted) - *room);
    unsigned int *const grown = (unsigned int *)realloc(*words, (*room + 1u) * width * sizeof(unsigned int));
    *words = grown ? grown : *words;
    return !!grown;
}

/**
 * @brief The leaf holding a peak raster index, by binary search over the ascending peaks.
 *
 * @param[in] peaks The peaks, ascending [BORROWS].
 * @param[in] count How many.
 * @param[in] peak  The raster index sought.
 * @return          The leaf, or -1 where the peak is not a positive basin's.
 */
static int leaf_of_peak(const unsigned int *peaks, unsigned int count, unsigned int peak)
{
    unsigned int low = 0u;
    unsigned int high = count;
    while (low < high)
    {
        const unsigned int middle = low + (high - low) / 2u;
        if (peaks[middle] < peak)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }
    // Narrowing is safe: a leaf count is at most the peak room, below 2^31.
    return ((low < count) && (peaks[low] == peak)) ? (int)low : -1;
}

/**
 * @brief The node slot of an id, by binary search over the ascending ids.
 *
 * @param[in] key      The answer key [BORROWS].
 * @param[in] identity The id sought.
 * @return             The slot, or -1 where no node has the id.
 */
static long node_slot_of(const AnswerKey *key, long long identity)
{
    unsigned int low = 0u;
    unsigned int high = key->node_count;
    while (low < high)
    {
        const unsigned int middle = low + (high - low) / 2u;
        if (key->node_identity[middle] < identity)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }
    return ((low < key->node_count) && (key->node_identity[low] == identity)) ? (long)low : -1L;
}

/**
 * @brief Reads an answer key written by maint/dump_frames.py.
 *
 * @param[in]  path The .truth file.
 * @param[out] key  The key [BORROWS].
 * @return          1 on success, 0 otherwise.
 */
static int read_answer_key(const char *path, AnswerKey *key)
{
    memset(key, 0, sizeof(*key));
    FILE *const handle = fopen(path, "rb");
    if (handle == NULL)
    {
        return 0;
    }
    unsigned int header[2];
    int good = (fread(header, sizeof(unsigned int), 2u, handle) == 2u);
    if (good != 0)
    {
        key->node_count = header[0];
        key->edge_count = header[1];
        key->node_identity = (long long *)malloc(((size_t)key->node_count + 1u) * sizeof(long long));
        key->node_coordinates = (int *)malloc(((size_t)key->node_count + 1u) * 4u * sizeof(int));
        key->edge_ends = (long long *)malloc(((size_t)key->edge_count + 1u) * 2u * sizeof(long long));
        good = (key->node_identity != NULL) && (key->node_coordinates != NULL) && (key->edge_ends != NULL);
    }
    for (unsigned int node = 0u; (good != 0) && (node < key->node_count); node += 1u)
    {
        good = (fread(&key->node_identity[node], sizeof(long long), 1u, handle) == 1u)
            && (fread(&key->node_coordinates[(size_t)node * 4u], sizeof(int), 4u, handle) == 4u);
    }
    if ((good != 0) && (key->edge_count > 0u))
    {
        good = (fread(key->edge_ends, sizeof(long long), (size_t)key->edge_count * 2u, handle)
                == (size_t)key->edge_count * 2u);
    }
    fclose(handle);
    return good;
}

/**
 * @brief Releases an answer key.
 *
 * @param[in,out] key The key [BORROWS].
 */
static void release_answer_key(AnswerKey *key)
{
    free(key->node_identity);
    free(key->node_coordinates);
    free(key->edge_ends);
    memset(key, 0, sizeof(*key));
}

/** @brief The engine buffers one sample reuses frame after frame. */
typedef struct
{
    unsigned int depth;               /**< Extent along z. */
    unsigned int height;              /**< Extent along y. */
    unsigned int width;               /**< Extent along x. */
    unsigned int peak_room;           /**< Peaks the peak buffers hold. */
    unsigned short *volume;           /**< One frame's raw voxels [OWNS]. */
    unsigned int *peak_indices;       /**< Engine output [OWNS]. */
    unsigned int *sizes;              /**< Engine output [OWNS]. */
    unsigned long long *sums;         /**< Engine output [OWNS]. */
    unsigned int *peak_limbs;         /**< Engine output [OWNS]. */
    unsigned int pair_room;           /**< Pairs the adjacency and joined buffers hold. */
    unsigned int *adjacency;          /**< Engine output [OWNS]. */
    unsigned int *joined;             /**< Engine output [OWNS]. */
    unsigned int *labels[2];          /**< Labels of the previous and current frame [OWNS]. */
    unsigned long long *positive[2];  /**< Sign words of the previous and current frame [OWNS]. */
    unsigned int overlap_room;        /**< Pairs the overlap buffers hold. */
    unsigned int *overlap_before;     /**< Engine output [OWNS]. */
    unsigned int *overlap_after;      /**< Engine output [OWNS]. */
    unsigned int *overlap_shared;     /**< Engine output [OWNS]. */
    int *leaf_at_peak[2];             /**< Leaf per peak voxel of the earlier and later frame, else -1 [OWNS]. */
    unsigned int *basin_start[2];     /**< Offsets of each leaf's basin voxels, earlier and later [OWNS]. */
    unsigned int *basin_voxels[2];    /**< Basin voxels grouped by leaf, earlier and later [OWNS]. */
    ClimbMachine *machine;            /**< Every frame on the device, and the climb that runs itself, or NULL [OWNS]. */
} EngineBuffers;

/**
 * @brief Runs the basin engine on the buffered volume into one label slot and keeps the tree's fields.
 *
 * @param[in,out] buffers The engine buffers [BORROWS].
 * @param[in]     slot    Which label and sign slot to fill, 0 or 1.
 * @param[out]    frame   The tree frame; peaks and joined are filled [BORROWS].
 * @return                1 on success, 0 otherwise.
 */
static int grow_leaves(EngineBuffers *buffers, unsigned int slot, TreeFrame *frame)
{
    long count = -1L;
    unsigned int adjacency_have = 0u;
    unsigned int joined_have = 0u;
    for (;;)
    {
        BinomialBasinsRequest request;
        memset(&request, 0, sizeof(request));
        request.volume = buffers->volume;
        request.depth = buffers->depth;
        request.height = buffers->height;
        request.width = buffers->width;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            request.smooth_orders[axis] = SMOOTH_ORDERS[axis];
            request.background_orders[axis] = BACKGROUND_ORDERS[axis];
        }
        request.room = buffers->peak_room;
        request.peak_indices = buffers->peak_indices;
        request.sizes = buffers->sizes;
        request.sums = buffers->sums;
        request.peak_limbs = buffers->peak_limbs;
        // The tree reads joined pairs only, so adjacency is not asked for.
        request.adjacency_room = 0u;
        request.adjacency = NULL;
        request.adjacency_count = &adjacency_have;
        request.labels = buffers->labels[slot];
        request.residual_limbs = NULL;
        request.positive_words = buffers->positive[slot];
        request.joined_room = buffers->pair_room;
        request.joined = buffers->joined;
        request.joined_count = &joined_have;
        count = binomial_basins_run(&request);
        if (count < 0L)
        {
            return 0;
        }
        if (joined_have <= buffers->pair_room)
        {
            break;
        }
        // The pairs did not fit; the count they need is known now, so grow and call again.
        buffers->pair_room = joined_have;
        free(buffers->joined);
        buffers->joined = (unsigned int *)malloc((size_t)buffers->pair_room * 2u * sizeof(unsigned int));
        if (buffers->joined == NULL)
        {
            return 0;
        }
    }
    // Narrowing is safe: the peak count is at most the peak room, an unsigned int.
    frame->leaf_count = (unsigned int)count;
    frame->peaks = (unsigned int *)malloc(((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
    frame->joined = (unsigned int *)malloc(((size_t)joined_have + 1u) * 2u * sizeof(unsigned int));
    if ((frame->peaks == NULL) || (frame->joined == NULL))
    {
        return 0;
    }
    memcpy(frame->peaks, buffers->peak_indices, (size_t)frame->leaf_count * sizeof(unsigned int));
    frame->sizes = (unsigned int *)malloc(((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
    frame->sums = (unsigned long long *)malloc(((size_t)frame->leaf_count + 1u) * 3u * sizeof(unsigned long long));
    if ((frame->sizes == NULL) || (frame->sums == NULL))
    {
        return 0;
    }
    memcpy(frame->sizes, buffers->sizes, (size_t)frame->leaf_count * sizeof(unsigned int));
    memcpy(frame->sums, buffers->sums, (size_t)frame->leaf_count * 3u * sizeof(unsigned long long));
    frame->joined_count = joined_have;
    for (unsigned int pair = 0u; pair < joined_have; pair += 1u)
    {
        const int first = leaf_of_peak(frame->peaks, frame->leaf_count, buffers->joined[2u * pair]);
        const int second = leaf_of_peak(frame->peaks, frame->leaf_count, buffers->joined[2u * pair + 1u]);
        // Narrowing is safe: both joined peaks are positive peaks, so both leaves exist.
        frame->joined[2u * pair] = (unsigned int)first;
        frame->joined[2u * pair + 1u] = (unsigned int)second;
    }
    return 1;
}

/**
 * @brief The leaf of another frame a peak lands in, carried by a lag.
 *
 * @param[in] buffers The engine buffers, for the extents [BORROWS].
 * @param[in] peak    The peak raster index.
 * @param[in] lag     The lag z y x [BORROWS].
 * @param[in] labels  The other frame's labels [BORROWS].
 * @param[in] other   The other frame, for its peaks [BORROWS].
 * @return            The leaf, or -1 where the landing is outside the view or in no positive basin.
 */
static int land_peak(const EngineBuffers *buffers, unsigned int peak, const int *lag, const unsigned int *labels,
                     const TreeFrame *other)
{
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int rest = peak % plane;
    // Widening to long keeps a negative landing representable before the bounds test.
    const long z = (long)(peak / plane) + (long)lag[0];
    const long y = (long)(rest / buffers->width) + (long)lag[1];
    const long x = (long)(rest % buffers->width) + (long)lag[2];
    if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height) || (x < 0L)
     || (x >= (long)buffers->width))
    {
        return -1;
    }
    // Narrowing is safe: the landing lies inside the view, whose voxel count fits an unsigned int.
    const unsigned int voxel = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
    return leaf_of_peak(other->peaks, other->leaf_count, labels[voxel]);
}

/**
 * @brief Groups every voxel of a frame by the leaf whose basin holds it.
 *
 * @param[in,out] buffers The engine buffers [BORROWS].
 * @param[in]     slot    0 for the earlier frame, 1 for the later.
 * @param[in]     labels  That frame's labels [BORROWS].
 * @param[in]     frame   That frame's tree frame [BORROWS].
 */
static void group_basin_voxels(EngineBuffers *buffers, unsigned int slot, const unsigned int *labels,
                               const TreeFrame *frame)
{
    const unsigned int voxels = buffers->depth * buffers->height * buffers->width;
    int *const leaf_at_peak = buffers->leaf_at_peak[slot];
    unsigned int *const start = buffers->basin_start[slot];
    for (unsigned int leaf = 0u; leaf < frame->leaf_count; leaf += 1u)
    {
        // Narrowing is safe: a leaf count is below 2^31.
        leaf_at_peak[frame->peaks[leaf]] = (int)leaf;
    }
    memset(start, 0, ((size_t)frame->leaf_count + 2u) * sizeof(unsigned int));
    // A label runs along a row, so the leaf is looked up again only where the label changes.
    unsigned int run_label = labels[0];
    int run_leaf = leaf_at_peak[run_label];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (labels[voxel] != run_label)
        {
            run_label = labels[voxel];
            run_leaf = leaf_at_peak[run_label];
        }
        if (run_leaf >= 0)
        {
            // Narrowing is safe: the leaf was found, so it is nonnegative.
            start[(unsigned int)run_leaf + 1u] += 1u;
        }
    }
    for (unsigned int leaf = 0u; leaf < frame->leaf_count; leaf += 1u)
    {
        start[leaf + 1u] += start[leaf];
    }
    // The last offset slot is the fill cursor while grouping, then restored.
    run_label = labels[0];
    run_leaf = leaf_at_peak[run_label];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (labels[voxel] != run_label)
        {
            run_label = labels[voxel];
            run_leaf = leaf_at_peak[run_label];
        }
        if (run_leaf >= 0)
        {
            // Narrowing is safe: the leaf was found, so it is nonnegative.
            buffers->basin_voxels[slot][start[(unsigned int)run_leaf]] = voxel;
            start[(unsigned int)run_leaf] += 1u;
        }
    }
    for (unsigned int leaf = frame->leaf_count; leaf > 0u; leaf -= 1u)
    {
        start[leaf] = start[leaf - 1u];
    }
    start[0] = 0u;
    for (unsigned int leaf = 0u; leaf < frame->leaf_count; leaf += 1u)
    {
        leaf_at_peak[frame->peaks[leaf]] = -1;
    }
}

/**
 * @brief A basin's coherence with another frame at one lag, truthy or falsy per voxel: a voxel is true where
 *        its landing is inside the view and its sign equals the sign it lands on, and false otherwise, a
 *        landing outside the view included. The positive core must land on positive voxels and the margin
 *        on negative ones. There is no third value, so the coherence is the count of true voxels.
 *
 * @param[in] buffers        The engine buffers, for the extents [BORROWS].
 * @param[in] basin          The basin's voxels [BORROWS].
 * @param[in] count          How many.
 * @param[in] own_positive   The basin frame's sign words [BORROWS].
 * @param[in] other_positive The other frame's sign words [BORROWS].
 * @param[in] lag            The lag z y x [BORROWS].
 * @return                   The true voxels.
 */
static long long basin_coherence(const EngineBuffers *buffers, const unsigned int *basin, unsigned int count,
                                 const unsigned long long *own_positive, const unsigned long long *other_positive,
                                 const int *lag)
{
    const unsigned int plane = buffers->height * buffers->width;
    long long score = 0LL;
    for (unsigned int member = 0u; member < count; member += 1u)
    {
        const unsigned int voxel = basin[member];
        const unsigned int rest = voxel % plane;
        // Widening to long keeps a negative landing representable before the bounds test.
        const long z = (long)(voxel / plane) + (long)lag[0];
        const long y = (long)(rest / buffers->width) + (long)lag[1];
        const long x = (long)(rest % buffers->width) + (long)lag[2];
        if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height) || (x < 0L)
         || (x >= (long)buffers->width))
        {
            // Outside the view is false.
            continue;
        }
        // Narrowing is safe: the landing lies inside the view.
        const unsigned int landed = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
        const unsigned long long own = (own_positive[voxel / 64u] >> (voxel % 64u)) & 1ULL;
        const unsigned long long other = (other_positive[landed / 64u] >> (landed % 64u)) & 1ULL;
        score += (own == other) ? 1LL : 0LL;
    }
    return score;
}

/**
 * @brief Climbs a basin's lag by steepest ascent of its coherence over the 26 neighbouring lags,
 *        from a starting lag, until no neighbour is strictly more coherent. No window bounds the climb.
 *
 * Among equally coherent neighbours the one with the shorter weighted squared lag is taken, then the
 * first in z y x order, so the climb is one path.
 *
 * @param[in]  buffers        The engine buffers [BORROWS].
 * @param[in]  basin          The basin's voxels [BORROWS].
 * @param[in]  count          How many.
 * @param[in]  own_positive   The basin frame's sign words [BORROWS].
 * @param[in]  other_positive The other frame's sign words [BORROWS].
 * @param[in]  start          The starting lag [BORROWS].
 * @param[out] climbed        The lag reached [BORROWS].
 */
static void climb_lag(const EngineBuffers *buffers, unsigned int slot, unsigned int leaf, const unsigned int *contact_start,
                      const unsigned int *contacts, const unsigned long long *own_positive,
                      const unsigned long long *other_positive, const int *start, int *climbed)
{
    // A basin alone, or, where contacts are given, the basin and every basin it touches: sticky cells move
    // together, so the patch's coherence is what the lag climbs.
    const auto patch_coherence = [&](const int *lag) -> long long
    {
        const unsigned int *const basin_start = buffers->basin_start[slot];
        long long total = basin_coherence(buffers, &buffers->basin_voxels[slot][basin_start[leaf]],
                                          basin_start[leaf + 1u] - basin_start[leaf], own_positive, other_positive, lag);
        for (unsigned int contact = (contact_start != NULL) ? contact_start[leaf] : 0u;
             (contact_start != NULL) && (contact < contact_start[leaf + 1u]); contact += 1u)
        {
            const unsigned int near = contacts[contact];
            total += basin_coherence(buffers, &buffers->basin_voxels[slot][basin_start[near]],
                                     basin_start[near + 1u] - basin_start[near], own_positive, other_positive, lag);
        }
        return total;
    };
    int here[3] = {start[0], start[1], start[2]};
    long long here_score = patch_coherence(here);
    for (;;)
    {
        int best[3] = {here[0], here[1], here[2]};
        long long best_score = here_score;
        unsigned long long best_length = 0ULL;
        int moved = 0;
        for (int step_z = -1; step_z <= 1; step_z += 1)
        {
            for (int step_y = -1; step_y <= 1; step_y += 1)
            {
                for (int step_x = -1; step_x <= 1; step_x += 1)
                {
                    if ((step_z == 0) && (step_y == 0) && (step_x == 0))
                    {
                        continue;
                    }
                    const int candidate[3] = {here[0] + step_z, here[1] + step_y, here[2] + step_x};
                    const long long score = patch_coherence(candidate);
                    // Widening: each squared lag component is nonnegative.
                    const unsigned long long length = (unsigned long long)AXIS_WEIGHTS[0]
                                                        * (unsigned long long)(candidate[0] * candidate[0])
                                                    + (unsigned long long)(candidate[1] * candidate[1])
                                                    + (unsigned long long)(candidate[2] * candidate[2]);
                    if ((score > best_score) || ((moved != 0) && (score == best_score) && (length < best_length)))
                    {
                        best[0] = candidate[0];
                        best[1] = candidate[1];
                        best[2] = candidate[2];
                        best_score = score;
                        best_length = length;
                        moved = 1;
                    }
                }
            }
        }
        if (moved == 0)
        {
            break;
        }
        here[0] = best[0];
        here[1] = best[1];
        here[2] = best[2];
        here_score = best_score;
    }
    climbed[0] = here[0];
    climbed[1] = here[1];
    climbed[2] = here[2];
}

/**
 * @brief Each leaf's direct contacts, both directions of every joined pair, as offsets and a flat list.
 *
 * @param[in]  tree          The frame [BORROWS].
 * @param[out] contact_start leaf_count + 1 offsets, allocated here [OWNS].
 * @param[out] contacts      The contacts, allocated here [OWNS].
 * @return                   1 on success, 0 on a failure.
 */
static int frame_contacts(const TreeFrame *tree, unsigned int **contact_start, unsigned int **contacts)
{
    *contact_start = (unsigned int *)calloc((size_t)tree->leaf_count + 2u, sizeof(unsigned int));
    *contacts = (unsigned int *)malloc(((size_t)tree->joined_count + 1u) * 2u * sizeof(unsigned int));
    if ((*contact_start == NULL) || (*contacts == NULL))
    {
        return 0;
    }
    unsigned int *const start = *contact_start;
    for (unsigned int pair = 0u; pair < tree->joined_count; pair += 1u)
    {
        start[tree->joined[2u * pair] + 1u] += 1u;
        start[tree->joined[2u * pair + 1u] + 1u] += 1u;
    }
    for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
    {
        start[leaf + 1u] += start[leaf];
    }
    for (unsigned int pair = 0u; pair < tree->joined_count; pair += 1u)
    {
        const unsigned int left = tree->joined[2u * pair];
        const unsigned int right = tree->joined[2u * pair + 1u];
        (*contacts)[start[left]] = right;
        start[left] += 1u;
        (*contacts)[start[right]] = left;
        start[right] += 1u;
    }
    for (unsigned int leaf = tree->leaf_count; leaf > 0u; leaf -= 1u)
    {
        start[leaf] = start[leaf - 1u];
    }
    start[0] = 0u;
    return 1;
}

/**
 * @brief Every leaf casts its voxels by its own lag, as cast_triples does where it is defined.
 *
 * @param[in,out] buffers The buffers [BORROWS].
 * @param[in,out] earlier The earlier frame [BORROWS].
 * @param[in]     later   The later frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
static int cast_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later);

/**
 * @brief The view moves with each candidate and counts what stays still, as still_triples does where it is
 *        defined.
 *
 * @param[in,out] buffers The buffers [BORROWS].
 * @param[in,out] earlier The earlier frame [BORROWS].
 * @param[in]     later   The later frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
static int still_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later);

/**
 * @brief The view's motion, landings both ways, and the overlap between two consecutive frames.
 *
 * @param[in,out] buffers The engine buffers; slot 0 holds the earlier frame, slot 1 the later [BORROWS].
 * @param[in,out] earlier The earlier frame; forward and the overlap are filled [BORROWS].
 * @param[in,out] later   The later frame; backward is filled [BORROWS].
 * @param[in]     rules   The tree's rules [BORROWS].
 * @param[in,out] clocks  Stage times, added to [BORROWS].
 * @return                1 on success, 0 otherwise.
 */
static int relate_frames(EngineBuffers *buffers, TreeFrame *earlier, TreeFrame *later, const TreeRules *rules,
                         StageClock *clocks)
{
    int lag[3] = {0, 0, 0};
    unsigned long long mark = clock_microseconds();
    if (rules->keep_view == 0)
    {
        ShiftAgreementRequest motion;
        memset(&motion, 0, sizeof(motion));
        motion.axes = 3u;
        motion.extents[0] = buffers->depth;
        motion.extents[1] = buffers->height;
        motion.extents[2] = buffers->width;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            motion.weights[axis] = AXIS_WEIGHTS[axis];
        }
        motion.before = buffers->positive[0];
        motion.after = buffers->positive[1];
        motion.counts = NULL;
        ShiftAgreementRequest again = motion;
        size_t padded_total = 1u;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            unsigned long long power = 1ull;
            while (power < (2ull * (unsigned long long)motion.extents[axis]) - 1ull)
            {
                power <<= 1u;
            }
            padded_total *= (size_t)power;
        }
        if (rules->motion_check != 0)
        {
            motion.counts = (unsigned int *)malloc(padded_total * sizeof(unsigned int));
            again.counts = (unsigned int *)malloc(padded_total * sizeof(unsigned int));
        }
        int moved_ok = ((rules->motion_check == 0) || ((motion.counts != NULL) && (again.counts != NULL)))
                    && (shift_agreement_run(&motion) == 0L);
        if ((moved_ok != 0) && (rules->motion_check != 0))
        {
            // The first call kept this pair's after, which is not this pair's before, so the second call transforms
            // both views afresh; every count and the choice must be the same.
            moved_ok = (shift_agreement_run(&again) == 0L);
            if ((moved_ok != 0) && ((memcmp(motion.counts, again.counts, padded_total * sizeof(unsigned int)) != 0)
                                    || (memcmp(motion.lag, again.lag, sizeof(motion.lag)) != 0)
                                    || (motion.agreement != again.agreement)))
            {
                fprintf(stderr, "    motion disagrees: frame %u\n", earlier->time);
            }
        }
        free(motion.counts);
        free(again.counts);
        if (moved_ok == 0)
        {
            return 0;
        }
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            lag[axis] = motion.lag[axis];
        }
    }
    const int back[3] = {-lag[0], -lag[1], -lag[2]};
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        earlier->lag_to_next[axis] = lag[axis];
    }
    // How far the clock dragged between these two frames. A step is a rate, so a step read over one gap is
    // carried over another by that ratio: a cell going nowhere stays nowhere however long the clock drags, and
    // a cell going somewhere departs further the longer it drags.
    earlier->step_next = later->time - earlier->time;
    later->step_back = later->time - earlier->time;
    clocks->motion += clock_microseconds() - mark;
    mark = clock_microseconds();

    earlier->forward = (int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(int));
    later->backward = (int *)malloc(((size_t)later->leaf_count + 1u) * sizeof(int));
    if ((earlier->forward == NULL) || (later->backward == NULL))
    {
        return 0;
    }
    if (rules->climb == 0)
    {
        for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
        {
            earlier->forward[leaf] = land_peak(buffers, earlier->peaks[leaf], lag, buffers->labels[1], later);
        }
        for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
        {
            later->backward[leaf] = land_peak(buffers, later->peaks[leaf], back, buffers->labels[0], earlier);
        }
    }
    else
    {
        // Each basin carries its peak by its own lag: the one its whole basin climbs to, from the view's lag,
        // forward against the later frame and backward against the earlier. The device climb is pended with the
        // machine, which writes the lags and the landings when it runs; the host reference climbs here.
        earlier->forward_lag = (int *)malloc(((size_t)earlier->leaf_count + 1u) * 3u * sizeof(int));
        later->backward_lag = (int *)malloc(((size_t)later->leaf_count + 1u) * 3u * sizeof(int));
        int climbed = (earlier->forward_lag != NULL) && (later->backward_lag != NULL);
        if ((climbed != 0) && (rules->climb != 2))
        {
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = earlier->time;
            pair.later = later->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                pair.lag[axis] = lag[axis];
            }
            pair.earlier_leaves = earlier->leaf_count;
            pair.earlier_peaks = earlier->peaks;
            pair.later_leaves = later->leaf_count;
            pair.later_peaks = later->peaks;
            pair.forward_lags = earlier->forward_lag;
            pair.forward = earlier->forward;
            pair.backward_lags = later->backward_lag;
            pair.backward = later->backward;
            // The observed coherence each leaf holds at its fixed point, which its null draws are ranked against.
            earlier->forward_held = (unsigned int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned int));
            pair.forward_held = earlier->forward_held;
            climbed = (earlier->forward_held != NULL) && (climb_machine_pend(buffers->machine, &pair) != 0);
        }
        if ((climbed != 0) && (rules->climb >= 2))
        {
            // Climb 2 takes the host reference only; climb 3 keeps it beside the machine's, to be compared.
            int *const forward_lags = (rules->climb == 2) ? earlier->forward_lag
                                                          : (int *)malloc(((size_t)earlier->leaf_count + 1u) * 3u * sizeof(int));
            int *const backward_lags = (rules->climb == 2) ? later->backward_lag
                                                           : (int *)malloc(((size_t)later->leaf_count + 1u) * 3u * sizeof(int));
            earlier->check_forward_lag = (rules->climb == 3) ? forward_lags : NULL;
            later->check_backward_lag = (rules->climb == 3) ? backward_lags : NULL;
            unsigned int *contact_start[2] = {NULL, NULL};
            unsigned int *contacts[2] = {NULL, NULL};
            climbed = (forward_lags != NULL) && (backward_lags != NULL);
            climbed = climbed && ((rules->sticky == 0) || ((frame_contacts(earlier, &contact_start[0], &contacts[0]) != 0)
                                                           && (frame_contacts(later, &contact_start[1], &contacts[1]) != 0)));
            for (unsigned int leaf = 0u; (climbed != 0) && (leaf < earlier->leaf_count); leaf += 1u)
            {
                climb_lag(buffers, 0u, leaf, contact_start[0], contacts[0], buffers->positive[0], buffers->positive[1], lag,
                          &forward_lags[3u * leaf]);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (leaf < later->leaf_count); leaf += 1u)
            {
                climb_lag(buffers, 1u, leaf, contact_start[1], contacts[1], buffers->positive[1], buffers->positive[0], back,
                          &backward_lags[3u * leaf]);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (rules->climb == 2) && (leaf < earlier->leaf_count); leaf += 1u)
            {
                earlier->forward[leaf] = land_peak(buffers, earlier->peaks[leaf], &forward_lags[3u * leaf],
                                                   buffers->labels[1], later);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (rules->climb == 2) && (leaf < later->leaf_count); leaf += 1u)
            {
                later->backward[leaf] = land_peak(buffers, later->peaks[leaf], &backward_lags[3u * leaf],
                                                  buffers->labels[0], earlier);
            }
            free(contact_start[0]);
            free(contact_start[1]);
            free(contacts[0]);
            free(contacts[1]);
        }
        if (climbed == 0)
        {
            return 0;
        }
    }
    clocks->landing += clock_microseconds() - mark;
    mark = clock_microseconds();

    if (rules->pick == 0)
    {
        return 1;
    }
    long total = -1L;
    for (;;)
    {
        BasinOverlapRequest overlap;
        memset(&overlap, 0, sizeof(overlap));
        // Both frames are already on the device, uploaded when each arrived.
        overlap.labels_before = climb_machine_labels(buffers->machine, earlier->time);
        overlap.positive_before = climb_machine_positive(buffers->machine, earlier->time);
        overlap.labels_after = climb_machine_labels(buffers->machine, later->time);
        overlap.positive_after = climb_machine_positive(buffers->machine, later->time);
        overlap.axes = 3u;
        overlap.extents[0] = buffers->depth;
        overlap.extents[1] = buffers->height;
        overlap.extents[2] = buffers->width;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            overlap.lag[axis] = lag[axis];
        }
        overlap.voxels = buffers->depth * buffers->height * buffers->width;
        overlap.room = buffers->overlap_room;
        overlap.peaks_before = buffers->overlap_before;
        overlap.peaks_after = buffers->overlap_after;
        overlap.counts = buffers->overlap_shared;
        total = basin_overlap_run_on_device(&overlap);
        if (total < 0L)
        {
            return 0;
        }
        // Widening: the room is an unsigned int and the total a nonnegative long.
        if ((unsigned long)total <= (unsigned long)buffers->overlap_room)
        {
            break;
        }
        // The pairs did not fit; the count they need is known now, so the second call is exact.
        // Narrowing is safe: the engine never returns more than BASIN_OVERLAP_ROOM_LIMIT.
        buffers->overlap_room = (unsigned int)total;
        free(buffers->overlap_before);
        free(buffers->overlap_after);
        free(buffers->overlap_shared);
        buffers->overlap_before = (unsigned int *)malloc((size_t)buffers->overlap_room * sizeof(unsigned int));
        buffers->overlap_after = (unsigned int *)malloc((size_t)buffers->overlap_room * sizeof(unsigned int));
        buffers->overlap_shared = (unsigned int *)malloc((size_t)buffers->overlap_room * sizeof(unsigned int));
        if ((buffers->overlap_before == NULL) || (buffers->overlap_after == NULL) || (buffers->overlap_shared == NULL))
        {
            return 0;
        }
    }
    // Only pairs of objects: a basin whose peak is not positive holds no object. The engine returns the
    // pairs ascending by peak before, and leaves follow peak order, so they stay grouped by leaf before.
    // Narrowing is safe: the total fits the room, an unsigned int.
    const unsigned int pairs = (unsigned int)total;
    earlier->triple_start = (unsigned int *)calloc((size_t)earlier->leaf_count + 1u, sizeof(unsigned int));
    earlier->triple_after = (unsigned int *)malloc(((size_t)pairs + 1u) * sizeof(unsigned int));
    earlier->triple_shared = (unsigned int *)malloc(((size_t)pairs + 1u) * sizeof(unsigned int));
    if ((earlier->triple_start == NULL) || (earlier->triple_after == NULL) || (earlier->triple_shared == NULL))
    {
        return 0;
    }
    unsigned int kept = 0u;
    for (unsigned int pair = 0u; pair < pairs; pair += 1u)
    {
        const int before = leaf_of_peak(earlier->peaks, earlier->leaf_count, buffers->overlap_before[pair]);
        const int after = leaf_of_peak(later->peaks, later->leaf_count, buffers->overlap_after[pair]);
        if ((before < 0) || (after < 0))
        {
            continue;
        }
        // Narrowing is safe: both leaves were found, so both are nonnegative.
        earlier->triple_start[(unsigned int)before + 1u] += 1u;
        earlier->triple_after[kept] = (unsigned int)after;
        earlier->triple_shared[kept] = buffers->overlap_shared[pair];
        kept += 1u;
    }
    for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
    {
        earlier->triple_start[leaf + 1u] += earlier->triple_start[leaf];
    }
    earlier->triple_count = kept;
    clocks->overlap += clock_microseconds() - mark;
    if (rules->cast != 0)
    {
        // Beside what the whole view's lag met, what each cell's own lag meets, the larger of the two standing
        // for every pair. A cell moving against the group is met where it went, and nothing else is given up.
        const unsigned long long casting = clock_microseconds();
        const int made = cast_triples(buffers, earlier, later);
        clocks->overlap += clock_microseconds() - casting;
        return made;
    }
    if (rules->parallax != 0)
    {
        // The view goes along with each candidate in turn, and what stays still under that move is counted.
        const unsigned long long moving = clock_microseconds();
        const int made = still_triples(buffers, earlier, later);
        clocks->overlap += clock_microseconds() - moving;
        return made;
    }
    return 1;
}

/**
 * @brief Path halving root of a union find over leaves or nodes, as the reference walks it.
 *
 * @param[in,out] parent The forest [BORROWS].
 * @param[in]     member The member whose root is sought.
 * @return               The root.
 */
static unsigned int find_root(unsigned int *parent, unsigned int member)
{
    while (parent[member] != member)
    {
        parent[member] = parent[parent[member]];
        member = parent[member];
    }
    return member;
}

/**
 * @brief Groups one frame's leaves into objects: fragments, and merge-split where it is set.
 *
 * @param[in,out] frame    The frame [BORROWS].
 * @param[in]     previous The frame before when backward exists, otherwise NULL [BORROWS].
 * @param[in]     rules    The tree's rules [BORROWS].
 * @return                 1 on success, 0 otherwise.
 */
static int group_objects(TreeFrame *frame, const TreeFrame *previous, const TreeFrame *next, const TreeRules *rules)
{
    const unsigned int count = frame->leaf_count;
    unsigned int *const parent = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    // A second pass groups the frame again from its leaves, so whatever a first pass made is let go here.
    free(frame->object_of);
    free(frame->member_start);
    free(frame->members);
    frame->object_of = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    frame->member_start = (unsigned int *)calloc((size_t)count + 2u, sizeof(unsigned int));
    frame->members = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    if ((parent == NULL) || (frame->object_of == NULL) || (frame->member_start == NULL) || (frame->members == NULL))
    {
        free(parent);
        return 0;
    }
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        parent[leaf] = leaf;
    }
    for (unsigned int pair = 0u; pair < frame->joined_count; pair += 1u)
    {
        const unsigned int left = frame->joined[2u * pair];
        const unsigned int right = frame->joined[2u * pair + 1u];
        int same_origin = 0;
        if (frame->backward != NULL)
        {
            const int left_from = frame->backward[left];
            const int right_from = frame->backward[right];
            if ((left_from >= 0) && (right_from >= 0))
            {
                if ((rules->merge_split != 0) && (previous != NULL))
                {
                    // Two joined leaves whose peaks came from one earlier object are two halves of one
                    // over-cut cell. Narrowing is safe: both sources were found.
                    same_origin = (previous->object_of[(unsigned int)left_from]
                                   == previous->object_of[(unsigned int)right_from]);
                }
                else
                {
                    same_origin = (left_from == right_from);
                }
            }
        }
        int same_destination = 0;
        int destinations_differ = 0;
        if (frame->forward != NULL)
        {
            same_destination = (frame->forward[left] >= 0) && (frame->forward[left] == frame->forward[right]);
            // Two halves of one cell go to one place. Where both halves land and the landings differ, they are
            // two cells that touch, whatever they came from, and the repair leaves them apart. The landings are
            // read as the next frame's objects wherever that frame has been grouped already, since two landings
            // in one cell's two halves are one place, not two.
            const int left_to = frame->forward[left];
            const int right_to = frame->forward[right];
            const int apart = ((next != NULL) && (next->object_of != NULL))
                            ? (next->object_of[(unsigned int)((left_to >= 0) ? left_to : 0)]
                               != next->object_of[(unsigned int)((right_to >= 0) ? right_to : 0)])
                            : (left_to != right_to);
            destinations_differ = (left_to >= 0) && (right_to >= 0) && (apart != 0);
        }
        const int origin_holds = (same_origin != 0) && ((rules->agree == 0) || (destinations_differ == 0));
        if ((origin_holds != 0) || (same_destination != 0))
        {
            const unsigned int first = find_root(parent, left);
            const unsigned int second = find_root(parent, right);
            if (first != second)
            {
                parent[second] = first;
            }
        }
    }
    // Objects are numbered by their root, ascending, as the reference sorts its groups.
    unsigned int *const number_of_root = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    if (number_of_root == NULL)
    {
        free(parent);
        return 0;
    }
    unsigned int objects = 0u;
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        if (find_root(parent, leaf) == leaf)
        {
            number_of_root[leaf] = objects;
            objects += 1u;
        }
    }
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        frame->object_of[leaf] = number_of_root[find_root(parent, leaf)];
        frame->member_start[frame->object_of[leaf] + 1u] += 1u;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        frame->member_start[object + 1u] += frame->member_start[object];
    }
    unsigned int *const fill = (unsigned int *)malloc(((size_t)objects + 1u) * sizeof(unsigned int));
    if (fill == NULL)
    {
        free(parent);
        free(number_of_root);
        return 0;
    }
    memcpy(fill, frame->member_start, (size_t)objects * sizeof(unsigned int));
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        frame->members[fill[frame->object_of[leaf]]] = leaf;
        fill[frame->object_of[leaf]] += 1u;
    }
    frame->object_count = objects;
    free(fill);
    free(number_of_root);
    free(parent);
    return 1;
}

/**
 * @brief The weighted squared magnitude of the disagreement between the two directions: what a leaf of the
 *        earlier frame says its step is, and what a leaf of the later frame says its step back is. Two views of
 *        one cell mirror each other, so their sum is nothing; two different cells do not, and their sum is the
 *        magnitude of how much they differ. The centres cancel in that difference, so this is motion against
 *        motion and nothing else.
 *
 * Each side is read at its lag, the step it was carried by, and at its lead, the step it was already making
 * carried on, and the pair of them that agrees most stands. The sweep boxes the disagreement a voxel wide at
 * first and doubling out, so the step it is met at says how far the two are from mirroring.
 *
 * @param[in] earlier The earlier frame [BORROWS].
 * @param[in] leaf    The leaf going somewhere.
 * @param[in] later   The later frame [BORROWS].
 * @param[in] other   The leaf it is measured against.
 * @return            The squared magnitude.
 */
static unsigned long long leaf_disagreement(const TreeFrame *earlier, unsigned int leaf, const TreeFrame *later,
                                            unsigned int other)
{
    // This side's lag is the step it was carried by; its lead is the step it was already making, carried on.
    // The other side reads the same way in its own direction: its lag is the step it was carried back by, its
    // lead the step it was already making back. Two views of one cell mirror, so a side's step plus the other's
    // is nothing.
    const int *const lag = (earlier->forward_lag != NULL) ? &earlier->forward_lag[3u * (size_t)leaf]
                                                          : earlier->lag_to_next;
    const int *const came = (earlier->backward_lag != NULL) ? &earlier->backward_lag[3u * (size_t)leaf] : NULL;
    const int *const back = (later->backward_lag != NULL) ? &later->backward_lag[3u * (size_t)other] : NULL;
    const int *const onward = (later->forward_lag != NULL) ? &later->forward_lag[3u * (size_t)other] : NULL;
    const int other_lag[3] = {(back != NULL) ? back[0] : -lag[0], (back != NULL) ? back[1] : -lag[1],
                              (back != NULL) ? back[2] : -lag[2]};
    // A lead is a step read over the gap before it and carried over the gap ahead, so it is scaled by the one
    // and divided by the other, rounded half away from zero. A step of nothing scales to nothing.
    const long long ahead = (long long)((later->step_back != 0u) ? later->step_back : 1u);
    const long long behind = (long long)((earlier->step_back != 0u) ? earlier->step_back : 1u);
    const long long onwards = (long long)((later->step_next != 0u) ? later->step_next : 1u);
    int lead[3];
    int other_lead[3];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const long long mine = (came != NULL) ? (-(long long)came[axis] * ahead) : ((long long)lag[axis] * behind);
        const long long theirs = (onward != NULL) ? (-(long long)onward[axis] * ahead)
                                                  : ((long long)other_lag[axis] * onwards);
        // Narrowing is safe: a scaled step of the view is far below 2^31.
        lead[axis] = (int)((mine + ((mine >= 0ll) ? behind : -behind) / 2ll) / behind);
        other_lead[axis] = (int)((theirs + ((theirs >= 0ll) ? onwards : -onwards) / 2ll) / onwards);
    }
    unsigned long long shortest = 0xFFFFFFFFFFFFFFFFull;
    for (unsigned int pairing = 0u; pairing < 4u; pairing += 1u)
    {
        // Lag against lag, lag against lead, lead against lag, lead against lead: the way the two sides are
        // read is swept as well, and the reading they agree most in stands.
        const int *const mine = ((pairing & 1u) == 0u) ? lag : lead;
        const int *const theirs = ((pairing & 2u) == 0u) ? other_lag : other_lead;
        unsigned long long magnitude = 0ull;
        unsigned long long widest = 0ull;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long apart = (long long)mine[axis] + (long long)theirs[axis];
            // Widening to unsigned long long is exact: a squared step of the view is far below 2^63.
            const unsigned long long spread = (unsigned long long)((apart < 0ll) ? -apart : apart);
            magnitude += (unsigned long long)(apart * apart) * (unsigned long long)AXIS_WEIGHTS[axis];
            widest = (spread > widest) ? spread : widest;
        }
        // The step is the finest box that holds the widest axis, read off once instead of walked.
        unsigned int step = 0u;
        for (unsigned int sweep = 0u; sweep < LINK_SWEEP_STEPS; sweep += 1u)
        {
            step += (unsigned int)((1ull << step) < widest);
        }
        // The step the disagreement was boxed at leads, and the magnitude orders what one step holds.
        const unsigned long long swept = ((unsigned long long)step << LINK_MAGNITUDE_BITS)
                                       | (magnitude & LINK_MAGNITUDE_MASK);
        shortest = (swept < shortest) ? swept : shortest;
    }
    return shortest;
}

/**
 * @brief Every leaf of a frame casts its own voxels onto the next frame, each carried by the lag that leaf
 *        climbed to, and counts where they land: per pair of leaves, the voxels of the earlier that fall in the
 *        later. That is the same count the overlap engine takes, except that each cell is carried by its own
 *        motion instead of the whole view's, so a cell moving against the group is still met where it went.
 *
 * @param[in,out] buffers The buffers, the earlier frame grouped in slot 0 and the later's labels in slot 1 [BORROWS].
 * @param[in,out] earlier The earlier frame, which takes the triples [BORROWS].
 * @param[in]     later   The later frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
static int cast_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later)
{
    const long long depth = (long long)buffers->depth;
    const long long height = (long long)buffers->height;
    const long long width = (long long)buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int *const labels = buffers->labels[1];
    int *const leaf_at_peak = buffers->leaf_at_peak[1];
    unsigned int *const counts = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const held = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const stamp = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const touched = (unsigned int *)malloc(((size_t)later->leaf_count + 1u) * sizeof(unsigned int));
    // A leaf casts onto at most as many leaves as it has voxels, and the room grows where that is not enough.
    size_t room = (size_t)earlier->leaf_count * 8u + 16u;
    unsigned int *const starts = (unsigned int *)calloc((size_t)earlier->leaf_count + 2u, sizeof(unsigned int));
    unsigned int *after = (unsigned int *)malloc(room * sizeof(unsigned int));
    unsigned int *shared = (unsigned int *)malloc(room * sizeof(unsigned int));
    int ok = (counts != NULL) && (held != NULL) && (stamp != NULL) && (touched != NULL) && (starts != NULL)
          && (after != NULL)
          && (shared != NULL);
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < later->leaf_count); leaf += 1u)
    {
        // Narrowing is safe: a leaf count is below 2^31.
        leaf_at_peak[later->peaks[leaf]] = (int)leaf;
    }
    unsigned int kept = 0u;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        const int *const lag = (earlier->forward_lag != NULL) ? &earlier->forward_lag[3u * (size_t)leaf]
                                                              : earlier->lag_to_next;
        unsigned int met = 0u;
        // What the whole view's lag already met stands beside what this cell's own lag meets, so a cell that
        // moved against the group is met where it went without losing what the group's lag saw.
        const unsigned int held_first = (earlier->triple_start != NULL) ? earlier->triple_start[leaf] : 0u;
        const unsigned int held_past = (earlier->triple_start != NULL) ? earlier->triple_start[leaf + 1u] : 0u;
        for (unsigned int pair = held_first; pair < held_past; pair += 1u)
        {
            const unsigned int found = earlier->triple_after[pair];
            const unsigned int fresh = (unsigned int)(stamp[found] != (leaf + 1u));
            touched[met] = found;
            met += fresh;
            counts[found] = (fresh != 0u) ? 0u : counts[found];
            held[found] = (fresh != 0u) ? 0u : held[found];
            stamp[found] = leaf + 1u;
            held[found] = (earlier->triple_shared[pair] > held[found]) ? earlier->triple_shared[pair] : held[found];
        }
        for (unsigned int at = buffers->basin_start[0][leaf]; at < buffers->basin_start[0][leaf + 1u]; at += 1u)
        {
            const unsigned int voxel = buffers->basin_voxels[0][at];
            const unsigned int rest = voxel % plane;
            // Widening to long long keeps a landing outside the view representable before the bounds test.
            const long long z = (long long)(voxel / plane) + (long long)lag[0];
            const long long y = (long long)(rest / buffers->width) + (long long)lag[1];
            const long long x = (long long)(rest % buffers->width) + (long long)lag[2];
            const int inside = (z >= 0ll) && (z < depth) && (y >= 0ll) && (y < height) && (x >= 0ll) && (x < width);
            // Narrowing is safe: the index is read only where the landing lies inside the view.
            const unsigned int landed = (unsigned int)(((z * height) + y) * width + x);
            const int other = (inside != 0) ? leaf_at_peak[labels[landed]] : -1;
            if (other < 0)
            {
                continue;
            }
            // Narrowing is safe: the leaf was found, so it is nonnegative.
            const unsigned int found = (unsigned int)other;
            // A leaf met for the first time by this one takes a place in the list and starts its count at zero.
            const unsigned int fresh = (unsigned int)(stamp[found] != (leaf + 1u));
            touched[met] = found;
            met += fresh;
            counts[found] = (fresh != 0u) ? 0u : counts[found];
            held[found] = (fresh != 0u) ? 0u : held[found];
            stamp[found] = leaf + 1u;
            counts[found] += 1u;
        }
        if ((kept + met) > room)
        {
            const size_t grown = (kept + met) * 2u;
            unsigned int *const wider_after = (unsigned int *)realloc(after, grown * sizeof(unsigned int));
            unsigned int *const wider_shared = (unsigned int *)realloc(shared, grown * sizeof(unsigned int));
            after = (wider_after != NULL) ? wider_after : after;
            shared = (wider_shared != NULL) ? wider_shared : shared;
            ok = (wider_after != NULL) && (wider_shared != NULL);
            room = (ok != 0) ? grown : room;
        }
        // The leaves met, ascending, so a pair's place never depends on the order the voxels were walked.
        for (unsigned int step = 1u; (ok != 0) && (step < met); step += 1u)
        {
            const unsigned int value = touched[step];
            unsigned int place = step;
            while ((place > 0u) && (touched[place - 1u] > value))
            {
                touched[place] = touched[place - 1u];
                place -= 1u;
            }
            touched[place] = value;
        }
        for (unsigned int step = 0u; (ok != 0) && (step < met); step += 1u)
        {
            after[kept] = touched[step];
            // The larger of the two: what the group's lag met, and what this cell's own lag met.
            shared[kept] = (counts[touched[step]] > held[touched[step]]) ? counts[touched[step]]
                                                                        : held[touched[step]];
            counts[touched[step]] = 0u;
            held[touched[step]] = 0u;
            kept += 1u;
        }
        starts[leaf + 1u] = met;
    }
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        starts[leaf + 1u] += starts[leaf];
    }
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = -1;
    }
    free(counts);
    free(held);
    free(stamp);
    free(touched);
    if (ok == 0)
    {
        free(starts);
        free(after);
        free(shared);
        return 0;
    }
    free(earlier->triple_start);
    free(earlier->triple_after);
    free(earlier->triple_shared);
    earlier->triple_start = starts;
    earlier->triple_after = after;
    earlier->triple_shared = shared;
    earlier->triple_count = kept;
    return 1;
}

/**
 * @brief An object's centre, as its leaves' index sums divided by their voxels, rounded half away from zero.
 *
 * @param[in]  frame  The frame [BORROWS].
 * @param[in]  object The object.
 * @param[out] centre Three: z y x [BORROWS].
 */
static void object_centre(const TreeFrame *frame, unsigned int object, long long *centre)
{
    unsigned long long voxels = 0ull;
    unsigned long long sums[3] = {0ull, 0ull, 0ull};
    for (unsigned int member = frame->member_start[object]; member < frame->member_start[object + 1u]; member += 1u)
    {
        const unsigned int leaf = frame->members[member];
        voxels += (unsigned long long)frame->sizes[leaf];
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            sums[axis] += frame->sums[(3u * (size_t)leaf) + axis];
        }
    }
    // An object holds at least one positive voxel, so the divisor is never zero.
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        centre[axis] = (long long)(((sums[axis] * 2ull) + voxels) / (voxels * 2ull));
    }
}

/**
 * @brief How sharply a track bends where it goes through a candidate: the second difference of the places it
 *        passes, weighted as the view weighs them. A cell carries on the way it was going, so a true step arcs
 *        and a step onto a neighbour kinks. Where nothing comes before or after there is no bend to read and
 *        the arc is nothing, which leaves the candidates as they stood.
 *
 * @param[in] before    The frame before the earlier one, or NULL [BORROWS].
 * @param[in] earlier   The earlier frame [BORROWS].
 * @param[in] object    The object of the earlier frame.
 * @param[in] later     The later frame [BORROWS].
 * @param[in] candidate The object of the later frame the track would go through.
 * @param[in] after     The frame after the later one, or NULL [BORROWS].
 * @return              The weighted squared bend, nothing where there is nothing to read.
 */
static unsigned long long track_bend(const TreeFrame *before, const TreeFrame *earlier, unsigned int object,
                                     const TreeFrame *later, unsigned int candidate, const TreeFrame *after)
{
    long long here[3];
    long long there[3];
    object_centre(earlier, object, here);
    object_centre(later, candidate, there);
    unsigned long long bend = 0ull;
    // Where the cell came from: the object its own leaves land back in, taken from the leaf holding most voxels.
    unsigned int came_from = 0xFFFFFFFFu;
    unsigned int widest = 0u;
    for (unsigned int member = earlier->member_start[object]; (before != NULL) && (earlier->backward != NULL)
         && (member < earlier->member_start[object + 1u]); member += 1u)
    {
        const unsigned int leaf = earlier->members[member];
        const int back = earlier->backward[leaf];
        const unsigned int voxels = earlier->sizes[leaf];
        came_from = ((back >= 0) && (voxels > widest)) ? before->object_of[(unsigned int)back] : came_from;
        widest = ((back >= 0) && (voxels > widest)) ? voxels : widest;
    }
    if (came_from != 0xFFFFFFFFu)
    {
        long long was[3];
        object_centre(before, came_from, was);
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long turn = (there[axis] - here[axis]) - (here[axis] - was[axis]);
            // Widening to unsigned long long is exact: a squared step of the view is far below 2^63.
            bend += (unsigned long long)(turn * turn) * (unsigned long long)AXIS_WEIGHTS[axis];
        }
    }
    // Where the candidate goes on to: the same reading, one frame further along.
    unsigned int goes_to = 0xFFFFFFFFu;
    widest = 0u;
    for (unsigned int member = later->member_start[candidate]; (after != NULL) && (later->forward != NULL)
         && (member < later->member_start[candidate + 1u]); member += 1u)
    {
        const unsigned int leaf = later->members[member];
        const int onward = later->forward[leaf];
        const unsigned int voxels = later->sizes[leaf];
        goes_to = ((onward >= 0) && (voxels > widest)) ? after->object_of[(unsigned int)onward] : goes_to;
        widest = ((onward >= 0) && (voxels > widest)) ? voxels : widest;
    }
    if (goes_to != 0xFFFFFFFFu)
    {
        long long will[3];
        object_centre(after, goes_to, will);
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long turn = (will[axis] - there[axis]) - (there[axis] - here[axis]);
            bend += (unsigned long long)(turn * turn) * (unsigned long long)AXIS_WEIGHTS[axis];
        }
    }
    return bend;
}

/**
 * @brief For every pair of leaves already met, the voxels that stay still once the view moves with the candidate.
 *
 * A cell and the candidate it might be are set side by side by moving the view by the step between their
 * centres, which is the observer going along with the candidate rather than the cell being carried by a lag it
 * guessed. Under that move the same cell stands still and nearly all of it coincides; a neighbour that merely
 * lies nearby does not, however many voxels it shares at the whole view's lag. The count is what is left
 * standing still, and it is the magnitude the pool is read by.
 *
 * @param[in,out] buffers The buffers, the earlier frame grouped in slot 0 and the later's labels in slot 1 [BORROWS].
 * @param[in,out] earlier The earlier frame, whose triples take the counts [BORROWS].
 * @param[in]     later   The later frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
static int still_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later)
{
    const long long depth = (long long)buffers->depth;
    const long long height = (long long)buffers->height;
    const long long width = (long long)buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int *const labels = buffers->labels[1];
    int *const leaf_at_peak = buffers->leaf_at_peak[1];
    free(earlier->triple_still);
    earlier->triple_still = (unsigned int *)calloc((size_t)earlier->triple_count + 1u, sizeof(unsigned int));
    int ok = (earlier->triple_still != NULL) ? 1 : 0;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < later->leaf_count); leaf += 1u)
    {
        // Narrowing is safe: a leaf count is below 2^31.
        leaf_at_peak[later->peaks[leaf]] = (int)leaf;
    }
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        const unsigned long long own_voxels = (unsigned long long)earlier->sizes[leaf];
        const unsigned int first = earlier->triple_start[leaf];
        const unsigned int past = earlier->triple_start[leaf + 1u];
        for (unsigned int pair = first; pair < past; pair += 1u)
        {
            const unsigned int other = earlier->triple_after[pair];
            const unsigned long long other_voxels = (unsigned long long)later->sizes[other];
            long long step[3];
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                // Both centres at once, rounded half away from zero: a basin holds at least one voxel, so
                // neither divisor is zero, and the step is the move that sets the two side by side.
                const unsigned long long mine = earlier->sums[(3u * (size_t)leaf) + axis];
                const unsigned long long theirs = later->sums[(3u * (size_t)other) + axis];
                const long long from = (long long)(((mine * 2ull) + own_voxels) / (own_voxels * 2ull));
                const long long to = (long long)(((theirs * 2ull) + other_voxels) / (other_voxels * 2ull));
                step[axis] = to - from;
            }
            unsigned int still = 0u;
            for (unsigned int at = buffers->basin_start[0][leaf]; at < buffers->basin_start[0][leaf + 1u]; at += 1u)
            {
                const unsigned int voxel = buffers->basin_voxels[0][at];
                const unsigned int rest = voxel % plane;
                // Widening to long long keeps a move off the view representable before the bounds test.
                const long long z = (long long)(voxel / plane) + step[0];
                const long long y = (long long)(rest / buffers->width) + step[1];
                const long long x = (long long)(rest % buffers->width) + step[2];
                const int inside = (z >= 0ll) && (z < depth) && (y >= 0ll) && (y < height) && (x >= 0ll)
                                && (x < width);
                // Narrowing is safe: the index is read only where the move lands inside the view.
                const unsigned int moved = (unsigned int)(((z * height) + y) * width + x);
                const int met = (inside != 0) ? leaf_at_peak[labels[moved]] : -1;
                // Narrowing is safe: a leaf index is far below 2^31.
                still += (unsigned int)(met == (int)other);
            }
            earlier->triple_still[pair] = still;
        }
    }
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = -1;
    }
    return ok;
}

/** @brief Rounds the settling takes before it stands, however much is still moving. */
#define SETTLE_ROUNDS 64u

/**
 * @brief Settles the cells that reach for one target between them: the survivor is the one with the most to
 *        lose, and the rest take the next candidate their pool holds.
 *
 * Every cell picked its target alone, so two cells can reach for the same one and the wrong one can hold it: the
 * cell it truly belongs to may meet it in fewer voxels than a neighbour that has a target of its own to go to.
 * The delta says which is which. A cell's delta is what it meets its best in less what it meets its second in,
 * which is what it gives up by being turned away, and the cell with the largest delta survives the contest
 * while the others fall to their next candidate. Falling changes their deltas, so it runs again until a round
 * turns nobody away, and every choice inside a round is a mask.
 *
 * @param[in,out] earlier The earlier frame, linked and holding its pools [BORROWS].
 * @param[in]     later   The later frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
static int settle_links(TreeFrame *earlier, const TreeFrame *later)
{
    const unsigned int objects = earlier->object_count;
    if ((earlier->pool_start == NULL) || (earlier->link_start == NULL))
    {
        return 1;
    }
    // Per cell, the pool entry it holds now, and per pool entry, whether the cell was turned away from it.
    unsigned int *const held = (unsigned int *)malloc(((size_t)objects + 1u) * sizeof(unsigned int));
    unsigned char *const turned = (unsigned char *)calloc((size_t)earlier->pool_start[objects] + 1u, 1u);
    // Per target, the cell surviving the contest for it, and the delta that survivor carried.
    unsigned int *const survivor = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const standing = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                      * sizeof(unsigned long long));
    if ((held == NULL) || (turned == NULL) || (survivor == NULL) || (standing == NULL))
    {
        free(held);
        free(turned);
        free(survivor);
        free(standing);
        return 0;
    }
    // What each cell holds to begin with is what it linked to, found in its own pool.
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int linked = (earlier->link_start[object + 1u] > earlier->link_start[object])
                                  ? earlier->link_target[earlier->link_start[object]] : 0xFFFFFFFFu;
        held[object] = 0xFFFFFFFFu;
        for (unsigned int slot = earlier->pool_start[object]; slot < earlier->pool_start[object + 1u]; slot += 1u)
        {
            held[object] = (earlier->pool_target[slot] == linked) ? slot : held[object];
        }
    }
    unsigned int moving = 1u;
    for (unsigned int round = 0u; (round < SETTLE_ROUNDS) && (moving != 0u); round += 1u)
    {
        for (unsigned int target = 0u; target <= later->object_count; target += 1u)
        {
            survivor[target] = 0xFFFFFFFFu;
            standing[target] = 0ull;
        }
        // Each cell's delta: what it meets the one it holds in, less what it meets its best untried other in.
        for (unsigned int object = 0u; object < objects; object += 1u)
        {
            const unsigned int slot = held[object];
            if (slot == 0xFFFFFFFFu)
            {
                continue;
            }
            unsigned long long second = 0ull;
            for (unsigned int other = earlier->pool_start[object]; other < earlier->pool_start[object + 1u];
                 other += 1u)
            {
                const int open = (turned[other] == 0u) && (other != slot);
                second = ((open != 0) && ((unsigned long long)earlier->pool_weight[other] > second))
                       ? (unsigned long long)earlier->pool_weight[other] : second;
            }
            const unsigned long long mine = (unsigned long long)earlier->pool_weight[slot];
            // A cell meeting its next candidate as well as this one gives up nothing by moving on.
            const unsigned long long delta = (mine > second) ? (mine - second) : 0ull;
            const unsigned int target = earlier->pool_target[slot];
            const int ahead = (delta > standing[target])
                           || ((delta == standing[target]) && (survivor[target] == 0xFFFFFFFFu));
            standing[target] = (ahead != 0) ? delta : standing[target];
            survivor[target] = (ahead != 0) ? object : survivor[target];
        }
        moving = 0u;
        for (unsigned int object = 0u; object < objects; object += 1u)
        {
            const unsigned int slot = held[object];
            if (slot == 0xFFFFFFFFu)
            {
                continue;
            }
            const unsigned int target = earlier->pool_target[slot];
            if (survivor[target] == object)
            {
                continue;
            }
            // Turned away: the cell takes the best candidate it has not been turned away from, and where it has
            // none left it keeps the one it had, since a cell that goes nowhere is worse than a cell that shares.
            turned[slot] = 1u;
            unsigned int next = 0xFFFFFFFFu;
            unsigned long long most = 0ull;
            for (unsigned int other = earlier->pool_start[object]; other < earlier->pool_start[object + 1u];
                 other += 1u)
            {
                const int open = (turned[other] == 0u);
                const int better = (open != 0) && (((unsigned long long)earlier->pool_weight[other] > most)
                                                   || (next == 0xFFFFFFFFu));
                most = (better != 0) ? (unsigned long long)earlier->pool_weight[other] : most;
                next = (better != 0) ? other : next;
            }
            held[object] = (next != 0xFFFFFFFFu) ? next : slot;
            turned[slot] = (next != 0xFFFFFFFFu) ? 1u : 0u;
            moving += (unsigned int)(next != 0xFFFFFFFFu);
        }
    }
    // The survivors are the links now, one per cell that holds anything.
    unsigned int written = 0u;
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int slot = held[object];
        earlier->link_target[written] = (slot != 0xFFFFFFFFu) ? earlier->pool_target[slot] : 0u;
        written += (unsigned int)(slot != 0xFFFFFFFFu);
        earlier->link_start[object + 1u] = written;
    }
    free(held);
    free(turned);
    free(survivor);
    free(standing);
    return 1;
}

/**
 * @brief Links one frame's objects to the next frame's with nothing kept out of the pool: every object a source
 *        shares a voxel with, and every object its leaves land in, stands as a candidate. The one kept is the
 *        candidate leaving the shortest vector when a leaf of the source is carried by its own lag onto a leaf
 *        of the candidate, by weighted squared magnitude, with z weighed as the view weighs it. Exact ties all
 *        stay, as the reference keeps them. Every choice is a mask, never a branch.
 *
 * @param[in,out] earlier The earlier frame, with its objects, lags and overlap [BORROWS].
 * @param[in]     later   The later frame, with its objects [BORROWS].
 * @return                1 on success, 0 otherwise.
 */
static int link_objects_unbound(TreeFrame *earlier, const TreeFrame *later, const TreeFrame *before,
                                const TreeFrame *after, const TreeRules *rules)
{
    const unsigned int objects = earlier->object_count;
    const size_t room = (size_t)earlier->triple_count + (size_t)earlier->leaf_count + 1u;
    unsigned int *const pool = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const cost = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                  * sizeof(unsigned long long));
    unsigned long long *const weight = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                    * sizeof(unsigned long long));
    unsigned long long *const under = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                   * sizeof(unsigned long long));
    // A stamp per later object says which source last put it in the pool, so a candidate is added once, and a
    // place says where in the pool it went, so what is met again lands on the same candidate.
    unsigned int *const stamp = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    unsigned int *const place = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    // The voxels every object of the next frame holds, taken once, so the share rule can weigh a candidate
    // against what it and this cell hold together instead of against its size alone.
    unsigned long long *const target_voxels = (unsigned long long *)calloc((size_t)later->object_count + 1u,
                                                                           sizeof(unsigned long long));
    for (unsigned int leaf = 0u; (target_voxels != NULL) && (leaf < later->leaf_count); leaf += 1u)
    {
        target_voxels[later->object_of[leaf]] += (unsigned long long)later->sizes[leaf];
    }
    earlier->link_start = (unsigned int *)calloc((size_t)objects + 2u, sizeof(unsigned int));
    earlier->link_target = (unsigned int *)malloc(room * sizeof(unsigned int));
    if ((pool == NULL) || (cost == NULL) || (weight == NULL) || (under == NULL) || (stamp == NULL)
     || (place == NULL) || (target_voxels == NULL) || (earlier->link_start == NULL)
     || (earlier->link_target == NULL))
    {
        free(pool);
        free(cost);
        free(weight);
        free(under);
        free(stamp);
        free(place);
        free(target_voxels);
        return 0;
    }
    // The pool is at most what the room holds, since every entry is a leaf met or a leaf landed in.
    earlier->pool_start = (unsigned int *)calloc((size_t)objects + 2u, sizeof(unsigned int));
    earlier->pool_target = (unsigned int *)malloc(room * sizeof(unsigned int));
    earlier->pool_weight = (unsigned int *)malloc(room * sizeof(unsigned int));
    earlier->pool_cost = (unsigned long long *)malloc(room * sizeof(unsigned long long));
    if ((earlier->pool_start == NULL) || (earlier->pool_target == NULL) || (earlier->pool_weight == NULL)
     || (earlier->pool_cost == NULL))
    {
        free(earlier->pool_start);
        free(earlier->pool_target);
        free(earlier->pool_weight);
        free(earlier->pool_cost);
        earlier->pool_start = NULL;
        earlier->pool_target = NULL;
        earlier->pool_weight = NULL;
        earlier->pool_cost = NULL;
    }
    unsigned int written = 0u;
    unsigned int gathered = 0u;
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        unsigned int filled = 0u;
        for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u];
             member += 1u)
        {
            const unsigned int leaf = earlier->members[member];
            const unsigned int first = (earlier->triple_start != NULL) ? earlier->triple_start[leaf] : 0u;
            const unsigned int past = (earlier->triple_start != NULL) ? earlier->triple_start[leaf + 1u] : 0u;
            // Every leaf this one meets, and the leaf it landed in, is weighed where it stands: the voxels the
            // two share are added to the candidate, and the vector between them keeps the shortest it is met by.
            for (unsigned int pair = first; pair <= past; pair += 1u)
            {
                const int landing = (earlier->forward != NULL) ? earlier->forward[leaf] : -1;
                const int met = (pair < past) ? (int)earlier->triple_after[pair] : landing;
                if (met < 0)
                {
                    continue;
                }
                // Narrowing is safe: a leaf was met, so it is nonnegative.
                const unsigned int other = (unsigned int)met;
                const unsigned int target = later->object_of[other];
                const unsigned int fresh = (unsigned int)(stamp[target] != (object + 1u));
                pool[filled] = target;
                place[target] = (fresh != 0u) ? filled : place[target];
                filled += fresh;
                stamp[target] = object + 1u;
                weight[place[target]] = (fresh != 0u) ? 0ull : weight[place[target]];
                cost[place[target]] = (fresh != 0u) ? 0xFFFFFFFFFFFFFFFFull : cost[place[target]];
                // What stays still when the view moves with the candidate, where that was taken; otherwise the
                // voxels shared at the whole view's lag.
                const unsigned int *const meeting = (earlier->triple_still != NULL) ? earlier->triple_still
                                                                                    : earlier->triple_shared;
                weight[place[target]] += (pair < past) ? (unsigned long long)meeting[pair] : 0ull;
                const unsigned long long apart = leaf_disagreement(earlier, leaf, later, other);
                cost[place[target]] = (apart < cost[place[target]]) ? apart : cost[place[target]];
            }
        }
        // The truthy magnitude leads: how many of this object's voxels land on the candidate. What that leaves
        // level is broken by the swept vector, which carries the step of the sweep the candidate was met at
        // above the magnitude itself, so a cell that jumped is ordered by how far it jumped and not lost.
        // Exact ties past both stay, as the reference keeps them.
        // The share rule weighs what is shared against the two cells together, so a candidate cannot win on its
        // size alone; without it the magnitude is the shared voxels themselves. Under is never zero where
        // anything is shared, and the fractions are compared cross multiplied, never formed.
        unsigned long long source_voxels = 0ull;
        for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u];
             member += 1u)
        {
            source_voxels += (unsigned long long)earlier->sizes[earlier->members[member]];
        }
        for (unsigned int slot = 0u; (rules->share != 0) && (slot < filled); slot += 1u)
        {
            under[slot] = (source_voxels + target_voxels[pool[slot]]) - weight[slot];
        }
        unsigned int leader = 0u;
        for (unsigned int slot = 1u; slot < filled; slot += 1u)
        {
            const int ahead = (rules->share != 0)
                            ? ((weight[slot] * under[leader]) > (weight[leader] * under[slot]))
                            : (weight[slot] > weight[leader]);
            leader = (ahead != 0) ? slot : leader;
        }
        // Contested: another candidate is met in the same box of the sweep as the leader, so the pair alone
        // cannot separate them. Then the track decides, by how sharply it would bend through each, and the
        // steering is a mask throughout: nothing branches on whether a contest was found.
        // A contest is a stalemate, not merely a crowd: the candidate is met in the same box of the sweep and
        // meets the cell in at least half the voxels the leader does, one doubling, which is one step of the
        // same sweep read on what they meet in. Anything the meeting separates by more than that is separated.
        unsigned int contested = 0u;
        for (unsigned int slot = 0u; (rules->arc != 0) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const int level = ((weight[slot] * 2ull) >= weight[leader]);
            contested += (unsigned int)((same != 0) && (level != 0) && (slot != leader));
        }
        // Where a contest was found the track speaks, but a track is a bent tube and not a line of points: it
        // is as wide as the cell that walks it, so a bend inside that width is the cell jiggling and says
        // nothing. A bend is inside the tube where its cube is under the cell's voxels squared, both being a
        // length to the sixth, which compares them exactly and forms no root. The contest is then read as one
        // truthy test, in the tube or out of it, and the meeting decides among those that are in.
        unsigned int champion = leader;
        unsigned int inside = 0u;
        for (unsigned int slot = 0u; (contested != 0u) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const unsigned long long bend = (same != 0) ? track_bend(before, earlier, object, later, pool[slot], after)
                                                        : 0xFFFFFFFFFFFFFFFFull;
            // A bend past this is out of any tube the view holds, and cubing it would not fit a word.
            const unsigned int walled = (unsigned int)(bend > 0xFFFFFull);
            // Two radii wide, one doubling of the tube, because a cell may wander its own width and still be
            // the same cell walking the same tube: a squared length doubles twice for a length doubled once.
            const unsigned long long room = source_voxels * source_voxels * 64ull;
            const int held = (walled == 0u) && ((bend * bend * bend) <= room);
            const int ahead = (same != 0) && (held != 0) && (inside == 0u);
            champion = (ahead != 0) ? slot : champion;
            inside += (unsigned int)((same != 0) && (held != 0));
            // Out of the tube a candidate keeps the vector it had; in it, the bend stands, so the ones inside
            // are ordered among themselves and the ones outside fall behind them.
            cost[slot] = ((same != 0) && (held != 0))
                       ? ((cost[slot] & ~LINK_MAGNITUDE_MASK) | (bend & LINK_MAGNITUDE_MASK)) : cost[slot];
        }
        // The leader keeps the contest unless it walked out of the tube while another candidate stayed in it.
        const unsigned long long leader_bend = (contested != 0u)
                                             ? track_bend(before, earlier, object, later, pool[leader], after) : 0ull;
        const int leader_held = (leader_bend <= 0xFFFFull)
                             && ((leader_bend * leader_bend * leader_bend)
                                 <= (source_voxels * source_voxels * 64ull));
        const unsigned int winner = ((contested != 0u) && (leader_held == 0) && (inside != 0u)) ? champion : leader;
        unsigned long long best = 0xFFFFFFFFFFFFFFFFull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                               : (weight[slot] == weight[winner]));
            best = ((level != 0) && (cost[slot] < best)) ? cost[slot] : best;
        }
        // Inside one tube the bend says nothing more, and where no frame comes before or after there is no bend
        // to read at all, so what the two meet in settles the rest. Only a candidate level in all three stays.
        unsigned long long crowned = 0ull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                               : (weight[slot] == weight[winner]));
            crowned = ((level != 0) && (cost[slot] == best) && (weight[slot] > crowned)) ? weight[slot] : crowned;
        }
        unsigned int kept = 0u;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                               : (weight[slot] == weight[winner]));
            earlier->link_target[written + kept] = pool[slot];
            kept += (unsigned int)((level != 0) && (cost[slot] == best) && (weight[slot] == crowned));
        }
        earlier->link_start[object + 1u] = kept;
        written += kept;
        // The whole pool is kept, refusals and all, so what was weighed can be asked about afterwards.
        for (unsigned int slot = 0u; (earlier->pool_target != NULL) && (slot < filled); slot += 1u)
        {
            earlier->pool_target[gathered + slot] = pool[slot];
            // Narrowing is safe: a meeting is at most the voxels of the view, well below 2^32.
            earlier->pool_weight[gathered + slot] = (unsigned int)weight[slot];
            earlier->pool_cost[gathered + slot] = cost[slot];
        }
        gathered += (earlier->pool_target != NULL) ? filled : 0u;
        earlier->pool_start[object + 1u] = gathered;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        earlier->link_start[object + 1u] += earlier->link_start[object];
    }
    const int settled = (rules->settle != 0) ? settle_links(earlier, later) : 1;
    free(pool);
    free(cost);
    free(weight);
    free(under);
    free(stamp);
    free(place);
    free(target_voxels);
    return settled;
}

/**
 * @brief Links one frame's objects to the next frame's: landing both ways, merge-target, forward-only
 *        and the pick where set.
 *
 * @param[in,out] earlier The earlier frame, with forward and the overlap [BORROWS].
 * @param[in]     later   The later frame, with backward [BORROWS].
 * @param[in]     rules   The tree's rules [BORROWS].
 * @return                1 on success, 0 otherwise.
 */
static int link_objects(TreeFrame *earlier, const TreeFrame *later, const TreeRules *rules)
{
    unsigned long long *const candidate = (unsigned long long *)malloc(((size_t)earlier->leaf_count + 1u)
                                                                       * sizeof(unsigned long long));
    unsigned long long *const confirmed = (unsigned long long *)malloc(((size_t)later->leaf_count + 1u)
                                                                       * sizeof(unsigned long long));
    unsigned int *const incoming = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    earlier->link_start = (unsigned int *)calloc((size_t)earlier->object_count + 2u, sizeof(unsigned int));
    earlier->link_target = (unsigned int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned int));
    unsigned int *const mutual = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const weight = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                    * sizeof(unsigned long long));
    // The two cells together less what they share, which is what the share rule weighs a branch against.
    unsigned long long *const under = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                   * sizeof(unsigned long long));
    if ((candidate == NULL) || (confirmed == NULL) || (incoming == NULL) || (earlier->link_start == NULL)
     || (earlier->link_target == NULL) || (mutual == NULL) || (weight == NULL) || (under == NULL))
    {
        free(candidate);
        free(confirmed);
        free(incoming);
        free(mutual);
        free(weight);
        free(under);
        return 0;
    }
    unsigned int candidates = 0u;
    for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
    {
        if (earlier->forward[leaf] >= 0)
        {
            // Narrowing is safe: the landing was found, so it is nonnegative.
            candidate[candidates] = ((unsigned long long)earlier->object_of[leaf] << 32u)
                                  | later->object_of[(unsigned int)earlier->forward[leaf]];
            candidates += 1u;
        }
    }
    candidates = sort_unique(candidate, candidates);
    unsigned int confirmations = 0u;
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        if (later->backward[leaf] >= 0)
        {
            // Narrowing is safe: the landing was found, so it is nonnegative.
            confirmed[confirmations] = ((unsigned long long)later->object_of[leaf] << 32u)
                                     | earlier->object_of[(unsigned int)later->backward[leaf]];
            confirmations += 1u;
        }
    }
    confirmations = sort_unique(confirmed, confirmations);
    for (unsigned int position = 0u; position < candidates; position += 1u)
    {
        incoming[(unsigned int)(candidate[position] & 0xFFFFFFFFULL)] += 1u;
    }

    unsigned int written = 0u;
    unsigned int position = 0u;
    while (position < candidates)
    {
        const unsigned int source = (unsigned int)(candidate[position] >> 32u);
        unsigned int end = position;
        while ((end < candidates) && ((unsigned int)(candidate[end] >> 32u) == source))
        {
            end += 1u;
        }
        unsigned int mutual_count = 0u;
        for (unsigned int slot = position; slot < end; slot += 1u)
        {
            const unsigned int target = (unsigned int)(candidate[slot] & 0xFFFFFFFFULL);
            int keep = (rules->forward_only != 0);
            if (keep == 0)
            {
                const unsigned long long sought = ((unsigned long long)target << 32u) | source;
                const void *const found = bsearch(&sought, confirmed, confirmations, sizeof(unsigned long long),
                                                  order_keys);
                keep = (found != NULL);
                if ((keep == 0) && (rules->merge_target != 0))
                {
                    keep = (incoming[target] >= 2u);
                }
            }
            if (keep != 0)
            {
                mutual[mutual_count] = target;
                mutual_count += 1u;
            }
        }
        if ((rules->pick != 0) && (mutual_count >= 2u))
        {
            for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
            {
                weight[slot] = 0ULL;
            }
            unsigned long long source_voxels = 0ULL;
            for (unsigned int member = earlier->member_start[source]; member < earlier->member_start[source + 1u];
                 member += 1u)
            {
                source_voxels += (unsigned long long)earlier->sizes[earlier->members[member]];
            }
            for (unsigned int member = earlier->member_start[source]; member < earlier->member_start[source + 1u];
                 member += 1u)
            {
                const unsigned int leaf = earlier->members[member];
                for (unsigned int pair = earlier->triple_start[leaf]; pair < earlier->triple_start[leaf + 1u];
                     pair += 1u)
                {
                    const unsigned int after_object = later->object_of[earlier->triple_after[pair]];
                    for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
                    {
                        if (mutual[slot] == after_object)
                        {
                            weight[slot] += earlier->triple_shared[pair];
                            break;
                        }
                    }
                }
            }
            // The share rule weighs each branch by what it shares of the two cells together, so a large
            // neighbour cannot win on its size alone. Over is what the branch shares; under is the two cells
            // less what they share, which is never zero where anything is shared at all.
            for (unsigned int slot = 0u; (rules->share != 0) && (slot < mutual_count); slot += 1u)
            {
                unsigned long long target_voxels = 0ULL;
                for (unsigned int member = later->member_start[mutual[slot]];
                     member < later->member_start[mutual[slot] + 1u]; member += 1u)
                {
                    target_voxels += (unsigned long long)later->sizes[later->members[member]];
                }
                under[slot] = (source_voxels + target_voxels) - weight[slot];
            }
            unsigned int leader = 0u;
            for (unsigned int slot = 1u; slot < mutual_count; slot += 1u)
            {
                // Cross multiplied, so the two fractions are compared exactly and neither is ever formed.
                const int ahead = (rules->share != 0)
                                ? ((weight[slot] * under[leader]) > (weight[leader] * under[slot]))
                                : (weight[slot] > weight[leader]);
                leader = (ahead != 0) ? slot : leader;
            }
            if (weight[leader] > 0ULL)
            {
                unsigned int narrowed = 0u;
                for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
                {
                    const int level = (rules->share != 0)
                                    ? ((weight[slot] * under[leader]) == (weight[leader] * under[slot]))
                                    : (weight[slot] == weight[leader]);
                    mutual[narrowed] = mutual[slot];
                    narrowed += (unsigned int)(level != 0);
                }
                mutual_count = narrowed;
            }
        }
        for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
        {
            earlier->link_target[written] = mutual[slot];
            written += 1u;
        }
        earlier->link_start[source + 1u] = mutual_count;
        position = end;
    }
    for (unsigned int object = 0u; object < earlier->object_count; object += 1u)
    {
        earlier->link_start[object + 1u] += earlier->link_start[object];
    }
    free(candidate);
    free(confirmed);
    free(incoming);
    free(mutual);
    free(weight);
    free(under);
    return 1;
}

/** @brief The whole tree as nodes: one node per object of every frame. */
typedef struct
{
    unsigned int frame_count;         /**< Frames of the tree. */
    TreeFrame *frames;                /**< The frames [BORROWS]. */
    unsigned int node_count;          /**< Objects over all frames. */
    unsigned int *node_offset;        /**< Frame count + 1 offsets [OWNS]. */
    unsigned int *node_frame;         /**< Frame of every node [OWNS]. */
} NodeIndex;

/**
 * @brief The links of a node, as a range of next-frame object numbers.
 *
 * @param[in]  index The node index [BORROWS].
 * @param[in]  node  The node.
 * @param[out] first The first link target [BORROWS].
 * @param[out] count How many links [BORROWS].
 */
static void links_of_node(const NodeIndex *index, unsigned int node, const unsigned int **first, unsigned int *count)
{
    const unsigned int frame = index->node_frame[node];
    const TreeFrame *const tree = &index->frames[frame];
    if (tree->link_start == NULL)
    {
        *first = NULL;
        *count = 0u;
        return;
    }
    const unsigned int object = node - index->node_offset[frame];
    *first = &tree->link_target[tree->link_start[object]];
    *count = tree->link_start[object + 1u] - tree->link_start[object];
}

/** @brief The status of each scored edge, in the order the tallies name them. */
static const char *const EDGE_STATUS_NAMES[5] = {"correct", "branched", "wrong", "nolink", "missed"};

/** @brief What the coherence reading needs from one scored sample. */
typedef struct
{
    const char *sample;                   /**< Sample name. */
    const char *stack_path;               /**< The stack file. */
    const AnswerKey *key;                 /**< The answer key [BORROWS]. */
    const TreeFrame *frames;              /**< The tree's frames [BORROWS]. */
    unsigned int frame_count;             /**< Frames of the tree. */
    const unsigned int *node_offset;      /**< Frame count + 1 offsets [BORROWS]. */
    const unsigned int *unified_of;       /**< Unified object per node [BORROWS]. */
    unsigned int unified_count;           /**< Unified objects over all frames. */
    const int *node_leaf;                 /**< Leaf per answer key node, or -1 [BORROWS]. */
    const int *tree_index_of_time;        /**< Tree frame per stack frame, or -1 [BORROWS]. */
    unsigned int stack_frames;            /**< Frames in the stack. */
    const signed char *edge_status;       /**< Per edge an index into EDGE_STATUS_NAMES, or -1 [BORROWS]. */
    const unsigned int *unified_start;    /**< Unified count + 1 offsets into unified_link [BORROWS]. */
    const unsigned long long *unified_link; /**< Source and child unified ids packed high and low [BORROWS]. */
    const char *vis_directory;            /**< Where the vis arm writes pictures, or NULL [BORROWS]. */
    FILE *vis_index;                      /**< The vis arm's page, appended to, or NULL [BORROWS]. */
    const unsigned int *unified_first;    /**< Frame count + 1: the first unified id of each frame [BORROWS]. */
} CoherenceInputs;

/**
 * @brief The frame a unified id belongs to, by binary search over each frame's first id.
 *
 * @param[in] inputs  The scored sample [BORROWS].
 * @param[in] unified The unified id.
 * @return            The tree frame.
 */
static unsigned int frame_of_unified(const CoherenceInputs *inputs, unsigned int unified)
{
    unsigned int low = 0u;
    unsigned int high = inputs->frame_count;
    while (low + 1u < high)
    {
        const unsigned int middle = low + (high - low) / 2u;
        if (inputs->unified_first[middle] <= unified)
        {
            low = middle;
        }
        else
        {
            high = middle;
        }
    }
    return low;
}

/**
 * @brief Writes the tree the engine grew for one sample as one vectored file of exact integers, laid out so a
 *        renderer reads each section as a typed array with no parsing: every cell of every frame with its positive
 *        voxel count, index sums, second moments, basins and membrane faces; every link; every contact between
 *        cells with the faces they share; the answer key's nodes placed in their cells; and every scored edge with
 *        its status, the lag its source peak was carried by, and the peak.
 *
 * Layout, little endian, all offsets implied by the counts:
 *     uint32 header[12]   magic 0x31525443 "CTR1", version 1, frames, depth, height, width, cells, links, contacts,
 *                         nodes, edges, 0
 *     uint32 frame[12]    per frame: t, follows (0 or 1), lag z, lag y, lag x (two's complement), first cell, cells,
 *                         first link, links, first contact, contacts, 0
 *     uint64 cell[12]     per cell: n, sum z, sum y, sum x, sum zz, sum yy, sum xx, sum zy, sum zx, sum yx, basins,
 *                         membrane faces
 *     uint32 link[3]      per link: frame, source cell within its frame, child cell within the next
 *     uint32 contact[3]   per contact: cell, cell, shared faces, both within the contact's frame, lower first
 *     int32  node[7]      per node: id low, id high, t, z, y, x, cell within its frame or -1
 *     int32  edge[9]      per scored edge: source node, target node, status, carried lag z y x, peak z y x
 *
 * @param[in] buffers   The engine buffers, for the extents [BORROWS].
 * @param[in] inputs    The scored sample [BORROWS].
 * @param[in] directory Where <sample>.room goes.
 * @return              1 on success, 0 otherwise.
 */
static int export_room(const EngineBuffers *buffers, const CoherenceInputs *inputs, const char *directory)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.room", directory, inputs->sample);
    const size_t unified = inputs->unified_first[inputs->frame_count];
    const unsigned int link_total = inputs->unified_start[unified];
    unsigned long long *const cells = (unsigned long long *)calloc((unified + 1u) * 12u, sizeof(unsigned long long));
    unsigned int *const frame_table = (unsigned int *)calloc(((size_t)inputs->frame_count + 1u) * 12u, sizeof(unsigned int));
    unsigned int *const links = (unsigned int *)malloc(((size_t)link_total + 1u) * 3u * sizeof(unsigned int));
    size_t contact_room = 1u << 16u;
    size_t contact_total = 0u;
    unsigned int *contacts = (unsigned int *)malloc(contact_room * 3u * sizeof(unsigned int));
    int good = (cells != NULL) && (frame_table != NULL) && (links != NULL) && (contacts != NULL);

    for (unsigned int frame = 0u; (good != 0) && (frame < inputs->frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &inputs->frames[frame];
        for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
        {
            const unsigned int object = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[leaf]];
            unsigned long long *const cell = &cells[(size_t)object * 12u];
            cell[0] += tree->sizes[leaf];
            cell[1] += tree->sums[(size_t)leaf * 3u];
            cell[2] += tree->sums[(size_t)leaf * 3u + 1u];
            cell[3] += tree->sums[(size_t)leaf * 3u + 2u];
            for (unsigned int moment = 0u; (tree->moments != NULL) && (moment < 6u); moment += 1u)
            {
                cell[4u + moment] += tree->moments[(size_t)leaf * 6u + moment];
            }
            cell[10] += 1u;
            cell[11] += (tree->exposed != NULL) ? tree->exposed[leaf] : 0u;
        }
        // Contacts between cells: faces two different cells share, summed over the basin pairs that carry them.
        // A face between two cells is membrane on both, so it adds to both membranes.
        unsigned long long *const keys = (unsigned long long *)malloc(((size_t)tree->joined_count + 1u) * sizeof(unsigned long long));
        good = (keys != NULL);
        unsigned int key_count = 0u;
        for (unsigned int pair = 0u; (good != 0) && (tree->contact_faces != NULL) && (pair < tree->joined_count); pair += 1u)
        {
            const unsigned int first = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[tree->joined[2u * pair]]];
            const unsigned int second = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[tree->joined[2u * pair + 1u]]];
            if ((first == second) || (tree->contact_faces[pair] == 0u))
            {
                continue;
            }
            cells[(size_t)first * 12u + 11u] += tree->contact_faces[pair];
            cells[(size_t)second * 12u + 11u] += tree->contact_faces[pair];
            const unsigned int low = ((first < second) ? first : second) - inputs->unified_first[frame];
            const unsigned int high = ((first < second) ? second : first) - inputs->unified_first[frame];
            // Twenty two bits for each cell and twenty for faces fit one key; a view here holds far fewer of each.
            keys[key_count] = ((unsigned long long)low << 42u) | ((unsigned long long)high << 20u) | tree->contact_faces[pair];
            key_count += 1u;
        }
        good = (good != 0) && radix_sort_keys(keys, key_count);
        frame_table[(size_t)frame * 12u] = tree->time;
        frame_table[(size_t)frame * 12u + 1u] = (tree->forward != NULL) ? 1u : 0u;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            // The lag's two's complement bits are kept whole in an unsigned slot.
            frame_table[(size_t)frame * 12u + 2u + axis] = (unsigned int)tree->lag_to_next[axis];
        }
        frame_table[(size_t)frame * 12u + 5u] = inputs->unified_first[frame];
        frame_table[(size_t)frame * 12u + 6u] = inputs->unified_first[frame + 1u] - inputs->unified_first[frame];
        // Narrowing is safe: contact totals are far below 2^32.
        frame_table[(size_t)frame * 12u + 9u] = (unsigned int)contact_total;
        for (unsigned int at = 0u; (good != 0) && (at < key_count);)
        {
            const unsigned long long pair = keys[at] >> 20u;
            unsigned long long faces = 0ULL;
            while ((at < key_count) && ((keys[at] >> 20u) == pair))
            {
                faces += keys[at] & 0xFFFFFULL;
                at += 1u;
            }
            if (contact_total == contact_room)
            {
                contact_room *= 2u;
                unsigned int *const grown = (unsigned int *)realloc(contacts, contact_room * 3u * sizeof(unsigned int));
                if (grown == NULL)
                {
                    good = 0;
                    break;
                }
                contacts = grown;
            }
            // Narrowing is safe: each part was packed from an unsigned int.
            contacts[contact_total * 3u] = (unsigned int)(pair >> 22u);
            contacts[contact_total * 3u + 1u] = (unsigned int)(pair & 0x3FFFFFULL);
            contacts[contact_total * 3u + 2u] = (unsigned int)faces;
            contact_total += 1u;
        }
        // Narrowing is safe: contact totals are far below 2^32.
        frame_table[(size_t)frame * 12u + 10u] = (unsigned int)contact_total - frame_table[(size_t)frame * 12u + 9u];
        free(keys);
    }
    // Links, ascending by source cell, so each frame's links are one run.
    for (unsigned int link = 0u; (good != 0) && (link < link_total); link += 1u)
    {
        const unsigned int source = (unsigned int)(inputs->unified_link[link] >> 32u);
        const unsigned int child = (unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL);
        const unsigned int frame = frame_of_unified(inputs, source);
        links[3u * link] = frame;
        links[3u * link + 1u] = source - inputs->unified_first[frame];
        links[3u * link + 2u] = child - inputs->unified_first[frame + 1u];
        if (frame_table[(size_t)frame * 12u + 8u] == 0u)
        {
            frame_table[(size_t)frame * 12u + 7u] = link;
        }
        frame_table[(size_t)frame * 12u + 8u] += 1u;
    }

    unsigned int edge_total = 0u;
    for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
    {
        edge_total += (inputs->edge_status[edge] >= 0) ? 1u : 0u;
    }
    FILE *const out = (good != 0) ? fopen(path, "wb") : NULL;
    good = (out != NULL);
    if (good != 0)
    {
        // Narrowing is safe: every count is far below 2^32.
        const unsigned int header[12] = {0x31525443u, 1u, inputs->frame_count, buffers->depth, buffers->height,
                                         buffers->width, (unsigned int)unified, link_total, (unsigned int)contact_total,
                                         inputs->key->node_count, edge_total, 0u};
        fwrite(header, sizeof(unsigned int), 12u, out);
        fwrite(frame_table, sizeof(unsigned int), (size_t)inputs->frame_count * 12u, out);
        fwrite(cells, sizeof(unsigned long long), unified * 12u, out);
        fwrite(links, sizeof(unsigned int), (size_t)link_total * 3u, out);
        fwrite(contacts, sizeof(unsigned int), contact_total * 3u, out);
        for (unsigned int node = 0u; node < inputs->key->node_count; node += 1u)
        {
            const int *const place = &inputs->key->node_coordinates[(size_t)node * 4u];
            int record[7] = {(int)(inputs->key->node_identity[node] & 0xFFFFFFFFLL), (int)(inputs->key->node_identity[node] >> 32),
                             place[0], place[1], place[2], place[3], -1};
            // Narrowing is safe: the time was tested nonnegative first.
            if ((place[0] >= 0) && ((unsigned int)place[0] < inputs->stack_frames) && (inputs->node_leaf[node] >= 0))
            {
                const int frame = inputs->tree_index_of_time[place[0]];
                if (frame >= 0)
                {
                    // Narrowing is safe: the frame and the leaf were both found, and a cell index is below 2^31.
                    const unsigned int id = inputs->unified_of[inputs->node_offset[(unsigned int)frame]
                                                               + inputs->frames[frame].object_of[(unsigned int)inputs->node_leaf[node]]];
                    record[6] = (int)(id - inputs->unified_first[frame]);
                }
            }
            fwrite(record, sizeof(int), 7u, out);
        }
        for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
        {
            const int status = inputs->edge_status[edge];
            if (status < 0)
            {
                continue;
            }
            // Narrowing is safe: node slots are below 2^31.
            int record[9] = {(int)node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge]),
                             (int)node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge + 1u]), status, 0, 0, 0, -1, -1, -1};
            if (status != 4)
            {
                const int time = inputs->key->node_coordinates[(size_t)record[0] * 4u];
                const int frame = inputs->tree_index_of_time[time];
                // Narrowing is safe: a scored edge that is not missed has its source frame and leaf.
                const TreeFrame *const tree = &inputs->frames[frame];
                const unsigned int leaf = (unsigned int)inputs->node_leaf[record[0]];
                const int *const carried = (tree->forward_lag != NULL) ? &tree->forward_lag[3u * leaf] : tree->lag_to_next;
                const unsigned int plane = buffers->height * buffers->width;
                record[3] = carried[0];
                record[4] = carried[1];
                record[5] = carried[2];
                // Narrowing is safe: a peak index of the view fits an int.
                record[6] = (int)(tree->peaks[leaf] / plane);
                record[7] = (int)((tree->peaks[leaf] % plane) / buffers->width);
                record[8] = (int)((tree->peaks[leaf] % plane) % buffers->width);
            }
            fwrite(record, sizeof(int), 9u, out);
        }
        good = (ferror(out) == 0);
        fclose(out);
    }
    free(cells);
    free(frame_table);
    free(links);
    free(contacts);
    return good;
}

/**
 * @brief The global cell an answer key node lies in, or all ones where it lies in none.
 *
 * @param[in] inputs The scored sample [BORROWS].
 * @param[in] node   The node's slot.
 * @return           The cell.
 */
static unsigned int object_cell_of_node(const CoherenceInputs *inputs, long node)
{
    const int time = (node >= 0L) ? inputs->key->node_coordinates[(size_t)node * 4u] : -1;
    // Narrowing is safe: the time is tested nonnegative before it is compared unsigned.
    const bool timed = (time >= 0) && ((unsigned int)time < inputs->stack_frames);
    const int frame = timed ? inputs->tree_index_of_time[time] : -1;
    const bool placed = (frame >= 0) && (inputs->node_leaf[node] >= 0);
    // Narrowing is safe: the frame and the leaf were both found.
    return placed ? inputs->unified_of[inputs->node_offset[(unsigned int)frame]
                                       + inputs->frames[frame].object_of[(unsigned int)inputs->node_leaf[node]]]
                  : 0xFFFFFFFFu;
}

/**
 * @brief Writes one sample as the object the card is fed. The page streams the file into one storage buffer and
 *        draws every section by its offset; the host builds no geometry and the card warps each run out itself.
 *
 * Layout, little endian, all uint32, every section's offset implied by the counts before it:
 *     header[16]  magic 0x314A424F "OBJ1", version 1, frames, depth, height, width, leaves, runs, cells, links,
 *                 edges, then the control: aberrant leaves, aberrant voxels, wide sums; then the .cfg's bytes, 0
 *     frame[10]   per frame: t, first leaf, leaves, first run, runs, first cell, cells, first link, links, 0
 *     leaf[4]     per leaf: its cell, its frame, its first run, its runs
 *     cell[4]     per cell: positive voxels, sum z, sum y, sum x, exact
 *     run[1]      per run: its first voxel's raster index << 8 | (length - 1); a leaf's runs are one range, in raster
 *                 order
 *     link[2]     per link: source cell, child cell, ascending by source
 *     edge[3]     per scored edge: the source node's cell, the target node's cell, the status, a cell being all ones
 *                 where the node lies in none
 *     cfg         the .cfg the run took, UTF-8, padded with zero bytes to a whole word: the object says how it was
 *                 made, and its view section is the state the page opens in
 *
 * The control rides in the header: leaves whose run lengths do not sum to their positive voxels, and by how many voxels
 * in all, which also shows whether two runs were ever cut into one slot; and cell sums past 32 bits. Nothing is refused;
 * the aberrance is there to be seen.
 *
 * @param[in] buffers   The engine buffers, for the extents [BORROWS].
 * @param[in] inputs    The scored sample [BORROWS].
 * @param[in] runs      One per run, every frame's runs in frame order [BORROWS].
 * @param[in] first_run Frame count + 1: the runs before each frame [BORROWS].
 * @param[in] leaf_runs Two per leaf of every frame in frame order: its first run and its runs [BORROWS].
 * @param[in] rules     The rules, for where the object goes and the .cfg it carries [BORROWS].
 * @return              1 on success, 0 otherwise.
 */
static int export_object(const EngineBuffers *buffers, const CoherenceInputs *inputs, const unsigned int *runs,
                         const unsigned int *first_run, const unsigned int *leaf_runs, const TreeRules *rules)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.object", rules->object_directory, inputs->sample);
    const unsigned int frame_count = inputs->frame_count;
    const unsigned int cell_count = inputs->unified_first[frame_count];
    const unsigned int link_count = inputs->unified_start[cell_count];
    const unsigned int run_count = first_run[frame_count];
    unsigned int leaf_count = 0u;
    unsigned int edge_count = 0u;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        leaf_count += inputs->frames[frame].leaf_count;
    }
    for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
    {
        edge_count += (unsigned int)(inputs->edge_status[edge] >= 0);
    }
    unsigned int *const frame_table = (unsigned int *)calloc(((size_t)frame_count + 1u) * 10u, sizeof(unsigned int));
    unsigned int *const leaves = (unsigned int *)malloc(((size_t)leaf_count + 1u) * 4u * sizeof(unsigned int));
    unsigned long long *const sums = (unsigned long long *)calloc(((size_t)cell_count + 1u) * 4u, sizeof(unsigned long long));
    unsigned int *const cells = (unsigned int *)malloc(((size_t)cell_count + 1u) * 4u * sizeof(unsigned int));
    unsigned int *const links = (unsigned int *)malloc(((size_t)link_count + 1u) * 2u * sizeof(unsigned int));
    unsigned int *const edges = (unsigned int *)malloc(((size_t)edge_count + 1u) * 3u * sizeof(unsigned int));
    int good = frame_table && leaves && sums && cells && links && edges;

    unsigned int leaf_base = 0u;
    unsigned int aberrant_leaves = 0u;
    unsigned int aberrant_voxels = 0u;
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &inputs->frames[frame];
        unsigned int *const row = &frame_table[(size_t)frame * 10u];
        row[0] = tree->time;
        row[1] = leaf_base;
        row[2] = tree->leaf_count;
        row[3] = first_run[frame];
        row[4] = first_run[frame + 1u] - first_run[frame];
        row[5] = inputs->unified_first[frame];
        row[6] = inputs->unified_first[frame + 1u] - inputs->unified_first[frame];
        row[7] = inputs->unified_start[inputs->unified_first[frame]];
        row[8] = inputs->unified_start[inputs->unified_first[frame + 1u]] - row[7];
        for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
        {
            const unsigned int cell = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[leaf]];
            const unsigned int *const range = &leaf_runs[2u * ((size_t)leaf_base + leaf)];
            unsigned int *const record = &leaves[4u * ((size_t)leaf_base + leaf)];
            record[0] = cell;
            record[1] = frame;
            record[2] = range[0];
            record[3] = range[1];
            unsigned int length = 0u;
            for (unsigned int run = range[0]; run < range[0] + range[1]; run += 1u)
            {
                length += (runs[run] & 0xFFu) + 1u;
            }
            // The control: a leaf's run lengths against its positive voxels, the gap accumulated either way round.
            const unsigned int over = (unsigned int)(length > tree->sizes[leaf]);
            aberrant_leaves += (unsigned int)(length != tree->sizes[leaf]);
            aberrant_voxels += (over * (length - tree->sizes[leaf])) + ((1u - over) * (tree->sizes[leaf] - length));
            sums[4u * (size_t)cell] += tree->sizes[leaf];
            sums[(4u * (size_t)cell) + 1u] += tree->sums[3u * (size_t)leaf];
            sums[(4u * (size_t)cell) + 2u] += tree->sums[(3u * (size_t)leaf) + 1u];
            sums[(4u * (size_t)cell) + 3u] += tree->sums[(3u * (size_t)leaf) + 2u];
        }
        leaf_base += tree->leaf_count;
    }
    // A cell's sums are kept in 32 bits; a sum that does not fit is counted in the control, not refused.
    unsigned int wide_sums = 0u;
    for (size_t slot = 0u; good && (slot < (size_t)cell_count * 4u); slot += 1u)
    {
        wide_sums += (unsigned int)!!(sums[slot] >> 32u);
        // Narrowing is counted: the high bits of a sum that does not fit are the control's wide sums.
        cells[slot] = (unsigned int)sums[slot];
    }
    fprintf(stderr, "  object %s: %u aberrant leaves, %u aberrant voxels, %u wide sums\n", inputs->sample, aberrant_leaves,
            aberrant_voxels, wide_sums);
    for (unsigned int link = 0u; good && (link < link_count); link += 1u)
    {
        // Narrowing is safe: each half was packed from an unsigned int.
        links[2u * link] = (unsigned int)(inputs->unified_link[link] >> 32u);
        links[(2u * link) + 1u] = (unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL);
    }
    unsigned int scored = 0u;
    for (unsigned int edge = 0u; good && (edge < inputs->key->edge_count); edge += 1u)
    {
        const long source = node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge]);
        const long target = node_slot_of(inputs->key, inputs->key->edge_ends[(2u * edge) + 1u]);
        // The record is written to the next free slot every edge and kept only where the edge was scored.
        edges[3u * scored] = object_cell_of_node(inputs, source);
        edges[(3u * scored) + 1u] = object_cell_of_node(inputs, target);
        // Narrowing is safe: a status is a small index, and one not scored is overwritten by the next edge.
        edges[(3u * scored) + 2u] = (unsigned int)inputs->edge_status[edge];
        scored += (unsigned int)(inputs->edge_status[edge] >= 0);
    }

    FILE *const out = good ? fopen(path, "wb") : NULL;
    good = good && out;
    if (good)
    {
        // Narrowing is safe: a .cfg is far below 2^32 bytes.
        const unsigned int cfg_bytes = (unsigned int)rules->cfg_length;
        const unsigned char padding[4] = {0u, 0u, 0u, 0u};
        const unsigned int header[16] = {0x314A424Fu, 1u, frame_count, buffers->depth, buffers->height, buffers->width,
                                         leaf_count, run_count, cell_count, link_count, edge_count, aberrant_leaves,
                                         aberrant_voxels, wide_sums, cfg_bytes, 0u};
        good = (fwrite(header, sizeof(unsigned int), 16u, out) == 16u)
            && (fwrite(frame_table, sizeof(unsigned int), (size_t)frame_count * 10u, out) == (size_t)frame_count * 10u)
            && (fwrite(leaves, sizeof(unsigned int), (size_t)leaf_count * 4u, out) == (size_t)leaf_count * 4u)
            && (fwrite(cells, sizeof(unsigned int), (size_t)cell_count * 4u, out) == (size_t)cell_count * 4u)
            && (fwrite(runs, sizeof(unsigned int), run_count, out) == run_count)
            && (fwrite(links, sizeof(unsigned int), (size_t)link_count * 2u, out) == (size_t)link_count * 2u)
            && (fwrite(edges, sizeof(unsigned int), (size_t)edge_count * 3u, out) == (size_t)edge_count * 3u)
            && (fwrite(rules->cfg_text, 1u, cfg_bytes, out) == cfg_bytes)
            && (fwrite(padding, 1u, (4u - (cfg_bytes & 3u)) & 3u, out) == ((4u - (cfg_bytes & 3u)) & 3u));
        good = (fclose(out) == 0) && good;
    }
    free(frame_table);
    free(leaves);
    free(sums);
    free(cells);
    free(links);
    free(edges);
    return good;
}

/** @brief Voxels shown across a vis panel, centred on the answer key's source node. */
#define VIS_CROP 64u

/** @brief Pixels per voxel in a vis panel. */
#define VIS_SCALE 6u

/** @brief Pixels between the two vis panels. */
#define VIS_GAP 8u

/** @brief An object id the vis arm reads as no object. */
#define VIS_NO_OBJECT 0xFFFFFFFFu

/**
 * @brief The PNG CRC-32 of bytes, continuing a running value.
 *
 * @param[in] bytes The bytes [BORROWS].
 * @param[in] count How many.
 * @param[in] crc   The running value, 0xFFFFFFFF to start.
 * @return          The running value after the bytes.
 */
static unsigned int png_crc(const unsigned char *bytes, size_t count, unsigned int crc)
{
    for (size_t at = 0u; at < count; at += 1u)
    {
        crc ^= bytes[at];
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            crc = ((crc & 1u) != 0u) ? ((crc >> 1u) ^ 0xEDB88320u) : (crc >> 1u);
        }
    }
    return crc;
}

/**
 * @brief Writes one PNG chunk.
 *
 * @param[in] handle The file [BORROWS].
 * @param[in] type   Four chunk type bytes [BORROWS].
 * @param[in] data   The chunk data [BORROWS].
 * @param[in] length Data bytes.
 */
static void png_chunk(FILE *handle, const char *type, const unsigned char *data, size_t length)
{
    const unsigned char size[4] = {(unsigned char)(length >> 24u), (unsigned char)(length >> 16u),
                                   (unsigned char)(length >> 8u), (unsigned char)length};
    fwrite(size, 1u, 4u, handle);
    fwrite(type, 1u, 4u, handle);
    if (length > 0u)
    {
        fwrite(data, 1u, length, handle);
    }
    unsigned int crc = png_crc((const unsigned char *)type, 4u, 0xFFFFFFFFu);
    crc = png_crc(data, length, crc) ^ 0xFFFFFFFFu;
    const unsigned char tail[4] = {(unsigned char)(crc >> 24u), (unsigned char)(crc >> 16u), (unsigned char)(crc >> 8u),
                                   (unsigned char)crc};
    fwrite(tail, 1u, 4u, handle);
}

/**
 * @brief Writes an RGB picture as a PNG whose deflate stream is stored blocks, needing no compressor.
 *
 * @param[in] path   Output file.
 * @param[in] rgb    Three bytes per pixel, rows top to bottom [BORROWS].
 * @param[in] width  Pixels across.
 * @param[in] height Pixels down.
 * @return           1 on success, 0 otherwise.
 */
static int write_png_rgb(const char *path, const unsigned char *rgb, unsigned int width, unsigned int height)
{
    const size_t row = 1u + (size_t)width * 3u;
    const size_t raw = row * height;
    const size_t blocks = (raw + 65534u) / 65535u;
    const size_t stream_bytes = 2u + blocks * 5u + raw + 4u;
    unsigned char *const stream = (unsigned char *)malloc(stream_bytes);
    FILE *const handle = fopen(path, "wb");
    if ((stream == NULL) || (handle == NULL))
    {
        free(stream);
        if (handle != NULL)
        {
            fclose(handle);
        }
        return 0;
    }
    size_t at = 0u;
    stream[at] = 0x78u;
    stream[at + 1u] = 0x01u;
    at += 2u;
    unsigned int adler_low = 1u;
    unsigned int adler_high = 0u;
    size_t emitted = 0u;
    size_t block_left = 0u;
    for (unsigned int line = 0u; line < height; line += 1u)
    {
        for (size_t column = 0u; column < row; column += 1u)
        {
            if (block_left == 0u)
            {
                const size_t length = ((raw - emitted) > 65535u) ? 65535u : (raw - emitted);
                stream[at] = ((raw - emitted) <= 65535u) ? 1u : 0u;
                stream[at + 1u] = (unsigned char)(length & 0xFFu);
                stream[at + 2u] = (unsigned char)(length >> 8u);
                stream[at + 3u] = (unsigned char)(~length & 0xFFu);
                stream[at + 4u] = (unsigned char)((~length >> 8u) & 0xFFu);
                at += 5u;
                block_left = length;
            }
            const unsigned char value = (column == 0u) ? 0u : rgb[(size_t)line * width * 3u + (column - 1u)];
            stream[at] = value;
            at += 1u;
            adler_low = (adler_low + value) % 65521u;
            adler_high = (adler_high + adler_low) % 65521u;
            emitted += 1u;
            block_left -= 1u;
        }
    }
    const unsigned int adler = (adler_high << 16u) | adler_low;
    stream[at] = (unsigned char)(adler >> 24u);
    stream[at + 1u] = (unsigned char)(adler >> 16u);
    stream[at + 2u] = (unsigned char)(adler >> 8u);
    stream[at + 3u] = (unsigned char)adler;
    at += 4u;
    static const unsigned char signature[8] = {137u, 80u, 78u, 71u, 13u, 10u, 26u, 10u};
    fwrite(signature, 1u, 8u, handle);
    const unsigned char header[13] = {(unsigned char)(width >> 24u), (unsigned char)(width >> 16u),
                                      (unsigned char)(width >> 8u), (unsigned char)width,
                                      (unsigned char)(height >> 24u), (unsigned char)(height >> 16u),
                                      (unsigned char)(height >> 8u), (unsigned char)height, 8u, 2u, 0u, 0u, 0u};
    png_chunk(handle, "IHDR", header, 13u);
    png_chunk(handle, "IDAT", stream, at);
    png_chunk(handle, "IEND", NULL, 0u);
    const int good = (ferror(handle) == 0);
    fclose(handle);
    free(stream);
    return good;
}

/** @brief One failing edge as the vis arm draws it. */
typedef struct
{
    unsigned int edge;                /**< Edge index in the answer key. */
    int status;                       /**< Index into EDGE_STATUS_NAMES. */
    const TreeFrame *earlier;         /**< Frame t [BORROWS]. */
    const TreeFrame *later;           /**< Frame t + 1 [BORROWS]. */
    unsigned int offset_before;       /**< Node offset of frame t. */
    unsigned int offset_after;        /**< Node offset of frame t + 1. */
    const int *leaf_at_peak[2];       /**< Leaf per peak voxel of t and t + 1 [BORROWS]. */
    const int *from;                  /**< t z y x of the source node [BORROWS]. */
    const int *to;                    /**< t z y x of the target node [BORROWS]. */
    unsigned int source_leaf;         /**< The source node's leaf. */
    unsigned int cell;                /**< The source's unified object. */
    unsigned int true_target;         /**< The target's unified object. */
    size_t cell_size;                 /**< Positive voxels of the cell. */
    unsigned int leaves;              /**< Basins of the cell. */
    unsigned int target_size;         /**< Positive voxels of the true target. */
    unsigned long long agree_view;    /**< Cell voxels agreeing at the view's lag. */
    unsigned long long agree_true;    /**< Cell voxels agreeing at the true step. */
    unsigned int land_true;           /**< Of those at the view's lag, how many land in the true target. */
    unsigned int land_objects;        /**< Objects receiving any at the view's lag. */
} VisCase;

/**
 * @brief A bright colour fixed by an object id, by integer mixing.
 *
 * @param[in]  object The id.
 * @param[out] rgb    Three bytes [BORROWS].
 */
static void object_colour(unsigned int object, unsigned char *rgb)
{
    const unsigned int mixed = object * 2654435761u;
    rgb[0] = (unsigned char)(80u + ((mixed >> 3u) % 160u));
    rgb[1] = (unsigned char)(80u + ((mixed >> 11u) % 120u));
    rgb[2] = (unsigned char)(80u + ((mixed >> 19u) % 160u));
}

/**
 * @brief Fills a square of voxel cells in a panel with one colour.
 *
 * @param[in,out] rgb     The picture [BORROWS].
 * @param[in]     width   Picture width in pixels.
 * @param[in]     left    Panel's left pixel.
 * @param[in]     row     Voxel row in the crop.
 * @param[in]     column  Voxel column in the crop.
 * @param[in]     inset   Pixels left bare on each side of the cell.
 * @param[in]     colour  Three bytes [BORROWS].
 */
static void paint_voxel(unsigned char *rgb, unsigned int width, unsigned int left, int row, int column,
                        unsigned int inset, const unsigned char *colour)
{
    if ((row < 0) || (column < 0) || (row >= (int)VIS_CROP) || (column >= (int)VIS_CROP))
    {
        return;
    }
    for (unsigned int down = inset; down < VIS_SCALE - inset; down += 1u)
    {
        for (unsigned int across = inset; across < VIS_SCALE - inset; across += 1u)
        {
            // Narrowing is safe: row and column were tested inside the crop.
            const size_t pixel = ((size_t)((unsigned int)row * VIS_SCALE + down) * width
                                  + left + (unsigned int)column * VIS_SCALE + across) * 3u;
            rgb[pixel] = colour[0];
            rgb[pixel + 1u] = colour[1];
            rgb[pixel + 2u] = colour[2];
        }
    }
}

/**
 * @brief Draws a plus of voxel cells centred on a voxel, so a marker reads above the tint.
 *
 * @param[in,out] rgb    The picture [BORROWS].
 * @param[in]     width  Picture width in pixels.
 * @param[in]     left   Panel's left pixel.
 * @param[in]     row    Centre voxel row in the crop.
 * @param[in]     column Centre voxel column in the crop.
 * @param[in]     colour Three bytes [BORROWS].
 */
static void paint_marker(unsigned char *rgb, unsigned int width, unsigned int left, int row, int column,
                         const unsigned char *colour)
{
    for (int step = -2; step <= 2; step += 1)
    {
        paint_voxel(rgb, width, left, row + step, column, 1u, colour);
        paint_voxel(rgb, width, left, row, column + step, 1u, colour);
    }
}

/**
 * @brief The vis arm: draws one failing edge from the engine's own state, frame t beside frame t + 1, each at
 *        its answer key node's z, and appends it to the page.
 *
 * Every channel is an integer read off engine state: raw intensity scaled by the crop's largest, positive
 * voxels tinted by their object, object boundaries in the object's colour, the source cell's boundary green
 * in frame t, the true target's green in frame t + 1, the objects the tree linked the cell to red there
 * (yellow where the link is the true target), the answer key's nodes as green plus marks, the cell's peak
 * as white, where the tree carried that peak as magenta, and the answer key's other nodes on the slice as
 * white cells.
 *
 * @param[in] buffers The engine buffers, slot 0 labels and signs for t and slot 1 for t + 1 [BORROWS].
 * @param[in] inputs  The scored sample [BORROWS].
 * @param[in] stack   The open stack file [BORROWS].
 * @param[in] view    The edge [BORROWS].
 * @return            1 on success, 0 otherwise.
 */
static int render_case(const EngineBuffers *buffers, const CoherenceInputs *inputs, FILE *stack, const VisCase *view)
{
    const size_t voxels = (size_t)buffers->depth * buffers->height * buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int panel = VIS_CROP * VIS_SCALE;
    const unsigned int width = 2u * panel + VIS_GAP;
    const unsigned int height = panel;
    unsigned char *const rgb = (unsigned char *)calloc((size_t)width * height * 3u, 1u);
    unsigned short *const raw[2] = {(unsigned short *)malloc((size_t)plane * sizeof(unsigned short)),
                                    (unsigned short *)malloc((size_t)plane * sizeof(unsigned short))};
    unsigned int *const object[2] = {(unsigned int *)malloc((size_t)VIS_CROP * VIS_CROP * sizeof(unsigned int)),
                                     (unsigned int *)malloc((size_t)VIS_CROP * VIS_CROP * sizeof(unsigned int))};
    int good = (rgb != NULL) && (raw[0] != NULL) && (raw[1] != NULL) && (object[0] != NULL) && (object[1] != NULL);

    // The crop is centred on the source node in both panels, so the target's displacement shows.
    const int top = (view->from[2] - (int)(VIS_CROP / 2u) < 0) ? 0
                  : ((view->from[2] + (int)(VIS_CROP / 2u) > (int)buffers->height) ? (int)buffers->height - (int)VIS_CROP
                                                                                  : view->from[2] - (int)(VIS_CROP / 2u));
    const int left_column = (view->from[3] - (int)(VIS_CROP / 2u) < 0) ? 0
                          : ((view->from[3] + (int)(VIS_CROP / 2u) > (int)buffers->width) ? (int)buffers->width - (int)VIS_CROP
                                                                                          : view->from[3] - (int)(VIS_CROP / 2u));
    const int slice[2] = {view->from[1], view->to[1]};
    const unsigned int times[2] = {view->earlier->time, view->later->time};
    const unsigned int offsets[2] = {view->offset_before, view->offset_after};
    const TreeFrame *const tree[2] = {view->earlier, view->later};
    unsigned int brightest = 1u;
    for (unsigned int side = 0u; (good != 0) && (side < 2u); side += 1u)
    {
        // Narrowing is safe: node coordinates lie inside the view.
        const long long offset = 20LL + 2LL * (long long)((size_t)times[side] * voxels + (size_t)slice[side] * plane);
        good = (STACK_SEEK(stack, offset, SEEK_SET) == 0) && (fread(raw[side], sizeof(unsigned short), plane, stack) == plane);
        for (unsigned int down = 0u; (good != 0) && (down < VIS_CROP); down += 1u)
        {
            for (unsigned int across = 0u; across < VIS_CROP; across += 1u)
            {
                // Narrowing is safe: the crop was placed inside the view.
                const unsigned int flat = (unsigned int)(top + (int)down) * buffers->width + (unsigned int)(left_column + (int)across);
                const unsigned int voxel = (unsigned int)slice[side] * plane + flat;
                brightest = (raw[side][flat] > brightest) ? raw[side][flat] : brightest;
                unsigned int id = VIS_NO_OBJECT;
                if (((buffers->positive[side][voxel / 64u] >> (voxel % 64u)) & 1ULL) != 0ULL)
                {
                    const int leaf = view->leaf_at_peak[side][buffers->labels[side][voxel]];
                    if (leaf >= 0)
                    {
                        // Narrowing is safe: the leaf was found, so it is nonnegative.
                        id = inputs->unified_of[offsets[side] + tree[side]->object_of[(unsigned int)leaf]];
                    }
                }
                object[side][down * VIS_CROP + across] = id;
            }
        }
    }

    const unsigned int *const links_begin = &inputs->unified_start[view->cell];
    const unsigned char green[3] = {40u, 255u, 60u};
    const unsigned char red[3] = {255u, 50u, 40u};
    const unsigned char yellow[3] = {255u, 230u, 30u};
    const unsigned char white[3] = {255u, 255u, 255u};
    const unsigned char magenta[3] = {255u, 60u, 255u};
    for (unsigned int side = 0u; (good != 0) && (side < 2u); side += 1u)
    {
        const unsigned int left = side * (panel + VIS_GAP);
        for (unsigned int down = 0u; down < VIS_CROP; down += 1u)
        {
            for (unsigned int across = 0u; across < VIS_CROP; across += 1u)
            {
                // Narrowing is safe: the crop was placed inside the view.
                const unsigned int flat = (unsigned int)(top + (int)down) * buffers->width + (unsigned int)(left_column + (int)across);
                const unsigned int gray = (unsigned int)raw[side][flat] * 255u / brightest;
                const unsigned int id = object[side][down * VIS_CROP + across];
                unsigned char colour[3] = {(unsigned char)gray, (unsigned char)gray, (unsigned char)gray};
                if (id != VIS_NO_OBJECT)
                {
                    unsigned char own[3];
                    object_colour(id, own);
                    int boundary = 0;
                    const int neighbours[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
                    for (unsigned int which = 0u; which < 4u; which += 1u)
                    {
                        const int near_row = (int)down + neighbours[which][0];
                        const int near_column = (int)across + neighbours[which][1];
                        const unsigned int near = ((near_row < 0) || (near_column < 0) || (near_row >= (int)VIS_CROP)
                                                   || (near_column >= (int)VIS_CROP))
                                                ? id
                                                : object[side][(unsigned int)near_row * VIS_CROP + (unsigned int)near_column];
                        boundary = boundary || (near != id);
                    }
                    for (unsigned int channel = 0u; channel < 3u; channel += 1u)
                    {
                        colour[channel] = (unsigned char)((gray * 5u + (unsigned int)own[channel] * 3u) / 8u);
                    }
                    if (boundary != 0)
                    {
                        const unsigned char *highlight = own;
                        int linked = 0;
                        for (unsigned int link = links_begin[0]; link < links_begin[1]; link += 1u)
                        {
                            linked = linked || ((unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL) == id);
                        }
                        if ((side == 0u) && (id == view->cell))
                        {
                            highlight = green;
                        }
                        else if ((side == 1u) && (linked != 0) && (id == view->true_target))
                        {
                            highlight = yellow;
                        }
                        else if ((side == 1u) && (id == view->true_target))
                        {
                            highlight = green;
                        }
                        else if ((side == 1u) && (linked != 0))
                        {
                            highlight = red;
                        }
                        colour[0] = highlight[0];
                        colour[1] = highlight[1];
                        colour[2] = highlight[2];
                    }
                }
                paint_voxel(rgb, width, left, (int)down, (int)across, 0u, colour);
            }
        }
        // The answer key's other nodes on this slice, as white cells.
        for (unsigned int node = 0u; node < inputs->key->node_count; node += 1u)
        {
            const int *const place = &inputs->key->node_coordinates[(size_t)node * 4u];
            // Narrowing is safe: a node time is nonnegative.
            if ((place[0] >= 0) && ((unsigned int)place[0] == times[side]) && (place[1] == slice[side]))
            {
                paint_voxel(rgb, width, left, place[2] - top, place[3] - left_column, 2u, white);
            }
        }
    }
    if (good != 0)
    {
        const unsigned int peak = view->earlier->peaks[view->source_leaf];
        const unsigned int peak_rest = peak % plane;
        const int peak_place[3] = {(int)(peak / plane), (int)(peak_rest / buffers->width), (int)(peak_rest % buffers->width)};
        paint_marker(rgb, width, 0u, view->from[2] - top, view->from[3] - left_column, green);
        paint_marker(rgb, width, 0u, peak_place[1] - top, peak_place[2] - left_column, white);
        paint_marker(rgb, width, panel + VIS_GAP, view->to[2] - top, view->to[3] - left_column, green);
        const int *const lag = (view->earlier->forward_lag != NULL) ? &view->earlier->forward_lag[3u * view->source_leaf]
                                                                     : view->earlier->lag_to_next;
        paint_marker(rgb, width, panel + VIS_GAP, peak_place[1] + lag[1] - top, peak_place[2] + lag[2] - left_column,
                     magenta);

        char path[1024];
        snprintf(path, sizeof(path), "%s/%s_t%u_edge%u.png", inputs->vis_directory, inputs->sample, view->earlier->time,
                 view->edge);
        good = write_png_rgb(path, rgb, width, height);
        unsigned int linked_count = links_begin[1] - links_begin[0];
        int linked_true = 0;
        for (unsigned int link = links_begin[0]; link < links_begin[1]; link += 1u)
        {
            linked_true = linked_true || ((unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL) == view->true_target);
        }
        // Integer percentages, half rounding up.
        const unsigned long long view_share = (view->cell_size > 0u) ? (view->agree_view * 200ULL + view->cell_size) / (2ULL * view->cell_size) : 0ULL;
        const unsigned long long true_share = (view->cell_size > 0u) ? (view->agree_true * 200ULL + view->cell_size) / (2ULL * view->cell_size) : 0ULL;
        const unsigned long long landing_share = (view->agree_view > 0ULL) ? ((unsigned long long)view->land_true * 200ULL + view->agree_view) / (2ULL * view->agree_view) : 0ULL;
        fprintf(inputs->vis_index,
                "<figure><img src=\"%s_t%u_edge%u.png\"><figcaption><b>%s</b> %s frame %u&rarr;%u &middot; "
                "source node z%d y%d x%d, target node z%d y%d x%d (step %d %d %d) &middot; peak z%d y%d x%d carried by "
                "lag %d %d %d to z%d &middot; view lag %d %d %d &middot; cell %zu voxels in %u basins, true target %u "
                "voxels &middot; agrees %llu%% at view lag, %llu%% at true step &middot; at view lag %llu%% lands in "
                "true target, spread over %u objects &middot; tree linked it to %u object%s%s</figcaption></figure>\n",
                inputs->sample, view->earlier->time, view->edge, EDGE_STATUS_NAMES[view->status], inputs->sample,
                view->earlier->time, view->later->time, view->from[1], view->from[2], view->from[3], view->to[1],
                view->to[2], view->to[3], view->to[1] - view->from[1], view->to[2] - view->from[2],
                view->to[3] - view->from[3], peak_place[0], peak_place[1], peak_place[2], lag[0], lag[1], lag[2],
                peak_place[0] + lag[0], view->earlier->lag_to_next[0], view->earlier->lag_to_next[1],
                view->earlier->lag_to_next[2], view->cell_size, view->leaves, view->target_size, view_share,
                true_share, landing_share, view->land_objects, linked_count, (linked_count == 1u) ? "" : "s",
                (linked_true != 0) ? ", including the true target" : "");
        fflush(inputs->vis_index);
    }
    free(rgb);
    free(raw[0]);
    free(raw[1]);
    free(object[0]);
    free(object[1]);
    return good;
}

/**
 * @brief Reads, for every failing edge and every correct edge leaving a frame a failure leaves, how the
 *        source cell agrees with the next frame at every lag, and where its agreeing voxels land.
 *
 * One row per edge goes to the rules' coherence file:
 *     sample time status size_A leaves_A size_B own_z own_y own_x view_z view_y view_x true_z true_y true_x
 *     agree_own agree_view agree_true land_B land_max land_sumsq land_objects
 * where own is the lag at which the cell A alone agrees most with the next frame's positive voxels, over
 * every lag at once; view is the view's lag; true is the answer key's step; agree_* count A's voxels
 * that land on positive voxels at each lag; and land_* describe, at the view's lag, how those voxels
 * divide among the next frame's objects: the count landing in the true target B, the largest count, the
 * sum of squared counts, and how many objects receive any. Every value is an integer.
 *
 * @param[in,out] buffers The engine buffers [BORROWS].
 * @param[in]     inputs  The scored sample [BORROWS].
 * @param[in]     out     The coherence file [BORROWS].
 * @return                1 on success, 0 otherwise.
 */
static int read_coherence(EngineBuffers *buffers, const CoherenceInputs *inputs, FILE *out)
{
    const AnswerKey *const key = inputs->key;
    const size_t voxels = (size_t)buffers->depth * buffers->height * buffers->width;
    const size_t words = (voxels + 63u) / 64u;
    const unsigned int plane = buffers->height * buffers->width;
    unsigned char *const failing_time = (unsigned char *)calloc((size_t)inputs->stack_frames + 1u, 1u);
    int *const leaf_at_peak[2] = {(int *)malloc(voxels * sizeof(int)), (int *)malloc(voxels * sizeof(int))};
    unsigned long long *const mask = (unsigned long long *)malloc(words * sizeof(unsigned long long));
    unsigned char *const leaf_in_cell = (unsigned char *)malloc(voxels / 8u + 1u);
    unsigned int *const unified_size = (unsigned int *)calloc((size_t)inputs->unified_count + 1u, sizeof(unsigned int));
    unsigned int *const landing = (unsigned int *)calloc((size_t)inputs->unified_count + 1u, sizeof(unsigned int));
    unsigned int *const touched = (unsigned int *)malloc(((size_t)inputs->unified_count + 1u) * sizeof(unsigned int));
    size_t cell_room = 1u << 16u;
    unsigned int *cell_voxels = (unsigned int *)malloc(cell_room * sizeof(unsigned int));
    FILE *const stack = fopen(inputs->stack_path, "rb");
    int good = (failing_time != NULL) && (leaf_at_peak[0] != NULL) && (leaf_at_peak[1] != NULL) && (mask != NULL)
            && (leaf_in_cell != NULL) && (unified_size != NULL) && (landing != NULL) && (touched != NULL)
            && (cell_voxels != NULL) && (stack != NULL);
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        leaf_at_peak[0][voxel] = -1;
        leaf_at_peak[1][voxel] = -1;
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key->edge_count); edge += 1u)
    {
        if ((inputs->edge_status[edge] >= 1) && (inputs->edge_status[edge] <= 3))
        {
            const long source = node_slot_of(key, key->edge_ends[2u * edge]);
            // Narrowing is safe: a scored edge's source exists and its time lies in the stack.
            failing_time[(unsigned int)key->node_coordinates[(size_t)source * 4u]] = 1u;
        }
    }

    for (unsigned int frame = 0u; (good != 0) && (frame + 1u < inputs->frame_count); frame += 1u)
    {
        const TreeFrame *const earlier = &inputs->frames[frame];
        if ((failing_time[earlier->time] == 0u) || (earlier->forward == NULL))
        {
            continue;
        }
        TreeFrame held[2];
        memset(held, 0, sizeof(held));
        for (unsigned int slot = 0u; (good != 0) && (slot < 2u); slot += 1u)
        {
            const long long offset = 20LL + (long long)((size_t)(earlier->time + slot) * voxels * 2u);
            good = (STACK_SEEK(stack, offset, SEEK_SET) == 0)
                && (fread(buffers->volume, sizeof(unsigned short), voxels, stack) == voxels)
                && (grow_leaves(buffers, slot, &held[slot]) != 0);
            for (unsigned int leaf = 0u; (good != 0) && (leaf < held[slot].leaf_count); leaf += 1u)
            {
                // Narrowing is safe: a leaf count is below 2^31.
                leaf_at_peak[slot][held[slot].peaks[leaf]] = (int)leaf;
            }
        }
        const unsigned int *const labels_before = buffers->labels[0];
        const unsigned int *const labels_after = buffers->labels[1];
        const unsigned long long *const positive_before = buffers->positive[0];
        const unsigned long long *const positive_after = buffers->positive[1];
        const unsigned int offset_before = inputs->node_offset[frame];
        const unsigned int offset_after = inputs->node_offset[frame + 1u];
        const TreeFrame *const later = &inputs->frames[frame + 1u];

        // Every unified object's positive voxels in the later frame.
        for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
        {
            if (((positive_after[voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
            {
                continue;
            }
            const int leaf = leaf_at_peak[1][labels_after[voxel]];
            if (leaf >= 0)
            {
                // Narrowing is safe: the leaf was found, so it is nonnegative.
                unified_size[inputs->unified_of[offset_after + later->object_of[(unsigned int)leaf]]] += 1u;
            }
        }

        for (unsigned int edge = 0u; (good != 0) && (edge < key->edge_count); edge += 1u)
        {
            const int status = inputs->edge_status[edge];
            if ((status < 0) || (status > 3))
            {
                continue;
            }
            const long source = node_slot_of(key, key->edge_ends[2u * edge]);
            const long target = node_slot_of(key, key->edge_ends[2u * edge + 1u]);
            const int *const from = &key->node_coordinates[(size_t)source * 4u];
            const int *const to = &key->node_coordinates[(size_t)target * 4u];
            // Narrowing is safe: a scored edge's times lie in the stack.
            if (((unsigned int)from[0] != earlier->time) || ((unsigned int)to[0] != earlier->time + 1u))
            {
                continue;
            }
            // Narrowing is safe: a scored edge that is not missed has both leaves.
            const unsigned int cell = inputs->unified_of[offset_before
                                                          + earlier->object_of[(unsigned int)inputs->node_leaf[source]]];
            const unsigned int true_target = inputs->unified_of[offset_after
                                                                 + later->object_of[(unsigned int)inputs->node_leaf[target]]];

            // The cell's leaves, and its voxels as a mask.
            memset(leaf_in_cell, 0, voxels / 8u + 1u);
            unsigned int leaves = 0u;
            for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
            {
                if (inputs->unified_of[offset_before + earlier->object_of[leaf]] == cell)
                {
                    leaf_in_cell[leaf / 8u] |= (unsigned char)(1u << (leaf % 8u));
                    leaves += 1u;
                }
            }
            memset(mask, 0, words * sizeof(unsigned long long));
            size_t cell_size = 0u;
            for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
            {
                if (((positive_before[voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
                {
                    continue;
                }
                const int leaf = leaf_at_peak[0][labels_before[voxel]];
                // Narrowing is safe: the leaf was tested nonnegative first.
                if ((leaf < 0) || (((leaf_in_cell[(unsigned int)leaf / 8u] >> ((unsigned int)leaf % 8u)) & 1u) == 0u))
                {
                    continue;
                }
                mask[voxel / 64u] |= 1ULL << (voxel % 64u);
                if (cell_size == cell_room)
                {
                    cell_room *= 2u;
                    unsigned int *const grown = (unsigned int *)realloc(cell_voxels, cell_room * sizeof(unsigned int));
                    if (grown == NULL)
                    {
                        good = 0;
                        break;
                    }
                    cell_voxels = grown;
                }
                // Narrowing is safe: a voxel index of the view fits an unsigned int.
                cell_voxels[cell_size] = (unsigned int)voxel;
                cell_size += 1u;
            }

            ShiftAgreementRequest motion;
            memset(&motion, 0, sizeof(motion));
            motion.axes = 3u;
            motion.extents[0] = buffers->depth;
            motion.extents[1] = buffers->height;
            motion.extents[2] = buffers->width;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                motion.weights[axis] = AXIS_WEIGHTS[axis];
            }
            motion.before = mask;
            motion.after = positive_after;
            motion.counts = NULL;
            good = (good != 0) && (cell_size > 0u) && (shift_agreement_run(&motion) == 0L);
            if (good == 0)
            {
                break;
            }
            const int true_lag[3] = {to[1] - from[1], to[2] - from[2], to[3] - from[3]};
            const int *const lags[3] = {motion.lag, earlier->lag_to_next, true_lag};
            unsigned long long agreement[3] = {0ULL, 0ULL, 0ULL};
            unsigned int touched_count = 0u;
            for (unsigned int which = 0u; which < 3u; which += 1u)
            {
                for (size_t member = 0u; member < cell_size; member += 1u)
                {
                    const unsigned int voxel = cell_voxels[member];
                    const unsigned int rest = voxel % plane;
                    // Widening to long keeps a negative landing representable before the bounds test.
                    const long z = (long)(voxel / plane) + (long)lags[which][0];
                    const long y = (long)(rest / buffers->width) + (long)lags[which][1];
                    const long x = (long)(rest % buffers->width) + (long)lags[which][2];
                    if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height)
                     || (x < 0L) || (x >= (long)buffers->width))
                    {
                        continue;
                    }
                    // Narrowing is safe: the landing lies inside the view.
                    const unsigned int landed = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
                    if (((positive_after[landed / 64u] >> (landed % 64u)) & 1ULL) == 0ULL)
                    {
                        continue;
                    }
                    agreement[which] += 1ULL;
                    // Where the agreeing voxels land is read at the view's lag, the lag the tree carries
                    // peaks by; a cell's own best lag saturates in dense tissue and says nothing.
                    if (which != 1u)
                    {
                        continue;
                    }
                    const int leaf = leaf_at_peak[1][labels_after[landed]];
                    if (leaf >= 0)
                    {
                        // Narrowing is safe: the leaf was found, so it is nonnegative.
                        const unsigned int object = inputs->unified_of[offset_after + later->object_of[(unsigned int)leaf]];
                        if (landing[object] == 0u)
                        {
                            touched[touched_count] = object;
                            touched_count += 1u;
                        }
                        landing[object] += 1u;
                    }
                }
            }
            unsigned long long land_max = 0ULL;
            unsigned long long land_sumsq = 0ULL;
            for (unsigned int slot = 0u; slot < touched_count; slot += 1u)
            {
                const unsigned long long count = landing[touched[slot]];
                land_max = (count > land_max) ? count : land_max;
                land_sumsq += count * count;
            }
            const unsigned int land_true = landing[true_target];
            for (unsigned int slot = 0u; slot < touched_count; slot += 1u)
            {
                landing[touched[slot]] = 0u;
            }
            if (out != NULL)
            {
                fprintf(out, "%s\t%u\t%s\t%zu\t%u\t%u\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%llu\t%llu\t%llu\t%u\t%llu\t%llu\t%u\n",
                        inputs->sample, earlier->time, EDGE_STATUS_NAMES[status], cell_size, leaves,
                        unified_size[true_target], motion.lag[0], motion.lag[1], motion.lag[2], earlier->lag_to_next[0],
                        earlier->lag_to_next[1], earlier->lag_to_next[2], true_lag[0], true_lag[1], true_lag[2],
                        agreement[0], agreement[1], agreement[2], land_true, land_max, land_sumsq, touched_count);
            }
            if ((inputs->vis_index != NULL) && (status >= 1) && (status <= 3))
            {
                VisCase view;
                memset(&view, 0, sizeof(view));
                view.edge = edge;
                view.status = status;
                view.earlier = earlier;
                view.later = later;
                view.offset_before = offset_before;
                view.offset_after = offset_after;
                view.leaf_at_peak[0] = leaf_at_peak[0];
                view.leaf_at_peak[1] = leaf_at_peak[1];
                view.from = from;
                view.to = to;
                // Narrowing is safe: a scored edge that is not missed has its source leaf.
                view.source_leaf = (unsigned int)inputs->node_leaf[source];
                view.cell = cell;
                view.true_target = true_target;
                view.cell_size = cell_size;
                view.leaves = leaves;
                view.target_size = unified_size[true_target];
                view.agree_view = agreement[1];
                view.agree_true = agreement[2];
                view.land_true = land_true;
                view.land_objects = touched_count;
                good = render_case(buffers, inputs, stack, &view);
            }
        }

        // Clear this frame pair's maps and sizes for the next.
        for (unsigned int slot = 0u; slot < 2u; slot += 1u)
        {
            for (unsigned int leaf = 0u; leaf < held[slot].leaf_count; leaf += 1u)
            {
                leaf_at_peak[slot][held[slot].peaks[leaf]] = -1;
            }
            free(held[slot].peaks);
            free(held[slot].sizes);
            free(held[slot].sums);
            free(held[slot].joined);
        }
        for (unsigned int node = offset_after; node < inputs->node_offset[frame + 2u]; node += 1u)
        {
            unified_size[inputs->unified_of[node]] = 0u;
        }
    }
    fflush(out);
    if (stack != NULL)
    {
        fclose(stack);
    }
    free(cell_voxels);
    free(touched);
    free(landing);
    free(unified_size);
    free(leaf_in_cell);
    free(mask);
    free(leaf_at_peak[0]);
    free(leaf_at_peak[1]);
    free(failing_time);
    return good;
}

/**
 * @brief Scores one sample: grows the tree and tallies the answer key's edges against it.
 *
 * @param[in]  directory Where the dumped files are.
 * @param[in]  sample    The sample name.
 * @param[in]  rules     The tree's rules [BORROWS].
 * @param[out] tally     The sample's tallies [BORROWS].
 * @return               1 on success, 0 otherwise.
 */
static int score_sample(const char *directory, const char *sample, const TreeRules *rules, EdgeTally *tally)
{
    memset(tally, 0, sizeof(*tally));
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.truth", directory, sample);
    AnswerKey key;
    if (read_answer_key(path, &key) == 0)
    {
        fprintf(stderr, "  could not read %s\n", path);
        return 0;
    }
    snprintf(path, sizeof(path), "%s/%s.stack", directory, sample);
    FILE *const stack = fopen(path, "rb");
    unsigned int header[5];
    if ((stack == NULL) || (fread(header, sizeof(unsigned int), 5u, stack) != 5u))
    {
        fprintf(stderr, "  could not read %s\n", path);
        if (stack != NULL)
        {
            fclose(stack);
        }
        release_answer_key(&key);
        return 0;
    }
    const unsigned int stack_frames = header[0];

    // The frames scored are those the answer key reaches, below the frames dumped, ascending.
    unsigned char *const reached = (unsigned char *)calloc((size_t)stack_frames + 1u, 1u);
    int *const tree_index_of_time = (int *)malloc(((size_t)stack_frames + 1u) * sizeof(int));
    if ((reached == NULL) || (tree_index_of_time == NULL))
    {
        fclose(stack);
        free(reached);
        free(tree_index_of_time);
        release_answer_key(&key);
        return 0;
    }
    for (unsigned int node = 0u; node < key.node_count; node += 1u)
    {
        const int time = key.node_coordinates[(size_t)node * 4u];
        // Narrowing is safe: the time was tested nonnegative first.
        if ((time >= 0) && ((unsigned int)time < stack_frames))
        {
            reached[(unsigned int)time] = 1u;
        }
    }
    unsigned int frame_count = 0u;
    for (unsigned int time = 0u; time < stack_frames; time += 1u)
    {
        // Narrowing is safe: a frame count is at most the dumped frames, far below 2^31.
        tree_index_of_time[time] = (reached[time] != 0u) ? (int)frame_count : -1;
        frame_count += (reached[time] != 0u) ? 1u : 0u;
    }
    TreeFrame *const frames = (TreeFrame *)calloc((size_t)frame_count + 1u, sizeof(TreeFrame));
    if (frames != NULL)
    {
        unsigned int written = 0u;
        for (unsigned int time = 0u; time < stack_frames; time += 1u)
        {
            if (reached[time] != 0u)
            {
                frames[written].time = time;
                written += 1u;
            }
        }
    }

    EngineBuffers buffers;
    memset(&buffers, 0, sizeof(buffers));
    buffers.depth = header[1];
    buffers.height = header[2];
    buffers.width = header[3];
    const size_t voxels = (size_t)buffers.depth * buffers.height * buffers.width;
    buffers.peak_room = ((buffers.depth + 1u) / 2u) * ((buffers.height + 1u) / 2u) * ((buffers.width + 1u) / 2u);
    buffers.pair_room = 1u << 18u;
    buffers.overlap_room = 1u << 16u;
    buffers.volume = (unsigned short *)malloc(voxels * sizeof(unsigned short));
    buffers.peak_indices = (unsigned int *)malloc((size_t)buffers.peak_room * sizeof(unsigned int));
    buffers.sizes = (unsigned int *)malloc((size_t)buffers.peak_room * sizeof(unsigned int));
    buffers.sums = (unsigned long long *)malloc((size_t)buffers.peak_room * 3u * sizeof(unsigned long long));
    buffers.peak_limbs = (unsigned int *)malloc((size_t)buffers.peak_room * BINOMIAL_BASINS_LIMBS
                                                * sizeof(unsigned int));
    buffers.adjacency = (unsigned int *)malloc((size_t)buffers.pair_room * 2u * sizeof(unsigned int));
    buffers.joined = (unsigned int *)malloc((size_t)buffers.pair_room * 2u * sizeof(unsigned int));
    buffers.overlap_before = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    buffers.overlap_after = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    buffers.overlap_shared = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        buffers.labels[slot] = (unsigned int *)malloc(voxels * sizeof(unsigned int));
        buffers.positive[slot] = (unsigned long long *)malloc(((voxels + 63u) / 64u) * sizeof(unsigned long long));
        if ((rules->climb != 0) || (rules->cast != 0) || (rules->parallax != 0))
        {
            buffers.leaf_at_peak[slot] = (int *)malloc(voxels * sizeof(int));
            buffers.basin_start[slot] = (unsigned int *)malloc(((size_t)buffers.peak_room + 2u) * sizeof(unsigned int));
            buffers.basin_voxels[slot] = (unsigned int *)malloc(voxels * sizeof(unsigned int));
            for (size_t voxel = 0u; (buffers.leaf_at_peak[slot] != NULL) && (voxel < voxels); voxel += 1u)
            {
                buffers.leaf_at_peak[slot][voxel] = -1;
            }
        }
    }

    // Each node's leaf, found while its frame's labels are held.
    int *const node_leaf = (int *)malloc(((size_t)key.node_count + 1u) * sizeof(int));
    if (node_leaf != NULL)
    {
        for (unsigned int node = 0u; node < key.node_count; node += 1u)
        {
            node_leaf[node] = -1;
        }
    }

    int good = (frames != NULL) && (node_leaf != NULL) && (buffers.volume != NULL) && (buffers.peak_indices != NULL)
            && (buffers.sizes != NULL) && (buffers.sums != NULL) && (buffers.peak_limbs != NULL)
            && (buffers.adjacency != NULL) && (buffers.joined != NULL) && (buffers.overlap_before != NULL)
            && (buffers.overlap_after != NULL) && (buffers.overlap_shared != NULL) && (buffers.labels[0] != NULL)
            && (buffers.labels[1] != NULL) && (buffers.positive[0] != NULL) && (buffers.positive[1] != NULL)
            && ((rules->climb == 0) || ((buffers.leaf_at_peak[0] != NULL) && (buffers.leaf_at_peak[1] != NULL)
                                        && (buffers.basin_start[0] != NULL) && (buffers.basin_start[1] != NULL)
                                        && (buffers.basin_voxels[0] != NULL) && (buffers.basin_voxels[1] != NULL)));
    // The machine holds every frame on the device, for the overlap and the climb, where either runs.
    const int machine_wanted = (rules->pick != 0) || (rules->climb == 1) || (rules->climb == 3);
    const unsigned long long started = clock_milliseconds();
    StageClock clocks;
    memset(&clocks, 0, sizeof(clocks));
    // The object: a frame is cut into runs from slot 1 of the cut, slot 0 taking every write a falsy voxel makes, so
    // the cut steers by truth values and never branches; the runs are then scattered by leaf, so a leaf's runs are
    // one range and a run need not name its leaf. A leaf's code is its leaf plus one at its peak voxel, else zero.
    const bool object = rules->object;
    size_t object_cut_room = 0u;
    unsigned int *object_cut = NULL;
    size_t object_run_room = 0u;
    size_t object_run_count = 0u;
    unsigned int *object_runs = NULL;
    size_t object_leaf_room = 0u;
    size_t object_leaf_count = 0u;
    unsigned int *object_leaf_runs = NULL;
    unsigned int *const object_first_run = (unsigned int *)calloc(((size_t)frame_count + 1u) * object, sizeof(unsigned int));
    unsigned int *const object_leaf_code = (unsigned int *)calloc(voxels * object, sizeof(unsigned int));
    // A run packs its first voxel above eight bits of its length less one, and the cut packs its leaf the same way. A
    // view past that aliases runs, which the object's control shows as aberrant leaves rather than being refused here.
    good = good && (!object || (object_first_run && object_leaf_code));
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        unsigned long long mark = clock_microseconds();
        const long long offset = 20LL + (long long)((size_t)frames[frame].time * voxels * 2u);
        good = (STACK_SEEK(stack, offset, SEEK_SET) == 0)
            && (fread(buffers.volume, sizeof(unsigned short), voxels, stack) == voxels);
        clocks.read += clock_microseconds() - mark;
        mark = clock_microseconds();
        // The current frame fills slot 1; the frame before, when it is held, sits in slot 0.
        good = (good != 0) && (grow_leaves(&buffers, 1u, &frames[frame]) != 0);
        clocks.basins += clock_microseconds() - mark;
        mark = clock_microseconds();
        if ((good != 0) && machine_wanted && (buffers.machine == NULL))
        {
            // Opened once the basin engine holds its buffers, leaving the motion and overlap engines their room:
            // four padded transform volumes, and a margin.
            unsigned long long padded = 1ull;
            const unsigned int extents[3] = {buffers.depth, buffers.height, buffers.width};
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                unsigned long long power = 1ull;
                while (power < (2ull * (unsigned long long)extents[axis]) - 1ull)
                {
                    power <<= 1u;
                }
                padded *= power;
            }
            ClimbMachineShape shape;
            memset(&shape, 0, sizeof(shape));
            shape.depth = buffers.depth;
            shape.height = buffers.height;
            shape.width = buffers.width;
            shape.peak_room = buffers.peak_room;
            shape.frames = frame_count;
            shape.weight_z = AXIS_WEIGHTS[0];
            // Narrowing is safe: four padded volumes of a view the engines accept fit well within 2^32 mebibytes.
            shape.reserve_bytes = (unsigned int)(((padded * 16ull) >> 20u) + 768ull);
            buffers.machine = climb_machine_open(&shape);
            good = (buffers.machine != NULL) ? 1 : 0;
        }
        if ((good != 0) && ((rules->climb >= 2) || (rules->cast != 0) || (rules->parallax != 0)))
        {
            // The host reference climbs grouped voxels, and the cast throws them. Grouped once, as the later
            // frame; the swap at the end keeps it for its turn as the earlier frame.
            group_basin_voxels(&buffers, 1u, buffers.labels[1], &frames[frame]);
        }
        if ((good != 0) && (buffers.machine != NULL))
        {
            // The frame goes to the device once, for the overlap and the climb both.
            ClimbMachineFrame stored;
            memset(&stored, 0, sizeof(stored));
            stored.frame = frames[frame].time;
            stored.leaf_count = frames[frame].leaf_count;
            stored.labels = buffers.labels[1];
            stored.positive = buffers.positive[1];
            unsigned int *contact_start = NULL;
            unsigned int *contacts = NULL;
            if ((rules->climb == 1) || (rules->climb == 3))
            {
                // With its leaves' peaks, the machine cuts the frame's basins into runs along its rows.
                stored.peaks = frames[frame].peaks;
                good = (rules->sticky == 0) || (frame_contacts(&frames[frame], &contact_start, &contacts) != 0);
                stored.contact_start = contact_start;
                stored.contacts = contacts;
            }
            good = (good != 0) && (climb_machine_store(buffers.machine, &stored) != 0);
            free(contact_start);
            free(contacts);
        }
        clocks.store += clock_microseconds() - mark;
        mark = clock_microseconds();
        if (good == 0)
        {
            break;
        }
        if (object)
        {
            // The frame as the object the card is fed: each leaf's positive voxels as runs along rows, in raster
            // order, a run's first voxel beside its leaf and its length less one.
            const unsigned long long *const positive = buffers.positive[1];
            size_t positives = 0u;
            for (size_t word = 0u; word < (voxels + 63u) / 64u; word += 1u)
            {
                positives += word_population(positive[word]);
            }
            // A frame cuts at most one run per positive voxel, and one slot past them takes the tentative first voxel.
            good = good && object_room_fit(&object_cut, &object_cut_room, positives + 2u, 2u)
                && object_room_fit(&object_runs, &object_run_room, object_run_count + positives, 1u)
                && object_room_fit(&object_leaf_runs, &object_leaf_room, object_leaf_count + frames[frame].leaf_count, 2u);
        }
        if (object && good)
        {
            const TreeFrame *const tree = &frames[frame];
            const unsigned int *const labels = buffers.labels[1];
            const unsigned long long *const positive = buffers.positive[1];
            unsigned int *const runs = object_cut;
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                object_leaf_code[tree->peaks[leaf]] = leaf + 1u;
            }
            runs[0] = 0u;
            runs[1] = 0u;
            size_t count = 0u;
            size_t voxel = 0u;
            for (unsigned int row = 0u; row < buffers.depth * buffers.height; row += 1u)
            {
                // A row starts with no code, so a live first voxel always begins a run.
                unsigned int previous = 0u;
                for (unsigned int column = 0u; column < buffers.width; column += 1u)
                {
                    // Narrowing is safe: the shifted word is masked to its lowest bit.
                    const unsigned int live = (unsigned int)((positive[voxel >> 6u] >> (voxel & 63u)) & 1ULL);
                    // A voxel that is not positive reads the code at voxel 0 and multiplies it away.
                    const unsigned int code = live * object_leaf_code[labels[voxel] * live];
                    const unsigned int held = !!code;
                    const unsigned int begins = held & (unsigned int)(code != previous);
                    // Narrowing is safe: a voxel index of a view the engines accept fits 32 bits. The first voxel is
                    // written to the next free slot every voxel, and kept only where a run begins.
                    runs[2u * (count + 1u)] = (unsigned int)voxel;
                    count += begins;
                    const size_t slot = count * held;
                    runs[(2u * slot) + 1u] = ((code - held) << 8u) | ((unsigned int)voxel - runs[2u * slot]);
                    previous = code;
                    voxel += 1u;
                }
            }
            // Scattered by leaf, raster order kept within each leaf: a leaf's runs counted, its first run placed past
            // the runs of the leaves before it, each run written at its leaf's cursor, and the cursors set back.
            unsigned int *const leaf_runs = &object_leaf_runs[2u * object_leaf_count];
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                object_leaf_code[tree->peaks[leaf]] = 0u;
                leaf_runs[2u * leaf] = 0u;
                leaf_runs[(2u * leaf) + 1u] = 0u;
            }
            for (size_t slot = 1u; slot <= count; slot += 1u)
            {
                leaf_runs[(2u * (runs[(2u * slot) + 1u] >> 8u)) + 1u] += 1u;
            }
            // Narrowing is safe: a sample's runs are far below 2^32.
            unsigned int placed = (unsigned int)object_run_count;
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                leaf_runs[2u * leaf] = placed;
                placed += leaf_runs[(2u * leaf) + 1u];
            }
            for (size_t slot = 1u; slot <= count; slot += 1u)
            {
                const unsigned int word = runs[(2u * slot) + 1u];
                unsigned int *const cursor = &leaf_runs[2u * (word >> 8u)];
                object_runs[*cursor] = (runs[2u * slot] << 8u) | (word & 0xFFu);
                *cursor += 1u;
            }
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                leaf_runs[2u * leaf] -= leaf_runs[(2u * leaf) + 1u];
            }
            // Narrowing is safe: a sample's runs are far below 2^32.
            object_first_run[frame] = (unsigned int)object_run_count;
            object_run_count += count;
            object_leaf_count += tree->leaf_count;
        }
        if (rules->export_directory != NULL)
        {
            // The shape each object's own edge encloses: second moments of its positive voxels, exact.
            TreeFrame *const tree = &frames[frame];
            tree->moments = (unsigned long long *)calloc((size_t)tree->leaf_count * 6u + 1u, sizeof(unsigned long long));
            tree->exposed = (unsigned int *)calloc((size_t)tree->leaf_count + 1u, sizeof(unsigned int));
            tree->contact_faces = (unsigned int *)calloc((size_t)tree->joined_count + 1u, sizeof(unsigned int));
            good = (tree->moments != NULL) && (tree->exposed != NULL) && (tree->contact_faces != NULL);
            const unsigned int plane = buffers.height * buffers.width;
            for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
            {
                if (((buffers.positive[1][voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
                {
                    continue;
                }
                const int leaf = leaf_of_peak(tree->peaks, tree->leaf_count, buffers.labels[1][voxel]);
                if (leaf < 0)
                {
                    continue;
                }
                // Widening: a coordinate of the view fits comfortably in 64 bits, and so does its square.
                const unsigned long long z = (unsigned long long)(voxel / plane);
                const unsigned long long y = (unsigned long long)((voxel % plane) / buffers.width);
                const unsigned long long x = (unsigned long long)((voxel % plane) % buffers.width);
                // Narrowing is safe: the leaf was found, so it is nonnegative.
                unsigned long long *const moment = &tree->moments[(size_t)(unsigned int)leaf * 6u];
                moment[0] += z * z;
                moment[1] += y * y;
                moment[2] += x * x;
                moment[3] += z * y;
                moment[4] += z * x;
                moment[5] += y * x;
                // The edge the voxel's faces make: a face on a non-positive voxel or the view's edge is
                // exposed; a face on another basin's positive voxel is contact, counted once, from the lower leaf.
                const long neighbours[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
                for (unsigned int face = 0u; face < 6u; face += 1u)
                {
                    // Widening to long keeps a negative neighbour representable before the bounds test.
                    const long near_z = (long)z + neighbours[face][0];
                    const long near_y = (long)y + neighbours[face][1];
                    const long near_x = (long)x + neighbours[face][2];
                    if ((near_z < 0L) || (near_z >= (long)buffers.depth) || (near_y < 0L) || (near_y >= (long)buffers.height)
                     || (near_x < 0L) || (near_x >= (long)buffers.width))
                    {
                        tree->exposed[(unsigned int)leaf] += 1u;
                        continue;
                    }
                    // Narrowing is safe: the neighbour lies inside the view.
                    const size_t near = (size_t)((near_z * (long)buffers.height + near_y) * (long)buffers.width + near_x);
                    if (((buffers.positive[1][near / 64u] >> (near % 64u)) & 1ULL) == 0ULL)
                    {
                        tree->exposed[(unsigned int)leaf] += 1u;
                        continue;
                    }
                    const int other = leaf_of_peak(tree->peaks, tree->leaf_count, buffers.labels[1][near]);
                    if ((other < 0) || (other <= leaf))
                    {
                        // A positive voxel of no leaf is exposed; the same leaf is inside; a lower leaf counts it.
                        tree->exposed[(unsigned int)leaf] += (other < 0) ? 1u : 0u;
                        continue;
                    }
                    const unsigned long long sought = ((unsigned long long)(unsigned int)leaf << 32u) | (unsigned int)other;
                    unsigned int low = 0u;
                    unsigned int high = tree->joined_count;
                    while (low < high)
                    {
                        const unsigned int middle = low + (high - low) / 2u;
                        const unsigned long long key = ((unsigned long long)tree->joined[2u * middle] << 32u)
                                                     | tree->joined[2u * middle + 1u];
                        if (key < sought)
                        {
                            low = middle + 1u;
                        }
                        else
                        {
                            high = middle;
                        }
                    }
                    if ((low < tree->joined_count) && (tree->joined[2u * low] == (unsigned int)leaf)
                     && (tree->joined[2u * low + 1u] == (unsigned int)other))
                    {
                        tree->contact_faces[low] += 1u;
                    }
                }
            }
        }
        for (unsigned int node = 0u; node < key.node_count; node += 1u)
        {
            const int *const place = &key.node_coordinates[(size_t)node * 4u];
            // Narrowing is safe: the time was tested nonnegative first.
            if ((place[0] < 0) || ((unsigned int)place[0] != frames[frame].time))
            {
                continue;
            }
            // Widening: coordinates of the answer key are nonnegative voxels inside the view.
            const size_t voxel = ((size_t)place[1] * buffers.height + (size_t)place[2]) * buffers.width
                               + (size_t)place[3];
            node_leaf[node] = leaf_of_peak(frames[frame].peaks, frames[frame].leaf_count, buffers.labels[1][voxel]);
        }
        clocks.ties += clock_microseconds() - mark;
        if ((frame > 0u) && (frames[frame].time == frames[frame - 1u].time + 1u))
        {
            good = relate_frames(&buffers, &frames[frame - 1u], &frames[frame], rules, &clocks);
        }
        unsigned int *const labels = buffers.labels[0];
        buffers.labels[0] = buffers.labels[1];
        buffers.labels[1] = labels;
        unsigned long long *const positive = buffers.positive[0];
        buffers.positive[0] = buffers.positive[1];
        buffers.positive[1] = positive;
        int *const leaf_at_peak = buffers.leaf_at_peak[0];
        buffers.leaf_at_peak[0] = buffers.leaf_at_peak[1];
        buffers.leaf_at_peak[1] = leaf_at_peak;
        unsigned int *const basin_start = buffers.basin_start[0];
        buffers.basin_start[0] = buffers.basin_start[1];
        buffers.basin_start[1] = basin_start;
        unsigned int *const basin_voxels = buffers.basin_voxels[0];
        buffers.basin_voxels[0] = buffers.basin_voxels[1];
        buffers.basin_voxels[1] = basin_voxels;
    }
    fclose(stack);
    // The null draws: each climbed frame's leaves climb again, from the same lag the view gave toward the next frame,
    // against frames far off in time, where no cell is the same cell. The climb is the same identity; only its input
    // is the null. Pended beside the observed pairs, they all run in the same ticks.
    int **null_scratch = NULL;
    unsigned int null_scratch_count = 0u;
    for (unsigned int frame = 0u; (good != 0) && (rules->null_draws != 0u) && (buffers.machine != NULL) && (frame < frame_count);
         frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        if (tree->forward_held == NULL)
        {
            continue;
        }
        tree->null_held = (unsigned int *)calloc(((size_t)tree->leaf_count + 1u) * rules->null_draws, sizeof(unsigned int));
        int **const grown = (int **)realloc(null_scratch, ((size_t)null_scratch_count + (4u * rules->null_draws)) * sizeof(int *));
        good = (tree->null_held != NULL) && (grown != NULL);
        null_scratch = (grown != NULL) ? grown : null_scratch;
        for (unsigned int draw = 0u; (good != 0) && (draw < rules->null_draws); draw += 1u)
        {
            // Half the series away and stepping on by one per draw, wrapping; never the frame, its neighbour, or
            // anything within two frames of it.
            const unsigned int other = (frame + (frame_count / 2u) + draw) % frame_count;
            const unsigned int apart = (other > frame) ? (other - frame) : (frame - other);
            if ((frame_count < 8u) || (apart <= 2u) || ((frame_count - apart) <= 2u))
            {
                continue;
            }
            const TreeFrame *const null_frame = &frames[other];
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = tree->time;
            pair.later = null_frame->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                pair.lag[axis] = tree->lag_to_next[axis];
            }
            pair.earlier_leaves = tree->leaf_count;
            pair.earlier_peaks = tree->peaks;
            pair.later_leaves = null_frame->leaf_count;
            pair.later_peaks = null_frame->peaks;
            pair.forward_lags = (int *)malloc(((size_t)tree->leaf_count + 1u) * 3u * sizeof(int));
            pair.forward = (int *)malloc(((size_t)tree->leaf_count + 1u) * sizeof(int));
            pair.backward_lags = (int *)malloc(((size_t)null_frame->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward = (int *)malloc(((size_t)null_frame->leaf_count + 1u) * sizeof(int));
            // Taken draws are packed from the start, so a skipped draw leaves no zero behind to be ranked.
            pair.forward_held = &tree->null_held[(size_t)tree->null_count * ((size_t)tree->leaf_count + 1u)];
            null_scratch[null_scratch_count] = pair.forward_lags;
            null_scratch[null_scratch_count + 1u] = pair.forward;
            null_scratch[null_scratch_count + 2u] = pair.backward_lags;
            null_scratch[null_scratch_count + 3u] = pair.backward;
            null_scratch_count += 4u;
            good = (pair.forward_lags != NULL) && (pair.forward != NULL) && (pair.backward_lags != NULL) && (pair.backward != NULL)
                && (climb_machine_pend(buffers.machine, &pair) != 0);
            tree->null_count += (good != 0) ? 1u : 0u;
        }
    }
    // The arms: the same climb fired from every frame at every gap beyond the next one, scattered out together
    // and settled in the same ticks. A cell that cannot be told from the neighbour it touches one frame on has
    // moved clear of it two or three frames on, so what the arms land in is evidence the next frame alone does
    // not hold. Each arm starts from the view's lag multiplied by its gap and climbs from there on its own.
    int **arm_scratch = NULL;
    unsigned int arm_scratch_count = 0u;
    for (unsigned int frame = 0u; (good != 0) && (rules->arms != 0u) && (buffers.machine != NULL)
         && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        tree->arm_forward = (int *)malloc(((size_t)tree->leaf_count + 1u) * rules->arms * sizeof(int));
        int **const grown = (int **)realloc(arm_scratch, ((size_t)arm_scratch_count + (3u * rules->arms))
                                            * sizeof(int *));
        good = (tree->arm_forward != NULL) && (grown != NULL);
        arm_scratch = (grown != NULL) ? grown : arm_scratch;
        for (size_t slot = 0u; (good != 0) && (slot < ((size_t)tree->leaf_count + 1u) * rules->arms); slot += 1u)
        {
            tree->arm_forward[slot] = CLIMB_MACHINE_NO_LEAF;
        }
        for (unsigned int arm = 0u; (good != 0) && (arm < rules->arms); arm += 1u)
        {
            // Arm one is the frame after the next, arm two the one after that, and so on out.
            const unsigned int gap = arm + 2u;
            if ((frame + gap) >= frame_count)
            {
                continue;
            }
            const TreeFrame *const far = &frames[frame + gap];
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = tree->time;
            pair.later = far->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                // Narrowing is safe: a lag of the view times a gap of the series stays a small step.
                pair.lag[axis] = (int)((long long)tree->lag_to_next[axis] * (long long)gap);
            }
            pair.earlier_leaves = tree->leaf_count;
            pair.earlier_peaks = tree->peaks;
            pair.later_leaves = far->leaf_count;
            pair.later_peaks = far->peaks;
            pair.forward_lags = (int *)malloc(((size_t)tree->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward_lags = (int *)malloc(((size_t)far->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward = (int *)malloc(((size_t)far->leaf_count + 1u) * sizeof(int));
            // Where this arm lands is kept; the way back is scratch the arm does not read.
            pair.forward = &tree->arm_forward[(size_t)arm * ((size_t)tree->leaf_count + 1u)];
            arm_scratch[arm_scratch_count] = pair.forward_lags;
            arm_scratch[arm_scratch_count + 1u] = pair.backward_lags;
            arm_scratch[arm_scratch_count + 2u] = pair.backward;
            arm_scratch_count += 3u;
            good = (pair.forward_lags != NULL) && (pair.backward_lags != NULL) && (pair.backward != NULL)
                && (climb_machine_pend(buffers.machine, &pair) != 0);
            tree->arm_count += (good != 0) ? 1u : 0u;
        }
    }
    // Every pair still pending climbs now, all at once, to its fixed point.
    const unsigned long long climbing = clock_microseconds();
    good = (good != 0) && ((buffers.machine == NULL) || (climb_machine_run(buffers.machine) != 0));
    clocks.climb += clock_microseconds() - climbing;
    for (unsigned int scratch = 0u; scratch < null_scratch_count; scratch += 1u)
    {
        free(null_scratch[scratch]);
    }
    free(null_scratch);
    for (unsigned int scratch = 0u; scratch < arm_scratch_count; scratch += 1u)
    {
        free(arm_scratch[scratch]);
    }
    free(arm_scratch);
    for (unsigned int frame = 0u; (good != 0) && (rules->climb == 3) && (frame < frame_count); frame += 1u)
    {
        // The machine's lags against the host reference's, leaf by leaf, both directions.
        const TreeFrame *const tree = &frames[frame];
        for (unsigned int leaf = 0u; (tree->check_forward_lag != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            if (memcmp(&tree->check_forward_lag[3u * leaf], &tree->forward_lag[3u * leaf], 3u * sizeof(int)) != 0)
            {
                fprintf(stderr, "    climb disagrees: earlier frame %u leaf %u\n", tree->time, leaf);
            }
        }
        for (unsigned int leaf = 0u; (tree->check_backward_lag != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            if (memcmp(&tree->check_backward_lag[3u * leaf], &tree->backward_lag[3u * leaf], 3u * sizeof(int)) != 0)
            {
                fprintf(stderr, "    climb disagrees: later frame %u leaf %u\n", tree->time, leaf);
            }
        }
    }
    const unsigned long long engines_done = clock_milliseconds();

    // Objects, frame by frame in order: merge-split reads the frame before's objects. Where the repair asks the
    // halves to agree about where they are going, a second pass reads that agreement as the next frame's objects,
    // which the first pass has by then given it.
    const unsigned int grouping_passes = (rules->agree != 0) ? 2u : 1u;
    for (unsigned int pass = 0u; (good != 0) && (pass < grouping_passes); pass += 1u)
    {
        for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
        {
            const TreeFrame *const previous = (frames[frame].backward != NULL) ? &frames[frame - 1u] : NULL;
            const TreeFrame *const next = ((pass != 0u) && ((frame + 1u) < frame_count)) ? &frames[frame + 1u] : NULL;
            good = group_objects(&frames[frame], previous, next, rules);
        }
    }
    for (unsigned int frame = 0u; (good != 0) && (frame + 1u < frame_count); frame += 1u)
    {
        if (frames[frame].forward != NULL)
        {
            const TreeFrame *const before = (frame > 0u) ? &frames[frame - 1u] : NULL;
            const TreeFrame *const after = ((frame + 2u) < frame_count) ? &frames[frame + 2u] : NULL;
            good = (rules->unbound != 0) ? link_objects_unbound(&frames[frame], &frames[frame + 1u], before, after,
                                                                rules)
                                         : link_objects(&frames[frame], &frames[frame + 1u], rules);
        }
    }

    NodeIndex index;
    memset(&index, 0, sizeof(index));
    index.frame_count = frame_count;
    index.frames = frames;
    index.node_offset = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    good = (good != 0) && (index.node_offset != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        index.node_offset[frame + 1u] = index.node_offset[frame] + frames[frame].object_count;
    }
    index.node_count = (good != 0) ? index.node_offset[frame_count] : 0u;
    index.node_frame = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    unsigned int *const parent = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    good = (good != 0) && (index.node_frame != NULL) && (parent != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        for (unsigned int node = index.node_offset[frame]; node < index.node_offset[frame + 1u]; node += 1u)
        {
            index.node_frame[node] = frame;
            parent[node] = node;
        }
    }

    // Branches read at the end of the series: two single continuations that meet were one object.
    unsigned int rejoined = 0u;
    unsigned int visited_room = 64u;
    unsigned int *visited = (unsigned int *)malloc((size_t)visited_room * 2u * sizeof(unsigned int));
    good = (good != 0) && (visited != NULL);
    for (unsigned int frame = 0u; (good != 0) && (rules->resolve != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start == NULL)
        {
            continue;
        }
        const unsigned int next_offset = index.node_offset[frame + 1u];
        for (unsigned int object = 0u; (good != 0) && (object < frames[frame].object_count); object += 1u)
        {
            const unsigned int *const children = &frames[frame].link_target[frames[frame].link_start[object]];
            const unsigned int child_count = frames[frame].link_start[object + 1u] - frames[frame].link_start[object];
            if (child_count < 2u)
            {
                continue;
            }
            for (unsigned int first_slot = 0u; (good != 0) && (first_slot < child_count); first_slot += 1u)
            {
                for (unsigned int second_slot = first_slot + 1u; (good != 0) && (second_slot < child_count);
                     second_slot += 1u)
                {
                    const unsigned int first = next_offset + children[first_slot];
                    const unsigned int second = next_offset + children[second_slot];
                    if (find_root(parent, first) == find_root(parent, second))
                    {
                        continue;
                    }
                    unsigned int left = first;
                    unsigned int right = second;
                    visited[0] = left;
                    visited[1] = right;
                    unsigned int steps = 1u;
                    while (left != right)
                    {
                        const unsigned int *left_next = NULL;
                        const unsigned int *right_next = NULL;
                        unsigned int left_count = 0u;
                        unsigned int right_count = 0u;
                        links_of_node(&index, left, &left_next, &left_count);
                        links_of_node(&index, right, &right_next, &right_count);
                        if ((left_count != 1u) || (right_count != 1u))
                        {
                            break;
                        }
                        left = index.node_offset[index.node_frame[left] + 1u] + left_next[0];
                        right = index.node_offset[index.node_frame[right] + 1u] + right_next[0];
                        if (steps == visited_room)
                        {
                            visited_room *= 2u;
                            unsigned int *const grown = (unsigned int *)realloc(visited, (size_t)visited_room * 2u
                                                                                * sizeof(unsigned int));
                            if (grown == NULL)
                            {
                                good = 0;
                                break;
                            }
                            visited = grown;
                        }
                        visited[2u * steps] = left;
                        visited[2u * steps + 1u] = right;
                        steps += 1u;
                    }
                    if ((good != 0) && (left == right))
                    {
                        rejoined += 1u;
                        for (unsigned int step = 0u; step + 1u < steps; step += 1u)
                        {
                            const unsigned int one = find_root(parent, visited[2u * step]);
                            const unsigned int other = find_root(parent, visited[2u * step + 1u]);
                            if (one != other)
                            {
                                parent[(one > other) ? one : other] = (one < other) ? one : other;
                            }
                        }
                    }
                }
            }
        }
    }
    free(visited);

    // Unified objects numbered by root within each frame, and the links between them.
    unsigned int *const unified_of = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    unsigned int *const rank_of_root = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    good = (good != 0) && (unified_of != NULL) && (rank_of_root != NULL);
    unsigned int unified_count = 0u;
    // The first unified id of each frame: the ids of one frame are contiguous, in root order.
    unsigned int *const unified_first = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    good = (good != 0) && (unified_first != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        unified_first[frame] = unified_count;
        for (unsigned int node = index.node_offset[frame]; node < index.node_offset[frame + 1u]; node += 1u)
        {
            if (find_root(parent, node) == node)
            {
                rank_of_root[node] = unified_count;
                unified_count += 1u;
            }
        }
    }
    if (good != 0)
    {
        unified_first[frame_count] = unified_count;
    }
    for (unsigned int node = 0u; (good != 0) && (node < index.node_count); node += 1u)
    {
        unified_of[node] = rank_of_root[find_root(parent, node)];
    }
    unsigned int link_total = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start != NULL)
        {
            link_total += frames[frame].link_start[frames[frame].object_count];
        }
    }
    unsigned long long *const unified_link = (unsigned long long *)malloc(((size_t)link_total + 1u)
                                                                         * sizeof(unsigned long long));
    good = (good != 0) && (unified_link != NULL);
    unsigned int unified_links = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start == NULL)
        {
            continue;
        }
        for (unsigned int object = 0u; object < frames[frame].object_count; object += 1u)
        {
            const unsigned int source = unified_of[index.node_offset[frame] + object];
            for (unsigned int link = frames[frame].link_start[object]; link < frames[frame].link_start[object + 1u];
                 link += 1u)
            {
                const unsigned int child = unified_of[index.node_offset[frame + 1u] + frames[frame].link_target[link]];
                unified_link[unified_links] = ((unsigned long long)source << 32u) | child;
                unified_links += 1u;
            }
        }
    }
    unified_links = (good != 0) ? sort_unique(unified_link, unified_links) : 0u;
    unsigned int *const unified_start = (unsigned int *)calloc((size_t)unified_count + 2u, sizeof(unsigned int));
    good = (good != 0) && (unified_start != NULL);
    for (unsigned int link = 0u; (good != 0) && (link < unified_links); link += 1u)
    {
        unified_start[(unsigned int)(unified_link[link] >> 32u) + 1u] += 1u;
    }
    for (unsigned int unified = 0u; (good != 0) && (unified < unified_count); unified += 1u)
    {
        unified_start[unified + 1u] += unified_start[unified];
    }

    // The score: each labelled edge against the unified links, as the reference tallies it.
    unsigned int *const successors = (unsigned int *)calloc((size_t)key.node_count + 1u, sizeof(unsigned int));
    signed char *const edge_status = (signed char *)malloc((size_t)key.edge_count + 1u);
    good = (good != 0) && (successors != NULL) && (edge_status != NULL);
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        edge_status[edge] = -1;
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        if (source >= 0L)
        {
            successors[(unsigned long)source] += 1u;
        }
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        const long target = node_slot_of(&key, key.edge_ends[2u * edge + 1u]);
        if ((source < 0L) || (target < 0L))
        {
            continue;
        }
        const int source_time = key.node_coordinates[(size_t)source * 4u];
        const int target_time = key.node_coordinates[(size_t)target * 4u];
        // Narrowing is safe: both times were tested nonnegative first.
        if ((source_time < 0) || (target_time < 0) || ((unsigned int)source_time >= stack_frames)
         || ((unsigned int)target_time >= stack_frames))
        {
            continue;
        }
        const int source_frame = tree_index_of_time[source_time];
        const int target_frame = tree_index_of_time[target_time];
        const int source_leaf = node_leaf[source];
        const int target_leaf = node_leaf[target];
        if ((source_leaf < 0) || (target_leaf < 0))
        {
            tally->missed += 1ULL;
            edge_status[edge] = 4;
            continue;
        }
        const unsigned int source_unified
            = unified_of[index.node_offset[source_frame] + frames[source_frame].object_of[source_leaf]];
        const unsigned int target_unified
            = unified_of[index.node_offset[target_frame] + frames[target_frame].object_of[target_leaf]];
        const unsigned int made = unified_start[source_unified + 1u] - unified_start[source_unified];
        if (made == 0u)
        {
            tally->unlinked += 1ULL;
            edge_status[edge] = 3;
            continue;
        }
        int holds_target = 0;
        for (unsigned int link = unified_start[source_unified]; link < unified_start[source_unified + 1u]; link += 1u)
        {
            if ((unsigned int)(unified_link[link] & 0xFFFFFFFFULL) == target_unified)
            {
                holds_target = 1;
            }
        }
        if ((holds_target != 0) && ((made == 1u) || (made == successors[source])))
        {
            tally->correct += 1ULL;
            edge_status[edge] = 0;
        }
        else if (holds_target != 0)
        {
            tally->branched += 1ULL;
            edge_status[edge] = 1;
        }
        else
        {
            tally->wrong += 1ULL;
            edge_status[edge] = 2;
        }
    }
    // One row per scored edge: the answer key's step, the group's motion (the view's lag), and the lag the cell
    // was carried by, so failure can be read against how far a cell's own motion departs from the group's.
    for (unsigned int edge = 0u; (good != 0) && (rules->edges != NULL) && (edge < key.edge_count); edge += 1u)
    {
        const int status = edge_status[edge];
        if ((status < 0) || (status == 4))
        {
            continue;
        }
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        const long target = node_slot_of(&key, key.edge_ends[2u * edge + 1u]);
        const int *const from = &key.node_coordinates[(size_t)source * 4u];
        const int *const to = &key.node_coordinates[(size_t)target * 4u];
        const TreeFrame *const tree = &frames[tree_index_of_time[from[0]]];
        // Narrowing is safe: an edge that is not missed has its source leaf.
        const unsigned int leaf = (unsigned int)node_leaf[source];
        const int *const carried = (tree->forward_lag != NULL) ? &tree->forward_lag[3u * leaf] : tree->lag_to_next;
        // The null tag: the observed coherence at the climbed lag, and how many null draws held at least as much.
        const unsigned int held = (tree->forward_held != NULL) ? tree->forward_held[leaf] : 0u;
        unsigned int null_at_least = 0u;
        unsigned int null_best = 0u;
        for (unsigned int draw = 0u; (tree->null_held != NULL) && (draw < tree->null_count); draw += 1u)
        {
            const unsigned int drawn = tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u)) + leaf];
            null_at_least += (drawn >= held) ? 1u : 0u;
            null_best = (drawn > null_best) ? drawn : null_best;
        }
        // Why an edge came out as it did, accumulated rather than guessed at: the later frame's leaf the answer
        // key's next node lies in, the leaf this cell's landing fell in, the voxels this cell shares with each of
        // them and with whichever it shares most, whether the key's leaf lands back on this cell, and whether the
        // two leaves are one object already.
        const TreeFrame *const next_tree = &frames[tree_index_of_time[to[0]]];
        const int truth_leaf = node_leaf[target];
        const int chosen_leaf = (tree->forward != NULL) ? tree->forward[leaf] : -1;
        const unsigned int pairs_first = (tree->triple_start != NULL) ? tree->triple_start[leaf] : 0u;
        const unsigned int pairs_past = (tree->triple_start != NULL) ? tree->triple_start[leaf + 1u] : 0u;
        unsigned int truth_shared = 0u;
        unsigned int chosen_shared = 0u;
        unsigned int best_shared = 0u;
        int best_leaf = -1;
        for (unsigned int pair = pairs_first; pair < pairs_past; pair += 1u)
        {
            // Narrowing is safe: a leaf index is far below 2^31.
            const int after = (int)tree->triple_after[pair];
            const unsigned int shared = tree->triple_shared[pair];
            truth_shared = (after == truth_leaf) ? shared : truth_shared;
            chosen_shared = (after == chosen_leaf) ? shared : chosen_shared;
            best_leaf = (shared > best_shared) ? after : best_leaf;
            best_shared = (shared > best_shared) ? shared : best_shared;
        }
        const int truth_back = ((truth_leaf >= 0) && (next_tree->backward != NULL)) ? next_tree->backward[truth_leaf] : -1;
        const unsigned int truth_mutual = (unsigned int)((truth_back >= 0)
                                                         && (tree->object_of[truth_back] == tree->object_of[leaf]));
        const unsigned int one_object = (unsigned int)((truth_leaf >= 0) && (chosen_leaf >= 0)
                                                       && (next_tree->object_of[truth_leaf]
                                                           == next_tree->object_of[chosen_leaf]));
        // The links themselves, at both heights: what this cell's object linked to in the next frame, and what
        // the unified object it belongs to linked to, each beside whether the key's object is among them.
        const unsigned int own_object = tree->object_of[leaf];
        const unsigned int truth_object = (truth_leaf >= 0) ? next_tree->object_of[truth_leaf] : 0xFFFFFFFFu;
        const unsigned int object_links = (tree->link_start != NULL)
                                        ? (tree->link_start[own_object + 1u] - tree->link_start[own_object]) : 0u;
        unsigned int object_links_truth = 0u;
        for (unsigned int link = 0u; (tree->link_start != NULL) && (link < object_links); link += 1u)
        {
            object_links_truth += (unsigned int)(tree->link_target[tree->link_start[own_object] + link] == truth_object);
        }
        // The weighing as the linker saw it: what the whole object shares with the key's object, and with the
        // object it did link to, summed over the object's member leaves exactly as the pick sums them.
        const unsigned int linked_object = ((tree->link_start != NULL) && (object_links != 0u))
                                         ? tree->link_target[tree->link_start[own_object]] : 0xFFFFFFFFu;
        unsigned long long truth_weight = 0ULL;
        unsigned long long linked_weight = 0ULL;
        const unsigned int members = tree->member_start[own_object + 1u] - tree->member_start[own_object];
        for (unsigned int member = tree->member_start[own_object]; member < tree->member_start[own_object + 1u];
             member += 1u)
        {
            const unsigned int other = tree->members[member];
            const unsigned int other_first = (tree->triple_start != NULL) ? tree->triple_start[other] : 0u;
            const unsigned int other_past = (tree->triple_start != NULL) ? tree->triple_start[other + 1u] : 0u;
            for (unsigned int pair = other_first; pair < other_past; pair += 1u)
            {
                const unsigned int after_object = next_tree->object_of[tree->triple_after[pair]];
                truth_weight += (after_object == truth_object) ? tree->triple_shared[pair] : 0u;
                linked_weight += (after_object == linked_object) ? tree->triple_shared[pair] : 0u;
            }
        }
        const unsigned int own_unified = unified_of[index.node_offset[tree_index_of_time[from[0]]] + own_object];
        const unsigned int truth_unified = (truth_leaf >= 0)
                                         ? unified_of[index.node_offset[tree_index_of_time[to[0]]] + truth_object]
                                         : 0xFFFFFFFFu;
        const unsigned int unified_links = unified_start[own_unified + 1u] - unified_start[own_unified];
        unsigned int unified_holds_truth = 0u;
        for (unsigned int link = unified_start[own_unified]; link < unified_start[own_unified + 1u]; link += 1u)
        {
            unified_holds_truth += (unsigned int)((unsigned int)(unified_link[link] & 0xFFFFFFFFULL) == truth_unified);
        }
        fprintf(rules->edges, "%s\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t", sample, from[0],
                EDGE_STATUS_NAMES[status], to[1] - from[1], to[2] - from[2], to[3] - from[3], tree->lag_to_next[0],
                tree->lag_to_next[1], tree->lag_to_next[2], carried[0], carried[1], carried[2], tree->sizes[leaf],
                (tree->forward != NULL) ? 1u : 0u, held, tree->null_count, null_at_least, null_best);
        // Every draw's coherence in draw order, so the curve can be read at any prefix of the draws.
        for (unsigned int draw = 0u; (tree->null_held != NULL) && (draw < tree->null_count); draw += 1u)
        {
            fprintf(rules->edges, "%s%u", (draw == 0u) ? "" : ",",
                    tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u)) + leaf]);
        }
        // Every candidate this cell's object weighed, taken or refused, written whole beside the edge. The
        // bounds are taken before the walk, since a run that kept no pool has none to read.
        const int kept_pool = (rules->pool != NULL) && (tree->pool_start != NULL);
        const unsigned int pool_first = (kept_pool != 0) ? tree->pool_start[own_object] : 0u;
        const unsigned int pool_past = (kept_pool != 0) ? tree->pool_start[own_object + 1u] : 0u;
        for (unsigned int slot = pool_first; slot < pool_past; slot += 1u)
        {
            const unsigned int candidate = tree->pool_target[slot];
            unsigned int candidate_voxels = 0u;
            for (unsigned int member = next_tree->member_start[candidate];
                 member < next_tree->member_start[candidate + 1u]; member += 1u)
            {
                candidate_voxels += next_tree->sizes[next_tree->members[member]];
            }
            unsigned int linked = 0u;
            for (unsigned int link = tree->link_start[own_object]; link < tree->link_start[own_object + 1u];
                 link += 1u)
            {
                linked += (unsigned int)(tree->link_target[link] == candidate);
            }
            fprintf(rules->pool, "%s\t%d\t%s\t%u\t%u\t%u\t%u\t%u\t%llu\t%llu\t%u\t%u\t%llu\t%u\n", sample, from[0],
                    EDGE_STATUS_NAMES[status], own_object, candidate, (unsigned int)(candidate == truth_object),
                    linked, tree->pool_weight[slot], tree->pool_cost[slot] >> LINK_MAGNITUDE_BITS,
                    tree->pool_cost[slot] & LINK_MAGNITUDE_MASK, candidate_voxels,
                    next_tree->member_start[candidate + 1u] - next_tree->member_start[candidate],
                    (unsigned long long)tree->sizes[leaf], members);
        }
        // The first arm: the object two frames on that this cell landed in, beside the object two frames on
        // that the key's own target links to. Where the two agree and the link taken does not, the arm holds
        // what the next frame alone could not tell.
        const TreeFrame *const beyond = ((tree_index_of_time[from[0]] + 2u) < frame_count)
                                      ? &frames[tree_index_of_time[from[0]] + 2u] : NULL;
        const int arm_leaf = ((tree->arm_forward != NULL) && (tree->arm_count != 0u))
                           ? tree->arm_forward[leaf] : CLIMB_MACHINE_NO_LEAF;
        const unsigned int arm_object = ((arm_leaf >= 0) && (beyond != NULL))
                                      ? beyond->object_of[(unsigned int)arm_leaf] : 0xFFFFFFFFu;
        unsigned int truth_onward = 0xFFFFFFFFu;
        for (unsigned int link = 0u; (truth_leaf >= 0) && (next_tree->link_start != NULL) && (beyond != NULL)
             && (link < (next_tree->link_start[truth_object + 1u] - next_tree->link_start[truth_object])); link += 1u)
        {
            truth_onward = next_tree->link_target[next_tree->link_start[truth_object] + link];
        }
        unsigned int linked_onward = 0xFFFFFFFFu;
        for (unsigned int link = 0u; (linked_object != 0xFFFFFFFFu) && (next_tree->link_start != NULL)
             && (beyond != NULL)
             && (link < (next_tree->link_start[linked_object + 1u] - next_tree->link_start[linked_object]));
             link += 1u)
        {
            linked_onward = next_tree->link_target[next_tree->link_start[linked_object] + link];
        }
        fprintf(rules->edges, "\t%u\t%u\t%u", arm_object, truth_onward, linked_onward);
        fprintf(rules->edges, "\t%d\t%d\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%llu\t%llu\n", truth_leaf,
                chosen_leaf, best_leaf, truth_shared, chosen_shared, best_shared, truth_mutual, one_object,
                object_links, object_links_truth, unified_links, unified_holds_truth, members, truth_weight,
                linked_weight);
    }
    if (good && (object || (rules->coherence != NULL) || (rules->vis_index != NULL) || (rules->export_directory != NULL)))
    {
        CoherenceInputs inputs;
        memset(&inputs, 0, sizeof(inputs));
        inputs.sample = sample;
        inputs.stack_path = path;
        inputs.key = &key;
        inputs.frames = frames;
        inputs.frame_count = frame_count;
        inputs.node_offset = index.node_offset;
        inputs.unified_of = unified_of;
        inputs.unified_count = unified_count;
        inputs.node_leaf = node_leaf;
        inputs.tree_index_of_time = tree_index_of_time;
        inputs.stack_frames = stack_frames;
        inputs.edge_status = edge_status;
        inputs.unified_start = unified_start;
        inputs.unified_link = unified_link;
        inputs.vis_directory = rules->vis_directory;
        inputs.vis_index = rules->vis_index;
        inputs.unified_first = unified_first;
        if ((rules->coherence != NULL) || (rules->vis_index != NULL))
        {
            good = read_coherence(&buffers, &inputs, rules->coherence);
        }
        if ((good != 0) && (rules->export_directory != NULL))
        {
            good = export_room(&buffers, &inputs, rules->export_directory);
        }
        if (good && object)
        {
            // Narrowing is safe: a sample's runs are far below 2^32.
            object_first_run[frame_count] = (unsigned int)object_run_count;
            good = export_object(&buffers, &inputs, object_runs, object_first_run, object_leaf_runs, rules);
        }
    }
    free(object_cut);
    free(object_runs);
    free(object_leaf_runs);
    free(object_first_run);
    free(object_leaf_code);
    const unsigned long long finished = clock_milliseconds();
    // What the repair made of the basins: objects against leaves, and the largest object of the series. A cell is
    // a basin or a few, so an object holding hundreds is the repair running away through cells that touch.
    unsigned int object_total = 0u;
    unsigned int leaf_total = 0u;
    unsigned int largest_object = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        object_total += tree->object_count;
        leaf_total += tree->leaf_count;
        for (unsigned int object = 0u; (tree->member_start != NULL) && (object < tree->object_count); object += 1u)
        {
            const unsigned int members = tree->member_start[object + 1u] - tree->member_start[object];
            largest_object = (members > largest_object) ? members : largest_object;
        }
    }
    if (good != 0)
    {
        const unsigned long long scored = tally->correct + tally->branched + tally->wrong + tally->unlinked
                                        + tally->missed;
        printf("  %-24.24s %-6llu %llu/%llu/%llu/%llu/%llu   %u frames, %u objects of %u leaves, largest %u,"
               " rejoined %u, engines %llu ms"
               " (read %llu, basins %llu, store %llu, ties %llu, motion %llu, landing %llu, overlap %llu,"
               " climb %llu), tree %llu ms\n",
               sample, scored, tally->correct, tally->branched, tally->wrong, tally->unlinked, tally->missed,
               frame_count, object_total, leaf_total, largest_object,
               rejoined, engines_done - started, clocks.read / 1000ULL, clocks.basins / 1000ULL,
               clocks.store / 1000ULL, clocks.ties / 1000ULL, clocks.motion / 1000ULL, clocks.landing / 1000ULL,
               clocks.overlap / 1000ULL, clocks.climb / 1000ULL, finished - engines_done);
        fflush(stdout);
    }

    free(edge_status);
    free(unified_first);
    free(successors);
    free(unified_start);
    free(unified_link);
    free(rank_of_root);
    free(unified_of);
    free(parent);
    free(index.node_frame);
    free(index.node_offset);
    for (unsigned int frame = 0u; (frames != NULL) && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        free(tree->peaks);
        free(tree->sizes);
        free(tree->sums);
        free(tree->moments);
        free(tree->exposed);
        free(tree->contact_faces);
        free(tree->joined);
        free(tree->forward);
        free(tree->forward_lag);
        free(tree->backward_lag);
        free(tree->check_forward_lag);
        free(tree->check_backward_lag);
        free(tree->forward_held);
        free(tree->null_held);
        free(tree->arm_forward);
        free(tree->backward);
        free(tree->triple_start);
        free(tree->triple_after);
        free(tree->triple_shared);
        free(tree->triple_still);
        free(tree->pool_start);
        free(tree->pool_target);
        free(tree->pool_weight);
        free(tree->pool_cost);
        free(tree->object_of);
        free(tree->member_start);
        free(tree->members);
        free(tree->link_start);
        free(tree->link_target);
    }
    free(frames);
    free(node_leaf);
    free(tree_index_of_time);
    free(reached);
    free(buffers.volume);
    free(buffers.peak_indices);
    free(buffers.sizes);
    free(buffers.sums);
    free(buffers.peak_limbs);
    free(buffers.adjacency);
    free(buffers.joined);
    free(buffers.overlap_before);
    free(buffers.overlap_after);
    free(buffers.overlap_shared);
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        free(buffers.labels[slot]);
        free(buffers.positive[slot]);
        free(buffers.leaf_at_peak[slot]);
        free(buffers.basin_start[slot]);
        free(buffers.basin_voxels[slot]);
    }
    climb_machine_close(buffers.machine);
    release_answer_key(&key);
    return good;
}

/** @brief The .cfg scheme's name, written into every .cfg and checked on every read. */
static const char CFG_SCHEME[] = "cell_tracking.cfg";

/** @brief The .cfg scheme's version. */
static const unsigned long long CFG_VERSION = 1ULL;

/** @brief The climb by .cfg name, in the order of TreeRules climb. */
static const char *const CLIMB_NAMES[4] = {"off", "machine", "host", "check"};

/** @brief The outputs by .cfg name, in the order of RunInputs outputs. */
static const char *const OUTPUT_NAMES[6] = {"edges", "coherence", "export", "object", "vis", "pool"};

/** @brief The boolean rules by .cfg name, beside the rule each sets. */
typedef struct
{
    const char *name;        /**< The .cfg name. */
    int TreeRules::*rule;    /**< The rule it sets. */
} CfgSwitch;

/** @brief Every rule a .cfg sets true or false. */
/** @brief Rules a .cfg sets true or false. */
#define CFG_SWITCH_COUNT 15u

static const CfgSwitch CFG_SWITCHES[CFG_SWITCH_COUNT] = {
    {"pick", &TreeRules::pick},
    {"share", &TreeRules::share},
    {"agree", &TreeRules::agree},
    {"unbound", &TreeRules::unbound},
    {"cast", &TreeRules::cast},
    {"parallax", &TreeRules::parallax},
    {"arc", &TreeRules::arc},
    {"settle", &TreeRules::settle},
    {"merge_split", &TreeRules::merge_split},
    {"merge_target", &TreeRules::merge_target},
    {"forward_only", &TreeRules::forward_only},
    {"keep_view", &TreeRules::keep_view},
    {"resolve", &TreeRules::resolve},
    {"sticky", &TreeRules::sticky},
    {"motion_check", &TreeRules::motion_check},
};

/** @brief A run's inputs and output paths, from the command line and any .cfg, in the order given. */
typedef struct
{
    char *stacks;          /**< The stack directory, or NULL [OWNS]. */
    char **samples;        /**< The samples [OWNS]. */
    unsigned int count;    /**< Samples. */
    unsigned int first;    /**< Where no sample is named: the first this many samples with an answer key, by name. */
    char *species;         /**< The specimen's species, carried for the viewer, or NULL [OWNS]. */
    unsigned long long voxel_pm[3]; /**< A voxel's size z y x in picometers, carried for the viewer; 0 where unknown. */
    unsigned long long membrane_pm; /**< The membrane's thickness in picometers, carried for the viewer; 0 where unknown. */
    char *outputs[6];      /**< Each output's path, or NULL, in OUTPUT_NAMES order [OWNS]. */
    char *view;            /**< The .cfg's view section, verbatim, or NULL [OWNS]. */
} RunInputs;

/** @brief A text that grows as it is written. */
typedef struct
{
    char *bytes;   /**< The text, NUL terminated [OWNS]. */
    size_t length; /**< Its bytes. */
    size_t room;   /**< Bytes held. */
    bool good;     /**< False once a grow failed. */
} CfgText;

static void cfg_append(CfgText *text, const char *piece, size_t size)
{
    const size_t wanted = text->length + size + 1u;
    // Where the room is enough the product is zero, whatever the wrapped difference.
    const size_t room = text->room + ((size_t)(wanted > text->room) * ((2u * wanted) - text->room));
    char *const grown = (char *)realloc(text->bytes, room);
    text->good = text->good && grown;
    text->bytes = grown ? grown : text->bytes;
    text->room = grown ? room : text->room;
    if (text->good)
    {
        memcpy(&text->bytes[text->length], piece, size);
        text->length += size;
        text->bytes[text->length] = '\0';
    }
}

static void cfg_append_text(CfgText *text, const char *piece)
{
    cfg_append(text, piece, strlen(piece));
}

static void cfg_append_quoted(CfgText *text, const char *piece)
{
    if (!piece)
    {
        cfg_append_text(text, "null");
        return;
    }
    cfg_append_text(text, "\"");
    for (const char *at = piece; *at; at += 1u)
    {
        const bool plain = (*at != '"') && (*at != '\\');
        cfg_append(text, "\\", (size_t)!plain);
        cfg_append(text, at, 1u);
    }
    cfg_append_text(text, "\"");
}

static char *cfg_copy(const char *piece)
{
    const size_t size = strlen(piece) + 1u;
    char *const copy = (char *)malloc(size);
    return copy ? (char *)memcpy(copy, piece, size) : NULL;
}

/**
 * @brief Opens an output a path names, closing the one it replaces; the edges and coherence tables get their
 *        header rows and the vis arm its page.
 *
 * @param[in,out] rules  The rules [BORROWS].
 * @param[in,out] inputs The run, which keeps the path [BORROWS].
 * @param[in]     output The output, in OUTPUT_NAMES order.
 * @param[in]     path   The path, or NULL for none [BORROWS].
 * @return               True where the output is open, or is none.
 */
static bool open_output(TreeRules *rules, RunInputs *inputs, unsigned int output, const char *path)
{
    free(inputs->outputs[output]);
    inputs->outputs[output] = path ? cfg_copy(path) : NULL;
    const char *const kept = inputs->outputs[output];
    FILE **const files[6] = {&rules->edges, &rules->coherence, NULL, NULL, &rules->vis_index, &rules->pool};
    if (files[output] && *files[output])
    {
        fclose(*files[output]);
        *files[output] = NULL;
    }
    rules->export_directory = (output == 2u) ? kept : rules->export_directory;
    rules->object_directory = (output == 3u) ? kept : rules->object_directory;
    rules->object = (output == 3u) ? !!kept : rules->object;
    rules->vis_directory = (output == 4u) ? kept : rules->vis_directory;
    if (!kept || !files[output])
    {
        return !path || kept;
    }
    char index_path[1024];
    snprintf(index_path, sizeof(index_path), "%s/index.html", kept);
    FILE *const file = fopen((output == 4u) ? index_path : kept, "w");
    *files[output] = file;
    if (!file)
    {
        fprintf(stderr, "  could not open %s\n", (output == 4u) ? index_path : kept);
        return false;
    }
    if (output == 0u)
    {
        fprintf(file, "sample\ttime\tstatus\ttrue_z\ttrue_y\ttrue_x\tview_z\tview_y\tview_x\tcarried_z\tcarried_y"
                      "\tcarried_x\tbasin_voxels\tfollows\theld\tnull_draws\tnull_at_least\tnull_best\tnull_held"
                      "\tarm_object\ttruth_onward\tlinked_onward"
                      "\ttruth_leaf\tchosen_leaf\tbest_leaf\ttruth_shared\tchosen_shared\tbest_shared\ttruth_mutual"
                      "\tone_object\tobject_links\tobject_links_truth\tunified_links\tunified_holds_truth\tmembers"
                      "\ttruth_weight\tlinked_weight\n");
    }
    if (output == 5u)
    {
        // One row per candidate the cell's object weighed, whether it was taken or refused, so a question about
        // the refusals is asked of what was actually there and not of a rule guessed at afterwards.
        fprintf(file, "sample\ttime\tstatus\tobject\tcandidate\tis_truth\tis_linked\tmeeting\tstep\tmagnitude"
                      "\tcandidate_voxels\tcandidate_leaves\tobject_voxels\tobject_leaves\n");
    }
    if (output == 1u)
    {
        fprintf(file, "sample\ttime\tstatus\tsize_A\tleaves_A\tsize_B\town_z\town_y\town_x\tview_z\tview_y"
                      "\tview_x\ttrue_z\ttrue_y\ttrue_x\tagree_own\tagree_view\tagree_true\tland_B"
                      "\tland_max\tland_sumsq\tland_objects\n");
    }
    if (output == 4u)
    {
        fprintf(file,
                "<!doctype html><meta charset=utf-8><title>What the engine sees</title><style>body{background:#111;"
                "color:#ddd;font:14px sans-serif;margin:16px}figure{margin:0 0 28px}img{image-rendering:pixelated;"
                "max-width:100%%}figcaption{max-width:1100px;margin-top:6px}b{color:#fff}</style><h1>Failing edges, "
                "as the engine holds them</h1><p>Left: frame t at the source node's z. Right: frame t+1 at the "
                "target node's z. Both crops are centred on the source node. Positive voxels are tinted by object; "
                "object boundaries in the object's colour. Green outline: the source cell (left) and the true "
                "target (right). Red outline: an object the tree linked the cell to. Yellow: linked and true. Green "
                "plus: answer key nodes. White plus: the cell's peak. Magenta plus: where the tree carried that peak. "
                "White cells: other answer key nodes on the slice.</p>\n");
    }
    return true;
}

/**
 * @brief Refuses a .cfg at a token, naming the file, the line and column, and what was wrong.
 *
 * @param[in] path   The .cfg [BORROWS].
 * @param[in] text   Its text [BORROWS].
 * @param[in] at     The byte refused.
 * @param[in] reason What was wrong [BORROWS].
 * @return           False, always.
 */
static bool cfg_refuse(const char *path, const char *text, size_t at, const char *reason)
{
    size_t line = 1u;
    size_t column = 1u;
    for (size_t byte = 0u; byte < at; byte += 1u)
    {
        const bool newline = (text[byte] == '\n');
        line += (size_t)newline;
        column = newline ? 1u : (column + 1u);
    }
    fprintf(stderr, "  %s:%zu:%zu: %s\n", path, line, column, reason);
    return false;
}

/**
 * @brief Reads a .cfg and applies it over the rules and the run, section by section. Every name is checked: a
 *        name the scheme does not have is refused, never skipped, so a misspelt rule cannot run as its default.
 *
 * @param[in]     path   The .cfg [BORROWS].
 * @param[in,out] rules  The rules [BORROWS].
 * @param[in,out] inputs The run [BORROWS].
 * @return               True where the whole .cfg applied.
 */
static bool apply_cfg(const char *path, TreeRules *rules, RunInputs *inputs)
{
    FILE *const file = fopen(path, "rb");
    if (!file)
    {
        fprintf(stderr, "  could not open %s\n", path);
        return false;
    }
    fseek(file, 0L, SEEK_END);
    const long size = ftell(file);
    fseek(file, 0L, SEEK_SET);
    // Widening: a .cfg's size is small and nonnegative once ftell succeeds.
    const size_t length = (size_t)((size > 0L) ? size : 0L);
    char *const text = (char *)malloc(length + 1u);
    // A token is at least one byte and all but the last are followed by a separator.
    const unsigned int room = (unsigned int)(length / 2u) + 4u;
    CfgJsonToken *const tokens = (CfgJsonToken *)malloc((size_t)room * sizeof(CfgJsonToken));
    bool good = text && tokens && (fread(text, 1u, length, file) == length);
    fclose(file);
    CfgJsonParse parse;
    memset(&parse, 0, sizeof(parse));
    good = good && cfg_json_parse(text, length, tokens, room, &parse);
    if (text && tokens && parse.reason)
    {
        fprintf(stderr, "  %s:%zu:%zu: %s\n", path, parse.line, parse.column, parse.reason);
    }
    good = good && ((tokens[0].kind == CFG_JSON_OBJECT) || cfg_refuse(path, text, 0u, "a .cfg is one object"));
    unsigned int key = 1u;
    unsigned long long number = 0ULL;
    char word[1024];
    for (unsigned int member = 0u; good && (member < tokens[0].count); member += 1u)
    {
        const unsigned int value = key + 1u;
        const CfgJsonToken *const token = &tokens[value];
        if (cfg_json_names(text, &tokens[key], "scheme"))
        {
            good = (cfg_json_string(text, token, word, sizeof(word)) && (strcmp(word, CFG_SCHEME) == 0))
                || cfg_refuse(path, text, token->start, "scheme is not cell_tracking.cfg");
        }
        else if (cfg_json_names(text, &tokens[key], "version"))
        {
            good = (cfg_json_unsigned(text, token, &number) && (number == CFG_VERSION))
                || cfg_refuse(path, text, token->start, "this tracker reads .cfg version 1");
        }
        else if (cfg_json_names(text, &tokens[key], "track") && (token->kind == CFG_JSON_OBJECT))
        {
            unsigned int rule = value + 1u;
            for (unsigned int inner = 0u; good && (inner < token->count); inner += 1u)
            {
                const CfgJsonToken *const setting = &tokens[rule + 1u];
                bool known = false;
                for (unsigned int slot = 0u; slot < CFG_SWITCH_COUNT; slot += 1u)
                {
                    const bool named = cfg_json_names(text, &tokens[rule], CFG_SWITCHES[slot].name);
                    const bool boolean = (setting->kind == CFG_JSON_TRUE) || (setting->kind == CFG_JSON_FALSE);
                    good = good && (!named || boolean || cfg_refuse(path, text, setting->start, "a rule takes true or false"));
                    rules->*CFG_SWITCHES[slot].rule = (named && boolean) ? (setting->kind == CFG_JSON_TRUE)
                                                                         : rules->*CFG_SWITCHES[slot].rule;
                    known = known || named;
                }
                if (cfg_json_names(text, &tokens[rule], "climb"))
                {
                    const bool read = cfg_json_string(text, setting, word, sizeof(word));
                    int mode = -1;
                    for (int slot = 0; read && (slot < 4); slot += 1)
                    {
                        mode = (strcmp(word, CLIMB_NAMES[slot]) == 0) ? slot : mode;
                    }
                    good = (mode >= 0) || cfg_refuse(path, text, setting->start, "climb is off, machine, host or check");
                    rules->climb = (mode >= 0) ? mode : rules->climb;
                    known = true;
                }
                if (cfg_json_names(text, &tokens[rule], "null_draws"))
                {
                    good = (cfg_json_unsigned(text, setting, &number) && (number < 4096ULL))
                        || cfg_refuse(path, text, setting->start, "null_draws is a count below 4096");
                    // Narrowing is safe: the count was bounded just above.
                    rules->null_draws = good ? (unsigned int)number : rules->null_draws;
                    known = true;
                }
                if (cfg_json_names(text, &tokens[rule], "arms"))
                {
                    good = (cfg_json_unsigned(text, setting, &number) && (number < 64ULL))
                        || cfg_refuse(path, text, setting->start, "arms is a count below 64");
                    // Narrowing is safe: the count was bounded just above.
                    rules->arms = good ? (unsigned int)number : rules->arms;
                    known = true;
                }
                good = good && (known || cfg_refuse(path, text, tokens[rule].start, "track has no such rule"));
                rule = tokens[rule + 1u].past;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "input") && (token->kind == CFG_JSON_OBJECT))
        {
            const unsigned int stacks = cfg_json_member(text, tokens, value, "stacks");
            const unsigned int samples = cfg_json_member(text, tokens, value, "samples");
            const unsigned int first = cfg_json_member(text, tokens, value, "first");
            const unsigned int species = cfg_json_member(text, tokens, value, "species");
            const unsigned int voxel = cfg_json_member(text, tokens, value, "voxel_pm");
            const unsigned int membrane = cfg_json_member(text, tokens, value, "membrane_pm");
            const unsigned int named = (unsigned int)!!stacks + (unsigned int)!!samples + (unsigned int)!!first
                                     + (unsigned int)!!species + (unsigned int)!!voxel + (unsigned int)!!membrane;
            good = (named == token->count)
                || cfg_refuse(path, text, token->start, "input takes stacks, samples, first, species, voxel_pm and membrane_pm");
            if (good && species)
            {
                good = cfg_json_string(text, &tokens[species], word, sizeof(word))
                    || cfg_refuse(path, text, tokens[species].start, "species is a name");
                free(inputs->species);
                inputs->species = good ? cfg_copy(word) : NULL;
            }
            if (good && voxel)
            {
                good = ((tokens[voxel].kind == CFG_JSON_ARRAY) && (tokens[voxel].count == 3u))
                    || cfg_refuse(path, text, tokens[voxel].start, "voxel_pm is three integers, z y x, in picometers");
                for (unsigned int axis = 0u; good && (axis < 3u); axis += 1u)
                {
                    good = cfg_json_unsigned(text, &tokens[voxel + 1u + axis], &inputs->voxel_pm[axis])
                        || cfg_refuse(path, text, tokens[voxel + 1u + axis].start, "a voxel size is a whole number of picometers");
                }
            }
            if (good && membrane)
            {
                good = cfg_json_unsigned(text, &tokens[membrane], &inputs->membrane_pm)
                    || cfg_refuse(path, text, tokens[membrane].start, "membrane_pm is a whole number of picometers");
            }
            if (good && stacks)
            {
                good = cfg_json_string(text, &tokens[stacks], word, sizeof(word))
                    || cfg_refuse(path, text, tokens[stacks].start, "stacks is a path");
                free(inputs->stacks);
                inputs->stacks = good ? cfg_copy(word) : NULL;
            }
            if (good && samples)
            {
                good = (tokens[samples].kind == CFG_JSON_ARRAY) || cfg_refuse(path, text, tokens[samples].start, "samples is a list");
                for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
                {
                    free(inputs->samples[slot]);
                }
                free(inputs->samples);
                inputs->count = 0u;
                inputs->samples = (char **)calloc((size_t)tokens[samples].count + 1u, sizeof(char *));
                for (unsigned int slot = 0u; good && (slot < tokens[samples].count); slot += 1u)
                {
                    const unsigned int element = samples + 1u + slot;
                    good = cfg_json_string(text, &tokens[element], word, sizeof(word))
                        || cfg_refuse(path, text, tokens[element].start, "a sample is a name");
                    inputs->samples[slot] = good ? cfg_copy(word) : NULL;
                    inputs->count += (unsigned int)good;
                }
            }
            if (good && first)
            {
                good = (cfg_json_unsigned(text, &tokens[first], &number) && (number < (1ULL << 20u)))
                    || cfg_refuse(path, text, tokens[first].start, "first is a count");
                // Narrowing is safe: the count was bounded just above.
                inputs->first = (unsigned int)number;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "output") && (token->kind == CFG_JSON_OBJECT))
        {
            unsigned int output = value + 1u;
            for (unsigned int inner = 0u; good && (inner < token->count); inner += 1u)
            {
                const CfgJsonToken *const setting = &tokens[output + 1u];
                int slot = -1;
                for (int name = 0; name < 6; name += 1)
                {
                    slot = cfg_json_names(text, &tokens[output], OUTPUT_NAMES[name]) ? name : slot;
                }
                const bool none = (setting->kind == CFG_JSON_NULL);
                good = ((slot >= 0) || cfg_refuse(path, text, tokens[output].start, "output has no such output"))
                    && (none || cfg_json_string(text, setting, word, sizeof(word))
                        || cfg_refuse(path, text, setting->start, "an output is a path or null"))
                    // Narrowing is safe: the slot was found.
                    && open_output(rules, inputs, (unsigned int)slot, none ? NULL : word);
                output = tokens[output + 1u].past;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "view") && (token->kind == CFG_JSON_OBJECT))
        {
            // The page's section: the tracker carries it into every object untouched, so the object opens as asked.
            free(inputs->view);
            inputs->view = (char *)malloc(token->end - token->start + 1u);
            good = inputs->view;
            if (good)
            {
                memcpy(inputs->view, &text[token->start], token->end - token->start);
                inputs->view[token->end - token->start] = '\0';
            }
        }
        else
        {
            good = cfg_refuse(path, text, tokens[key].start, "a .cfg has scheme, version, track, input, output and view, and "
                                                             "track, input, output and view are objects");
        }
        key = tokens[value].past;
    }
    // The flags' implications hold for a .cfg too: a sticky climb or a null draw is a climb.
    rules->climb += (int)((rules->climb == 0) && (rules->sticky || rules->null_draws)) * 1;
    free(text);
    free(tokens);
    return good;
}

/**
 * @brief Orders two names by their bytes, for qsort.
 *
 * @param[in] left  A pointer to the first name [BORROWS].
 * @param[in] right A pointer to the second name [BORROWS].
 * @return          Negative, zero or positive as the first sorts before, with or after the second.
 */
static int order_names(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

/**
 * @brief Names the first samples with an answer key in the stack directory, in byte order of their names.
 *
 * @param[in,out] inputs The run, whose samples are replaced [BORROWS].
 * @return               True where the directory was read.
 */
static bool first_samples(RunInputs *inputs)
{
    char **names = NULL;
    size_t count = 0u;
    size_t room = 0u;
    bool good = true;
#ifdef _WIN32
    char pattern[1024];
    snprintf(pattern, sizeof(pattern), "%s/*.truth", inputs->stacks);
    struct __finddata64_t found;
    const intptr_t search = _findfirst64(pattern, &found);
    for (int more = (search != -1) ? 0 : -1; good && (more == 0); more = _findnext64(search, &found))
    {
        const char *const name = found.name;
#else
    DIR *const search = opendir(inputs->stacks);
    for (struct dirent *entry = search ? readdir(search) : NULL; good && entry; entry = readdir(search))
    {
        const char *const name = entry->d_name;
#endif
        const size_t size = strlen(name);
        const bool truth = (size > 6u) && (strcmp(&name[size - 6u], ".truth") == 0);
        room += (size_t)(truth && (count == room)) * (room + 64u);
        char **const grown = (char **)realloc(names, (room + 1u) * sizeof(char *));
        good = grown;
        names = grown ? grown : names;
        names[count] = (good && truth) ? cfg_copy(name) : NULL;
        names[count] ? (void)(names[count][size - 6u] = '\0') : (void)0;
        count += (size_t)(good && truth);
    }
#ifdef _WIN32
    (search != -1) ? (void)_findclose(search) : (void)0;
#else
    search ? (void)closedir(search) : (void)0;
#endif
    qsort(names, count, sizeof(char *), order_names);
    const size_t kept = (count < inputs->first) ? count : inputs->first;
    for (size_t slot = kept; slot < count; slot += 1u)
    {
        free(names[slot]);
    }
    for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
    {
        free(inputs->samples[slot]);
    }
    free(inputs->samples);
    inputs->samples = names;
    // Narrowing is safe: a directory's samples are far below 2^32.
    inputs->count = (unsigned int)kept;
    return good && kept;
}

/**
 * @brief Writes the .cfg a run is taking, every rule and every path spelled out, so it runs again as it ran.
 *
 * @param[in]  rules  The rules [BORROWS].
 * @param[in]  inputs The run [BORROWS].
 * @param[out] out    The text [OWNS].
 * @return            True where the text is whole.
 */
static bool write_cfg(const TreeRules *rules, const RunInputs *inputs, CfgText *out)
{
    memset(out, 0, sizeof(*out));
    out->good = true;
    cfg_append_text(out, "{\n  \"scheme\": \"cell_tracking.cfg\",\n  \"version\": 1,\n  \"track\": {\n");
    for (unsigned int slot = 0u; slot < CFG_SWITCH_COUNT; slot += 1u)
    {
        char line[128];
        snprintf(line, sizeof(line), "    \"%s\": %s,\n", CFG_SWITCHES[slot].name, (rules->*CFG_SWITCHES[slot].rule) ? "true" : "false");
        cfg_append_text(out, line);
    }
    char line[128];
    // Narrowing is safe: the climb is one of the four modes.
    snprintf(line, sizeof(line), "    \"climb\": \"%s\",\n    \"null_draws\": %u\n  },\n", CLIMB_NAMES[(unsigned int)rules->climb & 3u],
             rules->null_draws);
    cfg_append_text(out, line);
    cfg_append_text(out, "  \"input\": {\n    \"stacks\": ");
    cfg_append_quoted(out, inputs->stacks);
    cfg_append_text(out, ",\n    \"samples\": [");
    for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
    {
        cfg_append_text(out, slot ? ", " : "");
        cfg_append_quoted(out, inputs->samples[slot]);
    }
    snprintf(line, sizeof(line), "],\n    \"first\": %u,\n    \"species\": ", inputs->first);
    cfg_append_text(out, line);
    cfg_append_quoted(out, inputs->species);
    snprintf(line, sizeof(line), ",\n    \"voxel_pm\": [%llu, %llu, %llu],\n    \"membrane_pm\": %llu\n  },\n  \"output\": {\n",
             inputs->voxel_pm[0], inputs->voxel_pm[1], inputs->voxel_pm[2], inputs->membrane_pm);
    cfg_append_text(out, line);
    for (unsigned int slot = 0u; slot < 6u; slot += 1u)
    {
        snprintf(line, sizeof(line), "    \"%s\": ", OUTPUT_NAMES[slot]);
        cfg_append_text(out, line);
        cfg_append_quoted(out, inputs->outputs[slot]);
        cfg_append_text(out, (slot < 5u) ? ",\n" : "\n  },\n");
    }
    cfg_append_text(out, "  \"view\": ");
    cfg_append_text(out, inputs->view ? inputs->view : "{}");
    cfg_append_text(out, "\n}\n");
    return out->good;
}

int main(int argc, char **argv)
{
    TreeRules rules;
    memset(&rules, 0, sizeof(rules));
    rules.resolve = 1;
    RunInputs inputs;
    memset(&inputs, 0, sizeof(inputs));
    const char *cfg_out = NULL;
    int argument = 1;
    while ((argument < argc) && (strncmp(argv[argument], "--", 2u) == 0))
    {
        const char *const flag = argv[argument];
        if (strcmp(flag, "--pick") == 0)
        {
            rules.pick = 1;
        }
        else if (strcmp(flag, "--share") == 0)
        {
            rules.share = 1;
        }
        else if (strcmp(flag, "--agree") == 0)
        {
            rules.agree = 1;
        }
        else if (strcmp(flag, "--unbound") == 0)
        {
            rules.unbound = 1;
        }
        else if (strcmp(flag, "--cast") == 0)
        {
            rules.cast = 1;
        }
        else if (strcmp(flag, "--parallax") == 0)
        {
            rules.parallax = 1;
        }
        else if (strcmp(flag, "--arc") == 0)
        {
            rules.arc = 1;
        }
        else if (strcmp(flag, "--settle") == 0)
        {
            rules.settle = 1;
        }
        else if (strcmp(flag, "--merge-split") == 0)
        {
            rules.merge_split = 1;
        }
        else if (strcmp(flag, "--merge-target") == 0)
        {
            rules.merge_target = 1;
        }
        else if (strcmp(flag, "--forward-only") == 0)
        {
            rules.forward_only = 1;
        }
        else if (strcmp(flag, "--keep-view") == 0)
        {
            rules.keep_view = 1;
        }
        else if (strcmp(flag, "--no-resolve") == 0)
        {
            rules.resolve = 0;
        }
        else if (strcmp(flag, "--climb") == 0)
        {
            rules.climb = 1;
        }
        else if ((strcmp(flag, "--cfg") == 0) && (argument + 1 < argc))
        {
            // Applied where it stands: flags before it are overridden by it, flags after it override it.
            argument += 1;
            if (!apply_cfg(argv[argument], &rules, &inputs))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--cfg-out") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            cfg_out = argv[argument];
        }
        else if ((strcmp(flag, "--edges") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 0u, argv[argument]))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--pool") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 5u, argv[argument]))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--export") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            open_output(&rules, &inputs, 2u, argv[argument]);
        }
        else if ((strcmp(flag, "--object") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            open_output(&rules, &inputs, 3u, argv[argument]);
        }
        else if ((strcmp(flag, "--vis") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 4u, argv[argument]))
            {
                return 2;
            }
        }
        else if (strcmp(flag, "--sticky") == 0)
        {
            rules.sticky = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--motion-check") == 0)
        {
            rules.motion_check = 1;
        }
        else if ((strcmp(flag, "--null") == 0) && ((argument + 1) < argc))
        {
            argument += 1;
            // Read digit by digit: glibc 2.38 redirects strtoul to a C23 symbol older systems do not carry.
            unsigned int draws = 0u;
            for (const char *digit = argv[argument]; (*digit >= '0') && (*digit <= '9') && (draws < 4096u); digit += 1u)
            {
                // Narrowing is safe: a digit is 0 to 9.
                draws = (draws * 10u) + (unsigned int)(*digit - '0');
            }
            rules.null_draws = draws;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if ((strcmp(flag, "--arms") == 0) && ((argument + 1) < argc))
        {
            argument += 1;
            // Read digit by digit, as the draws are read, for the same reason.
            unsigned int arms = 0u;
            for (const char *digit = argv[argument]; (*digit >= '0') && (*digit <= '9') && (arms < 64u); digit += 1u)
            {
                // Narrowing is safe: a digit is 0 to 9.
                arms = (arms * 10u) + (unsigned int)(*digit - '0');
            }
            rules.arms = arms;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--climb-host") == 0)
        {
            rules.climb = 2;
        }
        else if (strcmp(flag, "--climb-check") == 0)
        {
            rules.climb = 3;
        }
        else if ((strcmp(flag, "--coherence") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 1u, argv[argument]))
            {
                return 2;
            }
        }
        else
        {
            fprintf(stderr, "  unknown flag %s\n", flag);
            return 2;
        }
        argument += 1;
    }
    // Positional words name the stack directory and then the samples, over whatever a .cfg named.
    if (argument < argc)
    {
        free(inputs.stacks);
        inputs.stacks = cfg_copy(argv[argument]);
        argument += 1;
    }
    if (argument < argc)
    {
        for (unsigned int slot = 0u; slot < inputs.count; slot += 1u)
        {
            free(inputs.samples[slot]);
        }
        free(inputs.samples);
        // Narrowing is safe: the argument count is an int.
        inputs.count = (unsigned int)(argc - argument);
        inputs.samples = (char **)calloc((size_t)inputs.count + 1u, sizeof(char *));
        for (unsigned int slot = 0u; inputs.samples && (slot < inputs.count); slot += 1u)
        {
            inputs.samples[slot] = cfg_copy(argv[argument + (int)slot]);
        }
    }
    if (inputs.stacks && !inputs.count && inputs.first)
    {
        first_samples(&inputs);
    }
    if (!inputs.stacks || !inputs.count)
    {
        fprintf(stderr, "usage: track_driver [--cfg run.cfg] [--cfg-out effective.cfg] [--pick] [--merge-split]"
                        " [--merge-target] [--forward-only] [--keep-view] [--no-resolve] [--climb] [--edges path]"
                        " [--object directory] [<directory> [<sample> ...]]\n"
                        "  a .cfg names the stack directory and samples in its input section; positional words override it\n");
        return 2;
    }
    CfgText effective;
    if (!write_cfg(&rules, &inputs, &effective))
    {
        fprintf(stderr, "  could not write the effective .cfg\n");
        return 2;
    }
    rules.cfg_text = effective.bytes;
    rules.cfg_length = effective.length;
    FILE *const cfg_file = cfg_out ? fopen(cfg_out, "wb") : NULL;
    if (cfg_out && (!cfg_file || (fwrite(effective.bytes, 1u, effective.length, cfg_file) != effective.length)))
    {
        fprintf(stderr, "  could not write %s\n", cfg_out);
        return 2;
    }
    cfg_file ? (void)fclose(cfg_file) : (void)0;
    const char *const directory = inputs.stacks;
    // Build the device context once, before the first frame.
    (void)cudaFree(NULL);

    printf("  rules:%s%s%s%s%s%s%s%s%s%s\n", (rules.pick != 0) ? " pick" : "", (rules.share != 0) ? " share" : "",
           (rules.agree != 0) ? " agree" : "", (rules.unbound != 0) ? " unbound" : "",
           (rules.merge_split != 0) ? " merge-split" : "",
           (rules.merge_target != 0) ? " merge-target" : "", (rules.forward_only != 0) ? " forward-only" : "",
           (rules.keep_view != 0) ? " keep-view" : "", (rules.resolve != 0) ? " resolve" : "",
           (rules.climb != 0) ? " climb" : "");
    printf("  %-24s %-6s %s\n", "sample", "edges", "correct/branched/wrong/no link/missed");
    EdgeTally pooled;
    memset(&pooled, 0, sizeof(pooled));
    const unsigned long long started = clock_milliseconds();
    int failures = 0;
    for (unsigned int sample = 0u; sample < inputs.count; sample += 1u)
    {
        EdgeTally tally;
        if (score_sample(directory, inputs.samples[sample], &rules, &tally) == 0)
        {
            fprintf(stderr, "  %s failed\n", inputs.samples[sample]);
            failures += 1;
            continue;
        }
        pooled.correct += tally.correct;
        pooled.branched += tally.branched;
        pooled.wrong += tally.wrong;
        pooled.unlinked += tally.unlinked;
        pooled.missed += tally.missed;
    }
    const unsigned long long total = pooled.correct + pooled.branched + pooled.wrong + pooled.unlinked + pooled.missed;
    printf("\n  POOLED over %llu ground truth edges:\n", total);
    if (total > 0ULL)
    {
        const char *const names[5] = {"correct link", "target among branches", "wrong link", "no link made",
                                      "endpoint undetected"};
        const unsigned long long values[5] = {pooled.correct, pooled.branched, pooled.wrong, pooled.unlinked,
                                              pooled.missed};
        for (unsigned int row = 0u; row < 5u; row += 1u)
        {
            unsigned long long whole = 0ULL;
            unsigned long long tenth = 0ULL;
            percent_of(values[row], total, &whole, &tenth);
            printf("    %-22s %5llu   %llu.%llu%%\n", names[row], values[row], whole, tenth);
        }
    }
    printf("\n  %llu ms\n", clock_milliseconds() - started);
    if (rules.coherence != NULL)
    {
        fclose(rules.coherence);
    }
    if (rules.vis_index != NULL)
    {
        fclose(rules.vis_index);
    }
    if (rules.edges != NULL)
    {
        fclose(rules.edges);
    }
    for (unsigned int slot = 0u; slot < inputs.count; slot += 1u)
    {
        free(inputs.samples[slot]);
    }
    for (unsigned int slot = 0u; slot < 5u; slot += 1u)
    {
        free(inputs.outputs[slot]);
    }
    free(inputs.samples);
    free(inputs.stacks);
    free(inputs.species);
    free(inputs.view);
    free(effective.bytes);
    return (failures == 0) ? 0 : 1;
}
