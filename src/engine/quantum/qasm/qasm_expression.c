// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_expression.c: expressions and gate bounds
#include "qasm_internal.h"

static int qasm_primary(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    const QasmToken *const token = qasm_peek(parser);
    if (token->kind == QASM_TOKEN_NUMBER)
    {
        parser->at += 1u;
        return qasm_number(parser, token, value);
    }
    if (qasm_accept(parser, "("))
    {
        return qasm_expression(parser, scope, value) && qasm_expect(parser, ")");
    }
    if (token->kind == QASM_TOKEN_IDENT)
    {
        if (qasm_token_is(parser, token, "pi"))
        {
            parser->at += 1u;
            qasm_angle_rational(value, 0, 1, 1, 1);
            return 1;
        }
        if ((scope != NULL) && (scope->definition != NULL))
        {
            for (unsigned int param = 0u; param < scope->definition->params; param += 1u)
            {
                if (qasm_tokens_equal(parser, token, &parser->tokens[scope->definition->param_token[param]]))
                {
                    parser->at += 1u;
                    *value = scope->values[param];
                    return 1;
                }
            }
        }
        static const char *const functions[] = {"sin", "cos", "tan", "exp", "ln", "sqrt"};
        for (unsigned int at = 0u; at < (sizeof(functions) / sizeof(functions[0])); at += 1u)
        {
            if (qasm_token_is(parser, token, functions[at]))
            {
                qasm_refuse(parser, token,
                            "%s() in a parameter is not read: a parameter is + - * / over numbers and pi",
                            functions[at]);
                return 0;
            }
        }
        char name[QASM_NAME_CAPACITY];
        qasm_token_name(parser, token, name);
        qasm_refuse(parser, token, "'%s' is not a parameter here", name);
        return 0;
    }
    qasm_refuse(parser, token, "a number, pi, a parameter or '(' was expected here");
    return 0;
}

static int qasm_unary(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (qasm_accept(parser, "-"))
    {
        if (!qasm_unary(parser, scope, value))
        {
            return 0;
        }
        value->a.num.sign = -value->a.num.sign;
        value->b.num.sign = -value->b.num.sign;
        return 1;
    }
    if (qasm_accept(parser, "+"))
    {
        return qasm_unary(parser, scope, value);
    }
    if (!qasm_primary(parser, scope, value))
    {
        return 0;
    }
    if (qasm_token_is(parser, qasm_peek(parser), "^") && (qasm_peek(parser)->kind == QASM_TOKEN_SYMBOL))
    {
        qasm_refuse(parser, qasm_peek(parser),
                    "'^' in a parameter is not read: a parameter is + - * / over numbers and pi");
        return 0;
    }
    return 1;
}

static int qasm_term(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (!qasm_unary(parser, scope, value))
    {
        return 0;
    }
    while (1)
    {
        const QasmToken *const token = qasm_peek(parser);
        const int multiply = qasm_accept(parser, "*");
        const int divide = (multiply == 0) && qasm_accept(parser, "/");
        if ((multiply == 0) && (divide == 0))
        {
            return 1;
        }
        QasmAngle right;
        if (!qasm_unary(parser, scope, &right))
        {
            return 0;
        }
        const int left_pi = !qasm_exact_is_zero(&value->b.num);
        const int right_pi = !qasm_exact_is_zero(&right.b.num);
        if (divide != 0)
        {
            if (right_pi || qasm_exact_is_zero(&right.a.num))
            {
                qasm_refuse(parser, token,
                            right_pi ? "a division by a multiple of pi is not read" : "a parameter divides by zero");
                return 0;
            }
            if (!qasm_fraction_divide(parser, &value->a, &right.a, &value->a) ||
                !qasm_fraction_divide(parser, &value->b, &right.a, &value->b))
            {
                return 0;
            }
            continue;
        }
        if (left_pi && right_pi)
        {
            qasm_refuse(parser, token, "pi times pi is not read: an angle is a + b pi");
            return 0;
        }
        // (a1 + b1 pi)(a2 + b2 pi) with b1 b2 = 0
        QasmAngle made;
        QasmFraction cross;
        if (!qasm_fraction_multiply(parser, &value->a, &right.a, &made.a) ||
            !qasm_fraction_multiply(parser, &value->a, &right.b, &made.b) ||
            !qasm_fraction_multiply(parser, &value->b, &right.a, &cross) ||
            !qasm_fraction_add(parser, &made.b, &cross, 0, &made.b))
        {
            return 0;
        }
        *value = made;
    }
}

