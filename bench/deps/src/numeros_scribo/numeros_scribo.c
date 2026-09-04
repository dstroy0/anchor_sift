/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file numeros_scribo.c
 * @brief Formatted output assembled from a field spec and a list of values.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note s_kind gives every field kind a verba call, a union arm, a numeric base and a default width.
 */
#include "numeros_scribo/numeros_scribo.h"
#include "cellularum_laboro/cellularum_laboro.h"

/**
 * @brief Arguments for the numer backends.
 *
 * @note Every backend reads out. Every backend but numer_abandon reads cap. numer_emit_one and
 *       numer_finish read at.
 * @note numer_build reads spec. numer_build and numer_emit read vals and nvals. numer_emit_one reads
 *       width. numer_emit_one and numer_str read one.
 */
typedef struct
{
    char *out;              /**< Destination buffer [BORROWS]. */
    size_t cap;             /**< Bytes available in out. */
    size_t at;              /**< Offset the next field is written at. */
    const mmgr_field *spec; /**< Field list, ending at MMGR_FK_END [BORROWS]. */
    const mmgr_fval *vals;  /**< Values to place into the fields [BORROWS]. */
    size_t nvals;           /**< Values in vals. */
    const mmgr_fval *one;   /**< The single value emit_one formats [BORROWS]. */
    uint8_t width;          /**< Width override for that value, or 0 to take the kind's default. */
} NumerCtx;

/**
 * @brief Returns the string in args->one, substituting an empty one for NULL.
 *
 * @param[in] args The value to read [BORROWS].
 * @return         args->one->as.text, or a literal empty string when that arm is NULL [BORROWS].
 * @note Returns a literal empty string in place of NULL, so the verba call always receives a valid pointer.
 */
EMBED_INLINE const char *numer_str(const NumerCtx *args)
{
    if (args->one->as.text == NULL)
    {
        return "";
    }
    return args->one->as.text;
}

/**
 * @brief Which member of an mmgr_fval union a field kind reads.
 *
 * @note numer_emit_one tests this to pick the union member. NumerKind::fn decides the format.
 */
typedef enum EMBED_ENUM_PACKED
{
    NUMER_ARM_NONE = 0, /**< Reads no value at all. */
    NUMER_ARM_STR,      /**< Reads as.s. */
    NUMER_ARM_U32,      /**< Reads as.u32. */
    NUMER_ARM_U64,      /**< Reads as.u64. */
    NUMER_ARM_I64,      /**< Reads as.i64. */
    NUMER_ARM_D,        /**< Reads as.d. */
    NUMER_ARM_CH,       /**< Reads as.c. */
} NumerArm;

/**
 * @brief One field kind's formatting function, union arm, numeric base and default width.
 *
 * @note The verba entries are split by what they write, so they no longer share an argument pack
 *       and cannot sit in one function pointer table directly. Each kind gets a small function of
 *       its own with a common signature, which keeps the dispatch one indirect call rather than a
 *       walk of cases.
 */
typedef struct
{
    size_t (*fn)(const NumerCtx *args); /**< The function that formats this kind. */
    NumerArm arm;                       /**< Which union member holds the value. */
    uint8_t base;                       /**< Numeric base, or 0 where the call fixes its own. */
    uint8_t width;                      /**< Default width, used when the field and value both leave it 0. */
} NumerKind;

/* The table names these and they read the table, so the names come first. */
static size_t numer_refuse(const NumerCtx *args);
static size_t numer_verba_put(const NumerCtx *args);
static size_t numer_verba_json(const NumerCtx *args);
static size_t numer_verba_xml(const NumerCtx *args);
static size_t numer_verba_ch(const NumerCtx *args);
static size_t numer_verba_u32(const NumerCtx *args);
static size_t numer_verba_u64(const NumerCtx *args);
static size_t numer_verba_i64(const NumerCtx *args);
static size_t numer_verba_u32w(const NumerCtx *args);
static size_t numer_verba_hex(const NumerCtx *args);
static size_t numer_verba_uint(const NumerCtx *args);
static size_t numer_verba_g(const NumerCtx *args);
static size_t numer_verba_fixed(const NumerCtx *args);

