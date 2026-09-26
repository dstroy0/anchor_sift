// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle.h"
#include "exact_integer.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(ANCHOR_EXACT_LIMBS >= 2u, "cycle: a record constant is 64 bits and needs two limbs");

#define CYCLE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

static int cycle_host_fits(const AnchorExactInteger *value, unsigned int limbs)
{
    for (unsigned int at = limbs; at < ANCHOR_EXACT_LIMBS; at += 1u)
    {
        if (value->limb[at] != 0u)
        {
            return 0;
        }
    }
    return 1;
}

static void cycle_host_settle(AnchorExactInteger *value, int32_t sign)
{
    int zero = 1;
    for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at += 1u)
    {
        zero = zero && (value->limb[at] == 0u);
    }
    value->sign = zero ? 0 : sign;
}

static unsigned int cycle_host_limb(const unsigned int *value, unsigned int limbs, unsigned int at)
{
    return (at < limbs) ? value[at] : 0u;
}

static void cycle_host_field(const unsigned int *atom, unsigned int in_limbs, unsigned int offset, unsigned int bits,
                             unsigned int limbs, AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = offset + (32u * limb);
        const unsigned int word = bit / 32u;
        const unsigned int shift = bit % 32u;
        unsigned int gathered = cycle_host_limb(atom, in_limbs, word) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_host_limb(atom, in_limbs, word + 1u) << (32u - shift);
        }
        const unsigned int left = bits - (32u * limb);
        value->limb[limb] = (left < 32u) ? (gathered & ((1u << left) - 1u)) : gathered;
    }
    cycle_host_settle(value, 1);
}

