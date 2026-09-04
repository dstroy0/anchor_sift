/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file numeros_scribo.h
 * @brief Formatted output: the field kinds, the value union, the macros that build both, and the numer table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note A spec is an mmgr_field array ending at MMGR_FK_END. Every field but MMGR_FK_LIT takes one
 *       mmgr_fval.
 * @note Includes verba_scribo.h, which is where mmgr_config.h and the verba table come from.
 */
#ifndef MMGR_NUMEROS_SCRIBO_H
#define MMGR_NUMEROS_SCRIBO_H

#include "verba_scribo/verba_scribo.h"

EMBED_BEGIN_DECLS

/**
 * @brief What one field formats, and which mmgr_fval arm it reads.
 *
 * @note numeros_scribo.c indexes s_kind by this value, so MMGR_FK_XML is the largest one it accepts.
 * @note EMBED_ENUM_PACKED asks for the narrowest representation. mmgr_types.h asserts that it took
 *       effect.
 */
typedef enum EMBED_ENUM_PACKED
{
    MMGR_FK_END = 0, /**< Ends a spec. numer_build stops at this field. */
    MMGR_FK_LIT,     /**< Literal text, taken from mmgr_field::lit and mmgr_field::len. */
    MMGR_FK_STR,     /**< String from as.s, through mmgr_verba_put. */
    MMGR_FK_U32,     /**< Unsigned 32-bit from as.u32, base 10, through mmgr_verba_u32. */
    MMGR_FK_U64,     /**< Unsigned 64-bit from as.u64, base 10, through mmgr_verba_u64. */
    MMGR_FK_I64,     /**< Signed 64-bit from as.i64, base 10, through mmgr_verba_i64. */
    MMGR_FK_DEC,     /**< Unsigned 32-bit from as.u32, base 10, through mmgr_verba_u32w. */
    MMGR_FK_HEX,     /**< Unsigned 64-bit from as.u64, base 16, through mmgr_verba_hex. */
    MMGR_FK_OCT,     /**< Unsigned 64-bit from as.u64, base 8, through mmgr_verba_uint. */
    MMGR_FK_G,       /**< Double from as.d, through mmgr_verba_g, defaulting to six significant digits. */
    MMGR_FK_FIX,     /**< Double from as.d, through mmgr_verba_fixed. */
    MMGR_FK_CH,      /**< Single character from as.c, through mmgr_verba_ch. */
    MMGR_FK_JSON,    /**< String from as.s, through mmgr_verba_json. */
    MMGR_FK_XML,     /**< String from as.s, through mmgr_verba_xml. */
} mmgr_fk;

/**
 * @brief One field of a spec.
 *
 * @note numer_build reads literal and bytes only for MMGR_FK_LIT, and width only for the other kinds.
 */
typedef struct
{
    mmgr_fk kind;        /**< What this field formats. */
    uint8_t width;       /**< Width to give the value, or 0 to take the kind's default from s_kind. */
    uint16_t bytes;      /**< Bytes of literal to write, for MMGR_FK_LIT. */
    const char *literal; /**< Literal text, for MMGR_FK_LIT [BORROWS]. */
} mmgr_field;

/** @brief Expands to an mmgr_field of kind MMGR_FK_STR, with width 0, bytes 0 and literal NULL. */
#define MMGR_STR {MMGR_FK_STR, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_U32, with width 0, bytes 0 and literal NULL. */
#define MMGR_U32 {MMGR_FK_U32, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_U64, with width 0, bytes 0 and literal NULL. */
#define MMGR_U64 {MMGR_FK_U64, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_I64, with width 0, bytes 0 and literal NULL. */
#define MMGR_I64 {MMGR_FK_I64, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_CH, with width 0, bytes 0 and literal NULL. */
#define MMGR_CH {MMGR_FK_CH, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_JSON, with width 0, bytes 0 and literal NULL. */
#define MMGR_JSON {MMGR_FK_JSON, 0u, 0u, NULL}

/** @brief Expands to an mmgr_field of kind MMGR_FK_XML, with width 0, bytes 0 and literal NULL. */
#define MMGR_XML {MMGR_FK_XML, 0u, 0u, NULL}

/**
 * @brief Expands to an mmgr_field of kind MMGR_FK_END, with width 0, bytes 0 and literal NULL.
 *
 * @note numer_build stops at this field, so every spec array needs one as its last entry.
 */
#define MMGR_END {MMGR_FK_END, 0u, 0u, NULL}

/**
 * @brief One value, tagged with the kind that selects which arm of as holds it.
 *
 * @note numer_build requires kind to equal the field's kind, and abandons the whole write when it does not.
 * @note numer_emit takes width from here, where numer_build takes it from the field.
 * @warning numer_emit_one reads the arm that kind names and no other, so a value whose kind and
 *          filled arm disagree formats what that arm was left holding.
 */
