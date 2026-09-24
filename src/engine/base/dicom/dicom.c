// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "dicom.h"

#include "exact_integer.h"
#include "zip.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define DICOM_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_DICOM, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define DICOM_PREAMBLE 128ull
#define DICOM_UNDEFINED 0xFFFFFFFFull
#define DICOM_ITEM_GROUP 0xFFFEu
#define DICOM_ITEM 0xE000u
#define DICOM_ITEM_END 0xE00Du
#define DICOM_SEQUENCE_END 0xE0DDu

static const char dicom_explicit_little[] = "1.2.840.10008.1.2.1";

static const char dicom_implicit_little[] = "1.2.840.10008.1.2";

typedef struct
{
    AnchorExactInteger mantissa;
    long long exponent;
} DicomDecimal;

typedef struct
{
    unsigned char *member;
    unsigned long long member_bytes;
    unsigned long long member_crc;
    char *name;
    unsigned long long name_length;
    unsigned long long pixel_at;
    unsigned long long pixel_bytes;
    unsigned int rows;
    unsigned int columns;
    unsigned int bits_allocated;
    unsigned int bits_stored;
    unsigned int high_bit;
    unsigned int has_stored;
    unsigned int has_high;
    unsigned int pixel_representation;
    unsigned int samples;
    unsigned long long pixel_kept;
    unsigned int has_position;
    unsigned int has_orientation;
    unsigned int has_instance;
    DicomDecimal position[3];
    DicomDecimal orientation[6];
    DicomDecimal instance;
    DicomDecimal key;
    const unsigned char *sop;
    unsigned long long sop_length;
} DicomSlice;

typedef struct
{
    char *path;
    char *member;
    DicomSlice *slices;
    unsigned long long *order;
    unsigned long long count;
    unsigned int keyed;
    int held;
} DicomHeld;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    unsigned long long at;
} DicomWalk;

typedef struct
{
    unsigned int group;
    unsigned int element;
    char vr[2];
    unsigned long long value_at;
    unsigned long long value_length;
    int undefined;
} DicomElement;

static DicomHeld s_dicom_held;

static const DicomSlice *s_dicom_sorting;

static unsigned int s_dicom_keyed;

