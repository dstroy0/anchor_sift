// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_read.c: declarations, statements, the header and the reader
#include "qasm_internal.h"

static int qasm_declare(QasmParser *parser, int quantum)
{
    char name[QASM_NAME_CAPACITY];
    const QasmToken *const token = qasm_peek(parser);
    unsigned int size = 0u;
    if (!qasm_expect_ident(parser, name, NULL) || !qasm_expect(parser, "[") || !qasm_expect_count(parser, &size) ||
        !qasm_expect(parser, "]") || !qasm_expect(parser, ";"))
    {
        return 0;
    }
    QasmRegister *const registers = (quantum != 0) ? parser->qregs : parser->cregs;
    unsigned int *const count = (quantum != 0) ? &parser->qreg_count : &parser->creg_count;
    unsigned int *const total = (quantum != 0) ? &parser->circuit->qubits : &parser->circuit->clbits;
    const unsigned int maximum = (quantum != 0) ? QASM_QUBITS_MAX : QASM_CLBITS_MAX;
    if ((qasm_register(parser->qregs, parser->qreg_count, name) != NULL) ||
        (qasm_register(parser->cregs, parser->creg_count, name) != NULL))
    {
        qasm_refuse(parser, token, "the register '%s' is declared twice", name);
        return 0;
    }
    if ((size == 0u) || (*count == QASM_REGISTERS_MAX) || ((*total + size) > maximum))
    {
        qasm_refuse(parser, token,
                    (quantum != 0) ? "past %u qubits: the index names a record by 32 bits"
                                   : "past %u clbits: an outcome is one 64-bit word",
                    maximum);
        return 0;
    }
    snprintf(registers[*count].name, QASM_NAME_CAPACITY, "%s", name);
    registers[*count].offset = *total;
    registers[*count].size = size;
    *count += 1u;
    *total += size;
    return 1;
}

static int qasm_define(QasmParser *parser)
{
    if (parser->definition_count == parser->definition_capacity)
    {
        const unsigned int capacity = (parser->definition_capacity == 0u) ? 32u : (parser->definition_capacity * 2u);
        QasmDefinition *const grown =
            (QasmDefinition *)realloc(parser->definitions, (size_t)capacity * sizeof(QasmDefinition));
        if (!QASM_CHECK(grown != NULL, parser, parser->error))
        {
            parser->failed = 1;
            return 0;
        }
        parser->definitions = grown;
        parser->definition_capacity = capacity;
    }
    QasmDefinition *const definition = &parser->definitions[parser->definition_count];
    memset(definition, 0, sizeof(*definition));
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_expect_ident(parser, definition->name, NULL))
    {
        return 0;
    }
    if (qasm_definition(parser, definition->name) != NULL)
    {
        qasm_refuse(parser, token, "the gate '%s' is defined twice", definition->name);
        return 0;
    }
    if (qasm_accept(parser, "(") && !qasm_accept(parser, ")"))
    {
        do
        {
            if (definition->params == QASM_GATE_PARAMS_MAX)
            {
                qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u parameters", QASM_GATE_PARAMS_MAX);
                return 0;
            }
            if (!qasm_expect_ident(parser, NULL, &definition->param_token[definition->params]))
            {
                return 0;
            }
            definition->params += 1u;
        } while (qasm_accept(parser, ","));
        if (!qasm_expect(parser, ")"))
        {
            return 0;
        }
    }
    do
    {
        if (definition->args == QASM_GATE_ARGS_MAX)
        {
            qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u qubits", QASM_GATE_ARGS_MAX);
            return 0;
        }
        if (!qasm_expect_ident(parser, NULL, &definition->arg_token[definition->args]))
        {
            return 0;
        }
        definition->args += 1u;
    } while (qasm_accept(parser, ","));
    if (!qasm_expect(parser, "{"))
    {
        return 0;
    }
    definition->body_start = parser->at;
    while ((qasm_peek(parser)->kind != QASM_TOKEN_END) && !qasm_token_is(parser, qasm_peek(parser), "}"))
    {
        parser->at += 1u;
    }
    definition->body_end = parser->at;
    if (!qasm_expect(parser, "}"))
    {
        return 0;
    }
    parser->definition_count += 1u;
    return 1;
}

