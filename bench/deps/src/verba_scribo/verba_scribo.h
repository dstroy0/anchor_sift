/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file verba_scribo.h
 * @brief Text and number formatting, the limits, and one table per kind of thing written.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Five tables rather than one, each with the arguments its own entries read. A call carries the
 *       destination and the value it is placing, and nothing else. Writing a character does not pass
 *       a double, a base and a column count it will never look at.
 * @note Every writing entry takes the offset to write at and returns the offset past what it wrote, so calls chain.
 * @note An entry that will not fit returns args->cap, which every later entry then reads as no room left.
 * @note finish stores the terminator and reports the length. Nothing before it terminates the buffer.
 */
#ifndef MMGR_VERBA_SCRIBO_H
#define MMGR_VERBA_SCRIBO_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Expands to 18u, the most significant digits mmgr_verba_g will keep.
 *
 * @note A larger args->sig is held here. An args->sig of 0 is taken as 1.
 */
#define MMGR_G_MAX_SIG 18u

/**
 * @brief Expands to 18u, the most digits after the point mmgr_verba_fixed will write.
 *
 * @note A larger args->decimals is held here. An args->decimals of 0 writes no point at all.
 */
#define MMGR_FIXED_MAX_DECIMALS 18u

/**
 * @brief Arguments for the entries that write text into a buffer.
 *
 * @note put_n writes text_len bytes. put measures the text when text_len is 0 and takes it as given
 *       otherwise. put_clip, xml and json read text and leave text_len alone.
 * @warning out must be writable for cap bytes. A byte is always held back for the terminator finish
 *          stores.
 */
typedef struct
{
    char *const out;        /**< Destination buffer [BORROWS]. */
    const size_t cap;       /**< Bytes available in out. */
    const size_t at;        /**< Offset to write at. */
    const char *const text; /**< Text to write [BORROWS]. */
    const size_t text_len;  /**< Bytes of text put_n writes, and the length put takes when non-zero. */
} VerbaTextusCfg;

/**
 * @brief Type of the verba_textus dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the five members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    size_t (*put_n)(const VerbaTextusCfg *args);    /**< Writes a counted run of text. */
    size_t (*put)(const VerbaTextusCfg *args);      /**< Writes a terminated string, measuring it first. */
    size_t (*put_clip)(const VerbaTextusCfg *args); /**< Writes as much of a string as fits. */
    size_t (*xml)(const VerbaTextusCfg *args);      /**< Writes text with the four XML entities substituted. */
    size_t (*json)(const VerbaTextusCfg *args);     /**< Writes text as a quoted JSON string. */
} VerbaScriboTextusNs;
EMBED_TABLE_LAYOUT(VerbaScriboTextusNs, put_n, put, put_clip, xml, json);

/**
 * @brief Arguments for the entries that write one character.
 *
 * @note Only mmgr_verba_ch reads these, and it writes one byte at the offset in at.
 * @warning out must be writable for cap bytes. A byte is always held back for the terminator finish
 *          stores.
 */
typedef struct
{
    char *const out;  /**< Destination buffer [BORROWS]. */
    const size_t cap; /**< Bytes available in out. */
    const size_t at;  /**< Offset to write at. */
    const char ch;    /**< Character to write. */
} VerbaLitteraCfg;

/**
 * @brief Type of the verba_littera dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the ch member is at offset 0 and that the struct holds nothing else.
 */
typedef struct
{
    size_t (*ch)(const VerbaLitteraCfg *args); /**< Writes one character. */
} VerbaScriboLitteraNs;
EMBED_TABLE_LAYOUT(VerbaScriboLitteraNs, ch);

/**
 * @brief Arguments for the entries that write an integer.
 *
 * @note i64 reads sval and every other entry reads val. uint is the only one that reads base, and
 *       u64_clip the only one that reads columns.
 * @note uint, u32w and hex read min. u32, u64 and i64 fix it at one in the backend instead.
 * @warning out must be writable for cap bytes. A byte is always held back for the terminator finish
 *          stores.
 */
