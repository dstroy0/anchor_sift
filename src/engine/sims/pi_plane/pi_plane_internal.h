// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the pi_plane_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef PI_PLANE_INTERNAL_H
#define PI_PLANE_INTERNAL_H

//
// pi in the plane (Doug, 24 September: "write it bitwise in 2d and look for a line or spiral", "let's do 2kb, 16k
// bits", then "write it out horizontally as a tower of n widths and heights, then try circle shapes of bits written
// as horizontal lines first then write the bits in a circular fill"). pi's bits after the point, certified by
// Machin's bracket on the exact integer, are laid out as shapes; each shape is drawn as a PNG and read for its longest
// straight line of equal bits, against keyed shuffles of the same bits laid out the same way.
//
// 1. The bits: floor((pi - 3) 2^N) is one integer at both ends of Machin's bracket, and it begins 0x243F6A8885A308D3.
// 2. Every width at once: laid out in rows of width W, a line of step (dy, dx) is the progression of difference dy W +
// dx
//    along the bits. The longest run of equal bits at every difference L below N reads every line in every width,
//    a line that wraps a row's end included. The device reads it, one thread a difference, and the host reads it again
//    for pi.
// 3. The shapes: rows of width 7, 16, 32, 64, 106, 113, 128 and 256 (7, 106 and 113 are the denominators of pi's
//    convergents 22/7, 333/106 and 355/113; its floors, the partial quotients, are 3, 7, 15, 1, 292); the tower whose
//    row k holds k bits; a disc filled by horizontal lines and the same disc filled ring by ring; the square spiral;
//    and the twindragon, bit n at the Gaussian integer that n's binary digits name in base -1 + i. Each lays out every
//    bit on its own pixel. A shape's line is read along every step (dy, dx) with coprime parts of at most 6.
// 4. Against chance: every reading is taken again on keyed Fisher-Yates shuffles of the bits, which keep the count of
//    ones, and pi's is ranked among them.
#include "sim.h"

#include <algorithm>
#include <string>
#include <vector>

#define PLANE_BITS 16384u

// the lag scan holds the bits in one block's shared memory, one byte a bit
#define PLANE_BITS_MAX 32768u

// the guard bits Machin's bracket is taken at past the bits read
#define PLANE_GUARD 32u

#define PLANE_PUBLISHED_BITS 0x243F6A8885A308D3ull

#define PLANE_DRAWS 99u

#define PLANE_KEY 0x504C414E45ull

#define PLANE_THREADS 256u

// the widest part of a line's step on a shape
#define PLANE_STEP_MAX 6ll

// a picture's longer side is scaled up to at most this many pixels
#define PLANE_PICTURE_MAX 1024ull

// the shade of a pixel no bit lands on, midway. A one and a zero are equally far from it
#define PLANE_EMPTY_SHADE 128u

// the twindragon's pixels are read by their depth from its edge, 1 to this, the deepest class holding the rest
#define PLANE_DEPTHS 8u

// the golden sphere's spirals join point i to i + F_k: the Fibonacci differences below the bits
#define PLANE_FIBONACCI 20u

// the empty columns between the sphere's four views in its picture
#define PLANE_SPHERE_GAP 3ll

// the rings are drawn unrolled at this many pixels across, each ring a row this tall
#define PLANE_RING_UNROLLED_WIDTH 2048ull

#define PLANE_RING_ROW 24ull

// the fixed point, 2^this, the rings' turn is taken in
#define PLANE_FIXED 40u

// the rings drawn enlarged about the center, and how much
#define PLANE_RING_CENTER 10u

#define PLANE_RING_CENTER_SCALE 2ll

typedef struct
{
    unsigned long long agree;
    unsigned long long pairs;
    unsigned long long run;
    unsigned long long run_ring;
    unsigned long long run_place;
} PlaneRingMeasurement;

typedef struct
{
    long long x;
    long long y;
    long long z;
} PlaneSpherePoint;

#define PLANE_WIDTHS 8u

#define PLANE_TOP_LAGS 8u

// the density of ones is read over 2^m classes of the bits' index for m = 1 to this, each class two bits or more
#define PLANE_SCALES 13u

typedef struct
{
    std::string name;
    unsigned long long height;
    unsigned long long width;
    std::vector<long long> cell;
} PlaneExtent;

typedef struct
{
    long long row;
    long long column;
} PlaneStep;

typedef struct
{
    unsigned long long length;
    PlaneStep step;
    long long start;
} PlaneLine;

typedef struct
{
    long long x;
    long long y;
} PlanePoint;

int plane_bits(SimResults *results, unsigned int count, std::vector<unsigned char> *bits);

int plane_extent_place(PlaneExtent *extent, const std::string &name, const std::vector<long long> &rows,
                       const std::vector<long long> &columns);

int plane_rows(PlaneExtent *extent, unsigned int count, unsigned long long width);

int plane_tower(PlaneExtent *extent, unsigned int count);

int plane_half(const PlanePoint &point);

bool plane_ring_before(const PlanePoint &left, const PlanePoint &right);

bool plane_raster_before(const PlanePoint &left, const PlanePoint &right);

int plane_disc(PlaneExtent *by_rows, PlaneExtent *by_rings, unsigned int count);

