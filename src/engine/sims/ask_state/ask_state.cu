// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The ask and the state: a qubit's state carried exactly as the answer distribution of a complete ask.
// Two asks, E_i = (I + v_i . sigma) / 4 over four outcomes: a rational tetrahedral ask, v_i = (+-1, +-1, +-1) / 2,
// all in Q; and the true SIC, v_i = (+-1, +-1, +-1) / sqrt 3, in Q(sqrt 3), where the square root is carried by its
// defining relation (sqrt 3)^2 = 3 (Doug, 23 September), so every value stays exact. Proved for each ask: it is an
// ask; state -> answers -> state returns the state; the phase falls out of the ask; the valid set accepts every
// state and puts the pure ones on its boundary; the crossing rule reproduces the other asks' answers and carries
// a negative weight; a distribution outside the valid set crosses to a non-probability; the two asks cross into
// each other. Measured: how many of a grid of distributions are states.

#include "sim_rational.h"

#define ASK_OUTCOMES 4u

#define ASK_AXES 3u

#define ASK_GRID 12ll

#define ASK_STATES_MOST 32u

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

static AskNumber ask_number(SimRational rational, SimRational root)
{
    AskNumber value;
    value.rational = rational;
    value.root = root;
    return value;
}

static AskNumber ask_whole(long long numerator, long long denominator)
{
    return ask_number(sim_rational(numerator, denominator), sim_rational(0ll, 1ll));
}

static AskNumber ask_number_sum(AskNumber left, AskNumber right)
{
    return ask_number(sim_rational_sum(left.rational, right.rational), sim_rational_sum(left.root, right.root));
}

static AskNumber ask_number_difference(AskNumber left, AskNumber right)
{
    return ask_number(sim_rational_difference(left.rational, right.rational),
                      sim_rational_difference(left.root, right.root));
}

// (a + b sqrt 3)(c + d sqrt 3) = (ac + 3bd) + (ad + bc) sqrt 3: the square root's defining relation
static AskNumber ask_number_product(AskNumber left, AskNumber right)
{
    const SimRational roots = sim_rational_product(left.root, right.root);
    const SimRational rational = sim_rational_sum(sim_rational_product(left.rational, right.rational),
                                                  sim_rational_product(sim_rational(3ll, 1ll), roots));
    const SimRational root = sim_rational_sum(sim_rational_product(left.rational, right.root),
                                              sim_rational_product(left.root, right.rational));
    return ask_number(rational, root);
}

// the sign of a + b sqrt 3, exactly: with opposite signs the larger of a^2 and 3 b^2 decides, and they are never
// equal unless both are 0, since sqrt 3 is irrational
static int ask_number_sign(AskNumber value)
{
    const int rational = sim_rational_sign(value.rational);
    const int root = sim_rational_sign(value.root);
    if ((root == 0) || (rational == root))
    {
        return rational;
    }
    if (rational == 0)
    {
        return root;
    }
    const SimRational square = sim_rational_product(value.rational, value.rational);
    const SimRational root_square = sim_rational_product(sim_rational(3ll, 1ll),
                                                         sim_rational_product(value.root, value.root));
    return (sim_rational_sign(sim_rational_difference(square, root_square)) > 0) ? rational : root;
}

// 1 and sqrt 3 are independent over Q, so two numbers are equal exactly when both parts are
static int ask_number_equal(AskNumber left, AskNumber right)
{
    return sim_rational_equal(left.rational, right.rational) && sim_rational_equal(left.root, right.root);
}

static void ask_number_print(ScripturaLine *line, AskNumber value)
{
    const int root_sign = sim_rational_sign(value.root);
    if (root_sign == 0)
    {
        sim_rational_print(line, value.rational);
        return;
    }
    if (sim_rational_sign(value.rational) != 0)
    {
        sim_rational_print(line, value.rational);
        scriptura_text(line, (root_sign > 0) ? " + " : " - ");
        sim_rational_print(line, (root_sign > 0) ? value.root : sim_rational_negative(value.root));
    }
    else
    {
        sim_rational_print(line, value.root);
    }
    scriptura_text(line, " sqrt3");
}

