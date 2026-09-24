// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "double_fields.h"

_Static_assert(sizeof(double) * 8u == ENGINE_DOUBLE_BITS,
               "double is not 64 bits on this target, so every field position in this file is wrong");
_Static_assert(sizeof(unsigned long long) == sizeof(double), "the bit pattern of a double does not fit unsigned long long");
_Static_assert(1u + ENGINE_DOUBLE_EXP_BITS + ENGINE_DOUBLE_MANT_BITS == ENGINE_DOUBLE_BITS,
               "the three fields do not add up to the width of the value");
_Static_assert((ENGINE_DOUBLE_SIGN_MASK | ENGINE_DOUBLE_EXP_MASK | ENGINE_DOUBLE_MANT_MASK) == 0xFFFFFFFFFFFFFFFFull,
               "the three field masks leave a gap");
_Static_assert(((ENGINE_DOUBLE_SIGN_MASK & ENGINE_DOUBLE_EXP_MASK) == 0u)
                   && ((ENGINE_DOUBLE_EXP_MASK & ENGINE_DOUBLE_MANT_MASK) == 0u)
                   && ((ENGINE_DOUBLE_SIGN_MASK & ENGINE_DOUBLE_MANT_MASK) == 0u),
               "the three field masks overlap");
_Static_assert(ENGINE_DOUBLE_SIGN_MASK == (ENGINE_DOUBLE_SIGN_ONE << ENGINE_DOUBLE_SIGN_SHIFT),
               "the sign mask and the sign shift disagree about where the sign is");
_Static_assert(ENGINE_DOUBLE_EXP_MASK == (ENGINE_DOUBLE_EXP_ALL << ENGINE_DOUBLE_MANT_BITS),
               "the exponent mask and the exponent width disagree");
_Static_assert(ENGINE_DOUBLE_EXP_ALL == ((1u << ENGINE_DOUBLE_EXP_BITS) - 1u), "the exponent does not fill its field");
_Static_assert(ENGINE_DOUBLE_BIAS == ((1 << (ENGINE_DOUBLE_EXP_BITS - 1u)) - 1), "the bias is not the one binary64 uses");
_Static_assert(ENGINE_DOUBLE_SCALE_MAX == 971, "the largest scale a finite double can carry is not what it was");
_Static_assert(ENGINE_DOUBLE_SCALE_MIN == -1074, "the smallest scale a subnormal can carry is not what it was");

unsigned long long double_fields_sign(const DoubleFieldsRequest *request)
{
    return (request->bits & ENGINE_DOUBLE_SIGN_MASK) >> ENGINE_DOUBLE_SIGN_SHIFT;
}

unsigned long long double_fields_exp(const DoubleFieldsRequest *request)
{
    return (request->bits & ENGINE_DOUBLE_EXP_MASK) >> ENGINE_DOUBLE_MANT_BITS;
}

unsigned long long double_fields_mant(const DoubleFieldsRequest *request)
{
    return request->bits & ENGINE_DOUBLE_MANT_MASK;
}

unsigned long long double_fields_merge(const DoubleFieldsRequest *request)
{
    return ((request->sign & ENGINE_DOUBLE_SIGN_ONE) << ENGINE_DOUBLE_SIGN_SHIFT)
         | ((request->exp & ENGINE_DOUBLE_EXP_ALL) << ENGINE_DOUBLE_MANT_BITS) | (request->mant & ENGINE_DOUBLE_MANT_MASK);
}

double double_fields_from_bits(const DoubleFieldsRequest *request)
{
    return request->val;
}

unsigned long long double_fields_to_bits(const DoubleFieldsRequest *request)
{
    return request->bits;
}
