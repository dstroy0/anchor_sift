// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ask_state_number.cu: exact numbers, frames and answers
#include "ask_state_internal.h"

static AskNumber ask_number(SimRational rational, SimRational root)
{
    AskNumber value;
    value.rational = rational;
    value.root = root;
    return value;
}

AskNumber ask_fraction(long long numerator, long long denominator)
{
    return ask_number(sim_rational(numerator, denominator), sim_rational(0ll, 1ll));
}

AskNumber ask_number_sum(AskNumber left, AskNumber right)
{
    return ask_number(sim_rational_sum(left.rational, right.rational), sim_rational_sum(left.root, right.root));
}

AskNumber ask_number_difference(AskNumber left, AskNumber right)
{
    return ask_number(sim_rational_difference(left.rational, right.rational),
                      sim_rational_difference(left.root, right.root));
}

// (a + b sqrt 3)(c + d sqrt 3) = (ac + 3bd) + (ad + bc) sqrt 3: the square root's defining relation
AskNumber ask_number_product(AskNumber left, AskNumber right)
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
int ask_number_sign(AskNumber value)
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
    const SimRational root_square =
        sim_rational_product(sim_rational(3ll, 1ll), sim_rational_product(value.root, value.root));
    return (sim_rational_sign(sim_rational_difference(square, root_square)) > 0) ? rational : root;
}

// 1 and sqrt 3 are independent over Q. Two numbers are equal exactly when both parts are
int ask_number_equal(AskNumber left, AskNumber right)
{
    return sim_rational_equal(left.rational, right.rational) && sim_rational_equal(left.root, right.root);
}

void ask_number_print(ScripturaLine *line, AskNumber value)
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

static const long long s_ask_signs[ASK_OUTCOMES][ASK_AXES] = {
    {1ll, 1ll, 1ll}, {1ll, -1ll, -1ll}, {-1ll, 1ll, -1ll}, {-1ll, -1ll, 1ll}};

void ask_frame_rational(AskFrame *frame)
{
    frame->name = "rational tetrahedral ask, v = (+-1, +-1, +-1) / 2";
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            frame->vector[outcome][axis] = ask_fraction(s_ask_signs[outcome][axis], 2ll);
        }
    }
}

// (+-1) / sqrt 3 = (+-1/3) sqrt 3
void ask_frame_sic(AskFrame *frame)
{
    frame->name = "the SIC, v = (+-1, +-1, +-1) / sqrt3, in Q(sqrt3)";
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
        {
            frame->vector[outcome][axis] =
                ask_number(sim_rational(0ll, 1ll), sim_rational(s_ask_signs[outcome][axis], 3ll));
        }
    }
}

AskNumber ask_dot(const AskNumber *left, const AskNumber *right)
{
    AskNumber total = ask_fraction(0ll, 1ll);
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        total = ask_number_sum(total, ask_number_product(left[axis], right[axis]));
    }
    return total;
}

// it is an ask, and a complete one whose frame sum v v^T is c I. A state comes back as r = (4 / c) sum p v
int ask_frame_open(SimResults *results, AskFrame *frame, AskNumber *length_square)
{
    int sums_zero = 1;
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        AskNumber total = ask_fraction(0ll, 1ll);
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            total = ask_number_sum(total, frame->vector[outcome][axis]);
        }
        sums_zero = sums_zero && (ask_number_sign(total) == 0);
    }
    sim_check(results, sums_zero, "the ask's operators sum to the identity (the vectors sum to 0)");
    int positive = 1;
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        const AskNumber square = ask_dot(frame->vector[outcome], frame->vector[outcome]);
        positive = positive && (ask_number_sign(ask_number_difference(ask_fraction(1ll, 1ll), square)) >= 0);
        *length_square = square;
    }
    sim_check(results, positive, "every operator of the ask is positive (|v|^2 at most 1)");
    int identity = 1;
    AskNumber diagonal = ask_fraction(0ll, 1ll);
    for (unsigned int row = 0u; row < ASK_AXES; row += 1u)
    {
        for (unsigned int column = 0u; column < ASK_AXES; column += 1u)
        {
            AskNumber entry = ask_fraction(0ll, 1ll);
            for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
            {
                entry = ask_number_sum(entry,
                                       ask_number_product(frame->vector[outcome][row], frame->vector[outcome][column]));
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
    sim_check(results, identity, "the ask's frame is a multiple of the identity, so it is complete");
    frame->factor = sim_rational(0ll, 1ll);
    if (identity != 0)
    {
        frame->factor = sim_rational_product(sim_rational(4ll, 1ll), sim_rational_reciprocal(diagonal.rational));
    }
    return identity;
}

void ask_answers(const AskFrame *frame, const AskNumber *bloch, AskNumber *answer)
{
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        answer[outcome] = ask_number_product(
            ask_fraction(1ll, 4ll), ask_number_sum(ask_fraction(1ll, 1ll), ask_dot(bloch, frame->vector[outcome])));
    }
}

void ask_state_from(const AskFrame *frame, const AskNumber *answer, AskNumber *bloch)
{
    const AskNumber factor = ask_number(frame->factor, sim_rational(0ll, 1ll));
    for (unsigned int axis = 0u; axis < ASK_AXES; axis += 1u)
    {
        AskNumber total = ask_fraction(0ll, 1ll);
        for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
        {
            total = ask_number_sum(total, ask_number_product(answer[outcome], frame->vector[outcome][axis]));
        }
        bloch[axis] = ask_number_product(factor, total);
    }
}

// the crossing rule's weight for outcome i on the ask "+axis": 1/2 + (c^-1 . 2) v_i, from sum p = 1
AskNumber ask_weight(const AskFrame *frame, unsigned int outcome, unsigned int axis)
{
    const AskNumber half_factor =
        ask_number(sim_rational_product(frame->factor, sim_rational(1ll, 2ll)), sim_rational(0ll, 1ll));
    return ask_number_sum(ask_fraction(1ll, 2ll), ask_number_product(half_factor, frame->vector[outcome][axis]));
}

AskNumber ask_cross(const AskFrame *frame, const AskNumber *answer, unsigned int axis)
{
    AskNumber total = ask_fraction(0ll, 1ll);
    for (unsigned int outcome = 0u; outcome < ASK_OUTCOMES; outcome += 1u)
    {
        total = ask_number_sum(total, ask_number_product(answer[outcome], ask_weight(frame, outcome, axis)));
    }
    return total;
}

int ask_is_probability(AskNumber value)
{
    return (ask_number_sign(value) >= 0) &&
           (ask_number_sign(ask_number_difference(ask_fraction(1ll, 1ll), value)) >= 0);
}

int ask_valid(const AskFrame *frame, const AskNumber *answer)
{
    AskNumber bloch[ASK_AXES];
    ask_state_from(frame, answer, bloch);
    return ask_number_sign(ask_number_difference(ask_fraction(1ll, 1ll), ask_dot(bloch, bloch))) >= 0;
}