/**
 * @brief One entry per field kind, indexed by the mmgr_fk value itself.
 *
 * @note Sized to MMGR_FK_XML plus one, so every enumerator has a row.
 * @note MMGR_FK_DEC and MMGR_FK_U32 share the U32 arm but differ in call and default width.
 * @note MMGR_FK_G defaults to six significant digits. Every other kind defaults to 1 or 0.
 */
static const NumerKind s_kind[MMGR_FK_XML + 1u] = {
    [MMGR_FK_END] = {numer_refuse, NUMER_ARM_NONE, 0u, 0u},
    [MMGR_FK_LIT] = {numer_refuse, NUMER_ARM_NONE, 0u, 0u},
    [MMGR_FK_STR] = {numer_verba_put, NUMER_ARM_STR, 0u, 0u},
    [MMGR_FK_U32] = {numer_verba_u32, NUMER_ARM_U32, 10u, 1u},
    [MMGR_FK_U64] = {numer_verba_u64, NUMER_ARM_U64, 10u, 1u},
    [MMGR_FK_I64] = {numer_verba_i64, NUMER_ARM_I64, 10u, 1u},
    [MMGR_FK_DEC] = {numer_verba_u32w, NUMER_ARM_U32, 10u, 0u},
    [MMGR_FK_HEX] = {numer_verba_hex, NUMER_ARM_U64, 16u, 1u},
    [MMGR_FK_OCT] = {numer_verba_uint, NUMER_ARM_U64, 8u, 1u},
    [MMGR_FK_G] = {numer_verba_g, NUMER_ARM_D, 0u, 6u},
    [MMGR_FK_FIX] = {numer_verba_fixed, NUMER_ARM_D, 0u, 0u},
    [MMGR_FK_CH] = {numer_verba_ch, NUMER_ARM_CH, 0u, 0u},
    [MMGR_FK_JSON] = {numer_verba_json, NUMER_ARM_STR, 0u, 0u},
    [MMGR_FK_XML] = {numer_verba_xml, NUMER_ARM_STR, 0u, 0u},
};

/**
 * @brief Formats the single value in args->one at args->at, through that kind's verba call.
 *
 * @param[in] args Buffer, offset, the value and a width override [BORROWS].
 * @return         The offset past what was written, or args->cap when the kind is out of range.
 * @note The width override wins when non-zero. The kind's own default applies otherwise.
 * @note One indirect call through the kind's own function, which passes that entry only what it reads.
 * @warning args->one->kind above MMGR_FK_XML returns args->cap without a lookup, since s_kind ends at MMGR_FK_XML.
 */
EMBED_INLINE size_t numer_emit_one(const NumerCtx *args)
{
    if (args->one->kind > MMGR_FK_XML)
    {
        return args->cap;
    }
    return s_kind[args->one->kind].fn(args);
}

/**
 * @brief Terminates args->out where this write began and reports nothing written.
 *
 * @param[in] args Destination buffer and the starting cursor [BORROWS].
 * @return         0 always.
 * @note Terminates at args->at, which is where this write began, so text already in the buffer survives
 *       an abandoned append. args->at is the starting cursor here, not the offset the walk reached.
 * @note Reads args->out and args->at. cap and the value members take no part.
 * @warning args->out must be writable at args->at.
 */
EMBED_INLINE size_t numer_abandon(const NumerCtx *args)
{
    args->out[args->at] = '\0';
    return 0;
}

/**
 * @brief Closes the output through verba.finish.
 *
 * @param[in] args Buffer, capacity and the offset reached [BORROWS].
 * @return         The length verba.finish reported, which is args->at, or 0 when args->at reached args->cap.
 * @note Writes no terminator of its own. A 0 return is the caller's to act on, and the caller is the
 *       one that knows where the write began.
 */