// statements up to the token `end`: inside a definition (scope set) only gates and barriers
int qasm_statements(QasmParser *parser, const QasmScope *scope, unsigned int end)
{
    const int top = (scope == NULL) || (scope->definition == NULL);
    while ((parser->failed == 0) && (parser->at < end) && (qasm_peek(parser)->kind != QASM_TOKEN_END))
    {
        const QasmToken *const token = qasm_peek(parser);
        if (token->kind != QASM_TOKEN_IDENT)
        {
            qasm_refuse(parser, token, "a statement was expected here");
            return 0;
        }
        if (qasm_token_is(parser, token, "barrier"))
        {
            parser->at += 1u;
            while ((qasm_peek(parser)->kind != QASM_TOKEN_END) && !qasm_accept(parser, ";"))
            {
                parser->at += 1u;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "include"))
        {
            parser->at += 1u;
            const QasmToken *const file = qasm_peek(parser);
            if ((file->kind != QASM_TOKEN_STRING) || !qasm_token_is(parser, file, "\"qelib1.inc\""))
            {
                qasm_refuse(parser, file, "only \"qelib1.inc\" is included: its gates are built in");
                return 0;
            }
            parser->at += 1u;
            if (!qasm_expect(parser, ";"))
            {
                return 0;
            }
            continue;
        }
        if (top && (qasm_token_is(parser, token, "qreg") || qasm_token_is(parser, token, "creg")))
        {
            parser->at += 1u;
            if (!qasm_declare(parser, qasm_token_is(parser, token, "qreg")))
            {
                return 0;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "gate"))
        {
            parser->at += 1u;
            if (!qasm_define(parser))
            {
                return 0;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "measure"))
        {
            parser->at += 1u;
            if (!qasm_measure(parser))
            {
                return 0;
            }
            continue;
        }
        if (qasm_token_is(parser, token, "opaque") || qasm_token_is(parser, token, "reset") ||
            qasm_token_is(parser, token, "if") || qasm_token_is(parser, token, "measure") ||
            qasm_token_is(parser, token, "OPENQASM") || qasm_token_is(parser, token, "include") ||
            qasm_token_is(parser, token, "gate") || qasm_token_is(parser, token, "qreg") ||
            qasm_token_is(parser, token, "creg"))
        {
            char name[QASM_NAME_CAPACITY];
            qasm_token_name(parser, token, name);
            qasm_refuse(parser, token,
                        top ? "'%s' is not read: only unitary gates and a final measure are"
                            : "'%s' is not read inside a gate definition",
                        name);
            return 0;
        }
        if (!qasm_application(parser, scope))
        {
            return 0;
        }
    }
    return parser->failed == 0;
}

static int qasm_header(QasmParser *parser)
{
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_token_is(parser, token, "OPENQASM"))
    {
        qasm_refuse(parser, token, "a program opens with OPENQASM 2.0;");
        return 0;
    }
    parser->at += 1u;
    const QasmToken *const version = qasm_peek(parser);
    if ((version->kind != QASM_TOKEN_NUMBER) ||
        !(qasm_token_is(parser, version, "2.0") || qasm_token_is(parser, version, "2")))
    {
        qasm_refuse(parser, version, "only OpenQASM 2.0 is read");
        return 0;
    }
    parser->at += 1u;
    return qasm_expect(parser, ";");
}

