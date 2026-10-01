// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_self_program.cu: the self program built
#include "qasm_self_internal.h"

// Part p of e x, for an entry e and an amplitude x, is the sum over x's parts q of e's part qasm_self_entry_part[p][q]
// times x's part q, doubled where qasm_self_doubled[p][q] and negated where qasm_self_negated[p][q]. With r = sqrt2,
// (a + b r)(c + d r) = (ac + 2bd) + (ad + bc) r, and i^2 = -1 carries the imaginary halves' product into the real half.
static const unsigned int qasm_self_entry_part[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0u, 1u, 2u, 3u}, {1u, 0u, 3u, 2u}, {2u, 3u, 0u, 1u}, {3u, 2u, 1u, 0u}};
static const int qasm_self_doubled[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0, 1, 0, 1}, {0, 0, 0, 0}, {0, 1, 0, 1}, {0, 0, 0, 0}};
static const int qasm_self_negated[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0, 0, 1, 1}, {0, 0, 1, 1}, {0, 0, 0, 0}, {0, 0, 0, 0}};

// part p of a number: 0 the real rational, 1 the real sqrt2, 2 the imaginary rational, 3 the imaginary sqrt2
const QasmRational *qasm_self_part(const QasmNumber *value, unsigned int part)
{
    const QasmRational *const parts[QASM_SELF_PARTS] = {&value->real.rational, &value->real.sqrt2,
                                                        &value->imaginary.rational, &value->imaginary.sqrt2};
    return parts[part];
}

QasmRational *qasm_self_part_slot(QasmNumber *value, unsigned int part)
{
    QasmRational *const parts[QASM_SELF_PARTS] = {&value->real.rational, &value->real.sqrt2, &value->imaginary.rational,
                                                  &value->imaginary.sqrt2};
    return parts[part];
}

// appends one step and returns its number; once the list cannot grow it returns 0 and the list stays spent
unsigned int qasm_self_step(QasmSelfSteps *list, EngineRecordOperation operation, unsigned int left, unsigned int right,
                            unsigned int member)
{
    if ((list->spent == 0) && (list->count == list->capacity))
    {
        const unsigned int wanted = (list->capacity == 0u) ? 1024u : (list->capacity * 2u);
        // a doubling that wraps asks for less than it holds, and errors as a list that cannot grow; the count is
        // widened to size_t, which holds any unsigned int
        EngineRecordStep *const grown =
            (wanted > list->capacity)
                ? (EngineRecordStep *)realloc(list->steps, (size_t)wanted * sizeof(EngineRecordStep))
                : NULL;
        list->spent = (grown == NULL) ? 1 : 0;
        list->steps = (grown != NULL) ? grown : list->steps;
        list->capacity = (grown != NULL) ? wanted : list->capacity;
    }
    if (list->spent != 0)
    {
        return 0u;
    }
    const unsigned int step = list->count;
    list->steps[step].operation = operation;
    list->steps[step].left = left;
    list->steps[step].right = right;
    list->steps[step].member = member;
    list->count += 1u;
    return step;
}

// A magnitude of 2 or more as a register: one CONSTANT step up to 64 bits, and a wider one built a limb at a time from
// the top, times 2^32 and plus the next limb down.
static unsigned int qasm_self_constant(QasmSelfBuild *build, const AnchorExactInteger *magnitude)
{
    for (unsigned int at = 0u; at < build->constant_count; at += 1u)
    {
        if (anchor_exact_equal(&build->constant_value[at], magnitude) != 0)
        {
            return build->constant_step[at];
        }
    }
    unsigned int used = ANCHOR_EXACT_LIMBS;
    while ((used > 1u) && (magnitude->limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    unsigned int value = 0u;
    if (used <= 2u)
    {
        value = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[0],
                               (used == 2u) ? magnitude->limb[1] : 0u, 0u);
    }
    else
    {
        const unsigned int word = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, 0u, 1u, 0u);
        value = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[used - 1u], 0u, 0u);
        for (unsigned int limb = used - 1u; limb > 0u; limb -= 1u)
        {
            const unsigned int low =
                qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[limb - 1u], 0u, 0u);
            const unsigned int shifted = qasm_self_step(&build->list, ENGINE_RECORD_PRODUCT, value, word, 0u);
            value = qasm_self_step(&build->list, ENGINE_RECORD_SUM, shifted, low, 0u);
        }
    }
    if (build->constant_count < QASM_SELF_CONSTANTS_MAX)
    {
        build->constant_value[build->constant_count] = *magnitude;
        build->constant_step[build->constant_count] = value;
        build->constant_count += 1u;
    }
    return value;
}