EMBED_INLINE size_t numer_finish(const NumerCtx *args)
{
    // Reports and terminates nothing on failure. args->at here is the offset the walk reached, not where
    // it began, so this cannot restore the buffer. The caller holds the starting cursor and abandons
    return EMBED_CALL(verba_finis.finish, VerbaFinisCfg, .out = args->out, .cap = args->cap, .at = args->at);
}

/**
 * @brief Walks args->spec, writing each literal and pairing every other field with the next value in args->vals.
 *
 * @param[in] args Buffer, capacity, the field list and the values [BORROWS].
 * @return         What numer_finish returned, or 0 when args->cap is 0 or the spec and the values do
 *                 not match.
 * @note An MMGR_FK_LIT field takes cursor->literal and cursor->bytes. Every other field takes
 *       cursor->width.
 * @note Calls numer_abandon when a value is missing, when its kind differs, and when values are left over.
 * @warning args->spec must reach an MMGR_FK_END field, which is what ends the walk.
 */
EMBED_INLINE size_t numer_build(const NumerCtx *args)
{
    // Begins at the caller's cursor rather than the first byte, so a run of writes never re-measures
    // what the last one left. An unset at is 0, which is where a single write starts anyway.
    size_t at = args->at;
    size_t taken = 0;

    if (args->cap == 0u)
    {
        return 0;
    }

    for (const mmgr_field *cursor = args->spec; cursor->kind != MMGR_FK_END; cursor++)
    {
        if (cursor->kind == MMGR_FK_LIT)
        {
            at = EMBED_CALL(verba_textus.put_n, VerbaTextusCfg, .out = args->out, .cap = args->cap, .at = at,
                            .text = cursor->literal, .text_len = cursor->bytes);
            continue;
        }

        if ((taken >= args->nvals) || (args->vals[taken].kind != cursor->kind))
        {
            return numer_abandon(args);
        }

        at = EMBED_CALL(numer_emit_one, NumerCtx, .out = args->out, .cap = args->cap, .at = at,
                        .one = &args->vals[taken], .width = cursor->width);
        taken++;
    }
    if (taken != args->nvals)
    {
        return numer_abandon(args);
    }
    const size_t done = EMBED_CALL(numer_finish, NumerCtx, .out = args->out, .cap = args->cap, .at = at);

    // The finish reports 0 when it ran out of room. args->at is where this write began, so abandoning
    // here puts the terminator back there and leaves earlier text whole.
    return (done == 0u) ? numer_abandon(args) : done;
}

/**
 * @brief Formats every value in args->vals in order, with no field list.
 *
 * @param[in] args Buffer, capacity and the values [BORROWS].
 * @return         What numer_finish returned, or 0 when args->cap is 0.
 * @note Each value carries its own width in args->vals[taken].width, where build takes the width from the field.
 * @note Passes every value to numer_emit_one whatever its kind, so MMGR_FK_END and MMGR_FK_LIT reach numer_refuse.
 * @warning args->vals must hold args->nvals values.
 */
EMBED_INLINE size_t numer_emit(const NumerCtx *args)
{
    // Begins at the caller's cursor, as numer_build does
    size_t at = args->at;

    if (args->cap == 0u)
    {
        return 0;
    }

    for (size_t taken = 0; taken < args->nvals; taken++)
    {
        at = EMBED_CALL(numer_emit_one, NumerCtx, .out = args->out, .cap = args->cap, .at = at,
                        .one = &args->vals[taken], .width = args->vals[taken].width);
    }
    const size_t done = EMBED_CALL(numer_finish, NumerCtx, .out = args->out, .cap = args->cap, .at = at);

    // The finish reports 0 when it ran out of room. args->at is where this write began, so abandoning
    // here puts the terminator back there and leaves earlier text whole.
    return (done == 0u) ? numer_abandon(args) : done;
}

/**
 * @brief Returns the length cellul.len reports for the string already in args->out.
 *
 * @param[in] args Buffer and its capacity [BORROWS].
 * @return         What cellul.len returned, given args->out and args->cap.
 * @note Called by mmgr_numer_append and mmgr_numer_emit_append to find where to carry on writing.
 */