typedef struct
{
    char *const out;       /**< Destination buffer [BORROWS]. */
    const size_t cap;      /**< Bytes available in out. */
    const size_t at;       /**< Offset to write at. */
    const uint64_t val;    /**< Unsigned value the unsigned entries write. */
    const int64_t sval;    /**< Signed value i64 writes. */
    const uint8_t base;    /**< Numeric base uint writes in: 8, 16, or anything else for ten. */
    const uint8_t min;     /**< Fewest digits to write, padded on the left with zeros. */
    const uint8_t columns; /**< Fewest columns u64_clip fills, padded on the left with spaces. */
} VerbaNumerusCfg;

/**
 * @brief Type of the verba_numerus dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the seven members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    size_t (*u64_clip)(const VerbaNumerusCfg *args); /**< Writes a value right aligned, padded with spaces. */
    size_t (*uint)(const VerbaNumerusCfg *args);     /**< Writes a value in the base the caller gives. */
    size_t (*u32w)(const VerbaNumerusCfg *args);     /**< Writes a value in base ten, padded to min digits. */
    size_t (*hex)(const VerbaNumerusCfg *args);      /**< Writes a value in lower case base sixteen. */
    size_t (*u32)(const VerbaNumerusCfg *args);      /**< Writes a value in base ten, unpadded. */
    size_t (*u64)(const VerbaNumerusCfg *args);      /**< The same walk as u32, named for the width meant. */
    size_t (*i64)(const VerbaNumerusCfg *args);      /**< Writes a signed value in base ten. */
} VerbaScriboNumerusNs;
EMBED_TABLE_LAYOUT(VerbaScriboNumerusNs, u64_clip, uint, u32w, hex, u32, u64, i64);

/**
 * @brief Arguments for the entries that write a double.
 *
 * @note g reads sig and fixed reads decimals. Neither reads the other's. The three predicates read
 *       real on its own and write nothing, so out and cap may be left unset for them.
 * @warning g and fixed need out writable for cap bytes. A byte is always held back for the terminator
 *          finish stores.
 */
typedef struct
{
    char *const out;        /**< Destination buffer [BORROWS]. The three predicates leave it unset. */
    const size_t cap;       /**< Bytes available in out. */
    const size_t at;        /**< Offset to write at. */
    const double real;      /**< The value to write or classify. */
    const uint8_t sig;      /**< Significant digits g keeps, held at MMGR_G_MAX_SIG. */
    const uint8_t decimals; /**< Digits after the point fixed writes, held at MMGR_FIXED_MAX_DECIMALS. */
} VerbaFractioCfg;

/**
 * @brief Type of the verba_fractio dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the five members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    size_t (*g)(const VerbaFractioCfg *args);            /**< Writes a double to a significant digit count. */
    size_t (*fixed)(const VerbaFractioCfg *args);        /**< Writes a double to a decimal count. */
    embed_bool (*sign_bit)(const VerbaFractioCfg *args); /**< Reports a double's sign bit. */
    embed_bool (*is_inf)(const VerbaFractioCfg *args);   /**< Reports whether a double is an infinity. */
    embed_bool (*is_nan)(const VerbaFractioCfg *args);   /**< Reports whether a double is a NaN. */
} VerbaScriboFractioNs;
EMBED_TABLE_LAYOUT(VerbaScriboFractioNs, g, fixed, sign_bit, is_inf, is_nan);

/**
 * @brief Arguments for the entries that write the buffer itself, with no value to place in it.
 *
 * @note finish stores a byte at at, so it needs out. ok compares at against cap and reads neither the
 *       buffer nor a value, so out may be left unset for it.
 */
typedef struct
{
    char *const out;  /**< Destination buffer [BORROWS]. ok leaves it unset. */
    const size_t cap; /**< Bytes available in out. */
    const size_t at;  /**< Offset reached. */
} VerbaFinisCfg;