long qasm_read(const QasmReadRequest *request, QasmCircuit *circuit)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_ERROR;
    }
    EngineError *const error = request->error;
    if (!QASM_CHECK((circuit != NULL) && ((request->text != NULL) || (request->path != NULL)), request, error))
    {
        return QASM_ERROR;
    }
    memset(circuit, 0, sizeof(*circuit));
    char *owned = NULL;
    const char *text = request->text;
    size_t length = request->length;
    if (text == NULL)
    {
        FILE *const file = fopen(request->path, "rb");
        if (!engine_io_check(file != NULL, ENGINE_MODULE_QASM, __LINE__, request->path, error))
        {
            if (request->reason != NULL)
            {
                snprintf(request->reason, request->reason_capacity, "%s: could not be opened", request->path);
            }
            return QASM_ERROR;
        }
        size_t capacity = 65536u;
        owned = (char *)malloc(capacity);
        length = 0u;
        while (owned != NULL)
        {
            const size_t got = fread(owned + length, 1u, capacity - length, file);
            length += got;
            if (length < capacity)
            {
                break;
            }
            capacity *= 2u;
            char *const grown = (char *)realloc(owned, capacity);
            if (grown == NULL)
            {
                free(owned);
                owned = NULL;
            }
            owned = grown;
        }
        fclose(file);
        if (!QASM_CHECK(owned != NULL, request, error))
        {
            return QASM_ERROR;
        }
        text = owned;
    }
    QasmParser *const parser = (QasmParser *)calloc(1u, sizeof(QasmParser));
    if (!QASM_CHECK(parser != NULL, request, error))
    {
        free(owned);
        return QASM_ERROR;
    }
    parser->path = (request->path != NULL) ? request->path : "<text>";
    parser->text = text;
    parser->length = length;
    parser->circuit = circuit;
    parser->reason = request->reason;
    parser->reason_capacity = request->reason_capacity;
    parser->error = error;
    int ok = qasm_fixed_constants(parser) && qasm_lex(parser) && qasm_header(parser) &&
             qasm_statements(parser, NULL, 0xFFFFFFFFu);
    if (ok && (circuit->qubits == 0u))
    {
        qasm_refuse(parser, qasm_peek(parser), "no qreg is declared");
        ok = 0;
    }
    if (ok && (circuit->measured == 0u))
    {
        // no measure: every qubit is read, qubit i into clbit i
        if (circuit->qubits > QASM_CLBITS_MAX)
        {
            qasm_refuse(parser, qasm_peek(parser), "no measure, and more qubits than an outcome holds");
            ok = 0;
        }
        for (unsigned int qubit = 0u; ok && (qubit < circuit->qubits); qubit += 1u)
        {
            circuit->measure[qubit] = qubit + 1u;
        }
        if (ok)
        {
            circuit->measured = circuit->qubits;
            circuit->clbits = (circuit->clbits > circuit->qubits) ? circuit->clbits : circuit->qubits;
            circuit->measured_all_by_default = 1u;
        }
    }
    free(parser->tokens);
    free(parser->definitions);
    free(parser);
    free(owned);
    if (!ok)
    {
        qasm_release(circuit);
        return QASM_ERROR;
    }
    return 0L;
}

void qasm_release(QasmCircuit *circuit)
{
    if (circuit == NULL)
    {
        return;
    }
    free(circuit->gates);
    circuit->gates = NULL;
    circuit->gate_count = 0u;
    circuit->gate_capacity = 0u;
}

void qasm_bitstring(const QasmCircuit *circuit, unsigned long long outcome, char *text, size_t capacity)
{
    size_t at = 0u;
    for (unsigned int clbit = circuit->clbits; (clbit > 0u) && ((at + 1u) < capacity); clbit -= 1u)
    {
        text[at] = (((outcome >> (clbit - 1u)) & 1ull) != 0ull) ? '1' : '0';
        at += 1u;
    }
    if (capacity != 0u)
    {
        text[at] = '\0';
    }
}

void qasm_units_decimal(const unsigned int units[QASM_WIDE_LIMBS], unsigned int places, char *text, size_t capacity)
{
    AnchorExactInteger value;
    AnchorExactInteger scale;
    AnchorExactInteger integer_part;
    AnchorExactInteger part;
    qasm_wide_to_exact(units, &value);
    qasm_exact_power_of_two(&scale, 2u * QASM_FRACTION_BITS);
    if ((anchor_exact_divide(&value, &scale, &integer_part, &part) != ANCHOR_EXACT_OK) ||
        (anchor_exact_scale_by_ten(&part, places) != ANCHOR_EXACT_OK) ||
        (anchor_exact_divide(&part, &scale, &part, &value) != ANCHOR_EXACT_OK))
    {
        snprintf(text, capacity, "?");
        return;
    }
    char digits[64];
    unsigned long long fraction = qasm_exact_small(&part);
    for (unsigned int at = places; at > 0u; at -= 1u)
    {
        digits[at - 1u] = (char)('0' + (fraction % 10ull));
        fraction /= 10ull;
    }
    digits[(places < 63u) ? places : 63u] = '\0';
    snprintf(text, capacity, "%llu.%s", qasm_exact_small(&integer_part), digits);
}
