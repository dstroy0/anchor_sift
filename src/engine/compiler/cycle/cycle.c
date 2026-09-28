// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle.h"
#include "exact_integer.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(ANCHOR_EXACT_LIMBS >= 2u, "cycle: a record constant is 64 bits and needs two limbs");

#define CYCLE_CHECK(condition_, evacaddr_, error_, kind_)                                                              \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_),  \
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
    const int negative =
        (step->operation == ENGINE_RECORD_XOR) ? (left_negative ^ right_negative) : (left_negative & right_negative);
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
        const unsigned int bit_value =
            (bit < (32u * ANCHOR_EXACT_LIMBS)) ? ((value->limb[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
        unsigned int written = bit_value;
        if (value->sign < 0)
        {
            const unsigned int flipped = (bit_value ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        record[to / 32u] |= written << (to % 32u);
    }
}

static int cycle_host_step(const DeviceRecordStep *step, const unsigned int *atom, unsigned int in_limbs,
                           const AnchorExactInteger *file, const unsigned int *tables, unsigned long long lane,
                           AnchorExactInteger *value)
{
    if (step->operation == ENGINE_RECORD_LANE)
    {
        anchor_exact_zero(value);
        value->limb[0] = (uint32_t)(lane & 0xFFFFFFFFull);
        value->limb[1] = (uint32_t)(lane >> 32u);
        cycle_host_settle(value, 1);
        return 1;
    }
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
        const unsigned int index =
            (step->index_bits >= 32u) ? source->limb[0] : (source->limb[0] & ((1u << step->index_bits) - 1u));
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
        AnchorExactInteger integer_part;
        return anchor_exact_divide(left, right, &integer_part, value) == ANCHOR_EXACT_OK;
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
        return CYCLE_ERROR;
    }
    EngineError *const error = request->error;
    const EngineRecordLayout *const layout = request->layout;
    if (!CYCLE_CHECK((layout != NULL) && (request->out != NULL), request, error, ENGINE_ERROR_REQUEST) ||
        !CYCLE_CHECK((layout->steps != 0u) && (layout->out_limbs != 0u) && (layout->members != 0u) &&
                         (layout->members <= ENGINE_RECORD_MEMBERS_MAX),
                     layout, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        if (!CYCLE_CHECK((request->in[member] != NULL) && (request->bodies[member] != 0ull) &&
                             ((request->index != NULL) || (request->count <= request->bodies[member]) ||
                              (request->bodies[member] == 1ull)),
                         &request->in[member], error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_ERROR;
        }
    }
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        // a step wider than the host's exact integer cannot be held on the host
        if (!CYCLE_CHECK(layout->step_table[at].limbs <= ANCHOR_EXACT_LIMBS, &layout->step_table[at], error,
                         ENGINE_ERROR_REQUEST))
        {
            return CYCLE_ERROR;
        }
    }
    AnchorExactInteger *const file = (AnchorExactInteger *)malloc((size_t)layout->steps * sizeof(AnchorExactInteger));
    if (!CYCLE_CHECK(file != NULL, layout, error, ENGINE_ERROR_RESOURCE))
    {
        return CYCLE_ERROR;
    }
    int ok = 1;
    for (unsigned long long lane = 0ull; ok && (lane < request->count); lane += 1ull)
    {
        const unsigned int *atom[ENGINE_RECORD_MEMBERS_MAX];
        for (unsigned int member = 0u; member < layout->members; member += 1u)
        {
            const unsigned long long body = (request->index != NULL)
                                                ? (unsigned long long)request->index[(lane * layout->members) + member]
                                                : ((request->bodies[member] == 1ull) ? 0ull : lane);
            // a lane whose index names a record past its member errors on the run, as the device's errored count does
            ok = ok &&
                 CYCLE_CHECK(body < request->bodies[member], &request->bodies[member], error, ENGINE_ERROR_REQUEST);
            atom[member] = &request->in[member][(ok ? body : 0ull) * layout->in_limbs[member]];
        }
        unsigned int *const record = &request->out[lane * layout->out_limbs];
        memset(record, 0, (size_t)layout->out_limbs * sizeof(unsigned int));
        for (unsigned int at = 0u; ok && (at < layout->steps); at += 1u)
        {
            const DeviceRecordStep *const step = &layout->step_table[at];
            // an errored lane (a zero divisor, an inexact quotient) errors on the run, as the device's errored count
            // does
            ok = CYCLE_CHECK(cycle_host_step(step, atom[step->member], layout->in_limbs[step->member], file,
                                             layout->table_values, lane, &file[at]),
                             step, error, ENGINE_ERROR_REQUEST) &&
                 CYCLE_CHECK(cycle_host_fits(&file[at], step->limbs), step, error, ENGINE_ERROR_REQUEST);
            if (ok && (step->out_bits != 0u))
            {
                cycle_host_put(record, step->out_offset, step->out_bits, &file[at]);
            }
        }
    }
    free(file);
    return ok ? (long)request->count : CYCLE_ERROR;
}

// 1 where a record's `bits` bits at `offset` are not all zero, as the device's cycle_latch_valid
static int cycle_host_latch_valid(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned int set_bits = 0u;
    for (unsigned int bit = offset; bit < (offset + bits);)
    {
        const unsigned int shift = bit % 32u;
        const unsigned int left = offset + bits - bit;
        const unsigned int taken = (left < (32u - shift)) ? left : (32u - shift);
        const unsigned int mask = (taken == 32u) ? 0xFFFFFFFFu : (((1u << taken) - 1u) << shift);
        set_bits |= record[bit / 32u] & mask;
        bit += taken;
    }
    return (set_bits != 0u) ? 1 : 0;
}

long cycle_record_latch_host(const CycleRecordLatchRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_ERROR;
    }
    EngineError *const error = request->error;
    if (!CYCLE_CHECK((request->records != NULL) && (request->first != NULL) && (request->count != 0ull) &&
                         (request->out_limbs != 0u) && (request->bits != 0u) &&
                         (((unsigned long long)request->offset + request->bits) <=
                          (32ull * (unsigned long long)request->out_limbs)),
                     request, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_ERROR;
    }
    unsigned long long first = CYCLE_LATCH_NONE;
    for (unsigned long long lane = 0ull; (first == CYCLE_LATCH_NONE) && (lane < request->count); lane += 1ull)
    {
        const unsigned int *const record = &request->records[lane * request->out_limbs];
        first = cycle_host_latch_valid(record, request->offset, request->bits) ? lane : CYCLE_LATCH_NONE;
    }
    *request->first = first;
    return (long)request->count;
}