typedef struct
{
    mmgr_fk kind; /**< Which arm of as holds the value. */
    union {
        const char *text; /**< Read for MMGR_FK_STR, MMGR_FK_JSON and MMGR_FK_XML [BORROWS]. */
        uint32_t u32;     /**< Read for MMGR_FK_U32 and MMGR_FK_DEC. */
        uint64_t u64;     /**< Read for MMGR_FK_U64, MMGR_FK_HEX and MMGR_FK_OCT. */
        int64_t i64;      /**< Read for MMGR_FK_I64. */
        double real;      /**< Read for MMGR_FK_G and MMGR_FK_FIX. */
        char character;   /**< Read for MMGR_FK_CH. */
    } as;                 /**< The value, under the arm that kind names. */
    uint8_t width;        /**< Width numer_emit gives this value, or 0 to take the kind's default from s_kind. */
} mmgr_fval;

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_STR, with text_ in as.text and width 0.
 *
 * @param[in] text_ String placed in as.text [BORROWS].
 */
#define MMGR_VSTR(text_) {MMGR_FK_STR, {.text = (text_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_U32, with value_ in as.u32 and width 0.
 *
 * @param[in] value_ Value placed in as.u32.
 */
#define MMGR_VU32(value_) {MMGR_FK_U32, {.u32 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_U64, with value_ in as.u64 and width 0.
 *
 * @param[in] value_ Value placed in as.u64.
 */
#define MMGR_VU64(value_) {MMGR_FK_U64, {.u64 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_I64, with value_ in as.i64 and width 0.
 *
 * @param[in] value_ Value placed in as.i64.
 */
#define MMGR_VI64(value_) {MMGR_FK_I64, {.i64 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_DEC, with value_ in as.u32 and width 0.
 *
 * @param[in] value_ Value placed in as.u32.
 */
#define MMGR_VDEC(value_) {MMGR_FK_DEC, {.u32 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_HEX, with value_ in as.u64 and width 0.
 *
 * @param[in] value_ Value placed in as.u64.
 */
#define MMGR_VHEX(value_) {MMGR_FK_HEX, {.u64 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_OCT, with value_ in as.u64 and width 0.
 *
 * @param[in] value_ Value placed in as.u64.
 */
#define MMGR_VOCT(value_) {MMGR_FK_OCT, {.u64 = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_G, with value_ in as.real and width 0.
 *
 * @param[in] value_ Value placed in as.real.
 */
#define MMGR_VG(value_) {MMGR_FK_G, {.real = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_FIX, with value_ in as.real and width 0.
 *
 * @param[in] value_ Value placed in as.real.
 */
#define MMGR_VFIX(value_) {MMGR_FK_FIX, {.real = (value_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_CH, with character_ in as.character and width 0.
 *
 * @param[in] character_ Character placed in as.character.
 */
#define MMGR_VCH(character_) {MMGR_FK_CH, {.character = (character_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_JSON, with text_ in as.text and width 0.
 *
 * @param[in] text_ String placed in as.text [BORROWS].
 */
#define MMGR_VJSON(text_) {MMGR_FK_JSON, {.text = (text_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_XML, with text_ in as.text and width 0.
 *
 * @param[in] text_ String placed in as.text [BORROWS].
 */
#define MMGR_VXML(text_) {MMGR_FK_XML, {.text = (text_)}, 0u}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_DEC, with value_ in as.u32 and width_ in width.
 *
 * @param[in] value_ Value placed in as.u32.
 * @param[in] width_ Width placed in the width member.
 * @note numer_emit uses that width. numer_build takes the width from the field instead.
 */
#define MMGR_VDECW(value_, width_) {MMGR_FK_DEC, {.u32 = (value_)}, (width_)}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_HEX, with value_ in as.u64 and width_ in width.
 *
 * @param[in] value_ Value placed in as.u64.
 * @param[in] width_ Width placed in the width member.
 * @note numer_emit uses that width. numer_build takes the width from the field instead.
 */
#define MMGR_VHEXW(value_, width_) {MMGR_FK_HEX, {.u64 = (value_)}, (width_)}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_OCT, with value_ in as.u64 and width_ in width.
 *
 * @param[in] value_ Value placed in as.u64.
 * @param[in] width_ Width placed in the width member.
 * @note numer_emit uses that width. numer_build takes the width from the field instead.
 */
#define MMGR_VOCTW(value_, width_) {MMGR_FK_OCT, {.u64 = (value_)}, (width_)}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_G, with value_ in as.real and width_ in width.
 *
 * @param[in] value_ Value placed in as.real.
 * @param[in] width_ Width placed in the width member.
 * @note numer_emit_one hands that width to mmgr_verba_g as VerbaFractioCfg::sig, the significant
 *       digits it keeps.
 * @note numer_emit uses it. numer_build takes the width from the field instead.
 */
#define MMGR_VGW(value_, width_) {MMGR_FK_G, {.real = (value_)}, (width_)}

/**
 * @brief Expands to an mmgr_fval of kind MMGR_FK_FIX, with value_ in as.real and width_ in width.
 *
 * @param[in] value_ Value placed in as.real.
 * @param[in] width_ Width placed in the width member.
 * @note numer_emit_one hands that width to mmgr_verba_fixed as VerbaFractioCfg::decimals, the digits
 *       it writes after the point.
 * @note numer_emit uses it. numer_build takes the width from the field instead.
 */
