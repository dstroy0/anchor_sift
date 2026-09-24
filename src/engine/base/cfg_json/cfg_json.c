// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cfg_json.h"

#include <string.h>

typedef struct
{
    const char *text;
    size_t length;
    size_t at;
    CfgJsonToken *tokens;
    unsigned int room;
    unsigned int count;
    const char *reason;
    int fractions;
} CfgJsonWalk;

static void cfg_json_space(CfgJsonWalk *walk)
{
    while ((walk->at < walk->length)
           && ((walk->text[walk->at] == ' ') || (walk->text[walk->at] == '\t') || (walk->text[walk->at] == '\n')
               || (walk->text[walk->at] == '\r')))
    {
        walk->at += 1u;
    }
}

static unsigned int cfg_json_token(CfgJsonWalk *walk, CfgJsonKind kind, size_t start, size_t end)
{
    if (walk->count == walk->room)
    {
        walk->reason = "more tokens than the reader holds";
        return 0u;
    }
    const unsigned int slot = walk->count;
    walk->tokens[slot].kind = kind;
    walk->tokens[slot].start = start;
    walk->tokens[slot].end = end;
    walk->tokens[slot].count = 0u;
    walk->tokens[slot].past = slot + 1u;
    walk->count += 1u;
    return slot + 1u;
}

static int cfg_json_literal(CfgJsonWalk *walk, const char *spelled, CfgJsonKind kind)
{
    const size_t size = strlen(spelled);
    const int matches = ((walk->length - walk->at) >= size) && (memcmp(&walk->text[walk->at], spelled, size) == 0);
    walk->reason = matches ? walk->reason : "a value the scheme does not know";
    const unsigned int made = matches ? cfg_json_token(walk, kind, walk->at, walk->at + size) : 0u;
    walk->at += matches ? size : 0u;
    return made != 0u;
}

static int cfg_json_quoted(CfgJsonWalk *walk)
{
    walk->at += 1u;
    const size_t start = walk->at;
    while ((walk->at < walk->length) && (walk->text[walk->at] != '"'))
    {
        const unsigned char byte = (unsigned char)walk->text[walk->at];
        if (byte < 0x20u)
        {
            walk->reason = "a control character inside a string";
            return 0;
        }
        walk->at += (byte == '\\') ? 2u : 1u;
    }
    if (walk->at >= walk->length)
    {
        walk->reason = "a string that never closes";
        return 0;
    }
    const unsigned int made = cfg_json_token(walk, CFG_JSON_STRING, start, walk->at);
    walk->at += 1u;
    return made != 0u;
}

static int cfg_json_number(CfgJsonWalk *walk)
{
    const size_t start = walk->at;
    walk->at += (walk->text[walk->at] == '-') ? 1u : 0u;
    const size_t digits = walk->at;
    while ((walk->at < walk->length) && (walk->text[walk->at] >= '0') && (walk->text[walk->at] <= '9'))
    {
        walk->at += 1u;
    }
    int fraction = (walk->at < walk->length)
                && ((walk->text[walk->at] == '.') || (walk->text[walk->at] == 'e') || (walk->text[walk->at] == 'E'));
    while ((walk->fractions != 0) && (walk->at > digits) && (walk->at < walk->length)
           && (((walk->text[walk->at] >= '0') && (walk->text[walk->at] <= '9')) || (walk->text[walk->at] == '.')
               || (walk->text[walk->at] == 'e') || (walk->text[walk->at] == 'E') || (walk->text[walk->at] == '+')
               || (walk->text[walk->at] == '-')))
    {
        walk->at += 1u;
        fraction = 0;
    }
    if ((walk->at == digits) || fraction)
    {
        walk->reason = fraction ? "a number that is not an integer; a .cfg takes integers only" : "a number with no digits";
        return 0;
    }
    return cfg_json_token(walk, CFG_JSON_NUMBER, start, walk->at) != 0u;
}

