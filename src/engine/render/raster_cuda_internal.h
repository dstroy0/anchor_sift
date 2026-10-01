
// What the raster_cuda_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RASTER_CUDA_INTERNAL_H
#define RASTER_CUDA_INTERNAL_H

/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file raster_cuda_internal.h
 * @brief The device arm of the direct renderer. Same configuration, same bytes as the host arm.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 *
 * ONE THREAD PER ALIGNMENT. Rendering is the search. The parallel decomposition is the search's:
 * every alignment is independent until it reduces into a pixel. Nothing is tiled and nothing is
 * staged in shared memory, because each thread reads a handful of bytes and writes one value.
 *
 * WHY THIS AGREES WITH THE HOST BYTE FOR BYTE. Three properties hold it together. The value a thread
 * computes is integer arithmetic on the same inputs. No rounding can differ. The cell a thread
 * targets comes from integer division and a permutation, neither of which depends on which thread
 * runs. And the reduction is a minimum or a maximum, both associative and commutative. The
 * scheduler may interleave the atomics in any order and reach the same result. A reduction selecting
 * by arrival would have made the device answer depend on scheduling and could not have been graded
 * against the host at all.
 *
 * @note The transform and the channel are reimplemented here, because the host arm is built by
 *       MinGW through CMake and this is built by nvcc driving MSVC. The two cannot link, the same
 *       split maint/engine/build_gpu_arm.sh already documents for the exact arm. Where a device is
 *       present, bench_raster grades the two rasters byte for byte, and a divergence fails a row.
 * @warning A copy is a defect waiting to happen, and this one is only safe because a grader compares
 *          the outputs on every configuration. Delete that grader and this file becomes a second
 *          renderer nobody checks.
 */

#include <cstdio>
#include <cuda_runtime.h>

extern "C"
{
#include "anchor_raster.h"
}

/** @brief Death level step in the gray ramp. Matches ANCHOR_RASTER_STEP in anchor_raster_internal.h. */
#define RASTER_STEP 40u

/** @brief Brightest value a death level may reach. Matches ANCHOR_RASTER_CEILING. */
#define RASTER_CEILING 250u

/** @brief Probe as the kernel reads it, laid out to match AnchorRasterProbe exactly. */
struct DeviceProbe
{
    unsigned long long origin;
    unsigned long long step;
    unsigned long long length;
};

/** @brief Configuration as the kernel reads it. Only the fields a thread needs are carried. */
struct DeviceConfig
{
    unsigned long long width;
    unsigned long long height;
    int layout;
    int channel;
    int reduce;
    unsigned int gain;
};

__global__ void render_alignments(unsigned int *staging, DeviceConfig config, const unsigned char *corpus,
                                  unsigned long long corpus_len, const unsigned char *needle,
                                  unsigned long long needle_len, const DeviceProbe *probes,
                                  unsigned long long probe_count, const unsigned long long *occurrences,
                                  unsigned long long total);

extern "C" int anchor_raster_device_available(void);

/** @brief Volume configuration as the kernel reads it. The layout maps an alignment to a voxel. */
struct DeviceVolumeConfig
{
    unsigned long long width;
    unsigned long long height;
    unsigned long long depth;
    int layout;
    int channel;
    int reduce;
    unsigned int gain;
};

__global__ void render_volume(unsigned int *staging, int *error, DeviceVolumeConfig vconfig,
                              const unsigned char *corpus, unsigned long long corpus_len, const unsigned char *needle,
                              unsigned long long needle_len, const DeviceProbe *probes, unsigned long long probe_count,
                              const unsigned long long *occurrences, unsigned long long total);

#endif
