/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_raster.h
 * @brief Rasterizes the object under examination directly from engine state, on host or device.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE OBJECT UNDER EXAMINATION IS THE FIELD AND WHAT THE ENGINE SAW OF IT. A search over a corpus
 * produces one outcome per alignment: some probe rejected it, or every probe agreed and the full
 * compare decided it. That outcome sequence is already an image. One value per alignment, laid out
 * in corpus order, is a direct render of where the engine pruned and where it had to look harder.
 *
 * DIRECT, meaning the raster is built from the same state the search runs on, with no export step
 * and no second representation in between. A viewer that reads a dumped file is describing what was
 * written down; this describes what the engine did.
 *
 * WHAT A PIXEL CARRIES. The level at which an alignment died. Zero means the first probe rejected
 * it, one means the second did, and so on. An alignment that passed every probe carries the probe
 * count, and one that also matched under the full compare carries ANCHOR_RASTER_MATCH. Brighter is
 * later, so a bright pixel is an alignment the probe set could not cheaply refute.
 *
 * HOST AND DEVICE PRODUCE THE SAME BYTES. That is the contract, and it is gradeable rather than
 * aspirational: the raster is integer valued throughout, so agreement is exact and a difference of
 * one in one pixel is a defect. This is the same contract exact_arm.h states for the arms, kept for
 * the same reason.
 *
 * @note Downsampling takes the MINIMUM death level over the alignments mapping to a pixel. Minimum
 *       is associative and commutative, so a sequential host reduction and a parallel device one
 *       reach the same value without ordering agreeing between them. A rule like "first alignment
 *       wins" would make the device answer depend on scheduling.
 * @note No float anywhere. Positions map through integer division and values are counts.
 * @note Writes Netpbm P5, which needs no library and no encoder.
 */