static unsigned long long dicom_little(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

static int dicom_long_form(const char vr[2])
{
    static const char LONG_FORMS[13][2] = {{'O', 'B'}, {'O', 'D'}, {'O', 'F'}, {'O', 'L'}, {'O', 'V'},
                                          {'O', 'W'}, {'S', 'Q'}, {'U', 'C'}, {'U', 'N'}, {'U', 'R'},
                                          {'U', 'T'}, {'S', 'V'}, {'U', 'V'}};
    for (unsigned int form = 0u; form < 13u; form += 1u)
    {
        if ((vr[0] == LONG_FORMS[form][0]) && (vr[1] == LONG_FORMS[form][1]))
        {
            return 1;
        }
    }
    return 0;
}

static int dicom_element(DicomWalk *walk, int explicit_vr, DicomElement *element, EngineError *error)
{
    if (!DICOM_HELD((walk->at <= walk->length) && ((walk->length - walk->at) >= 8ull), &walk->at, error,
                    ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned char *const head = walk->bytes + walk->at;
    // a tag's group and element are 16 bit fields, and fit an unsigned int exactly
    element->group = (unsigned int)dicom_little(head, 2u);
    // a tag's group and element are 16 bit fields, and fit an unsigned int exactly
    element->element = (unsigned int)dicom_little(head + 2u, 2u);
    element->vr[0] = ' ';
    element->vr[1] = ' ';
    unsigned long long length = 0ull;
    unsigned long long header = 8ull;
    if (element->group == DICOM_ITEM_GROUP)
    {
        length = dicom_little(head + 4u, 4u);
    }
    else if (explicit_vr != 0)
    {
        // a VR is two ASCII characters, each held whole in a char
        element->vr[0] = (char)head[4];
        // a VR is two ASCII characters, each held whole in a char
        element->vr[1] = (char)head[5];
        if (dicom_long_form(element->vr))
        {
            if (!DICOM_HELD((walk->length - walk->at) >= 12ull, head, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            length = dicom_little(head + 8u, 4u);
            header = 12ull;
        }
        else
        {
            length = dicom_little(head + 6u, 2u);
        }
    }
    else
    {
        length = dicom_little(head + 4u, 4u);
    }
    element->value_at = walk->at + header;
    element->undefined = (length == DICOM_UNDEFINED) ? 1 : 0;
    element->value_length = (element->undefined != 0) ? 0ull : length;
    if (!DICOM_HELD((element->undefined != 0) || (element->value_length <= (walk->length - element->value_at)),
                    head, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    walk->at = element->value_at;
    return 1;
}

static int dicom_skip_sequence(DicomWalk *walk, int explicit_vr, EngineError *error);

static int dicom_skip_item(DicomWalk *walk, int explicit_vr, EngineError *error)
{
    for (;;)
    {
        DicomElement element;
        if (!dicom_element(walk, explicit_vr, &element, error))
        {
            return 0;
        }
        if ((element.group == DICOM_ITEM_GROUP) && (element.element == DICOM_ITEM_END))
        {
            return 1;
        }
        if (element.undefined != 0)
        {
            const int nested_explicit = ((element.vr[0] == 'U') && (element.vr[1] == 'N')) ? 0 : explicit_vr;
            if (!dicom_skip_sequence(walk, nested_explicit, error))
            {
                return 0;
            }
            continue;
        }
        walk->at = element.value_at + element.value_length;
    }
}

static int dicom_skip_sequence(DicomWalk *walk, int explicit_vr, EngineError *error)
{
    for (;;)
    {
        DicomElement element;
        if (!dicom_element(walk, explicit_vr, &element, error))
        {
            return 0;
        }
        if (!DICOM_HELD(element.group == DICOM_ITEM_GROUP, walk->bytes + element.value_at, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if (element.element == DICOM_SEQUENCE_END)
        {
            return 1;
        }
        if (!DICOM_HELD(element.element == DICOM_ITEM, walk->bytes + element.value_at, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if (element.undefined != 0)
        {
            if (!dicom_skip_item(walk, explicit_vr, error))
            {
                return 0;
            }
            continue;
        }
        walk->at = element.value_at + element.value_length;
    }
}

static int dicom_decimal_parse(const unsigned char *text, unsigned long long length, DicomDecimal *out,
                               EngineError *error)
{
    unsigned long long at = 0ull;
    while ((at < length) && (text[at] == ' '))
    {
        at += 1ull;
    }
    unsigned long long end = length;
    while ((end > at) && ((text[end - 1ull] == ' ') || (text[end - 1ull] == '\0')))
    {
        end -= 1ull;
    }
    int negative = 0;
    if ((at < end) && ((text[at] == '+') || (text[at] == '-')))
    {
        negative = (text[at] == '-') ? 1 : 0;
        at += 1ull;
    }
    anchor_exact_zero(&out->mantissa);
    unsigned long long count = 0ull;
    long long fraction = 0ll;
    int seen_point = 0;
    while ((at < end) && (((text[at] >= '0') && (text[at] <= '9')) || ((text[at] == '.') && (seen_point == 0))))
    {
        if (text[at] == '.')
        {
            seen_point = 1;
        }
        else
        {
            // a decimal digit character is held whole in a char
            const char digit_text = (char)text[at];
            AnchorExactInteger digit;
            AnchorExactInteger next;
            if (!DICOM_HELD((fraction < LLONG_MAX) && (anchor_exact_scale_by_ten(&out->mantissa, 1u) == ANCHOR_EXACT_OK)
                                && (anchor_exact_from_decimal(&digit_text, 1u, 0u, &digit) == ANCHOR_EXACT_OK)
                                && (anchor_exact_add(&out->mantissa, &digit, &next) == ANCHOR_EXACT_OK),
                            text, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            out->mantissa = next;
            count += 1ull;
            fraction += (seen_point != 0) ? 1ll : 0ll;
        }
        at += 1ull;
    }
    long long exponent = 0ll;
    if ((at < end) && ((text[at] == 'e') || (text[at] == 'E')))
    {
        at += 1ull;
        int exponent_negative = 0;
        if ((at < end) && ((text[at] == '+') || (text[at] == '-')))
        {
            exponent_negative = (text[at] == '-') ? 1 : 0;
            at += 1ull;
        }
        unsigned long long exponent_digits = 0ull;
        while ((at < end) && (text[at] >= '0') && (text[at] <= '9'))
        {
            if (!DICOM_HELD(exponent <= (((LLONG_MAX / 4ll) - 9ll) / 10ll), text, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            // one decimal digit's value, 0 to 9, fits a long long exactly
            exponent = (exponent * 10ll) + (long long)(text[at] - '0');
            exponent_digits += 1ull;
            at += 1ull;
        }
        if (!DICOM_HELD(exponent_digits != 0ull, text, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        exponent = (exponent_negative != 0) ? -exponent : exponent;
    }
    if (!DICOM_HELD((count != 0ull) && (at == end), text, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    out->mantissa.sign = ((negative != 0) && (out->mantissa.sign != 0)) ? -out->mantissa.sign : out->mantissa.sign;
    out->exponent = exponent - fraction;
    return 1;
}

static int dicom_decimal_list(const unsigned char *text, unsigned long long length, unsigned int want, DicomDecimal *out,
                              EngineError *error)
{
    unsigned long long start = 0ull;
    unsigned int found = 0u;
    for (unsigned long long at = 0ull; at <= length; at += 1ull)
    {
        if ((at == length) || (text[at] == '\\'))
        {
            if (!DICOM_HELD(found < want, text, error, ENGINE_ERROR_REQUEST)
                || !dicom_decimal_parse(text + start, at - start, &out[found], error))
            {
                return 0;
            }
            found += 1u;
            start = at + 1ull;
        }
    }
    return DICOM_HELD(found == want, text, error, ENGINE_ERROR_REQUEST);
}

static int dicom_decimal_align(DicomDecimal *value, long long exponent, EngineError *error)
{
    if (!DICOM_HELD((exponent <= value->exponent) && ((value->exponent - exponent) <= (long long)ANCHOR_EXACT_DIGITS),
                    value, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // the gap is at most ANCHOR_EXACT_DIGITS; it fits a uint32_t exactly
    const uint32_t power = (uint32_t)(value->exponent - exponent);
    if (!DICOM_HELD(anchor_exact_scale_by_ten(&value->mantissa, power) == ANCHOR_EXACT_OK, value, error,
                    ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    value->exponent = exponent;
    return 1;
}

static int dicom_decimal_multiply(const DicomDecimal *left, const DicomDecimal *right, DicomDecimal *out,
                                  EngineError *error)
{
    out->exponent = left->exponent + right->exponent;
    return DICOM_HELD(anchor_exact_multiply(&left->mantissa, &right->mantissa, &out->mantissa) == ANCHOR_EXACT_OK, left,
                      error, ENGINE_ERROR_REQUEST);
}

static int dicom_decimal_combine(const DicomDecimal *left, const DicomDecimal *right, int subtract, DicomDecimal *out,
                                 EngineError *error)
{
    DicomDecimal one = *left;
    DicomDecimal other = *right;
    const long long exponent = (one.exponent < other.exponent) ? one.exponent : other.exponent;
    if (!dicom_decimal_align(&one, exponent, error) || !dicom_decimal_align(&other, exponent, error))
    {
        return 0;
    }
    out->exponent = exponent;
    const AnchorExactStatus status = (subtract != 0) ? anchor_exact_subtract(&one.mantissa, &other.mantissa, &out->mantissa)
                                                     : anchor_exact_add(&one.mantissa, &other.mantissa, &out->mantissa);
    return DICOM_HELD(status == ANCHOR_EXACT_OK, left, error, ENGINE_ERROR_REQUEST);
}

static int dicom_cross_term(const DicomDecimal *orientation, unsigned int first, unsigned int second, DicomDecimal *out,
                            EngineError *error)
{
    DicomDecimal ahead;
    DicomDecimal behind;
    return dicom_decimal_multiply(&orientation[first], &orientation[3u + second], &ahead, error)
        && dicom_decimal_multiply(&orientation[second], &orientation[3u + first], &behind, error)
        && dicom_decimal_combine(&ahead, &behind, 1, out, error);
}

static int dicom_slice_key(const DicomDecimal *orientation, DicomSlice *slice, EngineError *error)
{
    DicomDecimal normal[3];
    if (!dicom_cross_term(orientation, 1u, 2u, &normal[0], error) || !dicom_cross_term(orientation, 2u, 0u, &normal[1], error)
        || !dicom_cross_term(orientation, 0u, 1u, &normal[2], error))
    {
        return 0;
    }
    DicomDecimal sum;
    if (!dicom_decimal_multiply(&normal[0], &slice->position[0], &sum, error))
    {
        return 0;
    }
    for (unsigned int axis = 1u; axis < 3u; axis += 1u)
    {
        DicomDecimal term;
        DicomDecimal next;
        if (!dicom_decimal_multiply(&normal[axis], &slice->position[axis], &term, error)
            || !dicom_decimal_combine(&sum, &term, 0, &next, error))
        {
            return 0;
        }
        sum = next;
    }
    slice->key = sum;
    return 1;
}

static int dicom_uid_compare(const unsigned char *left, unsigned long long left_length, const unsigned char *right,
                             unsigned long long right_length)
{
    unsigned long long one = 0ull;
    unsigned long long other = 0ull;
    while ((one < left_length) || (other < right_length))
    {
        unsigned long long one_end = one;
        while ((one_end < left_length) && (left[one_end] != '.'))
        {
            one_end += 1ull;
        }
        unsigned long long other_end = other;
        while ((other_end < right_length) && (right[other_end] != '.'))
        {
            other_end += 1ull;
        }
        while (((one_end - one) > 1ull) && (left[one] == '0'))
        {
            one += 1ull;
        }
        while (((other_end - other) > 1ull) && (right[other] == '0'))
        {
            other += 1ull;
        }
        const unsigned long long one_span = one_end - one;
        const unsigned long long other_span = other_end - other;
        if (one_span != other_span)
        {
            return (one_span < other_span) ? -1 : 1;
        }
        const int differ = (one_span != 0ull) ? memcmp(left + one, right + other, (size_t)one_span) : 0;
        if (differ != 0)
        {
            return (differ < 0) ? -1 : 1;
        }
        one = (one_end < left_length) ? (one_end + 1ull) : one_end;
        other = (other_end < right_length) ? (other_end + 1ull) : other_end;
    }
    return 0;
}

static int dicom_order_slices(const void *left, const void *right)
{
    const DicomSlice *const one = &s_dicom_sorting[*(const unsigned long long *)left];
    const DicomSlice *const other = &s_dicom_sorting[*(const unsigned long long *)right];
    if (s_dicom_keyed != 0u)
    {
        const int keyed = anchor_exact_compare(&one->key.mantissa, &other->key.mantissa);
        if (keyed != 0)
        {
            return keyed;
        }
    }
    if (one->has_instance != other->has_instance)
    {
        return (one->has_instance != 0u) ? -1 : 1;
    }
    if (one->has_instance != 0u)
    {
        const int instance = anchor_exact_compare(&one->instance.mantissa, &other->instance.mantissa);
        if (instance != 0)
        {
            return instance;
        }
    }
    const int uid = dicom_uid_compare(one->sop, one->sop_length, other->sop, other->sop_length);
    if (uid != 0)
    {
        return uid;
    }
    const unsigned long long shorter = (one->name_length < other->name_length) ? one->name_length : other->name_length;
    const int named = memcmp(one->name, other->name, (size_t)shorter);
    if (named != 0)
    {
        return named;
    }
    return (one->name_length < other->name_length) ? -1 : ((one->name_length > other->name_length) ? 1 : 0);
}

static int dicom_us(const DicomWalk *walk, const DicomElement *element, unsigned int *out, EngineError *error)
{
    if (!DICOM_HELD(element->value_length >= 2ull, walk->bytes + element->value_at, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // a US value is 16 bits, and fits an unsigned int exactly
    *out = (unsigned int)dicom_little(walk->bytes + element->value_at, 2u);
    return 1;
}

static int dicom_transfer_syntax(const unsigned char *value, unsigned long long length, int *explicit_vr,
                                 EngineError *error)
{
    unsigned long long end = length;
    while ((end > 0ull) && ((value[end - 1ull] == '\0') || (value[end - 1ull] == ' ')))
    {
        end -= 1ull;
    }
    const unsigned long long explicit_length = sizeof(dicom_explicit_little) - 1u;
    const unsigned long long implicit_length = sizeof(dicom_implicit_little) - 1u;
    if ((end == explicit_length) && (memcmp(value, dicom_explicit_little, (size_t)explicit_length) == 0))
    {
        *explicit_vr = 1;
        return 1;
    }
    if ((end == implicit_length) && (memcmp(value, dicom_implicit_little, (size_t)implicit_length) == 0))
    {
        *explicit_vr = 0;
        return 1;
    }
    return DICOM_HELD(0, value, error, ENGINE_ERROR_REQUEST);
}

static int dicom_parse(DicomSlice *slice, EngineError *error)
{
    const unsigned char *const bytes = slice->member;
    if (!DICOM_HELD((slice->member_bytes >= (DICOM_PREAMBLE + 4ull)) && (memcmp(bytes + DICOM_PREAMBLE, "DICM", 4u) == 0),
                    bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    DicomWalk walk = {bytes, slice->member_bytes, DICOM_PREAMBLE + 4ull};
    int explicit_vr = -1;
    while (((walk.length - walk.at) >= 8ull) && (dicom_little(bytes + walk.at, 2u) == 0x0002ull))
    {
        DicomElement element;
        if (!dicom_element(&walk, 1, &element, error)
            || !DICOM_HELD(element.undefined == 0, bytes + element.value_at, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if ((element.element == 0x0010u)
            && !dicom_transfer_syntax(bytes + element.value_at, element.value_length, &explicit_vr, error))
        {
            return 0;
        }
        walk.at = element.value_at + element.value_length;
    }
    if (!DICOM_HELD(explicit_vr >= 0, bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned int seen_pixels = 0u;
    unsigned int seen_rows = 0u;
    unsigned int seen_columns = 0u;
    unsigned int seen_bits = 0u;
    unsigned int seen_samples = 0u;
    unsigned long long pixel_value_length = 0ull;
    while ((seen_pixels == 0u) && (walk.at < walk.length))
    {
        DicomElement element;
        if (!dicom_element(&walk, explicit_vr, &element, error))
        {
            return 0;
        }
        const unsigned char *const value = bytes + element.value_at;
        const unsigned int tag_group = element.group;
        const unsigned int tag_element = element.element;
        if ((tag_group == 0x7FE0u) && (tag_element == 0x0010u))
        {
            if (!DICOM_HELD(element.undefined == 0, value, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            slice->pixel_at = element.value_at;
            pixel_value_length = element.value_length;
            seen_pixels = 1u;
            continue;
        }
        if (element.undefined != 0)
        {
            const int nested_explicit = ((element.vr[0] == 'U') && (element.vr[1] == 'N')) ? 0 : explicit_vr;
            if (!dicom_skip_sequence(&walk, nested_explicit, error))
            {
                return 0;
            }
            continue;
        }
        int good = 1;
        if ((tag_group == 0x0028u) && (tag_element == 0x0002u))
        {
            good = dicom_us(&walk, &element, &slice->samples, error);
            seen_samples = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0010u))
        {
            good = dicom_us(&walk, &element, &slice->rows, error);
            seen_rows = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0011u))
        {
            good = dicom_us(&walk, &element, &slice->columns, error);
            seen_columns = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0100u))
        {
            good = dicom_us(&walk, &element, &slice->bits_allocated, error);
            seen_bits = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0101u))
        {
            good = dicom_us(&walk, &element, &slice->bits_stored, error);
            slice->has_stored = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0102u))
        {
            good = dicom_us(&walk, &element, &slice->high_bit, error);
            slice->has_high = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0103u))
        {
            good = dicom_us(&walk, &element, &slice->pixel_representation, error);
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0032u) && (element.value_length != 0ull))
        {
            good = dicom_decimal_list(value, element.value_length, 3u, slice->position, error);
            slice->has_position = 1u;
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0037u) && (element.value_length != 0ull))
        {
            good = dicom_decimal_list(value, element.value_length, 6u, slice->orientation, error);
            slice->has_orientation = 1u;
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0013u) && (element.value_length != 0ull))
        {
            good = dicom_decimal_list(value, element.value_length, 1u, &slice->instance, error);
            slice->has_instance = 1u;
        }
        else if ((tag_group == 0x0008u) && (tag_element == 0x0018u))
        {
            unsigned long long end = element.value_length;
            while ((end > 0ull) && ((value[end - 1ull] == '\0') || (value[end - 1ull] == ' ')))
            {
                end -= 1ull;
            }
            slice->sop = value;
            slice->sop_length = end;
        }
        if (!good)
        {
            return 0;
        }
        walk.at = element.value_at + element.value_length;
    }
    if (!DICOM_HELD((seen_pixels != 0u) && (seen_rows != 0u) && (seen_columns != 0u) && (seen_bits != 0u)
                        && (seen_samples != 0u) && ((slice->bits_allocated % 8u) == 0u) && (slice->bits_allocated != 0u),
                    bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    slice->pixel_bytes = (unsigned long long)slice->rows * slice->columns * slice->samples * (slice->bits_allocated / 8u);
    const int signed_held = (slice->pixel_representation == 0u)
                         || ((slice->has_stored != 0u) && (slice->has_high != 0u) && (slice->bits_stored != 0u)
                             && (slice->high_bit < slice->bits_allocated) && (slice->bits_stored <= (slice->high_bit + 1u)));
    return DICOM_HELD(slice->pixel_bytes <= pixel_value_length, bytes + slice->pixel_at, error, ENGINE_ERROR_REQUEST)
        && DICOM_HELD(signed_held, &slice->bits_stored, error, ENGINE_ERROR_REQUEST);
}

static void dicom_held_release(void)
{
    DicomHeld *const held = &s_dicom_held;
    for (unsigned long long slot = 0ull; (held->slices != NULL) && (slot < held->count); slot += 1ull)
    {
        free(held->slices[slot].member);
        free(held->slices[slot].name);
    }
    free(held->slices);
    free(held->order);
    free(held->path);
    free(held->member);
    memset(held, 0, sizeof(*held));
}

static int dicom_prefix_length(const unsigned char *name, unsigned long long length, unsigned long long *prefix)
{
    unsigned long long last = length;
    while ((last > 0ull) && (name[last - 1ull] != '/'))
    {
        last -= 1ull;
    }
    *prefix = last;
    return (last != 0ull) ? 1 : 0;
}

static int dicom_gather(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                        unsigned long long first, unsigned long long count, EngineError *error)
{
    DicomHeld *const held = &s_dicom_held;
    held->slices = (DicomSlice *)calloc((size_t)count + 1u, sizeof(DicomSlice));
    held->order = (unsigned long long *)calloc((size_t)count + 1u, sizeof(unsigned long long));
    if (!DICOM_HELD((held->slices != NULL) && (held->order != NULL), &held->slices, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    const unsigned char *series = NULL;
    unsigned long long series_length = 0ull;
    for (unsigned long long slot = first; slot < (first + count); slot += 1ull)
    {
        ZipEntry entry;
        if (!zip_entry_at(archive, slot, &entry, error))
        {
            return 0;
        }
        if ((entry.name_length == 0ull) || (entry.name[entry.name_length - 1ull] == '/'))
        {
            continue;
        }
        unsigned long long prefix = 0ull;
        const int named = dicom_prefix_length(entry.name, entry.name_length, &prefix);
        if (series == NULL)
        {
            series = entry.name;
            series_length = prefix;
        }
        if (!DICOM_HELD(named && (prefix == series_length) && (memcmp(entry.name, series, (size_t)prefix) == 0),
                        entry.name, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        DicomSlice *const slice = &held->slices[held->count];
        slice->member = (unsigned char *)malloc((size_t)entry.uncompressed + 1u);
        slice->name = (char *)malloc((size_t)entry.name_length + 1u);
        if (!DICOM_HELD((slice->member != NULL) && (slice->name != NULL), &entry, error, ENGINE_ERROR_RESOURCE))
        {
            held->count += 1ull;
            return 0;
        }
        held->count += 1ull;
        memcpy(slice->name, entry.name, (size_t)entry.name_length);
        slice->name[entry.name_length] = '\0';
        slice->name_length = entry.name_length;
        slice->member_crc = entry.crc;
        slice->member_bytes = entry.uncompressed;
        if ((zip_member_read(tools, path, archive, &entry, slice->member, entry.uncompressed, error) == ZIP_REFUSED)
            || !dicom_parse(slice, error))
        {
            return 0;
        }
    }
    return DICOM_HELD(held->count != 0ull, archive, error, ENGINE_ERROR_REQUEST);
}

static int dicom_agree(EngineError *error)
{
    DicomHeld *const held = &s_dicom_held;
    const DicomSlice *const lead = &held->slices[0];
    unsigned int keyed = 1u;
    for (unsigned long long slot = 0ull; slot < held->count; slot += 1ull)
    {
        const DicomSlice *const slice = &held->slices[slot];
        if (!DICOM_HELD((slice->rows == lead->rows) && (slice->columns == lead->columns)
                            && (slice->bits_allocated == lead->bits_allocated) && (slice->samples == lead->samples)
                            && (slice->pixel_representation == lead->pixel_representation),
                        slice, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        keyed = ((keyed != 0u) && (slice->has_position != 0u) && (lead->has_orientation != 0u)) ? 1u : 0u;
    }
    held->keyed = keyed;
    return DICOM_HELD(lead->samples == 1u, lead, error, ENGINE_ERROR_REQUEST);
}

static int dicom_sort(EngineError *error)
{
    DicomHeld *const held = &s_dicom_held;
    long long key_floor = 0ll;
    long long instance_floor = 0ll;
    for (unsigned long long slot = 0ull; slot < held->count; slot += 1ull)
    {
        DicomSlice *const slice = &held->slices[slot];
        held->order[slot] = slot;
        if ((held->keyed != 0u) && !dicom_slice_key(held->slices[0].orientation, slice, error))
        {
            return 0;
        }
        key_floor = ((slot == 0ull) || (slice->key.exponent < key_floor)) ? slice->key.exponent : key_floor;
        instance_floor = ((slot == 0ull) || (slice->instance.exponent < instance_floor)) ? slice->instance.exponent
                                                                                          : instance_floor;
    }
    for (unsigned long long slot = 0ull; slot < held->count; slot += 1ull)
    {
        DicomSlice *const slice = &held->slices[slot];
        if (((held->keyed != 0u) && !dicom_decimal_align(&slice->key, key_floor, error))
            || ((slice->has_instance != 0u) && !dicom_decimal_align(&slice->instance, instance_floor, error)))
        {
            return 0;
        }
    }
    s_dicom_sorting = held->slices;
    s_dicom_keyed = held->keyed;
    qsort(held->order, (size_t)held->count, sizeof(unsigned long long), dicom_order_slices);
    s_dicom_sorting = NULL;
    return 1;
}

static int dicom_hold(const EngineIngestTools *tools, const char *path, const char *member, EngineError *error)
{
    DicomHeld *const held = &s_dicom_held;
    if (!DICOM_HELD((tools != NULL) && (path != NULL) && (member != NULL), &path, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if ((held->held != 0) && (strcmp(held->path, path) == 0) && (strcmp(held->member, member) == 0))
    {
        return 1;
    }
    dicom_held_release();
    const ZipArchive *const archive = zip_archive_held(tools, path, error);
    unsigned long long first = 0ull;
    unsigned long long count = 0ull;
    if ((archive == NULL) || !zip_folder_find(archive, member, &first, &count)
        || !DICOM_HELD(count != 0ull, member, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if (!dicom_gather(tools, path, archive, first, count, error) || !dicom_agree(error) || !dicom_sort(error))
    {
        dicom_held_release();
        return 0;
    }
    held->path = (char *)malloc(strlen(path) + 1u);
    held->member = (char *)malloc(strlen(member) + 1u);
    if (!DICOM_HELD((held->path != NULL) && (held->member != NULL), held, error, ENGINE_ERROR_RESOURCE))
    {
        dicom_held_release();
        return 0;
    }
    memcpy(held->path, path, strlen(path) + 1u);
    memcpy(held->member, member, strlen(member) + 1u);
    held->held = 1;
    return 1;
}

static void dicom_shape(EngineArrayShape *shape)
{
    const DicomHeld *const held = &s_dicom_held;
    const DicomSlice *const lead = &held->slices[0];
    memset(shape, 0, sizeof(*shape));
    shape->rank = 4u;
    shape->shape[0] = 1ull;
    shape->shape[1] = held->count;
    shape->shape[2] = lead->rows;
    shape->shape[3] = lead->columns;
    memcpy(shape->axes, "tzyx", 4u);
    shape->element_bytes = lead->bits_allocated / 8u;
    shape->element_kind = (lead->pixel_representation != 0u) ? ENGINE_ELEMENT_SIGNED : ENGINE_ELEMENT_UNSIGNED;
}

int dicom_zip_holds(const EngineIngestTools *tools, const char *path, const char *member)
{
    EngineError probe;
    memset(&probe, 0, sizeof(probe));
    const ZipArchive *const archive = (member != NULL) ? zip_archive_held(tools, path, &probe) : NULL;
    unsigned long long first = 0ull;
    unsigned long long count = 0ull;
    if ((archive == NULL) || !zip_folder_find(archive, member, &first, &count))
    {
        return 0;
    }
    for (unsigned long long slot = first; slot < (first + count); slot += 1ull)
    {
        ZipEntry entry;
        if (!zip_entry_at(archive, slot, &entry, &probe))
        {
            return 0;
        }
        if ((entry.name_length == 0ull) || (entry.name[entry.name_length - 1ull] == '/'))
        {
            continue;
        }
        unsigned char *const member = (unsigned char *)malloc((size_t)entry.uncompressed + 1u);
        const int read = (member != NULL)
                      && (zip_member_read(tools, path, archive, &entry, member, entry.uncompressed, &probe) != ZIP_REFUSED);
        const int holds = read && (entry.uncompressed >= (DICOM_PREAMBLE + 4ull))
                       && (memcmp(member + DICOM_PREAMBLE, "DICM", 4u) == 0);
        free(member);
        return holds ? 1 : 0;
    }
    return 0;
}

long dicom_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1L;
    }
    if (!DICOM_HELD(request->shape != NULL, request, request->error, ENGINE_ERROR_REQUEST)
        || !dicom_hold(request->tools, request->path, request->member, request->error))
    {
        return -1L;
    }
    dicom_shape(request->shape);
    return 0L;
}

static unsigned long long dicom_sign_extend(const DicomSlice *slice, unsigned char *pixels)
{
    const unsigned int element_bytes = slice->bits_allocated / 8u;
    const unsigned int width = 8u * element_bytes;
    const unsigned long long whole = (width >= 64u) ? ~0ull : ((1ull << width) - 1ull);
    const unsigned int low = (slice->high_bit + 1u) - slice->bits_stored;
    const unsigned long long field = (slice->bits_stored >= 64u) ? ~0ull : ((1ull << slice->bits_stored) - 1ull);
    const unsigned long long sign = 1ull << (slice->bits_stored - 1u);
    const unsigned long long elements = slice->pixel_bytes / element_bytes;
    unsigned long long kept = 0ull;
    for (unsigned long long element = 0ull; element < elements; element += 1ull)
    {
        unsigned char *const at = pixels + (element * element_bytes);
        unsigned long long word = 0ull;
        for (unsigned int place = element_bytes; place > 0u; place -= 1u)
        {
            word = (word << 8u) | (unsigned long long)at[place - 1u];
        }
        const unsigned long long stored = (word >> low) & field;
        const unsigned long long extended = ((stored & sign) != 0ull) ? ((stored | ~field) & whole) : stored;
        const unsigned long long canonical = (extended << low) & whole;
        kept |= (canonical != word) ? 1ull : 0ull;
        for (unsigned int place = 0u; place < element_bytes; place += 1u)
        {
            // one byte of the extended word is taken whole
            at[place] = (unsigned char)((extended >> (8u * place)) & 0xFFull);
        }
    }
    return kept;
}

static void dicom_side_release(EngineSideBytes *side)
{
    free(side->pixel_at);
    free(side->pixel_kept);
    free(side->byte_start);
    free(side->bytes);
    free(side->name_start);
    free(side->names);
    free(side->member_crc);
    free(side->member_bytes);
    memset(side, 0, sizeof(*side));
}

static int dicom_side_fill(EngineSideBytes *side, EngineError *error)
{
    const DicomHeld *const held = &s_dicom_held;
    unsigned long long kept = 0ull;
    unsigned long long named = 0ull;
    for (unsigned long long slot = 0ull; slot < held->count; slot += 1ull)
    {
        const DicomSlice *const slice = &held->slices[slot];
        kept += slice->member_bytes - ((slice->pixel_kept != 0ull) ? 0ull : slice->pixel_bytes);
        named += slice->name_length;
    }
    memset(side, 0, sizeof(*side));
    side->pixel_at = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    side->pixel_kept = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    side->byte_start = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    side->bytes = (unsigned char *)malloc((size_t)kept + 1u);
    side->name_start = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    side->names = (char *)malloc((size_t)named + 1u);
    side->member_crc = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    side->member_bytes = (unsigned long long *)calloc((size_t)held->count + 1u, sizeof(unsigned long long));
    if (!DICOM_HELD((side->pixel_at != NULL) && (side->pixel_kept != NULL) && (side->byte_start != NULL)
                        && (side->bytes != NULL)
                        && (side->name_start != NULL) && (side->names != NULL) && (side->member_crc != NULL)
                        && (side->member_bytes != NULL),
                    side, error, ENGINE_ERROR_RESOURCE))
    {
        dicom_side_release(side);
        return 0;
    }
    unsigned long long byte_at = 0ull;
    unsigned long long name_at = 0ull;
    for (unsigned long long place = 0ull; place < held->count; place += 1ull)
    {
        const DicomSlice *const slice = &held->slices[held->order[place]];
        const unsigned long long after = (slice->pixel_kept != 0ull) ? slice->pixel_at
                                                                      : (slice->pixel_at + slice->pixel_bytes);
        side->pixel_at[place] = slice->pixel_at;
        side->pixel_kept[place] = slice->pixel_kept;
        side->byte_start[place] = byte_at;
        memcpy(side->bytes + byte_at, slice->member, (size_t)slice->pixel_at);
        byte_at += slice->pixel_at;
        memcpy(side->bytes + byte_at, slice->member + after, (size_t)(slice->member_bytes - after));
        byte_at += slice->member_bytes - after;
        side->name_start[place] = name_at;
        memcpy(side->names + name_at, slice->name, (size_t)slice->name_length);
        name_at += slice->name_length;
        side->member_crc[place] = slice->member_crc;
        side->member_bytes[place] = slice->member_bytes;
    }
    side->byte_start[held->count] = byte_at;
    side->name_start[held->count] = name_at;
    side->leaves = held->count;
    return 1;
}

long long dicom_read(const EngineArrayRead *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1LL;
    }
    EngineError *const error = request->error;
    if (!DICOM_HELD((request->shape != NULL) && (request->out != NULL), request, error, ENGINE_ERROR_REQUEST)
        || !dicom_hold(request->tools, request->path, request->member, error))
    {
        return -1LL;
    }
    EngineArrayShape found;
    dicom_shape(&found);
    const DicomHeld *const held = &s_dicom_held;
    const unsigned long long slice_bytes = held->slices[0].pixel_bytes;
    const unsigned long long total = slice_bytes * held->count;
    int agrees = (found.rank == request->shape->rank) && (found.element_bytes == request->shape->element_bytes)
              && (found.element_kind == request->shape->element_kind) && (request->first == 0ull)
              && (request->past == 1ull) && (total <= request->out_room);
    for (unsigned int axis = 0u; agrees && (axis < found.rank); axis += 1u)
    {
        agrees = (found.shape[axis] == request->shape->shape[axis]);
    }
    if (!DICOM_HELD(agrees, request->shape, error, ENGINE_ERROR_REQUEST))
    {
        dicom_held_release();
        return -1LL;
    }
    for (unsigned long long place = 0ull; place < held->count; place += 1ull)
    {
        DicomSlice *const slice = &held->slices[held->order[place]];
        unsigned char *const pixels = request->out + (place * slice_bytes);
        memcpy(pixels, slice->member + slice->pixel_at, (size_t)slice_bytes);
        if (slice->pixel_representation != 0u)
        {
            slice->pixel_kept = dicom_sign_extend(slice, pixels);
        }
    }
    const int sided = (request->side == NULL) || dicom_side_fill(request->side, error);
    dicom_held_release();
    // the total fits the caller's room, a size in memory, and so fits a long long
    return sided ? (long long)total : -1LL;
}
