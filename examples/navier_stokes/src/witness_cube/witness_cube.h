// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// witness_cube.h: a subject measured by 8 witnesses at the corners of a cube around it, every value an exact form
#ifndef WITNESS_CUBE_H
#define WITNESS_CUBE_H

// The subject is a form at a point of 3 rational parameters. Corner b = b_0 + 2 b_1 + 4 b_2 sits at
// center_a + (2 b_a - 1) half_a on each axis a, its sign on that axis s_a = 2 b_a - 1. Component S, a set of axes
// written as the same three bits, is
//     c_S = (1/8) sum over the corners of f(corner) times the product over a in S of s_a,
// and f(corner) = sum over S of c_S times that product, exactly: c_0 is the value, c_1, c_2 and c_4 the edge
// differences, c_3, c_5 and c_6 the face differences, and c_7 the body difference. Each term the subject holds at any
// corner is marked with the components holding it: the count of those is the term's character, recorded as it is.

#include "atom_form.h"

#include <stdio.h>

// the subject's form at `point`, its atoms named in `book`
typedef AtomForm (*WitnessSubject)(const void *context, const SimRational *point, AtomBook *book);

typedef struct
{
    SimRational center[3];
    SimRational half[3];
    AtomForm corner[8];
    AtomForm component[8];
    // the slots held at any corner, in key order, and the components holding each, one bit per component
    std::vector<unsigned int> slot;
    std::vector<unsigned int> holding;
} WitnessCube;

// the cube measured around `center` with the half-edges `half`, each above 0
void witness_cube_measure(WitnessSubject subject, const void *context, const SimRational *center,
                          const SimRational *half, AtomBook *book, WitnessCube *cube);

// the corners rebuilt from the components: 1 where every corner is the subject's form exactly
int witness_cube_whole(const WitnessCube *cube);

// the number of terms whose character is `count`, 1 to 8
size_t witness_cube_characters(const WitnessCube *cube, unsigned int count);

// the cube written whole: center, half-edges, the 8 corners, the 8 components, and each term's components
void witness_cube_record(FILE *file, const char *name, const WitnessCube *cube, const AtomBook *book);

// 1 where a value in this module outgrew the build's width
int witness_cube_short(void);

#endif