int plane_spiral(PlaneExtent *extent, unsigned int count);

int plane_twindragon(PlaneExtent *extent, unsigned int count);

std::vector<PlaneSpherePoint> plane_shell(unsigned int count, long long *radius);

bool plane_latitude_before(const PlaneSpherePoint &left, const PlaneSpherePoint &right);

bool plane_meridian_before(const PlaneSpherePoint &left, const PlaneSpherePoint &right);

void plane_sphere_views(PlaneExtent *extent, const std::string &name, const std::vector<PlaneSpherePoint> &points,
                        long long radius);

unsigned long long plane_latitude_spread(const std::vector<PlaneSpherePoint> &points, long long radius,
                                         const unsigned char *bits);

std::vector<PlaneStep> plane_steps(void);

long long plane_cell_at(const PlaneExtent &extent, long long row, long long column);

PlaneLine plane_longest_line(const PlaneExtent &extent, const unsigned char *bits, const std::vector<PlaneStep> &steps);

void plane_lag_host(const unsigned char *bits, unsigned int count, unsigned int *longest);

int plane_lag_device(SimResults *results, const unsigned char *bits, unsigned int count, unsigned char *device_bits,
                     unsigned int *device_longest, unsigned int *longest);

unsigned int plane_lag_max(const unsigned int *longest, unsigned int count, unsigned int *lag);

unsigned long long plane_spread(const unsigned char *bits, unsigned int count, unsigned int scale, int by_block);

std::vector<unsigned int> plane_depth(const PlaneExtent &extent);

unsigned long long plane_depth_spread(const PlaneExtent &extent, const std::vector<unsigned int> &depth,
                                      const unsigned char *bits, unsigned long long *ones, unsigned long long *sizes);

int plane_png(const std::string &path, const std::vector<unsigned char> &pixels, unsigned long long width,
              unsigned long long height, unsigned int channels);

int plane_picture(const PlaneExtent &extent, const unsigned char *bits, const std::string &path);

int plane_sparse_picture(const PlaneExtent &extent, const unsigned char *bits, const PlaneLine &found,
                         const std::string &path);

std::vector<unsigned long long> plane_ring_sizes(const std::vector<unsigned char> &bits, unsigned long long maximum);

unsigned long long plane_ring_total(const std::vector<unsigned long long> &sizes);

PlaneRingMeasurement plane_ring_read(const std::vector<unsigned long long> &sizes, const unsigned char *bits);

int plane_ring_unrolled(const std::vector<unsigned long long> &sizes, const unsigned char *bits,
                        const std::string &path);

// the turn in integers: pi from its certified bits in 2^PLANE_FIXED, atan(2^-i) by its series, and CORDIC
typedef struct
{
    long long pi;
    long long gain;
    long long arctangent[PLANE_FIXED];
} PlaneTurn;

PlaneTurn plane_turn(const std::vector<unsigned char> &bits);

int plane_ring_circle(const std::vector<unsigned long long> &sizes, const unsigned char *bits, const PlaneTurn &turn,
                      size_t rings, long long scale, const std::string &path);

void plane_shuffle(const std::vector<unsigned char> &bits, unsigned int draw, std::vector<unsigned char> *drawn);

void plane_ring_spiral_read(SimResults *results, const std::vector<unsigned long long> &sizes,
                            const std::vector<unsigned char> &block, unsigned int draws, const char *label);

// the blind pairs hold rings 0 to this less one, and lie in the first this many blocks past the seen bits
#define PLANE_BLIND_RINGS 12u

#define PLANE_BLIND_MAX 16u

// the first round of blind pairs, which the eye scored 6 of 6 (Doug, 25 September)
#define PLANE_BLIND_SCORED 6u

int plane_blind(SimResults *results, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                unsigned int first, unsigned int pairs, int balanced, const std::string &directory);

#define PLANE_FUNNEL_READINGS 3u

typedef struct
{
    size_t ring;
    unsigned long long first;
    unsigned long long last;
} PlaneBar;

// the funnels' depth, their bars' fit to one ratio, and the bits agreeing with their parent
typedef struct
{
    unsigned long long value[PLANE_FUNNEL_READINGS];
} PlaneFunnelMeasurement;

int plane_funnels(SimResults *results, const std::vector<unsigned long long> &sizes, unsigned long long seen,
                  unsigned int fresh, unsigned int draws, const std::string &directory);

int plane_rings(SimResults *results, const std::vector<unsigned char> &bits, unsigned int draws, unsigned int blind,
                unsigned int blind_first, int balanced, unsigned int funnels, const std::string &directory);

std::vector<long long> plane_path_cells(const PlaneExtent &extent, const char *path);

unsigned long long plane_ones_under(const std::vector<long long> &under, const unsigned char *bits);

const char *plane_text(int count, char **arguments, const char *name);

std::string plane_directory(int count, char **arguments);

unsigned int plane_number(int count, char **arguments, const char *name, unsigned int fallback);

void plane_line_print(ScripturaLine *line, const PlaneLine &found);

void plane_band_print(ScripturaLine *line, std::vector<unsigned long long> band, unsigned long long measurement);

#endif
