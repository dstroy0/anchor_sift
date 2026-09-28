// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_lexer.c: the lexer and tokens
#include "qasm_internal.h"

// ---------------------------------------------------------------------------------------------------------------
// the lexer

static int qasm_is_letter(char c)
{
    return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')) || (c == '_');
}

static int qasm_is_digit(char c)
{
    return (c >= '0') && (c <= '9');
}

int qasm_lex(QasmParser *parser)
{
    const char *const text = parser->text;
    const size_t length = parser->length;
    size_t capacity = 1024u;
    parser->tokens = (QasmToken *)malloc(capacity * sizeof(QasmToken));
    if (!QASM_CHECK(parser->tokens != NULL, parser, parser->error))
    {
        parser->failed = 1;
        return 0;
    }
    unsigned int line = 1u;
    unsigned int column = 1u;
    size_t at = 0u;
    while (1)
    {
        // spaces and comments
        while (at < length)
        {
            const char c = text[at];
            if (c == '\n')
            {
                line += 1u;
                column = 1u;
                at += 1u;
            }
            else if ((c == ' ') || (c == '\t') || (c == '\r'))
            {
                column += 1u;
                at += 1u;
            }
            else if ((c == '/') && ((at + 1u) < length) && (text[at + 1u] == '/'))
            {
                while ((at < length) && (text[at] != '\n'))
                {
                    at += 1u;
                }
            }
            else if ((c == '/') && ((at + 1u) < length) && (text[at + 1u] == '*'))
            {
                at += 2u;
                column += 2u;
                while ((at < length) && !((text[at] == '*') && ((at + 1u) < length) && (text[at + 1u] == '/')))
                {
                    if (text[at] == '\n')
                    {
                        line += 1u;
                        column = 1u;
                    }
                    else
                    {
                        column += 1u;
                    }
                    at += 1u;
                }
                at += 2u;
                column += 2u;
            }
            else
            {
                break;
            }
        }
        if (parser->token_count + 1u >= capacity)
        {
            capacity *= 2u;
            QasmToken *const grown = (QasmToken *)realloc(parser->tokens, capacity * sizeof(QasmToken));
            if (!QASM_CHECK(grown != NULL, parser, parser->error))
            {
                parser->failed = 1;
                return 0;
            }
            parser->tokens = grown;
        }
        QasmToken *const token = &parser->tokens[parser->token_count];
        token->start = (unsigned int)at;
        token->line = line;
        token->column = column;
        if (at >= length)
        {
            token->kind = QASM_TOKEN_END;
            token->length = 0u;
            parser->token_count += 1u;
            return 1;
        }
        const char c = text[at];
        size_t end = at + 1u;
        if (qasm_is_letter(c))
        {
            while ((end < length) && (qasm_is_letter(text[end]) || qasm_is_digit(text[end])))
            {
                end += 1u;
            }
            token->kind = QASM_TOKEN_IDENT;
        }
        else if (qasm_is_digit(c) || ((c == '.') && ((at + 1u) < length) && qasm_is_digit(text[at + 1u])))
        {
            end = at;
            while ((end < length) && qasm_is_digit(text[end]))
            {
                end += 1u;
            }
            if ((end < length) && (text[end] == '.'))
            {
                end += 1u;
                while ((end < length) && qasm_is_digit(text[end]))
                {
                    end += 1u;
                }
            }
            if ((end < length) && ((text[end] == 'e') || (text[end] == 'E')))
            {
                size_t exponent = end + 1u;
                if ((exponent < length) && ((text[exponent] == '+') || (text[exponent] == '-')))
                {
                    exponent += 1u;
                }
                if ((exponent < length) && qasm_is_digit(text[exponent]))
                {
                    end = exponent;
                    while ((end < length) && qasm_is_digit(text[end]))
                    {
                        end += 1u;
                    }
                }
            }
            token->kind = QASM_TOKEN_NUMBER;
        }
        else if (c == '"')
        {
            while ((end < length) && (text[end] != '"') && (text[end] != '\n'))
            {
                end += 1u;
            }
            if ((end >= length) || (text[end] != '"'))
            {
                token->kind = QASM_TOKEN_SYMBOL;
                token->length = 1u;
                parser->token_count += 1u;
                qasm_error(parser, token, "a string is not closed on its line");
                return 0;
            }
            end += 1u;
            token->kind = QASM_TOKEN_STRING;
        }
        else if ((c == '-') && ((at + 1u) < length) && (text[at + 1u] == '>'))
        {
            end = at + 2u;
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else if ((c == '=') && ((at + 1u) < length) && (text[at + 1u] == '='))
        {
            end = at + 2u;
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else if (strchr(";,()[]{}+-*/^", c) != NULL)
        {
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else
        {
            token->kind = QASM_TOKEN_SYMBOL;
            token->length = 1u;
            parser->token_count += 1u;
            qasm_error(parser, token, "'%c' is not part of OpenQASM 2.0", c);
            return 0;
        }
        token->length = (unsigned int)(end - at);
        column += token->length;
        at = end;
        parser->token_count += 1u;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// the parser's reading of tokens

const QasmToken *qasm_peek(const QasmParser *parser)
{
    return &parser->tokens[parser->at];
}

int qasm_token_is(const QasmParser *parser, const QasmToken *token, const char *text)
{
    const size_t length = strlen(text);
    return (token->length == length) && (strncmp(parser->text + token->start, text, length) == 0);
}

int qasm_tokens_equal(const QasmParser *parser, const QasmToken *left, const QasmToken *right)
{
    return (left->length == right->length) &&
           (strncmp(parser->text + left->start, parser->text + right->start, left->length) == 0);
}

int qasm_accept(QasmParser *parser, const char *text)
{
    const QasmToken *const token = qasm_peek(parser);
    if ((token->kind != QASM_TOKEN_END) && (token->kind != QASM_TOKEN_STRING) && qasm_token_is(parser, token, text))
    {
        parser->at += 1u;
        return 1;
    }
    return 0;
}

int qasm_expect(QasmParser *parser, const char *text)
{
    if (qasm_accept(parser, text))
    {
        return 1;
    }
    qasm_error(parser, qasm_peek(parser), "'%s' was expected here", text);
    return 0;
}

void qasm_token_name(const QasmParser *parser, const QasmToken *token, char *name)
{
    const unsigned int length = (token->length < (QASM_NAME_CAPACITY - 1u)) ? token->length : (QASM_NAME_CAPACITY - 1u);
    memcpy(name, parser->text + token->start, length);
    name[length] = '\0';
}

int qasm_expect_ident(QasmParser *parser, char *name, unsigned int *token_at)
{
    const QasmToken *const token = qasm_peek(parser);
    if (token->kind != QASM_TOKEN_IDENT)
    {
        qasm_error(parser, token, "a name was expected here");
        return 0;
    }
    if (token->length >= QASM_NAME_CAPACITY)
    {
        qasm_error(parser, token, "a name past %u characters is not read", QASM_NAME_CAPACITY - 1u);
        return 0;
    }
    if (name != NULL)
    {
        qasm_token_name(parser, token, name);
    }
    if (token_at != NULL)
    {
        *token_at = parser->at;
    }
    parser->at += 1u;
    return 1;
}

int qasm_expect_count(QasmParser *parser, unsigned int *count)
{
    const QasmToken *const token = qasm_peek(parser);
    unsigned long long value = 0ull;
    int digits = (token->kind == QASM_TOKEN_NUMBER);
    for (unsigned int at = 0u; digits && (at < token->length); at += 1u)
    {
        const char c = parser->text[token->start + at];
        digits = qasm_is_digit(c) && (value < 100000000ull);
        value = (value * 10ull) + (unsigned long long)(c - '0');
    }
    if (!digits)
    {
        qasm_error(parser, token, "a whole number was expected here");
        return 0;
    }
    *count = (unsigned int)value;
    parser->at += 1u;
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------
// expressions: + - * / unary minus, parentheses, pi, numbers and the gate's parameters

int qasm_number(QasmParser *parser, const QasmToken *token, QasmAngle *value)
{
    const char *const text = parser->text + token->start;
    unsigned int mantissa_end = 0u;
    while ((mantissa_end < token->length) && (text[mantissa_end] != 'e') && (text[mantissa_end] != 'E'))
    {
        mantissa_end += 1u;
    }
    unsigned int places = 0u;
    int seen_point = 0;
    for (unsigned int at = 0u; at < mantissa_end; at += 1u)
    {
        if (text[at] == '.')
        {
            seen_point = 1;
        }
        else if (seen_point != 0)
        {
            places += 1u;
        }
    }
    if (places > 200u)
    {
        qasm_error(parser, token, "a number past 200 places is not read");
        return 0;
    }
    long long exponent = 0;
    if (mantissa_end < token->length)
    {
        exponent = strtoll(text + mantissa_end + 1u, NULL, 10);
        if ((exponent > 300) || (exponent < -300))
        {
            qasm_error(parser, token, "an exponent past 300 is not read");
            return 0;
        }
    }
    QasmFraction number;
    if (!qasm_exact_ok(parser, anchor_exact_from_decimal(text, mantissa_end, places, &number.num)))
    {
        return 0;
    }
    qasm_exact_set(&number.den, 1ull, 0);
    if (!qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.den, places)))
    {
        return 0;
    }
    if ((exponent > 0) && !qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.num, (uint32_t)exponent)))
    {
        return 0;
    }
    if ((exponent < 0) && !qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.den, (uint32_t)(-exponent))))
    {
        return 0;
    }
    if (!qasm_fraction_reduce(parser, &number))
    {
        return 0;
    }
    value->a = number;
    qasm_fraction_integer(&value->b, 0);
    return 1;
}