#ifndef ANCHOR_RASTER_H
#define ANCHOR_RASTER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
/* The device rasterizer is compiled as C++ by nvcc and calls these, which are compiled as C. */
extern "C" {
#endif

/** @brief Value a pixel carries when its alignment passed every probe and matched. */
#define ANCHOR_RASTER_MATCH 255u

/** @brief Value a pixel carries when no alignment mapped to it. */
#define ANCHOR_RASTER_EMPTY 0u

/**
 * @brief How an alignment index becomes a pixel position.
 *
 * A transform is a choice about the object's shape on the page, and it changes what a reader can
 * see without changing anything measured. Run length shows in one, locality shows in another, and
 * periodicity that a row layout smears across a scanline stands up as a column stripe.
 *
 * @note Every transform here is a bijection on the cell index computed in integer arithmetic, so
 *       the device reproduces it exactly and no transform can drop or duplicate an alignment.
 */
typedef enum
{
    ANCHOR_LAYOUT_ROWS = 0,       /**< Row major. Corpus order runs left to right, top to bottom. */
    ANCHOR_LAYOUT_SERPENTINE = 1, /**< Row major with odd rows reversed, so neighbors stay adjacent
                                   *   across a row boundary. */
    ANCHOR_LAYOUT_COLUMNS = 2,    /**< Column major. A period near the width stands up as a stripe. */
    ANCHOR_LAYOUT_DIAGONAL = 3    /**< Diagonal striping, which breaks up both axis alignments. */
} AnchorRasterLayout;

/**
 * @brief What quantity a pixel carries.
 *
 * @note Every channel is an integer read off engine state. None is computed in floating point and
 *       none is normalized against the image, so a pixel means the same thing in two rasters taken
 *       at different sizes.
 */
typedef enum
{
    ANCHOR_CHANNEL_DEATH_LEVEL = 0, /**< Probe index that rejected the alignment. Brighter is later. */
    ANCHOR_CHANNEL_SURVIVED = 1,    /**< Binary. Bright where every probe agreed, dark otherwise. */
    ANCHOR_CHANNEL_RARITY = 2,      /**< Rarity rank of the corpus byte at the alignment, from the
                                     *   census the engine steers by. */
    ANCHOR_CHANNEL_BYTE = 3,        /**< The corpus byte itself, which renders the object raw. */
    ANCHOR_CHANNEL_PROVEN = 4       /**< Two valued. Proven to hold no occurrence, or undetermined. */
} AnchorRasterChannel;

/** @brief Pixel value for a cell proven to contain no occurrence. */
#define ANCHOR_RASTER_PROVEN 200u

/** @brief Pixel value for a cell holding at least one alignment the probes could not refute. */
#define ANCHOR_RASTER_UNDETERMINED 60u

/**
 * @brief How pixels resolve when several alignments map to one cell.
 *
 * @warning Both rules here are associative and commutative, which is what lets the device reduce in
 *          scheduler order and still agree with the host. A rule selecting by arrival, such as
 *          first or last writer, would make the device answer depend on scheduling and must not be
 *          added to this enum.
 */
typedef enum
{
    ANCHOR_REDUCE_MIN = 0, /**< Darkest wins. Earliest rejection dominates. */
    ANCHOR_REDUCE_MAX = 1  /**< Brightest wins. Surviving alignments dominate. */
} AnchorRasterReduce;

/**
 * @brief The whole input configuration for a render.
 *
 * @note One structure drives both arms. A caller changing a field changes the host and the device
 *       render together, and the grader compares them under whatever configuration it was given
 *       rather than under a fixed one.
 */
typedef struct
{
    size_t width;                 /**< Pixels across. Non-zero. */
    size_t height;                /**< Pixel rows. Non-zero. */
    AnchorRasterLayout layout;    /**< How an alignment index becomes a pixel position. */
    AnchorRasterChannel channel;  /**< What quantity a pixel carries. */
    AnchorRasterReduce reduce;    /**< How collisions resolve. */
    uint8_t gain;                 /**< Multiplier on a death level before it reaches the ramp. Zero
                                   *   is treated as one, so a zeroed configuration still renders. */
} AnchorRasterConfig;

/** @brief Number of layouts, for a caller sweeping every one. */
#define ANCHOR_RASTER_LAYOUTS 4u

/**
 * @brief Number of channels, for a caller sweeping every one.
 *
 * THE PROOF CHANNEL IS DIFFERENT IN KIND FROM THE OTHER FOUR AND THE DIFFERENCE IS WORTH STATING.
 * A probe set is a sound filter: it never loses a true occurrence, and it does admit alignments that
 * are not one. So the negative direction is certain and the positive is not. A cell where no
 * alignment survived contains no occurrence, and that is a proof rather than a summary.
 *
 * Three properties follow and each one is load bearing. It reduces as a conjunction, a cell being
 * proven only when every alignment under it was refuted, and conjunction is associative and
 * commutative, so it rides ANCHOR_REDUCE_MIN and needs no new reduction rule. It is monotone under
 * refinement, since adding a probe only removes survivors, so a render never retracts a claim it
 * made earlier. And it inherits the anytime property of the planner: stop the descent anywhere,
 * render, and every proven pixel is still proven.
 *
 * That last one separates this channel from every other. A death level taken from a half-built plan
 * is a fact about the plan. A proof taken from a half-built plan is a fact about the OBJECT.
 *
 * @warning Brightness is not presence anywhere in this renderer, and here least of all.
 *          ANCHOR_RASTER_PROVEN is brighter than ANCHOR_RASTER_UNDETERMINED and means the opposite
 *          of an occurrence. ANCHOR_RASTER_MATCH is the only value entitled to assert one.
 */
#define ANCHOR_RASTER_CHANNELS 5u

/**
 * @brief One probe as the rasterizer needs it, matching AnchorProbe in anchor_sift.h.
 *
 * @note Declared here rather than including the engine header so the device translation unit
 *       compiles without pulling in the limb library it does not use. The two layouts are identical
 *       and anchor_raster.c asserts that at compile time.
 * @note Declared above the volume surface below, which names this type in a signature. A structure
 *       cannot name a type the compiler has not seen, and this header has been reordered once
 *       already for the same reason.
 */
typedef struct
{
    size_t origin; /**< First position in the needle this probe reads. */
    size_t step;   /**< Distance between successive positions. */
    size_t length; /**< Positions read. */
} AnchorRasterProbe;

/**
 * @brief How an alignment index becomes a voxel position.
 *
 * SEPARATE FROM AnchorRasterLayout AND NOT AN EXTENSION OF IT. A raster layout is a bijection onto
 * a width by height sheet and a volume layout is a bijection onto a width by height by depth block.
 * Widening the raster enum would change ANCHOR_RASTER_LAYOUTS, which every caller sweeping the
 * raster uses as its bound, and would hand those callers layouts needing a depth they do not carry.
 *
 * @note The channel, the reduce rule and the gain are unchanged and are not duplicated here. Each
 *       reads one alignment and returns one value, so none of them knows how many dimensions the
 *       destination has. Only the index to position map changes between a sheet and a block, which
 *       is the same statement the engine makes about its own index set needing no order and no
 *       dimension.
 * @note Every transform here is a bijection computed in integer arithmetic, so a device
 *       implementation reproduces it exactly and no transform can drop or duplicate an alignment.
 */
typedef enum
{
    ANCHOR_VOLUME_SLABS = 0,   /**< Slab major. Fills a sheet, then the next sheet behind it. The
                                *   three dimensional reading of ANCHOR_LAYOUT_ROWS. */
    ANCHOR_VOLUME_BOUSTRO = 1, /**< Slab major with every other row and every other slab reversed,
                                *   so consecutive alignments stay adjacent across both boundaries. */
    ANCHOR_VOLUME_MORTON = 2,  /**< Morton order, interleaving the bits of x, y and z. Locality is
                                *   preserved on all three axes at once, which is what a linear
                                *   index set needs to read as a solid rather than as stacked
                                *   sheets. Requires the extents to be powers of two; a caller
                                *   giving others gets a refusal rather than a silent remap. */
    ANCHOR_VOLUME_HELIX = 3    /**< Slab major with each slab's rows shifted by its depth index, so
                                *   a feature at a fixed corpus offset winds through the block
                                *   instead of stacking. A shear and not a rotation: a true helix
                                *   needs trigonometry, this renderer is integer throughout so the
                                *   host and a device agree exactly, and a shear is the bijection
                                *   that gives the same reading without leaving the integers. */
} AnchorVolumeLayout;

/** @brief Number of volume layouts, for a caller sweeping every one. */
#define ANCHOR_VOLUME_LAYOUTS 4u

/**
 * @brief The whole input configuration for a volume render.
 *
 * @note Carries the raster's channel, reduce and gain by reference to the same enums rather than by
 *       copy. A channel means one thing in this tree and a second spelling of it is a future
 *       disagreement.
 * @warning `depth` of zero renders nothing and is refused. A flat render is the raster's job and
 *          this entry does not quietly become one.
 */
typedef struct
{
    size_t width;                /**< Voxels across. Non-zero. */
    size_t height;               /**< Voxel rows. Non-zero. */
    size_t depth;                /**< Voxel slabs. Non-zero, and one is refused rather than flattened. */
    AnchorVolumeLayout layout;   /**< How an alignment index becomes a voxel position. */
    AnchorRasterChannel channel; /**< What quantity a voxel carries. Same set as the raster. */
    AnchorRasterReduce reduce;   /**< How collisions resolve. Same set as the raster. */
    uint8_t gain;                /**< Multiplier on a death level. Zero is treated as one. */
} AnchorVolumeConfig;

/**
 * @brief Voxel index an alignment lands on under a configuration's layout.
 *
 * @param[in] config    Render configuration [BORROWS].
 * @param[in] alignment Alignment index.
 * @return              Index into a width*height*depth block, or the block size where the
 *                      configuration is unusable, which a caller treats as "not placed".
 */
size_t anchor_volume_cell_for(const AnchorVolumeConfig *config, size_t alignment);

/**
 * @brief Renders the object under examination into a volume, on the host.
 *
 * @param[out] voxels     width*height*depth bytes, written whole [BORROWS].
 * @param[in]  config     Render configuration [BORROWS].
 * @param[in]  corpus     Bytes under examination [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     Bytes being searched for [BORROWS].
 * @param[in]  needle_len How many.
 * @param[in]  probes     Probes in evaluation order [BORROWS].
 * @param[in]  probe_count How many probes.
 * @param[in]  census     Rarity source for ANCHOR_CHANNEL_RARITY, or NULL [BORROWS].
 * @return                1 where the volume was written, 0 where the configuration was refused.
 *
 * @note HOST ONLY, AND THE DEVICE VOLUME IS NOT WIRED. anchor_raster_render prefers the device for a
 *       sheet. There is no device volume kernel, and this entry does not pretend otherwise by
 *       falling back silently: a caller wanting to know asks anchor_volume_device_available, which
 *       answers 0 on every build today. A stub reporting itself present is the defect this tree has
 *       spent a day removing.
 */
int anchor_volume_render_host(uint8_t *voxels, const AnchorVolumeConfig *config,
                              const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                              size_t needle_len, const AnchorRasterProbe *probes,
                              size_t probe_count, const void *census);

/**
 * @brief Whether a device volume renderer exists on this build.
 *
 * @return 0 on every build today. Declared so a caller can ask instead of assuming, and so the
 *         answer has one place to change when a kernel is written.
 */
int anchor_volume_device_available(void);

/**
 * @brief Writes a volume as a raw byte block beside a text header naming its extents.
 *
 * @param[in] path   Destination for the bytes [BORROWS].
 * @param[in] voxels width*height*depth bytes [BORROWS].
 * @param[in] config Render configuration, read for the extents [BORROWS].
 * @return           1 on success, 0 where the file could not be written.
 *
 * @note Netpbm has no volume format, so this writes the block raw and states its shape in a sidecar
 *       rather than inventing a container. A generated file says it is generated and names its
 *       generator, which the sidecar does.
 */
int anchor_volume_write_raw(const char *path, const uint8_t *voxels,
                            const AnchorVolumeConfig *config);

/** @brief Name of a volume layout, for a caller printing a row. Never null. */
const char *anchor_volume_layout_name(AnchorVolumeLayout layout);

/**
 * @brief Rasterizes the object under examination on the host.
 *
 * @param[out] pixels     Raster, `width` bytes per row, `height` rows [BORROWS].
 * @param[in]  width      Pixels across. Must be non-zero.
 * @param[in]  height     Pixel rows. Must be non-zero.
 * @param[in]  corpus     Bytes under examination [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     Bytes being searched for [BORROWS].
 * @param[in]  needle_len How many.
 * @param[in]  probes     Probe set in evaluation order [BORROWS].
 * @param[in]  probe_count How many probes.
 * @return                1 on success, 0 where an argument is rejected.
 *
 * @note Every alignment is examined. The raster is a rendering of the search and not a sample of
 *       it, so a pixel is never guessed from its neighbors.
 * @note Rejects and writes nothing where a pointer is null, where `width` or `height` is zero,
 *       where `needle_len` is zero, or where `needle_len` exceeds `corpus_len`.
 */
int anchor_raster_host(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                       size_t corpus_len, const uint8_t *needle, size_t needle_len,
                       const AnchorRasterProbe *probes, size_t probe_count);

/**
 * @brief Pixel index an alignment lands on under a configuration's layout.
 *
 * @param[in] config     Render configuration [BORROWS].
 * @param[in] at         Alignment index.
 * @param[in] alignments How many alignments the object has.
 * @return               Cell index inside `width * height`.
 * @note Exposed because the device rasterizer calls the same function, which is what keeps one
 *       transform rather than two that agree until somebody edits one.
 */
size_t anchor_raster_cell(const AnchorRasterConfig *config, size_t at, size_t alignments);

/**
 * @brief Value one alignment contributes under a configuration's channel.
 *
 * @param[in] occurrences Symbol counts over the object, 256 entries [BORROWS].
 * @param[in] total       Bytes counted into `occurrences`.
 * @return                The pixel value before reduction.
 * @note Shared with the device for the same reason anchor_raster_cell is.
 */
uint8_t anchor_raster_sample(const AnchorRasterConfig *config, const uint8_t *corpus,
                             const uint8_t *needle, size_t needle_len,
                             const AnchorRasterProbe *probes, size_t probe_count, size_t at,
                             const uint64_t *occurrences, uint64_t total);

/** @brief Name of a layout, for a caller printing a row. Never null. */
const char *anchor_raster_layout_name(AnchorRasterLayout layout);

/** @brief Name of a channel, for a caller printing a row. Never null. */
const char *anchor_raster_channel_name(AnchorRasterChannel channel);

/**
 * @brief Writes a raster as Netpbm P5 grayscale.
 *
 * @param[in] path   Where to write [BORROWS].
 * @param[in] pixels Raster [BORROWS].
 * @param[in] width  Pixels across.
 * @param[in] height Pixel rows.
 * @return           1 on success, 0 where the file could not be written.
 *
 * @note P5 because the format is a short text header and then the bytes. Nothing is encoded, so a
 *       reader comparing two rasters is comparing the same bytes the rasterizer produced.
 */
int anchor_raster_write_pgm(const char *path, const uint8_t *pixels, size_t width, size_t height);

/**
 * @brief Renders on whichever arm this machine has, preferring the device.
 *
 * @param[out] pixels     Raster, `config->width` bytes per row [BORROWS].
 * @param[in]  config     Render configuration [BORROWS].
 * @param[in]  corpus     Bytes under examination [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     Bytes being searched for [BORROWS].
 * @param[in]  needle_len How many.
 * @param[in]  probes     Probe set in evaluation order [BORROWS].
 * @param[in]  probe_count How many probes.
 * @return                1 on success, 0 where both arms refused.
 *
 * THE ENTRY A CALLER SHOULD USE. A machine carrying a device should render on it without the caller
 * asking, and the two arms produce the same bytes, so choosing between them is a performance
 * decision and never a correctness one. This asks the device first and falls back to the host.
 *
 * @note Falls back rather than failing where the device refuses, so a render always happens if
 *       either arm can do it.
 * @note anchor_raster_host and anchor_raster_device stay public because a grader has to be able to
 *       call one specific arm and compare. A caller that does not care should not have to.
 */
int anchor_raster_render(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count);

/**
 * @brief Whether a usable CUDA device is present for the device rasterizer.
 *
 * @return 1 where a device is present, 0 otherwise.
 * @note Always returns 0 in a build compiled without the device rasterizer, so a caller written
 *       against both arms links and runs either way.
 */
int anchor_raster_device_available(void);

/**
 * @brief Rasterizes the object under examination on the device.
 *
 * @param[out] pixels     Raster, `width` bytes per row, `height` rows [BORROWS].
 * @param[in]  width      Pixels across. Must be non-zero.
 * @param[in]  height     Pixel rows. Must be non-zero.
 * @param[in]  corpus     Bytes under examination [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     Bytes being searched for [BORROWS].
 * @param[in]  needle_len How many.
 * @param[in]  probes     Probe set in evaluation order [BORROWS].
 * @param[in]  probe_count How many probes.
 * @return                1 on success, 0 where no device is present or an argument is rejected.
 *
 * @note Produces the same bytes anchor_raster_host produces for the same arguments. A difference is
 *       a defect in one of them, and bench_raster grades exactly that.
 * @note One thread per alignment, reducing into the raster with atomicMin. The minimum rule is what
 *       lets that reduction run in any order and still agree with the host.
 */
int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config, const uint8_t *corpus,
                         size_t corpus_len, const uint8_t *needle, size_t needle_len,
                         const AnchorRasterProbe *probes, size_t probe_count);

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_RASTER_H */
