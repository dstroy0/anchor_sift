// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the ask_state_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef ASK_STATE_INTERNAL_H
#define ASK_STATE_INTERNAL_H

// The ask and the state: a qubit's state carried exactly as the answer distribution of a complete ask.
// Two asks, E_i = (I + v_i . sigma) / 4 over four outcomes: a rational tetrahedral ask, v_i = (+-1, +-1, +-1) / 2,
// all in Q; and the true SIC, v_i = (+-1, +-1, +-1) / sqrt 3, in Q(sqrt 3), where the square root is carried by its
// defining relation (sqrt 3)^2 = 3. Every value stays exact. Proved for each ask: it is an
// ask; state -> answers -> state returns the state; the phase falls out of the ask; the valid set accepts every
// state and puts the pure ones on its boundary; the crossing rule reproduces the other asks' answers and carries
// a negative weight; a distribution outside the valid set crosses to a non-probability; the two asks cross into
// each other. Measured: how many of a grid of distributions are states.

#include "sim_rational.h"

#define ASK_OUTCOMES 4u

#define ASK_AXES 3u

#define ASK_GRID 12ll

#define ASK_STATES_MAX 32u

// rational + root . sqrt 3
typedef struct
{
    SimRational rational;
    SimRational root;
} AskNumber;

typedef struct
{
    const char *name;
    AskNumber vector[ASK_OUTCOMES][ASK_AXES];
    SimRational factor;
} AskFrame;

typedef struct
{
    AskNumber bloch[ASK_AXES];
    int pure;
    int equator;
} AskState;

AskNumber ask_fraction(long long numerator, long long denominator);

AskNumber ask_number_sum(AskNumber left, AskNumber right);

AskNumber ask_number_difference(AskNumber left, AskNumber right);

AskNumber ask_number_product(AskNumber left, AskNumber right);

int ask_number_sign(AskNumber value);

int ask_number_equal(AskNumber left, AskNumber right);

void ask_number_print(ScripturaLine *line, AskNumber value);

void ask_frame_rational(AskFrame *frame);

void ask_frame_sic(AskFrame *frame);

AskNumber ask_dot(const AskNumber *left, const AskNumber *right);

int ask_frame_open(SimResults *results, AskFrame *frame, AskNumber *length_square);

void ask_answers(const AskFrame *frame, const AskNumber *bloch, AskNumber *answer);

void ask_state_from(const AskFrame *frame, const AskNumber *answer, AskNumber *bloch);

AskNumber ask_weight(const AskFrame *frame, unsigned int outcome, unsigned int axis);

AskNumber ask_cross(const AskFrame *frame, const AskNumber *answer, unsigned int axis);

int ask_is_probability(AskNumber value);

int ask_valid(const AskFrame *frame, const AskNumber *answer);

#endif
