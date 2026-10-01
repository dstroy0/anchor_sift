// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef FACES_H
#define FACES_H

#include "../../../../src/c/engine/engine.h"

#include <stdio.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define FACES_ERROR (-1L)

// S9's faces, beside each sample's .links as <sample>.faces. Every word is little-endian.
//
// .faces opens with frames, depth, height and width, which are the .points', the .drift's, the .shape's and the
// .links', and then the CRC-64 of the whole .links it was made from, its low word first, as .divide takes it
// (src/divide/divide.h). Each frame follows, in order: its count, and then each point's words in the order of the
// frame's .points: its back-prediction (z, y, x), signed, each written as its two's complement word, then its flags.
//
// The back-prediction mirrors the sort's prediction (sort_link.cu, sort_predict), run backward: a point q of frame
// f > 0 is carried back onto frame f - 1 by the lag the .drift records at f, and by the motion its chosen link out
// q -> q' brought, less the drift then, reversed:
//   b = x_q - lag(f) - (x_q' - x_q - lag(f + 1)).
// With no chosen link out, or at the last frame, b = x_q - lag(f). A point of frame 0 has no frame before it, and its
// back-prediction is its place. The links are the sort's, as the .links holds them: a .divide the output makes after
// changes no word here
#define FACES_HEADER_WORDS 6u

#define FACES_POINT_WORDS 4u

// a start (a point after frame 0 with no chosen link in) whose back-prediction lies outside [0, extent) on some axis,
// with no buffer: the cell entered the view (O11)
#define FACES_ENTERING 0x1u
// an end (a point before the last frame with no chosen link out) whose prediction, the .links' own, lies outside
// [0, extent) on some axis: the cell left the view
#define FACES_LEAVING 0x2u
// a point of frame 0, which starts with the movie, and a point of the last frame, which ends with it
#define FACES_FIRST 0x4u
#define FACES_LAST 0x8u
// the back-prediction took the motion of the point's chosen link out
#define FACES_CARRIED 0x10u

// the faces a place crosses, one bit each in the order of the shape's faces (peaks/hessian.h): below 0 on z, at or past
// the depth on z, then y, then x. The back-prediction's faces sit at FACES_BACK_SHIFT, the prediction's at
// FACES_AHEAD_SHIFT (none for a point of the last frame, which has no prediction), and the point's own faces from its
// .shape, the O4 bits of the faces that cut its neighborhood, at FACES_HESSIAN_SHIFT
#define FACES_BACK_SHIFT 8u
#define FACES_AHEAD_SHIFT 16u
#define FACES_HESSIAN_SHIFT 24u
#define FACES_SIX 0x3Fu

    // what the part reads and where it writes: each sample's .points, .drift, .shape and .links in `set`, and its
    // .faces beside them. `report` takes a line a sample and the set's; an error's reason goes to stderr
    typedef struct
    {
        const char *set;
        char *const *samples;
        unsigned int count;
        FILE *report;
    } FacesRequest;

    // writes each sample's .faces; a sample that errors (a head that disagrees, a file that stops short or goes on
    // past its last frame, a flag the .links sets against its own prediction, a back-prediction past 32 bits) leaves no
    // .faces, not even one an earlier run wrote, and the set errors
    long faces_find_set(const FacesRequest *request);

#ifdef __cplusplus
}
#endif

#endif