/**
 * @brief Type of the verba_finis dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the two members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    size_t (*finish)(const VerbaFinisCfg *args); /**< Stores the terminator and reports the length. */
    embed_bool (*ok)(const VerbaFinisCfg *args); /**< Reports whether there is still room. */
} VerbaScriboFinisNs;
EMBED_TABLE_LAYOUT(VerbaScriboFinisNs, finish, ok);

/**
 * @brief Writes a counted run of text.
 *
 * @param[in] args Buffer, capacity, offset, text and its length [BORROWS].
 * @return         The offset past the text, or args->cap when it did not fit.
 * @note Writes nothing at all when it does not fit, rather than writing what it can.
 * @warning args->text must be readable for args->text_len bytes. No terminator is looked for.
 */
size_t mmgr_verba_put_n(const VerbaTextusCfg *args);

/**
 * @brief Writes a terminated string, measuring it first.
 *
 * @param[in] args Buffer, capacity, offset and the text [BORROWS].
 * @return         The offset past the text, or args->cap when it did not fit.
 * @note Takes args->text_len as the length when it is non-zero, and only otherwise measures.
 * @warning args->text must not be NULL here, unlike put_clip, xml and json.
 */
size_t mmgr_verba_put(const VerbaTextusCfg *args);

/**
 * @brief Writes as much of a string as fits.
 *
 * @param[in] args Buffer, capacity, offset and the text [BORROWS].
 * @return         The offset past what was written, which is args->at when nothing was.
 * @note Returns args->at rather than args->cap when it writes nothing, so a later call can still write.
 * @note Bounds the measure by the room left, so the length measured is already the length that fits.
 * @warning A NULL args->text writes nothing rather than faulting, unlike put.
 */
size_t mmgr_verba_put_clip(const VerbaTextusCfg *args);

/**
 * @brief Writes text with the four XML entities substituted.
 *
 * @param[in] args Buffer, capacity, offset and the text [BORROWS].
 * @return         The offset past what was written, which is args->at for a NULL args->text.
 * @note Replaces the ampersand, the two angle brackets and the double quote. The apostrophe is
 *       written as it stands, so this suits element text and double quoted attributes.
 * @warning Walks to the terminator, so args->text is bounded by its own terminator rather than by args->cap.
 */
size_t mmgr_verba_xml(const VerbaTextusCfg *args);

/**
 * @brief Writes text as a quoted JSON string.
 *
 * @param[in] args Buffer, capacity, offset and the text [BORROWS].
 * @return         The offset past the closing quote, or args->cap once something did not fit.
 * @note Writes the opening and closing quotes itself, so the result is a complete JSON string, and a
 *       NULL args->text writes an empty pair of quotes where xml writes nothing at all.
 * @warning Walks to the terminator, so args->text is bounded by its own terminator rather than by args->cap.
 */
size_t mmgr_verba_json(const VerbaTextusCfg *args);

/**
 * @brief Writes one character.
 *
 * @param[in] args Buffer, capacity, offset and the character [BORROWS].
 * @return         args->at plus one, or args->cap when there is no room.
 * @note The building block the escape and digit entries write through, one character at a time.
 * @warning args->out must be writable for args->cap bytes. A byte is always held back for the
 *          terminator finish stores.
 */
size_t mmgr_verba_ch(const VerbaLitteraCfg *args);

/**
 * @brief Writes a value right aligned, padded with spaces.
 *
 * @param[in] args Buffer, capacity, offset, the value and the column count [BORROWS].
 * @return         The offset past what was written, which is args->at when there was no room.
 * @note Takes args->columns as a floor, so a value needing more digits than that widens the field.
 * @note Pads on the left with spaces, where uint pads with leading zeros.
 * @warning args->out must be writable for args->cap bytes, and a byte is held back for the terminator.
 */
size_t mmgr_verba_u64_clip(const VerbaNumerusCfg *args);

/**
 * @brief Writes a value in the base the caller gives.
 *
 * @param[in] args Buffer, capacity, offset, the value, the base and the least digit count [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note Raising the digit count to args->min before the room test is what pads with leading zeros.
 * @warning Any args->base other than 8 or 16 is written in base ten, whatever value it holds.
 */