#define MMGR_VFIXW(value_, width_) {MMGR_FK_FIX, {.real = (value_)}, (width_)}

/**
 * @brief Arguments for the four numer calls.
 *
 * @note build and append read all six members. emit and emit_append leave spec alone.
 * @note at is the cursor, as in verba. build and emit begin there and return where they finished, so
 *       a run of writes threads the cursor rather than measuring the text again between each. Leave
 *       it unset and a call starts at the first byte, which is what a single write wants.
 */
typedef struct
{
    char *const out;              /**< Destination buffer [BORROWS]. */
    const size_t cap;             /**< Bytes available in out. */
    const size_t at;              /**< Offset to begin writing at; 0 for the first write. */
    const mmgr_field *const spec; /**< Field list, ending at MMGR_FK_END [BORROWS]. */
    const mmgr_fval *const vals;  /**< Values to place into the fields [BORROWS]. */
    const size_t nvals;           /**< Values in vals. */
} NumerosCfg;

/**
 * @brief Type of the numer dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the four members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note build and emit begin at NumerosCfg::at, which is out's first byte while the caller leaves it
 *       unset. The two append members begin past the text already there.
 */
typedef struct
{
    size_t (*build)(const NumerosCfg *args);       /**< Writes a spec and its values. */
    size_t (*append)(const NumerosCfg *args);      /**< Writes a spec and its values after the text in out. */
    size_t (*emit)(const NumerosCfg *args);        /**< Writes values, with no field list. */
    size_t (*emit_append)(const NumerosCfg *args); /**< Writes values after the text in out, with no field list. */
} NumerosScriboNs;
EMBED_TABLE_LAYOUT(NumerosScriboNs, build, append, emit, emit_append);

/**
 * @brief Writes args->spec and args->vals into args->out, starting at args->at.
 *
 * @param[in] args Buffer, capacity, the field list and the values [BORROWS].
 * @return         Length of the whole string in args->out, not counting its terminator, or 0 when
 *                 nothing was written.
 * @note An MMGR_FK_LIT field writes its own text. Every other field consumes the next value in
 *       args->vals.
 * @note Returns 0 and puts the terminator back at args->at when a value is missing, when a kind differs,
 *       or when values are left over, which leaves the text written before this call whole.
 * @warning args->spec must reach an MMGR_FK_END field, and args->vals must hold args->nvals values.
 */
size_t mmgr_numer_build(const NumerosCfg *args);

/**
 * @brief Writes args->spec and args->vals into args->out after the string already there.
 *
 * @param[in] args Buffer, capacity, the field list and the values [BORROWS].
 * @return         Length of the whole string in args->out, or 0 when nothing was added.
 * @note Carries on at args->at when the caller threaded one, and measures the existing string with
 *       cellul.len only when args->at is 0. Either way the build gets the whole of args->cap and
 *       that offset.
 * @note Puts the terminator back at the offset it began from and returns 0 when the build writes nothing.
 * @warning args->spec must reach an MMGR_FK_END field, and args->out must hold a terminated string when
 *          args->at is 0, since that is the only time the length is measured.
 */
size_t mmgr_numer_append(const NumerosCfg *args);

/**
 * @brief Writes args->vals into args->out, starting at args->at and reading no field list.
 *
 * @param[in] args Buffer, capacity and the values [BORROWS].
 * @return         Length of the whole string in args->out, not counting its terminator, or 0 when
 *                 nothing was written.
 * @note Each value carries its own width, and no kind is matched, since there are no fields to match against.
 * @warning args->vals must hold args->nvals values.
 * @warning A value of kind MMGR_FK_END or MMGR_FK_LIT formats nothing, which abandons the write and returns 0.
 */
size_t mmgr_numer_emit(const NumerosCfg *args);

/**
 * @brief Writes args->vals into args->out after the string already there, reading no field list.
 *
 * @param[in] args Buffer, capacity and the values [BORROWS].
 * @return         Length of the whole string in args->out, or 0 when nothing was added.
 * @note Carries on at args->at when the caller threaded one, and measures the existing string with
 *       cellul.len only when args->at is 0. Either way the emit gets the whole of args->cap and
 *       that offset.
 * @note Puts the terminator back at the offset it began from and returns 0 when the emit writes nothing.
 * @warning args->vals must hold args->nvals values, and args->out must hold a terminated string when
 *          args->at is 0, since that is the only time the length is measured.
 */
size_t mmgr_numer_emit_append(const NumerosCfg *args);

/**
 * @brief Dispatch table instance named numer.
 *
 * @note Each member calls the matching mmgr_numer_ function, one to one.
 * @note mmgr_numer_append reaches build through this table, and mmgr_numer_emit_append reaches emit.
 */
EMBED_TABLE_STORAGE NumerosScriboNs numer EMBED_UNUSED = {
    .build = mmgr_numer_build,
    .append = mmgr_numer_append,
    .emit = mmgr_numer_emit,
    .emit_append = mmgr_numer_emit_append,
};

EMBED_END_DECLS

#endif
