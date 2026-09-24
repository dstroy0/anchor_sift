// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DOUBLE_FIELDS_H
#define DOUBLE_FIELDS_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    union
    {
        const double val;
        const unsigned long long bits;
    };
    const unsigned long long sign;
    const unsigned long long exp;
    const unsigned long long mant;
} DoubleFieldsRequest;

unsigned long long double_fields_sign(const DoubleFieldsRequest *request);

unsigned long long double_fields_exp(const DoubleFieldsRequest *request);

unsigned long long double_fields_mant(const DoubleFieldsRequest *request);

unsigned long long double_fields_merge(const DoubleFieldsRequest *request);

double double_fields_from_bits(const DoubleFieldsRequest *request);

unsigned long long double_fields_to_bits(const DoubleFieldsRequest *request);

#ifdef __cplusplus
}
#endif

#endif