size_t mmgr_verba_uint(const VerbaNumerusCfg *args);

/**
 * @brief Writes a value in base ten, padded to min digits.
 *
 * @param[in] args Buffer, capacity, offset, the value and the least digit count [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note Fixes the base at ten and forwards args->min, which is what separates it from u32.
 * @warning args->base takes no part here, whatever the caller put in it.
 */
size_t mmgr_verba_u32w(const VerbaNumerusCfg *args);

/**
 * @brief Writes a value in lower case base sixteen.
 *
 * @param[in] args Buffer, capacity, offset, the value and the least digit count [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note Fixes the base at sixteen, so the digits come out lower case, and forwards args->min so the
 *       result can be padded with leading zeros to a fixed width.
 * @warning args->base takes no part here, whatever the caller put in it.
 */
size_t mmgr_verba_hex(const VerbaNumerusCfg *args);

/**
 * @brief Writes a value in base ten, unpadded.
 *
 * @param[in] args Buffer, capacity, offset and the value [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note Fixes both the base at ten and the least digit count at one.
 * @warning Neither args->base nor args->min takes any part here. Reach for u32w to pad.
 */
size_t mmgr_verba_u32(const VerbaNumerusCfg *args);

/**
 * @brief Writes a value in base ten, unpadded.
 *
 * @param[in] args Buffer, capacity, offset and the value [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note The same walk as u32, since args->val is 64 bits either way. Both names exist so a caller
 *       reads the width it means at the call.
 * @warning Neither args->base nor args->min takes any part here. Reach for u32w to pad.
 */
size_t mmgr_verba_u64(const VerbaNumerusCfg *args);

/**
 * @brief Writes a signed value in base ten.
 *
 * @param[in] args Buffer, capacity, offset and the signed value in sval [BORROWS].
 * @return         The offset past the digits, or args->cap when they do not fit.
 * @note Writes the sign through ch, then hands the magnitude to uint at base ten.
 * @note The magnitude is taken as -(sval + 1) plus one, which stays in range for the most negative value.
 * @warning Reads args->sval and not args->val, so a caller filling the unsigned member writes a zero.
 */
size_t mmgr_verba_i64(const VerbaNumerusCfg *args);

/**
 * @brief Writes a double to a significant digit count.
 *
 * @param[in] args Buffer, capacity, offset, the value and the significant digit count [BORROWS].
 * @return         The offset past what was written, or args->cap once something did not fit.
 * @note An args->sig of 0 is taken as 1, and anything above MMGR_G_MAX_SIG is held there.
 * @note Picks the shorter of a plain and an exponential form, dropping trailing zeros before it chooses.
 * @warning An infinity writes inf and a NaN writes nan, lower case and unquoted, so neither is valid
 *          JSON on its own.
 */
size_t mmgr_verba_g(const VerbaFractioCfg *args);

/**
 * @brief Writes a double to a decimal count.
 *
 * @param[in] args Buffer, capacity, offset, the value and the decimal count [BORROWS].
 * @return         The offset past what was written, or args->cap once something did not fit.
 * @note args->decimals is held at MMGR_FIXED_MAX_DECIMALS, and a value of 0 writes no point at all.
 * @note A half rounds up, and a fraction that carries raises the integer part. The sign is written
 *       ahead of the magnitude, so a negative half rounds away from zero.
 * @warning A magnitude too large for 64 bits of integer part falls back to g at ten significant
 *          digits, so the result is not always in the fixed form asked for.
 */
size_t mmgr_verba_fixed(const VerbaFractioCfg *args);

/**
 * @brief Reports a double's sign bit.
 *
 * @param[in] args The value to test, as args->real [BORROWS].
 * @return         EMBED_TRUE when the sign bit is set, with nothing written.
 * @note Reads the bit rather than comparing against zero, so a negative zero returns EMBED_TRUE.
 * @note Reads no member but args->real, so args->out may be left unset.
 */