// one term: the register times the coefficient's magnitude, or the register itself where that is 1
static unsigned int qasm_self_term(QasmSelfBuild *build, unsigned int source, const AnchorExactInteger *magnitude)
{
    if (anchor_exact_equal(magnitude, &qasm_self_one) != 0)
    {
        return source;
    }
    const unsigned int factor = qasm_self_constant(build, magnitude);
    return qasm_self_step(&build->list, ENGINE_RECORD_PRODUCT, source, factor, 0u);
}

// Part `part` of amplitude `target` on the floor being built: every nonzero term over the floor below, summed from the
// first, the first taken from zero where it is negative, and zero where no term reaches the part.
static unsigned int qasm_self_sum(QasmSelfBuild *build, unsigned int target, unsigned int part)
{
    const unsigned int amplitudes = build->amplitudes;
    int started = 0;
    unsigned int sum = build->zero;
    for (unsigned int source = 0u; source < amplitudes; source += 1u)
    {
        const AnchorExactInteger *const entry = &build->numerators[QASM_SELF_PARTS * ((source * amplitudes) + target)];
        for (unsigned int from = 0u; from < QASM_SELF_PARTS; from += 1u)
        {
            const AnchorExactInteger *const coefficient = &entry[qasm_self_entry_part[part][from]];
            const unsigned int below = build->below[(QASM_SELF_PARTS * source) + from];
            if ((coefficient->sign == 0) || (below == build->zero))
            {
                continue;
            }
            AnchorExactInteger magnitude = *coefficient;
            magnitude.sign = 1;
            if (qasm_self_doubled[part][from] != 0)
            {
                const AnchorExactStatus doubled = anchor_exact_add(&magnitude, &magnitude, &magnitude);
                build->over_width = build->over_width || (doubled != ANCHOR_EXACT_OK);
            }
            const int negative = (coefficient->sign < 0) != (qasm_self_negated[part][from] != 0);
            const unsigned int term = qasm_self_term(build, below, &magnitude);
            if (started == 0)
            {
                sum = negative ? qasm_self_step(&build->list, ENGINE_RECORD_DIFFERENCE, build->zero, term, 0u) : term;
                started = 1;
            }
            else
            {
                sum = qasm_self_step(&build->list, negative ? ENGINE_RECORD_DIFFERENCE : ENGINE_RECORD_SUM, sum, term,
                                     0u);
            }
        }
    }
    return sum;
}

// common = lcm(common, denominator), both positive
int qasm_self_lcm(AnchorExactInteger *common, const AnchorExactInteger *denominator, EngineError *error)
{
    AnchorExactInteger divisor;
    AnchorExactInteger share;
    return QASM_FITS(anchor_exact_gcd(common, denominator, &divisor), common, error) &&
           QASM_FITS(anchor_exact_divide_exact(denominator, &divisor, &share), common, error) &&
           QASM_FITS(anchor_exact_multiply(common, &share, common), common, error);
}

// a rational over a denominator it divides: its numerator times the denominator's share of it
int qasm_self_over(const QasmRational *value, const AnchorExactInteger *common, AnchorExactInteger *numerator,
                   EngineError *error)
{
    AnchorExactInteger share;
    return QASM_FITS(anchor_exact_divide_exact(common, &value->denominator, &share), value, error) &&
           QASM_FITS(anchor_exact_multiply(&value->numerator, &share, numerator), value, error);
}

