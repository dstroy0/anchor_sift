// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_statements.c: definitions, registers, application and measurement
#include "qasm_internal.h"

// ---------------------------------------------------------------------------------------------------------------
// statements

const QasmDefinition *qasm_definition(const QasmParser *parser, const char *name)
{
    for (unsigned int at = 0u; at < parser->definition_count; at += 1u)
    {
        if (strcmp(parser->definitions[at].name, name) == 0)
        {
            return &parser->definitions[at];
        }
    }
    return NULL;
}

const QasmRegister *qasm_register(const QasmRegister *registers, unsigned int count, const char *name)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        if (strcmp(registers[at].name, name) == 0)
        {
            return &registers[at];
        }
    }
    return NULL;
}

// one gate on resolved qubits: a definition's body, or a built-in
static int qasm_apply(QasmParser *parser, const char *name, const QasmToken *token, const QasmAngle *angles,
                      unsigned int angle_count, const unsigned int *qubits, unsigned int qubit_count)
{
    for (unsigned int one = 0u; one < qubit_count; one += 1u)
    {
        if (parser->measured_qubit[qubits[one]] != 0u)
        {
            qasm_error(parser, token, "a gate follows the measure of qubit %u: only a final measure is read",
                        qubits[one]);
            return 0;
        }
        for (unsigned int two = one + 1u; two < qubit_count; two += 1u)
        {
            if (qubits[one] == qubits[two])
            {
                qasm_error(parser, token, "the gate '%s' names qubit %u twice", name, qubits[one]);
                return 0;
            }
        }
    }
    const QasmDefinition *const definition = qasm_definition(parser, name);
    if (definition != NULL)
    {
        if ((angle_count != definition->params) || (qubit_count != definition->args))
        {
            qasm_error(parser, token, "the gate '%s' takes %u parameters and %u qubits", name, definition->params,
                        definition->args);
            return 0;
        }
        if (parser->depth >= QASM_EXPAND_DEPTH_MAX)
        {
            qasm_error(parser, token, "gate definitions nest past %u", QASM_EXPAND_DEPTH_MAX);
            return 0;
        }
        const QasmScope inner = {definition, angles, qubits};
        const unsigned int resume = parser->at;
        parser->at = definition->body_start;
        parser->depth += 1u;
        const int ok = qasm_statements(parser, &inner, definition->body_end);
        parser->depth -= 1u;
        parser->at = resume;
        return ok;
    }
    const QasmBuiltin *const builtin = qasm_builtin(name);
    if (builtin == NULL)
    {
        qasm_error(parser, token, "the gate '%s' is not defined", name);
        return 0;
    }
    if ((angle_count != builtin->params) || (qubit_count != builtin->qubits))
    {
        qasm_error(parser, token, "the gate '%s' takes %u parameters and %u qubits", name, builtin->params,
                    builtin->qubits);
        return 0;
    }
    return qasm_lower_gate(parser, name, angles, qubits, token);
}

static int qasm_argument(QasmParser *parser, const QasmRegister *registers, unsigned int count, QasmArgument *argument)
{
    char name[QASM_NAME_CAPACITY];
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_expect_ident(parser, name, NULL))
    {
        return 0;
    }
    argument->reg = qasm_register(registers, count, name);
    if (argument->reg == NULL)
    {
        qasm_error(parser, token, "'%s' is not a register of this kind", name);
        return 0;
    }
    argument->index = -1;
    if (qasm_accept(parser, "["))
    {
        unsigned int index = 0u;
        const QasmToken *const at = qasm_peek(parser);
        if (!qasm_expect_count(parser, &index) || !qasm_expect(parser, "]"))
        {
            return 0;
        }
        if (index >= argument->reg->size)
        {
            qasm_error(parser, at, "%s[%u] is past the register's %u", name, index, argument->reg->size);
            return 0;
        }
        argument->index = (long long)index;
    }
    return 1;
}