static int cycle_host_ladder(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                             unsigned int *band)
{
    AnchorExactInteger magnitude = *numerator;
    magnitude.sign = (numerator->sign != 0) ? 1 : 0;
    unsigned long long lower = 0ull;
    unsigned long long upper = 1ull;
    unsigned int counted = 0u;
    int below = 1;
    for (unsigned int rung = 1u; (below != 0) && (rung < ENGINE_GOLDEN_RUNGS); rung += 1u)
    {
        AnchorExactInteger step;
        AnchorExactInteger reached;
        anchor_exact_zero(&step);
        step.limb[0] = (uint32_t)(upper & 0xFFFFFFFFull);
        step.limb[1] = (uint32_t)(upper >> 32u);
        cycle_host_settle(&step, 1);
        if (anchor_exact_multiply(&step, denominator, &reached) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
        below = (anchor_exact_compare(&reached, &magnitude) <= 0) ? 1 : 0;
        counted += (unsigned int)below;
        const unsigned long long next = lower + upper;
        lower = upper;
        upper = next;
    }
    *band = counted;
    return 1;
}

// limb `at` of an integer's two's complement, the device's cycle_record_complement: `carry` starts at 1 and the limbs
// are taken from the lowest up
static uint32_t cycle_host_complement(const AnchorExactInteger *value, unsigned int at, unsigned long long *carry)
{
    if (value->sign >= 0)
    {
        return value->limb[at];
    }
    const unsigned long long total = (unsigned long long)(~value->limb[at] & 0xFFFFFFFFu) + *carry;
    *carry = total >> 32u;
    return (uint32_t)(total & 0xFFFFFFFFull);
}

// the low `limbs` of a two's complement read back as a magnitude, masked to `bits`, and settled with `negative`
static void cycle_host_uncomplement(AnchorExactInteger *value, unsigned int limbs, unsigned int bits, int negative)
{
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; (negative != 0) && (at < limbs); at += 1u)
    {
        const unsigned long long total = (unsigned long long)(~value->limb[at] & 0xFFFFFFFFu) + carry;
        value->limb[at] = (uint32_t)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    const unsigned int kept = bits - (32u * (limbs - 1u));
    value->limb[limbs - 1u] &= (kept < 32u) ? ((1u << kept) - 1u) : 0xFFFFFFFFu;
    cycle_host_settle(value, (negative != 0) ? -1 : 1);
}

// the xor or the and over the step's limbs, its sign the operands' (the xor negative where exactly one is, the and
// where both are), as the device's cycle_record_bitwise
static void cycle_host_bitwise(const DeviceRecordStep *step, const AnchorExactInteger *left,
                               const AnchorExactInteger *right, AnchorExactInteger *value)
{
    AnchorExactInteger result;
    anchor_exact_zero(&result);
    unsigned long long left_carry = 1ull;
    unsigned long long right_carry = 1ull;
    for (unsigned int at = 0u; at < step->limbs; at += 1u)
    {
        const uint32_t one = cycle_host_complement(left, at, &left_carry);
        const uint32_t other = cycle_host_complement(right, at, &right_carry);
        result.limb[at] = (step->operation == ENGINE_RECORD_XOR) ? (one ^ other) : (one & other);
    }
    const int left_negative = (left->sign < 0) ? 1 : 0;
    const int right_negative = (right->sign < 0) ? 1 : 0;
    const int negative = (step->operation == ENGINE_RECORD_XOR) ? (left_negative ^ right_negative)
                                                                : (left_negative & right_negative);
    cycle_host_uncomplement(&result, step->limbs, 32u * step->limbs, negative);
    *value = result;
}

// the two's complement wrap to the step's wrap_bits, as the device's cycle_record_wrap
static void cycle_host_wrap(const DeviceRecordStep *step, const AnchorExactInteger *source, AnchorExactInteger *value)
{
    if (step->wrap_bits > (32u * step->limbs))
    {
        *value = *source;
        return;
    }
    AnchorExactInteger result;
    anchor_exact_zero(&result);
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; at < step->limbs; at += 1u)
    {
        result.limb[at] = cycle_host_complement(source, at, &carry);
    }
    const unsigned int kept = step->wrap_bits - (32u * (step->limbs - 1u));
    result.limb[step->limbs - 1u] &= (kept < 32u) ? ((1u << kept) - 1u) : 0xFFFFFFFFu;
    const unsigned int top = step->wrap_bits - 1u;
    const int negative = (((result.limb[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    cycle_host_uncomplement(&result, step->limbs, step->wrap_bits, negative);
    *value = result;
}

static void cycle_host_put(unsigned int *record, unsigned int offset, unsigned int bits,
                           const AnchorExactInteger *value)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int held = (bit < (32u * ANCHOR_EXACT_LIMBS)) ? ((value->limb[bit / 32u] >> (bit % 32u)) & 1u)
                                                                      : 0u;
        unsigned int written = held;
        if (value->sign < 0)
        {
            const unsigned int flipped = (held ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        record[to / 32u] |= written << (to % 32u);
    }
}

static int cycle_host_step(const DeviceRecordStep *step, const unsigned int *atom, unsigned int in_limbs,
                           const AnchorExactInteger *file, const unsigned int *tables, AnchorExactInteger *value)
{
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        cycle_host_field(atom, in_limbs, step->left, step->right, step->limbs, value);
        return 1;
    }
    if (step->operation == ENGINE_RECORD_FIELD_SIGNED)
    {
        cycle_host_field(atom, in_limbs, step->left, step->right, step->limbs, value);
        const unsigned int top = step->right - 1u;
        const int negative = (((value->limb[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
        unsigned long long carry = 1ull;
        for (unsigned int at = 0u; (negative != 0) && (at < step->limbs); at += 1u)
        {
            const unsigned long long total = (unsigned long long)(~value->limb[at] & 0xFFFFFFFFu) + carry;
            value->limb[at] = (uint32_t)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        const unsigned int left = step->right - (32u * (step->limbs - 1u));
        value->limb[step->limbs - 1u] &= (left < 32u) ? ((1u << left) - 1u) : 0xFFFFFFFFu;
        cycle_host_settle(value, (negative != 0) ? -1 : 1);
        return 1;
    }
    if (step->operation == ENGINE_RECORD_CONSTANT)
    {
        anchor_exact_zero(value);
        value->limb[0] = step->left;
        value->limb[1] = (step->limbs > 1u) ? step->right : 0u;
        cycle_host_settle(value, 1);
        return 1;
    }
    if (step->operation == ENGINE_RECORD_TABLE)
    {
        const AnchorExactInteger *const source = &file[step->left];
        const unsigned int index = (step->index_bits >= 32u) ? source->limb[0]
                                                             : (source->limb[0] & ((1u << step->index_bits) - 1u));
        anchor_exact_zero(value);
        const unsigned int *const entry = &tables[step->table_offset + (index * step->limbs)];
        for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
        {
            value->limb[limb] = entry[limb];
        }
        cycle_host_settle(value, 1);
        return 1;
    }
    const AnchorExactInteger *const left = &file[step->left];
    const AnchorExactInteger *const right = &file[step->right];
    if (step->operation == ENGINE_RECORD_PRODUCT)
    {
        return anchor_exact_multiply(left, right, value) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_SUM)
    {
        return anchor_exact_add(left, right, value) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_DIFFERENCE)
    {
        return anchor_exact_subtract(left, right, value) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_ABSOLUTE)
    {
        *value = *left;
        value->sign = (left->sign != 0) ? 1 : 0;
        return 1;
    }
    if (step->operation == ENGINE_RECORD_COMPARE)
    {
        const int order = anchor_exact_compare(left, right);
        anchor_exact_zero(value);
        value->limb[0] = (order != 0) ? 1u : 0u;
        value->sign = order;
        return 1;
    }
    if (step->operation == ENGINE_RECORD_QUOTIENT)
    {
        AnchorExactInteger rest;
        return anchor_exact_divide(left, right, value, &rest) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_REMAINDER)
    {
        AnchorExactInteger whole;
        return anchor_exact_divide(left, right, &whole, value) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_GCD)
    {
        return anchor_exact_gcd(left, right, value) == ANCHOR_EXACT_OK;
    }
    if (step->operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        return anchor_exact_divide_exact(left, right, value) == ANCHOR_EXACT_OK;
    }
    if ((step->operation == ENGINE_RECORD_XOR) || (step->operation == ENGINE_RECORD_AND))
    {
        cycle_host_bitwise(step, left, right, value);
        return 1;
    }
    if (step->operation == ENGINE_RECORD_WRAP)
    {
        cycle_host_wrap(step, left, value);
        return 1;
    }
    if ((step->operation == ENGINE_RECORD_LADDER) && (right->sign > 0))
    {
        unsigned int band = 0u;
        if (cycle_host_ladder(left, right, &band) == 0)
        {
            return 0;
        }
        anchor_exact_zero(value);
        value->limb[0] = band;
        cycle_host_settle(value, left->sign);
        return 1;
    }
    return 0;
}

long cycle_record_run_host(const CycleRecordHostRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    const EngineRecordLayout *const layout = request->layout;
    if (!CYCLE_HELD((layout != NULL) && (request->out != NULL), request, error, ENGINE_ERROR_REQUEST)
     || !CYCLE_HELD((layout->steps != 0u) && (layout->out_limbs != 0u) && (layout->members != 0u)
                        && (layout->members <= ENGINE_RECORD_MEMBERS_MAX),
                    layout, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        if (!CYCLE_HELD((request->in[member] != NULL) && (request->bodies[member] != 0ull)
                            && ((request->index != NULL) || (request->count <= request->bodies[member])),
                        &request->in[member], error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_REFUSED;
        }
    }
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        // a step wider than the host's exact integer cannot be held on the host
        if (!CYCLE_HELD(layout->step_table[at].limbs <= ANCHOR_EXACT_LIMBS, &layout->step_table[at], error,
                        ENGINE_ERROR_REQUEST))
        {
            return CYCLE_REFUSED;
        }
    }
    AnchorExactInteger *const file = (AnchorExactInteger *)malloc((size_t)layout->steps * sizeof(AnchorExactInteger));
    if (!CYCLE_HELD(file != NULL, layout, error, ENGINE_ERROR_RESOURCE))
    {
        return CYCLE_REFUSED;
    }
    int good = 1;
    for (unsigned long long lane = 0ull; good && (lane < request->count); lane += 1ull)
    {
        const unsigned int *atom[ENGINE_RECORD_MEMBERS_MAX];
        for (unsigned int member = 0u; member < layout->members; member += 1u)
        {
            const unsigned long long body = (request->index != NULL)
                                          ? (unsigned long long)request->index[(lane * layout->members) + member] : lane;
            // a lane whose index names a record past its member refuses the run, as the device's refused count does
            good = good && CYCLE_HELD(body < request->bodies[member], &request->bodies[member], error,
                                      ENGINE_ERROR_REQUEST);
            atom[member] = &request->in[member][(good ? body : 0ull) * layout->in_limbs[member]];
        }
        unsigned int *const record = &request->out[lane * layout->out_limbs];
        memset(record, 0, (size_t)layout->out_limbs * sizeof(unsigned int));
        for (unsigned int at = 0u; good && (at < layout->steps); at += 1u)
        {
            const DeviceRecordStep *const step = &layout->step_table[at];
            // a refused lane (a zero divisor, an inexact quotient) refuses the run, as the device's refused count does
            good = CYCLE_HELD(cycle_host_step(step, atom[step->member], layout->in_limbs[step->member], file,
                                              layout->table_values, &file[at]),
                              step, error, ENGINE_ERROR_REQUEST)
                && CYCLE_HELD(cycle_host_fits(&file[at], step->limbs), step, error, ENGINE_ERROR_REQUEST);
            if (good && (step->out_bits != 0u))
            {
                cycle_host_put(record, step->out_offset, step->out_bits, &file[at]);
            }
        }
    }
    free(file);
    return good ? (long)request->count : CYCLE_REFUSED;
}