// One gate as a floor: its columns from the dense port, its denominator, and every part of the floor above as the sum
// of the parts below times the integers its entries make over that denominator.
int qasm_self_floor(QasmSelfBuild *build, unsigned int qubits, const QasmExactGate *gate)
{
    EngineError *const error = build->error;
    const unsigned int amplitudes = build->amplitudes;
    QasmDense basis = {0u, NULL};
    int ok = (qasm_dense_alloc(&basis, qubits, error) == 0L);
    for (unsigned int source = 0u; ok && (source < amplitudes); source += 1u)
    {
        for (unsigned int target = 0u; target < amplitudes; target += 1u)
        {
            basis.amplitudes[target] = (target == source) ? qasm_number_one : qasm_number_zero;
        }
        ok = (qasm_dense_apply(&basis, gate, error) == 0L);
        for (unsigned int target = 0u; ok && (target < amplitudes); target += 1u)
        {
            build->columns[(source * amplitudes) + target] = basis.amplitudes[target];
        }
    }
    qasm_dense_release(&basis);
    AnchorExactInteger common = qasm_self_one;
    const unsigned int entries = amplitudes * amplitudes;
    for (unsigned int entry = 0u; ok && (entry < entries); entry += 1u)
    {
        for (unsigned int part = 0u; ok && (part < QASM_SELF_PARTS); part += 1u)
        {
            ok = qasm_self_lcm(&common, &qasm_self_part(&build->columns[entry], part)->denominator, error);
        }
    }
    for (unsigned int entry = 0u; ok && (entry < entries); entry += 1u)
    {
        for (unsigned int part = 0u; ok && (part < QASM_SELF_PARTS); part += 1u)
        {
            ok = qasm_self_over(qasm_self_part(&build->columns[entry], part), &common,
                                &build->numerators[(QASM_SELF_PARTS * entry) + part], error);
        }
    }
    build->constant_count = 0u;
    for (unsigned int target = 0u; ok && (target < amplitudes); target += 1u)
    {
        for (unsigned int part = 0u; part < QASM_SELF_PARTS; part += 1u)
        {
            build->built[(QASM_SELF_PARTS * target) + part] = qasm_self_sum(build, target, part);
        }
    }
    ok = ok && QASM_CHECK(build->over_width == 0, gate, error, ENGINE_ERROR_RESOURCE) &&
         QASM_CHECK(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE) &&
         QASM_FITS(anchor_exact_multiply(&build->denominator, &common, &build->denominator), gate, error);
    // the floor just built is the floor the next gate reads
    unsigned int *const below = build->below;
    build->below = build->built;
    build->built = below;
    return ok;
}

// the bits a magnitude uses, 0 for zero
unsigned int qasm_self_bits(const AnchorExactInteger *value)
{
    for (unsigned int limb = ANCHOR_EXACT_LIMBS; limb > 0u; limb -= 1u)
    {
        const uint32_t word = value->limb[limb - 1u];
        if (word != 0u)
        {
            unsigned int bits = 32u;
            while (((word >> (bits - 1u)) & 1u) == 0u)
            {
                bits -= 1u;
            }
            return (32u * (limb - 1u)) + bits;
        }
    }
    return 0u;
}

// a value as `bits` bits of two's complement at bit `offset` of a zeroed record: a negative value is its magnitude's
// complement plus one, the carry walking up from bit 0
void qasm_self_put(unsigned int *record, unsigned int offset, unsigned int bits, const AnchorExactInteger *value)
{
    const unsigned int negative = (value->sign < 0) ? 1u : 0u;
    unsigned int carry = negative;
    for (unsigned int at = 0u; at < bits; at += 1u)
    {
        const unsigned int limb = at >> 5u;
        const unsigned int magnitude_bit = (limb < ANCHOR_EXACT_LIMBS) ? ((value->limb[limb] >> (at & 31u)) & 1u) : 0u;
        const unsigned int flipped = magnitude_bit ^ negative;
        const unsigned int bit = flipped ^ carry;
        carry = flipped & carry;
        const unsigned int place = offset + at;
        record[place >> 5u] |= bit << (place & 31u);
    }
}