int qasm_expression(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (!qasm_term(parser, scope, value))
    {
        return 0;
    }
    while (1)
    {
        const int add = qasm_accept(parser, "+");
        const int subtract = (add == 0) && qasm_accept(parser, "-");
        if ((add == 0) && (subtract == 0))
        {
            return 1;
        }
        QasmAngle right;
        if (!qasm_term(parser, scope, &right) || !qasm_angle_add(parser, value, &right, subtract, value))
        {
            return 0;
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------
// the bound

void qasm_wide_to_exact(const unsigned int wide[QASM_WIDE_LIMBS], AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    int any = 0;
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        value->limb[limb] = wide[limb];
        any |= (wide[limb] != 0u);
    }
    value->sign = any ? 1 : 0;
}

static int qasm_exact_to_wide(const AnchorExactInteger *value, unsigned int wide[QASM_WIDE_LIMBS])
{
    for (unsigned int limb = QASM_WIDE_LIMBS; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        if (value->limb[limb] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        wide[limb] = (value->sign > 0) ? value->limb[limb] : 0u;
    }
    return 1;
}

// E' = E' + ceil(delta E' / 2^F) + (delta + T) 2^F, in units of 2^-2F. delta bounds ||M' - M|| in units of 2^-F;
// T bounds the truncations' 2-norm, sqrt(2 N_on) <= 2^ceil((m + 1) / 2) with N_on = 2^m lanes dividing.
static int qasm_bound_gate(QasmParser *parser, const QasmGate *gate)
{
    const unsigned int divides = (gate->kind == QASM_GATE_PAIR) || (gate->kind == QASM_GATE_DIAGONAL);
    if (divides == 0u)
    {
        parser->circuit->exact_gates += 1u;
        return 1;
    }
    parser->circuit->rounded_gates += 1u;
    // a 2x2 whose components are each within one unit: ||.||_2 <= ||.||_F <= sqrt(8) < 3; a diagonal: sqrt(2) < 2
    const unsigned long long delta =
        (gate->exact_entries != 0u) ? 0ull : ((gate->kind == QASM_GATE_PAIR) ? 3ull : 2ull);
    const unsigned int m = parser->circuit->qubits - gate->control_count;
    const unsigned int t_bits = (m + 2u) / 2u;
    AnchorExactInteger bound;
    AnchorExactInteger grown;
    AnchorExactInteger scale;
    AnchorExactInteger remainder;
    AnchorExactInteger local;
    AnchorExactInteger by;
    qasm_wide_to_exact(parser->circuit->bound, &bound);
    qasm_exact_power_of_two(&scale, QASM_FRACTION_BITS);
    qasm_exact_set(&by, delta, 0);
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&bound, &by, &grown)) ||
        !qasm_exact_ok(parser, anchor_exact_divide(&grown, &scale, &grown, &remainder)))
    {
        return 0;
    }
    if (!qasm_exact_is_zero(&remainder))
    {
        AnchorExactInteger one;
        qasm_exact_set(&one, 1ull, 0);
        if (!qasm_exact_ok(parser, anchor_exact_add(&grown, &one, &grown)))
        {
            return 0;
        }
    }
    AnchorExactInteger t;
    qasm_exact_power_of_two(&t, t_bits);
    AnchorExactInteger delta_exact;
    qasm_exact_set(&delta_exact, delta, 0);
    if (!qasm_exact_ok(parser, anchor_exact_add(&t, &delta_exact, &local)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&local, &scale, &local)) ||
        !qasm_exact_ok(parser, anchor_exact_add(&bound, &grown, &bound)) ||
        !qasm_exact_ok(parser, anchor_exact_add(&bound, &local, &bound)))
    {
        return 0;
    }
    // E past 1/2: nothing can be proved, and an amplitude could outgrow its 62-bit field
    AnchorExactInteger half;
    qasm_exact_power_of_two(&half, (2u * QASM_FRACTION_BITS) - 1u);
    if ((anchor_exact_compare(&bound, &half) >= 0) || !qasm_exact_to_wide(&bound, parser->circuit->bound))
    {
        qasm_refuse(parser, &parser->tokens[parser->at],
                    "the proved error bound reaches 1/2 at this gate (%u rounded gates at F = %u): no bitstring could "
                    "be proved",
                    parser->circuit->rounded_gates, QASM_FRACTION_BITS);
        return 0;
    }
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------
// gates

int qasm_push_gate(QasmParser *parser, const QasmGate *gate)
{
    QasmCircuit *const circuit = parser->circuit;
    if (circuit->gate_count == circuit->gate_capacity)
    {
        const unsigned int capacity = (circuit->gate_capacity == 0u) ? 256u : (circuit->gate_capacity * 2u);
        QasmGate *const grown = (QasmGate *)realloc(circuit->gates, (size_t)capacity * sizeof(QasmGate));
        if (!QASM_CHECK(grown != NULL, circuit, parser->error))
        {
            parser->failed = 1;
            return 0;
        }
        circuit->gates = grown;
        circuit->gate_capacity = capacity;
    }
    circuit->gates[circuit->gate_count] = *gate;
    circuit->gate_count += 1u;
    return qasm_bound_gate(parser, gate);
}
