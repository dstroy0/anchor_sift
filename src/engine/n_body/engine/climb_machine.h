/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file climb_machine.h
 * @brief A frame store on the device and a climb that runs itself over every pending pair of frames at once.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * Each frame is stored once, as its sign words and its basins as runs, a run being the voxels of one leaf's
 * basin that lie next to each other along one row. That is the whole frame: no labelled volume is kept, so
 * every frame of a series is held at once. A pair of stored frames is pended with the
 * view's lag between them. Running the machine climbs every leaf of every pending pair, forward against the
 * later frame and backward against the earlier, all in the same ticks.
 *
 * A tick scores every climbing leaf at its lag and the 26 neighbouring lags, truthy or falsy per voxel (true
 * where the voxel lands inside the view on its own sign), and moves each leaf to its most coherent neighbour
 * where one is strictly more coherent, the shorter weighted lag first among equals, then the first in z y x
 * order. A run lands on one row of the other frame, so a run's true voxels at a candidate are counted a word
 * at a time: its sign bits beside the sign bits it lands on, differing bits set by exclusive or, and the true
 * count the run's length inside the view less their population count.
 *
 * A leaf that does not move has reached its fixed point and stays there; ticking it again changes nothing.
 * So the machine is never told to stop between ticks and never waits on the host to choose a step: the host
 * feeds ticks and watches, and reads the lags once a whole block of ticks moved nothing.
 *
 * The signs a stored frame keeps, and the labels of the two frames still in the ring, are also what the
 * overlap engine reads, through climb_machine_positive and climb_machine_labels, so a frame is uploaded once
 * for every device stage.
 *
 * NO FLOATING POINT VALUE IS FORMED.
 */
#ifndef CLIMB_MACHINE_H
#define CLIMB_MACHINE_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief A landing outside the view, or a label that is no leaf's peak. */
#define CLIMB_MACHINE_NO_LEAF (-1)

/** @brief The view the machine stores frames of. */
typedef struct
{
    unsigned int depth;          /**< Extent along z. */
    unsigned int height;         /**< Extent along y. */
    unsigned int width;          /**< Extent along x. */
    unsigned int peak_room;      /**< Most leaves one frame can have. */
    unsigned int frames;         /**< Frames held at once; every one of them is, since a frame held is its runs. */
    unsigned int weight_z;       /**< Weight of z in a lag's squared length, the tie rule; y and x weigh one. */
    unsigned int reserve_bytes;  /**< Device memory, in mebibytes, left free for the other engines. */
} ClimbMachineShape;

/** @brief One frame to store. Every pointer is a host pointer read during the call only. */
typedef struct
{
    unsigned int frame;                   /**< The caller's index for the frame. */
    unsigned int leaf_count;              /**< Leaves. */
    const unsigned int *labels;           /**< Each voxel's peak index [BORROWS]. */
    const unsigned long long *positive;   /**< Sign words [BORROWS]. */
    const unsigned int *peaks;            /**< Peak raster index per leaf, ascending, or NULL where no climb [BORROWS]. */
    const unsigned int *contact_start;    /**< leaf_count + 1 offsets into contacts, or NULL where not sticky [BORROWS]. */
    const unsigned int *contacts;         /**< Each leaf's touching leaves [BORROWS]. */
} ClimbMachineFrame;

/**
 * @brief One pair to climb. The peaks are read, and the outputs written, when the machine runs, so every
 *        pointer must stay valid until then.
 */
typedef struct
{
    unsigned int earlier;             /**< The earlier frame's index, stored. */
    unsigned int later;               /**< The later frame's index, stored. */
    int lag[3];                       /**< The view's lag from earlier to later: every forward climb's start. */
    unsigned int earlier_leaves;      /**< Leaves of the earlier frame. */
    const unsigned int *earlier_peaks;/**< Peak raster index per earlier leaf, ascending [BORROWS]. */
    unsigned int later_leaves;        /**< Leaves of the later frame. */
    const unsigned int *later_peaks;  /**< Peak raster index per later leaf, ascending [BORROWS]. */
    int *forward_lags;                /**< Out: three per earlier leaf, the lag climbed to [BORROWS]. */
    int *forward;                     /**< Out: per earlier leaf, the later leaf its peak lands in, or NO_LEAF [BORROWS]. */
    int *backward_lags;               /**< Out: three per later leaf, the lag climbed to [BORROWS]. */
    int *backward;                    /**< Out: per later leaf, the earlier leaf its peak lands in, or NO_LEAF [BORROWS]. */
    unsigned int *forward_held;       /**< Out, optional: per earlier leaf, its coherence at its fixed point [BORROWS]. */
    unsigned int *backward_held;      /**< Out, optional: per later leaf, its coherence at its fixed point [BORROWS]. */
} ClimbMachinePair;

/** @brief The machine; opaque. */
typedef struct ClimbMachine ClimbMachine;

/**
 * @brief Opens a machine holding as many frames as the shape asks and the device allows, at least two.
 *
 * @param[in] shape The view [BORROWS].
 * @return          The machine, or NULL where two frames do not fit.
 */
ClimbMachine *climb_machine_open(const ClimbMachineShape *shape);

/**
 * @brief Stores a frame. Where every slot is taken, the pending pairs run first and every frame but the newest
 *        is let go, so a pending pair's outputs may be written during this call.
 *
 * @param[in,out] machine The machine [BORROWS].
 * @param[in]     frame   The frame [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
int climb_machine_store(ClimbMachine *machine, const ClimbMachineFrame *frame);

/**
 * @brief The labels of one of the two frames still in the ring: the frame stored last and the one before it.
 *
 * @param[in] machine The machine [BORROWS].
 * @param[in] frame   The frame's index.
 * @return            The device pointer, or NULL where that frame's labels have been let go.
 */
const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame);

/**
 * @brief A stored frame's sign words on the device.
 *
 * @param[in] machine The machine [BORROWS].
 * @param[in] frame   The frame's index.
 * @return            The device pointer, or NULL where the frame is not stored.
 */
const unsigned long long *climb_machine_positive(const ClimbMachine *machine, unsigned int frame);

/**
 * @brief Pends a pair of stored frames for the next run.
 *
 * @param[in,out] machine The machine [BORROWS].
 * @param[in]     pair    The pair, copied; its pointers are borrowed until the run [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
int climb_machine_pend(ClimbMachine *machine, const ClimbMachinePair *pair);

/**
 * @brief Runs every pending pair to its fixed point and writes their outputs.
 *
 * @param[in,out] machine The machine [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
int climb_machine_run(ClimbMachine *machine);

/**
 * @brief Frees the machine and everything it holds.
 *
 * @param[in] machine The machine, or NULL [OWNS].
 */
void climb_machine_close(ClimbMachine *machine);

#ifdef __cplusplus
}
#endif

#endif /* CLIMB_MACHINE_H */
