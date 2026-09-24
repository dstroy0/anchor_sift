// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CFG_JSON_H
#define CFG_JSON_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CFG_JSON_DEPTH 32u

typedef enum
{
    CFG_JSON_OBJECT = 0,
    CFG_JSON_ARRAY = 1,
    CFG_JSON_STRING = 2,
    CFG_JSON_NUMBER = 3,
    CFG_JSON_TRUE = 4,
    CFG_JSON_FALSE = 5,
    CFG_JSON_NULL = 6
} CfgJsonKind;

typedef struct
{
    CfgJsonKind kind;
    size_t start;
    size_t end;
    unsigned int count;
    unsigned int past;
} CfgJsonToken;

typedef struct
{
    unsigned int tokens;
    size_t line;
    size_t column;
    const char *reason;
} CfgJsonParse;

int cfg_json_parse(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room, CfgJsonParse *parse);

int cfg_json_parse_metadata(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room,
                            CfgJsonParse *parse);

int cfg_json_names(const char *text, const CfgJsonToken *token, const char *name);

int cfg_json_unsigned(const char *text, const CfgJsonToken *token, unsigned long long *value);

int cfg_json_string(const char *text, const CfgJsonToken *token, char *out, size_t room);

unsigned int cfg_json_member(const char *text, const CfgJsonToken *tokens, unsigned int object, const char *name);

#ifdef __cplusplus
}
#endif

#endif
