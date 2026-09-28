// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the noise_terms_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef NOISE_TERMS_INTERNAL_H
#define NOISE_TERMS_INTERNAL_H

#include "sim_camera.h"

#include "noise_detector.h"

#define TERMS_KEY 0x5445524D53ull

// 96 frames of 32 x 128 x 128: the structure function's lag 64 keeps 32 pairs a voxel
#define TERMS_FRAMES 96ull

#define TERMS_DEPTH 32ull

#define TERMS_HEIGHT 128ull

#define TERMS_WIDTH 128ull

// every measurement pools at one level: an offset of 20 and 100 electrons at gain 1, inside the means 40 to 199
#define TERMS_OFFSET 20ull

#define TERMS_BACKGROUND 100ull

#define TERMS_READ_SQUARE 4ull

#define TERMS_PATTERN_RANGE 8ull

// a value's independent variance: the shot's S g^2 and the read's r^2, 104 lane units squared
#define TERMS_VALUE_SQUARE (TERMS_BACKGROUND + TERMS_READ_SQUARE)

// the shared offsets planted, each of variance 4 a frame
#define TERMS_SHARED_SQUARE 4ull

// flicker: octaves 0 to 5, each of variance 16, held 1 to 32 frames
#define TERMS_FLICKER_SQUARE 16ull

#define TERMS_FLICKER_OCTAVES 6u

// spikes of 256 electrons at one voxel-frame in 1024
#define TERMS_SPIKE_DENOMINATOR 1024ull

#define TERMS_SPIKE_ELECTRONS 256ull

// z mixing: each plane but the first takes 1/8 of the plane before it, the way an interpolation along z would
#define TERMS_MIX_EIGHTHS 1ull

// the constant boxes: one held at 0 and one at the lane's top
#define TERMS_ZERO_BOX_VOXELS (3ull * 20ull * 40ull)

#define TERMS_TOP_BOX_VOXELS (1ull * 4ull * 4ull)

// the tolerances: the whole-plane ratios within 2.5% (rows, columns) and 15% (the plane) of what the plant predicts.
// Each frame difference shares a frame with the next. A ratio read over K lines spreads by about sqrt(3/K) of itself:
// the rows and columns at about 9.6 standard errors planted and 12.6 in the null, the plane at 5.7 in the null and
// 4.8 planted, over its 3040 planes
#define TERMS_LINE_PARTS 25ll

#define TERMS_PLANE_PARTS 150ll

// the shot laws are read at 16 electrons, where the moment pass holds a block's fourth cumulant to about 1.4 lane units
// to the fourth over the static blocks, and third to about 0.1
#define TERMS_SHOT_BACKGROUND 16ull

// the ladder's scene: 1 electron plus 1 a column along x, read at gain 2
#define TERMS_LADDER_BACKGROUND 1ull

#define TERMS_LADDER_RAMP 1ull

#define TERMS_LADDER_GAIN 2ll

// the noise detector's static mask, copied to count its voxels by column: the quiet test's slope and floor
// (noise_detector_lines.cu:159-161), the dimmest share (:24), the lane's top (noise_detector_internal.h:42) and
// values (:44), and the moment pass's block of frames (:232)
#define TERMS_QUIET_SLOPE 4ull

#define TERMS_QUIET_FLOOR 32ull

#define TERMS_STATIC_SHARE 4ull

#define TERMS_LANE_TOP 65535u

#define TERMS_LANE_VALUES 65536ull

#define TERMS_MOMENT_BLOCK 5ull

// crosstalk along x: 1/8 of each neighbor's value after the draw
#define TERMS_CROSSTALK_EIGHTHS 1ull

// charge before the gain: no light, gain 2, a reset variance of 4 beside the read's 4, and 16 dark electrons a frame
// at the first exposure, 32 at the second, twice as long
#define TERMS_CHARGE_GAIN 2ull

#define TERMS_RESET_SQUARE 4ull

#define TERMS_DARK 16ull

#define TERMS_EXPOSURES 2ull

// thinning: 64 electrons of light, each counted electron kept with chance a / 4 for a from 1 to 4
#define TERMS_THIN_LIGHT 64ull

#define TERMS_THIN_BITS 2u