static const long long s_ask_signs[ASK_OUTCOMES][ASK_AXES] = {{1ll, 1ll, 1ll}, {1ll, -1ll, -1ll}, {-1ll, 1ll, -1ll},
                                                                {-1ll, -1ll, 1ll}};

static void ask_frame_rational(AskFrame *frame)
{
    frame->name = "rational tetrahedral ask, v = (+-1, +-1, +-1) / 2";
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            frame->vector[outcome][axis] = ask_whole(s_ask_signs[outcome][axis], 2ll);
        }
    }
}

// (+-1) / sqrt 3 = (+-1/3) sqrt 3
static void ask_frame_sic(AskFrame *frame)
{
    frame->name = "the SIC, v = (+-1, +-1, +-1) / sqrt3, in Q(sqrt3)";
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            frame->vector[outcome][axis] = ask_number(sim_rational(0ll, 1ll), sim_rational(s_ask_signs[outcome][axis], 3ll));
        }
    }
}

static AskNumber ask_dot(const AskNumber *left, const AskNumber *right)
{
    AskNumber total = ask_whole(0ll, 1ll);
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        total = ask_number_sum(total, ask_number_product(left[axis], right[axis]));
    }
    return total;
}

// it is an ask, and a complete one whose frame sum v v^T is c I, so a state comes back as r = (4 / c) sum p v
static int ask_frame_open(SimTally *tally, AskFrame *frame, AskNumber *length_square)
{
    int sums_zero = 1;
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        AskNumber total = ask_whole(0ll, 1ll);
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            total = ask_number_sum(total, frame->vector[outcome][axis]);
        }
        sums_zero = sums_zero && (ask_number_sign(total) == 0);
    }
    sim_check(tally, sums_zero, "the ask's operators sum to the identity (the vectors sum to 0)");
    int positive = 1;
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        const AskNumber square = ask_dot(frame->vector[outcome], frame->vector[outcome]);
        positive = positive && (ask_number_sign(ask_number_difference(ask_whole(1ll, 1ll), square)) >= 0);
        *length_square = square;
    }
    sim_check(tally, positive, "every operator of the ask is positive (|v|^2 at most 1)");
    int identity = 1;
    AskNumber diagonal = ask_whole(0ll, 1ll);
    for (unsigned int row = 0u; row < ASK_AXES; row += 1u)
    {
        for (unsigned int column = 0u; column < ASK_AXES; column += 1u)
        {
            AskNumber entry = ask_whole(0ll, 1ll);
            for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
            {
                entry = ask_number_sum(entry, ask_number_product(frame->vector[outcome][row], frame->vector[outcome][column]));
            }
            if (row == column)
            {
                identity = identity && ((row == 0u) || ask_number_equal(entry, diagonal));
                diagonal = entry;
            }
            else
            {
                identity = identity && (ask_number_sign(entry) == 0);
            }
        }
    }
    identity = identity && (sim_rational_sign(diagonal.root) == 0) && (sim_rational_sign(diagonal.rational) != 0);
    sim_check(tally, identity, "the ask's frame is a multiple of the identity, so it is complete");
    frame->factor = sim_rational(0ll, 1ll);
    if (identity != 0)
    {
        frame->factor = sim_rational_product(sim_rational(4ll, 1ll), sim_rational_reciprocal(diagonal.rational));
    }
    return identity;
}

static void ask_answers(const AskFrame *frame, const AskNumber *bloch, AskNumber *answer)
{
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        answer[outcome] = ask_number_product(ask_whole(1ll, 4ll),
                                             ask_number_sum(ask_whole(1ll, 1ll), ask_dot(bloch, frame->vector[outcome])));
    }
}