int qasm_application(QasmParser *parser, const QasmScope *scope)
{
    const QasmToken *const token = qasm_peek(parser);
    char name[QASM_NAME_CAPACITY];
    if (!qasm_expect_ident(parser, name, NULL))
    {
        return 0;
    }
    QasmAngle *const angles = (QasmAngle *)malloc(QASM_GATE_PARAMS_MAX * sizeof(QasmAngle));
    if (!QASM_CHECK(angles != NULL, parser, parser->error))
    {
        parser->failed = 1;
        return 0;
    }
    unsigned int angle_count = 0u;
    int ok = 1;
    if (qasm_accept(parser, "("))
    {
        if (!qasm_accept(parser, ")"))
        {
            do
            {
                if (angle_count == QASM_GATE_PARAMS_MAX)
                {
                    qasm_error(parser, qasm_peek(parser), "a gate takes at most %u parameters", QASM_GATE_PARAMS_MAX);
                    ok = 0;
                    break;
                }
                ok = qasm_expression(parser, scope, &angles[angle_count]);
                angle_count += 1u;
            } while (ok && qasm_accept(parser, ","));
            ok = ok && qasm_expect(parser, ")");
        }
    }
    unsigned int qubits[QASM_GATE_ARGS_MAX];
    unsigned int qubit_count = 0u;
    if (ok && (scope != NULL) && (scope->definition != NULL))
    {
        // inside a definition: plain argument names
        do
        {
            unsigned int at = 0u;
            const QasmToken *const argument = qasm_peek(parser);
            if (!qasm_expect_ident(parser, NULL, &at))
            {
                ok = 0;
                break;
            }
            unsigned int found = QASM_GATE_ARGS_MAX;
            for (unsigned int arg = 0u; arg < scope->definition->args; arg += 1u)
            {
                if (qasm_tokens_equal(parser, argument, &parser->tokens[scope->definition->arg_token[arg]]))
                {
                    found = arg;
                }
            }
            if ((found == QASM_GATE_ARGS_MAX) || (qubit_count == QASM_GATE_ARGS_MAX))
            {
                qasm_error(parser, argument, "not an argument of this gate");
                ok = 0;
                break;
            }
            qubits[qubit_count] = scope->qubits[found];
            qubit_count += 1u;
        } while (qasm_accept(parser, ","));
        ok =
            ok && qasm_expect(parser, ";") && qasm_apply(parser, name, token, angles, angle_count, qubits, qubit_count);
        free(angles);
        return ok;
    }
    // at the top: register bits, or whole registers broadcast over their common size
    QasmArgument arguments[QASM_GATE_ARGS_MAX];
    unsigned int argument_count = 0u;
    unsigned int broadcast = 0u;
    if (ok)
    {
        do
        {
            if (argument_count == QASM_GATE_ARGS_MAX)
            {
                qasm_error(parser, qasm_peek(parser), "a gate takes at most %u qubits", QASM_GATE_ARGS_MAX);
                ok = 0;
                break;
            }
            const QasmToken *const at = qasm_peek(parser);
            if (!qasm_argument(parser, parser->qregs, parser->qreg_count, &arguments[argument_count]))
            {
                ok = 0;
                break;
            }
            if (arguments[argument_count].index < 0)
            {
                if ((broadcast != 0u) && (broadcast != arguments[argument_count].reg->size))
                {
                    qasm_error(parser, at, "registers of different sizes are applied together");
                    ok = 0;
                    break;
                }
                broadcast = arguments[argument_count].reg->size;
            }
            argument_count += 1u;
        } while (qasm_accept(parser, ","));
        ok = ok && qasm_expect(parser, ";");
    }
    const unsigned int times = (broadcast != 0u) ? broadcast : 1u;
    for (unsigned int time = 0u; ok && (time < times); time += 1u)
    {
        for (unsigned int argument = 0u; argument < argument_count; argument += 1u)
        {
            const long long index = (arguments[argument].index < 0) ? (long long)time : arguments[argument].index;
            qubits[argument] = arguments[argument].reg->offset + (unsigned int)index;
        }
        ok = qasm_apply(parser, name, token, angles, angle_count, qubits, argument_count);
    }
    free(angles);
    return ok;
}

int qasm_measure(QasmParser *parser)
{
    const QasmToken *const token = qasm_peek(parser);
    QasmArgument from;
    QasmArgument into;
    if (!qasm_argument(parser, parser->qregs, parser->qreg_count, &from) || !qasm_expect(parser, "->") ||
        !qasm_argument(parser, parser->cregs, parser->creg_count, &into) || !qasm_expect(parser, ";"))
    {
        return 0;
    }
    if ((from.index < 0) != (into.index < 0))
    {
        qasm_error(parser, token, "a measure takes a register into a register, or a bit into a bit");
        return 0;
    }
    if ((from.index < 0) && (from.reg->size != into.reg->size))
    {
        qasm_error(parser, token, "a measure takes registers of one size");
        return 0;
    }
    const unsigned int times = (from.index < 0) ? from.reg->size : 1u;
    for (unsigned int time = 0u; time < times; time += 1u)
    {
        const unsigned int qubit = from.reg->offset + ((from.index < 0) ? time : (unsigned int)from.index);
        const unsigned int clbit = into.reg->offset + ((into.index < 0) ? time : (unsigned int)into.index);
        if (parser->measured_qubit[qubit] != 0u)
        {
            qasm_error(parser, token, "qubit %u is measured twice", qubit);
            return 0;
        }
        if (parser->clbit_written[clbit] != 0u)
        {
            qasm_error(parser, token, "clbit %u is written twice", clbit);
            return 0;
        }
        parser->measured_qubit[qubit] = 1u;
        parser->clbit_written[clbit] = 1u;
        parser->circuit->measure[qubit] = clbit + 1u;
        parser->circuit->measured += 1u;
    }
    return 1;
}