embed_bool mmgr_verba_sign_bit(const VerbaFractioCfg *args);

/**
 * @brief Reports whether a double is an infinity.
 *
 * @param[in] args The value to test, as args->real [BORROWS].
 * @return         EMBED_TRUE for either infinity, with nothing written.
 * @note Wants the exponent field all ones and the mantissa zero, where is_nan wants it non-zero.
 * @note The sign takes no part, so a negative infinity returns EMBED_TRUE too.
 */
embed_bool mmgr_verba_is_inf(const VerbaFractioCfg *args);

/**
 * @brief Reports whether a double is a NaN.
 *
 * @param[in] args The value to test, as args->real [BORROWS].
 * @return         EMBED_TRUE for any NaN, with nothing written.
 * @note Wants the exponent field all ones and the mantissa non-zero, where is_inf wants it zero.
 * @note Quiet and signalling NaNs answer alike, since only the mantissa being non-zero is tested.
 */
embed_bool mmgr_verba_is_nan(const VerbaFractioCfg *args);

/**
 * @brief Stores the terminator and reports the length.
 *
 * @param[in] args Buffer, capacity and the offset reached [BORROWS].
 * @return         args->at, or 0 when args->at already reached args->cap.
 * @note A return of 0 covers both an empty result and one that ran out of room. ok tells them apart.
 * @warning The only entry that writes a terminator, so a buffer is not a string until this has run.
 */
size_t mmgr_verba_finish(const VerbaFinisCfg *args);

/**
 * @brief Reports whether there is still room.
 *
 * @param[in] args Capacity and the offset reached [BORROWS].
 * @return         EMBED_TRUE while there is still room, EMBED_FALSE once an entry returned args->cap.
 * @note Reads neither args->out nor any value member, so it touches no memory and args->out may be NULL.
 */
embed_bool mmgr_verba_ok(const VerbaFinisCfg *args);

/**
 * @brief Dispatch table instance named verba_textus, with each member set to its mmgr_verba_ function.
 */
EMBED_TABLE_STORAGE VerbaScriboTextusNs verba_textus EMBED_UNUSED = {
    .put_n = mmgr_verba_put_n,
    .put = mmgr_verba_put,
    .put_clip = mmgr_verba_put_clip,
    .xml = mmgr_verba_xml,
    .json = mmgr_verba_json,
};

/**
 * @brief Dispatch table instance named verba_littera, whose one member is set to mmgr_verba_ch.
 */
EMBED_TABLE_STORAGE VerbaScriboLitteraNs verba_littera EMBED_UNUSED = {
    .ch = mmgr_verba_ch,
};

/**
 * @brief Dispatch table instance named verba_numerus, with each member set to its mmgr_verba_ function.
 */
EMBED_TABLE_STORAGE VerbaScriboNumerusNs verba_numerus EMBED_UNUSED = {
    .u64_clip = mmgr_verba_u64_clip,
    .uint = mmgr_verba_uint,
    .u32w = mmgr_verba_u32w,
    .hex = mmgr_verba_hex,
    .u32 = mmgr_verba_u32,
    .u64 = mmgr_verba_u64,
    .i64 = mmgr_verba_i64,
};

/**
 * @brief Dispatch table instance named verba_fractio, with each member set to its mmgr_verba_ function.
 */
EMBED_TABLE_STORAGE VerbaScriboFractioNs verba_fractio EMBED_UNUSED = {
    .g = mmgr_verba_g,
    .fixed = mmgr_verba_fixed,
    .sign_bit = mmgr_verba_sign_bit,
    .is_inf = mmgr_verba_is_inf,
    .is_nan = mmgr_verba_is_nan,
};

/**
 * @brief Dispatch table instance named verba_finis, with each member set to its mmgr_verba_ function.
 */
EMBED_TABLE_STORAGE VerbaScriboFinisNs verba_finis EMBED_UNUSED = {
    .finish = mmgr_verba_finish,
    .ok = mmgr_verba_ok,
};

EMBED_END_DECLS

#endif