static void ask_state_from(const AskFrame *frame, const AskNumber *answer, AskNumber *bloch)
{
    const AskNumber factor = ask_number(frame->factor, sim_rational(0ll, 1ll));
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        AskNumber total = ask_whole(0ll, 1ll);
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            total = ask_number_sum(total, ask_number_product(answer[outcome], frame->vector[outcome][axis]));
        }
        bloch[axis] = ask_number_product(factor, total);
    }
}

// the crossing rule's weight for outcome i on the ask "+axis": 1/2 + (c^-1 . 2) v_i, from sum p = 1
static AskNumber ask_weight(const AskFrame *frame, unsigned int outcome, unsigned int axis)
{
    const AskNumber half_factor = ask_number(sim_rational_product(frame->factor, sim_rational(1ll, 2ll)),
                                             sim_rational(0ll, 1ll));
    return ask_number_sum(ask_whole(1ll, 2ll), ask_number_product(half_factor, frame->vector[outcome][axis]));
}

static AskNumber ask_cross(const AskFrame *frame, const AskNumber *answer, unsigned int axis)
{
    AskNumber total = ask_whole(0ll, 1ll);
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        total = ask_number_sum(total, ask_number_product(answer[outcome], ask_weight(frame, outcome, axis)));
    }
    return total;
}

static int ask_is_probability(AskNumber value)
{
    return (ask_number_sign(value) >= 0) && (ask_number_sign(ask_number_difference(ask_whole(1ll, 1ll), value)) >= 0);
}

static int ask_valid(const AskFrame *frame, const AskNumber *answer)
{
    AskNumber bloch[ASK_AXES];
    ask_state_from(frame, answer, bloch);
    return ask_number_sign(ask_number_difference(ask_whole(1ll, 1ll), ask_dot(bloch, bloch))) >= 0;
}

static unsigned int ask_states(AskState *state)
{
    unsigned int count = 0u;
    // pure states on the equator from rational t: ((1 - t^2) / (1 + t^2), 2t / (1 + t^2), 0), t = n / d
    const long long turn[13][2] = {{0ll, 1ll}, {1ll, 3ll}, {1ll, 2ll}, {2ll, 3ll}, {1ll, 1ll}, {3ll, 2ll}, {2ll, 1ll},
                                   {3ll, 1ll}, {-1ll, 2ll}, {-1ll, 1ll}, {-2ll, 1ll}, {1ll, 5ll}, {4ll, 7ll}};
    for (unsigned int at = 0u; at < 13u; at += 1u)
    {
        const long long n = turn[at][0];
        const long long d = turn[at][1];
        state[count].bloch[0] = ask_whole((d * d) - (n * n), (d * d) + (n * n));
        state[count].bloch[1] = ask_whole(2ll * n * d, (d * d) + (n * n));
        state[count].bloch[2] = ask_whole(0ll, 1ll);
        state[count].pure = 1;
        state[count].equator = 1;
        count += 1u;
    }
    state[count].bloch[0] = ask_whole(-1ll, 1ll);
    state[count].bloch[1] = ask_whole(0ll, 1ll);
    state[count].bloch[2] = ask_whole(0ll, 1ll);
    state[count].pure = 1;
    state[count].equator = 1;
    count += 1u;
    // pure states off the equator: rational points of the sphere
    const long long sphere[7][4] = {{2ll, 2ll, 1ll, 3ll},  {1ll, -2ll, 2ll, 3ll}, {2ll, 3ll, 6ll, 7ll}, {0ll, 0ll, 1ll, 1ll},
                                    {0ll, 0ll, -1ll, 1ll}, {-2ll, 1ll, -2ll, 3ll}, {6ll, 6ll, 7ll, 11ll}};
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            state[count].bloch[axis] = ask_whole(sphere[at][axis], sphere[at][3]);
        }
        state[count].pure = 1;
        state[count].equator = 0;
        count += 1u;
    }
    // mixed states: pure ones pulled toward the centre, and the centre itself
    const long long mixed[4][4] = {{1ll, 1ll, 1ll, 6ll}, {2ll, 3ll, 6ll, 21ll}, {3ll, 4ll, 0ll, 10ll}, {0ll, 0ll, 0ll, 1ll}};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        state[count].bloch[0] = ask_whole(2ll * mixed[at][0], 2ll * mixed[at][3]);
        state[count].bloch[1] = ask_whole(2ll * mixed[at][1], 2ll * mixed[at][3]);
        state[count].bloch[2] = ask_whole(mixed[at][2], mixed[at][3]);
        state[count].pure = 0;
        state[count].equator = 0;
        count += 1u;
    }
    return count;
}