#define TERMS_THIN_STEPS 4ull

// optical crosstalk: (1, 2, 1) / 4 along x over a plant along x of period 16 and amplitude 64
#define TERMS_BLUR_EIGHTHS 2ull

#define TERMS_BLUR_PERIOD 16ull

#define TERMS_BLUR_AMPLITUDE 64ull

#define TERMS_BLUR_KEY 0x424C5552ull

// the structure function against the shared scale: a plant along x over the whole width, 60 to 180 electrons, and a
// scale of 4 octaves of variance 1024 over 2^10, about 1 +- 6%
#define TERMS_STRUCTURE_BACKGROUND 60ull

#define TERMS_STRUCTURE_AMPLITUDE 120ull

#define TERMS_STRUCTURE_KEY 0x5354525543ull

#define TERMS_SCALE_SQUARE 1024ull

#define TERMS_SCALE_OCTAVES 4u

#define TERMS_SCALE_BITS 10u

// the gain pattern: flat lights of 100, 200 and 400 electrons, each pixel's gain (1024 + p) / 1024, p in [-32, 32]
#define TERMS_GAIN_PATTERN_RANGE 32ull

#define TERMS_GAIN_PATTERN_BITS 10u

#define TERMS_FLAT_LIGHTS 3u

// the offset pattern (DSNU): each pixel's offset in [0, 12], var(o) about 14 lane units squared
#define TERMS_OFFSET_PATTERN_RANGE 12ull

#define TERMS_MILLION 1000000ull

// the halves' four cameras: the null, the gain pattern, the offset pattern, and both
#define TERMS_HALVES_CAMERAS 4u

static const unsigned long long TERMS_EXTENT[4] = {TERMS_FRAMES, TERMS_DEPTH, TERMS_HEIGHT, TERMS_WIDTH};

void terms_camera(SimCamera *camera);

int terms_render(SimResults *results, const SimScene *scene, const SimCamera *camera, unsigned short *device_lanes,
                 unsigned short *lanes, unsigned long long count);

void terms_lines(SimResults *results, const unsigned short *lanes, unsigned long long row_square,
                 unsigned long long column_square, unsigned long long plane_square);

void terms_flicker(SimResults *results, const unsigned short *lanes, unsigned long long flicker_square,
                   unsigned int octaves);

void terms_neighbors(SimResults *results, const unsigned short *lanes, long long expected_z);

void terms_shot_law(SimResults *results, const unsigned short *lanes, unsigned long long law);

void terms_ratio_within(SimResults *results, const char *what, const AnchorExactInteger *numerator,
                        const AnchorExactInteger *denominator, long long expected_numerator,
                        unsigned long long expected_denominator, unsigned long long range_numerator,
                        unsigned long long range_denominator);

void terms_ladder(SimResults *results, const unsigned short *lanes);

void terms_crosstalk_mix(unsigned short *lanes, const unsigned short *drawn);

void terms_crosstalk(SimResults *results, const unsigned short *lanes, unsigned long long along_x_eighths);

void terms_charge(SimResults *results, const unsigned short *bias, const unsigned short *dark, const SimCamera *camera);

void terms_thinned(SimResults *results, const unsigned short *bias, const unsigned short *lit, long long expected,
                   unsigned long long expected_denominator);

void terms_blur(SimResults *results, const unsigned short *lanes, const SimScene *scene, const SimCamera *camera);

void terms_structure(SimResults *results, const unsigned short *lanes, const SimScene *scene, const SimCamera *camera);

int terms_halves(SimResults *results, const unsigned short *lanes, const SimCamera *camera, unsigned long long light,
                 unsigned long long range_numerator, unsigned long long range_denominator,
                 NoiseHalvesMeasurement *measurement);

void terms_halves_line(SimResults *results, const SimCamera *camera, const NoiseHalvesMeasurement *low,
                       unsigned long long low_light, const NoiseHalvesMeasurement *high, unsigned long long high_light);

void terms_spikes(SimResults *results, const unsigned short *lanes, unsigned long long spike_denominator,
                  unsigned long long law);

void terms_boxes(unsigned short *lanes);

void terms_clips(SimResults *results, const unsigned short *lanes);

#endif