static int cfg_json_walk(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room, CfgJsonParse *parse,
                         int fractions)
{
    CfgJsonWalk walk = {text, length, 0u, tokens, room, 0u, NULL, fractions};
    unsigned int open[CFG_JSON_DEPTH];
    unsigned int depth = 0u;
    int expect_key = 0;
    int done = 0;
    cfg_json_space(&walk);
    while ((walk.reason == NULL) && !done)
    {
        cfg_json_space(&walk);
        if (walk.at >= walk.length)
        {
            walk.reason = "the text ends inside a value";
            break;
        }
        const char byte = walk.text[walk.at];
        const CfgJsonToken *const parent = (depth > 0u) ? &walk.tokens[open[depth - 1u]] : NULL;
        const int closes = (parent != NULL)
                        && (((byte == '}') && (parent->kind == CFG_JSON_OBJECT)) || ((byte == ']') && (parent->kind == CFG_JSON_ARRAY)));
        if (closes)
        {
            depth -= 1u;
            walk.tokens[open[depth]].end = walk.at + 1u;
            walk.tokens[open[depth]].past = walk.count;
            walk.at += 1u;
            done = (depth == 0u);
            expect_key = 0;
            cfg_json_space(&walk);
            if (!done && (walk.at < walk.length) && (walk.text[walk.at] == ','))
            {
                walk.at += 1u;
                expect_key = (walk.tokens[open[depth - 1u]].kind == CFG_JSON_OBJECT);
            }
            continue;
        }
        if (expect_key || ((parent != NULL) && (parent->kind == CFG_JSON_OBJECT) && (walk.count == open[depth - 1u] + 1u)))
        {
            if (byte != '"')
            {
                walk.reason = "a member with no quoted name";
                break;
            }
            if (!cfg_json_quoted(&walk))
            {
                break;
            }
            walk.tokens[open[depth - 1u]].count += 1u;
            cfg_json_space(&walk);
            if ((walk.at >= walk.length) || (walk.text[walk.at] != ':'))
            {
                walk.reason = "a name with no colon after it";
                break;
            }
            walk.at += 1u;
            expect_key = 0;
            continue;
        }
        if ((parent != NULL) && (parent->kind == CFG_JSON_ARRAY))
        {
            walk.tokens[open[depth - 1u]].count += 1u;
        }
        if ((byte == '{') || (byte == '['))
        {
            if (depth == CFG_JSON_DEPTH)
            {
                walk.reason = "nesting deeper than a .cfg may go";
                break;
            }
            const unsigned int made = cfg_json_token(&walk, (byte == '{') ? CFG_JSON_OBJECT : CFG_JSON_ARRAY, walk.at, walk.at);
            if (made == 0u)
            {
                break;
            }
            open[depth] = made - 1u;
            depth += 1u;
            walk.at += 1u;
            expect_key = 0;
            continue;
        }
        const int made = (byte == '"')                                  ? cfg_json_quoted(&walk)
                       : ((byte == '-') || ((byte >= '0') && (byte <= '9'))) ? cfg_json_number(&walk)
                       : (byte == 't')                                  ? cfg_json_literal(&walk, "true", CFG_JSON_TRUE)
                       : (byte == 'f')                                  ? cfg_json_literal(&walk, "false", CFG_JSON_FALSE)
                       : (byte == 'n')                                  ? cfg_json_literal(&walk, "null", CFG_JSON_NULL)
                                                                        : (walk.reason = "a value the scheme does not know", 0);
        if (!made)
        {
            break;
        }
        done = (depth == 0u);
        cfg_json_space(&walk);
        if (!done && (walk.at < walk.length) && (walk.text[walk.at] == ','))
        {
            walk.at += 1u;
            expect_key = (walk.tokens[open[depth - 1u]].kind == CFG_JSON_OBJECT);
        }
        else if (!done && (walk.at < walk.length) && (walk.text[walk.at] != '}') && (walk.text[walk.at] != ']'))
        {
            walk.reason = "a value with no comma or close after it";
        }
    }
    cfg_json_space(&walk);
    if ((walk.reason == NULL) && (walk.at != walk.length))
    {
        walk.reason = "text after the value";
    }
    size_t line = 1u;
    size_t column = 1u;
    for (size_t byte = 0u; (walk.reason != NULL) && (byte < walk.at) && (byte < walk.length); byte += 1u)
    {
        const int newline = (walk.text[byte] == '\n');
        line += (size_t)newline;
        column = newline ? 1u : (column + 1u);
    }
    parse->tokens = walk.count;
    parse->reason = walk.reason;
    parse->line = (walk.reason != NULL) ? line : 0u;
    parse->column = (walk.reason != NULL) ? column : 0u;
    return walk.reason == NULL;
}

int cfg_json_parse(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room, CfgJsonParse *parse)
{
    return cfg_json_walk(text, length, tokens, room, parse, 0);
}

int cfg_json_parse_metadata(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room,
                            CfgJsonParse *parse)
{
    return cfg_json_walk(text, length, tokens, room, parse, 1);
}

int cfg_json_names(const char *text, const CfgJsonToken *token, const char *name)
{
    const size_t size = strlen(name);
    return (token->kind == CFG_JSON_STRING) && ((token->end - token->start) == size)
        && (memcmp(&text[token->start], name, size) == 0);
}

int cfg_json_unsigned(const char *text, const CfgJsonToken *token, unsigned long long *value)
{
    unsigned long long total = 0ULL;
    int fits = (token->kind == CFG_JSON_NUMBER) && (text[token->start] != '-');
    for (size_t at = token->start; fits && (at < token->end); at += 1u)
    {
        const unsigned long long digit = (unsigned long long)(text[at] - '0');
        fits = (total <= ((~0ULL - digit) / 10ULL));
        total = (total * 10ULL) + digit;
    }
    *value = total;
    return fits;
}

int cfg_json_string(const char *text, const CfgJsonToken *token, char *out, size_t room)
{
    size_t written = 0u;
    int good = (token->kind == CFG_JSON_STRING) && (room > 0u);
    for (size_t at = token->start; good && (at < token->end); at += 1u)
    {
        const char byte = text[at];
        const int escaped = (byte == '\\');
        const char next = escaped ? text[at + 1u] : byte;
        const char resolved = !escaped      ? byte
                            : (next == 'n') ? '\n'
                            : (next == 't') ? '\t'
                            : ((next == '"') || (next == '\\') || (next == '/')) ? next
                                                                                : '\0';
        good = (resolved != '\0') && (written + 1u < room);
        out[written] = resolved;
        written += (size_t)good;
        at += (size_t)escaped;
    }
    out[(written < room) ? written : 0u] = '\0';
    return good;
}

unsigned int cfg_json_member(const char *text, const CfgJsonToken *tokens, unsigned int object, const char *name)
{
    unsigned int found = 0u;
    unsigned int key = object + 1u;
    for (unsigned int member = 0u; (tokens[object].kind == CFG_JSON_OBJECT) && (member < tokens[object].count); member += 1u)
    {
        const unsigned int value = key + 1u;
        found = cfg_json_names(text, &tokens[key], name) ? value : found;
        key = tokens[value].past;
    }
    return found;
}