static void ask_frame_run(SimTally *tally, AskFrame *frame, const AskState *state, unsigned int states)
{
    ScripturaLine *const line = &tally->line;
    AskNumber length_square = ask_whole(0ll, 1ll);
    const int complete = ask_frame_open(tally, frame, &length_square);
    scriptura_text(line, "\n  ");
    scriptura_text(line, frame->name);
    scriptura_text(line, "\n    |v|^2 = ");
    ask_number_print(line, length_square);
    scriptura_text(line, ask_number_equal(length_square, ask_whole(1ll, 1ll)) ? " (rank one: a SIC)" : " (not rank one)");
    scriptura_text(line, "; the frame is c I, so the state comes back as r = ");
    sim_rational_print(line, frame->factor);
    scriptura_text(line, " sum p_i v_i\n");
    if (complete == 0)
    {
        sim_flush(tally);
        return;
    }
    unsigned int probabilities = 0u;
    unsigned int returned = 0u;
    unsigned int accepted = 0u;
    unsigned int pure = 0u;
    unsigned int on_boundary = 0u;
    unsigned int mixed = 0u;
    unsigned int inside = 0u;
    unsigned int crossings = 0u;
    // an exact number is four exact integers, so the table is held statically rather than on the stack
    static AskNumber equator_answer[ASK_STATES_MOST][ASK_OUTCOMES];
    unsigned int equators = 0u;
    unsigned int same_magnitudes = 0u;
    for (unsigned int at = 0u; at < states; at += 1u)
    {
        AskNumber answer[ASK_OUTCOMES];
        ask_answers(frame, state[at].bloch, answer);
        AskNumber total = ask_whole(0ll, 1ll);
        int each = 1;
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            each = each && (ask_number_sign(answer[outcome]) >= 0);
            total = ask_number_sum(total, answer[outcome]);
        }
        probabilities += (each && ask_number_equal(total, ask_whole(1ll, 1ll))) ? 1u : 0u;
        AskNumber bloch[ASK_AXES];
        ask_state_from(frame, answer, bloch);
        int same = 1;
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            same = same && ask_number_equal(bloch[axis], state[at].bloch[axis]);
        }
        returned += same ? 1u : 0u;
        accepted += ask_valid(frame, answer) ? 1u : 0u;
        const AskNumber square = ask_dot(bloch, bloch);
        if (state[at].pure != 0)
        {
            pure += 1u;
            on_boundary += ask_number_equal(square, ask_whole(1ll, 1ll)) ? 1u : 0u;
        }
        else
        {
            mixed += 1u;
            inside += (ask_number_sign(ask_number_difference(ask_whole(1ll, 1ll), square)) > 0) ? 1u : 0u;
        }
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            const AskNumber direct = ask_number_product(ask_whole(1ll, 2ll),
                                                        ask_number_sum(ask_whole(1ll, 1ll), state[at].bloch[axis]));
            crossings += ask_number_equal(ask_cross(frame, answer, axis), direct) ? 1u : 0u;
        }
        if (state[at].equator != 0)
        {
            // the 0/1 ask reads z: every equator state answers 1/2, 1/2 there
            same_magnitudes += ask_number_equal(ask_cross(frame, answer, 2u), ask_whole(1ll, 2ll)) ? 1u : 0u;
            for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
            {
                equator_answer[equators][outcome] = answer[outcome];
            }
            equators += 1u;
        }
    }
    unsigned int pairs = 0u;
    unsigned int distinct = 0u;
    for (unsigned int first = 0u; first < equators; first += 1u)
    {
        for (unsigned int second = first + 1u; second < equators; second += 1u)
        {
            int differ = 0;
            for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
            {
                differ = differ || !ask_number_equal(equator_answer[first][outcome], equator_answer[second][outcome]);
            }
            pairs += 1u;
            distinct += differ ? 1u : 0u;
        }
    }
    sim_check(tally, probabilities == states, "every state's answers are a probability distribution");
    sim_check(tally, returned == states, "state -> answers -> state returns every state exactly");
    sim_check(tally, accepted == states, "the valid set accepts every state");
    sim_check(tally, on_boundary == pure, "every pure state sits on the valid set's boundary, |r|^2 = 1");
    sim_check(tally, inside == mixed, "every mixed state sits strictly inside");
    sim_check(tally, crossings == (states * ASK_AXES), "the crossing rule reproduces the +x, +y and +z asks' answers");
    sim_check(tally, same_magnitudes == equators, "every equator state answers 1/2, 1/2 to the 0/1 ask");
    sim_check(tally, distinct == pairs, "yet the complete ask tells every pair of them apart: the phase falls out");
    scriptura_text(line, "    ");
    scriptura_decimal(line, states, 1u);
    scriptura_text(line, " states (");
    scriptura_decimal(line, pure, 1u);
    scriptura_text(line, " pure, ");
    scriptura_decimal(line, mixed, 1u);
    scriptura_text(line, " mixed): answers a distribution ");
    scriptura_decimal(line, probabilities, 1u);
    scriptura_text(line, ", returned exactly ");
    scriptura_decimal(line, returned, 1u);
    scriptura_text(line, ", accepted ");
    scriptura_decimal(line, accepted, 1u);
    scriptura_text(line, ", pure on the boundary ");
    scriptura_decimal(line, on_boundary, 1u);
    scriptura_text(line, ", mixed inside ");
    scriptura_decimal(line, inside, 1u);
    scriptura_text(line, ", crossings matched ");
    scriptura_decimal(line, crossings, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, states * ASK_AXES, 1u);
    scriptura_text(line, "\n    the phase: ");
    scriptura_decimal(line, equators, 1u);
    scriptura_text(line, " equator states all answer 1/2, 1/2 to the 0/1 ask; the complete ask tells apart ");
    scriptura_decimal(line, distinct, 1u);
    scriptura_text(line, " of their ");
    scriptura_decimal(line, pairs, 1u);
    scriptura_text(line, " pairs\n");

    int negative = 0;
    scriptura_text(line, "    the crossing weights onto +x:");
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        const AskNumber weight = ask_weight(frame, outcome, 0u);
        negative = negative || (ask_number_sign(weight) < 0);
        scriptura_text(line, (outcome == 0u) ? " " : ", ");
        ask_number_print(line, weight);
    }
    scriptura_character(line, '\n');
    sim_check(tally, negative, "a crossing weight is negative, so the crossing is not classical total probability");

    AskNumber corner[ASK_OUTCOMES];
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        corner[outcome] = ask_whole((outcome == 0u) ? 1ll : 0ll, 1ll);
    }
    const AskNumber corner_cross = ask_cross(frame, corner, 0u);
    sim_check(tally, !ask_valid(frame, corner), "the distribution (1, 0, 0, 0) is refused: it is no state");
    sim_check(tally, !ask_is_probability(corner_cross), "and it crosses onto +x at a value that is no probability");
    scriptura_text(line, "    outside the valid set: (1, 0, 0, 0) is refused, and crosses onto +x at ");
    ask_number_print(line, corner_cross);
    scriptura_character(line, '\n');

    unsigned int grid = 0u;
    unsigned int valid = 0u;
    unsigned int valid_crossing = 0u;
    unsigned int invalid_axes_fine = 0u;
    for (long long first = 0ll; first <= ASK_GRID; first += 1ll)
    {
        for (long long second = 0ll; (first + second) <= ASK_GRID; second += 1ll)
        {
            for (long long third = 0ll; (first + second + third) <= ASK_GRID; third += 1ll)
            {
                const long long fourth = ASK_GRID - first - second - third;
                AskNumber answer[ASK_OUTCOMES];
                answer[0] = ask_whole(first, ASK_GRID);
                answer[1] = ask_whole(second, ASK_GRID);
                answer[2] = ask_whole(third, ASK_GRID);
                answer[3] = ask_whole(fourth, ASK_GRID);
                int axes_fine = 1;
                for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
                {
                    axes_fine = axes_fine && ask_is_probability(ask_cross(frame, answer, axis));
                }
                grid += 1u;
                if (ask_valid(frame, answer))
                {
                    valid += 1u;
                    valid_crossing += axes_fine ? 1u : 0u;
                }
                else
                {
                    invalid_axes_fine += axes_fine ? 1u : 0u;
                }
            }
        }
    }
    sim_check(tally, valid_crossing == valid, "every grid distribution in the valid set crosses to probabilities");
    scriptura_text(line, "    the grid of distributions with denominator 12 (");
    scriptura_decimal(line, grid, 1u);
    scriptura_text(line, "): ");
    scriptura_decimal(line, valid, 1u);
    scriptura_text(line, " are states; of the other ");
    scriptura_decimal(line, grid - valid, 1u);
    scriptura_text(line, ", ");
    scriptura_decimal(line, invalid_axes_fine, 1u);
    scriptura_text(line, " still cross to probabilities on the x, y and z asks yet are no state\n");
    sim_flush(tally);
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    ScripturaLine *const line = &tally.line;
    scriptura_text(line, "  the ask and the state: a qubit carried exactly as the answers of a complete ask, E_i = (I + v_i . sigma) / 4\n");
    scriptura_text(line, "  every value exact in Q(sqrt3): a square root is carried by its relation (sqrt3)^2 = 3\n");
    sim_flush(&tally);

    static AskState state[ASK_STATES_MOST];
    const unsigned int states = ask_states(state);
    int pure_listed = 1;
    for (unsigned int at = 0u; at < states; at += 1u)
    {
        if (state[at].pure != 0)
        {
            pure_listed = pure_listed && ask_number_equal(ask_dot(state[at].bloch, state[at].bloch), ask_whole(1ll, 1ll));
        }
    }
    sim_check(&tally, pure_listed, "every listed pure state has |r|^2 = 1 exactly");

    AskFrame rational;
    AskFrame sic;
    ask_frame_rational(&rational);
    ask_frame_sic(&sic);
    ask_frame_run(&tally, &rational, state, states);
    ask_frame_run(&tally, &sic, state, states);

    // the two complete asks cross into each other: the SIC's answers give the state, which gives the rational
    // ask's answers, and they equal the rational ask asked directly
    unsigned int crossed = 0u;
    for (unsigned int at = 0u; at < states; at += 1u)
    {
        AskNumber sic_answer[ASK_OUTCOMES];
        AskNumber bloch[ASK_AXES];
        AskNumber through[ASK_OUTCOMES];
        AskNumber direct[ASK_OUTCOMES];
        ask_answers(&sic, state[at].bloch, sic_answer);
        ask_state_from(&sic, sic_answer, bloch);
        ask_answers(&rational, bloch, through);
        ask_answers(&rational, state[at].bloch, direct);
        int same = 1;
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            same = same && ask_number_equal(through[outcome], direct[outcome]);
        }
        crossed += same ? 1u : 0u;
    }
    sim_check(&tally, crossed == states, "the SIC's answers cross into the rational ask's exactly");
    scriptura_text(line, "\n  the two asks cross into each other on ");
    scriptura_decimal(line, crossed, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, states, 1u);
    scriptura_text(line, " states\n");
    sim_check(&tally, s_sim_rational_wide == 0, "every value fit the exact integer's width");
    return sim_close(&tally, "ask and state");
}
