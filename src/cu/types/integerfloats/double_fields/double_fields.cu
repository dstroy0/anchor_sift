// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "double_fields.h"

// double_fields as one record program, the four functions of double_fields.c on every lane at once. Member 0 is a
// double's bits, the low word then the high word. Member 1 is a merge's request, the sign, the exponent and the
// mantissa's low and high words. The outputs are double_fields_sign, double_fields_exp and double_fields_mant of
// member 0, and double_fields_merge of member 1, in that order.

#define DOUBLE_FIELDS_LOW(value_) ((unsigned int)((unsigned long long)(value_) & 0xFFFFFFFFull))
#define DOUBLE_FIELDS_HIGH(value_) ((unsigned int)((unsigned long long)(value_) >> 32u))

static_assert(ENGINE_DOUBLE_SIGN_SHIFT >= 32u, "the sign is read from the high word");
static_assert(ENGINE_DOUBLE_MANT_BITS >= 32u, "the exponent is read from the high word");

static const EngineRecordStep s_double_fields_steps[] = {
    {ENGINE_RECORD_FIELD, 0u, 0u, 0u},
    {ENGINE_RECORD_FIELD, 1u, 0u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_LOW(1ull << (ENGINE_DOUBLE_SIGN_SHIFT - 32u)), 0u, 0u},
    {ENGINE_RECORD_QUOTIENT, 1u, 2u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_LOW(1ull << (ENGINE_DOUBLE_MANT_BITS - 32u)), 0u, 0u},
    {ENGINE_RECORD_QUOTIENT, 1u, 4u, 0u},
    {ENGINE_RECORD_CONSTANT, ENGINE_DOUBLE_EXP_ALL, 0u, 0u},
    {ENGINE_RECORD_AND, 5u, 6u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_HIGH(ENGINE_DOUBLE_MANT_MASK), 0u, 0u},
    {ENGINE_RECORD_AND, 1u, 8u, 0u},
    {ENGINE_RECORD_CONSTANT, 0u, 1u, 0u},
    {ENGINE_RECORD_PRODUCT, 9u, 10u, 0u},
    {ENGINE_RECORD_SUM, 11u, 0u, 0u},
    {ENGINE_RECORD_FIELD, 2u, 0u, 1u},
    {ENGINE_RECORD_CONSTANT, (unsigned int)ENGINE_DOUBLE_SIGN_ONE, 0u, 0u},
    {ENGINE_RECORD_AND, 13u, 14u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_LOW(ENGINE_DOUBLE_SIGN_MASK), DOUBLE_FIELDS_HIGH(ENGINE_DOUBLE_SIGN_MASK), 0u},
    {ENGINE_RECORD_PRODUCT, 15u, 16u, 0u},
    {ENGINE_RECORD_FIELD, 3u, 0u, 1u},
    {ENGINE_RECORD_AND, 18u, 6u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_LOW(1ull << ENGINE_DOUBLE_MANT_BITS),
     DOUBLE_FIELDS_HIGH(1ull << ENGINE_DOUBLE_MANT_BITS), 0u},
    {ENGINE_RECORD_PRODUCT, 19u, 20u, 0u},
    {ENGINE_RECORD_FIELD, 4u, 0u, 1u},
    {ENGINE_RECORD_FIELD, 5u, 0u, 1u},
    {ENGINE_RECORD_PRODUCT, 23u, 10u, 0u},
    {ENGINE_RECORD_SUM, 24u, 22u, 0u},
    {ENGINE_RECORD_CONSTANT, DOUBLE_FIELDS_LOW(ENGINE_DOUBLE_MANT_MASK), DOUBLE_FIELDS_HIGH(ENGINE_DOUBLE_MANT_MASK),
     0u},
    {ENGINE_RECORD_AND, 25u, 26u, 0u},
    {ENGINE_RECORD_SUM, 17u, 21u, 0u},
    {ENGINE_RECORD_SUM, 28u, 27u, 0u},
};
static const unsigned int s_double_fields_field_bits[] = {32u, 32u, 32u, 32u, 32u, 32u};
static const unsigned int s_double_fields_field_offset[] = {0u, 32u, 0u, 32u, 64u, 96u};
static const unsigned int s_double_fields_outputs[DOUBLE_FIELDS_RECORD_OUTPUTS] = {3u, 7u, 12u, 29u};

extern "C" long double_fields_record(EngineRecordRequest *request)
{
    if (request == NULL)
    {
        return -1L;
    }
    request->steps = s_double_fields_steps;
    request->count = (unsigned int)(sizeof(s_double_fields_steps) / sizeof(s_double_fields_steps[0]));
    request->field_bits = s_double_fields_field_bits;
    request->field_offset = s_double_fields_field_offset;
    request->fields = (unsigned int)(sizeof(s_double_fields_field_bits) / sizeof(s_double_fields_field_bits[0]));
    request->in_limbs[0] = 2u;
    request->in_limbs[1] = 4u;
    request->members = 2u;
    request->outputs = s_double_fields_outputs;
    request->output_count = DOUBLE_FIELDS_RECORD_OUTPUTS;
    request->tables = NULL;
    request->table_count = 0u;
    return 0L;
}