EMBED_INLINE size_t numer_used(const NumerCtx *args)
{
    return EMBED_CALL(cellul.len, CatenaFinitaCfg, .src = args->out, .cap = args->cap);
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_numer_ and numer_ prefixes, which the two share.
 * @param[in] ...         Designated initializers for the NumerCtx the entry hands to the inline call.
 */
#define NUMER_ENTRY(ReturnType_, name_, ...)                                                                           \
    EMBED_ENTRY(mmgr_numer_, numer_, NumerCtx, NumerosCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief The two entries that forward and nothing else.
 *
 * @note Each is documented at its declaration in numeros_scribo.h.
 * @note The two append entries below are not here. They read the text already in args->out and re-enter
 *       through the numer table, so they carry logic rather than an argument pack alone.
 */
NUMER_ENTRY(size_t, build, .out = args->out, .cap = args->cap, .at = args->at, .spec = args->spec, .vals = args->vals,
            .nvals = args->nvals)
NUMER_ENTRY(size_t, emit, .out = args->out, .cap = args->cap, .at = args->at, .vals = args->vals, .nvals = args->nvals)

/**
 * @brief Writes args->spec and args->vals into args->out after the string already there.
 *
 * @param[in] args Buffer, capacity, the field list and the values [BORROWS].
 * @return         Length of the whole string in args->out, or 0 when nothing was added.
 * @note Calls through the numer table, where mmgr_numer_build reaches numer_build directly.
 * @note Puts the terminator back at args->out[used] when the build reports 0, leaving the earlier text in place.
 * @note Documented at the declaration in numeros_scribo.h.
 * @warning args->out must already hold a terminated string, and args->spec must reach an MMGR_FK_END field.
 */
size_t mmgr_numer_append(const NumerosCfg *args)
{
    if (args->cap == 0u)
    {
        return 0;
    }

    // args->at when the caller threaded it, and only otherwise a scan. A caller that keeps the cursor
    // pays nothing here. One that does not is measured once per call, which is what made a run of
    // appends cost more the longer the text got
    const size_t used =
        (args->at != 0u) ? args->at : EMBED_CALL(numer_used, NumerCtx, .out = args->out, .cap = args->cap);

    if (used >= args->cap)
    {
        return 0;
    }

    const size_t count = EMBED_CALL(numer.build, NumerosCfg, .out = args->out, .cap = args->cap, .at = used,
                                    .spec = args->spec, .vals = args->vals, .nvals = args->nvals);
    if (count == 0)
    {
        args->out[used] = '\0';
        return 0;
    }
    return count;
}

/**
 * @brief Writes args->vals into args->out after the string already there, reading no field list.
 *
 * @param[in] args Buffer, capacity and the values [BORROWS].
 * @return         Length of the whole string in args->out, or 0 when nothing was added.
 * @note Calls through the numer table, where mmgr_numer_emit reaches numer_emit directly.
 * @note Puts the terminator back at args->out[used] when the emit reports 0, leaving the earlier text in place.
 * @note Documented at the declaration in numeros_scribo.h.
 * @warning args->out must already hold a terminated string, and args->vals must hold args->nvals values.
 */
size_t mmgr_numer_emit_append(const NumerosCfg *args)
{
    if (args->cap == 0u)
    {
        return 0;
    }

    // args->at when the caller threaded it, and only otherwise a scan, as in mmgr_numer_append
    const size_t used =
        (args->at != 0u) ? args->at : EMBED_CALL(numer_used, NumerCtx, .out = args->out, .cap = args->cap);

    if (used >= args->cap)
    {
        return 0;
    }

    const size_t count = EMBED_CALL(numer.emit, NumerosCfg, .out = args->out, .cap = args->cap, .at = used,
                                    .vals = args->vals, .nvals = args->nvals);
    if (count == 0)
    {
        args->out[used] = '\0';
        return 0;
    }
    return count;
}

/**
 * @brief Formats nothing, leaving the output untouched.
 *
 * @param[in] args The arguments, of which only cap is read [BORROWS].
 * @return         args->cap unchanged.
 * @note Bound to MMGR_FK_END and MMGR_FK_LIT in s_kind. numer_build handles both before reaching
 *       numer_emit_one.
 */
static size_t numer_refuse(const NumerCtx *args)
{
    return args->cap;
}

/**
 * @brief Picks the width this value is formatted at, taking the override ahead of the kind's default.
 *
 * @param[in] args The value and its override [BORROWS].
 * @return         The width every formatting function below passes on.
 */
EMBED_INLINE uint8_t numer_latitudo(const NumerCtx *args)
{
    const uint8_t own = s_kind[args->one->kind].width;

    return (args->width != 0u) ? args->width : own;
}

/**
 * @brief The unsigned value, whichever arm holds it.
 *
 * @param[in] args The value [BORROWS].
 * @return         as.u32 widened, or as.u64 as it stands.
 */
EMBED_INLINE uint64_t numer_numerus(const NumerCtx *args)
{
    // Explicit cast widens the u32 arm to the width every unsigned entry is declared with
    return (s_kind[args->one->kind].arm == NUMER_ARM_U32) ? (uint64_t)args->one->as.u32 : args->one->as.u64;
}

/**
 * @brief Formats this kind through verba_textus.put.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_put(const NumerCtx *args)
{
    return EMBED_CALL(verba_textus.put, VerbaTextusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .text = numer_str(args));
}

/**
 * @brief Formats this kind through verba_textus.json.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_json(const NumerCtx *args)
{
    return EMBED_CALL(verba_textus.json, VerbaTextusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .text = numer_str(args));
}

/**
 * @brief Formats this kind through verba_textus.xml.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_xml(const NumerCtx *args)
{
    return EMBED_CALL(verba_textus.xml, VerbaTextusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .text = numer_str(args));
}

/**
 * @brief Formats this kind through verba_littera.ch.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_ch(const NumerCtx *args)
{
    return EMBED_CALL(verba_littera.ch, VerbaLitteraCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .ch = args->one->as.character);
}

/**
 * @brief Formats this kind through verba_numerus.u32.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_u32(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.u32, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .val = numer_numerus(args));
}

/**
 * @brief Formats this kind through verba_numerus.u64.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_u64(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.u64, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .val = numer_numerus(args));
}

/**
 * @brief Formats this kind through verba_numerus.i64.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_i64(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.i64, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .sval = args->one->as.i64);
}

/**
 * @brief Formats this kind through verba_numerus.u32w.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_u32w(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.u32w, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .val = numer_numerus(args), .min = numer_latitudo(args));
}

/**
 * @brief Formats this kind through verba_numerus.hex.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_hex(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.hex, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .val = numer_numerus(args), .min = numer_latitudo(args));
}

/**
 * @brief Formats this kind through verba_numerus.uint.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_uint(const NumerCtx *args)
{
    return EMBED_CALL(verba_numerus.uint, VerbaNumerusCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .val = numer_numerus(args), .base = s_kind[args->one->kind].base, .min = numer_latitudo(args));
}

/**
 * @brief Formats this kind through verba_fractio.g.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_g(const NumerCtx *args)
{
    return EMBED_CALL(verba_fractio.g, VerbaFractioCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .real = args->one->as.real, .sig = numer_latitudo(args));
}

/**
 * @brief Formats this kind through verba_fractio.fixed.
 *
 * @param[in] args The arguments this entry reads [BORROWS].
 * @return         The offset past what was written, or args->cap when it did not fit.
 */
static size_t numer_verba_fixed(const NumerCtx *args)
{
    return EMBED_CALL(verba_fractio.fixed, VerbaFractioCfg, .out = args->out, .cap = args->cap, .at = args->at,
                      .real = args->one->as.real, .decimals = numer_latitudo(args));
}
