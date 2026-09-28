// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// dicom_decimal.c: decimal strings and the order of slices
#include "dicom_internal.h"

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
            // a decimal digit character fits in a char
            const char digit_text = (char)text[at];
            AnchorExactInteger digit;
            AnchorExactInteger next;
            if (!DICOM_CHECK((fraction < LLONG_MAX) &&
                                 (anchor_exact_scale_by_ten(&out->mantissa, 1u) == ANCHOR_EXACT_OK) &&
                                 (anchor_exact_from_decimal(&digit_text, 1u, 0u, &digit) == ANCHOR_EXACT_OK) &&
                                 (anchor_exact_add(&out->mantissa, &digit, &next) == ANCHOR_EXACT_OK),
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
            if (!DICOM_CHECK(exponent <= (((LLONG_MAX / 4ll) - 9ll) / 10ll), text, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            // one decimal digit's value, 0 to 9, fits a long long exactly
            exponent = (exponent * 10ll) + (long long)(text[at] - '0');
            exponent_digits += 1ull;
            at += 1ull;
        }
        if (!DICOM_CHECK(exponent_digits != 0ull, text, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        exponent = (exponent_negative != 0) ? -exponent : exponent;
    }
    if (!DICOM_CHECK((count != 0ull) && (at == end), text, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    out->mantissa.sign = ((negative != 0) && (out->mantissa.sign != 0)) ? -out->mantissa.sign : out->mantissa.sign;
    out->exponent = exponent - fraction;
    return 1;
}

int dicom_decimal_list(const unsigned char *text, unsigned long long length, unsigned int want, DicomDecimal *out,
                       EngineError *error)
{
    unsigned long long start = 0ull;
    unsigned int found = 0u;
    for (unsigned long long at = 0ull; at <= length; at += 1ull)
    {
        if ((at == length) || (text[at] == '\\'))
        {
            if (!DICOM_CHECK(found < want, text, error, ENGINE_ERROR_REQUEST) ||
                !dicom_decimal_parse(text + start, at - start, &out[found], error))
            {
                return 0;
            }
            found += 1u;
            start = at + 1ull;
        }
    }
    return DICOM_CHECK(found == want, text, error, ENGINE_ERROR_REQUEST);
}

int dicom_decimal_align(DicomDecimal *value, long long exponent, EngineError *error)
{
    if (!DICOM_CHECK((exponent <= value->exponent) && ((value->exponent - exponent) <= (long long)ANCHOR_EXACT_DIGITS),
                     value, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // the gap is at most ANCHOR_EXACT_DIGITS. It fits a uint32_t exactly
    const uint32_t power = (uint32_t)(value->exponent - exponent);
    if (!DICOM_CHECK(anchor_exact_scale_by_ten(&value->mantissa, power) == ANCHOR_EXACT_OK, value, error,
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
    return DICOM_CHECK(anchor_exact_multiply(&left->mantissa, &right->mantissa, &out->mantissa) == ANCHOR_EXACT_OK,
                       left, error, ENGINE_ERROR_REQUEST);
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
    const AnchorExactStatus status = (subtract != 0)
                                         ? anchor_exact_subtract(&one.mantissa, &other.mantissa, &out->mantissa)
                                         : anchor_exact_add(&one.mantissa, &other.mantissa, &out->mantissa);
    return DICOM_CHECK(status == ANCHOR_EXACT_OK, left, error, ENGINE_ERROR_REQUEST);
}

static int dicom_cross_term(const DicomDecimal *orientation, unsigned int first, unsigned int second, DicomDecimal *out,
                            EngineError *error)
{
    DicomDecimal ahead;
    DicomDecimal behind;
    return dicom_decimal_multiply(&orientation[first], &orientation[3u + second], &ahead, error) &&
           dicom_decimal_multiply(&orientation[second], &orientation[3u + first], &behind, error) &&
           dicom_decimal_combine(&ahead, &behind, 1, out, error);
}

int dicom_slice_key(const DicomDecimal *orientation, DicomSlice *slice, EngineError *error)
{
    DicomDecimal normal[3];
    if (!dicom_cross_term(orientation, 1u, 2u, &normal[0], error) ||
        !dicom_cross_term(orientation, 2u, 0u, &normal[1], error) ||
        !dicom_cross_term(orientation, 0u, 1u, &normal[2], error))
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
        if (!dicom_decimal_multiply(&normal[axis], &slice->position[axis], &term, error) ||
            !dicom_decimal_combine(&sum, &term, 0, &next, error))
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

int dicom_order_slices(const void *left, const void *right)
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
