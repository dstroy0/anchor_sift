/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file cfg_json.h
 * @brief A reader for the driver's .cfg files: JSON holding integers only, tokenized in place.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note A .cfg is JSON with one restriction. A number is an integer, and a fraction or exponent is
 *       refused by name at parse time. Every measured quantity the configuration carries is an
 *       integer in a named unit, voxel sizes in picometers among them. No value arrives rounded.
 * @note The reader allocates nothing. The caller hands it a token array, and each token records a
 *       byte range of the text. A string is read out of the text only when a caller asks for it.
 */
#ifndef CFG_JSON_H
#define CFG_JSON_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Deepest nesting of objects and arrays the reader accepts. Deeper text is refused. */
#define CFG_JSON_DEPTH 32u

/** @brief What one token holds. */
typedef enum
{
    CFG_JSON_OBJECT = 0, /**< An object. Its members follow it as name then value tokens. */
    CFG_JSON_ARRAY = 1,  /**< An array. Its elements follow it. */
    CFG_JSON_STRING = 2, /**< A string, a member name included. The range excludes the quotes. */
    CFG_JSON_NUMBER = 3, /**< An integer, optionally negative. */
    CFG_JSON_TRUE = 4,   /**< The literal true. */
    CFG_JSON_FALSE = 5,  /**< The literal false. */
    CFG_JSON_NULL = 6    /**< The literal null. */
} CfgJsonKind;

/**
 * @brief One value, or one member name, as a byte range of the text.
 *
 * @note Tokens are laid out in text order with every child after its parent. The children of a
 *       token are the tokens from its index plus one up to `past`. A caller skips a whole value
 *       by jumping to `past`.
 */
typedef struct
{
    CfgJsonKind kind;  /**< What the token holds. */
    size_t start;      /**< First byte of the token in the text. */
    size_t end;        /**< One past the last byte. For a string, the closing quote. */
    unsigned int count; /**< Members of an object or elements of an array, 0 for anything else. */
    unsigned int past; /**< Index one past the last token belonging to this one. */
} CfgJsonToken;

/** @brief How a parse ended, and where it stopped where it failed. */
typedef struct
{
    unsigned int tokens; /**< Tokens written. */
    size_t line;         /**< Line of the failure, counted from 1, or 0 on success. */
    size_t column;       /**< Column of the failure, counted from 1, or 0 on success. */
    const char *reason;  /**< Why the parse failed, or NULL on success. Static text, never freed. */
} CfgJsonParse;

/**
 * @brief Tokenizes a .cfg text into a caller's token array.
 *
 * @param[in]  text   The text [BORROWS].
 * @param[in]  length How many bytes of text.
 * @param[out] tokens Where the tokens are written [BORROWS].
 * @param[in]  room   How many tokens the array holds.
 * @param[out] parse  How the parse ended [BORROWS].
 * @return            1 where the whole text is one well formed value, 0 otherwise.
 * @note The text must hold exactly one value, and anything after it but whitespace is refused.
 *       Whitespace is a space, tab, line feed or carriage return.
 * @note On a return of 0 `parse` names the reason and the line and column where reading stopped,
 *       and the tokens written so far are not a complete value.
 */
int cfg_json_parse(const char *text, size_t length, CfgJsonToken *tokens, unsigned int room, CfgJsonParse *parse);

/**
 * @brief Whether a token is a string holding exactly the given name.
 *
 * @param[in] text  The text the token was read from [BORROWS].
 * @param[in] token The token [BORROWS].
 * @param[in] name  The name, NUL terminated [BORROWS].
 * @return          1 where the token is a string equal to `name` byte for byte, 0 otherwise.
 * @note Compares the raw bytes of the text. An escaped character in the text never equals the
 *       character it stands for.
 */
int cfg_json_names(const char *text, const CfgJsonToken *token, const char *name);

/**
 * @brief Reads a number token as an unsigned 64 bit integer.
 *
 * @param[in]  text  The text the token was read from [BORROWS].
 * @param[in]  token The token [BORROWS].
 * @param[out] value Where the value is written [BORROWS].
 * @return           1 where the token is a non-negative number that fits 64 bits, 0 otherwise.
 * @warning `value` is written on a return of 0 as well, holding whatever the digits had reached. A
 *          caller reads it only after a return of 1.
 */
int cfg_json_unsigned(const char *text, const CfgJsonToken *token, unsigned long long *value);

/**
 * @brief Copies a string token out of the text, with its escapes resolved.
 *
 * @param[in]  text  The text the token was read from [BORROWS].
 * @param[in]  token The token [BORROWS].
 * @param[out] out   Where the string is written, NUL terminated [BORROWS].
 * @param[in]  room  How many bytes `out` holds, the terminator included.
 * @return           1 where the whole string was copied, 0 where the token is not a string, an
 *                   escape is one the reader does not resolve, or the string does not fit.
 * @note Resolves \\n, \\t, \\", \\\\ and \\/. Any other escape, \\u included, is refused.
 * @note `out` is NUL terminated on every return where `room` is at least 1.
 * @warning A `room` of 0 still writes the terminator to out[0], one byte past a buffer of no bytes.
 *          The return is 0 in that case. Every caller in track_driver.cu passes the size of a fixed
 *          array, which is never 0.
 */
int cfg_json_string(const char *text, const CfgJsonToken *token, char *out, size_t room);

/**
 * @brief Finds the value of a named member of an object.
 *
 * @param[in] text   The text the tokens were read from [BORROWS].
 * @param[in] tokens The token array [BORROWS].
 * @param[in] object Index of the object token.
 * @param[in] name   The member name, NUL terminated [BORROWS].
 * @return           Index of the member's value token, or 0 where the object has no such member or
 *                   `object` is not an object. A value always sits after its object and its name,
 *                   and 0 is therefore never the index of a value.
 * @note A name appearing twice returns the value of the last one.
 */
unsigned int cfg_json_member(const char *text, const CfgJsonToken *tokens, unsigned int object, const char *name);

#ifdef __cplusplus
}
#endif

#endif
