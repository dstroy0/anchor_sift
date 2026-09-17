/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file cfg_json.h
 * @brief The .cfg reader: one JSON text cut into a flat run of tokens, in place, with no allocation, so the
 *        compiled tracker and the page read the same file by the same names.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * A .cfg is JSON with one restriction: numbers are integers. A fraction or an exponent is refused where it is
 * read, because nothing the tracker takes is a fraction and a value that silently rounds is a setting nobody
 * asked for.
 *
 * Tokens are laid out in document order. A container's children follow it directly; an object's children
 * alternate key and value. Every token records the token past its whole subtree, so a caller walks siblings by
 * jumping and never recurses.
 *
 * NO FLOATING POINT VALUE IS FORMED.
 */
#ifndef CFG_JSON_H
#define CFG_JSON_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Deepest nesting a .cfg may reach. */
#define CFG_JSON_DEPTH 32u

/** @brief What a token is. */
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

/** @brief One token: a span of the text and where its subtree ends. */
typedef struct
{
    CfgJsonKind kind;   /**< What it is. */
    size_t start;       /**< First byte; a string's first byte inside its quotes. */
    size_t end;         /**< Byte past the last; a string's closing quote. */
    unsigned int count; /**< An object's members or an array's elements; zero otherwise. */
    unsigned int past;  /**< The token after this token's whole subtree. */
} CfgJsonToken;

/** @brief A parse's outcome. */
typedef struct
{
    unsigned int tokens; /**< Tokens written. */
    size_t line;         /**< Where the text was refused, counted from 1, or 0 where it was not. */
    size_t column;       /**< Where the text was refused, counted from 1, or 0 where it was not. */
    const char *reason;  /**< Why it was refused, or NULL where it was not [BORROWS]. */
} CfgJsonParse;

/**
 * @brief Cuts a .cfg into tokens.
 *
 * @param[in]  text   The text [BORROWS].
 * @param[in]  length Its bytes.
 * @param[out] tokens Where the tokens go [BORROWS].
 * @param[in]  room   Tokens that fit.
 * @param[out] parse  The outcome [BORROWS].
 * @return            1 where the whole text is one value and every token fit, 0 otherwise.
 */
int cfg_json_parse(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room, CfgJsonParse *parse);

/**
 * @brief Whether a string token spells a name exactly, with no escape in it.
 *
 * @param[in] text  The text [BORROWS].
 * @param[in] token The token [BORROWS].
 * @param[in] name  The name [BORROWS].
 * @return          1 where it does, 0 otherwise.
 */
int cfg_json_names(const char *text, const CfgJsonToken *token, const char *name);

/**
 * @brief A number token's value as an unsigned integer.
 *
 * @param[in]  text  The text [BORROWS].
 * @param[in]  token The token [BORROWS].
 * @param[out] value The value [BORROWS].
 * @return           1 where the token is a nonnegative integer that fits, 0 otherwise.
 */
int cfg_json_unsigned(const char *text, const CfgJsonToken *token, unsigned long long *value);

/**
 * @brief A string token's text with its escapes resolved, NUL terminated.
 *
 * @param[in]  text  The text [BORROWS].
 * @param[in]  token The token [BORROWS].
 * @param[out] out   Where the string goes [BORROWS].
 * @param[in]  room  Bytes that fit, the terminator included.
 * @return           1 where it fit and every escape is one the scheme takes, 0 otherwise.
 */
int cfg_json_string(const char *text, const CfgJsonToken *token, char *out, size_t room);

/**
 * @brief The member of an object token with a name, found by jumping from member to member.
 *
 * @param[in] text   The text [BORROWS].
 * @param[in] tokens The tokens [BORROWS].
 * @param[in] object The object's token index.
 * @param[in] name   The member's name [BORROWS].
 * @return           The value's token index, or 0 where the object has no such member.
 */
unsigned int cfg_json_member(const char *text, const CfgJsonToken *tokens, unsigned int object, const char *name);

#ifdef __cplusplus
}
#endif

#endif /* CFG_JSON_H */
